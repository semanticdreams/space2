(local glm (require :glm))

(fn GraphViewMovables [opts]
    (local options (or opts {}))
    (local movables options.movables)
    (local ctx options.ctx)
    (local pointer-target (or options.pointer-target
                              (and ctx ctx.pointer-target)))
    (local persistence options.persistence)
    (local on-position options.on-position)
    (local on-drag-start options.on-drag-start)
    (local on-drag-end options.on-drag-end)
    (local movable-targets {})
    (local position-magnitude-threshold 1e6)

    (fn assert-valid-position [position context node]
        (local label (or (and node node.key) "<unknown>"))
        (fn finite-number? [v]
            (and (= (type v) :number)
                 (= v v)
                 (not (= v math.huge))
                 (not (= v (- math.huge)))))
        (when (or (not position)
                  (not (finite-number? position.x))
                  (not (finite-number? position.y))
                  (not (finite-number? position.z)))
            (error (string.format "GraphViewMovables received non-finite position in %s for %s"
                                  (or context "movables")
                                  label)))
        (local magnitude (glm.length position))
        (when (> magnitude position-magnitude-threshold)
            (error (string.format "GraphViewMovables position magnitude %.3f exceeds threshold %.0f in %s for %s"
                                  magnitude
                                  position-magnitude-threshold
                                  (or context "movables")
                                  label))))

    (fn make-target [node point]
        (local target {:position point.position
                       :pointer-target pointer-target})
        (set target.set-position
             (fn [self position]
                 (when position
                     (assert-valid-position position "movable-target.set-position" node)
                     (set self.position position)
                     (when on-position
                         (on-position node position)))
                 self))
        target)

    (fn register [_self node point]
        (when (and movables point)
            (when (and node node.graph node.key)
                (when (not node.graph.presentation-points)
                    (set node.graph.presentation-points {}))
                (set (. node.graph.presentation-points node.key) point))
            (local target (make-target node point))
            (set (. movable-targets node) target)
            (movables:register point {:target target
                                      :handle point
                                      :pointer-target target.pointer-target
                                      :key node
                                      :on-drag-start (fn [entry]
                                                       (when on-drag-start
                                                           (on-drag-start node entry)))
                                      :on-drag-end (fn [_entry]
                                                      (when on-drag-end
                                                          (on-drag-end node _entry))
                                                      (when (and persistence persistence.schedule-save)
                                                          (persistence:schedule-save)))})
            target))

    (fn unregister [_self node]
        (when node
            (when (and node.graph node.graph.presentation-points node.key)
                (set (. node.graph.presentation-points node.key) nil))
            (when (and movables node)
                (movables:unregister node))
            (set (. movable-targets node) nil)))

    (fn update-position [_self node position]
        (local target (. movable-targets node))
        (when (and target position)
            (assert-valid-position position "movable-target.update-position" node)
            (set target.position position)))

    (fn drop-node [self node]
        (unregister self node))

    (fn drop-all [self]
        (local nodes [])
        (each [node _ (pairs movable-targets)]
            (table.insert nodes node))
        (each [_ node (ipairs nodes)]
            (unregister self node)))

    {:targets movable-targets
     :register register
     :unregister unregister
     :update-position update-position
     :drop-node drop-node
     :drop-all drop-all})

GraphViewMovables
