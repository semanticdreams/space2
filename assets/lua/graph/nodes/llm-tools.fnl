(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local LlmToolsView (require :graph/view/views/llm-tools))
(local LlmToolNode (require :graph/nodes/llm-tool))
(local LlmTools (require :llm/tools/init))
(local Signal (require :signal))

(fn LlmToolsNode [opts]
    (local options (or opts {}))
    (local key (or options.key "llm-tools"))
    (local label (or options.label "llm tools"))
    (local node (GraphNode {:key key
                                :label label
                                :color (glm.vec4 0.2 0.7 0.6 1)
                                :sub-color (glm.vec4 0.1 0.6 0.5 1)
                                :size 8.0
                                :view LlmToolsView}))
    (set node.kind "llm-tools")
    (set node.items-changed (Signal))

    (set node.build-items
         (fn [self]
             (local items [])
             (each [_ tool (ipairs (or options.tools LlmTools.tools []))]
                 (table.insert items [tool tool.name]))
             items))

    (set node.emit-items
         (fn [self]
             (self:build-items)))

    (set node.refresh
         (fn [self]
             (local items (self:build-items))
             (self.items-changed:emit items)))

    (set node.create-tool
         (fn [self tool]
             (assert tool "LlmToolsNode requires a tool")
             (local graph self.graph)
             (assert graph "LlmToolsNode requires a mounted graph")
             (local tool-name (tostring (or tool.name "llm-tool")))
             (local key (.. "llm-tool:" tool-name))
             (local existing (and graph.nodes (. graph.nodes key)))
             (local tool-node
                 (or existing
                     (LlmToolNode {:key key
                                   :name tool-name
                                   :tool tool})))
             (graph:add-node tool-node)
             (graph:add-edge (GraphEdge {:source self
                                         :target tool-node}))
             tool-node))

    (set node.actions
         [{:name "Refresh"
           :icon "refresh"
           :fn (fn [_button _event]
                   (node:refresh))}])

    (set node.drop
         (fn [self]
             (when self.items-changed
                 (self.items-changed:clear))))

    node)

LlmToolsNode
