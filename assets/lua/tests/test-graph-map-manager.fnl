(local Graph (require :graph/init))
(local GraphMapManager (require :graph/map-manager))
(local fs (require :fs))
(local json (require :json))
(local JsonUtils (require :json-utils))

(local tests [])

(fn table-has-value? [items value]
    (var found? false)
    (local source (if items items []))
    (each [_ item (ipairs source) &until found?]
        (when (= item value)
            (set found? true)))
    found?)

(fn assert-has-value [items value context]
    (assert (table-has-value? items value)
            (.. context " should include " value)))

(fn assert-lacks-value [items value context]
    (assert (not (table-has-value? items value))
            (.. context " should not include " value)))

(fn register-canonical-activity-loaders [graph]
    (each [_ scheme (ipairs ["activity-background"
                             "activity-skybox"
                             "activity-lights"
                             "activity-terrains"
                             "activity-scene-panels"
                             "activity-light-type"
                             "activity-light"
                             "activity-terrain"
                             "activity-terrain-editor"
                             "activity-terrain-tool"
                             "activity-scene-panel"])]
        (graph:register-key-loader scheme
            (fn [key]
                (Graph.GraphNode {:key key})))))

(fn manager-creates-default-map-from-empty-state []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "start"
        (fn [_key]
            (Graph.GraphNode {:key "start"})))
    (local manager (GraphMapManager.GraphMapManager {:graph graph :state {}}))
    (local maps (manager:list-maps))
    (assert (= (length maps) 1) "Manager should create one default map")
    (assert (= (. maps 1 :id) "main") "Default map id should be 'main'")
    (assert (= (. maps 1 :name) "Main") "Default map name should be 'Main'")
    (local active (manager:get-active-map))
    (assert active "Manager should return active map")
    (assert (= active.id "main") "Active map id should be 'main'")
    (assert (>= (active:node-count) 1) "Default active map should have at least one node")
    (manager:drop)
    (graph:drop))

(fn manager-migrates-legacy-state []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local legacy-state {:graph {:graph {:nodes ["test:a" "test:b"]
                                        :edges [{:source "test:a" :target "test:b"}]}}})
    (local manager (GraphMapManager.GraphMapManager {:graph graph :state legacy-state}))
    (local maps (manager:list-maps))
    (assert (= (length maps) 1) "Manager should create one map from legacy state")
    (local active (manager:get-active-map))
    (assert (active:lookup "test:a") "Active map should contain test:a from legacy state")
    (assert (active:lookup "test:b") "Active map should contain test:b from legacy state")
    (assert (= (active:edge-count) 1) "Active map should have edge from legacy state")
    (manager:drop)
    (graph:drop))

(fn manager-migrates-legacy-activity-category-keys []
    (local graph (Graph {:with-start false}))
    (register-canonical-activity-loaders graph)
    (local legacy-keys ["background:w1" "skybox:w1" "lights:w1" "terrains:w1" "scene-panels:w1"])
    (local state {:active_map_id "main"
                  :maps [{:id "main" :name "Main" :nodes legacy-keys :edges []}]})
    (local manager (GraphMapManager.GraphMapManager {:graph graph :state state}))
    (local captured (manager:capture-state))
    (local main-map (. captured.maps 1))
    (each [_ key (ipairs ["activity-background:w1:sandbox"
                         "activity-skybox:w1:sandbox"
                         "activity-lights:w1:sandbox"
                         "activity-terrains:w1:sandbox"
                         "activity-scene-panels:w1:sandbox"])]
        (assert-has-value main-map.nodes key "Migrated category nodes"))
    (each [_ key (ipairs legacy-keys)]
        (assert-lacks-value main-map.nodes key "Migrated category nodes"))
    (manager:drop)
    (graph:drop))

(fn manager-migrates-legacy-activity-detail-keys []
    (local graph (Graph {:with-start false}))
    (register-canonical-activity-loaders graph)
    (local legacy-keys ["light-type:w1:point"
                        "light:w1:point:p1"
                        "terrain:w1:t1"
                        "terrain-editor:w1:t1"
                        "terrain-tool:w1:t1:resize-terrain"
                        "scene-panel:w1:2"])
    (local state {:active_map_id "main"
                  :maps [{:id "main" :name "Main" :nodes legacy-keys :edges []}]})
    (local manager (GraphMapManager.GraphMapManager {:graph graph :state state}))
    (local captured (manager:capture-state))
    (local main-map (. captured.maps 1))
    (each [_ key (ipairs ["activity-light-type:w1:sandbox:point"
                         "activity-light:w1:sandbox:point:p1"
                         "activity-terrain:w1:sandbox:t1"
                         "activity-terrain-editor:w1:sandbox:t1"
                         "activity-terrain-tool:w1:sandbox:t1:resize-terrain"
                         "activity-scene-panel:w1:sandbox:2"])]
        (assert-has-value main-map.nodes key "Migrated detail nodes"))
    (each [_ key (ipairs legacy-keys)]
        (assert-lacks-value main-map.nodes key "Migrated detail nodes"))
    (manager:drop)
    (graph:drop))

(fn manager-migrates-legacy-activity-edges-and-metadata []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-metadata"
                             (.. "legacy-activity-migration-" (os.time) "-" (do
                                                                               (set temp-counter (+ temp-counter 1))
                                                                               temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local metadata-dir (fs.join-path dir "graph" "maps" "main"))
    (fs.create-dirs metadata-dir)
    (local metadata-path (fs.join-path metadata-dir "metadata.json"))
    (JsonUtils.write-json! metadata-path
                           {:positions {"terrains:w1" [1 2 3]
                                        "terrain:w1:t1" [4 5 6]}
                            :presentations {"terrains:w1" :expanded}
                            :sizes {"terrain:w1:t1" [7 8]}
                            :panels [{:kind "graph-node-view"
                                      :node-key "terrain:w1:t1"
                                      :graph-map-id "main"}]
                            :extra_panels [{:kind "graph-node-cube"
                                            :node-key "terrains:w1"
                                            :graph-map-id "main"}]})
    (local graph (Graph {:with-start false}))
    (register-canonical-activity-loaders graph)
    (local manager (GraphMapManager.GraphMapManager
                     {:graph graph
                      :data-dir dir
                      :state {:active_map_id "main"
                              :maps [{:id "main" :name "Main"
                                      :nodes ["terrains:w1" "terrain:w1:t1"]
                                      :edges [{:source "terrains:w1" :target "terrain:w1:t1"}]}]}}))
    (local captured (manager:capture-state))
    (local main-map (. captured.maps 1))
    (assert-has-value main-map.nodes "activity-terrains:w1:sandbox" "Migrated metadata test nodes")
    (assert-has-value main-map.nodes "activity-terrain:w1:sandbox:t1" "Migrated metadata test nodes")
    (local main-edges (if main-map.edges main-map.edges []))
    (assert (= (length main-edges) 1)
            "Migrated map should keep edge after endpoint migration")
    (assert (= (. main-map.edges 1 :source) "activity-terrains:w1:sandbox")
            "Migrated edge source should use canonical activity key")
    (assert (= (. main-map.edges 1 :target) "activity-terrain:w1:sandbox:t1")
            "Migrated edge target should use canonical activity key")
    (local meta (json.loads (fs.read-file metadata-path)))
    (assert (. meta.positions "activity-terrains:w1:sandbox")
            "Migrated metadata should rewrite category position key")
    (assert (. meta.positions "activity-terrain:w1:sandbox:t1")
            "Migrated metadata should rewrite detail position key")
    (assert (= (. meta.positions "terrains:w1") nil)
            "Migrated metadata should remove legacy category position key")
    (assert (= (. meta.positions "terrain:w1:t1") nil)
            "Migrated metadata should remove legacy detail position key")
    (assert (. meta.presentations "activity-terrains:w1:sandbox")
            "Migrated metadata should rewrite presentation key")
    (assert (. meta.sizes "activity-terrain:w1:sandbox:t1")
            "Migrated metadata should rewrite size key")
    (assert (= (. meta.panels 1 :node-key) "activity-terrain:w1:sandbox:t1")
            "Migrated panel metadata should rewrite node-key")
    (assert (= (. meta.extra_panels 1 :node-key) "activity-terrains:w1:sandbox")
            "Migrated extra panel metadata should rewrite node-key")
    (manager:drop)
    (graph:drop)
    (fs.remove-all dir)
    true)

(fn manager-migration-skips-legacy-derived-link-edges []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-manager"
                             (.. "legacy-derived-" (os.time) "-" (do
                                                                      (set temp-counter (+ temp-counter 1))
                                                                      temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                (local LinkEntityStore (require :entities/link))
                (local link-store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
                (link-store:create-entity {:id "link-a-b"
                                           :source-key "test:a"
                                           :target-key "test:b"})
                (local graph (Graph {:with-start false
                                     :entity-events? false
                                     :link-store link-store}))
                (graph:register-key-loader "test"
                    (fn [key]
                        (Graph.GraphNode {:key key})))
                (local legacy-state {:graph {:graph {:nodes ["test:a" "test:b"]
                                                     :edges [{:source "test:a" :target "test:b"}]}}})
                (local manager (GraphMapManager.GraphMapManager {:graph graph :state legacy-state}))
                (local active (manager:get-active-map))
                (assert (= (active:edge-count) 1)
                        "Hydrated map should display recomputed derived link edge")
                (local captured (manager:capture-state))
                (local main-map (. captured.maps 1))
                (assert (= (length (or main-map.edges [])) 0)
                        "Migrated derived link edge should not persist as explicit map edge")
                (manager:drop)
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn manager-migration-skips-identity-resolved-legacy-derived-link-edges []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-manager"
                             (.. "legacy-derived-identity-" (os.time) "-" (do
                                                                                (set temp-counter (+ temp-counter 1))
                                                                                temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                (local LinkEntityStore (require :entities/link))
                (local IdentityStore (require :entities/identity))
                (local link-store (LinkEntityStore.LinkEntityStore {:base-dir (fs.join-path dir "link")}))
                (local identity-store (IdentityStore.IdentityStore {:base-dir (fs.join-path dir "identity")}))
                (identity-store:create-entity {:id "alias" :target-key "test:a"})
                (link-store:create-entity {:id "identity-link-a-b"
                                           :source-key "identity:alias"
                                           :target-key "test:b"})
                (local graph (Graph {:with-start false
                                     :entity-events? false
                                     :link-store link-store
                                     :identity-store identity-store}))
                (graph:register-key-loader "test"
                    (fn [key]
                        (Graph.GraphNode {:key key})))
                (local legacy-state {:graph {:graph {:nodes ["test:a" "test:b"]
                                                     :edges [{:source "test:a" :target "test:b"}]}}})
                (local manager (GraphMapManager.GraphMapManager {:graph graph :state legacy-state}))
                (local active (manager:get-active-map))
                (assert (= (active:edge-count) 1)
                        "Hydrated map should display recomputed identity-resolved derived link edge")
                (local captured (manager:capture-state))
                (local main-map (. captured.maps 1))
                (assert (= (length (or main-map.edges [])) 0)
                        "Identity-resolved derived link edge should not migrate as explicit map edge")
                (manager:drop)
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn manager-migration-preserves-metadata-legacy-link-overlap-edge []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-manager"
                             (.. "legacy-explicit-link-" (os.time) "-" (do
                                                                             (set temp-counter (+ temp-counter 1))
                                                                             temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                (local LinkEntityStore (require :entities/link))
                (local link-store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
                (link-store:create-entity {:id "link-a-b"
                                           :source-key "test:a"
                                           :target-key "test:b"})
                (local graph (Graph {:with-start false
                                     :entity-events? false
                                     :link-store link-store}))
                (graph:register-key-loader "test"
                    (fn [key]
                        (Graph.GraphNode {:key key})))
                (local legacy-state {:graph {:graph {:nodes ["test:a" "test:b"]
                                                     :edges [{:source "test:a"
                                                              :target "test:b"
                                                              :label "manual edge"}]}}})
                (local manager (GraphMapManager.GraphMapManager {:graph graph :state legacy-state}))
                (local active (manager:get-active-map))
                (assert (= (active:edge-count) 2)
                        "Explicit metadata edge should coexist with recomputed derived link edge")
                (local captured (manager:capture-state))
                (local main-map (. captured.maps 1))
                (assert (= (length (or main-map.edges [])) 1)
                        "Explicit metadata edge should remain persisted")
                (assert (= (. main-map.edges 1 :source) "test:a"))
                (assert (= (. main-map.edges 1 :target) "test:b"))
                (manager:drop)
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn manager-migrates-legacy-empty-state []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "start"
        (fn [_key]
            (Graph.GraphNode {:key "start"})))
    (local legacy-state {:graph {:graph {:nodes [] :edges []}}})
    (local manager (GraphMapManager.GraphMapManager {:graph graph :state legacy-state}))
    (local active (manager:get-active-map))
    (assert active "Manager should create active map from legacy empty state")
    (assert (= (active:node-count) 1) "Empty legacy state should seed start node")
    (manager:drop)
    (graph:drop))

(fn manager-migrates-home-world-legacy-shape []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    ;; HomeWorld passes world.state.graph = {:graph {:nodes [...] :edges [...]}}
    (local homeworld-shape {:graph {:nodes ["test:a" "test:b"]
                                    :edges [{:source "test:a" :target "test:b"}]}})
    (local manager (GraphMapManager.GraphMapManager {:graph graph :state homeworld-shape}))
    (local maps (manager:list-maps))
    (assert (= (length maps) 1) "Manager should create one map from homeworld legacy shape")
    (local active (manager:get-active-map))
    (assert (active:lookup "test:a") "Active map should contain test:a from homeworld legacy shape")
    (assert (active:lookup "test:b") "Active map should contain test:b from homeworld legacy shape")
    (assert (= (active:edge-count) 1) "Active map should have edge from homeworld legacy shape")
    (manager:drop)
    (graph:drop))

(fn manager-homeworld-legacy-carries-additional-maps []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local shape {:graph {:nodes ["test:a"]
                          :edges []
                          :next_map_id 5
                          :maps [false
                                 {:id "extra" :name "Extra" :nodes [] :edges []}]}})
    (local manager (GraphMapManager.GraphMapManager {:graph graph :state shape}))
    (local maps (manager:list-maps))
    (assert (= (length maps) 2) "Homeworld legacy with graph.maps should carry additional maps")
    (local ids (icollect [_ m (ipairs maps)] m.id))
    (assert (or (= (. ids 1) "main") (= (. ids 2) "main"))
            "Main map should be present")
    (assert (or (= (. ids 1) "extra") (= (. ids 2) "extra"))
            "Extra map should be carried")
    (assert (>= manager.next-map-id 5) "next-map-id should be at least parsed next_map_id")
    (manager:drop)
    (graph:drop))

(fn manager-loads-migrated-state-with-default-graph []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    ;; After merge-state-defaults, persisted state has both default .graph
    ;; (from base-default-state) and real .maps/.active_map_id from migration.
    (local merged-shape {:active_map_id "main"
                           :next_map_id 2
                           :maps [{:id "main" :name "Main"
                                   :nodes ["test:a" "test:b"]
                                   :edges [{:source "test:a" :target "test:b"}]}]
                           :graph {:nodes [] :edges []}})
    (local manager (GraphMapManager.GraphMapManager {:graph graph :state merged-shape}))
    (local active (manager:get-active-map))
    (assert (active:lookup "test:a") "Active map should contain test:a from merged-default shape")
    (assert (active:lookup "test:b") "Active map should contain test:b from merged-default shape")
    (assert (= (active:edge-count) 1) "Active map should have edge from merged-default shape")
    (manager:drop)
    (graph:drop))

(fn manager-captures-state-in-target-shape []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local state {:active_map_id "main"
                  :next_map_id 2
                  :maps [{:id "main" :name "Main" :nodes ["test:a"] :edges []}]})
    (local manager (GraphMapManager.GraphMapManager {:graph graph :state state}))
    (local captured (manager:capture-state))
    (assert (= (type captured.active_map_id) :string) "Captured state should have active_map_id")
    (assert (= (type captured.maps) :table) "Captured state should have maps")
    (assert (>= (length captured.maps) 1) "Captured state should have at least one map")
    (local main-map (. captured.maps 1))
    (assert (= main-map.id "main") "Main map should have id")
    (assert (= main-map.name "Main") "Main map should have name")
    (assert (= (type main-map.nodes) :table) "Main map should have nodes")
    (assert (= (type main-map.edges) :table) "Main map should have edges")
    (manager:drop)
    (graph:drop))

(fn manager-normalizes-integral-float-next-map-id []
    (local graph (Graph {:with-start false}))
    (local restored-state (json.loads "{\"active_map_id\":\"main\",\"next_map_id\":2.0,\"maps\":[{\"id\":\"main\",\"name\":\"Main\",\"nodes\":[],\"edges\":[]}]}"))
    (local manager
        (GraphMapManager.GraphMapManager
            {:graph graph
             :state restored-state}))
    (assert (= manager.next-map-id 2)
            "Restored integral float next_map_id should normalize to 2")
    (assert (= (tostring manager.next-map-id) "2")
            "Normalized next-map-id should stringify without .0")
    (manager:drop)
    (graph:drop))

(fn manager-captures-normalized-next-map-id []
    (local graph (Graph {:with-start false}))
    (local restored-state (json.loads "{\"active_map_id\":\"main\",\"next_map_id\":2.0,\"maps\":[{\"id\":\"main\",\"name\":\"Main\",\"nodes\":[],\"edges\":[]}]}"))
    (local manager
        (GraphMapManager.GraphMapManager
            {:graph graph
             :state restored-state}))
    (local captured (manager:capture-state))
    (assert (= captured.next_map_id 2)
            "Captured next_map_id should remain integer-like")
    (assert (= (tostring captured.next_map_id) "2")
            "Captured next_map_id should stringify without .0")
    (manager:drop)
    (graph:drop))

(fn manager-creates-map []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (local id (manager:create-map! "my-map" "My Map"))
    (assert (= id "my-map") "create-map! should return the map id")
    (local maps (manager:list-maps))
    (assert (= (length maps) 2) "Manager should have two maps after create")
    (var entry nil)
    (each [_ m (ipairs maps)]
        (when (= m.id "my-map")
            (set entry m)))
    (assert entry "Created map should appear in list")
    (assert (= entry.name "My Map") "Created map should have correct name")
    (local active (manager:get-active-map))
    (assert (= (. active :id) "main") "Active map should still be main after create")
    (manager:drop)
    (graph:drop))

(fn manager-renames-map []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (manager:rename-map! "main" "Start Map")
    (local maps (manager:list-maps))
    (var entry nil)
    (each [_ m (ipairs maps)]
        (when (= m.id "main")
            (set entry m)))
    (assert entry "Renamed map should still exist")
    (assert (= entry.name "Start Map") "Map should have new name")
    (assert (= (. (manager:get-active-map) :name) "Start Map")
            "Mounted active GraphMap should have new name")
    (manager:drop)
    (graph:drop))

(fn manager-rename-unknown-map-errors []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (local (ok err) (pcall (fn [] (manager:rename-map! "nonexistent" "X"))))
    (assert (not ok) "Rename of unknown map should error")
    (manager:drop)
    (graph:drop))

(fn manager-switches-map []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (manager:create-map! "project" "Project")
    (assert (= (. (manager:get-active-map) :id) "main") "Active should be main before switch")
    (manager:switch-map! "project")
    (assert (= (. (manager:get-active-map) :id) "project") "Active should be project after switch")
    (manager:drop)
    (graph:drop))

(fn manager-capture-during-switch-keeps-target-map-mounted []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (manager:create-map! "project" "Project")
    (var captured-during-switch? false)
    (manager.maps-will-change:connect
      (fn [_payload]
        (set captured-during-switch? true)
        (local captured (manager:capture-state))
        (assert (= captured.active_map_id "main")
                "Capture during maps-will-change should still report previous active id")))
    (manager:switch-map! "project")
    (assert captured-during-switch?
            "Switch should emit maps-will-change before activation")
    (local active (manager:get-active-map))
    (assert active "Target map should stay mounted after capture during switch")
    (assert (= active.id "project") "Active map should be project after switch")
    (manager:drop)
    (graph:drop))

(fn manager-switch-unknown-map-errors []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (local (ok err) (pcall (fn [] (manager:switch-map! "nonexistent"))))
    (assert (not ok) "Switch to unknown map should error")
    (manager:drop)
    (graph:drop))

(fn manager-switch-build-failure-keeps-previous-map-active []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager
                     {:graph graph
                      :state {:active_map_id "main"
                              :maps [{:id "main" :name "Main" :nodes [] :edges []}
                                     {:id "bad" :name "Bad" :nodes [42] :edges []}]}}))
    (local previous (manager:get-active-map))
    (local (ok err) (pcall (fn [] (manager:switch-map! "bad"))))
    (assert (not ok) "Switch to map with invalid persisted state should fail")
    (assert (= manager.active-map-id "main") "Failed switch should keep previous active id")
    (assert (= (manager:get-active-map) previous) "Failed switch should keep previous map mounted")
    (manager:drop)
    (graph:drop))

(fn manager-deletes-map []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (manager:create-map! "temp" "Temp")
    (assert (= (length (manager:list-maps)) 2) "Should have 2 maps before delete")
    (manager:delete-map! "temp")
    (assert (= (length (manager:list-maps)) 1) "Should have 1 map after delete")
    (manager:drop)
    (graph:drop))

(fn manager-cannot-delete-active-map []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (local (ok err) (pcall (fn [] (manager:delete-map! "main"))))
    (assert (not ok) "Delete of active map should error")
    (manager:drop)
    (graph:drop))

(fn manager-cannot-delete-only-map []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (manager:switch-map! "main")
    (local (ok err) (pcall (fn [] (manager:delete-map! "other"))))
    (assert (not ok) "Delete of unknown map should error")
    (local (ok2 err2) (pcall (fn [] (manager:delete-map! "main"))))
    (assert (not ok2) "Delete of active map should error")
    (manager:drop)
    (graph:drop))

(fn manager-prunes-unresolvable-keys-on-hydration []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (if (= key "test:a")
                (Graph.GraphNode {:key key})
                nil)))
    (local state {:active_map_id "main"
                  :next_map_id 2
                  :maps [{:id "main" :name "Main"
                          :nodes ["test:a" "test:missing"]
                          :edges [{:source "test:a" :target "test:missing"}]}]})
    (local manager (GraphMapManager.GraphMapManager {:graph graph :state state}))
    (local captured (manager:capture-state))
    (local main-map (. captured.maps 1))
    (assert (= (length main-map.nodes) 1)
            "Captured active map should prune unresolvable node key after hydration")
    (assert (= (length main-map.edges) 0)
            "Captured active map should prune edge with unresolvable target after hydration")
    (manager:drop)
    (graph:drop))

(fn manager-hydration-prunes-edges-without-resurrecting-on-recapture []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (if (or (= key "test:a") (= key "test:b"))
                (Graph.GraphNode {:key key})
                nil)))
    (local state {:active_map_id "main"
                  :next_map_id 2
                  :maps [{:id "main" :name "Main"
                          :nodes ["test:a" "test:b"]
                          :edges [{:source "test:a" :target "test:missing"}]}]})
    (local manager (GraphMapManager.GraphMapManager {:graph graph :state state}))
    (local active (manager:get-active-map))
    (assert (= (active:node-count) 2)
            "Both nodes should resolve")
    (assert (= (active:edge-count) 0)
            "Unresolvable edge should be pruned")
    (local captured (manager:capture-state))
    (local main-map (. captured.maps 1))
    (assert (= (length (or main-map.edges [])) 0)
            "Captured state should not include pruned edge even when only edges were pruned")
    (manager:drop)
    (graph:drop))

(fn manager-hydration-does-not-resurrect-loadable-edge-endpoints []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (if (or (= key "test:a") (= key "test:b"))
                (Graph.GraphNode {:key key})
                nil)))
    (local state {:active_map_id "main"
                  :next_map_id 2
                  :maps [{:id "main" :name "Main"
                          :nodes ["test:a"]
                          :edges [{:source "test:a" :target "test:b"}]}]})
    (local manager (GraphMapManager.GraphMapManager {:graph graph :state state}))
    (local active (manager:get-active-map))
    (assert (active:lookup "test:a") "Persisted node should load")
    (assert (not (active:lookup "test:b")) "Loadable edge endpoint outside map membership should not load")
    (assert (= (active:edge-count) 0) "Edge to node outside membership should be pruned")
    (local captured (manager:capture-state))
    (local main-map (. captured.maps 1))
    (assert (= (length main-map.nodes) 1) "Capture should not persist resurrected endpoint")
    (assert (= (. main-map.nodes 1) "test:a"))
    (assert (= (length main-map.edges) 0) "Capture should not persist pruned edge")
    (manager:drop)
    (graph:drop))

(fn manager-preserves-unresolved-keys-in-capture []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (if (= key "test:a")
                (Graph.GraphNode {:key key})
                nil)))
    (local state {:active_map_id "main"
                  :next_map_id 2
                  :maps [{:id "main" :name "Main"
                          :nodes ["test:a" "test:missing"]
                          :edges [{:source "test:a" :target "test:missing"}]}]})
    (local manager (GraphMapManager.GraphMapManager {:graph graph :state state}))
    (local captured (manager:capture-state))
    (local main-map (. captured.maps 1))
    (assert (= (length main-map.nodes) 1)
            "Captured active map should prune unresolvable node key")
    (assert (= (length main-map.edges) 0)
            "Captured active map should prune edge with unresolvable target")
    (manager:drop)
    (graph:drop))

(fn manager-multiple-maps []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (manager:create-map! "alpha" "Alpha")
    (manager:create-map! "beta" "Beta")
    (local maps (manager:list-maps))
    (assert (= (length maps) 3) "Should have 3 maps")
    (local captured (manager:capture-state))
    (assert (= (length captured.maps) 3) "Captured state should have 3 maps")
    (manager:drop)
    (graph:drop))

(fn manager-maps-share-graph []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local manager (GraphMapManager.GraphMapManager {:graph graph
                                                      :state {:maps [{:id "main" :name "Main" :nodes [] :edges []}]}}))
    (manager:create-map! "extra" "Extra")
    (manager:switch-map! "extra")
    (local extra-map (manager:get-active-map))
    (extra-map:load-by-key "test:shared")
    (manager:switch-map! "main")
    (local main-map (manager:get-active-map))
    (assert (not (main-map:lookup "test:shared"))
            "Nodes from one map should not leak into another")
    (manager:drop)
    (graph:drop))

(fn manager-drop-cleans-all-maps []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (manager:create-map! "temp" "Temp")
    (manager:drop)
    (assert (= (# (manager:list-maps)) 0) "Maps list should be empty after drop")
    (graph:drop))

(fn manager-delete-map-removes-metadata []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-metadata"
                             (.. "del-meta-" (os.time) "-" (do
                                                               (set temp-counter (+ temp-counter 1))
                                                               temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                (local graph (Graph {:with-start false}))
                (local manager (GraphMapManager.GraphMapManager {:graph graph :data-dir dir}))
                (manager:create-map! "target" "Target")
                (local metadata-dir (fs.join-path dir "graph" "maps" "target"))
                (fs.create-dirs metadata-dir)
                (local metadata-path (fs.join-path metadata-dir "metadata.json"))
                (fs.write-file metadata-path "{\"positions\":{}}")
                (assert (fs.exists metadata-dir) "Metadata dir should exist before delete")
                (manager:switch-map! "target")
                (manager:switch-map! "main")
                (manager:delete-map! "target")
                (assert (not (fs.exists metadata-dir))
                        "Metadata dir should be removed after delete")
                (manager:drop)
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn manager-prunes-panel-metadata-on-hydration []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-metadata"
                             (.. "prune-panel-" (os.time) "-" (do
                                                                  (set temp-counter (+ temp-counter 1))
                                                                  temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                ;; Write metadata BEFORE constructing manager so prune-hydrated-map! finds it
                (local metadata-dir (fs.join-path dir "graph" "maps" "main"))
                (fs.create-dirs metadata-dir)
                (local metadata-path (fs.join-path metadata-dir "metadata.json"))
                (local panels [{:node-key "test:valid"
                                :panel {:layer "float" :position [10 20 0]}}
                               {:node-key "test:dead"
                                :panel {:layer "tiles" :align-x :end}}])
                (JsonUtils.write-json! metadata-path {:positions {} :panels panels})
                (local graph (Graph {:with-start false}))
                (graph:register-key-loader "test"
                    (fn [key]
                        (if (= key "test:valid")
                            (Graph.GraphNode {:key key})
                            nil)))
                (local manager (GraphMapManager.GraphMapManager {:graph graph :data-dir dir
                                                                  :state {:maps [{:id "main" :name "Main"
                                                                                   :nodes ["test:valid" "test:dead"]
                                                                                   :edges []}]}}))
                ;; Check that only "main" has 1 node after hydration
                (local captured (manager:capture-state))
                (local main-map (. captured.maps 1))
                (assert (= (length main-map.nodes) 1)
                        "Should have exactly one node after pruning dead key")
                ;; Verify metadata panels for dead key were pruned
                (local (read-ok meta-content) (pcall fs.read-file metadata-path))
                (assert read-ok "Should be able to read updated metadata")
                (local meta (json.loads meta-content))
                (assert (= (length (or meta.panels [])) 1)
                        "Metadata should have exactly one panel after pruning dead key")
                (assert (= (. (. meta.panels 1) :node-key) "test:valid")
                        "Remaining panel should be for the valid node key")
                (manager:drop)
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn manager-prunes-extra-panel-metadata-on-hydration []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-metadata"
                             (.. "prune-extra-panel-" (os.time) "-" (do
                                                                          (set temp-counter (+ temp-counter 1))
                                                                          temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                (local metadata-dir (fs.join-path dir "graph" "maps" "main"))
                (fs.create-dirs metadata-dir)
                (local metadata-path (fs.join-path metadata-dir "metadata.json"))
                (JsonUtils.write-json! metadata-path
                                       {:positions {}
                                        :extra_panels [{:kind "llm-conversation-messages-view-dialog"
                                                        :node-key "test:valid"
                                                        :graph-map-id "main"}
                                                       {:kind "graph-node-cube"
                                                        :node-key "test:dead"
                                                        :graph-map-id "main"}]})
                (local graph (Graph {:with-start false}))
                (graph:register-key-loader "test"
                    (fn [key]
                        (if (= key "test:valid")
                            (Graph.GraphNode {:key key})
                            nil)))
                (local manager (GraphMapManager.GraphMapManager {:graph graph :data-dir dir
                                                                  :state {:maps [{:id "main" :name "Main"
                                                                                   :nodes ["test:valid" "test:dead"]
                                                                                   :edges []}]}}))
                (local meta (json.loads (fs.read-file metadata-path)))
                (assert (= (length (or meta.extra_panels [])) 1)
                        "Metadata should have exactly one extra panel after pruning dead key")
                (assert (= (. (. meta.extra_panels 1) :node-key) "test:valid")
                        "Remaining extra panel should be for the valid node key")
                (manager:drop)
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn manager-prunes-inactive-panel-metadata-on-capture []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-metadata"
                             (.. "prune-inactive-panel-" (os.time) "-" (do
                                                                             (set temp-counter (+ temp-counter 1))
                                                                             temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                (local metadata-dir (fs.join-path dir "graph" "maps" "beta"))
                (fs.create-dirs metadata-dir)
                (local metadata-path (fs.join-path metadata-dir "metadata.json"))
                (JsonUtils.write-json! metadata-path
                                       {:positions {"test:dead" [1 2 3]
                                                    "test:valid" [4 5 6]}
                                        :panels [{:kind "graph-node-view"
                                                  :node-key "test:dead"
                                                  :graph-map-id "beta"}
                                                 {:kind "graph-node-view"
                                                  :node-key "test:valid"
                                                  :graph-map-id "beta"}]
                                        :extra_panels [{:kind "graph-node-cube"
                                                        :node-key "test:dead"
                                                        :graph-map-id "beta"}]})
                (local graph (Graph {:with-start false}))
                (graph:register-key-loader "test"
                    (fn [key]
                        (if (= key "test:valid")
                            (Graph.GraphNode {:key key})
                            nil)))
                (local manager (GraphMapManager.GraphMapManager
                                 {:graph graph
                                  :data-dir dir
                                  :state {:active_map_id "main"
                                          :maps [{:id "main" :name "Main" :nodes [] :edges []}
                                                 {:id "beta" :name "Beta"
                                                  :nodes ["test:valid" "test:dead"]
                                                  :edges [{:source "test:valid" :target "test:dead"}]}]}}))
                (local captured (manager:capture-state))
                (var beta-map nil)
                (each [_ m (ipairs captured.maps) &until beta-map]
                    (when (= m.id "beta")
                        (set beta-map m)))
                (assert beta-map "Captured maps should include inactive beta map")
                (assert (= (length beta-map.nodes) 1)
                        "Inactive map capture should prune unresolvable node key")
                (assert (= (. beta-map.nodes 1) "test:valid")
                        "Inactive map capture should keep resolvable node key")
                (assert (= (length (or beta-map.edges [])) 0)
                        "Inactive map capture should prune edges with unresolved endpoints")
                (local meta (json.loads (fs.read-file metadata-path)))
                (assert (= (. meta.positions "test:dead") nil)
                        "Inactive map metadata positions should prune dead key")
                (assert (= (length (or meta.panels [])) 1)
                        "Inactive map metadata panels should prune dead key")
                (assert (= (. (. meta.panels 1) :node-key) "test:valid")
                        "Inactive map metadata should keep valid panel")
                (assert (= (length (or meta.extra_panels [])) 0)
                        "Inactive map extra panels should prune dead key")
                (manager:drop)
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn manager-prunes-orphan-and-wrong-map-metadata []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-metadata"
                             (.. "orphan-wrong-map-" (os.time) "-" (do
                                                                       (set temp-counter (+ temp-counter 1))
                                                                       temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                (local metadata-dir (fs.join-path dir "graph" "maps" "main"))
                (fs.create-dirs metadata-dir)
                (local metadata-path (fs.join-path metadata-dir "metadata.json"))
                (JsonUtils.write-json! metadata-path
                                       {:positions {"test:valid" [1 2 3]
                                                    "test:orphan" [4 5 6]}
                                        :presentations {"test:orphan" :expanded}
                                        :sizes {"test:orphan" [7 8]}
                                        :panels [{:kind "graph-node-view"
                                                  :node-key "test:valid"
                                                  :graph-map-id "main"}
                                                 {:kind "graph-node-view"
                                                  :node-key "test:orphan"
                                                  :graph-map-id "main"}
                                                 {:kind "graph-node-view"
                                                  :node-key "test:valid"
                                                  :graph-map-id "other"}]
                                        :extra_panels [{:kind "graph-node-cube"
                                                        :node-key "test:orphan"
                                                        :graph-map-id "main"}]})
                (local graph (Graph {:with-start false}))
                (graph:register-key-loader "test"
                    (fn [key]
                        (if (= key "test:valid")
                            (Graph.GraphNode {:key key})
                            nil)))
                (local manager (GraphMapManager.GraphMapManager
                                 {:graph graph
                                  :data-dir dir
                                  :state {:active_map_id "main"
                                          :maps [{:id "main" :name "Main"
                                                  :nodes ["test:valid"]
                                                  :edges []}]}}))
                (local meta (json.loads (fs.read-file metadata-path)))
                (assert (. meta.positions "test:valid"))
                (assert (= (. meta.positions "test:orphan") nil) "Orphan position should be pruned")
                (assert (= (. meta.presentations "test:orphan") nil) "Orphan presentation should be pruned")
                (assert (= (. meta.sizes "test:orphan") nil) "Orphan size should be pruned")
                (assert (= (length meta.panels) 1) "Only valid same-map panel should remain")
                (assert (= (. meta.panels 1 :node-key) "test:valid"))
                (assert (= (length meta.extra_panels) 0) "Orphan extra panel should be pruned")
                (manager:drop)
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn manager-reprunes-inactive-map-on-each-capture []
    (local graph (Graph {:with-start false}))
    (var allow-dead? true)
    (graph:register-key-loader "test"
        (fn [key]
            (if (or (= key "test:valid")
                    (and allow-dead? (= key "test:dead")))
                (Graph.GraphNode {:key key})
                nil)))
    (local manager (GraphMapManager.GraphMapManager
                     {:graph graph
                      :state {:active_map_id "main"
                              :maps [{:id "main" :name "Main" :nodes [] :edges []}
                                     {:id "beta" :name "Beta"
                                      :nodes ["test:valid" "test:dead"]
                                      :edges []}]}}))
    (local first (manager:capture-state))
    (var first-beta nil)
    (each [_ m (ipairs first.maps) &until first-beta]
        (when (= m.id "beta")
            (set first-beta m)))
    (assert (= (length first-beta.nodes) 2)
            "First inactive capture should keep keys that still resolve")
    (set allow-dead? false)
    (local second (manager:capture-state))
    (var second-beta nil)
    (each [_ m (ipairs second.maps) &until second-beta]
        (when (= m.id "beta")
            (set second-beta m)))
    (assert (= (length second-beta.nodes) 1)
            "Second inactive capture should re-prune keys that stopped resolving")
    (assert (= (. second-beta.nodes 1) "test:valid"))
    (manager:drop)
    (graph:drop))

(fn manager-cleans-inactive-map-after-prune-failure []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-metadata"
                             (.. "inactive-prune-failure-" (os.time) "-" (do
                                                                               (set temp-counter (+ temp-counter 1))
                                                                               temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                (local metadata-dir (fs.join-path dir "graph" "maps" "beta"))
                (fs.create-dirs metadata-dir)
                (local metadata-path (fs.join-path metadata-dir "metadata.json"))
                (fs.write-file metadata-path "{not-json")
                (local graph (Graph {:with-start false}))
                (graph:register-key-loader "test"
                    (fn [key]
                        (if (= key "test:valid")
                            (Graph.GraphNode {:key key})
                            nil)))
                (local manager (GraphMapManager.GraphMapManager
                                 {:graph graph
                                  :data-dir dir
                                  :state {:active_map_id "main"
                                          :maps [{:id "main" :name "Main" :nodes [] :edges []}
                                                 {:id "beta" :name "Beta"
                                                  :nodes ["test:valid" "test:dead"]
                                                  :edges []}]}}))
                (local (capture-ok capture-err)
                    (pcall (fn [] (manager:capture-state))))
                (assert (not capture-ok)
                        "Inactive corrupt metadata should fail capture loudly")
                (assert (string.find (tostring capture-err) "failed to parse" 1 true)
                        "Inactive capture error should identify metadata parse failure")
                (JsonUtils.write-json! metadata-path {:positions {} :panels [] :extra_panels []})
                (local captured (manager:capture-state))
                (var beta-map nil)
                (each [_ m (ipairs captured.maps) &until beta-map]
                    (when (= m.id "beta")
                        (set beta-map m)))
                (assert (= (length beta-map.nodes) 1)
                        "Manager should recover after failed inactive prune cleanup")
                (assert (= (. beta-map.nodes 1) "test:valid"))
                (manager:drop)
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn manager-drops-map-when-restore-fails []
    (local signal-counts {:connected 0 :disconnected 0})
    (fn counting-signal []
        {:connect (fn [_self handler]
                    (set signal-counts.connected (+ signal-counts.connected 1))
                    handler)
         :disconnect (fn [_self _handler _not-connected-ok?]
                       (set signal-counts.disconnected (+ signal-counts.disconnected 1)) nil)})
    (local graph {:entity-events? true
                  :node-removed (counting-signal)
                  :node-replaced (counting-signal)
                  :node-morphed (counting-signal)
                  :edge-added (counting-signal)
                  :edge-removed (counting-signal)
                  :has-key-loader-for-key (fn [_self _key] false)
                  :create-node-by-key (fn [_self _key] nil)})
    (local (ok err)
        (pcall
          (fn []
            (GraphMapManager.GraphMapManager
              {:graph graph
               :state {:active_map_id "main"
                       :maps [{:id "main" :name "Main" :nodes [42] :edges []}]}}))))
    (assert (not ok) "Manager should fail on invalid map restore state")
    (assert (string.find (tostring err) "node keys must be strings" 1 true)
            "Manager restore failure should preserve restore-state error")
    (assert (= signal-counts.connected signal-counts.disconnected)
            "Manager should drop partially constructed graph map after restore failure"))

(fn manager-drops-active-map-when-prune-fails []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-metadata"
                             (.. "active-prune-failure-" (os.time) "-" (do
                                                                               (set temp-counter (+ temp-counter 1))
                                                                               temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
          (fn []
            (local metadata-dir (fs.join-path dir "graph" "maps" "main"))
            (fs.create-dirs metadata-dir)
            (fs.write-file (fs.join-path metadata-dir "metadata.json") "{not-json")
            (local signal-counts {:connected 0 :disconnected 0})
            (fn counting-signal []
                {:connect (fn [_self handler]
                            (set signal-counts.connected (+ signal-counts.connected 1))
                            handler)
                 :disconnect (fn [_self _handler _not-connected-ok?]
                               (set signal-counts.disconnected (+ signal-counts.disconnected 1)) nil)})
            (local graph {:entity-events? true
                          :node-removed (counting-signal)
                          :node-replaced (counting-signal)
                          :node-morphed (counting-signal)
                          :edge-added (counting-signal)
                          :edge-removed (counting-signal)
                          :has-key-loader-for-key (fn [_self _key] false)
                          :create-node-by-key (fn [_self _key] nil)})
            (local (manager-ok manager-err)
                (pcall
                  (fn []
                    (GraphMapManager.GraphMapManager
                      {:graph graph
                       :data-dir dir
                       :state {:active_map_id "main"
                               :maps [{:id "main" :name "Main" :nodes ["test:dead"] :edges []}]}}))))
            (assert (not manager-ok)
                    "Manager should fail when active metadata prune fails")
            (assert (string.find (tostring manager-err) "failed to parse" 1 true)
                    "Manager should preserve active prune failure error")
            (assert (= signal-counts.connected signal-counts.disconnected)
                    "Manager should drop active graph map after prune failure"))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn manager-errors-on-corrupt-metadata-during-hydration-prune []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-metadata"
                             (.. "corrupt-meta-" (os.time) "-" (do
                                                                    (set temp-counter (+ temp-counter 1))
                                                                    temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                (local metadata-dir (fs.join-path dir "graph" "maps" "main"))
                (fs.create-dirs metadata-dir)
                (local metadata-path (fs.join-path metadata-dir "metadata.json"))
                (fs.write-file metadata-path "{not-json")
                (local graph (Graph {:with-start false}))
                (graph:register-key-loader "test"
                    (fn [key]
                        (if (= key "test:valid")
                            (Graph.GraphNode {:key key})
                            nil)))
                (local (manager-ok manager-err)
                    (pcall (fn []
                             (GraphMapManager.GraphMapManager
                               {:graph graph
                                :data-dir dir
                                :state {:maps [{:id "main" :name "Main"
                                                :nodes ["test:valid" "test:dead"]
                                                :edges []}]}}))))
                (assert (not manager-ok)
                        "Manager should fail on corrupt metadata while pruning")
                (assert (string.find (tostring manager-err) "failed to parse" 1 true)
                        "Manager error should identify metadata parse failure")
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn manager-preserves-new-format-empty-map []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "start"
        (fn [_key]
            (Graph.GraphNode {:key "start"})))
    (local manager (GraphMapManager.GraphMapManager
                     {:graph graph
                      :state {:active_map_id "main"
                              :maps [{:id "main" :name "Main" :nodes [] :edges []}]}}))
    (local active (manager:get-active-map))
    (assert (= (active:node-count) 0)
            "New-format empty map should remain empty")
    (manager:drop)
    (graph:drop))

(fn manager-rejects-unsafe-map-ids-in-state []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local state-with-bad-active {:active_map_id "../escape"
                                  :next_map_id 2
                                  :maps [{:id "main" :name "Main" :nodes [] :edges []}]})
    (local (ok1 err1) (pcall (fn [] (GraphMapManager.GraphMapManager {:graph graph :state state-with-bad-active}))))
    (assert (not ok1) "Manager should reject unsafe active_map_id from state")
    (local state-with-bad-map {:active_map_id "main"
                                :next_map_id 2
                                :maps [{:id "main" :name "Main" :nodes [] :edges []}
                                       {:id "../traverse" :name "Bad" :nodes [] :edges []}]})
    (local (ok2 err2) (pcall (fn [] (GraphMapManager.GraphMapManager {:graph graph :state state-with-bad-map}))))
    (assert (not ok2) "Manager should reject unsafe map id from state maps list")
    (local legacy-state-with-bad {:graph {:graph {:nodes ["test:a"] :edges []}
                                          :active_map_id "../escape"
                                          :maps []}})
    (local (ok4 err4) (pcall (fn [] (GraphMapManager.GraphMapManager {:graph graph :state legacy-state-with-bad}))))
    (assert (not ok4) "Manager should reject unsafe active_map_id from legacy state")
    (local state-with-numeric-id {:active_map_id 42
                                    :next_map_id 2
                                    :maps [{:id "main" :name "Main" :nodes [] :edges []}]})
    (local (ok5 err5) (pcall (fn [] (GraphMapManager.GraphMapManager {:graph graph :state state-with-numeric-id}))))
    (assert (not ok5) "Manager should reject numeric active_map_id")
    (local state-with-false-id {:active_map_id false
                                  :next_map_id 2
                                  :maps [{:id "main" :name "Main" :nodes [] :edges []}]})
    (local (ok6 err6) (pcall (fn [] (GraphMapManager.GraphMapManager {:graph graph :state state-with-false-id}))))
    (assert (not ok6) "Manager should reject false active_map_id")
    (local legacy-with-false {:graph {:graph {:nodes ["test:a"] :edges []}
                                        :active_map_id false
                                        :maps []}})
    (local (ok7 err7) (pcall (fn [] (GraphMapManager.GraphMapManager {:graph graph :state legacy-with-false}))))
    (assert (not ok7) "Manager should reject false active_map_id in legacy state")
    (local homeworld-with-bad-active {:graph {:nodes ["test:a"] :edges []
                                              :active_map_id "../escape"
                                              :maps []}})
    (local (ok8 err8) (pcall (fn [] (GraphMapManager.GraphMapManager {:graph graph :state homeworld-with-bad-active}))))
    (assert (not ok8) "Manager should reject unsafe active_map_id in homeworld legacy shape")
    (graph:drop))

(fn manager-rejects-active-id-missing-from-maps []
    (local graph (Graph {:with-start false}))
    (local state {:active_map_id "missing"
                  :next_map_id 2
                  :maps [{:id "main" :name "Main" :nodes [] :edges []}]})
    (local (ok err) (pcall (fn []
                             (GraphMapManager.GraphMapManager {:graph graph :state state}))))
    (assert (not ok) "Manager should reject active_map_id that is absent from maps")
    (assert (string.find (tostring err) "active_map_id does not reference a map" 1 true)
            "Manager should report missing active_map_id target")
    (graph:drop))

(fn manager-rejects-duplicate-map-ids []
    (local graph (Graph {:with-start false}))
    (local state {:active_map_id "main"
                  :next_map_id 2
                  :maps [{:id "main" :name "Main" :nodes [] :edges []}
                         {:id "main" :name "Duplicate" :nodes [] :edges []}]})
    (local (ok err) (pcall (fn []
                             (GraphMapManager.GraphMapManager {:graph graph :state state}))))
    (assert (not ok) "Manager should reject duplicate map ids")
    (assert (string.find (tostring err) "duplicate map id" 1 true)
            "Manager should report duplicate map id")
    (graph:drop))

(table.insert tests {:name "GraphMapManager rejects unsafe map ids in parsed state" :fn manager-rejects-unsafe-map-ids-in-state})
(table.insert tests {:name "GraphMapManager rejects active_map_id missing from maps" :fn manager-rejects-active-id-missing-from-maps})
(table.insert tests {:name "GraphMapManager rejects duplicate map ids" :fn manager-rejects-duplicate-map-ids})
(table.insert tests {:name "GraphMapManager creates default map from empty state" :fn manager-creates-default-map-from-empty-state})
(table.insert tests {:name "GraphMapManager migrates legacy state" :fn manager-migrates-legacy-state})
(table.insert tests {:name "GraphMapManager migrates legacy activity category keys"
                     :fn manager-migrates-legacy-activity-category-keys})
(table.insert tests {:name "GraphMapManager migrates legacy activity detail keys"
                     :fn manager-migrates-legacy-activity-detail-keys})
(table.insert tests {:name "GraphMapManager migrates legacy activity edges and metadata"
                     :fn manager-migrates-legacy-activity-edges-and-metadata})
(table.insert tests {:name "GraphMapManager migration skips legacy derived link edges" :fn manager-migration-skips-legacy-derived-link-edges})
(table.insert tests {:name "GraphMapManager migration skips identity-resolved legacy derived link edges" :fn manager-migration-skips-identity-resolved-legacy-derived-link-edges})
(table.insert tests {:name "GraphMapManager migration preserves metadata legacy link-overlap edge"
                      :fn manager-migration-preserves-metadata-legacy-link-overlap-edge})
(table.insert tests {:name "GraphMapManager migrates legacy empty state" :fn manager-migrates-legacy-empty-state})
(table.insert tests {:name "GraphMapManager migrates homeworld legacy shape" :fn manager-migrates-home-world-legacy-shape})
(table.insert tests {:name "GraphMapManager homeworld legacy carries additional maps" :fn manager-homeworld-legacy-carries-additional-maps})
(table.insert tests {:name "GraphMapManager loads migrated state with default graph" :fn manager-loads-migrated-state-with-default-graph})
(table.insert tests {:name "GraphMapManager captures state in target shape" :fn manager-captures-state-in-target-shape})
(table.insert tests {:name "GraphMapManager normalizes integral float next-map-id"
                     :fn manager-normalizes-integral-float-next-map-id})
(table.insert tests {:name "GraphMapManager captures normalized next-map-id"
                     :fn manager-captures-normalized-next-map-id})
(table.insert tests {:name "GraphMapManager creates map" :fn manager-creates-map})
(table.insert tests {:name "GraphMapManager renames map" :fn manager-renames-map})
(table.insert tests {:name "GraphMapManager rename unknown map errors" :fn manager-rename-unknown-map-errors})
(table.insert tests {:name "GraphMapManager switches map" :fn manager-switches-map})
(table.insert tests {:name "GraphMapManager capture during switch keeps target map mounted"
                     :fn manager-capture-during-switch-keeps-target-map-mounted})
(table.insert tests {:name "GraphMapManager switch unknown map errors" :fn manager-switch-unknown-map-errors})
(table.insert tests {:name "GraphMapManager failed switch keeps previous map active" :fn manager-switch-build-failure-keeps-previous-map-active})
(fn manager-captures-selection-state []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local state {:active_map_id "main"
                  :next_map_id 2
                  :maps [{:id "main" :name "Main"
                          :nodes ["test:a" "test:b"]
                          :edges []
                          :selected_node_keys ["test:a" "test:b"]
                          :focused_node_key "test:a"}]})
    (local manager (GraphMapManager.GraphMapManager {:graph graph :state state}))
    (local active (manager:get-active-map))
    (assert (= (length active.selected_node_keys) 2)
            "Active map should have selected keys from state")
    (assert (= (. active.selected_node_keys 1) "test:a"))
    (assert (= active.focused_node_key "test:a")
            "Active map should have focused key from state")
    (local captured (manager:capture-state))
    (local main-map (. captured.maps 1))
    (assert (= (length (or main-map.selected_node_keys [])) 2)
            "Manager capture-state should include selected_node_keys")
    (assert (= main-map.focused_node_key "test:a")
            "Manager capture-state should include focused_node_key")
    (manager:drop)
    (graph:drop))

(fn manager-selection-survives-switch []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (manager:create-map! "beta" "Beta")
    (manager:switch-map! "beta")
    (local beta (manager:get-active-map))
    (beta:load-by-key "test:x")
    (beta:load-by-key "test:y")
    (set beta.selected_node_keys ["test:x" "test:y"])
    (set beta.focused_node_key "test:x")
    (manager:switch-map! "main")
    (manager:switch-map! "beta")
    (local beta-restored (manager:get-active-map))
    (assert (= (length beta-restored.selected_node_keys) 2)
            "Selected keys should survive switch")
    (assert (= (. beta-restored.selected_node_keys 1) "test:x"))
    (assert (= beta-restored.focused_node_key "test:x")
            "Focused key should survive switch")
    (manager:drop)
    (graph:drop))

(fn manager-selection-survives-capture-roundtrip []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (local active (manager:get-active-map))
    (active:load-by-key "test:a")
    (set active.selected_node_keys ["test:a"])
    (set active.focused_node_key "test:a")
    (local captured (manager:capture-state))
    (manager:drop)
    (local manager2 (GraphMapManager.GraphMapManager {:graph graph :state captured}))
    (local active2 (manager2:get-active-map))
    (assert (= (length active2.selected_node_keys) 1)
            "Selection should survive capture roundtrip")
    (assert (= (. active2.selected_node_keys 1) "test:a"))
    (assert (= active2.focused_node_key "test:a")
            "Focused key should survive capture roundtrip")
    (manager2:drop)
    (graph:drop))

(table.insert tests {:name "GraphMapManager deletes map" :fn manager-deletes-map})
(table.insert tests {:name "GraphMapManager cannot delete active map" :fn manager-cannot-delete-active-map})
(table.insert tests {:name "GraphMapManager cannot delete only map" :fn manager-cannot-delete-only-map})
(table.insert tests {:name "GraphMapManager preserves unresolved keys in capture" :fn manager-preserves-unresolved-keys-in-capture})
(table.insert tests {:name "GraphMapManager prunes unresolvable keys on hydration" :fn manager-prunes-unresolvable-keys-on-hydration})
(table.insert tests {:name "GraphMapManager hydration prunes edges without resurrecting on recapture" :fn manager-hydration-prunes-edges-without-resurrecting-on-recapture})
(table.insert tests {:name "GraphMapManager hydration does not resurrect loadable edge endpoints" :fn manager-hydration-does-not-resurrect-loadable-edge-endpoints})
(table.insert tests {:name "GraphMapManager multiple maps" :fn manager-multiple-maps})
(table.insert tests {:name "GraphMapManager maps share graph adapter instances" :fn manager-maps-share-graph})
(table.insert tests {:name "GraphMapManager drop cleans all maps" :fn manager-drop-cleans-all-maps})
(table.insert tests {:name "GraphMapManager delete map removes metadata" :fn manager-delete-map-removes-metadata})
(table.insert tests {:name "GraphMapManager prunes panel metadata on hydration" :fn manager-prunes-panel-metadata-on-hydration})
(table.insert tests {:name "GraphMapManager prunes extra panel metadata on hydration" :fn manager-prunes-extra-panel-metadata-on-hydration})
(table.insert tests {:name "GraphMapManager prunes inactive panel metadata on capture"
                     :fn manager-prunes-inactive-panel-metadata-on-capture})
(table.insert tests {:name "GraphMapManager prunes orphan and wrong-map metadata"
                     :fn manager-prunes-orphan-and-wrong-map-metadata})
(table.insert tests {:name "GraphMapManager reprunes inactive map on each capture"
                     :fn manager-reprunes-inactive-map-on-each-capture})
(table.insert tests {:name "GraphMapManager cleans inactive map after prune failure"
                     :fn manager-cleans-inactive-map-after-prune-failure})
(table.insert tests {:name "GraphMapManager drops map when restore fails"
                     :fn manager-drops-map-when-restore-fails})
(table.insert tests {:name "GraphMapManager drops active map when prune fails"
                     :fn manager-drops-active-map-when-prune-fails})
(table.insert tests {:name "GraphMapManager errors on corrupt metadata during hydration prune" :fn manager-errors-on-corrupt-metadata-during-hydration-prune})
(table.insert tests {:name "GraphMapManager preserves new-format empty map" :fn manager-preserves-new-format-empty-map})
(table.insert tests {:name "GraphMapManager captures selection and focused key" :fn manager-captures-selection-state})
(table.insert tests {:name "GraphMapManager selection survives switch" :fn manager-selection-survives-switch})
(table.insert tests {:name "GraphMapManager selection survives capture roundtrip" :fn manager-selection-survives-capture-roundtrip})

(fn manager-newly-created-map-seeds-start-after-switch []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "start"
        (fn [_key]
            (Graph.GraphNode {:key "start"})))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    ;; Create a second map and switch to it
    (manager:create-map! "second" "Second")
    (manager:switch-map! "second")
    (local active (manager:get-active-map))
    (assert (>= (active:node-count) 1)
            "Newly created map should seed start node after switch")
    (manager:switch-map! "main")
    (manager:drop)
    (graph:drop))

(table.insert tests {:name "GraphMapManager newly created map seeds start after switch" :fn manager-newly-created-map-seeds-start-after-switch})

(fn manager-switch-emits-will-change-before-drop []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (manager:create-map! "second" "Second")
    (local main-map (manager:get-active-map))
    (main-map:load-by-key "test:x")
    (var will-change-previous nil)
    (var will-change-active nil)
    (var map-available-during-will-change? false)
    (manager.maps-will-change:connect
        (fn [payload]
            (set will-change-previous payload.previous-id)
            (set will-change-active payload.active-id)
            (local active (manager:get-active-map))
            (set map-available-during-will-change? (and active (= active.id payload.previous-id)))))
    (manager:switch-map! "second")
    (assert (= will-change-previous "main")
            "maps-will-change should fire with previous-id")
    (assert (= will-change-active "second")
            "maps-will-change should fire with active-id")
    (assert map-available-during-will-change?
            "Active map should still be available during maps-will-change handler")
    (manager:drop)
    (graph:drop))

(table.insert tests {:name "GraphMapManager switch emits maps-will-change before drop" :fn manager-switch-emits-will-change-before-drop})

(fn manager-create-and-switch-empty-map-does-not-seed-start []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "start"
        (fn [_key]
            (Graph.GraphNode {:key "start"})))
    (local manager (GraphMapManager.GraphMapManager {:graph graph :state {}}))
    (local created (manager:create-and-switch-map! {:name "Empty"}))
    (assert (= created (manager:get-active-map))
            "create-and-switch-map! should return the active map")
    (assert (= created.id "map-2")
            "create-and-switch-map! should allocate map id from next-map-id")
    (assert (= created.name "Empty")
            "create-and-switch-map! should apply the requested name")
    (assert (= (created:node-count) 0)
            "Empty create-and-switch map should not seed start")
    (local captured (manager:capture-state))
    (assert (= captured.active_map_id "map-2")
            "Capture should mark the new map active")
    (var empty-entry nil)
    (each [_ entry (ipairs captured.maps) &until empty-entry]
        (when (= entry.id "map-2")
            (set empty-entry entry)))
    (assert empty-entry "Capture should include the new empty map")
    (assert (= empty-entry.name "Empty")
            "Captured empty map should preserve requested name")
    (assert (= (length (or empty-entry.nodes [])) 0)
            "Captured empty map should have no nodes")
    (assert (= (length (or empty-entry.edges [])) 0)
            "Captured empty map should have no edges")
    (manager:drop)
    (graph:drop))

(fn manager-create-and-switch-map-from-state []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (local state {:nodes ["test:a" "test:b"]
                  :edges [{:source "test:a" :target "test:b"}]
                  :islands [{:id "island-1"
                             :kind "ordered-list"
                             :members ["test:a" "test:b"]
                             :state {:list-key "test:a" :collapsed false}}]
                  :next_island_id 2
                  :selected_node_keys ["test:a"]
                  :focused_node_key "test:a"})
    (local created (manager:create-and-switch-map! {:name "Selection" :state state}))
    (assert (= created (manager:get-active-map))
            "State-backed create-and-switch should return the active map")
    (assert (= created.id "map-2")
            "State-backed create-and-switch should allocate map id from next-map-id")
    (assert (= created.name "Selection")
            "State-backed create-and-switch should use requested name")
    (assert (created:lookup "test:a")
            "State-backed map should restore test:a")
    (assert (created:lookup "test:b")
            "State-backed map should restore test:b")
    (assert (= (created:edge-count) 1)
            "State-backed map should restore explicit edge")
    (local islands (created:list-islands))
    (assert (= (length islands) 1)
            "State-backed map should restore island")
    (assert (= (. islands 1 :id) "island-1")
            "Restored island should keep id")
    (assert (= (length created.selected_node_keys) 1)
            "State-backed map should restore selection")
    (assert (= (. created.selected_node_keys 1) "test:a")
            "State-backed map should restore selected key")
    (assert (= created.focused_node_key "test:a")
            "State-backed map should restore focus")
    (local maps (manager:list-maps))
    (var has-main? false)
    (each [_ entry (ipairs maps)]
        (when (= entry.id "main")
            (set has-main? true)))
    (assert has-main? "Previous active map should still exist after create-and-switch")
    (manager:drop)
    (graph:drop))

(table.insert tests {:name "GraphMapManager create-and-switch empty map does not seed start"
                     :fn manager-create-and-switch-empty-map-does-not-seed-start})
(table.insert tests {:name "GraphMapManager create-and-switch map from state"
                     :fn manager-create-and-switch-map-from-state})

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "graph-map-manager" :tests tests})))

{:name "graph-map-manager"
 :tests tests
 :main main}
