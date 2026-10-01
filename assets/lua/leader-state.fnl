(local State (require :state))
(local Routes (require :state-routes))
(local HoverHandlers (require :state-handlers/hover))
(local TextInputHandlers (require :state-handlers/text-input))
(local FocusHandlers (require :state-handlers/focus))
(local PointerHandlers (require :state-handlers/pointer))
(local TouchHandlers (require :state-handlers/touch-pointer))
(local PenPointer (require :state-handlers/pen-pointer))
(local GamepadHandlers (require :state-handlers/gamepad))
(local CameraHandlers (require :state-handlers/camera))
(local Commands (require :commands/core))
(local Keymap (require :commands/keymap))
(local CoreLeader (require :commands/providers/core-leader))

(local KEY
  {:escape 27})

(fn list-or-empty [items]
  (if (= items nil) [] items))

(fn active-providers []
  (local providers [(CoreLeader.provider)])
  (each [_ provider (ipairs (list-or-empty app.activity-leader-command-providers))]
    (table.insert providers provider))
  providers)

(fn compose-active [ctx]
  (Commands.compose (active-providers) ctx))

(fn core-command? [command-id]
  (and (= (type command-id) :string)
       (= (string.sub command-id 1 5) "core.")))

(fn exit-leader [ctx reset-sequence! result]
  (reset-sequence!)
  ((. ctx :set-state) :normal)
  result)

(fn handle-resolved-command [ctx resolved composed reset-sequence!]
  (local available? (Commands.available? composed resolved.command-id ctx))
  (when available?
    (Commands.run composed resolved.command-id ctx)
    ((. ctx :mark-command-executed!)))
  (reset-sequence!)
  (when (not (core-command? resolved.command-id))
    ((. ctx :set-state) :normal))
  true)

(fn handle-resolved-sequence [ctx resolved composed reset-sequence!]
  (if (= resolved.kind :prefix)
      (do
        ((. ctx :mark-command-executed!))
        true)
      (= resolved.kind :command)
      (handle-resolved-command ctx resolved composed reset-sequence!)
      (exit-leader ctx reset-sequence! false)))

(fn LeaderState []
  (local PenHandlers (PenPointer.PenPointerHandlers {}))
  (var sequence [])
  (fn reset-sequence! []
    (set sequence []))
  (local LeaderCommands
    {:key-down (fn [ctx payload]
                 (local key (and payload payload.key))
                 (if (= key KEY.escape)
                     (do
                       (reset-sequence!)
                       ((. ctx :mark-command-executed!))
                       ((. ctx :set-state) :normal)
                       true)
                     (do
                       (local token (Keymap.key-token payload))
                       (local composed (compose-active ctx))
                       (table.insert sequence token)
                       (local resolved (Keymap.resolve composed.tree sequence))
                       (handle-resolved-sequence ctx resolved composed reset-sequence!))))})
  (fn leader-hints-provider [self _payload]
    (local ctx (assert (and self self.ctx) "LeaderState command hints require state ctx"))
    (local composed (compose-active ctx))
    (local section (Commands.hint-section composed sequence ctx {:id :mode :title "MODE"}))
    (if section [section] []))
  (local LeaderLifecycle
    {:enter (fn [_ctx]
              (reset-sequence!))})
  (local state
    (State
      {:name :leader
       :route-wrappers [Routes.CommandHints]
       :command_hints_provider leader-hints-provider
       :routes {:touch-down (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseDown])
                :touch-motion (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseMotion])
                :touch-up (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseUp])
                :touch-canceled (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseCanceled])
                :pen-proximity-in (Routes.Chain [PenHandlers.PenProximityIn])
                :pen-proximity-out (Routes.Chain [PenHandlers.PenProximityOut])
                :pen-motion (Routes.Chain [PenHandlers.PenMotion])
                :pen-down (Routes.Chain [PenHandlers.PenDown])
                :pen-up (Routes.Chain [PenHandlers.PenUp])
                :pen-button-down (Routes.Chain [PenHandlers.PenButtonDown])
                :pen-button-up (Routes.Chain [PenHandlers.PenButtonUp])
                :pen-axis (Routes.Chain [PenHandlers.PenAxis])
                :text-input (Routes.FirstHandlerWins [TextInputHandlers.TextInputDispatch])
                :text-editing (Routes.FirstHandlerWins [TextInputHandlers.TextEditingDispatch])
                :key-down (Routes.FirstHandlerWins [LeaderCommands])
                :key-up (Routes.FirstHandlerWins [FocusHandlers.InputKeyUpDispatch
                                                 FocusHandlers.ActiveInputKeyBlock])
                :mouse-button-down (Routes.Chain [PointerHandlers.InputMouseButtonDownDispatch
                                                  PointerHandlers.ResizableMouseButtonDown
                                                  PointerHandlers.ClickableMouseButtonDown
                                                  PointerHandlers.MovableMouseButtonDown
                                                  PointerHandlers.SelectionMouseButtonDown
                                                  PointerHandlers.CameraMouseButtonDown])
                :mouse-button-up (Routes.Chain [PointerHandlers.InputMouseButtonUpDispatch
                                                PointerHandlers.ResizableMouseButtonUp
                                                PointerHandlers.ClickableMouseButtonUp
                                                PointerHandlers.MovableMouseButtonUp
                                                PointerHandlers.SelectionMouseButtonUp
                                                PointerHandlers.CameraMouseButtonUp
                                                HoverHandlers.HoverAfterMouseButtonUp])
                :mouse-motion (Routes.Chain [PointerHandlers.InputMouseMotionDispatch
                                             PointerHandlers.MovableMouseMotion
                                             PointerHandlers.ResizableMouseMotion
                                             PointerHandlers.CameraDragMouseMotion
                                             PointerHandlers.SelectionMouseMotion
                                             PointerHandlers.CameraMouseMotion
                                             HoverHandlers.HoverMouseMotion])
                :mouse-wheel (Routes.FirstHandlerWins [PointerHandlers.InputMouseWheelDispatch
                                                      PointerHandlers.HoveredMouseWheel
                                                      PointerHandlers.CameraMouseWheel])
                :gamepad-button-down (Routes.FirstHandlerWins [GamepadHandlers.GamepadButtonDown])
                :gamepad-axis-motion (Routes.FirstHandlerWins [GamepadHandlers.GamepadAxisMotion])
                :gamepad-removed (Routes.FirstHandlerWins [GamepadHandlers.GamepadRemoved])
                :updated (Routes.Chain [CameraHandlers.CameraUpdated
                                        HoverHandlers.HoverUpdated])}
       :enter [LeaderLifecycle
               PenHandlers.PenLifecycle
               TouchHandlers.TouchLifecycle
               HoverHandlers.HoverLifecycle]
       :leave [PenHandlers.PenLifecycle
               TouchHandlers.TouchLifecycle
               HoverHandlers.HoverLifecycle]}))
  state)

LeaderState
