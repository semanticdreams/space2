# String Entity Create Child Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a string-entity node action named `Create child` that creates a child string entity, creates a link entity from the parent to the child, and materializes the child in the containing `GraphMap`.

**Architecture:** Implement the behavior as a node-local capability on the string entity graph node adapter. Domain data remains owned by `StringEntityStore` and `LinkEntityStore`; the string node action only uses the mounted `GraphMap` to load the new child key, relying on existing link-entity derived-edge recomputation rather than adding an explicit map edge.

**Tech Stack:** Space Fennel, graph node adapters, `GraphMap`, `entities/string`, `entities/link`, project-native Fennel compile/constraints/test tooling.

## Global Constraints

- The string entity node context menu must include `Create child`.
- `Create child` must create a new string entity with the store default contents.
- `Create child` must create one link entity with `source-key` equal to the current node key and `target-key` equal to the new child node key.
- The new child string entity must be added to the same active/containing `GraphMap` as the parent node.
- Do not add an explicit map edge; existing link-entity derived-edge behavior should display the relationship when both endpoint nodes are visible.
- Derived link edges must remain omitted from `GraphMap:capture-state`.
- `StringEntityStore` owns string entity data; `LinkEntityStore` owns relationship data; `GraphMap` owns only visible topology and map-local adapter state.
- Missing mount context, missing `load-by-key`, missing created ids, and child load failures must raise explicit errors.
- Preserve existing string entity behavior, including `Delete Entity`.
- Use `local` in Fennel; do not use `let`.
- Validate through project-native `tools.fennel-check`, constraints, and tests; do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e`.
- Out of scope: child positioning policy, prompting for initial child text, link labels/metadata editing, multiple-child creation, root action changes, and persisting derived link edges as explicit graph map edges.

---

## File Structure

- `assets/lua/graph/nodes/string-entity.fnl`: adds the node-local `create-child` method, link-store resolution, explicit failure checks, and the `Create child` action.
- `assets/lua/tests/test-string-entity-create-child.fnl`: focused TDD coverage for successful child/link creation, graph-map materialization, derived-edge capture behavior, and failure paths.
- `assets/lua/tests/fast.fnl`: registers the focused test module in the fast suite.
- `docs/dev/graph-maps.md`: documents the graph doctrine semantics for the new explicit node action.

---

### Task 1: String Entity Create Child Action

**Files:**
- Create: `assets/lua/tests/test-string-entity-create-child.fnl`
- Modify: `assets/lua/graph/nodes/string-entity.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `StringEntityStore:create-entity(opts) -> entity`, `LinkEntityStore:create-entity(opts) -> entity`, `GraphMap:load-by-key(key) -> node|nil`, `GraphMap:lookup(key) -> node|nil`, `GraphMap:capture-state() -> table`.
- Produces: `StringEntityNode:create-child() -> {:child table :child-key string :child-node table :link table}` and node action `{:name "Create child" :icon "subdirectory_arrow_right" :fn function}`.

- [ ] **Step 1: Inspect existing exact constructor/export names before editing**

Read these files and confirm names used by the implementation and tests:

```bash
rg "StringEntityNode|register-loader|StringEntityStore|LinkEntityStore|GraphMap" assets/lua/graph/nodes/string-entity.fnl assets/lua/entities/string.fnl assets/lua/entities/link.fnl assets/lua/tests/test-string-entities.fnl assets/lua/tests/test-link-entities.fnl assets/lua/tests/test-graph-map.fnl
```

Expected: identify the existing string node constructor/export, loader registration helper, store constructors, and graph-map fixture patterns. Use those exact names in the next steps.

- [ ] **Step 2: Write the focused failing test module**

Create `assets/lua/tests/test-string-entity-create-child.fnl`. Use the existing test runner and the real stores/graph/map. The test module should use this structure:

```fennel
(local fs (require :fs))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local StringEntityStore (require :entities/string))
(local LinkEntityStore (require :entities/link))
(local {:StringEntityNode StringEntityNode
        :register-loader register-string-loader} (require :graph/nodes/string-entity))

(local tests [])
(var temp-counter 0)

(fn temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path "/tmp/space/tests/string-entity-create-child"
                (.. "case-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (if ok result (error result)))

(fn make-stores [dir]
  {:string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path dir "string")})
   :link-store (LinkEntityStore.LinkEntityStore {:base-dir (fs.join-path dir "link")})})

(fn find-action [node name]
  (var found nil)
  (each [_ action (ipairs (or node.actions []))]
    (when (= action.name name)
      (set found action)))
  found)

(fn invoke-action [action]
  (assert action "expected action to exist")
  (assert (= (type action.fn) "function") "expected action.fn to be function")
  (action.fn nil nil))

(fn assert-error-contains [f expected]
  (local (ok err) (pcall f))
  (assert (not ok) "expected function to fail")
  (assert (string.find (tostring err) expected 1 true)
          (.. "expected error to contain " expected ", got " (tostring err))))

(fn with-real-graph-map [f]
  (with-temp-dir
    (fn [dir]
      (local stores (make-stores dir))
      (local graph (Graph {:with-start false
                           :string-store stores.string-store
                           :link-store stores.link-store}))
      (register-string-loader graph {:store stores.string-store})
      (local graph-map (GraphMap.GraphMap {:graph graph :id "create-child-test"}))
      (local parent (stores.string-store:create-entity {:value "parent"}))
      (local parent-key (.. "string-entity:" parent.id))
      (local parent-node (graph-map:load-by-key parent-key))
      (assert parent-node "expected parent node to load")
      (local (ok result) (pcall f {:stores stores
                                   :graph graph
                                   :graph-map graph-map
                                   :parent parent
                                   :parent-key parent-key
                                   :parent-node parent-node}))
      (graph-map:drop)
      (graph:drop)
      (if ok result (error result)))))

(fn test-create-child-success []
  (with-real-graph-map
    (fn [ctx]
      (local create-action (find-action ctx.parent-node "Create child"))
      (local delete-action (find-action ctx.parent-node "Delete Entity"))
      (assert create-action "expected Create child action")
      (assert delete-action "expected Delete Entity action to remain")
      (local result (invoke-action create-action))
      (assert result.child "expected child entity in result")
      (assert result.child.id "expected child id")
      (assert result.link "expected link entity in result")
      (local child-key (.. "string-entity:" result.child.id))
      (assert (= result.child-key child-key) "expected child-key to match id")
      (assert (= result.link.source-key ctx.parent-key) "expected parent source-key")
      (assert (= result.link.target-key child-key) "expected child target-key")
      (assert (= (length (ctx.stores.string-store:list-entities)) 2) "expected parent plus child")
      (assert (= (length (ctx.stores.link-store:list-entities)) 1) "expected one link")
      (assert (ctx.graph-map:lookup child-key) "expected child in same graph map")
      (assert (= (ctx.graph-map:edge-count) 1) "expected one visible derived edge")
      (local captured (ctx.graph-map:capture-state))
      (assert (= (length captured.edges) 0) "derived edge must not persist"))))

(fn test-create-child-unmounted-fails []
  (with-temp-dir
    (fn [dir]
      (local stores (make-stores dir))
      (local parent (stores.string-store:create-entity {:value "parent"}))
      (local node (StringEntityNode {:entity-id parent.id
                                     :store stores.string-store}))
      (local action (find-action node "Create child"))
      (assert-error-contains (fn [] (invoke-action action))
                             "StringEntityNode.create-child requires mounted GraphMap")
      (assert (= (length (stores.string-store:list-entities)) 1) "must not create child on unmounted failure")
      (assert (= (length (stores.link-store:list-entities)) 0) "must not create link on unmounted failure")
      (node:drop))))

(fn test-create-child-without-load-by-key-fails []
  (with-temp-dir
    (fn [dir]
      (local stores (make-stores dir))
      (local parent (stores.string-store:create-entity {:value "parent"}))
      (local node (StringEntityNode {:entity-id parent.id
                                     :store stores.string-store}))
      (node:mount {:graph {:link-store stores.link-store}})
      (local action (find-action node "Create child"))
      (assert-error-contains (fn [] (invoke-action action))
                             "StringEntityNode.create-child requires mounted GraphMap with load-by-key")
      (assert (= (length (stores.string-store:list-entities)) 1) "must not create child without load-by-key")
      (assert (= (length (stores.link-store:list-entities)) 0) "must not create link without load-by-key")
      (node:drop))))

(fn test-create-child-load-failure-fails-loudly []
  (with-temp-dir
    (fn [dir]
      (local stores (make-stores dir))
      (local parent (stores.string-store:create-entity {:value "parent"}))
      (local node (StringEntityNode {:entity-id parent.id
                                     :store stores.string-store}))
      (node:mount {:graph {:link-store stores.link-store}
                   :load-by-key (fn [_self _key] nil)})
      (local action (find-action node "Create child"))
      (assert-error-contains (fn [] (invoke-action action))
                             "StringEntityNode.create-child failed to load child key into GraphMap")
      (node:drop))))

(table.insert tests {:name "Create child creates child link and derived edge" :fn test-create-child-success})
(table.insert tests {:name "Create child fails when unmounted" :fn test-create-child-unmounted-fails})
(table.insert tests {:name "Create child fails without load-by-key" :fn test-create-child-without-load-by-key-fails})
(table.insert tests {:name "Create child fails when child load fails" :fn test-create-child-load-failure-fails-loudly})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "string-entity-create-child" :tests tests})))

{:name "string-entity-create-child"
 :tests tests
 :main main}
```

- [ ] **Step 3: Compile-check the new test file before running RED**

If `./build/space` is missing or stale, run `make build` with timeout `14400000`. Then run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-string-entity-create-child.fnl
```

Expected: the test file compiles. If a parse error appears, inspect the nearest enclosing form, repair the test syntax only, and rerun this compile check.

- [ ] **Step 4: Run the focused test and verify RED**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-string-entity-create-child:main
```

Expected: FAIL for the missing `Create child` behavior. If it fails because the test harness used a wrong existing constructor/export name, correct the test to match Step 1 evidence and rerun until the failure is the missing feature.

- [ ] **Step 5: Add the link store dependency and explicit context helpers**

Modify `assets/lua/graph/nodes/string-entity.fnl` to require the link store module and add helpers near existing local helpers:

```fennel
(local LinkEntityStore (require :entities/link))

(fn require-graph-map [node]
  (local graph-map node.graph)
  (assert graph-map "StringEntityNode.create-child requires mounted GraphMap")
  (assert (= (type graph-map.load-by-key) "function")
          "StringEntityNode.create-child requires mounted GraphMap with load-by-key")
  graph-map)

(fn resolve-link-store [graph-map]
  (or (and graph-map graph-map.graph graph-map.graph.link-store)
      (and graph-map graph-map.link-store)
      (LinkEntityStore.get-default)))

(fn require-created-entity [entity context]
  (assert entity (.. context " failed to create entity"))
  (assert entity.id (.. context " created entity is missing id"))
  entity)
```

- [ ] **Step 6: Implement `StringEntityNode:create-child`**

Inside the node constructor, after `node.delete-entity` is defined and before `node.actions`, add:

```fennel
(set node.create-child
     (fn [self]
       (local graph-map (require-graph-map self))
       (local child (require-created-entity
                      (self.store:create-entity {})
                      "StringEntityNode.create-child string store"))
       (local child-key (.. KEY_PREFIX (tostring child.id)))
       (local link-store (resolve-link-store graph-map))
       (local link (require-created-entity
                     (link-store:create-entity {:source-key self.key
                                                :target-key child-key})
                     "StringEntityNode.create-child link store"))
       (local child-node (graph-map:load-by-key child-key))
       (assert child-node
               (.. "StringEntityNode.create-child failed to load child key into GraphMap: " child-key))
       {:child child
        :child-key child-key
        :child-node child-node
        :link link}))
```

This method must not call `graph-map:add-edge`.

- [ ] **Step 7: Add the node action before `Delete Entity`**

Replace the existing `node.actions` assignment with:

```fennel
(set node.actions
     [{:name "Create child"
       :icon "subdirectory_arrow_right"
       :fn (fn [_button _event]
             (node:create-child))}
      {:name "Delete Entity"
       :icon "delete"
       :fn (fn [_button _event]
             (node:delete-entity))}])
```

- [ ] **Step 8: Register the focused test in the fast suite**

Modify `assets/lua/tests/fast.fnl` and add this module near the existing string/link/graph entity tests:

```fennel
:tests.test-string-entity-create-child
```

- [ ] **Step 9: Run focused validation in Fennel order**

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/nodes/string-entity.fnl --file assets/lua/tests/test-string-entity-create-child.fnl --file assets/lua/tests/fast.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-string-entity-create-child:main
```

Expected: compile check, constraints, and focused test all PASS.

- [ ] **Step 10: Run the registered fast suite**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
```

Expected: PASS, including `tests.test-string-entity-create-child`.

- [ ] **Step 11: Commit Task 1**

```bash
git add assets/lua/graph/nodes/string-entity.fnl assets/lua/tests/test-string-entity-create-child.fnl assets/lua/tests/fast.fnl
git commit -m "feat(graph): add string entity create child action"
```

Commit report must include compile-check, constraints, focused-test, fast-suite, and constraint-impact evidence.

---

### Task 2: Graph Map Doctrine Documentation

**Files:**
- Modify: `docs/dev/graph-maps.md`

**Interfaces:**
- Consumes: Task 1 behavior: `StringEntityNode:create-child() -> {:child table :child-key string :child-node table :link table}`.
- Produces: developer documentation describing `Create child` as an explicit node action that mutates string/link stores and materializes only the child node in the containing graph map.

- [ ] **Step 1: Document current status**

In `docs/dev/graph-maps.md`, under `Implemented:`, add:

```markdown
- String entity nodes expose a `Create child` action that creates a child string entity, creates a link entity from parent key to child key, and loads the child key into the containing `GraphMap`.
```

- [ ] **Step 2: Document action semantics**

In `## Action Semantics`, add:

```markdown
String entity `Create child` is a node-specific domain action. It mutates `StringEntityStore` and `LinkEntityStore`, then materializes the new child node in the containing `GraphMap`; it does not add an explicit map edge.
```

- [ ] **Step 3: Document derived-edge semantics**

In `## Derived Edges`, add:

```markdown
String entity `Create child` relies on link-entity derived-edge recomputation. The created link entity owns the parent-child relationship, and the visible edge remains omitted from `GraphMap:capture-state`.
```

- [ ] **Step 4: Document test coverage**

In the `## Tests` list, add:

```markdown
- String entity `Create child` creates store-owned child/link entities, materializes the child in the containing graph map, and leaves the derived link edge out of captured topology.
```

- [ ] **Step 5: Run focused docs checks**

```bash
rg "Create child|derived-edge|GraphMap:capture-state" docs/dev/graph-maps.md
rg "graph-backed object|first-class graph object|graph-native object|stored in the graph" docs/dev/graph-maps.md
```

Expected: the first command finds the new documentation. The second command finds no forbidden terminology introduced by this task.

- [ ] **Step 6: Re-run the focused feature test**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-string-entity-create-child:main
```

Expected: PASS.

- [ ] **Step 7: Commit Task 2**

```bash
git add docs/dev/graph-maps.md
git commit -m "docs(graph): document string entity create child action"
```

---

## Final Validation

- [ ] If `./build/space` may be missing or stale, run `make build` with timeout `14400000`.
- [ ] Run `make fennel-check`.
- [ ] Run `make constraints`.
- [ ] Run the focused test:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-string-entity-create-child:main
```

- [ ] Run the broader fast suite:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
```

- [ ] If any validation fails, capture the failing command, relevant output, and `git status --porcelain`; invoke systematic debugging before changing code.
- [ ] Do not claim ready-to-merge until reviewed changes are committed, final validation passes, the worktree is clean, the branch has been evaluated against current `origin/main`, and PR CI is green.
