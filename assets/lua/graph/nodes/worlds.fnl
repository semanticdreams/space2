(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local WorldsNodeView (require :graph/view/views/worlds))
(local {:WorldNode WorldNode} (require :graph/nodes/world))
(local WorldData (require :graph/world-data))

(local M {})

(fn M.WorldsNode [opts]
  (local options (or opts {}))
  (local world-manager (assert options.world-manager "WorldsNode requires :world-manager"))
  (local asset-path-resolver options.asset-path-resolver)
  (local key (or options.key "worlds"))
  (local node (GraphNode {:key key
                           :label "worlds"
                           :color (glm.vec4 0.75 0.55 0.15 1)
                           :sub-color (glm.vec4 0.65 0.45 0.05 1)
                           :size 8.0
                           :view WorldsNodeView}))
  (set node.world-manager world-manager)
  (set node.asset-path-resolver asset-path-resolver)
  (set node.items-changed (Signal))
  (fn collect-items [self]
    (local tabs (self.world-manager:list-tabs))
    (local produced [])
    (each [_ tab (ipairs tabs)]
      (local label (.. tab.name (if tab.active? " (active)" "")))
      (table.insert produced [tab label]))
    produced)
  (fn emit-items [self]
    (local items (collect-items self))
    (self.items-changed:emit items)
    items)
  (set node.collect-items collect-items)
  (set node.emit-items emit-items)
  (set node.add-world-node
       (fn [self tab]
         (local graph self.graph)
         (when (and graph tab tab.id)
           (local world-node (WorldNode {:world-id tab.id
                                         :world-manager self.world-manager
                                         :asset-path-resolver self.asset-path-resolver
                                         :world-entry (or (WorldData.resolve-world-entry self.world-manager tab.id)
                                                          tab)}))
           (graph:add-edge (GraphEdge {:source self
                                       :target world-node})))))
  (set node.create-world
       (fn [self opts]
         (local create-opts (or opts {}))
         (self.world-manager:create-home-world create-opts)))
  (set node.actions
       [{:name "Refresh"
         :icon "refresh"
         :fn (fn [_button _event]
               (node:emit-items))}
        {:name "New World"
         :icon "add"
         :fn (fn [_button _event]
               (node:create-world {}))}])
  (var changed-handler nil)
  (set changed-handler
       (world-manager.changed:connect
         (fn [_payload]
           (node:emit-items))))
  (set node.drop
       (fn [self]
         (when changed-handler
           (world-manager.changed:disconnect changed-handler true)
           (set changed-handler nil))
         (when self.items-changed
           (self.items-changed:clear))))
  node)

M
