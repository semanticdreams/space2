# Island Member Drag Handles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow alt-dragging any member of an island to move the whole island on drag end while preserving normal snap-back behavior for non-alt drags.

**Architecture:** `GraphView` detects an alt-modified drag end and delegates island state derivation to `GraphViewIslandHost`, which delegates to the island presenter. Ordered-list presenter math remains inside the ordered-list presenter and derives the new island body from its own layout result rather than from hardcoded index math in `GraphView`.

**Tech Stack:** Space Fennel (`.fnl`), `GraphMap`, `GraphView`, `GraphViewMovables`, `GraphViewIslandHost`, ordered-list island presenter, project-native `./build/space` Fennel test runner.

## Global Constraints

- Alt-dragging any member of an island moves the whole island, with whole-island movement applied only on drag end.
- During drag, only the dragged member follows the pointer.
- On drag end, the island presenter derives a new island body state from the dropped member position.
- `GraphMap` persists the derived state and normal island reconciliation places all members relative to the new body.
- Do not add user-facing configuration for island drag policies in this slice.
- Do not move the whole island live while the pointer is dragging.
- Do not implement list reordering through graph node drag.
- Do not make `GraphView` understand ordered-list index or spacing math.
- Do not change ownership of domain list data; list order remains owned by the list entity store.
- Presenters without the optional drag-end hook are treated as not supporting this interaction.
- Missing presenter kinds fail visibly, matching existing island reconciliation behavior.
- Missing `GraphMap:update-island` fails loudly when an alt island move is attempted.
- Invalid request data, missing member keys, and invalid positions raise explicit errors at the host/presenter boundary.
- Fennel code uses `local` instead of `let` for new bindings.
- Validation follows the Space Fennel ladder: compile check, constraints, focused Fennel tests, broader suite when the branch is finished.

---

## File Structure

- `assets/lua/graph/view/island-presenters/ordered-list.fnl`
  - Owns ordered-list layout rules and the new `member-drag-end-state` hook.
  - Must not expose ordered-list spacing/index math to `GraphView`.
- `assets/lua/graph/view/island-host.fnl`
  - Mediates presenter lookup for the new optional hook.
  - Keeps presenter-missing errors consistent with reconciliation.
- `assets/lua/graph/view/movables.fnl`
  - Bridges generic movable callback payloads through to GraphView-specific callbacks.
- `assets/lua/graph/view/init.fnl`
  - Tracks whether the active graph-node drag started with Alt.
  - On alt drag end, asks island host for derived island state and persists it through `GraphMap:update-island` before reconciliation.
- `assets/lua/tests/test-graph-island-presenters.fnl`
  - Unit coverage for presenter hook and island host delegation.
- `assets/lua/tests/test-graph-view-islands.fnl`
  - Integration coverage for alt-dragging an island member and non-alt snap-back behavior.
- `docs/dev/notes/graph.md`
  - Documents presenter-owned island movement interaction semantics.

## Validation Environment

Use this environment for direct `./build/space` test commands:

```bash
export SPACE_DISABLE_AUDIO=1
export SKIP_KEYRING_TESTS=1
export XDG_DATA_HOME=/tmp/space/tests/xdg-data
export SPACE_ASSETS_PATH="$(pwd)/assets"
export FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"
export FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"
```

If `./build/space` may be missing or stale, run `make build` with timeout `14400000` before direct test commands.

---

### Task 1: Add ordered-list presenter drag-end state hook

**Files:**
- Modify: `assets/lua/graph/view/island-presenters/ordered-list.fnl`
- Test: `assets/lua/tests/test-graph-island-presenters.fnl`

**Interfaces:**
- Consumes: `OrderedListPresenter.layout-island(island: table, host: table) -> table<string, glm.vec3>`
- Consumes: `host:position-for-key(key: string) -> glm.vec3|nil`
- Produces: `OrderedListPresenter.member-drag-end-state(island: table, host: table, request: table) -> table|nil`
- `request.member-key` is the dragged node key.
- `request.position` is the dropped graph position as a vec3-like value.
- Returned table is a complete replacement for `island.state` and stores `position` as a JSON-safe `[x y z]` array.

- [ ] **Step 1: Add presenter hook tests**

In `assets/lua/tests/test-graph-island-presenters.fnl`, add tests with these behaviors:

```fennel
(fn ordered-list-presenter-derives-origin-from-second-member-drop []
    (local host (make-host {:positions {"item:a" (glm.vec3 10 20 0)
                                        "item:b" (glm.vec3 10 -4 0)}}))
    (local island {:id "island-1"
                   :kind "ordered-list"
                   :members ["item:a" "item:b"]
                   :state {:list-key "list:1"
                           :interaction-policy "snap-back"
                           :spacing 24
                           :position [10 20 0]}})
    (local next-state (OrderedListPresenter.member-drag-end-state
                        island host {:member-key "item:b"
                                     :position (glm.vec3 50 60 0)}))
    (assert (= next-state.list-key "list:1") "list-key should be preserved")
    (assert (= next-state.interaction-policy "snap-back") "interaction policy should be preserved")
    (assert (= next-state.spacing 24) "spacing should be preserved")
    (assert (= (. next-state.position 1) 50) "new origin x should follow dropped member delta")
    (assert (= (. next-state.position 2) 84) "new origin y should keep second member at drop after spacing")
    (assert (= (. next-state.position 3) 0) "new origin z should follow dropped member delta"))

(fn ordered-list-presenter-upgrades-legacy-island-on-member-drop []
    (local host (make-host {:positions {"item:a" (glm.vec3 100 100 0)
                                        "item:b" (glm.vec3 100 76 0)}}))
    (local island {:id "island-1"
                   :kind "ordered-list"
                   :members ["item:a" "item:b"]
                   :state {:list-key "list:1" :spacing 24}})
    (local next-state (OrderedListPresenter.member-drag-end-state
                        island host {:member-key "item:b"
                                     :position (glm.vec3 200 176 0)}))
    (assert (= (. next-state.position 1) 200) "legacy island should receive explicit body x")
    (assert (= (. next-state.position 2) 200) "legacy island should receive explicit body y")
    (assert (= (. next-state.position 3) 0) "legacy island should receive explicit body z"))

(fn ordered-list-presenter-ignores-non-member-drop []
    (local host (make-host {:positions {"item:a" (glm.vec3 0 0 0)}}))
    (local island {:id "island-1" :kind "ordered-list" :members ["item:a"] :state {:position [0 0 0]}})
    (local next-state (OrderedListPresenter.member-drag-end-state
                        island host {:member-key "item:x"
                                     :position (glm.vec3 10 10 0)}))
    (assert (= next-state nil) "non-member drag should not update island state"))
```

Register the tests in the existing `tests` table with descriptive names.

- [ ] **Step 2: Run presenter tests and record RED evidence**

```bash
make build
export SPACE_DISABLE_AUDIO=1
export SKIP_KEYRING_TESTS=1
export XDG_DATA_HOME=/tmp/space/tests/xdg-data
export SPACE_ASSETS_PATH="$(pwd)/assets"
export FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"
export FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"
./build/space -m tests.test-graph-island-presenters:main
```

Expected RED: failure because `OrderedListPresenter.member-drag-end-state` is missing.

- [ ] **Step 3: Implement ordered-list state derivation helpers**

In `assets/lua/graph/view/island-presenters/ordered-list.fnl`, add helpers near the existing vec3 helpers:

```fennel
(fn vec3-array [position label]
    (local value (vec3-copy position label))
    [value.x value.y value.z])

(fn copy-state [state]
    (local next {})
    (each [k v (pairs (or state {}))]
        (set (. next k) v))
    next)

(fn member-index [island member-key]
    (var found nil)
    (each [index key (ipairs (or island.members []))]
        (when (and (not found) (= key member-key))
            (set found index)))
    found)
```

- [ ] **Step 4: Implement and export `member-drag-end-state`**

Add this function before the export table:

```fennel
(fn member-drag-end-state [island host request]
    (assert island "OrderedListPresenter.member-drag-end-state requires island")
    (assert host "OrderedListPresenter.member-drag-end-state requires host")
    (assert request "OrderedListPresenter.member-drag-end-state requires request")
    (assert request.member-key "OrderedListPresenter.member-drag-end-state requires request.member-key")
    (assert request.position "OrderedListPresenter.member-drag-end-state requires request.position")
    (if (not (member-index island request.member-key))
        nil
        (do
            (local placements (layout-island island host))
            (local current-placement (vec3-copy (. placements request.member-key)
                                                "OrderedListPresenter current member placement"))
            (local dropped-position (vec3-copy request.position
                                               "OrderedListPresenter dropped member position"))
            (local base (base-position island host))
            (local delta (- dropped-position current-placement))
            (local next-origin (+ base delta))
            (local next-state (copy-state island.state))
            (set next-state.position (vec3-array next-origin
                                                 "OrderedListPresenter next origin"))
            next-state)))
```

Export it:

```fennel
{:kind kind
 :layout-island layout-island
 :member-drag-end-state member-drag-end-state
 :apply apply}
```

- [ ] **Step 5: Run focused validation for Task 1**

```bash
make fennel-check
make constraints
./build/space -m tests.test-graph-island-presenters:main
```

Expected: all pass.

- [ ] **Step 6: Commit Task 1**

```bash
git add assets/lua/graph/view/island-presenters/ordered-list.fnl \
        assets/lua/tests/test-graph-island-presenters.fnl
git commit -m "feat(graph): derive island origin from member drag"
```

---

### Task 2: Add island host mediation for presenter drag-end hooks

**Files:**
- Modify: `assets/lua/graph/view/island-host.fnl`
- Test: `assets/lua/tests/test-graph-island-presenters.fnl`

**Interfaces:**
- Consumes: `presenter.member-drag-end-state(island: table, host: table, request: table) -> table|nil`
- Produces: `GraphViewIslandHost:state-after-member-drag-end(island: table, request: table) -> table|nil`

- [ ] **Step 1: Add island host delegation tests**

In `assets/lua/tests/test-graph-island-presenters.fnl`, add a local presenter fixture and tests equivalent to:

```fennel
(fn island-host-delegates-member-drag-end-state []
    (local called? false)
    (local presenter {:kind "custom"
                      :apply (fn [_island _host] {})
                      :member-drag-end-state
                      (fn [island _host request]
                          (set called? true)
                          {:position [request.position.x request.position.y request.position.z]
                           :source island.id})})
    (local host (GraphViewIslandHost {:presenters [presenter]
                                      :position-for-key (fn [_key] (glm.vec3 0 0 0))
                                      :set-member-position (fn [_island-id _key _position])
                                      :set-member-pinned (fn [_island-id _key _pinned?])}))
    (local state (host:state-after-member-drag-end
                   {:id "island-1" :kind "custom" :members ["item:a"]}
                   {:member-key "item:a" :position (glm.vec3 9 8 7)}))
    (assert called? "host should call presenter hook")
    (assert (= state.source "island-1") "host should return presenter state"))

(fn island-host-returns-nil-when-presenter-has-no-member-drag-hook []
    (local presenter {:kind "custom" :apply (fn [_island _host] {})})
    (local host (GraphViewIslandHost {:presenters [presenter]
                                      :position-for-key (fn [_key] (glm.vec3 0 0 0))
                                      :set-member-position (fn [_island-id _key _position])
                                      :set-member-pinned (fn [_island-id _key _pinned?])}))
    (local state (host:state-after-member-drag-end
                   {:id "island-1" :kind "custom" :members ["item:a"]}
                   {:member-key "item:a" :position (glm.vec3 1 2 3)}))
    (assert (= state nil) "presenters without hook should decline island movement"))
```

Register both tests.

- [ ] **Step 2: Run tests and record RED evidence**

```bash
./build/space -m tests.test-graph-island-presenters:main
```

Expected RED: failure because `state-after-member-drag-end` is missing.

- [ ] **Step 3: Implement host method**

In `assets/lua/graph/view/island-host.fnl`, add this method to the returned object literal near `:reconcile-island`:

```fennel
:state-after-member-drag-end
(fn [self island request]
    (assert island "GraphViewIslandHost.state-after-member-drag-end requires island")
    (assert request "GraphViewIslandHost.state-after-member-drag-end requires request")
    (assert request.member-key "GraphViewIslandHost.state-after-member-drag-end requires request.member-key")
    (assert request.position "GraphViewIslandHost.state-after-member-drag-end requires request.position")
    (local presenter (presenter-for-kind island.kind))
    (when (not presenter)
        (error (.. "GraphViewIslandHost missing presenter for island kind: " (tostring island.kind))))
    (if presenter.member-drag-end-state
        (do
            (local state (presenter.member-drag-end-state island self request))
            (when (and state (not (= (type state) "table")))
                (error "GraphViewIslandHost presenter member-drag-end-state must return table or nil"))
            state)
        nil))
```

- [ ] **Step 4: Run focused validation for Task 2**

```bash
make fennel-check
make constraints
./build/space -m tests.test-graph-island-presenters:main
```

Expected: all pass.

- [ ] **Step 5: Commit Task 2**

```bash
git add assets/lua/graph/view/island-host.fnl \
        assets/lua/tests/test-graph-island-presenters.fnl
git commit -m "feat(graph): mediate island member drag state"
```

---

### Task 3: Wire GraphView alt-drag end to island state updates

**Files:**
- Modify: `assets/lua/graph/view/movables.fnl`
- Modify: `assets/lua/graph/view/init.fnl`
- Test: `assets/lua/tests/test-graph-view-islands.fnl`

**Interfaces:**
- Consumes: `GraphViewIslandHost:state-after-member-drag-end(island: table, request: table) -> table|nil`
- Consumes: `graph-map:list-islands() -> table[]`
- Consumes: `graph-map:update-island(id: string, patch: table) -> island record`
- Produces: GraphView alt-drag-end behavior where dropped island members update island body state before reconciliation.

- [ ] **Step 1: Add GraphView integration test for non-first member alt-drag**

In `assets/lua/tests/test-graph-view-islands.fnl`, extend `with-list-fixture` so it creates a second item and exposes it to the callback:

```fennel
(local item-b (string-store:create-entity {:id "item-b" :value "B"}))
(local list (list-store:create-entity {:id "list"
                                       :name "List"
                                       :items [(.. "string-entity:" item.id)
                                               (.. "string-entity:" item-b.id)]}))
(local second-item-key (.. "string-entity:" item-b.id))
(map:load-by-key second-item-key)
```

Add `:second-item-key second-item-key` to the fixture table passed to `f`.

Add a test using the existing fixture style with these assertions:

```fennel
(fn check-alt-dragging-second-island-member-moves-whole-island-on-drag-end [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local item-node (map:lookup fixture.item-key))
    (local second-node (map:lookup fixture.second-item-key))
    (local list-entry (. movables.by-node list-node))
    (local second-entry (. movables.by-node second-node))
    (list-entry.target:set-position (glm.vec3 24 0 0))
    (list-node:expand-items-as-island)
    (second-entry.on-drag-start second-entry {} {:mod 256})
    (second-entry.target:set-position (glm.vec3 200 300 0))
    (assert-vec3 (view:get-position item-node) (glm.vec3 48 0 0)
                 "other members should not live-move during alt drag")
    (second-entry.on-drag-end second-entry {})
    (local island (map:get-island "ordered-list:list"))
    (assert (= (. island.state.position 1) 200) "island body x should update from second member drop")
    (assert (= (. island.state.position 2) 324) "island body y should keep second member at drop")
    (assert-vec3 (view:get-position item-node) (glm.vec3 200 324 0)
                 "first member should move to new island body")
    (assert-vec3 (view:get-position second-node) (glm.vec3 200 300 0)
                 "dragged second member should stay at dropped position after reconcile"))
```

Register the test as `GraphView alt-dragging second island member moves whole island on drag end`. Keep the existing non-alt snap-back test intact.

- [ ] **Step 2: Run GraphView test and record RED evidence**

```bash
./build/space -m tests.test-graph-view-islands:main
```

Expected RED: island state does not update from alt-drag end yet.

- [ ] **Step 3: Forward drag callback payloads through GraphViewMovables**

In `assets/lua/graph/view/movables.fnl`, update callback forwarding:

```fennel
:on-drag-start (fn [entry drag payload]
                 (when on-drag-start
                     (on-drag-start node entry drag payload)))
:on-drag-end (fn [entry drag]
               (when on-drag-end
                   (on-drag-end node entry drag))
               (when (and persistence persistence.schedule-save)
                   (persistence:schedule-save)))
```

Preserve the existing persistence scheduling after `on-drag-end`.

- [ ] **Step 4: Track alt-modified graph node drags in GraphView**

In `assets/lua/graph/view/init.fnl`, near existing drag state locals, add:

```fennel
(var drag-alt? false)
```

Update the `GraphViewMovables` callbacks around the existing `:on-drag-start` and `:on-drag-end` definitions:

```fennel
:on-drag-start (fn [node _entry _drag payload]
                  (set drag-active? true)
                  (set drag-node node)
                  (set drag-alt? (Modifiers.alt-held? (and payload payload.mod))))
```

On drag end, capture and clear the state before the existing label and island reconciliation work:

```fennel
:on-drag-end (fn [node _entry _drag]
               (local alt-drag? drag-alt?)
               (set drag-active? false)
               (set drag-node nil)
               (set drag-alt? false))
```

- [ ] **Step 5: Add island-member lookup and state update helpers in GraphView**

In `assets/lua/graph/view/init.fnl`, add local helpers before the `GraphViewMovables` construction:

```fennel
(fn island-contains-member? [island member-key]
    (accumulate [found false _ key (ipairs (or island.members []))]
        (or found (= key member-key))))

(fn update-islands-after-member-drag-end! [node]
    (when (and node node.key)
        (assert graph-map.update-island
                "GraphView island member alt-drag requires GraphMap.update-island")
        (local member-key node.key)
        (local position (get-position nil node))
        (each [_ island (ipairs (graph-map:list-islands))]
            (when (island-contains-member? island member-key)
                (local next-state (island-host:state-after-member-drag-end
                                    island {:member-key member-key
                                            :position position}))
                (when next-state
                    (graph-map:update-island island.id {:state next-state}))))))
```

Use the existing local `get-position` helper so the position goes through the same validation as `view:get-position`.

- [ ] **Step 6: Invoke helper only for alt drag end**

In the `:on-drag-end` callback, invoke the helper before labels/reconciliation:

```fennel
(when alt-drag?
    (update-islands-after-member-drag-end! node))
(update-labels [node] {:force? true})
(refresh-label-positions [node])
(reconcile-graph-islands!)
```

Non-alt drag end must not call `update-islands-after-member-drag-end!`.

- [ ] **Step 7: Run focused validation for Task 3**

```bash
make fennel-check
make constraints
./build/space -m tests.test-graph-view-islands:main
```

Expected: all pass.

- [ ] **Step 8: Commit Task 3**

```bash
git add assets/lua/graph/view/movables.fnl \
        assets/lua/graph/view/init.fnl \
        assets/lua/tests/test-graph-view-islands.fnl
git commit -m "feat(graph): move islands from member drag handles"
```

---

### Task 4: Document island member drag handles and run focused validation

**Files:**
- Modify: `docs/dev/notes/graph.md`

**Interfaces:**
- Consumes: completed presenter-owned alt-drag behavior.
- Produces: documented graph presentation island interaction contract.

- [ ] **Step 1: Document presenter-owned island movement**

In `docs/dev/notes/graph.md`, add a note under the graph presentation islands section:

```markdown
### Island member drag handles

Alt-dragging a presentation island member moves the island body on drag end.
During the drag, only the dragged member follows the pointer; after drop,
`GraphView` asks the island presenter to derive the next island state and then
reconciles the island. Ordered-list islands store the moved body as
`island.state.position`. Normal non-alt member drag remains snap-back under
island reconciliation.
```

- [ ] **Step 2: Run focused validation ladder**

```bash
make fennel-check
make constraints
./build/space -m tests.test-graph-island-presenters:main
./build/space -m tests.test-ordered-list-islands:main
./build/space -m tests.test-graph-view-islands:main
```

Expected: all pass.

- [ ] **Step 3: Commit Task 4**

```bash
git add docs/dev/notes/graph.md
git commit -m "docs(graph): document island member drag handles"
```

---

## Acceptance Criteria

- Alt-dragging any member of an ordered-list island updates `island.state.position` on drag end.
- During the drag, only the dragged member moves.
- After drag end reconciliation, the dragged member remains at its dropped position and other members move around the new island body.
- Non-alt member dragging keeps the existing snap-back behavior.
- Legacy ordered-list islands without `state.position` are upgraded to an explicit position after alt-drag.
- `GraphView` contains no ordered-list index or spacing math.
- Focused validation passes in the documented ladder order.
