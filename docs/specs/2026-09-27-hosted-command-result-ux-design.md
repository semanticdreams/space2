# Hosted Command Result UX Design

## Context

Hosted app command controls can render command metadata, payload forms, and inline
confirmations. Running a command currently calls
`descriptor/session:run-command(command-id, payload)` synchronously and writes a
single latest result string such as `<command> succeeded` or `<command> failed:
<error>`. That is enough for plumbing, but not production-quality feedback:
successful command values are invisible, error state is text-only, and repeated
clicks are not guarded by a clear running state.

The command runner contract is intentionally small and should remain stable for
this slice: handler success returns `{:id command-id :status :ok :value value}`;
handler exceptions return `{:id command-id :status :error :error error-string}`;
structural host, registry, metadata, lookup, and payload validation failures
throw loudly before a handler result envelope is produced.

## Goals

- Render latest command results with an explicit status badge and readable text.
- Include bounded success values when command handlers return useful values.
- Show handler error envelopes as danger/error results without changing envelope
  semantics.
- Add synchronous busy/reentrant protection so accidental double-runs are
  suppressed while a command execution is in progress.
- Preserve payload form and inline confirmation timing: the first confirmation
  click must not build payloads or run handlers; payload construction happens
  only on the actual execution click.
- Keep the design open for future async/pending command states without adding
  async progress, cancellation, queues, or command registry API changes now.
- Document the updated result and busy behavior.

## Non-Goals

- No async command API, pending handles, polling, progress bars, cancellation, or
  command queues.
- No permissions/auth policy, persistent approvals, or “always allow” behavior.
- No app-specific command controls.
- No command registry API changes.
- No rich object inspector for command return values beyond deterministic bounded
  text rendering.
- No change to handler result-envelope semantics or structural-error behavior.

## Approaches Considered

### 1. Inline synchronous UI state only

The smallest change would add busy flags, badge updates, and result formatting
directly inside `workspace-command-controls.fnl`. This is fast, but it further
entangles confirmation state, payload forms, result formatting, button state, and
future status phases in one widget module.

### 2. Command result model helper (chosen)

Add a small pure helper that converts command/result state into a display
summary. `workspace-command-controls.fnl` remains responsible for widget
ownership and click orchestration, while the helper owns status phases, badge
tone/text, messages, and bounded value formatting. This keeps the current
synchronous execution contract, reduces UI coupling, and gives future async work
a natural place to add `:pending` or run-id backed summaries.

### 3. Full async command execution API

Introduce pending command handles, callbacks, cancellation, and progress updates
now. This would be a larger architecture project touching command registries,
runtime host contracts, lifecycle, error reporting, and tests. It is the right
future direction for long-running commands, but it is too broad for this slice.

## Design

### Command result model

Create `app-host.command-result-model` as a pure Fennel module with no widget,
descriptor, registry, or host dependencies. It produces display summaries with a
stable shape:

```fennel
{:phase :idle|:confirming|:running|:ok|:error|:unknown
 :badge-text "Idle"
 :tone :neutral|:info|:success|:warning|:danger
 :message "No command run yet"
 :command-id command-id-or-nil
 :result result-or-nil}
```

Initial, confirmation, running, and result summaries are derived from the command
label and result envelope. Success summaries use `:success` tone and include a
bounded rendering of `result.value` when it is non-nil. Error summaries use
`:danger` tone and include `result.error`. Unknown result statuses use
`:warning` tone and state the unexpected status without throwing, because an
unknown envelope status is display data rather than a structural integration
failure.

Value rendering must be deterministic and bounded to 500 characters. Scalars use
`tostring`; tables use a stable shallow representation sufficient for compact UI
feedback; long rendered values are truncated with an explicit ellipsis marker.
This intentionally avoids adding a rich object viewer while making successful
command output visible.

### Workspace command controls

`workspace-command-controls.fnl` will consume the result model and replace the
single text-only result area with a `StatusBadge` plus `WrappedText`. The widget
keeps its existing public factory shape and debug/test state, while adding
inspectable state for the active summary, result badge, busy flag, and active
command id.

Click flow remains synchronous:

1. If `state.busy?` is true, ignore the click and do not build payloads, change
   confirmation state, or call `descriptor:run-command`.
2. If confirmation is required and the command is not already armed, update the
   summary to the confirmation message, change that button label to `Confirm`,
   and return without building payloads.
3. On the actual execution click, clear confirmation state, restore labels,
   build payload from the command form if present, then enter running state.
4. While running, disable all command buttons through existing button APIs, set a
   running summary, and call `descriptor:run-command(command.id, payload)`.
5. On a returned result envelope, store `state.last-result`, apply the result
   summary, restore labels, clear busy state, and re-enable buttons.
6. On a structural thrown error from payload building, descriptor dispatch, or
   metadata/contract validation, clear busy state if it was set, re-enable
   buttons, restore labels and the previous visible summary, leave
   `state.last-result` unchanged, and rethrow.

Payload construction intentionally happens before entering running state so
invalid local payloads do not flash as a running command. Reentrant direct test
calls are still suppressed by the explicit `state.busy?` guard even if they
bypass button event unregistration.

### Documentation

Update `docs/dev/features/hosted-runtime-apps.md` to describe the latest-result
badge, bounded success value rendering, handler error display, synchronous busy
protection, and the fact that async progress/cancellation/queues remain deferred
follow-up work.

## Error Handling

- Handler exceptions remain normal command result envelopes and render as danger
  summaries.
- Structural failures still throw loudly and are not converted into result
  envelopes.
- Structural failures during command-control clicks must leave the last result
  intact and restore the previous visible summary so failed dispatch setup does
  not present a false command result.
- Unknown result statuses are rendered as warning summaries rather than thrown,
  because the result area should remain robust against future envelope phases.

## Testing

- Add focused unit tests for the pure result model: idle, confirmation, running,
  ok with nil/scalar/table values, bounded long values, error, and unknown
  status.
- Extend command-control tests for result badge/message rendering, success value
  display, handler error display, unknown status display, busy disabling,
  reentrant click suppression, confirmation first-click preservation, payload
  deferral, invalid payload behavior, and structural-error cleanup.
- Run Space Fennel validation in order: `make fennel-check`, `make constraints`,
  then focused Fennel tests. Broaden only if the implementation expands into C++,
  runtime bootstrap, bindings, or other high-risk surfaces.

## Acceptance Criteria

- Command controls show an initial neutral result badge and message.
- Successful command envelopes update the badge to success and display the
  command label plus bounded returned value when present.
- Handler error envelopes update the badge to danger and display the error text.
- Unknown result envelope statuses update the badge to warning and do not crash
  the controls.
- While a command is running synchronously, command buttons are disabled and
  direct reentrant clicks do not call handlers or build payloads.
- After success or handler error envelope return, buttons are re-enabled and
  labels are restored.
- Structural thrown errors restore the previous visible summary, leave
  `state.last-result` unchanged, re-enable buttons, restore labels, and rethrow.
- Required confirmation remains inline/two-click and first-click confirmation
  does not build payloads.
- Documentation reflects the behavior and retains the deferred async boundary.
