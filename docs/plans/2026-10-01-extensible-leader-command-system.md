# Extensible Leader Command System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable nested leader command/keymap layer and use it to add selection-based graph preview expand/collapse/toggle commands under `SPC g p ...`.

**Architecture:** Add a small command subsystem that composes contextual command providers into a keymap trie, resolves leader prefixes, executes available commands, and derives command hints from the same data. Graph activity will contribute graph commands through a reusable graph command provider factory, while GraphView owns the selected-node preview presentation operations.

**Tech Stack:** Space Fennel, modal state routes, command hints HUD, activity runtime hooks, GraphView presentation lifecycle, focused Fennel tests.

## Global Constraints

- Support nested Spacemacs-style leader sequences such as `SPC g p e`.
- Keep command availability contextual: graph commands are available only when a graph command provider is active, and graph preview commands are available only when selected graph nodes exist.
- Preview commands operate on selected graph nodes only. They must not fall back to focused, hovered, or child-widget focus targets.
- Commands should be reusable outside graph activity. If another context embeds a graph view later, that context should be able to contribute the same graph command provider with a different graph-view resolver.
- Key bindings should be remappable by changing declarative keymap data, not by rewriting command execution functions.
- Command hints should be derived from the active command/keymap data so hints and actual bindings do not drift.
- Do not introduce a mandatory generic “target scope” abstraction for all commands. Use namespace conventions and command-local availability/resolution logic instead.
- Preserve existing leader behavior: `SPC q`, `SPC c`, and `SPC p` continue to work.
- Preserve existing normal-mode behavior: `Enter`, `Delete`, F4, and activity input dispatch remain separate from leader command dispatch.
- Use project Fennel idioms: `local` instead of `let`, multi-branch `if`, factory functions instead of `.new` constructors.
- Validate Fennel through `tools.fennel-check`, constraints, and focused Space tests; do not use system Fennel or system Lua as validation oracles.

---

## File Structure

- Create `assets/lua/commands/keymap.fnl`: pure key sequence/keymap trie logic. It does not know about app state, activities, graph views, or command execution.
- Create `assets/lua/commands/core.fnl`: command provider composition, command availability/execution, and command-hint section generation.
- Create `assets/lua/commands/providers/core-leader.fnl`: provider for existing global leader commands (`q`, `c`, `p`).
- Create `assets/lua/graph/commands.fnl`: reusable graph command provider factory. It accepts a graph-view resolver and contributes `SPC g p e/c/t` bindings.
- Modify `assets/lua/leader-state.fnl`: replace hard-coded one-key command dispatch with command subsystem sequence resolution while preserving pointer/focus route behavior.
- Modify `assets/lua/activities.fnl`: add an activity hook for leader command providers so activity contexts can contribute bindings cleanly.
- Modify `assets/lua/graph-activity-unit.fnl`: install graph command provider with the active graph-view resolver.
- Modify `assets/lua/graph/view/init.fnl`: expose selected-node preview presentation methods.
- Create `assets/lua/tests/test-commands.fnl`: unit tests for keymap/core command subsystem behavior.
- Modify `assets/lua/tests/test-states.fnl`: leader state tests for existing commands, nested prefixes, and graph provider dispatch.
- Modify `assets/lua/tests/test-graph-view.fnl`: direct GraphView selected preview method tests.
- Modify `assets/lua/tests/test-graph-activity-slots.fnl`: verify graph activity contributes graph leader providers.
- Modify `assets/lua/tests/fast.fnl`: include `tests.test-commands` in the fast suite.
- Add `docs/dev/features/leader-command-system.md`: document provider/keymap conventions and graph namespace reservations.

### Task 1: Command Keymap Core

**Files:**
- Create: `assets/lua/commands/keymap.fnl`
- Create: `assets/lua/commands/core.fnl`
- Create: `assets/lua/commands/providers/core-leader.fnl`
- Create: `assets/lua/tests/test-commands.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Produces: `Keymap.key-token(payload-or-key) -> string|nil`
- Produces: `Keymap.build(bindings) -> tree`
- Produces: `Keymap.resolve(tree, sequence) -> {:kind :prefix|:command|:missing, ...}`
- Produces: `Commands.compose(providers, command-ctx) -> {:commands table, :bindings list, :tree tree}`
- Produces: `Commands.run(composed, command-id, command-ctx) -> true|false`
- Produces: `Commands.hint-section(composed, prefix, command-ctx, opts) -> section|nil`
- Produces: `CoreLeader.provider(opts) -> provider`
- Consumes: existing `command-hints.entry`, `command-hints.section`, `command-hints.key-label`.

- [ ] **Step 1: Write failing command keymap tests**

  Create `assets/lua/tests/test-commands.fnl` with tests in this shape:

  ```fennel
  (local Keymap (require :commands/keymap))
  (local Commands (require :commands/core))

  (local tests [])

  (fn add-test [name f]
    (table.insert tests {:name name :fn f}))

  (add-test "Keymap resolves prefix command and missing sequences"
    (fn []
      (local tree (Keymap.build [{:keys ["g" "p" "e"]
                                  :command "graph.preview.expand-selected"
                                  :label "expand-preview"
                                  :priority 10}
                                 {:keys ["q"]
                                  :command "core.quit"
                                  :label "quit"
                                  :priority 20}]))
      (local g (Keymap.resolve tree ["g"]))
      (assert (= g.kind :prefix) "g should resolve as a prefix")
      (local gpe (Keymap.resolve tree ["g" "p" "e"]))
      (assert (= gpe.kind :command) "g p e should resolve to command")
      (assert (= gpe.command-id "graph.preview.expand-selected"))
      (local missing (Keymap.resolve tree ["x"]))
      (assert (= missing.kind :missing) "unknown sequence should be missing")))

  (add-test "Commands execute only available commands"
    (fn []
      (var ran 0)
      (local provider {:commands {"demo.run" {:id "demo.run"
                                               :label "run-demo"
                                               :available? (fn [ctx]
                                                             (= ctx.allowed? true))
                                               :run (fn [_ctx]
                                                      (set ran (+ ran 1))
                                                      true)}}
                       :bindings [{:keys ["d"]
                                   :command "demo.run"
                                   :label "run-demo"
                                   :priority 10}]})
      (local composed (Commands.compose [provider] {:allowed? false}))
      (assert (not (Commands.run composed "demo.run" {:allowed? false}))
              "Unavailable command should not run")
      (assert (= ran 0) "Unavailable command should not mutate")
      (assert (Commands.run composed "demo.run" {:allowed? true})
              "Available command should run")
      (assert (= ran 1) "Available command should mutate once")))

  (add-test "Command hints derive from availability and prefix"
    (fn []
      (local provider {:commands {"demo.a" {:id "demo.a"
                                             :label "alpha"
                                             :run (fn [_ctx] true)}
                                 "demo.b" {:id "demo.b"
                                             :label "beta"
                                             :available? (fn [_ctx] false)
                                             :run (fn [_ctx] true)}}
                       :bindings [{:keys ["g" "a"] :command "demo.a" :label "alpha" :priority 20}
                                  {:keys ["g" "b"] :command "demo.b" :label "beta" :priority 10}]})
      (local composed (Commands.compose [provider] {}))
      (local section (Commands.hint-section composed ["g"] {} {:id :mode :title "MODE"}))
      (assert section "Prefix hint section should exist")
      (assert (= (length section.entries) 1) "Unavailable command should be hidden")
      (assert (= (. section.entries 1 :key) "a"))
      (assert (= (. section.entries 1 :label) "alpha"))))

  (local main
    (fn []
      (local runner (require :tests/runner))
      (runner.run-tests {:name "commands" :tests tests})))

  {:name "commands" :tests tests :main main}
  ```

- [ ] **Step 2: Run the new command tests and verify failure**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-commands:main
  ```

  Expected before implementation: FAIL because `commands/keymap` and `commands/core` do not exist.

- [ ] **Step 3: Implement `commands/keymap.fnl`**

  Create `assets/lua/commands/keymap.fnl` with pure functions:

  ```fennel
  (local CommandHints (require :command-hints))

  (local M {})

  (fn clone-list [items]
    (icollect [_ item (ipairs (or items []))] item))

  (fn M.key-token [payload-or-key]
    (if (= payload-or-key nil)
        nil
        (= (type payload-or-key) :table)
        (CommandHints.key-label payload-or-key.key)
        (CommandHints.key-label payload-or-key)))

  (fn ensure-child [node token]
    (set node.children (or node.children {}))
    (when (not (. node.children token))
      (set (. node.children token) {:token token :children {}}))
    (. node.children token))

  (fn M.build [bindings]
    (local root {:children {}})
    (each [_ binding (ipairs (or bindings []))]
      (local keys (assert binding.keys "Command key binding requires :keys"))
      (assert binding.command "Command key binding requires :command")
      (var node root)
      (each [_ key (ipairs keys)]
        (set node (ensure-child node key)))
      (set node.command-id binding.command)
      (set node.binding binding))
    root)

  (fn M.resolve [tree sequence]
    (var node tree)
    (var missing false)
    (each [_ token (ipairs (or sequence []))]
      (if (and node node.children (. node.children token))
          (set node (. node.children token))
          (set missing true)))
    (if missing
        {:kind :missing}
        (and node node.command-id)
        {:kind :command :command-id node.command-id :binding node.binding :node node}
        (and node node.children)
        {:kind :prefix :node node}
        {:kind :missing}))

  (fn M.children [tree sequence]
    (local resolved (M.resolve tree sequence))
    (if (= resolved.kind :prefix)
        (do
          (local items [])
          (each [token child (pairs (or resolved.node.children {}))]
            (table.insert items {:token token :node child :binding child.binding :command-id child.command-id}))
          (table.sort items (fn [a b]
                              (< (or (and a.binding a.binding.priority) 50)
                                 (or (and b.binding b.binding.priority) 50))))
          items)
        []))

  (fn M.binding-key-label [binding prefix]
    (local keys (or binding.keys []))
    (local index (+ (length (or prefix [])) 1))
    (or (. keys index) ""))

  {:key-token M.key-token
   :build M.build
   :resolve M.resolve
   :children M.children
   :binding-key-label M.binding-key-label}
  ```

- [ ] **Step 4: Implement `commands/core.fnl`**

  Create `assets/lua/commands/core.fnl`:

  ```fennel
  (local Keymap (require :commands/keymap))
  (local {: entry : section} (require :command-hints))

  (local M {})

  (fn command-available? [command ctx]
    (if (not command)
        false
        command.available?
        (not (= (command.available? ctx) false))
        true))

  (fn M.compose [providers ctx]
    (local commands {})
    (local bindings [])
    (each [_ provider (ipairs (or providers []))]
      (local resolved (if (= (type provider) :function) (provider ctx) provider))
      (when resolved
        (each [id command (pairs (or resolved.commands {}))]
          (set (. commands id) command))
        (each [_ binding (ipairs (or resolved.bindings []))]
          (table.insert bindings binding))))
    {:commands commands
     :bindings bindings
     :tree (Keymap.build bindings)})

  (fn M.available? [composed command-id ctx]
    (command-available? (. composed.commands command-id) ctx))

  (fn M.run [composed command-id ctx]
    (local command (. composed.commands command-id))
    (if (and command (command-available? command ctx))
        (command.run ctx)
        false))

  (fn command-label [composed item]
    (local command-id (or item.command-id (and item.binding item.binding.command)))
    (local command (and command-id (. composed.commands command-id)))
    (or (and item.binding item.binding.label)
        (and command command.label)
        command-id
        item.token))

  (fn child-visible? [composed item ctx]
    (if item.command-id
        (M.available? composed item.command-id ctx)
        true))

  (fn M.hint-section [composed prefix ctx opts]
    (local options (or opts {}))
    (local entries [])
    (each [_ item (ipairs (Keymap.children composed.tree (or prefix [])))]
      (when (child-visible? composed item ctx)
        (table.insert entries
                      (entry item.token
                             (command-label composed item)
                             {:priority (or (and item.binding item.binding.priority) 50)
                              :id (or item.command-id item.token)}))))
    (when (> (length entries) 0)
      (section (or options.id :mode)
               (or options.title "MODE")
               entries)))

  {:compose M.compose
   :available? M.available?
   :run M.run
   :hint-section M.hint-section}
  ```

- [ ] **Step 5: Implement core leader provider**

  Create `assets/lua/commands/providers/core-leader.fnl`:

  ```fennel
  (local LauncherLaunchable (require :launchables/launcher))

  (fn open-launcher [ctx]
    (local hud ((. ctx :hud)))
    (assert hud "LeaderState launcher requires a HUD host")
    (LauncherLaunchable.open-panel {:hud hud})
    true)

  (fn provider []
    {:commands {"core.quit" {:id "core.quit"
                              :label "quit-mode"
                              :run (fn [ctx]
                                     ((. ctx :set-state) :quit)
                                     true)}
                "core.camera" {:id "core.camera"
                                :label "camera-mode"
                                :run (fn [ctx]
                                       ((. ctx :set-state) :camera)
                                       true)}
                "core.launcher" {:id "core.launcher"
                                  :label "launcher"
                                  :run open-launcher}}
     :bindings [{:keys ["q"] :command "core.quit" :label "quit-mode" :priority 20}
                {:keys ["c"] :command "core.camera" :label "camera-mode" :priority 30}
                {:keys ["p"] :command "core.launcher" :label "launcher" :priority 40}]})

  {:provider provider}
  ```

- [ ] **Step 6: Add command tests to fast suite**

  Insert `:tests.test-commands` near `:tests.test-states` in `assets/lua/tests/fast.fnl` so the command subsystem is part of the fast suite.

- [ ] **Step 7: Validate Task 1**

  Run:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/commands/keymap.fnl --file assets/lua/commands/core.fnl --file assets/lua/commands/providers/core-leader.fnl --file assets/lua/tests/test-commands.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-commands:main
  ```

  Expected: all commands pass. If `./build/space` is missing or stale, run `make build` with timeout `14400000` first.

- [ ] **Step 8: Commit Task 1**

  ```bash
  git add assets/lua/commands/keymap.fnl assets/lua/commands/core.fnl assets/lua/commands/providers/core-leader.fnl assets/lua/tests/test-commands.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(lua): add leader command keymap core"
  ```

### Task 2: Leader State Provider Dispatch

**Files:**
- Modify: `assets/lua/leader-state.fnl`
- Modify: `assets/lua/activities.fnl`
- Modify: `assets/lua/tests/test-states.fnl`

**Interfaces:**
- Consumes: `Commands.compose`, `Commands.run`, `Commands.hint-section`, `Keymap.key-token`, `Keymap.resolve`, `CoreLeader.provider` from Task 1.
- Produces: activity hook `leader-command-providers` stored at `app.activity-leader-command-providers`.
- Produces: leader state sequence behavior for nested prefixes.

- [ ] **Step 1: Add failing leader state tests**

  In `assets/lua/tests/test-states.fnl`, add tests near existing leader tests:

  ```fennel
  (fn leader-state-supports-nested-activity-provider-command []
    (with-state-recorder
      (fn [transitions install-state]
        (var ran 0)
        (set app.activity-leader-command-providers
             [{:commands {"demo.nested" {:id "demo.nested"
                                          :label "nested-demo"
                                          :run (fn [_ctx]
                                                 (set ran (+ ran 1))
                                                 true)}}
               :bindings [{:keys ["g" "p" "e"]
                           :command "demo.nested"
                           :label "nested-demo"
                           :priority 10}]}])
        (local state (install-state :leader (LeaderState)))
        (state.on-key-down {:key KEY_G})
        (assert (= ran 0) "Prefix should not run command")
        (assert (= (# transitions) 0) "Prefix should remain in leader state")
        (state.on-key-down {:key KEY_P})
        (assert (= ran 0) "Second prefix should not run command")
        (state.on-key-down {:key KEY_E})
        (assert (= ran 1) "Nested command should run after full sequence")
        (assert (= (. transitions (# transitions)) :normal)
                "Completed leader command should return to normal")
        (set app.activity-leader-command-providers nil))))

  (fn leader-state-hints-show-active-prefix-commands []
    (set app.activity-leader-command-providers
         [{:commands {"demo.nested" {:id "demo.nested"
                                      :label "nested-demo"
                                      :run (fn [_ctx] true)}}
           :bindings [{:keys ["g" "p" "e"]
                       :command "demo.nested"
                       :label "nested-demo"
                       :priority 10}]}])
    (local state (LeaderState))
    (local root-section (. (state.command_hints_provider state {}) 1))
    (assert root-section "Leader root hints should exist")
    (var found-g false)
    (each [_ item (ipairs root-section.entries)]
      (when (= item.key "g") (set found-g true)))
    (assert found-g "Leader root hints should include graph prefix")
    (state.on-key-down {:key KEY_G})
    (local gp-section (. (state.command_hints_provider state {}) 1))
    (assert (= (. gp-section.entries 1 :key) "p") "g prefix should expose p child")
    (state.on-key-down {:key KEY_P})
    (local gpe-section (. (state.command_hints_provider state {}) 1))
    (assert (= (. gpe-section.entries 1 :key) "e") "g p prefix should expose e command")
    (set app.activity-leader-command-providers nil))
  ```

  Register them near the existing leader tests. Define `KEY_G` and `KEY_E` alongside existing test key constants if they are missing:

  ```fennel
  (local KEY_G (string.byte "g"))
  (local KEY_E (string.byte "e"))
  ```

- [ ] **Step 2: Run state tests and verify failure**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-states:main
  ```

  Expected before implementation: FAIL because leader state does not understand nested activity providers.

- [ ] **Step 3: Add activity leader provider hook**

  In `assets/lua/activities.fnl`, add `leader-command-providers` to every activity hook table path:

  - `clear-activity-runtime-hooks!`: set `app.activity-leader-command-providers nil`.
  - `empty-activity-hooks`: include `:leader-command-providers nil`.
  - `apply-activity-hooks!`: set `app.activity-leader-command-providers hooks.leader-command-providers`.
  - `activity-context`: add `:set-leader-command-providers! (fn [_self value] (set-staged-hook! :leader-command-providers value))` next to `:set-command-hints-provider!`.

  Use the existing hook naming and setter style in `activities.fnl`; assert lists/functions if the surrounding setters assert types.

- [ ] **Step 4: Replace hard-coded leader dispatch with command composition**

  In `assets/lua/leader-state.fnl`:

  - Require `commands/core`, `commands/keymap`, and `commands/providers/core-leader`.
  - Remove the direct `open-launcher` helper and fixed `LeaderCommands` if no longer used.
  - Keep route wrappers and non-key routes unchanged.
  - Add local `sequence []` inside `LeaderState`.
  - Compose providers from `[(CoreLeader.provider)]` plus `app.activity-leader-command-providers`.
  - On `Esc`, reset sequence, mark command executed, set state `:normal`, and return true.
  - On prefix, keep leader state active and return true after marking command executed.
  - On available command, run it, reset sequence, mark command executed, set state `:normal`, and return true.
  - On unavailable or missing command, reset sequence, set state `:normal`, and return false for missing / true for unavailable no-op if a command id was resolved.
  - Add an enter lifecycle function that resets `sequence` every time leader mode is entered.

  The dispatch shape should be equivalent to:

  ```fennel
  (local providers [(CoreLeader.provider)])
  (each [_ provider (ipairs (or app.activity-leader-command-providers []))]
    (table.insert providers provider))
  (local composed (Commands.compose providers ctx))
  (local token (Keymap.key-token payload))
  (table.insert sequence token)
  (local resolved (Keymap.resolve composed.tree sequence))
  ```

- [ ] **Step 5: Generate leader hints from active keymap**

  Replace `leader-state.fnl` static `command_hints_provider` with a provider that composes the same active providers and returns:

  ```fennel
  [(Commands.hint-section composed sequence ctx {:id :mode :title "MODE"})]
  ```

  Filter nil sections before returning. Root leader hints must still include `q`, `c`, and `p` when no activity provider exists.

- [ ] **Step 6: Validate Task 2**

  Run:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/leader-state.fnl --file assets/lua/activities.fnl --file assets/lua/tests/test-states.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-states:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-commands:main
  ```

  Expected: all pass.

- [ ] **Step 7: Commit Task 2**

  ```bash
  git add assets/lua/leader-state.fnl assets/lua/activities.fnl assets/lua/tests/test-states.fnl
  git commit -m "feat(lua): route leader keys through command providers"
  ```

### Task 3: Graph Preview Leader Commands

**Files:**
- Create: `assets/lua/graph/commands.fnl`
- Modify: `assets/lua/graph/view/init.fnl`
- Modify: `assets/lua/graph-activity-unit.fnl`
- Modify: `assets/lua/tests/test-graph-view.fnl`
- Modify: `assets/lua/tests/test-graph-activity-slots.fnl`
- Modify: `assets/lua/tests/test-states.fnl`
- Create: `docs/dev/features/leader-command-system.md`

**Interfaces:**
- Consumes: Task 1/2 command provider interface.
- Produces: `GraphCommands.provider {:graph-view (fn [] graph-view|nil)} -> provider`.
- Produces: `GraphView:selected-node-count() -> integer`.
- Produces: `GraphView:expand-selected-previews() -> integer`.
- Produces: `GraphView:collapse-selected-previews() -> integer`.
- Produces: `GraphView:toggle-selected-previews() -> integer`.

- [ ] **Step 1: Add failing GraphView selected preview tests**

  In `assets/lua/tests/test-graph-view.fnl`, add a test near existing preview expansion tests:

  ```fennel
  (fn graph-selected-preview-commands-operate-only-on-selection []
      (with-temp-data-dir
          (fn [_root]
              (local ctx (make-ctx))
              (local selector (ObjectSelector {:project (fn [position _opts] position)
                                               :ctx ctx
                                               :enabled? true}))
              (local graph (make-test-graph-map))
              (local view (GraphView {:graph-map graph
                                      :ctx ctx
                                      :selector selector}))
              (local selected (Graph.GraphNode {:key "selected-preview"
                                                :preview (tracked-preview {})}))
              (local focused-only (Graph.GraphNode {:key "focused-only-preview"
                                                    :preview (tracked-preview {})}))
              (graph:add-node selected {:position (glm.vec3 0 0 0)})
              (graph:add-node focused-only {:position (glm.vec3 10 0 0)})
              ((. view.focus-nodes focused-only):request-focus)
              (assert (= (view:expand-selected-previews) 0)
                      "No selected nodes should make expand-selected a no-op")
              (assert (not (. view.points focused-only :_card-size))
                      "Focused node must not be expanded as fallback")
              (selector:set-selected [(. view.points selected)])
              (assert (= (view:expand-selected-previews) 1)
                      "Selected compact node should expand")
              (assert (. view.points selected :_card-size)
                      "Selected node should now be expanded")
              (assert (= (view:expand-selected-previews) 0)
                      "Expanding already-expanded selection should be idempotent")
              (assert (= (view:collapse-selected-previews) 1)
                      "Selected expanded node should collapse")
              (assert (not (. view.points selected :_card-size))
                      "Selected node should now be compact")
              (assert (= (view:toggle-selected-previews) 1)
                      "Toggle should expand compact selected node")
              (assert (. view.points selected :_card-size)
                      "Toggle should leave selected node expanded")
              (assert (= (view:toggle-selected-previews) 1)
                      "Toggle should collapse expanded selected node")
              (assert (not (. view.points selected :_card-size))
                      "Toggle should leave selected node compact")
              (view:drop)
              (graph:drop)
              (selector:drop))))
  ```

  Register it near the existing preview tests.

- [ ] **Step 2: Add failing graph leader dispatch test**

  In `assets/lua/tests/test-states.fnl`, add a leader test using a graph provider with a stub graph view:

  ```fennel
  (fn leader-state-graph-preview-command-uses-selection-provider []
    (with-state-recorder
      (fn [transitions install-state]
        (local GraphCommands (require :graph/commands))
        (var expand-calls 0)
        (local graph-view {:selected-node-count (fn [_self] 1)
                           :expand-selected-previews (fn [_self]
                                                       (set expand-calls (+ expand-calls 1))
                                                       1)})
        (set app.activity-leader-command-providers
             [(GraphCommands.provider {:graph-view (fn [] graph-view)})])
        (local state (install-state :leader (LeaderState)))
        (state.on-key-down {:key KEY_G})
        (state.on-key-down {:key KEY_P})
        (state.on-key-down {:key KEY_E})
        (assert (= expand-calls 1) "SPC g p e should expand selected previews")
        (assert (= (. transitions (# transitions)) :normal)
                "Graph preview command should return to normal")
        (set app.activity-leader-command-providers nil))))
  ```

  Also add a no-selection version where `selected-node-count` returns `0`; assert the command does not call `expand-selected-previews`.

- [ ] **Step 3: Run graph tests and verify failure**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-states:main
  ```

  Expected before implementation: FAIL because selected preview methods and graph command provider do not exist.

- [ ] **Step 4: Add GraphView selected preview methods**

  In `assets/lua/graph/view/init.fnl`, add internal helpers near `toggle-node-presentation` / `expand-node-presentation`:

  - `expand-node-presentation` should remain idempotent and return true only when it changed a compact node to expanded.
  - Add `collapse-node-presentation node -> true|nil`, which collapses only if the node is expanded.
  - Add `toggle-node-presentation` reuse for toggle command.

  Public methods near other `view.*` methods:

  ```fennel
  (set view.selected-node-count
       (fn [_self]
         (assert-not-dropped "selected-node-count")
         (length (or selected-nodes []))))

  (set view.expand-selected-previews
       (fn [_self]
         (assert-not-dropped "expand-selected-previews")
         (var changed 0)
         (each [_ node (ipairs (or selected-nodes []))]
           (when (expand-node-presentation node)
             (set changed (+ changed 1))))
         changed))

  (set view.collapse-selected-previews
       (fn [_self]
         (assert-not-dropped "collapse-selected-previews")
         (var changed 0)
         (each [_ node (ipairs (or selected-nodes []))]
           (when (collapse-node-presentation node)
             (set changed (+ changed 1))))
         changed))

  (set view.toggle-selected-previews
       (fn [_self]
         (assert-not-dropped "toggle-selected-previews")
         (var changed 0)
         (each [_ node (ipairs (or selected-nodes []))]
           (when (and node (. registry.points node))
             (toggle-node-presentation node)
             (set changed (+ changed 1))))
         changed))
  ```

  Do not use focused or hovered node fallback in these methods.

- [ ] **Step 5: Implement graph command provider**

  Create `assets/lua/graph/commands.fnl`:

  ```fennel
  (local M {})

  (fn resolve-graph-view [opts]
    (local resolver (assert opts.graph-view "GraphCommands.provider requires graph-view resolver"))
    (resolver))

  (fn has-selection? [opts]
    (local graph-view (resolve-graph-view opts))
    (and graph-view graph-view.selected-node-count (> (graph-view:selected-node-count) 0)))

  (fn run-selected [opts method-name]
    (local graph-view (resolve-graph-view opts))
    (if (and graph-view (. graph-view method-name) (has-selection? opts))
        (> ((. graph-view method-name) graph-view) 0)
        false))

  (fn M.provider [opts]
    (local options (or opts {}))
    {:commands {"graph.preview.expand-selected"
                {:id "graph.preview.expand-selected"
                 :label "expand-preview"
                 :available? (fn [_ctx] (has-selection? options))
                 :run (fn [_ctx] (run-selected options :expand-selected-previews))}
                "graph.preview.collapse-selected"
                {:id "graph.preview.collapse-selected"
                 :label "collapse-preview"
                 :available? (fn [_ctx] (has-selection? options))
                 :run (fn [_ctx] (run-selected options :collapse-selected-previews))}
                "graph.preview.toggle-selected"
                {:id "graph.preview.toggle-selected"
                 :label "toggle-preview"
                 :available? (fn [_ctx] (has-selection? options))
                 :run (fn [_ctx] (run-selected options :toggle-selected-previews))}}
     :bindings [{:keys ["g" "p" "e"] :command "graph.preview.expand-selected" :label "expand-preview" :priority 10}
                {:keys ["g" "p" "c"] :command "graph.preview.collapse-selected" :label "collapse-preview" :priority 20}
                {:keys ["g" "p" "t"] :command "graph.preview.toggle-selected" :label "toggle-preview" :priority 30}]})

  {:provider M.provider}
  ```

- [ ] **Step 6: Install graph provider from graph activity**

  In `assets/lua/graph-activity-unit.fnl`, require `graph/commands` and call the activity context setter added in Task 2:

  ```fennel
  (ctx:set-leader-command-providers!
    [(GraphCommands.provider {:graph-view (fn [] app.graph-view)})])
  ```

  Add this next to the existing graph activity hook setup where command hints and focused activation are installed.

- [ ] **Step 7: Verify graph activity hook test**

  In `assets/lua/tests/test-graph-activity-slots.fnl`, add or update a test that activates graph activity and asserts `app.activity-leader-command-providers` is a non-empty list while graph activity is active, then clears after deactivation/activity hook cleanup.

- [ ] **Step 8: Document leader command conventions**

  Create `docs/dev/features/leader-command-system.md`:

  ```markdown
  # Leader Command System

  Space leader commands are contributed by contextual command providers. A provider supplies command descriptors and declarative key bindings. Leader state composes active providers, resolves nested `SPC ...` sequences, executes available commands, and derives command hints from the same data.

  Providers should be reusable. Graph commands, for example, are created with a graph-view resolver so graph activity and future embedded graph views can install the same commands in their own context.

  Graph namespace conventions:

  - `SPC g p ...` graph preview / presentation commands.
  - `SPC g s ...` graph selection editing.
  - `SPC g n ...` focused graph node actions.
  - `SPC g v ...` graph view, camera, and layout.
  - `SPC g m ...` graph map and topology.

  These namespaces are conventions for predictable command placement. They are not a generic target-scope type system. Each command owns its own availability and target resolution rules.
  ```

- [ ] **Step 9: Validate Task 3**

  Run:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/commands.fnl --file assets/lua/graph/view/init.fnl --file assets/lua/graph-activity-unit.fnl --file assets/lua/tests/test-graph-view.fnl --file assets/lua/tests/test-graph-activity-slots.fnl --file assets/lua/tests/test-states.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-states:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
  ```

  Expected: all pass.

- [ ] **Step 10: Commit Task 3**

  ```bash
  git add assets/lua/graph/commands.fnl assets/lua/graph/view/init.fnl assets/lua/graph-activity-unit.fnl assets/lua/tests/test-graph-view.fnl assets/lua/tests/test-graph-activity-slots.fnl assets/lua/tests/test-states.fnl docs/dev/features/leader-command-system.md
  git commit -m "feat(ui): add graph preview leader commands"
  ```

### Task 4: Final Focused Validation and Baseline Hygiene

**Files:**
- Modify: `assets/lua/constraints/baseline-data.fnl` only if constraints report precise stale/worsened accepted violations caused by the reviewed changes.
- No other files should change unless validation reveals a reviewed fix is required.

**Interfaces:**
- Consumes: all command and graph interfaces from Tasks 1-3.
- Produces: green focused validation from a clean tree.

- [ ] **Step 1: Run combined touched-file compile check**

  Run:

  ```bash
  SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/commands/keymap.fnl --file assets/lua/commands/core.fnl --file assets/lua/commands/providers/core-leader.fnl --file assets/lua/graph/commands.fnl --file assets/lua/leader-state.fnl --file assets/lua/activities.fnl --file assets/lua/graph/view/init.fnl --file assets/lua/graph-activity-unit.fnl --file assets/lua/tests/test-commands.fnl --file assets/lua/tests/test-states.fnl --file assets/lua/tests/test-graph-view.fnl --file assets/lua/tests/test-graph-activity-slots.fnl --file assets/lua/tests/fast.fnl
  ```

  Expected: PASS.

- [ ] **Step 2: Run constraints and handle only precise baseline drift**

  Run:

  ```bash
  make constraints
  ```

  Expected: PASS. If constraints report stale/worsened baseline entries in touched, already-baselined files, update `assets/lua/constraints/baseline-data.fnl` with precise reviewed entries and reasons referencing this leader command task. Do not change constraint rules or add broad allowlists.

- [ ] **Step 3: Run focused tests**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-commands:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-states:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-activity-slots:main
  ```

  Expected: all pass.

- [ ] **Step 4: Commit baseline-only validation fix if needed**

  If Step 2 required a baseline-data update, commit it separately:

  ```bash
  git add assets/lua/constraints/baseline-data.fnl
  git commit -m "fix(assets): refresh leader command constraints baseline"
  ```

  If Step 2 passed with no changes, do not create an empty commit.
