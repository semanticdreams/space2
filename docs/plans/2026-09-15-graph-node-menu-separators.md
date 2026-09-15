# Graph Node Menu Separators Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add first-class menu separators and use them so graph node menus show general graph actions first, then a separator, then node-specific actions.

**Architecture:** The generic menu path will accept a mixed list of action entries and separator entries, rendering actions as `Button`s and separators as non-clickable divider rows. `MenuManager` will preserve separators while wrapping only real actions with close behavior. `GraphView` will continue to own graph-node menu composition, including `Copy key`, and will place node adapter actions at the bottom.

**Tech Stack:** Space Fennel, Space Fennel UI widgets (`Flex`, `Layout`, `Button`, `Rectangle`), graph view Fennel modules, `gl.clipboard-set`, project-native Fennel validation through `tools.fennel-check`, constraints, and focused Fennel tests.

## Global Constraints

- `GraphView` composes node context menu actions in `assets/lua/graph/view/init.fnl`.
- The desired graph node context menu order is: `Open`, `Copy key`, `Expand` or `Collapse`, `cube`, `Remove from Map`, separator, node-specific actions from `node.actions`.
- The separator is always present for graph node context menus, even when the node has no node-specific actions.
- `Copy key` copies `(tostring node.key)` to the clipboard through the existing `gl.clipboard-set` binding and is treated as a general graph-view action.
- Add first-class separator support to the generic menu path rather than encoding separators as fake actions.
- `MenuManager` should preserve separator entries when wrapping actions for display.
- `Menu` should accept the separator entry shape `{:type :separator}` without requiring a name or click handler.
- `Menu` should render separator entries as non-clickable divider rows, not `Button`s.
- `GraphView` should own graph-node menu composition, including the `Copy key` action, and insert the separator between general graph actions and node-specific actions.
- Action entries still require a resolved name.
- Separator entries do not require a name or handler.
- Unknown nameless entries should continue to fail loudly instead of silently rendering empty menu rows.
- `Copy key` should fail loudly if the clipboard binding fails; it should not swallow clipboard errors.
- Separator rows should not be clickable and should not invoke menu close behavior.
- Follow Space Fennel UI ownership rules: composite widgets own and drop their direct children, and layout transforms are written during layout passes.
- Use `local` instead of `let` in Fennel.
- Use factory functions instead of constructors (`.new`).
- Do not add legacy aliases or compatibility shims; `{:type :separator}` is the only separator entry shape.
- Do not expose a new public `GraphView` method solely for tests.
- On delimiter or parse errors, inspect the nearest enclosing form around the reported location; if deeply nested, move logic into helper functions instead of guessing at closing delimiters.
- Before any `./build/space` validation, run `make build` with timeout `14400000` if `./build/space` is missing or stale.
- Focused Fennel validation order is mandatory: touched-file `tools.fennel-check` first, constraints second, focused Fennel tests third.
- Complete relevant local suites for this change: `tests.test-menu:main` and `tests.test-graph-view:main`.
- Broader final integration gate: PR CI is the full integration gate.
- Out of scope: root context menu reordering, node adapter API changes, graph persistence changes, new theme token work, keyboard navigation changes, and visual redesign beyond a simple separator divider.
- HUMAN_DECISION_REQUIRED: none.

---

### Task 1: Generic Menu Separator Support

**Files:**
- Modify: `assets/lua/menu.fnl`
- Modify: `assets/lua/menu-manager.fnl`
- Test: `assets/lua/tests/test-menu.fnl`

**Interfaces:**
- Consumes: Existing `Menu` factory signature `(Menu opts) -> build`, where `opts.actions` is an array of action tables.
- Produces: `Menu` accepts mixed `opts.actions` entries:
  - Action entry input: `{:name string :text string? :icon any? :variant any? :padding any? :fn function? :handler function? :on-click function?}`.
  - Separator entry input: `{:type :separator}`.
  - Normalized action entry: `{:type :action :name string :handler function? :icon any? :variant any? :padding any?}`.
  - Normalized separator entry: `{:type :separator}`.
  - Built menu object keeps `:actions` as the normalized mixed entry list and keeps `:buttons` as only clickable action buttons, in action order.
- Produces: `MenuManager:open(opts)` preserves separator entries and wraps only action entries with close-on-action-click behavior.

- [ ] **Step 1: Add failing generic `Menu` separator tests**

  In `assets/lua/tests/test-menu.fnl`, add tests near the existing menu widget tests after `menu-grows-downward-from-click` and before `menu-manager-opens-and-closes`.

  Add this test:

  ```fennel
  (fn menu-separator-renders-non-clickable-row []
    (local clickables (make-clickables-stub))
    (local hoverables (make-hoverables-stub))
    (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
    (local calls [])
    (local menu
      ((Menu {:actions [{:name "Alpha"
                         :on-click (fn [_button _event]
                                     (table.insert calls "Alpha"))}
                        {:type :separator}
                        {:name "Beta"
                         :on-click (fn [_button _event]
                                     (table.insert calls "Beta"))}]})
       ctx))
    (assert (= (length menu.actions) 3)
            "Menu should preserve separator entries in normalized actions")
    (assert (= (. menu.actions 1 :type) :action)
            "Menu should normalize named entries as action entries")
    (assert (= (. menu.actions 2 :type) :separator)
            "Menu should normalize separator entries by type")
    (assert (= (. menu.actions 3 :type) :action)
            "Menu should preserve action order after separator")
    (assert (= (length menu.buttons) 2)
            "Menu should build buttons only for action entries")
    (local flex-layout (. menu.layout.children 1))
    (assert (= (length flex-layout.children) 3)
            "Menu layout should include one row per action or separator entry")
    (assert (= (. flex-layout.children 2 :name) "menu-separator")
            "Menu separator row should use a named separator layout")
    ((. menu.buttons 1):on-click {:button 1})
    ((. menu.buttons 2):on-click {:button 1})
    (assert (= (length calls) 2)
            "Menu action buttons before and after a separator should remain invokable")
    (assert (= (. calls 1) "Alpha")
            "First action should fire before separator-adjacent action")
    (assert (= (. calls 2) "Beta")
            "Second action should fire after separator")
    (menu:drop))
  ```

  Add this test:

  ```fennel
  (fn menu-unknown-nameless-entry-errors []
    (local (ok err)
      (pcall
        (fn []
          ((Menu {:actions [{:type :unknown}]})
           (make-test-ctx {:clickables (make-clickables-stub)
                           :hoverables (make-hoverables-stub)})))))
    (assert (not ok)
            "Menu should reject unknown nameless entries")
    (assert (string.find (tostring err) "Menu entry has unknown type" 1 true)
            "Menu should report unknown entry types explicitly"))
  ```

  Register both tests near the existing menu test registrations:

  ```fennel
  (table.insert tests {:name "Menu separator renders non-clickable row"
                       :fn menu-separator-renders-non-clickable-row})
  (table.insert tests {:name "Menu unknown nameless entry errors"
                       :fn menu-unknown-nameless-entry-errors})
  ```

- [ ] **Step 2: Add failing `MenuManager` separator preservation test**

  In `assets/lua/tests/test-menu.fnl`, add this test after `menu-manager-opens-and-closes`:

  ```fennel
  (fn menu-manager-preserves-separators-without-close-action []
    (reset-engine-events)
    (local clickables (make-clickables-stub))
    (local hoverables (make-hoverables-stub))
    (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
    (local hud (make-hud-stub ctx))
    (local calls [])
    (local manager
      (MenuManager {:clickables clickables
                    :hud hud}))
    (manager:open {:actions [{:name "First"
                              :fn (fn [_button _event]
                                    (table.insert calls "First"))}
                             {:type :separator}
                             {:name "Second"
                              :fn (fn [_button _event]
                                    (table.insert calls "Second"))}]
                   :position (glm.vec3 1 2 0)})
    (assert (= (length hud.overlay-root.children) 1)
            "MenuManager should open a menu with separator entries")
    (local element (. (. hud.overlay-root.children 1) :element))
    (assert (= (length element.actions) 3)
            "MenuManager should preserve separator entries in menu actions")
    (assert (= (. element.actions 2 :type) :separator)
            "MenuManager should pass separator entries through to Menu")
    (assert (= (length element.buttons) 2)
            "MenuManager should not create a button for the separator")
    ((. element.buttons 2):on-click {:button 1})
    (assert (= (length calls) 1)
            "Action after separator should remain invokable")
    (assert (= (. calls 1) "Second")
            "Second action should fire through MenuManager wrapper")
    (assert (= (length hud.overlay-root.children) 0)
            "MenuManager should close after action click, not because of separator")
    (manager:drop))
  ```

  Register it near the existing menu manager test registrations:

  ```fennel
  (table.insert tests {:name "Menu separator manager preserves entries"
                       :fn menu-manager-preserves-separators-without-close-action})
  ```

- [ ] **Step 3: Run focused menu tests and verify expected failure**

  If `./build/space` is missing or stale, first run:

  ```bash
  make build
  ```

  Use timeout `14400000`.

  Then run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="Menu separator" ./build/space -m tests.test-menu:main
  ```

  Expected: FAIL before implementation because `Menu` currently requires every entry to have a name and `MenuManager` does not preserve separators.

- [ ] **Step 4: Implement separator normalization and rendering in `assets/lua/menu.fnl`**

  Add a rectangle import at the top:

  ```fennel
  (local Rectangle (require :rectangle))
  ```

  Add helper definitions near `resolve-action-handler`:

  ```fennel
  (local default-separator-height 1)
  (local default-separator-thickness 0.08)
  (local default-separator-color (glm.vec4 0.35 0.35 0.35 1))

  (fn separator-entry? [entry]
    (= entry.type :separator))
  ```

  Replace `normalize-actions` with mixed-entry normalization:

  ```fennel
  (fn normalize-actions [actions]
    (local normalized [])
    (each [_ entry (ipairs (or actions []))]
      (when (not (= (type entry) :table))
        (error "Menu actions must be provided as tables"))
      (if (separator-entry? entry)
          (table.insert normalized {:type :separator})
          entry.type
          (error (.. "Menu entry has unknown type: " (tostring entry.type)))
          (do
            (local name (resolve-action-name entry))
            (assert name "Menu action is missing a name")
            (table.insert normalized
                          {:type :action
                           :name name
                           :handler (resolve-action-handler entry)
                           :icon entry.icon
                           :variant entry.variant
                           :padding entry.padding}))))
    normalized)
  ```

  Add a local separator widget before `Menu`:

  ```fennel
  (fn MenuSeparator []
    (fn build [ctx]
      (local rectangle ((Rectangle {:color default-separator-color}) ctx))

      (fn measurer [self]
        (set self.measure (glm.vec3 0 default-separator-height 0)))

      (fn layouter [self]
        (local row-size (or self.size self.measure (glm.vec3 0 default-separator-height 0)))
        (local thickness (math.min default-separator-thickness row-size.y))
        (set rectangle.layout.size (glm.vec3 row-size.x thickness 0))
        (set rectangle.layout.position
             (+ self.position
                (glm.vec3 0 (* 0.5 (- row-size.y thickness)) 0)))
        (set rectangle.layout.rotation self.rotation)
        (set rectangle.layout.depth-offset-index self.depth-offset-index)
        (set rectangle.layout.clip-region self.clip-region)
        (rectangle.layout:layouter))

      (local layout
        (Layout {:name "menu-separator"
                 :children [rectangle.layout]
                 :measurer measurer
                 :layouter layouter}))

      (fn drop [_self]
        (layout:drop)
        (rectangle:drop))

      {:layout layout
       :rectangle rectangle
       :drop drop}))
  ```

  Update `children` construction in `Menu` so separator entries build `MenuSeparator` rows and action entries build `Button`s:

  ```fennel
  (local children
    (icollect [_ action (ipairs actions)]
      (FlexChild
        (fn [child-ctx]
          (if (= action.type :separator)
              ((MenuSeparator) child-ctx)
              (do
                (local button
                  ((Button {:text action.name
                            :icon action.icon
                            :content-spacing (or action.content-spacing default-spacing)
                            :variant (or action.variant default-variant)
                            :padding (or action.padding default-padding)
                            :on-click (if action.handler
                                          (fn [btn event]
                                            (action.handler btn event))
                                          nil)})
                   child-ctx))
                (table.insert buttons button)
                button)))
        0)))
  ```

- [ ] **Step 5: Preserve separators in `assets/lua/menu-manager.fnl`**

  Replace `wrap-actions` with this shape:

  ```fennel
  (fn wrap-actions [actions]
    (icollect [_ action (ipairs (or actions []))]
      (if (= action.type :separator)
          {:type :separator}
          {:name (or action.name action.text)
           :text action.text
           :icon action.icon
           :variant action.variant
           :padding action.padding
           :on-click (fn [button event]
                       (when action.fn
                         (action.fn button event))
                       (when action.handler
                         (action.handler button event))
                       (when action.on-click
                         (action.on-click button event))
                       (close))})))
  ```

- [ ] **Step 6: Run focused validation for Task 1 in required order**

  Compile check first:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/menu.fnl --file assets/lua/menu-manager.fnl --file assets/lua/tests/test-menu.fnl
  ```

  Constraints second:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets make constraints
  ```

  Focused tests third:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="Menu separator" ./build/space -m tests.test-menu:main
  ```

  Expected: PASS.

- [ ] **Step 7: Run complete relevant menu suite**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-menu:main
  ```

  Expected: PASS.

- [ ] **Step 8: Commit Task 1**

  ```bash
  git add assets/lua/menu.fnl assets/lua/menu-manager.fnl assets/lua/tests/test-menu.fnl
  git commit -m "feat(ui): add menu separators"
  ```

---

### Task 2: Graph Node Menu Ordering and Copy Key

**Files:**
- Modify: `assets/lua/graph/view/init.fnl`
- Modify: `assets/lua/tests/test-graph-view.fnl`
- Modify: `docs/dev/features/graph-browsing.md`

**Interfaces:**
- Consumes: Task 1 mixed menu entry support, specifically separator entry `{:type :separator}` accepted by `Menu` and preserved by `MenuManager`.
- Consumes: Existing private `node-menu-actions node` in `assets/lua/graph/view/init.fnl`.
- Produces: `node-menu-actions(node)` returns an array ordered as:
  1. `{:name "Open" ...}`
  2. `{:name "Copy key" :icon "content_copy" :fn function}`
  3. `{:name "Expand" ...}` or `{:name "Collapse" ...}`
  4. `{:name "cube" ...}`
  5. `{:name "Remove from Map" ...}`
  6. `{:type :separator}`
  7. zero or more validated node-specific action tables from `node.actions`
- Produces: `Copy key` action calls `(gl.clipboard-set (tostring node.key))` and lets clipboard errors propagate.
- Produces: Compact point right-click menus and expanded card header menus use the same ordered mixed entry list.

- [ ] **Step 1: Confirm `content_copy` icon is available**

  Run:

  ```bash
  rtk rg '^content_copy$' assets/material-design-icons/icons.txt
  ```

  Expected: PASS with one exact icon name match. If it fails, use `content_paste` only if it has an exact match; otherwise omit the icon and keep the action text.

- [ ] **Step 2: Update failing expanded-card graph menu test**

  In `assets/lua/tests/test-graph-view.fnl`, update `expanded-card-header-buttons-work` assertions around the first menu open from the four-entry expectation to this six-entry expectation:

  ```fennel
  (assert (= (length menu-actions) 6)
          "Header menu should include Open, Copy key, Collapse, cube, Remove from Map, and separator")
  (assert (= (. menu-actions 1 :name) "Open"))
  (assert (= (. menu-actions 2 :name) "Copy key"))
  (assert (= (. menu-actions 3 :name) "Collapse"))
  (assert (= (. menu-actions 4 :name) "cube"))
  (assert (= (. menu-actions 5 :name) "Remove from Map"))
  (assert (= (. menu-actions 6 :type) :separator)
          "Header menu should keep a separator even without node-specific actions")
  ```

  Keep the remove invocation at index 5:

  ```fennel
  ((. menu-actions 5 :fn) nil {})
  ```

- [ ] **Step 3: Update compact right-click graph menu test**

  In `assets/lua/tests/test-graph-view.fnl`, update `graph-point-right-click-opens-node-actions-menu` to stub the clipboard and assert the new seven-entry order.

  Add local state near the other counters:

  ```fennel
  (var copied nil)
  (local original-clipboard-set gl.clipboard-set)
  (set gl.clipboard-set (fn [value]
                          (set copied value)))
  ```

  Ensure teardown restores the stub after restoring `app.scene`:

  ```fennel
  (set gl.clipboard-set original-clipboard-set)
  ```

  Replace ordering assertions and action invocations with:

  ```fennel
  (assert (= (length opened.actions) 7)
          "Node menu should include Open, Copy key, Expand, cube, Remove from Map, separator, and custom actions")
  (assert (= (. opened.actions 1 :name) "Open"))
  (assert (= (. opened.actions 2 :name) "Copy key"))
  (assert (= (. opened.actions 3 :name) "Expand"))
  (assert (= (. opened.actions 4 :name) "cube"))
  (assert (= (. opened.actions 5 :name) "Remove from Map"))
  (assert (= (. opened.actions 6 :type) :separator)
          "Node menu should separate graph actions from node-specific actions")
  (assert (= (. opened.actions 7 :name) "Custom Action"))
  ((. opened.actions 2 :fn) nil {})
  (assert (= copied "menu-node")
          "Copy key action should copy the selected graph node key")
  ((. opened.actions 4 :fn) nil {})
  (assert (= cube-invoked 1)
          "Cube action should create one scene graph-node cube")
  ((. opened.actions 7 :fn) nil {})
  (assert (= custom-invoked 1)
          "Custom node action should be callable from the context menu after separator")
  ((. opened.actions 5 :fn) nil {})
  (assert (not (map:lookup "menu-node"))
          "Remove from Map action should remove the node from the map")
  ```

- [ ] **Step 4: Run focused graph menu tests and verify expected failure**

  If `./build/space` is missing or stale, first run:

  ```bash
  make build
  ```

  Use timeout `14400000`.

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="GraphView expanded card header buttons work" ./build/space -m tests.test-graph-view:main
  ```

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="GraphView node point right-click opens node actions" ./build/space -m tests.test-graph-view:main
  ```

  Expected: FAIL before implementation because `Copy key` and the separator are not present and `Remove from Map` is currently after node-specific actions.

- [ ] **Step 5: Reorder and extend `node-menu-actions` in `assets/lua/graph/view/init.fnl`**

  In `node-menu-actions`, insert `Copy key` after `Open`, move `Remove from Map` before node-specific actions, insert `{:type :separator}` immediately after `Remove from Map`, and leave node-specific validation unchanged.

  The action construction must have this shape:

  ```fennel
  (table.insert actions
                {:name "Open"
                 :icon "open_in_new"
                 :fn (fn [_button event]
                       (when focus-manager
                         (focus-manager:arm-auto-focus {:event event}))
                       (local (ok err) (pcall (fn [] (views:open node))))
                       (when focus-manager
                         (focus-manager:clear-auto-focus))
                       (when (not ok)
                         (error err)))})
  (table.insert actions
                {:name "Copy key"
                 :icon "content_copy"
                 :fn (fn [_button _event]
                       (gl.clipboard-set (tostring node.key)))})
  (table.insert actions
                {:name (if (. expanded-nodes node) "Collapse" "Expand")
                 :icon (if (. expanded-nodes node) "close_fullscreen" "open_in_full")
                 :fn (fn [_button _event]
                       (toggle-node-presentation node))})
  (table.insert actions
                {:name "cube"
                 :fn (fn [_button _event]
                       (local scene app.scene)
                       (when (and scene scene.add-graph-node-cube)
                         (scene:add-graph-node-cube {:node node})))})
  (table.insert actions
                {:name "Remove from Map"
                 :icon "close"
                 :fn (fn [_button _event]
                       (when (and graph-map graph-map.remove-nodes)
                         (graph-map:remove-nodes [node])))})
  (table.insert actions {:type :separator})
  (each [_ action (ipairs (or configured-actions []))]
    (when (and action action.name action.fn)
      (table.insert actions action)))
  ```

- [ ] **Step 6: Update graph browsing docs/dev page**

  In `docs/dev/features/graph-browsing.md`, change frontmatter:

  ```markdown
  updated: 2026-09-15
  ```

  Add this bullet under `## Design`, after `- Keep interaction model consistent with rest of space UI`:

  ```markdown
  - Order graph node context menus with graph-view actions first, including `Copy key`, then a first-class separator, then adapter-provided `node.actions`; graph-map actions such as open, expand/collapse, cube presentation, and removal stay owned by `GraphView`.
  ```

- [ ] **Step 7: Run focused validation for Task 2 in required order**

  Compile check first:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/view/init.fnl --file assets/lua/tests/test-graph-view.fnl
  ```

  Constraints second:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets make constraints
  ```

  Focused graph tests third:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="GraphView expanded card header buttons work" ./build/space -m tests.test-graph-view:main
  ```

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" TEST_FILTER="GraphView node point right-click opens node actions" ./build/space -m tests.test-graph-view:main
  ```

  Expected: PASS.

- [ ] **Step 8: Run complete relevant local suites**

  Run the generic menu suite:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-menu:main
  ```

  Run the graph view suite:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  ```

  Expected: PASS.

- [ ] **Step 9: Run final diff hygiene check**

  ```bash
  git diff --check
  ```

  Expected: PASS with no whitespace errors.

- [ ] **Step 10: Commit Task 2**

  ```bash
  git add assets/lua/graph/view/init.fnl assets/lua/tests/test-graph-view.fnl docs/dev/features/graph-browsing.md
  git commit -m "feat(graph): separate graph node menu actions"
  ```

- [ ] **Step 11: Final integration statement**

  Confirm the branch has:
  - Task 1 commit: `feat(ui): add menu separators`
  - Task 2 commit: `feat(graph): separate graph node menu actions`
  - Passing touched-file Fennel compile checks
  - Passing constraints
  - Passing `tests.test-menu:main`
  - Passing `tests.test-graph-view:main`

  PR CI is the full integration gate.
