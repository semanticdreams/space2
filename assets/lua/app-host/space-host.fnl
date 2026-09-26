(local Services (require :app-host.services))
(local SceneCapability (require :app-host.scene-capability))
(local MathUtils (require :math-utils))

(local array->vec3 (. MathUtils :array->vec3))
(local array->quat (. MathUtils :array->quat))

(fn space-host-error [message]
  (error (.. "[space-host] " message)))

(fn remove-owned-child [owned child]
  (var removed? false)
  (for [i (# owned) 1 -1]
    (when (= (. owned i) child)
      (table.remove owned i)
      (set removed? true)))
  removed?)

(fn native-vec3 [value label]
  (if (= value nil)
      nil
      (and (= (type value) :table) value.x value.y value.z)
      value
      (= (type value) :table)
      (array->vec3 value)
      (space-host-error (.. label " must be a vector table"))))

(fn native-quat [value label]
  (if (= value nil)
      nil
      (and (= (type value) :table) value.w value.x value.y value.z)
      value
      (= (type value) :table)
      (array->quat value)
      (space-host-error (.. label " must be a quaternion table"))))

(fn clone-table [source]
  (when (not (= (type source) :table))
    (space-host-error "scene spawn spec must be a table"))
  (local out {})
  (each [key value (pairs source)]
    (set (. out key) value))
  out)

(fn native-scene-opts [spec]
  (local opts (clone-table spec))
  (set opts.position (native-vec3 spec.position "scene spawn position"))
  (set opts.rotation (native-quat spec.rotation "scene spawn rotation"))
  (set opts.size (native-vec3 spec.size "scene spawn size"))
  opts)

(fn native-point [point]
  (native-vec3 point "scene point"))

(fn native-ray [ray]
  (when (not (= (type ray) :table))
    (space-host-error "scene ray must be a table"))
  {:origin (native-vec3 ray.origin "scene ray origin")
   :direction (native-vec3 ray.direction "scene ray direction")})

(fn trim-array-to [items target-length]
  (when items
    (while (> (# items) target-length)
      (table.remove items))))

(fn capture-scene-arrays [target]
  (local entity target.entity)
  {:scene-children target.scene-children
   :scene-children-count (if target.scene-children (# target.scene-children) 0)
   :entity-children (and entity entity.children)
   :entity-children-count (if (and entity entity.children) (# entity.children) 0)})

(fn rollback-partial-scene-insertions [snapshot]
  (trim-array-to snapshot.scene-children snapshot.scene-children-count)
  (trim-array-to snapshot.entity-children snapshot.entity-children-count))

(fn supported-embedded-kind? [target spec]
  (local kind spec.kind)
  (if (= kind :panel)
      (= (type target.add-panel-child) :function)
      (= kind :custom)
      (and spec.object (= (type target.add-object) :function))
      (= kind :cube)
      (and spec.object (= (type target.add-object) :function))
      false))

(fn assert-supported-embedded-kind [target spec]
  (when (not (= (type spec) :table))
    (space-host-error "scene spawn spec must be a table"))
  (when (not (supported-embedded-kind? target spec))
    (space-host-error (.. "unsupported embedded scene spawn kind: " (tostring spec.kind)))))

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
    (local native (native-point point))
    (if (= (type target.height-at) :function)
        (target:height-at native opts)
        (= (type target.height-at-world-point) :function)
        (target:height-at-world-point native opts)
        nil))

  (fn scene-raycast-terrain [_self ray opts]
    (local native (native-ray ray))
    (if (= (type target.raycast-terrain) :function)
        (target:raycast-terrain native opts)
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
    (assert-supported-embedded-kind target spec)
    (local native-spec (native-scene-opts spec))
    (local handle (base-spawn self spec))
    (if (= spec.kind :panel)
        (do
          (local add (require-method :add-panel-child))
          (local snapshot (capture-scene-arrays target))
          (local (ok child-or-error) (pcall add target native-spec))
          (when (not ok)
            (rollback-partial-scene-insertions snapshot)
            (base-despawn self handle)
            (error child-or-error))
          (when (= child-or-error nil)
            (base-despawn self handle)
            (space-host-error "scene:add-panel-child returned nil for panel spawn"))
          (set (. raw-children-by-handle handle) child-or-error))
        (= spec.kind :custom)
        (do
          (local add-object (require-method :add-object))
          (local snapshot (capture-scene-arrays target))
          (local (ok child-or-error) (pcall add-object target spec.object native-spec))
          (when (not ok)
            (rollback-partial-scene-insertions snapshot)
            (base-despawn self handle)
            (error child-or-error))
          (when (= child-or-error nil)
            (base-despawn self handle)
            (space-host-error "scene:add-object returned nil for object spawn"))
          (set (. raw-children-by-handle handle) child-or-error))
        (= spec.kind :cube)
        (do
          (local add-object (require-method :add-object))
          (local snapshot (capture-scene-arrays target))
          (local (ok child-or-error) (pcall add-object target spec.object native-spec))
          (when (not ok)
            (rollback-partial-scene-insertions snapshot)
            (base-despawn self handle)
            (error child-or-error))
          (when (= child-or-error nil)
            (base-despawn self handle)
            (space-host-error "scene:add-object returned nil for object spawn"))
          (set (. raw-children-by-handle handle) child-or-error)))
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
