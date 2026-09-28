# Hosted App Launcher Graph Node Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a graph-visible hosted app launcher node, reachable from `start`, that hosts the currently selected filesystem app source through the existing workspace panel.

**Architecture:** Implement a UX-purpose `hosted-app-launcher:workspace` graph node rather than a registry, catalog, search surface, or fs-node action. The node observes active `GraphMap` selection, resolves exactly one selected `fs:` source through deterministic file/directory conventions, and calls the existing hosted workspace panel on explicit button click.

**Tech Stack:** Space Fennel, GraphMap/GraphView, built-in graph extension descriptors, Space widgets/views, `app-host.workspace-panel`, project-native Fennel validation and focused Lua/Fennel tests.

## Global Constraints

- No hosted app registry, catalog, index, marketplace, or search.
- No app discovery scan across projects, directories, packages, networks, or remote machines.
- No hosted-app-specific actions on `fs:` nodes.
- No new hosted app manifest format in this slice.
- No launchables integration and no scanning `assets/lua/launchables/*.fnl`.
- No remote/non-filesystem source adapter yet.
- No persistence of launched app history or app source metadata.
- No sandboxing, permissions, approvals, process isolation, or auth policy.
- Graph topology persistence remains limited to graph keys, explicit map edges, and map-local interaction state.
- The launcher must be reachable from the `start` node.
- The launcher enables only for exactly one selected `fs:` source that resolves by first-slice `.fnl` file or directory rules.
- Invalid selections, directory ambiguity, module load failures, missing `create(host)`, and workspace-panel open failures must produce explicit launcher status rather than silent no-ops.
- Widget constructors return build closures; builders receive renderer/build context and instantiate children with that context.
- Composite widgets own and drop their direct child widgets; missing required context must assert loudly.
- Use project Fennel idioms: `local` instead of `let`, multi-branch `if`, and factory functions instead of `.new` constructors.
- Validation order for Fennel-facing work is compile check, constraints, focused tests, then broader relevant tests when risk requires it.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.

---

## File Structure

- `assets/lua/graph/map.fnl`: owns map-local selected-key state, emits selection changes, and prunes selection when visible nodes are removed.
- `assets/lua/graph/view/init.fnl`: synchronizes runtime selection changes into `GraphMap` through the new setter.
- `assets/lua/app-host/source-resolver.fnl`: pure resolver for selected `fs:` graph keys and paths; it detects launch candidates without loading modules.
- `assets/lua/app-host/hosted-source-launcher.fnl`: wraps a resolved source as a hosted module and opens it through `app-host.workspace-panel`.
- `assets/lua/graph/nodes/hosted-app-launcher.fnl`: graph node adapter and runtime status owner for `hosted-app-launcher:workspace`.
- `assets/lua/graph/view/views/hosted-app-launcher.fnl`: small launcher view with status text and `Host selected app` button.
- `assets/lua/graph/extensions/builtins/hosted-apps.fnl`: built-in graph extension descriptor/key loader for the launcher node.
- `assets/lua/graph/extensions/builtins/init.fnl`: includes the hosted-apps built-in family.
- `assets/lua/graph/nodes/start.fnl`: includes `Hosted App Launcher` as a start-node target.
- `assets/lua/tests/test-app-host-source-resolver.fnl`: focused resolver tests.
- `assets/lua/tests/test-app-host-hosted-source-launcher.fnl`: focused module-wrapper/workspace-panel launch tests.
- `assets/lua/tests/test-graph-hosted-app-launcher.fnl`: graph node, extension, start-node, and view behavior tests.
- `assets/lua/tests/test-graph-map.fnl`: extends existing graph-map selection tests.
- `assets/lua/tests/fast.fnl`: registers new focused test modules.
- `docs/dev/features/hosted-runtime-apps.md`: documents the graph launcher contract and exclusions.

---

### Task 1: GraphMap Live Selection Contract

**Files:**
- Modify: `assets/lua/graph/map.fnl`
- Modify: `assets/lua/graph/view/init.fnl`
- Modify: `assets/lua/tests/test-graph-map.fnl`

**Interfaces:**
- Consumes: existing `GraphMap.selected_node_keys`, `GraphMap.nodes`, and `GraphView` `selected-nodes` runtime list.
- Produces: `graph-map.selection-changed` signal emitting `{:selected-node-keys keys}` and `graph-map:set-selected-node-keys(keys) -> stored-keys`.

- [ ] **Step 1: Add failing selection setter tests**

  Add tests to `assets/lua/tests/test-graph-map.fnl` proving:
  - `set-selected-node-keys` accepts a table of keys, stores a fresh sequential table, and returns the stored table.
  - non-string entries and keys not visible in `graph-map.nodes` are ignored.
  - `selection-changed` emits once with `{:selected-node-keys [...]}` when the selection changes.
  - calling the setter with the same selected keys does not emit a duplicate signal.

- [ ] **Step 2: Add failing prune-on-remove test**

  Add a test proving that when `remove-nodes` removes a selected node, `selected_node_keys` is pruned and `selection-changed` emits the pruned key list.

- [ ] **Step 3: Run focused failing tests**

  Run:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map:main
  ```
  Expected: the new tests fail because the setter/signal does not exist yet.

- [ ] **Step 4: Implement the GraphMap setter and signal**

  In `assets/lua/graph/map.fnl`:
  - add `selection-changed` next to existing graph-map signals;
  - add `set-selected-node-keys` that validates table input, copies only visible string keys, compares with current `selected_node_keys`, stores the copied table, emits `selection-changed` only on change, and returns the stored table;
  - update remove/prune paths so selection changes caused by node removal use the same emission behavior.

- [ ] **Step 5: Sync GraphView selection through the setter**

  In `assets/lua/graph/view/init.fnl`, replace direct writes to `graph-map.selected_node_keys` during runtime selection/capture with `graph-map:set-selected-node-keys(keys)` when available. Keep capture-state output shape unchanged: `:selected_node_keys keys`.

- [ ] **Step 6: Run validation for Task 1**

  Run:
  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/map.fnl --file assets/lua/graph/view/init.fnl --file assets/lua/tests/test-graph-map.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map:main
  ```

- [ ] **Step 7: Commit Task 1**

  Commit message:
  ```bash
  git add assets/lua/graph/map.fnl assets/lua/graph/view/init.fnl assets/lua/tests/test-graph-map.fnl
  git commit -m "feat(graph): expose live map selection changes"
  ```

---

### Task 2: Hosted App Source Resolver

**Files:**
- Create: `assets/lua/app-host/source-resolver.fnl`
- Create: `assets/lua/tests/test-app-host-source-resolver.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: selected graph keys, optional visible graph nodes with `:path`, and filesystem `fs.stat`/path helpers.
- Produces: `SourceResolver.resolve-selection(graph-map, selected-keys) -> result` where success is `{:ok? true :source-kind :file|:directory :selection-key string :path string :entry-path string :lua-root string :module-name string :label string}` and failure is `{:ok? false :reason keyword :message string}`.

- [ ] **Step 1: Add failing resolver tests for invalid selections**

  In `test-app-host-source-resolver.fnl`, add tests for:
  - no selection returns `:reason :no-selection`;
  - multiple selections returns `:reason :multiple-selection`;
  - non-`fs:` selected key returns `:reason :unsupported-selection`;
  - missing filesystem path returns `:reason :missing-path`;
  - unsupported file extension returns `:reason :unsupported-file`.

- [ ] **Step 2: Add failing resolver tests for file sources**

  Add tests using temporary directories under `/tmp/space/tests/hosted-app-source-resolver` proving:
  - selecting `fs:<root>/assets/lua/main.fnl` resolves `:lua-root <root>/assets/lua` and `:module-name "main"`;
  - selecting `fs:<root>/assets/lua/snake/app.fnl` resolves `:module-name "snake/app"`;
  - selecting a standalone `.fnl` file outside `assets/lua` resolves with the file parent as `:lua-root` and basename without extension as `:module-name`.

- [ ] **Step 3: Add failing resolver tests for directory sources**

  Add tests proving:
  - a directory with exactly one `assets/lua/main.fnl`, `main.fnl`, or `init.fnl` resolves successfully;
  - a directory with none of those entries returns `:reason :no-directory-entry`;
  - a directory with more than one recognized entry returns `:reason :ambiguous-directory` and does not choose one silently.

- [ ] **Step 4: Run focused failing resolver tests**

  Run:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-source-resolver:main
  ```
  Expected: module not found or resolver function missing.

- [ ] **Step 5: Implement `source-resolver.fnl`**

  Implement helpers that:
  - accept exactly one selected key;
  - resolve `fs:` paths from the visible node's `path` when available, otherwise by stripping `fs:`;
  - inspect only the selected file or the three directory entry conventions;
  - return explicit failure records for ordinary invalid input;
  - never load or execute selected app code.

- [ ] **Step 6: Register the new test module in `fast.fnl`**

  Add `:tests.test-app-host-source-resolver` to the fast test module list in the same style as adjacent app-host tests.

- [ ] **Step 7: Run validation for Task 2**

  Run:
  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/source-resolver.fnl --file assets/lua/tests/test-app-host-source-resolver.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-source-resolver:main
  ```

- [ ] **Step 8: Commit Task 2**

  Commit message:
  ```bash
  git add assets/lua/app-host/source-resolver.fnl assets/lua/tests/test-app-host-source-resolver.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(app-host): resolve hosted app sources"
  ```

---

### Task 3: Hosted Source Launcher Helper

**Files:**
- Create: `assets/lua/app-host/hosted-source-launcher.fnl`
- Create: `assets/lua/tests/test-app-host-hosted-source-launcher.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: Task 2 source records and `app-host.workspace-panel.open(opts)`.
- Produces: `HostedSourceLauncher.make-module(source) -> module-wrapper` and `HostedSourceLauncher.open-source(source, opts) -> session`.

- [ ] **Step 1: Add failing module-wrapper tests**

  Add tests proving `make-module(source):create(host)`:
  - temporarily prepends `source.lua-root` to Fennel module resolution;
  - loads `source.module-name`;
  - validates `module.create` exists and is a function;
  - calls `module.create(host)` and returns its result;
  - restores Fennel path and app suppression state after success and after error.

- [ ] **Step 2: Add failing workspace open tests**

  Add tests proving `open-source(source, opts)` calls a supplied `workspace-panel.open` fake with:
  - `:app` from `opts.app`;
  - `:runtime` from `opts.runtime`;
  - `:module` set to the wrapper returned by `make-module`;
  - a useful label/title derived from `source.label`.

- [ ] **Step 3: Run focused failing launcher-helper tests**

  Run:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-hosted-source-launcher:main
  ```
  Expected: module not found or helper function missing.

- [ ] **Step 4: Implement `hosted-source-launcher.fnl`**

  Implement:
  - `make-module(source)` with explicit assertions for required source fields;
  - state restoration around `fennel.path`, `_G.require` if needed by project loader behavior, and `app.__suppress-main-run?`;
  - `open-source(source, opts)` with explicit `app` and `runtime` resolution from opts first, then global `app` / `app.active-world-runtime`;
  - loud errors for missing runtime/app/workspace-panel open rather than silent fallback.

- [ ] **Step 5: Register the new test module in `fast.fnl`**

  Add `:tests.test-app-host-hosted-source-launcher` next to the source resolver test.

- [ ] **Step 6: Run validation for Task 3**

  Run:
  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/hosted-source-launcher.fnl --file assets/lua/tests/test-app-host-hosted-source-launcher.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-hosted-source-launcher:main
  ```

- [ ] **Step 7: Commit Task 3**

  Commit message:
  ```bash
  git add assets/lua/app-host/hosted-source-launcher.fnl assets/lua/tests/test-app-host-hosted-source-launcher.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(app-host): open hosted app sources"
  ```

---

### Task 4: Launcher Graph Node, Extension, and Start Target

**Files:**
- Create: `assets/lua/graph/nodes/hosted-app-launcher.fnl`
- Create: `assets/lua/graph/extensions/builtins/hosted-apps.fnl`
- Modify: `assets/lua/graph/extensions/builtins/init.fnl`
- Modify: `assets/lua/graph/nodes/start.fnl`
- Create: `assets/lua/tests/test-graph-hosted-app-launcher.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `SourceResolver.resolve-selection(graph-map, selected-keys)`, `HostedSourceLauncher.open-source(source, opts)`, and `graph-map.selection-changed`.
- Produces: graph key `hosted-app-launcher:workspace`, node methods `refresh-selection() -> status`, `current-status() -> status`, and `open-selected(opts) -> session|nil`.

- [ ] **Step 1: Add failing extension/start-node tests**

  In `test-graph-hosted-app-launcher.fnl`, add tests proving:
  - the built-in descriptor list includes a descriptor for scheme `hosted-app-launcher`;
  - loading key `hosted-app-launcher:workspace` returns a node labeled `Hosted App Launcher`;
  - `StartNode():collect-targets()` includes a target labeled `Hosted App Launcher`.

- [ ] **Step 2: Add failing node status tests**

  Add tests with fake graph maps proving `refresh-selection` returns/stores explicit statuses for no selection, multiple selection, non-`fs:` selection, unresolved filesystem source, and resolvable source.

- [ ] **Step 3: Add failing launch tests**

  Add tests proving `open-selected`:
  - resolves current selection;
  - calls injected launcher helper on valid source;
  - updates status to launched on success;
  - captures launch failure as `:status :error` with explicit message.

- [ ] **Step 4: Run focused failing graph launcher tests**

  Run:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-hosted-app-launcher:main
  ```
  Expected: module not found or launcher key not registered.

- [ ] **Step 5: Implement launcher node adapter**

  In `graph/nodes/hosted-app-launcher.fnl`:
  - construct a `GraphNode` with key `hosted-app-launcher:workspace`, label `Hosted App Launcher`, and a kind badge suitable for hosted apps;
  - store status as a small table such as `{:status :disabled|:ready|:launched|:error :message string :source source}`;
  - subscribe to `graph-map.selection-changed` when mounted and disconnect on drop;
  - implement `refresh-selection`, `current-status`, and `open-selected`;
  - emit a `status-changed` signal when status changes.

- [ ] **Step 6: Implement built-in graph extension**

  In `graph/extensions/builtins/hosted-apps.fnl`:
  - use `graph/extensions/builtins/common.fnl` descriptor helpers;
  - register an exact key loader for `hosted-app-launcher:workspace`;
  - declare scheme `hosted-app-launcher`;
  - include the family in `graph/extensions/builtins/init.fnl`.

- [ ] **Step 7: Add the start-node target**

  In `graph/nodes/start.fnl`, add a `HostedAppLauncherNode` target to `collect-targets` so users can materialize the launcher from `start`.

- [ ] **Step 8: Register the graph launcher test in `fast.fnl`**

  Add `:tests.test-graph-hosted-app-launcher` near other graph tests.

- [ ] **Step 9: Run validation for Task 4**

  Run:
  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/nodes/hosted-app-launcher.fnl --file assets/lua/graph/extensions/builtins/hosted-apps.fnl --file assets/lua/graph/extensions/builtins/init.fnl --file assets/lua/graph/nodes/start.fnl --file assets/lua/tests/test-graph-hosted-app-launcher.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-hosted-app-launcher:main
  ```

- [ ] **Step 10: Commit Task 4**

  Commit message:
  ```bash
  git add assets/lua/graph/nodes/hosted-app-launcher.fnl assets/lua/graph/extensions/builtins/hosted-apps.fnl assets/lua/graph/extensions/builtins/init.fnl assets/lua/graph/nodes/start.fnl assets/lua/tests/test-graph-hosted-app-launcher.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(graph): add hosted app launcher node"
  ```

---

### Task 5: Launcher View and Button UI

**Files:**
- Create: `assets/lua/graph/view/views/hosted-app-launcher.fnl`
- Modify: `assets/lua/graph/nodes/hosted-app-launcher.fnl`
- Modify: `assets/lua/tests/test-graph-hosted-app-launcher.fnl`

**Interfaces:**
- Consumes: Task 4 node methods and `status-changed` signal.
- Produces: launcher view rendering status text and a `Host selected app` button using icon `rocket_launch`.

- [ ] **Step 1: Add failing view tests**

  Extend `test-graph-hosted-app-launcher.fnl` to prove:
  - the launcher node exposes the hosted launcher view constructor;
  - the built view reads `node:current-status()` and renders disabled status text for invalid selection;
  - the launch button is disabled unless status is `:ready`;
  - clicking the enabled button calls `node:open-selected()` and refreshes visible status.

- [ ] **Step 2: Run focused failing view tests**

  Run:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-hosted-app-launcher:main
  ```
  Expected: view module or rendered controls missing.

- [ ] **Step 3: Implement the launcher view**

  In `graph/view/views/hosted-app-launcher.fnl`:
  - follow existing graph view widget patterns;
  - require renderer/build context explicitly;
  - render title, source/status text, latest launch message, and the `Host selected app` button;
  - use icon `rocket_launch`, which is available in `assets/material-design-icons/icons.txt`;
  - own/drop direct child widgets and signal subscriptions;
  - refresh the shallowest appropriate layout when status changes.

- [ ] **Step 4: Wire node to the view**

  Set the launcher node `:view` to `HostedAppLauncherView` and ensure `refresh-selection` is called during view build or attachment so the first render reflects current graph selection.

- [ ] **Step 5: Run validation for Task 5**

  Run:
  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/views/hosted-app-launcher.fnl --file assets/lua/graph/nodes/hosted-app-launcher.fnl --file assets/lua/tests/test-graph-hosted-app-launcher.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-hosted-app-launcher:main
  ```

- [ ] **Step 6: Commit Task 5**

  Commit message:
  ```bash
  git add assets/lua/graph/view/views/hosted-app-launcher.fnl assets/lua/graph/nodes/hosted-app-launcher.fnl assets/lua/tests/test-graph-hosted-app-launcher.fnl
  git commit -m "feat(ui): show hosted app launcher controls"
  ```

---

### Task 6: Documentation and Final Local Validation

**Files:**
- Modify: `docs/dev/features/hosted-runtime-apps.md`

**Interfaces:**
- Consumes: implemented launcher behavior and resolver contract.
- Produces: canonical docs for the hosted app graph launcher and its exclusions.

- [ ] **Step 1: Update hosted runtime docs**

  Add a section documenting:
  - `hosted-app-launcher:workspace` is a UX-purpose graph node;
  - users can reach it through the `start` node;
  - it reads active graph-map selection;
  - it supports selected `.fnl` files and selected directories through strict deterministic conventions;
  - it opens through the existing workspace panel;
  - invalid selections and launch failures show explicit status;
  - it does not add a registry, catalog, search, fs-node hosted actions, manifests, launchable scans, remote adapters, or graph topology persistence of app source data.

- [ ] **Step 2: Run docs search**

  Run:
  ```bash
  rg -n "hosted-app-launcher|Hosted App Launcher|registry|catalog|search|fs-node|start node|selected.*fs|manifest" docs/dev/features/hosted-runtime-apps.md
  ```
  Expected: matches show the new launcher contract and non-goals.

- [ ] **Step 3: Run full Fennel compile and constraints**

  Run:
  ```bash
  make fennel-check
  make constraints
  ```

- [ ] **Step 4: Run focused tests**

  Run:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-source-resolver:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-hosted-source-launcher:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-hosted-app-launcher:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hosted-app-workspace-panel:main
  ```

- [ ] **Step 5: Run broader relevant suite**

  Because this slice crosses graph, widgets, filesystem resolution, and hosted runtime opening, run:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- [ ] **Step 6: Commit Task 6**

  Commit message:
  ```bash
  git add docs/dev/features/hosted-runtime-apps.md
  git commit -m "docs: document hosted app launcher node"
  ```

---

## Final Acceptance Checklist

- `hosted-app-launcher:workspace` resolves through the built-in graph extension loader.
- The `start` node exposes a `Hosted App Launcher` target.
- The launcher view displays current selection status and a `Host selected app` button.
- The button enables only for exactly one selected `fs:` source that resolves by the file/directory rules.
- Clicking the button opens through the existing hosted workspace panel path.
- Invalid selections and launch failures produce explicit status.
- No registry, catalog, search, fs-node hosted action, manifest, launchable scan, or hidden graph expansion is introduced.
- Graph topology persistence remains limited to node keys, edge keys, and map-local interaction state.
