;; Native startup cases run in a child with a private checkout AND runtime root.
;; No synthetic healthy record may be published into the developer's partition.
(local fs (require :fs))
(local fennel (require :fennel))
(local process (require :process))
(local tempfile (require :tempfile))
(local sysinfo (require :sysinfo))

(fn prepare [root]
  (local source (assert (fennel.search-module "main")))
  (local assets (fs.parent (fs.parent source)))
  (local checkout (fs.join-path root "checkout"))
  (local lua-dir (fs.join-path checkout "assets" "lua"))
  (fs.create-dirs lua-dir)
  (fs.create-dir (fs.join-path checkout ".git"))
  (fs.write-file (fs.join-path lua-dir "main.fnl") (fs.read-file source))
  (fs.write-file (fs.join-path lua-dir "macros.fnl")
                 (fs.read-file (assert (fennel.search-module "macros"))))
  (local runtime (fs.join-path root "runtime"))
  (local mkdir (process.run {:args ["mkdir" "-m" "700" "--" runtime]
                            :env {:PATH (assert (os.getenv "PATH"))} :timeout 2}))
  (assert (= mkdir.exit-code 0) "cannot create isolated native startup runtime")
  (local paths (.. lua-dir "/?.fnl;" lua-dir "/?/init.fnl;"
                   assets "/lua/?.fnl;" assets "/lua/?/init.fnl"))
  {:PATH (assert (os.getenv "PATH")) :HOME (fs.join-path root "home")
   :SPACE_ASSETS_PATH (.. (fs.join-path checkout "assets") ":" assets)
   :FENNEL_PATH paths :FENNEL_MACRO_PATH paths
   :SPACE_LIVE_DEV_STARTUP_FIXTURE root :XDG_RUNTIME_DIR runtime
   :XDG_DATA_HOME (fs.join-path root "data") :XDG_CONFIG_HOME (fs.join-path root "config")
   :XDG_CACHE_HOME (fs.join-path root "cache") :XDG_STATE_HOME (fs.join-path root "state")
   :XDG_CONFIG_DIRS (fs.join-path root "site-config") :XDG_DATA_DIRS (fs.join-path root "site-data")
   :SPACE_LOG_DIR (fs.join-path root "logs") :SPACE_DISABLE_AUDIO "1" :SKIP_KEYRING_TESTS "1"})

(fn run [case-name]
  (when (not= (. (sysinfo.platform) :os) "linux") (lua "return true"))
  (fs.create-dirs "/tmp/space")
  (local dir (tempfile.TemporaryDirectory {:dir "/tmp/space" :prefix "lds-"}))
  (fn body []
    (local env (prepare dir.path))
    (local native (. (require :app-config) :live-dev))
    (local executable (. (native.describe-source (assert (fennel.search-module "main"))) :executable))
    (local result (process.run {:args [executable "--no-dotenv" "-m"
                                      "tests.test-live-dev-runtime:test-native-startup" case-name]
                               :cwd dir.path :env env :timeout 30}))
    (assert (= result.exit-code 0)
            (.. "isolated native startup failed: "
                (if (= result.stderr nil) "" result.stderr)
                (if (= result.stdout nil) "" result.stdout))))
  (local (ok err) (pcall body))
  (dir:drop)
  (assert ok (tostring err))
  true)

{:run run}
