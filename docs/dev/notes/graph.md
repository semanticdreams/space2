---
type: dev-note
tags:
  - note
---

# Graph Core Refactors & Architecture Doctrine

## Doctrine: Graph as exposure layer, not universal store

**The graph is an exposure/adaptor layer — it does not own the objects it exposes.** Domain data lives wherever it naturally belongs: entity data in entity stores (`entities/string/`, `entities/code/`, etc.), activity-owned world surface state in activity sessions, LLM conversations in the LLM store (`llm/`), filesystem nodes on the real filesystem, kernel instances in the kernel system. The graph creates lightweight adapter nodes that project these domain objects into a uniform navigable topology.

**Graph core persists only user-materialized topology** — which visible node keys exist and which visible edge connections exist (`graph:capture-state` / `graph:restore-state`). Owning systems persist the actual object data. There is no "full graph state backup" that captures domain data; `capture-state` stores node keys and edge source/target keys only.

Related objects become graph-visible only through explicit preview, view, search-row, or action controls. A node may offer actions such as `Show Code`, `Open Timeline`, `Show Run Steps`, `Reveal Failed Steps`, `Start`, or a searchable picker that loads a selected key into the current graph map and adds any display edge needed for that user-visible relationship. Dense records such as logs, JSON, inputs, outputs, and errors belong in payload panels or full node views rather than generic detail toggles. Graph code should not rely on hidden relationship expansion hooks to bulk-materialize neighboring records.

### Canonical terminology

| Use | Avoid |
|-----|-------|
| graph-exposed object, graph-visible object | graph-backed object, graph object |
| graph node adapter, projection | first-class graph object |
| entity-store-backed node, world-state-backed node, LLM-store-backed node | backed by the graph |
| graph topology state (node keys + edge keys) | full graph state, graph data, graph node data |
| exposed through the graph, visible in the graph | lives in the graph, stored in the graph |
| graph as universal interface / exposure layer | graph as universal model |
| domain object | graph-native object |

### Key architectural facts

- `graph/core.fnl`: nodes are lightweight records (key, label, color, view ref, graph ref). It exposes low-level primitives such as `graph:register-key-loader`, `create-node-by-key`, and topology capture/restore. `capture-state` stores node keys and edge source/target keys only — no domain data.
- `graph/extension-registry.fnl`: the only node-type installation mechanism for built-ins and user/runtime extensions. Descriptors install owner-safe key-loader and morph handles into live and future world runtimes, then refresh map-local adapters by scheme during reload. See [Reloadable Graph Extension Units](/dev/features/reloadable-graph-extension-units).
- `graph/extensions/builtins/`: family-scoped built-in graph extension descriptors register through the app registry. Their installer functions call the low-level `graph:register-key-loader` primitive to adapt owning stores/systems into graph nodes on demand via `load-by-key`; they do not own or persist domain records. Entity descriptors adapt entity stores; LLM descriptors adapt the LLM store; workflow descriptors adapt workflow stores; world activity and surface descriptors adapt `world-manager` and `WorldData`.
- `graph/map.fnl`: graph maps hold the visible topology a user has materialized in that interaction context. Preview/search/action code loads keys through the active `GraphMap` and inserts explicit display edges when the user asks to reveal related records.
- Graph presentation islands are map-local presentation state over graph-exposed objects. `GraphMap` persists island records, while `GraphView` hosts presenters by kind. Presenter kinds such as `ordered-list` must not make domain stores subordinate to graph view; domain stores remain the source of truth for domain data.
- `graph/world-data.fnl`: activity-owned scene/HUD/canvas state is resolved from `world.state.activity.sessions.<activity-id>` through `WorldData` helpers. Activity-owned graph keys include both `world-id` and `activity-id` (for example `activity-scene:<world-id>:<activity-id>`, `activity-background:<world-id>:<activity-id>`, and `activity-terrain:<world-id>:<activity-id>:<terrain-id>`). Updates mutate the owning activity surface state, then sync to the active surface and persist world. Graph nodes are projections, not the source of truth.
- Activity hierarchy keys expose `world:<world-id>` → `world-activities:<world-id>` → `world-activity:<world-id>:<activity-id>` → `activity-surfaces:<world-id>:<activity-id>` before reaching concrete surface nodes such as scene, HUD, or canvas.
- `graph/nodes/*.fnl`: node constructors receive stores/world-manager, resolve domain records from them, and emit signals when underlying data changes.
- `graph/view/`: owns visual/interactive systems (ForceLayout, points, labels, selection, movables, persistence metadata). Graph nodes do not track view instances.

### Preview vs UX node vs full view

Previews expose compact state, high-frequency local actions, and short search/list controls. They are appropriate for status summaries, small action rows, revealing one selected related node, opening a focused UX node, or opening a full view/panel.

UX-purpose graph nodes expose one focused operation/detail surface and own no domain records. They are graph-addressable adapters over owning stores or systems, such as workflow step explorers or run timelines, and they materialize related topology only through explicit user actions.

- Filesystem file content follows the same exposure-layer rule: `fs:<path>` remains the generic path adapter, regular files expose explicit interaction rows, and `fs-file-viewer:<absolute-path>` is a UX-purpose node that reads only bounded windows. See [Graph Filesystem File Interactions](/dev/features/graph-filesystem-file-interactions).

Full node views and panels handle dense content, long payloads, and editor-style interactions. Source code, logs, JSON, Fennel forms, multiline errors, inputs, and outputs belong in these views rather than in single-line preview labels.

Graph-selection actions must read active `GraphMap` selection, validate accepted node types, and fail loudly or display explicit graph-native status on invalid selection. Destructive actions must be explicit graph actions rather than confirmation-dialog flows.

### Kind badges

Graph node adapters may expose `kind-badge` presentation metadata for preview-card and full node-view titlebars. Missing metadata derives compact badge text from a stable key scheme before the first `:` when one exists; explicit `false` opts out. Graph core and GraphMap persistence still capture topology only: node keys, edge source/target keys, and map-local interaction state. Badge text and colors remain render-time presentation metadata and must not be written into graph topology state.

## Extracted
- Graph model: `graph/core` owns nodes/edges, add/remove/replace, and emits signals (`node-added`, `node-removed`, `node-replaced`, `edge-added`, `edge-removed`).
- Graph view: `graph/view` (`GraphView`) owns ForceLayout, points, labels, selection, movables, persistence, and node dialogs. It listens to graph signals and can be dropped/recreated without touching the graph model.
- Persistence: `graph/view/persistence` handles metadata load/save and scheduled writes.
- Labels and LOD: `graph/view/labels` (`GraphViewLabels`) manages label creation, LOD switching, camera-distance debounce, positioning, and cleanup.
- Selection: `graph/view/selection` (`GraphViewSelection`) owns selector wiring, selected-node bookkeeping, pruning, and signals.
- Node view wiring: `graph/view/node-views` (`GraphViewNodeViews`) builds/drops node dialogs or HUD embeds.
- Movables: `graph/view/movables` (`GraphViewMovables`) builds drag targets, registers/unregisters with `app.movables`, forwards position updates, and schedules persistence on drag end.
- Layout and edges: `graph/view/layout` (`GraphViewLayout`) wraps `ForceLayout`, line updates, node positioning, and rebuilds.
- View registry: `graph/view/registry` (`GraphViewRegistry`) centralizes view-only bookkeeping (indices, node/point maps, edge map), replacement, and deduping.
- Utils split: `graph/core/utils` holds core-only helpers (glm vec coercion). `graph/view/utils` adds view helpers (label text truncation/wrapping) and re-exports the core glm helpers.

## Label and LOD handling
- Core now forwards node→point maps to `graph/view/labels` to build spans and reposition them based on camera distance; tune LOD thresholds and label styling there instead of in core.
- Benefits: keeps HUD text concerns and camera logic out of core; makes it easier to tune LOD thresholds separately.

## Selection and node views
- Selection is owned by `graph/view` + `graph/view/selection`; update behavior there when changing selector policies or selection logging.
- Node dialogs are handled by `graph/view/node-views`; tweak dialog builders or HUD embedding there without touching the graph model.
- Graph nodes **do not track view instances**. Nodes expose a plain `:view` constructor (e.g. `:view HackerNewsStoryView`) and emit state via signals (`rows-changed`, `items-changed`, `targets-changed`, etc.). Views subscribe to those signals (or call node methods like `fetch`, `open-entry`, `add-target`) and stay UI-only so multiple views can hang off the same node.

## What stays in core
- Graph model: adding/removing/replacing visible nodes/edges and lifecycle (`drop`).
- No visual state: layout, labels, selection, movables, points, or persistence belong in `graph/view`.

## See also

- [Graph Foundation](/dev/features/graph-foundation), [Graph as Universal Interface](/dev/adrs/adr-graph-as-universal-model)
- [Reloadable Graph Extension Units](/dev/features/reloadable-graph-extension-units)
