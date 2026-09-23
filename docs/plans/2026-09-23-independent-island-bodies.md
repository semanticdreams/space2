# Independent Island Bodies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make graph presentation islands independent map-local layout bodies whose `state.position` is an absolute island body position, not a source-node-relative anchor.

**Architecture:** Keep island records in `GraphMap` and presenter dispatch in `GraphView` unchanged. Narrow the behavioral change to ordered-list presenter positioning, list-node island initialization/preservation, focused regression tests, and canonical developer documentation. `state.list-key` may remain metadata, but no presenter may use it to derive a missing position.

**Tech Stack:** Space Fennel (`.fnl`), `GraphMap`, `GraphView`, ordered-list island presenter, list entity graph node, project-native `./build/space` Fennel test runner.

## Global Constraints

- Make every graph presentation island an independent map-local layout body.
- Island presenter state uses `state.position` as the island body's absolute graph position.
- For `ordered-list`, the first item is placed at `state.position`, and later items are offset vertically by `state.spacing`.
- If an island is created by a node action, that action may initialize `state.position` near the creating node for convenience.
- After creation, the stored island position is authoritative and independent.
- Presenters must not use `state.list-key` to derive positions when `state.position` is missing.
- For restored legacy records with no `state.position`, presenters should fall back to an island-local default or existing member position rather than re-anchoring to a source node.
- `ListEntityNode:expand-items-as-island` should materialize current item nodes through the mounted `GraphMap`.
- `ListEntityNode:expand-items-as-island` should upsert an `ordered-list` island whose members are item node keys in stored list order.
- `ListEntityNode:expand-items-as-island` should preserve an existing island's `state.position` on refresh.
- `ListEntityNode:expand-items-as-island` should initialize a new island's `state.position` near the list node only as an initial placement convenience.
- `ListEntityNode:expand-items-as-island` should refresh existing islands when list items or identity targets change.
- `ListEntityNode:expand-items-as-island` should remove an existing island when it has no members.
- Do not make islands own domain data. List order remains owned by the list entity store.
- Do not add user-facing island policy controls in this slice.
- Do not implement domain reordering through drag operations.
- Do not require richer member role records unless a concrete presenter needs them later.
- Missing mounted graph map or island APIs should fail loudly.
- Missing presenter kinds should continue to fail visibly in `GraphView`.
- Invalid island position shapes should continue to raise explicit errors during normalization or presenter conversion.

---

## Implementation Invariants

- `assets/lua/graph/view/island-presenters/ordered-list.fnl` must not call `host:position-for-key state.list-key`.
- `state.list-key` may remain on list-created island records as non-spatial metadata only.
- Legacy ordered-list islands without `state.position` use first-member current position when available, otherwise `(glm.vec3 0 0 0)`.
- New list-created islands may read the current list node presentation point once to choose initial `state.position`.
- Refreshing an existing list-created island must preserve the existing island `state.position` exactly.
- Removing an island must not remove list entities, item entities, or graph-visible member nodes.

## Observable Acceptance Criteria

- Ordered-list presenter tests prove no source/list-key fallback remains.
- List entity island tests prove new islands initialize near the list node but preserve body position after refresh/source movement.
- GraphView island tests prove unrelated drag-end reconciliation does not re-anchor list-created or restored legacy islands to the list node.
- Developer documentation states that island `state.position` is an absolute body position.
- Focused Fennel validation passes in this order: compile check, constraints, focused tests.
- PR CI is the full integration gate.

## Validation Environment

Use this environment for direct `./build/space` test commands:

```bash
export SPACE_DISABLE_AUDIO=1
export SKIP_KEYRING_TESTS=1
export XDG_DATA_HOME=/tmp/space/tests/xdg-data
export SPACE_ASSETS_PATH="$(pwd)/assets"
export FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"
export FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"
```

Runtime/freshness prerequisite before any `./build/space` validation when the binary may be missing or stale:

```bash
make build
```

Fennel delimiter/parse-error repair rule: inspect the nearest enclosing form around the reported location first; if the form is deeply nested, move logic into a small helper rather than guessing at closing delimiters.

---

### Task 1: Make OrderedListPresenter independent from source-node anchors

**Files:**
- Modify: `assets/lua/graph/view/island-presenters/ordered-list.fnl`
- Test: `assets/lua/tests/test-graph-island-presenters.fnl`
- Test: `assets/lua/tests/test-ordered-list-islands.fnl`

**Interfaces:**
- Consumes: `OrderedListPresenter.layout-island(island: table, host: table) -> table<string, glm.vec3>`
- Consumes: `host:position-for-key(key: string) -> glm.vec3|nil`
- Produces: `OrderedListPresenter.layout-island` with base-position precedence `state.position`, first member position, default origin.
- Produces: `OrderedListPresenter.apply(island: table, host: table) -> table<string, glm.vec3>` with unchanged pinning behavior.

- [ ] **Step 1: Replace the source-anchor presenter test with member/default fallback tests**

In `assets/lua/tests/test-graph-island-presenters.fnl`, replace `ordered-list-presenter-offsets-list-key-anchored-vertical-placements` with:

```fennel
(fn ordered-list-presenter-uses-member-position-for-legacy-island-without-body-position []
    (local host (make-host {:positions {"list:1" (glm.vec3 100 200 3)
                                        "item:a" (glm.vec3 10 20 30)}}))
    (local island {:id "island-1"
                   :kind "ordered-list"
                   :members ["item:a" "item:b" "item:c"]
                   :state {:list-key "list:1" :spacing 10}})
    (local layout (OrderedListPresenter.layout-island island host))
    (assert-vec3 (. layout "item:a") (glm.vec3 10 20 30)
                 "legacy island without body position should fall back to first member position")
    (assert-vec3 (. layout "item:b") (glm.vec3 10 10 30)
                 "second member should offset from member fallback by spacing")
    (assert-vec3 (. layout "item:c") (glm.vec3 10 0 30)
                 "third member should offset from member fallback deterministically"))

(fn ordered-list-presenter-uses-default-origin-without-body-or-member-position []
    (local host (make-host {:positions {"list:1" (glm.vec3 100 200 3)}}))
    (local island {:id "island-1"
                   :kind "ordered-list"
                   :members ["item:a" "item:b"]
                   :state {:list-key "list:1"}})
    (local layout (OrderedListPresenter.layout-island island host))
    (assert-vec3 (. layout "item:a") (glm.vec3 0 0 0)
                 "legacy island without body or member position should use default origin")
    (assert-vec3 (. layout "item:b") (glm.vec3 0 -24 0)
                 "default spacing should apply from default origin"))
```

Update the `table.insert` section:

```fennel
(table.insert tests {:name "OrderedListPresenter uses member position for legacy island without body position"
                     :fn ordered-list-presenter-uses-member-position-for-legacy-island-without-body-position})
(table.insert tests {:name "OrderedListPresenter uses default origin without body or member position"
                     :fn ordered-list-presenter-uses-default-origin-without-body-or-member-position})
```

- [ ] **Step 2: Update the ordered-list island presenter regression test**

In `assets/lua/tests/test-ordered-list-islands.fnl`, replace `ordered-list-presenter-offsets-old-format-list-key-anchor` with:

```fennel
(fn ordered-list-presenter-uses-member-position-for-old-format-island []
  (local list-key "list-entity:list")
  (local member-key "string-entity:a")
  (local positions {})
  (set (. positions list-key) {:x 24 :y 0 :z 0})
  (set (. positions member-key) {:x 300 :y 400 :z 0})
  (local island {:id "ordered-list:list"
                 :kind "ordered-list"
                 :members [member-key]
                 :state {:list-key list-key
                         :spacing 24}})
  (OrderedListPresenter.apply island (make-reconcile-host positions))
  (local first-position (. positions member-key))
  (assert-vec3-position first-position {:x 300 :y 400 :z 0}
                        "old-format island should fall back to existing member position")
  (local list-position (. positions list-key))
  (assert (not (and (= first-position.x list-position.x)
                    (= first-position.y list-position.y)
                    (= first-position.z list-position.z)))
          "old-format island first item should not re-anchor to the list node"))
```

Update the registration name/function:

```fennel
(table.insert tests {:name "OrderedListPresenter uses member position for old-format island"
                     :fn ordered-list-presenter-uses-member-position-for-old-format-island})
```

- [ ] **Step 3: Run the focused tests and verify they fail before implementation**

```bash
make build
export SPACE_DISABLE_AUDIO=1
export SKIP_KEYRING_TESTS=1
export XDG_DATA_HOME=/tmp/space/tests/xdg-data
export SPACE_ASSETS_PATH="$(pwd)/assets"
export FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"
export FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"
./build/space -m tests.test-graph-island-presenters:main
./build/space -m tests.test-ordered-list-islands:main
```

Expected: both fail on old list-key/source-anchor behavior.

- [ ] **Step 4: Remove source-key fallback from ordered-list presenter**

In `assets/lua/graph/view/island-presenters/ordered-list.fnl`, replace `base-position` with:

```fennel
(fn base-position [island host]
    (local state (if island.state island.state {}))
    (local state-position (vec3-copy state.position "OrderedListPresenter state.position"))
    (local first-member-key (. island.members 1))
    (local member-position (if first-member-key
                               (vec3-copy (host:position-for-key first-member-key)
                                          "OrderedListPresenter member position")))
    (if state-position
        state-position
        member-position
        member-position
        (fallback-origin)))
```

Also remove the unused `default-anchor-offset` binding from the top of the file.

- [ ] **Step 5: Confirm no source-anchor lookup remains in the presenter**

```bash
rg "host:position-for-key state.list-key|default-anchor-offset|list-key anchor" assets/lua/graph/view/island-presenters/ordered-list.fnl
```

Expected: no matches.

- [ ] **Step 6: Run focused validation for this task**

```bash
make fennel-check
make constraints
./build/space -m tests.test-graph-island-presenters:main
./build/space -m tests.test-ordered-list-islands:main
```

Expected: all pass.

- [ ] **Step 7: Commit Task 1**

```bash
git add assets/lua/graph/view/island-presenters/ordered-list.fnl \
        assets/lua/tests/test-graph-island-presenters.fnl \
        assets/lua/tests/test-ordered-list-islands.fnl
git commit -m "fix(graph): make ordered-list islands independent bodies"
```

---

### Task 2: Cover list-created island body initialization and preservation

**Files:**
- Modify: `assets/lua/graph/nodes/list-entity.fnl`
- Test: `assets/lua/tests/test-ordered-list-islands.fnl`

**Interfaces:**
- Consumes: `ListEntityNode:expand-items-as-island(_opts: table|nil) -> island record|nil`
- Consumes: `GraphMap:get-island(id: string) -> island record|nil`
- Consumes: `GraphMap:upsert-island(record: table) -> island record`
- Produces: list-created `ordered-list` island records with `state.position` initialized once and preserved on refresh.

- [ ] **Step 1: Add a regression test for initial placement near the list node and preservation after source movement**

Add this function to `assets/lua/tests/test-ordered-list-islands.fnl` after `list-entity-node-expands-item-nodes-as-ordered-list-island`:

```fennel
(fn list-entity-node-initializes-island-body-near-list-node-then-preserves-it []
  (with-fixture
    (fn [fixture]
      (local key-a (create-string fixture "a" "A"))
      (local key-b (create-string fixture "b" "B"))
      (local key-c (create-string fixture "c" "C"))
      (local entity (create-list fixture "list" [key-a key-b]))
      (local list-node (fixture.map:load-by-key (.. "list-entity:" entity.id)))
      (set fixture.map.presentation-points {})
      (set (. fixture.map.presentation-points list-node.key)
           {:position (glm.vec3 100 200 3)})
      (local island (list-node:expand-items-as-island))
      (assert-position-array island.state.position [124 200 3]
                             "new list-created island should initialize near current list node")
      (set (. fixture.map.presentation-points list-node.key)
           {:position (glm.vec3 900 901 9)})
      (fixture.list-store:reorder-items entity.id [key-c key-b key-a])
      (local refreshed (fixture.map:get-island "ordered-list:list"))
      (assert-members refreshed [key-c key-b key-a])
      (assert-position-array refreshed.state.position [124 200 3]
                             "refresh should preserve island body position instead of re-reading source position"))))
```

Ensure `glm` is required at the top of `test-ordered-list-islands.fnl`:

```fennel
(local glm (require :glm))
```

- [ ] **Step 2: Register the new test**

Add this registration near the other list-created island tests:

```fennel
(table.insert tests {:name "ListEntityNode initializes island body near list node then preserves it"
                     :fn list-entity-node-initializes-island-body-near-list-node-then-preserves-it})
```

- [ ] **Step 3: Run the focused test**

```bash
make build
export SPACE_DISABLE_AUDIO=1
export SKIP_KEYRING_TESTS=1
export XDG_DATA_HOME=/tmp/space/tests/xdg-data
export SPACE_ASSETS_PATH="$(pwd)/assets"
export FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"
export FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"
./build/space -m tests.test-ordered-list-islands:main
```

Expected: pass if current preservation behavior is already correct; fail if source position is reread during refresh.

- [ ] **Step 4: Keep the existing preservation rule explicit if implementation is needed**

In `assets/lua/graph/nodes/list-entity.fnl`, ensure `island-origin-position` keeps this precedence:

```fennel
(fn island-origin-position [list-node existing-island]
  (if (and existing-island existing-island.state existing-island.state.position)
      existing-island.state.position
      (do
        (local graph list-node.graph)
        (local list-point (and graph graph.presentation-points
                               (. graph.presentation-points list-node.key)))
        (local list-position (and list-point list-point.position))
        (if list-position
            [(+ list-position.x 24) list-position.y list-position.z]
            [24 0 0]))))
```

Do not add aliases or alternate option keys.

- [ ] **Step 5: Run focused validation for this task**

```bash
make fennel-check
make constraints
./build/space -m tests.test-ordered-list-islands:main
```

Expected: all pass.

- [ ] **Step 6: Commit Task 2**

```bash
git add assets/lua/graph/nodes/list-entity.fnl \
        assets/lua/tests/test-ordered-list-islands.fnl
git commit -m "test(graph): cover list island body preservation"
```

---

### Task 3: Update GraphView integration coverage for independent island bodies

**Files:**
- Modify: `assets/lua/tests/test-graph-view-islands.fnl`

**Interfaces:**
- Consumes: `GraphView` island reconciliation through `view.island-host`
- Consumes: `GraphMap:restore-state(state: table) -> boolean`
- Consumes: `ListEntityNode:expand-items-as-island() -> island record`
- Produces: integration tests proving drag-end reconciliation uses stored island body/member fallback, not source node anchors.

- [ ] **Step 1: Rename and strengthen the list-created island drag-end helper**

In `assets/lua/tests/test-graph-view-islands.fnl`, replace `check-list-created-island-uses-list-node-offset-after-unrelated-drag-end` with:

```fennel
(fn check-list-created-island-preserves-body-position-after-unrelated-drag-end [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local item-node (map:lookup fixture.item-key))
    (local unrelated-node (map:lookup fixture.unrelated-key))
    (local list-entry (. movables.by-node list-node))
    (local item-entry (. movables.by-node item-node))
    (local unrelated-entry (. movables.by-node unrelated-node))
    (assert list-entry "list node should be movable")
    (assert item-entry "list item should be movable")
    (assert unrelated-entry "unrelated node should be movable")
    (list-entry.target:set-position (glm.vec3 24 0 0))
    (assert-vec3 (view:get-position list-node) (glm.vec3 24 0 0)
                 "fixture should place list node at non-origin position")
    (assert (. map.presentation-points list-node.key) "graph map should expose GraphView presentation point")
    (list-node:expand-items-as-island)
    (local island (map:get-island "ordered-list:list"))
    (assert (= (. island.state.position 1) 48)
            (.. "island body x should initialize near list node, got " (. island.state.position 1)))
    (list-entry.target:set-position (glm.vec3 500 0 0))
    (assert-vec3 (view:get-position list-node) (glm.vec3 500 0 0)
                 "source list node should be allowed to move after island creation")
    (item-entry.target:set-position (glm.vec3 300 400 0))
    (unrelated-entry.on-drag-end unrelated-entry)
    (local reconciled-position (view:get-position item-node))
    (assert-vec3 reconciled-position (glm.vec3 48 0 0)
                 "unrelated drag-end reconciliation should use stored island body position")
    (local list-position (view:get-position list-node))
    (assert (not (and (= reconciled-position.x (+ list-position.x 24))
                      (= reconciled-position.y list-position.y)
                      (= reconciled-position.z list-position.z)))
            "first list island member should not be recomputed from current list node position"))
```

- [ ] **Step 2: Rename and update the restored legacy island helper**

Replace `check-restored-old-format-list-island-offsets-from-list-node-after-drag-end` with:

```fennel
(fn check-restored-old-format-list-island-uses-member-fallback-after-drag-end [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local item-node (map:lookup fixture.item-key))
    (local unrelated-node (map:lookup fixture.unrelated-key))
    (local unrelated-entry (. movables.by-node unrelated-node))
    (assert unrelated-entry "unrelated node should be movable")
    (assert-vec3 (view:get-position list-node) (glm.vec3 24 0 0)
                 "restored fixture should materialize list node at non-origin position")
    (assert (map:get-island "ordered-list:list")
            "restored fixture should have old-format ordered-list island")
    (unrelated-entry.on-drag-end unrelated-entry)
    (local list-position (view:get-position list-node))
    (local item-position (view:get-position item-node))
    (assert-vec3 item-position (glm.vec3 300 400 0)
                 "old-format island without body position should fall back to member position")
    (assert (not (and (= item-position.x list-position.x)
                      (= item-position.y list-position.y)
                      (= item-position.z list-position.z)))
            "restored old-format island first member should not overlap list node after unrelated drag-end"))
```

- [ ] **Step 3: Rename the wrapper tests and registrations**

Replace:

```fennel
(fn graph-view-list-created-island-uses-list-node-offset-after-unrelated-drag-end []
    (with-list-fixture
        check-list-created-island-uses-list-node-offset-after-unrelated-drag-end))
```

with:

```fennel
(fn graph-view-list-created-island-preserves-body-position-after-unrelated-drag-end []
    (with-list-fixture
        check-list-created-island-preserves-body-position-after-unrelated-drag-end))
```

Replace:

```fennel
(fn graph-view-restored-old-format-list-island-offsets-from-list-node-after-drag-end []
```

with:

```fennel
(fn graph-view-restored-old-format-list-island-uses-member-fallback-after-drag-end []
```

and update its callback to:

```fennel
        check-restored-old-format-list-island-uses-member-fallback-after-drag-end))
```

Update the two `table.insert` entries:

```fennel
(table.insert tests {:name "GraphView list-created island preserves body position after unrelated drag end"
                     :fn graph-view-list-created-island-preserves-body-position-after-unrelated-drag-end})
(table.insert tests {:name "GraphView restored old-format list island uses member fallback after unrelated drag end"
                     :fn graph-view-restored-old-format-list-island-uses-member-fallback-after-drag-end})
```

- [ ] **Step 4: Run the focused integration test**

```bash
make build
export SPACE_DISABLE_AUDIO=1
export SKIP_KEYRING_TESTS=1
export XDG_DATA_HOME=/tmp/space/tests/xdg-data
export SPACE_ASSETS_PATH="$(pwd)/assets"
export FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"
export FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"
./build/space -m tests.test-graph-view-islands:main
```

Expected: pass with the Task 1 presenter change.

- [ ] **Step 5: Run focused validation for this task**

```bash
make fennel-check
make constraints
./build/space -m tests.test-graph-view-islands:main
```

Expected: all pass.

- [ ] **Step 6: Commit Task 3**

```bash
git add assets/lua/tests/test-graph-view-islands.fnl
git commit -m "test(graph): cover independent island reconciliation"
```

---

### Task 4: Document independent presentation island body semantics

**Files:**
- Modify: `docs/dev/graph-maps.md`

**Interfaces:**
- Consumes: implementation behavior from Tasks 1-3.
- Produces: canonical developer documentation for graph presentation island body positioning.

- [ ] **Step 1: Update the Presentation islands documentation**

In `docs/dev/graph-maps.md`, replace the presentation-island paragraph around the persisted shape and ordered-list behavior with this text:

````markdown
#### Presentation islands

`GraphMap` persists presentation islands as map-local presentation state over
graph-exposed objects. Domain stores continue to own domain data; island records
only describe how already-exposed graph members should be presented in this map.

Persisted island records use the generic shape:

```text
{:id string
 :kind string
 :members [graph-key ...]
 :state presenter-owned-table}
```

For presenters that lay out graph members spatially, `state.position` is the
island body's absolute graph-space position. A node action may choose an initial
body position near the creating node, but after creation the stored island body
position is authoritative and must not be recomputed from source-node metadata.

`GraphView` hosts presenters by island `:kind`. Presenter behavior such as
`ordered-list` is registered through the island presenter host rather than a
hardcoded list-entity branch in GraphView. The `ordered-list` presenter places
the first member at `state.position` and offsets later members vertically by
`state.spacing`; legacy records with no `state.position` fall back to an existing
member position or the presenter's default origin, not a list/source-node anchor.

Removing an island removes only the map-local presentation record. It does not
delete member nodes or any backing domain entities. Initial `ordered-list`
islands provide snap-back vertical presentation in stored list order; they are
not domain reorder controls.
```
````

- [ ] **Step 2: Review terminology against graph doctrine**

Confirm the documentation uses graph-doctrine terms:

```bash
rg "graph-native|first-class graph object|full graph state|lives in the graph|stored in the graph" docs/dev/graph-maps.md docs/dev/notes/graph.md
```

Expected: no new forbidden terminology in the edited section.

- [ ] **Step 3: Commit Task 4**

```bash
git add docs/dev/graph-maps.md
git commit -m "docs(graph): document island body positions"
```

---

## Final Validation Ladder

Run from a clean tree after all task commits.

1. Runtime/freshness prerequisite when needed:

```bash
make build
```

2. Fennel compile check first:

```bash
make fennel-check
```

3. Constraints second:

```bash
make constraints
```

4. Focused Fennel tests third:

```bash
export SPACE_DISABLE_AUDIO=1
export SKIP_KEYRING_TESTS=1
export XDG_DATA_HOME=/tmp/space/tests/xdg-data
export SPACE_ASSETS_PATH="$(pwd)/assets"
export FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"
export FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"

./build/space -m tests.test-graph-island-presenters:main
./build/space -m tests.test-ordered-list-islands:main
./build/space -m tests.test-graph-view-islands:main
```

5. Complete relevant local suite, justified because this changes graph presentation behavior used by fast graph/list/view coverage:

```bash
./build/space -m tests.fast:main
```

6. Broader final local check when preparing the PR, justified by graph-view behavioral risk and persistence interaction surface:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" make test
```

7. Full integration gate: **PR CI**.

## Out of Scope

- No force-layout simulation for island bodies.
- No drag-based list/domain reordering.
- No user-facing island policy controls.
- No new presenter role/member schema.
- No migration that rewrites persisted island records.
- No removal of `state.list-key` metadata from list-created records unless a test proves it is unsafe; it must simply be non-spatial.
