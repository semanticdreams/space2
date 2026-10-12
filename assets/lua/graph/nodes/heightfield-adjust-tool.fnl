(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local HeightfieldTerrainData (require :heightfield-terrain-data))
(local HeightfieldAdjustToolNodeView (require :graph/view/views/heightfield-adjust-tool))
(local WorldData (require :graph/world-data))

(local M {})

(fn M.HeightfieldAdjustToolNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "HeightfieldAdjustToolNode requires :world-id"))
  (local activity-id (assert options.activity-id "HeightfieldAdjustToolNode requires :activity-id"))
  (local world-manager (assert options.world-manager "HeightfieldAdjustToolNode requires :world-manager"))
  (local terrain-id (assert options.terrain-id "HeightfieldAdjustToolNode requires :terrain-id"))
  (local key (or options.key (.. "activity-terrain-tool:" world-id ":" activity-id ":" terrain-id ":adjust-height")))
  (local node (GraphNode {:key key
                          :label "raise/lower"
                          :color (glm.vec4 0.52 0.44 0.29 1)
                          :sub-color (glm.vec4 0.38 0.31 0.19 1)
                          :size 8.0
                          :view HeightfieldAdjustToolNodeView}))
  (set node.world-id world-id)
  (set node.activity-id activity-id)
  (set node.world-manager world-manager)
  (set node.terrain-id terrain-id)
  (set node.terrain-kind "heightfield-terrain")
  (set node.changed (Signal))
  (set node.get-record
       (fn [self]
          (local resolved (WorldData.find-terrain self.world-manager self.world-id self.activity-id self.terrain-id))
         (or (and resolved resolved.record) {})))
  (set node.get-live-scene
       (fn [self]
         (WorldData.resolve-active-scene self.world-manager self.world-id)))
  (set node.get-selection-target
       (fn [self]
         (WorldData.get-terrain-selection-target self.world-manager self.world-id self.terrain-id)))
  (set node.set-selection-target
       (fn [self target]
         (WorldData.set-terrain-selection-target self.world-manager self.world-id self.terrain-id target)))
  (set node.clear-selection-target
       (fn [self]
         (WorldData.clear-terrain-selection-target self.world-manager self.world-id self.terrain-id)))
  (set node.apply-values
       (fn [self validated]
         (local updated
            (WorldData.update-terrain-record self.world-manager self.world-id self.activity-id self.terrain-id
             (fn [record]
               (HeightfieldTerrainData.adjust-record! record validated.delta validated.target))))
         (when updated
           (self.changed:emit updated))
         updated))
  (set node.apply-stroke-values
       (fn [self validated]
         (local updated
            (WorldData.update-terrain-record self.world-manager self.world-id self.activity-id self.terrain-id
             (fn [record]
               (HeightfieldTerrainData.adjust-record-targets! record validated.delta validated.targets))))
         (when updated
           (self.changed:emit {:reason :live-stroke-applied
                               :terrain-id self.terrain-id
                               :target-count (length (or validated.targets []))}))
         updated))
  (set node.drop
       (fn [self]
         (when self.changed
           (self.changed:clear))))
  node)

{:HeightfieldAdjustToolNode M.HeightfieldAdjustToolNode}
