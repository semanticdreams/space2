(local glm (require :glm))
(local NodeBase (require :graph/node-base))
(local Utils (require :graph/view/utils))
(local logging (require :logging))
(local GraphEdgeBatch (require :graph-edge-batch))
(local Text (require :text))
(local TextStyle (require :text-style))

(local node-id NodeBase.node-id)
(local ensure-glm-vec3 Utils.ensure-glm-vec3)
(local ensure-glm-vec4 Utils.ensure-glm-vec4)

(local position-epsilon 1e-4)
(local position-magnitude-threshold 1e6)

(local {:ForceLayout ForceLayout :ForceLayoutSignal ForceLayoutSignal} (require :force-layout))
(fn GraphViewLayout [opts]
    (local options (or opts {}))
    (local layout (or options.layout (ForceLayout)))
    (local nodes-by-index (or options.nodes-by-index []))
    (local indices (or options.indices {}))
    (local nodes (or options.nodes {}))
    (local points (or options.points {}))
    (local edges (or options.edges []))
    (local edge-map (or options.edge-map {}))
    (local pinned (or options.pinned {}))
    (local make-line options.make-line)
    (local ctx options.ctx)
    (local base-edge-thickness (or options.edge-thickness 2.0))
    (local default-edge-color (ensure-glm-vec4 options.edge-color (glm.vec4 0.6 0.6 0.6 1)))
    (local label-color (ensure-glm-vec4 options.label-color (glm.vec4 0.8 0.8 0.8 1)))
    (local label-depth-offset (or options.label-depth-offset 1.0))
    (local label-scale (or options.label-scale 2.5))
    (local edge-key (or options.edge-key
                        (fn [edge]
                            (.. (node-id edge.source) "->" (node-id edge.target)))))
    (local set-point-position (or options.set-point-position
                                  (fn [_node _pos] nil)))
    (local update-labels (or options.update-labels (fn [_nodes _opts] nil)))
    (local refresh-label-positions (or options.refresh-label-positions (fn [_nodes] nil)))
    (local get-position (or options.get-position
                            (fn [_self _node]
                                (error "GraphViewLayout requires get-position callback"))))
     (local get-position-raw (or options.get-position-raw get-position))
     (local on-island-position (or options.on-island-position (fn [_id _position] nil)))
     (local force-indices {})
     (local force-participants-by-index [])
     (local island-layouts {})
     (local island-member-layouts {})

    (fn assert-valid-position [pos context node]
        (local key (and node node.key))
        (fn finite-number? [v]
            (and (= (type v) :number)
                 (= v v)
                 (not (= v math.huge))
                 (not (= v (- math.huge)))))
        (when (or (not pos)
                  (not (finite-number? pos.x))
                  (not (finite-number? pos.y))
                  (not (finite-number? pos.z)))
            (error (string.format "GraphViewLayout received non-finite position in %s for %s"
                                  context
                                  (or key "unknown node"))))
        (local magnitude (glm.length pos))
        (when (> magnitude position-magnitude-threshold)
            (logging.error (string.format "[graph-view] refusing position magnitude %.3f for %s (%s) in %s"
                                          magnitude
                                          (or key "unknown node")
                                          (node-id node)
                                          context))
            (error (string.format "GraphViewLayout position magnitude %.3f exceeds threshold %.0f for %s (%s)"
                                  magnitude
                                  position-magnitude-threshold
                                  context
                                  (or key "unknown node")))))

     (fn position-changed? [current new-pos]
         (or (not current)
             (> (glm.length (- current new-pos)) position-epsilon)))

     (fn vec3-like? [position]
         (and position
              (= (type position.x) :number)
              (= (type position.y) :number)
              (= (type position.z) :number)))

     (fn validate-island-layout-record [record]
         (assert (= (type record) :table) "GraphViewLayout.sync-island-layouts requires table records")
         (assert (= (type record.id) :string) "GraphViewLayout island layout record requires string id")
         (assert (= (type record.members) :table) "GraphViewLayout island layout record requires members table")
         (assert (vec3-like? record.position) "GraphViewLayout island layout record requires vec3-like position")
         (assert (= (type record.member-placements) :function)
                 "GraphViewLayout island layout record requires member-placements function")
         record)

     (fn clear-force-tables []
         (each [k _ (pairs force-indices)]
             (set (. force-indices k) nil))
         (each [k _ (pairs force-participants-by-index)]
             (set (. force-participants-by-index k) nil)))

     (fn clear-island-member-layouts []
         (each [k _ (pairs island-member-layouts)]
             (set (. island-member-layouts k) nil)))

     (fn active-island-member? [node]
         (and node (not (. pinned node)) (. island-member-layouts node)))

     (fn force-index-for-node [node]
         (local island-record (active-island-member? node))
         (if island-record
             (. force-indices island-record)
             (. force-indices node)))

     (fn add-force-node [participant position pinned?]
         (local idx (layout:add-node position))
         (assert (not (= idx nil)) "GraphViewLayout failed to allocate force layout index")
         (set (. force-participants-by-index (+ idx 1)) participant)
         (if (= participant.kind :island)
             (set (. force-indices participant.record) idx)
             (set (. force-indices participant.node) idx))
         (when pinned?
             (layout:pin-node idx true))
         idx)

     (fn add-force-edge [source-node target-node]
         (local source-idx (force-index-for-node source-node))
         (local target-idx (force-index-for-node target-node))
         (when (and source-idx target-idx (not (= source-idx target-idx)))
             (layout:add-edge source-idx target-idx true)))

     (fn allocate-public-index []
         (var max-index -1)
         (each [_ idx (pairs indices)]
             (when (and (= (type idx) :number) (> idx max-index))
                 (set max-index idx)))
         (+ max-index 1))

    (local self {:layout layout
                 :nodes-by-index nodes-by-index
                 :indices indices
                 :nodes nodes
                 :points points
                 :edges edges
                 :edge-map edge-map})

     (fn refresh-layout []
         (local positions (layout:get-positions))
         (local count (length positions))
         (local changed [])
         (for [i 1 count]
             (local participant (. force-participants-by-index i))
             (when participant
                 (local pos (. positions i))
                 (when pos
                     (local new-pos (ensure-glm-vec3 pos))
                     (if (= participant.kind :island)
                         (do
                             (assert-valid-position new-pos "GraphViewLayout.refresh-layout:island" nil)
                             (local record participant.record)
                             (when (position-changed? record.position new-pos)
                                 (set record.position new-pos)
                                 (on-island-position record.id new-pos)
                                 (local placements (record.member-placements new-pos))
                                 (each [_ member (ipairs record.members)]
                                     (when (not (. pinned member))
                                         (local placement (or (. placements member.key) (. placements (node-id member))))
                                         (assert placement
                                                 (string.format "GraphViewLayout.refresh-layout missing island placement for node %s"
                                                               (node-id member)))
                                         (assert-valid-position placement "GraphViewLayout.refresh-layout:island" member)
                                         (local point (. points member))
                                         (assert point (string.format "GraphViewLayout.refresh-layout missing point for island member %s"
                                                              (node-id member)))
                                         (when (position-changed? point.position placement)
                                             (set-point-position member placement "GraphViewLayout.refresh-layout:island")
                                             (table.insert changed member))))))
                         (do
                             (local node participant.node)
                             (assert-valid-position new-pos "GraphViewLayout.refresh-layout" node)
                             (local point (. points node))
                             (assert point (string.format "GraphViewLayout.refresh-layout missing point for node %s"
                                                          (node-id node)))
                             (when (position-changed? point.position new-pos)
                                 (set-point-position node new-pos "GraphViewLayout.refresh-layout")
                                 (table.insert changed node)))))))
         changed)

    (fn flush-batch [batch]
        (when (and batch.vector (> (length batch.handles) 0))
            (GraphEdgeBatch.write-triangle-batch
                batch.vector
                batch.handles
                batch.starts
                batch.ends
                batch.colors
                batch.thicknesses
                batch.depths)
            (set batch.handles [])
            (set batch.starts [])
            (set batch.ends [])
            (set batch.colors [])
            (set batch.thicknesses [])
            (set batch.depths [])
            (set batch.vector nil)))

    (fn queue-batch [batch line start-pos end-pos]
        (when line
            (if (and batch.vector (not (= batch.vector line.vector)))
                (flush-batch batch)
                (when (not batch.vector)
                    (set batch.vector line.vector)))
            (table.insert batch.handles line.handle)
            (table.insert batch.starts start-pos)
            (table.insert batch.ends end-pos)
            (table.insert batch.colors line.color)
            (table.insert batch.thicknesses line.thickness)
            (table.insert batch.depths line.depth-offset)))

    (fn place-edge-label [span start-pos end-pos]
        (when span
            (local midpoint (* (+ start-pos end-pos) 0.5))
            (local measure (or span.layout.measure (glm.vec3 0 0 0)))
            (local offset (glm.vec3 (- (/ measure.x 2.0))
                                    (- (- measure.y) 1.0)
                                    0.05))
            (set span.layout.depth-offset-index label-depth-offset)
            (set span.layout.position (+ midpoint offset))
            (set span.layout.rotation (glm.quat 1 0 0 0))
            (span.layout:layouter)))

    (fn create-edge-label [text]
        (local builder (Text {:text text
                              :style (TextStyle {:color label-color
                                                 :scale label-scale})}))
        (local span (builder ctx))
        (span.layout:measurer)
        span)

    (fn drop-edge-label [record]
        (when record.label-span
            (record.label-span:drop)
            (set record.label-span nil)))

    (fn update-line-record [record batch]
        (local edge record.edge)
        (local line record.line)
        (assert edge "Graph edge record missing edge")
        (assert line (string.format "Graph edge %s missing line handle"
                                    (node-id edge.source)))
        (local start-pos (get-position-raw self edge.source))
        (local end-pos (get-position-raw self edge.target))
        (assert start-pos
                (string.format "Graph edge %s->%s missing start position"
                               (node-id edge.source)
                               (node-id edge.target)))
        (assert end-pos
                (string.format "Graph edge %s->%s missing end position"
                               (node-id edge.source)
                               (node-id edge.target)))
        (if (and GraphEdgeBatch line.vector line.color line.thickness line.depth-offset)
            (do
                (line:prepare-batch start-pos end-pos)
                (when line.handle
                    (queue-batch batch line start-pos end-pos)))
            (line:update start-pos end-pos))
        (when record.label-span
            (place-edge-label record.label-span start-pos end-pos)))

    (fn update-lines []
        (local batch {:handles []
                      :starts []
                      :ends []
                      :colors []
                      :thicknesses []
                      :depths []
                      :vector nil})
        (each [_ record (ipairs edges)]
            (update-line-record record batch))
        (flush-batch batch))

    (fn start []
        (layout:start)
        (update-lines)
        self)

      (fn add-node [_self node position pinned?]
          (assert-valid-position position "GraphViewLayout.add-node" node)
          (add-force-node {:kind :node :node node} position pinned?)
          (local public-idx (allocate-public-index))
          (set (. nodes-by-index (+ public-idx 1)) node)
          (set (. indices node) public-idx)
          public-idx)

    (fn add-edge [_self edge]
        (assert edge "GraphViewLayout.add-edge requires an edge")
        (assert make-line "GraphViewLayout.add-edge requires make-line callback")
         (local source-idx (force-index-for-node edge.source))
         (local target-idx (force-index-for-node edge.target))
         (assert (and source-idx target-idx)
                 "GraphViewLayout.add-edge requires indexed source and target nodes")
         (when (not (= source-idx target-idx))
             (layout:add-edge source-idx target-idx true))
        (local source-size (or (and edge edge.source edge.source.size) 0))
        (local target-size (or (and edge edge.target edge.target.size) 0))
        (local min-node-size (math.min source-size target-size))
        (local scaled-edge-thickness
               (if (> min-node-size 0)
                   (math.max base-edge-thickness (* min-node-size 0.35))
                   base-edge-thickness))
        (local line (make-line ctx {:color (ensure-glm-vec4 edge.color default-edge-color)
                                    :thickness scaled-edge-thickness
                                    :label (edge-key edge)}))
        (assert line (string.format "GraphViewLayout.add-edge failed to create line for %s->%s"
                                    (node-id edge.source)
                                    (node-id edge.target)))
        (local record {:edge edge :line line})
        (when (and ctx edge.label (> (string.len edge.label) 0))
            (local span (create-edge-label edge.label))
            (set record.label-span span))
        (local start-pos (get-position-raw self edge.source))
        (local end-pos (get-position-raw self edge.target))
        (assert start-pos
                (string.format "GraphViewLayout.add-edge missing start position for %s"
                               (node-id edge.source)))
        (assert end-pos
                (string.format "GraphViewLayout.add-edge missing end position for %s"
                               (node-id edge.target)))
        (line:update start-pos end-pos)
        (when record.label-span
            (place-edge-label record.label-span start-pos end-pos))
        (table.insert edges record)
        record)

    (fn refresh-edge-line [_self record]
        (drop-edge-label record)
        (when record.line
            (record.line:drop))
        (local edge record.edge)
        (local source-size (or (and edge edge.source edge.source.size) 0))
        (local target-size (or (and edge edge.target edge.target.size) 0))
        (local min-node-size (math.min source-size target-size))
        (local scaled-edge-thickness
               (if (> min-node-size 0)
                   (math.max base-edge-thickness (* min-node-size 0.35))
                   base-edge-thickness))
        (local line (make-line ctx {:color (ensure-glm-vec4 edge.color default-edge-color)
                                     :thickness scaled-edge-thickness
                                     :label (edge-key edge)}))
        (set record.line line)
        (when (and ctx edge.label (> (string.len edge.label) 0))
            (local span (create-edge-label edge.label))
            (set record.label-span span))
        (local start-pos (get-position-raw self edge.source))
        (local end-pos (get-position-raw self edge.target))
        (when (and start-pos end-pos)
            (line:update start-pos end-pos)
            (when record.label-span
                (place-edge-label record.label-span start-pos end-pos))))

     (fn set-node-position [_self node position opts]
         (when position
             (assert-valid-position position "GraphViewLayout.set-node-position" node)
             (local idx (. force-indices node))
             (when idx
                 (layout:set-position idx position))
             (set-point-position node position "GraphViewLayout.set-node-position")
             (update-lines)
            (local skip-labels? (and opts opts.skip-labels?))
            (when (not skip-labels?)
                (update-labels [node] {:force? true})
                (refresh-label-positions [node]))))

     (fn set-node-pinned [_self node pinned?]
         (local idx (force-index-for-node node))
         (when idx
             (layout:pin-node idx (if pinned? true false)))
         true)

     (fn rebuild []
         (layout:clear)
         (clear-force-tables)
         (each [_ node (pairs nodes)]
             (local point (. points node))
             (assert point (string.format "GraphViewLayout.rebuild missing point for node %s"
                                          (node-id node)))
             (local position (ensure-glm-vec3 point.position))
             (assert-valid-position position "GraphViewLayout.rebuild" node)
             (when (or (. pinned node) (not (. island-member-layouts node)))
                 (add-force-node {:kind :node :node node} position (. pinned node))))
         (each [_ record (pairs island-layouts)]
             (add-force-node {:kind :island :record record}
                             (ensure-glm-vec3 record.position)
                             false))
         (each [_ record (ipairs edges)]
             (local edge record.edge)
             (when edge
                 (add-force-edge edge.source edge.target)))
         (start)
         (update-labels nil {:force? true})
         (refresh-label-positions))

     (fn sync-island-layouts [_self records]
         (local next-records (if records records []))
         (each [k _ (pairs island-layouts)]
             (set (. island-layouts k) nil))
         (clear-island-member-layouts)
         (each [_ record (ipairs next-records)]
             (validate-island-layout-record record)
             (local position (ensure-glm-vec3 record.position))
             (assert-valid-position position "GraphViewLayout.sync-island-layouts" nil)
             (set record.position position)
             (set (. island-layouts record.id) record))
         (each [_ record (pairs island-layouts)]
             (each [_ member (ipairs record.members)]
                 (when (not (. pinned member))
                     (set (. island-member-layouts member) record))))
         (rebuild)
         true)

    (fn update [_self _delta]
        (layout:update 40)
        (local moved-nodes (refresh-layout))
        (update-lines)
        moved-nodes)

    (set self.add-node add-node)
    (set self.add-edge add-edge)
    (set self.update update)
    (set self.set-node-position set-node-position)
     (set self.set-node-pinned set-node-pinned)
     (set self.rebuild rebuild)
     (set self.sync-island-layouts sync-island-layouts)
     (set self.start start)
    (set self.update-lines update-lines)
    (set self.drop-edge-label drop-edge-label)
    (set self.refresh-edge-line refresh-edge-line)

    self)

GraphViewLayout
