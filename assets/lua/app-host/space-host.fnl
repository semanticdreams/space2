(local Services (require :app-host.services))
(local SceneCapability (require :app-host.scene-capability))

(fn space-host-error [message]
  (error (.. "[space-host] " message)))

(fn remove-owned-child [owned child]
  (var removed? false)
  (for [i (# owned) 1 -1]
    (when (= (. owned i) child)
      (table.remove owned i)
      (set removed? true)))
  removed?)

(fn make-panel-adapter [label target]
  (local owned [])

  (fn require-method [method-name]
    (local method (. target method-name))
    (if (= (type method) :function)
        method
        (space-host-error (.. label " adapter requires target:" (tostring method-name)))))

  (fn add-panel-child [_self opts]
    (local add (require-method :add-panel-child))
    (local child (add target opts))
    (when child
      (table.insert owned child))
    child)

  (fn remove-panel-child [_self child]
    (local remove (require-method :remove-panel-child))
    (remove-owned-child owned child)
    (remove target child))

  (fn drop [_self]
    (when (> (# owned) 0)
      (local remove (require-method :remove-panel-child))
      (for [i (# owned) 1 -1]
        (local child (. owned i))
        (table.remove owned i)
        (remove target child)))
    nil)

  {:target target
   :add-panel-child add-panel-child
   :remove-panel-child remove-panel-child
   :drop drop
   :find-panel-persistence (fn [_self child]
                             (local find-persistence (require-method :find-panel-persistence))
                             (find-persistence target child))
   :capture-panel-element-state (fn [_self child]
                                  (local capture-state (require-method :capture-panel-element-state))
                                  (capture-state target child))
   :register-panel-restorer (fn [_self kind restorer owner]
                              (local register (require-method :register-panel-restorer))
                              (register target kind restorer owner))
   :unregister-panel-restorer (fn [_self kind owner]
                                (local unregister (require-method :unregister-panel-restorer))
                                (unregister target kind owner))})

(fn make-space-scene-capability [target]
  (local raw-children-by-handle {})

  (fn require-method [method-name]
    (local method (. target method-name))
    (if (= (type method) :function)
        method
        (space-host-error (.. "scene capability requires target:" (tostring method-name)))))

  (fn scene-height-at [_self point opts]
    (if (= (type target.height-at) :function)
        (target:height-at point opts)
        (= (type target.height-at-world-point) :function)
        (target:height-at-world-point point opts)
        nil))

  (fn scene-raycast-terrain [_self ray opts]
    (if (= (type target.raycast-terrain) :function)
        (target:raycast-terrain ray opts)
        nil))

  (fn scene-despawn [_self handle]
    (local child (. raw-children-by-handle handle))
    (when child
      (local remove (require-method :remove-panel-child))
      (remove target child)
      (set (. raw-children-by-handle handle) nil))
    nil)

  (local scene (SceneCapability.create {:backend {:despawn scene-despawn
                                                  :height-at scene-height-at
                                                  :raycast-terrain scene-raycast-terrain}}))
  (local base-spawn scene.spawn)
  (local base-despawn scene.despawn)

  (fn spawn [self spec]
    (local handle (base-spawn self spec))
    (when (= spec.kind :panel)
      (local add (require-method :add-panel-child))
      (local (ok child-or-error) (pcall add target spec))
      (when (not ok)
        (base-despawn self handle)
        (error child-or-error))
      (when (= child-or-error nil)
        (base-despawn self handle)
        (space-host-error "scene:add-panel-child returned nil for panel spawn"))
      (set (. raw-children-by-handle handle) child-or-error))
    handle)

  (set scene.spawn spawn)
  scene)

(fn resolve-shell [options]
  (if options.app
      options.app
      (if app
          app
          {})))

(fn resolve-viewport [options shell runtime]
  (if options.viewport
      options.viewport
      (if shell.viewport
          shell.viewport
          (if runtime.viewport
              runtime.viewport
              {:x 0 :y 0 :width 0 :height 0}))))

(fn resolve-engine [options shell]
  (if options.engine
      options.engine
      shell.engine))

(fn create [opts]
  (local options (if opts opts {}))
  (local runtime options.runtime)
  (when (not runtime)
    (space-host-error "create requires :runtime"))
  (local shell (resolve-shell options))
  (local scheduler (Services.make-scheduler options))
  (local input (Services.make-input options))
  (local adapters [])
  (var dropped? false)
  (var host nil)

  (fn add-adapter [name target]
    (when target
      (local adapter (make-panel-adapter (tostring name) target))
      (set (. host name) adapter)
      (table.insert adapters adapter)))

  (fn add-scene-capability [target]
    (when target
      (local scene (make-space-scene-capability target))
      (set host.scene scene)
      (table.insert adapters scene)))

  (fn quit [_self]
    (if options.on-quit
        (options.on-quit host)
        (space-host-error "lifecycle:quit requires on-quit callback")))

  (fn drop [_self]
    (when (not dropped?)
      (set dropped? true)
      (for [i (# adapters) 1 -1]
        (local adapter (. adapters i))
        (adapter:drop)
        (table.remove adapters i)))
    nil)

  (fn render-targets [_self]
    [])

  (set host {:runtime runtime
             :viewport (resolve-viewport options shell runtime)
             :surfaces (Services.make-registry "surfaces")
             :presentation {:render-targets render-targets}
             :scheduler scheduler
             :input input
             :inspectors (Services.make-registry "inspectors")
             :commands (Services.make-registry "commands")
             :assets (Services.make-assets {:engine (resolve-engine options shell)
                                             :asset-path-resolver options.asset-path-resolver})
             :logging (Services.make-logging options)
             :lifecycle {:quit quit}
             :drop drop})
  (add-adapter :hud shell.hud)
  (add-adapter :canvas shell.canvas)
  (add-scene-capability shell.scene)
  host)

{:create create}
