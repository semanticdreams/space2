(global app (or app {}))

(local FpcState (require :fpc-state))

(local tests [])

(fn fpc-command-hints-withhold-when-presentation-controls-are-canvas []
  (local original-presentation-controls app.presentation-input-controls)
  (local canvas-controls {:on-mouse-button-down (fn [_self _payload] true)
                         :on-mouse-button-up (fn [_self _payload] true)
                         :on-mouse-motion (fn [_self _payload] true)
                         :drag-active? (fn [_self] false)})
  (set app.presentation-input-controls (fn [] canvas-controls))
  (local (ok result-or-err)
    (pcall
      (fn []
        (local state (FpcState))
        (state.command_hints_provider state {}))))
  (set app.presentation-input-controls original-presentation-controls)
  (when (not ok)
    (error result-or-err))
  (assert (= (# result-or-err) 0)
          "FPC command hints should be withheld for canvas presentation controls"))

(table.insert tests {:name "FPC command hints withhold when presentation controls are canvas"
                     :fn fpc-command-hints-withhold-when-presentation-controls-are-canvas})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "fpc-command-hints"
                       :tests tests})))

{:name "fpc-command-hints"
 :tests tests
 :main main}
