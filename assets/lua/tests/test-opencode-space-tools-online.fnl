;; Verify the production OpenCode bridge config denies native tools while Space
;; MCP tools remain available.
;;
;; Run:
;; SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-opencode-space-tools-online:main
;; OPENCODE_SPACE_TOOLS_HELPER_ONLY=1 runs the offline helper regressions only.

(local OpencodeSdk (require :llm/providers/opencode))
(local callbacks (require :callbacks))
(local fs (require :fs))
(local sysinfo (require :sysinfo))
(local process (require :process))
(local json (require :json))
(local ToolRegistry (require :mcp/tool-registry))
(local AgentOpencodeMcpBridgeMod (require :llm/agent/opencode-mcp-bridge))

(var passed 0)
(var failed 0)
(var failures [])
(var active-test nil)

(fn now-ms []
  (sysinfo.now-ms))

(fn assert-ok [condition message]
  (when (not condition)
    (error (or message "assertion failed"))))

(fn response-error [result]
  (if (and result result.raw)
      result.raw
      (and result result.error)
      result.error
      "unknown error"))

(fn assert-response-ok [result label]
  (assert-ok result (.. label " should return a response"))
  (assert-ok result.ok (.. label " failed: " (response-error result))))

(fn poll-all []
  (callbacks.run-loop {:poll-http true :poll-process true :sleep-ms 10 :timeout-ms 50}))

(fn wait-for [pred timeout-ms]
  (local wait-ms (if timeout-ms timeout-ms 10000))
  (local deadline (+ (now-ms) wait-ms))
  (var result nil)
  (while (and (not result) (< (now-ms) deadline))
    (poll-all)
    (local (ok value) (pcall pred))
    (when ok
      (set result value)))
  (assert-ok result (.. "timeout after " wait-ms "ms")))

(fn run-test [name f]
  (io.write (.. "  " name " ... "))
  (io.flush)
  (local (ok err) (pcall f))
  (if ok
      (do
        (set passed (+ passed 1))
        (print "PASS"))
      (do
        (set failed (+ failed 1))
        (table.insert failures {:name name :error (tostring err)})
        (print (.. "FAIL: " (tostring err))))))

(fn ensure-dir! [path]
  (when (not (fs.exists path))
    (fs.create-dirs path)))

(fn choose-model [server override]
  (local override-provider (and override override.providerID))
  (local override-model (and override override.modelID))
  (local env-provider (if override-provider override-provider (os.getenv "OPENCODE_SPACE_TOOLS_PROVIDER_ID")))
  (local env-model (if override-model override-model (os.getenv "OPENCODE_SPACE_TOOLS_MODEL_ID")))
  (if (or env-provider env-model)
      (do
        (assert-ok (and env-provider env-model)
                   "OPENCODE_SPACE_TOOLS_PROVIDER_ID and OPENCODE_SPACE_TOOLS_MODEL_ID must be set together")
        {:providerID env-provider :modelID env-model})
      (do
        (var result nil)
        (server.config.providers (fn [r] (set result r)))
        (wait-for #(not= result nil) 10000)
        (assert-response-ok result "config providers")
        (if (and result.data.default result.data.default.opencode)
            {:providerID "opencode" :modelID result.data.default.opencode}
            result.data.default
            (do
              (local picked [])
              (each [provider-id model-id (pairs result.data.default)]
                (when (= (# picked) 0)
                  (table.insert picked {:providerID provider-id :modelID model-id})))
              (assert-ok (> (# picked) 0) "no default model configured")
              (. picked 1))
            (error "no default model configured")))))

(fn tool-name [tool]
  (if tool.name
      tool.name
      tool.id
      tool.id
      tool.tool
      tool.tool
      (and tool.function tool.function.name)
      tool.function.name
      nil))

(fn collect-tool-names [value names]
  (when (= (type value) "table")
    (local direct (tool-name value))
    (when (and direct (= (type direct) "string"))
      (table.insert names direct))
    (if value.tools
        (collect-tool-names value.tools names)
        value.tool
        nil
        (each [_ item (ipairs value)]
          (collect-tool-names item names)))))

(fn sorted-tool-names [data]
  (local names [])
  (collect-tool-names data names)
  (table.sort names)
  names)

(fn all-space-tools? [names]
  (var ok true)
  (each [_ name (ipairs names)]
    (when (not (string.find name "^space_"))
      (set ok false)))
  ok)

(fn permission-denied? [permission]
  (if (= permission "deny")
      true
      (= (type permission) "table")
      (do
        (var has-deny false)
        (var has-allow false)
        (each [_ decision (pairs permission)]
          (if (= decision "allow")
              (set has-allow true)
              (= decision "deny")
              (set has-deny true)))
        (and has-deny (not has-allow)))
      false))

(fn native-permission-key [name]
  (if (= name "apply_patch")
      "edit"
      name))

(fn all-native-tools-denied? [names permissions]
  (var ok true)
  (each [_ name (ipairs names)]
    (local permission-key (native-permission-key name))
    (when (and (not (string.find name "^space_"))
               (not (permission-denied? (. permissions permission-key))))
      (set ok false)))
  ok)

(fn fake-providers-response [state callback]
  (tset state :calls (+ state.calls 1))
  (callback {:ok true
              :data {:providers []
                     :default {:opencode "test-default"}}}))

(fn fake-provider-server []
  (local state {:calls 0})
  {:state state
   :config {:providers (fn [callback]
                         (fake-providers-response state callback))}})

(fn explicit-model-override []
  (local provider-id (os.getenv "OPENCODE_SPACE_TOOLS_PROVIDER_ID"))
  (local model-id (os.getenv "OPENCODE_SPACE_TOOLS_MODEL_ID"))
  (if provider-id
      (do
        (assert-ok model-id
                   "OPENCODE_SPACE_TOOLS_PROVIDER_ID and OPENCODE_SPACE_TOOLS_MODEL_ID must be set together")
        {:providerID provider-id :modelID model-id})
      model-id
      (error "OPENCODE_SPACE_TOOLS_PROVIDER_ID and OPENCODE_SPACE_TOOLS_MODEL_ID must be set together")
      nil))

(fn provider-model-config-extra [model]
  (when model
    (local models {})
    (tset models model.modelID {:name model.modelID})
    (local provider-config {:models models})
    (local providers {})
    (tset providers model.providerID provider-config)
    {:default_agent "build"
     :provider providers}))

(fn filter-auth-content-json [provider-id content]
  (when (and provider-id content (> (# content) 0))
    (local (ok parsed) (pcall json.loads content))
    (when (and ok (= (type parsed) "table") (. parsed provider-id))
      (local filtered {})
      (tset filtered provider-id (. parsed provider-id))
      (json.dumps filtered))))

(fn default-auth-content []
  (local env-content (os.getenv "OPENCODE_AUTH_CONTENT"))
  (if env-content
      env-content
      (do
        (local home (os.getenv "HOME"))
        (when home
          (local auth-path (fs.join-path home ".local/share/opencode/auth.json"))
          (when (fs.exists auth-path)
            (fs.read-file auth-path))))))

(fn provider-auth-content [provider-id]
  (filter-auth-content-json provider-id (default-auth-content)))

(fn copy-env [source]
  (local input (if (= source nil) {} source))
  (local env {})
  (each [k v (pairs input)]
    (tset env k v))
  env)

(fn path-only-env []
  (local env {})
  (local path (os.getenv "PATH"))
  (when path
    (tset env :PATH path))
  env)

(fn isolated-opencode-env [root bridge-env explicit-model]
  (local env (copy-env bridge-env))
  (local home (fs.join-path root "home"))
  (local data-home (fs.join-path root "xdg-data"))
  (ensure-dir! home)
  (ensure-dir! data-home)
  (tset env :HOME home)
  (tset env :XDG_DATA_HOME data-home)
  (local path (os.getenv "PATH"))
  (when path
    (tset env :PATH path))
  (local auth-content (and explicit-model (provider-auth-content explicit-model.providerID)))
  (when auth-content
    (tset env :OPENCODE_AUTH_CONTENT auth-content))
  env)

(fn opencode-server-options [opencode-path bridge root]
  (local explicit-model (explicit-model-override))
  {:opencode-path opencode-path
   :port 0
   :env (isolated-opencode-env root (bridge:opencode-env) explicit-model)
   :clear-env true})

(fn opencode-version-check-options [opencode-path]
  {:args [opencode-path "--version"]
   :timeout_seconds 5
   :env (path-only-env)
   :clear-env true})

(fn assert-explicit-model-override []
  (local override {:providerID "openai" :modelID "gpt-5.5"})
  (local server (fake-provider-server))
  (local model (choose-model server override))
  (assert-ok (= model.providerID override.providerID) "provider override should be selected")
  (assert-ok (= model.modelID override.modelID) "model override should be selected")
  (assert-ok (= server.state.calls 0) "explicit override should not query provider list"))

(fn assert-env-model-override []
  (local env-provider (os.getenv "OPENCODE_SPACE_TOOLS_PROVIDER_ID"))
  (local env-model (os.getenv "OPENCODE_SPACE_TOOLS_MODEL_ID"))
  (assert-ok (and env-provider env-model)
             "set OPENCODE_SPACE_TOOLS_PROVIDER_ID and OPENCODE_SPACE_TOOLS_MODEL_ID for env override regression")
  (local server (fake-provider-server))
  (local model (choose-model server))
  (assert-ok (= model.providerID env-provider) "env provider override should be selected")
  (assert-ok (= model.modelID env-model) "env model override should be selected")
  (assert-ok (= server.state.calls 0) "env override should not query provider list"))

(fn assert-provider-model-config-extra []
  (local config (provider-model-config-extra {:providerID "openai" :modelID "gpt-5-test"}))
  (assert-ok (= config.provider.openai.models.gpt-5-test.name "gpt-5-test")
             "explicit provider model should be injected into generated config"))

(fn assert-auth-content-filter []
  (local content (json.dumps {:openai {:type "api" :key "openai-key"}
                              :anthropic {:type "api" :key "anthropic-key"}}))
  (local filtered (filter-auth-content-json "openai" content))
  (local parsed (json.loads filtered))
  (assert-ok parsed.openai "filtered auth should include requested provider")
  (assert-ok (not parsed.anthropic) "filtered auth should exclude other providers"))

(fn assert-opencode-server-options-clear-env []
  (local root (.. "/tmp/space/tests/opencode-env-helper-" (os.time) "-" (math.random 0 99999)))
  (local bridge {:opencode-env (fn [] {:XDG_CONFIG_HOME "/tmp/space-config"
                                       :OPENCODE_CONFIG_CONTENT "{\"mcp\":{}}"})})
  (local (ok opts) (pcall opencode-server-options "opencode" bridge root))
  (when (fs.exists root)
    (fs.remove-all root))
  (assert-ok ok (.. "server options should build: " (tostring opts)))
  (assert-ok (= opts.clear-env true) "OpenCode server should clear inherited environment")
  (assert-ok (= opts.env.XDG_CONFIG_HOME "/tmp/space-config") "bridge config env should be preserved")
  (assert-ok (= opts.env.HOME (fs.join-path root "home")) "HOME should be isolated")
  (assert-ok (= opts.env.XDG_DATA_HOME (fs.join-path root "xdg-data")) "XDG data should be isolated")
  (assert-ok (not opts.env.OPENAI_API_KEY) "parent provider API keys should not be copied directly"))

(fn assert-opencode-version-check-clear-env []
  (local opts (opencode-version-check-options "opencode"))
  (assert-ok (= opts.clear-env true) "OpenCode version preflight should clear inherited environment")
  (assert-ok (= opts.timeout_seconds 5) "OpenCode version preflight should retain timeout")
  (assert-ok opts.env "OpenCode version preflight should pass an explicit env")
  (assert-ok (not opts.env.HOME) "OpenCode version preflight should not inherit HOME")
  (assert-ok (not opts.env.OPENAI_API_KEY) "OpenCode version preflight should not inherit provider API keys"))

(fn assert-literal-deny []
  (assert-ok (all-native-tools-denied? ["bash"] {:bash "deny"})
             "literal deny should deny native bash"))

(fn assert-wildcard-deny-table []
  (assert-ok (all-native-tools-denied? ["bash" "space_probe"]
                                       {:bash {"*" "deny"}})
             "wildcard deny table with no allows should deny native bash"))

(fn assert-allow-table-not-denied []
  (assert-ok (not (all-native-tools-denied? ["read"]
                                            {:read {"*" "deny" "/tmp/**" "allow"}}))
             "bounded permission table with an allow entry should not count as fully denied"))

(fn run-helper-regression-tests []
  (run-test "explicit model override bypasses generated provider list" assert-explicit-model-override)
  (when (and (os.getenv "OPENCODE_SPACE_TOOLS_PROVIDER_ID")
             (os.getenv "OPENCODE_SPACE_TOOLS_MODEL_ID"))
    (run-test "explicit env model override bypasses generated provider list" assert-env-model-override))
  (run-test "literal deny counts as native tool denied" assert-literal-deny)
  (run-test "bounded wildcard deny table counts as native tool denied" assert-wildcard-deny-table)
  (run-test "bounded table with any allow is not fully denied" assert-allow-table-not-denied)
  (run-test "explicit model override injects provider model config" assert-provider-model-config-extra)
  (run-test "explicit model override filters provider auth content" assert-auth-content-filter)
  (run-test "opencode server options clear inherited env" assert-opencode-server-options-clear-env)
  (run-test "opencode version preflight clears inherited env" assert-opencode-version-check-clear-env))

(fn text-from-parts [parts]
  (var text "")
  (local safe-parts (if parts parts []))
  (each [_ part (ipairs safe-parts)]
    (when (= part.type "text")
      (local part-text (if part.text part.text ""))
      (set text (.. text part-text))))
  text)

(fn cleanup [handles]
  (when handles.server
    (pcall handles.server.close))
  (when handles.bridge
    (pcall (fn [] (handles.bridge:stop))))
  (when (and handles.root (fs.exists handles.root))
    (pcall (fn [] (fs.remove-all handles.root)))))

(fn trim-version [text]
  (string.gsub (if text text "") "%s+$" ""))

(fn register-probe-tool [registry state]
  (registry:register
    {:name "space_only_probe"
     :description "Space-only verification tool. Returns a fixed token."
     :inputSchema {:type "object"
                   :properties {}
                   :additionalProperties false}
     :run (fn [_args]
            (tset state :probe-call-count (+ state.probe-call-count 1))
            "space-only-ok")}))

(fn start-bridge [root handles state]
  (ensure-dir! root)
  (local registry (ToolRegistry {:namespace-prefix "space_"}))
  (register-probe-tool registry state)
  (local explicit-model (explicit-model-override))
  (local bridge (AgentOpencodeMcpBridgeMod.AgentOpencodeMcpBridge
                  {:tools registry
                   :data-dir (fs.join-path root "bridge")
                   :config-extra (provider-model-config-extra explicit-model)}))
  (bridge:start)
  (tset handles :bridge bridge)
  (local bridge-status (bridge:status))
  (print "mcp: " bridge-status.url)
  {:bridge bridge
   :config (json.loads (fs.read-file bridge-status.config-path))})

(fn start-opencode-server [opencode-path bridge handles]
  (local server (OpencodeSdk.Opencode (opencode-server-options opencode-path bridge handles.root)))
  (tset handles :server server)
  (print "server: " (server.server.url))
  server)

(fn health-test-body []
  (var health nil)
  (active-test.server.global.health (fn [r] (set health r)))
  (wait-for #(not= health nil) 10000)
  (assert-response-ok health "health check"))

(fn run-health-test [server]
  (set active-test {:server server})
  (run-test "health check" health-test-body))

(fn tool-schema-test-body []
  (var tools-result nil)
  (active-test.server.client.submit "GET" "/experimental/tool"
                                    {:query {:provider active-test.model.providerID
                                             :model active-test.model.modelID}
                                     :on_response (fn [r] (set tools-result r))})
  (wait-for #(not= tools-result nil) 30000)
  (assert-response-ok tools-result "experimental tool list")
  (local names (sorted-tool-names tools-result.data))
  (local raw (if tools-result.raw tools-result.raw ""))
  (print "  tools: " (table.concat names ", "))
  (print "  raw: " (string.sub raw 1 1000))
  (assert-ok (> (# names) 0) "tool list should not be empty")
  (assert-ok (all-native-tools-denied? names active-test.bridge-config.permission)
             (.. "all advertised native tools should be denied by bridge config, got: "
                 (table.concat names ", "))))

(fn run-tool-schema-test [server model bridge-config]
  (set active-test {:server server :model model :bridge-config bridge-config})
  (run-test "experimental tool schema inspection" tool-schema-test-body))

(fn create-session-test-body []
  (var result nil)
  (active-test.server.session.create {:title active-test.title} (fn [r] (set result r)))
  (wait-for #(not= result nil) 10000)
  (assert-response-ok result active-test.label)
  (tset active-test :session-id result.data.id)
  (assert-ok active-test.session-id (.. active-test.label " session id missing")))

(fn create-session [server title label]
  (set active-test {:server server :title title :label label :session-id nil})
  (run-test label create-session-test-body)
  active-test.session-id)

(fn safe-parts [parts]
  (if parts parts []))

(fn collect-session-tool-names [messages]
  (local tool-names [])
  (each [_ msg (ipairs messages.data)]
    (each [_ part (ipairs (safe-parts msg.parts))]
      (when (= part.type "tool")
        (table.insert tool-names (if part.tool part.tool "")))))
  (table.sort tool-names)
  tool-names)

(fn load-session-tool-names [server session-id label]
  (var messages nil)
  (server.session.messages session-id (fn [r] (set messages r)))
  (wait-for #(not= messages nil) 10000)
  (assert-response-ok messages label)
  (collect-session-tool-names messages))

(fn prompt-session [server session-id model prompt label]
  (var result nil)
  (server.session.prompt session-id
    {:model model
     :parts [{:type "text" :text prompt}]}
    (fn [r] (set result r)))
  (wait-for #(not= result nil) 120000)
  (assert-response-ok result label)
  result)

(fn space-tool-prompt-test-body []
  (local result (prompt-session active-test.server active-test.session-id active-test.model
                                "Call the space_only_probe tool exactly once. Reply with exactly the tool result and no extra text."
                                "space_only_probe prompt"))
  (local text (text-from-parts result.data.parts))
  (print "  response: " (string.sub text 1 300))
  (assert-ok (= active-test.state.probe-call-count 1)
             (.. "space_only_probe should be called once, got " active-test.state.probe-call-count))
  (assert-ok (string.find text "space-only-ok" 1 true)
             (.. "response should include tool result, got: " text)))

(fn run-space-tool-prompt-test [server session-id model state]
  (set active-test {:server server :session-id session-id :model model :state state})
  (run-test "online model calls only space tool" space-tool-prompt-test-body))

(fn space-audit-test-body []
  (local tool-names (load-session-tool-names active-test.server active-test.session-id "session messages"))
  (print "  audit tools: " (table.concat tool-names ", "))
  (assert-ok (> (# tool-names) 0) "expected at least one audited tool call")
  (assert-ok (all-space-tools? tool-names)
             (.. "expected audit to contain only space tools, got: " (table.concat tool-names ", "))))

(fn run-space-audit-test [server session-id]
  (set active-test {:server server :session-id session-id})
  (run-test "session audit has no native tool calls" space-audit-test-body))

(fn name-matches-any? [name needles]
  (var found false)
  (each [_ needle (ipairs needles)]
    (if (= name needle)
        (set found true)
        (string.find name needle 1 true)
        (set found true)))
  found)

(fn any-tool-matches? [tool-names needles]
  (var found false)
  (each [_ name (ipairs tool-names)]
    (when (name-matches-any? name needles)
      (set found true)))
  found)

(fn native-bash-deny-test-body []
  (local result (prompt-session active-test.server active-test.session-id active-test.model
                                "Call the bash tool with command `echo native-tool-leaked`. Do not call any Space tools. If bash is unavailable, reply exactly `bash unavailable`."
                                "denied bash prompt"))
  (local text (text-from-parts result.data.parts))
  (print "  response: " (string.sub text 1 300))
  (local tool-names (load-session-tool-names active-test.server active-test.session-id "native-deny session messages"))
  (print "  native-deny audit tools: " (table.concat tool-names ", "))
  (assert-ok (not (any-tool-matches? tool-names ["bash" "shell"]))
             (.. "denied native bash should not execute, got: " (table.concat tool-names ", "))))

(fn run-native-bash-deny-test [server session-id model]
  (set active-test {:server server :session-id session-id :model model})
  (run-test "online model cannot execute denied native bash" native-bash-deny-test-body))

(fn native-write-deny-test-body []
  (local leak-path (fs.join-path active-test.root "native-write-leak.txt"))
  (local result (prompt-session active-test.server active-test.session-id active-test.model
                                (.. "Call the write tool to write file `" leak-path "` with content `native-write-leaked`. "
                                    "Do not call any Space tools. If write is unavailable, reply exactly `write unavailable`.")
                                "denied write prompt"))
  (local text (text-from-parts result.data.parts))
  (print "  response: " (string.sub text 1 300))
  (local tool-names (load-session-tool-names active-test.server active-test.session-id "native-write-deny session messages"))
  (print "  native-write-deny audit tools: " (table.concat tool-names ", "))
  (assert-ok (not (any-tool-matches? tool-names ["write" "edit"]))
             (.. "denied native write should not execute, got: " (table.concat tool-names ", ")))
  (assert-ok (not (fs.exists leak-path))
             (.. "denied native write should not create " leak-path)))

(fn run-native-write-deny-test [server session-id model root]
  (set active-test {:server server :session-id session-id :model model :root root})
  (run-test "online model cannot execute denied native write" native-write-deny-test-body))

(fn run-online-verification [root handles opencode-path]
  (local state {:probe-call-count 0})
  (local bridge-info (start-bridge root handles state))
  (local server (start-opencode-server opencode-path bridge-info.bridge handles))
  (run-health-test server)
  (local model (choose-model server))
  (print "model: " model.providerID "/" model.modelID)
  (run-tool-schema-test server model bridge-info.config)
  (local session-id (create-session server "space-only-tools-verification" "create session"))
  (run-space-tool-prompt-test server session-id model state)
  (run-space-audit-test server session-id)
  (local native-session-id (create-session server "native-deny-probe" "create native-deny probe session"))
  (run-native-bash-deny-test server native-session-id model)
  (local write-session-id (create-session server "native-write-deny-probe" "create native-write deny probe session"))
  (run-native-write-deny-test server write-session-id model root)
  (print "")
  (print "==========================")
  (print (.. "Results: " passed " passed, " failed " failed")))

(fn main []
  (print "OpenCode Space-only Tool Verification")
  (print "====================================")
  (print "")

  (run-helper-regression-tests)
  (when (> failed 0)
    (error "online harness helper regression failed"))
  (if (= (os.getenv "OPENCODE_SPACE_TOOLS_HELPER_ONLY") "1")
      (print (.. "Results: " passed " passed, " failed " failed"))
      (do
        (local opencode-path (if (os.getenv "OPENCODE_PATH") (os.getenv "OPENCODE_PATH") "opencode"))
        (local check (process.run (opencode-version-check-options opencode-path)))
        (assert-ok (= check.exit-code 0)
                   (.. "opencode unavailable at " opencode-path ": " (if check.stderr check.stderr "")))
        (print "opencode: " (trim-version check.stdout))

        (local root (.. "/tmp/space/tests/opencode-space-tools-" (os.time) "-" (math.random 0 99999)))
        (var handles {:root root})
        (local (ok err) (pcall #(run-online-verification root handles opencode-path)))
        (cleanup handles)
        (when (not ok)
          (error err)))))

{:main main}
