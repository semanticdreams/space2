(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local HeightfieldTerrainData (require :heightfield-terrain-data))
(local HeightfieldFlatToolNodeView (require :graph/view/views/heightfield-flat-tool))
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

(fn M.HeightfieldFlatToolNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "HeightfieldFlatToolNode requires :world-id"))
  (local activity-id (assert options.activity-id "HeightfieldFlatToolNode requires :activity-id"))
  (local world-manager (assert options.world-manager "HeightfieldFlatToolNode requires :world-manager"))
  (local terrain-id (assert options.terrain-id "HeightfieldFlatToolNode requires :terrain-id"))
  (local key (or options.key (.. "activity-terrain-tool:" world-id ":" activity-id ":" terrain-id ":initialize-flat")))
  (local node (GraphNode {:key key
                          :label "initialize flat"
                          :color (glm.vec4 0.36 0.53 0.37 1)
                          :sub-color (glm.vec4 0.24 0.39 0.25 1)
                          :size 8.0
                          :view HeightfieldFlatToolNodeView}))
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
               (HeightfieldTerrainData.fill-record! record validated.height validated.target))))
        (when updated
          (self.changed:emit (clone-table updated)))
        updated))
  (set node.drop
       (fn [self]
         (when self.changed
           (self.changed:clear))))
  node)

{:HeightfieldFlatToolNode M.HeightfieldFlatToolNode}
