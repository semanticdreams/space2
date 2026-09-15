(local fs (require :fs))
(local GraphMap (require :graph/map))
(local BuiltinGraphTestHelpers (require :tests/graph-builtin-extension-helpers))
(local _main (require :main))

(local tests [])
(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "workflow-graph-action-boundaries"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "graph-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir) (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (when (fs.exists dir) (fs.remove-all dir))
  (if ok result (error result)))

(fn make-runner [workflow-store]
  {:start-run (fn [_self definition-id input context]
                (workflow-store:create-run definition-id
                                           (if input input {})
                                           (if context context {})))})

(fn make-runtime [dir]
  (local {:WorkflowStore WorkflowStore} (require :workflows/store))
  (local CodeEntityStore (require :entities/code))
  (local workflow-store (WorkflowStore {:base-dir (fs.join-path dir "workflow")}))
  (local code-store (CodeEntityStore.CodeEntityStore {:base-dir (fs.join-path dir "code")}))
  {:store workflow-store :code-store code-store :runner (make-runner workflow-store)})

(fn with-runtime [f]
  (with-temp-dir (fn [dir] (f (make-runtime dir)))))

(fn make-graph-with-workflow-loaders [runtime loader-names]
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (local builtins (BuiltinGraphTestHelpers.install-builtins! graph {:workflow-store runtime.store
                                                                    :workflow-runner runtime.runner
                                                                    :code-store runtime.code-store
                                                                    :only-schemes loader-names}))
  (local original-drop graph.drop)
  (set graph.drop (fn [self]
                    (builtins:drop)
                    (original-drop self)))
  graph)

(fn workflows-root-new-workflow-without-required-loaders-does-not-persist-workflow-or-code-case [runtime]
  (local graph (make-graph-with-workflow-loaders runtime [:workflows :workflow-definition]))
  (local map (GraphMap.GraphMap {:graph graph :id "new-workflow-missing-loader-map"}))
  (local root (map:load-by-key "workflows"))
  (local before-definitions (length (runtime.store:list-definitions)))
  (local before-code (length (runtime.code-store:list-entities)))
  (local (ok err) (pcall root.create-workflow-from-graph root {:name "Should Not Persist"}))
  (assert (not ok) "New Workflow without required graph loaders should fail loudly")
  (assert (string.find (tostring err) "requires graph loader" 1 true) "missing loader failure should explain the missing graph loader")
  (assert (= (length (runtime.store:list-definitions)) before-definitions) "failed New Workflow should not persist a workflow definition")
  (assert (= (length (runtime.code-store:list-entities)) before-code) "failed New Workflow should not persist a code entity")
  (assert (= (map:node-count) 1) "failed New Workflow should not leave partial graph nodes")
  (assert (= (map:edge-count) 0) "failed New Workflow should not leave partial graph edges")
  (map:drop)
  (graph:drop))

(fn workflows-root-new-workflow-without-required-loaders-does-not-persist-workflow-or-code []
  (with-runtime workflows-root-new-workflow-without-required-loaders-does-not-persist-workflow-or-code-case))

(fn workflows-root-new-workflow-without-definition-loader-does-not-persist-workflow-or-code-case [runtime]
  (local graph (make-graph-with-workflow-loaders runtime [:workflows :workflow-step :code-entity]))
  (local map (GraphMap.GraphMap {:graph graph :id "new-workflow-missing-definition-loader-map"}))
  (local root (map:load-by-key "workflows"))
  (local before-definitions (length (runtime.store:list-definitions)))
  (local before-code (length (runtime.code-store:list-entities)))
  (local (ok err) (pcall root.create-workflow-from-graph root {:name "Should Not Persist"}))
  (assert (not ok) "New Workflow without workflow-definition loader should fail loudly")
  (assert (string.find (tostring err) "requires graph loader for workflow-definition" 1 true)
          "missing workflow-definition loader failure should explain the missing graph loader")
  (assert (= (length (runtime.store:list-definitions)) before-definitions)
          "failed New Workflow without workflow-definition loader should not persist a workflow definition")
  (assert (= (length (runtime.code-store:list-entities)) before-code)
          "failed New Workflow without workflow-definition loader should not persist a code entity")
  (assert (= (map:node-count) 1) "failed New Workflow without workflow-definition loader should not leave partial graph nodes")
  (assert (= (map:edge-count) 0) "failed New Workflow without workflow-definition loader should not leave partial graph edges")
  (map:drop)
  (graph:drop))

(fn workflows-root-new-workflow-without-definition-loader-does-not-persist-workflow-or-code []
  (with-runtime workflows-root-new-workflow-without-definition-loader-does-not-persist-workflow-or-code-case))

(fn seed-definition [runtime]
  (local code (runtime.code-store:create-entity {:id "code-a" :name "A" :source "(+ 1 1)"}))
  (local code-b (runtime.code-store:create-entity {:id "code-b" :name "B" :source "(+ 2 2)"}))
  (runtime.store:create-definition {:id "wf-demo" :name "Demo" :steps [{:id "step-a" :name "A" :code-entity-id code.id}
                                                                        {:id "step-b" :name "B" :code-entity-id code-b.id}]
                                    :edges [{:id "edge-a-b" :source-step-id "step-a" :target-step-id "step-b"}]}))

(fn seed-run [runtime]
  (local definition (seed-definition runtime))
  (local run (runtime.store:create-run definition.id {} {}))
  (runtime.store:upsert-run-step run.id "step-a" {:status :failed :error {:message "boom"}})
  (runtime.store:append-event run.id {:id "event-a" :kind :step-failed :step-id "step-a"})
  {:definition definition :run (runtime.store:get-run run.id)})

(fn assert-requires-mounted-graph-map [call message]
  (local (ok err) (pcall call))
  (assert (not ok) (.. message " should fail loudly without a mounted GraphMap"))
  (assert (string.find (tostring err) "requires a graph map" 1 true)
          (.. message " failure should explain graph map requirement")))

(fn assert-no-step-or-code-topology [map message]
  (each [key _ (pairs map.nodes)]
    (assert (not (string.find key "workflow-step:" 1 true)) (.. message " should not leave stale step graph nodes"))
    (assert (not (string.find key "code-entity:" 1 true)) (.. message " should not leave stale code graph nodes")))
  (assert (= (map:edge-count) 0) (.. message " should not leave stale graph edges")))

(fn assert-no-step-or-explorer-topology [map message]
  (each [key _ (pairs map.nodes)]
    (assert (not (string.find key "workflow-step:" 1 true)) (.. message " should not leave stale step graph nodes"))
    (assert (not (string.find key "workflow-step-explorer:" 1 true)) (.. message " should not leave stale step explorer graph nodes")))
  (assert (= (map:node-count) 1) (.. message " should leave only the already-loaded definition node"))
  (assert (= (map:edge-count) 0) (.. message " should not leave stale graph edges")))

(fn assert-no-run-step-or-timeline-topology [map before-edge-count message]
  (each [key _ (pairs map.nodes)]
    (assert (not (string.find key "workflow-run-step:" 1 true)) (.. message " should not leave stale run-step graph nodes"))
    (assert (not (string.find key "workflow-run-timeline:" 1 true)) (.. message " should not leave stale timeline graph nodes")))
  (assert (= (map:edge-count) before-edge-count) (.. message " should not add graph edges")))

(fn assert-no-run-event-topology [graph before-edge-count message]
  (each [key _ (pairs graph.nodes)]
    (assert (not (string.find key "workflow-run-event:" 1 true)) (.. message " should not leave stale run-event graph nodes")))
  (assert (= (graph:edge-count) before-edge-count) (.. message " should not add graph edges")))

(fn capture-node-keys [graph]
  (local keys {})
  (each [key _ (pairs graph.nodes)]
    (set (. keys key) true))
  keys)

(fn step-exists? [definition step-id]
  (var found false)
  (local steps (assert (and definition definition.steps) "step-exists? requires definition.steps"))
  (each [_ step (ipairs steps)]
    (when (= step.id step-id) (set found true)))
  found)

(fn graph-edge-touches-key? [graph key]
  (var found false)
  (each [_ edge (ipairs graph.edges)]
    (when (if (and edge.source (= edge.source.key key))
              true
              (and edge.target (= edge.target.key key)))
      (set found true)))
  found)

(fn action-named? [actions name]
  (var found false)
  (each [_ action (ipairs actions)]
    (when (= action.name name) (set found true)))
  found)

(fn assert-no-shared-graph-materializer-topology [graph before-edge-count before-keys message]
  (each [key _ (pairs graph.nodes)]
    (assert (. before-keys key) (.. message " should not leave newly materialized shared graph node: " key)))
  (assert (= (graph:edge-count) before-edge-count) (.. message " should not add graph edges")))

(fn assert-shared-graph-domain-unchanged [runtime definition-id before message]
  (assert (= (length (runtime.store:list-definitions)) before.definitions)
          (.. message " should not persist workflow definitions"))
  (assert (= (length (runtime.code-store:list-entities)) before.code)
          (.. message " should not persist code entities"))
  (assert (= (length (runtime.store:list-runs {:definition-id definition-id})) before.runs)
           (.. message " should not persist workflow runs"))
  (assert (= (length (. (runtime.store:get-definition definition-id) :steps)) before.steps)
          (.. message " should not persist workflow steps"))
  (assert (= (length (. (runtime.store:get-definition definition-id) :edges)) before.edges)
          (.. message " should not mutate workflow edges")))

(fn definition-new-step-without-code-loader-does-not-persist-or-leave-stale-graph-case [runtime]
  (local definition (seed-definition runtime))
  (local graph (make-graph-with-workflow-loaders runtime [:workflow-definition :workflow-step]))
  (local map (GraphMap.GraphMap {:graph graph :id "new-step-missing-code-loader-map"}))
  (local node (map:load-by-key (.. "workflow-definition:" definition.id)))
  (local before-steps (length (. (runtime.store:get-definition definition.id) :steps)))
  (local before-code (length (runtime.code-store:list-entities)))
  (local (ok err) (pcall node.create-step-from-graph node {:step-name "Should Not Persist"}))
  (assert (not ok) "New Step without code-entity loader should fail loudly")
  (assert (string.find (tostring err) "requires graph loader" 1 true) "missing code loader failure should explain the missing graph loader")
  (assert (= (length (. (runtime.store:get-definition definition.id) :steps)) before-steps) "failed New Step should not persist a workflow step")
  (assert (= (length (runtime.code-store:list-entities)) before-code) "failed New Step should not persist a code entity")
  (assert-no-step-or-code-topology map "failed New Step")
  (map:drop)
  (graph:drop))

(fn definition-new-step-without-code-loader-does-not-persist-or-leave-stale-graph []
  (with-runtime definition-new-step-without-code-loader-does-not-persist-or-leave-stale-graph-case))

(fn definition-new-step-code-load-failure-removes-stale-step-node-case [runtime]
  (local definition (seed-definition runtime))
  (local graph (make-graph-with-workflow-loaders runtime [:workflow-definition :workflow-step :code-entity]))
  (local map (GraphMap.GraphMap {:graph graph :id "new-step-code-load-failure-map"}))
  (local node (map:load-by-key (.. "workflow-definition:" definition.id)))
  (local original-load-by-key map.load-by-key)
  (fn fail-code-load [self key]
    (if (= (string.sub key 1 12) "code-entity:") nil (original-load-by-key self key)))
  (set map.load-by-key fail-code-load)
  (local before-steps (length (. (runtime.store:get-definition definition.id) :steps)))
  (local before-code (length (runtime.code-store:list-entities)))
  (local (ok err) (pcall node.create-step-from-graph node {:step-name "Should Roll Back"}))
  (assert (not ok) "New Step should fail loudly when code node loading fails")
  (assert (string.find (tostring err) "failed to load graph node" 1 true) "code load failure should surface graph materialization failure")
  (assert (= (length (. (runtime.store:get-definition definition.id) :steps)) before-steps) "code load failure should roll back the workflow step")
  (assert (= (length (runtime.code-store:list-entities)) before-code) "code load failure should roll back the code entity")
  (assert-no-step-or-code-topology map "code load failure")
  (map:drop)
  (graph:drop))

(fn definition-new-step-code-load-failure-removes-stale-step-node []
  (with-runtime definition-new-step-code-load-failure-removes-stale-step-node-case))

(fn definition-reveal-all-steps-without-step-loader-does-not-materialize-case [runtime]
  (local definition (seed-definition runtime))
  (local graph (make-graph-with-workflow-loaders runtime [:workflow-definition]))
  (local map (GraphMap.GraphMap {:graph graph :id "reveal-steps-missing-loader-map"}))
  (local node (map:load-by-key (.. "workflow-definition:" definition.id)))
  (local (ok err) (pcall node.reveal-all-steps-from-graph node))
  (assert (not ok) "Reveal all steps without workflow-step loader should fail loudly")
  (assert (string.find (tostring err) "requires graph loader" 1 true) "missing workflow-step loader failure should explain the missing graph loader")
  (assert-no-step-or-explorer-topology map "failed Reveal All Steps")
  (map:drop)
  (graph:drop))

(fn definition-reveal-all-steps-without-step-loader-does-not-materialize []
  (with-runtime definition-reveal-all-steps-without-step-loader-does-not-materialize-case))

(fn definition-open-step-explorer-without-loader-does-not-materialize-case [runtime]
  (local definition (seed-definition runtime))
  (local graph (make-graph-with-workflow-loaders runtime [:workflow-definition :workflow-step]))
  (local map (GraphMap.GraphMap {:graph graph :id "open-step-explorer-missing-loader-map"}))
  (local node (map:load-by-key (.. "workflow-definition:" definition.id)))
  (local (ok err) (pcall node.open-step-explorer-from-graph node))
  (assert (not ok) "Open step explorer without workflow-step-explorer loader should fail loudly")
  (assert (string.find (tostring err) "requires graph loader" 1 true) "missing workflow-step-explorer loader failure should explain the missing graph loader")
  (assert-no-step-or-explorer-topology map "failed Open Step Explorer")
  (map:drop)
  (graph:drop))

(fn definition-open-step-explorer-without-loader-does-not-materialize []
  (with-runtime definition-open-step-explorer-without-loader-does-not-materialize-case))

(fn definition-open-run-explorer-without-loader-does-not-materialize-case [runtime]
  (local definition (seed-definition runtime))
  (local graph (make-graph-with-workflow-loaders runtime [:workflow-definition :workflow-run]))
  (local map (GraphMap.GraphMap {:graph graph :id "open-run-explorer-missing-loader-map"}))
  (local node (map:load-by-key (.. "workflow-definition:" definition.id)))
  (local (ok err) (pcall node.open-run-explorer-from-graph node))
  (assert (not ok) "Open run explorer without workflow-run-explorer loader should fail loudly")
  (assert (string.find (tostring err) "requires graph loader" 1 true)
          "missing workflow-run-explorer loader failure should explain the missing graph loader")
  (assert (not (action-named? node.actions "Reveal Steps"))
          "definition actions should not expose Reveal Steps")
  (assert (= (map:node-count) 1) "failed Open Run Explorer should leave only the already-loaded definition node")
  (assert (= (map:edge-count) 0) "failed Open Run Explorer should not leave stale graph edges")
  (map:drop)
  (graph:drop))

(fn definition-open-run-explorer-without-loader-does-not-materialize []
  (with-runtime definition-open-run-explorer-without-loader-does-not-materialize-case))

(fn workflow-run-show-steps-without-run-step-loader-does-not-materialize-case [runtime]
  (local seeded (seed-run runtime))
  (local graph (make-graph-with-workflow-loaders runtime [:workflow-run]))
  (local map (GraphMap.GraphMap {:graph graph :id "run-steps-missing-loader-map"}))
  (local node (map:load-by-key (.. "workflow-run:" seeded.run.id)))
  (local before-edges (map:edge-count))
  (local (ok err) (pcall node.load-run-steps-from-graph node))
  (assert (not ok) "Show Run Steps without workflow-run-step loader should fail loudly")
  (assert (string.find (tostring err) "requires graph loader" 1 true) "missing workflow-run-step loader failure should explain the missing graph loader")
  (assert-no-run-step-or-timeline-topology map before-edges "failed Show Run Steps")
  (map:drop)
  (graph:drop))

(fn workflow-run-show-steps-without-run-step-loader-does-not-materialize []
  (with-runtime workflow-run-show-steps-without-run-step-loader-does-not-materialize-case))

(fn workflow-run-open-timeline-without-loader-does-not-materialize-case [runtime]
  (local seeded (seed-run runtime))
  (local graph (make-graph-with-workflow-loaders runtime [:workflow-run :workflow-run-step]))
  (local map (GraphMap.GraphMap {:graph graph :id "run-timeline-missing-loader-map"}))
  (local node (map:load-by-key (.. "workflow-run:" seeded.run.id)))
  (local before-edges (map:edge-count))
  (local (ok err) (pcall node.open-timeline-from-graph node))
  (assert (not ok) "Open Timeline without workflow-run-timeline loader should fail loudly")
  (assert (string.find (tostring err) "requires graph loader" 1 true) "missing workflow-run-timeline loader failure should explain the missing graph loader")
  (assert-no-run-step-or-timeline-topology map before-edges "failed Open Timeline")
  (map:drop)
  (graph:drop))

(fn workflow-run-open-timeline-without-loader-does-not-materialize []
  (with-runtime workflow-run-open-timeline-without-loader-does-not-materialize-case))

(fn workflow-run-timeline-shared-graph-event-load-requires-graph-map-case [runtime]
  (local seeded (seed-run runtime))
  (local graph (make-graph-with-workflow-loaders runtime [:workflow-run-timeline :workflow-run-event]))
  (local timeline (graph:load-by-key (.. "workflow-run-timeline:" seeded.run.id)))
  (local before-edges (graph:edge-count))
  (local (ok err) (pcall timeline.load-event-from-graph timeline "event-a"))
  (assert (not ok) "Timeline event load from shared Graph should fail loudly")
  (assert (string.find (tostring err) "requires a graph map" 1 true) "shared Graph failure should explain graph map requirement")
  (assert-no-run-event-topology graph before-edges "failed shared Graph timeline event load")
  (graph:drop))

(fn workflow-run-timeline-shared-graph-event-load-requires-graph-map []
  (with-runtime workflow-run-timeline-shared-graph-event-load-requires-graph-map-case))

(fn workflow-step-delete-removes-domain-step-and-visible-map-node-case [runtime]
  (local definition (seed-definition runtime))
  (local run (runtime.store:create-run definition.id {} {}))
  (runtime.store:upsert-run-step run.id "step-a" {:status :succeeded})
  (local graph (make-graph-with-workflow-loaders runtime [:workflow-definition :workflow-step :code-entity]))
  (local map (GraphMap.GraphMap {:graph graph :id "delete-step-map"}))
  (local definition-node (map:load-by-key (.. "workflow-definition:" definition.id)))
  (definition-node:reveal-all-steps-from-graph)
  (local step-key (.. "workflow-step:" definition.id ":step-a"))
  (local step-node (assert (map:lookup step-key) "Delete Step test requires visible step-a"))
  (step-node:show-code-from-graph)
  (assert step-node.delete-step-from-graph "workflow step should expose delete-step-from-graph")
  (assert (action-named? step-node.actions "Delete Step") "workflow step should expose Delete Step action")
  (local deleted (step-node:delete-step-from-graph))
  (local reloaded (runtime.store:get-definition definition.id))
  (assert (= deleted.id "step-a") "Delete Step should return deleted workflow step")
  (assert (not (step-exists? reloaded "step-a")) "Delete Step should remove workflow step")
  (assert (= (length reloaded.edges) 0) "Delete Step should remove dependent workflow edges")
  (assert (not (map:lookup step-key)) "Delete Step should remove visible workflow-step node")
  (assert (not (graph-edge-touches-key? map step-key)) "Delete Step should remove visible graph edges touching step")
  (assert (runtime.code-store:get-entity "code-a") "Delete Step should keep linked code entity durable")
  (local reloaded-run (runtime.store:get-run run.id))
  (assert (. reloaded-run.steps "step-a") "Delete Step should keep existing run history durable")
  (map:drop)
  (graph:drop))

(fn workflow-step-delete-removes-domain-step-and-visible-map-node []
  (with-runtime workflow-step-delete-removes-domain-step-and-visible-map-node-case))

(fn graph-materializing-methods-require-mounted-graph-map-case [runtime]
  (local seeded (seed-run runtime))
  (local graph (make-graph-with-workflow-loaders runtime [:workflow-definition
                                                          :workflows
                                                           :workflow-step
                                                           :workflow-step-explorer
                                                           :workflow-run
                                                           :workflow-run-explorer
                                                           :workflow-run-step
                                                          :workflow-run-timeline
                                                          :workflow-run-event
                                                          :code-entity]))
  (local root-node (graph:load-by-key "workflows"))
  (local definition-node (graph:load-by-key (.. "workflow-definition:" seeded.definition.id)))
  (local step-node (graph:load-by-key (.. "workflow-step:" seeded.definition.id ":step-a")))
  (local run-node (graph:load-by-key (.. "workflow-run:" seeded.run.id)))
  (local explorer-node (graph:load-by-key (.. "workflow-step-explorer:" seeded.definition.id)))
  (local timeline-node (graph:load-by-key (.. "workflow-run-timeline:" seeded.run.id)))
  (local before-edges (graph:edge-count))
  (local before-keys (capture-node-keys graph))
  (local before {:definitions (length (runtime.store:list-definitions))
                  :code (length (runtime.code-store:list-entities))
                  :runs (length (runtime.store:list-runs {:definition-id seeded.definition.id}))
                  :steps (length (. (runtime.store:get-definition seeded.definition.id) :steps))
                  :edges (length (. (runtime.store:get-definition seeded.definition.id) :edges))})
  (assert-requires-mounted-graph-map
    (fn [] (root-node:create-workflow-from-graph {:name "Shared Graph Leak"}))
    "WorkflowsNode.create-workflow-from-graph")
  (assert-requires-mounted-graph-map
    (fn [] (root-node:load-definition-from-graph seeded.definition.id))
    "WorkflowsNode.load-definition-from-graph")
  (assert-requires-mounted-graph-map
    (fn [] (definition-node:start-workflow-from-graph {:prompt "go"} {}))
    "WorkflowDefinitionNode.start-workflow-from-graph")
  (assert-requires-mounted-graph-map
    (fn [] (definition-node:create-step-from-graph {:step-name "Shared Graph Step"}))
    "WorkflowDefinitionNode.create-step-from-graph")
  (assert-requires-mounted-graph-map
    (fn [] (definition-node:load-run-from-graph seeded.run.id))
    "WorkflowDefinitionNode.load-run-from-graph")
  (assert-requires-mounted-graph-map
    (fn [] (definition-node:load-step-from-graph "step-a"))
    "WorkflowDefinitionNode.load-step-from-graph")
  (assert-requires-mounted-graph-map
    (fn [] (definition-node:reveal-all-steps-from-graph))
    "WorkflowDefinitionNode.reveal-all-steps-from-graph")
  (assert-requires-mounted-graph-map
    (fn [] (definition-node:open-step-explorer-from-graph))
    "WorkflowDefinitionNode.open-step-explorer-from-graph")
  (assert-requires-mounted-graph-map
    (fn [] (definition-node:open-run-explorer-from-graph))
    "WorkflowDefinitionNode.open-run-explorer-from-graph")
  (assert-requires-mounted-graph-map
    (fn [] (step-node:show-code-from-graph))
    "WorkflowStepNode.show-code-from-graph")
  (assert-requires-mounted-graph-map
    (fn [] (step-node:delete-step-from-graph))
    "WorkflowStepNode.delete-step-from-graph")
  (assert-requires-mounted-graph-map
    (fn [] (explorer-node:load-step-from-graph "step-a"))
    "WorkflowStepExplorerNode.load-step-from-graph")
  (assert-requires-mounted-graph-map
    (fn [] (explorer-node:reveal-all-steps-from-graph))
    "WorkflowStepExplorerNode.reveal-all-steps-from-graph")
  (assert-requires-mounted-graph-map
    (fn [] (run-node:load-run-steps-from-graph))
    "WorkflowRunNode.load-run-steps-from-graph")
  (assert-requires-mounted-graph-map
    (fn [] (run-node:open-timeline-from-graph))
    "WorkflowRunNode.open-timeline-from-graph")
  (assert-requires-mounted-graph-map
    (fn [] (timeline-node:load-event-from-graph "event-a"))
    "WorkflowRunTimelineNode.load-event-from-graph")
  (assert-no-shared-graph-materializer-topology graph before-edges before-keys "shared Graph materializers")
  (assert-shared-graph-domain-unchanged runtime seeded.definition.id before "shared Graph materializers")
  (graph:drop))

(fn graph-materializing-methods-require-mounted-graph-map []
  (with-runtime graph-materializing-methods-require-mounted-graph-map-case))

(fn selection-aware-start-validates-active-selection-case [runtime]
  (local definition (seed-definition runtime))
  (local graph (make-graph-with-workflow-loaders runtime [:workflow-definition :workflow-step :workflow-run]))
  (local map (GraphMap.GraphMap {:graph graph :id "selection-start-map"}))
  (local node (map:load-by-key (.. "workflow-definition:" definition.id)))
  (local before-runs (length (runtime.store:list-runs {:definition-id definition.id})))
  (local (empty-ok empty-err) (pcall node.start-workflow-with-selection-from-graph node {:prompt "go"} {}))
  (assert (not empty-ok) "selection-aware Start should fail loudly with no active selection")
  (assert (string.find (tostring empty-err) "requires selected graph nodes" 1 true)
          "empty selection failure should explain selected graph node requirement")
  (set map.selected_node_keys [node.key])
  (local (invalid-ok invalid-err) (pcall node.start-workflow-with-selection-from-graph node {:prompt "go"} {}))
  (assert (not invalid-ok) "selection-aware Start should reject unsupported selected node types")
  (assert (string.find (tostring invalid-err) "unsupported selected graph node" 1 true)
          "unsupported selection failure should identify unsupported selected nodes")
  (assert (= (length (runtime.store:list-runs {:definition-id definition.id})) before-runs)
          "invalid selection-aware Start should not persist workflow runs")
  (local step-key (.. "workflow-step:" definition.id ":step-a"))
  (map:load-by-key step-key)
  (set map.selected_node_keys [step-key])
  (local run (node:start-workflow-with-selection-from-graph {:prompt "go"} {}))
  (assert (= (. run.context :graph-map-id) "selection-start-map")
          "selection-aware Start should persist graph map id in run context")
  (assert (= (. run.context :graph-node-keys 1) step-key)
          "selection-aware Start should persist selected node keys in run context")
  (assert (map:lookup (.. "workflow-run:" run.id))
          "selection-aware Start should load the created run into the graph map")
  (map:drop)
  (graph:drop))

(fn selection-aware-start-validates-active-selection []
  (with-runtime selection-aware-start-validates-active-selection-case))

(fn selection-aware-start-rejects-workflow-run-explorer-selection-case [runtime]
  (local definition (seed-definition runtime))
  (local graph (make-graph-with-workflow-loaders runtime [:workflow-definition
                                                          :workflow-step
                                                          :workflow-run
                                                          :workflow-run-explorer]))
  (local map (GraphMap.GraphMap {:graph graph :id "selection-start-run-explorer-map"}))
  (local node (map:load-by-key (.. "workflow-definition:" definition.id)))
  (local run-explorer-key (.. "workflow-run-explorer:" definition.id))
  (map:load-by-key run-explorer-key)
  (local before-runs (length (runtime.store:list-runs {:definition-id definition.id})))
  (set map.selected_node_keys [run-explorer-key])
  (local (ok err) (pcall node.start-workflow-with-selection-from-graph node {:prompt "go"} {}))
  (assert (not ok) "selection-aware Start should reject workflow-run-explorer selections")
  (assert (string.find (tostring err) "unsupported selected graph node" 1 true)
          "workflow-run-explorer selection failure should identify unsupported selected nodes")
  (assert (= (length (runtime.store:list-runs {:definition-id definition.id})) before-runs)
          "workflow-run-explorer selection should not persist workflow runs")
  (map:drop)
  (graph:drop))

(fn selection-aware-start-rejects-workflow-run-explorer-selection []
  (with-runtime selection-aware-start-rejects-workflow-run-explorer-selection-case))

(table.insert tests {:name "workflows-root-new-workflow-without-required-loaders-does-not-persist-workflow-or-code" :fn workflows-root-new-workflow-without-required-loaders-does-not-persist-workflow-or-code})
(table.insert tests {:name "workflows-root-new-workflow-without-definition-loader-does-not-persist-workflow-or-code" :fn workflows-root-new-workflow-without-definition-loader-does-not-persist-workflow-or-code})
(table.insert tests {:name "definition-new-step-without-code-loader-does-not-persist-or-leave-stale-graph" :fn definition-new-step-without-code-loader-does-not-persist-or-leave-stale-graph})
(table.insert tests {:name "definition-new-step-code-load-failure-removes-stale-step-node" :fn definition-new-step-code-load-failure-removes-stale-step-node})
(table.insert tests {:name "definition-reveal-all-steps-without-step-loader-does-not-materialize" :fn definition-reveal-all-steps-without-step-loader-does-not-materialize})
(table.insert tests {:name "definition-open-step-explorer-without-loader-does-not-materialize" :fn definition-open-step-explorer-without-loader-does-not-materialize})
(table.insert tests {:name "definition-open-run-explorer-without-loader-does-not-materialize" :fn definition-open-run-explorer-without-loader-does-not-materialize})
(table.insert tests {:name "workflow-run-show-steps-without-run-step-loader-does-not-materialize" :fn workflow-run-show-steps-without-run-step-loader-does-not-materialize})
(table.insert tests {:name "workflow-run-open-timeline-without-loader-does-not-materialize" :fn workflow-run-open-timeline-without-loader-does-not-materialize})
(table.insert tests {:name "workflow-run-timeline-shared-graph-event-load-requires-graph-map" :fn workflow-run-timeline-shared-graph-event-load-requires-graph-map})
(table.insert tests {:name "workflow-step-delete-removes-domain-step-and-visible-map-node" :fn workflow-step-delete-removes-domain-step-and-visible-map-node})
(table.insert tests {:name "graph-materializing-methods-require-mounted-graph-map" :fn graph-materializing-methods-require-mounted-graph-map})
(table.insert tests {:name "selection-aware-start-validates-active-selection" :fn selection-aware-start-validates-active-selection})
(table.insert tests {:name "selection-aware-start-rejects-workflow-run-explorer-selection" :fn selection-aware-start-rejects-workflow-run-explorer-selection})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "workflow-graph-action-boundaries" :tests tests})))

{:name "workflow-graph-action-boundaries" :tests tests :main main}
