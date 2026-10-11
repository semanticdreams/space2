# Graph Projection Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor spatial GraphView and GraphOutlineView so they share a formal graph projection runtime/lifecycle contract while retaining separate projection behavior and separate mode-specific camera/view state.

**Architecture:** Keep `assets/lua/graph/view.fnl` as the mode dispatcher and keep `GraphMap.view_mode` as the projection selector. Add shared graph-view runtime and selection/focus helper modules under `assets/lua/graph/view/`, then migrate outline and spatial projections onto that runtime without moving outline into its own activity.

**Tech Stack:** Space Fennel modules, existing `GraphMap`, `GraphViewPersistence`, `GraphViewNodeViews`, `FocusedActions`, `CompactNodeProjection`, project-native validation through `tools.fennel-check`, constraints, and Fennel tests.

## Global Constraints

- Keep `GraphMap` as the owner of graph-map interaction state: `view_mode`, `outline_root_keys`, `selected_node_keys`, and `focused_node_key`.
- Keep graph topology and domain data out of view/runtime persistence.
- Make spatial and outline projections share graph-view lifecycle mechanisms through one explicit runtime contract.
- Keep projection-specific behavior separate: spatial layout/edges/islands/LOD and outline row/compact-point layout should remain in their projection modules.
- Keep spatial and outline camera/view state separate while using the same capture/restore mechanism.
- Preserve existing graph commands and graph activity behavior.
- Do not move outline into a separate activity in this pass.
- Do not change graph topology, graph persistence, key loaders, or graph terminology.
- For Fennel-facing work, run compile checks before constraints, then focused Fennel tests.

---

## File Structure

- Create `assets/lua/graph/view/runtime.fnl`: shared runtime shell for graph-view lifecycle, camera methods, capture/restore, node-view wiring, persistence access, drop guards, and common node actions.
- Create `assets/lua/graph/view/projection-selection.fnl`: adapter-based selection/focus command implementation shared by spatial and outline projections.
- Modify `assets/lua/graph/view/persistence.fnl`: add canonical mode-specific view state and mode-specific camera state while loading legacy top-level spatial camera data.
- Modify `assets/lua/graph/view/outline.fnl`: keep row/compact-point projection logic, but consume runtime and shared selection/focus helpers.
- Modify `assets/lua/graph/view/init.fnl`: keep spatial layout, labels, islands, movables, and LOD logic, but consume runtime and shared selection/focus helpers.
- Modify `assets/lua/graph/view/focused-actions.fnl`: expose generic focused-action dependencies usable by both projections.
- Modify `assets/lua/graph-activity-unit.fnl`: consume required runtime contract methods instead of spatial-only persistence internals or optional camera hooks.
- Modify `docs/dev/notes/graph.md` and `docs/dev/graph-maps.md`: document projection runtime, mode-specific view state, and unchanged GraphMap ownership.

---

### Task 1: Mode-Specific Camera Persistence and Contract Tests

**Files:**
- Modify: `assets/lua/graph/view/persistence.fnl`
- Modify: `assets/lua/tests/test-graph-view-camera-persistence.fnl`
- Modify: `assets/lua/tests/test-graph-outline-view.fnl`

**Interfaces:**
- Consumes: existing `GraphViewPersistence {:data-dir string :map-id string}`.
- Produces: `(persistence:saved-mode-camera-state mode) -> table|nil`, `(persistence:set-mode-camera-state mode camera-state) -> true`, and canonical persisted field `view_modes` keyed by mode string.

- [ ] **Step 1: Write failing legacy migration test.** Add `legacy-camera-loads-as-spatial-mode-camera` to `test-graph-view-camera-persistence.fnl`. Write a metadata JSON file with top-level `camera`, instantiate `GraphViewPersistence`, and assert both `saved-camera-state` and `saved-mode-camera-state "spatial"` return the same camera position.

- [ ] **Step 2: Write failing independent mode camera test.** Add `mode-camera-states-are-independent` to `test-graph-view-camera-persistence.fnl`. Save spatial camera position `[1 2 100]` and outline camera position `[20 30 80]`, reload persistence, and assert each mode returns its own value.

- [ ] **Step 3: Write failing malformed mode camera test.** Add `malformed-mode-camera-fails-loudly`. Write `{:view_modes {"outline" {:camera {:position [1 "bad" 3]}}}}`, instantiate persistence in `pcall`, and assert failure text includes `GraphViewPersistence` and `camera`.

- [ ] **Step 4: Write failing outline contract test.** Add `outline-view-exposes-shared-runtime-camera-contract` to `test-graph-outline-view.fnl`. Construct an outline `GraphView` and assert these fields are functions: `saved-camera-state`, `capture-camera-state!`, and `apply-initial-camera-policy!`.

- [ ] **Step 5: Implement mode camera persistence.** In `graph/view/persistence.fnl`, load `persisted.view_modes` as a table, validate each mode entry as a table, validate each mode camera with the existing camera validation, and expose legacy top-level `camera` as spatial mode camera when `view_modes.spatial.camera` is absent.

- [ ] **Step 6: Add persistence methods.** Implement `saved-mode-camera-state` and `set-mode-camera-state`. Both methods assert `mode` is a string. The setter creates the mode table when absent, stores a cloned camera state at `view_modes[mode].camera`, sets `pending-save?`, and returns `true`.

- [ ] **Step 7: Preserve legacy aliases.** Keep `saved-camera-state` and `set-camera-state` as spatial-mode aliases so existing spatial behavior remains compatible.

- [ ] **Step 8: Register tests.** Insert the new test records into the existing `tests` arrays with exact names from Steps 1-4.

- [ ] **Step 9: Validate.**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/persistence.fnl --file assets/lua/tests/test-graph-view-camera-persistence.fnl --file assets/lua/tests/test-graph-outline-view.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-view-camera-persistence:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-outline-view:main
```

---

### Task 2: Shared Runtime and Selection Helper Modules

**Files:**
- Create: `assets/lua/graph/view/runtime.fnl`
- Create: `assets/lua/graph/view/projection-selection.fnl`
- Modify: `assets/lua/graph/view/focused-actions.fnl`
- Modify: `assets/lua/tests/test-graph-outline-view.fnl`
- Modify: `assets/lua/tests/test-graph-view.fnl`

**Interfaces:**
- Consumes: `GraphViewNodeViews`, `GraphViewPersistence`, `ActivityCameraState`, and `FocusedActions.install!`.
- Produces: `(Runtime.init! view options projection) -> runtime`, `(Runtime.install! view runtime projection) -> view`, `(Selection.install! view opts) -> view`, and `(FocusedActions.generic-deps opts) -> table`.

- [ ] **Step 1: Write shared method contract tests.** Add tests that construct one spatial view and one outline view, then assert both expose these methods as functions: `update`, `drop`, `capture-state`, `restore-state`, `restore-graph-state`, `restore-views-state`, `remove-nodes`, `remove-selected-nodes`, `node-actions`, `reveal-node`, `open-node`, `open-focused-node`, `selected-node-count`, `select-all-visible-nodes`, `clear-selection`, `focused-node-selected?`, `select-focused-node-only`, `add-focused-node-to-selection`, `remove-focused-node-from-selection`, `toggle-focused-node-selection`, `focus-selected-node`, `saved-camera-state`, `capture-camera-state!`, and `apply-initial-camera-policy!`.

- [ ] **Step 2: Write dropped guard test.** Drop an outline view, call `view:select-all-visible-nodes` inside `pcall`, and assert failure text includes `called after drop` and either `GraphOutlineView` or `GraphViewRuntime`.

- [ ] **Step 3: Implement `runtime.fnl`.** Export `init!` and `install!`. `init!` asserts required inputs: `options.graph-map`, `options.ctx`, `projection.mode`, `projection.capture-projection-state!`, `projection.restore-projection-state!`, `projection.drop-projection!`, and `projection.apply-initial-camera-policy!`. It creates runtime fields for graph map, context, mode, node views, persistence, retained mode states, connections, and dropped state.

- [ ] **Step 4: Implement runtime camera methods.** `Runtime.install!` installs `saved-camera-state`, `capture-camera-state!`, and `apply-initial-camera-policy!`. Camera capture uses `ActivityCameraState.capture-camera options.camera` and `persistence:set-mode-camera-state runtime.mode state`.

- [ ] **Step 5: Implement runtime state methods.** `capture-state` returns retained `mode_states` with the current mode entry replaced by `projection.capture-projection-state!`. `restore-state` retains incoming `mode_states`, restores selected/focused keys into `GraphMap`, restores node views when present, then calls `projection.restore-projection-state!` with current mode state.

- [ ] **Step 6: Implement `projection-selection.fnl`.** Export `install!`. It receives adapters for visible keys, selected keys, setting selected keys, focused key, focusing a key, visible-key checks, and selector synchronization. Install shared methods for selected counts, select all visible, clear selection, focused-node selection checks, select/add/remove/toggle focused node, and focus selected node.

- [ ] **Step 7: Add generic focused-actions seam.** In `focused-actions.fnl`, add `generic-deps` that validates and returns a dependency table accepted by `FocusedActions.install!`. Preserve existing spatial call behavior.

- [ ] **Step 8: Validate.**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/runtime.fnl --file assets/lua/graph/view/projection-selection.fnl --file assets/lua/graph/view/focused-actions.fnl --file assets/lua/tests/test-graph-outline-view.fnl --file assets/lua/tests/test-graph-view.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-outline-view:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-view:main
```

---

### Task 3: Migrate Outline Projection to Shared Runtime

**Files:**
- Modify: `assets/lua/graph/view/outline.fnl`
- Modify: `assets/lua/tests/test-graph-outline-view.fnl`

**Interfaces:**
- Consumes: `Runtime.init!`, `Runtime.install!`, `Selection.install!`, and `FocusedActions.generic-deps`.
- Produces: `GraphOutlineView(options) -> view` with the shared graph-view runtime contract while preserving row/compact projection behavior.

- [ ] **Step 1: Keep outline row state projection-owned.** Preserve row construction, compact projection options, row rebuild handlers, focus node mapping, selector sync, and expanded-card behavior in `outline.fnl`.

- [ ] **Step 2: Initialize runtime in `GraphOutlineView`.** After resolving graph map, context, clickables, selector, focus, pointer target, and outline options, call `Runtime.init!` with mode `"outline"` and outline projection hooks.

- [ ] **Step 3: Install runtime methods.** Call `Runtime.install!` before installing outline rebuild connections so shared methods exist before signals can fire.

- [ ] **Step 4: Replace outline-local selection methods.** Use `ProjectionSelection.install!` with adapters based on `view.rows`, `view.row-by-key`, `graph-map.selected_node_keys`, and existing `set-outline-selection!` semantics.

- [ ] **Step 5: Replace outline focused-action wiring.** Use `FocusedActions.generic-deps`, supplying outline focused-node lookup, node actions, menu position, and reveal behavior.

- [ ] **Step 6: Keep outline camera policy explicit.** The outline projection adapter returns true for initial camera policy without moving the camera. Runtime still provides `saved-camera-state` and `capture-camera-state!` through outline mode state.

- [ ] **Step 7: Preserve drop order.** Outline projection drop disconnects outline signals, drops row handles, drops node views, removes selector entries, and clears focus nodes exactly once.

- [ ] **Step 8: Validate.**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/outline.fnl --file assets/lua/tests/test-graph-outline-view.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-outline-view:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-view-compact-projection:main
```

---

### Task 4: Migrate Spatial Projection to Shared Runtime

**Files:**
- Modify: `assets/lua/graph/view/init.fnl`
- Modify: `assets/lua/tests/test-graph-view.fnl`
- Modify: `assets/lua/tests/test-graph-view-camera-persistence.fnl`
- Modify: `assets/lua/tests/test-graph-view-islands.fnl`

**Interfaces:**
- Consumes: shared runtime and selection/focus helpers from Tasks 2 and 3.
- Produces: spatial `GraphView(options) -> view` with the same shared runtime contract as outline while preserving spatial internals.

- [ ] **Step 1: Initialize runtime without moving spatial layout internals.** Keep registry, layout, force layout, labels, movables, island runtime, points, edges, and node presentation logic in `init.fnl`. Add runtime initialization with mode `"spatial"`.

- [ ] **Step 2: Preserve spatial camera suppression.** Spatial `capture-camera-state!` uses runtime mode camera storage but keeps current initial-centering capture suppression through `should-capture-camera-state?`.

- [ ] **Step 3: Adapt spatial selection methods.** Use `ProjectionSelection.install!` with adapters around existing `selected-nodes`, `selected-set`, `selection:set-selection`, `focus-nodes`, and `focused-node`.

- [ ] **Step 4: Adapt spatial focused actions.** Use `FocusedActions.generic-deps` while preserving existing menu projection and HUD screen-position behavior.

- [ ] **Step 5: Move shared capture/restore to runtime hooks.** Runtime owns common selected/focused key state and mode-state merge. Spatial projection hooks still persist points, panels, extra panels, island layout positions, and graph layout state.

- [ ] **Step 6: Preserve spatial initial camera behavior.** Keep behavior that centers mounted `start`, falls back to first visible point, and arms pending initial centering for empty maps without saving default camera prematurely.

- [ ] **Step 7: Preserve spatial drop order.** Projection drop releases labels, edges, movables, selector entries, focus nodes, node views, island state, compact records, panel transfers, and persistence handles without double-drop.

- [ ] **Step 8: Validate.**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/init.fnl --file assets/lua/tests/test-graph-view.fnl --file assets/lua/tests/test-graph-view-camera-persistence.fnl --file assets/lua/tests/test-graph-view-islands.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-view:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-view-camera-persistence:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-view-islands:main
```

---

### Task 5: Graph Activity Contract Cleanup and Mode Switch State Merge

**Files:**
- Modify: `assets/lua/graph-activity-unit.fnl`
- Modify: `assets/lua/graph/view/runtime.fnl`
- Modify: `assets/lua/tests/test-graph-activity-slots.fnl`
- Modify: `assets/lua/tests/test-graph-outline-view.fnl`

**Interfaces:**
- Consumes: both projections exposing required runtime contract methods.
- Produces: graph activity that treats graph-view runtime methods as required and preserves mode-specific state on spatial ⇄ outline switches.

- [ ] **Step 1: Add mode-switch camera tests.** Activate spatial, capture spatial camera state, switch to outline, capture outline camera state, switch back to spatial, and assert spatial state remains distinct from outline state.

- [ ] **Step 2: Add selection/focus preservation test.** Switch spatial ⇄ outline with selected and focused graph-map keys set. Assert `graph-map.selected_node_keys` and `graph-map.focused_node_key` survive both switches.

- [ ] **Step 3: Implement runtime mode-state merge.** Runtime `restore-state` retains incoming `mode_states`. Runtime `capture-state` returns all retained mode states with only the current mode entry replaced by current projection state.

- [ ] **Step 4: Tighten graph activity camera restore.** In `graph-activity-unit.fnl`, replace spatial-only persistence access with `(graph-view:saved-camera-state)` and assert the method exists before use.

- [ ] **Step 5: Tighten graph activity camera capture.** Replace optional `capture-camera-state!` checks in graph activity with required `graph-view:capture-camera-state!` calls.

- [ ] **Step 6: Preserve graph activity rebuild behavior.** Ensure theme switching still deactivates/rebuilds graph mode and restores active graph view after rebuild. Existing test `Graph activity theme switch rebuilds label colors` must continue to pass.

- [ ] **Step 7: Validate.**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph-activity-unit.fnl --file assets/lua/graph/view/runtime.fnl --file assets/lua/tests/test-graph-activity-slots.fnl --file assets/lua/tests/test-graph-outline-view.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-activity-slots:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-outline-view:main
```

---

### Task 6: Documentation and Broad Validation

**Files:**
- Modify: `docs/dev/notes/graph.md`
- Modify: `docs/dev/graph-maps.md`

**Interfaces:**
- Consumes: completed runtime contract and mode-specific state behavior.
- Produces: documented graph projection runtime contract and state ownership rules.

- [ ] **Step 1: Update graph doctrine notes.** In `docs/dev/notes/graph.md`, document that GraphView consists of a shared runtime shell plus projection adapters. State that spatial and outline are projections over `GraphMap`, not graph topology owners.

- [ ] **Step 2: Update graph maps documentation.** In `docs/dev/graph-maps.md`, document that `GraphMap` owns `view_mode` and `outline_root_keys`, while projection runtime owns mode-specific view/camera state.

- [ ] **Step 3: Document required projection adapter methods.** Add a short list covering mode, visible nodes, selection/focus adapters, reveal/open behavior, projection capture/restore, initial camera policy, and drop logic.

- [ ] **Step 4: Review documentation diff.**

```bash
git diff -- docs/dev/notes/graph.md docs/dev/graph-maps.md
```

- [ ] **Step 5: Run final validation.**

```bash
make fennel-check
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

- [ ] **Step 6: Record validation evidence in implementation report.** Include compile, constraints, focused tests, and full test outcome.
