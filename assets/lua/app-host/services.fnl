(fn service-error [message]
  (error (.. "[app-host.services] " message)))

(fn copy-list [items]
  (local out [])
  (each [_ item (ipairs items)]
    (table.insert out item))
  out)

(fn make-registry [label]
  (local items [])

  (fn register [_self item]
    (when (= item nil)
      (service-error (.. label ":register requires a facet")))
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

(fn make-scheduler [_opts]
  (local registrations [])
  (var paused? false)

  (fn register [_self facet]
    (when (not (= (type facet) :table))
      (service-error "scheduler:register requires a facet table"))
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

(fn make-input [_opts]
  (local handlers [])

  (fn register [_self handler]
    (when (not (= (type handler) :table))
      (service-error "input:register requires a handler table"))
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

(fn make-logging [_opts]
  (local (ok logging) (pcall require :logging))
  (fn call-logger [level message]
    (if (and ok logging (= (type (. logging level)) :function))
        ((. logging level) message)
        nil))
  {:debug (fn [_self message] (call-logger :debug message))
   :info (fn [_self message] (call-logger :info message))
   :warn (fn [_self message] (call-logger :warn message))
   :error (fn [_self message] (call-logger :error message))})

{:copy-list copy-list
 :make-registry make-registry
 :make-scheduler make-scheduler
 :make-input make-input
 :make-assets make-assets
 :make-logging make-logging}
