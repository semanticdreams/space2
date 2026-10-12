---
type: dev-note
tags:
  - note
---

# Remote MCP Integration

## Overview

Space exposes MCP tools over a small HTTP server backed by `cpp-httplib`. The MCP protocol logic stays in Fennel, while C++ owns sockets, request copying, SSE chunking, and main-thread dispatch.

```
opencode  <->  HTTP/SSE (/mcp)  <->  C++ http_server binding  <->  Fennel MCP handler/tools
```

The normal MCP HTTP handler supports direct POST requests. OpenCode integration opts into `:force-sse true`, which returns 500 before an SSE stream exists so opencode falls back to its SSE transport. That rejection happens before MCP request handling, so failed Streamable HTTP probes do not create sessions or run tools.

## Current Design

### Main-Thread Lua Dispatch

HTTP worker threads never call Lua directly. A route handler copies request data into a pending call, blocks on a condition variable, and waits for `lua_http_server_dispatch` to run on the Lua thread.

Dispatch runs from:

- `Engine::run` via `dispatch_lua_work`
- `callbacks.run-loop`, so CLI tests and tools can service HTTP requests without app frames

This keeps synchronous HTTP semantics without sharing Lua state across threads.

### Transport Modes

- Direct mode: `MCPHTTPServer {:http-server ... :tools ...}` registers POST `/mcp` only and returns regular JSON-RPC HTTP responses.
- OpenCode SSE mode: `MCPHTTPServer {:http-server ... :tools ... :force-sse true}` also registers GET `/mcp`, emits the MCP `endpoint` event, pushes responses over SSE, and sends `notifications/tools/list_changed`.
- The SSE `endpoint` event includes a generated `sessionId` query parameter. OpenCode's SSE transport posts follow-up JSON-RPC messages to that endpoint instead of carrying `Mcp-Session-Id` headers, so the handler accepts both `Mcp-Session-Id` and `sessionId`.

Route registration still happens before `listen()`, and the C++ binding fails loudly if callers register routes after listen or call listen twice. SSE is registered only for `force-sse` because same-path POST/GET behavior in `cpp-httplib` is fragile and should not affect direct HTTP tests.

### Stream Lifecycle

Only one active MCP SSE stream is supported. A reconnect closes the previous stream and removes the previous tool-change listener before installing a new one. `stop` also removes the listener and closes the stream. The raw C++ HTTP server also tracks active SSE streams, closes them on `HttpServer:stop`, and dispatches stream-close callbacks back onto the Lua thread so the Fennel wrapper can clear stale connection state without worker threads touching Lua.

Reconnect sends a fresh `endpoint` event and `notifications/tools/list_changed`, so an opencode reconnect rehydrates the current Space tool list without waiting for another tool mutation.

### Sessions

Session IDs come from the native `uuid.v4` binding. Sessions track `created` and `last-seen` timestamps and are pruned on request handling after the default one-hour TTL.

`llm/providers/opencode/server.fnl` pumps `callbacks.run-loop` while waiting for `opencode serve` to print its listening URL. OpenCode probes remote MCP servers during startup; without dispatching the Space HTTP server queue, that probe can fail before the test/tool services it.

### Production Hardening

- `MCPHTTPServer:status()` exposes connection diagnostics: running host/port, SSE connection/reconnect counts, active session id, POST/method counters, list_changed count/timestamp, last error, tool count, and tool namespace prefix.
- MCP servers reject non-loopback binds by default. Passing `:allow-non-loopback true` is required for `0.0.0.0` or other non-local hosts.
- OpenCode-facing registries should use `ToolRegistry {:namespace-prefix "space_"}`. The registry validates tool names, non-empty descriptions, object schemas, and namespace prefixes before registration.
- The MCP server writes structured logs through the `mcp` logger for start/stop, Streamable HTTP rejection, POST handling, SSE connect/reconnect, and list_changed notifications.

## Files

### C++

- `external/cpp-httplib/httplib.h`: vendored header-only HTTP server
- `src/lua_http_server.cpp`: HTTP server binding, request queue, SSE stream, main-thread dispatch
- `src/lua_http_server.h`: binding and dispatch declarations
- `src/lua_callbacks.cpp`: dispatches pending HTTP server calls in `callbacks.run-loop`
- `src/engine.cpp`: dispatches pending HTTP server calls in the engine frame loop
- `src/lua_runtime.cpp`: registers `http_server`

### Fennel

- `assets/lua/mcp/protocol.fnl`: JSON-RPC helpers
- `assets/lua/mcp/tool-registry.fnl`: mutable tool registry and change listeners
- `assets/lua/mcp/handler.fnl`: MCP initialize, tools/list, tools/call, sessions
- `assets/lua/mcp/server-http.fnl`: HTTP/SSE transport wrapper
- `assets/lua/tools/mcp-remote-server.fnl`: server entrypoint for opencode SSE mode; it requires the app bootstrap-owned `app.mcp-tools` registry rather than installing stub tools
- `assets/lua/tools/external-unit-mcp-server.fnl`: standalone external unit-development MCP server entrypoint
- `assets/lua/llm/external-unit-mcp/service.fnl`: loader-neutral unit operations
- `assets/lua/llm/external-unit-mcp/tools.fnl`: external unit MCP tool definitions
- `assets/lua/llm/external-unit-mcp/bridge.fnl`: loopback server and isolated OpenCode config

## Internal vs. External MCP Registries

Space has two separate MCP tool registries exposed through different server
entrypoints. Both bind loopback by default and use the same MCP HTTP/SSE
transport, but they serve different audiences with different tool sets.

### Internal Agent MCP Server

`assets/lua/tools/mcp-remote-server.fnl` (module `tools.mcp-remote-server:main`)

- Serves the app bootstrap-owned `app.mcp-tools` registry.
- Registry uses `ToolRegistry {:namespace-prefix "space_"}`.
- Tools are registered by the preset system (`llm/presets/builtins/`) and
  adapt to the current app context (scene, canvas, graph, drawing).
- The Space agent uses this surface for runtime operations: scene manipulation,
  canvas drawing, graph navigation, unit management, file and shell access.
- Internal agent tools include `space_unit_*` tools from
  `llm/presets/builtins/units.fnl` that expect the full app runtime.

### External Unit MCP Server

`assets/lua/tools/external-unit-mcp-server.fnl` (module `tools.external-unit-mcp-server:main`)

- Creates its own standalone `ToolRegistry` with namespace prefix `space_`.
- Tools are registered from `llm/external-unit-mcp/tools.fnl`.
- Exposes loader-neutral unit development tools: `space_unit_resolve`,
  `space_unit_inspect`, `space_unit_read_source`, `space_unit_apply_patch`,
  `space_unit_create_source`, `space_unit_run_tests`, `space_unit_reload`,
  `space_unit_read_log`, `space_unit_snapshot`, `space_unit_list`.
- Uses `ExternalUnitMcpBridge` (`llm/external-unit-mcp/bridge.fnl`) which
  writes an **isolated** OpenCode config into a temporary directory and prints
  `OPENCODE_XDG_CONFIG_HOME=<path>` (a label; the caller must set
  `XDG_CONFIG_HOME` to that path).
- Does **not** mutate global `~/.config/opencode`.
- Denies all native tool permissions (filesystem, shell, web, etc.) in the
  generated config so external sessions can only use `space_unit_*` MCP tools.
- Headless engine — no graphics window.

### Shared Infrastructure

Both servers reuse the same infrastructure:
- `mcp/tool-registry.fnl` for tool registration and change notifications
- `mcp/protocol.fnl` for JSON-RPC helpers
- `mcp/handler.fnl` for MCP lifecycle (initialize, tools/list, tools/call)
- `mcp/server-http.fnl` for HTTP/SSE transport
- C++ `http_server` binding for loopback HTTP and main-thread dispatch

OpenCode-facing bridge wrappers also delegate common bridge mechanics to
`assets/lua/llm/opencode-mcp/bridge.fnl`. That shared module owns loopback MCP
server lifecycle and generated OpenCode config writing, but it does not own tool
registries or permission policy derivation. The internal Space Agent, external
unit MCP, and Fennel validation MCP surfaces keep separate wrappers, registries,
MCP config keys, and native OpenCode permission profiles.

## Tests

- `assets/lua/tests/test-mcp.fnl`: protocol, tool registry, contract validation, and registry status
- `assets/lua/tests/test-http-server.fnl`: HTTP server binding, lifecycle guards, SSE delivery/cleanup
- `assets/lua/tests/test-mcp-http.fnl`: direct HTTP MCP integration, status diagnostics, loopback guard, SSE reconnect/list_changed behavior, and force-SSE pre-stream rejection
- `assets/lua/tests/test-mcp-live.fnl`: opencode live integration, gated by `MCP_LIVE_TESTS=1`
- `assets/lua/tests/test-external-unit-mcp.fnl`: external unit MCP service, tools, bridge, and integration tests

Live tests write opencode config under an isolated `/tmp/space/tests/opencode-mcp-live-*` `XDG_CONFIG_HOME`; they no longer mutate the user’s real `~/.config/opencode`.

## Known Issues

1. Single active SSE stream; concurrent opencode clients conflict.
2. `force-sse` relies on opencode continuing to fall back from Streamable HTTP to SSE after a 500.
3. Live tool-change discovery is verified through a model prompt after `notifications/tools/list_changed`; OpenCode does not expose remote MCP tools through `/experimental/tool/ids`.

## Test Commands

```bash
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-mcp-http:main
```

```bash
MCP_LIVE_TESTS=1 \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-mcp-live:main
```

## See also

- [External Unit MCP](./external-unit-mcp)
- [OpenCode MCP Bridge Guide](./opencode-mcp-bridges)
- [Agent Presets](./agent-presets)
- [Agent Tools](/dev/features/agent-tools), [Agent Runner System](/dev/features/agent-runner-system)
