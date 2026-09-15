(global app (or app {}))

(local trace-require (os.getenv "SPACE_TRACE_REQUIRE"))

(fn install-trace-require! []
  (local current-wrapper (rawget _G "__space_trace_require_wrapper"))
  (when (and current-wrapper
             (= require current-wrapper))
    (set _G.require (or (rawget _G "__space_trace_require_original")
                        require)))
  (when trace-require
    (local original-require (or (rawget _G "__space_trace_require_original")
                                require))
    (local wrapper
      (fn [name]
        (io.stderr:write (string.format "[require] %s\n" name))
        (io.stderr:flush)
        (original-require name)))
    (set _G.__space_trace_require_original original-require)
    (set _G.__space_trace_require_wrapper wrapper)
    (set _G.require wrapper))
  _G.require)

(install-trace-require!)

(local EngineModule (require :engine))
(local AppConfig (require :app-config))
(local CliArgs (require :cli-args))
(local Activities (require :activities))
(local Launcher (require :launcher))

(set app.engine-autocreated false)
(when (not app.engine)
  (set app.engine (EngineModule.Engine {}))
  (set app.engine-autocreated true))

(local glm (require :glm))
(global fennel (require :fennel))
(local callbacks (require :callbacks))
(local runtime (require :runtime))
(local logging (require :logging))
(local Units (require :units))
(local UnitManager (require :unit-manager))

(set app.unit-manager (or app.unit-manager (UnitManager {})))
(set app.launcher (or app.launcher (Launcher {})))
(app.launcher:clear-runtime)

(global pp (fn [x] (logging.debug (fennel.view x))))

(local IoUtils (require :io-utils))
(global read-file IoUtils.read-file)

(global one (fn [val] (assert (= (length val) 1) val) (. val 1)))

(local debug-log-root-reload?
  (and app.__hot-reload-ctx
       app.__hot-reload-ctx.target-unit
       (= app.__hot-reload-ctx.target-unit.id "app-root")))
(local DebugLog (require :debug-log))
(when (and (not debug-log-root-reload?)
           (not (rawget _G "__space_debug_log_session_started")))
  (DebugLog.reset-log!)
  (set _G.__space_debug_log_session_started true))
(local TerrainIssueLog (require :terrain-issue-log))
(TerrainIssueLog.start-session! "space startup")
(local fs (require :fs))
(local json (require :json))
(local appdirs (require :appdirs))
(local log-path (logging.get-output-path))
(logging.init {:path log-path})
(logging.set-level "shader" "warn")
(logging.set-level "window" "warn")
(local audio (require :audio))
(local _input-state-binding (require :input-state))
(local Signal (require :signal))
(local Settings (require :settings))
(local RuntimePerformance (require :runtime-performance))
(local VolumeControl (require :volume-control))
(local MenuManager (require :menu-manager))
(local PanelTransfer (require :panel-transfer))
(local WalletManager (require :wallet-manager))
(local AgentPresetRegistry (require :llm/presets/registry))
(local AgentPresetManager (require :llm/presets/init))
(local AgentToolAdapterRegistry (require :llm/presets/tool-adapters))
(local AgentBuiltinDrawing (require :llm/presets/builtins/drawing))
(local AgentBuiltinGraph (require :llm/presets/builtins/graph))
(local AgentBuiltinScene (require :llm/presets/builtins/scene))
(local AgentBuiltinGeneral (require :llm/presets/builtins/general))
(local AgentBuiltinUnits (require :llm/presets/builtins/units))
(local AgentBuiltinRepo (require :llm/presets/builtins/repo))
(local AgentRegistry (require :llm/agent/registry))
(local WorkflowAgentRunner (require :llm/agent/workflow-runner))
(local AgentToolSurface (require :llm/agent/tool-surface))
(local AgentApprovals (require :llm/agent/approvals))
(local AgentMcpSync (require :llm/agent/mcp-sync))
(local AgentOpencodeMcpBridge (require :llm/agent/opencode-mcp-bridge))
(local SpaceAgent (require :llm/agent/builtins/space-agent))
(local PromptUtils (require :llm/agent/prompt-utils))
(local OpencodeSdk (require :llm/providers/opencode))
(local HudExtendedSidebar (require :hud-extended-sidebar))
(local HudExtendedSidebarView (require :hud-extended-sidebar-view))
(local ActivityTopToolbarView (require :activity-top-toolbar-view))
(local fennel-cache (require :fennel-cache))
(local bytecode-enabled
  (do
    (local flag (os.getenv "SPACE_FENNEL_BYTECODE"))
    (if flag
        (not (or (= flag "0")
                 (= (string.lower flag) "false")
                 (= (string.lower flag) "off")))
        true)))


(fn read-file-raw [path]
  (local file (io.open path "rb"))
  (if file
      (do
        (local content (file:read "*all"))
        (file:close)
        content)
      (error (.. "Could not open file: " path))))

(fn write-cache-file [path content]
  (when (and path content)
    (local file (io.open path "wb"))
    (when file
      (file:write content)
      (file:close))))

(fn loadfile-with-env [path mode]
  (local legacy? (or (= _VERSION "Lua 5.1") (string.find _VERSION "LuaJIT")))
  (local setfenv-fn (rawget _G "setfenv"))
  (if legacy?
      (do
        (local (ok result) (pcall loadfile path))
        (if ok
            (do
              (when setfenv-fn
                (setfenv-fn result _G))
              result)
            (do
              (logging.warn (string.format "[space] fennel cache load failed: %s" result))
              nil)))
      (do
        (local (ok result) (pcall loadfile path mode _G))
        (if ok
            result
            (do
              (logging.warn (string.format "[space] fennel cache load failed: %s" result))
              nil)))))

(fn cache-path-source [module-path module-name]
  (fennel-cache.cache-path-source module-path module-name))

(fn cache-path-bytecode [module-path module-name]
  (fennel-cache.cache-path-bytecode module-path module-name))

(fn load-from-cache [cache-file mode]
  (when cache-file
    (local cache-stat (fs.stat cache-file))
    (when (and cache-stat cache-stat.exists cache-stat.is-file)
      (loadfile-with-env cache-file mode))))

(fn write-bytecode-cache [cache-file loader]
  (when (and bytecode-enabled cache-file loader)
    (local (ok dumped-or-error) (pcall string.dump loader))
    (if ok
        (write-cache-file cache-file dumped-or-error)
        (logging.warn (string.format "[space] fennel bytecode disabled: %s" dumped-or-error)))))

(fn compile-fennel-module [module-name module-path source-cache bytecode-cache]
  (local source (read-file-raw module-path))
  (local compile (. fennel :compile-string))
  (local load-code (. fennel :load-code))
  (local lua-source (compile source {:filename module-path
                                     :module-name module-name
                                     :correlate true}))
  (write-cache-file source-cache lua-source)
  (local loader (load-code lua-source _G (.. "@" module-path)))
  (write-bytecode-cache bytecode-cache loader)
  (loader))

(fn clear-fennel-module-cache! [module-name module-path]
  (fennel-cache.clear-fennel-module-cache! module-name module-path))

(fn load-fennel-module [module-name module-path]
  (local source-cache (cache-path-source module-path module-name))
  (local bytecode-cache (cache-path-bytecode module-path module-name))
  (if bytecode-enabled
      (do
        (local loader (load-from-cache bytecode-cache "b"))
        (if loader
            (loader)
            (do
              (local source-loader (load-from-cache source-cache "t"))
              (if source-loader
                  (source-loader)
                  (compile-fennel-module module-name module-path source-cache bytecode-cache)))))
      (do
        (local source-loader (load-from-cache source-cache "t"))
        (if source-loader
            (source-loader)
            (compile-fennel-module module-name module-path source-cache bytecode-cache)))))

(fn make-fennel-loader [module-name module-path]
  (fn []
    (load-fennel-module module-name module-path)))

(fn fennel-cache-searcher [module-name]
  (local module-path ((. fennel :search-module) module-name))
  (if module-path
      (make-fennel-loader module-name module-path)
      nil))

(fn install-fennel-cache-searcher! []
  (local previous package.__space_fennel_cache_searcher)
  (when previous
    (var index nil)
    (each [i searcher (ipairs package.searchers) &until index]
      (when (= searcher previous)
        (set index i)))
    (when index
      (table.remove package.searchers index)))
  (set package.__space_fennel_cache_searcher fennel-cache-searcher)
  (table.insert package.searchers 1 fennel-cache-searcher)
  fennel-cache-searcher)

(when (and fs appdirs)
  (local cache-root (appdirs.user-cache-dir "space"))
  (when cache-root
    (local target (fs.join-path cache-root "fennel"))
    (local (ok err)
           (pcall
             (fn []
               (when (and fs fs.create-dirs)
                 (fs.create-dirs target)))))
    (if ok
        (do
          (fennel-cache.init! target)
          (install-fennel-cache-searcher!))
        (logging.warn (string.format "[space] fennel cache disabled: %s" err)))))

(fn init-app-dirs []
(when (and app.engine appdirs)
    (local data-dir (appdirs.user-data-dir "space"))
    (assert data-dir "appdirs.user-data-dir must return a directory")
    (set app.user-data-dir data-dir)
    (local apps-dir (fs.join-path data-dir "apps"))
    (local worlds-dir (fs.join-path data-dir "worlds"))
    (local code-dir (fs.join-path data-dir "code"))
    (when (and fs fs.create-dirs)
      (fs.create-dirs apps-dir))
    (when (and fs fs.create-dirs)
      (fs.create-dirs worlds-dir))
    (when (and fs fs.create-dirs)
      (fs.create-dirs code-dir))
    (set app.worlds-dir worlds-dir)
    (set app.code-dir code-dir)
    (set app.get-app-dir
         (fn [name]
           (assert (and name (> (string.len name) 0)) "app.get-app-dir requires a name")
           (assert (not (string.find name "/" 1 true)) "app.get-app-dir name cannot include /")
           (assert (not (string.find name "\\" 1 true)) "app.get-app-dir name cannot include \\")
           (local target (fs.join-path apps-dir name))
           (when (and fs fs.create-dirs)
             (fs.create-dirs target))
           target))))

(fn disconnect-volume-settings []
  (when (and app.volume-settings-handler VolumeControl.volume-settings-changed-debounced)
    (VolumeControl.volume-settings-changed-debounced:disconnect app.volume-settings-handler true)
    (set app.volume-settings-handler nil)))

(fn connect-volume-settings []
  (when VolumeControl.volume-settings-changed-debounced
    (set app.volume-settings-handler
         (VolumeControl.volume-settings-changed-debounced:connect
           (fn [_settings]
             (when (and app.settings app.settings.set-value app.settings.save)
               (local volume (VolumeControl.get-stored-volume))
               (local muted? (VolumeControl.get-muted?))
               (when (not (= volume nil))
                 (app.settings.set-value "audio.volume" volume {:save? false}))
               (app.settings.set-value "audio.muted" muted? {:save? false})
               (app.settings.save)))))))

(fn ensure-runtime-performance-state []
  (if (not app.runtime-performance-state)
      (set app.runtime-performance-state (RuntimePerformance.create-state)))
  app.runtime-performance-state)

(fn wall-now-ms []
  (assert (and app.engine app.engine.now-ms)
          "app.engine.now-ms missing")
  (app.engine:now-ms))

(fn dev-flag-enabled? [value]
  (and value
       (not (or (= value "0")
                (= (string.lower value) "false")
                (= (string.lower value) "off")))))

(fn sync-physics-paused-state []
  (when (and app.engine app.engine.set-physics-paused)
    (app.engine.set-physics-paused
      (or (= app.runtime-performance-physics-paused true)
          (not (= app.startup-physics-pause-owner nil)))))
  true)

(fn apply-runtime-performance-settings []
  (if (and app.settings app.engine)
      (do
        (local state (ensure-runtime-performance-state))
        (local prev-control app.runtime-performance-control-mode)
        (local prev-mode app.runtime-performance-active-mode)
        (local prev-fps app.runtime-performance-fps-cap)
        (local prev-physics app.runtime-performance-physics-paused)
        (local prev-input app.runtime-performance-input-paused)
        (local prev-ui app.runtime-performance-ui-paused)
        (local prev-screensaver app.runtime-performance-screensaver-inhibited)
        (local prev-source app.runtime-performance-source)
        (local prev-override app.runtime-performance-active-override)
        (local result (RuntimePerformance.apply-settings app.settings state app.engine))
        (when result
          (set app.runtime-performance-control-mode result.control_mode)
          (set app.runtime-performance-active-mode result.effective_mode)
          (set app.runtime-performance-fps-cap result.fps_cap)
          (set app.runtime-performance-physics-paused result.pause_physics)
          (set app.runtime-performance-input-paused result.pause_input)
          (set app.runtime-performance-ui-paused result.pause_ui)
          (set app.runtime-performance-screensaver-inhibited result.screensaver_inhibited)
          (set app.runtime-performance-source result.source)
          (set app.runtime-performance-active-override result.active_override)
          (sync-physics-paused-state)
          (when (or (not (= prev-control result.control_mode))
                    (not (= prev-mode result.effective_mode))
                    (not (= prev-fps result.fps_cap))
                    (not (= prev-physics result.pause_physics))
                    (not (= prev-input result.pause_input))
                    (not (= prev-ui result.pause_ui))
                    (not (= prev-screensaver result.screensaver_inhibited))
                    (not (= prev-source result.source))
                    (not (= prev-override result.active_override)))
            (logging.info
              (string.format
                "[space] runtime-performance control=%s mode=%s fps=%s physics-paused=%s input-paused=%s ui-paused=%s screensaver-inhibited=%s source=%s override=%s (prev control=%s mode=%s fps=%s physics-paused=%s input-paused=%s ui-paused=%s screensaver-inhibited=%s source=%s override=%s)"
                (tostring result.control_mode)
                (tostring result.effective_mode)
                (tostring result.fps_cap)
                (tostring result.pause_physics)
                (tostring result.pause_input)
                (tostring result.pause_ui)
                (tostring result.screensaver_inhibited)
                (tostring result.source)
                (tostring result.active_override)
                (tostring prev-control)
                (tostring prev-mode)
                (tostring prev-fps)
                (tostring prev-physics)
                (tostring prev-input)
                (tostring prev-ui)
                (tostring prev-screensaver)
                (tostring prev-source)
                (tostring prev-override))))))))

(fn app.set-startup-physics-paused [owner paused]
  (assert (and (= (type owner) :string) (> (# owner) 0))
          "set-startup-physics-paused requires non-empty string owner")
  (if paused
      (set app.startup-physics-pause-owner owner)
      (when (= app.startup-physics-pause-owner owner)
        (set app.startup-physics-pause-owner nil)))
  (sync-physics-paused-state)
  (= app.startup-physics-pause-owner owner))

(fn app.set-runtime-performance-control-mode [control-mode]
  (assert (and app.settings app.settings.set-value) "settings must be initialized")
  (local normalized (RuntimePerformance.normalize-control-mode control-mode))
  (app.settings.set-value "runtime_performance.control_mode" normalized {:save? true})
  (apply-runtime-performance-settings)
  normalized)

(fn app.set-runtime-performance-manual-mode [mode]
  (assert (and app.settings app.settings.set-value) "settings must be initialized")
  (local normalized (RuntimePerformance.normalize-mode mode))
  (app.settings.set-value "runtime_performance.manual_mode" normalized {:save? true})
  (apply-runtime-performance-settings)
  normalized)

(fn app.set-runtime-performance-screensaver-inhibit-mode [mode]
  (assert (and app.settings app.settings.set-value) "settings must be initialized")
  (local normalized (RuntimePerformance.normalize-screensaver-inhibit-mode mode))
  (app.settings.set-value "runtime_performance.screensaver.inhibit_mode" normalized {:save? true})
  (apply-runtime-performance-settings)
  normalized)

(fn app.activate-runtime-performance-lease [opts]
  (local state (ensure-runtime-performance-state))
  (local lease (RuntimePerformance.activate-lease state opts))
  (apply-runtime-performance-settings)
  lease)

(fn app.clear-runtime-performance-lease [id]
  (local state (ensure-runtime-performance-state))
  (RuntimePerformance.clear-lease state id)
  (apply-runtime-performance-settings)
  true)

(fn resolve-hot-reload-config []
  (local override app.hot-reload-config)
  (local env-watch-path (os.getenv "SPACE_HOT_RELOAD_WATCH_PATH"))
  (local enabled?
    (if (and override (not (= override.enabled nil)))
        (not (= override.enabled false))
        (dev-flag-enabled? (os.getenv "SPACE_HOT_RELOAD"))))
  (if (not enabled?)
      nil
      {:watch-paths (or (and override override.watch-paths)
                        (and env-watch-path [env-watch-path])
                        [(fs.join-path runtime.assets-path "lua")])
       :debounce-ms (or (and override override.debounce-ms) 150)
       :module-name (or (and override override.module-name) "main")
       :preserve-modules (or (and override override.preserve-modules)
                             ["hot-reload" "units"])
       :generic? (and override override.generic?)}))

(fn app-root-reload-in-progress? []
  (and app.__hot-reload-ctx
       app.__hot-reload-ctx.target-unit
       (= app.__hot-reload-ctx.target-unit.id "app-root")))

(fn ensure-hot-reload-controller []
  (local config (resolve-hot-reload-config))
  (if (not config)
      nil
      (do
        (when (not app.hot-reload-callback-id)
          (set app.hot-reload-callback-id
               (callbacks.register
                 (fn [_payload]
                   (when (and app.hot-reload-controller
                              app.hot-reload-controller.reload-now!)
                     (app.hot-reload-controller:reload-now!))))))
        (when (not app.hot-reload-controller)
          (local HotReload (require :hot-reload))
          (local controller-config
            {:watch-paths config.watch-paths
             :debounce-ms config.debounce-ms
             :module-name config.module-name
             :preserve-modules config.preserve-modules
             :generic? config.generic?
             :on-reload-requested (fn [_controller]
                                    (assert app.hot-reload-callback-id
                                            "hot reload callback id missing")
                                    (callbacks.enqueue app.hot-reload-callback-id true))
             :units-fn (fn [_root-unit]
                          (app.unit-manager:list))})
          (set app.hot-reload-controller
               (HotReload.AppRootController controller-config)))
        app.hot-reload-controller)))

(fn app.activate-runtime-performance-gameplay-lease [id]
  (assert (and (= (type id) :string) (> (# id) 0))
          "activate-runtime-performance-gameplay-lease requires non-empty string id")
  (if (not app.settings)
      nil
      (do
  (local state (ensure-runtime-performance-state))
  (local lease (RuntimePerformance.activate-gameplay-lease app.settings state id))
  (apply-runtime-performance-settings)
  lease)))

(fn app.clear-runtime-performance-gameplay-lease [id]
  (assert (and (= (type id) :string) (> (# id) 0))
          "clear-runtime-performance-gameplay-lease requires non-empty string id")
  (local state (ensure-runtime-performance-state))
  (RuntimePerformance.clear-gameplay-lease state id)
  (apply-runtime-performance-settings)
  true)

(fn mark-runtime-performance-input-activity []
  (local state (ensure-runtime-performance-state))
  (local was-idle (RuntimePerformance.note-input state (os.clock)))
  (when was-idle
    (apply-runtime-performance-settings)))

(local runtime-performance-input-signal-names
  ["pen-proximity-in"
   "pen-proximity-out"
   "pen-motion"
   "pen-down"
   "pen-up"
   "pen-button-down"
   "pen-button-up"
   "pen-axis"
   "touch-down"
   "touch-motion"
   "touch-up"
   "touch-canceled"
   "key-down"
   "key-up"
   "mouse-motion"
   "mouse-button-down"
   "mouse-button-up"
   "mouse-wheel"
   "text-input"
   "text-editing"
   "gamepad-axis-motion"
   "gamepad-button-down"
   "gamepad-button-up"])

(fn disconnect-runtime-performance-input-handlers []
  (when (and app.runtime-performance-input-handlers app.engine.events)
    (each [_ name (ipairs runtime-performance-input-signal-names)]
      (local handler (. app.runtime-performance-input-handlers name))
      (local signal (. app.engine.events name))
      (when (and signal handler)
        (signal:disconnect handler true))))
  (set app.runtime-performance-input-handlers {}))

(fn connect-runtime-performance-input-handlers []
  (set app.runtime-performance-input-handlers {})
  (if (not (and app.engine app.engine.events))
      nil
      (do
        (each [_ name (ipairs runtime-performance-input-signal-names)]
          (local signal (. app.engine.events name))
          (when signal
            (tset app.runtime-performance-input-handlers name
                 (signal:connect
                   (fn [_event]
                     (mark-runtime-performance-input-activity)))))))))

(fn init-settings []
  (when (and app.settings app.settings.drop)
    (app.settings.drop))
  (set app.settings (Settings {:app-name "space"}))
  (if app.runtime-performance-state
      (do
        (RuntimePerformance.set-focused app.runtime-performance-state true)
        (RuntimePerformance.set-minimized app.runtime-performance-state false)
        (RuntimePerformance.set-occluded app.runtime-performance-state false)
        (RuntimePerformance.set-hidden app.runtime-performance-state false)
        (RuntimePerformance.set-suspended app.runtime-performance-state false)
        (RuntimePerformance.set-screen-locked app.runtime-performance-state false)
        (RuntimePerformance.set-on-battery app.runtime-performance-state false)
        (RuntimePerformance.set-video-playback app.runtime-performance-state false))
      (ensure-runtime-performance-state))
  (when app.engine
    (when app.engine.is-on-battery
      (RuntimePerformance.set-on-battery app.runtime-performance-state (not (= (app.engine.is-on-battery) false))))
    (when app.engine.has-active-video-playback
      (RuntimePerformance.set-video-playback
        app.runtime-performance-state
        (not (= (app.engine.has-active-video-playback) false)))))
  (local changed (RuntimePerformance.ensure-settings-defaults app.settings))
  (if (and changed app.settings app.settings.save)
      (do
        (app.settings.save)))
  (RuntimePerformance.note-input app.runtime-performance-state (os.clock))
  (apply-runtime-performance-settings)
  (local stored-volume (app.settings.get-value "audio.volume" nil))
  (local stored-muted (app.settings.get-value "audio.muted" nil))
  (when (or (not (= stored-volume nil)) (not (= stored-muted nil)))
    (VolumeControl.apply-settings {:volume stored-volume :muted? stored-muted}))
  (disconnect-volume-settings)
  (connect-volume-settings))

(fn normalize-window-mode [mode]
  (if (= mode "windowed")
      "windowed"
      (= mode "fullscreen")
      "fullscreen"
      "maximized"))

(fn sanitize-window-dimension [value]
  (if (and (= (type value) :number) (> value 0))
      (math.floor value)
      nil))

(fn load-window-startup-options []
  (local settings (Settings {:app-name "space"}))
  (local mode (normalize-window-mode (settings.get-value "window.mode" "maximized")))
  (local width (sanitize-window-dimension (settings.get-value "window.width" nil)))
  (local height (sanitize-window-dimension (settings.get-value "window.height" nil)))
  (settings.drop)
  (local options {:window-mode mode})
  (when width
    (set (. options :width) width))
  (when height
    (set (. options :height) height))
  options)

(fn schedule-window-settings-save []
  (set app.window-settings-dirty true)
  (set app.window-settings-save-deadline (+ (os.clock) 0.25)))

(fn flush-window-settings-save []
  (when (and app.window-settings-dirty
             app.settings
             app.settings.save
             (>= (os.clock) app.window-settings-save-deadline))
    (app.settings.save)
    (set app.window-settings-dirty false)))

(fn persist-window-size [width height]
  (when (and app.settings app.settings.set-value)
    (local safe-width (sanitize-window-dimension width))
    (local safe-height (sanitize-window-dimension height))
    (when (and safe-width safe-height)
      (app.settings.set-value "window.width" safe-width {:save? false})
      (app.settings.set-value "window.height" safe-height {:save? false})
      (schedule-window-settings-save))))

(fn persist-window-mode [mode]
  (when (and app.settings app.settings.set-value)
    (local safe-mode (normalize-window-mode mode))
    (app.settings.set-value "window.mode" safe-mode {:save? false})
    (if (= safe-mode "windowed")
        (persist-window-size (and app.engine app.engine.width)
                             (and app.engine app.engine.height)))
    (schedule-window-settings-save)))

(fn matches-filters? [target filters]
  (or
    (= filters nil)
    (each [k v (pairs filters)]
      (when (not (= (. target k) v))
        (lua "return false")))
    true))

(local {:to-table viewport->table
        :to-glm-vec4 viewport->glm-vec4
        :input-pos->viewport-pos viewport->input-pos} (require :viewport-utils))
(local AppViewport (require :app-viewport))
(local AppProjection (require :app-projection))
(local {: FocusManager} (require :focus))
(local Tray (require :tray-manager))
(local Notify (require :notify-manager))
(local AppBootstrap (require :app-bootstrap))
(local WorldManager (require :world-manager))
(local WorldTabsWidget (require :world-tabs-widget))
(local InputState (require :input-state-router))
(local Modifiers (require :input-modifiers))

(local FrameProfiler (require :frame-profiler))

(local number-or
  (fn [value fallback]
    (if (not (= value nil)) value fallback)))

(set (. app :set-viewport) (. AppViewport :set-viewport))
(set (. app :create-default-projection) (. AppProjection :create-default-projection))

(fn current-pixel-viewport-size []
  (local pixel-width (or (and app.engine (. app.engine "pixel-width")) 0))
  (local pixel-height (or (and app.engine (. app.engine "pixel-height")) 0))
  (if (and (> pixel-width 0) (> pixel-height 0))
      {:width pixel-width :height pixel-height}
      (let [width (or (and app.engine app.engine.width) 0)
            height (or (and app.engine app.engine.height) 0)]
        {:width width :height height})))

(fn app.reset-projection []
  (if app.scene
      (app.scene:reset-projection)
      (set app.projection (app.create-default-projection)))
  (when app.scene
    (set app.projection app.scene.projection))
  (when app.canvas
    (app.canvas:reset-projection))
  (when app.hud
    (app.hud:reset-projection)))

(local PresentHelpers (require :app-presentation-helpers))
(PresentHelpers.install-presentation-helpers! app)

(fn resolve-screen-ray-target [opts]
  (local options (or opts {}))
  (local explicit-target (or options.target options.pointer-target))
  (if explicit-target
      explicit-target
      (do
        (local explicit-surface options.surface)
        (if (= explicit-surface :canvas)
            app.canvas
            (= explicit-surface :scene)
            app.scene
            (if (and (= app.active-interaction-surface :canvas)
                     app.canvas
                     (= app.canvas-visible? true))
                app.canvas
                app.scene)))))

(fn app.screen-pos-ray [pos opts]
  (fn finite-number? [value]
    (and (= (type value) :number)
         (= value value)
         (not (= value math.huge))
          (not (= value (- math.huge)))))
  (fn assert-finite-vec3 [vec label]
    (when (or (not vec)
              (not (finite-number? vec.x))
              (not (finite-number? vec.y))
              (not (finite-number? vec.z)))
      (error (.. "app.screen-pos-ray produced non-finite " label))))
  ;; Try presentation provider first
  (let [provider (app.active-presentation)]
    (if provider
        (provider:screen-pos-ray pos opts)
        ;; No provider: only delegate to explicit targets (opts.target or
        ;; opts.pointer-target).  Implicit fallback to app.scene/app.canvas
        ;; is removed — callers must pass an explicit target or ensure an
        ;; active presentation provider exists.
        (let [options (or opts {})
              explicit-target (or options.target options.pointer-target)]
          (if (and explicit-target explicit-target.screen-pos-ray)
              (let [copy {}]
                (each [k v (pairs options)]
                  (set (. copy k) v))
                (explicit-target:screen-pos-ray pos copy))
              (error "app.screen-pos-ray requires a presentation provider or explicit target with screen-pos-ray"))))))

(set app.layout-root nil)
(set app.viewport nil)
(app.set-viewport {:width 0 :height 0})
(set app.projection nil)
(set app.scene nil)
(set app.canvas nil)
(set app.hud nil)
(set app.canvas-unit nil)
(set app.hud-unit nil)
(set app.activity-units nil)
(set app.profiler nil)
(set app.movables nil)
(set app.focus nil)
(set app.scene-focus-scope nil)
(set app.canvas-focus-scope nil)
(set app.hud-focus-scope nil)
(set app.canvas-controls nil)
(set app.active-pointer-controls nil)
(set app.preferred-interaction-surface :scene)
(set app.active-interaction-surface :scene)
(set app.active-activity-id nil)
(set app.scene-interactive? true)
(set app.canvas-interactive? false)
(set app.canvas-surface-interactive? true)
(set app.canvas-visible? false)
(set app.graph-map nil)
(set app.graph-map-manager nil)
(set app.graph-view nil)
(set app.board nil)
(set app.board-view nil)
(set app.tray-manager nil)
(set app.menu-manager nil)
(set app.panel-transfer nil)
(set app.launcher nil)
(set app.notify nil)
(set app.kernels nil)
(set app.settings nil)
(set app.volume-settings-handler nil)
(set app.window-resized-handler nil)
(set app.window-pixel-size-handler nil)
(set app.window-mode-handler nil)
(set app.window-focus-handler nil)
(set app.window-minimized-handler nil)
(set app.window-occluded-handler nil)
(set app.window-hidden-handler nil)
(set app.app-suspended-handler nil)
(set app.screen-locked-handler nil)
(set app.runtime-performance-input-handlers {})
(set app.update-handler nil)
(set app.engine-tick-handler nil)
(set app.global-shortcuts-handler nil)
(set app.remote-control nil)
(set app.remote-control-endpoint nil)
(set app.hot-reload-callback-id nil)
(set app.browser-cube-surface nil)
(set app.next-frame-queue [])
(set app.next-frame-pending [])
(set app.window-settings-dirty false)
(set app.window-settings-save-deadline 0)
(set app.runtime-performance-state nil)
(set app.runtime-performance-control-mode nil)
(set app.runtime-performance-active-mode nil)
(set app.runtime-performance-fps-cap nil)
(set app.runtime-performance-physics-paused nil)
(set app.startup-physics-pause-owner nil)
(set app.runtime-performance-input-paused nil)
(set app.runtime-performance-ui-paused nil)
(set app.runtime-performance-screensaver-inhibited nil)
(set app.runtime-performance-source nil)
(set app.runtime-performance-active-override nil)
(set app.world-manager nil)
(set app.world-tabs-builder nil)
(set app.active-world-hud-contrib nil)
(set app.active-world-hud-overlay nil)
(set app.active-world-runtime nil)
(do (set app.workspace-shell-changed (Signal)) (set app.activity-dock-changed (Signal)))

(fn app.next-frame [cb]
  (assert cb "app.next-frame requires callback")
  (table.insert app.next-frame-queue cb))

(fn run-next-ui-frame []
  (local pending app.next-frame-pending)
  (set app.next-frame-pending [])
  (each [_ cb (ipairs pending)]
    (cb)))

(fn workspace-shell-state []
  {:interaction-surface app.active-interaction-surface
   :activity app.active-activity-id
   :canvas-visible? (= app.canvas-visible? true)})

(fn agent-preset-context []
  (fn repos-available?* []
    (local store-path (and app.user-data-dir
                           (fs.join-path app.user-data-dir "repositories" "registry.json")))
    (when store-path
      (when (fs.exists store-path)
        (local parsed (json.loads (fs.read-file store-path)))
        (when (= (type parsed) :table)
          (not= (next parsed) nil)))))
  {:surface (or app.active-interaction-surface :scene)
   :activity app.active-activity-id
   :canvas-visible? (= app.canvas-visible? true)
   :repos-available? (= (repos-available?*) true)})

(fn workspace-shell-state= [a b]
  (and a b
       (= a.interaction-surface b.interaction-surface)
       (= a.activity b.activity)
       (= a.canvas-visible? b.canvas-visible?)))

(fn emit-workspace-shell-changed [reason previous]
  (local current (workspace-shell-state))
  (when (and app.workspace-shell-changed
             (not app.suppress-workspace-shell-change?)
             (not (workspace-shell-state= previous current)))
    (app.workspace-shell-changed:emit {:reason reason
                                       :previous previous
                                       :current current}))
  current)

(fn collect-cli-args []
  (local args [])
  (when _G.arg
    (var i 1)
    (while (<= i (# _G.arg))
      (table.insert args (. _G.arg i))
      (set i (+ i 1))))
  args)

(fn parse-remote-control-endpoint []
  (local spec {:name "space"
               :allow-unknown? true
               :add-help? false
               :options [{:key "remote-control"
                          :long "remote-control"
                          :takes-value? true}]})
  (local result (CliArgs.parse spec (collect-cli-args)))
  (if result.ok
      (. result.values "remote-control")
      (do
        (local message (or result.error "invalid remote control args"))
        (error (.. "[space] " message "\n" result.usage)))))

(set app.remote-control-endpoint (parse-remote-control-endpoint))

(local SDLK_TAB 9)
(local KEY_W_LOWER (string.byte "w"))
(local KEY_W_UPPER (string.byte "W"))
(local KEY_1 (string.byte "1"))
(local KEY_9 (string.byte "9"))

(fn build-hud-world-tabs-widget [world-manager]
  (assert world-manager "build-hud-world-tabs-widget requires world-manager")
  (WorldTabsWidget {:world-manager world-manager
                    :tab-spacing 0}))

(fn world-tab-status-builder []
  (assert app.world-manager "world-tab-status-builder requires app.world-manager")
  (fn [ctx]
    ((build-hud-world-tabs-widget app.world-manager) ctx)))

(fn world-runtime-context []
  {:hud app.hud
   :focus-manager app.focus
   :focus-root (and app.focus (app.focus:get-root-scope))
   :icons app.icons
   :states app.states
   :movables app.movables})

(fn resolve-active-world-hud-contrib []
  (local entry (and app.world-manager (app.world-manager:active-world)))
  (local world (and entry entry.world))
  (if (and world world.get-hud-contrib)
      (or (world:get-hud-contrib) {})
      {}))

(fn clear-active-world-hud-overlay []
  (when (and app.hud app.active-world-hud-overlay)
    (app.hud:remove-overlay-child app.active-world-hud-overlay)
    (set app.active-world-hud-overlay nil)))

(fn ensure-extended-sidebar! []
  (when (not app.extended-sidebar)
    (set app.extended-sidebar (HudExtendedSidebar))
    (local TerminalWidget (require :terminal-widget))
    (app.extended-sidebar:register-entry
      {:id :terminal
       :icon :terminal
       :label "Terminal"
       :build-panel (fn [ctx]
                      ((TerminalWidget {:focusable? true}) ctx))}))
  (when (and app.agent-runner (not (app.extended-sidebar:get-entry :space-agent)))
    (local AgentPanel (require :llm/agent/ui/panel))
    (app.extended-sidebar:register-entry
      {:id :space-agent
       :icon :smart_toy
       :label "Space Agent"
       :build-panel (fn [ctx]
                      ((AgentPanel.AgentPanel
                         {:runner app.agent-runner
                          :registry app.agent-registry
                          :approvals app.agent-approvals
                          :presets app.agent-presets})
                       ctx))}))
  (when app.pending-extended-sidebar-state
    (app.extended-sidebar:restore-state app.pending-extended-sidebar-state)
    (when (or (not app.pending-extended-sidebar-state.active-id)
              (= app.extended-sidebar.active-id app.pending-extended-sidebar-state.active-id))
      (set app.pending-extended-sidebar-state nil)))
  true)

(fn apply-active-world-hud-contrib []
  (when app.hud
    (local contrib (resolve-active-world-hud-contrib))
    (set app.active-world-hud-contrib contrib)
    (set app.hud.world-hud-contrib contrib)
    (local control-panel-opts {:status-builder app.world-tabs-builder})
    (local status-panel-opts {})
    (when contrib.control_panel_body
      (set control-panel-opts.body-builder contrib.control_panel_body))
    (when contrib.status_panel_body
      (set status-panel-opts.body-builder contrib.status_panel_body))
    (local hud-opts {:control-panel-opts control-panel-opts})
    (when (or status-panel-opts.body-builder)
      (set hud-opts.status-panel-opts status-panel-opts))
    (when contrib.left_dock_builder
      (set hud-opts.left-dock-builder contrib.left_dock_builder))
    (when app.agent-runner
      (ensure-extended-sidebar!)
      (set hud-opts.right-dock-builder
           (HudExtendedSidebarView app.extended-sidebar
                                   {:top-reserve-height-provider
                                    (fn [] (or app.activity-top-toolbar-height 0))})))
    (set hud-opts.top-toolbar-builder (ActivityTopToolbarView {}))
    (app.hud:build-default hud-opts)
    (clear-active-world-hud-overlay)
    (when contrib.overlay
      (set app.active-world-hud-overlay
           (app.hud:add-overlay-child {:builder contrib.overlay})))
    (app.reset-projection)))

(set app.apply-active-world-hud-contrib apply-active-world-hud-contrib)

(fn bind-hud-runtime []
  (when app.hud
    (set app.hud.scene app.scene)
    (when app.hud.build-context
      (set app.hud.build-context.object-selector app.object-selector)
      (set app.hud.build-context.layout-root app.layout-root))
    (when (or app.scene app.active-world-entry app.world-manager)
      (apply-active-world-hud-contrib)))
  true)

(set app.bind-hud-runtime bind-hud-runtime)

(fn app.request-theme-change [theme-name]
  (assert theme-name "app.request-theme-change requires a theme name")
  ;; Theme changes rebuild scene/HUD shell state. Do not run them directly from
  ;; widget/input callbacks or route them through BucketQueue tolerance hacks.
  ;; Defer to the next UI frame boundary so input dispatch and current layout work
  ;; have fully unwound before the rebuild runs.
  (assert app.next-frame "app.request-theme-change requires app.next-frame")
  (app.next-frame
    (fn []
      (local ThemeActions (require :theme-actions))
      (ThemeActions.apply-theme theme-name)))
  theme-name)

(fn resolve-interaction-surface [surface]
  (if (= surface :canvas)
      (if app.canvas :canvas :scene)
      :scene))

(fn effective-interaction-surface [preferred-surface canvas-available?]
  (if (and (= preferred-surface :canvas)
           canvas-available?)
      :canvas
      :scene))

(fn resolve-activity [activity-id]
  (Activities.resolve activity-id))

(fn mark-active-world-hud-dirty []
  (when (and app.hud app.hud.entity app.hud.entity.layout)
    (app.hud.entity.layout:mark-measure-dirty)
    (app.hud.entity.layout:mark-layout-dirty))
  true)

(set app.mark-active-world-hud-dirty mark-active-world-hud-dirty)

(fn sync-interaction-surface-state [reason previous]
  (local preferred-surface (resolve-interaction-surface app.preferred-interaction-surface))
  (local canvas-visible? (and app.canvas (= app.canvas-visible? true)))
  (local canvas-surface-interactive? (not (= app.canvas-surface-interactive? false)))
  (local canvas-available? (and canvas-visible? canvas-surface-interactive?))
  (local surface (effective-interaction-surface preferred-surface canvas-available?))
  (set app.preferred-interaction-surface preferred-surface)
  (set app.active-interaction-surface surface)
  (set app.canvas-visible? canvas-visible?)
  (set app.canvas-surface-interactive? canvas-surface-interactive?)
  (set app.scene-interactive? (= surface :scene))
  (set app.canvas-interactive? (and canvas-visible?
                                       canvas-surface-interactive?
                                       (= surface :canvas)))
  (set app.active-pointer-controls
       (and app.presentation-input-controls
            (app.presentation-input-controls)))
  (emit-workspace-shell-changed (or reason "interaction-surface") previous)
  (mark-active-world-hud-dirty)
  surface)

(set app.sync-interaction-surface-state sync-interaction-surface-state)

(fn app.set-canvas-visible [visible?]
  (local previous (workspace-shell-state))
  (set app.canvas-visible? (and app.canvas
                                (not (= visible? false))))
  (sync-interaction-surface-state "canvas-visibility" previous))

(fn app.set-active-interaction-surface [surface opts]
  (local options (or opts {}))
  (local previous (workspace-shell-state))
  (set app.preferred-interaction-surface (resolve-interaction-surface surface))
  (when (or (= options.sync-canvas-visibility nil)
            options.sync-canvas-visibility)
    (set app.canvas-visible? (and app.canvas
                                  (= app.preferred-interaction-surface :canvas))))
  (when app.active-world-runtime
    (set app.active-world-runtime.preferred-interaction-surface
         app.preferred-interaction-surface))
  (sync-interaction-surface-state "interaction-surface" previous))

(fn app.set-active-activity [activity-id]
  (local resolved (resolve-activity activity-id))
  (Activities.activate-activity resolved)
  (mark-active-world-hud-dirty)
  resolved)

(fn app.toggle-active-interaction-surface []
  (if (not app.canvas)
      false
      (if (= app.active-interaction-surface :canvas)
          (app.set-active-interaction-surface :scene
                                              {:sync-canvas-visibility true})
          (app.set-active-interaction-surface :canvas
                                              {:sync-canvas-visibility true}))))

(fn pointer-target-surface [target]
  (if (or (= target nil)
          (= target app.scene)
          (= (and target target.interaction-surface) :scene))
      :scene
      (if (or (= target app.canvas)
              (= (and target target.interaction-surface) :canvas))
          :canvas
          (if (or (= target app.hud)
                  (= (and target target.interaction-surface) :hud))
              :hud
              nil))))

(fn app.pointer-target-enabled? [target]
  (local surface (pointer-target-surface target))
  (local canvas-target-enabled? app.activity-target-enabled?)
  (local activity-slot (and target target.activity-slot))
  (local activity-slot-enabled?
    (if activity-slot
        (and app.canvas
             (= app.canvas.active-activity-slot activity-slot)
             (= activity-slot.interactive? true))
        true))
  (local slot (and target target.activity-slot (= (type target.activity-slot) :table) target.activity-slot))
  (local scene-slot-enabled?
    (or (not slot)
        (and (= target.interaction-surface :scene)
             app.scene
             (= app.scene.active-activity-slot slot)
             (= slot.interactive? true))))
  (local canvas-enabled?
    (and (= app.canvas-interactive? true)
         activity-slot-enabled?
         (if canvas-target-enabled?
             (canvas-target-enabled? target)
             (= (and target target.canvas-target-kind) nil))))
  (if (= surface :scene)
      (and (= app.scene-interactive? true)
           scene-slot-enabled?)
      (if (= surface :canvas)
          canvas-enabled?
          true)))

(fn bind-active-world-runtime [entry runtime]
  (local previous-runtime app.active-world-runtime)
  (local previous-shell (workspace-shell-state))
  (when (and previous-runtime
               (not (= previous-runtime runtime)))
    (local previous-requested-known? previous-runtime.requested-activity-known?)
    (local previous-requested-id
      (if previous-requested-known?
          previous-runtime.requested-activity-id
          previous-runtime.active-activity-id))
    (Activities.with-workspace-shell-change-suppressed
      (fn []
        (Activities.deactivate-active-activity)))
    (set previous-runtime.requested-activity-id previous-requested-id)
    (set previous-runtime.requested-activity-known?
         (or previous-requested-known?
             (not (= previous-requested-id nil)))))
  (set app.active-world-entry entry)
  (set app.active-world-runtime runtime)
  (set app.scene-focus-scope (and runtime runtime.scene-scope))
  (set app.canvas-focus-scope (and runtime runtime.canvas-scope))
  (set app.scene (and runtime runtime.scene))
  (set app.canvas (and runtime runtime.canvas))
  (set app.canvas-controls (and runtime runtime.canvas-controls))
  (set app.object-selector (and runtime runtime.object-selector))
  (set app.terrain-rect-pick-session nil)
  (set app.terrain-rect-pick-previous-state nil)
  (set app.terrain-paint-session nil)
  (set app.terrain-paint-previous-state nil)
  (set app.graph (and runtime runtime.graph))
  (set app.graph-map (or (and runtime runtime.graph-map-manager (runtime.graph-map-manager:get-active-map))
                         (and runtime runtime.graph-map)))
  (set app.graph-map-manager (and runtime runtime.graph-map-manager))
  (set app.graph-view nil)
  (set app.board nil)
  (set app.board-view nil)
  (set app.drawing-controller (and runtime runtime.drawing-controller))
  (set app.drawing-render nil)
  (set app.layout-root (and app.scene app.scene.layout-root))
  (bind-hud-runtime)
  (when (and app.canvas app.canvas.build-context)
    (set app.canvas.build-context.object-selector app.object-selector))
  (when (and app.scene app.scene.build-context)
    (set app.scene.build-context.object-selector app.object-selector)
    (set app.scene.build-context.layout-root app.layout-root))
  (when (and runtime runtime.restore-workspace-shell-state)
    (runtime:restore-workspace-shell-state app.canvas))
  (local requested-activity-id
    (if (and runtime runtime.requested-activity-known?)
        runtime.requested-activity-id
        (and runtime runtime.active-activity-id)))
  (var activity-emitted? false)
  (if (and app.canvas
           (Activities.activity-registered? requested-activity-id))
      (do
        (when (= (Activities.active-activity-id) requested-activity-id)
          (Activities.with-workspace-shell-change-suppressed
            (fn []
              (Activities.deactivate-active-activity))))
        (app.set-active-activity requested-activity-id)
        (set activity-emitted? true))
      (do
        (Activities.with-workspace-shell-change-suppressed
          (fn []
            (Activities.activate-activity nil)))
        (set app.active-activity-id nil)
        (when runtime
          (set runtime.requested-activity-id requested-activity-id)
          (set runtime.requested-activity-known? true)
          (set runtime.active-activity-id nil))))
  (when (and runtime runtime.restore-surface-state)
    (runtime:restore-surface-state app.canvas app.hud))
  (local shell-before-interaction-sync (workspace-shell-state))
  (when (and (not activity-emitted?)
             (not (workspace-shell-state= previous-shell shell-before-interaction-sync)))
    (emit-workspace-shell-changed "bind-runtime" previous-shell))
  (app.set-active-interaction-surface (or (and runtime runtime.preferred-interaction-surface)
                                          app.preferred-interaction-surface)
                                      {:sync-canvas-visibility true}))

(fn ensure-hud-unit []
  (when (not app.hud-unit)
    (local HudUnitModule (require :hud-unit))
    (set app.hud-unit
         (Units.ModuleUnit {:id "hud"
                            :parent-id "app-root"
                            :source :builtin
                            :module-name "hud-unit"
                            :owned-paths ((. HudUnitModule :hud-owned-paths))
                            :load-export "load-hud!"
                            :unload-export "unload-hud!"
                            :snapshot-export "snapshot-hud!"
                            :restore-export "restore-hud!"}))
    (app.unit-manager:register app.hud-unit))
  app.hud-unit)

(fn ensure-canvas-unit []
  (when (not app.canvas-unit)
    (local CanvasUnitModule (require :canvas-unit))
    (set app.canvas-unit
         (Units.ModuleUnit {:id "canvas"
                            :parent-id "app-root"
                            :source :builtin
                            :module-name "canvas-unit"
                            :owned-paths ((. CanvasUnitModule :canvas-owned-paths))
                            :load-export "load-canvas!"
                            :unload-export "unload-canvas!"
                            :snapshot-export "snapshot-canvas!"
                            :restore-export "restore-canvas!"}))
    (app.unit-manager:register app.canvas-unit))
  app.canvas-unit)

(local built-in-activity-unit-specs
  [{:activity-id "sandbox"
    :unit-id "sandbox-activity"
    :module-name "sandbox-activity-unit"
    :owned-paths-export "sandbox-activity-owned-paths"
    :load-export "load-sandbox-activity!"
    :unload-export "unload-sandbox-activity!"
    :snapshot-export "snapshot-sandbox-activity!"
    :restore-export "restore-sandbox-activity!"}
   {:activity-id "graph"
    :unit-id "graph-activity"
    :module-name "graph-activity-unit"
    :owned-paths-export "graph-activity-owned-paths"
    :load-export "load-graph-activity!"
    :unload-export "unload-graph-activity!"
    :snapshot-export "snapshot-graph-activity!"
    :restore-export "restore-graph-activity!"}
   {:activity-id "drawing"
    :unit-id "drawing-activity"
    :module-name "drawing-activity-unit"
    :owned-paths-export "drawing-activity-owned-paths"
    :load-export "load-drawing-activity!"
    :unload-export "unload-drawing-activity!"
    :snapshot-export "snapshot-drawing-activity!"
    :restore-export "restore-drawing-activity!"}
   {:activity-id "board"
    :unit-id "board-activity"
    :module-name "board-activity-unit"
    :owned-paths-export "board-activity-owned-paths"
    :load-export "load-board-activity!"
    :unload-export "unload-board-activity!"
    :snapshot-export "snapshot-board-activity!"
    :restore-export "restore-board-activity!"}])

(fn ensure-activity-units []
  (set app.activity-units (or app.activity-units {}))
  app.activity-units)

(fn ensure-built-in-activity-unit [unit-spec]
  (local units (ensure-activity-units))
  (local existing (. units unit-spec.activity-id))
  (if existing
      existing
      (do
        (local ActivityUnitModule (require unit-spec.module-name))
        (local unit
          (Units.ModuleUnit {:id unit-spec.unit-id
                             :parent-id "app-root"
                             :source :builtin
                             :module-name unit-spec.module-name
                             :owned-paths ((. ActivityUnitModule unit-spec.owned-paths-export))
                             :load-export unit-spec.load-export
                             :unload-export unit-spec.unload-export
                             :snapshot-export unit-spec.snapshot-export
                             :restore-export unit-spec.restore-export}))
        (set (. units unit-spec.activity-id) unit)
        (app.unit-manager:register unit)
        unit)))

(fn load-built-in-activity-units! []
  (each [_ unit-spec (ipairs built-in-activity-unit-specs)]
    (local unit (ensure-built-in-activity-unit unit-spec))
    (unit:load))
  true)

(fn ensure-user-code-units! []
  (when (and app.code-dir fs fs.list-dir (fs.exists app.code-dir))
    (local (ok entries) (pcall fs.list-dir app.code-dir false))
    (when ok
      (local by-name {})
      (each [_ entry (ipairs entries)]
        (local module-name (string.match entry.name "^([^.]+)%.fnl$"))
        (when (and entry.is-file module-name)
          (tset by-name module-name
                {:name module-name
                 :path (fs.join-path app.code-dir entry.name)
                 :owned-paths [(fs.join-path app.code-dir entry.name)]
                 :directory? false})))
      (each [_ entry (ipairs entries)]
        (when (and entry.is-dir entry.name
                   (fs.exists (fs.join-path app.code-dir entry.name "init.fnl")))
          (let [had-flat? (not (not (. by-name entry.name)))
                dir-path (fs.join-path app.code-dir entry.name)
                init-path (fs.join-path dir-path "init.fnl")]
            (tset by-name entry.name
                  {:name entry.name
                   :path init-path
                   :owned-paths [dir-path init-path]
                   :directory? true
                   :directory-override? had-flat?}))))
      (local candidates [])
      (each [_ candidate (pairs by-name)]
        (table.insert candidates candidate))
      (table.sort candidates (fn [a b] (< a.name b.name)))
      (local default-module-paths (.. app.code-dir "/?.fnl;" app.code-dir "/?/init.fnl"))
      (local dir-first-module-paths (.. app.code-dir "/?/init.fnl;" app.code-dir "/?.fnl"))
      (each [_ candidate (ipairs candidates)]
        (local unit-module-paths
          (if candidate.directory?
              dir-first-module-paths
              default-module-paths))
        (local unit
          (Units.ModuleUnit {:id (.. "user-" candidate.name)
                             :parent-id "app-root"
                             :source :user
                             :module-name candidate.name
                             :module-paths unit-module-paths
                             :owned-paths candidate.owned-paths}))
        (app.unit-manager:register unit)
        (local (load-ok load-err) (pcall #(unit:load)))
        (when (not load-ok)
          (app.unit-manager:unregister unit.id)
          (print (.. "Failed to load user-code unit \"" candidate.name "\": " (tostring load-err)))))))
  true)

(local installable-reset-projection app.reset-projection)
(local installable-set-viewport app.set-viewport)
(local installable-create-default-projection app.create-default-projection)
(local installable-mark-active-world-hud-dirty app.mark-active-world-hud-dirty)
(local installable-sync-interaction-surface-state app.sync-interaction-surface-state)
(local installable-set-canvas-visible app.set-canvas-visible)
(local installable-set-active-interaction-surface app.set-active-interaction-surface)
(local installable-set-active-activity app.set-active-activity)
(local installable-toggle-active-interaction-surface app.toggle-active-interaction-surface)
(local installable-pointer-target-enabled? app.pointer-target-enabled?)
(local installable-bind-active-world-runtime bind-active-world-runtime)

(fn install-app-shell! []
  (do (set app.workspace-shell-changed (or app.workspace-shell-changed (Signal))) (set app.activity-dock-changed (or app.activity-dock-changed (Signal))))
  (set app.set-viewport installable-set-viewport)
  (set app.create-default-projection installable-create-default-projection)
  (set app.reset-projection installable-reset-projection)
  (set app.mark-active-world-hud-dirty installable-mark-active-world-hud-dirty)
  (set app.sync-interaction-surface-state installable-sync-interaction-surface-state)
  (set app.set-canvas-visible installable-set-canvas-visible)
  (set app.set-active-interaction-surface installable-set-active-interaction-surface)
  (set app.set-active-activity installable-set-active-activity)
  (set app.toggle-active-interaction-surface installable-toggle-active-interaction-surface)
  (set app.pointer-target-enabled? installable-pointer-target-enabled?)
  (set app.bind-active-world-runtime installable-bind-active-world-runtime)
  true)

(set app.install-app-shell! install-app-shell!)
(set app.bind-active-world-runtime bind-active-world-runtime)

(fn init-world-manager []
  (when (and app.world-manager app.world-manager.drop)
    (app.world-manager:drop))
  (assert app.worlds-dir "init-world-manager requires app.worlds-dir")
  (set app.world-manager
       (WorldManager {:root-dir app.worlds-dir
                      :asset-path-resolver (and app.engine app.engine.get-asset-path)
                      :context-fn world-runtime-context
                      :on-active-runtime bind-active-world-runtime
                      :on-empty (fn []
                                  (when (and app.engine app.engine.quit)
                                    (app.engine.quit)))
                      :suspend-delay-ms 3000}))
  (set app.world-tabs-builder (world-tab-status-builder))
  app.world-manager)

(fn world-shortcut-conflict? []
  (and InputState InputState.active-input (InputState.active-input)))

(fn handle-global-world-shortcut [payload]
  (if (or (not payload) (not app.world-manager))
      false
      (do
        (local key payload.key)
        (local ctrl? (Modifiers.ctrl-held? payload.mod))
        (local shift? (Modifiers.shift-held? payload.mod))
        (local alt? (Modifiers.alt-held? payload.mod))
        (local tab-shortcut? (and ctrl? (= key SDLK_TAB)))
        (local close-shortcut? (and ctrl? (or (= key KEY_W_LOWER) (= key KEY_W_UPPER))))
        (local alt-number-shortcut?
          (and alt? (= (type key) :number) (>= key KEY_1) (<= key KEY_9)))
        (if (or tab-shortcut? close-shortcut? alt-number-shortcut?)
            (do
              (when (world-shortcut-conflict?)
                (error "World shortcut conflict: input widget has focus"))
              (if tab-shortcut?
                  (if shift?
                      (app.world-manager:activate-previous)
                      (app.world-manager:activate-next))
                  close-shortcut?
                  (app.world-manager:close-active-world)
                  alt-number-shortcut?
                  (app.world-manager:activate-by-tab-number (+ 1 (- key KEY_1)))
                  false)
              true)
            false))))

(fn tick-workflow-runner []
  (when (and app.workflow-runner app.workflow-runner.tick)
    (app.workflow-runner:tick)))

(fn app.init []
  (local init-start-ms (wall-now-ms))
  (assert (and app.engine app.engine.events) "app.engine.events missing; load engine-events before app.init")
  (set app.startup-physics-pause-owner nil)
  (set app.next-frame-queue [])
  (set app.next-frame-pending [])
  (sync-physics-paused-state)
  (init-app-dirs)
  (init-settings)
  (app.reset-projection)
  (when (and app.window-resized-handler app.engine.events app.engine.events.window-resized)
    (app.engine.events.window-resized:disconnect app.window-resized-handler true)
    (set app.window-resized-handler nil))
  (when (and app.window-pixel-size-handler app.engine.events app.engine.events.window-pixel-size-changed)
    (app.engine.events.window-pixel-size-changed:disconnect app.window-pixel-size-handler true)
    (set app.window-pixel-size-handler nil))
  (when (and app.window-mode-handler app.engine.events app.engine.events.window-mode-changed)
    (app.engine.events.window-mode-changed:disconnect app.window-mode-handler true)
    (set app.window-mode-handler nil))
  (when (and app.window-focus-handler app.engine.events app.engine.events.window-focus-changed)
    (app.engine.events.window-focus-changed:disconnect app.window-focus-handler true)
    (set app.window-focus-handler nil))
  (when (and app.window-minimized-handler app.engine.events app.engine.events.window-minimized-changed)
    (app.engine.events.window-minimized-changed:disconnect app.window-minimized-handler true)
    (set app.window-minimized-handler nil))
  (when (and app.window-occluded-handler app.engine.events app.engine.events.window-occluded-changed)
    (app.engine.events.window-occluded-changed:disconnect app.window-occluded-handler true)
    (set app.window-occluded-handler nil))
  (when (and app.window-hidden-handler app.engine.events app.engine.events.window-hidden-changed)
    (app.engine.events.window-hidden-changed:disconnect app.window-hidden-handler true)
    (set app.window-hidden-handler nil))
  (when (and app.app-suspended-handler app.engine.events app.engine.events.app-suspended-changed)
    (app.engine.events.app-suspended-changed:disconnect app.app-suspended-handler true)
    (set app.app-suspended-handler nil))
  (when (and app.screen-locked-handler app.engine.events app.engine.events.screen-locked-changed)
    (app.engine.events.screen-locked-changed:disconnect app.screen-locked-handler true)
    (set app.screen-locked-handler nil))
  (when (and app.on-battery-handler app.engine.events app.engine.events.on-battery-changed)
    (app.engine.events.on-battery-changed:disconnect app.on-battery-handler true)
    (set app.on-battery-handler nil))
  (when (and app.video-playback-active-handler app.engine.events app.engine.events.video-playback-active-changed)
    (app.engine.events.video-playback-active-changed:disconnect app.video-playback-active-handler true)
    (set app.video-playback-active-handler nil))
  (disconnect-runtime-performance-input-handlers)
  (when (and app.engine.events app.engine.events.window-resized)
    (set app.window-resized-handler
         (app.engine.events.window-resized:connect
           (fn [e]
             (app.set-viewport (current-pixel-viewport-size))
             (app.reset-projection)
             (if (= (normalize-window-mode (and app.engine (. app.engine "window-mode"))) "windowed")
                 (persist-window-size e.width e.height))))))
  (when (and app.engine.events app.engine.events.window-pixel-size-changed)
    (set app.window-pixel-size-handler
         (app.engine.events.window-pixel-size-changed:connect
           (fn [_e]
             (app.set-viewport (current-pixel-viewport-size))
             (app.reset-projection)))))
  (when (and app.engine.events app.engine.events.window-mode-changed)
    (set app.window-mode-handler
         (app.engine.events.window-mode-changed:connect
           (fn [e]
             (when app.engine
               (set (. app.engine "window-mode") (normalize-window-mode e.mode)))
             (persist-window-mode e.mode)))))
  (when (and app.engine.events app.engine.events.window-focus-changed)
    (set app.window-focus-handler
         (app.engine.events.window-focus-changed:connect
           (fn [e]
             (local state (ensure-runtime-performance-state))
             (RuntimePerformance.set-focused state (not (= e.focused false)))
             (apply-runtime-performance-settings)))))
  (when (and app.engine.events app.engine.events.window-minimized-changed)
    (set app.window-minimized-handler
         (app.engine.events.window-minimized-changed:connect
           (fn [e]
             (local state (ensure-runtime-performance-state))
             (RuntimePerformance.set-minimized state (not (= e.minimized false)))
             (apply-runtime-performance-settings)))))
  (when (and app.engine.events app.engine.events.window-occluded-changed)
    (set app.window-occluded-handler
         (app.engine.events.window-occluded-changed:connect
           (fn [e]
             (local state (ensure-runtime-performance-state))
             (RuntimePerformance.set-occluded state (not (= e.occluded false)))
             (apply-runtime-performance-settings)))))
  (when (and app.engine.events app.engine.events.window-hidden-changed)
    (set app.window-hidden-handler
         (app.engine.events.window-hidden-changed:connect
           (fn [e]
             (local state (ensure-runtime-performance-state))
             (RuntimePerformance.set-hidden state (not (= e.hidden false)))
             (apply-runtime-performance-settings)))))
  (when (and app.engine.events app.engine.events.app-suspended-changed)
    (set app.app-suspended-handler
         (app.engine.events.app-suspended-changed:connect
           (fn [e]
             (local state (ensure-runtime-performance-state))
             (RuntimePerformance.set-suspended state (not (= e.suspended false)))
             (apply-runtime-performance-settings)))))
  (when (and app.engine.events app.engine.events.screen-locked-changed)
    (set app.screen-locked-handler
         (app.engine.events.screen-locked-changed:connect
           (fn [e]
             (local state (ensure-runtime-performance-state))
             (RuntimePerformance.set-screen-locked state (not (= e.locked false)))
             (apply-runtime-performance-settings)))))
  (when (and app.engine.events app.engine.events.on-battery-changed)
    (set app.on-battery-handler
         (app.engine.events.on-battery-changed:connect
           (fn [e]
             (local state (ensure-runtime-performance-state))
             (RuntimePerformance.set-on-battery state (not (= e.on_battery false)))
             (apply-runtime-performance-settings)))))
  (when (and app.engine.events app.engine.events.video-playback-active-changed)
    (set app.video-playback-active-handler
         (app.engine.events.video-playback-active-changed:connect
           (fn [e]
             (local state (ensure-runtime-performance-state))
             (RuntimePerformance.set-video-playback state (not (= e.active false)))
             (apply-runtime-performance-settings)))))
  (connect-runtime-performance-input-handlers)
  (when (and app.update-handler app.engine.events app.engine.events.updated)
    (app.engine.events.updated:disconnect app.update-handler true)
    (set app.update-handler nil))
  (when (and app.engine.events app.engine.events.updated)
    (set app.update-handler (app.engine.events.updated:connect app.update)))
  (when (and app.engine-tick-handler app.engine.events app.engine.events.engine-tick)
    (app.engine.events.engine-tick:disconnect app.engine-tick-handler true)
    (set app.engine-tick-handler nil))
  (when (and app.engine.events app.engine.events.engine-tick)
    (set app.engine-tick-handler
         (app.engine.events.engine-tick:connect
           (fn [_payload]
             (when (and app.hot-reload-controller app.hot-reload-controller.update)
               (when (app.hot-reload-controller:update 0)
                 (lua "return nil")))
             (when app.remote-control
               (app.remote-control:tick))
              (when (and app.kernels app.kernels.tick)
                (app.kernels:tick))
              (tick-workflow-runner)))))
  (when (and app.global-shortcuts-handler app.engine.events app.engine.events.key-down)
    (app.engine.events.key-down:disconnect app.global-shortcuts-handler true)
    (set app.global-shortcuts-handler nil))
  (when (and app.engine.events app.engine.events.key-down)
    (set app.global-shortcuts-handler
         (app.engine.events.key-down:connect handle-global-world-shortcut)))

  (when app.remote-control
    (app.remote-control:drop)
    (set app.remote-control nil))
  (when app.remote-control-endpoint
    (local RemoteControl (require :remote-control))
    (set app.remote-control (RemoteControl {:endpoint app.remote-control-endpoint})))

  (when (and app.kernels app.kernels.drop)
    (app.kernels:drop)
    (set app.kernels nil))
  (local Kernels (require :kernels))
  (set app.kernels (Kernels.get-default))
  (local CodeEntityStore (require :entities/code))
  (local WorkflowStore (require :workflows/store))
  (local WorkflowCodeExecutor (require :workflows/code-executor))
  (local WorkflowRunner (require :workflows/runner))
  (set app.code-store
       (CodeEntityStore.CodeEntityStore {:base-dir app.user-data-dir}))
  (set app.workflow-store
       (WorkflowStore.get-default {:base-dir app.user-data-dir}))
  (set app.workflow-code-executor
       (WorkflowCodeExecutor.WorkflowCodeExecutor {:code-store app.code-store
                                                   :app app}))
  (set app.workflow-runner
       (WorkflowRunner.WorkflowRunner {:store app.workflow-store
                                       :executor app.workflow-code-executor
                                       :app app}))
  (AppBootstrap.init-themes)
  (AppBootstrap.init-lights)
  (AppBootstrap.init-input-systems)
  (assert app.clickables "app.clickables missing; AppBootstrap.init-input-systems should provide it")
  (local initial-width (or (and app.engine (. app.engine "pixel-width")) (and app.engine app.engine.width) 0))
  (local initial-height (or (and app.engine (. app.engine "pixel-height")) (and app.engine app.engine.height) 0))
  (when (and (> initial-width 0) (> initial-height 0))
    (app.set-viewport {:width initial-width :height initial-height}))
  (AppBootstrap.init-renderers {:viewport app.viewport})
  (AppBootstrap.init-icons)
  (local profiler-env (os.getenv "SPACE_FENNEL_PROFILE"))
  (local profiler-enabled
    (and profiler-env
         (not (or (= profiler-env "0")
                  (= (string.lower profiler-env) "false")
                  (= (string.lower profiler-env) "off")))))
  (set app.profiler (and profiler-enabled
                           (FrameProfiler {:threshold-ms 60.0
                                           :log-interval 0
                                           :enabled true})))

  (AppBootstrap.init-states)

  (when app.focus
    (app.focus:drop))
  (set app.focus (FocusManager {:root-name "space-focus"}))
  (set app.scene-focus-scope nil)
  (set app.canvas-focus-scope nil)
  (set app.hud-focus-scope nil)
  (when app.clickables
    (when app.focus-void-callback
      (app.clickables:unregister-left-click-void-callback app.focus-void-callback)
      (set app.focus-void-callback nil))
    (set app.focus-void-callback
         (fn [_event]
             (when app.focus
               (app.focus:clear-focus))))
    (app.clickables:register-left-click-void-callback app.focus-void-callback))
  (set app.scene nil)
  (set app.canvas nil)
  (set app.active-world-runtime nil)
  (set app.canvas-controls nil)
  (set app.active-pointer-controls nil)
  (set app.preferred-interaction-surface :scene)
  (set app.active-interaction-surface :scene)
  (set app.scene-interactive? true)
  (set app.canvas-interactive? false)
  (set app.canvas-surface-interactive? true)
  (set app.canvas-visible? false)
  (set app.graph nil)
  (set app.graph-map nil)
  (set app.graph-map-manager nil)
  (set app.graph-view nil)
  (set app.board nil)
  (set app.board-view nil)
  (set app.object-selector nil)
  (set app.terrain-rect-pick-session nil)
  (set app.terrain-rect-pick-previous-state nil)
  (set app.terrain-paint-session nil)
  (set app.terrain-paint-previous-state nil)
  (set app.layout-root nil)
  (set app.hud nil)
  (set app.launcher (Launcher {}))
  (app.launcher:clear-runtime)
  (Activities.clear-activity-runtime-hooks!)
  (ensure-canvas-unit)
  (local hud-unit (ensure-hud-unit))
  (hud-unit:load)
  (load-built-in-activity-units!) (app.ensure-graph-extension-registry!)
  (init-world-manager) (app.ensure-built-in-graph-extensions!)
  (ensure-user-code-units!)
  (when app.world-manager
    (app.world-manager:activate-first))
  (app.reset-projection)
  (local browser-cube-demo-env (os.getenv "SPACE_BROWSER_CUBE_DEMO"))
  (local browser-cube-demo?
    (and browser-cube-demo-env
         (not (or (= browser-cube-demo-env "0")
                  (= (string.lower browser-cube-demo-env) "false")
                  (= (string.lower browser-cube-demo-env) "off")))))
  (when app.browser-cube-surface
    (app.browser-cube-surface:drop)
    (set app.browser-cube-surface nil))
  (when browser-cube-demo?
    (local BrowserCubeSurface (require :browser-cube-surface))
    (set app.browser-cube-surface (BrowserCubeSurface {})))
  (when app.menu-manager
    (app.menu-manager:drop)
    (set app.menu-manager nil))
  (set app.menu-manager (MenuManager))

  (when app.panel-transfer
    (set app.panel-transfer nil))
  (set app.panel-transfer (PanelTransfer))
  (fn active-canvas-panel-target []
    (or (and app.canvas
             app.canvas.active-activity-slot
             app.canvas.active-activity-slot.visible?
             app.canvas.active-activity-slot)
        app.canvas))
  (app.panel-transfer:register-receiver
    {:id :hud
     :label "HUD"
     :icon "dashboard"
     :target-fn (fn [] app.hud)
     :rollback (fn [_r el]
                 (var removed false)
                 (when (and app.hud app.hud.remove-panel-child)
                   (set removed (app.hud:remove-panel-child el)))
                 removed)})
  (app.panel-transfer:register-receiver
    {:id :scene
     :label "Scene"
     :icon "view_in_ar"
     :target-fn (fn [] app.scene)
     :rollback (fn [_r el]
                 (when (and app.scene app.scene.remove-panel-child)
                   (app.scene:remove-panel-child el)))})
  (app.panel-transfer:register-receiver
    {:id :canvas
     :label "Canvas"
     :icon "space_dashboard"
     :target-fn active-canvas-panel-target
     :rollback (fn [_r el]
                  (var removed false)
                  (local target (active-canvas-panel-target))
                  (when (and target target.remove-panel-child)
                    (set removed (target:remove-panel-child el)))
                  removed)})

  (when app.system-cursors
    (app.system-cursors:reset))
  (if (and (app-root-reload-in-progress?)
           app.tray-manager
           app.notify)
      true
      (do
        (when app.tray-manager
          (app.tray-manager.drop)
          (set app.tray-manager nil))
        (set app.tray-manager (Tray))
        (when app.tray-manager
          (app.tray-manager.setup))
        (set app.notify (Notify))
        true))
  (when app.wallet
    (set app.wallet nil))
  (set app.wallet (WalletManager {}))
  (app.wallet:load-active)
  (ensure-hot-reload-controller)

  (when (not app.mcp-tools)
    (local ToolRegistry (require :mcp/tool-registry))
    (set app.mcp-tools (ToolRegistry {:namespace-prefix "space_"})))
  (when (not app.agent-tool-adapters)
    (set app.agent-tool-adapters (AgentToolAdapterRegistry.ToolAdapterRegistry {})))
  (when (not app.agent-presets)
    (set app.agent-presets
         (AgentPresetManager.PresetManager
           {:registry (AgentPresetRegistry.PresetRegistry {})
            :tool-adapters app.agent-tool-adapters
            :app app
            :context (agent-preset-context)}))
    (AgentBuiltinDrawing.register app.agent-presets)
    (AgentBuiltinGraph.register app.agent-presets)
    (AgentBuiltinScene.register app.agent-presets)
    (AgentBuiltinGeneral.register app.agent-presets)
    (AgentBuiltinUnits.register app.agent-presets)
    (AgentBuiltinRepo.register app.agent-presets))
  (app.agent-presets:set-context (agent-preset-context))

  ;; Agent layer bootstrap
  (when (not app.agent-registry)
    (set app.agent-registry (AgentRegistry.AgentRegistry {:deps {:app app}})))
  (when (not app.agent-approvals)
    (set app.agent-approvals
         (AgentApprovals.AgentApprovals
           {:data-dir (fs.join-path app.user-data-dir "agent-approvals")
             :policy {:normal :auto
                      :filesystem-read :ask
                      :filesystem-write {:default :ask
                                         :tools {:unit.create-test :auto}}
                      :destructive :ask
                      :shell {:default :ask
                              :tools {:unit.create :auto
                                      :unit.eval :auto
                                      :unit.connect-signal :auto}}}})))
  (when (not app.agent-tool-surface)
    (set app.agent-tool-surface
         (AgentToolSurface.AgentToolSurface
           {:presets app.agent-presets
            :mcp-tools app.mcp-tools
            :approvals app.agent-approvals})))
  (when app.agent-preset-mcp-sync
    (app.agent-preset-mcp-sync:stop)
    (set app.agent-preset-mcp-sync nil))
  (when (and app.agent-tool-surface (not app.agent-mcp-sync))
    (set app.agent-mcp-sync
         (AgentMcpSync.AgentMcpSync {:surface app.agent-tool-surface
                                     :change-source app.agent-presets
                                     :tool-registry app.mcp-tools
                                     :owner "agent-tools"}))
    (app.agent-mcp-sync:start))
  (when (not app.agent-opencode-mcp-bridge)
    (set app.agent-opencode-mcp-bridge
          (AgentOpencodeMcpBridge.AgentOpencodeMcpBridge
            {:tools app.mcp-tools :data-dir (fs.join-path app.user-data-dir "agent-opencode") :space-data-dir app.user-data-dir
             :space-cache-dir (appdirs.user-cache-dir "space") :code-dir app.code-dir :artifact-root (fs.join-path app.user-data-dir "agent-artifacts")}))
    (app.agent-opencode-mcp-bridge:start))
  (when (and app.workspace-shell-changed (not app.agent-presets-workspace-handler))
    (set app.agent-presets-workspace-handler
         (app.workspace-shell-changed:connect
           (fn [_payload]
             (app.agent-presets:set-context (agent-preset-context))))))

  (when (not app.agent-providers)
    (set app.agent-providers {}))
  (when (not (. app.agent-providers :opencode-factory))
    (tset app.agent-providers :opencode-factory
          (fn []
            (local bridge (or app.agent-opencode-mcp-bridge
                              (error "OpenCode agent provider requires app.agent-opencode-mcp-bridge")))
            (local provider
              (OpencodeSdk.Opencode
                {:opencode-path (or (os.getenv "OPENCODE_PATH") "opencode")
                 :env (bridge:opencode-env)}))
            (tset app.agent-providers :opencode provider)
            provider)))
  (when (not (. app.agent-providers :refresh-opencode))
    (tset app.agent-providers :refresh-opencode
          (fn []
            (local bridge (or app.agent-opencode-mcp-bridge
                              (error "OpenCode agent provider refresh requires app.agent-opencode-mcp-bridge")))
            (AgentOpencodeMcpBridge.refresh-opencode-provider!
              app.agent-providers
              bridge))))
  (SpaceAgent.register app.agent-registry
    {:app app
     :presets app.agent-presets
     :tools app.agent-tool-surface
     :approvals app.agent-approvals
     :providers app.agent-providers})
  (PromptUtils.register-enricher
    :active-world
    (fn [ctx]
      (when ctx.app.world-manager
        "active world available")))
  (PromptUtils.register-enricher
    :unit-context
    (fn [ctx]
      (when ctx.app.unit-manager
        (local units (ctx.app.unit-manager:list))
        (when (> (length units) 0)
          (local parts [(.. "Registered units (" (length units) "):")])
          (each [_ unit (ipairs units)]
            (table.insert parts
              (.. "- " unit.id
                 " (source:" (or unit.source :user) ")"
                 (if (unit:loaded?) " [loaded]" " [unloaded]"))))
          (table.insert parts
            (.. "Code directory: " (or ctx.app.code-dir "N/A")))
          (local log-path (logging.get-output-path))
          (table.insert parts (.. "Log file: " log-path))
          (table.insert parts
             "Available signals on app: workspace-shell-changed, activities-changed")
          (table.insert parts
            "Use space_unit_read_log to check for runtime errors after unit operations.")
          ;; Scan for existing test modules
          (when (and ctx.app.code-dir (fs.exists ctx.app.code-dir))
            (var test-summary [])
            (fn add-test-lines! [unit unit-dir]
              (when (and unit-dir (fs.exists unit-dir))
                (local entries (fs.list-dir unit-dir))
                (each [_ entry (ipairs entries)]
                  (local entry-name (or entry.name entry))
                  (when (and (= (type entry-name) :string)
                             (string.match entry-name "^test%-.*%.fnl$"))
                    (table.insert test-summary
                      (.. "  " unit.id "/" entry-name " -> run: space_unit_run_tests "
                          "{id \"" unit.id "\" test-name \""
                          (string.match entry-name "^test%-(.*)%.fnl$") "\"}"))))))
            (each [_ unit (ipairs units)]
              (when (not (= unit.source :builtin))
                (var scanned-dirs {})
                (fn scan-dir! [unit-dir]
                  (when (and unit-dir (not (. scanned-dirs unit-dir)))
                    (tset scanned-dirs unit-dir true)
                    (add-test-lines! unit unit-dir)))
                (scan-dir! (fs.join-path ctx.app.code-dir (or unit.module-name unit.id)))
                (var unit-dir nil)
                (each [_ path (ipairs (or unit.owned-paths []))]
                  (when (not unit-dir)
                    (set unit-dir (fs.parent path))))
                (scan-dir! unit-dir)))
            (when (> (length test-summary) 0)
              (table.insert parts "Existing test modules:")
              (each [_ line (ipairs test-summary)]
                (table.insert parts line))))
          (table.concat parts "\n")))))
  (when (not app.agent-runner)
    (set app.agent-runner
         (WorkflowAgentRunner.WorkflowAgentRunner
           {:workflow-store app.workflow-store :workflow-runner app.workflow-runner
             :code-store app.code-store :registry app.agent-registry
             :artifact-root (fs.join-path app.user-data-dir "agent-artifacts")
            :deps {:app app
                   :presets app.agent-presets
                   :tools app.agent-tool-surface
                   :approvals app.agent-approvals
                   :agents app.agent-registry :providers app.agent-providers
                   :opencode-mcp-bridge app.agent-opencode-mcp-bridge}})))

  ;; Rebuild HUD to show agent panel now that runner is available
  (when (and app.hud app.agent-runner)
    (apply-active-world-hud-contrib))

  (local init-end-ms (wall-now-ms))
  (logging.info
    (string.format "[space] init completed in %.2fms"
                   (- init-end-ms init-start-ms)))

  (app.update 0)
  (logging.info (string.format "[space] first update completed in %.2fms"
                               (- (wall-now-ms) init-end-ms)))
  )

(fn read-debug-log-content []
  (local (ok content) (pcall fs.read-file DebugLog.log-path))
  (if ok content nil))

(fn restore-debug-log-history! [snapshot-content]
  (when snapshot-content
    (local (ok current-content) (pcall fs.read-file DebugLog.log-path))
    (local current (if ok current-content ""))
    (when (not (and ok
                    (string.find current snapshot-content 1 true)))
      (local combined
        (if (> (# current) 0)
            (.. snapshot-content "\n" current)
            snapshot-content))
      (pcall fs.write-file DebugLog.log-path combined))))

(fn app.snapshot-app-state []
  (local active-world-id
    (or (and app.active-world-entry app.active-world-entry.id)
        (and app.world-manager
             app.world-manager.active-world-id
             (app.world-manager:active-world-id))))
  (local snapshot
    {:active-world-id active-world-id
     :active-activity-id app.active-activity-id
     :preferred-interaction-surface app.preferred-interaction-surface
     :active-interaction-surface app.active-interaction-surface
     :canvas-visible? app.canvas-visible?
     :debug-log-content (read-debug-log-content)})
  snapshot)

(fn app.restore-app-state [state]
  (local snapshot (or state {}))
  (when (and snapshot.active-world-id
             app.world-manager
             app.world-manager.activate-world-id)
    (app.world-manager:activate-world-id snapshot.active-world-id))
  (when app.set-active-activity
    (app.set-active-activity snapshot.active-activity-id))
  (when (and snapshot.preferred-interaction-surface app.set-active-interaction-surface)
    (app.set-active-interaction-surface snapshot.preferred-interaction-surface
                                        {:sync-canvas-visibility false}))
  (when (and (not (= snapshot.canvas-visible? nil))
             app.set-canvas-visible)
    (app.set-canvas-visible snapshot.canvas-visible?))
  (restore-debug-log-history! snapshot.debug-log-content)
  true)

(fn app.update [delta]
  (local profiler app.profiler)
  (fn run-section [label cb]
    (if profiler
        (profiler.measure label cb)
        (cb)))
  (local pending app.next-frame-pending)
  (local queued app.next-frame-queue)
  (set app.next-frame-queue [])
  (each [_ cb (ipairs queued)]
    (table.insert pending cb))
  (set app.next-frame-pending pending)
  (when profiler
    (profiler.begin-frame delta))
  (when (and app.settings app.runtime-performance-state)
    (if (RuntimePerformance.update-idle-state app.settings app.runtime-performance-state (os.clock))
        (apply-runtime-performance-settings)))
  (flush-window-settings-save)
  (local ui-paused (= app.runtime-performance-ui-paused true))
  (when (not ui-paused)
    (when (and app.world-manager app.world-manager.update)
      (app.world-manager:update delta))
    (let [provider (app.active-presentation)]
      (when (and app.engine.audio provider)
        (let [audio-cam (provider:audio-listener-camera)]
          (when audio-cam
            (local forward (audio-cam:get-forward))
            (local up (audio-cam:get-up))
            (app.engine.audio:setListenerPosition audio-cam.position)
            (app.engine.audio:setListenerOrientation forward up)))))
    (when app.scene
      (run-section "scene" (fn [] (app.scene:update))))
    (when app.canvas
      (run-section "canvas" (fn [] (app.canvas:update))))
    (when app.hud
      (run-section "hud" (fn [] (app.hud:update))))
    (when app.renderers
      (run-section "renderers" (fn [] (app.renderers:update))))
    (run-next-ui-frame))
  (when app.tray-manager
    (app.tray-manager.loop))
  (when profiler
    (profiler.end-frame))
  )

(fn drop-agent-runtime! []
  (when app.agent-runner
    (app.agent-runner:drop)
    (set app.agent-runner nil))
  (when app.agent-providers
    (local opencode app.agent-providers.opencode)
    (when (and opencode opencode.close)
      (opencode.close)))
  (set app.agent-providers nil)
  (when app.agent-opencode-mcp-bridge
    (app.agent-opencode-mcp-bridge:stop)
    (set app.agent-opencode-mcp-bridge nil))
  (when app.agent-mcp-sync
    (app.agent-mcp-sync:stop)
    (set app.agent-mcp-sync nil))
  (when (and app.agent-presets-workspace-handler app.workspace-shell-changed)
    (app.workspace-shell-changed:disconnect app.agent-presets-workspace-handler true)
    (set app.agent-presets-workspace-handler nil))
  (set app.agent-tool-surface nil)
  (set app.agent-approvals nil)
  (set app.agent-registry nil)
  (set app.agent-presets nil)
  (set app.agent-tool-adapters nil)) (var drop-built-in-graph-extensions! nil)

(fn app.drop []
  (set (. package.loaded "renderers") nil)
  (set app.workflow-runner nil)
  (set app.workflow-code-executor nil)
  (set app.workflow-store nil)
  (set app.code-store nil)
  (drop-agent-runtime!)
  (InputState.release-active-input)
  (AppBootstrap.drop-states)
  (when (and app.update-handler app.engine.events app.engine.events.updated)
    (app.engine.events.updated:disconnect app.update-handler true)
    (set app.update-handler nil))
  (when (and app.engine-tick-handler app.engine.events app.engine.events.engine-tick)
    (app.engine.events.engine-tick:disconnect app.engine-tick-handler true)
    (set app.engine-tick-handler nil))
  (when (and app.window-resized-handler app.engine.events app.engine.events.window-resized)
    (app.engine.events.window-resized:disconnect app.window-resized-handler true)
    (set app.window-resized-handler nil))
  (when (and app.window-pixel-size-handler app.engine.events app.engine.events.window-pixel-size-changed)
    (app.engine.events.window-pixel-size-changed:disconnect app.window-pixel-size-handler true)
    (set app.window-pixel-size-handler nil))
  (when (and app.window-mode-handler app.engine.events app.engine.events.window-mode-changed)
    (app.engine.events.window-mode-changed:disconnect app.window-mode-handler true)
    (set app.window-mode-handler nil))
  (when (and app.window-focus-handler app.engine.events app.engine.events.window-focus-changed)
    (app.engine.events.window-focus-changed:disconnect app.window-focus-handler true)
    (set app.window-focus-handler nil))
  (when (and app.window-minimized-handler app.engine.events app.engine.events.window-minimized-changed)
    (app.engine.events.window-minimized-changed:disconnect app.window-minimized-handler true)
    (set app.window-minimized-handler nil))
  (when (and app.window-occluded-handler app.engine.events app.engine.events.window-occluded-changed)
    (app.engine.events.window-occluded-changed:disconnect app.window-occluded-handler true)
    (set app.window-occluded-handler nil))
  (when (and app.window-hidden-handler app.engine.events app.engine.events.window-hidden-changed)
    (app.engine.events.window-hidden-changed:disconnect app.window-hidden-handler true)
    (set app.window-hidden-handler nil))
  (when (and app.app-suspended-handler app.engine.events app.engine.events.app-suspended-changed)
    (app.engine.events.app-suspended-changed:disconnect app.app-suspended-handler true)
    (set app.app-suspended-handler nil))
  (when (and app.screen-locked-handler app.engine.events app.engine.events.screen-locked-changed)
    (app.engine.events.screen-locked-changed:disconnect app.screen-locked-handler true)
    (set app.screen-locked-handler nil))
  (when (and app.on-battery-handler app.engine.events app.engine.events.on-battery-changed)
    (app.engine.events.on-battery-changed:disconnect app.on-battery-handler true)
    (set app.on-battery-handler nil))
  (when (and app.video-playback-active-handler app.engine.events app.engine.events.video-playback-active-changed)
    (app.engine.events.video-playback-active-changed:disconnect app.video-playback-active-handler true)
    (set app.video-playback-active-handler nil))
  (disconnect-runtime-performance-input-handlers)
  (when (and app.global-shortcuts-handler app.engine.events app.engine.events.key-down)
    (app.engine.events.key-down:disconnect app.global-shortcuts-handler true)
    (set app.global-shortcuts-handler nil))
  (when (and app.world-manager app.world-manager.drop)
    (app.world-manager:drop)
    (set app.world-manager nil))
  (Activities.clear-activity-runtime-hooks!) (drop-built-in-graph-extensions!)
  (when app.unit-manager
    (app.unit-manager:clear) (set app.graph-extension-registry nil))
  (set app.canvas-unit nil)
  (set app.active-world-entry nil)
  (set app.active-world-runtime nil)
  (set app.canvas-controls nil)
  (set app.active-pointer-controls nil)
  (set app.graph nil)
  (set app.graph-map nil)
  (set app.graph-map-manager nil)
  (set app.graph-view nil)
  (set app.board nil)
  (set app.board-view nil)
  (set app.object-selector nil)
  (set app.terrain-rect-pick-session nil)
  (set app.terrain-rect-pick-previous-state nil)
  (set app.terrain-paint-session nil)
  (set app.terrain-paint-previous-state nil)
  (set app.scene nil)
  (set app.canvas nil)
  (set app.preferred-interaction-surface :scene)
  (set app.active-interaction-surface :scene)
  (set app.active-activity-id nil)
  (set app.scene-interactive? true)
  (set app.canvas-interactive? false)
  (set app.canvas-surface-interactive? true)
  (set app.canvas-visible? false)
  (set app.world-tabs-builder nil)
  (set app.active-world-hud-contrib nil)
  (set app.active-world-hud-overlay nil)
  (set app.activity-units nil)
  (set app.hud-unit nil)
  (when app.hoverables
    (app.hoverables:drop)
    (set app.hoverables nil))
  (when app.movables
    (app.movables:drop)
    (set app.movables nil))
  (when app.resizables
    (app.resizables:drop)
    (set app.resizables nil))
  (when app.intersectables
    (app.intersectables:drop)
    (set app.intersectables nil))
  (when app.system-cursors
    (app.system-cursors:drop)
    (set app.system-cursors nil))
  (when app.browser-cube-surface
    (app.browser-cube-surface:drop)
    (set app.browser-cube-surface nil))
  (when app.renderers
    (app.renderers:drop)
    (set app.renderers nil))
  (when app.menu-manager
    (app.menu-manager:drop)
    (set app.menu-manager nil))
  (when app.panel-transfer
    (set app.panel-transfer nil))
  (when (and app.focus-void-callback app.clickables)
    (app.clickables:unregister-left-click-void-callback app.focus-void-callback)
    (set app.focus-void-callback nil))
  (when app.focus
    (app.focus:drop)
    (set app.focus nil))
  (set app.scene-focus-scope nil)
  (set app.canvas-focus-scope nil)
  (set app.hud-focus-scope nil)
  (when app.profiler
    (app.profiler.set_enabled false)
    (set app.profiler nil))
  (when app.remote-control
    (app.remote-control:drop)
    (set app.remote-control nil))
  (when (and app.kernels app.kernels.drop)
    (app.kernels:drop)
    (set app.kernels nil))
  (set app.next-frame-queue [])
  (set app.next-frame-pending [])
  (set app.projection nil)
  (set app.layout-root nil)
  (if (app-root-reload-in-progress?)
      (logging.info "[space] drop preserving tray and notify during app-root reload")
      (do
        (when app.tray-manager
          (app.tray-manager.drop)
          (set app.tray-manager nil))
        (set app.notify nil)))
  (when (and (not (app-root-reload-in-progress?))
             app.hot-reload-callback-id)
    (callbacks.unregister app.hot-reload-callback-id)
    (set app.hot-reload-callback-id nil))
  (when (and (not (app-root-reload-in-progress?))
             app.hot-reload-controller)
    (app.hot-reload-controller:drop)
    (set app.hot-reload-controller nil))
  (when (and app.volume-settings-handler VolumeControl.volume-settings-changed-debounced)
    (VolumeControl.volume-settings-changed-debounced:disconnect app.volume-settings-handler true)
    (set app.volume-settings-handler nil))
  (when (and app.window-settings-dirty app.settings app.settings.save)
    (app.settings.save)
    (set app.window-settings-dirty false))
  (when (and app.settings app.settings.drop)
    (app.settings.drop)
    (set app.settings nil))
  (set app.runtime-performance-state nil)
  (set app.runtime-performance-control-mode nil)
  (set app.runtime-performance-active-mode nil)
  (set app.runtime-performance-fps-cap nil)
  (set app.runtime-performance-physics-paused nil)
  (set app.startup-physics-pause-owner nil)
  (set app.runtime-performance-input-paused nil)
  (set app.runtime-performance-ui-paused nil)
  (set app.runtime-performance-source nil)
  (set app.runtime-performance-active-override nil)
  (sync-physics-paused-state)
  )
(fn ensure-graph-extension-registry! []
  (when (not app.graph-extension-registry)
    (local Registry (require :graph/extension-registry))
    (set app.graph-extension-registry (Registry.GraphExtensionRegistry {:app app})))
  app.graph-extension-registry)

(fn built-in-graph-extension-options [opts]
  (local options (or opts {}))
  (local StringEntityStore (require :entities/string))
  (local CodeEntityStore (require :entities/code))
  (local ListEntityStore (require :entities/list))
  (local LinkEntityStore (require :entities/link))
  (local IdentityStore (require :entities/identity))
  (local NotebookStore (require :notebooks/store))
  (local LlmStore (require :llm/conversations/store))
  (local WorkflowStore (require :workflows/store))
  (local KernelsStore (require :kernels))
  (local data-dir (or app.user-data-dir (appdirs.user-data-dir "space")))
  (assert data-dir "built-in graph extensions require app user data dir")
  {:world-manager (or options.world-manager app.world-manager)
   :asset-path-resolver (or options.asset-path-resolver
                            (and app.engine app.engine.get-asset-path))
   :code-store (or options.code-store app.code-store
                   (CodeEntityStore.get-default {:base-dir data-dir}))
   :workflow-store (or options.workflow-store app.workflow-store
                       (WorkflowStore.get-default {:base-dir data-dir}))
   :workflow-runner (or options.workflow-runner app.workflow-runner)
   :string-store (or options.string-store app.string-store
                     (StringEntityStore.get-default {:base-dir data-dir}))
   :list-store (or options.list-store app.list-store
                   (ListEntityStore.get-default {:base-dir data-dir}))
   :link-store (or options.link-store app.link-store
                   (LinkEntityStore.get-default {:base-dir data-dir}))
   :identity-store (or options.identity-store app.identity-store
                       (IdentityStore.get-default {:base-dir data-dir}))
   :notebook-store (or options.notebook-store app.notebook-store
                       (NotebookStore.get-default {:base-dir data-dir}))
   :llm-store (or options.llm-store app.llm-store
                  (LlmStore.get-default {:base-dir data-dir}))
   :kernels (or options.kernels app.kernels (KernelsStore.get-default))
   :hackernews-ensure-client (or options.hackernews-ensure-client
                                 app.hackernews-ensure-client)})

(fn ensure-built-in-graph-extensions! [opts]
  (if app.builtin-graph-extension-handles
      app.builtin-graph-extension-handles
      (do
        (local BuiltInGraphExtensions (require :graph/extensions/builtins))
        (local registry (ensure-graph-extension-registry!))
        (local handles (BuiltInGraphExtensions.register!
                         registry
                         (built-in-graph-extension-options opts)))
        (set app.builtin-graph-extension-handles handles)
        handles)))

(set drop-built-in-graph-extensions!
     (fn []
       (when app.builtin-graph-extension-handles
         (for [i (length app.builtin-graph-extension-handles) 1 -1]
           (local handle (. app.builtin-graph-extension-handles i))
           (when (and handle handle.unregister)
             (handle:unregister)))
         (set app.builtin-graph-extension-handles nil))
       true))

(set app.ensure-graph-extension-registry! ensure-graph-extension-registry!)
(set app.ensure-built-in-graph-extensions! ensure-built-in-graph-extensions!)

(when (and app.engine AppConfig.run-main (not app.__suppress-main-run?))
  (when app.engine-autocreated
    (set app.engine (EngineModule.Engine (load-window-startup-options)))
    (set app.engine-autocreated false))
  (when (not (app.engine:start))
    (error "[space] engine failed to start (window/GL init failed)"))
  (app.init)
  (app.engine:run)
  (app.drop)
  (when (and app.hot-reload-controller app.hot-reload-controller.drop)
    (app.hot-reload-controller:drop)
    (set app.hot-reload-controller nil))
  (app.engine:shutdown))

{:init app.init
  :build-hud-world-tabs-widget build-hud-world-tabs-widget
  :install-app-shell! install-app-shell!
   :bind-active-world-runtime installable-bind-active-world-runtime
   :ensure-graph-extension-registry! app.ensure-graph-extension-registry!
   :ensure-built-in-graph-extensions! app.ensure-built-in-graph-extensions!
   :ensure-user-code-units! ensure-user-code-units!
 :clear-fennel-module-cache! clear-fennel-module-cache!
 :drop app.drop
 :snapshot app.snapshot-app-state
 :restore app.restore-app-state}
