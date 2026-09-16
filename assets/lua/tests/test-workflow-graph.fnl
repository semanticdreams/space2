(local fs (require :fs))
(local GraphMap (require :graph/map))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Templates (require :workflows/templates))
(local WorkflowEvents (require :llm/agent/workflow-events))
(local AgentSessionGraphNode (require :graph/nodes/agent-session))
(local BuiltinGraphTestHelpers (require :tests/graph-builtin-extension-helpers))

(local _main (require :main))

(local BuildContext (require :build-context))
(local Intersectables (require :intersectables))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))

(local tests [])
(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "workflow-graph"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1)) (fs.join-path temp-root (.. "graph-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (if ok result (error result)))

(fn table-or-empty [value]
  (if value value {}))

(fn make-runner [workflow-store]
  (local started [])
  (local cancelled [])
  (fn start-run [self definition-id input context]
    (table.insert self.started {:definition-id definition-id
                                :input (table-or-empty input)
                                :context (table-or-empty context)})
    (workflow-store:create-run definition-id (table-or-empty input) (table-or-empty context)))
  (fn cancel-run [self run-id reason]
    (table.insert self.cancelled {:run-id run-id :reason reason})
    (workflow-store:update-run run-id {:status :cancelled :error {:message (tostring reason)}}))
  {:started started
   :cancelled cancelled
   :start-run start-run
   :cancel-run cancel-run})

(fn make-runtime [dir]
  (local {:WorkflowStore WorkflowStore} (require :workflows/store))
  (local CodeEntityStore (require :entities/code))
  (local Graph (require :graph/init))
  (local workflow-store (WorkflowStore {:base-dir (fs.join-path dir "workflow")}))
  (local code-store (CodeEntityStore.CodeEntityStore {:base-dir (fs.join-path dir "code")}))
  (local runner (make-runner workflow-store))
  (local graph (Graph {:with-start false}))
  (local builtins (BuiltinGraphTestHelpers.install-builtins! graph {:code-store code-store
                                                                    :workflow-store workflow-store
                                                                    :workflow-runner runner}))
  {:store workflow-store
   :code-store code-store
   :runner runner
   :graph graph
   :builtins builtins})

(fn with-runtime-dir [f dir]
  (local runtime (make-runtime dir))
  (local (ok result) (pcall f runtime))
  (runtime.builtins:drop)
  (runtime.graph:drop)
  (if ok result (error result)))

(fn with-runtime [f]
  (with-temp-dir (fn [dir] (with-runtime-dir f dir))))

(fn edge-target-key-set [edges]
  (local keys {})
  (each [_ edge (ipairs (if edges edges []))]
    (when (and edge edge.target edge.target.key) (set (. keys edge.target.key) true)))
  keys)

(fn action-named? [actions name]
  (var found false)
  (each [_ action (ipairs (if actions actions []))]
    (when (= action.name name) (set found true)))
  found)

(fn action-named [actions name]
  (var found nil)
  (each [_ action (ipairs (if actions actions []))]
    (when (= action.name name) (set found action)))
  found)

(fn assert-edge-target [edges key message]
  (assert (. (edge-target-key-set edges) key) message))

(fn make-preview-ctx []
  (local AppBootstrap (require :app-bootstrap))
  (AppBootstrap.init-themes)
  (local intersectables (Intersectables))
  (local clickables (assert (Clickables {:intersectables intersectables})
                            "workflow graph preview test requires clickables"))
  (local hoverables (assert (Hoverables {:intersectables intersectables})
                            "workflow graph preview test requires hoverables"))
  (BuildContext {:clickables clickables
                 :hoverables hoverables}))

(fn assert-missing-build-context [builder message]
  (local (ok _result) (pcall builder))
  (assert (not ok) message))

(fn assert-missing-build-context-with-fallbacks [Preview node message]
  (local fallback-ctx (make-preview-ctx))
  (local previous-graph-ctx (and node node.graph node.graph.ctx))
  (when (and node node.graph)
    (set node.graph.ctx fallback-ctx))
  (local builder (Preview node {:node node :ctx fallback-ctx}))
  (local (ok result) (pcall builder))
  (when (and node node.graph)
    (set node.graph.ctx previous-graph-ctx))
  (assert (not ok) message)
  (assert (string.find (tostring result) "requires a build context")
          "missing build context failure should mention build context"))

(fn assert-contains [text needle message]
  (assert (string.find (tostring text) needle 1 true) message))
(fn assert-not-contains [text needle message] (assert (not (string.find (tostring text) needle 1 true)) message))
(local graph-discovery-files ["lua/graph/node-base.fnl" "lua/graph/core.fnl" "lua/graph/map.fnl" "lua/graph/nodes/workflows.fnl" "lua/graph/nodes/workflow-definition.fnl" "lua/graph/nodes/workflow-step.fnl" "lua/graph/nodes/workflow-step-explorer.fnl" "lua/graph/nodes/workflow-run-explorer.fnl" "lua/graph/nodes/workflow-run.fnl" "lua/graph/nodes/workflow-run-step.fnl" "lua/graph/nodes/workflow-run-event.fnl" "lua/graph/nodes/workflow-run-timeline.fnl"])

(fn graph-discovery-has-no-relationship-hook-leftovers []
  (local relationship-hook-marker (.. "get" "-edges"))
  (local graph-api-marker (.. "self." "tri" "gger"))
  (each [_ path (ipairs graph-discovery-files)]
    (local source (fs.read-file (app.engine.get-asset-path path)))
    (assert (not (string.find source relationship-hook-marker 1 true)) (.. path " should not contain the removed relationship hook"))
    (assert (not (string.find source graph-api-marker 1 true)) (.. path " should not contain the removed graph materialization API"))))

(fn codepoints->text [codepoints]
  (local source (if codepoints codepoints []))
  (accumulate [text "" _ codepoint (ipairs source)]
    (.. text (string.char codepoint))))

(fn text-widget-string [widget]
  (codepoints->text (widget:get-codepoints)))
(fn definition-named? [workflow-store name] (var found? false) (each [_ definition (ipairs (workflow-store:list-definitions))] (when (= definition.name name) (set found? true))) found?)

(fn wrap-preview-drop-counter [widget dropped field key] (local child (. widget field)) (local original-drop child.drop) (set child.drop (fn [self] (set (. dropped key) (+ (. dropped key) 1)) (original-drop self))))
(fn assert-drop-counts [dropped label] (each [key count (pairs dropped)] (assert (> count 0) (.. label " should drop " (tostring key)))))
(fn assert-widget-drop-counters [widget fields label] (local dropped {}) (each [_ pair (ipairs fields)] (set (. dropped (. pair 2)) 0) (wrap-preview-drop-counter widget dropped (. pair 1) (. pair 2))) (widget:drop) (assert-drop-counts dropped label))
(fn assert-preview-drops-owned-children [widget message]
  (local dropped {:title 0 :summary 0 :flex 0 :definition-search 0 :workflow-name-input 0})
  (local original-title-drop widget.title.drop)
  (local original-summary-drop widget.summary-text.drop)
  (local original-flex-drop widget.flex.drop)
  (local original-definition-search-drop (and widget.definition-search widget.definition-search.drop))
  (local original-workflow-name-input-drop (and widget.workflow-name-input widget.workflow-name-input.drop))
  (set widget.title.drop
       (fn [self]
         (set dropped.title (+ dropped.title 1))
         (original-title-drop self)))
  (set widget.summary-text.drop
       (fn [self]
         (set dropped.summary (+ dropped.summary 1))
         (original-summary-drop self)))
  (set widget.flex.drop
       (fn [self]
         (set dropped.flex (+ dropped.flex 1))
         (original-flex-drop self)))
  (when widget.definition-search
    (set widget.definition-search.drop
         (fn [self]
           (set dropped.definition-search (+ dropped.definition-search 1))
           (original-definition-search-drop self))))
  (when widget.workflow-name-input (set widget.workflow-name-input.drop (fn [self] (set dropped.workflow-name-input (+ dropped.workflow-name-input 1)) (original-workflow-name-input-drop self))))
  (widget:drop)
  (assert (> dropped.title 0) (.. message " should drop title"))
  (assert (> dropped.summary 0) (.. message " should drop summary"))
  (when widget.definition-search
    (assert (> dropped.definition-search 0) (.. message " should drop definition search")))
  (when widget.workflow-name-input (assert (> dropped.workflow-name-input 0) (.. message " should drop workflow name input")))
  (assert (> dropped.flex 0) (.. message " should drop flex")))

(fn target-node-by-key [targets key]
  (var found nil)
  (each [_ target (ipairs (assert targets "target-node-by-key requires targets"))]
    (local node (. target 1))
    (when (and node (= node.key key))
      (set found node)))
  found)

(fn with-app-workflow-runtime [runtime f]
  (local previous-workflow-store (and app app.workflow-store))
  (local previous-workflow-runner (and app app.workflow-runner))
  (local previous-code-store (and app app.code-store))
  (set app.workflow-store runtime.store)
  (set app.workflow-runner runtime.runner)
  (set app.code-store runtime.code-store)
  (local (ok result) (pcall f))
  (set app.workflow-store previous-workflow-store)
  (set app.workflow-runner previous-workflow-runner)
  (set app.code-store previous-code-store)
  (if ok result (error result)))

(fn start-node-includes-workflows-when-workflow-store-exists-case [runtime]
  (with-app-workflow-runtime runtime
    (fn []
      (local StartNode (require :graph/nodes/start))
      (local node (StartNode))
      (local targets (node:collect-targets))
      (local workflows-node (target-node-by-key targets "workflows"))
      (assert workflows-node "Start node should include Workflows target when workflow store exists")
      (assert (= workflows-node.label "Workflows") "Workflows target should use Workflows label"))))

(fn start-node-includes-workflows-when-workflow-store-exists []
  (with-runtime start-node-includes-workflows-when-workflow-store-exists-case))

(fn workflows-root-new-workflow-creates-and-loads-graph-nodes-case [runtime]
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "new-workflow-map"}))
  (local root (map:load-by-key "workflows"))
  (assert root "workflows root should load through key loader")
  (local action (action-named root.actions "New Workflow"))
  (assert action "workflows root should expose New Workflow action")
  (local result (root:create-workflow-from-graph {:name "Graph Created Workflow"}))
  (assert result.definition "New Workflow should create a workflow definition")
  (assert result.step "New Workflow should create a starter step")
  (assert result.code-entity "New Workflow should create a code entity")
  (assert (runtime.store:get-definition result.definition.id) "created workflow definition should be durable")
  (assert (runtime.code-store:get-entity result.code-entity.id) "created step code should be durable")
  (local definition-key (.. "workflow-definition:" result.definition.id))
  (local step-key (.. "workflow-step:" result.definition.id ":" result.step.id))
  (local code-key (.. "code-entity:" result.code-entity.id))
  (assert (map:lookup definition-key) "New Workflow should load definition node into graph map")
  (assert (map:lookup step-key) "New Workflow should load starter step node into graph map")
  (assert (map:lookup code-key) "New Workflow should load code entity node into graph map")
  (assert-edge-target map.edges definition-key "New Workflow should add definition edge")
  (assert-edge-target map.edges step-key "New Workflow should add starter step edge")
  (assert-edge-target map.edges code-key "New Workflow should add code edge")
  (map:drop))

(fn workflows-root-new-workflow-creates-and-loads-graph-nodes []
  (with-runtime workflows-root-new-workflow-creates-and-loads-graph-nodes-case))

(fn workflows-root-new-workflow-without-graph-does-not-persist-workflow-or-code-case [runtime]
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "new-workflow-missing-graph-map"}))
  (local root (map:load-by-key "workflows"))
  (assert root "workflows root should load through key loader")
  (local action (action-named root.actions "New Workflow"))
  (assert action "workflows root should expose New Workflow action")
  (set root.graph nil)
  (local before-definitions (length (runtime.store:list-definitions)))
  (local before-code (length (runtime.code-store:list-entities)))
  (local (ok err) (pcall action.fn action {:source :test}))
  (assert (not ok) "New Workflow without a graph should fail loudly")
  (assert (string.find (tostring err) "requires a graph map" 1 true)
          "New Workflow missing graph failure should explain the missing graph map")
  (assert (= (length (runtime.store:list-definitions)) before-definitions)
          "failed New Workflow without graph should not persist a workflow definition")
  (assert (= (length (runtime.code-store:list-entities)) before-code)
          "failed New Workflow without graph should not persist a code entity")
  (map:drop))

(fn workflows-root-new-workflow-without-graph-does-not-persist-workflow-or-code []
  (with-runtime workflows-root-new-workflow-without-graph-does-not-persist-workflow-or-code-case))

(fn workflows-preview-builds-with-new-workflow-action-case [runtime]
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "workflow-preview-map"}))
  (local node (map:load-by-key "workflows"))
  (local (loaded? Preview) (pcall require :graph/view/previews/workflows))
  (assert loaded? "workflows preview module should load")
  (assert-missing-build-context-with-fallbacks
    Preview node
    "workflows preview should not fall back to opts.ctx or graph.ctx")
  (local builder (Preview node {:node node}))
  (assert-missing-build-context builder "workflows preview should assert on missing build context")
  (local widget (builder (make-preview-ctx)))
  (assert widget "workflows preview should build a widget")
  (assert widget.workflow-name-input "workflows preview should expose workflow name input")
  (assert widget.new-workflow-button "workflows preview should expose a New Workflow button")
  (assert widget.new-workflow-row "workflows preview should expose New Workflow row")
  (assert (= (. widget.new-workflow-row.children 1 :element) widget.workflow-name-input) "workflow name input should be a child of New Workflow row")
  (assert (= (. widget.new-workflow-row.children 2 :element) widget.new-workflow-button) "New Workflow button should be a child of New Workflow row")
  (local before (length (runtime.store:list-definitions))) (widget.workflow-name-input:set-text "Help Desk Intake") (widget.new-workflow-button:on-click {:source :test})
  (assert (= (length (runtime.store:list-definitions)) (+ before 1)) "New Workflow preview button should create a definition")
  (assert (definition-named? runtime.store "Help Desk Intake") "New Workflow preview button should persist the typed workflow name") (widget:drop) (map:drop))
(fn workflows-preview-builds-with-new-workflow-action [] (with-runtime workflows-preview-builds-with-new-workflow-action-case))
(fn workflows-preview-blank-name-keeps-default-workflow-name-case [runtime] (local map (GraphMap.GraphMap {:graph runtime.graph :id "workflow-preview-blank-name-map"})) (local node (map:load-by-key "workflows")) (local Preview (require :graph/view/previews/workflows)) (local widget ((Preview node {:node node}) (make-preview-ctx))) (assert widget.workflow-name-input "workflows preview should expose workflow name input for blank-name flow") (widget.workflow-name-input:set-text "   ") (widget.new-workflow-button:on-click {:source :test}) (assert (definition-named? runtime.store "Untitled Workflow") "blank workflow name input should preserve default Untitled Workflow behavior") (widget:drop) (map:drop))
(fn workflows-preview-blank-name-keeps-default-workflow-name [] (with-runtime workflows-preview-blank-name-keeps-default-workflow-name-case))

(fn seed-definition-with-run [runtime]
  (local code-a (runtime.code-store:create-entity {:id "code-a" :name "A" :source "(+ 1 1)"}))
  (local code-b (runtime.code-store:create-entity {:id "code-b" :name "B" :source "(+ 2 2)"}))
  (local definition (runtime.store:create-definition {:id "wf-demo"
                                                     :name "Demo workflow"
                                                     :steps [{:id "step-a" :name "A" :code-entity-id code-a.id}
                                                             {:id "step-b" :name "B" :code-entity-id code-b.id}]
                                                     :edges [{:id "edge-a-b" :source-step-id "step-a" :target-step-id "step-b"}]}))
  (local run (runtime.runner:start-run definition.id {:prompt "go"} {:source :test}))
  (runtime.store:upsert-run-step run.id "step-a" {:status :succeeded :output {:answer 42}})
  (runtime.store:upsert-run-step run.id "step-b" {:status :failed :error {:message "boom"}})
  (local event (runtime.store:append-event run.id {:id "event-started" :kind :step-started :step-id "step-a"}))
  {:definition definition :run (runtime.store:get-run run.id) :event event})
(fn seed-two-definitions-with-run [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local other (runtime.store:create-definition {:id "wf-other"
                                                 :name "Other workflow"
                                                 :steps []
                                                 :edges []}))
  {:selected seeded.definition
   :other other
    :run seeded.run})
(fn seed-two-definitions-with-runs [runtime] (local seeded (seed-definition-with-run runtime)) (local other (runtime.store:create-definition {:id "wf-other" :name "Other workflow" :steps [] :edges []})) (local other-run (runtime.store:create-run other.id {:prompt "other"} {:source :other-test})) {:selected seeded.definition :other other :selected-run seeded.run :other-run other-run})
(fn workflow-run-explorer-lists-only-definition-runs-case [runtime] (local seeded (seed-two-definitions-with-runs runtime)) (local map (GraphMap.GraphMap {:graph runtime.graph :id "run-explorer-list-map"})) (local explorer (map:load-by-key (.. "workflow-run-explorer:" seeded.selected.id))) (assert explorer "workflow-run-explorer key should load") (local items (explorer:run-items)) (assert (= (length items) 1) "run explorer should list selected definition runs") (assert (= (. items 1 1 :id) seeded.selected-run.id) "run explorer should include selected run") (each [_ item (ipairs items)] (assert (= (. item 1 :definition-id) seeded.selected.id) "run explorer should exclude foreign definition runs")) (map:drop))
(fn workflow-run-explorer-preview-search-materializes-one-run-case [runtime] (local seeded (seed-two-definitions-with-runs runtime)) (local map (GraphMap.GraphMap {:graph runtime.graph :id "run-explorer-select-map"})) (local explorer (map:load-by-key (.. "workflow-run-explorer:" seeded.selected.id))) (local Preview (require :graph/view/previews/workflow-run-explorer)) (assert-missing-build-context-with-fallbacks Preview explorer "workflow run explorer preview should not fall back to opts.ctx or graph.ctx") (local builder (Preview explorer {:node explorer})) (assert-missing-build-context builder "workflow run explorer preview should require direct build context") (local widget (builder (make-preview-ctx))) (each [_ field (ipairs [:title :summary-text :run-count-text :run-search :flex])] (assert (. widget field) (.. "workflow run explorer preview should expose " (tostring field)))) (assert-contains (text-widget-string widget.run-search.input.placeholder) "Search workflow runs" "run explorer search should use run search hint") (widget.run-search.submitted:emit (. (explorer:run-items) 1)) (local selected-run-key (.. "workflow-run:" seeded.selected-run.id)) (assert (map:lookup selected-run-key) "run explorer search should load selected run") (var edge-found false) (each [_ edge (ipairs map.edges)] (when (and (= (and edge.source edge.source.key) explorer.key) (= (and edge.target edge.target.key) selected-run-key)) (set edge-found true))) (assert edge-found "run explorer search should add explorer-to-run edge") (assert (not (map:lookup (.. "workflow-run:" seeded.other-run.id))) "run explorer search should not load foreign runs") (widget:drop) (map:drop))
(fn workflow-run-explorer-preview-drops-owned-children-and-search-listener-case [runtime] (local seeded (seed-two-definitions-with-runs runtime)) (local map (GraphMap.GraphMap {:graph runtime.graph :id "run-explorer-drop-map"})) (local explorer (map:load-by-key (.. "workflow-run-explorer:" seeded.selected.id))) (local Preview (require :graph/view/previews/workflow-run-explorer)) (local widget ((Preview explorer {:node explorer}) (make-preview-ctx))) (local dropped {:title 0 :run-count 0 :run-search 0 :flex 0}) (each [_ pair (ipairs [[:title :title] [:run-count-text :run-count] [:run-search :run-search] [:flex :flex]])] (wrap-preview-drop-counter widget dropped (. pair 1) (. pair 2))) (widget:drop) (assert (= widget.__run-search-listener nil) "run explorer drop should clear search listener handle") (assert-drop-counts dropped "workflow run explorer preview drop") (widget.run-search.submitted:emit (. (explorer:run-items) 1)) (assert (not (map:lookup (.. "workflow-run:" seeded.selected-run.id))) "dropped run explorer search listener should not load a run") (map:drop))
(fn workflows-preview-search-selects-one-definition-only-case [runtime]
  (local seeded (seed-two-definitions-with-run runtime))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "definition-search-map"}))
  (local root (map:load-by-key "workflows"))
  (local Preview (require :graph/view/previews/workflows))
  (local widget ((Preview root {:node root}) (make-preview-ctx)))
  (assert widget.definition-search "workflows preview should expose definition search")
  (assert widget.definition-count-text "workflows preview should expose definition count text")
  (assert (not widget.show-existing-button) "workflows preview should not expose bulk existing workflows button")
  (local count-text (text-widget-string widget.definition-count-text))
  (assert-contains count-text "Definitions: 2" "workflows preview should count definitions only")
  (local selected-item (. (root:definition-items) 1))
  (widget.definition-search.submitted:emit selected-item)
  (local selected-key (.. "workflow-definition:" (. selected-item 1 :id)))
  (local other-key (.. "workflow-definition:" seeded.other.id))
  (local run-key (.. "workflow-run:" seeded.run.id))
  (assert (map:lookup selected-key) "definition search submit should load selected definition")
  (assert (not (map:lookup other-key)) "definition search submit should not load unselected definitions")
  (assert (not (map:lookup run-key)) "definition search submit should not load workflow runs")
  (assert-edge-target map.edges selected-key "definition search submit should add root-to-definition edge")
  (assert-preview-drops-owned-children widget "workflows preview")
  (map:drop))
(fn workflows-preview-search-selects-one-definition-only []
  (with-runtime workflows-preview-search-selects-one-definition-only-case))

(fn workflows-root-does-not-load-runs-directly-case [runtime]
  (local seeded (seed-two-definitions-with-run runtime))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "definition-only-root-map"}))
  (local root (map:load-by-key "workflows"))
  (assert root "workflows root should load through key loader")
  (assert (not (action-named root.actions "Show Existing Workflows"))
          "workflows root should not expose bulk Show Existing Workflows action")
  (assert root.definition-items "workflows root should expose definition items")
  (assert root.load-definition-from-graph "workflows root should load one selected definition")
  (assert (not root.load-existing-workflows) "workflows root should not expose bulk existing workflow loader")
  (local loaded (root:load-definition-from-graph seeded.selected))
  (local definition-key (.. "workflow-definition:" seeded.selected.id))
  (local other-key (.. "workflow-definition:" seeded.other.id))
  (local run-key (.. "workflow-run:" seeded.run.id))
  (assert (= loaded.key definition-key) "selected definition loader should return the selected node")
  (assert (map:lookup definition-key) "selected definition loader should load the selected definition")
  (assert (not (map:lookup other-key)) "selected definition loader should not load other definitions")
  (assert (not (map:lookup run-key)) "workflows root should not load workflow runs directly")
  (assert-edge-target map.edges definition-key "selected definition loader should add root-to-definition edge")
  (map:drop))

(fn workflows-root-does-not-load-runs-directly []
  (with-runtime workflows-root-does-not-load-runs-directly-case))

(fn with-definition-run-preview [runtime map-id f]
  (local seeded (seed-two-definitions-with-runs runtime)) (local map (GraphMap.GraphMap {:graph runtime.graph :id map-id})) (local node (map:load-by-key (.. "workflow-definition:" seeded.selected.id))) (local Preview (require :graph/view/previews/workflow-definition))
  (local widget ((Preview node {:node node}) (make-preview-ctx))) (local (ok result) (pcall f seeded map node widget)) (widget:drop) (map:drop) (if ok result (error result)))

(fn with-definition-structured-preview [runtime map-id f] (local seeded (seed-two-definitions-with-runs runtime)) (local map (GraphMap.GraphMap {:graph runtime.graph :id map-id})) (local node (map:load-by-key (.. "workflow-definition:" seeded.selected.id))) (local Preview (require :graph/view/previews/workflow-definition)) (local widget ((Preview node {:node node}) (make-preview-ctx))) (local (ok result) (pcall f seeded map node widget)) (when (not widget.__dropped) (widget:drop)) (map:drop) (if ok result (error result)))
(fn search-placeholder-string [search] (text-widget-string search.input.placeholder))
(fn workflow-definition-preview-selects-latest-run-by-created-at-case [runtime] (local definition (runtime.store:create-definition {:id "wf-run-recency-preview" :name "Run recency" :steps [] :edges []})) (local first-run (runtime.store:create-run definition.id {} {})) (local second-run (runtime.store:create-run definition.id {} {})) (local newer (if (< first-run.id second-run.id) first-run second-run)) (local older (if (= newer first-run) second-run first-run)) (runtime.store:update-run newer.id {:created-at 200 :status :succeeded}) (runtime.store:update-run older.id {:created-at 100 :status :failed}) (local node (runtime.graph:load-by-key (.. "workflow-definition:" definition.id))) (local Preview (require :graph/view/previews/workflow-definition)) (local widget ((Preview node {:node node}) (make-preview-ctx))) (local overview (text-widget-string widget.overview-text)) (assert-contains overview "Runs: 2" "workflow definition overview should count recency test runs") (assert-contains overview "Latest: succeeded" "workflow definition overview should select latest run by created-at instead of list order") (widget:drop))
(fn workflow-definition-preview-selects-latest-run-by-created-at [] (with-runtime workflow-definition-preview-selects-latest-run-by-created-at-case))
(fn workflow-definition-preview-builds-structured-inspector-case [runtime] (local seeded (seed-two-definitions-with-runs runtime)) (local node (runtime.graph:load-by-key (.. "workflow-definition:" seeded.selected.id))) (local Preview (require :graph/view/previews/workflow-definition)) (assert-missing-build-context-with-fallbacks Preview node "workflow definition compact preview should not fall back to opts.ctx or graph.ctx") (local builder (Preview node {:node node})) (assert-missing-build-context builder "workflow definition compact preview should require direct build context") (local widget (builder (make-preview-ctx))) (each [_ field (ipairs [:title :overview-text :summary-text :open-steps-button :open-runs-button :start-button :new-step-button :flex])] (assert (. widget field) (.. "workflow definition compact preview should expose " (tostring field)))) (each [_ field (ipairs [:step-search :run-search :reveal-all-steps-button :step-count-text :run-count-text])] (assert (not (. widget field)) (.. "workflow definition compact preview should not expose " (tostring field)))) (assert-contains (text-widget-string widget.title) "Demo workflow" "workflow definition title should use node label") (local overview (text-widget-string widget.overview-text)) (each [_ needle (ipairs ["wf-demo" "Demo workflow" "Steps: 2" "Runs: 1" (.. "Latest: " (tostring seeded.selected-run.status))])] (assert-contains overview needle "workflow definition overview should include structured summary data")) (widget:drop))
(fn workflow-definition-preview-builds-structured-inspector [] (with-runtime workflow-definition-preview-builds-structured-inspector-case))
(fn workflow-definition-preview-step-search-reveals-one-step-body [seeded map node widget] (local selected-item (. (node:step-items) 1)) (widget.step-search.submitted:emit selected-item) (local selected-step-key (.. "workflow-step:" seeded.selected.id ":" (. selected-item 1 :id))) (assert (map:lookup selected-step-key) "step search submit should load selected step") (assert (not (map:lookup (.. "workflow-step:" seeded.selected.id ":step-b"))) "step search submit should not load sibling steps") (assert (not (map:lookup (.. "workflow-step:" seeded.other.id ":other-step"))) "step search submit should not load foreign definition steps") (assert-edge-target map.edges selected-step-key "step search submit should add definition-to-step edge") (widget.run-search.submitted:emit (. (node:run-items) 1)) (assert (map:lookup (.. "workflow-run:" seeded.selected-run.id)) "run search submit should still load selected definition run") (assert (not (map:lookup (.. "workflow-run:" seeded.other-run.id))) "run search submit should still ignore other definition runs"))
(fn workflow-definition-preview-step-search-reveals-one-step-case [runtime] (with-definition-structured-preview runtime "definition-step-search-preview-map" workflow-definition-preview-step-search-reveals-one-step-body))
(fn workflow-definition-preview-step-search-reveals-one-step [] (with-runtime workflow-definition-preview-step-search-reveals-one-step-case))
(fn workflow-step-explorer-reveal-all-button-materializes-steps-case [runtime] (local seeded-run (seed-definition-with-run runtime)) (local other-code (runtime.code-store:create-entity {:id "code-other-step-preview" :name "Other" :source "(+ 3 3)"})) (local other (runtime.store:create-definition {:id "wf-other-steps-preview" :name "Other steps" :steps [{:id "other-step" :name "Other" :code-entity-id other-code.id}] :edges []})) (local seeded {:selected seeded-run.definition :other other}) (local map (GraphMap.GraphMap {:graph runtime.graph :id "step-explorer-reveal-map"})) (local explorer (map:load-by-key (.. "workflow-step-explorer:" seeded.selected.id))) (local Preview (require :graph/view/previews/workflow-step-explorer)) (local widget ((Preview explorer {:node explorer}) (make-preview-ctx))) (widget.reveal-all-steps-button:on-click {:source :test}) (assert (map:lookup (.. "workflow-step:" seeded.selected.id ":step-a"))) (assert (map:lookup (.. "workflow-step:" seeded.selected.id ":step-b"))) (assert (not (map:lookup (.. "workflow-step:" seeded.other.id ":other-step")))) (widget:drop) (map:drop))
(fn workflow-step-explorer-reveal-all-button-materializes-steps [] (with-runtime workflow-step-explorer-reveal-all-button-materializes-steps-case))
(fn workflow-definition-preview-open-explorer-buttons-body [seeded map _node widget] (widget.open-steps-button:on-click {:source :test}) (local step-explorer-key (.. "workflow-step-explorer:" seeded.selected.id)) (assert (map:lookup step-explorer-key) "Open Steps button should load workflow-step-explorer node") (assert-edge-target map.edges step-explorer-key "Open Steps button should add definition-to-step-explorer edge") (widget.open-runs-button:on-click {:source :test}) (local run-explorer-key (.. "workflow-run-explorer:" seeded.selected.id)) (assert (map:lookup run-explorer-key) "Open Runs button should load workflow-run-explorer node") (assert-edge-target map.edges run-explorer-key "Open Runs button should add definition-to-run-explorer edge") (assert (not (map:lookup (.. "workflow-step:" seeded.selected.id ":step-a"))) "explorer buttons should not load step payload nodes") (assert (not (map:lookup (.. "workflow-run:" seeded.selected-run.id))) "explorer buttons should not load run payload nodes"))
(fn workflow-definition-preview-open-explorer-buttons-case [runtime] (with-definition-structured-preview runtime "definition-explorer-buttons-preview-map" workflow-definition-preview-open-explorer-buttons-body))
(fn workflow-definition-preview-open-explorer-buttons [] (with-runtime workflow-definition-preview-open-explorer-buttons-case))
(fn workflow-definition-preview-drops-owned-children-and-search-listeners-body [_seeded _map _node widget] (local dropped {:title 0 :overview 0 :open-steps 0 :open-runs 0 :start 0 :new-step 0 :flex 0}) (each [_ pair (ipairs [[:title :title] [:overview-text :overview] [:open-steps-button :open-steps] [:open-runs-button :open-runs] [:start-button :start] [:new-step-button :new-step] [:flex :flex]])] (wrap-preview-drop-counter widget dropped (. pair 1) (. pair 2))) (widget:drop) (assert (= widget.__step-search-listener nil) "compact drop should not retain step search listener handle") (assert (= widget.__run-search-listener nil) "compact drop should not retain run search listener handle") (assert-drop-counts dropped "workflow definition compact preview drop"))
(fn workflow-definition-preview-drops-owned-children-and-search-listeners-case [runtime] (with-definition-structured-preview runtime "definition-preview-drop-map" workflow-definition-preview-drops-owned-children-and-search-listeners-body))
(fn workflow-definition-preview-drops-owned-children-and-search-listeners [] (with-runtime workflow-definition-preview-drops-owned-children-and-search-listeners-case))

(fn workflow-definition-preview-search-selects-one-run-case [runtime]
  (with-definition-run-preview runtime "definition-run-search-map" (fn [seeded map node widget]
    (assert widget.run-search "workflow definition preview should expose run search") (assert widget.run-count-text "workflow definition preview should expose run count text")
    (assert widget.start-button "workflow definition preview should keep Start button") (assert widget.new-step-button "workflow definition preview should keep New Step button") (assert-contains (text-widget-string widget.run-count-text) "Runs: 1" "definition preview should count only this definition's runs")
    (widget.run-search.submitted:emit (. (node:run-items) 1)) (local selected-run-key (.. "workflow-run:" seeded.selected-run.id)) (assert (map:lookup selected-run-key) "run search submit should load selected run")
    (assert (not (map:lookup (.. "workflow-run:" seeded.other-run.id))) "run search submit should not load runs from other definitions")
    (assert-edge-target map.edges selected-run-key "run search submit should add definition-to-run edge"))))
(fn workflow-definition-run-search-filters-to-definition-case [runtime]
  (with-definition-run-preview runtime "definition-run-filter-map" (fn [seeded map node widget]
    (local items (node:run-items)) (assert (= (length items) 1) "workflow definition run items should include only selected definition runs")
    (assert (= (. items 1 1 :id) seeded.selected-run.id) "workflow definition run item should be selected definition's run") (widget.run-search.submitted:emit (. items 1))
    (assert (map:lookup (.. "workflow-run:" seeded.selected-run.id)) "filtered run search should load selected definition's run")
    (assert (not (map:lookup (.. "workflow-run:" seeded.other-run.id))) "filtered run search should not load other definition's run"))))
(fn workflow-definition-load-run-rejects-foreign-definition-case [runtime]
  (with-definition-run-preview runtime "definition-run-foreign-map" (fn [seeded map node _widget]
    (local foreign-key (.. "workflow-run:" seeded.other-run.id)) (local (ok err) (pcall node.load-run-from-graph node seeded.other-run))
    (assert (not ok) "workflow definition should reject a run owned by another definition") (assert (string.find (tostring err) "does not belong" 1 true) "foreign run failure should explain ownership mismatch")
    (assert (not (map:lookup foreign-key)) "foreign run rejection should not materialize the run node") (assert (not (. (edge-target-key-set map.edges) foreign-key)) "foreign run rejection should not add a visible edge"))))
(fn seed-two-definitions-with-steps [runtime] (local seeded (seed-definition-with-run runtime)) (local other-code (runtime.code-store:create-entity {:id "code-other-step" :name "Other" :source "(+ 3 3)"})) (local other (runtime.store:create-definition {:id "wf-other-steps" :name "Other steps" :steps [{:id "other-step" :name "Other" :code-entity-id other-code.id}] :edges []})) {:selected seeded.definition :other other}) (fn workflow-definition-step-items-filter-to-definition-case [runtime] (local seeded (seed-two-definitions-with-steps runtime)) (local map (GraphMap.GraphMap {:graph runtime.graph :id "definition-step-items-map"})) (local node (map:load-by-key (.. "workflow-definition:" seeded.selected.id))) (local items (node:step-items)) (assert (= (length items) 2) "workflow definition step items should include only selected definition steps") (assert (= (. items 1 1 :id) "step-a") "workflow definition step items should include selected definition step-a") (assert (= (. items 2 1 :id) "step-b") "workflow definition step items should include selected definition step-b") (each [_ item (ipairs items)] (assert (not (= (. item 1 :id) "other-step")) "workflow definition step items should exclude other definition steps")) (map:drop)) (fn workflow-definition-step-items-filter-to-definition [] (with-runtime workflow-definition-step-items-filter-to-definition-case)) (fn workflow-definition-load-step-materializes-one-selected-step-case [runtime] (local seeded (seed-two-definitions-with-steps runtime)) (local map (GraphMap.GraphMap {:graph runtime.graph :id "definition-load-step-map"})) (local node (map:load-by-key (.. "workflow-definition:" seeded.selected.id))) (local loaded (node:load-step-from-graph {:id "step-a"})) (local selected-key (.. "workflow-step:" seeded.selected.id ":step-a")) (local sibling-key (.. "workflow-step:" seeded.selected.id ":step-b")) (local foreign-key (.. "workflow-step:" seeded.other.id ":other-step")) (assert (= loaded.key selected-key) "selected step loader should return the selected step node") (assert (map:lookup selected-key) "selected step loader should load selected step") (assert (not (map:lookup sibling-key)) "selected step loader should not load sibling steps") (assert (not (map:lookup foreign-key)) "selected step loader should not load foreign definition steps") (assert-edge-target map.edges selected-key "selected step loader should add definition-to-step edge") (map:drop)) (fn workflow-definition-load-step-materializes-one-selected-step [] (with-runtime workflow-definition-load-step-materializes-one-selected-step-case)) (fn workflow-definition-reveal-all-steps-materializes-steps-and-derived-workflow-edges-case [runtime] (local seeded (seed-two-definitions-with-steps runtime)) (local map (GraphMap.GraphMap {:graph runtime.graph :id "definition-reveal-steps-map"})) (local node (map:load-by-key (.. "workflow-definition:" seeded.selected.id))) (local result (node:reveal-all-steps-from-graph)) (local step-a-key (.. "workflow-step:" seeded.selected.id ":step-a")) (local step-b-key (.. "workflow-step:" seeded.selected.id ":step-b")) (local foreign-key (.. "workflow-step:" seeded.other.id ":other-step")) (assert (= result.step-count 2) "reveal all should report selected definition step count") (assert (= result.edge-count 1) "reveal all should report selected definition workflow edge count") (assert (map:lookup step-a-key) "reveal all should load step-a") (assert (map:lookup step-b-key) "reveal all should load step-b") (assert (not (map:lookup foreign-key)) "reveal all should not load foreign steps") (assert-edge-target map.edges step-a-key "reveal all should add definition edge to step-a") (assert-edge-target map.edges step-b-key "reveal all should add definition edge to step-b") (local state (map:capture-state)) (var captured-derived? false) (each [_ edge (ipairs state.edges)] (when (and (= edge.source step-a-key) (= edge.target step-b-key)) (set captured-derived? true))) (assert (not captured-derived?) "reveal all workflow-derived step edges should not be captured as map topology") (map:drop)) (fn workflow-definition-reveal-all-steps-materializes-steps-and-derived-workflow-edges [] (with-runtime workflow-definition-reveal-all-steps-materializes-steps-and-derived-workflow-edges-case)) (fn workflow-definition-open-step-explorer-materializes-ux-node-case [runtime] (local seeded (seed-two-definitions-with-steps runtime)) (local map (GraphMap.GraphMap {:graph runtime.graph :id "definition-open-step-explorer-map"})) (local node (map:load-by-key (.. "workflow-definition:" seeded.selected.id))) (local explorer (node:open-step-explorer-from-graph)) (local explorer-key (.. "workflow-step-explorer:" seeded.selected.id)) (assert (= explorer.key explorer-key) "open step explorer should return the explorer node") (assert (map:lookup explorer-key) "open step explorer should materialize the explorer UX node") (assert-edge-target map.edges explorer-key "open step explorer should add definition-to-explorer edge") (assert (= explorer.workflow-definition-id seeded.selected.id) "step explorer should reference selected definition") (assert (not explorer.workflow-step-id) "step explorer should not own a workflow step record") (map:drop)) (fn workflow-definition-open-step-explorer-materializes-ux-node [] (with-runtime workflow-definition-open-step-explorer-materializes-ux-node-case)) (fn workflow-step-explorer-preview-search-selects-one-step-case [runtime] (local seeded (seed-two-definitions-with-steps runtime)) (local map (GraphMap.GraphMap {:graph runtime.graph :id "step-explorer-preview-map"})) (local definition-node (map:load-by-key (.. "workflow-definition:" seeded.selected.id))) (local explorer (definition-node:open-step-explorer-from-graph)) (local (loaded? Preview) (pcall require :graph/view/previews/workflow-step-explorer)) (assert loaded? "workflow step explorer preview module should load") (assert-missing-build-context-with-fallbacks Preview explorer "workflow step explorer preview should not fall back to opts.ctx or graph.ctx") (local builder (Preview explorer {:node explorer})) (assert-missing-build-context builder "workflow step explorer preview should assert on missing build context") (local widget (builder (make-preview-ctx))) (assert widget.step-search "workflow step explorer preview should expose step search") (assert widget.step-count-text "workflow step explorer preview should expose step count text") (assert widget.reveal-all-steps-button "workflow step explorer preview should expose reveal all steps button") (assert-contains (text-widget-string widget.step-count-text) "Steps: 2" "workflow step explorer preview should count selected definition steps") (widget.step-search.submitted:emit (. (explorer:step-items) 1)) (local selected-key (.. "workflow-step:" seeded.selected.id ":step-a")) (local sibling-key (.. "workflow-step:" seeded.selected.id ":step-b")) (assert (map:lookup selected-key) "step explorer search submit should load selected step") (assert (not (map:lookup sibling-key)) "step explorer search submit should not load sibling step") (assert-edge-target map.edges selected-key "step explorer search submit should add explorer-to-step edge") (widget:drop) (map:drop)) (fn workflow-step-explorer-preview-search-selects-one-step [] (with-runtime workflow-step-explorer-preview-search-selects-one-step-case))
(fn workflow-step-explorer-preview-drops-owned-children-and-search-listener-case [runtime] (local seeded (seed-two-definitions-with-steps runtime)) (local map (GraphMap.GraphMap {:graph runtime.graph :id "step-explorer-drop-map"})) (local explorer (map:load-by-key (.. "workflow-step-explorer:" seeded.selected.id))) (local Preview (require :graph/view/previews/workflow-step-explorer)) (assert-missing-build-context-with-fallbacks Preview explorer "workflow step explorer preview should not fall back to opts.ctx or graph.ctx") (local builder (Preview explorer {:node explorer})) (assert-missing-build-context builder "workflow step explorer preview should assert on missing build context") (local widget (builder (make-preview-ctx))) (local dropped {:title 0 :step-count 0 :step-search 0 :reveal-all 0 :flex 0}) (each [_ pair (ipairs [[:title :title] [:step-count-text :step-count] [:step-search :step-search] [:reveal-all-steps-button :reveal-all] [:flex :flex]])] (wrap-preview-drop-counter widget dropped (. pair 1) (. pair 2))) (widget:drop) (assert (= widget.__step-search-listener nil) "step explorer drop should clear search listener handle") (assert-drop-counts dropped "workflow step explorer preview drop") (widget.step-search.submitted:emit (. (explorer:step-items) 1)) (assert (not (map:lookup (.. "workflow-step:" seeded.selected.id ":step-a"))) "dropped step explorer search listener should not load a step") (map:drop))
(fn workflow-step-explorer-preview-drops-owned-children-and-search-listener [] (with-runtime workflow-step-explorer-preview-drops-owned-children-and-search-listener-case))
(fn workflow-run-node-and-preview-have-no-generic-details-leftovers-case [runtime] (local seeded (seed-definition-with-run runtime)) (local map (GraphMap.GraphMap {:graph runtime.graph :id "run-details-leftovers-map"})) (local node (map:load-by-key (.. "workflow-run:" seeded.run.id))) (local actions (node:actions)) (assert (not (action-named? actions "Show Details")) "run node should not expose Show Details") (assert (not (action-named? actions "Hide Details")) "run node should not expose Hide Details") (local Preview (require :graph/view/previews/workflow-run)) (local widget ((Preview node {:node node}) (make-preview-ctx))) (assert (not widget.show-details-button) "run preview should not expose show-details-button") (assert (not widget.hide-details-button) "run preview should not expose hide-details-button") (widget:drop) (map:drop) (assert (and app app.engine app.engine.get-asset-path) "workflow-run source test requires app.engine.get-asset-path") (local source (fs.read-file (app.engine.get-asset-path "lua/graph/nodes/workflow-run.fnl"))) (assert-not-contains source "details-expanded?" "workflow-run node source should not retain details-expanded?"))
(fn workflow-run-node-and-preview-have-no-generic-details-leftovers [] (with-runtime workflow-run-node-and-preview-have-no-generic-details-leftovers-case))

(fn seed-agent-session-run [runtime] (local definition (runtime.store:create-definition {:id "wf-agent-session-graph" :name "Agent Session Workflow" :steps [] :edges []})) (local run (runtime.store:create-run definition.id {} {:kind :agent-session :agent-session? true :agent-id "opencode"})) (WorkflowEvents.append-session-created runtime.store run.id {:kind :agent-session :agent-session? true :agent-id "opencode" :data {:topic "Graph parity"}}) (WorkflowEvents.append-item runtime.store run.id {:id "item-user" :role "user" :content "hello"}) (WorkflowEvents.append-item runtime.store run.id {:id "item-assistant" :role "assistant" :content "hi"}) (WorkflowEvents.append-status runtime.store run.id :waiting {}) {:definition definition :run (runtime.store:get-run run.id) :session (WorkflowEvents.project-session (runtime.store:get-run run.id))})

(fn agent-session-key-loads-workflow-backed-session-case [runtime]
  (local seeded (seed-agent-session-run runtime))
  (local node (runtime.graph:create-node-by-key (.. "agent-session:" seeded.run.id)))
  (assert node "agent-session key should resolve workflow-backed session")
  (assert (= node.key (.. "agent-session:" seeded.run.id)) "agent session node key should use workflow run id")
  (assert (= node.label (.. "Agent session " seeded.run.id " (waiting)")) "agent session title should project status")
  (assert (= node.agent-session.status :waiting) "agent session node should expose projected status")
  (assert (= (length node.agent-session.items) 2) "agent session node should expose projected item count"))

(fn agent-session-key-loads-workflow-backed-session []
  (with-runtime agent-session-key-loads-workflow-backed-session-case))

(fn agent-session-node-loads-backing-workflow-run-case [runtime]
  (local seeded (seed-agent-session-run runtime))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "agent-session-map"}))
  (local node (map:load-by-key (.. "agent-session:" seeded.run.id)))
  (assert node "agent-session node should load through graph map")
  (assert (action-named node.actions "Open Workflow Run") "agent-session node should expose backing run action")
  (assert (action-named node.actions "Show Recent Events") "agent-session node should expose recent events action")
  (local run-node (node:load-backing-workflow-run))
  (assert run-node "Open Workflow Run should return the loaded run node")
  (assert (= run-node.key (.. "workflow-run:" seeded.run.id)) "Open Workflow Run should load workflow-run node")
  (assert-edge-target map.edges run-node.key "Open Workflow Run should add session-to-run edge")
  (local event-nodes (node:load-recent-run-events))
  (assert (>= (length event-nodes) 4) "Show Recent Events should load projected run events")
  (assert (map:lookup (. event-nodes 1 :key)) "Show Recent Events should make event nodes visible in graph map")
  (map:drop))

(fn agent-session-node-loads-backing-workflow-run []
  (with-runtime agent-session-node-loads-backing-workflow-run-case))

(fn agent-session-node-loads-only-recent-workflow-events-case [runtime]
  (local seeded (seed-agent-session-run runtime))
  (local recent-limit AgentSessionGraphNode.RECENT_EVENT_LIMIT)
  (for [i 1 (+ recent-limit 3)]
    (runtime.store:append-event seeded.run.id {:id (.. "history-" i)
                                               :kind :agent-history
                                               :index i}))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "agent-session-recent-events-map"}))
  (local node (map:load-by-key (.. "agent-session:" seeded.run.id)))
  (assert node "agent-session node should load through graph map")
  (local event-nodes (node:load-recent-run-events))
  (assert (= (length event-nodes) recent-limit) "Show Recent Events should load a bounded recent window")
  (assert (not (map:lookup (.. "workflow-run-event:" seeded.run.id ":history-1")))
          "Show Recent Events should not load stale historical events")
  (assert (map:lookup (.. "workflow-run-event:" seeded.run.id ":history-4"))
          "Show Recent Events should include the oldest event inside the recent window")
  (assert (map:lookup (.. "workflow-run-event:" seeded.run.id ":history-" (+ recent-limit 3)))
          "Show Recent Events should load newest workflow events")
  (map:drop))

(fn agent-session-node-loads-only-recent-workflow-events []
  (with-runtime agent-session-node-loads-only-recent-workflow-events-case))

(fn agent-session-preview-requires-direct-context-case [runtime]
  (local seeded (seed-agent-session-run runtime))
  (local node (runtime.graph:load-by-key (.. "agent-session:" seeded.run.id)))
  (local (loaded? Preview) (pcall require :graph/view/previews/agent-session))
  (assert loaded? "agent session preview module should load")
  (assert-missing-build-context-with-fallbacks
    Preview node
    "agent session preview should not fall back to opts.ctx or graph.ctx")
  (local builder (Preview node {:node node}))
  (assert-missing-build-context builder "agent session preview should assert on missing build context"))

(fn agent-session-preview-requires-direct-context []
  (with-runtime agent-session-preview-requires-direct-context-case))

(fn agent-session-preview-shows-status-and-item-count-case [runtime]
  (local seeded (seed-agent-session-run runtime))
  (local node (runtime.graph:load-by-key (.. "agent-session:" seeded.run.id)))
  (local Preview (require :graph/view/previews/agent-session))
  (local widget ((Preview node {:node node}) (make-preview-ctx)))
  (assert widget.summary-text "agent session preview should expose summary text")
  (local summary (text-widget-string widget.summary-text))
  (assert-contains summary "Status: waiting" "agent session preview should show projected status")
  (assert-contains summary "Agent: opencode" "agent session preview should show projected agent id")
  (assert-contains summary "Items: 2" "agent session preview should show projected item count")
  (assert-preview-drops-owned-children widget "agent session preview"))

(fn agent-session-preview-shows-status-and-item-count []
  (with-runtime agent-session-preview-shows-status-and-item-count-case))

(fn workflow-key-loaders-resolve-all-workflow-keys-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local graph runtime.graph)
  (local keys ["workflows"
               (.. "workflow-definition:" seeded.definition.id)
               (.. "workflow-step:" seeded.definition.id ":step-a")
               (.. "workflow-run:" seeded.run.id)
               (.. "workflow-run-step:" seeded.run.id ":step-a")
               (.. "workflow-run-event:" seeded.run.id ":" seeded.event.id)
               (.. "workflow-run-timeline:" seeded.run.id)])
  (each [_ key (ipairs keys)]
    (local node (graph:create-node-by-key key))
    (assert node (.. "workflow key should resolve: " key))
    (assert (= node.key key) (.. "workflow key should match: " key))))

(fn workflow-key-loaders-resolve-all-workflow-keys []
  (with-runtime workflow-key-loaders-resolve-all-workflow-keys-case))

(fn missing-key-result [graph key]
  (graph:create-node-by-key key))

(fn workflow-key-loaders-return-nil-for-missing-records-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local graph runtime.graph)
  (local keys ["workflow-definition:missing"
                   "workflow-step:missing:step-a"
                   (.. "workflow-step:" seeded.definition.id ":missing-step")
                   "workflow-run:missing"
                    "workflow-run-step:missing:step-a"
                    (.. "workflow-run-step:" seeded.run.id ":missing-step")
                    "workflow-run-event:missing:event-a"
                     (.. "workflow-run-event:" seeded.run.id ":missing-event")
                     "workflow-run-timeline:missing"
                    "agent-session:missing"
                    (.. "agent-session:" seeded.run.id)])
  (each [_ key (ipairs keys)]
    (local (ok result) (pcall missing-key-result graph key))
    (assert ok (.. "missing workflow key should not throw: " key))
    (assert (= result nil) (.. "missing workflow key should return nil: " key))))

(fn workflow-key-loaders-return-nil-for-missing-records []
  (with-runtime workflow-key-loaders-return-nil-for-missing-records-case))

(fn workflow-definition-explicit-actions-materialize-selected-run-and-step-code-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "explicit-definition-actions-map"}))
  (local node (map:load-by-key (.. "workflow-definition:" seeded.definition.id)))
  (local run-node (node:load-run-from-graph seeded.run))
  (assert (= run-node.key (.. "workflow-run:" seeded.run.id)) "definition run action should load selected run")
  (assert-edge-target map.edges run-node.key "definition run action should add a visible run edge")
  (local step-node (map:load-by-key (.. "workflow-step:" seeded.definition.id ":step-a")))
  (local code-node (step-node:show-code-from-graph))
  (assert (= code-node.key "code-entity:code-a") "step code action should load linked code entity")
  (assert-edge-target map.edges code-node.key "step code action should add a visible code edge")
  (map:drop))

(fn workflow-definition-explicit-actions-materialize-selected-run-and-step-code []
  (with-runtime workflow-definition-explicit-actions-materialize-selected-run-and-step-code-case))

(fn workflow-run-node-exposes-granular-inspection-actions-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "run-actions-map"}))
  (local node (map:load-by-key (.. "workflow-run:" seeded.run.id)))
  (local actions (node:actions))
  (assert (action-named? actions "Show Run Steps") "run node should expose Show Run Steps")
  (assert (action-named? actions "Reveal Failed Steps") "run node should expose Reveal Failed Steps")
  (assert (action-named? actions "Open Timeline") "run node should expose Open Timeline")
  (assert (not (action-named? actions "Show Details")) "run node should not expose Show Details")
  (assert (not (action-named? actions "Hide Details")) "run node should not expose Hide Details")
  (assert node.load-run-steps-from-graph "run node should expose granular run step loading")
  (assert node.reveal-failed-run-steps-from-graph "run node should expose failed-step reveal")
  (assert node.open-timeline-from-graph "run node should expose timeline opening")
  (assert (not node.load-details-from-graph) "run node should not preserve generic detail loader")
  (map:drop))

(fn workflow-run-node-exposes-granular-inspection-actions [] (with-runtime workflow-run-node-exposes-granular-inspection-actions-case))

(fn workflow-run-show-run-steps-materializes-all-run-steps-only-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "run-steps-map"}))
  (local node (map:load-by-key (.. "workflow-run:" seeded.run.id)))
  (local result (node:load-run-steps-from-graph))
  (assert (= result.run-step-count 2) "Show Run Steps should report all run steps")
  (assert (= result.event-count nil) "Show Run Steps should not report or load events")
  (assert (map:lookup (.. "workflow-run-step:" seeded.run.id ":step-a")) "Show Run Steps should make first run-step visible")
  (assert (map:lookup (.. "workflow-run-step:" seeded.run.id ":step-b")) "Show Run Steps should make second run-step visible")
  (assert (not (map:lookup (.. "workflow-run-event:" seeded.run.id ":" seeded.event.id))) "Show Run Steps should not materialize event nodes")
  (assert (not (map:lookup (.. "workflow-run-timeline:" seeded.run.id))) "Show Run Steps should not materialize timeline node")
  (assert-edge-target map.edges (.. "workflow-run-step:" seeded.run.id ":step-a")
                      "Show Run Steps should add run-to-step edge")
  (map:drop))

(fn workflow-run-show-run-steps-materializes-all-run-steps-only [] (with-runtime workflow-run-show-run-steps-materializes-all-run-steps-only-case))

(fn workflow-run-reveal-failed-steps-materializes-failed-subset-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "failed-run-steps-map"}))
  (local node (map:load-by-key (.. "workflow-run:" seeded.run.id)))
  (local result (node:reveal-failed-run-steps-from-graph))
  (assert (= result.run-step-count 1) "Reveal Failed Steps should report only failed run steps")
  (assert (not (map:lookup (.. "workflow-run-step:" seeded.run.id ":step-a"))) "Reveal Failed Steps should not load succeeded run steps")
  (assert (map:lookup (.. "workflow-run-step:" seeded.run.id ":step-b")) "Reveal Failed Steps should load failed run steps")
  (assert (not (map:lookup (.. "workflow-run-event:" seeded.run.id ":" seeded.event.id))) "Reveal Failed Steps should not materialize event nodes")
  (map:drop))

(fn workflow-run-reveal-failed-steps-materializes-failed-subset [] (with-runtime workflow-run-reveal-failed-steps-materializes-failed-subset-case))

(fn workflow-run-open-timeline-materializes-timeline-node-only-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "run-timeline-map"}))
  (local node (map:load-by-key (.. "workflow-run:" seeded.run.id)))
  (local timeline (node:open-timeline-from-graph))
  (local timeline-key (.. "workflow-run-timeline:" seeded.run.id))
  (assert (= timeline.key timeline-key) "Open Timeline should load the workflow-run-timeline node")
  (assert (map:lookup timeline-key) "Open Timeline should materialize the timeline node")
  (assert (not (map:lookup (.. "workflow-run-event:" seeded.run.id ":" seeded.event.id))) "Open Timeline should not materialize event nodes")
  (assert-edge-target map.edges timeline-key "Open Timeline should add run-to-timeline edge")
  (map:drop))

(fn workflow-run-open-timeline-materializes-timeline-node-only [] (with-runtime workflow-run-open-timeline-materializes-timeline-node-only-case))

(fn workflow-status-color-mapping-covers-all-statuses []
  (local WorkflowRunNode (require :graph/nodes/workflow-run))
  (local statuses [:pending :queued :ready :running :waiting :failed :succeeded :skipped :cancelled])
  (each [_ status (ipairs statuses)]
    (local color (WorkflowRunNode.status-color status))
    (assert color (.. "status color should exist for " (tostring status)))
    (assert (= (type color) :userdata) (.. "status color should be vec4 for " (tostring status)))))

(fn definition-new-step-creates-template-backed-step-and-loads-nodes-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local definition seeded.definition)
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "new-step-map"}))
  (local node (map:load-by-key (.. "workflow-definition:" definition.id)))
  (assert node "workflow definition should load through graph map")
  (assert (action-named node.actions "New Step") "workflow definition should expose New Step action")
  (assert node.create-step-from-graph "workflow definition should expose create-step-from-graph")
  (local result (node:create-step-from-graph {:step-name "Added Step"}))
  (assert result.step "New Step should create a workflow step")
  (assert result.code-entity "New Step should create a code entity")
  (local reloaded (runtime.store:get-definition definition.id))
  (local created-step (. reloaded.steps (length reloaded.steps)))
  (assert (= created-step.id result.step.id) "created step should be durable in workflow definition")
  (assert (= created-step.name "Added Step") "created step should use requested step name")
  (assert (= created-step.code-entity-id result.code-entity.id)
          "created step should reference created code entity")
  (assert (= created-step.source nil) "created step should not embed source")
  (assert (runtime.code-store:get-entity result.code-entity.id) "created code entity should be durable")
  (local step-key (.. "workflow-step:" definition.id ":" result.step.id))
  (local code-key (.. "code-entity:" result.code-entity.id))
  (assert (map:lookup step-key) "New Step should load step node into graph map")
  (assert (map:lookup code-key) "New Step should load code node into graph map")
  (assert-edge-target map.edges step-key "New Step should add definition-to-step edge")
  (assert-edge-target map.edges code-key "New Step should add step-to-code edge")
  (map:drop))

(fn definition-new-step-creates-template-backed-step-and-loads-nodes []
  (with-runtime definition-new-step-creates-template-backed-step-and-loads-nodes-case))

(fn definition-new-step-without-graph-does-not-persist-step-or-code-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local definition seeded.definition)
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "new-step-missing-graph-map"}))
  (local node (map:load-by-key (.. "workflow-definition:" definition.id)))
  (set node.graph nil)
  (local before-steps (length (. (runtime.store:get-definition definition.id) :steps)))
  (local before-code (length (runtime.code-store:list-entities)))
  (local (ok err) (pcall node.create-step-from-graph node {:step-name "Should Not Persist"}))
  (assert (not ok) "New Step without a graph should fail loudly")
  (assert (string.find (tostring err) "requires a graph map" 1 true)
          "New Step missing graph failure should explain the missing graph map")
  (assert (= (length (. (runtime.store:get-definition definition.id) :steps)) before-steps)
          "failed New Step without graph should not persist a workflow step")
  (assert (= (length (runtime.code-store:list-entities)) before-code)
          "failed New Step without graph should not persist a code entity")
  (map:drop))

(fn definition-new-step-without-graph-does-not-persist-step-or-code []
  (with-runtime definition-new-step-without-graph-does-not-persist-step-or-code-case))

(fn definition-new-step-rolls-back-when-graph-load-fails-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local definition seeded.definition)
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "new-step-load-failure-map"}))
  (local node (map:load-by-key (.. "workflow-definition:" definition.id)))
  (local original-load-by-key map.load-by-key)
  (set map.load-by-key (fn [self key]
                         (if (= (string.sub key 1 14) "workflow-step:")
                             nil
                             (original-load-by-key self key))))
  (local before-steps (length (. (runtime.store:get-definition definition.id) :steps)))
  (local before-code (length (runtime.code-store:list-entities)))
  (local (ok err) (pcall node.create-step-from-graph node {:step-name "Should Roll Back"}))
  (assert (not ok) "New Step should fail loudly when graph loading fails")
  (assert (string.find (tostring err) "failed to load graph node" 1 true)
          "graph load failure should be surfaced")
  (assert (= (length (. (runtime.store:get-definition definition.id) :steps)) before-steps)
          "graph load failure should roll back the workflow step")
  (assert (= (length (runtime.code-store:list-entities)) before-code)
          "graph load failure should roll back the code entity")
  (map:drop))

(fn definition-new-step-rolls-back-when-graph-load-fails []
  (with-runtime definition-new-step-rolls-back-when-graph-load-fails-case))

(fn workflow-step-show-code-loads-linked-code-node-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local definition seeded.definition)
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "show-code-map"}))
  (local step-node (map:load-by-key (.. "workflow-step:" definition.id ":step-a")))
  (assert step-node "workflow step should load through graph map")
  (assert (action-named step-node.actions "Show Code") "workflow step should expose Show Code action")
  (assert step-node.show-code-from-graph "workflow step should expose show-code-from-graph")
  (local code-node (step-node:show-code-from-graph))
  (assert code-node "Show Code should return the loaded code node")
  (assert (= code-node.key "code-entity:code-a") "Show Code should load linked code entity node")
  (assert (map:lookup "code-entity:code-a") "Show Code should make code node visible in graph map")
  (assert-edge-target map.edges "code-entity:code-a" "Show Code should add a visible step-to-code edge")
  (map:drop))

(fn workflow-step-show-code-loads-linked-code-node []
  (with-runtime workflow-step-show-code-loads-linked-code-node-case))

(fn workflow-step-preview-builds-with-show-code-action-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local definition seeded.definition)
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "step-preview-map"}))
  (local node (map:load-by-key (.. "workflow-step:" definition.id ":step-a")))
  (local (loaded? Preview) (pcall require :graph/view/previews/workflow-step))
  (assert loaded? "workflow step preview module should load")
  (assert-missing-build-context-with-fallbacks
    Preview node
    "workflow step preview should not fall back to opts.ctx or graph.ctx")
  (local builder (Preview node {:node node}))
  (assert-missing-build-context builder "workflow step preview should assert on missing build context")
  (local widget (builder (make-preview-ctx)))
  (assert widget "workflow step preview should build a widget")
  (assert widget.show-code-button "workflow step preview should expose a Show Code button")
  (widget.show-code-button:on-click {:source :test})
  (assert (map:lookup "code-entity:code-a") "Show Code preview button should load linked code node")
  (widget:drop)
  (map:drop))

(fn workflow-step-preview-builds-with-show-code-action []
  (with-runtime workflow-step-preview-builds-with-show-code-action-case))

(fn workflow-run-timeline-preview-search-materializes-one-event-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (runtime.store:append-event seeded.run.id {:id "event-finished" :kind :step-finished :step-id "step-b"})
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "run-timeline-preview-map"}))
  (local timeline (map:load-by-key (.. "workflow-run-timeline:" seeded.run.id)))
  (local (loaded? Preview) (pcall require :graph/view/previews/workflow-run-timeline))
  (assert loaded? "workflow run timeline preview module should load")
  (assert-missing-build-context-with-fallbacks
    Preview timeline
    "run timeline preview should not fall back to opts.ctx or graph.ctx")
  (local builder (Preview timeline {:node timeline}))
  (assert-missing-build-context builder "run timeline preview should assert on missing build context")
  (local widget (builder (make-preview-ctx)))
  (assert widget.event-search "timeline preview should expose event search")
  (assert widget.event-count-text "timeline preview should expose event count text")
  (assert-contains (text-widget-string widget.event-count-text) "Events: 2" "timeline preview should count events")
  (widget.event-search.submitted:emit (. (timeline:event-items) 1))
  (assert (map:lookup (.. "workflow-run-event:" seeded.run.id ":" seeded.event.id)) "timeline event search should load selected event")
  (assert (not (map:lookup (.. "workflow-run-event:" seeded.run.id ":event-finished"))) "timeline event search should not load unselected events")
  (assert-edge-target map.edges (.. "workflow-run-event:" seeded.run.id ":" seeded.event.id)
                      "timeline event search should add timeline-to-event edge")
  (widget:drop)
  (map:drop))

(fn workflow-run-timeline-preview-search-materializes-one-event [] (with-runtime workflow-run-timeline-preview-search-materializes-one-event-case))

(fn workflow-run-timeline-preview-drops-owned-children-and-search-listener-case [runtime] (local seeded (seed-definition-with-run runtime)) (runtime.store:append-event seeded.run.id {:id "event-finished" :kind :step-finished :step-id "step-b"}) (local map (GraphMap.GraphMap {:graph runtime.graph :id "run-timeline-drop-map"})) (local timeline (map:load-by-key (.. "workflow-run-timeline:" seeded.run.id))) (local Preview (require :graph/view/previews/workflow-run-timeline)) (assert-missing-build-context-with-fallbacks Preview timeline "run timeline preview should not fall back to opts.ctx or graph.ctx") (local builder (Preview timeline {:node timeline})) (assert-missing-build-context builder "run timeline preview should assert on missing build context") (local widget (builder (make-preview-ctx))) (local dropped {:title 0 :event-count 0 :event-search 0 :flex 0}) (each [_ pair (ipairs [[:title :title] [:event-count-text :event-count] [:event-search :event-search] [:flex :flex]])] (wrap-preview-drop-counter widget dropped (. pair 1) (. pair 2))) (widget:drop) (assert (= widget.__event-search-listener nil) "run timeline drop should clear event search listener handle") (assert-drop-counts dropped "workflow run timeline preview drop") (widget.event-search.submitted:emit (. (timeline:event-items) 1)) (assert (not (map:lookup (.. "workflow-run-event:" seeded.run.id ":" seeded.event.id))) "dropped timeline event search listener should not load an event") (map:drop))
(fn workflow-run-timeline-preview-drops-owned-children-and-search-listener [] (with-runtime workflow-run-timeline-preview-drops-owned-children-and-search-listener-case))

(fn workflow-run-preview-exposes-granular-buttons-without-details-toggle-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "run-preview-actions-map"}))
  (local node (map:load-by-key (.. "workflow-run:" seeded.run.id)))
  (local (loaded? Preview) (pcall require :graph/view/previews/workflow-run))
  (assert loaded? "workflow run preview module should load")
  (assert-missing-build-context-with-fallbacks
    Preview node
    "run preview should not fall back to opts.ctx or graph.ctx")
  (local builder (Preview node {:node node}))
  (assert-missing-build-context builder "run preview should assert on missing build context")
  (local widget (builder (make-preview-ctx)))
  (assert widget.show-run-steps-button "run preview should expose Show Run Steps button")
  (assert widget.reveal-failed-steps-button "run preview should expose Reveal Failed Steps button")
  (assert widget.open-timeline-button "run preview should expose Open Timeline button")
  (assert (not widget.show-details-button) "run preview should not expose generic Show Details button")
  (assert (= (map:lookup (.. "workflow-run-step:" seeded.run.id ":step-a")) nil) "run-step should not be visible before granular action")
  (widget.show-run-steps-button:on-click {:source :test})
  (assert (map:lookup (.. "workflow-run-step:" seeded.run.id ":step-a")) "Show Run Steps preview button should load run-step node")
  (widget.open-timeline-button:on-click {:source :test})
  (assert (map:lookup (.. "workflow-run-timeline:" seeded.run.id)) "Open Timeline preview button should load timeline node")
  (assert (not (map:lookup (.. "workflow-run-event:" seeded.run.id ":" seeded.event.id))) "run preview granular buttons should not load events directly")
  (widget:drop)
  (map:drop))

(fn workflow-run-preview-exposes-granular-buttons-without-details-toggle [] (with-runtime workflow-run-preview-exposes-granular-buttons-without-details-toggle-case))

(fn workflow-run-preview-drops-owned-children-case [runtime] (local seeded (seed-definition-with-run runtime)) (local map (GraphMap.GraphMap {:graph runtime.graph :id "run-preview-drop-map"})) (local node (map:load-by-key (.. "workflow-run:" seeded.run.id))) (local Preview (require :graph/view/previews/workflow-run)) (assert-missing-build-context-with-fallbacks Preview node "run preview should not fall back to opts.ctx or graph.ctx") (local builder (Preview node {:node node})) (assert-missing-build-context builder "run preview should assert on missing build context") (local widget (builder (make-preview-ctx))) (assert-widget-drop-counters widget [[:title :title] [:status-text :status] [:show-run-steps-button :show-run-steps] [:reveal-failed-steps-button :reveal-failed] [:open-timeline-button :timeline] [:flex :flex]] "workflow run preview drop") (map:drop))
(fn workflow-run-preview-drops-owned-children [] (with-runtime workflow-run-preview-drops-owned-children-case))

(fn workflow-run-node-omits-cancel-action-for-succeeded-run-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (runtime.store:update-run seeded.run.id {:status :succeeded :finished-at (os.time)})
  (local node (runtime.graph:load-by-key (.. "workflow-run:" seeded.run.id)))
  (assert node "workflow run node should load")
  (assert (action-named? (node:actions) "Show Run Steps") "terminal run should still expose run-step inspection")
  (assert (not (action-named? (node:actions) "Show Details")) "terminal run should not expose generic detail toggle")
  (assert (not (action-named? (node:actions) "Cancel Run")) "terminal run should omit cancel action"))

(fn workflow-run-node-omits-cancel-action-for-succeeded-run [] (with-runtime workflow-run-node-omits-cancel-action-for-succeeded-run-case))

(fn workflow-run-step-status-colors-cover-all-run-step-statuses []
  (local WorkflowRunStepNode (require :graph/nodes/workflow-run-step))
  (local statuses [:pending :queued :ready :running :waiting :failed :succeeded :skipped :cancelled])
  (each [_ status (ipairs statuses)]
    (local color (WorkflowRunStepNode.status-color status))
    (assert color (.. "run step status color should exist for " (tostring status)))
    (assert (= (type color) :userdata) (.. "run step status color should be vec4 for " (tostring status)))))

(fn workflow-run-step-and-event-summaries-include-details []
  (local PreviewSummary (require :workflows/preview-summary))
  (local step-summary
    (PreviewSummary.run-step-summary {:status :failed
                                      :attempt 2
                                      :output {:answer 42}
                                      :wait {:kind :human-input}
                                      :error {:message "boom"}}))
  (assert-contains step-summary "Status:" "run-step summary should include status label")
  (assert-contains step-summary "Attempt:" "run-step summary should include attempt label")
  (assert-contains step-summary "Output:" "run-step summary should include output label")
  (assert-contains step-summary "Wait:" "run-step summary should include wait label")
  (assert-contains step-summary "Error:" "run-step summary should include error label")
  (assert-contains step-summary "42" "run-step summary should include serialized output")
  (local event-summary
    (PreviewSummary.run-event-summary {:id "event-a"
                                      :run-id "run-a"
                                      :kind :step-waiting
                                      :step-id "step-a"
                                      :created-at 123
                                      :wait-kind :human-input
                                      :payload {:question "continue?"}}))
  (assert-contains event-summary "Kind:" "run-event summary should include kind label")
  (assert-contains event-summary "Step:" "run-event summary should include step label")
  (assert-contains event-summary "Payload:" "run-event summary should include payload label")
  (assert-contains event-summary "step-a" "run-event summary should include step id")
  (assert-contains event-summary "human-input" "run-event summary should include non-metadata event fields"))
(fn workflow-run-step-preview-builds-summary-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local graph runtime.graph)
  (local node (graph:load-by-key (.. "workflow-run-step:" seeded.run.id ":step-a")))
  (assert node.preview "workflow run-step node should expose a preview")
  (local (loaded? Preview) (pcall require :graph/view/previews/workflow-run-step))
  (assert loaded? "workflow run-step preview module should load")
  (assert-missing-build-context-with-fallbacks
    Preview node
    "workflow run-step preview should not fall back to opts.ctx or graph.ctx")
  (local builder (node.preview node {:node node}))
  (assert-missing-build-context builder "workflow run-step preview should assert on missing build context")
  (local widget (builder (make-preview-ctx)))
  (assert widget.summary-text "workflow run-step preview should expose summary text")
  (local summary (text-widget-string widget.summary-text))
  (assert-contains summary "Status:" "workflow run-step preview summary should include status")
  (assert-contains summary "succeeded" "workflow run-step preview summary should include useful status text")
  (each [_ needle (ipairs ["Output:" "Wait:" "Error:" "42"])]
    (assert-not-contains summary needle "workflow run-step preview summary should omit dense payload text"))
  (assert widget.payload-hint "workflow run-step preview should expose compact payload panel hint when details exist") (assert-contains (text-widget-string widget.payload-hint) "Open node for payload panel" "workflow run-step preview should direct dense payloads to full view")
  (assert-preview-drops-owned-children widget "workflow run-step preview"))
(fn workflow-run-step-preview-builds-summary [] (with-runtime workflow-run-step-preview-builds-summary-case))
(fn workflow-run-step-node-has-payload-view-case [runtime] (local seeded (seed-definition-with-run runtime)) (local node (runtime.graph:load-by-key (.. "workflow-run-step:" seeded.run.id ":step-a"))) (assert node "workflow run-step node should load") (assert node.view "workflow run-step node should expose a full payload view") (assert node.get-run-step "workflow run-step node should expose get-run-step") (assert (= (. (node:get-run-step) :status) :succeeded) "get-run-step should return the current persisted run step"))
(fn workflow-run-step-node-has-payload-view [] (with-runtime workflow-run-step-node-has-payload-view-case))
(fn workflow-run-step-view-renders-payload-in-multiline-input-case [runtime] (local seeded (seed-definition-with-run runtime)) (runtime.store:upsert-run-step seeded.run.id "step-a" {:status :succeeded :attempt 3 :output {:answer 42 :detail "complete-output"} :wait {:kind :none} :error {:message "not-present"}}) (local node (runtime.graph:load-by-key (.. "workflow-run-step:" seeded.run.id ":step-a"))) (local View (require :graph/view/views/workflow-run-step)) (assert-missing-build-context-with-fallbacks View node "workflow run-step view should not fall back to opts.ctx or graph.ctx") (local builder (node.view node {:node node})) (assert-missing-build-context builder "workflow run-step view should require direct build context") (local widget (builder (make-preview-ctx))) (each [_ field (ipairs [:title :payload-input :scroll-view :flex])] (assert (. widget field) (.. "workflow run-step view should expose " (tostring field)))) (assert (= widget.payload-input.multiline? true) "workflow run-step payload should be multiline") (local payload-text (widget.payload-input:get-text)) (each [_ needle (ipairs ["Status:" "succeeded" "Attempt:" "3" "Output:" "complete-output" "Wait:" "none" "Error:" "not-present"])] (assert-contains payload-text needle "workflow run-step view should render complete payload fields")) (widget:drop))
(fn workflow-run-step-view-renders-payload-in-multiline-input [] (with-runtime workflow-run-step-view-renders-payload-in-multiline-input-case))

(fn workflow-run-step-view-drops-owned-children-case [runtime] (local seeded (seed-definition-with-run runtime)) (local node (runtime.graph:load-by-key (.. "workflow-run-step:" seeded.run.id ":step-a"))) (local View (require :graph/view/views/workflow-run-step)) (assert-missing-build-context-with-fallbacks View node "workflow run-step view should not fall back to opts.ctx or graph.ctx") (local builder (node.view node {:node node})) (assert-missing-build-context builder "workflow run-step view should require direct build context") (local widget (builder (make-preview-ctx))) (assert-widget-drop-counters widget [[:title :title] [:payload-input :payload-input] [:flex :flex] [:scroll-view :scroll-view]] "workflow run-step view drop"))
(fn workflow-run-step-view-drops-owned-children [] (with-runtime workflow-run-step-view-drops-owned-children-case))

(fn workflow-run-event-preview-builds-summary-case [runtime]
  (local seeded (seed-definition-with-run runtime))
  (local graph runtime.graph)
  (local node (graph:load-by-key (.. "workflow-run-event:" seeded.run.id ":" seeded.event.id)))
  (assert node.preview "workflow run-event node should expose a preview")
  (local (loaded? Preview) (pcall require :graph/view/previews/workflow-run-event))
  (assert loaded? "workflow run-event preview module should load")
  (assert-missing-build-context-with-fallbacks
    Preview node
    "workflow run-event preview should not fall back to opts.ctx or graph.ctx")
  (local builder (node.preview node {:node node}))
  (assert-missing-build-context builder "workflow run-event preview should assert on missing build context")
  (local widget (builder (make-preview-ctx)))
  (assert widget.summary-text "workflow run-event preview should expose summary text")
  (local summary (text-widget-string widget.summary-text))
  (assert-contains summary "Kind:" "workflow run-event preview summary should include kind")
  (assert-contains summary "step-started" "workflow run-event preview summary should include useful kind text")
  (assert-contains summary "Step:" "workflow run-event preview summary should include step id")
  (assert (not widget.payload-hint) "workflow run-event preview should stay compact without event payload details") (assert-preview-drops-owned-children widget "workflow run-event preview"))
(fn workflow-run-event-preview-builds-summary [] (with-runtime workflow-run-event-preview-builds-summary-case))

(fn workflow-run-event-node-has-payload-view-case [runtime] (local seeded (seed-definition-with-run runtime)) (local node (runtime.graph:load-by-key (.. "workflow-run-event:" seeded.run.id ":" seeded.event.id))) (assert node "workflow run-event node should load") (assert node.view "workflow run-event node should expose a full payload view") (assert node.get-event "workflow run-event node should expose get-event") (assert (= (. (node:get-event) :id) seeded.event.id) "get-event should return the current persisted event"))
(fn workflow-run-event-node-has-payload-view [] (with-runtime workflow-run-event-node-has-payload-view-case))
(fn workflow-run-event-view-renders-payload-in-multiline-input-case [runtime] (local seeded (seed-definition-with-run runtime)) (local event (runtime.store:append-event seeded.run.id {:id "event-payload" :kind :step-output :step-id "step-a" :created-at 456 :payload {:answer 42 :detail "event-payload-detail"} :notes "extra event notes"})) (local node (runtime.graph:load-by-key (.. "workflow-run-event:" seeded.run.id ":" event.id))) (local preview-widget ((node.preview node {:node node}) (make-preview-ctx))) (local preview-summary (text-widget-string preview-widget.summary-text)) (each [_ needle (ipairs ["Payload:" "event-payload-detail" "extra event notes" "42"])] (assert-not-contains preview-summary needle "workflow run-event preview summary should omit dense payload text")) (assert preview-widget.payload-hint "workflow run-event preview should expose payload panel hint when details exist") (assert-contains (text-widget-string preview-widget.payload-hint) "Open node for payload panel" "workflow run-event preview should direct dense payloads to full view") (preview-widget:drop) (local View (require :graph/view/views/workflow-run-event)) (assert-missing-build-context-with-fallbacks View node "workflow run-event view should not fall back to opts.ctx or graph.ctx") (local builder (node.view node {:node node})) (assert-missing-build-context builder "workflow run-event view should require direct build context") (local widget (builder (make-preview-ctx))) (each [_ field (ipairs [:title :payload-input :scroll-view :flex])] (assert (. widget field) (.. "workflow run-event view should expose " (tostring field)))) (assert (= widget.payload-input.multiline? true) "workflow run-event payload should be multiline") (local payload-text (widget.payload-input:get-text)) (each [_ needle (ipairs ["Event:" "event-payload" "Kind:" "step-output" "Step:" "step-a" "Created At:" "456" "Payload:" "event-payload-detail" "notes" "extra event notes"])] (assert-contains payload-text needle "workflow run-event view should render complete payload fields")) (widget:drop))
(fn workflow-run-event-view-renders-payload-in-multiline-input [] (with-runtime workflow-run-event-view-renders-payload-in-multiline-input-case))

(fn workflow-run-event-view-drops-owned-children-case [runtime] (local seeded (seed-definition-with-run runtime)) (local event (runtime.store:append-event seeded.run.id {:id "event-payload-drop" :kind :step-output :step-id "step-a" :payload {:answer 42}})) (local node (runtime.graph:load-by-key (.. "workflow-run-event:" seeded.run.id ":" event.id))) (local View (require :graph/view/views/workflow-run-event)) (assert-missing-build-context-with-fallbacks View node "workflow run-event view should not fall back to opts.ctx or graph.ctx") (local builder (node.view node {:node node})) (assert-missing-build-context builder "workflow run-event view should require direct build context") (local widget (builder (make-preview-ctx))) (assert-widget-drop-counters widget [[:title :title] [:payload-input :payload-input] [:flex :flex] [:scroll-view :scroll-view]] "workflow run-event view drop"))
(fn workflow-run-event-view-drops-owned-children [] (with-runtime workflow-run-event-view-drops-owned-children-case))

(fn seed-definition-for-authoring [runtime]
  (local code-a (runtime.code-store:create-entity {:id "code-a" :name "A" :source "(+ 1 1)"}))
  (local code-b (runtime.code-store:create-entity {:id "code-b" :name "B" :source "(+ 2 2)"}))
  (runtime.store:create-definition {:id "wf-author"
                                    :name "Author workflow"
                                    :steps [{:id "step-a" :name "A" :code-entity-id code-a.id}
                                            {:id "step-b" :name "B" :code-entity-id code-b.id}]
                                    :edges []}))

(fn workflow-edge-count [runtime definition-id]
  (local definition (runtime.store:get-definition definition-id))
  (local edges (if (and definition definition.edges) definition.edges []))
  (length edges))

(fn graph-step-connection-creates-canonical-workflow-control-edge-case [runtime]
  (local definition (seed-definition-for-authoring runtime))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "author-map"}))
  (local step-a (map:load-by-key (.. "workflow-step:" definition.id ":step-a")))
  (local step-b (map:load-by-key (.. "workflow-step:" definition.id ":step-b")))
  (local edge (map:add-edge (GraphEdge {:source step-a :target step-b})))
  (local current (runtime.store:get-definition definition.id))
  (assert (= (length current.edges) 1) "graph step connection should create one canonical workflow edge")
  (local workflow-edge (. current.edges 1))
  (assert (= workflow-edge.kind :control) "authored workflow edge should default to control")
  (assert (= workflow-edge.source-step-id "step-a") "authored workflow edge should use source step")
  (assert (= workflow-edge.target-step-id "step-b") "authored workflow edge should use target step")
  (assert (and edge edge._opts edge._opts.from-workflow-edge) "display edge should reference canonical workflow edge")
  (map:drop))

(fn graph-step-connection-creates-canonical-workflow-control-edge []
  (with-runtime graph-step-connection-creates-canonical-workflow-control-edge-case))

(fn graph-map-capture-skips-workflow-derived-edges-case [runtime]
  (local definition (seed-definition-for-authoring runtime))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "capture-map"}))
  (local step-a (map:load-by-key (.. "workflow-step:" definition.id ":step-a")))
  (local step-b (map:load-by-key (.. "workflow-step:" definition.id ":step-b")))
  (map:add-edge (GraphEdge {:source step-a :target step-b}))
  (local state (map:capture-state))
  (assert (= (length state.edges) 0) "workflow-derived graph edges should not be captured as map topology")
  (map:drop))

(fn graph-map-capture-skips-workflow-derived-edges []
  (with-runtime graph-map-capture-skips-workflow-derived-edges-case))

(fn graph-remove-edge-deletes-canonical-workflow-edge-case [runtime]
  (local definition (seed-definition-for-authoring runtime))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "remove-map"}))
  (local step-a (map:load-by-key (.. "workflow-step:" definition.id ":step-a")))
  (local step-b (map:load-by-key (.. "workflow-step:" definition.id ":step-b")))
  (local edge (map:add-edge (GraphEdge {:source step-a :target step-b})))
  (assert (= (workflow-edge-count runtime definition.id) 1) "workflow edge should exist before graph removal")
  (local removed (map:remove-edge edge))
  (assert removed "GraphMap.remove-edge should return removed edge")
  (assert (= (map:edge-count) 0) "displayed workflow edge should be removed from graph map")
  (assert (= (workflow-edge-count runtime definition.id) 0) "removing displayed workflow edge should delete canonical edge")
  (map:drop))

(fn graph-remove-edge-deletes-canonical-workflow-edge []
  (with-runtime graph-remove-edge-deletes-canonical-workflow-edge-case))

(fn graph-remove-derived-workflow-edge-with-caller-opts-clears-domain-and-indexes-case [runtime]
  (local definition (seed-definition-for-authoring runtime))
  (local map (GraphMap.GraphMap {:graph runtime.graph :id "remove-derived-map"}))
  (local step-a (map:load-by-key (.. "workflow-step:" definition.id ":step-a")))
  (local step-b (map:load-by-key (.. "workflow-step:" definition.id ":step-b")))
  (local edge (map:add-edge (GraphEdge {:source step-a :target step-b})))
  (local workflow-edge-id edge._opts.from-workflow-edge)
  (local derived-key (.. step-a.key "->" step-b.key "#link:" workflow-edge-id))
  (assert (. map.edge-map derived-key) "workflow-derived edge should be indexed by derived workflow key before removal")
  (local removed (map:remove-edge edge {:cause "user"}))
  (assert (= removed edge) "GraphMap.remove-edge should return the displayed workflow edge")
  (assert (= (workflow-edge-count runtime definition.id) 0)
          "removing with caller opts should delete canonical workflow edge using edge identity metadata")
  (assert (= (. map.edge-map derived-key) nil)
          "removing with caller opts should clear the derived workflow edge-map entry")
  (assert (= (map:edge-count) 0) "removing with caller opts should remove displayed workflow edge")
  (map:drop))

(fn graph-remove-derived-workflow-edge-with-caller-opts-clears-domain-and-indexes []
  (with-runtime graph-remove-derived-workflow-edge-with-caller-opts-clears-domain-and-indexes-case))

(fn start-definition-node-creates-visible-run-node-and-definition-run-edge-case [runtime]
  (local definition (seed-definition-for-authoring runtime)) (local map (GraphMap.GraphMap {:graph runtime.graph :id "start-map"})) (local node (map:load-by-key (.. "workflow-definition:" definition.id))) (local run (node:start-workflow-from-graph {:prompt "go"} {}))
  (assert run "starting workflow from graph should return run") (assert (runtime.store:get-run run.id) "run should be durable immediately") (assert (map:lookup (.. "workflow-run:" run.id)) "run node should be visible in active graph map")
  (assert-edge-target map.edges (.. "workflow-run:" run.id) "definition-to-run edge should be inserted in graph map") (map:drop))

(fn start-definition-node-creates-visible-run-node-and-definition-run-edge []
  (with-runtime start-definition-node-creates-visible-run-node-and-definition-run-edge-case))

(fn assert-start-preflight-fails-without-persisting [runtime node graph-value expected-message]
  (set node.graph graph-value) (local before-started (length runtime.runner.started)) (local before-runs (length (runtime.store:list-runs {:definition-id node.workflow-definition-id}))) (local (ok err) (pcall node.start-workflow-from-graph node {:prompt "go"} {}))
  (assert (not ok) "Start should fail loudly when graph dependencies are missing") (assert (string.find (tostring err) expected-message 1 true) "Start missing dependency failure should explain the missing graph dependency")
  (assert (= (length runtime.runner.started) before-started) "Start missing dependency failure should not call the runner") (assert (= (length (runtime.store:list-runs {:definition-id node.workflow-definition-id})) before-runs) "Start missing dependency failure should not persist a workflow run"))

(fn start-definition-node-requires-graph-dependencies-before-persisting-case [runtime]
  (local definition (seed-definition-for-authoring runtime)) (local map (GraphMap.GraphMap {:graph runtime.graph :id "start-preflight-map"})) (local node (map:load-by-key (.. "workflow-definition:" definition.id))) (assert-start-preflight-fails-without-persisting runtime node nil "requires a graph map") (assert-start-preflight-fails-without-persisting runtime node {:add-edge (fn [])} "requires a graph map") (assert-start-preflight-fails-without-persisting runtime node {:load-by-key (fn [])} "requires a graph map") (map:drop))

(fn start-definition-node-requires-workflow-run-loader-before-persisting-case [runtime] (local Graph (require :graph/init))
  (local graph (Graph {:with-start false})) (local builtins (BuiltinGraphTestHelpers.install-builtins! graph {:workflow-store runtime.store :workflow-runner runtime.runner :code-store runtime.code-store :only-schemes [:workflow-definition]}))
  (local definition (seed-definition-for-authoring runtime)) (local map (GraphMap.GraphMap {:graph graph :id "start-missing-run-loader-map"})) (local node (map:load-by-key (.. "workflow-definition:" definition.id)))
  (local before-started (length runtime.runner.started)) (local before-runs (length (runtime.store:list-runs {:definition-id definition.id}))) (local (ok err) (pcall node.start-workflow-from-graph node {:prompt "go"} {}))
  (assert (not ok) "Start should fail loudly without a workflow-run key loader") (assert (string.find (tostring err) "requires graph loader for workflow-run" 1 true) "Start missing loader failure should explain the workflow-run loader requirement") (assert (= (length runtime.runner.started) before-started) "Start without workflow-run loader should not call the runner") (assert (= (length (runtime.store:list-runs {:definition-id definition.id})) before-runs) "Start without workflow-run loader should not persist a workflow run") (map:drop) (builtins:drop) (graph:drop))

(fn start-context-captures-graph-map-and-selected-node-keys-case [runtime]
  (local definition (seed-definition-for-authoring runtime)) (local map (GraphMap.GraphMap {:graph runtime.graph :id "context-map"})) (local node (map:load-by-key (.. "workflow-definition:" definition.id))) (map:load-by-key (.. "workflow-step:" definition.id ":step-a"))
  (set map.selected_node_keys [node.key (.. "workflow-step:" definition.id ":step-a")]) (node:start-workflow-from-graph {:prompt "go"} {}) (local started (. runtime.runner.started 1))
  (assert (= started.context.graph-map-id "context-map") "run context should include active graph map id") (assert (= (. started.context.graph-node-keys 1) node.key) "run context should include first selected node key")
  (assert (= (. started.context.graph-node-keys 2) (.. "workflow-step:" definition.id ":step-a")) "run context should include selected workflow step key") (map:drop))

(fn start-context-captures-graph-map-and-selected-node-keys []
  (with-runtime start-context-captures-graph-map-and-selected-node-keys-case))

(fn workflow-step-source [value]
  (.. "{:run (fn [_self _context _input _state] {:status :succeeded :output {:value " value "}})}"))

(fn graph-code-entity-edits-feed-cached-workflow-executor-case [dir]
  (local {:WorkflowStore WorkflowStore} (require :workflows/store))
  (local {:WorkflowCodeExecutor WorkflowCodeExecutor} (require :workflows/code-executor))
  (local {:WorkflowRunner WorkflowRunner} (require :workflows/runner))
  (local CodeEntityStore (require :entities/code))
  (local Graph (require :graph/init))
  (local previous-code-store (and app app.code-store))
  (local workflow-store (WorkflowStore {:base-dir (fs.join-path dir "workflow-shared-code")}))
  (local code-store (CodeEntityStore.CodeEntityStore {:base-dir (fs.join-path dir "code-shared")}))
  (set app.code-store code-store)
  (local executor (WorkflowCodeExecutor {:code-store app.code-store :app app}))
  (local runner (WorkflowRunner {:store workflow-store :executor executor :app app}))
  (local graph (Graph {:with-start false}))
  (local builtins (BuiltinGraphTestHelpers.install-builtins! graph {:code-store code-store
                                                                    :workflow-store workflow-store
                                                                    :workflow-runner runner}))
  (local code (code-store:create-entity {:id "step-code" :name "Step" :source (workflow-step-source 1)}))
  (local definition (workflow-store:create-definition {:id "wf-shared-code"
                                                       :name "Shared code"
                                                       :steps [{:id "step" :code-entity-id code.id}]
                                                       :edges []}))
  (local first-run (runner:start-run definition.id {} {}))
  (runner:tick-run first-run.id {})
  (assert (= (. (workflow-store:get-run first-run.id) :output :step :value) 1)
          "first workflow run should use initial source")
  (local code-node (graph:create-node-by-key "code-entity:step-code"))
  (assert code-node "graph should resolve the app-scoped code entity")
  (code-node:update-source (workflow-step-source 2))
  (local second-run (runner:start-run definition.id {} {}))
  (runner:tick-run second-run.id {})
  (assert (= (. (workflow-store:get-run second-run.id) :output :step :value) 2)
          "workflow execution should observe graph-authored code edits after executor cached the entity")
  (builtins:drop)
  (graph:drop)
  (set app.code-store previous-code-store))

(fn graph-code-entity-edits-feed-cached-workflow-executor []
  (with-temp-dir graph-code-entity-edits-feed-cached-workflow-executor-case))

(fn template-helper-creates-durable-workflow-step-and-code-case [dir]
  (local {:WorkflowStore WorkflowStore} (require :workflows/store))
  (local {:WorkflowCodeExecutor WorkflowCodeExecutor} (require :workflows/code-executor))
  (local {:WorkflowRunner WorkflowRunner} (require :workflows/runner))
  (local CodeEntityStore (require :entities/code))
  (local workflow-store (WorkflowStore {:base-dir (fs.join-path dir "workflow-template")}))
  (local code-store (CodeEntityStore.CodeEntityStore {:base-dir (fs.join-path dir "code-template")}))
  (local result (Templates.create-template-workflow workflow-store code-store {:name "Created from graph"}))
  (assert result.definition "template helper should return a workflow definition")
  (assert result.step "template helper should return a workflow step")
  (assert result.code-entity "template helper should return a code entity")
  (assert (workflow-store:get-definition result.definition.id) "created workflow definition should be durable")
  (local reloaded-definition (workflow-store:get-definition result.definition.id))
  (assert (= (length reloaded-definition.steps) 1) "created workflow should have one starter step")
  (local reloaded-step (. reloaded-definition.steps 1))
  (assert (= reloaded-step.code-entity-id result.code-entity.id)
          "starter step should reference the created code entity")
  (assert (= reloaded-step.source nil) "starter step should not embed source")
  (local reloaded-code (code-store:get-entity result.code-entity.id))
  (assert reloaded-code "created code entity should be durable")
  (assert (= reloaded-code.language "fnl") "template code entity should be Fennel")
  (assert (string.find reloaded-code.source "workflow step completed")
          "template source should include completion message")
  (local executor (WorkflowCodeExecutor {:code-store code-store :app app}))
  (local runner (WorkflowRunner {:store workflow-store :executor executor :app app}))
  (local run (runner:start-run result.definition.id {:echo "input"} {:source :test}))
  (local finished (runner:tick-run run.id {:max-steps 5}))
  (assert (= finished.status :succeeded) "template workflow should run successfully")
  (local output (. finished.output result.step.id))
  (assert output "template run should include starter step output")
  (assert (= output.message "workflow step completed") "template output should include completion message")
  (assert (= output.input.echo "input") "template output should echo workflow input"))

(fn template-helper-creates-durable-workflow-step-and-code []
  (with-temp-dir template-helper-creates-durable-workflow-step-and-code-case))

(fn template-helper-keeps-code-entity-when-add-step-fails-after-commit-case [dir]
  (local {:WorkflowStore WorkflowStore} (require :workflows/store))
  (local CodeEntityStore (require :entities/code))
  (local workflow-store (WorkflowStore {:base-dir (fs.join-path dir "workflow-template-post-commit-fail")}))
  (local code-store (CodeEntityStore.CodeEntityStore {:base-dir (fs.join-path dir "code-template-post-commit-fail")}))
  (local definition (workflow-store:create-definition {:name "Post commit failure" :steps [] :edges []}))
  (local failing-handler
    (workflow-store.definition-updated:connect
      (fn [_definition]
        (error "simulated definition-updated failure"))))
  (local (ok err) (pcall Templates.create-template-step workflow-store code-store definition.id {:name "After commit"}))
  (workflow-store.definition-updated:disconnect failing-handler true)
  (assert (not ok) "simulated post-commit add-step failure should be surfaced")
  (assert (string.find (tostring err) "simulated definition-updated failure" 1 true)
          "create-template-step should rethrow the add-step failure")
  (local reloaded-definition (workflow-store:get-definition definition.id))
  (assert (= (length reloaded-definition.steps) 1)
          "test setup should leave the add-step mutation committed before the signal failure")
  (local committed-step (. reloaded-definition.steps 1))
  (assert committed-step.code-entity-id "committed step should reference template code")
  (assert (code-store:get-entity committed-step.code-entity-id)
          "committed workflow step must not point at a deleted template code entity"))

(fn template-helper-keeps-code-entity-when-add-step-fails-after-commit []
  (with-temp-dir template-helper-keeps-code-entity-when-add-step-fails-after-commit-case))

(fn template-helper-rolls-back-workflow-and-code-when-starter-step-fails-after-commit-case [dir]
  (local {:WorkflowStore WorkflowStore} (require :workflows/store))
  (local CodeEntityStore (require :entities/code))
  (local workflow-store (WorkflowStore {:base-dir (fs.join-path dir "workflow-template-workflow-rollback")}))
  (local code-store (CodeEntityStore.CodeEntityStore {:base-dir (fs.join-path dir "code-template-workflow-rollback")}))
  (local failing-handler
    (workflow-store.definition-updated:connect
      (fn [_definition]
        (error "simulated definition-updated failure"))))
  (local (ok err) (pcall Templates.create-template-workflow workflow-store code-store {:name "Rollback workflow"}))
  (workflow-store.definition-updated:disconnect failing-handler true)
  (assert (not ok) "simulated post-commit starter-step failure should be surfaced")
  (assert (string.find (tostring err) "simulated definition-updated failure" 1 true)
          "create-template-workflow should rethrow the starter-step failure")
  (assert (= (length (workflow-store:list-definitions)) 0)
          "failed template workflow creation should delete the new definition")
  (assert (= (length (code-store:list-entities)) 0)
          "failed template workflow creation should delete the starter step code entity"))

(fn template-helper-rolls-back-workflow-and-code-when-starter-step-fails-after-commit []
  (with-temp-dir template-helper-rolls-back-workflow-and-code-when-starter-step-fails-after-commit-case))

(table.insert tests {:name "graph-discovery-has-no-relationship-hook-leftovers" :fn graph-discovery-has-no-relationship-hook-leftovers})
(table.insert tests {:name "workflow key loaders resolve all workflow keys" :fn workflow-key-loaders-resolve-all-workflow-keys})
(table.insert tests {:name "workflow key loaders return nil for missing records" :fn workflow-key-loaders-return-nil-for-missing-records})
(table.insert tests {:name "agent-session-key-loads-workflow-backed-session" :fn agent-session-key-loads-workflow-backed-session})
(table.insert tests {:name "agent-session-node-loads-backing-workflow-run" :fn agent-session-node-loads-backing-workflow-run})
(table.insert tests {:name "agent-session-node-loads-only-recent-workflow-events" :fn agent-session-node-loads-only-recent-workflow-events})
(table.insert tests {:name "agent-session-preview-requires-direct-context" :fn agent-session-preview-requires-direct-context})
(table.insert tests {:name "agent-session-preview-shows-status-and-item-count" :fn agent-session-preview-shows-status-and-item-count})
(table.insert tests {:name "start-node-includes-workflows-when-workflow-store-exists" :fn start-node-includes-workflows-when-workflow-store-exists})
(table.insert tests {:name "workflows-root-new-workflow-creates-and-loads-graph-nodes" :fn workflows-root-new-workflow-creates-and-loads-graph-nodes})
(table.insert tests {:name "workflows-root-new-workflow-without-graph-does-not-persist-workflow-or-code" :fn workflows-root-new-workflow-without-graph-does-not-persist-workflow-or-code})
(table.insert tests {:name "workflows-preview-builds-with-new-workflow-action" :fn workflows-preview-builds-with-new-workflow-action})
(table.insert tests {:name "workflows-preview-blank-name-keeps-default-workflow-name" :fn workflows-preview-blank-name-keeps-default-workflow-name})
(table.insert tests {:name "workflows-preview-search-selects-one-definition-only" :fn workflows-preview-search-selects-one-definition-only})
(table.insert tests {:name "workflows-root-does-not-load-runs-directly" :fn workflows-root-does-not-load-runs-directly})
(each [_ test (ipairs ((require :tests/workflow-graph-rename-cases) {:with-runtime with-runtime :make-preview-ctx make-preview-ctx :assert-missing-build-context assert-missing-build-context :assert-missing-build-context-with-fallbacks assert-missing-build-context-with-fallbacks :GraphMap GraphMap :seed-definition-with-run seed-definition-with-run}))] (table.insert tests test))
(table.insert tests {:name "workflow-definition-preview-builds-structured-inspector" :fn workflow-definition-preview-builds-structured-inspector})
(table.insert tests {:name "workflow-definition-preview-selects-latest-run-by-created-at" :fn workflow-definition-preview-selects-latest-run-by-created-at})
(table.insert tests {:name "workflow-step-explorer-reveal-all-button-materializes-steps" :fn workflow-step-explorer-reveal-all-button-materializes-steps})
(table.insert tests {:name "workflow-definition-preview-open-explorer-buttons" :fn workflow-definition-preview-open-explorer-buttons})
(table.insert tests {:name "workflow-definition-preview-drops-owned-children-and-search-listeners" :fn workflow-definition-preview-drops-owned-children-and-search-listeners})
(table.insert tests {:name "workflow-definition-load-run-rejects-foreign-definition" :fn (fn [] (with-runtime workflow-definition-load-run-rejects-foreign-definition-case))}) (table.insert tests {:name "workflow-run-explorer-lists-only-definition-runs" :fn (fn [] (with-runtime workflow-run-explorer-lists-only-definition-runs-case))}) (table.insert tests {:name "workflow-run-explorer-preview-search-materializes-one-run" :fn (fn [] (with-runtime workflow-run-explorer-preview-search-materializes-one-run-case))}) (each [_ test (ipairs ((require :tests/workflow-run-explorer-cases) {:with-runtime with-runtime :GraphMap GraphMap :seed-two-definitions-with-runs seed-two-definitions-with-runs :edge-target-key-set edge-target-key-set}))] (table.insert tests test)) (table.insert tests {:name "workflow-run-explorer-preview-drops-owned-children-and-search-listener" :fn (fn [] (with-runtime workflow-run-explorer-preview-drops-owned-children-and-search-listener-case))}) (table.insert tests {:name "workflow-definition-step-items-filter-to-definition" :fn workflow-definition-step-items-filter-to-definition}) (table.insert tests {:name "workflow-definition-load-step-materializes-one-selected-step" :fn workflow-definition-load-step-materializes-one-selected-step}) (table.insert tests {:name "workflow-definition-open-step-explorer-materializes-ux-node" :fn workflow-definition-open-step-explorer-materializes-ux-node}) (table.insert tests {:name "workflow-step-explorer-preview-search-selects-one-step" :fn workflow-step-explorer-preview-search-selects-one-step})
(table.insert tests {:name "workflow-step-explorer-preview-drops-owned-children-and-search-listener" :fn workflow-step-explorer-preview-drops-owned-children-and-search-listener}) (table.insert tests {:name "workflow-run-node-and-preview-have-no-generic-details-leftovers" :fn workflow-run-node-and-preview-have-no-generic-details-leftovers})
(table.insert tests {:name "workflow-definition-explicit-actions-materialize-selected-run-and-step-code" :fn workflow-definition-explicit-actions-materialize-selected-run-and-step-code})
(table.insert tests {:name "workflow-run-node-exposes-granular-inspection-actions" :fn workflow-run-node-exposes-granular-inspection-actions})
(table.insert tests {:name "workflow-run-show-run-steps-materializes-all-run-steps-only" :fn workflow-run-show-run-steps-materializes-all-run-steps-only})
(table.insert tests {:name "workflow-run-reveal-failed-steps-materializes-failed-subset" :fn workflow-run-reveal-failed-steps-materializes-failed-subset})
(table.insert tests {:name "workflow-run-open-timeline-materializes-timeline-node-only" :fn workflow-run-open-timeline-materializes-timeline-node-only})
(table.insert tests {:name "workflow status color mapping covers all statuses" :fn workflow-status-color-mapping-covers-all-statuses})
(table.insert tests {:name "definition-new-step-creates-template-backed-step-and-loads-nodes" :fn definition-new-step-creates-template-backed-step-and-loads-nodes})
(table.insert tests {:name "definition-new-step-without-graph-does-not-persist-step-or-code" :fn definition-new-step-without-graph-does-not-persist-step-or-code})
(table.insert tests {:name "definition-new-step-rolls-back-when-graph-load-fails" :fn definition-new-step-rolls-back-when-graph-load-fails})
(table.insert tests {:name "workflow-step-show-code-loads-linked-code-node" :fn workflow-step-show-code-loads-linked-code-node})
(table.insert tests {:name "workflow-step-preview-builds-with-show-code-action" :fn workflow-step-preview-builds-with-show-code-action})
(table.insert tests {:name "workflow-run-timeline-preview-search-materializes-one-event" :fn workflow-run-timeline-preview-search-materializes-one-event}) (table.insert tests {:name "workflow-run-timeline-preview-drops-owned-children-and-search-listener" :fn workflow-run-timeline-preview-drops-owned-children-and-search-listener}) (table.insert tests {:name "workflow-run-preview-exposes-granular-buttons-without-details-toggle" :fn workflow-run-preview-exposes-granular-buttons-without-details-toggle}) (table.insert tests {:name "workflow-run-preview-drops-owned-children" :fn workflow-run-preview-drops-owned-children})
(table.insert tests {:name "workflow run node omits cancel action for succeeded run" :fn workflow-run-node-omits-cancel-action-for-succeeded-run})
(table.insert tests {:name "workflow run step status colors cover all run step statuses" :fn workflow-run-step-status-colors-cover-all-run-step-statuses})
(table.insert tests {:name "workflow-run-step-and-event-summaries-include-details" :fn workflow-run-step-and-event-summaries-include-details})
(table.insert tests {:name "workflow-run-step-preview-builds-summary" :fn workflow-run-step-preview-builds-summary})
(table.insert tests {:name "workflow-run-event-preview-builds-summary" :fn workflow-run-event-preview-builds-summary})
(table.insert tests {:name "workflow-run-step-node-has-payload-view" :fn workflow-run-step-node-has-payload-view}) (table.insert tests {:name "workflow-run-event-node-has-payload-view" :fn workflow-run-event-node-has-payload-view}) (table.insert tests {:name "workflow-run-step-view-renders-payload-in-multiline-input" :fn workflow-run-step-view-renders-payload-in-multiline-input}) (table.insert tests {:name "workflow-run-event-view-renders-payload-in-multiline-input" :fn workflow-run-event-view-renders-payload-in-multiline-input})
(table.insert tests {:name "workflow-run-step-view-drops-owned-children" :fn workflow-run-step-view-drops-owned-children}) (table.insert tests {:name "workflow-run-event-view-drops-owned-children" :fn workflow-run-event-view-drops-owned-children})
(table.insert tests {:name "graph step connection creates canonical workflow control edge" :fn graph-step-connection-creates-canonical-workflow-control-edge})
(table.insert tests {:name "graph map capture skips workflow derived edges" :fn graph-map-capture-skips-workflow-derived-edges})
(table.insert tests {:name "graph remove edge deletes canonical workflow edge" :fn graph-remove-edge-deletes-canonical-workflow-edge})
(table.insert tests {:name "graph remove derived workflow edge with caller opts clears domain and indexes" :fn graph-remove-derived-workflow-edge-with-caller-opts-clears-domain-and-indexes})
(table.insert tests {:name "start definition node creates visible run node and definition run edge" :fn start-definition-node-creates-visible-run-node-and-definition-run-edge})
(table.insert tests {:name "start definition node requires graph dependencies before persisting" :fn (fn [] (with-runtime start-definition-node-requires-graph-dependencies-before-persisting-case))}) (table.insert tests {:name "start definition node requires workflow-run loader before persisting" :fn (fn [] (with-runtime start-definition-node-requires-workflow-run-loader-before-persisting-case))})
(table.insert tests {:name "start context captures graph map and selected node keys" :fn start-context-captures-graph-map-and-selected-node-keys})
(table.insert tests {:name "graph code entity edits feed cached workflow executor" :fn graph-code-entity-edits-feed-cached-workflow-executor})
(table.insert tests {:name "template-helper-creates-durable-workflow-step-and-code" :fn template-helper-creates-durable-workflow-step-and-code})
(table.insert tests {:name "template-helper-keeps-code-entity-when-add-step-fails-after-commit" :fn template-helper-keeps-code-entity-when-add-step-fails-after-commit})
(table.insert tests {:name "template-helper-rolls-back-workflow-and-code-when-starter-step-fails-after-commit" :fn template-helper-rolls-back-workflow-and-code-when-starter-step-fails-after-commit})

(local main (fn [] (local runner (require :tests/runner)) (runner.run-tests {:name "workflow-graph" :tests tests})))
{:name "workflow-graph" :tests tests :main main}
