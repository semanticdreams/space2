# Hierarchical Focus Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build generic hierarchical focus entry/exit semantics, one-shot focus leader commands, and graph preview child focus scopes.

**Architecture:** Extend the existing `FocusManager` model with optional node-to-scope entry links and scope-to-node exit links while keeping scopes as the only tree structure. Traversal resolves an active scope and prunes unopened entry scopes so parent traversal sees container nodes, not their interiors. Graph view will create per-node preview scopes and build expanded preview widgets inside those scopes while graph-node commands continue to target only the graph node focus node itself.

**Tech Stack:** Space Fennel, `assets/lua/focus.fnl`, widget `BuildContext`, leader command providers, graph view Fennel modules, project-native Fennel tests.

## Global Constraints

- Add generic focus hierarchy semantics; do not make graph previews a one-off special case.
- Do not introduce a separate "shell node" type. A normal focus node may optionally advertise an entry scope.
- Allow arbitrary nesting: a focus node can be a child of one container's scope while also being the entry point for another scope.
- Preserve the graph invariant that graph-node commands target a graph node only when that graph node's own focus node is focused.
- Provide explicit one-shot leader commands under a focus namespace: `Space f i` / `focus.into`, `Space f o` / `focus.out`, `Space f n` / `focus.next`, `Space f p` / `focus.previous`, `Space f h/j/k/l` / directional focus aliases.
- Keep existing direct shortcuts: `Tab`, `Shift+Tab`, and direct directional focus where already wired remain available.
- Focus entry should prefer the last focused descendant in the entry scope when available; otherwise it should choose the first traversable focus node in that scope.
- Focus exit should return to the nearest owning/exit node for the current focus branch.
- Parent-level traversal should not accidentally enter a child entry scope. A user enters that scope through `focus.into`; once inside, next/previous and directional traversal operate at that interior level until `focus.out` returns to the owner node.
- Do not add a persistent focus mode. `Space f ...` is a one-shot leader namespace.
- Do not overload plain `Enter`; activation remains distinct from entering a focus hierarchy.
- Do not make focus nodes parent other focus nodes directly. Scopes remain the tree structure; entry/exit relationships are explicit links across that tree.
- Do not move graph topology or domain ownership into focus or graph view code.
- Use project Fennel idioms: `local` instead of `let`, factory functions instead of `.new`, multi-branch `if`, and loud errors for inconsistent focus relationships.
- Validation order for Fennel changes: `make fennel-check`, then `make constraints`, then focused Fennel tests.

---

### Task 1: Generic Focus Hierarchy Semantics

**Files:**
- Modify: `assets/lua/focus.fnl`
- Test: `assets/lua/tests/test-focus.fnl`

**Interfaces:**
- Consumes: existing `FocusManager`, `FocusNode`, `FocusScope`, `focus-next`, `focus-direction`, and scope parent/child tree.
- Produces: `FocusNode.entry-scope`, `FocusNode:set-entry-scope(scope-or-nil)`, `FocusScope.exit-node`, `FocusScope.last-focused-descendant`, `FocusScope:set-exit-node(node-or-nil)`, `FocusManager:focus-into(opts)`, `FocusManager:focus-out(opts)`, `FocusManager:can-focus-into?()`, `FocusManager:can-focus-out?()`.

- [ ] **Step 1: Write failing hierarchy tests**

Add tests in `assets/lua/tests/test-focus.fnl` covering these exact cases:

```fennel
(add-test
  "focus into enters first traversable child"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local owner (manager:create-node {:name "owner"}))
    (local sibling (manager:create-node {:name "sibling"}))
    (local inner (manager:create-scope {:name "inner"}))
    (local child-a (manager:create-node {:name "child-a"}))
    (local child-b (manager:create-node {:name "child-b"}))
    (manager:attach owner root)
    (manager:attach inner root)
    (manager:attach sibling root)
    (manager:attach child-a inner)
    (manager:attach child-b inner)
    (owner:set-entry-scope inner)
    (owner:request-focus)
    (assert (= (manager:focus-into {}) child-a))
    (assert (= (manager:get-focused-node) child-a))
    (manager:drop)))
```

Also add tests named:

```fennel
"focus into restores remembered descendant"
"focus out returns nearest exit node through nesting"
"focus traversal skips unopened entry scopes"
"directional focus honors active entry scope"
```

The assertions must prove remembered child restoration, nearest-owner exit ordering, `focus-next` skipping unopened entry scopes, and directional selection staying inside the entered scope.

- [ ] **Step 2: Run the failing tests**

Run:

```bash
make fennel-check
make constraints
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 \
XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 \
SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-focus:main
```

Expected: compile and constraints pass; `tests.test-focus` fails because entry/exit focus APIs do not exist yet.

- [ ] **Step 3: Implement entry/exit relationship methods**

In `assets/lua/focus.fnl`:

- Add `entry-scope nil` to focus nodes.
- Add `exit-node nil` and `last-focused-descendant nil` to focus scopes.
- Add same-manager assertions for node/scope links.
- Implement `node:set-entry-scope(scope-or-nil)` so setting a scope also sets `scope.exit-node` to the node, and clearing it clears that exit node only when it still points back to the node.
- Implement `scope:set-exit-node(node-or-nil)` with the symmetric behavior for `node.entry-scope`.
- Raise explicit errors for cross-manager links.

- [ ] **Step 4: Track remembered descendants**

Update focus marking so when a non-scope node receives focus, every ancestor scope on that focus branch records `last-focused-descendant` as that node. Preserve existing `focused-child` live-branch behavior.

- [ ] **Step 5: Implement pruned active traversal**

Add helper logic in `assets/lua/focus.fnl` so traversal from a scope includes normal focus nodes but does not descend into a child scope with `exit-node` unless that child scope is the active entered scope. Add an active traversal resolver that returns the nearest ancestor scope with `exit-node`, or the root scope when the focused node is not inside an entry scope.

- [ ] **Step 6: Update `focus-next` and `focus-direction`**

Change `focus-next` to collect candidates from the active traversal scope with unopened entry scopes pruned. Change directional focus candidate collection to use the same active traversal level while still respecting existing `directional-traversal-boundary?` behavior inside that level.

- [ ] **Step 7: Implement focus entry/exit APIs**

Add:

```fennel
manager:can-focus-into?()
manager:focus-into {}
manager:can-focus-out?()
manager:focus-out {}
```

`focus-into` should return the focused target or `nil`; it should choose a valid `last-focused-descendant` before the first traversable descendant. `focus-out` should climb ancestor scopes and focus the nearest `exit-node`.

- [ ] **Step 8: Run focused validation**

Run the same command set from Step 2. Expected: `tests.test-focus` passes.

- [ ] **Step 9: Commit Task 1**

```bash
git add assets/lua/focus.fnl assets/lua/tests/test-focus.fnl
git commit -m "feat(ui): add hierarchical focus traversal"
```

Constraint-impact line for handoff: changed; hierarchy traversal now prunes unopened entry scopes.

---

### Task 2: Scoped Focus Build Context Helper

**Files:**
- Modify: `assets/lua/build-context.fnl`
- Test: `assets/lua/tests/test-focus.fnl`

**Interfaces:**
- Consumes: `ctx.focus:get-scope()`, `ctx.focus:set-scope(scope)`.
- Produces: `ctx.focus:with-scope(scope, f) -> callback results`, restoring the previous scope on success and failure.

- [ ] **Step 1: Write failing `with-scope` test**

In `assets/lua/tests/test-focus.fnl`, add test `"build context focus with-scope restores scope"`. The test must create a build context with a focus manager, create an original scope and nested scope, call `ctx.focus:with-scope nested-scope`, create a node inside the callback, and assert the node parent is `nested-scope`. Then assert `ctx.focus:get-scope()` is the original scope after both a successful callback and a callback that raises `(error "boom")` inside `pcall`.

- [ ] **Step 2: Run the failing test**

Run:

```bash
make fennel-check
make constraints
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 \
XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 \
SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-focus:main
```

Expected: `tests.test-focus` fails because `with-scope` is missing.

- [ ] **Step 3: Implement `ctx.focus:with-scope`**

In `assets/lua/build-context.fnl`, add `with-scope` to `focus-ctx`. Validate the target scope using the existing scope validation, save the previous scope, set the new scope, call the callback with `pcall`, restore the previous scope, return callback values on success, and rethrow the callback error on failure.

- [ ] **Step 4: Run focused validation**

Run the same command set from Step 2. Expected: `tests.test-focus` passes.

- [ ] **Step 5: Commit Task 2**

```bash
git add assets/lua/build-context.fnl assets/lua/tests/test-focus.fnl
git commit -m "feat(ui): add scoped focus build helper"
```

Constraint-impact line for handoff: changed; build context focus scope restoration is explicit.

---

### Task 3: One-Shot Focus Leader Commands

**Files:**
- Create: `assets/lua/commands/providers/focus.fnl`
- Modify: `assets/lua/leader-state.fnl`
- Test: `assets/lua/tests/test-commands.fnl`
- Test: `assets/lua/tests/test-leader-state.fnl`

**Interfaces:**
- Consumes: `ctx.focus-manager()`, `ctx.active-input()`, `FocusManager:focus-into`, `FocusManager:focus-out`, `FocusManager:focus-next`, `FocusManager:focus-direction`, `FocusManager:can-focus-into?`, `FocusManager:can-focus-out?`.
- Produces: `commands/providers/focus.fnl` with `provider()`, prefix `[:f]`, and commands `focus.into`, `focus.out`, `focus.next`, `focus.previous`, `focus.left`, `focus.down`, `focus.up`, `focus.right`.

- [ ] **Step 1: Write failing command tests**

In `assets/lua/tests/test-commands.fnl`, add tests proving:

- Root command hints include key `"f"` label `"focus"` when a focus manager exists.
- `Commands.hint-section` for prefix `["f"]` includes `into`, `out`, `next`, `prev`, `left`, `down`, `up`, `right` according to availability.
- `into` is unavailable without `manager:can-focus-into?()`.
- `out` is unavailable without `manager:can-focus-out?()`.
- Directional commands are unavailable when `ctx.active-input()` returns a non-nil object.
- Running `focus.previous` calls `focus-next {:backwards? true}`.
- Running `focus.left` calls `focus-direction {:direction :left ...}`.

- [ ] **Step 2: Write failing one-shot leader test**

In `assets/lua/tests/test-leader-state.fnl`, add test `"Leader state runs Space f n as one-shot focus command"`. Use a focus manager stub recording `focus-next` calls. Enter leader, send key `f`, assert the leader remains pending on a prefix, send key `n`, then assert `focus-next` was called once and leader returned to normal through the existing one-shot command path.

- [ ] **Step 3: Run failing command tests**

Run:

```bash
make fennel-check
make constraints
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 \
XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 \
SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-commands:main
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 \
XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 \
SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-leader-state:main
```

Expected: focused tests fail because the focus provider is missing and leader state does not include it.

- [ ] **Step 4: Implement focus command provider**

Create `assets/lua/commands/providers/focus.fnl`. Follow existing provider style from `commands/providers/core-leader.fnl` and `graph/commands.fnl`. Add concise labels and prefix metadata. Use `ctx.focus-manager()` for the manager, `ctx.active-input()` for the directional guard, and return `true` from a run handler only when the manager operation succeeds.

- [ ] **Step 5: Wire provider into leader state**

In `assets/lua/leader-state.fnl`, require `:commands/providers/focus` and insert `(FocusLeader.provider)` into `active-providers` after core leader commands and before activity-provided commands.

- [ ] **Step 6: Run focused validation**

Run the command set from Step 3. Expected: `tests.test-commands` and `tests.test-leader-state` pass.

- [ ] **Step 7: Commit Task 3**

```bash
git add assets/lua/commands/providers/focus.fnl assets/lua/leader-state.fnl assets/lua/tests/test-commands.fnl assets/lua/tests/test-leader-state.fnl
git commit -m "feat(ui): add focus leader commands"
```

Constraint-impact line for handoff: changed; focus commands add a new leader provider.

---

### Task 4: Graph Preview Entry Scopes

**Files:**
- Modify: `assets/lua/graph/view/init.fnl`
- Test: `assets/lua/tests/test-graph-view.fnl`

**Interfaces:**
- Consumes: `ctx.focus:create-scope`, `ctx.focus:create-node`, `ctx.focus:with-scope`, `FocusNode:set-entry-scope`, `FocusScope:set-exit-node`, graph `node-by-focus` shell mapping.
- Produces: per graph node focus structure with a graph node focus node linked to a node-specific preview entry scope; preview child focus nodes attach to the preview scope and are not mapped in `node-by-focus`.

- [ ] **Step 1: Write failing graph preview tests**

In `assets/lua/tests/test-graph-view.fnl`, add tests named:

```fennel
"GraphView expanded preview children attach to node preview scope"
"GraphView graph node commands require shell focus when preview child focused"
"GraphView collapse clears preview focus descendants"
```

Use a preview builder that calls `preview-ctx.focus:create-node {:name "preview-child"}` and returns a minimal widget with a `Layout`. Assert that after expanding a graph node, the shell focus node has an `entry-scope`, the preview scope's `exit-node` is the shell node, the preview child parent is the preview scope, and the preview child is absent from `view.node-by-focus`. Assert `view:has-focused-node?` is true with shell focus and false after `focus-manager:focus-into {}` focuses the child. Assert collapsing the presentation detaches/drops the child so stale preview focus cannot remain.

- [ ] **Step 2: Run failing graph tests**

Run:

```bash
make fennel-check
make constraints
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 \
XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 \
SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-graph-view:main
```

Expected: focused graph-view tests fail because expanded previews currently use the ambient focus scope.

- [ ] **Step 3: Add per-node focus scopes**

In `assets/lua/graph/view/init.fnl`, add local tables keyed by graph node for any new container/preview scopes. When adding a graph node, create a node-specific preview scope and link it with the shell focus node via `focus-node:set-entry-scope(preview-scope)`. Keep `node-by-focus` populated only for the shell focus node.

- [ ] **Step 4: Build expanded previews inside preview scope**

In `build-expanded-presentation`, resolve the graph node's preview scope and call the card builder inside `ctx.focus:with-scope(preview-scope, fn [] ...)`. Before rebuilding a card for a node, clear stale preview-scope children from any previous expanded presentation.

- [ ] **Step 5: Clean up preview descendants**

Add a graph-view-local cleanup helper that drops children of a preview scope until none remain. Call it on collapse, presentation detach/replacement, node removal, and view drop. The helper must tolerate already-dropped child widgets and leave shell focus nodes intact.

- [ ] **Step 6: Preserve graph command invariant**

Leave `handle-focus-change` based on `node-by-focus`. Do not map preview children into `node-by-focus`. Confirm `focused-node` becomes nil when focus moves into preview children and graph commands become unavailable through existing `view:has-focused-node?` behavior.

- [ ] **Step 7: Run focused validation**

Run the command set from Step 2. Expected: `tests.test-graph-view` passes.

- [ ] **Step 8: Commit Task 4**

```bash
git add assets/lua/graph/view/init.fnl assets/lua/tests/test-graph-view.fnl
git commit -m "feat(ui): scope graph preview focus"
```

Constraint-impact line for handoff: changed; graph preview focus is now hierarchical.

---

### Task 5: Final Validation

**Files:**
- Modify: none.
- Test: focused validation and broader local suite.

**Interfaces:**
- Consumes: completed Tasks 1-4.
- Produces: validation evidence for finishing.

- [ ] **Step 1: Ensure runtime freshness**

If `./build/space` is missing or stale, run:

```bash
make build
```

Use timeout `14400000`.

- [ ] **Step 2: Run compile and constraints**

Run:

```bash
make fennel-check
make constraints
```

Expected: both pass.

- [ ] **Step 3: Run focused tests**

Run:

```bash
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 \
XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 \
SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-focus:main

FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 \
XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 \
SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-commands:main

FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 \
XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 \
SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-leader-state:main

FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
SKIP_KEYRING_TESTS=1 \
XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 \
SPACE_ASSETS_PATH="$(pwd)/assets" \
./build/space -m tests.test-graph-view:main
```

Expected: all focused tests pass.

- [ ] **Step 4: Run broader suite**

Run:

```bash
SKIP_KEYRING_TESTS=1 \
XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 \
SPACE_ASSETS_PATH="$(pwd)/assets" \
make test
```

Expected: pass.

- [ ] **Step 5: Record validation evidence**

In the implementation handoff, list each command, pass/fail result, and any constraint-impact notes from task commits. State that PR CI remains the full integration gate.
