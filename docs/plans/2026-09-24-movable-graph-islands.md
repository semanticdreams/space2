# Movable Graph Map Ordered-List Islands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ordered-list graph map islands movable by default in force layout as unit aggregates instead of pinning every member as an obstacle.

**Architecture:** Stop treating ordered-list island membership as an implicit node-pin reason. Add graph-view layout support for aggregate island participants: island members remain rendered as normal graph node points, but their force-layout participation is represented by one virtual island body whose movement applies presenter-computed member placements as a unit. Keep ForceLayout C++ unchanged because it already defaults nodes to unpinned and skips only explicitly pinned nodes.

**Tech Stack:** Space Fennel, GraphMap/GraphView, GraphViewLayout, ordered-list island presenter, C++ ForceLayout binding surface, native `./build/space` Fennel test runner.

## Global Constraints

- This is Space Fennel/UI/graph work. Use `space-fennel`, `space-fennel-ui`, `space-graph-doctrine`, `space-testing-runtime` constraints.
- TDD required: failing test first, RED evidence, minimal implementation.
- Supervisor cannot edit production/test code; implementation must go through `implementer` and review.
- Prefer project idioms: Fennel `local`, factory functions, no silent fallbacks. Use native validation: compile check, constraints, focused tests. Avoid system fennel/lua.
- Avoid broad C++ changes unless necessary. ForceLayout already supports movable/unpinned nodes.
- Do not introduce legacy aliases or compatibility shims; use canonical option keys only.
- Preserve graph doctrine: graph nodes stay decoupled from views; GraphMap owns island records as map-local presentation state.
- Ordered-list island members must not be pinned by default.
- Explicit node pins must remain honored; an explicitly pinned member must not be moved by aggregate island layout while pinned.
- Do not add a user-facing or persisted explicit island-pin API/key without human approval; this plan only fixes default unpinned aggregate movement and preserves existing explicit node-pin behavior.
- Documentation for changed behavior must update `docs/dev/graph-maps.md`.

---

## Acceptance Criteria

- Ordered-list presenter no longer calls `host:set-member-pinned` during default apply.
- Creating or restoring an ordered-list island does not set `view.pinned` for its members unless another explicit pin reason exists.
- Ordered-list island members participate in force layout through one aggregate island body; after force-layout updates, all unpinned members move by the same delta and keep ordered-list spacing.
- Edges connected to unpinned island members route force-layout attraction to the aggregate island body, not to separate member bodies.
- Normal member drag still snaps back on drag end.
- Alt-drag still updates `island.state.position` and moves the whole island on drag end.
- Removing an island does not delete nodes and does not clear unrelated explicit pins.
- No C++ ForceLayout changes are required.
- `docs/dev/graph-maps.md` documents movable aggregate presentation-island behavior.
- PR CI is the full integration gate before ready-to-merge claims.

## Validation Ladder

1. Runtime/freshness prerequisite when `./build/space` is missing or stale:
   ```bash
   make build
   ```
   Use timeout `14400000` ms for cold builds.
2. First focused Fennel compile check for touched files:
   ```bash
   SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/island-presenters/ordered-list.fnl --file assets/lua/graph/view/island-host.fnl --file assets/lua/graph/view/layout.fnl --file assets/lua/graph/view/init.fnl --file assets/lua/tests/test-graph-view-islands.fnl
   ```
3. Constraints second:
   ```bash
   make constraints
   ```
4. Focused Fennel tests third:
   ```bash
   SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-islands:main
   ```
5. Broader relevant local suite justified by central GraphViewLayout force-layout behavior:
   ```bash
   SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
   SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map:main
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
   ```
6. PR CI is the full integration gate.

---

### Task 1: Stop Ordered-List Islands from Pinning Members by Default

**Files:**
- Modify: `assets/lua/graph/view/island-presenters/ordered-list.fnl`
- Modify: `assets/lua/tests/test-graph-view-islands.fnl`

**Interfaces:**
- Consumes: existing `OrderedListPresenter.apply(island, host) -> placements`.
- Produces: ordered-list apply still positions members via `host:set-member-position`, but no longer calls `host:set-member-pinned` for default island membership.

- [ ] **Step 1: Write the RED test updates for default unpinned membership**

  In `assets/lua/tests/test-graph-view-islands.fnl`, update `check-applies-ordered-list-island-positions` so the last two assertions require no island default pin:

  ```fennel
  (assert (not (. view.pinned (map:lookup "test:a")))
          "first member should not be pinned by island by default")
  (assert (not (. view.pinned (map:lookup "test:b")))
          "second member should not be pinned by island by default")
  ```

- [ ] **Step 2: Update obsolete island-removal pin expectations**

  In the same test file:
  - Rename `check-unpins-members-after-island-removal` to `check-island-removal-keeps-default-unpinned-members-unpinned`.
  - Change its initial assertions to require `not (. view.pinned node-a)` and `not (. view.pinned node-b)`.
  - Keep the `map:remove-island` call.
  - Keep final assertions requiring both members to remain unpinned.
  - Rename `graph-view-unpins-members-after-island-removal` and the test table name to `GraphView island removal keeps default unpinned members unpinned`.

- [ ] **Step 3: Update node-removal pin cleanup expectations**

  In `check-removes-island-member-node-without-pin-cleanup-error`, change the first assertion to:

  ```fennel
  (assert (not (. view.pinned node-a))
          "fixture should start with removed member unpinned by default")
  ```

  Keep the removal no-error assertion and final stale-pin assertion.

- [ ] **Step 4: Verify the updated tests fail before production changes**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-islands:main
  ```

  Expected RED: failure on `"first member should not be pinned by island by default"` or equivalent updated unpinned assertion.

- [ ] **Step 5: Remove the default pin call from the ordered-list presenter**

  In `assets/lua/graph/view/island-presenters/ordered-list.fnl`, change `apply` from positioning and pinning each member to positioning only:

  ```fennel
  (fn apply [island host]
      (local placements (layout-island island host))
      (local members (if island.members island.members []))
      (each [_ key (ipairs members)]
          (host:set-member-position island.id key (. placements key)))
      placements)
  ```

- [ ] **Step 6: Run focused compile, constraints, and focused tests**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/island-presenters/ordered-list.fnl --file assets/lua/tests/test-graph-view-islands.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-islands:main
  ```

- [ ] **Step 7: Commit Task 1**

  ```bash
  git add assets/lua/graph/view/island-presenters/ordered-list.fnl assets/lua/tests/test-graph-view-islands.fnl
  git commit -m "fix(graph): stop default ordered-list island member pins"
  ```

---

### Task 2: Add Aggregate Force-Layout Participation for Ordered-List Islands

**Files:**
- Modify: `assets/lua/graph/view/island-presenters/ordered-list.fnl`
- Modify: `assets/lua/graph/view/island-host.fnl`
- Modify: `assets/lua/graph/view/layout.fnl`
- Modify: `assets/lua/graph/view/init.fnl`
- Modify: `assets/lua/tests/test-graph-view-islands.fnl`

**Interfaces:**
- Consumes: Task 1 unpinned ordered-list apply behavior.
- Produces:
  - `GraphViewIslandHost:node-for-key(key: string) -> GraphNode`
  - `GraphViewIslandHost:aggregate-layout-record(island: table) -> table|nil`
  - ordered-list presenter method `aggregate-layout-record(island: table, host: GraphViewIslandHost) -> {:id string, :members table, :position glm.vec3, :member-placements function}`
  - `GraphViewLayout:sync-island-layouts(records: table) -> true`
  - GraphView internal runtime island-position cache used by aggregate layout.

- [ ] **Step 1: Add the RED unit-movement test**

  In `assets/lua/tests/test-graph-view-islands.fnl`, add a helper named `check-list-created-island-moves-as-force-layout-unit`:

  ```fennel
  (fn check-list-created-island-moves-as-force-layout-unit [fixture]
      (local map fixture.map)
      (local view fixture.view)
      (local movables fixture.movables)
      (local list-node (map:lookup fixture.list-key))
      (local item-node (map:lookup fixture.item-key))
      (local second-node (map:lookup fixture.second-item-key))
      (local list-entry (. movables.by-node list-node))
      (assert list-entry "list node should be movable")
      (list-entry.target:set-position (glm.vec3 48 0 0))
      (list-node:expand-items-as-island)
      (assert (not (. view.pinned item-node))
              "first list island member should be unpinned by default")
      (assert (not (. view.pinned second-node))
              "second list island member should be unpinned by default")
      (local before-a (view:get-position item-node))
      (local before-b (view:get-position second-node))
      (for [_ 1 8]
          (view:update 0.016))
      (local after-a (view:get-position item-node))
      (local after-b (view:get-position second-node))
      (local delta-a (- after-a before-a))
      (local delta-b (- after-b before-b))
      (assert (> (glm.length delta-a) 0.001)
              "ordered-list island body should move during force layout")
      (assert-vec3 delta-b delta-a
                   "ordered-list island members should move by the same aggregate delta")
      (assert-close (- after-a.y after-b.y) 24
                    "ordered-list island spacing should be preserved after force layout"))
  ```

- [ ] **Step 2: Register the new test**

  Add:

  ```fennel
  (fn graph-view-list-created-island-moves-as-force-layout-unit []
      (with-list-fixture
          check-list-created-island-moves-as-force-layout-unit))
  ```

  Add the table entry near the other ordered-list island tests:

  ```fennel
  (table.insert tests {:name "GraphView list-created island moves as force-layout unit"
                       :fn graph-view-list-created-island-moves-as-force-layout-unit})
  ```

- [ ] **Step 3: Verify RED movement behavior**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-islands:main
  ```

  Expected RED: failure on `"ordered-list island body should move during force layout"` or the same-delta assertion.

- [ ] **Step 4: Add aggregate-layout presenter support**

  In `assets/lua/graph/view/island-presenters/ordered-list.fnl`, add an `aggregate-layout-record` function that:
  - asserts `island` and `host`;
  - resolves each member key through `host:node-for-key`;
  - uses `base-position` as the aggregate body position;
  - returns a `member-placements` closure that computes placements from a supplied aggregate origin using the same spacing rules as `layout-island`.

  Required returned shape:

  ```fennel
  {:id island.id
   :members member-nodes
   :position base
   :member-placements member-placements}
  ```

  Add `:aggregate-layout-record aggregate-layout-record` to the exported presenter table.

- [ ] **Step 5: Expose host aggregate resolution**

  In `assets/lua/graph/view/island-host.fnl`, add these methods to `self`:
  - `:node-for-key (fn [_self key] (resolve-node key))`
  - `:aggregate-layout-record (fn [self island] ...)`

  `aggregate-layout-record` must:
  - require a presenter for `island.kind`;
  - return `nil` when the presenter has no `aggregate-layout-record`;
  - call `presenter.aggregate-layout-record island self`;
  - assert that any non-nil record has `:id`, `:members`, `:position`, and function `:member-placements`.

- [ ] **Step 6: Refactor GraphViewLayout to keep private force indices**

  In `assets/lua/graph/view/layout.fnl`:
  - Add private `force-indices {}`, `force-participants-by-index []`, `island-layouts {}`, and `island-member-layouts {}`.
  - Keep the existing `indices` table for GraphViewRegistry/view bookkeeping.
  - Update ForceLayout operations to use `force-indices` instead of `indices`.
  - Preserve `add-node` return value and ordinary-node behavior so non-island tests using `view.indices` and `view.layout:get-positions` keep working.

- [ ] **Step 7: Add island layout syncing to GraphViewLayout**

  Add public method:

  ```fennel
  (fn sync-island-layouts [_self records]
      ...)
  ```

  Required behavior:
  - Validate each record has a string `id`, table `members`, vec3-like `position`, and function `member-placements`.
  - Replace the active island layout record set.
  - Rebuild force participants so unpinned island members are omitted as individual ForceLayout nodes.
  - Add one ForceLayout node per island layout record at `record.position`.
  - Route edges connected to unpinned island members to the island aggregate index.
  - Skip self-edges where both endpoints resolve to the same aggregate index.
  - Call `start` after rebuild so force layout is active.

- [ ] **Step 8: Apply aggregate movement back to member points**

  In `GraphViewLayout.refresh-layout`:
  - For ordinary node participants, keep existing point-position update behavior.
  - For island participants, when the aggregate position changes:
    - call `record.member-placements new-pos`;
    - for each unpinned member node, call `set-point-position member placement "GraphViewLayout.refresh-layout:island"`;
    - collect moved member nodes in `changed`;
    - invoke optional `options.on-island-position(record.id, new-pos)` when provided.
  - Continue `update-lines` after refresh so edges track member point positions.

- [ ] **Step 9: Preserve direct member dragging**

  In `GraphViewLayout.set-node-position`:
  - If the node is an active unpinned island member with no private force index, update only the rendered point position, edge lines, and labels.
  - Do not call `layout:set-position` for that member because its force participant is the island aggregate.
  - Keep existing behavior for ordinary nodes and explicitly pinned members with private force indices.

- [ ] **Step 10: Integrate aggregate layout records in GraphView**

  In `assets/lua/graph/view/init.fnl`:
  - Add `island-layout-positions {}` runtime cache.
  - Add helper `record-island-layout-position! [island-id position]` that stores a glm vec3 copy.
  - Pass `:on-island-position record-island-layout-position!` into `GraphViewLayout`.
  - Add helper `island-with-runtime-position [island]` that overlays cached `state.position` onto a cloned island record before presenter/layout reconciliation.
  - Add helper `sync-island-layouts!` that:
    - iterates `graph-map:list-islands`;
    - applies runtime position overlay;
    - calls `island-host:aggregate-layout-record` for presenters that support aggregate layout;
    - calls `graph-layout:sync-island-layouts records`.

- [ ] **Step 11: Call island layout syncing from reconciliation lifecycle**

  In `assets/lua/graph/view/init.fnl`:
  - After `island-host:reconcile-all`, call `sync-island-layouts!`.
  - After `island-host:reconcile-island`, call `sync-island-layouts!`.
  - In island add/update handling, update the runtime cache from incoming `island.state.position` when present, then reconcile.
  - In island remove handling, clear `island-layout-positions[island.id]`, call `island-host:drop-island`, then `sync-island-layouts!`.

- [ ] **Step 12: Flush runtime island positions on capture/drop**

  In `assets/lua/graph/view/init.fnl`, add `flush-island-layout-positions!` that:
  - for each cached island id, loads the current island with `graph-map:get-island`;
  - copies existing state;
  - writes `state.position` as `[position.x position.y position.z]`;
  - calls `graph-map:update-island island-id {:state next-state}`;
  - clears cache entries for missing islands.

  Call this helper at the start of `view.capture-state` and at the start of `view.drop` before the view is marked dropped.

- [ ] **Step 13: Run focused compile and tests**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/island-presenters/ordered-list.fnl --file assets/lua/graph/view/island-host.fnl --file assets/lua/graph/view/layout.fnl --file assets/lua/graph/view/init.fnl --file assets/lua/tests/test-graph-view-islands.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-islands:main
  ```

  Expected: all `test-graph-view-islands` tests pass, including snap-back and alt-drag tests.

- [ ] **Step 14: Run broader graph-view regression checks**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map:main
  ```

- [ ] **Step 15: Commit Task 2**

  ```bash
  git add assets/lua/graph/view/island-presenters/ordered-list.fnl assets/lua/graph/view/island-host.fnl assets/lua/graph/view/layout.fnl assets/lua/graph/view/init.fnl assets/lua/tests/test-graph-view-islands.fnl
  git commit -m "fix(graph): move ordered-list islands as force-layout aggregates"
  ```

---

### Task 3: Document Movable Presentation Island Semantics

**Files:**
- Modify: `docs/dev/graph-maps.md`

**Interfaces:**
- Consumes: Task 1 default unpinned behavior and Task 2 aggregate force-layout records.
- Produces: canonical developer documentation for ordered-list island layout semantics.

- [ ] **Step 1: Update the Presentation islands section**

  In `docs/dev/graph-maps.md`, update the section around `#### Presentation islands` to state:
  - presentation islands remain map-local presentation state;
  - ordered-list islands use `state.position` as the island body position;
  - ordered-list members are not pinned by default;
  - GraphView represents unpinned ordered-list members as one aggregate ForceLayout participant so the list moves as a unit;
  - explicit node pins still override movement for the pinned node;
  - alt-drag updates the island body position on drag end;
  - persisted island pin UI/API is not defined in this change.

- [ ] **Step 2: Run documentation diff review**

  Run:

  ```bash
  git diff -- docs/dev/graph-maps.md
  ```

  Expected: the doc describes the changed behavior without mentioning implementation alternatives.

- [ ] **Step 3: Commit Task 3**

  ```bash
  git add docs/dev/graph-maps.md
  git commit -m "docs(graph): document movable ordered-list islands"
  ```

---

### Task 4: Final Validation and Integration Readiness

**Files:**
- Validate: `assets/lua/graph/view/island-presenters/ordered-list.fnl`
- Validate: `assets/lua/graph/view/island-host.fnl`
- Validate: `assets/lua/graph/view/layout.fnl`
- Validate: `assets/lua/graph/view/init.fnl`
- Validate: `assets/lua/tests/test-graph-view-islands.fnl`
- Validate: `docs/dev/graph-maps.md`

**Interfaces:**
- Consumes: all prior task commits.
- Produces: validation evidence for final handoff and PR.

- [ ] **Step 1: Ensure runtime is fresh enough**

  If `./build/space` is missing or stale, run:

  ```bash
  make build
  ```

- [ ] **Step 2: Run first focused Fennel compile check**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/island-presenters/ordered-list.fnl --file assets/lua/graph/view/island-host.fnl --file assets/lua/graph/view/layout.fnl --file assets/lua/graph/view/init.fnl --file assets/lua/tests/test-graph-view-islands.fnl
  ```

- [ ] **Step 3: Run constraints**

  ```bash
  make constraints
  ```

- [ ] **Step 4: Run focused island tests**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-islands:main
  ```

- [ ] **Step 5: Run broader graph suites**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map:main
  ```

- [ ] **Step 6: Run full relevant local suite**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- [ ] **Step 7: Confirm clean final diff**

  ```bash
  git status --porcelain
  git diff --stat origin/main...
  ```

- [ ] **Step 8: Record final handoff evidence**

  Include:
  - compile-check command/result;
  - constraints command/result and constraint-impact note;
  - focused island test command/result;
  - broader graph suite command/results;
  - `make test` command/result if run;
  - note that PR CI remains the full integration gate.

## Out of Scope

- Adding a new explicit island pin UI, menu action, persistence key, or public API is out of scope pending human approval.
- Changing C++ ForceLayout physics, Barnes-Hut behavior, bounds, or binding signatures is out of scope.
- Reordering list entities by dragging ordered-list island members is out of scope.
- Changing list entity domain storage, identity resolution, or GraphMap persistence schema beyond existing island `state.position` updates is out of scope.
- E2E snapshot updates are out of scope unless focused runtime validation exposes a visual regression requiring them.
