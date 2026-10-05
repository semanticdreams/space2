# Focus Start Node Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `SPC g v s` to ensure the active graph map contains `start`, then select, focus, and center that node in the active graph view.

**Architecture:** Implement this as graph command-provider orchestration in `assets/lua/graph/commands.fnl`. Reuse `GraphMap:add-start-node!` for map membership and `GraphView:reveal-node` for view selection/focus/camera behavior, without adding new graph map or graph view APIs.

**Tech Stack:** Space Fennel modules, graph command provider, leader state routing, project-native `tools.fennel-check`, constraints, and focused Fennel runtime tests.

## Global Constraints

- Command id: `graph.view.focus-start`.
- Binding: `SPC g v s`.
- Label: `start`.
- Behavior: require an active graph view and active graph map, call `GraphMap:add-start-node!`, then call `GraphView:reveal-node` with the returned node and explicit `{ :select? true :focus? true :center? true }` options.
- Availability is true only when an active graph view, active graph map, `GraphMap:add-start-node!`, and `GraphView:reveal-node` are available.
- The command does not require an existing focused node.
- Missing graph map/view dependencies or required methods fail loudly with assertions.
- The command must not silently no-op if the start loader fails or if the returned node cannot be revealed.
- No graph map persistence or schema changes.
- No automatic start-node seeding for every new map.
- No alternate bindings or compatibility aliases.
- No changes to the existing Add Start button behavior.
- For Fennel validation, run compile check first, constraints second, then focused tests.

---

### Task 1: Focus Start Graph Command

**Files:**
- Modify: `assets/lua/graph/commands.fnl`
- Modify: `assets/lua/tests/test-commands.fnl`
- Modify: `assets/lua/tests/test-states.fnl`
- Modify: `docs/dev/features/leader-command-system.md`
- Modify: `docs/dev/graph-maps.md`

**Interfaces:**
- Consumes: `graph-map:add-start-node!() -> node`
- Consumes: `graph-view:reveal-node(node-or-key, opts) -> node-or-truthy`
- Produces: command descriptor `graph.view.focus-start`
- Produces: binding descriptor `{:keys ["g" "v" "s"] :command "graph.view.focus-start" :label "start"}`

- [ ] **Step 1: Add failing command-provider test coverage**

  In `assets/lua/tests/test-commands.fnl`, extend `make-expanded-graph-view-stub` at the existing expanded graph command helper so it can record direct reveal calls:

  ```fennel
  (local calls {:open 0 :menu 0 :toggle 0 :copy 0 :remove 0 :slot [] :center 0 :layout 0
                :focus-start 0 :last-reveal-node nil :last-reveal-opts nil})
  ```

  Add this method to the returned graph view stub table:

  ```fennel
  :reveal-node (fn [_self node opts]
                 (set calls.focus-start (+ calls.focus-start 1))
                 (set calls.last-reveal-node node)
                 (set calls.last-reveal-opts opts)
                 true)
  ```

  Update `make-expanded-map-stub` so `add-start-node!` returns the ensured node:

  ```fennel
  :add-start-node! (fn [_self]
                     (set calls.add-start (+ calls.add-start 1))
                     (or options.start-node {:key "start"}))
  ```

  Add a new provider test near `graph-provider-view-commands-route-to-graph-view`:

  ```fennel
  (fn graph-provider-focus-start-ensures-start-and-reveals []
    (local start-node {:key "start"})
    (local view (make-expanded-graph-view-stub))
    (local graph-map (make-expanded-map-stub {:start-node start-node
                                              :focused-node-key "stale-focus"
                                              :clearable? true}))
    (local manager (make-expanded-manager-stub))
    (local composed (expanded-graph-composed view graph-map manager))
    (assert (Commands.available? composed "graph.view.focus-start" {})
            "focus-start should be available with graph view reveal-node and map add-start-node!")
    (assert (Commands.run composed "graph.view.focus-start" {})
            "focus-start should run")
    (assert (= graph-map.calls.add-start 1)
            "focus-start should ensure start through active graph map")
    (assert (= view.calls.focus-start 1)
            "focus-start should reveal exactly once")
    (assert (= view.calls.last-reveal-node start-node)
            "focus-start should reveal the node returned by add-start-node!")
    (local reveal-opts view.calls.last-reveal-opts)
    (assert (= (. reveal-opts :select?) true)
            "focus-start should explicitly select the start node")
    (assert (= (. reveal-opts :focus?) true)
            "focus-start should explicitly focus the start node")
    (assert (= (. reveal-opts :center?) true)
            "focus-start should explicitly center the start node")
    (assert (not (Commands.available? (expanded-graph-composed nil graph-map manager)
                                      "graph.view.focus-start" {}))
            "focus-start should require active graph view")
    (assert (not (Commands.available? (expanded-graph-composed view nil manager)
                                      "graph.view.focus-start" {}))
            "focus-start should require active graph map")
    (local no-reveal-view (make-expanded-graph-view-stub))
    (set no-reveal-view.reveal-node nil)
    (assert (not (Commands.available? (expanded-graph-composed no-reveal-view graph-map manager)
                                      "graph.view.focus-start" {}))
            "focus-start should require GraphView:reveal-node")
    (local no-add-map (make-expanded-map-stub {:focused-node-key "focus"}))
    (set no-add-map.add-start-node! nil)
    (assert (not (Commands.available? (expanded-graph-composed view no-add-map manager)
                                      "graph.view.focus-start" {}))
            "focus-start should require GraphMap:add-start-node!"))
  ```

  Add a hint test near `graph-provider-prefix-hints-include-expanded-namespaces`:

  ```fennel
  (fn graph-provider-view-prefix-hints-include-focus-start []
    (local view (make-expanded-graph-view-stub))
    (local graph-map (make-expanded-map-stub {:focused-node-key "focus" :clearable? true}))
    (local manager (make-expanded-manager-stub))
    (local composed (expanded-graph-composed view graph-map manager))
    (local view-section (Commands.hint-section composed ["g" "v"] {} {:id :mode :title "MODE"}))
    (assert view-section "Graph provider view hints should exist")
    (assert-hint view-section "c" "center")
    (assert-hint view-section "l" "layout")
    (assert-hint view-section "s" "start"))
  ```

  Register both tests at the bottom of `assets/lua/tests/test-commands.fnl` with the existing `add-test` calls:

  ```fennel
  (add-test "Graph provider focus-start ensures start and reveals"
            graph-provider-focus-start-ensures-start-and-reveals)
  (add-test "Graph provider view prefix hints include focus-start"
            graph-provider-view-prefix-hints-include-focus-start)
  ```

- [ ] **Step 2: Add failing leader routing coverage**

  In `assets/lua/tests/test-states.fnl`, add this test near the existing `leader-state-graph-view-command-routes-to-provider` test:

  ```fennel
  (fn leader-state-graph-view-focus-start-routes-to-provider []
    (local GraphCommands (require :graph/commands))
    (local start-node {:key "start"})
    (local calls {:add-start 0 :reveal 0 :node nil :opts nil})
    (local graph-view {:reveal-node (fn [_self node opts]
                                      (set calls.reveal (+ calls.reveal 1))
                                      (set calls.node node)
                                      (set calls.opts opts)
                                      true)})
    (local graph-map {:add-start-node! (fn [_self]
                                         (set calls.add-start (+ calls.add-start 1))
                                         start-node)})
    (local last-transition
      (run-graph-leader-sequence (GraphCommands.provider {:graph-view (fn [] graph-view)
                                                          :graph-map (fn [] graph-map)})
                                 ["g" "v" "s"]))
    (assert (= calls.add-start 1) "SPC g v s should ensure start once")
    (assert (= calls.reveal 1) "SPC g v s should reveal once")
    (assert (= calls.node start-node) "SPC g v s should reveal returned start node")
    (assert (= (. calls.opts :select?) true) "SPC g v s should select")
    (assert (= (. calls.opts :focus?) true) "SPC g v s should focus")
    (assert (= (. calls.opts :center?) true) "SPC g v s should center")
    (assert (= last-transition :normal) "Graph focus-start command should return to normal"))
  ```

  Register it with the existing test table insertions:

  ```fennel
  (table.insert tests {:name "Leader state graph view focus-start routes to provider"
                       :fn leader-state-graph-view-focus-start-routes-to-provider})
  ```

- [ ] **Step 3: Run focused tests and confirm the new tests fail for the expected reason**

  If `./build/space` is missing or stale, run `make build` first with timeout `14400000` ms. Then run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-commands:main
  ```

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-states:main
  ```

  Expected: the new checks fail because `graph.view.focus-start` and `SPC g v s` are not registered yet.

- [ ] **Step 4: Implement command availability and execution**

  In `assets/lua/graph/commands.fnl`, add helpers near the existing view/map availability helpers:

  ```fennel
  (fn focus-start-available? [opts]
    (local graph-view (resolve-graph-view opts))
    (local graph-map (resolve-active-map opts))
    (and graph-view
         graph-map
         graph-view.reveal-node
         graph-map.add-start-node!))

  (fn run-focus-start [opts]
    (local graph-view (require-graph-view opts))
    (local graph-map (require-active-map opts))
    (assert graph-map.add-start-node!
            "GraphCommands requires active graph map add-start-node!")
    (assert graph-view.reveal-node
            "GraphCommands requires graph view reveal-node")
    (local node (graph-map:add-start-node!))
    (graph-view:reveal-node node {:select? true
                                  :focus? true
                                  :center? true}))
  ```

  Register the command in `M.provider` near the existing graph view commands:

  ```fennel
  "graph.view.focus-start"
  (make-map-command options "graph.view.focus-start" "start" focus-start-available? run-focus-start)
  ```

  Keep the existing `make-map-command` name unchanged; despite its name, it already wraps context-sensitive commands over provider options and avoids adding a new abstraction for one command.

- [ ] **Step 5: Add the `SPC g v s` binding**

  In the provider bindings list, add the start binding next to other graph view commands:

  ```fennel
  {:keys ["g" "v" "s"] :command "graph.view.focus-start" :label "start" :priority 30}
  ```

  Preserve the existing bindings for `SPC g v c`, `SPC g v l`, and all `SPC g m ...` commands.

- [ ] **Step 6: Update developer docs**

  In `docs/dev/features/leader-command-system.md`, add this row to the Graph view commands table:

  ```markdown
  | `SPC g v s` | ensure the `start` node is in the active map, then select, focus, and center it in the graph view. |
  ```

  In `docs/dev/graph-maps.md`, near the existing Add Start description, add:

  ```markdown
  `SPC g v s` is a graph view navigation command for the same canonical `start` node. It uses the active `GraphMap:add-start-node!` path first, so missing start membership is recovered the same way as the sidebar **Add Start** action, then it reveals the returned node through `GraphView:reveal-node` with select, focus, and center enabled.
  ```

- [ ] **Step 7: Run validation in the required Fennel order**

  Compile check first:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/commands.fnl --file assets/lua/tests/test-commands.fnl --file assets/lua/tests/test-states.fnl
  ```

  Constraints second:

  ```bash
  make constraints
  ```

  Focused tests third:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-commands:main
  ```

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-states:main
  ```

  Broader relevant local suite because this touches shared leader command routing:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
  ```

- [ ] **Step 8: Review and commit the implementation**

  Inspect only the planned files:

  ```bash
  git diff -- assets/lua/graph/commands.fnl assets/lua/tests/test-commands.fnl assets/lua/tests/test-states.fnl docs/dev/features/leader-command-system.md docs/dev/graph-maps.md
  git status --porcelain
  ```

  Commit after review passes:

  ```bash
  git add assets/lua/graph/commands.fnl assets/lua/tests/test-commands.fnl assets/lua/tests/test-states.fnl docs/dev/features/leader-command-system.md docs/dev/graph-maps.md
  git commit -m "feat(graph): add focus-start leader command"
  ```

  Include the validation commands and a constraint-impact line in the commit body.
