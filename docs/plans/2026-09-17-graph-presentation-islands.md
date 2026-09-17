# Graph Presentation Islands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build graph-map-owned presentation islands with a minimally useful ordered-list island that arranges list item nodes vertically in graph space.

**Architecture:** `GraphMap` will own persisted island records and expose constrained island mutation APIs/signals. `GraphView` will host island presenters through a generic presenter host, with an ordered-list presenter registered by kind rather than hardcoded list-entity branches in graph view. List entity nodes will request materialization and island creation/update through `GraphMap` APIs.

**Tech Stack:** Space Fennel, `GraphMap`, `GraphView`, `ForceLayout`, `Signal`, project JSON persistence, project-native Fennel test runner.

## Global Constraints

- The graph is an exposure/adaptor layer; it does not own the objects it exposes.
- `GraphMap` owns map-local topology and presentation state.
- Domain data remains owned by domain stores.
- `GraphView` must not contain hardcoded domain branches such as `if list entity then vertical stack`.
- Do not start with soft force constraints for ordered lists.
- Occurrence/member indirection for ordered thought children is out of scope.
- Use project-native Fennel validation only: `tools.fennel-check`, constraints, and Fennel tests; do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e`.
- If `./build/space` may be missing or stale, run `make build` with a 4-hour timeout (`timeout: 14400000`) before validation.

---

### Task 1: GraphMap Island Record API

**Files:**
- Create: `assets/lua/graph/islands.fnl`
- Create: `assets/lua/tests/test-graph-islands.fnl`
- Modify: `assets/lua/graph/map.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: existing `Signal`, `GraphMap:capture-state`, `GraphMap:restore-state`, `GraphMap:remove-nodes`.
- Produces:
  - `GraphIslands.clone-record(record: table) -> table`
  - `GraphIslands.normalize-record(record: table, context: string) -> table`
  - `GraphIslands.records-equal?(left: table, right: table) -> boolean`
  - `GraphMap` fields: `islands: table`, `island-added: Signal`, `island-updated: Signal`, `island-removed: Signal`
  - `graph-map:create-island(opts: table) -> table`
  - `graph-map:upsert-island(opts: table) -> table`
  - `graph-map:update-island(id: string, patch: table) -> table`
  - `graph-map:remove-island(id: string, opts?: table) -> table|nil`
  - `graph-map:get-island(id: string) -> table|nil`
  - `graph-map:list-islands() -> table`
  - `graph-map:prune-islands-for-node-keys(valid-node-keys: table) -> table`

- [ ] **Step 1: Write failing island API tests**
  - In `assets/lua/tests/test-graph-islands.fnl`, add direct `:main` support via `tests/runner.run-tests`.
  - Add these tests:
    - `GraphMap upserts captures and restores islands`
    - `GraphMap rejects invalid island records`
    - `GraphMap removes island without removing member nodes`
    - `GraphMap removes origin node while island remains`
    - `GraphMap prunes removed member nodes from islands`
  - Register `:tests.test-graph-islands` in `assets/lua/tests/fast.fnl` near `:tests.test-graph-map`.

- [ ] **Step 2: Run focused test and verify it fails**

  Run `make build` first if `./build/space` is missing or stale.

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-graph-islands.fnl --file assets/lua/tests/fast.fnl
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-islands:main
  ```

  Expected: compile passes; focused test fails because `graph/islands` and `GraphMap` island methods do not exist yet.

- [ ] **Step 3: Implement island record validation/cloning**
  - In `assets/lua/graph/islands.fnl`, validate:
    - `id` is a non-empty string.
    - `kind` is a non-empty string.
    - `members` is an array of non-empty string graph keys with no duplicates.
    - `state` is a table or defaults to `{}`.
  - Return cloned records so callers cannot mutate stored `GraphMap` state by holding returned tables.
  - Use `local`, factory-returned tables, and explicit errors; do not add silent fallback records.

- [ ] **Step 4: Add GraphMap island storage, signals, and APIs**
  - In `assets/lua/graph/map.fnl`, add `islands`, `island-added`, `island-updated`, and `island-removed`.
  - Add `next-island-id` internal counter; allocate `"island-<n>"` when `create-island` receives no `:id`.
  - `create-island` must reject duplicate ids.
  - `upsert-island` must create when absent and update when present.
  - `update-island` must preserve `id` and `kind`; allow `:members` and `:state` changes only.
  - `remove-island` must remove only the island record and must not remove graph nodes, edges, or domain entities.
  - `list-islands` must return records sorted by id.

- [ ] **Step 5: Persist islands in GraphMap capture/restore**
  - Extend `capture-state` to include:

    ```fennel
    :islands [...]
    :next_island_id next-island-id
    ```

  - Extend `restore-state` to accept missing `:islands` as `[]` for backward compatibility.
  - Restored island records must emit `island-added` after validation.

- [ ] **Step 6: Reconcile islands during node removal**
  - In `remove-nodes`, after map membership is updated, remove removed node keys from island members.
  - Drop islands that have zero members after pruning.
  - Do not remove an island merely because `state.list-key` or another presenter-owned state key references the removed node.

- [ ] **Step 7: Validate Task 1**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/islands.fnl --file assets/lua/graph/map.fnl --file assets/lua/tests/test-graph-islands.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-islands:main
  ```

- [ ] **Step 8: Commit Task 1**

  ```bash
  git add assets/lua/graph/islands.fnl assets/lua/graph/map.fnl assets/lua/tests/test-graph-islands.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(graph): add graph map presentation island records"
  ```

---

### Task 2: GraphMapManager Island Persistence and Hydration Pruning

**Files:**
- Modify: `assets/lua/graph/map-manager.fnl`
- Modify: `assets/lua/tests/test-graph-islands.fnl`

**Interfaces:**
- Consumes:
  - `GraphMap:restore-state(state)` with `:islands` and `:next_island_id`
  - `GraphMap:capture-state() -> {:islands table :next_island_id number ...}`
  - `GraphMap:prune-islands-for-node-keys(valid-node-keys: table) -> table`
- Produces:
  - Map manager entries preserve `islands` and `next_island_id` across create, switch, drop, capture, and inactive hydration.
  - Hydration prunes island members whose graph keys cannot be resolved into the map.

- [ ] **Step 1: Add failing manager persistence tests**
  - In `assets/lua/tests/test-graph-islands.fnl`, add:
    - `GraphMapManager captures and restores island records`
    - `GraphMapManager prunes unresolved island members during hydration`
    - `GraphMapManager drops empty island after member pruning`
  - Use test key loaders for `test:a`, `test:b`, and intentionally omit a loader for `missing:item`.

- [ ] **Step 2: Run focused test and verify it fails**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-graph-islands.fnl
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-islands:main
  ```

  Expected: new manager island tests fail because manager does not preserve island fields.

- [ ] **Step 3: Thread islands through manager entry construction**
  - Update parsed map entries to include `:islands (or entry.islands [])` and `:next_island_id entry.next_island_id`.
  - Legacy graph state must produce empty islands and no compatibility aliases.

- [ ] **Step 4: Pass islands into active/inactive GraphMap construction**
  - Update `construct-map` to accept `islands` and `next-island-id`.
  - Pass both to `map:restore-state`.

- [ ] **Step 5: Capture islands from active and inactive maps**
  - Update `capture-active-map-state`, `hydrate-inactive-entry-for-capture!`, and `drop-active-map` to save `state.islands` and `state.next_island_id` into entries.

- [ ] **Step 6: Prune islands during hydration**
  - In `prune-hydrated-map!`, build the valid node-key set from `entry.map.nodes`.
  - Call `entry.map:prune-islands-for-node-keys(valid-keys)`.
  - Update `entry.islands` and `entry.next_island_id` from `entry.map:capture-state()` after pruning.

- [ ] **Step 7: Validate Task 2**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/map-manager.fnl --file assets/lua/tests/test-graph-islands.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-islands:main
  ```

- [ ] **Step 8: Commit Task 2**

  ```bash
  git add assets/lua/graph/map-manager.fnl assets/lua/tests/test-graph-islands.fnl
  git commit -m "feat(graph): persist graph map islands through map manager"
  ```

---

### Task 3: Island Presenter Host and Ordered-List Presenter

**Files:**
- Create: `assets/lua/graph/view/island-host.fnl`
- Create: `assets/lua/graph/view/island-presenters/init.fnl`
- Create: `assets/lua/graph/view/island-presenters/ordered-list.fnl`
- Create: `assets/lua/tests/test-graph-island-presenters.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes:
  - Island records shaped as `{:id string :kind string :members [string...] :state table}`
- Produces:
  - `OrderedListPresenter.kind = "ordered-list"`
  - `OrderedListPresenter.layout-island(island: table, host: table) -> table`
  - `OrderedListPresenter.apply(island: table, host: table) -> table`
  - `IslandPresenters.presenter-for-kind(kind: string) -> table|nil`
  - `GraphViewIslandHost(opts: table) -> table`
  - Host methods: `reconcile-island(island)`, `reconcile-all(islands?)`, `drop-island(id)`, `drop()`

- [ ] **Step 1: Add failing presenter and host tests**
  - In `assets/lua/tests/test-graph-island-presenters.fnl`, add direct `:main` support.
  - Add these tests:
    - `OrderedListPresenter computes deterministic vertical placements`
    - `OrderedListPresenter uses state position before member fallback`
    - `IslandHost errors on missing presenter kind`
    - `IslandHost pins and unpins island members through host callbacks`
  - Register `:tests.test-graph-island-presenters` in `assets/lua/tests/fast.fnl`.

- [ ] **Step 2: Run focused test and verify it fails**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-graph-island-presenters.fnl --file assets/lua/tests/fast.fnl
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-island-presenters:main
  ```

  Expected: compile or focused test fails because presenter modules do not exist.

- [ ] **Step 3: Implement ordered-list layout**
  - `layout-island` must:
    - read ordered member keys from `island.members`;
    - choose base position from `island.state.position`, then `host:position-for-key(island.state.list-key)`, then `host:position-for-key(first-member-key)`, then `glm.vec3 0 0 0`;
    - use spacing from `island.state.spacing` or `24`;
    - place members at `base.x`, `base.y - spacing * (index - 1)`, `base.z`.
  - `apply` must call:
    - `host:set-member-position(island.id, key, position)`
    - `host:set-member-pinned(island.id, key, true)`

- [ ] **Step 4: Implement presenter registry**
  - `assets/lua/graph/view/island-presenters/init.fnl` must register only `"ordered-list"` initially.
  - Missing kinds must return `nil`; the host, not the registry, raises the visible error.

- [ ] **Step 5: Implement IslandHost**
  - Required `opts`:
    - `:presenters`
    - `:node-for-key`
    - `:position-for-key`
    - `:set-node-position`
    - `:set-node-pinned`
  - `reconcile-island` must fail visibly with `"missing graph island presenter kind: <kind>"` when no presenter is registered.
  - Host must track which member keys it pinned per island and unpin previous members that are no longer in that island.
  - Host must not expose graph view registry tables or mutate presenter state directly.

- [ ] **Step 6: Validate Task 3**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/island-host.fnl --file assets/lua/graph/view/island-presenters/init.fnl --file assets/lua/graph/view/island-presenters/ordered-list.fnl --file assets/lua/tests/test-graph-island-presenters.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-island-presenters:main
  ```

- [ ] **Step 7: Commit Task 3**

  ```bash
  git add assets/lua/graph/view/island-host.fnl assets/lua/graph/view/island-presenters/init.fnl assets/lua/graph/view/island-presenters/ordered-list.fnl assets/lua/tests/test-graph-island-presenters.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(graph): add island presenter host and ordered list presenter"
  ```

---

### Task 4: GraphView Island Host Integration

**Files:**
- Modify: `assets/lua/graph/view/init.fnl`
- Modify: `assets/lua/graph/view/layout.fnl`
- Create: `assets/lua/tests/test-graph-view-islands.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes:
  - `GraphMap:list-islands()`
  - `graph-map.island-added`, `graph-map.island-updated`, `graph-map.island-removed`
  - `GraphViewIslandHost`
  - `GraphViewLayout:set-node-position(node, position, opts?)`
- Produces:
  - `GraphViewLayout:set-node-pinned(node: table, pinned?: boolean) -> boolean`
  - `view.island-host`
  - GraphView reconciliation for island add/update/remove and drag-end snap-back.

- [ ] **Step 1: Add failing GraphView integration tests**
  - In `assets/lua/tests/test-graph-view-islands.fnl`, add direct `:main` support.
  - Add these tests:
    - `GraphView applies ordered-list island positions`
    - `GraphView updates island layout when island changes`
    - `GraphView fails visibly for missing island presenter`
    - `GraphView unpins members after island removal`
  - Register `:tests.test-graph-view-islands` in `assets/lua/tests/fast.fnl`.

- [ ] **Step 2: Run focused test and verify it fails**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-graph-view-islands.fnl --file assets/lua/tests/fast.fnl
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-islands:main
  ```

  Expected: test fails because GraphView does not host islands.

- [ ] **Step 3: Add pin control to GraphViewLayout**
  - Implement `set-node-pinned` in `assets/lua/graph/view/layout.fnl`.
  - It must:
    - assert the node has a layout index;
    - update the underlying `ForceLayout` pin state;
    - return `true`.
  - Do not add soft force constraints.

- [ ] **Step 4: Instantiate IslandHost inside GraphView**
  - Require `graph/view/island-host` and `graph/view/island-presenters`.
  - Create `island-host` after `graph-layout` and before graph signal attachment.
  - Host callbacks must use constrained view APIs:
    - `node-for-key`: `graph-map:lookup(key)`
    - `position-for-key`: `get-position(nil, node)` when the node exists
    - `set-node-position`: `graph-layout:set-node-position(node, pos, {:skip-labels? true})`
    - `set-node-pinned`: update `pinned[node]`, then `graph-layout:set-node-pinned(node, pinned?)`

- [ ] **Step 5: Wire island signals**
  - Connect `graph-map.island-added` and `graph-map.island-updated` to `island-host:reconcile-island(payload.island)`.
  - Connect `graph-map.island-removed` to `island-host:drop-island(payload.island.id)`.
  - Disconnect these handlers in `detach-graph`.

- [ ] **Step 6: Reconcile initial and drag-end layouts**
  - After initial node/edge handling in GraphView startup, call `island-host:reconcile-all(graph-map:list-islands())`.
  - In movable drag end, after label refresh, call `island-host:reconcile-all(graph-map:list-islands())` so ordered-list members snap back to presenter-owned positions.

- [ ] **Step 7: Drop island host**
  - In GraphView `drop`, call `island-host:drop()` before clearing pinned tables and dropping movables.
  - Expose `view.island-host = island-host` for tests and debugging.

- [ ] **Step 8: Validate Task 4**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/init.fnl --file assets/lua/graph/view/layout.fnl --file assets/lua/tests/test-graph-view-islands.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-islands:main
  ```

- [ ] **Step 9: Commit Task 4**

  ```bash
  git add assets/lua/graph/view/init.fnl assets/lua/graph/view/layout.fnl assets/lua/tests/test-graph-view-islands.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(graph): host presentation islands in graph view"
  ```

---

### Task 5: List Entity Expand Items as Ordered-List Island

**Files:**
- Modify: `assets/lua/graph/nodes/list-entity.fnl`
- Create: `assets/lua/tests/test-ordered-list-islands.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes:
  - `graph-map:load-by-key(key: string) -> node|nil`
  - `graph-map:resolve-node(key-or-node, opts?) -> node|nil`
  - `graph-map:upsert-island(opts: table) -> table`
- Produces:
  - `list-node:expand-items-as-island(opts?: table) -> table`
  - Node action named `Expand items as island` with icon `format_list_numbered`
  - Ordered-list island records:

    ```fennel
    {:id (.. "ordered-list:" entity-id)
     :kind "ordered-list"
     :members [resolved-visible-item-key ...]
     :state {:list-key list-node.key
             :interaction-policy "snap-back"
             :spacing 24}}
    ```

- [ ] **Step 1: Add failing ordered-list materialization tests**
  - In `assets/lua/tests/test-ordered-list-islands.fnl`, add direct `:main` support.
  - Add these tests:
    - `ListEntityNode expands item nodes as ordered-list island`
    - `ListEntityNode updates existing ordered-list island in store order`
    - `ListEntityNode resolves identity items to visible target keys`
    - `Removing ordered-list island does not delete list or item entities`
    - `ListEntityNode exposes Expand items as island action`
  - Register `:tests.test-ordered-list-islands` in `assets/lua/tests/fast.fnl`.

- [ ] **Step 2: Run focused test and verify it fails**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-ordered-list-islands.fnl --file assets/lua/tests/fast.fnl
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-ordered-list-islands:main
  ```

  Expected: test fails because list nodes cannot create islands yet.

- [ ] **Step 3: Refactor item resolution inside ListEntityNode**
  - Extract current item resolution logic from `add-item-nodes` into a local helper that returns the visible target node for a list item key.
  - Preserve existing `Refresh Items` behavior and derived/list edge behavior.

- [ ] **Step 4: Implement `expand-items-as-island`**
  - Assert the node is mounted into a graph map with `load-by-key` and `upsert-island`.
  - Iterate current list entity `items` in stored order.
  - Resolve identity keys to their target graph key when applicable.
  - Load each visible item into the graph map.
  - Build `members` from loaded node keys in the same order.
  - Upsert island id `"ordered-list:<entity-id>"`.
  - Return the island record from `graph-map:upsert-island`.

- [ ] **Step 5: Keep existing islands fresh on list item changes**
  - In `handle-items-changed`, after `node:add-item-nodes`, check whether `graph-map:get-island("ordered-list:<entity-id>")` exists.
  - If it exists, call `node:expand-items-as-island`.
  - If no island exists, do not create one passively.

- [ ] **Step 6: Add the node action and validate icon availability**
  - Confirm the icon exists before implementation:

    ```bash
    rg '^format_list_numbered$' assets/material-design-icons/icons.txt
    ```

  - Add action:

    ```fennel
    {:name "Expand items as island"
     :icon "format_list_numbered"
     :fn (fn [_button _event]
           (node:expand-items-as-island))}
    ```

  - Keep `Refresh Items` and `Delete Entity` actions.

- [ ] **Step 7: Validate Task 5**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/nodes/list-entity.fnl --file assets/lua/tests/test-ordered-list-islands.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-ordered-list-islands:main
  ```

- [ ] **Step 8: Commit Task 5**

  ```bash
  git add assets/lua/graph/nodes/list-entity.fnl assets/lua/tests/test-ordered-list-islands.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(graph): expand list entities as ordered presentation islands"
  ```

---

### Task 6: Developer Documentation

**Files:**
- Modify: `docs/dev/graph-maps.md`
- Modify: `docs/dev/notes/graph.md`

**Interfaces:**
- Consumes: final public behavior from Tasks 1-5.
- Produces: documented graph doctrine and GraphMap island ownership model.

- [ ] **Step 1: Update `docs/dev/graph-maps.md`**
  - Add `Presentation islands` under Graph Map State.
  - Document persisted island shape:

    ```text
    {:id string
     :kind string
     :members [graph-key ...]
     :state presenter-owned-table}
    ```

  - State that GraphMap persists island records and GraphView hosts presenters.
  - State that removing an island does not delete nodes or domain entities.
  - State that ordered-list islands are initially snap-back vertical presentations, not domain reorder controls.

- [ ] **Step 2: Update `docs/dev/notes/graph.md`**
  - Add a short note that graph presentation islands are map-local presentation state over graph-exposed objects.
  - Reinforce that presenter kinds must not make domain stores subordinate to graph view.

- [ ] **Step 3: Validate docs task**

  ```bash
  rg "presentation islands|ordered-list|GraphMap persists island" docs/dev/graph-maps.md docs/dev/notes/graph.md
  ```

- [ ] **Step 4: Commit Task 6**

  ```bash
  git add docs/dev/graph-maps.md docs/dev/notes/graph.md
  git commit -m "docs(graph): document presentation islands"
  ```

---

## Observable Acceptance Criteria

- A `GraphMap` can create, update, remove, capture, restore, and list generic island records without storing domain data.
- Legacy graph map state without `islands` still loads.
- GraphMapManager captures/restores island records and prunes unresolved island members during hydration.
- Removing the list node that originally requested an island does not remove the island when its members remain.
- Removing an island does not delete list entities, string entities, identity entities, link entities, or member graph nodes.
- GraphView hosts island presenters by `kind`; ordered-list behavior is not implemented as a list-entity branch in GraphView.
- Missing presenter kinds fail visibly.
- Ordered-list islands deterministically place member nodes vertically in stored list order.
- List entity nodes expose `Expand items as island`, materialize item nodes, and upsert an `ordered-list` island.

## Validation Ladder

1. **Runtime/freshness prerequisite when needed**

   ```bash
   make build
   ```

2. **Focused compile checks first**
   - For each task, run the touched-file `tools.fennel-check` command listed in that task.
   - If a delimiter or parse error appears, inspect the nearest enclosing form around the reported location, simplify deeply nested forms into helpers, then rerun the same compile check before running constraints.

3. **Constraints second**

   ```bash
   make constraints
   ```

4. **Focused Fennel tests third**

   ```bash
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-islands:main
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-island-presenters:main
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-islands:main
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-ordered-list-islands:main
   ```

5. **Complete relevant local suite**
   - Justification: this changes GraphMap persistence/hydration, GraphView layout/drag behavior, and graph node actions, all of which have broad map/view regression risk.

   ```bash
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
   ```

6. **Final integration gate**
   - PR CI is the full integration gate. Do not claim ready-to-merge until PR CI is green.

## Risks to Watch During Implementation and Testing

- Island presenter power can blur ownership boundaries; keep presenters limited to host APIs and never let them mutate GraphView internals directly.
- GraphMap persistence schema can drift; validate and clone island records at API boundaries.
- Missing presenter kinds must fail visibly so persisted islands are not silently dropped.
- Ordered-list snap-back may surprise users expecting drag reorder; reorder/detach behavior is intentionally out of scope for this first vertical slice.
- GraphView layout pinning can affect force layout; tests must verify unpinning when islands are removed.
- If implementation shows that islands are too powerful or too hard to reconcile, narrow the first slice to ordered-list islands and keep the generic host smaller.

## Explicitly Out of Scope

- A full Logseq-like outline activity.
- Specialized block/outline domain entities.
- Soft force constraints for ordered child lists.
- Making island state domain truth.
- Generic graph-view special cases for list entities.
- Occurrence/member indirection for ordered thought children.
- Drag-to-reorder, detach-on-drag, external drop into islands, island chrome, island labels, group drag, and overlapping-island resolution.
