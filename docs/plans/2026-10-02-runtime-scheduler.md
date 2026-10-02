# Runtime Scheduler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Track 12 `RuntimeScheduler` with deterministic typed scheduling, recurrence support, host scheduler integration, and existing `RuntimeTimers` compatibility.

**Architecture:** Add a focused Fennel policy module, `assets/lua/runtime-scheduler.fnl`, above existing temporal primitives. Keep app-host scheduler generic by delegating typed methods to an internal runtime scheduler. Preserve `runtime-timers` as a compatibility wrapper layer for existing millisecond-key callers.

**Tech Stack:** Space Fennel, `Temporal.duration`, `Temporal.clock`, `Temporal.recurrence-set`, app-host scheduler services, project-native Fennel tests.

## Global Constraints

- The scheduler is a Fennel policy layer. It must not move scheduler policy into the native temporal core, infer host-local timezones, fetch network data, or add legacy option aliases to the new typed API.
- No native C++ temporal-core redesign.
- No OS-threaded timers, background jobs, or cross-process scheduling.
- No host-local timezone inference.
- No network-backed timezone, recurrence, or provider lookups.
- No natural-language schedule strings.
- No broad migration of existing `RuntimeTimers` call sites beyond preserving the compatibility wrappers.
- No media clocks, profiling clocks, `engine.now-ms`, or `sysinfo.now-ms` redesign in this slice.
- Exact `Temporal.duration` values remain nanoseconds-only.
- `schedule-recurrence` requires explicit `:zone-id`; there is no host-local timezone fallback.
- Callback errors propagate out of `advance`/`update`/`step`; they must not be swallowed.
- Direct Fennel validation must use project-native `tools.fennel-check`, constraints, and test commands; do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.

---

## File Structure

- Create `assets/lua/runtime-scheduler.fnl`: typed scheduler policy module. Owns schedule storage, exact duration conversion, due-job ordering, recurrence job expansion, cancellation, lifecycle, and deterministic manual advancement.
- Create `assets/lua/tests/test-runtime-scheduler.fnl`: focused tests for typed scheduler API, fixed-clock/manual advancement, catch-up, ordering, recurrence, cancellation, clear, and loud validation.
- Modify `assets/lua/tests/fast.fnl`: register `tests.test-runtime-scheduler`.
- Modify `assets/lua/app-host/services.fnl`: instantiate and delegate to internal `RuntimeScheduler` inside `make-scheduler` while keeping existing facet registry behavior.
- Modify `assets/lua/tests/test-app-host-services.fnl`: focused host scheduler typed-method tests.
- Modify `assets/lua/tests/test-standalone-app-runtime.fnl`: verify engine update, pause, and step drive typed scheduled work through host scheduler.
- Modify `assets/lua/runtime-timers.fnl`: replace direct timer policy with compatibility wrapper delegation to a private scheduler and engine update connection.
- Modify `assets/lua/tests/test-runtime-timers.fnl`: preserve behavior assertions while removing assertions against `app.__runtime_timers.update-handler` internals.
- Create `docs/dev/features/runtime-scheduler.md`: public runtime scheduler docs.
- Modify `docs/dev/features/temporal.md`: link runtime scheduler docs and keep native-core separation explicit.
- Modify `docs/dev/features/temporal-complete-library.md`: mark Track 12 current status after implementation.
- Modify `docs/dev/features/temporal-complete-acceptance.md`: add Track 12 validation commands and evidence.
- Modify `docs/dev/features/hosted-runtime-apps.md`: document host scheduler typed methods, pause, and step behavior.

---

### Task 1: RuntimeScheduler Core API and Tests

**Files:**
- Create: `assets/lua/runtime-scheduler.fnl`
- Create: `assets/lua/tests/test-runtime-scheduler.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `Temporal.duration`, `Temporal.clock`, `Temporal.recurrence-set`.
- Produces:
  - `RuntimeScheduler.create(opts) -> scheduler`
  - `scheduler:schedule-once(opts) -> handle`
  - `scheduler:schedule-every(opts) -> handle`
  - `scheduler:schedule-recurrence(opts) -> handle`
  - `scheduler:advance(duration) -> true`
  - `scheduler:update(delta-ms) -> true`
  - `scheduler:clear() -> true`
  - `scheduler:drop() -> true`
  - `scheduler:list() -> sequential job summaries`
  - `handle:cancel() -> true`
  - `handle:drop() -> true`
  - `handle:active?() -> boolean`

- [ ] **Step 1: Write the failing test module skeleton**

Create `assets/lua/tests/test-runtime-scheduler.fnl` with local helpers and the first failing API test:

```fennel
(local tests [])
(local Temporal (require :temporal))
(local RuntimeScheduler (require :runtime-scheduler))

(fn assert-error-contains [f needle message]
  (local (ok err) (pcall f))
  (assert (not ok) message)
  (assert (string.find (tostring err) needle 1 true)
          (.. message ": expected " needle ", got " (tostring err))))

(fn duration-ms [ms]
  (Temporal.duration.from {:milliseconds ms}))

(fn fixed-clock [iso]
  (Temporal.clock.fixed (Temporal.instant.from iso)))

(fn schedule-once-fires-with-fixed-clock []
  (local scheduler (RuntimeScheduler.create {:clock (fixed-clock "2026-01-01T00:00:00Z")}))
  (local calls [])
  (scheduler:schedule-once {:delay (duration-ms 100)
                            :callback (fn [] (table.insert calls "fired"))})
  (scheduler:advance (duration-ms 99))
  (assert (= (length calls) 0) "one-shot should wait until due")
  (scheduler:advance (duration-ms 1))
  (assert (= (length calls) 1) "one-shot should fire when due")
  (scheduler:advance (duration-ms 100))
  (assert (= (length calls) 1) "one-shot should not fire twice"))

(table.insert tests {:name "RuntimeScheduler one-shot fixed-clock fire"
                     :fn schedule-once-fires-with-fixed-clock})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "runtime-scheduler" :tests tests})))

{:main main}
```

- [ ] **Step 2: Run the focused test to verify RED**

Run:

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-runtime-scheduler:main
```

Expected: FAIL because `runtime-scheduler` is missing or `create` is missing.

- [ ] **Step 3: Implement the minimal scheduler module**

Create `assets/lua/runtime-scheduler.fnl` with:

```fennel
(local Temporal (require :temporal))

(fn scheduler-error [message]
  (error (.. "[runtime-scheduler] " message)))

(fn table-or-empty [value]
  (if (= value nil) {} value))

(fn function? [value]
  (= (type value) :function))

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn reject-unknown-keys [label options allowed]
  (each [key _value (pairs (table-or-empty options))]
    (when (not (. allowed key))
      (scheduler-error (.. label " unknown option: " (tostring key))))))

(fn duration->nanoseconds [value label]
  (when (= value nil)
    (scheduler-error (.. label " requires duration")))
  (local nanos
    (if (= (type value) :number)
        value
        (and (= (type value) :userdata)
             (= (type value.nanoseconds) :function)
             (value:nanoseconds))))
  (when (not (and (= (type nanos) :number) (= nanos (math.floor nanos)) (>= nanos 0)))
    (scheduler-error (.. label " requires non-negative exact duration")))
  nanos)

(fn create-handle [scheduler job]
  (fn cancel [_self]
    (when job.active?
      (set job.active? false)
      (tset scheduler.jobs job.id nil))
    true)
  (fn active? [_self] job.active?)
  {:cancel cancel :drop cancel :active? active?})

(fn create [opts]
  (local options (table-or-empty opts))
  (reject-unknown-keys "create" options {:clock true})
  (local scheduler {:clock (or options.clock (Temporal.clock.system))
                    :now-ns 0
                    :next-id 1
                    :jobs {}})
  ;; Additional methods are added in subsequent steps in this task.
  scheduler)

{:create create}
```

Then continue within this task to add `schedule-once`, `advance`, and due-job execution until Step 1 passes. Use the existing native duration method `duration:nanoseconds()` to read exact integer nanoseconds; do not add a lossy millisecond conversion to the typed API.

- [ ] **Step 4: Add tests for interval catch-up and deterministic ordering**

Append tests to `test-runtime-scheduler.fnl`:

```fennel
(fn interval-catches-up-in-deadline-order []
  (local scheduler (RuntimeScheduler.create {:clock (fixed-clock "2026-01-01T00:00:00Z")}))
  (local calls [])
  (scheduler:schedule-every {:interval (duration-ms 100)
                             :callback (fn [] (table.insert calls "interval"))})
  (scheduler:advance (duration-ms 350))
  (assert (= (length calls) 3) "interval should fire once per missed interval"))

(fn equal-deadlines-fire-in-creation-order []
  (local scheduler (RuntimeScheduler.create {:clock (fixed-clock "2026-01-01T00:00:00Z")}))
  (local calls [])
  (scheduler:schedule-once {:delay (duration-ms 50) :callback (fn [] (table.insert calls "a"))})
  (scheduler:schedule-once {:delay (duration-ms 50) :callback (fn [] (table.insert calls "b"))})
  (scheduler:advance (duration-ms 50))
  (assert (= (. calls 1) "a") "first equal-deadline job should fire first")
  (assert (= (. calls 2) "b") "second equal-deadline job should fire second"))
```

Register both tests. Expected RED before implementation of interval/order behavior; expected GREEN after implementation.

- [ ] **Step 5: Implement interval, due ordering, cancellation, clear, drop, list, and update**

In `runtime-scheduler.fnl` implement these semantics exactly:

- Jobs have `:id`, `:kind`, `:deadline-ns`, `:created-order`, `:active?`, `:callback`.
- Interval jobs additionally have `:interval-ns`.
- Due jobs sort by `deadline-ns`, then `created-order`.
- `schedule-once` accepts exactly `:delay`, `:callback`.
- `schedule-every` accepts exactly `:interval`, `:callback`.
- `advance(duration)` increments `scheduler.now-ns`, then drains due jobs until no active job is due.
- A one-shot job is removed before its callback.
- An interval job fires, then reschedules to `deadline-ns + interval-ns` only if still active after callback.
- `cancel`/`drop` are idempotent.
- `clear` deactivates and removes all jobs.
- `drop` delegates to `clear`.
- `list` returns sequential summaries with at least `:id`, `:kind`, `:deadline-ns`, and `:active?`.
- `update(delta-ms)` rejects non-finite or negative `delta-ms`, converts milliseconds to nanoseconds, and delegates to `advance`.

- [ ] **Step 6: Add cancellation, clear, callback error, and unknown-option tests**

Add tests covering:

```fennel
(fn cancel-before-due-prevents-callback []
  (local scheduler (RuntimeScheduler.create))
  (local calls [])
  (local handle
    (scheduler:schedule-once {:delay (duration-ms 10)
                              :callback (fn [] (table.insert calls "late"))}))
  (handle:cancel)
  (scheduler:advance (duration-ms 10))
  (assert (= (length calls) 0) "cancelled one-shot should not fire")
  (assert (not (handle:active?)) "cancelled handle should report inactive"))

(fn interval-cancel-inside-callback-stops-catchup []
  (local scheduler (RuntimeScheduler.create))
  (local calls [])
  (var handle nil)
  (set handle
       (scheduler:schedule-every {:interval (duration-ms 10)
                                  :callback (fn []
                                              (table.insert calls "tick")
                                              (handle:cancel))}))
  (scheduler:advance (duration-ms 50))
  (assert (= (length calls) 1) "interval cancellation should stop same-advance catch-up"))

(fn clear-inside-callback-stops-siblings []
  (local scheduler (RuntimeScheduler.create))
  (local calls [])
  (scheduler:schedule-once {:delay (duration-ms 10)
                            :callback (fn []
                                        (table.insert calls "first")
                                        (scheduler:clear))})
  (scheduler:schedule-once {:delay (duration-ms 10)
                            :callback (fn [] (table.insert calls "second"))})
  (scheduler:advance (duration-ms 10))
  (assert (= (length calls) 1) "clear from callback should stop siblings")
  (assert (= (. calls 1) "first") "first callback should be the one that cleared"))

(fn callback-error-propagates []
  (local scheduler (RuntimeScheduler.create))
  (scheduler:schedule-once {:delay (duration-ms 1)
                            :callback (fn [] (error "boom"))})
  (assert-error-contains #(scheduler:advance (duration-ms 1))
                         "boom"
                         "callback errors should propagate"))

(fn typed-api-rejects-legacy-keys []
  (local scheduler (RuntimeScheduler.create))
  (assert-error-contains #(scheduler:schedule-once {:delay-ms 1 :callback (fn [] nil)})
                         "unknown option"
                         "typed scheduler should reject delay-ms alias"))
```

Use concrete assertions, not broad smoke checks. `clear-inside-callback-stops-siblings` must schedule two jobs at the same deadline, make the first callback call `scheduler:clear()`, and assert the second callback did not run.

- [ ] **Step 7: Add recurrence tests and implementation**

Add tests for:

- missing `:zone-id` fails with an error containing `zone-id`;
- a finite recurrence set with two due occurrences fires in order;
- callback receives `{:scheduled-at instant :occurrence-index n}`.

Use the existing recurrence helpers exactly as they are used in `assets/lua/tests/test-temporal-recurrence-set.fnl`: construct finite sets with `Temporal.recurrence-set.from` and expand them with `Temporal.recurrence-set.occurrences`. The required public scheduler contract remains:

```fennel
(scheduler:schedule-recurrence {:recurrence-set recurrence-set
                                :zone-id "UTC"
                                :limit 2
                                :callback callback})
```

Implementation rules:

- Reject unknown keys.
- Reject missing `:recurrence-set`, missing `:zone-id`, and non-function `:callback`.
- Default `:disambiguation` to `:reject`.
- Use `Temporal.recurrence-set.occurrences recurrence-set {:zone-id zone-id :disambiguation disambiguation :limit limit}` to precompute occurrences.
- Insert one one-shot internal job per occurrence.
- Callback receives exactly one payload table with `:scheduled-at` and `:occurrence-index`.

- [ ] **Step 8: Register the new focused suite in fast tests**

Modify `assets/lua/tests/fast.fnl` to include `tests.test-runtime-scheduler` using the same registration pattern as neighboring temporal/runtime focused suites.

- [ ] **Step 9: Run validation and commit Task 1**

Run:

```bash
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-runtime-scheduler:main
```

Commit:

```bash
git add assets/lua/runtime-scheduler.fnl assets/lua/tests/test-runtime-scheduler.fnl assets/lua/tests/fast.fnl
git commit -m "feat(lua): add runtime scheduler core"
```

Report compile-check evidence before constraints and tests. Include a constraint-impact note.

---

### Task 2: App-Host Scheduler Delegation

**Files:**
- Modify: `assets/lua/app-host/services.fnl`
- Modify: `assets/lua/tests/test-app-host-services.fnl`
- Modify: `assets/lua/tests/test-standalone-app-runtime.fnl`

**Interfaces:**
- Consumes: `RuntimeScheduler.create`, `scheduler:schedule-once`, `scheduler:schedule-every`, `scheduler:schedule-recurrence`, `scheduler:update`.
- Produces host scheduler methods:
  - `host.scheduler:schedule-once(opts) -> handle`
  - `host.scheduler:schedule-every(opts) -> handle`
  - `host.scheduler:schedule-recurrence(opts) -> handle`
  - existing `register`, `unregister`, `update`, `set-paused`, `step`, `list` behavior remains compatible.

- [ ] **Step 1: Add failing app-host service tests**

In `assets/lua/tests/test-app-host-services.fnl`, add tests:

```fennel
(fn test-scheduler_typed_timer_updates_before_facets []
  (local Services (require :app-host/services))
  (local scheduler (Services.make-scheduler))
  (local calls [])
  (scheduler:schedule-once {:delay (Temporal.duration.from {:milliseconds 10})
                            :callback (fn [] (table.insert calls "timer"))})
  (scheduler:register {:update (fn [_self _delta] (table.insert calls "facet"))})
  (scheduler:update 10)
  (assert (= (. calls 1) "timer") "typed timer should run before facets")
  (assert (= (. calls 2) "facet") "facet should still update"))

(fn test-scheduler_pause_and_step_control_typed_timers []
  (local Services (require :app-host/services))
  (local scheduler (Services.make-scheduler))
  (local calls [])
  (scheduler:schedule-once {:delay (Temporal.duration.from {:milliseconds 10})
                            :callback (fn [] (table.insert calls "timer"))})
  (scheduler:set-paused true)
  (scheduler:update 10)
  (assert (= (length calls) 0) "paused update should not advance typed timers")
  (scheduler:step 10)
  (assert (= (length calls) 1) "step should advance typed timers while paused"))
```

Import `Temporal` in the test file if it is not already imported.

- [ ] **Step 2: Run app-host service tests to verify RED**

Run:

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-app-host-services:main
```

Expected: FAIL because host scheduler lacks typed methods or does not advance typed timers.

- [ ] **Step 3: Delegate typed methods in `Services.make-scheduler`**

Modify `assets/lua/app-host/services.fnl`:

- `local RuntimeScheduler (require :runtime-scheduler)` at the top.
- In `make-scheduler`, create `(local runtime-scheduler (RuntimeScheduler.create))`.
- Add methods `schedule-once`, `schedule-every`, and `schedule-recurrence` delegating to `runtime-scheduler`.
- In `update`, when not paused, call `(runtime-scheduler:update delta-ms)` before updating registered facets.
- In `step`, call `(runtime-scheduler:update delta-ms)` before updating registered facets even when paused.
- Keep `list` returning registered facets only.

- [ ] **Step 4: Add standalone runtime integration tests**

In `assets/lua/tests/test-standalone-app-runtime.fnl`, add tests proving engine update drives typed scheduled callbacks and paused controller step advances them. Use the existing fake app/host setup patterns in the file. The assertions must verify:

- `host.scheduler:schedule-once` callback fires after the standalone engine emits an update with enough delta;
- `controller:set-paused(true)` prevents normal update from firing the callback;
- `controller:step(delta-ms)` fires the callback while paused.

- [ ] **Step 5: Run validation and commit Task 2**

Run:

```bash
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-app-host-services:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-standalone-app-runtime:main
```

Commit:

```bash
git add assets/lua/app-host/services.fnl assets/lua/tests/test-app-host-services.fnl assets/lua/tests/test-standalone-app-runtime.fnl
git commit -m "feat(lua): delegate host scheduler timers"
```

Report compile-check evidence before constraints and tests. Include a constraint-impact note.

---

### Task 3: RuntimeTimers Compatibility Wrappers

**Files:**
- Modify: `assets/lua/runtime-timers.fnl`
- Modify: `assets/lua/tests/test-runtime-timers.fnl`

**Interfaces:**
- Consumes: `RuntimeScheduler.create`, `scheduler:schedule-once`, `scheduler:schedule-every`, `scheduler:update`, `scheduler:clear`.
- Produces unchanged compatibility API:
  - `RuntimeTimers.Timeout {:delay-ms number :callback fn}`
  - `RuntimeTimers.Interval {:interval-ms positive-number :callback fn}`
  - `RuntimeTimers.Debouncer {:delay-ms number :callback fn}`
  - `RuntimeTimers.clear()`

- [ ] **Step 1: Update compatibility tests before implementation**

In `assets/lua/tests/test-runtime-timers.fnl`:

- Keep existing behavior tests for timeout, interval catch-up, debouncer latest payload, self-drop, and clear from callback.
- Remove assertions that depend on `app.__runtime_timers.update-handler` being present or nil.
- Add an assertion that `RuntimeTimers.clear()` prevents later callbacks after an engine update.

Run `tests.test-runtime-timers:main` before implementation. Expected: existing internals assertions may fail after test edits if wrappers have not been migrated, or tests pass before migration; report RED only when an edited test captures behavior not yet implemented.

- [ ] **Step 2: Replace direct timer policy with scheduler delegation**

In `assets/lua/runtime-timers.fnl`:

- Require `runtime-scheduler` and `temporal`.
- Keep a private compatibility state under `app.__runtime_timers` with:
  - `:scheduler`
  - `:update-handler`
  - active handle count or equivalent tracking
- Convert `:delay-ms` and `:interval-ms` to typed durations at the wrapper boundary with `Temporal.duration.from {:milliseconds value}`.
- `Timeout:start` cancels any existing handle, schedules once, and clears its stored handle before invoking the callback.
- `Interval:start` cancels any existing handle and schedules every.
- `Debouncer:trigger(payload)` cancels any existing handle, stores latest payload, and schedules once unless delay is zero; zero delay fires synchronously as today.
- `clear` cancels all scheduler jobs and disconnects the compatibility update handler.
- The compatibility update handler continues to connect to `app.engine.events.updated` for global legacy callers and delegates delta values to the private scheduler.

- [ ] **Step 3: Preserve legacy wrapper validation behavior**

Ensure:

- `Timeout` treats missing/malformed/negative `:delay-ms` as zero, matching current compatibility behavior.
- `Debouncer` treats missing/malformed/negative initial `:delay-ms` as zero, matching current compatibility behavior.
- `Debouncer:set-delay-ms` still requires a finite non-negative number and throws the existing style of error.
- `Interval` still requires positive finite `:interval-ms`.
- `:delay-ms` and `:interval-ms` are not accepted by `RuntimeScheduler` itself.

- [ ] **Step 4: Run validation and commit Task 3**

Run:

```bash
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-runtime-timers:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-runtime-scheduler:main
```

Commit:

```bash
git add assets/lua/runtime-timers.fnl assets/lua/tests/test-runtime-timers.fnl
git commit -m "refactor(lua): route runtime timers through scheduler"
```

Report compile-check evidence before constraints and tests. Include a constraint-impact note.

---

### Task 4: Runtime Scheduler Documentation and Acceptance Updates

**Files:**
- Create: `docs/dev/features/runtime-scheduler.md`
- Modify: `docs/dev/features/temporal.md`
- Modify: `docs/dev/features/temporal-complete-library.md`
- Modify: `docs/dev/features/temporal-complete-acceptance.md`
- Modify: `docs/dev/features/hosted-runtime-apps.md`

**Interfaces:**
- Consumes: public API from Tasks 1-3.
- Produces: developer documentation and Track 12 acceptance evidence.

- [ ] **Step 1: Create runtime scheduler docs**

Create `docs/dev/features/runtime-scheduler.md` with sections:

- Overview and boundary: Fennel runtime policy, not native temporal core.
- Public API: `RuntimeScheduler.create`, `schedule-once`, `schedule-every`, `schedule-recurrence`, `advance`, `update`, `clear`, `drop`, `list`, handle methods.
- Time model: exact durations, fixed-clock creation, manual advance.
- Catch-up policy: one-shot, interval, equal deadlines, pause, step, cancel during callback, clear during callback.
- Recurrence: explicit `:zone-id`, `:disambiguation :reject` default, `:limit`, callback payload `{:scheduled-at instant :occurrence-index n}`.
- Host scheduler integration: typed methods and pause/step semantics.
- RuntimeTimers compatibility: millisecond keys only remain in wrappers.
- Validation commands.

- [ ] **Step 2: Update temporal docs and roadmap**

Update:

- `docs/dev/features/temporal.md` to link the runtime scheduler page and state scheduler policy is outside the native temporal core.
- `docs/dev/features/temporal-complete-library.md` current status to include Track 12 complete once implemented.
- Remove Track 12 from the future-work wording while leaving Track 13 future work.

- [ ] **Step 3: Update acceptance matrix**

In `docs/dev/features/temporal-complete-acceptance.md`, add Track 12 acceptance evidence commands:

```bash
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-runtime-scheduler:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-runtime-timers:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-app-host-services:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-standalone-app-runtime:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

- [ ] **Step 4: Update hosted runtime docs**

Update `docs/dev/features/hosted-runtime-apps.md` to document:

- existing facet registry remains;
- typed methods `schedule-once`, `schedule-every`, `schedule-recurrence`;
- `update` is paused by `set-paused true`;
- `step` advances typed scheduled work and facets while paused.

- [ ] **Step 5: Run docs and focused validation; commit Task 4**

Run:

```bash
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-runtime-scheduler:main
```

Commit:

```bash
git add docs/dev/features/runtime-scheduler.md docs/dev/features/temporal.md docs/dev/features/temporal-complete-library.md docs/dev/features/temporal-complete-acceptance.md docs/dev/features/hosted-runtime-apps.md
git commit -m "docs(lua): document runtime scheduler"
```

Report compile-check evidence before constraints and tests. Include a constraint-impact note.

---

### Task 5: Final Track 12 Validation

**Files:**
- No planned source changes.
- If validation finds a real repository defect, fix only through the normal implementer/reviewer loop.

**Interfaces:**
- Consumes: all public APIs and tests from Tasks 1-4.
- Produces: final validation evidence for finishing.

- [ ] **Step 1: Verify working tree status**

Run:

```bash
```

Expected: no uncommitted changes except SDD coordination files managed by the supervisor.

- [ ] **Step 2: Run final validation ladder**

Run:

```bash
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-runtime-scheduler:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-runtime-timers:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-app-host-services:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-standalone-app-runtime:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

- [ ] **Step 3: Record final validation evidence**

The implementer report must list each command, result, and coverage rationale:

- compile check covers all changed `.fnl` files;
- constraints cover Space structural rules;
- focused tests cover typed scheduler, compatibility wrappers, host service integration, and standalone runtime integration;
- `make test` covers broad runtime regression risk.

- [ ] **Step 4: Do not create an empty commit**

If validation passes without changes, do not commit. If a repository fix is required, implement the minimal fix, rerun covering validation, and commit with a focused message.

---

## Final Acceptance

- `RuntimeScheduler` exists with one-shot, interval, recurrence, manual advance, update, clear, drop, list, and handle methods.
- New typed scheduler options reject unknown keys and legacy millisecond aliases.
- Recurrence scheduling requires explicit `:zone-id` and exposes the public callback payload `{:scheduled-at instant :occurrence-index n}`.
- Host scheduler typed methods work with pause and step semantics.
- Existing `RuntimeTimers` wrappers remain available and behavior-compatible.
- Callback failures propagate loudly.
- Fixed-clock tests are deterministic.
- Track 12 docs and acceptance matrix are updated.
- Validation ladder passes locally, and finishing/PR CI is the integration gate.
