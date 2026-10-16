(local AppBootstrap (require :app-bootstrap))
(local fs (require :fs))
(local tempfile (require :tempfile))
(local FileWatch (require :file-watch))
(local runtime (require :runtime))

(fn count-searcher-occurrences [target]
  (var count 0)
  (each [_ searcher (ipairs package.searchers)]
    (when (= searcher target)
      (set count (+ count 1))))
  count)

(fn assert-root-reload-state! [deps controller control world-id DebugLog]
  (local app (deps.get-app))
  (assert (= (. (controller:debug-state) :last-target-unit-id) "app-root")
          "Default controller execution must target app root")
  (assert app.world-manager "Expected app.world-manager after reload")
  (assert (= (app.world-manager:active-world-id) world-id)
          "Expected active world id to roundtrip through full-app reload")
  (assert (string.find (fs.read-file DebugLog.log-path) "root reload marker" 1 true)
          "Expected root reload to preserve debug.log history")
  (assert (= app.hot-reload-controller controller) "Root reload must retain its controller")
  (assert (= ((. (require :live-dev-runtime) :current)) control) "Root reload must retain its coordinator")
  (assert (= app.hot-reload-callback-id nil) "Main must not acquire a duplicate reload callback")
  (assert package.__space_fennel_cache_searcher "Expected installed fennel cache searcher")
  (assert (= (count-searcher-occurrences package.__space_fennel_cache_searcher) 1)
          "Expected exactly one installed fennel cache searcher after repeated reloads"))

(fn assert-default-root-roundtrips! [deps watch-root DebugLog control filenames]
  (local app (deps.get-app))
  (local controller (assert app.hot-reload-controller "Outer owner must construct the reload controller"))
  (DebugLog.log "test" "root reload marker")
  (local created-world (app.world-manager:create-home-world {:activate? false}))
  (assert (app.world-manager:activate-world-id created-world.id))
  (each [_ filename (ipairs filenames)]
    (local old-world-manager app.world-manager)
    (assert (controller:reload-now! {:changes [{:path (fs.join-path watch-root filename)
                                               :action "modified"}]})
            "Expected default root hot reload to succeed")
    (assert (not (= app.world-manager old-world-manager)) "Default reload must reconstruct root ownership")
    (assert-root-reload-state! deps controller control created-world.id DebugLog)))

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
    (set fixture-app.hot-reload-controller nil)
    (if owned.stop-control (owned.stop-control) (controller:drop))))

(fn drop-owned-root-main! [owned loaded]
  (when owned.init-entered?
    (local Main (if loaded loaded owned.main))
    (assert (= (type Main.drop) :function) "owned Main cleanup handler missing")
    (Main.drop)))

(fn assert-manual-root-roundtrip! [deps control transport async-id DebugLog]
  (local app (deps.get-app))
  (DebugLog.log "test" "root reload marker")
  (local created-world (app.world-manager:create-home-world {:activate? false}))
  (assert (app.world-manager:activate-world-id created-world.id))
  (local controller (assert app.hot-reload-controller "outer controller missing"))
  (control:request 1 "manual")
  (deps.dispatch-control!)
  (fn forbid-watcher [_opts] (error "root init reacquired watcher"))
  (set FileWatch.FileWatcher forbid-watcher)
  (control:request 2 "reload")
  (deps.dispatch-control!)
  (local result (control:operation 2))
  (assert (= result.status "succeeded") "Expected root hot reload to succeed")
  (assert (= result.action "reload"))
  (assert (= result.rollback "not-needed"))
  (assert (= (. (control:status) :generation) 2))
  (assert (= app.remote-control transport) "root reload must retain the RC object")
  (deps.check-async-result! async-id)
  (assert (= (. (controller:debug-state) :watch?) false))
  (assert-root-reload-state! deps controller control created-world.id DebugLog))

(fn with-root-reload-fixture [deps root-cleanup-slot scenario]
  (local app (deps.get-app))
  (local owned {:original-controller app.hot-reload-controller :init-entered? false
                :stop-control deps.stop-test-control!})
  (local restorations [])
  (fn drop-controller [] (drop-owned-root-controller! app owned))
  (fn drop-main [] (drop-owned-root-main! owned (. package.loaded "main")))
  (fn drop-temp [] (when owned.temp (owned.temp:drop)))
  (fn cleanup []
    (local stages [["Main.drop" drop-main] ["control" drop-controller]
                  ["themes" AppBootstrap.init-themes] ["lights" AppBootstrap.init-lights]
                  ["input" AppBootstrap.init-input-systems]])
    (each [_ restore (ipairs restorations)] (table.insert stages restore))
    (table.insert stages ["temp" drop-temp])
    (run-cleanup-stages! stages))
  (set root-cleanup-slot.cleanup cleanup)
  (set owned.temp (tempfile.TemporaryDirectory {:prefix "units-test-"}))
  (set owned.main (deps.require-main!))
  (local DebugLog (require :debug-log))
  (each [_ key (ipairs [:renderers :hot-reload-config :hot-reload-controller :worlds-dir
                       :remote-control :remote-control-endpoint])]
    (table.insert restorations (field-restoration app key)))
  (table.insert restorations (field-restoration FileWatch :FileWatcher))
  (local watch-root (fs.join-path runtime.assets-path "lua"))
  (local endpoint (.. "ipc://" (fs.join-path owned.temp.path "control.sock")))
  (set app.hot-reload-controller nil)
  (set app.hot-reload-config (deps.test-hot-reload-config watch-root nil))
  ((. owned.main :install-app-shell!))
  (local control (deps.start-test-control! endpoint))
  (local transport app.remote-control)
  (local async-id (_G.remote_control.create))
  (set owned.init-entered? true)
  ((. owned.main :init))
  (control:mark-ready!)
  (if (= scenario "manual")
      (assert-manual-root-roundtrip! deps control transport async-id DebugLog)
      (assert-default-root-roundtrips! deps watch-root DebugLog control scenario))
  true)

(fn runner-timeout-metadata-precedence-and-validation [runner]
  (local select runner.select-test-timeout-seconds)
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
  (fn drop-controller [] (drop-owned-root-controller! fixture-app owned))
  (fn drop-main [] (drop-owned-root-main! owned nil))
  (fn cleanup []
    (run-cleanup-stages! [["controller" drop-controller] ["Main" drop-main]]))
  (local slot {:cleanup cleanup})
  (assert (not (pcall drain-cleanup-slot! slot))) (drain-cleanup-slot! slot)
  (assert (and (= root-drops 1) (= main-drops 1) (= outside-drops 0) (= fixture-app.hot-reload-controller nil))
          "consume slot/controller before throwing drop; still attempt Main once"))

(fn runner-case-teardown-restores-hook-and-preserves-errors [runner]
  (assert-root-cleanup-ownership!)
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

(fn runner-saved-engine-scope-attempts-shutdown-once [runner]
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
    (fn forbid-mutable-engine [_self] (error "must not use mutable app engine"))
    (fn success [] true)
    (fn body []
      (table.insert events :body)
      (set fake-app.engine {:shutdown forbid-mutable-engine})
      (when (= mode :module-error) (set fake-app.engine nil))
      (when (= mode :drop-error)
        (local (ok err) (runner.run-case {:name "owned app drop" :fn success :teardown app-drop} 0 nil))
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

(fn create [deps]
  (assert (= (type deps.get-app) :function) "root support requires late-bound get-app")
  (assert deps.runner "root support requires the existing test runner")
  (local root-cleanup-slot {})
  (fn run-fixture [scenario] (with-root-reload-fixture deps root-cleanup-slot scenario))
  (fn teardown [] (drain-cleanup-slot! root-cleanup-slot))
  (fn timeout-metadata [] (runner-timeout-metadata-precedence-and-validation deps.runner))
  (fn case-teardown [] (runner-case-teardown-restores-hook-and-preserves-errors deps.runner))
  (fn saved-engine [] (runner-saved-engine-scope-attempts-shutdown-once deps.runner))
  {:with-root-reload-fixture run-fixture
   :teardown-root-fixture teardown
   :runner-timeout-metadata-precedence-and-validation timeout-metadata
   :runner-case-teardown-restores-hook-and-preserves-errors case-teardown
   :runner-saved-engine-scope-attempts-shutdown-once saved-engine})

{:create create}
