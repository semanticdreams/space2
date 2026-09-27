# Hosted App Command Confirmations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add metadata-only danger levels and inline two-click confirmations for hosted app commands.

**Architecture:** Add a focused `app-host.command-metadata` helper as the single authority for command danger/confirmation validation and normalization, delegating existing payload-schema checks when present. Use that helper from snapshots, runner dispatch, and command controls so structural metadata failures are loud everywhere; implement inline confirmation entirely in `workspace-command-controls` while keeping actual execution routed through `descriptor:run-command(command-id, payload)`.

**Tech Stack:** Space Fennel, hosted app command snapshots/runner, classic HUD UI widgets (`Button`, `StatusBadge`, `WrappedText`, `Flex`, `Padding`), focused Fennel tests, `tools.fennel-check`, `make constraints`.

## Global Constraints

- Let command facets declare canonical `:danger-level` metadata.
- Let command facets declare optional `:confirmation` metadata.
- Propagate normalized danger/confirmation metadata through read-only inspector snapshots without executing commands.
- Validate command metadata before command-runner dispatch so malformed metadata fails as a structural integration error, not as a handler result envelope.
- Render danger state in hosted command controls with badges and button variants.
- Require an inline two-click confirmation for commands whose confirmation is required.
- Preserve existing payload form behavior and execute only through `descriptor:run-command(command-id, payload)`.
- Document the metadata contract and retained follow-up boundaries.
- No permissions, auth, or policy engine.
- No persistent approvals or “always allow” behavior.
- No modal/dialog framework for hosted command confirmations.
- No async progress, cancellation, or command queues.
- No app-specific command controls.
- No changes to command registry APIs.
- No changes to command handler success/error result envelope semantics.
- No danger-level aliases or compatibility shims.
- Valid `:danger-level` values are exactly `:normal`, `:warning`, and `:danger`.
- Omitted `:danger-level` normalizes to `:normal`.
- `:confirmation`, when present, must be a table.
- Supported confirmation keys are exactly `:message` and `:required?`.
- `:confirmation.message`, when present, must be a string.
- `:confirmation.required?`, when present, must be a boolean.
- Omitted `:confirmation.required?` normalizes to `true`.
- Danger level does not imply confirmation.
- Confirmation is controlled only by `:confirmation.required?`.
- All malformed metadata throws with prefix `[app-host.command-metadata]`.
- Snapshot reads must never call command handlers.
- Handler exceptions continue returning the existing `{:id command-id :status :error :error error-string}` envelopes.
- For schema-backed commands, payload construction happens only on the actual execution click.
- A first confirmation click must not validate number text or otherwise build payloads.
- Invalid payloads fail before execution on the second click and leave descriptor run count unchanged.
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

- `assets/lua/app-host/command-metadata.fnl`: new validator/normalizer for `:danger-level`, `:confirmation`, and existing `:payload-schema`.
- `assets/lua/app-host/workspace-inspector-snapshot.fnl`: include normalized danger/confirmation metadata in command entries.
- `assets/lua/app-host/command-runner.fnl`: validate command metadata before handler invocation.
- `assets/lua/tests/test-app-host-workspace-inspector-snapshot.fnl`: snapshot metadata, non-execution, and malformed metadata tests.
- `assets/lua/tests/test-app-host-command-runner.fnl`: runner structural metadata validation tests.
- `assets/lua/app-host/workspace-command-controls.fnl`: danger badge/button variants and inline two-click confirmation flow.
- `assets/lua/tests/test-app-host-workspace-command-controls.fnl`: UI danger/confirmation and payload deferral tests.
- `docs/dev/features/hosted-runtime-apps.md`: command facet metadata docs.
- `docs/dev/features/hosted-app-command-payload-forms.md`: confirmation/payload interaction docs.

---

### Task 1: Command Metadata Validation and Snapshot/Runner Propagation

**Files:**
- Create: `assets/lua/app-host/command-metadata.fnl`
- Modify: `assets/lua/app-host/workspace-inspector-snapshot.fnl`
- Modify: `assets/lua/app-host/command-runner.fnl`
- Modify: `assets/lua/tests/test-app-host-workspace-inspector-snapshot.fnl`
- Modify: `assets/lua/tests/test-app-host-command-runner.fnl`

**Interfaces:**
- Consumes: `PayloadSchema.validate-schema(schema, context) -> schema` from `app-host.command-payload-schema`.
- Produces: `Metadata.validate-command(command: table, context: table|nil) -> command`.
- Produces: `Metadata.danger-level(command: table) -> keyword`.
- Produces: `Metadata.confirmation(command: table) -> table|nil`.
- Produces: `Metadata.confirmation-required?(command: table) -> boolean`.

- [ ] **Step 1: Add failing snapshot tests for danger and confirmation metadata**

In `assets/lua/tests/test-app-host-workspace-inspector-snapshot.fnl`, add tests equivalent to:

```fennel
(fn test-command_danger_and_confirmation_are_metadata_only []
  (var ran? false)
  (local host (host-with {:commands [{:id :reset
                                      :title "Reset"
                                      :danger-level :danger
                                      :confirmation {:message "Reset game state?"}
                                      :run (fn []
                                             (set ran? true))}]}))
  (local snapshot (Snapshot.read-host host))
  (local command (. snapshot.commands 1))
  (assert (= command.id :reset))
  (assert (= command.danger-level :danger))
  (assert (= command.confirmation.message "Reset game state?"))
  (assert (= command.confirmation.required? true))
  (assert (= ran? false) "snapshot must not execute command handlers"))

(fn test-command_danger_defaults_to_normal []
  (local host (host-with {:commands [{:id :inspect :title "Inspect"}]}))
  (local snapshot (Snapshot.read-host host))
  (assert (= (. snapshot.commands 1 :danger-level) :normal)))

(fn test-invalid_command_metadata_fails_snapshot []
  (local host (host-with {:commands [{:id :bad :danger-level :catastrophic}]}))
  (assert-error-contains #(Snapshot.read-host host) "[app-host.command-metadata]")
  (assert-error-contains #(Snapshot.read-host host) "danger-level"))

(fn test-invalid_confirmation_shape_fails_snapshot []
  (local host (host-with {:commands [{:id :bad :confirmation {:required? "yes"}}]}))
  (assert-error-contains #(Snapshot.read-host host) "[app-host.command-metadata]")
  (assert-error-contains #(Snapshot.read-host host) "required?"))

(add-test "command danger and confirmation are metadata only" test-command_danger_and_confirmation_are_metadata_only)
(add-test "command danger defaults to normal" test-command_danger_defaults_to_normal)
(add-test "invalid command metadata fails snapshot" test-invalid_command_metadata_fails_snapshot)
(add-test "invalid confirmation shape fails snapshot" test-invalid_confirmation_shape_fails_snapshot)
```

Use the fixture helper names already present in the test file; keep the behavior and assertions equivalent.

- [ ] **Step 2: Add failing command-runner metadata tests**

In `assets/lua/tests/test-app-host-command-runner.fnl`, add:

```fennel
(fn test-runner_rejects_invalid_danger_metadata_before_handler []
  (var ran? false)
  (local host (host-with-commands [{:id :bad
                                    :danger-level :critical
                                    :run (fn [_self _payload]
                                           (set ran? true)
                                           true)}]))
  (assert-error-contains #(CommandRunner.run-host host :bad {}) "[app-host.command-metadata]")
  (assert (= ran? false) "invalid metadata must fail before handler invocation"))

(fn test-runner_rejects_invalid_confirmation_before_handler []
  (var ran? false)
  (local host (host-with-commands [{:id :bad
                                    :confirmation "confirm"
                                    :run (fn [_self _payload]
                                           (set ran? true)
                                           true)}]))
  (assert-error-contains #(CommandRunner.run-host host :bad {}) "[app-host.command-metadata]")
  (assert (= ran? false) "invalid confirmation must fail before handler invocation"))

(add-test "runner rejects invalid danger metadata before handler" test-runner_rejects_invalid_danger_metadata_before_handler)
(add-test "runner rejects invalid confirmation before handler" test-runner_rejects_invalid_confirmation_before_handler)
```

Run and expect failure because `app-host.command-metadata` does not exist and snapshots/runner do not validate this metadata yet:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-app-host-workspace-inspector-snapshot.fnl --file assets/lua/tests/test-app-host-command-runner.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-inspector-snapshot:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-runner:main
```

- [ ] **Step 3: Implement `command-metadata.fnl`**

Create `assets/lua/app-host/command-metadata.fnl` with this required behavior:

```fennel
(local PayloadSchema (require :app-host.command-payload-schema))

(local danger-levels {:normal true :warning true :danger true})

(fn metadata-error [message]
  (error (.. "[app-host.command-metadata] " message)))
```

Implement helpers:

- `validate-confirmation(conf, context)`:
  - returns nil when `conf` is nil;
  - requires table when non-nil;
  - rejects unknown keys other than `:message` and `:required?`;
  - validates `:message` as string when non-nil;
  - validates `:required?` as boolean when non-nil;
  - returns normalized table with `:required?` defaulting to true and optional `:message`.
- `danger-level(command)`:
  - returns `:normal` when `command.danger-level` is nil;
  - validates exact `:normal`, `:warning`, or `:danger`;
  - throws metadata error for any other value.
- `confirmation(command)` returns normalized confirmation or nil.
- `confirmation-required?(command)` returns true only when normalized confirmation exists and `required?` is true.
- `validate-command(command, context)`:
  - requires command table;
  - validates danger level;
  - validates confirmation;
  - when `command.payload-schema` is not nil, delegates to `PayloadSchema.validate-schema command.payload-schema context`;
  - returns command.

Export:

```fennel
{:validate-command validate-command
 :danger-level danger-level
 :confirmation confirmation
 :confirmation-required? confirmation-required?}
```

- [ ] **Step 4: Update snapshot command entries**

In `assets/lua/app-host/workspace-inspector-snapshot.fnl`:

- require `app-host.command-metadata`;
- in `command-entry`, call `Metadata.validate-command facet {:command-id facet.id}` before creating the returned entry;
- include `:danger-level (Metadata.danger-level facet)` in every command entry;
- include `:confirmation (Metadata.confirmation facet)` only when non-nil;
- preserve existing `:payload-schema` behavior;
- never call `facet.run`.

- [ ] **Step 5: Update command runner metadata validation**

In `assets/lua/app-host/command-runner.fnl`:

- require `app-host.command-metadata`;
- after finding the command and before checking/calling `command.run`, call `Metadata.validate-command command {:command-id command-id}`;
- remove duplicated direct payload-schema validation if command metadata now delegates to the payload schema helper;
- keep handler invocation and result envelope behavior unchanged.

- [ ] **Step 6: Validate and commit Task 1**

Run:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/command-metadata.fnl --file assets/lua/app-host/workspace-inspector-snapshot.fnl --file assets/lua/app-host/command-runner.fnl --file assets/lua/tests/test-app-host-workspace-inspector-snapshot.fnl --file assets/lua/tests/test-app-host-command-runner.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-inspector-snapshot:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-runner:main
```

Commit:

```bash
git add assets/lua/app-host/command-metadata.fnl assets/lua/app-host/workspace-inspector-snapshot.fnl assets/lua/app-host/command-runner.fnl assets/lua/tests/test-app-host-workspace-inspector-snapshot.fnl assets/lua/tests/test-app-host-command-runner.fnl
git commit -m "feat(lua): validate hosted command metadata"
```

---

### Task 2: Workspace Command Danger UI and Inline Confirmation

**Files:**
- Modify: `assets/lua/app-host/workspace-command-controls.fnl`
- Modify: `assets/lua/tests/test-app-host-workspace-command-controls.fnl`

**Interfaces:**
- Consumes: `Metadata.validate-command(command, context) -> command`.
- Consumes: `Metadata.danger-level(command) -> keyword`.
- Consumes: `Metadata.confirmation(command) -> table|nil`.
- Consumes: `Metadata.confirmation-required?(command) -> boolean`.
- Produces: `widget.__command-controls.confirming-command-id` state.
- Produces: test-visible command button variants and danger badge tone/text for command rows.

- [ ] **Step 1: Add failing danger UI tests**

In `assets/lua/tests/test-app-host-workspace-command-controls.fnl`, add or extend fixture commands and tests equivalent to:

```fennel
(fn test-danger_levels_update_badges_and_button_variants []
  (local fixture (make-descriptor {:commands [{:id :inspect :title "Inspect" :status :metadata :danger-level :normal}
                                               {:id :warn :title "Warn" :status :metadata :danger-level :warning}
                                               {:id :delete :title "Delete" :status :metadata :danger-level :danger}]}))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  (assert (= (. state.danger-levels-by-id :inspect) :normal))
  (assert (= (. state.danger-levels-by-id :warn) :warning))
  (assert (= (. state.danger-levels-by-id :delete) :danger))
  (assert (= (. state.buttons-by-id :warn :variant) :warning))
  (assert (= (. state.buttons-by-id :delete :variant) :danger))
  (widget:drop))

(add-test "danger levels update badges and button variants" test-danger_levels_update_badges_and_button_variants)
```

If `Button` does not currently expose `:variant`, the implementation should attach a test-visible `variant` field to command button widgets after build without changing click behavior.

- [ ] **Step 2: Add failing confirmation tests**

Add tests equivalent to:

```fennel
(fn test-required_confirmation_needs_second_click_to_run []
  (local fixture (make-descriptor {:commands [{:id :reset
                                               :title "Reset"
                                               :status :metadata
                                               :danger-level :danger
                                               :confirmation {:message "Reset game state?"}}]}))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  (local button (. state.buttons-by-id :reset))
  (button:on-click {:source :test})
  (assert (= fixture.state.run-count 0) "first click must not run command")
  (assert (= state.confirming-command-id :reset))
  (assert (string.find state.result-message "Reset game state?" 1 true))
  (assert (string.find (button.text:get-text) "Confirm" 1 true))
  (button:on-click {:source :test})
  (assert (= fixture.state.run-count 1) "second click should run command")
  (assert (= state.confirming-command-id nil))
  (widget:drop))

(fn test-confirmation_required_false_runs_immediately []
  (local fixture (make-descriptor {:commands [{:id :safe-reset
                                               :title "Safe Reset"
                                               :status :metadata
                                               :confirmation {:message "No prompt" :required? false}}]}))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  ((. widget.__command-controls.buttons-by-id :safe-reset):on-click {:source :test})
  (assert (= fixture.state.run-count 1))
  (assert (= widget.__command-controls.confirming-command-id nil))
  (widget:drop))

(add-test "required confirmation needs second click to run" test-required_confirmation_needs_second_click_to_run)
(add-test "confirmation required false runs immediately" test-confirmation_required_false_runs_immediately)
```

If `button.text:get-text` is unavailable, assert equivalent test-visible state such as `state.button-labels-by-id[command-id]`.

- [ ] **Step 3: Add failing payload deferral test**

Add a schema-backed command with required confirmation and invalid number input. The first click must arm confirmation without error and without execution. The second click must throw `number field` and leave run count zero:

```fennel
(fn test-confirmation_defers_payload_validation_until_execute_click []
  (local schema {:fields [{:id :count :type :number :label "Count"}]})
  (local fixture (make-descriptor {:commands [{:id :configure
                                               :title "Configure"
                                               :status :metadata
                                               :payload-schema schema
                                               :confirmation {:message "Apply config?"}}]}))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  (local form (. state.forms-by-id :configure))
  ((. form.inputs-by-id :count):set-text "not-a-number")
  ((. state.buttons-by-id :configure):on-click {:source :test})
  (assert (= fixture.state.run-count 0))
  (assert (= state.confirming-command-id :configure))
  (assert-error-contains #((. state.buttons-by-id :configure):on-click {:source :test}) "number field")
  (assert (= fixture.state.run-count 0))
  (widget:drop))

(add-test "confirmation defers payload validation until execute click" test-confirmation_defers_payload_validation_until_execute_click)
```

Run and expect failures because danger UI and confirmation flow are not implemented:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-app-host-workspace-command-controls.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-command-controls:main
```

- [ ] **Step 4: Implement danger helpers in command controls**

In `assets/lua/app-host/workspace-command-controls.fnl`:

- require `app-host.command-metadata`;
- replace direct payload-schema command validation with `Metadata.validate-command command {:command-id command.id}`;
- add helpers:

```fennel
(fn danger-tone [level]
  (if (= level :warning) :warning
      (= level :danger) :danger
      :neutral))

(fn danger-button-variant [level]
  (if (= level :warning) :warning
      (= level :danger) :danger
      nil))

(fn command-label [command]
  (tostring (or command.title command.id "command")))

(fn confirmation-message [command confirmation]
  (or (and confirmation confirmation.message)
      (.. "Confirm run for " (command-label command) "?")))
```

Store `:danger-levels-by-id {}`, `:danger-badges-by-id {}`, `:button-labels-by-id {}`, and `:confirming-command-id nil` in `state`.

- [ ] **Step 5: Render danger badge and button variant**

For each command row:

- compute `level` with `Metadata.danger-level command`;
- store `state.danger-levels-by-id[command.id]`;
- render `StatusBadge {:text (tostring level) :tone (danger-tone level)}`;
- build Run button with `:variant (danger-button-variant level)`;
- after building the button, set `button.variant` to the variant for test visibility;
- store badge and button in state maps.

- [ ] **Step 6: Implement inline confirmation flow**

Modify `state.run-command` or the button click handler so:

- when `Metadata.confirmation-required? command` and `state.confirming-command-id` is not the command id:
  - clear the previously armed command button label, if any;
  - set `state.confirming-command-id` to `command.id`;
  - set `state.result-message` to the confirmation message;
  - update visible result text;
  - set this command button label to `Confirm` using `button.text:set-text` when present;
  - set `state.button-labels-by-id[command.id]` to `"Confirm"`;
  - return nil without building payload and without calling `descriptor:run-command`.
- when executing a command:
  - clear confirmation state;
  - restore all command button labels to `"Run"`;
  - build payload only at this point;
  - call `descriptor:run-command command.id payload`;
  - preserve existing success/error result-message behavior;
  - return the command result.
- when clicking a different non-confirming command, clear prior confirmation labels before execution.

Do not catch structural errors from metadata validation, payload construction, or `descriptor:run-command`.

- [ ] **Step 7: Validate and commit Task 2**

Run:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/workspace-command-controls.fnl --file assets/lua/tests/test-app-host-workspace-command-controls.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-command-controls:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-inspector-snapshot:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-runner:main
```

Commit:

```bash
git add assets/lua/app-host/workspace-command-controls.fnl assets/lua/tests/test-app-host-workspace-command-controls.fnl
git commit -m "feat(ui): confirm dangerous hosted commands"
```

---

### Task 3: Hosted Command Metadata Documentation

**Files:**
- Modify: `docs/dev/features/hosted-runtime-apps.md`
- Modify: `docs/dev/features/hosted-app-command-payload-forms.md`

**Interfaces:**
- Consumes: implemented metadata shape and UI behavior from Tasks 1 and 2.
- Produces: developer documentation for danger levels, confirmations, payload interaction, and out-of-scope boundaries.

- [ ] **Step 1: Update hosted runtime command facet docs**

In `docs/dev/features/hosted-runtime-apps.md`, add a command metadata example equivalent to:

```fennel
{:id :reset
 :title "Reset"
 :description "Reset game state"
 :danger-level :danger
 :confirmation {:message "Reset game state?" :required? true}
 :run run-reset}
```

Document:

- `:danger-level` values are `:normal`, `:warning`, `:danger`;
- omitted danger level defaults to `:normal`;
- `:confirmation` supports only `:message` and `:required?`;
- omitted `:confirmation.required?` defaults to true;
- danger level does not imply confirmation;
- malformed metadata fails loudly with `[app-host.command-metadata]`.

- [ ] **Step 2: Document UI behavior**

In the same hosted runtime docs, state:

- warning/danger commands render matching badge tones and button variants;
- confirmations are inline, not modal;
- first click arms confirmation and changes label to `Confirm`;
- second click runs the command;
- execution still uses `descriptor/session:run-command(command-id, payload)`;
- command handler errors remain result envelopes.

- [ ] **Step 3: Update payload form docs**

In `docs/dev/features/hosted-app-command-payload-forms.md`, add a short section stating:

- when a command has required confirmation, the first click does not build payloads;
- payload construction and payload validation happen only on the actual execution click;
- invalid payloads fail before command execution;
- confirmations do not add permissions/auth/persistent approval behavior.

- [ ] **Step 4: Run docs-focused checks**

Run:

```bash
rg "confirmation|danger-level|permissions|modal|persistent" docs/dev/features/hosted-runtime-apps.md docs/dev/features/hosted-app-command-payload-forms.md
```

Verify the matches do not claim a modal, permission system, persistent approval, or changed execution path.

- [ ] **Step 5: Commit Task 3 docs**

Commit:

```bash
git add docs/dev/features/hosted-runtime-apps.md docs/dev/features/hosted-app-command-payload-forms.md
git commit -m "docs: document hosted command danger metadata"
```

---

### Task 4: Final Validation and Acceptance Evidence

**Files:**
- Validate: `assets/lua/app-host/command-metadata.fnl`
- Validate: `assets/lua/app-host/workspace-inspector-snapshot.fnl`
- Validate: `assets/lua/app-host/command-runner.fnl`
- Validate: `assets/lua/app-host/workspace-command-controls.fnl`
- Validate: `assets/lua/tests/test-app-host-workspace-inspector-snapshot.fnl`
- Validate: `assets/lua/tests/test-app-host-command-runner.fnl`
- Validate: `assets/lua/tests/test-app-host-workspace-command-controls.fnl`
- Validate: `docs/dev/features/hosted-runtime-apps.md`
- Validate: `docs/dev/features/hosted-app-command-payload-forms.md`

**Interfaces:**
- Consumes: completed Tasks 1 through 3.
- Produces: final local validation and acceptance evidence for finishing.

- [ ] **Step 1: Run final compile check**

Run:

```bash
make fennel-check
```

- [ ] **Step 2: Run constraints**

Run:

```bash
make constraints
```

- [ ] **Step 3: Run focused app-host tests**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-inspector-snapshot:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-runner:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-command-controls:main
```

- [ ] **Step 4: Confirm acceptance criteria**

Report evidence that:

- snapshots normalize metadata and do not execute commands;
- invalid metadata fails loudly;
- command handler failures remain result envelopes;
- warning/danger UI variants are observable in tests;
- confirmations are inline and two-click;
- payload validation waits until actual execution click;
- docs match behavior and scope.

- [ ] **Step 5: Leave implementation commits unchanged**

Task 4 is validation-only. If no files change, do not create an empty commit. If validation exposes a repository issue, stop and route the fix through an implementer/reviewer fix loop.
