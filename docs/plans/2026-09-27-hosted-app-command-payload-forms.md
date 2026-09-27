# Hosted App Command Payload Forms Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optional scalar payload schemas and classic HUD form controls for hosted app commands.

**Architecture:** Introduce a focused `app-host.command-payload-schema` helper as the single authority for schema validation, defaults, display, and payload coercion. Propagate validated `:payload-schema` metadata through read-only inspector snapshots, render forms in `workspace-command-controls` through a dedicated `workspace-command-payload-form` widget, and keep all command execution routed through `descriptor:run-command(command-id, payload)`.

**Tech Stack:** Space Fennel, app-host command runner/snapshots, classic HUD widgets (`Input`, `Button`, `Flex`, `Padding`, `WrappedText`), focused Fennel tests, `tools.fennel-check`, `make constraints`.

## Global Constraints

- Let command facets optionally declare a canonical `:payload-schema`.
- Preserve no-schema compatibility: commands without `:payload-schema` still run with nil payload from visual controls.
- Propagate validated payload schemas through read-only inspector snapshots.
- Render simple classic HUD form controls in hosted command rows.
- Construct flat payload tables keyed by field id and pass them to `descriptor:run-command(command-id, payload)`.
- Fail loudly for malformed schemas and form payload construction errors.
- Keep command handler errors on the existing result-envelope path.
- Document the schema contract and retained follow-up boundaries.
- No JSON Schema subset or external schema language.
- No nested objects, arrays, repeated fields, computed fields, or validation DSL.
- No required/optional validation beyond type/default/select membership checks.
- No async progress, cancellation, command queues, or command history.
- No permissions, confirmations, danger levels, auth, or destructive-command UX.
- No app-specific command UI.
- No dropdown/select framework; select uses a simple cycling button.
- No persistent form state across panel rebuilds or app restarts.
- No changes to `command-runner` result envelope semantics for handler errors.
- `:payload-schema` is the only canonical schema key; no aliases are added.
- Schema is a table with ordered `:fields` list.
- Each field is a table with non-nil `:id` and supported `:type`.
- Field ids must be unique.
- Supported types are exactly `:string`, `:number`, `:boolean`, and `:select`.
- `:label` is optional display text.
- `:default` is optional and must match the field type.
- `:select` requires non-empty `:options`.
- Select options are tables with non-nil scalar `:value` and optional `:label`.
- Select default, when present, must match one option value.
- No nested schema shape is accepted.
- All structural schema failures should throw with prefix `[app-host.command-payload-schema]`.
- Schema failures are structural integration errors and must throw; they must not be converted into handler error envelopes.
- Snapshot reads must remain read-only and non-executing.
- Use classic HUD widgets only; do not depend on next-app direct widgets.
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

- `assets/lua/app-host/command-payload-schema.fnl`: schema validation, default/display helpers, and payload coercion.
- `assets/lua/app-host/command-runner.fnl`: validate declared schema before command handler invocation.
- `assets/lua/tests/test-app-host-command-runner.fnl`: schema validation coverage at runner dispatch.
- `assets/lua/app-host/workspace-inspector-snapshot.fnl`: include validated `:payload-schema` in command metadata entries.
- `assets/lua/tests/test-app-host-workspace-inspector-snapshot.fnl`: schema propagation and non-execution tests.
- `assets/lua/app-host/workspace-command-payload-form.fnl`: classic HUD form widget for scalar command payload fields.
- `assets/lua/app-host/workspace-command-controls.fnl`: build forms for schema-backed commands and pass constructed payloads on Run.
- `assets/lua/tests/test-app-host-workspace-command-controls.fnl`: form rendering, payload construction, no-schema compatibility, and payload error tests.
- `docs/dev/features/hosted-app-command-payload-forms.md`: canonical feature docs.
- `docs/dev/features/index.md`: link the new docs page.

---

### Task 1: Payload Schema Helper and Runner Checks

**Files:**
- Create: `assets/lua/app-host/command-payload-schema.fnl`
- Modify: `assets/lua/app-host/command-runner.fnl`
- Modify: `assets/lua/tests/test-app-host-command-runner.fnl`

**Interfaces:**
- Produces: `Schema.validate-schema(schema, context) -> schema`.
- Produces: `Schema.default-value(field) -> value`.
- Produces: `Schema.display-value(field, value) -> string`.
- Produces: `Schema.payload-from-values(schema, values, context) -> table`.
- Consumes existing command facets with optional `command.payload-schema`.
- Produces runner behavior: validate `command.payload-schema` before validating/calling `command.run`; schema failures throw with `[app-host.command-payload-schema]` and are not caught as handler error envelopes.

- [ ] **Step 1: Add command-runner schema tests**

In `assets/lua/tests/test-app-host-command-runner.fnl`, add:

```fennel
(fn test-valid_payload_schema_preserves_payload_dispatch []
  (var received-payload nil)
  (local host (host-with-commands [{:id :configure
                                    :payload-schema {:fields [{:id :name :type :string}]}
                                    :run (fn [_self payload]
                                           (set received-payload payload)
                                           {:ok? true :name payload.name})}]))
  (local result (CommandRunner.run-host host :configure {:name "Ada"}))
  (assert (= result.status :ok))
  (assert (= result.value.name "Ada"))
  (assert (= received-payload.name "Ada")))

(fn test-malformed_payload_schema_is_structural_error []
  (local host (host-with-commands [{:id :bad
                                    :payload-schema {:fields [{:id :payload :type :object}]}
                                    :run (fn [_self _payload]
                                           (error "handler must not run"))}]))
  (assert-error-contains #(CommandRunner.run-host host :bad {}) "[app-host.command-payload-schema]")
  (assert-error-contains #(CommandRunner.run-host host :bad {}) "unsupported field type"))

(add-test "valid payload schema preserves payload dispatch" test-valid_payload_schema_preserves_payload_dispatch)
(add-test "malformed payload schema is structural error" test-malformed_payload_schema_is_structural_error)
```

Run and expect failure because `command-payload-schema` does not exist and runner does not validate schemas yet:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-app-host-command-runner.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-runner:main
```

- [ ] **Step 2: Implement `command-payload-schema.fnl`**

Create `assets/lua/app-host/command-payload-schema.fnl` with these required functions and behavior:

```fennel
(local supported-types {:string true :number true :boolean true :select true})

(fn schema-error [message]
  (error (.. "[app-host.command-payload-schema] " message)))

(fn scalar? [value]
  (local t (type value))
  (or (= t :string) (= t :number) (= t :boolean) (= t :nil)))
```

Implement:

- `validate-schema(schema, context)`:
  - requires schema table;
  - requires `schema.fields` table;
  - requires every field to be a table;
  - requires non-nil `field.id`;
  - rejects duplicate field ids;
  - requires `field.type` in `supported-types`;
  - validates default type when present;
  - for `:select`, requires non-empty `field.options`, every option table has non-nil scalar `:value`, optional `:label`, and default matches an option when default is present;
  - returns schema.
- `default-value(field)`:
  - string default or `""`;
  - number default converted to string for input display, or `""`;
  - boolean default or `false`;
  - select default or first option value.
- `display-value(field, value)`:
  - select values use matching option label when present, otherwise `tostring value`;
  - boolean returns `"true"` or `"false"`;
  - other values use `tostring` with nil as `""`.
- `payload-from-values(schema, values, context)`:
  - validates schema first;
  - string uses current text or `""`;
  - number uses `tonumber` and throws `number field <id> requires numeric value` when conversion fails;
  - boolean requires actual boolean;
  - select requires membership in declared options;
  - returns flat payload table keyed by field id.

Export:

```fennel
{:validate-schema validate-schema
 :default-value default-value
 :display-value display-value
 :payload-from-values payload-from-values}
```

- [ ] **Step 3: Wire schema validation into command runner**

In `assets/lua/app-host/command-runner.fnl`:

- add `(local Schema (require :app-host.command-payload-schema))`;
- after `find-command` and before reading/calling `command.run`, add:

```fennel
(when command.payload-schema
  (Schema.validate-schema command.payload-schema {:command-id command-id}))
```

Do not wrap schema validation in `pcall`; structural schema failures must throw.

- [ ] **Step 4: Validate and commit Task 1**

Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/command-payload-schema.fnl --file assets/lua/app-host/command-runner.fnl --file assets/lua/tests/test-app-host-command-runner.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-runner:main
```

Commit:

```bash
git add assets/lua/app-host/command-payload-schema.fnl assets/lua/app-host/command-runner.fnl assets/lua/tests/test-app-host-command-runner.fnl
git commit -m "feat(lua): validate hosted command payload schemas"
```

---

### Task 2: Inspector Snapshot Schema Propagation

**Files:**
- Modify: `assets/lua/app-host/workspace-inspector-snapshot.fnl`
- Modify: `assets/lua/tests/test-app-host-workspace-inspector-snapshot.fnl`

**Interfaces:**
- Consumes: `Schema.validate-schema(schema, context) -> schema` from Task 1.
- Produces: snapshot command entries include optional `:payload-schema` when a command facet declares it.

- [ ] **Step 1: Add snapshot schema propagation tests**

In `assets/lua/tests/test-app-host-workspace-inspector-snapshot.fnl`, add a test like:

```fennel
(fn test-command_payload_schema_is_metadata_only []
  (var ran? false)
  (local schema {:fields [{:id :title :type :string :label "Title"}]})
  (local host (host-with {:commands [{:id :configure
                                      :title "Configure"
                                      :payload-schema schema
                                      :run (fn []
                                             (set ran? true))}]}))
  (local snapshot (Snapshot.read-host host))
  (assert (= (. snapshot.commands 1 :id) :configure))
  (assert (= (. snapshot.commands 1 :payload-schema) schema))
  (assert (= ran? false) "snapshot must not execute command handlers"))

(fn test-malformed_command_payload_schema_fails_snapshot []
  (local host (host-with {:commands [{:id :bad
                                      :payload-schema {:fields [{:id :value :type :object}]}}]}))
  (assert-error-contains #(Snapshot.read-host host) "[app-host.command-payload-schema]")
  (assert-error-contains #(Snapshot.read-host host) "unsupported field type"))

(add-test "command payload schema is metadata only" test-command_payload_schema_is_metadata_only)
(add-test "malformed command payload schema fails snapshot" test-malformed_command_payload_schema_fails_snapshot)
```

Use existing helper names if this test file uses different local fixture helpers; keep the assertions and schema shape exactly equivalent.

Run and expect failure because snapshots currently strip `:payload-schema`:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-app-host-workspace-inspector-snapshot.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-inspector-snapshot:main
```

- [ ] **Step 2: Update snapshot command entries**

In `assets/lua/app-host/workspace-inspector-snapshot.fnl`:

- require `app-host.command-payload-schema`;
- keep existing command metadata fields exactly as they are;
- in `command-entry`, build the entry table first;
- when `facet.payload-schema` is not nil, validate it with `Schema.validate-schema facet.payload-schema {:command-id facet.id}` and set `entry.payload-schema` to the original schema;
- do not call `facet.run`.

- [ ] **Step 3: Validate and commit Task 2**

Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/workspace-inspector-snapshot.fnl --file assets/lua/tests/test-app-host-workspace-inspector-snapshot.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-inspector-snapshot:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-runner:main
```

Commit:

```bash
git add assets/lua/app-host/workspace-inspector-snapshot.fnl assets/lua/tests/test-app-host-workspace-inspector-snapshot.fnl
git commit -m "feat(lua): expose hosted command payload schemas in snapshots"
```

---

### Task 3: Classic HUD Command Payload Form UI

**Files:**
- Create: `assets/lua/app-host/workspace-command-payload-form.fnl`
- Modify: `assets/lua/app-host/workspace-command-controls.fnl`
- Modify: `assets/lua/tests/test-app-host-workspace-command-controls.fnl`

**Interfaces:**
- Consumes: snapshot command entries with optional `command.payload-schema`.
- Consumes: `Schema.validate-schema`, `Schema.default-value`, `Schema.display-value`, and `Schema.payload-from-values` from Task 1.
- Produces: `PayloadForm.CommandPayloadForm({:command command}) -> build(ctx) -> form-widget`.
- Produces: `form-widget:build-payload() -> table`.
- Produces: `form-widget.inputs-by-id[field-id]` for `:string` and `:number` fields.
- Produces: `form-widget.buttons-by-id[field-id]` for `:boolean` and `:select` fields.
- Produces: `form-widget.values-by-id[field-id]` for button-backed field state.
- Produces: `widget.__command-controls.forms-by-id[command.id]`.

- [ ] **Step 1: Add schema form payload test**

In `assets/lua/tests/test-app-host-workspace-command-controls.fnl`, add a command fixture with this schema:

```fennel
(local configure-schema
  {:fields [{:id :title :type :string :label "Title" :default "draft"}
            {:id :count :type :number :label "Count" :default 2}
            {:id :enabled :type :boolean :label "Enabled" :default false}
            {:id :mode :type :select :label "Mode"
             :options [{:value :fast :label "Fast"}
                       {:value :safe :label "Safe"}]}]})
```

Add a test equivalent to:

```fennel
(fn test-schema_form_builds_payload_for_command []
  (local fixture (make-descriptor {:commands [{:id :configure
                                               :title "Configure"
                                               :status :metadata
                                               :payload-schema configure-schema}]
                                  :results {:configure {:id :configure :status :ok :value {:configured? true}}}}))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local state widget.__command-controls)
  (local form (. state.forms-by-id :configure))
  (assert form "schema command should build a payload form")
  ((. form.inputs-by-id :title):set-text "launch")
  ((. form.inputs-by-id :count):set-text "3.5")
  ((. form.buttons-by-id :enabled):on-click {:source :test})
  ((. form.buttons-by-id :mode):on-click {:source :test})
  ((. state.buttons-by-id :configure):on-click {:source :test})
  (local call (. fixture.state.calls 1))
  (assert (= call.id :configure))
  (assert (= call.payload.title "launch"))
  (assert (= call.payload.count 3.5))
  (assert (= call.payload.enabled true))
  (assert (= call.payload.mode :safe))
  (widget:drop))

(add-test "schema form builds payload for command" test-schema_form_builds_payload_for_command)
```

Adjust helper fixture shape to match the current test file, but keep the behavior and assertions equivalent.

- [ ] **Step 2: Add compatibility and payload error tests**

Add or update tests so they assert:

```fennel
(assert (= (. fixture.state.calls 1 :payload) nil) "no-schema command should still pass nil payload")
```

Add invalid number coverage:

```fennel
(fn test-invalid_number_payload_fails_before_command_run []
  (local fixture (make-descriptor {:commands [{:id :configure
                                               :title "Configure"
                                               :status :metadata
                                               :payload-schema configure-schema}]}))
  (local context (test-context))
  (local widget (build-widget fixture.descriptor context.ctx))
  (local form (. widget.__command-controls.forms-by-id :configure))
  ((. form.inputs-by-id :count):set-text "not-a-number")
  (assert-error-contains #((. widget.__command-controls.buttons-by-id :configure):on-click {:source :test}) "number field")
  (assert (= fixture.state.run-count 0) "invalid payload must fail before descriptor run-command")
  (widget:drop))

(add-test "invalid number payload fails before command run" test-invalid_number_payload_fails_before_command_run)
```

Add malformed schema build coverage:

```fennel
(fn test-malformed_payload_schema_fails_control_build []
  (local fixture (make-descriptor {:commands [{:id :bad
                                               :title "Bad"
                                               :status :metadata
                                               :payload-schema {:fields [{:id :x :type :object}]}}]}))
  (local context (test-context))
  (assert-error-contains #(build-widget fixture.descriptor context.ctx) "[app-host.command-payload-schema]"))

(add-test "malformed payload schema fails control build" test-malformed_payload_schema_fails_control_build)
```

Run and expect failure because the form module/control integration does not exist yet:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-app-host-workspace-command-controls.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-command-controls:main
```

- [ ] **Step 3: Implement `workspace-command-payload-form.fnl`**

Create `assets/lua/app-host/workspace-command-payload-form.fnl`:

- require `Input`, `Button`, `WrappedText`, `Flex`, `FlexChild`, `Padding`, and `app-host.command-payload-schema`;
- `CommandPayloadForm(opts)` requires `opts.command`;
- build validates `command.payload-schema`;
- render each field as label text plus control;
- string/number fields use `Input` initialized with `Schema.default-value`;
- boolean fields use `Button`; click toggles `values-by-id[field.id]`, updates button text with `Schema.display-value`, and returns the new value;
- select fields use `Button`; click cycles to the next option value, updates button text with `Schema.display-value`, and returns the new value;
- `build-payload` gathers text values from inputs and button-backed values from `values-by-id`, then calls `Schema.payload-from-values`;
- return widget exposes `layout`, `drop`, `inputs-by-id`, `buttons-by-id`, `values-by-id`, and `build-payload`;
- `drop` drops the direct root widget exactly once.

- [ ] **Step 4: Integrate forms into command controls**

In `assets/lua/app-host/workspace-command-controls.fnl`:

- require `app-host.workspace-command-payload-form`;
- add `:forms-by-id {}` to `state`;
- when a command row has `command.payload-schema`, build `CommandPayloadForm {:command command}`, store the built form in `state.forms-by-id[command.id]`, and include it below the existing command header row;
- in `state.run-command`, compute payload as `(if form (form:build-payload) nil)` before calling `descriptor:run-command`;
- do not catch schema/payload errors;
- keep success/error result message behavior unchanged.

- [ ] **Step 5: Validate and commit Task 3**

Run:

```bash
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/workspace-command-payload-form.fnl --file assets/lua/app-host/workspace-command-controls.fnl --file assets/lua/tests/test-app-host-workspace-command-controls.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-command-controls:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-runner:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-inspector-snapshot:main
```

Commit:

```bash
git add assets/lua/app-host/workspace-command-payload-form.fnl assets/lua/app-host/workspace-command-controls.fnl assets/lua/tests/test-app-host-workspace-command-controls.fnl
git commit -m "feat(lua): render hosted command payload forms"
```

---

### Task 4: Documentation and Final Validation

**Files:**
- Create: `docs/dev/features/hosted-app-command-payload-forms.md`
- Modify: `docs/dev/features/index.md`

**Interfaces:**
- Consumes: implemented schema key `:payload-schema` and UI behavior from Tasks 1-3.
- Produces: canonical developer documentation for hosted app command payload forms.

- [ ] **Step 1: Create feature docs**

Create `docs/dev/features/hosted-app-command-payload-forms.md` with content equivalent to:

````markdown
# Hosted App Command Payload Forms

Hosted app command facets may declare an optional `:payload-schema` so workspace panels can render simple payload forms before calling `run-command`.

## Schema shape

```fennel
{:payload-schema
 {:fields [{:id :title :type :string :label "Title" :default "draft"}
           {:id :count :type :number :label "Count" :default 2}
           {:id :enabled :type :boolean :label "Enabled" :default false}
           {:id :mode :type :select :label "Mode"
            :options [{:value :fast :label "Fast"}
                      {:value :safe :label "Safe"}]}]}}
```

## Field types

- `:string`: classic text input; payload value is text.
- `:number`: classic text input; payload value is `tonumber` output and invalid text fails before command execution.
- `:boolean`: button-backed toggle; payload value is boolean.
- `:select`: button-backed option cycler; payload value is the selected option value.

## Execution

Commands without `:payload-schema` still run with nil payload from visual controls. Commands with schemas build flat payload tables keyed by field id and execute through `descriptor/session:run-command(command-id, payload)`.

## Errors

Malformed schemas fail loudly with `[app-host.command-payload-schema]` during snapshot reads, widget builds, and command runner dispatch. Command handler exceptions still use the existing command-runner error result envelope.

## Out of scope

Nested objects, arrays, validation DSLs, async progress/cancellation, permissions, confirmations, persistent form state, app-specific controls, and dropdown framework work are future slices.
````

- [ ] **Step 2: Link docs from the feature index**

Modify `docs/dev/features/index.md` to add a bullet/link named `Hosted App Command Payload Forms` pointing to `hosted-app-command-payload-forms.md`. Follow the existing index formatting exactly.

- [ ] **Step 3: Run final validation**

Run:

```bash
rg "inputSchema|payloadSchema|:schema" assets/lua/app-host docs/dev/features/hosted-app-command-payload-forms.md || true
make fennel-check
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-runner:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-inspector-snapshot:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-command-controls:main
```

If the `rg` command finds aliases introduced by this work, remove those aliases. If it only finds unrelated pre-existing text outside this feature's contract, report that evidence.

- [ ] **Step 4: Confirm acceptance criteria**

Report evidence for each item:

- no-schema commands still call `run-command(command-id, nil)`;
- snapshots include valid schema metadata and remain non-executing;
- malformed schemas fail with `[app-host.command-payload-schema]`;
- forms support string, number, boolean, and select;
- select uses a cycling button;
- invalid number text fails before command execution;
- payloads are flat/coerced tables keyed by field id;
- controls execute only through `descriptor:run-command`;
- widget teardown still unregisters child handlers;
- docs page exists and is linked.

- [ ] **Step 5: Commit docs**

Commit only docs changes for this task:

```bash
git add docs/dev/features/hosted-app-command-payload-forms.md docs/dev/features/index.md
git commit -m "docs(lua): document hosted command payload forms"
```
