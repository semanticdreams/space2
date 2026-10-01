(local Keymap (require :commands/keymap))
(local {: entry : section} (require :command-hints))

(local M {})

(fn list-or-empty [items]
  (if (= items nil) [] items))

(fn options-or-empty [opts]
  (if (= opts nil) {} opts))

(fn command-available? [command ctx]
  (if (not command)
      false
      command.available?
      (not (= (command.available? ctx) false))
      true))

(fn M.compose [providers ctx]
  (local commands {})
  (local bindings [])
  (each [_ provider (ipairs (list-or-empty providers))]
    (local resolved (if (= (type provider) :function) (provider ctx) provider))
    (when resolved
      (each [id command (pairs (options-or-empty resolved.commands))]
        (set (. commands id) command))
      (each [_ binding (ipairs (list-or-empty resolved.bindings))]
        (table.insert bindings binding))))
  {:commands commands
   :bindings bindings
   :tree (Keymap.build bindings)})

(fn M.available? [composed command-id ctx]
  (command-available? (. composed.commands command-id) ctx))

(fn M.run [composed command-id ctx]
  (local command (. composed.commands command-id))
  (if (and command (command-available? command ctx))
      (command.run ctx)
      false))

(fn command-label [composed item]
  (local command-id (if item.command-id
                        item.command-id
                        (and item.binding item.binding.command)))
  (local command (and command-id (. composed.commands command-id)))
  (if (and item.binding item.binding.label)
      item.binding.label
      (and command command.label)
      command.label
      command-id
      command-id
      item.token))

(fn child-visible? [composed item ctx]
  (if item.command-id
      (M.available? composed item.command-id ctx)
      true))

(fn M.hint-section [composed prefix ctx opts]
  (local options (options-or-empty opts))
  (local entries [])
  (each [_ item (ipairs (Keymap.children composed.tree (list-or-empty prefix)))]
    (when (child-visible? composed item ctx)
      (table.insert entries
                    (entry item.token
                           (command-label composed item)
                           {:priority (if (and item.binding item.binding.priority) item.binding.priority 50)
                            :id (if item.command-id item.command-id item.token)}))))
  (when (> (length entries) 0)
    (section (if options.id options.id :mode)
             (if options.title options.title "MODE")
             entries)))

{:compose M.compose
 :available? M.available?
 :run M.run
 :hint-section M.hint-section}
