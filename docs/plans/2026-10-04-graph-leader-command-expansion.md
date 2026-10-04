# Graph Leader Command Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand graph leader commands for focused-node, graph-view, and graph-map operations while preserving existing preview and selection command behavior.

**Architecture:** Add a bounded first-phase command expansion: map-local topology helpers live on `GraphMap`, map creation/switch helpers live on `GraphMapManager`, focused-node action methods live on `GraphView`, and `graph/commands.fnl` binds those through runtime resolvers. Pointer context menus and keyboard numeric action slots must use one shared GraphView action-list path.

**Tech Stack:** Space Fennel, Space leader command providers, `GraphView`, `GraphMap`, `GraphMapManager`, Space Fennel tests, docs/dev Markdown.

## Global Constraints

- Preserve existing `SPC g p ...` and `SPC g s ...` bindings and semantics.
- Add only first-phase graph leader commands: focused-node, view/layout, and map/topology commands listed in the spec.
- Graph doctrine still applies: graph nodes are adapters over owning systems, `GraphMap` owns map-local interaction/topology state, and graph core persists topology only.
- Keyboard commands must not silently delete backing domain objects.
- Creating a map from selection copies map-local topology only: selected visible node keys, explicit edges whose endpoints are both selected, selection/focus limited to included nodes, and presentation islands only when all island members are included.
- Clearing a graph map removes map-local nodes, explicit edges, islands, selection, and focus, but must not delete domain objects or backing records.
- Commands must resolve the current graph view, active `GraphMap`, and `GraphMapManager` at run time rather than capturing stale instances.
- Node action command slots and pointer context menus must share the same action construction path.
- Missing required dependencies should fail explicitly or make commands unavailable; no silent topology no-ops for unavailable graph context.
- Active map delete and rename leader commands are out of scope.
- Keyboard node repositioning/nudging is out of scope.
- Do not add dependencies or introduce a generic cross-system command palette.
- Fennel-facing validation must run compile check first, constraints second, focused Fennel tests third.
- If `./build/space` is missing or stale, run `make build` before any `./build/space -m ...` validation command.
- On Fennel delimiter or parse errors, inspect the nearest enclosing form first; if the form is deeply nested, move logic into helper functions rather than adding delimiters by guesswork.

---

## File Structure

- Modify `assets/lua/graph/map.fnl`: add map-local helpers `clear!`, `clearable?`, `add-start-node!`, `capture-subgraph-state`, and `capture-selected-subgraph-state`.
- Modify `assets/lua/graph/map-manager.fnl`: add `create-and-switch-map!` for command-created empty maps and selection-derived maps.
- Modify `assets/lua/graph/view/init.fnl`: expose one focused-node action boundary shared by pointer context menus and keyboard action slots, plus focused-node command methods.
- Modify `assets/lua/graph/map-sidebar.fnl`: reuse `GraphMap:add-start-node!` for sidebar Add Start parity.
- Modify `assets/lua/graph/commands.fnl`: add `SPC g n ...`, `SPC g v ...`, and `SPC g m ...` command descriptors, availability checks, prefixes, and bindings.
- Modify `assets/lua/graph-activity-unit.fnl`: install graph commands with runtime graph view, active graph map, and graph map manager resolvers.
- Modify tests: `assets/lua/tests/test-graph-map.fnl`, `assets/lua/tests/test-graph-map-manager.fnl`, `assets/lua/tests/test-graph-view.fnl`, `assets/lua/tests/test-commands.fnl`, `assets/lua/tests/test-states.fnl`, `assets/lua/tests/test-graph-map-sidebar.fnl`, and `assets/lua/tests/test-graph-activity-slots.fnl`.
- Modify docs: `docs/dev/features/leader-command-system.md` and `docs/dev/graph-maps.md`.
- Do not create a separate `docs/dev/features/graph-leader-commands.md`; keep bindings in the leader command system page and map semantics in the graph maps page.

## Acceptance Criteria

- Existing `SPC g p ...` preview and `SPC g s ...` selection tests still pass unchanged.
- `SPC g` hints expose `preview`, `selection`, `node`, `view`, and `map` when dependencies make descendants available.
- Focused-node commands require focus and invoke GraphView methods, not duplicated command-provider behavior.
- `SPC g n 1` through `SPC g n 9` execute the same runnable action entries that pointer context menus expose at the same indices.
- `SPC g n r` removes only the focused node’s map-local reference and connected map-local topology.
- `SPC g v c` reveals/centers the focused node through GraphView.
- `SPC g v l` starts graph layout through GraphView.
- `SPC g m a` loads `start` into the active map through the same `GraphMap:add-start-node!` path used by sidebar Add Start.
- `SPC g m n` creates and switches to a new empty graph map, without implicitly adding `start`.
- `SPC g m s` creates and switches to a new map containing only selected visible nodes, explicit selected-to-selected edges, restricted selection/focus, and complete islands.
- `SPC g m c` clears the active map’s topology/selection/focus/islands and is unavailable when the map is already clear.
- No command deletes backing domain objects.
- Missing graph view/map/manager dependencies either make commands unavailable in hints or raise explicit assertions when run directly.
- Docs describe bindings and non-destructive map semantics.

## Validation Ladder

Runtime/freshness prerequisite when `./build/space` may be missing or stale:

```bash
make build
```

Use timeout `14400000` ms for `make build`.

Fennel checks must run before constraints and tests. Use touched-file compile checks while iterating, for example:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/map.fnl
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/map-manager.fnl
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/init.fnl
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/commands.fnl
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph-activity-unit.fnl
```

Constraints:

```bash
make constraints
```

Focused Fennel test environment:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map-manager:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-commands:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-states:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map-sidebar:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
```

Complete relevant local suite after all tasks:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

PR CI is the full integration gate.

---

### Task 1: GraphMap Topology Helpers

**Files:**
- Modify: `assets/lua/graph/map.fnl`
- Test: `assets/lua/tests/test-graph-map.fnl`

**Interfaces:**
- Consumes: existing `GraphMap:add-node`, `GraphMap:add-edge`, `GraphMap:remove-nodes`, `GraphMap:capture-state`, `GraphMap:restore-state`, `GraphMap:list-islands`, `GraphMap:load-by-key`.
- Produces:
  - `GraphMap:clear!() -> true`
  - `GraphMap:clearable?() -> boolean`
  - `GraphMap:add-start-node!() -> node`
  - `GraphMap:capture-subgraph-state(node-keys: table, opts?: {:selected-node-keys table, :focused-node-key string|nil}) -> table`
  - `GraphMap:capture-selected-subgraph-state(opts?: {:focused-node-key string|nil}) -> table`

- [ ] **Step 1: Add failing GraphMap clear test**
  - In `assets/lua/tests/test-graph-map.fnl`, add `graph-map-clear-removes-map-local-topology-only`.
  - Arrange a `GraphMap` with loaded nodes `test:a` and `test:b`, one explicit edge `test:a -> test:b`, one island containing both nodes, `selected_node_keys` containing `test:a`, and `focused_node_key` set to `test:a`.
  - Keep a separate shared/domain object or shared graph key-loader record that can be asserted after clear.
  - Call `map:clear!()`.
  - Assert node count, edge count, island count, selected keys, and focused key are empty/nil.
  - Assert the shared/domain object or loader source still exists.
  - Assert `map:clearable?()` returns `false` after clear.

- [ ] **Step 2: Add failing selected-subgraph capture test**
  - Add `graph-map-captures-selected-subgraph-state`.
  - Arrange visible nodes `test:a`, `test:b`, and `test:c`.
  - Add explicit edges `test:a -> test:b` and `test:b -> test:c`; add or mark a derived edge when the test fixture supports it so derived edges are not copied.
  - Add a complete island with members `test:a` and `test:b`, and a partial island with members `test:b` and `test:c`.
  - Set `selected_node_keys` to `test:a` and `test:b`; set focus to `test:b`.
  - Call `map:capture-selected-subgraph-state {:focused-node-key "test:b"}`.
  - Assert the returned state contains only selected node keys, only the explicit selected-to-selected edge, restricted selected/focused keys, and only the complete island.
  - Assert the state has no panels, camera, position metadata, or domain-data fields.

- [ ] **Step 3: Add failing Add Start helper test**
  - Add `graph-map-add-start-node-uses-key-loader`.
  - With a `start` key loader, assert `(map:add-start-node!)` returns a node whose key is `"start"` and the node is visible in the map.
  - Without a `start` key loader, assert `(pcall (fn [] (map:add-start-node!)))` fails with text containing `Add Start failed to load graph key: start`.

- [ ] **Step 4: Implement `clearable?`**
  - Return true when nodes, edges, islands, selected keys, or focused key are present.
  - Return false only when all are empty or nil.

- [ ] **Step 5: Implement `clear!`**
  - Delegate to `self:restore-state` with `{:nodes [] :edges [] :islands [] :selected_node_keys [] :focused_node_key nil}`.
  - Return true.
  - Do not call shared graph delete APIs or domain deletion hooks.

- [ ] **Step 6: Implement `add-start-node!`**
  - Call `(self:load-by-key "start")`.
  - Assert the result with error text containing `Add Start failed to load graph key: start`.
  - Return the node.

- [ ] **Step 7: Implement subgraph capture helpers**
  - Normalize requested keys to currently visible map-local node keys only.
  - Sort copied node keys for deterministic tests.
  - Copy only explicit edges whose source and target keys are both included; skip derived edges tracked by existing derived-edge markers.
  - Copy `selected_node_keys` only for included keys.
  - Copy `focused_node_key` only when included.
  - Copy an island only when every island member is included.
  - Return a `restore-state` compatible table.

- [ ] **Step 8: Run focused validation**
  - Run:

```bash
make build
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/map.fnl --file assets/lua/tests/test-graph-map.fnl
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map:main
```

- [ ] **Step 9: Commit**
  - Run:

```bash
git add assets/lua/graph/map.fnl assets/lua/tests/test-graph-map.fnl
git commit -m "feat(graph): add map-local topology helpers"
```

---

### Task 2: GraphMapManager Create-and-Switch Helper

**Files:**
- Modify: `assets/lua/graph/map-manager.fnl`
- Test: `assets/lua/tests/test-graph-map-manager.fnl`

**Interfaces:**
- Consumes: `GraphMapManager:create-map!`, `GraphMapManager:switch-map!`, `GraphMapManager:get-active-map`, `GraphMap:restore-state`, `GraphMap:capture-state`.
- Produces: `GraphMapManager:create-and-switch-map!(opts?: {:name string|nil, :state table|nil}) -> GraphMap`

- [ ] **Step 1: Add failing empty map creation test**
  - In `assets/lua/tests/test-graph-map-manager.fnl`, add `manager-create-and-switch-empty-map-does-not-seed-start`.
  - Arrange a manager with a shared graph that has a `start` key loader.
  - Call `manager:create-and-switch-map! {:name "Empty"}`.
  - Assert the returned map is active, has name `Empty`, has a generated `map-N` id, has zero nodes, and manager capture includes the new empty map state.

- [ ] **Step 2: Add failing state-backed map creation test**
  - Add `manager-create-and-switch-map-from-state`.
  - Arrange a state table with nodes `test:a` and `test:b`, one explicit edge, one island, selection `test:a`, and focus `test:a`.
  - Call `manager:create-and-switch-map! {:name "Selection" :state state}`.
  - Assert the new active map restores nodes, edge, island, selection, and focus from state.
  - Assert the previous active map still exists in `manager:list-maps`.

- [ ] **Step 3: Implement `create-and-switch-map!`**
  - Generate a safe id using the existing `map-N` scheme and current next id.
  - Default name to generated id when absent.
  - Default state to empty map-local state with empty nodes, edges, islands, selected keys, and nil focus.
  - Insert the entry so the active map hydrates from the provided state and does not implicitly seed `start`.
  - Use existing switch lifecycle to make the new map active.
  - Return `(self:get-active-map)`.

- [ ] **Step 4: Preserve existing manager APIs**
  - Do not change behavior of `create-map!`, `rename-map!`, `delete-map!`, or `switch-map!`.

- [ ] **Step 5: Run focused validation**
  - Run:

```bash
make build
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/map-manager.fnl --file assets/lua/tests/test-graph-map-manager.fnl
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map-manager:main
```

- [ ] **Step 6: Commit**
  - Run:

```bash
git add assets/lua/graph/map-manager.fnl assets/lua/tests/test-graph-map-manager.fnl
git commit -m "feat(graph): create graph maps from command state"
```

---

### Task 3: GraphView Focused-Node Action Boundary

**Files:**
- Modify: `assets/lua/graph/view/init.fnl`
- Test: `assets/lua/tests/test-graph-view.fnl`

**Interfaces:**
- Consumes: existing local node menu actions, `GraphView:focused-node`, `GraphView:reveal-node`, `GraphView:open-node`, `GraphView:start-layout`, `GraphMap:remove-nodes`.
- Produces:
  - `GraphView:node-actions(node: table) -> table`
  - `GraphView:focused-node-actions() -> table`
  - `GraphView:run-focused-node-action-slot(index: number) -> boolean`
  - `GraphView:open-focused-node-menu() -> boolean`
  - `GraphView:toggle-focused-node-preview() -> boolean`
  - `GraphView:copy-focused-node-key() -> boolean`
  - `GraphView:remove-focused-node-from-map() -> boolean`
  - `GraphView:reveal-focused-node() -> boolean`

- [ ] **Step 1: Add failing shared action-list test**
  - In `assets/lua/tests/test-graph-view.fnl`, add `graph-view-focused-action-slots-share-context-menu-actions`.
  - Arrange a focused node whose `actions` include runnable `Custom A` and `Custom B` entries.
  - Capture the pointer context menu action list through the existing menu-opening test hooks.
  - Call `view:focused-node-actions`.
  - Assert the same action names appear in the same order.
  - Call `view:run-focused-node-action-slot` for the index containing `Custom A` and assert its function runs once.

- [ ] **Step 2: Add failing focused-node method tests**
  - Add `graph-view-focused-node-command-methods-require-focus`.
  - With no focus, assert focused-node command methods return false.
  - With focus, assert applicable methods return true.
  - Assert `remove-focused-node-from-map` removes the node from the `GraphMap` without mutating the shared backing object fixture.

- [ ] **Step 3: Add failing view operation test**
  - Add `graph-view-reveal-focused-node-centers-through-reveal-path`.
  - Assert `view:reveal-focused-node` uses the existing reveal/center behavior for the focused node.
  - Assert `view:start-layout` still calls the graph layout start path.

- [ ] **Step 4: Refactor local action construction into a stable boundary**
  - Keep the helper inside `graph/view/init.fnl` because it closes over private GraphView state.
  - Rename the local action builder to `build-node-actions` or an equivalent stable helper.
  - Set `view.node-actions` to call that helper.
  - Update right-click handlers and expanded-card menu callbacks to call `view:node-actions node`.

- [ ] **Step 5: Implement focused-node command methods**
  - `focused-node-actions` returns `[]` without focus and `self:node-actions focused-node` with focus.
  - `run-focused-node-action-slot` validates numeric index, resolves the action, returns false when absent or non-runnable, calls `:fn` when present, returns true, and lets errors propagate.
  - `open-focused-node-menu` opens at focused node presentation center and returns false when focus or menu manager is missing.
  - `toggle-focused-node-preview` uses the same presentation toggle path as pointer activation.
  - `copy-focused-node-key` uses the same clipboard behavior as the existing context menu action.
  - `remove-focused-node-from-map` calls `graph-map:remove-nodes [focused-node]` and returns true only when a node was removed.
  - `reveal-focused-node` calls `self:reveal-node focused-node {:select? true :focus? true :center? true}`.

- [ ] **Step 6: Run focused validation**
  - Run:

```bash
make build
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/init.fnl --file assets/lua/tests/test-graph-view.fnl
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
```

- [ ] **Step 7: Commit**
  - Run:

```bash
git add assets/lua/graph/view/init.fnl assets/lua/tests/test-graph-view.fnl
git commit -m "feat(graph): expose focused node action boundary"
```

---

### Task 4: Graph Leader Command Provider Expansion

**Files:**
- Modify: `assets/lua/graph/commands.fnl`
- Modify: `assets/lua/graph-activity-unit.fnl`
- Modify: `assets/lua/graph/map-sidebar.fnl`
- Test: `assets/lua/tests/test-commands.fnl`
- Test: `assets/lua/tests/test-states.fnl`
- Test: `assets/lua/tests/test-graph-map-sidebar.fnl`
- Test: `assets/lua/tests/test-graph-activity-slots.fnl`

**Interfaces:**
- Consumes: GraphView methods from Task 3, GraphMap methods from Task 1, `GraphMapManager:create-and-switch-map!` from Task 2.
- Produces command ids and bindings:
  - `graph.node.open-focused` -> `SPC g n o`
  - `graph.node.menu-focused` -> `SPC g n m`
  - `graph.node.toggle-focused-preview` -> `SPC g n t`
  - `graph.node.copy-focused-key` -> `SPC g n y`
  - `graph.node.remove-focused-from-map` -> `SPC g n r`
  - `graph.node.action-1` through `graph.node.action-9` -> `SPC g n 1..9`
  - `graph.view.center-focused` -> `SPC g v c`
  - `graph.view.start-layout` -> `SPC g v l`
  - `graph.map.add-start` -> `SPC g m a`
  - `graph.map.new-empty` -> `SPC g m n`
  - `graph.map.from-selection` -> `SPC g m s`
  - `graph.map.clear-active` -> `SPC g m c`

- [ ] **Step 1: Add failing command provider hint test**
  - In `assets/lua/tests/test-commands.fnl`, add `graph-provider-prefix-hints-include-expanded-namespaces`.
  - Compose `GraphCommands.provider` with graph-view, graph-map, and graph-map-manager stubs.
  - Assert `Commands.hint-section` for `SPC g` includes labels `preview`, `selection`, `node`, `view`, and `map`.

- [ ] **Step 2: Add failing node command provider tests**
  - Add `graph-provider-node-commands-route-to-graph-view`.
  - Use stubs that count calls to open/menu/toggle/copy/remove/run-slot methods.
  - Assert each command id calls the corresponding method once.
  - Assert `graph.node.action-3` passes index `3`.

- [ ] **Step 3: Add failing view command provider tests**
  - Add `graph-provider-view-commands-route-to-graph-view`.
  - Assert `graph.view.center-focused` calls `reveal-focused-node`.
  - Assert `graph.view.start-layout` calls `start-layout`.

- [ ] **Step 4: Add failing map command provider tests**
  - Add `graph-provider-map-commands-route-to-active-map-and-manager`.
  - Assert `add-start` calls `active-map:add-start-node!`.
  - Assert `new-empty` calls `manager:create-and-switch-map!` with no state.
  - Assert `from-selection` calls `active-map:capture-selected-subgraph-state` with focused key and passes that state into `manager:create-and-switch-map!`.
  - Assert `clear-active` calls `active-map:clear!`.
  - Assert commands are unavailable when required graph view, map, manager, focus, selection, or clearable state is missing.

- [ ] **Step 5: Add failing leader-state sequence tests**
  - In `assets/lua/tests/test-states.fnl`, add:
    - `leader-state-graph-node-command-routes-to-provider` for `SPC g n o`.
    - `leader-state-graph-view-command-routes-to-provider` for `SPC g v l`.
    - `leader-state-graph-map-command-routes-to-provider` for `SPC g m n`.
  - Assert each command runs and returns to normal state.

- [ ] **Step 6: Add failing graph activity resolver test**
  - In `assets/lua/tests/test-graph-activity-slots.fnl`, extend provider installation coverage so a map command resolves the current runtime `graph-map-manager` and active graph map at run time rather than stale construction time.

- [ ] **Step 7: Update sidebar Add Start to reuse GraphMap helper**
  - Replace local `current-map:load-by-key "start"` logic in `assets/lua/graph/map-sidebar.fnl` with `current-map:add-start-node!`.
  - Keep sidebar rebuild behavior unchanged.
  - Adjust `test-graph-map-sidebar.fnl` so sidebar Add Start still passes.

- [ ] **Step 8: Implement runtime resolvers in `graph/commands.fnl`**
  - Keep `opts.graph-view` as the graph-view resolver.
  - Add optional `opts.graph-map` and `opts.graph-map-manager` resolvers.
  - Availability functions return false when optional resolvers are absent.
  - Run functions assert explicit messages when required dependencies are absent: `GraphCommands requires graph view`, `GraphCommands requires active graph map`, and `GraphCommands requires graph-map-manager`.

- [ ] **Step 9: Implement focused-node commands**
  - Add prefix `{:keys ["g" "n"] :label "node" :priority 30}`.
  - Add command descriptors and bindings for open, menu, toggle, copy, remove, and numeric slots.
  - Numeric slot availability requires a focused node, an action at that index, and a runnable `:fn`.

- [ ] **Step 10: Implement view commands**
  - Add prefix `{:keys ["g" "v"] :label "view" :priority 40}`.
  - Center availability requires focus and `reveal-focused-node`.
  - Layout availability requires graph view and `start-layout`.

- [ ] **Step 11: Implement map commands**
  - Add prefix `{:keys ["g" "m"] :label "map" :priority 50}`.
  - `add-start` calls `active-map:add-start-node!`.
  - `new-empty` calls `manager:create-and-switch-map! {:name nil}`.
  - `from-selection` requires non-empty selection, captures selected subgraph state with focused key, and calls `manager:create-and-switch-map! {:name "Selection" :state state}`.
  - `clear-active` requires `active-map:clearable?` and calls `active-map:clear!`.

- [ ] **Step 12: Update graph activity provider installation**
  - Add a current graph map manager resolver in `graph-activity-unit.fnl`.
  - Install graph provider with `:graph-view`, `:graph-map`, and `:graph-map-manager` resolver functions that return current values at call time.

- [ ] **Step 13: Run focused validation**
  - Run:

```bash
make build
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/commands.fnl --file assets/lua/graph-activity-unit.fnl --file assets/lua/graph/map-sidebar.fnl --file assets/lua/tests/test-commands.fnl --file assets/lua/tests/test-states.fnl --file assets/lua/tests/test-graph-map-sidebar.fnl --file assets/lua/tests/test-graph-activity-slots.fnl
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-commands:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-states:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map-sidebar:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
```

- [ ] **Step 14: Commit**
  - Run:

```bash
git add assets/lua/graph/commands.fnl assets/lua/graph-activity-unit.fnl assets/lua/graph/map-sidebar.fnl assets/lua/tests/test-commands.fnl assets/lua/tests/test-states.fnl assets/lua/tests/test-graph-map-sidebar.fnl assets/lua/tests/test-graph-activity-slots.fnl
git commit -m "feat(graph): expand graph leader commands"
```

---

### Task 5: Documentation and Final Validation

**Files:**
- Modify: `docs/dev/features/leader-command-system.md`
- Modify: `docs/dev/graph-maps.md`

**Interfaces:**
- Consumes: command ids/bindings from Task 4 and map semantics from Tasks 1 and 2.
- Produces: documented graph leader bindings and documented clear/create-from-selection GraphMap semantics.

- [ ] **Step 1: Update leader command docs**
  - In `docs/dev/features/leader-command-system.md`, add tables for `SPC g p`, `SPC g s`, `SPC g n`, `SPC g v`, and `SPC g m`.
  - Document the exact new bindings from Task 4.
  - State that node action slots use the same action list as the focused node context menu.

- [ ] **Step 2: Update graph map docs**
  - In `docs/dev/graph-maps.md`, add a “Leader map commands” subsection.
  - Document that Clear Map is non-destructive and map-local.
  - Document that New Empty Map does not seed `start`; Add Start is explicit.
  - Document that New Map From Selection copies selected visible node keys, selected-to-selected explicit edges, restricted selection/focus, and complete islands only.
  - Document that panels, camera state, high-churn metadata, and backing domain data are not copied.
  - State active map delete/rename remain outside leader-command scope in this phase.

- [ ] **Step 3: Run docs text check**
  - Run:

```bash
rg "SPC g n|SPC g v|SPC g m|New Map From Selection|Clear Map" docs/dev/features/leader-command-system.md docs/dev/graph-maps.md
```

- [ ] **Step 4: Run final Fennel validation ladder**
  - Run:

```bash
make build
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map-manager:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-commands:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-states:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map-sidebar:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
```

- [ ] **Step 5: Run complete relevant local suite**
  - Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

- [ ] **Step 6: Commit**
  - Run:

```bash
git add docs/dev/features/leader-command-system.md docs/dev/graph-maps.md
git commit -m "docs(graph): document graph leader commands"
```

- [ ] **Step 7: Final status check**
  - Run:

```bash
git status --porcelain
```

  - Expected: no output.
