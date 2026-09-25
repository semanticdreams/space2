# Center-Anchored Ordered-List Island Force Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement center-anchored aggregate force layout for GraphView ordered-list islands while preserving persisted island state as presenter body/origin position.

**Architecture:** Extend the existing island aggregate layout contract so presenters may expose a separate force anchor and a conversion back to persisted body position. Ordered-list islands keep `state.position` as the first-member/body origin, expose the vertical list bounding-box center as the force participant position, and let `GraphViewLayout` convert solver movement back into origin-based placements and runtime cache entries.

**Tech Stack:** Space Fennel, GraphView/GraphMap island presenters, `GraphViewLayout`, project-native Fennel tests via `./build/space`.

## Global Constraints

- Do not add compound-body physics or per-member rigid constraints to the C++ force solver.
- Do not change graph topology or make graph core own island layout semantics.
- Do not make pinned/expanded members follow aggregate movement.
- Do not eagerly persist runtime force movement outside the existing capture/flush path.
- Keep persisted `state.position` as the presenter body/origin position and translate to/from a center force anchor inside the presenter/layout adapter.
- Graph core/topology does not own island layout behavior.
- `GraphMap` persists map-local island records.
- Presenters own island-specific placement rules.
- `GraphViewLayout` adapts presenter records into force-layout participants.
- For Fennel-facing work, run `make fennel-check` before `make constraints`, then focused Fennel tests.
- If `./build/space` is missing or stale, run `make build` first with timeout `14400000`.

---

### Task 1: Ordered-List Presenter Exposes Center Force Anchor

**Files:**
- Modify: `assets/lua/graph/view/island-presenters/ordered-list.fnl`
- Modify/Test: `assets/lua/tests/test-graph-view-islands.fnl`

**Interfaces:**
- Consumes: existing ordered-list presenter contract:
  - `aggregate-layout-record(island: table, host: GraphViewIslandHost) -> table`
  - `member-placements(origin: vec3) -> table<member-key, vec3>`
- Produces: extended aggregate record fields:
  - `record.position: vec3` remains the ordered-list body/origin position.
  - `record.force-position: vec3` is the ordered-list visual center used by force layout.
  - `record.body-position-for-force-position(force-position: vec3) -> vec3` converts a moved force center back to ordered-list origin.
  - `record.member-placements(origin: vec3) -> table<member-key, vec3>` continues to accept origin/body position.

- [ ] **Step 1: Add the presenter module import to the island tests**

Add near the existing `require` block in `assets/lua/tests/test-graph-view-islands.fnl`:

```fennel
(local OrderedListPresenter (require :graph/view/island-presenters/ordered-list))
```

- [ ] **Step 2: Add a focused failing presenter contract test**

Add this helper/test function near the other island behavior checks:

```fennel
(fn check-ordered-list-aggregate-record-exposes-center-force-anchor []
    (local node-a {:key "test:a" :size 10})
    (local node-b {:key "test:b" :size 10})
    (local node-c {:key "test:c" :size 10})
    (local nodes {})
    (set (. nodes "test:a") node-a)
    (set (. nodes "test:b") node-b)
    (set (. nodes "test:c") node-c)
    (local positions {})
    (set (. positions "test:a") (glm.vec3 0 0 0))
    (set (. positions "test:b") (glm.vec3 0 -20 0))
    (set (. positions "test:c") (glm.vec3 0 -40 0))
    (local host
        {:node-for-key (fn [_self key] (. nodes key))
         :position-for-key (fn [_self key] (. positions key))})
    (local island
        {:id "island-1"
         :kind "ordered-list"
         :members ["test:a" "test:b" "test:c"]
         :state {:position (glm.vec3 100 200 0)
                 :spacing 20}})
    (local record (OrderedListPresenter.aggregate-layout-record island host))
    (assert-vec3 record.position (glm.vec3 100 200 0)
                 "aggregate record body position should remain ordered-list origin")
    (assert-vec3 record.force-position (glm.vec3 100 180 0)
                 "aggregate force position should be the ordered-list visual center")
    (assert (= (type record.body-position-for-force-position) :function)
            "aggregate record should expose center-to-origin conversion")
    (local moved-origin (record.body-position-for-force-position (glm.vec3 130 230 0)))
    (assert-vec3 moved-origin (glm.vec3 130 250 0)
                 "moved force center should convert back to ordered-list origin")
    (local placements (record.member-placements moved-origin))
    (assert-vec3 (. placements "test:a") (glm.vec3 130 250 0)
                 "first member placement should use converted origin")
    (assert-vec3 (. placements "test:b") (glm.vec3 130 230 0)
                 "second member placement should preserve spacing")
    (assert-vec3 (. placements "test:c") (glm.vec3 130 210 0)
                 "third member placement should preserve spacing"))
```

- [ ] **Step 3: Register the failing test**

Add a wrapper near the other `graph-view-*` functions:

```fennel
(fn graph-view-ordered-list-aggregate-record-exposes-center-force-anchor []
    (check-ordered-list-aggregate-record-exposes-center-force-anchor))
```

Add it to the `tests` table before the runtime force-layout tests:

```fennel
(table.insert tests {:name "GraphView ordered-list aggregate record exposes center force anchor"
                     :fn graph-view-ordered-list-aggregate-record-exposes-center-force-anchor})
```

- [ ] **Step 4: Run the focused test and verify it fails**

Prerequisite if `./build/space` is missing or stale:

```bash
make build
```

Use timeout `14400000` for `make build`.

Focused test command:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-islands:main
```

Expected result: FAIL because `record.force-position` and `record.body-position-for-force-position` do not exist yet.

- [ ] **Step 5: Implement ordered-list center/origin conversion helpers**

In `assets/lua/graph/view/island-presenters/ordered-list.fnl`, add helpers near `placements-from-origin`:

```fennel
(fn ordered-list-center-offset [island]
    (local state (if island.state island.state {}))
    (local spacing (if state.spacing state.spacing default-spacing))
    (local members (if island.members island.members []))
    (local count (length members))
    (glm.vec3 0 (- (/ (* spacing (- count 1)) 2.0)) 0))

(fn force-position-from-origin [island origin]
    (+ origin (ordered-list-center-offset island)))

(fn origin-from-force-position [island force-position]
    (- force-position (ordered-list-center-offset island)))
```

- [ ] **Step 6: Extend `aggregate-layout-record` without changing persisted/body position semantics**

Update `aggregate-layout-record` so the returned table includes the new fields while keeping `:position base` and `member-placements` origin-based:

```fennel
{:id island.id
 :members member-nodes
 :position base
 :force-position (force-position-from-origin island base)
 :body-position-for-force-position (fn [force-position]
                                     (origin-from-force-position island force-position))
 :member-placements (fn [origin]
                      (placements-from-origin island origin))}
```

- [ ] **Step 7: Run focused validation for Task 1**

Run in this order:

```bash
make fennel-check
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-islands:main
```

Expected result: PASS for the new presenter contract test; later runtime tests may still expose layout-adapter failures until Task 2 is complete.

- [ ] **Step 8: Commit Task 1**

```bash
git add assets/lua/graph/view/island-presenters/ordered-list.fnl assets/lua/tests/test-graph-view-islands.fnl
git commit -m "feat(graph): expose ordered-list island force center"
```

---

### Task 2: GraphViewLayout Uses Force Anchor and Stores Runtime Body Position

**Files:**
- Modify: `assets/lua/graph/view/layout.fnl`
- Modify: `assets/lua/graph/view/island-host.fnl`
- Modify/Test: `assets/lua/tests/test-graph-view-islands.fnl`

**Interfaces:**
- Consumes from Task 1:
  - `record.position: vec3` body/origin position.
  - `record.force-position: vec3 | nil` force participant position.
  - `record.body-position-for-force-position(force-position: vec3) -> vec3 | nil`.
  - `record.member-placements(body-position: vec3) -> table`.
- Produces:
  - `GraphViewLayout.sync-island-layouts(records)` accepts paired optional `force-position` and `body-position-for-force-position`.
  - `on-island-position(island-id: string, body-position: vec3)` receives body/origin position, never force-center position.
  - Island member edges still route through the aggregate force participant for unpinned members.

- [ ] **Step 1: Add fake force-layout helpers for layout-adapter tests**

Add these helpers in `assets/lua/tests/test-graph-view-islands.fnl` near the other local test helpers:

```fennel
(local GraphViewLayout (require :graph/view/layout))

(fn copy-vec3 [position]
    (glm.vec3 position.x position.y position.z))

(fn make-force-layout-stub []
    {:positions []
     :next-positions nil
     :edges []
     :pins {}
     :starts 0
     :clears 0
     :add-node (fn [self position]
                 (table.insert self.positions (copy-vec3 position))
                 (- (length self.positions) 1))
     :add-edge (fn [self source target _bidirectional?]
                 (table.insert self.edges {:source source :target target}))
     :pin-node (fn [self idx pinned?]
                 (set (. self.pins idx) pinned?))
     :set-position (fn [self idx position]
                     (set (. self.positions (+ idx 1)) (copy-vec3 position)))
     :get-positions (fn [self]
                      (or self.next-positions self.positions))
     :update (fn [_self _iterations] nil)
     :start (fn [self]
              (set self.starts (+ self.starts 1)))
     :clear (fn [self]
              (set self.clears (+ self.clears 1))
              (set self.positions [])
              (set self.next-positions nil)
              (set self.edges [])
              (set self.pins {}))})

(fn make-line-stub [_ctx _opts]
    {:update (fn [_self _start _end] nil)
     :drop (fn [_self] nil)})
```

- [ ] **Step 2: Add a failing layout conversion test**

Add:

```fennel
(fn check-graph-view-layout-converts-force-center-to-island-body-position []
    (local force-layout (make-force-layout-stub))
    (local normal {:key "test:normal" :size 10})
    (local member-a {:key "test:a" :size 10})
    (local member-b {:key "test:b" :size 10})
    (local center (glm.vec3 10 88 0))
    (local origin (glm.vec3 10 100 0))
    (local delta (glm.vec3 5 -7 0))
    (local nodes {})
    (set (. nodes normal) normal)
    (set (. nodes member-a) member-a)
    (set (. nodes member-b) member-b)
    (local points {})
    (set (. points normal) {:position center})
    (set (. points member-a) {:position origin})
    (set (. points member-b) {:position (glm.vec3 10 76 0)})
    (var captured-body-position nil)
    (local graph-layout
        (GraphViewLayout {:layout force-layout
                          :nodes nodes
                          :points points
                          :make-line make-line-stub
                          :set-point-position (fn [node position _context]
                                                (set (. (. points node) :position) position))
                          :get-position (fn [_self node]
                                          (. (. points node) :position))
                          :get-position-raw (fn [_self node]
                                              (. (. points node) :position))
                          :on-island-position (fn [_island-id position]
                                                (set captured-body-position position))}))
    (graph-layout:add-node normal center false)
    (local record
        {:id "island-1"
         :members [member-a member-b]
         :position origin
         :force-position center
         :body-position-for-force-position (fn [force-position]
                                             (+ force-position (glm.vec3 0 12 0)))
         :member-placements (fn [body-position]
                              (local placements {})
                              (set (. placements "test:a") body-position)
                              (set (. placements "test:b") (- body-position (glm.vec3 0 24 0)))
                              placements)})
    (graph-layout:sync-island-layouts [record])
    (set force-layout.next-positions [(+ center delta) (+ center delta)])
    (graph-layout:update 0.016)
    (assert-vec3 (. (. points normal) :position) (+ center delta)
                 "normal node should move by injected force delta")
    (assert-vec3 captured-body-position (+ origin delta)
                 "island runtime callback should receive body/origin position")
    (assert-vec3 (. (. points member-a) :position) (+ origin delta)
                 "first island member should use converted body origin")
    (assert-vec3 (. (. points member-b) :position) (- (+ origin delta) (glm.vec3 0 24 0))
                 "second island member should preserve ordered-list spacing"))
```

Register it:

```fennel
(fn graph-view-layout-converts-force-center-to-island-body-position []
    (check-graph-view-layout-converts-force-center-to-island-body-position))

(table.insert tests {:name "GraphViewLayout converts island force center to body position"
                     :fn graph-view-layout-converts-force-center-to-island-body-position})
```

- [ ] **Step 3: Add a failing edge-routing test for unpinned island members**

Add:

```fennel
(fn check-graph-view-layout-routes-member-edge-through-island-force-anchor []
    (local force-layout (make-force-layout-stub))
    (local member-a {:key "test:a" :size 10})
    (local member-b {:key "test:b" :size 10})
    (local outside {:key "test:outside" :size 10})
    (local island-force-position (glm.vec3 0 -12 0))
    (local outside-position (glm.vec3 100 0 0))
    (local nodes {})
    (set (. nodes member-a) member-a)
    (set (. nodes member-b) member-b)
    (set (. nodes outside) outside)
    (local points {})
    (set (. points member-a) {:position (glm.vec3 0 0 0)})
    (set (. points member-b) {:position (glm.vec3 0 -24 0)})
    (set (. points outside) {:position outside-position})
    (local graph-layout
        (GraphViewLayout {:layout force-layout
                          :nodes nodes
                          :points points
                          :make-line make-line-stub
                          :set-point-position (fn [node position _context]
                                                (set (. (. points node) :position) position))
                          :get-position (fn [_self node]
                                          (. (. points node) :position))
                          :get-position-raw (fn [_self node]
                                              (. (. points node) :position))}))
    (graph-layout:add-node outside outside-position false)
    (graph-layout:sync-island-layouts
        [{:id "island-1"
          :members [member-a member-b]
          :position (glm.vec3 0 0 0)
          :force-position island-force-position
          :body-position-for-force-position (fn [force-position]
                                              (+ force-position (glm.vec3 0 12 0)))
          :member-placements (fn [body-position]
                               (local placements {})
                               (set (. placements "test:a") body-position)
                               (set (. placements "test:b") (- body-position (glm.vec3 0 24 0)))
                               placements)}])
    (graph-layout:add-edge {:source member-b :target outside})
    (local edge (. force-layout.edges 1))
    (assert edge "member edge should be added to force layout")
    (assert-vec3 (. force-layout.positions (+ edge.source 1)) island-force-position
                 "edge from unpinned island member should use aggregate force anchor")
    (assert-vec3 (. force-layout.positions (+ edge.target 1)) outside-position
                 "edge target should use outside node force body"))
```

Register it:

```fennel
(fn graph-view-layout-routes-member-edge-through-island-force-anchor []
    (check-graph-view-layout-routes-member-edge-through-island-force-anchor))

(table.insert tests {:name "GraphViewLayout routes island member edge through force anchor"
                     :fn graph-view-layout-routes-member-edge-through-island-force-anchor})
```

- [ ] **Step 4: Run the focused test and verify it fails**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-islands:main
```

Expected result: FAIL because `GraphViewLayout` still uses `record.position` as the force participant and passes moved force positions directly to `on-island-position` and `member-placements`.

- [ ] **Step 5: Validate the extended host contract**

In `assets/lua/graph/view/island-host.fnl`, inside the existing `when record` validation block, add paired validation:

```fennel
(when record.force-position
    (assert (= (type record.body-position-for-force-position) :function)
            "GraphViewIslandHost aggregate layout record with force-position requires body-position-for-force-position function"))
(when (and record.body-position-for-force-position (not record.force-position))
    (error "GraphViewIslandHost aggregate layout record with body-position-for-force-position requires force-position"))
```

- [ ] **Step 6: Validate the extended layout contract**

In `assets/lua/graph/view/layout.fnl`, extend `validate-island-layout-record`:

```fennel
(when record.force-position
    (assert (vec3-like? record.force-position)
            "GraphViewLayout island layout record force-position must be vec3-like")
    (assert (= (type record.body-position-for-force-position) :function)
            "GraphViewLayout island layout record with force-position requires body-position-for-force-position function"))
(when (and record.body-position-for-force-position (not record.force-position))
    (error "GraphViewLayout island layout record with body-position-for-force-position requires force-position"))
```

- [ ] **Step 7: Use force position when rebuilding aggregate participants**

In `rebuild`, change the island aggregate `add-force-node` call to use the force anchor when present:

```fennel
(each [_ record (pairs island-layouts)]
    (add-force-node {:kind :island :record record}
                    (ensure-glm-vec3 (or record.force-position record.position))
                    false))
```

- [ ] **Step 8: Normalize force position during island sync**

In `sync-island-layouts`, after validating and normalizing `record.position`, normalize `record.force-position` when present:

```fennel
(local position (ensure-glm-vec3 record.position))
(assert-valid-position position "GraphViewLayout.sync-island-layouts" nil)
(set record.position position)
(when record.force-position
    (local force-position (ensure-glm-vec3 record.force-position))
    (assert-valid-position force-position "GraphViewLayout.sync-island-layouts:force-position" nil)
    (set record.force-position force-position))
(set (. island-layouts record.id) record)
```

- [ ] **Step 9: Convert moved force center back to body position during refresh**

In the island branch of `refresh-layout`, compare against the current force position and call `member-placements` with body/origin position:

```fennel
(local record participant.record)
(local previous-force-position (or record.force-position record.position))
(when (position-changed? previous-force-position new-pos)
    (local body-position
        (if record.body-position-for-force-position
            (record.body-position-for-force-position new-pos)
            new-pos))
    (assert-valid-position body-position "GraphViewLayout.refresh-layout:island-body" nil)
    (set record.force-position new-pos)
    (set record.position body-position)
    (on-island-position record.id body-position)
    (local placements (record.member-placements body-position))
    (each [_ member (ipairs record.members)]
        (when (not (. pinned member))
            (local placement (or (. placements member.key) (. placements (node-id member))))
            (assert placement
                    (string.format "GraphViewLayout.refresh-layout missing island placement for node %s"
                                   (node-id member)))
            (assert-valid-position placement "GraphViewLayout.refresh-layout:island" member)
            (local point (. points member))
            (assert point (string.format "GraphViewLayout.refresh-layout missing point for island member %s"
                                         (node-id member)))
            (when (position-changed? point.position placement)
                (set-point-position member placement "GraphViewLayout.refresh-layout:island")
                (table.insert changed member)))))
```

- [ ] **Step 10: Run focused validation for Task 2**

Run in this order:

```bash
make fennel-check
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-islands:main
```

Expected result: PASS for the new layout conversion and edge-routing tests.

- [ ] **Step 11: Commit Task 2**

```bash
git add assets/lua/graph/view/layout.fnl assets/lua/graph/view/island-host.fnl assets/lua/tests/test-graph-view-islands.fnl
git commit -m "feat(graph): adapt island force centers to body positions"
```

---

### Task 3: Runtime GraphView Behavior Preserves Origin Cache and Pinned Exceptions

**Files:**
- Modify/Test: `assets/lua/tests/test-graph-view-islands.fnl`

**Interfaces:**
- Consumes from Task 2:
  - `on-island-position(island-id, body-position)` stores runtime origin/body position.
  - `record.member-placements(body-position)` applies origin-based ordered-list placements.
- Produces:
  - Focused runtime coverage proving GraphView capture flushes body/origin position, not force center.
  - Existing pinned/expanded member behavior remains documented by tests.

- [ ] **Step 1: Add a runtime test for flushing body origin rather than visual center**

Add this check near the other list-created island force-layout checks:

```fennel
(fn check-force-moved-island-flushes-body-origin-not-force-center [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local item-node (map:lookup fixture.item-key))
    (local second-node (map:lookup fixture.second-item-key))
    (local list-entry (. movables.by-node list-node))
    (assert list-entry "list node should be movable")
    (list-entry.target:set-position (glm.vec3 48 0 0))
    (list-node:expand-items-as-island)
    (for [_ 1 8]
        (view:update 0.016))
    (local first-runtime (view:get-position item-node))
    (local second-runtime (view:get-position second-node))
    (view:capture-state)
    (local island (map:get-island "ordered-list:list"))
    (assert island "captured map should still contain ordered-list island")
    (assert-close (. island.state.position 1) first-runtime.x
                  "flushed island state x should be first-member/body origin x")
    (assert-close (. island.state.position 2) first-runtime.y
                  "flushed island state y should be first-member/body origin y")
    (assert-close (. island.state.position 3) first-runtime.z
                  "flushed island state z should be first-member/body origin z")
    (local visual-center-y (* (+ first-runtime.y second-runtime.y) 0.5))
    (assert (> (math.abs (- (. island.state.position 2) visual-center-y)) 0.001)
            "flushed island state should not store ordered-list visual center"))
```

- [ ] **Step 2: Register the runtime test**

Add:

```fennel
(fn graph-view-force-moved-island-flushes-body-origin-not-force-center []
    (with-list-fixture
        check-force-moved-island-flushes-body-origin-not-force-center))
```

Add to the `tests` table near the existing runtime cache tests:

```fennel
(table.insert tests {:name "GraphView force-moved island flushes body origin not force center"
                     :fn graph-view-force-moved-island-flushes-body-origin-not-force-center})
```

- [ ] **Step 3: Run the focused test command**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-islands:main
```

Expected result: PASS after Task 2. If it fails by storing the center, fix only the layout/runtime conversion path; do not change `GraphMap` persistence schema.

- [ ] **Step 4: Re-run pinned-member runtime coverage**

Use the same focused test command and confirm these existing named tests still pass:
- `GraphView expanded member stays pinned through island position flush`
- `GraphView collapsed expanded member rejoins aggregate placement`
- `GraphView replacing expanded island member resyncs aggregate record`

- [ ] **Step 5: Run focused validation for Task 3**

```bash
make fennel-check
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-islands:main
```

- [ ] **Step 6: Commit Task 3**

```bash
git add assets/lua/tests/test-graph-view-islands.fnl
git commit -m "test(graph): cover island body-origin runtime flush"
```

---

### Task 4: Document Center-Anchored Island Force Layout

**Files:**
- Modify: `docs/dev/graph-maps.md`

**Interfaces:**
- Consumes: implemented behavior from Tasks 1-3.
- Produces: canonical developer documentation for ordered-list island force layout expectations.

- [ ] **Step 1: Update the Presentation islands force-layout paragraph**

In `docs/dev/graph-maps.md`, update the paragraph describing ordered-list aggregate force layout so it states:

```markdown
In `GraphView` force layout, ordered-list islands participate as one aggregate
island body by default. The aggregate force participant uses the ordered-list
visual center, while persisted `state.position` remains the presenter body/origin
position used for member placement. `GraphViewLayout` converts force-center
movement back to body/origin position before recording runtime island layout
state or applying presenter placements. Unpinned members remain normal rendered
graph nodes, but their individual force-layout bodies are omitted while the
aggregate body moves; the presenter then reapplies ordered-list member placements
from the body/origin so the island moves as a unit and preserves spacing.
Explicit node pins are still honored: a pinned member keeps its own pinned force
participant and is not moved by aggregate island refresh until that explicit pin
is released.
```

Keep the existing statement that alt-drag writes final body position back to `state.position`.

- [ ] **Step 2: Verify the docs mention both center force anchor and origin persistence**

Run:

```bash
rg "visual center|body/origin|state.position" docs/dev/graph-maps.md
```

Expected result: the updated section includes all three concepts.

- [ ] **Step 3: Commit Task 4**

```bash
git add docs/dev/graph-maps.md
git commit -m "docs(graph): document center-anchored island layout"
```

---

## Acceptance Criteria

- Unpinned ordered-list islands contribute one aggregate force participant.
- The aggregate participant starts at the ordered-list visual center.
- Ordered-list `state.position` remains the persisted body/origin position; no schema migration is introduced.
- Runtime island layout cache stores body/origin position and flushes only through existing `GraphView:capture-state`.
- Member placements continue to preserve ordered-list spacing.
- External edges to unpinned island members route to the aggregate force participant.
- Explicitly pinned or expanded island members remain independent force participants and are not moved by aggregate refresh.
- Existing legacy fallback behavior for island records without `state.position` remains intact.
- `docs/dev/graph-maps.md` documents the center-anchor/body-origin split.

## Validation Ladder

1. Runtime/freshness prerequisite when `./build/space` is missing or stale:

   ```bash
   make build
   ```

   Use timeout `14400000`.

2. First focused Fennel check:

   ```bash
   make fennel-check
   ```

3. Fennel constraints:

   ```bash
   make constraints
   ```

4. Focused Fennel test:

   ```bash
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view-islands:main
   ```

5. Broader relevant local suite, justified because this changes graph-view force layout, edge routing, runtime cache, and presenter contracts:

   ```bash
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
   ```

6. Final local integration check when ready for PR:

   ```bash
   SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
   ```

7. Full integration gate: PR CI.

If Fennel delimiter or parse errors appear, inspect the nearest enclosing form around the reported location first. If the reported location looks innocent, isolate the bad form by temporarily removing nearby chunks, then re-add them incrementally; prefer extracting helper functions to reduce nesting before attempting broad rewrites.

## Out of Scope

- Compound-body physics or per-member rigid constraints.
- C++ force solver changes.
- Graph core/topology changes.
- GraphMap persistence schema migration.
- Making pinned or expanded members follow aggregate island movement.
- Eager persistence of runtime force movement outside the existing capture/flush path.
- New user-facing island pin UI or API.

## HUMAN_DECISION_REQUIRED

None.
