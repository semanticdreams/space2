(local _ (require :main))
(local glm (require :glm))
(local States (require :states))
(local NormalState (require :normal-state))
(local LeaderState (require :leader-state))
(local QuitState (require :quit-state))
(local TextState (require :text-state))
(local InsertState (require :insert-state))
(local CameraState (require :camera-state))
(local Camera (require :camera))
(local FpcState (require :fpc-state))
(local TerrainRectPickState (require :terrain-rect-pick-state))
(local TerrainRectPickManager (require :graph/view/terrain-rect-pick-manager))
(local TerrainPaintState (require :terrain-paint-state))
(local TerrainPaintManager (require :graph/view/terrain-paint-manager))
(local InputState (require :input-state-router))
(local State (require :state))
(local Runtime (require :state-runtime))
(local BuildContext (require :build-context))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local GraphView (require :graph/view))
(local Intersectables (require :intersectables))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))
(local {:FocusManager FocusManager} (require :focus))
(local HoverHandlers (require :state-handlers/hover))
(local TextInputHandlers (require :state-handlers/text-input))
(local FocusHandlers (require :state-handlers/focus))
(local PointerHandlers (require :state-handlers/pointer))
(local GamepadHandlers (require :state-handlers/gamepad))
(local CameraHandlers (require :state-handlers/camera))
(local Routes (require :state-routes))
(local InputModel (require :input-model))
(local StateSystemBindings (require :state-system-bindings))
(local TestSupport (require :tests/test-support))

(fn make-test-graph-map []
  (local graph (Graph {:with-start false}))
  (local original-has-key-loader graph.has-key-loader-for-key)
  (set graph.has-key-loader-for-key
       (fn [self key]
         (if (and original-has-key-loader (original-has-key-loader self key))
             true
             (if key true false))))
  (GraphMap.GraphMap {:graph graph :id "states-graph-focus"}))

(fn drop-test-graph-map! [graph-map]
  (local graph graph-map.graph)
  (graph-map:drop)
  (graph:drop))
(local viewport-utils (require :viewport-utils))

(local tests [])

(local SHIFT-MOD 1)
(local KEY_ESCAPE 27)
(local KEY_SPACE (string.byte " "))
(local KEY_BACKQUOTE (string.byte "`"))
(local KEY_DELETE 127)
(local KEY_RETURN 13)
(local KEY_C (string.byte "c"))
(local KEY_F (string.byte "f"))
(local KEY_H (string.byte "h"))
(local KEY_J (string.byte "j"))
(local KEY_K (string.byte "k"))
(local KEY_L (string.byte "l"))
(local KEY_F4 1073741885)
(local KEY_Q (string.byte "q"))
(local KEY_P (string.byte "p"))
(local KEY_LEFT 1073741904)
(local KEY_RIGHT 1073741903)
(local KEY_DOWN 1073741905)
(local KEY_UP 1073741906)

(fn make-command-hints-stub []
  {:handle-toggle-key (fn [_self _payload] true)
   :close-on-handled-event (fn [_self _route-key _payload] false)})

(fn make-command-hints-hud-stub []
  {:command-hints (make-command-hints-stub)})

(fn command-hints-hud-provider [_self]
  (make-command-hints-hud-stub))

(fn ensure-command-hints-hud! [states]
  (when (and states states.get-hud states.set-hud-provider (not (states:get-hud)))
    (states:set-hud-provider command-hints-hud-provider))
  states)

(fn set-app-states! [states]
  (ensure-command-hints-hud! states)
  (StateSystemBindings.bind-states-host states)
  (set app.states states)
  states)

(fn snapshot-app-fields [keys]
  (local snapshot {:keys keys
                   :values {}})
  (each [_ key (ipairs keys)]
    (set (. snapshot.values key) (. app key)))
  snapshot)

(fn restore-app-fields! [snapshot]
  (each [_ key (ipairs snapshot.keys)]
    (if (= key :states)
        (set-app-states! (. snapshot.values key))
        (set (. app key) (. snapshot.values key))))
  true)

(fn with-restored-app-fields [keys f]
  (local snapshot (snapshot-app-fields keys))
  (local (ok result) (pcall f))
  (restore-app-fields! snapshot)
  (if ok
      result
      (error result)))

(fn own-test-state! [name state]
  (local states
    (States {:hud_provider command-hints-hud-provider
             :focus_manager_provider (fn [_self]
                                       app.focus)}))
  (states:add-state name state)
  states)

(fn fresh-engine-events []
  (local Signal (require :signal))
  {:pen-proximity-in (Signal)
   :pen-proximity-out (Signal)
   :pen-motion (Signal)
   :pen-down (Signal)
   :pen-up (Signal)
   :pen-button-down (Signal)
   :pen-button-up (Signal)
   :pen-axis (Signal)
   :touch-down (Signal)
   :touch-motion (Signal)
   :touch-up (Signal)
   :touch-canceled (Signal)
   :text-input (Signal)
   :text-editing (Signal)
   :key-down (Signal)
   :key-up (Signal)
   :mouse-button-down (Signal)
   :mouse-button-up (Signal)
   :mouse-motion (Signal)
   :mouse-wheel (Signal)
   :gamepad-button-down (Signal)
   :gamepad-axis-motion (Signal)
   :gamepad-removed (Signal)
   :updated (Signal)})

(fn fresh-engine-events-with-connect-log [log]
  (local events (fresh-engine-events))
  (each [name signal (pairs events)]
    (local original-connect signal.connect)
    (set signal.connect
         (fn [first handler]
           (table.insert log name)
           (original-connect first handler))))
  events)

(fn transitions-call-enter-and-leave []
  (local states (States))
  (local log [])
  (fn push [label]
    (table.insert log label))
  (states:add-state :alpha {:on-enter (fn [] (push :alpha-enter))
                            :on-leave (fn [] (push :alpha-leave))})
  (states:add-state :beta {:on-enter (fn [] (push :beta-enter))
                           :on-leave (fn [] (push :beta-leave))})
  (states:set-state :alpha)
  (states:set-state :beta)
  (assert (= (# log) 3))
  (assert (= (. log 1) :alpha-enter))
  (assert (= (. log 2) :alpha-leave))
  (assert (= (. log 3) :beta-enter)))

(fn reselecting-active-state-noops []
  (local states (States))
  (var enters 0)
  (states:add-state :solo {:on-enter (fn [] (set enters (+ enters 1)))})
  (states:set-state :solo)
  (states:set-state :solo)
  (assert (= enters 1)))

(fn state-history-tracks-transitions []
  (local states (States {:history-limit 2}))
  (states:add-state :alpha {})
  (states:add-state :beta {})
  (states:add-state :gamma {})
  (states:set-state :alpha)
  (states:set-state :beta)
  (states:set-state :gamma)
  (local history (states:get-history))
  (local first (. history 1))
  (local second (. history 2))
  (assert (= (# history) 2))
  (assert (= first.previous :alpha))
  (assert (= first.current :beta))
  (assert (= second.previous :beta))
  (assert (= second.current :gamma))
  (states:clear-history)
  (assert (= (# (states:get-history)) 0)))

(fn remove-state-unregisters-inactive-state []
  (local states (States))
  (local state {})
  (states:add-state :temporary state)
  (assert (= (states:get-state :temporary) state))
  (assert (= state.states_owner states))
  (local removed (states:remove-state :temporary))
  (assert (= removed state))
  (assert (= (states:get-state :temporary) nil))
  (assert (= state.states_owner nil)))

(fn remove-state-leaves-active-state []
  (local states (States))
  (var left 0)
  (states:add-state :normal {})
  (states:add-state :temporary {:on-leave (fn [] (set left (+ left 1)))})
  (states:set-state :temporary)
  (states:remove-state :temporary {:fallback :normal})
  (assert (= left 1))
  (assert (= (states:active-name) :normal))
  (assert (= (states:get-state :temporary) nil)))

(fn remove-active-state-requires-fallback []
  (local states (States))
  (states:add-state :temporary {})
  (states:set-state :temporary)
  (local (ok err) (pcall #(states:remove-state :temporary)))
  (assert (not ok) "removing active state without fallback should fail")
  (assert (string.find (tostring err) "without :fallback" 1 true)
          "error should explain missing fallback"))

(fn add-state-replacing-owner-clears-previous-owner []
  (local states (States))
  (local old-state {:name :temporary})
  (states:add-state :temporary old-state)
  (assert (= old-state.states_owner states)
          "old state should be bound to host")
  (local new-state {:name :temporary})
  (states:add-state :temporary new-state)
  (assert (= old-state.states_owner nil)
          "previous state owner should be cleared after replacement")
  (assert (= new-state.states_owner states)
          "new state should be bound to host"))

(fn add-state-rejects-active-replacement []
  (local states (States))
  (states:add-state :normal {:name :normal})
  (states:set-state :normal)
  (local (ok err) (pcall #(states:add-state :normal {:name :normal})))
  (assert (not ok) "add-state should reject replacing active state")
  (assert (string.find (tostring err) "add-state" 1 true)
          "error should mention add-state restriction"))

(fn add-state-rejection-does-not-bind-rejected-state []
  (local states (States))
  (states:add-state :normal {:name :normal})
  (states:set-state :normal)
  (local rejected {:name :normal})
  (local (ok err) (pcall #(states:add-state :normal rejected)))
  (assert (not ok) "add-state should reject replacing active state")
  (assert (= rejected.states_owner nil)
          "rejected state should not be bound to the states host"))

(fn add-state-rejects-same-object-alias []
  (local states (States))
  (local shared {:name :shared})
  (states:add-state :alpha shared)
  (local (ok err) (pcall #(states:add-state :beta shared)))
  (assert (not ok) "add-state should reject same state object under different names")
  (assert (string.find (tostring err) "multiple names" 1 true)
          "error should explain multiple-name rejection"))

(fn add-state-re-registering-same-object-is-idempotent []
  (local states (States))
  (local obj {:name :idem})
  (states:add-state :idem obj)
  (assert (= obj.states_owner states))
  (states:add-state :idem obj)
  (assert (= obj.states_owner states)
          "owner should remain set after idempotent add-state"))

(fn add-state-idempotent-when-active []
  (local states (States))
  (local obj {:name :idem})
  (states:add-state :idem obj)
  (states:set-state :idem)
  (assert (= (states:active-name) :idem))
  (states:add-state :idem obj)
  (assert (= obj.states_owner states)
          "owner should remain set after idempotent add-state on active state")
  (assert (= (states:active-name) :idem)
          "active name should be unchanged after idempotent add-state"))

(fn create-controls-stub []
  (local record
    {:key_down nil
     :key_up nil
     :mouse_wheel nil
     :mouse_motion nil
     :mouse_button_down nil
     :mouse_button_up nil
     :gamepad_button nil
     :gamepad_axis nil
     :gamepad_removed false
     :updated nil})
  (local controls
    {:record record
     :on-key-down (fn [self payload] (set record.key_down payload.key))
     :on-key-up (fn [self payload] (set record.key_up payload.key))
     :on-mouse-wheel (fn [self payload] (set record.mouse_wheel payload.y))
     :on-mouse-motion (fn [self payload] (set record.mouse_motion {:x payload.x :y payload.y}))
     :on-mouse-button-down (fn [self payload] (set record.mouse_button_down payload.button))
     :on-mouse-button-up (fn [self payload] (set record.mouse_button_up payload.button))
     :on-gamepad-button-down (fn [self payload] (set record.gamepad_button payload.button))
     :on-gamepad-axis-motion (fn [self payload] (set record.gamepad_axis payload.value))
     :on-gamepad-removed (fn [self payload] (set record.gamepad_removed payload.which))
     :drag-active? (fn [_self] false)
     :update (fn [self delta] (set record.updated delta))})
  controls)

(fn make-hoverables-stub []
  (local record {:enter 0 :leave 0 :motions []})
  (local stub {:record record})
  (set stub.on-enter (fn []
                       (set record.enter (+ record.enter 1))))
  (set stub.on-leave (fn []
                       (set record.leave (+ record.leave 1))))
  (set stub.on-mouse-motion (fn [_self payload]
                              (table.insert record.motions payload)))
  stub)

(fn recorded-motion? [record x y]
  (var found false)
  (each [_ payload (ipairs record.motions)]
    (when (and (= payload.x x) (= payload.y y))
      (set found true)))
  found)

(fn engine-touch-payload [touch-id finger-id x y xrel yrel pressure timestamp]
  (local payload {:x x
                  :y y
                  :xrel xrel
                  :yrel yrel
                  :pressure pressure
                  :timestamp timestamp})
  (tset payload "touch-id" touch-id)
  (tset payload "finger-id" finger-id)
  payload)

(fn create-clickables-stub []
  (local record {:mouse-button-down 0
                 :mouse-button-up 0
                 :last-down nil
                 :last-up nil})
  {:record record
   :on-mouse-button-down (fn [_self payload]
                           (set record.mouse-button-down (+ record.mouse-button-down 1))
                           (set record.last-down payload))
   :on-mouse-button-up (fn [_self payload]
                         (set record.mouse-button-up (+ record.mouse-button-up 1))
                         (set record.last-up payload))
   :active? false})

(fn create-touch-transform-controls-stub []
  (local record {:start nil
                 :motion nil
                 :ended nil})
  {:record record
   :on-touch-transform-start (fn [_self gesture]
                               (set record.start gesture)
                               true)
   :on-touch-transform (fn [_self gesture]
                         (set record.motion gesture)
                         true)
   :on-touch-transform-end (fn [_self payload]
                             (set record.ended payload)
                             true)
   :drag-active? (fn [_self] false)
   :update (fn [_self _delta] nil)})

(fn reset-engine-events []
  (Runtime.reset)
  (local events (and app.engine app.engine.events))
  (when events
    (each [_ signal (ipairs [events.pen-proximity-in
                             events.pen-proximity-out
                             events.pen-motion
                             events.pen-down
                             events.pen-up
                             events.pen-button-down
                             events.pen-button-up
                             events.pen-axis
                             events.touch-down
                             events.touch-motion
                             events.touch-up
                             events.touch-canceled
                             events.text-input
                             events.text-editing
                             events.key-down
                             events.key-up
                             events.mouse-button-down
                             events.mouse-button-up
                             events.mouse-motion
                             events.mouse-wheel
                             events.gamepad-button-down
                             events.gamepad-axis-motion
                             events.gamepad-removed
                             events.updated])]
      (when (and signal signal.clear)
        (signal:clear)))))

(fn interactive-routes [overrides]
  (local route-overrides (or overrides {}))
  {:text-input (or route-overrides.text-input
                   (Routes.FirstHandlerWins [TextInputHandlers.TextInputDispatch]))
   :text-editing (or route-overrides.text-editing
                     (Routes.FirstHandlerWins [TextInputHandlers.TextEditingDispatch]))
   :key-down (or route-overrides.key-down
                 (Routes.FirstHandlerWins [FocusHandlers.InputKeyDownDispatch
                                          FocusHandlers.FocusTabKeyDown
                                          FocusHandlers.FocusDirectionKeyDown
                                          FocusHandlers.ActiveInputKeyBlock]))
   :key-up (or route-overrides.key-up
               (Routes.FirstHandlerWins [FocusHandlers.InputKeyUpDispatch
                                        FocusHandlers.ActiveInputKeyBlock]))
   :mouse-button-down (or route-overrides.mouse-button-down
                          (Routes.Chain [PointerHandlers.InputMouseButtonDownDispatch
                                         PointerHandlers.ResizableMouseButtonDown
                                         PointerHandlers.ClickableMouseButtonDown
                                         PointerHandlers.MovableMouseButtonDown
                                         PointerHandlers.SelectionMouseButtonDown
                                         PointerHandlers.CameraMouseButtonDown]))
   :mouse-button-up (or route-overrides.mouse-button-up
                        (Routes.Chain [PointerHandlers.InputMouseButtonUpDispatch
                                       PointerHandlers.ResizableMouseButtonUp
                                       PointerHandlers.ClickableMouseButtonUp
                                       PointerHandlers.MovableMouseButtonUp
                                       PointerHandlers.SelectionMouseButtonUp
                                       PointerHandlers.CameraMouseButtonUp
                                       HoverHandlers.HoverAfterMouseButtonUp]))
   :mouse-motion (or route-overrides.mouse-motion
                     (Routes.Chain [PointerHandlers.InputMouseMotionDispatch
                                    PointerHandlers.MovableMouseMotion
                                    PointerHandlers.ResizableMouseMotion
                                    PointerHandlers.CameraDragMouseMotion
                                    PointerHandlers.SelectionMouseMotion
                                    PointerHandlers.CameraMouseMotion
                                    HoverHandlers.HoverMouseMotion]))
   :mouse-wheel (or route-overrides.mouse-wheel
                    (Routes.FirstHandlerWins [PointerHandlers.InputMouseWheelDispatch
                                             PointerHandlers.HoveredMouseWheel
                                             PointerHandlers.CameraMouseWheel]))
   :gamepad-button-down (or route-overrides.gamepad-button-down
                            (Routes.FirstHandlerWins [GamepadHandlers.GamepadButtonDown]))
   :gamepad-axis-motion (or route-overrides.gamepad-axis-motion
                            (Routes.FirstHandlerWins [GamepadHandlers.GamepadAxisMotion]))
   :gamepad-removed (or route-overrides.gamepad-removed
                        (Routes.FirstHandlerWins [GamepadHandlers.GamepadRemoved]))
   :updated (or route-overrides.updated
                (Routes.Chain [CameraHandlers.CameraUpdated
                               HoverHandlers.HoverUpdated]))})

(fn normal-state-forwards-events []
  (reset-engine-events)
  (local controls (create-controls-stub))
  (local original-presentation-controls app.presentation-input-controls)
  (set app.first-person-controls controls)
  (set app.presentation-input-controls (fn [] controls))
  (local original-hoverables app.hoverables)
  (local hoverables (make-hoverables-stub))
  (set app.hoverables hoverables)
  (assert app.hoverables.on-mouse-motion "test hoverables stub missing on-mouse-motion")
  (local state (NormalState))
  (own-test-state! :normal state)
  (state.on-enter)
  (app.engine.events.key-down.emit {:key 44})
  (app.engine.events.key-up.emit {:key 45})
  (app.engine.events.mouse-wheel.emit {:x 0 :y 2})
  (app.engine.events.mouse-motion.emit {:x 10 :y 20})
  (app.engine.events.mouse-button-down.emit {:button 1 :x 0 :y 0})
  (app.engine.events.mouse-button-up.emit {:button 1 :x 0 :y 0})
  (app.engine.events.gamepad-button-down.emit {:button 5 :which 1})
  (app.engine.events.gamepad-axis-motion.emit {:axis 0 :value 0.5 :which 1})
  (app.engine.events.gamepad-removed.emit {:which 1})
  (app.engine.events.updated.emit 0.25)
  (assert (= controls.record.key_down nil))
  (assert (= controls.record.key_up nil))
  (assert (= controls.record.mouse_wheel 2))
  (assert (= controls.record.mouse_motion.x 10))
  (assert (= controls.record.mouse_button_down 1))
  (assert (= controls.record.mouse_button_up 1))
  (assert (= controls.record.gamepad_button 5))
  (assert (= controls.record.gamepad_axis 0.5))
  (assert (= controls.record.gamepad_removed 1))
  (assert (= controls.record.updated 0.25))

  (assert (= hoverables.record.enter 1) "hoverables should receive on-enter")
  (assert (recorded-motion? hoverables.record 10 20) "hoverables should see mouse motion payloads")
  (state.on-leave)
  (assert (= hoverables.record.leave 1) "hoverables should receive on-leave")
  (app.engine.events.key-down.emit {:key 99})
  (assert (= controls.record.key_down nil))
  (set app.first-person-controls nil)
  (set app.presentation-input-controls original-presentation-controls)
  (set app.hoverables original-hoverables))

(fn normal-state-injects-single-touch-as-mouse []
  (reset-engine-events)
  (local controls (create-controls-stub))
  (local original-active-controls app.active-pointer-controls)
  (local original-hoverables (assert app.hoverables "test requires app.hoverables"))
  (local original-clickables (assert app.clickables "test requires app.clickables"))
  (local original-movables app.movables)
  (local original-resizables app.resizables)
  (local original-touch-targets app.touch-gesture-targets)
  (local original-presentation-controls app.presentation-input-controls)
  (local clickables (create-clickables-stub))
  (set app.active-pointer-controls nil)
  (set app.hoverables {:on-enter (fn [])
                        :on-leave (fn [])
                        :on-mouse-motion (fn [_self _payload])})
  (set app.clickables clickables)
  (set app.movables {:drag-active? (fn [_self] false)
                      :on-mouse-motion (fn [_self _payload])
                      :on-mouse-button-down (fn [_self _payload])
                     :on-mouse-button-up (fn [_self _payload])})
  (set app.resizables {:drag-active? (fn [_self] false)
                       :on-mouse-motion (fn [_self _payload])
                       :on-mouse-button-down (fn [_self _payload])
                       :on-mouse-button-up (fn [_self _payload])})
  (set app.touch-gesture-targets {:select-object (fn [_self _payload _opts] nil)})
  (set app.first-person-controls controls)
  (set app.presentation-input-controls (fn [] controls))
  (local (ok err) (pcall (fn []
    (local state (NormalState))
    (own-test-state! :normal state)
    (state.on-enter)
    (state:on-touch-down (engine-touch-payload 1 11 10 20 0 0 0.5 1))
    (state:on-touch-motion (engine-touch-payload 1 11 18 24 8 4 0.5 2))
    (app.engine.input:on-touch-up 1 11 0.2 0.3 0 0 0.5 3)
    (state:on-touch-up (engine-touch-payload 1 11 22 28 4 4 0.5 3))
    (assert (= controls.record.mouse_button_down 1))
    (assert controls.record.mouse_motion)
    (assert (= controls.record.mouse_button_up 1))
    (assert (= clickables.record.mouse-button-down 1)
            "single-touch should press clickables through synthetic mouse events")
    (assert (= clickables.record.mouse-button-up 1)
            "single-touch should release clickables through synthetic mouse events")
    (assert (= (rawget clickables.record.last-down "touch-id") 1)
            "synthetic button-down payload should preserve the touch device id")
    (assert (= (rawget clickables.record.last-up "finger-id") 11)
            "synthetic button-up payload should preserve the finger id")
    (state:on-leave))))
  (set app.active-pointer-controls original-active-controls)
  (set app.hoverables original-hoverables)
  (set app.clickables original-clickables)
  (set app.movables original-movables)
  (set app.resizables original-resizables)
  (set app.first-person-controls nil)
  (set app.presentation-input-controls original-presentation-controls)
  (set app.touch-gesture-targets original-touch-targets)
  (when (not ok) (error err)))

(fn normal-state-routes-canvas-multitouch-to-active-controls []
  (reset-engine-events)
  (local controls (create-touch-transform-controls-stub))
  (local original-active-controls app.active-pointer-controls)
  (local original-hoverables (assert app.hoverables "test requires app.hoverables"))
  (local original-clickables (assert app.clickables "test requires app.clickables"))
  (local original-movables app.movables)
  (local original-resizables app.resizables)
  (local original-touch-targets app.touch-gesture-targets)
  (local original-canvas-interactive app.canvas-interactive?)
  (local original-mode app.active-activity-id)
  (set app.active-pointer-controls controls)
  (set app.hoverables {:on-enter (fn [])
                        :on-leave (fn [])
                        :on-mouse-motion (fn [_self _payload])})
  (local clickables (create-clickables-stub))
  (set app.clickables clickables)
  (set app.movables {:drag-active? (fn [_self] false)
                      :on-mouse-motion (fn [_self _payload])
                      :on-mouse-button-down (fn [_self _payload])
                     :on-mouse-button-up (fn [_self _payload])})
  (set app.resizables {:drag-active? (fn [_self] false)
                       :on-mouse-motion (fn [_self _payload])
                       :on-mouse-button-down (fn [_self _payload])
                       :on-mouse-button-up (fn [_self _payload])})
  (set app.touch-gesture-targets {:select-object (fn [_self _payload _opts] nil)})
  (set app.canvas-interactive? true)
  (set app.active-activity-id "graph")
  (local state (NormalState))
  (own-test-state! :normal state)
  (state.on-enter)
  (state:on-touch-down (engine-touch-payload 7 301 20 30 0 0 0.5 1))
  (assert (= controls.record.start nil)
          "single touch should not start a transform gesture")
  (state:on-touch-down (engine-touch-payload 7 302 40 30 0 0 0.6 2))
  (assert (= clickables.record.mouse-button-up 1)
          "multitouch promotion should release the synthetic single-touch mouse stream")
  (assert (= (and clickables.record.last-up clickables.record.last-up.suppress-click?) true)
          "multitouch promotion should suppress click dispatch on the synthetic release")
  (assert controls.record.start
          "second touch in drawing activity should start a multitouch transform")
  (assert (= controls.record.start.count 2)
          "canvas multitouch transform should include both contacts")
  (assert (= (rawget (. controls.record.start.contacts 1) "touch-id") 7)
          "multitouch gesture should preserve touch device ids")
  (state:on-touch-motion (engine-touch-payload 7 302 48 34 8 4 0.6 3))
  (assert controls.record.motion
          "active canvas multitouch gesture should forward motion to controls")
  (assert (= controls.record.motion.count 2)
          "canvas multitouch motion should still report two active contacts")
  (state:on-touch-up (engine-touch-payload 7 302 48 34 0 0 0.6 4))
  (assert controls.record.ended
          "ending a canvas multitouch gesture should notify controls")
  (assert (= (and controls.record.ended.gesture controls.record.ended.gesture.count) 1)
          "gesture end payload should report the remaining active contact count")
  (state:on-touch-up (engine-touch-payload 7 301 20 30 0 0 0.5 5))
  (state:on-leave)
  (set app.active-pointer-controls original-active-controls)
  (set app.hoverables original-hoverables)
  (set app.clickables original-clickables)
  (set app.movables original-movables)
  (set app.resizables original-resizables)
  (set app.touch-gesture-targets original-touch-targets)
  (set app.canvas-interactive? original-canvas-interactive)
  (set app.active-activity-id original-mode))

(fn normal-state-forwards-control-click-suppression-to-clickables []
  (reset-engine-events)
  (local original-hoverables (assert app.hoverables "test requires app.hoverables"))
  (local original-clickables (assert app.clickables "test requires app.clickables"))
  (local original-movables app.movables)
  (local original-resizables app.resizables)
  (local original-controls app.first-person-controls)
  (local original-presentation-controls app.presentation-input-controls)
  (set app.hoverables {:on-enter (fn [])
                        :on-leave (fn [])
                        :on-mouse-motion (fn [_self _payload])})
  (local clickables (create-clickables-stub))
  (set app.clickables clickables)
  (set app.movables {:drag-active? (fn [_self] false)
                      :on-mouse-motion (fn [_self _payload])
                      :on-mouse-button-down (fn [_self _payload])
                     :on-mouse-button-up (fn [_self _payload])})
  (set app.resizables {:drag-active? (fn [_self] false)
                       :on-mouse-motion (fn [_self _payload])
                       :on-mouse-button-down (fn [_self _payload])
                       :on-mouse-button-up (fn [_self _payload])})
  (local controls
    {:on-mouse-button-down (fn [_self _payload] nil)
     :on-mouse-button-up (fn [_self _payload] nil)
     :on-mouse-motion (fn [_self _payload] nil)
     :drag-active? (fn [_self] false)
     :should-suppress-click? (fn [_self payload]
                               (= payload.button 3))})
  (set app.first-person-controls controls)
  (set app.presentation-input-controls (fn [] controls))
  (local (ok err) (pcall (fn []
    (local state (NormalState))
    (own-test-state! :normal state)
    (state:on-mouse-button-up {:button 3 :x 12 :y 14})
    (assert (= clickables.record.mouse-button-up 1)
            "normal state should still forward releases to clickables")
    (assert (= (and clickables.record.last-up clickables.record.last-up.suppress-click?) true)
            "normal state should propagate pointer-control click suppression to clickables"))))
  (set app.hoverables original-hoverables)
  (set app.clickables original-clickables)
  (set app.movables original-movables)
  (set app.resizables original-resizables)
  (set app.first-person-controls original-controls)
  (set app.presentation-input-controls original-presentation-controls)
  (when (not ok) (error err)))

(fn normal-state-touch-focuses-graph-node-under-logical-input-scaling []
  (reset-engine-events)
  (local original-active-controls app.active-pointer-controls)
  (local original-hoverables (assert app.hoverables "test requires app.hoverables"))
  (local original-clickables (assert app.clickables "test requires app.clickables"))
  (local original-movables app.movables)
  (local original-resizables app.resizables)
  (local original-touch-targets app.touch-gesture-targets)
  (local original-intersectables app.intersectables)
  (local original-first-person app.first-person-controls)
  (local original-object-selector app.object-selector)
  (local original-engine-width (and app.engine app.engine.width))
  (local original-engine-height (and app.engine app.engine.height))
  (local original-viewport app.viewport)
  (var view nil)
  (var graph nil)
  (local (ok err)
    (pcall
      (fn []
        (set app.active-pointer-controls nil)
        (set app.engine.width 100)
        (set app.engine.height 50)
        (set app.viewport {:x 0 :y 0 :width 200 :height 100})
        (set app.intersectables (Intersectables))
        (set app.clickables (Clickables {:intersectables app.intersectables}))
        (set app.hoverables (Hoverables {:intersectables app.intersectables}))
        (set app.movables {:drag-active? (fn [_self] false)
                           :on-mouse-motion (fn [_self _payload])
                           :on-mouse-button-down (fn [_self _payload])
                           :on-mouse-button-up (fn [_self _payload])})
        (set app.resizables {:drag-active? (fn [_self] false)
                             :on-mouse-motion (fn [_self _payload])
                             :on-mouse-button-down (fn [_self _payload])
                             :on-mouse-button-up (fn [_self _payload])})
        (set app.touch-gesture-targets {:select-object (fn [_self _payload _opts] nil)})
        (set app.object-selector nil)
        (set app.first-person-controls (create-controls-stub))
        (local focus-manager (FocusManager {:root-name "test-states-graph-focus"}))
        (local focus-scope (focus-manager:create-scope {:name "test-states-graph-view"}))
        (local ctx
          (BuildContext {:clickables app.clickables
                         :hoverables app.hoverables
                         :theme {:graph {:selection-border-color (glm.vec4 1 0.6 0.2 1)}
                                 :input {:focus-outline (glm.vec4 0.2 0.6 1 1)}}
                         :focus-manager focus-manager
                         :focus-scope focus-scope}))
        (local pointer-target
          {:screen-pos-ray (fn [_self pointer _opts]
                             (local viewport (viewport-utils.to-table app.viewport))
                             (local screen (viewport-utils.input-pos->viewport-pos pointer viewport app.engine))
                             {:origin (glm.vec3 (or (and screen screen.x) 0)
                                                (or (and screen screen.y) 0)
                                                10)
                              :direction (glm.vec3 0 0 -1)})})
        (set graph (make-test-graph-map))
        (set view (GraphView {:graph-map graph
                              :ctx ctx
                              :pointer-target pointer-target}))
        (local node (Graph.GraphNode {:key "touch-focus-node"
                                      :size 8}))
        (graph:add-node node {:position (glm.vec3 40 50 0)
                              :run-force? false})
        (local focus-node (. view.focus-nodes node))
        (assert focus-node "GraphView should create a focus node for the touch target")
        (local state (NormalState))
        (own-test-state! :normal state)
        (state.on-enter)
        (state:on-touch-down (engine-touch-payload 1 11 20 25 0 0 0.5 1))
        (app.engine.input:on-touch-up 1 11 0.2 0.3 0 0 0.5 2)
        (state:on-touch-up (engine-touch-payload 1 11 20 25 0 0 0.5 2))
        (state:on-leave)
        (assert (= (focus-manager:get-focused-node) focus-node)
                "NormalState touch should focus graph nodes after logical input is scaled into viewport space"))))
  (when view
    (view:drop))
  (when graph
    (drop-test-graph-map! graph))
  (set app.active-pointer-controls original-active-controls)
  (set app.hoverables original-hoverables)
  (set app.clickables original-clickables)
  (set app.movables original-movables)
  (set app.resizables original-resizables)
  (set app.touch-gesture-targets original-touch-targets)
  (set app.intersectables original-intersectables)
  (set app.first-person-controls original-first-person)
  (set app.object-selector original-object-selector)
  (set app.engine.width original-engine-width)
  (set app.engine.height original-engine-height)
  (set app.viewport original-viewport)
  (when (not ok)
    (error err)))

(fn fpc-state-injects-single-touch-as-mouse []
  (reset-engine-events)
  (local controls (create-controls-stub))
  (local original-controls app.first-person-controls)
  (local original-presentation-controls app.presentation-input-controls)
  (local original-touch-targets app.touch-gesture-targets)
  (set app.first-person-controls controls)
  (set app.presentation-input-controls (fn [] controls))
  (set app.touch-gesture-targets {:select-object (fn [_self _payload _opts] nil)})
  (local (ok err) (pcall (fn []
    (local state (FpcState))
    (state:on-enter)
    (state:on-touch-down (engine-touch-payload 1 11 10 20 0 0 0.5 1))
    (state:on-touch-motion (engine-touch-payload 1 11 18 24 8 4 0.5 2))
    (state:on-touch-up (engine-touch-payload 1 11 22 28 4 4 0.5 3))
    (assert (= controls.record.mouse_button_down 1))
    (assert (= controls.record.mouse_button_up 1))
    (assert controls.record.mouse_motion
            "touch motion should reach first-person controls")
    (state:on-leave))))
  (set app.first-person-controls original-controls)
  (set app.presentation-input-controls original-presentation-controls)
  (set app.touch-gesture-targets original-touch-targets)
  (when (not ok) (error err)))

(fn normal-state-injects-pen-as-mouse-and-restores-drawing-tool []
  (reset-engine-events)
  (local controls (create-controls-stub))
  (local original-hoverables (assert app.hoverables "states test requires app.hoverables"))
  (local original-clickables (assert app.clickables "states test requires app.clickables"))
  (local original-movables app.movables)
  (local original-resizables app.resizables)
  (local original-touch-targets app.touch-gesture-targets)
  (local original-controls app.first-person-controls)
  (local original-presentation-controls app.presentation-input-controls)
  (local original-controller app.drawing-controller)
  (local original-canvas-interactive app.canvas-interactive?)
  (local original-mode app.active-activity-id)
  (local tool-log [])
  (set app.hoverables {:on-enter (fn [])
                       :on-leave (fn [])
                       :on-mouse-motion (fn [_self _payload])
                       :clear-active (fn [_self] nil)})
  (set app.clickables {:on-mouse-button-down (fn [_self _payload])
                       :on-mouse-button-up (fn [_self _payload])
                       :active? false})
  (set app.movables {:drag-active? (fn [_self] false)
                     :on-mouse-motion (fn [_self _payload])
                     :on-mouse-button-down (fn [_self _payload])
                     :on-mouse-button-up (fn [_self _payload])})
  (set app.resizables {:drag-active? (fn [_self] false)
                       :on-mouse-motion (fn [_self _payload])
                       :on-mouse-button-down (fn [_self _payload])
                       :on-mouse-button-up (fn [_self _payload])})
  (set app.touch-gesture-targets {:select-object (fn [_self _payload _opts] nil)})
  (set app.first-person-controls controls)
  (set app.presentation-input-controls (fn [] controls))
  (set app.canvas-interactive? true)
  (set app.active-activity-id "drawing")
  (set app.activity-drawing-enabled? true)
  (set app.drawing-controller
       {:active-layer (fn [_self] {:id "layer-1" :kind "vector"})
        :active-tool (fn [self] self.tool)
        :persistent-tool (fn [self] self.tool)
        :tool "brush"
        :set-active-tool (fn [self tool]
                           (table.insert tool-log tool)
                            (set self.tool tool))})
  (local (ok err) (pcall (fn []
    (local state (NormalState))
    (own-test-state! :normal state)
    (state:on-enter)
    (state:on-pen-proximity-in {:pen-id 77
                                :x 10
                                :y 20
                                :xrel 0
                                :yrel 0
                                :timestamp 1
                                :in-range true})
    (state:on-pen-down {:pen-id 77
                        :x 10
                        :y 20
                        :xrel 0
                        :yrel 0
                        :timestamp 2
                        :in-range true
                        :eraser true})
    (state:on-touch-down {:touch-id 1
                          :finger-id 11
                          :x 14
                          :y 24
                          :xrel 0
                          :yrel 0
                          :pressure 0.5
                          :timestamp 3})
    (state:on-pen-up {:pen-id 77
                      :x 10
                      :y 20
                      :xrel 0
                      :yrel 0
                      :timestamp 4
                      :in-range true
                      :eraser false})
    (assert (= controls.record.mouse_button_down 1))
    (assert (= controls.record.mouse_button_up 1))
    (assert (= (# tool-log) 2))
    (assert (= (. tool-log 1) "eraser"))
    (assert (= (. tool-log 2) "brush"))
    (assert (= (app.drawing-controller:active-tool) "brush"))
    (state:on-leave))))
  (set app.hoverables original-hoverables)
  (set app.clickables original-clickables)
  (set app.movables original-movables)
  (set app.resizables original-resizables)
  (set app.touch-gesture-targets original-touch-targets)
  (set app.first-person-controls original-controls)
  (set app.presentation-input-controls original-presentation-controls)
  (set app.drawing-controller original-controller)
  (set app.canvas-interactive? original-canvas-interactive)
  (set app.activity-drawing-enabled? nil)
  (set app.active-activity-id original-mode)
  (when (not ok) (error err)))

(fn fpc-state-injects-pen-as-mouse []
  (reset-engine-events)
  (local controls (create-controls-stub))
  (local original-controls app.first-person-controls)
  (local original-presentation-controls app.presentation-input-controls)
  (set app.first-person-controls controls)
  (set app.presentation-input-controls (fn [] controls))
  (local (ok err) (pcall (fn []
    (local state (FpcState))
    (state:on-enter)
    (state:on-pen-proximity-in {:pen-id 77
                                :x 10
                                :y 20
                                :xrel 0
                                :yrel 0
                                :timestamp 1
                                :in-range true})
    (state:on-pen-down {:pen-id 77
                        :x 10
                        :y 20
                        :xrel 0
                        :yrel 0
                        :timestamp 2
                        :in-range true})
    (state:on-pen-motion {:pen-id 77
                          :x 18
                          :y 24
                          :xrel 8
                          :yrel 4
                          :timestamp 3
                          :in-range true})
    (state:on-pen-up {:pen-id 77
                      :x 18
                      :y 24
                      :xrel 0
                      :yrel 0
                      :timestamp 4
                      :in-range true})
    (assert (= controls.record.mouse_button_down 1))
    (assert (= controls.record.mouse_button_up 1))
    (assert controls.record.mouse_motion
            "pen motion should reach first-person controls")
    (state:on-leave))))
  (set app.first-person-controls original-controls)
  (set app.presentation-input-controls original-presentation-controls)
  (when (not ok) (error err)))

(fn normal-state-tab-cycles-focus []
  (reset-engine-events)
  (local original-states app.states)
  (local controls (create-controls-stub))
  (set app.first-person-controls controls)
  (local calls [])
  (local states
    (States {:focus_manager_provider (fn [_self]
                                       app.focus)}))
  (set app.focus {:focus-next (fn [_self opts]
                                  (table.insert calls opts))})
  (set-app-states! states)
  (local state (NormalState))
  (states:add-state :normal state)
  (state.on-enter)
  (app.engine.events.key-down.emit {:key 9 :mod 0})
  (assert (= (# calls) 1) "Tab should invoke focus cycling")
  (assert (= (. (. calls 1) :backwards?) false))
  (assert (= controls.record.key_down nil) "Tab should not reach controls")
  (app.engine.events.key-down.emit {:key 9 :mod 1})
  (assert (= (# calls) 2) "Shift+Tab should also invoke focus cycling")
  (assert (. (. calls 2) :backwards?) "Shift modifier should request backwards traversal")
  (state.on-leave)
  (set-app-states! original-states)
  (set app.focus nil)
  (set app.first-person-controls nil))

(fn normal-state-swallows-keys-when-input-active []
  (reset-engine-events)
  (local original-states app.states)
  (local controls (create-controls-stub))
  (set app.first-person-controls controls)
  (local input {:on-key-down (fn [_self _payload] false)})
  (local states (States {:hud_provider command-hints-hud-provider}))
  (local state (NormalState))
  (states:add-state :normal state)
  (states:set-state :normal)
  (set-app-states! states)
  (InputState.connect-input input)
  (state.on-enter)
  (app.engine.events.key-down.emit {:key 87})
  (assert (= controls.record.key_down nil) "Input should block controls when connected")
  (state.on-leave)
  (InputState.disconnect-input input)
  (set-app-states! original-states)
  (set app.first-person-controls nil))

(fn terrain-rect-pick-state-routes-and-restores []
  (reset-engine-events)
  (local original-states app.states)
  (var suspended-state nil)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal {})
  (states:add-state :terrain-rect-pick (TerrainRectPickState))
  (set suspended-state (TestSupport.suspend-active-state original-states))
  (set-app-states! states)
  (set app.hud {:build-context {}
                :world-units-per-pixel 1})
  (states:set-state :normal)
  (local forwarded [])
  (var active? false)
  (local session
    {:active? (fn [_self] active?)
     :begin (fn [_self] (set active? true))
     :cancel-selection (fn [_self] (set active? false))
     :begin-drag (fn [_self payload]
                   (table.insert forwarded [:button true payload.x payload.y])
                   true)
     :drag-active? (fn [_self] active?)
     :update-drag (fn [_self payload]
                    (table.insert forwarded [:motion payload.x payload.y])
                    true)
     :end-drag (fn [_self payload]
                 (table.insert forwarded [:button false payload.x payload.y])
                 (set active? false)
                 true)
     :on-key-down (fn [_self payload]
                    (table.insert forwarded [:key payload.key])
                    (when (= payload.key KEY_ESCAPE)
                      (set active? false)))})
  (TerrainRectPickManager.begin session)
  (assert (= (states:active-name) :terrain-rect-pick))
  (app.engine.events.mouse-button-down.emit {:button 1 :x 10 :y 20})
  (app.engine.events.mouse-motion.emit {:x 30 :y 40})
  (assert (= (# forwarded) 1))
  (assert (= (. (. forwarded 1) 1) :button))
  (app.engine.events.updated.emit 0.016)
  (app.engine.events.mouse-button-up.emit {:button 1 :x 30 :y 40})
  (assert (= (# forwarded) 3))
  (assert (= (. (. forwarded 1) 1) :button))
  (assert (= (. (. forwarded 2) 1) :motion))
  (assert (= (. (. forwarded 3) 1) :button))
  (assert (= (states:active-name) :normal)
          "terrain rect pick state should restore the previous state when the session completes")
  (set app.hud original-hud)
  (set-app-states! original-states)
  (TestSupport.resume-active-state suspended-state))

(fn terrain-rect-pick-state-coalesces-motion-until-update []
  (reset-engine-events)
  (local original-states app.states)
  (var suspended-state nil)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal {})
  (states:add-state :terrain-rect-pick (TerrainRectPickState))
  (set suspended-state (TestSupport.suspend-active-state original-states))
  (set-app-states! states)
  (set app.hud {:build-context {}
                :world-units-per-pixel 1})
  (states:set-state :normal)
  (local forwarded [])
  (var active? false)
  (local session
    {:active? (fn [_self] active?)
     :begin (fn [_self] (set active? true))
     :cancel-selection (fn [_self] (set active? false))
     :begin-drag (fn [_self payload]
                   (table.insert forwarded [:button true payload.x payload.y])
                   true)
     :drag-active? (fn [_self] active?)
     :update-drag (fn [_self payload]
                    (table.insert forwarded [:motion payload.x payload.y])
                    true)
     :end-drag (fn [_self payload]
                 (table.insert forwarded [:button false payload.x payload.y])
                 (set active? false)
                 true)
     :on-key-down (fn [_self _payload] nil)})
  (TerrainRectPickManager.begin session)
  (app.engine.events.mouse-button-down.emit {:button 1 :x 10 :y 20})
  (app.engine.events.mouse-motion.emit {:x 30 :y 40})
  (app.engine.events.mouse-motion.emit {:x 50 :y 60})
  (assert (= (# forwarded) 1)
          "motion should be deferred until the next update tick")
  (app.engine.events.updated.emit 0.016)
  (assert (= (# forwarded) 2))
  (assert (= (. (. forwarded 2) 1) :motion))
  (assert (= (. (. forwarded 2) 2) 50))
  (assert (= (. (. forwarded 2) 3) 60))
  (app.engine.events.mouse-button-up.emit {:button 1 :x 50 :y 60})
  (set app.hud original-hud)
  (set-app-states! original-states)
  (TestSupport.resume-active-state suspended-state))

(fn terrain-rect-pick-state-flushes-pending-motion-on-mouse-up []
  (reset-engine-events)
  (local original-states app.states)
  (var suspended-state nil)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal {})
  (states:add-state :terrain-rect-pick (TerrainRectPickState))
  (set suspended-state (TestSupport.suspend-active-state original-states))
  (set-app-states! states)
  (set app.hud {:build-context {}
                :world-units-per-pixel 1})
  (states:set-state :normal)
  (local forwarded [])
  (var active? false)
  (local session
    {:active? (fn [_self] active?)
     :begin (fn [_self] (set active? true))
     :cancel-selection (fn [_self] (set active? false))
     :begin-drag (fn [_self payload]
                   (table.insert forwarded [:button true payload.x payload.y])
                   true)
     :drag-active? (fn [_self] active?)
     :update-drag (fn [_self payload]
                    (table.insert forwarded [:motion payload.x payload.y])
                    true)
     :end-drag (fn [_self payload]
                 (table.insert forwarded [:button false payload.x payload.y])
                 (set active? false)
                 true)
     :on-key-down (fn [_self _payload] nil)})
  (TerrainRectPickManager.begin session)
  (app.engine.events.mouse-button-down.emit {:button 1 :x 10 :y 20})
  (app.engine.events.mouse-motion.emit {:x 30 :y 40})
  (app.engine.events.mouse-button-up.emit {:button 1 :x 30 :y 40})
  (assert (= (# forwarded) 3)
          "mouse up should flush pending drag motion before ending the drag")
  (assert (= (. (. forwarded 2) 1) :motion))
  (assert (= (. (. forwarded 2) 2) 30))
  (assert (= (. (. forwarded 2) 3) 40))
  (assert (= (. (. forwarded 3) 1) :button))
  (set app.hud original-hud)
  (set-app-states! original-states)
  (TestSupport.resume-active-state suspended-state))

(fn terrain-rect-pick-state-forwards-pending-start-motion-before-drag-active []
  (reset-engine-events)
  (local original-states app.states)
  (var suspended-state nil)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal {})
  (states:add-state :terrain-rect-pick (TerrainRectPickState))
  (set suspended-state (TestSupport.suspend-active-state original-states))
  (set-app-states! states)
  (set app.hud {:build-context {}
                :world-units-per-pixel 1})
  (states:set-state :normal)
  (local forwarded [])
  (var active? false)
  (var drag-active? false)
  (local session
    {:active? (fn [_self] active?)
     :begin (fn [_self] (set active? true))
     :cancel-selection (fn [_self] (set active? false) (set drag-active? false))
     :begin-drag (fn [_self payload]
                   (table.insert forwarded [:button true payload.x payload.y])
                   false)
     :drag-active? (fn [_self] drag-active?)
     :update-drag (fn [_self payload]
                    (table.insert forwarded [:motion payload.x payload.y])
                    (set drag-active? true)
                    true)
     :end-drag (fn [_self payload]
                 (table.insert forwarded [:button false payload.x payload.y])
                 (set active? false)
                 (set drag-active? false)
                 true)
     :on-key-down (fn [_self _payload] nil)})
  (TerrainRectPickManager.begin session)
  (app.engine.events.mouse-button-down.emit {:button 1 :x 10 :y 20})
  (app.engine.events.mouse-motion.emit {:x 30 :y 40})
  (assert (= (# forwarded) 1)
          "motion should still be deferred until the next update tick")
  (app.engine.events.updated.emit 0.016)
  (assert (= (# forwarded) 2)
          "pending-start motion should be forwarded even before drag-active becomes true")
  (assert (= (. (. forwarded 2) 1) :motion))
  (assert (= (. (. forwarded 2) 2) 30))
  (assert (= (. (. forwarded 2) 3) 40))
  (app.engine.events.mouse-button-up.emit {:button 1 :x 30 :y 40})
  (assert (= (. (. forwarded 3) 1) :button))
  (set app.hud original-hud)
  (set-app-states! original-states)
  (TestSupport.resume-active-state suspended-state))

(fn terrain-rect-pick-state-forwards-camera-wheel-and-updates []
  (reset-engine-events)
  (local original-states app.states)
  (var suspended-state nil)
  (local original-hud app.hud)
  (local original-controls app.first-person-controls)
  (local original-presentation-controls app.presentation-input-controls)
  (local original-hoverables (assert app.hoverables "states test requires app.hoverables"))
  (local states (States))
  (local controls (create-controls-stub))
  (states:add-state :normal {})
  (states:add-state :terrain-rect-pick (TerrainRectPickState))
  (set suspended-state (TestSupport.suspend-active-state original-states))
  (set-app-states! states)
  (set app.hud {:build-context {}
                :world-units-per-pixel 1})
  (set app.first-person-controls controls)
  (set app.presentation-input-controls (fn [] controls))
  (set app.hoverables (make-hoverables-stub))
  (local (ok err) (pcall (fn []
    (states:set-state :normal)
    (local session
      {:active? (fn [_self] true)
       :begin (fn [_self] true)
       :cancel-selection (fn [_self] nil)
       :begin-drag (fn [_self _payload] true)
       :drag-active? (fn [_self] true)
       :update-drag (fn [_self _payload] true)
       :end-drag (fn [_self _payload] true)
       :on-key-down (fn [_self _payload] nil)})
    (TerrainRectPickManager.begin session)
    (app.engine.events.mouse-wheel.emit {:x 0 :y 2})
    (app.engine.events.updated.emit 0.125)
    (assert (= controls.record.mouse_wheel 2))
    (assert (= controls.record.updated 0.125)))))
  (set app.hoverables original-hoverables)
  (set app.first-person-controls original-controls)
  (set app.presentation-input-controls original-presentation-controls)
  (set app.hud original-hud)
  (set-app-states! original-states)
  (TestSupport.resume-active-state suspended-state)
  (when (not ok) (error err)))

(fn terrain-paint-state-routes-and-restores []
  (reset-engine-events)
  (local original-states app.states)
  (var suspended-state nil)
  (local states (States))
  (states:add-state :normal {})
  (states:add-state :terrain-paint (TerrainPaintState))
  (set suspended-state (TestSupport.suspend-active-state original-states))
  (set-app-states! states)
  (states:set-state :normal)
  (local forwarded [])
  (var active? false)
  (local session
    {:active? (fn [_self] active?)
     :begin (fn [_self] (set active? true))
     :cancel-selection (fn [_self] (set active? false))
     :begin-stroke (fn [_self payload]
                     (table.insert forwarded [:button true payload.x payload.y])
                     true)
     :update-stroke (fn [_self payload]
                      (table.insert forwarded [:motion payload.x payload.y])
                      true)
     :end-stroke (fn [_self payload]
                   (table.insert forwarded [:button false payload.x payload.y])
                   (set active? false)
                   true)
     :on-key-down (fn [_self payload]
                    (table.insert forwarded [:key payload.key])
                    (when (= payload.key KEY_ESCAPE)
                      (set active? false)))})
  (TerrainPaintManager.begin session)
  (assert (= (states:active-name) :terrain-paint))
  (app.engine.events.mouse-button-down.emit {:button 1 :x 10 :y 20})
  (app.engine.events.mouse-motion.emit {:x 30 :y 40})
  (assert (= (# forwarded) 1))
  (app.engine.events.updated.emit 0.016)
  (app.engine.events.mouse-button-up.emit {:button 1 :x 30 :y 40})
  (assert (= (# forwarded) 3))
  (assert (= (. (. forwarded 1) 1) :button))
  (assert (= (. (. forwarded 2) 1) :motion))
  (assert (= (. (. forwarded 3) 1) :button))
  (assert (= (states:active-name) :normal)
          "terrain paint state should restore the previous state when the session completes")
  (set-app-states! original-states)
  (TestSupport.resume-active-state suspended-state))

(fn terrain-paint-state-routes-touch-and-restores []
  (reset-engine-events)
  (local original-states app.states)
  (local original-touch-targets app.touch-gesture-targets)
  (var suspended-state nil)
  (local states (States))
  (states:add-state :normal {})
  (states:add-state :terrain-paint (TerrainPaintState))
  (set suspended-state (TestSupport.suspend-active-state original-states))
  (set-app-states! states)
  (set app.touch-gesture-targets {:select-object (fn [_self _payload _opts] nil)})
  (states:set-state :normal)
  (local forwarded [])
  (var active? false)
  (local session
    {:active? (fn [_self] active?)
     :begin (fn [_self] (set active? true))
     :cancel-selection (fn [_self] (set active? false))
     :begin-stroke (fn [_self payload]
                     (table.insert forwarded [:button true payload.x payload.y])
                     true)
     :update-stroke (fn [_self payload]
                      (table.insert forwarded [:motion payload.x payload.y])
                      true)
     :end-stroke (fn [_self payload]
                   (table.insert forwarded [:button false payload.x payload.y])
                   (set active? false)
                   true)
     :on-key-down (fn [_self _payload] nil)})
  (TerrainPaintManager.begin session)
  (assert (= (states:active-name) :terrain-paint))
  (app.engine.events.touch-down:emit {:touch-id 1
                                      :finger-id 11
                                      :x 10
                                      :y 20
                                      :xrel 0
                                      :yrel 0
                                      :timestamp 1})
  (app.engine.events.touch-motion:emit {:touch-id 1
                                        :finger-id 11
                                        :x 30
                                        :y 40
                                        :xrel 20
                                        :yrel 20
                                        :timestamp 2})
  (assert (= (# forwarded) 1))
  (app.engine.events.updated:emit 0.016)
  (app.engine.events.touch-up:emit {:touch-id 1
                                    :finger-id 11
                                    :x 30
                                    :y 40
                                    :xrel 0
                                    :yrel 0
                                    :timestamp 3})
  (assert (= (# forwarded) 3))
  (assert (= (. (. forwarded 1) 1) :button))
  (assert (= (. (. forwarded 2) 1) :motion))
  (assert (= (. (. forwarded 3) 1) :button))
  (assert (= (states:active-name) :normal)
          "terrain paint touch should restore the previous state when the session completes")
  (set app.touch-gesture-targets original-touch-targets)
  (set-app-states! original-states)
  (TestSupport.resume-active-state suspended-state))

(fn terrain-paint-state-suppresses-touch-while-pen-active []
  (reset-engine-events)
  (local original-states app.states)
  (local original-touch-targets app.touch-gesture-targets)
  (var suspended-state nil)
  (local states (States))
  (states:add-state :normal {})
  (states:add-state :terrain-paint (TerrainPaintState))
  (set suspended-state (TestSupport.suspend-active-state original-states))
  (set-app-states! states)
  (set app.touch-gesture-targets {:select-object (fn [_self _payload _opts] nil)})
  (states:set-state :normal)
  (local forwarded [])
  (var active? false)
  (local session
    {:active? (fn [_self] active?)
     :begin (fn [_self] (set active? true))
     :cancel-selection (fn [_self] (set active? false))
     :begin-stroke (fn [_self payload]
                     (table.insert forwarded [:button true payload.x payload.y])
                     true)
     :update-stroke (fn [_self payload]
                      (table.insert forwarded [:motion payload.x payload.y])
                      true)
     :end-stroke (fn [_self payload]
                   (table.insert forwarded [:button false payload.x payload.y])
                   (set active? false)
                   true)
     :on-key-down (fn [_self _payload] nil)})
  (TerrainPaintManager.begin session)
  (local state (states:get-state :terrain-paint))
  (assert state "terrain paint state should be active")
  (state:on-pen-down {:pen-id 77
                      :x 10
                      :y 20
                      :xrel 0
                      :yrel 0
                      :timestamp 1
                      :in-range true})
  (state:on-touch-down {:touch-id 1
                        :finger-id 11
                        :x 30
                        :y 40
                        :xrel 0
                        :yrel 0
                        :pressure 0.5
                        :timestamp 2})
  (assert (= (# forwarded) 1)
          "touch should be suppressed while a pen stroke is active")
  (state:on-pen-up {:pen-id 77
                    :x 10
                    :y 20
                    :xrel 0
                    :yrel 0
                    :timestamp 3
                    :in-range true})
  (set app.touch-gesture-targets original-touch-targets)
  (set-app-states! original-states)
  (TestSupport.resume-active-state suspended-state))

(fn terrain-paint-state-cancels-active-touch-when-pen-takes-over []
  (reset-engine-events)
  (local original-states app.states)
  (local original-touch-targets app.touch-gesture-targets)
  (var suspended-state nil)
  (local states (States))
  (states:add-state :normal {})
  (states:add-state :terrain-paint (TerrainPaintState))
  (set suspended-state (TestSupport.suspend-active-state original-states))
  (set-app-states! states)
  (set app.touch-gesture-targets {:select-object (fn [_self _payload _opts] nil)})
  (states:set-state :normal)
  (local forwarded [])
  (var active? false)
  (local session
    {:active? (fn [_self] active?)
     :begin (fn [_self] (set active? true))
     :cancel-selection (fn [_self]
                         (set active? false))
     :begin-stroke (fn [_self payload]
                     (table.insert forwarded [:button true payload.x payload.y])
                     true)
     :update-stroke (fn [_self payload]
                      (table.insert forwarded [:motion payload.x payload.y])
                      true)
     :end-stroke (fn [_self payload]
                   (table.insert forwarded [:button false payload.x payload.y])
                   (set active? false)
                   true)
     :on-key-down (fn [_self _payload] nil)})
  (TerrainPaintManager.begin session)
  (local state (states:get-state :terrain-paint))
  (assert state "terrain paint state should be active")
  (state:on-touch-down {:touch-id 1
                        :finger-id 11
                        :x 10
                        :y 20
                        :xrel 0
                        :yrel 0
                        :pressure 0.5
                        :timestamp 1})
  (assert active? "touch stroke should begin")
  (state:on-pen-down {:pen-id 77
                      :x 30
                      :y 40
                      :xrel 0
                      :yrel 0
                      :timestamp 2
                      :in-range true})
  (state:on-touch-motion {:touch-id 1
                          :finger-id 11
                          :x 15
                          :y 25
                          :xrel 5
                          :yrel 5
                          :pressure 0.5
                          :timestamp 3})
  (assert (>= (# forwarded) 2))
  (assert (= (. (. forwarded 1) 1) :button))
  (local last-entry (. forwarded (# forwarded)))
  (assert (= (. last-entry 1) :button))
  (assert (= (. last-entry 2) false))
  (assert (not active?)
          "suppressed touch should end the active touch-driven stroke cleanly")
  (set app.touch-gesture-targets original-touch-targets)
  (set-app-states! original-states)
  (TestSupport.resume-active-state suspended-state))

(fn normal-state-keeps-eraser-override-while-another-pen-is-still-eraser []
  (reset-engine-events)
  (local controls (create-controls-stub))
  (local original-hoverables app.hoverables)
  (local original-clickables app.clickables)
  (local original-movables app.movables)
  (local original-resizables app.resizables)
  (local original-touch-targets app.touch-gesture-targets)
  (local original-controls app.first-person-controls)
  (local original-controller app.drawing-controller)
  (local original-canvas-interactive app.canvas-interactive?)
  (local original-mode app.active-activity-id)
  (local tool-log [])
  (set app.hoverables {:on-enter (fn [])
                       :on-leave (fn [])
                       :on-mouse-motion (fn [_self _payload])
                       :clear-active (fn [_self] nil)})
  (set app.clickables {:on-mouse-button-down (fn [_self _payload])
                       :on-mouse-button-up (fn [_self _payload])
                       :active? false})
  (set app.movables {:drag-active? (fn [_self] false)
                     :on-mouse-motion (fn [_self _payload])
                     :on-mouse-button-down (fn [_self _payload])
                     :on-mouse-button-up (fn [_self _payload])})
  (set app.resizables {:drag-active? (fn [_self] false)
                       :on-mouse-motion (fn [_self _payload])
                       :on-mouse-button-down (fn [_self _payload])
                       :on-mouse-button-up (fn [_self _payload])})
  (set app.touch-gesture-targets {:select-object (fn [_self _payload _opts] nil)})
  (set app.first-person-controls controls)
  (set app.canvas-interactive? true)
  (set app.active-activity-id "drawing")
  (set app.activity-drawing-enabled? true)
  (set app.drawing-controller
       {:active-layer (fn [_self] {:id "layer-1" :kind "vector"})
        :active-tool (fn [self] self.tool)
        :persistent-tool (fn [self] self.tool)
        :tool "brush"
        :set-active-tool (fn [self tool]
                           (table.insert tool-log tool)
                           (set self.tool tool))})
  (local state (NormalState))
  (own-test-state! :normal state)
  (state:on-enter)
  (state:on-pen-down {:pen-id 77
                      :x 10
                      :y 20
                      :xrel 0
                      :yrel 0
                      :timestamp 1
                      :in-range true
                      :eraser true})
  (state:on-pen-down {:pen-id 88
                      :x 12
                      :y 22
                      :xrel 0
                      :yrel 0
                      :timestamp 2
                      :in-range true
                      :eraser true})
  (state:on-pen-up {:pen-id 88
                    :x 12
                    :y 22
                    :xrel 0
                    :yrel 0
                    :timestamp 3
                    :in-range true
                    :eraser false})
  (assert (= (app.drawing-controller:active-tool) "eraser")
          "releasing one eraser pen should not restore brush while another eraser pen is still active")
  (state:on-pen-up {:pen-id 77
                    :x 10
                    :y 20
                    :xrel 0
                    :yrel 0
                    :timestamp 4
                    :in-range true
                    :eraser false})
  (assert (= (app.drawing-controller:active-tool) "brush"))
  (assert (= (# tool-log) 2))
  (assert (= (. tool-log 1) "eraser"))
  (assert (= (. tool-log 2) "brush"))
  (state:on-leave)
  (set app.hoverables original-hoverables)
  (set app.clickables original-clickables)
  (set app.movables original-movables)
  (set app.resizables original-resizables)
  (set app.touch-gesture-targets original-touch-targets)
  (set app.first-person-controls original-controls)
  (set app.drawing-controller original-controller)
  (set app.canvas-interactive? original-canvas-interactive)
  (set app.activity-drawing-enabled? nil)
  (set app.active-activity-id original-mode))

(fn terrain-paint-state-coalesces-motion-until-update []
  (reset-engine-events)
  (local original-states app.states)
  (var suspended-state nil)
  (local states (States))
  (states:add-state :normal {})
  (states:add-state :terrain-paint (TerrainPaintState))
  (set suspended-state (TestSupport.suspend-active-state original-states))
  (set-app-states! states)
  (states:set-state :normal)
  (local forwarded [])
  (var active? false)
  (local session
    {:active? (fn [_self] active?)
     :begin (fn [_self] (set active? true))
     :cancel-selection (fn [_self] (set active? false))
     :begin-stroke (fn [_self payload]
                     (table.insert forwarded [:button true payload.x payload.y])
                     true)
     :update-stroke (fn [_self payload]
                      (table.insert forwarded [:motion payload.x payload.y])
                      true)
     :end-stroke (fn [_self payload]
                   (table.insert forwarded [:button false payload.x payload.y])
                   (set active? false)
                   true)
     :on-key-down (fn [_self _payload] nil)})
  (TerrainPaintManager.begin session)
  (app.engine.events.mouse-button-down.emit {:button 1 :x 10 :y 20})
  (app.engine.events.mouse-motion.emit {:x 30 :y 40})
  (app.engine.events.mouse-motion.emit {:x 50 :y 60})
  (assert (= (# forwarded) 1))
  (app.engine.events.updated.emit 0.016)
  (assert (= (# forwarded) 2))
  (assert (= (. (. forwarded 2) 1) :motion))
  (assert (= (. (. forwarded 2) 2) 50))
  (assert (= (. (. forwarded 2) 3) 60))
  (app.engine.events.mouse-button-up.emit {:button 1 :x 50 :y 60})
  (set-app-states! original-states)
  (TestSupport.resume-active-state suspended-state))

(fn terrain-paint-state-forwards-mouse-wheel []
  (reset-engine-events)
  (local original-controls app.first-person-controls)
  (local original-presentation-controls app.presentation-input-controls)
  (local original-hoverables app.hoverables)
  (local original-states app.states)
  (local controls (create-controls-stub))
  (local hoverables (make-hoverables-stub))
  (local states (States))
  (set app.first-person-controls controls)
  (set app.presentation-input-controls (fn [] controls))
  (set app.hoverables hoverables)
  (set-app-states! states)
  (local state (TerrainPaintState))
  (states:add-state :terrain-paint state)
  (state:on-enter)
  (app.engine.events.mouse-wheel:emit {:x 0 :y 3})
  (state:on-leave)
  (assert (= controls.record.mouse_wheel 3))
  (set-app-states! original-states)
  (set app.first-person-controls original-controls)
  (set app.presentation-input-controls original-presentation-controls)
  (set app.hoverables original-hoverables))

(fn terrain-paint-state-forwards-camera-updates []
  (reset-engine-events)
  (local original-controls app.first-person-controls)
  (local original-presentation-controls app.presentation-input-controls)
  (local original-hoverables app.hoverables)
  (local original-states app.states)
  (local controls (create-controls-stub))
  (local hoverables (make-hoverables-stub))
  (local states (States))
  (set app.first-person-controls controls)
  (set app.presentation-input-controls (fn [] controls))
  (set app.hoverables hoverables)
  (set-app-states! states)
  (local state (TerrainPaintState))
  (states:add-state :terrain-paint state)
  (state:on-enter)
  (app.engine.events.updated.emit 0.125)
  (state:on-leave)
  (assert (= controls.record.updated 0.125))
  (set-app-states! original-states)
  (set app.first-person-controls original-controls)
  (set app.presentation-input-controls original-presentation-controls)
  (set app.hoverables original-hoverables))

(fn terrain-rect-pick-manager-cleans-up-dropped-session []
  (local TerrainRectPickManager (require :graph/view/terrain-rect-pick-manager))
  (reset-engine-events)
  (local original-states app.states)
  (var suspended-state nil)
  (local original-hud app.hud)
  (local states (States))
  (states:add-state :normal {})
  (states:add-state :terrain-rect-pick (TerrainRectPickState))
  (set suspended-state (TestSupport.suspend-active-state original-states))
  (set-app-states! states)
  (set app.hud {:build-context {}
                :world-units-per-pixel 1})
  (states:set-state :normal)
  (var active? false)
  (local session
    {:active? (fn [_self] active?)
     :begin (fn [_self] (set active? true))
     :cancel-selection (fn [_self] (set active? false))
     :begin-drag (fn [_self _payload] true)
     :drag-active? (fn [_self] active?)
     :update-drag (fn [_self _payload] true)
     :end-drag (fn [_self _payload]
                 (set active? false)
                 true)
     :on-key-down (fn [_self _payload] nil)})
  (TerrainRectPickManager.begin session)
  (assert (= (states:active-name) :terrain-rect-pick))
  (assert (= (TerrainRectPickManager.active-session) session))
  (assert (TerrainRectPickManager.cleanup-session session)
          "cleanup-session should clear an owned terrain rect pick session")
  (assert (= (TerrainRectPickManager.active-session) nil))
  (assert (= (states:active-name) :normal)
          "cleanup-session should restore the previous app state")
  (set app.hud original-hud)
  (set-app-states! original-states)
  (TestSupport.resume-active-state suspended-state))

(fn terrain-paint-manager-cleans-up-dropped-session []
  (local TerrainPaintManager (require :graph/view/terrain-paint-manager))
  (reset-engine-events)
  (local original-states app.states)
  (var suspended-state nil)
  (local states (States))
  (states:add-state :normal {})
  (states:add-state :terrain-paint (TerrainPaintState))
  (set suspended-state (TestSupport.suspend-active-state original-states))
  (set-app-states! states)
  (states:set-state :normal)
  (var active? false)
  (local session
    {:active? (fn [_self] active?)
     :begin (fn [_self] (set active? true))
     :cancel-selection (fn [_self] (set active? false))
     :begin-stroke (fn [_self _payload] true)
     :update-stroke (fn [_self _payload] true)
     :end-stroke (fn [_self _payload]
                   (set active? false)
                   true)
     :on-key-down (fn [_self _payload] nil)})
  (TerrainPaintManager.begin session)
  (assert (= (states:active-name) :terrain-paint))
  (assert (= (TerrainPaintManager.active-session) session))
  (assert (TerrainPaintManager.cleanup-session session)
          "cleanup-session should clear an owned terrain paint session")
  (assert (= (TerrainPaintManager.active-session) nil))
  (assert (= (states:active-name) :normal)
          "cleanup-session should restore the previous app state")
  (set-app-states! original-states)
  (TestSupport.resume-active-state suspended-state))

(fn state-switch-during-mouse-up-does-not-deliver-same-event-to-new-state []
  (reset-engine-events)
  (local original-states app.states)
  (local states (States))
  (var next-state-mouse-up 0)
  (states:add-state
    :normal
    (State {:name :normal
            :routes (interactive-routes
                      {:mouse-button-up (fn [_event-name _ctx _payload]
                                          (states:set-state :next)
                                          true)})
            :enter [HoverHandlers.HoverLifecycle]
            :leave [HoverHandlers.HoverLifecycle]}))
  (states:add-state
    :next
    (State {:name :next
            :routes (interactive-routes
                      {:mouse-button-up (fn [_event-name _ctx _payload]
                                          (set next-state-mouse-up (+ next-state-mouse-up 1))
                                          true)})
            :enter [HoverHandlers.HoverLifecycle]
            :leave [HoverHandlers.HoverLifecycle]}))
  (set-app-states! states)
  (states:set-state :normal)
  (app.engine.events.mouse-button-up.emit {:button 1 :x 10 :y 20})
  (assert (= next-state-mouse-up 0)
          "switching states during mouse-up should not deliver the same mouse-up to the newly entered state")
  (assert (= (states:active-name) :next))
  (set-app-states! original-states))

(fn state-enter-fails-fast-when-used-engine-signal-missing []
  (local original-events app.engine.events)
  (set app.engine.events (fresh-engine-events))
  (set app.engine.events.mouse-wheel nil)
  (local (ok err) (pcall
                    (fn []
                      (local broken (State {:name :broken
                                            :routes {:mouse-wheel (fn [_event-name _ctx _payload] true)}}))
                      ((. broken :on-enter)))))
  (set app.engine.events original-events)
  (assert (not ok))
  (assert (and err (string.find err "requires engine event signal mouse%-wheel"))))

(fn state-enters-only-connect-declared-routes []
  (local original-events app.engine.events)
  (local connect-log [])
  (set app.engine.events (fresh-engine-events-with-connect-log connect-log))
  (local state
    (State {:name :subset
            :routes {:key-down (fn [_event-name _ctx _payload] true)
                     :updated (fn [_event-name _ctx _payload] true)}}))
  (state:on-enter)
  (state:on-leave)
  (set app.engine.events original-events)
  (assert (= (# connect-log) 2))
  (assert (= (. connect-log 1) :key-down))
  (assert (= (. connect-log 2) :updated)))

(fn state-route-wrappers-fail-fast-on-malformed-config []
  (local (ok-map err-map)
    (pcall
      (fn []
        (State {:name :bad-map
                :route-wrappers {:hint (fn [_route-key route _ctx _state] route)}
                :routes {}}))))
  (assert (not ok-map)
          "route-wrappers should reject map-shaped tables")
  (assert (and err-map
               (string.find err-map "route%-wrappers must be a dense list"))
          "route-wrappers should report map-shaped tables clearly")
  (local (ok-hole err-hole)
    (pcall
      (fn []
        (State {:name :bad-hole
                :route-wrappers {1 (fn [_route-key route _ctx _state] route)
                                 3 (fn [_route-key route _ctx _state] route)}
                :routes {}}))))
  (assert (not ok-hole)
          "route-wrappers should reject lists with holes")
  (assert (and err-hole
               (string.find err-hole "route%-wrappers must not contain holes"))
          "route-wrappers should report holes clearly"))

(fn exercise-normal-state-delete-removes-graph-selection []
  (reset-engine-events)
  (local controls (create-controls-stub))
  (set app.first-person-controls controls)
  (set app.active-activity-id "graph")
  (set app.canvas-interactive? true)
  (set app.drawing-controller nil)
  (var removed 0)
  (set app.graph-view {:remove-selected-nodes (fn [_self]
                                                (set removed (+ removed 1))
                                                1)})
  (set app.activity-delete-selection
       (fn []
         (> (app.graph-view:remove-selected-nodes) 0)))
  (local state (NormalState))
  (own-test-state! :normal state)
  (local (ok result)
    (pcall
      (fn []
        (state.on-enter)
        (app.engine.events.key-down.emit {:key KEY_DELETE})
        (assert (= removed 1) "Delete should trigger graph selection removal")
        (assert (= controls.record.key_down nil) "Handled delete should not reach controls"))))
  (pcall state.on-leave)
  (if ok result (error result)))

(fn exercise-normal-state-enter-opens-focused-graph-node []
  (reset-engine-events)
  (local controls (create-controls-stub))
  (set app.first-person-controls controls)
  (set app.active-activity-id "graph")
  (set app.canvas-interactive? true)
  (set app.drawing-controller nil)
  (var opened 0)
  (local states
    (States {:focus_manager_provider (fn [_self]
                                       nil)}))
  (set app.graph-view {:open-focused-node (fn [_self]
                                            (set opened (+ opened 1))
                                            true)})
  (set app.activity-activate-focused
       (fn []
         (app.graph-view:open-focused-node)))
  (set-app-states! states)
  (local state (NormalState))
  (states:add-state :normal state)
  (local (ok result)
    (pcall
      (fn []
        (state.on-enter)
        (app.engine.events.key-down.emit {:key KEY_RETURN})
        (assert (= opened 1) "Enter should open focused graph node")
        (assert (= controls.record.key_down nil) "Handled enter should not reach controls"))))
  (pcall state.on-leave)
  (if ok result (error result)))

(fn exercise-normal-state-f4-without-workspace-shell []
  (reset-engine-events)
  (local controls (create-controls-stub))
  (set app.first-person-controls controls)
  (set app.active-activity-id "graph")
  (set app.drawing-controller nil)
  (set app.canvas nil)
  (set app.toggle-active-interaction-surface nil)
  (set app.graph-view nil)
  (var created 0)
  (var dropped 0)
  (set app.graph-view-factory
       (fn []
         (set created (+ created 1))
         (local view {})
         (set view.drop
              (fn [_self]
                (set dropped (+ dropped 1))))
         view))
  (local state (NormalState))
  (own-test-state! :normal state)
  (local (ok result)
    (pcall
      (fn []
        (state.on-enter)
        (app.engine.events.key-down.emit {:key KEY_F4})
        (assert (= created 0) "F4 should not recreate removed graph-view fallback behavior")
        (assert (not app.graph-view) "F4 should leave app.graph-view unchanged without workspace shell support")
        (assert (= controls.record.key_down nil) "F4 should remain a no-op when no workspace shell is available"))))
  (pcall state.on-leave)
  (if ok result (error result)))

(fn normal-state-delete-removes-graph-selection []
  (with-restored-app-fields
    [:activity-delete-selection
     :active-activity-id
     :canvas-interactive?
     :drawing-controller
     :first-person-controls
     :graph-view]
    exercise-normal-state-delete-removes-graph-selection))

(fn normal-state-enter-opens-focused-graph-node []
  (with-restored-app-fields
    [:activity-activate-focused
     :active-activity-id
     :canvas-interactive?
     :drawing-controller
     :first-person-controls
     :graph-view
     :states]
    exercise-normal-state-enter-opens-focused-graph-node))

(fn normal-state-activity-keyboard-commands-require-interactive-canvas []
  (reset-engine-events)
  (local original-delete-selection app.activity-delete-selection)
  (local original-activate-focused app.activity-activate-focused)
  (local original-canvas-interactive? app.canvas-interactive?)
  (local original-activity-id app.active-activity-id)
  (set app.active-activity-id "graph")
  (set app.canvas-interactive? false)
  (var removed 0)
  (var opened 0)
  (set app.activity-delete-selection (fn []
                                       (set removed (+ removed 1))
                                       true))
  (set app.activity-activate-focused (fn []
                                       (set opened (+ opened 1))
                                       true))
  (local state (NormalState))
  (own-test-state! :normal state)
  (state.on-enter)
  (app.engine.events.key-down.emit {:key KEY_DELETE})
  (app.engine.events.key-down.emit {:key KEY_RETURN})
  (state.on-leave)
  (set app.activity-delete-selection original-delete-selection)
  (set app.activity-activate-focused original-activate-focused)
  (set app.canvas-interactive? original-canvas-interactive?)
  (set app.active-activity-id original-activity-id)
  (assert (= removed 0)
          "Delete should not reach activity hooks when canvas is not interactive")
  (assert (= opened 0)
          "Enter should not reach activity hooks when canvas is not interactive"))

(fn normal-state-directional-focus-triggers []
  (reset-engine-events)
  (local original-states app.states)
  (local controls (create-controls-stub))
  (local original-presentation-controls app.presentation-input-controls)
  (local original-presentation-camera app.presentation-camera)
  (set app.first-person-controls controls)
  (set app.presentation-input-controls (fn [] controls))
  (local calls [])
  (local camera {:id :cam})
  (local states
    (States {:focus_manager_provider (fn [_self]
                                       app.focus)}))
  (set app.camera camera)
  (set app.presentation-camera (fn [opts] camera))
  (set app.focus {:focus-direction (fn [_self opts]
                                     (table.insert calls opts))})
  (set-app-states! states)
  (local state (NormalState))
  (states:add-state :normal state)
  (state.on-enter)
  (local keys [KEY_LEFT KEY_RIGHT KEY_UP KEY_DOWN KEY_H KEY_L KEY_K KEY_J])
  (local expected [:left :right :up :down :left :right :up :down])
  (for [i 1 (length keys)]
    (app.engine.events.key-down.emit {:key (. keys i)})
    (local entry (. calls i))
    (assert entry "Directional focus should be invoked")
    (assert (= (. entry :direction) (. expected i)))
    (assert (= (. entry :camera) camera)))
  (state.on-leave)
  (set-app-states! original-states)
  (set app.focus nil)
  (set app.camera nil)
  (set app.presentation-camera original-presentation-camera)
  (set app.first-person-controls nil)
  (set app.presentation-input-controls original-presentation-controls))

(fn normal-state-directional-focus-skips-with-input []
  (reset-engine-events)
  (local original-states app.states)
  (local controls (create-controls-stub))
  (set app.first-person-controls controls)
  (local calls [])
  (local states
    (States {:focus_manager_provider (fn [_self]
                                       app.focus)}))
  (set app.focus {:focus-direction (fn [_self opts]
                                     (table.insert calls opts))})
  (set-app-states! states)
  (local input {:on-key-down (fn [_self _payload] false)})
  (InputState.connect-input input)
  (local state (NormalState))
  (states:add-state :normal state)
  (state.on-enter)
  (app.engine.events.key-down.emit {:key KEY_RIGHT})
  (assert (= (# calls) 0) "Directional focus should skip while input active")
  (state.on-leave)
  (InputState.disconnect-input input)
  (set-app-states! original-states)
  (set app.focus nil)
  (set app.first-person-controls nil))

(fn normal-state-f4-ignores-graph-view-factory-without-workspace-shell []
  (with-restored-app-fields
    [:active-activity-id
     :canvas
     :drawing-controller
     :first-person-controls
     :graph-view
     :graph-view-factory
     :toggle-active-interaction-surface]
    exercise-normal-state-f4-without-workspace-shell))

(fn normal-state-f4-toggles-canvas-surface []
  (reset-engine-events)
  (local original-canvas app.canvas)
  (local original-toggle-active-interaction-surface app.toggle-active-interaction-surface)
  (local controls (create-controls-stub))
  (set app.first-person-controls controls)
  (var toggles 0)
  (set app.canvas {})
  (set app.toggle-active-interaction-surface
       (fn []
         (set toggles (+ toggles 1))
         true))
  (local state (NormalState))
  (own-test-state! :normal state)
  (state.on-enter)
  (app.engine.events.key-down.emit {:key KEY_F4})
  (assert (= toggles 1) "F4 should toggle the canvas surface when workspace shell support exists")
  (assert (= controls.record.key_down nil) "Handled F4 should not reach controls")
  (state.on-leave)
  (set app.canvas original-canvas)
  (set app.toggle-active-interaction-surface original-toggle-active-interaction-surface)
  (set app.first-person-controls nil))

(fn normal-state-command-hints-label-f4-as-toggle-canvas []
  (reset-engine-events)
  (local original-canvas app.canvas)
  (local original-toggle-active-interaction-surface app.toggle-active-interaction-surface)
  (set app.canvas {})
  (set app.toggle-active-interaction-surface (fn [] true))
  (local state (NormalState))
  (local sections (state.command_hints_provider state {}))
  (local entries (and (> (length sections) 0) (. (. sections 1) :entries)))
  (var f4-entry nil)
  (each [_ entry (ipairs (or entries []))]
    (when (= entry.key "f4")
      (set f4-entry entry)))
  (assert f4-entry "NormalState command hints should expose an F4 entry")
  (assert (= f4-entry.label "toggle-canvas")
          "NormalState should label F4 as toggle-canvas when the workspace shell is available")
  (set app.canvas original-canvas)
  (set app.toggle-active-interaction-surface original-toggle-active-interaction-surface))

(fn normal-state-backquote-opens-fennel-interpreters []
  (reset-engine-events)
  (local controls (create-controls-stub))
  (set app.first-person-controls controls)
  (var opens 0)
  (set app.scene {:add-panel-child (fn [_self opts]
                                     (set opens (+ opens 1))
                                     opts)})
  (local state (NormalState))
  (own-test-state! :normal state)
  (state.on-enter)
  (app.engine.events.key-down.emit {:key KEY_BACKQUOTE})
  (app.engine.events.key-down.emit {:key KEY_BACKQUOTE})
  (assert (= opens 2) "Backquote should open a new interpreter each press")
  (assert (= controls.record.key_down nil) "Handled backquote should not reach controls")
  (state.on-leave)
  (set app.scene nil)
  (set app.first-person-controls nil))

(table.insert tests {:name "State transitions call enter/leave hooks" :fn transitions-call-enter-and-leave})
(table.insert tests {:name "Setting the same state twice is a no-op" :fn reselecting-active-state-noops})
(table.insert tests {:name "State history records recent transitions" :fn state-history-tracks-transitions})
(table.insert tests {:name "States remove inactive registered state" :fn remove-state-unregisters-inactive-state})
(table.insert tests {:name "States remove active state calls leave" :fn remove-state-leaves-active-state})
(table.insert tests {:name "States remove active state requires fallback" :fn remove-active-state-requires-fallback})
(table.insert tests {:name "States replace owner clears previous owner" :fn add-state-replacing-owner-clears-previous-owner})
(table.insert tests {:name "States reject active replacement via add-state" :fn add-state-rejects-active-replacement})
(table.insert tests {:name "States rejection does not bind rejected state" :fn add-state-rejection-does-not-bind-rejected-state})
(table.insert tests {:name "States rejects same-object alias via add-state" :fn add-state-rejects-same-object-alias})
(table.insert tests {:name "States re-adding same object is idempotent" :fn add-state-re-registering-same-object-is-idempotent})
(table.insert tests {:name "States add-state idempotent when active" :fn add-state-idempotent-when-active})
(table.insert tests {:name "Normal state forwards events to controls" :fn normal-state-forwards-events})
(table.insert tests {:name "Normal state injects single touch as mouse" :fn normal-state-injects-single-touch-as-mouse})
(table.insert tests {:name "Normal state routes canvas multitouch to active controls"
                     :fn normal-state-routes-canvas-multitouch-to-active-controls})
(table.insert tests {:name "Normal state forwards control click suppression to clickables"
                     :fn normal-state-forwards-control-click-suppression-to-clickables})
(table.insert tests {:name "Normal state touch focuses graph node under logical input scaling"
                     :fn normal-state-touch-focuses-graph-node-under-logical-input-scaling})
(table.insert tests {:name "Normal state injects pen as mouse and restores drawing tool"
                     :fn normal-state-injects-pen-as-mouse-and-restores-drawing-tool})
(table.insert tests {:name "Normal state keeps eraser override while another pen is still eraser"
                     :fn normal-state-keeps-eraser-override-while-another-pen-is-still-eraser})
(table.insert tests {:name "Normal state Tab cycles focus" :fn normal-state-tab-cycles-focus})
(table.insert tests {:name "Normal state swallows keys when input is active" :fn normal-state-swallows-keys-when-input-active})
(table.insert tests {:name "Terrain rect pick state routes and restores" :fn terrain-rect-pick-state-routes-and-restores})
(table.insert tests {:name "Terrain rect pick state coalesces motion until update"
                     :fn terrain-rect-pick-state-coalesces-motion-until-update})
(table.insert tests {:name "Terrain rect pick state flushes pending motion on mouse up"
                     :fn terrain-rect-pick-state-flushes-pending-motion-on-mouse-up})
(table.insert tests {:name "Terrain rect pick state forwards camera wheel and updates"
                     :fn terrain-rect-pick-state-forwards-camera-wheel-and-updates})
(table.insert tests {:name "Terrain paint state routes and restores"
                     :fn terrain-paint-state-routes-and-restores})
(table.insert tests {:name "Terrain paint state routes touch and restores"
                     :fn terrain-paint-state-routes-touch-and-restores})
(table.insert tests {:name "Terrain paint state suppresses touch while pen active"
                     :fn terrain-paint-state-suppresses-touch-while-pen-active})
(table.insert tests {:name "Terrain paint state cancels active touch when pen takes over"
                     :fn terrain-paint-state-cancels-active-touch-when-pen-takes-over})
(table.insert tests {:name "Terrain paint state coalesces motion until update"
                     :fn terrain-paint-state-coalesces-motion-until-update})
(table.insert tests {:name "Terrain paint state forwards mouse wheel"
                     :fn terrain-paint-state-forwards-mouse-wheel})
(table.insert tests {:name "Terrain paint state forwards camera updates"
                     :fn terrain-paint-state-forwards-camera-updates})
(table.insert tests {:name "Terrain rect pick manager cleans up dropped session"
                     :fn terrain-rect-pick-manager-cleans-up-dropped-session})
(table.insert tests {:name "Terrain paint manager cleans up dropped session"
                     :fn terrain-paint-manager-cleans-up-dropped-session})
(table.insert tests {:name "State switch during mouse up does not deliver same event to new state"
                     :fn state-switch-during-mouse-up-does-not-deliver-same-event-to-new-state})
(table.insert tests {:name "State enter fails fast when used engine signal missing"
                     :fn state-enter-fails-fast-when-used-engine-signal-missing})
(table.insert tests {:name "State enters only connect declared routes"
                     :fn state-enters-only-connect-declared-routes})
(table.insert tests {:name "State route wrappers fail fast on malformed config"
                     :fn state-route-wrappers-fail-fast-on-malformed-config})
(table.insert tests {:name "Normal state directional focus triggers" :fn normal-state-directional-focus-triggers})
(table.insert tests {:name "Normal state directional focus skips while input active"
                     :fn normal-state-directional-focus-skips-with-input})
(table.insert tests {:name "Normal state delete removes selected graph nodes" :fn normal-state-delete-removes-graph-selection})
(table.insert tests {:name "Normal state Enter opens focused graph node" :fn normal-state-enter-opens-focused-graph-node})
(table.insert tests {:name "Normal state activity keyboard commands require interactive canvas"
                     :fn normal-state-activity-keyboard-commands-require-interactive-canvas})
(table.insert tests {:name "Normal state F4 ignores graph view factory without workspace shell"
                      :fn normal-state-f4-ignores-graph-view-factory-without-workspace-shell})
(table.insert tests {:name "Normal state F4 toggles canvas surface" :fn normal-state-f4-toggles-canvas-surface})
(table.insert tests {:name "Normal state command hints label F4 as toggle-canvas"
                     :fn normal-state-command-hints-label-f4-as-toggle-canvas})
(table.insert tests {:name "Normal state backquote opens interpreter dialogs" :fn normal-state-backquote-opens-fennel-interpreters})

(fn with-state-recorder [body]
  (local original app.states)
  (local transitions [])
  (local states
    (States {:hud_provider command-hints-hud-provider
             :focus_manager_provider (fn [_self]
                                       app.focus)}))
  (local original-set-state states.set-state)
  (set states.set-state
       (fn [_self name]
         (when (not (states:get-state name))
           (states:add-state name {}))
         (table.insert transitions name)
         (original-set-state states name)))
  (fn install-state [name state]
    (states:add-state name state)
    state)
  (set-app-states! states)
  (local (ok result) (pcall (fn [] (body transitions install-state states))))
  (set-app-states! original)
  (when (not ok)
    (error result))
  result)

(fn normal-state-leader-enters-leader-state []
  (with-state-recorder
    (fn [transitions install-state]
      (local state (install-state :normal (NormalState)))
      (state.on-key-down {:key KEY_SPACE})
      (assert (= (# transitions) 1) "Space should move to leader state")
      (assert (= (. transitions 1) :leader))
      (state.on-key-down {:key KEY_Q})
      (assert (= (# transitions) 1) "Non-leader keys should defer to base handling"))
    ))

(fn leader-state-c-enters-camera-state []
  (with-state-recorder
    (fn [transitions install-state]
      (local state (install-state :leader (LeaderState)))
      (state.on-key-down {:key KEY_C})
      (assert (= (# transitions) 1) "C should move to camera state")
      (assert (= (. transitions 1) :camera)))))

(fn leader-state-p-opens-launcher []
  (local original-hud app.hud)
  (local original-engine app.engine)
  (local original-states app.states)
  (local transitions [])
  (var panel-added? false)
  (local states
    (States {:hud_provider (fn [_self]
                             app.hud)
             :focus_manager_provider (fn [_self]
                                       app.focus)}))
  (set app.hud {:add-panel-child (fn [_self _opts]
                                  (set panel-added? true)
                                  {:set-items (fn [_view _items] nil)
                                   :set-query (fn [_view _query] nil)})
                :remove-panel-child (fn [_self _element] true)
                :command-hints (make-command-hints-stub)})
  (states:add-state :leader {})
  (states:set-state :leader)
  (local original-set-state states.set-state)
  (set states.set-state
       (fn [_self name]
         (table.insert transitions name)
         (original-set-state states name)))
  (set-app-states! states)
  (set app.engine {:get-asset-path (fn [path]
                                    (if (= path "lua/launchables")
                                        (.. (or (os.getenv "SPACE_ASSETS_PATH") ".") "/lua/launchables")
                                        path))})
  (local state (LeaderState))
  (states:add-state :subject state)
  (state.on-key-down {:key KEY_P})
  (assert (= (# transitions) 0) "Leader-P should not force a state transition")
  (assert panel-added? "Leader-P should open launcher")
  (set app.hud original-hud)
  (set app.engine original-engine)
  (set-app-states! original-states))

(fn camera-state-f-enters-fpc-state []
  (with-state-recorder
    (fn [transitions install-state]
      (local state (install-state :camera (CameraState)))
      (state.on-key-down {:key KEY_F})
      (assert (= (# transitions) 1) "F should move to fpc state")
      (assert (= (. transitions 1) :fpc)))))

(fn camera-state-escape-exits-to-normal []
  (with-state-recorder
    (fn [transitions install-state]
      (local state (install-state :camera (CameraState)))
      (state.on-key-down {:key KEY_ESCAPE})
      (assert (= (# transitions) 1) "Escape should move to normal state")
      (assert (= (. transitions 1) :normal)))))

(fn camera-state-zero-resets-camera []
  (local original-presentation-camera app.presentation-camera)
  (local original-camera app.camera)
  (var camera nil)
  (let [(ok err) (pcall (fn []
    (with-state-recorder
      (fn [transitions install-state]
        (set camera (Camera {:position (glm.vec3 1 2 3)
                             :rotation (glm.quat 0 1 0 0)}))
        (set app.camera camera)
        (set app.presentation-camera (fn [opts] camera))
        (local state (install-state :camera (CameraState)))
        (state.on-key-down {:key (string.byte "0")})
        (assert (= (# transitions) 0))
        (assert (= camera.position.x 0))
        (assert (= camera.position.y 0))
        (assert (= camera.position.z 0))
        (assert (= camera.rotation.w 1))
        (assert (= camera.rotation.x 0))
        (assert (= camera.rotation.y 0))
        (assert (= camera.rotation.z 0))
        (camera:drop)))))]
    (set app.camera original-camera)
    (set app.presentation-camera original-presentation-camera)
    (when (not ok)
      (when camera (camera:drop))
      (error err))))

(fn fpc-state-escape-exits-to-normal []
  (with-state-recorder
    (fn [transitions install-state]
      (local state (install-state :fpc (FpcState)))
      (state.on-key-down {:key KEY_ESCAPE})
      (assert (= (# transitions) 1) "Escape should move to normal state")
      (assert (= (. transitions 1) :normal)))))

(fn fpc-state-routes-input-only-to-controls []
  (reset-engine-events)
  (local calls {:input 0 :clickables 0 :hover 0 :movables 0})
  (local controls (create-controls-stub))
  (local original-states app.states)
  (local original-controls app.first-person-controls)
  (local original-presentation-controls app.presentation-input-controls)
  (local original-clickables (assert app.clickables "test requires app.clickables"))
  (local original-hoverables (assert app.hoverables "test requires app.hoverables"))
  (local original-movables app.movables)
  (local input {:on-key-down (fn [_self _payload]
                               (set calls.input (+ calls.input 1))
                               true)
                :on-mouse-button-down (fn [_self _payload]
                                        (set calls.input (+ calls.input 1))
                                        true)})
  (local states (States {:hud_provider command-hints-hud-provider}))
  (states:add-state :normal {})
  (states:set-state :normal)
  (set app.first-person-controls controls)
  (set app.presentation-input-controls (fn [] controls))
  (set app.clickables {:on-mouse-button-down (fn [_self _payload] (assert calls.clickables "test requires calls.clickables") (set calls.clickables (+ calls.clickables 1)))
                       :on-mouse-button-up (fn [_self _payload] (assert calls.clickables "test requires calls.clickables") (set calls.clickables (+ calls.clickables 1)))
                       :active? false})
  (set app.hoverables {:on-mouse-motion (fn [_self _payload]
                                           (set calls.hover (+ calls.hover 1)))
                        :on-enter (fn [] nil)
                        :on-leave (fn [] nil)})
  (set app.movables {:on-mouse-motion (fn [_self _payload]
                                         (set calls.movables (+ calls.movables 1)))
                      :drag-active? (fn [_self] false)})
  (local (ok err) (pcall (fn []
    (set-app-states! states)
    (InputState.connect-input input)
    (local state (FpcState))
    (states:add-state :fpc state)
    (state.on-enter)
    (app.engine.events.key-down.emit {:key 44})
    (app.engine.events.mouse-button-down.emit {:button 1 :x 0 :y 0})
    (app.engine.events.mouse-motion.emit {:x 5 :y 6})
    (assert (= calls.input 0) "InputState should not receive events in fpc state")
    (assert (= calls.clickables 0) "Clickables should not receive events in fpc state")
    (assert (= calls.hover 0) "Hoverables should not receive events in fpc state")
    (assert (= calls.movables 0) "Movables should not receive events in fpc state")
    (assert (= controls.record.key_down 44))
    (assert (= controls.record.mouse_button_down 1))
    (state.on-leave))))
  (InputState.disconnect-input input)
  (set-app-states! original-states)
  (set app.clickables original-clickables)
  (set app.hoverables original-hoverables)
  (set app.movables original-movables)
  (set app.first-person-controls original-controls)
  (set app.presentation-input-controls original-presentation-controls)
  (when (not ok) (error err)))

(fn leader-state-q-and-escape-transitions []
  (with-state-recorder
    (fn [transitions install-state]
      (local state (install-state :leader (LeaderState)))
      (state.on-key-down {:key KEY_Q})
      (state.on-key-down {:key KEY_ESCAPE})
      (assert (= (# transitions) 2))
      (assert (= (. transitions 1) :quit))
      (assert (= (. transitions 2) :normal))))
  )

(fn quit-state-quits-and-escapes []
  (local original-quit app.engine.quit)
  (var quit-calls 0)
  (set app.engine.quit (fn [] (set quit-calls (+ quit-calls 1))))
  (local (ok err)
         (pcall
           (fn []
             (with-state-recorder
               (fn [transitions install-state]
                 (local state (install-state :quit (QuitState)))
                 (state.on-key-down {:key KEY_Q})
                 (state.on-key-down {:key KEY_ESCAPE})
                 (assert (= quit-calls 1) "Quit state should invoke app.engine.quit on q")
                 (assert (= (# transitions) 1))
                 (assert (= (. transitions 1) :normal)))))))
  (set app.engine.quit original-quit)
  (when (not ok)
    (error err)))

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
               :deleted-before 0
               :deleted-at 0
               :moved-to nil
               :movement-log []
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
  (set stub.move-caret (fn [self delta]
                         (local moved (model:move-caret delta))
                         (table.insert self.movement-log delta)
                         (when moved
                           (sync))
                         moved))
  (set stub.move-caret-to (fn [self position]
                            (local moved (model:move-caret-to position))
                            (set self.moved-to position)
                            (when moved
                              (sync))
                            moved))
  (set stub.delete-before-cursor (fn [self]
                                    (local removed (model:delete-before-cursor))
                                    (when removed
                                      (set self.deleted-before (+ self.deleted-before 1))
                                      (sync))
                                    removed))
  (set stub.delete-at-cursor (fn [self]
                                (local removed (model:delete-at-cursor))
                                (when removed
                                  (set self.deleted-at (+ self.deleted-at 1))
                                  (sync))
                                removed))
  (set stub.insert-text (fn [self text]
                          (when text
                            (table.insert self.inserted text)
                            (model:insert-text text)
                            (sync))
                          true))
  (set stub.on-text-input (fn [self payload]
                            (when (and payload payload.text)
                              (self:insert-text payload.text))
                            true))
  (model:move-caret-to initial-cursor)
  (sync)
  stub)

(fn text-state-handles-navigation []
  (with-state-recorder
    (fn [transitions install-state]
      (local input (make-input-stub {:text "abc"}))
      (InputState.connect-input input)
      (local state (install-state :text (TextState)))
      (state.on-key-down {:key (string.byte "i")})
      (Runtime.dispatch-text-input nil)
      (assert (= (. transitions 1) :insert))
      (assert (= input.mode :insert))
      (state.on-key-down {:key (string.byte "h")})
      (state.on-key-down {:key (string.byte "l")})
      (state.on-key-down {:key (string.byte "4") :mod SHIFT-MOD})
      (assert (= input.model.cursor-column 2))
      (state.on-key-down {:key (string.byte "0")})
      (state.on-key-down {:key (string.byte "x")})
      (assert (= input.deleted-at 1))
      (assert (= input.moved-to 0))
      (InputState.disconnect-input input))))

(fn text-state-horizontal-stays-on-line []
  (with-state-recorder
    (fn [_transitions install-state]
      (local input (make-input-stub {:text "alpha\nbeta" :multiline? true}))
      (InputState.connect-input input)
      (input:move-caret-to 5)
      (local state (install-state :text (TextState)))
      (state.on-key-down {:key (string.byte "l")})
      (assert (= input.model.cursor-line 0))
      (assert (= input.model.cursor-column 4))
      (input:move-caret-to 6)
      (state.on-key-down {:key (string.byte "h")})
      (assert (= input.model.cursor-line 1))
      (assert (= input.model.cursor-column 0))
      (InputState.disconnect-input input))))

(fn text-state-supports-vertical-navigation []
  (with-state-recorder
    (fn [_transitions install-state]
      (local input (make-input-stub {:text "car\ntruck\nplane" :multiline? true}))
      (InputState.connect-input input)
      (input:move-caret-to 2)
      (local state (install-state :text (TextState)))
      (state.on-key-down {:key (string.byte "j")})
      (assert (= input.model.cursor-line 1))
      (assert (= input.model.cursor-column 2))
      (state.on-key-down {:key (string.byte "k")})
      (assert (= input.model.cursor-line 0))
      (InputState.disconnect-input input))))

(fn text-state-open-line-commands []
  (with-state-recorder
    (fn [_transitions install-state]
      (local state (install-state :text (TextState)))
      (local below (make-input-stub {:text "foo\nbar" :multiline? true}))
      (InputState.connect-input below)
      (state.on-key-down {:key (string.byte "o")})
      (Runtime.dispatch-text-input nil)
      (assert (= below.mode :insert))
      (assert (= (below.model:get-text) "foo\n\nbar"))
      (InputState.disconnect-input below)

      (local above (make-input-stub {:text "foo\nbar\nbaz" :multiline? true}))
      (InputState.connect-input above)
      (above:move-caret-to 4)
      (state.on-key-down {:key (string.byte "o") :mod SHIFT-MOD})
      (Runtime.dispatch-text-input nil)
      (assert (= (above.model:get-text) "foo\n\nbar\nbaz"))
      (assert (= above.mode :insert))
      (assert (= above.model.cursor-line 1))
      (InputState.disconnect-input above))))

(fn text-state-line-jumps []
  (with-state-recorder
    (fn [_transitions install-state]
      (local input (make-input-stub {:text "one\ntwo\nthree" :multiline? true}))
      (InputState.connect-input input)
      (input:move-caret-to 4)
      (local state (install-state :text (TextState)))
      (state.on-key-down {:key (string.byte "g")})
      (state.on-key-down {:key (string.byte "g")})
      (assert (= input.model.cursor-line 0))
      (input:move-caret-to 2)
      (state.on-key-down {:key (string.byte "g") :mod SHIFT-MOD})
      (assert (= input.model.cursor-line 2))
      (assert (= input.model.cursor-column 2))
      (InputState.disconnect-input input))))

(fn text-state-linewise-insert-shortcuts []
  (with-state-recorder
    (fn [_transitions install-state]
      (local state (install-state :text (TextState)))
      (local input (make-input-stub {:text "  foo" :multiline? true}))
      (InputState.connect-input input)
      (state.on-key-down {:key (string.byte "i") :mod SHIFT-MOD})
      (Runtime.dispatch-text-input nil)
      (assert (= input.mode :insert))
      (assert (= input.model.cursor-column 2))
      (InputState.disconnect-input input)

      (local append (make-input-stub {:text "bar" :multiline? true}))
      (InputState.connect-input append)
      (state.on-key-down {:key (string.byte "a") :mod SHIFT-MOD})
      (Runtime.dispatch-text-input nil)
      (assert (= append.mode :insert))
      (assert (= append.model.cursor-column 3))
      (InputState.disconnect-input append))))

(fn text-state-clamps-before-delete []
  (with-state-recorder
    (fn [_transitions install-state]
      (local state (install-state :text (TextState)))
      (local input (make-input-stub {:text "abc"}))
      (InputState.connect-input input)
      (input:move-caret-to 3)
      (state.on-key-down {:key (string.byte "x")})
      (assert (= input.deleted-at 1))
      (assert (= input.model.cursor-column 1))
      (InputState.disconnect-input input))))

(fn text-state-ignores-text-input-when-entering-insert []
  (with-state-recorder
    (fn [_transitions install-state]
      (local input (make-input-stub))
      (InputState.connect-input input)
      (local text-state (install-state :text (TextState)))
      (local insert-state (install-state :insert (InsertState)))
      (text-state.on-key-down {:key (string.byte "i")})
      (insert-state.on-text-input {:text "i"})
      (insert-state.on-text-input {:text "a"})
      (local inserted-count (# input.inserted))
      (assert (= inserted-count 1)
              (.. "expected 1 inserted value, got " inserted-count))
      (local first-insert (. input.inserted 1))
      (assert (= first-insert "a")
              (.. "expected 'a' as first insert but saw " (tostring first-insert)))
      (InputState.disconnect-input input))))

(fn text-state-swallows-unhandled-keys-when-input-active []
  (with-state-recorder
    (fn [_transitions install-state]
      (local controls (create-controls-stub))
      (set app.first-person-controls controls)
      (local input (make-input-stub {:text "abc"}))
      (InputState.connect-input input)
      (local state (install-state :text (TextState)))
      (state.on-key-down {:key (string.byte "z")})
      (assert (= controls.record.key_down nil)
              "Unhandled text keys should not reach controls when input is active")
      (InputState.disconnect-input input)
      (set app.first-person-controls nil))))

(fn insert-state-handles-editing []
  (with-state-recorder
    (fn [transitions install-state]
      (local input (make-input-stub {:text "abcd"}))
      (input:move-caret-to 2)
      (InputState.connect-input input)
      (local state (install-state :insert (InsertState)))
      (state.on-key-down {:key 27})
      (assert (= (. transitions 1) :text))
      (assert (= input.mode :normal))
      (assert (= input.cursor-index 1))
      (state.on-key-down {:key 8})
      (assert (= input.deleted-before 1))
      (state.on-key-down {:key 127})
      (assert (= input.deleted-at 1))
      (state.on-key-down {:key 1073741904})
      (state.on-key-down {:key 1073741903})
      (assert (= (# input.movement-log) 3))
      (InputState.disconnect-input input))))

(fn insert-state-inserts-newline-when-multiline []
  (with-state-recorder
    (fn [transitions install-state]
      (local input (make-input-stub {:multiline? true}))
      (InputState.connect-input input)
      (input:enter-insert-mode)
      (local state (install-state :insert (InsertState)))
      (state.on-key-down {:key 13})
      (assert (= input.mode :insert))
      (assert (= (. input.inserted 1) "\n"))
      (assert (= (# transitions) 0))
      (InputState.disconnect-input input))))

(table.insert tests {:name "Normal state leader key enters leader state" :fn normal-state-leader-enters-leader-state})
(table.insert tests {:name "Leader state C enters camera state" :fn leader-state-c-enters-camera-state})
(table.insert tests {:name "Leader state P opens launcher" :fn leader-state-p-opens-launcher})
(table.insert tests {:name "Camera state F enters fpc state" :fn camera-state-f-enters-fpc-state})
(table.insert tests {:name "Camera state escape exits to normal" :fn camera-state-escape-exits-to-normal})
(table.insert tests {:name "Camera state 0 resets camera transform" :fn camera-state-zero-resets-camera})
(table.insert tests {:name "Fpc state escape exits to normal" :fn fpc-state-escape-exits-to-normal})
(table.insert tests {:name "Fpc state routes input only to controls" :fn fpc-state-routes-input-only-to-controls})
(table.insert tests {:name "Fpc state injects single touch as mouse" :fn fpc-state-injects-single-touch-as-mouse})
(table.insert tests {:name "Fpc state injects pen as mouse" :fn fpc-state-injects-pen-as-mouse})
(table.insert tests {:name "Leader state routes to quit or normal" :fn leader-state-q-and-escape-transitions})
(table.insert tests {:name "Quit state quits and escapes to normal" :fn quit-state-quits-and-escapes})
(table.insert tests {:name "Text state handles navigation commands" :fn text-state-handles-navigation})
(table.insert tests {:name "Text state horizontal movement stays within a line" :fn text-state-horizontal-stays-on-line})
(table.insert tests {:name "Text state supports vertical navigation" :fn text-state-supports-vertical-navigation})
(table.insert tests {:name "Text state open line commands insert correctly" :fn text-state-open-line-commands})
(table.insert tests {:name "Text state handles gg and G line jumps" :fn text-state-line-jumps})
(table.insert tests {:name "Text state linewise insert shortcuts" :fn text-state-linewise-insert-shortcuts})
(table.insert tests {:name "Text state clamps cursor before deletes" :fn text-state-clamps-before-delete})
(table.insert tests {:name "Text state ignores text input when entering insert" :fn text-state-ignores-text-input-when-entering-insert})
(table.insert tests {:name "Text state swallows unhandled keys when input is active" :fn text-state-swallows-unhandled-keys-when-input-active})
(table.insert tests {:name "Insert state handles editing commands" :fn insert-state-handles-editing})
(table.insert tests {:name "Insert state inserts newline for multiline input" :fn insert-state-inserts-newline-when-multiline})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "states"
                       :tests tests})))

{:name "states"
 :tests tests
 :main main}
