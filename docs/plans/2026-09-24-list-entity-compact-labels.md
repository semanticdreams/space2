# List Entity Compact Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Suppress collapsed graph compact labels for unnamed list entity nodes while preserving named list labels and all explicit raw-id access paths.

**Architecture:** Add a generic runtime presentation contract consumed by `graph/view/labels`: `node.compact-label == false` opts out, a string overrides the compact label base, and `nil` keeps the existing `node.label`/key fallback. `ListEntityNode` will populate and refresh `node.compact-label` from the custom list name only, leaving `node.label` unchanged for non-compact surfaces. Graph topology persistence remains unchanged because this is render-time node adapter metadata.

**Tech Stack:** Space Fennel (`assets/lua/**/*.fnl`), graph node adapters, graph view label rendering, project-native `./build/space` Fennel tools, `make constraints`, Fennel test runner.

## Global Constraints

- Do not change list entity persistence or storage schema.
- Do not remove raw keys from copy-key, preview, full-view, debugging, or other explicit access paths.
- Do not change ordered-list island layout, list item rendering, or list entity membership behavior.
- Do not change compact label behavior for other node families except as needed to support a generic opt-out mechanism.
- Do not persist compact-label presentation metadata into graph topology state.
- `node.compact-label == false` means `graph/view/labels` renders no compact label for that node.
- A non-nil string `node.compact-label` is the compact label text base.
- `nil` preserves current fallback behavior: compact labels use `node.label` or the node key.
- `compact-label == false` is the only opt-out sentinel.
- Empty strings should not be introduced by `ListEntityNode`; custom names should continue to be tested for non-empty content before becoming compact labels.
- Missing required graph view build context should continue to assert as it does today; this feature must not add silent UI fallbacks.
- Fennel validation must use project-native tools only: `tools.fennel-check`, `make constraints`, and Space runtime tests through `./build/space`.
- When `./build/space` may be missing or stale, run `make build` first.

---

## File Structure

- `assets/lua/graph/view/labels.fnl` owns compact graph label rendering and will learn the generic `compact-label` opt-out contract.
- `assets/lua/tests/test-graph-view-labels.fnl` covers the generic compact label renderer behavior.
- `assets/lua/graph/nodes/list-entity.fnl` remains the list entity graph node adapter and will expose runtime compact-label metadata derived from the backing list entity name.
- `assets/lua/tests/test-list-entities.fnl` covers list entity adapter metadata and refresh behavior.
- `docs/dev/notes/graph.md` documents compact-label metadata as render-time graph presentation metadata, not topology or domain storage.

### Task 1: GraphViewLabels Compact Label Contract

**Files:**
- Modify: `assets/lua/graph/view/labels.fnl`
- Test: `assets/lua/tests/test-graph-view-labels.fnl`

**Interfaces:**
- Consumes: Optional runtime node field `node.compact-label` with values `false`, string, or `nil`.
- Produces: `GraphViewLabels` behavior where `false` drops/skips the compact label span, a string uses that text as the compact label base before existing truncation/wrapping, and `nil` preserves existing fallback to `node.label` or node key.

- [ ] **Step 1: Add focused GraphViewLabels tests**

In `assets/lua/tests/test-graph-view-labels.fnl`, add this helper near the existing helpers:

```fennel
(fn codepoints->text [codepoints]
  (assert (= (type codepoints) :table) "codepoints->text requires codepoints")
  (local chars [])
  (each [_ codepoint (ipairs codepoints)]
    (table.insert chars (string.char codepoint)))
  (table.concat chars))
```

Add these tests after `labels-create-span-with-defaults`:

```fennel
(fn labels-use-compact-label-string-when-present []
  (local ctx (make-ctx))
  (local camera {:position (glm.vec3 0 0 0)})
  (local labels (GraphViewLabels {:ctx ctx :camera camera}))
  (local node (GraphNode {:key "compact-string" :label "Raw Fallback"}))
  (set node.compact-label "Friendly Name")
  (local point {:position (glm.vec3 0 0 0) :size 6})
  (local points {node point})
  (labels:update points [node] {:force? true})
  (local span (. labels.labels node))
  (assert span "compact-label string should create a text span")
  (assert (= (codepoints->text (span:get-codepoints)) "Friendly Name")
          "compact-label string should override node.label for compact labels")
  (labels:drop-all))

(fn labels-preserve-fallback-when-compact-label-missing []
  (local ctx (make-ctx))
  (local camera {:position (glm.vec3 0 0 0)})
  (local labels (GraphViewLabels {:ctx ctx :camera camera}))
  (local node (GraphNode {:key "fallback-key" :label "Fallback Label"}))
  (local point {:position (glm.vec3 0 0 0) :size 6})
  (local points {node point})
  (labels:update points [node] {:force? true})
  (local span (. labels.labels node))
  (assert span "missing compact-label should preserve existing label fallback")
  (assert (= (codepoints->text (span:get-codepoints)) "Fallback Label")
          "missing compact-label should render node.label")
  (labels:drop-all))

(fn labels-drop-span-when-compact-label-is-false []
  (local ctx (make-ctx))
  (local camera {:position (glm.vec3 0 0 0)})
  (local labels (GraphViewLabels {:ctx ctx :camera camera}))
  (local node (GraphNode {:key "list-entity:unnamed" :label "raw-list-id"}))
  (set node.compact-label "Temporary Name")
  (local point {:position (glm.vec3 0 0 0) :size 6})
  (local points {node point})
  (labels:update points [node] {:force? true})
  (assert (. labels.labels node) "test should start with an existing span")
  (set node.compact-label false)
  (labels:update points [node] {:force? true})
  (assert (not (. labels.labels node))
          "compact-label false should drop existing compact label span")
  (labels:drop-all))
```

Register them near the other label tests:

```fennel
(table.insert tests {:name "GraphView labels use compact-label string when present"
                     :fn labels-use-compact-label-string-when-present})
(table.insert tests {:name "GraphView labels preserve fallback when compact-label missing"
                     :fn labels-preserve-fallback-when-compact-label-missing})
(table.insert tests {:name "GraphView labels drop span when compact-label is false"
                     :fn labels-drop-span-when-compact-label-is-false})
```

- [ ] **Step 2: Run the focused test and verify it fails for the missing behavior**

Runtime/freshness prerequisite if needed:

```bash
make build
```

Then run:

```bash
SPACE_DISABLE_AUDIO=1 \
SKIP_KEYRING_TESTS=1 \
XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-graph-view-labels:main
```

Expected before implementation: at least the `compact-label false` and string override tests fail.

- [ ] **Step 3: Implement compact label resolution in `graph/view/labels.fnl`**

Replace the existing `label-text` helper with explicit compact-label resolution:

```fennel
(fn compact-label-base [node]
  (local compact node.compact-label)
  (if (= compact false)
      false
      (or compact node.label (node-id node))))

(fn label-text [node settings]
  (local base (compact-label-base node))
  (if (= base false)
      false
      (do
        (local truncated (truncate-with-ellipsis base settings.text-length))
        (if settings.line-length
            (wrap-text truncated settings.line-length)
            truncated))))
```

In `update-node-label`, replace the existing `if (< target 3) ...` body with this exact branch so `false` drops any existing span before normal span creation can run:

```fennel
(if (< target 3)
    (do
      (local text (label-text node settings))
      (if (= text false)
          (drop-label node)
          (do
            (local existing (. labels node))
            (var span existing)
            (if span
                (do
                  (span:set-text text {:mark-measure-dirty? true})
                  (set span.style.scale next-scale))
                (do
                  (local builder (Text {:text text
                                        :style (TextStyle {:color label-color
                                                           :scale next-scale})}))
                  (set span (builder ctx))
                  (set (. labels node) span)))
            (span.layout:measurer)
            (place-label span point))))
    (drop-label node))
```

Keep the existing LOD behavior for `target >= 3` by calling `drop-label node`. Do not add list-entity-specific logic to `graph/view/labels.fnl`.

- [ ] **Step 4: Run Fennel compile check first**

```bash
./build/space -m tools.fennel-check:main -- \
  --target files \
  --file assets/lua/graph/view/labels.fnl \
  --file assets/lua/tests/test-graph-view-labels.fnl
```

If a delimiter or parse error appears, inspect the nearest enclosing `update-node-label` or helper form first; simplify the branch into helper functions instead of guessing at closing delimiters.

- [ ] **Step 5: Run constraints second**

```bash
make constraints
```

- [ ] **Step 6: Run the focused GraphViewLabels test third**

```bash
SPACE_DISABLE_AUDIO=1 \
SKIP_KEYRING_TESTS=1 \
XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-graph-view-labels:main
```

Expected: PASS.

- [ ] **Step 7: Commit Task 1**

```bash
git add assets/lua/graph/view/labels.fnl assets/lua/tests/test-graph-view-labels.fnl
git commit -m "feat(ui): add compact graph label opt-out"
```

### Task 2: ListEntityNode Compact Label Metadata

**Files:**
- Modify: `assets/lua/graph/nodes/list-entity.fnl`
- Test: `assets/lua/tests/test-list-entities.fnl`

**Interfaces:**
- Consumes: Task 1 `node.compact-label` contract.
- Produces: `ListEntityNode` sets `node.label` to custom name or raw entity id fallback as before, sets `node.compact-label` to the non-empty custom name label or `false`, and `node:refresh-label()` refreshes both `label` and `compact-label` before emitting `node.changed`.

- [ ] **Step 1: Add list entity compact-label tests**

In `assets/lua/tests/test-list-entities.fnl`, add these tests after `list-entity-node-creates-with-correct-properties`:

```fennel
(fn list-entity-node-sets-compact-label-for-named-list []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:name "Named List"}))
      (local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
      (local node (ListEntityNode {:entity-id entity.id :store store}))
      (assert (= node.label "Named List")
              "named list entity should keep custom name as node.label")
      (assert (= node.compact-label "Named List")
              "named list entity should use custom name as compact-label")
      (node:drop))))

(fn list-entity-node-opts-out-compact-label-for-unnamed-list []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {}))
      (local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
      (local node (ListEntityNode {:entity-id entity.id :store store}))
      (assert (= node.label entity.id)
              "unnamed list entity should keep raw id fallback as node.label")
      (assert (= node.compact-label false)
              "unnamed list entity should opt out of compact labels")
      (node:drop))))

(fn list-entity-node-refreshes-compact-label-and-emits-changed []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:name "Visible"}))
      (local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
      (local node (ListEntityNode {:entity-id entity.id :store store}))
      (var changed-count 0)
      (var changed-payload nil)
      (node.changed:connect
        (fn [payload]
          (set changed-count (+ changed-count 1))
          (set changed-payload payload)))

      (store:update-entity entity.id {:name ""})
      (assert (= node.label entity.id)
              "clearing the custom name should restore raw id fallback label")
      (assert (= node.compact-label false)
              "clearing the custom name should opt out of compact labels")
      (assert (> changed-count 0)
              "clearing the custom name should emit node.changed")
      (assert (= changed-payload node)
              "node.changed payload should be the list entity node")

      (set changed-count 0)
      (store:update-entity entity.id {:name "Restored"})
      (assert (= node.label "Restored")
              "setting the custom name should refresh node.label")
      (assert (= node.compact-label "Restored")
              "setting the custom name should refresh compact-label")
      (assert (> changed-count 0)
              "setting the custom name should emit node.changed")
      (node:drop))))
```

Register them near the list entity node tests:

```fennel
(table.insert tests {:name "list entity node sets compact-label for named list"
                     :fn list-entity-node-sets-compact-label-for-named-list})
(table.insert tests {:name "list entity node opts out compact-label for unnamed list"
                     :fn list-entity-node-opts-out-compact-label-for-unnamed-list})
(table.insert tests {:name "list entity node refreshes compact-label and emits changed"
                     :fn list-entity-node-refreshes-compact-label-and-emits-changed})
```

- [ ] **Step 2: Run the focused list entity test and verify it fails**

```bash
SPACE_DISABLE_AUDIO=1 \
SKIP_KEYRING_TESTS=1 \
XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-list-entities:main
```

Expected before implementation: compact-label assertions fail.

- [ ] **Step 3: Implement list entity compact-label metadata**

In `assets/lua/graph/nodes/list-entity.fnl`, replace the current `make-label` helper with separate custom-name, label, and compact-label helpers:

```fennel
(fn custom-name [entity]
  (local name (or (and entity entity.name) ""))
  (if (> (string.len name) 0)
      name
      nil))

(fn make-label [entity]
  (local name (custom-name entity))
  (if name
      (Utils.truncate-with-ellipsis name 50)
      (or (and entity entity.id) "list entity")))

(fn make-compact-label [entity]
  (local name (custom-name entity))
  (if name
      (Utils.truncate-with-ellipsis name 50)
      false))
```

After `initial-label`, compute and assign the compact label:

```fennel
(local initial-compact-label (make-compact-label entity))
```

After constructing `node`, set the runtime presentation metadata:

```fennel
(set node.compact-label initial-compact-label)
```

Update `refresh-label` so it refreshes both fields before emitting `changed`:

```fennel
(fn refresh-label [self]
  (local current (self.store:get-entity self.entity-id))
  (set self.label (make-label current))
  (set self.compact-label (make-compact-label current))
  (when self.changed
    (self.changed:emit self)))
```

Do not change list entity persistence, entity store schema, item membership, ordered-list islands, copy-key behavior, previews, or full views.

- [ ] **Step 4: Run Fennel compile check first**

```bash
./build/space -m tools.fennel-check:main -- \
  --target files \
  --file assets/lua/graph/nodes/list-entity.fnl \
  --file assets/lua/tests/test-list-entities.fnl
```

If a parse error points near `local initial-compact-label` or `refresh-label`, inspect the nearest enclosing `ListEntityNode` form and repair the smallest malformed form first.

- [ ] **Step 5: Run constraints second**

```bash
make constraints
```

- [ ] **Step 6: Run focused tests third**

```bash
SPACE_DISABLE_AUDIO=1 \
SKIP_KEYRING_TESTS=1 \
XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-list-entities:main
```

Expected: PASS.

- [ ] **Step 7: Re-run GraphViewLabels focused test to verify cross-task behavior remains green**

```bash
SPACE_DISABLE_AUDIO=1 \
SKIP_KEYRING_TESTS=1 \
XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-graph-view-labels:main
```

Expected: PASS.

- [ ] **Step 8: Commit Task 2**

```bash
git add assets/lua/graph/nodes/list-entity.fnl assets/lua/tests/test-list-entities.fnl
git commit -m "feat(assets): suppress unnamed list compact labels"
```

### Task 3: Graph Doctrine Documentation

**Files:**
- Modify: `docs/dev/notes/graph.md`

**Interfaces:**
- Consumes: Task 1 compact label contract and Task 2 list entity adapter behavior.
- Produces: Canonical graph doctrine documentation for compact-label presentation metadata.

- [ ] **Step 1: Document compact label presentation metadata**

In `docs/dev/notes/graph.md`, add this section after `### Kind badges`:

```markdown
### Compact labels

Graph node adapters may expose `compact-label` presentation metadata for collapsed graph labels. `graph/view/labels` treats `compact-label: false` as an explicit opt-out, a string value as the compact label text base, and missing metadata as the existing fallback to `node.label` or the node key. This metadata is render-time presentation state only; graph core and GraphMap persistence still capture topology only and must not write compact-label metadata into graph topology state.

List entity adapters use this contract to keep raw ids available on non-compact surfaces while suppressing collapsed labels for unnamed lists. Named lists continue to expose their custom name as both the normal node label and compact label text base.
```

- [ ] **Step 2: Verify docs terminology**

Run:

```bash
rg -n "compact-label|Compact labels|graph-backed|graph object|first-class graph object|full graph state" docs/dev/notes/graph.md
```

Expected:
- The new `Compact labels` section appears.
- No new forbidden graph doctrine terms are introduced.

- [ ] **Step 3: Commit Task 3**

```bash
git add docs/dev/notes/graph.md
git commit -m "docs(graph): document compact graph label metadata"
```

### Task 4: Final Validation and Integration Readiness

**Files:**
- Validate: `assets/lua/graph/view/labels.fnl`
- Validate: `assets/lua/graph/nodes/list-entity.fnl`
- Validate: `assets/lua/tests/test-graph-view-labels.fnl`
- Validate: `assets/lua/tests/test-list-entities.fnl`
- Validate: `docs/dev/notes/graph.md`

**Interfaces:**
- Consumes: Tasks 1-3 committed changes.
- Produces: Clean, validated branch ready for reviewer/PR flow; PR CI remains the full integration gate.

- [ ] **Step 1: Ensure runtime is fresh if needed**

Run when `./build/space` is missing/stale or after any runtime/build dependency uncertainty:

```bash
make build
```

- [ ] **Step 2: Focused compile check first**

```bash
./build/space -m tools.fennel-check:main -- \
  --target files \
  --file assets/lua/graph/view/labels.fnl \
  --file assets/lua/graph/nodes/list-entity.fnl \
  --file assets/lua/tests/test-graph-view-labels.fnl \
  --file assets/lua/tests/test-list-entities.fnl
```

- [ ] **Step 3: Constraints second**

```bash
make constraints
```

- [ ] **Step 4: Focused Fennel tests third**

```bash
SPACE_DISABLE_AUDIO=1 \
SKIP_KEYRING_TESTS=1 \
XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-graph-view-labels:main
```

```bash
SPACE_DISABLE_AUDIO=1 \
SKIP_KEYRING_TESTS=1 \
XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-list-entities:main
```

- [ ] **Step 5: Run the broader relevant local Fennel suite**

This is justified because `graph/view/labels.fnl` is shared graph view infrastructure used by many node families.

```bash
SPACE_DISABLE_AUDIO=1 \
SKIP_KEYRING_TESTS=1 \
XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.fast:main
```

- [ ] **Step 6: Review the diff for out-of-scope changes**

Run:

```bash
git diff --stat origin/main...HEAD
git diff origin/main...HEAD -- \
  assets/lua/graph/view/labels.fnl \
  assets/lua/graph/nodes/list-entity.fnl \
  assets/lua/tests/test-graph-view-labels.fnl \
  assets/lua/tests/test-list-entities.fnl \
  docs/dev/notes/graph.md
```

Confirm:
- No list entity persistence/storage schema changes.
- No ordered-list island layout or membership changes.
- No list-entity special-case was added to `graph/view/labels.fnl`.
- No graph topology persistence writes include `compact-label`.
- Raw id fallback remains in `node.label` for unnamed list entities.

- [ ] **Step 7: Check branch status**

```bash
git status --porcelain
```

Expected: clean tree.

- [ ] **Step 8: Final integration gate**

Before PR readiness, fetch and evaluate against current `origin/main` per repository policy:

```bash
git fetch origin
git status --porcelain
git log --oneline origin/main..HEAD
```

If local validation is green and the tree is clean, proceed with the normal PR flow. Do not claim ready-to-merge until PR CI is green; PR CI is the full integration gate.
