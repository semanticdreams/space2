(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local LightSystemModule (require :light-system))
(local LightTypeNodeView (require :graph/view/views/light-type))
(local {:LightNode LightNode} (require :graph/nodes/light))
(local WorldData (require :graph/world-data))

(local M {})

(fn light-node-key [self light-id]
  (.. "activity-light:" self.world-id ":" self.activity-id ":" self.type-key ":" light-id))

(fn M.LightTypeNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "LightTypeNode requires :world-id"))
  (local activity-id (assert options.activity-id "LightTypeNode requires :activity-id"))
  (local world-manager (assert options.world-manager "LightTypeNode requires :world-manager"))
  (local type-key (assert options.type-key "LightTypeNode requires :type-key"))
  (local spec (assert (LightSystemModule.type-spec type-key)
                      (.. "LightTypeNode unsupported type " (tostring type-key))))
  (local key (or options.key (.. "activity-light-type:" world-id ":" activity-id ":" type-key)))
  (local node (GraphNode {:key key
                          :label spec.label
                          :color (glm.vec4 0.78 0.68 0.28 1)
                          :sub-color (glm.vec4 0.62 0.5 0.18 1)
                          :size 8.0
                          :view LightTypeNodeView}))
  (set node.world-id world-id)
  (set node.activity-id activity-id)
  (set node.world-manager world-manager)
  (set node.type-key type-key)
  (set node.light-spec spec)
  (set node.items-changed (Signal))
  (set node.collect-items
       (fn [self]
          (WorldData.list-lights self.world-manager self.world-id self.activity-id self.type-key)))
  (set node.emit-items
       (fn [self]
         (local items (self:collect-items))
         (self.items-changed:emit items)
         items))
  (set node.show-add-controls?
       (fn [self]
         (not (= self.type-key "ambient"))))
  (set node.can-add-light?
       (fn [self]
         (if (not (self:show-add-controls?))
             false
             (do
               (local count (length (self:collect-items)))
               (< count (. self.light-spec :max-count))))))
  (set node.limit-error-text
       (fn [self]
         (if (or (not (self:show-add-controls?))
                 (self:can-add-light?))
             ""
             (.. "Reached max " self.type-key " lights: "
                 (tostring (. self.light-spec :max-count))))))
  (set node.open-light-node
       (fn [self entry]
         (local graph self.graph)
         (when (and graph entry entry.light-id)
           (local light-node
              (LightNode {:world-id self.world-id
                           :activity-id self.activity-id
                           :world-manager self.world-manager
                          :type-key self.type-key
                          :light-id entry.light-id
                          :light-record entry.record
                          :key (light-node-key self entry.light-id)}))
           (graph:add-edge (GraphEdge {:source self
                                       :target light-node})))))
  (set node.add-light
       (fn [self]
         (assert (self:show-add-controls?)
                 "Ambient light is a required singleton and cannot be added")
         (assert (self:can-add-light?)
                 (self:limit-error-text))
          (WorldData.add-light self.world-manager self.world-id self.activity-id self.type-key)))
  (set node.actions
       [{:name "Refresh"
         :icon "refresh"
         :fn (fn [_button _event]
               (node:emit-items))}])
  (var changed-handler nil)
  (set changed-handler
        (world-manager.changed:connect
          (fn [payload]
            (if (WorldData.resolve-activity-surface-state world-manager world-id activity-id "scene")
                (do
                  (local items (node:collect-items))
                  (node.items-changed:emit items))
                (when (and node.graph node.graph.remove-nodes)
                  (node.graph:remove-nodes [node] {:cause "shared-delete"}))))))
  (set node.drop
       (fn [self]
         (when changed-handler
           (world-manager.changed:disconnect changed-handler true)
           (set changed-handler nil))
         (when self.items-changed
           (self.items-changed:clear))))
  node)

M
