# Outline Compact Projection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make outline mode an alternate compact `GraphView` projection where compact point presentations, not outline rows or labels, own click/select/focus interaction.

**Architecture:** Extract compact graph-node presentation and interaction lifecycle into a shared `graph/view/compact-node-projection` runtime used by outline first, then by spatial `GraphView`. Outline keeps deterministic topology traversal, row ordering, and label placement, while compact points own clickables, selector entries, focus bounds, right-click, activation, visual rings, and teardown.

**Tech Stack:** Space Fennel, `GraphView`, `GraphMap`, `GraphNodePresentation.compact-point`, `Clickables`, `ObjectSelector`, focus manager, project Fennel test runner, E2E harness, graph doctrine docs.

## Global Constraints

- Outline mode is an alternate projection of the active `GraphMap`, not a list widget.
- Rows and labels are layout/visual artifacts only.
- Clicking the compact point focuses that graph node and does not change selection.
- Clicking row whitespace or label area outside the compact point does nothing.
- Box/object selection selects outline compact points and synchronizes `GraphMap.selected_node_keys`.
- Right-clicking an outline compact point focuses the graph node and opens the same node action menu path as spatial compact nodes.
- Double-clicking or activating an outline compact point uses compact graph-node expansion semantics, not row/full-view-open semantics.
- Rebuilds remove stale compact point handles before creating new visible projection handles.
- Preserve outline projection doctrine: ordered roots, outgoing visible graph-map edges only, first occurrence wins, no hidden materialization.
- Preserve `GraphMap` ownership of selected and focused graph node keys.
- No graph core or graph-map persistence format redesign.
- No hidden relationship expansion or topology materialization.
- No global changes to clickables, intersectables, focus manager, ObjectSelector, or theme systems.
- No label/row click affordance in this pass.
- Use project Fennel idioms: `local`, factory functions, multi-branch `if`, no `.new` constructors for new code.
- Direct Fennel test commands must set `SPACE_ASSETS_PATH=$(pwd)/assets`, `FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"`, `FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"`, `SPACE_DISABLE_AUDIO=1`, `XDG_DATA_HOME=/tmp/space/tests/xdg-data`, and `SKIP_KEYRING_TESTS=1`.
- If `./build/space` may be missing or stale, run `make build` first with timeout `14400000`.
- Validation order: compile check, constraints, focused Fennel tests, focused E2E repros, then broader `make test` because shared compact runtime affects both spatial and outline renderers.
- Documentation for this behavior belongs in `docs/dev/notes/graph.md` and `docs/dev/graph-maps.md` if graph-map wording needs adjustment.

---

### Task 1: RED Tests for Outline Point-Only Interaction

**Files:**
- Modify: `assets/lua/tests/test-graph-outline-view.fnl`
- Modify: `assets/lua/tests/e2e/test-graph-outline-view.fnl`

**Interfaces:**
- Consumes: existing `GraphView`, `Clickables`, `ObjectSelector`, focus test stubs, and E2E `make-outline-e2e-env` helpers.
- Produces: failing tests that require outline compact points, not row proxies, to own click/select/focus behavior.

- [ ] **Step 1: Add point-aware helpers to `assets/lua/tests/test-graph-outline-view.fnl`**

  Add these helpers near the existing click helpers:

  ```fennel
  (fn view-record-for-key [view key]
      (var found nil)
      (each [_ record (ipairs (or view.row-handles [])) &until found]
          (when (and record record.row (= record.row.key key))
              (set found record)))
      (assert found (.. "missing outline record for " key)))

  (fn click-position [clickables position button timestamp]
      (click-row clickables position.x position.y button timestamp))

  (fn click-record-point [clickables record button timestamp]
      (local point (assert record.point "outline record requires compact point"))
      (click-position clickables point.position button timestamp))

  (fn offset-position [position dx dy]
      (glm.vec3 (+ position.x dx) (+ position.y dy) position.z))
  ```

- [ ] **Step 2: Preserve dynamic focus bounds in the focus stub**

  In `make-focus-ctx`, update `:attach-bounds` so tests can assert compact point bounds:

  ```fennel
  :attach-bounds (fn [_self node opts]
                   (set node.position (and opts opts.position))
                   (set node.size (and opts opts.size))
                   (set node.get-bounds (and opts opts.get-bounds))
                   node)
  ```

- [ ] **Step 3: Replace row-click positive assertions with compact-point positive assertions**

  Replace the old row-click test with:

  ```fennel
  (fn outline-compact-point-clicks-body []
      (local {:graph graph :graph-map graph-map} (make-map))
      (add-edge! graph-map "test:root" "test:child")
      (graph-map:set-view-mode! "outline")
      (graph-map:set-outline-root-keys! ["test:root"])
      (graph-map:set-selected-node-keys ["test:root"])
      (local clickables (Clickables))
      (local view (GraphView {:graph-map graph-map
                              :ctx (make-real-render-ctx clickables)}))
      (local child-record (view-record-for-key view "test:child"))
      (assert (= (. clickables.left-click-objects 2) child-record.point)
              "outline should register compact point as left-click target")
      (assert (= (. clickables.right-click-objects 2) child-record.point)
              "outline should register compact point as right-click target")
      (assert (= (. clickables.double-click-objects 2) child-record.point)
              "outline should register compact point as double-click target")
      (click-record-point clickables child-record 1 100)
      (assert (= graph-map.focused_node_key "test:child")
              "compact point click should focus hit-tested child node")
      (assert (= (table.concat graph-map.selected_node_keys ",") "test:root")
              "compact point click should preserve existing selection")
      (view:drop)
      (graph-map:drop)
      (graph:drop))
  ```

  Register it as `outline compact point clicks use real hit testing`.

- [ ] **Step 4: Add negative row-whitespace and label-area hit tests**

  Add a test that clicks coordinates offset from `child-record.point.position`, including one near the label and one in row whitespace, and asserts:

  ```fennel
  (assert (= graph-map.focused_node_key nil)
          "row whitespace or label area outside compact point should not focus")
  (assert (= (table.concat graph-map.selected_node_keys ",") "test:root")
          "row whitespace or label area outside compact point should preserve selection")
  (assert (= opened-menu nil)
          "right-clicking row whitespace should not open menu")
  (assert (= opened-node-key nil)
          "double-clicking row whitespace should not activate/open node")
  ```

- [ ] **Step 5: Tighten selector/focus assertions**

  In the selector/focus-manager outline test, assert:

  ```fennel
  (assert (= child-record.selectable child-record.point)
          "outline selector entry should be the compact point presentation")
  (local bounds (and child-record.focus-node.get-bounds
                    (child-record.focus-node:get-bounds)))
  (assert bounds "outline focus node should expose dynamic compact point bounds")
  (assert (approx bounds.size.x child-record.point.size)
          "outline focus bounds width should match compact point size")
  (assert (approx bounds.size.y child-record.point.size)
          "outline focus bounds height should match compact point size")
  ```

- [ ] **Step 6: Tighten lifecycle registration assertions**

  Update the registration/drop test so the registered clickable objects are compact points and stale compact points disappear after root rebuild and drop.

- [ ] **Step 7: Update E2E click repro to use point center and whitespace miss**

  In `assets/lua/tests/e2e/test-graph-outline-view.fnl`, make the click repro project `child-record.point.position` for the positive click. Add a second click projected from `(glm.vec3 (+ child-record.point.position.x 80) child-record.point.position.y child-record.point.position.z)` and assert focus remains nil and selection remains unchanged.

- [ ] **Step 8: Run RED tests and record failures**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-outline-view:main
  ```

  Expected: FAIL because current outline still registers row targets. Do not commit this RED-only state separately.

---

### Task 2: Shared Compact Projection Runtime and Outline Wiring

**Files:**
- Create: `assets/lua/graph/view/compact-node-projection.fnl`
- Modify: `assets/lua/graph/view/outline.fnl`
- Modify: `assets/lua/tests/test-graph-outline-view.fnl`
- Modify: `assets/lua/tests/e2e/test-graph-outline-view.fnl`

**Interfaces:**
- Consumes: `GraphNodePresentation.compact-point`, `Clickables`, `ObjectSelector`, focus context, outline rows.
- Produces: `graph/view/compact-node-projection` with `attach!`, `refresh!`, `drop!`, `bounds-for-presentation`, and `visible-size`; outline row records whose `point` is the clickable/selectable/focus-bound presentation.

- [ ] **Step 1: Create `compact-node-projection.fnl`**

  Export:

  ```fennel
  {:attach! attach!
   :refresh! refresh!
   :drop! drop!
   :bounds-for-presentation bounds-for-presentation
   :visible-size visible-size}
  ```

  `attach!` must assert required options (`:points`, `:node`, `:position`, `:layers`, `:clickables`) and return a record with fields `node`, `key`, `point`, `presentation`, `selectable`, `focus-node`, `refresh!`, and `drop!`.

- [ ] **Step 2: Implement compact point creation and layer refresh**

  `refresh!` computes selection and focus ring sizes exactly like spatial GraphView:

  ```fennel
  (local selection-size (if selected?
                            (+ base-size selection-border-width)
                            0))
  (local focus-size (if focused?
                        (+ base-size
                           (if selected? selection-border-width 0)
                           focus-border-width)
                        0))
  ```

  Then call `point:set-layer-size` for focus and selection layer indices.

- [ ] **Step 3: Implement compact point click/right-click/double-click wiring**

  `point.on-click` requests focus only and calls `opts.on-focus`.

  `point.on-right-click` requests focus, calls `opts.on-focus`, then calls `opts.on-right-click`.

  `point.on-double-click` calls `opts.on-activate`.

  Do not mutate selection in this module.

- [ ] **Step 4: Implement selector, focus, and teardown lifecycle**

  `attach!` registers `point` with clickables and selector. Focus bounds must be dynamic:

  ```fennel
  (focus:attach-bounds focus-node
                       {:get-bounds (fn [_self]
                                      (bounds-for-presentation point))})
  ```

  `drop!` unregisters the same point from clickables, removes it from selector, drops focus node when owned, clears handlers, and drops the point.

- [ ] **Step 5: Replace outline row targets with compact point projections**

  In `outline.fnl`, stop using row-rectangle hit helpers for non-empty rows. `attach-row-handles!` must create row metadata, call `CompactNodeProjection.attach!`, store the returned `point/selectable/focus-node`, and create the text label as visual-only.

- [ ] **Step 6: Keep outline selection/focus sync against point records**

  `row-selectables-for-keys` returns `record.selectable`, which equals `record.point`. `selected-keys-from-selector` reads `selectable.key`. `row-by-focus` maps `focus-node` to row metadata.

- [ ] **Step 7: Keep labels visual-only**

  Labels remain text handles positioned relative to `record.point`; they are not clickables, selector entries, or focus nodes.

- [ ] **Step 8: Run compile, constraints, and focused outline/E2E tests**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/compact-node-projection.fnl --file assets/lua/graph/view/outline.fnl --file assets/lua/tests/test-graph-outline-view.fnl --file assets/lua/tests/e2e/test-graph-outline-view.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-outline-view:main
  SPACE_OUTLINE_REPRO_CASE=click SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" xvfb-run -a ./build/space -m tests.e2e.test-graph-outline-view:main
  ```

- [ ] **Step 9: Commit**

  ```bash
  git add assets/lua/graph/view/compact-node-projection.fnl assets/lua/graph/view/outline.fnl assets/lua/tests/test-graph-outline-view.fnl assets/lua/tests/e2e/test-graph-outline-view.fnl
  git commit -m "feat(graph): make outline compact points own interaction"
  ```

---

### Task 3: Spatial GraphView Reuse of Compact Projection Runtime

**Files:**
- Modify: `assets/lua/graph/view/init.fnl`
- Modify: `assets/lua/graph/view/compact-node-projection.fnl`
- Test: existing graph view and selection/focus tests.

**Interfaces:**
- Consumes: `CompactNodeProjection.attach!`, `CompactNodeProjection.refresh!`, `CompactNodeProjection.drop!`.
- Produces: spatial compact nodes and outline compact nodes sharing compact point presentation/interaction lifecycle, while ForceLayout, edges, labels, movables, islands, persistence, and expanded-card policy remain in spatial `GraphView`.

- [ ] **Step 1: Require the compact projection runtime in `init.fnl`**

  Add:

  ```fennel
  (local CompactNodeProjection (require :graph/view/compact-node-projection))
  ```

- [ ] **Step 2: Add `compact-records` table**

  Near `focus-nodes` and `node-by-focus`, add:

  ```fennel
  (local compact-records {})
  ```

- [ ] **Step 3: Replace spatial compact point creation with runtime attach**

  Create an `attach-compact-node!` helper that passes spatial GraphView constants, callbacks, selector, focus scope, and pointer target into `CompactNodeProjection.attach!`. The helper returns a compact record whose `point` is used wherever the old compact point was used.

- [ ] **Step 4: Preserve spatial preview/focus scope setup**

  After attaching a compact record for a node, store `focus-nodes[node]`, `node-by-focus[focus-node]`, and `_preview-scopes[node]` exactly as before. Preserve `focus-node:set-entry-scope` and `preview-scope:set-exit-node` behavior.

- [ ] **Step 5: Remove duplicate manual compact event and clickable wiring**

  In new compact-node creation paths, remove manual `point.on-click`, `point.on-right-click`, `point.on-double-click`, clickables registration, and selector registration. These are owned by the compact projection runtime.

- [ ] **Step 6: Refresh compact records from `update-point-state`**

  If `compact-records[node]` exists, call `CompactNodeProjection.refresh!` for that record. Keep existing expanded-card layer update behavior separate.

- [ ] **Step 7: Preserve compact/expanded transitions**

  When expanding a compact node, drop the compact record without removing selector/focus state incorrectly, then install the expanded card via the existing card path. When collapsing, attach a compact record and replace the expanded card selector entry with the new compact point.

- [ ] **Step 8: Preserve node removal/drop cleanup**

  When removing compact nodes or dropping the view, call `CompactNodeProjection.drop!` for compact records exactly once. Expanded card cleanup remains in existing spatial paths.

- [ ] **Step 9: Run compile, constraints, and spatial/outline focused tests**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/init.fnl --file assets/lua/graph/view/compact-node-projection.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-outline-view:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-selection-focus-command:main
  ```

- [ ] **Step 10: Commit**

  ```bash
  git add assets/lua/graph/view/init.fnl assets/lua/graph/view/compact-node-projection.fnl assets/lua/tests/test-graph-outline-view.fnl
  git commit -m "refactor(graph): share compact node projection lifecycle"
  ```

---

### Task 4: Docs, E2E Naming, and Final Validation

**Files:**
- Modify: `assets/lua/tests/e2e/test-graph-outline-view.fnl`
- Modify: `docs/dev/notes/graph.md`
- Modify: `docs/dev/graph-maps.md` if graph-map outline wording needs the same clarification.

**Interfaces:**
- Consumes: shared compact runtime from Tasks 2 and 3.
- Produces: canonical docs stating outline rows/labels are visual-only and compact node presentations own interaction.

- [ ] **Step 1: Rename E2E repro to compact point terminology**

  Rename the click repro function and printed messages so they describe compact point click/focus and whitespace miss behavior.

- [ ] **Step 2: Update graph doctrine docs**

  In `docs/dev/notes/graph.md`, update the outline rendering section to state that outline rows are deterministic visual/layout records and compact node presentations own clickables, selector entries, focus bounds, menu routing, activation, and teardown.

  In `docs/dev/graph-maps.md`, clarify the same only if the current outline-mode section would otherwise imply row-level interaction ownership.

- [ ] **Step 3: Run focused E2E click and visual repros**

  ```bash
  SPACE_OUTLINE_REPRO_CASE=click SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" xvfb-run -a ./build/space -m tests.e2e.test-graph-outline-view:main
  SPACE_OUTLINE_REPRO_CASE=visual SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" xvfb-run -a ./build/space -m tests.e2e.test-graph-outline-view:main
  ```

- [ ] **Step 4: Run full validation ladder**

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-outline-view:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-selection-focus-command:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add assets/lua/tests/e2e/test-graph-outline-view.fnl docs/dev/notes/graph.md docs/dev/graph-maps.md
  git commit -m "docs(graph): document outline compact projection semantics"
  ```

- [ ] **Step 6: Integration gate**

  Use `finishing-a-development-branch` after all tasks pass review. PR CI is the final integration gate; do not claim ready-to-merge until required local validation and PR CI are green.
