# Hosted App Command Controls Design

## Context

Hosted workspace panels now have a generic command execution surface:
`session:run-command` and descriptor `run-command` delegate to
`app-host.command-runner`, while inspector snapshots expose command metadata
without executing commands. The current workspace panel HUD child is still a
non-visual descriptor widget. This slice makes hosted app commands visible and
clickable without introducing schemas, permissions, async protocols, or
app-specific command UI.

## Goals

- Render generic hosted app command controls in the workspace panel HUD child.
- Read command metadata from `descriptor:read-inspector-snapshot()`.
- Preserve snapshot behavior: reading metadata must not execute commands.
- Invoke commands through the existing `descriptor:run-command(command-id, nil)`
  surface.
- Display the latest command success/error result in the panel and keep it in
  inspectable widget state for focused tests and future UI integration.
- Preserve existing workspace panel descriptor/session API and mount teardown
  behavior.
- Follow Space Fennel UI ownership and lifecycle rules.

## Non-goals

- No payload schemas or argument editor widgets.
- No permissions, confirmations, destructive-command policy, or auth UX.
- No async progress, cancellation, command queues, or persistent command history.
- No app-specific command rendering or Snake-specific controls.
- No full hosted inspector/dashboard framework.
- No graph/editor/launcher integration.
- No changes to `workspace-inspector-snapshot` execution semantics.
- No changes to `command-runner` result envelope semantics.

## Approach

Add a dedicated visual widget module:

```fennel
(local Controls (require :app-host.workspace-command-controls))
(Controls.WorkspaceCommandControls {:descriptor descriptor})
```

The widget builder reads one snapshot during build, stores the command metadata
rows, renders a row per command, and creates a Run button for each row. Button
clicks call `descriptor:run-command(command.id, nil)`. Successful result
envelopes update state with a success message. Handler error result envelopes
update state with an error message. Structural `run-command` exceptions are not
caught; they remain loud programmer/integration errors.

`workspace-panel.fnl` remains responsible for mounting, descriptor/session
construction, and close/drop ownership. Its HUD descriptor builder should build
the new command-controls widget instead of the current zero-size placeholder.
The built widget still exposes `:hosted-app-workspace-panel descriptor` so
existing descriptor tests and future consumers remain compatible.

## Rejected alternatives

### Inline controls directly in `workspace-panel.fnl`

This minimizes file count but mixes mounting/session lifecycle, descriptor
construction, UI composition, button state, and result display in one module.
The UI behavior is easier to test and evolve as a focused widget module.

### Add command schemas or action framework now

Schemas, confirmations, permissions, and async progress are likely useful later,
but command metadata currently has only id/title/description/status. A larger
action framework would force product and API decisions that are unnecessary for
generic zero-payload buttons.

### Build a full hosted inspector dashboard first

A dashboard could eventually combine inspector data, commands, forms, history,
and graph/editor hooks. This slice should prove the smallest visual/control path
and leave dashboard structure for a future spec.

## Widget interface

New file: `assets/lua/app-host/workspace-command-controls.fnl`.

Export:

```fennel
{:WorkspaceCommandControls WorkspaceCommandControls}
```

Constructor:

```fennel
(WorkspaceCommandControls {:descriptor descriptor}) ; -> build closure
```

The constructor requires `opts.descriptor` and should fail loudly when missing.
The build closure receives a normal Space UI context. Because it uses `Button`,
the context must provide `ctx.clickables` and `ctx.hoverables`; missing required
context should fail loudly through existing widget behavior rather than silently
falling back.

The built widget exposes:

- `:layout` — owned layout for the controls root.
- `:drop` — drops direct child widgets and unregisters button handlers through
  normal child teardown.
- `:hosted-app-workspace-panel` — original descriptor for compatibility.
- `:__command-controls` — inspectable test/future-integration state:
  - `:snapshot` — snapshot returned by `descriptor:read-inspector-snapshot()`;
  - `:commands` — command metadata rows from the snapshot;
  - `:buttons-by-id` — command id to Run button widget;
  - `:last-result` — latest command result envelope or nil;
  - `:result-message` — latest visible result text;
  - `:run-command` — helper that invokes a command row and updates result state.

## Rendering behavior

Each command row should show:

- title, falling back to command id text;
- optional description;
- metadata status, initially `:metadata` from snapshots;
- a Run button.

The first slice can use existing primitives such as `Flex`, `FlexChild`,
`Padding`, `WrappedText`, `StatusBadge`, and `Button`. Exact visual polish is less
important than clear layout ownership, visible command rows, and robust testable
state.

## Command execution behavior

Clicking a Run button:

1. calls `descriptor:run-command(command.id, nil)`;
2. stores the returned envelope in `state.last-result`;
3. updates `state.result-message`;
4. updates visible result text.

Expected messages:

- success envelope (`:status :ok`): message includes the command id/title and a
  success word such as “succeeded”;
- handler error envelope (`:status :error`): message includes the command
  id/title, “failed”, and the error string;
- structural exceptions from `run-command`: propagate loudly and do not convert
  to result messages.

The button passes `nil` payload because command metadata has no schema yet.
Payload forms are a separate future slice.

## Workspace panel integration

`assets/lua/app-host/workspace-panel.fnl` should keep the public session fields
and descriptor fields unchanged:

- session: `mount`, `pause`, `resume`, `step`, `read-inspector-snapshot`,
  `run-command`, `close`;
- descriptor: `kind`, `mount`, `controller`, `session`,
  `read-inspector-snapshot`, `run-command`, `builder`.

Only the descriptor builder changes: it should build `WorkspaceCommandControls`
with the descriptor and return the resulting widget.

## Testing strategy

Add focused widget tests for `workspace-command-controls`:

- building reads command metadata and does not run commands;
- command ids map to Run buttons;
- clicking success command calls `run-command(command-id, nil)` and updates
  `last-result`/`result-message`;
- clicking error-envelope command updates error state/message;
- structural `run-command` exceptions propagate;
- `drop` unregisters owned button click/hover handlers.

Extend workspace panel tests:

- builder HUD test supplies UI context with clickables/hoverables stubs;
- built widget exposes `.__command-controls` and command buttons;
- opening/building visual controls still does not execute commands;
- existing session/descriptor `read-inspector-snapshot`, `run-command`, close,
  and HUD failure behavior still pass.

Validation order for implementation:

1. touched-file `tools.fennel-check` or `make fennel-check`;
2. `make constraints`;
3. focused widget/panel tests;
4. adjacent command-runner and inspector snapshot tests when integration risk
   warrants them;
5. broader local suite only if reviewer/risk/failures require it.

## Documentation

Update `docs/dev/features/hosted-runtime-apps.md` to say workspace panels now
render generic command metadata rows with Run buttons. Document that buttons call
`run-command(command-id, nil)`, latest result/error is visible in the panel, and
snapshot reads remain non-executing. Keep payload schemas, confirmations,
permissions, async progress/cancellation, app-specific controls, editor/graph
integration, discovery, and launcher UX as follow-up work.

## Acceptance criteria

- Hosted workspace panel HUD builder returns a visible command-controls widget
  with a layout.
- Building visual controls reads snapshot command metadata and does not execute
  commands.
- Each command row has a Run button keyed by command id.
- Clicking a Run button invokes `descriptor:run-command(command-id, nil)`.
- Success and error envelopes update visible/in-state latest result messaging.
- Structural command execution failures remain loud.
- Widget teardown unregisters owned button handlers through child teardown.
- Existing workspace panel descriptor/session APIs remain compatible.
- No payload/schema/permission/async/app-specific/dashboard framework is added.
