(local Common (require :graph/extensions/builtins/common))
(local WorkflowsNode (require :graph/nodes/workflows))
(local WorkflowDefinitionNode (require :graph/nodes/workflow-definition))
(local WorkflowStepNode (require :graph/nodes/workflow-step))
(local WorkflowRunNode (require :graph/nodes/workflow-run))
(local WorkflowRunStepNode (require :graph/nodes/workflow-run-step))
(local WorkflowRunEventNode (require :graph/nodes/workflow-run-event))
(local WorkflowRunTimelineNode (require :graph/nodes/workflow-run-timeline))
(local WorkflowStepExplorerNode (require :graph/nodes/workflow-step-explorer))
(local WorkflowRunExplorerNode (require :graph/nodes/workflow-run-explorer))
(local AgentSessionNode (require :graph/nodes/agent-session))

(local schemes
  ["workflows" "workflow-definition" "workflow-run" "workflow-step" "workflow-step-explorer"
   "workflow-run-explorer" "workflow-run-step" "workflow-run-event" "workflow-run-timeline" "agent-session"])

(fn loader-opts [ctx]
  {:owner-id ctx.owner-id :extension-id ctx.extension-id})

(fn owner-safe-graph [graph ctx]
  {:register-key-loader
   (fn [_self scheme loader-fn opts]
     (local options (if opts opts {}))
     (graph:register-key-loader scheme loader-fn
                                {:owner-id (if options.owner-id options.owner-id ctx.owner-id)
                                 :extension-id (if options.extension-id options.extension-id ctx.extension-id)}))})

(fn install-loaders [options graph ctx]
  (local workflow-store options.workflow-store)
  (if (not workflow-store)
      []
      (do
        (local code-store options.code-store)
        (local workflow-runner options.workflow-runner)
        (local safe-graph (owner-safe-graph graph ctx))
        (local handles [])
        (fn add! [handle]
          (assert (= (type handle) "table") "workflow descriptor expected handle")
          (assert (= (type handle.unregister) "function") "workflow descriptor expected handle.unregister")
          (table.insert handles handle))
        (add! (WorkflowsNode.register-loader safe-graph {:store workflow-store :runner workflow-runner :code-store code-store}))
        (when workflow-runner
          (add! (WorkflowDefinitionNode.register-loader safe-graph {:store workflow-store :runner workflow-runner :code-store code-store}))
          (add! (WorkflowRunNode.register-loader safe-graph {:store workflow-store :runner workflow-runner})))
        (add! (WorkflowStepNode.register-loader safe-graph {:store workflow-store}))
        (add! (WorkflowStepExplorerNode.register-loader safe-graph {:store workflow-store}))
        (add! (WorkflowRunExplorerNode.register-loader safe-graph {:store workflow-store}))
        (add! (WorkflowRunStepNode.register-loader safe-graph {:store workflow-store}))
        (add! (WorkflowRunEventNode.register-loader safe-graph {:store workflow-store}))
        (add! (WorkflowRunTimelineNode.register-loader safe-graph {:store workflow-store}))
        (add! (AgentSessionNode.register-loader safe-graph {:store workflow-store}))
        handles)))

(fn descriptors [opts]
  (local options (if opts opts {}))
  (fn install [graph ctx]
    (install-loaders options graph ctx))
  [(Common.descriptor
     {:id "builtin-graph-workflows"
      :unit-id "builtin-graph-workflows"
      :schemes schemes
      :install-loaders install})])

{:descriptors descriptors}
