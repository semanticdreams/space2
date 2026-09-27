# Hosted Async Command Progress Design

## Context

Hosted app commands now support metadata, payload forms, inline confirmations,
latest-result rendering, and synchronous busy protection. The current execution
contract is intentionally simple: command facets expose `:run`,
`CommandRunner.run-host` calls that handler synchronously, handler success returns
`{:id command-id :status :ok :value value}`, handler exceptions return
`{:id command-id :status :error :error error-string}`, and structural host,
registry, lookup, metadata, descriptor, and payload failures throw loudly.

That sync-only contract is still valuable and must remain stable, but hosted apps
need a clean way to run longer work without freezing command controls or forcing
each app to invent progress/cancellation plumbing. Existing Space patterns point
to callback-based async handles: MCP tools use `call-async` with `on-result` and
`cancelled?`; agent turns expose `cancel`, `running?`, and status; runtime timers
and subscriptions return cancellable/drop handles. This slice brings the same
style to hosted app commands.

## Goals

- Add an explicit opt-in async command contract for hosted command facets.
- Preserve existing synchronous `:run`, `CommandRunner.run-host`,
  `session:run-command`, and UI behavior for sync commands.
- Let async commands publish progress messages and terminal success/error/cancel
  results through callbacks.
- Let users cancel the active async command from workspace command controls.
- Ensure widget/session teardown drops or cancels pending async work and ignores
  late callbacks.
- Keep the first slice bounded: one active command per command-controls widget,
  no command queue, no persistent jobs, no polling API, no auth/policy layer.

## Non-Goals

- No command queues or multiple concurrent workspace command runs.
- No persistent/background jobs beyond the lifetime of the workspace/session or
  controls widget.
- No polling API, durable run ids, job storage, or recovery after reload.
- No auth, permission prompts, approvals, or policy decisions.
- No payload-schema expansion beyond the existing flat forms.
- No app-specific custom command controls.
- No port of `next-app/progress-widget` into the classic HUD stack.
- No C++ engine or binding changes.

## Approaches Considered

### 1. Overload `command.run` return values with pending handles

`command.run` could return either a normal value or `{:pending true ...}`. This
keeps one handler key but creates ambiguous app return values, complicates the
existing success envelope, and makes backward compatibility fragile. A command
that legitimately returns `{:pending true}` would become special accidentally.

### 2. Add explicit `:run-async` with callbacks and handles (chosen)

Async support is opt-in through a canonical `:run-async` facet key. The sync
handler remains unchanged. A new runner entrypoint invokes `:run-async` with
callbacks for progress, resolve, reject, and cancellation checks, and returns a
cancellable invocation handle. This is explicit, testable, aligned with existing
MCP/agent patterns, and leaves room for future job registries without forcing one
now.

### 3. Add a persistent host job registry and polling API now

A host-level job registry could support durable run ids, queues, recovery, and
external polling. That is likely useful later, but it is too broad for this
slice. It would require lifecycle, storage, authorization, queue policy, and API
decisions that are not needed for immediate hosted UI progress/cancel behavior.

## Design

### Command facet contract

Async command facets may provide a canonical `:run-async` function:

```fennel
{:id :long-task
 :title "Long task"
 :run-async (fn [command payload callbacks]
              (callbacks.progress {:message "starting" :value 0})
              {:pending true
               :cancel cancel-fn
               :drop drop-fn})}
```

`callbacks` provided to `:run-async` contains:

- `progress(progress-table)`: emits non-terminal progress. `progress-table`
  supports `:message` string and `:value` number in `[0, 1]`.
- `resolve(value)`: emits terminal `{:id command-id :status :ok :value value}`.
- `reject(error)`: emits terminal `{:id command-id :status :error :error
  error-string}`.
- `cancelled?()`: returns whether cancellation/drop has been requested.

The `:run-async` return value is either:

- `:completed`, only when a terminal callback has already been delivered; or
- `{:pending true :cancel fn? :drop fn?}` for pending work.

Malformed async returns and malformed progress payloads are command handler
contract failures after dispatch, so they produce one error result envelope and
close the invocation rather than throwing structural runner errors. Missing host,
registry, command id, command lookup, metadata, and invalid runner callback
arguments remain structural errors with the command-runner prefix.

### Runner API

`CommandRunner.run-host(host, command-id, payload)` remains unchanged.

Add:

```fennel
(CommandRunner.run-host-async host command-id payload callbacks)
```

Caller callbacks:

- `callbacks.on-result(result)`: required; receives exactly one terminal result
  envelope for completed, failed, or cancelled invocations.
- `callbacks.on-progress(progress)`: optional; receives validated progress
  tables before terminal result.

The returned invocation handle has fields/methods:

```fennel
{:id command-id
 :status :running|:completed|:cancelled|:dropped
 :cancel (fn [self reason] true)
 :drop (fn [self] true)
 :cancelled? (fn [self] boolean)}
```

`run-host-async` wraps sync commands automatically: when a command has only
`:run`, it calls the existing sync path, invokes `on-result` synchronously, and
returns a completed handle. When a command has `:run-async`, the async path owns
exactly-once terminal delivery, idempotent cancel/drop, and stale callback
suppression.

Cancellation emits one terminal `{:id command-id :status :cancelled :error
reason-string}` result unless the invocation has already completed or dropped.
Drop is lifecycle cleanup: it calls the underlying `:drop` handle when present,
falls back to `:cancel` when needed, prevents future callbacks, and does not emit
a user-visible terminal result.

### Workspace panel/session API

Workspace sessions and descriptors keep `run-command` unchanged and add:

```fennel
(session:run-command-async command-id payload callbacks)
(descriptor:run-command-async command-id payload callbacks)
```

The workspace panel tracks running async handles so `session:close()` drops them
before dropping the mount. Close remains idempotent. Cleanup attempts all active
handles; if cleanup throws, it records the first error, attempts the rest, then
rethrows after cleanup attempts finish.

### Command controls UI

Command controls prefer `descriptor:run-command-async` when available and fall
back to existing `descriptor:run-command` for older descriptors/tests. Confirmation
and payload timing stay unchanged: first confirmation click only arms the inline
confirmation, and payload construction happens only on the execution click.

While an async command is running:

- one active command per controls widget is allowed;
- active command button label becomes `Cancel` and remains enabled;
- other command buttons are disabled;
- progress updates the existing result badge/text area using the result model;
- terminal success/error/cancel restores labels, re-enables buttons, clears busy
  state, and records `state.last-result`;
- structural invocation failures restore the previous visible summary, preserve
  `state.last-result`, restore buttons/labels, and rethrow.

The controls maintain an active run token. Every progress/result callback checks
that the widget is not dropped and the token still matches before mutating UI
state. Drop calls the active invocation handle’s `drop` method once and ignores
late callbacks.

### Result model

Extend `app-host.command-result-model` with:

- `progress-summary(command, progress)`: phase `:running`, info tone, and message
  containing command label, progress message, and a percentage when `:value` is a
  valid number in `[0, 1]`.
- `result-summary` support for `:cancelled`: phase `:cancelled`, warning tone,
  and cancellation reason when present.

Existing `:ok`, `:error`, bounded value rendering, and unknown status behavior
remain unchanged.

## Error Handling

- Structural runner inputs still throw loudly and are not converted to result
  envelopes.
- Sync handler exceptions still become `:error` result envelopes.
- Async handler throws, rejects, malformed returns, and malformed progress after
  dispatch produce exactly one `:error` result envelope.
- Cancellation is terminal and idempotent; late progress/resolve/reject callbacks
  after cancellation are ignored.
- Drop is lifecycle cleanup and does not emit a user-visible terminal result;
  late callbacks after drop are ignored.
- UI teardown and workspace close must not leave live callbacks mutating dropped
  widgets.

## Testing

- Command runner tests cover sync fallback through async API, pending progress,
  resolve, reject, thrown async handler errors, cancellation idempotency, drop
  cleanup, malformed async returns, and malformed progress.
- Result model tests cover progress summaries, valid percentage rendering,
  message-only progress, and cancelled summaries.
- Workspace panel/session tests cover `run-command-async` delegation and close
  cleanup of active handles while preserving existing close behavior.
- Command controls tests cover pending state, progress updates, terminal success,
  terminal error, cancel button behavior, drop cleanup/late callback suppression,
  confirmation payload deferral, structural invocation cleanup, and sync fallback.
- Validation order: `make fennel-check`, `make constraints`, focused hosted app
  command tests, then `tests.fast:main` because this changes command runner,
  workspace panel lifecycle, and classic HUD control behavior.

## Acceptance Criteria

- Existing synchronous hosted commands keep passing through `run-command` without
  API or envelope changes.
- `run-host-async` wraps sync commands and supports opt-in `:run-async` pending
  commands.
- Async commands can emit progress and exactly one terminal success/error/cancel
  result.
- Active command controls show running/progress state, expose Cancel for the
  active command, and disable other commands.
- Cancel produces one cancelled result and ignores late callbacks.
- Drop/close cleans up active async handles and ignores late callbacks without UI
  mutation after teardown.
- Docs describe the new async API and remove stale claims that async progress or
  cancellation is out of scope.
