(local M {})

(fn resolve-graph-view [opts]
  (local resolver (assert opts.graph-view "GraphCommands.provider requires graph-view resolver"))
  (resolver))

(fn has-selection? [opts]
  (local graph-view (resolve-graph-view opts))
  (and graph-view graph-view.selected-node-count (> (graph-view:selected-node-count) 0)))

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

(fn M.provider [opts]
  (local options (if opts opts {}))
  {:commands {"graph.preview.expand-selected"
              (make-selected-preview-command options "graph.preview.expand-selected" "expand-preview" :expand-selected-previews)
              "graph.preview.collapse-selected"
              (make-selected-preview-command options "graph.preview.collapse-selected" "collapse-preview" :collapse-selected-previews)
              "graph.preview.toggle-selected"
              (make-selected-preview-command options "graph.preview.toggle-selected" "toggle-preview" :toggle-selected-previews)}
   :bindings [{:keys ["g" "p" "e"] :command "graph.preview.expand-selected" :label "expand-preview" :priority 10}
              {:keys ["g" "p" "c"] :command "graph.preview.collapse-selected" :label "collapse-preview" :priority 20}
              {:keys ["g" "p" "t"] :command "graph.preview.toggle-selected" :label "toggle-preview" :priority 30}]})

{:provider M.provider}
