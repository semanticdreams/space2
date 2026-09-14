(local runtime (or (rawget _G "__space_state_system_runtime") {}))
(set _G.__space_state_system_runtime runtime)

(fn assert-provider [provider]
  (assert (or (= provider nil)
              (= (type provider) :function))
          "StateSystemRuntime states provider must be a function"))

(fn set-states-provider [provider]
  (assert-provider provider)
  (set runtime.states-provider provider)
  provider)

(fn maybe-states-host []
  (local provider runtime.states-provider)
  (and provider
       (provider)))

(fn states-host [owner action]
  (local states (maybe-states-host))
  (assert states
          (.. owner " requires a states host for " action))
  states)

{:set-states-provider set-states-provider
 :maybe-states-host maybe-states-host
 :states-host states-host}
