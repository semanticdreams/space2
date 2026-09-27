(local Schema (require :app-host.command-payload-schema))

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

(fn run-host [host command-id payload]
  (local command (find-command (command-list host) command-id))
  (when command.payload-schema
    (Schema.validate-schema command.payload-schema {:command-id command-id}))
  (local run-fn command.run)
  (when (not (= (type run-fn) :function))
    (command-error (.. "command requires run function: " (tostring command-id))))
  (local (ok value) (pcall run-fn command payload))
  (if ok
      {:id command-id :status :ok :value value}
      {:id command-id :status :error :error (tostring value)}))

{:run-host run-host}
