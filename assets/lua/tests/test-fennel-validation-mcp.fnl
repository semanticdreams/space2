(local tests [])
(local fs (require :fs))
(local json (require :json))
(local tempfile (require :tempfile))
(local ServiceModule (require :llm/fennel-validation/service))
(local FennelValidationMcpTools (require :llm/fennel-validation/tools))

(fn with-temp-dir [f]
  (local handle (tempfile.TemporaryDirectory {:prefix "fennel-validation-mcp-test-"}))
  (local (ok result) (pcall f handle.path))
  (handle:drop)
  (if ok
      result
      (error result)))

(fn write-temp-file [dir name content]
  (local path (fs.join-path dir name))
  (fs.write-file path content)
  path)

(fn new-registry []
  (local service (ServiceModule.FennelValidationService {}))
  (local registry (FennelValidationMcpTools.make-tool-registry {}))
  (FennelValidationMcpTools.register-tools registry service)
  registry)

(fn tool-json [registry name args]
  (local result (registry:call name args))
  (assert (= result.isError false) (.. name " should not return MCP error"))
  (assert (= (length result.content) 1) (.. name " should return one text content item"))
  (assert (= (. result.content 1 :type) "text") (.. name " content should be text"))
  (json.loads (. result.content 1 :text)))

(fn registry-lists-read-only-fennel-validation-tools []
  (local registry (new-registry))
  (local expected ["space_constraints_check_files"
                  "space_fennel_check_file"
                  "space_fennel_enclosing_form"
                  "space_fennel_parse_tree"
                  "space_fennel_structure_metrics"])
  (local listed (registry:list))
  (assert (= (# listed) (# expected)) "registry should expose exactly five tools")
  (each [i name (ipairs expected)]
    (local tool (. listed i))
    (assert tool (.. "missing tool at index " i))
    (assert (= tool.name name) (.. "expected tool " name ", got " (or tool.name "nil")))
    (assert (not= tool.description nil) (.. name " should have a description"))
    (assert tool.inputSchema (.. name " should have input schema")))
  (local risks (FennelValidationMcpTools.get-tool-risks))
  (each [_ name (ipairs expected)]
    (assert (= (. risks name) "filesystem-read")
            (.. name " should be labeled filesystem-read"))))

(fn check-file-tool-returns-compile-diagnostics-in-dir [dir]
  (local path (write-temp-file dir "broken.fnl" "(fn broken [name]\n  (print name)\n"))
  (local payload (tool-json (new-registry) "space_fennel_check_file" {:file path}))
  (assert (= payload.status "fail") "malformed file should fail")
  (assert (= payload.ok false) "malformed file should be not ok")
  (assert (= payload.summary.checked 1) "should check one file")
  (assert (> (# payload.diagnostics) 0) "should include diagnostics")
  (assert (= (. payload.diagnostics 1 :kind) "compile") "diagnostic should be compile kind"))

(fn check-file-tool-returns-compile-diagnostics []
  (with-temp-dir check-file-tool-returns-compile-diagnostics-in-dir))

(fn structural-tools-return-json-payloads-in-dir [dir]
  (local path (write-temp-file dir "valid.fnl" "(fn outer [item]\n  (let [wrapped item]\n    (print item)\n    wrapped))\n{:outer outer}\n"))
  (local registry (new-registry))
  (local parse (tool-json registry "space_fennel_parse_tree" {:file path :max-chars 80}))
  (assert parse.ok "parse-tree should be ok")
  (assert (= (type parse.sexpr) "string") "parse-tree should include sexpr")
  (local enclosing (tool-json registry "space_fennel_enclosing_form" {:file path :line 3 :column 12}))
  (assert enclosing.ok "enclosing-form should be ok")
  (assert (= enclosing.form "(print item)") "should return smallest enclosing form")
  (local metrics (tool-json registry "space_fennel_structure_metrics" {:file path}))
  (assert metrics.ok "structure-metrics should be ok")
  (assert (= (type metrics.metrics) "table") "metrics payload should include metrics table")
  (assert (> (# metrics.metrics.functions) 0) "metrics should include functions"))

(fn structural-tools-return-json-payloads []
  (with-temp-dir structural-tools-return-json-payloads-in-dir))

(fn constraints-tool-returns-status-counts-diagnostics-in-dir [dir]
  (local path (write-temp-file dir "constraints.fnl" "{:ok true}\n"))
  (local payload (tool-json (new-registry) "space_constraints_check_files" {:files [path]}))
  (assert payload.status "constraints payload should include status")
  (assert (= (type payload.counts) "table") "constraints payload should include counts")
  (assert (= (type payload.diagnostics) "table") "constraints payload should include diagnostics"))

(fn constraints-tool-returns-status-counts-diagnostics []
  (with-temp-dir constraints-tool-returns-status-counts-diagnostics-in-dir))

(local FennelValidationMcpBridge (require :llm/fennel-validation/bridge))

(var bridge-stopped? false)

(fn fake-server-start [_self host port]
  (assert (= host "127.0.0.1") "bridge should bind loopback by default")
  (assert (= port 0) "bridge should request an ephemeral port")
  31337)

(fn fake-server-stop [_self]
  (set bridge-stopped? true))

(fn fake-http-server []
  {:fake-http true})

(fn fake-mcp-server [_http-server]
  {:start fake-server-start
   :stop fake-server-stop})

(fn empty-tool-list [] [])

(local expected-fennel-validation-opencode-permissions
  {:invalid "deny"
   :read "allow"
   :write "deny"
   :edit "deny"
   :grep "allow"
   :glob "allow"
   :list "allow"
   :bash "deny"
   :task "deny"
   :external_directory "deny"
   :todowrite "deny"
   :webfetch "deny"
   :websearch "deny"
   :lsp "deny"
   :skill "deny"
   :question "deny"})

(fn assert-exact-opencode-permissions [actual expected]
  (assert (= (type actual) "table") "config permission should be a table")
  (var expected-count 0)
  (each [name expected-value (pairs expected)]
    (set expected-count (+ expected-count 1))
    (local actual-value (. actual name))
    (assert (= actual-value expected-value)
            (.. "native OpenCode permission '" name "' expected '" expected-value
                "', got '" (or actual-value "nil") "'")))
  (var actual-count 0)
  (each [name _value (pairs actual)]
    (set actual-count (+ actual-count 1))
    (assert (not= (. expected name) nil)
            (.. "unexpected native OpenCode permission key: " name)))
  (assert (= actual-count expected-count)
          (.. "native OpenCode permission map should have exactly " expected-count
              " entries, got " actual-count)))

(fn bridge-writes-isolated-read-only-opencode-config-in-dir [dir]
  (set bridge-stopped? false)
  (local data-dir (fs.join-path dir "bridge-data"))
  (fs.create-dirs data-dir)
  (local bridge (FennelValidationMcpBridge.FennelValidationMcpBridge
                  {:tools {:list empty-tool-list}
                   :data-dir data-dir
                   :http-server-factory fake-http-server
                   :mcp-server-factory fake-mcp-server}))
  (bridge:start)
  (local status (bridge:status))
  (assert (= status.started? true) "bridge should be started")
  (assert (= status.url "http://127.0.0.1:31337/mcp") "status should expose MCP URL")
  (assert (= (bridge:config-path) status.config-path)
          "bridge config-path method should expose the generated config path")
  (assert (= (string.sub status.config-path 1 (# data-dir)) data-dir)
          "config should live under provided data dir")
  (local env (bridge:opencode-env))
  (assert (= env.XDG_CONFIG_HOME status.config-root) "env should point at isolated config root")
  (local config (json.loads (fs.read-file status.config-path)))
  (assert config.mcp.space-fennel-validation "config should register fennel validation MCP server")
  (assert (= config.mcp.space-fennel-validation.url status.url) "MCP URL should match status")
  (assert-exact-opencode-permissions config.permission expected-fennel-validation-opencode-permissions)
  (local refreshed (bridge:refresh-config!))
  (assert (= refreshed.config-path status.config-path)
          "refresh should report the same generated config path")
  (assert (= refreshed.url status.url)
          "refresh should keep the active MCP url")
  (bridge:stop)
  (assert bridge-stopped? "bridge should stop server"))

(fn bridge-writes-isolated-read-only-opencode-config []
  (with-temp-dir bridge-writes-isolated-read-only-opencode-config-in-dir))

(fn server-entrypoint-exports-main []
  (local server (require :tools/fennel-validation-mcp-server))
  (assert (= (type server.main) "function") "server module should export main"))

(table.insert tests {:name "fennel-validation-mcp: registry lists read-only tools and risks"
                     :fn registry-lists-read-only-fennel-validation-tools})
(table.insert tests {:name "fennel-validation-mcp: check file returns structured diagnostics"
                     :fn check-file-tool-returns-compile-diagnostics})
(table.insert tests {:name "fennel-validation-mcp: structural tools return JSON payloads"
                     :fn structural-tools-return-json-payloads})
(table.insert tests {:name "fennel-validation-mcp: constraints tool returns status counts diagnostics"
                     :fn constraints-tool-returns-status-counts-diagnostics})
(table.insert tests {:name "fennel-validation-mcp: bridge writes isolated read-only config"
                     :fn bridge-writes-isolated-read-only-opencode-config})
(table.insert tests {:name "fennel-validation-mcp: server entrypoint exports main"
                     :fn server-entrypoint-exports-main})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "fennel-validation-mcp"
                       :tests tests})))

{:name "fennel-validation-mcp"
 :tests tests
 :main main}
