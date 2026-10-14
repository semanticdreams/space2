(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Signal (require :signal))
(local Utils (require :graph/view/utils))
(local CodeEntityListNodeView (require :graph/view/views/code-entity-list))

(fn single-line [text]
  (assert (= (type text) "string") "code browser label metadata must be a string")
  (string.match (string.gsub text "%s+" " ") "^ *(.-) *$"))

(fn entity-label [entity]
  (local name (single-line entity.name))
  (local fallback (.. (single-line entity.id) " (" (single-line entity.language) ")"))
  (Utils.truncate-with-ellipsis (if (> (string.len name) 0) name fallback) 50))

(fn CodeEntityListNode [opts]
  (local store (assert (and opts opts.store) "CodeEntityListNode requires :store"))
  (local base (GraphNode {:key "code-entity-list"
                         :label "code entities"
                         :color (glm.vec4 0.2 0.35 0.85 1)
                         :sub-color (glm.vec4 0.3 0.45 0.9 1)
                         :size 8.0
                         :view CodeEntityListNodeView}))
  (local items-changed (Signal))
  (local subscriptions [])
  (var dropped? false)

  (fn collect-items [_self]
    (assert (not dropped?) "CodeEntityListNode collect-items after drop")
    (icollect [_ entity (ipairs (store:list-entities))]
      ;; Rows retain only navigation identity, never source code payloads.
      [{:id entity.id} (entity-label entity)]))

  (fn emit-items [self]
    (local items (collect-items self))
    (items-changed:emit items)
    items)

  (fn add-entity-node [self entity]
    (assert (not dropped?) "CodeEntityListNode add-entity-node after drop")
    (local id (assert (and entity entity.id) "CodeEntityListNode.add-entity-node requires entity id"))
    (local key (.. "code-entity:" id))
    (local graph-map (assert self.graph (.. "missing GraphMap for " key)))
    (assert (= (type graph-map.load-by-key) "function") (.. "missing GraphMap:load-by-key for " key))
    (assert (= (type graph-map.add-edge) "function") (.. "missing GraphMap:add-edge for " key))
    (local target (assert (graph-map:load-by-key key) (.. "failed to load " key)))
    (graph-map:add-edge (GraphEdge {:source self :target target}))
    target)

  (fn refresh [_button _event] (emit-items nil))

  (fn drop [_self]
    (when (not dropped?)
      (set dropped? true)
      (each [_ subscription (ipairs subscriptions)]
        (subscription.signal:disconnect subscription.handler))
      (items-changed:clear)))

  (local self {:key base.key :label base.label :color base.color :accent base.accent
               :kind-badge base.kind-badge :size base.size :view base.view :preview base.preview
               :mount base.mount :unmount base.unmount
               :store store :items-changed items-changed
               :collect-items collect-items :emit-items emit-items
               :add-entity-node add-entity-node :drop drop
               :actions [{:name "Refresh" :icon "refresh" :fn refresh}]})

  (fn on-store-changed [_entity] (self:emit-items))
  (each [_ signal (ipairs [store.code-entity-created store.code-entity-updated store.code-entity-deleted])]
    (table.insert subscriptions {:signal signal :handler (signal:connect on-store-changed)}))
  self)

CodeEntityListNode
