(local State (require :state))
(local Routes (require :state-routes))
(local TouchHandlers (require :state-handlers/touch-pointer))
(local PenPointer (require :state-handlers/pen-pointer))
(local {: entry : section : key-label} (require :command-hints))

(local KEY_ESCAPE 27)

(fn require-controls [action]
  (let [controls (and app.presentation-input-controls
                      (app.presentation-input-controls))]
    (assert controls
            (.. "FpcState requires presentation input controls for " action))
    controls))

(fn dispatch-control [action method payload]
  (local controls (require-controls action))
  (local handler (. controls method))
  (assert handler
          (.. "FpcState first-person-controls missing handler for " action))
  (handler controls payload))

(fn command-hints-keymap []
  (local controls (require-controls "command hints"))
  controls.key-mapping)

(fn control-entry [keymap action label priority opts]
  (local key (assert (. keymap action)
                      (.. "FpcState command hints missing key mapping for " (tostring action))))
  (local options (or opts {}))
  (entry (key-label key)
         label
         {:priority priority
          :show-collapsed? (if (= options.show-collapsed? nil)
                               true
                               options.show-collapsed?)}))

(fn FpcState []
  (local PenHandlers (PenPointer.PenPointerHandlers {}))
  (fn append-entry! [entries hint]
    (when hint
      (table.insert entries hint)))
  (fn mark-command [ctx handled]
    (when handled
      ((. ctx :mark-command-executed!)))
    handled)
  (fn fpc-command-sections []
    (local keymap (command-hints-keymap))
    (if keymap
        (do
          (local entries [(entry "esc" "normal-mode" {:priority 10})])
          (append-entry! entries (control-entry keymap :move-forward "move-forward" 20))
          (append-entry! entries (control-entry keymap :move-left "move-left" 21))
          (append-entry! entries (control-entry keymap :move-backward "move-backward" 22))
          (append-entry! entries (control-entry keymap :move-right "move-right" 23))
          (append-entry! entries (control-entry keymap :look-up "look-up" 30 {:show-collapsed? false}))
          (append-entry! entries (control-entry keymap :look-down "look-down" 31 {:show-collapsed? false}))
          (append-entry! entries (control-entry keymap :look-left "look-left" 32 {:show-collapsed? false}))
          (append-entry! entries (control-entry keymap :look-right "look-right" 33 {:show-collapsed? false}))
          (append-entry! entries (control-entry keymap :speed "speed-boost" 40))
          [(section :mode "MODE" entries)])
        []))

  (local ControlsOnly
    {:text-input (fn [_ctx _payload] false)
     :key-down (fn [ctx payload]
                 (if (= (and payload payload.key) KEY_ESCAPE)
                     (do
                       ((. ctx :mark-command-executed!))
                       ((. ctx :set-state) :normal)
                       true)
                     (mark-command ctx (dispatch-control :key-down :on-key-down payload))))
     :key-up (fn [_ctx payload]
               (dispatch-control :key-up :on-key-up payload))
     :mouse-button-up (fn [ctx payload]
                        (mark-command ctx (dispatch-control :mouse-button-up :on-mouse-button-up payload)))
     :mouse-button-down (fn [ctx payload]
                          (mark-command ctx (dispatch-control :mouse-button-down :on-mouse-button-down payload)))
     :mouse-motion (fn [_ctx payload]
                     (dispatch-control :mouse-motion :on-mouse-motion payload))
     :mouse-wheel (fn [ctx payload]
                    (mark-command ctx (dispatch-control :mouse-wheel :on-mouse-wheel payload)))
     :gamepad-button-down (fn [ctx payload]
                            (mark-command ctx (dispatch-control :gamepad-button-down :on-gamepad-button-down payload)))
     :gamepad-axis-motion (fn [_ctx payload]
                            (dispatch-control :gamepad-axis-motion :on-gamepad-axis-motion payload))
     :gamepad-removed (fn [_ctx payload]
                        (dispatch-control :gamepad-removed :on-gamepad-removed payload))
     :updated (fn [_ctx delta]
                (dispatch-control :updated :update delta))})

  (local state
    (State
      {:name :fpc
       :route-wrappers [Routes.CommandHints]
       :command_hints_provider (fn [_ctx]
                                 (fpc-command-sections))
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
                :text-input (Routes.FirstHandlerWins [ControlsOnly])
                :key-down (Routes.FirstHandlerWins [ControlsOnly])
                :key-up (Routes.FirstHandlerWins [ControlsOnly])
                :mouse-button-up (Routes.FirstHandlerWins [ControlsOnly])
                :mouse-button-down (Routes.FirstHandlerWins [ControlsOnly])
                :mouse-motion (Routes.FirstHandlerWins [ControlsOnly])
                :mouse-wheel (Routes.FirstHandlerWins [ControlsOnly])
                :gamepad-button-down (Routes.FirstHandlerWins [ControlsOnly])
                :gamepad-axis-motion (Routes.FirstHandlerWins [ControlsOnly])
                :gamepad-removed (Routes.FirstHandlerWins [ControlsOnly])
                :updated (Routes.FirstHandlerWins [ControlsOnly])}
       :enter [PenHandlers.PenLifecycle
               TouchHandlers.TouchLifecycle]
       :leave [PenHandlers.PenLifecycle
               TouchHandlers.TouchLifecycle]}))
  state)

FpcState
