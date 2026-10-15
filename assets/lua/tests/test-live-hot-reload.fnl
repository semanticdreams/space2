(local callbacks (require :callbacks))
(local fs (require :fs))
(local json (require :json))
(local process (require :process))
(local sysinfo (require :sysinfo))
(local tempfile (require :tempfile))

(local tests [])

(local platform-os (. (sysinfo.platform) :os))
(local is-windows (= platform-os "windows"))

(fn executable-name []
  (if is-windows "build/space.exe" "./build/space"))

(fn wait-until [predicate opts]
  (local options (or opts {}))
  (callbacks.run-loop {:poll-jobs true
                       :poll-http false
                       :poll-process true
                       :sleep-ms (or options.sleep-ms 20)
                       :timeout-ms (or options.timeout-ms 10000)
                       :until predicate}))

(fn sleep-ms [duration-ms]
  (local start (os.clock))
  (wait-until (fn []
                (>= (* (- (os.clock) start) 1000.0) duration-ms))
              {:sleep-ms 20
               :timeout-ms (+ duration-ms 1000)}))

(fn cleanup-dir! [path]
  (var last-err nil)
  (if (not (fs.exists path))
      true
      (do
        (local removed?
          (wait-until
            (fn []
              (local (ok err)
                (pcall
                  (fn []
                    (when (fs.exists path)
                      (fs.remove-all path)))))
              (if ok
                  true
                  (do
                    (set last-err err)
                    false)))
            {:sleep-ms 50
             :timeout-ms 2000}))
        (if removed?
            true
            (error (or last-err (.. "failed to clean up " path)))))))

(fn with-temp-dir [f]
  (local handle (tempfile.TemporaryDirectory {:prefix "live-hot-reload-"}))
  (local path handle.path)
  (local (ok result) (pcall f path))
  (local keep-dir?
    (or (= (os.getenv "SPACE_KEEP_LIVE_HOT_RELOAD_DIR") "1")
        (not ok)))
  (if keep-dir?
      (if ok
          result
          (error (.. result "\nPreserved live hot reload temp dir: " path)))
      (do
        (local (cleanup-ok cleanup-err) (pcall cleanup-dir! path))
        (if ok
            (if cleanup-ok
                result
            (error cleanup-err))
            (error result)))))

(fn keep-live-child-on-failure? []
  (= (os.getenv "SPACE_KEEP_LIVE_HOT_RELOAD_CHILD") "1"))

(fn trim-trailing-newline [text]
  (string.gsub (or text "") "[\r\n]+$" ""))

(fn make-remote-endpoint [root]
  (.. "ipc://" (fs.join-path root "space-live-hot-reload.sock")))

(fn xvfb-run-available? []
  (local result
    (process.run
      {:args ["xvfb-run" "--help"]
       :cwd "."
       :env {:PATH (or (os.getenv "PATH") "")}
       :timeout 1}))
  (and (not (= result.exit-code nil))
       (not (string.find (or result.stderr "") "failed to exec" 1 true))))

(fn make-runtime-env [opts]
  (local options (or opts {}))
  (local root (assert options.xdg-data-home "xdg-data-home required"))
  (local runtime-dir (fs.join-path root "runtime"))
  (local created (process.run {:args ["mkdir" "-m" "700" "--" runtime-dir]
                               :cwd "." :env {:PATH (or (os.getenv "PATH") "")} :timeout 2}))
  (assert (= created.exit-code 0) "could not create private watcher fixture runtime directory")
  {:PATH (or (os.getenv "PATH") "")
   :HOME root
   :XDG_CONFIG_HOME (fs.join-path root "config")
   :XDG_CACHE_HOME (fs.join-path root "cache")
   :XDG_STATE_HOME (fs.join-path root "state")
   :XDG_RUNTIME_DIR runtime-dir
   :XDG_CONFIG_DIRS (fs.join-path root "site-config")
   :XDG_DATA_DIRS (fs.join-path root "site-data")
   :SPACE_ASSETS_PATH (assert options.assets-path "assets-path required")
   :SPACE_DISABLE_AUDIO "1"
   :SDL_VIDEODRIVER "x11"
   :SPACE_HOT_RELOAD "1"
   :SPACE_HOT_RELOAD_WATCH_PATH (assert options.watch-path "watch-path required")
   :SPACE_LOG_DIR (assert options.log-dir "log-dir required")
   :FENNEL_PATH (assert options.fennel-path "fennel-path required")
   :FENNEL_MACRO_PATH (assert options.fennel-macro-path "fennel-macro-path required")
   :XDG_DATA_HOME (assert options.xdg-data-home "xdg-data-home required")
   :SKIP_KEYRING_TESTS "1"})

(fn spawn-live-app [opts]
  (local options (or opts {}))
  (process.spawn
    {:args ["xvfb-run"
            "-a"
            "-s"
            "-screen 0 1280x720x24"
            (executable-name)
            "-m"
            "main"
            (.. "--remote-control=" options.endpoint)]
     :cwd "."
     :env (make-runtime-env options)}))

(fn isolate-reporting-before-main! [main-path]
  (local source (fs.read-file main-path))
  (local first "(global app (or app {}))")
  (assert (= (string.sub source 1 (# first)) first) "fixture requires main's app global first")
  (fs.write-file main-path
                 (.. first "\n(require :tests.live-dev-offline)\n"
                     (string.sub source (+ (# first) 1)))))

(fn remote-eval [endpoint code opts]
  (local options (or opts {}))
  (process.run
    {:args [(executable-name)
            "-m"
            "tools.remote-control-client:main"
            "--"
            "--endpoint"
            endpoint
            "--timeout-ms"
            (tostring (or options.timeout-ms 500))
            "-c"
            code]
     :cwd "."
     :env {:PATH (or (os.getenv "PATH") "")
           :SPACE_ASSETS_PATH (assert (os.getenv "SPACE_ASSETS_PATH") "SPACE_ASSETS_PATH required")
           :SPACE_DISABLE_AUDIO "1"
           :FENNEL_PATH (assert (os.getenv "FENNEL_PATH") "FENNEL_PATH required")
           :FENNEL_MACRO_PATH (assert (os.getenv "FENNEL_MACRO_PATH") "FENNEL_MACRO_PATH required")}
     :timeout (or options.process-timeout 2)}))

(fn wait-for-remote [endpoint child-id]
  (var last-result nil)
  (local ready?
    (wait-until
      (fn []
        (when (and child-id (not (process.running child-id)))
          (local child-result (process.wait child-id))
          (error
            (.. "live app exited before remote control became ready"
                " stdout=" (tostring child-result.stdout)
                " stderr=" (tostring child-result.stderr)
                " signal=" (tostring child-result.signal)
                " timed-out=" (tostring (. child-result "timed-out")))))
        (set last-result
             (remote-eval endpoint "(do \"ready\")" {:timeout-ms 1500
                                                     :process-timeout 4}))
        (= (and last-result.stdout
                (trim-trailing-newline last-result.stdout))
           "ok ready"))
      {:timeout-ms 60000}))
  (assert ready?
          (.. "live app remote control did not become ready"
              " last-stdout=" (tostring (and last-result last-result.stdout))
              " last-stderr=" (tostring (and last-result last-result.stderr)))))

(fn extract-ok-payload [result]
  (assert (= result.exit-code 0)
          (.. "remote-control command failed stdout=" (tostring result.stdout)
              " stderr=" (tostring result.stderr)
              " signal=" (tostring result.signal)
              " timed-out=" (tostring (. result "timed-out"))))
  (local text (trim-trailing-newline result.stdout))
  (assert (= (string.sub text 1 3) "ok ")
          (.. "remote-control expected ok reply, got: " text))
  (string.sub text 4))

(fn wait-for-default-world-id! [xdg-data-home]
  (local index-path (fs.join-path xdg-data-home "space" "worlds" "index.json"))
  (var resolved nil)
  (assert
    (wait-until
      (fn []
        (if (not (fs.exists index-path))
            false
            (do
              (local decoded (json.loads (fs.read-file index-path)))
              (local worlds (or decoded.worlds []))
              (local first-world (. worlds 1))
              (set resolved (and first-world first-world.id))
              (and resolved (> (# resolved) 0)))))
      {:sleep-ms 100
       :timeout-ms 10000})
    (.. "expected default world id in " index-path))
  resolved)

(fn query-reload-status [endpoint]
  (local result
    (remote-eval endpoint
                 "(do
                    (local debug
                      (if (and app.hot-reload-controller app.hot-reload-controller.debug-state)
                          (app.hot-reload-controller:debug-state)
                          {}))
                    (local count (or debug.reload-count -1))
                    (local pending (or debug.pending-event-count -1))
                    (local polled (or debug.polled-event-count -1))
                    (local matched (or debug.matched-event-count -1))
                    (local updates (or debug.update-count -1))
                    (local current-now (or debug.now-ms -1))
                    (local deadline (or debug.pending-deadline-ms -1))
                    (local snapshot-state
                      (if app.snapshot-app-state
                          (app.snapshot-app-state)
                          {}))
                    (local snapshot-world-id
                      (or (. snapshot-state \"active-world-id\") \"\"))
                    (.. count \"|\" pending \"|\" polled \"|\" matched \"|\" updates \"|\" current-now \"|\" deadline \"|\" snapshot-world-id))"
                 {:timeout-ms 8000
                  :process-timeout 10}))
  (if (= result.exit-code 0)
      (extract-ok-payload result)
      nil))

(fn remote-ready-result [endpoint]
  (remote-eval endpoint "(do \"alive\")" {:timeout-ms 1500
                                           :process-timeout 4}))

(fn query-active-world-snapshot [endpoint]
  (local result
    (remote-eval endpoint
                 "(do
                    (local snapshot-state
                      (if app.snapshot-app-state
                          (app.snapshot-app-state)
                          {}))
                    (or (. snapshot-state \"active-world-id\") \"\"))"
                 {:timeout-ms 3000
                  :process-timeout 4}))
  result)

(fn split-status [payload]
  (local parts [])
  (var start 1)
  (while (<= start (# payload))
    (local separator (string.find payload "|" start true))
    (if separator
        (do
          (table.insert parts (string.sub payload start (- separator 1)))
          (set start (+ separator 1)))
        (do
          (table.insert parts (string.sub payload start))
          (set start (+ (# payload) 1)))))
  (assert (>= (length parts) 8) (.. "expected 8 hot reload status fields in " payload))
  {:count (tonumber (. parts 1))
   :pending-event-count (tonumber (. parts 2))
   :polled-event-count (tonumber (. parts 3))
   :matched-event-count (tonumber (. parts 4))
   :update-count (tonumber (. parts 5))
   :now-ms (tonumber (. parts 6))
   :pending-deadline-ms (tonumber (. parts 7))
   :snapshot-world-id (. parts 8)})

(fn wait-for-reload [endpoint child-id expected-world-id]
  (var latest nil)
  (var latest-child-read nil)
  (var latest-ready-result nil)
  (var latest-snapshot-result nil)
  (assert
    (wait-until
      (fn []
        (when (and child-id (not (process.running child-id)))
          (local child-result (process.wait child-id))
          (error
            (.. "live app exited while waiting for reload"
                " stdout=" (tostring child-result.stdout)
                " stderr=" (tostring child-result.stderr)
                " signal=" (tostring child-result.signal)
                " timed-out=" (tostring (. child-result "timed-out")))))
        (when child-id
          (set latest-child-read (process.read child-id)))
        (local payload (query-reload-status endpoint))
        (if payload
            (do
              (local status (split-status payload))
              (set latest status)
              (and status.count
                   (>= status.count 1)
                   (= status.snapshot-world-id expected-world-id)))
            (do
              (set latest-ready-result (remote-ready-result endpoint))
              (set latest-snapshot-result (query-active-world-snapshot endpoint))
              false)))
      {:sleep-ms 250
       :timeout-ms 30000})
    (.. "expected live hot reload to restore active world "
        expected-world-id
        ", latest-count="
        (tostring (and latest latest.count))
        ", latest-pending="
        (tostring (and latest latest.pending-event-count))
        ", latest-polled="
        (tostring (and latest latest.polled-event-count))
        ", latest-matched="
        (tostring (and latest latest.matched-event-count))
        ", latest-updates="
        (tostring (and latest latest.update-count))
        ", latest-now-ms="
        (tostring (and latest latest.now-ms))
        ", latest-pending-deadline-ms="
        (tostring (and latest latest.pending-deadline-ms))
        ", latest-snapshot-world-id="
        (tostring (and latest latest.snapshot-world-id))
        ", latest-child-stdout="
        (tostring (and latest-child-read latest-child-read.stdout))
        ", latest-child-stderr="
        (tostring (and latest-child-read latest-child-read.stderr))
        ", latest-ready-stdout="
        (tostring (and latest-ready-result latest-ready-result.stdout))
        ", latest-ready-stderr="
        (tostring (and latest-ready-result latest-ready-result.stderr))
        ", latest-snapshot-stdout="
        (tostring (and latest-snapshot-result latest-snapshot-result.stdout))
        ", latest-snapshot-stderr="
        (tostring (and latest-snapshot-result latest-snapshot-result.stderr)))))

(fn request-app-quit! [endpoint]
  (remote-eval endpoint
               "(do
                  (app.next-frame
                    (fn []
                      (app.engine.quit)))
                  \"quitting\")"
               {:timeout-ms 3000
                :process-timeout 4}))

(fn live-app-root-hot-reload-roundtrip []
  (when is-windows
    (print "Skipping live hot reload test on Windows")
    (lua "return true"))
  (when (not (xvfb-run-available?))
    (print "Skipping live hot reload test: xvfb-run not available")
    (lua "return true"))
  (with-temp-dir
    (fn [dir]
      (local assets-path (assert (os.getenv "SPACE_ASSETS_PATH") "SPACE_ASSETS_PATH required"))
      (local source-lua-dir (fs.join-path assets-path "lua"))
      (local copied-assets-root (fs.join-path dir "assets"))
      (local copied-lua-dir (fs.join-path copied-assets-root "lua"))
      (local log-dir (fs.join-path dir "logs"))
      (local xdg-data-home (fs.join-path dir "xdg-data"))
      (local endpoint (make-remote-endpoint dir))
      (var child-id nil)

      (fs.create-dirs copied-assets-root)
      (fs.create-dirs log-dir)
      (fs.create-dirs xdg-data-home)
      (fs.copy source-lua-dir copied-lua-dir true true)

      (local fennel-path (.. copied-lua-dir "/?.fnl;" copied-lua-dir "/?/init.fnl"))
      (local main-path (fs.join-path copied-lua-dir "main.fnl"))
      (isolate-reporting-before-main! main-path)
      (set child-id
            (spawn-live-app {:assets-path (.. copied-assets-root ":" assets-path)
                            :watch-path copied-lua-dir
                            :log-dir log-dir
                            :xdg-data-home xdg-data-home
                            :fennel-path fennel-path
                            :fennel-macro-path fennel-path
                            :endpoint endpoint}))
      (assert (> child-id 0) "expected live app process to start")

      (local (ok result)
        (pcall
          (fn []
            (wait-for-remote endpoint child-id)
            (sleep-ms 3000)
            (local active-world-id (wait-for-default-world-id! xdg-data-home))
            (sleep-ms 3000)
            (fs.append-file main-path
                            (.. "\n; live-hot-reload-test "
                                (tostring (os.time))
                                "-"
                                (tostring (math.random 1000000))
                                "\n"))
            (wait-for-reload endpoint child-id active-world-id)
            (request-app-quit! endpoint)
            (local child-result (process.wait child-id))
            (set child-id nil)
            (assert (= child-result.exit-code 0)
                    (.. "live app exited unsuccessfully stdout=" (tostring child-result.stdout)
                        " stderr=" (tostring child-result.stderr)
                        " signal=" (tostring child-result.signal)
                        " timed-out=" (tostring (. child-result "timed-out"))))
            true)))

      (when (and child-id (process.running child-id))
        (if (keep-live-child-on-failure?)
            nil
            (do
              (process.kill child-id)
              (process.wait child-id))))

      (if ok
          result
          (error
            (if (and child-id (process.running child-id))
                (.. result "\nPreserved live hot reload child id: " (tostring child-id))
                result))))))

(table.insert tests {:name "live app root hot reload roundtrips active world"
                     :fn live-app-root-hot-reload-roundtrip})

(fn runtime-env-is-isolated []
  (with-temp-dir
    (fn [dir]
      (local env (make-runtime-env {:assets-path "/fixture/assets" :watch-path "/fixture/lua"
                                   :log-dir dir :xdg-data-home dir
                                   :fennel-path "/fixture/?.fnl" :fennel-macro-path "/fixture/?.fnl"}))
      (each [_ key (ipairs [:HOME :XDG_CONFIG_HOME :XDG_CACHE_HOME :XDG_STATE_HOME
                           :XDG_RUNTIME_DIR :XDG_CONFIG_DIRS :XDG_DATA_DIRS])]
        (local path (assert (. env key) (.. "missing isolated fixture environment " key)))
        (assert (= (string.sub path 1 (# dir)) dir) (.. "fixture environment escapes test root: " key)))
      (assert (= (. (fs.stat env.XDG_RUNTIME_DIR) :permissions) "rwx------"))
      true)))

(table.insert tests {:name "watcher fixture isolates home and all XDG roots" :fn runtime-env-is-isolated})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "live-hot-reload"
                       :tests tests})))

{:name "live-hot-reload"
 :tests tests
 :test-runtime-env runtime-env-is-isolated
 :main main}
