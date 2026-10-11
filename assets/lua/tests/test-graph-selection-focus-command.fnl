(local glm (require :glm))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local CommandHelpers (require :tests/graph-command-helpers))
(local GraphView (require :graph/view))
(local BuildContext (require :build-context))
(local ObjectSelector (require :object-selector))
(local {:FocusManager FocusManager} (require :focus))

(local tests [])

(fn identity-project [position _opts]
  position)

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

(fn make-command-graph-view [count calls]
  {:selected-node-count (fn [_self] count)
   :has-visible-nodes? (fn [_self] (> count 0))
   :select-all-visible-nodes (fn [_self]
                               (set calls.select-all (+ calls.select-all 1))
                               true)
   :focus-selected-node (fn [_self]
                           (set calls.focus (+ calls.focus 1))
                           true)})

(fn run-command-case [count expected-available expected-calls message]
  (local calls {:focus 0})
  (local graph-view (make-command-graph-view count calls))
  (CommandHelpers.reset!)
  (CommandHelpers.set-graph-view! graph-view)
  (local provider (CommandHelpers.provider))
  (local binding (assert (CommandHelpers.find-binding-by-keys provider.bindings ["g" "s" "f"]) "SPC g s f binding missing"))
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

(fn command-provider-select-all-routes-only-when-visible []
  (fn run-case [count expected-available expected-calls message]
    (local calls {:focus 0 :select-all 0})
    (local graph-view (make-command-graph-view count calls))
    (CommandHelpers.reset!)
    (CommandHelpers.set-graph-view! graph-view)
    (local provider (CommandHelpers.provider))
    (local binding (assert (CommandHelpers.find-binding-by-keys provider.bindings ["g" "s" "e"]) "SPC g s e binding missing"))
    (assert (= binding.command "graph.selection.select-all") "SPC g s e should bind select-all command")
    (assert (= binding.label "select-all") "SPC g s e binding should use select-all label")
    (local command (assert (. provider.commands binding.command) "select-all command missing"))
    (assert (= command.id "graph.selection.select-all") "select-all command id mismatch")
    (assert (= command.label "select-all") "select-all command label mismatch")
    (assert (= (command:available? {}) expected-available) message)
    (assert (= (command:run {}) expected-available) message)
    (assert (= calls.select-all expected-calls) message))
  (run-case 2 true 1 "SPC g s e should select all when visible nodes exist")
  (run-case 0 false 0 "SPC g s e should no-op without visible nodes"))

(fn assert-selection [view graph-map nodes label]
  (assert (= (length view.selected-nodes) (length nodes)) (.. label " selected node count mismatch"))
  (assert (= (length graph-map.selected_node_keys) (length nodes)) (.. label " selected key count mismatch"))
  (each [i node (ipairs nodes)]
    (assert (= (. view.selected-nodes i) node) (.. label " selected node mismatch"))
    (assert (= (. graph-map.selected_node_keys i) node.key) (.. label " selected key mismatch"))))

(fn array-contains? [items expected]
  (var found? false)
  (each [_ item (ipairs items)]
    (when (= item expected)
      (set found? true)))
  found?)

(fn assert-array-members [actual expected label]
  (assert (= (length actual) (length expected)) (.. label " length mismatch"))
  (each [_ item (ipairs expected)]
    (assert (array-contains? actual item) (.. label " missing expected item"))))

(fn graph-view-select-all-visible-nodes-syncs-selection-and-selector []
  (local ctx (make-ctx))
  (local selector (ObjectSelector {:project identity-project :ctx ctx :enabled? true}))
  (local graph-map (make-graph-map))
  (local view (GraphView {:graph-map graph-map :ctx ctx :selector selector :data-dir "/tmp/space/tests/graph-selection-select-all"}))
  (assert (= (view:select-all-visible-nodes) false) "Empty graph view select-all should no-op")
  (local a (Graph.GraphNode {:key "a"}))
  (local b (Graph.GraphNode {:key "b"}))
  (graph-map:add-node a {:position (glm.vec3 0 0 0)})
  (graph-map:add-node b {:position (glm.vec3 10 0 0)})
  (selector:set-selected [(. view.points a)])
  (assert (= (view:select-all-visible-nodes) true) "Select-all should report success when visible nodes exist")
  (assert-selection view graph-map [a b] "select all visible")
  (assert-array-members selector.selected [(. view.points a) (. view.points b)] "select all selector points")
  (assert (not (graph-map:lookup "lazy-only")) "Select-all should not materialize lazy-only nodes")
  (view:drop)
  (graph-map:drop)
  (selector:drop))

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
(table.insert tests {:name "Graph selection select-all command routes only when nodes are visible"
                      :fn command-provider-select-all-routes-only-when-visible})
(table.insert tests {:name "GraphView focus selected node preserves selection and requires single selection"
                      :fn graph-view-focus-selected-node-preserves-selection-and-requires-single-selection})
(table.insert tests {:name "GraphView select all visible nodes syncs selection and selector"
                      :fn graph-view-select-all-visible-nodes-syncs-selection-and-selector})

(fn main []
  (table.insert tests 1 {:name "Graph selection focus command suppresses selection info logs"
                         :fn (fn []
                               (assert ((. (require :logging) :set-level) "warn")
                                       "graph selection focus command test requires logging level control"))})
  ((. (require :tests/runner) :run-tests) {:name "graph-selection-focus-command" :tests tests}))

{:name "graph-selection-focus-command" :tests tests :main main}
