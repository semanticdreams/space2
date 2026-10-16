(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local GraphMapContext (require :graph/map-context))
(local GraphAuthoring (require :workflows/graph-authoring))
(local WorkflowStepNodePreview (require :graph/view/previews/workflow-step))

(local STEP_GREEN (glm.vec4 0.18 0.58 0.34 1))
(local STEP_GREEN_ACCENT (glm.vec4 0.28 0.72 0.46 1))

(fn split-key-parts [text]
  (assert text "split-key-parts requires text")
  (local parts [])
  (each [part (string.gmatch text "[^:]+")]
    (table.insert parts part))
  parts)

(fn find-step [definition step-id]
  (var found nil)
  (when (and definition definition.steps)
    (each [_ step (ipairs definition.steps)]
      (when (= step.id step-id)
        (set found step))))
  found)

(fn step-key [definition-id step-id]
  (.. "workflow-step:" definition-id ":" step-id))

(fn load-required-node [graph key]
  (assert graph "WorkflowStepNode requires a graph map for node loading")
  (assert graph.load-by-key "WorkflowStepNode requires graph:load-by-key")
  (local node (graph:load-by-key key))
  (assert node (.. "WorkflowStepNode failed to load graph node: " key))
  node)

(fn add-visible-edge [graph source target label]
  (assert graph "WorkflowStepNode requires a graph map for edge creation")
  (assert graph.add-edge "WorkflowStepNode requires graph:add-edge")
  (graph:add-edge (GraphEdge {:source source :target target :label label})))

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

(fn assert-show-code-graph-dependencies [self]
  (local action "WorkflowStepNode.show-code-from-graph")
  (GraphMapContext.assert-graph-map self.graph action)
  (assert self.graph.load-by-key (.. action " requires graph:load-by-key"))
  (assert self.graph.add-edge (.. action " requires graph:add-edge")))

(fn resolve-reference-lifecycle! [self]
  (local mounted (and self.graph self.graph.reference-lifecycle))
  (assert (or (not self.lifecycle) (not mounted) (= self.lifecycle mounted)) "reference lifecycle node/graph conflict")
  (local service (assert (or self.lifecycle mounted) "node requires reference lifecycle"))
  (assert (service:owns-store? "workflow-step" self.workflow-store) "reference lifecycle store ownership mismatch")
  service)

(fn step-label [step step-id]
  (if (and step (> (string.len (if step.name step.name "")) 0))
      step.name
      step-id))

(fn WorkflowStepNode [opts]
  (local options (or opts {}))
  (local store (assert options.store "WorkflowStepNode requires store"))
  (local definition-id (assert options.definition-id "WorkflowStepNode requires definition-id"))
  (local step-id (assert options.step-id "WorkflowStepNode requires step-id"))
  (local definition (store:get-definition definition-id))
  (local step (find-step definition step-id))
  (local label (step-label step step-id))
  (local node (GraphNode {:key (step-key definition-id step-id)
                          :label label
                          :color STEP_GREEN
                          :sub-color STEP_GREEN_ACCENT
                          :preview WorkflowStepNodePreview
                          :size 8.0}))
  (set node.workflow-definition-id definition-id)
  (set node.workflow-step-id step-id)
  (set node.workflow-store store)
  (set node.lifecycle options.lifecycle)
  (set node.resolve-reference-lifecycle! resolve-reference-lifecycle!)
  (set node.author-domain-edge
       (fn [self edge edge-opts]
         (GraphAuthoring.author-edge self (and edge edge.target) edge-opts)))
  (set node.remove-domain-edge
       (fn [_self edge edge-opts]
         (GraphAuthoring.delete-authored-edge edge edge-opts)))
  (set node.get-step (fn [self]
                        (find-step (self.workflow-store:get-definition self.workflow-definition-id)
                                   self.workflow-step-id)))
  (set node.show-code-from-graph
        (fn [self]
          (assert-show-code-graph-dependencies self)
          (local current-step (assert (self:get-step)
                                      "WorkflowStepNode.show-code-from-graph requires an existing workflow step"))
          (local code-entity-id (assert current-step.code-entity-id
                                        "WorkflowStepNode.show-code-from-graph requires step.code-entity-id"))
          (assert-graph-loader self.graph (.. "code-entity:" code-entity-id)
                               "WorkflowStepNode.show-code-from-graph"
                               "code-entity")
          (local code-node (load-required-node self.graph (.. "code-entity:" code-entity-id)))
          (add-visible-edge self.graph self code-node "code")
          code-node))
  (set node.delete-step-from-graph
       (fn [self _opts]
         (local service (self:resolve-reference-lifecycle!))
         (local result (service:delete! self.key))
         (when self.graph (self.graph:remove-nodes [self] {:cause "workflow-step-delete"}))
         result.source-record))
  (set node.actions [{:name "Show Code"
                       :icon "code"
                       :fn (fn [_button _event]
                             (node:show-code-from-graph))}
                     {:name "Delete Step"
                      :icon "delete"
                      :fn (fn [_button _event]
                            (node:delete-step-from-graph))}])
  node)

(fn parse-key [key]
  (local prefix "workflow-step:")
  (when (= (string.sub key 1 (string.len prefix)) prefix)
    (local parts (split-key-parts (string.sub key (+ 1 (string.len prefix)))))
    (when (= (length parts) 2)
      (values (. parts 1) (. parts 2)))))

(fn register-loader [graph opts]
  (local options (or opts {}))
  (local store (assert options.store "workflow-step.register-loader requires store"))
  (graph:register-key-loader "workflow-step"
    (fn [key]
      (local (definition-id step-id) (parse-key key))
      (when (and definition-id step-id)
        (local definition (store:get-definition definition-id))
        (when (find-step definition step-id)
          (WorkflowStepNode {:definition-id definition-id
                             :step-id step-id
                             :store store :lifecycle options.lifecycle}))))))

{:WorkflowStepNode WorkflowStepNode
 :parse-key parse-key
 :register-loader register-loader}
