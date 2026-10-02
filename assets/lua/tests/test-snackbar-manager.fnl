(local tests [])
(local SnackbarManager (require :snackbar-manager))
(local RuntimeTimers (require :runtime-timers))

(fn reset-timers []
  (RuntimeTimers.clear)
  (set app.__runtime_timers nil))

(fn entry-ids [entries]
  (local ids [])
  (each [_ entry (ipairs entries)]
    (table.insert ids entry.id))
  ids)

(fn assert-ids [entries expected message]
  (local ids (entry-ids entries))
  (assert (= (length ids) (length expected))
          (.. message " length expected " (length expected) " got " (length ids)))
  (each [idx id (ipairs expected)]
    (assert (= (. ids idx) id)
            (.. message " at " idx " expected " id " got " (tostring (. ids idx))))))

(fn timer-count []
  (var count 0)
  (when app.__runtime_timers
    (each [_ _timer (pairs app.__runtime_timers.timers)]
      (set count (+ count 1))))
  count)

(fn assert-error-contains [body expected]
  (local (ok err) (pcall body))
  (assert (not ok) "Expected function to fail")
  (assert (and (= (type err) :string)
               (string.find err expected 1 true))
          (.. "Expected error to contain '" expected "', got '" (tostring err) "'")))

(fn show-requires-content []
  (local manager (SnackbarManager))
  (assert-error-contains
    (fn []
      (manager:show {}))
    "SnackbarManager.show requires :text, :message, or :content-builder")
  (manager:drop))

(fn message-normalizes-to-text []
  (local manager (SnackbarManager))
  (local handle (manager:show {:message "Saved"}))
  (assert (= handle.entry.text "Saved") "message should normalize to entry.text")
  (manager:drop))

(fn explicit-id-is-preserved []
  (local manager (SnackbarManager))
  (local handle (manager:show {:id "custom" :text "Saved"}))
  (assert (= handle.id "custom") "handle.id should preserve explicit id")
  (assert (= handle.entry.id "custom") "entry.id should preserve explicit id")
  (manager:drop))

(fn generated-ids-are-stable-strings []
  (local manager (SnackbarManager))
  (local first (manager:show {:text "First"}))
  (local second (manager:show {:text "Second"}))
  (assert (= first.id "snackbar-1") "first generated id should be snackbar-1")
  (assert (= second.id "snackbar-2") "second generated id should be snackbar-2")
  (manager:drop))

(fn duplicate-explicit-id-is-rejected []
  (local manager (SnackbarManager))
  (manager:show {:id "custom" :text "First"})
  (assert-error-contains
    (fn []
      (manager:show {:id "custom" :text "Second"}))
    "SnackbarManager.show duplicate live id: custom")
  (assert (= (length (manager:visible-entries)) 1) "duplicate id should not add another visible entry")
  (manager:drop))

(fn text-snackbar-preserves-action-descriptors []
  (local manager (SnackbarManager))
  (local clicked (fn [_entry _handle _button _event] true))
  (local request-action {:label "Undo"
                         :button-variant :text
                         :on-click clicked})
  (local handle (manager:show {:text "Saved"
                               :actions [request-action]}))
  (local action (. handle.entry.actions 1))
  (assert (= handle.entry.text "Saved") "entry text should be preserved with actions")
  (assert (= (length handle.entry.actions) 1) "entry should preserve one action descriptor")
  (assert (= action.label "Undo") "action label should be preserved")
  (assert (= action.button-variant :text) "action button variant should be preserved")
  (assert (= action.on-click clicked) "action callback should be preserved")
  (assert (not (= action request-action)) "action descriptor should be copied")
  (set request-action.label "Changed")
  (assert (= action.label "Undo") "entry action should not change when request action mutates")
  (local visible-action (. (. (. (manager:visible-entries) 1) :actions) 1))
  (assert (= visible-action.label "Undo") "visible entries should include copied actions for hosts")
  (manager:drop))

(fn newest-first-visible-ordering []
  (local manager (SnackbarManager {:max-visible 3}))
  (manager:show {:id "one" :text "One" :persistent? true})
  (manager:show {:id "two" :text "Two" :persistent? true})
  (manager:show {:id "three" :text "Three" :persistent? true})
  (assert-ids (manager:visible-entries) ["three" "two" "one"]
              "visible entries should default to newest-first")
  (manager:drop))

(fn max-visible-queues-and-promotes-after-dismiss []
  (local manager (SnackbarManager {:max-visible 1 :max-queued 2}))
  (manager:show {:id "visible" :text "Visible" :persistent? true})
  (manager:show {:id "queued" :text "Queued" :persistent? true})
  (assert-ids (manager:visible-entries) ["visible"] "first entry should remain visible")
  (assert-ids (manager:queued-entries) ["queued"] "second entry should queue")
  (manager:dismiss "visible")
  (assert-ids (manager:visible-entries) ["queued"] "queued entry should promote after dismiss")
  (assert-ids (manager:queued-entries) [] "queue should be empty after promotion")
  (manager:drop))

(fn max-queued-drops-second-overflow []
  (local manager (SnackbarManager {:max-visible 1 :max-queued 1}))
  (manager:show {:id "visible" :text "Visible" :persistent? true})
  (local queued (manager:show {:id "queued" :text "Queued" :persistent? true}))
  (local dropped (manager:show {:id "dropped" :text "Dropped" :persistent? true}))
  (assert (not queued.dropped?) "first queued overflow should stay queued")
  (assert dropped.dropped? "second queued overflow should return a dropped handle")
  (assert (= dropped.drop-reason :queue-full) "drop reason should be queue-full")
  (assert-ids (manager:queued-entries) ["queued"] "queue should preserve the first queued entry")
  (manager:drop))

(fn priority-order-sorts-by-priority-then-newest []
  (local manager (SnackbarManager {:max-visible 4 :max-queued 3 :priority-order? true}))
  (manager:show {:id "low" :text "Low" :priority 1 :persistent? true})
  (manager:show {:id "tie-old" :text "Tie old" :priority 5 :persistent? true})
  (manager:show {:id "high" :text "High" :priority 10 :persistent? true})
  (manager:show {:id "tie-new" :text "Tie new" :priority 5 :persistent? true})
  (manager:show {:id "queued-low" :text "Queued low" :priority 1 :persistent? true})
  (manager:show {:id "queued-high" :text "Queued high" :priority 10 :persistent? true})
  (assert-ids (manager:visible-entries) ["high" "tie-new" "tie-old" "low"]
              "priority visible entries should sort by priority then newest")
  (assert-ids (manager:queued-entries) ["queued-high" "queued-low"]
              "priority queued entries should sort by priority then newest")
  (manager:drop))

(fn replace-key-replaces-visible-and-queued []
  (local manager (SnackbarManager {:max-visible 1 :max-queued 2}))
  (local first (manager:show {:id "first" :text "First" :replace-key "save" :persistent? true}))
  (local replacement (manager:show {:id "replacement" :text "Replacement" :replace-key "save" :persistent? true}))
  (assert first.dropped? "visible replace-key target should be dropped")
  (assert (= first.drop-reason :replaced) "visible replace-key target should be marked replaced")
  (assert-ids (manager:visible-entries) ["replacement"] "replacement should be visible")
  (local queued (manager:show {:id "queued" :text "Queued" :replace-key "queued" :persistent? true}))
  (local queued-replacement (manager:show {:id "queued-replacement" :text "Queued replacement" :replace-key "queued" :persistent? true}))
  (assert queued.dropped? "queued replace-key target should be dropped")
  (assert (= queued.drop-reason :replaced) "queued replace-key target should be marked replaced")
  (assert (not queued-replacement.dropped?) "queued replacement should stay live")
  (assert-ids (manager:queued-entries) ["queued-replacement"] "queued replacement should replace queued target")
  (manager:drop))

(fn drop-overflow-mode-drops-when-visible-full []
  (local manager (SnackbarManager {:max-visible 1 :overflow-mode :drop}))
  (manager:show {:id "visible" :text "Visible" :persistent? true})
  (local dropped (manager:show {:id "dropped" :text "Dropped" :persistent? true}))
  (assert dropped.dropped? "drop overflow mode should return a dropped handle")
  (assert (= dropped.drop-reason :visible-full) "drop overflow mode should mark visible-full")
  (assert-ids (manager:visible-entries) ["visible"] "visible entry should be unchanged")
  (manager:drop))

(fn replace-overflow-mode-replaces-oldest-visible []
  (local manager (SnackbarManager {:max-visible 2 :overflow-mode :replace}))
  (local oldest (manager:show {:id "oldest" :text "Oldest" :persistent? true}))
  (manager:show {:id "middle" :text "Middle" :persistent? true})
  (manager:show {:id "newest" :text "Newest" :persistent? true})
  (assert oldest.dropped? "replace overflow mode should drop oldest visible entry")
  (assert (= oldest.drop-reason :replaced) "replaced visible entry should be marked replaced")
  (assert-ids (manager:visible-entries) ["newest" "middle"] "newest replacement should be visible")
  (manager:drop))

(fn queued-entry-starts-timer-only-after-promotion []
  (reset-timers)
  (local manager (SnackbarManager {:max-visible 1}))
  (manager:show {:id "first" :text "First" :duration-ms 100})
  (manager:show {:id "second" :text "Second" :duration-ms 100})
  (assert (= (timer-count) 1) "only visible entry should have a timer")
  (app.engine.events.updated:emit 100)
  (assert-ids (manager:visible-entries) ["second"] "second entry should promote after first timeout")
  (assert (= (timer-count) 1) "promoted queued entry should start its timer")
  (app.engine.events.updated:emit 99)
  (assert-ids (manager:visible-entries) ["second"] "promoted entry should not expire before its own duration")
  (app.engine.events.updated:emit 1)
  (assert-ids (manager:visible-entries) [] "promoted entry should expire after its own duration")
  (manager:drop)
  (RuntimeTimers.clear)
  (set app.__runtime_timers nil))

(fn persistent-entry-does-not-auto-dismiss []
  (reset-timers)
  (local manager (SnackbarManager))
  (manager:show {:id "persistent" :text "Persistent" :duration-ms 100 :persistent? true})
  (assert (= (timer-count) 0) "persistent entry should not start a timer")
  (app.engine.events.updated:emit 1000)
  (assert-ids (manager:visible-entries) ["persistent"] "persistent entry should remain visible")
  (manager:drop)
  (RuntimeTimers.clear)
  (set app.__runtime_timers nil))

(fn drop-cancels-timers-and-blocks-later-use []
  (reset-timers)
  (local manager (SnackbarManager))
  (manager:show {:id "timed" :text "Timed" :duration-ms 100})
  (assert (= (timer-count) 1) "timed entry should start a timer")
  (manager:drop)
  (assert (= (timer-count) 0) "drop should cancel runtime timers")
  (assert (= app.__runtime_timers.update-handler nil) "drop should disconnect runtime timer handler")
  (assert-error-contains (fn [] (manager:show {:text "Late"})) "SnackbarManager is dropped")
  (assert-error-contains (fn [] (manager:dismiss "timed")) "SnackbarManager is dropped")
  (assert-error-contains (fn [] (manager:clear)) "SnackbarManager is dropped")
  (RuntimeTimers.clear)
  (set app.__runtime_timers nil))

(table.insert tests {:name "SnackbarManager.show requires content"
                     :fn show-requires-content})
(table.insert tests {:name "SnackbarManager normalizes message to text"
                     :fn message-normalizes-to-text})
(table.insert tests {:name "SnackbarManager preserves explicit ids"
                     :fn explicit-id-is-preserved})
(table.insert tests {:name "SnackbarManager generates stable string ids"
                      :fn generated-ids-are-stable-strings})
(table.insert tests {:name "SnackbarManager rejects duplicate explicit ids"
                     :fn duplicate-explicit-id-is-rejected})
(table.insert tests {:name "SnackbarManager preserves text action descriptors"
                      :fn text-snackbar-preserves-action-descriptors})
(table.insert tests {:name "SnackbarManager orders visible entries newest-first"
                     :fn newest-first-visible-ordering})
(table.insert tests {:name "SnackbarManager queues overflow and promotes after dismiss"
                     :fn max-visible-queues-and-promotes-after-dismiss})
(table.insert tests {:name "SnackbarManager drops queued overflow when queue is full"
                     :fn max-queued-drops-second-overflow})
(table.insert tests {:name "SnackbarManager priority order sorts by priority then newest"
                     :fn priority-order-sorts-by-priority-then-newest})
(table.insert tests {:name "SnackbarManager replace-key replaces visible and queued entries"
                     :fn replace-key-replaces-visible-and-queued})
(table.insert tests {:name "SnackbarManager drop overflow mode drops when visible full"
                     :fn drop-overflow-mode-drops-when-visible-full})
(table.insert tests {:name "SnackbarManager replace overflow mode replaces oldest visible"
                     :fn replace-overflow-mode-replaces-oldest-visible})
(table.insert tests {:name "SnackbarManager queued entry starts timer only after promotion"
                     :fn queued-entry-starts-timer-only-after-promotion})
(table.insert tests {:name "SnackbarManager persistent entry does not auto-dismiss"
                     :fn persistent-entry-does-not-auto-dismiss})
(table.insert tests {:name "SnackbarManager drop cancels timers and blocks later use"
                     :fn drop-cancels-timers-and-blocks-later-use})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "snackbar-manager"
                     :tests tests}))

{:main main}
