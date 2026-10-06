(local _ (require :main))
(local glm (require :glm))
(local MenuManager (require :menu-manager))
(local ContextMenuState (require :context-menu-state))
(local LeaderState (require :leader-state))
(local States (require :states))
(local {: Layout} (require :layout))

(local tests [])
(var action-calls nil)
(var state-action-states nil)

(local KEY_G (string.byte "g"))
(local KEY_N (string.byte "n"))
(local KEY_M (string.byte "m"))

(fn reset-engine-events []
  (when _G.reset-engine-events
    (_G.reset-engine-events)))

(fn noop [_self _value] nil)
(fn vector-allocate [_self _count] 1)
(fn vector-delete [_self _handle] nil)
(fn vector-set [_self _handle _offset _value] nil)
(fn icon-resolve [_self _name] nil)
(fn upsert-text [_batcher _key _opts] nil)
(fn update-text-transform [_batcher _key _opts] nil)
(fn remove-text [_batcher _key] nil)
(fn text-batcher [_self]
  {:upsert-text upsert-text
   :update-text-transform update-text-transform
   :remove-text remove-text})
(fn record-first [_button _event]
  (table.insert action-calls "First"))

(fn record-second [_button _event]
  (table.insert action-calls "Second"))

(fn record-click [_button _event]
  (table.insert action-calls "Click"))

(fn set-normal-state [_button _event]
  (state-action-states:set-state :normal))

(fn command-hints-toggle [_self _payload]
  true)

(fn command-hints-close-on-handled [_self _route-key _payload]
  false)

(fn provide-hud [hud]
  (fn [_self]
    hud))

(fn run-open-context-menu [_ctx]
  (app.menu-manager:open
    {:actions [{:name "First" :fn record-first}]
     :position (glm.vec3 0 0 0)})
  true)

(fn make-vector-buffer []
  {:allocate vector-allocate
   :delete vector-delete
   :set-glm-vec3 vector-set
   :set-glm-vec4 vector-set
   :set-glm-vec2 vector-set
   :set-float vector-set})

(fn make-clickables-stub []
  (local state {:right-void nil :left-void nil})
  (local stub {:state state})
  (set stub.register noop)
  (set stub.unregister noop)
  (set stub.register-right-click noop)
  (set stub.unregister-right-click noop)
  (set stub.register-double-click noop)
  (set stub.unregister-double-click noop)
  (set stub.register-left-click-void-callback
       (fn [_self cb] (set state.left-void cb)))
  (set stub.register-right-click-void-callback
       (fn [_self cb] (set state.right-void cb)))
  (set stub.unregister-left-click-void-callback
       (fn [_self cb]
         (when (= state.left-void cb)
           (set state.left-void nil))))
  (set stub.unregister-right-click-void-callback
       (fn [_self cb]
         (when (= state.right-void cb)
           (set state.right-void nil))))
  stub)

(fn make-test-ctx [clickables]
  (local text-buffer (make-vector-buffer))
  (fn get-text-vector [_self _font]
    text-buffer)
  {:triangle-vector (make-vector-buffer)
   :clickables clickables
   :hoverables {:register noop
                :unregister noop}
   :icons {:resolve icon-resolve}
   :get-text-vector get-text-vector
   :get-text-ssbo-batcher text-batcher})

(fn no-op-action [_button _event]
  nil)

(fn make-hud-stub [ctx]
  (local overlay-layout
    (Layout {:name "context-menu-state-test-overlay"
             :measurer (fn [self] (set self.measure (glm.vec3 0 0 0)))
             :layouter (fn [_self] nil)}))
  (local overlay-root {:children [] :layout overlay-layout})
  (local hud {:build-context ctx
              :overlay-root overlay-root
              :command-hints {:handle-toggle-key command-hints-toggle
                              :close-on-handled-event command-hints-close-on-handled}})
  (fn add-overlay-child [_self opts]
    (local element ((assert opts.builder "hud add-overlay-child requires builder") ctx {}))
    (table.insert overlay-root.children {:element element
                                        :position (assert opts.position "test overlay requires position")})
    (overlay-layout:add-child element.layout)
    element)
  (fn remove-overlay-child [_self element]
    (var removed? false)
    (for [idx (length overlay-root.children) 1 -1]
      (when (= (. overlay-root.children idx :element) element)
        (set removed? true)
        (overlay-layout:remove-child idx)
        (table.remove overlay-root.children idx)))
    (when (and removed? element element.drop)
      (element:drop))
    removed?)
  (fn screen-pos-ray [_self pos]
    {:origin (glm.vec3 (assert pos.x "screen ray test requires x")
                       (assert pos.y "screen ray test requires y")
                       10)
     :direction (glm.vec3 0 0 -1)})
  (set hud.add-overlay-child add-overlay-child)
  (set hud.remove-overlay-child remove-overlay-child)
  (set hud.screen-pos-ray screen-pos-ray)
  hud)

(fn make-context-menu-fixture []
  (reset-engine-events)
  (local clickables (make-clickables-stub))
  (local ctx (make-test-ctx clickables))
  (local hud (make-hud-stub ctx))
  (local manager (MenuManager {:clickables clickables :hud hud}))
  (local states (States {:hud_provider (provide-hud hud)}))
  (states:add-state :normal {})
  (states:add-state :leader {})
  (states:add-state :context-menu (ContextMenuState))
  (states:set-state :leader)
  (set app.states states)
  (set app.menu-manager manager)
  {:states states :manager manager :hud hud})

(fn open-menu-leader-provider []
  {:commands {"demo.open-context-menu" {:id "demo.open-context-menu"
                                         :label "open context menu"
                                         :run run-open-context-menu}}
   :prefixes [{:keys ["g"] :label "graph" :priority 10}
              {:keys ["g" "n"] :label "node" :priority 10}]
   :bindings [{:keys ["g" "n" "m"]
               :command "demo.open-context-menu"
               :label "menu"
               :priority 10}]})

(fn make-leader-context-menu-fixture []
  (reset-engine-events)
  (local clickables (make-clickables-stub))
  (local ctx (make-test-ctx clickables))
  (local hud (make-hud-stub ctx))
  (local manager (MenuManager {:clickables clickables :hud hud}))
  (local states (States {:hud_provider (provide-hud hud)}))
  (states:add-state :normal {})
  (states:add-state :leader (LeaderState))
  (states:add-state :context-menu (ContextMenuState))
  (states:set-state :leader)
  (set app.states states)
  (set app.menu-manager manager)
  {:states states :manager manager :hud hud})

(fn drop-context-menu-fixture [fixture]
  (fixture.manager:drop)
  (fixture.states:drop))

(fn run-context-menu-fixture [f]
  (local original-states app.states)
  (local original-menu-manager app.menu-manager)
  (local fixture (make-context-menu-fixture))
  (local (ok result) (pcall f fixture))
  (drop-context-menu-fixture fixture)
  (set app.states original-states)
  (set app.menu-manager original-menu-manager)
  (if ok result (error result)))

(fn run-leader-context-menu-fixture [f]
  (local original-states app.states)
  (local original-menu-manager app.menu-manager)
  (local original-providers app.activity-leader-command-providers)
  (local fixture (make-leader-context-menu-fixture))
  (set app.activity-leader-command-providers [(open-menu-leader-provider)])
  (local (ok result) (pcall f fixture))
  (drop-context-menu-fixture fixture)
  (set app.activity-leader-command-providers original-providers)
  (set app.states original-states)
  (set app.menu-manager original-menu-manager)
  (if ok result (error result)))

(fn assert-open-enters-context-menu-and-escape-restores [fixture]
  (fixture.manager:open {:actions [{:name "Action" :fn no-op-action}]
                         :position (glm.vec3 0 0 0)})
  (assert (= (fixture.states:active-name) :context-menu)
          "opening any MenuManager context menu should enter context-menu state")
  (app.engine.events.key-down.emit {:key 27})
  (assert (= (fixture.states:active-name) :leader)
          "Escape should restore the state active before the menu opened")
  (assert (= (length fixture.hud.overlay-root.children) 0)
          "Escape should close the menu overlay"))

(fn open-enters-context-menu-and-escape-restores []
  (run-context-menu-fixture assert-open-enters-context-menu-and-escape-restores))

(fn assert-digit-invokes-action-and-restores [fixture]
  (set action-calls [])
  (fixture.manager:open {:actions [{:name "First" :fn record-first}
                                   {:name "Second" :fn record-second}]
                         :position (glm.vec3 0 0 0)})
  (app.engine.events.key-down.emit {:key (string.byte "2")})
  (assert (= (length action-calls) 1) "digit key should invoke exactly one action")
  (assert (= (. action-calls 1) "Second") "digit 2 should invoke the second actionable item")
  (assert (= (fixture.states:active-name) :leader)
          "numeric action should restore the previous state"))

(fn digit-invokes-action-and-restores []
  (run-context-menu-fixture assert-digit-invokes-action-and-restores))

(fn assert-digits-skip-separators [fixture]
  (set action-calls [])
  (fixture.manager:open {:actions [{:name "First" :fn record-first}
                                   {:type :separator}
                                   {:name "Second" :fn record-second}]
                         :position (glm.vec3 0 0 0)})
  (app.engine.events.key-down.emit {:key (string.byte "2")})
  (assert (= (. action-calls 1) "Second") "separator rows should not consume numeric slots"))

(fn digits-skip-separators []
  (run-context-menu-fixture assert-digits-skip-separators))

(fn assert-command-hints-list-actions-and-close [fixture]
  (fixture.manager:open {:actions [{:name "First" :fn record-first}
                                   {:type :separator}
                                   {:name "Second" :fn record-second}]
                         :position (glm.vec3 0 0 0)})
  (local state (fixture.states:active-state))
  (assert state.command_hints_provider
          "context-menu state should expose command hints while active")
  (local sections (state.command_hints_provider state {}))
  (assert (= (length sections) 1) "context menu should expose one command hint section")
  (local menu-section (. sections 1))
  (assert (= menu-section.id :context) "context menu hints should use context section id")
  (assert (= menu-section.title "MENU") "context menu hints should label the section MENU")
  (assert (= (length menu-section.entries) 3)
          "context menu hints should include actions plus escape")
  (assert (= (. menu-section.entries 1 :key) "1") "first actionable item should be shortcut 1")
  (assert (= (. menu-section.entries 1 :label) "First") "first hint should use first action label")
  (assert (= (. menu-section.entries 2 :key) "2") "separator should not consume shortcut 2")
  (assert (= (. menu-section.entries 2 :label) "Second") "second hint should use second action label")
  (assert (= (. menu-section.entries 3 :key) "esc") "context menu hints should include escape")
  (assert (= (. menu-section.entries 3 :label) "close") "escape hint should close the menu"))

(fn command-hints-list-actions-and-close []
  (run-context-menu-fixture assert-command-hints-list-actions-and-close))

(fn assert-command-hints-limit-actions-to-nine [fixture]
  (fixture.manager:open {:actions [{:name "One" :fn no-op-action}
                                   {:name "Two" :fn no-op-action}
                                   {:name "Three" :fn no-op-action}
                                   {:name "Four" :fn no-op-action}
                                   {:name "Five" :fn no-op-action}
                                   {:name "Six" :fn no-op-action}
                                   {:name "Seven" :fn no-op-action}
                                   {:name "Eight" :fn no-op-action}
                                   {:name "Nine" :fn no-op-action}
                                   {:name "Ten" :fn no-op-action}]
                         :position (glm.vec3 0 0 0)})
  (local state (fixture.states:active-state))
  (local sections (state.command_hints_provider state {}))
  (local entries (. sections 1 :entries))
  (assert (= (length entries) 10)
          "context menu hints should include nine numeric actions plus escape")
  (assert (= (. entries 9 :key) "9") "ninth action should use shortcut 9")
  (assert (= (. entries 9 :label) "Nine") "ninth action should still be exposed")
  (assert (= (. entries 10 :key) "esc") "tenth menu action should not expose unsupported digit")
  (assert (= (. entries 10 :label) "close") "escape should remain after numeric actions"))

(fn command-hints-limit-actions-to-nine []
  (run-context-menu-fixture assert-command-hints-limit-actions-to-nine))

(fn assert-action-state-change-is-not-overridden [fixture]
  (set state-action-states fixture.states)
  (fixture.manager:open {:actions [{:name "Go Normal"
                                    :fn set-normal-state}]
                         :position (glm.vec3 0 0 0)})
  (app.engine.events.key-down.emit {:key (string.byte "1")})
  (assert (= (fixture.states:active-name) :normal)
          "closing after an action should not override an explicit state transition"))

(fn action-state-change-is-not-overridden []
  (run-context-menu-fixture assert-action-state-change-is-not-overridden))

(fn assert-mouse-click-still-invokes-action-while-context-menu-active [fixture]
  (set action-calls [])
  (fixture.manager:open {:actions [{:name "Click" :fn record-click}]
                         :position (glm.vec3 0 0 0)})
  (assert (= (fixture.states:active-name) :context-menu))
  (local menu (. (. fixture.hud.overlay-root.children 1) :element))
  (local button (. menu.buttons 1))
  (button:on-click {:button 1})
  (assert (= (. action-calls 1) "Click") "menu buttons should remain clickable in context-menu state"))

(fn mouse-click-still-invokes-action-while-context-menu-active []
  (run-context-menu-fixture assert-mouse-click-still-invokes-action-while-context-menu-active))

(fn assert-leader-opened-menu-keeps-context-menu-routing [fixture]
  (set action-calls [])
  (app.engine.events.key-down.emit {:key KEY_G})
  (app.engine.events.key-down.emit {:key KEY_N})
  (app.engine.events.key-down.emit {:key KEY_M})
  (assert (= (fixture.states:active-name) :context-menu)
          "leader command that opens a context menu should leave context-menu active")
  (app.engine.events.key-down.emit {:key (string.byte "1")})
  (assert (= (. action-calls 1) "First")
          "numeric key should route through context-menu state after leader-opened menu")
  (assert (= (fixture.states:active-name) :leader)
          "numeric action should restore the state active before the menu opened"))

(fn leader-opened-menu-keeps-context-menu-routing []
  (run-leader-context-menu-fixture assert-leader-opened-menu-keeps-context-menu-routing))

(table.insert tests {:name "open enters context-menu state and Escape restores"
                     :fn open-enters-context-menu-and-escape-restores})
(table.insert tests {:name "digit invokes action and restores"
                     :fn digit-invokes-action-and-restores})
(table.insert tests {:name "digits skip separators"
                      :fn digits-skip-separators})
(table.insert tests {:name "command hints list actions and close"
                      :fn command-hints-list-actions-and-close})
(table.insert tests {:name "command hints limit actions to nine"
                      :fn command-hints-limit-actions-to-nine})
(table.insert tests {:name "action state change is not overridden"
                     :fn action-state-change-is-not-overridden})
(table.insert tests {:name "mouse click still invokes action while context-menu active"
                      :fn mouse-click-still-invokes-action-while-context-menu-active})
(table.insert tests {:name "leader-opened menu keeps context-menu key routing"
                      :fn leader-opened-menu-keeps-context-menu-routing})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "context-menu-state"
                       :tests tests})))

{:name "context-menu-state"
 :tests tests
 :main main}
