(local Runner (require :tests/runner))
(local ResultModel (require :app-host.command-result-model))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn test-initial-summary []
  (local summary (ResultModel.initial-summary))
  (assert (= summary.phase :idle))
  (assert (= summary.tone :neutral))
  (assert (= summary.badge-text "Idle"))
  (assert (string.find summary.message "No command run" 1 true))
  (assert (= summary.command-id nil))
  (assert (= summary.result nil)))

(fn test-confirmation-summary []
  (local summary (ResultModel.confirmation-summary {:id :reset :title "Reset"} "Reset game state?"))
  (assert (= summary.phase :confirming))
  (assert (= summary.tone :warning))
  (assert (= summary.badge-text "Confirm"))
  (assert (= summary.command-id :reset))
  (assert (string.find summary.message "Reset game state?" 1 true)))

(fn test-running-summary []
  (local summary (ResultModel.running-summary {:id :configure :title "Configure"}))
  (assert (= summary.phase :running))
  (assert (= summary.tone :info))
  (assert (= summary.badge-text "Running"))
  (assert (= summary.command-id :configure))
  (assert (string.find summary.message "Configure" 1 true)))

(fn test-progress-summary-with-percent []
  (local summary (ResultModel.progress-summary {:id :long :title "Long"}
                                               {:message "halfway" :value 0.5}))
  (assert (= summary.phase :running))
  (assert (= summary.tone :info))
  (assert (= summary.badge-text "Running"))
  (assert (= summary.command-id :long))
  (assert (string.find summary.message "Long" 1 true))
  (assert (string.find summary.message "halfway" 1 true))
  (assert (string.find summary.message "50%" 1 true)))

(fn test-progress-summary-message-only []
  (local summary (ResultModel.progress-summary {:id :long :title "Long"}
                                               {:message "working"}))
  (assert (= summary.phase :running))
  (assert (string.find summary.message "working" 1 true))
  (assert (= (string.find summary.message "%" 1 true) nil)))

(fn test-ok-summary-includes-value []
  (local summary (ResultModel.result-summary {:id :restart :title "Restart"}
                                             {:id :restart :status :ok :value "done"}))
  (assert (= summary.phase :ok))
  (assert (= summary.tone :success))
  (assert (= summary.badge-text "Success"))
  (assert (string.find summary.message "Restart" 1 true))
  (assert (string.find summary.message "done" 1 true)))

(fn test-ok-summary-with-nil-value []
  (local summary (ResultModel.result-summary {:id :restart :title "Restart"}
                                             {:id :restart :status :ok}))
  (assert (= summary.phase :ok))
  (assert (string.find summary.message "succeeded" 1 true))
  (assert (= (string.find summary.message "value" 1 true) nil)))

(fn test-error-summary []
  (local summary (ResultModel.result-summary {:id :explode :title "Explode"}
                                             {:id :explode :status :error :error "boom"}))
  (assert (= summary.phase :error))
  (assert (= summary.tone :danger))
  (assert (= summary.badge-text "Error"))
  (assert (string.find summary.message "Explode" 1 true))
  (assert (string.find summary.message "boom" 1 true)))

(fn test-cancelled-result-summary []
  (local summary (ResultModel.result-summary {:id :long :title "Long"}
                                             {:id :long :status :cancelled :error "user cancelled"}))
  (assert (= summary.phase :cancelled))
  (assert (= summary.tone :warning))
  (assert (= summary.badge-text "Cancelled"))
  (assert (string.find summary.message "Long" 1 true))
  (assert (string.find summary.message "user cancelled" 1 true)))

(fn test-unknown-summary []
  (local summary (ResultModel.result-summary {:id :mystery :title "Mystery"}
                                             {:id :mystery :status :queued}))
  (assert (= summary.phase :unknown))
  (assert (= summary.tone :warning))
  (assert (= summary.badge-text "Unknown"))
  (assert (string.find summary.message "queued" 1 true)))

(fn test-table-value-is-stable-and-bounded []
  (local rendered (ResultModel.value-text {:z 3 :a 1 :nested {:x true}}))
  (assert (string.find rendered ":a" 1 true))
  (assert (string.find rendered ":z" 1 true))
  (assert (<= (# rendered) 500)))

(fn test-opaque-key-value-is-deterministic-and-bounded []
  (local opaque-key (fn [] true))
  (local rendered (ResultModel.value-text {opaque-key "secret"}))
  (assert (string.find rendered "<function>" 1 true))
  (assert (= (string.find rendered "function:" 1 true) nil))
  (assert (<= (# rendered) 500)))

(fn test-ambiguous-key-ordering-is-stable []
  (local first-key {})
  (local second-key {})
  (local rendered (ResultModel.value-text {first-key "z" second-key "a"}))
  (local first-match (string.find rendered "<table>=a" 1 true))
  (local second-match (string.find rendered "<table>=z" 1 true))
  (assert first-match)
  (assert second-match)
  (assert (< first-match second-match)))

(fn test-long-value-is-truncated []
  (local long (string.rep "x" 700))
  (local rendered (ResultModel.value-text long))
  (assert (<= (# rendered) 500))
  (assert (string.find rendered "truncated" 1 true)))

(fn test-large_table_value_reports_omitted_entries []
  (local value {})
  (for [i 1 80]
    (tset value (.. "k" i) i))
  (local rendered (ResultModel.value-text value))
  (assert (<= (# rendered) 500))
  (assert (string.find rendered "more entries" 1 true)
          (.. "expected omitted-entry marker, got " rendered)))

(fn test-deep_table_value_reports_depth_limit []
  (local value {:level 1})
  (var cursor value)
  (for [i 2 40]
    (local child {:level i})
    (tset cursor :child child)
    (set cursor child))
  (local rendered (ResultModel.value-text value))
  (assert (<= (# rendered) 500))
  (assert (string.find rendered "max depth" 1 true)
          (.. "expected depth-limit marker, got " rendered)))

(add-test "initial summary" test-initial-summary)
(add-test "confirmation summary" test-confirmation-summary)
(add-test "running summary" test-running-summary)
(add-test "progress summary with percent" test-progress-summary-with-percent)
(add-test "progress summary message only" test-progress-summary-message-only)
(add-test "ok summary includes value" test-ok-summary-includes-value)
(add-test "ok summary with nil value" test-ok-summary-with-nil-value)
(add-test "error summary" test-error-summary)
(add-test "cancelled result summary" test-cancelled-result-summary)
(add-test "unknown summary" test-unknown-summary)
(add-test "table value is stable and bounded" test-table-value-is-stable-and-bounded)
(add-test "opaque key value is deterministic and bounded" test-opaque-key-value-is-deterministic-and-bounded)
(add-test "ambiguous key ordering is stable" test-ambiguous-key-ordering-is-stable)
(add-test "long value is truncated" test-long-value-is-truncated)
(add-test "large table value reports omitted entries" test-large_table_value_reports_omitted_entries)
(add-test "deep table value reports depth limit" test-deep_table_value_reports_depth_limit)

(fn main []
  (Runner.run-tests {:name "app-host-command-result-model" :tests tests}))

{:main main :tests tests}
