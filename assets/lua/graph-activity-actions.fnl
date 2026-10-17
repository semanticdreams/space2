(fn selected-graph-nodes [view]
  (or (and view view.selection view.selection.selected-nodes)
      []))

(fn current-graph-map [fallback]
  (local runtime app.active-world-runtime)
  (or (and runtime
           runtime.graph-map-manager
           (runtime.graph-map-manager:get-active-map))
      (and runtime runtime.graph-map)
      app.graph-map
      fallback))

(fn show-link-entities-for-selection [context]
  (local graph (current-graph-map (and context.graph context.graph.graph-map)))
  (when (not graph)
    (lua "return nil"))
  (local selected (or (and context.graph context.graph.selected-nodes)
                      []))
  (when (<= (length selected) 0)
    (lua "return nil"))

  (local selected-keys {})
  (each [_ node (ipairs selected)]
    (local key (and node node.key))
    (when key
      (set (. selected-keys (tostring key)) true)))
  (when (= (next selected-keys) nil)
    (lua "return nil"))

  (local owner (or graph.graph graph))
  (local store (assert owner.link-store "Show link entities requires graph link-store"))
  (local identity-store (assert owner.identity-store "Show link entities requires graph identity-store"))
  (assert (= store.identity-store identity-store) "Show link entities identity-store mismatch")
  (local {:LinkEntityNode LinkEntityNode} (require :graph/nodes/link-entity))
  (local entities (store:list-entities))
  (each [_ entity (ipairs (or entities []))]
    (local source-key (identity-store:resolve-key entity.source-key))
    (local target-key (identity-store:resolve-key entity.target-key))
    (local entity-keys {source-key true target-key true})
    (var all-match true)
    (each [k _ (pairs selected-keys) &until (not all-match)]
      (when (not (. entity-keys (identity-store:resolve-key k)))
        (set all-match false)))
    (when all-match
      (local id (tostring (or (and entity entity.id) "")))
      (when (> (string.len id) 0)
        (local key (.. "link-entity:" id))
        (when (not (graph:lookup key))
          (graph:add-node (LinkEntityNode {:entity-id id
                                           :store store}))))))
  nil)

(fn graph-root-actions [context]
  (local actions [])
  (local graph (and context.graph context.graph.graph-map))
  (when (not graph)
    (lua "return actions"))
  (local selected (or (and context.graph context.graph.selected-nodes) []))
  (local canvas-target (or (and context.targets context.targets.canvas)
                            (and context.targets context.targets.hud)))
  (table.insert actions
                {:name "Add to Map"
                 :icon "add"
                 :fn (fn [_button _event]
                        (local AddToMap (require :graph/add-to-map-dialog))
                        (AddToMap.open-panel {:target (assert canvas-target
                                                            "Add to Map requires canvas or HUD target")
                                               :graph-map graph
                                               :graph-map-provider (fn []
                                                                     (local runtime app.active-world-runtime)
                                                                     (or (and runtime
                                                                              runtime.graph-map-manager
                                                                              (runtime.graph-map-manager:get-active-map))
                                                                         (and runtime runtime.graph-map)
                                                                         app.graph-map
                                                                         graph))}))})
  (table.insert actions
                {:name "Create String Entity"
                 :icon "note_add"
                  :fn (fn [_button _event]
                        (local StringEntityStore (require :entities/string))
                        (local store (StringEntityStore.get-default))
                        (local entity (store:create-entity {}))
                        (local active-graph-map (current-graph-map graph))
                        (when (and active-graph-map entity active-graph-map.load-by-key)
                          (active-graph-map:load-by-key (.. "string-entity:" (tostring entity.id)))))})
  (table.insert actions
                {:name "Create Link Entity"
                 :icon "link"
                 :fn (fn [_button _event]
                       (local LinkEntityStore (require :entities/link))
                       (local store (LinkEntityStore.get-default))
                       (local opts {})
                       (when (= (length selected) 2)
                         (set opts.source-key (or (. selected 1 :key) ""))
                         (set opts.target-key (or (. selected 2 :key) ""))
                         nil)
                        (local entity (store:create-entity opts))
                        (local active-graph-map (current-graph-map graph))
                        (when (and active-graph-map entity)
                          (local {:LinkEntityNode LinkEntityNode} (require :graph/nodes/link-entity))
                          (local node (LinkEntityNode {:entity-id entity.id
                                                       :store store}))
                          (active-graph-map:add-node node)))})
  (table.insert actions
                {:name "Show link entities"
                 :icon "link"
                 :fn (fn [_button _event]
                       (show-link-entities-for-selection context))})
  (table.insert actions
                {:name "Create List Entity"
                 :icon "playlist_add"
                 :fn (fn [_button _event]
                       (local ListEntityStore (require :entities/list))
                       (local store (ListEntityStore.get-default))
                       (local items [])
                       (each [_ node (ipairs selected)]
                         (when (and node node.key)
                           (table.insert items node.key)))
                        (local entity (store:create-entity {:items items}))
                        (local active-graph-map (current-graph-map graph))
                        (when (and active-graph-map entity)
                          (local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
                          (local node (ListEntityNode {:entity-id entity.id
                                                       :store store}))
                          (active-graph-map:add-node node)))})
  (table.insert actions
                {:name "Graph Control"
                 :icon "tune"
                 :fn (fn [_button _event]
                       (local launchable (require :launchables/graph-control))
                       (launchable.open-panel {:target canvas-target}))})
  actions)

{:selected-graph-nodes selected-graph-nodes
 :current-graph-map current-graph-map
 :graph-root-actions graph-root-actions}
