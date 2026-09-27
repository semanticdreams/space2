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

(fn test-long-value-is-truncated []
  (local long (string.rep "x" 700))
  (local rendered (ResultModel.value-text long))
  (assert (<= (# rendered) 500))
  (assert (string.find rendered "truncated" 1 true)))

(add-test "initial summary" test-initial-summary)
(add-test "confirmation summary" test-confirmation-summary)
(add-test "running summary" test-running-summary)
(add-test "ok summary includes value" test-ok-summary-includes-value)
(add-test "ok summary with nil value" test-ok-summary-with-nil-value)
(add-test "error summary" test-error-summary)
(add-test "unknown summary" test-unknown-summary)
(add-test "table value is stable and bounded" test-table-value-is-stable-and-bounded)
(add-test "long value is truncated" test-long-value-is-truncated)

(fn main []
  (Runner.run-tests {:name "app-host-command-result-model" :tests tests}))

{:main main :tests tests}
