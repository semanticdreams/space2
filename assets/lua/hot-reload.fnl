(local fs (require :fs))
(local fennel (require :fennel))
(local fennel-cache (require :fennel-cache))
(local logging (require :logging))
(local FileWatch (require :file-watch))
(local Units (require :units))
(local path-utils (require :path-utils))
(local path-separator? path-utils.path-separator?)

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn normalize-root [path]
  (assert (= (type path) :string) "HotReload watch path must be a string")
  (fs.absolute path))

(fn normalize-path [path]
  (if (= (type path) :string)
      (fs.absolute path)
      nil))

(fn clone-list [items]
  (icollect [_ item (ipairs (or items []))]
    item))

(fn path-under-root? [path root]
  (and path root
       (= (string.sub path 1 (# root)) root)
       (or (= (# path) (# root))
           (path-separator? (string.sub path (+ (# root) 1) (+ (# root) 1))))))

(fn path-under-any-root? [path roots]
  (var matched false)
  (each [_ root (ipairs roots) &until matched]
    (when (path-under-root? path root)
      (set matched true)))
  matched)

(fn normalize-owned-paths [paths]
  (icollect [_ path (ipairs (or paths []))]
    (normalize-root path)))

(fn unit-owned-paths [unit watch-paths]
  (local owned (normalize-owned-paths (and unit unit.owned-paths)))
  (if (> (length owned) 0)
      owned
      watch-paths))

(fn append-unique-unit! [units unit]
  (when unit
    (var present? false)
    (each [_ existing (ipairs units) &until present?]
      (when (= existing unit)
        (set present? true)))
    (when (not present?)
      (table.insert units unit)))
  units)

(fn collect-live-units [root-unit options]
  (local units [])
  (append-unique-unit! units root-unit)
  (each [_ unit (ipairs (or options.units []))]
    (append-unique-unit! units unit))
  (local units-fn options.units-fn)
  (when units-fn
    (each [_ unit (ipairs (or (units-fn root-unit) []))]
      (append-unique-unit! units unit)))
  units)

(fn unit-id-map [units]
  (local out {})
  (each [_ unit (ipairs units)]
    (when (and unit unit.id)
      (set (. out unit.id) unit)))
  out)

(fn find-root-unit [units options]
  (local by-id (unit-id-map units))
  (or (and options.root-unit-id (. by-id options.root-unit-id))
      (and options.unit-id (. by-id options.unit-id))
      (. by-id "app-root")
      (. units 1)))

(fn unit-match-length [unit path watch-paths]
  (var best-length nil)
  (each [_ root (ipairs (unit-owned-paths unit watch-paths))]
    (when (path-under-root? path root)
      (if (or (not best-length)
              (> (# root) best-length))
          (set best-length (# root)))))
  best-length)

(fn lineage-to-root [unit units-by-id]
  (local lineage [])
  (var current unit)
  (while current
    (table.insert lineage current)
    (set current (and current.parent-id
                      (. units-by-id current.parent-id))))
  lineage)

(fn resolve-common-ancestor [units units-by-id root-unit]
  (local first-unit (. units 1))
  (if (or (not first-unit)
          (= (length units) 0))
      root-unit
      (do
        (local first-lineage (lineage-to-root first-unit units-by-id))
        (var resolved nil)
        (each [_ candidate (ipairs first-lineage) &until resolved]
          (var shared? true)
          (each [_ unit (ipairs units) &until (not shared?)]
            (local lineage (lineage-to-root unit units-by-id))
            (var contains? false)
            (each [_ member (ipairs lineage) &until contains?]
              (when (= member candidate)
                (set contains? true)))
            (when (not contains?)
              (set shared? false)))
          (when shared?
            (set resolved candidate)))
        (or resolved root-unit))))

(fn resolve-target-unit [changes units watch-paths options]
  (local root-unit (find-root-unit units options))
  (local units-by-id (unit-id-map units))
  (local matched-units [])
  (local matched-ids {})
  (each [_ change (ipairs changes)]
    (local path (normalize-path (and change change.path)))
    (var best-unit nil)
    (var best-length nil)
    (each [_ unit (ipairs units)]
      (local match-length (and path (unit-match-length unit path watch-paths)))
      (when (and match-length
                 (or (not best-length)
                     (> match-length best-length)))
        (set best-length match-length)
        (set best-unit unit)))
    (when (and best-unit
               (not (. matched-ids best-unit.id)))
      (set (. matched-ids best-unit.id) true)
      (table.insert matched-units best-unit)))
  (if (= (length matched-units) 0)
      root-unit
      (if (= (length matched-units) 1)
          (. matched-units 1)
          (resolve-common-ancestor matched-units units-by-id root-unit))))

(fn allowed-extension? [path]
  (or (string.match (or path "") "%.fnl$")
      (string.match (or path "") "%.lua$")))

(fn file-stamp [path]
  (when path
    (local info (and fs.stat (fs.stat path)))
    (when (and info info.exists)
      {:modified info.modified
       :size info.size
       :type info.type})))

(fn capture-startup-file-stamps [roots]
  (local stamps {})
  (fn walk [path]
    (local info (and fs.stat (fs.stat path)))
    (when (and info info.exists)
      (if (= info.type "directory")
          (each [_ entry (ipairs (or (and fs.list-dir (fs.list-dir path true)) []))]
            (walk entry.path))
          (when (and (= info.type "file")
                     (allowed-extension? path))
            (set (. stamps path)
                 {:modified info.modified
                  :size info.size
                  :type info.type})))))
  (each [_ root (ipairs roots)]
    (walk root))
  stamps)

(fn reloadable-action? [action]
  (not (or (= action "add")
           (= action "created")
           (= action "unknown"))))

(fn startup-noise-event? [event startup-stamps]
  (local action (and event event.action))
  (if (or (= action "delete")
          (= action "moved-from"))
      false
      (do
        (local path (and event event.path))
        (local baseline (. startup-stamps path))
        (local current (file-stamp path))
        (and baseline current
             (= baseline.modified current.modified)
             (= baseline.size current.size)
             (= baseline.type current.type)))))

(fn module-source-path [module-name]
  (or (and fennel fennel.search-module
           (fennel.search-module module-name))
      (and package package.searchpath package.path
           (package.searchpath module-name package.path))))

(fn ensure-module-source-path-registry []
  (when (not package.__hot_reload_module_source_paths)
    (set package.__hot_reload_module_source_paths {}))
  package.__hot_reload_module_source_paths)

(fn remember-module-source-path! [module-name]
  (local registry (ensure-module-source-path-registry))
  (local path (normalize-path (module-source-path module-name)))
  (when path
    (set (. registry module-name) path))
  path)

(fn ensure-module-source-tracker! []
  (local registry (ensure-module-source-path-registry))
  (when (not package.__hot_reload_require_wrapped?)
    (local original-require require)
    (set package.__hot_reload_require_wrapped? true)
    (set package.__hot_reload_original_require original-require)
    (set _G.require
         (fn [module-name]
           (local result (original-require module-name))
           (remember-module-source-path! module-name)
           result)))
  registry)

(fn capture-known-module-paths []
  (local known (ensure-module-source-tracker!))
  (each [module-name value (pairs package.loaded)]
    (when value
      (local path (remember-module-source-path! module-name))
      (when path
        (set (. known module-name) path))))
  known)

(fn normalize-event [event]
  (local path (normalize-path (and event event.path)))
  (if (not path)
      nil
      {:action (or (and event event.action) "unknown")
       :path path
       :old-path (normalize-path (and event event.old-path))
       :filename (and event event.filename)
       :dir (and event event.dir)
       :watch-id (and event event.watch-id)
       :missed (and event event.missed)}))

(fn clear-loaded-modules! [module-names]
  (each [_ module-name (ipairs module-names)]
    (set (. package.loaded module-name) nil))
  true)

(fn capture-loaded-modules [module-names]
  (local backup {})
  (each [_ module-name (ipairs module-names)]
    (set (. backup module-name) (. package.loaded module-name)))
  backup)

(fn restore-loaded-modules! [backup]
  (each [module-name value (pairs backup)]
    (set (. package.loaded module-name) value))
  true)

(fn collect-owned-loaded-modules [roots preserve known-module-paths]
  (local module-names [])
  (each [module-name value (pairs package.loaded)]
    (when (and (not (. preserve module-name))
               value)
      (var path (normalize-path (module-source-path module-name)))
      (when path
        (set (. known-module-paths module-name) path))
      (when (not path)
        (set path (. known-module-paths module-name)))
      (when (path-under-any-root? path roots)
        (table.insert module-names module-name))))
  (table.sort module-names)
  module-names)

(fn now-ms []
  (assert (and app app.engine app.engine.now-ms)
          "HotReload requires app.engine:now-ms")
  (app.engine:now-ms))

(fn select-eligible-target-unit [candidate root-unit narrow-unit-ids]
  (var eligible? (= candidate root-unit))
  (each [_ id (ipairs narrow-unit-ids) &until eligible?]
    (when (= id candidate.id)
      (set eligible? true)))
  (if eligible? candidate root-unit))

(fn HotReloadController [opts]
  (local options (or opts {}))
  (local narrow-unit-ids (or options.narrow-reload-unit-ids []))
  (local watch-paths
    (icollect [_ path (ipairs (or options.watch-paths []))]
      (normalize-root path)))
  (assert (> (length watch-paths) 0)
          "HotReloadController requires at least one :watch-path")
  (local preserve-modules {})
  (each [_ module-name (ipairs (or options.preserve-modules []))]
    (set (. preserve-modules module-name) true))
  (local unit (assert options.unit "HotReloadController requires :unit"))
  (assert (= (type unit.id) :string) "HotReloadController requires string unit.id")
  (local fallback-target-id (or options.root-unit-id options.unit-id unit.id))
  (assert (= (type fallback-target-id) :string) "HotReloadController requires string root unit id")
  (assert (or (= options.watch? nil) (= (type options.watch?) :boolean))
          "HotReloadController :watch? must be a boolean")
  (var watch? (not (= options.watch? false)))
  (local debounce-ms (or options.debounce-ms 150))
  (local startup-ignore-ms (or options.startup-ignore-ms 5000))
  (local on-reload-requested options.on-reload-requested)
  (assert (and (= (type debounce-ms) :number) (>= debounce-ms 0))
          "HotReloadController :debounce-ms must be nonnegative")
  (assert (and (= (type startup-ignore-ms) :number) (>= startup-ignore-ms 0))
          "HotReloadController :startup-ignore-ms must be nonnegative")
  (assert (or (= on-reload-requested nil) (= (type on-reload-requested) :function))
          "HotReloadController :on-reload-requested must be a function")
  (assert (or (= options.units-fn nil) (= (type options.units-fn) :function))
          "HotReloadController :units-fn must be a function")
  (local startup-stamps (if watch? (capture-startup-file-stamps watch-paths) {}))
  (local known-module-paths (capture-known-module-paths))
  (var pending-events [])
  (var pending-deadline-ms nil)
  (var reload-scheduled? false)
  (var dropped? false)
  (var reload-count 0)
  (var update-count 0)
  (var last-polled-event-count 0)
  (var last-matched-event-count 0)
  (var last-reload-change-count 0)
  (var last-reload-module-count 0)
  (var last-target-unit-id unit.id)
  (local started-at-ms (now-ms))
  (var watcher nil)
  (when watch?
    (set watcher (FileWatch.FileWatcher {:generic? (or options.generic? false)}))
    (fn start-watching []
      (each [_ path (ipairs watch-paths)]
        (watcher:add-watch path true))
      (watcher:start))
    (local (ok err) (pcall start-watching))
    (when (not ok)
      (watcher:drop)
      (error err)))

  (fn live-units []
    (collect-live-units unit options))

  (logging.info (string.format
                  "[hot-reload] controller %s roots=%s debounce=%dms"
                  unit.id
                  (table.concat watch-paths ", ")
                  debounce-ms))

  (fn queue-event! [event]
    (table.insert pending-events event)
    (set pending-deadline-ms (+ (now-ms) debounce-ms))
    true)

  (fn collect-pending-fs-events! []
    (local events (watcher:poll))
    (set last-polled-event-count 0)
    (set last-matched-event-count 0)
    (each [_ raw (ipairs events)]
      (local event (normalize-event raw))
      (when event
        (set last-polled-event-count (+ last-polled-event-count 1))
        (when (and (>= (- (now-ms) started-at-ms) startup-ignore-ms)
                   (reloadable-action? event.action)
                   (allowed-extension? event.path)
                   (path-under-any-root? event.path watch-paths)
                   (not (startup-noise-event? event startup-stamps)))
          (queue-event! event)
          (set last-matched-event-count (+ last-matched-event-count 1))
          (when (and event.old-path
                     (allowed-extension? event.old-path)
                     (path-under-any-root? event.old-path watch-paths))
            (local moved-event {:action "moved-from"
                                :path event.old-path
                                :old-path event.path})
            (queue-event! moved-event)
            (set last-matched-event-count (+ last-matched-event-count 1))))))
    pending-events)

  (fn rollback! [target-unit module-names backup snapshot failed-target-loaded?]
    (when failed-target-loaded?
      (target-unit:unload {:reload-phase "rollback-unload-failed"}))
    (clear-loaded-modules! module-names)
    (restore-loaded-modules! backup)
    (target-unit:load {:reload-phase "rollback"})
    (target-unit:restore snapshot {:reload-phase "rollback"})
    (Units.refresh-graph-extensions-for-unit! target-unit.id)
    true)

  (fn handle-reload-failure [transaction result err]
    (local target-unit transaction.target-unit)
    (set result.ok false)
    (set result.error (tostring err))
    (logging.error (string.format "[hot-reload] reload failed for %s: %s"
                                  result.target-unit-id result.error))
    (when transaction.mutated?
      (local (rollback-ok rollback-err)
        (pcall rollback! target-unit transaction.module-names transaction.backup
               transaction.snapshot transaction.target-loaded?))
      (set result.rollback (if rollback-ok "restored" "failed"))
      (if rollback-ok
          (logging.warn (string.format
                          "[hot-reload] rollback restored previous runtime for %s"
                          target-unit.id))
          (set result.rollback-error (tostring rollback-err))))
    result)

  (fn prepare-reload! [transaction result changes root?]
    (local units (live-units))
    (local root-unit (or (find-root-unit units options) unit))
    (local candidate (if root? root-unit
                         (or (resolve-target-unit changes units watch-paths options) root-unit)))
    (local target-unit
      (assert (if root? root-unit
                  (select-eligible-target-unit candidate root-unit narrow-unit-ids))
              "HotReloadController could not select a target unit"))
    (set transaction.target-unit target-unit)
    (set result.target-unit-id target-unit.id)
    (set last-target-unit-id target-unit.id)
    (set result.phase "collect-modules")
    (local module-roots (unit-owned-paths target-unit watch-paths))
    (local module-names (collect-owned-loaded-modules module-roots preserve-modules known-module-paths))
    (set transaction.module-names module-names)
    (set transaction.backup (capture-loaded-modules module-names))
    (logging.info (string.format
                    "[hot-reload] begin target=%s changes=%d"
                    target-unit.id
                    (length changes)))
    (set last-reload-change-count (length changes))
    (set last-reload-module-count (length module-names))
    (local reload-ctx {:changes changes
                       :module-names module-names
                       :target-unit target-unit})
    (set transaction.ctx reload-ctx)
    (set result.phase "snapshot")
    (logging.info (string.format
                    "[hot-reload] snapshot target=%s"
                    target-unit.id))
    (set transaction.snapshot (target-unit:snapshot reload-ctx))
    (when app
      (set app.__hot-reload-ctx reload-ctx)))

  (fn reload-target! [transaction result]
    (local target-unit transaction.target-unit)
    (local module-names transaction.module-names)
    (local reload-ctx transaction.ctx)
    (set result.phase "unload")
    (set transaction.mutated? true)
    (logging.info (string.format "[hot-reload] unload target=%s" target-unit.id))
    (target-unit:unload reload-ctx)
    (set result.phase "clear-modules")
    (logging.info (string.format "[hot-reload] clear-modules target=%s count=%d names=%s"
                                target-unit.id (length module-names) (table.concat module-names ", ")))
    (clear-loaded-modules! module-names)
    (each [_ module-name (ipairs module-names)]
      (local source-path (. known-module-paths module-name))
      (when source-path
        (fennel-cache.clear-fennel-module-cache! module-name source-path)))
    (set result.phase "load")
    (logging.info (string.format "[hot-reload] load target=%s" target-unit.id))
    (when (= target-unit.id "app-root")
      (set _G.__space_debug_log_session_started true))
    (target-unit:load reload-ctx)
    (set transaction.target-loaded? true)
    (set result.phase "restore")
    (logging.info (string.format "[hot-reload] restore target=%s" target-unit.id))
    (target-unit:restore transaction.snapshot reload-ctx)
    (set result.phase "refresh-extensions")
    (Units.refresh-graph-extensions-for-unit! target-unit.id))

  (fn perform-reload! [changes root?]
    (local result {:ok false
                   :target-unit-id fallback-target-id
                   :phase "target-selection" :rollback "not-needed"})
    (local transaction {})
    (local previous-reload-ctx (and app app.__hot-reload-ctx))
    (fn run-transaction []
      (prepare-reload! transaction result changes root?)
      (reload-target! transaction result))
    (local (ok err) (pcall run-transaction))
    (if ok
        (do
          (set pending-events [])
          (set pending-deadline-ms nil)
          (set reload-count (+ reload-count 1))
          (set result.ok true)
          (set result.phase "complete")
          (logging.info (string.format
                          "[hot-reload] reloaded %s modules=%d changes=%d total=%d"
                          result.target-unit-id
                          (length transaction.module-names)
                          (length changes)
                          reload-count)))
        (handle-reload-failure transaction result err))
    (when app
      (set app.__hot-reload-ctx previous-reload-ctx))
    result)

  (fn legacy-result [result]
    (if result.ok true
        (= result.rollback "failed")
        (error (.. result.error " rollback=" result.rollback-error))
        false))

  (fn reload-now! [_self opts]
    (assert (not dropped?) "HotReloadController.reload-now! called after drop")
    (set reload-scheduled? false)
    (local options-arg (or opts {}))
    (local changes (clone-table (or options-arg.changes pending-events)))
    (legacy-result (perform-reload! changes false)))

  (fn reload-root! [_self]
    (assert (not dropped?) "HotReloadController.reload-root! called after drop")
    (set reload-scheduled? false)
    (perform-reload! (clone-table pending-events) true))

  (fn reload-pending! [_self]
    (assert (not dropped?) "HotReloadController.reload-pending! called after drop")
    (set reload-scheduled? false)
    (perform-reload! (clone-table pending-events) false))

  (fn use-manual! [_self]
    (assert (not dropped?) "HotReloadController.use-manual! called after drop")
    (when watcher
      (watcher:drop)
      (set watcher nil))
    (set watch? false)
    (set pending-events [])
    (set pending-deadline-ms nil)
    (set reload-scheduled? false)
    true)

  (fn update [self _delta]
    (assert (not dropped?) "HotReloadController.update called after drop")
    (set update-count (+ update-count 1))
    (when watcher
      (collect-pending-fs-events!))
    (if (and pending-deadline-ms
             (> (length pending-events) 0)
             (>= (now-ms) pending-deadline-ms))
        (if on-reload-requested
            (do
              (when (not reload-scheduled?)
                (set reload-scheduled? true)
                (on-reload-requested self))
              true)
            (reload-now! self {:changes pending-events}))
        false))

  (fn debug-state [_self]
    {:watch? watch?
     :watch-paths (clone-table watch-paths)
     :watch-directories (if watcher (clone-table (watcher:directories)) [])
     :debounce-ms debounce-ms
     :startup-ignore-ms startup-ignore-ms
     :now-ms (now-ms)
     :reload-count reload-count
     :update-count update-count
     :unit-ids (icollect [_ live-unit (ipairs (live-units))]
                  live-unit.id)
     :pending-event-count (length pending-events)
     :pending-deadline-ms pending-deadline-ms
     :polled-event-count last-polled-event-count
     :matched-event-count last-matched-event-count
     :last-reload-change-count last-reload-change-count
     :last-reload-module-count last-reload-module-count
     :last-target-unit-id last-target-unit-id})

  (fn drop [_self]
    (when (not dropped?)
      (set dropped? true)
      (when watcher
        (watcher:drop)
        (set watcher nil))
      (set pending-events [])
      (set pending-deadline-ms nil)
      (set reload-scheduled? false))
    true)

  {:unit unit
   :watch-paths watch-paths
   :preserve-modules preserve-modules
   :debounce-ms debounce-ms
   :reload-count (fn [_self] reload-count)
   :debug-state debug-state
   :reload-now! reload-now!
   :reload-root! reload-root!
   :reload-pending! reload-pending!
   :use-manual! use-manual!
   :update update
   :drop drop})

(fn AppRootController [opts]
  (local options (or opts {}))
  (local default-preserve ["hot-reload" "units"])
  (local unit
    (Units.ModuleUnit
      {:id "app-root"
       :owned-paths (or options.owned-paths
                        options.watch-paths)
       :module-name (or options.module-name "main")
       :suppress-run-main? true
       :load-export (or options.load-export "init")
       :unload-export (or options.unload-export "drop")
       :snapshot-export (or options.snapshot-export "snapshot")
       :restore-export (or options.restore-export "restore")}))
  (fn all-units [root-unit]
    (local units [])
    (append-unique-unit! units root-unit)
    (each [_ extra-unit (ipairs (or options.units []))]
      (append-unique-unit! units extra-unit))
    (when options.units-fn
      (each [_ extra-unit (ipairs (or (options.units-fn root-unit) []))]
        (append-unique-unit! units extra-unit)))
    units)
  (HotReloadController
    {:unit unit
     :units-fn all-units
     :root-unit-id unit.id
     :narrow-reload-unit-ids options.narrow-reload-unit-ids
     :watch-paths (or options.watch-paths [])
     :preserve-modules (or options.preserve-modules default-preserve)
     :debounce-ms (or options.debounce-ms 150)
     :watch? options.watch?
     :startup-ignore-ms options.startup-ignore-ms
     :on-reload-requested options.on-reload-requested
     :generic? (or options.generic? false)}))

{:HotReloadController HotReloadController
 :AppRootController AppRootController}
