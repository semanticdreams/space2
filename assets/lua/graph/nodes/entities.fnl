(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Signal (require :signal))
(local EntitiesNodeView (require :graph/view/views/entities))

(fn make-type-action [self descriptor]
  (local id descriptor.id)
  {:name descriptor.action-name :icon descriptor.icon
   :fn (fn [_button _event] (self:add-type-node id))})

(fn EntitiesNode [opts]
  (local catalog (assert (and opts opts.entity-type-catalog) "EntitiesNode requires :entity-type-catalog"))
  (assert (and (= (type catalog.list-types) "function") (= (type catalog.get-type) "function"))
          "EntitiesNode requires entity-type-catalog list-types and get-type methods")
  (local base (GraphNode {:key "entities" :label "entities"
                         :color (glm.vec4 0.4 0.4 0.4 1)
                         :sub-color (glm.vec4 0.45 0.45 0.45 1)
                         :size 8.0 :view EntitiesNodeView}))
  (local types-changed (Signal))
  (local actions [])
  (var dropped? false)

  (fn collect-types [self]
    (assert (not dropped?) "EntitiesNode collect-types after drop")
    (icollect [_ descriptor (ipairs (self.entity-type-catalog:list-types))]
      [descriptor.id descriptor.label]))

  (fn emit-types [self]
    (local types (collect-types self))
    (types-changed:emit types)
    types)

  (fn add-type-node [self id]
    (assert (not dropped?) "EntitiesNode add-type-node after drop")
    (local descriptor (self.entity-type-catalog:get-type id))
    (local key descriptor.browser-key)
    (local graph-map (assert self.graph (.. "missing GraphMap for " key)))
    (assert (= (type graph-map.load-by-key) "function") (.. "missing GraphMap:load-by-key for " key))
    (assert (= (type graph-map.add-edge) "function") (.. "missing GraphMap:add-edge for " key))
    (local target (assert (graph-map:load-by-key key) (.. "failed to load " key)))
    (graph-map:add-edge (GraphEdge {:source self :target target}))
    target)

  (fn drop [_self]
    (when (not dropped?)
      (set dropped? true)
      (types-changed:clear)))

  (local self {:key base.key :label base.label :color base.color :accent base.accent
               :kind-badge base.kind-badge :size base.size :view base.view :preview base.preview
               :mount base.mount :unmount base.unmount
               :entity-type-catalog catalog :types-changed types-changed :actions actions
               :collect-types collect-types :emit-types emit-types :add-type-node add-type-node :drop drop})
  (each [_ descriptor (ipairs (catalog:list-types))]
    (table.insert actions (make-type-action self descriptor)))
  self)

EntitiesNode
