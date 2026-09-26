(local HostedRuntime (require :hosted-app-runtime))
(local SceneCapability (require :app-host.scene-capability))
(local Services (require :app-host.services))

(fn host-error [message]
  (error (.. "[standalone-app-runtime] " message)))

(fn default-viewport []
  {:x 0 :y 0 :width 800 :height 600})

(fn connect-signal [connections signal handler]
  (when (and signal signal.connect)
    (local token (signal:connect handler))
    (table.insert connections {:signal signal :token token})))

(fn disconnect-all [connections]
  (for [i (# connections) 1 -1]
    (local connection (. connections i))
    (when (and connection connection.signal connection.signal.disconnect connection.token)
      (connection.signal:disconnect connection.token true))
    (table.remove connections i))
  true)

(fn create-host [opts]
  (local options (if opts opts {}))
  (local viewport (if options.viewport options.viewport (default-viewport)))
  (local scheduler (Services.make-scheduler))
  (local input (Services.make-input))
  (local inspectors (Services.make-registry "inspectors"))
  (local commands (Services.make-registry "commands"))
  (local surfaces (Services.make-registry "surfaces"))
  (local connections [])
  (local engine options.engine)

  (fn handle-resize [payload]
    (when payload
      (when (not (= payload.x nil))
        (set viewport.x payload.x))
      (when (not (= payload.y nil))
        (set viewport.y payload.y))
      (when (not (= payload.width nil))
        (set viewport.width payload.width))
      (when (not (= payload.height nil))
        (set viewport.height payload.height)))
    (when (and options.renderers options.renderers.on-viewport-changed)
      (options.renderers:on-viewport-changed viewport))
    (when app
      (set app.viewport viewport)))

  (fn quit [_self]
    (if (and engine (= (type engine.quit) :function))
        (engine:quit)
        (host-error "lifecycle:quit requires engine quit method")))

  (when (and engine engine.events)
    (connect-signal connections engine.events.updated
                    (fn [delta-ms]
                      (scheduler:update delta-ms)
                      (when (and options.renderers options.renderers.update)
                        (options.renderers:update))))
    (connect-signal connections engine.events.window-resized handle-resize)
    (each [_ spec (ipairs [[:key-down :key-down]
                           [:key-up :key-up]
                           [:text-input :text-input]
                           [:mouse-button-down :mouse-button-down]
                           [:mouse-button-up :mouse-button-up]
                           [:mouse-motion :mouse-motion]
                           [:mouse-wheel :mouse-wheel]])]
      (local signal-name (. spec 1))
      (local event-name (. spec 2))
      (connect-signal connections (. engine.events signal-name)
                      (fn [payload]
                        (input:dispatch event-name payload)))))

  {:viewport viewport
   :surfaces surfaces
   :presentation {:render-targets (fn [_self]
                                    [])}
   :scheduler scheduler
   :input input
   :inspectors inspectors
   :commands commands
   :assets (Services.make-assets options)
   :logging (Services.make-logging)
   :scene (SceneCapability.create {:backend options.scene-backend})
   :lifecycle {:quit quit
               :disconnect (fn [_self]
                              (disconnect-all connections))}})

(fn load-module [opts]
  (if opts.module
      opts.module
      (do
        (local module-name opts.module-name)
        (if module-name
            (require module-name)
            (host-error "run requires :module or :module-name")))))

(fn failure-message [phase primary-error cleanup-error]
  (if cleanup-error
      (.. "[standalone-app-runtime] " phase " failed: " (tostring primary-error)
          "; cleanup failed: " (tostring cleanup-error))
      (tostring primary-error)))

(fn run [opts]
  (local options (if opts opts {}))
  (local EngineModule (if options.engine-module options.engine-module (require :engine)))
  (local AppBootstrap (if options.bootstrap-module options.bootstrap-module (require :app-bootstrap)))
  (global app (if app app {}))
  (local previous-engine app.engine)
  (local previous-renderers app.renderers)
  (local previous-viewport app.viewport)
  (local previous-runtime app.active-world-runtime)
  (local engine-options (if options.engine-options options.engine-options {}))
  (local engine (EngineModule.Engine engine-options))
  (set app.engine engine)
  (local viewport (if options.viewport options.viewport (default-viewport)))
  (var renderers nil)
  (var host nil)
  (var controller nil)

  (var cleanup-error nil)
  (fn note-cleanup-error [err]
    (when (not cleanup-error)
      (set cleanup-error err)))

  (fn cleanup-step [cb]
    (local (ok err) (pcall cb))
    (when (not ok)
      (note-cleanup-error err)))

  (fn drop-controller []
    (when controller
      (controller:drop)))

  (fn disconnect-host []
    (when (and host host.lifecycle host.lifecycle.disconnect)
      (host.lifecycle:disconnect)))

  (fn drop-renderers []
    (local dropped-renderers renderers)
    (var drop-error nil)
    (when renderers
      (local (ok err) (pcall #(renderers:drop)))
      (when (not ok)
        (set drop-error err))
      (set renderers nil))
    (when (and app.renderers
               (not (= app.renderers previous-renderers))
               (not (= app.renderers dropped-renderers)))
      (local (ok err) (pcall #(app.renderers:drop)))
      (when (and (not ok) (not drop-error))
        (set drop-error err)))
    (set app.renderers previous-renderers)

    (when drop-error
      (error drop-error)))

  (fn clear-viewport []
    (set app.viewport previous-viewport))

  (fn clear-runtime []
    (set app.active-world-runtime previous-runtime))

  (fn clear-engine []
    (when (= app.engine engine)
      (set app.engine previous-engine)))

  (fn shutdown-engine []
    (engine:shutdown))

  (fn cleanup []
    (cleanup-step drop-controller)
    (cleanup-step disconnect-host)
    (cleanup-step drop-renderers)
    (cleanup-step clear-viewport)
    (cleanup-step clear-runtime)
    (cleanup-step shutdown-engine)
    (cleanup-step clear-engine)
    (when cleanup-error
      (error cleanup-error)))

  (local (setup-ok setup-err)
    (pcall
      (fn []
        (when (not (engine:start))
          (host-error "engine failed to start"))
        (set app.viewport viewport)
        (set renderers (AppBootstrap.init-renderers {:viewport viewport}))
         (set host (create-host {:engine engine
                                 :renderers renderers
                                 :viewport viewport
                                 :scene-backend options.scene-backend
                                 :asset-path-resolver options.asset-path-resolver}))
        (set controller (HostedRuntime.mount {:module (load-module options)
                                              :host host}))
        (set app.active-world-runtime (controller:runtime)))))
  (when (not setup-ok)
    (local (cleanup-ok cleanup-err) (pcall cleanup))
    (error (failure-message "setup" setup-err (and (not cleanup-ok) cleanup-err))))
  (local (run-ok run-err) (pcall engine.run engine))
  (local (cleanup-ok cleanup-err) (pcall cleanup))
  (when (not run-ok)
    (error (failure-message "run" run-err (and (not cleanup-ok) cleanup-err))))
  (when (not cleanup-ok)
    (error cleanup-err))
  nil)

{:create-host create-host
 :run run}
