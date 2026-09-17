(local Harness (require :tests.e2e.harness))
(local glm (require :glm))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local GraphView (require :graph/view))
(local {:FocusManager FocusManager} (require :focus))
(local {:Layout Layout} (require :layout))
(local fs (require :fs))

(fn make-test-graph-map []
  (local graph (Graph {:with-start false}))
  (local original-has-key-loader graph.has-key-loader-for-key)
  (set graph.has-key-loader-for-key
       (fn [self key]
         (if (and original-has-key-loader (original-has-key-loader self key))
             true
             (if key true false))))
  (GraphMap.GraphMap {:graph graph :id "e2e-graph-node-points"}))

(fn drop-test-graph-map! [graph-map]
  (local graph graph-map.graph)
  (graph-map:drop)
  (graph:drop))

(fn run [ctx]
  (local focus-manager (FocusManager {:root-name "e2e-graph"}))
  (var view nil)
  (var graph nil)
  (local world-size ctx.world-size)
  (local data-root (fs.join-path "/tmp/space/tests" "graph-node-points"))
  (when (fs.exists data-root)
    (fs.remove-all data-root))
  (fs.create-dirs data-root)
  (local screen-target
    (Harness.make-screen-target
      {:focus-manager focus-manager
       :builder (fn [ctx]
                   (set graph (make-test-graph-map))
                  (set view (GraphView {:graph-map graph
                                        :ctx ctx
                                        :data-dir data-root}))
                  (local node-a (Graph.GraphNode {:key "node-a"
                                                  :label "Selected + Focused"
                                                  :color (glm.vec4 0.32 0.62 0.98 1)
                                                  :size 12}))
                  (local node-b (Graph.GraphNode {:key "node-b"
                                                  :label "Selected"
                                                  :color (glm.vec4 0.58 0.86 0.32 1)
                                                  :size 12}))
                  (local node-c (Graph.GraphNode {:key "node-c"
                                                  :label "Idle"
                                                  :color (glm.vec4 0.78 0.46 0.25 1)
                                                  :size 12}))
                  (graph:add-node node-a {:position (glm.vec3 8 9 0)
                                          :run-force? false})
                  (graph:add-node node-b {:position (glm.vec3 16 6 0)
                                          :run-force? false})
                  (graph:add-node node-c {:position (glm.vec3 24 12 0)
                                          :run-force? false})
                  (graph:add-edge (Graph.GraphEdge {:source node-a
                                                    :target node-b})
                                  {:run-force? false})
                  (view.selection:set-selection [node-a node-b])
                  (local focus-node (. view.focus-nodes node-a))
                  (when focus-node
                    (focus-node:request-focus))
                  (view:update 0.016)
                  (assert (> (ctx.point-vector:length) 0)
                          "Graph node points should emit point data")
                  (local layout
                    (Layout {:name "graph-node-points"
                             :measurer (fn [self]
                                         (set self.measure (glm.vec3 0 0 0)))
                             :layouter (fn [self]
                                         (set self.size self.measure))}))
                  {:layout layout
                   :drop (fn [_self]
                           (when view
                             (view:drop))
                            (when graph
                              (drop-test-graph-map! graph))
                           (layout:drop))})}))
  (Harness.draw-targets ctx.width ctx.height [{:target screen-target}])
  (Harness.capture-snapshot {:name "graph-node-points"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 3})
  (Harness.cleanup-target screen-target)
  )

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E graph-node-points snapshot complete"))

{:run run
 :main main}
