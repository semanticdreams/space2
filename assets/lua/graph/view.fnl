(local SpatialGraphView (require :graph/view/init))
(local GraphOutlineView (require :graph/view/outline))

(fn GraphView [options]
    (local graph-map (assert options.graph-map "GraphView requires :graph-map"))
    (if (= graph-map.view_mode "outline")
        (GraphOutlineView options)
        (SpatialGraphView options)))

GraphView
