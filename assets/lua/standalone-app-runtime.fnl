(local HostedRuntime (require :hosted-app-runtime))

(fn host-error [message]
  (error (.. "[standalone-app-runtime] " message)))

(fn copy-list [items]
  (local out [])
  (each [_ item (ipairs items)]
    (table.insert out item))
  out)

(fn make-registry [label]
  (local items [])

  (fn register [_self item]
    (when (= item nil)
      (host-error (.. label ":register requires a facet")))
    (table.insert items item)
    item)

  (fn unregister [_self item]
    (var removed? false)
    (for [i (# items) 1 -1]
      (when (= (. items i) item)
        (table.remove items i)
        (set removed? true)))
    removed?)

  (fn list [_self]
    (copy-list items))

  (fn clear [_self]
    (for [i (# items) 1 -1]
      (table.remove items i))
    true)

  {:register register
   :unregister unregister
   :list list
   :clear clear})

(fn make-scheduler []
  (local registrations [])
  (var paused? false)

  (fn register [_self facet]
    (when (not (= (type facet) :table))
      (host-error "scheduler:register requires a facet table"))
    (table.insert registrations facet)
    facet)

  (fn unregister [_self facet]
    (var removed? false)
    (for [i (# registrations) 1 -1]
      (when (= (. registrations i) facet)
        (table.remove registrations i)
        (set removed? true)))
    removed?)

  (fn update [_self delta-ms]
    (when (not paused?)
      (each [_ facet (ipairs registrations)]
        (when (and facet (= (type facet.update) :function))
          (facet:update delta-ms))))
    true)

  (fn set-paused [_self next-paused]
    (set paused? (not (not next-paused)))
    paused?)

  (fn step [_self delta-ms]
    (each [_ facet (ipairs registrations)]
      (when (and facet (= (type facet.update) :function))
        (facet:update delta-ms)))
    true)

  (fn list [_self]
    (copy-list registrations))

  {:register register
   :unregister unregister
   :update update
   :set-paused set-paused
   :step step
   :list list})

(fn make-input []
  (local handlers [])

  (fn register [_self handler]
    (when (not (= (type handler) :table))
      (host-error "input:register requires a handler table"))
    (table.insert handlers handler)
    handler)

  (fn unregister [_self handler]
    (var removed? false)
    (for [i (# handlers) 1 -1]
      (when (= (. handlers i) handler)
        (table.remove handlers i)
        (set removed? true)))
    removed?)

  (fn dispatch [_self event-name payload]
    (each [_ handler (ipairs handlers)]
      (local cb (. handler event-name))
      (when (= (type cb) :function)
        (cb handler payload)))
    true)

  (fn list [_self]
    (copy-list handlers))

  {:register register
   :unregister unregister
   :dispatch dispatch
   :list list})

(fn make-assets [opts]
  (local options (if opts opts {}))
  (var resolver options.asset-path-resolver)
  (when (and (not resolver) options.engine options.engine.get-asset-path)
    (set resolver options.engine.get-asset-path))
  (when (and (not resolver) app app.engine app.engine.get-asset-path)
    (set resolver app.engine.get-asset-path))
  {:resolve (fn [_self path]
              (if resolver
                  (resolver path)
                  path))})

(fn make-logging []
  (local (ok logging) (pcall require :logging))
  (fn call-logger [level message]
    (if (and ok logging (= (type (. logging level)) :function))
        ((. logging level) message)
        nil))
  {:debug (fn [_self message] (call-logger :debug message))
   :info (fn [_self message] (call-logger :info message))
   :warn (fn [_self message] (call-logger :warn message))
   :error (fn [_self message] (call-logger :error message))})

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
  (local scheduler (make-scheduler))
  (local input (make-input))
  (local inspectors (make-registry "inspectors"))
  (local commands (make-registry "commands"))
  (local surfaces (make-registry "surfaces"))
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
      (options.renderers:on-viewport-changed viewport)))

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
   :assets (make-assets options)
   :logging (make-logging)
   :lifecycle {:disconnect (fn [_self]
                             (disconnect-all connections))}})

(fn load-module [opts]
  (if opts.module
      opts.module
      (do
        (local module-name opts.module-name)
        (if module-name
            (require module-name)
            (host-error "run requires :module or :module-name")))))

(fn run [opts]
  (local options (if opts opts {}))
  (local EngineModule (require :engine))
  (local AppBootstrap (require :app-bootstrap))
  (global app (if app app {}))
  (local engine-options (if options.engine-options options.engine-options {}))
  (local engine (EngineModule.Engine engine-options))
  (set app.engine engine)
  (local viewport (if options.viewport options.viewport (default-viewport)))
  (local renderers (AppBootstrap.init-renderers {:viewport viewport}))
  (local host (create-host {:engine engine
                            :renderers renderers
                            :viewport viewport
                            :asset-path-resolver options.asset-path-resolver}))
  (local controller (HostedRuntime.mount {:module (load-module options)
                                          :host host}))
  (set app.active-world-runtime (controller:runtime))

  (var cleanup-error nil)
  (fn note-cleanup-error [err]
    (when (not cleanup-error)
      (set cleanup-error err)))

  (fn cleanup-step [cb]
    (local (ok err) (pcall cb))
    (when (not ok)
      (note-cleanup-error err)))

  (fn drop-controller []
    (controller:drop))

  (fn disconnect-host []
    (host.lifecycle:disconnect))

  (fn drop-renderers []
    (when app.renderers
      (app.renderers:drop)
      (set app.renderers nil)))

  (fn clear-runtime []
    (set app.active-world-runtime nil))

  (fn shutdown-engine []
    (engine:shutdown))

  (fn cleanup []
    (cleanup-step drop-controller)
    (cleanup-step disconnect-host)
    (cleanup-step drop-renderers)
    (cleanup-step clear-runtime)
    (cleanup-step shutdown-engine)
    (when cleanup-error
      (error cleanup-error)))

  (when (not (engine:start))
    (local (_cleanup-ok _cleanup-err) (pcall cleanup))
    (host-error "engine failed to start"))
  (local (run-ok run-err) (pcall engine.run engine))
  (local (cleanup-ok cleanup-err) (pcall cleanup))
  (when (not run-ok)
    (error run-err))
  (when (not cleanup-ok)
    (error cleanup-err))
  nil)

{:create-host create-host
 :run run}
