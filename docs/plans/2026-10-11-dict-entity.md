# Dict Entity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persistent keyed `dict` entities, graph loaders/nodes, entity-browser access, and simple graph UI views parallel to existing list entities.

**Architecture:** Implement `dict` as a first-class entity store under `assets/lua/entities/` with JSON persistence and explicit item mutation APIs. Graph adapters mirror the list-entity pattern but use string-keyed item maps, preserve unresolved references, and materialize edges only when referenced nodes can be resolved. UI views stay intentionally simple: edit the dict name, inspect key/value rows, set or rename items, focus referenced nodes, and delete the entity.

**Tech Stack:** Space Fennel, JSON persistence via `json-utils`, graph key loaders, graph node/view widgets (`Input`, `Button`, `ListView`, `SearchView`, `Flex`), Space Fennel tests through `./build/space`.

## Global Constraints

- Accepted primitive set: `string`, `code`, `list`, `dict`, `link`, `identity`.
- A dict entity is a persistent keyed collection whose values are graph-addressable keys.
- It does not store inline scalars or tagged value payloads.
- Scalar-like values are represented by referenced scalar entities, normally `string-entity` or `code-entity`; nested ordered or keyed structures are represented by referenced `list-entity` or `dict-entity` values.
- Directory: `{user-data-dir}/entities/dict/`
- Format: one JSON file per entity, named `<uuid>.json`
- Required fields: `id`, `name`, `items`, `created-at`, `updated-at`
- Store API: `:get-entity id`, `:create-entity opts`, `:update-entity id updates`, `:delete-entity id`, `:list-entities`, `:get-item id item-key`, `:set-item id item-key node-key`, `:remove-item id item-key`, `:rename-item id old-key new-key`
- Signals: `dict-entity-created`, `dict-entity-updated`, `dict-entity-deleted`, `dict-entity-items-changed`
- Item keys are stringified and empty keys are invalid for mutating item operations; callers receive an explicit error rather than a successful no-op.
- Item values are stringified graph keys and empty values are invalid for mutating item operations; callers receive an explicit error rather than a successful no-op.
- `:items` is always a table keyed by item key, not an array.
- Updating unchanged values is a no-op and should avoid unnecessary update/item signals where practical, matching the no-op behavior in list entity item operations.
- Key scheme: `dict-entity:<id>`
- Key scheme: `dict-entity-list`
- The built-in graph entity extension should register loaders for both schemes.
- The root `EntitiesNode` should expose a `dict` type next to `string`, `link`, and `list`.
- `DictEntityListNode` responsibilities: List all dict entities sorted by `updated-at` descending; show labels with item counts; create new dict entities; refresh on create/update/delete/items-changed signals.
- The first version does not need a schema system, inline scalar editor, table editor, source-backed claims, or provenance model.
- Do not silently convert invalid required state into successful no-ops when the caller has supplied malformed required data.
- Surface persistence failures that would lose data.
- Keep graph adapters tolerant of references that are not currently visible or loadable; unresolved references remain stored as keys and may resolve later.

---

## File Structure

- Create: `assets/lua/entities/dict.fnl` — `DictEntityStore` factory, JSON persistence, normalization, CRUD, item mutation, signals, default store.
- Create: `assets/lua/graph/nodes/dict-entity.fnl` — individual graph node adapter for `dict-entity:<id>`, item edge materialization, identity wrapping for graph-facing set flows.
- Create: `assets/lua/graph/nodes/dict-entity-list.fnl` — browser/list node for all dict entities.
- Create: `assets/lua/graph/view/views/dict-entity.fnl` — simple dict editor view.
- Create: `assets/lua/graph/view/views/dict-entity-list.fnl` — searchable dict entity browser view.
- Create: `assets/lua/tests/test-dict-entities.fnl` — focused store, graph, loader, root browser, and view-load tests.
- Modify: `assets/lua/tests/fast.fnl` — include `:tests.test-dict-entities`.
- Modify: `assets/lua/graph/extensions/builtins/entities.fnl` — require dict node modules, require `:dict-store`, register `dict-entity` and `dict-entity-list`, add schemes.
- Modify: `assets/lua/graph/nodes/entities.fnl` — add `:dict` type, action, and `DictEntityListNode` branch.
- Modify: `assets/lua/main.fnl` — provide `dict-store` in built-in graph extension options.
- Modify: `assets/lua/tests/test-builtin-graph-extensions.fnl` — expected scheme coverage and test options include dict store.
- Create: `docs/dev/notes/dict-entities.md` — focused dev note for dict semantics, storage, graph keys, UI.
- Modify: `docs/dev/notes/entity-store.md` — update entity count and add dict store summary.

## Invariants and Compatibility Requirements

- Do not change existing list entity behavior or APIs.
- Do not add legacy aliases or compatibility shims; use only canonical dict names.
- Store item values exactly as graph key strings; identity wrapping happens in `DictEntityNode:set-item`, not in the store.
- Reject `nil` and empty required item keys/values in mutating item APIs with explicit `error`.
- Preserve unresolved references in storage; graph nodes may omit edges for unresolved references but must not delete stored items because a target is absent.
- `rename-item` must error if `new-key` already exists and differs from `old-key`, to avoid silent overwrite/data loss.
- Use `local`, not `let`; avoid copying the large single-function structure debt from `entities/list.fnl` by splitting helper functions.
- Use `JsonUtils.write-json!` for persistence.
- New Fennel files must pass constraints without adding baseline entries unless a reviewer explicitly approves a justified baseline update.

## Observable Acceptance Criteria

- A dict entity persists as `{id, name, items, created-at, updated-at}` under `{base-dir}/entities/dict/<id>.json`.
- Reloading a fresh `DictEntityStore` from the same base dir returns the same dict entity and string-keyed `items` table.
- `set-item`, `remove-item`, and `rename-item` update `updated-at`, persist JSON, emit `dict-entity-updated` and `dict-entity-items-changed` only when the item map actually changes.
- Invalid empty or missing item keys/values raise explicit errors.
- `dict-entity:<id>` and `dict-entity-list` load through built-in graph extension loaders.
- `EntitiesNode:collect-types` includes `[:dict "dict"]`, and `add-type-node :dict` opens a dict entity list node.
- `DictEntityNode` exposes `get-entity`, `update-name`, `get-item`, `set-item`, `remove-item`, `rename-item`, and `delete-entity`.
- `DictEntityListNode:collect-items` returns all dict entities sorted by `updated-at` descending with labels containing item counts.
- Dict UI view modules load and are assigned as the node views.
- `docs/dev/notes/dict-entities.md` documents the new primitive.
- PR CI is the full integration gate.

## Validation Ladder

Runtime/freshness prerequisite before direct `./build/space` commands when the binary may be missing or stale:

```bash
make build
```

Focused checks during implementation, in this order:

1. Compile check first:
   ```bash
   for f in assets/lua/entities/dict.fnl \
            assets/lua/graph/nodes/dict-entity.fnl \
            assets/lua/graph/nodes/dict-entity-list.fnl \
            assets/lua/graph/view/views/dict-entity.fnl \
            assets/lua/graph/view/views/dict-entity-list.fnl \
            assets/lua/tests/test-dict-entities.fnl; do
     ./build/space -m tools.fennel-check:main -- --target files --file "$f"
   done
   ```
2. Constraints second:
   ```bash
   make constraints
   ```
3. Focused Fennel tests third:
   ```bash
   SKIP_KEYRING_TESTS=1 \
   XDG_DATA_HOME=/tmp/space/tests/xdg-data \
   SPACE_DISABLE_AUDIO=1 \
   SPACE_ASSETS_PATH=$(pwd)/assets \
   FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
   FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
   ./build/space -m tests.test-dict-entities:main
   ```
4. Focused loader regression after built-in extension edits:
   ```bash
   SKIP_KEYRING_TESTS=1 \
   XDG_DATA_HOME=/tmp/space/tests/xdg-data \
   SPACE_DISABLE_AUDIO=1 \
   SPACE_ASSETS_PATH=$(pwd)/assets \
   FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
   FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
   ./build/space -m tests.test-builtin-graph-extensions:main
   ```

Broader final local validation is justified because this touches built-in graph loading, `main.fnl` runtime extension options, and the fast suite registration:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

If any Fennel delimiter or parse error appears, inspect the nearest enclosing form around the reported location first, simplify deeply nested logic into helper functions, rerun the touched-file compile check, then rerun constraints and focused tests. Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.

## Out of Scope

- Inline scalar values inside dict entities.
- Typed value payloads such as `{:type "string" :value "Alice"}`.
- Schema/type systems for dict item names.
- Source-backed claim/provenance/confidence entities.
- General table/row UI; tables can be composed later from list/dict entities.
- Menu-manager or context-menu create actions for dict entities.
- E2E snapshot creation unless a reviewer finds the simple widget composition insufficiently covered by focused tests.

---

### Task 1: Dict Store and Store Tests

**Files:**
- Create: `assets/lua/entities/dict.fnl`
- Create: `assets/lua/tests/test-dict-entities.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `Signal`, `appdirs.user-data-dir`, `fs`, `uuid`, `json`, `json-utils.write-json!`
- Produces:
  - `DictEntityStore.DictEntityStore(opts: table?) -> store`
  - `DictEntityStore.get-default(opts: table?) -> store`
  - `store:get-entity(id: string) -> table|nil`
  - `store:create-entity(opts: table?) -> table`
  - `store:update-entity(id: string, updates: table?) -> table|nil`
  - `store:delete-entity(id: string) -> table|nil`
  - `store:list-entities() -> table[]`
  - `store:get-item(id: string, item-key: any) -> string|nil`
  - `store:set-item(id: string, item-key: any, node-key: any) -> table|nil`
  - `store:remove-item(id: string, item-key: any) -> table|nil`
  - `store:rename-item(id: string, old-key: any, new-key: any) -> table|nil`
  - Signals on store table: `dict-entity-created`, `dict-entity-updated`, `dict-entity-deleted`, `dict-entity-items-changed`

- [ ] **Step 1: Write failing store tests in `assets/lua/tests/test-dict-entities.fnl`**

  Start the file with the same temp-dir style as `test-list-entities.fnl`, but use a dict-specific root:

  ```fennel
  (local fs (require :fs))

  (local tests [])
  (var temp-counter 0)
  (local temp-root (fs.join-path "/tmp/space/tests" "dict-entities"))

  (fn make-temp-dir []
    (set temp-counter (+ temp-counter 1))
    (fs.join-path temp-root (.. "entities-" (os.time) "-" temp-counter)))

  (fn with-temp-dir [f]
    (local dir (make-temp-dir))
    (when (fs.exists dir)
      (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result) (pcall f dir))
    (fs.remove-all dir)
    (if ok
        result
        (error result)))

  (fn with-temp-store [f]
    (with-temp-dir
      (fn [root]
        (local DictEntityStore (require :entities/dict))
        (local store (DictEntityStore.DictEntityStore {:base-dir root}))
        (f store root))))
  ```

  Add store tests with these exact behaviors:

  ```fennel
  (fn dict-entity-store-creates-entities []
    (with-temp-store
      (fn [store _root]
        (local entity (store:create-entity {:name "Alice profile"
                                            :items {"name" "string-entity:name"
                                                    "manager" "identity:bob"}}))
        (assert entity "entity should be created")
        (assert entity.id "entity should have id")
        (assert (= entity.name "Alice profile") "entity should keep name")
        (assert (= (. entity.items "name") "string-entity:name") "items should be keyed table")
        (assert (= (. entity.items "manager") "identity:bob") "items should store graph keys")
        (assert (= (length entity.items) 0) "dict items must not be stored as an array")
        (assert entity.created-at "entity should have created-at")
        (assert entity.updated-at "entity should have updated-at"))))

  (fn dict-entity-store-persists-and-reloads-json []
    (with-temp-store
      (fn [store root]
        (local entity (store:create-entity {:id "profile"
                                            :name "Profile"
                                            :items {"role" "string-entity:role"}}))
        (local DictEntityStore (require :entities/dict))
        (local reloaded-store (DictEntityStore.DictEntityStore {:base-dir root}))
        (local reloaded (reloaded-store:get-entity entity.id))
        (assert reloaded "reloaded entity should exist")
        (assert (= reloaded.id "profile") "id should persist")
        (assert (= reloaded.name "Profile") "name should persist")
        (assert (= (. reloaded.items "role") "string-entity:role") "dict item should persist"))))
  ```

  Add item mutation and signal tests:

  ```fennel
  (fn dict-entity-store-set-get-remove-rename-items []
    (with-temp-store
      (fn [store _root]
        (local entity (store:create-entity {:name "x"}))
        (store:set-item entity.id "name" "string-entity:a")
        (assert (= (store:get-item entity.id "name") "string-entity:a") "set-item should store value")
        (store:rename-item entity.id "name" "display-name")
        (assert (= (store:get-item entity.id "name") nil) "rename should remove old key")
        (assert (= (store:get-item entity.id "display-name") "string-entity:a") "rename should keep value")
        (store:remove-item entity.id "display-name")
        (assert (= (store:get-item entity.id "display-name") nil) "remove should delete item"))))

  (fn dict-entity-store-rejects-invalid-item-mutations []
    (with-temp-store
      (fn [store _root]
        (local entity (store:create-entity {}))
        (local (ok-empty-key err-empty-key) (pcall store.set-item store entity.id "" "node-a"))
        (assert (not ok-empty-key) "empty item key should error")
        (assert (string.find (tostring err-empty-key) "item key" 1 true) "empty key error should mention item key")
        (local (ok-empty-value err-empty-value) (pcall store.set-item store entity.id "k" ""))
        (assert (not ok-empty-value) "empty item value should error")
        (assert (string.find (tostring err-empty-value) "item value" 1 true) "empty value error should mention item value")
        (store:set-item entity.id "a" "node-a")
        (store:set-item entity.id "b" "node-b")
        (local (ok-collision err-collision) (pcall store.rename-item store entity.id "a" "b"))
        (assert (not ok-collision) "rename collision should error")
        (assert (string.find (tostring err-collision) "already exists" 1 true) "collision error should mention existing key"))))
  ```

  Add unchanged/no-op signal coverage:

  ```fennel
  (fn dict-entity-store-skips-unchanged-item-signals []
    (with-temp-store
      (fn [store _root]
        (local entity (store:create-entity {:items {"role" "string-entity:role"}}))
        (var updated-count 0)
        (var items-count 0)
        (store.dict-entity-updated:connect (fn [_] (set updated-count (+ updated-count 1))))
        (store.dict-entity-items-changed:connect (fn [_] (set items-count (+ items-count 1))))
        (store:set-item entity.id "role" "string-entity:role")
        (store:remove-item entity.id "missing")
        (store:rename-item entity.id "role" "role")
        (assert (= updated-count 0) "unchanged item operations should not emit updated")
        (assert (= items-count 0) "unchanged item operations should not emit items-changed"))))
  ```

  End the file with test registration and module export:

  ```fennel
  (table.insert tests {:name "dict entity store creates entities"
                       :fn dict-entity-store-creates-entities})
  (table.insert tests {:name "dict entity store persists and reloads json"
                       :fn dict-entity-store-persists-and-reloads-json})
  (table.insert tests {:name "dict entity store set get remove rename items"
                       :fn dict-entity-store-set-get-remove-rename-items})
  (table.insert tests {:name "dict entity store rejects invalid item mutations"
                       :fn dict-entity-store-rejects-invalid-item-mutations})
  (table.insert tests {:name "dict entity store skips unchanged item signals"
                       :fn dict-entity-store-skips-unchanged-item-signals})

  (local main
    (fn []
      (local runner (require :tests/runner))
      (runner.run-tests {:name "dict-entities"
                         :tests tests})))

  {:name "dict-entities"
   :tests tests
   :main main}
  ```

- [ ] **Step 2: Register the focused test module in `assets/lua/tests/fast.fnl`**

  Insert `:tests.test-dict-entities` immediately after `:tests.test-list-entities`.

- [ ] **Step 3: Run the store tests and verify they fail because `entities/dict` does not exist**

  ```bash
  make build
  SKIP_KEYRING_TESTS=1 \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-dict-entities:main
  ```

  Expected: FAIL with a missing `entities/dict` module or missing `DictEntityStore`.

- [ ] **Step 4: Implement `assets/lua/entities/dict.fnl`**

  Use small helpers, not one large store body. Required helper signatures:

  - `(fn ensure-dir [path]) -> path`
  - `(fn normalize-items [items]) -> string-keyed table`
  - `(fn items-equal? [a b]) -> boolean`
  - `(fn item-count [items]) -> integer`
  - `(fn required-item-key [value context]) -> non-empty string or error`
  - `(fn required-item-value [value context]) -> non-empty string or error`
  - `(fn DictEntityStore [opts]) -> store table`
  - `(fn get-default [opts]) -> store table`

  Required exported shape:

  ```fennel
  {:DictEntityStore DictEntityStore
   :get-default get-default}
  ```

  Required mutation behavior:
  - `normalize-items` returns a string-keyed table and ignores empty keys/values only when reading persisted or create/update bulk `:items` data.
  - `required-item-key` and `required-item-value` reject `nil` and empty strings with `error`.
  - `set-item` emits `dict-entity-updated` and `dict-entity-items-changed` only when the stored value changes.
  - `remove-item` is a no-op for missing keys.
  - `rename-item` is a no-op when old and new keys stringify to the same key.
  - `rename-item` errors when `new-key` already exists and is not `old-key`.
  - `update-entity` emits `dict-entity-items-changed` if normalized `:items` actually changes.

- [ ] **Step 5: Run focused compile, constraints, and tests**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/entities/dict.fnl
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-dict-entities.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-dict-entities:main
  ```

  Expected: PASS.

- [ ] **Step 6: Commit Task 1**

  ```bash
  git add assets/lua/entities/dict.fnl assets/lua/tests/test-dict-entities.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(assets): add dict entity store"
  ```

---

### Task 2: Graph Nodes, Loaders, Root Browser, and Tests

**Files:**
- Create: `assets/lua/graph/nodes/dict-entity.fnl`
- Create: `assets/lua/graph/nodes/dict-entity-list.fnl`
- Modify: `assets/lua/graph/extensions/builtins/entities.fnl`
- Modify: `assets/lua/graph/nodes/entities.fnl`
- Modify: `assets/lua/main.fnl`
- Modify: `assets/lua/tests/test-dict-entities.fnl`
- Modify: `assets/lua/tests/test-builtin-graph-extensions.fnl`

**Interfaces:**
- Consumes:
  - `DictEntityStore.DictEntityStore`
  - `IdentityStore.IdentityStore`
  - `Graph`, `GraphNode`, `GraphEdge`
  - `KeyLoaderUtils.key-prefix`, `KeyLoaderUtils.extract-id`
- Produces:
  - `DictEntityNode(opts: {:entity-id string :store table? :identity-store table?}) -> GraphNode`
  - `DictEntityNode.register-loader(graph: table, opts: table?) -> any`
  - `DictEntityListNode(opts: {:store table? :identity-store table?}) -> GraphNode`
  - Built-in loaders for `dict-entity:<id>` and `dict-entity-list`
  - `EntitiesNode` type key `:dict`

- [ ] **Step 1: Add failing graph/node tests to `assets/lua/tests/test-dict-entities.fnl`**

  Add node property and label tests:

  ```fennel
  (fn dict-entity-node-creates-with-correct-properties []
    (with-temp-store
      (fn [store _root]
        (local entity (store:create-entity {:name "Profile"}))
        (local {:DictEntityNode DictEntityNode} (require :graph/nodes/dict-entity))
        (local node (DictEntityNode {:entity-id entity.id :store store}))
        (assert (= node.key (.. "dict-entity:" entity.id)) "key should be prefixed entity id")
        (assert (= node.label "Profile") "named dict should label by name")
        (assert (= node.compact-label "Profile") "named dict should use compact label")
        (assert node.items-changed "should have items-changed signal")
        (assert node.changed "should have changed signal")
        (assert node.entity-deleted "should have entity-deleted signal")
        (assert node.get-entity "should expose get-entity")
        (assert node.update-name "should expose update-name")
        (assert node.get-item "should expose get-item")
        (assert node.set-item "should expose set-item")
        (assert node.remove-item "should expose remove-item")
        (assert node.rename-item "should expose rename-item")
        (assert node.delete-entity "should expose delete-entity")
        (node:drop))))
  ```

  Add edge materialization and unresolved-reference tests:

  ```fennel
  (fn dict-entity-node-adds-edges-for-resolved-values []
    (with-temp-store
      (fn [store _root]
        (local Graph (require :graph/init))
        (local graph (Graph {:with-start false}))
        (local a (Graph.GraphNode {:key "node-a"}))
        (local b (Graph.GraphNode {:key "node-b"}))
        (graph:add-node a {})
        (graph:add-node b {})
        (local entity (store:create-entity {:items {"first" "node-a"
                                                    "second" "node-b"
                                                    "missing" "node-missing"}}))
        (local {:DictEntityNode DictEntityNode} (require :graph/nodes/dict-entity))
        (local node (DictEntityNode {:entity-id entity.id :store store}))
        (graph:add-node node {})
        (assert (= (graph:edge-count) 2) "dict entity node should edge only resolved values")
        (assert (= (. (store:get-entity entity.id) :items "missing") "node-missing")
                "unresolved reference should remain stored")
        (graph:drop))))
  ```

  Add identity wrapping test for graph-facing `set-item`:

  ```fennel
  (fn dict-entity-node-set-item-wraps-non-identity-key []
    (with-temp-store
      (fn [store root]
        (local Graph (require :graph/init))
        (local IdentityStore (require :entities/identity))
        (local identity-store (IdentityStore.IdentityStore {:base-dir (fs.join-path root "identity")}))
        (local entity (store:create-entity {:name "x"}))
        (local {:DictEntityNode DictEntityNode} (require :graph/nodes/dict-entity))
        (local graph (Graph {:with-start false :identity-store identity-store}))
        (local node (DictEntityNode {:entity-id entity.id
                                     :store store
                                     :identity-store identity-store}))
        (graph:add-node node {})
        (node:set-item "manager" "node-a")
        (local stored-key (. (store:get-entity entity.id) :items "manager"))
        (assert (= (string.sub stored-key 1 9) "identity:")
                "dict graph node should wrap non-identity values")
        (local identity-id (string.sub stored-key 10))
        (local identity-entity (identity-store:get-entity identity-id))
        (assert identity-entity "identity should be persisted")
        (assert (= identity-entity.target-key "node-a") "identity target should match source key")
        (graph:drop))))
  ```

  Add list-node, loader, and root-browser tests:

  ```fennel
  (fn dict-entity-list-node-collects-items-with-counts []
    (with-temp-store
      (fn [store _root]
        (store:create-entity {:name "old" :updated-at 10 :items {"a" "node-a"}})
        (store:create-entity {:name "new" :updated-at 20 :items {"a" "node-a" "b" "node-b"}})
        (local DictEntityListNode (require :graph/nodes/dict-entity-list))
        (local node (DictEntityListNode {:store store}))
        (local items (node:collect-items))
        (assert (= (length items) 2) "should collect two dicts")
        (assert (string.find (. items 1 2) "2 items" 1 true) "newer label should include item count")
        (node:drop))))

  (fn entities-node-includes-dict-type []
    (local EntitiesNode (require :graph/nodes/entities))
    (local node (EntitiesNode {}))
    (local types (node:collect-types))
    (var found false)
    (each [_ t (ipairs types)]
      (when (= (. t 1) :dict)
        (set found true)))
    (assert found "entities node should include dict type"))

  (fn built-in-loaders-resolve-dict-entity-keys []
    (with-temp-store
      (fn [dict-store root]
        (local Graph (require :graph/init))
        (local graph (Graph {:with-start false}))
        (local IdentityStore (require :entities/identity))
        (local identity-store (IdentityStore.IdentityStore {:base-dir (fs.join-path root "identity")}))
        (local entity (dict-store:create-entity {:name "x"}))
        (local DictNodeModule (require :graph/nodes/dict-entity))
        (DictNodeModule.register-loader graph {:store dict-store :identity-store identity-store})
        (assert (graph:load-by-key (.. "dict-entity:" entity.id)) "dict entity key should load")
        (graph:drop))))
  ```

- [ ] **Step 2: Run graph tests and verify they fail on missing graph modules/loaders**

  ```bash
  SKIP_KEYRING_TESTS=1 \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-dict-entities:main
  ```

  Expected: FAIL with missing `graph/nodes/dict-entity` or `graph/nodes/dict-entity-list`.

- [ ] **Step 3: Implement `assets/lua/graph/nodes/dict-entity.fnl`**

  Mirror `list-entity.fnl` structure where it fits, but keep unresolved references stored and avoid direct removal on missing targets.

  Required constants and helper signatures:
  ```fennel
  (local SCHEME "dict-entity")
  (local KEY_PREFIX (KeyLoaderUtils.key-prefix SCHEME))
  (local IDENTITY_KEY_PREFIX (KeyLoaderUtils.key-prefix "identity"))
  ```

  - `(fn item-values [entity]) -> array of graph key strings from entity.items`
  - `(fn item-value-set [entity]) -> table keyed by graph key string`
  - `(fn resolve-item-target [self item-key]) -> GraphNode|nil`
  - `(fn remove-edge-by-key [graph key]) -> nil`
  - `(fn make-label [entity]) -> string`
  - `(fn make-compact-label [entity]) -> string|false`

  Required node methods:
  ```fennel
  :refresh-label
  :get-entity
  :get-item
  :set-item
  :remove-item
  :rename-item
  :delete-entity
  :add-item-nodes
  :added
  :mount
  :drop
  ```

  Required behavior:
  - `node.key` is `"dict-entity:" .. entity-id`.
  - `set-item` wraps non-identity values through `graph:ensure-identity-key` when available, else through `identity-store:find-by-target-key` / `identity-store:create-entity`.
  - `add-item-nodes` iterates `(pairs current.items)`, resolves direct keys or identity target keys, and adds edges only to resolved nodes.
  - Track `dict-item-edge-keys` and remove stale edges after item changes.
  - Listen to `dict-entity-updated`, `dict-entity-deleted`, `dict-entity-items-changed`.
  - On graph `node-added` and identity updates, refresh edges because previously unresolved values may now resolve.
  - Do not delete stored dict items when graph nodes disappear.

- [ ] **Step 4: Implement `assets/lua/graph/nodes/dict-entity-list.fnl`**

  Required behavior:
  - `node.key` is `"dict-entity-list"`.
  - `node.label` is `"dict entities"`.
  - Use a distinct but nearby color from list cyan, for example teal:
    ```fennel
    (local TEAL (glm.vec4 0.0 0.55 0.45 1))
    (local TEAL_ACCENT (glm.vec4 0.05 0.65 0.55 1))
    ```
  - `collect-items` returns `[entity label]` rows sorted by store order.
  - Count item keys with `pairs`, not `length`.
  - `create-entity` delegates to `store:create-entity`, then emits items.
  - Refresh on `dict-entity-created`, `dict-entity-updated`, `dict-entity-deleted`, `dict-entity-items-changed`.
  - `add-entity-node` creates `DictEntityNode` and connects it from the list node with `GraphEdge`.

- [ ] **Step 5: Update built-in graph loaders in `assets/lua/graph/extensions/builtins/entities.fnl`**

  Add requires:
  ```fennel
  (local DictEntityNodeModule (require :graph/nodes/dict-entity))
  (local DictEntityListNode (require :graph/nodes/dict-entity-list))
  ```

  Add schemes to `entity-schemes`:
  ```fennel
  "dict-entity" "dict-entity-list"
  ```

  Require `dict-store`:
  ```fennel
  (local dict-store (assert options.dict-store "builtin-graph-entities requires :dict-store"))
  ```

  Add factories and registrations:
  ```fennel
  (fn make-dict-entity [entity-id]
    (DictEntityNodeModule.DictEntityNode {:entity-id entity-id
                                          :store dict-store
                                          :identity-store identity-store}))
  (fn make-dict-entity-list [] (DictEntityListNode {:store dict-store
                                                    :identity-store identity-store}))

  (add! (register-store-node-loader graph ctx "dict-entity" dict-store
      make-dict-entity))
  (add! (graph:register-key-loader "dict-entity-list"
      (Common.exact-key-loader "dict-entity-list"
        make-dict-entity-list)
      (loader-opts ctx)))
  ```

- [ ] **Step 6: Update runtime built-in extension options in `assets/lua/main.fnl`**

  In `built-in-graph-extension-options`, require `entities/dict` and provide `:dict-store`:

  Add `(local DictEntityStore (require :entities/dict))` next to the other
  entity store requires inside `built-in-graph-extension-options`, then add this
  option entry next to `:list-store` and `:link-store`:

  ```fennel
  :dict-store (or options.dict-store app.dict-store
                  (DictEntityStore.get-default {:base-dir data-dir}))
  ```

- [ ] **Step 7: Update root entity browser in `assets/lua/graph/nodes/entities.fnl`**

  Add require:
  ```fennel
  (local DictEntityListNode (require :graph/nodes/dict-entity-list))
  ```

  Add type:
  ```fennel
  (table.insert produced [:dict "dict"])
  ```

  Add branch:
  ```fennel
  (= type-key :dict)
  (do
    (local list-node (DictEntityListNode {}))
    (graph:add-edge (GraphEdge {:source self
                                :target list-node})))
  ```

  Add action using a validated icon from `assets/material-design-icons/icons.txt`:
  ```fennel
  {:name "Dict Entities"
   :icon "data_object"
   :fn (fn [_button _event]
         (node:add-type-node :dict))}
  ```

- [ ] **Step 8: Update `assets/lua/tests/test-builtin-graph-extensions.fnl`**

  Add `"dict-entity"` and `"dict-entity-list"` to `expected-schemes`.

  In `create-test-built-in-options`, require `DictEntityStore` next to the other
  entity store requires and add this option entry next to the existing store
  entries:

  ```fennel
  :dict-store (DictEntityStore.DictEntityStore {:base-dir base-dir})
  ```

  Add representative loader assertions after existing entity-list assertions:
  ```fennel
  (assert-loads graph "dict-entity-list")
  ```

- [ ] **Step 9: Run focused compile, constraints, and tests**

  ```bash
  for f in assets/lua/graph/nodes/dict-entity.fnl \
           assets/lua/graph/nodes/dict-entity-list.fnl \
           assets/lua/graph/extensions/builtins/entities.fnl \
           assets/lua/graph/nodes/entities.fnl \
           assets/lua/main.fnl \
           assets/lua/tests/test-dict-entities.fnl \
           assets/lua/tests/test-builtin-graph-extensions.fnl; do
    ./build/space -m tools.fennel-check:main -- --target files --file "$f"
  done

  make constraints

  SKIP_KEYRING_TESTS=1 \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-dict-entities:main

  SKIP_KEYRING_TESTS=1 \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-builtin-graph-extensions:main
  ```

  Expected: PASS.

- [ ] **Step 10: Commit Task 2**

  ```bash
  git add assets/lua/graph/nodes/dict-entity.fnl \
          assets/lua/graph/nodes/dict-entity-list.fnl \
          assets/lua/graph/extensions/builtins/entities.fnl \
          assets/lua/graph/nodes/entities.fnl \
          assets/lua/main.fnl \
          assets/lua/tests/test-dict-entities.fnl \
          assets/lua/tests/test-builtin-graph-extensions.fnl
  git commit -m "feat(assets): add dict entity graph nodes"
  ```

---

### Task 3: Dict Entity Views and View Tests

**Files:**
- Create: `assets/lua/graph/view/views/dict-entity.fnl`
- Create: `assets/lua/graph/view/views/dict-entity-list.fnl`
- Modify: `assets/lua/tests/test-dict-entities.fnl`

**Interfaces:**
- Consumes:
  - `DictEntityNode.view`
  - `DictEntityListNode.view`
  - Node methods from Task 2
  - Widgets: `Input`, `Button`, `ListView`, `SearchView`, `Text`, `Flex`, `FlexChild`
- Produces:
  - `DictEntityNodeView(node, opts?) -> build(ctx) -> view`
  - `DictEntityListNodeView(node, opts?) -> build(ctx) -> view`

- [ ] **Step 1: Add failing view-load tests**

  Add to `assets/lua/tests/test-dict-entities.fnl`:

  ```fennel
  (fn dict-entity-node-view-loads []
    (local DictEntityNodeView (require :graph/view/views/dict-entity))
    (assert DictEntityNodeView "DictEntityNodeView should load")
    (assert (= (type DictEntityNodeView) "function") "DictEntityNodeView should be a function"))

  (fn dict-entity-list-node-view-loads []
    (local DictEntityListNodeView (require :graph/view/views/dict-entity-list))
    (assert DictEntityListNodeView "DictEntityListNodeView should load")
    (assert (= (type DictEntityListNodeView) "function") "DictEntityListNodeView should be a function"))
  ```

  Register both tests at the end of the test file.

- [ ] **Step 2: Run tests and verify they fail on missing view modules**

  ```bash
  SKIP_KEYRING_TESTS=1 \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-dict-entities:main
  ```

  Expected: FAIL with missing `graph/view/views/dict-entity`.

- [ ] **Step 3: Implement `assets/lua/graph/view/views/dict-entity.fnl`**

  Required top-level shape: `DictEntityNodeView` returns a build closure. The
  closure binds `build-ctx` from `ctx`, `options.ctx`, or `target.graph.ctx`,
  asserts with `"DictEntityNodeView requires a build context"`, constructs child
  widgets with that context, assigns `view.layout`, implements `view.drop`, and
  returns `view`. The module returns `DictEntityNodeView` as its final form.

  Required UI:
  - Name input calling `target:update-name`.
  - Item count label named `"dict-entity-items-label"`.
  - Scrollable `ListView` named `"dict-entity-items"`.
  - Each row shows:
    - item key input initialized to the current key;
    - referenced graph key button that focuses/opens the value;
    - value input initialized to the current graph key;
    - save button calling `target:rename-item` when key changed and `target:set-item` with the final key/value;
    - remove button calling `target:remove-item`.
  - Add/update row:
    - item key input;
    - graph key input;
    - `"Use Selected"` button that sets the graph key input to the first selected node key from `app.graph-view.selection.selected-nodes`;
    - `"Set Item"` button calling `target:set-item`.
  - Delete dict button calling `target:delete-entity`.

  Required helper signatures:

  - `(fn item-count [items]) -> integer`
  - `(fn sorted-item-rows [items]) -> array of {:key string :value string}`
  - `(fn maybe-focus-node [node-key]) -> nil`
  - `(fn first-selected-node-key []) -> string|nil`

  Sort item rows lexicographically by item key so the UI is stable despite Lua table iteration order.

- [ ] **Step 4: Implement `assets/lua/graph/view/views/dict-entity-list.fnl`**

  Mirror `list-entity-list.fnl`:
  - Build context assert message: `"DictEntityListNodeView requires a build context"`.
  - Create button text `"Create"` calls `target:create-entity {}` and `target:add-entity-node`.
  - `SearchView` name `"dict-entity-list-view"`.
  - Search row button text is the label from `collect-items`.
  - `refresh-items` uses `target:emit-items`.
  - Connect/disconnect `target.items-changed`.
  - Drop owned flex tree.

- [ ] **Step 5: Run focused compile, constraints, and tests**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/views/dict-entity.fnl
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/views/dict-entity-list.fnl
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-dict-entities.fnl

  make constraints

  SKIP_KEYRING_TESTS=1 \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-dict-entities:main
  ```

  Expected: PASS.

- [ ] **Step 6: Commit Task 3**

  ```bash
  git add assets/lua/graph/view/views/dict-entity.fnl \
          assets/lua/graph/view/views/dict-entity-list.fnl \
          assets/lua/tests/test-dict-entities.fnl
  git commit -m "feat(ui): add dict entity views"
  ```

---

### Task 4: Documentation and Final Validation

**Files:**
- Create: `docs/dev/notes/dict-entities.md`
- Modify: `docs/dev/notes/entity-store.md`

**Interfaces:**
- Consumes: Implemented dict store, graph node, loader, and UI behavior from Tasks 1–3.
- Produces: Developer-facing documentation and final validation evidence.

- [ ] **Step 1: Create `docs/dev/notes/dict-entities.md`**

  Include this focused content:

  ````markdown
  ---
  type: dev-note
  tags:
    - note
  ---

  # Dict Entities

  Dict entities are persistent keyed collections whose values are graph-addressable keys. They complement list entities: lists store ordered arrays of references, while dicts store string-keyed maps of references.

  ## Storage

  - File: `assets/lua/entities/dict.fnl`
  - Directory: `{user-data-dir}/entities/dict/`
  - Format: one JSON file per entity, named `<uuid>.json`
  - Required fields: `id`, `name`, `items`, `created-at`, `updated-at`

  Example:

  ```fennel
  {:id "profile"
   :name "Alice profile"
   :items {"name" "string-entity:name"
           "manager" "identity:bob"}
   :created-at 123
   :updated-at 456}
  ```

  ## API

  `DictEntityStore` exposes CRUD plus `get-item`, `set-item`, `remove-item`, and `rename-item`. Mutating item operations reject missing or empty required keys/values with explicit errors.

  ## Graph keys

  - `dict-entity:<id>` opens one dict entity.
  - `dict-entity-list` opens the dict entity browser.

  Graph-facing `DictEntityNode:set-item` wraps non-identity target keys through identity entities when possible. Unresolved references remain stored and can resolve later.

  ## UI

  The initial dict view supports name editing, item count, stable key-sorted rows, key/value save, remove, selected-node insertion, focus/open for referenced keys, and delete.
  ````

- [ ] **Step 2: Update `docs/dev/notes/entity-store.md`**

  Change “Five entity types exist” to “Six entity types exist”.

  Add a section after list entities:

  ```markdown
  ### Dict entity (`entities/dict.fnl`)

  Keyed collections of graph-addressable references. Used for profile-like or object-like structures composed from primitive entity references.

  - **Fields**: `:items` (string-keyed table of graph reference keys)
  - **Store**: `entities/dict/`
  - **Signals**: `dict-entity-created`, `dict-entity-updated`, `dict-entity-deleted`, `dict-entity-items-changed`
  - **API**: `get-item`, `set-item`, `remove-item`, `rename-item`
  ```

- [ ] **Step 3: Run docs/text sanity checks**

  ```bash
  rg "Dict Entities|dict-entity|entities/dict" docs/dev/notes
  rg "Five entity types exist" docs/dev/notes/entity-store.md
  ```

  Expected:
  - First command finds the new note and updated entity store references.
  - Second command returns no matches.

- [ ] **Step 4: Run final Fennel compile checks**

  ```bash
  for f in assets/lua/entities/dict.fnl \
           assets/lua/graph/nodes/dict-entity.fnl \
           assets/lua/graph/nodes/dict-entity-list.fnl \
           assets/lua/graph/view/views/dict-entity.fnl \
           assets/lua/graph/view/views/dict-entity-list.fnl \
           assets/lua/graph/extensions/builtins/entities.fnl \
           assets/lua/graph/nodes/entities.fnl \
           assets/lua/main.fnl \
           assets/lua/tests/test-dict-entities.fnl \
           assets/lua/tests/test-builtin-graph-extensions.fnl \
           assets/lua/tests/fast.fnl; do
    ./build/space -m tools.fennel-check:main -- --target files --file "$f"
  done
  ```

  Expected: PASS.

- [ ] **Step 5: Run final constraints**

  ```bash
  make constraints
  ```

  Expected: PASS.

- [ ] **Step 6: Run focused dict and loader tests**

  ```bash
  SKIP_KEYRING_TESTS=1 \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-dict-entities:main

  SKIP_KEYRING_TESTS=1 \
  XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-builtin-graph-extensions:main
  ```

  Expected: PASS.

- [ ] **Step 7: Run broader final local validation**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: PASS. This broader run is required here because the change touches built-in graph loaders, `main.fnl` runtime extension setup, and fast-suite registration.

- [ ] **Step 8: Commit Task 4**

  ```bash
  git add docs/dev/notes/dict-entities.md docs/dev/notes/entity-store.md
  git commit -m "docs(assets): document dict entities"
  ```

- [ ] **Step 9: Record final integration gate**

  Confirm the implementation report states:
  - focused compile checks passed;
  - `make constraints` passed;
  - `tests.test-dict-entities:main` passed;
  - `tests.test-builtin-graph-extensions:main` passed;
  - `make test` passed locally;
  - PR CI remains the full integration gate.
