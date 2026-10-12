(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local TerrainIssueLog (require :terrain-issue-log))
(local Signal (require :signal))
(local HeightfieldTerrainData (require :heightfield-terrain-data))
(local HeightfieldTerrainSpace (require :heightfield-terrain-space))
(local HeightfieldResizeToolNodeView (require :graph/view/views/heightfield-resize-tool))
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

(fn chunk-summary [record]
  (local chunks (or (and record record.chunks) []))
  (if (= (length chunks) 0)
      "count=0 coords=[]"
      (do
        (local coords
          (icollect [_ chunk (ipairs chunks)]
            (do
              (local coord (or chunk.coord [0 0]))
              (.. "[" (tostring (or (. coord 1) coord.x 0))
                  "," (tostring (or (. coord 2) coord.y coord.z 0)) "]"))))
        (.. "count=" (tostring (length chunks))
            " coords=" (table.concat coords " ")))))

(fn M.HeightfieldResizeToolNode [opts]
  (local options (or opts {}))
  (local world-id (assert options.world-id "HeightfieldResizeToolNode requires :world-id"))
  (local activity-id (assert options.activity-id "HeightfieldResizeToolNode requires :activity-id"))
  (local world-manager (assert options.world-manager "HeightfieldResizeToolNode requires :world-manager"))
  (local terrain-id (assert options.terrain-id "HeightfieldResizeToolNode requires :terrain-id"))
  (local key (or options.key (.. "activity-terrain-tool:" world-id ":" activity-id ":" terrain-id ":resize-terrain")))
  (local node (GraphNode {:key key
                          :label "resize terrain"
                          :color (glm.vec4 0.37 0.48 0.58 1)
                          :sub-color (glm.vec4 0.25 0.35 0.44 1)
                          :size 8.0
                          :view HeightfieldResizeToolNodeView}))
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
  (set node.apply-values
       (fn [self validated]
         (TerrainIssueLog.info
           (string.format
             "[terrain-resize] apply terrain=%s world=%s requested-chunks=[%d,%d..%d,%d] fill-height=%s"
             self.terrain-id
             self.world-id
             validated.min-chunk-x
             validated.min-chunk-z
             validated.max-chunk-x
             validated.max-chunk-z
             (tostring validated.fill-height)))
         (local updated
            (WorldData.update-terrain-record self.world-manager self.world-id self.activity-id self.terrain-id
             (fn [record]
               (TerrainIssueLog.info
                 (string.format
                   "[terrain-resize] before terrain=%s chunks=%s"
                   self.terrain-id
                   (chunk-summary record)))
               (HeightfieldTerrainData.resize-record! record validated)
               (TerrainIssueLog.info
                 (string.format
                   "[terrain-resize] after terrain=%s chunks=%s"
                   self.terrain-id
                   (chunk-summary record))))))
         (when updated
           (self.changed:emit (clone-table updated)))
         updated))
  (set node.apply-values-centered-on-origin
       (fn [self validated]
         (TerrainIssueLog.info
           (string.format
             "[terrain-resize] apply-centered terrain=%s world=%s requested-chunks=[%d,%d..%d,%d] fill-height=%s"
             self.terrain-id
             self.world-id
             validated.min-chunk-x
             validated.min-chunk-z
             validated.max-chunk-x
             validated.max-chunk-z
             (tostring validated.fill-height)))
         (local updated
            (WorldData.update-terrain-record self.world-manager self.world-id self.activity-id self.terrain-id
             (fn [record]
               (TerrainIssueLog.info
                 (string.format
                   "[terrain-resize] before-centered terrain=%s chunks=%s"
                   self.terrain-id
                   (chunk-summary record)))
               (HeightfieldTerrainData.resize-record! record validated)
               (local centered-record (HeightfieldTerrainSpace.record-centered-on-origin-xz record))
               (set record.options centered-record.options)
               (TerrainIssueLog.info
                 (string.format
                   "[terrain-resize] after-centered terrain=%s chunks=%s position=[%s,%s,%s]"
                   self.terrain-id
                   (chunk-summary record)
                   (tostring (. record.options.position 1))
                   (tostring (. record.options.position 2))
                   (tostring (. record.options.position 3)))))))
         (when updated
           (self.changed:emit (clone-table updated)))
         updated))
  (set node.drop
       (fn [self]
         (when self.changed
           (self.changed:clear))))
  node)

{:HeightfieldResizeToolNode M.HeightfieldResizeToolNode}
