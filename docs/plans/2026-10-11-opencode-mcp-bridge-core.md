# Shared OpenCode MCP Bridge Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the duplicated OpenCode MCP bridge mechanism into a shared policy-neutral core while preserving the internal Space Agent, external unit, and Fennel validation bridge contracts.

**Architecture:** Add `llm/opencode-mcp/bridge.fnl` as the single owner of loopback MCP server lifecycle, isolated OpenCode config writing, `XDG_CONFIG_HOME` environment exposure, refresh, and status. Keep the three existing bridge modules as thin wrappers that provide MCP key, config directory name, tool registry, status extras, and exact native OpenCode permission policy.

**Tech Stack:** Space Fennel, `mcp/server-http`, `http_server`, `json-utils`, existing MCP `ToolRegistry`, generated OpenCode `opencode.json`, Space Fennel validation and test runtime.

## Global Constraints

- Preserve existing public constructors: `AgentOpencodeMcpBridge`, `ExternalUnitMcpBridge`, and `FennelValidationMcpBridge`.
- Preserve existing MCP config keys: `space`, `space-unit-dev`, and `space-fennel-validation`.
- Preserve existing generated config directory names: `opencode-mcp-config`, `external-unit-opencode-config`, and `fennel-validation-opencode-config`.
- Preserve existing native OpenCode permission semantics exactly for all three bridges.
- Do not merge internal, external unit, or Fennel validation tool registries, services, approval policies, or risk labels.
- Do not mutate or depend on global `~/.config/opencode`.
- Keep `:force-sse true` as the default bridge MCP server mode.
- Bind bridge servers to loopback by default with `127.0.0.1`.
- Use project-native validation only: `make fennel-check`, `make constraints`, and focused Space test modules.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- If `./build/space` is missing or stale, run `make build` with timeout `14400000` before direct test commands.

---

## File Structure

- Create `assets/lua/llm/opencode-mcp/bridge.fnl`
  - Shared bridge core with no Space Agent, external unit, or Fennel validation policy knowledge.
  - Owns `start`, `stop`, `opencode-env`, `refresh-config!`, `config-path`, and `status`.
- Create `assets/lua/tests/test-opencode-mcp-bridge.fnl`
  - Focused offline tests for the shared bridge using fake server factories.
- Modify `assets/lua/tests/fast.fnl`
  - Register the new shared-core bridge test.
- Modify `assets/lua/llm/external-unit-mcp/bridge.fnl`
  - Replace duplicated lifecycle/config code with the shared core while preserving all-deny permissions and public API.
- Modify `assets/lua/llm/fennel-validation/bridge.fnl`
  - Replace duplicated lifecycle/config code with the shared core while preserving read-only permissions and public API.
- Modify `assets/lua/llm/agent/opencode-mcp-bridge.fnl`
  - Keep internal policy helpers and provider refresh helper; delegate lifecycle/config mechanics to the shared core.
- Modify existing tests as needed:
  - `assets/lua/tests/test-agent-layer.fnl`
  - `assets/lua/tests/test-external-unit-mcp.fnl`
  - `assets/lua/tests/test-fennel-validation-mcp.fnl`
- Modify docs after code behavior is stable:
  - `docs/dev/notes/remote-mcp.md`
  - `docs/dev/notes/external-unit-mcp.md`
  - `docs/dev/features/fennel-agent-reliability.md`

---

### Task 1: Shared OpenCode MCP Bridge Core

**Files:**
- Create: `assets/lua/llm/opencode-mcp/bridge.fnl`
- Create: `assets/lua/tests/test-opencode-mcp-bridge.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `fs`, `json-utils`, optional `http-server-factory`, optional `mcp-server-factory`, and the existing `mcp/server-http` constructor shape.
- Produces: `OpencodeMcpBridge(opts)` returning a bridge table with methods `start`, `stop`, `opencode-env`, `refresh-config!`, `config-path`, and `status`.

- [ ] **Step 1: Add a focused failing test module for core lifecycle**

  Create `assets/lua/tests/test-opencode-mcp-bridge.fnl` with fake factories. The fake MCP server object should record `start` and `stop` calls:

  ```fennel
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
             (set state.stop-count (+ (or state.stop-count 0) 1)))})

  (fn load-config [path]
    (json.loads (fs.read-file path)))
  ```

  Add a test named `shared bridge writes isolated opencode config` that:

  - creates a temporary directory;
  - constructs `Bridge.OpencodeMcpBridge` with `:name "TestBridge"`, `:tools {}`, `:data-dir root`, `:config-dir-name "test-opencode-config"`, `:mcp-key "space-test"`, `:permissions {:read "deny" :write "deny"}`, and the fake factories;
  - calls `bridge:start`;
  - asserts the fake server was started with host `127.0.0.1` and port `0`;
  - asserts `(bridge:opencode-env).XDG_CONFIG_HOME` equals `<root>/test-opencode-config`;
  - loads `<root>/test-opencode-config/opencode/opencode.json`;
  - asserts `config.permission.read == "deny"` and `config.permission.write == "deny"`;
  - asserts `config.mcp.space-test.type == "remote"`, `config.mcp.space-test.enabled == true`, and `config.mcp.space-test.url == "http://127.0.0.1:41237/mcp"`;
  - calls `bridge:stop` and asserts the fake server stop count is `1`.

- [ ] **Step 2: Add focused failing tests for refresh, status extras, and failure cleanup**

  In the same test module, add tests named:

  - `shared bridge refresh rewrites current config`
  - `shared bridge status merges wrapper extras`
  - `shared bridge cleans up failed start`

  Required assertions:

  ```fennel
  ;; refresh rewrites config and returns config-path/url metadata
  (local result (bridge:refresh-config!))
  (assert (= result.url "http://127.0.0.1:41237/mcp"))
  (assert (= result.config-path (bridge:config-path)))

  ;; status extras are present but core fields still win
  (local status (bridge:status))
  (assert (= status.started? true))
  (assert (= status.kind "unit-test"))
  (assert (= status.port 41237))

  ;; failure cleanup calls stop and clears runtime state
  (local failed
    (Bridge.OpencodeMcpBridge
      {:name "FailingBridge"
       :tools {}
       :data-dir root
       :config-dir-name "failing-opencode-config"
       :mcp-key "space-failing"
       :permissions {:read "deny"}
       :http-server-factory (fn [] {})
       :mcp-server-factory (fn [_http]
                             {:start (fn [_self _host _port] 0)
                              :stop (fn [_self]
                                      (set state.stop-count (+ (or state.stop-count 0) 1)))})}))
  (local (ok err) (pcall failed.start failed))
  (assert (not ok))
  (assert (= state.stop-count 1))
  (assert (= (failed:status).started? false))
  (assert (= (failed:status).port nil))
  ```

  The failure fake server should return `0` from `start` so the core raises an invalid-port error after server construction.

- [ ] **Step 3: Register the test module in `assets/lua/tests/fast.fnl`**

  Add `:tests.test-opencode-mcp-bridge` to the fast suite list near other MCP/agent tests so it runs in normal focused coverage.

- [ ] **Step 4: Implement the shared core**

  Create `assets/lua/llm/opencode-mcp/bridge.fnl` with helper functions named
  `ensure-dir!`, `remote-url`, `config-path`, `write-opencode-config!`,
  `resolve-permissions`, `merge-status`, and `OpencodeMcpBridge`.

  Implementation rules:

  - assert required options with explicit messages using the supplied `:name` where useful;
  - create config root as `(fs.join-path data-dir config-dir-name)`;
  - create the generated config at `(fs.join-path config-root "opencode" "opencode.json")`;
  - default `:host` to `"127.0.0.1"`;
  - default `:force-sse` to `true`;
  - default `:http-server-factory` to a function requiring `:http_server` and returning `(HttpServer)`;
  - default `:mcp-server-factory` to a function requiring `:mcp/server-http` and returning `(MCPHTTPServer {:http-server http-server :tools tools :force-sse force-sse})`;
  - `start` must reject double start, ensure directories, create server, call `server:start host 0`, verify returned port is positive, write config, set state, and return `self`;
  - `stop` must call `server:stop` when a server exists, then clear server, port, url, and `started?`;
  - `opencode-env` must error before start and return only `{:XDG_CONFIG_HOME config-root}` after start;
  - `refresh-config!` must error before start, rewrite config with current URL and current permissions, and return `{:config-path config-path-value :url current-url}`;
  - `status` must expose `:started?`, `:host`, `:port`, `:url`, `:config-root`, and `:config-path`, plus wrapper extras from `status-extra` without allowing extras to override those core fields.

- [ ] **Step 5: Run Task 1 validation**

  Run in this order:

  ```bash
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-opencode-mcp-bridge:main
  ```

  If `./build/space` is missing, run `make build` first with timeout `14400000`.

- [ ] **Step 6: Commit Task 1**

  Commit only Task 1 files:

  ```bash
  git add assets/lua/llm/opencode-mcp/bridge.fnl assets/lua/tests/test-opencode-mcp-bridge.fnl assets/lua/tests/fast.fnl
  git commit -m "refactor(lua): add shared OpenCode MCP bridge core"
  ```

---

### Task 2: External Unit and Fennel Validation Bridge Wrappers

**Files:**
- Modify: `assets/lua/llm/external-unit-mcp/bridge.fnl`
- Modify: `assets/lua/llm/fennel-validation/bridge.fnl`
- Test: `assets/lua/tests/test-external-unit-mcp.fnl`
- Test: `assets/lua/tests/test-fennel-validation-mcp.fnl`

**Interfaces:**
- Consumes: `OpencodeMcpBridge(opts)` from `llm/opencode-mcp/bridge.fnl`.
- Produces unchanged constructors `ExternalUnitMcpBridge(opts)` and `FennelValidationMcpBridge(opts)`.

- [ ] **Step 1: Replace external unit lifecycle code with shared core delegation**

  Keep the module comment stating this bridge is separate from the internal agent bridge. Keep the local all-deny permission map exactly as current behavior:

  ```fennel
  (local native-tool-permissions
    {:invalid "deny"
     :read "deny"
     :write "deny"
     :edit "deny"
     :grep "deny"
     :glob "deny"
     :list "deny"
     :bash "deny"
     :task "deny"
     :external_directory "deny"
     :todowrite "deny"
     :webfetch "deny"
     :websearch "deny"
     :lsp "deny"
     :skill "deny"
     :question "deny"})
  ```

  Implement `ExternalUnitMcpBridge` as a wrapper that asserts `:tools` and `:data-dir`, then returns:

  ```fennel
  (Core.OpencodeMcpBridge
    {:name "ExternalUnitMcpBridge"
     :tools tools
     :data-dir data-dir
     :config-dir-name "external-unit-opencode-config"
     :mcp-key "space-unit-dev"
     :permissions native-tool-permissions
     :host (or opts.host "127.0.0.1")
     :http-server-factory opts.http-server-factory
     :mcp-server-factory opts.mcp-server-factory})
  ```

- [ ] **Step 2: Replace Fennel validation lifecycle code with shared core delegation**

  Keep the read-only permission map exactly as current behavior:

  ```fennel
  (local native-tool-permissions
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
  ```

  Implement `FennelValidationMcpBridge` as a wrapper that asserts `:tools` and `:data-dir`, then returns:

  ```fennel
  (Core.OpencodeMcpBridge
    {:name "FennelValidationMcpBridge"
     :tools tools
     :data-dir data-dir
     :config-dir-name "fennel-validation-opencode-config"
     :mcp-key "space-fennel-validation"
     :permissions native-tool-permissions
     :host (or opts.host "127.0.0.1")
     :http-server-factory opts.http-server-factory
     :mcp-server-factory opts.mcp-server-factory})
  ```

- [ ] **Step 3: Preserve and extend wrapper config tests**

  In `test-external-unit-mcp.fnl`, ensure the bridge test still asserts:

  ```fennel
  (assert config.mcp.space-unit-dev)
  (assert (= config.mcp.space-unit-dev.url status.url))
  (assert (= config.permission.read "deny"))
  (assert (= config.permission.write "deny"))
  (assert (= config.permission.bash "deny"))
  (assert (= config.permission.external_directory "deny"))
  ```

  In `test-fennel-validation-mcp.fnl`, ensure the bridge test still asserts:

  ```fennel
  (assert config.mcp.space-fennel-validation)
  (assert (= config.mcp.space-fennel-validation.url status.url))
  (assert (= config.permission.read "allow"))
  (assert (= config.permission.grep "allow"))
  (assert (= config.permission.glob "allow"))
  (assert (= config.permission.list "allow"))
  (assert (= config.permission.write "deny"))
  (assert (= config.permission.bash "deny"))
  ```

  Add assertions for `bridge:config-path` only if the shared core now exposes it on these wrappers and the assertion does not change public compatibility expectations.

- [ ] **Step 4: Run Task 2 validation**

  Run in this order:

  ```bash
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-external-unit-mcp:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fennel-validation-mcp:main
  ```

- [ ] **Step 5: Commit Task 2**

  Commit only Task 2 files:

  ```bash
  git add assets/lua/llm/external-unit-mcp/bridge.fnl assets/lua/llm/fennel-validation/bridge.fnl assets/lua/tests/test-external-unit-mcp.fnl assets/lua/tests/test-fennel-validation-mcp.fnl
  git commit -m "refactor(lua): reuse bridge core for standalone MCP tools"
  ```

---

### Task 3: Internal Space Agent Bridge Wrapper

**Files:**
- Modify: `assets/lua/llm/agent/opencode-mcp-bridge.fnl`
- Test: `assets/lua/tests/test-agent-layer.fnl`

**Interfaces:**
- Consumes: `OpencodeMcpBridge(opts)` from `llm/opencode-mcp/bridge.fnl`.
- Produces unchanged constructor `AgentOpencodeMcpBridge(opts)` and unchanged helper `refresh-opencode-provider!(providers bridge)`.

- [ ] **Step 1: Keep internal policy helpers in the agent bridge module**

  Preserve these responsibilities in `llm/agent/opencode-mcp-bridge.fnl`:

  - `normalize-root`
  - `join-pattern`
  - `space-owned-roots`
  - sensitive runtime path deny pattern generation
  - `bounded-permission-map`
  - `native-tool-permissions`
  - `refresh-opencode-provider!`

  Do not move these policy helpers into `llm/opencode-mcp/bridge.fnl`.

- [ ] **Step 2: Delegate bridge lifecycle to the shared core**

  Refactor `AgentOpencodeMcpBridge` so `start` computes `allowed-roots`, creates `artifact-root` when present, and constructs the core with:

  ```fennel
  (Core.OpencodeMcpBridge
    {:name "AgentOpencodeMcpBridge"
     :tools tools
     :data-dir data-dir
     :config-dir-name "opencode-mcp-config"
     :mcp-key "space"
     :permissions (fn [] (native-tool-permissions allowed-roots))
     :host host
     :http-server-factory http-server-factory
     :mcp-server-factory mcp-server-factory
     :status-extra (fn [] {:artifact-root artifact-root
                           :allowed-roots allowed-roots})})
  ```

  Preserve public methods by forwarding to the core:

  - `start`
  - `stop`
  - `opencode-env`
  - `refresh-config!`
  - `config-path`
  - `status`

  Ensure `status` still includes `:artifact-root` and `:allowed-roots` exactly as current tests expect.

- [ ] **Step 3: Preserve provider refresh behavior**

  Keep `refresh-opencode-provider!` behavior unchanged:

  - require `providers` and `bridge`;
  - close and remove old `providers.opencode` when present;
  - call `bridge:refresh-config!`;
  - call `providers.opencode-factory`;
  - store the new provider in `providers.opencode`;
  - return the new provider.

- [ ] **Step 4: Preserve and strengthen internal bridge tests**

  In `test-agent-layer.fnl`, ensure existing bridge tests still assert:

  ```fennel
  (assert config.mcp.space)
  (assert (= config.mcp.space.url status.url))
  (assert (= (. config.permission.write) "deny"))
  (assert (= (. config.permission.bash) "deny"))
  (assert status.artifact-root)
  (assert status.allowed-roots)
  (assert (= (bridge:config-path) status.config-path))
  ```

  Add a focused assertion that `bridge:refresh-config!` returns the same `config-path` and current `url` after the core extraction.

- [ ] **Step 5: Run Task 3 validation**

  Run in this order:

  ```bash
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-layer:main
  ```

- [ ] **Step 6: Commit Task 3**

  Commit only Task 3 files:

  ```bash
  git add assets/lua/llm/agent/opencode-mcp-bridge.fnl assets/lua/tests/test-agent-layer.fnl
  git commit -m "refactor(lua): reuse bridge core for Space Agent MCP"
  ```

---

### Task 4: Documentation and Final Validation

**Files:**
- Modify: `docs/dev/notes/remote-mcp.md`
- Modify: `docs/dev/notes/external-unit-mcp.md`
- Modify: `docs/dev/features/fennel-agent-reliability.md`

**Interfaces:**
- Consumes: final module layout from Tasks 1-3.
- Produces: docs describing the shared mechanism without implying shared tool surfaces or shared policies.

- [ ] **Step 1: Update `docs/dev/notes/remote-mcp.md`**

  Add a section or bullet describing `assets/lua/llm/opencode-mcp/bridge.fnl` as the shared OpenCode MCP bridge mechanism. State explicitly:

  - it owns loopback server lifecycle and generated OpenCode config writing;
  - it does not own tool registries or permission policy derivation;
  - internal Space Agent, external unit MCP, and Fennel validation MCP still use separate registries and wrappers.

- [ ] **Step 2: Update `docs/dev/notes/external-unit-mcp.md`**

  Keep existing internal/external separation language. Add one concise note:

  ```markdown
  `ExternalUnitMcpBridge` delegates common OpenCode bridge mechanics to
  `llm/opencode-mcp/bridge.fnl`, but keeps its own `space-unit-dev` MCP key,
  all-deny native OpenCode permission policy, and external unit tool registry.
  ```

- [ ] **Step 3: Update `docs/dev/features/fennel-agent-reliability.md`**

  Add one concise note that the Fennel validation MCP bridge uses the shared
  OpenCode bridge mechanism while remaining read-only and preserving the
  existing validation tool list.

- [ ] **Step 4: Run docs-focused searches**

  Run:

  ```bash
  rg "opencode-mcp/bridge|space-unit-dev|space-fennel-validation|mcp\.space" docs/dev assets/lua
  ```

  Review the matches and confirm the docs do not claim the tool registries,
  approval policies, or permission profiles are merged.

- [ ] **Step 5: Run final local validation**

  Because this refactor touches app bootstrap-adjacent Fennel and bridge runtime
  behavior, run:

  ```bash
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-opencode-mcp-bridge:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-external-unit-mcp:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fennel-validation-mcp:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-layer:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  If `./build/space` is missing or stale because C++/runtime prerequisites changed, run `make build` first with timeout `14400000`.

- [ ] **Step 6: Commit Task 4**

  Commit docs and any final test-list updates only after validation passes:

  ```bash
  git add docs/dev/notes/remote-mcp.md docs/dev/notes/external-unit-mcp.md docs/dev/features/fennel-agent-reliability.md
  git commit -m "docs: describe shared OpenCode MCP bridge core"
  ```

---

## Plan Self-Review

- Spec coverage: all spec requirements map to Tasks 1-4. Task 1 creates the core, Tasks 2-3 preserve wrappers and policies, Task 4 updates docs and runs final validation.
- Placeholder scan: this plan contains no unresolved placeholder sections.
- Type consistency: the shared core API is consistently named `OpencodeMcpBridge`; wrapper constructor names remain unchanged; method names match the design spec.
- Validation order: compile check precedes constraints, and constraints precede focused tests for Fennel-facing work.
