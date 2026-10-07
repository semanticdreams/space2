(local _ (require :main))
(local States (require :states))
(local LeaderState (require :leader-state))
(local StateSystemBindings (require :state-system-bindings))

(local tests [])

(local KEY_C (string.byte "c"))
(local KEY_F (string.byte "f"))
(local KEY_G (string.byte "g"))
(local KEY_N (string.byte "n"))
(local KEY_Z (string.byte "z"))
(local KEY_F1 1073741882)

(fn make-command-hints-stub []
  {:handle-toggle-key (fn [_self _payload] true)
   :close-on-handled-event (fn [_self _route-key _payload] false)})

(fn command-hints-hud-provider [_self]
  {:command-hints (make-command-hints-stub)})

(fn focus-manager-provider [_self]
  app.focus)

(fn set-app-states! [states]
  (StateSystemBindings.bind-states-host states)
  (set app.states states)
  states)

(fn make-recording-set-state [states transitions original-set-state]
  (fn [_self name]
    (when (not (states:get-state name))
      (states:add-state name {}))
    (table.insert transitions name)
    (original-set-state states name)))

(fn install-state [states name state]
  (states:add-state name state)
  state)

(fn with-state-recorder [body]
  (local original app.states)
  (local transitions [])
  (local states
    (States {:hud_provider command-hints-hud-provider
             :focus_manager_provider focus-manager-provider}))
  (local original-set-state states.set-state)
  (set states.set-state (make-recording-set-state states transitions original-set-state))
  (set-app-states! states)
  (local (ok result) (pcall body transitions states))
  (set-app-states! original)
  (if ok
      result
      (error result)))

(fn assert-unknown-key-stays-in-leader [transitions states]
  (local state (install-state states :leader (LeaderState)))
  (local handled (state.on-key-down {:key KEY_Z}))
  (assert (not handled) "Unknown leader key should remain available to route wrappers")
  (assert (= (# transitions) 0)
          "Unknown leader key should not leave leader state"))

(fn assert-f1-stays-in-leader [transitions states]
  (local state (install-state states :leader (LeaderState)))
  (local handled (state.on-key-down {:key KEY_F1}))
  (assert handled "F1 should remain available for command hints after leader misses")
  (assert (= (# transitions) 0)
          "F1 in leader state should not transition to normal"))

(fn leader-state-unknown-key-stays-in-leader []
  (with-state-recorder assert-unknown-key-stays-in-leader))

(fn leader-state-f1-stays-in-leader []
  (with-state-recorder assert-f1-stays-in-leader))

(fn nested-demo-run [_ctx]
  true)

(local nested-miss-leader-provider
  {:commands {"demo.nested" {:id "demo.nested" :label "nested-demo" :run nested-demo-run}}
   :prefixes [{:keys ["g"] :label "graph" :priority 10}]
   :bindings [{:keys ["g" "p"] :command "demo.nested" :label "nested-demo" :priority 10}]})

(fn assert-root-command-after-nested-leader-miss [transitions states]
  (local state (install-state states :leader (LeaderState)))
  (state.on-key-down {:key KEY_G})
  (assert (= (# transitions) 0) "Prefix should stay in leader")
  (local handled (state.on-key-down {:key KEY_Z}))
  (assert (not handled) "Unknown nested leader key should not be handled")
  (assert (= (# transitions) 0)
          "Unknown nested leader key should not leave leader state")
  (state.on-key-down {:key KEY_C})
  (assert (= (# transitions) 1)
          "Valid root command after nested miss should use cleared sequence")
  (assert (= (. transitions 1) :camera)
          "Valid root command after nested miss should run normally"))

(fn run-nested-leader-miss-scenario []
  (with-state-recorder assert-root-command-after-nested-leader-miss))

(fn leader-state-unknown-nested-key-clears-sequence []
  (local original app.activity-leader-command-providers)
  (set app.activity-leader-command-providers [nested-miss-leader-provider])
  (local (ok err) (pcall run-nested-leader-miss-scenario))
  (set app.activity-leader-command-providers original)
  (when (not ok)
    (error err)))

(fn make-recording-focus-manager []
  (local calls {:next []})
  {:calls calls
   :can-focus-into? (fn [_self] false)
   :can-focus-out? (fn [_self] false)
   :focus-next (fn [_self opts]
                 (table.insert calls.next opts)
                 true)
   :focus-direction (fn [_self _opts] true)})

(fn assert-focus-next-leader-command [transitions states]
  (local original-focus app.focus)
  (local manager (make-recording-focus-manager))
  (set app.focus manager)
  (local (ok err)
    (pcall
      (fn []
        (local state (install-state states :leader (LeaderState)))
        (local handled-prefix (state.on-key-down {:key KEY_F}))
        (assert handled-prefix "Space f should enter the one-shot focus prefix")
        (assert (= (# manager.calls.next) 0)
                "Space f prefix should not run focus-next yet")
        (assert (= (# transitions) 0)
                "Space f prefix should stay in leader state")
        (local handled-command (state.on-key-down {:key KEY_N}))
        (assert handled-command "Space f n should run focus.next")
        (assert (= (# manager.calls.next) 1)
                "Space f n should call focus-next once")
        (assert (not (. manager.calls.next 1 :backwards?))
                "Space f n should call forward focus-next")
        (assert (= (. transitions 1) :normal)
                "Space f n should return to normal through one-shot command handling"))))
  (set app.focus original-focus)
  (when (not ok)
    (error err)))

(fn leader-state-runs-focus-next-one-shot []
  (with-state-recorder assert-focus-next-leader-command))

(table.insert tests {:name "Leader state unknown key stays in leader"
                     :fn leader-state-unknown-key-stays-in-leader})
(table.insert tests {:name "Leader state F1 stays in leader"
                     :fn leader-state-f1-stays-in-leader})
(table.insert tests {:name "Leader state unknown nested key clears sequence"
                      :fn leader-state-unknown-nested-key-clears-sequence})
(table.insert tests {:name "Leader state runs Space f n as one-shot focus command"
                     :fn leader-state-runs-focus-next-one-shot})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "leader-state"
                       :tests tests})))

{:name "leader-state"
 :tests tests
 :main main}
