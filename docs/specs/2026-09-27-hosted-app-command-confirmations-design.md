# Hosted App Command Confirmations Design

## Context

Hosted app command controls now render command rows, optional payload forms, and
Run buttons. Commands can already be powerful because payload forms let users
send structured input. The next safety layer is metadata-only danger levels and
inline confirmations for risky commands, without changing the command registry,
command runner result envelopes, or adding a permission/auth system.

## Goals

- Let command facets declare canonical `:danger-level` metadata.
- Let command facets declare optional `:confirmation` metadata.
- Propagate normalized danger/confirmation metadata through read-only inspector
  snapshots without executing commands.
- Validate command metadata before command-runner dispatch so malformed metadata
  fails as a structural integration error, not as a handler result envelope.
- Render danger state in hosted command controls with badges and button variants.
- Require an inline two-click confirmation for commands whose confirmation is
  required.
- Preserve existing payload form behavior and execute only through
  `descriptor:run-command(command-id, payload)`.
- Document the metadata contract and retained follow-up boundaries.

## Non-goals

- No permissions, auth, or policy engine.
- No persistent approvals or “always allow” behavior.
- No modal/dialog framework for hosted command confirmations.
- No async progress, cancellation, or command queues.
- No app-specific command controls.
- No changes to command registry APIs.
- No changes to command handler success/error result envelope semantics.
- No danger-level aliases or compatibility shims.

## Metadata contract

Command facets may include:

```fennel
{:id :reset
 :title "Reset"
 :description "Reset game state"
 :danger-level :danger
 :confirmation {:message "Reset game state?" :required? true}
 :run run-reset}
```

Rules:

- valid `:danger-level` values are exactly `:normal`, `:warning`, and `:danger`;
- omitted `:danger-level` normalizes to `:normal`;
- `:confirmation`, when present, must be a table;
- supported confirmation keys are exactly `:message` and `:required?`;
- `:confirmation.message`, when present, must be a string;
- `:confirmation.required?`, when present, must be a boolean;
- omitted `:confirmation.required?` normalizes to `true`;
- danger level does not imply confirmation;
- confirmation is controlled only by `:confirmation.required?`.

All malformed metadata throws with prefix `[app-host.command-metadata]`.

## Command metadata helper

Add `assets/lua/app-host/command-metadata.fnl` as the single authority for
command metadata validation and normalization. It should expose:

- `validate-command(command, context) -> command`;
- `danger-level(command) -> keyword`;
- `confirmation(command) -> table|nil`;
- `confirmation-required?(command) -> boolean`.

`validate-command` also delegates to `app-host.command-payload-schema` when
`command.payload-schema` is present so runner, snapshot, and controls use one
command-level structural validation path.

## Snapshot behavior

`workspace-inspector-snapshot` remains metadata-only. Command entries include
existing fields plus normalized metadata:

- `:danger-level` is always present, defaulting to `:normal`;
- `:confirmation` is present only when the command declares it, normalized to the
  supported shape;
- `:payload-schema` remains present only when declared and valid.

Snapshot reads must never call command handlers.

## Runner behavior

`command-runner` validates metadata for the selected command before checking and
calling `:run`. Metadata failures throw with `[app-host.command-metadata]` before
handler invocation. Handler exceptions continue returning the existing
`{:status :error :error ...}` envelopes.

## UI behavior

Hosted command controls use normalized metadata from snapshot rows:

- `:normal` displays a neutral badge and default Run button;
- `:warning` displays warning badge tone and warning button variant;
- `:danger` displays danger badge tone and danger button variant.

For commands with required confirmation:

1. first click arms only that command;
2. first click updates result text with the confirmation message;
3. first click changes that command’s button label to `Confirm`;
4. first click does not build payload and does not call `run-command`;
5. second click on the same command clears confirmation state, restores the
   button label, builds payload, and calls `descriptor:run-command`;
6. clicking a different command clears any previously armed command before
   arming/running the new command;
7. commands with `{:confirmation {:required? false}}` run immediately.

Fallback confirmation message is `Confirm run for <label>?`, where label is the
command title or id text. Structural errors still propagate loudly.

## Payload interaction

For schema-backed commands, payload construction happens only on the actual
execution click. A first confirmation click must not validate number text or
otherwise build payloads. Invalid payloads fail before execution on the second
click and leave descriptor run count unchanged.

## Testing strategy

Add/extend focused tests for:

- snapshot normalization of danger level and confirmation metadata;
- snapshot non-execution with confirmation metadata;
- snapshot and runner loud failures for invalid danger/confirmation metadata;
- warning/danger button variants and danger badge state in command controls;
- omitted danger level behaving as `:normal`;
- required confirmation first click arming without execution;
- second click executing through `descriptor:run-command`;
- `:required? false` confirmation running immediately;
- payload construction deferred until actual execution click;
- existing handler error envelopes and structural error propagation.

Validation order remains Space-native Fennel compile check, constraints, focused
app-host tests, and broader validation only if risk or failures require it.

## Documentation

Update hosted runtime docs and payload form docs. Documentation should cover the
metadata shape, validation rules, inline two-click behavior, payload interaction,
and out-of-scope boundaries: permissions/auth, persistent approvals,
async/cancel, modal framework, app-specific controls.

## Acceptance criteria

- Snapshots include normalized danger metadata and optional normalized
  confirmation without executing commands.
- Invalid danger/confirmation metadata fails loudly with
  `[app-host.command-metadata]`.
- Command runner validates metadata before handler invocation.
- Handler failures remain result envelopes.
- Warning/danger rows expose matching badge/button variants.
- Required confirmations are inline and two-click.
- First confirmation click does not build payload or run commands.
- Confirmation-disabled commands run immediately.
- Docs match behavior and do not imply permissions, modals, or persistent
  approvals.
