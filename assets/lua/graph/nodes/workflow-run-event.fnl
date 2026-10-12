(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local WorkflowRunEventNodePreview (require :graph/view/previews/workflow-run-event))
(local WorkflowRunEventNodeView (require :graph/view/views/workflow-run-event))

(local EVENT_ORANGE (glm.vec4 0.85 0.45 0.15 1))
(local EVENT_ORANGE_ACCENT (glm.vec4 0.95 0.56 0.22 1))

(fn split-key-parts [text]
  (assert text "split-key-parts requires text")
  (local parts [])
  (each [part (string.gmatch text "[^:]+")]
    (table.insert parts part))
  parts)

(fn find-event [store run-id event-id]
  (var found nil)
  (local run (store:get-run run-id))
  (when run
    (each [_ event (ipairs run.events)]
      (when (= event.id event-id)
        (set found event))))
  found)

(fn event-key [run-id event-id]
  (.. "workflow-run-event:" run-id ":" event-id))

(fn get-event [self]
  (local store (assert self.workflow-store "WorkflowRunEventNode.get-event requires workflow store"))
  (local run-id (assert self.workflow-run-id "WorkflowRunEventNode.get-event requires workflow run id"))
  (local event-id (assert self.workflow-event-id "WorkflowRunEventNode.get-event requires workflow event id"))
  (assert (find-event store run-id event-id)
          (.. "WorkflowRunEventNode.get-event missing run event: " run-id ":" event-id)))

(fn WorkflowRunEventNode [opts]
  (local options (or opts {}))
  (local store (assert options.store "WorkflowRunEventNode requires store"))
  (local run-id (assert options.run-id "WorkflowRunEventNode requires run-id"))
  (local event-id (assert options.event-id "WorkflowRunEventNode requires event-id"))
  (local event (find-event store run-id event-id))
  (local node (GraphNode {:key (event-key run-id event-id)
                          :label (.. "Event " (tostring (or (and event event.kind) event-id)))
                           :color EVENT_ORANGE
                           :sub-color EVENT_ORANGE_ACCENT
                           :preview WorkflowRunEventNodePreview
                           :view WorkflowRunEventNodeView
                           :size 8.0}))
  (set node.workflow-run-id run-id)
  (set node.workflow-event-id event-id)
  (set node.workflow-store store)
  (set node.get-event get-event)
  node)

(fn parse-key [key]
  (local prefix "workflow-run-event:")
  (when (= (string.sub key 1 (string.len prefix)) prefix)
    (local parts (split-key-parts (string.sub key (+ 1 (string.len prefix)))))
    (when (= (length parts) 2)
      (values (. parts 1) (. parts 2)))))

(fn register-loader [graph opts]
  (local options (or opts {}))
  (local store (assert options.store "workflow-run-event.register-loader requires store"))
  (graph:register-key-loader "workflow-run-event"
    (fn [key]
      (local (run-id event-id) (parse-key key))
      (when (and run-id event-id (find-event store run-id event-id))
        (WorkflowRunEventNode {:run-id run-id :event-id event-id :store store})))))

{:WorkflowRunEventNode WorkflowRunEventNode
 :find-event find-event
 :parse-key parse-key
 :register-loader register-loader}
