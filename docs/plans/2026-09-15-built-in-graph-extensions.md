# Built-in Graph Extensions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate every built-in graph node type to graph extension descriptors so built-in and user/runtime graph node types use one installation mechanism.

**Architecture:** Add family-scoped built-in graph extension descriptor modules under `graph/extensions/builtins/`, register those descriptors through `app.graph-extension-registry` during app init, and remove the old centralized `graph/key-loaders.fnl` runtime/test setup path. Keep `graph:register-key-loader` only as the low-level primitive used inside descriptor installers; app/runtime setup and tests must use descriptors through the registry.

**Tech Stack:** Space Fennel, `GraphExtensionRegistry`, HomeWorld runtime creation, Graph/GraphMap/GraphMapManager, existing graph node adapter modules, project constraints, and Space Fennel test runner.

## Global Constraints

- Built-in node types and user/runtime node types must both use graph extension descriptors installed through `app.graph-extension-registry`.
- There must be no compatibility wrapper, fallback central registrar, or parallel HomeWorld registration path.
- The low-level `graph:register-key-loader` API remains, but only as the primitive that extension descriptor installers call.
- App/runtime setup, tests, and docs must stop using `GraphKeyLoaders.register` or any equivalent centralized fallback.
- `assets/lua/graph/key-loaders.fnl` should be removed rather than kept as a forwarding module.
- Use family-scoped descriptor modules rather than one monolithic built-in descriptor.
- Descriptors adapt owning stores/systems into graph node adapters; they must not move domain persistence into graph code.
- Existing individual node modules may keep focused `register-loader` helpers only if they are internal utilities used by descriptor installers and still return owner-safe handles.
- Tests should not use individual node `register-loader` helpers to recreate a second built-in installation mechanism except where a node module's helper itself is the unit under test.
- The accepted runtime/test setup path is descriptor registration through the registry.
- Built-in schemes such as `start` are supplied by built-in descriptors.
- Graph core may keep low-level registration primitives and generic edge/node topology behavior.
- Before persisted graph-map topology is hydrated, the registry installs all current descriptors into a temporary runtime containing that graph.
- No missing-store or missing-context fallback should silently skip a built-in family when the family is expected to be present.
- Optional subsystems may register only the schemes whose owning system is available, but the descriptor must make that conditionality explicit and tests must cover it.
- Do not change graph key schemes.
- Do not change graph-map persistence format.
- Do not add compatibility aliases or forwarding shims for `graph/key-loaders`.
- Do not add sandbox/plugin security.
- Do not move domain data ownership into graph descriptors.
- Do not add new graph node types beyond descriptor migration.
- Validation for Fennel changes must run compile check first, constraints second, focused tests third, and broader tests after focused checks pass.
- If `./build/space` may be missing or stale, run `make build` with timeout `14400000` before runtime validation.
- Final validation must include Fennel compile check, constraints, focused graph loader/world/workflow tests, `tests.fast`, and `make test`.

---

### Task 1: Built-in Descriptor Families and Coverage Tests

**Files:**
- Create: `assets/lua/graph/extensions/builtins/common.fnl`
- Create: `assets/lua/graph/extensions/builtins/entities.fnl`
- Create: `assets/lua/graph/extensions/builtins/filesystem.fnl`
- Create: `assets/lua/graph/extensions/builtins/llm.fnl`
- Create: `assets/lua/graph/extensions/builtins/hackernews.fnl`
- Create: `assets/lua/graph/extensions/builtins/kernels.fnl`
- Create: `assets/lua/graph/extensions/builtins/workflows.fnl`
- Create: `assets/lua/graph/extensions/builtins/worlds.fnl`
- Create: `assets/lua/graph/extensions/builtins/init.fnl`
- Test: `assets/lua/tests/test-builtin-graph-extensions.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes:
  - `(registry:register-extension descriptor) -> handle`
  - `(graph:register-key-loader scheme loader-fn opts) -> handle`
  - existing graph node modules under `assets/lua/graph/nodes/`
- Produces:
  - `(BuiltInGraphExtensions.descriptors opts?:table) -> sequential descriptor table`
  - `(BuiltInGraphExtensions.register! registry opts?:table) -> sequential registration handle table`
  - descriptor ids: `builtin-graph-entities`, `builtin-graph-workflows`, `builtin-graph-filesystem`, `builtin-graph-llm`, `builtin-graph-hackernews`, `builtin-graph-kernels`, `builtin-graph-worlds`, `builtin-graph-static`
  - common helpers: `exact-key-loader`, `prefix-loader`, `existing-path-loader`, `existing-any-path-loader`, `collect-handles`, `descriptor`

- [ ] **Step 1: Write failing descriptor coverage tests.**

  Create `assets/lua/tests/test-builtin-graph-extensions.fnl` with tests that require `:graph/extensions/builtins` and assert `BuiltInGraphExtensions.descriptors {}` returns descriptors with non-empty `:id`, `:unit-id`, non-empty sequential `:schemes`, and function `:install-loaders`.

  Add an exact scheme coverage assertion. The expected schemes are:

  ```fennel
  ["activity-background" "activity-canvas" "activity-hud" "activity-lights"
   "activity-light" "activity-light-type" "activity-scene" "activity-scene-panel"
   "activity-scene-panels" "activity-skybox" "activity-surface" "activity-surfaces"
   "activity-terrain" "activity-terrain-editor" "activity-terrain-tool" "activity-terrains"
   "agent-session" "class" "code-dir" "code-entity" "cpp-module" "entities"
   "fnl-module" "fs" "fs-file-viewer" "hackernews-root" "hackernews-story"
   "hackernews-story-list" "hackernews-user" "hud-panel" "hud-panels" "identity"
   "kernel" "kernel-instance" "kernels" "link-entity" "link-entity-list" "list-entity"
   "list-entity-list" "llm" "llm-conversation" "llm-conversations" "llm-message"
   "llm-model" "llm-provider" "llm-tool" "llm-tool-call" "llm-tool-result"
   "llm-tools" "notebook" "notebooks" "quit" "start" "string-entity"
   "string-entity-list" "table" "text-module" "workflow-definition" "workflow-run"
   "workflow-run-event" "workflow-run-explorer" "workflow-run-step" "workflow-run-timeline"
   "workflow-step" "workflow-step-explorer" "workflows" "world" "world-activities"
   "world-activity" "worlds"]
  ```

  The test must fail if any scheme is missing, duplicated, or extra.

- [ ] **Step 2: Run red descriptor tests.**

  Run:

  ```bash
  make build
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-builtin-graph-extensions:main
  ```

  Expected: FAIL because `graph/extensions/builtins` does not exist.

- [ ] **Step 3: Implement common built-in descriptor helpers.**

  Create `assets/lua/graph/extensions/builtins/common.fnl`. Move/copy helper behavior from `graph/key-loaders.fnl` into focused helpers without requiring `graph/key-loaders`:

  - `exact-key-loader expected make-node`
  - `prefix-loader prefix make-node`
  - `existing-path-loader prefix kind make-node`
  - `existing-any-path-loader prefix make-node`
  - `split-key-parts text`
  - `collect-handles ...` that returns a sequential handle table and asserts each handle has `:unregister`
  - `descriptor opts` that asserts `:id`, `:unit-id`, `:schemes`, and `:install-loaders` and returns the descriptor.

  New helpers must not register anything by themselves.

- [ ] **Step 4: Implement entity/static descriptor module.**

  Create `assets/lua/graph/extensions/builtins/entities.fnl`. It must export `descriptors(opts)` returning descriptors for store-backed entity schemes and static/category schemes:

  - `builtin-graph-entities`: `string-entity`, `code-entity`, `list-entity`, `link-entity`, `identity`, `notebook`, `string-entity-list`, `list-entity-list`, `link-entity-list`, `entities`, `notebooks`
  - `builtin-graph-static`: `start`, `quit`, `class`

  The install function must resolve canonical options only: `:string-store`, `:code-store`, `:list-store`, `:link-store`, `:identity-store`, `:notebook-store`, `:kernels`. Do not add underscore aliases.

  Every `graph:register-key-loader` call must pass `{:owner-id ctx.owner-id :extension-id ctx.extension-id}`.

- [ ] **Step 5: Implement workflow descriptor module.**

  Create `assets/lua/graph/extensions/builtins/workflows.fnl`. It must export descriptor `builtin-graph-workflows` with schemes:

  - `workflows`, `workflow-definition`, `workflow-run`, `workflow-step`, `workflow-step-explorer`, `workflow-run-explorer`, `workflow-run-step`, `workflow-run-event`, `workflow-run-timeline`, `agent-session`

  Preserve current conditional behavior: schemes needing `:workflow-runner` should only register when `:workflow-runner` is present, while store-only workflow explorer/step schemes remain available when `:workflow-store` is present. The descriptor's `:schemes` lists all possible schemes; installer returns handles only for available context.

- [ ] **Step 6: Implement filesystem/source/module descriptor module.**

  Create `assets/lua/graph/extensions/builtins/filesystem.fnl`. It must export descriptor `builtin-graph-filesystem` with schemes:

  - `fs`, `fs-file-viewer`, `code-dir`, `fnl-module`, `cpp-module`, `text-module`, `table`

  Preserve current file-kind checks through `graph/file-types.fnl`.

- [ ] **Step 7: Implement LLM, Hacker News, and kernel descriptor modules.**

  Create:
  - `assets/lua/graph/extensions/builtins/llm.fnl` for `llm`, `llm-provider`, `llm-model`, `llm-tools`, `llm-conversations`, `llm-tool`, `llm-conversation`, `llm-message`, `llm-tool-call`, `llm-tool-result`.
  - `assets/lua/graph/extensions/builtins/hackernews.fnl` for `hackernews-root`, `hackernews-story-list`, `hackernews-story`, `hackernews-user`.
  - `assets/lua/graph/extensions/builtins/kernels.fnl` for `kernels`, `kernel`, `kernel-instance`.

  Use canonical options `:llm-store`, `:hackernews-ensure-client`, and `:kernels`.

- [ ] **Step 8: Implement world/activity descriptor module.**

  Create `assets/lua/graph/extensions/builtins/worlds.fnl` for:

  - `worlds`, `world`, `world-activities`, `world-activity`, `activity-surfaces`, `activity-surface`, `activity-scene`, `activity-hud`, `activity-canvas`, `activity-scene-panels`, `activity-terrains`, `activity-skybox`, `activity-background`, `activity-lights`, `activity-scene-panel`, `activity-terrain`, `activity-light-type`, `activity-light`, `activity-terrain-editor`, `activity-terrain-tool`, `hud-panels`, `hud-panel`

  The installer must accept canonical `:world-manager` and `:asset-path-resolver` options and must work during the pre-restore temporary runtime where only `:graph` exists.

- [ ] **Step 9: Implement aggregate built-ins module.**

  Create `assets/lua/graph/extensions/builtins/init.fnl` that requires every family module, concatenates their descriptor lists in deterministic family order, and exports:

  ```fennel
  {:descriptors descriptors
   :register! register!}
  ```

  `register!` must register each descriptor through the provided registry and unregister prior descriptor handles in reverse order if any registration fails.

- [ ] **Step 10: Add tests to fast suite and validate Task 1.**

  Add `:tests.test-builtin-graph-extensions` near other graph extension tests in `assets/lua/tests/fast.fnl`.

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/extensions/builtins/common.fnl --file assets/lua/graph/extensions/builtins/entities.fnl --file assets/lua/graph/extensions/builtins/filesystem.fnl --file assets/lua/graph/extensions/builtins/llm.fnl --file assets/lua/graph/extensions/builtins/hackernews.fnl --file assets/lua/graph/extensions/builtins/kernels.fnl --file assets/lua/graph/extensions/builtins/workflows.fnl --file assets/lua/graph/extensions/builtins/worlds.fnl --file assets/lua/graph/extensions/builtins/init.fnl --file assets/lua/tests/test-builtin-graph-extensions.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-builtin-graph-extensions:main
  ```

- [ ] **Step 11: Commit Task 1.**

  ```bash
  git add assets/lua/graph/extensions/builtins assets/lua/tests/test-builtin-graph-extensions.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(graph): add built-in extension descriptors"
  ```

---

### Task 2: Register Built-ins Through the App Registry and Remove HomeWorld Direct Registration

**Files:**
- Modify: `assets/lua/main.fnl`
- Modify: `assets/lua/home-world.fnl`
- Modify: `assets/lua/tests/test-graph-extension-runtime-plumbing.fnl`
- Modify: `assets/lua/tests/test-builtin-graph-extensions.fnl`

**Interfaces:**
- Consumes:
  - `(BuiltInGraphExtensions.register! registry opts) -> handles`
  - existing `app.ensure-graph-extension-registry!`
  - existing HomeWorld registry temporary/live runtime installation
- Produces:
  - `(app.ensure-built-in-graph-extensions! opts?:table) -> handles`
  - app-owned `app.builtin-graph-extension-handles`
  - HomeWorld runtime creation with no `GraphKeyLoaders.register` call

- [ ] **Step 1: Write failing runtime tests for registry-only built-ins.**

  Extend `assets/lua/tests/test-graph-extension-runtime-plumbing.fnl` with a test named `built-in-graph-extensions-install-before-homeworld-map-restore`. It must:
  - initialize `app.graph-extension-registry`;
  - register built-in graph extensions with a fake world manager and asset resolver;
  - create a HomeWorld runtime with persisted graph map state containing `start` and `worlds` keys;
  - assert those keys hydrate through registry-installed built-ins before map pruning.

  Add a separate test in `test-builtin-graph-extensions.fnl` named `built-in-registration-through-registry-loads-representative-families` that installs descriptors into a real `Graph` via registry and loads representative keys: `start`, `string-entity-list`, `fs:<existing-dir>`, `llm`, `kernels`, and `worlds` when required context exists.

- [ ] **Step 2: Run red runtime tests.**

  Run:

  ```bash
  make build
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-extension-runtime-plumbing:main
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-builtin-graph-extensions:main
  ```

  Expected: FAIL because app startup does not yet register built-in descriptors and HomeWorld still uses `GraphKeyLoaders.register`.

- [ ] **Step 3: Add app-owned built-in descriptor registration.**

  In `assets/lua/main.fnl`, require `:graph/extensions/builtins`. Add `ensure-built-in-graph-extensions!` that:
  - asserts/creates `app.graph-extension-registry`;
  - returns existing `app.builtin-graph-extension-handles` when present;
  - calls `BuiltInGraphExtensions.register! app.graph-extension-registry` with canonical options:
    `:world-manager`, `:asset-path-resolver`, `:code-store`, `:workflow-store`, `:workflow-runner`, and any globally owned stores/systems already available on app;
  - stores handles on `app.builtin-graph-extension-handles`.

  Call it during app init after the registry exists and before user-code units and world activation. During drop, unregister built-in handles before clearing `app.graph-extension-registry`.

- [ ] **Step 4: Remove HomeWorld direct built-in registration.**

  In `assets/lua/home-world.fnl`:
  - remove the `GraphKeyLoaders` require;
  - remove `register-runtime-graph-loaders`;
  - remove `(register-runtime-graph-loaders graph world)` from `create-runtime`.

  HomeWorld must rely entirely on `app.graph-extension-registry:install-runtime` for both temporary restore runtime and final runtime installs.

- [ ] **Step 5: Validate Task 2.**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/main.fnl --file assets/lua/home-world.fnl --file assets/lua/tests/test-graph-extension-runtime-plumbing.fnl --file assets/lua/tests/test-builtin-graph-extensions.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-extension-runtime-plumbing:main
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-builtin-graph-extensions:main
  ```

- [ ] **Step 6: Commit Task 2.**

  ```bash
  git add assets/lua/main.fnl assets/lua/home-world.fnl assets/lua/tests/test-graph-extension-runtime-plumbing.fnl assets/lua/tests/test-builtin-graph-extensions.fnl
  git commit -m "feat(graph): install built-ins through registry"
  ```

---

### Task 3: Remove Graph Core Built-in Node Ownership

**Files:**
- Modify: `assets/lua/graph/core.fnl`
- Modify: `assets/lua/tests/test-graph-core.fnl`
- Modify: `assets/lua/tests/test-graph-map.fnl`
- Modify: `assets/lua/tests/test-graph-view.fnl`
- Modify: any focused tests that construct `Graph` expecting an automatic start node

**Interfaces:**
- Consumes: built-in `start` descriptor from Task 1.
- Produces: graph core with no built-in node imports and no automatic built-in node creation.

- [ ] **Step 1: Write failing graph-core genericity test.**

  In `assets/lua/tests/test-graph-core.fnl`, add a test named `graph-core-does-not-auto-create-built-in-start-node` that constructs `(Graph {})` and asserts `(graph:lookup "start")` is nil and `(graph:node-count)` is `0` before any explicit node additions.

- [ ] **Step 2: Run red graph-core test.**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-core:main
  ```

  Expected: FAIL if graph core still auto-creates `start` by default.

- [ ] **Step 3: Remove built-in node imports and auto-start behavior.**

  In `assets/lua/graph/core.fnl`:
  - remove direct requires of `graph/nodes/start`, `graph/nodes/class`, and `graph/nodes/quit` unless they are used only for exported compatibility;
  - remove `with-start` auto-add behavior;
  - remove `Graph.StartNode`, `Graph.ClassNode`, `Graph.QuitNode` exports if no tests/users require them; update call sites to require node modules directly if they construct those nodes.

- [ ] **Step 4: Update tests that require explicit start nodes.**

  Replace implicit graph start assumptions with explicit descriptor-backed loading or direct node construction, depending on the test purpose:
  - If the test is about built-in loader availability, install built-ins through the registry and call `graph:load-by-key "start"`.
  - If the test is about generic graph behavior, create a plain `Graph.GraphNode` or require `:graph/nodes/start` directly.

- [ ] **Step 5: Validate Task 3.**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/core.fnl --file assets/lua/tests/test-graph-core.fnl --file assets/lua/tests/test-graph-map.fnl --file assets/lua/tests/test-graph-view.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-core:main
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map:main
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  ```

- [ ] **Step 6: Commit Task 3.**

  ```bash
  git add assets/lua/graph/core.fnl assets/lua/tests/test-graph-core.fnl assets/lua/tests/test-graph-map.fnl assets/lua/tests/test-graph-view.fnl
  git commit -m "refactor(graph): keep graph core generic"
  ```

---

### Task 4: Migrate Tests and Remove the Old Registrar

**Files:**
- Create: `assets/lua/tests/graph-builtin-extension-helpers.fnl`
- Modify: `assets/lua/tests/test-graph-loaders.fnl`
- Modify: `assets/lua/tests/test-world-nodes.fnl`
- Modify: `assets/lua/tests/test-world-background-node.fnl`
- Modify: `assets/lua/tests/test-world-skybox-node.fnl`
- Modify: `assets/lua/tests/test-fs-file-viewer.fnl`
- Modify: `assets/lua/tests/test-graph-view.fnl`
- Modify: `assets/lua/tests/test-workflow-graph.fnl`
- Modify: `assets/lua/tests/workflow-run-explorer-cases.fnl`
- Modify: `assets/lua/tests/test-workflow-graph-action-boundaries.fnl`
- Delete: `assets/lua/graph/key-loaders.fnl`
- Modify: `assets/lua/tests/fast.fnl` if renamed/reorganized tests require it

**Interfaces:**
- Consumes:
  - `(BuiltInGraphExtensions.register! registry opts) -> handles`
  - `(Registry.GraphExtensionRegistry opts) -> registry`
- Produces:
  - `(BuiltinGraphTestHelpers.install-builtins! graph opts?:table) -> {:registry table :runtime table :handles table :drop function}`
  - no app/test setup references to `GraphKeyLoaders.register`

- [ ] **Step 1: Add registry-backed built-in test helper.**

  Create `assets/lua/tests/graph-builtin-extension-helpers.fnl`. It must:
  - require `:graph/extension-registry` and `:graph/extensions/builtins`;
  - provide `install-builtins! graph opts` that creates a registry, registers built-in descriptors with canonical opts, installs runtime `{:graph graph :graph-map-manager opts.graph-map-manager}`, and returns a cleanup record;
  - never require `:graph/key-loaders`.

- [ ] **Step 2: Migrate graph loader tests to descriptors.**

  In `assets/lua/tests/test-graph-loaders.fnl`, replace `GraphKeyLoaders.register` setup with `BuiltinGraphTestHelpers.install-builtins!`. Preserve assertions about every existing key scheme. Update tests that previously exercised `GraphKeyLoaders.register` itself to exercise `BuiltInGraphExtensions.descriptors/register!` instead.

- [ ] **Step 3: Migrate world graph tests.**

  In `test-world-nodes.fnl`, `test-world-background-node.fnl`, and `test-world-skybox-node.fnl`, replace direct built-in registration with registry-backed helper setup. Preserve world-manager/asset-resolver fixtures and assertions.

- [ ] **Step 4: Migrate workflow tests.**

  In `test-workflow-graph.fnl`, `workflow-run-explorer-cases.fnl`, and `test-workflow-graph-action-boundaries.fnl`, replace direct workflow loader registration with built-in workflow descriptor installation. Preserve tests that assert missing `workflow-runner` makes runner-backed schemes unavailable.

- [ ] **Step 5: Migrate graph view/filesystem tests.**

  In `test-fs-file-viewer.fnl` and `test-graph-view.fnl`, replace `GraphKeyLoaders.register` setup with registry-backed helper setup.

- [ ] **Step 6: Delete the old centralized registrar.**

  Delete `assets/lua/graph/key-loaders.fnl`. Do not add a replacement file with the same module name.

- [ ] **Step 7: Add no-fallback enforcement test.**

  In `test-builtin-graph-extensions.fnl`, add a test named `graph-key-loaders-module-is-not-present` that asserts requiring `:graph/key-loaders` fails. Also include a repository-search validation command in the report:

  ```bash
  rtk rg -n "GraphKeyLoaders|:graph/key-loaders|graph/key-loaders" assets/lua docs/dev
  ```

  Expected after migration: no runtime/test setup references remain. Documentation may mention the removed file only as historical removal in the new docs.

- [ ] **Step 8: Validate Task 4.**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-loaders:main
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-world-nodes:main
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-builtin-graph-extensions:main
  rtk rg -n "GraphKeyLoaders|:graph/key-loaders|graph/key-loaders" assets/lua docs/dev
  ```

  The search must find no app/runtime/test setup references. If docs intentionally mention the removed file, the report must list those doc-only historical references and reviewer must verify they do not describe a supported path.

- [ ] **Step 9: Commit Task 4.**

  ```bash
  git add assets/lua/tests assets/lua/graph/key-loaders.fnl
  git commit -m "refactor(graph): remove legacy key loader registrar"
  ```

---

### Task 5: Documentation and Final Validation

**Files:**
- Modify: `docs/dev/features/reloadable-graph-extension-units.md`
- Modify: `docs/dev/notes/graph.md`
- Modify: `docs/dev/notes/graph-key-based-loaders.md`
- Modify: `docs/dev/graph-maps.md` if adapter refresh wording references the old registrar
- Modify: `assets/lua/constraints/baseline-data.fnl` only if constraints require reviewed baseline updates

**Interfaces:**
- Consumes: final built-in descriptor API and removed legacy registrar.
- Produces: canonical documentation that the graph extension registry is the only node-type installation mechanism.

- [ ] **Step 1: Update reloadable graph extension docs.**

  In `docs/dev/features/reloadable-graph-extension-units.md`, add a built-in section stating:
  - built-ins and user graph extensions use the same registry;
  - built-in descriptor families and ownership boundaries;
  - `graph:register-key-loader` is low-level installer code only;
  - `graph/key-loaders.fnl` no longer exists and is not a supported path.

- [ ] **Step 2: Update graph doctrine docs.**

  In `docs/dev/notes/graph.md`, replace any centralized built-in key-loader language with descriptor/registry language while preserving the doctrine that graph core is an exposure/adaptor layer and persists topology only.

- [ ] **Step 3: Update key-loader docs.**

  In `docs/dev/notes/graph-key-based-loaders.md`, document built-in descriptors as the runtime mechanism. Keep `graph:register-key-loader` documented only as the primitive used by descriptors, not by app setup.

- [ ] **Step 4: Run final validation.**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-builtin-graph-extensions:main
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-extension-runtime-plumbing:main
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-loaders:main
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-world-nodes:main
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.fast:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- [ ] **Step 5: Run no-fallback repository search.**

  Run:

  ```bash
  rtk rg -n "GraphKeyLoaders|:graph/key-loaders|graph/key-loaders" assets/lua docs/dev
  ```

  Expected: no app/runtime/test setup references. Any remaining docs hit must explicitly describe the removed historical path, not a supported API.

- [ ] **Step 6: Commit Task 5.**

  ```bash
  git add docs/dev/features/reloadable-graph-extension-units.md docs/dev/notes/graph.md docs/dev/notes/graph-key-based-loaders.md docs/dev/graph-maps.md assets/lua/constraints/baseline-data.fnl
  git commit -m "docs(graph): document single graph extension mechanism"
  ```
