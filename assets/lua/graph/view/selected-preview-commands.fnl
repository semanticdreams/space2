(fn assert-not-dropped [view context]
  (local guard (assert view._assert-not-dropped
                       "GraphView selected preview command requires drop guard"))
  (guard context))

(fn toggle-node-presentation [view node]
  (local toggle (assert view._toggle-node-presentation
                        "GraphView selected preview command requires presentation toggler"))
  (toggle node))

(fn selected-node-count [self]
  (assert-not-dropped self "selected-node-count")
  (local selected (assert self.selected-nodes
                         "GraphView selected preview command requires selected-nodes"))
  (length selected))

(fn expand-selected-previews [self]
  (assert-not-dropped self "expand-selected-previews")
  (local selected (assert self.selected-nodes
                         "GraphView selected preview command requires selected-nodes"))
  (var changed 0)
  (each [_ node (ipairs selected)]
    (when (and node (. self.points node) (not (. self.expanded-nodes node)))
      (toggle-node-presentation self node)
      (set changed (+ changed 1))))
  changed)

(fn collapse-selected-previews [self]
  (assert-not-dropped self "collapse-selected-previews")
  (local selected (assert self.selected-nodes
                         "GraphView selected preview command requires selected-nodes"))
  (var changed 0)
  (each [_ node (ipairs selected)]
    (when (and node (. self.points node) (. self.expanded-nodes node))
      (toggle-node-presentation self node)
      (set changed (+ changed 1))))
  changed)

(fn toggle-selected-previews [self]
  (assert-not-dropped self "toggle-selected-previews")
  (local selected (assert self.selected-nodes
                         "GraphView selected preview command requires selected-nodes"))
  (var changed 0)
  (each [_ node (ipairs selected)]
    (when (and node (. self.points node))
      (toggle-node-presentation self node)
      (set changed (+ changed 1))))
  changed)

(fn install! [view assert-not-dropped-fn toggle-node-presentation-fn expanded-nodes]
  (set view.expanded-nodes expanded-nodes)
  (set view._assert-not-dropped assert-not-dropped-fn)
  (set view._toggle-node-presentation toggle-node-presentation-fn)
  (set view.selected-node-count selected-node-count)
  (set view.expand-selected-previews expand-selected-previews)
  (set view.collapse-selected-previews collapse-selected-previews)
  (set view.toggle-selected-previews toggle-selected-previews)
  view)

{:install! install!
 :selected-node-count selected-node-count
 :expand-selected-previews expand-selected-previews
 :collapse-selected-previews collapse-selected-previews
 :toggle-selected-previews toggle-selected-previews}
