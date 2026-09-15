(local Harness (require :tests.e2e.harness))
(local fs (require :fs))
(local glm (require :glm))
(local viewport-utils (require :viewport-utils))
(local Main (require :main))
(local HomeWorld (require :home-world))
(local Signal (require :signal))

(var temp-counter 0)
(var click-timestamp 0)
(local temp-root "/tmp/space/tests/e2e/drawing-workflow")

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "drawing-workflow-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (if ok
      result
      (error result)))

(fn codepoints->text [codepoints]
  (local parts [])
  (each [_ codepoint (ipairs (or codepoints []))]
    (table.insert parts (utf8.char codepoint)))
  (table.concat parts))

(fn clickable-label [obj]
  (if (and obj obj.text obj.text.get-codepoints)
      (codepoints->text (obj.text:get-codepoints))
      nil))

(fn find-clickable-by-label [label]
  (var resolved nil)
  (each [_ obj (ipairs (assert (. (assert app.clickables "drawing workflow e2e requires app.clickables") :left-click-objects) "drawing workflow e2e requires left-click objects"))]
    (when (and (not resolved)
               (= (clickable-label obj) label))
      (set resolved obj)))
  resolved)

(fn find-clickable-by-icon [icon]
  (var resolved nil)
  (each [_ obj (ipairs (assert (. (assert app.clickables "drawing workflow e2e requires app.clickables") :left-click-objects) "drawing workflow e2e requires left-click objects"))]
    (when (and (not resolved)
               obj
               (= obj.icon icon))
      (set resolved obj)))
  resolved)

(fn next-click-timestamp []
  (set click-timestamp (+ click-timestamp 1))
  click-timestamp)

(fn project-to-screen [position target]
  (assert (and glm glm.project) "drawing workflow e2e requires glm.project")
  (local viewport (viewport-utils.to-table app.viewport))
  (local viewport-vec (viewport-utils.to-glm-vec4 viewport))
  (local view (target:get-view-matrix))
  (local projection target.projection)
  (local projected (glm.project position view projection viewport-vec))
  (assert projected "glm.project returned nil")
  {:x projected.x
   :y (- (+ viewport.height viewport.y) projected.y)})

(fn layout-screen-point [target layout]
  (local size (or layout.size layout.measure (glm.vec3 0 0 0)))
  (local rotation (or layout.rotation (glm.quat 1 0 0 0)))
  (local offset (glm.vec3 (/ size.x 2)
                          (/ size.y 2)
                          0))
  (local world-pos (+ layout.position
                      (rotation:rotate offset)))
  (project-to-screen world-pos target))

(fn canvas-screen-point [point]
  (project-to-screen point app.canvas))

(fn apply-runtime-to-app [world runtime hud]
  (local entry {:id world.id
                :world world})
  (set app.hud hud)
  (set app.focus hud.__e2e_focus_manager)
  (assert (and Main Main.install-app-shell!)
          "drawing workflow e2e requires Main.install-app-shell!")
  (Main.install-app-shell!)
  (assert app.bind-active-world-runtime
          "drawing workflow e2e requires app.bind-active-world-runtime")
  (app.bind-active-world-runtime entry runtime)
  (assert app.set-active-interaction-surface
          "drawing workflow e2e requires app.set-active-interaction-surface")
  (app.set-active-interaction-surface :canvas)
  (when app.hud
    (app.hud:update)))

(fn active-state []
  (local state (and app.states (app.states:active-state)))
  (assert state "drawing workflow e2e requires active state")
  state)

(fn refresh-world [env]
  (when env.flush-next-frame
    (env.flush-next-frame))
  (env.world:update 0 {})
  (when app.scene
    (app.scene:update))
  (when app.canvas
    (app.canvas:update))
  (when app.hud
    (app.hud:update)))

(fn click-at [env point]
  (local state (active-state))
  (local timestamp (next-click-timestamp))
  (state.on-mouse-button-down {:button 1
                               :x point.x
                               :y point.y
                               :timestamp timestamp})
  (state.on-mouse-button-up {:button 1
                             :x point.x
                             :y point.y
                             :timestamp timestamp})
  (refresh-world env))

(fn click-button [env label]
  (refresh-world env)
  (local button (assert (find-clickable-by-label label)
                        (.. "drawing workflow e2e missing button: " label)))
  (click-at env (layout-screen-point app.hud button.layout))
  button)

(fn click-button-icon [env icon]
  (refresh-world env)
  (local button (assert (find-clickable-by-icon icon)
                        (.. "drawing workflow e2e missing button icon: " icon)))
  (click-at env (layout-screen-point app.hud button.layout))
  button)

(fn drag-on-canvas [env start finish]
  (local state (active-state))
  (local start-point (canvas-screen-point start))
  (local finish-point (canvas-screen-point finish))
  (state.on-mouse-button-down {:button 1
                               :x start-point.x
                               :y start-point.y
                               :timestamp (next-click-timestamp)})
  (state.on-mouse-motion {:x finish-point.x
                          :y finish-point.y})
  (state.on-mouse-button-up {:button 1
                             :x finish-point.x
                             :y finish-point.y
                             :timestamp (next-click-timestamp)})
  (refresh-world env))

(fn active-layer []
  (and app.drawing-controller
       (app.drawing-controller:active-layer)))

(fn object-count []
  (local layer (active-layer))
  (length (or (and layer layer.objects) [])))

(fn triangle-vector-length []
  (local vector
    (and app.canvas
         app.canvas.get-triangle-vector
         (app.canvas:get-triangle-vector)))
  (and vector (vector:length)))

(fn raster-tile-count []
  (local layer (active-layer))
  (if (and layer (= layer.kind "raster"))
      (do
        (local raster-runtime (app.drawing-controller:ensure-raster-runtime layer))
        (local runtime raster-runtime.runtime)
        (var count 0)
        (each [_ _tile (pairs runtime.tiles)]
          (set count (+ count 1)))
        count)
      0))

(fn image-batch-vertex-count []
  (local batches
    (and app.canvas
         app.canvas.get-image-batches
         (app.canvas:get-image-batches)))
  (var count 0)
  (each [_ batch (pairs (or batches {}))]
    (when (and batch batch.vector batch.vector.length)
      (set count (+ count (batch.vector:length)))))
  count)

(fn graph-node-sort-key [node]
  (tostring (or (and node node.key)
               (and node node.id)
               "")))

(fn stabilize-graph-view-for-snapshot []
  (local graph-view app.graph-view)
  (when (and graph-view graph-view.nodes graph-view.graph-layout)
    (local nodes [])
    (each [_key node (pairs graph-view.nodes)]
      (table.insert nodes node))
    (table.sort nodes
                (fn [left right]
                  (< (graph-node-sort-key left)
                     (graph-node-sort-key right))))
    (each [idx node (ipairs nodes)]
      (graph-view.graph-layout:set-node-position
        node
        (glm.vec3 (+ -500 (* idx 10)) 500 0)))))

(fn install-next-frame-stub []
  (var pending [])
  (set app.next-frame
       (fn [callback]
         (assert (= (type callback) :function)
                 "drawing workflow e2e next-frame requires callback")
         (table.insert pending callback)
         callback))
  (fn []
    (when (> (length pending) 0)
      (local callbacks pending)
      (set pending [])
      (each [_ callback (ipairs callbacks)]
        (callback)))))

(fn with-home-world [ctx run-fn]
  (with-temp-dir
    (fn [dir]
      (local hud (Harness.make-hud-target {:width ctx.width
                                           :height ctx.height}))
      (local focus-manager hud.__e2e_focus_manager)
      (var active-world-entry nil)
      (local runtime-context {:hud hud
                              :focus-manager focus-manager
                              :focus-root (focus-manager:get-root-scope)
                              :icons app.icons
                              :states app.states
                              :movables app.movables})
      (local world-manager-stub {:changed (Signal)
                                 :active-world (fn [_self] active-world-entry)
                                 :list-tabs (fn [_self] [])})
      (local world (HomeWorld {:id "e2e-world"
                               :name "home"
                               :type "home"
                               :dir dir
                               :graph-world-manager world-manager-stub
                               :asset-path-resolver (fn [path]
                                                      (app.engine:get-asset-path path))}))
      (local previous {:hud app.hud
                       :focus app.focus
                       :scene app.scene
                       :canvas app.canvas
                       :projection app.projection
                       :camera app.camera
                       :first-person-controls app.first-person-controls
                       :canvas-controls app.canvas-controls
                       :graph app.graph
                       :graph-view app.graph-view
                       :drawing-controller app.drawing-controller
                       :drawing-render app.drawing-render
                       :pointer-target-enabled? app.pointer-target-enabled?
                       :mark-active-world-hud-dirty app.mark-active-world-hud-dirty
                       :reset-projection app.reset-projection
                       :set-active-interaction-surface app.set-active-interaction-surface
                       :set-active-activity app.set-active-activity
                       :bind-active-world-runtime app.bind-active-world-runtime
                        :world-manager app.world-manager
                        :active-world-entry app.active-world-entry
                        :active-world-runtime app.active-world-runtime
                        :graph-extension-registry app.graph-extension-registry
                        :builtin-graph-extension-handles app.builtin-graph-extension-handles
                        :preferred-interaction-surface app.preferred-interaction-surface
                        :active-interaction-surface app.active-interaction-surface
                        :active-activity-id app.active-activity-id
                       :workspace-shell-changed app.workspace-shell-changed
                       :canvas-visible? app.canvas-visible?
                       :scene-interactive? app.scene-interactive?
                       :canvas-interactive? app.canvas-interactive?
                       :active-pointer-controls app.active-pointer-controls
                       :object-selector app.object-selector
                       :layout-root app.layout-root
                       :next-frame app.next-frame})
      (var ok false)
      (var result nil)
      (var err nil)
      (var stage "boot")
      (local (run-ok run-result)
        (pcall
          (fn []
            (local flush-next-frame (install-next-frame-stub))
            (set app.hud hud)
            (set app.focus focus-manager)
            (set app.world-manager world-manager-stub)
            (set app.graph-extension-registry nil)
            (set app.builtin-graph-extension-handles nil)
            (Main.ensure-built-in-graph-extensions! {:world-manager world-manager-stub
                                                     :asset-path-resolver (fn [path]
                                                                            (app.engine:get-asset-path path))})
            (local JsonUtils (require :json-utils))
            (JsonUtils.write-json! (fs.join-path dir "world.json")
                                   {:activity {:active_id "graph"}})
            (world:activate runtime-context)
            (local runtime (assert (world:get-runtime)
                                   "drawing workflow e2e expected active runtime"))
            (set active-world-entry {:id world.id
                                     :world world})
            (apply-runtime-to-app world runtime hud)
            (flush-next-frame)
            (set click-timestamp 0)
            (set stage "run")
            (set result (run-fn {:world world
                                 :hud hud
                                 :runtime runtime
                                 :runtime-context runtime-context
                                 :flush-next-frame flush-next-frame
                                 :set-stage (fn [value]
                                              (set stage value))}))
            (set ok true))))
      (when (not run-ok)
        (set err (.. "[stage " stage "] " run-result)))
      (when world
        (world:drop runtime-context "e2e-drawing-workflow"))
      (Harness.cleanup-target hud)
      (when app.builtin-graph-extension-handles
        (for [i (length app.builtin-graph-extension-handles) 1 -1]
          (local handle (. app.builtin-graph-extension-handles i))
          (when (and handle handle.unregister)
            (handle:unregister))))
      (each [key value (pairs previous)]
        (set (. app key) value))
      (if ok
          result
          (error err)))))

(fn run [ctx]
  (with-home-world
    ctx
    (fn [env]
      (env.set-stage "assert start graph")
      (assert (= app.active-activity-id "graph")
              "drawing workflow e2e should start in graph activity")
      (env.set-stage "click draw")
      (click-button-icon env "draw")
      (env.set-stage "assert drawing mode")
      (assert (= app.active-activity-id "drawing")
              "drawing workflow e2e should enter drawing activity")
      (env.set-stage "add vector layer")
      (click-button env "+ Vector")
      (env.set-stage "assert vector layer active")
      (assert (= (. (active-layer) :kind) "vector")
              "drawing workflow e2e should activate a new vector layer before drawing")
      (env.set-stage "click rect")
      (click-button env "Rect")
      (env.set-stage "assert rect tool")
      (assert (= (app.drawing-controller:active-tool) "rectangle")
              "drawing workflow e2e should switch to rectangle tool")
      (env.set-stage "drag rectangle")
      (drag-on-canvas env
                      (glm.vec3 -12 -8 0)
                      (glm.vec3 12 8 0))
      (env.set-stage "assert rectangle count")
      (assert (= (object-count) 1)
              "drawing workflow e2e should create one rectangle")
      (env.set-stage "assert triangle vector")
      (assert (> (or (triangle-vector-length) 0) 0)
              "drawing workflow e2e should populate the canvas triangle vector")
      (env.set-stage "click graph")
      (click-button-icon env "account_tree")
      (env.set-stage "assert graph mode")
      (assert (= app.active-activity-id "graph")
              "drawing workflow e2e should switch back to graph activity")
      (env.set-stage "click draw again")
      (click-button-icon env "draw")
      (env.set-stage "assert drawing mode again")
      (assert (= app.active-activity-id "drawing")
              "drawing workflow e2e should switch back to drawing activity")
      (env.set-stage "click select")
      (click-button env "Select")
      (env.set-stage "assert select tool")
      (assert (= (app.drawing-controller:active-tool) "select")
              "drawing workflow e2e should switch to select tool")
      (env.set-stage "select rectangle")
      (click-at env (canvas-screen-point (glm.vec3 0 0 0)))
      (env.set-stage "assert selection")
      (assert (= (app.drawing-controller:selection-count) 1)
              "drawing workflow e2e should select the drawn rectangle")
      (env.set-stage "add raster layer")
      (click-button env "+ Raster")
      (env.set-stage "assert raster layer active")
      (assert (= (. (active-layer) :kind) "raster")
              "drawing workflow e2e should activate the new raster layer")
      (env.set-stage "assert raster tool memory")
      (assert (= (app.drawing-controller:active-tool) "brush")
              "drawing workflow e2e should auto-switch to the raster brush")
      (env.set-stage "paint raster stroke")
      (drag-on-canvas env
                      (glm.vec3 14 12 0)
                      (glm.vec3 22 4 0))
      (env.set-stage "assert raster tiles")
      (assert (> (raster-tile-count) 0)
              "drawing workflow e2e should allocate raster tiles after painting")
      (env.set-stage "assert raster image batch")
      (assert (> (image-batch-vertex-count) 0)
              "drawing workflow e2e should populate image batches for raster tiles")
      (env.set-stage "disable shape fill")
      (click-button env "Fill On")
      (env.set-stage "assert fill disabled")
      (assert (= (. (app.drawing-controller:current-defaults) :fill_enabled) false)
              "drawing workflow e2e should disable raster shape fill")
      (env.set-stage "draw raster outline rectangle")
      (click-button env "Rect")
      (drag-on-canvas env
                      (glm.vec3 12 -14 0)
                      (glm.vec3 28 2 0))
      (env.set-stage "pick fill color")
      (click-button env "Gold")
      (env.set-stage "fill raster region")
      (click-button env "Fill")
      (click-at env (canvas-screen-point (glm.vec3 20 -6 0)))
      (env.set-stage "sample fill color")
      (click-button env "Dropper")
      (click-at env (canvas-screen-point (glm.vec3 20 -6 0)))
      (env.set-stage "assert eyedropper color")
      (local sampled (. (app.drawing-controller:current-defaults) :stroke_color))
      (assert (> (. sampled 4) 0.15)
              (string.format "drawing workflow e2e eyedropper alpha too low: %.3f %.3f %.3f %.3f"
                             (. sampled 1) (. sampled 2) (. sampled 3) (. sampled 4)))
      (assert (> (. sampled 1) (. sampled 3))
              (string.format "drawing workflow e2e eyedropper should sample a warm fill color: %.3f %.3f %.3f %.3f"
                             (. sampled 1) (. sampled 2) (. sampled 3) (. sampled 4)))
      (assert (> (. sampled 2) (. sampled 3))
              (string.format "drawing workflow e2e eyedropper should keep green above blue for the filled region: %.3f %.3f %.3f %.3f"
                             (. sampled 1) (. sampled 2) (. sampled 3) (. sampled 4)))
      (env.set-stage "marquee raster selection")
      (click-button env "Marquee")
      (drag-on-canvas env
                      (glm.vec3 10 -16 0)
                      (glm.vec3 30 4 0))
      (env.set-stage "assert raster selection")
      (assert (= (app.drawing-controller:selection-count) 1)
              "drawing workflow e2e should create a raster marquee selection")
      (env.set-stage "move raster selection")
      (click-button env "Move")
      (drag-on-canvas env
                      (glm.vec3 20 -6 0)
                      (glm.vec3 30 4 0))
      (env.set-stage "assert moved raster selection")
      (assert (= (app.drawing-controller:selection-count) 1)
              "drawing workflow e2e should keep the raster selection active after move")
      (local moved-selection (app.drawing-controller:raster-selection))
      (assert moved-selection
              "drawing workflow e2e should retain raster selection metadata after move")
      (assert (> moved-selection.bounds.left 10)
              "drawing workflow e2e should move the raster selection to the right")
      (env.set-stage "capture snapshot")
      (stabilize-graph-view-for-snapshot)
      (Harness.draw-targets ctx.width
                            ctx.height
                            [{:target app.canvas}
                             {:target app.hud :clear-depth? true}])
      (Harness.capture-snapshot {:name "drawing-workflow"
                                 :width ctx.width
                                 :height ctx.height
                                 :tolerance 3})
      (env.set-stage "final update")
      (refresh-world env))))

(fn main []
  (Harness.with-app {:width 1280 :height 720}
                    (fn [ctx]
                      (run ctx)))
  (print "E2E drawing workflow complete"))

{:run run
 :main main}
