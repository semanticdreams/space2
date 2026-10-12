(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local LlmNodeView (require :graph/view/views/llm))
(local LlmProviderNode (require :graph/nodes/llm-provider))
(local LlmModelNode (require :graph/nodes/llm-model))
(local LlmToolsNode (require :graph/nodes/llm-tools))
(local LlmConversationsNode (require :graph/nodes/llm-conversations))
(local Signal (require :signal))

(fn LlmNode []
    (local node
        (GraphNode {:key "llm"
                    :label "llm"
                    :color (glm.vec4 0.2 0.7 0.6 1)
                    :sub-color (glm.vec4 0.1 0.6 0.5 1)
                    :size 8.0
                    :view LlmNodeView}))
    (set node.targets-changed (Signal))

    (set node.collect-targets
         (fn [_self]
             (local produced [])
             (local llm-provider (LlmProviderNode))
             (table.insert produced [llm-provider (or llm-provider.label llm-provider.key)])
             (local llm-model (LlmModelNode))
             (table.insert produced [llm-model (or llm-model.label llm-model.key)])
             (local llm-tools (LlmToolsNode))
             (table.insert produced [llm-tools (or llm-tools.label llm-tools.key)])
             (local llm-conversations (LlmConversationsNode))
             (table.insert produced [llm-conversations (or llm-conversations.label llm-conversations.key)])
             produced))

    (set node.emit-targets
         (fn [self]
             (local targets (self:collect-targets))
             (when self.targets-changed
                 (self.targets-changed:emit targets))
             targets))

    (set node.add-target
         (fn [self target]
             (local graph self.graph)
             (when (and graph target)
                 (graph:add-edge (GraphEdge {:source self
                                             :target target})))))

    (fn add-target-by-key [self key]
        (each [_ pair (ipairs (self:collect-targets))]
            (local target (. pair 1))
            (when (= (and target target.key) key)
                (self:add-target target))))

    (set node.actions
         [{:name "Add Conversations"
           :icon "chat"
           :fn (fn [_button _event]
                   (add-target-by-key node "llm-conversations"))}
          {:name "Add Tools"
           :icon "build"
           :fn (fn [_button _event]
                   (add-target-by-key node "llm-tools"))}
          {:name "Add Model"
           :icon "memory"
           :fn (fn [_button _event]
                   (add-target-by-key node "llm-model"))}
          {:name "Add Provider"
           :icon "settings"
           :fn (fn [_button _event]
                   (add-target-by-key node "llm-provider"))}])

    (set node.drop
         (fn [self]
             (when self.targets-changed
                 (self.targets-changed:clear))))
    node)

LlmNode
