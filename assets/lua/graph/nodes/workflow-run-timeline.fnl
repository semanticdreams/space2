(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local GraphMapContext (require :graph/map-context))
(local WorkflowRunTimelinePreview (require :graph/view/previews/workflow-run-timeline))

(local TIMELINE_PURPLE (glm.vec4 0.48 0.32 0.82 1))
(local TIMELINE_PURPLE_ACCENT (glm.vec4 0.62 0.44 0.95 1))

(fn timeline-key [run-id]
  (.. "workflow-run-timeline:" run-id))

(fn event-key [run-id event-id]
  (.. "workflow-run-event:" run-id ":" event-id))

(fn event-label [event]
  (local kind (tostring (if (and event event.kind) event.kind "event")))
  (if (and event event.step-id)
      (.. kind " · " (tostring event.step-id))
      kind))

(fn event-id [event-or-id action]
  (if (= (type event-or-id) :table)
      (assert event-or-id.id (.. action " requires event id"))
      (assert event-or-id (.. action " requires event id"))))

(fn find-event [events id]
  (var found nil)
  (each [_ event (ipairs (assert events "WorkflowRunTimelineNode.find-event requires events"))]
    (when (= event.id id)
      (set found event)))
  found)

(fn load-required-node [graph key action]
  (assert graph (.. action " requires a graph map"))
  (assert graph.load-by-key (.. action " requires graph:load-by-key"))
  (local node (graph:load-by-key key))
  (assert node (.. action " failed to load graph node: " key))
  node)

(fn add-visible-edge [graph source target label]
  (assert graph "WorkflowRunTimelineNode requires a graph map")
  (assert graph.add-edge "WorkflowRunTimelineNode requires graph:add-edge")
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

(fn current-events [self action]
  (assert self.workflow-store (.. action " requires workflow store"))
  (assert self.workflow-store.get-run (.. action " requires workflow store:get-run"))
  (assert self.workflow-store.list-events (.. action " requires workflow store:list-events"))
  (local run (self.workflow-store:get-run self.workflow-run-id))
  (assert run (.. action " missing workflow run: " (tostring self.workflow-run-id)))
  (self.workflow-store:list-events self.workflow-run-id))

(fn WorkflowRunTimelineNode [opts]
  (local options (or opts {}))
  (local store (assert options.store "WorkflowRunTimelineNode requires store"))
  (local run-id (assert options.run-id "WorkflowRunTimelineNode requires run-id"))
  (local node (GraphNode {:key (timeline-key run-id)
                          :label (.. "Timeline " run-id)
                          :color TIMELINE_PURPLE
                          :sub-color TIMELINE_PURPLE_ACCENT
                          :preview WorkflowRunTimelinePreview
                          :size 8.0}))
  (set node.workflow-run-id run-id)
  (set node.workflow-store store)
  (set node.event-items
       (fn [self]
         (local events (current-events self "WorkflowRunTimelineNode.event-items"))
         (icollect [_ event (ipairs events)]
           [event (event-label event)])))
  (set node.load-event-from-graph
        (fn [self event-or-id]
           (local action "WorkflowRunTimelineNode.load-event-from-graph")
           (GraphMapContext.assert-graph-map self.graph action)
           (assert self.graph.load-by-key (.. action " requires graph:load-by-key"))
          (assert self.graph.add-edge (.. action " requires graph:add-edge"))
          (local events (current-events self action))
          (local id (event-id event-or-id action))
          (local event (find-event events id))
          (assert event (.. action " event " (tostring id) " does not belong to workflow run " (tostring self.workflow-run-id)))
          (assert-graph-loader self.graph (event-key self.workflow-run-id id) action "workflow-run-event")
          (local event-node (load-required-node self.graph (event-key self.workflow-run-id id) action))
          (add-visible-edge self.graph self event-node "event")
          event-node))
  node)

(fn register-loader [graph opts]
  (local options (or opts {}))
  (local store (assert options.store "workflow-run-timeline.register-loader requires store"))
  (graph:register-key-loader "workflow-run-timeline"
    (fn [key]
      (local prefix "workflow-run-timeline:")
      (when (= (string.sub key 1 (string.len prefix)) prefix)
        (local run-id (string.sub key (+ 1 (string.len prefix))))
        (when (and (> (string.len run-id) 0) (store:get-run run-id))
          (WorkflowRunTimelineNode {:run-id run-id :store store}))))))

{:WorkflowRunTimelineNode WorkflowRunTimelineNode
 :event-label event-label
 :register-loader register-loader}
