(local tests [])
(local Temporal (require :temporal))
(local RuntimeScheduler (require :runtime-scheduler))

(fn assert-error-contains [f needle message]
  (local (ok err) (pcall f))
  (assert (not ok) message)
  (assert (string.find (tostring err) needle 1 true)
          (.. message ": expected " needle ", got " (tostring err))))

(fn duration-ms [ms]
  (Temporal.duration.from {:milliseconds ms}))

(fn fixed-clock [iso]
  (Temporal.clock.fixed (Temporal.instant.parse iso)))

(fn plain [text]
  (Temporal.plain-date-time.parse text))

(fn noop [_payload]
  nil)

(fn boom []
  (error "boom"))

(fn record-callback [calls value]
  (fn []
    (table.insert calls value)))

(fn schedule-once-fires-with-fixed-clock []
  (local scheduler (RuntimeScheduler.create {:clock (fixed-clock "2026-01-01T00:00:00Z")}))
  (local calls [])
  (scheduler:schedule-once {:delay (duration-ms 100)
                            :callback (record-callback calls "fired")})
  (scheduler:advance (duration-ms 99))
  (assert (= (length calls) 0) "one-shot should wait until due")
  (scheduler:advance (duration-ms 1))
  (assert (= (length calls) 1) "one-shot should fire when due")
  (scheduler:advance (duration-ms 100))
  (assert (= (length calls) 1) "one-shot should not fire twice"))

(fn interval-catches-up-in-deadline-order []
  (local scheduler (RuntimeScheduler.create {:clock (fixed-clock "2026-01-01T00:00:00Z")}))
  (local calls [])
  (scheduler:schedule-every {:interval (duration-ms 100)
                             :callback (record-callback calls "interval")})
  (scheduler:advance (duration-ms 350))
  (assert (= (length calls) 3) "interval should fire once per missed interval"))

(fn interval-catchup-recomputes-before-later-deadlines []
  (local scheduler (RuntimeScheduler.create {:clock (fixed-clock "2026-01-01T00:00:00Z")}))
  (local calls [])
  (scheduler:schedule-every {:interval (duration-ms 10)
                             :callback (record-callback calls "a")})
  (scheduler:schedule-once {:delay (duration-ms 30)
                            :callback (record-callback calls "b")})
  (scheduler:advance (duration-ms 30))
  (assert (= (# calls) 4) "interval catch-up and one-shot should all fire")
  (assert (= (. calls 1) "a") "first interval deadline should fire first")
  (assert (= (. calls 2) "a") "rescheduled earlier interval should fire before later one-shot")
  (assert (= (. calls 3) "a") "equal-deadline interval should keep creation-order priority")
  (assert (= (. calls 4) "b") "later-created equal-deadline one-shot should fire last"))

(fn equal-deadlines-fire-in-creation-order []
  (local scheduler (RuntimeScheduler.create {:clock (fixed-clock "2026-01-01T00:00:00Z")}))
  (local calls [])
  (scheduler:schedule-once {:delay (duration-ms 50) :callback (record-callback calls "a")})
  (scheduler:schedule-once {:delay (duration-ms 50) :callback (record-callback calls "b")})
  (scheduler:advance (duration-ms 50))
  (assert (= (. calls 1) "a") "first equal-deadline job should fire first")
  (assert (= (. calls 2) "b") "second equal-deadline job should fire second"))

(fn cancel-before-due-prevents-callback []
  (local scheduler (RuntimeScheduler.create))
  (local calls [])
  (local handle
    (scheduler:schedule-once {:delay (duration-ms 10)
                              :callback (record-callback calls "late")}))
  (handle:cancel)
  (scheduler:advance (duration-ms 10))
  (assert (= (length calls) 0) "cancelled one-shot should not fire")
  (assert (not (handle:active?)) "cancelled handle should report inactive"))

(fn interval-cancel-inside-callback-stops-catchup []
  (local scheduler (RuntimeScheduler.create))
  (local calls [])
  (var handle nil)
  (fn cancel-on-tick []
    (table.insert calls "tick")
    (handle:cancel))
  (set handle
    (scheduler:schedule-every {:interval (duration-ms 10)
                               :callback cancel-on-tick}))
  (scheduler:advance (duration-ms 50))
  (assert (= (length calls) 1) "interval cancellation should stop same-advance catch-up"))

(fn clear-inside-callback-stops-siblings []
  (local scheduler (RuntimeScheduler.create))
  (local calls [])
  (fn clear-after-first []
    (table.insert calls "first")
    (scheduler:clear))
  (scheduler:schedule-once {:delay (duration-ms 10)
                            :callback clear-after-first})
  (scheduler:schedule-once {:delay (duration-ms 10)
                            :callback (record-callback calls "second")})
  (scheduler:advance (duration-ms 10))
  (assert (= (length calls) 1) "clear from callback should stop siblings")
  (assert (= (. calls 1) "first") "first callback should be the one that cleared"))

(fn callback-error-propagates []
  (local scheduler (RuntimeScheduler.create))
  (scheduler:schedule-once {:delay (duration-ms 1)
                            :callback boom})
  (fn advance-one []
    (scheduler:advance (duration-ms 1)))
  (assert-error-contains advance-one
                         "boom"
                         "callback errors should propagate"))

(fn typed-api-rejects-legacy-keys []
  (local scheduler (RuntimeScheduler.create))
  (fn schedule-with-legacy-key []
    (scheduler:schedule-once {:delay-ms 1 :callback noop}))
  (assert-error-contains schedule-with-legacy-key
                         "unknown option"
                         "typed scheduler should reject delay-ms alias"))

(fn list-and-update-expose-active-jobs []
  (local scheduler (RuntimeScheduler.create))
  (local calls [])
  (local handle (scheduler:schedule-once {:delay (duration-ms 5)
                                          :callback (record-callback calls "done")}))
  (local jobs (scheduler:list))
  (assert (= (# jobs) 1) "list should return active job summaries")
  (assert (= (. jobs 1 :kind) :once) "list should include job kind")
  (assert (= (. jobs 1 :active?) true) "list should include active status")
  (scheduler:update 5)
  (assert (= (length calls) 1) "update should advance by milliseconds")
  (assert (not (handle:active?)) "one-shot handle should deactivate after firing"))

(fn recurrence-requires-zone-id []
  (local scheduler (RuntimeScheduler.create))
  (local recurrence-set
    (Temporal.recurrence-set.from {:dtstart (plain "2026-01-01T00:00:00")
                                   :rdates [(plain "2026-01-01T00:00:01")]}))
  (fn schedule-without-zone []
    (scheduler:schedule-recurrence {:recurrence-set recurrence-set
                                    :limit 1
                                    :callback noop}))
  (assert-error-contains schedule-without-zone
                         "zone-id"
                         "recurrence scheduling should require zone-id"))

(fn recurrence-fires-finite-occurrences-in-order-with-payload []
  (local scheduler (RuntimeScheduler.create {:clock (fixed-clock "2026-01-01T00:00:00Z")}))
  (local calls [])
  (local recurrence-set
    (Temporal.recurrence-set.from {:dtstart (plain "2026-01-01T00:00:00")
                                   :rdates [(plain "2026-01-01T00:00:01")
                                            (plain "2026-01-01T00:00:02")]}))
  (fn collect-payload [payload]
    (table.insert calls {:index payload.occurrence-index
                         :scheduled-at (payload.scheduled-at:to-string)}))
  (scheduler:schedule-recurrence {:recurrence-set recurrence-set
                                  :zone-id "UTC"
                                  :limit 2
                                  :callback collect-payload})
  (scheduler:advance (duration-ms 2000))
  (assert (= (# calls) 2) "recurrence should fire both due occurrences")
  (assert (= (. calls 1 :index) 1) "first recurrence payload should have index 1")
  (assert (= (. calls 1 :scheduled-at) "2026-01-01T00:00:01Z") "first recurrence scheduled-at should be public")
  (assert (= (. calls 2 :index) 2) "second recurrence payload should have index 2")
  (assert (= (. calls 2 :scheduled-at) "2026-01-01T00:00:02Z") "second recurrence scheduled-at should be public"))

(fn recurrence-scheduled-after-advance-keeps-absolute-deadline []
  (local scheduler (RuntimeScheduler.create {:clock (fixed-clock "2026-01-01T00:00:00Z")}))
  (local calls [])
  (local recurrence-set
    (Temporal.recurrence-set.from {:dtstart (plain "2026-01-01T00:00:00")
                                   :rdates [(plain "2026-01-01T00:00:02")]}))
  (scheduler:advance (duration-ms 1000))
  (scheduler:schedule-recurrence {:recurrence-set recurrence-set
                                  :zone-id "UTC"
                                  :limit 1
                                  :callback (fn [payload]
                                              (table.insert calls (payload.scheduled-at:to-string)))})
  (scheduler:advance (duration-ms 999))
  (assert (= (# calls) 0) "recurrence should wait until the absolute occurrence deadline")
  (scheduler:advance (duration-ms 1))
  (assert (= (# calls) 1) "recurrence should fire at absolute scheduler time")
  (assert (= (. calls 1) "2026-01-01T00:00:02Z") "recurrence should keep scheduled-at payload"))

(table.insert tests {:name "RuntimeScheduler one-shot fixed-clock fire"
                     :fn schedule-once-fires-with-fixed-clock})
(table.insert tests {:name "RuntimeScheduler interval catches up in deadline order"
                     :fn interval-catches-up-in-deadline-order})
(table.insert tests {:name "RuntimeScheduler interval catch-up recomputes before later deadlines"
                     :fn interval-catchup-recomputes-before-later-deadlines})
(table.insert tests {:name "RuntimeScheduler equal deadlines fire in creation order"
                     :fn equal-deadlines-fire-in-creation-order})
(table.insert tests {:name "RuntimeScheduler cancel before due prevents callback"
                     :fn cancel-before-due-prevents-callback})
(table.insert tests {:name "RuntimeScheduler interval cancel inside callback stops catchup"
                     :fn interval-cancel-inside-callback-stops-catchup})
(table.insert tests {:name "RuntimeScheduler clear inside callback stops siblings"
                     :fn clear-inside-callback-stops-siblings})
(table.insert tests {:name "RuntimeScheduler callback error propagates"
                     :fn callback-error-propagates})
(table.insert tests {:name "RuntimeScheduler typed API rejects legacy keys"
                     :fn typed-api-rejects-legacy-keys})
(table.insert tests {:name "RuntimeScheduler list and update expose active jobs"
                     :fn list-and-update-expose-active-jobs})
(table.insert tests {:name "RuntimeScheduler recurrence requires zone-id"
                     :fn recurrence-requires-zone-id})
(table.insert tests {:name "RuntimeScheduler recurrence fires finite occurrences in order with payload"
                     :fn recurrence-fires-finite-occurrences-in-order-with-payload})
(table.insert tests {:name "RuntimeScheduler recurrence scheduled after advance keeps absolute deadline"
                     :fn recurrence-scheduled-after-advance-keeps-absolute-deadline})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "runtime-scheduler" :tests tests})))

{:name "runtime-scheduler" :tests tests :main main}
