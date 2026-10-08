(local GraphCommands (require :graph/commands))

(var command-graph-view nil)
(var command-graph-map nil)
(var command-graph-map-manager nil)

(fn reset! []
  (set command-graph-view nil)
  (set command-graph-map nil)
  (set command-graph-map-manager nil)
  true)

(fn set-graph-view! [graph-view]
  (set command-graph-view graph-view)
  graph-view)

(fn set-graph-map! [graph-map]
  (set command-graph-map graph-map)
  graph-map)

(fn set-graph-map-manager! [manager]
  (set command-graph-map-manager manager)
  manager)

(fn resolve-command-graph-view []
  command-graph-view)

(fn resolve-command-graph-map []
  command-graph-map)

(fn resolve-command-graph-map-manager []
  command-graph-map-manager)

(fn provider []
  (GraphCommands.provider {:graph-view resolve-command-graph-view
                           :graph-map resolve-command-graph-map
                           :graph-map-manager resolve-command-graph-map-manager}))

(fn find-binding-by-command [bindings expected-command]
  (var found nil)
  (each [_ binding (ipairs bindings) &until found]
    (when (= binding.command expected-command)
      (set found binding)))
  found)

(fn binding-keys-match? [binding expected-keys]
  (if (not (= (length binding.keys) (length expected-keys)))
      false
      (do
        (var matches? true)
        (each [idx key (ipairs expected-keys) &until (not matches?)]
          (when (not (= (. binding.keys idx) key))
            (set matches? false)))
        matches?)))

(fn find-binding-by-keys [bindings expected-keys]
  (var found nil)
  (each [_ binding (ipairs bindings) &until found]
    (when (binding-keys-match? binding expected-keys)
      (set found binding)))
  found)

{:reset! reset!
 :set-graph-view! set-graph-view!
 :set-graph-map! set-graph-map!
 :set-graph-map-manager! set-graph-map-manager!
 :provider provider
 :find-binding-by-command find-binding-by-command
 :find-binding-by-keys find-binding-by-keys}
