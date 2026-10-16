(local AppBootstrap (require :app-bootstrap))
(local fennel (require :fennel))
(local fs (require :fs))
(local tempfile (require :tempfile))
(local HotReload (require :hot-reload))
(local RootSupport (require :tests/hot-reload-root-support))
(local LauncherLaunchable (require :launchables/launcher))
(local runtime (require :runtime))
(local Activities (require :activities))
(local Units (require :units))

(local tests [])

(fn start-test-control! [endpoint]
  (local LiveDev (require :live-dev-runtime))
  (LiveDev.start! nil {:args [] :endpoint endpoint :reload-config app.hot-reload-config}))

(fn stop-test-control! []
  ((. (require :live-dev-runtime) :stop!)))

(fn dispatch-control! [] ((. (require :callbacks) :dispatch)))
(fn check-async-result! [id]
  (_G.remote_control.resolve id "after-root-reload")
  (assert (= (. (_G.remote_control.poll id) :value) "after-root-reload")))

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
  (local (drop-ok drop-result) (pcall drop-main-and-restore-test-fixture!))
  (local (stop-ok stop-result) (pcall stop-test-control!))
  (finish-protected-result drop-ok drop-result stop-ok stop-result))

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

(fn activity-unit [mode-id]
  (and app.activity-units
       (. app.activity-units mode-id)))

;; Slow full-app / hot-reload integration tests moved from tests.test-units.

(fn test-hot-reload-config [watch-root narrow-unit-ids]
  {:enabled true
   :watch-paths [watch-root]
   :narrow-reload-unit-ids narrow-unit-ids
   :preserve-modules ["app-bootstrap" "hot-reload" "tests.test-hot-reload-integration" "units"]})

(fn current-test-app [] app)
(local root-support
  (RootSupport.create
    {:get-app current-test-app :require-main! require-main!
     :start-test-control! start-test-control! :stop-test-control! stop-test-control!
     :dispatch-control! dispatch-control! :check-async-result! check-async-result!
     :test-hot-reload-config test-hot-reload-config :runner (require :tests/runner)}))

(fn check-test-control! [control controller]
  (local LiveDev (require :live-dev-runtime))
  (assert (= app.hot-reload-controller controller)
          "Root drop must preserve borrowed process control")
  (assert (= (LiveDev.current) control)))

(fn cleanup-test-control! [Main]
  (local (ok result) (pcall cleanup-main-var-if-engine! Main))
  (local (stop-ok stop-result) (pcall stop-test-control!))
  (finish-protected-result ok result stop-ok stop-result))

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
            (local control (start-test-control!))
            (local controller app.hot-reload-controller)
            ((. Main :init))
            (assert app.hot-reload-controller
                    "Expected app.hot-reload-controller after init")
            (assert (= app.hot-reload-callback-id nil)
                    "Root init must not create process-owned callbacks")
            ((. Main :drop))
            (check-test-control! control controller)
            (stop-test-control!)
            true)))
      (local (cleanup-ok cleanup-result)
        (pcall cleanup-test-control! Main))
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
            (start-test-control!)
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

(table.insert tests {:name "test runner timeout metadata precedence and validation" :fn root-support.runner-timeout-metadata-precedence-and-validation})
(table.insert tests {:name "test runner case teardown restores deadline hook and preserves errors" :fn root-support.runner-case-teardown-restores-hook-and-preserves-errors})
(table.insert tests {:name "test runner saved engine scope attempts shutdown once" :fn root-support.runner-saved-engine-scope-attempts-shutdown-once})
(fn normal-startup-first-reload []
  (local AppConfig (require :app-config))
  (local LiveDev (require :live-dev-runtime))
  (local ErrorReporting (require :error-reporting))
  (local before-reporting-init ErrorReporting.init)
  (local before-renderers app.renderers)
  (local before-main package.loaded.main)
  (local engine app.engine)
  (local updated engine.events.updated)
  (local before {:run engine.run :shutdown engine.shutdown :connect updated.connect
                 :disconnect updated.disconnect :run-main AppConfig.run-main
                 :config app.hot-reload-config :renderers AppBootstrap.init-renderers
                 :suppressed app.__suppress-main-run?})
  (local state {:connections 0 :active 0 :snapshots 0 :unloads 0 :inside-run false :handlers {} :reporting-inits 0})
  (fn connect [self handler]
    (when (= handler app.update)
      (set state.connections (+ state.connections 1))
      (set state.active (+ state.active 1))
      (tset state.handlers handler true))
    (before.connect self handler))
  (fn disconnect [self handler allow-missing?]
    (when (. state.handlers handler)
      (set state.active (- state.active 1))
      (tset state.handlers handler nil))
    (before.disconnect self handler allow-missing?))
  (fn renderers [opts]
    (local previous-renderer-factory package.loaded.renderers)
    (set package.loaded.renderers make-renderer-stub)
    (local (ok result) (pcall before.renderers opts))
    (set package.loaded.renderers previous-renderer-factory)
    (assert ok (tostring result))
    result)
  (fn shutdown [_self] (set state.shutdown true))
  (fn init-reporting [_opts]
    (set state.reporting-inits (+ state.reporting-inits 1))
    true)
  (fn run [_self]
    (set state.inside-run true)
    (local root (assert (. package.loaded :main) "normal startup must publish root exports before run"))
    (each [_ key (ipairs [:init :drop :snapshot :restore])]
      (assert (= (type (. root key)) :function) (.. "current root export missing: " key)))
    (local world app.world-manager)
    (local handler app.update-handler)
    (local old-snapshot root.snapshot)
    (local old-drop root.drop)
    (fn snapshot []
      (assert state.inside-run)
      (assert (= app.world-manager world) "snapshot must inspect the existing root")
      (assert (= app.update-handler handler) "snapshot must not reevaluate main")
      (set state.snapshots (+ state.snapshots 1))
      (old-snapshot))
    (fn unload []
      (assert (= app.world-manager world) "unload must drop the existing root")
      (set state.unloads (+ state.unloads 1))
      (old-drop))
    (set root.snapshot snapshot)
    (set root.drop unload)
    (local control (assert (LiveDev.current)))
    (control:request 1 "manual") (dispatch-control!)
    (control:request 2 "reload") (dispatch-control!)
    (local op (control:operation 2))
    (assert (= op.status "succeeded") (tostring op.error))
    (assert (= state.snapshots 1))
    (assert (= state.unloads 1))
    (assert (= state.connections 2) "root must initialize exactly once per generation")
    (assert (= state.active 1) "first reload must not leave duplicate root subscriptions")
    (assert (= (. (control:status) :generation) 2))
    (set state.current (. package.loaded :main))
    (assert (not= state.current root))
    (set state.inside-run false))
  (fn body []
    (set ErrorReporting.init init-reporting)
    (set engine.run run) (set engine.shutdown shutdown)
    (set updated.connect connect) (set updated.disconnect disconnect)
    (set AppBootstrap.init-renderers renderers)
    (set app.hot-reload-config {:enabled true :generic? true
                               :preserve-modules ["app-bootstrap" "tests.test-hot-reload-integration"]})
    (set AppConfig.run-main true) (set app.__suppress-main-run? nil)
    (local returned (require-main!))
    (assert (= state.reporting-inits 1) "normal startup must call only the isolated reporting initializer")
    (assert (= returned state.current) "initial require must return the latest root exports")
    (assert (= state.active 0))
    (assert state.shutdown)
    (assert (= (LiveDev.current) nil)))
  (local (ok err) (pcall body))
  (set ErrorReporting.init before-reporting-init)
  (set engine.run before.run) (set engine.shutdown before.shutdown)
  (set updated.connect before.connect) (set updated.disconnect before.disconnect)
  (set AppConfig.run-main before.run-main) (set app.__suppress-main-run? before.suppressed)
  (set AppBootstrap.init-renderers before.renderers) (set app.hot-reload-config before.config)
  (set app.renderers before-renderers)
  (set package.loaded.main before-main)
  (local (stop-ok stop-err) (pcall LiveDev.stop!))
  (restore-test-runner-app-services!)
  (assert stop-ok (tostring stop-err))
  (assert ok (tostring err)))

(fn full-app-root-reload-roundtrips-active-world [] (root-support.with-root-reload-fixture "manual"))
(fn default-root-main-path-roundtrip [] (root-support.with-root-reload-fixture ["main.fnl"]))
(fn repeated-default-root-hud-path-roundtrips [] (root-support.with-root-reload-fixture ["hud.fnl" "hud.fnl"]))

(table.insert tests {:name "default root main path reload roundtrips active world"
                     :timeout-seconds 300 :teardown root-support.teardown-root-fixture
                     :fn default-root-main-path-roundtrip})
(table.insert tests {:name "repeated default root HUD path reloads retain root ownership and active world"
                     :timeout-seconds 300 :teardown root-support.teardown-root-fixture
                     :fn repeated-default-root-hud-path-roundtrips})
(table.insert tests {:name "full app root reload roundtrips active world"
                     :timeout-seconds 300 :teardown root-support.teardown-root-fixture
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
(table.insert tests {:name "normal startup first reload snapshots the still-running existing root"
                     :fn normal-startup-first-reload})

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
