(local Harness (require :tests.e2e.harness))
(local glm (require :glm))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local GraphView (require :graph/view))
(local {:FocusManager FocusManager} (require :focus))
(local {:Layout Layout} (require :layout))
(local fs (require :fs))

(fn accept-test-key-loader [_self key]
  (if key true false))

(fn make-test-graph-map [id]
  (local graph (Graph {:with-start false}))
  (set graph.has-key-loader-for-key accept-test-key-loader)
  (local graph-map (GraphMap.GraphMap {:graph graph :id id}))
  (graph-map:set-view-mode! "outline")
  graph-map)

(fn drop-test-graph-map! [graph-map]
  (local graph graph-map.graph)
  (graph-map:drop)
  (graph:drop))

(fn make-node [key label color]
  (Graph.GraphNode {:key key
                    :label label
                    :color color
                    :size 8}))

(fn add-node! [graph-map node]
  (graph-map:add-node node {:position (glm.vec3 0 0 0)
                            :run-force? false})
  node)

(fn add-edge! [graph-map source target]
  (graph-map:add-edge (Graph.GraphEdge {:source source
                                        :target target})
                      {:run-force? false}))

(fn populate-outline-graph! [graph-map opts]
  (local root (add-node! graph-map (make-node "root" "Main Root" (glm.vec4 0.32 0.62 0.98 1))))
  (local child (add-node! graph-map (make-node "child" "Indented Child" (glm.vec4 0.58 0.86 0.32 1))))
  (local grandchild (add-node! graph-map (make-node "grandchild" "Deep Grandchild" (glm.vec4 0.86 0.68 0.28 1))))
  (local branch (add-node! graph-map (make-node "branch" "Alternate Root" (glm.vec4 0.78 0.46 0.25 1))))
  (local branch-child (add-node! graph-map (make-node "branch-child" "Branch Leaf" (glm.vec4 0.62 0.42 0.86 1))))
  (local hidden (add-node! graph-map (make-node "hidden" "Unreachable Hidden" (glm.vec4 0.5 0.5 0.5 1))))
  (add-edge! graph-map root child)
  (add-edge! graph-map child grandchild)
  (add-edge! graph-map grandchild root)
  (add-edge! graph-map branch branch-child)
  (when (and opts opts.include-cross-edge?)
    (add-edge! graph-map branch child))
  {:root root
   :child child
   :grandchild grandchild
   :branch branch
   :branch-child branch-child
   :hidden hidden})

(fn outline-layout-measurer [self]
  (set self.measure self.desired-size))

(fn outline-layout-layouter [self]
  (set self.size self.measure))

(fn make-outline-layout [name world-width world-height]
  (local desired-size (glm.vec3 world-width world-height 0))
  (Layout {:name name
           :desired-size desired-size
           :measurer outline-layout-measurer
           :layouter outline-layout-layouter}))

(fn drop-outline-element! [state layout]
  (when state.view
    (state.view:drop))
  (when state.graph-map
    (drop-test-graph-map! state.graph-map))
  (layout:drop))

(fn outline-element-drop [self]
  (drop-outline-element! self.state self.layout))

(fn make-outline-element [state options world-width world-height build-ctx]
  (set state.graph-map (make-test-graph-map options.name))
  (when options.populate
    (local nodes (populate-outline-graph! state.graph-map options))
    (options.populate state.graph-map nodes))
  (set state.view (GraphView {:graph-map state.graph-map
                              :ctx build-ctx
                              :outline-text-scale 2.4
                              :data-dir options.data-root}))
  (state.view:update 0.016)
  (local layout (make-outline-layout options.name world-width world-height))
  {:layout layout
   :state state
   :drop outline-element-drop})

(var current-outline-build nil)

(fn outline-screen-builder [build-ctx]
  (local config (assert current-outline-build "outline-screen-builder requires current build config"))
  (make-outline-element config.state config.options config.world-width config.world-height build-ctx))

(fn populate-main-root! [graph-map nodes]
  (graph-map:set-outline-root-keys! [nodes.root.key]))

(fn populate-branch-root! [graph-map nodes]
  (graph-map:set-outline-root-keys! [nodes.branch.key])
  (graph-map:set-selected-node-keys [nodes.branch-child.key])
  (set graph-map.focused_node_key nodes.branch-child.key))

(fn capture-outline [ctx opts]
  (local options (assert opts "capture-outline requires opts"))
  (local world-width 192)
  (local world-height 72)
  (local world-units-per-pixel (/ world-height ctx.height))
  (local focus-manager (FocusManager {:root-name (.. "e2e-" options.name)}))
  (local data-root (fs.join-path "/tmp/space/tests" options.name))
  (when (fs.exists data-root)
    (fs.remove-all data-root))
  (fs.create-dirs data-root)
  (set options.data-root data-root)
  (local state {:view nil :graph-map nil})
  (set current-outline-build {:state state
                              :options options
                              :world-width world-width
                              :world-height world-height})
  (local screen-target
    (Harness.make-screen-target
      {:focus-manager focus-manager
        :width ctx.width
        :height ctx.height
        :world-units-per-pixel world-units-per-pixel
       :projection (glm.ortho 0 world-width (- world-height) 0 -100.0 100.0)
       :builder outline-screen-builder}))
  (set current-outline-build nil)
  (Harness.draw-targets ctx.width ctx.height [{:target screen-target}])
  (Harness.capture-snapshot {:name options.name
                             :width ctx.width
                             :height ctx.height
                             :tolerance 3})
  (Harness.cleanup-target screen-target))

(fn run [ctx]
  (capture-outline ctx {:name "graph-outline-empty"})
  (capture-outline ctx {:name "graph-outline-root-main"
                        :populate populate-main-root!})
  (capture-outline ctx {:name "graph-outline-root-branch"
                        :include-cross-edge? false
                        :populate populate-branch-root!}))

(fn run-context [ctx]
  (run ctx))

(fn main []
  (Harness.with-app {:width 640 :height 360 :units-per-pixel 1}
                    run-context)
  (print "E2E graph outline view snapshots complete"))

{:run run
 :main main}
