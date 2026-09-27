# Hosted Command History Design

## Context

Hosted app command controls now support metadata, payload forms, inline
confirmation, latest-result rendering, synchronous busy protection, async
progress, cancellation, and lifecycle cleanup. The UI still only exposes the
latest command state. Once a command finishes, users lose context about prior
runs, payload choices, cancellations, and failures. Async commands especially
benefit from a compact run log so users can tell what happened without adding a
full job queue or persistent telemetry system.

The current command controls layer is the only layer that sees the full
user-facing lifecycle: confirmation, execution click, payload construction,
structural payload failures, sync/async dispatch, progress callbacks, terminal
results, user cancellation, stale callback guards, and widget drop. That makes it
the right owner for a first run-history slice.

## Goals

- Add a bounded, session-local, in-memory recent command run log to hosted
  workspace command controls.
- Record actual execution attempts for both synchronous and asynchronous
  commands.
- Show the recent run log below the latest-result area using compact text.
- Update the active history row for async progress instead of appending one row
  per progress event.
- Record local failures that happen after execution click, including payload
  validation and structural descriptor invocation errors.
- Store only deterministic bounded text summaries for payloads, progress,
  results, and errors; never retain raw payload/result tables in history entries.
- Keep the slice explicitly non-persistent and independent of queues, polling,
  background jobs, auth, or app-specific APIs.

## Non-Goals

- No persistent command history or cross-session/global log.
- No durable job ids, polling APIs, command queues, background jobs, or recovery
  after reload.
- No auth, permissions, approvals, or policy decisions.
- No app-specific history APIs or custom command controls.
- No filtering, search, export/download, or expandable detail inspector.
- No new progress-bar widget; the log uses compact text summaries.
- No C++ engine or binding changes.

## Approaches Considered

### 1. Controls-owned history with a reusable model (chosen)

Command controls own a small in-memory history model and render one compact
`WrappedText` block. This layer can distinguish confirmation-only clicks from
actual execution attempts, attach payload summaries after payload construction,
record payload validation failures, update async progress in place, and avoid
turning lifecycle drop cleanup into a user-visible terminal run. The reusable
model keeps formatting, bounds, and privacy rules out of the large controls file.

### 2. Workspace panel/session-level history

The panel/session wrappers can observe `run-command` and `run-command-async`, but
they do not know about confirmation, payload form construction, local payload
validation failures, or whether a controls widget drop should suppress a visible
terminal history update. Putting history there would either miss important UI
events or force UI policy upward into the panel layer.

### 3. Command runner-level history

The runner sees low-level sync/async execution and structural contract errors,
but not UI execution intent, payload form failures before dispatch, confirmation,
or control teardown semantics. Runner-level history also risks turning an
execution primitive into a telemetry owner and makes future non-UI callers inherit
workspace UI logging policy.

## Design

### History model

Create `app-host.command-run-history` as a small pure model consumed by
`workspace-command-controls`. It owns run ids, timestamps, bounded summaries,
entry updates, trimming, and display text.

History configuration:

- `:limit` defaults to `10` recent entries per controls widget.
- `:now` defaults to `os.time` and is injectable for deterministic tests.
- entries are ordered newest first.
- run ids are controls-local monotonically increasing integers.

Entry shape:

```fennel
{:run-id number
 :started-at number
 :updated-at number
 :command-id any
 :command-label string
 :status :running|:ok|:error|:cancelled|:unknown
 :terminal? boolean
 :payload-text string|nil
 :progress-text string|nil
 :progress-value number|nil
 :result-text string|nil
 :error-text string|nil
 :result-status-text string|nil}
```

Entries must not contain raw `command`, `payload`, `progress`, or `result`
objects. Payload and result values are summarized with
`CommandResultModel.value-text`, which is already deterministic and bounded.
Errors and status strings are converted to bounded text as well.

Model operations:

- `create(opts)` creates an empty bounded history.
- `start-run!(history, command)` inserts a new running entry and returns it.
- `set-payload!(history, run-id, payload)` stores a bounded payload summary.
- `progress!(history, run-id, command, progress)` updates the existing running
  entry with progress message/value.
- `finish!(history, run-id, command, result)` updates the existing entry with a
  terminal result summary.
- `fail!(history, run-id, command, err)` updates the entry as a local failed run.
- `entries(history)` returns the newest-first entry list.
- `list-text(history)` returns compact text for rendering.

### Controls integration

`WorkspaceCommandControls` accepts optional `:history-limit` and `:now` options
for tests and constructs one history model per controls widget. Its existing
latest-result UI remains unchanged. A new single `WrappedText` block below the
latest result renders `History.list-text(history)`. The controls state exposes
`run-history`, `active-history-run-id`, and `history-message` for focused tests.

History updates follow user intent:

- Build/snapshot rendering never creates history entries.
- First confirmation click never creates a history entry.
- The actual execution click creates exactly one running entry.
- If payload construction succeeds, the entry receives a payload summary.
- If payload validation fails after execution click, the entry becomes `:error`,
  the handler is not called, and the existing thrown-error behavior is preserved.
- Sync terminal envelopes finish the same entry.
- Sync structural descriptor errors after execution click mark the entry failed,
  preserve existing latest-result restoration, and rethrow.
- Async progress updates the active entry and refreshes the single text block.
- Async terminal success/error/cancel finishes the active entry.
- User cancellation records a `:cancelled` terminal entry using the existing
  cancellation result envelope.
- Widget drop or workspace close cleanup does not append or convert history
  entries to terminal drop/cancel rows; late callbacks remain ignored by existing
  token/drop guards.

### Display

The first UI is intentionally compact:

```text
Recent runs
#3 Save Game — ok — payload {slot=1} — result saved
#2 Export — cancelled — user cancelled
#1 Reset — error — number field count is required
```

Empty history displays:

```text
Recent runs
No command runs yet
```

This avoids dynamic child management per history row, keeps widget ownership
simple, and leaves future expandable rows/search/filtering as separate slices.

## Error Handling

- History model errors should be structural programming errors only; normal
  command failures are represented as entry statuses.
- Payload validation failures after execution click create failed local entries
  and rethrow as they do today.
- Structural descriptor invocation failures after execution click create failed
  local entries and rethrow as they do today.
- Stale async callbacks after completion/cancel/drop must not mutate history.
- History trimming must remove lookup references for evicted entries so late
  updates to evicted run ids are ignored.

## Testing

- Model tests cover injected timestamps, monotonically increasing run ids,
  newest-first ordering, default/custom limit trimming, progress updating the same
  entry, terminal ok/error/cancelled/unknown statuses, bounded payload/result
  text, and absence of raw payload/result fields.
- Controls tests cover confirmation first-click no-entry behavior, execution
  click entry creation, invalid payload failure entry, structural descriptor
  failure entry, sync terminal result entry, async progress in-place update,
  async terminal/cancel finish, drop cleanup not appending terminal entries, and
  default 10-entry trimming.
- Documentation updates describe session-local lifetime, bounds, privacy summary
  behavior, and non-goals.
- Validation order: compile check, constraints, focused history/controls tests,
  and broader hosted command tests when useful. PR CI remains the full integration
  gate.

## Acceptance Criteria

- A fresh controls widget shows an empty recent-runs message.
- Confirmation first-click leaves history empty.
- Actual execution creates exactly one history entry.
- Payload validation failures after execution click create one failed entry and do
  not call the command handler.
- Sync and async terminal results finish the entry created for that run.
- Async progress updates the active entry without appending progress rows.
- User cancellation finishes the active entry as cancelled.
- Drop/close lifecycle cleanup does not create a user-visible terminal entry.
- History is bounded to 10 entries by default, newest first.
- Entries store bounded text summaries only and do not retain raw payload/result
  objects.
- Existing latest-result, confirmation, busy/cancel, and async callback guard
  behavior remains intact.
