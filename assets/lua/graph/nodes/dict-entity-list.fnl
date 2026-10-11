(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Signal (require :signal))
(local DictEntityStore (require :entities/dict))
(local {:DictEntityNode DictEntityNode} (require :graph/nodes/dict-entity))
(local Utils (require :graph/view/utils))

(local TEAL (glm.vec4 0.0 0.55 0.45 1))
(local TEAL_ACCENT (glm.vec4 0.05 0.65 0.55 1))

(fn options-table [opts]
  (if (= (type opts) "table") opts {}))

(fn entity-items [entity]
  (if (and entity (= (type entity.items) "table")) entity.items {}))

(fn entity-name [entity]
  (if (and entity entity.name) entity.name ""))

(fn entity-id-label [entity]
  (if (and entity entity.id) entity.id "unknown"))

(fn item-count [entity]
  (var count 0)
  (each [_ _ (pairs (entity-items entity))]
    (set count (+ count 1)))
  count)

(fn item-count-label [entity]
  (local count (item-count entity))
  (if (= count 1) "1 item" (.. count " items")))

(fn make-entity-label [entity]
  (local name (entity-name entity))
  (local id (entity-id-label entity))
  (local base (if (> (string.len name) 0) name id))
  (.. (Utils.truncate-with-ellipsis base 45) " (" (item-count-label entity) ")"))

(fn DictEntityListNode [opts]
  (local options (options-table opts))
  (local store (if options.store options.store (DictEntityStore.get-default)))
  (local identity-store options.identity-store)
  (local DictEntityListNodeView (require :graph/view/views/dict-entity-list))
  (local node
    (GraphNode {:key "dict-entity-list"
                :label "dict entities"
                :color TEAL
                :sub-color TEAL_ACCENT
                :size 8.0
                :view DictEntityListNodeView}))

  (set node.store store)
  (set node.identity-store identity-store)
  (set node.items-changed (Signal))

  (fn collect-items [self]
    (local entities (self.store:list-entities))
    (local produced [])
    (each [_ entity (ipairs entities)]
      (table.insert produced [entity (make-entity-label entity)]))
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
           (local entity-node (DictEntityNode {:entity-id entity.id
                                               :store self.store
                                               :identity-store self.identity-store}))
           (graph:add-edge (GraphEdge {:source self :target entity-node})))))

  (set node.create-entity
       (fn [self opts]
         (local entity (self.store:create-entity opts))
         (self:emit-items)
         entity))

  (set node.actions
       [{:name "Refresh"
         :icon "refresh"
         :fn (fn [_button _event] (node:emit-items))}
        {:name "New Dict"
         :icon "data_object"
         :fn (fn [_button _event] (node:create-entity {}))}])

  (var created-handler nil)
  (var updated-handler nil)
  (var deleted-handler nil)
  (var items-handler nil)
  (set created-handler (store.dict-entity-created:connect (fn [_entity] (node:emit-items))))
  (set updated-handler (store.dict-entity-updated:connect (fn [_entity] (node:emit-items))))
  (set deleted-handler (store.dict-entity-deleted:connect (fn [_entity] (node:emit-items))))
  (set items-handler (store.dict-entity-items-changed:connect (fn [_payload] (node:emit-items))))

  (set node.drop
       (fn [self]
         (when created-handler
           (store.dict-entity-created:disconnect created-handler true)
           (set created-handler nil))
         (when updated-handler
           (store.dict-entity-updated:disconnect updated-handler true)
           (set updated-handler nil))
         (when deleted-handler
           (store.dict-entity-deleted:disconnect deleted-handler true)
           (set deleted-handler nil))
         (when items-handler
           (store.dict-entity-items-changed:disconnect items-handler true)
           (set items-handler nil))
         (self.items-changed:clear)))

  node)

DictEntityListNode
