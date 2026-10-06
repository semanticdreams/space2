(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Signal (require :signal))
(local StringEntityStore (require :entities/string))
(local {:StringEntityNode StringEntityNode} (require :graph/nodes/string-entity))
(local Utils (require :graph/view/utils))

(local DARK_GREEN (glm.vec4 0.1 0.4 0.2 1))
(local DARK_GREEN_ACCENT (glm.vec4 0.15 0.45 0.25 1))

(fn make-entity-label [entity]
  (if (and entity entity.value (> (string.len entity.value) 0))
      (Utils.truncate-with-ellipsis entity.value 50)
      (or entity.id "unknown")))

(fn StringEntityListNode [opts]
  (local options (or opts {}))
  (local store (or options.store (StringEntityStore.get-default)))
  (local StringEntityListNodeView (require :graph/view/views/string-entity-list))

  (local node
    (GraphNode {:key "string-entity-list"
                :label "string entities"
                :color DARK_GREEN
                :sub-color DARK_GREEN_ACCENT
                :size 8.0
                :view StringEntityListNodeView}))

  (set node.store store)
  (set node.items-changed (Signal))

  (fn collect-items [self]
    (local entities (self.store:list-entities))
    (local produced [])
    (each [_ entity (ipairs entities)]
      (local label (make-entity-label entity))
      (table.insert produced [entity label]))
    produced)

  (fn emit-items [self]
    (local items (collect-items self))
    (self.items-changed:emit items)
    items)

  (set node.collect-items collect-items)
  (set node.emit-items emit-items)

  (set node.add-entity-node
       (fn [self entity]
         (local graph self.graph)
         (when (and graph entity entity.id)
           (local entity-node (StringEntityNode {:entity-id entity.id
                                                 :store self.store}))
            (graph:add-edge (GraphEdge {:source self
                                        :target entity-node})))))

  (set node.add-search-node
       (fn [self]
         (local graph (assert self.graph "StringEntityListNode.add-search-node requires mounted GraphMap"))
         (assert graph.load-by-key "StringEntityListNode.add-search-node requires GraphMap:load-by-key")
         (assert graph.add-edge "StringEntityListNode.add-search-node requires GraphMap:add-edge")
         (local search-node (graph:load-by-key "string-entity-search"))
         (assert search-node "StringEntityListNode.add-search-node failed to load string-entity-search")
         (graph:add-edge (GraphEdge {:source self :target search-node}))
         search-node))

  (set node.create-entity
       (fn [self opts]
         (local entity (self.store:create-entity opts))
         (self:emit-items)
         entity))

  (set node.actions
       [{:name "Refresh"
         :icon "refresh"
         :fn (fn [_button _event]
                 (node:emit-items))}
         {:name "New String"
          :icon "note_add"
          :fn (fn [_button _event]
                  (node:create-entity {}))}
         {:name "Search Text"
          :icon "search"
          :fn (fn [_button _event]
                  (node:add-search-node))}])

  (var created-handler nil)
  (var updated-handler nil)
  (var deleted-handler nil)

  (set created-handler
       (store.string-entity-created:connect
         (fn [_entity]
           (node:emit-items))))

  (set updated-handler
       (store.string-entity-updated:connect
         (fn [_entity]
           (node:emit-items))))

  (set deleted-handler
       (store.string-entity-deleted:connect
         (fn [_entity]
           (node:emit-items))))

  (set node.drop
       (fn [self]
         (when created-handler
           (store.string-entity-created:disconnect created-handler true)
           (set created-handler nil))
         (when updated-handler
           (store.string-entity-updated:disconnect updated-handler true)
           (set updated-handler nil))
         (when deleted-handler
           (store.string-entity-deleted:disconnect deleted-handler true)
           (set deleted-handler nil))
         (self.items-changed:clear)))

  node)

StringEntityListNode
