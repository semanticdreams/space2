# Hosted App Command Surface Design

## Context

Hosted workspace panels now expose read-only inspector snapshots. Those snapshots
include command metadata but intentionally do not execute commands. The next
increment is a small, generic command execution surface so a workspace session can
invoke app-provided commands without adding app-specific methods or a full action
framework.

Runtime controllers already register app command facets into `host.commands`.
Existing tests use command facets shaped like `{:id id :run fn}`. The host
registry remains a generic item registry with `register`, `unregister`, `list`,
and `clear`; it should not gain command-specific lookup behavior in this slice.

## Goals

- Add a first generic hosted app command execution surface.
- Preserve existing workspace panel session API and add exactly one command
  method: `run-command`.
- Execute commands from `host.commands:list()` by command id.
- Keep inspector snapshots metadata-only; snapshot reads must not execute
  commands.
- Return explicit result envelopes for command handler success/failure.
- Fail loudly for structural host/registry/command contract errors.
- Preserve workspace panel mount ownership and teardown behavior.
- Document the command execution contract and follow-up boundaries.

## Non-goals

- Do not add visual command buttons or editor widgets.
- Do not add command schemas, permissions, confirmation prompts, async progress,
  cancellation, or multi-value result protocols.
- Do not add command-specific methods to generic registries.
- Do not redesign runtime-controller command registration.
- Do not add app-specific command APIs or Snake-specific commands.
- Do not add aliases such as `execute-command`.

## Recommended approach

Add a focused `app-host.command-runner` helper with:

```fennel
(CommandRunner.run-host host command-id payload)
```

The helper validates `host.commands:list()`, finds exactly one command facet with
matching `:id`, validates that the facet has a `:run` function, and invokes it.
`WorkspacePanel.open` then exposes this helper through the session and descriptor
as `run-command`.

This approach was chosen over two alternatives:

- Adding lookup methods to every generic registry would couple command semantics
  to registries that are intentionally plain item stores.
- Building a full action bus with schemas, async state, permissions, and UI would
  overbuild before multiple hosted apps prove those needs.

## Command result contract

Successful handlers return:

```fennel
{:id command-id
 :status :ok
 :value first-return-value}
```

Handlers that raise return:

```fennel
{:id command-id
 :status :error
 :error error-string}
```

Structural contract problems throw `[app-host.command-runner]` errors:

- missing host table;
- missing `host.commands` registry;
- missing `commands:list`;
- nil command id;
- command id not found;
- duplicate command id;
- matching command without a function `:run`.

The command handler should be invoked as `(run-fn command payload)` so a command
facet can use itself as state. Only the first return value is captured in
`:value`; richer result protocols are follow-up work.

## Workspace panel integration

`WorkspacePanel.open(opts)` should preserve the existing session fields and
methods:

- `mount`;
- `pause`;
- `resume`;
- `step`;
- `read-inspector-snapshot`;
- `close`.

It should add:

```fennel
(session:run-command command-id payload)
(descriptor:run-command command-id payload)
```

The descriptor stored on built widgets should expose the same method so future UI
controls can call through the existing descriptor path. Command execution should
use `mount.host`, not controller internals.

## Error handling

- Command lookup/contract failures throw loudly with the command runner prefix.
- Command handler exceptions are caught and returned as `:status :error` result
  envelopes so a workspace panel can display the failure without tearing down the
  panel.
- Workspace panel close/drop semantics remain unchanged.

## Testing strategy

Add focused command runner tests for:

- successful command execution and payload passing;
- only the matching command runs;
- handler exceptions become explicit error results;
- missing/unknown/duplicate/non-runnable command contract failures throw loudly.

Extend workspace panel tests for:

- `session:run-command`;
- descriptor and built widget descriptor `run-command`;
- throwing commands returning error envelopes;
- snapshots still listing command metadata without executing commands;
- existing pause/resume/step/close/HUD failure behavior remaining intact.

Validation should use Space-native Fennel commands: compile check, constraints,
focused command runner and workspace panel tests, plus adjacent hosted app tests
when integration risk requires it.

## Acceptance criteria

- Hosted workspace sessions can run a uniquely identified command by id.
- Command success and handler failure use explicit result envelopes.
- Structural command lookup/contract errors fail loudly.
- Snapshot command metadata remains side-effect free.
- Existing workspace panel controls and teardown behavior remain intact.
- No registry redesign, app-specific API, visual button UI, schema protocol, or
  async command framework is introduced.

## Follow-up

Future slices can add visual command buttons, argument schemas, confirmation UX,
permissions, async progress/cancellation, richer result displays, editor
integration, graph integration, launcher/app discovery, and app-specific
moldable actions.
