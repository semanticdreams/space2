# Track 12 Runtime Scheduler Design

## Summary

Track 12 adds a typed Fennel runtime scheduler surface for Space temporal work:
`RuntimeScheduler`. The scheduler provides deterministic one-shot, interval, and
recurrence scheduling; fixed-clock/manual-advance tests; idempotent
cancellation/lifecycle behavior; and compatibility wrappers for the existing
`RuntimeTimers.Timeout`, `RuntimeTimers.Interval`, `RuntimeTimers.Debouncer`, and
`RuntimeTimers.clear` APIs.

The scheduler is a Fennel policy layer. It must not move scheduler policy into
the native temporal core, infer host-local timezones, fetch network data, or add
legacy option aliases to the new typed API.

## Goals

- Provide a public `RuntimeScheduler` module with typed scheduling methods.
- Preserve existing `runtime-timers` compatibility APIs for current callers.
- Integrate typed scheduled work with the existing app-host scheduler pause and
  step lifecycle.
- Support deterministic fixed-clock tests that advance scheduler time without
  depending on wall-clock time.
- Support recurrence scheduling using existing temporal recurrence surfaces with
  explicit zone policy.
- Define catch-up semantics for large advances, host pause, missed deadlines,
  and cancellation during callbacks.
- Keep callback failures loud and observable.

## Non-goals

- No native C++ temporal-core redesign.
- No OS-threaded timers, background jobs, or cross-process scheduling.
- No host-local timezone inference.
- No network-backed timezone, recurrence, or provider lookups.
- No natural-language schedule strings.
- No broad migration of existing `RuntimeTimers` call sites beyond preserving the
  compatibility wrappers.
- No media clocks, profiling clocks, `engine.now-ms`, or `sysinfo.now-ms`
  redesign in this slice.

## Existing Context

- `assets/lua/runtime-timers.fnl` currently owns timer policy directly through
  `app.engine.events.updated` and a global `app.__runtime_timers` table.
- `assets/lua/app-host/services.fnl` already has a generic scheduler service
  that registers facets with `update(delta-ms)`, supports `set-paused`, `step`,
  and `list`, and is used by hosted runtime controllers.
- `Temporal.duration`, `Temporal.clock`, `Temporal.recurrence-set`, and related
  temporal APIs already exist and remain the source of typed temporal values.
- Track 12 acceptance requires fixed-clock tests, recurrence scheduling tests,
  cancellation/lifecycle tests, and timer compatibility APIs.

## Evaluated Approaches

### Option A: Patch `runtime-timers.fnl` in place

This is the smallest change, but it keeps timer policy tied to a global table and
direct engine update connection. It does not provide a clean typed scheduler
surface, fixed-clock model, or host scheduler integration. Rejected.

### Option B: Put temporal timer policy into `app-host.services.make-scheduler`

This naturally integrates pause/step, but it couples the generic host service to
temporal recurrence policy and legacy wrapper behavior. That makes isolated
scheduler tests harder and blurs the boundary between host orchestration and
temporal scheduling. Rejected.

### Option C: Add `runtime-scheduler.fnl`, delegate from host services, and keep
`runtime-timers` as wrappers

This creates a focused Fennel policy layer with deterministic tests, keeps the
host scheduler generic by delegation, and preserves existing timer APIs. This is
the selected approach.

## Public API

Create `assets/lua/runtime-scheduler.fnl` exporting at least:

```fennel
{:create create}
```

`RuntimeScheduler.create(opts)` returns a scheduler object. Supported options:

- `:clock` optional temporal clock. Defaults to `Temporal.clock.system()`.

Scheduler methods:

- `scheduler:schedule-once {:delay duration :callback fn} -> handle`
- `scheduler:schedule-every {:interval duration :callback fn} -> handle`
- `scheduler:schedule-recurrence {:recurrence-set recurrence-set
                                  :zone-id string
                                  :callback fn
                                  :disambiguation keyword?
                                  :limit number?} -> handle`
- `scheduler:advance(duration) -> true`
- `scheduler:update(delta-ms) -> true`
- `scheduler:clear() -> true`
- `scheduler:drop() -> true`
- `scheduler:list() -> sequential job summaries`

Handle methods:

- `handle:cancel() -> true`
- `handle:drop() -> true`
- `handle:active?() -> boolean`

The new typed scheduler API accepts only canonical keys. It must reject aliases
such as `:delay-ms`, `:interval-ms`, `:timezone`, and `:tz`. Millisecond keys
remain valid only on the legacy `runtime-timers` compatibility wrappers.

## Time Model

The scheduler stores internal deadlines as integer nanoseconds relative to its
internal epoch. Exact `Temporal.duration` values remain nanoseconds-only.

`create {:clock clock}` seeds scheduler time from `clock:now()` so tests can use
`Temporal.clock.fixed(start-instant)` and deterministic `advance` calls.

`advance(duration)` moves scheduler time by an exact non-negative duration and
executes all due work in deterministic deadline order.

`update(delta-ms)` is the host/engine compatibility entry point. It converts a
finite non-negative millisecond delta to a duration and delegates to `advance`.
Malformed or negative deltas must fail loudly for the typed scheduler. Legacy
wrappers may preserve their existing non-negative clamping only at the wrapper
boundary if required for compatibility.

## Catch-up Semantics

- One-shot jobs fire once when their deadline is due.
- Interval jobs fire once for every missed interval during an explicit
  `advance`, `step`, or `update` call.
- Large explicit advances catch up deterministically in deadline order.
- If multiple jobs share a deadline, fire them in creation order.
- Host pause does not create hidden elapsed time because paused host update does
  not call into the scheduler.
- `step(delta-ms)` while paused explicitly advances scheduled work.
- Cancelling an interval inside its callback prevents later catch-up callbacks
  for that handle in the same tick.
- `clear` during a callback cancels all pending work and prevents sibling jobs
  from firing later in the same tick.

This preserves the current interval catch-up behavior while making pause and
manual-step behavior explicit.

## Recurrence Scheduling

Recurrence scheduling uses existing temporal recurrence surfaces and remains in
Fennel policy code.

- `schedule-recurrence` requires explicit `:zone-id`; there is no host-local
  timezone fallback.
- `:disambiguation` defaults to `:reject` if omitted.
- Unbounded recurrence sets must require `:limit` or propagate the existing
  recurrence-layer loud error.
- Due occurrence instants fire in chronological order.
- Recurrence callbacks receive one argument: a table with `:scheduled-at` set to
  the due occurrence instant and `:occurrence-index` set to its one-based index
  within this handle's emitted occurrences. This payload shape is public and
  must be tested.

## Host Scheduler Integration

`assets/lua/app-host/services.fnl` should keep the existing scheduler facet
registry contract unchanged. `make-scheduler` gains an internal
`RuntimeScheduler` instance and delegates typed methods:

- `host.scheduler:schedule-once(opts)`
- `host.scheduler:schedule-every(opts)`
- `host.scheduler:schedule-recurrence(opts)`

Existing methods remain compatible:

- `register`, `unregister`, and `list` continue to operate on registered update
  facets, not internal timer jobs.
- `update(delta-ms)` advances typed scheduled work first, then registered facets,
  when not paused.
- `step(delta-ms)` advances typed scheduled work and registered facets even when
  paused.
- `set-paused(true)` prevents both typed scheduler advancement and facet updates
  during normal `update` calls.

## RuntimeTimers Compatibility

`assets/lua/runtime-timers.fnl` remains the compatibility module for current
callers:

- `RuntimeTimers.Timeout {:delay-ms number :callback fn}`
- `RuntimeTimers.Interval {:interval-ms positive-number :callback fn}`
- `RuntimeTimers.Debouncer {:delay-ms number :callback fn}`
- `RuntimeTimers.clear()`

These wrappers delegate to a compatibility-owned scheduler and may retain the
current engine update connection for global `RuntimeTimers` users. They are the
only place where `:delay-ms` and `:interval-ms` remain valid. The wrappers must
preserve public behavior: restart on `start`, interval catch-up, debouncer latest
payload, idempotent cancel/drop, self-drop from callback, and clear from callback.

Tests should stop relying on `app.__runtime_timers.update-handler` internals once
the implementation migrates to scheduler delegation.

## Errors and Validation

The typed scheduler must fail loudly for:

- unknown option keys;
- missing or non-function callbacks;
- missing required `:delay`, `:interval`, `:recurrence-set`, or `:zone-id`;
- negative or malformed durations;
- malformed `delta-ms` values on typed `update`;
- recurrence scheduling without explicit zone policy.

Callback errors propagate out of `advance`/`update`/`step`; they must not be
swallowed.

## Testing Requirements

Focused tests must cover:

- fixed-clock one-shot scheduling;
- interval catch-up on large advance;
- deterministic ordering by deadline and creation order;
- host pause and explicit step behavior;
- recurrence `:zone-id` requirement;
- recurrence due occurrences firing in order;
- cancellation before due, during callback, and `clear` during callback;
- callback error propagation;
- unknown option key rejection;
- `RuntimeTimers` compatibility behavior;
- app-host scheduler typed method delegation while preserving facet registry
  behavior.

Validation ladder:

1. `make fennel-check`
2. `make constraints`
3. focused `tests.test-runtime-scheduler:main`
4. focused `tests.test-runtime-timers:main`
5. focused host scheduler/runtime tests as changed
6. broader `make test` because the runtime scheduler is public runtime behavior

Direct Fennel test runs must use project runtime environment variables from
`AGENTS.md` and the Space Fennel skills.

## Documentation Updates

Track 12 should add `docs/dev/features/runtime-scheduler.md` and update:

- `docs/dev/features/temporal.md`
- `docs/dev/features/temporal-complete-library.md`
- `docs/dev/features/temporal-complete-acceptance.md`
- hosted-runtime documentation if host scheduler methods change there

Docs must clearly state that scheduler policy is Fennel runtime policy, not a
native temporal-core primitive, and that recurrence scheduling requires explicit
timezone policy.

## Acceptance Criteria

- `RuntimeScheduler` exists and supports one-shot, interval, and recurrence
  scheduling with typed temporal inputs.
- Fixed-clock tests can deterministically advance scheduler time.
- Host scheduler pause/step semantics apply to typed scheduled work.
- Existing `RuntimeTimers` public APIs remain available and behavior-compatible.
- Recurrence scheduling requires explicit `:zone-id` and never infers host-local
  timezone.
- Cancellation, drop, and clear are idempotent and prevent late callbacks.
- Callback failures surface loudly.
- No runtime scheduler behavior fetches network data.
- Native temporal core remains independent from scheduler policy.
