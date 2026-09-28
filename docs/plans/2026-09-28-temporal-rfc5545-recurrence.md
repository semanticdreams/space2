# Temporal RFC5545 Recurrence Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement full in-scope RFC5545 RRULE parsing, serialization, validation, and `PlainDateTime` occurrence expansion for `Temporal.recurrence`.

**Architecture:** Keep `Temporal.recurrence` as the public facade while splitting rule normalization and occurrence expansion into focused Fennel modules. Replace the current patched generator/filter loops with a candidate-set engine that expands frequency buckets, applies RFC5545 selectors, sorts candidates, applies `BYSETPOS`, and then applies bounds.

**Tech Stack:** Space Fennel, native `temporal-core` `PlainDateTime`/`Duration` bindings, existing `Temporal.period` and `Temporal.standard` facades, project-native `tools.fennel-check`, constraints, and Fennel test runner.

## Global Constraints

- No host-local timezone defaulting.
- Exact `Duration` remains nanoseconds-only.
- Calendar periods, business days, localized calendars, and exact durations remain separate concepts.
- Native temporal primitives stay independent from natural-language parsing, recurrence policy, ICU/CLDR presentation, holiday policy, provider loading, and scheduler product semantics.
- Runtime temporal work does not fetch network data.
- Preserve public API names: `Temporal.recurrence.from`, `Temporal.recurrence.parse-rrule`, `Temporal.recurrence.to-rrule`, and `Temporal.recurrence.occurrences`.
- This track implements standalone RRULE expansion over `PlainDateTime`; recurrence sets, ICS/VEVENT, explicit-zone expansion, DST policy, and UTC/instant `UNTIL` expansion remain explicit errors for later roadmap tracks.
- Use canonical option keys only; do not add legacy aliases.
- Unsupported inputs must fail loudly, not silently no-op.
- Reject `BYSECOND=60` because current `PlainDateTime` cannot represent leap seconds.

---

## File Structure

- Modify `assets/lua/temporal.fnl`: pass `base.duration` into the recurrence factory for sub-daily exact-duration stepping.
- Modify `assets/lua/temporal/recurrence.fnl`: shrink to the public facade and dependency validation; delegate to rule and engine modules.
- Create `assets/lua/temporal/recurrence/rule.fnl`: own canonical option validation, normalized rule construction, RRULE parsing, RRULE serialization, and invalid-rule diagnostics.
- Create `assets/lua/temporal/recurrence/engine.fnl`: own bounded occurrence expansion, frequency interval buckets, selector application, deterministic candidate ordering, `BYSETPOS`, and satisfiability/infinite-loop guards.
- Modify `assets/lua/tests/test-temporal-parsing-recurrence.fnl`: keep existing tests and adjust only if behavior becomes a documented full-RFC behavior.
- Create `assets/lua/tests/test-temporal-recurrence-rfc5545.fnl`: focused RFC5545 parser/serializer/engine tests.
- Modify `assets/lua/tests/fast.fnl`: register `:tests.test-temporal-recurrence-rfc5545` near the existing temporal recurrence tests.
- Modify `docs/dev/features/temporal-parsing-recurrence.md`: document completed RRULE scope and next-track boundaries.
- Modify `docs/dev/features/temporal-complete-acceptance.md`: update the RFC5545 recurrence evidence row after implementation validation.

---

### Task 1: Extract Rule Module With Current-Behavior Parity

**Files:**
- Create: `assets/lua/temporal/recurrence/rule.fnl`
- Modify: `assets/lua/temporal/recurrence.fnl`
- Test: `assets/lua/tests/test-temporal-parsing-recurrence.fnl`

**Interfaces:**
- Consumes: current rule option shape accepted by `Temporal.recurrence.from`.
- Produces:
  - `rule.from(options: table) -> table`
  - `rule.parse-rrule(text: string) -> table`
  - `rule.to-rrule(rule: table) -> string`
  - `rule.parse-until(standard: table, text: string) -> table`
  - `rule.normalize-occurrence-options(options: table|nil) -> table`
  - `rule.occurrence-bounds(standard: table, recurrence-rule: table, occurrence-options: table) -> table`
  - `rule.day-to-number: table`
  - `rule.number-to-day: table`

- [ ] **Step 1: Move validation helpers into `rule.fnl`**

  Move these existing responsibilities out of `recurrence.fnl` without changing behavior: frequency maps, valid option keys, positive integer validation, BYDAY/BYMONTH/BYMONTHDAY normalization, RRULE splitting, `UNTIL` parsing helpers, RRULE parser, RRULE serializer, occurrence option normalization, and occurrence bounds.

  The module return shape must be:

  ```fennel
  {:from from
   :parse-rrule parse-rrule
   :to-rrule to-rrule
   :parse-until parse-until
   :normalize-occurrence-options normalize-occurrence-options
   :occurrence-bounds occurrence-bounds
   :day-to-number day-to-number
   :number-to-day number-to-day}
  ```

- [ ] **Step 2: Delegate public facade calls**

  In `assets/lua/temporal/recurrence.fnl`, require the rule module and wire:

  ```fennel
  (local rule (require :temporal/recurrence/rule))
  ```

  The public return table from `create` must still expose:

  ```fennel
  {:from rule.from
   :parse-rrule rule.parse-rrule
   :to-rrule rule.to-rrule
   :occurrences (fn [input-rule dtstart options]
                  ...)}
  ```

- [ ] **Step 3: Keep occurrence implementation in the facade for this task**

  Existing occurrence helper functions may remain in `recurrence.fnl` for Task 1. Change only the call sites that now use `rule.from`, `rule.normalize-occurrence-options`, `rule.occurrence-bounds`, `rule.day-to-number`, and `rule.number-to-day`.

- [ ] **Step 4: Run touched-file compile check**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/recurrence.fnl --file assets/lua/temporal/recurrence/rule.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  ```

  Expected: pass.

- [ ] **Step 5: Run focused regression test**

  Run:

  ```bash
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected: existing recurrence tests pass with the same count as before this task.

- [ ] **Step 6: Commit Task 1**

  Commit:

  ```bash
  git add assets/lua/temporal/recurrence.fnl assets/lua/temporal/recurrence/rule.fnl assets/lua/tests/test-temporal-parsing-recurrence.fnl
  git commit -m "refactor(temporal): split recurrence rule parsing"
  ```

---

### Task 2: Add Candidate-Set Engine With Existing-Behavior Parity

**Files:**
- Create: `assets/lua/temporal/recurrence/engine.fnl`
- Modify: `assets/lua/temporal/recurrence.fnl`
- Test: `assets/lua/tests/test-temporal-parsing-recurrence.fnl`

**Interfaces:**
- Consumes: `rule.from`, `rule.occurrence-bounds`, weekday maps from Task 1.
- Produces:
  - `engine.occurrences(deps: table, input-rule: table, dtstart: PlainDateTime, options: table|nil) -> table`

- [ ] **Step 1: Create `engine.fnl` with dependency contract**

  Add an engine module returning:

  ```fennel
  {:occurrences occurrences}
  ```

  `occurrences` must validate that `deps.period.add-to-plain-date-time`, `deps.standard.parse-plain-date-time`, and `deps.plain-date-time.from-fields` exist before expansion. It must call `rule.from`, normalize occurrence options, and compute bounds through the rule module.

- [ ] **Step 2: Port existing expansion helpers into `engine.fnl`**

  Move daily, weekly, monthly, yearly, generated-candidate, filter, sorting, bound, and satisfiability helper functions from `recurrence.fnl` into `engine.fnl`. Preserve current results for:

  ```fennel
  {:freq :daily :interval 2 :count 3}
  {:freq :weekly :by-day [:mo :we] :count 4}
  {:freq :monthly :by-month-day [31] :count 3}
  {:freq :yearly :by-month [2] :by-month-day [29] :count 2}
  ```

- [ ] **Step 3: Delegate facade occurrence expansion**

  In `recurrence.fnl`, require the engine module and delegate:

  ```fennel
  (local engine (require :temporal/recurrence/engine))
  ...
  :occurrences (fn [input-rule dtstart options]
                 (engine.occurrences deps input-rule dtstart options))
  ```

- [ ] **Step 4: Keep current unsupported errors stable**

  Existing tests for UTC `UNTIL`, unbounded expansion, and unsupported unsatisfiable expansions must still fail loudly with messages containing the previous broad text, such as `unsupported temporal recurrence expansion` or `temporal recurrence expansion requires count, limit, or until`.

- [ ] **Step 5: Run compile, constraints, and focused regression**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/recurrence.fnl --file assets/lua/temporal/recurrence/rule.fnl --file assets/lua/temporal/recurrence/engine.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  make constraints
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected: all commands pass.

- [ ] **Step 6: Commit Task 2**

  Commit:

  ```bash
  git add assets/lua/temporal/recurrence.fnl assets/lua/temporal/recurrence/engine.fnl assets/lua/tests/test-temporal-parsing-recurrence.fnl
  git commit -m "refactor(temporal): add recurrence expansion engine"
  ```

---

### Task 3: Parse and Serialize Full RFC5545 RRULE Surface

**Files:**
- Modify: `assets/lua/temporal/recurrence/rule.fnl`
- Create: `assets/lua/tests/test-temporal-recurrence-rfc5545.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `rule.from`, `rule.parse-rrule`, `rule.to-rrule` from Task 1.
- Produces: normalized rules with canonical keys `:by-second`, `:by-minute`, `:by-hour`, `:by-year-day`, `:by-week-no`, `:by-set-pos`, and `:week-start`.

- [ ] **Step 1: Add failing parser/serializer tests**

  Create `assets/lua/tests/test-temporal-recurrence-rfc5545.fnl` with a local `tests` array and runner shape matching existing Fennel tests. Include these initial tests:

  ```fennel
  (fn parses-sub-daily-frequencies []
    (assert= (. (Temporal.recurrence.parse-rrule "RRULE:FREQ=SECONDLY;COUNT=2") :freq) :secondly)
    (assert= (. (Temporal.recurrence.parse-rrule "RRULE:FREQ=MINUTELY;COUNT=2") :freq) :minutely)
    (assert= (. (Temporal.recurrence.parse-rrule "RRULE:FREQ=HOURLY;COUNT=2") :freq) :hourly))

  (fn parses-new-selector-lists []
    (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;BYSECOND=0,30;BYMINUTE=5;BYHOUR=9,17;BYYEARDAY=1,-1;BYWEEKNO=1,-1;BYMONTH=1,12;BYSETPOS=1,-1;WKST=SU"))
    (assert= (. rule :by-second 2) 30)
    (assert= (. rule :by-minute 1) 5)
    (assert= (. rule :by-hour 2) 17)
    (assert= (. rule :by-year-day 2) -1)
    (assert= (. rule :by-week-no 2) -1)
    (assert= (. rule :by-set-pos 2) -1)
    (assert= rule.week-start :su))

  (fn parses-ordinal-byday []
    (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYDAY=1MO,-1FR;COUNT=4"))
    (assert= (. rule :by-day 1 :weekday) :mo)
    (assert= (. rule :by-day 1 :ordinal) 1)
    (assert= (. rule :by-day 2 :weekday) :fr)
    (assert= (. rule :by-day 2 :ordinal) -1))

  (fn serializes-full-field-order []
    (assert= (Temporal.recurrence.to-rrule {:freq :hourly :interval 2 :count 3 :by-second [0 30] :by-minute [15] :by-hour [9] :by-day [:mo] :by-month-day [1 -1] :by-year-day [1 -1] :by-week-no [1] :by-month [1] :by-set-pos [1 -1] :week-start :su})
             "RRULE:FREQ=HOURLY;INTERVAL=2;COUNT=3;BYSECOND=0,30;BYMINUTE=15;BYHOUR=9;BYDAY=MO;BYMONTHDAY=1,-1;BYYEARDAY=1,-1;BYWEEKNO=1;BYMONTH=1;BYSETPOS=1,-1;WKST=SU"))
  ```

  Also include invalid tests for `BYSECOND=60`, `BYMINUTE=60`, `BYHOUR=24`, `BYYEARDAY=0`, `BYYEARDAY=367`, `BYWEEKNO=0`, `BYWEEKNO=54`, `BYSETPOS=0`, `BYSETPOS=367`, malformed `BYDAY=1`, malformed `BYDAY=MO1`, and duplicate `WKST`.

- [ ] **Step 2: Extend canonical validation in `rule.fnl`**

  Add valid frequencies `:secondly`, `:minutely`, and `:hourly`. Add valid option keys for `:by-second`, `:by-minute`, `:by-hour`, `:by-year-day`, `:by-week-no`, `:by-set-pos`, and `:week-start`.

  Validation ranges:

  - `BYSECOND`: integer `0..59`
  - `BYMINUTE`: integer `0..59`
  - `BYHOUR`: integer `0..23`
  - `BYMONTH`: integer `1..12`
  - `BYMONTHDAY`: integer `-31..-1` or `1..31`
  - `BYYEARDAY`: integer `-366..-1` or `1..366`
  - `BYWEEKNO`: integer `-53..-1` or `1..53`
  - `BYSETPOS`: integer `-366..-1` or `1..366`
  - `WKST`: weekday keyword `:mo`, `:tu`, `:we`, `:th`, `:fr`, `:sa`, or `:su`; default is `:mo`

- [ ] **Step 3: Normalize `BYDAY` entries**

  Accept existing simple weekday keywords and new ordinal entries. Normalize parsed ordinal RRULE tokens to tables:

  ```fennel
  {:weekday :fr :ordinal -1}
  ```

  Keep simple programmatic entries as weekday keywords when callers pass `[:mo :we]`; serializer must emit both shapes correctly.

- [ ] **Step 4: Register focused test module**

  Add `:tests.test-temporal-recurrence-rfc5545` immediately after `:tests.test-temporal-parsing-recurrence` in `assets/lua/tests/fast.fnl`.

- [ ] **Step 5: Run expected RED then GREEN validation**

  Before implementation, run the new focused test once and record the expected failures in the implementer report. After implementation, run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/recurrence/rule.fnl --file assets/lua/tests/test-temporal-recurrence-rfc5545.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-recurrence-rfc5545:main
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected: all commands pass after implementation.

- [ ] **Step 6: Commit Task 3**

  Commit:

  ```bash
  git add assets/lua/temporal/recurrence/rule.fnl assets/lua/tests/test-temporal-recurrence-rfc5545.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(temporal): parse full RFC5545 recurrence rules"
  ```

---

### Task 4: Implement Date Selector Candidate Semantics

**Files:**
- Modify: `assets/lua/temporal/recurrence/engine.fnl`
- Modify: `assets/lua/tests/test-temporal-recurrence-rfc5545.fnl`

**Interfaces:**
- Consumes: normalized selector fields from `rule.fnl`.
- Produces: correct `PlainDateTime` expansion for `DAILY`, `WEEKLY`, `MONTHLY`, and `YEARLY` with `BYDAY`, `BYMONTHDAY`, `BYYEARDAY`, `BYWEEKNO`, `BYMONTH`, `BYSETPOS`, and `WKST`.

- [ ] **Step 1: Add failing date-selector tests**

  Add focused tests for these exact examples:

  ```fennel
  (fn expands-last-friday-of-month []
    (local dtstart (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
    (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYDAY=-1FR;COUNT=3"))
    (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-30T09:00:00" "2026-02-27T09:00:00" "2026-03-27T09:00:00"]))

  (fn expands-negative-month-day []
    (local dtstart (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
    (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=3"))
    (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-31T09:00:00" "2026-02-28T09:00:00" "2026-03-31T09:00:00"]))

  (fn applies-bysetpos-after-sorting []
    (local dtstart (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
    (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=4"))
    (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-01T09:00:00" "2026-01-30T09:00:00" "2026-02-02T09:00:00" "2026-02-27T09:00:00"]))

  (fn expands-year-day-selectors []
    (local dtstart (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
    (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;BYYEARDAY=1,-1;COUNT=4"))
    (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-01T09:00:00" "2026-12-31T09:00:00" "2027-01-01T09:00:00" "2027-12-31T09:00:00"]))
  ```

  Add a weekly `WKST` test where `INTERVAL=2` changes selected weeks when `WKST=SU` compared with the default `WKST=MO`.

- [ ] **Step 2: Implement field extraction helpers**

  In `engine.fnl`, add helpers that read `candidate:fields()`, compare with `candidate:compare(other)`, compute days in month by probing `plain-date-time.from-fields`, compute day-of-year, compute ISO-like week number with configured week start, and build candidates while preserving `DTSTART` hour/minute/second/nanosecond.

- [ ] **Step 3: Implement frequency buckets**

  For each supported date frequency:

  - `DAILY`: bucket is one selected day per interval.
  - `WEEKLY`: bucket is a week starting on `rule.week-start`.
  - `MONTHLY`: bucket is one calendar month per interval.
  - `YEARLY`: bucket is one calendar year per interval.

  Each bucket must return a sorted array of candidate `PlainDateTime` values before bounds are applied.

- [ ] **Step 4: Apply date selectors**

  Implement selector behavior for `BYMONTH`, positive and negative `BYMONTHDAY`, positive and negative `BYYEARDAY`, positive and negative `BYWEEKNO`, simple and ordinal `BYDAY`, and `WKST`.

- [ ] **Step 5: Apply `BYSETPOS` inside each bucket**

  After candidates are filtered and sorted within a bucket, keep positions listed in `rule.by-set-pos`. Positive positions count from the start; negative positions count from the end. Out-of-range positions produce no candidate for that bucket.

- [ ] **Step 6: Run focused validation**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/recurrence/engine.fnl --file assets/lua/tests/test-temporal-recurrence-rfc5545.fnl
  make constraints
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-recurrence-rfc5545:main
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected: all commands pass.

- [ ] **Step 7: Commit Task 4**

  Commit:

  ```bash
  git add assets/lua/temporal/recurrence/engine.fnl assets/lua/tests/test-temporal-recurrence-rfc5545.fnl
  git commit -m "feat(temporal): expand RFC5545 calendar selectors"
  ```

---

### Task 5: Implement Sub-Daily Frequencies and Time Selectors

**Files:**
- Modify: `assets/lua/temporal.fnl`
- Modify: `assets/lua/temporal/recurrence.fnl`
- Modify: `assets/lua/temporal/recurrence/engine.fnl`
- Modify: `assets/lua/tests/test-temporal-recurrence-rfc5545.fnl`

**Interfaces:**
- Consumes: `base.duration.from` from `assets/lua/temporal.fnl` and native `PlainDateTime:add(Duration)`.
- Produces: occurrence expansion for `SECONDLY`, `MINUTELY`, `HOURLY`, `BYSECOND`, `BYMINUTE`, and `BYHOUR`.

- [ ] **Step 1: Add failing sub-daily tests**

  Add these tests to `test-temporal-recurrence-rfc5545.fnl`:

  ```fennel
  (fn expands-hourly-frequency []
    (local dtstart (Temporal.plain-date-time.parse "2026-01-01T09:30:00"))
    (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=HOURLY;INTERVAL=2;COUNT=4"))
    (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-01T09:30:00" "2026-01-01T11:30:00" "2026-01-01T13:30:00" "2026-01-01T15:30:00"]))

  (fn expands-minutely-frequency-across-hour []
    (local dtstart (Temporal.plain-date-time.parse "2026-01-01T23:58:00"))
    (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MINUTELY;COUNT=4"))
    (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-01T23:58:00" "2026-01-01T23:59:00" "2026-01-02T00:00:00" "2026-01-02T00:01:00"]))

  (fn expands-secondly-frequency-across-minute []
    (local dtstart (Temporal.plain-date-time.parse "2026-01-01T00:00:58"))
    (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=SECONDLY;COUNT=4"))
    (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-01T00:00:58" "2026-01-01T00:00:59" "2026-01-01T00:01:00" "2026-01-01T00:01:01"]))

  (fn applies-time-selectors []
    (local dtstart (Temporal.plain-date-time.parse "2026-01-01T00:00:00"))
    (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;BYHOUR=9,17;BYMINUTE=15;BYSECOND=30;COUNT=4"))
    (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-01T09:15:30" "2026-01-01T17:15:30" "2026-01-02T09:15:30" "2026-01-02T17:15:30"]))
  ```

- [ ] **Step 2: Pass duration dependency**

  In `assets/lua/temporal.fnl`, change recurrence construction to include duration:

  ```fennel
  (local recurrence (create-recurrence {:period period :standard standard :plain-date-time base.plain-date-time :duration base.duration}))
  ```

- [ ] **Step 3: Validate duration dependency for sub-daily expansion**

  In `recurrence.fnl` or `engine.fnl`, require `deps.duration.from` before running sub-daily frequencies or time selectors. Keep existing daily/weekly/monthly/yearly behavior working even when tests instantiate the factory with only existing deps, if such tests exist.

- [ ] **Step 4: Implement exact stepping**

  Use `dtstart:add(duration.from {:seconds n})` or equivalent exact durations for `SECONDLY`, `MINUTELY`, and `HOURLY`. Do not use calendar periods for sub-daily stepping.

- [ ] **Step 5: Apply time selectors**

  For bucket candidates that represent date-level intervals, generate selected hours, minutes, and seconds from `BYHOUR`, `BYMINUTE`, and `BYSECOND`. If a time selector is absent, use the corresponding `DTSTART` field for frequencies coarser than that field, matching RFC candidate semantics for the bounded `PlainDateTime` engine.

- [ ] **Step 6: Run focused validation**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/recurrence.fnl --file assets/lua/temporal/recurrence/engine.fnl --file assets/lua/tests/test-temporal-recurrence-rfc5545.fnl
  make constraints
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-recurrence-rfc5545:main
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected: all commands pass.

- [ ] **Step 7: Commit Task 5**

  Commit:

  ```bash
  git add assets/lua/temporal.fnl assets/lua/temporal/recurrence.fnl assets/lua/temporal/recurrence/engine.fnl assets/lua/tests/test-temporal-recurrence-rfc5545.fnl
  git commit -m "feat(temporal): expand sub-daily recurrence rules"
  ```

---

### Task 6: Final Diagnostics, Docs, and Acceptance Evidence

**Files:**
- Modify: `assets/lua/temporal/recurrence/rule.fnl`
- Modify: `assets/lua/temporal/recurrence/engine.fnl`
- Modify: `assets/lua/tests/test-temporal-recurrence-rfc5545.fnl`
- Modify: `assets/lua/tests/test-temporal-parsing-recurrence.fnl`
- Modify: `docs/dev/features/temporal-parsing-recurrence.md`
- Modify: `docs/dev/features/temporal-complete-acceptance.md`

**Interfaces:**
- Consumes: completed rule and engine modules from Tasks 1-5.
- Produces: documented full RFC5545 recurrence scope, invalid-rule diagnostics coverage, and final local validation evidence.

- [ ] **Step 1: Add diagnostics tests**

  Add tests asserting error messages contain the key name or unsupported boundary for:

  - `RRULE:FREQ=DAILY;BYSECOND=60`
  - `RRULE:FREQ=DAILY;WKST=XX`
  - `RRULE:FREQ=DAILY;BYDAY=0MO`
  - `RRULE:FREQ=DAILY;BYSETPOS=0`
  - `RRULE:FREQ=DAILY;COUNT=2;UNTIL=20260101T000000Z` when expanded
  - occurrence expansion without `COUNT`, local `UNTIL`, or `:limit`

- [ ] **Step 2: Add bounds-combination tests**

  Add tests proving:

  - `COUNT` stops before `:limit` when `COUNT` is smaller.
  - `:limit` stops before `COUNT` when `:limit` is smaller.
  - local/floating `UNTIL` is inclusive.
  - local/floating `UNTIL` stops selector-heavy rules without overshooting.

- [ ] **Step 3: Keep natural-language recurrence unchanged**

  Run existing natural recurrence tests in `test-temporal-parsing-recurrence.fnl`. If the full engine changes ordering for a natural `every Tuesday` recurrence, keep the documented output unchanged by preserving natural's emitted rule shape.

- [ ] **Step 4: Update recurrence docs**

  In `docs/dev/features/temporal-parsing-recurrence.md`, document:

  - full in-scope RRULE frequencies and selectors;
  - candidate-set ordering and `BYSETPOS` behavior;
  - `PlainDateTime`-only expansion;
  - explicit errors for recurrence sets, ICS, UTC/instant `UNTIL` expansion, explicit-zone/DST expansion, host-local timezone defaults, and leap-second `BYSECOND=60`;
  - examples for ordinal `BYDAY`, negative `BYMONTHDAY`, `BYYEARDAY`, `BYWEEKNO`, `BYSETPOS`, `WKST`, and sub-daily rules.

- [ ] **Step 5: Update acceptance matrix**

  In `docs/dev/features/temporal-complete-acceptance.md`, update the RFC5545 recurrence row evidence to mention full selector tests, sub-daily tests, candidate-set ordering tests, invalid-rule diagnostics, focused recurrence suite, fast-suite registration, and PR CI.

- [ ] **Step 6: Run full track validation**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/recurrence.fnl --file assets/lua/temporal/recurrence/rule.fnl --file assets/lua/temporal/recurrence/engine.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl --file assets/lua/tests/test-temporal-recurrence-rfc5545.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-recurrence-rfc5545:main
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
  rg "RFC5545|BYSETPOS|WKST|PlainDateTime|recurrence-set|DST" docs/dev/features/temporal-parsing-recurrence.md docs/dev/features/temporal-complete-acceptance.md
  git diff --check
  ```

  Expected: all commands pass. The fast suite may print existing diagnostic log noise, but the final test count must pass.

- [ ] **Step 7: Commit Task 6**

  Commit:

  ```bash
  git add assets/lua/temporal/recurrence/rule.fnl assets/lua/temporal/recurrence/engine.fnl assets/lua/tests/test-temporal-recurrence-rfc5545.fnl assets/lua/tests/test-temporal-parsing-recurrence.fnl docs/dev/features/temporal-parsing-recurrence.md docs/dev/features/temporal-complete-acceptance.md
  git commit -m "docs(temporal): document RFC5545 recurrence support"
  ```

---

## Final Whole-Branch Review and Finishing

- After Task 6 passes review, run a final whole-branch review against `origin/main`.
- Required final validation before integration:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/recurrence.fnl --file assets/lua/temporal/recurrence/rule.fnl --file assets/lua/temporal/recurrence/engine.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl --file assets/lua/tests/test-temporal-recurrence-rfc5545.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-recurrence-rfc5545:main
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
  git diff --check
  ```

- Then use the finishing-a-development-branch workflow: clean tree, current `origin/main`, push, PR, auto-merge/merge queue, and poll until merged.
