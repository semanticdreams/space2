(global app (or app {}))

(local glm (require :glm))
(local Hud (require :hud))
(local States (require :states))
(local State (require :state))
(local Routes (require :state-routes))
(local HudCommandHints (require :hud-command-hints))
(local TerrainPaintState (require :terrain-paint-state))
(local TerrainPaintManager (require :graph/view/terrain-paint-manager))
(local TerrainRectPickState (require :terrain-rect-pick-state))
(local TerrainRectPickManager (require :graph/view/terrain-rect-pick-manager))
(local TextState (require :text-state))
(local InsertState (require :insert-state))
(local InputState (require :input-state-router))
(local InputModel (require :input-model))
(local StateSystemBindings (require :state-system-bindings))
(local TextInputHandlers (require :state-handlers/text-input))
(local HudLayout (require :hud-layout))
(local StatusPanel (require :hud-status-panel))
(local {: Layout} (require :layout))
(local {: entry : section : KEY_F1} (require :command-hints))

(local tests [])

(fn fixed-widget [name measure]
  (fn [_ctx]
    (local layout
      (Layout {:name name
               :measurer (fn [self]
                           (set self.measure measure))
               :layouter (fn [self]
                           (set self.size (or self.size self.measure)))}))
    {:layout layout
     :drop (fn [_self]
              (layout:drop))}))

(fn make-input-stub [opts]
  (local options (or opts {}))
  (local model (InputModel {:text (or options.text "")}))
  (local initial-cursor (or options.cursor-index 0))
  (local stub {:model model
               :cursor-index model.cursor-index
               :cursor-line model.cursor-line
               :cursor-column model.cursor-column
               :codepoints model.codepoints
               :lines model.lines
               :mode model.mode
               :inserted []
               :multiline? (and (= options.multiline? true))})

  (fn sync []
    (set stub.cursor-index model.cursor-index)
    (set stub.cursor-line (or model.cursor-line 0))
    (set stub.cursor-column (or model.cursor-column 0))
    (set stub.codepoints model.codepoints)
    (set stub.lines model.lines)
    (set stub.mode model.mode))

  (set stub.enter-insert-mode (fn [_self]
                                (model:enter-insert-mode)
                                (sync)
                                true))
  (set stub.enter-normal-mode (fn [_self]
                                (model:enter-normal-mode)
                                (sync)
                                true))
  (set stub.move-caret (fn [_self delta]
                         (local moved (model:move-caret delta))
                         (when moved
                           (sync))
                         moved))
  (set stub.move-caret-to (fn [_self position]
                            (local moved (model:move-caret-to position))
                            (when moved
                              (sync))
                            moved))
  (set stub.insert-text (fn [self text]
                          (when text
                            (table.insert self.inserted text)
                            (model:insert-text text)
                            (sync))
                          true))
  (set stub.on-key-down (fn [_self _payload] false))
  (model:move-caret-to initial-cursor)
  (sync)
  stub)

(fn set-app-states! [states]
  (StateSystemBindings.bind-states-host states)
  (set app.states states)
  states)

(fn build-test-hud [states opts]
  (local options (or opts {}))
  (local hud (Hud {:states states :icons options.icons}))
  (hud:build
    (HudLayout.make-hud-builder
      {:control-builder (or options.control-builder
                             (fixed-widget "control" (glm.vec3 8 3 0)))
       :status-builder options.status-builder :right-dock-builder options.right-dock-builder}))
  (hud:update-projection (or options.viewport {:width 1920 :height 1080}))
  (hud:update)
  (when (and states states.set-hud-provider)
    (states:set-hud-provider (fn [_states]
                               hud)))
  (when (and states states.set-focus-manager-provider)
    (states:set-focus-manager-provider (fn [_states]
                                         hud.focus-manager)))
  hud)

(fn state-with-hints [name hints]
 {:name name
   :command_hints_provider
   (fn [_self _ctx]
     [(section :mode "MODE" hints)])})

(fn hint-aware-state [opts]
  (local options {})
  (each [k v (pairs opts)]
    (set (. options k) v))
  (set options.route-wrappers [Routes.CommandHints])
  (when (not options.hud_provider)
    (set options.hud_provider (fn [_state]
                                app.hud)))
  (State options))

(fn hud-command-strip-follows-active-state []
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:add-state :leader (state-with-hints :leader [(entry "q" "quit-mode" {:priority 20})]))
  (states:set-state :normal)
  (set-app-states! states)
  (local hud (build-test-hud states))
  (set app.hud hud)
  (hud:update)
  (local initial (hud.command-hints:get-collapsed-text))
  (assert (string.find initial "%[space%] leader")
          "normal mode should expose leader in the collapsed strip")
  (states:set-state :leader)
  (hud:update)
  (local updated (hud.command-hints:get-collapsed-text))
  (assert (string.find updated "%[q%] quit%-mode")
          "leader mode should expose quit-mode after a state change")
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn status-panel-update-populates-width-based-collapsed-field []
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:set-state :normal)
  (set-app-states! states)
  (local hud (build-test-hud states))
  (set app.hud hud)
  (hud:update)
  (assert (string.find hud.command-hints.collapsed "%[space%] leader")
          "status-panel width path should populate the collapsed field with visible commands")
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn hud-command-overlay-live-updates []
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:add-state :leader (state-with-hints :leader [(entry "q" "quit-mode" {:priority 20})]))
  (states:set-state :normal)
  (set-app-states! states)
  (local hud (build-test-hud states))
  (set app.hud hud)
  (assert (hud.command-hints:toggle-overlay)
          "command hints overlay should toggle open")
  (hud:update)
  (local initial (hud.command-hints:get-overlay-text))
  (assert (string.find initial "COMMANDS")
          "overlay should include a heading")
  (assert (string.find initial "%[space%] leader")
          "overlay should render the normal-mode commands")
  (states:set-state :leader)
  (hud:update)
  (local updated (hud.command-hints:get-overlay-text))
  (assert (string.find updated "%[q%] quit%-mode")
          "overlay should live-update when the active state changes")
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn declarative-state-command-hints-provider-works []
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal
                    (hint-aware-state
                      {:name :normal
                       :command_hints_provider (fn [_self _ctx]
                                                 [(section :mode
                                                           "MODE"
                                                           [(entry "x" "inline-provider" {:priority 10})])])
                       :routes {}}))
  (states:set-state :normal)
  (set-app-states! states)
  (local hud (build-test-hud states))
  (set app.hud hud)
  (hud:update)
  (local collapsed (hud.command-hints:get-collapsed-text))
  (assert (string.find collapsed "%[x%] inline%-provider")
          "State should expose command hints directly from command_hints_provider options")
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn hud-command-hints-use-hud-states-over-globals []
  (local original-states app.states)
  (local original-hud app.hud)
  (local hud-states (States))
  (hud-states:add-state :normal (state-with-hints :normal [(entry "h" "hud-state" {:priority 10})]))
  (hud-states:set-state :normal)
  (local global-states (States))
  (global-states:add-state :normal (state-with-hints :normal [(entry "g" "global-state" {:priority 10})]))
  (global-states:set-state :normal)
  (set-app-states! global-states)
  (local hud (build-test-hud hud-states))
  (set app.hud hud)
  (hud:update)
  (local collapsed (hud.command-hints:get-collapsed-text))
  (assert (string.find collapsed "%[h%] hud%-state")
          "command hints should read the HUD's injected states instance")
  (assert (not (string.find collapsed "%[g%] global%-state"))
          "command hints should ignore unrelated global state registries")
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn hud-command-hints-use-hud-focus-manager-over-globals []
  (local original-states app.states)
  (local original-hud app.hud)
  (local original-focus app.focus)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:set-state :normal)
  (set-app-states! states)
  (local hud (build-test-hud states))
  (set hud.focus-manager
       {:get-focused-node (fn [_self]
                            {:command_hints_provider (fn [_owner _payload]
                                                       [(section :focus
                                                                 "FOCUS"
                                                                 [(entry "h" "hud-focus" {:priority 10})])])})})
  (set app.focus
       {:get-focused-node (fn [_self]
                            {:command_hints_provider (fn [_owner _payload]
                                                       [(section :focus
                                                                 "FOCUS"
                                                                 [(entry "g" "global-focus" {:priority 10})])])})})
  (set app.hud hud)
  (assert (hud.command-hints:toggle-overlay)
          "overlay should open for HUD focus manager test")
  (hud:update)
  (local text (hud.command-hints:get-overlay-text))
  (assert (string.find text "%[h%] hud%-focus")
          "command hints should read focus entries from the HUD focus manager")
  (assert (not (string.find text "%[g%] global%-focus"))
          "command hints should ignore unrelated global focus managers")
  (hud:drop)
  (set app.focus original-focus)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn f1-toggle-opens-and-command-closes-overlay []
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:set-state :normal)
  (set-app-states! states)
  (local hud (build-test-hud states))
  (set app.hud hud)
  (local subject
    (hint-aware-state
      {:name :subject
       :routes {:key-down (Routes.FirstHandlerWins [{:key-down (fn [ctx payload]
                                                                 (if (= payload.key (string.byte "x"))
                                                                     (do
                                                                       ((. ctx :mark-command-executed!))
                                                                       true)
                                                                     false))}])
                :text-input (Routes.FirstHandlerWins [TextInputHandlers.TextInputDispatch])}}))
  (assert (subject:on-key-down {:key KEY_F1})
          "F1 should be handled by the shared state toggle path")
  (assert (hud.command-hints:overlay-open?)
          "F1 should open the overlay")
  (assert (not (subject:on-text-input {:text "?"}))
          "text-input without an active input should not report handled")
  (assert (hud.command-hints:overlay-open?)
          "passive text-input should not immediately close the overlay")
  (assert (subject:on-key-down {:key (string.byte "x")})
          "handled key commands should still flow through the wrapped route")
  (assert (not (hud.command-hints:overlay-open?))
          "a handled non-toggle command should close the overlay")
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn handled-but-unmarked-key-does-not-close-overlay []
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:set-state :normal)
  (set-app-states! states)
  (local hud (build-test-hud states))
  (set app.hud hud)
  (local subject
    (hint-aware-state
      {:name :subject
       :routes {:key-down (Routes.FirstHandlerWins [{:key-down (fn [ctx payload]
                                                                 (if (= payload.key (string.byte "x"))
                                                                     (do
                                                                       ((. ctx :mark-command-executed!))
                                                                       true)
                                                                     (= payload.key (string.byte "z"))))}])}}))
  (assert (subject:on-key-down {:key KEY_F1})
          "F1 should open the overlay before command checks")
  (assert (hud.command-hints:overlay-open?)
          "overlay should start open")
  (assert (subject:on-key-down {:key (string.byte "z")})
          "handled but unmarked keys should still report handled")
  (assert (hud.command-hints:overlay-open?)
          "handled but unmarked keys should not close the overlay")
  (assert (subject:on-key-down {:key (string.byte "x")})
          "marked commands should still report handled")
  (assert (not (hud.command-hints:overlay-open?))
          "marked commands should close the overlay")
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn route-command-hints-use-state-hud-provider-over-app-hud []
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:set-state :normal)
  (set-app-states! states)
  (local app-hud (build-test-hud states))
  (local state-hud (build-test-hud states))
  (set app.hud app-hud)
  (local subject
    (hint-aware-state
      {:name :subject
       :hud_provider (fn [_state]
                       state-hud)
       :routes {:key-down (Routes.FirstHandlerWins [{:key-down (fn [ctx payload]
                                                                 (if (= payload.key (string.byte "x"))
                                                                     (do
                                                                       ((. ctx :mark-command-executed!))
                                                                       true)
                                                                     false))}])}}))
  (assert (subject:on-key-down {:key KEY_F1})
          "F1 should be handled through the state HUD provider")
  (assert (state-hud.command-hints:overlay-open?)
          "state-owned HUD should receive the overlay toggle")
  (assert (not (app-hud.command-hints:overlay-open?))
          "global app.hud should stay untouched when the state targets another HUD")
  (assert (subject:on-key-down {:key (string.byte "x")})
          "handled commands should still flow through the wrapped route")
  (assert (not (state-hud.command-hints:overlay-open?))
          "handled commands should close the state-owned HUD overlay")
  (assert (not (app-hud.command-hints:overlay-open?))
          "global app.hud should remain closed after state-owned command handling")
  (state-hud:drop)
  (app-hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn question-mark-is-not-a-global-hud-toggle []
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:set-state :normal)
  (set-app-states! states)
  (local hud (build-test-hud states))
  (set app.hud hud)
  (local subject (hint-aware-state {:name :subject :routes {}}))
  (assert (not (subject:on-key-down {:key (string.byte "?")}))
          "question-mark should not be intercepted by the HUD toggle")
  (assert (not (hud.command-hints:overlay-open?))
          "question-mark should leave the overlay closed")
  (assert (subject:on-key-down {:key KEY_F1})
          "F1 should still toggle the overlay globally")
  (assert (hud.command-hints:overlay-open?)
          "F1 should open the overlay")
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn route-handled-f1-keeps-priority-over-hud-toggle []
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:set-state :normal)
  (set-app-states! states)
  (local hud (build-test-hud states))
  (set app.hud hud)
  (var handled-f1-count 0)
  (local subject
    (hint-aware-state
      {:name :subject
       :routes {:key-down (Routes.FirstHandlerWins [{:key-down (fn [_ctx payload]
                                                                 (if (= payload.key KEY_F1)
                                                                     (do
                                                                       (set handled-f1-count (+ handled-f1-count 1))
                                                                       true)
                                                                     false))}])}}))
  (assert (subject:on-key-down {:key KEY_F1})
          "state route should still handle F1")
  (assert (= handled-f1-count 1)
          "F1 should reach the route before HUD toggle handling")
  (assert (not (hud.command-hints:overlay-open?))
          "HUD overlay should stay closed when another feature handles F1")
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn focus-provider-receives-owner-and-payload []
  (local original-states app.states)
  (local original-hud app.hud)
  (local original-focus app.focus)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:set-state :normal)
  (set-app-states! states)
  (local focus-manager
    {:get-focused-node (fn [_self]
                         {:label "focus-owner"
                          :command_hints_provider (fn [self payload]
                                                    [(section :focus
                                                              "FOCUS"
                                                              [(entry "f"
                                                                      (.. self.label
                                                                          "-"
                                                                          (if payload.expanded?
                                                                              "expanded"
                                                                              "collapsed"))
                                                                      {:priority 10})])])})})
  (local hud (build-test-hud states))
  (set hud.focus-manager focus-manager)
  (set app.hud hud)
  (assert (hud.command-hints:toggle-overlay)
          "overlay should open for focus provider test")
  (hud:update)
  (local text (hud.command-hints:get-overlay-text))
  (assert (string.find text "%[f%] focus%-owner%-expanded")
          "focus providers should receive their owner and expanded payload")
  (hud:drop)
  (set app.focus original-focus)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn direct-provider-one-arg-receives-owner []
  (local original-states app.states)
  (local original-hud app.hud)
  (local original-focus app.focus)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:set-state :normal)
  (set-app-states! states)
  (local focus-manager
    {:get-focused-node (fn [_self]
                         {:label "one-arg-owner"
                          :command_hints_provider (fn [self]
                                                    [(section :focus
                                                              "FOCUS"
                                                              [(entry "o" self.label {:priority 10})])])})})
  (local hud (build-test-hud states))
  (set hud.focus-manager focus-manager)
  (set app.hud hud)
  (assert (hud.command-hints:toggle-overlay)
          "overlay should open for one-arg direct provider test")
  (hud:update)
  (local text (hud.command-hints:get-overlay-text))
  (assert (string.find text "%[o%] one%-arg%-owner")
          "direct one-arg providers should receive their owner as self")
  (hud:drop)
  (set app.focus original-focus)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn world-contrib-provider-receives-owner-and-payload []
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:set-state :normal)
  (set-app-states! states)
  (local hud (build-test-hud states))
  (local original-contrib hud.world-hud-contrib)
  (set hud.world-hud-contrib
       {:label "world-owner"
        :command_hints_provider (fn [self payload]
                                  [(section :context
                                            "CONTEXT"
                                            [(entry "w"
                                                    (.. self.label
                                                        "-"
                                                        (if payload.expanded?
                                                            "expanded"
                                                            "collapsed"))
                                                    {:priority 10})])])})
  (set app.hud hud)
  (assert (hud.command-hints:toggle-overlay)
          "overlay should open for world provider test")
  (hud:update)
  (local text (hud.command-hints:get-overlay-text))
  (assert (string.find text "%[w%] world%-owner%-expanded")
          "world contrib providers should receive owner and expanded payload")
  (hud:drop)
  (set hud.world-hud-contrib original-contrib)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn insert-state-unhandled-f1-opens-overlay []
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:set-state :normal)
  (set-app-states! states)
  (InputState.reset)
  (InputState.connect-input (make-input-stub {:text "abc"}))
  (local hud (build-test-hud states))
  (set app.hud hud)
  (local subject (InsertState))
  (states:add-state :insert subject)
  (assert (subject:on-key-down {:key KEY_F1})
          "insert state should allow unhandled F1 to use HUD toggle handling")
  (assert (hud.command-hints:overlay-open?)
          "unhandled F1 should open the HUD overlay from insert state")
  (InputState.reset)
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn text-state-unhandled-f1-opens-overlay-while-input-active []
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:set-state :normal)
  (set-app-states! states)
  (InputState.reset)
  (local hud (build-test-hud states))
  (set app.hud hud)
  (local subject (TextState))
  (states:add-state :text subject)
  (InputState.connect-input (make-input-stub {:text "abc"}))
  (states:set-state :text)
  (assert (subject:on-key-down {:key KEY_F1})
          "text state should allow unhandled F1 to use HUD toggle handling while input is active")
  (assert (hud.command-hints:overlay-open?)
          "unhandled F1 should open the HUD overlay from text state")
  (InputState.reset)
  (hud:drop)
  (states:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn text-state-prefix-keeps-overlay-open-and-updates-hints []
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:set-state :normal)
  (set-app-states! states)
  (InputState.reset)
  (local hud (build-test-hud states))
  (set app.hud hud)
  (local subject (TextState))
  (states:add-state :text subject)
  (InputState.connect-input (make-input-stub {:text "abc"}))
  (states:set-state :text)
  (assert (hud.command-hints:toggle-overlay)
          "overlay should open before prefix key test")
  (assert (subject:on-key-down {:key (string.byte "g") :mod 0})
          "text state should handle prefix key transitions")
  (assert (hud.command-hints:overlay-open?)
          "prefix key should keep the overlay open")
  (hud:update)
  (local text (hud.command-hints:get-overlay-text))
  (assert (string.find text "MODE GOTO")
          "prefix key should switch command hints into the prefix section")
  (assert (string.find text "%[g%] first%-line")
          "prefix hints should be visible while the overlay stays open")
  (InputState.reset)
  (hud:drop)
  (states:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn text-state-drop-disconnects-updated-handler []
  (local original-states app.states)
  (local original-presentation-input-controls app.presentation-input-controls)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:set-state :normal)
  (set-app-states! states)
  (InputState.reset)
  (local subject (TextState))
  (states:add-state :text subject)
  (InputState.connect-input (make-input-stub {:text "test"}))
  (states:set-state :text)
  ;; Clean up: drop states to disconnect all routes including updated
  (InputState.reset)
  (states:drop)
  (set-app-states! original-states)
  ;; Spy on app.presentation-input-controls to prove updated handler is gone
  (var spy-called 0)
  (set app.presentation-input-controls
       (fn []
         (set spy-called (+ spy-called 1))
         nil))
  ;; Emit updated — the leaked handler must NOT fire
  (pcall #(when (and app.engine app.engine.events app.engine.events.updated)
              (app.engine.events.updated:emit {:dt (/ 1 60)})))
  (set app.presentation-input-controls original-presentation-input-controls)
  (assert (= spy-called 0)
          (.. "expected no updated handler after TextState drop, but presentation-input-controls was called " (tostring spy-called) " times")))

(fn command-hints-route-fails-loudly-without-hud-host []
  (local subject
    (State {:name :subject
            :hud_provider (fn [_state]
                            nil)
            :route-wrappers [Routes.CommandHints]
            :routes {}}))
  (local (ok err)
    (pcall (fn []
             (subject:on-key-down {:key KEY_F1}))))
  (assert (not ok)
          "command hints route should fail loudly when no HUD host is available")
  (assert (and err (string.find err "requires a HUD host for command hints"))
          "command hints route should report the missing HUD host clearly"))

(fn command-hints-close-fails-loudly-without-hud-host []
  (local subject
    (State {:name :subject
            :hud_provider (fn [_state]
                            nil)
            :route-wrappers [Routes.CommandHints]
            :routes {:key-down (fn [_event-name ctx _payload]
                                 ((. ctx :mark-command-executed!))
                                 true)}}))
  (local (ok err)
    (pcall (fn []
             (subject:on-key-down {:key (string.byte "x")}))))
  (assert (not ok)
          "handled command routes should fail loudly when no HUD host is available")
  (assert (and err (string.find err "requires a HUD host for command hints"))
          "handled command routes should report the missing HUD host clearly"))

(fn terrain-paint-unhandled-key-does-not-close-overlay []
  (local original-states app.states)
  (local original-hud app.hud)
  (local original-session app.terrain-paint-session)
  (local original-previous-state app.terrain-paint-previous-state)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:add-state :terrain-paint (TerrainPaintState))
  (states:set-state :normal)
  (set-app-states! states)
  (local hud (build-test-hud states))
  (set app.hud hud)
  (local session
    {:begin (fn [_self] true)
     :active? (fn [_self] true)
     :cancel-selection (fn [_self] true)
     :on-key-down (fn [_self payload]
                    (= payload.key 27))})
  (TerrainPaintManager.begin session)
  (local active-state (states:active-state))
  (assert (hud.command-hints:toggle-overlay)
          "overlay should open in terrain paint mode")
  (assert (not (active-state:on-key-down {:key (string.byte "z")}))
          "terrain paint should leave unrelated keys unhandled")
  (assert (hud.command-hints:overlay-open?)
          "unhandled terrain-paint keys should not close the overlay")
  (assert (active-state:on-key-down {:key 27})
          "terrain paint should still handle escape")
  (assert (not (hud.command-hints:overlay-open?))
          "handled terrain-paint commands should close the overlay")
  (TerrainPaintManager.cleanup-session session)
  (set app.terrain-paint-session original-session)
  (set app.terrain-paint-previous-state original-previous-state)
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn terrain-rect-pick-unhandled-key-does-not-close-overlay []
  (local original-states app.states)
  (local original-hud app.hud)
  (local original-session app.terrain-rect-pick-session)
  (local original-previous-state app.terrain-rect-pick-previous-state)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:add-state :terrain-rect-pick (TerrainRectPickState))
  (states:set-state :normal)
  (set-app-states! states)
  (local hud (build-test-hud states))
  (set app.hud hud)
  (local session
    {:begin (fn [_self] true)
     :active? (fn [_self] true)
     :cancel-selection (fn [_self] true)
     :on-key-down (fn [_self payload]
                    (= payload.key 27))})
  (TerrainRectPickManager.begin session)
  (local active-state (states:active-state))
  (assert (hud.command-hints:toggle-overlay)
          "overlay should open in terrain rect pick mode")
  (assert (not (active-state:on-key-down {:key (string.byte "z")}))
          "terrain rect pick should leave unrelated keys unhandled")
  (assert (hud.command-hints:overlay-open?)
          "unhandled terrain rect pick keys should not close the overlay")
  (assert (active-state:on-key-down {:key 27})
          "terrain rect pick should still handle escape")
  (assert (not (hud.command-hints:overlay-open?))
          "handled terrain rect pick commands should close the overlay")
  (TerrainRectPickManager.cleanup-session session)
  (set app.terrain-rect-pick-session original-session)
  (set app.terrain-rect-pick-previous-state original-previous-state)
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn terrain-paint-unhandled-f1-opens-overlay []
  (local original-states app.states)
  (local original-hud app.hud)
  (local original-session app.terrain-paint-session)
  (local original-previous-state app.terrain-paint-previous-state)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:add-state :terrain-paint (TerrainPaintState))
  (states:set-state :normal)
  (set-app-states! states)
  (local hud (build-test-hud states))
  (set app.hud hud)
  (local session
    {:begin (fn [_self] true)
     :active? (fn [_self] true)
     :cancel-selection (fn [_self] true)
     :on-key-down (fn [_self _payload] false)})
  (TerrainPaintManager.begin session)
  (local active-state (states:active-state))
  (assert (active-state:on-key-down {:key KEY_F1})
          "terrain paint should allow unhandled F1 to use HUD toggle handling")
  (assert (hud.command-hints:overlay-open?)
          "unhandled F1 should open the HUD overlay in terrain paint mode")
  (TerrainPaintManager.cleanup-session session)
  (set app.terrain-paint-session original-session)
  (set app.terrain-paint-previous-state original-previous-state)
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn terrain-rect-pick-unhandled-f1-opens-overlay []
  (local original-states app.states)
  (local original-hud app.hud)
  (local original-session app.terrain-rect-pick-session)
  (local original-previous-state app.terrain-rect-pick-previous-state)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:add-state :terrain-rect-pick (TerrainRectPickState))
  (states:set-state :normal)
  (set-app-states! states)
  (local hud (build-test-hud states))
  (set app.hud hud)
  (local session
    {:begin (fn [_self] true)
     :active? (fn [_self] true)
     :cancel-selection (fn [_self] true)
     :on-key-down (fn [_self _payload] false)})
  (TerrainRectPickManager.begin session)
  (local active-state (states:active-state))
  (assert (active-state:on-key-down {:key KEY_F1})
          "terrain rect pick should allow unhandled F1 to use HUD toggle handling")
  (assert (hud.command-hints:overlay-open?)
          "unhandled F1 should open the HUD overlay in terrain rect pick mode")
  (TerrainRectPickManager.cleanup-session session)
  (set app.terrain-rect-pick-session original-session)
  (set app.terrain-rect-pick-previous-state original-previous-state)
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn overlay-reanchors-while-open []
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (var status-height 2)
  (fn status-builder [_ctx]
    (local layout
      (Layout {:name "dynamic-status"
               :measurer (fn [self]
                           (set self.measure (glm.vec3 8 status-height 0)))
               :layouter (fn [self]
                           (set self.size (or self.size self.measure)))}))
    {:layout layout
     :drop (fn [_self]
             (layout:drop))})
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:set-state :normal)
  (set-app-states! states)
  (local hud (build-test-hud states {:status-builder status-builder}))
  (set app.hud hud)
  (assert (hud.command-hints:toggle-overlay)
          "overlay should open before re-anchor test")
  (hud:update)
  (local overlay-wrapper hud.command-hints.overlay-element)
  (local initial-y overlay-wrapper.layout.position.y)
  (set status-height 5)
  (hud.entity.status-root.layout:mark-measure-dirty)
  (hud:update)
  (local updated-y overlay-wrapper.layout.position.y)
  (local middle-overlay-y hud.middle-overlay-root.layout.position.y)
  (assert (not (= initial-y updated-y))
          "overlay y position should follow the status strip while open")
  (assert (= updated-y middle-overlay-y)
          "overlay should stay rooted in the middle overlay layer")
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn overlay-defaults-to-hud-local-origin []
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:set-state :normal)
  (set-app-states! states)
  (local hud (build-test-hud states))
  (set app.hud hud)
  (assert (hud.command-hints:toggle-overlay)
          "overlay should open before position check")
  (hud:update)
  (local overlay-wrapper hud.command-hints.overlay-element)
  (local overlay-root hud.middle-overlay-root)
  (local status-root hud.entity.status-root)
  (assert overlay-wrapper
          "command hints should create an overlay element")
  (assert (= overlay-wrapper.layout.position.x overlay-root.layout.position.x)
          "default overlay x should start at the HUD overlay root, not world center")
  (assert (= overlay-wrapper.layout.position.y overlay-root.layout.position.y)
          "default overlay y should start at the HUD overlay root, not world center")
  (assert (< (math.abs (- overlay-root.layout.position.y
                          (+ status-root.layout.position.y status-root.layout.size.y)))
             0.001)
          (.. "command hints overlay root should sit directly above the status panel; got overlay-y "
              overlay-wrapper.layout.position.y
              " status-y "
              status-root.layout.position.y
              " status-height "
              status-root.layout.size.y))
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn width-path-preserves-f1-toggle []
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal
                    (state-with-hints :normal
                                      [(entry "space" "leader" {:priority 10})
                                       (entry "del" "delete-selection" {:priority 20})]))
  (states:set-state :normal)
  (set-app-states! states)
  (local hud (build-test-hud states {:viewport {:width 40 :height 1080}}))
  (set app.hud hud)
  (hud:update)
  (local collapsed (hud.command-hints:get-collapsed-text))
  (assert (string.find collapsed "%[f1%] more")
          "width-based collapse should keep the F1 toggle visible")
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn width-path-preserves-f1-toggle-with-status-body []
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal
                    (state-with-hints :normal
                                      [(entry "space" "leader" {:priority 10})
                                       (entry "del" "delete-selection" {:priority 20})]))
  (states:set-state :normal)
  (set-app-states! states)
  (local body-builder (fixed-widget "status-body" (glm.vec3 10 2 0)))
  (local hud
    (build-test-hud
      states
      {:viewport {:width 40 :height 1080}
       :status-builder (StatusPanel {:body-builder body-builder})}))
  (set app.hud hud)
  (hud:update)
  (local collapsed (hud.command-hints:get-collapsed-text))
  (assert (string.find collapsed "%[f1%] more")
          "status body content should still leave the F1 toggle discoverable")
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn collapsed-strip-reserves-visible-room-for-f1-toggle []
  (local sections
    [(section :mode
              "MODE"
              [(entry "space" "leader" {:priority 10})
               (entry "del" "delete-selection" {:priority 20})
               (entry "f1" "more" {:priority 999 :id :toggle})])])
  (local collapsed
    (HudCommandHints.collapsed-text sections {:max-chars 12}))
  (assert (= collapsed "[f1] more")
          "collapsed strip should preserve visible room for the F1 toggle"))

(fn overlay-right-edge-stays-left-of-right-rail []
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:set-state :normal)
  (set-app-states! states)
  (local hud
    (build-test-hud
      states
      {:right-dock-builder (fixed-widget "right-rail" (glm.vec3 5 4 0))}))
  (set app.hud hud)
  (assert (hud.command-hints:toggle-overlay)
          "overlay should open before right rail bounds check")
  (hud:update)
  (local overlay hud.command-hints.overlay-element)
  (local rail hud.entity.right-dock-root)
  (local overlay-right (+ overlay.layout.position.x overlay.layout.size.x))
  (local rail-left rail.layout.position.x)
  (assert (<= overlay-right rail-left)
          (.. "command hints overlay should not cross into the right rail; overlay-right "
              overlay-right
              " rail-left "
              rail-left))
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(fn long-command-hint-text-is-clipped-to-rail-safe-overlay []
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state
    :normal
    (state-with-hints
      :normal
      [(entry "space" "this-single-line-command-label-is-intentionally-long-enough-to-run-past-the-middle-overlay-allocation-without-layout-clipping" {:priority 10})]))
  (states:set-state :normal)
  (set-app-states! states)
  (local hud
    (build-test-hud
      states
      {:right-dock-builder (fixed-widget "right-rail" (glm.vec3 5 4 0))}))
  (set app.hud hud)
  (assert (hud.command-hints:toggle-overlay)
          "overlay should open before clipped text bounds check")
  (hud:update)
  (local overlay hud.command-hints.overlay-element)
  (local rail hud.entity.right-dock-root)
  (local clip (and overlay overlay.layout overlay.layout.clip-region))
  (local bounds (and clip clip.bounds))
  (assert bounds
          "command hints overlay should establish a layout clip region for long rendered text")
  (local clip-right (+ bounds.position.x bounds.size.x))
  (local rail-left rail.layout.position.x)
  (assert (<= clip-right rail-left)
          (.. "command hints text clip should stay left of the right rail; clip-right "
              clip-right
              " rail-left "
              rail-left))
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

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

(fn overlay-may-overlap-expanded-sidebar-panel-but-not-rail []
  (local HudExtendedSidebar (require :hud-extended-sidebar))
  (local HudExtendedSidebarView (require :hud-extended-sidebar-view))
  (local original-states app.states)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal (state-with-hints :normal [(entry "space" "leader" {:priority 10})]))
  (states:set-state :normal)
  (set-app-states! states)
  (local sidebar (HudExtendedSidebar))
  (sidebar:register-entry {:id :test
                            :icon :test_icon
                            :label "Test"
                            :build-panel (fixed-widget "right-panel" (glm.vec3 38 10 0))})
  (sidebar:select :test)
  (local hud
    (build-test-hud
      states
      {:right-dock-builder (HudExtendedSidebarView sidebar)
       :icons (make-icons-stub)}))
  (set app.hud hud)
  (assert (hud.command-hints:toggle-overlay)
          "overlay should open before expanded right sidebar bounds check")
  (hud:update)
  (local overlay hud.command-hints.overlay-element)
  (local right-dock hud.entity.right-dock-root)
  (local panel-layout (. right-dock.layout.children 1))
  (local rail-layout (. right-dock.layout.children 2))
  (local overlay-right (+ overlay.layout.position.x overlay.layout.size.x))
  (local panel-left panel-layout.position.x)
  (local rail-left rail-layout.position.x)
  (assert (> overlay-right panel-left)
          (.. "command hints overlay may overlap the expanded right sidebar flyout panel; overlay-right "
              overlay-right
              " panel-left "
              panel-left))
  (assert (<= overlay-right rail-left)
          (.. "command hints overlay should not cross into the right rail when sidebar is expanded; overlay-right "
              overlay-right
              " rail-left "
              rail-left))
  (hud:drop)
  (set app.hud original-hud)
  (set-app-states! original-states))

(table.insert tests {:name "HUD command strip follows active state"
                     :fn hud-command-strip-follows-active-state})
(table.insert tests {:name "Status panel update populates width-based collapsed field"
                     :fn status-panel-update-populates-width-based-collapsed-field})
(table.insert tests {:name "HUD command overlay live updates"
                     :fn hud-command-overlay-live-updates})
(table.insert tests {:name "Declarative state command hints provider works"
                     :fn declarative-state-command-hints-provider-works})
(table.insert tests {:name "HUD command hints use HUD states over globals"
                     :fn hud-command-hints-use-hud-states-over-globals})
(table.insert tests {:name "HUD command hints use HUD focus manager over globals"
                     :fn hud-command-hints-use-hud-focus-manager-over-globals})
(table.insert tests {:name "Shared F1 toggle opens and closes HUD overlay"
                     :fn f1-toggle-opens-and-command-closes-overlay})
(table.insert tests {:name "Handled but unmarked keys do not close HUD overlay"
                     :fn handled-but-unmarked-key-does-not-close-overlay})
(table.insert tests {:name "Route command hints use state HUD provider over app.hud"
                     :fn route-command-hints-use-state-hud-provider-over-app-hud})
(table.insert tests {:name "Question mark is not a global HUD toggle"
                     :fn question-mark-is-not-a-global-hud-toggle})
(table.insert tests {:name "Handled F1 routes keep priority over HUD toggle"
                     :fn route-handled-f1-keeps-priority-over-hud-toggle})
(table.insert tests {:name "Focus providers receive owner and payload"
                     :fn focus-provider-receives-owner-and-payload})
(table.insert tests {:name "Direct one-arg providers receive owner"
                     :fn direct-provider-one-arg-receives-owner})
(table.insert tests {:name "World contrib providers receive owner and payload"
                     :fn world-contrib-provider-receives-owner-and-payload})
(table.insert tests {:name "Insert state unhandled F1 opens HUD overlay"
                     :fn insert-state-unhandled-f1-opens-overlay})
(table.insert tests {:name "Text state unhandled F1 opens HUD overlay while input is active"
                     :fn text-state-unhandled-f1-opens-overlay-while-input-active})
(table.insert tests {:name "Text state prefix keeps overlay open and updates hints"
                      :fn text-state-prefix-keeps-overlay-open-and-updates-hints})
(table.insert tests {:name "Text state drop disconnects updated handler"
                      :fn text-state-drop-disconnects-updated-handler})
(table.insert tests {:name "Command hints route fails loudly without HUD host"
                     :fn command-hints-route-fails-loudly-without-hud-host})
(table.insert tests {:name "Command hints close fails loudly without HUD host"
                     :fn command-hints-close-fails-loudly-without-hud-host})
(table.insert tests {:name "Terrain paint unhandled key does not close overlay"
                     :fn terrain-paint-unhandled-key-does-not-close-overlay})
(table.insert tests {:name "Terrain rect pick unhandled key does not close overlay"
                     :fn terrain-rect-pick-unhandled-key-does-not-close-overlay})
(table.insert tests {:name "Terrain paint unhandled F1 opens HUD overlay"
                     :fn terrain-paint-unhandled-f1-opens-overlay})
(table.insert tests {:name "Terrain rect pick unhandled F1 opens HUD overlay"
                     :fn terrain-rect-pick-unhandled-f1-opens-overlay})
(table.insert tests {:name "Overlay reanchors while open"
                     :fn overlay-reanchors-while-open})
(table.insert tests {:name "Overlay defaults to HUD local origin"
                     :fn overlay-defaults-to-hud-local-origin})
(table.insert tests {:name "Width path preserves the F1 toggle"
                     :fn width-path-preserves-f1-toggle})
(table.insert tests {:name "Width path preserves the F1 toggle with status body"
                     :fn width-path-preserves-f1-toggle-with-status-body})
(table.insert tests {:name "Collapsed strip preserves room for the F1 toggle"
                      :fn collapsed-strip-reserves-visible-room-for-f1-toggle})
(table.insert tests {:name "Overlay right edge stays left of right rail"
                      :fn overlay-right-edge-stays-left-of-right-rail})
(table.insert tests {:name "Long command hint text is clipped to rail-safe overlay"
                     :fn long-command-hint-text-is-clipped-to-rail-safe-overlay})
(table.insert tests {:name "Overlay may overlap expanded sidebar panel but not rail"
                      :fn overlay-may-overlap-expanded-sidebar-panel-but-not-rail})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "hud-command-hints"
                       :tests tests})))

{:name "hud-command-hints"
 :tests tests
 :main main}
