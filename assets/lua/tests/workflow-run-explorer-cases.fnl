(var module-deps nil)

(fn run-foreign-case [deps runtime]
  (local seeded (deps.seed-two-definitions-with-runs runtime))
  (local map (deps.GraphMap.GraphMap {:graph runtime.graph :id "run-explorer-foreign-map"}))
  (local explorer (map:load-by-key (.. "workflow-run-explorer:" seeded.selected.id)))
  (local foreign-key (.. "workflow-run:" seeded.other-run.id))
  (local (ok err) (pcall explorer.load-run-from-graph explorer seeded.other-run))
  (assert (not ok) "workflow run explorer should reject a run owned by another definition")
  (assert (string.find (tostring err) "does not belong" 1 true) "foreign run failure should explain ownership mismatch")
  (assert (not (map:lookup foreign-key)) "foreign run rejection should not materialize the run node")
  (assert (not (. (deps.edge-target-key-set map.edges) foreign-key)) "foreign run rejection should not add a visible edge")
  (map:drop))

(fn run-missing-definition-case [deps runtime]
  (local seeded (deps.seed-two-definitions-with-runs runtime))
  (local map (deps.GraphMap.GraphMap {:graph runtime.graph :id "run-explorer-missing-definition-map"}))
  (local explorer (map:load-by-key (.. "workflow-run-explorer:" seeded.selected.id)))
  (runtime.store:delete-definition seeded.selected.id {})
  (local selected-run-key (.. "workflow-run:" seeded.selected-run.id))
  (local (ok err) (pcall explorer.load-run-from-graph explorer seeded.selected-run))
  (assert (not ok) "workflow run explorer should fail when owning definition is deleted")
  (assert (string.find (tostring err) "missing workflow definition" 1 true) "missing definition failure should be loud")
  (assert (not (map:lookup selected-run-key)) "missing definition failure should not materialize the run node")
  (assert (not (. (deps.edge-target-key-set map.edges) selected-run-key)) "missing definition failure should not add a visible edge")
  (map:drop))

(fn store-only-loader-case [deps runtime]
  (local Graph (require :graph/init))
  (local BuiltinGraphTestHelpers (require :tests/graph-builtin-extension-helpers))
  (local seeded (deps.seed-two-definitions-with-runs runtime))
  (local graph (Graph {:with-start false}))
  (local builtins (BuiltinGraphTestHelpers.install-builtins! graph {:code-store runtime.code-store :workflow-store runtime.store}))
  (local map (deps.GraphMap.GraphMap {:graph graph :id "run-explorer-no-runner-map"}))
  (local explorer (map:load-by-key (.. "workflow-run-explorer:" seeded.selected.id)))
  (assert explorer "workflow-run-explorer key should load with workflow-store only")
  (assert (= (length (explorer:run-items)) 1) "store-only run explorer should list scoped runs")
  (assert (not (graph:has-key-loader-for-key (.. "workflow-run:" seeded.selected-run.id))) "store-only registration should not register workflow-run loader")
  (map:drop)
  (builtins:drop)
  (graph:drop))

(fn run-foreign []
  (module-deps.with-runtime (fn [runtime] (run-foreign-case module-deps runtime))))

(fn run-missing-definition []
  (module-deps.with-runtime (fn [runtime] (run-missing-definition-case module-deps runtime))))

(fn store-only-loader []
  (module-deps.with-runtime (fn [runtime] (store-only-loader-case module-deps runtime))))

(fn make-tests [deps]
  (set module-deps deps)
  [{:name "workflow-run-explorer-load-run-rejects-foreign-definition"
    :fn run-foreign}
   {:name "workflow-run-explorer-load-run-revalidates-definition"
    :fn run-missing-definition}
   {:name "workflow-run-explorer-key-loads-with-store-without-runner"
    :fn store-only-loader}])

make-tests
