# String Entity Text Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a graph-native text search surface for string entities, launched from the existing `string entities` node and backed initially by ripgrep.

**Architecture:** Add a reusable UX-purpose graph node keyed by exact loader key `string-entity-search`. A focused string-search backend module wraps ripgrep behind `backend:search-text(query, callback)` so graph nodes and views do not depend on ripgrep details. The search node owns runtime query/result state and materializes selected results through `GraphMap:load-by-key`; string entity storage remains owned by `StringEntityStore`.

**Tech Stack:** Space Fennel, `GraphNode`, `GraphEdge`, `GraphMap`, built-in graph key loaders, `Signal`, `Input`, `Button`, `Text`, `ListView`, `Flex`, existing `ripgrep.fnl`, Space Fennel validation tools.

## Global Constraints

- The graph is an exposure/adaptor layer; string entity domain data stays owned by `StringEntityStore`.
- `GraphMap` persists explicit visible topology only; search query text and result rows are runtime-only.
- The search node key is exactly `string-entity-search` and contains no query text.
- Initial search backend uses ripgrep literal fixed-string matching with case-insensitive behavior.
- Ripgrep searches only `store.entities-dir` and `*.md` files.
- Selecting a result materializes `string-entity:<id>` through the active `GraphMap`; it does not create a `LinkEntity` or persisted domain relationship.
- Backend code must be isolated so another backend can satisfy the same node-facing contract.
- All Fennel changes must pass touched-file compile checks, `make constraints`, and focused tests before broader validation.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.

---

## File Structure

- Create `assets/lua/entities/string-search.fnl`: backend boundary and ripgrep-backed implementation. It converts ripgrep matches into string entity search results and knows nothing about graph nodes or views.
- Create `assets/lua/graph/nodes/string-entity-search.fnl`: UX-purpose graph node that owns runtime query/result/status state, delegates searches to an injected backend, and materializes selected results through `GraphMap:load-by-key`.
- Create `assets/lua/graph/view/views/string-entity-search.fnl`: widget view for the search node, with query input, search button, status text, and result list.
- Modify `assets/lua/graph/nodes/string-entity-list.fnl`: add `add-search-node` and expose a `Search Text` node action.
- Modify `assets/lua/graph/view/views/string-entity-list.fnl`: add the `Search Text` button beside the existing `Create` control.
- Modify `assets/lua/graph/extensions/builtins/entities.fnl`: register exact loader support for `string-entity-search`.
- Create `assets/lua/tests/test-string-entity-search.fnl`: focused backend, node, and view tests.
- Modify `assets/lua/tests/test-string-entities.fnl`: adjacent property coverage for the list node/view entry point.
- Modify `assets/lua/tests/fast.fnl`: include the new focused test module.
- Create `docs/dev/features/string-entity-full-text-search.md`: developer documentation for the graph node, runtime state rule, and backend contract.

---

### Task 1: Ripgrep-backed string entity search backend

**Files:**
- Create: `assets/lua/entities/string-search.fnl`
- Create: `assets/lua/tests/test-string-entity-search.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `store.entities-dir`, `store:get-entity(id)`, injected `ripgrep.search-async(opts, callback)`.
- Produces: `StringSearch.RipgrepStringEntitySearchBackend(opts table) -> backend table`.
- Produces: `backend:search-text(query string, callback function) -> token|nil`.
- Produces callback payload: `{:ok boolean :query string :results table :stderr string|nil :error string|nil}`.
- Produces result rows: `{:entity-id string :entity table :matches table :match-count number}`.

- [ ] **Step 1: Write backend test scaffolding**

  Add `assets/lua/tests/test-string-entity-search.fnl` with temporary-store helpers and fake ripgrep support. The fake captures the search options and invokes the callback synchronously.

  ```fennel
  (local fs (require :fs))
  (local tests [])
  (var temp-counter 0)
  (local temp-root (fs.join-path "/tmp/space/tests" "string-entity-search"))

  (fn make-temp-dir []
    (set temp-counter (+ temp-counter 1))
    (fs.join-path temp-root (.. "search-" (os.time) "-" temp-counter)))

  (fn with-temp-store [f]
    (local dir (make-temp-dir))
    (when (fs.exists dir)
      (fs.remove-all dir))
    (fs.create-dirs dir)
    (local StringEntityStore (require :entities/string))
    (local store (StringEntityStore.StringEntityStore {:base-dir dir}))
    (local (ok result) (pcall f store dir))
    (fs.remove-all dir)
    (if ok result (error result)))

  (fn fake-ripgrep [matches]
    (local state {:calls []})
    (set state.search-async
         (fn [opts callback]
           (table.insert state.calls opts)
           (callback {:ok true :query opts.query :matches matches :stderr ""})
           {:cancel (fn [_self _opts] (set state.cancelled true))}))
    state)
  ```

- [ ] **Step 2: Add failing tests for ripgrep options and blank query**

  Add tests named `backend passes literal ignore-case ripgrep options` and `backend blank query does not invoke ripgrep`.

  ```fennel
  (fn backend-passes-ripgrep-options []
    (with-temp-store
      (fn [store _root]
        (local entity (store:create-entity {:id "alpha" :value "Needle text"}))
        (local path (fs.join-path store.entities-dir (.. entity.id ".md")))
        (local rg (fake-ripgrep [{:path path :line 5 :column 1 :text "Needle text"}]))
        (local Search (require :entities/string-search))
        (local backend (Search.RipgrepStringEntitySearchBackend {:store store :ripgrep rg}))
        (local seen [])
        (backend:search-text "Needle" (fn [payload] (table.insert seen payload)))
        (local opts (. rg.calls 1))
        (assert opts "ripgrep should be invoked")
        (assert (= opts.query "Needle"))
        (assert (= opts.literal true))
        (assert (= opts.case :ignore))
        (assert (= (. opts.paths 1) store.entities-dir))
        (assert (= (. opts.globs 1) "*.md"))
        (assert (= (length (. (. seen 1) :results)) 1)))))

  (fn backend-blank-query-does-not-invoke-ripgrep []
    (with-temp-store
      (fn [store _root]
        (local rg (fake-ripgrep []))
        (local Search (require :entities/string-search))
        (local backend (Search.RipgrepStringEntitySearchBackend {:store store :ripgrep rg}))
        (local seen nil)
        (local token (backend:search-text "  " (fn [payload] (set seen payload))))
        (assert (= token nil))
        (assert (= (length rg.calls) 0))
        (assert seen)
        (assert (= seen.ok true))
        (assert (= (length seen.results) 0))))))
  ```

- [ ] **Step 3: Add failing tests for path mapping, dedupe, and filtering**

  Add tests named `backend dedupes multiple matches per entity` and `backend ignores non-entity matches`.

  ```fennel
  (fn backend-dedupes-multiple-matches-per-entity []
    (with-temp-store
      (fn [store _root]
        (local entity (store:create-entity {:id "dupe" :value "needle\nneedle"}))
        (local path (fs.join-path store.entities-dir "dupe.md"))
        (local rg (fake-ripgrep [{:path path :line 5 :column 1 :text "needle"}
                                 {:path path :line 6 :column 1 :text "needle again"}]))
        (local Search (require :entities/string-search))
        (local backend (Search.RipgrepStringEntitySearchBackend {:store store :ripgrep rg}))
        (local seen nil)
        (backend:search-text "needle" (fn [payload] (set seen payload)))
        (assert (= (length seen.results) 1))
        (assert (= (. (. seen.results 1) :entity-id) "dupe"))
        (assert (= (. (. seen.results 1) :match-count) 2)))))

  (fn backend-ignores-non-entity-matches []
    (with-temp-store
      (fn [store root]
        (store:create-entity {:id "kept" :value "needle"})
        (local kept-path (fs.join-path store.entities-dir "kept.md"))
        (local other-path (fs.join-path root "outside.md"))
        (local txt-path (fs.join-path store.entities-dir "note.txt"))
        (local missing-path (fs.join-path store.entities-dir "missing.md"))
        (local rg (fake-ripgrep [{:path kept-path :line 5 :column 1 :text "needle"}
                                 {:path other-path :line 1 :column 1 :text "needle"}
                                 {:path txt-path :line 1 :column 1 :text "needle"}
                                 {:path missing-path :line 1 :column 1 :text "needle"}]))
        (local Search (require :entities/string-search))
        (local backend (Search.RipgrepStringEntitySearchBackend {:store store :ripgrep rg}))
        (local seen nil)
        (backend:search-text "needle" (fn [payload] (set seen payload)))
        (assert (= (length seen.results) 1))
        (assert (= (. (. seen.results 1) :entity-id) "kept"))))))
  ```

- [ ] **Step 4: Register the focused tests in the test module and fast suite**

  Finish `test-string-entity-search.fnl` with test registrations and add the module to `assets/lua/tests/fast.fnl` near the existing string entity entries.

  ```fennel
  (table.insert tests {:name "backend passes literal ignore-case ripgrep options"
                       :fn backend-passes-ripgrep-options})
  (table.insert tests {:name "backend blank query does not invoke ripgrep"
                       :fn backend-blank-query-does-not-invoke-ripgrep})
  (table.insert tests {:name "backend dedupes multiple matches per entity"
                       :fn backend-dedupes-multiple-matches-per-entity})
  (table.insert tests {:name "backend ignores non-entity matches"
                       :fn backend-ignores-non-entity-matches})

  (local main
    (fn []
      (local runner (require :tests/runner))
      (runner.run-tests {:name "string-entity-search" :tests tests})))

  {:name "string-entity-search" :tests tests :main main}
  ```

- [ ] **Step 5: Run the new backend tests and verify RED**

  Run:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-string-entity-search.fnl --file assets/lua/tests/fast.fnl
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-string-entity-search:main
  ```

  Expected: compile passes; focused test fails because `entities/string-search.fnl` does not exist or exports no backend.

- [ ] **Step 6: Implement `assets/lua/entities/string-search.fnl`**

  Implement the backend with small helpers for trimming, path mapping, result grouping, and ripgrep payload conversion.

  ```fennel
  (local fs (require :fs))

  (fn trim [text]
    (string.match (or text "") "^%s*(.-)%s*$"))

  (fn has-prefix? [text prefix]
    (= (string.sub text 1 (string.len prefix)) prefix))

  (fn strip-md-extension [name]
    (string.match name "^(.*)%.md$"))

  (fn basename [path]
    (or (string.match path "([^/]+)$") path))

  (fn entity-id-for-path [entities-dir path]
    (when (and entities-dir path (has-prefix? path entities-dir))
      (strip-md-extension (basename path))))

  (fn add-match! [groups order store entities-dir match]
    (local entity-id (entity-id-for-path entities-dir match.path))
    (when entity-id
      (local entity (store:get-entity entity-id))
      (when entity
        (var group (. groups entity-id))
        (when (not group)
          (set group {:entity-id entity-id :entity entity :matches [] :match-count 0})
          (set (. groups entity-id) group)
          (table.insert order entity-id))
        (table.insert group.matches match)
        (set group.match-count (+ group.match-count 1)))))

  (fn matches-to-results [store entities-dir matches]
    (local groups {})
    (local order [])
    (each [_ match (ipairs (or matches []))]
      (add-match! groups order store entities-dir match))
    (icollect [_ entity-id (ipairs order)] (. groups entity-id)))

  (fn RipgrepStringEntitySearchBackend [opts]
    (local options (or opts {}))
    (local store (assert options.store "RipgrepStringEntitySearchBackend requires :store"))
    (local rg (or options.ripgrep (require :ripgrep)))
    (assert store.entities-dir "RipgrepStringEntitySearchBackend requires store.entities-dir")
    (assert store.get-entity "RipgrepStringEntitySearchBackend requires store:get-entity")
    (assert rg.search-async "RipgrepStringEntitySearchBackend requires ripgrep.search-async")
    (local backend {})
    (set backend.search-text
         (fn [_self query callback]
           (assert (= (type callback) :function) "search-text requires callback")
           (local trimmed (trim query))
           (if (= (# trimmed) 0)
               (do
                 (callback {:ok true :query trimmed :results []})
                 nil)
               (rg.search-async
                 {:query trimmed
                  :paths [store.entities-dir]
                  :globs ["*.md"]
                  :literal true
                  :case :ignore}
                 (fn [result]
                   (callback {:ok result.ok
                              :query trimmed
                              :stderr result.stderr
                              :error (and (not result.ok) result.stderr)
                              :results (matches-to-results store store.entities-dir result.matches)}))))))
    backend)

  {:RipgrepStringEntitySearchBackend RipgrepStringEntitySearchBackend}
  ```

- [ ] **Step 7: Validate Task 1**

  Run:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/entities/string-search.fnl --file assets/lua/tests/test-string-entity-search.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-string-entity-search:main
  ```

  Expected: compile check passes, constraints pass, and focused backend tests pass.

- [ ] **Step 8: Review handoff checkpoint**

  Report changed files, RED evidence, validation results, and any constraint impact. Do not commit until the reviewer gate passes.

---

### Task 2: Loader-backed string entity search graph node

**Files:**
- Create: `assets/lua/graph/nodes/string-entity-search.fnl`
- Modify: `assets/lua/graph/extensions/builtins/entities.fnl`
- Modify: `assets/lua/tests/test-string-entity-search.fnl`

**Interfaces:**
- Consumes: `Search.RipgrepStringEntitySearchBackend({:store store})` from Task 1.
- Produces: `StringEntitySearchNode(opts table) -> node`.
- Produces node methods: `node:search-text(query string) -> token|nil`, `node:clear-results() -> nil`, `node:open-result(result table) -> graph node`.
- Produces signals: `node.results-changed`, `node.status-changed`.
- Produces module fields: `{:StringEntitySearchNode StringEntitySearchNode :register-loader register-loader}`.

- [ ] **Step 1: Add failing node construction and search delegation tests**

  Extend `assets/lua/tests/test-string-entity-search.fnl` with a fake backend and tests named `search node creates with exact key` and `search node delegates and emits results`.

  ```fennel
  (fn fake-backend []
    {:calls []
     :search-text (fn [self query callback]
                    (table.insert self.calls query)
                    (callback {:ok true :query query :results [{:entity-id "alpha" :entity {:id "alpha" :value "Alpha"} :matches [] :match-count 0}]})
                    {:cancel (fn [_token _opts] (set self.cancelled true))})})

  (fn search-node-creates-with-exact-key []
    (local {:StringEntitySearchNode StringEntitySearchNode} (require :graph/nodes/string-entity-search))
    (local node (StringEntitySearchNode {:store {:entities-dir "/tmp/entities" :get-entity (fn [] nil)}
                                         :backend (fake-backend)}))
    (assert (= node.key "string-entity-search"))
    (assert (= node.label "string entity text search"))
    (assert node.results-changed)
    (assert node.status-changed)
    (node:drop))

  (fn search-node-delegates-and-emits-results []
    (local {:StringEntitySearchNode StringEntitySearchNode} (require :graph/nodes/string-entity-search))
    (local backend (fake-backend))
    (local node (StringEntitySearchNode {:store {:entities-dir "/tmp/entities" :get-entity (fn [] nil)}
                                         :backend backend}))
    (var emitted nil)
    (node.results-changed:connect (fn [results] (set emitted results)))
    (node:search-text "Alpha")
    (assert (= (. backend.calls 1) "Alpha"))
    (assert (= node.status "Found 1 result"))
    (assert (= (length emitted) 1))
    (node:drop))
  ```

- [ ] **Step 2: Add failing cancellation and stale callback tests**

  Add tests named `search node cancels previous token` and `search node ignores stale callbacks`.

  ```fennel
  (fn controllable-backend []
    {:callbacks []
     :tokens []
     :search-text (fn [self query callback]
                    (table.insert self.callbacks {:query query :callback callback})
                    (local token {:cancelled false
                                  :cancel (fn [self _opts] (set self.cancelled true))})
                    (table.insert self.tokens token)
                    token)})

  (fn search-node-cancels-previous-token []
    (local {:StringEntitySearchNode StringEntitySearchNode} (require :graph/nodes/string-entity-search))
    (local backend (controllable-backend))
    (local node (StringEntitySearchNode {:store {:entities-dir "/tmp/entities" :get-entity (fn [] nil)}
                                         :backend backend}))
    (node:search-text "one")
    (node:search-text "two")
    (assert (= (. (. backend.tokens 1) :cancelled) true))
    (node:drop))

  (fn search-node-ignores-stale-callbacks []
    (local {:StringEntitySearchNode StringEntitySearchNode} (require :graph/nodes/string-entity-search))
    (local backend (controllable-backend))
    (local node (StringEntitySearchNode {:store {:entities-dir "/tmp/entities" :get-entity (fn [] nil)}
                                         :backend backend}))
    (node:search-text "old")
    (node:search-text "new")
    ((. (. backend.callbacks 1) :callback) {:ok true :query "old" :results [{:entity-id "old"}]})
    ((. (. backend.callbacks 2) :callback) {:ok true :query "new" :results [{:entity-id "new"}]})
    (assert (= (. (. node.results 1) :entity-id) "new"))
    (node:drop))
  ```

- [ ] **Step 3: Add failing result materialization and capture-state tests**

  Add tests named `search node open result loads string entity key` and `search node capture state omits query text`.

  ```fennel
  (fn search-node-open-result-loads-string-entity-key []
    (local {:StringEntitySearchNode StringEntitySearchNode} (require :graph/nodes/string-entity-search))
    (local loaded [])
    (local graph-map {:load-by-key (fn [_self key]
                                     (table.insert loaded key)
                                     {:key key})})
    (local node (StringEntitySearchNode {:store {:entities-dir "/tmp/entities" :get-entity (fn [] nil)}
                                         :backend (fake-backend)}))
    (set node.graph graph-map)
    (local result (node:open-result {:entity-id "abc"}))
    (assert (= result.key "string-entity:abc"))
    (assert (= (. loaded 1) "string-entity:abc"))
    (node:drop))

  (fn search-node-capture-state-omits-query-text []
    (local GraphMap (require :graph/map))
    (local {:StringEntitySearchNode StringEntitySearchNode} (require :graph/nodes/string-entity-search))
    (local graph-map (GraphMap {:id "test-map" :name "test"}))
    (local node (StringEntitySearchNode {:store {:entities-dir "/tmp/entities" :get-entity (fn [] nil)}
                                         :backend (controllable-backend)}))
    (graph-map:add-node node)
    (node:search-text "secret query")
    (local state (graph-map:capture-state))
    (local encoded (tostring state))
    (assert (= (string.find encoded "secret query" 1 true) nil))
    (graph-map:drop))
  ```

- [ ] **Step 4: Run node tests and verify RED**

  Run:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-string-entity-search.fnl
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-string-entity-search:main
  ```

  Expected: compile passes; focused test fails because `graph/nodes/string-entity-search.fnl` does not exist or lacks the expected exports.

- [ ] **Step 5: Implement `assets/lua/graph/nodes/string-entity-search.fnl`**

  Implement the node with runtime-only state and robust callback sequencing.

  ```fennel
  (local glm (require :glm))
  (local {:GraphNode GraphNode} (require :graph/node-base))
  (local Signal (require :signal))
  (local StringEntityStore (require :entities/string))
  (local StringSearch (require :entities/string-search))

  (local GREEN (glm.vec4 0.15 0.35 0.2 1))
  (local GREEN_ACCENT (glm.vec4 0.2 0.45 0.25 1))
  (local KEY "string-entity-search")

  (fn status-for-result [payload]
    (if (not payload.ok)
        "Search failed"
        (= (length payload.results) 1)
        "Found 1 result"
        (string.format "Found %d results" (length payload.results))))

  (fn StringEntitySearchNode [opts]
    (local options (or opts {}))
    (local store (or options.store (StringEntityStore.get-default)))
    (local backend (or options.backend (StringSearch.RipgrepStringEntitySearchBackend {:store store})))
    (local StringEntitySearchNodeView (require :graph/view/views/string-entity-search))
    (local node (GraphNode {:key KEY
                            :label "string entity text search"
                            :color GREEN
                            :sub-color GREEN_ACCENT
                            :size 8.0
                            :view StringEntitySearchNodeView}))
    (set node.store store)
    (set node.backend backend)
    (set node.query "")
    (set node.results [])
    (set node.status "Enter text to search string entities")
    (set node.results-changed (Signal))
    (set node.status-changed (Signal))
    (set node.search-token nil)
    (set node.search-seq 0)
    (set node.search-text
         (fn [self query]
           (set self.search-seq (+ self.search-seq 1))
           (local seq self.search-seq)
           (when (and self.search-token self.search-token.cancel)
             (self.search-token:cancel {:suppress-callback true}))
           (set self.query (or query ""))
           (set self.status "Searching...")
           (self.status-changed:emit self.status)
           (set self.search-token
                (self.backend:search-text self.query
                  (fn [payload]
                    (when (= seq self.search-seq)
                      (set self.results (or payload.results []))
                      (set self.status (status-for-result payload))
                      (self.results-changed:emit self.results)
                      (self.status-changed:emit self.status)))))))
    (set node.clear-results
         (fn [self]
           (set self.results [])
           (self.results-changed:emit self.results)))
    (set node.open-result
         (fn [self result]
           (local entity-id (assert (and result result.entity-id) "StringEntitySearchNode.open-result requires entity-id"))
           (local graph-map (assert self.graph "StringEntitySearchNode.open-result requires mounted GraphMap"))
           (assert graph-map.load-by-key "StringEntitySearchNode.open-result requires GraphMap:load-by-key")
           (local loaded (graph-map:load-by-key (.. "string-entity:" entity-id)))
           (assert loaded (.. "StringEntitySearchNode.open-result failed to load string-entity:" entity-id))
           loaded))
    (set node.drop
         (fn [self]
           (when (and self.search-token self.search-token.cancel)
             (self.search-token:cancel {:suppress-callback true}))
           (self.results-changed:clear)
           (self.status-changed:clear)))
    node)

  (fn register-loader [graph opts]
    (local options (or opts {}))
    (local store (or options.store (StringEntityStore.get-default)))
    (graph:register-key-loader KEY
      (fn [key]
        (when (= key KEY)
          (StringEntitySearchNode {:store store})))) )

  {:StringEntitySearchNode StringEntitySearchNode
   :register-loader register-loader
   :key KEY}
  ```

- [ ] **Step 6: Register built-in entity loader**

  Modify `assets/lua/graph/extensions/builtins/entities.fnl` to require the new node module, add the scheme to `entity-schemes`, and register an exact loader.

  ```fennel
  (local StringEntitySearchNodeModule (require :graph/nodes/string-entity-search))
  ```

  ```fennel
  (local entity-schemes
    ["string-entity" "code-entity" "list-entity" "link-entity" "identity" "notebook"
     "string-entity-list" "string-entity-search" "list-entity-list" "link-entity-list" "entities" "notebooks"])
  ```

  ```fennel
  (fn make-string-entity-search []
    (StringEntitySearchNodeModule.StringEntitySearchNode {:store string-store}))
  (add! (graph:register-key-loader "string-entity-search"
      (Common.exact-key-loader "string-entity-search" make-string-entity-search)
      (loader-opts ctx)))
  ```

- [ ] **Step 7: Validate Task 2**

  Run:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/nodes/string-entity-search.fnl --file assets/lua/graph/extensions/builtins/entities.fnl --file assets/lua/tests/test-string-entity-search.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-string-entity-search:main
  ```

  Expected: compile check passes, constraints pass, and focused backend/node tests pass.

- [ ] **Step 8: Review handoff checkpoint**

  Report changed files, RED evidence, validation results, and any constraint impact. Do not commit until the reviewer gate passes.

---

### Task 3: Search node entry point and search view

**Files:**
- Create: `assets/lua/graph/view/views/string-entity-search.fnl`
- Modify: `assets/lua/graph/nodes/string-entity-list.fnl`
- Modify: `assets/lua/graph/view/views/string-entity-list.fnl`
- Modify: `assets/lua/tests/test-string-entity-search.fnl`
- Modify: `assets/lua/tests/test-string-entities.fnl`

**Interfaces:**
- Consumes: `StringEntitySearchNode` exact key `string-entity-search` from Task 2.
- Produces: `StringEntityListNode:add-search-node() -> search node`.
- Produces: `StringEntitySearchNodeView(node, opts) -> build(ctx) -> view`.
- Produces view fields for tests: `view.input`, `view.search-button`, `view.results-list`, `view.status-text`.

- [ ] **Step 1: Confirm icon availability**

  Verify `assets/material-design-icons/icons.txt` contains exact icon `search`. If the icon is unavailable, stop and report the missing icon instead of inventing a name.

- [ ] **Step 2: Add failing list node/view tests**

  Extend `assets/lua/tests/test-string-entities.fnl` with tests for the list node method and list view button. The method test can use a fake mounted graph map.

  ```fennel
  (fn string-entity-list-node-adds-search-node []
    (local StringEntityListNode (require :graph/nodes/string-entity-list))
    (local loaded [])
    (local edges [])
    (local node (StringEntityListNode {}))
    (set node.graph {:load-by-key (fn [_self key]
                                    (table.insert loaded key)
                                    {:key key})
                     :add-edge (fn [_self edge]
                                 (table.insert edges edge)
                                 edge)})
    (local search-node (node:add-search-node))
    (assert (= search-node.key "string-entity-search"))
    (assert (= (. loaded 1) "string-entity-search"))
    (assert (= (length edges) 1))
    (node:drop))
  ```

  ```fennel
  (fn string-entity-list-view-search-text-button-invokes-target []
    (local View (require :graph/view/views/string-entity-list))
    (local called {:count 0})
    (local target {:items-changed {:connect (fn [] nil) :disconnect (fn [] nil)}
                   :emit-items (fn [] [])
                   :add-search-node (fn [_self]
                                      (set called.count (+ called.count 1))
                                      {:key "string-entity-search"})})
    (local view ((View target) (make-ctx)))
    (assert view.search-text-button)
    (view.search-text-button:on-click {:button 1})
    (assert (= called.count 1))
    (view:drop))
  ```

- [ ] **Step 3: Add failing search view tests**

  Extend `assets/lua/tests/test-string-entity-search.fnl` with view tests. Use a fake node with signals.

  ```fennel
  (fn fake-search-node-for-view []
    (local Signal (require :signal))
    {:results []
     :status "Ready"
     :results-changed (Signal)
     :status-changed (Signal)
     :searched []
     :opened []
     :search-text (fn [self query] (table.insert self.searched query))
     :open-result (fn [self result] (table.insert self.opened result) {:key (.. "string-entity:" result.entity-id)})})

  (fn search-node-view-click-search-submits-input []
    (local View (require :graph/view/views/string-entity-search))
    (local node (fake-search-node-for-view))
    (local view ((View node) (make-ctx)))
    (view.input:set-text "needle")
    (view.search-button:on-click {:button 1})
    (assert (= (. node.searched 1) "needle"))
    (view:drop))

  (fn search-node-view-refreshes-results-and-opens-row []
    (local View (require :graph/view/views/string-entity-search))
    (local node (fake-search-node-for-view))
    (local view ((View node) (make-ctx)))
    (local result {:entity-id "abc" :entity {:value "Alpha body"} :matches [{:text "Alpha body"}] :match-count 1})
    (node.results-changed:emit [result])
    (assert (= (length view.results-list.items) 1))
    (local row-builder view.results-list.builder)
    (local row (row-builder [result "Alpha body"] (make-ctx)))
    (row:on-click {:button 1})
    (assert (= (. (. node.opened 1) :entity-id) "abc"))
    (view:drop))
  ```

- [ ] **Step 4: Run entry/view tests and verify RED**

  Run:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-string-entity-search.fnl --file assets/lua/tests/test-string-entities.fnl
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-string-entity-search:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-string-entities:main
  ```

  Expected: compile passes; tests fail because the list node method, button, and search view do not exist.

- [ ] **Step 5: Implement `StringEntityListNode:add-search-node` and action**

  Modify `assets/lua/graph/nodes/string-entity-list.fnl` to assert mounted graph APIs, load the search node, and add an explicit edge.

  ```fennel
  (set node.add-search-node
       (fn [self]
         (local graph (assert self.graph "StringEntityListNode.add-search-node requires mounted GraphMap"))
         (assert graph.load-by-key "StringEntityListNode.add-search-node requires GraphMap:load-by-key")
         (assert graph.add-edge "StringEntityListNode.add-search-node requires GraphMap:add-edge")
         (local search-node (graph:load-by-key "string-entity-search"))
         (assert search-node "StringEntityListNode.add-search-node failed to load string-entity-search")
         (graph:add-edge (GraphEdge {:source self :target search-node}))
         search-node))
  ```

  Add a node action after `New String`:

  ```fennel
  {:name "Search Text"
   :icon "search"
   :fn (fn [_button _event]
         (node:add-search-node))}
  ```

- [ ] **Step 6: Add `Search Text` button to the list view**

  Modify `assets/lua/graph/view/views/string-entity-list.fnl` to build and expose `view.search-text-button`. Place it in a small horizontal button row with the existing `Create` button.

  ```fennel
  (local search-text-button
    ((Button {:icon "search"
              :text "Search Text"
              :variant :ghost
              :on-click (fn [_button _event]
                          (assert target "StringEntityListNodeView Search Text requires target")
                          (assert target.add-search-node "StringEntityListNodeView target missing add-search-node")
                          (target:add-search-node))})
     build-ctx))

  (local controls
    ((Flex {:axis 1
            :xspacing 0.3
            :children [(FlexChild (fn [_] create-button) 0)
                       (FlexChild (fn [_] search-text-button) 0)]})
     build-ctx))
  ```

  Use `controls` as the first child of the existing vertical flex and set `(set view.search-text-button search-text-button)`.

- [ ] **Step 7: Implement `StringEntitySearchNodeView`**

  Create `assets/lua/graph/view/views/string-entity-search.fnl` with explicit child ownership through the root flex and signal cleanup.

  ```fennel
  (local Input (require :input))
  (local Button (require :button))
  (local Text (require :text))
  (local ListView (require :list-view))
  (local {: Flex : FlexChild} (require :flex))
  (local Utils (require :graph/view/utils))

  (fn result-label [result]
    (local entity-text (or (and result.entity result.entity.value) result.entity-id "result"))
    (local first-line (or (string.match entity-text "([^\r\n]+)") entity-text))
    (local count (or result.match-count 0))
    (string.format "%s (%d)" (Utils.truncate-with-ellipsis first-line 80) count))

  (fn result-items [results]
    (icollect [_ result (ipairs (or results []))]
      [result (result-label result)]))

  (fn StringEntitySearchNodeView [node opts]
    (local options (or opts {}))
    (local target (or node options.node))
    (fn build [ctx]
      (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
      (assert build-ctx "StringEntitySearchNodeView requires a build context")
      (local view {})
      (local input ((Input {:text (or target.query "") :placeholder "Search string entity text"}) build-ctx))
      (local search-button ((Button {:text "Search"
                                     :icon "search"
                                     :variant :ghost
                                     :on-click (fn [_button _event]
                                                 (target:search-text input.model.text))}) build-ctx))
      (local status-text ((Text {:text (or target.status "Ready")}) build-ctx))
      (local results-list
        ((ListView {:items (result-items target.results)
                    :name "string-entity-text-search-results"
                    :show-head false
                    :paginate false
                    :fill-width true
                    :scroll true
                    :builder (fn [item child-ctx]
                               (local result (. item 1))
                               (local label (tostring (. item 2)))
                               ((Button {:text label
                                         :variant :ghost
                                         :on-click (fn [_button _event]
                                                     (target:open-result result))})
                                child-ctx))}) build-ctx))
      (local query-row ((Flex {:axis 1
                               :xspacing 0.3
                               :xalign :stretch
                               :children [(FlexChild (fn [_] input) 1)
                                          (FlexChild (fn [_] search-button) 0)]}) build-ctx))
      (local root ((Flex {:axis 2
                          :xalign :stretch
                          :yspacing 0.3
                          :children [(FlexChild (fn [_] query-row) 0)
                                     (FlexChild (fn [_] status-text) 0)
                                     (FlexChild (fn [_] results-list) 1)]}) build-ctx))
      (set view.input input)
      (set view.search-button search-button)
      (set view.status-text status-text)
      (set view.results-list results-list)
      (set view.layout root.layout)
      (local results-handler (fn [results] (results-list:set-items (result-items results))))
      (local status-handler (fn [status] (status-text:set-text status)))
      (target.results-changed:connect results-handler)
      (target.status-changed:connect status-handler)
      (set view.drop
           (fn [_self]
             (target.results-changed:disconnect results-handler true)
             (target.status-changed:disconnect status-handler true)
             (root:drop)))
      view))

  StringEntitySearchNodeView
  ```

- [ ] **Step 8: Validate Task 3**

  Run:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/views/string-entity-search.fnl --file assets/lua/graph/nodes/string-entity-list.fnl --file assets/lua/graph/view/views/string-entity-list.fnl --file assets/lua/tests/test-string-entity-search.fnl --file assets/lua/tests/test-string-entities.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-string-entity-search:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-string-entities:main
  ```

  Expected: compile check passes, constraints pass, focused search tests pass, and adjacent string entity tests pass.

- [ ] **Step 9: Review handoff checkpoint**

  Report changed files, RED evidence, validation results, and any constraint impact. Do not commit until the reviewer gate passes.

---

### Task 4: Documentation and full relevant validation

**Files:**
- Create: `docs/dev/features/string-entity-full-text-search.md`
- Modify: `assets/lua/tests/fast.fnl` only if Task 1 did not already register the new focused test.

**Interfaces:**
- Consumes: backend contract, graph node key, and view behavior from Tasks 1-3.
- Produces: developer documentation describing the runtime-state rule, backend seam, and result materialization behavior.

- [ ] **Step 1: Write developer documentation**

  Create `docs/dev/features/string-entity-full-text-search.md` with this structure and concrete content.

  ```markdown
  # String Entity Full-Text Search

  String entity full-text search is exposed through the graph node key
  `string-entity-search`. The node is a UX-purpose search surface: it owns
  runtime query, status, and result state, but it owns no string entity records.

  The string entity store remains the source of truth. GraphMap topology stores
  only explicit visible nodes and edges, so search query text and result rows are
  not written into graph capture state.

  ## Backend contract

  Search nodes consume a backend with:

  ```text
  backend:search-text(query, callback) -> token|nil
  ```

  The callback receives `{:ok boolean :query string :results table :stderr string|nil :error string|nil}`.
  Result rows use `{:entity-id string :entity table :matches table :match-count number}`.

  ## Ripgrep backend

  The initial backend uses `ripgrep.fnl` with fixed-string, case-insensitive
  search. It searches only `store.entities-dir`, only `*.md` files, and maps
  `<id>.md` paths back to string entity IDs through `store:get-entity`.

  ## Result opening

  Selecting a result loads `string-entity:<id>` into the active `GraphMap`.
  It does not create a `LinkEntity`, does not author a domain relationship, and
  does not silently expand every matching entity.
  ```

- [ ] **Step 2: Compile all touched Fennel files**

  Run:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/entities/string-search.fnl --file assets/lua/graph/nodes/string-entity-search.fnl --file assets/lua/graph/view/views/string-entity-search.fnl --file assets/lua/graph/nodes/string-entity-list.fnl --file assets/lua/graph/view/views/string-entity-list.fnl --file assets/lua/graph/extensions/builtins/entities.fnl --file assets/lua/tests/test-string-entity-search.fnl --file assets/lua/tests/test-string-entities.fnl --file assets/lua/tests/fast.fnl
  ```

  Expected: compile check passes with zero diagnostics.

- [ ] **Step 3: Run constraints**

  Run:

  ```bash
  make constraints
  ```

  Expected: constraints pass. Any new or shifted baseline entry must be explained and reviewed; do not bypass violations.

- [ ] **Step 4: Run focused and adjacent Fennel tests**

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-string-entity-search:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-string-entities:main
  ```

  Expected: both focused modules pass.

- [ ] **Step 5: Run relevant broader fast suite**

  Because this changes built-in graph loader registration, graph map materialization, UI widgets, and the fast test module list, run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.fast:main
  ```

  Expected: fast suite passes.

- [ ] **Step 6: Broader validation for integration readiness**

  Before finishing the development branch, run the full local gate if runtime/build state permits:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: full suite passes. If any validation fails, invoke systematic debugging before proposing fixes.

- [ ] **Step 7: Review handoff checkpoint**

  Report documentation path, validation results, and any known risk. Do not commit until the reviewer gate passes.

---

## Self-Review Notes

- Spec coverage: the plan covers the `Search Text` entry point, exact search node key, runtime-only query/results, ripgrep backend behavior, backend abstraction for another implementation, result ID mapping, result materialization through `GraphMap`, no domain links, error handling, and validation requirements.
- Placeholder scan: no incomplete-marker or open-ended implementation placeholders are intentionally present.
- Type consistency: backend, node, and view method names are consistent across tasks: `RipgrepStringEntitySearchBackend`, `search-text`, `results-changed`, `status-changed`, `open-result`, and `add-search-node`.
