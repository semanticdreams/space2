(fn configured-node-actions [node]
    (if (= (type (and node node.actions)) :function)
        ((. node :actions) node)
        (and node node.actions)))

(fn add-preview-action! [actions opts node]
    (local expanded-nodes (or opts.expanded-nodes {}))
    (local toggle-node-presentation (assert opts.toggle-node-presentation
                                           "GraphNodeActions.build preview action requires :toggle-node-presentation"))
    (fn run-preview [_button _event]
        (toggle-node-presentation node))
    (table.insert actions
                  {:name (if (. expanded-nodes node) "Collapse" "Expand")
                   :icon (if (. expanded-nodes node) "close_fullscreen" "open_in_full")
                   :fn run-preview}))

(fn open-action [views focus-manager node]
    (fn run-open [_button event]
        (when focus-manager
            (focus-manager:arm-auto-focus {:event event}))
        (local (ok err) (pcall views.open views node))
        (when focus-manager
            (focus-manager:clear-auto-focus))
        (when (not ok)
            (error err)))
    {:name "Open"
     :icon "open_in_new"
     :fn run-open})

(fn copy-key-action [node]
    (fn run-copy [_button _event]
        (local runtime-gl (require :gl))
        (runtime-gl.clipboard-set (tostring node.key)))
    {:name "Copy key"
     :icon "content_copy"
     :fn run-copy})

(fn cube-action [node]
    (fn run-cube [_button _event]
        (local scene app.scene)
        (when (and scene scene.add-graph-node-cube)
            (scene:add-graph-node-cube {:node node})))
    {:name "cube"
     :fn run-cube})

(fn remove-from-map-action [graph-map node]
    (fn run-remove [_button _event]
        (when (and graph-map graph-map.remove-nodes)
            (graph-map:remove-nodes [node])))
    {:name "Remove from Map"
     :icon "close"
     :fn run-remove})

(fn set-outline-root-action [graph-map node]
    (fn run-set-outline-root [_button _event]
        (graph-map:set-outline-root-keys! [node.key])
        true)
    {:name "Set Outline Root"
     :fn run-set-outline-root})

(fn add-open-copy-map-actions! [actions opts node graph-map]
    (local views (assert opts.views "GraphNodeActions.build requires :views"))
    (local focus-manager opts.focus-manager)
    (table.insert actions (open-action views focus-manager node))
    (table.insert actions (copy-key-action node))
    (when (not= opts.include-preview-action? false)
        (add-preview-action! actions opts node))
    (table.insert actions (cube-action node))
    (table.insert actions (remove-from-map-action graph-map node))
    (table.insert actions (set-outline-root-action graph-map node)))

(fn build [opts node]
    (local options (or opts {}))
    (local graph-map (assert options.graph-map "GraphNodeActions.build requires :graph-map"))
    (local actions [])
    (add-open-copy-map-actions! actions options node graph-map)
    (table.insert actions {:type :separator})
    (each [_ action (ipairs (or (configured-node-actions node) []))]
        (when (and action action.name action.fn)
            (table.insert actions action)))
    actions)

{:build build}
