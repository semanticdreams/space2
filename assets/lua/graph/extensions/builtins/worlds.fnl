(local Common (require :graph/extensions/builtins/common))
(local {:WorldsNode WorldsNode} (require :graph/nodes/worlds))
(local {:WorldNode WorldNode} (require :graph/nodes/world))
(local {:WorldActivitiesNode WorldActivitiesNode} (require :graph/nodes/world-activities))
(local {:WorldActivityNode WorldActivityNode} (require :graph/nodes/world-activity))
(local {:ActivitySurfacesNode ActivitySurfacesNode} (require :graph/nodes/activity-surfaces))
(local {:ActivitySurfaceNode ActivitySurfaceNode} (require :graph/nodes/activity-surface))
(local {:ScenePanelsNode ScenePanelsNode} (require :graph/nodes/scene-panels))
(local {:HudPanelsNode HudPanelsNode} (require :graph/nodes/hud-panels))
(local {:TerrainsNode TerrainsNode} (require :graph/nodes/terrains))
(local {:SkyboxNode SkyboxNode} (require :graph/nodes/skybox))
(local {:BackgroundNode BackgroundNode} (require :graph/nodes/background))
(local {:LightsNode LightsNode} (require :graph/nodes/lights))
(local {:LightTypeNode LightTypeNode} (require :graph/nodes/light-type))
(local {:LightNode LightNode} (require :graph/nodes/light))
(local {:ScenePanelNode ScenePanelNode} (require :graph/nodes/scene-panel))
(local {:HudPanelNode HudPanelNode} (require :graph/nodes/hud-panel))
(local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))
(local TerrainEditors (require :graph/terrain-editors))
(local TerrainTools (require :graph/terrain-tools))
(local WorldData (require :graph/world-data))

(local schemes
  ["worlds" "world" "world-activities" "world-activity" "activity-surfaces" "activity-surface"
   "activity-scene" "activity-hud" "activity-canvas" "activity-scene-panels" "activity-terrains"
   "activity-skybox" "activity-background" "activity-lights" "activity-scene-panel" "activity-terrain"
   "activity-light-type" "activity-light" "activity-terrain-editor" "activity-terrain-tool" "hud-panels" "hud-panel"])

(fn loader-opts [ctx]
  {:owner-id ctx.owner-id :extension-id ctx.extension-id})

(fn activity-surface-key [surface-key]
  (if (= surface-key "scene") "activity-scene"
      (= surface-key "hud") "activity-hud"
      (= surface-key "canvas") "activity-canvas"
      (error (.. "unsupported activity surface " (tostring surface-key)))))

(fn activity-pair-loader [prefix make-node]
  (Common.prefix-loader prefix
    (fn [rest key]
      (local parts (Common.split-key-parts rest))
      (when (= (length parts) 2)
        (make-node (. parts 1) (. parts 2) key)))))

(fn activity-triple-loader [prefix make-node]
  (Common.prefix-loader prefix
    (fn [rest key]
      (local parts (Common.split-key-parts rest))
      (when (= (length parts) 3)
        (make-node (. parts 1) (. parts 2) (. parts 3) key)))))

(fn activity-quad-loader [prefix make-node]
  (Common.prefix-loader prefix
    (fn [rest key]
      (local parts (Common.split-key-parts rest))
      (when (= (length parts) 4)
        (make-node (. parts 1) (. parts 2) (. parts 3) (. parts 4) key)))))

(fn resolve-activity-scene [world-manager world-id activity-id]
  (and world-manager
       (WorldData.resolve-activity-surface-state world-manager world-id activity-id "scene")))

(fn make-activity-surface-loader [world-manager asset-path-resolver surface-key]
  (activity-pair-loader (.. (activity-surface-key surface-key) ":")
    (fn [world-id activity-id key]
      (local surface-state
        (and world-manager
             (WorldData.resolve-activity-surface-state world-manager world-id activity-id surface-key)))
      (when surface-state
        (ActivitySurfaceNode {:world-id world-id
                              :activity-id activity-id
                              :surface-key surface-key
                              :world-manager world-manager
                              :asset-path-resolver asset-path-resolver
                              :key key})))))

(fn register-activity-scene-category-loaders [handles graph ctx world-manager asset-path-resolver]
  (fn make-scene-panels [world-id activity-id key]
    (when (resolve-activity-scene world-manager world-id activity-id)
      (ScenePanelsNode {:world-id world-id :activity-id activity-id :world-manager world-manager :key key})))
  (fn make-terrains [world-id activity-id key]
    (when (resolve-activity-scene world-manager world-id activity-id)
      (TerrainsNode {:world-id world-id :activity-id activity-id :world-manager world-manager :key key})))
  (fn make-skybox [world-id activity-id key]
    (when (resolve-activity-scene world-manager world-id activity-id)
      (SkyboxNode {:world-id world-id :activity-id activity-id :world-manager world-manager :asset-path-resolver asset-path-resolver :key key})))
  (fn make-background [world-id activity-id key]
    (when (resolve-activity-scene world-manager world-id activity-id)
      (BackgroundNode {:world-id world-id :activity-id activity-id :world-manager world-manager :key key})))
  (fn make-lights [world-id activity-id key]
    (when (resolve-activity-scene world-manager world-id activity-id)
      (LightsNode {:world-id world-id :activity-id activity-id :world-manager world-manager :key key})))
  (table.insert handles (graph:register-key-loader "activity-scene-panels"
    (activity-pair-loader "activity-scene-panels:" make-scene-panels)
    (loader-opts ctx)))
  (table.insert handles (graph:register-key-loader "activity-terrains"
    (activity-pair-loader "activity-terrains:" make-terrains)
    (loader-opts ctx)))
  (table.insert handles (graph:register-key-loader "activity-skybox"
    (activity-pair-loader "activity-skybox:" make-skybox)
    (loader-opts ctx)))
  (table.insert handles (graph:register-key-loader "activity-background"
    (activity-pair-loader "activity-background:" make-background)
    (loader-opts ctx)))
  (table.insert handles (graph:register-key-loader "activity-lights"
    (activity-pair-loader "activity-lights:" make-lights)
    (loader-opts ctx))))

(fn register-activity-scene-child-loaders [handles graph ctx world-manager]
  (fn make-scene-panel [world-id activity-id index-text key]
    (local panel-index (tonumber index-text))
    (local panel-entry (and panel-index (resolve-activity-scene world-manager world-id activity-id)
                            (WorldData.find-scene-panel world-manager world-id activity-id panel-index)))
    (when panel-entry
      (ScenePanelNode {:world-id world-id :activity-id activity-id :world-manager world-manager :panel-index panel-index :panel-entry panel-entry :key key})))
  (fn make-terrain [world-id activity-id terrain-id key]
    (local terrain-entry (and (resolve-activity-scene world-manager world-id activity-id)
                              (WorldData.find-terrain world-manager world-id activity-id terrain-id)))
    (when terrain-entry
      (TerrainNode {:world-id world-id :activity-id activity-id :world-manager world-manager :terrain-id terrain-id :terrain-entry terrain-entry :key key})))
  (fn make-light-type [world-id activity-id type-key key]
    (when (resolve-activity-scene world-manager world-id activity-id)
      (LightTypeNode {:world-id world-id :activity-id activity-id :world-manager world-manager :type-key type-key :key key})))
  (fn make-light [world-id activity-id type-key light-id key]
    (local light-entry (and (resolve-activity-scene world-manager world-id activity-id)
                            (WorldData.find-light world-manager world-id activity-id type-key light-id)))
    (when light-entry
      (LightNode {:world-id world-id :activity-id activity-id :world-manager world-manager :type-key type-key :light-id light-id :light-entry light-entry :key key})))
  (table.insert handles (graph:register-key-loader "activity-scene-panel"
    (activity-triple-loader "activity-scene-panel:" make-scene-panel)
    (loader-opts ctx)))
  (table.insert handles (graph:register-key-loader "activity-terrain"
    (activity-triple-loader "activity-terrain:" make-terrain)
    (loader-opts ctx)))
  (table.insert handles (graph:register-key-loader "activity-light-type"
    (activity-triple-loader "activity-light-type:" make-light-type)
    (loader-opts ctx)))
  (table.insert handles (graph:register-key-loader "activity-light"
    (activity-quad-loader "activity-light:" make-light)
    (loader-opts ctx))))

(fn register-activity-terrain-action-loaders [handles graph ctx world-manager]
  (fn make-terrain-editor [world-id activity-id terrain-id key]
    (local terrain-entry (and (resolve-activity-scene world-manager world-id activity-id)
                              (WorldData.find-terrain world-manager world-id activity-id terrain-id)))
    (when terrain-entry
      (TerrainEditors.create-editor-node {:world-id world-id :activity-id activity-id :world-manager world-manager :terrain-id terrain-id :terrain-entry terrain-entry :key key})))
  (fn make-terrain-tool [world-id activity-id terrain-id tool-id key]
    (local terrain-entry (and (resolve-activity-scene world-manager world-id activity-id)
                              (WorldData.find-terrain world-manager world-id activity-id terrain-id)))
    (local terrain-kind (and terrain-entry terrain-entry.kind))
    (when terrain-kind
      (TerrainTools.create-tool-node {:world-id world-id :activity-id activity-id :world-manager world-manager :terrain-id terrain-id :terrain-kind terrain-kind :tool-id tool-id :key key})))
  (table.insert handles (graph:register-key-loader "activity-terrain-editor"
    (activity-triple-loader "activity-terrain-editor:" make-terrain-editor)
    (loader-opts ctx)))
  (table.insert handles (graph:register-key-loader "activity-terrain-tool"
    (activity-quad-loader "activity-terrain-tool:" make-terrain-tool)
    (loader-opts ctx))))

(fn install-loaders [options graph ctx]
  (local world-manager options.world-manager)
  (local asset-path-resolver options.asset-path-resolver)
  (local handles [])
  (fn add! [handle] (table.insert handles handle))
  (fn make-worlds []
    (when world-manager
      (WorldsNode {:world-manager world-manager :asset-path-resolver asset-path-resolver})))
  (fn make-world [world-id key]
    (local world-entry (and world-manager (WorldData.resolve-world-entry world-manager world-id)))
    (when world-entry
      (WorldNode {:world-id world-id :world-manager world-manager :asset-path-resolver asset-path-resolver :world-entry world-entry :key key})))
  (fn make-world-activities [world-id key]
    (local world-entry (and world-manager (WorldData.resolve-world-entry world-manager world-id)))
    (when world-entry
      (WorldActivitiesNode {:world-id world-id :world-manager world-manager :key key})))
  (fn make-world-activity [world-id activity-id key]
    (local session (and world-manager (WorldData.resolve-activity-session world-manager world-id activity-id)))
    (when session
      (WorldActivityNode {:world-id world-id :activity-id activity-id :world-manager world-manager :key key})))
  (fn make-activity-surfaces [world-id activity-id key]
    (local session (and world-manager (WorldData.resolve-activity-session world-manager world-id activity-id)))
    (when session
      (ActivitySurfacesNode {:world-id world-id :activity-id activity-id :world-manager world-manager :asset-path-resolver asset-path-resolver :key key})))
  (fn make-hud-panels [world-id key]
    (when world-manager
      (HudPanelsNode {:world-id world-id :world-manager world-manager :key key})))
  (fn make-hud-panel [rest key]
    (local parts (Common.split-key-parts rest))
    (when (>= (length parts) 3)
      (local world-id (. parts 1))
      (local layer (. parts 2))
      (local panel-index (tonumber (. parts 3)))
      (local panel-entry (and world-manager panel-index
                              (WorldData.find-hud-panel world-manager world-id layer panel-index)))
      (when panel-entry
        (HudPanelNode {:world-id world-id :world-manager world-manager :layer layer :panel-index panel-index :panel-entry panel-entry :key key}))))
  (add! (graph:register-key-loader "worlds"
    (Common.exact-key-loader "worlds" make-worlds)
    (loader-opts ctx)))
  (add! (graph:register-key-loader "world"
    (Common.prefix-loader "world:" make-world)
    (loader-opts ctx)))
  (add! (graph:register-key-loader "world-activities"
    (Common.prefix-loader "world-activities:" make-world-activities)
    (loader-opts ctx)))
  (add! (graph:register-key-loader "world-activity"
    (activity-pair-loader "world-activity:" make-world-activity)
    (loader-opts ctx)))
  (add! (graph:register-key-loader "activity-surfaces"
    (activity-pair-loader "activity-surfaces:" make-activity-surfaces)
    (loader-opts ctx)))
  (each [_ surface-key (ipairs ["scene" "hud" "canvas"])]
    (add! (graph:register-key-loader (activity-surface-key surface-key)
            (make-activity-surface-loader world-manager asset-path-resolver surface-key)
            (loader-opts ctx))))
  (register-activity-scene-category-loaders handles graph ctx world-manager asset-path-resolver)
  (register-activity-scene-child-loaders handles graph ctx world-manager)
  (register-activity-terrain-action-loaders handles graph ctx world-manager)
  (add! (graph:register-key-loader "hud-panels"
    (Common.prefix-loader "hud-panels:" make-hud-panels)
    (loader-opts ctx)))
  (add! (graph:register-key-loader "hud-panel"
    (Common.prefix-loader "hud-panel:" make-hud-panel)
    (loader-opts ctx)))
  handles)

(fn descriptors [opts]
  (local options (if opts opts {}))
  (fn install [graph ctx]
    (install-loaders options graph ctx))
  [(Common.descriptor
     {:id "builtin-graph-worlds"
      :unit-id "builtin-graph-worlds"
      :schemes schemes
      :install-loaders install})])

{:descriptors descriptors}
