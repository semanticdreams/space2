(local Harness (require :tests.e2e.harness))
(local glm (require :glm))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local GraphView (require :graph/view))
(local {:FocusManager FocusManager} (require :focus))
(local {:Layout Layout} (require :layout))
(local fs (require :fs))
(local viewport-utils (require :viewport-utils))

(var click-timestamp 0)

(fn approx [actual expected]
  (< (math.abs (- actual expected)) 0.0001))

(fn vec4-approx= [actual expected]
  (and actual expected
       (approx actual.x expected.x)
       (approx actual.y expected.y)
       (approx actual.z expected.z)
       (approx actual.w expected.w)))

(fn next-click-timestamp []
  (set click-timestamp (+ click-timestamp 1))
  click-timestamp)

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

(fn populate-child-root! [graph-map nodes]
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

(fn active-state []
  (local state (and app.states (app.states:active-state)))
  (assert state "outline e2e requires active app state")
  state)

(fn project-to-screen [position target]
  (assert (and glm glm.project) "outline e2e requires glm.project")
  (local viewport (viewport-utils.to-table app.viewport))
  (local viewport-vec (viewport-utils.to-glm-vec4 viewport))
  (local projected (glm.project position
                                (target:get-view-matrix)
                                target.projection
                                viewport-vec))
  (assert projected "outline e2e glm.project returned nil")
  {:x projected.x
   :y (- (+ viewport.height viewport.y) projected.y)})

(fn click-at [point]
  (local state (active-state))
  (local timestamp (next-click-timestamp))
  (state.on-mouse-button-down {:button 1
                               :x point.x
                               :y point.y
                               :timestamp timestamp})
  (state.on-mouse-button-up {:button 1
                             :x point.x
                             :y point.y
                             :timestamp timestamp}))

(fn make-outline-e2e-env [ctx opts]
  (local options (assert opts "make-outline-e2e-env requires opts"))
  (local world-width 192)
  (local world-height 72)
  (local world-units-per-pixel (/ world-height ctx.height))
  (local focus-manager (FocusManager {:root-name (.. "e2e-outline-repro-" options.name)}))
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
  {:target screen-target
   :state state
   :focus-manager focus-manager})

(fn cleanup-outline-e2e-env [env]
  (when (and env env.target)
    (Harness.cleanup-target env.target)))

(fn row-record [view key]
  (var found nil)
  (each [_ record (ipairs (or view.row-handles [])) &until found]
    (when (and record record.row (= record.row.key key))
      (set found record)))
  (assert found (.. "missing outline row record for " key)))

(fn layer-record [point idx label]
  (assert (and point point.layers) (.. label " missing layered point layers"))
  (assert (. point.layers idx) (.. label " missing layer " idx)))

(fn assert-layer-matches [actual expected label]
  (assert (approx actual.size expected.size)
          (.. label " size mismatch: expected " (tostring expected.size)
              ", got " (tostring actual.size)))
  (when (> expected.size 0)
    (assert (> actual.size 0)
            (.. label " should be visible before comparing color/depth"))
    (assert (vec4-approx= actual.color expected.color)
            (.. label " color mismatch"))
    (assert (= actual.depth-offset-index expected.depth-offset-index)
            (.. label " depth layer mismatch: expected " (tostring expected.depth-offset-index)
                ", got " (tostring actual.depth-offset-index)))))

(fn make-spatial-style-sample [ctx focus-manager data-root state-name opts]
  (local options (or opts {}))
  (local graph-map (make-test-graph-map (.. "spatial-style-" state-name)))
  (graph-map:set-view-mode! "spatial")
  (local node (add-node! graph-map (make-node (.. "spatial-" state-name)
                                              (.. "Spatial " state-name)
                                              (glm.vec4 0.32 0.62 0.98 1))))
  (when options.selected?
    (graph-map:set-selected-node-keys [node.key]))
  (when options.focused?
    (set graph-map.focused_node_key node.key))
  (local view (GraphView {:graph-map graph-map
                         :ctx ctx
                         :data-dir data-root}))
  (when options.selected?
    (view.selection:set-selection [node]))
  (when options.focused?
    (local focus-node (. view.focus-nodes node))
    (assert focus-node "spatial style sample missing focus node")
    (focus-node:request-focus {:reason :e2e-style-sample}))
  (view:update 0.016)
  (local point (assert (. view.points node) "spatial style sample missing point"))
  (local sample {:focus {:size (. point.layers 1 :size)
                         :color (. point.layers 1 :color)
                         :depth-offset-index (. point.layers 1 :depth-offset-index)}
                :selection {:size (. point.layers 2 :size)
                            :color (. point.layers 2 :color)
                            :depth-offset-index (. point.layers 2 :depth-offset-index)}})
  (view:drop)
  (drop-test-graph-map! graph-map)
  sample)

(fn selected-keys-text [graph-map]
  (table.concat (assert graph-map.selected_node_keys
                         "outline click repro requires graph-map selected_node_keys")
                ","))

(fn outline-click-selects-and-focuses-visible-row [ctx]
  (local env (make-outline-e2e-env ctx {:name "graph-outline-repro-click-selection"
                                        :populate populate-child-root!}))
  (local (ok err)
    (pcall
      (fn []
        (local view (assert env.state.view "outline click repro missing view"))
        (local graph-map (assert env.state.graph-map "outline click repro missing graph map"))
        (local child-record (row-record view "child"))
        (local click-point (project-to-screen (glm.vec3 40 -36 0) env.target))
        (click-at click-point)
        (view:update 0.016)
        (assert (= graph-map.focused_node_key "child")
                (.. "outline row click should focus child graph node, got "
                    (tostring graph-map.focused_node_key)))
        (assert (= (selected-keys-text graph-map) "child")
                (.. "outline row click should select child graph node, got "
                    (selected-keys-text graph-map)))
        (assert child-record.selectable
                "outline row click repro requires row selectable proxy")
        (assert child-record.focus-node
                "outline row click repro requires row focus node")
        (assert (= (env.focus-manager:get-focused-node) child-record.focus-node)
                "outline row click should focus the row focus-manager node"))))
  (cleanup-outline-e2e-env env)
  (when (not ok)
    (error err)))

(var current-style-build nil)

(fn style-outline-populate [graph-map nodes]
  (local config (assert current-style-build "style-outline-populate requires current style build"))
  (local options config.options)
  (graph-map:set-outline-root-keys! [nodes.root.key])
  (when options.selected?
    (graph-map:set-selected-node-keys [nodes.child.key]))
  (when options.focused?
    (set graph-map.focused_node_key nodes.child.key)))

(fn style-screen-builder [build-ctx]
  (local config (assert current-style-build "style-screen-builder requires current style build"))
  (local expected (make-spatial-style-sample build-ctx
                                             config.focus-manager
                                             config.data-root
                                             config.state-name
                                             config.options))
  (local state {:view nil :graph-map nil})
  (local outline-options {:name (.. "graph-outline-style-" config.state-name)
                          :populate style-outline-populate
                          :data-root config.data-root})
  (local element (make-outline-element state outline-options 192 72 build-ctx))
  (local child-record (row-record state.view "child"))
  (local focus-layer (layer-record child-record.point 1 (.. config.state-name " outline focus")))
  (local selection-layer (layer-record child-record.point 2 (.. config.state-name " outline selection")))
  (assert-layer-matches focus-layer expected.focus (.. config.state-name " focus ring"))
  (assert-layer-matches selection-layer expected.selection (.. config.state-name " selection ring"))
  element)

(fn draw-style-target [ctx screen-target]
  (Harness.draw-targets ctx.width ctx.height [{:target screen-target}]))

(fn assert-outline-row-style [ctx state-name opts]
  (local options (or opts {}))
  (local data-root (fs.join-path "/tmp/space/tests" (.. "graph-outline-style-source-" state-name)))
  (when (fs.exists data-root)
    (fs.remove-all data-root))
  (fs.create-dirs data-root)
  (local focus-manager (FocusManager {:root-name (.. "e2e-outline-style-" state-name)}))
  (set current-style-build {:focus-manager focus-manager
                            :data-root data-root
                            :state-name state-name
                            :options options})
  (local screen-target
    (Harness.make-screen-target
      {:focus-manager focus-manager
       :width ctx.width
       :height ctx.height
       :world-units-per-pixel (/ 72 ctx.height)
       :projection (glm.ortho 0 192 -72 0 -100.0 100.0)
       :builder style-screen-builder}))
  (set current-style-build nil)
  (local (ok err)
    (pcall draw-style-target ctx screen-target))
  (Harness.cleanup-target screen-target)
  (focus-manager:drop)
  (when (not ok)
    (error err)))

(fn outline-selection-focus-visuals-match-graph-view [ctx]
  (assert-outline-row-style ctx "selected-only" {:selected? true :focused? false})
  (assert-outline-row-style ctx "focused-only" {:selected? false :focused? true})
  (assert-outline-row-style ctx "selected-focused" {:selected? true :focused? true}))

(fn run-reproduction-tests [ctx]
  (local repro-case (os.getenv "SPACE_OUTLINE_REPRO_CASE"))
  (if (= repro-case "click")
      (outline-click-selects-and-focuses-visible-row ctx)
      (= repro-case "visual")
      (outline-selection-focus-visuals-match-graph-view ctx)
      (do
        (outline-click-selects-and-focuses-visible-row ctx)
        (outline-selection-focus-visuals-match-graph-view ctx))))

(fn run [ctx]
  (run-reproduction-tests ctx)
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
  (print "E2E graph outline view reproduction tests and snapshots complete"))

{:run run
 :run-reproduction-tests run-reproduction-tests
  :main main}
