(local Services (require :app-host.services))

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
  (add-adapter :scene shell.scene)
  host)

{:create create}
