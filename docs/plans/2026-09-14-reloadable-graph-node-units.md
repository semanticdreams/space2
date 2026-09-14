# Reloadable Graph Node Units Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and validate an end-to-end vertical prototype proving reloadable runtime graph extension units can add, reload, refresh, morph, and unload graph node types without root reload or whole-graph teardown.

**Architecture:** Add owner-safe registration handles for graph key loaders and morphs, add a small graph extension registry that installs descriptors into live and future world graph runtimes, and prove the seam with a real `ModuleUnit` loaded from a user-code-style temp directory. The prototype owns a `demo-node` key scheme, adapter, preview, full view, morph, reload refresh, and unload cleanup through the same registry seam production units will use.

**Tech Stack:** Space Fennel, `Unit` / `ModuleUnit` / `UnitManager`, `HotReloadController`, `Graph`, `GraphMap`, `GraphMapManager`, `GraphView` preview/view contracts, `Morphs`, `Signal`, project-native `tools.fennel-check`, constraints, and the Fennel test runner.

## Global Constraints

- Use reloadable graph extension units as the primary seam.
- Root reload remains a fallback boundary only.
- The graph activity unit owns shared graph activity UI/runtime behavior; it must not become the owner of all graph node types.
- Prove the full loop in one vertical path: key loader, adapter, preview, full view, morph, reload, unload, and visible-node adapter refresh.
- Graph topology remains key-only; owning units/systems own domain data.
- Duplicate active key-loader or morph registrations fail loudly.
- Unregistering the same inactive handle is idempotent; stale handles cannot remove another active registration.
- Extension install into a runtime must either complete with recorded handles or roll back any handles installed during the failed attempt.
- Explicit adapter refresh must fail loudly when a visible node cannot be rebuilt.
- Unit unload must remove loaders, morphs, registry handles, and unit-owned signal subscriptions.
- Fennel code uses `local`, factory functions, explicit errors, and no silent fallbacks for missing required context.
- Widget/view builders used by previews and full views return build closures and assert required context.
- Do not add sandbox/plugin isolation, a dependency graph for hot reload, automatic marketplace discovery, root-reload escalation, or graph-topology persistence for domain data.
- If `./build/space` is missing or stale, run `make build` with timeout `14400000` before runtime validation.
- Fennel validation order is compile check, constraints, focused tests, broader tests.
- Required final validation: focused graph extension tests, `tests.fast`, and `make test`; PR CI remains the integration gate.

---

### Task 1: Owner-Safe Graph Key Loader Handles and GraphMap Adapter Refresh

**Files:**
- Modify: `assets/lua/graph/key-loader-utils.fnl`
- Modify: `assets/lua/graph/core.fnl`
- Modify: `assets/lua/graph/map.fnl`
- Test: `assets/lua/tests/test-graph-core.fnl`
- Test: `assets/lua/tests/test-graph-map.fnl`

**Interfaces:**
- Consumes: existing `graph:register-key-loader(scheme, loader-fn)`, `graph:load-by-key`, `graph:create-node-by-key`, `GraphMap:add-node`, `GraphMap` node replacement signals.
- Produces:
  - `(KeyLoaderUtils.key-scheme key:string) -> string|nil`
  - `(graph:register-key-loader scheme:string loader-fn:function opts?:{:owner-id string? :extension-id string?}) -> handle`
  - `(graph:unregister-key-loader handle-or-scheme:table|string opts?:{:owner-id string? :registration-id integer?}) -> boolean`
  - `(graph:key-loader-owner scheme:string) -> string|nil`
  - `(graph-map:refresh-adapters-by-scheme scheme:string) -> {:scheme string :refreshed table :failed table}`

- [ ] **Step 1: Add failing key-loader handle tests.**

  Add tests to `assets/lua/tests/test-graph-core.fnl` that assert:
  - `graph:register-key-loader` returns a handle for scheme `ext` with owner `unit-a`.
  - `graph:key-loader-owner "ext"` returns `unit-a`.
  - `graph:unregister-key-loader handle` removes the loader and is idempotent on the same inactive handle.
  - Registering another active loader for `ext` fails with an error containing `duplicate scheme: ext`.
  - A stale handle from `unit-a` cannot unregister a later `unit-b` loader and errors with `belongs to another registration`.

  Use this assertion shape for the stale-handle test:

  ```fennel
  (local handle-a
    (graph:register-key-loader "ext"
                               (fn [key] (Graph.GraphNode {:key key :label "a"}))
                               {:owner-id "unit-a"}))
  (graph:unregister-key-loader handle-a)
  (graph:register-key-loader "ext"
                             (fn [key] (Graph.GraphNode {:key key :label "b"}))
                             {:owner-id "unit-b"})
  (local (ok err) (pcall #(graph:unregister-key-loader handle-a)))
  (assert (not ok) "stale handle should not remove another owner registration")
  (assert (string.find (tostring err) "belongs to another registration" 1 true))
  ```

- [ ] **Step 2: Add failing GraphMap refresh tests.**

  Add tests to `assets/lua/tests/test-graph-map.fnl` that create a shared `Graph`, a `GraphMap`, a loader-backed scheme `ext`, two visible nodes `ext:a` and `ext:b`, and an edge from `a` to `b`. Set `map.selected_node_keys` to `["ext:a"]` and `map.focused_node_key` to `"ext:b"`; change loader behavior from label `v1` to `v2`; call `(map:refresh-adapters-by-scheme "ext")`; assert labels are `v2`, edge endpoints point at replacement adapters, selection/focus keys are unchanged, and `node-replaced` emitted twice.

  Add a second test where the loader returns nil after a node is visible; assert `(pcall #(map:refresh-adapters-by-scheme "ext"))` fails with `failed to refresh graph nodes for scheme ext` and the previous adapter remains visible.

- [ ] **Step 3: Run red tests.**

  ```bash
  make build
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-core:main
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map:main
  ```

  Expected: FAIL because owner-aware unregister and adapter refresh do not exist.

- [ ] **Step 4: Implement key scheme helper.**

  Add and export `key-scheme` in `assets/lua/graph/key-loader-utils.fnl`:

  ```fennel
  (fn key-scheme [key]
    (when (and key (= (type key) "string"))
      (local (start _end) (string.find key ":" 1 true))
      (if start
          (string.sub key 1 (- start 1))
          key)))
  ```

- [ ] **Step 5: Implement owner-safe loader records.**

  In `assets/lua/graph/core.fnl`, store key loaders as registration records containing `:scheme`, `:loader-fn`, `:owner-id`, `:extension-id`, `:registration-id`, and `:active?`. Keep existing two-argument callers working by accepting nil opts. Return a handle with the same identity fields and an `:unregister` method that calls `graph:unregister-key-loader`.

- [ ] **Step 6: Implement unregister and diagnostics.**

  Add `graph:unregister-key-loader` and `graph:key-loader-owner`. Same-handle unregister removes the active record; repeated same-handle unregister returns true; stale handle unregister errors with `belongs to another registration`; string unregister requires matching `opts.owner-id` when the registration has an owner.

- [ ] **Step 7: Update loader consumers.**

  Update `load-by-key`, `create-node-by-key`, and `has-key-loader-for-key` to read `registration.loader-fn`.

- [ ] **Step 8: Implement GraphMap refresh.**

  Add `graph-map:refresh-adapters-by-scheme`. It asserts a non-empty string scheme, finds matching visible nodes using `KeyLoaderUtils.key-scheme`, prebuilds all replacements via `shared-graph:create-node-by-key`, errors before mutating if any replacement is missing, then replaces each node through the existing `replace-node` helper and returns refreshed keys.

- [ ] **Step 9: Validate Task 1.**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/key-loader-utils.fnl --file assets/lua/graph/core.fnl --file assets/lua/graph/map.fnl --file assets/lua/tests/test-graph-core.fnl --file assets/lua/tests/test-graph-map.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-core:main
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map:main
  ```

- [ ] **Step 10: Commit Task 1.**

  ```bash
  git add assets/lua/graph/key-loader-utils.fnl assets/lua/graph/core.fnl assets/lua/graph/map.fnl assets/lua/tests/test-graph-core.fnl assets/lua/tests/test-graph-map.fnl
  git commit -m "feat(graph): add owner-safe loader refresh seam"
  ```

---

### Task 2: Owner-Safe Morph Handles

**Files:**
- Modify: `assets/lua/morphs/init.fnl`
- Create: `assets/lua/tests/test-graph-extension-morphs.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: existing `(morphs:register from-scheme to-scheme morph-fn meta)` and `morphs:target-items`.
- Produces:
  - `(morphs:register from-scheme:string to-scheme:string morph-fn:function meta?:table opts?:{:owner-id string? :extension-id string?}) -> handle`
  - `(morphs:unregister handle-or-from:table|string to-scheme?:string opts?:{:owner-id string? :registration-id integer?}) -> boolean`
  - `(morphs:morph-owner from-scheme:string to-scheme:string) -> string|nil`

- [ ] **Step 1: Create failing morph tests.**

  Create `assets/lua/tests/test-graph-extension-morphs.fnl` with three tests:
  - owner-safe morph handle unregisters current registration;
  - duplicate active morph registration fails loudly with `duplicate morph: demo-node -> demo-target`;
  - stale morph handle cannot remove a new owner and errors with `belongs to another registration`.

  Use a real `(Morphs.Morphs {})`; register `demo-node -> demo-target`; assert `morphs:morph-owner` returns the owner; assert `morphs:target-items {:key "demo-node:a"}` changes from one target to zero after unregister.

- [ ] **Step 2: Add the test module to fast suite.**

  Add `:tests.test-graph-extension-morphs` immediately after `:tests.test-morphs` in `assets/lua/tests/fast.fnl`.

- [ ] **Step 3: Run red morph tests.**

  ```bash
  make build
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-extension-morphs:main
  ```

  Expected: FAIL because morph handles and unregister do not exist.

- [ ] **Step 4: Implement owner-safe morph records.**

  Store each morph as `{:run morph-fn :label label :from-scheme from-scheme :to-scheme to-scheme :owner-id owner-id :extension-id extension-id :registration-id registration-id :active? true}`. Preserve existing four-argument register calls by accepting nil opts. Return a handle with `:unregister`.

- [ ] **Step 5: Implement unregister and diagnostics.**

  Add `morphs:unregister` and `morphs:morph-owner` with the same semantics as loader handles: same-handle idempotence, stale-handle owner protection, and owner matching for string pair unregister.

- [ ] **Step 6: Validate Task 2.**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/morphs/init.fnl --file assets/lua/tests/test-graph-extension-morphs.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-extension-morphs:main
  ```

- [ ] **Step 7: Commit Task 2.**

  ```bash
  git add assets/lua/morphs/init.fnl assets/lua/tests/test-graph-extension-morphs.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(graph): add owner-safe morph handles"
  ```

---

### Task 3: Graph Extension Registry for Live and Future Runtimes

**Files:**
- Create: `assets/lua/graph/extension-registry.fnl`
- Create: `assets/lua/tests/test-graph-extension-registry.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: loader handles, morph handles, `GraphMap:refresh-adapters-by-scheme`, runtime tables with `:graph` and `:graph-map-manager`.
- Produces:
  - `(GraphExtensionRegistry.GraphExtensionRegistry opts?:{:app table?}) -> registry`
  - `(registry:register-extension descriptor) -> handle`
  - `(registry:unregister-extension handle-or-id) -> boolean`
  - `(registry:install-runtime runtime:table) -> boolean`
  - `(registry:uninstall-runtime runtime:table) -> boolean`
  - `(registry:refresh-extension extension-id:string) -> table`
  - `(registry:refresh-unit unit-id:string) -> table`
  - `(registry:debug-state) -> table`
  - descriptor shape: `{:id string :unit-id string :schemes [string...] :install-loaders function :install-morphs function? :refresh-schemes [string...]?}`

- [ ] **Step 1: Create failing registry tests.**

  Create `assets/lua/tests/test-graph-extension-registry.fnl` with tests named:
  - `extension-registry-installs-into-live-and-future-runtime`: create one runtime before registering extension and one runtime after; assert both can load `demo-node:a`.
  - `extension-registry-unregister-cleans-loaders-and-morphs`: unregister extension and assert `graph:create-node-by-key "demo-node:c"` returns nil and morph target items are empty.
  - `extension-registry-rolls-back-partial-install`: make the second runtime installer throw; assert first runtime has no installed `demo-node` loader afterward.
  - `extension-registry-refreshes-visible-adapters-by-scheme`: load `demo-node:a`, change a captured `version` from `v1` to `v2`, call `registry:refresh-extension`, assert the active map node has label `v2` and the key remains `demo-node:a`.

  The descriptor in tests must use real handles:

  ```fennel
  {:id "demo-extension"
   :unit-id "user-demo-extension"
   :schemes ["demo-node"]
   :install-loaders
   (fn [graph ctx]
     [(graph:register-key-loader
        "demo-node"
        (fn [key] (Graph.GraphNode {:key key :label version}))
        {:owner-id ctx.owner-id :extension-id ctx.extension-id})])}
  ```

- [ ] **Step 2: Register tests in fast suite.**

  Add `:tests.test-graph-extension-registry` immediately after `:tests.test-graph-extension-morphs` in `assets/lua/tests/fast.fnl`.

- [ ] **Step 3: Run red registry tests.**

  ```bash
  make build
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-extension-registry:main
  ```

  Expected: FAIL because `graph/extension-registry.fnl` does not exist.

- [ ] **Step 4: Implement descriptor validation and registration.**

  Validate non-empty `id`, `unit-id`, non-empty sequential `schemes`, `install-loaders` function, optional `install-morphs` function, and duplicate extension id errors containing `duplicate graph extension`.

- [ ] **Step 5: Implement runtime install with rollback.**

  For each runtime, call `descriptor.install-loaders runtime.graph ctx`; call `descriptor.install-morphs runtime.graph.morphs ctx` when present. Record returned handles. If any installer fails, call `:unregister` on handles already installed for that runtime before rethrowing.

- [ ] **Step 6: Implement live/future runtime behavior.**

  `register-extension` installs into all installed runtimes and rolls back all runtimes on failure before storing the extension. `install-runtime` installs all existing extensions into the new runtime. `unregister-extension` and `uninstall-runtime` unregister all recorded handles.

- [ ] **Step 7: Implement refresh and debug state.**

  `refresh-extension` refreshes `(or descriptor.refresh-schemes descriptor.schemes)` across every installed runtime's active map. `refresh-unit` refreshes all extensions with matching `unit-id`. `debug-state` returns sorted extension summaries and `runtime-count`.

- [ ] **Step 8: Validate Task 3.**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/extension-registry.fnl --file assets/lua/tests/test-graph-extension-registry.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-extension-registry:main
  ```

- [ ] **Step 9: Commit Task 3.**

  ```bash
  git add assets/lua/graph/extension-registry.fnl assets/lua/tests/test-graph-extension-registry.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(graph): add runtime extension registry"
  ```

---

### Task 4: End-to-End Reloadable Demo Graph Extension Unit

**Files:**
- Modify: `assets/lua/units.fnl`
- Modify: `assets/lua/hot-reload.fnl`
- Create: `assets/lua/tests/test-graph-extension-units.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: graph extension registry, `ModuleUnit`, `UnitManager.reload-unit`, `HotReloadController`, owner-safe loader/morph handles, `GraphMap:refresh-adapters-by-scheme`.
- Produces:
  - `(Units.refresh-graph-extensions-for-unit! unit-id:string) -> boolean`
  - Direct `Unit:reload` refreshes graph extensions after restore.
  - `HotReloadController` refreshes graph extensions for the target unit after manual restore.

- [ ] **Step 1: Create failing vertical unit tests.**

  Create `assets/lua/tests/test-graph-extension-units.fnl` with `reloadable-demo-graph-extension-unit-refreshes-visible-node-without-root-reload`. The test must create a temp user-code directory containing `demo_extension/init.fnl`, set `app.graph-extension-registry`, create a real `Graph` with `:with-start false` and a real `Morphs.Morphs`, create a real `GraphMapManager`, install the runtime, load a `ModuleUnit` with id `user-demo-extension`, load `demo-node:a` and `demo-node:b`, add edge `a -> b`, set selection/focus keys, assert v1 preview/view labels, rewrite the unit source to v2, call `(manager:reload-unit "user-demo-extension" {:source :test})`, and assert the visible adapters are different tables with v2 labels while root reload count remains `0`, edge endpoints point to v2 adapters, and selection/focus keys remain unchanged.

  Add a morph assertion: after reload, `graph.morphs:target-items {:key "demo-node:a"}` has one `:to-scheme "demo-node"`; applying that morph returns target key `demo-node:a-morphed-v2`, and loading that key succeeds.

  Add unload assertions: unregister/drop the unit, then assert `graph:create-node-by-key "demo-node:c"` is nil and morph target items for `demo-node:b` are empty.

- [ ] **Step 2: Generate exact demo unit source in the test.**

  Add `(demo-unit-source version)` helper in the test. It writes a module that requires `:graph/init` and `:graph/key-loader-utils`, registers extension id `demo-extension`, unit id `user-demo-extension`, scheme `demo-node`, a loader producing nodes with labels `Demo v1 a` or `Demo v2 a`, preview builders returning layout names `preview-v1-a` or `preview-v2-a`, full view builders returning `view-v1-a` or `view-v2-a`, and a self-morph returning `target-key` with suffix `-morphed-v1` or `-morphed-v2`. Its `drop` calls `extension-handle:unregister`.

- [ ] **Step 3: Create failing hot reload routing test.**

  Add `hot-reload-controller-refreshes-demo-extension-unit`. Use the same `ModuleUnit`, mutate its file from v1 to v2, call `(controller:reload-now! {:changes [{:path init-path :action "modified"}]})`, and assert the active map's existing `demo-node:a` adapter label becomes `Demo v2 a` without reconstructing graph or graph map.

- [ ] **Step 4: Register tests in fast suite and run red.**

  Add `:tests.test-graph-extension-units` immediately after `:tests.test-graph-extension-registry` in `assets/lua/tests/fast.fnl`.

  ```bash
  make build
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-extension-units:main
  ```

  Expected: FAIL because unit reload and hot reload do not refresh graph extensions for the target unit.

- [ ] **Step 5: Add unit-level graph extension refresh helper.**

  In `assets/lua/units.fnl`, export `refresh-graph-extensions-for-unit!`:

  ```fennel
  (fn refresh-graph-extensions-for-unit! [unit-id]
    (when (and app app.graph-extension-registry app.graph-extension-registry.refresh-unit)
      (app.graph-extension-registry:refresh-unit unit-id))
    true)
  ```

  Call it at the end of `Unit:reload` after restore succeeds.

- [ ] **Step 6: Refresh after hot reload restore.**

  In `assets/lua/hot-reload.fnl`, after successful `(target-unit:restore snapshot reload-ctx)` in the manual reload path, call the exported `Units.refresh-graph-extensions-for-unit!` with `target-unit.id`.

- [ ] **Step 7: Validate Task 4.**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/units.fnl --file assets/lua/hot-reload.fnl --file assets/lua/tests/test-graph-extension-units.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-extension-units:main
  ```

- [ ] **Step 8: Commit Task 4.**

  ```bash
  git add assets/lua/units.fnl assets/lua/hot-reload.fnl assets/lua/tests/test-graph-extension-units.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(graph): prove reloadable extension unit path"
  ```

---

### Task 5: App Runtime Plumbing, Documentation, and Full Validation

**Files:**
- Modify: `assets/lua/main.fnl`
- Modify: `assets/lua/home-world.fnl`
- Create: `assets/lua/tests/test-graph-extension-runtime-plumbing.fnl`
- Modify: `assets/lua/tests/fast.fnl`
- Create: `docs/dev/features/reloadable-graph-extension-units.md`
- Modify: `docs/dev/notes/graph.md`
- Modify: `docs/dev/graph-maps.md`

**Interfaces:**
- Consumes: graph extension registry and existing HomeWorld runtime creation/drop.
- Produces:
  - `app.graph-extension-registry`
  - `(Main.ensure-graph-extension-registry!) -> registry`
  - world runtimes installed into the registry after graph/map-manager creation and uninstalled before graph cleanup.

- [ ] **Step 1: Create failing runtime plumbing tests.**

  Create `assets/lua/tests/test-graph-extension-runtime-plumbing.fnl` with:
  - `main-ensures-graph-extension-registry`: require `:main`, call `(Main.ensure-graph-extension-registry!)`, assert `app.graph-extension-registry` exists and debug-state runtime-count is `0`.
  - `registry-installed-runtime-debug-state-is-visible`: create a registry, a real `Graph`, a real `GraphMapManager`, install/uninstall runtime, and assert debug-state runtime-count changes `0 -> 1 -> 0`.

- [ ] **Step 2: Register tests and run red.**

  Add `:tests.test-graph-extension-runtime-plumbing` immediately after `:tests.test-graph-extension-units` in `assets/lua/tests/fast.fnl`.

  ```bash
  make build
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-extension-runtime-plumbing:main
  ```

  Expected: FAIL because app-level registry creation is not exported or wired.

- [ ] **Step 3: Add app-level registry creation.**

  In `assets/lua/main.fnl`, require `:graph/extension-registry`; add `ensure-graph-extension-registry!`; call it during app init before user-code units load; export it from the module return table. During drop, clear user units/unit manager before setting `app.graph-extension-registry` nil.

- [ ] **Step 4: Install and uninstall world runtimes.**

  In `assets/lua/home-world.fnl`, after runtime construction includes `:graph` and `:graph-map-manager`, call `(app.graph-extension-registry:install-runtime runtime)` when present. In runtime cleanup, call `(app.graph-extension-registry:uninstall-runtime runtime)` before dropping graph-map-manager or graph.

- [ ] **Step 5: Document the new seam.**

  Create `docs/dev/features/reloadable-graph-extension-units.md` covering descriptor shape, loader/morph owner handles, live/future runtime installation, refresh-by-scheme semantics, unit reload and hot reload refresh, graph topology invariants, and a minimal `demo-node` unit example. Link it from `docs/dev/notes/graph.md` and add a GraphMap adapter-refresh note to `docs/dev/graph-maps.md`.

- [ ] **Step 6: Validate Task 5 and full suite.**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/main.fnl --file assets/lua/home-world.fnl --file assets/lua/tests/test-graph-extension-runtime-plumbing.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-extension-runtime-plumbing:main
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-extension-units:main
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-extension-registry:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.fast:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- [ ] **Step 7: Commit Task 5.**

  ```bash
  git add assets/lua/main.fnl assets/lua/home-world.fnl assets/lua/tests/test-graph-extension-runtime-plumbing.fnl assets/lua/tests/fast.fnl docs/dev/features/reloadable-graph-extension-units.md docs/dev/notes/graph.md docs/dev/graph-maps.md
  git commit -m "feat(graph): wire extension registry into runtime"
  ```
