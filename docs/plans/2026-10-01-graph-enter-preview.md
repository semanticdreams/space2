# Graph Enter Preview Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pressing Enter on a focused graph node expands its inline preview card instead of opening the full node view.

**Architecture:** Keep the behavior in `GraphView`, which already owns node presentations, focus bounds, labels, pins, persistence, and layout refreshes. Add an idempotent preview-expansion helper and route graph-node focus activation plus graph-activity fallback activation through it, while preserving explicit full-view opening from context-menu and card-header actions.

**Tech Stack:** Space Fennel, GraphView presentation lifecycle, focus manager activation, graph activity hooks, project-native Fennel validation.

## Global Constraints

- Pressing Enter on a focused compact graph node expands its inline preview card.
- Pressing Enter when the node is already represented by an expanded preview card is idempotent: it leaves the card expanded and does not collapse it.
- Pressing Enter must not open the full node view.
- Full node view opening remains available through explicit context-menu and expanded-card header actions.
- Existing Alt+Enter and Alt+double-click linked-frontier behavior remains unchanged.
- The change stays in the graph view/presentation interaction layer; graph core and domain node persistence do not own this behavior.
- Use project Fennel idioms: `local` instead of `let`, multi-branch `if`, factory functions instead of `.new` constructors.
- Validate Fennel through `tools.fennel-check`, constraints, and focused Space tests; do not use system Fennel or system Lua as validation oracles.

---

## File Structure

- `assets/lua/graph/view/init.fnl`: Owns the implementation. Add an idempotent graph-node preview expansion helper, use it from focus-node activation, and expose a focused-node preview API for activity fallback.
- `assets/lua/graph-activity-unit.fnl`: Change the activity-level focused activation hook from full-open to preview-expand.
- `assets/lua/tests/test-graph-view.fnl`: Add direct GraphView focus activation coverage for Enter expanding preview, idempotent repeat activation, focus association survival, and explicit full-open preservation. Update existing focus-replacement activation coverage so it expects preview expansion instead of full view opening.
- `assets/lua/tests/test-states.fnl`: Rename/update the normal-state Enter fallback test so it asserts generic activity activation without encoding the old full-open wording.
- `docs/dev/notes/graph.md`: Document the preview/full-view interaction contract under “Preview vs UX node vs full view”.

### Task 1: Make Graph Node Enter Expand Preview

**Files:**
- Modify: `assets/lua/graph/view/init.fnl:149`, `assets/lua/graph/view/init.fnl:348-368`, `assets/lua/graph/view/init.fnl:1002-1031`, `assets/lua/graph/view/init.fnl:1583-1593`
- Modify: `assets/lua/graph-activity-unit.fnl:122-126`
- Modify: `assets/lua/tests/test-graph-view.fnl:1146-1265`, `assets/lua/tests/test-graph-view.fnl:3615-3618`
- Modify: `assets/lua/tests/test-states.fnl:1831-1857`
- Modify: `docs/dev/notes/graph.md:50-58`

**Interfaces:**
- Consumes: existing `toggle-node-presentation node`, `expanded-nodes`, `registry.points`, `focus-nodes`, `focused-node`, `views:open node`, `GraphView:open-node`, `GraphView:open-focused-node`, focus manager `activate-focused-from-payload payload`.
- Produces: internal `expand-node-presentation node -> true|nil`; public `GraphView:expand-focused-node -> true|nil`; unchanged explicit full-open APIs `GraphView:open-node node-or-key opts -> true` and `GraphView:open-focused-node -> true|nil`.

- [ ] **Step 1: Add the failing GraphView focus activation test**

  Add this test near `graph-expands-node-inline-on-double-click` and `graph-expanded-card-uses-preview-and-measures-child` in `assets/lua/tests/test-graph-view.fnl`:

  ```fennel
  (fn graph-enter-expands-focused-node-inline-idempotently []
      (with-temp-data-dir
          (fn [_root]
              (local ctx (make-ctx))
              (local graph (make-test-graph-map))
              (local state {:measure (glm.vec3 73 37 0)})
              (var full-view-opened 0)
              (local node (Graph.GraphNode {:key "enter-preview-node"
                                            :label "Enter Preview"
                                            :view (fn [_node _opts]
                                                    (set full-view-opened (+ full-view-opened 1))
                                                    (fn [_ctx]
                                                      {:layout (Layout {:name "unexpected-full-view"})}))
                                            :preview (tracked-preview state)}))
              (graph:add-node node {:position (glm.vec3 0 0 0)})
              (local view (GraphView {:graph-map graph
                                      :ctx ctx}))
              (local point (. view.points node))
              (local focus-node (. view.focus-nodes node))
              (assert focus-node "GraphView should create a focus node for graph nodes")
              (focus-node:request-focus)
              (local handled? (ctx.focus-manager:activate-focused-from-payload {:mod 0}))
              (assert handled? "Enter activation should be handled by graph node focus")
              (local card (. view.points node))
              (assert (not (= card point)) "Enter should replace compact point with expanded card")
              (assert card._card-size "Enter should expand the inline preview card")
              (assert (= state.built-node node) "Enter expansion should build the node preview")
              (assert (= full-view-opened 0) "Enter should not open the full node view")
              (assert (= (. view.focus-nodes node) focus-node)
                      "Graph node focus association should survive point-to-card replacement")
              (local focused (ctx.focus-manager:get-focused-node))
              (assert (= focused focus-node)
                      "Focused graph node should remain focused after preview expansion")
              (ctx.focus-manager:activate-focused-from-payload {:mod 0})
              (assert (= (. view.points node) card)
                      "Second Enter should leave the existing card expanded")
              (assert card._card-size "Second Enter should not collapse the expanded card")
              (assert (= full-view-opened 0)
                      "Second Enter should still not open the full node view")
              (local open-button (. card.header-bar.children 4 :element))
              (open-button:on-click {})
              (assert (= full-view-opened 1)
                      "Card header open button should still open the full node view")
              (view:drop)
              (graph:drop))))
  ```

  Register it next to the existing inline expansion tests:

  ```fennel
  (table.insert tests {:name "GraphView Enter expands focused node inline idempotently"
                       :fn graph-enter-expands-focused-node-inline-idempotently})
  ```

- [ ] **Step 2: Update existing focus replacement activation expectations**

  In `graph-compact-replacement-refreshes-focus-binding`, keep the replacement/focus binding setup but change activation expectations from opening the replacement full view to expanding the replacement preview. Give both replacement candidates tracked previews so the activated replacement can build a card:

  ```fennel
  (local first-state {})
  (local second-state {})
  (var first-opened 0)
  (var second-opened 0)
  (local first (Graph.GraphNode {:key "focus-swap"
                                 :preview (tracked-preview first-state)
                                 :view (fn [_node]
                                           (set first-opened (+ first-opened 1))
                                           (fn [_ctx]
                                               {:layout (Layout {:name "first-focus-view"})}))}))
  (local second (Graph.GraphNode {:key "focus-swap"
                                  :preview (tracked-preview second-state)
                                  :view (fn [_node]
                                            (set second-opened (+ second-opened 1))
                                            (fn [_ctx]
                                                {:layout (Layout {:name "second-focus-view"})}))}))
  ```

  Replace the final full-open assertions with preview assertions:

  ```fennel
  (ctx.focus.manager:activate-focused {})
  (local card (. view.points second))
  (assert card._card-size
          "Replacement focus activation should expand replacement preview")
  (assert (= second-state.built-node second)
          "Replacement focus activation should build replacement preview")
  (assert (= first-opened 0)
          "Replacement focus activation should not open stale original node")
  (assert (= second-opened 0)
          "Replacement focus activation should not open replacement full view")
  ```

- [ ] **Step 3: Run the focused test and verify the old behavior fails**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  ```

  Expected before implementation: FAIL in `GraphView Enter expands focused node inline idempotently` because focus activation opens the full view instead of replacing the point with a preview card.

- [ ] **Step 4: Add the idempotent preview expansion helper**

  In `assets/lua/graph/view/init.fnl`, near the existing `var toggle-node-presentation nil`, add:

  ```fennel
  (var expand-node-presentation nil)
  ```

  After the existing `(set toggle-node-presentation ...)` form, add:

  ```fennel
  (set expand-node-presentation
       (fn [node]
           (assert-not-dropped "expand-node-presentation")
           (when (not node) (lua "return nil"))
           (local current-point (. registry.points node))
           (when (not current-point) (lua "return nil"))
           (if (. expanded-nodes node)
               true
               (do
                 (toggle-node-presentation node)
                 true))))
  ```

  Keep `toggle-node-presentation` unchanged for mouse/menu collapse behavior; the helper must be expand-only and idempotent.

- [ ] **Step 5: Route graph-node focus activation through preview expansion**

  In `bind-focus-node-activate`, keep the Alt branch unchanged and replace the non-Alt branch:

  ```fennel
  (expand-node-presentation node)
  ```

  The resulting branch shape should still return truthy for handled compact and already-expanded nodes, and should not call `views:open node`.

- [ ] **Step 6: Expose focused preview expansion for graph activity fallback**

  In the public `view` method setup near `open-focused-node`, add:

  ```fennel
  (set view.expand-focused-node (fn [_self]
                                    (assert-not-dropped "expand-focused-node")
                                    (when focused-node
                                        (expand-node-presentation focused-node))))
  ```

  Leave `view.open-node` and `view.open-focused-node` in place so explicit full-open affordances and any non-Enter callers can continue to use them.

- [ ] **Step 7: Route graph activity focused activation to preview expansion**

  In `assets/lua/graph-activity-unit.fnl`, change `activate-focused-node` to use the new preview API:

  ```fennel
  (fn activate-focused-node []
    (local graph-view app.graph-view)
    (and graph-view
         graph-view.expand-focused-node
         (graph-view:expand-focused-node)))
  ```

- [ ] **Step 8: Update the normal-state fallback test wording and stub**

  In `assets/lua/tests/test-states.fnl`, rename `exercise-normal-state-enter-opens-focused-graph-node` to `exercise-normal-state-enter-activates-focused-graph-node`, rename the counter from `opened` to `activated`, and use an `expand-focused-node` stub:

  ```fennel
  (var activated 0)
  (set app.graph-view {:expand-focused-node (fn [_self]
                                             (set activated (+ activated 1))
                                             true)})
  (set app.activity-activate-focused
       (fn []
         (app.graph-view:expand-focused-node)))
  ```

  Update the assertion message to:

  ```fennel
  (assert (= activated 1) "Enter should activate focused graph node")
  ```

  Also update the test registration name at the bottom of the file to remove the stale “opens” wording.

- [ ] **Step 9: Document the interaction contract**

  In `docs/dev/notes/graph.md`, under `### Preview vs UX node vs full view`, add a short paragraph after the first preview paragraph:

  ```markdown
  In graph view, double-clicking a compact node point and pressing Enter on a focused graph node both expand the inline preview card. Enter expansion is idempotent: once the compact point has been replaced by an expanded card, another Enter leaves the preview expanded rather than collapsing it or opening the full view. Full views remain explicit actions through context-menu `Open` and expanded-card header controls.
  ```

- [ ] **Step 10: Run Fennel compile checks**

  Run:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/init.fnl --file assets/lua/graph-activity-unit.fnl --file assets/lua/tests/test-graph-view.fnl --file assets/lua/tests/test-states.fnl
  ```

  Expected: PASS. If `./build/space` is missing or stale, first run `make build` with timeout `14400000`.

- [ ] **Step 11: Run constraints**

  Run:

  ```bash
  make constraints
  ```

  Expected: PASS. Constraint-impact note for the commit: changed graph interaction behavior only; no graph persistence/domain constraints should change.

- [ ] **Step 12: Run focused tests**

  Run graph view tests:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  ```

  Run normal state tests because Enter routing text/stub changed:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-states:main
  ```

  Run graph activity slot tests because `graph-activity-unit.fnl` changed:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
  ```

  Expected: all PASS.

- [ ] **Step 13: Commit implementation**

  Stage only the files changed by this task and commit with a project-style message:

  ```bash
  git add assets/lua/graph/view/init.fnl assets/lua/graph-activity-unit.fnl assets/lua/tests/test-graph-view.fnl assets/lua/tests/test-states.fnl docs/dev/notes/graph.md
  git commit -m "fix(ui): expand graph preview on enter"
  ```

  Include the focused validation results and the constraint-impact note in the commit/report handoff.
