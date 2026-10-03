# Graph Selection Leader Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add graph-focused `SPC g s ...` selection editing commands that can add, remove, toggle, replace, and clear graph selections from the keyboard.

**Architecture:** Keep the behavior graph-native: install a small `GraphView` selection-editing helper that resolves the focused graph node and mutates the existing `ObjectSelector`/`GraphViewSelection` path. Bind those methods from the existing graph command provider under `SPC g s ...`, and document reusable terminal verbs for future systems without introducing a generic selection framework now.

**Tech Stack:** Space Fennel, `GraphView`, `GraphViewSelection`, `ObjectSelector`, graph command providers, `LeaderState`, `tests.runner`.

## Global Constraints

- Graph selection is map-local interaction state.
- Runtime selection is owned by `GraphViewSelection` and the point-oriented `ObjectSelector`, while persisted interaction state lives on `GraphMap.selected_node_keys`.
- Graph core and domain node adapters do not own selection behavior.
- Add Spacemacs-style graph selection editing commands under the documented `SPC g s ...` graph namespace.
- Commands target the currently focused graph node, not hover or pointer position, so keyboard-driven workflows are deterministic.
- Provide these graph bindings:
  - `SPC g s s`: select the focused graph node only.
  - `SPC g s a`: add the focused graph node to the existing selection.
  - `SPC g s r`: remove/deselect the focused graph node from the selection.
  - `SPC g s t`: toggle the focused graph node in the selection.
  - `SPC g s c`: clear graph selection.
- Mutations keep `ObjectSelector.selected`, `GraphViewSelection.selected-nodes`, and `GraphMap.selected_node_keys` coherent.
- Remove/deselect commands must not remove a node from the graph map and must not delete any backing domain object.
- Future systems should reuse the terminal verbs `s`, `a`, `r`, `t`, and `c` under their own command namespace, implemented against their native selection controller.
- Graph doctrine: the graph is an exposure/adaptor layer, not the owner of domain objects.
- Graph doctrine: graph core persists topology only.
- Graph doctrine: `GraphMap` owns interaction context over shared graph-addressable objects.
- Do not add scene/object selection commands.
- Do not add a generic cross-system selection framework.
- Do not add graph map topology removal commands.
- Do not add destructive domain object deletion.
- Do not add search or picker-based bulk selection commands.

---

## File Structure

- Create `assets/lua/graph/view/selection-editing.fnl`: focused helper that installs graph selection-editing methods onto `GraphView`.
- Modify `assets/lua/graph/view/init.fnl`: require and install the helper with closures for the private focused-node state, selected set, points, selector, and `GraphViewSelection`.
- Modify `assets/lua/graph/commands.fnl`: add `SPC g s` prefix, command descriptors, availability checks, and key bindings.
- Modify `assets/lua/tests/test-graph-view.fnl`: add focused GraphView selection-editing tests.
- Modify `assets/lua/tests/test-commands.fnl`: add graph command provider hint, availability, and run tests.
- Modify `assets/lua/tests/test-states.fnl`: add leader routing tests beside the existing `SPC g p e` graph leader tests.
- Modify `docs/dev/features/leader-command-system.md`: document concrete graph selection bindings and the reusable terminal verb convention.

## Acceptance Criteria

- `GraphView` exposes:
  - `view:focused-node() -> node|nil`
  - `view:has-focused-node?() -> boolean`
  - `view:focused-node-selected?() -> boolean`
  - `view:select-focused-node-only() -> boolean`
  - `view:add-focused-node-to-selection() -> boolean`
  - `view:remove-focused-node-from-selection() -> boolean`
  - `view:toggle-focused-node-selection() -> boolean`
  - `view:clear-selection() -> boolean`
- The methods keep `view.selected-nodes`, `view.selection`, `selector.selected`, and `graph-map.selected_node_keys` synchronized.
- `remove-focused-node-from-selection` deselects only; it does not call `graph-map:remove-nodes`, drop nodes, delete domain records, or change graph map membership.
- `SPC g s` appears as a `selection` prefix next to the existing `SPC g p` `preview` prefix.
- Focused-node commands are unavailable without a focused graph node.
- Remove is unavailable when the focused node is not selected.
- Clear is unavailable when the selection is empty.
- Existing `SPC g p ...` preview commands and command IDs remain compatible.

## Validation Ladder

If `./build/space` is missing or stale, run `make build` with timeout `14400000` ms before direct runtime validation.

Run focused Fennel validation in this order:

1. Compile check for touched files:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/selection-editing.fnl --file assets/lua/graph/view/init.fnl --file assets/lua/graph/commands.fnl --file assets/lua/tests/test-graph-view.fnl --file assets/lua/tests/test-commands.fnl --file assets/lua/tests/test-states.fnl
```

2. Constraints:

```bash
make constraints
```

3. Focused tests:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="GraphView selection editing" ./build/space -m tests.test-graph-view:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="Graph provider selection" ./build/space -m tests.test-commands:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="Leader state graph selection" ./build/space -m tests.test-states:main
```

Run the complete relevant local suites after all tasks:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-commands:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-states:main
```

Broader `make test` is not required for this narrow graph-command surface unless focused failures, reviewer findings, or implementation scope show wider risk. PR CI remains the full integration gate.

If Fennel delimiter or parse errors appear, inspect the nearest enclosing form around the reported line and simplify nested logic into helpers before retrying. Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.

---

### Task 1: GraphView Selection Editing API

**Files:**
- Create: `assets/lua/graph/view/selection-editing.fnl`
- Modify: `assets/lua/graph/view/init.fnl`
- Test: `assets/lua/tests/test-graph-view.fnl`

**Interfaces:**
- Consumes:
  - `selection:set-selection(nodes: table) -> nil`
  - `selector:set-selected(items: table, emit-changed?: boolean|nil) -> nil`
  - `selected-nodes: table`
  - `points: table` mapping graph node tables to point handles
  - `focused-node: fn() -> table|nil`
  - `selected-node?: fn(node: table) -> boolean`
  - `assert-not-dropped: fn(context: string) -> nil|error`
- Produces:
  - `SelectionEditing.install!(view: table, opts: table) -> table`
  - `view:focused-node() -> table|nil`
  - `view:has-focused-node?() -> boolean`
  - `view:focused-node-selected?() -> boolean`
  - `view:select-focused-node-only() -> boolean`
  - `view:add-focused-node-to-selection() -> boolean`
  - `view:remove-focused-node-from-selection() -> boolean`
  - `view:toggle-focused-node-selection() -> boolean`
  - `view:clear-selection() -> boolean`

- [ ] **Step 1: Add failing select-only GraphView test**
  - In `assets/lua/tests/test-graph-view.fnl`, follow the existing GraphView test helpers and add a test named `GraphView selection editing select focused node only syncs state`.
  - Arrange a graph map with at least nodes `a` and `b`, create a `GraphView`, preselect node `b` through the existing selector/selection path, focus node `a` via its focus node, call `view:select-focused-node-only()`, and assert:
    - the method returns `true`;
    - `view.selected-nodes` contains exactly node `a`;
    - `view.selection:resolve-selection()` resolves exactly node `a`;
    - `selector.selected` contains exactly `(. view.points a)`;
    - `graph-map.selected_node_keys` contains exactly `"a"`.
  - Register the test in the file's `tests` table.

- [ ] **Step 2: Add failing add/remove/toggle/clear GraphView test**
  - Add a test named `GraphView selection editing add remove toggle and clear sync state`.
  - Arrange nodes `a`, `b`, and `c`; select `a`; focus `b`.
  - Call `view:add-focused-node-to-selection()` and assert selected nodes, selector points, and selected keys contain `a` and `b` exactly once each.
  - Call `view:add-focused-node-to-selection()` again and assert selection still has exactly two entries.
  - Call `view:remove-focused-node-from-selection()` and assert only `a` remains selected.
  - Assert `graph-map:lookup "b"` still returns node `b` and the graph map still includes node `b`.
  - Call `view:toggle-focused-node-selection()` and assert `a` and `b` are selected.
  - Call `view:toggle-focused-node-selection()` again and assert only `a` is selected.
  - Call `view:clear-selection()` and assert selected nodes, selector points, and selected keys are empty.
  - Register the test in the file's `tests` table.

- [ ] **Step 3: Run the new focused GraphView tests and verify they fail**
  - Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="GraphView selection editing" ./build/space -m tests.test-graph-view:main
```

  - Expected: FAIL because `select-focused-node-only` and related methods are not implemented.

- [ ] **Step 4: Implement `assets/lua/graph/view/selection-editing.fnl`**
  - Export `{:install! install!}`.
  - In `install!`, assert required inputs: `view`, `opts.assert-not-dropped`, `opts.focused-node`, `opts.selected-node?`, `opts.selected-nodes`, `opts.points`, and `opts.selection`.
  - Add local helpers:
    - `copy-nodes(nodes)` copies an array without mutating the source.
    - `contains-node?(nodes node)` checks identity membership.
    - `remove-node(nodes node)` returns a copied array without `node`.
    - `points-for(nodes)` maps every node to `(. points node)` and raises an explicit error when a selected node has no current point.
    - `apply-selection!(nodes)` calls `assert-not-dropped "selection-editing"`, updates `selector:set-selected` when a selector exists, calls `selection:set-selection`, and returns `true`.
  - Install methods on `view`:
    - `focused-node` returns `(opts.focused-node)`.
    - `has-focused-node?` returns true when `focused-node` returns non-nil.
    - `focused-node-selected?` returns true when a focused node exists and `opts.selected-node?` returns true for it.
    - `select-focused-node-only` applies `[focused-node]` and returns false when no focused node exists.
    - `add-focused-node-to-selection` applies the current selection plus the focused node if absent, and returns false when no focused node exists.
    - `remove-focused-node-from-selection` applies the current selection without the focused node, and returns false when no focused node exists.
    - `toggle-focused-node-selection` removes the focused node if selected and adds it otherwise, and returns false when no focused node exists.
    - `clear-selection` applies `[]` and returns true when the current selection was non-empty, false when already empty.
  - Do not call graph map node removal or domain deletion APIs.

- [ ] **Step 5: Install the helper from `GraphView`**
  - In `assets/lua/graph/view/init.fnl`, require `:graph/view/selection-editing` near the existing selected-preview command helper.
  - After the `view` table is constructed and before returning it, call:

```fennel
(GraphViewSelectionEditing.install!
  view
  {:assert-not-dropped assert-not-dropped
   :focused-node (fn [] focused-node)
   :selected-node? (fn [node] (and node (rawget selected-set node)))
   :selected-nodes selected-nodes
   :points registry.points
   :selector selector
   :selection selection})
```

  - Keep `(SelectedPreviewCommands.install! ...)` unchanged for existing `SPC g p ...` behavior.

- [ ] **Step 6: Run Task 1 compile check**
  - Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/selection-editing.fnl --file assets/lua/graph/view/init.fnl --file assets/lua/tests/test-graph-view.fnl
```

  - Expected: PASS.

- [ ] **Step 7: Run Task 1 focused tests**
  - Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="GraphView selection editing" ./build/space -m tests.test-graph-view:main
```

  - Expected: PASS.

- [ ] **Step 8: Commit Task 1**
  - Run:

```bash
git add assets/lua/graph/view/selection-editing.fnl assets/lua/graph/view/init.fnl assets/lua/tests/test-graph-view.fnl
git commit -m "feat(graph): add focused node selection editing"
```

---

### Task 2: Graph Selection Leader Commands

**Files:**
- Modify: `assets/lua/graph/commands.fnl`
- Test: `assets/lua/tests/test-commands.fnl`
- Test: `assets/lua/tests/test-states.fnl`

**Interfaces:**
- Consumes:
  - `graph-view:selected-node-count() -> integer`
  - `graph-view:has-focused-node?() -> boolean`
  - `graph-view:focused-node-selected?() -> boolean`
  - `graph-view:select-focused-node-only() -> boolean`
  - `graph-view:add-focused-node-to-selection() -> boolean`
  - `graph-view:remove-focused-node-from-selection() -> boolean`
  - `graph-view:toggle-focused-node-selection() -> boolean`
  - `graph-view:clear-selection() -> boolean`
- Produces:
  - `graph.selection.select-focused` bound to `SPC g s s` with label `select`.
  - `graph.selection.add-focused` bound to `SPC g s a` with label `add`.
  - `graph.selection.remove-focused` bound to `SPC g s r` with label `remove`.
  - `graph.selection.toggle-focused` bound to `SPC g s t` with label `toggle`.
  - `graph.selection.clear` bound to `SPC g s c` with label `clear`.

- [ ] **Step 1: Add failing graph command provider tests**
  - In `assets/lua/tests/test-commands.fnl`, add tests with names starting `Graph provider selection`.
  - Add a graph-view stub with fields/methods:
    - `selected-count` value used by `selected-node-count`;
    - `focused?` value used by `has-focused-node?`;
    - `focused-selected?` value used by `focused-node-selected?`;
    - counters for `select-focused-node-only`, `add-focused-node-to-selection`, `remove-focused-node-from-selection`, `toggle-focused-node-selection`, and `clear-selection`.
  - Add `Graph provider selection prefix hints include selection commands`:
    - Build `GraphCommands.provider {:graph-view resolver}`.
    - Assert root graph hints still include `p` labeled `preview`.
    - Assert root graph hints include `s` labeled `selection`.
    - Assert hints for `g s` include keys `s`, `a`, `r`, `t`, `c` with labels `select`, `add`, `remove`, `toggle`, `clear`.
  - Add `Graph provider selection availability follows focus and selection`:
    - With no focused node, assert select/add/remove/toggle commands are unavailable.
    - With focused node, empty selection, and focused node not selected, assert select/add/toggle are available, remove is unavailable, and clear is unavailable.
    - With focused node, non-empty selection, and focused node selected, assert all five commands are available.
  - Add `Graph provider selection commands run view methods`:
    - Run each command through the command provider/core helper used by existing tests.
    - Assert the matching counter increments once and unrelated counters remain unchanged.

- [ ] **Step 2: Add failing leader-state routing tests**
  - In `assets/lua/tests/test-states.fnl`, add tests near the existing `leader-state-graph-preview-*` tests, with names starting `Leader state graph selection`.
  - Add key constants for `KEY_A`, `KEY_R`, `KEY_S`, and `KEY_T` if the file does not already define them.
  - Add `Leader state graph selection command routes to provider`:
    - Use `GraphCommands.provider {:graph-view (fn [] graph-view)}` with a graph-view stub where `has-focused-node?` returns true and `add-focused-node-to-selection` increments a counter.
    - Drive leader keys `g`, `s`, `a`.
    - Assert the add counter is `1` and the last transition is `:normal`.
  - Add `Leader state graph selection unavailable command does not mutate`:
    - Use a graph-view stub where `has-focused-node?` returns true, `focused-node-selected?` returns false, and `remove-focused-node-from-selection` increments a counter.
    - Drive leader keys `g`, `s`, `r`.
    - Assert the remove counter remains `0` and the last transition is `:normal`.
  - Register both tests in the `tests` table.

- [ ] **Step 3: Run new command and leader tests and verify they fail**
  - Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="Graph provider selection" ./build/space -m tests.test-commands:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="Leader state graph selection" ./build/space -m tests.test-states:main
```

  - Expected: FAIL because `SPC g s ...` commands and bindings are not implemented.

- [ ] **Step 4: Implement graph command provider selection commands**
  - In `assets/lua/graph/commands.fnl`, keep existing preview commands, command IDs, and bindings unchanged.
  - Add helper functions:
    - `has-focused-node? [opts]` resolves the graph view and calls `view:has-focused-node?()` when available.
    - `focused-node-selected? [opts]` resolves the graph view and calls `view:focused-node-selected?()` when available.
    - `selection-non-empty? [opts]` reuses selected count to check for a non-empty graph selection.
    - `run-selection [opts method-name availability-fn]` returns false when unavailable, otherwise calls the view method and returns true so available idempotent commands are handled.
  - Add command descriptors:
    - `graph.selection.select-focused`, available when `has-focused-node?`.
    - `graph.selection.add-focused`, available when `has-focused-node?`.
    - `graph.selection.remove-focused`, available when `focused-node-selected?`.
    - `graph.selection.toggle-focused`, available when `has-focused-node?`.
    - `graph.selection.clear`, available when `selection-non-empty?`.
  - Add prefix `{:keys ["g" "s"] :label "selection" :priority 20}`.
  - Add bindings with priorities select `10`, add `20`, remove `30`, toggle `40`, clear `50`.

- [ ] **Step 5: Run Task 2 compile check**
  - Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/commands.fnl --file assets/lua/tests/test-commands.fnl --file assets/lua/tests/test-states.fnl
```

  - Expected: PASS.

- [ ] **Step 6: Run Task 2 focused tests**
  - Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="Graph provider selection" ./build/space -m tests.test-commands:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="Leader state graph selection" ./build/space -m tests.test-states:main
```

  - Expected: PASS.

- [ ] **Step 7: Commit Task 2**
  - Run:

```bash
git add assets/lua/graph/commands.fnl assets/lua/tests/test-commands.fnl assets/lua/tests/test-states.fnl
git commit -m "feat(graph): bind selection leader commands"
```

---

### Task 3: Documentation and Final Validation

**Files:**
- Modify: `docs/dev/features/leader-command-system.md`

**Interfaces:**
- Consumes: command IDs and bindings from Task 2.
- Produces: documented `SPC g s ...` graph bindings and documented terminal verb convention for future native selection controllers.

- [ ] **Step 1: Update leader command docs**
  - In `docs/dev/features/leader-command-system.md`, under graph namespace conventions, add a graph selection binding table:
    - `SPC g s s` — select focused graph node only.
    - `SPC g s a` — add focused graph node to selection.
    - `SPC g s r` — remove/deselect focused graph node from selection.
    - `SPC g s t` — toggle focused graph node in selection.
    - `SPC g s c` — clear graph selection.
  - Add a short note that future systems should reuse terminal verbs `s`, `a`, `r`, `t`, and `c` under their own namespace, backed by their native selection controller, and that this is not a generic selection framework.

- [ ] **Step 2: Validate docs text search**
  - Run:

```bash
rg "SPC g s|select focused|terminal verbs|generic selection framework" docs/dev/features/leader-command-system.md
```

  - Expected: matches for the graph selection namespace, focused selection behavior, terminal verbs, and non-framework guidance.

- [ ] **Step 3: Run final compile check**
  - Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/selection-editing.fnl --file assets/lua/graph/view/init.fnl --file assets/lua/graph/commands.fnl --file assets/lua/tests/test-graph-view.fnl --file assets/lua/tests/test-commands.fnl --file assets/lua/tests/test-states.fnl
```

  - Expected: PASS.

- [ ] **Step 4: Run constraints**
  - Run:

```bash
make constraints
```

  - Expected: PASS.
  - Report constraint impact as `not applicable` unless a constraint directly catches or drives a change.

- [ ] **Step 5: Run focused tests**
  - Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="GraphView selection editing" ./build/space -m tests.test-graph-view:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="Graph provider selection" ./build/space -m tests.test-commands:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="Leader state graph selection" ./build/space -m tests.test-states:main
```

  - Expected: PASS.

- [ ] **Step 6: Run complete relevant local suites**
  - Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-commands:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-states:main
```

  - Expected: PASS.

- [ ] **Step 7: Commit Task 3**
  - Run:

```bash
git add docs/dev/features/leader-command-system.md
git commit -m "docs(graph): document selection leader commands"
```

- [ ] **Step 8: Final status check**
  - Run:

```bash
git status --porcelain
```

  - Expected: no output.
