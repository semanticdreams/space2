# Graph Outline View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an alternate compact indented outline view mode for the active `GraphMap`, with per-map roots and outgoing-edge traversal.

**Architecture:** Keep the existing spatial graph renderer intact and add a separate outline renderer selected from the public `graph/view` module by `graph-map.view_mode`. Store outline interaction state on `GraphMap`, derive outline rows with a pure projection module, and share non-spatial node action/focus behavior between spatial and outline renderers.

**Tech Stack:** Space Fennel modules under `assets/lua`, Graph/GraphMap/GraphView, existing widget/build-context systems, existing Fennel fast test harness.

## Global Constraints

- This is an alternate view mode for the same active `GraphMap`, not a companion panel.
- `Graph` remains an exposure/adaptor layer and must not persist outline state.
- `GraphMap` owns map-local `view_mode` and `outline_root_keys` interaction state.
- The outline projection follows outgoing graph-map edges only.
- Graph-map nodes unreachable from current outline roots are hidden in outline mode without being removed from the map.
- Cycles and shared nodes use first occurrence wins; later encounters of an already emitted node are skipped.
- Initial rows are compact only; inline preview cards remain spatial-only.
- Child ordering follows graph-map edge insertion/order with a deterministic label/key fallback when needed.
- Root state is an ordered list internally; initial UI sets/replaces it with one focused or singly selected node.
- Graph-map selection and focus remain node-key-based.
- User-initiated invalid or ambiguous root-setting must surface explicit graph-native status or fail loudly; do not silently choose.
- Use project Fennel idioms: `local`, factory functions, multi-branch `if`, no `.new` constructors for new code.
- Validation order for Fennel work is compile check, constraints, focused tests, broader suite when justified.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- Direct Fennel test commands must set `SPACE_ASSETS_PATH=$(pwd)/assets`, `FENNEL_PATH=$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl`, `FENNEL_MACRO_PATH=$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl`, `SPACE_DISABLE_AUDIO=1`, `XDG_DATA_HOME=/tmp/space/tests/xdg-data`, and `SKIP_KEYRING_TESTS=1`.

---

## File Structure

- `assets/lua/graph/outline.fnl`: pure outline projection over a `GraphMap`; no widgets, no graph mutation, no persistence writes.
- `assets/lua/graph/map.fnl`: map-local outline state, signals, normalization, capture/restore, pruning on removal/clear.
- `assets/lua/graph/map-manager.fnl`: carries `view_mode` and `outline_root_keys` through map records, hydration, switching, and capture.
- `assets/lua/graph/view.fnl`: public graph view factory; dispatches to spatial `graph/view/init` or outline `graph/view/outline`.
- `assets/lua/graph/view/init.fnl`: existing spatial renderer; stays the spatial implementation and delegates reusable node/focused actions to helper modules.
- `assets/lua/graph/view/node-actions.fnl`: shared node action construction for spatial and outline renderers.
- `assets/lua/graph/view/focused-actions.fnl`: shared focused-node command method installer for view-compatible objects.
- `assets/lua/graph/view/outline.fnl`: outline renderer/controller; owns row widgets, focus/click integration, and node-view opening.
- `assets/lua/graph/commands.fnl`: graph leader commands for toggling outline mode and setting root from focus/selection.
- `assets/lua/graph-activity-unit.fnl`: reconnects/rebuilds the active graph renderer when the active map's view mode changes.
- `assets/lua/tests/test-graph-outline-view.fnl`: focused tests for projection, map state, renderer behavior, and commands introduced here.
- `assets/lua/tests/fast.fnl`: includes `:tests.test-graph-outline-view` in the fast suite after the new test module passes directly.
- `docs/dev/graph-maps.md`: documents per-map outline state and traversal contract.
- `docs/dev/notes/graph.md`: documents outline projection/rendering ownership under graph doctrine.

---

### Task 1: GraphMap Outline State and Pure Projection

**Files:**
- Create: `assets/lua/graph/outline.fnl`
- Modify: `assets/lua/graph/map.fnl`
- Modify: `assets/lua/graph/map-manager.fnl`
- Create: `assets/lua/tests/test-graph-outline-view.fnl`

**Interfaces:**
- Consumes: `GraphMap.nodes`, `GraphMap.edges`, `GraphMap:lookup(key)`, `GraphMap:capture-state()`, `GraphMap:restore-state(state)`.
- Produces: `GraphOutline.build-rows(graph-map, root-keys) -> rows`.
- Produces row shape: `{:key string :node table :depth number :parent-key string-or-nil}`.
- Produces GraphMap fields: `view_mode`, `outline_root_keys`, `view-mode-changed`, `outline-roots-changed`.
- Produces GraphMap methods: `set-view-mode!`, `set-outline-root-keys!`, `get-outline-root-keys`.

- [ ] **Step 1: Add the projection test module skeleton**

  Create `assets/lua/tests/test-graph-outline-view.fnl` with graph/map helpers and a runnable test module:

  ```fennel
  (local Graph (require :graph/init))
  (local GraphMap (require :graph/map))
  (local Edge (require :graph/edge))
  (local GraphOutline (require :graph/outline))

  (local tests [])

  (fn register-test-loader [graph]
      (graph:register-key-loader "test"
          (fn [key]
              (Graph.GraphNode {:key key
                                :label key})))
      graph)

  (fn make-map []
      (local graph (register-test-loader (Graph {:with-start false})))
      (local graph-map (GraphMap.GraphMap {:graph graph :id "outline-test" :name "Outline Test"}))
      {:graph graph :graph-map graph-map})

  (fn add-edge! [graph-map source-key target-key]
      (local source (or (graph-map:lookup source-key) (graph-map:load-by-key source-key)))
      (local target (or (graph-map:lookup target-key) (graph-map:load-by-key target-key)))
      (graph-map:add-edge (Edge.GraphEdge {:source source :target target})))

  (fn row-keys [rows]
      (icollect [_ row (ipairs rows)] row.key))

  (fn row-depths [rows]
      (icollect [_ row (ipairs rows)] row.depth))
  ```

- [ ] **Step 2: Write failing projection traversal tests**

  Add tests to the same file:

  ```fennel
  (fn outline-builds-reachable-outgoing-depth-first-rows []
      (local {:graph graph :graph-map graph-map} (make-map))
      (add-edge! graph-map "test:root" "test:a")
      (add-edge! graph-map "test:a" "test:a1")
      (add-edge! graph-map "test:root" "test:b")
      (graph-map:load-by-key "test:unreachable")
      (local rows (GraphOutline.build-rows graph-map ["test:root"]))
      (assert (= (table.concat (row-keys rows) ",") "test:root,test:a,test:a1,test:b")
              "outline should include only outgoing reachable nodes in depth-first order")
      (assert (= (table.concat (row-depths rows) ",") "0,1,2,1")
              "outline should assign indentation depth from roots")
      (graph-map:drop)
      (graph:drop))

  (fn outline-skips-incoming-only-edges []
      (local {:graph graph :graph-map graph-map} (make-map))
      (add-edge! graph-map "test:parent" "test:root")
      (local rows (GraphOutline.build-rows graph-map ["test:root"]))
      (assert (= (table.concat (row-keys rows) ",") "test:root")
              "outline should not walk incoming edges")
      (graph-map:drop)
      (graph:drop))

  (fn outline-handles-cycles-and-shared-nodes-by-first-occurrence []
      (local {:graph graph :graph-map graph-map} (make-map))
      (add-edge! graph-map "test:root" "test:a")
      (add-edge! graph-map "test:a" "test:root")
      (add-edge! graph-map "test:root" "test:b")
      (add-edge! graph-map "test:b" "test:a")
      (local rows (GraphOutline.build-rows graph-map ["test:root"]))
      (assert (= (table.concat (row-keys rows) ",") "test:root,test:a,test:b")
              "outline should emit each key once at first occurrence")
      (graph-map:drop)
      (graph:drop))
  ```

- [ ] **Step 3: Write failing GraphMap state tests**

  Add tests for defaults, normalization, persistence, and pruning:

  ```fennel
  (fn graph-map-persists-outline-mode-and-roots []
      (local {:graph graph :graph-map graph-map} (make-map))
      (graph-map:load-by-key "test:root")
      (graph-map:load-by-key "test:child")
      (assert (= graph-map.view_mode "spatial") "GraphMap should default to spatial mode")
      (assert (= (length graph-map.outline_root_keys) 0) "GraphMap should default to no outline roots")
      (graph-map:set-view-mode! "outline")
      (graph-map:set-outline-root-keys! ["test:root" "test:missing" "test:root" "test:child"])
      (assert (= (table.concat graph-map.outline_root_keys ",") "test:root,test:child")
              "GraphMap should keep visible unique outline roots in input order")
      (local state (graph-map:capture-state))
      (local restored (GraphMap.GraphMap {:graph graph :id "restored-outline"}))
      (restored:restore-state state)
      (assert (= restored.view_mode "outline") "restore should keep outline mode")
      (assert (= (table.concat restored.outline_root_keys ",") "test:root,test:child")
              "restore should keep valid outline roots")
      (restored:drop)
      (graph-map:drop)
      (graph:drop))

  (fn graph-map-prunes-removed-outline-roots []
      (local {:graph graph :graph-map graph-map} (make-map))
      (local root (graph-map:load-by-key "test:root"))
      (graph-map:load-by-key "test:child")
      (graph-map:set-outline-root-keys! ["test:root" "test:child"])
      (graph-map:remove-nodes [root])
      (assert (= (table.concat graph-map.outline_root_keys ",") "test:child")
              "removing a node should prune matching outline roots")
      (graph-map:drop)
      (graph:drop))
  ```

- [ ] **Step 4: Register tests in the module footer**

  Add the test list and entrypoint:

  ```fennel
  (table.insert tests {:name "outline builds reachable outgoing depth-first rows" :fn outline-builds-reachable-outgoing-depth-first-rows})
  (table.insert tests {:name "outline skips incoming-only edges" :fn outline-skips-incoming-only-edges})
  (table.insert tests {:name "outline handles cycles and shared nodes by first occurrence" :fn outline-handles-cycles-and-shared-nodes-by-first-occurrence})
  (table.insert tests {:name "graph map persists outline mode and roots" :fn graph-map-persists-outline-mode-and-roots})
  (table.insert tests {:name "graph map prunes removed outline roots" :fn graph-map-prunes-removed-outline-roots})

  (fn main []
      {:name "graph-outline-view" :tests tests})

  {:main main}
  ```

- [ ] **Step 5: Run the new focused test and verify it fails for missing implementation**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-outline-view:main
  ```

  Expected: fail because `graph/outline` and GraphMap outline APIs do not exist yet.

- [ ] **Step 6: Create `assets/lua/graph/outline.fnl`**

  Implement a pure module with this API:

  ```fennel
  (fn node-key [node-or-key]
      (if (= (type node-or-key) :string)
          node-or-key
          (and node-or-key node-or-key.key)))

  (fn node-label [node]
      (tostring (or (and node node.label) (and node node.key) "")))

  (fn normalize-root-keys [graph-map root-keys]
      (local result [])
      (local seen {})
      (each [_ key (ipairs (or root-keys []))]
          (when (and (= (type key) :string) (not (. seen key)) (graph-map:lookup key))
              (set (. seen key) true)
              (table.insert result key)))
      result)

  (fn build-child-index [graph-map]
      (local index {})
      (local seen-by-source {})
      (each [_ edge (ipairs graph-map.edges)]
          (local source-key (node-key edge.source))
          (local target-key (node-key edge.target))
          (when (and source-key target-key (graph-map:lookup source-key) (graph-map:lookup target-key))
              (when (not (. index source-key))
                  (set (. index source-key) [])
                  (set (. seen-by-source source-key) {}))
              (when (not (. (. seen-by-source source-key) target-key))
                  (set (. (. seen-by-source source-key) target-key) true)
                  (table.insert (. index source-key) target-key))))
      index)

  (fn build-rows [graph-map root-keys]
      (local rows [])
      (local visited {})
      (local child-index (build-child-index graph-map))
      (fn visit [key depth parent-key]
          (when (and (graph-map:lookup key) (not (. visited key)))
              (set (. visited key) true)
              (table.insert rows {:key key :node (graph-map:lookup key) :depth depth :parent-key parent-key})
              (each [_ child-key (ipairs (or (. child-index key) []))]
                  (visit child-key (+ depth 1) key))))
      (each [_ key (ipairs (normalize-root-keys graph-map root-keys))]
          (visit key 0 nil))
      rows)

  {:build-rows build-rows
   :normalize-root-keys normalize-root-keys}
  ```

  Complete `build-child-index` by iterating `graph-map.edges` with `ipairs`, extracting source and target keys via `edge.source`, `edge.target`, and node key helpers, keeping only visible endpoints, and deduping target keys per source. Complete `build-rows` with depth-first traversal, a global `visited` table, and `parent-key` values.

- [ ] **Step 7: Extend `assets/lua/graph/map.fnl` with outline state**

  Add `view_mode`, `outline_root_keys`, `view-mode-changed`, and `outline-roots-changed` to the `self` literal. Add methods with these contracts:

  ```fennel
  (fn set-view-mode! [self mode]
      (assert (or (= mode "spatial") (= mode "outline")) "GraphMap view mode must be spatial or outline")
      (when (not= self.view_mode mode)
          (set self.view_mode mode)
          (self.view-mode-changed:emit mode))
      self.view_mode)

  (fn set-outline-root-keys! [self keys]
      (local normalized (normalize-outline-root-keys self keys))
      (when (not (same-array? self.outline_root_keys normalized))
          (set self.outline_root_keys normalized)
          (self.outline-roots-changed:emit (copy-array normalized)))
      (copy-array self.outline_root_keys))

  (fn get-outline-root-keys [self]
      (copy-array self.outline_root_keys))
  ```

  Add local helpers `copy-array`, `same-array?`, and `normalize-outline-root-keys` near existing selection-key helpers. `normalize-outline-root-keys` must keep only visible string keys, preserve input order, and dedupe by first occurrence.

  Update `capture-state` to include `:view_mode self.view_mode` and `:outline_root_keys (self:get-outline-root-keys)`. Update `restore-state` after node restore to call setters with defaults of `"spatial"` and `[]`. Update node removal and clear paths so removed node keys are pruned from `outline_root_keys`.

- [ ] **Step 8: Thread outline state through `assets/lua/graph/map-manager.fnl`**

  Carry `view_mode` and `outline_root_keys` through map record creation, hydration, active map capture, inactive map persisted state, new map defaults, and switch flows. Legacy records without these fields must become `"spatial"` and `[]`.

- [ ] **Step 9: Run Task 1 validation**

  If `./build/space` is missing or stale, run `make build` with timeout `14400000`.

  Run:

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-outline-view:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map-manager:main
  ```

  Expected: pass. Constraint-impact note: changed, because GraphMap outline fields add graph-map state shape that constraints may inspect.

---

### Task 2: Shared Actions and Outline Renderer

**Files:**
- Create: `assets/lua/graph/view/node-actions.fnl`
- Create: `assets/lua/graph/view/focused-actions.fnl`
- Create: `assets/lua/graph/view/outline.fnl`
- Modify: `assets/lua/graph/view.fnl`
- Modify: `assets/lua/graph/view/init.fnl`
- Modify: `assets/lua/tests/test-graph-outline-view.fnl`
- Modify: `assets/lua/tests/test-graph-view.fnl`

**Interfaces:**
- Consumes: `GraphOutline.build-rows(graph-map, root-keys)`, `GraphMap:set-selected-node-keys!(keys)`, `GraphMap.focused_node_key`, `GraphViewNodeViews`.
- Produces: `GraphNodeActions.build(opts, node) -> actions`.
- Produces: `FocusedActions.install!(view, deps) -> view`.
- Produces: `GraphOutlineView(options) -> GraphView-compatible object`.
- Produces: public `graph/view` factory dispatching to spatial or outline by `graph-map.view_mode`.

- [ ] **Step 1: Add renderer behavior tests before implementation**

  Extend `assets/lua/tests/test-graph-outline-view.fnl` with tests that construct the public graph view factory:

  ```fennel
  (local GraphView (require :graph/view))

  (fn make-render-ctx []
      {:triangle-vector {:add (fn [_] {:drop (fn [_])})}
       :points {:add (fn [_] {:drop (fn [_])})}
       :clickables {:register (fn [_ _] {:drop (fn [_])})}
       :focus {:create-scope (fn [_ _] {:drop (fn [_])})}})

  (fn outline-view-exposes-visible-row-selection []
      (local {:graph graph :graph-map graph-map} (make-map))
      (add-edge! graph-map "test:root" "test:child")
      (graph-map:set-view-mode! "outline")
      (graph-map:set-outline-root-keys! ["test:root"])
      (local view (GraphView {:graph-map graph-map :ctx (make-render-ctx)}))
      (assert (= (view:selected-node-count) 0) "outline view should start with no selected rows")
      (view:reveal-node "test:child" {:select? true :focus? true})
      (assert (= graph-map.focused_node_key "test:child") "outline reveal should focus visible rows")
      (assert (= (table.concat graph-map.selected_node_keys ",") "test:child") "outline reveal should select visible rows")
      (view:drop)
      (graph-map:drop)
      (graph:drop))

  (fn outline-view-rejects-unreachable-reveal []
      (local {:graph graph :graph-map graph-map} (make-map))
      (graph-map:load-by-key "test:root")
      (graph-map:load-by-key "test:other")
      (graph-map:set-view-mode! "outline")
      (graph-map:set-outline-root-keys! ["test:root"])
      (local view (GraphView {:graph-map graph-map :ctx (make-render-ctx)}))
      (local ok message (pcall (fn [] (view:reveal-node "test:other" {:select? true}))))
      (assert (not ok) "outline reveal should fail for hidden map nodes")
      (assert (string.find (tostring message) "not visible") "outline reveal error should explain visibility")
      (view:drop)
      (graph-map:drop)
      (graph:drop))
  ```

- [ ] **Step 2: Extract node action construction into `graph/view/node-actions.fnl`**

  Move the spatial renderer's existing local node action construction into a helper with this module shape. The body of `build` is the moved spatial action assembly; the only new branch is that preview-related actions are appended only when `include-preview?` is true:

  ```fennel
  (fn build [opts node]
      (local graph-map (assert opts.graph-map "GraphNodeActions.build requires :graph-map"))
      (local include-preview? (not= opts.include-preview-action? false))
      (local actions [])
      (when include-preview?
          (append-preview-actions! actions opts node))
      (append-open-copy-remove-and-node-actions! actions opts node graph-map)
      (table.insert actions {:label "Set Outline Root"
                             :run (fn [] (graph-map:set-outline-root-keys! [node.key]) true)})
      actions)

  {:build build}
  ```

  `append-preview-actions!` and `append-open-copy-remove-and-node-actions!` can be private helper names or inlined code, but their behavior must come from the existing spatial action assembly so existing spatial menu order and labels remain unchanged except for the added `Set Outline Root` action.

  Preserve existing spatial actions exactly, add `Set Outline Root` to call `(graph-map:set-outline-root-keys! [node.key])`, and make outline callers pass `{:include-preview-action? false}`.

- [ ] **Step 3: Extract focused action methods into `graph/view/focused-actions.fnl`**

  Move focused-node command method installation into this module shape. The installed methods must use the same logic as the current spatial local installer, with preview toggling conditional on the supplied dependency:

  ```fennel
  (fn install! [view deps]
      (assert view "FocusedActions.install! requires view")
      (assert deps.focused-node "FocusedActions.install! requires :focused-node")
      (set view.focused-node (fn [self] (deps.focused-node self)))
      (set view.has-focused-node? (fn [self] (if (self:focused-node) true false)))
      (set view.focused-node-actions (fn [self] (deps.focused-node-actions self)))
      (set view.run-focused-node-action-slot (fn [self slot] (deps.run-focused-node-action-slot self slot)))
      (set view.open-focused-node-menu (fn [self] (deps.open-focused-node-menu self)))
      (set view.copy-focused-node-key (fn [self] (deps.copy-focused-node-key self)))
      (set view.remove-focused-node-from-map (fn [self] (deps.remove-focused-node-from-map self)))
      (set view.reveal-focused-node (fn [self opts] (deps.reveal-focused-node self opts)))
      (when deps.toggle-node-presentation
          (set view.toggle-focused-node-preview
               (fn [self] (deps.toggle-node-presentation self))))
      view)

  {:install! install!}
  ```

  Preserve method names consumed by `assets/lua/graph/commands.fnl`.

- [ ] **Step 4: Update spatial `graph/view/init.fnl` to use helpers**

  Require `graph/view/node-actions` and `graph/view/focused-actions`. Replace local duplicated action/focused method code with helper calls. Spatial mode must pass `include-preview-action? true` and provide the existing preview toggle dependency.

- [ ] **Step 5: Implement `assets/lua/graph/view/outline.fnl`**

  Build a GraphView-compatible controller with at least these methods:

  ```fennel
  (fn GraphOutlineView [options]
      (local graph-map (assert options.graph-map "GraphOutlineView requires :graph-map"))
      (local ctx (assert options.ctx "GraphOutlineView requires :ctx"))
      (local node-views (GraphViewNodeViews {:graph-map graph-map :ctx ctx :data-dir options.data-dir}))
      (local self {:graph-map graph-map
                   :rows []
                   :row-by-key {}
                   :node-views node-views
                   :connections []
                   :row-handles []})
      self)
  ```

  Add private helpers in the module for `rebuild-rows!`, `drop-row-handles!`, `visible-key?`, `select-key!`, and `open-key!`. Connect `node-added`, `node-removed`, `edge-added`, `edge-removed`, and `outline-roots-changed` to `rebuild-rows!`, storing disconnect handles in `self.connections`.

  Required behavior:
  - `rebuild-rows!` calls `GraphOutline.build-rows graph-map graph-map.outline_root_keys`.
  - Row click selects and focuses the row's node key.
  - Row activation and `open-node` delegate to `GraphViewNodeViews` using existing node-view behavior.
  - Right-click/action menu uses `GraphNodeActions.build` with preview disabled.
  - `selected-node-count` reports selected keys visible in the current row set.
  - `select-all-visible-nodes` selects row keys only.
  - `reveal-node` accepts a node table or key, updates focus/selection for visible rows, and errors with text containing `not visible` for hidden keys.
  - `expand-focused-node` opens the focused node instead of toggling inline preview.
  - `drop` disconnects signals and drops row widgets/focus/clickable handles.

- [ ] **Step 6: Dispatch in public `assets/lua/graph/view.fnl`**

  Replace the current one-line require with a factory:

  ```fennel
  (local SpatialGraphView (require :graph/view/init))
  (local GraphOutlineView (require :graph/view/outline))

  (fn GraphView [options]
      (local graph-map (assert options.graph-map "GraphView requires :graph-map"))
      (if (= graph-map.view_mode "outline")
          (GraphOutlineView options)
          (SpatialGraphView options)))

  GraphView
  ```

- [ ] **Step 7: Run Task 2 validation**

  If `./build/space` is missing or stale, run `make build` with timeout `14400000`.

  Run:

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-outline-view:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  ```

  Expected: pass. Constraint-impact note: changed, because GraphView helper extraction and outline renderer add view modules.

---

### Task 3: Commands, Activity Rebuild, and Fast Test Registration

**Files:**
- Modify: `assets/lua/graph/commands.fnl`
- Modify: `assets/lua/graph-activity-unit.fnl`
- Modify: `assets/lua/tests/test-graph-outline-view.fnl`
- Modify: `assets/lua/tests/test-graph-selection-focus-command.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `GraphMap:set-view-mode!(mode)`, `GraphMap:set-outline-root-keys!(keys)`, `graph-map.view-mode-changed`, `GraphView:focused-node()`, `GraphView:selected-node-count()`.
- Produces command: `graph.view.toggle-outline`.
- Produces command: `graph.outline.set-root-from-current`.
- Produces bindings: `SPC g v o` for toggle, `SPC g o r` for set root from current.
- Produces activity behavior: active graph view rebuilds when active map view mode changes.

- [ ] **Step 1: Add command tests**

  Extend `assets/lua/tests/test-graph-outline-view.fnl` with command-level cases using the existing command provider patterns from `test-graph-selection-focus-command.fnl`:

  ```fennel
  (local GraphCommands (require :graph/commands))
  (var command-graph-view nil)
  (var command-graph-map nil)

  (fn resolve-command-graph-view [] command-graph-view)
  (fn resolve-command-graph-map [] command-graph-map)

  (fn find-binding [bindings expected]
      (var found nil)
      (each [_ binding (ipairs bindings) &until found]
          (when (= binding.command expected)
              (set found binding)))
      found)

  (fn command-toggle-outline-flips-view-mode []
      (local {:graph graph :graph-map graph-map} (make-map))
      (set command-graph-map graph-map)
      (set command-graph-view {:graph-map graph-map})
      (local provider (GraphCommands.provider {:graph-view resolve-command-graph-view
                                               :graph-map resolve-command-graph-map}))
      (local binding (assert (find-binding provider.bindings "graph.view.toggle-outline") "outline toggle binding missing"))
      (assert (= (. binding.keys 1) "g") "outline toggle binding should live under graph leader")
      (local command (assert (. provider.commands "graph.view.toggle-outline") "outline toggle command missing"))
      (assert (= (command:run {}) true) "toggle command should run")
      (assert (= graph-map.view_mode "outline") "toggle should enter outline mode")
      (assert (= (command:run {}) true) "toggle command should run twice")
      (assert (= graph-map.view_mode "spatial") "toggle should return to spatial mode")
      (graph-map:drop)
      (graph:drop))

  (fn command-set-outline-root-prefers-focused-node []
      (local {:graph graph :graph-map graph-map} (make-map))
      (graph-map:load-by-key "test:focused")
      (graph-map:load-by-key "test:selected")
      (set graph-map.focused_node_key "test:focused")
      (graph-map:set-selected-node-keys! ["test:selected"])
      (set command-graph-map graph-map)
      (set command-graph-view {:graph-map graph-map
                               :focused-node (fn [_self] (graph-map:lookup graph-map.focused_node_key))})
      (local provider (GraphCommands.provider {:graph-view resolve-command-graph-view
                                               :graph-map resolve-command-graph-map}))
      (local command (assert (. provider.commands "graph.outline.set-root-from-current") "set outline root command missing"))
      (assert (= (command:run {}) true) "set root command should run with focus")
      (assert (= (table.concat graph-map.outline_root_keys ",") "test:focused")
              "set root should prefer focused node over selection")
      (graph-map:drop)
      (graph:drop))

  (fn command-set-outline-root-uses-single-selection []
      (local {:graph graph :graph-map graph-map} (make-map))
      (graph-map:load-by-key "test:selected")
      (graph-map:set-selected-node-keys! ["test:selected"])
      (set command-graph-map graph-map)
      (set command-graph-view {:graph-map graph-map
                               :focused-node (fn [_self] nil)})
      (local provider (GraphCommands.provider {:graph-view resolve-command-graph-view
                                               :graph-map resolve-command-graph-map}))
      (local command (assert (. provider.commands "graph.outline.set-root-from-current") "set outline root command missing"))
      (assert (= (command:run {}) true) "set root command should run with one selected key")
      (assert (= (table.concat graph-map.outline_root_keys ",") "test:selected")
              "set root should use exactly one selected node when focus is absent")
      (graph-map:drop)
      (graph:drop))
  ```

  Use actual provider helpers already present in `test-graph-selection-focus-command.fnl` rather than adding a second command harness.

- [ ] **Step 2: Implement graph commands and bindings**

  In `assets/lua/graph/commands.fnl`, add:
  - `graph.view.toggle-outline`: reads the active graph map, sets `"outline"` when current mode is not outline, otherwise sets `"spatial"`.
  - `graph.outline.set-root-from-current`: chooses focused node key first; if none, accepts exactly one selected key; otherwise reports explicit status or returns unavailable according to the existing command API.
  - Leader bindings `SPC g v o` and `SPC g o r`.

  Do not add command aliases.

- [ ] **Step 3: Add activity rebuild handling**

  In `assets/lua/graph-activity-unit.fnl`, connect to the active map's `view-mode-changed` signal when a graph view is activated. On signal:
  1. capture applicable current view state;
  2. drop the current renderer;
  3. activate a new graph view for the same active graph map.

  Disconnect this handler in graph view drop, map switching, and activity deactivation paths. Store the disconnect handle on graph activity runtime state with a specific field such as `graph-view-mode-conn`.

- [ ] **Step 4: Register fast test module**

  Add `:tests.test-graph-outline-view` to `assets/lua/tests/fast.fnl` near existing graph tests after the direct test module passes.

- [ ] **Step 5: Run Task 3 validation**

  If `./build/space` is missing or stale, run `make build` with timeout `14400000`.

  Run:

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-outline-view:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-selection-focus-command:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
  ```

  Expected: pass. Constraint-impact note: changed, because graph command and activity lifecycle surfaces changed.

---

### Task 4: Documentation and Final Local Validation

**Files:**
- Modify: `docs/dev/graph-maps.md`
- Modify: `docs/dev/notes/graph.md`

**Interfaces:**
- Consumes: implemented `GraphMap` outline state, outline projection, outline renderer, graph commands, and activity rebuild behavior.
- Produces: documented ownership and behavior contract for future graph work.

- [ ] **Step 1: Update `docs/dev/graph-maps.md`**

  Add outline mode to the GraphMap-owned state sections:
  - `view_mode` is per `GraphMap` and defaults to `"spatial"`.
  - `outline_root_keys` is an ordered per-map root list.
  - Outline traversal follows outgoing visible graph-map edges only.
  - Unreachable graph-map nodes are hidden in outline mode but remain in the map.
  - Cycles/shared nodes use first occurrence wins.

- [ ] **Step 2: Update `docs/dev/notes/graph.md`**

  Add a short GraphView/GraphMap note:
  - outline rows are a `GraphMap` projection over graph-visible topology;
  - outline rendering is a `GraphView` runtime concern;
  - graph node adapters do not track view instances;
  - graph core still persists topology only.

- [ ] **Step 3: Run documentation terminology review**

  Run:

  ```bash
  rtk rg "outline_root_keys|view_mode|outline view|GraphMap|GraphView" docs/dev assets/lua/graph assets/lua/tests/test-graph-outline-view.fnl
  ```

  Expected: results use canonical terms: `GraphMap`, `GraphView`, graph node adapter, graph-visible object, and graph-map topology.

- [ ] **Step 4: Run final focused validation**

  If `./build/space` is missing or stale, run `make build` with timeout `14400000`.

  Run:

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-outline-view:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-map-manager:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-selection-focus-command:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
  ```

  Expected: pass.

- [ ] **Step 5: Run broader local validation before final integration**

  Because this feature changes graph view construction, graph activity lifecycle, command routing, and graph-map persistence, run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: pass. PR CI remains the full integration gate.

---

## Acceptance Criteria

- Users can toggle the active graph map between spatial and outline modes.
- Users can set the outline root from the focused node or exactly one selected node.
- Outline mode displays compact indented rows reachable from roots by outgoing graph-map edges.
- Nodes in cycles or shared paths appear only at their first traversal position.
- Unreachable graph-map nodes are hidden in outline mode without being removed from the map.
- Row selection/focus, full node-view opening, and node action menus work in outline mode.
- Each graph map restores its own view mode and outline roots when switching maps.
- Existing spatial graph behavior remains the default and existing graph tests remain green.

## Explicitly Out of Scope

- Companion/sidebar outline panel.
- Inline preview cards in outline mode.
- Multi-root editing UI beyond internal ordered root list support and one-root set/replace command.
- Graph edge reordering or topology editing from outline rows.
- Persisting outline state in graph core or graph node adapters.
- Hidden relationship expansion or automatic materialization of unreachable graph nodes.
