# Outline Marker Box Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilize graph outline compact marker layout by wrapping layout-free layered points in a reusable measured box and binding compact graph interactions to caller-owned points.

**Architecture:** Keep raw `LayeredPoint` layout-free for spatial graph performance and keep `TreeView` unchanged. Add a reusable `LayeredPointBox` widget for layout contexts, extend `CompactNodeProjection` with an explicit caller-owned point seam, then compose outline rows from a top-aligned marker box, label, and optional expanded card.

**Tech Stack:** Space Fennel, old widget `Layout`, `LayeredPoint`, `CompactNodeProjection`, `OutlineRowWidget`, `TreeView`, project-native Fennel validation and E2E snapshots.

## Global Constraints

- Keep `TreeView` generic and unchanged: it stacks whatever row widgets measure.
- Keep raw `LayeredPoint` layout-free for spatial graph performance.
- Add a reusable layout wrapper for contexts that need a layered point to participate in widget layout.
- Keep graph interaction ownership in `CompactNodeProjection` and graph outline, not in generic marker layout code.
- Make outline marker measurement stable across focus/selection state changes.
- Keep point and label top-aligned in outline summary rows.
- Preserve current graph outline behavior: compact point click/focus/select/menu semantics, row whitespace non-interaction, expanded-card behavior, teardown, and all-visible outline rows.
- Do not make `LayeredPoint` itself a widget or give every spatial graph point a `Layout` node.
- Do not add shared row metrics or uniform row-height behavior to `TreeView`.
- Do not change graph topology traversal, graph persistence, outline root semantics, selection/focus ownership, or graph commands.
- Do not change spatial graph layout behavior.
- Do not introduce virtualization or port outline rendering to `next-app`.
- `TreeView` owns tree flattening and stacking only.
- `LayeredPointBox` owns layout footprint and raw point lifetime in layout contexts.
- `LayeredPoint` owns raw render-layer records only.
- `CompactNodeProjection` owns graph compact interaction registrations, selector membership, focus-node bindings, activation/menu callbacks, and layer refresh.
- `OutlineRowWidget` composes marker box, label, projection record, and optional expanded card for graph outline rows.
- `GraphMap` remains the owner of view mode, outline roots, selected keys, and focused key.
- Graph core persists topology only.
- For Fennel/UI/layout graph work, run validation in this order: project-native Fennel compile check, `make constraints`, focused Fennel tests, graph outline E2E snapshot/click validation when visuals change, and broader `make test` when reusable widget or graph interaction behavior changes.
- Do not use system Fennel/Lua or non-project compiler paths as validation oracles.

---

## File Structure

- Create `assets/lua/layered-point-box.fnl`: generic measured widget wrapper around raw `LayeredPoint` for layout contexts.
- Create `assets/lua/tests/test-layered-point-box.fnl`: graph-free widget tests for reserved-size measurement, placement, overflow guards, and drop ownership.
- Modify `assets/lua/tests/fast.fnl`: register new focused test modules.
- Modify `assets/lua/graph/view/compact-node-projection.fnl`: add caller-owned point seam and ownership-aware teardown.
- Modify `assets/lua/tests/test-graph-view-compact-projection.fnl`: add supplied-point interaction/teardown tests while preserving existing behavior.
- Modify `assets/lua/graph/view/outline-row-widget.fnl`: compose rows from `LayeredPointBox`, label, projection record, and expanded card.
- Create `assets/lua/tests/test-graph-outline-row-widget.fnl`: focused outline row widget tests that avoid increasing the already-large graph outline view test module.
- Do not add new coverage to the already-large `assets/lua/tests/test-graph-outline-view.fnl`; put new whole-view regressions in `assets/lua/tests/test-graph-outline-row-widget.fnl` with local helpers.
- Keep `assets/lua/tests/e2e/test-graph-outline-view.fnl` unchanged; use its existing click/layout/style/snapshot coverage as the visual integration gate.
- Update graph outline snapshot goldens under `assets/lua/tests/data/snapshots/graph-outline-*.png` only after visual inspection.
- Modify `docs/dev/notes/graph.md`: document measured marker box ownership in outline rows.
- Modify `docs/dev/notes/layered-points-in-graph.md`: distinguish layout-free `LayeredPoint` from measured `LayeredPointBox`.

---

### Task 1: Reusable LayeredPointBox Widget

**Files:**
- Create: `assets/lua/layered-point-box.fnl`
- Create: `assets/lua/tests/test-layered-point-box.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `LayeredPoint(opts) -> point` from `assets/lua/layered-point.fnl`.
- Produces: `(LayeredPointBox opts) -> builder`, where the built widget exposes:
  - `layout`: explicit `Layout` object;
  - `point`: owned raw `LayeredPoint`;
  - `reserved-size`: stable numeric layout footprint;
  - `set-reserved-size(self, size)`: updates reserved footprint and marks measure/layout dirty;
  - `refresh(self)`: marks layout dirty after visual-only point changes;
  - `drop(self)`: drops point and layout exactly once.
- Required opts: `:layers`, `:reserved-size`.
- Optional opts: `:points`, `:ctx`, `:position`, `:pointer-target`, `:depth-offset-step`, `:base-depth-offset-index`, `:base-layer-index`, `:name`.

- [ ] **Step 1: Write failing measurement test.** In `test-layered-point-box.fnl`, add `LayeredPointBox measures reserved chrome size`. Build a box with reserved size `12` and layers sized `0`, `8`, and `6`. Assert `box.layout.measure` is `12 x 12`, not the current maximum layer size.

- [ ] **Step 2: Run the new test and verify RED.** Command:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-layered-point-box:main
```

Expected: failure because `layered-point-box` cannot be required or `LayeredPointBox` is undefined.

- [ ] **Step 3: Implement minimal `LayeredPointBox` builder.** Create `layered-point-box.fnl`; assert `:layers`, positive finite `:reserved-size`, and available `ctx.points` or `opts.points`. Build a raw `LayeredPoint` and an explicit `Layout` whose measurer reports `(glm.vec3 reserved-size reserved-size 0)`.

- [ ] **Step 4: Write failing placement test.** Add `LayeredPointBox centers point in reserved box`. Set layout position `(10, -20, 0)`, size `(12, 12, 0)`, run layouter, and assert the raw point center is `(16, -14, 0)`.

- [ ] **Step 5: Implement layouter.** In `LayeredPointBox`, set the raw point position to the center of the assigned layout box. Write child transforms directly during layout; do not dirty layout from inside the layouter.

- [ ] **Step 6: Write failing overflow guard tests.** Add `LayeredPointBox rejects layer sizes larger than reserved size` and `LayeredPointBox can update reserved size explicitly`. Assert `point:set-layer-size 1 14` fails while reserved size is `12`, then `box:set-reserved-size 14` allows `point:set-layer-size 1 14` and remeasures to `14 x 14`.

- [ ] **Step 7: Implement guarded point mutators.** Wrap the owned point's `set-size`, `set-layer`, and `set-layer-size` methods so any size greater than `reserved-size` errors with `LayeredPointBox` and `reserved size` in the message. `set-reserved-size` must assert positive finite size and mark measure/layout dirty.

- [ ] **Step 8: Write failing lifecycle tests.** Add `LayeredPointBox drops point and layout once` and `LayeredPointBox methods fail after drop`. Count point layer drops, call `drop` twice, and assert public methods fail after drop with `LayeredPointBox` and `called after drop` in the error text.

- [ ] **Step 9: Implement lifecycle guards.** Track `dropped?`, make public methods call `assert-not-dropped`, and drop the raw point before dropping the layout.

- [ ] **Step 10: Register focused test.** Add `tests.test-layered-point-box` to `assets/lua/tests/fast.fnl`.

- [ ] **Step 11: Validate Task 1.** Run:

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/layered-point-box.fnl --file assets/lua/tests/test-layered-point-box.fnl --file assets/lua/tests/fast.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-layered-point-box:main
```

---

### Task 2: CompactNodeProjection Caller-Owned Point Seam

**Files:**
- Modify: `assets/lua/graph/view/compact-node-projection.fnl`
- Modify: `assets/lua/tests/test-graph-view-compact-projection.fnl`

**Interfaces:**
- Consumes: a LayeredPoint-like `point` table with `size`, `layers`, `set-layer-size`, `intersect`, event fields, and `drop`.
- Produces: extended `CompactNodeProjection.attach!(opts) -> record`:
  - existing creation path remains compatible;
  - new optional `:point` accepts a caller-owned point;
  - `:points`, `:position`, and `:layers` are required only when `:point` is not supplied;
  - record exposes `owns-point?`, true for internally-created points and false for supplied points;
  - `drop!` drops the point by default only when `owns-point?` is true.

- [ ] **Step 1: Write failing supplied-point interaction test.** In `test-graph-view-compact-projection.fnl`, add `CompactNodeProjection binds interactions to supplied point`. Build a point stub with layers, `set-layer-size`, `intersect`, and `drop`; call `CompactNodeProjection.attach!` with `:point`; assert `point.on-click`, `point.on-right-click`, `point.on-double-click`, and `point.activate` are functions and invoke the expected focus/right-click/activate callbacks with the row node and owner.

- [ ] **Step 2: Write failing supplied-point drop test.** Add `CompactNodeProjection does not drop supplied point by default`. Drop the record and assert clickables were unregistered, selector entry removed, focus node dropped according to existing defaults, but the point stub `drop` count remains `0`.

- [ ] **Step 3: Write internally-created compatibility test.** Add `CompactNodeProjection still drops internally-created point by default`. Use the existing `points:create-point` stub path and assert dropping the record drops the created point.

- [ ] **Step 4: Run focused test and verify RED.** Command:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-view-compact-projection:main
```

Expected: supplied-point tests fail because `attach!` still requires `:points`, `:position`, and `:layers` and always owns point teardown.

- [ ] **Step 5: Refactor attach point creation.** In `compact-node-projection.fnl`, add a local helper that returns `(point owns-point?)`: use `opts.point` when supplied; otherwise create the existing `GraphNodePresentation.compact-point` from `:points`, `:position`, and `:layers`.

- [ ] **Step 6: Preserve behavior on both paths.** Attach click/right/double/activate handlers, selector membership, focus bounds, focus-node activation, `refresh!`, and owner callbacks identically whether the point was supplied or created.

- [ ] **Step 7: Make teardown ownership-aware.** Store `record.owns-point?`. In `drop!`, default `:drop-point?` to `record.owns-point?`; still allow explicit `:drop-point? true/false` to override.

- [ ] **Step 8: Validate Task 2.** Run:

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/compact-node-projection.fnl --file assets/lua/tests/test-graph-view-compact-projection.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-view-compact-projection:main
```

---

### Task 3: OutlineRowWidget Uses Stable Marker Box Layout

**Files:**
- Modify: `assets/lua/graph/view/outline-row-widget.fnl`
- Create: `assets/lua/tests/test-graph-outline-row-widget.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `LayeredPointBox(opts) -> builder` from Task 1.
- Consumes: `CompactNodeProjection.attach!({:point point, ...}) -> record` from Task 2.
- Produces: existing `OutlineRowWidget(opts) -> builder` API, plus exposed `marker-box` for focused tests. Existing exposed fields `point`, `selectable`, `focus-node`, `label`, `expanded-card`, `expanded?`, `expand!`, `collapse!`, `refresh`, and `drop` remain available.

- [ ] **Step 1: Create focused outline row test module.** Add `test-graph-outline-row-widget.fnl` with minimal render stubs copied only as needed from `test-graph-outline-view.fnl`: points, clickables, selector, focus, text batcher, quad batcher, theme, and `make-outline-row-widget` helper. Register `tests.test-graph-outline-row-widget` in `assets/lua/tests/fast.fnl`.

- [ ] **Step 2: Write failing stable selection/focus measurement test.** Add `outline row marker measurement is stable across focus and selection`. Build a row with `selected?` and `focused?` predicates backed by mutable state; measure compact height; toggle selected/focused true; call `widget:refresh`; measure again; assert row height and label x are unchanged while focus/selection layer sizes become positive.

- [ ] **Step 3: Write failing top alignment test.** Add `outline row marker and label are top aligned`. Use a label whose measured height is taller than marker reserved size. After layout, assert marker box top and label top match the compact summary top within epsilon, and assert point center is `marker-box.position.y + marker-box.size.y / 2` rather than centered against the full label height.

- [ ] **Step 4: Write failing descendant stability regression.** In `test-graph-outline-row-widget.fnl`, add `outline focus and selection do not move descendant row points`. Build a minimal root/child outline view with local helpers, record child point position, toggle root selected/focused through graph-map/view APIs, refresh, and assert child point y is unchanged.

- [ ] **Step 5: Write failing expand/collapse point ownership test.** Add `outline row keeps marker box point across expand and collapse`. Build a row, save `widget.point` and `widget.marker-box.point`, expand, collapse, and assert the same marker-box point is reused, compact click handlers are restored after collapse, and selector/focus ownership remains correct.

- [ ] **Step 6: Run focused row tests and verify RED.** Command:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-outline-row-widget:main
```

Expected: failures because `OutlineRowWidget` still creates compact projection points directly and derives layout from current `visible-size`.

- [ ] **Step 7: Replace direct point creation with marker box.** In `outline-row-widget.fnl`, require `layered-point-box`; create a marker box with layers from existing `projection-layers` and `reserved-size = node-size + selection-border-width + focus-border-width`; bind `CompactNodeProjection.attach!` to `state.marker-box.point` with `:point`.

- [ ] **Step 8: Update measurement.** Measure `state.marker-box.layout` and `state.label.layout`; compact summary height is `max(marker-box.measure.y, label.measure.y) + vertical-padding * 2`. Expanded height adds `expanded-gap + expanded-card.layout.measure.y`.

- [ ] **Step 9: Update layout.** Treat `point-x` as the marker center x. Place marker box at x `point-x - marker-box.measure.x / 2`; place marker and label top-aligned at `summary-top - vertical-padding`; set label x to `point-x + marker-box.measure.x / 2 + label-gap`; set label y to `summary-top - vertical-padding - label.measure.y`.

- [ ] **Step 10: Update refresh semantics.** `refresh!` updates projection/card layer sizes and marker visuals, then marks row layout dirty. It must not use `CompactNodeProjection.visible-size` for layout or label placement.

- [ ] **Step 11: Update expand/collapse and drop ownership.** On expand, drop projection registrations without dropping the marker point; keep marker box alive; make expanded card active selectable/focus presentation. On collapse, unregister/drop card and reattach compact projection to the same marker point. On row drop, drop projection registrations, expanded card if present, focus node exactly once, marker box, label, and row layout.

- [ ] **Step 12: Preserve existing outline behavior.** Keep compact point click/focus/right-click/activation callbacks, row whitespace miss behavior, failed expansion preservation, set-row rejection, and all-visible outline integration behavior passing.

- [ ] **Step 13: Validate Task 3.** Run:

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/outline-row-widget.fnl --file assets/lua/tests/test-graph-outline-row-widget.fnl --file assets/lua/tests/fast.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-outline-row-widget:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-outline-view:main
```

---

### Task 4: Docs, E2E Snapshots, and Broad Validation

**Files:**
- Modify: `docs/dev/notes/graph.md`
- Modify: `docs/dev/notes/layered-points-in-graph.md`
- Modify: `assets/lua/tests/data/snapshots/graph-outline-empty.png`, `graph-outline-root-main.png`, and `graph-outline-root-branch.png` only if visual output intentionally changes.

**Interfaces:**
- Consumes: completed `LayeredPointBox`, caller-owned compact projection seam, and outline row marker composition.
- Produces: documented ownership boundary and final validation evidence.

- [ ] **Step 1: Update graph doctrine docs.** In `docs/dev/notes/graph.md`, state that outline rows compose a measured marker box and label, while compact graph interactions remain owned by compact node projection records and GraphMap-owned state remains unchanged.

- [ ] **Step 2: Update layered point docs.** In `docs/dev/notes/layered-points-in-graph.md`, distinguish raw layout-free `LayeredPoint` from measured `LayeredPointBox`; note that spatial graph uses raw points for performance and outline rows use marker boxes for stable widget layout.

- [ ] **Step 3: Run focused graph outline E2E non-update.** Command:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl FENNEL_MACRO_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl SDL_VIDEODRIVER=x11 xvfb-run -a -s "-screen 0 1280x720x24" ./build/space -m tests.e2e.test-graph-outline-view:main
```

If snapshots mismatch, inspect generated `.actual.png` images before updating goldens.

- [ ] **Step 4: Update graph outline snapshots only if visually correct.** If Task 4 Step 3 reports intentional visual drift, rerun with:

```bash
SPACE_OUTLINE_REPRO_CASE=visual SPACE_SNAPSHOT_UPDATE=graph-outline-empty,graph-outline-root-main,graph-outline-root-branch SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl FENNEL_MACRO_PATH=$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl SDL_VIDEODRIVER=x11 xvfb-run -a -s "-screen 0 1280x720x24" ./build/space -m tests.e2e.test-graph-outline-view:main
```

Then visually inspect the updated PNGs and rerun the non-update command from Step 3.

- [ ] **Step 5: Run final local validation.** Run:

```bash
make fennel-check
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-layered-point-box:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-view-compact-projection:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-outline-row-widget:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-graph-outline-view:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test-e2e
```

- [ ] **Step 6: Record final evidence.** The implementation report must include compile, constraints, focused tests, E2E status, full non-E2E suite outcome, visual snapshot inspection notes if goldens changed, and a constraint-impact note.

---

## Acceptance Checklist

- `TreeView` source and behavior are unchanged.
- Raw `LayeredPoint` remains layout-free.
- `LayeredPointBox` provides stable reserved-size layout for layered points.
- `CompactNodeProjection` supports both internally-created and caller-owned points with explicit point drop ownership.
- Outline row measurement no longer depends on current focus/selection `visible-size`.
- Focus/selection visual changes do not alter outline row height or descendant point positions.
- Outline marker and label are top-aligned in the compact summary row.
- Outline compact click/focus/select/menu/activate behavior remains owned by compact projection and still passes focused/E2E tests.
- Expanded card behavior and teardown remain intact.
- Graph topology, GraphMap interaction state ownership, and graph persistence remain unchanged.
