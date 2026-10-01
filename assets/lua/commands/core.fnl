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

(fn prefix-child? [item]
  (var has-child? false)
  (each [_ _child (pairs (list-or-empty (and item item.node item.node.nodes)))]
    (set has-child? true))
  has-child?)

(fn M.compose [providers ctx]
  (local commands {})
  (local bindings [])
  (local prefixes [])
  (each [_ provider (ipairs (list-or-empty providers))]
    (local resolved (if (= (type provider) :function) (provider ctx) provider))
    (when resolved
      (each [id command (pairs (options-or-empty resolved.commands))]
        (set (. commands id) command))
      (each [_ prefix (ipairs (list-or-empty resolved.prefixes))]
        (table.insert prefixes prefix))
      (each [_ binding (ipairs (list-or-empty resolved.bindings))]
        (table.insert bindings binding))))
  {:commands commands
    :bindings bindings
    :prefixes prefixes
    :tree (Keymap.build bindings prefixes)})

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
  (if (and (prefix-child? item) item.prefix item.prefix.label)
      item.prefix.label
      (and item.binding item.binding.label)
      item.binding.label
      (and command command.label)
      command.label
      command-id
      command-id
      item.token))

(fn node-has-available-command? [composed node ctx]
  (if (and node node.command-id (M.available? composed node.command-id ctx))
      true
      (do
        (var visible? false)
        (each [_ child (pairs (list-or-empty (and node node.nodes)))]
          (when (node-has-available-command? composed child ctx)
            (set visible? true)))
        visible?)))

(fn child-visible? [composed item ctx]
  (node-has-available-command? composed item.node ctx))

(fn hint-priority [item]
  (if (and (prefix-child? item) item.prefix item.prefix.priority)
      item.prefix.priority
      (and item.binding item.binding.priority)
      item.binding.priority
      50))

(fn M.hint-section [composed prefix ctx opts]
  (local options (options-or-empty opts))
  (local entries [])
  (each [_ item (ipairs (Keymap.children composed.tree (list-or-empty prefix)))]
    (when (child-visible? composed item ctx)
       (table.insert entries
                     (entry item.token
                            (command-label composed item)
                            {:priority (hint-priority item)
                             :id (if item.command-id item.command-id item.token)}))))
  (when (> (length entries) 0)
    (section (if options.id options.id :mode)
             (if options.title options.title "MODE")
             entries)))

{:compose M.compose
 :available? M.available?
 :run M.run
 :hint-section M.hint-section}
