(local RuntimeScheduler (require :runtime-scheduler))
(local Temporal (require :temporal))

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn non-negative-ms-or-zero [value]
  (if (and (finite-number? value) (>= value 0))
      value
      0))

(fn duration-ms [value]
  (Temporal.duration.from {:nanoseconds (math.floor (+ (* value 1000000) 0.5))}))

(fn service-state []
  (if app.__runtime_timers
      app.__runtime_timers
      (do
        (set app.__runtime_timers {:scheduler (RuntimeScheduler.create)
                                   :update-handler nil
                                   :active-count 0
                                   :next-control-id 1
                                   :controls {}})
        app.__runtime_timers)))

(fn disconnect-update-handler [state]
  (when (and state.update-handler
             app.engine
             app.engine.events
             app.engine.events.updated)
    (app.engine.events.updated:disconnect state.update-handler true)
    (set state.update-handler nil)))

(fn ensure-update-handler [state]
  (when (and (<= state.active-count 0) state.update-handler)
    (disconnect-update-handler state))
  (when (and (> state.active-count 0)
             (not state.update-handler)
             app.engine
             app.engine.events
             app.engine.events.updated)
    (set state.update-handler
         (app.engine.events.updated:connect
           (fn [delta]
             (local elapsed (non-negative-ms-or-zero delta))
             (state.scheduler:update elapsed)
             (ensure-update-handler state))))))

(fn activate-control [control handle]
  (local state (service-state))
  (when control.active?
    (control:cancel))
  (set control.state state)
  (set control.handle handle)
  (set control.active? true)
  (set control.id state.next-control-id)
  (set state.next-control-id (+ state.next-control-id 1))
  (tset state.controls control.id control)
  (set state.active-count (+ state.active-count 1))
  (ensure-update-handler state)
  true)

(fn deactivate-control [control cancel-handle?]
  (when control.active?
    (local state control.state)
    (set control.active? false)
    (when (and cancel-handle? control.handle)
      (control.handle:cancel))
    (set control.handle nil)
    (when state
      (when control.id
        (tset state.controls control.id nil))
      (set state.active-count (math.max 0 (- state.active-count 1)))
      (ensure-update-handler state)))
  true)

(fn create-control []
  (local control {:state nil :id nil :active? false :handle nil})
  (fn cancel [_self]
    (deactivate-control control true))
  (tset control :cancel cancel)
  (tset control :drop cancel)
  control)

(fn clear []
  (local state (service-state))
  (state.scheduler:clear)
  (each [_id control (pairs state.controls)]
    (set control.active? false)
    (set control.handle nil))
  (set state.controls {})
  (set state.active-count 0)
  (disconnect-update-handler state)
  true)

(fn Timeout [opts]
  (local options (or opts {}))
  (local delay-ms (non-negative-ms-or-zero options.delay-ms))
  (local callback
    (assert options.callback "RuntimeTimers.Timeout requires :callback"))
  (local control (create-control))

  (fn start [_self]
    (control:cancel)
    (local state (service-state))
    (var handle nil)
    (set handle
         (state.scheduler:schedule-once
           {:delay (duration-ms delay-ms)
            :callback (fn []
                        (deactivate-control control false)
                        (callback))}))
    (activate-control control handle)
    true)

  {:start start
   :cancel control.cancel
   :drop control.drop})

(fn Interval [opts]
  (local options (or opts {}))
  (assert (and (finite-number? options.interval-ms)
               (> options.interval-ms 0))
          "RuntimeTimers.Interval requires positive :interval-ms")
  (local interval-ms options.interval-ms)
  (local callback
    (assert options.callback "RuntimeTimers.Interval requires :callback"))
  (local control (create-control))

  (fn start [_self]
    (control:cancel)
    (local state (service-state))
    (activate-control control
                      (state.scheduler:schedule-every {:interval (duration-ms interval-ms)
                                                       :callback callback}))
    true)

  {:start start
   :cancel control.cancel
   :drop control.drop})

(fn Debouncer [opts]
  (local options (or opts {}))
  (var delay-ms (non-negative-ms-or-zero options.delay-ms))
  (local callback
    (assert options.callback "RuntimeTimers.Debouncer requires :callback"))
  (local control (create-control))
  (var last-payload nil)

  (fn set-delay-ms [_self next-delay-ms]
    (assert (and (finite-number? next-delay-ms)
                 (>= next-delay-ms 0))
            "RuntimeTimers.Debouncer.set-delay-ms requires non-negative number")
    (set delay-ms next-delay-ms)
    true)

  (fn trigger [_self payload]
    (set last-payload payload)
    (control:cancel)
    (if (<= delay-ms 0)
        (callback last-payload)
        (do
          (local state (service-state))
          (var handle nil)
          (set handle
               (state.scheduler:schedule-once
                 {:delay (duration-ms delay-ms)
                  :callback (fn []
                              (local payload-to-send last-payload)
                              (deactivate-control control false)
                              (callback payload-to-send))}))
          (activate-control control handle)))
    true)

  {:trigger trigger
   :set-delay-ms set-delay-ms
   :cancel control.cancel
   :drop control.drop})

{:Timeout Timeout
 :Interval Interval
 :Debouncer Debouncer
 :clear clear}
