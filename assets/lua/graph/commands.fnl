(local M {})

(fn resolve-graph-view [opts]
  (local resolver opts.graph-view)
  (and resolver (resolver)))

(fn require-graph-view [opts]
  (assert (resolve-graph-view opts) "GraphCommands requires graph view"))

(fn resolve-active-map [opts]
  (local resolver opts.graph-map)
  (and resolver (resolver)))

(fn require-active-map [opts]
  (assert (resolve-active-map opts) "GraphCommands requires active graph map"))

(fn resolve-map-manager [opts]
  (local resolver opts.graph-map-manager)
  (and resolver (resolver)))

(fn require-map-manager [opts]
  (assert (resolve-map-manager opts) "GraphCommands requires graph-map-manager"))

(fn has-selection? [opts]
  (local graph-view (resolve-graph-view opts))
  (and graph-view graph-view.selected-node-count (> (graph-view:selected-node-count) 0)))

(fn has-exactly-one-selected-node? [opts]
  (local graph-view (resolve-graph-view opts))
  (and graph-view
       graph-view.selected-node-count
       (= (graph-view:selected-node-count) 1)
       graph-view.focus-selected-node))

(fn has-focused-node? [opts]
  (local graph-view (resolve-graph-view opts))
  (and graph-view graph-view.has-focused-node? (graph-view:has-focused-node?)))

(fn focused-node-selected? [opts]
  (local graph-view (resolve-graph-view opts))
  (and graph-view graph-view.focused-node-selected? (graph-view:focused-node-selected?)))

(fn selection-non-empty? [opts]
  (has-selection? opts))

(fn has-visible-nodes? [opts]
  (local graph-view (resolve-graph-view opts))
  (and graph-view graph-view.has-visible-nodes? (graph-view:has-visible-nodes?)))

(fn focused-action [opts index]
  (local graph-view (resolve-graph-view opts))
  (and graph-view graph-view.focused-node-actions
       (. (graph-view:focused-node-actions) index)))

(fn focused-action-available? [opts index]
  (local action (focused-action opts index))
  (and (has-focused-node? opts) action (= (type action.fn) :function)))

(fn selected-map-key-count [graph-map]
  (if (and graph-map graph-map.selected_node_keys)
      (length graph-map.selected_node_keys)
      0))

(fn active-map-has-selection? [opts]
  (local graph-map (resolve-active-map opts))
  (and graph-map (> (selected-map-key-count graph-map) 0)))

(fn graph-map-clearable? [opts]
  (local graph-map (resolve-active-map opts))
  (and graph-map graph-map.clearable? (graph-map:clearable?)))

(fn graph-map-view-mode-toggleable? [opts]
  (local graph-map (resolve-active-map opts))
  (and graph-map graph-map.set-view-mode!))

(fn graph-map-outline-root-settable? [opts]
  (local graph-map (resolve-active-map opts))
  (and graph-map graph-map.set-outline-root-keys!))

(fn graph-view-focused-node-key [graph-view]
  (if (and graph-view graph-view.focused-node)
      (do
        (local node (graph-view:focused-node))
        (and node node.key))
      nil))

(fn current-focused-node-key [opts]
  (local graph-view (resolve-graph-view opts))
  (graph-view-focused-node-key graph-view))

(fn single-selected-node-key [graph-map]
  (local keys (and graph-map graph-map.selected_node_keys))
  (if (and keys (= (length keys) 1))
      (. keys 1)
      nil))

(fn graph-view-method-available? [opts method-name]
  (local graph-view (resolve-graph-view opts))
  (and graph-view (. graph-view method-name)))

(fn graph-view-focused-method-available? [opts method-name]
  (and (has-focused-node? opts)
       (graph-view-method-available? opts method-name)))

(fn graph-map-deps-available? [opts]
  (and (resolve-graph-view opts)
       (resolve-active-map opts)
       (resolve-map-manager opts)))

(fn run-selected [opts method-name]
  (local graph-view (require-graph-view opts))
  (if (and graph-view (. graph-view method-name) (has-selection? opts))
      (> ((. graph-view method-name) graph-view) 0)
      false))

(fn make-selected-preview-command [options id label method-name]
  (fn available? [_ctx]
    (not (not (has-selection? options))))
  (fn run [_ctx]
    (run-selected options method-name))
  {:id id
   :label label
   :available? available?
   :run run})

(fn run-selection [opts method-name availability-fn]
  (if (availability-fn opts)
      (do
        (local graph-view (require-graph-view opts))
        (local method (. graph-view method-name))
        (if method
            (do
              (method graph-view))
            false))
      false))

(fn make-selection-command [options id label method-name availability-fn]
  (fn available? [_ctx]
    (not (not (availability-fn options))))
  (fn run [_ctx]
    (run-selection options method-name availability-fn))
  {:id id
   :label label
    :available? available?
    :run run})

(fn make-graph-view-command [options id label method-name availability-fn]
  (fn available? [_ctx]
    (not (not (availability-fn options))))
  (fn run [_ctx]
    (local graph-view (require-graph-view options))
    (local method (assert (. graph-view method-name) (.. id " requires graph view method")))
    (method graph-view))
  {:id id
   :label label
   :available? available?
   :run run})

(fn make-focused-action-command [options index]
  (local id (.. "graph.node.action-" index))
  (fn available? [_ctx]
    (not (not (focused-action-available? options index))))
  (fn run [_ctx]
    (local graph-view (require-graph-view options))
    (graph-view:run-focused-node-action-slot index))
  {:id id
   :label (.. "action-" index)
   :available? available?
   :run run})

(fn make-map-command [options id label availability-fn run-fn]
  (fn available? [_ctx]
    (not (not (availability-fn options))))
  (fn run [_ctx]
    (run-fn options))
  {:id id
   :label label
   :available? available?
   :run run})

(fn map-add-start-available? [opts]
  (local graph-map (resolve-active-map opts))
  (and (resolve-graph-view opts)
       graph-map
       graph-map.add-start-node!))

(fn focus-start-available? [opts]
  (local graph-view (resolve-graph-view opts))
  (local graph-map (resolve-active-map opts))
  (and graph-view
       graph-map
       graph-view.reveal-node
       graph-map.add-start-node!))

(fn map-new-empty-available? [opts]
  (local manager (resolve-map-manager opts))
  (and (graph-map-deps-available? opts)
       manager.create-and-switch-map!))

(fn map-from-selection-available? [opts]
  (local graph-map (resolve-active-map opts))
  (local manager (resolve-map-manager opts))
  (and (graph-map-deps-available? opts)
       graph-map.capture-selected-subgraph-state
       manager.create-and-switch-map!
       (active-map-has-selection? opts)))

(fn map-clear-active-available? [opts]
  (local graph-map (resolve-active-map opts))
  (and (resolve-graph-view opts)
       graph-map
        graph-map.clear!
        (graph-map-clearable? opts)))

(fn outline-set-root-from-current-available? [opts]
  (local graph-map (resolve-active-map opts))
  (and (graph-map-outline-root-settable? opts)
       (if (current-focused-node-key opts)
           true
           (not (= (single-selected-node-key graph-map) nil)))))

(fn run-add-start [opts]
  (require-graph-view opts)
  (local graph-map (require-active-map opts))
  (assert graph-map.add-start-node! "GraphCommands requires active graph map add-start-node!")
  (graph-map:add-start-node!))

(fn run-focus-start [opts]
  (local graph-view (require-graph-view opts))
  (local graph-map (require-active-map opts))
  (assert graph-map.add-start-node!
          "GraphCommands requires active graph map add-start-node!")
  (assert graph-view.reveal-node
          "GraphCommands requires graph view reveal-node")
  (local node (assert (graph-map:add-start-node!)
                      "GraphCommands focus-start requires add-start-node! to return start node"))
  (assert (graph-view:reveal-node node {:select? true
                                        :focus? true
                                        :center? true})
          "GraphCommands focus-start failed to reveal start node"))

(fn run-new-empty [opts]
  (require-graph-view opts)
  (require-active-map opts)
  (local manager (require-map-manager opts))
  (assert manager.create-and-switch-map! "GraphCommands requires graph-map-manager create-and-switch-map!")
  (manager:create-and-switch-map! {:name nil}))

(fn run-from-selection [opts]
  (local graph-view (require-graph-view opts))
  (local graph-map (require-active-map opts))
  (local manager (require-map-manager opts))
  (assert graph-map.capture-selected-subgraph-state "GraphCommands requires active graph map capture-selected-subgraph-state")
  (assert manager.create-and-switch-map! "GraphCommands requires graph-map-manager create-and-switch-map!")
  (local state (graph-map:capture-selected-subgraph-state {:focused-node-key (graph-view-focused-node-key graph-view)
                                                           :focused-node-key-provided? true}))
  (manager:create-and-switch-map! {:name "Selection" :state state}))

(fn run-clear-active [opts]
  (require-graph-view opts)
  (local graph-map (require-active-map opts))
  (assert graph-map.clear! "GraphCommands requires active graph map clear!")
  (graph-map:clear!))

(fn run-toggle-outline [opts]
  (local graph-map (require-active-map opts))
  (assert graph-map.set-view-mode! "GraphCommands requires active graph map set-view-mode!")
  (graph-map:set-view-mode! (if (= graph-map.view_mode "outline") "spatial" "outline"))
  true)

(fn run-set-outline-root-from-current [opts]
  (local graph-map (require-active-map opts))
  (assert graph-map.set-outline-root-keys! "GraphCommands requires active graph map set-outline-root-keys!")
  (local focused-key (current-focused-node-key opts))
  (local selected-key (single-selected-node-key graph-map))
  (local root-key (or focused-key selected-key))
  (if root-key
      (do
        (graph-map:set-outline-root-keys! [root-key])
        true)
      false))

(fn add-focused-action-commands [commands options]
  (for [index 1 9]
    (local id (.. "graph.node.action-" index))
    (set (. commands id) (make-focused-action-command options index))))

(fn append-focused-action-bindings [bindings]
  (for [index 1 9]
    (table.insert bindings {:keys ["g" "n" (tostring index)]
                            :command (.. "graph.node.action-" index)
                            :label (.. "action-" index)
                            :priority (+ 50 index)})))

(fn M.provider [opts]
  (local options (if opts opts {}))
  (local commands
    {"graph.preview.expand-selected"
     (make-selected-preview-command options "graph.preview.expand-selected" "expand-preview" :expand-selected-previews)
     "graph.preview.collapse-selected"
     (make-selected-preview-command options "graph.preview.collapse-selected" "collapse-preview" :collapse-selected-previews)
     "graph.preview.toggle-selected"
     (make-selected-preview-command options "graph.preview.toggle-selected" "toggle-preview" :toggle-selected-previews)
     "graph.selection.select-focused"
     (make-selection-command options "graph.selection.select-focused" "select" :select-focused-node-only has-focused-node?)
     "graph.selection.add-focused"
     (make-selection-command options "graph.selection.add-focused" "add" :add-focused-node-to-selection has-focused-node?)
     "graph.selection.remove-focused"
     (make-selection-command options "graph.selection.remove-focused" "remove" :remove-focused-node-from-selection focused-node-selected?)
      "graph.selection.toggle-focused"
      (make-selection-command options "graph.selection.toggle-focused" "toggle" :toggle-focused-node-selection has-focused-node?)
      "graph.selection.clear"
       (make-selection-command options "graph.selection.clear" "clear" :clear-selection selection-non-empty?)
       "graph.selection.select-all"
       (make-selection-command options "graph.selection.select-all" "select-all" :select-all-visible-nodes has-visible-nodes?)
       "graph.selection.focus-selected"
       (make-selection-command options "graph.selection.focus-selected" "focus" :focus-selected-node has-exactly-one-selected-node?)
      "graph.node.open-focused"
     (make-graph-view-command options "graph.node.open-focused" "open" :open-focused-node #(graph-view-focused-method-available? $1 :open-focused-node))
     "graph.node.menu-focused"
     (make-graph-view-command options "graph.node.menu-focused" "menu" :open-focused-node-menu #(graph-view-focused-method-available? $1 :open-focused-node-menu))
     "graph.node.toggle-focused-preview"
     (make-graph-view-command options "graph.node.toggle-focused-preview" "toggle-preview" :toggle-focused-node-preview #(graph-view-focused-method-available? $1 :toggle-focused-node-preview))
     "graph.node.copy-focused-key"
     (make-graph-view-command options "graph.node.copy-focused-key" "copy-key" :copy-focused-node-key #(graph-view-focused-method-available? $1 :copy-focused-node-key))
     "graph.node.remove-focused-from-map"
     (make-graph-view-command options "graph.node.remove-focused-from-map" "remove" :remove-focused-node-from-map #(graph-view-focused-method-available? $1 :remove-focused-node-from-map))
     "graph.view.center-focused"
     (make-graph-view-command options "graph.view.center-focused" "center" :reveal-focused-node #(graph-view-focused-method-available? $1 :reveal-focused-node))
      "graph.view.start-layout"
      (make-graph-view-command options "graph.view.start-layout" "layout" :start-layout #(graph-view-method-available? $1 :start-layout))
      "graph.view.toggle-outline"
      (make-map-command options "graph.view.toggle-outline" "outline" graph-map-view-mode-toggleable? run-toggle-outline)
      "graph.outline.set-root-from-current"
      (make-map-command options "graph.outline.set-root-from-current" "root" outline-set-root-from-current-available? run-set-outline-root-from-current)
      "graph.view.focus-start"
      (make-map-command options "graph.view.focus-start" "start" focus-start-available? run-focus-start)
     "graph.map.add-start"
     (make-map-command options "graph.map.add-start" "add-start" map-add-start-available? run-add-start)
     "graph.map.new-empty"
     (make-map-command options "graph.map.new-empty" "new" map-new-empty-available? run-new-empty)
     "graph.map.from-selection"
     (make-map-command options "graph.map.from-selection" "selection" map-from-selection-available? run-from-selection)
     "graph.map.clear-active"
     (make-map-command options "graph.map.clear-active" "clear" map-clear-active-available? run-clear-active)})
  (add-focused-action-commands commands options)
  (local bindings [{:keys ["g" "p" "e"] :command "graph.preview.expand-selected" :label "expand-preview" :priority 10}
                   {:keys ["g" "p" "c"] :command "graph.preview.collapse-selected" :label "collapse-preview" :priority 20}
                   {:keys ["g" "p" "t"] :command "graph.preview.toggle-selected" :label "toggle-preview" :priority 30}
                   {:keys ["g" "s" "s"] :command "graph.selection.select-focused" :label "select" :priority 10}
                   {:keys ["g" "s" "a"] :command "graph.selection.add-focused" :label "add" :priority 20}
                   {:keys ["g" "s" "r"] :command "graph.selection.remove-focused" :label "remove" :priority 30}
                     {:keys ["g" "s" "t"] :command "graph.selection.toggle-focused" :label "toggle" :priority 40}
                     {:keys ["g" "s" "c"] :command "graph.selection.clear" :label "clear" :priority 50}
                     {:keys ["g" "s" "f"] :command "graph.selection.focus-selected" :label "focus" :priority 60}
                     {:keys ["g" "s" "e"] :command "graph.selection.select-all" :label "select-all" :priority 70}
                    {:keys ["g" "n" "o"] :command "graph.node.open-focused" :label "open" :priority 10}
                   {:keys ["g" "n" "m"] :command "graph.node.menu-focused" :label "menu" :priority 20}
                   {:keys ["g" "n" "t"] :command "graph.node.toggle-focused-preview" :label "toggle-preview" :priority 30}
                   {:keys ["g" "n" "y"] :command "graph.node.copy-focused-key" :label "copy-key" :priority 40}
                   {:keys ["g" "n" "r"] :command "graph.node.remove-focused-from-map" :label "remove" :priority 50}
                    {:keys ["g" "v" "c"] :command "graph.view.center-focused" :label "center" :priority 10}
                    {:keys ["g" "v" "l"] :command "graph.view.start-layout" :label "layout" :priority 20}
                    {:keys ["g" "v" "o"] :command "graph.view.toggle-outline" :label "outline" :priority 30}
                    {:keys ["g" "v" "s"] :command "graph.view.focus-start" :label "start" :priority 40}
                    {:keys ["g" "o" "r"] :command "graph.outline.set-root-from-current" :label "root" :priority 10}
                   {:keys ["g" "m" "a"] :command "graph.map.add-start" :label "add-start" :priority 10}
                   {:keys ["g" "m" "n"] :command "graph.map.new-empty" :label "new" :priority 20}
                   {:keys ["g" "m" "s"] :command "graph.map.from-selection" :label "selection" :priority 30}
                   {:keys ["g" "m" "c"] :command "graph.map.clear-active" :label "clear" :priority 40}])
  (append-focused-action-bindings bindings)
  {:commands commands
   :prefixes [{:keys ["g"] :label "graph" :priority 10}
               {:keys ["g" "p"] :label "preview" :priority 10}
               {:keys ["g" "s"] :label "selection" :priority 20}
                {:keys ["g" "n"] :label "node" :priority 30}
                {:keys ["g" "v"] :label "view" :priority 40}
                {:keys ["g" "o"] :label "outline" :priority 50}
                {:keys ["g" "m"] :label "map" :priority 60}]
   :bindings bindings})

{:provider M.provider}
