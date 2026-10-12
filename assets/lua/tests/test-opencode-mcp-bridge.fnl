(local tests [])
(local runner (require :tests/runner))
(local tempfile (require :tempfile))
(local fs (require :fs))
(local json (require :json))
(local Bridge (require :llm/opencode-mcp/bridge))

(fn make-fake-server [state]
  {:start (fn [_self host port]
            (tset state :started-with {:host host :port port})
            41237)
   :stop (fn [_self]
           (local current-count (if (= state.stop-count nil) 0 state.stop-count))
           (set state.stop-count (+ current-count 1)))})

(fn load-config [path]
  (json.loads (fs.read-file path)))

(fn with-temp-dir [f]
  (local handle (tempfile.TemporaryDirectory {:prefix "opencode-mcp-bridge-test-"}))
  (local (ok result) (pcall f handle.path))
  (handle:drop)
  (if ok
      result
      (error result)))

(fn make-bridge [root state extra]
  (local opts {:name "TestBridge"
               :tools {}
               :data-dir root
               :config-dir-name "test-opencode-config"
               :mcp-key "space-test"
               :permissions {:read "deny" :write "deny"}
               :http-server-factory (fn [] {:fake-http true})
               :mcp-server-factory (fn [_http] (make-fake-server state))})
  (local extras (if (= extra nil) {} extra))
  (each [k v (pairs extras)]
    (tset opts k v))
  (Bridge.OpencodeMcpBridge opts))

(fn assert-started-with-loopback [state]
  (assert (= state.started-with.host "127.0.0.1") "server should bind loopback")
  (assert (= state.started-with.port 0) "server should request an ephemeral port"))

(fn assert-config-permissions [config]
  (assert (= config.permission.read "deny") "read permission should be preserved")
  (assert (= config.permission.write "deny") "write permission should be preserved"))

(fn assert-config-mcp [config]
  (assert (= (. config.mcp :space-test :type) "remote") "MCP config should be remote")
  (assert (= (. config.mcp :space-test :enabled) true) "MCP config should be enabled")
  (assert (= (. config.mcp :space-test :url) "http://127.0.0.1:41237/mcp")
          "MCP URL should include fake port"))

(fn bridge-writes-isolated-opencode-config-in-dir [root]
  (local state {})
  (local bridge (make-bridge root state))
  (bridge:start)
  (assert-started-with-loopback state)
  (local env (bridge:opencode-env))
  (assert (= env.XDG_CONFIG_HOME (fs.join-path root "test-opencode-config"))
          "opencode env should point at isolated config root")
  (assert env.OPENCODE_CONFIG_CONTENT
          "opencode env should inject generated config content for final precedence")
  (local config (load-config (fs.join-path root "test-opencode-config" "opencode" "opencode.json")))
  (assert-config-permissions config)
  (assert-config-mcp config)
  (bridge:stop)
  (assert (= state.stop-count 1) "stop should stop the MCP server once"))

(fn shared-bridge-writes-isolated-opencode-config []
  (with-temp-dir bridge-writes-isolated-opencode-config-in-dir))

(fn explicit-openai-config-extra []
  (local models {})
  (tset models :gpt-5-test {:name "GPT 5 Test"})
  (local openai {:models models})
  (local providers {})
  (tset providers :openai openai)
  {:provider providers})

(fn bridge-writes-extra-generated-config-in-dir [root]
  (local state {})
  (local bridge
    (make-bridge root state {:config-extra (explicit-openai-config-extra)}))
  (bridge:start)
  (local env (bridge:opencode-env))
  (assert (= env.XDG_CONFIG_HOME (fs.join-path root "test-opencode-config"))
          "opencode env should remain isolated")
  (assert env.OPENCODE_CONFIG_CONTENT
          "opencode env should inject generated config content for final precedence")
  (local config (load-config (fs.join-path root "test-opencode-config" "opencode" "opencode.json")))
  (assert (= config.provider.openai.models.gpt-5-test.name "GPT 5 Test")
          "extra config should add explicit provider model")
  (assert-config-permissions config)
  (assert-config-mcp config)
  (bridge:stop))

(fn shared-bridge-writes-extra-generated-config []
  (with-temp-dir bridge-writes-extra-generated-config-in-dir))

(fn protected-config-extra []
  {:provider {:openai {:models {:gpt-5-test {:name "GPT 5 Test"}}}}
   :permission {:bash "allow"}
   :mcp {:untrusted {:type "remote" :url "http://127.0.0.1:1/mcp"}}})

(fn bridge-rejects-protected-extra-config-in-dir [root]
  (local state {})
  (local bridge
    (make-bridge root state {:config-extra (protected-config-extra)}))
  (local (ok err) (pcall bridge.start bridge))
  (assert (not ok) "protected config-extra keys should fail bridge start")
  (assert (string.find (tostring err) "permission")
          "protected config-extra failure should name permission config"))

(fn shared-bridge-rejects-protected-extra-config []
  (with-temp-dir bridge-rejects-protected-extra-config-in-dir))

(fn bridge-refresh-rewrites-current-config-in-dir [root]
  (local state {})
  (local bridge (make-bridge root state))
  (bridge:start)
  (local result (bridge:refresh-config!))
  (assert (= result.url "http://127.0.0.1:41237/mcp") "refresh should return current URL")
  (assert (= result.config-path (bridge:config-path)) "refresh should return config path")
  (local config (load-config result.config-path))
  (assert (= (. config.mcp :space-test :url) result.url) "refresh should rewrite current URL")
  (assert (= config.permission.read "deny") "refresh should write current permissions")
  (bridge:stop))

(fn shared-bridge-refresh-rewrites-current-config []
  (with-temp-dir bridge-refresh-rewrites-current-config-in-dir))

(fn unit-test-status-extra []
  {:kind "unit-test"
   :started? false
   :port 99})

(fn bridge-status-merges-wrapper-extras-in-dir [root]
  (local state {})
  (local bridge (make-bridge root state {:status-extra unit-test-status-extra}))
  (bridge:start)
  (local status (bridge:status))
  (assert (= status.started? true) "core started field should win")
  (assert (= status.kind "unit-test") "status should include wrapper extras")
  (assert (= status.port 41237) "core port field should win")
  (bridge:stop))

(fn shared-bridge-status-merges-wrapper-extras []
  (with-temp-dir bridge-status-merges-wrapper-extras-in-dir))

(fn failing-http-server [] {})

(fn make-failing-server [state]
  {:start (fn [_self _host _port] 0)
   :stop (fn [_self]
           (local current-count (if (= state.stop-count nil) 0 state.stop-count))
           (set state.stop-count (+ current-count 1)))})

(fn make-failing-bridge [root state]
  (Bridge.OpencodeMcpBridge
    {:name "FailingBridge"
     :tools {}
     :data-dir root
     :config-dir-name "failing-opencode-config"
     :mcp-key "space-failing"
     :permissions {:read "deny"}
     :http-server-factory failing-http-server
     :mcp-server-factory (fn [_http] (make-failing-server state))}))

(fn bridge-cleans-up-failed-start-in-dir [root]
  (local state {})
  (local failed (make-failing-bridge root state))
  (local (ok _err) (pcall failed.start failed))
  (assert (not ok) "invalid port should fail start")
  (assert (= state.stop-count 1) "failed start should stop the server")
  (local status (failed:status))
  (assert (= status.started? false) "failed start should clear started state")
  (assert (= status.port nil) "failed start should clear port"))

(fn shared-bridge-cleans-up-failed-start []
  (with-temp-dir bridge-cleans-up-failed-start-in-dir))

(table.insert tests {:name "shared bridge writes isolated opencode config"
                      :fn shared-bridge-writes-isolated-opencode-config})
(table.insert tests {:name "shared bridge writes extra generated config"
                     :fn shared-bridge-writes-extra-generated-config})
(table.insert tests {:name "shared bridge rejects protected extra config"
                     :fn shared-bridge-rejects-protected-extra-config})
(table.insert tests {:name "shared bridge refresh rewrites current config"
                     :fn shared-bridge-refresh-rewrites-current-config})
(table.insert tests {:name "shared bridge status merges wrapper extras"
                     :fn shared-bridge-status-merges-wrapper-extras})
(table.insert tests {:name "shared bridge cleans up failed start"
                     :fn shared-bridge-cleans-up-failed-start})

(fn main []
  (runner.run-tests {:name "opencode-mcp-bridge" :tests tests}))

{:tests tests
 :main main}
