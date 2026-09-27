(local Runner (require :tests/runner))
(local Controls (require :app-host.workspace-command-controls))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn assert-error-contains [f expected]
  (local (ok err) (pcall f))
  (assert (= ok false) "expected call to fail")
  (assert (string.find (tostring err) expected 1 true)
          (.. "expected error to contain " expected ", got " (tostring err))))

(fn make-registry []
  {:registered []
   :unregistered []
   :register (fn [self item]
               (table.insert self.registered item)
               item)
   :register-right-click (fn [self item]
                           (table.insert self.registered item)
                           item)
   :register-double-click (fn [self item]
                            (table.insert self.registered item)
                            item)
   :unregister (fn [self item]
                 (table.insert self.unregistered item)
                 item)
   :unregister-right-click (fn [self item]
                             (table.insert self.unregistered item)
                             item)
   :unregister-double-click (fn [self item]
                              (table.insert self.unregistered item)
                              item)})

(fn make-hover-registry []
  {:registered []
   :unregistered []
   :register (fn [self item]
               (table.insert self.registered item)
               item)
   :unregister (fn [self item]
                 (table.insert self.unregistered item)
                 item)})

(fn make-text-ssbo-batcher []
  {:upsert-text (fn [_self _key _payload] nil)
   :update-text-transform (fn [_self _key _payload] nil)
   :remove-text (fn [_self _key] nil)})

(fn test-context []
  (local clickables (assert (make-registry) "clickables registry required"))
  (local hoverables (assert (make-hover-registry) "hoverables registry required"))
  (local text-ssbo-batcher (make-text-ssbo-batcher))
  {:ctx {:clickables clickables
         :hoverables hoverables
         :get-text-ssbo-batcher (fn [_self] text-ssbo-batcher)}
   :clickables clickables
   :hoverables hoverables})

(fn make-read-inspector-snapshot [state commands]
  (fn read-inspector-snapshot [_self]
    (set state.read-count (+ state.read-count 1))
    {:inspectors [] :commands commands}))

(fn make-default-run-command [state results]
  (fn default-run-command [_self command-id payload]
    (set state.run-count (+ state.run-count 1))
    (table.insert state.calls {:id command-id :payload payload})
    (. results command-id)))

(fn make-descriptor [opts]
  (local options (if opts opts {}))
  (local state {:read-count 0 :run-count 0 :calls []})
  (local commands (if (not (= options.commands nil))
                    options.commands
                    [{:id :restart :title "Restart" :description "Restart app" :status :metadata}
                     {:id :explode :title "Explode" :description "Return an error" :status :metadata}]))
  (local results (if (not (= options.results nil))
                   options.results
                   {:restart {:id :restart :status :ok :value {:done? true}}
                    :explode {:id :explode :status :error :error "boom"}}))
  (local run-command (if options.run-command
                       options.run-command
                       (make-default-run-command state results)))
  {:state state
   :descriptor {:read-inspector-snapshot (make-read-inspector-snapshot state commands)
                :run-command run-command}})

(fn build-widget [descriptor ctx]
  (local builder (Controls.WorkspaceCommandControls {:descriptor descriptor}))
  (builder ctx))

(fn test-build_reads_metadata_without_running_commands []
  (local fixture (make-descriptor))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  (assert (= fixture.state.read-count 1) "build should read exactly one snapshot")
  (assert (= fixture.state.run-count 0) "build must not run commands")
  (assert (= (# state.commands) 2))
  (assert (= (. state.commands 1 :id) :restart))
  (assert state.snapshot)
  (assert widget.hosted-app-workspace-panel)
  (assert widget.layout)
  (assert (. state.buttons-by-id :restart) "restart command should have a run button")
  (assert (. state.buttons-by-id :explode) "explode command should have a run button")
  (widget:drop))

(add-test "build reads command metadata without running commands" test-build_reads_metadata_without_running_commands)

(fn test-run_button_updates_success_result []
  (local fixture (make-descriptor))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  (local button (. state.buttons-by-id :restart))
  (button:on-click {:source :test})
  (assert (= fixture.state.run-count 1))
  (assert (= (. fixture.state.calls 1 :id) :restart))
  (assert (= (. fixture.state.calls 1 :payload) nil) "visual command buttons pass nil payload")
  (assert (= state.last-result.status :ok))
  (assert (string.find state.result-message "Restart" 1 true))
  (assert (string.find state.result-message "succeeded" 1 true))
  (widget:drop))

(fn test-run_button_updates_error_result []
  (local fixture (make-descriptor))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  (local button (. state.buttons-by-id :explode))
  (button:on-click {:source :test})
  (assert (= fixture.state.run-count 1))
  (assert (= state.last-result.status :error))
  (assert (string.find state.result-message "Explode" 1 true))
  (assert (string.find state.result-message "failed" 1 true))
  (assert (string.find state.result-message "boom" 1 true))
  (widget:drop))

(add-test "run button updates success result" test-run_button_updates_success_result)
(add-test "run button updates error result" test-run_button_updates_error_result)

(fn structural-failing-run-command [_self _command-id _payload]
  (error "structural failure"))

(fn test-structural_run_command_errors_propagate []
  (local fixture (make-descriptor {:run-command structural-failing-run-command}))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  (local button (. state.buttons-by-id :restart))
  (fn click-button []
    (button:on-click {:source :test}))
  (assert-error-contains click-button "structural failure")
  (assert (= state.last-result nil) "structural errors must not become result envelopes")
  (widget:drop))

(add-test "structural run-command errors propagate" test-structural_run_command_errors_propagate)

(fn test-drop_unregisters_button_handlers []
  (local fixture (make-descriptor))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (assert (> (# context.clickables.registered) 0) "buttons should register clickable handlers")
  (assert (> (# context.hoverables.registered) 0) "buttons should register hover handlers")
  (widget:drop)
  (assert (= (# context.clickables.unregistered) (# context.clickables.registered))
          "drop should unregister every clickable handler registered by buttons")
  (assert (= (# context.hoverables.unregistered) (# context.hoverables.registered))
          "drop should unregister every hover handler registered by buttons"))

(add-test "drop unregisters button handlers" test-drop_unregisters_button_handlers)

(fn main []
  (Runner.run-tests {:name "app-host-workspace-command-controls" :tests tests}))

{:main main :tests tests}
