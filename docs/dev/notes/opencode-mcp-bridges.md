---
type: dev-note
tags:
  - note
---

# OpenCode MCP Bridge Guide

Use this guide when adding a new Space MCP bridge that should be consumed by an
OpenCode process, whether that process is the in-app Space agent or a separate
developer/validation harness.

## Bridge Shape

Keep the common mechanics in `assets/lua/llm/opencode-mcp/bridge.fnl`:

- starts and stops the loopback MCP HTTP/SSE server;
- chooses the loopback MCP URL written into OpenCode config;
- writes an isolated generated `opencode/opencode.json` under a caller-provided
  data/config root;
- returns the OpenCode environment (`XDG_CONFIG_HOME` plus config content) and
  supports config refresh/status.

Each wrapper owns the policy and product surface:

- the tool registry passed as `:tools`;
- the generated MCP config key, such as `space`, `space-unit-dev`, or
  `space-fennel-validation`;
- native OpenCode permissions;
- wrapper status extras and entrypoint wiring.

Do not put surface-specific tool registration, permission derivation, or agent
policy into the shared bridge core.

## Existing Examples

- Internal Space agent: `assets/lua/llm/agent/opencode-mcp-bridge.fnl` uses the
  app-owned registry (`app.mcp-tools`), key `space`, and bounded native read/list
  permissions for Space-owned runtime paths.
- External unit development: `assets/lua/llm/external-unit-mcp/bridge.fnl` uses a
  standalone unit-development registry, key `space-unit-dev`, and all-deny native
  permissions so access flows through `space_unit_*` MCP tools.
- Fennel validation: `assets/lua/llm/fennel-validation/bridge.fnl` uses key
  `space-fennel-validation` and a narrow read/list/grep/glob policy for
  validation-oriented sessions.

## Internal vs. External Use

Internal bridges may depend on app bootstrap state and Space-owned runtime roots
because the caller is the Space agent inside the running app. External bridges
should be standalone: create their own registry, bind loopback by default, avoid
depending on UI/app context unless the entrypoint explicitly starts it, and avoid
mutating global `~/.config/opencode`.

For external or online harnesses, keep auth and environment isolated. Spawn
OpenCode with `:clear-env true` and construct the child environment explicitly:

- set `XDG_CONFIG_HOME` to the bridge-owned generated config root and provide
  `OPENCODE_CONFIG_CONTENT` from the bridge output;
- set isolated `HOME` and `XDG_DATA_HOME` values under temporary or
  harness-owned roots;
- include only the `PATH` needed to execute OpenCode and its direct helper
  binaries;
- pass only intentionally filtered auth, such as provider-scoped
  `OPENCODE_AUTH_CONTENT`, when a harness needs model access.

Do not inherit the parent process environment wholesale. In particular, do not
forward provider API keys from the developer shell and do not allow the spawned
OpenCode process to read or write the user's normal OpenCode config/data roots.

## Config and Permission Rules

The shared bridge merges `:config-extra` into the generated OpenCode config, but
only for additive provider/model setup. It must not override bridge-owned
`permission` or `mcp` keys; the core rejects those keys so wrappers remain the
single owner of native OpenCode permissions and MCP server identity.

Use OpenCode's native permission policy directly rather than inventing a second
allow/deny layer. For each wrapper, make the native policy match the intended
audience: deny all native tools for tool-only external sessions, or allow only
bounded Space-owned paths for internal sessions that need artifact/log access.

## Validation Checklist

When adding a bridge, add focused coverage for:

- generated config path and MCP key;
- loopback URL/config refresh/status behavior through the shared core;
- native permission policy, including denied native tools and any allowed roots;
- rejection of `config-extra.permission` and `config-extra.mcp` overrides when the
  wrapper exposes `config-extra`;
- entrypoint output/environment labels for external harnesses;
- external/online harness spawn isolation: `:clear-env true`, explicit
  bridge-derived `XDG_CONFIG_HOME`/`OPENCODE_CONFIG_CONTENT`, isolated `HOME` and
  `XDG_DATA_HOME`, minimal required `PATH`, intentionally filtered
  provider-scoped auth, and no inherited provider API keys or normal user
  OpenCode config/data paths;
- live/online tests gated behind explicit environment variables, with temporary
  config/data roots and isolated auth.

Prefer focused bridge/tool tests first. Add live OpenCode coverage only for the
observable integration surface that cannot be validated with the local harness.

## Related Docs

- [Remote MCP Integration](./remote-mcp)
- [External Unit MCP](./external-unit-mcp)
- [Agent Presets](./agent-presets)
- [Fennel Runtime Paths](./fennel-runtime-paths)
