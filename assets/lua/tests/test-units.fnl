(local callbacks (require :callbacks))
(local fennel (require :fennel))
(local fs (require :fs))
(local tempfile (require :tempfile))
(local FileWatch (require :file-watch))
(local HotReload (require :hot-reload))
(local runtime (require :runtime))
(local Activities (require :activities))
(local Units (require :units))

(local tests [])

(fn with-temp-dir [f]
  (local handle (tempfile.TemporaryDirectory {:prefix "units-test-"}))
  (local path handle.path)
  (local (ok result) (pcall f path))
  (handle:drop)
  (if ok
      result
      (error result)))

(fn with-temp-module-search-path [dir f]
  (local original-fennel-path fennel.path)
  (local original-package-path package.path)
  (local fennel-prefix (.. dir "/?.fnl;" dir "/?/init.fnl"))
  (local package-prefix (.. dir "/?.lua"))
  (set fennel.path (.. fennel-prefix ";" original-fennel-path))
  (set package.path (.. package-prefix ";" original-package-path))
  (local cache-searcher package.__space_fennel_cache_searcher)
  (var cache-index nil)
  (when cache-searcher
    (each [i searcher (ipairs package.searchers) &until cache-index]
      (when (= searcher cache-searcher)
        (set cache-index i)))
    (when cache-index
      (table.remove package.searchers cache-index)))
  (local (ok result) (pcall f))
  (set fennel.path original-fennel-path)
  (set package.path original-package-path)
  (when cache-index
    (table.insert package.searchers cache-index cache-searcher))
  (if ok
      result
      (error result)))

(fn clear-loaded-modules! [module-names]
  (each [_ module-name (ipairs module-names)]
    (set (. package.loaded module-name) nil))
  true)

(fn wait-until [predicate opts]
  (local options (or opts {}))
  (callbacks.run-loop {:sleep-ms (or options.sleep-ms 10)
                       :timeout-ms (or options.timeout-ms 2000)
                       :until predicate}))

;; Fast unit tests for file-watch, module units, hot-reload controller, and activity registry.

(fn file-watch-detects-basic-events []
  (with-temp-dir
    (fn [dir]
      (local watcher (FileWatch.FileWatcher {}))
      (local path (fs.join-path dir "watched.fnl"))
      (var saw-write? false)
      (var saw-delete? false)
      (watcher:add-watch dir false)
      (watcher:start)
      (fs.write-file path "(local x 1)\n")
      (fs.append-file path "(local y 2)\n")
      (assert (wait-until
                (fn []
                  (each [_ event (ipairs (watcher:poll))]
                    (when (and (= event.path path)
                               (or (= event.action "add")
                                   (= event.action "modified")))
                      (set saw-write? true)))
                  saw-write?))
              "Expected file-watch to observe write event")
      (fs.remove path)
      (assert (wait-until
                (fn []
                  (each [_ event (ipairs (watcher:poll))]
                    (when (and (= event.path path)
                               (= event.action "delete"))
                      (set saw-delete? true)))
                  saw-delete?))
              "Expected file-watch to observe delete event")
      (watcher:drop)
      true)))

(fn module-unit-reload-applies-edited-implementation []
  (with-temp-dir
    (fn [dir]
      (with-temp-module-search-path
        dir
        (fn []
          (local module-names ["tmp_reload_impl"
                               "tmp_reload_unit"])
          (clear-loaded-modules! module-names)
          (fs.write-file (fs.join-path dir "tmp_reload_impl.fnl")
                         "{:version \"v1\"}\n")
           (fs.write-file (fs.join-path dir "tmp_reload_unit.fnl")
                          (.. "(local TempImpl (require :tmp_reload_impl))\n"
                              "(fn load-child! []\n"
                              "  (set app.__tmp-reload-version TempImpl.version)\n"
                              "  true)\n"
                              "(fn unload-child! [] true)\n"
                              "(fn snapshot-child! [] app.__tmp-reload-version)\n"
                              "(fn restore-child! [state]\n"
                              "  (set app.__tmp-reload-restored state)\n"
                              "  true)\n"
                              "{:load-child! load-child!\n"
                              " :unload-child! unload-child!\n"
                              " :snapshot-child! snapshot-child!\n"
                             " :restore-child! restore-child!}\n"))
          (local previous-engine (and app app.engine))
          (set app.engine {:now-ms (fn [_self]
                                     (math.floor (* (os.clock) 1000.0)))})
          (local unit
            (Units.ModuleUnit
              {:id "tmp-reload"
               :module-name "tmp_reload_unit"
               :owned-paths [dir]
               :load-export "load-child!"
               :unload-export "unload-child!"
               :snapshot-export "snapshot-child!"
               :restore-export "restore-child!"}))
          (local controller
            (HotReload.HotReloadController
              {:unit unit
               :watch-paths [dir]
               :preserve-modules ["hot-reload" "tests.test-units" "units"]}))
          (local (ok result)
            (pcall
               (fn []
                (unit:load)
                (assert (= app.__tmp-reload-version "v1")
                        "Expected initial module unit load to use v1")
                (local impl-path (fs.join-path dir "tmp_reload_impl.fnl"))
                (fs.write-file impl-path "{:version \"v2\"}\n")
                (assert (controller:reload-now!
                          {:changes [{:path impl-path
                                      :action "modified"}]})
                        "Expected module unit reload to succeed")
                (assert (= app.__tmp-reload-version "v2")
                        "Expected module unit reload to apply updated dependency code")
                (assert (= app.__tmp-reload-restored "v1")
                        "Expected module unit reload to restore prior snapshot state")
                true)))
          (controller:drop)
          (clear-loaded-modules! module-names)
          (set app.__tmp-reload-version nil)
          (set app.__tmp-reload-restored nil)
          (set app.engine previous-engine)
          (if ok
              result
              (error result)))))))

(fn hot-reload-clears-deleted-modules-by-known-source-path []
  (with-temp-dir
    (fn [dir]
      (with-temp-module-search-path
        dir
        (fn []
          (local module-names ["tmp_delete_dep"
                               "tmp_delete_unit"])
          (clear-loaded-modules! module-names)
          (local dep-path (fs.join-path dir "tmp_delete_dep.fnl"))
          (local unit-path (fs.join-path dir "tmp_delete_unit.fnl"))
          (fs.write-file dep-path
                         "{:value \"with-dep\"}\n")
          (fs.write-file unit-path
                         (.. "(local TempDep (require :tmp_delete_dep))\n"
                             "(fn load-child! []\n"
                             "  (set app.__tmp-delete-value TempDep.value)\n"
                             "  true)\n"
                             "(fn unload-child! [] true)\n"
                             "(fn snapshot-child! [] app.__tmp-delete-value)\n"
                             "(fn restore-child! [state]\n"
                             "  (set app.__tmp-delete-restored state)\n"
                             "  true)\n"
                             "{:load-child! load-child!\n"
                             " :unload-child! unload-child!\n"
                             " :snapshot-child! snapshot-child!\n"
                             " :restore-child! restore-child!}\n"))
          (local previous-engine (and app app.engine))
          (set app.engine {:now-ms (fn [_self]
                                     (math.floor (* (os.clock) 1000.0)))})
          (local unit
            (Units.ModuleUnit
              {:id "tmp-delete"
               :module-name "tmp_delete_unit"
               :owned-paths [dir]
               :load-export "load-child!"
               :unload-export "unload-child!"
               :snapshot-export "snapshot-child!"
               :restore-export "restore-child!"}))
          (local controller
            (HotReload.HotReloadController
              {:unit unit
               :watch-paths [dir]
               :preserve-modules ["hot-reload" "tests.test-units" "units"]}))
          (local (ok result)
            (pcall
              (fn []
                (unit:load)
                (assert (= app.__tmp-delete-value "with-dep")
                        "Expected initial module load to use dependency")
                (assert (. package.loaded "tmp_delete_dep")
                        "Expected dependency module to be loaded")
                (fs.write-file unit-path
                               (.. "(fn load-child! []\n"
                                   "  (set app.__tmp-delete-value \"without-dep\")\n"
                                   "  true)\n"
                                   "(fn unload-child! [] true)\n"
                                   "(fn snapshot-child! [] app.__tmp-delete-value)\n"
                                   "(fn restore-child! [state]\n"
                                   "  (set app.__tmp-delete-restored state)\n"
                                   "  true)\n"
                                   "{:load-child! load-child!\n"
                                   " :unload-child! unload-child!\n"
                                   " :snapshot-child! snapshot-child!\n"
                                   " :restore-child! restore-child!}\n"))
                (fs.remove dep-path)
                (assert (controller:reload-now!
                          {:changes [{:path dep-path
                                      :action "delete"}
                                     {:path unit-path
                                      :action "modified"}]})
                        "Expected reload after dependency deletion to succeed")
                (assert (= app.__tmp-delete-value "without-dep")
                        "Expected reloaded unit to use updated implementation")
                (assert (= app.__tmp-delete-restored "with-dep")
                        "Expected delete reload to restore prior snapshot state")
                (assert (= (. package.loaded "tmp_delete_dep") nil)
                        "Expected deleted module to be cleared from package.loaded")
                true)))
          (controller:drop)
          (clear-loaded-modules! module-names)
          (set app.__tmp-delete-value nil)
          (set app.__tmp-delete-restored nil)
          (set app.engine previous-engine)
          (if ok
              result
              (error result)))))))

(fn activities-require-registration-before-activation []
  (local previous-registry app.activity-registry)
  (local previous-root-actions app.activity-root-actions)
  (local previous-selection-actions app.activity-selection-actions)
  (local previous-left-dock-builder app.activity-left-dock-builder)
  (local previous-command-hints-provider app.activity-command-hints-provider)
  (local previous-delete-selection app.activity-delete-selection)
  (local previous-activate-focused app.activity-activate-focused)
  (local previous-drawing-enabled app.activity-drawing-enabled?)
  (local previous-target-enabled app.activity-target-enabled?)
  (local previous-mode-update app.activity-update)
  (set app.activity-registry nil)
  (Activities.clear-activity-runtime-hooks!)
  (local (resolve-ok _resolve-err)
    (pcall Activities.resolve "graph"))
  (assert (not resolve-ok)
          "Activities.resolve should reject built-in ids before they are registered")
  (Activities.register-activity
    {:id "graph"
     :label "Graph"
     :icon "account_tree"
     :button-name "graph-activity"
     :show-in-switcher? true
     :activate (fn [ctx]
                 (ctx:set-root-actions! (fn [_context] []))
                 {:activity-id "graph"})
     :deactivate (fn [_ctx _session]
                   true)})
  (Activities.activate-activity "graph")
  (assert (= (Activities.active-activity-id) "graph")
          "Activities.activate-activity should activate a registered mode")
  (Activities.unregister-activity "graph")
  (local (activate-ok _activate-err)
    (pcall Activities.activate-activity "graph"))
  (set app.activity-registry previous-registry)
  (set app.activity-root-actions previous-root-actions)
  (set app.activity-selection-actions previous-selection-actions)
  (set app.activity-left-dock-builder previous-left-dock-builder)
  (set app.activity-command-hints-provider previous-command-hints-provider)
  (set app.activity-delete-selection previous-delete-selection)
  (set app.activity-activate-focused previous-activate-focused)
  (set app.activity-drawing-enabled? previous-drawing-enabled)
  (set app.activity-target-enabled? previous-target-enabled)
  (set app.activity-update previous-mode-update)
  (assert (not activate-ok)
          "Activities.activate-activity should reject modes once they are unregistered"))

(table.insert tests {:name "file-watch detects write/delete events"
                     :fn file-watch-detects-basic-events})
(table.insert tests {:name "module unit reload applies edited implementation"
                     :fn module-unit-reload-applies-edited-implementation})
(table.insert tests {:name "hot reload clears deleted modules by known source path"
                     :fn hot-reload-clears-deleted-modules-by-known-source-path})
(table.insert tests {:name "activities require registration before activation"
                     :fn activities-require-registration-before-activation})

(fn path-separator-rejects-backslash-on-posix []
  (local path-utils (require :path-utils))
  (local windows? (= (string.sub (or package.config "") 1 1) "\\"))
  (if windows?
      (do
        (assert (path-utils.path-separator? "\\")
                "backslash should be separator on Windows")
        (assert (path-utils.path-separator? "/")
                "forward slash should be separator on all platforms"))
      (do
        (assert (path-utils.path-separator? "/")
                "forward slash should be separator on POSIX")
        (assert (not (path-utils.path-separator? "\\"))
                "backslash must NOT be a separator on POSIX — it is a valid filename character"))))

(table.insert tests {:name "path separator rejects backslash on POSIX"
                     :fn path-separator-rejects-backslash-on-posix})

(fn make-reload-fixture-root [dir state]
  (fn snapshot [_ctx]
    (when (= state.fail "snapshot")
      (set app.__hot-reload-ctx :snapshot-leak)
      (error "snapshot trap"))
    {:value "previous"})
  (fn unload [_ctx]
    (set state.unloads (+ state.unloads 1))
    (when (= state.fail "unload") (error "unload trap")))
  (fn load [ctx]
    (assert ctx "fixture load requires context")
    (assert (and app.__hot-reload-ctx
                 (= app.__hot-reload-ctx.target-unit.id "app-root"))
            "forward load and rollback must retain the root transaction context")
    (when (and (= state.fail "load") (not (= ctx.reload-phase "rollback")))
      (error "load trap"))
    (when (and state.rollback-fails? (= ctx.reload-phase "rollback"))
      (error "load trap"))
    (set state.root-loads (+ state.root-loads 1)))
  (fn restore [snapshot ctx]
    (assert (= snapshot.value "previous"))
    (set state.restores (+ state.restores 1))
    (when (and (= state.fail "restore") (not (= ctx.reload-phase "rollback")))
      (error "restore trap")))
  (Units.Unit {:id "app-root" :owned-paths [dir]
               :snapshot snapshot :unload unload :load load :restore restore}))

(fn make-reload-fixture-controller [dir state opts]
  (local root (make-reload-fixture-root dir state))
  (fn load-child [_ctx] (set state.child-loads (+ state.child-loads 1)))
  (fn unload-child [_ctx] true)
  (local child
    (Units.Unit {:id "child" :parent-id "app-root"
                 :owned-paths [(fs.join-path dir "child.fnl")]
                 :load load-child :unload unload-child}))
  (fn live-children [_root]
    (when state.selection-fails? (error "selection trap"))
    [child])
  (local config
    {:unit root :root-unit-id "app-root" :watch-paths [dir]
     :watch? opts.watch? :debounce-ms 10 :startup-ignore-ms 0
     :narrow-reload-unit-ids opts.narrow-reload-unit-ids
     :on-reload-requested opts.on-reload-requested :units-fn live-children})
  (if opts.app-root?
      (HotReload.AppRootController config)
      (HotReload.HotReloadController config)))

(fn with-reload-fixture [opts body]
  (fn run-in-dir [dir]
    (local original-engine app.engine)
    (local original-ctx app.__hot-reload-ctx)
    (local original-watcher FileWatch.FileWatcher)
    (local state {:root-loads 0 :child-loads 0 :unloads 0 :restores 0 :clock 0})
    (var controller nil)
    (fn fixture-now-ms [_self] state.clock)
    (set app.engine {:now-ms fixture-now-ms})
    (when opts.watcher
      (set FileWatch.FileWatcher opts.watcher))
    (fn run-body []
      (set controller (make-reload-fixture-controller dir state opts))
      (body controller state dir))
    (fn cleanup [] (when controller (controller:drop)))
    (local (ok result) (pcall run-body))
    (local (cleanup-ok cleanup-error) (pcall cleanup))
    (set FileWatch.FileWatcher original-watcher)
    (set app.engine original-engine)
    (set app.__hot-reload-ctx original-ctx)
    (assert cleanup-ok cleanup-error)
    (if ok result (error result)))
  (with-temp-dir run-in-dir))

(fn manual-reload-never-acquires-watcher-and-selects-root []
  (with-reload-fixture
    {:watch? false :narrow-reload-unit-ids ["child"]
     :watcher (fn [_opts] (error "manual mode constructed watcher"))}
    (fn [controller state dir]
      (fs.write-file (fs.join-path dir "child.fnl") "{:edited true}\n")
      (set state.clock 100)
      (assert (= (controller:update 0) false))
      (assert (= state.root-loads 0))
      (assert (= state.child-loads 0))
      (local debug (controller:debug-state))
      (assert (= debug.watch? false))
      (assert (= (# debug.watch-directories) 0))
      (assert (= (. debug.watch-paths 1) dir))
      (assert (controller:reload-now! {:changes [{:path (fs.join-path dir "child.fnl")}]}))
      (assert (= state.child-loads 1))
      (assert (= state.root-loads 0))
      (local result (controller:reload-root!))
      (assert result.ok)
      (assert (= result.target-unit-id "app-root"))
      (assert (= result.phase "complete"))
      (assert (= result.rollback "not-needed"))
      (assert (= state.root-loads 1))
      (assert (= state.child-loads 1))
      (assert (= (. (controller:debug-state) :last-target-unit-id) "app-root"))
      (assert (controller:drop))
      (assert (controller:drop)))))

(fn check-watcher-conversion [app-root?]
  (local events [])
  (var drops 0)
  (var polls 0)
  (var requests 0)
  (fn poll [_self]
    (set polls (+ polls 1))
    (local batch [])
    (while (> (# events) 0) (table.insert batch (table.remove events)))
    batch)
  (fn make-watcher [_opts]
    {:add-watch (fn [_self _path _recursive] true)
     :start (fn [_self] true)
     :poll poll
     :directories (fn [_self] [])
     :drop (fn [_self] (set drops (+ drops 1)))})
  (with-reload-fixture
    {:watcher make-watcher :app-root? app-root?
     :on-reload-requested (fn [_controller] (set requests (+ requests 1)))}
    (fn [controller state dir]
      (assert (= (. (controller:debug-state) :watch?) true) "watching defaults to true")
      (assert (= (. (controller:debug-state) :startup-ignore-ms) 0))
      (table.insert events {:path (fs.join-path dir "child.fnl") :action "modified"})
      (controller:update 0)
      (set state.clock 11)
      (controller:update 0)
      (assert (= requests 1))
      (assert (> (. (controller:debug-state) :pending-event-count) 0))
      (assert (controller:use-manual!))
      (assert (controller:use-manual!))
      (assert (= drops 1))
      (assert (= (. (controller:debug-state) :pending-event-count) 0))
      (assert (= (. (controller:debug-state) :pending-deadline-ms) nil))
      (local before-polls polls)
      (assert (= (controller:update 0) false))
      (assert (= polls before-polls))
      (assert (= requests 1))
      (when (not app-root?)
        (assert (. (controller:reload-root!) :ok)))
      (controller:drop)
      (controller:drop)
      (assert (= drops 1))
      (assert (not (pcall controller.use-manual! controller))))))

(fn manual-conversion-discards-scheduled-filesystem-reload []
  (check-watcher-conversion false)
  (check-watcher-conversion true))

(fn app-root-forwards-manual-construction []
  (with-reload-fixture
    {:app-root? true :watch? false
     :watcher (fn [_opts] (error "manual app root constructed watcher"))}
    (fn [controller _state _dir]
      (assert (= (. (controller:debug-state) :watch?) false))
      (assert (= (controller:update 0) false)))))

(fn root-reload-captures-failure-phases-and-restores-context []
  (with-reload-fixture
    {:watch? false}
    (fn [controller state _dir]
      (local sentinel {})
      (set app.__hot-reload-ctx sentinel)
      (set state.selection-fails? true)
      (local selection (controller:reload-root!))
      (assert (= selection.ok false))
      (assert (= selection.target-unit-id "app-root"))
      (assert (= selection.phase "target-selection"))
      (assert (= selection.rollback "not-needed"))
      (assert (string.find selection.error "selection trap" 1 true))
      (assert (= app.__hot-reload-ctx sentinel))
      (assert (= (controller:reload-now!) false))
      (set state.selection-fails? false)
      (set state.fail "snapshot")
      (local snapshot (controller:reload-root!))
      (assert (= snapshot.ok false))
      (assert (= snapshot.phase "snapshot"))
      (assert (= snapshot.rollback "not-needed"))
      (assert (string.find snapshot.error "snapshot trap" 1 true))
      (assert (= state.unloads 0))
      (assert (= app.__hot-reload-ctx sentinel))
      (each [_ phase (ipairs ["unload" "load" "restore"])]
        ;; Fail only the forward load; rollback uses a distinct context.
        (set state.fail phase)
        (local result (controller:reload-root!))
        (assert (= result.ok false))
        (assert (= result.phase phase))
        (assert (= result.rollback "restored"))
        (assert (string.find result.error (.. phase " trap") 1 true))
        (assert (= app.__hot-reload-ctx sentinel)))
      (set state.fail "restore")
      (assert (= (controller:reload-now!) false))
      (set state.rollback-fails? true)
      (local failed (controller:reload-root!))
      (assert (= failed.ok false))
      (assert (= failed.phase "restore"))
      (assert (= failed.rollback "failed"))
      (assert (string.find failed.rollback-error "load trap" 1 true))
      (assert (= app.__hot-reload-ctx sentinel))
      (local (legacy-ok legacy-error) (pcall controller.reload-now! controller))
      (assert (not legacy-ok))
      (assert (string.find legacy-error "rollback=" 1 true))
      (assert (= app.__hot-reload-ctx sentinel))
      (set state.fail nil)
      (set state.rollback-fails? false)
      (assert (. (controller:reload-root!) :ok))
      (assert (= app.__hot-reload-ctx sentinel)))))

(fn controller-validates-options-before-watcher-acquisition []
  (local original FileWatch.FileWatcher)
  (var acquired? false)
  (set FileWatch.FileWatcher (fn [_opts] (set acquired? true) (error "watcher trap")))
  (local (ok result)
    (pcall
      (fn []
        (each [_ opts (ipairs [{:watch-paths [runtime.assets-path]}
                               {:unit {:id "app-root"} :watch-paths [runtime.assets-path] :watch? "no"}])]
          (assert (not (pcall HotReload.HotReloadController opts)))
          (assert (not acquired?) "invalid options must fail before acquiring a watcher")))))
  (set FileWatch.FileWatcher original)
  (if ok result (error result)))

(table.insert tests {:name "manual reload never acquires watcher and selects root"
                     :fn manual-reload-never-acquires-watcher-and-selects-root})
(table.insert tests {:name "manual conversion discards scheduled filesystem reload"
                     :fn manual-conversion-discards-scheduled-filesystem-reload})
(table.insert tests {:name "root reload captures failure phases and restores context"
                     :fn root-reload-captures-failure-phases-and-restores-context})
(table.insert tests {:name "controller validates options before watcher acquisition"
                     :fn controller-validates-options-before-watcher-acquisition})
(table.insert tests {:name "app root forwards manual construction"
                     :fn app-root-forwards-manual-construction})
(fn with-fake-reload-watcher [f]
  (with-temp-dir
    (fn [dir]
      (local original-watcher FileWatch.FileWatcher)
      (local original-now-ms app.engine.now-ms)
      (local state {:now-ms 0 :events [] :controller nil :dropped? false})
      (set FileWatch.FileWatcher
           (fn [_opts]
             {:add-watch (fn [_self _path _recursive?] true)
              :start (fn [_self] true)
              :poll (fn [_self]
                      (local events state.events)
                      (set state.events [])
                      events)
              :directories (fn [_self] [dir])
              :drop (fn [_self] (set state.dropped? true))}))
      (set app.engine.now-ms (fn [_self] state.now-ms))
      (local (ok result) (pcall f dir state))
      (local (cleanup-ok cleanup-err)
        (pcall (fn []
                 (when state.controller
                   (state.controller:drop)))))
      (set FileWatch.FileWatcher original-watcher)
      (set app.engine.now-ms original-now-ms)
      (if (not ok) (error result)
          (not cleanup-ok) (error cleanup-err)
          result))))

(fn record-deferred-request! [spy state controller]
  (assert (= controller state.controller) "Callback must receive the controller")
  (set spy.requests (+ spy.requests 1)))

(fn app-root-wrapper-defers-watcher-reload-until-requested-execution []
  (local module-name "__test_app_root_deferred_reload")
  (local previous-module (. package.loaded module-name))
  (local previous-log-session _G.__space_debug_log_session_started)
  (local spy {:requests 0 :unloads 0 :restores 0})
  (set (. package.loaded module-name)
       {:init (fn [] true)
        :drop (fn [] (set spy.unloads (+ spy.unloads 1)))
        :snapshot (fn [] {:marker "deferred"})
        :restore (fn [snapshot]
                   (assert (= snapshot.marker "deferred"))
                   (set spy.restores (+ spy.restores 1)))})
  (local (ok result)
    (pcall with-fake-reload-watcher
      (fn [dir state]
        (set state.controller
             (HotReload.AppRootController
               {:watch-paths [dir]
                :module-name module-name
                :debounce-ms 10
                :on-reload-requested #(record-deferred-request! spy state $1)}))
        (set state.now-ms 6000)
        (set state.events [{:path (fs.join-path dir "changed.fnl") :action "modified"}])
        (state.controller:update 0)
        (set state.now-ms 6011)
        (state.controller:update 0)
        (state.controller:update 0)
        (assert (= spy.requests 1) "Expected one deferred request per pending batch")
        (assert (= spy.unloads 0) "Watcher update must not execute reload inline")
        (assert (= (. (state.controller:debug-state) :pending-event-count) 1))
        (assert (state.controller:reload-now!))
        (assert (= spy.unloads 1))
        (assert (= spy.restores 1))
        (assert (= (. (state.controller:debug-state) :pending-event-count) 0))
        (state.controller:update 0)
        (assert (= spy.requests 1) "Successful reload must clear the pending batch")
        true)))
  (set (. package.loaded module-name) previous-module)
  (set _G.__space_debug_log_session_started previous-log-session)
  (if ok result (error result)))

(table.insert tests {:name "app root wrapper defers watcher reload until requested execution"
                     :fn app-root-wrapper-defers-watcher-reload-until-requested-execution})

(fn record-reload-phase! [calls id phase ctx]
  (assert (= ctx.target-unit.id id) "Lifecycle context must identify the executed target")
  (table.insert calls (.. id ":" phase)))

(fn counted-reload-unit [id parent-id path calls]
  (Units.Unit
    {:id id :parent-id parent-id :owned-paths [path]
     :snapshot (fn [ctx]
                 (record-reload-phase! calls id "snapshot" ctx)
                 {:unit-id id})
     :unload #(record-reload-phase! calls id "unload" $1)
     :load #(record-reload-phase! calls id "load" $1)
     :restore (fn [snapshot ctx]
                (assert (= snapshot.unit-id id) "Restore must receive the target's snapshot")
                (record-reload-phase! calls id "restore" ctx))}))

(fn check-hot-reload-eligibility [scenario dir state]
  (local calls [])
  (local root (counted-reload-unit "dev-root" nil dir calls))
  (local group-path (fs.join-path dir "group"))
  (local group (counted-reload-unit "group" "dev-root" group-path calls))
  (local a (counted-reload-unit "a" "group" (fs.join-path group-path "a") calls))
  (local b (counted-reload-unit "b" "group" (fs.join-path group-path "b") calls))
  (local other (counted-reload-unit "other" "dev-root" (fs.join-path dir "other") calls))
  (local paths {:a (fs.join-path group-path "a" "code.fnl")
                :b (fs.join-path group-path "b" "code.fnl")
                :other (fs.join-path dir "other" "code.fnl")
                :root (fs.join-path dir "root.fnl")
                :unmatched (fs.join-path (fs.parent dir) "unmatched.fnl")})
  (set state.controller
       (HotReload.HotReloadController
         {:unit root :units [group a b other] :root-unit-id "dev-root"
          :watch-paths [dir] :narrow-reload-unit-ids scenario.allowlist}))
  (local changes (icollect [_ key (ipairs scenario.changes)]
                   {:path (. paths key) :action "modified"}))
  (assert (state.controller:reload-now! {:changes changes}))
  (local expected (icollect [_ phase (ipairs ["snapshot" "unload" "load" "restore"])]
                    (.. scenario.target ":" phase)))
  (assert (= (fennel.view calls) (fennel.view expected))
          (.. "Only final target may execute: " (fennel.view calls)))
  (local debug-state (state.controller:debug-state))
  (assert (= debug-state.last-target-unit-id scenario.target) "Debug target must match execution")
  (assert (= debug-state.last-reload-change-count (length changes)))
  (assert (= debug-state.reload-count 1)))

(each [_ scenario (ipairs [{:name "omitted defaults to root" :changes [:a] :target "dev-root"}
                       {:name "empty defaults to root" :allowlist [] :changes [:a] :target "dev-root"}
                       {:name "explicit leaf" :allowlist ["a"] :changes [:a] :target "a"}
                       {:name "unlisted sibling" :allowlist ["a"] :changes [:b] :target "dev-root"}
                       {:name "unlisted other" :allowlist ["a"] :changes [:other] :target "dev-root"}
                       {:name "leaves do not certify ancestor" :allowlist ["a" "b"] :changes [:a :b] :target "dev-root"}
                       {:name "explicit common ancestor" :allowlist ["group"] :changes [:a :b] :target "group"}
                       {:name "cross branch common root" :allowlist ["a" "other"] :changes [:a :other] :target "dev-root"}
                       {:name "root owned" :allowlist ["a"] :changes [:root] :target "dev-root"}
                       {:name "unmatched" :allowlist ["a"] :changes [:unmatched] :target "dev-root"}
                       {:name "empty changes" :allowlist ["a"] :changes [] :target "dev-root"}])]
  (table.insert tests {:name (.. "hot reload eligibility " scenario.name)
                       :fn #(with-fake-reload-watcher
                              (fn [dir state] (check-hot-reload-eligibility scenario dir state)))}))

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "units"
                       :tests tests})))

{:name "units"
 :tests tests
 :main main}
