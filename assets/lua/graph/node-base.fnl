(local glm (require :glm))
(local Utils (require :graph/core/utils))
(local KindBadge (require :graph/kind-badge))
(local DefaultNodePreview (require :graph/view/previews/default))

(fn GraphNode [opts]
    (local options (or opts {}))
    (local color (Utils.ensure-glm-vec4 options.color (glm.vec4 0.5 0.5 0.5 1)))
    (local accent (Utils.ensure-glm-vec4 options.sub-color color))
    (local kind-badge
      (KindBadge.normalize {:key options.key
                            :value options.kind-badge
                            :color color
                            :accent accent}))
    (local node {:key options.key
                 :label (or options.label options.key "node")
                 :color color
                 :accent accent
                 :kind-badge kind-badge
                 :view options.view
                 :preview (or options.preview options.view DefaultNodePreview)
                 :actions (or options.actions [])
                 :size (or options.size 8.0)
                 :graph nil})
    (set node.mount (fn [self graph]
        (set self.graph graph)
        self))
    (set node.unmount (fn [self]
        (set self.graph nil)
        self))
    (set node.drop (fn [_self] nil))
    node)

(fn node-id [node] (or (and node node.key) (tostring node)))

{:GraphNode GraphNode
 :node-id node-id}
