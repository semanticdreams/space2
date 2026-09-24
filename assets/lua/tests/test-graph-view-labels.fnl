(local glm (require :glm))
(local GraphViewLabels (require :graph/view/labels))
(local BuildContext (require :build-context))
(local Camera (require :camera))
(local Scene (require :scene))
(local {:GraphNode GraphNode} (require :graph/node-base))

(local tests [])

(fn assert-close [actual expected message]
    (assert (< (math.abs (- actual expected)) 1e-6)
            (or message
                (string.format "Expected %s to equal %s" actual expected))))

(fn make-ctx []
    (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                   :hoverables (assert app.hoverables "test requires app.hoverables")}))

(fn make-perspective-surface [opts]
    (local options (or opts {}))
    (local viewport (or options.viewport {:x 0 :y 0 :width 100 :height 100}))
    (local position (or options.position (glm.vec3 0 0 170)))
    (local camera (Camera {:position position}))
    (local scene (Scene {:camera camera
                         :position (glm.vec3 0 0 0)
                         :rotation (glm.quat 1 0 0 0)}))
    (scene:on-viewport-changed viewport)
    (when options.projection
        (set scene.projection options.projection)
        (set scene.projection-version (+ (or scene.projection-version 0) 1)))
    {:camera camera
     :surface scene})

(fn codepoints->text [codepoints]
    (assert (= (type codepoints) :table) "codepoints->text requires codepoints")
    (local chars [])
    (each [_ codepoint (ipairs codepoints)]
        (table.insert chars (string.char codepoint)))
    (table.concat chars))

(fn labels-create-span-with-defaults []
    (local ctx (make-ctx))
    (local camera {:position (glm.vec3 0 0 0)})
    (local labels (GraphViewLabels {:ctx ctx :camera camera}))
    (local node (GraphNode {:key "a" :label "Alpha"}))
    (local point {:position (glm.vec3 0 0 0) :size 6})
    (local points {node point})
    (labels:update points [node] {:force? true})
    (local span (. labels.labels node))
    (assert span "Labels should create text span for visible node")
    (assert span.layout "Label span should expose a layout")
    (assert (= span.style.scale 3)
            (string.format "LOD0 label should use scale 3 (got %s)" span.style.scale))
    (assert (= span.layout.depth-offset-index 1.0)
            "Label depth offset should default to 1.0")
    (assert span.layout.position "Label layout should assign a position")
    (labels:drop-all))

(fn labels-use-compact-label-string-when-present []
    (local ctx (make-ctx))
    (local camera {:position (glm.vec3 0 0 0)})
    (local labels (GraphViewLabels {:ctx ctx :camera camera}))
    (local node (GraphNode {:key "compact-string" :label "Raw Fallback"}))
    (set node.compact-label "Friendly Name")
    (local point {:position (glm.vec3 0 0 0) :size 6})
    (local points {node point})
    (labels:update points [node] {:force? true})
    (local span (. labels.labels node))
    (assert span "compact-label string should create a text span")
    (assert (= (codepoints->text (span:get-codepoints)) "Friendly Name")
            "compact-label string should override node.label for compact labels")
    (labels:drop-all))

(fn labels-preserve-fallback-when-compact-label-missing []
    (local ctx (make-ctx))
    (local camera {:position (glm.vec3 0 0 0)})
    (local labels (GraphViewLabels {:ctx ctx :camera camera}))
    (local node (GraphNode {:key "fallback-key" :label "Fallback Label"}))
    (local point {:position (glm.vec3 0 0 0) :size 6})
    (local points {node point})
    (labels:update points [node] {:force? true})
    (local span (. labels.labels node))
    (assert span "missing compact-label should preserve existing label fallback")
    (assert (= (codepoints->text (span:get-codepoints)) "Fallback Label")
            "missing compact-label should render node.label")
    (labels:drop-all))

(fn labels-drop-span-when-compact-label-is-false []
    (local ctx (make-ctx))
    (local camera {:position (glm.vec3 0 0 0)})
    (local labels (GraphViewLabels {:ctx ctx :camera camera}))
    (local node (GraphNode {:key "list-entity:unnamed" :label "raw-list-id"}))
    (set node.compact-label "Temporary Name")
    (local point {:position (glm.vec3 0 0 0) :size 6})
    (local points {node point})
    (labels:update points [node] {:force? true})
    (assert (. labels.labels node) "test should start with an existing span")
    (set node.compact-label false)
    (labels:update points [node] {:force? true})
    (assert (not (. labels.labels node))
            "compact-label false should drop existing compact label span")
    (labels:drop-all))

(fn labels-move-reassigns-span []
    (local ctx (make-ctx))
    (local camera {:position (glm.vec3 0 0 0)})
    (local labels (GraphViewLabels {:ctx ctx :camera camera}))
    (local first (GraphNode {:key "first" :label "First"}))
    (local second (GraphNode {:key "second" :label "Second"}))
    (local point {:position (glm.vec3 0 0 0) :size 4})
    (local points {first point})
    (labels:update points [first] {:force? true})
    (local span (. labels.labels first))
    (assert span "Labels should create span for first node")
    (labels:move-label first second)
    (assert (not (. labels.labels first)) "Move should clear old label entry")
    (assert (= (. labels.labels second) span)
            "Move should reassign span to replacement node")
    (labels:update points [second] {:force? true})
    (labels:drop-node second)
    (assert (not (. labels.labels second)) "Drop-node should clear reassigned span")
    (labels:drop-all))

(fn labels-update-when-camera-moves-without-debounced-signal []
    (local ctx (make-ctx))
    (local camera {:position (glm.vec3 0 0 900)})
    (local labels (GraphViewLabels {:ctx ctx :camera camera}))
    (local node (GraphNode {:key "camera-move" :label "Camera Move"}))
    (local point {:position (glm.vec3 0 0 0) :size 4})
    (local points {node point})
    (labels:update points [node] {:force? true})
    (assert (not (. labels.labels node))
            "Node should start hidden when camera is far enough for LOD3")
    (set camera.position (glm.vec3 0 0 0))
    (labels:update points [node] nil)
    (assert (. labels.labels node)
            "Label should appear when camera moves close, even without debounced camera signal")
    (labels:drop-all))

(fn labels-update-when-orthographic-surface-scale-changes []
    (local ctx (make-ctx))
    (local surface {:world-units-per-pixel 1.0})
    (local labels (GraphViewLabels {:ctx ctx :surface surface}))
    (local node (GraphNode {:key "canvas-scale" :label "Canvas Scale"}))
    (local point {:position (glm.vec3 0 0 0) :size 4})
    (local points {node point})
    (labels:update points [node] {:force? true})
    (local span (. labels.labels node))
    (assert span "Label should appear at the default orthographic canvas scale")
    (assert-close span.style.scale 10.0
                  (string.format "Orthographic labels should target a 10px height (got %s)"
                                 span.style.scale))
    (set surface.world-units-per-pixel 0.1)
    (labels:update points [node] nil)
    (assert-close span.style.scale 3.0
                  (string.format "Zoomed-in orthographic LOD should clamp to scale 3 (got %s)"
                                 span.style.scale))
    (set surface.world-units-per-pixel 4.0)
    (labels:update points [node] nil)
    (assert (not (. labels.labels node))
            "Label should hide when orthographic zoom is far enough out")
    (labels:drop-all))

(fn labels-scale-continuously-within-the-same-lod []
    (local ctx (make-ctx))
    (local surface {:world-units-per-pixel 1.0})
    (local labels (GraphViewLabels {:ctx ctx :surface surface}))
    (local node (GraphNode {:key "continuous-scale" :label "Continuous Scale"}))
    (local point {:position (glm.vec3 0 0 0) :size 4})
    (local points {node point})
    (labels:update points [node] {:force? true})
    (local span (. labels.labels node))
    (assert span "Label should be visible for continuous scaling checks")
    (local initial-scale span.style.scale)
    (local initial-lod (. labels.node-lod node))
    (assert (= initial-lod 1)
            (string.format "Expected initial LOD1 for orthographic scale 1.0 (got %s)"
                           initial-lod))
    (set surface.world-units-per-pixel 1.25)
    (labels:update points [node] nil)
    (assert (= (. labels.node-lod node) 1)
            "Changing projected size within the same band should keep the same LOD")
    (assert (> span.style.scale initial-scale)
            (string.format "Lower projected density should increase label scale (%s -> %s)"
                           initial-scale
                           span.style.scale))
    (assert-close span.style.scale 12.5
                  (string.format "Scale should target a 10px height within the same LOD band (got %s)"
                                 span.style.scale))
    (labels:drop-all))

(fn labels-update-when-perspective-surface-camera-moves-small-distance []
    (local ctx (make-ctx))
    (local {:camera camera :surface surface}
           (make-perspective-surface {:position (glm.vec3 0 0 81)}))
    (local labels (GraphViewLabels {:ctx ctx :camera camera :surface surface}))
    (local node (GraphNode {:key "scene-small-move" :label "Scene Small Move"}))
    (local point {:position (glm.vec3 0 0 0) :size 4})
    (local points {node point})
    (labels:update points [node] {:force? true})
    (local span (. labels.labels node))
    (assert span "Label should be visible just outside the highest-detail threshold")
    (assert (= (. labels.node-lod node) 1)
            (string.format "Expected initial LOD1 just outside the closest perspective band (got %s)"
                           (. labels.node-lod node)))
    (local initial-scale span.style.scale)
    (camera:set-position (glm.vec3 0 0 79.5))
    (labels:update points [node] nil)
    (assert (= (. labels.node-lod node) 0)
            (string.format "Small perspective camera move should promote to LOD0 (got %s)"
                           (. labels.node-lod node)))
    (assert (< span.style.scale initial-scale)
            (string.format "Moving closer should shrink projected-size scale (%s -> %s)"
                           initial-scale
                           span.style.scale))
    (labels:drop-all)
    (surface:drop)
    (camera:drop))

(fn labels-update-when-perspective-projection-changes []
    (local ctx (make-ctx))
    (local {:camera camera :surface surface}
           (make-perspective-surface {:position (glm.vec3 0 0 170)}))
    (local labels (GraphViewLabels {:ctx ctx :camera camera :surface surface}))
    (local node (GraphNode {:key "scene-projection" :label "Scene Projection"}))
    (local point {:position (glm.vec3 0 0 0) :size 4})
    (local points {node point})
    (labels:update points [node] {:force? true})
    (local span (. labels.labels node))
    (assert span "Label should be visible at the default perspective projection")
    (assert (= (. labels.node-lod node) 2)
            (string.format "Expected initial perspective LOD2 (got %s)"
                           (. labels.node-lod node)))
    (local initial-scale span.style.scale)
    (set surface.projection (glm.perspective (/ math.pi 6) 1.0 1.0 10000.0))
    (set surface.projection-version (+ (or surface.projection-version 0) 1))
    (labels:update points [node] nil)
    (assert (= (. labels.node-lod node) 1)
            (string.format "Projection change should promote perspective LOD to 1 (got %s)"
                           (. labels.node-lod node)))
    (assert (< span.style.scale initial-scale)
            (string.format "Zooming the camera projection should shrink projected-size scale (%s -> %s)"
                           initial-scale
                           span.style.scale))
    (labels:drop-all)
    (surface:drop)
    (camera:drop))

(table.insert tests {:name "GraphView labels create spans with defaults" :fn labels-create-span-with-defaults})
(table.insert tests {:name "GraphView labels use compact-label string when present"
                     :fn labels-use-compact-label-string-when-present})
(table.insert tests {:name "GraphView labels preserve fallback when compact-label missing"
                     :fn labels-preserve-fallback-when-compact-label-missing})
(table.insert tests {:name "GraphView labels drop span when compact-label is false"
                     :fn labels-drop-span-when-compact-label-is-false})
(table.insert tests {:name "GraphView labels move and drop reassigned spans" :fn labels-move-reassigns-span})
(table.insert tests {:name "GraphView labels update when camera moves without debounce signal"
                     :fn labels-update-when-camera-moves-without-debounced-signal})
(table.insert tests {:name "GraphView labels update when orthographic surface scale changes"
                     :fn labels-update-when-orthographic-surface-scale-changes})
(table.insert tests {:name "GraphView labels scale continuously within the same LOD"
                     :fn labels-scale-continuously-within-the-same-lod})
(table.insert tests {:name "GraphView labels update when perspective surface camera moves a small distance"
                     :fn labels-update-when-perspective-surface-camera-moves-small-distance})
(table.insert tests {:name "GraphView labels update when perspective projection changes"
                     :fn labels-update-when-perspective-projection-changes})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-view-labels"
                       :tests tests})))

{:name "graph-view-labels"
 :tests tests
 :main main}
