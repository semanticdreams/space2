;; Agent panel tests

(local panel-mod (require :llm/agent/ui/panel))
(local AgentPanel panel-mod.AgentPanel)
(local controller-mod (require :llm/agent/ui/controller))
(local AgentPanelController controller-mod.AgentPanelController)
(local preset-list-mod (require :llm/agent/ui/preset-list))
(local AgentPresetList preset-list-mod.AgentPresetList)
(local session-list-mod (require :llm/agent/ui/session-list))
(local AgentSessionList session-list-mod.AgentSessionList)
(local registry-mod (require :llm/agent/registry))
(local AgentRegistry registry-mod.AgentRegistry)
(local approvals-mod (require :llm/agent/approvals))
(local AgentApprovals approvals-mod.AgentApprovals)
(local preset-registry-mod (require :llm/presets/registry))
(local PresetRegistry preset-registry-mod.PresetRegistry)
(local preset-manager-mod (require :llm/presets/init))
(local PresetManager preset-manager-mod.PresetManager)
(local tool-adapters-mod (require :llm/presets/tool-adapters))
(local ToolAdapterRegistry tool-adapters-mod.ToolAdapterRegistry)
(local transcript-mod (require :llm/agent/ui/transcript))
(local AgentTranscript transcript-mod.AgentTranscript)
(local BuildContext (require :build-context))
(local Intersectables (require :intersectables))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))
(local glm (require :glm))

(local tests [])

(fn make-test-theme []
  (local active (app.themes.get-active-theme))
  (local active-text (or active.text {}))
  (local active-list-view (or active.list-view {}))
  {:font active.font
   :code-font (or active.code-font active.font)
   :text {:foreground (or active-text.foreground
                         (glm.vec4 0.9 0.9 0.9 1))
          :dim-foreground (or active-text.dim-foreground
                              active-text.foreground
                              (glm.vec4 0.7 0.7 0.7 1))
          :scale (or active-text.scale 1)}
   :list-view {:item-selected-background
               (or active-list-view.item-selected-background
                   (glm.vec4 0.2 0.2 0.25 1))
               :item-foreground (or active-list-view.item-foreground
                                    active-text.foreground
                                    (glm.vec4 0.9 0.9 0.9 1))}
   :approval (or active.approval {})
   :transcript (or active.transcript {})})

(fn make-real-presets [opts]
  (local registry (PresetRegistry {}))
  (each [_ preset (ipairs (or opts.presets []))]
    (registry:register preset))
  (PresetManager {:registry registry
                  :tool-adapters (ToolAdapterRegistry {})
                  :app {}
                  :context (or opts.context
                               {:surface "canvas"
                                :activity "drawing"
                                :canvas-visible? true})
                  :overrides opts.overrides}))

(fn make-presets-stub []
  (make-real-presets {:presets []}))

(fn make-icons-stub []
  (local glyph {:advance 1})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {4242 glyph}
               :advance 1})
  {:font font
   :resolve (fn [_self _name]
              {:type :font
               :codepoint 4242
               :font font})
   :get (fn [_self _name] 4242)})

(fn make-widget-ctx []
  (local intersector (Intersectables))
  (local clickables (assert (Clickables {:intersectables intersector}) "agent panel test context requires clickables"))
  (local hoverables (assert (Hoverables {:intersectables intersector}) "agent panel test context requires hoverables"))
  (BuildContext {:clickables clickables
                 :hoverables hoverables
                 :icons (make-icons-stub)
                 :theme (make-test-theme)}))

(fn approx= [a b]
  (< (math.abs (- a b)) 0.0001))

(fn layout-test-transcript [transcript]
  (transcript.layout:measure-constrained {:max (glm.vec3 12 5 0)})
  (set transcript.layout.size (glm.vec3 12 5 0))
  (set transcript.layout.position (glm.vec3 0 0 0))
  (transcript.layout:layouter))

(fn make-test-runner []
  (var sessions {})
  (var session-count 0)
  (var turns [])
  (var cancelled [])

  (fn create-session [self agent-id]
    (set session-count (+ session-count 1))
    (local id (.. "test-ses-" session-count))
    (local session {:id id
                    :agent-id agent-id
                    :status :idle
                    :items []
                    :data {}
                    :created-at (os.time)
                    :updated-at (os.time)})
    (tset sessions id session)
    session)

  (fn get-session [self id]
    (local s (. sessions id))
    (when (not s)
      (. sessions (.. "test-ses-" 1)))
    s)

  (fn list-sessions [self]
    (local result [])
    (each [_ session (pairs sessions)]
      (table.insert result {:id session.id
                            :agent-id session.agent-id
                            :status session.status
                            :item-count (length session.items)
                            :created-at session.created-at
                            :updated-at session.updated-at}))
    result)

  (fn run-turn [self session-id input callbacks]
    (local turn-id (.. "turn-" (length turns)))
    (local session (. sessions session-id))
    (when session
      (table.insert session.items {:id (.. "item-" (+ (length session.items) 1))
                                   :type :message
                                   :role :user
                                   :content input
                                   :created-at (os.time)})
      (set session.status :running)
      (set session.updated-at (os.time)))
    (table.insert turns {:session-id session-id :input input :callbacks callbacks})
    (when callbacks.on-status
      (callbacks.on-status {:id turn-id
                            :session-id session-id
                            :status :running}))
    {:id turn-id
     :session-id session-id
     :status (fn [] :running)
     :result (fn [] nil)
     :error (fn [] nil)
     :cancel (fn [] true)
     :running? (fn [] true)
     :wait (fn [] :running)
     :start (fn [] nil)})

  (fn cancel-turn [self session-id]
    (table.insert cancelled session-id)
    true)

  (fn complete-last-turn [self]
    (local turn (. turns (length turns)))
    (local session (. sessions turn.session-id))
    (set session.status :idle)
    (set session.updated-at (os.time))
    (when turn.callbacks.on-complete
      (turn.callbacks.on-complete {:session-id turn.session-id
                                   :status :completed}))
    true)

  (fn update-last-item [self updates]
    (local turn (. turns (length turns)))
    (local session (. sessions turn.session-id))
    (local item (. session.items (length session.items)))
    (each [k v (pairs updates)]
      (tset item k v))
    (when turn.callbacks.on-update
      (turn.callbacks.on-update item.id updates))
    item)

  {:create-session create-session
   :get-session get-session
   :list-sessions list-sessions
   :run-turn run-turn
   :cancel-turn cancel-turn
   :complete-last-turn complete-last-turn
   :update-last-item update-last-item})

  (fn test-controller-init []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets (make-presets-stub))
  (local controller (AgentPanelController {:runner runner
                                              :registry registry
                                              :approvals approvals
                                              :presets presets}))
  (controller:init)
  (assert (not (not controller.state.active-agent-id))
          "controller should have active agent after init")
  (assert (= (length controller.state.agents) 1) "should have one agent")
  (assert (= (length controller.state.sessions) 1) "should create first session")
  (assert (not (not controller.state.active-session-id))
          "should have active session"))

  (fn test-controller-select-agent []
  (local registry (AgentRegistry {:deps {}}))
  (registry:register "agent-a" (fn [_deps] {:id "agent-a" :name "Agent A" :run (fn [] nil)}))
  (registry:register "agent-b" (fn [_deps] {:id "agent-b" :name "Agent B" :run (fn [] nil)}))
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets (make-presets-stub))
  (local controller (AgentPanelController {:runner runner
                                              :registry registry
                                              :approvals approvals
                                              :presets presets}))
  (controller:init)
  (assert (not (not controller.state.active-agent-id)) "should auto-select first agent")
  (controller:select-agent "agent-b")
  (assert (= controller.state.active-agent-id "agent-b") "should switch"))

  (fn test-controller-send-text []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets (make-presets-stub))
  (local controller (AgentPanelController {:runner runner
                                              :registry registry
                                              :approvals approvals
                                              :presets presets}))
  (controller:init)
  (local handle (controller:send "draw a circle"))
  (assert handle "send should return a turn handle"))

(fn test-controller-send-loads_user_message []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets (make-presets-stub))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals
                                              :presets presets}))
  (controller:init)
  (controller:send "draw a circle")
  (assert (= (length controller.state.items) 1)
          "send should refresh the appended user message")
  (assert (= (. controller.state.items 1 :content) "draw a circle")
          "send should expose the submitted content")
  (assert (= (. controller.state.sessions 1 :status) :running)
          "send should refresh the active session status")
  (assert (= (. controller.state.sessions 1 :item-count) 1)
          "send should refresh active session item count")
  (assert controller.state.active-turn
          "send should mark the controller running immediately")
  (runner:complete-last-turn)
  (assert (not controller.state.active-turn)
          "turn completion should clear active turn")
  (assert (= (. controller.state.sessions 1 :status) :idle)
          "turn completion should refresh the active session status"))


(fn test-controller-live-update-notifies []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets (make-presets-stub))
  (local controller (AgentPanelController {:runner runner
                                           :registry registry
                                           :approvals approvals
                                              :presets presets}))
  (controller:init)
  (controller:send "draw a circle")
  (var change-count 0)
  (controller.change-signal.connect
    (fn [_state]
      (set change-count (+ change-count 1))))
  (runner:update-last-item {:content "draw a square"})
  (assert (= (. controller.state.items 1 :content) "draw a square")
          "live update should mutate controller-visible item state")
  (assert (> change-count 0)
          "live update should notify the transcript"))

(fn test-transcript_auto_scrolls_only_from_live_edge []
  (local controller
    {:state {:items []}
     :toggle-expanded (fn [_self _item-id] nil)
     :item-expanded? (fn [_self _item-id] false)})
  (for [idx 1 18]
    (table.insert controller.state.items
                  {:id (.. "msg-" idx)
                   :type :message
                   :role :assistant
                   :content (.. "message " idx "\nline two\nline three")
                   :stream-status :complete}))
  (local transcript ((AgentTranscript controller) (make-widget-ctx)))
  (layout-test-transcript transcript)
  (assert (> transcript.scroll-view.state.max-offset 0)
          "transcript fixture should be scrollable")
  (assert (approx= transcript.scroll-view.state.scroll-offset 0)
          "transcript should initially start at the live edge")
  (transcript.scroll-view:set-scroll-offset 0.1)
  (layout-test-transcript transcript)
  (assert (= transcript.scroll-view.state.user-set-offset? true)
          "manual scroll should set user scroll state")
  (table.insert controller.state.items
                {:id "msg-while-scrolled-up"
                 :type :message
                 :role :assistant
                 :content "message while scrolled up"
                 :stream-status :streaming})
  (transcript:refresh)
  (layout-test-transcript transcript)
  (assert (approx= transcript.scroll-view.state.scroll-offset 0.1)
          "transcript refresh should preserve even a small positive manual scroll offset")
  (transcript.scroll-view:set-scroll-offset 0)
  (layout-test-transcript transcript)
  (table.insert controller.state.items
                {:id "msg-at-live-edge"
                 :type :message
                 :role :assistant
                 :content "message at live edge"
                 :stream-status :streaming})
  (transcript:refresh)
  (layout-test-transcript transcript)
  (assert (approx= transcript.scroll-view.state.scroll-offset 0)
          "transcript should keep following once the user returns to the live edge")
  (transcript:drop))

(fn test-controller-stop []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets (make-presets-stub))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals
                                              :presets presets}))
  (controller:init)
  (controller:stop)
  (assert (not controller.state.active-turn) "stop should clear active turn"))

(fn test-controller-toggle-expanded []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets (make-presets-stub))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals
                                              :presets presets}))
  (controller:init)
  (controller:toggle-expanded "item-1")
  (assert (controller:is-expanded? "item-1") "should expand")
  (controller:toggle-expanded "item-1")
  (assert (not (controller:is-expanded? "item-1")) "should collapse"))

(fn test-controller-get-active-agent []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets (make-presets-stub))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals
                                              :presets presets}))
  (controller:init)
  (local agent (controller:get-active-agent))
  (assert agent "should return active agent")
  (assert (= agent.id "test-agent") "should be correct agent"))

(fn test-controller-get-active-session []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets (make-presets-stub))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals
                                              :presets presets}))
  (controller:init)
  (local session (controller:get-active-session))
  (assert session "should return active session"))

(fn test-controller-new-session []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets (make-presets-stub))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals
                                              :presets presets}))
  (controller:init)
  (local session-count (length controller.state.sessions))
  (controller:new-session)
  (assert (= (length controller.state.sessions) (+ session-count 1))
          "should create new session"))

(fn test-controller-drop-disconnects []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets (make-presets-stub))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals
                                              :presets presets}))
  (controller:init)
  (var signaled? false)
  (controller.change-signal.connect (fn [] (set signaled? true)))
  (controller:drop)
  (set signaled? false)
  (set controller.state.active-agent-id "something")
  (assert (not signaled?) "signal should not fire after drop"))

(fn test-controller-select-session-loads-items []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets (make-presets-stub))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals
                                              :presets presets}))
  (controller:init)
  (assert (= (length controller.state.items) 0) "new session should have no items"))

(fn test-controller-init-selects-existing-session []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local presets (make-presets-stub))
  (local runner (make-test-runner))
  ;; Pre-create a session with items so load-sessions finds it before ensure-first-session.
  (local existing-session (runner:create-session "test-agent"))
  (table.insert existing-session.items {:id "item-1" :type :message :role :user :content "hello" :created-at (os.time)})
  (local controller (AgentPanelController {:runner runner
                                              :registry registry
                                              :approvals approvals
                                              :presets presets}))
  (controller:init)
  (assert (= controller.state.active-session-id existing-session.id)
          "ensure-first-session should select the first existing session instead of creating a new one")
  (assert (= (length controller.state.items) 1)
          "session items should be loaded when existing session is selected"))

(fn test-controller_tracks_pending_approval []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:destructive :ask}}))
  (local runner (make-test-runner))
  (local presets (make-presets-stub))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals
                                              :presets presets}))
  (controller:init)
  (var approved-result nil)
  (approvals:request-risk :destructive "delete world"
    {:on-approved (fn [r] (set approved-result r))
     :on-denied (fn [_r] nil)})
  (assert controller.state.pending-approval
          "controller should track pending approval requests")
  (controller:approve-pending)
  (assert approved-result "approve-pending should resolve approval")
  (assert (not controller.state.pending-approval)
          "approve-pending should clear pending approval"))

(fn test-controller_ignores_duplicate_pending_approval []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:destructive :ask}}))
  (local runner (make-test-runner))
  (local presets (make-presets-stub))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals
                                              :presets presets}))
  (controller:init)
  (approvals:request-risk :destructive "delete world"
    {:on-approved (fn [_r] nil)
     :on-denied (fn [_r] nil)}
    {:tool "space_delete_world" :grant-on-approve true})
  (local request controller.state.pending-approval)
  (assert request "controller should track first pending approval")
  (var change-count 0)
  (var approval-change-count 0)
  (controller.change-signal.connect
    (fn [_state]
      (set change-count (+ change-count 1))))
  (controller.approval-change-signal.connect
    (fn [_request]
      (set approval-change-count (+ approval-change-count 1))))
  (controller:sync-pending-approval request)
  (assert (= change-count 0)
          "duplicate pending approval should not notify the whole panel")
  (assert (= approval-change-count 0)
          "duplicate pending approval should not notify approval observers"))

(fn test-controller_approve_pending_always []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:shell :ask}}))
  (local runner (make-test-runner))
  (local presets (make-presets-stub))
  (local controller (AgentPanelController {:runner runner
                                             :registry registry
                                             :approvals approvals
                                              :presets presets}))
  (controller:init)
  (local context {:tool "space_app_run_bash"
                  :source "app.run-bash"
                  :args_hash "hash-a"
                  :grant-on-approve true})
  (approvals:request-risk :shell "run command"
    {:on-approved (fn [_r] nil)
     :on-denied (fn [_r] nil)}
    context)
  (assert controller.state.pending-approval
          "controller should track pending approval requests")
  (controller:approve-pending-always)
  (var approved-count 0)
  (approvals:request-risk :shell "run command"
    {:on-approved (fn [_r] (set approved-count (+ approved-count 1)))
     :on-denied (fn [_r] nil)}
    context)
  (approvals:request-risk :shell "run command"
    {:on-approved (fn [_r] (set approved-count (+ approved-count 1)))
     :on-denied (fn [_r] nil)}
    context)
  (assert (= approved-count 2)
          "approve-pending-always should grant repeated exact matches"))

(fn test-controller_hydrates_existing_pending_approval []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:destructive :ask}}))
  (local runner (make-test-runner))
  (local presets (make-presets-stub))
  (approvals:request-risk :destructive "delete world"
    {:on-approved (fn [_r] nil)
     :on-denied (fn [_r] nil)}
    {:tool "space_delete_world" :grant-on-approve true})
  (local controller (AgentPanelController {:runner runner
                                              :registry registry
                                              :approvals approvals
                                              :presets presets}))
  (controller:init)
  (assert controller.state.pending-approval
          "controller should hydrate approval that existed before listener attach")
  (assert (= controller.state.pending-approval.reason "delete world")
           "hydrated approval should be the pending request"))

(fn test-controller-requires-presets []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local (ok? err) (pcall (fn []
                             (AgentPanelController {:runner runner
                                                     :registry registry
                                                     :approvals approvals}))))
  (assert (not ok?)
          "controller should assert when :presets is missing"))

(fn test-load-presets-includes-inactive []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets
    (make-real-presets
      {:presets [{:name "drawing" :group "drawing" :risk :normal
                  :default-state :auto
                  :contexts [{:surface :canvas :activity "drawing"}]
                  :tool-ids ["drawing.inspect"]}
                 {:name "shell" :group "general" :risk :shell
                  :default-state :off
                  :contexts [{:surface :canvas}]
                  :tool-ids ["shell.run"]}]}))
  (local controller (AgentPanelController {:runner runner
                                            :registry registry
                                            :approvals approvals
                                            :presets presets}))
  (controller:init)
  (assert (= (length controller.state.preset-rows) 2)
          "should include both active and inactive presets")
  (var drawing-row nil)
  (var shell-row nil)
  (each [_ row (ipairs controller.state.preset-rows)]
    (if (= row.name "drawing") (set drawing-row row))
    (if (= row.name "shell") (set shell-row row)))
  (assert drawing-row "should include drawing preset")
  (assert shell-row "should include shell preset")
  (assert drawing-row.active? "drawing should be active when context matches")
  (assert (= drawing-row.active-reason :context)
          "drawing should be active due to context")
  (assert (not shell-row.active?)
          "shell should be inactive when default-state is off and no override"))

(fn test-set-preset-override-activates-mismatched []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets
    (make-real-presets
      {:presets [{:name "shell" :group "general" :risk :shell
                  :default-state :off
                  :contexts [{:surface :canvas}]
                  :tool-ids ["shell.run"]}]}))
  (local controller (AgentPanelController {:runner runner
                                            :registry registry
                                            :approvals approvals
                                            :presets presets}))
  (controller:init)
  (controller:set-preset-override "shell" :on)
  (var shell-row nil)
  (each [_ row (ipairs controller.state.preset-rows)]
    (if (= row.name "shell") (set shell-row row)))
  (assert shell-row "should include shell row")
  (assert (= shell-row.override-state :on)
          "override state should be :on after set-preset-override :on")
  (assert shell-row.active?
          "override :on should activate a default-off preset")
  (assert (= shell-row.active-reason :override)
          "override :on should report override activation reason"))

(fn test-set-preset-override-off-deactivates []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets
    (make-real-presets
      {:presets [{:name "drawing" :group "drawing" :risk :normal
                  :default-state :auto
                  :contexts [{:surface :canvas :activity "drawing"}]
                  :tool-ids ["drawing.inspect"]}]}))
  (local controller (AgentPanelController {:runner runner
                                            :registry registry
                                            :approvals approvals
                                            :presets presets}))
  (controller:init)
  (controller:set-preset-override "drawing" :off)
  (var drawing-row nil)
  (each [_ row (ipairs controller.state.preset-rows)]
    (if (= row.name "drawing") (set drawing-row row)))
  (assert drawing-row "should include drawing row")
  (assert (= drawing-row.override-state :off)
          "override state should be :off")
  (assert (not drawing-row.active?)
          "override :off should deactivate a context-matched preset"))

(fn test-set-preset-override-auto-restores-context []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets
    (make-real-presets
      {:presets [{:name "shell" :group "general" :risk :shell
                  :default-state :off
                  :contexts [{:surface :canvas}]
                  :tool-ids ["shell.run"]}]
       :overrides {:shell {:state :on}}}))
  (local controller (AgentPanelController {:runner runner
                                            :registry registry
                                            :approvals approvals
                                            :presets presets}))
  (controller:init)
  (controller:set-preset-override "shell" :auto)
  (var shell-row nil)
  (each [_ row (ipairs controller.state.preset-rows)]
    (if (= row.name "shell") (set shell-row row)))
  (assert shell-row "should include shell row")
  (assert (= shell-row.override-state :auto)
          "override state should be :auto after reset")
  (assert (not shell-row.active?)
          "auto should restore default-off inactive behavior"))

(fn test-reset-preset-overrides []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets
    (make-real-presets
      {:presets [{:name "drawing" :group "drawing" :risk :normal
                  :default-state :auto
                  :contexts [{:surface :canvas :activity "drawing"}]
                  :tool-ids ["drawing.inspect"]}
                 {:name "shell" :group "general" :risk :shell
                  :default-state :off
                  :contexts [{:surface :canvas}]
                  :tool-ids ["shell.run"]}]
       :overrides {:drawing {:state :on} :shell {:state :off}}}))
  (local controller (AgentPanelController {:runner runner
                                            :registry registry
                                            :approvals approvals
                                            :presets presets}))
  (controller:init)
  (controller:reset-preset-overrides)
  (each [_ row (ipairs controller.state.preset-rows)]
    (assert (= row.override-state :auto)
            (.. row.name " override should be :auto after reset"))))

(fn test-registry-change-refreshes-controller []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets
    (make-real-presets
      {:presets [{:name "drawing" :group "drawing" :risk :normal
                  :default-state :auto
                  :contexts [{:surface :canvas :activity "drawing"}]
                  :tool-ids ["drawing.inspect"]}]}))
  (local controller (AgentPanelController {:runner runner
                                            :registry registry
                                            :approvals approvals
                                            :presets presets}))
  (controller:init)
  (assert (= (length controller.state.preset-rows) 1)
          "should have 1 preset after init")
  (var change-count 0)
  (controller.change-signal.connect (fn [] (set change-count (+ change-count 1))))
  (presets.registry:register {:name "new-tools" :group "general" :risk :normal
                               :default-state :auto
                               :contexts [{:surface :canvas}]
                               :tool-ids ["new.tool"]})
  (assert (> change-count 0)
          "registry change should trigger controller refresh")
  (assert (= (length controller.state.preset-rows) 2)
          "should have 2 presets after register"))

(fn test-manager-override-change-refreshes-controller []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets
    (make-real-presets
      {:presets [{:name "drawing" :group "drawing" :risk :normal
                  :default-state :auto
                  :contexts [{:surface :canvas :activity "drawing"}]
                  :tool-ids ["drawing.inspect"]}]}))
  (local controller (AgentPanelController {:runner runner
                                            :registry registry
                                            :approvals approvals
                                            :presets presets}))
  (controller:init)
  (var change-count 0)
  (controller.change-signal.connect (fn [] (set change-count (+ change-count 1))))
  (presets:set-override "drawing" :on)
  (assert (> change-count 0)
          "override change should trigger controller refresh"))

(fn test-drop-removes-all-preset-listeners []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets
    (make-real-presets
      {:presets [{:name "drawing" :group "drawing" :risk :normal
                  :default-state :auto
                  :contexts [{:surface :canvas :activity "drawing"}]
                  :tool-ids ["drawing.inspect"]}]}))
  (local controller (AgentPanelController {:runner runner
                                            :registry registry
                                            :approvals approvals
                                            :presets presets}))
  (controller:init)
  ;; Registry listener should be registered
  (local registry-status-after-init (presets.registry:status))
  (assert (> registry-status-after-init.listener-count 0)
          "should have registry listener after init")
  (controller:drop)
  ;; After drop, no listeners should remain
  (local registry-status-after-drop (presets.registry:status))
  (assert (= registry-status-after-drop.listener-count 0)
          "should remove all registry listeners on drop")
  ;; After drop, changes should not trigger any notification
  (var change-count 0)
  (controller.change-signal.connect (fn [] (set change-count (+ change-count 1))))
  (presets.registry:register {:name "new-tools" :group "general" :risk :normal
                               :default-state :auto
                               :contexts [{:surface :canvas}]
                               :tool-ids ["new.tool"]})
  (presets:set-override "drawing" :on)
  (assert (= change-count 0)
          "no change signal should fire after drop"))

(fn test-session-list-builds-has-refresh []
  (local controller
    {:state {:sessions [{:id "test-session-1"
                         :status :idle
                         :title "Test Session"
                         :updated-at (os.time)}]
             :active-session-id "test-session-1"}
     :select-session (fn [_self _id] nil)})
  (local widget ((AgentSessionList controller) (make-widget-ctx)))
  (assert (= (type widget.refresh) :function)
          "session list widget should have a refresh method")
  (assert (= (type widget.drop) :function)
          "session list widget should have a drop method")
  (widget:refresh)
  (widget:drop))

(fn test-session-list-builds-with-workflow-timestamp []
  (local controller
    {:state {:sessions [{:id "workflow-session-1"
                         :status :idle
                         :title "Workflow Session"
                         :updated-at "2026-08-15T07:08:09Z"}]
             :active-session-id "workflow-session-1"}
     :select-session (fn [_self _id] nil)})
  (local widget ((AgentSessionList controller) (make-widget-ctx)))
  (assert (= (type widget.refresh) :function)
          "session list should build with canonical workflow timestamp strings")
  (widget:drop))

(fn test-panel-refresh-does-not-crash []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps]
    {:id "test-agent"
     :name "Test Agent"
     :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-test-runner))
  (local presets (make-presets-stub))
  (local panel-fn (AgentPanel {:runner runner
                                :registry registry
                                :approvals approvals
                                :presets presets}))
  (local ctx (make-widget-ctx))
  (local panel (panel-fn ctx))
  (panel.controller:init)
  (assert (not (not panel.controller.state.active-agent-id))
          "controller should have active agent after init")
  (panel:drop))

(fn test-preset-list-builds-expanded-row []
  (local controller
    {:state {:preset-groups ["general"]
             :preset-rows [{:name "shell"
                            :group "general"
                            :risk :shell
                            :default-state :off
                            :contexts [{:surface :canvas}]
                            :tool-ids ["shell.run"]
                            :tool-count 1
                            :override-state :auto
                            :active? false
                            :active-reason nil}]}
     :set-preset-override (fn [_self _name _state] nil)
     :reset-preset-overrides (fn [_self] nil)
      :toggle-group-override (fn [_self _group-name] nil)
      :get-preset-group-override-state (fn [self group-name]
                                         (var s nil)
                                         (each [_ row (ipairs self.state.preset-rows)]
                                           (when (= row.group group-name)
                                             (if (= s nil) (set s row.override-state)
                                                 (not (= s row.override-state)) (set s :mixed))))
                                         (or s :auto))
     :toggle-preset-group-expanded (fn [_self _group-name] nil)
     :is-preset-group-expanded? (fn [_self _group-name] true)
     :toggle-preset-expanded (fn [_self _preset-name] nil)
     :is-preset-expanded? (fn [_self _preset-name] true)})
  (local widget ((AgentPresetList controller) (make-widget-ctx)))
  (widget:refresh)
  (widget:drop))

(table.insert tests {:name "controller init creates first session"
                     :fn test-controller-init})
(table.insert tests {:name "controller select agent switches active agent"
                     :fn test-controller-select-agent})
(table.insert tests {:name "controller send returns turn handle"
                     :fn test-controller-send-text})
(table.insert tests {:name "controller send loads user message"
                      :fn test-controller-send-loads_user_message})
(table.insert tests {:name "controller live update notifies"
                     :fn test-controller-live-update-notifies})
(table.insert tests {:name "transcript auto-scrolls only from live edge"
                     :fn test-transcript_auto_scrolls_only_from_live_edge})
(table.insert tests {:name "controller stop clears active turn"
                     :fn test-controller-stop})
(table.insert tests {:name "controller toggle expanded toggles expanded state"
                     :fn test-controller-toggle-expanded})
(table.insert tests {:name "controller get-active-agent"
                     :fn test-controller-get-active-agent})
(table.insert tests {:name "controller get-active-session"
                     :fn test-controller-get-active-session})
(table.insert tests {:name "controller new-session creates session"
                     :fn test-controller-new-session})
(table.insert tests {:name "controller drop disconnects signals"
                     :fn test-controller-drop-disconnects})
(table.insert tests {:name "controller select-session loads items"
                     :fn test-controller-select-session-loads-items})
(table.insert tests {:name "controller init selects existing session"
                     :fn test-controller-init-selects-existing-session})
(table.insert tests {:name "controller tracks pending approval"
                     :fn test-controller_tracks_pending_approval})
(table.insert tests {:name "controller ignores duplicate pending approval"
                     :fn test-controller_ignores_duplicate_pending_approval})
(table.insert tests {:name "controller approve pending always"
                     :fn test-controller_approve_pending_always})
(table.insert tests {:name "controller hydrates existing pending approval"
                     :fn test-controller_hydrates_existing_pending_approval})
(table.insert tests {:name "controller requires presets"
                     :fn test-controller-requires-presets})
(table.insert tests {:name "load-presets includes inactive presets"
                     :fn test-load-presets-includes-inactive})
(table.insert tests {:name "set-preset-override :on activates mismatched"
                     :fn test-set-preset-override-activates-mismatched})
(table.insert tests {:name "set-preset-override :off deactivates"
                     :fn test-set-preset-override-off-deactivates})
(table.insert tests {:name "set-preset-override :auto restores context behavior"
                     :fn test-set-preset-override-auto-restores-context})
(table.insert tests {:name "reset-preset-overrides returns all to auto"
                     :fn test-reset-preset-overrides})
(table.insert tests {:name "registry change refreshes controller"
                     :fn test-registry-change-refreshes-controller})
(table.insert tests {:name "manager override change refreshes controller"
                     :fn test-manager-override-change-refreshes-controller})
(table.insert tests {:name "drop removes all preset listeners"
                     :fn test-drop-removes-all-preset-listeners})
(table.insert tests {:name "preset list builds expanded row"
                     :fn test-preset-list-builds-expanded-row})
(table.insert tests {:name "session list builds has refresh"
                      :fn test-session-list-builds-has-refresh})
(table.insert tests {:name "session list builds with workflow timestamp"
                     :fn test-session-list-builds-with-workflow-timestamp})
(table.insert tests {:name "panel refresh does not crash"
                      :fn test-panel-refresh-does-not-crash})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "agent-panel"
                      :tests tests}))

(fn workflow-panel-agent-run [_agent _input _session ctx]
  (ctx.turn:finish {:ok true}))

(fn workflow-panel-registry-get [_self id]
  {:id id
   :name "Workflow Test Agent"
   :run workflow-panel-agent-run})

(fn workflow-panel-required-deps []
  {:app {}
   :presets {}
   :tools {}
   :approvals {}
   :agents {}
   :providers {}})

(fn make-workflow-panel-runner []
  (local fs (require :fs))
  (local Uuid (require :uuid))
  (local {: WorkflowStore} (require :workflows/store))
  (local {: WorkflowRunner} (require :workflows/runner))
  (local {: WorkflowCodeExecutor} (require :workflows/code-executor))
  (local {: CodeEntityStore} (require :entities/code))
  (local {: WorkflowAgentRunner} (require :llm/agent/workflow-runner))
  (local dir (fs.join-path "/tmp/space/tests/agent-panel-workflow-runner" (Uuid.v4)))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local workflow-store (WorkflowStore {:base-dir dir}))
  (local code-store (CodeEntityStore {:base-dir dir}))
  (local executor (WorkflowCodeExecutor {:code-store code-store :app {}}))
  (local workflow-runner (WorkflowRunner {:store workflow-store :executor executor :app {}}))
  (WorkflowAgentRunner {:workflow-store workflow-store
                        :workflow-runner workflow-runner
                         :code-store code-store
                         :registry {:get workflow-panel-registry-get}
                         :artifact-root (fs.join-path dir "agent-artifacts")
                         :deps (workflow-panel-required-deps)}))

(fn test-controller-send-loads-user-message-with-workflow-runner []
  (local registry (AgentRegistry {:deps {}}))
  (fn make-agent [_deps] {:id "test-agent" :name "Test Agent" :run (fn [] nil)})
  (registry:register "test-agent" make-agent)
  (local approvals (AgentApprovals {:policy {:normal :auto}}))
  (local runner (make-workflow-panel-runner))
  (local presets (make-presets-stub))
  (local controller (AgentPanelController {:runner runner
                                           :registry registry
                                           :approvals approvals
                                           :presets presets}))
  (controller:init)
  (local handle (controller:send "draw a workflow circle"))
  (assert handle "workflow-backed send should return a turn handle")
  (assert (= (length controller.state.items) 1)
          "workflow-backed send should refresh the appended user message")
  (assert (= (. controller.state.items 1 :content) "draw a workflow circle")
          "workflow-backed send should expose submitted content")
  (assert (= (. controller.state.sessions 1 :status) :idle)
          "workflow-backed completed turn should project idle status")
  (assert (= (. controller.state.sessions 1 :item-count) 1)
          "workflow-backed session summary should expose item count")
  (runner:drop))

(table.insert tests {:name "controller send loads user message with workflow runner"
                     :fn test-controller-send-loads-user-message-with-workflow-runner})

{:tests tests
  :main main}
