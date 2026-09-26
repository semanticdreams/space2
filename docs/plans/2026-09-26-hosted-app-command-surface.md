# Hosted App Command Surface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a first generic hosted app command execution surface through workspace panel sessions/descriptors without changing command registries or adding visual action UI.

**Architecture:** Introduce a small `app-host.command-runner` helper that validates `host.commands:list()`, looks up a unique command by `:id`, and returns explicit success/error result envelopes. Wire `WorkspacePanel` to expose this helper as `run-command` on sessions and descriptors while keeping inspector snapshots metadata-only. Document the minimal command contract and defer visual buttons, schemas, permissions, and async protocols.

**Tech Stack:** Space Fennel, `app-host` registries, workspace panel session/descriptor APIs, focused Fennel tests, `tools.fennel-check`, `make constraints`.

## Global Constraints

- Add a first generic hosted app command execution surface.
- Preserve existing workspace panel session API and add exactly one command method: `run-command`.
- Execute commands from `host.commands:list()` by command id.
- Keep inspector snapshots metadata-only; snapshot reads must not execute commands.
- Return explicit result envelopes for command handler success/failure.
- Fail loudly for structural host/registry/command contract errors.
- Preserve workspace panel mount ownership and teardown behavior.
- Document the command execution contract and follow-up boundaries.
- Do not add visual command buttons or editor widgets.
- Do not add command schemas, permissions, confirmation prompts, async progress, cancellation, or multi-value result protocols.
- Do not add command-specific methods to generic registries.
- Do not redesign runtime-controller command registration.
- Do not add app-specific command APIs or Snake-specific commands.
- Do not add aliases such as `execute-command`.
- Structural command lookup/contract failures throw loudly with the command runner prefix.
- Command handler exceptions are caught and returned as `:status :error` result envelopes so a workspace panel can display the failure without tearing down the panel.
- Workspace panel close/drop semantics remain unchanged.
- Widget/UI code must follow Space Fennel UI guidance: builders receive context, widgets own explicit layouts, composite widgets drop children, and missing required context fails loudly.
- Use `local` instead of `let` in Fennel.
- Use factory functions instead of `.new` constructors.
- For Fennel work, compile-check first with project-native `tools.fennel-check`/`make fennel-check`, then run `make constraints`, then focused Fennel tests.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- For direct test runs, set `SKIP_KEYRING_TESTS=1`, `XDG_DATA_HOME=/tmp/space/tests/xdg-data`, `SPACE_DISABLE_AUDIO=1`, `SPACE_ASSETS_PATH=$(pwd)/assets`, `FENNEL_PATH=$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl`, and the same value for `FENNEL_MACRO_PATH`.

---

## File Structure

- `assets/lua/app-host/command-runner.fnl`: new helper that validates and executes command facets from `host.commands:list()`.
- `assets/lua/tests/test-app-host-command-runner.fnl`: focused tests for command execution, result envelopes, and structural failures.
- `assets/lua/app-host/workspace-panel.fnl`: expose `run-command` through workspace panel sessions/descriptors.
- `assets/lua/tests/test-hosted-app-workspace-panel.fnl`: extend workspace panel tests for command execution and snapshot non-execution.
- `docs/dev/features/hosted-runtime-apps.md`: document command facets and workspace panel command execution.

---

### Task 1: Generic Command Runner

**Files:**
- Create: `assets/lua/app-host/command-runner.fnl`
- Create: `assets/lua/tests/test-app-host-command-runner.fnl`

**Interfaces:**
- Produces: `CommandRunner.run-host(host: table, command-id: any, payload: any|nil) -> result: table`.
- Success result: `{:id command-id :status :ok :value first-return-value}`.
- Handler error result: `{:id command-id :status :error :error error-string}`.
- Consumes host registry `host.commands:list() -> sequential command facets`.

- [ ] **Step 1: Write command runner test scaffolding**

Create `assets/lua/tests/test-app-host-command-runner.fnl`:

```fennel
(local Runner (require :tests/runner))
(local CommandRunner (require :app-host.command-runner))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn assert-error-contains [f expected]
  (local (ok err) (pcall f))
  (assert (= ok false) "expected call to fail")
  (assert (string.find (tostring err) expected 1 true)
          (.. "expected error to contain " expected ", got " (tostring err))))

(fn registry [items]
  {:list (fn [_self]
           (local out [])
           (each [_ item (ipairs items)]
             (table.insert out item))
           out)})

(fn host-with-commands [commands]
  {:commands (registry commands)})

(fn main []
  (Runner.run-tests {:name "app-host-command-runner" :tests tests}))

{:main main :tests tests}
```

- [ ] **Step 2: Add failing success and payload test**

Add:

```fennel
(fn test-runs-matching-command-with-payload []
  (var ran-restart? false)
  (var ran-other? false)
  (var received-payload nil)
  (local restart-command {:id :restart
                          :run (fn [self payload]
                                 (set ran-restart? true)
                                 (set received-payload payload)
                                 {:self-id self.id :payload-value payload.value})})
  (local host (host-with-commands [restart-command
                                   {:id :other
                                    :run (fn [_self _payload]
                                           (set ran-other? true))}]))
  (local result (CommandRunner.run-host host :restart {:value 42}))
  (assert (= result.id :restart))
  (assert (= result.status :ok))
  (assert (= result.value.self-id :restart))
  (assert (= result.value.payload-value 42))
  (assert (= ran-restart? true))
  (assert (= ran-other? false) "non-matching commands must not run")
  (assert (= received-payload.value 42)))

(add-test "runs matching command with payload" test-runs-matching-command-with-payload)
```

Run and expect failure because `app-host.command-runner` does not exist:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-runner:main
```

- [ ] **Step 3: Add failing command handler error test**

Add:

```fennel
(fn test-command-handler-errors-return-error-result []
  (local host (host-with-commands [{:id :explode
                                    :run (fn [_self _payload]
                                           (error "boom"))}]))
  (local result (CommandRunner.run-host host :explode {:why :test}))
  (assert (= result.id :explode))
  (assert (= result.status :error))
  (assert (string.find result.error "boom" 1 true)))

(add-test "command handler errors return error result" test-command-handler-errors-return-error-result)
```

- [ ] **Step 4: Add failing structural error tests**

Add:

```fennel
(fn test-structural-command-failures-are-loud []
  (assert-error-contains #(CommandRunner.run-host nil :restart {}) "host table")
  (assert-error-contains #(CommandRunner.run-host {} :restart {}) "commands")
  (assert-error-contains #(CommandRunner.run-host {:commands {}} :restart {}) "list")
  (assert-error-contains #(CommandRunner.run-host (host-with-commands []) nil {}) "command id")
  (assert-error-contains #(CommandRunner.run-host (host-with-commands []) :missing {}) "not found")
  (assert-error-contains #(CommandRunner.run-host (host-with-commands [{:id :dup :run (fn [] true)}
                                                                        {:id :dup :run (fn [] true)}]) :dup {})
                         "duplicate")
  (assert-error-contains #(CommandRunner.run-host (host-with-commands [{:id :bad}]) :bad {})
                         "run"))

(add-test "structural command failures are loud" test-structural-command-failures-are-loud)
```

- [ ] **Step 5: Implement `command-runner.fnl`**

Create `assets/lua/app-host/command-runner.fnl`:

```fennel
(fn command-error [message]
  (error (.. "[app-host.command-runner] " message)))

(fn command-list [host]
  (when (not (= (type host) :table))
    (command-error "run-host requires host table"))
  (local registry host.commands)
  (when (not (= (type registry) :table))
    (command-error "host commands registry is required"))
  (when (not (= (type registry.list) :function))
    (command-error "host commands registry requires list"))
  (registry:list))

(fn find-command [commands command-id]
  (when (= command-id nil)
    (command-error "run-host requires command id"))
  (var found nil)
  (var count 0)
  (each [_ command (ipairs commands)]
    (when (= command.id command-id)
      (set count (+ count 1))
      (set found command)))
  (when (= count 0)
    (command-error (.. "command not found: " (tostring command-id))))
  (when (> count 1)
    (command-error (.. "duplicate command id: " (tostring command-id))))
  found)

(fn run-host [host command-id payload]
  (local command (find-command (command-list host) command-id))
  (local run-fn command.run)
  (when (not (= (type run-fn) :function))
    (command-error (.. "command requires run function: " (tostring command-id))))
  (local (ok value) (pcall run-fn command payload))
  (if ok
      {:id command-id :status :ok :value value}
      {:id command-id :status :error :error (tostring value)}))

{:run-host run-host}
```

- [ ] **Step 6: Validate and commit Task 1**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/command-runner.fnl --file assets/lua/tests/test-app-host-command-runner.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-runner:main
```

Commit:

```bash
git add assets/lua/app-host/command-runner.fnl assets/lua/tests/test-app-host-command-runner.fnl
git commit -m "feat(apps): add hosted command runner"
```

---

### Task 2: Workspace Panel Command Surface

**Files:**
- Modify: `assets/lua/app-host/workspace-panel.fnl`
- Modify: `assets/lua/tests/test-hosted-app-workspace-panel.fnl`

**Interfaces:**
- Consumes: `CommandRunner.run-host(host, command-id, payload) -> command-result` from Task 1.
- Produces: `session:run-command(command-id, payload) -> command-result` and `descriptor:run-command(command-id, payload) -> command-result`.

- [ ] **Step 1: Extend fake mount commands in workspace panel tests**

In `test-hosted-app-workspace-panel.fnl`, replace `make-fake-mount` with this version so it includes a runnable command, a throwing command, and keeps mutable state:

```fennel
(fn make-fake-mount []
  (local command-state {:ran? false :payload nil})
  (local controller {:paused-calls []
                     :step-calls []
                     :set-paused (fn [self paused]
                                   (table.insert self.paused-calls paused)
                                   paused)
                     :step (fn [self delta-ms]
                             (table.insert self.step-calls delta-ms)
                             delta-ms)})
  {:controller controller
   :host {:inspectors (registry [{:id :state
                                  :title "State"
                                  :read read-fake-state}])
          :commands (registry [{:id :restart
                                :title "Restart"
                                :run (fn [_self payload]
                                       (set command-state.ran? true)
                                       (set command-state.payload payload)
                                       {:restarted? true :value payload.value})}
                               {:id :explode
                                :title "Explode"
                                :run (fn [_self _payload]
                                       (error "command exploded"))}])}
   :command-state command-state
   :drop-count 0
   :drop (fn [self]
            (set self.drop-count (+ self.drop-count 1)))})
```

- [ ] **Step 2: Add failing `session:run-command` test**

Add:

```fennel
(fn test-session_runs_hosted_command []
  (local hud (make-fake-hud))
  (local fake-mount (make-fake-mount))
  (local fixture (install-panel-module fake-mount))
  (local session (fixture.WorkspacePanel.open (panel-opts hud)))
  (local result (session:run-command :restart {:value 7}))
  (assert (= result.status :ok))
  (assert (= result.value.value 7))
  (assert (= fake-mount.command-state.ran? true))
  (assert (= fake-mount.command-state.payload.value 7))
  (fixture:restore))

(add-test "session runs hosted command" test-session_runs_hosted_command)
```

- [ ] **Step 3: Add failing descriptor and widget command tests**

Add:

```fennel
(fn test_descriptor_and_widget_run_hosted_command []
  (local hud (make-builder-hud))
  (local fake-mount (make-fake-mount))
  (local fixture (install-panel-module fake-mount))
  (local session (fixture.WorkspacePanel.open (panel-opts hud)))
  (local descriptor-result (hud.descriptor:run-command :restart {:value 9}))
  (local widget-descriptor (. hud.children 1 :hosted-app-workspace-panel))
  (local widget-result (widget-descriptor:run-command :restart {:value 11}))
  (assert (= descriptor-result.status :ok))
  (assert (= widget-result.status :ok))
  (assert (= widget-result.value.value 11))
  (session:close)
  (fixture:restore))

(fn test_command_errors_return_result_envelope []
  (local hud (make-fake-hud))
  (local fake-mount (make-fake-mount))
  (local fixture (install-panel-module fake-mount))
  (local session (fixture.WorkspacePanel.open (panel-opts hud)))
  (local result (session:run-command :explode {}))
  (assert (= result.status :error))
  (assert (string.find result.error "command exploded" 1 true))
  (fixture:restore))

(add-test "descriptor and widget run hosted command" test_descriptor_and_widget_run_hosted_command)
(add-test "command errors return result envelope" test_command_errors_return_result_envelope)
```

- [ ] **Step 4: Assert snapshots still do not execute commands**

Extend `test-session_exposes_read_only_inspector_snapshot` with these assertions immediately after the existing command id assertion:

```fennel
(local snapshot (session:read-inspector-snapshot))
(assert (= (. snapshot.commands 1 :id) :restart))
(assert (= fake-mount.command-state.ran? false) "snapshot must not execute command")
```

- [ ] **Step 5: Wire workspace panel to command runner**

In `assets/lua/app-host/workspace-panel.fnl`, add:

```fennel
(local CommandRunner (require :app-host.command-runner))
```

Inside `open`, add:

```fennel
(fn run-command [_self command-id payload]
  (CommandRunner.run-host mount.host command-id payload))
```

Add `:run-command run-command` to both `session` and `descriptor`.

- [ ] **Step 6: Validate and commit Task 2**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/workspace-panel.fnl --file assets/lua/tests/test-hosted-app-workspace-panel.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-runner:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hosted-app-workspace-panel:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-inspector-snapshot:main
```

Commit:

```bash
git add assets/lua/app-host/workspace-panel.fnl assets/lua/tests/test-hosted-app-workspace-panel.fnl
git commit -m "feat(apps): expose hosted commands from workspace panel"
```

---

### Task 3: Docs and Final Validation

**Files:**
- Modify: `docs/dev/features/hosted-runtime-apps.md`

**Interfaces:**
- Consumes: command runner and workspace panel `run-command` behavior from Tasks 1 and 2.
- Produces: docs and validation evidence for branch finishing.

- [ ] **Step 1: Update hosted runtime docs**

In `docs/dev/features/hosted-runtime-apps.md`:

- In “Runtime composition facets”, document command facets as:

```markdown
- `commands`: sequential command facets such as `{:id id :title title :description description :run fn}`. Commands are registered with `host.commands`; command handlers receive the command facet and optional payload.
```

- In “Minimal workspace controls”, add `session:run-command(command-id, payload)` to the session method list.
- State that inspector snapshots list command metadata without executing commands.
- Replace “Command execution remains follow-up” wording with narrower follow-ups: richer visual controls, schemas, async progress, permissions, editor integration, graph integration, app discovery, and launcher UX.

- [ ] **Step 2: Run final compile and constraints**

Run:

```bash
make fennel-check
make constraints
```

- [ ] **Step 3: Run focused command/panel tests**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-runner:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hosted-app-workspace-panel:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-inspector-snapshot:main
```

- [ ] **Step 4: Run adjacent hosted app tests**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-runtime-controller:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hosted-app-workspace-mount:main
```

- [ ] **Step 5: Confirm acceptance criteria and clean tree**

Confirm in the report:

- workspace sessions and descriptors can run commands by id;
- command success/error result envelopes work;
- structural command failures fail loudly;
- snapshots remain metadata-only and do not execute commands;
- existing workspace panel controls/teardown pass;
- no registry redesign, app-specific API, visual command UI, schema protocol, or async framework was added.

Run:

```bash
git status --short
```

Expected: clean tree after reviewed commits.

- [ ] **Step 6: Commit docs if not already committed**

If Task 3 made only docs changes and validation passed, commit:

```bash
git add docs/dev/features/hosted-runtime-apps.md
git commit -m "docs(apps): document hosted command surface"
```
