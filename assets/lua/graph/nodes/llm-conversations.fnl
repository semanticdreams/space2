(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local LlmConversationsView (require :graph/view/views/llm-conversations))
(local LlmConversationNode (require :graph/nodes/llm-conversation))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Signal (require :signal))
(local LlmStore (require :llm/conversations/store))
(local Utils (require :graph/view/utils))

(fn conversation-label [record]
  (local name (or (and record record.name) ""))
  (if (> (length name) 0)
      (Utils.truncate-with-ellipsis name 40)
      (Utils.truncate-with-ellipsis (tostring (or (and record record.id) "")) 40)))

(fn attach-refresh-handler [node handlers signal]
  (when signal
    (local handler
      (signal:connect
        (fn [_record]
          (when (and node node.refresh)
            (node:refresh)))))
    (table.insert handlers {:signal signal
                            :handler handler}))
  handlers)

(fn attach-store-handlers [node store]
  (local handlers [])
  (local conversations-signal (and store store.conversations-changed))
  (local conversation-signal (and store store.conversation-changed))
  (attach-refresh-handler node handlers conversations-signal)
  (attach-refresh-handler node handlers conversation-signal)
  handlers)

(fn drop-handlers [handlers]
  (each [_ record (ipairs (or handlers []))]
    (when (and record record.signal record.handler)
      (record.signal:disconnect record.handler true))))

(fn LlmConversationsNode [opts]
  (local options (or opts {}))
  (local store (or options.store (LlmStore.get-default)))
  (local key (or options.key "llm-conversations"))
  (local label (or options.label "llm conversations"))
  (local node (GraphNode {:key key
                          :label label
                          :color (glm.vec4 0.2 0.7 0.6 1)
                          :sub-color (glm.vec4 0.1 0.6 0.5 1)
                          :size 8.0
                          :view LlmConversationsView}))
  (set node.store store)
  (set node.items-changed (Signal))
  (set node.open-requested (Signal))
  (set node.handlers [])

  (set node.build-items
       (fn [self]
         (local entries [])
         (each [_ record (ipairs (store:list-conversations))]
           (table.insert entries {:id record.id
                                  :label (conversation-label record)
                                  :updated-at record.updated_at}))
         entries))

  (set node.refresh
       (fn [self]
         (local items (self:build-items))
         (self.items-changed:emit items)))

  (set node.open-entry
       (fn [self entry]
         (local graph self.graph)
         (assert graph "LlmConversationsNode requires a mounted graph")
         (local conversation (LlmConversationNode {:llm-id entry.id
                                                   :store store}))
         (graph:add-node conversation)
         (graph:add-edge (GraphEdge {:source self
                                     :target conversation}))
         conversation))

  (set node.request-open
       (fn [self entry]
         (self:open-entry entry)
         (self.open-requested:emit entry)))

  (set node.create-conversation
       (fn [self opts]
         (local graph self.graph)
         (assert graph "LlmConversationsNode requires a mounted graph")
         (local options (or opts {}))
         (local record (store:create-conversation {:name options.name
                                                   :model options.model
                                                   :temperature options.temperature}))
         (local conversation (LlmConversationNode {:llm-id record.id
                                                   :store store}))
         (graph:add-node conversation)
         (graph:add-edge (GraphEdge {:source self
                                     :target conversation}))
         conversation))

  (set node.actions
       [{:name "Refresh"
         :icon "refresh"
         :fn (fn [_button _event]
                 (node:refresh))}
        {:name "New Conversation"
         :icon "add_comment"
         :fn (fn [_button _event]
                 (node:create-conversation {}))}])

  (local drop-fn
    (fn [self]
      (when self.items-changed
        (self.items-changed:clear))
      (when self.open-requested
        (self.open-requested:clear))
      (drop-handlers self.handlers)))
  (set node.drop drop-fn)
  (set node.handlers (attach-store-handlers node store))
  node)

LlmConversationsNode
