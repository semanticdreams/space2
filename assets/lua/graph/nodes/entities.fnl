(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Signal (require :signal))
(local StringEntityListNode (require :graph/nodes/string-entity-list))
(local LinkEntityListNode (require :graph/nodes/link-entity-list))
(local ListEntityListNode (require :graph/nodes/list-entity-list))

(local GRAY (glm.vec4 0.4 0.4 0.4 1))
(local GRAY_ACCENT (glm.vec4 0.45 0.45 0.45 1))

(fn EntitiesNode [opts]
  (local options (or opts {}))
  (local EntitiesNodeView (require :graph/view/views/entities))

  (local node
    (GraphNode {:key "entities"
                :label "entities"
                :color GRAY
                :sub-color GRAY_ACCENT
                :size 8.0
                :view EntitiesNodeView}))

  (set node.types-changed (Signal))

  (fn collect-types [_self]
    (local produced [])
    (table.insert produced [:string "string"])
    (table.insert produced [:link "link"])
    (table.insert produced [:list "list"])
    (table.insert produced [:dict "dict"])
    produced)

  (fn emit-types [self]
    (local types (collect-types self))
    (self.types-changed:emit types)
    types)

  (set node.collect-types collect-types)
  (set node.emit-types emit-types)

  (set node.add-type-node
       (fn [self type-key]
         (local graph self.graph)
         (when graph
           (if (= type-key :string)
               (do
                 (local list-node (StringEntityListNode {}))
                 (graph:add-edge (GraphEdge {:source self
                                             :target list-node})))
               (= type-key :link)
               (do
                 (local list-node (LinkEntityListNode {}))
                 (graph:add-edge (GraphEdge {:source self
                                             :target list-node})))
                (= type-key :list)
                (do
                  (local list-node (ListEntityListNode {}))
                  (graph:add-edge (GraphEdge {:source self
                                              :target list-node})))
                (= type-key :dict)
                (do
                  (local DictEntityListNode (require :graph/nodes/dict-entity-list))
                  (local list-node (DictEntityListNode {}))
                  (graph:add-edge (GraphEdge {:source self
                                              :target list-node})))))))

  (set node.actions
       [{:name "String Entities"
         :icon "text_fields"
         :fn (fn [_button _event]
                 (node:add-type-node :string))}
        {:name "Link Entities"
         :icon "link"
         :fn (fn [_button _event]
                 (node:add-type-node :link))}
         {:name "List Entities"
          :icon "list"
          :fn (fn [_button _event]
                  (node:add-type-node :list))}
         {:name "Dict Entities"
          :icon "data_object"
          :fn (fn [_button _event]
                  (node:add-type-node :dict))}])

  (set node.drop
       (fn [self]
         (self.types-changed:clear)))

  node)

EntitiesNode
