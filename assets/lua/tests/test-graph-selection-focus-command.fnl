(local glm (require :glm))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local GraphCommands (require :graph/commands))
(local GraphView (require :graph/view))
(local BuildContext (require :build-context))
(local ObjectSelector (require :object-selector))
(local {:FocusManager FocusManager} (require :focus))

(local tests [])
(var command-graph-view nil)

(fn identity-project [position _opts]
  position)

(fn resolve-command-graph-view []
  command-graph-view)

(fn make-ctx []
  (local focus-manager (FocusManager {:root-name "test-graph-selection-focus-command"}))
  (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                 :hoverables (assert app.hoverables "test requires app.hoverables")
                 :focus-manager focus-manager
                 :focus-scope (focus-manager:create-scope {:name "graph-view"})
                 :theme {:graph {:selection-border-color (glm.vec4 1 0.6 0.2 1)
                                  :label-color (glm.vec4 1 1 1 1)
                                  :label-target-pixels 13.0
                                  :label-min-scale 4.0
                                  :edge-color (glm.vec4 0.6 0.6 0.6 1)}
                         :input {:focus-outline (glm.vec4 0.2 0.6 1 1)}}}))

(fn make-graph-map []
  (local graph (Graph {:with-start false}))
  (local original-has-key-loader graph.has-key-loader-for-key)
  (set graph.has-key-loader-for-key
       (fn [self key]
         (if (and original-has-key-loader (original-has-key-loader self key))
             true
             (if key true false))))
  (GraphMap.GraphMap {:graph graph :id "test-graph-selection-focus-command"}))

(fn find-binding [bindings]
  (var found nil)
  (each [_ binding (ipairs bindings) &until found]
    (when (and (= (. binding.keys 1) "g")
               (= (. binding.keys 2) "s")
               (= (. binding.keys 3) "f"))
      (set found binding)))
  found)

(fn make-command-graph-view [count calls]
  {:selected-node-count (fn [_self] count)
   :focus-selected-node (fn [_self]
                          (set calls.focus (+ calls.focus 1))
                          true)})

(fn run-command-case [count expected-available expected-calls message]
  (local calls {:focus 0})
  (local graph-view (make-command-graph-view count calls))
  (set command-graph-view graph-view)
  (local provider (GraphCommands.provider {:graph-view resolve-command-graph-view}))
  (local binding (assert (find-binding provider.bindings) "SPC g s f binding missing"))
  (assert (= binding.command "graph.selection.focus-selected") "SPC g s f should bind focus-selected command")
  (assert (= binding.label "focus") "SPC g s f binding should use focus label")
  (local command (assert (. provider.commands binding.command) "focus-selected command missing"))
  (assert (= command.id "graph.selection.focus-selected") "focus-selected command id mismatch")
  (assert (= command.label "focus") "focus-selected command label mismatch")
  (assert (= (command:available? {}) expected-available) message)
  (assert (= (command:run {}) expected-available) message)
  (assert (= calls.focus expected-calls) message))

(fn command-provider-focus-selected-routes-only-for-single-selection []
  (run-command-case 1 true 1 "SPC g s f should focus exactly one selected node")
  (run-command-case 0 false 0 "SPC g s f should no-op with zero selected nodes")
  (run-command-case 2 false 0 "SPC g s f should no-op with multiple selected nodes"))

(fn assert-selection [view graph-map nodes label]
  (assert (= (length view.selected-nodes) (length nodes)) (.. label " selected node count mismatch"))
  (assert (= (length graph-map.selected_node_keys) (length nodes)) (.. label " selected key count mismatch"))
  (each [i node (ipairs nodes)]
    (assert (= (. view.selected-nodes i) node) (.. label " selected node mismatch"))
    (assert (= (. graph-map.selected_node_keys i) node.key) (.. label " selected key mismatch"))))

(fn graph-view-focus-selected-node-preserves-selection-and-requires-single-selection []
  (local ctx (make-ctx))
  (local selector (ObjectSelector {:project identity-project :ctx ctx :enabled? true}))
  (local graph-map (make-graph-map))
  (local view (GraphView {:graph-map graph-map :ctx ctx :selector selector :data-dir "/tmp/space/tests/graph-selection-focus-command"}))
  (local a (Graph.GraphNode {:key "a"}))
  (local b (Graph.GraphNode {:key "b"}))
  (local c (Graph.GraphNode {:key "c"}))
  (graph-map:add-node a {:position (glm.vec3 0 0 0)})
  (graph-map:add-node b {:position (glm.vec3 10 0 0)})
  (graph-map:add-node c {:position (glm.vec3 20 0 0)})
  (local existing-focus-node (. view.focus-nodes c))
  (existing-focus-node:request-focus)
  (assert (= (view:focus-selected-node) false) "Zero selected nodes should no-op")
  (assert (= (ctx.focus.manager:get-focused-node) (. view.focus-nodes c)) "Zero selection should preserve focus")
  (assert-selection view graph-map [] "zero selection")
  (selector:set-selected [(. view.points a) (. view.points b)])
  (assert (= (view:focus-selected-node) false) "Multiple selected nodes should no-op")
  (assert (= (ctx.focus.manager:get-focused-node) (. view.focus-nodes c)) "Multiple selection should preserve focus")
  (assert-selection view graph-map [a b] "multiple selection")
  (selector:set-selected [(. view.points a)])
  (assert (= (view:focus-selected-node) true) "Single selected node should focus")
  (assert (= (ctx.focus.manager:get-focused-node) (. view.focus-nodes a)) "Single selection should focus selected node")
  (assert-selection view graph-map [a] "single selection")
  (view:drop)
  (graph-map:drop)
  (selector:drop))

(table.insert tests {:name "Graph selection focus command routes only for single selection"
                     :fn command-provider-focus-selected-routes-only-for-single-selection})
(table.insert tests {:name "GraphView focus selected node preserves selection and requires single selection"
                     :fn graph-view-focus-selected-node-preserves-selection-and-requires-single-selection})

(fn main []
  (table.insert tests 1 {:name "Graph selection focus command suppresses selection info logs"
                         :fn (fn []
                               (assert ((. (require :logging) :set-level) "warn")
                                       "graph selection focus command test requires logging level control"))})
  ((. (require :tests/runner) :run-tests) {:name "graph-selection-focus-command" :tests tests}))

{:name "graph-selection-focus-command" :tests tests :main main}
