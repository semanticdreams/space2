# Graph Titlebar Kind Badges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add compact graph kind badges before titles in expanded preview cards and full node-view dialogs, while leaving compact graph points and persisted graph topology unchanged.

**Architecture:** Badge metadata is normalized on graph node adapters as presentation metadata, not topology state. A graph-level metadata helper handles badge normalization without depending on UI widgets; graph view/dialog modules consume the normalized metadata with a small titlebar badge builder. Shared dialog titlebars gain an optional prefix slot so full node views and future dialogs can place a widget before the title without duplicating titlebar layout.

**Tech Stack:** Space Fennel, graph node adapters, graph view presentation widgets, `Dialog`, `StatusBadge`, Flex layout, Space Fennel compile/constraints/tests.

## Global Constraints

- Expanded preview cards show a compact kind badge immediately before the title in the titlebar.
- Full node-view dialogs show the same kind badge immediately before the title in the titlebar.
- Compact graph points keep their current layered point rendering, colors, sizes, labels, selection rings, and focus outlines.
- Nodes without badge metadata still render valid titlebars with the existing title layout.
- Kind badges are graph node adapter presentation metadata.
- The graph core does not own badge semantics and does not persist badge data in graph topology state.
- `text`: required non-empty display text after normalization.
- Optional visual fields such as background and foreground colors may default from existing node presentation colors.
- An explicit `false` opt-out remains possible for adapters that should not show a badge.
- No centralized global kind taxonomy or style registry is required for this change.
- When an adapter does not provide explicit badge metadata, default badge text should be derived from the stable key scheme before the first `:` and uppercased, such as `fs:/tmp/a.txt` becoming `FS`.
- If a key has no scheme, the node should render without a badge unless the adapter provides one explicitly.
- Malformed explicit badge metadata should fail loudly during node construction or rendering with a clear error.
- Missing badge metadata is not an error and should preserve existing titlebar behavior.
- Use `local` instead of `let` in touched Fennel.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.

---

## File Structure

- Create `assets/lua/graph/kind-badge.fnl`: validates and normalizes graph adapter badge metadata; no widget or rendering dependencies.
- Create `assets/lua/graph/view/kind-badge.fnl`: converts normalized badge metadata into a `StatusBadge` titlebar builder for graph preview/view UI.
- Modify `assets/lua/graph/node-base.fnl`: attaches normalized `:kind-badge` metadata to graph node adapters.
- Modify `assets/lua/graph/view/presentation.fnl`: inserts a badge before preview-card title text when `node.kind-badge` is present.
- Modify `assets/lua/dialog.fnl`: adds a generic optional `:title-prefix` builder before the dialog title.
- Modify `assets/lua/graph/view/node-view-dialog-builder.fnl`: passes a graph badge title prefix into full node-view dialogs.
- Create `assets/lua/tests/test-graph-kind-badge.fnl`: focused graph badge behavior and regression tests.
- Modify `assets/lua/tests/fast.fnl`: registers the focused graph badge test module.
- Modify `docs/dev/notes/graph.md`: documents that kind badges are adapter presentation metadata, not persisted graph topology.

---

### Task 1: Normalize Badge Metadata on Graph Node Adapters

**Files:**
- Create: `assets/lua/graph/kind-badge.fnl`
- Create: `assets/lua/tests/test-graph-kind-badge.fnl`
- Modify: `assets/lua/graph/node-base.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `Graph.GraphNode(opts: table) -> node table`
- Produces: `KindBadge.normalize(opts: table) -> table|false|nil`
- Produces normalized badge shape: `{:text string :background-color glm.vec4 :foreground-color glm.vec4}`
- Produces graph node field: `node.kind-badge`, containing normalized table, explicit `false`, or `nil`

- [ ] **Step 1: Add the focused test module shell**

Create `assets/lua/tests/test-graph-kind-badge.fnl` with this structure:

```fennel
(local Graph (require :graph/init))
(local GraphMapModule (require :graph/map))
(local KindBadge (require :graph/kind-badge))
(local glm (require :glm))

(local GraphMap GraphMapModule.GraphMap)
(local tests [])

(fn approx [a b]
  (< (math.abs (- a b)) 1e-5))

(fn color= [a b]
  (and a b
       (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)
       (approx a.w b.w)))

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "graph-kind-badge" :tests tests}))

{:name "graph-kind-badge" :tests tests :main main}
```

- [ ] **Step 2: Add failing normalization tests**

Add these tests before `main` and register each with `table.insert`:

```fennel
(fn normalize-derives-uppercase-scheme []
  (local badge (KindBadge.normalize {:key "fs:/tmp/a.txt"
                                     :color (glm.vec4 0.3 0.6 1 1)}))
  (assert badge "scheme-bearing keys should derive a default badge")
  (assert (= badge.text "FS"))
  (assert (color= badge.background-color (glm.vec4 0.3 0.6 1 1))))

(fn normalize-no-scheme-is-nil []
  (assert (= (KindBadge.normalize {:key "start"}) nil)
          "keys without ':' should not derive badges"))

(fn normalize-explicit-false-opts-out []
  (assert (= (KindBadge.normalize {:key "fs:/tmp/a.txt" :value false}) false)
          "explicit false should suppress derived badges"))

(fn normalize-explicit-text-trims-without-changing-case []
  (local badge (KindBadge.normalize {:key "fs:/tmp/a.txt"
                                     :value {:text " File "
                                             :foreground-color (glm.vec4 1 1 0 1)}}))
  (assert (= badge.text "File"))
  (assert (color= badge.foreground-color (glm.vec4 1 1 0 1))))

(fn malformed-explicit-badge-fails-loudly []
  (each [_ value (ipairs [true {} {:text ""} {:text "  "}])]
    (local (ok err)
      (pcall (fn [] (KindBadge.normalize {:key "fs:/tmp/a.txt" :value value}))))
    (assert (not ok) "malformed explicit badge should fail")
    (assert (string.find (tostring err) "kind-badge" 1 true)
            (.. "expected clear kind-badge error, got " (tostring err)))))

(table.insert tests {:name "KindBadge derives uppercase scheme text"
                     :fn normalize-derives-uppercase-scheme})
(table.insert tests {:name "KindBadge omits badge for keys without scheme"
                     :fn normalize-no-scheme-is-nil})
(table.insert tests {:name "KindBadge explicit false opts out"
                     :fn normalize-explicit-false-opts-out})
(table.insert tests {:name "KindBadge explicit text trims without changing case"
                     :fn normalize-explicit-text-trims-without-changing-case})
(table.insert tests {:name "KindBadge malformed explicit metadata fails loudly"
                     :fn malformed-explicit-badge-fails-loudly})
```

- [ ] **Step 3: Add failing GraphNode adapter tests**

Add and register these tests:

```fennel
(fn graph-node-stores-normalized-derived-kind-badge []
  (local node (Graph.GraphNode {:key "fs:/tmp/a.txt"
                                :label "a.txt"
                                :color (glm.vec4 0.25 0.5 0.75 1)}))
  (assert node.kind-badge "GraphNode should store normalized badge metadata")
  (assert (= node.kind-badge.text "FS")))

(fn graph-node-preserves-explicit-kind-badge-opt-out []
  (local node (Graph.GraphNode {:key "fs:/tmp/a.txt" :kind-badge false}))
  (assert (= node.kind-badge false)
          "GraphNode should preserve explicit false opt-out"))

(table.insert tests {:name "GraphNode stores normalized derived kind-badge metadata"
                     :fn graph-node-stores-normalized-derived-kind-badge})
(table.insert tests {:name "GraphNode preserves explicit kind-badge opt-out"
                     :fn graph-node-preserves-explicit-kind-badge-opt-out})
```

- [ ] **Step 4: Run the focused test and verify it fails because the module is missing**

If `./build/space` is missing, first run `make build` with timeout `14400000`.

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-kind-badge:main
```

Expected: FAIL with a missing `graph/kind-badge` module or missing `KindBadge.normalize`.

- [ ] **Step 5: Implement `assets/lua/graph/kind-badge.fnl`**

Create a metadata-only helper. Do not require UI modules here.

```fennel
(local glm (require :glm))
(local Utils (require :graph/core/utils))

(local KindBadge {})
(local default-background (glm.vec4 0.35 0.38 0.42 1))
(local default-foreground (glm.vec4 0.96 0.97 1 1))

(fn trim [text]
  (string.match text "^%s*(.-)%s*$"))

(fn scheme-text [key]
  (when (= (type key) :string)
    (local colon-at (string.find key ":" 1 true))
    (when (and colon-at (> colon-at 1))
      (string.upper (string.sub key 1 (- colon-at 1))))))

(fn normalize-text [text]
  (assert (= (type text) :string)
          "kind-badge.text must be a non-empty string")
  (local normalized (trim text))
  (assert (> (string.len normalized) 0)
          "kind-badge.text must be a non-empty string")
  normalized)

(fn normalize-color [value fallback]
  (Utils.ensure-glm-vec4 value fallback))

(fn KindBadge.normalize [opts]
  (local options (or opts {}))
  (local value options.value)
  (local text
    (if (= value false)
        false
        (= value nil)
        (scheme-text options.key)
        (= (type value) :string)
        (normalize-text value)
        (= (type value) :table)
        (normalize-text value.text)
        (error "kind-badge must be false, string, or table")))
  (if (= text false)
      false
      text
      {:text text
       :background-color (normalize-color (and (= (type value) :table) value.background-color)
                                          (normalize-color (or options.color options.accent) default-background))
       :foreground-color (normalize-color (and (= (type value) :table) value.foreground-color)
                                          default-foreground)}
      nil))

KindBadge
```

- [ ] **Step 6: Attach normalized metadata in `assets/lua/graph/node-base.fnl`**

Require the helper and add `:kind-badge` to the final node literal:

```fennel
(local KindBadge (require :graph/kind-badge))
```

After `color` and `accent` are available:

```fennel
(local kind-badge
  (KindBadge.normalize {:key options.key
                        :value options.kind-badge
                        :color color
                        :accent accent}))
```

Then add:

```fennel
:kind-badge kind-badge
```

- [ ] **Step 7: Register the new test module in `assets/lua/tests/fast.fnl`**

Add `:tests.test-graph-kind-badge` near existing graph test modules, before `:tests.test-graph-core`.

- [ ] **Step 8: Run compile check first**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/kind-badge.fnl --file assets/lua/graph/node-base.fnl --file assets/lua/tests/test-graph-kind-badge.fnl --file assets/lua/tests/fast.fnl
```

Expected: PASS.

- [ ] **Step 9: Run constraints second**

```bash
make constraints
```

Expected: PASS.

- [ ] **Step 10: Run the focused test**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-kind-badge:main
```

Expected: PASS.

- [ ] **Step 11: Commit Task 1**

```bash
git add assets/lua/graph/kind-badge.fnl assets/lua/graph/node-base.fnl assets/lua/tests/test-graph-kind-badge.fnl assets/lua/tests/fast.fnl
git commit -m "feat(ui): normalize graph kind badges"
```

Constraint-impact line for handoff: not applicable to baseline data; this adds metadata normalization and tests.

---

### Task 2: Preserve Topology Persistence and Compact Point Behavior

**Files:**
- Modify: `assets/lua/tests/test-graph-kind-badge.fnl`

**Interfaces:**
- Consumes: `Graph.GraphNode(opts)` with `node.kind-badge`
- Consumes: `GraphMap {:graph graph :id string}` and `graph-map:capture-state()`
- Consumes: `GraphNodePresentation.compact-point(opts) -> LayeredPoint widget`
- Produces: tests proving badges are not graph topology and compact points ignore badge metadata

- [ ] **Step 1: Add GraphMap topology capture regression**

Add and register this test:

```fennel
(fn graph-map-capture-excludes-kind-badge-metadata []
  (local graph (Graph {:with-start false}))
  (graph:register-key-loader "test"
    (fn [key]
      (Graph.GraphNode {:key key :kind-badge {:text "Test"}})))
  (local graph-map (GraphMap {:graph graph :id "badge-topology"}))
  (local a (graph-map:load-by-key "test:a"))
  (local b (graph-map:load-by-key "test:b"))
  (graph-map:add-edge (Graph.GraphEdge {:source a :target b}))
  (local state (graph-map:capture-state))
  (assert (= state.kind-badge nil) "capture-state must not add top-level badge metadata")
  (assert (= (length state.nodes) 2) "capture-state should preserve node keys")
  (assert (= (. state.nodes 1) "test:a"))
  (assert (= (. state.nodes 2) "test:b"))
  (assert (= (length state.edges) 1) "capture-state should preserve edges")
  (assert (= (. state.edges 1 :kind-badge) nil) "captured edges must not include badges")
  (graph-map:drop)
  (graph:drop))

(table.insert tests {:name "GraphMap capture excludes kind-badge metadata"
                     :fn graph-map-capture-excludes-kind-badge-metadata})
```

- [ ] **Step 2: Add compact point invariant regression**

Add and register this test with a local points stub so it does not depend on rendering hardware:

```fennel
(fn make-points-stub []
  (local created [])
  (local stub {:created created})
  (set stub.create-point
       (fn [_self opts]
         (local point {:opts opts
                       :position opts.position
                       :color opts.color
                       :size opts.size
                       :depth-offset-index opts.depth-offset-index})
         (set point.set-position (fn [self position] (set self.position position)))
         (set point.set-position-values
              (fn [self x y z]
                (set self.position (glm.vec3 x y z))))
         (set point.set-color (fn [self color] (set self.color color)))
         (set point.set-size (fn [self size] (set self.size size)))
         (set point.set-depth-offset-index
              (fn [self depth] (set self.depth-offset-index depth)))
         (set point.intersect (fn [_self _ray] nil))
         (set point.drop (fn [_self] nil))
         (table.insert created point)
         point))
  stub)

(fn compact-point-ignores-kind-badge-metadata []
  (local GraphNodePresentation (require :graph/view/presentation))
  (local points (make-points-stub))
  (local node (Graph.GraphNode {:key "fs:/tmp/badged.txt"
                                :label "badged.txt"
                                :color (glm.vec4 0.1 0.2 0.3 1)
                                :size 11.0}))
  (local point-builder
    (GraphNodePresentation.compact-point
      {:points points
       :position (glm.vec3 1 2 3)
       :depth-offset-step 1
       :base-depth-offset-index 2
       :base-layer-index 3
       :layers [{:size 0 :color (glm.vec4 0.7 0.8 0.9 1)}
                {:size 0 :color (glm.vec4 0.4 0.5 0.6 1)}
                {:size node.size :color node.color}]}))
  (local point (point-builder {:points points}))
  (assert (= (length point.layers) 3) "compact point should keep three layers")
  (assert (= point.header-bar nil) "compact point should not gain titlebar UI")
  (assert (= point.kind-badge nil) "compact point should not copy badge metadata")
  (when point.drop (point:drop)))

(table.insert tests {:name "Compact point ignores kind-badge metadata"
                     :fn compact-point-ignores-kind-badge-metadata})
```

- [ ] **Step 3: Run compile check first**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-graph-kind-badge.fnl
```

Expected: PASS.

- [ ] **Step 4: Run constraints second**

```bash
make constraints
```

Expected: PASS.

- [ ] **Step 5: Run focused badge tests**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-kind-badge:main
```

Expected: PASS.

- [ ] **Step 6: Commit Task 2**

```bash
git add assets/lua/tests/test-graph-kind-badge.fnl
git commit -m "test(ui): lock graph badge invariants"
```

---

### Task 3: Render Badges in Expanded Preview Card Titlebars

**Files:**
- Create: `assets/lua/graph/view/kind-badge.fnl`
- Modify: `assets/lua/graph/view/presentation.fnl`
- Modify: `assets/lua/tests/test-graph-kind-badge.fnl`

**Interfaces:**
- Consumes: normalized `node.kind-badge`
- Produces: `GraphViewKindBadge.titlebar-builder(badge: table|false|nil, opts?: table) -> function|nil`
- Produces: preview-card header order `[badge, title, spacer, collapse, open, menu]` when a badge exists and `[title, spacer, collapse, open, menu]` otherwise

- [ ] **Step 1: Add titlebar badge builder test**

Add and register this test:

```fennel
(fn titlebar-builder-returns-nil-for-missing-or-opted-out-badges []
  (local ViewKindBadge (require :graph/view/kind-badge))
  (assert (= (ViewKindBadge.titlebar-builder nil) nil))
  (assert (= (ViewKindBadge.titlebar-builder false) nil)))

(table.insert tests {:name "Graph view kind badge builder omits missing badges"
                     :fn titlebar-builder-returns-nil-for-missing-or-opted-out-badges})
```

- [ ] **Step 2: Add expanded-card titlebar ordering tests**

Add these test helpers before the card tests:

```fennel
(fn make-icons-stub []
  (local glyph {:advance 1
                :planeBounds {:left 0 :right 1 :top 1 :bottom 0}
                :atlasBounds {:left 0 :right 1 :top 1 :bottom 0}})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {4242 glyph}
               :advance 1})
  (local stub {:font font
               :codepoints {:close_fullscreen 4242
                            :open_in_new 4242
                            :more_vert 4242
                            :table 4242
                            :code 4242
                            :close 4242}})
  (set stub.get
       (fn [self name]
         (local value (. self.codepoints name))
         (assert value (.. "Missing icon " name))
         value))
  (set stub.resolve
       (fn [self name]
         (local code (self:get name))
         {:type :font :codepoint code :font self.font}))
  stub)

(fn make-clickables-stub []
  {:register (fn [_self _obj] nil)
   :unregister (fn [_self _obj] nil)
   :register-right-click (fn [_self _obj] nil)
   :unregister-right-click (fn [_self _obj] nil)
   :register-double-click (fn [_self _obj] nil)
   :unregister-double-click (fn [_self _obj] nil)})

(fn make-hoverables-stub []
  {:register (fn [_self _obj] nil)
   :unregister (fn [_self _obj] nil)})

(fn make-ui-ctx []
  (local BuildContext (require :build-context))
  (local {: LayoutRoot} (require :layout))
  (local ctx (BuildContext {:layout-root (LayoutRoot {:log-dirt? false})
                            :clickables (make-clickables-stub)
                            :hoverables (make-hoverables-stub)}))
  (set ctx.icons (make-icons-stub))
  ctx)

(fn make-simple-widget [name]
  (local {: Layout} (require :layout))
  (local layout
    (Layout {:name name
             :measurer (fn [self] (set self.measure (glm.vec3 4 2 0)))
             :layouter (fn [_self] nil)}))
  {:layout layout :drop (fn [_self] (layout:drop))})

(fn tracked-preview []
  (fn [_node _opts]
    (fn [_ctx]
      (make-simple-widget "graph-kind-badge-preview"))))

(fn build-test-card [GraphNodePresentation node]
  (set node.preview (tracked-preview))
  ((GraphNodePresentation.card-builder
     {:node node
      :position (glm.vec3 0 0 0)
      :default-size (glm.vec3 32 18 0)
      :on-collapse (fn [] nil)
      :on-open (fn [_event] nil)
      :on-menu (fn [_event] nil)})
   (make-ui-ctx)))
```

Then add and register tests that assert these conditions after building a card with `GraphNodePresentation.card-builder`:

```fennel
(fn expanded-card-renders-kind-badge-before-title []
  (local GraphNodePresentation (require :graph/view/presentation))
  (local node (Graph.GraphNode {:key "fs:/tmp/a.txt" :label "a.txt"}))
  (local card (build-test-card GraphNodePresentation node))
  (assert card.header-kind-badge "badged card should expose header-kind-badge")
  (assert (= (. card.header-bar.children 1 :element) card.header-kind-badge)
          "badge should be first header child")
  (assert (= (. card.header-bar.children 2 :element) card.header-title)
          "title should immediately follow badge")
  (assert (= card.header-title-text "a.txt"))
  (card:drop))

(fn expanded-card-without-badge-keeps-existing-titlebar-structure []
  (local GraphNodePresentation (require :graph/view/presentation))
  (local node (Graph.GraphNode {:key "start" :label "Start"}))
  (local card (build-test-card GraphNodePresentation node))
  (assert (= node.kind-badge nil))
  (assert (= card.header-kind-badge nil))
  (assert (= (. card.header-bar.children 1 :element) card.header-title)
          "title should remain first header child without badge")
  (card:drop))
```

The helper definitions above are local to `assets/lua/tests/test-graph-kind-badge.fnl` and are shared by Task 4 dialog tests.

- [ ] **Step 3: Run focused test and verify it fails before production changes**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-kind-badge:main
```

Expected: FAIL because preview cards do not yet expose or render `header-kind-badge`.

- [ ] **Step 4: Implement `assets/lua/graph/view/kind-badge.fnl`**

Create the UI-only badge builder:

```fennel
(local StatusBadge (require :status-badge))

(local ViewKindBadge {})

(fn ViewKindBadge.titlebar-builder [badge opts]
  (local options (or opts {}))
  (if (or (= badge nil) (= badge false))
      nil
      (do
        (assert (= (type badge) :table) "kind-badge renderer requires normalized badge table")
        (assert badge.text "kind-badge renderer requires badge.text")
        (StatusBadge {:text badge.text
                      :color badge.background-color
                      :foreground badge.foreground-color
                      :scale (or options.scale 0.95)
                      :padding (or options.padding [0.22 0.08])}))))

ViewKindBadge
```

- [ ] **Step 5: Insert badge before title in `presentation.fnl`**

Modify only expanded-card titlebar rendering:

```fennel
(local ViewKindBadge (require :graph/view/kind-badge))
```

Inside `build-header-bar`, compute:

```fennel
(local badge-builder
  (ViewKindBadge.titlebar-builder node.kind-badge {:scale 0.9
                                                   :padding [0.18 0.06]}))
(local titlebar-children [])
(when badge-builder
  (table.insert titlebar-children (FlexChild badge-builder 0)))
(table.insert titlebar-children (FlexChild title-builder 0))
(table.insert titlebar-children (FlexChild spacer-builder 1))
```

Then append the existing collapse/open/menu buttons in the same order and with the same handlers.

After building `header-bar`, set:

```fennel
(set card.header-bar header-bar)
(set card.header-kind-badge (and badge-builder (. header-bar.children 1 :element)))
(set card.header-title (. header-bar.children (if badge-builder 2 1) :element))
(set card.header-title-text title-text)
```

Do not change `compact-point`.

- [ ] **Step 6: Run compile check first**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/kind-badge.fnl --file assets/lua/graph/view/presentation.fnl --file assets/lua/tests/test-graph-kind-badge.fnl
```

Expected: PASS.

- [ ] **Step 7: Run constraints second**

```bash
make constraints
```

Expected: PASS.

- [ ] **Step 8: Run focused badge tests and graph-view regressions**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-kind-badge:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="Graph expanded card" ./build/space -m tests.test-graph-view:main
```

Expected: PASS.

- [ ] **Step 9: Commit Task 3**

```bash
git add assets/lua/graph/view/kind-badge.fnl assets/lua/graph/view/presentation.fnl assets/lua/tests/test-graph-kind-badge.fnl
git commit -m "feat(ui): show graph badges on preview cards"
```

---

### Task 4: Render Badges in Full Node-View Dialog Titlebars

**Files:**
- Modify: `assets/lua/dialog.fnl`
- Modify: `assets/lua/graph/view/node-view-dialog-builder.fnl`
- Modify: `assets/lua/tests/test-graph-kind-badge.fnl`

**Interfaces:**
- Consumes: `Dialog(opts)`
- Produces: optional `Dialog` option `:title-prefix`, a builder function returning a widget with `.layout`
- Consumes: `ViewKindBadge.titlebar-builder(node.kind-badge, opts) -> function|nil`
- Produces: full node-view dialog titlebar order `[badge, title, spacer, actions]` when badged

- [ ] **Step 1: Add generic dialog prefix test**

Add this test using the `make-ui-ctx` and `make-simple-widget` helpers from Task 3:

```fennel
(fn dialog-title-prefix-renders-before-title []
  (local Dialog (require :dialog))
  (local Text (require :text))
  (local dialog
    ((Dialog {:title "Node"
              :title-prefix (fn [ctx] ((Text {:text "FS"}) ctx))
              :child (fn [_ctx] (make-simple-widget "body"))})
     (make-ui-ctx)))
  (local titlebar-card (. dialog.children 1 :element))
  (local title-flex (. titlebar-card.children 2))
  (assert (= (. title-flex.children 1 :element :text) "FS")
          "title prefix should be before title")
  (dialog:drop))
```

The assertion follows the current dialog structure used by `assets/lua/tests/test-dialog.fnl`: the built dialog is a vertical flex, child 1 is the titlebar card/stack, and stack child 2 is the titlebar flex.

- [ ] **Step 2: Add full node-view dialog badge test**

Add a focused test for `graph/view/node-view-dialog-builder.fnl`:

```fennel
(fn node-view-dialog-renders-kind-badge-before-title []
  (local Builder (require :graph/view/node-view-dialog-builder))
  (local node (Graph.GraphNode {:key "fs:/tmp/a.txt"
                                :label "a.txt"
                                :view (fn [_node]
                                        (fn [_ctx _opts]
                                          (make-simple-widget "node-view")))}))
  (local builder (Builder.make-dialog-builder node (node.view node) {}))
  (local dialog (builder (make-ui-ctx) {}))
  (assert dialog.title-kind-badge "node-view dialog should expose the title badge")
  (assert (= dialog.title-kind-badge-text "FS"))
  (dialog:drop))
```

- [ ] **Step 3: Run focused test and verify it fails before production changes**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-kind-badge:main
```

Expected: FAIL because `Dialog` does not yet support `:title-prefix` and node-view dialogs do not pass badges.

- [ ] **Step 4: Add optional `:title-prefix` to `assets/lua/dialog.fnl`**

Modify `Dialog` as follows:

```fennel
(when options.title-prefix
  (assert (= (type options.title-prefix) :function)
          "Dialog title-prefix must be a builder function"))

(local titlebar-children [])
(when options.title-prefix
  (table.insert titlebar-children (FlexChild options.title-prefix 0)))
(table.insert titlebar-children (FlexChild title 0))
```

Then keep spacer/action row insertion exactly as it is today. While touching this file, replace the existing `let` in `resolve-titlebar-color` with `local`/`do` form to match project Fennel style.

- [ ] **Step 5: Pass title prefix from node-view dialog builder**

Modify `assets/lua/graph/view/node-view-dialog-builder.fnl`:

```fennel
(local ViewKindBadge (require :graph/view/kind-badge))
```

Before constructing `Dialog`, compute:

```fennel
(local title-prefix
  (ViewKindBadge.titlebar-builder node.kind-badge {:scale 0.95
                                                   :padding [0.22 0.08]}))
```

Pass `:title-prefix title-prefix` into `Dialog`. After `dialog-instance` is built, expose diagnostic fields:

```fennel
(when title-prefix
  (set dialog-instance.title-kind-badge-text node.kind-badge.text))
```

Set `dialog-instance.title-kind-badge` by walking the current dialog structure: `(. dialog-instance.children 1 :element :children 2 :children 1 :element)`. Do not write badge data into panel or graph persistence state.

- [ ] **Step 6: Run compile check first**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/dialog.fnl --file assets/lua/graph/view/node-view-dialog-builder.fnl --file assets/lua/tests/test-graph-kind-badge.fnl
```

Expected: PASS.

- [ ] **Step 7: Run constraints second**

```bash
make constraints
```

Expected: PASS.

- [ ] **Step 8: Run focused and existing dialog/node-view tests**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-kind-badge:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-dialog:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hackernews-graph-view-node-views:main
```

Expected: PASS.

- [ ] **Step 9: Commit Task 4**

```bash
git add assets/lua/dialog.fnl assets/lua/graph/view/node-view-dialog-builder.fnl assets/lua/tests/test-graph-kind-badge.fnl
git commit -m "feat(ui): show graph badges on node view dialogs"
```

---

### Task 5: Graph Doctrine Documentation and Final Local Validation

**Files:**
- Modify: `docs/dev/notes/graph.md`

**Interfaces:**
- Consumes: normalized `node.kind-badge` metadata and graph view rendering behavior
- Produces: canonical documentation for graph kind badge ownership and persistence boundaries

- [ ] **Step 1: Update graph doctrine docs**

Add this subsection under the existing preview/view guidance in `docs/dev/notes/graph.md`:

```markdown
### Kind badges

Graph node adapters may expose `kind-badge` presentation metadata for preview-card and full node-view titlebars. Missing metadata derives compact badge text from a stable key scheme before the first `:` when one exists; explicit `false` opts out. Graph core and GraphMap persistence still capture topology only: node keys, edge source/target keys, and map-local interaction state. Badge text and colors remain render-time presentation metadata and must not be written into graph topology state.
```

- [ ] **Step 2: Run docs-focused searches**

```bash
rg "kind-badge|Kind badges|topology only|explicit `false` opts out" docs/dev/notes/graph.md
rg "kind-badge" assets/lua/graph assets/lua/tests docs/dev/notes/graph.md
```

Expected: both commands find the documentation and implementation references.

- [ ] **Step 3: Run full Fennel compile check**

```bash
make fennel-check
```

Expected: PASS.

- [ ] **Step 4: Run constraints**

```bash
make constraints
```

Expected: PASS.

- [ ] **Step 5: Run focused tests**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-kind-badge:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="Graph expanded card" ./build/space -m tests.test-graph-view:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-dialog:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hackernews-graph-view-node-views:main
```

Expected: PASS.

- [ ] **Step 6: Run broader local suite because shared dialog infrastructure changed**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Expected: PASS.

- [ ] **Step 7: Commit Task 5**

```bash
git add docs/dev/notes/graph.md
git commit -m "docs(graph): document kind badge presentation metadata"
```

Constraint-impact line for handoff: not applicable unless constraints require baseline updates, which should not be expected for this change.

---

## Final Review and Integration Notes

After all tasks pass implementation review, the supervisor must use the finishing-a-development-branch workflow before reporting completion. Required final checks include a clean worktree, current evaluation against `origin/main`, local validation evidence from Task 5, and then the repository default integration action: push the branch and create a PR targeting `main` if green.
