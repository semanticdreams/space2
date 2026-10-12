(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local ScenePanelNodeView (require :graph/view/views/scene-panel))
(local WorldData (require :graph/world-data))

(local M {})

(fn M.ScenePanelNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "ScenePanelNode requires :world-id"))
  (local activity-id (assert options.activity-id "ScenePanelNode requires :activity-id"))
  (local world-manager (assert options.world-manager "ScenePanelNode requires :world-manager"))
  (local panel-index (assert options.panel-index "ScenePanelNode requires :panel-index"))
  (local resolved (or options.panel-entry
                       (WorldData.find-scene-panel world-manager world-id activity-id panel-index)
                      {}))
  (local panel (or options.panel resolved.metadata {}))
  (local panel-record (or options.panel-record resolved.panel {}))
  (local persistence (or panel.persistence panel-record {}))
  (local panel-kind (or persistence.kind resolved.kind "unknown"))
  (local key (or options.key (.. "activity-scene-panel:" world-id ":" activity-id ":" panel-index)))
  (local label (or options.label panel-kind))
  (local node (GraphNode {:key key
                           :label label
                           :color (glm.vec4 0.6 0.5 0.8 1)
                           :sub-color (glm.vec4 0.5 0.4 0.7 1)
                           :size 8.0
                           :view ScenePanelNodeView}))
  (set node.world-id world-id)
  (set node.activity-id activity-id)
  (set node.world-manager world-manager)
  (set node.panel-index panel-index)
  (set node.panel-kind panel-kind)
  (set node.panel panel)
  (set node.panel-record panel-record)
  (set node.changed (Signal))
  (set node.remove-panel
       (fn [self]
          (WorldData.remove-scene-panel self.world-manager self.world-id self.activity-id self.panel-index)))
  (set node.actions
        [{:name "Delete Scene Panel"
         :icon "delete"
         :fn (fn [_button _event]
                (when (node:remove-panel)
                   (when (and node.graph node.graph.remove-nodes)
                     (node.graph:remove-nodes [node] {:cause "shared-delete"}))))}])
  (fn remove-self []
    (when (and node.graph node.graph.remove-nodes)
      (node.graph:remove-nodes [node] {:cause "shared-delete"})))
  (fn refresh-or-remove []
    (if (not (WorldData.resolve-activity-surface-state world-manager world-id activity-id "scene"))
        (remove-self)
        (do
          (local current (WorldData.find-scene-panel world-manager world-id activity-id panel-index))
          (local stale?
            (or (not current)
                (and node.panel current.metadata (not (= current.metadata node.panel)))
                (and node.panel-record current.panel (not (= current.panel node.panel-record)))))
          (when stale?
            (remove-self)))))
  (var changed-handler nil)
  (set changed-handler
       (world-manager.changed:connect
         (fn [_payload]
           (refresh-or-remove))))
  (set node.drop
       (fn [self]
         (when changed-handler
           (world-manager.changed:disconnect changed-handler true)
           (set changed-handler nil))
         (when self.changed
           (self.changed:clear))))
  node)

M
