# Hosted Async Command Progress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add opt-in async hosted app commands with progress, cancellation, teardown cleanup, and backward-compatible synchronous command behavior.

**Architecture:** Preserve `CommandRunner.run-host`, command `:run`, `session:run-command`, and existing result envelopes. Add canonical `:run-async` plus `CommandRunner.run-host-async`, then thread that through workspace panel descriptors and command controls using callback handles, token-guarded UI updates, and lifecycle drop cleanup.

**Tech Stack:** Space Fennel, app-host command runner/panel/control modules, classic HUD widgets (`Button`, `StatusBadge`, `WrappedText`, `Flex`, `Padding`), Space Fennel test runner, `make fennel-check`, constraints, focused Lua/Fennel tests.

## Global Constraints

- No command queues or multiple concurrent workspace command runs.
- No persistent/background jobs beyond the lifetime of the workspace/session or controls widget.
- No polling API, durable run ids, job storage, or recovery after reload.
- No auth, permission prompts, approvals, or policy decisions.
- No payload-schema expansion beyond the existing flat forms.
- No app-specific custom command controls.
- No port of `next-app/progress-widget` into the classic HUD stack.
- No C++ engine or binding changes.
- Preserve existing synchronous `:run`, `CommandRunner.run-host`, `session:run-command`, and UI behavior for sync commands.
- `CommandRunner.run-host(host, command-id, payload)` keeps returning `{:id command-id :status :ok :value value}` for handler success and `{:id command-id :status :error :error error-string}` for handler exceptions.
- Structural host, registry, command id, command lookup, metadata, descriptor, and payload failures throw loudly and must not be converted into result envelopes.
- Async support is opt-in through canonical `:run-async`; do not add aliases or compatibility shims.
- Async commands emit progress and terminal success/error/cancel through callbacks.
- Cancellation is terminal and idempotent; late progress/resolve/reject callbacks after cancellation are ignored.
- Drop is lifecycle cleanup and does not emit a user-visible terminal result; late callbacks after drop are ignored.
- Workspace controls allow one active command per controls widget.
- First confirmation click only arms inline confirmation and must not build payloads or run handlers.
- Payload construction happens only on the actual execution click.
- Widget constructors return build closures.
- Builders receive renderer/build context and instantiate children with that context.
- Composite widgets own and drop their direct child widgets.
- Assert on missing required context instead of silently falling back.
- Use `local` instead of `let` in Fennel.
- Use factory functions instead of constructors (`.new`).
- Use project-native Fennel validation only: `make fennel-check` or touched-file `tools.fennel-check`, then `make constraints`, then focused Fennel tests.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- For direct test runs, set `SKIP_KEYRING_TESTS=1`, `XDG_DATA_HOME=/tmp/space/tests/xdg-data`, `SPACE_DISABLE_AUDIO=1`, `SPACE_ASSETS_PATH=$(pwd)/assets`, `FENNEL_PATH=$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl`, and the same value for `FENNEL_MACRO_PATH`.

---

## File Structure

- Modify `assets/lua/app-host/command-runner.fnl`: keep sync `run-host`; add `run-host-async`, async callbacks, progress validation, cancellation/drop handle semantics.
- Modify `assets/lua/tests/test-app-host-command-runner.fnl`: add focused runner tests for sync fallback, pending progress/resolve, reject/error, cancel, drop, and malformed async contracts.
- Modify `assets/lua/app-host/command-result-model.fnl`: add `progress-summary`; extend `result-summary` for `:cancelled`.
- Modify `assets/lua/tests/test-app-host-command-result-model.fnl`: add progress and cancelled summary tests.
- Modify `assets/lua/app-host/workspace-panel.fnl`: add `run-command-async` to session/descriptor and close cleanup for active invocation handles.
- Modify `assets/lua/tests/test-hosted-app-workspace-panel.fnl`: cover descriptor/session async delegation and close cleanup.
- Modify `assets/lua/app-host/workspace-command-controls.fnl`: prefer async descriptor method, support progress/cancel UI, token-guard callbacks, and drop cleanup.
- Modify `assets/lua/tests/test-app-host-workspace-command-controls.fnl`: cover async pending/progress/completion/cancel/drop and sync fallback regressions.
- Modify `docs/dev/features/hosted-runtime-apps.md` and `docs/dev/features/hosted-app-command-payload-forms.md`: document async API and remove stale out-of-scope wording.

---

### Task 1: Command Runner Async Invocation Contract

**Files:**
- Modify: `assets/lua/app-host/command-runner.fnl`
- Modify: `assets/lua/tests/test-app-host-command-runner.fnl`

**Interfaces:**
- Consumes existing `Metadata.validate-command(command, {:command-id command-id})` and existing sync `run-host` behavior.
- Produces:
  - Existing unchanged: `CommandRunner.run-host(host, command-id, payload) -> result-table`.
  - New: `CommandRunner.run-host-async(host, command-id, payload, callbacks) -> invocation-handle`.
  - Async command facet key: `:run-async`.
  - Async command callback table with `progress`, `resolve`, `reject`, `cancelled?`.
  - Caller callback table with required `on-result` and optional `on-progress`.
  - Invocation handle with `id`, `status`, `cancel`, `drop`, and `cancelled?`.

- [ ] **Step 1: Add failing sync-fallback async runner test**

Add a test named `async runner wraps sync command` to `assets/lua/tests/test-app-host-command-runner.fnl`:

```fennel
(fn test-async_runner_wraps_sync_command []
  (local state {:result-count 0 :progress-count 0 :result nil})
  (local host (host-with-commands [{:id :restart :run restart-command-run :state {:ran-restart? false}}]))
  (local handle (CommandRunner.run-host-async
                  host :restart {:value 42}
                  {:on-result (fn [result]
                                (set state.result-count (+ state.result-count 1))
                                (set state.result result))
                   :on-progress (fn [_progress]
                                  (set state.progress-count (+ state.progress-count 1)))}))
  (assert (= state.result-count 1))
  (assert (= state.progress-count 0))
  (assert (= state.result.id :restart))
  (assert (= state.result.status :ok))
  (assert (= state.result.value.payload-value 42))
  (assert (= handle.id :restart))
  (assert (= handle.status :completed)))
```

- [ ] **Step 2: Add failing pending progress/resolve test**

Add a test named `async runner reports progress and resolve`:

```fennel
(fn test-async_runner_reports_progress_and_resolve []
  (local state {:callbacks nil :progress nil :result nil})
  (local command {:id :long
                  :run-async (fn [_self _payload callbacks]
                               (set state.callbacks callbacks)
                               {:pending true})})
  (local handle (CommandRunner.run-host-async
                  (host-with-commands [command]) :long nil
                  {:on-progress (fn [progress] (set state.progress progress))
                   :on-result (fn [result] (set state.result result))}))
  (assert (= handle.status :running))
  (state.callbacks.progress {:message "halfway" :value 0.5})
  (assert (= state.progress.message "halfway"))
  (assert (= state.progress.value 0.5))
  (state.callbacks.resolve {:done? true})
  (assert (= state.result.status :ok))
  (assert (= state.result.value.done? true))
  (assert (= handle.status :completed)))
```

- [ ] **Step 3: Add failing reject/throw tests**

Add tests named `async runner reject returns error result` and `async runner thrown handler returns error result`. The reject case stores callbacks and calls `(state.callbacks.reject "boom")`; assert one result with `:status :error` and error containing `boom`. The thrown case uses `:run-async (fn [] (error "explode"))`; assert `on-result` receives one `:error` envelope and the returned handle is terminal `:completed`.

- [ ] **Step 4: Add failing cancellation test**

Add `async runner cancellation is terminal and idempotent`:

```fennel
(fn test-async_runner_cancellation_is_terminal_and_idempotent []
  (local state {:callbacks nil :cancel-count 0 :results []})
  (local command {:id :long
                  :run-async (fn [_self _payload callbacks]
                               (set state.callbacks callbacks)
                               {:pending true
                                :cancel (fn [_reason]
                                          (set state.cancel-count (+ state.cancel-count 1)))})})
  (local handle (CommandRunner.run-host-async
                  (host-with-commands [command]) :long nil
                  {:on-result (fn [result] (table.insert state.results result))}))
  (assert (= (state.callbacks.cancelled?) false))
  (handle:cancel "user cancelled")
  (assert (= state.cancel-count 1))
  (assert (= (state.callbacks.cancelled?) true))
  (assert (= (# state.results) 1))
  (assert (= (. state.results 1 :status) :cancelled))
  (state.callbacks.resolve {:late true})
  (handle:cancel "again")
  (assert (= state.cancel-count 1))
  (assert (= (# state.results) 1)))
```

- [ ] **Step 5: Add failing drop cleanup test**

Add `async runner drop suppresses late callbacks`: start a pending command with `:drop` and `:cancel`; call `handle:drop`; assert only `drop` count increments, no result is emitted, late progress/resolve/reject callbacks are ignored, and repeated drop is idempotent.

- [ ] **Step 6: Implement `run-host-async`**

In `command-runner.fnl`:

- Extract existing lookup/validation logic for reuse by `run-host` and `run-host-async`.
- Validate the caller callback table:

```fennel
(fn validate-async-callbacks [callbacks]
  (when (not (= (type callbacks) :table))
    (command-error "run-host-async requires callbacks table"))
  (when (not (= (type callbacks.on-result) :function))
    (command-error "run-host-async requires on-result callback")))
```

- Create an invocation handle table whose `:cancel`, `:drop`, and `:cancelled?` methods close over local `terminal?`, `cancelled?`, `dropped?`, and underlying pending handle fields.
- Deliver terminal results through a helper that checks `terminal?` and `dropped?`, sets handle status, and calls `callbacks.on-result` exactly once.
- Validate progress with explicit table shape: `:message`, when present, must be a string; `:value`, when present, must be a number between `0` and `1`. Malformed progress calls deliver one `:error` envelope.
- If `command.run-async` exists, call it with `(command payload async-callbacks)` inside `pcall`.
- If `command.run-async` is absent, call existing `run-host`, deliver its result synchronously, and return a completed handle.
- If neither `:run-async` nor `:run` is a function, throw a structural command-runner error.
- Treat malformed async return values as one `:error` envelope.

- [ ] **Step 7: Validate Task 1**

Run:

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/command-runner.fnl --file assets/lua/tests/test-app-host-command-runner.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-runner:main
```

Expected: compile check passes, constraints pass, command runner tests pass.

- [ ] **Step 8: Commit Task 1**

```bash
git add assets/lua/app-host/command-runner.fnl assets/lua/tests/test-app-host-command-runner.fnl
git commit -m "feat(lua): add hosted async command runner"
```

Include compile/constraints/test evidence, coverage rationale, and constraint-impact note in the implementer report.

---

### Task 2: Result Model Progress and Cancellation Summaries

**Files:**
- Modify: `assets/lua/app-host/command-result-model.fnl`
- Modify: `assets/lua/tests/test-app-host-command-result-model.fnl`

**Interfaces:**
- Consumes progress table `{:message string? :value number?}` from Task 1.
- Consumes cancellation result envelope `{:id command-id :status :cancelled :error reason-string?}` from Task 1.
- Produces `ResultModel.progress-summary(command, progress) -> summary-table`.
- Extends `ResultModel.result-summary(command, result)` for `result.status == :cancelled`.

- [ ] **Step 1: Add failing progress-summary tests**

Add to `test-app-host-command-result-model.fnl`:

```fennel
(fn test-progress-summary-with-percent []
  (local summary (ResultModel.progress-summary {:id :long :title "Long"}
                                               {:message "halfway" :value 0.5}))
  (assert (= summary.phase :running))
  (assert (= summary.tone :info))
  (assert (= summary.badge-text "Running"))
  (assert (= summary.command-id :long))
  (assert (string.find summary.message "Long" 1 true))
  (assert (string.find summary.message "halfway" 1 true))
  (assert (string.find summary.message "50%" 1 true)))

(fn test-progress-summary-message-only []
  (local summary (ResultModel.progress-summary {:id :long :title "Long"}
                                               {:message "working"}))
  (assert (= summary.phase :running))
  (assert (string.find summary.message "working" 1 true))
  (assert (= (string.find summary.message "%" 1 true) nil)))
```

- [ ] **Step 2: Add failing cancelled-summary test**

```fennel
(fn test-cancelled-result-summary []
  (local summary (ResultModel.result-summary {:id :long :title "Long"}
                                             {:id :long :status :cancelled :error "user cancelled"}))
  (assert (= summary.phase :cancelled))
  (assert (= summary.tone :warning))
  (assert (= summary.badge-text "Cancelled"))
  (assert (string.find summary.message "Long" 1 true))
  (assert (string.find summary.message "user cancelled" 1 true)))
```

- [ ] **Step 3: Implement result model extensions**

Add `progress-summary` with percent text only when `progress.value` is a number in `[0, 1]`. Extend `result-summary` with a `:cancelled` branch before unknown-status fallback. Preserve existing bounded value rendering for `:ok`.

- [ ] **Step 4: Validate Task 2**

Run:

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/command-result-model.fnl --file assets/lua/tests/test-app-host-command-result-model.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-result-model:main
```

- [ ] **Step 5: Commit Task 2**

```bash
git add assets/lua/app-host/command-result-model.fnl assets/lua/tests/test-app-host-command-result-model.fnl
git commit -m "feat(lua): summarize hosted async command progress"
```

---

### Task 3: Workspace Panel Async Session API

**Files:**
- Modify: `assets/lua/app-host/workspace-panel.fnl`
- Modify: `assets/lua/tests/test-hosted-app-workspace-panel.fnl`

**Interfaces:**
- Consumes `CommandRunner.run-host-async(host, command-id, payload, callbacks) -> invocation-handle` from Task 1.
- Produces `session:run-command-async(command-id, payload, callbacks) -> invocation-handle`.
- Produces `descriptor:run-command-async(command-id, payload, callbacks) -> invocation-handle`.
- Preserves `session:run-command` and `descriptor:run-command` unchanged.

- [ ] **Step 1: Add failing workspace-panel async delegation test**

In `test-hosted-app-workspace-panel.fnl`, follow the existing fixture style and add a command with `:run-async` that stores callbacks and returns `{:pending true :drop drop-fn}`. Open a workspace panel, call `session:run-command-async :long nil callbacks`, and assert the command callback storage happened and the returned handle status is `:running`.

- [ ] **Step 2: Add failing close cleanup test**

Add a test that opens a session, starts a pending async command, calls `session:close()`, and asserts the pending handle `drop` function was called exactly once. Call `session:close()` again and assert the drop count remains one.

- [ ] **Step 3: Implement async session/descriptor methods**

In `workspace-panel.fnl`:

- Add local `active-async-handles` table.
- Add `run-command-async` beside `run-command`.
- Wrap caller `on-result` so completed handles are removed from `active-async-handles` before forwarding.
- Add running handles to `active-async-handles` only when `handle.status == :running`.
- Add `run-command-async` to both `session` and `descriptor` tables.

- [ ] **Step 4: Implement close cleanup**

Before `mount:drop` in `close`, iterate active handles and call `handle:drop()` with `pcall`. Attempt all handles; store the first error; clear the active handle list; then rethrow the first cleanup error after attempts complete. Keep HUD child removal and mount drop idempotent.

- [ ] **Step 5: Validate Task 3**

Run:

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/workspace-panel.fnl --file assets/lua/tests/test-hosted-app-workspace-panel.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hosted-app-workspace-panel:main
```

- [ ] **Step 6: Commit Task 3**

```bash
git add assets/lua/app-host/workspace-panel.fnl assets/lua/tests/test-hosted-app-workspace-panel.fnl
git commit -m "feat(lua): expose hosted async command sessions"
```

---

### Task 4: Workspace Command Controls Async UI

**Files:**
- Modify: `assets/lua/app-host/workspace-command-controls.fnl`
- Modify: `assets/lua/tests/test-app-host-workspace-command-controls.fnl`

**Interfaces:**
- Consumes optional `descriptor:run-command-async(command-id, payload, callbacks) -> invocation-handle` from Task 3.
- Consumes existing `descriptor:run-command(command-id, payload) -> result-table` fallback.
- Consumes `ResultModel.progress-summary(command, progress)` and `ResultModel.result-summary(command, result)` from Task 2.
- Produces state fields for tests: `active-invocation`, `active-run-token`.
- Preserves state fields: `busy?`, `active-command-id`, `result-summary`, `result-message`, `last-result`, `button-labels-by-id`.

- [ ] **Step 1: Add failing pending-state controls test**

Add a descriptor fixture with `run-command-async` that stores callbacks and returns a pending handle. Click a command button and assert:

```fennel
(assert (= state.busy? true))
(assert (= state.active-command-id :long))
(assert (= (. state.button-labels-by-id :long) "Cancel"))
(assert (= (. state.buttons-by-id :long :enabled?) true))
(assert (= (. state.buttons-by-id :other :enabled?) false))
(assert (= state.result-summary.phase :running))
```

- [ ] **Step 2: Add failing progress update test**

After starting pending command, call stored `on-progress {:message "halfway" :value 0.5}`. Assert `state.result-summary.phase :running`, `state.result-message` contains command label, `halfway`, and `50%`, and `state.result-badge.tone :info`.

- [ ] **Step 3: Add failing async completion test**

After starting pending command, call stored `on-result {:id :long :status :ok :value "done"}`. Assert busy false, active command nil, all buttons enabled, labels restored to `Run`, last result `:ok`, and visible summary success.

- [ ] **Step 4: Add failing cancel-click test**

Start pending command, click the active command button again, assert the pending handle cancel function was called once, cancellation summary becomes `:cancelled`, buttons re-enable, labels restore, and late success callback is ignored.

- [ ] **Step 5: Add failing drop cleanup test**

Start pending command, call `widget:drop()`, assert active invocation `drop` count is one. Invoke stored progress/result callbacks after drop and assert `state.result-message` and `state.last-result` do not change.

- [ ] **Step 6: Refactor execution flow**

In `workspace-command-controls.fnl`:

- Preserve the confirmation first-click branch and payload timing.
- After payload validation, prefer `descriptor:run-command-async` when present.
- Fallback to existing `descriptor:run-command` and route the returned result through the same terminal-result helper.
- Keep structural failure restoration for descriptor invocation throws.

- [ ] **Step 7: Implement running/cancel UI helpers**

Add helpers to set non-active buttons enabled/disabled, set active label to `Cancel`, restore labels, set `state.active-invocation`, and clear terminal state. The only allowed busy-time click is active-command cancellation; other busy clicks return without payload build or command execution.

- [ ] **Step 8: Implement token-guarded callbacks**

Increment `state.active-run-token` on each actual execution. Callback closures must check not dropped, token match, and current active command id before mutating state. Ignore stale callbacks after completion, cancel, newer run, or drop.

- [ ] **Step 9: Validate Task 4**

Run:

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/workspace-command-controls.fnl --file assets/lua/tests/test-app-host-workspace-command-controls.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-command-controls:main
```

- [ ] **Step 10: Commit Task 4**

```bash
git add assets/lua/app-host/workspace-command-controls.fnl assets/lua/tests/test-app-host-workspace-command-controls.fnl
git commit -m "feat(ui): support hosted async command progress"
```

---

### Task 5: Developer Documentation

**Files:**
- Modify: `docs/dev/features/hosted-runtime-apps.md`
- Modify: `docs/dev/features/hosted-app-command-payload-forms.md`

**Interfaces:**
- Consumes the final async runner/session/control API from Tasks 1-4.
- Produces canonical docs for hosted async command progress/cancellation.

- [ ] **Step 1: Document `:run-async` in hosted runtime docs**

Add an example command facet with `:run-async`, `callbacks.progress`, `callbacks.resolve`, `callbacks.reject`, `callbacks.cancelled?`, and pending return `{:pending true :cancel cancel-fn :drop drop-fn}`.

- [ ] **Step 2: Document session/control behavior**

Document `session:run-command-async(command-id, payload, callbacks)`, one active command per controls widget, active button becomes Cancel, progress appears in the result badge/text area, terminal success/error/cancel restores controls, and close/drop cleans up pending invocations.

- [ ] **Step 3: Remove stale out-of-scope wording**

Search docs and remove or rewrite claims that async progress/cancellation remain future work. Keep queues, persistent jobs, polling APIs, auth/permissions, persistent approvals, and app discovery out of scope.

- [ ] **Step 4: Run docs check**

```bash
rg -n "async progress|cancellation|run-command-async|run-async|pending command|command queue" docs/dev/features
```

Expected: output shows the new async docs and retained queue/persistent-job non-goals without contradictions.

- [ ] **Step 5: Commit Task 5**

```bash
git add docs/dev/features/hosted-runtime-apps.md docs/dev/features/hosted-app-command-payload-forms.md
git commit -m "docs: document hosted async commands"
```

---

### Task 6: Final Validation and Acceptance Evidence

**Files:**
- No implementation files should change.
- Write validation evidence only to the SDD report path provided by the supervisor.

**Interfaces:**
- Consumes all implementation and docs from Tasks 1-5.
- Produces final validation evidence for review and finishing gates.

- [ ] **Step 1: Run full Fennel compile check**

```bash
make fennel-check
```

- [ ] **Step 2: Run constraints**

```bash
make constraints
```

- [ ] **Step 3: Run focused hosted command tests**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-runner:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-result-model:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hosted-app-workspace-panel:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-command-controls:main
```

- [ ] **Step 4: Run fast suite**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
```

If validation fails, do not mark the task complete. Capture the failing command, relevant output, branch state, and `git status --porcelain`; the supervisor must invoke systematic debugging.

- [ ] **Step 5: Record acceptance evidence**

The report must cite evidence that sync commands remain compatible, async runner progress/resolve/reject/cancel/drop semantics work, result model progress/cancel summaries work, workspace panel close drops active handles, command controls show progress/cancel and ignore late callbacks, docs no longer claim async progress/cancellation is out of scope, and no C++/binding changes were required.

- [ ] **Step 6: Do not create an empty commit**

If validation did not change repository files, leave git history unchanged for this task.

---

## Validation Summary

Minimum implementation-task validation:

```bash
./build/space -m tools.fennel-check:main -- --target files --file <touched-fennel-file> [...]
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m <focused-test-module>:main
```

Final validation uses `make fennel-check`, `make constraints`, focused hosted command tests, and `tests.fast:main`. PR CI remains the full integration gate before ready-to-merge claims.
