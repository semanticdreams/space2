(local {:GraphNode GraphNode} (require :graph/node-base))
(local WorkflowRunNode (require :graph/nodes/workflow-run))
(local WorkflowRunStepNodePreview (require :graph/view/previews/workflow-run-step))
(local WorkflowRunStepNodeView (require :graph/view/views/workflow-run-step))

(fn split-key-parts [text]
  (assert text "split-key-parts requires text")
  (local parts [])
  (each [part (string.gmatch text "[^:]+")]
    (table.insert parts part))
  parts)

(fn run-step-key [run-id step-id]
  (.. "workflow-run-step:" run-id ":" step-id))

(fn run-step-label [run-step step-id]
  (local status (if (and run-step run-step.status) run-step.status :pending))
  (.. "Run step " step-id " (" (tostring status) ")"))

(fn status-color [status]
  (WorkflowRunNode.status-color status))

(fn status-tone [status]
  (WorkflowRunNode.status-tone status))

(fn get-run-step [self]
  (local store (assert self.workflow-store "WorkflowRunStepNode.get-run-step requires workflow store"))
  (local run-id (assert self.workflow-run-id "WorkflowRunStepNode.get-run-step requires workflow run id"))
  (local step-id (assert self.workflow-step-id "WorkflowRunStepNode.get-run-step requires workflow step id"))
  (assert (store:get-run-step run-id step-id)
          (.. "WorkflowRunStepNode.get-run-step missing run step: " run-id ":" step-id)))

(fn WorkflowRunStepNode [opts]
  (local options (or opts {}))
  (local store (assert options.store "WorkflowRunStepNode requires store"))
  (local run-id (assert options.run-id "WorkflowRunStepNode requires run-id"))
  (local step-id (assert options.step-id "WorkflowRunStepNode requires step-id"))
  (local run-step (store:get-run-step run-id step-id))
  (local node (GraphNode {:key (run-step-key run-id step-id)
                          :label (run-step-label run-step step-id)
                           :color (WorkflowRunNode.status-color (and run-step run-step.status))
                           :sub-color (WorkflowRunNode.status-color (and run-step run-step.status))
                           :preview WorkflowRunStepNodePreview
                           :view WorkflowRunStepNodeView
                           :size 8.0}))
  (set node.workflow-run-id run-id)
  (set node.workflow-step-id step-id)
  (set node.workflow-store store)
  (set node.get-run-step get-run-step)
  node)

(fn parse-key [key]
  (local prefix "workflow-run-step:")
  (when (= (string.sub key 1 (string.len prefix)) prefix)
    (local parts (split-key-parts (string.sub key (+ 1 (string.len prefix)))))
    (when (= (length parts) 2)
      (values (. parts 1) (. parts 2)))))

(fn register-loader [graph opts]
  (local options (or opts {}))
  (local store (assert options.store "workflow-run-step.register-loader requires store"))
  (graph:register-key-loader "workflow-run-step"
    (fn [key]
      (local (run-id step-id) (parse-key key))
      (when (and run-id step-id (store:get-run-step run-id step-id))
        (WorkflowRunStepNode {:run-id run-id :step-id step-id :store store})))))

{:WorkflowRunStepNode WorkflowRunStepNode
  :parse-key parse-key
  :status-color status-color
  :status-tone status-tone
  :register-loader register-loader}
