(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local HudPanelNodeView (require :graph/view/views/hud-panel))
(local WorldData (require :graph/world-data))

(local M {})

(fn M.HudPanelNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "HudPanelNode requires :world-id"))
  (local world-manager (assert options.world-manager "HudPanelNode requires :world-manager"))
  (local layer (assert options.layer "HudPanelNode requires :layer"))
  (local panel-index (assert options.panel-index "HudPanelNode requires :panel-index"))
  (local resolved (or options.panel-entry
                      (WorldData.find-hud-panel world-manager world-id layer panel-index)
                      {}))
  (local panel (or options.panel resolved.metadata {}))
  (local panel-record (or options.panel-record resolved.panel {}))
  (local persistence (or panel.persistence panel-record {}))
  (local panel-kind (or persistence.kind resolved.kind "unknown"))
  (local key (or options.key (.. "hud-panel:" world-id ":" layer ":" panel-index)))
  (local label (or options.label (.. panel-kind " (" layer ")")))
  (local node (GraphNode {:key key
                           :label label
                           :color (glm.vec4 0.5 0.7 0.6 1)
                           :sub-color (glm.vec4 0.4 0.6 0.5 1)
                           :size 8.0
                           :view HudPanelNodeView}))
  (set node.world-id world-id)
  (set node.world-manager world-manager)
  (set node.layer layer)
  (set node.panel-index panel-index)
  (set node.panel-kind panel-kind)
  (set node.panel panel)
  (set node.panel-record panel-record)
  (set node.changed (Signal))
  (set node.remove-panel
       (fn [self]
         (WorldData.remove-hud-panel self.world-manager self.world-id self.layer self.panel-index)))
  (set node.actions
        [{:name "Delete HUD Panel"
         :icon "delete"
         :fn (fn [_button _event]
               (when (node:remove-panel)
                  (when (and node.graph node.graph.remove-nodes)
                    (node.graph:remove-nodes [node] {:cause "shared-delete"}))))}])
  (var changed-handler nil)
  (set changed-handler
       (world-manager.changed:connect
         (fn [_payload]
            (local current (WorldData.find-hud-panel world-manager world-id layer panel-index))
            (local stale?
              (or (not current)
                  (and node.panel current.metadata (not (= current.metadata node.panel)))
                  (and node.panel-record current.panel (not (= current.panel node.panel-record)))))
            (when stale?
              (when (and node.graph node.graph.remove-nodes)
                (node.graph:remove-nodes [node] {:cause "shared-delete"}))))))
  (set node.drop
       (fn [self]
         (when changed-handler
           (world-manager.changed:disconnect changed-handler true)
           (set changed-handler nil))
         (when self.changed
           (self.changed:clear))))
  node)

M
