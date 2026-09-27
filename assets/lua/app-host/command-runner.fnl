(local Metadata (require :app-host.command-metadata))

(fn command-error [message]
  (error (.. "[app-host.command-runner] " message)))

(fn command-list [host]
  (when (not (= (type host) :table))
    (command-error "run-host requires host table"))
  (local registry host.commands)
  (when (not (= (type registry) :table))
    (command-error "host commands registry is required"))
  (when (not (= (type registry.list) :function))
    (command-error "host commands registry requires list"))
  (local commands (registry:list))
  (when (not (= (type commands) :table))
    (command-error "host commands registry list must return a table"))
  commands)

(fn find-command [commands command-id]
  (when (= command-id nil)
    (command-error "run-host requires command id"))
  (var found nil)
  (var count 0)
  (each [_ command (ipairs commands)]
    (when (not (= (type command) :table))
      (command-error "command facet must be a table"))
    (when (= command.id command-id)
      (set count (+ count 1))
      (set found command)))
  (when (= count 0)
    (command-error (.. "command not found: " (tostring command-id))))
  (when (> count 1)
    (command-error (.. "duplicate command id: " (tostring command-id))))
  found)

(fn command-for-run [host command-id]
  (local command (find-command (command-list host) command-id))
  (Metadata.validate-command command {:command-id command-id})
  command)

(fn result-ok [command-id value]
  {:id command-id :status :ok :value value})

(fn result-error [command-id value]
  {:id command-id :status :error :error (tostring value)})

(fn validate-async-callbacks [callbacks]
  (when (not (= (type callbacks) :table))
    (command-error "run-host-async requires callbacks table"))
  (when (not (= (type callbacks.on-result) :function))
    (command-error "run-host-async requires on-result callback")))

(fn validate-progress [progress]
  (when (not (= (type progress) :table))
    (command-error "async progress must be a table"))
  (when (and (not (= progress.message nil)) (not (= (type progress.message) :string)))
    (command-error "async progress.message must be a string"))
  (when (not (= progress.value nil))
    (if (not (= (type progress.value) :number))
        (command-error "async progress.value must be a number between 0 and 1")
        (< progress.value 0)
        (command-error "async progress.value must be a number between 0 and 1")
        (> progress.value 1)
        (command-error "async progress.value must be a number between 0 and 1")))
  progress)

(fn validate-pending-handle [pending]
  (when (not (= (type pending) :table))
    (command-error "async command must return pending handle"))
  (when (not (= pending.pending true))
    (command-error "async command must return pending handle"))
  (when (and (not (= pending.cancel nil)) (not (= (type pending.cancel) :function)))
    (command-error "async pending handle cancel must be a function"))
  (when (and (not (= pending.drop nil)) (not (= (type pending.drop) :function)))
    (command-error "async pending handle drop must be a function"))
  pending)

(fn cancel-reason [reason]
  (if (= reason nil) "cancelled" (tostring reason)))

(fn run-host [host command-id payload]
  (local command (command-for-run host command-id))
  (local run-fn command.run)
  (when (not (= (type run-fn) :function))
    (command-error (.. "command requires run function: " (tostring command-id))))
  (local (ok value) (pcall run-fn command payload))
  (if ok
      (result-ok command-id value)
      (result-error command-id value)))

(fn run-host-async [host command-id payload callbacks]
  (validate-async-callbacks callbacks)
  (local command (command-for-run host command-id))
  (local run-async-fn command.run-async)
  (when (and (not (= run-async-fn nil))
             (not (= (type run-async-fn) :function)))
    (command-error (.. "command run-async must be a function: " (tostring command-id))))
  (when (and (= run-async-fn nil) (not (= (type command.run) :function)))
    (command-error (.. "command requires run or run-async function: " (tostring command-id))))
  (var terminal? false)
  (var cancelled? false)
  (var dropped? false)
  (var initializing? false)
  (var queued-terminal-result nil)
  (var pending-handle nil)
  (local handle {:id command-id :status :running})
  (fn deliver-result [result]
    (when (and (not terminal?) (not dropped?))
      (if initializing?
          (when (= queued-terminal-result nil)
            (set queued-terminal-result result))
          (do
            (set terminal? true)
            (set handle.status :completed)
            (callbacks.on-result result)))))
  (fn deliver-error [message]
    (deliver-result (result-error command-id message)))
  (fn deliver-progress [progress]
    (when (and (not terminal?) (not dropped?))
      (local (ok value) (pcall validate-progress progress))
      (if ok
          (when (= (type callbacks.on-progress) :function)
            (callbacks.on-progress value))
          (deliver-error value))))
  (fn cancel [_self reason]
    (when (and (not terminal?) (not dropped?))
      (set cancelled? true)
      (set terminal? true)
      (set handle.status :cancelled)
      (when (and (= (type pending-handle) :table)
                  (= (type pending-handle.cancel) :function))
        (pcall pending-handle.cancel reason))
      (callbacks.on-result {:id command-id :status :cancelled :error (cancel-reason reason)})))
  (fn drop [_self]
    (when (and (not terminal?) (not dropped?))
      (set cancelled? true)
      (set dropped? true)
      (set handle.status :dropped)
      (when (= (type pending-handle) :table)
        (if (= (type pending-handle.drop) :function)
            (pending-handle.drop)
            (= (type pending-handle.cancel) :function)
            (pending-handle.cancel "dropped")))))
  (fn is-cancelled? [_self]
    cancelled?)
  (set handle.cancel cancel)
  (set handle.drop drop)
  (set handle.cancelled? is-cancelled?)
  (local async-callbacks {:progress deliver-progress
                          :resolve (fn [value]
                                     (deliver-result (result-ok command-id value)))
                          :reject (fn [err]
                                    (deliver-error err))
                          :cancelled? (fn [] cancelled?)})
  (if (= (type run-async-fn) :function)
      (do
        (set initializing? true)
        (local (ok value) (pcall run-async-fn command payload async-callbacks))
        (if ok
            (do
              (if (= value :completed)
                  (do
                    (set initializing? false)
                    (if (not (= queued-terminal-result nil))
                        (deliver-result queued-terminal-result)
                        (deliver-error "async command returned :completed without terminal callback")))
                  (do
                    (local (pending-ok pending-or-error) (pcall validate-pending-handle value))
                    (set initializing? false)
                    (if pending-ok
                        (do
                          (set pending-handle pending-or-error)
                          (when (not (= queued-terminal-result nil))
                            (deliver-result queued-terminal-result)))
                        (deliver-error pending-or-error)))))
            (do
              (set initializing? false)
              (deliver-error value))))
      (deliver-result (run-host host command-id payload)))
  (when (not terminal?)
    (set handle.status :running))
  handle)

{:run-host run-host
 :run-host-async run-host-async}
