(fn copy-nodes [nodes]
    (assert (= (type nodes) :table) "SelectionEditing.copy-nodes requires nodes table")
    (local copied [])
    (each [_ node (ipairs nodes)]
        (table.insert copied node))
    copied)

(fn contains-node? [nodes node]
    (assert (= (type nodes) :table) "SelectionEditing.contains-node? requires nodes table")
    (var found? false)
    (each [_ candidate (ipairs nodes)]
        (when (= candidate node)
            (set found? true)))
    found?)

(fn remove-node [nodes node]
    (assert (= (type nodes) :table) "SelectionEditing.remove-node requires nodes table")
    (local remaining [])
    (each [_ candidate (ipairs nodes)]
        (when (not (= candidate node))
            (table.insert remaining candidate)))
    remaining)

(fn install! [view opts]
    (assert view "SelectionEditing.install! requires view")
    (local options (assert opts "SelectionEditing.install! requires opts"))
    (local assert-not-dropped (assert options.assert-not-dropped
                                      "SelectionEditing.install! requires assert-not-dropped"))
    (local focused-node (assert options.focused-node
                                "SelectionEditing.install! requires focused-node"))
    (local selected-node? (assert options.selected-node?
                                  "SelectionEditing.install! requires selected-node?"))
    (local selected-nodes (assert options.selected-nodes
                                  "SelectionEditing.install! requires selected-nodes"))
    (local points (assert options.points
                          "SelectionEditing.install! requires points"))
    (local selection (assert options.selection
                              "SelectionEditing.install! requires selection"))
    (local focus-nodes (assert options.focus-nodes
                               "SelectionEditing.install! requires focus-nodes"))
    (local selector options.selector)

    (fn points-for [nodes]
        (local selected-points [])
        (each [_ node (ipairs nodes)]
            (local point (. points node))
            (when (not point)
                (error (string.format "GraphView selection-editing missing point for selected node %s"
                                      (or (and node node.key) "<unknown>"))))
            (table.insert selected-points point))
        selected-points)

    (fn apply-selection! [nodes]
        (assert-not-dropped "selection-editing")
        (when selector
            (selector:set-selected (points-for nodes)))
        (selection:set-selection nodes)
        true)

    (set view.focused-node
         (fn [_self]
             (focused-node)))
    (set view.has-focused-node?
         (fn [self]
             (not (= (self:focused-node) nil))))
    (set view.focused-node-selected?
         (fn [self]
             (local node (self:focused-node))
             (if node
                 (not (not (selected-node? node)))
                 false)))
    (set view.select-focused-node-only
         (fn [self]
             (local node (self:focused-node))
             (if node
                 (apply-selection! [node])
                 false)))
    (set view.add-focused-node-to-selection
         (fn [self]
             (local node (self:focused-node))
             (if node
                 (do
                     (local next-selection (copy-nodes selected-nodes))
                     (when (not (contains-node? next-selection node))
                         (table.insert next-selection node))
                     (apply-selection! next-selection))
                 false)))
    (set view.remove-focused-node-from-selection
         (fn [self]
             (local node (self:focused-node))
             (if node
                 (apply-selection! (remove-node selected-nodes node))
                 false)))
    (set view.toggle-focused-node-selection
         (fn [self]
             (local node (self:focused-node))
             (if node
                 (if (selected-node? node)
                     (apply-selection! (remove-node selected-nodes node))
                     (do
                         (local next-selection (copy-nodes selected-nodes))
                         (table.insert next-selection node)
                         (apply-selection! next-selection)))
                 false)))
    (set view.clear-selection
          (fn [_self]
              (if (> (length selected-nodes) 0)
                  (apply-selection! [])
                  false)))
    (set view.focus-selected-node
         (fn [_self]
             (assert-not-dropped "focus-selected-node")
             (if (= (length selected-nodes) 1)
                 (do
                     (local node (. selected-nodes 1))
                     (local focus-node (. focus-nodes node))
                     (assert focus-node "GraphView focus-selected-node requires focus node")
                     (focus-node:request-focus)
                     true)
                 false)))
    view)

{:install! install!}
