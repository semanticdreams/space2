(local Runner (require :tests/runner))
(local CommandRunner (require :app-host.command-runner))
(local Schema (require :app-host.command-payload-schema))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn assert-error-contains [f expected]
  (local (ok err) (pcall f))
  (assert (= ok false) "expected call to fail")
  (assert (string.find (tostring err) expected 1 true)
          (.. "expected error to contain " expected ", got " (tostring err))))

(fn assert-command-runner-error-contains [f expected]
  (local (ok err) (pcall f))
  (local message (tostring err))
  (assert (= ok false) "expected call to fail")
  (assert (string.find message "[app-host.command-runner]" 1 true)
          (.. "expected command runner error prefix, got " message))
  (assert (string.find message expected 1 true)
          (.. "expected error to contain " expected ", got " message)))

(fn registry-list [self]
  (local out [])
  (each [_ item (ipairs self.items)]
    (table.insert out item))
  out)

(fn registry [items]
  {:items items :list registry-list})

(fn host-with-commands [commands]
  {:commands (registry commands)})

(fn no-op-command-run []
  true)

(fn exploding-command-run [_self _payload]
  (error "boom"))

(fn restart-command-run [self payload]
  (set self.state.ran-restart? true)
  (set self.state.received-payload payload)
  {:self-id self.id :payload-value payload.value})

(fn configure-command-run [self payload]
  (set self.state.received-payload payload)
  {:ok? true :name payload.name})

(fn other-command-run [self _payload]
  (set self.state.ran-other? true))

(fn run-host-with-missing-host []
  (CommandRunner.run-host nil :restart {}))

(fn run-host-with-missing-commands []
  (CommandRunner.run-host {} :restart {}))

(fn run-host-with-missing-list []
  (CommandRunner.run-host {:commands {}} :restart {}))

(fn run-host-with-missing-command-id []
  (CommandRunner.run-host (host-with-commands []) nil {}))

(fn run-host-with-unknown-command []
  (CommandRunner.run-host (host-with-commands []) :missing {}))

(fn run-host-with-duplicate-command []
  (CommandRunner.run-host (host-with-commands [{:id :dup :run no-op-command-run}
                                                {:id :dup :run no-op-command-run}]) :dup {}))

(fn run-host-with-command-missing-run []
  (CommandRunner.run-host (host-with-commands [{:id :bad}]) :bad {}))

(fn list-returns-non-table [_self]
  nil)

(fn run-host-with-non-table-command-list []
  (CommandRunner.run-host {:commands {:list list-returns-non-table}} :restart {}))

(fn run-host-with-non-table-command-facet []
  (CommandRunner.run-host (host-with-commands ["bad-command"]) :restart {}))

(fn test-runs-matching-command-with-payload []
  (local state {:ran-restart? false :ran-other? false :received-payload nil})
  (local restart-command {:id :restart
                          :state state
                          :run restart-command-run})
  (local host (host-with-commands [restart-command
                                   {:id :other
                                    :state state
                                    :run other-command-run}]))
  (local result (CommandRunner.run-host host :restart {:value 42}))
  (assert (= result.id :restart))
  (assert (= result.status :ok))
  (assert (= result.value.self-id :restart))
  (assert (= result.value.payload-value 42))
  (assert (= state.ran-restart? true))
  (assert (= state.ran-other? false) "non-matching commands must not run")
  (assert (= state.received-payload.value 42)))

(add-test "runs matching command with payload" test-runs-matching-command-with-payload)

(fn test-command-handler-errors-return-error-result []
  (local host (host-with-commands [{:id :explode
                                    :run exploding-command-run}]))
  (local result (CommandRunner.run-host host :explode {:why :test}))
  (assert (= result.id :explode))
  (assert (= result.status :error))
  (assert (string.find result.error "boom" 1 true)))

(add-test "command handler errors return error result" test-command-handler-errors-return-error-result)

(fn test-structural-command-failures-are-loud []
  (assert-error-contains run-host-with-missing-host "host table")
  (assert-error-contains run-host-with-missing-commands "commands")
  (assert-error-contains run-host-with-missing-list "list")
  (assert-error-contains run-host-with-missing-command-id "command id")
  (assert-error-contains run-host-with-unknown-command "not found")
  (assert-error-contains run-host-with-duplicate-command "duplicate")
  (assert-error-contains run-host-with-command-missing-run "run")
  (assert-command-runner-error-contains run-host-with-non-table-command-list "list")
  (assert-command-runner-error-contains run-host-with-non-table-command-facet "command facet"))

(add-test "structural command failures are loud" test-structural-command-failures-are-loud)

(fn test-valid_payload_schema_preserves_payload_dispatch []
  (local state {:received-payload nil})
  (local host (host-with-commands [{:id :configure
                                    :state state
                                    :payload-schema {:fields [{:id :name :type :string}]}
                                    :run configure-command-run}]))
  (local result (CommandRunner.run-host host :configure {:name "Ada"}))
  (assert (= result.status :ok))
  (assert (= result.value.name "Ada"))
  (assert (= state.received-payload.name "Ada")))

(fn test-malformed_payload_schema_is_structural_error []
  (local host (host-with-commands [{:id :bad
                                    :payload-schema {:fields [{:id :payload :type :object}]}
                                    :run exploding-command-run}]))
  (fn run-bad-command []
    (CommandRunner.run-host host :bad {}))
  (assert-error-contains run-bad-command "[app-host.command-payload-schema]")
  (assert-error-contains run-bad-command "unsupported field type"))

(fn test-false_payload_schema_is_structural_error []
  (local host (host-with-commands [{:id :bad
                                    :payload-schema false
                                    :run exploding-command-run}]))
  (fn run-bad-command []
    (CommandRunner.run-host host :bad {}))
  (assert-error-contains run-bad-command "[app-host.command-payload-schema]")
  (assert-error-contains run-bad-command "schema must be a table"))

(add-test "valid payload schema preserves payload dispatch" test-valid_payload_schema_preserves_payload_dispatch)
(add-test "malformed payload schema is structural error" test-malformed_payload_schema_is_structural_error)
(add-test "false payload schema is structural error" test-false_payload_schema_is_structural_error)

(fn test-payload_schema_defaults_and_display_values []
  (local schema {:fields [{:id :name :type :string}
                          {:id :count :type :number :default 3}
                          {:id :enabled :type :boolean}
                          {:id :mode :type :select :options [{:value :fast :label "Fast"}
                                                             {:value :safe}]}]})
  (Schema.validate-schema schema {:command-id :configure})
  (assert (= (Schema.default-value (. schema.fields 1)) ""))
  (assert (= (Schema.default-value (. schema.fields 2)) "3"))
  (assert (= (Schema.default-value (. schema.fields 3)) false))
  (assert (= (Schema.default-value (. schema.fields 4)) :fast))
  (assert (= (Schema.display-value (. schema.fields 4) :fast) "Fast"))
  (assert (= (Schema.display-value (. schema.fields 3) true) "true")))

(fn test-payload_schema_builds_flat_payload_from_values []
  (local schema {:fields [{:id :name :type :string}
                          {:id :count :type :number}
                          {:id :enabled :type :boolean}
                          {:id :mode :type :select :options [{:value :fast}
                                                             {:value :safe}]}]})
  (local payload (Schema.payload-from-values schema {:name "Ada"
                                                     :count "42"
                                                     :enabled true
                                                     :mode :safe}
                                             {:command-id :configure}))
  (assert (= payload.name "Ada"))
  (assert (= payload.count 42))
  (assert (= payload.enabled true))
  (assert (= payload.mode :safe)))

(fn test-payload_schema_rejects_invalid_payload_values []
  (local number-schema {:fields [{:id :count :type :number}]})
  (local boolean-schema {:fields [{:id :enabled :type :boolean}]})
  (local select-schema {:fields [{:id :mode :type :select :options [{:value :fast}]}]})
  (fn payload-with-invalid-number []
    (Schema.payload-from-values number-schema {:count "abc"} {:command-id :configure}))
  (fn payload-with-invalid-boolean []
    (Schema.payload-from-values boolean-schema {:enabled "true"} {:command-id :configure}))
  (fn payload-with-invalid-select []
    (Schema.payload-from-values select-schema {:mode :safe} {:command-id :configure}))
  (assert-error-contains payload-with-invalid-number "number field count requires numeric value")
  (assert-error-contains payload-with-invalid-boolean "boolean field enabled requires boolean value")
  (assert-error-contains payload-with-invalid-select "select field mode requires declared option value"))

(fn test-payload_schema_rejects_non_list_fields []
  (local keyed-schema {:fields {:name {:id :name :type :object}}})
  (local sparse-fields [])
  (tset sparse-fields 2 {:id :name :type :string})
  (local sparse-schema {:fields sparse-fields})
  (fn validate-keyed-schema []
    (Schema.validate-schema keyed-schema {:command-id :configure}))
  (fn validate-sparse-schema []
    (Schema.validate-schema sparse-schema {:command-id :configure}))
  (assert-error-contains validate-keyed-schema "[app-host.command-payload-schema]")
  (assert-error-contains validate-keyed-schema "fields must be an ordered list")
  (assert-error-contains validate-sparse-schema "fields must be an ordered list"))

(fn test-payload_schema_rejects_nested_and_extra_shapes []
  (local top-extra-schema {:fields [{:id :title :type :string}]
                           :computed true})
  (local field-extra-schema {:fields [{:id :title
                                       :type :string
                                       :fields [{:id :nested :type :string}]}]})
  (local option-extra-schema {:fields [{:id :mode
                                        :type :select
                                        :options [{:value :fast :metadata {}}]}]})
  (local nested-label-schema {:fields [{:id :title
                                        :type :string
                                        :label {:text "Title"}}]})
  (fn validate-top-extra-schema []
    (Schema.validate-schema top-extra-schema {:command-id :configure}))
  (fn validate-field-extra-schema []
    (Schema.validate-schema field-extra-schema {:command-id :configure}))
  (fn validate-option-extra-schema []
    (Schema.validate-schema option-extra-schema {:command-id :configure}))
  (fn validate-nested-label-schema []
    (Schema.validate-schema nested-label-schema {:command-id :configure}))
  (assert-error-contains validate-top-extra-schema "[app-host.command-payload-schema]")
  (assert-error-contains validate-top-extra-schema "unsupported schema key")
  (assert-error-contains validate-field-extra-schema "unsupported field key")
  (assert-error-contains validate-option-extra-schema "unsupported option key")
  (assert-error-contains validate-nested-label-schema "label for field title must be scalar"))

(fn test-payload_schema_rejects_non_list_select_options []
  (local options [{:value :fast}])
  (tset options :metadata {:value :safe})
  (local schema {:fields [{:id :mode
                           :type :select
                           :options options}]})
  (fn validate-schema-with-keyed-option []
    (Schema.validate-schema schema {:command-id :configure}))
  (assert-error-contains validate-schema-with-keyed-option "[app-host.command-payload-schema]")
  (assert-error-contains validate-schema-with-keyed-option "options for field mode must be an ordered list"))

(add-test "payload schema defaults and display values" test-payload_schema_defaults_and_display_values)
(add-test "payload schema builds flat payload from values" test-payload_schema_builds_flat_payload_from_values)
(add-test "payload schema rejects invalid payload values" test-payload_schema_rejects_invalid_payload_values)
(add-test "payload schema rejects non-list fields" test-payload_schema_rejects_non_list_fields)
(add-test "payload schema rejects nested and extra shapes" test-payload_schema_rejects_nested_and_extra_shapes)
(add-test "payload schema rejects non-list select options" test-payload_schema_rejects_non_list_select_options)

(fn main []
  (Runner.run-tests {:name "app-host-command-runner" :tests tests}))

{:main main :tests tests}
