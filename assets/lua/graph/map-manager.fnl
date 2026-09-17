(local Signal (require :signal))
(local GraphMap (require :graph/map))
(local fs (require :fs))
(local json (require :json))
(local JsonUtils (require :json-utils))

(fn ensure-int [v default]
    (if (and (= (type v) :number)
             (>= v 1)
             (= v (math.floor v)))
        (math.floor v)
        default))

(fn safe-map-id? [id]
    (and (= (type id) :string)
         (> (string.len id) 0)
         (not (= (string.sub id 1 1) "."))
         (not (string.find id "/" 1 true))
         (not (string.find id "\\" 1 true))
         (not (string.find id "." 1 true))))

(fn assert-safe-map-id [id context]
    (assert (safe-map-id? id)
            (.. context ": map-id contains invalid characters: " (tostring id))))

(fn split-key-parts [key]
    (local parts [])
    (when (= (type key) :string)
        (each [part (string.gmatch key "[^:]+")]
            (table.insert parts part)))
    parts)

(fn canonicalize-legacy-activity-key [key]
    (if (not (= (type key) :string))
        (values key false)
        (do
            (local parts (split-key-parts key))
            (local scheme (. parts 1))
            (local sandbox "sandbox")
            (local category-key?
                   (if (= scheme "background") true
                       (= scheme "skybox") true
                       (= scheme "lights") true
                       (= scheme "terrains") true
                       (= scheme "scene-panels") true
                       false))
            (if (and (= (length parts) 2) category-key?)
                (values (.. "activity-" scheme ":" (. parts 2) ":" sandbox) true)
                (and (= (length parts) 3)
                     (= scheme "light-type"))
                (values (.. "activity-light-type:" (. parts 2) ":" sandbox ":" (. parts 3)) true)
                (and (= (length parts) 4)
                     (= scheme "light"))
                (values (.. "activity-light:" (. parts 2) ":" sandbox ":" (. parts 3) ":" (. parts 4)) true)
                (and (= (length parts) 3)
                     (= scheme "terrain"))
                (values (.. "activity-terrain:" (. parts 2) ":" sandbox ":" (. parts 3)) true)
                (and (= (length parts) 3)
                     (= scheme "terrain-editor"))
                (values (.. "activity-terrain-editor:" (. parts 2) ":" sandbox ":" (. parts 3)) true)
                (and (= (length parts) 4)
                     (= scheme "terrain-tool"))
                (values (.. "activity-terrain-tool:" (. parts 2) ":" sandbox ":" (. parts 3) ":" (. parts 4)) true)
                (and (= (length parts) 3)
                     (= scheme "scene-panel"))
                (values (.. "activity-scene-panel:" (. parts 2) ":" sandbox ":" (. parts 3)) true)
                (values key false)))))

(fn sorted-keys [tbl]
    (local keys [])
    (local source (if tbl tbl {}))
    (each [key _ (pairs source)]
        (table.insert keys key))
    (table.sort keys (fn [a b] (< (tostring a) (tostring b))))
    keys)

(fn migrate-keyed-metadata-table! [tbl]
    (var migrated? false)
    (each [_ key (ipairs (sorted-keys tbl))]
        (local (canonical-key key-migrated?) (canonicalize-legacy-activity-key key))
        (when key-migrated?
            (when (= (. tbl canonical-key) nil)
                (tset tbl canonical-key (. tbl key)))
            (tset tbl key nil)
            (set migrated? true)))
    migrated?)

(fn migrate-panel-node-keys! [panels]
    (var migrated? false)
    (local source (if panels panels []))
    (each [_ panel (ipairs source)]
        (local (canonical-key key-migrated?) (canonicalize-legacy-activity-key (and panel panel.node-key)))
        (when key-migrated?
            (tset panel :node-key canonical-key)
            (set migrated? true)))
    migrated?)

(fn migrate-map-entry-state [entry]
    (local node-set {})
    (local migrated-nodes [])
    (var migrated? false)
    (local source-nodes (if entry.nodes entry.nodes []))
    (each [_ key (ipairs source-nodes)]
        (local (canonical-key key-migrated?) (canonicalize-legacy-activity-key key))
        (when key-migrated?
            (set migrated? true))
        (when (not (. node-set canonical-key))
            (tset node-set canonical-key true)
            (table.insert migrated-nodes canonical-key)))
    (local edge-set {})
    (local migrated-edges [])
    (local source-edges (if entry.edges entry.edges []))
    (each [_ edge (ipairs source-edges)]
        (if (= (type edge) :table)
            (do
                (local (source source-migrated?) (canonicalize-legacy-activity-key edge.source))
                (local (target target-migrated?) (canonicalize-legacy-activity-key edge.target))
                (when (if source-migrated? true target-migrated?)
                    (set migrated? true))
                (if (and (= source target) (if source-migrated? true target-migrated?))
                    (set migrated? true)
                    (do
                        (local edge-key (.. (tostring source) "->" (tostring target)))
                        (when (not (. edge-set edge-key))
                            (tset edge-set edge-key true)
                            (local migrated-edge {})
                            (each [k v (pairs edge)]
                                (tset migrated-edge k v))
                            (tset migrated-edge :source source)
                            (tset migrated-edge :target target)
                            (table.insert migrated-edges migrated-edge)))))))
    (local migrated-selection [])
    (local source-selection (if entry.selected_node_keys entry.selected_node_keys []))
    (each [_ key (ipairs source-selection)]
        (local (canonical-key key-migrated?) (canonicalize-legacy-activity-key key))
        (when key-migrated?
            (set migrated? true))
        (table.insert migrated-selection canonical-key))
    (local (focused-key focused-migrated?) (canonicalize-legacy-activity-key entry.focused_node_key))
    (when focused-migrated?
        (set migrated? true))
    (tset entry :nodes migrated-nodes)
    (tset entry :edges migrated-edges)
    (tset entry :selected_node_keys migrated-selection)
    (tset entry :focused_node_key focused-key)
    (values entry migrated?))

(fn GraphMapManager [opts]
    (local options (or opts {}))
    (local shared-graph (assert options.graph "GraphMapManager requires :graph"))
    (local data-dir options.data-dir)

    (var entries {})
    (var active-id nil)
    (var next-id 2)

    (local maps-changed (Signal))
    (local maps-will-change (Signal))

    (fn legacy-edge-has-explicit-metadata? [edge]
        (var has-metadata? false)
        (each [k _ (pairs (or edge {}))]
            (when (not (or (= k :source)
                           (= k :target)))
                (set has-metadata? true)))
        has-metadata?)

    (fn legacy-derived-link-edge? [edge]
        (local source-key (and edge edge.source))
        (local target-key (and edge edge.target))
        (local link-store (and shared-graph shared-graph.link-store))
        (fn resolve-link-key [key]
            (var resolved (if (and shared-graph shared-graph.resolve-key)
                              (shared-graph:resolve-key key)
                              key))
            (when (and (= resolved key)
                       (= (type key) :string)
                       (= (string.sub key 1 9) "identity:"))
                (local identity-store (and shared-graph shared-graph.identity-store))
                (local entity-id (string.sub key 10))
                (local entity (and identity-store identity-store.get-entity
                                   (identity-store:get-entity entity-id)))
                (when (and entity entity.target-key
                           (> (string.len (tostring entity.target-key)) 0))
                    (set resolved (tostring entity.target-key))))
            resolved)
        (fn link-candidates []
            (local candidates [])
            (local seen {})
            (fn add-candidate [entity]
                (when (and entity entity.id (not (. seen (tostring entity.id))))
                    (set (. seen (tostring entity.id)) true)
                    (table.insert candidates entity)))
            (when link-store.find-edges-for-nodes
                (each [_ entity (ipairs (or (link-store:find-edges-for-nodes [source-key target-key]) []))]
                    (add-candidate entity)))
            (when link-store.list-entities
                (each [_ entity (ipairs (or (link-store:list-entities) []))]
                    (add-candidate entity)))
            candidates)
        (if (or (legacy-edge-has-explicit-metadata? edge)
                (not (and (= (type source-key) :string)
                          (= (type target-key) :string)
                          link-store
                          (or link-store.find-edges-for-nodes
                              link-store.list-entities))))
            false
            (do
                (var derived? false)
                (each [_ entity (ipairs (link-candidates))]
                    (local resolved-source (resolve-link-key entity.source-key))
                    (local resolved-target (resolve-link-key entity.target-key))
                    (when (and (= (tostring resolved-source) source-key)
                               (= (tostring resolved-target) target-key))
                        (set derived? true)))
                derived?)))

    (fn explicit-legacy-edges [edge-list]
        (icollect [_ edge (ipairs (or edge-list []))]
            (if (not (legacy-derived-link-edge? edge))
                edge)))

    (fn metadata-path-for [map-id]
        (assert data-dir "GraphMapManager requires :data-dir for metadata operations")
        (assert-safe-map-id map-id "GraphMapManager.metadata-path-for")
        (fs.join-path (fs.join-path (fs.join-path data-dir "graph" "maps") map-id) "metadata.json"))

    (fn prune-metadata-for-state [metadata-path valid-node-keys map-id]
        (when (and metadata-path (fs.exists metadata-path))
            (local (read-ok content) (pcall fs.read-file metadata-path))
            (when (not read-ok)
                (error (string.format "GraphMapManager failed to read %s during metadata prune: %s"
                                      metadata-path
                                      content)))
            (local (parse-ok meta) (pcall json.loads content))
            (when (not parse-ok)
                (error (string.format "GraphMapManager failed to parse %s during metadata prune: %s"
                                      metadata-path
                                      meta)))
            (local positions (or meta.positions {}))
            (local presentations (or meta.presentations {}))
            (local sizes (or meta.sizes {}))
            (local panels (or meta.panels []))
            (local extra-panels (or meta.extra_panels []))
            (local kept-panels [])
            (local kept-extra-panels [])
            (var pruned-metadata? false)
            (when (migrate-keyed-metadata-table! positions)
                (set pruned-metadata? true))
            (when (migrate-keyed-metadata-table! presentations)
                (set pruned-metadata? true))
            (when (migrate-keyed-metadata-table! sizes)
                (set pruned-metadata? true))
            (when (migrate-panel-node-keys! panels)
                (set pruned-metadata? true))
            (when (migrate-panel-node-keys! extra-panels)
                (set pruned-metadata? true))
            (fn valid-node-key? [key]
                (and (= (type key) :string)
                     (. valid-node-keys key)))
            (fn wrong-map? [panel]
                (and panel.graph-map-id
                     (not (= panel.graph-map-id map-id))))
            (each [key _ (pairs positions)]
                (when (not (valid-node-key? key))
                    (tset positions key nil)
                    (set pruned-metadata? true)))
            (each [key _ (pairs presentations)]
                (when (not (valid-node-key? key))
                    (tset presentations key nil)
                    (set pruned-metadata? true)))
            (each [key _ (pairs sizes)]
                (when (not (valid-node-key? key))
                    (tset sizes key nil)
                    (set pruned-metadata? true)))
            (each [_ panel (ipairs panels)]
                (when (and (= (and panel panel.kind) "graph-node-view")
                           (not panel.graph-map-id))
                    (set panel.graph-map-id map-id)
                    (set pruned-metadata? true))
                (if (or (not (valid-node-key? panel.node-key))
                        (wrong-map? panel))
                    (set pruned-metadata? true)
                    (table.insert kept-panels panel)))
            (each [_ panel (ipairs extra-panels)]
                (when (and panel.kind (not panel.graph-map-id))
                    (set panel.graph-map-id map-id)
                    (set pruned-metadata? true))
                (if (or (not (valid-node-key? panel.node-key))
                        (wrong-map? panel))
                    (set pruned-metadata? true)
                    (table.insert kept-extra-panels panel)))
            (when pruned-metadata?
                (tset meta :positions positions)
                (tset meta :presentations presentations)
                (tset meta :sizes sizes)
                (tset meta :panels kept-panels)
                (tset meta :extra_panels kept-extra-panels)
                (JsonUtils.write-json! metadata-path meta))))

    (fn prune-hydrated-map! [entry]
        (when (and entry entry.map)
            (local valid-keys {})
            (each [key _ (pairs entry.map.nodes)]
                (tset valid-keys key true))
            (var pruned-nodes? false)
            (local kept-nodes [])
            (each [_ key (ipairs entry.nodes)]
                (if (. valid-keys key)
                    (table.insert kept-nodes key)
                    (set pruned-nodes? true)))
            (when data-dir
                (prune-metadata-for-state (metadata-path-for entry.id) valid-keys entry.id))
            (local pruned-islands (entry.map:prune-islands-for-node-keys valid-keys))
            (when (if pruned-nodes? true (> (length pruned-islands) 0))
                (local state (entry.map:capture-state))
                (set entry.nodes kept-nodes)
                (set entry.islands state.islands)
                (set entry.next_island_id state.next_island_id)
                (entry.map:clear-unresolved-restored-state)))
        (when (and entry entry.map entry.edges (> (length entry.edges) 0))
            (local valid-keys {})
            (each [key _ (pairs entry.map.nodes)]
                (tset valid-keys key true))
            (var pruned-edges? false)
            (local kept-edges [])
            (each [_ edge (ipairs entry.edges)]
                (if (and (. valid-keys edge.source)
                         (. valid-keys edge.target))
                    (table.insert kept-edges edge)
                    (set pruned-edges? true)))
            (when pruned-edges?
                (set entry.edges kept-edges)
                (entry.map:clear-unresolved-restored-state)
                true)))

    (fn construct-map [id name node-keys edge-list selected-keys focused-key islands next-island-id]
        (local map (GraphMap.GraphMap {:graph shared-graph :id id :name name}))
        (local (ok result)
            (pcall
              (fn []
                (when (or (> (length (or node-keys [])) 0)
                          (> (length (or edge-list [])) 0)
                          (> (length (or islands [])) 0)
                          (> (length (or selected-keys [])) 0)
                          (not (= next-island-id nil))
                          (not (= focused-key nil)))
                    (map:restore-state {:nodes (or node-keys [])
                                         :edges (or edge-list [])
                                         :islands (or islands [])
                                         :next_island_id next-island-id
                                         :selected_node_keys (or selected-keys [])
                                         :focused_node_key focused-key}))
                true)))
        (when (not ok)
            (map:drop)
            (error result))
        map)

    (fn capture-active-map-state []
        (local entry (. entries active-id))
        (when (and entry entry.map)
            (local state (entry.map:capture-state))
            {:nodes (or state.nodes [])
             :edges (or state.edges [])
             :islands (or state.islands [])
             :next_island_id state.next_island_id
             :selected_node_keys (or state.selected_node_keys [])
             :focused_node_key state.focused_node_key}))

    (fn build-active-map [target-id]
        (local entry (. entries target-id))
        (when entry
            (assert (not entry.map) (.. "GraphMapManager.build-active-map map already active: " target-id))
            (local (ok result)
                (pcall
                  (fn []
                    (set entry.map (construct-map target-id
                                                  (or entry.name target-id)
                                                   (or entry.nodes [])
                                                   (or entry.edges [])
                                                   (or entry.selected_node_keys [])
                                                   entry.focused_node_key
                                                   (or entry.islands [])
                                                   entry.next_island_id))
                    (prune-hydrated-map! entry)
                    (when (and (or (not entry.restored-from-state?) entry.seed-start?)
                               (= (length (or entry.nodes [])) 0)
                               (= (entry.map:node-count) 0)
                               shared-graph.has-key-loader-for-key
                               (shared-graph:has-key-loader-for-key "start"))
                        (entry.map:load-by-key "start"))
                    true)))
            (when (not ok)
                (local map-to-drop entry.map)
                (set entry.map nil)
                (when map-to-drop
                    (local (drop-ok drop-err)
                        (pcall (fn [] (map-to-drop:drop))))
                    (when (not drop-ok)
                        (error (.. "GraphMapManager failed to drop map after build failure: "
                                   (tostring drop-err)
                                   " (build failure: "
                                   (tostring result)
                                   ")"))))
                (error result))
            true))

    (fn hydrate-inactive-entry-for-capture! [entry]
        (when entry
            (var constructed-for-capture? false)
            (when (not entry.map)
                (set constructed-for-capture? true)
                (set entry.map (construct-map entry.id
                                              (or entry.name entry.id)
                                               (or entry.nodes [])
                                               (or entry.edges [])
                                               (or entry.selected_node_keys [])
                                               entry.focused_node_key
                                               (or entry.islands [])
                                               entry.next_island_id)))
            (local (ok result)
                (pcall
                  (fn []
                    (prune-hydrated-map! entry)
                    (local state (entry.map:capture-state))
                    (set entry.nodes (or state.nodes []))
                    (set entry.edges (or state.edges []))
                    (set entry.islands (or state.islands []))
                    (set entry.next_island_id state.next_island_id)
                    (set entry.selected_node_keys (or state.selected_node_keys []))
                    (set entry.focused_node_key state.focused_node_key)
                    true)))
            (when constructed-for-capture?
                (local map-to-drop entry.map)
                (set entry.map nil)
                (when map-to-drop
                    (local (drop-ok drop-err)
                        (pcall (fn [] (map-to-drop:drop))))
                    (when (and ok (not drop-ok))
                        (error drop-err))))
            (when (not ok)
                (error result)))
        entry)

    (fn drop-active-map []
        (local entry (. entries active-id))
        (when entry
            (when entry.map
                (local state (entry.map:capture-state))
                (set entry.nodes (or state.nodes []))
                (set entry.edges (or state.edges []))
                (set entry.islands (or state.islands []))
                (set entry.next_island_id state.next_island_id)
                (set entry.selected_node_keys (or state.selected_node_keys []))
                (set entry.focused_node_key state.focused_node_key)
                (entry.map:drop)
                (set entry.map nil))
            true))

    (fn get-active-entry []
        (. entries active-id))

    (fn parse-legacy-state [state]
        (local payload (or state {}))
        (local graph (or payload.graph {}))
        (var active-id-result "main")
        (var next-map-id 2)
        (var maps-list [])
        (fn sanitize-id [id context]
            (if (safe-map-id? id)
                id
                (do
                    (assert-safe-map-id id context)
                    nil)))
        (if (= (type graph.graph) :table)
            (do
                ;; Double-wrapped legacy: {:graph {:graph {:nodes [...], :edges [...]}}}
                (local core (or graph.graph {}))
                (table.insert maps-list {:id "main"
                                           :name "Main"
                                           :nodes (or core.nodes [])
                                           :edges (explicit-legacy-edges core.edges)
                                           :islands []
                                           :next_island_id nil
                                           :selected_node_keys (or core.selected_node_keys [])
                                           :focused_node_key core.focused_node_key})
                (when (not (= graph.active_map_id nil))
                    (set active-id-result (sanitize-id graph.active_map_id "legacy-graph.active_map_id")))
                (when graph.next_map_id
                    (set next-map-id (ensure-int graph.next_map_id 2)))
                (for [i 2 (length (or graph.maps []))]
                    (local legacy-map (. graph.maps i))
                    (when (= (type legacy-map) :table)
                        (local map-id (sanitize-id legacy-map.id (.. "legacy-graph.maps[" i "].id")))
                        (when map-id
                            (table.insert maps-list {:id map-id
                                                      :name (or legacy-map.name legacy-map.id)
                                                      :nodes (or legacy-map.nodes [])
                                                      :edges (explicit-legacy-edges legacy-map.edges)
                                                      :islands []
                                                      :next_island_id nil
                                                      :selected_node_keys (or legacy-map.selected_node_keys [])
                                                      :focused_node_key legacy-map.focused_node_key}))))
                (values active-id-result next-map-id maps-list))
            (or (= (type payload.maps) :table)
                (not (= payload.active_map_id nil)))
            (do
                ;; Maps format (may coexist with default .graph from merge-state-defaults)
                (set active-id-result (sanitize-id (if (not (= payload.active_map_id nil))
                                                        payload.active_map_id
                                                        "main")
                                                    "active_map_id"))
                (set next-map-id (ensure-int (or payload.next_map_id) 2))
                (local raw-maps (or payload.maps
                                    [{:id "main" :name "Main" :nodes [] :edges [] :selected_node_keys [] :focused_node_key nil}]))
                (each [_ entry (ipairs raw-maps)]
                    (when (= (type entry) :table)
                        (local map-id (sanitize-id entry.id (.. "maps-entry.id=" (tostring entry.id))))
                        (when map-id
                            (table.insert maps-list {:id map-id
                                                      :name (or entry.name entry.id)
                                                      :nodes (or entry.nodes [])
                                                      :edges (or entry.edges [])
                                                      :islands (or entry.islands [])
                                                      :next_island_id entry.next_island_id
                                                      :selected_node_keys (or entry.selected_node_keys [])
                                                      :focused_node_key entry.focused_node_key}))))
                (values active-id-result next-map-id maps-list))
            (= (type graph.nodes) :table)
            (do
                ;; Single-wrapped HomeWorld legacy: {:graph {:nodes [...], :edges [...]}}
                (table.insert maps-list {:id "main"
                                           :name "Main"
                                           :nodes (or graph.nodes [])
                                           :edges (explicit-legacy-edges graph.edges)
                                           :islands []
                                           :next_island_id nil
                                           :selected_node_keys (or graph.selected_node_keys [])
                                           :focused_node_key graph.focused_node_key})
                (when (not (= graph.active_map_id nil))
                    (set active-id-result (sanitize-id graph.active_map_id "legacy-graph.active_map_id")))
                (when graph.next_map_id
                    (set next-map-id (ensure-int graph.next_map_id 2)))
                (for [i 2 (length (or graph.maps []))]
                    (local legacy-map (. graph.maps i))
                    (when (= (type legacy-map) :table)
                        (local map-id (sanitize-id legacy-map.id (.. "legacy-graph.maps[" i "].id")))
                        (when map-id
                            (table.insert maps-list {:id map-id
                                                      :name (or legacy-map.name legacy-map.id)
                                                      :nodes (or legacy-map.nodes [])
                                                      :edges (explicit-legacy-edges legacy-map.edges)
                                                      :islands []
                                                      :next_island_id nil
                                                      :selected_node_keys (or legacy-map.selected_node_keys [])
                                                      :focused_node_key legacy-map.focused_node_key}))))
                (values active-id-result next-map-id maps-list))
            (do
                (set active-id-result (sanitize-id (if (not (= payload.active_map_id nil))
                                                        payload.active_map_id
                                                        (not (= graph.active_map_id nil))
                                                        graph.active_map_id
                                                        "main")
                                                    "active_map_id"))
                (set next-map-id (ensure-int (or payload.next_map_id graph.next_map_id) 2))
                (local raw-maps (or payload.maps graph.maps
                                    [{:id "main" :name "Main" :nodes [] :edges [] :selected_node_keys [] :focused_node_key nil}]))
                (each [_ entry (ipairs raw-maps)]
                    (when (= (type entry) :table)
                        (local map-id (sanitize-id entry.id (.. "maps-entry.id=" (tostring entry.id))))
                        (when map-id
                            (table.insert maps-list {:id map-id
                                                      :name (or entry.name entry.id)
                                                      :nodes (or entry.nodes [])
                                                      :edges (or entry.edges [])
                                                      :islands (or entry.islands [])
                                                      :next_island_id entry.next_island_id
                                                      :selected_node_keys (or entry.selected_node_keys [])
                                                      :focused_node_key entry.focused_node_key}))))
                (values active-id-result next-map-id maps-list))))

    (local init-state (or options.state {}))
    (local restored-from-state?
           (or (= (type init-state.maps) :table)
               (not (= init-state.active_map_id nil))
               (= (type init-state.nodes) :table)
               (= (type init-state.graph) :table)))
    (local seed-start-for-legacy-empty?
           (and (= (type init-state.graph) :table)
                (not (= (type init-state.maps) :table))))
    (local (parsed-active-id parsed-next-id parsed-maps) (parse-legacy-state init-state))
    (set active-id parsed-active-id)
    (set next-id parsed-next-id)

    (each [_ entry (ipairs parsed-maps)]
        (assert (not (. entries entry.id))
                (.. "GraphMapManager duplicate map id in state: " entry.id))
        (local (migrated-entry _activity-migrated?) (migrate-map-entry-state entry))
        (set (. entries migrated-entry.id) {:id migrated-entry.id
                                            :name migrated-entry.name
                                             :nodes migrated-entry.nodes
                                             :edges migrated-entry.edges
                                             :islands (or migrated-entry.islands [])
                                             :next_island_id migrated-entry.next_island_id
                                             :selected_node_keys (or migrated-entry.selected_node_keys [])
                                            :focused_node_key migrated-entry.focused_node_key
                                            :restored-from-state? restored-from-state?
                                            :seed-start? seed-start-for-legacy-empty?
                                            :map nil}))

    (when (not (. entries active-id))
        (error (.. "GraphMapManager active_map_id does not reference a map: "
                   (tostring active-id))))

    (local entry-count (length (icollect [_ _ (pairs entries)] true)))
    (when (= entry-count 0)
        (set (. entries "main") {:id "main"
                                  :name "Main"
                                   :nodes []
                                   :edges []
                                   :islands []
                                   :next_island_id nil
                                   :selected_node_keys []
                                  :focused_node_key nil
                                  :restored-from-state? false
                                  :map nil})
        (set active-id "main"))

    ;; Ensure next-id is beyond any existing map-N numeric IDs
    (each [id _ (pairs entries)]
        (local (match-start _match-end _prefix suffix-str) (string.find id "^(map%-)(%d+)$"))
        (when (and match-start suffix-str)
            (local suffix-num (tonumber suffix-str))
            (when suffix-num
                (set next-id (math.max next-id (+ suffix-num 1))))))

    (build-active-map active-id)

    (fn get-active-map [_self]
        (local entry (get-active-entry))
        (when entry
            entry.map))

    (fn active-map-status [_self]
        (local entry (get-active-entry))
        (when entry
            {:id entry.id
             :name entry.name
             :node-count (if entry.map
                             (entry.map:node-count)
                             (length (or entry.nodes [])))
             :edge-count (if entry.map
                             (entry.map:edge-count)
                             (length (or entry.edges [])))}))

    (fn list-maps [_self]
        (local result [])
        (each [_ entry (pairs entries)]
            (table.insert result {:id entry.id
                                  :name entry.name
                                  :node-count (if entry.map
                                                  (entry.map:node-count)
                                                  (length (or entry.nodes [])))
                                  :edge-count (if entry.map
                                                  (entry.map:edge-count)
                                                  (length (or entry.edges [])))}))
        (table.sort result (fn [a b] (< a.id b.id)))
        result)

    (fn switch-map! [self target-id]
        (assert target-id "GraphMapManager.switch-map! requires target-id")
        (assert (. entries target-id)
                (.. "GraphMapManager.switch-map! unknown map: " target-id))
        (when (not (= target-id active-id))
            (local previous-id active-id)
            (local entry (. entries target-id))
            (build-active-map target-id)
            (var previous-dropped? false)
            (local (ok result)
                (pcall
                  (fn []
                    (maps-will-change:emit {:previous-id previous-id
                                            :active-id target-id})
                    (drop-active-map)
                    (set previous-dropped? true)
                    (set active-id target-id)
                    (set self.active-map-id target-id)
                    (set self.active-map-name entry.name)
                    (maps-changed:emit {:previous-id previous-id
                                        :active-id target-id})
                    true)))
            (when (not ok)
                (if previous-dropped?
                    (do
                        (set active-id target-id)
                        (set self.active-map-id target-id)
                        (set self.active-map-name entry.name))
                    (do
                        (when entry.map
                            (local map-to-drop entry.map)
                            (set entry.map nil)
                            (local (drop-ok drop-err) (pcall (fn [] (map-to-drop:drop))))
                            (when (not drop-ok)
                                (error (.. "GraphMapManager failed to drop target map after switch failure: "
                                           (tostring drop-err)
                                           " (switch failure: "
                                           (tostring result)
                                           ")"))))
                        (set active-id previous-id)
                        (set self.active-map-id previous-id)
                        (local previous-entry (. entries previous-id))
                        (set self.active-map-name (and previous-entry previous-entry.name))))
                (error result))
            true))

    (fn create-map! [self id name]
        (assert id "GraphMapManager.create-map! requires :id")
        (assert-safe-map-id id "GraphMapManager.create-map!")
        (local resolved-name (or name id))
        (when (. entries id)
            (error (.. "GraphMapManager.create-map! duplicate id: " id)))
         (set (. entries id) {:id id
                               :name resolved-name
                                :nodes []
                                :edges []
                                :islands []
                                :next_island_id nil
                                :selected_node_keys []
                               :focused_node_key nil
                               :restored-from-state? false
                               :map nil})
        (set next-id (+ next-id 1))
        (set self.next-map-id next-id)
        (maps-changed:emit {:created-id id :active-id active-id})
        id)

    (fn rename-map! [self id name]
        (local entry (. entries id))
        (assert entry (.. "GraphMapManager.rename-map! unknown map: " id))
        (set entry.name name)
        (when entry.map
            (set entry.map.name name))
        (when (= id active-id)
            (set self.active-map-name name))
        (maps-changed:emit {:renamed-id id :name name :active-id active-id})
        true)

    (fn delete-map-metadata [map-id]
        (when (and data-dir map-id)
            (assert-safe-map-id map-id "GraphMapManager.delete-map-metadata")
            (local map-dir (fs.join-path (fs.join-path data-dir "graph" "maps") map-id))
            (when (fs.exists map-dir)
                (fs.remove-all map-dir))))

    (fn delete-map! [self id]
        (assert id "GraphMapManager.delete-map! requires :id")
        (assert (not (= id active-id))
                "GraphMapManager.delete-map! cannot delete active map")
        (local entry (. entries id))
        (assert entry (.. "GraphMapManager.delete-map! unknown map: " id))
        (local maps-count (length (icollect [_ _ (pairs entries)] true)))
        (assert (> maps-count 1)
                "GraphMapManager.delete-map! cannot delete the only map")
        (when entry.map
            (entry.map:drop)
            (set entry.map nil))
        (set (. entries id) nil)
        (delete-map-metadata id)
        (maps-changed:emit {:deleted-id id :active-id active-id})
        true)

    (fn capture-state [_self]
        (local maps-list [])
        (each [_ entry (pairs entries)]
            (when (not (= entry.id active-id))
                (hydrate-inactive-entry-for-capture! entry))
            (local state
                (if (= entry.id active-id)
                    (capture-active-map-state)
                    {:nodes (or entry.nodes [])
                     :edges (or entry.edges [])
                     :islands (or entry.islands [])
                     :next_island_id entry.next_island_id
                     :selected_node_keys (or entry.selected_node_keys [])
                     :focused_node_key entry.focused_node_key}))
            (table.insert maps-list {:id entry.id
                                      :name entry.name
                                      :nodes (or state.nodes [])
                                      :edges (or state.edges [])
                                      :islands (or state.islands [])
                                      :next_island_id state.next_island_id
                                      :selected_node_keys (or state.selected_node_keys [])
                                     :focused_node_key state.focused_node_key}))
        (table.sort maps-list (fn [a b] (< a.id b.id)))
        {:active_map_id active-id
         :next_map_id next-id
         :maps maps-list})

    (fn drop [_self]
        (each [_ entry (pairs entries)]
            (when entry.map
                (entry.map:drop)
                (set entry.map nil)))
        (each [k _ (pairs entries)]
            (set (. entries k) nil))
        (maps-changed:clear)
        (maps-will-change:clear)
        (set active-id nil))

    (local self {:graph shared-graph
                 :data-dir data-dir
                 :maps-changed maps-changed
                 :maps-will-change maps-will-change})

    (set self.active-map-id active-id)
    (local active-entry (. entries active-id))
    (set self.active-map-name (and active-entry active-entry.name))
    (set self.next-map-id next-id)
    (set self.get-active-map get-active-map)
    (set self.active-map-status active-map-status)
    (set self.list-maps list-maps)
    (set self.switch-map! switch-map!)
    (set self.create-map! create-map!)
    (set self.rename-map! rename-map!)
    (set self.delete-map! delete-map!)
    (set self.capture-state capture-state)
    (set self.drop drop)

    self)

{:GraphMapManager GraphMapManager}
