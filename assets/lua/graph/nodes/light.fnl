(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local LightNodeView (require :graph/view/views/light))
(local WorldData (require :graph/world-data))

(local M {})

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn light-label [type-key light-id]
  (if (= type-key "ambient")
      "ambient"
      (.. type-key " [" light-id "]")))

(fn remove-from-graph [node]
  (when (and node.graph node.graph.remove-nodes)
    (node.graph:remove-nodes [node] {:cause "shared-delete"})))

(fn refresh-light-node [node]
  (if (not (WorldData.resolve-activity-surface-state node.world-manager node.world-id node.activity-id "scene"))
      (remove-from-graph node)
      (do
        (local current (WorldData.find-light node.world-manager node.world-id node.activity-id node.type-key node.light-id))
        (if current
            (do
              (set node.light-record (clone-table current.record))
              (set node.label (light-label node.type-key node.light-id))
              (node.changed:emit node.light-record))
            (remove-from-graph node)))))

(fn M.LightNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "LightNode requires :world-id"))
  (local activity-id (assert options.activity-id "LightNode requires :activity-id"))
  (local world-manager (assert options.world-manager "LightNode requires :world-manager"))
  (local type-key (assert options.type-key "LightNode requires :type-key"))
  (local light-id (assert options.light-id "LightNode requires :light-id"))
  (local resolved (or options.light-entry
                       (WorldData.find-light world-manager world-id activity-id type-key light-id)
                      {}))
  (local light-record (or options.light-record resolved.record {}))
  (local key (or options.key (.. "activity-light:" world-id ":" activity-id ":" type-key ":" light-id)))
  (local node (GraphNode {:key key
                          :label (light-label type-key light-id)
                          :color (glm.vec4 0.82 0.7 0.26 1)
                          :sub-color (glm.vec4 0.64 0.52 0.16 1)
                          :size 8.0
                          :view LightNodeView}))
  (set node.world-id world-id)
  (set node.activity-id activity-id)
  (set node.world-manager world-manager)
  (set node.type-key type-key)
  (set node.light-id light-id)
  (set node.light-record (clone-table light-record))
  (set node.changed (Signal))
  (set node.get-record
       (fn [self]
         (or self.light-record {})))
  (set node.update-record
       (fn [self updater]
         (local updated
           (WorldData.update-light-record self.world-manager
                                           self.world-id
                                           self.activity-id
                                           self.type-key
                                          self.light-id
                                          updater))
         (when updated
           (set self.light-record updated))
         updated))
  (fn apply-light-values [self validated]
    (self:update-record
      (fn [record]
        (set record.enabled? validated.enabled)
        (if (= self.type-key "ambient")
            (set record.color validated.color)
            (do
              (when validated.position
                (set record.position validated.position))
              (when validated.direction
                (set record.direction validated.direction))
              (when validated.ambient
                (set record.ambient validated.ambient))
              (when validated.diffuse
                (set record.diffuse validated.diffuse))
              (when validated.specular
                (set record.specular validated.specular))
              (when (not (= validated.specular-power nil))
                (set record.specular-power validated.specular-power))
              (when (not (= validated.cutoff nil))
                (set record.cutoff validated.cutoff))
              (when (not (= validated.outer-cutoff nil))
                (set record.outer-cutoff validated.outer-cutoff))
              (when (not (= validated.constant nil))
                (set record.constant validated.constant))
              (when (not (= validated.linear nil))
                (set record.linear validated.linear))
              (when (not (= validated.quadratic nil))
                (set record.quadratic validated.quadratic)))))))
  (set node.apply-values
       apply-light-values)
  (set node.remove-light
       (fn [self]
          (WorldData.remove-light self.world-manager self.world-id self.activity-id self.type-key self.light-id)))
  (set node.removable?
       (fn [self]
         (not (= self.type-key "ambient"))))
  (set node.actions
       (if (= type-key "ambient")
           []
            [{:name "Delete Light"
             :fn (fn [_button _event]
                   (assert (node:remove-light)
                           (.. "Failed to remove light " node.light-id))
                    (when (and node.graph node.graph.remove-nodes)
                      (node.graph:remove-nodes [node] {:cause "shared-delete"})))}]))
  (var changed-handler nil)
  (set changed-handler
       (world-manager.changed:connect
          (fn [_payload]
            (refresh-light-node node))))
  (set node.drop
       (fn [self]
         (when changed-handler
           (world-manager.changed:disconnect changed-handler true)
           (set changed-handler nil))
         (when self.changed
           (self.changed:clear))))
  node)

M
