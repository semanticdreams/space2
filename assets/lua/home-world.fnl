(local glm (require :glm))
(local fs (require :fs))
(local json (require :json))
(local logging (require :logging))
(local TerrainIssueLog (require :terrain-issue-log))
(local JsonUtils (require :json-utils))
(local Camera (require :camera))
(local Scene (require :scene))
(local {: FirstPersonControls} (require :first-person-controls))
(local Graph (require :graph/init))

(local GraphMap (require :graph/map))
(local GraphMapManager (require :graph/map-manager))
(local DrawingDocument (require :drawing/document))
(local DrawingController (require :drawing/controller))
(local ActivityDockView (require :activity-dock-view))
(local Activities (require :activities))
(local WorkspaceShellState (require :home-world-workspace-shell-state))
(local MathUtils (require :math-utils))
(local CoordinateGuard (require :coordinate-guard))
(local PhysicsContainment (require :physics-containment))
(local TerrainRecords (require :scene-terrain-records))
(local LightSystemModule (require :light-system))
(local SkyboxState (require :skybox-state))
(local BackgroundState (require :background-state))
(local ActivitySceneState (require :activity-scene-state))
(local Presentation (require :activity-presentation))

(local vec3->array (. MathUtils :vec3->array))
(local quat->array (. MathUtils :quat->array))
(local array->vec3 (. MathUtils :array->vec3))
(local array->quat (. MathUtils :array->quat))
(local safe-vec3? CoordinateGuard.safe-vec3?)
(local sanitize-vec3 CoordinateGuard.sanitize-vec3)
(local finite-number? CoordinateGuard.finite-number?)

(local default-containment-config
  (PhysicsContainment.serialize-config (PhysicsContainment.default-config)))

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn resolve-sandbox-scene-state [world]
  "Return the canonical sandbox scene session state, or nil."
  (and world.state
       world.state.activity
       world.state.activity.sessions
       world.state.activity.sessions.sandbox
       world.state.activity.sessions.sandbox.scene))

(fn merge-state-defaults [defaults persisted]
  (if (not (= (type defaults) :table))
      (if (= persisted nil) defaults persisted)
      (do
        (local out {})
        (local source
          (if (= (type persisted) :table)
              persisted
              {}))
        (each [k v (pairs defaults)]
          (set (. out k) (merge-state-defaults v (. source k))))
        (each [k v (pairs source)]
          (when (= (. out k) nil)
            (set (. out k) (clone-table v))))
        out)))

(local resolve-runtime-interaction-surface WorkspaceShellState.resolve-runtime-interaction-surface)
(local encode-interaction-surface WorkspaceShellState.encode-interaction-surface)
(local capture-activity-shell-state WorkspaceShellState.capture-activity-shell-state)

(fn drop-graph-node-view-panels! [state]
  (local panels (and state state.panels))
  (if (not (= (type panels) :table))
      false
      (do
        (local kept [])
        (var changed? false)
        (each [_ panel (ipairs panels)]
          (if (= (and panel panel.kind) "graph-node-view")
              (set changed? true)
              (table.insert kept panel)))
        (when changed?
          (set state.panels kept))
        changed?)))

(fn safe-graph-map-id? [id]
  (and (= (type id) :string)
       (> (string.len id) 0)
       (not (= (string.sub id 1 1) "."))
       (not (string.find id "/" 1 true))
       (not (string.find id "\\" 1 true))
       (not (string.find id "." 1 true))))

(fn list-contains? [items value]
  (var found? false)
  (each [_ item (ipairs (or items [])) &until found?]
    (when (= item value)
      (set found? true)))
  found?)

(fn ensure-graph-map-state-entry! [world map-id]
  (assert (safe-graph-map-id? map-id)
          (.. "HomeWorld legacy graph panel migration unsafe map id: " (tostring map-id)))
  (when (not world.state.graph)
    (set world.state.graph {}))
  (local graph-state world.state.graph)
  (when (not (= (type graph-state.maps) :table))
    (local active-id (if (= (type graph-state.active_map_id) :string)
                         graph-state.active_map_id
                         "main"))
    (local core (if (= (type graph-state.graph) :table)
                    graph-state.graph
                    graph-state))
    (set graph-state.maps [{:id active-id
                            :name (if (= active-id "main") "Main" active-id)
                            :nodes (clone-table (or core.nodes []))
                            :edges (clone-table (or core.edges []))
                            :selected_node_keys (clone-table (or core.selected_node_keys []))
                            :focused_node_key core.focused_node_key}])
    (set graph-state.active_map_id active-id)
    (set graph-state.next_map_id (or graph-state.next_map_id 2))
    (set graph-state.graph nil))
  (var entry nil)
  (each [_ candidate (ipairs graph-state.maps) &until entry]
    (when (= candidate.id map-id)
      (set entry candidate)))
  entry)

(fn ensure-legacy-panel-node-in-map! [world map-id node-key]
  (assert (= (type node-key) :string)
          "HomeWorld legacy graph panel migration requires graph-node-view :node-key")
  (local entry (ensure-graph-map-state-entry! world map-id))
  (when entry
    (when (not (= (type entry.nodes) :table))
      (set entry.nodes []))
    (when (not (list-contains? entry.nodes node-key))
      (table.insert entry.nodes node-key)))
  entry)

(fn metadata-path-for-graph-map [world map-id]
  (assert (safe-graph-map-id? map-id)
          (.. "HomeWorld graph map metadata unsafe map id: " (tostring map-id)))
  (local metadata-dir (fs.join-path (fs.join-path (fs.join-path world.dir "graph") "maps") map-id))
  (local metadata-path (fs.join-path metadata-dir "metadata.json"))
  (local (dir-ok dir-err) (pcall fs.create-dirs metadata-dir))
  (when (not dir-ok)
    (error (string.format "HomeWorld failed to create %s for graph panel migration: %s"
                          metadata-dir
                          dir-err)))
  metadata-path)

(fn read-graph-map-metadata-for-migration [metadata-path]
  (if (fs.exists metadata-path)
      (do
        (local (read-ok content) (pcall fs.read-file metadata-path))
        (when (not read-ok)
          (error (string.format "HomeWorld failed to read %s for graph panel migration: %s"
                                metadata-path
                                content)))
        (local (parse-ok decoded) (pcall json.loads content))
        (when (not parse-ok)
          (error (string.format "HomeWorld failed to parse %s for graph panel migration: %s"
                                metadata-path
                                decoded)))
        decoded)
      {:positions {}
       :presentations {}
       :sizes {}
       :panels []
       :extra_panels []}))

(fn write-graph-map-metadata-for-migration! [metadata-path meta]
  (local (write-ok write-err) (pcall (fn [] (JsonUtils.write-json! metadata-path meta))))
  (when (not write-ok)
    (error (string.format "HomeWorld failed to write %s for graph panel migration: %s"
                          metadata-path
                          write-err))))

(fn migrate-legacy-graph-node-view-panels! [world]
  (local migrated-by-map {})
  (local migrated-node-keys-by-map {})
  (fn collect! [state target-kind]
    (local panels (and state state.panels))
    (if (not (= (type panels) :table))
        false
        (do
          (local kept [])
          (var changed? false)
          (each [_ panel (ipairs panels)]
            (if (= (and panel panel.kind) "graph-node-view")
                (do
                  (set changed? true)
                  (local map-id (or panel.graph-map-id
                                    (and world.state world.state.graph
                                         world.state.graph.active_map_id)
                                    "main"))
                  (local entry {:kind "graph-node-view"
                                :graph-map-id map-id
                                :node-key panel.node-key
                                :target-kind target-kind
                                :restorer-module (or panel.restorer-module
                                                     "graph/view/node-view-panel-restorer")
                                :panel (clone-table panel)})
                  (when (not (. migrated-by-map map-id))
                    (tset migrated-by-map map-id []))
                  (table.insert (. migrated-by-map map-id) entry))
                (table.insert kept panel)))
          (when changed?
            (set state.panels kept))
          changed?)))
  (local canvas-changed? (collect! (and world.state world.state.canvas) "canvas"))
  (local hud-changed? (collect! (and world.state world.state.hud) "hud"))
  (local scene-changed? (collect! (and world.state world.state.scene) "scene"))
  (local changed? (or canvas-changed? hud-changed? scene-changed?))
  (when changed?
    (each [map-id entries (pairs migrated-by-map)]
      (local valid-entries [])
      (each [_ entry (ipairs entries)]
        (when (ensure-legacy-panel-node-in-map! world map-id entry.node-key)
          (when (not (. migrated-node-keys-by-map map-id))
            (tset migrated-node-keys-by-map map-id {}))
          (tset (. migrated-node-keys-by-map map-id) entry.node-key true)
          (table.insert valid-entries entry)))
      (when (> (length valid-entries) 0)
        (local metadata-path (metadata-path-for-graph-map world map-id))
        (local meta (read-graph-map-metadata-for-migration metadata-path))
        (local panels (or meta.panels []))
        (each [_ entry (ipairs valid-entries)]
          (table.insert panels entry))
        (set meta.panels panels)
        (write-graph-map-metadata-for-migration! metadata-path meta))))
  (values changed? migrated-node-keys-by-map))


(fn base-default-state []
  {:camera {:position [0 0 30]
            :rotation [1 0 0 0]}
   :activity {:active_id nil
              :preferred_interaction_surface "scene"
              :sessions {}}
   :canvas {:camera {:position [0 0 100]}
            :scale_factor 1.0
            :panels []}
   :drawing (DrawingDocument.default-state)
   :physics {}
   :graph {:graph {:nodes []
                    :edges []}}
   :board {:items []
           :connectors []}
   :scene {}
   :hud {:panels []}})

(fn default-state []
  (base-default-state))

(fn resolve-graph-core-state [state]
  (local payload (or state {}))
  (if (and (= (type payload.graph) :table))
      payload.graph
      (and (= (type payload.maps) :table)
           (= (type payload.active_map_id) :string))
      (do
        (var entry nil)
        (each [_ m (ipairs payload.maps) &until entry]
          (when (= m.id payload.active_map_id)
            (set entry m)))
        {:nodes (or (and entry entry.nodes) [])
         :edges (or (and entry entry.edges) [])})
      {:nodes (or payload.nodes [])
       :edges (or payload.edges [])}))

(fn merge-preserved-graph-map-state [graph existing-state captured-map-state]
  (local merged (clone-table captured-map-state))
  (local active-map-id merged.active_map_id)
  (local supports-key?
    (fn [key]
      (and graph graph.has-key-loader-for-key (graph:has-key-loader-for-key key))))
  (when (= (type merged.maps) :table)
    ;; Build lookup from existing persisted map entries by id (including legacy
    ;; graph.graph which maps to "main").
    (local existing-by-id {})
    (if (= (type existing-state.maps) :table)
        ;; Maps format - authoritative when present
        (each [_ m (ipairs existing-state.maps)]
          (set (. existing-by-id m.id)
               {:nodes (or m.nodes [])
                :edges (or m.edges [])}))
        (= (type existing-state.graph) :table)
        ;; Legacy format (.graph directly has nodes/edges)
        (set (. existing-by-id "main")
             {:nodes (or existing-state.graph.nodes [])
              :edges (or existing-state.graph.edges [])}))
    (each [_ map-entry (ipairs merged.maps)]
      (local existing (. existing-by-id map-entry.id))
      (when (and existing (not (= map-entry.id active-map-id)))
        (local captured-nodes {})
        (local captured-edges {})
        (each [_ key (ipairs (or map-entry.nodes []))]
          (set (. captured-nodes key) true))
        (each [_ edge (ipairs (or map-entry.edges []))]
          (local composite (.. (or edge.source "") "->" (or edge.target "")))
          (set (. captured-edges composite) true))
        (each [_ key (ipairs (or existing.nodes []))]
          (when (and (not (. captured-nodes key))
                     (not (supports-key? key)))
            (table.insert map-entry.nodes key)))
        (each [_ edge (ipairs (or existing.edges []))]
          (local source-key edge.source)
          (local target-key edge.target)
          (local composite (.. (or source-key "") "->" (or target-key "")))
          (local preserve?
            (and (not (. captured-edges composite))
                 (or (and source-key (not (supports-key? source-key)))
                     (and target-key (not (supports-key? target-key))))))
          (when preserve?
            (table.insert map-entry.edges edge))))))
  merged)

(fn merge-preserved-graph-state [graph existing-state captured-state]
  (if (= (type captured-state.maps) :table)
      (merge-preserved-graph-map-state graph existing-state captured-state)
      (do
        (local existing-core (resolve-graph-core-state existing-state))
        (local captured-core (resolve-graph-core-state captured-state))
        (local supports-key?
          (fn [key]
            (and graph graph.has-key-loader-for-key (graph:has-key-loader-for-key key))))
        (local captured-nodes {})
        (local captured-edges {})
        (var merged-nodes [])
        (var merged-edges [])
        (each [_ key (ipairs (or captured-core.nodes []))]
          (set (. captured-nodes key) true)
          (table.insert merged-nodes key))
        (each [_ edge (ipairs (or captured-core.edges []))]
          (local composite (.. (or edge.source "") "->" (or edge.target "")))
          (set (. captured-edges composite) true)
          (table.insert merged-edges edge))
        (each [_ key (ipairs (or existing-core.nodes []))]
          (when (and (not (. captured-nodes key))
                     (not (supports-key? key)))
            (table.insert merged-nodes key)))
        (each [_ edge (ipairs (or existing-core.edges []))]
          (local source-key edge.source)
          (local target-key edge.target)
          (local composite (.. (or source-key "") "->" (or target-key "")))
          (local preserve?
            (and (not (. captured-edges composite))
                 (or (and source-key (not (supports-key? source-key)))
                     (and target-key (not (supports-key? target-key))))))
          (when preserve?
            (table.insert merged-edges edge)))
        {:graph {:nodes merged-nodes
                 :edges merged-edges}})))

(fn parse-terrain-persistence-key [key]
  (if (= (type key) :string)
      (do
        (local (terrain-world terrain-id) (string.match key "^terrain:([^:]+):([^:]+)$"))
        (if terrain-world
            {:key key
             :world-id terrain-world
             :terrain-id terrain-id}
            (do
              (local (editor-world editor-terrain-id) (string.match key "^terrain%-editor:([^:]+):([^:]+)$"))
              (if editor-world
                  {:key key
                   :world-id editor-world
                   :terrain-id editor-terrain-id}
                  (do
                    (local (tool-world tool-terrain-id _tool-id)
                      (string.match key "^terrain%-tool:([^:]+):([^:]+):([^:]+)$"))
                    (if tool-world
                        {:key key
                         :world-id tool-world
                         :terrain-id tool-terrain-id}
                        nil))))))
      nil))

(fn legacy-activity-terrain-graph-key? [world key]
  "Return true for same-world legacy terrain graph keys that GraphMapManager migrates."
  (local parsed (parse-terrain-persistence-key key))
  (and parsed (= parsed.world-id world.id)))

(fn invalid-terrain-persistence-keys [world state transient-map-node-keys]
  (local payload (or state {}))
  (local graph-state (or payload.graph {}))
  (local valid-terrain-ids {})
  (var invalid-keys [])
  (local seen-invalid {})
  (each [_ record (ipairs (or (and payload.activity
                                   payload.activity.sessions
                                   payload.activity.sessions.sandbox
                                   payload.activity.sessions.sandbox.scene
                                   payload.activity.sessions.sandbox.scene.terrains)
                              (and payload.scene payload.scene.terrains)
                              []))]
    (local terrain-id (and record record.id))
    (when terrain-id
      (set (. valid-terrain-ids terrain-id) true)))
  (fn record-invalid! [key]
    (when (and (= (type key) :string)
               (not (. seen-invalid key)))
      (set (. seen-invalid key) true)
      (table.insert invalid-keys key)))
  (fn validate-key! [key]
    (local parsed (parse-terrain-persistence-key key))
    (when (and parsed
               (or (not (= parsed.world-id world.id))
                   (not (. valid-terrain-ids parsed.terrain-id))))
      (record-invalid! key)))
  (fn validate-panel-node-key! [panel expected-kind]
    (when (= (and panel panel.kind) expected-kind)
      (validate-key! (and panel panel.node-key))))
  (fn transient-map-node-key? [map-id key]
    (local map-keys (and transient-map-node-keys
                         map-id
                         (. transient-map-node-keys map-id)))
    (and map-keys key (. map-keys key)))
  (fn validate-map-entries [map-state]
    (local map-id (and map-state map-state.id))
    (each [_ key (ipairs (or map-state.nodes []))]
      (when (not (transient-map-node-key? map-id key))
        (when (not (legacy-activity-terrain-graph-key? world key))
          (validate-key! key))))
    (each [_ edge (ipairs (or map-state.edges []))]
      (when (not (legacy-activity-terrain-graph-key? world edge.source))
        (validate-key! edge.source))
      (when (not (legacy-activity-terrain-graph-key? world edge.target))
        (validate-key! edge.target))))
  ;; Validate all maps when in new format; otherwise validate active/resolved core
  (if (= (type graph-state.maps) :table)
      (each [_ m (ipairs graph-state.maps)]
        (validate-map-entries m))
      (validate-map-entries (resolve-graph-core-state graph-state)))
  (each [_ key (ipairs (or (and graph-state.views graph-state.views.open-node-keys) []))]
    (when (not (legacy-activity-terrain-graph-key? world key))
      (validate-key! key)))
  (each [_ panel (ipairs (or (and payload.canvas payload.canvas.panels) []))]
    (validate-panel-node-key! panel "graph-node-view"))
  (each [_ panel (ipairs (or (and payload.hud payload.hud.panels) []))]
    (validate-panel-node-key! panel "graph-node-view"))
  (each [_ panel (ipairs (or (and payload.activity
                                   payload.activity.sessions
                                   payload.activity.sessions.sandbox
                                   payload.activity.sessions.sandbox.scene
                                   payload.activity.sessions.sandbox.scene.panels)
                              (and payload.scene payload.scene.panels)
                              []))]
    (validate-panel-node-key! panel "graph-node-cube"))
  invalid-keys)

(fn read-world-state [path]
  (if (not (fs.exists path))
      nil
      (do
        (local (ok-read content) (pcall fs.read-file path))
        (if (not ok-read)
            (error (string.format "HomeWorld failed to read %s: %s" path content))
            (do
              (local (ok-parse decoded) (pcall json.loads content))
              (when (not ok-parse)
                (error (string.format "HomeWorld failed to parse %s: %s" path decoded)))
              (when (not (= (type decoded) :table))
                (error (string.format "HomeWorld expected table in %s" path)))
              decoded)))))

(fn HomeWorld [opts]
  (local options (or opts {}))
  (local id (assert options.id "HomeWorld requires :id"))
  (local name (or options.name "home"))
  (local type-name (or options.type "home"))
  (local dir (assert options.dir "HomeWorld requires :dir"))
  (local state-path (fs.join-path dir "world.json"))

  (local self {:id id
               :name name
               :type type-name
               :dir dir
               :graph-world-manager options.graph-world-manager
               :asset-path-resolver options.asset-path-resolver
               :state-path state-path
               :state (default-state)
               :active? false
               :initialized? false
               :runtime nil})

  (fn ensure-world-dir []
    (local (ok err) (pcall fs.create-dirs dir))
    (when (not ok)
      (error (string.format "HomeWorld failed to create %s: %s" dir err))))

  (fn persist-loaded-state! [world]
    (ensure-world-dir)
    (local (ok err) (pcall (fn [] (JsonUtils.write-json! world.state-path world.state))))
    (when (not ok)
      (error (string.format "HomeWorld failed to write %s during load: %s" world.state-path err))))

  (fn load-state [world]
    (local persisted (read-world-state world.state-path))
    (var repaired-persisted-state? false)
    (if persisted
        (do
          (set world.state (merge-state-defaults (base-default-state) persisted))
          (local (migrated-legacy-panels? transient-map-node-keys)
            (migrate-legacy-graph-node-view-panels! world))
          (when migrated-legacy-panels?
            (set repaired-persisted-state? true))
          ;; Only run legacy scene repair when persisted data has no canonical
          ;; sandbox session yet.  If activity.sessions.sandbox.scene already
          ;; exists the migration below is the only normalizer and we skip
          ;; synthesizing old top-level fields.
          (local has-canonical-sandbox?
            (and (= (type persisted.activity) :table)
                 (= (type persisted.activity.sessions) :table)
                 (= (type persisted.activity.sessions.sandbox) :table)
                 (= (type persisted.activity.sessions.sandbox.scene) :table)))
          (local persisted-lights (and (not has-canonical-sandbox?)
                                       persisted.scene
                                       persisted.scene.lights))
          (local persisted-skybox (and (not has-canonical-sandbox?)
                                       persisted.scene
                                       persisted.scene.skybox))
          (local persisted-background (and (not has-canonical-sandbox?)
                                           persisted.scene
                                           persisted.scene.background))
          (if persisted-lights
              (set world.state.scene.lights
                   (LightSystemModule.normalize-complete-state persisted-lights
                                                              (string.format "HomeWorld.load-state %s"
                                                                             world.id)))
              (when (not has-canonical-sandbox?)
                (set world.state.scene.lights (LightSystemModule.default-state))
                (set repaired-persisted-state? true)))
          (if persisted-skybox
              (set world.state.scene.skybox
                   (SkyboxState.normalize-complete-state persisted-skybox
                                                        (string.format "HomeWorld.load-state %s"
                                                                       world.id)))
              (when (not has-canonical-sandbox?)
                (set world.state.scene.skybox (SkyboxState.default-state))
                (set repaired-persisted-state? true)))
          (if persisted-background
              (set world.state.scene.background
                   (BackgroundState.normalize-complete-state persisted-background
                                                            (string.format "HomeWorld.load-state %s"
                                                                           world.id)))
              (when (not has-canonical-sandbox?)
                (set world.state.scene.background (BackgroundState.default-state))
                (set repaired-persisted-state? true)))
          (local stale-terrain-graph-keys
            (invalid-terrain-persistence-keys world world.state transient-map-node-keys))
          (when (> (length stale-terrain-graph-keys) 0)
            (error
              (string.format
                "HomeWorld.load-state %s found stale terrain graph refs: %s"
                world.id
                (table.concat stale-terrain-graph-keys ", ")))))
        (do
          (TerrainIssueLog.warn (string.format
                                  "[world] %s persisted state missing/invalid; resetting world.state"
                                  world.id))
          (set world.state (default-state))))
    (local canvas-state (or (and world.state world.state.canvas) {}))
    (local activity-state (or (and world.state world.state.activity) {}))
    (when (and (= activity-state.active_id nil)
               (not (= canvas-state.active_mode nil)))
      (set activity-state.active_id canvas-state.active_mode)
      (set repaired-persisted-state? true))
    (when (and (= activity-state.preferred_interaction_surface nil)
               (not (= canvas-state.preferred_interaction_surface nil)))
      (set activity-state.preferred_interaction_surface
           canvas-state.preferred_interaction_surface)
      (set repaired-persisted-state? true))
    (when (= activity-state.active_id nil)
      (set activity-state.active_id nil))
    (local (normalized-activity-id repaired-activity? activity-repair-reason)
      (Activities.normalize-persisted-activity-id activity-state.active_id))
    (when repaired-activity?
      (logging.warn (string.format "[world] %s %s"
                                   world.id
                                   activity-repair-reason))
      (set repaired-persisted-state? true))
    (set activity-state.active_id normalized-activity-id)
    (set activity-state.preferred_interaction_surface
         (encode-interaction-surface (or activity-state.preferred_interaction_surface "scene")))
    (when (not activity-state.sessions)
      (set activity-state.sessions {}))
    (set world.state.activity activity-state)
    (when (or (not (= canvas-state.active_mode nil))
              (not (= canvas-state.preferred_interaction_surface nil)))
      (set repaired-persisted-state? true))
    (set canvas-state.active_mode nil)
    (set canvas-state.preferred_interaction_surface nil)
    (set world.state.canvas canvas-state)
    (local camera-state (or (and world.state world.state.camera) {}))
    (local raw-position camera-state.position)
    (local (ok parsed-position) (pcall array->vec3 raw-position))
    (local camera-position
      (if ok
          parsed-position
          nil))
    (if (safe-vec3? camera-position)
        (set camera-state.position (vec3->array camera-position))
        (do
          (logging.warn (string.format
                          "[world] %s invalid persisted camera.position; resetting to default"
                          world.id))
          (set camera-state.position [0 0 30])))
    (set world.state.camera camera-state)
    ;; Physics containment legacy repair: only run when no canonical sandbox
    ;; session exists.  If activity.sessions.sandbox.scene is already present,
    ;; the migration below normalizes containment; we skip synthesizing legacy
    ;; physics.containment to avoid spurious rewrites.
    (local physics-state (or (and world.state world.state.physics) {}))
    ;; Only run legacy containment repair when this is a persisted load and
    ;; no canonical sandbox session exists.  The migration below normalizes
    ;; containment for canonical loads; new worlds get defaults from migration.
    (when persisted
      (local has-canonical-sandbox?
        (and (= (type persisted.activity) :table)
             (= (type persisted.activity.sessions) :table)
             (= (type persisted.activity.sessions.sandbox) :table)
             (= (type persisted.activity.sessions.sandbox.scene) :table)))
      (when (not has-canonical-sandbox?)
      (local containment
        (if (= (type physics-state.containment) :table)
            physics-state.containment
            (if (finite-number? physics-state.floor-y)
                (do
                  (logging.warn (string.format
                                  "[world] %s migrating persisted physics.floor-y to containment bounds"
                                  world.id))
                  {:mode "manual-bounds"
                   :bounds {:min [-500 physics-state.floor-y -500]
                            :max [500 500 500]}})
                (do
                  (when (not (= physics-state.floor-y nil))
                    (logging.warn (string.format
                                    "[world] %s invalid persisted physics containment; resetting to default"
                                    world.id)))
                  default-containment-config))))
      (set physics-state.containment
           (PhysicsContainment.serialize-config
             (PhysicsContainment.normalize-config containment)))))
    (set physics-state.floor-y nil)
    (set world.state.physics physics-state)
    ;; Migrate legacy top-level scene/physics state into canonical activity sessions
    (local migrated-scene-state? (ActivitySceneState.migrate-legacy-world-state! world.state))
    (when (or migrated-scene-state? repaired-persisted-state?)
      (set repaired-persisted-state? true))
    ;; Migrate legacy top-level camera state into the sandbox session
    ;; so camera ownership moves from the runtime globals to the activity slot.
    (let [sandbox-scene (resolve-sandbox-scene-state world)
          camera-state (and world.state world.state.camera)]
      (when (and sandbox-scene
                 (= (type camera-state) :table)
                 (not sandbox-scene.camera))
        (set sandbox-scene.camera
             {:position (or camera-state.position [0 0 30])
              :rotation (or camera-state.rotation [1 0 0 0])})))
    ;; Migrate legacy canvas camera into the selected/default canvas activity
    ;; session when no per-activity canvas camera exists yet.  Only the
    ;; active canvas activity receives the legacy camera, not all canvas
    ;; activities.  When no canvas activity is selected (e.g. active_id is
    ;; nil or sandbox), the camera is migrated into the default canvas
    ;; activity "graph" so it is available when graph activates.
    (let [canvas-camera-state (and world.state world.state.canvas
                                   world.state.canvas.camera)
          activity-state (and world.state world.state.activity)
          active-id (and activity-state activity-state.active_id)
          canvas-ids {:graph true :drawing true :board true}
          ;; Use active-id if it is a canvas activity; otherwise default to "graph"
          target-id (if (and active-id (. canvas-ids active-id))
                       active-id
                       "graph")]
      (when (= (type canvas-camera-state) :table)
        (when (not (and activity-state.sessions
                        (= (type activity-state.sessions) :table)))
          (set activity-state.sessions {}))
        (when (not (. activity-state.sessions target-id))
          (set (. activity-state.sessions target-id) {}))
        (let [session (. activity-state.sessions target-id)]
          (when (not session.canvas-camera)
            (set session.canvas-camera
                 {:position (or canvas-camera-state.position [0 0 100])})
            (when (not repaired-persisted-state?)
              (set repaired-persisted-state? true))))))
    (when repaired-persisted-state?
      (persist-loaded-state! world)))

  (fn save-state [world]
    (ensure-world-dir)
    (local (ok err) (pcall (fn [] (JsonUtils.write-json! world.state-path world.state))))
    (when (not ok)
      (error (string.format "HomeWorld failed to write %s: %s" world.state-path err)))
    true)

  (fn resolve-runtime-containment-config [world]
    (local sandbox-scene (resolve-sandbox-scene-state world))
    (local state-config (and sandbox-scene sandbox-scene.containment))
    (PhysicsContainment.serialize-config
      (PhysicsContainment.normalize-config (or state-config default-containment-config))))

  (fn set-runtime-containment-config! [world config]
    (local serialized
      (PhysicsContainment.serialize-config
        (PhysicsContainment.normalize-config (or config default-containment-config))))
    (when world.state
      ;; Write to sandbox activity session scene
      (local sandbox-scene (resolve-sandbox-scene-state world))
      (when sandbox-scene
        (set sandbox-scene.containment serialized)))
    serialized)

  (fn apply-runtime-containment! [world opts]
    (local options (or opts {}))
    (local config
      (set-runtime-containment-config! world (resolve-runtime-containment-config world)))
    (local scene (or options.scene
                     (and world.runtime world.runtime.scene)))
    (if (and scene scene.active-containment-manager)
        (let [manager (scene:active-containment-manager)]
          (manager:ensure-installed {:scene scene :config config}))
        false)
    config)

  (fn clear-active-runtime-containment! [world]
    (local runtime world.runtime)
    (local runtime-scene (and runtime runtime.scene))
    (when runtime-scene
      (local manager (and runtime-scene runtime-scene.active-containment-manager
                         (runtime-scene:active-containment-manager)))
      (when manager
        (manager:clear)))
    true)

  (fn apply-runtime-physics-policy! []
    (when (and app.engine app.engine.physics)
      (app.engine.physics:setGravity 0 -25 0))
    true)

  (fn hydration-pending? [runtime]
    (local hydration (and runtime runtime.hydration))
    (and hydration (not hydration.completed?)))

  (fn sync-startup-physics-pause! [world]
    (when (and app app.set-startup-physics-paused)
      (app.set-startup-physics-paused world.id
                                      (and world.active?
                                           (hydration-pending? world.runtime))))
    true)

  (fn apply-runtime-light-state! [world]
    (local runtime world.runtime)
    (local scene (and runtime runtime.scene))
    (local sandbox-scene (resolve-sandbox-scene-state world))
    (when (and scene scene.set-light-state)
      (scene:set-light-state (and sandbox-scene sandbox-scene.lights))))

  (fn apply-runtime-skybox-state! [world]
    (local runtime world.runtime)
    (local scene (and runtime runtime.scene))
    (local sandbox-scene (resolve-sandbox-scene-state world))
    (local theme-key
      (if (and app app.themes app.themes.get-active-theme-name)
          (SkyboxState.normalize-theme-key
            (app.themes.get-active-theme-name)
            (string.format "HomeWorld.apply-runtime-skybox-state %s" world.id))
          nil))
    (when (and scene scene.set-skybox-state)
      (scene:set-skybox-state
        (SkyboxState.resolve-for-theme
          (assert (and sandbox-scene sandbox-scene.skybox)
                  (string.format "HomeWorld %s requires sandbox scene.skybox" world.id))
          theme-key))))

  (fn apply-runtime-background-state! [world]
    (local runtime world.runtime)
    (local scene (and runtime runtime.scene))
    (local sandbox-scene (resolve-sandbox-scene-state world))
    (when (and scene scene.set-background-state)
      (scene:set-background-state
        (BackgroundState.normalize-complete-state
          (assert (and sandbox-scene sandbox-scene.background)
                  (string.format "HomeWorld %s requires sandbox scene.background" world.id))
          (string.format "HomeWorld.apply-runtime-background-state %s" world.id)))))

  (fn hydration-now-ms []
    (assert (and app app.engine app.engine.now-ms)
            "HomeWorld hydration timing requires app.engine.now-ms")
    (app.engine:now-ms))

  (fn clone-array-slice [entries start-index]
    (local out [])
    (each [idx entry (ipairs (or entries []))]
      (when (>= idx start-index)
        (table.insert out (clone-table entry))))
    out)

  (fn merge-panel-state [restored pending]
    (local panels [])
    (each [_ panel (ipairs (or restored []))]
      (table.insert panels panel))
    (each [_ panel (ipairs (or pending []))]
      (table.insert panels (clone-table panel)))
    panels)

  (fn remaining-hydration-panels [hydration]
    (if hydration
        (clone-array-slice hydration.scene-panels hydration.scene-panel-index)
        []))

  (fn mark-runtime-hydration-complete! [world runtime hydration]
    (when (and hydration (not hydration.completed?))
      (set hydration.completed? true)
      (set hydration.phase "complete")
      (set hydration.completed-at-ms (hydration-now-ms))
      (sync-startup-physics-pause! world)
      (logging.info
        (string.format
          "[world] %s hydration completed in %.2fms"
          world.id
          (- hydration.completed-at-ms (or hydration.started-at-ms hydration.completed-at-ms)))))
    true)

  (fn schedule-runtime-hydration-start! [world runtime]
    (local hydration (and runtime runtime.hydration))
    (when (and hydration
               (not hydration.completed?)
               (not hydration.start-scheduled?))
      (assert (and app app.next-frame)
              "HomeWorld hydration requires app.next-frame")
      (set hydration.start-scheduled? true)
      (app.next-frame
        (fn []
          (when (= world.runtime runtime)
            (local active-hydration (and runtime runtime.hydration))
            (when active-hydration
              (set active-hydration.ready? true))))))
    true)

  (fn start-runtime-hydration! [world runtime hydration]
    (when (and hydration (not hydration.started?))
      (set hydration.started? true)
      (set hydration.started-at-ms (hydration-now-ms))
      (logging.info (string.format "[world] %s hydration started" world.id)))
    true)

  (fn restore-next-runtime-panel! [world runtime hydration]
    (local panels (or hydration.scene-panels []))
    (if (> hydration.scene-panel-index (length panels))
        (mark-runtime-hydration-complete! world runtime hydration)
        (do
          (runtime.scene:restore-panel-state
            (. panels hydration.scene-panel-index)
            hydration.scene-panel-index)
          (runtime.scene:sync-scene-objects)
          (set hydration.scene-panel-index (+ hydration.scene-panel-index 1))
          (when (> hydration.scene-panel-index (length panels))
            (mark-runtime-hydration-complete! world runtime hydration)))))

  (fn update-runtime-hydration! [world runtime]
    (local hydration (and runtime runtime.hydration))
    (when (and hydration
               hydration.ready?
               (not hydration.completed?))
      (start-runtime-hydration! world runtime hydration)
      (if (= hydration.phase "scene-panels")
          (restore-next-runtime-panel! world runtime hydration)
          (mark-runtime-hydration-complete! world runtime hydration))))

  (fn capture-runtime-state [world ctx opts]
    (local options (or opts {}))
    (local capture-reason (or options.reason "unknown"))
    (local runtime world.runtime)
    (local scene (and runtime runtime.scene))
    (local canvas (and runtime runtime.canvas))
    (local graph (and runtime runtime.graph))
    (local graph-map (and runtime runtime.graph-map))
    (local hud (and ctx ctx.hud))
    (local next-state (clone-table world.state))
    (when (and runtime.graph-view runtime.graph-view.capture-state)
        (runtime.graph-view:capture-state))
    (if (and runtime.graph-map-manager runtime.graph-map-manager.capture-state)
        (set next-state.graph
             (merge-preserved-graph-state
               graph
               next-state.graph
               (runtime.graph-map-manager:capture-state)))
        (and graph-map graph-map.capture-state)
        (set next-state.graph
             (merge-preserved-graph-state
               graph
               next-state.graph
               (graph-map:capture-state)))
        (and graph graph.capture-state)
        (set next-state.graph
             (merge-preserved-graph-state
               graph
               next-state.graph
               (graph:capture-state))))
    (when runtime
      (if (and runtime.board-view runtime.board-view.capture-state)
          (set next-state.board (runtime.board-view:capture-state))
          (when runtime.board-state
            (set next-state.board (clone-table runtime.board-state)))))
    (when (and scene scene.capture-state)
      (local captured-scene (scene:capture-state))
      ;; Ensure the sandbox session exists in next-state
      (when (not (= (type next-state.activity) :table))
        (set next-state.activity {}))
      (when (not (= (type next-state.activity.sessions) :table))
        (set next-state.activity.sessions {}))
      (when (not (= (type next-state.activity.sessions.sandbox) :table))
        (set next-state.activity.sessions.sandbox {}))
      (local existing-sandbox-scene (or next-state.activity.sessions.sandbox.scene
                                        (ActivitySceneState.empty-state)))
      (set captured-scene.panels
           (merge-panel-state
             captured-scene.panels
             (remaining-hydration-panels (and runtime runtime.hydration))))
      (when (= captured-scene.terrains nil)
        (TerrainIssueLog.warn (string.format
                                "[world] %s runtime terrain capture unavailable; preserving persisted terrains reason=%s scene=%s"
                                world.id
                                capture-reason
                                (tostring (and scene scene.debug-id)))))
      (set captured-scene.terrains
           (TerrainRecords.merge-preserved-records
             existing-sandbox-scene.terrains
             captured-scene.terrains))
      (assert captured-scene.lights "HomeWorld.capture-runtime-state requires scene lights")
      (assert captured-scene.skybox "HomeWorld.capture-runtime-state requires scene skybox")
      (assert captured-scene.background "HomeWorld.capture-runtime-state requires scene background")
      (set captured-scene.skybox
           (SkyboxState.normalize-complete-state
             (assert existing-sandbox-scene.skybox
                     "HomeWorld.capture-runtime-state requires persisted sandbox scene skybox policy")
             "HomeWorld.capture-runtime-state persisted skybox"))
      (drop-graph-node-view-panels! captured-scene)
      (set captured-scene.containment (resolve-runtime-containment-config world))
      ;; Write captured scene state into the sandbox activity session
      (set next-state.activity.sessions.sandbox.scene captured-scene))
    ;; Always capture runtime containment config into the sandbox session,
    ;; even when the scene surface is not available for state capture.
    (when (not next-state.activity)
      (set next-state.activity {}))
    (when (not next-state.activity.sessions)
      (set next-state.activity.sessions {}))
    (when (not next-state.activity.sessions.sandbox)
      (set next-state.activity.sessions.sandbox {}))
    (when (not next-state.activity.sessions.sandbox.scene)
      (set next-state.activity.sessions.sandbox.scene (ActivitySceneState.empty-state)))
    (set next-state.activity.sessions.sandbox.scene.containment
         (resolve-runtime-containment-config world))
    (local canvas-state
      (if (and canvas canvas.capture-state)
          (canvas:capture-state)
          (and next-state next-state.canvas)))
    (when canvas-state
      (drop-graph-node-view-panels! canvas-state)
      (set next-state.canvas canvas-state)
      (set next-state.activity
            (capture-activity-shell-state world runtime
                                          (or (and next-state next-state.activity) {}))))
    (when (and runtime
               (= app.active-world-runtime runtime)
               Activities.snapshot-activity-sessions)
      (set next-state.activity.sessions (Activities.snapshot-activity-sessions)))
    (when (and runtime runtime.drawing-controller)
      (set next-state.drawing
           (runtime.drawing-controller:snapshot)))
    (when (and hud hud.capture-state)
      (local hud-state (hud:capture-state))
      (drop-graph-node-view-panels! hud-state)
      (set next-state.hud hud-state))
    (set world.state next-state))

  (fn queue-runtime-restore-state [world]
    (local runtime world.runtime)
    (when runtime
      (set runtime.pending-canvas-state
           (clone-table (and world.state world.state.canvas)))
      (set runtime.pending-hud-state
           (clone-table (and world.state world.state.hud)))))

  (fn current-canvas-runtime-module []
    (local module (require :home-world-canvas-runtime))
    (assert (= (type module) :table)
            "HomeWorld requires :home-world-canvas-runtime to return a table")
    module)










  (fn drop-runtime-resources! [runtime]
    (when runtime
      (when (and runtime.graph-extension-registry-installed?
                 app.graph-extension-registry)
        (app.graph-extension-registry:uninstall-runtime runtime)
        (set runtime.graph-extension-registry-installed? false))
      (when runtime.scene
        (runtime.scene:drop)
        (set runtime.scene nil))
      (when runtime.graph-map-manager
        (when runtime.graph-map-sync-handler
          (runtime.graph-map-manager.maps-changed:disconnect runtime.graph-map-sync-handler true)
          (set runtime.graph-map-sync-handler nil))
        (runtime.graph-map-manager:drop)
        (set runtime.graph-map-manager nil))
      (when runtime.graph
        (runtime.graph:drop)
        (set runtime.graph nil))
      (set runtime.scene-scope nil))
    true)

  (fn setup-created-runtime! [world runtime graph-map-manager]
    (when (and app.graph-extension-registry
               (not runtime.graph-extension-registry-installed?))
      (app.graph-extension-registry:install-runtime runtime)
      (set runtime.graph-extension-registry-installed? true))
    ;; Install presentation provider on the runtime so renderers and input
    ;; helpers can query activity-owned cameras and render targets.
    (set runtime.presentation (Presentation.for-runtime runtime))
    (local sync-active-graph-map!
      (fn []
        (local active-graph-map (graph-map-manager:get-active-map))
        (set runtime.graph-map active-graph-map)
        (when (and runtime.scene runtime.scene.set-graph-map)
          (runtime.scene:set-graph-map active-graph-map))
        (when (= app.active-world-runtime runtime)
          (set app.graph-map active-graph-map)
          (set app.graph-map-manager graph-map-manager))
        active-graph-map))
    (set runtime.graph-map-sync-handler
         (graph-map-manager.maps-changed:connect (fn [_payload]
                                                   (sync-active-graph-map!))))
    (set runtime.load-canvas-runtime
         (fn [rt]
           (assert (= rt runtime) "HomeWorld.load-canvas-runtime called with wrong runtime")
           ((. (current-canvas-runtime-module) :load-runtime-canvas-surface!) world runtime)))
    (set runtime.unload-canvas-runtime
         (fn [rt]
           (assert (= rt runtime) "HomeWorld.unload-canvas-runtime called with wrong runtime")
           ((. (current-canvas-runtime-module) :drop-runtime-canvas-surface!) runtime)))
    (set runtime.capture-canvas-unit-state
         (fn [rt]
           (assert (= rt runtime) "HomeWorld.capture-canvas-unit-state called with wrong runtime")
           ((. (current-canvas-runtime-module) :capture-runtime-canvas-unit-state) world runtime)))
    (set runtime.restore-canvas-unit-state
         (fn [rt state]
           (assert (= rt runtime) "HomeWorld.restore-canvas-unit-state called with wrong runtime")
           ((. (current-canvas-runtime-module) :restore-runtime-canvas-unit-state!) runtime state)))
    (set runtime.restore-workspace-shell-state
         (fn [rt canvas-target]
             (when (and canvas-target rt.pending-canvas-state)
               (canvas-target:restore-shell-state rt.pending-canvas-state))))
    (set runtime.restore-surface-state
         (fn [rt canvas-target hud]
           (when (and canvas-target canvas-target.restore-state rt.pending-canvas-state)
             (canvas-target:restore-state rt.pending-canvas-state)
             (set rt.pending-canvas-state nil))
           (when (and hud hud.restore-state rt.pending-hud-state)
             (hud:restore-state rt.pending-hud-state)
             (set rt.pending-hud-state nil))))
    (runtime:load-canvas-runtime)
    runtime)

  (fn create-runtime [world ctx]
    ;; Create a default scene surface camera.  Activity slots (e.g. sandbox)
    ;; will install their own cameras via slot:set-camera and the scene's
    ;; resolve-active-camera will prefer the active slot's camera.
    (local default-scene-camera (Camera {:position (glm.vec3 0 0 30)}))
    (local canvas-state (or (and world.state world.state.canvas) {}))
    (local activity-state (or (and world.state world.state.activity) {}))
    (local graph (Graph {:with-start false :entity-events? false}))

    (local restore-runtime {:graph graph})
    (var restore-runtime-installed? false)
    (when app.graph-extension-registry
      (local (install-ok install-result) (pcall #(app.graph-extension-registry:install-runtime restore-runtime)))
      (if install-ok
          (set restore-runtime-installed? true)
          (do (graph:drop) (error install-result))))
    (local (map-manager-ok graph-map-manager)
      (pcall #(GraphMapManager.GraphMapManager
                {:graph graph
                 :state (or world.state.graph {})
                 :data-dir world.dir})))
    (when restore-runtime-installed?
      (app.graph-extension-registry:uninstall-runtime restore-runtime))
    (when (not map-manager-ok)
      (graph:drop)
      (error graph-map-manager))
    (local graph-map (graph-map-manager:get-active-map))
    (local scene-scope
      (do
        (local scope
          (ctx.focus-manager:create-scope {:name (.. "scene:" world.id)
                                           :directional-traversal-boundary? true}))
        (ctx.focus-manager:attach scope ctx.focus-root)
        scope))
    (local scene
      (Scene {:focus-manager ctx.focus-manager
              :debug-id (.. "scene:" world.id)
              :focus-scope scene-scope
              :camera default-scene-camera
              :icons ctx.icons
              :states ctx.states
              :movables ctx.movables
               :on-terrains-changed
               (fn [updated-scene]
                 (local manager (and updated-scene updated-scene.active-containment-manager
                                    (updated-scene:active-containment-manager)))
                 (when manager
                   (manager:schedule-refresh
                     {:scene updated-scene
                      :config (resolve-runtime-containment-config world)})))
               :graph graph
              :graph-map graph-map}))
    (local drawing-state
      (DrawingDocument.normalize-state
        (or world.state.drawing
            (DrawingDocument.default-state))))
    (local drawing-controller
      (DrawingController {:document drawing-state.document
                          :ui drawing-state.ui
                          :data_dir world.dir}))
    ;; Create an empty Scene surface; sandbox activity activation will populate it.
    (local sandbox-scene-state (resolve-sandbox-scene-state world))
    (scene:ensure-activity-slot "sandbox")
    ;; Store serialized containment config for later use by Scene slot activation,
    ;; but do NOT install containment into the physics world here — only the
    ;; active Scene slot calls ensure-installed.
    (local containment-config
      (resolve-runtime-containment-config world))
    (set-runtime-containment-config! world containment-config)
    (local runtime
      {:world-dir world.dir
       :focus-manager ctx.focus-manager
       :focus-root ctx.focus-root
       :icons ctx.icons
       :states ctx.states
       :movables ctx.movables
        :scene-scope scene-scope
        :scene scene
        :graph graph
        :graph-map graph-map
        :graph-map-manager graph-map-manager
        :drawing-controller drawing-controller
        :active-activity-id nil
        :requested-activity-id activity-state.active_id
        :requested-activity-known? true
        :activity-session-state (clone-table (or activity-state.sessions {}))
        :activity-cameras {:scene {} :canvas {}}
        :activity-controls {:scene {} :canvas {}}
        :graph-view-states (clone-table (and activity-state.sessions
                                             activity-state.sessions.graph
                                             activity-state.sessions.graph.graph-view-states))
        :graph-view-state (clone-table (and activity-state.sessions
                                            activity-state.sessions.graph
                                            activity-state.sessions.graph.graph-view-state))
        :preferred-interaction-surface
        (resolve-runtime-interaction-surface (or activity-state.preferred_interaction_surface "scene"))
        :pending-canvas-state (clone-table world.state.canvas)
        :pending-hud-state (clone-table world.state.hud)
        :board-state (clone-table (or world.state.board {:items [] :connectors []}))
        :hydration {:phase "scene-panels"
                   :ready? false
                   :started? false
                   :completed? false
                   :start-scheduled? false
                   :scene-panels (clone-table (and sandbox-scene-state sandbox-scene-state.panels []))
        :scene-panel-index 1}})
    (local (setup-ok setup-result)
      (pcall setup-created-runtime! world runtime graph-map-manager))
    (if setup-ok
        setup-result
        (do
          (drop-runtime-resources! runtime)
          (error setup-result))))

  (fn clear-runtime [world ctx reason]
    (local runtime world.runtime)
    (when (and app app.set-startup-physics-paused)
      (app.set-startup-physics-paused world.id false))
    (when runtime
      (capture-runtime-state world ctx {:reason (or reason "clear-runtime")})
      (clear-active-runtime-containment! world)
      (runtime:unload-canvas-runtime)
      (set runtime.drawing-controller nil)
      (drop-runtime-resources! runtime)
      (set world.runtime nil)
      (when reason
        (logging.info (string.format "[world] %s runtime cleared (%s)" world.id reason)))))

  (fn init [world _ctx]
    (when (not world.initialized?)
      (ensure-world-dir)
      (load-state world)
      (set world.initialized? true)))

  (fn activate [world ctx]
    (world:init ctx)
    (var created-runtime? false)
    (when (not world.runtime)
      (set world.runtime (create-runtime world ctx))
      (set created-runtime? true))
    (apply-runtime-physics-policy!)
    (when created-runtime?
      (schedule-runtime-hydration-start! world world.runtime))
    (set world.active? true)
    (when (hydration-pending? world.runtime)
      (schedule-runtime-hydration-start! world world.runtime))
    (sync-startup-physics-pause! world))

  (fn deactivate [world ctx reason]
    (capture-runtime-state world ctx {:reason (or reason "deactivate")})
    (queue-runtime-restore-state world)
    (clear-active-runtime-containment! world)
    (set world.active? false)
    (sync-startup-physics-pause! world)
    (when reason
      (logging.info (string.format "[world] %s deactivated (%s)" world.id reason))))

  (fn suspend [world ctx]
    (clear-runtime world ctx "suspend"))

  (fn resume [world ctx]
    (var created-runtime? false)
    (when (not world.runtime)
      (set world.runtime (create-runtime world ctx))
      (set created-runtime? true))
    (apply-runtime-physics-policy!)
    (when created-runtime?
      (schedule-runtime-hydration-start! world world.runtime))
    (set world.active? true)
    (when (hydration-pending? world.runtime)
      (schedule-runtime-hydration-start! world world.runtime))
    (sync-startup-physics-pause! world))

  (fn drop [world ctx reason]
    (set world.active? false)
    (sync-startup-physics-pause! world)
    (clear-runtime world ctx (or reason "drop"))
    (save-state world))

  (fn update [world delta opts]
    (local runtime world.runtime)
    (local active? (if (and opts (not (= opts.active? nil)))
                       opts.active?
                       world.active?))
    (when (and active?
                 runtime
                 app.activity-update)
      (app.activity-update {:world world
                            :runtime runtime
                            :delta delta}))
    nil)

  (fn get-runtime [world]
    world.runtime)

  (fn get-hud-contrib [world]
    (local runtime world.runtime)
    (if runtime
        {:left_dock_builder (ActivityDockView
                              {:top-reserve-height-provider
                               (fn [] (or app.activity-top-toolbar-height 0))})}
        nil))

  (set self.init init)
  (set self.activate activate)
  (set self.deactivate deactivate)
  (set self.suspend suspend)
  (set self.resume resume)
  (set self.drop drop)
  (set self.update update)
  (set self.get-runtime get-runtime)
  (set self.get-hud-contrib get-hud-contrib)
  (set self.save-state save-state)
  self)

HomeWorld
