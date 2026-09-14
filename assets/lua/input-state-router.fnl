(var active-input nil)
(local StateSystemRuntime (require :state-system-runtime))

(fn states-host [action]
  (StateSystemRuntime.states-host "InputStateRouter" action))

(fn set-states-provider [provider]
  (StateSystemRuntime.set-states-provider provider))

(fn set-state [name]
  (local states (states-host "state transitions"))
  (assert (and states states.set-state)
          "InputStateRouter requires a states host for state transitions")
  (states:set-state name))

(fn set-text-input-enabled [enabled?]
  (when (and app.engine app.engine.set-text-input-enabled)
    (app.engine.set-text-input-enabled enabled?)))

(fn current-state-name []
  (local states (states-host "current-state-name"))
  (assert states.active-name
          "InputStateRouter states host must expose :active-name")
  (states:active-name))

(fn states-host-available? []
  (not (not (StateSystemRuntime.maybe-states-host))))

(fn release-active-input []
  (when active-input
    (local state-name (current-state-name))
    (local handler active-input.on-state-disconnected)
    (when handler
      (active-input:on-state-disconnected {:state state-name}))
    (set active-input nil)
    (set-text-input-enabled false)
    (when (if (= state-name :text)
              true
              (= state-name :insert)
              true
              false)
      (set-state :normal))))

(fn connect-input [input]
  (when (not (= input active-input))
    (release-active-input)
    (when input
      (set active-input input)
      (set-text-input-enabled true)
      (local handler input.on-state-connected)
      (when handler
        (input:on-state-connected {:state (current-state-name)}))))
  active-input)

(fn disconnect-input [input]
  (when (and active-input (= input active-input))
    (release-active-input))
  active-input)

(fn clear-active-input-for-teardown [input]
  (when (and active-input (= input active-input))
    (set active-input nil)
    (set-text-input-enabled false)
    true))

(fn reset []
  (set active-input nil)
  (set-text-input-enabled false)
  nil)

(fn dispatch-input [method payload]
  (local current active-input)
  (if (and current method (. current method))
      ((. current method) current payload)
      false))

{:connect-input connect-input
 :disconnect-input disconnect-input
 :dispatch-input dispatch-input
 :active-input (fn [] active-input)
 :current-state-name current-state-name
 :states-host-available? states-host-available?
 :clear-active-input-for-teardown clear-active-input-for-teardown
 :set-state set-state
 :set-states-provider set-states-provider
 :reset reset
 :release-active-input release-active-input}

;
