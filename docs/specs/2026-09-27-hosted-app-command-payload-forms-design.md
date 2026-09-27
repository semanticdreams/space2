# Hosted App Command Payload Forms Design

## Context

Hosted workspace panels now render generic command metadata rows with Run
buttons. Those buttons call `descriptor:run-command(command-id, nil)`, so every
visual command is currently zero-argument. The underlying command runner already
accepts an arbitrary payload and passes it to the command facet's `:run` handler.
This slice adds a small optional schema contract so hosted app commands can
request simple scalar payloads without introducing a full action framework.

## Goals

- Let command facets optionally declare a canonical `:payload-schema`.
- Preserve no-schema compatibility: commands without `:payload-schema` still run
  with nil payload from visual controls.
- Propagate validated payload schemas through read-only inspector snapshots.
- Render simple classic HUD form controls in hosted command rows.
- Construct flat payload tables keyed by field id and pass them to
  `descriptor:run-command(command-id, payload)`.
- Fail loudly for malformed schemas and form payload construction errors.
- Keep command handler errors on the existing result-envelope path.
- Document the schema contract and retained follow-up boundaries.

## Non-goals

- No JSON Schema subset or external schema language.
- No nested objects, arrays, repeated fields, computed fields, or validation DSL.
- No required/optional validation beyond type/default/select membership checks.
- No async progress, cancellation, command queues, or command history.
- No permissions, confirmations, danger levels, auth, or destructive-command UX.
- No app-specific command UI.
- No dropdown/select framework; select uses a simple cycling button.
- No persistent form state across panel rebuilds or app restarts.
- No changes to `command-runner` result envelope semantics for handler errors.

## Schema contract

Command facets may include:

```fennel
{:id :configure
 :title "Configure"
 :payload-schema
 {:fields [{:id :title :type :string :label "Title" :default "draft"}
           {:id :count :type :number :label "Count" :default 2}
           {:id :enabled :type :boolean :label "Enabled" :default false}
           {:id :mode :type :select :label "Mode"
            :options [{:value :fast :label "Fast"}
                      {:value :safe :label "Safe"}]}]}
 :run run-fn}
```

Rules:

- `:payload-schema` is the only canonical schema key; no aliases are added.
- schema is a table with ordered `:fields` list;
- each field is a table with non-nil `:id` and supported `:type`;
- field ids must be unique;
- supported types are exactly `:string`, `:number`, `:boolean`, and `:select`;
- `:label` is optional display text;
- `:default` is optional and must match the field type;
- `:select` requires non-empty `:options`;
- select options are tables with non-nil scalar `:value` and optional `:label`;
- select default, when present, must match one option value;
- no nested schema shape is accepted.

Default values:

- string: `""` unless `:default` is provided;
- number: text initialized from default when provided, otherwise `""`;
- boolean: `false` unless `:default` is provided;
- select: explicit default when provided, otherwise the first option value.

## Schema validation helper

Add `assets/lua/app-host/command-payload-schema.fnl` as the single schema
authority. It should expose helpers such as:

- `validate-schema(schema, context) -> schema`;
- `default-value(field) -> value`;
- `display-value(field, value) -> string`;
- `payload-from-values(schema, values, context) -> table`.

All structural schema failures should throw with prefix
`[app-host.command-payload-schema]`. This includes unsupported field types,
duplicate ids, malformed select options, invalid defaults, and invalid field
values during payload construction.

The command runner should validate a command facet's schema before invoking the
handler. Schema failures are structural integration errors and must throw; they
must not be converted into handler error envelopes. Handler exceptions keep the
existing `{:status :error :error ...}` envelope behavior.

## Snapshot propagation

`workspace-inspector-snapshot` should continue to execute no commands. Command
metadata rows should still include `:id`, `:title`, `:description`, and
`:status :metadata`. When a command facet declares `:payload-schema`, the
snapshot helper validates it and includes it in the command metadata row. A
malformed schema makes the snapshot read fail loudly with the schema prefix.

This keeps visual forms driven by snapshot metadata while preserving the
snapshot's read-only/non-executing guarantee.

## Form UI

Add a focused classic HUD form module:

```fennel
(local PayloadForm (require :app-host.workspace-command-payload-form))
(PayloadForm.CommandPayloadForm {:command command}) ; -> build closure
```

The form consumes a snapshot command metadata row with optional
`:payload-schema`. It should use classic HUD widgets only:

- `Input` for string fields;
- `Input` for number fields, with conversion via `tonumber` during payload
  construction;
- `Button` for boolean fields, toggling true/false and updating button text;
- `Button` for select fields, cycling through options and updating button text.

No dropdown framework is introduced in this slice.

The built form exposes test/future-integration state:

- `inputs-by-id` for string/number field widgets;
- `buttons-by-id` for boolean/select field widgets;
- `values-by-id` for button-backed values;
- `build-payload()` to return the coerced flat payload table.

Payload construction errors, such as invalid number text or invalid select
state, throw with the schema prefix before `descriptor:run-command` is called.

## Command controls integration

`workspace-command-controls` should keep no-schema commands on the current path:
Run button click passes nil payload. For commands with a payload schema, controls
build a form under the command row, store it in `state.forms-by-id[command.id]`,
and call `form:build-payload()` before execution.

Execution remains:

```fennel
(descriptor:run-command command.id payload)
```

Result-message behavior remains unchanged for success and handler error
envelopes. Structural schema or payload errors propagate loudly and do not update
the latest command result.

## Error handling

- Malformed schema in command runner dispatch: throw schema-prefixed error before
  command handler invocation.
- Malformed schema in snapshot read: throw schema-prefixed error; do not call
  command handlers.
- Malformed schema in visual controls/form build: throw schema-prefixed error.
- Invalid form payload at button click: throw schema-prefixed error before
  command execution and leave descriptor run count unchanged.
- Command handler exceptions: preserve existing error result envelope behavior.

## Testing strategy

Add/extend focused tests for:

- command runner validates schema but still passes valid payload through;
- command runner throws schema-prefixed structural errors for malformed schemas;
- snapshots include valid `:payload-schema` metadata without executing commands;
- snapshots throw for malformed schemas;
- command controls build forms for string/number/boolean/select fields;
- controls pass coerced flat payloads to `run-command`;
- no-schema commands still pass nil payload;
- invalid number text throws before command execution;
- malformed schemas fail during control/form build;
- widget teardown still unregisters child handlers.

Validation order:

1. `make fennel-check` or touched-file `tools.fennel-check`;
2. `make constraints`;
3. focused app-host tests for command runner, inspector snapshot, and workspace
   command controls;
4. broader local validation only if risk, reviewer, or failures require it.

## Documentation

Create `docs/dev/features/hosted-app-command-payload-forms.md` and link it from
`docs/dev/features/index.md`. The page should document the exact schema shape,
supported field types, defaults, select cycling behavior, payload construction,
nil-payload compatibility, structural error behavior, and out-of-scope items.

## Acceptance criteria

- Commands without `:payload-schema` still call
  `descriptor:run-command(command-id, nil)`.
- Snapshot command entries include validated `:payload-schema` metadata when
  declared and never execute command handlers.
- Malformed schemas fail loudly with `[app-host.command-payload-schema]` during
  snapshot/widget build and command runner dispatch.
- Form UI supports string, number, boolean, and select fields using classic HUD
  widgets.
- Select fields cycle through declared options with a button.
- Number parse failures throw before command execution.
- Payloads are flat tables keyed by field id and contain coerced scalar values.
- Command controls route all execution through
  `descriptor:run-command(command.id, payload)`.
- Widget teardown continues to unregister child button/input handlers.
- Documentation exists and is linked from the feature index.
