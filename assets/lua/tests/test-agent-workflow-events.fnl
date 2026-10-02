(local fs (require :fs))
(local {: WorkflowStore} (require :workflows/store))
(local WorkflowEvents (require :llm/agent/workflow-events))

(local tests [])
(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "agent-workflow-events"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "store-" (os.time) "-" temp-counter)))

(fn prepare-temp-dir []
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  dir)

(fn remove-temp-dir [dir]
  (when (fs.exists dir)
    (fs.remove-all dir)))

(fn make-temp-store []
  (local root (prepare-temp-dir))
  (local store (WorkflowStore {:base-dir root}))
  (local definition (store:create-definition {:id "wf-agent-test" :name "Agent test workflow"}))
  (local run (store:create-run definition.id {} {:agent-id "agent-alpha"
                                                 :data {:topic "initial"}
                                                 :legacy-session-id "legacy-1"}))
  {:root root :store store :run run})

(fn with-temp-store [f]
  (local record (make-temp-store))
  (local (ok result) (pcall f record.store record.run))
  (remove-temp-dir record.root)
  (if ok
      result
      (error result)))

(fn get-projected-session [store run-id]
  (WorkflowEvents.project-session (store:get-run run-id)))

(fn assert-pcall-error-containing [ok err expected]
  (assert (not ok) "expected function to fail")
  (assert (string.find (tostring err) expected 1 true)
          (.. "expected error containing " expected ", got " (tostring err))))

(fn assert-session-created-projection [store run]
  (WorkflowEvents.append-session-created store run.id {:agent-id "agent-beta"
                                                       :data {:topic "created"}
                                                       :created-at "2026-08-15T00:00:00Z"})
  (local session (get-projected-session store run.id))
  (assert (= session.id run.id) "session id should be the workflow run id")
  (assert (= session.workflow-run-id run.id) "workflow run id should be exposed")
  (assert (= session.agent-id "agent-beta") "session-created event should set agent id")
  (assert (= session.data.topic "created") "session-created event data should be projected")
  (assert (= session.legacy-session-id "legacy-1") "legacy metadata should come from run context")
  (assert (= (length session.items) 0) "session starts without transcript items")
  (assert (= session.created-at "2026-08-15T00:00:00Z") "created-at should come from session-created event")
  (assert (= session.updated-at "2026-08-15T00:00:00Z") "updated-at should come from latest relevant event")
  (local summary (WorkflowEvents.session-summary session))
  (assert (= summary.id run.id) "summary id should match session")
  (assert (= summary.agent-id "agent-beta") "summary agent id should match session")
  (assert (= summary.item-count 0) "summary should count projected items"))

(fn projects-session-created-event-to-sidebar-session-shape []
  (with-temp-store assert-session-created-projection))

(fn assert-appended-message-items-in-order [store run]
  (WorkflowEvents.append-item store run.id {:id "item-user" :type :message :role :user :content "hello"})
  (WorkflowEvents.append-item store run.id {:id "item-assistant" :type :message :role :assistant :content "hi"})
  (local session (get-projected-session store run.id))
  (assert (= (length session.items) 2) "two appended items should project")
  (local first-item (. session.items 1))
  (local second-item (. session.items 2))
  (assert (= first-item.id "item-user") "first item should stay first")
  (assert (= second-item.id "item-assistant") "second item should stay second"))

(fn projects-appended-message-items-in-order []
  (with-temp-store assert-appended-message-items-in-order))

(fn assert-status-changes-use-latest-status [store run]
  (WorkflowEvents.append-status store run.id :running {:created-at "2026-08-15T00:00:01Z"})
  (WorkflowEvents.append-status store run.id :idle {:created-at "2026-08-15T00:00:02Z"})
  (local session (get-projected-session store run.id))
  (assert (= session.status :idle) "latest status event should win")
  (assert (= session.updated-at "2026-08-15T00:00:02Z") "latest status timestamp should be updated-at"))

(fn projects-status-changes-with-latest-status []
  (with-temp-store assert-status-changes-use-latest-status))

(fn assert-upsert-replaces-stream-item [store run]
  (WorkflowEvents.append-item store run.id {:id "stream-1" :type :message :role :assistant :content "hel"})
  (WorkflowEvents.append-upsert store run.id {:id "stream-1" :type :message :role :assistant :content "hello"})
  (local session (get-projected-session store run.id))
  (assert (= (length session.items) 1) "upsert should replace existing item")
  (local item (. session.items 1))
  (assert (= item.id "stream-1") "upsert should preserve stable item id")
  (assert (= item.content "hello") "upsert should replace item fields"))

(fn upserts-existing-stream-item-with-stable-id []
  (with-temp-store assert-upsert-replaces-stream-item))

(fn assert-update-merges-existing-item-fields [store run]
  (WorkflowEvents.append-item store run.id {:id "tool-1" :type :tool-call :status :running :content "call"})
  (WorkflowEvents.append-update store run.id "tool-1" {:status :done :result "ok"})
  (local session (get-projected-session store run.id))
  (assert (= (length session.items) 1) "update should not append a new item")
  (local item (. session.items 1))
  (assert (= item.id "tool-1") "update should preserve item id")
  (assert (= item.status :done) "update should change requested field")
  (assert (= item.result "ok") "update should add requested field")
  (assert (= item.content "call") "update should preserve other fields"))

(fn updates-existing-item-fields []
  (with-temp-store assert-update-merges-existing-item-fields))

(fn assert-duplicate-append-is-rejected [store run]
  (WorkflowEvents.append-item store run.id {:id "dup" :type :message :content "one"})
  (local (ok err) (pcall WorkflowEvents.append-item store run.id {:id "dup" :type :message :content "two"}))
  (assert-pcall-error-containing ok err "duplicate agent item id"))

(fn rejects-duplicate-append-item-id []
  (with-temp-store assert-duplicate-append-is-rejected))

(fn assert-missing-update-is-rejected [store run]
  (local (ok err) (pcall WorkflowEvents.append-update store run.id "missing" {:status :done}))
  (assert-pcall-error-containing ok err "missing agent item id"))

(fn rejects-update-for-missing-item-id []
  (with-temp-store assert-missing-update-is-rejected))

(fn assert-reserved-context-and-created-fields-do-not-own-projection []
  (local run {:id "run-owned"
              :status :running
              :context {:id "legacy-context"
                        :workflow-run-id "legacy-workflow"
                        :items [{:id "cached-item" :content "cached"}]
                        :agent-id "agent-alpha"
                        :data {:topic "context"}}
              :events [{:kind WorkflowEvents.KIND_SESSION_CREATED
                        :data {:id "legacy-event"
                               :workflow-run-id "event-workflow"
                               :items [{:id "cached-event" :content "cached"}]
                               :agent-id "agent-beta"
                               :data {:topic "created"}}
                        :created-at "2026-08-15T00:00:00Z"}]
              :created-at "2026-08-14T00:00:00Z"
              :updated-at "2026-08-14T00:00:00Z"})
  (local session (WorkflowEvents.project-session run))
  (assert (= session.id "run-owned") "run id must remain projection-owned")
  (assert (= session.workflow-run-id "run-owned") "workflow run id must remain projection-owned")
  (assert (= session.legacy-session-id "legacy-context") "legacy id should be audit metadata")
  (assert (= session.legacy-workflow-run-id "legacy-workflow") "legacy workflow id should be audit metadata")
  (assert (= (length session.items) 0) "metadata items must not become transcript items")
  (assert (= session.data.topic "created") "non-reserved session data should still project")
  (assert (= session.agent-id "agent-beta") "session-created agent id should still project"))

(fn preserves-run-identity-and-items-against-reserved-metadata []
  (assert-reserved-context-and-created-fields-do-not-own-projection))

(fn assert-numeric-workflow-timestamps-project-as-canonical-strings []
  (local session (WorkflowEvents.project-session {:id "run-numeric"
                                                  :status :running
                                                  :context {:agent-id "agent-alpha"}
                                                  :created-at 0
                                                  :updated-at 1
                                                  :events [{:kind WorkflowEvents.KIND_SESSION_CREATED
                                                            :data {:agent-id "agent-beta"}
                                                            :created-at 2}
                                                           {:kind WorkflowEvents.KIND_STATUS_CHANGED
                                                            :status :idle
                                                            :created-at 3}]}))
  (assert (= session.created-at "1970-01-01T00:00:02Z") "numeric session-created timestamp should project as canonical UTC string")
  (assert (= session.updated-at "1970-01-01T00:00:03Z") "numeric latest event timestamp should project as canonical UTC string")
  (local summary (WorkflowEvents.session-summary session))
  (assert (= summary.created-at "1970-01-01T00:00:02Z") "summary created-at should remain canonical UTC string")
  (assert (= summary.updated-at "1970-01-01T00:00:03Z") "summary updated-at should remain canonical UTC string"))

(fn projects-numeric-workflow-timestamps-as-canonical-strings []
  (assert-numeric-workflow-timestamps-project-as-canonical-strings))

(fn assert-present-malformed-event-timestamps-fail-loudly []
  (local payload-session-created-run {:id "run-bad-session-created-payload-timestamp"
                                      :status :running
                                      :context {:agent-id "agent-alpha"}
                                      :created-at "2026-08-14T00:00:00Z"
                                      :updated-at "2026-08-14T00:00:00Z"
                                      :events [{:kind WorkflowEvents.KIND_SESSION_CREATED
                                                :data {:agent-id "agent-beta"
                                                       :created-at false}
                                                :created-at "2026-08-15T00:00:00Z"}]})
  (local (payload-created-ok payload-created-err) (pcall WorkflowEvents.project-session payload-session-created-run))
  (assert-pcall-error-containing payload-created-ok payload-created-err "unsupported timestamp value type: boolean")
  (local payload-status-run {:id "run-bad-status-payload-timestamp"
                             :status :running
                             :context {:agent-id "agent-alpha"}
                             :created-at "2026-08-14T00:00:00Z"
                             :updated-at "2026-08-14T00:00:00Z"
                             :events [{:kind WorkflowEvents.KIND_STATUS_CHANGED
                                       :status :idle
                                       :data {:created-at false}
                                       :created-at "2026-08-15T00:00:01Z"}]})
  (local (payload-status-ok payload-status-err) (pcall WorkflowEvents.project-session payload-status-run))
  (assert-pcall-error-containing payload-status-ok payload-status-err "unsupported timestamp value type: boolean")
  (local session-created-run {:id "run-bad-session-created-timestamp"
                              :status :running
                              :context {:agent-id "agent-alpha"}
                              :created-at "2026-08-14T00:00:00Z"
                              :updated-at "2026-08-14T00:00:00Z"
                              :events [{:kind WorkflowEvents.KIND_SESSION_CREATED
                                        :data {:agent-id "agent-beta"}
                                        :created-at false}]})
  (local (created-ok created-err) (pcall WorkflowEvents.project-session session-created-run))
  (assert-pcall-error-containing created-ok created-err "unsupported timestamp value type: boolean")
  (local status-run {:id "run-bad-status-timestamp"
                     :status :running
                     :context {:agent-id "agent-alpha"}
                     :created-at "2026-08-14T00:00:00Z"
                     :updated-at "2026-08-14T00:00:00Z"
                     :events [{:kind WorkflowEvents.KIND_STATUS_CHANGED
                               :status :idle
                               :created-at false}]})
  (local (status-ok status-err) (pcall WorkflowEvents.project-session status-run))
  (assert-pcall-error-containing status-ok status-err "unsupported timestamp value type: boolean"))

(fn rejects-present-malformed-event-timestamps []
  (assert-present-malformed-event-timestamps-fail-loudly))

(fn assert-appended-session-created-payload-is-isolated [store run]
  (local payload {:agent-id "agent-beta"
                  :data {:nested {:value "before"}}
                  :created-at "2026-08-15T00:00:00Z"})
  (WorkflowEvents.append-session-created store run.id payload)
  (set payload.data.nested.value "after")
  (local first-session (get-projected-session store run.id))
  (assert (= first-session.data.nested.value "before") "appended session-created data should be immutable event history")
  (set first-session.data.nested.value "projected-mutation")
  (local second-session (get-projected-session store run.id))
  (assert (= second-session.data.nested.value "before") "projected session data should be isolated copies"))

(fn isolates-nested-session-created-payloads-and-projections []
  (with-temp-store assert-appended-session-created-payload-is-isolated))

(fn assert-appended-item-payload-is-isolated [store run]
  (local item {:id "tool-args" :type :tool-call :arguments {:path {:value "before"}}})
  (WorkflowEvents.append-item store run.id item)
  (set item.arguments.path.value "after")
  (local first-session (get-projected-session store run.id))
  (local first-item (. first-session.items 1))
  (assert (= first-item.arguments.path.value "before") "appended item data should be immutable event history")
  (set first-item.arguments.path.value "projected-mutation")
  (local second-session (get-projected-session store run.id))
  (local second-item (. second-session.items 1))
  (assert (= second-item.arguments.path.value "before") "projected item data should be isolated copies"))

(fn isolates-nested-item-payloads-and-projections []
  (with-temp-store assert-appended-item-payload-is-isolated))

(fn assert-status-and-update-payloads-are-isolated [store run]
  (WorkflowEvents.append-item store run.id {:id "tool-update" :type :tool-call :status :running})
  (local status-data {:details {:value "status-before"} :created-at "2026-08-15T00:00:01Z"})
  (local updates {:status :done :details {:value "update-before"} :updated-at "2026-08-15T00:00:02Z"})
  (WorkflowEvents.append-status store run.id :running status-data)
  (WorkflowEvents.append-update store run.id "tool-update" updates)
  (set status-data.details.value "status-after")
  (set updates.details.value "update-after")
  (local stored-run (store:get-run run.id))
  (local status-event (. stored-run.events 2))
  (local update-event (. stored-run.events 3))
  (assert (= status-event.data.details.value "status-before") "stored status event data should be isolated")
  (assert (= update-event.updates.details.value "update-before") "stored update event data should be isolated")
  (local first-session (WorkflowEvents.project-session stored-run))
  (local first-item (. first-session.items 1))
  (assert (= first-item.details.value "update-before") "projected update data should use stored event history")
  (set first-item.details.value "projected-mutation")
  (local second-session (get-projected-session store run.id))
  (local second-item (. second-session.items 1))
  (assert (= second-item.details.value "update-before") "projected update data should be isolated copies"))

(fn isolates-nested-status-and-update-payloads []
  (with-temp-store assert-status-and-update-payloads-are-isolated))

(fn assert-returned-events-are-isolated-from-history [store run]
  (local created-event (WorkflowEvents.append-session-created store run.id {:agent-id "agent-beta"
                                                                            :data {:nested {:value "created-before"}}
                                                                            :created-at "2026-08-15T00:00:00Z"}))
  (local status-event (WorkflowEvents.append-status store run.id :running {:details {:value "status-before"}
                                                                           :created-at "2026-08-15T00:00:01Z"}))
  (local append-event (WorkflowEvents.append-item store run.id {:id "returned-append"
                                                                :type :message
                                                                :content {:value "append-before"}}))
  (local upsert-event (WorkflowEvents.append-upsert store run.id {:id "returned-upsert"
                                                                  :type :message
                                                                  :content {:value "upsert-before"}}))
  (local update-event (WorkflowEvents.append-update store run.id "returned-append" {:content {:value "update-before"}
                                                                                    :updated-at "2026-08-15T00:00:02Z"}))
  (set created-event.data.data.nested.value "created-after")
  (set status-event.data.details.value "status-after")
  (set append-event.item.content.value "append-after")
  (set upsert-event.item.content.value "upsert-after")
  (set update-event.updates.content.value "update-after")
  (local stored-run (store:get-run run.id))
  (local stored-created-event (. stored-run.events 1))
  (local stored-status-event (. stored-run.events 2))
  (local stored-append-event (. stored-run.events 3))
  (local stored-upsert-event (. stored-run.events 4))
  (local stored-update-event (. stored-run.events 5))
  (assert (= stored-created-event.data.data.nested.value "created-before") "returned session-created event must not mutate stored run history")
  (assert (= stored-status-event.data.details.value "status-before") "returned status event must not mutate stored run history")
  (assert (= stored-append-event.item.content.value "append-before") "returned append event must not mutate stored run history")
  (assert (= stored-upsert-event.item.content.value "upsert-before") "returned upsert event must not mutate stored run history")
  (assert (= stored-update-event.updates.content.value "update-before") "returned update event must not mutate stored run history")
  (local session (get-projected-session store run.id))
  (local appended-item (. session.items 1))
  (local upserted-item (. session.items 2))
  (assert (= session.data.nested.value "created-before") "returned session-created event must not mutate stored history")
  (assert (= session.status :running) "returned status event mutation should not affect status projection")
  (assert (= appended-item.content.value "update-before") "returned append/update events must not mutate stored item history")
  (assert (= upserted-item.content.value "upsert-before") "returned upsert event must not mutate stored item history"))

(fn isolates-returned-events-from-stored-history []
  (with-temp-store assert-returned-events-are-isolated-from-history))

(table.insert tests {:name "projects-session-created-event-to-sidebar-session-shape"
                     :fn projects-session-created-event-to-sidebar-session-shape})
(table.insert tests {:name "projects-appended-message-items-in-order"
                     :fn projects-appended-message-items-in-order})
(table.insert tests {:name "projects-status-changes-with-latest-status"
                     :fn projects-status-changes-with-latest-status})
(table.insert tests {:name "upserts-existing-stream-item-with-stable-id"
                     :fn upserts-existing-stream-item-with-stable-id})
(table.insert tests {:name "updates-existing-item-fields"
                     :fn updates-existing-item-fields})
(table.insert tests {:name "rejects-duplicate-append-item-id"
                     :fn rejects-duplicate-append-item-id})
(table.insert tests {:name "rejects-update-for-missing-item-id"
                      :fn rejects-update-for-missing-item-id})
(table.insert tests {:name "preserves-run-identity-and-items-against-reserved-metadata"
                      :fn preserves-run-identity-and-items-against-reserved-metadata})
(table.insert tests {:name "projects-numeric-workflow-timestamps-as-canonical-strings"
                     :fn projects-numeric-workflow-timestamps-as-canonical-strings})
(table.insert tests {:name "rejects-present-malformed-event-timestamps"
                      :fn rejects-present-malformed-event-timestamps})
(table.insert tests {:name "isolates-nested-session-created-payloads-and-projections"
                      :fn isolates-nested-session-created-payloads-and-projections})
(table.insert tests {:name "isolates-nested-item-payloads-and-projections"
                     :fn isolates-nested-item-payloads-and-projections})
(table.insert tests {:name "isolates-nested-status-and-update-payloads"
                      :fn isolates-nested-status-and-update-payloads})
(table.insert tests {:name "isolates-returned-events-from-stored-history"
                     :fn isolates-returned-events-from-stored-history})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "agent-workflow-events"
                       :tests tests})))

{:name "agent-workflow-events"
 :tests tests
 :main main}
