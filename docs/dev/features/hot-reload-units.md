---
type: feature
status: shipped
parent-goal: core-platform
tags:
  - feature
  - hot-reload
  - live-development
created: 2026-07-14
updated: 2026-10-15
---

# Hot reload and reloadable units

## Summary

Live Fennel/Lua development reloads use native file watching (efsw), module/cache
invalidation and load/unload/snapshot/restore lifecycles. **Controller reloads
default to app-root**, rebuilding the Fennel app inside the existing native
process. A lifecycle unit is not automatically an independent reload boundary.
The [canonical reload contract](/dev/reloadable-units) defines eligibility,
author/reviewer obligations, entry points and recovery limits.

## Motivation

Live development should pick up edited code without a native restart while
preserving supported shell state. Whole-app reload is the supported baseline;
smaller boundaries need an audited consumer/cleanup contract, not just path ownership.

## Design

- **Lifecycle API** (`assets/lua/units.fnl`): `load`, `unload` and optional
  `snapshot`, `restore`; direct calls remain caller-managed.
- **Controller** (`assets/lua/hot-reload.fnl`): owned paths/common ancestors select
  a candidate, then eligibility selects the final target before module collection
  or lifecycle mutation. Omitted/empty `narrow-reload-unit-ids` means root-only;
  opt-ins record an audit, not automatic certification. Main defers watcher reload
  through a callback; explicit `reload-now!` is synchronous.
- **Inventory**: app-root; `hud`, `canvas`, `sandbox-activity`, `graph-activity`,
  `drawing-activity`, `board-activity`; and filesystem-discovered `user-<name>`
  units. All six built-in leaves are siblings under app-root and lifecycle-only
  by default. Direct/explicit opt-in fixtures are experimental evidence. The
  [graph-extension seam](/dev/features/reloadable-graph-extension-units) has a
  specific narrow contract, not blanket graph-code eligibility.
- **Discovery** (`main.fnl`): immediate `app.code-dir/<name>.fnl` or
  `<name>/init.fnl`, directory preferred on collision. Watch roots are configured
  separately; the default assets Lua root does not include user code. Discovery
  does not certify independent replacement.
- **Recovery**: controller failures attempt same-target tracked-module and
  snapshot recovery, not parent escalation or atomic rollback of globals,
  external effects or pending work. Manager/agent/MCP direct operations do not
  inherit this policy or recovery wrapper.

## Tasks

- [x] Unit API with load/unload/snapshot/restore
- [x] efsw-based file watcher with change routing
- [x] Controller lifecycle reload with best-effort same-target recovery
- [x] Fennel cache clearing on reload
- [x] User code directory scanner
- [x] Subdirectory init.fnl support
- [x] Root-only default and explicit audited narrow eligibility

## Related

- Goal: [Core Platform](/dev/features/core-platform)
- See: [Reloadable Units](/dev/reloadable-units)
- See: [Lifecycle Centralization](/dev/lifecycle-centralization) — ownership is a prerequisite, not freshness proof
