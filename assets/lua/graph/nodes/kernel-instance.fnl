(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))

(local INSTANCE_COLOR (glm.vec4 0.65 0.2 0.2 1))
(local INSTANCE_ACCENT (glm.vec4 0.75 0.25 0.25 1))

(fn KernelInstanceNode [opts]
  (local options (or opts {}))
  (local instance-id (assert options.instance-id "KernelInstanceNode requires instance-id"))
  (local Kernels (require :kernels))
  (local manager (or options.kernels (and app app.kernels) (Kernels.get-default)))
  (assert manager "KernelInstanceNode requires kernels manager")
  (local KernelInstanceNodeView (require :graph/view/views/kernel-instance))

  (local instance (manager:get-instance instance-id))
  (assert instance (.. "Kernel instance not found: " (tostring instance-id)))

  (local node
    (GraphNode {:key (.. "kernel-instance:" (tostring instance-id))
                :label (manager:instance-label instance)
                :color INSTANCE_COLOR
                :sub-color INSTANCE_ACCENT
                :size 8.0
                :view KernelInstanceNodeView}))

  (set node.instance-id instance-id)
  (set node.kernels manager)
  (set node.changed (Signal))

  (set node.get-instance
       (fn [self]
         (self.kernels:get-instance self.instance-id)))

  (set node.stop-instance
       (fn [self]
         (self.kernels:stop-instance self.instance-id)))

  (set node.refresh
       (fn [self]
         (local current (self:get-instance))
         (when current
           (set self.label (self.kernels:instance-label current))
           (self.changed:emit self))))

  (set node.actions
       [{:name "Stop Instance"
         :icon "stop"
         :fn (fn [_button _event]
               (node:stop-instance))}])

  (var instances-handler nil)
  (set instances-handler
       (manager.instances-changed:connect
         (fn [_]
           (local current (node:get-instance))
           (if current
               (node:refresh)
               (when (and node.graph node.graph.remove-nodes)
                  (node.graph:remove-nodes [node] {:cause "shared-delete"}))))))

  (set node.drop
       (fn [self]
         (when instances-handler
           (manager.instances-changed:disconnect instances-handler true)
           (set instances-handler nil))
         (self.changed:clear)))

  node)

{:KernelInstanceNode KernelInstanceNode}
