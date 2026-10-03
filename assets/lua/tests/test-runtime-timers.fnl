(local tests [])
(local RuntimeTimers (require :runtime-timers))

(fn reset-timers []
  (RuntimeTimers.clear)
  (set app.__runtime_timers nil))

(fn runtime-timeout-fires-once []
  (reset-timers)
  (var calls 0)
  (local timer (RuntimeTimers.Timeout {:delay-ms 100
                                       :callback (fn []
                                                   (set calls (+ calls 1)))}))
  (timer:start)
  (app.engine.events.updated:emit 50)
  (assert (= calls 0) "Timeout should not fire before delay elapses")
  (app.engine.events.updated:emit 50)
  (assert (= calls 1) "Timeout should fire once after delay elapses")
  (app.engine.events.updated:emit 100)
  (assert (= calls 1) "Timeout should not fire again after completion"))

(fn runtime-interval-repeats-and-drops-cleanly []
  (reset-timers)
  (var calls 0)
  (local timer (RuntimeTimers.Interval {:interval-ms 100
                                        :callback (fn []
                                                    (set calls (+ calls 1)))}))
  (timer:start)
  (app.engine.events.updated:emit 250)
  (assert (= calls 2) "Interval should fire once per elapsed interval")
  (timer:drop))

(fn runtime-debouncer-resets-delay-and-uses-latest-payload []
  (reset-timers)
  (local payloads [])
  (local debouncer
    (RuntimeTimers.Debouncer {:delay-ms 100
                              :callback (fn [payload]
                                          (table.insert payloads payload))}))
  (debouncer:trigger "first")
  (app.engine.events.updated:emit 60)
  (debouncer:trigger "second")
  (app.engine.events.updated:emit 60)
  (assert (= (length payloads) 0)
          "Debouncer should wait for quiet period after the latest trigger")
  (app.engine.events.updated:emit 40)
  (assert (= (length payloads) 1) "Debouncer should fire once after quiet period")
  (assert (= (. payloads 1) "second") "Debouncer should use the latest payload")
  (debouncer:drop))

(fn runtime-interval-callback-can-drop-itself []
  (reset-timers)
  (var calls 0)
  (var timer nil)
  (set timer
       (RuntimeTimers.Interval {:interval-ms 100
                                :callback (fn []
                                            (set calls (+ calls 1))
                                            (timer:drop))}))
  (timer:start)
  (app.engine.events.updated:emit 250)
  (assert (= calls 1)
          "Self-dropping interval should stop after the first callback"))

(fn runtime-timeout-callback-can-clear-service []
  (reset-timers)
  (local calls [])
  (local timeout-a
    (RuntimeTimers.Timeout {:delay-ms 100
                            :callback (fn []
                                        (table.insert calls "a")
                                        (RuntimeTimers.clear))}))
  (local timeout-b
    (RuntimeTimers.Timeout {:delay-ms 100
                            :callback (fn []
                                        (table.insert calls "b"))}))
  (timeout-a:start)
  (timeout-b:start)
  (app.engine.events.updated:emit 100)
  (assert (= (length calls) 1)
          "Clearing from a callback should stop sibling timers in the same tick"))

(fn runtime-clear-prevents-later-engine-callbacks []
  (reset-timers)
  (var calls 0)
  (local timeout (RuntimeTimers.Timeout {:delay-ms 100
                                        :callback (fn []
                                                    (set calls (+ calls 1)))}))
  (timeout:start)
  (RuntimeTimers.clear)
  (app.engine.events.updated:emit 100)
  (assert (= calls 0)
          "RuntimeTimers.clear should cancel pending callbacks before later engine updates"))

(fn runtime-fractional-millisecond-values-remain-compatible []
  (reset-timers)
  (var timeout-calls 0)
  (local timeout (RuntimeTimers.Timeout {:delay-ms 0.5
                                        :callback (fn []
                                                    (set timeout-calls (+ timeout-calls 1)))}))
  (timeout:start)
  (app.engine.events.updated:emit 0.499)
  (assert (= timeout-calls 0) "Fractional timeout should not fire before exact delay")
  (app.engine.events.updated:emit 0.001)
  (assert (= timeout-calls 1) "Fractional timeout should fire at exact fractional delay")

  (var interval-calls 0)
  (local interval (RuntimeTimers.Interval {:interval-ms 16.6667
                                          :callback (fn []
                                                      (set interval-calls (+ interval-calls 1)))}))
  (interval:start)
  (app.engine.events.updated:emit 50.0001)
  (assert (= interval-calls 3) "Fractional interval should catch up using exact nanoseconds")
  (interval:drop)

  (local payloads [])
  (local debouncer (RuntimeTimers.Debouncer {:delay-ms 0.5
                                            :callback (fn [payload]
                                                        (table.insert payloads payload))}))
  (debouncer:trigger "fractional")
  (app.engine.events.updated:emit 0.5)
  (assert (= (length payloads) 1) "Fractional debouncer delay should schedule successfully")
  (assert (= (. payloads 1) "fractional") "Fractional debouncer should preserve payload"))

(fn runtime-timeout-restart-replaces-prior-handle []
  (reset-timers)
  (var calls 0)
  (local timer (RuntimeTimers.Timeout {:delay-ms 100
                                      :callback (fn []
                                                  (set calls (+ calls 1)))}))
  (timer:start)
  (app.engine.events.updated:emit 60)
  (timer:start)
  (app.engine.events.updated:emit 50)
  (assert (= calls 0) "Restarted timeout should replace the prior pending handle")
  (app.engine.events.updated:emit 50)
  (assert (= calls 1) "Restarted timeout should fire once after the replacement delay")
  (app.engine.events.updated:emit 100)
  (assert (= calls 1) "Restarted timeout should still be one-shot"))

(fn runtime-cancel-and-drop-are-idempotent []
  (reset-timers)
  (var timeout-calls 0)
  (local timeout (RuntimeTimers.Timeout {:delay-ms 25
                                        :callback (fn []
                                                    (set timeout-calls (+ timeout-calls 1)))}))
  (timeout:start)
  (timeout:cancel)
  (timeout:cancel)
  (timeout:drop)
  (app.engine.events.updated:emit 25)
  (assert (= timeout-calls 0) "Repeated timeout cancel/drop should keep callback canceled")

  (timeout:start)
  (app.engine.events.updated:emit 25)
  (assert (= timeout-calls 1) "Timeout should fire once after restarting from canceled state")
  (timeout:cancel)
  (timeout:drop)

  (var interval-calls 0)
  (local interval (RuntimeTimers.Interval {:interval-ms 10
                                          :callback (fn []
                                                      (set interval-calls (+ interval-calls 1)))}))
  (interval:start)
  (RuntimeTimers.clear)
  (interval:drop)
  (interval:cancel)
  (app.engine.events.updated:emit 30)
  (assert (= interval-calls 0) "Repeated drop/cancel after clear should remain safe and inactive"))

(fn runtime-zero-delay-debouncer-fires-synchronously []
  (reset-timers)
  (local payloads [])
  (local debouncer (RuntimeTimers.Debouncer {:delay-ms 0
                                            :callback (fn [payload]
                                                        (table.insert payloads payload))}))
  (debouncer:trigger "first")
  (assert (= (length payloads) 1) "Zero-delay debouncer should fire during trigger")
  (assert (= (. payloads 1) "first") "Zero-delay debouncer should use current payload")
  (debouncer:trigger "second")
  (assert (= (length payloads) 2) "Zero-delay debouncer should fire each trigger synchronously")
  (assert (= (. payloads 2) "second") "Zero-delay debouncer should use latest payload synchronously"))

(table.insert tests {:name "RuntimeTimers timeout fires once" :fn runtime-timeout-fires-once})
(table.insert tests {:name "RuntimeTimers interval repeats and drops cleanly"
                     :fn runtime-interval-repeats-and-drops-cleanly})
(table.insert tests {:name "RuntimeTimers debouncer resets delay and uses latest payload"
                     :fn runtime-debouncer-resets-delay-and-uses-latest-payload})
(table.insert tests {:name "RuntimeTimers interval callback can drop itself"
                     :fn runtime-interval-callback-can-drop-itself})
(table.insert tests {:name "RuntimeTimers timeout callback can clear service"
                      :fn runtime-timeout-callback-can-clear-service})
(table.insert tests {:name "RuntimeTimers clear prevents later engine callbacks"
                      :fn runtime-clear-prevents-later-engine-callbacks})
(table.insert tests {:name "RuntimeTimers accepts fractional millisecond compatibility values"
                     :fn runtime-fractional-millisecond-values-remain-compatible})
(table.insert tests {:name "RuntimeTimers timeout restart replaces prior handle"
                     :fn runtime-timeout-restart-replaces-prior-handle})
(table.insert tests {:name "RuntimeTimers cancel and drop are idempotent"
                     :fn runtime-cancel-and-drop-are-idempotent})
(table.insert tests {:name "RuntimeTimers zero-delay debouncer fires synchronously"
                     :fn runtime-zero-delay-debouncer-fires-synchronously})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "runtime-timers"
                       :tests tests})))

{:main main}
