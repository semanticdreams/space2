(local CommandHints (require :command-hints))

(local M {})

(fn list-or-empty [items]
  (if (= items nil) [] items))

(fn M.key-token [payload-or-key]
  (if (= payload-or-key nil)
      nil
      (= (type payload-or-key) :table)
      (CommandHints.key-label payload-or-key.key)
      (CommandHints.key-label payload-or-key)))

(fn ensure-child [node token]
  (when (= node.nodes nil)
    (set node.nodes {}))
  (when (not (. node.nodes token))
    (set (. node.nodes token) {:token token :nodes {}}))
  (. node.nodes token))

(fn attach-prefix [root prefix]
  (local keys (assert prefix.keys "Command prefix metadata requires :keys"))
  (assert prefix.label "Command prefix metadata requires :label")
  (var node root)
  (each [_ key (ipairs keys)]
    (set node (ensure-child node key)))
  (set node.prefix prefix))

(fn M.build [bindings prefixes]
  (local root {:nodes {}})
  (each [_ prefix (ipairs (list-or-empty prefixes))]
    (attach-prefix root prefix))
  (each [_ binding (ipairs (list-or-empty bindings))]
    (local keys (assert binding.keys "Command key binding requires :keys"))
    (assert binding.command "Command key binding requires :command")
    (var node root)
    (each [_ key (ipairs keys)]
      (set node (ensure-child node key)))
    (set node.command-id binding.command)
    (set node.binding binding))
  root)

(fn M.resolve [tree sequence]
  (var node tree)
  (var missing false)
  (each [_ token (ipairs (list-or-empty sequence))]
    (if (and node node.nodes (. node.nodes token))
        (set node (. node.nodes token))
        (set missing true)))
  (if missing
      {:kind :missing}
      (and node node.command-id)
      {:kind :command :command-id node.command-id :binding node.binding :node node}
      (and node node.nodes)
      {:kind :prefix :node node}
      {:kind :missing}))

(fn M.children [tree sequence]
  (local resolved (M.resolve tree sequence))
  (if (= resolved.kind :prefix)
      (do
        (local items [])
        (each [token item-node (pairs (list-or-empty resolved.node.nodes))]
          (table.insert items {:token token
                               :node item-node
                               :prefix item-node.prefix
                               :binding item-node.binding
                               :command-id item-node.command-id}))
        (table.sort items (fn [a b]
                            (< (or (and a.prefix a.prefix.priority)
                                   (and a.binding a.binding.priority)
                                   50)
                               (or (and b.prefix b.prefix.priority)
                                   (and b.binding b.binding.priority)
                                   50))))
        items)
      []))

(fn M.binding-key-label [binding prefix]
  (local keys (list-or-empty binding.keys))
  (local index (+ (length (list-or-empty prefix)) 1))
  (or (. keys index) ""))

{:key-token M.key-token
 :build M.build
 :resolve M.resolve
 :children M.children
 :binding-key-label M.binding-key-label}
