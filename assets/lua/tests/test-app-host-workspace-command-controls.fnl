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

(local configure-schema
  {:fields [{:id :title :type :string :label "Title" :default "draft"}
            {:id :count :type :number :label "Count" :default 2}
            {:id :enabled :type :boolean :label "Enabled" :default false}
            {:id :mode :type :select :label "Mode"
             :options [{:value :fast :label "Fast"}
                       {:value :safe :label "Safe"}]}]})

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
  (assert (= (. fixture.state.calls 1 :payload) nil) "no-schema command should still pass nil payload")
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

(fn test-schema_form_builds_payload_for_command []
  (local fixture (make-descriptor {:commands [{:id :configure
                                               :title "Configure"
                                               :status :metadata
                                               :payload-schema configure-schema}]
                                  :results {:configure {:id :configure
                                                        :status :ok
                                                        :value {:configured? true}}}}))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  (local form (. state.forms-by-id :configure))
  (assert form "schema command should build a payload form")
  (local title-input (. form.inputs-by-id :title))
  (local count-input (. form.inputs-by-id :count))
  (local enabled-button (. form.buttons-by-id :enabled))
  (local mode-button (. form.buttons-by-id :mode))
  (local run-button (. state.buttons-by-id :configure))
  (title-input:set-text "launch")
  (count-input:set-text "3.5")
  (enabled-button:on-click {:source :test})
  (mode-button:on-click {:source :test})
  (run-button:on-click {:source :test})
  (local call (. fixture.state.calls 1))
  (assert (= call.id :configure))
  (assert (= call.payload.title "launch"))
  (assert (= call.payload.count 3.5))
  (assert (= call.payload.enabled true))
  (assert (= call.payload.mode :safe))
  (widget:drop))

(fn test-invalid_number_payload_fails_before_command_run []
  (local fixture (make-descriptor {:commands [{:id :configure
                                               :title "Configure"
                                               :status :metadata
                                               :payload-schema configure-schema}]}))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local form (. widget.__command-controls.forms-by-id :configure))
  (local count-input (. form.inputs-by-id :count))
  (local run-button (. widget.__command-controls.buttons-by-id :configure))
  (count-input:set-text "not-a-number")
  (assert-error-contains #(run-button:on-click {:source :test}) "number field")
  (assert (= fixture.state.run-count 0) "invalid payload must fail before descriptor run-command")
  (widget:drop))

(fn test-malformed_payload_schema_fails_control_build []
  (local fixture (make-descriptor {:commands [{:id :bad
                                               :title "Bad"
                                               :status :metadata
                                               :payload-schema {:fields [{:id :x :type :object}]}}]}))
  (local context (test-context))
  (assert-error-contains #(build-widget fixture.descriptor context.ctx)
                         "[app-host.command-payload-schema]")
  (assert (= (# context.clickables.registered) 0)
          "malformed schema must fail before registering click handlers")
  (assert (= (# context.hoverables.registered) 0)
          "malformed schema must fail before registering hover handlers"))

(fn test-false_payload_schema_fails_control_build []
  (local fixture (make-descriptor {:commands [{:id :bad
                                               :title "Bad"
                                               :status :metadata
                                               :payload-schema false}]}))
  (local context (test-context))
  (assert-error-contains #(build-widget fixture.descriptor context.ctx)
                         "[app-host.command-payload-schema]")
  (assert (= fixture.state.run-count 0)
          "false payload schema must fail before descriptor run-command")
  (assert (= (# context.clickables.registered) 0)
          "false payload schema must fail before registering click handlers")
  (assert (= (# context.hoverables.registered) 0)
          "false payload schema must fail before registering hover handlers"))

(add-test "schema form builds payload for command" test-schema_form_builds_payload_for_command)
(add-test "invalid number payload fails before command run" test-invalid_number_payload_fails_before_command_run)
(add-test "malformed payload schema fails control build" test-malformed_payload_schema_fails_control_build)
(add-test "false payload schema fails control build" test-false_payload_schema_fails_control_build)

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

(fn test-danger_levels_update_badges_and_button_variants []
  (local fixture (make-descriptor {:commands [{:id :inspect :title "Inspect" :status :metadata :danger-level :normal}
                                               {:id :warn :title "Warn" :status :metadata :danger-level :warning}
                                               {:id :delete :title "Delete" :status :metadata :danger-level :danger}]}))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  (assert (= (. state.danger-levels-by-id :inspect) :normal))
  (assert (= (. state.danger-levels-by-id :warn) :warning))
  (assert (= (. state.danger-levels-by-id :delete) :danger))
  (assert (= (. state.buttons-by-id :warn :variant) :warning))
  (assert (= (. state.buttons-by-id :delete :variant) :danger))
  (assert (= (. state.danger-badges-by-id :warn :tone) :warning))
  (assert (= (. state.danger-badges-by-id :delete :tone) :danger))
  (widget:drop))

(fn test-required_confirmation_needs_second_click_to_run []
  (local fixture (make-descriptor {:commands [{:id :reset
                                               :title "Reset"
                                               :status :metadata
                                               :danger-level :danger
                                               :confirmation {:message "Reset game state?"}}]
                                  :results {:reset {:id :reset :status :ok :value {:reset? true}}}}))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  (local button (. state.buttons-by-id :reset))
  (button:on-click {:source :test})
  (assert (= fixture.state.run-count 0) "first click must not run command")
  (assert (= state.confirming-command-id :reset))
  (assert (string.find state.result-message "Reset game state?" 1 true))
  (assert (= (. state.button-labels-by-id :reset) "Confirm"))
  (button:on-click {:source :test})
  (assert (= fixture.state.run-count 1) "second click should run command")
  (assert (= state.confirming-command-id nil))
  (assert (= (. state.button-labels-by-id :reset) "Run"))
  (widget:drop))

(fn test-confirmation_required_false_runs_immediately []
  (local fixture (make-descriptor {:commands [{:id :safe-reset
                                               :title "Safe Reset"
                                               :status :metadata
                                               :confirmation {:message "No prompt" :required? false}}]
                                  :results {:safe-reset {:id :safe-reset :status :ok :value {:reset? true}}}}))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local button (. widget.__command-controls.buttons-by-id :safe-reset))
  (button:on-click {:source :test})
  (assert (= fixture.state.run-count 1))
  (assert (= widget.__command-controls.confirming-command-id nil))
  (widget:drop))

(fn test-confirmation_defers_payload_validation_until_execute_click []
  (local schema {:fields [{:id :count :type :number :label "Count"}]})
  (local fixture (make-descriptor {:commands [{:id :configure
                                               :title "Configure"
                                               :status :metadata
                                               :payload-schema schema
                                               :confirmation {:message "Apply config?"}}]}))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  (local form (. state.forms-by-id :configure))
  (local input (. form.inputs-by-id :count))
  (local button (. state.buttons-by-id :configure))
  (input:set-text "not-a-number")
  (button:on-click {:source :test})
  (assert (= fixture.state.run-count 0))
  (assert (= state.confirming-command-id :configure))
  (assert-error-contains #(button:on-click {:source :test}) "number field")
  (assert (= fixture.state.run-count 0))
  (widget:drop))

(add-test "danger levels update badges and button variants" test-danger_levels_update_badges_and_button_variants)
(add-test "required confirmation needs second click to run" test-required_confirmation_needs_second_click_to_run)
(add-test "confirmation required false runs immediately" test-confirmation_required_false_runs_immediately)
(add-test "confirmation defers payload validation until execute click" test-confirmation_defers_payload_validation_until_execute_click)

(fn main []
  (Runner.run-tests {:name "app-host-workspace-command-controls" :tests tests}))

{:main main :tests tests}
