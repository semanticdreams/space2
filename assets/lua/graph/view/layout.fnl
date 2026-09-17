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
            (local node (. nodes-by-index i))
            (when node
                (local pos (. positions i))
                (when pos
                    (local new-pos (ensure-glm-vec3 pos))
                    (assert-valid-position new-pos "GraphViewLayout.refresh-layout" node)
                    (local point (. points node))
                    (assert point (string.format "GraphViewLayout.refresh-layout missing point for node %s"
                                                 (node-id node)))
                    (when (position-changed? point.position new-pos)
                        (set-point-position node new-pos "GraphViewLayout.refresh-layout")
                        (table.insert changed node)))))
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
        (local idx (layout:add-node position))
        (assert (not (= idx nil)) "GraphViewLayout.add-node failed to allocate layout index")
        (set (. nodes-by-index (+ idx 1)) node)
        (set (. indices node) idx)
        (when pinned?
            (layout:pin-node idx true))
        idx)

    (fn add-edge [_self edge]
        (assert edge "GraphViewLayout.add-edge requires an edge")
        (assert make-line "GraphViewLayout.add-edge requires make-line callback")
        (local source-idx (. indices edge.source))
        (local target-idx (. indices edge.target))
        (assert (and source-idx target-idx)
                "GraphViewLayout.add-edge requires indexed source and target nodes")
        (layout:add-edge source-idx target-idx true)
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
            (local idx (. indices node))
            (assert idx (string.format "GraphViewLayout.set-node-position missing index for node %s"
                                        (node-id node)))
            (assert-valid-position position "GraphViewLayout.set-node-position" node)
            (layout:set-position idx position)
            (set-point-position node position "GraphViewLayout.set-node-position")
            (update-lines)
            (local skip-labels? (and opts opts.skip-labels?))
            (when (not skip-labels?)
                (update-labels [node] {:force? true})
                (refresh-label-positions [node]))))

    (fn set-node-pinned [_self node pinned?]
        (local idx (. indices node))
        (assert idx (string.format "GraphViewLayout.set-node-pinned missing index for node %s"
                                   (node-id node)))
        (layout:pin-node idx (if pinned? true false))
        true)

    (fn rebuild []
        (local ordered [])
        (for [i 1 (length nodes-by-index)]
            (local node (. nodes-by-index i))
            (when node
                (table.insert ordered node)))
        (layout:clear)
        (each [k _ (pairs nodes-by-index)]
            (set (. nodes-by-index k) nil))
        (each [k _ (pairs indices)]
            (set (. indices k) nil))
        (each [_ node (pairs nodes)]
            (var found? false)
            (each [_ existing (ipairs ordered)]
                (when (= existing node)
                    (set found? true)))
            (when (not found?)
                (table.insert ordered node)))
        (each [_ node (ipairs ordered)]
            (local point (. points node))
            (assert point (string.format "GraphViewLayout.rebuild missing point for node %s"
                                         (node-id node)))
            (local position (ensure-glm-vec3 point.position))
            (assert-valid-position position "GraphViewLayout.rebuild" node)
            (local idx (layout:add-node position))
            (set (. nodes-by-index (+ idx 1)) node)
            (set (. indices node) idx)
            (when (. pinned node)
                (layout:pin-node idx true)))
        (each [_ record (ipairs edges)]
            (local edge record.edge)
            (when edge
                (local source-idx (. indices edge.source))
                (local target-idx (. indices edge.target))
                (when (and source-idx target-idx)
                    (layout:add-edge source-idx target-idx true))))
        (start)
        (update-labels nil {:force? true})
        (refresh-label-positions))

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
    (set self.start start)
    (set self.update-lines update-lines)
    (set self.drop-edge-label drop-edge-label)
    (set self.refresh-edge-line refresh-edge-line)

    self)

GraphViewLayout
