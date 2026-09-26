(local Presentation {})
(local Boundary (require :activity-surface-boundary))

(fn active-owned-target [target]
  (when (Boundary.target-owned-by-active? target)
    target))

(fn active-activity-context? []
  (Boundary.expected-owner-id))

(fn maybe-insert-target! [targets target]
  (when target
    (table.insert targets target))
  targets)

(fn insert-hosted-targets! [targets runtime]
  (local mounts (and runtime runtime.hosted-app-mounts))
  (when mounts
    (each [_ mount (ipairs mounts)]
      (when mount
        (local render-targets mount.render-targets)
        (when (not (= (type render-targets) :function))
          (error "hosted app mount requires render-targets function"))
        (each [_ target (ipairs (render-targets mount))]
          (maybe-insert-target! targets target)))))
  targets)

(fn Presentation.for-runtime [runtime]
  (local provider {})

  (fn provider.render-targets [self]
    (local targets [])
    ;; Scene target
    (when (and runtime runtime.scene runtime.scene.presentation-target)
      (maybe-insert-target! targets (active-owned-target (runtime.scene:presentation-target))))
    ;; Canvas target
    (when (and runtime runtime.canvas runtime.canvas.presentation-target)
      (maybe-insert-target! targets (active-owned-target (runtime.canvas:presentation-target))))
    ;; Hosted app workspace targets compose above scene/canvas and below HUD.
    (insert-hosted-targets! targets runtime)
    ;; HUD target (retained surface via app.hud)
    (when (and app app.hud app.hud.presentation-target)
      (maybe-insert-target! targets (app.hud:presentation-target)))
    targets)

  (fn provider.default-screen-ray-target [self opts]
    (local options (or opts {}))
    (or (when options.target
          (active-owned-target options.target))
        (when options.surface
          (if (= options.surface :scene)
              (when (and runtime runtime.scene runtime.scene.presentation-target)
                (active-owned-target (runtime.scene:presentation-target)))
              (= options.surface :canvas)
              (when (and runtime runtime.canvas runtime.canvas.presentation-target)
                (active-owned-target (runtime.canvas:presentation-target)))))
        (do
          (local active-surface (and app app.active-interaction-surface))
          (when active-surface
            (if (or (= active-surface :scene) (= active-surface "scene"))
                (when (and runtime runtime.scene runtime.scene.presentation-target)
                  (active-owned-target (runtime.scene:presentation-target)))
                (or (= active-surface :canvas) (= active-surface "canvas"))
                (when (and runtime runtime.canvas runtime.canvas.presentation-target)
                  (active-owned-target (runtime.canvas:presentation-target))))))))

  (fn provider.screen-pos-ray [self pos opts]
    (local target (self:default-screen-ray-target opts))
    (assert target "screen ray target is required: no render target with a camera is available")
    (assert target.screen-pos-ray
            "screen ray target does not support screen-pos-ray")
    (target:screen-pos-ray pos opts))

  (fn resolve-active-slot-controls [surface-key]
    "Return the controls stored for the currently active slot on the given surface."
    (local surface (and runtime runtime.activity-controls (. runtime.activity-controls surface-key)))
    (when surface
      (local slot-id (if (= surface-key :scene)
                         (and runtime runtime.scene runtime.scene.active-activity-slot-id)
                         (and runtime runtime.canvas runtime.canvas.active-activity-slot-id)))
      (when slot-id
        (. surface slot-id))))

  (fn provider.input-controls [self]
    (local surface-key (if (and app app.canvas-interactive?)
                           :canvas
                           :scene))
    (local slot-controls (resolve-active-slot-controls surface-key))
    (if (active-activity-context?)
        slot-controls
        (= surface-key :canvas)
        (if slot-controls
            slot-controls
            (if (and runtime runtime.canvas runtime.canvas.active-activity-slot-id)
                nil
                runtime.canvas-controls))
        (or slot-controls
            runtime.first-person-controls)))

  (fn provider.camera [self opts]
    (local options (or opts {}))
    (local target (self:default-screen-ray-target options))
    (if (and target target.camera)
        target.camera
        options.required?
        (error "presentation camera not available: no render target with a camera is available")
        nil))

  (fn provider.audio-listener-camera [self]
    (self:camera {:required? false}))

  (fn provider.update [self delta]
    true)

  provider)

Presentation
