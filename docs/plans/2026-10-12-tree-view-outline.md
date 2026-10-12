# Reusable TreeView Graph Outline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace graph outline's fixed-stride row placement with a reusable measured `TreeView` widget while preserving current graph outline behavior.

**Architecture:** Build a generic old-widget-stack `TreeView` that flattens caller-provided tree data and lays out measured row widgets. Graph outline adapts its `GraphMap` projection into `TreeView` and uses a graph-specific row widget that owns compact graph node presentations, labels, expanded cards, and teardown. `TreeView` remains graph-agnostic.

**Tech Stack:** Space Fennel, old `Layout`/widget builder conventions, `Flex`/layout primitives where useful, `CompactNodeProjection`, `GraphNodePresentation`, graph projection runtime, project-native Fennel validation.

## Global Constraints

- Build a reusable Fennel `TreeView` widget for hierarchical row layout.
- Replace graph outline fixed-stride row placement with widget-driven measured layout.
- Preserve graph outline behavior by default: all reachable outline rows remain visible unless a later feature explicitly opts into collapsed defaults.
- Keep graph-specific interaction semantics out of the generic tree widget.
- Graph core persists topology only.
- `GraphMap` owns `view_mode`, `outline_root_keys`, `selected_node_keys`, and `focused_node_key`.
- Outline rows are visual projection state, not topology or domain data.
- Compact graph node presentations own graph node click, focus, selection, menu, activation, and teardown semantics.
- Do not port outline rendering to `next-app` in this pass.
- Do not introduce virtualized tree rendering yet.
- Do not persist tree expansion state in graph core or `GraphMap`.
- Do not change graph topology traversal semantics or outline root semantics.
- Do not make the generic tree widget aware of graph maps, graph nodes, selectors, focus managers, or graph commands.
- For Fennel-facing work, run compile checks before constraints, then focused Fennel tests.

---

## File Structure

- Create `assets/lua/tree-view.fnl`: generic old-widget-stack tree view builder with adapter callbacks, visible row flattening, measured row layout, expansion state, and lifecycle methods.
- Create `assets/lua/tests/test-tree-view.fnl`: graph-free tests for tree flattening, expansion, row metadata, variable row measurement/layout, and drop guards.
- Create `assets/lua/graph/view/outline-row-widget.fnl`: graph-specific outline row composite that owns compact projection, label, optional expanded card, and direct teardown.
- Modify `assets/lua/graph/view/outline.fnl`: replace fixed row positioning/row handle construction with `TreeView` and `outline-row-widget` integration while keeping graph projection runtime and graph-map state ownership.
- Modify `assets/lua/tests/test-graph-outline-view.fnl`: focused outline behavior and layout regression tests.
- Modify `assets/lua/tests/e2e/test-graph-outline-view.fnl`: E2E interaction/snapshot checks for outline row visual placement and click routing.
- Modify `docs/dev/features/tree-view-widget.md`: reusable widget contract and ownership documentation.
- Modify `docs/dev/notes/graph.md`: graph doctrine note that outline row layout delegates to `TreeView` while graph state remains graph-owned.

---

### Task 1: Generic TreeView Widget and Tests

**Files:**
- Create: `assets/lua/tree-view.fnl`
- Create: `assets/lua/tests/test-tree-view.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: old widget `Layout` conventions from `assets/lua/layout.fnl`.
- Produces: `(TreeView opts) -> builder`, where the built widget exposes `refresh`, `set-roots`, `set-expanded`, `expanded?`, `visible-rows`, and `drop`.
- Produces row metadata tables: `{:key string :item any :depth number :index number :parent-key string|nil :expanded? boolean :has-children? boolean :toggle! function}`.

- [ ] **Step 1: Write failing depth-first flattening test.** In `test-tree-view.fnl`, create a test named `TreeView flattens expanded tree depth first`. Use roots `[{ :id "a" :children [{:id "b"} {:id "c"}]}]`, `:key (fn [item] item.id)`, `:children (fn [item] (or item.children []))`, `:default-expanded? (fn [_row] true)`, and a row builder that records row keys/depths. Assert `visible-rows` returns keys `a,b,c` with depths `0,1,1`.

- [ ] **Step 2: Run the new test and verify RED.** Command:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-tree-view:main
```

Expected: failure because `tree-view` cannot be required or `TreeView` is not defined.

- [ ] **Step 3: Implement minimal `TreeView` builder skeleton.** In `tree-view.fnl`, assert required `:roots`, `:key`, `:children`, and `:row-builder`. Build a widget with explicit `Layout`, local `roots`, internal `expanded-keys`, and `visible-rows` method. Implement a pure `flatten-visible-rows` helper that depth-first traverses expanded roots and constructs row metadata.

- [ ] **Step 4: Write failing expansion tests.** Add `TreeView toggles internal expansion state` and `TreeView supports caller-owned expanded keys`. Verify collapsed roots hide descendants, `set-expanded "a" true` reveals descendants, and caller-owned `expanded-keys` plus `on-expanded-change` receives `"a" false` when toggled.

- [ ] **Step 5: Implement expansion methods.** Add `expanded?`, `set-expanded`, and row `toggle!`. For caller-owned state, read `opts.expanded-keys` and call `opts.on-expanded-change key next-expanded?`; for internal state, mutate the widget's internal expansion lookup. `:default-expanded?` decides missing keys.

- [ ] **Step 6: Write failing measured layout test.** Add `TreeView lays out variable height row widgets`. Create row widgets with `layout.measure.y` values `6`, `10`, and `4`, set `:row-gap 2`, run the tree layout, and assert y positions are stacked by measured heights and gap rather than a fixed global stride.

- [ ] **Step 7: Implement row widget creation and layout.** `refresh` rebuilds owned row widgets from `visible-rows`; `layout:measurer` sums child measured heights plus gaps; `layout:layouter` assigns each child layout position based on measured heights and row gap. Drop prior child widgets before rebuilding.

- [ ] **Step 8: Write failing lifecycle tests.** Add `TreeView drops owned rows exactly once` and `TreeView methods fail after drop`. Use row widgets with counters; assert `drop` calls each child once and `visible-rows`, `refresh`, and `set-expanded` fail after drop with `TreeView` and `called after drop` in the error text.

- [ ] **Step 9: Implement lifecycle guards.** Track `dropped?`, add `assert-not-dropped`, make public methods call it, and make `drop` terminal. Ensure row widget drops happen before layout drop.

- [ ] **Step 10: Register test module.** Add `tests.test-tree-view` to `assets/lua/tests/fast.fnl` so it participates in fast/full suites.

- [ ] **Step 11: Validate Task 1.** Run:

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tree-view.fnl --file assets/lua/tests/test-tree-view.fnl --file assets/lua/tests/fast.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-tree-view:main
```

---

### Task 2: Graph Outline Row Widget

**Files:**
- Create: `assets/lua/graph/view/outline-row-widget.fnl`
- Modify: `assets/lua/tests/test-graph-outline-view.fnl`

**Interfaces:**
- Consumes: `CompactNodeProjection.attach!`, `CompactNodeProjection.drop!`, `GraphNodePresentation.card-builder`, `Text`, `Layout`, and graph outline row metadata.
- Produces: `(OutlineRowWidget opts) -> builder`, where the built row widget exposes `refresh`, `set-row`, `point`, `selectable`, `focus-node`, `expanded?`, `expand!`, `collapse!`, and `drop`.
- Produces callback contract: graph outline passes `:on-focus`, `:on-right-click`, `:on-activate`, `:on-collapse`, `:on-open`, `:on-menu`, and `:selected?` / `:focused?` predicates.

- [ ] **Step 1: Write failing row measurement test.** In `test-graph-outline-view.fnl`, add `outline row widget measures compact point and label`. Build an outline row widget with a graph node size `8`, label text, and a test render context. Assert the row layout measured height is at least the compact point visible size and less than the old fixed `24` stride for a compact row with normal text.

- [ ] **Step 2: Write failing row interaction ownership test.** Add `outline row widget keeps compact projection interaction owner`. Simulate compact point click through the row widget's point and assert focus/selection callbacks are invoked through `CompactNodeProjection`, not through row background or whitespace.

- [ ] **Step 3: Implement `outline-row-widget.fnl` skeleton.** Create a builder that asserts required dependencies (`ctx`, `row`, `clickables`, `selector`, `focus`, `pointer-target`, callbacks). It owns an explicit `Layout`, creates a compact projection, creates a label, and records child handles.

- [ ] **Step 4: Implement compact row measure/layout.** Row measurement derives height from `max(compact visible size, label.layout.measure.y) + vertical padding`. Row layout positions compact point and label through layout transforms, with indentation supplied by `TreeView` row metadata or explicit `depth-indent` option.

- [ ] **Step 5: Write failing expanded row test.** Add `outline row widget expands to measured card height`. Expand a row and assert measured height increases by the expanded card height plus summary/details gap.

- [ ] **Step 6: Implement expand/collapse.** `expand!` drops compact-only registrations that must be replaced, creates an expanded card with `GraphNodePresentation.card-builder`, preserves selector/focus node ownership, and marks layout dirty. `collapse!` drops the expanded card and restores compact projection state.

- [ ] **Step 7: Write failing teardown test.** Add `outline row widget drops compact projection label and expanded card once`. Count drops for compact projection, label, expanded card, focus node, and selector removal; assert one terminal drop.

- [ ] **Step 8: Implement teardown.** `drop` unregisters clickables/selectables through owned compact projection/card handles, drops label/card/compact handles, clears callbacks, drops row layout, and fails loudly if public methods are called after drop.

- [ ] **Step 9: Validate Task 2.** Run:

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/outline-row-widget.fnl --file assets/lua/tests/test-graph-outline-view.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-outline-view:main
```

---

### Task 3: Graph Outline Uses TreeView Layout

**Files:**
- Modify: `assets/lua/graph/view/outline.fnl`
- Modify: `assets/lua/tests/test-graph-outline-view.fnl`
- Modify: `assets/lua/tests/e2e/test-graph-outline-view.fnl`

**Interfaces:**
- Consumes: `TreeView(opts)` from Task 1 and `OutlineRowWidget(opts)` from Task 2.
- Produces: `GraphOutlineView(options) -> view` whose rows are laid out by `TreeView`, not by fixed index stride.

- [ ] **Step 1: Write failing no-fixed-stride regression.** Add `outline rows use measured tree layout instead of fixed stride`. Build an outline with two normal nodes, record their compact point y positions, and assert the vertical distance is less than `24` while still greater than the compact point visible size plus configured row gap. This should fail against the current `row-height 24` implementation.

- [ ] **Step 2: Write failing preservation tests.** Extend existing outline tests to assert visible row order/depth, all reachable rows visible by default, select-all visible nodes, focus sync, context menu, activation, expanded-card collapse/re-expand, and empty-state behavior still pass after TreeView integration.

- [ ] **Step 3: Add graph outline tree adapter.** In `outline.fnl`, convert `GraphOutline.build-rows` output into `TreeView` roots/items while preserving existing row order and depth. Use `:default-expanded? (fn [_row] true)` so current graph outline remains fully visible.

- [ ] **Step 4: Replace row handle construction.** Replace `attach-row-handles!`, direct `row-node-position`, direct label placement, and fixed empty-state placement with a `TreeView` instance whose `row-builder` creates `OutlineRowWidget` builders.

- [ ] **Step 5: Preserve GraphMap state ownership.** Keep `set-outline-selection!`, `sync-selector-selection-to-map!`, `sync-map-selection-to-selector!`, `focus-visible-key!`, and `graph-map.focused_node_key` ownership in `outline.fnl`. Do not move these into `TreeView`.

- [ ] **Step 6: Preserve CompactNodeProjection ownership.** Ensure row click/focus/menu/activation callbacks still flow through `OutlineRowWidget` -> `CompactNodeProjection` -> graph outline callbacks. Row whitespace must not select/focus graph nodes.

- [ ] **Step 7: Preserve runtime lifecycle.** Update outline projection drop to drop the `TreeView` and row widgets once, then let shared runtime drop node views and persistence handles. Ensure rebuilds do not double-drop row widgets or pending focus nodes.

- [ ] **Step 8: Update empty state.** Render empty state through a measured widget or TreeView empty-state child, not fixed rectangle coordinates. Preserve the message text and theme-derived colors.

- [ ] **Step 9: Validate Task 3.** Run:

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/outline.fnl --file assets/lua/graph/view/outline-row-widget.fnl --file assets/lua/tree-view.fnl --file assets/lua/tests/test-graph-outline-view.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-tree-view:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-outline-view:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-view-compact-projection:main
```

---

### Task 4: Documentation, E2E Coverage, and Broad Validation

**Files:**
- Create: `docs/dev/features/tree-view-widget.md`
- Modify: `docs/dev/notes/graph.md`
- Modify: `assets/lua/tests/e2e/test-graph-outline-view.fnl`

**Interfaces:**
- Consumes: completed `TreeView` and graph outline integration.
- Produces: canonical docs and final validation evidence.

- [ ] **Step 1: Document `TreeView`.** Create `docs/dev/features/tree-view-widget.md` with sections for adapter API, row metadata, expansion ownership, row builder contract, layout/measurement behavior, lifecycle/drop ownership, and non-goals.

- [ ] **Step 2: Update graph doctrine docs.** In `docs/dev/notes/graph.md`, state that outline row layout delegates to reusable `TreeView`, while graph topology, outline roots, selected/focused keys, compact graph interactions, and row projection state remain graph-owned.

- [ ] **Step 3: Check docs for ownership drift.** Search the new docs for claims that `TreeView` owns graph topology, graph domain data, GraphMap selection/focus, or graph commands; remove any such claims.

- [ ] **Step 4: Run E2E outline validation.** Because this plan changes visual row placement and click routing boundaries, run the graph outline E2E command outside sandbox per project policy:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test-e2e
```

If E2E cannot run in the current environment, record the exact environment blocker, the command attempted, and the focused unit coverage that protects row placement/click routing until PR CI or a trusted outside-sandbox run can execute it.

- [ ] **Step 5: Run final validation.** Run:

```bash
make fennel-check
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-tree-view:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-outline-view:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

- [ ] **Step 6: Record final evidence.** The implementation report must include compile, constraints, focused tests, E2E status if applicable, full test outcome, and a constraint-impact note.

---

## Acceptance Checklist

- `TreeView` tests prove the widget is reusable without graph dependencies.
- Graph outline no longer computes row positions with hardcoded index stride.
- Graph outline preserves current all-visible default behavior.
- Graph outline selection, focus, context menu, activation, expanded-card behavior, and empty state remain intact.
- Compact point whitespace behavior remains unchanged.
- Docs describe reusable tree view ownership and graph doctrine boundaries.
