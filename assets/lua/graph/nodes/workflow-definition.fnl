(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local GraphMapContext (require :graph/map-context))
(local WorkflowTemplates (require :workflows/templates))
(local WorkflowDefinitionNodePreview (require :graph/view/previews/workflow-definition))
(local WorkflowDefinitionNodeView (require :graph/view/views/workflow-definition))
(local Signal (require :signal))

(local DEFINITION_BLUE (glm.vec4 0.22 0.4 0.82 1))
(local DEFINITION_BLUE_ACCENT (glm.vec4 0.32 0.52 0.95 1))

(fn find-step [definition step-id]
  (var found nil)
  (when (and definition definition.steps)
    (each [_ step (ipairs definition.steps)]
      (when (= step.id step-id)
        (set found step))))
  found)

(fn load-required-node [graph key]
  (assert graph "WorkflowDefinitionNode requires a graph map for node loading")
  (assert graph.load-by-key "WorkflowDefinitionNode requires graph:load-by-key")
  (local node (graph:load-by-key key))
  (assert node (.. "WorkflowDefinitionNode failed to load graph node: " key))
  node)

(fn add-visible-edge [graph source target label edge-opts]
  (assert graph "WorkflowDefinitionNode requires a graph map for edge creation")
  (assert graph.add-edge "WorkflowDefinitionNode requires graph:add-edge")
  (graph:add-edge (GraphEdge {:source source :target target :label label}) edge-opts))

(fn step-key [definition-id step-id]
  (.. "workflow-step:" definition-id ":" step-id))

(fn run-key [run-id]
  (.. "workflow-run:" run-id))

(fn run-explorer-key [definition-id]
  (.. "workflow-run-explorer:" definition-id))

(fn run-label [run]
  (local status (if (and run run.status) run.status :pending))
  (.. "Workflow run " run.id " (" (tostring status) ")"))

(fn run-created-at [run]
  (if (and run run.created-at)
      (tonumber run.created-at)
      0))

(fn run-id-string [run]
  (if (and run run.id)
      (tostring run.id)
      ""))

(fn later-run? [candidate current]
  (local candidate-created-at (run-created-at candidate))
  (local current-created-at (run-created-at current))
  (if (not current)
      true
      (> candidate-created-at current-created-at)
      true
      (and (= candidate-created-at current-created-at)
           (> (run-id-string candidate) (run-id-string current)))
      true
      false))

(fn latest-run-status-from-runs [runs]
  (var latest nil)
  (each [_ run (ipairs (if runs runs []))]
    (when (and run (later-run? run latest))
      (set latest run)))
  (if (and latest latest.status) (tostring latest.status) "none"))

(fn step-label [step]
  (local name (if step.step-name step.step-name (if step.name step.name step.id)))
  (if (= name step.id)
      (tostring name)
      (.. name " (" step.id ")")))

(fn step-id [step-or-id action]
  (if (= (type step-or-id) :table)
      (assert step-or-id.id (.. action " requires step id"))
      (assert step-or-id (.. action " requires step id"))))

(fn current-definition [self action]
  (assert self.workflow-store (.. action " requires workflow store"))
  (assert self.workflow-store.get-definition (.. action " requires workflow store:get-definition"))
  (local definition (self.workflow-store:get-definition self.workflow-definition-id))
  (assert definition (.. action " missing workflow definition: " (tostring self.workflow-definition-id)))
  definition)

(fn load-owned-step-record [self step-or-id action]
  (local id (step-id step-or-id action))
  (local definition (current-definition self action))
  (local step (find-step definition id))
  (assert step (.. action " step " (tostring id)
                " does not belong to workflow definition " (tostring self.workflow-definition-id)))
  step)

(fn load-owned-run-record [self run-or-id]
  (assert self.workflow-store "WorkflowDefinitionNode.load-run-from-graph requires workflow store")
  (assert self.workflow-store.get-run "WorkflowDefinitionNode.load-run-from-graph requires workflow store:get-run")
  (local run-id (if (= (type run-or-id) :table)
                    (assert run-or-id.id "WorkflowDefinitionNode.load-run-from-graph requires run id")
                    (assert run-or-id "WorkflowDefinitionNode.load-run-from-graph requires run id")))
  (local run (self.workflow-store:get-run run-id))
  (assert run (.. "WorkflowDefinitionNode.load-run-from-graph missing workflow run: " (tostring run-id)))
  (assert (= run.definition-id self.workflow-definition-id)
          (.. "WorkflowDefinitionNode.load-run-from-graph run " (tostring run-id)
              " does not belong to workflow definition " (tostring self.workflow-definition-id)))
  run)

(fn assert-create-step-graph-dependencies [self]
  (GraphMapContext.assert-graph-map self.graph "WorkflowDefinitionNode.create-step-from-graph")
  (assert self.graph.load-by-key "WorkflowDefinitionNode.create-step-from-graph requires graph:load-by-key")
  (assert self.graph.add-edge "WorkflowDefinitionNode.create-step-from-graph requires graph:add-edge")
  (assert self.workflow-store.delete-step
          "WorkflowDefinitionNode.create-step-from-graph rollback requires workflow store:delete-step")
  (assert self.code-store.retire-entity!
          "WorkflowDefinitionNode.create-step-from-graph rollback requires code store:retire-entity!"))

(fn loader-graph [graph]
  (if (and graph graph.graph graph.graph.has-key-loader-for-key)
      graph.graph
      (if (and graph graph.has-key-loader-for-key)
          graph
          nil)))

(fn assert-graph-loader [graph key action label]
  (local provider (loader-graph graph))
  (assert (and provider (provider:has-key-loader-for-key key))
          (.. action " requires graph loader for " label)))

(fn assert-create-step-loaders [self]
  (assert-graph-loader self.graph "workflow-step:__preflight__:__step__"
                       "WorkflowDefinitionNode.create-step-from-graph"
                       "workflow-step")
  (assert-graph-loader self.graph "code-entity:__preflight__"
                       "WorkflowDefinitionNode.create-step-from-graph"
                       "code-entity"))

(fn assert-load-run-graph-dependencies [self]
  (GraphMapContext.assert-graph-map self.graph "WorkflowDefinitionNode.load-run-from-graph")
  (assert self.graph.load-by-key "WorkflowDefinitionNode.load-run-from-graph requires graph:load-by-key")
  (assert self.graph.add-edge "WorkflowDefinitionNode.load-run-from-graph requires graph:add-edge"))

(fn assert-step-graph-dependencies [self action]
  (GraphMapContext.assert-graph-map self.graph action)
  (assert self.graph.load-by-key (.. action " requires graph:load-by-key"))
  (assert self.graph.add-edge (.. action " requires graph:add-edge")))

(fn assert-step-loader [self action]
  (assert-graph-loader self.graph
                       (step-key self.workflow-definition-id "__preflight__")
                       action
                       "workflow-step"))

(fn assert-step-explorer-loader [self action]
  (assert-graph-loader self.graph
                       (.. "workflow-step-explorer:" self.workflow-definition-id)
                       action
                       "workflow-step-explorer"))

(fn assert-run-explorer-loader [self action]
  (assert-graph-loader self.graph
                       (run-explorer-key self.workflow-definition-id)
                       action
                       "workflow-run-explorer"))

(fn assert-start-graph-dependencies [self]
  (GraphMapContext.assert-graph-map self.graph "WorkflowDefinitionNode.start-workflow-from-graph")
  (assert self.graph.load-by-key "WorkflowDefinitionNode.start-workflow-from-graph requires graph:load-by-key")
  (assert self.graph.add-edge "WorkflowDefinitionNode.start-workflow-from-graph requires graph:add-edge")
  (local provider (loader-graph self.graph))
  (assert (and provider
               (provider:has-key-loader-for-key "workflow-run:__preflight__"))
           "WorkflowDefinitionNode.start-workflow-from-graph requires graph loader for workflow-run"))

(fn remove-graph-nodes-by-key! [graph keys]
  (when (and graph graph.lookup graph.remove-nodes)
    (local nodes [])
    (each [_ key (ipairs keys)]
      (local node (graph:lookup key))
      (when node
        (table.insert nodes node)))
    (when (> (length nodes) 0)
      (graph:remove-nodes nodes {:cause "workflow-step-create-rollback"}))))

(fn rollback-created-step! [self result cause]
  (local rollback-errors [])
  (when (and result result.step result.step.id)
    (remove-graph-nodes-by-key! self.graph [(step-key self.workflow-definition-id result.step.id)
                                            (and result.code-entity
                                                 result.code-entity.id
                                                 (.. "code-entity:" result.code-entity.id))]))
  (when (and result result.step result.step.id)
    (local (ok err) (pcall self.workflow-store.delete-step
                           self.workflow-store
                           self.workflow-definition-id
                           result.step.id
                           {:delete-dependent-edges? true}))
    (when (not ok)
      (table.insert rollback-errors (tostring err))))
  (when (and result result.code-entity result.code-entity.id)
    (local (ok err) (pcall self.code-store.retire-entity! self.code-store result.code-entity.id))
    (when (not ok)
      (table.insert rollback-errors (tostring err))))
  (if (> (length rollback-errors) 0)
      (error (.. (tostring cause) " (rollback failed: " (table.concat rollback-errors "; ") ")"))
      (error cause)))

(fn load-created-step-into-graph! [self result]
  (local step-key (step-key self.workflow-definition-id result.step.id))
  (local code-key (.. "code-entity:" result.code-entity.id))
  (local step-node (load-required-node self.graph step-key))
  (local code-node (load-required-node self.graph code-key))
  (add-visible-edge self.graph self step-node "step")
  (add-visible-edge self.graph step-node code-node "code"))

(fn copy-array [items]
  (local source (if (= items nil) [] items))
  (local out [])
  (each [_ item (ipairs source)]
    (table.insert out item))
  out)

(fn graph-context [graph context-opts]
  (local context (if (= context-opts nil) {} context-opts))
  (local out {})
  (each [k v (pairs context)]
    (set (. out k) v))
  (when (and graph graph.id)
    (set out.graph-map-id graph.id))
  (when (and graph graph.selected_node_keys)
    (set out.graph-node-keys (copy-array graph.selected_node_keys)))
  out)

(fn accepted-selection-key? [key]
  (if (not (= (type key) :string))
      false
      (= key "workflows")
      false
      (= (string.sub key 1 20) "workflow-definition:")
      false
      (= (string.sub key 1 23) "workflow-step-explorer:")
      false
      (= (string.sub key 1 22) "workflow-run-explorer:")
      false
      (= (string.sub key 1 22) "workflow-run-timeline:")
      false
      (string.find key ":" 1 true)
      true
      false))

(fn selected-graph-node-keys [graph action]
  (GraphMapContext.assert-graph-map graph action)
  (local selected (copy-array graph.selected_node_keys))
  (assert (> (length selected) 0) (.. action " requires selected graph nodes"))
  (each [_ key (ipairs selected)]
    (assert (accepted-selection-key? key)
            (.. action " unsupported selected graph node: " (tostring key)))
    (assert (graph:lookup key)
            (.. action " selected graph node is not visible in this graph map: " (tostring key))))
  selected)

(fn definition-label [definition definition-id]
  (if (and definition (> (string.len (if definition.name definition.name "")) 0))
      definition.name
      definition-id))

(fn trim-text [text]
  (assert (= (type text) :string) "WorkflowDefinitionNode.update-name requires a string name")
  (string.match (tostring text) "^%s*(.-)%s*$"))

(fn load-step-node-from-definition [self step]
  (local step-node (load-required-node self.graph (step-key self.workflow-definition-id step.id)))
  (add-visible-edge self.graph self step-node "step")
  step-node)

(fn reveal-workflow-step-edge [self loaded-steps workflow-edge]
  (local source-node (. loaded-steps workflow-edge.source-step-id))
  (local target-node (. loaded-steps workflow-edge.target-step-id))
  (when (and source-node target-node)
    (local workflow-edge-id (assert workflow-edge.id "WorkflowDefinitionNode.reveal-all-steps-from-graph requires workflow edge id"))
    (add-visible-edge self.graph
                      source-node
                      target-node
                      (if workflow-edge.kind workflow-edge.kind "workflow")
                      {:from-workflow-edge workflow-edge-id})))

(fn reveal-definition-steps [self action]
  (assert-step-graph-dependencies self action)
  (assert-step-loader self action)
  (local definition (current-definition self action))
  (local loaded-steps {})
  (local steps (assert definition.steps (.. action " requires definition.steps")))
  (local edges (assert definition.edges (.. action " requires definition.edges")))
  (each [_ step (ipairs steps)]
    (set (. loaded-steps step.id) (load-step-node-from-definition self step)))
  (each [_ workflow-edge (ipairs edges)]
    (reveal-workflow-step-edge self loaded-steps workflow-edge))
  {:step-count (length steps)
   :edge-count (length edges)
   :steps loaded-steps})

(fn workflow-definition-actions [node]
  [{:name "Start Run"
    :icon "play_arrow"
    :fn (fn [_button _event]
          (node:start-workflow-from-graph {} {}))}
   {:name "Start With Selection"
    :icon "play_circle"
    :fn (fn [_button _event]
          (node:start-workflow-with-selection-from-graph {} {}))}
   {:name "New Step"
    :icon "add"
    :fn (fn [_button _event]
          (node:create-step-from-graph {}))}
    {:name "Explore Steps"
     :icon "manage_search"
     :fn (fn [_button _event]
           (node:open-step-explorer-from-graph))}
    {:name "Explore Runs"
     :icon "history"
     :fn (fn [_button _event]
           (node:open-run-explorer-from-graph))}])

(fn clear-changed-on-drop [node]
  (local original-drop node.drop)
  (set node.drop
       (fn [self]
         (when original-drop
           (original-drop self))
         (when self.changed
           (self.changed:clear)))))

(fn WorkflowDefinitionNode [opts]
  (local options (or opts {}))
  (local store (assert options.store "WorkflowDefinitionNode requires store"))
  (local runner (assert options.runner "WorkflowDefinitionNode requires runner"))
  (local definition-id (assert options.definition-id "WorkflowDefinitionNode requires definition-id"))
  (local definition (store:get-definition definition-id))
  (local label (definition-label definition definition-id))
  (local node (GraphNode {:key (.. "workflow-definition:" definition-id)
                          :label label
                          :color DEFINITION_BLUE
                          :sub-color DEFINITION_BLUE_ACCENT
                          :view WorkflowDefinitionNodeView
                          :preview WorkflowDefinitionNodePreview
                          :size 8.0}))
  (set node.workflow-definition-id definition-id)
  (set node.workflow-store store)
  (set node.workflow-runner runner)
  (set node.code-store options.code-store)
  (set node.changed (Signal))
  (set node.update-name
       (fn [self new-name]
         (local trimmed (trim-text new-name))
         (assert (> (string.len trimmed) 0)
                 "WorkflowDefinitionNode.update-name requires a non-empty name")
         (assert self.workflow-store "WorkflowDefinitionNode.update-name requires workflow store")
         (assert self.workflow-store.update-definition
                 "WorkflowDefinitionNode.update-name requires workflow store:update-definition")
          (current-definition self "WorkflowDefinitionNode.update-name")
          (local updated (self.workflow-store:update-definition self.workflow-definition-id {:name trimmed}))
          (set self.label (definition-label updated self.workflow-definition-id))
          (self.changed:emit self)
          updated))
  (set node.start-workflow-from-graph
        (fn [self input context-opts]
           (assert-start-graph-dependencies self)
           (local run-input (if (= input nil) {} input))
           (local run (self.workflow-runner:start-run self.workflow-definition-id
                                                     run-input
                                                     (graph-context self.graph context-opts)))
           (local run-node (load-required-node self.graph (run-key run.id)))
           (add-visible-edge self.graph self run-node "run")
           run))
  (set node.start-workflow-with-selection-from-graph
       (fn [self input context-opts]
         (local action "WorkflowDefinitionNode.start-workflow-with-selection-from-graph")
         (selected-graph-node-keys self.graph action)
         (self:start-workflow-from-graph input context-opts)))
  (set node.create-step-from-graph
        (fn [self opts]
           (assert self.workflow-store "WorkflowDefinitionNode.create-step-from-graph requires workflow store")
           (assert self.code-store "WorkflowDefinitionNode.create-step-from-graph requires code store")
           (assert-create-step-graph-dependencies self)
           (assert-create-step-loaders self)
           (local result (WorkflowTemplates.create-template-step self.workflow-store
                                                                self.code-store
                                                                self.workflow-definition-id
                                                                (or opts {})))
          (local (ok graph-err)
            (pcall load-created-step-into-graph! self result))
          (if ok
               result
               (rollback-created-step! self result graph-err))))
  (set node.run-items
        (fn [self]
          (assert self.workflow-store "WorkflowDefinitionNode.run-items requires workflow store")
          (icollect [_ run (ipairs (self.workflow-store:list-runs {:definition-id self.workflow-definition-id}))]
            [run (run-label run)])))
  (set node.step-items
       (fn [self]
         (local definition (current-definition self "WorkflowDefinitionNode.step-items"))
         (local steps (assert definition.steps "WorkflowDefinitionNode.step-items requires definition.steps"))
          (icollect [_ step (ipairs steps)]
            [step (step-label step)])))
  (set node.workflow-summary
       (fn [self]
         (local definition (current-definition self "WorkflowDefinitionNode.workflow-summary"))
         (assert self.workflow-store.list-runs "WorkflowDefinitionNode.workflow-summary requires workflow store:list-runs")
         (local runs (self.workflow-store:list-runs {:definition-id self.workflow-definition-id}))
         {:definition-id self.workflow-definition-id
          :name (if definition.name definition.name self.workflow-definition-id)
          :step-count (length (or definition.steps []))
          :run-count (length runs)
          :latest-run-status (latest-run-status-from-runs runs)}))
  (set node.load-run-from-graph
         (fn [self run-or-id]
           (assert-load-run-graph-dependencies self)
           (local run (load-owned-run-record self run-or-id))
           (local run-id run.id)
           (local run-node (load-required-node self.graph (run-key run-id)))
           (add-visible-edge self.graph self run-node "run")
           run-node))
  (set node.load-step-from-graph
       (fn [self step-or-id]
         (assert-step-graph-dependencies self "WorkflowDefinitionNode.load-step-from-graph")
         (local step (load-owned-step-record self step-or-id "WorkflowDefinitionNode.load-step-from-graph"))
         (load-step-node-from-definition self step)))
  (set node.reveal-all-steps-from-graph
       (fn [self]
         (reveal-definition-steps self "WorkflowDefinitionNode.reveal-all-steps-from-graph")))
  (set node.open-step-explorer-from-graph
       (fn [self]
         (assert-step-graph-dependencies self "WorkflowDefinitionNode.open-step-explorer-from-graph")
         (assert-step-explorer-loader self "WorkflowDefinitionNode.open-step-explorer-from-graph")
          (local explorer-node (load-required-node self.graph (.. "workflow-step-explorer:" self.workflow-definition-id)))
          (add-visible-edge self.graph self explorer-node "steps")
          explorer-node))
  (set node.open-run-explorer-from-graph
       (fn [self]
         (assert-step-graph-dependencies self "WorkflowDefinitionNode.open-run-explorer-from-graph")
         (assert-run-explorer-loader self "WorkflowDefinitionNode.open-run-explorer-from-graph")
         (local explorer-node (load-required-node self.graph (run-explorer-key self.workflow-definition-id)))
         (add-visible-edge self.graph self explorer-node "runs")
         explorer-node))
  (set node.actions (workflow-definition-actions node))
  (clear-changed-on-drop node)
  node)

(fn register-loader [graph opts]
  (local options (or opts {}))
  (local store (assert options.store "workflow-definition.register-loader requires store"))
  (local runner (assert options.runner "workflow-definition.register-loader requires runner"))
  (graph:register-key-loader "workflow-definition"
    (fn [key]
      (local prefix "workflow-definition:")
      (when (= (string.sub key 1 (string.len prefix)) prefix)
        (local definition-id (string.sub key (+ 1 (string.len prefix))))
        (when (and (> (string.len definition-id) 0)
                   (store:get-definition definition-id))
           (WorkflowDefinitionNode {:definition-id definition-id
                                    :store store
                                    :runner runner
                                    :code-store options.code-store}))))))

{:WorkflowDefinitionNode WorkflowDefinitionNode
 :find-step find-step
 :register-loader register-loader}
