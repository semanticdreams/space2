# Entity-Type Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Derive Entities browsing from one explicit catalog and expose code entities.

**Architecture:** App composition owns an immutable catalog of browsing metadata.
Existing graph extensions install store-injected loaders per runtime. Entities
and the new code browser navigate through their containing GraphMap.

**Tech Stack:** Fennel, entity stores/signals, GraphMap, SearchView, native tests.

**Spec:** `docs/specs/2026-10-14-entity-type-catalog-design.md`.

## Global Constraints

- Each descriptor has canonical nonempty string fields `id`, `label`,
  `action-name`, `icon`, and `browser-key`.
- Validate dense ordered input and unique IDs.
- Copy input and output descriptors so callers cannot mutate catalog contents.
- No registration/removal API, signal, store, or node instance belongs in this catalog.
- Labels equal IDs for built-ins. Preserve declaration/action order;
  SearchView retains its existing alphabetical search presentation.
- Publish only after successful registration. Repeated initialization reuses it
  and rejects conflicting explicit replacement while built-ins are installed.
- Runtime creation/uninstallation does not change it. Tests use isolated
  catalogs. Teardown releases the app reference.
- Graph extension descriptors remain the sole loader installation mechanism.
- New Fennel self objects use final literals with methods included;
  affected legacy code is simplified only as needed for this change.
- Preserve existing graph keys, action labels, entity storage formats, and
  persisted topology. No graph-core/C++ changes, discovery, CRUD framework,
  identity browser, notebook-menu migration, live membership changes, or
  unrelated browser refactoring. No rebase or force push.
- Implement sequentially. Do not commit implementation before independent
  reviewer pass; the supervisor owns reviewed checkpoint commits.

## File responsibilities

- `entities/type-catalog.fnl`: pure validated metadata catalog.
- `graph/extensions/builtins/entities.fnl`: metadata manifest and store-injected
  graph loaders; `builtins/init.fnl` exposes the manifest through the aggregate.
- `graph/nodes/code-entity-list.fnl`: listing/navigation/store subscriptions;
  its matching view owns SearchView and UI subscriptions.
- `main.fnl`: catalog initialization, successful publication, reuse, teardown.
- `graph/nodes/entities.fnl`: catalog-derived rows/actions/key navigation.
- `graph/nodes/start.fnl`: lazy Entities key target; other targets unchanged.
- Tests cover catalog, node/view lifecycles, map locality and app composition;
  docs explain intentional catalog composition versus loader installation.

## Shared validation and runtime prerequisite

The build directory is absent. Before runtime tests run `make build` with
timeout **14400000 ms**; use `make cmake` with timeout **600000 ms** if needed.
Set direct-command environment:

```bash
export SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data
export SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets"
export FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"
export FENNEL_MACRO_PATH="$FENNEL_PATH"
```

Run native compile checks, then constraints, then focused tests in that order.
For touched files use `./build/space -m tools.fennel-check:main -- --target files
--file <path>` with a repeated `--file` for each touched Fennel file. Constraints:
`make constraints`. A deliberate behavioral RED is expected; unexpected
compile/constraint/test/build failures require systematic debugging.
Do not use external Lua/Fennel validation or expand baselines to bypass failures.
Record compile/constraints/test commands/results and constraint impact.

---

### Task 1: Catalog and explicit built-in metadata

**Files:** Create `assets/lua/entities/type-catalog.fnl` and
`assets/lua/tests/test-entity-type-catalog.fnl`; modify
`assets/lua/graph/extensions/builtins/entities.fnl`,
`assets/lua/graph/extensions/builtins/init.fnl`, `assets/lua/tests/fast.fnl`.

**Interfaces:** Export `{:EntityTypeCatalog EntityTypeCatalog}`;
`EntityTypeCatalog({:types descriptors}) -> catalog`;
`catalog:list-types() -> fresh descriptors`; `catalog:get-type(id) -> fresh
descriptor` or error. Both built-in modules export `entity-types()` returning
a fresh ordered sequence. Empty catalog is valid; dictionary/sparse input is not.

- [ ] Write tests first using existing suite/runner conventions. Include this
  mutation-isolation test and table-driven missing/empty/nonstring fields,
  duplicate IDs, sparse/non-sequence input, empty catalog, and unknown lookup:

```fennel
(local input [{:id "code" :label "code" :action-name "Code Entities"
               :icon "code" :browser-key "code-entity-list"}])
(local catalog (EntityTypeCatalog {:types input}))
(set (. input 1 :label) "mutated")
(assert (= (. (catalog:get-type "code") :label) "code"))
(local rows (catalog:list-types))
(set (. rows 1 :browser-key) "wrong")
(assert (= (. (catalog:get-type "code") :browser-key) "code-entity-list"))
(local (ok err) (pcall #(catalog:get-type "unknown")))
(assert (not ok))
(assert (string.find (tostring err) "unknown" 1 true))
```

- [ ] Compile tests, run constraints, then
  `./build/space -m tests.test-entity-type-catalog:main`; capture RED for absent API.
- [ ] Implement dense sequence validation by checking all indices are positive
  integers and count equals maximum; validate and copy all five fields, rejecting
  duplicate IDs. Keep ordered descriptors and lookup private. Return final literal:

```fennel
{:list-types (fn [_self]
               (icollect [_ descriptor (ipairs ordered)]
                 (copy-descriptor descriptor)))
 :get-type (fn [_self id]
             (copy-descriptor
               (assert (. by-id id)
                       (.. "EntityTypeCatalog unknown type: " (tostring id)))))}
```

- [ ] Define fresh built-in metadata: string/text_fields/string-entity-list,
  link/link/link-entity-list, list/list/list-entity-list,
  dict/data_object/dict-entity-list, code/code/code-entity-list, in that order.
  Action names are respectively String/Link/List/Dict/Code Entities; labels equal
  IDs. Expose the function from the aggregate; register suite in tests.fast.
- [ ] Compile touched files, constraints, catalog and built-in extension suites;
  check all icons by exact name in assets/material-design-icons/icons.txt.
  Run `git diff --check`. Hand off for independent review then reviewed checkpoint
  `feat(lua): add immutable entity type catalog`.

### Task 2: Code browser and exact-key loader

**Files:** Create `assets/lua/graph/nodes/code-entity-list.fnl`,
`assets/lua/graph/view/views/code-entity-list.fnl`,
`assets/lua/tests/test-code-entity-list.fnl`; modify builtins/entities.fnl,
tests/test-builtin-graph-extensions.fnl and tests/fast.fnl.

**Interfaces:** Bare factory `CodeEntityListNode({:store store})`; required store,
key code-entity-list, label code entities, size 8.0. Expose store, items-changed,
collect-items/emit-items/add-entity-node/drop and Refresh action only.
View factory returns build(ctx) closure with search/layout/refresh-items/drop.

- [ ] Write isolated real-store/GraphMap tests with existing
  tests/graph-builtin-extension-helpers.fnl fixtures. Assert listing bounded
  single-line labels, name fallback, no source payload, explicit-store identity,
  exact-key rejection for code-entity-list:unexpected, stale-row/missing context
  errors, repeated-opening deduplication, and two map-local adapter identities:

```fennel
(local browser (assert (graph-map:load-by-key "code-entity-list")))
(assert (= browser.store supplied-code-store))
(local opened (browser:add-entity-node entity))
(assert (= opened.key (.. "code-entity:" entity.id)))
(assert (= opened.store supplied-code-store))
(assert (= opened (browser:add-entity-node entity)))
(assert (= (graph-map:edge-count) 1))
```

- [ ] Test real create/update/delete events refresh rows. Instrument private
  test signal wrappers to count connections/list reads: one subscription per
  signal/browser, zero after drop, no reads after drop. Build two views, exercise
  SearchView row button and submitted signal, drop one, mutate again and ensure
  other works; drop both without dropping store/node. Missing build context fails.
- [ ] Compile tests, constraints, run tests.test-code-entity-list:main for RED.
- [ ] Implement listing from required store:list-entities. Collapse whitespace
  and use graph/view/utils truncation (50 UTF-8 characters) for names and
  ID/language fallback. Capture subscriptions privately, disconnect on idempotent
  drop. Include methods in final self literal without changing node-base.
  Resolve selected records through map navigation:

```fennel
(local key (.. "code-entity:" entity.id))
(local graph-map (assert self.graph (.. "missing GraphMap for " key)))
(assert (= (type graph-map.load-by-key) "function"))
(assert (= (type graph-map.add-edge) "function"))
(local target (assert (graph-map:load-by-key key) (.. "failed to load " key)))
(graph-map:add-edge (GraphEdge {:source self :target target}))
target
```

- [ ] Build SearchView with default row builder and one submitted handler, avoiding
  duplicate click routing. Connect items before initial emit; own/disconnect
  callbacks and drop SearchView. Do not directly overwrite search.items.
- [ ] Add exact-key code-entity-list loader and scheme to existing entity extension,
  capturing the same code-store as the individual code loader. Extend expected
  scheme and representative-loader tests; register suite in tests.fast.
- [ ] Compile touched files, constraints, focused code-list/code-entity/built-in
  extension/graph-map suites; diff check. Independent review then checkpoint
  `feat(lua): add map-local code entity browser`.

### Task 3: App ownership and catalog-driven navigation

**Files:** Modify assets/lua/main.fnl, graph/nodes/entities.fnl,
graph/nodes/start.fnl, graph/view/views/entities.fnl,
graph/extensions/builtins/entities.fnl, tests/graph-builtin-extension-helpers.fnl,
tests/test-builtin-graph-extensions.fnl, tests/test-graph-extension-runtime-plumbing.fnl,
tests/test-main-events.fnl, tests/test-{string,link,list,dict}-entities.fnl,
tests/fast.fnl. Create tests/test-entities-browser.fnl and
docs/dev/features/entity-type-catalog.md. Correct only the Entities section of
docs/dev/notes/string-entities.md. Paths without prefix are under assets/lua.

**Interfaces:** app.entity-type-catalog; canonical :entity-type-catalog option
to Main.ensure-built-in-graph-extensions!, entity extension and EntitiesNode.
Entities rows remain [type-id,label], generated actions preserve order.
Start collect-targets includes ["entities","entities"]; string targets resolve
on selection, existing function/node targets unchanged.

- [ ] Write regression tests first: rows/actions match all five descriptors,
  each generated action opens its own target (closure capture), custom demo
  descriptor plus separately registered loader works without changing Entities,
  unknown type/unresolved browser/missing catalog/map fail loudly. Test view
  alphabetical ordering, click/submission and two-view teardown. Catalog fixture:

```fennel
(local types (Builtins.entity-types))
(table.insert types {:id "demo" :label "demo" :action-name "Demo Entities"
                     :icon "code" :browser-key "demo-entity-list"})
(local catalog (EntityTypeCatalog {:types types}))
```

- [ ] Add app composition tests with save/reset/restore of registry, handles and
  catalog using pcall cleanup. Inject second-registration failure and assert
  earlier registration rollback and no candidate publication; test both nil and
  prior catalog. Test retry, reuse, explicit conflicting replacement rejection
  before registration, runtime install/uninstall identity stability and app.drop
  releasing reference. Start target collection is lazy; activating Entities uses
  injected catalog. Restored topology includes Entities/code-list and correct stores.
- [ ] Compile tests, constraints, focused Entities/built-in suites for RED.
- [ ] Compose catalog once in ensure-built-in-graph-extensions!: explicit option,
  existing app reference, or new default; validate catalog methods. Pass through
  resolved extension options. Publish catalog/handles only after Builtins.register!
  returns. Existing installed handles reject a different explicit catalog. Clear
  app catalog after teardown, not per runtime. Do not modify extension-registry.
- [ ] Require injected catalog in Entities loader/node. Remove browser imports
  and branches, build rows/actions solely from catalog. Use map key resolution
  as in Task 2 with explicit browser-key errors. Keep types signal contract.

```fennel
(fn collect-types [self]
  (icollect [_ descriptor (ipairs (self.entity-type-catalog:list-types))]
    [descriptor.id descriptor.label]))
(fn make-type-action [descriptor]
  (local id descriptor.id)
  {:name descriptor.action-name :icon descriptor.icon
   :fn (fn [_button _event] (self:add-type-node id))})
```

- [ ] Replace only Start's directly constructed Entities target with canonical
  string key and handle strings via map resolution. Simplify Entities view to
  required context plus default SearchView builder and one submitted handler;
  disconnect both callbacks on drop. No hidden discovery or no-op fallbacks.
- [ ] Add isolated default catalog in shared built-in test options and migrate
  four direct Entities construction tests. Save/restore catalog with handles in
  affected app tests. Exercise all built-in browser store identities and custom
  type in two maps. Refresh code-list adapter via existing APIs; old subscriptions
  disappear and replacement owns one per signal while topology/catalog remain.
- [ ] Document descriptor fields, startup composition example, immutable lifetime,
  distinct loader registration, store/map ownership, errors and exclusions.
- [ ] Compile (`make fennel-check`), constraints, then focused suites: catalog,
  code-list, Entities, built-in extensions, runtime plumbing, main events,
  string/link/list/dict/code entities, notebooks, workflow graph, hosted app
  launcher, graph extension registry. Use `tests.<suite>:main` commands. Diff check,
  independent review, then checkpoint `feat(lua): integrate catalog-driven entity browsing`.

## Final gate

### Task 3 constraint remediation addendum

The native constraint gate reproduced nine diagnostics after Task 3 wiring:
Main's accepted existing module measure grew 2327 to 2348, Start's unchanged
fallback fingerprint moved 17 to 16, and five eliminated Entities violations
left dead baseline entries. Debug advisor confirmed a narrow remediation.

Additional Task 3 files: create
`assets/lua/graph/extensions/builtins/composition.fnl`; modify
`assets/lua/constraints/baseline-data.fnl`. Do not add allowances or change rules.

- [ ] Extract the existing built-in option resolution and catalog composition
  from Main to the focused helper, receiving app and its registry resolver
  explicitly. Preserve Main's exported ensure API and graph registry ownership:

```fennel
(fn ensure-built-in-graph-extensions! [opts]
  ((. (require :graph/extensions/builtins/composition) :ensure!)
    app opts ensure-graph-extension-registry!))
```

- [ ] Preserve catalog validation before registry/store work, lazy imports,
  identity/reuse/conflicting replacement, existing rollback and publication;
  no circular Main import from the helper. Keep app teardown in Main.
- [ ] Delete exactly five stale Entities baseline entries; relocate Start's
  unchanged fingerprint; tighten Main's existing measure to the observed reduced
  value strictly below 2327. No new baseline allowance, no unrelated compaction.
- [ ] Rerun compile, repository constraints and Task 3 focused behavioral tests.
  Include full helper/baseline changes in independent Task 3 review. New
  diagnostics or scope expansion require renewed diagnosis.

Fetch origin via capability wrapper; evaluate against current origin/main and
safe-merge if needed, routing conflict/fix changes through implementer/reviewer.
From reviewed committed clean tree run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" make test
```

The real-map/UI integration test supplies Start → Entities → Code → existing
entity smoke coverage; no snapshot change is required unless rendering regresses.
Unexpected failures require systematic diagnosis and reviewed fixes, not handoff
as success. Push/create PR through dedicated wrappers only after green checks;
enable auto-merge and poll merge queue until merged, or report concrete human gate.
