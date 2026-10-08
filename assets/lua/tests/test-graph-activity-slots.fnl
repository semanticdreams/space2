(local glm (require :glm))
(local fs (require :fs))
(local Main (require :main))
(local Activities (require :activities))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map)) (local GraphMapManager (require :graph/map-manager))
(local Commands (require :commands/core))
(local Scene (require :scene))
(local Canvas (require :canvas))
(local Camera (require :camera))
(local ObjectSelector (require :object-selector))
(local GraphActivityUnit (require :graph-activity-unit))
(local RootContextActions (require :root-context-menu-actions))
(local DrawingController (require :drawing/controller))
(local DrawingActivityUnit (require :drawing-activity-unit))
(local BoardActivityUnit (require :board-activity-unit))
(local Rectangle (require :rectangle))
(local {: FocusManager} (require :focus))

(local tests [])

(fn restore-app-fields! [snapshot]
  (each [_ key (ipairs snapshot.keys)]
    (set (. app key) (. snapshot.values key)))
  true)

(fn snapshot-app-fields [keys]
  (local snapshot {:keys keys
                   :values {}})
  (each [_ key (ipairs keys)]
    (set (. snapshot.values key) (. app key)))
  snapshot)

(fn make-font-stub []
  (local glyph {:advance 1})
  {:metadata {:metrics {:ascender 1 :descender -0.25 :lineHeight 1.25}
              :atlas {:width 1 :height 1}}
   :glyph-map {65533 glyph}})

(fn make-icons-stub []
  (local font (make-font-stub))
  (local codepoints {:close 4242
                     :code 4242
                     :move_item 4242
                     :table 4242})
  {:font font
   :get (fn [_self name]
          (local value (. codepoints name))
          (assert value (.. "Missing icon " name))
          value)
   :resolve (fn [self name]
              {:type :font
               :codepoint (self:get name)
               :font self.font})})

(fn test-theme []
  {:font (make-font-stub)
   :graph {:background (glm.vec4 0.18 0.19 0.21 1)
           :selection-border-color (glm.vec4 1 0.6 0.2 1)
           :label-color (glm.vec4 1 1 1 1)
           :label-target-pixels 13.0
           :label-min-scale 4.0
           :edge-color (glm.vec4 0.6 0.6 0.6 1)}
   :input {:focus-outline (glm.vec4 0.2 0.6 1 1)}})

(fn make-panel-node []
  {:key "test-panel-node:one"
   :label "Panel Node"
   :view (fn [_node]
           (Rectangle {:color (glm.vec4 0.1 0.8 0.3 1)}))})

(fn count-clickables-for-target [target]
  (local clickables (assert app.clickables "graph activity slot test requires app.clickables")) (var count 0)
  (each [_ object (ipairs (or clickables.left-click-objects []))]
    (when (= object.pointer-target target)
      (set count (+ count 1))))
  count)

(fn assert-graph-provider-resolves-runtime-map [runtime]
  (local runtime-map-calls {:add-start 0})
  (local runtime-map {:add-start-node! (fn [_self]
                                        (set runtime-map-calls.add-start (+ runtime-map-calls.add-start 1))
                                        true)})
  (local runtime-manager {:get-active-map (fn [_self] runtime-map)})
  (set runtime.graph-map-manager runtime-manager)
  (set runtime.graph-map runtime-map)
  (local composed (Commands.compose app.activity-leader-command-providers {}))
  (assert (Commands.run composed "graph.map.add-start" {})
          "Graph activity leader provider should run map command")
  (assert (= runtime-map-calls.add-start 1)
          "Graph activity provider should resolve current runtime active map at run time"))

(fn graph-activity-builds-view-in-canvas-slot []
  (local app-keys [:active-world-runtime
                    :canvas
                    :graph-map
                    :graph-map-manager
                    :graph-view :activity-leader-command-providers
                    :activity-registry
                   :activities-changed
                   :active-activity-id
                   :active-interaction-surface
                   :preferred-interaction-surface
                   :active-pointer-controls
                   :scene-interactive?
                   :canvas-interactive?
                   :canvas-surface-interactive?
                   :canvas-visible?
                   :canvas-controls
                   :first-person-controls
                   :viewport
                   :themes])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.themes {:get-active-theme test-theme})
  (local data-dir "/tmp/space/tests/graph-activity-slots")
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (fs.create-dirs data-dir)
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "graph-activity-slot-test"}))
  (local canvas (Canvas {:camera camera
                          :focus-manager focus-manager}))
  (local AppProjection (require :app-projection))
  (when (not app.create-default-projection)
    (set app.create-default-projection AppProjection.create-default-projection))
  (local scene (Scene {:camera camera}))
  (set app.viewport {:x 0 :y 0 :width 800 :height 600})
  (canvas:on-viewport-changed app.viewport)
  (scene:on-viewport-changed app.viewport)
  (local graph (Graph {:with-start false})) (local graph-map-manager (GraphMapManager.GraphMapManager {:graph graph}))
  (local graph-map (graph-map-manager:get-active-map))
  (local object-selector (ObjectSelector {:ctx-provider (fn []
                                                         (or (and canvas.active-activity-slot
                                                                  canvas.active-activity-slot.ctx)
                                                             canvas.build-context))
                                           :enabled? true}))
  (local runtime {:canvas canvas
                  :scene scene
                  :graph graph
                  :graph-map graph-map :graph-map-manager graph-map-manager
                  :object-selector object-selector
                  :movables app.movables
                  :activity-cameras {:canvas {} :scene {}}
                  :activity-controls {:canvas {} :scene {}}
                  :world-dir data-dir})

  (set app.active-world-runtime runtime)
  (set app.canvas canvas)
  (set app.graph-map graph-map) (set app.graph-map-manager graph-map-manager)
  ;; Pre-create canvas slots with activity-owned cameras so
  ;; active-slot camera resolution does not fall back to the
  ;; canvas constructor camera.
  (canvas:ensure-activity-slot "graph" {:camera camera})
  (local (ok result)
    (pcall
      (fn []
        (GraphActivityUnit.load-graph-activity!)
        (Activities.activate-activity "graph")
        (local slot (canvas:activity-slot "graph"))
        (assert slot "Graph activity should create a graph canvas slot")
        (assert (= canvas.active-activity-slot slot)
                "Graph activity should activate its canvas slot")
        (assert (= slot.pointer-target.canvas-target-kind :graph-view)
                "Graph activity slot should expose graph view target kind")
        (assert app.graph-view "Graph activity should create a graph view") (assert (> (length (assert app.activity-leader-command-providers "Graph activity should install graph leader command providers")) 0) "Graph activity should install graph leader command providers")
        (assert-graph-provider-resolves-runtime-map runtime)
        (set runtime.graph-map-manager graph-map-manager)
        (set runtime.graph-map graph-map)
        (assert (= app.graph-view.ctx slot.ctx)
                "Graph view should be built with the graph slot context")
        (assert (= app.graph-view.ctx.pointer-target slot.pointer-target)
                "Graph view context should route interactions through the graph slot pointer target")
        (assert (= app.graph-view.ctx.panel-target slot)
                "Graph view panels should route through the graph slot panel target")
        (local root-context (RootContextActions.empty-context :canvas))
        (assert (= root-context.targets.canvas slot)
                "Graph activity actions should receive the graph slot as the canvas panel target")
        (assert (= (canvas:get-triangle-vector) slot.ctx.triangle-vector)
                "Active graph slot draw data should be exposed by the canvas")
        (assert (not (= (canvas:get-triangle-vector) canvas.build-context.triangle-vector))
                "Graph activity should not draw through the default canvas context")
        (object-selector:on-mouse-button {:button 1 :state true :x 100 :y 100})
        (assert (> (length (slot.ctx:get-quad-draw-list)) 0)
                "Graph selector rectangle should draw through the active graph slot context")
        (assert (= (length (canvas.build-context:get-quad-draw-list)) 0)
                "Graph selector rectangle should not draw through the default canvas context")
        (object-selector:cancel-selection)
        (Activities.deactivate-active-activity)
        (assert (not slot.visible?)
                "Deactivating graph activity should hide the graph slot")
        (assert (not app.graph-view) "Deactivating graph activity should stop exposing app.graph-view") (assert (= app.activity-leader-command-providers nil) "Deactivating graph activity should clear graph leader command providers")
         true)))
  (pcall GraphActivityUnit.unload-graph-activity!)
  (when runtime.graph-view
    (runtime.graph-view:drop)
    (set runtime.graph-view nil))
  (object-selector:drop)
  (graph-map-manager:drop)
  (graph:drop)
  (scene:drop)
  (canvas:drop)
  (focus-manager:drop)
  (camera:drop)
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Graph activity builds view in canvas activity slot"
                      :fn graph-activity-builds-view-in-canvas-slot})

(fn graph-panels-are-confined-to-graph-slot-after-activity-switch []
  (local app-keys [:active-world-runtime
                   :canvas
                   :graph
                   :graph-map
                   :graph-map-manager
                   :graph-view
                   :drawing-controller
                   :drawing-render
                   :board
                   :board-view
                   :activity-registry
                   :activities-changed
                   :active-activity-id
                   :active-interaction-surface
                   :preferred-interaction-surface
                   :active-pointer-controls
                   :scene-interactive?
                   :canvas-interactive?
                   :canvas-surface-interactive?
                   :canvas-visible?
                   :activity-target-enabled?
                   :pointer-target-enabled?
                   :canvas-controls
                   :first-person-controls
                   :set-canvas-visible
                   :set-active-interaction-surface
                   :sync-interaction-surface-state
                   :viewport
                   :themes
                   :renderers
                   :lights
                   :engine])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.canvas-visible? false)
  (set app.canvas-interactive? false)
  (set app.canvas-surface-interactive? true)
  (set app.active-interaction-surface :scene)
  (set app.preferred-interaction-surface :scene)
  (Main.install-app-shell!)
  (set app.themes {:get-active-theme test-theme})
  (set app.set-canvas-visible
       (fn [visible?]
         (set app.canvas-visible? (and app.canvas (not (= visible? false))))
         (when app.sync-interaction-surface-state
           (app.sync-interaction-surface-state :test-visible nil))))
  (set app.set-active-interaction-surface
       (fn [surface _opts]
         (set app.preferred-interaction-surface surface)
         (when app.sync-interaction-surface-state
           (app.sync-interaction-surface-state :test-surface nil))))
  (local data-dir "/tmp/space/tests/graph-activity-slot-panels")
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (fs.create-dirs data-dir)
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "graph-activity-slot-panel-test"}))
  (local canvas (Canvas {:camera camera
                         :focus-manager focus-manager
                         :icons (make-icons-stub)}))
  (local AppProjection (require :app-projection))
  (when (not app.create-default-projection)
    (set app.create-default-projection AppProjection.create-default-projection))
  (local scene (Scene {:camera camera}))
  ;; Mock services needed by scene:activate-activity-slot and scene:capture-activity-slot-state
  (local SkyboxState (require :skybox-state))
  (local BackgroundState (require :background-state))
  (var skybox-state {:enabled? false :name "lake" :brightness 0.5 :tint-color [1.0 1.0 1.0]})
  (set app.renderers {:skybox {:get-state (fn [_] skybox-state)
                               :set-state (fn [_ state] (set skybox-state (SkyboxState.normalize-resolved-state state "skybox-mock")))}
                      :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
                      :set-background-state (fn [_ state] (set app.background-state (BackgroundState.normalize-complete-state state "bg-mock")))})
  (var mock-lights-state {:ambient {:enabled? false :color [0.1 0.1 0.1] :intensity 1.0} :directional [] :point [] :spot []})
  (set app.lights {:get-state (fn [_] mock-lights-state) :set-state (fn [_ state] (set mock-lights-state state))})
  (set app.engine {:physics {:addRigidBody (fn [_phys _body]) :removeRigidBody (fn [_phys _body])}})
  (set app.viewport {:x 0 :y 0 :width 800 :height 600})
  (canvas:on-viewport-changed app.viewport)
  (scene:on-viewport-changed app.viewport)
  (local graph (Graph {:with-start false}))
  (local panel-node (make-panel-node))
  (graph:register-key-loader "test-panel-node"
                             (fn [key]
                               (assert (= key panel-node.key)
                                       "Unexpected test graph key")
                               panel-node))
  (local graph-map-manager (GraphMapManager.GraphMapManager {:graph graph})) (local graph-map (graph-map-manager:get-active-map))
  (graph-map:load-by-key panel-node.key)
  (local object-selector (ObjectSelector {:ctx-provider (fn []
                                                         (or (and canvas.active-activity-slot
                                                                  canvas.active-activity-slot.ctx)
                                                             canvas.build-context))
                                           :enabled? true}))
  (local controller (DrawingController {:data_dir data-dir}))
  (controller:add-layer "vector")
  (local runtime {:canvas canvas
                  :scene scene
                  :graph graph
                  :graph-map graph-map :graph-map-manager graph-map-manager
                  :object-selector object-selector
                  :movables app.movables
                  :activity-cameras {:canvas {} :scene {}}
                  :activity-controls {:canvas {} :scene {}}
                  :world-dir data-dir
                  :drawing-controller controller
                  :board-state {:items [] :connectors []}})
  (set app.active-world-runtime runtime)
  (set app.canvas canvas)
  (set app.graph graph)
  (set app.graph-map graph-map) (set app.graph-map-manager graph-map-manager)
  (set app.drawing-controller controller)
  ;; Pre-create canvas slots with activity-owned cameras.
  (canvas:ensure-activity-slot "graph" {:camera camera})
  (canvas:ensure-activity-slot "drawing" {:camera camera})
  (canvas:ensure-activity-slot "board" {:camera camera})
  (local (ok result)
    (pcall
      (fn []
        (GraphActivityUnit.load-graph-activity!)
        (DrawingActivityUnit.load-drawing-activity!)
        (BoardActivityUnit.load-board-activity!)

        (Activities.activate-activity "graph")
        (local graph-slot (canvas:activity-slot "graph"))
        (assert graph-slot "Graph activity should create a graph slot")
        (local clickables-before-open (count-clickables-for-target graph-slot.pointer-target))
        (app.graph-view.views:open panel-node)
        (assert (= (length graph-slot.float.children) 1)
                "Graph node dialog should mount in the graph activity slot float")
        (assert (= (length canvas.float.children) 0)
                "Graph node dialog should not mount in the default canvas float")
        (assert (> (count-clickables-for-target graph-slot.pointer-target)
                   clickables-before-open)
                "Graph node dialog controls should register on the graph slot pointer target")
        (canvas:update)
        (assert (> (length (graph-slot.ctx:get-quad-draw-list)) 0)
                "Graph node dialog should draw through the graph slot context")
        (assert (= (length (canvas.build-context:get-quad-draw-list)) 0)
                "Graph node dialog should not draw through the default canvas context")
        (assert (app.pointer-target-enabled? graph-slot.pointer-target)
                "Graph panel pointer target should be enabled while graph is active")

        (Activities.activate-activity "drawing")
        (local drawing-slot (canvas:activity-slot "drawing"))
        (assert drawing-slot.visible?
                "Drawing slot should be visible after switching to drawing")
        (assert (not graph-slot.visible?)
                "Graph slot should hide after switching to drawing")
        (assert (= (length graph-slot.float.children) 1)
                "Inactive graph slot should retain its graph dialog")
        (assert (not (app.pointer-target-enabled? graph-slot.pointer-target))
                "Graph panel pointer target should be disabled while drawing is active")
        (assert (= (canvas:get-triangle-vector) drawing-slot.ctx.triangle-vector)
                "Canvas rendering should read vectors from the active drawing slot after graph deactivation")
        (assert (not (= (canvas:get-triangle-vector) graph-slot.ctx.triangle-vector))
                "Canvas rendering should stop reading vectors from the inactive graph slot")
        (assert (= (length (canvas:get-quad-draw-list))
                   (length (drawing-slot.ctx:get-quad-draw-list)))
                "Canvas quad rendering should match the active drawing slot after graph deactivation")

        (Activities.activate-activity "board")
        (local board-slot (canvas:activity-slot "board"))
        (assert board-slot.visible?
                "Board slot should be visible after switching to board")
        (assert (not graph-slot.visible?)
                "Graph slot should remain hidden after switching to board")
        (assert (not (app.pointer-target-enabled? graph-slot.pointer-target))
                "Graph panel pointer target should stay disabled while board is active")
        (assert (= (canvas:get-triangle-vector) board-slot.ctx.triangle-vector)
                "Canvas rendering should read vectors from the active board slot after graph deactivation")
        (assert (not (= (canvas:get-triangle-vector) graph-slot.ctx.triangle-vector))
                "Canvas rendering should keep ignoring vectors from the inactive graph slot")
        (assert (= (length (canvas:get-quad-draw-list))
                   (length (board-slot.ctx:get-quad-draw-list)))
                "Canvas quad rendering should match the active board slot after graph deactivation")
        true)))
  (pcall GraphActivityUnit.unload-graph-activity!)
  (pcall DrawingActivityUnit.unload-drawing-activity!)
  (pcall BoardActivityUnit.unload-board-activity!)
  (object-selector:drop)
  (graph-map-manager:drop)
  (graph:drop)
  (scene:drop)
  (canvas:drop)
  (focus-manager:drop)
  (camera:drop)
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Graph panels are confined to graph slot after activity switch"
                      :fn graph-panels-are-confined-to-graph-slot-after-activity-switch})

(fn graph-activity-scene-isolation-prevents-sandbox-inheritance []
  ;; When Sandbox has terrain/lights/etc and Graph activates, Graph's Scene
  ;; slot must be empty and must not inherit Sandbox content/environment.
  (local AppProjection (require :app-projection))
  (when (not app.create-default-projection)
    (set app.create-default-projection AppProjection.create-default-projection))
  (local ActivitySceneState (require :activity-scene-state))
  (local SkyboxState (require :skybox-state))
  (local BackgroundState (require :background-state))
  (local Scene (require :scene))
  (local SandboxActivityUnit (require :sandbox-activity-unit))
  (local app-keys [:active-world-runtime
                   :canvas
                   :graph
                   :graph-map
                   :graph-map-manager
                   :graph-view
                   :activity-registry
                   :activities-changed
                   :active-activity-id
                   :active-interaction-surface
                   :preferred-interaction-surface
                   :active-pointer-controls
                   :scene-interactive?
                   :canvas-interactive?
                   :canvas-surface-interactive?
                   :canvas-visible?
                   :canvas-controls
                   :first-person-controls
                   :set-canvas-visible
                   :set-active-interaction-surface
                   :sync-interaction-surface-state
                   :viewport
                   :themes
                   :lights
                   :renderers
                   :background-state
                   :skybox-state
                    :physics-containment-config
                    :engine
                    :pointer-target-enabled?
                    :camera
                    :scene])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.canvas-visible? false)
  (set app.canvas-interactive? false)
  (set app.canvas-surface-interactive? true)
  (set app.active-interaction-surface :scene)
  (set app.preferred-interaction-surface :scene)
  (Main.install-app-shell!)
  (set app.themes {:get-active-theme test-theme})
  (set app.set-canvas-visible
       (fn [visible?]
         (set app.canvas-visible? (and app.canvas (not (= visible? false))))
         (when app.sync-interaction-surface-state
           (app.sync-interaction-surface-state :test-visible nil))))
  (set app.set-active-interaction-surface
       (fn [surface _opts]
         (set app.preferred-interaction-surface surface)
         (when app.sync-interaction-surface-state
           (app.sync-interaction-surface-state :test-surface nil))))

  ;; Mock renderer services: lights, skybox, background
  (var skybox-state {:enabled? false
                     :name "lake"
                     :brightness 0.5
                     :tint-color [1.0 1.0 1.0]})
  (set app.renderers {:skybox {:get-state (fn [_] skybox-state)
                               :set-state (fn [_ state]
                                            (set skybox-state (SkyboxState.normalize-resolved-state state "skybox-mock")))}
                      :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
                      :set-background-state (fn [_ state]
                                               (set app.background-state (BackgroundState.normalize-complete-state state "bg-mock")))})
  ;; Mock lights
  (var mock-lights-state {:ambient {:enabled? false
                                    :color [0.1 0.1 0.1]
                                    :intensity 1.0}
                           :directional []
                           :point []
                           :spot []})
  (set app.lights {:get-state (fn [_] mock-lights-state)
                   :set-state (fn [_ state]
                                (set mock-lights-state state))})
  ;; Mock physics
  (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                              :removeRigidBody (fn [_phys _body])}})

  (local data-dir "/tmp/space/tests/graph-scene-isolation")
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (fs.create-dirs data-dir)
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "graph-scene-isolation-test"}))
  (local scene (Scene {:camera camera}))
  (local canvas (Canvas {:camera camera
                          :focus-manager focus-manager}))
  (set app.viewport {:x 0 :y 0 :width 800 :height 600})
  (canvas:on-viewport-changed app.viewport)
  (scene:on-viewport-changed app.viewport)
  (local graph (Graph {:with-start false}))
  (local graph-map-manager (GraphMapManager.GraphMapManager {:graph graph})) (local graph-map (graph-map-manager:get-active-map))
  (local object-selector (ObjectSelector {:ctx-provider (fn []
                                                         (or (and canvas.active-activity-slot
                                                                  canvas.active-activity-slot.ctx)
                                                             canvas.build-context))
                                           :enabled? true}))
  (local runtime {:canvas canvas
                  :scene scene
                  :graph graph
                  :graph-map graph-map :graph-map-manager graph-map-manager
                  :object-selector object-selector
                  :movables app.movables
                  :activity-cameras {:canvas {} :scene {}}
                  :activity-controls {:canvas {} :scene {}}
                  :world-dir data-dir})
  (set app.active-world-runtime runtime)
  (set app.canvas canvas)
  (set app.scene scene)
  (set app.graph graph)
  (set app.graph-map graph-map) (set app.graph-map-manager graph-map-manager)
  (local (ok result)
    (pcall
      (fn []
        (SandboxActivityUnit.load-sandbox-activity!)
        (GraphActivityUnit.load-graph-activity!)

        ;; Give sandbox a non-default scene state with terrain and enabled lights/skybox
        (local sandbox-state
          {:panels []
           :terrains [{:kind "heightfield-terrain"}]
           :lights {:ambient {:enabled? true :color [1.0 1.0 1.0] :intensity 1.0}
                    :directional []
                    :point []
                    :spot []}
           :skybox {:enabled? true
                    :name "lake"
                    :brightness 0.5
                    :tint-color [1.0 1.0 1.0]}
           :background {:color [0.2 0.3 0.4]}
           :containment {:enabled? true}})
        (scene:restore-activity-slot-state "sandbox" sandbox-state)

        ;; Activate Sandbox and verify services reflect sandbox state
        (Activities.activate-activity "sandbox")
        (assert (= scene.active-activity-slot-id "sandbox")
                "Scene should report sandbox as active slot")
        ;; Sandbox camera must be owned by the scene slot, not a global
        (assert (= app.camera nil)
                "Sandbox camera must be owned by the sandbox scene slot, not app.camera")
        (let [sb-slot (scene:activity-slot "sandbox")]
          (assert sb-slot "Sandbox scene slot must exist")
          (assert sb-slot.camera "Sandbox scene slot must own its camera"))
        (assert (. mock-lights-state :ambient :enabled?)
                "Sandbox activation should enable ambient light")
        (assert skybox-state.enabled?
                "Sandbox activation should enable skybox")
        ;; Background and containment should reflect sandbox state
        (assert (and app.background-state
                     (= (. app.background-state.color 1) 0.2)
                     (= (. app.background-state.color 2) 0.3)
                     (= (. app.background-state.color 3) 0.4))
                "Sandbox activation should apply custom background color")
        (let [sb-slot (scene:activity-slot "sandbox")
              sb-manager (and sb-slot sb-slot.physics-containment-manager)]
          (assert (and sb-manager sb-manager.config sb-manager.config.enabled?)
                  "Sandbox containment should be enabled"))
        ;; Sandbox pointer target should be enabled while sandbox is active
        (let [sb-slot (scene:activity-slot "sandbox")]
          (assert (app.pointer-target-enabled? (. sb-slot :pointer-target))
                  "Sandbox pointer target should be enabled while sandbox is active"))

        ;; Switch to Graph
        (Activities.activate-activity "graph")
        (assert (= scene.active-activity-slot-id "graph")
                "Graph activation should make graph the active scene slot")
        ;; Graph slot should not be sandbox slot
        (local graph-slot (scene:activity-slot "graph"))
        (assert graph-slot "Graph should own a scene slot")
        (local sandbox-slot (scene:activity-slot "sandbox"))
        (assert (not (= graph-slot sandbox-slot))
                "Graph scene slot must not be Sandbox scene slot")
        ;; Graph services should be empty/disabled
        (assert (not (. mock-lights-state :ambient :enabled?))
                "Graph activation should disable ambient light (empty slot)")
        (assert (not skybox-state.enabled?)
                "Graph activation should disable skybox (empty slot)")
        ;; Graph slot captured state should have empty terrain and panels
        (local graph-captured (scene:capture-activity-slot-state "graph"))
        (assert (= (length graph-captured.terrains) 0)
                "Graph scene slot should have no terrains")
        (assert (= (length graph-captured.panels) 0)
                "Graph scene slot should have no panels")
        (assert (not graph-captured.lights.ambient.enabled?)
                "Captured graph state should have disabled ambient light")
        (assert (not graph-captured.skybox.enabled?)
                "Captured graph state should have disabled skybox")
        (local graph-background (. (test-theme) :graph :background))
        (assert (and app.background-state
                     (= (. app.background-state.color 1) graph-background.x)
                     (= (. app.background-state.color 2) graph-background.y)
                     (= (. app.background-state.color 3) graph-background.z))
                "Graph activation should apply theme graph background")
        ;; Containment should be disabled
        (let [g-slot (scene:activity-slot "graph")
              g-manager (and g-slot g-slot.physics-containment-manager)]
          (assert (and g-manager g-manager.config
                       (not g-manager.config.enabled?))
                  "Graph activation should disable containment"))
        ;; Sandbox pointer target should be rejected
        (let [sb-slot (scene:activity-slot "sandbox")]
          (assert (not (app.pointer-target-enabled? (. sb-slot :pointer-target)))
                  "Sandbox pointer target should be rejected while graph is active"))

        ;; Switch back to Sandbox — content should be preserved
        (Activities.activate-activity "sandbox")
        (assert (= scene.active-activity-slot-id "sandbox")
                "Switching back to sandbox should restore sandbox as active scene slot")
        (assert (. mock-lights-state :ambient :enabled?)
                "Sandbox reactivation should re-enable ambient light")
        (assert skybox-state.enabled?
                "Sandbox reactivation should re-enable skybox")
        true)))
  (pcall SandboxActivityUnit.unload-sandbox-activity!)
  (pcall GraphActivityUnit.unload-graph-activity!)
  (object-selector:drop)
  (graph-map-manager:drop)
  (graph:drop)
  (scene:drop)
  (canvas:drop)
  (focus-manager:drop)
  (camera:drop)
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Graph activity scene isolation prevents sandbox inheritance"
                      :fn graph-activity-scene-isolation-prevents-sandbox-inheritance})

(fn graph-and-drawing-do-not-share-canvas-camera []
  ;; Graph and Drawing each own their canvas camera via
  ;; ensure-activity-canvas-camera!.  Activating graph then drawing
  ;; must give each its own camera — the drawing slot camera must not
  ;; inherit the graph slot camera position.
  (local app-keys [:active-world-runtime
                   :canvas
                   :graph
                   :graph-map
                   :graph-map-manager
                   :graph-view
                   :drawing-controller
                   :drawing-render
                   :activity-registry
                   :activities-changed
                   :active-activity-id
                   :active-interaction-surface
                   :preferred-interaction-surface
                   :active-pointer-controls
                   :scene-interactive?
                   :canvas-interactive?
                   :canvas-surface-interactive?
                   :canvas-visible?
                   :canvas-controls
                   :first-person-controls
                   :viewport
                   :themes
                   :renderers
                   :lights
                   :engine])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.canvas-visible? false)
  (set app.canvas-interactive? false)
  (set app.canvas-surface-interactive? true)
  (set app.active-interaction-surface :scene)
  (set app.preferred-interaction-surface :scene)
  (Main.install-app-shell!)
  (set app.themes {:get-active-theme test-theme})
  (var skybox-state {:enabled? false :name "lake" :brightness 0.5 :tint-color [1.0 1.0 1.0]})
  (local SkyboxState (require :skybox-state))
  (local BackgroundState (require :background-state))
  (set app.renderers {:skybox {:get-state (fn [_] skybox-state)
                               :set-state (fn [_ state] (set skybox-state (SkyboxState.normalize-resolved-state state "skybox-mock")))}
                      :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
                      :set-background-state (fn [_ state] (set app.background-state (BackgroundState.normalize-complete-state state "bg-mock")))})
  (var mock-lights-state {:ambient {:enabled? false :color [0.1 0.1 0.1] :intensity 1.0} :directional [] :point [] :spot []})
  (set app.lights {:get-state (fn [_] mock-lights-state) :set-state (fn [_ state] (set mock-lights-state state))})
  (set app.engine {:physics {:addRigidBody (fn [_phys _body]) :removeRigidBody (fn [_phys _body])}})
  (local data-dir "/tmp/space/tests/graph-drawing-camera-isolation")
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (fs.create-dirs data-dir)
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "graph-drawing-camera-isolation"}))
  (local canvas (Canvas {:camera camera
                         :focus-manager focus-manager}))
  (local AppProjection (require :app-projection))
  (when (not app.create-default-projection)
    (set app.create-default-projection AppProjection.create-default-projection))
  (local scene (Scene {:camera camera}))
  (set app.viewport {:x 0 :y 0 :width 800 :height 600})
  (canvas:on-viewport-changed app.viewport)
  (scene:on-viewport-changed app.viewport)
  (local graph (Graph {:with-start false}))
  (local graph-map-manager (GraphMapManager.GraphMapManager {:graph graph})) (local graph-map (graph-map-manager:get-active-map))
  (local object-selector (ObjectSelector {:ctx-provider (fn []
                                                         (or (and canvas.active-activity-slot
                                                                  canvas.active-activity-slot.ctx)
                                                             canvas.build-context))
                                           :enabled? true}))
  (local controller (DrawingController {:data_dir data-dir}))
  (controller:add-layer "vector")
  (local runtime {:canvas canvas
                  :scene scene
                  :graph graph
                  :graph-map graph-map :graph-map-manager graph-map-manager
                  :object-selector object-selector
                  :movables app.movables
                  :activity-cameras {:canvas {} :scene {}}
                  :activity-controls {:canvas {} :scene {}}
                  :world-dir data-dir
                  :drawing-controller controller
                  :board-state {:items [] :connectors []}})
  (set app.active-world-runtime runtime)
  (set app.canvas canvas)
  (set app.graph graph)
  (set app.graph-map graph-map) (set app.graph-map-manager graph-map-manager)
  (set app.drawing-controller controller)
  (local (ok result)
    (pcall
      (fn []
        (GraphActivityUnit.load-graph-activity!)
        (DrawingActivityUnit.load-drawing-activity!)
        ;; Activate graph — camera is created in activity-cameras.canvas.graph
        (Activities.activate-activity "graph")
        (local graph-slot (canvas:activity-slot "graph"))
        (assert graph-slot "Graph should have a canvas slot")
        (assert graph-slot.camera "Graph slot must own its camera")
        ;; Move the graph camera
        (graph-slot.camera:set-position (glm.vec3 100 0 100))
        ;; Switch to drawing — camera is created in activity-cameras.canvas.drawing
        (Activities.activate-activity "drawing")
        (local drawing-slot (canvas:activity-slot "drawing"))
        (assert drawing-slot "Drawing should have a canvas slot")
        (assert drawing-slot.camera "Drawing slot must own its camera")
        ;; Drawing camera must NOT inherit graph camera position
        (assert (not (= drawing-slot.camera.position.x 100))
                "Drawing must not inherit Graph camera position")
        true)))
  (pcall GraphActivityUnit.unload-graph-activity!)
  (pcall DrawingActivityUnit.unload-drawing-activity!)
  (object-selector:drop)
  (graph-map-manager:drop)
  (graph:drop)
  (scene:drop)
  (canvas:drop)
  (focus-manager:drop)
  (camera:drop)
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Graph and drawing do not share canvas camera"
                     :fn graph-and-drawing-do-not-share-canvas-camera})

(local board-graph-camera-app-keys
  [:active-world-runtime
   :canvas
   :graph
   :graph-map
   :graph-map-manager
   :graph-view
   :board
   :board-view
   :activity-registry
   :activities-changed
   :active-activity-id
   :active-interaction-surface
   :preferred-interaction-surface
   :active-pointer-controls
   :scene-interactive?
   :canvas-interactive?
   :canvas-surface-interactive?
   :canvas-visible?
   :canvas-controls
   :first-person-controls
   :viewport
   :themes
   :renderers
   :background-state
   :lights
   :engine])

(fn make-board-graph-camera-renderers []
  (var skybox-state {:enabled? false :name "lake" :brightness 0.5 :tint-color [1.0 1.0 1.0]})
  (local SkyboxState (require :skybox-state))
  (local BackgroundState (require :background-state))
  {:skybox {:get-state (fn [_] skybox-state)
            :set-state (fn [_ state] (set skybox-state (SkyboxState.normalize-resolved-state state "skybox-mock")))}
   :get-background-state (fn [_]
                           (if app.background-state
                               app.background-state
                               BackgroundState.default-state))
   :set-background-state (fn [_ state] (set app.background-state (BackgroundState.normalize-complete-state state "bg-mock")))})

(fn make-board-graph-camera-lights []
  (var mock-lights-state {:ambient {:enabled? false :color [0.1 0.1 0.1] :intensity 1.0}
                          :directional []
                          :point []
                          :spot []})
  {:get-state (fn [_] mock-lights-state)
   :set-state (fn [_ state] (set mock-lights-state state))})

(fn board-and-graph-activity-cameras-stay-isolated []
  (local app-snapshot (snapshot-app-fields board-graph-camera-app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.canvas-visible? false)
  (set app.canvas-interactive? false)
  (set app.canvas-surface-interactive? true)
  (set app.active-interaction-surface :scene)
  (set app.preferred-interaction-surface :scene)
  (Main.install-app-shell!)
  (set app.themes {:get-active-theme test-theme})
  (set app.renderers (make-board-graph-camera-renderers))
  (set app.lights (make-board-graph-camera-lights))
  (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                             :removeRigidBody (fn [_phys _body])}})
  (local data-dir "/tmp/space/tests/board-graph-camera-isolation")
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (fs.create-dirs data-dir)
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "board-graph-camera-isolation"}))
  (local canvas (Canvas {:camera camera
                         :focus-manager focus-manager}))
  (local AppProjection (require :app-projection))
  (when (not app.create-default-projection)
    (set app.create-default-projection AppProjection.create-default-projection))
  (local scene (Scene {:camera camera}))
  (set app.viewport {:x 0 :y 0 :width 800 :height 600})
  (canvas:on-viewport-changed app.viewport)
  (scene:on-viewport-changed app.viewport)
  (local graph (Graph {:with-start false}))
  (local graph-map-manager (GraphMapManager.GraphMapManager {:graph graph}))
  (local graph-map (graph-map-manager:get-active-map))
  (local object-selector (ObjectSelector {:ctx-provider (fn []
                                                         (or (and canvas.active-activity-slot
                                                                  canvas.active-activity-slot.ctx)
                                                             canvas.build-context))
                                           :enabled? true}))
  (local runtime {:canvas canvas
                  :scene scene
                  :graph graph
                  :graph-map graph-map
                  :graph-map-manager graph-map-manager
                  :object-selector object-selector
                  :movables app.movables
                  :activity-cameras {:canvas {} :scene {}}
                  :activity-controls {:canvas {} :scene {}}
                  :world-dir data-dir
                  :board-state {:items [] :connectors []}})
  (set app.active-world-runtime runtime)
  (set app.canvas canvas)
  (set app.graph graph)
  (set app.graph-map graph-map)
  (set app.graph-map-manager graph-map-manager)
  (local (ok result)
    (pcall
      (fn []
        (GraphActivityUnit.load-graph-activity!)
        (BoardActivityUnit.load-board-activity!)

        (Activities.activate-activity "graph")
        (local graph-slot (canvas:activity-slot "graph"))
        (local graph-camera (. runtime.activity-cameras.canvas "graph"))
        (assert graph-camera "Graph activity should create a graph camera")
        (assert (= graph-slot.camera graph-camera)
                "Graph slot must use the graph activity camera")
        (graph-camera:set-position (glm.vec3 10 20 100))

        (Activities.activate-activity "board")
        (local board-slot (canvas:activity-slot "board"))
        (local board-camera (. runtime.activity-cameras.canvas "board"))
        (assert board-camera "Board activity should create a board camera")
        (assert (= board-slot.camera board-camera)
                "Board slot must use the board activity camera")
        (assert (not (= graph-camera board-camera))
                "Graph and Board must not share the same activity camera object")
        (board-camera:set-position (glm.vec3 -30 -40 100))
        (assert (= graph-camera.position.x 10)
                "Moving Board must not change Graph camera x")
        (assert (= graph-camera.position.y 20)
                "Moving Board must not change Graph camera y")

        (Activities.activate-activity "graph")
        (assert (= graph-camera.position.x 10)
                "Graph camera x should restore after Board activity movement")
        (assert (= graph-camera.position.y 20)
                "Graph camera y should restore after Board activity movement")
        (assert (= board-camera.position.x -30)
                "Graph reactivation must not change Board camera x")
        (assert (= board-camera.position.y -40)
                "Graph reactivation must not change Board camera y")
        true)))
  (pcall GraphActivityUnit.unload-graph-activity!)
  (pcall BoardActivityUnit.unload-board-activity!)
  (when runtime.graph-view
    (runtime.graph-view:drop)
    (set runtime.graph-view nil))
  (when runtime.board-view
    (runtime.board-view:drop)
    (set runtime.board-view nil))
  (object-selector:drop)
  (graph-map-manager:drop)
  (graph:drop)
  (scene:drop)
  (canvas:drop)
  (focus-manager:drop)
  (camera:drop)
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Board and Graph activity cameras stay isolated"
                     :fn board-and-graph-activity-cameras-stay-isolated})

(fn graph-map-cameras-save-and-restore-on-switch []
  (local app-snapshot (snapshot-app-fields board-graph-camera-app-keys))
  (set app.activity-registry nil) (set app.activities-changed nil) (set app.active-activity-id nil)
  (set app.canvas-visible? false) (set app.canvas-interactive? false) (set app.canvas-surface-interactive? true)
  (set app.active-interaction-surface :scene) (set app.preferred-interaction-surface :scene) (Main.install-app-shell!)
  (set app.themes {:get-active-theme test-theme}) (set app.renderers (make-board-graph-camera-renderers)) (set app.lights (make-board-graph-camera-lights))
  (set app.engine {:physics {:addRigidBody (fn [_phys _body]) :removeRigidBody (fn [_phys _body])}})
  (local data-dir "/tmp/space/tests/graph-map-camera-switch")
  (when (fs.exists data-dir) (fs.remove-all data-dir)) (fs.create-dirs data-dir)
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "graph-map-camera-switch"}))
  (local canvas (Canvas {:camera camera :focus-manager focus-manager}))
  (local AppProjection (require :app-projection))
  (when (not app.create-default-projection) (set app.create-default-projection AppProjection.create-default-projection))
  (local scene (Scene {:camera camera}))
  (set app.viewport {:x 0 :y 0 :width 800 :height 600}) (canvas:on-viewport-changed app.viewport) (scene:on-viewport-changed app.viewport)
  (local graph (Graph {:with-start false}))
  (local graph-map-manager (GraphMapManager.GraphMapManager {:graph graph :data-dir data-dir}))
  (graph:register-key-loader "beta-node" (fn [key] (Graph.GraphNode {:key key})))
  (graph-map-manager:create-map! "beta" "beta")
  (local graph-map (graph-map-manager:get-active-map))
  (local object-selector (ObjectSelector {:ctx-provider (fn [] (or (and canvas.active-activity-slot canvas.active-activity-slot.ctx) canvas.build-context))
                                           :enabled? true}))
  (local runtime {:canvas canvas :scene scene :graph graph :graph-map graph-map :graph-map-manager graph-map-manager
                  :object-selector object-selector
                  :movables app.movables
                  :activity-cameras {:canvas {} :scene {}}
                  :activity-controls {:canvas {} :scene {}}
                  :world-dir data-dir})
  (set app.active-world-runtime runtime) (set app.canvas canvas) (set app.graph graph) (set app.graph-map graph-map) (set app.graph-map-manager graph-map-manager)
  (local (ok result)
    (pcall
      (fn []
        (GraphActivityUnit.load-graph-activity!)
        (Activities.activate-activity "graph")
        (local graph-camera (. runtime.activity-cameras.canvas "graph"))
        (assert graph-camera "Graph activity should create a graph camera")
        (graph-camera:set-position (glm.vec3 10 20 100))

        (graph-map-manager:switch-map! "beta")
        (local GraphViewPersistence (require :graph/view/persistence))
        (local main-persistence (GraphViewPersistence {:data-dir data-dir :map-id "main"}))
        (local main-camera (main-persistence:saved-camera-state))
        (assert (= (. main-camera.position 1) 10) "Switching away should persist main camera x")
        (assert (= (. main-camera.position 2) 20) "Switching away should persist main camera y")
        (assert (= graph-camera.position.x 0) "Map with no saved camera should reset camera x before first node")
        (assert (= graph-camera.position.y 0) "Map with no saved camera should reset camera y before first node")
        (assert (= graph-camera.position.z 100) "Map with no saved camera should reset camera z")
        (app.graph-map:add-node (Graph.GraphNode {:key "beta-node"}) {:position (glm.vec3 111 222 0)})
        (assert (= graph-camera.position.x 111) "Map with no saved camera should center first added node x")
        (assert (= graph-camera.position.y 222) "Map with no saved camera should center first added node y")

        (graph-map-manager:switch-map! "main")
        (local beta-persistence (GraphViewPersistence {:data-dir data-dir :map-id "beta"}))
        (local beta-camera (beta-persistence:saved-camera-state))
        (assert (= (. beta-camera.position 1) 111) "Switching away from untouched beta should persist centered camera x")
        (assert (= (. beta-camera.position 2) 222) "Switching away from untouched beta should persist centered camera y")
        (assert (= (. beta-camera.position 3) 100) "Switching away from untouched beta should persist default camera z")
        (assert (= graph-camera.position.x 10) "Switching back to main after untouched beta should restore main camera x")
        (assert (= graph-camera.position.y 20) "Switching back to main after untouched beta should restore main camera y")

        (graph-map-manager:switch-map! "beta")
        (assert (= graph-camera.position.x 111) "Switching back to untouched beta should restore centered camera x")
        (assert (= graph-camera.position.y 222) "Switching back to untouched beta should restore centered camera y")

        (graph-camera:set-position (glm.vec3 -30 -40 150))
        (graph-map-manager:switch-map! "main")
        (assert (= graph-camera.position.x 10) "Switching back to main should restore main camera x")
        (assert (= graph-camera.position.y 20) "Switching back to main should restore main camera y")

        (graph-map-manager:switch-map! "beta")
        (assert (= graph-camera.position.x -30) "Switching back to beta should restore beta camera x")
        (assert (= graph-camera.position.y -40) "Switching back to beta should restore beta camera y")
        true)))
  (pcall GraphActivityUnit.unload-graph-activity!)
  (when runtime.graph-view (runtime.graph-view:drop) (set runtime.graph-view nil))
  (object-selector:drop) (graph-map-manager:drop) (graph:drop) (scene:drop) (canvas:drop) (focus-manager:drop) (camera:drop)
  (when (fs.exists data-dir) (fs.remove-all data-dir))
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Graph map cameras save and restore on switch"
                      :fn graph-map-cameras-save-and-restore-on-switch})

(fn graph-view-mode-change-rebuilds-active-renderer-and-cleans-connections []
  (local app-snapshot (snapshot-app-fields board-graph-camera-app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.canvas-visible? false)
  (set app.canvas-interactive? false)
  (set app.canvas-surface-interactive? true)
  (set app.active-interaction-surface :scene)
  (set app.preferred-interaction-surface :scene)
  (Main.install-app-shell!)
  (set app.themes {:get-active-theme test-theme})
  (set app.renderers (make-board-graph-camera-renderers))
  (set app.lights (make-board-graph-camera-lights))
  (set app.engine {:physics {:addRigidBody (fn [_phys _body])
                             :removeRigidBody (fn [_phys _body])}})
  (local data-dir "/tmp/space/tests/graph-view-mode-rebuild")
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (fs.create-dirs data-dir)
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "graph-view-mode-rebuild"}))
  (local canvas (Canvas {:camera camera :focus-manager focus-manager}))
  (local AppProjection (require :app-projection))
  (when (not app.create-default-projection)
    (set app.create-default-projection AppProjection.create-default-projection))
  (local scene (Scene {:camera camera}))
  (set app.viewport {:x 0 :y 0 :width 800 :height 600})
  (canvas:on-viewport-changed app.viewport)
  (scene:on-viewport-changed app.viewport)
  (local graph (Graph {:with-start false}))
  (local graph-map-manager (GraphMapManager.GraphMapManager {:graph graph :data-dir data-dir}))
  (graph-map-manager:create-map! "beta" "Beta")
  (local graph-map (graph-map-manager:get-active-map))
  (local object-selector (ObjectSelector {:ctx-provider (fn []
                                                          (if (and canvas.active-activity-slot
                                                                   canvas.active-activity-slot.ctx)
                                                              canvas.active-activity-slot.ctx
                                                              canvas.build-context))
                                            :enabled? true}))
  (local runtime {:canvas canvas
                  :scene scene
                  :graph graph
                  :graph-map graph-map
                  :graph-map-manager graph-map-manager
                  :object-selector object-selector
                  :movables app.movables
                  :activity-cameras {:canvas {} :scene {}}
                  :activity-controls {:canvas {} :scene {}}
                  :world-dir data-dir})
  (set app.active-world-runtime runtime)
  (set app.canvas canvas)
  (set app.graph graph)
  (set app.graph-map graph-map)
  (set app.graph-map-manager graph-map-manager)
  (local (ok result)
    (pcall
      (fn []
        (GraphActivityUnit.load-graph-activity!)
        (Activities.activate-activity "graph")
        (local spatial-view app.graph-view)
        (assert spatial-view "Graph activity should create an initial spatial graph view")
        (assert spatial-view.points "Initial graph view should be spatial")
        (assert runtime.graph-view-mode-conn "Graph activity should connect active map view-mode changes")

        (graph-map:set-view-mode! "outline")
        (local outline-view app.graph-view)
        (assert (not (= outline-view spatial-view)) "View mode change should replace the active graph view")
        (assert (= outline-view.graph-map graph-map) "Outline rebuild should keep the same active graph map")
        (assert outline-view.rows "Outline rebuild should create an outline renderer")
        (assert runtime.graph-view-mode-conn "Outline rebuild should reconnect view-mode changes")

        (graph-map:set-view-mode! "spatial")
        (local rebuilt-spatial-view app.graph-view)
        (assert (not (= rebuilt-spatial-view outline-view)) "Returning to spatial should replace outline renderer")
        (assert (= rebuilt-spatial-view.graph-map graph-map) "Spatial rebuild should keep the same active graph map")
        (assert rebuilt-spatial-view.points "Spatial rebuild should create a spatial renderer")

        (graph-map-manager:switch-map! "beta")
        (local beta-map (graph-map-manager:get-active-map))
        (local beta-view app.graph-view)
        (assert (= app.graph-map beta-map) "Map switch should expose the beta graph map")
        (assert (= beta-view.graph-map beta-map) "Map switch should rebuild for beta map")
        (assert runtime.graph-view-mode-conn "Map switch should connect beta map view-mode changes")
        (graph-map:set-view-mode! "outline")
        (assert (= app.graph-map beta-map) "Old map view-mode changes must not switch the active map")
        (assert (= app.graph-view beta-view) "Old map view-mode changes must not rebuild the beta renderer")

        (Activities.deactivate-active-activity)
        (assert (= runtime.graph-view-mode-conn nil) "Deactivation should disconnect view-mode changes")
        (beta-map:set-view-mode! "outline")
        (assert (= app.graph-view nil) "View-mode change after deactivation must not rebuild a graph view")

        (Activities.activate-activity "graph")
        (assert runtime.graph-view-mode-conn "Reactivation should reconnect view-mode changes")
        (GraphActivityUnit.drop-graph-view! false)
        (assert (= runtime.graph-view-mode-conn nil) "Dropping graph view should disconnect view-mode changes")
        (beta-map:set-view-mode! "spatial")
        (assert (= app.graph-view nil) "View-mode change after drop must not rebuild a graph view")
        true)))
  (pcall GraphActivityUnit.unload-graph-activity!)
  (when runtime.graph-view
    (runtime.graph-view:drop)
    (set runtime.graph-view nil))
  (object-selector:drop)
  (graph-map-manager:drop)
  (graph:drop)
  (scene:drop)
  (canvas:drop)
  (focus-manager:drop)
  (camera:drop)
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Graph view-mode change rebuilds active renderer and cleans connections"
                     :fn graph-view-mode-change-rebuilds-active-renderer-and-cleans-connections})

(fn theme-switch-color-approx [a b]
  (local MathUtils (require :math-utils))
  (and a b
       (MathUtils.approx a.x b.x)
       (MathUtils.approx a.y b.y)
       (MathUtils.approx a.z b.z)
       (MathUtils.approx a.w b.w)))

(fn make-theme-switch-themes []
  (local Themes (require :themes))
  (local themes (Themes))
  (themes.add-theme :dark (require :dark-theme))
  (themes.add-theme :light (require :light-theme))
  (themes.set-theme :dark)
  themes)

(fn make-theme-switch-icons-stub []
  (local font (make-font-stub))
  {:font font
   :get (fn [_self name]
          (assert (= name "account_tree") (.. "Missing icon " name))
          4242)
   :resolve (fn [self name]
              {:type :font
               :codepoint (self:get name)
               :font self.font})})

(fn find-theme-switch-rail-button []
  (local clickables (assert app.clickables "graph activity theme switch test requires app.clickables"))
  (var found nil)
  (each [_ object (ipairs (or clickables.left-click-objects []))]
    (when (and (not found) (= object.icon "account_tree"))
      (set found object)))
  found)

(fn make-theme-switch-hud-ctx []
  (local BuildContext (require :build-context))
  (BuildContext {:theme (and app.themes app.themes.get-active-theme (app.themes:get-active-theme))
                 :clickables (assert app.clickables "test requires app.clickables")
                 :hoverables (assert app.hoverables "test requires app.hoverables")
                 :system-cursors app.system-cursors
                 :icons (make-theme-switch-icons-stub)
                 :states app.states}))

(fn install-theme-switch-rail-check! []
  (local ActivityDockView (require :activity-dock-view))
  (local state {:checked? false :dock nil})
  (set app.apply-active-world-hud-contrib
       (fn []
         (local dock ((ActivityDockView {}) (make-theme-switch-hud-ctx)))
         (set state.dock dock)
         (local graph-button (find-theme-switch-rail-button))
         (local expected-colors (app.themes:get-button-colors :secondary))
         (assert graph-button "graph theme switch HUD rebuild should recreate the graph rail button")
         (assert (theme-switch-color-approx graph-button.foreground-color expected-colors.foreground)
                  "graph theme switch HUD rebuild should use the new theme rail button foreground")
         (set state.checked? true)
         true))
  state)

(fn with-graph-theme-switch-env [f]
  (local app-keys [:active-world-runtime :canvas :graph-map :graph-view :activity-registry
                   :activities-changed :activity-dock-changed :active-activity-id :active-interaction-surface
                   :preferred-interaction-surface :active-pointer-controls :scene-interactive?
                   :canvas-interactive? :canvas-surface-interactive? :canvas-visible? :graph-map-manager
                   :canvas-controls :first-person-controls :viewport :themes :settings
                   :renderers :engine :apply-active-world-hud-contrib :mark-active-world-hud-dirty])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.engine (or app.engine {}))
  (set app.themes (make-theme-switch-themes))
  (set app.settings {:set-value (fn [_key _value _opts] true) :save (fn [] true)})
  (set app.renderers {:apply-theme (fn [_self _theme] true)})
  (set app.mark-active-world-hud-dirty (fn [] true))
  (Main.install-app-shell!)
  (local rail-state (install-theme-switch-rail-check!))
  (local data-dir "/tmp/space/tests/graph-activity-theme-switch")
  (when (fs.exists data-dir) (fs.remove-all data-dir))
  (fs.create-dirs data-dir)
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "graph-activity-theme-switch-test"}))
  (local canvas (Canvas {:camera camera :focus-manager focus-manager}))
  (local AppProjection (require :app-projection))
  (when (not app.create-default-projection)
    (set app.create-default-projection AppProjection.create-default-projection))
  (local scene (Scene {:camera camera}))
  (set app.viewport {:x 0 :y 0 :width 800 :height 600})
  (canvas:on-viewport-changed app.viewport)
  (scene:on-viewport-changed app.viewport)
  (local graph (Graph {:with-start false}))
  (local node {:key "theme-node:one" :label "Theme Node"})
  (graph:register-key-loader "theme-node" (fn [key] (assert (= key node.key) "Unexpected theme test key") node))
  (local graph-map-manager (GraphMapManager.GraphMapManager {:graph graph}))
  (local graph-map (graph-map-manager:get-active-map))
  (local loaded-node (graph-map:load-by-key node.key))
  (local object-selector (ObjectSelector {:ctx-provider (fn [] (or (and canvas.active-activity-slot canvas.active-activity-slot.ctx) canvas.build-context))
                                          :enabled? true}))
  (local runtime {:canvas canvas :scene scene :graph graph :graph-map graph-map :graph-map-manager graph-map-manager
                  :object-selector object-selector :movables app.movables
                  :activity-cameras {:canvas {} :scene {}} :activity-controls {:canvas {} :scene {}}
                  :world-dir data-dir})
  (set app.active-world-runtime runtime)
  (set app.canvas canvas)
  (set app.graph-map graph-map)
  (set app.graph-map-manager graph-map-manager)
  (local (ok result) (pcall f loaded-node rail-state))
  (pcall GraphActivityUnit.unload-graph-activity!)
  (when (and rail-state.dock rail-state.dock.drop)
    (rail-state.dock:drop))
  (when runtime.graph-view (runtime.graph-view:drop) (set runtime.graph-view nil))
  (object-selector:drop)
  (graph-map-manager:drop)
  (graph:drop)
  (scene:drop)
  (canvas:drop)
  (focus-manager:drop)
  (camera:drop)
  (when (fs.exists data-dir) (fs.remove-all data-dir))
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(fn graph-activity-theme-switch-rebuilds-label-colors []
  (with-graph-theme-switch-env
    (fn [loaded-node rail-state]
      (local ThemeActions (require :theme-actions))
      (GraphActivityUnit.load-graph-activity!)
      (Activities.activate-activity "graph")
      (local dark-theme (app.themes:get-active-theme))
      (local dark-color dark-theme.graph.label-color)
      (app.graph-view.labels:update app.graph-view.points [loaded-node] {:force? true})
      (local dark-span (. app.graph-view.labels.labels loaded-node))
      (assert dark-span "graph activity should create a visible graph label before theme switch")
      (assert (theme-switch-color-approx dark-span.style.color dark-color)
              "graph label should start with the active dark theme color")
      (local old-view app.graph-view)
      (ThemeActions.apply-theme :light)
      (assert app.graph-view "theme switch should leave graph mode active with a graph view")
      (local light-theme (app.themes:get-active-theme))
      (local light-color light-theme.graph.label-color)
      (app.graph-view.labels:update app.graph-view.points [loaded-node] {:force? true})
      (local light-span (. app.graph-view.labels.labels loaded-node))
      (assert light-span "graph activity should recreate a visible graph label after theme switch")
      (assert (theme-switch-color-approx light-span.style.color light-color)
              "graph label should use the new light theme color after ThemeActions.apply-theme")
      (assert (not (theme-switch-color-approx light-span.style.color dark-color))
              "graph label must not retain the stale dark theme color after ThemeActions.apply-theme")
      (assert (not (= app.graph-view old-view))
              "graph activity theme switch should rebuild the retained graph view so cached theme colors are refreshed")
      (assert rail-state.checked?
              "graph activity theme switch should cover real HUD rail foreground rebuild")
      (assert app.activity-left-dock-builder
              "graph activity theme switch should restore the graph sidebar dock builder")
      (assert rail-state.dock
              "graph activity theme switch test should keep the rebuilt activity dock")
      (rail-state.dock:update)
      (assert (rail-state.dock:active-dock-entity)
              "activity dock should rebuild to include graph sidebar after graph theme switch")
      true)))

(table.insert tests {:name "Graph activity theme switch rebuilds label colors"
                      :fn graph-activity-theme-switch-rebuilds-label-colors})

(fn graph-activity-requires-map-manager-for-sidebar []
  (local app-keys [:active-world-runtime :canvas :graph-map :graph-map-manager :graph-view :activity-registry :activities-changed :active-activity-id :active-interaction-surface :preferred-interaction-surface :canvas-visible? :viewport :themes])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil) (set app.activities-changed nil) (set app.active-activity-id nil) (set app.themes {:get-active-theme test-theme})
  (local data-dir "/tmp/space/tests/graph-activity-missing-manager") (when (fs.exists data-dir) (fs.remove-all data-dir)) (fs.create-dirs data-dir)
  (local camera (Camera {:position (glm.vec3 0 0 100)})) (local focus-manager (FocusManager {:root-name "graph-activity-missing-manager"}))
  (local canvas (Canvas {:camera camera :focus-manager focus-manager})) (local scene (Scene {:camera camera}))
  (set app.viewport {:x 0 :y 0 :width 800 :height 600}) (canvas:on-viewport-changed app.viewport) (scene:on-viewport-changed app.viewport)
  (local graph (Graph {:with-start false})) (local graph-map (GraphMap.GraphMap {:graph graph :id "main"}))
  (local object-selector (ObjectSelector {:ctx-provider (fn [] (or (and canvas.active-activity-slot canvas.active-activity-slot.ctx) canvas.build-context)) :enabled? true}))
  (set app.active-world-runtime {:canvas canvas :scene scene :graph graph :graph-map graph-map :object-selector object-selector :movables app.movables :activity-cameras {:canvas {} :scene {}} :activity-controls {:canvas {} :scene {}} :world-dir data-dir})
  (set app.canvas canvas) (set app.graph-map graph-map) (set app.graph-map-manager nil)
  (local (ok result) (pcall (fn [] (GraphActivityUnit.load-graph-activity!) (Activities.activate-activity "graph"))))
  (pcall GraphActivityUnit.unload-graph-activity!) (object-selector:drop) (graph-map:drop) (graph:drop) (scene:drop) (canvas:drop) (focus-manager:drop) (camera:drop) (when (fs.exists data-dir) (fs.remove-all data-dir)) (restore-app-fields! app-snapshot)
  (assert (not ok) "Graph activity should fail loudly when runtime.graph-map-manager is missing")
  (assert (string.find (tostring result) "runtime.graph-map-manager" 1 true) "Missing graph-map-manager failure should name the required manager") true)

(table.insert tests {:name "Graph activity requires graph map manager for sidebar"
                      :fn graph-activity-requires-map-manager-for-sidebar})


(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-activity-slots"
                       :tests tests})))

{:name "graph-activity-slots"
 :tests tests
 :main main}
