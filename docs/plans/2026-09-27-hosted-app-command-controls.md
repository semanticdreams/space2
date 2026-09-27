# Hosted App Command Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add generic visual Run buttons for hosted app commands in workspace panel HUD widgets.

**Architecture:** Create a focused `app-host.workspace-command-controls` widget that reads command metadata from the existing read-only inspector snapshot and invokes `descriptor:run-command(command-id, nil)` on button clicks. Keep `workspace-panel.fnl` responsible for mounting/session/descriptor lifecycle and swap its zero-size placeholder widget for the new visual command-controls widget. Preserve existing command runner and snapshot semantics; this slice displays latest success/error state but does not add payload schemas, permissions, async protocols, app-specific controls, or a full inspector dashboard.

**Tech Stack:** Space Fennel UI, `Button`, `Flex`/`FlexChild`, `Padding`, `WrappedText`, `StatusBadge`, workspace panel descriptors, focused Fennel widget tests, `tools.fennel-check`, `make constraints`.

## Global Constraints

- Render generic hosted app command controls in the workspace panel HUD child.
- Read command metadata from `descriptor:read-inspector-snapshot()`.
- Preserve snapshot behavior: reading metadata must not execute commands.
- Invoke commands through the existing `descriptor:run-command(command-id, nil)` surface.
- Display the latest command success/error result in the panel and keep it in inspectable widget state for focused tests and future UI integration.
- Preserve existing workspace panel descriptor/session API and mount teardown behavior.
- Follow Space Fennel UI ownership and lifecycle rules.
- No payload schemas or argument editor widgets.
- No permissions, confirmations, destructive-command policy, or auth UX.
- No async progress, cancellation, command queues, or persistent command history.
- No app-specific command rendering or Snake-specific controls.
- No full hosted inspector/dashboard framework.
- No graph/editor/launcher integration.
- No changes to `workspace-inspector-snapshot` execution semantics.
- No changes to `command-runner` result envelope semantics.
- The constructor requires `opts.descriptor` and should fail loudly when missing.
- The build closure receives a normal Space UI context. Because it uses `Button`, the context must provide `ctx.clickables` and `ctx.hoverables`; missing required context should fail loudly through existing widget behavior rather than silently falling back.
- The built widget exposes `:hosted-app-workspace-panel` with the original descriptor for compatibility.
- Structural exceptions from `run-command` propagate loudly and do not convert to result messages.
- The button passes `nil` payload because command metadata has no schema yet.
- Existing workspace panel descriptor/session APIs remain compatible.
- Widget constructors return build closures.
- Builders receive renderer/build context and instantiate children with that context.
- Widgets own explicit `Layout` objects.
- Composite widgets own and drop their direct child widgets.
- Assert on missing required context instead of silently falling back.
- Use `local` instead of `let` in Fennel.
- Use factory functions instead of constructors (`.new`).
- Use project-native Fennel validation only: touched-file `tools.fennel-check` or `make fennel-check`, then `make constraints`, then focused Fennel tests.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- For direct test runs, set `SKIP_KEYRING_TESTS=1`, `XDG_DATA_HOME=/tmp/space/tests/xdg-data`, `SPACE_DISABLE_AUDIO=1`, `SPACE_ASSETS_PATH=$(pwd)/assets`, `FENNEL_PATH=$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl`, and the same value for `FENNEL_MACRO_PATH`.

---

## File Structure

- `assets/lua/app-host/workspace-command-controls.fnl`: new focused widget module that renders command rows and Run buttons from a workspace panel descriptor.
- `assets/lua/tests/test-app-host-workspace-command-controls.fnl`: focused widget tests for metadata rendering, command execution, result messaging, loud structural errors, and drop ownership.
- `assets/lua/app-host/workspace-panel.fnl`: replace the zero-size placeholder widget builder with `WorkspaceCommandControls` while preserving session and descriptor APIs.
- `assets/lua/tests/test-hosted-app-workspace-panel.fnl`: extend existing panel tests so builder HUDs provide UI context and assert visual controls exist without executing commands during build.
- `docs/dev/features/hosted-runtime-apps.md`: document the new visual command controls and retained follow-up boundaries.

---

### Task 1: Generic Hosted Command Controls Widget

**Files:**
- Create: `assets/lua/app-host/workspace-command-controls.fnl`
- Create: `assets/lua/tests/test-app-host-workspace-command-controls.fnl`

**Interfaces:**
- Consumes: `descriptor:read-inspector-snapshot() -> {:commands command-rows}` where each command row may contain `:id`, `:title`, `:description`, and `:status`.
- Consumes: `descriptor:run-command(command-id, payload) -> {:id command-id :status :ok :value value}` or `{:id command-id :status :error :error error-string}`.
- Produces: module export `{:WorkspaceCommandControls WorkspaceCommandControls}`.
- Produces: `(WorkspaceCommandControls {:descriptor descriptor}) -> build(ctx) -> widget`.
- Produces built widget state at `widget.__command-controls` with keys `:snapshot`, `:commands`, `:buttons-by-id`, `:last-result`, `:result-message`, and `:run-command`.
- Produces built widget compatibility field `widget.hosted-app-workspace-panel` containing the original descriptor.

- [ ] **Step 1: Create focused test scaffolding**

Create `assets/lua/tests/test-app-host-workspace-command-controls.fnl` with this base content:

```fennel
(local Runner (require :tests/runner))
(local Controls (require :app-host.workspace-command-controls))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn assert-error-contains [f expected]
  (local (ok err) (pcall f))
  (assert (= ok false) "expected call to fail")
  (assert (string.find (tostring err) expected 1 true)
          (.. "expected error to contain " expected ", got " (tostring err))))

(fn make-registry []
  {:registered []
   :unregistered []
   :register (fn [self item]
               (table.insert self.registered item)
               item)
   :register-right-click (fn [self item]
                           (table.insert self.registered item)
                           item)
   :register-double-click (fn [self item]
                            (table.insert self.registered item)
                            item)
   :unregister (fn [self item]
                 (table.insert self.unregistered item)
                 item)
   :unregister-right-click (fn [self item]
                             (table.insert self.unregistered item)
                             item)
   :unregister-double-click (fn [self item]
                              (table.insert self.unregistered item)
                              item)})

(fn make-hover-registry []
  {:registered []
   :unregistered []
   :register (fn [self item]
               (table.insert self.registered item)
               item)
   :unregister (fn [self item]
                 (table.insert self.unregistered item)
                 item)})

(fn test-context []
  (local clickables (make-registry))
  (local hoverables (make-hover-registry))
  {:ctx {:clickables clickables :hoverables hoverables}
   :clickables clickables
   :hoverables hoverables})

(fn make-descriptor [opts]
  (local options (or opts {}))
  (local state {:read-count 0 :run-count 0 :calls []})
  (local commands (or options.commands
                      [{:id :restart :title "Restart" :description "Restart app" :status :metadata}
                       {:id :explode :title "Explode" :description "Return an error" :status :metadata}]))
  (local results (or options.results
                     {:restart {:id :restart :status :ok :value {:done? true}}
                      :explode {:id :explode :status :error :error "boom"}}))
  {:state state
   :descriptor {:read-inspector-snapshot (fn [_self]
                                           (set state.read-count (+ state.read-count 1))
                                           {:inspectors [] :commands commands})
                :run-command (or options.run-command
                                 (fn [_self command-id payload]
                                   (set state.run-count (+ state.run-count 1))
                                   (table.insert state.calls {:id command-id :payload payload})
                                   (. results command-id)))}})

(fn build-widget [descriptor ctx]
  (local builder (Controls.WorkspaceCommandControls {:descriptor descriptor}))
  (builder ctx))

(fn main []
  (Runner.run-tests {:name "app-host-workspace-command-controls" :tests tests}))

{:main main :tests tests}
```

- [ ] **Step 2: Add failing metadata rendering test**

Append:

```fennel
(fn test-build_reads_metadata_without_running_commands []
  (local fixture (make-descriptor))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  (assert (= fixture.state.read-count 1) "build should read exactly one snapshot")
  (assert (= fixture.state.run-count 0) "build must not run commands")
  (assert (= (# state.commands) 2))
  (assert (= (. state.commands 1 :id) :restart))
  (assert state.snapshot)
  (assert widget.hosted-app-workspace-panel)
  (assert widget.layout)
  (assert (. state.buttons-by-id :restart) "restart command should have a run button")
  (assert (. state.buttons-by-id :explode) "explode command should have a run button")
  (widget:drop))

(add-test "build reads command metadata without running commands" test-build_reads_metadata_without_running_commands)
```

Run and expect failure because the module does not exist yet:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-command-controls:main
```

- [ ] **Step 3: Add failing success and error result tests**

Append:

```fennel
(fn test-run_button_updates_success_result []
  (local fixture (make-descriptor))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  (local button (. state.buttons-by-id :restart))
  (button:on-click {:source :test})
  (assert (= fixture.state.run-count 1))
  (assert (= (. fixture.state.calls 1 :id) :restart))
  (assert (= (. fixture.state.calls 1 :payload) nil) "visual command buttons pass nil payload")
  (assert (= state.last-result.status :ok))
  (assert (string.find state.result-message "Restart" 1 true))
  (assert (string.find state.result-message "succeeded" 1 true))
  (widget:drop))

(fn test-run_button_updates_error_result []
  (local fixture (make-descriptor))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  (local button (. state.buttons-by-id :explode))
  (button:on-click {:source :test})
  (assert (= fixture.state.run-count 1))
  (assert (= state.last-result.status :error))
  (assert (string.find state.result-message "Explode" 1 true))
  (assert (string.find state.result-message "failed" 1 true))
  (assert (string.find state.result-message "boom" 1 true))
  (widget:drop))

(add-test "run button updates success result" test-run_button_updates_success_result)
(add-test "run button updates error result" test-run_button_updates_error_result)
```

- [ ] **Step 4: Add failing loud structural error test**

Append:

```fennel
(fn test-structural_run_command_errors_propagate []
  (local fixture (make-descriptor {:run-command (fn [_self _command-id _payload]
                                                  (error "structural failure"))}))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  (local button (. state.buttons-by-id :restart))
  (assert-error-contains #(button:on-click {:source :test}) "structural failure")
  (assert (= state.last-result nil) "structural errors must not become result envelopes")
  (widget:drop))

(add-test "structural run-command errors propagate" test-structural_run_command_errors_propagate)
```

- [ ] **Step 5: Add failing ownership/drop test**

Append:

```fennel
(fn test-drop_unregisters_button_handlers []
  (local fixture (make-descriptor))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (assert (> (# context.clickables.registered) 0) "buttons should register clickable handlers")
  (assert (> (# context.hoverables.registered) 0) "buttons should register hover handlers")
  (widget:drop)
  (assert (= (# context.clickables.unregistered) (# context.clickables.registered))
          "drop should unregister every clickable handler registered by buttons")
  (assert (= (# context.hoverables.unregistered) (# context.hoverables.registered))
          "drop should unregister every hover handler registered by buttons"))

(add-test "drop unregisters button handlers" test-drop_unregisters_button_handlers)
```

- [ ] **Step 6: Implement `workspace-command-controls.fnl`**

Create `assets/lua/app-host/workspace-command-controls.fnl` with these implementation requirements:

```fennel
(local Button (require :button))
(local Padding (require :padding))
(local WrappedText (require :wrapped-text))
(local StatusBadge (require :status-badge))
(local {: Flex : FlexChild} (require :flex))

(fn controls-error [message]
  (error (.. "[app-host.workspace-command-controls] " message)))

(fn label-for-command [command]
  (tostring (or command.title command.id "command")))

(fn result-message [command result]
  (local label (label-for-command command))
  (if (= result.status :ok)
      (.. label " succeeded")
      (= result.status :error)
      (.. label " failed: " (tostring result.error))
      (.. label " returned status " (tostring result.status))))
```

Then implement `WorkspaceCommandControls` so that:

- it asserts `opts` is a table and `opts.descriptor` is present;
- the build closure calls `descriptor:read-inspector-snapshot()` exactly once;
- `commands` is `(or snapshot.commands [])`;
- `state.buttons-by-id` is a table keyed by command id;
- each command row is a `Flex` with a text area, `StatusBadge {:text (tostring (or command.status :metadata)) :tone :neutral}`, and `Button {:text "Run" :on-click (fn [_button _event] (state.run-command command))}`;
- the root is a vertical `Flex`, padded by `Padding`, containing command rows and a result `WrappedText` initialized to `"No command run yet"`;
- `state.run-command` calls `descriptor:run-command command.id nil`, stores `state.last-result`, stores `state.result-message`, updates the result text widget with `result-text:set-text`, and returns the result;
- structural exceptions from `descriptor:run-command` are not caught;
- returned widget exposes `:layout`, `:drop`, `:hosted-app-workspace-panel`, and `:__command-controls`;
- `drop` drops the direct root widget exactly once.

The module must export:

```fennel
{:WorkspaceCommandControls WorkspaceCommandControls}
```

- [ ] **Step 7: Validate and commit Task 1**

Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/workspace-command-controls.fnl --file assets/lua/tests/test-app-host-workspace-command-controls.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-command-controls:main
```

Commit:

```bash
git add assets/lua/app-host/workspace-command-controls.fnl assets/lua/tests/test-app-host-workspace-command-controls.fnl
git commit -m "feat(apps): add hosted command controls widget"
```

---

### Task 2: Workspace Panel Visual Integration

**Files:**
- Modify: `assets/lua/app-host/workspace-panel.fnl`
- Modify: `assets/lua/tests/test-hosted-app-workspace-panel.fnl`

**Interfaces:**
- Consumes: `WorkspaceCommandControls.WorkspaceCommandControls {:descriptor descriptor}` from Task 1.
- Produces: existing `WorkspacePanel.open(opts)` behavior with a visual HUD child whose built widget exposes `:hosted-app-workspace-panel` and `:__command-controls`.

- [ ] **Step 1: Update builder HUD test context**

In `assets/lua/tests/test-hosted-app-workspace-panel.fnl`, add helper registries near the existing `registry` helper:

```fennel
(fn make-click-registry []
  {:registered []
   :unregistered []
   :register (fn [self item]
               (table.insert self.registered item)
               item)
   :register-right-click (fn [self item]
                           (table.insert self.registered item)
                           item)
   :register-double-click (fn [self item]
                            (table.insert self.registered item)
                            item)
   :unregister (fn [self item]
                 (table.insert self.unregistered item)
                 item)
   :unregister-right-click (fn [self item]
                             (table.insert self.unregistered item)
                             item)
   :unregister-double-click (fn [self item]
                              (table.insert self.unregistered item)
                              item)})

(fn make-hover-registry []
  {:registered []
   :unregistered []
   :register (fn [self item]
               (table.insert self.registered item)
               item)
   :unregister (fn [self item]
                 (table.insert self.unregistered item)
                 item)})

(fn make-ui-context []
  {:clickables (make-click-registry)
   :hoverables (make-hover-registry)})
```

Update `make-builder-hud` so its `add-panel-child` calls `(child.builder self.ctx {})`, stores `self.descriptor`, stores `self.ctx`, and appends the built widget. Initialize the HUD with `:ctx (make-ui-context)`.

- [ ] **Step 2: Extend fake mount command state**

Ensure `make-fake-mount` command fixtures have runnable `:restart` and `:explode` commands and expose `:command-state`. If the current file already has this from the command-surface slice, keep it and do not add aliases. The restart command should set `command-state.ran?` and record the payload. The visual build path must leave `command-state.ran?` false until a button click.

- [ ] **Step 3: Add failing visual panel assertions**

Extend `test-builder_path_returns_hud_widget_with_layout` after the existing layout assertion:

```fennel
(local controls (. hud.children 1 :__command-controls))
(assert controls "built panel widget should expose command controls state")
(assert (. controls.buttons-by-id :restart) "restart command should render a Run button")
(assert (= fake-mount.command-state.ran? false) "building visual controls must not execute commands")
```

Extend `test_descriptor_and_built_widget_run_hosted_command` or add a new test to click the rendered restart button:

```fennel
(fn test_built_widget_command_button_runs_hosted_command []
  (local hud (make-builder-hud))
  (local fake-mount (make-fake-mount))
  (local fixture (install-panel-module fake-mount))
  (local session (fixture.WorkspacePanel.open (panel-opts hud)))
  (local controls (. hud.children 1 :__command-controls))
  ((. controls.buttons-by-id :restart):on-click {:source :test})
  (assert (= fake-mount.command-state.ran? true))
  (assert (= fake-mount.command-state.payload nil) "visual panel buttons pass nil payload")
  (assert (= controls.last-result.status :ok))
  (assert (string.find controls.result-message "Restart" 1 true))
  (session:close)
  (fixture:restore))

(add-test "built widget command button runs hosted command" test_built_widget_command_button_runs_hosted_command)
```

- [ ] **Step 4: Integrate `WorkspaceCommandControls` in `workspace-panel.fnl`**

In `assets/lua/app-host/workspace-panel.fnl`:

- remove the `glm` and `Layout` requires if they are no longer used;
- remove `measure-zero`, `layout-noop`, and `make-panel-widget`;
- add `(local CommandControls (require :app-host.workspace-command-controls))`;
- replace `build-panel` with:

```fennel
(fn build-panel [ctx _builder-options]
  (local builder (CommandControls.WorkspaceCommandControls {:descriptor descriptor}))
  (builder ctx))
```

Do not change `session` fields, descriptor fields, `read-inspector-snapshot`, `run-command`, or `close` semantics.

- [ ] **Step 5: Validate and commit Task 2**

Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/workspace-command-controls.fnl --file assets/lua/app-host/workspace-panel.fnl --file assets/lua/tests/test-app-host-workspace-command-controls.fnl --file assets/lua/tests/test-hosted-app-workspace-panel.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-command-controls:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hosted-app-workspace-panel:main
```

Commit:

```bash
git add assets/lua/app-host/workspace-panel.fnl assets/lua/tests/test-hosted-app-workspace-panel.fnl
git commit -m "feat(apps): render hosted command controls in panels"
```

---

### Task 3: Documentation and Final Focused Validation

**Files:**
- Modify: `docs/dev/features/hosted-runtime-apps.md`

**Interfaces:**
- Consumes: public widget and panel behavior from Tasks 1 and 2.
- Produces: documented hosted workspace command-control behavior and retained no-goals.

- [ ] **Step 1: Update hosted runtime app docs**

In `docs/dev/features/hosted-runtime-apps.md`, update the workspace controls section to state:

```markdown
Workspace panels render generic command metadata rows from the read-only inspector snapshot. Each row includes a Run button that calls `descriptor/session:run-command(command-id, nil)`. The panel displays the latest success or error result from the command result envelope, while snapshot reads remain metadata-only and never execute commands.
```

Also ensure the follow-up paragraph keeps these as future subprojects:

- payload schemas;
- confirmations and permissions;
- async progress and cancellation;
- app-specific controls;
- editor integration;
- graph integration;
- persistent app discovery;
- launcher UX.

- [ ] **Step 2: Run final focused validation**

Run:

```bash
rg "command metadata|Run button|payload schemas|async progress" docs/dev/features/hosted-runtime-apps.md
make fennel-check
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-command-controls:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hosted-app-workspace-panel:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-inspector-snapshot:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-runner:main
```

- [ ] **Step 3: Confirm acceptance criteria**

Report evidence for each item:

- workspace panel HUD builder returns a visible command-controls widget with a layout;
- build reads snapshot metadata without executing commands;
- command rows have Run buttons keyed by command id;
- button click invokes `descriptor:run-command(command-id, nil)`;
- success/error envelopes update latest result messaging;
- structural failures remain loud;
- widget teardown unregisters button handlers;
- existing descriptor/session APIs remain compatible;
- no payload/schema/permission/async/app-specific/dashboard framework was added.

- [ ] **Step 4: Commit docs**

Commit only the docs change for this task:

```bash
git add docs/dev/features/hosted-runtime-apps.md
git commit -m "docs(apps): document hosted command controls"
```
