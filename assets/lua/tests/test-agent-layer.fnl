;; Agent layer tests — session CRUD, turn lifecycle, approvals, tool surface, prompt utils, runner, SpaceAgent.
;; Run: SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-agent-layer:main

(local tests [])

;; ── Test helpers ──

(local fs (require :fs))
(local json (require :json))
(local Uuid (require :uuid))

(fn temp-dir []
  (local dir (fs.join-path "/tmp/space/tests/agent-layer" (Uuid.v4)))
  (when (not (fs.exists dir))
    (fs.create-dirs dir))
  dir)

(fn clean-dir [dir]
  (when (and dir (fs.exists dir))
    (fs.remove-all dir)))

(fn mock-tool-surface [fragments]
  {:prompt-fragments (fn [self] (or fragments []))})

;; ═══════════════════════════════════════
;; Session CRUD tests
;; ═══════════════════════════════════════

(fn test-session-create []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local session (SessionMod.create-session "test-agent" dir))
  (assert session "session should be created")
  (assert (= session.agent-id "test-agent") "session should have agent-id")
  (assert (= session.status :idle) "session should start idle")
  (assert (= (type session.id) "string") "session should have string id")
  (assert (= (type session.items) "table") "session should have items table")
  (assert (= (type session.data) "table") "session should have data table")
  (assert (= (type session.created-at) "number") "session should have created-at")
  (assert (= (type session.updated-at) "number") "session should have updated-at")
  ;; Verify persisted to disk
  (local path (fs.join-path dir (.. session.id ".json")))
  (assert (fs.exists path) "session should be persisted to disk")
  (clean-dir dir))

(fn test-session-load-and-cache []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local created (SessionMod.create-session "test-agent" dir))
  ;; Load from disk
  (local loaded (SessionMod.load-session created.id dir))
  (assert loaded "session should be loadable")
  (assert (= loaded.id created.id) "loaded session should have same id")
  (assert (= loaded.agent-id "test-agent") "loaded session should have same agent-id")
  ;; Should be cached
  (SessionMod.invalidate-cache created.id)
  (local reloaded (SessionMod.load-session created.id dir))
  (assert reloaded "session should be reloadable after cache invalidation")
  (assert (= reloaded.id created.id) "reloaded session should have same id")
  (clean-dir dir))

(fn test-session-load-missing []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local result (SessionMod.load-session "nonexistent-id" dir))
  (assert (= result nil) "loading nonexistent session should return nil")
  (clean-dir dir))

(fn test-session-load-corrupt-errors []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local session-id "agt-ses-corrupt")
  (fs.write-file (fs.join-path dir (.. session-id ".json")) "{")
  (local (ok err) (pcall SessionMod.load-session session-id dir))
  (assert (not ok) "corrupt session load should error")
  (assert (string.match (tostring err) "failed to parse agent session") "error should mention parse failure")
  (clean-dir dir))

(fn test-session-save-updates-timestamp []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local session (SessionMod.create-session "test-agent" dir))
  (local original-updated-at session.updated-at)
  (os.execute "sleep 1")  ;; ensure timestamp changes
  (SessionMod.update-session session {:status :busy})
  (SessionMod.save-session session dir)
  (assert (> (or session.updated-at 0) (or original-updated-at 0))
          "updated-at should be newer after save")
  (clean-dir dir))

(fn test-session-delete []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local session (SessionMod.create-session "test-agent" dir))
  (local path (fs.join-path dir (.. session.id ".json")))
  (assert (fs.exists path) "file should exist before delete")
  (SessionMod.delete-session session.id dir)
  (assert (not (fs.exists path)) "file should not exist after delete")
  ;; Loading should return nil after delete
  (local reloaded (SessionMod.load-session session.id dir))
  (assert (= reloaded nil) "loading deleted session should return nil")
  (clean-dir dir))

(fn test-session-list []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local s1 (SessionMod.create-session "agent-a" dir))
  (local s2 (SessionMod.create-session "agent-b" dir))
  (local items (SessionMod.list-sessions dir))
  (assert (>= (length items) 2) "should list at least 2 sessions")
  (var found-s1 false)
  (var found-s2 false)
  (each [_ entry (ipairs items)]
    (when (= entry.id s1.id) (set found-s1 true))
    (when (= entry.id s2.id) (set found-s2 true)))
  (assert found-s1 "should find session 1")
  (assert found-s2 "should find session 2")
  (clean-dir dir))

(fn test-session-list-empty-dir []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (clean-dir dir)
  (local items (SessionMod.list-sessions dir))
  (assert (= (type items) "table") "should return table")
  (assert (= (length items) 0) "should return empty list")
  (clean-dir dir))

(fn test-session-list-corrupt-errors []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (fs.write-file (fs.join-path dir "agt-ses-corrupt.json") "{")
  (local (ok err) (pcall SessionMod.list-sessions dir))
  (assert (not ok) "corrupt session list entry should error")
  (assert (string.match (tostring err) "failed to parse agent session list entry") "error should mention list parse failure")
  (clean-dir dir))

(fn test-session-append-item []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local session (SessionMod.create-session "test-agent" dir))
  (SessionMod.append-item session {:id "itm-1" :type "message" :role "user" :content "hello"})
  (assert (= (length session.items) 1) "should have 1 item")
  (local item1 (. session.items 1))
  (assert (= item1.id "itm-1") "item should have correct id")
  (assert (= item1.type "message") "item should have correct type")
  ;; Persist and reload
  (SessionMod.save-session session dir)
  (SessionMod.invalidate-cache session.id)
  (local loaded (SessionMod.load-session session.id dir))
  (assert (= (length loaded.items) 1) "reloaded session should have 1 item")
  (local loaded-item1 (. loaded.items 1))
  (assert (= loaded-item1.id "itm-1") "reloaded item should have correct id")
  (clean-dir dir))

(fn test-session-prunes-stale-input-echo-assistant-drafts []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local session-id "agt-ses-stale-echo")
  (fs.write-file (fs.join-path dir (.. session-id ".json"))
                 (json.dumps {:id session-id
                              :agent-id "space-agent"
                              :status "idle"
                              :created-at 1
                              :updated-at 1
                              :data {}
                              :items [{:id "itm-user"
                                       :type "message"
                                       :role "user"
                                       :content "draw a circle"}
                                      {:id "itm-assistant-echo"
                                       :type "message"
                                       :role "assistant"
                                       :content "draw a circle"
                                       :stream-status "streaming"}
                                      {:id "itm-assistant-real"
                                       :type "message"
                                       :role "assistant"
                                       :content "done"
                                       :stream-status "complete"}]}))
  (local loaded (SessionMod.load-session session-id dir))
  (assert (= (length loaded.items) 2)
          "load should prune stale assistant echo drafts")
  (assert (= (. loaded.items 1 :id) "itm-user")
          "user item should remain")
  (assert (= (. loaded.items 2 :id) "itm-assistant-real")
          "real assistant item should remain")
  (SessionMod.save-session loaded dir)
  (SessionMod.invalidate-cache session-id)
  (local reloaded (SessionMod.load-session session-id dir))
  (assert (= (length reloaded.items) 2)
          "save should persist the pruned transcript")
  (clean-dir dir))

(fn test-session-append-multiple-item-types []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local session (SessionMod.create-session "test-agent" dir))
  (SessionMod.append-item session {:id "itm-1" :type "message" :role "user" :content "draw"})
  (SessionMod.append-item session {:id "itm-2" :type "tool-call" :name "draw_shape" :arguments "{}" :call-id "call-1" :parent-id "itm-1"})
  (SessionMod.append-item session {:id "itm-3" :type "tool-result" :name "draw_shape" :output "ok" :call-id "call-1" :parent-id "itm-2"})
  (SessionMod.append-item session {:id "itm-4" :type "message" :role "assistant" :content "done" :parent-id "itm-3" :provider "opencode" :model "claude" :usage {:input-tokens 10 :output-tokens 20}})
  (SessionMod.append-item session {:id "itm-5" :type "event" :event-type "turn-started"})
  (SessionMod.append-item session {:id "itm-6" :type "error" :error "something went wrong"})
  (assert (= (length session.items) 6) "should have 6 items")
  ;; Check types preserved
  (local si1 (. session.items 1))
  (local si2 (. session.items 2))
  (local si3 (. session.items 3))
  (local si4 (. session.items 4))
  (local si5 (. session.items 5))
  (local si6 (. session.items 6))
  (assert (= si1.type "message"))
  (assert (= si2.type "tool-call"))
  (assert (= si2.call-id "call-1"))
  (assert (= si3.type "tool-result"))
  (assert (= si3.call-id "call-1"))
  (assert (= si4.type "message"))
  (assert (= si4.provider "opencode"))
  (assert (= si4.usage.input-tokens 10))
  (assert (= si5.type "event"))
  (assert (= si6.type "error"))
  (clean-dir dir))

(fn test-session-upsert-item []
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local session (SessionMod.create-session "test-agent" dir))
  (SessionMod.upsert-item session {:id "itm-live" :type "message" :role "assistant" :content "hel"})
  (assert (= (length session.items) 1) "upsert should append a missing item")
  (SessionMod.upsert-item session {:id "itm-live" :type "message" :role "assistant" :content "hello"})
  (assert (= (length session.items) 1) "upsert should update an existing item")
  (assert (= (. session.items 1 :content) "hello") "upsert should replace fields")
  (assert (. session.items 1 :updated-at) "upsert update should stamp updated-at")
  (clean-dir dir))

;; ═══════════════════════════════════════
;; Turn lifecycle tests
;; ═══════════════════════════════════════

(fn test-turn-pair-creation []
  (local TurnMod (require :llm/agent/turn))
  (local (handle controller) (TurnMod.TurnPair "ses-1" {}))
  (assert handle "handle should be created")
  (assert controller "controller should be created")
  (assert (= (type handle.id) "string") "handle should have string id")
  (assert (= handle.session-id "ses-1") "handle should have session-id")
  (assert (= (handle:status) :created) "initial status should be :created")
  (assert (not (handle:running?)) "should not be running initially"))

(fn test-turn-start-and-complete []
  (local TurnMod (require :llm/agent/turn))
  (var completed nil)
  (local (handle controller) (TurnMod.TurnPair "ses-1"
    {:on-complete (fn [result] (set completed result))}))
  (handle:start)
  (assert (= (handle:status) :running) "status should be :running after start")
  (assert (handle:running?) "should be running")
  (controller:finish {:content "done"})
  (assert (= (handle:status) :completed) "status should be :completed after finish")
  (assert (not (handle:running?)) "should not be running after completion")
  (assert completed "on-complete should have been called")
  (assert (= completed.result.content "done") "result should be passed to callback"))

(fn test-turn-fail []
  (local TurnMod (require :llm/agent/turn))
  (var error-received nil)
  (local (handle controller) (TurnMod.TurnPair "ses-1"
    {:on-error (fn [err] (set error-received err))}))
  (handle:start)
  (controller:fail "something broke")
  (assert (= (handle:status) :failed) "status should be :failed")
  (assert (= (handle:error) "something broke") "error should be stored")
  (assert error-received "on-error should have been called")
  (assert (= error-received.error "something broke") "error should match"))

(fn test-turn-cancel []
  (local TurnMod (require :llm/agent/turn))
  (var cancelled false)
  (local (handle controller) (TurnMod.TurnPair "ses-1"
    {:on-error (fn [err] (set cancelled true))}))
  (handle:start)
  (local result (handle:cancel))
  (assert result "cancel should return true")
  (assert (= (handle:status) :cancelled) "status should be :cancelled")
  (assert cancelled "on-error should have been called on cancel"))

(fn test-turn-cancel-invokes-registered-fn []
  (local TurnMod (require :llm/agent/turn))
  (var cancel-called false)
  (local (handle controller) (TurnMod.TurnPair "ses-1" {}))
  (controller:set-cancel (fn [] (set cancel-called true)))
  (handle:start)
  (handle:cancel)
  (assert cancel-called "registered cancel function should be invoked"))

(fn test-turn-cancel-surfaces-cancel-fn-error []
  (local TurnMod (require :llm/agent/turn))
  (var error-received nil)
  (local (handle controller) (TurnMod.TurnPair "ses-1"
    {:on-error (fn [err] (set error-received err))}))
  (controller:set-cancel (fn [] (error "abort failed")))
  (handle:start)
  (handle:cancel)
  (assert (= (handle:status) :cancelled) "turn should still be cancelled")
  (assert (string.match (handle:error) "cancel hook failed")
          "handle error should mention cancel hook failure")
  (assert (string.match error-received.error "abort failed")
          "on-error should surface cancel hook failure"))

(fn test-turn-cannot-finish-twice []
  (local TurnMod (require :llm/agent/turn))
  (var completion-count 0)
  (local (handle controller) (TurnMod.TurnPair "ses-1"
    {:on-complete (fn [r] (set completion-count (+ completion-count 1)))}))
  (handle:start)
  (controller:finish {:content "first"})
  (controller:finish {:content "second"})
  (assert (= completion-count 1) "on-complete should only fire once"))

(fn test-turn-fail-after-complete-noop []
  (local TurnMod (require :llm/agent/turn))
  (var error-count 0)
  (local (handle controller) (TurnMod.TurnPair "ses-1"
    {:on-error (fn [r] (set error-count (+ error-count 1)))}))
  (handle:start)
  (controller:finish {:content "done"})
  (controller:fail "late error")
  (assert (= error-count 0) "fail after finish should not fire on-error"))

(fn test-turn-cancelled?-flag []
  (local TurnMod (require :llm/agent/turn))
  (local (handle controller) (TurnMod.TurnPair "ses-1" {}))
  (handle:start)
  (assert (not (controller:cancelled?)) "should not be cancelled initially")
  (handle:cancel)
  (assert (controller:cancelled?) "should be cancelled after cancel"))

(fn test-turn-append-item-callback []
  (local TurnMod (require :llm/agent/turn))
  (var items [])
  (local (handle controller) (TurnMod.TurnPair "ses-1"
    {:on-item (fn [item] (table.insert items item))}))
  (handle:start)
  (controller:append-item {:id "itm-1" :type "message" :role "user" :content "hi"})
  (assert (= (length items) 1) "on-item should have been called")
  (local captured (. items 1))
  (assert (= captured.id "itm-1") "item should be passed through"))

;; ═══════════════════════════════════════
;; Registry tests
;; ═══════════════════════════════════════

(fn test-registry-register-and-get []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local reg (AgentRegistry {:deps {:app :stub}}))
  (reg:register "test-agent" (fn [deps] {:id "test-agent" :name "Test" :run (fn [] nil)}))
  (local agent (reg:get "test-agent"))
  (assert agent "agent should be retrievable")
  (assert (= agent.id "test-agent") "agent should have correct id"))

(fn test-registry-lazy-construction []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (var factory-called false)
  (local reg (AgentRegistry {:deps {}}))
  (reg:register "lazy-agent" (fn [deps] (set factory-called true) {:id "lazy-agent" :run (fn [] nil)}))
  (assert (not factory-called) "factory should not be called on register")
  (reg:get "lazy-agent")
  (assert factory-called "factory should be called on first get"))

(fn test-registry-get-unknown []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local reg (AgentRegistry {:deps {}}))
  (local result (reg:get "nonexistent"))
  (assert (= result nil) "getting unknown agent should return nil"))

(fn test-registry-list []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local reg (AgentRegistry {:deps {}}))
  (reg:register "alpha" (fn [d] {:id "alpha" :name "Alpha"}))
  (reg:register "beta" (fn [d] {:id "beta" :name "Beta"}))
  (local items (reg:list))
  (assert (= (length items) 2) "should list 2 agents")
  (assert (= (. items 1 :id) "alpha") "registry list should be sorted by id")
  (assert (= (. items 1 :name) "Alpha") "registry list should resolve display names")
  (assert (= (. items 2 :id) "beta") "registry list should keep deterministic order")
  (assert (= (. items 2 :name) "Beta") "registry list should resolve later display names")
  (var found-alpha false)
  (var found-beta false)
  (each [_ item (ipairs items)]
    (when (= item.id "alpha") (set found-alpha true))
    (when (= item.id "beta") (set found-beta true)))
  (assert found-alpha "should find alpha")
  (assert found-beta "should find beta"))

(fn test-registry-unregister []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local reg (AgentRegistry {:deps {}}))
  (reg:register "temp" (fn [d] {:id "temp"}))
  (assert (reg:get "temp") "should be registered")
  (reg:unregister "temp")
  (assert (= (reg:get "temp") nil) "should be nil after unregister"))

(fn test-registry-reregister-invalidates-cache []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (var call-count 0)
  (local reg (AgentRegistry {:deps {}}))
  (reg:register "agent-r" (fn [d] (set call-count (+ call-count 1)) {:id "agent-r" :version 1}))
  (local v1 (reg:get "agent-r"))
  (assert (= v1.version 1))
  (assert (= call-count 1))
  ;; Re-register with new factory
  (reg:register "agent-r" (fn [d] (set call-count (+ call-count 1)) {:id "agent-r" :version 2}))
  (local v2 (reg:get "agent-r"))
  (assert (= v2.version 2))
  (assert (= call-count 2) "factory should be called again after re-register"))

;; ═══════════════════════════════════════
;; Approvals tests
;; ═══════════════════════════════════════

(fn test-approvals-normal-always-approved []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals {:policy {}}))
  (assert (= (approvals:check-risk :normal) :approved) "normal risk should be auto-approved"))

(fn test-approvals-auto-policy []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals {:policy {:filesystem-read :auto}}))
  (assert (= (approvals:check-risk :filesystem-read) :approved) "auto policy should approve"))

(fn test-approvals-deny-policy []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals {:policy {:shell :deny}}))
  (assert (= (approvals:check-risk :shell) :denied) "deny policy should deny"))

(fn test-approvals-ask-default []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals {:policy {}}))
  (assert (= (approvals:check-risk :filesystem-write) :needs-approval)
          "high-risk without policy should need approval"))

(fn test-approvals-request-risk-auto []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (var approved-result nil)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (approvals:request-risk :normal "testing"
    {:on-approved (fn [r] (set approved-result r))
     :on-denied (fn [r] (set approved-result :denied))})
  (assert approved-result "callback should be called")
  (assert (= approved-result.risk :normal) "should report risk"))

(fn test-approvals-request-risk-needs-approval []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (var denied-result nil)
  (var approved-result nil)
  (var requested-result nil)
  (local approvals (AgentApprovals {:policy {:destructive :ask}}))
  (approvals.requested:connect
    (fn [request]
      (when request
        (set requested-result request))))
  (local result (approvals:request-risk :destructive "delete world"
    {:on-approved (fn [r] (set approved-result r))
     :on-denied (fn [r] (set denied-result r))}))
  (assert (= result false) "should return false when needs approval")
  (assert requested-result "pending request should be emitted")
  (assert requested-result.needs-approval "should indicate needs-approval")
  (assert (not denied-result) "on-denied should wait for explicit denial")
  (requested-result:approve)
  (assert approved-result "approve should resolve via on-approved"))

(fn test-approvals-approve-grants-one-matching-retry []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals {:policy {:shell :ask}}))
  (var pending nil)
  (approvals.requested:connect
    (fn [request]
      (when request
        (set pending request))))
  (local context {:tool "space_app_run_bash"
                  :source "app.run-bash"
                  :args_hash "hash-a"
                  :grant-on-approve true})
  (local first-result
    (approvals:request-risk :shell "space_app_run_bash requested shell access"
      {:on-approved (fn [_r] nil)
       :on-denied (fn [_r] nil)}
      context))
  (assert (= first-result false) "first ask-policy request should become pending")
  (assert (= (length (approvals:list-pending)) 1) "pending request should be listed")
  (pending:approve)
  (assert (= (length (approvals:list-pending)) 0) "approved request should leave pending list")
  (var approved-count 0)
  (approvals:request-risk :shell "space_app_run_bash requested shell access"
    {:on-approved (fn [_r] (set approved-count (+ approved-count 1)))
     :on-denied (fn [_r] nil)}
    context)
  (assert (= approved-count 1) "approval should grant one matching retry")
  (local third-result
    (approvals:request-risk :shell "space_app_run_bash requested shell access"
      {:on-approved (fn [_r] (set approved-count (+ approved-count 1)))
       :on-denied (fn [_r] nil)}
      context))
  (assert (= third-result false) "approval grant should be consumed after one retry"))

(fn test-approvals-exact-args-and-always-grants []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals {:policy {:shell :ask}}))
  (var pending nil)
  (approvals.requested:connect
    (fn [request]
      (when request
        (set pending request))))
  (local context-a {:tool "space_app_run_bash"
                    :source "app.run-bash"
                    :args_hash "hash-a"
                    :grant-on-approve true})
  (local context-b {:tool "space_app_run_bash"
                    :source "app.run-bash"
                    :args_hash "hash-b"
                    :grant-on-approve true})
  (approvals:request-risk :shell "run command"
    {:on-approved (fn [_r] nil)
     :on-denied (fn [_r] nil)}
    context-a)
  (assert pending "first request should create pending approval")
  (pending:approve {:always true})
  (var approved-a 0)
  (approvals:request-risk :shell "run command"
    {:on-approved (fn [_r] (set approved-a (+ approved-a 1)))
     :on-denied (fn [_r] nil)}
    context-a)
  (approvals:request-risk :shell "run command"
    {:on-approved (fn [_r] (set approved-a (+ approved-a 1)))
     :on-denied (fn [_r] nil)}
    context-a)
  (assert (= approved-a 2) "always approval should allow repeated exact matches")
  (local mismatch-result
    (approvals:request-risk :shell "run command"
      {:on-approved (fn [_r] (set approved-a (+ approved-a 1)))
       :on-denied (fn [_r] nil)}
      context-b))
  (assert (= mismatch-result false) "different args hash should require a new approval"))

(fn test-approvals-always-grants-persist []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local dir (temp-dir))
  (local grants-path (fs.join-path dir "approval-grants.json"))
  (local context {:tool "space_app_run_bash"
                  :source "app.run-bash"
                  :args_hash "hash-a"
                  :args_canonical "{\"cmd\":\"echo hi\"}"
                  :grant-on-approve true})
  (local first (AgentApprovals {:policy {:shell :ask}
                                :grants-path grants-path}))
  (var pending nil)
  (first.requested:connect
    (fn [request]
      (when request
        (set pending request))))
  (first:request-risk :shell "run command"
    {:on-approved (fn [_r] nil)
     :on-denied (fn [_r] nil)}
    context)
  (assert pending "first approvals instance should create pending request")
  (pending:approve {:always true})
  (local second (AgentApprovals {:policy {:shell :ask}
                                 :grants-path grants-path}))
  (var approved-count 0)
  (second:request-risk :shell "run command"
    {:on-approved (fn [_r] (set approved-count (+ approved-count 1)))
     :on-denied (fn [_r] nil)}
    context)
  (assert (= approved-count 1)
          "persistent always grant should approve matching request after reload")
  (clean-dir dir))

(fn test-approvals-denied-policy-does-not-consume-grant []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local policy {:shell :ask})
  (local approvals (AgentApprovals {:policy policy}))
  (local context {:tool "space_app_run_bash"
                  :source "app.run-bash"
                  :args_hash "hash-a"
                  :args_canonical "{\"cmd\":\"echo hi\"}"
                  :grant-on-approve true})
  (var pending nil)
  (approvals.requested:connect
    (fn [request]
      (when request
        (set pending request))))
  (approvals:request-risk :shell "run command"
    {:on-approved (fn [_r] nil)
     :on-denied (fn [_r] nil)}
    context)
  (assert pending "request should create pending approval")
  (pending:approve)
  (set policy.shell :deny)
  (var denied-count 0)
  (approvals:request-risk :shell "run command"
    {:on-approved (fn [_r] nil)
     :on-denied (fn [_r] (set denied-count (+ denied-count 1)))}
    context)
  (assert (= denied-count 1) "deny policy should deny without consuming grant")
  (set policy.shell :ask)
  (var approved-count 0)
  (approvals:request-risk :shell "run command"
    {:on-approved (fn [_r] (set approved-count (+ approved-count 1)))
     :on-denied (fn [_r] nil)}
    context)
  (assert (= approved-count 1)
          "one-time grant should still be available after denied policy check"))

(fn test-approvals-unknown-risk-asserts []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals {:policy {}}))
  (local (ok _err) (pcall approvals.check-risk approvals :made-up-risk))
  (assert (not ok) "unknown risk should assert"))

(fn test-approvals-record-decision []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals {:policy {}}))
  (approvals:record-decision {:risk :normal :reason "test" :decision :approved})
  (approvals:record-decision {:risk :shell :reason "test2" :decision :denied})
  ;; No direct access to decisions list, but no error means success
  (assert true))

(fn test-approvals-per-tool-auto-overrides-risk-ask []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals
                     {:policy {:shell {:default :ask
                                       :tools {:unit.create :auto}}}}))
  (local context {:tool "space_unit_create" :source "unit.create"})
  (assert (= (approvals:check-risk :shell context) :approved)
          "per-tool auto should override shell ask"))

(fn test-approvals-per-tool-deny-overrides-risk-auto []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals
                     {:policy {:shell {:default :auto
                                       :tools {:unit.create :deny}}}}))
  (local context {:tool "space_unit_create" :source "unit.create"})
  (assert (= (approvals:check-risk :shell context) :denied)
          "per-tool deny should override shell auto"))

(fn test-approvals-per-tool-unmatched-falls-back-to-default []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals
                     {:policy {:shell {:default :ask
                                       :tools {:unit.create :auto}}}}))
  (local context {:tool "space_app_run_bash" :source "app.run-bash"})
  (assert (= (approvals:check-risk :shell context) :needs-approval)
          "unmatched tool should fall back to default :ask"))

(fn test-approvals-per-tool-unmatched-falls-back-to-auto-default []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals
                     {:policy {:shell {:default :auto
                                       :tools {:unit.create :auto}}}}))
  (local context {:tool "space_app_run_bash" :source "app.run-bash"})
  (assert (= (approvals:check-risk :shell context) :approved)
          "unmatched tool should fall back to default :auto"))

(fn test-approvals-per-tool-nil-context-falls-back []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals
                     {:policy {:shell {:default :ask
                                       :tools {:unit.create :auto}}}}))
  (assert (= (approvals:check-risk :shell) :needs-approval)
          "nil context should fall back to :needs-approval"))

(fn test-approvals-per-tool-table-without-default []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals
    (AgentApprovals {:policy {:shell {:tools {:unit.create :auto}}}}))
  (local context {:tool "space_unit_create" :source "unit.create"})
  (assert (= (approvals:check-risk :shell context) :approved)
          "table without default should use .tools entry and return :approved")
  (local context2 {:tool "space_app_run_bash" :source "app.run-bash"})
  (assert (= (approvals:check-risk :shell context2) :needs-approval)
          "table without default should fall back to :ask for unmatched tools"))

(fn test-approvals-per-tool-plain-risk-value-still-works []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local approvals (AgentApprovals {:policy {:shell :auto}}))
  (local context {:tool "space_app_run_bash" :source "app.run-bash"})
  (assert (= (approvals:check-risk :shell context) :approved)
          "plain risk value should still auto-approve"))

(fn test-approvals-per-tool-request-risk-auto-resolves []
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (var approved? false)
  (var denied? false)
  (local approvals (AgentApprovals
                     {:policy {:shell {:default :ask
                                       :tools {:unit.create :auto}}}}))
  (local context {:tool "space_unit_create"
                  :source "unit.create"
                  :grant-on-approve true})
  (approvals:request-risk :shell "create unit"
    {:on-approved (fn [_r] (set approved? true))
     :on-denied (fn [_r] (set denied? true))}
    context)
  (assert approved? "per-tool auto should fire on-approved synchronously")
  (assert (not denied?) "per-tool auto should not fire on-denied")
  (assert (= (# (approvals:list-pending)) 0)
          "per-tool auto should not create a pending request"))

;; ═══════════════════════════════════════
;; Tool surface tests
;; ═══════════════════════════════════════

(fn test-tool-surface-active-presets []
  (local {: AgentToolSurface} (require :llm/agent/tool-surface))
  (local mock-presets
    {:get-active-presets (fn [] [{:name "drawing-shape-tools" :reason "auto"}])})
  (local mock-mcp-tools {})
  (local mock-approvals {:check-risk (fn [self risk context] :approved)})
  (local surface (AgentToolSurface {:presets mock-presets
                                     :mcp-tools mock-mcp-tools
                                     :approvals mock-approvals}))
  (local presets (surface:active-presets))
  (assert (= (length presets) 1) "should have 1 active preset")
  (local first-preset (. presets 1))
  (assert (= first-preset.name "drawing-shape-tools") "should have correct name"))

(fn test-tool-surface-openai-tools []
  (local {: AgentToolSurface} (require :llm/agent/tool-surface))
  (local input-schema {:type "object" :properties {:x {:type "number"}}})
  (local mock-def {:name "space_test_tool"
                   :description "A test tool"
                   :inputSchema input-schema
                   :managed-source "tool-test"})
  (local mock-presets
    {:get-tool-defs (fn [] [mock-def])
     :get-active-presets (fn [] [{:name "test-preset"
                                  :reason :context
                                  :risk :normal
                                  :tool-ids ["tool-test"]}])
     :get-prompt-fragments (fn [] [])})
  (local mock-mcp-tools {})
  (local mock-approvals {:check-risk (fn [self risk context] :approved)})
  (local surface (AgentToolSurface {:presets mock-presets
                                     :mcp-tools mock-mcp-tools
                                     :approvals mock-approvals}))
  (local tools (surface:openai-tools))
  (assert (= (length tools) 2) "should include approval tool plus active tool")
  (local by-name {})
  (each [_ tool (ipairs tools)]
    (set (. by-name tool.name) tool))
  (assert by-name.space_agent_request_tool_approval "approval request tool should be exposed")
  (local target-tool by-name.space_test_tool)
  (assert target-tool "active tool should be exposed")
  (assert (= target-tool.type "function") "should be function type")
  (assert (= target-tool.description "A test tool") "should have correct description")
  (assert target-tool.parameters "should have parameters"))

(fn test-tool-surface-mcp-defs []
  (local {: AgentToolSurface} (require :llm/agent/tool-surface))
  (local mock-def {:name "space_test" :description "test" :inputSchema {} :run (fn []) :managed-source "tool-test"})
  (local mock-presets
    {:get-tool-defs (fn [] [mock-def])
     :get-active-presets (fn [] [{:name "test-preset" :reason :context :risk :normal :tool-ids ["tool-test"]}])
     :get-prompt-fragments (fn [] [])})
  (local mock-mcp-tools {})
  (local mock-approvals {:check-risk (fn [self risk context] :approved)})
  (local surface (AgentToolSurface {:presets mock-presets
                                     :mcp-tools mock-mcp-tools
                                     :approvals mock-approvals}))
  (local defs (surface:mcp-tool-defs))
  (assert (= (length defs) 2) "should include approval tool plus active def")
  (local by-name {})
  (each [_ def (ipairs defs)]
    (set (. by-name def.name) def))
  (assert by-name.space_agent_request_tool_approval "approval request def should be present")
  (assert by-name.space_test "active def should be present"))

(fn test-tool-surface-call-runs-active-tool []
  (local {: AgentToolSurface} (require :llm/agent/tool-surface))
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (var call-log nil)
  (local mock-def {:name "space_draw_circle"
                   :description "draw"
                   :inputSchema {}
                   :managed-source "draw-circle"
                   :run (fn [args]
                          (set call-log {:name "space_draw_circle" :args args})
                          "ok")})
  (local mock-presets
    {:get-tool-defs (fn [] [mock-def])
     :get-active-presets (fn [] [{:name "drawing" :reason :context :risk :normal :tool-ids ["draw-circle"]}])
     :get-prompt-fragments (fn [] [])})
  (local mock-approvals (AgentApprovals {:policy {:normal :auto}}))
  (local surface (AgentToolSurface {:presets mock-presets
                                     :mcp-tools {}
                                     :approvals mock-approvals}))
  (surface:call "space_draw_circle" {:radius 10})
  (assert call-log "call should have been dispatched")
  (assert (= call-log.name "space_draw_circle") "should call correct tool")
  (assert (= call-log.args.radius 10) "should pass args"))

(fn test-tool-surface-call-per-tool-auto-policy []
  (local {: AgentToolSurface} (require :llm/agent/tool-surface))
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (var called false)
  (local mock-def {:name "space_unit_create"
                   :description "create unit"
                   :inputSchema {}
                   :managed-source "unit.create"
                   :run (fn [_args]
                          (set called true)
                          "created")})
  (local mock-presets
    {:get-tool-defs (fn [] [mock-def])
     :get-active-presets (fn [] [{:name "units-create-tools" :risk :shell :tool-ids ["unit.create"]}])
     :get-prompt-fragments (fn [] [])})
  (local approvals (AgentApprovals
                     {:policy {:shell {:default :ask
                                       :tools {:unit.create :auto}}}}))
  (var pending nil)
  (approvals.requested:connect
    (fn [request] (when request (set pending request))))
  (local surface (AgentToolSurface {:presets mock-presets
                                     :mcp-tools {}
                                     :approvals approvals}))
  (local result (surface:call "space_unit_create" {:source "(+ 1 2)"}))
  (assert (= result "created") "auto-approved per-tool call should execute synchronously")
  (assert called "auto-approved tool should run")
  (assert (not pending) "auto-approved tool should not create a pending approval request"))

(fn test-tool-surface-exposes-and-gates-ask-risk []
  (local {: AgentToolSurface} (require :llm/agent/tool-surface))
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (var called false)
  (local mock-def {:name "space_shell"
                   :description "shell"
                   :inputSchema {}
                   :managed-source "shell-tool"
                   :run (fn [_args]
                          (set called true)
                          "ran")})
  (local mock-presets
    {:get-tool-defs (fn [] [mock-def])
     :get-active-presets (fn [] [{:name "shell-preset" :reason :override :risk :shell :tool-ids ["shell-tool"]}])
     :get-prompt-fragments (fn [] [])})
  (local approvals (AgentApprovals {:policy {:shell :ask}}))
  (var pending nil)
  (approvals.requested:connect
    (fn [request]
      (when request
        (set pending request))))
  (local surface (AgentToolSurface {:presets mock-presets
                                     :mcp-tools {}
                                     :approvals approvals}))
  (assert (= (length (surface:mcp-tool-defs)) 2) "ask-risk tool and approval tool should be exposed")
  (local (ok err) (pcall (fn [] (surface:call "space_shell" {}))))
  (assert (not ok) "ask-risk tool call should error while approval is pending")
  (assert (string.match (tostring err) "approval_required") "error should explain pending approval")
  (assert pending "tool call should create a pending approval request")
  (assert pending.args_hash "pending approval should include exact args hash")
  (assert (not called) "pending high-risk tool should not execute")
  (pending:approve)
  (local retry-result (surface:call "space_shell" {}))
  (assert (= retry-result "ran") "approved matching retry should execute")
  (assert called "approved retry should call the underlying tool"))

(fn test-tool-surface-request-approval-tool-grants-exact-call []
  (local {: AgentToolSurface} (require :llm/agent/tool-surface))
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (var call-count 0)
  (local mock-def {:name "space_shell"
                   :description "shell"
                   :inputSchema {:type "object" :properties {:cmd {:type "string"}}}
                   :managed-source "shell-tool"
                   :run (fn [_args]
                          (set call-count (+ call-count 1))
                          "ran")})
  (local mock-presets
    {:get-tool-defs (fn [] [mock-def])
     :get-active-presets (fn [] [{:name "shell-preset" :reason :override :risk :shell :tool-ids ["shell-tool"]}])
     :get-prompt-fragments (fn [] [])})
  (local approvals (AgentApprovals {:policy {:shell :ask}}))
  (var pending nil)
  (approvals.requested:connect
    (fn [request]
      (when request
        (set pending request))))
  (local surface (AgentToolSurface {:presets mock-presets
                                     :mcp-tools {}
                                     :approvals approvals}))
  (local approval-json
    (surface:call "space_agent_request_tool_approval"
                  {:tool "space_shell"
                   :arguments {:cmd "echo hi"}
                   :reason "run the requested command"}))
  (local approval-result (json.loads approval-json))
  (assert (= approval-result.status "approval_required")
          "request approval tool should create an approval request")
  (assert pending "approval request should be pending")
  (assert (= pending.args_hash approval-result.args_hash)
          "pending request and response should share args hash")
  (local (direct-ok direct-err) (pcall (fn [] (surface:call "space_shell" {:cmd "echo hi"}))))
  (assert (not direct-ok) "direct exact call should still wait for approval")
  (assert (string.find (tostring direct-err) approval-result.request_id 1 true)
          "direct exact call should report the existing approval request id")
  (pending:approve)
  (assert (= (surface:call "space_shell" {:cmd "echo hi"}) "ran")
          "approved exact call should run")
  (local (ok _err) (pcall (fn [] (surface:call "space_shell" {:cmd "echo bye"}))))
  (assert (not ok) "different arguments should require a separate approval")
  (assert (= call-count 1) "only the approved exact call should run"))

(fn test-tool-surface-request-approval-normalizes-opencode-prefix []
  (local {: AgentToolSurface} (require :llm/agent/tool-surface))
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (local mock-def {:name "space_shell"
                   :description "shell"
                   :inputSchema {:type "object" :properties {:cmd {:type "string"}}}
                   :managed-source "shell-tool"
                   :run (fn [_args] "ran")})
  (local mock-presets
    {:get-tool-defs (fn [] [mock-def])
     :get-active-presets (fn [] [{:name "shell-preset" :reason :override :risk :shell :tool-ids ["shell-tool"]}])
     :get-prompt-fragments (fn [] [])})
  (local approvals (AgentApprovals {:policy {:shell :ask}}))
  (var pending nil)
  (approvals.requested:connect
    (fn [request]
      (when request
        (set pending request))))
  (local surface (AgentToolSurface {:presets mock-presets
                                     :mcp-tools {}
                                     :approvals approvals}))
  (local approval-json
    (surface:call "space_agent_request_tool_approval"
                  {:tool "space_space_shell"
                   :arguments {:cmd "echo hi"}
                   :reason "run the requested command"}))
  (local approval-result (json.loads approval-json))
  (assert (= approval-result.status "approval_required")
          "request approval tool should create an approval request")
  (assert pending "approval request should be pending")
  (assert (= pending.tool "space_shell") "pending approval should use raw tool name"))

(fn test-tool-surface-call-async-immediate []
  (local {: AgentToolSurface} (require :llm/agent/tool-surface))
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (var called false)
  (local mock-def {:name "space_normal"
                   :description "normal"
                   :inputSchema {}
                   :managed-source "normal-tool"
                   :run (fn [_args]
                          (set called true)
                          "done")})
  (local mock-presets
    {:get-tool-defs (fn [] [mock-def])
     :get-active-presets (fn [] [{:name "normal-preset" :risk :normal :tool-ids ["normal-tool"]}])
     :get-prompt-fragments (fn [] [])})
  (local approvals (AgentApprovals {}))
  (local surface (AgentToolSurface {:presets mock-presets
                                     :mcp-tools {}
                                     :approvals approvals}))
  (var captured nil)
  (local status (surface:call-async "space_normal" {}
                                    (fn [result] (set captured result))))
  (assert (= status :completed) "normal risk should complete synchronously")
  (assert captured "on-result should have been called")
  (assert (= captured.type :success) "immediate tool should succeed")
  (assert (= captured.value "done") "immediate tool should return value")
  (assert called "tool should have executed"))

(table.insert tests {:name "tool surface call-async immediate" :fn test-tool-surface-call-async-immediate})

(fn test-tool-surface-call-async-pending-approval []
  (local {: AgentToolSurface} (require :llm/agent/tool-surface))
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (var called false)
  (local mock-def {:name "space_shell"
                   :description "shell"
                   :inputSchema {}
                   :managed-source "shell-tool"
                   :run (fn [_args]
                          (set called true)
                          "ran")})
  (local mock-presets
    {:get-tool-defs (fn [] [mock-def])
     :get-active-presets (fn [] [{:name "shell-preset" :risk :shell :tool-ids ["shell-tool"]}])
     :get-prompt-fragments (fn [] [])})
  (local approvals (AgentApprovals {:policy {:shell :ask}}))
  (var pending nil)
  (approvals.requested:connect
    (fn [request]
      (when request
        (set pending request))))
  (local surface (AgentToolSurface {:presets mock-presets
                                     :mcp-tools {}
                                     :approvals approvals}))
  (var captured nil)
  (local status (surface:call-async "space_shell" {}
                                     (fn [result] (set captured result))))
  (assert (= status :completed) "ask risk should return approval_required immediately")
  (assert pending "tool call should create a pending approval request")
  (assert (not called) "pending high-risk tool should not execute")
  (assert captured "on-result should be called immediately")
  (assert (= captured.type :error) "approval-required direct call should be an error result")
  (assert (string.find captured.message "approval_required") "result should mention approval_required")
  (pending:approve)
  (set captured nil)
  (local retry-status (surface:call-async "space_shell" {}
                                          (fn [result] (set captured result))))
  (assert (= retry-status :completed) "approved retry should complete synchronously")
  (assert (= captured.type :success) "approved retry should succeed")
  (assert (= captured.value "ran") "approved retry should return value")
  (assert called "tool should execute after approve"))

(table.insert tests {:name "tool surface call-async pending approval" :fn test-tool-surface-call-async-pending-approval})

(fn test-tool-surface-call-async-cancelled-before-approval []
  (local {: AgentToolSurface} (require :llm/agent/tool-surface))
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (var called false)
  (local mock-def {:name "space_shell"
                   :description "shell"
                   :inputSchema {}
                   :managed-source "shell-tool"
                   :run (fn [_args]
                          (set called true)
                          "ran")})
  (local mock-presets
    {:get-tool-defs (fn [] [mock-def])
     :get-active-presets (fn [] [{:name "shell-preset" :risk :shell :tool-ids ["shell-tool"]}])
     :get-prompt-fragments (fn [] [])})
  (local approvals (AgentApprovals {:policy {:shell :ask}}))
  (var pending nil)
  (approvals.requested:connect
    (fn [request]
      (when request
        (set pending request))))
  (local surface (AgentToolSurface {:presets mock-presets
                                     :mcp-tools {}
                                     :approvals approvals}))
  (var captured nil)
  (var cancelled false)
  (local cancelled? (fn [] cancelled))
  (local status (surface:call-async "space_shell" {}
                                    (fn [result] (set captured result))
                                    cancelled?))
  (assert (= status :completed) "ask risk should return approval_required immediately")
  (assert pending "tool call should create a pending approval request")
  (assert (not called) "pending high-risk tool should not execute")
  (assert captured "on-result should have been called immediately")
  (assert (= captured.type :error) "direct pending approval should return an error result")
  (assert (string.find captured.message "approval_required") "error should mention approval_required")
  ;; Simulate SSE disconnect before approval. The original request has already completed,
  ;; so approval only grants a future retry and must not run the old call.
  (set cancelled true)
  (pending:approve)
  (assert (not called) "cancelled tool should not execute after approval")
  (assert (= captured.type :error) "original request should remain approval_required"))

(table.insert tests {:name "tool surface call-async cancelled before approval" :fn test-tool-surface-call-async-cancelled-before-approval})

(fn test-tool-surface-call-async-denied []
  (local {: AgentToolSurface} (require :llm/agent/tool-surface))
  (local {: AgentApprovals} (require :llm/agent/approvals))
  (var called false)
  (local mock-def {:name "space_shell"
                   :description "shell"
                   :inputSchema {}
                   :managed-source "shell-tool"
                   :run (fn [_args]
                          (set called true)
                          "ran")})
  (local mock-presets
    {:get-tool-defs (fn [] [mock-def])
     :get-active-presets (fn [] [{:name "shell-preset" :risk :shell :tool-ids ["shell-tool"]}])
     :get-prompt-fragments (fn [] [])})
  (local approvals (AgentApprovals {:policy {:shell :deny}}))
  (local surface (AgentToolSurface {:presets mock-presets
                                     :mcp-tools {}
                                     :approvals approvals}))
  (var captured nil)
  (local status (surface:call-async "space_shell" {}
                                    (fn [result] (set captured result))))
  (assert (= status :completed) "deny policy should complete synchronously")
  (assert captured "on-result should have been called")
  (assert (= captured.type :error) "denied tool should return error")
  (assert (string.find captured.message "denied") "error should mention denied")
  (assert (not called) "denied tool should not execute"))

(table.insert tests {:name "tool surface call-async denied" :fn test-tool-surface-call-async-denied})

(fn test-tool-registry-call-async-delegates-to-run-async []
  (local ToolRegistry (require :mcp/tool-registry))
  (local registry (ToolRegistry))
  (var async-called false)
  (registry:register {:name "test-async"
                      :description "async tool"
                      :inputSchema {:type "object" :properties {}}
                      :run (fn [] "sync-result")
                      :run-async (fn [args on-result]
                                   (set async-called true)
                                   (on-result {:type :success :value "async-result"})
                                   :completed)})
  (var captured nil)
  (local status (registry:call-async "test-async" {}
                                     (fn [result] (set captured result))))
  (assert (= status :completed))
  (assert async-called "should use run-async when available")
  (assert (= captured.type :success))
  (assert (= captured.value "async-result")))

(table.insert tests {:name "tool registry call-async delegates to run-async" :fn test-tool-registry-call-async-delegates-to-run-async})

(fn test-tool-registry-call-async-unknown-tool []
  (local ToolRegistry (require :mcp/tool-registry))
  (local registry (ToolRegistry))
  (var captured nil)
  (local status (registry:call-async "nonexistent" {}
                                     (fn [result] (set captured result))))
  (assert (= status :completed) "unknown tool should complete synchronously with error")
  (assert captured "on-result should have been called")
  (assert (= captured.type :error) "unknown tool should return error")
  (assert (string.find (or captured.message "") "Unknown tool") "error should mention unknown"))

(table.insert tests {:name "tool registry call-async unknown tool" :fn test-tool-registry-call-async-unknown-tool})

(fn test-mcp-handler-async-tool-call-pending []
  (local ToolRegistry (require :mcp/tool-registry))
  (local MCPHTTPHandler (require :mcp/handler))
  (local protocol (require :mcp/protocol))
  (local json (require :json))
  (var captured-on-result nil)
  (var sse-messages [])
  (local tools (ToolRegistry))
  (tools:register
    {:name "test-async"
     :description "async"
     :inputSchema {:type "object" :properties {}}
     :run (fn [] "sync-fallback")
     :run-async (fn [args on-result]
                  (set captured-on-result on-result)
                  {:pending true})})
  (local handler (MCPHTTPHandler {:tools tools}))
  ;; Initialize MCP session
  (local init-req
    {:body (json.dumps {:jsonrpc "2.0" :id 1 :method "initialize"
                        :params {:protocolVersion "2025-03-26"
                                 :capabilities {}
                                 :clientInfo {:name "test" :version "1.0"}}})
     :headers {}
     :query_params {}})
  (local init-resp (handler.handle-post init-req))
  (local session-id-header (. (or init-resp.headers {}) :mcp-session-id))
  (assert session-id-header "initialize should return session id")
  ;; Call async tool
  (local mock-stream
    {:send (fn [_self data] (table.insert sse-messages data))
     :close (fn [])})
  (local req
    {:body (json.dumps {:jsonrpc "2.0" :id 42 :method "tools/call"
                        :params {:name "test-async" :arguments {:x 1}}})
     :headers {:mcp-session-id session-id-header}
     :query_params {}})
  (local resp (handler.handle-post req mock-stream))
  (assert (= resp.status 202) "handler should return accepted")
  (assert (= resp.body "") "accepted body should be empty")
  (assert resp.on-disconnect "pending call should have on-disconnect callback")
  (assert (not (not captured-on-result)) "should have captured on-result callback")
  (assert (= (# sse-messages) 0) "SSE should not have been sent yet")
  (captured-on-result {:type :success :value "approved"})
  (assert (= (# sse-messages) 1) "SSE should have been sent after callback")
  (local sse-text (. sse-messages 1))
  (local json-start (+ (string.find sse-text "data: ") 5))
  (local json-end (string.find sse-text "\n\n" json-start))
  (local json-body (string.sub sse-text json-start (- json-end 1)))
  (local parsed (json.loads json-body))
  (assert (= parsed.jsonrpc "2.0"))
  (assert (= parsed.id 42))
  (assert (not parsed.result.isError))
  (local content-item (. (. parsed.result :content) 1))
  (assert (= (. content-item :text) "approved"))
  (pcall captured-on-result {:type :success :value "double"})
  (assert (= (# sse-messages) 1) "deliver should be idempotent, no extra SSE messages"))

(table.insert tests {:name "mcp handler async tool call pending" :fn test-mcp-handler-async-tool-call-pending})

(fn test-mcp-handler-async-tool-call-cancelled []
  (local ToolRegistry (require :mcp/tool-registry))
  (local MCPHTTPHandler (require :mcp/handler))
  (local json (require :json))
  (var captured-on-result nil)
  (var sse-messages [])
  (local tools (ToolRegistry))
  (tools:register
    {:name "test-cancel"
     :description "cancellable"
     :inputSchema {:type "object" :properties {}}
     :run (fn [] "sync")
     :run-async (fn [args on-result]
                  (set captured-on-result on-result)
                  {:pending true})})
  (local handler (MCPHTTPHandler {:tools tools}))
  ;; Initialize MCP session
  (local init-req
    {:body (json.dumps {:jsonrpc "2.0" :id 1 :method "initialize"
                        :params {:protocolVersion "2025-03-26"
                                 :capabilities {}
                                 :clientInfo {:name "test" :version "1.0"}}})
     :headers {}
     :query_params {}})
  (local init-resp (handler.handle-post init-req))
  (local session-id-header (. (or init-resp.headers {}) :mcp-session-id))
  (assert session-id-header "initialize should return session id")
  ;; Call async tool
  (local mock-stream
    {:send (fn [_self data] (table.insert sse-messages data))
     :close (fn [])})
  (local req
    {:body (json.dumps {:jsonrpc "2.0" :id 1 :method "tools/call"
                        :params {:name "test-cancel" :arguments {}}})
     :headers {:mcp-session-id session-id-header}
     :query_params {}})
  (local resp (handler.handle-post req mock-stream))
  (assert resp.on-disconnect "pending call should have on-disconnect")
  (resp.on-disconnect)
  (captured-on-result {:type :success :value "should-not-appear"})
  (assert (= (# sse-messages) 0) "SSE should not be sent after disconnect"))

(table.insert tests {:name "mcp handler async tool call cancelled" :fn test-mcp-handler-async-tool-call-cancelled})

(fn test-mcp-handler-async-tool-call-cleanup-on-complete []
  (local ToolRegistry (require :mcp/tool-registry))
  (local MCPHTTPHandler (require :mcp/handler))
  (local json (require :json))
  (var captured-on-result nil)
  (var sse-messages [])
  (local tools (ToolRegistry))
  (tools:register
    {:name "test-cleanup"
     :description "cleanup"
     :inputSchema {:type "object" :properties {}}
     :run (fn [] "sync")
     :run-async (fn [args on-result]
                  (set captured-on-result on-result)
                  {:pending true})})
  (local handler (MCPHTTPHandler {:tools tools}))
  ;; Initialize MCP session
  (local init-req
    {:body (json.dumps {:jsonrpc "2.0" :id 1 :method "initialize"
                        :params {:protocolVersion "2025-03-26"
                                 :capabilities {}
                                 :clientInfo {:name "test" :version "1.0"}}})
     :headers {}
     :query_params {}})
  (local init-resp (handler.handle-post init-req))
  (local session-id-header (. (or init-resp.headers {}) :mcp-session-id))
  (assert session-id-header "initialize should return session id")
  ;; Call async tool
  (local mock-stream
    {:send (fn [_self data] (table.insert sse-messages data))
     :close (fn [])})
  (local req
    {:body (json.dumps {:jsonrpc "2.0" :id 1 :method "tools/call"
                        :params {:name "test-cleanup" :arguments {}}})
     :headers {:mcp-session-id session-id-header}
     :query_params {}})
  (local resp (handler.handle-post req mock-stream))
  (assert resp.on-disconnect "pending call should have on-disconnect callback")
  (assert resp.on-complete "pending call should have on-complete callback")
  ;; Simulate server wrapping: store cleanup in a table
  (var pending-callbacks {})
  (local cancel-fn resp.on-disconnect)
  (local cleanup
    (fn []
      (set pending-callbacks {})
      (cancel-fn)))
  (set pending-callbacks.cleanup cleanup)
  (tset resp :on-disconnect cleanup)
  (tset resp :on-complete cleanup)
  ;; Deliver result (normal completion)
  (captured-on-result {:type :success :value "cleanup-test"})
  (assert (= (# sse-messages) 1) "SSE should have been sent")
  ;; Server-style pending-callbacks table should be empty after cleanup
  (assert (not (. pending-callbacks :cleanup))
          "cleanup callback should self-remove after normal completion"))

(table.insert tests {:name "mcp handler async tool call cleanup on complete" :fn test-mcp-handler-async-tool-call-cleanup-on-complete})

;; ═══════════════════════════════════════
;; Agent MCP sync tests
;; ═══════════════════════════════════════

(fn test-agent-mcp-sync-registers-surface-tools []
  (local {: AgentMcpSync} (require :llm/agent/mcp-sync))
  (local ToolRegistry (require :mcp/tool-registry))
  (var defs [{:name "space_agent_echo"
              :description "Echo test tool"
              :inputSchema {:type "object" :properties {}}
              :managed-source "agent.echo"
              :run (fn [] "ok")}])
  (local surface {:mcp-tool-defs (fn [self] defs)})
  (local tool-reg (ToolRegistry {:namespace-prefix "space_"}))
  (local sync (AgentMcpSync {:surface surface
                             :tool-registry tool-reg
                             :owner "test-agent"}))
  (sync:start)
  (local tools (tool-reg:list))
  (assert (= (# tools) 1) "surface tool should be registered")
  (assert (= (. tools 1 :name) "space_agent_echo") "registered tool name should match")
  (set defs [])
  (sync:sync)
  (assert (= (# (tool-reg:list)) 0) "removed surface tool should be unregistered")
  (sync:stop))

(fn test-agent-mcp-sync-does-not_bypass_surface_gating []
  (local {: AgentMcpSync} (require :llm/agent/mcp-sync))
  (local ToolRegistry (require :mcp/tool-registry))
  (local surface {:mcp-tool-defs (fn [self] [])})
  (local tool-reg (ToolRegistry {:namespace-prefix "space_"}))
  (local sync (AgentMcpSync {:surface surface
                             :tool-registry tool-reg
                             :owner "test-agent"}))
  (sync:start)
  (assert (= (# (tool-reg:list)) 0) "agent MCP sync should expose only surface-approved tools")
  (sync:stop))

(fn test-opencode-mcp-bridge-starts-and-writes-config []
  (local {: AgentOpencodeMcpBridge} (require :llm/agent/opencode-mcp-bridge))
  (local ToolRegistry (require :mcp/tool-registry))
  (local dir (temp-dir))
  (local space-data-dir (fs.join-path dir "space-data")) (local space-cache-dir (fs.join-path dir "space-cache")) (local code-dir (fs.join-path space-data-dir "code")) (local artifact-root (fs.join-path space-data-dir "agent-artifacts"))
  (local tool-reg (ToolRegistry {:namespace-prefix "space_"})) (local bridge (AgentOpencodeMcpBridge {:tools tool-reg :data-dir dir :space-data-dir space-data-dir :space-cache-dir space-cache-dir :code-dir code-dir :artifact-root artifact-root}))
  (bridge:start) (local status (bridge:status)) (assert status.started? "bridge should report started")
  (assert (> status.port 0) "bridge should bind a port") (assert (= status.artifact-root artifact-root) "bridge status should report artifact root") (assert (fs.exists artifact-root) "bridge should ensure artifact root exists") (assert (= (bridge:config-path) status.config-path) "bridge should expose config path")
  (local env (bridge:opencode-env)) (assert (= env.XDG_CONFIG_HOME status.config-root) "OpenCode env should point to bridge config root") (local config (json.loads (fs.read-file status.config-path)))
  (assert (= config.mcp.space.type "remote") "config should create remote MCP server")
  (assert (= config.mcp.space.url status.url) "config URL should match bridge URL") (assert (= config.mcp.space.enabled true) "config should enable MCP server")
  (each [_ name (ipairs ["invalid" "write" "edit" "bash" "task" "todowrite" "webfetch" "websearch" "lsp" "skill" "question"])] (assert (= (. config.permission name) "deny") (.. "config should deny native OpenCode tool: " name)))
  (fn slash-path [path] (string.gsub path "\\" "/")) (fn permission-value [permissions expected-pattern] (var found nil) (each [pattern value (pairs permissions)] (when (= (slash-path pattern) (slash-path expected-pattern)) (set found value))) found)
  (fn assert-pattern-permission [permissions expected-pattern expected-value message] (assert (= (permission-value permissions expected-pattern) expected-value) message)) (local allowed-patterns [(.. space-data-dir "/agent-sessions/**") (.. space-data-dir "/agent-opencode/**") (.. space-data-dir "/agent-approvals/**") (.. space-data-dir "/agent-artifacts/**") (.. space-data-dir "/code/**") (.. space-cache-dir "/log/**")])
  ;; Nested secret deny patterns are derived per allowed root and marker below.
  (fn assert-bounded-tool [tool-name]
    (local permissions (. config.permission tool-name)) (assert (= (type permissions) "table") (.. tool-name " should use bounded permission patterns")) (assert-pattern-permission permissions "*" "deny" (.. tool-name " should deny broad access"))
    (each [_ pattern (ipairs allowed-patterns)] (assert-pattern-permission permissions pattern "allow" (.. tool-name " should allow bounded root: " pattern))
      (each [_ marker (ipairs ["auth" "token" "secret" "credential" "keyring"])] (local deny-pattern (string.gsub pattern "%*%*$" (.. "*" marker "*"))) (local nested-deny-pattern (string.gsub pattern "/%*%*$" (.. "/**/*" marker "*"))) (assert-pattern-permission permissions deny-pattern "deny" (.. tool-name " should deny secret-looking path: " deny-pattern)) (assert-pattern-permission permissions nested-deny-pattern "deny" (.. tool-name " should deny nested secret-looking path: " nested-deny-pattern)))))
  (each [_ name (ipairs ["read" "list" "glob" "grep" "external_directory"])] (assert-bounded-tool name))
  (assert (= (length status.allowed-roots) (length allowed-patterns)) "bridge status should report allowed roots")
  (each [i pattern (ipairs allowed-patterns)]
    (local actual-pattern (. status.allowed-roots i))
    (local expected-root (slash-path pattern))
    (local actual-root (slash-path actual-pattern))
    (assert (= actual-root expected-root) (.. "bridge status allowed root should match: expected " expected-root " actual " actual-root)))
  (bridge:refresh-config!) (local refreshed (json.loads (fs.read-file status.config-path))) (assert (= refreshed.mcp.space.url status.url) "refresh-config should preserve current MCP URL") (bridge:stop) (clean-dir dir))

(fn test-opencode-mcp-bridge-refreshes-provider-table []
  (local BridgeMod (require :llm/agent/opencode-mcp-bridge))
  (var old-closed false)
  (var refresh-called 0)
  (var factory-called 0)
  (local old-provider {:close (fn [] (set old-closed true))})
  (local new-provider {:id "new-provider"})
  (local bridge
    {:refresh-config! (fn [self]
                        (set refresh-called (+ refresh-called 1))
                        {:url "http://127.0.0.1:4321/mcp"})
     :opencode-env (fn [self] {:XDG_CONFIG_HOME "/tmp/space/test-opencode-config"})})
  (local providers
    {:opencode old-provider
     :opencode-factory (fn []
                         (set factory-called (+ factory-called 1))
                         new-provider)})
  (local refreshed (BridgeMod.refresh-opencode-provider! providers bridge))
  (assert old-closed "refresh should close existing provider")
  (assert (= refresh-called 1) "refresh should refresh bridge config exactly once")
  (assert (= factory-called 1) "refresh should create replacement provider exactly once")
  (assert (= refreshed new-provider) "refresh should return the replacement provider")
  (assert (= providers.opencode new-provider) "refresh should store replacement provider"))

;; ═══════════════════════════════════════
;; Prompt utilities tests
;; ═══════════════════════════════════════

(fn test-prompt-assemble-blocks []
  (local PromptUtils (require :llm/agent/prompt-utils))
  (local result (PromptUtils.assemble-blocks
    [{:name "Instructions" :content "Be helpful."}
     {:name "Context" :content "No active context."}]))
  (assert (string.match result "## Instructions") "should include Instructions header")
  (assert (string.match result "Be helpful") "should include content")
  (assert (string.match result "## Context") "should include Context header"))

(fn test-prompt-assemble-blocks-skips-nameless []
  (local PromptUtils (require :llm/agent/prompt-utils))
  (local result (PromptUtils.assemble-blocks
    [{:content "No name here"}
     {:name "Valid" :content "Has name"}]))
  (assert (string.match result "## Valid") "should include named block")
  (assert (not (string.match result "No name here")) "should skip nameless block"))

(fn test-prompt-render-template []
  (local PromptUtils (require :llm/agent/prompt-utils))
  (local result (PromptUtils.render-template "Hello ${name}, you are ${role}." {:name "Sam" :role "admin"}))
  (assert (= result "Hello Sam, you are admin.") "should replace variables"))

(fn test-prompt-render-template-missing-vars []
  (local PromptUtils (require :llm/agent/prompt-utils))
  (local result (PromptUtils.render-template "Hello ${name}!" {}))
  (assert (= result "Hello ${name}!") "should leave missing vars in place"))

(fn test-prompt-format-context-with-enrichers []
  (local PromptUtils (require :llm/agent/prompt-utils))
  (PromptUtils.register-enricher :test-world (fn [ctx] "active world available"))
  (PromptUtils.register-enricher :test-canvas (fn [ctx] "canvas visible"))
  (local result (PromptUtils.format-context {}))
  (assert (string.match result "active world available") "should include enricher output")
  (assert (string.match result "canvas visible") "should include second enricher")
  (PromptUtils.remove-enricher :test-world)
  (PromptUtils.remove-enricher :test-canvas))

(fn test-prompt-format-context-empty []
  (local PromptUtils (require :llm/agent/prompt-utils))
  ;; Ensure no enrichers registered
  (PromptUtils.remove-enricher :test-world)
  (PromptUtils.remove-enricher :test-canvas)
  (local result (PromptUtils.format-context {}))
  (assert (= result "No active context.") "should return default message"))

(fn test-prompt-format-presets []
  (local PromptUtils (require :llm/agent/prompt-utils))
  (local mock-presets
    {:get-active-presets (fn [] [{:name "drawing-shape-tools" :reason "auto"}
                                  {:name "drawing-history-tools" :reason "auto"}])})
  (local result (PromptUtils.format-presets mock-presets))
  (assert (string.match result "Active presets") "should have header")
  (assert (string.match result "drawing%-shape%-tools") "should include preset name")
  (assert (string.match result "drawing%-history%-tools") "should include second preset name"))

(fn test-prompt-format-presets-empty []
  (local PromptUtils (require :llm/agent/prompt-utils))
  (local mock-presets
    {:get-active-presets (fn [] [])})
  (local result (PromptUtils.format-presets mock-presets))
  (assert (= result "No active presets.") "should return default message"))

(fn test-prompt-remove-enricher []
  (local PromptUtils (require :llm/agent/prompt-utils))
  (PromptUtils.register-enricher :temp-enricher (fn [ctx] "temp"))
  (local with-enricher (PromptUtils.format-context {}))
  (assert (string.match with-enricher "temp") "should have enricher output")
  (PromptUtils.remove-enricher :temp-enricher)
  (local without-enricher (PromptUtils.format-context {}))
  (assert (not (string.match without-enricher "temp")) "should not have removed enricher output"))

(fn test-prompt-enricher-errors-are-explicit []
  (local PromptUtils (require :llm/agent/prompt-utils))
  (PromptUtils.register-enricher :broken-enricher (fn [ctx] (error "context failed")))
  (local (ok err) (pcall (fn [] (PromptUtils.format-context {}))))
  (PromptUtils.remove-enricher :broken-enricher)
  (assert (not ok) "broken enricher should fail loudly")
  (assert (string.match (tostring err) "broken%-enricher")
          "error should name the failing enricher"))

;; ═══════════════════════════════════════
;; Runner tests
;; ═══════════════════════════════════════

(fn test-runner-create-session []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (local registry (AgentRegistry {:deps {}}))
  (local runner (AgentRunner
    {:data-dir dir
     :registry registry
     :deps {:app :stub
            :presets {}
            :tools {}
            :approvals {}
            :agents registry
            :providers {}}}))
  (local session (runner:create-session "space-agent"))
  (assert session "session should be created")
  (assert (= session.agent-id "space-agent") "should have correct agent-id")
  (assert (= session.status :idle) "should start idle")
  (runner:drop)
  (clean-dir dir))

(fn test-runner-get-session []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (local registry (AgentRegistry {:deps {}}))
  (local runner (AgentRunner
    {:data-dir dir
     :registry registry
     :deps {:app :stub
            :presets {}
            :tools {}
            :approvals {}
            :agents registry
            :providers {}}}))
  (local created (runner:create-session "space-agent"))
  (local loaded (runner:get-session created.id))
  (assert loaded "session should be loadable")
  (assert (= loaded.id created.id) "ids should match")
  (runner:drop)
  (clean-dir dir))

(fn test-runner-run-turn-returns-handle-immediately []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (local registry (AgentRegistry {:deps {}}))
  ;; Register an agent that completes immediately
  (registry:register "space-agent"
    (fn [deps]
      {:id "space-agent"
       :name "Test"
       :run (fn [self input session ctx]
              (ctx.turn:finish {:content (.. "echo: " input)}))}))
  (local runner (AgentRunner
    {:data-dir dir
     :registry registry
     :deps {:app :stub
            :presets {}
            :tools {}
            :approvals {}
            :agents registry
            :providers {}}}))
  (local session (runner:create-session "space-agent"))
  (var turn-result nil)
  (local handle (runner:run-turn session.id "hello"
    {:on-complete (fn [r] (set turn-result r))}))
  (assert handle "handle should be returned immediately")
  (assert (= (handle:status) :completed) "turn should be completed synchronously")
  (assert turn-result "on-complete should have fired")
  (assert (= turn-result.result.content "echo: hello") "should echo input")
  (runner:drop)
  (clean-dir dir))

(fn test-runner-run-turn-appends-user-message []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (local registry (AgentRegistry {:deps {}}))
  (registry:register "space-agent"
    (fn [deps]
      {:id "space-agent"
       :run (fn [self input session ctx] (ctx.turn:finish {:content "ok"}))}))
  (local runner (AgentRunner
    {:data-dir dir
     :registry registry
     :deps {:app :stub :presets {} :tools {} :approvals {} :agents registry :providers {}}}))
  (local session (runner:create-session "space-agent"))
  (runner:run-turn session.id "draw a circle" {})
  ;; Reload session to check persisted items
  (local reloaded (runner:get-session session.id))
  (assert reloaded "session should be reloadable")
  (assert (>= (length reloaded.items) 1) "should have at least user message item")
  (local user-item (. reloaded.items 1))
  (assert (= user-item.type "message") "first item should be message")
  (assert (= user-item.role "user") "should be user role")
  (assert (= user-item.content "draw a circle") "should have user content")
  (runner:drop)
  (clean-dir dir))

(fn test-runner-cancel-turn []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (local registry (AgentRegistry {:deps {}}))
  (var cancel-invoked false)
  (var agent-started false)
  (var agent-finished false)
  (registry:register "space-agent"
    (fn [deps]
      {:id "space-agent"
       :run (fn [self input session ctx]
              (set agent-started true)
              (ctx.turn:set-cancel (fn [] (set cancel-invoked true)))
              ;; Don't finish - simulate long-running agent
              )}))
  (local runner (AgentRunner
    {:data-dir dir
     :registry registry
     :deps {:app :stub :presets {} :tools {} :approvals {} :agents registry :providers {}}}))
  (local session (runner:create-session "space-agent"))
  (local handle (runner:run-turn session.id "do something long" {}))
  (assert agent-started "agent should have started")
  (runner:cancel-turn session.id)
  (assert cancel-invoked "agent-registered cancel should be invoked")
  (assert (= (handle:status) :cancelled) "handle should report cancelled")
  (runner:drop)
  (clean-dir dir))

(fn test-runner-second-turn-cancels-first []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (local registry (AgentRegistry {:deps {}}))
   (var first-cancelled false)
  (var first-finished false)
  (registry:register "space-agent"
    (fn [deps]
      {:id "space-agent"
       :run (fn [self input session ctx]
              (ctx.turn:set-cancel (fn [] (set first-cancelled true)))
              ;; Don't finish immediately — simulate long-running turn
              ;; Only finish if not the first input (second turn)
              (when (not (= input "first"))
                (ctx.turn:finish {:content input})))}))
  (local runner (AgentRunner
    {:data-dir dir
     :registry registry
     :deps {:app :stub :presets {} :tools {} :approvals {} :agents registry :providers {}}}))
  (local session (runner:create-session "space-agent"))
  ;; First turn - agent registers cancel but does NOT finish (long-running)
  (local handle1 (runner:run-turn session.id "first" {}))
  (assert (= (handle1:status) :running) "first turn should be running")
  ;; Second turn should cancel first
  (local handle2 (runner:run-turn session.id "second" {}))
  (assert (= (handle1:status) :cancelled) "first turn should be cancelled")
  (assert (= (handle2:status) :completed) "second turn should complete")
  (runner:drop)
  (clean-dir dir))

(fn test-runner-delete-session []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (local registry (AgentRegistry {:deps {}}))
  (local runner (AgentRunner
    {:data-dir dir
     :registry registry
     :deps {:app :stub :presets {} :tools {} :approvals {} :agents registry :providers {}}}))
  (local session (runner:create-session "space-agent"))
  (local path (fs.join-path dir (.. session.id ".json")))
  (assert (fs.exists path) "file should exist")
  (runner:delete-session session.id)
  (assert (not (fs.exists path)) "file should not exist after delete")
  (assert (= (runner:get-session session.id) nil) "should not be loadable")
  (runner:drop)
  (clean-dir dir))

(fn test-runner-list-sessions []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (local registry (AgentRegistry {:deps {}}))
  (local runner (AgentRunner
    {:data-dir dir
     :registry registry
     :deps {:app :stub :presets {} :tools {} :approvals {} :agents registry :providers {}}}))
  (runner:create-session "space-agent")
  (runner:create-session "space-agent")
  (local items (runner:list-sessions))
  (assert (= (length items) 2) "should list 2 sessions")
  (runner:drop)
  (clean-dir dir))

(fn test-runner-turn-fail-persists-error-item []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (local registry (AgentRegistry {:deps {}}))
  (registry:register "space-agent"
    (fn [deps]
      {:id "space-agent"
       :run (fn [self input session ctx]
              (ctx.turn:fail "something went wrong"))}))
  (local runner (AgentRunner
    {:data-dir dir
     :registry registry
     :deps {:app :stub :presets {} :tools {} :approvals {} :agents registry :providers {}}}))
  (local session (runner:create-session "space-agent"))
  (runner:run-turn session.id "test" {})
  (local reloaded (runner:get-session session.id))
  ;; Should have user message + error item
  (assert (>= (length reloaded.items) 2) "should have user message and error item")
  (local error-item (. reloaded.items (length reloaded.items)))
  (assert (= error-item.type "error") "last item should be error type")
  (assert (= error-item.error "something went wrong") "error should match")
  (runner:drop)
  (clean-dir dir))

(fn test-runner-creates-artifact-context []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local SessionMod (require :llm/agent/session))
  (local dir (temp-dir))
  (local artifact-root (fs.join-path dir "agent-artifacts"))
  (local registry (AgentRegistry {:deps {}}))
  (var captured-artifacts nil)
  (var captured-runtime-context nil)
  (registry:register "space-agent"
    (fn [_deps]
      {:id "space-agent"
       :run (fn [_self _input _session ctx]
              (set captured-artifacts ctx.artifacts)
              (set captured-runtime-context ctx.runtime-context)
              (ctx.turn:finish {:content "ok"}))}))
  (local runner (AgentRunner
    {:data-dir dir
     :registry registry
     :deps {:app :stub
            :presets {}
            :tools {}
            :approvals {}
            :agents registry
            :providers {}
            :artifact-root artifact-root}}))
  (local session (runner:create-session "space-agent"))
  (runner:run-turn session.id "capture artifacts" {})
  (local expected-session-dir (fs.join-path artifact-root session.id))
  (local expected-report-path (fs.join-path expected-session-dir "report.md"))
  (assert captured-artifacts "agent context should include artifacts")
  (assert (= captured-artifacts.root artifact-root) "artifact context should include root")
  (assert (= captured-artifacts.session-dir expected-session-dir)
          "artifact context should include session directory")
  (assert (= captured-artifacts.report-path expected-report-path)
          "artifact context should include report path")
  (assert (fs.exists expected-session-dir) "artifact session directory should exist")
  (assert captured-runtime-context "agent context should include runtime-context")
  (assert (= captured-runtime-context.artifact-dir expected-session-dir)
          "runtime-context should use the session artifact directory")
  (assert (= captured-runtime-context.report-path expected-report-path)
          "runtime-context should use the artifact report path")
  (assert (= captured-runtime-context.agent-session-id session.id)
          "runtime-context should persist agent session id")
  (assert (= captured-runtime-context.validation-mode "disk-only")
          "runtime-context should start as disk-only")
  (SessionMod.invalidate-cache session.id)
  (local persisted (runner:get-session session.id))
  (local runtime-context persisted.data.runtime-context)
  (assert (= runtime-context.artifact-dir expected-session-dir)
          "persisted runtime-context should include artifact-dir")
  (assert (= runtime-context.report-path expected-report-path)
          "persisted runtime-context should include report-path")
  (assert (= runtime-context.agent-session-id session.id)
          "persisted runtime-context should include agent-session-id")
  (assert (= runtime-context.validation-mode "disk-only")
          "persisted runtime-context should default to disk-only")
  (runner:drop)
  (clean-dir dir))

(fn capture-runner-artifacts [data-dir]
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local registry (AgentRegistry {:deps {}}))
  (var captured-artifacts nil)
  (registry:register "space-agent"
    (fn [_deps]
      {:id "space-agent"
       :run (fn [_self _input _session ctx]
              (set captured-artifacts ctx.artifacts)
              (ctx.turn:finish {:content "ok"}))}))
  (local runner (AgentRunner
    {:data-dir data-dir
     :registry registry
     :deps {:app :stub :presets {} :tools {} :approvals {} :agents registry :providers {}}}))
  (local session (runner:create-session "space-agent"))
  (runner:run-turn session.id "capture default artifacts" {})
  (runner:drop)
  {:artifacts captured-artifacts :session-id session.id})

(fn test-runner-default-artifacts-nested-under-non-session-data-dir []
  (local dir (temp-dir)) (local PathUtils (require :tests.path-utils))
  (local result (capture-runner-artifacts dir))
  (local expected-root (fs.join-path dir "agent-artifacts"))
  (local expected-session-dir (fs.join-path expected-root result.session-id))
  (assert (PathUtils.paths-eq result.artifacts.root expected-root)
          "non-agent-sessions data-dir should use nested artifact root")
  (assert (PathUtils.paths-eq result.artifacts.session-dir expected-session-dir)
          "non-agent-sessions data-dir should create nested session artifact dir")
  (assert (fs.exists expected-session-dir)
          "nested default session artifact directory should exist")
  (clean-dir dir))

(fn test-runner-default-artifacts-sibling-for-agent-sessions-data-dir []
  (local root (temp-dir)) (local PathUtils (require :tests.path-utils))
  (local data-dir (fs.join-path root "agent-sessions"))
  (local result (capture-runner-artifacts data-dir))
  (local expected-root (fs.join-path root "agent-artifacts"))
  (local expected-session-dir (fs.join-path expected-root result.session-id))
  (assert (PathUtils.paths-eq result.artifacts.root expected-root)
          "agent-sessions data-dir should use sibling artifact root")
  (assert (PathUtils.paths-eq result.artifacts.session-dir expected-session-dir)
          "agent-sessions data-dir should create sibling session artifact dir")
  (assert (fs.exists expected-session-dir)
          "sibling default session artifact directory should exist")
  (clean-dir root))

;; ═══════════════════════════════════════
;; SpaceAgent fixture tests
;; ═══════════════════════════════════════

(fn test-space-agent-registers-with-registry []
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local SpaceAgentMod (require :llm/agent/builtins/space-agent))
  (local reg (AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register reg {:app :stub :presets {} :tools {} :approvals {} :providers {}})
  (local agent (reg:get "space-agent"))
  (assert agent "space-agent should be registered")
  (assert (= agent.id "space-agent") "should have correct id"))

(fn test-space-agent-run-with-mock-opencode []
  (local SpaceAgentMod (require :llm/agent/builtins/space-agent))
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (local artifact-root (fs.join-path dir "agent-artifacts"))

  ;; Mock opencode client
  (var create-calls [])
  (var prompt-calls [])
  (var abort-calls [])
  (local mock-opencode
    {:session
     {:create (fn [body on-response]
                (table.insert create-calls {:body body})
                (on-response {:ok true :data {:id "oc-ses-mock" :title body.title}}))
      :prompt (fn [id body on-response]
                (table.insert prompt-calls {:id id :body body})
                (on-response {:ok true
                              :data {:info {:role "user" :model {:modelID "claude-mock"}}
                                     :parts [{:type "text" :text "draw a red circle"}]
                                     :usage {:inputTokens 50 :outputTokens 30}}})
                )
      :abort (fn [id on-response]
               (table.insert abort-calls {:id id})
               (on-response true))
      :get (fn [id on-response]
             (on-response {:ok true :data {:id id :title "existing"}}))
      :messages (fn [id on-response]
                  (on-response
                    {:ok true
                     :data [{:info {:id "msg-user" :role "user"}
                             :parts [{:type "text" :text "draw a red circle"}]}
                            {:info {:id "msg-assistant" :role "assistant" :model {:modelID "claude-mock"}}
                             :parts [{:type "text" :text "I'll draw that for you!"}]
                             :usage {:inputTokens 50 :outputTokens 30}}]}))}})

  ;; Register SpaceAgent with mock provider
  (local reg (AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register reg
    {:app :stub
     :presets {}
     :tools {}
     :approvals {}
     :providers {:opencode mock-opencode}})

  ;; Create runner
  (local mock-presets
    {:get-active-presets (fn [] [{:name "drawing-shape-tools" :reason "auto"}])
     :get-prompt-fragments (fn [] [])
     :get-tool-defs (fn [] [])})
  (local mock-tools (mock-tool-surface [{:preset "drawing-shape-tools"
                                         :prompt "Use drawing shape tools for geometry edits."}]))
  (local runner (AgentRunner
    {:data-dir dir
     :registry reg
     :deps {:app :stub
            :presets mock-presets
            :tools mock-tools
            :approvals {}
            :agents reg
            :providers {:opencode mock-opencode}
            :artifact-root artifact-root}}))

  (local session (runner:create-session "space-agent"))
  (var items-log [])
  (var completed nil)

  (local handle (runner:run-turn session.id "draw a red circle"
    {:on-item (fn [item] (table.insert items-log item))
     :on-complete (fn [r] (set completed r))}))

  ;; Verify handle completed
  (assert (= (handle:status) :completed) "turn should complete")
  (assert completed "on-complete should fire")
  (assert (= completed.result.content "I'll draw that for you!") "result should contain assistant response")

  ;; Verify OpenCode calls
  (assert (= (length create-calls) 1) "should call session.create once")
  (assert (= (length prompt-calls) 1) "should call session.prompt once")
  (local first-call (. prompt-calls 1))
  (local first-part (. first-call.body.parts 1))
  (assert (string.match first-part.text "draw a red circle") "prompt should contain user input")
  (assert (string.match first-call.body.system "Use drawing shape tools")
          "system prompt should include active preset guidance")
  (local expected-report-path
    (fs.join-path artifact-root session.id "report.md"))
  (assert (string.find first-call.body.system expected-report-path 1 true)
          "system prompt should include artifact report path")
  (assert (string.find first-call.body.system "validation-mode: live" 1 true)
          "system prompt should document live validation mode")
  (assert (string.find first-call.body.system "validation-mode: disk-only" 1 true)
          "system prompt should document disk-only validation mode")
  (assert (string.find first-call.body.system "compile check" 1 true)
          "system prompt should mention compile check evidence")
  (assert (string.find first-call.body.system "constraints" 1 true)
          "system prompt should mention constraints evidence")
  (assert (string.find first-call.body.system "focused test" 1 true)
          "system prompt should mention focused test evidence")
  (assert (string.find first-call.body.system
                       "Do not claim the running app was validated from disk-only evidence"
                       1 true)
          "system prompt should warn against live claims after disk-only validation")

  ;; Verify session items persisted
  (local reloaded (runner:get-session session.id))
  (assert (>= (length reloaded.items) 2) "should have user message and assistant message")
  ;; Check user message
  (var user-msg nil)
  (var assistant-msg nil)
  (var user-count 0)
  (var assistant-count 0)
  (each [_ item (ipairs reloaded.items)]
    (when (and (= item.type "message") (= item.role "user"))
      (set user-count (+ user-count 1))
      (set user-msg item))
    (when (and (= item.type "message") (= item.role "assistant"))
      (set assistant-count (+ assistant-count 1))
      (set assistant-msg item)))
  (assert (= user-count 1) "should persist exactly one user message")
  (assert (= assistant-count 1) "should persist exactly one assistant message")
  (assert user-msg "should have user message")
  (assert (= user-msg.content "draw a red circle") "user message should match")
  (assert assistant-msg "should have assistant message")
  (assert (= assistant-msg.content "I'll draw that for you!") "assistant message should match")
  (assert (= assistant-msg.provider "opencode") "should record provider")
  (assert (= assistant-msg.model "claude-mock") "should record model")

  ;; OpenCode session ID should be stored
  (assert (= reloaded.data.opencode-session-id "oc-ses-mock") "should store opencode session id")

  (runner:drop)
  (clean-dir dir))

(fn test-space-agent-persists-opencode-tool-audit []
  (local SpaceAgentMod (require :llm/agent/builtins/space-agent))
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (var messages-called false)
  (local mock-opencode
    {:session
     {:create (fn [body on-response]
                (on-response {:ok true :data {:id "oc-audit"}}))
      :prompt (fn [id body on-response]
                (on-response {:ok true
                              :data {:info {:model {:modelID "audit-model"}}
                                     :parts [{:type "text" :text "done"}]
                                     :usage {}}}))
      :abort (fn [id on-response] (on-response true))
      :get (fn [id on-response]
             (on-response {:ok true :data {:id id :title "existing"}}))
      :messages (fn [id on-response]
                  (set messages-called true)
                  (on-response
                    {:ok true
                     :data [{:info {:id "msg-tool"}
                             :parts [{:type "tool"
                                      :tool "space_agent_echo_token"
                                      :callID "call-123"
                                      :input {:token "abc"}
                                      :state {:status "completed"
                                              :output "abc"}}
                                     {:type "tool"
                                      :tool "space_agent_fail_token"
                                      :callID "call-err"
                                      :input {:token "bad"}
                                      :state {:status "error"
                                              :error {:message "boom"}}}]}]}))}})

  (local reg (AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register reg
    {:app :stub :presets {} :tools {} :approvals {} :providers {:opencode mock-opencode}})

  (local mock-presets
    {:get-active-presets (fn [] [])
     :get-prompt-fragments (fn [] [])
     :get-tool-defs (fn [] [])})
  (local runner (AgentRunner
    {:data-dir dir
     :registry reg
     :deps {:app :stub
            :presets mock-presets
            :tools (mock-tool-surface [])
            :approvals {}
            :agents reg
            :providers {:opencode mock-opencode}}}))

  (local session (runner:create-session "space-agent"))
  (local handle (runner:run-turn session.id "use the echo tool" {}))
  (assert (= (handle:status) :completed) "turn should complete")
  (assert messages-called "SpaceAgent should fetch OpenCode messages for audit persistence")
  (local reloaded (runner:get-session session.id))
  (var tool-call nil)
  (var tool-result nil)
  (var failed-tool-result nil)
  (each [_ item (ipairs reloaded.items)]
    (when (and (= item.type "tool-call") (= item.call-id "call-123"))
      (set tool-call item))
    (when (and (= item.type "tool-result") (= item.call-id "call-123"))
      (set tool-result item))
    (when (and (= item.type "tool-result") (= item.call-id "call-err"))
      (set failed-tool-result item)))
  (assert tool-call "tool call item should be persisted")
  (assert (= tool-call.name "space_agent_echo_token") "tool call should preserve name")
  (assert (= tool-call.call-id "call-123") "tool call should preserve call id")
  (assert (string.match tool-call.arguments "abc") "tool call should preserve arguments")
  (assert tool-result "tool result item should be persisted")
  (assert (= tool-result.call-id "call-123") "tool result should use same call id")
  (assert (= tool-result.output "abc") "tool result should preserve output")
  (assert failed-tool-result "failed tool result item should be persisted")
  (assert failed-tool-result.is-error "failed tool result should be marked as error")
  (assert (string.match failed-tool-result.output "boom")
          "failed tool result should preserve error payload")

  (runner:drop)
  (clean-dir dir))

(fn test-space-agent-streams-live-opencode-tool-events []
  (local SpaceAgentMod (require :llm/agent/builtins/space-agent))
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (var prompt-callback nil)
  (var event-callback nil)
  (var unsubscribed false)
  (var messages-called false)
  (local mock-opencode
    {:events
     {:subscribe (fn [on-event]
                   (set event-callback on-event)
                   {:unsubscribe (fn [] (set unsubscribed true))
                    :closed? (fn [] unsubscribed)})}
     :session
     {:create (fn [_body on-response]
                (on-response {:ok true :data {:id "oc-live"}}))
      :prompt (fn [_id _body on-response]
                (set prompt-callback on-response))
      :abort (fn [_id on-response] (on-response true))
      :get (fn [id on-response]
             (on-response {:ok true :data {:id id :title "existing"}}))
      :messages (fn [_id on-response]
                  (set messages-called true)
                  (on-response
                    {:ok true
                     :data [{:info {:id "msg-live"}
                             :parts [{:type "tool"
                                      :sessionID "oc-live"
                                      :messageID "msg-live"
                                      :tool "space_agent_echo_token"
                                      :callID "call-live"
                                      :state {:status "completed"
                                              :input {:token "abc"}
                                              :output "abc"}}]}]}))}})

  (local reg (AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register reg
    {:app :stub :presets {} :tools {} :approvals {} :providers {:opencode mock-opencode}})

  (local mock-presets
    {:get-active-presets (fn [] [])
     :get-prompt-fragments (fn [] [])
     :get-tool-defs (fn [] [])})
  (local runner (AgentRunner
    {:data-dir dir
     :registry reg
     :deps {:app :stub
            :presets mock-presets
            :tools (mock-tool-surface [])
            :approvals {}
            :agents reg
            :providers {:opencode mock-opencode}}}))

  (local session (runner:create-session "space-agent"))
  (var items-log [])
  (var updates-log [])
  (local handle (runner:run-turn session.id "use live tool"
    {:on-item (fn [item] (table.insert items-log item))
     :on-update (fn [item-id updates]
                  (table.insert updates-log {:item-id item-id :updates updates}))}))
  (assert (= (handle:status) :running) "turn should wait for prompt completion")
  (assert event-callback "SpaceAgent should subscribe to OpenCode events before prompt completion")

  (event-callback {:type "message.part.updated"
                   :properties {:part {:type "tool"
                                       :sessionID "oc-live"
                                       :messageID "msg-live"
                                       :tool "space_agent_echo_token"
                                       :callID "call-live"
                                       :state {:status "running"
                                               :input {:token "abc"}}}}})
  (local after-running (runner:get-session session.id))
  (var live-call nil)
  (each [_ item (ipairs after-running.items)]
    (when (and (= item.type "tool-call") (= item.call-id "call-live"))
      (set live-call item)))
  (assert live-call "live tool-call should be persisted before prompt response")
  (assert (= live-call.status "running") "live tool-call should record running status")
  (assert (string.match live-call.arguments "abc") "live tool-call should record arguments")
  (assert (= (handle:status) :running) "live tool event should not complete turn")

  (event-callback {:type "message.part.updated"
                   :properties {:part {:type "tool"
                                       :sessionID "oc-live"
                                       :messageID "msg-live"
                                       :tool "space_agent_echo_token"
                                       :callID "call-live"
                                       :state {:status "completed"
                                               :input {:token "abc"}
                                               :output "abc"}}}})
  (local after-completed (runner:get-session session.id))
  (var live-result nil)
  (each [_ item (ipairs after-completed.items)]
    (when (and (= item.type "tool-result") (= item.call-id "call-live"))
      (set live-result item)))
  (assert live-result "live tool-result should be persisted before prompt response")
  (assert (= live-result.output "abc") "live tool-result should preserve output")
  (assert (> (length updates-log) 0) "live duplicate tool event should update the existing call item")

  (prompt-callback {:ok true
                    :data {:info {:model {:modelID "live-model"}}
                           :parts [{:type "text" :text "done"}]
                           :usage {}}})
  (assert (= (handle:status) :completed) "turn should complete after prompt response")
  (assert unsubscribed "live event subscription should be closed when prompt completes")
  (assert messages-called "final audit should still reconcile OpenCode messages")
  (local reloaded (runner:get-session session.id))
  (var call-count 0)
  (var result-count 0)
  (var assistant-count 0)
  (each [_ item (ipairs reloaded.items)]
    (when (and (= item.type "tool-call") (= item.call-id "call-live"))
      (set call-count (+ call-count 1)))
    (when (and (= item.type "tool-result") (= item.call-id "call-live"))
      (set result-count (+ result-count 1)))
    (when (and (= item.type "message") (= item.role "assistant"))
      (set assistant-count (+ assistant-count 1))))
  (assert (= call-count 1) "final audit should not duplicate live tool-call")
  (assert (= result-count 1) "final audit should not duplicate live tool-result")
  (assert (= assistant-count 1) "assistant response should be persisted once")

  (runner:drop)
  (clean-dir dir))

(fn test-space-agent-streams-live_text_and_reasoning []
  (local SpaceAgentMod (require :llm/agent/builtins/space-agent))
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (var prompt-callback nil)
  (var prompt-body nil)
  (var event-callback nil)
  (local mock-opencode
    {:events
     {:subscribe (fn [on-event]
                   (set event-callback on-event)
                   {:unsubscribe (fn [] nil)
                    :closed? (fn [] false)})}
     :session
     {:create (fn [_body on-response]
                (on-response {:ok true :data {:id "oc-live-text"}}))
      :prompt (fn [_id body on-response]
                (set prompt-body body)
                (set prompt-callback on-response))
      :abort (fn [_id on-response] (on-response true))
      :get (fn [id on-response]
             (on-response {:ok true :data {:id id :title "existing"}}))
      :messages (fn [_id on-response]
                  (on-response {:ok true :data []}))}})

  (local reg (AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register reg
    {:app :stub :presets {} :tools {} :approvals {} :providers {:opencode mock-opencode}})

  (local mock-presets
    {:get-active-presets (fn [] [])
     :get-prompt-fragments (fn [] [])
     :get-tool-defs (fn [] [])})
  (local runner (AgentRunner
    {:data-dir dir
     :registry reg
     :deps {:app :stub
            :presets mock-presets
            :tools (mock-tool-surface [])
            :approvals {}
            :agents reg
            :providers {:opencode mock-opencode}}}))

  (local session (runner:create-session "space-agent"))
  (local handle (runner:run-turn session.id "stream text"
    {:on-item (fn [_item] nil)
     :on-update (fn [_item-id _updates] nil)}))
  (assert event-callback "SpaceAgent should subscribe to OpenCode events")
  (assert prompt-body "SpaceAgent should submit the prompt before waiting for live events")

  ;; OpenCode may stream the submitted user message as a text part. That must not
  ;; become an assistant draft in Space's transcript.
  (event-callback {:type "message.part.updated"
                   :properties {:message {:info {:role "user"}}
                                :part {:type "text"
                                       :sessionID "oc-live-text"
                                       :messageID "msg-user"
                                       :id "part-user"
                                       :text "stream text"}}})
  (local after-user-stream (runner:get-session session.id))
  (var user-message-count 0)
  (var assistant-message-count 0)
  (each [_ item (ipairs after-user-stream.items)]
    (when (and (= item.type "message") (= item.role "user"))
      (set user-message-count (+ user-message-count 1)))
    (when (and (= item.type "message") (= item.role "assistant"))
      (set assistant-message-count (+ assistant-message-count 1))))
  (assert (= user-message-count 1)
          "streamed user text should leave the original user message as the only user row")
  (assert (= assistant-message-count 0)
          "streamed user text should not create an assistant row")

  ;; Even if role metadata is missing, the prompt message id Space sent to
  ;; OpenCode identifies the user input and must be ignored in the live stream.
  (event-callback {:type "message.part.updated"
                   :properties {:part {:type "text"
                                       :sessionID "oc-live-text"
                                       :messageID prompt-body.messageId
                                       :id "part-user-without-role"
                                       :text "stream text"}}})
  (local after-user-id-stream (runner:get-session session.id))
  (var assistant-after-input-id-count 0)
  (each [_ item (ipairs after-user-id-stream.items)]
    (when (and (= item.type "message") (= item.role "assistant"))
      (set assistant-after-input-id-count (+ assistant-after-input-id-count 1))))
  (assert (= assistant-after-input-id-count 0)
          "streamed prompt message id should not create an assistant row")

  ;; Some OpenCode builds echo the submitted user text as a separate live
  ;; text message with no role metadata and no prompt message id.
  (event-callback {:type "message.part.updated"
                   :properties {:part {:type "text"
                                       :sessionID "oc-live-text"
                                       :messageID "msg-user-echo"
                                       :id "part-user-echo"
                                       :text "stream text"}}})
  (local after-user-echo-stream (runner:get-session session.id))
  (var assistant-after-echo-count 0)
  (each [_ item (ipairs after-user-echo-stream.items)]
    (when (and (= item.type "message") (= item.role "assistant"))
      (set assistant-after-echo-count (+ assistant-after-echo-count 1))))
  (assert (= assistant-after-echo-count 0)
          "streamed input echo should not create an assistant row")

  ;; Buffer an out-of-order text delta, then provide the part metadata.
  (event-callback {:type "message.part.delta"
                   :properties {:sessionID "oc-live-text"
                                :messageID "msg-assistant"
                                :partID "part-text"
                                :field "text"
                                :delta "hel"}})
  (event-callback {:type "message.part.updated"
                   :properties {:part {:type "text"
                                       :sessionID "oc-live-text"
                                       :messageID "msg-assistant"
                                       :id "part-text"
                                       :text ""}}})
  (event-callback {:type "message.part.delta"
                   :properties {:sessionID "oc-live-text"
                                :messageID "msg-assistant"
                                :partID "part-text"
                                :field "text"
                                :delta "lo"}})

  (event-callback {:type "message.part.updated"
                   :properties {:part {:type "reasoning"
                                       :sessionID "oc-live-text"
                                       :messageID "msg-assistant"
                                       :id "part-reason"
                                       :text "thinking"}}})
  (event-callback {:type "message.part.delta"
                   :properties {:sessionID "oc-live-text"
                                :messageID "msg-assistant"
                                :partID "part-reason"
                                :field "text"
                                :delta " live"}})

  (local during-stream (runner:get-session session.id))
  (var assistant nil)
  (var reasoning nil)
  (each [_ item (ipairs during-stream.items)]
    (when (and (= item.type "message") (= item.role "assistant"))
      (set assistant item))
    (when (= item.type "reasoning")
      (set reasoning item)))
  (assert assistant "assistant draft should be persisted before prompt response")
  (assert (= assistant.content "hello") "assistant draft should include buffered and live deltas")
  (assert (= assistant.stream-status "streaming") "assistant draft should be marked streaming")
  (assert reasoning "reasoning row should be persisted before prompt response")
  (assert (= reasoning.content "thinking live") "reasoning should stream deltas")
  (assert (= (handle:status) :running) "streaming text should not complete the turn")

  (prompt-callback {:ok true
                    :data {:info {:model {:modelID "live-model"}}
                           :parts [{:type "text" :text "hello final"}]
                           :usage {:output 2}}})
  (assert (= (handle:status) :completed) "turn should complete after prompt response")

  (local reloaded (runner:get-session session.id))
  (var assistant-count 0)
  (var final-assistant nil)
  (each [_ item (ipairs reloaded.items)]
    (when (and (= item.type "message") (= item.role "assistant"))
      (set assistant-count (+ assistant-count 1))
      (set final-assistant item)))
  (assert (= assistant-count 1) "final response should update live assistant draft")
  (assert (= final-assistant.content "hello final") "final response should reconcile assistant content")
  (assert (= final-assistant.stream-status "complete") "final assistant item should be complete")

  (runner:drop)
  (clean-dir dir))

(fn test-space-agent-waits-for-async-opencode-callbacks []
  (local SpaceAgentMod (require :llm/agent/builtins/space-agent))
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (var create-callback nil)
  (var prompt-callback nil)
  (var prompt-body nil)
  (local mock-opencode
    {:session
     {:create (fn [body on-response]
                (set create-callback on-response))
      :prompt (fn [id body on-response]
                (set prompt-body body)
                (set prompt-callback on-response))
      :abort (fn [id on-response] (on-response true))
      :get (fn [id on-response]
             (on-response {:ok true :data {:id id :title "existing"}}))
      :messages (fn [id on-response]
                  (on-response {:ok true :data []}))}})

  (local reg (AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register reg
    {:app :stub :presets {} :tools {} :approvals {} :providers {:opencode mock-opencode}})

  (local mock-presets
    {:get-active-presets (fn [] [])
     :get-prompt-fragments (fn [] [])
     :get-tool-defs (fn [] [])})
  (local runner (AgentRunner
    {:data-dir dir
     :registry reg
     :deps {:app :stub
            :presets mock-presets
            :tools (mock-tool-surface [])
            :approvals {}
            :agents reg
            :providers {:opencode mock-opencode}}}))

  (local session (runner:create-session "space-agent"))
  (var completed nil)
  (local handle (runner:run-turn session.id "async prompt"
    {:on-complete (fn [r] (set completed r))}))
  (assert (= (handle:status) :running) "turn should remain running until callbacks fire")
  (assert create-callback "session.create callback should be captured")
  (create-callback {:ok true :data {:id "oc-async"}})
  (assert (= (handle:status) :running) "turn should remain running until prompt callback fires")
  (assert prompt-callback "session.prompt callback should be captured")
  (local first-part (. prompt-body.parts 1))
  (assert (= first-part.text "async prompt") "prompt should contain input")
  (prompt-callback {:ok true
                    :data {:info {:model {:modelID "async-model"}}
                           :parts [{:type "text" :text "async result"}]
                           :usage {}}})
  (assert (= (handle:status) :completed) "turn should complete after prompt callback")
  (assert (= completed.result.content "async result") "completion should contain async response")
  (local reloaded (runner:get-session session.id))
  (var user-count 0)
  (var assistant-count 0)
  (each [_ item (ipairs reloaded.items)]
    (when (and (= item.type "message") (= item.role "user"))
      (set user-count (+ user-count 1)))
    (when (and (= item.type "message") (= item.role "assistant"))
      (set assistant-count (+ assistant-count 1))))
  (assert (= user-count 1) "async path should persist exactly one user message")
  (assert (= assistant-count 1) "async path should persist exactly one assistant message")

  (runner:drop)
  (clean-dir dir))

(fn test-space-agent-reuses-opencode-session []
  (local SpaceAgentMod (require :llm/agent/builtins/space-agent))
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))

  (var create-calls [])
  (var get-calls [])
  (local mock-opencode
    {:session
     {:create (fn [body on-response]
                (table.insert create-calls {:body body})
                (on-response {:ok true :data {:id (.. "oc-ses-" (length create-calls))}}))
      :prompt (fn [id body on-response]
                (on-response {:ok true
                              :data {:info {:model {:modelID "claude-mock"}}
                                     :parts [{:type "text" :text "done"}]
                                     :usage {:inputTokens 1 :outputTokens 1}}}))
      :abort (fn [id on-response] (on-response true))
      :get (fn [id on-response]
             (table.insert get-calls {:id id})
             (on-response {:ok true :data {:id id :title "existing"}}))
      :messages (fn [id on-response]
                  (on-response {:ok true :data []}))}})

  (local reg (AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register reg
    {:app :stub :presets {} :tools {} :approvals {} :providers {:opencode mock-opencode}})

  (local mock-presets
    {:get-active-presets (fn [] [])
     :get-prompt-fragments (fn [] [])
     :get-tool-defs (fn [] [])})
  (local runner (AgentRunner
    {:data-dir dir
     :registry reg
     :deps {:app :stub
            :presets mock-presets
            :tools (mock-tool-surface [])
            :approvals {}
            :agents reg
            :providers {:opencode mock-opencode}}}))

  (local session (runner:create-session "space-agent"))
  ;; First turn: should create OpenCode session
  (runner:run-turn session.id "first message" {})
  (assert (= (length create-calls) 1) "first turn should create OpenCode session")

  ;; Second turn: should reuse OpenCode session
  (runner:run-turn session.id "second message" {})
  (assert (= (length create-calls) 1) "second turn should NOT create new OpenCode session")
  ;; Should have called session.get to validate existing session
  (assert (>= (length get-calls) 1) "should call session.get to validate")

  (runner:drop)
  (clean-dir dir))

(fn test-space-agent-refreshes-stale-opencode-session []
  (local SpaceAgentMod (require :llm/agent/builtins/space-agent))
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (var first-get-calls 0)
  (var refresh-calls 0)
  (var fresh-create-calls 0)
  (var prompt-calls 0)
  (local first-provider
    {:session
     {:create (fn [_body on-response]
                (on-response {:ok false :error "old provider should not create after stale get"}))
      :prompt (fn [_id _body _on-response]
                (error "old provider should not prompt after stale get"))
      :abort (fn [_id on-response] (on-response true))
      :get (fn [id on-response]
             (set first-get-calls (+ first-get-calls 1))
             (assert (= id "stale-oc-session") "should look up stale OpenCode session id")
             (on-response {:ok false :error "Session not found"}))
      :messages (fn [_id on-response] (on-response {:ok true :data []}))}})
  (local second-provider
    {:server {:url (fn [] "http://127.0.0.1:9999")}
     :session
     {:create (fn [_body on-response]
                (set fresh-create-calls (+ fresh-create-calls 1))
                (on-response {:ok true :data {:id "fresh-oc-session"}}))
      :prompt (fn [id _body on-response]
                (set prompt-calls (+ prompt-calls 1))
                (assert (= id "fresh-oc-session") "prompt should use fresh session")
                (on-response {:ok true
                              :data {:info {:model {:modelID "mock-live"}}
                                     :parts [{:type "text" :text "fresh response"}]
                                     :usage {}}}))
      :abort (fn [_id on-response] (on-response true))
      :get (fn [_id _on-response]
             (error "refreshed provider should create, not retry stale get"))
      :messages (fn [_id on-response]
                  (on-response {:ok true
                                :data [{:info {:id "fresh-msg" :role "assistant" :model {:modelID "mock-live"}}
                                        :parts [{:type "text" :text "fresh response"}]}]}))}})
  (var providers nil)
  (set providers
       {:opencode first-provider
        :refresh-opencode (fn []
                            (set refresh-calls (+ refresh-calls 1))
                            (tset providers :opencode second-provider)
                            second-provider)})
  (local reg (AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register reg
    {:app :stub :presets {} :tools {} :approvals {} :providers providers})
  (local mock-presets
    {:get-active-presets (fn [] [])
     :get-prompt-fragments (fn [] [])
     :get-tool-defs (fn [] [])})
  (local runner (AgentRunner
    {:data-dir dir
     :registry reg
     :deps {:app :stub
            :presets mock-presets
            :tools (mock-tool-surface [])
            :approvals {}
            :agents reg
            :providers providers
            :opencode-mcp-bridge {:status (fn [self]
                                           {:url "http://127.0.0.1:4321/mcp"})}}}))
  (local session (runner:create-session "space-agent"))
  (tset session.data :opencode-session-id "stale-oc-session")
  (local handle (runner:run-turn session.id "recover stale session" {}))
  (assert (= (handle:status) :completed) "turn should complete after bounded refresh")
  (assert (= first-get-calls 1) "stale get should be attempted exactly once")
  (assert (= refresh-calls 1) "refresh-opencode should be called exactly once")
  (assert (= fresh-create-calls 1) "fresh provider should create one new session")
  (assert (= prompt-calls 1) "prompt should run exactly once")
  (local reloaded (runner:get-session session.id))
  (assert (= reloaded.data.opencode-session-id "fresh-oc-session")
          "session should store fresh OpenCode session id")
  (assert (= reloaded.data.runtime-context.validation-mode "live")
          "runtime context should record live validation mode")
  (assert (= reloaded.data.runtime-context.opencode-session-id "fresh-oc-session")
          "runtime context should record fresh OpenCode session id")
  (assert (= reloaded.data.runtime-context.mcp-endpoint "http://127.0.0.1:4321/mcp")
          "runtime context should record MCP endpoint evidence")
  (assert (= reloaded.data.runtime-context.opencode-server-url "http://127.0.0.1:9999")
          "runtime context should record OpenCode server URL")
  (assert reloaded.data.runtime-context.last-live-connection-at
          "runtime context should record live connection timestamp")
  (runner:drop)
  (clean-dir dir))

(fn test-space-agent-fails-non-stale-opencode-get-error []
  (local SpaceAgentMod (require :llm/agent/builtins/space-agent))
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (var create-calls 0)
  (var refresh-calls 0)
  (local provider
    {:session
     {:create (fn [_body _on-response] (set create-calls (+ create-calls 1)))
      :prompt (fn [_id _body _on-response] nil)
      :abort (fn [_id on-response] (on-response true))
      :get (fn [_id on-response]
             (on-response {:ok false :error "permission denied"}))
      :messages (fn [_id on-response] (on-response {:ok true :data []}))}})
  (local providers {:opencode provider
                    :refresh-opencode (fn []
                                        (set refresh-calls (+ refresh-calls 1))
                                        provider)})
  (local reg (AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register reg
    {:app :stub :presets {} :tools {} :approvals {} :providers providers})
  (local runner (AgentRunner
    {:data-dir dir
     :registry reg
     :deps {:app :stub
            :presets {:get-active-presets (fn [] []) :get-prompt-fragments (fn [] []) :get-tool-defs (fn [] [])}
            :tools (mock-tool-surface [])
            :approvals {}
            :agents reg
            :providers providers}}))
  (local session (runner:create-session "space-agent"))
  (tset session.data :opencode-session-id "existing-oc-session")
  (var error-received nil)
  (local handle (runner:run-turn session.id "non-stale get error"
    {:on-error (fn [e] (set error-received e))}))
  (assert (= (handle:status) :failed) "non-stale get error should fail the turn")
  (assert (= create-calls 0) "non-stale get error should not create a fresh session")
  (assert (= refresh-calls 0) "non-stale get error should not refresh provider")
  (assert (string.match error-received.error "permission denied") "failure should include OpenCode error")
  (local reloaded (runner:get-session session.id))
  (assert (= reloaded.data.opencode-session-id "existing-oc-session")
          "non-stale get error should preserve saved OpenCode session id")
  (runner:drop)
  (clean-dir dir))

(fn test-space-agent-fails-when-opencode-refresh-raises []
  (local SpaceAgentMod (require :llm/agent/builtins/space-agent))
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))
  (var get-callback nil)
  (var create-calls 0)
  (local provider
    {:session
     {:create (fn [_body _on-response] (set create-calls (+ create-calls 1)))
      :prompt (fn [_id _body _on-response] nil)
      :abort (fn [_id on-response] (on-response true))
      :get (fn [_id on-response] (set get-callback on-response))
      :messages (fn [_id on-response] (on-response {:ok true :data []}))}})
  (local providers {:opencode provider
                    :refresh-opencode (fn [] (error "bridge refresh failed"))})
  (local reg (AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register reg
    {:app :stub :presets {} :tools {} :approvals {} :providers providers})
  (local runner (AgentRunner
    {:data-dir dir
     :registry reg
     :deps {:app :stub
            :presets {:get-active-presets (fn [] []) :get-prompt-fragments (fn [] []) :get-tool-defs (fn [] [])}
            :tools (mock-tool-surface [])
            :approvals {}
            :agents reg
            :providers providers}}))
  (local session (runner:create-session "space-agent"))
  (tset session.data :opencode-session-id "stale-oc-session")
  (var error-received nil)
  (local handle (runner:run-turn session.id "refresh raises"
    {:on-error (fn [e] (set error-received e))}))
  (assert (= (handle:status) :running) "turn should wait for async get callback")
  (assert get-callback "test should capture async get callback")
  (get-callback {:ok false :error "Session not found"})
  (assert (= (handle:status) :failed) "refresh exception should fail the turn")
  (assert (= create-calls 0) "refresh exception should not create a fresh session")
  (assert (string.match error-received.error "OpenCode reconnect failed")
          "failure should identify reconnect failure")
  (assert (string.match error-received.error "bridge refresh failed")
          "failure should include refresh error")
  (local reloaded (runner:get-session session.id))
  (assert (string.match reloaded.data.runtime-context.last-reconnect-error "bridge refresh failed")
          "runtime context should record refresh failure")
  (runner:drop)
  (clean-dir dir))

(fn test-space-agent-handles-opencode-error []
  (local SpaceAgentMod (require :llm/agent/builtins/space-agent))
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))

  (local mock-opencode
    {:session
     {:create (fn [body on-response]
                (on-response {:ok false :error "server down"}))
      :prompt (fn [id body on-response] nil)
      :abort (fn [id on-response] nil)
      :get (fn [id on-response]
             (on-response {:ok false :error "not found"}))
      :messages (fn [id on-response]
                  (on-response {:ok true :data []}))}})

  (local reg (AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register reg
    {:app :stub :presets {} :tools {} :approvals {} :providers {:opencode mock-opencode}})

  (local mock-presets
    {:get-active-presets (fn [] [])
     :get-prompt-fragments (fn [] [])
     :get-tool-defs (fn [] [])})
  (local runner (AgentRunner
    {:data-dir dir
     :registry reg
     :deps {:app :stub
            :presets mock-presets
            :tools (mock-tool-surface [])
            :approvals {}
            :agents reg
            :providers {:opencode mock-opencode}}}))

  (local session (runner:create-session "space-agent"))
  (var error-received nil)
  (local handle (runner:run-turn session.id "do something"
    {:on-error (fn [e] (set error-received e))}))

  (assert (= (handle:status) :failed) "turn should fail on opencode error")
  (assert error-received "on-error should fire")
  (assert (string.match error-received.error "server down") "error should mention cause")

  (runner:drop)
  (clean-dir dir))

(fn test-space-agent-handles-prompt-error []
  (local SpaceAgentMod (require :llm/agent/builtins/space-agent))
  (local {: AgentRegistry} (require :llm/agent/registry))
  (local {: AgentRunner} (require :llm/agent/runner))
  (local dir (temp-dir))

  (local mock-opencode
    {:session
     {:create (fn [body on-response]
                (on-response {:ok true :data {:id "oc-ses-mock"}}))
      :prompt (fn [id body on-response]
                (on-response {:ok false :error "rate limited"}))
      :abort (fn [id on-response] (on-response true))
      :get (fn [id on-response]
             (on-response {:ok true :data {:id id}}))
      :messages (fn [id on-response]
                  (on-response {:ok true :data []}))}})

  (local reg (AgentRegistry {:deps {:app :stub}}))
  (SpaceAgentMod.register reg
    {:app :stub :presets {} :tools {} :approvals {} :providers {:opencode mock-opencode}})

  (local mock-presets
    {:get-active-presets (fn [] [])
     :get-prompt-fragments (fn [] [])
     :get-tool-defs (fn [] [])})
  (local runner (AgentRunner
    {:data-dir dir
     :registry reg
     :deps {:app :stub
            :presets mock-presets
            :tools (mock-tool-surface [])
            :approvals {}
            :agents reg
            :providers {:opencode mock-opencode}}}))

  (local session (runner:create-session "space-agent"))
  (var error-received nil)
  (local handle (runner:run-turn session.id "do something"
    {:on-error (fn [e] (set error-received e))}))

  (assert (= (handle:status) :failed) "turn should fail on prompt error")
  (assert (string.match error-received.error "rate limited") "error should mention cause")

  (runner:drop)
  (clean-dir dir))

;; ═══════════════════════════════════════
;; Register all tests
;; ═══════════════════════════════════════

(table.insert tests {:name "session create" :fn test-session-create})
(table.insert tests {:name "session load and cache" :fn test-session-load-and-cache})
(table.insert tests {:name "session load missing" :fn test-session-load-missing})
(table.insert tests {:name "session load corrupt errors" :fn test-session-load-corrupt-errors})
(table.insert tests {:name "session save updates timestamp" :fn test-session-save-updates-timestamp})
(table.insert tests {:name "session delete" :fn test-session-delete})
(table.insert tests {:name "session list" :fn test-session-list})
(table.insert tests {:name "session list empty dir" :fn test-session-list-empty-dir})
(table.insert tests {:name "session list corrupt errors" :fn test-session-list-corrupt-errors})
(table.insert tests {:name "session append item" :fn test-session-append-item})
(table.insert tests {:name "session prunes stale input echo assistant drafts"
                     :fn test-session-prunes-stale-input-echo-assistant-drafts})
(table.insert tests {:name "session append multiple item types" :fn test-session-append-multiple-item-types})
(table.insert tests {:name "session upsert item" :fn test-session-upsert-item})

(table.insert tests {:name "turn pair creation" :fn test-turn-pair-creation})
(table.insert tests {:name "turn start and complete" :fn test-turn-start-and-complete})
(table.insert tests {:name "turn fail" :fn test-turn-fail})
(table.insert tests {:name "turn cancel" :fn test-turn-cancel})
(table.insert tests {:name "turn cancel invokes registered fn" :fn test-turn-cancel-invokes-registered-fn})
(table.insert tests {:name "turn cancel surfaces cancel fn error" :fn test-turn-cancel-surfaces-cancel-fn-error})
(table.insert tests {:name "turn cannot finish twice" :fn test-turn-cannot-finish-twice})
(table.insert tests {:name "turn fail after complete noop" :fn test-turn-fail-after-complete-noop})
(table.insert tests {:name "turn cancelled? flag" :fn test-turn-cancelled?-flag})
(table.insert tests {:name "turn append item callback" :fn test-turn-append-item-callback})

(table.insert tests {:name "registry register and get" :fn test-registry-register-and-get})
(table.insert tests {:name "registry lazy construction" :fn test-registry-lazy-construction})
(table.insert tests {:name "registry get unknown" :fn test-registry-get-unknown})
(table.insert tests {:name "registry list" :fn test-registry-list})
(table.insert tests {:name "registry unregister" :fn test-registry-unregister})
(table.insert tests {:name "registry reregister invalidates cache" :fn test-registry-reregister-invalidates-cache})

(table.insert tests {:name "approvals normal always approved" :fn test-approvals-normal-always-approved})
(table.insert tests {:name "approvals auto policy" :fn test-approvals-auto-policy})
(table.insert tests {:name "approvals deny policy" :fn test-approvals-deny-policy})
(table.insert tests {:name "approvals ask default" :fn test-approvals-ask-default})
(table.insert tests {:name "approvals request-risk auto" :fn test-approvals-request-risk-auto})
(table.insert tests {:name "approvals request-risk needs-approval" :fn test-approvals-request-risk-needs-approval})
(table.insert tests {:name "approvals approve grants one matching retry" :fn test-approvals-approve-grants-one-matching-retry})
(table.insert tests {:name "approvals exact args and always grants" :fn test-approvals-exact-args-and-always-grants})
(table.insert tests {:name "approvals always grants persist" :fn test-approvals-always-grants-persist})
(table.insert tests {:name "approvals denied policy does not consume grant" :fn test-approvals-denied-policy-does-not-consume-grant})
(table.insert tests {:name "approvals unknown risk asserts" :fn test-approvals-unknown-risk-asserts})
(table.insert tests {:name "approvals record decision" :fn test-approvals-record-decision})
(table.insert tests {:name "approvals per-tool auto overrides risk ask" :fn test-approvals-per-tool-auto-overrides-risk-ask})
(table.insert tests {:name "approvals per-tool deny overrides risk auto" :fn test-approvals-per-tool-deny-overrides-risk-auto})
(table.insert tests {:name "approvals per-tool unmatched falls back to default" :fn test-approvals-per-tool-unmatched-falls-back-to-default})
(table.insert tests {:name "approvals per-tool unmatched falls back to auto default" :fn test-approvals-per-tool-unmatched-falls-back-to-auto-default})
(table.insert tests {:name "approvals per-tool nil context falls back" :fn test-approvals-per-tool-nil-context-falls-back})
(table.insert tests {:name "approvals per-tool table without default" :fn test-approvals-per-tool-table-without-default})
(table.insert tests {:name "approvals per-tool plain risk value still works" :fn test-approvals-per-tool-plain-risk-value-still-works})
(table.insert tests {:name "approvals per-tool request-risk auto resolves" :fn test-approvals-per-tool-request-risk-auto-resolves})

(table.insert tests {:name "tool surface active presets" :fn test-tool-surface-active-presets})
(table.insert tests {:name "tool surface openai tools" :fn test-tool-surface-openai-tools})
(table.insert tests {:name "tool surface mcp defs" :fn test-tool-surface-mcp-defs})
(table.insert tests {:name "tool surface call runs active tool" :fn test-tool-surface-call-runs-active-tool})
(table.insert tests {:name "tool surface call per-tool auto policy" :fn test-tool-surface-call-per-tool-auto-policy})
(table.insert tests {:name "tool surface exposes and gates ask risk" :fn test-tool-surface-exposes-and-gates-ask-risk})
(table.insert tests {:name "tool surface request approval tool grants exact call" :fn test-tool-surface-request-approval-tool-grants-exact-call})
(table.insert tests {:name "tool surface request approval normalizes opencode prefix"
                     :fn test-tool-surface-request-approval-normalizes-opencode-prefix})
(table.insert tests {:name "agent mcp sync registers surface tools" :fn test-agent-mcp-sync-registers-surface-tools})
(table.insert tests {:name "agent mcp sync does not bypass surface gating" :fn test-agent-mcp-sync-does-not_bypass_surface_gating})
(table.insert tests {:name "opencode mcp bridge starts and writes config" :fn test-opencode-mcp-bridge-starts-and-writes-config})
(table.insert tests {:name "opencode mcp bridge refreshes provider table" :fn test-opencode-mcp-bridge-refreshes-provider-table})

(table.insert tests {:name "prompt assemble blocks" :fn test-prompt-assemble-blocks})
(table.insert tests {:name "prompt assemble blocks skips nameless" :fn test-prompt-assemble-blocks-skips-nameless})
(table.insert tests {:name "prompt render template" :fn test-prompt-render-template})
(table.insert tests {:name "prompt render template missing vars" :fn test-prompt-render-template-missing-vars})
(table.insert tests {:name "prompt format context with enrichers" :fn test-prompt-format-context-with-enrichers})
(table.insert tests {:name "prompt format context empty" :fn test-prompt-format-context-empty})
(table.insert tests {:name "prompt format presets" :fn test-prompt-format-presets})
(table.insert tests {:name "prompt format presets empty" :fn test-prompt-format-presets-empty})
(table.insert tests {:name "prompt remove enricher" :fn test-prompt-remove-enricher})
(table.insert tests {:name "prompt enricher errors are explicit" :fn test-prompt-enricher-errors-are-explicit})

(table.insert tests {:name "runner create session" :fn test-runner-create-session})
(table.insert tests {:name "runner get session" :fn test-runner-get-session})
(table.insert tests {:name "runner run-turn returns handle immediately" :fn test-runner-run-turn-returns-handle-immediately})
(table.insert tests {:name "runner run-turn appends user message" :fn test-runner-run-turn-appends-user-message})
(table.insert tests {:name "runner cancel turn" :fn test-runner-cancel-turn})
(table.insert tests {:name "runner second turn cancels first" :fn test-runner-second-turn-cancels-first})
(table.insert tests {:name "runner delete session" :fn test-runner-delete-session})
(table.insert tests {:name "runner list sessions" :fn test-runner-list-sessions})
(table.insert tests {:name "runner turn fail persists error item" :fn test-runner-turn-fail-persists-error-item})
(table.insert tests {:name "runner creates artifact context" :fn test-runner-creates-artifact-context})
(table.insert tests {:name "runner default artifacts nested under non-session data-dir"
                     :fn test-runner-default-artifacts-nested-under-non-session-data-dir})
(table.insert tests {:name "runner default artifacts sibling for agent-sessions data-dir"
                     :fn test-runner-default-artifacts-sibling-for-agent-sessions-data-dir})

(table.insert tests {:name "space-agent registers with registry" :fn test-space-agent-registers-with-registry})
(table.insert tests {:name "space-agent run with mock opencode" :fn test-space-agent-run-with-mock-opencode})
(table.insert tests {:name "space-agent persists opencode tool audit" :fn test-space-agent-persists-opencode-tool-audit})
(table.insert tests {:name "space-agent streams live opencode tool events" :fn test-space-agent-streams-live-opencode-tool-events})
(table.insert tests {:name "space-agent streams live text and reasoning" :fn test-space-agent-streams-live_text_and_reasoning})
(table.insert tests {:name "space-agent waits for async opencode callbacks" :fn test-space-agent-waits-for-async-opencode-callbacks})
(table.insert tests {:name "space-agent reuses opencode session" :fn test-space-agent-reuses-opencode-session})
(table.insert tests {:name "space-agent refreshes stale opencode session" :fn test-space-agent-refreshes-stale-opencode-session})
(table.insert tests {:name "space-agent fails non-stale opencode get error" :fn test-space-agent-fails-non-stale-opencode-get-error})
(table.insert tests {:name "space-agent fails when opencode refresh raises" :fn test-space-agent-fails-when-opencode-refresh-raises})
(table.insert tests {:name "space-agent handles opencode error" :fn test-space-agent-handles-opencode-error})
(table.insert tests {:name "space-agent handles prompt error" :fn test-space-agent-handles-prompt-error})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests
      {:name "agent-layer"
       :tests tests})))

{:name "agent-layer"
 :tests tests
 :main main}
