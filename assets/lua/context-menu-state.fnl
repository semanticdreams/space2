(local State (require :state))
(local Routes (require :state-routes))
(local HoverHandlers (require :state-handlers/hover))
(local PointerHandlers (require :state-handlers/pointer))
(local {: entry : section} (require :command-hints))

(fn context-menu-manager []
  (assert app.menu-manager
          "ContextMenuState requires app.menu-manager"))

(local ContextMenuCommands
  {:key-down
   (fn [ctx payload]
     (local manager (context-menu-manager))
     (assert manager.handle-key-down
             "ContextMenuState requires menu-manager:handle-key-down")
      (local handled (manager:handle-key-down payload))
      (when handled
        ((. ctx :mark-event-consumed!)))
      handled)})

(fn context-menu-command-hints [_self _payload]
  (local manager (context-menu-manager))
  (assert manager.active-action-hints
          "ContextMenuState requires menu-manager:active-action-hints")
  (local entries [])
  (each [_ hint (ipairs (manager:active-action-hints))]
    (table.insert entries (entry hint.key hint.label {:priority 10})))
  (table.insert entries (entry "esc" "close" {:priority 90}))
  [(section :context "MENU" entries)])

(fn ContextMenuState []
  (State
    {:name :context-menu
     :route-wrappers [Routes.CommandHints]
     :command_hints_provider context-menu-command-hints
     :routes {:key-down (Routes.FirstHandlerWins [ContextMenuCommands])
               :mouse-button-down (Routes.Chain [PointerHandlers.InputMouseButtonDownDispatch
                                                 PointerHandlers.ResizableMouseButtonDown
                                                 PointerHandlers.ClickableMouseButtonDown
                                                 PointerHandlers.MovableMouseButtonDown])
              :mouse-button-up (Routes.Chain [PointerHandlers.InputMouseButtonUpDispatch
                                              PointerHandlers.ResizableMouseButtonUp
                                              PointerHandlers.ClickableMouseButtonUp
                                              PointerHandlers.MovableMouseButtonUp
                                              HoverHandlers.HoverAfterMouseButtonUp])
              :mouse-motion (Routes.Chain [PointerHandlers.InputMouseMotionDispatch
                                           PointerHandlers.MovableMouseMotion
                                           PointerHandlers.ResizableMouseMotion
                                           HoverHandlers.HoverMouseMotion])
              :mouse-wheel (Routes.FirstHandlerWins [PointerHandlers.InputMouseWheelDispatch
                                                    PointerHandlers.HoveredMouseWheel])
              :updated (Routes.Chain [HoverHandlers.HoverUpdated])}
     :enter [HoverHandlers.HoverLifecycle]
     :leave [HoverHandlers.HoverLifecycle]}))

ContextMenuState
