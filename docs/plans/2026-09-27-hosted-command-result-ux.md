# Hosted Command Result UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add production-quality latest-result rendering and synchronous busy/double-run protection to hosted app command controls.

**Architecture:** Keep the existing synchronous `descriptor/session:run-command(command-id, payload)` contract and preserve command result envelopes. Add a pure `app-host.command-result-model` helper that maps command/result state to display summaries, then have `workspace-command-controls.fnl` render those summaries with `StatusBadge` and `WrappedText` while guarding reentrant clicks.

**Tech Stack:** Space Fennel, classic HUD widgets (`Button`, `StatusBadge`, `WrappedText`, `Flex`, `Padding`), app-host command descriptors, `tools.fennel-check`, constraints, focused Fennel tests.

## Global Constraints

- No command registry API changes.
- Preserve handler result-envelope semantics: success returns `{:id command-id :status :ok :value value}` and handler exceptions return `{:id command-id :status :error :error error-string}`.
- Structural host, registry, metadata, lookup, descriptor, and payload validation failures throw loudly and must not be converted into command result envelopes.
- No async command API, pending handles, polling, progress bars, cancellation, or command queues.
- No app-specific command controls.
- No permissions/auth policy, persistent approvals, or “always allow” behavior.
- No rich object inspector for command return values beyond deterministic bounded text rendering.
- Required confirmation remains inline/two-click; first-click confirmation must not build payloads or run handlers.
- Payload construction happens only on the actual execution click.
- Widget constructors return build closures.
- Builders receive renderer/build context and instantiate children with that context.
- Composite widgets own and drop their direct child widgets.
- Assert on missing required context instead of silently falling back.
- Use `local` instead of `let` in Fennel.
- Use factory functions instead of constructors (`.new`).
- Use project-native Fennel validation only: touched-file `tools.fennel-check` or `make fennel-check`, then `make constraints`, then focused Fennel tests.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- For direct test runs, set `SKIP_KEYRING_TESTS=1`, `XDG_DATA_HOME=/tmp/space/tests/xdg-data`, `SPACE_DISABLE_AUDIO=1`, `SPACE_ASSETS_PATH=$(pwd)/assets`, `FENNEL_PATH=$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl`, and the same value for `FENNEL_MACRO_PATH`.

---

## File Structure

- Create `assets/lua/app-host/command-result-model.fnl`: pure summary and bounded value-formatting helper. It must not require widgets, descriptors, registries, or host objects.
- Create `assets/lua/tests/test-app-host-command-result-model.fnl`: focused unit tests for summary phases, tones, messages, and bounded formatting.
- Modify `assets/lua/app-host/workspace-command-controls.fnl`: render result summaries with a status badge plus text; add synchronous busy/reentrant guards; preserve confirmation/payload timing and widget ownership.
- Modify `assets/lua/tests/test-app-host-workspace-command-controls.fnl`: extend existing tests for result badge/message state, busy behavior, reentrant suppression, and cleanup after structural errors.
- Modify `assets/lua/tests/fast.fnl`: register the new result-model suite and app-host command-control suite in the fast suite if they are not already listed.
- Modify `docs/dev/features/hosted-runtime-apps.md`: document result badge/message behavior, bounded values, busy suppression, and deferred async boundary.

---

### Task 1: Command Result Model

**Files:**
- Create: `assets/lua/app-host/command-result-model.fnl`
- Create: `assets/lua/tests/test-app-host-command-result-model.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: command tables with optional `:id`, `:title`; result envelopes with `:status`, `:value`, and `:error`.
- Produces module `app-host.command-result-model` with:
  - `initial-summary() -> {:phase :idle :badge-text string :tone keyword :message string :command-id nil :result nil}`
  - `confirmation-summary(command table, message string) -> summary`
  - `running-summary(command table) -> summary`
  - `result-summary(command table, result table) -> summary`
  - `value-text(value any) -> string|nil`
- Summary shape is always `{:phase keyword :badge-text string :tone keyword :message string :command-id any|nil :result table|nil}`.
- `value-text` output is deterministic and no longer than 500 characters.

- [ ] **Step 1: Write failing model tests**

Create `assets/lua/tests/test-app-host-command-result-model.fnl` using the existing test-runner pattern:

```fennel
(local Runner (require :tests/runner))
(local ResultModel (require :app-host.command-result-model))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn test-initial-summary []
  (local summary (ResultModel.initial-summary))
  (assert (= summary.phase :idle))
  (assert (= summary.tone :neutral))
  (assert (= summary.badge-text "Idle"))
  (assert (string.find summary.message "No command run" 1 true))
  (assert (= summary.command-id nil))
  (assert (= summary.result nil)))

(fn test-confirmation-summary []
  (local summary (ResultModel.confirmation-summary {:id :reset :title "Reset"} "Reset game state?"))
  (assert (= summary.phase :confirming))
  (assert (= summary.tone :warning))
  (assert (= summary.badge-text "Confirm"))
  (assert (= summary.command-id :reset))
  (assert (string.find summary.message "Reset game state?" 1 true)))

(fn test-running-summary []
  (local summary (ResultModel.running-summary {:id :configure :title "Configure"}))
  (assert (= summary.phase :running))
  (assert (= summary.tone :info))
  (assert (= summary.badge-text "Running"))
  (assert (= summary.command-id :configure))
  (assert (string.find summary.message "Configure" 1 true)))

(fn test-ok-summary-includes-value []
  (local summary (ResultModel.result-summary {:id :restart :title "Restart"}
                                             {:id :restart :status :ok :value "done"}))
  (assert (= summary.phase :ok))
  (assert (= summary.tone :success))
  (assert (= summary.badge-text "Success"))
  (assert (string.find summary.message "Restart" 1 true))
  (assert (string.find summary.message "done" 1 true)))

(fn test-ok-summary-with-nil-value []
  (local summary (ResultModel.result-summary {:id :restart :title "Restart"}
                                             {:id :restart :status :ok}))
  (assert (= summary.phase :ok))
  (assert (string.find summary.message "succeeded" 1 true))
  (assert (= (string.find summary.message "value" 1 true) nil)))

(fn test-error-summary []
  (local summary (ResultModel.result-summary {:id :explode :title "Explode"}
                                             {:id :explode :status :error :error "boom"}))
  (assert (= summary.phase :error))
  (assert (= summary.tone :danger))
  (assert (= summary.badge-text "Error"))
  (assert (string.find summary.message "Explode" 1 true))
  (assert (string.find summary.message "boom" 1 true)))

(fn test-unknown-summary []
  (local summary (ResultModel.result-summary {:id :mystery :title "Mystery"}
                                             {:id :mystery :status :queued}))
  (assert (= summary.phase :unknown))
  (assert (= summary.tone :warning))
  (assert (= summary.badge-text "Unknown"))
  (assert (string.find summary.message "queued" 1 true)))

(fn test-table-value-is-stable-and-bounded []
  (local rendered (ResultModel.value-text {:z 3 :a 1 :nested {:x true}}))
  (assert (string.find rendered ":a" 1 true))
  (assert (string.find rendered ":z" 1 true))
  (assert (<= (# rendered) 500)))

(fn test-long-value-is-truncated []
  (local long (string.rep "x" 700))
  (local rendered (ResultModel.value-text long))
  (assert (<= (# rendered) 500))
  (assert (string.find rendered "truncated" 1 true)))

(add-test "initial summary" test-initial-summary)
(add-test "confirmation summary" test-confirmation-summary)
(add-test "running summary" test-running-summary)
(add-test "ok summary includes value" test-ok-summary-includes-value)
(add-test "ok summary with nil value" test-ok-summary-with-nil-value)
(add-test "error summary" test-error-summary)
(add-test "unknown summary" test-unknown-summary)
(add-test "table value is stable and bounded" test-table-value-is-stable-and-bounded)
(add-test "long value is truncated" test-long-value-is-truncated)

(fn main []
  (Runner.run-tests {:name "app-host-command-result-model" :tests tests}))

{:main main :tests tests}
```

- [ ] **Step 2: Run the focused model test and verify it fails because the module is missing**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-result-model:main
```

Expected: FAIL with an `app-host.command-result-model` require/module-not-found error.

- [ ] **Step 3: Implement the result model**

Create `assets/lua/app-host/command-result-model.fnl` with pure helpers:

```fennel
(local max-value-length 500)

(fn command-label [command]
  (if command.title
      (tostring command.title)
      command.id
      (tostring command.id)
      "command"))

(fn sorted-table-keys [tbl]
  (local keys [])
  (each [k _v (pairs tbl)]
    (table.insert keys k))
  (table.sort keys (fn [a b] (< (tostring a) (tostring b))))
  keys)

(fn raw-value-text [value]
  (if (= value nil)
      nil
      (= (type value) :table)
      (do
        (local parts [])
        (each [_ key (ipairs (sorted-table-keys value))]
          (table.insert parts (.. (tostring key) "=" (tostring (. value key)))))
        (.. "{" (table.concat parts ", ") "}"))
      (tostring value)))

(fn truncate-value [text]
  (if (and text (> (# text) max-value-length))
      (.. (string.sub text 1 (- max-value-length 16)) "… [truncated]")
      text))

(fn value-text [value]
  (truncate-value (raw-value-text value)))

(fn summary [phase badge-text tone message command result]
  {:phase phase
   :badge-text badge-text
   :tone tone
   :message message
   :command-id (if command command.id nil)
   :result result})

(fn initial-summary []
  (summary :idle "Idle" :neutral "No command run yet" nil nil))

(fn confirmation-summary [command message]
  (summary :confirming "Confirm" :warning message command nil))

(fn running-summary [command]
  (summary :running "Running" :info (.. (command-label command) " is running…") command nil))

(fn result-summary [command result]
  (local label (command-label command))
  (if (= result.status :ok)
      (do
        (local rendered (value-text result.value))
        (summary :ok "Success" :success
                 (if rendered (.. label " succeeded: " rendered) (.. label " succeeded"))
                 command result))
      (= result.status :error)
      (summary :error "Error" :danger (.. label " failed: " (tostring result.error)) command result)
      (summary :unknown "Unknown" :warning (.. label " returned status " (tostring result.status)) command result)))

{:initial-summary initial-summary
 :confirmation-summary confirmation-summary
 :running-summary running-summary
 :result-summary result-summary
 :value-text value-text}
```

- [ ] **Step 4: Register the model test in `assets/lua/tests/fast.fnl`**

Add `:tests.test-app-host-command-result-model` near the other app-host tests or near `:tests.test-status-badge` if there is no existing app-host block. Do not remove existing modules.

- [ ] **Step 5: Validate Task 1**

Run:

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/command-result-model.fnl --file assets/lua/tests/test-app-host-command-result-model.fnl --file assets/lua/tests/fast.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-result-model:main
```

Expected: compile check passes, constraints pass, model tests pass.

- [ ] **Step 6: Commit Task 1**

```bash
git add assets/lua/app-host/command-result-model.fnl assets/lua/tests/test-app-host-command-result-model.fnl assets/lua/tests/fast.fnl
git commit -m "feat(lua): add hosted command result model"
```

Include validation evidence and constraint-impact note in the implementer report.

---

### Task 2: Workspace Command Controls Integration

**Files:**
- Modify: `assets/lua/app-host/workspace-command-controls.fnl`
- Modify: `assets/lua/tests/test-app-host-workspace-command-controls.fnl`
- Modify: `assets/lua/tests/fast.fnl` if Task 1 did not register `:tests.test-app-host-workspace-command-controls`

**Interfaces:**
- Consumes `ResultModel.initial-summary`, `ResultModel.confirmation-summary`, `ResultModel.running-summary`, and `ResultModel.result-summary` from Task 1.
- Preserves existing state fields: `snapshot`, `commands`, `buttons-by-id`, `button-labels-by-id`, `danger-levels-by-id`, `danger-badges-by-id`, `forms-by-id`, `confirming-command-id`, `last-result`, `result-message`, `run-command`.
- Produces new inspectable state fields: `busy?`, `active-command-id`, `result-summary`, and `result-badge`.

- [ ] **Step 1: Add failing command-control tests for result summaries**

Extend `assets/lua/tests/test-app-host-workspace-command-controls.fnl` with tests equivalent to:

```fennel
(fn test-initial_result_badge_and_message []
  (local fixture (make-descriptor))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  (assert (= state.result-summary.phase :idle))
  (assert (= state.result-message "No command run yet"))
  (assert (= state.result-badge.tone :neutral))
  (widget:drop))

(fn test-success_result_shows_badge_and_value []
  (local fixture (make-descriptor))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  ((. state.buttons-by-id :restart):on-click {:source :test})
  (assert (= state.result-summary.phase :ok))
  (assert (= state.result-badge.tone :success))
  (assert (string.find state.result-message "Restart" 1 true))
  (assert (string.find state.result-message "done" 1 true))
  (widget:drop))

(fn test-error_result_shows_danger_badge []
  (local fixture (make-descriptor))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  ((. state.buttons-by-id :explode):on-click {:source :test})
  (assert (= state.result-summary.phase :error))
  (assert (= state.result-badge.tone :danger))
  (assert (string.find state.result-message "boom" 1 true))
  (widget:drop))

(fn test-unknown_result_status_is_warning []
  (local fixture (make-descriptor {:commands [{:id :wait :title "Wait" :status :metadata}]
                                   :results {:wait {:id :wait :status :queued}}}))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  ((. state.buttons-by-id :wait):on-click {:source :test})
  (assert (= state.result-summary.phase :unknown))
  (assert (= state.result-badge.tone :warning))
  (assert (string.find state.result-message "queued" 1 true))
  (widget:drop))
```

- [ ] **Step 2: Add failing command-control tests for busy/reentrant behavior**

Add tests equivalent to:

```fennel
(fn test-busy_guard_ignores_reentrant_clicks []
  (var widget nil)
  (local fixture
    (make-descriptor
      {:commands [{:id :restart :title "Restart" :status :metadata}
                  {:id :explode :title "Explode" :status :metadata}]
       :run-command (fn [self command-id payload]
                      (set self.state.run-count (+ self.state.run-count 1))
                      (table.insert self.state.calls {:id command-id :payload payload})
                      (when (= command-id :restart)
                        ((. widget.__command-controls.buttons-by-id :explode):on-click {:source :reentrant}))
                      {:id command-id :status :ok :value "done"})}))
  (local context (test-context))
  (set widget (build-widget fixture.descriptor context.ctx))
  ((. widget.__command-controls.buttons-by-id :restart):on-click {:source :test})
  (assert (= fixture.state.run-count 1))
  (assert (= (# fixture.state.calls) 1))
  (assert (= (. fixture.state.calls 1 :id) :restart))
  (assert (= widget.__command-controls.busy? false))
  (widget:drop))

(fn test-structural_error_restores_previous_summary_and_buttons []
  (local fixture (make-descriptor {:run-command structural-failing-run-command}))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  (local previous-message state.result-message)
  (assert-error-contains #((. state.buttons-by-id :restart):on-click {:source :test}) "structural failure")
  (assert (= state.last-result nil))
  (assert (= state.result-message previous-message))
  (assert (= state.result-summary.phase :idle))
  (assert (= state.busy? false))
  (assert (= (. state.button-labels-by-id :restart) "Run"))
  (widget:drop))
```

Also update the existing confirmation and invalid payload tests to assert first confirmation clicks keep `state.busy?` false and do not change the result summary to `:running`.

- [ ] **Step 3: Run the focused command-control test and verify the new tests fail**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-command-controls:main
```

Expected: FAIL because `result-summary`, `result-badge`, success value text, and busy guards are not implemented yet.

- [ ] **Step 4: Integrate result summaries into the controls**

In `workspace-command-controls.fnl`:

- Add `(local ResultModel (require :app-host.command-result-model))`.
- Remove the old local `result-message` helper after callers move to `ResultModel.result-summary`.
- Initialize:

```fennel
(local initial-summary (ResultModel.initial-summary))
...
:busy? false
:active-command-id nil
:result-summary initial-summary
:result-message initial-summary.message
:result-badge nil
```

- Add an `apply-result-summary` helper that updates `state.result-summary`, `state.result-message`, `result-text`, and `state.result-badge`:

```fennel
(fn apply-result-summary [state summary]
  (set state.result-summary summary)
  (set state.result-message summary.message)
  (when state.result-badge
    (state.result-badge:set-text summary.badge-text)
    (state.result-badge:set-tone summary.tone))
  (when result-text
    (result-text:set-text summary.message))
  summary)
```

- Build the result area as a row containing one `StatusBadge` and one `WrappedText`. Store the badge in `state.result-badge`.

- [ ] **Step 5: Add button enable/label helpers**

Implement local helpers:

```fennel
(fn set-command-buttons-enabled [state enabled?]
  (each [_ button (pairs state.buttons-by-id)]
    (when button.set-enabled
      (button:set-enabled enabled?))))

(fn set-active-command [state command-id]
  (set state.active-command-id command-id))
```

Keep `restore-button-labels` and `set-button-label` behavior compatible with existing tests.

- [ ] **Step 6: Update confirmation click path**

When a first confirmation click arms a command:

```fennel
(local message (confirmation-message command confirmation))
(apply-result-summary state (ResultModel.confirmation-summary command message))
```

Do not call `form:build-payload`, do not set `busy?`, and do not call `descriptor:run-command` in this branch.

- [ ] **Step 7: Update execution click path with cleanup**

Keep payload construction before running-state transition. Then use protected cleanup around descriptor execution:

```fennel
(local previous-summary state.result-summary)
(local form (. state.forms-by-id command.id))
(local payload (if form (form:build-payload) nil))
(set state.confirming-command-id nil)
(restore-button-labels state)
(set state.busy? true)
(set-active-command state command.id)
(set-command-buttons-enabled state false)
(apply-result-summary state (ResultModel.running-summary command))
(local (ok result-or-error) (pcall #(descriptor:run-command command.id payload)))
(set-command-buttons-enabled state true)
(set state.busy? false)
(set-active-command state nil)
(restore-button-labels state)
(if ok
    (do
      (set state.last-result result-or-error)
      (apply-result-summary state (ResultModel.result-summary command result-or-error))
      result-or-error)
    (do
      (apply-result-summary state previous-summary)
      (error result-or-error)))
```

If implementation needs a more compact helper to avoid nesting, extract `run-descriptor-command` locally. Preserve structural thrown errors and keep `state.last-result` unchanged on thrown errors.

- [ ] **Step 8: Add a top-level busy guard**

Wrap the existing `run-command` body so the first branch returns without side
effects when busy, before confirmation or payload work:

```fennel
(fn run-command [command]
  (if state.busy?
      nil
      (do
        ;; existing confirmation and execution branches live here
        )))
```

The resulting behavior must be: no payload build, no confirmation change, no descriptor call while busy.

- [ ] **Step 9: Register command-control test in `fast.fnl` if missing**

If `:tests.test-app-host-workspace-command-controls` is absent from `assets/lua/tests/fast.fnl`, add it next to `:tests.test-app-host-command-result-model`.

- [ ] **Step 10: Validate Task 2**

Run:

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/workspace-command-controls.fnl --file assets/lua/tests/test-app-host-workspace-command-controls.fnl --file assets/lua/tests/fast.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-result-model:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-command-controls:main
```

Expected: compile check passes, constraints pass, result-model tests pass, command-control tests pass.

- [ ] **Step 11: Commit Task 2**

```bash
git add assets/lua/app-host/workspace-command-controls.fnl assets/lua/tests/test-app-host-workspace-command-controls.fnl assets/lua/tests/fast.fnl
git commit -m "feat(ui): show hosted command results"
```

Include validation evidence and constraint-impact note in the implementer report.

---

### Task 3: Documentation

**Files:**
- Modify: `docs/dev/features/hosted-runtime-apps.md`

**Interfaces:**
- Consumes implemented behavior from Tasks 1-2.
- Produces developer-facing docs for result badges/messages, bounded value rendering, synchronous busy protection, and deferred async scope.

- [ ] **Step 1: Update hosted runtime docs**

In `docs/dev/features/hosted-runtime-apps.md`, update the minimal workspace controls section so it states:

- command controls display the latest result with a status badge plus text;
- success envelopes render success tone and include a bounded textual value when `:value` is non-nil;
- handler error envelopes render danger/error tone and include `:error` text;
- unknown envelope statuses render as warning/unknown display state instead of crashing controls;
- command buttons are synchronously disabled/guarded while a command run is in progress;
- first-click confirmation still only arms confirmation and does not build payloads;
- async progress, cancellation, queues, polling, and pending command APIs remain deferred.

- [ ] **Step 2: Run docs-focused validation**

Run a focused search command such as:

```bash
rg -n "latest result|bounded|async progress|cancellation|queues|confirmation|run-command" docs/dev/features/hosted-runtime-apps.md
```

Expected: output contains the updated result/busy documentation and the existing deferred async boundary.

- [ ] **Step 3: Commit Task 3**

```bash
git add docs/dev/features/hosted-runtime-apps.md
git commit -m "docs: document hosted command result UX"
```

Include docs validation rationale and constraint-impact note in the implementer report.

---

### Task 4: Final Validation and Acceptance Evidence

**Files:**
- No implementation files should change.
- Create report only through the SDD task report path provided by the supervisor.

**Interfaces:**
- Consumes all code, tests, and docs from Tasks 1-3.
- Produces validation evidence for reviewer and finishing gates.

- [ ] **Step 1: Run compile check**

```bash
make fennel-check
```

Expected: pass.

- [ ] **Step 2: Run constraints**

```bash
make constraints
```

Expected: pass.

- [ ] **Step 3: Run focused tests**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-result-model:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-command-controls:main
```

Expected: both focused suites pass. Existing `space-http-lifecycle` / `space-http-client` shutdown traces after direct test processes are non-blocking only when tests pass and no new assertion/failure output appears.

- [ ] **Step 4: Run relevant fast-suite coverage**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
```

Expected: fast suite passes. If this command exposes unrelated-looking, flaky, timing-dependent, or environmental failures, do not mark the task done; capture the failure and escalate to systematic debugging through the supervisor.

- [ ] **Step 5: Verify acceptance criteria in the report**

The report must cite evidence that:

- initial result badge/message render;
- success values are visible and bounded;
- handler errors render danger/error results;
- unknown statuses render warning/unknown results;
- busy guard suppresses reentrant clicks;
- buttons re-enable and labels restore after returned results;
- structural thrown errors restore prior visible summary, preserve last result, re-enable buttons, restore labels, and rethrow;
- confirmation first-click still defers payload building;
- docs retain the deferred async boundary.

- [ ] **Step 6: Commit only if validation required repository changes**

If no repository files changed, do not create an empty commit. If validation exposed a repository fix, the supervisor must route that fix through a new implementer/reviewer loop before this task can pass.

---

## Validation Summary

Minimum per implementation task:

```bash
./build/space -m tools.fennel-check:main -- --target files --file <touched-fennel-file> [...]
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m <focused-test-module>:main
```

Final validation:

```bash
make fennel-check
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-result-model:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-command-controls:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
```

Do not run the system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
