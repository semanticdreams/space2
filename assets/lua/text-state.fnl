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
(local Runtime (require :state-runtime))
(local InputState (require :input-state-router))
(local TextNormalCommands (require :text-normal-commands))
(local {: entry : section : KEY_F1} (require :command-hints))

(local SDLK_RETURN 13)

(fn active-input []
  (and InputState InputState.active-input (InputState.active-input)))

(fn mark-command [ctx]
  ((. ctx :mark-command-executed!)))

(fn handle-submit [ctx payload]
  (local input (active-input))
  (if (not input)
      false
      (if (and payload
               (= payload.key SDLK_RETURN)
               (Runtime.ctrl-held? payload))
          (do
            (input:submit payload)
            (mark-command ctx)
            true)
          false)))

(fn handle-text-key [ctx state payload]
  (local input (active-input))
  (if input
      (TextNormalCommands.handle-key ctx state.command-state input payload)
      false))

(fn on-key-down [ctx state payload]
  (local controls (and app.presentation-input-controls
                        (app.presentation-input-controls)))
  (if (handle-submit ctx payload)
      true
      (handle-text-key ctx state payload)
      true
      (InputState.dispatch-input :on-key-down payload)
      (do
        (mark-command ctx)
        true)
      (Runtime.handle-focus-tab ctx payload)
      (do
        (mark-command ctx)
        true)
      (and (active-input)
           (not (= (and payload payload.key) KEY_F1)))
      true
      controls
      (do
        (local handled (controls:on-key-down payload))
        (when handled
          (mark-command ctx))
        handled)
      false))

(fn sync-mode []
  (TextNormalCommands.sync-mode (active-input)))

(fn command-hint-entries [state payload]
  (local (entries prefix-meta) (TextNormalCommands.command-hint-entries state.command-state payload))
  (local focus-manager (and payload payload.focus-manager))
  (when (not prefix-meta)
    (table.insert entries (entry "ctrl+enter" "submit" {:priority 16 :show-collapsed? false}))
    (when focus-manager
      (table.insert entries (entry "tab" "focus-next" {:priority 60 :show-collapsed? false}))))
  (values entries prefix-meta))

(fn text-command-hints-provider [state payload]
  (local (entries prefix-meta) (command-hint-entries state payload))
  (if (> (length entries) 0)
      [(section :mode
                (if (and prefix-meta prefix-meta.title)
                    (.. "MODE " prefix-meta.title)
                    "MODE")
                entries)]
      []))

(fn TextState []
  (var state nil)
  (local PenHandlers (PenPointer.PenPointerHandlers {}))
  (fn on-text-lifecycle-enter [_ctx]
    (when (and state state.command-state)
      (set state.command-state.pending-keymap nil))
    (sync-mode))
  (fn on-text-command-key-down [ctx payload]
    (not (not (on-key-down ctx state payload))))
  (fn on-text-command-hints [_self payload]
    (text-command-hints-provider state payload))
  (local TextLifecycle
    {:enter on-text-lifecycle-enter})
  (local TextCommands
    {:key-down on-text-command-key-down})
  (set state
       (State
        {:name :text
         :route-wrappers [Routes.CommandHints]
         :command_hints_provider on-text-command-hints
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
                  :key-down (Routes.FirstHandlerWins [TextCommands])
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
         :enter [PenHandlers.PenLifecycle
                 TouchHandlers.TouchLifecycle
                 HoverHandlers.HoverLifecycle
                 TextLifecycle]
         :leave [PenHandlers.PenLifecycle
                 TouchHandlers.TouchLifecycle
                 HoverHandlers.HoverLifecycle]}))
  (set state.command-state (TextNormalCommands.make-state))
  state)

TextState
