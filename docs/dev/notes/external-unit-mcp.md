---
type: dev-note
tags:
  - note
---

# External Unit MCP

## Overview

External unit MCP is a separate Space-owned MCP surface that lets external
OpenCode sessions develop user units through Space MCP tools instead of direct
filesystem edits. The subsystem lives under `assets/lua/llm/external-unit-mcp/`
with a standalone entrypoint at `assets/lua/tools/external-unit-mcp-server.fnl`.

```
external opencode  <->  HTTP/SSE  <->  ExternalUnitMcpBridge  <->  ExternalUnitService
                                        (isolated config)           (loader-neutral)
```

The external bridge writes an isolated OpenCode configuration into a temporary
directory and prints the environment variables the external OpenCode session
must use. It never mutates global `~/.config/opencode`.

## Separation from Internal Agent MCP

Space has two distinct MCP registries and two separate tool surfaces:

| Surface | Registry | Tools Location | Audience |
|---------|----------|---------------|----------|
| Internal agent MCP | `app.mcp-tools` (bootstrap-owned) | `llm/presets/builtins/units.fnl`, scene, drawing, graph adapters | Space's own agent |
| External unit MCP | Standalone `ToolRegistry` | `llm/external-unit-mcp/tools.fnl` | External OpenCode sessions |

The internal registry serves the Space agent's runtime context (scene
manipulation, canvas drawing, graph navigation, app-level operations) through
`app.mcp-tools`. Preset-based tools like `space_unit_list`, `space_unit_edit`,
and `space_unit_apply_patch` exposed through internal presets
(`llm/presets/builtins/units.fnl`) are internal Space agent tools and expect the
full app runtime.

The external registry serves external user-unit development and exposes
loader-neutral operations (`space_unit_resolve`, `space_unit_inspect`,
`space_unit_read_source`, `space_unit_apply_patch`, `space_unit_create_source`,
`space_unit_run_tests`, `space_unit_reload`, `space_unit_read_log`,
`space_unit_snapshot`, `space_unit_list`) through
`llm/external-unit-mcp/tools.fnl`.

`ExternalUnitMcpBridge` delegates common OpenCode bridge mechanics to
`llm/opencode-mcp/bridge.fnl`, but keeps its own `space-unit-dev` MCP key,
all-deny native OpenCode permission policy, and external unit tool registry.

Do not add Space-specific user-unit behavior to global `~/.config/opencode`.

## Starting the Server

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tools.external-unit-mcp-server:main
```

The server boots a headless engine, creates a temporary data directory for the
isolated OpenCode config, starts a loopback HTTP/SSE MCP server, and prints:

```
MCP_URL=http://127.0.0.1:<port>/mcp
OPENCODE_XDG_CONFIG_HOME=/tmp/ext-unit-mcp-server-<...>/external-unit-opencode-config
```

The server prints `OPENCODE_XDG_CONFIG_HOME=` as a label; the OpenCode process
itself reads the standard `XDG_CONFIG_HOME` environment variable. See the next
section for how to connect.

## Connecting an External OpenCode Session

The server prints `OPENCODE_XDG_CONFIG_HOME=<path>` as a label; the actual
environment variable OpenCode consumes is `XDG_CONFIG_HOME`. Point an
external OpenCode session at the printed config root without modifying global
`~/.config/opencode`:

```bash
XDG_CONFIG_HOME=<printed-config-root> opencode ...
```

The bridge writes an isolated `opencode.json` inside that directory that:
- Denies all native tool permissions (filesystem, shell, web, etc.)
- Enables only the `space-unit-dev` MCP server pointing at the loopback URL

The external session only has access to the `space_unit_*` MCP tools. It cannot
read arbitrary files or run arbitrary commands through the host.

## Resolution Workflow

External unit development follows this high-level workflow:

1. **`space_unit_list`** — List all external units with loader-neutral handles.
2. **`space_unit_resolve`** — Find a unit by natural-language description;
   returns ranked candidates.
3. **`space_unit_inspect`** — Inspect a unit by id: loader, source artifacts,
   lifecycle exports (init/drop/snapshot/restore), and edit/test capabilities.
4. **Read source** — `space_unit_read_source` returns the content of a source
   artifact and its current hash.
5. **Edit source** — `space_unit_apply_patch` applies an edit (exact replacement
   or unified diff patch) with optional stale-content detection via
   `expected_hash`. `space_unit_create_source` creates a new source file inside
   a directory-based unit.
6. **Test** — `space_unit_run_tests` runs tests for a unit by executing its test
   module in a subprocess.
7. **Reload** — `space_unit_reload` triggers a reload of the unit to reflect
   its current source state and reports active activity reactivation evidence
   when an activity was active before reload.
8. **Read log** — `space_unit_read_log` reads recent lines from the application
   log with optional filtering and pagination.
9. **Snapshot** — `space_unit_snapshot` captures a unit's current state for
   inspection. Capture alone does not establish a supported migration or recovery
   contract.

## Safety Model

### Editing safety is not reload isolation

The checks below protect source editing and tool access, not arbitrary runtime
replacement. External `space_unit_reload`, and the automatic reload after patch
or create, call `UnitManager:reload-unit` directly. **They do not pass through the
hot-reload controller** and do not inherit root-only routing,
`narrow-reload-unit-ids`, callback deferral or controller module/snapshot backup.
Internal agent tools are also direct operations, but have different edit helpers
and parameters (`id` internally versus `unit_id` externally).

Direct manager reload uses the unit's loader-specific invalidation: a ModuleUnit
clears remembered owned modules/caches, while a SourceUnit discards its evaluated
module table. Neither replaces every consumer retaining old functions or factories.
Outside a specific tested boundary contract, direct replacement is caller-managed
and experimental. See the [canonical entry-point and recovery comparison](/dev/reloadable-units#recovery-and-distinct-entry-points).

External patch failure paths attempt to restore the original file and then try
a recovery reload; create failure attempts to remove the new file, without an
equivalent recovery reload. Some recovery errors are suppressed by the service,
so an error saying source was restored is not proof of a healthy runtime. Explicit
reload has no edit backup. These are operation-specific best-effort actions, not
atomic runtime restoration: globals, external effects and in-flight work may
remain changed. Inspect evidence/logs and use an enclosing reload or restart when
needed; a later watcher event cannot retroactively protect a direct operation.

### Loopback-Only Binding

The external MCP server binds to `127.0.0.1` by default. Non-loopback binds are
disabled.

### Isolated OpenCode Config

The bridge writes an isolated config that denies all native tool permissions
(filesystem, shell, web, etc.). External OpenCode sessions cannot read arbitrary
files, write outside the bridge-managed config, or run commands.

### Stale-Content Protection

`space_unit_apply_patch` supports an optional `expected_hash` parameter. When
provided, the patch is rejected if the file's current hash no longer matches.
This prevents concurrent edits from silently overwriting each other.

### Path Containment

All source read/write operations resolve source-ids relative to the unit root
and enforce path containment. Source-ids must be relative, must not contain
`..` segments or NUL bytes, and must not escape the unit directory. Symlink
ancestors and targets are rejected.

### Loader Capability Checks

Tools fail loudly when a loader lacks a requested capability. For example,
non-filesystem loaders cannot read or write source files.

### Risk Labels

Each external tool carries a risk label (`normal`, `filesystem-read`,
`filesystem-write`, `shell`, `destructive`) exported via `get-tool-risks`.

## Common Local Storage Is Not the Contract

`app.code-dir` — the Space user-data code directory — is common local storage
where user units happen to live today. It is an implementation detail, not the
external contract. The external tools operate on unit handles and source-ids,
not on raw filesystem paths.

External OpenCode sessions must never construct paths into `app.code-dir`.
Future units may be backed by database records, remote hosts, generated stores,
or other loaders.

## Direct Filesystem Edits

Direct filesystem edits are an escape hatch only. The external MCP tools
(`space_unit_apply_patch`, `space_unit_create_source`, `space_unit_read_source`)
are the supported editing path. Direct filesystem edits skip stale-content
protection, path containment, and reload integration.

If an external OpenCode session must use native filesystem tools, that requires
explicit human approval and a Space-reported local filesystem source handle.

## Tool Reference

### space_unit_list

List all external units with loader-neutral handles. Returns `unit-id`, `loader`,
`source-handle`, `edit-capabilities`, `test-capabilities`, and `commit-capability`
for each unit. Sorted by unit-id.

### space_unit_resolve

Resolve a unit from a natural-language description. Accepts:
- `description` (string, required): natural-language description to match
- `limit` (integer, optional): max candidates to return (default 20)

Returns ranked candidates with `unit-id`, `confidence` (0.0–1.0), and `evidence`.
Matches against unit id, module name, and source file basenames.

### space_unit_inspect

Inspect a unit by id. Accepts `unit_id` (string, required). Returns:
- `unit-id`, `loader`
- `source-handle` with `source-id`, `kind`, `primary`, `size`, `hash`
- `lifecycle` with `init`, `drop`, `snapshot`, `restore` export names
- `source-artifacts` listing all source files with hashes

### space_unit_read_source

Read the content of a unit source artifact. Accepts:
- `unit_id` (string, required)
- `source_id` (string, required): the source artifact identifier

Returns `unit-id`, `source-id`, `content` (the file text), and `hash`
(sha256-prefixed).

### space_unit_apply_patch

Apply an edit to a unit source file. Accepts:
- `unit_id` (string, required)
- `source_id` (string, required)
- `patch` (string): a unified diff patch
- `old` (string): exact text to find and replace
- `new` (string): replacement text
- `expected_hash` (string, optional): reject patch if file hash differs

Exactly one of `patch` or `old`+`new` must be provided. The unit is
automatically reloaded after a successful patch. On reload failure, the service
attempts original-source restoration and a recovery reload. On patch-apply failure
in diff mode it also attempts source restoration. See the recovery limits above;
these attempts do not establish a transaction over runtime state.

### space_unit_create_source

Create a new source file inside a directory-based unit. Accepts:
- `unit_id` (string, required)
- `source_id` (string, required): new file name relative to unit root
- `source` (string, required): file content

Rejects overwriting existing files. Creates parent directories as needed.
Validates Fennel source before writing. The unit is reloaded after creation.
On reload failure, removal of the new file is attempted; this path does not also
attempt a recovery reload.

### space_unit_run_tests

Run tests for a unit. Accepts:
- `unit_id` (string, required)
- `test_name` (string, optional): test suffix name (default: "init")

Executes `<module-name>.test-<test-name>:main` in a subprocess with a
headless engine. Returns `passed`, `exit-code`, `stdout`, and `stderr`.

### space_unit_reload

Reload a unit to reflect its current source state. Accepts `unit_id` (string,
required). Returns structured reload evidence:

- `unit-id`
- `reloaded`
- `activity.active-activity-before`
- `activity.active-activity-after`
- `activity.reactivation-attempted`
- `activity.registered-after?`
- `activity.has-active-session-after?`
- `activity.error` when reactivation fails

Successful `space_unit_apply_patch` and `space_unit_create_source` responses also
include `reload-result` and `activity` fields from the post-write reload.

### space_unit_read_log

Read recent lines from the application log. Accepts:
- `grep` (string, optional): filter lines containing this substring
- `lines` (integer, optional): number of recent lines (default 100)
- `offset` (integer, optional): start from this line number
- `limit` (integer, optional): max lines when using offset

The response never exposes the raw native log-path through the external API.

### space_unit_snapshot

Capture a unit's current state. Accepts `unit_id` (string, required). Returns
`unit-id`, `supported` (bool), and `state` if supported. This external surface does
not expose a corresponding restore tool or promise versioned state migration.

## Architecture

### Service Layer (`llm/external-unit-mcp/service.fnl`)

`ExternalUnitService` wraps `UnitManager` and provides loader-neutral operations:
unit listing, inspection, resolution (token-based matching), source
reading/writing/patching, test execution, log reading, and snapshot capture.

Internal helpers handle:
- `classify-loader` — maps unit source type to loader name ("filesystem" for
  user units with owned paths)
- `derive-source-artifacts` — enumerates files from owned-paths with hashes
- `resolve-source-path` — safe file path resolution with containment checks
  and symlink rejection
- `validate-fnl-source` — compiles Fennel source to catch syntax errors early

### Tools Layer (`llm/external-unit-mcp/tools.fnl`)

Wraps the service in MCP tool definitions using `ToolRegistry` with namespace
prefix `space_`. Each tool carries a risk label.

### Bridge Layer (`llm/external-unit-mcp/bridge.fnl`)

`ExternalUnitMcpBridge` owns the loopback MCP HTTP server and isolated OpenCode
configuration. It:
- Creates a temporary data directory
- Starts an HTTP/SSE MCP server on a random loopback port
- Writes an isolated `opencode.json` denying all native permissions
- Exposes `status()` for connection diagnostics and `opencode-env()` for the
  environment variables an external session must use

### Standalone Entrypoint (`tools/external-unit-mcp-server.fnl`)

Boots a headless engine, initializes app dirs, loads user code units, creates
the service and tool registry, starts the bridge, prints the connection
environment, and enters the run loop.

## Files

### Fennel

- `assets/lua/llm/external-unit-mcp/service.fnl` — loader-neutral unit operations
- `assets/lua/llm/external-unit-mcp/tools.fnl` — MCP tool definitions
- `assets/lua/llm/external-unit-mcp/bridge.fnl` — loopback server and isolated config
- `assets/lua/tools/external-unit-mcp-server.fnl` — standalone entrypoint

### Tests

- `assets/lua/tests/test-external-unit-mcp.fnl` — service, tools, bridge, and
  integration tests

## Test Command

```bash
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-external-unit-mcp:main
```

## See also

- [Remote Mcp](./remote-mcp)
- [Agent Presets](./agent-presets)
- [Reloadable Units](/dev/reloadable-units)
