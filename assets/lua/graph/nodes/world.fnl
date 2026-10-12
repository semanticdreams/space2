(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local WorldNodeView (require :graph/view/views/world))
(local {:WorldActivitiesNode WorldActivitiesNode} (require :graph/nodes/world-activities))
(local WorldData (require :graph/world-data))

(local M {})

(fn M.WorldNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "WorldNode requires :world-id"))
  (local world-manager (assert options.world-manager "WorldNode requires :world-manager"))
  (local asset-path-resolver options.asset-path-resolver)
  (local world-entry (or options.world-entry
                          (WorldData.resolve-world-entry world-manager world-id)))
  (assert world-entry (.. "WorldNode could not resolve world: " world-id))
  (local key (or options.key (.. "world:" world-id)))
  (local name (or (and world-entry world-entry.name) world-id))
  (local node (GraphNode {:key key
                          :label name
                          :color (glm.vec4 0.8 0.6 0.2 1)
                          :sub-color (glm.vec4 0.7 0.5 0.1 1)
                          :size 8.0
                          :view WorldNodeView}))
  (set node.world-id world-id)
  (set node.world-manager world-manager)
  (set node.asset-path-resolver asset-path-resolver)
  (set node.world-entry world-entry)
  (set node.changed (Signal))
  (set node.categories-changed (Signal))
  (fn emit-categories [self]
    (local categories
      [{:key "activities" :label "activities" :kind WorldActivitiesNode}])
    (when self.categories-changed
      (self.categories-changed:emit categories))
    categories)
  (set node.emit-categories emit-categories)
  (set node.add-category-node
       (fn [self category]
          (local graph self.graph)
          (when (and graph category category.kind)
            (local category-node (category.kind {:world-id self.world-id
                                                :world-manager self.world-manager
                                                :asset-path-resolver self.asset-path-resolver
                                                :key (.. "world-activities:" self.world-id)}))
            (graph:add-edge (GraphEdge {:source self :target category-node})))))
  (set node.activate
       (fn [self]
         (local tabs (self.world-manager:list-tabs))
         (var target-idx nil)
         (each [_ tab (ipairs tabs)]
           (when (and (not target-idx) (= tab.id self.world-id))
             (set target-idx tab.index)))
         (when target-idx
           (self.world-manager:activate-index target-idx))))
  (set node.close
       (fn [self]
         (local tabs (self.world-manager:list-tabs))
         (var target-idx nil)
         (each [_ tab (ipairs tabs)]
           (when (and (not target-idx) (= tab.id self.world-id))
             (set target-idx tab.index)))
         (when target-idx
           (self.world-manager:close-world-index target-idx))))
  (set node.actions
       [{:name "Activate"
         :icon "play_arrow"
         :fn (fn [_button _event]
               (node:activate))}
        {:name "Close"
         :icon "close"
         :fn (fn [_button _event]
               (node:close))}])
  (var changed-handler nil)
  (set changed-handler
       (world-manager.changed:connect
         (fn [_payload]
           (local entry (WorldData.resolve-world-entry world-manager world-id))
           (if entry
               (set node.world-entry entry)
               (when (and node.graph node.graph.remove-nodes)
                  (node.graph:remove-nodes [node] {:cause "shared-delete"}))))))
  (set node.drop
       (fn [self]
         (when changed-handler
           (world-manager.changed:disconnect changed-handler true)
           (set changed-handler nil))
         (when self.changed
           (self.changed:clear))
         (when self.categories-changed
           (self.categories-changed:clear))))
  node)

M
