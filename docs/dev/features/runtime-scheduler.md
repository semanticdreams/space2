# Runtime Scheduler

`runtime-scheduler` is Space's typed runtime scheduling policy layer. It lives in
Fennel above `Temporal.duration`, `Temporal.clock`, and
`Temporal.recurrence-set`; it is not part of the native temporal core and does
not infer host-local timezones, fetch network data, create OS threads, or run
background/cross-process jobs.

## Public API

Require it from Fennel with `(require :runtime-scheduler)`:

```fennel
(local RuntimeScheduler (require :runtime-scheduler))
(local scheduler (RuntimeScheduler.create {:clock (Temporal.clock.fixed start)}))
```

`RuntimeScheduler.create(opts)` accepts only `{:clock clock?}`. The clock defaults
to `Temporal.clock.system()` and seeds the scheduler's internal epoch with
`clock:now()`.

Scheduler methods are:

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

Handle methods are:

- `handle:cancel() -> true`
- `handle:drop() -> true`
- `handle:active?() -> boolean`

The typed scheduler accepts only canonical keys. Legacy `:delay-ms` and
`:interval-ms` keys are rejected here and remain valid only at the
`runtime-timers` compatibility wrapper boundary.

## Time model

Deadlines are stored as exact integer nanoseconds relative to the scheduler's
internal epoch. `advance(duration)` requires a non-negative exact
`Temporal.duration` and drains all due work before returning. Tests and replay can
create a deterministic scheduler with `Temporal.clock.fixed(instant)` and then
move time explicitly with `advance`.

`update(delta-ms)` is the host/engine compatibility entry point. It accepts a
finite non-negative millisecond delta, converts it to exact nanoseconds, and
delegates to `advance`. Malformed deltas fail loudly.

## Catch-up and lifecycle policy

- One-shot jobs fire once when their deadline is due.
- Interval jobs fire once for each missed interval during a single `advance`,
  `update`, or host `step`.
- Due jobs run by earliest deadline, then creation order for equal deadlines.
- Callback errors propagate out of `advance`, `update`, and host `step`; they are
  not swallowed.
- Cancelling or dropping a handle is idempotent and prevents future callbacks.
- Cancelling an interval from inside its callback stops any later catch-up
  callbacks for that handle in the same drain.
- `clear`/`drop` deactivate all pending work. Calling `clear` from a callback
  prevents sibling jobs at the same deadline from firing later in that drain.
- Host pause does not accumulate hidden elapsed time: paused host `update` calls
  do not advance scheduled work. An explicit host `step(delta-ms)` does advance
  scheduled work while paused.

## Recurrence scheduling

`schedule-recurrence` uses `Temporal.recurrence-set.occurrences` and requires an
explicit `:zone-id`; there is no host-local timezone fallback. If
`:disambiguation` is omitted, it defaults to `:reject`. Use `:limit` for finite
expansion when the recurrence layer requires one.

Each occurrence schedules internal one-shot work. The callback receives exactly
one public payload table:

```fennel
{:scheduled-at instant :occurrence-index n}
```

`:scheduled-at` is the occurrence instant and `:occurrence-index` is one-based
within that scheduled recurrence handle.

## Host scheduler integration

`app-host.services.make-scheduler` owns an internal runtime scheduler and exposes
typed delegation methods:

- `host.scheduler:schedule-once(opts)`
- `host.scheduler:schedule-every(opts)`
- `host.scheduler:schedule-recurrence(opts)`

The existing facet registry remains separate: `register`, `unregister`, and
`list` continue to operate on update facets, not internal timer jobs. Normal
`update(delta-ms)` advances typed scheduled work before facets when not paused.
`set-paused true` prevents normal updates from advancing both typed scheduled
work and facets. `step(delta-ms)` advances typed scheduled work and facets even
while paused.

## RuntimeTimers compatibility

`runtime-timers` remains the compatibility API for legacy callers:

- `RuntimeTimers.Timeout {:delay-ms number :callback fn}`
- `RuntimeTimers.Interval {:interval-ms positive-number :callback fn}`
- `RuntimeTimers.Debouncer {:delay-ms number :callback fn}`
- `RuntimeTimers.clear()`

Those wrappers convert millisecond options to typed durations at their boundary
and delegate to a private `RuntimeScheduler`. Do not add millisecond aliases to
the typed scheduler API.

## Validation

Use the project runtime and native Fennel validation tools:

```bash
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-runtime-scheduler:main
```
