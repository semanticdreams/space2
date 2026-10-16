(local AppBootstrap (require :app-bootstrap))
(local fennel (require :fennel))
(local fs (require :fs))
(local tempfile (require :tempfile))
(local HotReload (require :hot-reload))
(local LauncherLaunchable (require :launchables/launcher))
(local runtime (require :runtime))
(local Activities (require :activities))
(local Units (require :units))

(local tests [])

(fn restore-test-runner-app-services! []
  (AppBootstrap.init-themes)
  (AppBootstrap.init-lights)
  (AppBootstrap.init-input-systems)
  true)

(fn drop-main-and-restore-test-fixture! []
  (local main-mod (. package.loaded "main"))
  (when (and main-mod (= (type main-mod.drop) :function))
    (main-mod.drop))
  (restore-test-runner-app-services!))

(fn require-main! []
  (set (. package.loaded "main") nil)
  (require :main))

(fn make-renderer-stub []
  (var skybox-state {:enabled? false :name "lake" :brightness 0.5 :tint-color [1.0 1.0 1.0]})
  (var background-state {:enabled? false :color [0.5 0.5 0.5] :texture nil})
  {:skybox {:set-state (fn [_self state]
                          (set skybox-state state)
                          true)
            :get-state (fn [_self]
                         skybox-state)}
   :set-background-state (fn [_self state]
                           (set background-state state)
                           true)
   :get-background-state (fn [_self]
                            background-state)
   :apply-theme (fn [_self _theme] true)
   :prerender-sub-apps (fn [_self] true)
   :draw-target (fn [_self _target _opts] true)
   :update (fn [_self] true)
    :on-viewport-changed (fn [_self _viewport] true)
    :drop (fn [_self] true)})

(fn apply-renderer-viewport! [opts]
  (when (and app.renderers opts.viewport)
    (app.renderers:on-viewport-changed opts.viewport)))

(fn with-temp-dir [f]
  (local handle (tempfile.TemporaryDirectory {:prefix "units-test-"}))
  (local path handle.path)
  (local (ok result) (pcall f path))
  (handle:drop)
  (if ok
      result
      (error result)))

(fn finish-protected-result [body-ok body-result cleanup-ok cleanup-result]
  (if body-ok
      (if cleanup-ok body-result (error cleanup-result))
      (error body-result)))

(fn cleanup-app-hot-reload-controller-and-main! []
  (when app.hot-reload-controller
    (app.hot-reload-controller:drop)
    (set app.hot-reload-controller nil))
  (when (= (type (. (require :main) :drop)) :function)
    (drop-main-and-restore-test-fixture!)))

(fn cleanup-main-if-engine! []
  (when (and (= (type (. (require :main) :drop)) :function) app.engine)
    (drop-main-and-restore-test-fixture!)))

(fn cleanup-main-loaded! []
  (when (= (type (. (require :main) :drop)) :function)
    (drop-main-and-restore-test-fixture!)))

(fn cleanup-main-var-if-engine! [Main]
  (when (and (= (type Main.drop) :function) app.engine)
    (Main.drop)
    (restore-test-runner-app-services!)))

(fn cleanup-controller-and-main-if-engine! [controller]
  (when controller
    (controller:drop))
  (cleanup-main-if-engine!))

(fn count-searcher-occurrences [target]
  (var count 0)
  (each [_ searcher (ipairs package.searchers)]
    (when (= searcher target)
      (set count (+ count 1))))
  count)

(fn activity-unit [mode-id]
  (and app.activity-units
       (. app.activity-units mode-id)))

;; Slow full-app / hot-reload integration tests moved from tests.test-units.

(fn test-hot-reload-config [watch-root narrow-unit-ids]
  {:enabled true
   :watch-paths [watch-root]
   :narrow-reload-unit-ids narrow-unit-ids
   :preserve-modules ["app-bootstrap" "hot-reload" "tests.test-hot-reload-integration" "units"]})

(fn assert-root-reload-state! [controller callback-id world-id DebugLog]
  (assert (= (. (controller:debug-state) :last-target-unit-id) "app-root")
          "Default controller execution must target app root")
  (assert app.world-manager "Expected app.world-manager after reload")
  (assert (= (app.world-manager:active-world-id) world-id)
          "Expected active world id to roundtrip through full-app reload")
  (assert (string.find (fs.read-file DebugLog.log-path) "root reload marker" 1 true)
          "Expected root reload to preserve debug.log history")
  (assert (= app.hot-reload-controller controller) "Root reload must retain its controller")
  (assert (= app.hot-reload-callback-id callback-id) "Root reload must retain its callback ID")
  (assert package.__space_fennel_cache_searcher "Expected installed fennel cache searcher")
  (assert (= (count-searcher-occurrences package.__space_fennel_cache_searcher) 1)
          "Expected exactly one installed fennel cache searcher after repeated reloads"))

(fn assert-default-root-roundtrips! [watch-root DebugLog]
  (local controller (assert app.hot-reload-controller "Main must construct the reload controller"))
  (local callback-id (assert app.hot-reload-callback-id "Main must register the reload callback"))
  (DebugLog.log "test" "root reload marker")
  (local created-world (app.world-manager:create-home-world {:activate? false}))
  (assert (app.world-manager:activate-world-id created-world.id))
  (each [_ filename (ipairs ["main.fnl" "hud.fnl" "hud.fnl"])]
    (local old-world-manager app.world-manager)
    (assert (controller:reload-now! {:changes [{:path (fs.join-path watch-root filename)
                                               :action "modified"}]})
            "Expected default root hot reload to succeed")
    (assert (not (= app.world-manager old-world-manager)) "Default reload must reconstruct root ownership")
    (assert-root-reload-state! controller callback-id created-world.id DebugLog)))

(fn run-cleanup-stages! [stages]
  (local errors [])
  (each [_ stage (ipairs stages)]
    (local (ok err) (pcall (. stage 2)))
    (when (not ok) (table.insert errors (.. (. stage 1) ": " (tostring err)))))
  (when (> (# errors) 0) (error (table.concat errors "\n") 0)))

(fn field-restoration [target key]
  (local value (. target key))
  (fn restore [] (set (. target key) value))
  [key restore])

(fn drain-cleanup-slot! [slot]
  (local cleanup slot.cleanup)
  (set slot.cleanup nil) ; consume BEFORE any partial Main.drop
  (when cleanup (cleanup)))

(fn drop-owned-root-controller! [fixture-app owned]
  (local controller fixture-app.hot-reload-controller)
  (when (and controller (not (= controller owned.original-controller)))
    (set fixture-app.hot-reload-controller nil) (controller:drop)))

(fn drop-owned-root-main! [owned loaded]
  (when owned.init-entered?
    (local Main (if loaded loaded owned.main))
    (assert (= (type Main.drop) :function) "owned Main cleanup handler missing")
    (Main.drop)))

(local root-cleanup-slot {})
(fn teardown-root-fixture [] (drain-cleanup-slot! root-cleanup-slot))

(fn full-app-root-reload-roundtrips-active-world []
  (local owned {:original-controller app.hot-reload-controller :init-entered? false})
  (local restorations [])
  (fn drop-controller [] (drop-owned-root-controller! app owned))
  (fn drop-main [] (drop-owned-root-main! owned (. package.loaded "main")))
  (fn drop-temp [] (when owned.temp (owned.temp:drop)))
  (fn cleanup []
    (local stages [["controller" drop-controller] ["Main.drop" drop-main]
                  ["themes" AppBootstrap.init-themes] ["lights" AppBootstrap.init-lights]
                  ["input" AppBootstrap.init-input-systems]])
    (each [_ restore (ipairs restorations)] (table.insert stages restore))
    (table.insert stages ["temp" drop-temp])
    (run-cleanup-stages! stages))
  (set root-cleanup-slot.cleanup cleanup)
  (set owned.temp (tempfile.TemporaryDirectory {:prefix "units-test-"}))
  (set owned.main (require-main!))
  (local DebugLog (require :debug-log))
  (each [_ key (ipairs [:renderers :hot-reload-config :hot-reload-controller :worlds-dir])]
    (table.insert restorations (field-restoration app key)))
  (local watch-root (fs.join-path runtime.assets-path "lua"))
  (set app.hot-reload-controller nil)
  (set app.hot-reload-config (test-hot-reload-config watch-root nil))
  ((. owned.main :install-app-shell!))
  (set owned.init-entered? true)
  ((. owned.main :init))
  (assert-default-root-roundtrips! watch-root DebugLog)
  true)

(fn drop-app-cleans-hot-reload-controller-and-callback []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local original-init-renderers AppBootstrap.init-renderers)
      (local original-renderers app.renderers)
      (local original-config app.hot-reload-config)
      (set AppBootstrap.init-renderers
           (fn [opts]
             (set app.renderers (make-renderer-stub))
              (apply-renderer-viewport! opts)
             app.renderers))
      (set app.hot-reload-config {:enabled true
                                  :watch-paths [(fs.join-path runtime.assets-path "lua")]
                                  :preserve-modules ["app-bootstrap"
                                                     "hot-reload"
                                                     "tests.test-hot-reload-integration"
                                                     "units"]})
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init))
            (assert app.hot-reload-controller
                    "Expected app.hot-reload-controller after init")
            (assert app.hot-reload-callback-id
                    "Expected app.hot-reload-callback-id after init")
            ((. Main :drop))
            (assert (= app.hot-reload-controller nil)
                    "Expected drop to clear app.hot-reload-controller")
            (assert (= app.hot-reload-callback-id nil)
                    "Expected drop to clear app.hot-reload-callback-id")
            true)))
      (local (cleanup-ok cleanup-result)
        (pcall cleanup-main-var-if-engine! Main))
      (set app.renderers original-renderers)
      (set AppBootstrap.init-renderers original-init-renderers)
      (set app.hot-reload-config original-config)
      (finish-protected-result ok result cleanup-ok cleanup-result))))

(fn app-init-refreshes-agent-preset-context-after-drop []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local original-init-renderers AppBootstrap.init-renderers)
      (local original-renderers app.renderers)
      (set AppBootstrap.init-renderers
           (fn [opts]
             (set app.renderers (make-renderer-stub))
              (apply-renderer-viewport! opts)
             app.renderers))
      (var controller nil)
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init))
            (app.agent-presets:set-context {:surface :canvas
                                             :activity "stale-mode"
                                             :canvas-visible? true})
            ((. Main :drop))
            ((. Main :install-app-shell!))
            ((. Main :init))
            (local reset-context (app.agent-presets:get-context))
            (assert (= reset-context.surface app.active-interaction-surface)
                    "Expected app init to refresh preset surface from current shell state")
            (assert (= reset-context.activity app.active-activity-id)
                    "Expected app init to refresh preset activity from current shell state")
            (assert (= reset-context.canvas-visible? (= app.canvas-visible? true))
                    "Expected app init to refresh preset canvas visibility from current shell state")
            (assert (not (= reset-context.activity "stale-mode"))
                    "Expected app init to overwrite stale preset context")
            true)))
      (local (cleanup-ok cleanup-result)
        (pcall cleanup-main-loaded!))
      (set app.renderers original-renderers)
      (set AppBootstrap.init-renderers original-init-renderers)
      (finish-protected-result ok result cleanup-ok cleanup-result))))

(fn hud-unit-reload-roundtrips-panel-state []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local original-init-renderers AppBootstrap.init-renderers)
      (local original-renderers app.renderers)
      (set AppBootstrap.init-renderers
           (fn [opts]
             (set app.renderers (make-renderer-stub))
              (apply-renderer-viewport! opts)
             app.renderers))
      (var controller nil)
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init))
            (assert app.hud-unit "Expected app.hud-unit after app init")
            (assert app.hud "Expected app.hud after app init")
            (local old-hud app.hud)
            (local old-scope app.hud-focus-scope)
            (LauncherLaunchable.open-panel
              {:hud app.hud
               :panel {:layer "float"
                       :position [2 3 0]
                       :rotation [1 0 0 0]
                       :size [12 8 0]}})
            (app.hud:update)
            (local before-state (app.hud:capture-state))
            (local before-panel (. before-state.panels 1))
            (assert before-panel "Expected HUD panel before reload")
            (assert (app.hud-unit:reload {})
                    "Expected HUD unit reload to succeed")
            (assert app.hud "Expected app.hud after HUD unit reload")
            (assert (not (= app.hud old-hud))
                    "HUD unit reload should replace the HUD instance")
            (assert (not (= app.hud-focus-scope old-scope))
                    "HUD unit reload should replace the HUD focus scope")
            (app.hud:update)
            (local after-state (app.hud:capture-state))
            (local after-panel (. after-state.panels 1))
            (assert after-panel "Expected HUD panel after reload")
            (assert (= (length (or after-state.panels []))
                       (length (or before-state.panels [])))
                    "Expected HUD unit reload to preserve panel count")
            (assert (= after-panel.kind before-panel.kind)
                    "Expected HUD unit reload to preserve panel kind")
            (assert (= after-panel.layer before-panel.layer)
                    "Expected HUD unit reload to preserve panel layer")
            (assert (= after-panel.restorer-module before-panel.restorer-module)
                    "Expected HUD unit reload to preserve panel restorer module")
            (assert (= (fennel.view after-panel.relative-size)
                       (fennel.view before-panel.relative-size))
                    "Expected HUD unit reload to preserve panel size")
            (assert after-panel.relative-position
                    "Expected HUD unit reload to preserve panel position state")
            true)))
      (local (cleanup-ok cleanup-result)
        (pcall cleanup-controller-and-main-if-engine! controller))
      (set app.renderers original-renderers)
      (set AppBootstrap.init-renderers original-init-renderers)
      (finish-protected-result ok result cleanup-ok cleanup-result))))

(fn assert-experimental-hud-opt-in! [watch-root]
  (assert app.hud-unit "Expected app.hud-unit after app init")
  (local controller (assert app.hot-reload-controller "Main must construct the opted-in controller"))
  (local old-hud app.hud)
  (local old-scope app.hud-focus-scope)
  (local old-world-manager app.world-manager)
  (LauncherLaunchable.open-panel
    {:hud app.hud
     :panel {:layer "float" :position [4 5 0] :rotation [1 0 0 0] :size [14 9 0]}})
  (app.hud:update)
  (local before-state (app.hud:capture-state))
  (assert (controller:reload-now! {:changes [{:path (fs.join-path watch-root "hud.fnl")
                                             :action "modified"}]})
          "Expected opted-in HUD file change to reload successfully")
  (assert (= (. (controller:debug-state) :last-target-unit-id) "hud")
          "Main config must forward explicit HUD eligibility through both config tables and wrapper")
  (assert app.hud "Expected app.hud after routed reload")
  (assert (not (= app.hud old-hud)) "Expected routed HUD reload to replace app.hud")
  (assert (not (= app.hud-focus-scope old-scope)) "Expected routed HUD reload to replace HUD focus scope")
  (assert (= app.world-manager old-world-manager) "Expected opted-in HUD reload to avoid app root")
  (app.hud:update)
  (local after-state (app.hud:capture-state))
  (assert (= (length (or after-state.panels [])) (length (or before-state.panels [])))
          "Expected routed HUD reload to preserve panel count"))

;; Built-in child routing below is experimental explicit opt-in evidence, not freshness certification.
(fn hot-reload-routes-hud-file-changes-to-hud-unit []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local original-init-renderers AppBootstrap.init-renderers)
      (local original-renderers app.renderers)
      (local original-config app.hot-reload-config)
      (local watch-root (fs.join-path runtime.assets-path "lua"))
      (set AppBootstrap.init-renderers
           (fn [opts]
             (set app.renderers (make-renderer-stub))
              (apply-renderer-viewport! opts)
             app.renderers))
      (set app.hot-reload-config (test-hot-reload-config watch-root ["hud"]))
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init))
            (assert-experimental-hud-opt-in! watch-root)
            true)))
      (local (cleanup-ok cleanup-result)
        (pcall cleanup-app-hot-reload-controller-and-main!))
      (set app.renderers original-renderers)
      (set AppBootstrap.init-renderers original-init-renderers)
      (set app.hot-reload-config original-config)
      (finish-protected-result ok result cleanup-ok cleanup-result))))

(fn canvas-unit-reload-roundtrips-surface-state []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local original-init-renderers AppBootstrap.init-renderers)
      (local original-renderers app.renderers)
      (set AppBootstrap.init-renderers
           (fn [opts]
             (set app.renderers (make-renderer-stub))
              (apply-renderer-viewport! opts)
             app.renderers))
      (var controller nil)
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init))
            (assert app.canvas-unit "Expected app.canvas-unit after app init")
            (assert app.canvas "Expected app.canvas after app init")
            (assert app.canvas-controls "Expected app.canvas-controls after app init")
            (app.set-active-activity nil)
            (assert (not app.graph-view)
                     "Graph view should not exist before graph activity is active")
            (assert app.object-selector "Expected app.object-selector after app init")
            (local old-canvas app.canvas)
            (local old-scope app.canvas-focus-scope)
            (local old-controls app.canvas-controls)
            (local old-object-selector app.object-selector)
            (local old-graph app.graph)
            (local old-drawing-controller app.drawing-controller)
            (local old-world-manager app.world-manager)
            (LauncherLaunchable.open-panel
              {:target app.canvas
               :panel {:layer "float"
                       :position [6 7 0]
                       :rotation [1 0 0 0]
                       :size [16 10 0]}})
            (app.set-active-activity "drawing")
            (app.set-active-interaction-surface :canvas
                                                {:sync-canvas-visibility true})
            (app.canvas:update)
            (local before-state (app.canvas:capture-state))
            (local before-panel (. before-state.panels 1))
            (assert before-panel "Expected canvas panel before reload")
            (assert (app.canvas-unit:reload {})
                    "Expected canvas unit reload to succeed")
            (assert app.canvas "Expected app.canvas after canvas unit reload")
            (assert (not (= app.canvas old-canvas))
                    "Canvas unit reload should replace the canvas instance")
            (assert (not (= app.canvas-focus-scope old-scope))
                    "Canvas unit reload should replace the canvas focus scope")
            (assert (not (= app.canvas-controls old-controls))
                    "Canvas unit reload should replace canvas controls")
            (assert (not app.graph-view)
                    "Canvas unit reload should not create graph view while drawing activity is active")
            (assert (not (= app.object-selector old-object-selector))
                    "Canvas unit reload should replace object selector")
            (assert (= app.graph old-graph)
                    "Canvas unit reload should preserve graph state owner")
            (assert (= app.drawing-controller old-drawing-controller)
                    "Canvas unit reload should preserve drawing controller")
            (assert (= app.world-manager old-world-manager)
                    "Canvas unit reload should avoid reloading world manager")
            (assert (= app.active-activity-id "drawing")
                    "Canvas unit reload should preserve active activity")
            (assert (= app.active-interaction-surface :canvas)
                    "Canvas unit reload should preserve active interaction surface")
            (assert (= app.canvas-visible? true)
                    "Canvas unit reload should preserve canvas visibility")
            (app.canvas:update)
            (local after-state (app.canvas:capture-state))
            (local after-panel (. after-state.panels 1))
            (assert after-panel "Expected canvas panel after reload")
            (assert (= (length (or after-state.panels []))
                       (length (or before-state.panels [])))
                    "Expected canvas unit reload to preserve panel count")
            (assert (= after-panel.kind before-panel.kind)
                    "Expected canvas unit reload to preserve panel kind")
            (assert (= after-panel.restorer-module before-panel.restorer-module)
                    "Expected canvas unit reload to preserve panel restorer module")
            true)))
      (local (cleanup-ok cleanup-result)
        (pcall cleanup-controller-and-main-if-engine! controller))
      (set app.renderers original-renderers)
      (set AppBootstrap.init-renderers original-init-renderers)
      (finish-protected-result ok result cleanup-ok cleanup-result))))

(fn hot-reload-routes-canvas-file-changes-to-canvas-unit []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local original-init-renderers AppBootstrap.init-renderers)
      (local original-renderers app.renderers)
      (local watch-root (fs.join-path runtime.assets-path "lua"))
      (set AppBootstrap.init-renderers
           (fn [opts]
             (set app.renderers (make-renderer-stub))
              (apply-renderer-viewport! opts)
             app.renderers))
      (var controller nil)
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init))
            (assert app.canvas-unit "Expected app.canvas-unit after app init")
            (assert app.hud-unit "Expected app.hud-unit after app init")
            (local root-unit
              (Units.ModuleUnit
                {:id "app-root"
                 :owned-paths [watch-root]
                 :module-name "main"
                 :suppress-run-main? true
                 :load-export "init"
                 :unload-export "drop"
                 :snapshot-export "snapshot"
                 :restore-export "restore"}))
            (set controller
              (HotReload.HotReloadController
                {:unit root-unit
                  :units-fn (fn [_root-unit]
                              [app.canvas-unit app.hud-unit])
                  :root-unit-id "app-root"
                  :narrow-reload-unit-ids ["canvas"]
                  :watch-paths [watch-root]
                 :preserve-modules ["app-bootstrap"
                                    "hot-reload"
                                    "tests.test-hot-reload-integration"
                                    "units"]}))
            (local old-canvas app.canvas)
            (local old-world-manager app.world-manager)
            (local old-graph app.graph)
            (LauncherLaunchable.open-panel
              {:target app.canvas
               :panel {:layer "float"
                       :position [8 9 0]
                       :rotation [1 0 0 0]
                       :size [18 11 0]}})
            (app.set-active-activity "drawing")
            (app.set-active-interaction-surface :canvas
                                                {:sync-canvas-visibility true})
            (app.canvas:update)
            (local before-state (app.canvas:capture-state))
            (assert (controller:reload-now!
                      {:changes [{:path (fs.join-path watch-root "canvas.fnl")
                                  :action "modified"}]})
                    "Expected canvas file change to reload successfully")
            (local debug-state (controller:debug-state))
            (assert (= debug-state.last-target-unit-id "canvas")
                    "Expected canvas file change to target canvas unit")
            (assert app.canvas "Expected app.canvas after routed canvas reload")
            (assert (not (= app.canvas old-canvas))
                    "Expected routed canvas reload to replace app.canvas")
            (assert (= app.world-manager old-world-manager)
                    "Expected routed canvas reload to avoid reloading app root")
            (assert (= app.graph old-graph)
                    "Expected routed canvas reload to preserve graph owner")
            (assert (= app.active-activity-id "drawing")
                    "Expected routed canvas reload to preserve active activity")
            (assert (= app.active-interaction-surface :canvas)
                    "Expected routed canvas reload to preserve interaction surface")
            (app.canvas:update)
            (local after-state (app.canvas:capture-state))
            (assert (= (length (or after-state.panels []))
                       (length (or before-state.panels [])))
                    "Expected routed canvas reload to preserve panel count")
            true)))
      (local (cleanup-ok cleanup-result)
        (pcall cleanup-controller-and-main-if-engine! controller))
      (set app.renderers original-renderers)
      (set AppBootstrap.init-renderers original-init-renderers)
      (finish-protected-result ok result cleanup-ok cleanup-result))))

(fn hot-reload-routes-workspace-shell-state-file-changes-to-app-root []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local original-init-renderers AppBootstrap.init-renderers)
      (local original-renderers app.renderers)
      (local watch-root (fs.join-path runtime.assets-path "lua"))
      (set AppBootstrap.init-renderers
           (fn [opts]
             (set app.renderers (make-renderer-stub))
              (apply-renderer-viewport! opts)
             app.renderers))
      (var controller nil)
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init))
            (assert app.canvas-unit "Expected app.canvas-unit after app init")
            (assert app.hud-unit "Expected app.hud-unit after app init")
            (local root-unit
              (Units.ModuleUnit
                {:id "app-root"
                 :owned-paths [watch-root]
                 :module-name "main"
                 :suppress-run-main? true
                 :load-export "init"
                 :unload-export "drop"
                 :snapshot-export "snapshot"
                 :restore-export "restore"}))
            (set controller
              (HotReload.HotReloadController
                {:unit root-unit
                 :units-fn (fn [_root-unit]
                             [app.canvas-unit app.hud-unit])
                 :root-unit-id "app-root"
                 :watch-paths [watch-root]
                 :preserve-modules ["app-bootstrap"
                                    "hot-reload"
                                    "tests.test-hot-reload-integration"
                                    "units"]}))
            (local old-world-manager app.world-manager)
            (assert (controller:reload-now!
                       {:changes [{:path (fs.join-path watch-root
                                                       "home-world-workspace-shell-state.fnl")
                                   :action "modified"}]})
                    "Expected workspace shell state change to reload successfully")
            (local debug-state (controller:debug-state))
            (assert (= debug-state.last-target-unit-id "app-root")
                    "Expected workspace shell state change to target app root")
            (assert app.world-manager "Expected app.world-manager after app-root reload")
            (assert (not (= app.world-manager old-world-manager))
                    "Expected workspace shell helper reload to replace app root ownership")
            true)))
      (local (cleanup-ok cleanup-result)
        (pcall cleanup-controller-and-main-if-engine! controller))
      (set app.renderers original-renderers)
      (set AppBootstrap.init-renderers original-init-renderers)
      (finish-protected-result ok result cleanup-ok cleanup-result))))

(fn hot-reload-routes-shared-triangle-line-to-canvas-unit []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local original-init-renderers AppBootstrap.init-renderers)
      (local original-renderers app.renderers)
      (local watch-root (fs.join-path runtime.assets-path "lua"))
      (set AppBootstrap.init-renderers
           (fn [opts]
             (set app.renderers (make-renderer-stub))
              (apply-renderer-viewport! opts)
             app.renderers))
      (var controller nil)
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init))
            (app.set-active-activity "graph")
            (assert app.graph-view "Expected graph activity to create graph view before shared renderer reload")
            (local root-unit
              (Units.ModuleUnit
                {:id "app-root"
                 :owned-paths [watch-root]
                 :module-name "main"
                 :suppress-run-main? true
                 :load-export "init"
                 :unload-export "drop"
                 :snapshot-export "snapshot"
                 :restore-export "restore"}))
            (set controller
              (HotReload.HotReloadController
                {:unit root-unit
                 :units-fn (fn [_root-unit]
                              [app.canvas-unit
                               app.hud-unit
                               (activity-unit "graph")
                               (activity-unit "board")])
                  :root-unit-id "app-root"
                  :narrow-reload-unit-ids ["canvas"]
                 :watch-paths [watch-root]
                 :preserve-modules ["app-bootstrap"
                                    "hot-reload"
                                    "tests.test-hot-reload-integration"
                                    "units"]}))
            (assert (controller:reload-now!
                      {:changes [{:path (fs.join-path watch-root "triangle-line.fnl")
                                  :action "modified"}]})
                    "Expected shared triangle-line change to reload successfully")
            (local debug-state (controller:debug-state))
            (assert (= debug-state.last-target-unit-id "canvas")
                    "Shared triangle-line changes should target the canvas unit")
            (assert (= app.active-activity-id "graph")
                    "Canvas unit reload should preserve active graph activity for shared triangle-line changes")
            (assert app.graph-view
                    "Canvas unit reload should recreate graph view for shared triangle-line changes")
            true)))
      (local (cleanup-ok cleanup-result)
        (pcall cleanup-controller-and-main-if-engine! controller))
      (set app.renderers original-renderers)
      (set AppBootstrap.init-renderers original-init-renderers)
      (finish-protected-result ok result cleanup-ok cleanup-result))))

(fn hot-reload-routes-drawing-render-file-changes-to-drawing-activity-unit []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local original-init-renderers AppBootstrap.init-renderers)
      (local original-renderers app.renderers)
      (local watch-root (fs.join-path runtime.assets-path "lua"))
      (set AppBootstrap.init-renderers
           (fn [opts]
             (set app.renderers (make-renderer-stub))
              (apply-renderer-viewport! opts)
             app.renderers))
      (var controller nil)
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init))
            (assert (activity-unit "drawing")
                    "Expected drawing canvas activity unit after app init")
            (app.set-active-activity "drawing")
            (assert (= app.active-activity-id "drawing")
                    "Expected drawing activity to become active before routed reload")
            (assert (= app.activity-drawing-enabled? true)
                    "Expected drawing activity hooks before routed reload")
            (local root-unit
              (Units.ModuleUnit
                {:id "app-root"
                 :owned-paths [watch-root]
                 :module-name "main"
                 :suppress-run-main? true
                 :load-export "init"
                 :unload-export "drop"
                 :snapshot-export "snapshot"
                 :restore-export "restore"}))
            (set controller
              (HotReload.HotReloadController
                {:unit root-unit
                 :units-fn (fn [_root-unit]
                              [app.canvas-unit
                               app.hud-unit
                               (activity-unit "drawing")])
                  :root-unit-id "app-root"
                  :narrow-reload-unit-ids ["drawing-activity"]
                 :watch-paths [watch-root]
                 :preserve-modules ["app-bootstrap"
                                    "hot-reload"
                                    "tests.test-hot-reload-integration"
                                    "units"]}))
            (assert (controller:reload-now!
                      {:changes [{:path (fs.join-path watch-root
                                                       "drawing"
                                                       "render.fnl")
                                   :action "modified"}]})
                    "Expected drawing render file change to reload successfully")
            (local debug-state (controller:debug-state))
            (assert (= debug-state.last-target-unit-id "drawing-activity")
                    "Expected drawing render file change to target drawing activity unit")
            (assert (= app.active-activity-id "drawing")
                    "Expected drawing activity unit reload to preserve active activity")
            (assert (= app.activity-drawing-enabled? true)
                    "Expected drawing activity unit reload to restore drawing hooks")
            (assert app.activity-command-hints-provider
                    "Expected drawing activity unit reload to restore command hints hook")
            true)))
      (local (cleanup-ok cleanup-result)
        (pcall cleanup-controller-and-main-if-engine! controller))
      (set app.renderers original-renderers)
      (set AppBootstrap.init-renderers original-init-renderers)
      (finish-protected-result ok result cleanup-ok cleanup-result))))

(fn hot-reload-routes-graph-view-file-changes-to-graph-activity-unit []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local original-init-renderers AppBootstrap.init-renderers)
      (local original-renderers app.renderers)
      (local watch-root (fs.join-path runtime.assets-path "lua"))
      (set AppBootstrap.init-renderers
           (fn [opts]
             (set app.renderers (make-renderer-stub))
              (apply-renderer-viewport! opts)
             app.renderers))
      (var controller nil)
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init))
            (assert (activity-unit "graph")
                    "Expected graph canvas activity unit after app init")
            (app.set-active-activity "graph")
            (assert app.graph-view "Expected graph activity to create graph view")
            (local root-unit
              (Units.ModuleUnit
                {:id "app-root"
                 :owned-paths [watch-root]
                 :module-name "main"
                 :suppress-run-main? true
                 :load-export "init"
                 :unload-export "drop"
                 :snapshot-export "snapshot"
                 :restore-export "restore"}))
            (set controller
              (HotReload.HotReloadController
                {:unit root-unit
                 :units-fn (fn [_root-unit]
                              [app.canvas-unit
                               app.hud-unit
                               (activity-unit "graph")])
                  :root-unit-id "app-root"
                  :narrow-reload-unit-ids ["graph-activity"]
                 :watch-paths [watch-root]
                 :preserve-modules ["app-bootstrap"
                                    "hot-reload"
                                    "tests.test-hot-reload-integration"
                                    "units"]}))
            (assert (controller:reload-now!
                      {:changes [{:path (fs.join-path watch-root
                                                      "graph"
                                                      "view"
                                                      "init.fnl")
                                  :action "modified"}]})
                    "Expected graph view file change to reload successfully")
            (local debug-state (controller:debug-state))
            (assert (= debug-state.last-target-unit-id "graph-activity")
                    "Expected graph view file change to target graph activity unit")
            (assert (= app.active-activity-id "graph")
                    "Expected graph activity unit reload to preserve active activity")
            (assert app.graph-view
                    "Expected graph activity unit reload to restore graph view")
            true)))
      (local (cleanup-ok cleanup-result)
        (pcall cleanup-controller-and-main-if-engine! controller))
      (set app.renderers original-renderers)
      (set AppBootstrap.init-renderers original-init-renderers)
      (finish-protected-result ok result cleanup-ok cleanup-result))))

(fn graph-activity-registers-active-activity-snapshot-hooks []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local original-init-renderers AppBootstrap.init-renderers)
      (local original-renderers app.renderers)
      (set AppBootstrap.init-renderers
           (fn [opts]
             (set app.renderers (make-renderer-stub))
              (apply-renderer-viewport! opts)
             app.renderers))
      (var controller nil)
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init))
            (app.set-active-activity "graph")
            (assert app.graph-view "Expected graph activity to create graph view")
            (local snapshot (Activities.snapshot-active-activity))
            (assert (and snapshot snapshot.active?)
                    "Graph activity snapshot should report active graph activity")
            (assert (and snapshot.graph-view-state snapshot.graph-view-state.views)
                    "Graph activity snapshot should include graph-view state")
            (Activities.restore-active-activity snapshot)
            (assert app.graph-view
                    "Graph activity restore-active-activity should keep graph view active")
            true)))
      (local (cleanup-ok cleanup-result)
        (pcall cleanup-controller-and-main-if-engine! controller))
      (set app.renderers original-renderers)
      (set AppBootstrap.init-renderers original-init-renderers)
      (finish-protected-result ok result cleanup-ok cleanup-result))))

(fn hot-reload-routes-board-file-changes-to-board-activity-unit []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local original-init-renderers AppBootstrap.init-renderers)
      (local original-renderers app.renderers)
      (local watch-root (fs.join-path runtime.assets-path "lua"))
      (set AppBootstrap.init-renderers
           (fn [opts]
             (set app.renderers (make-renderer-stub))
          (apply-renderer-viewport! opts)
             app.renderers))
      (var controller nil)
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init))
            (assert (activity-unit "board")
                    "Expected board canvas activity unit after app init")
            (app.set-active-activity "board")
            (assert app.board-view "Expected board activity to create board view")
            (local root-unit
              (Units.ModuleUnit
                {:id "app-root"
                 :owned-paths [watch-root]
                 :module-name "main"
                 :suppress-run-main? true
                 :load-export "init"
                 :unload-export "drop"
                 :snapshot-export "snapshot"
                 :restore-export "restore"}))
            (set controller
              (HotReload.HotReloadController
                {:unit root-unit
                 :units-fn (fn [_root-unit]
                              [app.canvas-unit
                               app.hud-unit
                               (activity-unit "board")])
                  :root-unit-id "app-root"
                  :narrow-reload-unit-ids ["board-activity"]
                 :watch-paths [watch-root]
                 :preserve-modules ["app-bootstrap"
                                    "hot-reload"
                                    "tests.test-hot-reload-integration"
                                    "units"]}))
            (assert (controller:reload-now!
                      {:changes [{:path (fs.join-path watch-root
                                                      "board"
                                                      "view.fnl")
                                  :action "modified"}]})
                    "Expected board file change to reload successfully")
            (local debug-state (controller:debug-state))
            (assert (= debug-state.last-target-unit-id "board-activity")
                    "Expected board file change to target board activity unit")
            (assert (= app.active-activity-id "board")
                    "Expected board activity unit reload to preserve active activity")
            (assert app.board-view
                    "Expected board activity unit reload to restore board view")
            true)))
      (local (cleanup-ok cleanup-result)
        (pcall cleanup-controller-and-main-if-engine! controller))
      (set app.renderers original-renderers)
      (set AppBootstrap.init-renderers original-init-renderers)
      (finish-protected-result ok result cleanup-ok cleanup-result))))

(fn unloading-active-drawing-activity-updates-shell-state []
  (local Main (require-main!))
  (local original-init-renderers AppBootstrap.init-renderers)
  (local original-renderers app.renderers)
  (set AppBootstrap.init-renderers
       (fn [opts]
         (set app.renderers (make-renderer-stub))
              (apply-renderer-viewport! opts)
         app.renderers))
  (local (ok result)
    (pcall
      (fn []
        ((. Main :install-app-shell!))
        ((. Main :init))
        (assert (activity-unit "drawing")
                "Expected drawing canvas activity unit after app init")
        (app.set-active-activity "drawing")
        (assert (= app.active-activity-id "drawing")
                "Expected drawing activity active before unloading its unit")
        (local drawing-activity-unit (activity-unit "drawing"))
        (local runtime app.active-world-runtime)
        (drawing-activity-unit:unload)
        (assert (= app.active-activity-id nil)
                "Expected unloading active drawing activity to clear the active activity")
        (assert (= (Activities.active-activity-id) nil)
                "Expected Activities registry to clear the active activity on unload")
        (assert (= runtime.requested-activity-id nil)
                "Expected unloading active drawing activity to clear requested activity persistence")
        (assert (not (= app.activity-drawing-enabled? true))
                "Expected drawing-only hooks to clear after unloading drawing activity")
        true)))
  (local (cleanup-ok cleanup-result)
    (pcall cleanup-main-if-engine!))
  (set app.renderers original-renderers)
  (set AppBootstrap.init-renderers original-init-renderers)
  (finish-protected-result ok result cleanup-ok cleanup-result))

(fn hot-reload-routes-drawing-activity-actions-file-changes-to-drawing-activity-unit []
  (with-temp-dir
    (fn [_dir]
      (local Main (require-main!))
      (local original-init-renderers AppBootstrap.init-renderers)
      (local original-renderers app.renderers)
      (local watch-root (fs.join-path runtime.assets-path "lua"))
      (set AppBootstrap.init-renderers
           (fn [opts]
             (set app.renderers (make-renderer-stub))
              (apply-renderer-viewport! opts)
             app.renderers))
      (var controller nil)
      (local (ok result)
        (pcall
          (fn []
            ((. Main :install-app-shell!))
            ((. Main :init))
            (assert (activity-unit "drawing")
                    "Expected drawing canvas activity unit after app init")
            (app.set-active-activity "drawing")
            (local root-unit
              (Units.ModuleUnit
                {:id "app-root"
                 :owned-paths [watch-root]
                 :module-name "main"
                 :suppress-run-main? true
                 :load-export "init"
                 :unload-export "drop"
                 :snapshot-export "snapshot"
                 :restore-export "restore"}))
            (set controller
              (HotReload.HotReloadController
                {:unit root-unit
                 :units-fn (fn [_root-unit]
                              [app.canvas-unit
                               app.hud-unit
                               (activity-unit "drawing")])
                  :root-unit-id "app-root"
                  :narrow-reload-unit-ids ["drawing-activity"]
                 :watch-paths [watch-root]
                 :preserve-modules ["app-bootstrap"
                                    "hot-reload"
                                    "tests.test-hot-reload-integration"
                                    "units"]}))
            (assert (controller:reload-now!
                      {:changes [{:path (fs.join-path watch-root
                                                      "drawing-activity-actions.fnl")
                                  :action "modified"}]})
                    "Expected drawing activity actions file change to reload successfully")
            (local debug-state (controller:debug-state))
            (assert (= debug-state.last-target-unit-id "drawing-activity")
                    "Expected drawing activity actions file change to target drawing activity unit")
            true)))
      (local (cleanup-ok cleanup-result)
        (pcall cleanup-controller-and-main-if-engine! controller))
      (set app.renderers original-renderers)
      (set AppBootstrap.init-renderers original-init-renderers)
      (finish-protected-result ok result cleanup-ok cleanup-result))))

(fn runner-timeout-metadata-precedence-and-validation []
  (local select (. (require :tests/runner) :select-test-timeout-seconds))
  (each [_ [raw budget expected] (ipairs [[false false 120] ["" false 120] [false 300 300]
                        ["3" 300 3] ["0" 300 0] ["" 300 300]])]
    (assert (= (select (if raw raw nil) (if budget budget nil)) expected)
            "case metadata must select 300; explicit env including 0 must dominate"))
  (each [_ budget (ipairs [0 -1 "300" true (/ 0 0) math.huge (- math.huge)])]
    (assert (not (pcall select nil budget)) "invalid case budget must fail")
    (assert (not (pcall select "0" budget)) "override must not hide invalid metadata"))
  (each [_ raw (ipairs ["bogus" "-1"])]
    (assert (not (pcall select raw nil)) "legacy invalid env must fail")))

(fn assert-root-cleanup-ownership! []
  (var outside-drops 0) (var root-drops 0) (var main-drops 0)
  (fn outside-drop [_self] (set outside-drops (+ outside-drops 1)))
  (fn root-drop [_self] (set root-drops (+ root-drops 1)) (error "partial controller drop" 0))
  (fn main-drop [] (set main-drops (+ main-drops 1)))
  (local original {:drop outside-drop})
  (local fixture-app {:hot-reload-controller original})
  (local owned {:original-controller original :main {:drop main-drop} :init-entered? false})
  (drop-owned-root-controller! fixture-app owned) (drop-owned-root-main! owned nil)
  (assert (and (= outside-drops 0) (= main-drops 0) (= fixture-app.hot-reload-controller original))
          "failure before init must not consume outside controller or drop uninitialized Main")
  (set fixture-app.hot-reload-controller {:drop root-drop}) (set owned.init-entered? true)
  (fn cleanup []
    (run-cleanup-stages! [["controller" (fn [] (drop-owned-root-controller! fixture-app owned))]
                         ["Main" (fn [] (drop-owned-root-main! owned nil))]]))
  (local slot {:cleanup cleanup})
  (assert (not (pcall drain-cleanup-slot! slot))) (drain-cleanup-slot! slot)
  (assert (and (= root-drops 1) (= main-drops 1) (= outside-drops 0) (= fixture-app.hot-reload-controller nil))
          "consume slot/controller before throwing drop; still attempt Main once"))

(fn runner-case-teardown-restores-hook-and-preserves-errors []
  (assert-root-cleanup-ownership!)
  (local runner (require :tests/runner))
  (var calls 0)
  (fn cleanup [] (set calls (+ calls 1)))
  (fn body-error [] (error "body-primary" 0))
  (local (case-ok case-error)
    (runner.run-case {:name "declared cleanup RED" :fn body-error :teardown cleanup} 0 nil))
  (assert (= calls 1) "existing executor must call declared teardown after a failing body")
  (assert (and (not case-ok) (= case-error "body-primary")))
  (local (saved-hook saved-mask saved-count) (debug.gethook))
  (fn parent-hook [] nil)
  (fn success [] :body-result)
  (fn cleanup-error [] (error "cleanup-secondary" 0))
  (fn bounded-loop [] (var total 0) (for [i 1 100000] (set total (+ total i))) total)
  (var tick 0)
  (fn clock [] (set tick (+ tick 1000)) tick)
  (fn observe []
    (local (hook mask count) (debug.gethook))
    (assert (and (= hook parent-hook) (= mask "cr") (= count 37)) "restore exact parent hook before teardown")
    (cleanup))
  (fn check-cases []
    (debug.sethook parent-hook "cr" 37)
    (each [_ body (ipairs [success body-error bounded-loop])]
      (local before calls)
      (local (ok result) (runner.run-case {:name "hook" :fn body :teardown observe} 1 nil clock))
      (assert (= calls (+ before 1)) "teardown must run exactly once")
      (assert (= ok (= body success)) "success/failure semantics must remain unchanged")
      (when (= body success) (assert (= result :body-result)))
      (when (= body body-error) (assert (= result "body-primary")))
      (when (= body bounded-loop) (assert (string.find result "test timed out after 1s" 1 true))))
    (each [_ body (ipairs [success body-error])]
      (local (ok primary secondary) (runner.run-case {:name "errors" :fn body :teardown cleanup-error} 0 nil))
      (assert (not ok))
      (assert (= primary (if (= body success) "cleanup-secondary" "body-primary")))
      (assert (= (. secondary 1) "cleanup-secondary")))
    (assert (runner.run-case {:name "no cleanup" :fn success} 0 nil))
    (assert (not (pcall runner.run-case {:name "invalid" :fn success :teardown true} 0 nil)))
    (local restored {})
    (local stages [["partial drop" cleanup-error]])
    (each [_ key (ipairs [:renderers :config :controller :worlds-dir :temp])]
      (table.insert stages (field-restoration restored key))
      (set (. restored key) :mutated))
    (assert (not (pcall run-cleanup-stages! stages)))
    (assert (= (next restored) nil) "all independent restorations must run after drop fails"))
  (local (ok err) (pcall check-cases))
  (if saved-hook (debug.sethook saved-hook saved-mask saved-count) (debug.sethook nil "" 0))
  (assert ok err))

(fn runner-saved-engine-scope-attempts-shutdown-once []
  (local runner (require :tests/runner))
  (local primary {})
  (each [_ mode (ipairs [:success :body-error :module-error :drop-error :shutdown-error :both-errors :already-attempted :unstarted])]
    (local events [])
    (var attempted (= mode :already-attempted))
    (var shutdowns 0)
    (fn shutdown [_self]
      (set shutdowns (+ shutdowns 1))
      (set attempted true)
      (table.insert events :engine)
      (when (or (= mode :shutdown-error) (= mode :both-errors)) (error "shutdown-secondary" 0)))
    (fn is-started [_self] (not (= mode :unstarted)))
    (fn is-shutdown [_self] attempted)
    (local engine {:shutdown shutdown :is-started is-started :is-shutdown is-shutdown})
    (local fake-app {:engine engine})
    (fn app-drop [] (table.insert events :drop) (error primary 0))
    (fn body []
      (table.insert events :body)
      (set fake-app.engine {:shutdown (fn [_self] (error "must not use mutable app engine"))})
      (when (= mode :module-error) (set fake-app.engine nil))
      (when (= mode :drop-error)
        (local (ok err) (runner.run-case {:name "owned app drop" :fn (fn [] true) :teardown app-drop} 0 nil))
        (assert (not ok)) (error err 0))
      (when (or (= mode :body-error) (= mode :module-error) (= mode :both-errors)) (error primary 0))
      :suite-result)
    (local (ok result) (pcall runner.with-owned-engine engine body nil))
    (assert (= shutdowns (if (or (= mode :already-attempted) (= mode :unstarted)) 0 1))
            "saved owned engine must get one attempt on success and failure, never retry")
    (assert (= (. events (# events)) (if (= shutdowns 1) :engine :body)))
    (if (or (= mode :success) (= mode :already-attempted) (= mode :unstarted))
        (assert (and ok (= result :suite-result)))
        (do (assert (not ok))
            (assert (= result (if (= mode :shutdown-error) "shutdown-secondary" primary)))))
    (when (= mode :drop-error) (assert (= (# events) 3) "fixture drop failure must not cause generic app drop retry"))))

(table.insert tests {:name "test runner timeout metadata precedence and validation" :fn runner-timeout-metadata-precedence-and-validation})
(table.insert tests {:name "test runner case teardown restores deadline hook and preserves errors" :fn runner-case-teardown-restores-hook-and-preserves-errors})
(table.insert tests {:name "test runner saved engine scope attempts shutdown once" :fn runner-saved-engine-scope-attempts-shutdown-once})
(table.insert tests {:name "full app root reload roundtrips active world"
                     :timeout-seconds 300 :teardown teardown-root-fixture
                     :fn full-app-root-reload-roundtrips-active-world})
(table.insert tests {:name "drop app cleans hot reload controller and callback"
                     :fn drop-app-cleans-hot-reload-controller-and-callback})
(table.insert tests {:name "app init refreshes agent preset context after drop"
                     :fn app-init-refreshes-agent-preset-context-after-drop})
(table.insert tests {:name "HUD unit reload roundtrips panel state"
                     :fn hud-unit-reload-roundtrips-panel-state})
(table.insert tests {:name "experimental opt-in hot reload routes hud file changes to hud unit"
                     :fn hot-reload-routes-hud-file-changes-to-hud-unit})
(table.insert tests {:name "canvas unit reload roundtrips surface state"
                     :fn canvas-unit-reload-roundtrips-surface-state})
(table.insert tests {:name "experimental opt-in hot reload routes canvas file changes to canvas unit"
                     :fn hot-reload-routes-canvas-file-changes-to-canvas-unit})
(table.insert tests {:name "hot reload routes workspace shell state file changes to app root"
                      :fn hot-reload-routes-workspace-shell-state-file-changes-to-app-root})
(table.insert tests {:name "experimental opt-in hot reload routes shared triangle-line to canvas unit"
                     :fn hot-reload-routes-shared-triangle-line-to-canvas-unit})
(table.insert tests {:name "experimental opt-in hot reload routes drawing render file changes to drawing activity unit"
                     :fn hot-reload-routes-drawing-render-file-changes-to-drawing-activity-unit})
(table.insert tests {:name "experimental opt-in hot reload routes graph view file changes to graph activity unit"
                     :fn hot-reload-routes-graph-view-file-changes-to-graph-activity-unit})
(table.insert tests {:name "graph activity registers active activity snapshot hooks"
                     :fn graph-activity-registers-active-activity-snapshot-hooks})
(table.insert tests {:name "experimental opt-in hot reload routes board file changes to board activity unit"
                     :fn hot-reload-routes-board-file-changes-to-board-activity-unit})
(table.insert tests {:name "unloading active drawing activity updates shell state"
                     :fn unloading-active-drawing-activity-updates-shell-state})
(table.insert tests {:name "experimental opt-in hot reload routes drawing activity actions file changes to drawing activity unit"
                     :fn hot-reload-routes-drawing-activity-actions-file-changes-to-drawing-activity-unit})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "hot-reload-integration"
                       :tests tests})))

(fn probe-missing-module []
  ((. (require :tests/runner) :run-modules)
    {:modules ["tests.__intentional_missing_runner_module__"]}))

{:name "hot-reload-integration"
 :tests tests
 :probe-missing-module probe-missing-module
 :main main}
