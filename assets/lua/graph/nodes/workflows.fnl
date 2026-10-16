(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local GraphMapContext (require :graph/map-context))
(local WorkflowTemplates (require :workflows/templates))
(local WorkflowsNodePreview (require :graph/view/previews/workflows))

(local WORKFLOW_PURPLE (glm.vec4 0.45 0.25 0.75 1))
(local WORKFLOW_PURPLE_ACCENT (glm.vec4 0.58 0.38 0.88 1))

(fn load-required-node [graph key]
  (assert graph "WorkflowsNode requires a graph map for node loading")
  (assert graph.load-by-key "WorkflowsNode requires graph:load-by-key")
  (local node (graph:load-by-key key))
  (assert node (.. "WorkflowsNode failed to load graph node: " key))
  node)

(fn add-visible-edge [graph source target label]
  (assert graph "WorkflowsNode requires a graph map for edge creation")
  (assert graph.add-edge "WorkflowsNode requires graph:add-edge")
  (graph:add-edge (GraphEdge {:source source :target target :label label})))

(fn assert-graph-load-and-edge [graph action]
  (GraphMapContext.assert-graph-map graph action)
  (assert graph.load-by-key (.. action " requires graph:load-by-key"))
  (assert graph.add-edge (.. action " requires graph:add-edge")))

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

(fn assert-create-workflow-loaders [graph action]
  (assert-graph-loader graph "workflow-definition:__preflight__" action "workflow-definition")
  (assert-graph-loader graph "workflow-step:__preflight__:__step__" action "workflow-step")
  (assert-graph-loader graph "code-entity:__preflight__" action "code-entity"))

(fn remove-graph-nodes-by-key! [graph keys]
  (when (and graph graph.lookup graph.remove-nodes)
    (local nodes [])
    (each [_ key (ipairs keys)]
      (local node (graph:lookup key))
      (when node
        (table.insert nodes node)))
    (when (> (length nodes) 0)
      (graph:remove-nodes nodes {:cause "workflow-create-rollback"}))))

(fn rollback-created-workflow! [self result materialized-keys cause]
  (local rollback-errors [])
  (remove-graph-nodes-by-key! self.graph materialized-keys)
  (when (and result result.definition result.definition.id)
    (local (ok err) (pcall self.workflow-store.delete-definition
                           self.workflow-store
                           result.definition.id
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

(fn load-created-workflow-into-graph! [self result]
  (local definition-key (.. "workflow-definition:" result.definition.id))
  (local step-key (.. "workflow-step:" result.definition.id ":" result.step.id))
  (local code-key (.. "code-entity:" result.code-entity.id))
  (local definition-node (load-required-node self.graph definition-key))
  (local step-node (load-required-node self.graph step-key))
  (local code-node (load-required-node self.graph code-key))
  (add-visible-edge self.graph self definition-node "definition")
  (add-visible-edge self.graph definition-node step-node "step")
  (add-visible-edge self.graph step-node code-node "code"))

(fn list-required-definitions [store]
  (assert store "WorkflowsNode requires workflow store")
  (assert store.list-definitions "WorkflowsNode requires workflow-store:list-definitions")
  (store:list-definitions))

(fn definition-id [definition-or-id]
  (if (= (type definition-or-id) :table)
      definition-or-id.id
      definition-or-id))

(fn definition-label [definition]
  (local name (if definition.name definition.name definition.id))
  (if (= name definition.id)
      (tostring name)
      (.. name " (" definition.id ")")))

(fn WorkflowsNode [opts]
  (local options (or opts {}))
  (local store (assert options.store "WorkflowsNode requires store"))
  (local node (GraphNode {:key "workflows"
                          :label "Workflows"
                          :color WORKFLOW_PURPLE
                          :sub-color WORKFLOW_PURPLE_ACCENT
                          :preview WorkflowsNodePreview
                          :size 8.0}))
  (set node.workflow-store store)
  (set node.runner options.runner)
  (set node.code-store options.code-store)
  (set node.create-workflow-from-graph
       (fn [self opts]
         (assert self.workflow-store "WorkflowsNode.create-workflow-from-graph requires workflow store")
         (assert self.runner "WorkflowsNode.create-workflow-from-graph requires workflow runner")
          (assert self.code-store "WorkflowsNode.create-workflow-from-graph requires code store")
          (assert-graph-load-and-edge self.graph "WorkflowsNode.create-workflow-from-graph")
          (assert-create-workflow-loaders self.graph "WorkflowsNode.create-workflow-from-graph")
          (local result (WorkflowTemplates.create-template-workflow self.workflow-store self.code-store (or opts {})))
          (local definition-key (.. "workflow-definition:" result.definition.id))
          (local step-key (.. "workflow-step:" result.definition.id ":" result.step.id))
          (local code-key (.. "code-entity:" result.code-entity.id))
          (local (ok graph-err)
            (pcall load-created-workflow-into-graph! self result))
          (if ok
              result
              (rollback-created-workflow! self result [definition-key step-key code-key] graph-err))))
  (set node.definition-items
       (fn [self]
         (icollect [_ definition (ipairs (list-required-definitions self.workflow-store))]
           [definition (definition-label definition)])))
  (set node.load-definition-from-graph
        (fn [self definition-or-id]
          (GraphMapContext.assert-graph-map self.graph "WorkflowsNode.load-definition-from-graph")
          (assert self.graph.load-by-key "WorkflowsNode.load-definition-from-graph requires graph:load-by-key")
         (assert self.graph.add-edge "WorkflowsNode.load-definition-from-graph requires graph:add-edge")
         (local id (assert (definition-id definition-or-id)
                           "WorkflowsNode.load-definition-from-graph requires a workflow definition id"))
         (local definition-node (load-required-node self.graph (.. "workflow-definition:" id)))
         (add-visible-edge self.graph self definition-node "definition")
         definition-node))
  (set node.actions [{:name "New Workflow"
                        :icon "add"
                        :fn (fn [_button _event]
                              (node:create-workflow-from-graph {}))}])
  node)

(fn register-loader [graph opts]
  (local options (or opts {}))
  (local store (assert options.store "workflows.register-loader requires store"))
  (graph:register-key-loader "workflows"
    (fn [key]
      (when (= key "workflows")
        (WorkflowsNode {:store store
                        :runner options.runner
                        :code-store options.code-store})))))

{:WorkflowsNode WorkflowsNode
 :register-loader register-loader}
