(local M {})

(fn resolve-graph-view [opts]
  (local resolver (assert opts.graph-view "GraphCommands.provider requires graph-view resolver"))
  (resolver))

(fn has-selection? [opts]
  (local graph-view (resolve-graph-view opts))
  (and graph-view graph-view.selected-node-count (> (graph-view:selected-node-count) 0)))

(fn has-focused-node? [opts]
  (local graph-view (resolve-graph-view opts))
  (and graph-view graph-view.has-focused-node? (graph-view:has-focused-node?)))

(fn focused-node-selected? [opts]
  (local graph-view (resolve-graph-view opts))
  (and graph-view graph-view.focused-node-selected? (graph-view:focused-node-selected?)))

(fn selection-non-empty? [opts]
  (has-selection? opts))

(fn run-selected [opts method-name]
  (local graph-view (resolve-graph-view opts))
  (if (and graph-view (. graph-view method-name) (has-selection? opts))
      (> ((. graph-view method-name) graph-view) 0)
      false))

(fn make-selected-preview-command [options id label method-name]
  (fn available? [_ctx]
    (has-selection? options))
  (fn run [_ctx]
    (run-selected options method-name))
  {:id id
   :label label
   :available? available?
   :run run})

(fn run-selection [opts method-name availability-fn]
  (if (availability-fn opts)
      (do
        (local graph-view (resolve-graph-view opts))
        (local method (. graph-view method-name))
        (if method
            (do
              (method graph-view)
              true)
            false))
      false))

(fn make-selection-command [options id label method-name availability-fn]
  (fn available? [_ctx]
    (availability-fn options))
  (fn run [_ctx]
    (run-selection options method-name availability-fn))
  {:id id
   :label label
   :available? available?
   :run run})

(fn M.provider [opts]
  (local options (if opts opts {}))
  {:commands {"graph.preview.expand-selected"
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
               (make-selection-command options "graph.selection.clear" "clear" :clear-selection selection-non-empty?)}
    :prefixes [{:keys ["g"] :label "graph" :priority 10}
                {:keys ["g" "p"] :label "preview" :priority 10}
                {:keys ["g" "s"] :label "selection" :priority 20}]
    :bindings [{:keys ["g" "p" "e"] :command "graph.preview.expand-selected" :label "expand-preview" :priority 10}
                {:keys ["g" "p" "c"] :command "graph.preview.collapse-selected" :label "collapse-preview" :priority 20}
                {:keys ["g" "p" "t"] :command "graph.preview.toggle-selected" :label "toggle-preview" :priority 30}
                {:keys ["g" "s" "s"] :command "graph.selection.select-focused" :label "select" :priority 10}
                {:keys ["g" "s" "a"] :command "graph.selection.add-focused" :label "add" :priority 20}
                {:keys ["g" "s" "r"] :command "graph.selection.remove-focused" :label "remove" :priority 30}
                {:keys ["g" "s" "t"] :command "graph.selection.toggle-focused" :label "toggle" :priority 40}
                {:keys ["g" "s" "c"] :command "graph.selection.clear" :label "clear" :priority 50}]})

{:provider M.provider}
