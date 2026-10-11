---
type: design-spec
tags:
  - spec
  - llm
  - mcp
  - opencode
---

# Shared OpenCode MCP Bridge Core Design

## Purpose

Space currently has three OpenCode MCP bridge implementations that use the same
mechanism but expose different tool surfaces and permission policies:

- internal Space Agent bridge: `assets/lua/llm/agent/opencode-mcp-bridge.fnl`
- external unit bridge: `assets/lua/llm/external-unit-mcp/bridge.fnl`
- Fennel validation bridge: `assets/lua/llm/fennel-validation/bridge.fnl`

The goal is to extract the duplicated bridge mechanism into one shared,
policy-neutral core so future internal and external agents can get isolated
OpenCode MCP configs without copying bridge lifecycle code.

## Scope

In scope:

- loopback MCP HTTP server startup and shutdown;
- `mcp/server-http` construction with `:force-sse true` by default;
- isolated OpenCode config root creation;
- generated `opencode/opencode.json` writing;
- remote MCP server config entry generation;
- `XDG_CONFIG_HOME` environment exposure for OpenCode;
- bridge status, config path, and refresh behavior;
- compatibility wrappers for the three existing bridge modules;
- tests proving config shape, lifecycle, and permission policy preservation.

Out of scope:

- merging internal/external/Fennel tool registries;
- changing tool names, services, risk labels, or approval behavior;
- changing MCP protocol handling or HTTP/SSE transport internals;
- changing global `~/.config/opencode`;
- adding native OpenCode permissions;
- unifying `AgentMcpSync` and `PresetMcpSync`.

## Current design problem

All three bridge modules repeat the same structural work:

1. ensure data and config directories exist;
2. start an MCP HTTP server on loopback with an ephemeral port;
3. turn that port into `http://host:port/mcp`;
4. write an isolated OpenCode config containing one remote MCP server;
5. expose `opencode-env`, `status`, and `stop` methods;
6. clean up partially started servers after startup failures.

The differences are policy/configuration parameters rather than transport
mechanics:

| Bridge | MCP key | Config directory | Native OpenCode permissions |
| --- | --- | --- | --- |
| Internal Space Agent | `space` | `opencode-mcp-config` | bounded Space runtime read/list/grep/glob/external-directory; sensitive-looking paths denied; write/edit/bash/etc. denied |
| External Unit MCP | `space-unit-dev` | `external-unit-opencode-config` | all native tools denied |
| Fennel Validation MCP | `space-fennel-validation` | `fennel-validation-opencode-config` | read/list/grep/glob allowed; write/edit/bash/web/external-directory/etc. denied |

Keeping separate implementations would make every future agent copy the same
mechanism again and increases the risk of permission drift, config drift, or
inconsistent lifecycle behavior.

## Chosen approach

Create a shared core module, tentatively:

```text
assets/lua/llm/opencode-mcp/bridge.fnl
```

The core owns only the OpenCode-facing MCP bridge mechanism. Existing modules
become thin wrappers that compute their policy and call the core.

### Public core API

The core exports `OpencodeMcpBridge`:

```fennel
(local Bridge (require :llm/opencode-mcp/bridge))

(Bridge.OpencodeMcpBridge
  {:name "ExternalUnitMcpBridge"
   :tools registry
   :data-dir data-dir
   :config-dir-name "external-unit-opencode-config"
   :mcp-key "space-unit-dev"
   :permissions native-tool-permissions
   :host "127.0.0.1"})
```

Required options:

- `:name` — human-readable name used in error messages;
- `:tools` — MCP tool registry/server surface;
- `:data-dir` — bridge-owned data root;
- `:config-dir-name` — generated config subdirectory under `data-dir`;
- `:mcp-key` — key under generated OpenCode `mcp` config;
- `:permissions` — permission map or function returning a permission map.

Optional options:

- `:host` — default `127.0.0.1`;
- `:http-server-factory` — test seam, defaults to `http_server.HttpServer`;
- `:mcp-server-factory` — test seam, defaults to `mcp/server-http` with
  supplied tools and `:force-sse true`;
- `:force-sse` — default `true`;
- `:status-extra` — function merged into `status` for wrapper-specific fields.

Methods returned by the core:

- `start(self)`;
- `stop(self)`;
- `opencode-env(self)` returning `{:XDG_CONFIG_HOME config-root}`;
- `refresh-config!(self)` rewriting the current generated config;
- `config-path(self)`;
- `status(self)`.

### Generated config shape

The core writes:

```fennel
{:permission permissions
 :mcp {mcp-key {:type "remote"
                :url url
                :enabled true}}}
```

The core must not know what any permission entry means; wrappers are responsible
for deriving exact maps.

## Wrapper responsibilities

### Internal Space Agent bridge

`assets/lua/llm/agent/opencode-mcp-bridge.fnl` remains the owner of:

- `space-owned-roots` derivation;
- sensitive-path deny pattern generation;
- bounded permission map generation;
- artifact-root creation;
- `refresh-opencode-provider!`;
- public constructor name `AgentOpencodeMcpBridge`.

It delegates only lifecycle/config writing to the shared core. The existing
`main.fnl` call site must continue to work unchanged.

### External unit bridge

`assets/lua/llm/external-unit-mcp/bridge.fnl` remains the public module for
external unit sessions. It passes:

- `:config-dir-name "external-unit-opencode-config"`
- `:mcp-key "space-unit-dev"`
- the existing all-deny permission map.

It must retain the note that this bridge is separate from the internal Space
Agent bridge and must not import or mutate the internal agent bridge.

### Fennel validation bridge

`assets/lua/llm/fennel-validation/bridge.fnl` remains the public module for
read-only validation sessions. It passes:

- `:config-dir-name "fennel-validation-opencode-config"`
- `:mcp-key "space-fennel-validation"`
- the existing read-only permission map.

It must continue to expose only validation tools through its own registry.

## Error handling

- Starting an already-started bridge raises an explicit error.
- Calling `opencode-env` or `refresh-config!` before start raises an explicit
  error.
- Invalid or non-positive MCP server port after start raises an explicit error.
- Startup failures stop the partially created server and clear partial runtime
  state so retry is safe.
- `stop` is idempotent enough for shutdown paths: if no server is active, it
  clears runtime state and returns the bridge.

## Compatibility requirements

- Existing require paths and constructor names keep working.
- Existing generated config directory names are preserved.
- Existing MCP keys are preserved.
- Existing permission maps are preserved exactly.
- Existing bridge status fields used by tests/callers remain available.
- Existing OpenCode provider construction with `{:env (bridge:opencode-env)}`
  continues to receive only the generated `XDG_CONFIG_HOME` value.

## Testing strategy

Add a focused shared-core test module:

```text
assets/lua/tests/test-opencode-mcp-bridge.fnl
```

It should use fake HTTP/MCP factories to verify:

- start binds `127.0.0.1` on port `0`;
- generated URL is `http://127.0.0.1:<port>/mcp`;
- `opencode/opencode.json` contains the supplied MCP key and permissions;
- `opencode-env` returns the generated config root;
- `refresh-config!` rewrites config using current URL;
- failed start calls server stop and resets partial state;
- `status-extra` adds wrapper-specific fields without overriding core fields.

Existing wrapper tests must continue to verify each wrapper's generated config:

- `assets/lua/tests/test-agent-layer.fnl`
- `assets/lua/tests/test-external-unit-mcp.fnl`
- `assets/lua/tests/test-fennel-validation-mcp.fnl`

Because this is Fennel runtime work, validation must follow the Space Fennel
ladder:

1. compile check first (`make fennel-check`, or touched-file check during fix
   loops);
2. constraints second (`make constraints`);
3. focused tests for the new shared core and all three wrappers;
4. broader suite when finishing because app bootstrap/runtime bridge behavior is
   touched.

## Risks

- **Permission drift:** the highest risk. Tests must load generated JSON and
  assert exact policy shapes for each wrapper.
- **Internal startup regression:** `main.fnl` starts the internal bridge during
  app bootstrap. Preserve public constructor and status behavior.
- **Over-generalization:** the core must not gain knowledge of Space Agent,
  external units, Fennel validation, approvals, or app roots.
- **Config key drift:** changing `space`, `space-unit-dev`, or
  `space-fennel-validation` would break existing OpenCode MCP connections.
- **Fennel syntax churn:** keep the shared core small and move policy helpers
  into wrappers to avoid deeply nested forms.

## Acceptance criteria

- One shared bridge core owns the duplicated MCP/OpenCode config mechanism.
- All three existing bridge modules delegate to the core but retain their public
  APIs and policies.
- Internal, external unit, and Fennel validation tool surfaces remain separate.
- Generated OpenCode configs remain isolated and do not touch global OpenCode
  configuration.
- Tests prove lifecycle behavior and permission/config preservation.
- Documentation describes the new mechanism boundary without implying that tool
  surfaces or approval policies were unified.
