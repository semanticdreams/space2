# Temporal Calendar Periods Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add bounded calendar period records and civil calendar arithmetic for `PlainDateTime` while preserving exact nanosecond `Duration` behavior.

**Architecture:** Native C++ adds one correctness-critical `PlainDateTime::add_calendar` helper. Fennel owns public `Temporal.period` records, date-only ISO-like parsing/formatting, validation policy, and docs.

**Tech Stack:** C++17 temporal core, Howard Hinnant `date/tz`, sol2 Lua bindings, Space Fennel modules/tests, CMake/CTest, Space-native Fennel check/constraints/test tooling.

## Global Constraints

- Add a bounded calendar `Period` layer for ISO proleptic Gregorian civil date arithmetic.
- Keep exact `Duration` nanoseconds-only and unchanged.
- Keep public period records in Fennel while using native helpers for correctness-critical civil arithmetic on `PlainDateTime`.
- Support canonical period fields `:years`, `:months`, `:weeks`, and `:days`.
- Support date-only ISO-like parsing and formatting such as `P1Y2M3W4D`, `P0D`, and `-P1M`.
- Apply periods only to `PlainDateTime` in this slice.
- Make all invalid or unsupported forms fail loudly.
- Preserve all existing temporal APIs and behavior.
- Do not add native C++ `Period` userdata.
- Do not add calendar units to exact `Duration`.
- Do not apply periods to `Instant` or `ZonedDateTime`.
- Do not add DST-aware or timezone-aware period arithmetic.
- Do not implement monthly/yearly recurrence expansion.
- Do not implement ISO interval `duration/start`, `start/duration`, or `duration/end` forms.
- Do not implement `Period.between` or calendar diffing.
- Do not add time-based period fields such as hours, minutes, seconds, or nanoseconds.
- Do not add non-Gregorian calendars, localization, business calendars, holiday calendars, ICU, CLDR, or new third-party runtime dependencies.
- Period addition to `PlainDateTime` combines years/months into one total-month shift, clamps the day-of-month once, then adds weeks/days, preserving time-of-day and nanoseconds.
- No API may silently default to host-local timezone behavior.

---

## File Structure

- `src/temporal.h` / `src/temporal.cpp` — native `PlainDateTime::add_calendar`.
- `src/lua_temporal_core.cpp` — `TemporalPlainDateTime:add-calendar` binding.
- `tests/test_temporal_core.cpp` — native calendar arithmetic tests.
- `tests/test_lua_temporal_core_binding.cpp` — binding tests.
- `assets/lua/temporal/period.fnl` — public period records and operations.
- `assets/lua/temporal.fnl` — export `period` namespace.
- `assets/lua/tests/test-temporal-period.fnl` — focused Fennel period tests.
- `assets/lua/tests/fast.fnl` — register focused period tests.
- `docs/dev/features/temporal-calendar-periods.md` — developer guide.
- `docs/dev/features/index.md`, `docs/dev/features/temporal.md`, `docs/dev/features/temporal-intervals.md`, `docs/dev/features/temporal-parsing-recurrence.md` — doc links and deferral updates.

## Public API Additions

```fennel
Temporal.period.from
Temporal.period.parse
Temporal.period.format
Temporal.period.negate
Temporal.period.add-to-plain-date-time
Temporal.period.subtract-from-plain-date-time
```

Period record shape:

```fennel
{:kind :period
 :years integer
 :months integer
 :weeks integer
 :days integer}
```

---

### Task 1: Native PlainDateTime Calendar Arithmetic

**Files:**
- Modify: `src/temporal.h`
- Modify: `src/temporal.cpp`
- Modify: `tests/test_temporal_core.cpp`

**Interfaces:**
- Consumes: existing `PlainDateTime` and native checked arithmetic helpers.
- Produces: `PlainDateTime PlainDateTime::add_calendar(std::int64_t years, std::int64_t months, std::int64_t weeks, std::int64_t days) const`.

- [ ] **Step 1: Add failing native tests.**
  In `tests/test_temporal_core.cpp`, add and register `test_plain_date_time_add_calendar_period`:

  ```cpp
  void test_plain_date_time_add_calendar_period()
  {
      expect_eq(PlainDateTime::parse("2026-01-31T10:11:12").add_calendar(0, 1, 0, 0).to_string(), std::string("2026-02-28T10:11:12"));
      expect_eq(PlainDateTime::parse("2028-01-31T10:11:12").add_calendar(0, 1, 0, 0).to_string(), std::string("2028-02-29T10:11:12"));
      expect_eq(PlainDateTime::parse("2028-02-29T10:11:12").add_calendar(1, 0, 0, 0).to_string(), std::string("2029-02-28T10:11:12"));
      expect_eq(PlainDateTime::parse("2026-01-31T10:11:12").add_calendar(0, 2, 0, 0).to_string(), std::string("2026-03-31T10:11:12"));
      expect_eq(PlainDateTime::parse("2026-03-31T10:11:12").add_calendar(0, -1, 0, 0).to_string(), std::string("2026-02-28T10:11:12"));
      expect_eq(PlainDateTime::parse("2026-01-30T10:11:12").add_calendar(1, 2, 1, 3).to_string(), std::string("2027-04-09T10:11:12"));
      expect_throws([] { PlainDateTime::parse("2262-04-11T23:47:16.854775807").add_calendar(0, 0, 0, 1); });
  }
  ```

- [ ] **Step 2: Verify the native test fails before implementation.**
  Run:

  ```bash
  make build
  ctest --test-dir build -R test_temporal_core --output-on-failure
  ```

  Expected before implementation: compile failure because `PlainDateTime::add_calendar` is missing.

- [ ] **Step 3: Add native declaration.**
  Add this public method to `PlainDateTime` in `src/temporal.h`:

  ```cpp
  PlainDateTime add_calendar(std::int64_t years, std::int64_t months, std::int64_t weeks, std::int64_t days) const;
  ```

- [ ] **Step 4: Implement native arithmetic.**
  In `src/temporal.cpp`, implement the documented policy: split date/time, combine `years * 12 + months`, shift target year/month, clamp original day once to target month length, then add `weeks * 7 + days`, preserve time-of-day, and use existing checked range helpers.

- [ ] **Step 5: Validate focused native surface.**
  Run:

  ```bash
  make build
  ctest --test-dir build -R test_temporal_core --output-on-failure
  ```

  Expected: pass.

- [ ] **Step 6: Commit after review approval.**
  Commit message: `feat(temporal): add calendar arithmetic helper`.

---

### Task 2: Lua Binding and Fennel Period Facade

**Files:**
- Modify: `src/lua_temporal_core.cpp`
- Modify: `tests/test_lua_temporal_core_binding.cpp`
- Create: `assets/lua/temporal/period.fnl`
- Modify: `assets/lua/temporal.fnl`
- Create: `assets/lua/tests/test-temporal-period.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `PlainDateTime::add_calendar`.
- Produces: Lua method `plain:add-calendar(fields)` and public `Temporal.period` functions.

- [ ] **Step 1: Add failing Lua binding assertions.**
  In `tests/test_lua_temporal_core_binding.cpp`, add assertions equivalent to:

  ```lua
  local jan31 = core["plain-date-time"].parse("2026-01-31T10:11:12")
  local feb28 = jan31["add-calendar"](jan31, { months = 1 })
  assert(feb28["to-string"](feb28) == "2026-02-28T10:11:12")
  local start = core["plain-date-time"].parse("2026-01-30T10:11:12")
  local combined = start["add-calendar"](start, { years = 1, months = 2, weeks = 1, days = 3 })
  assert(combined["to-string"](combined) == "2027-04-09T10:11:12")
  assert(not pcall(function() return jan31["add-calendar"](jan31, { monthz = 1 }) end))
  assert(not pcall(function() return jan31["add-calendar"](jan31, { months = 1.5 }) end))
  ```

- [ ] **Step 2: Bind `add-calendar`.**
  In `src/lua_temporal_core.cpp`, add a `TemporalPlainDateTime` method named `add-calendar`. It must accept a table with only `years`, `months`, `weeks`, and `days`; default missing fields to `0`; reject unknown keys and non-integer values; then call `self.add_calendar(years, months, weeks, days)`.

- [ ] **Step 3: Add focused Fennel tests.**
  Create `assets/lua/tests/test-temporal-period.fnl` with this coverage:

  ```fennel
  (local tests [])
  (local Temporal (require :temporal))
  (fn assert-error [f message] (local (ok err) (pcall f)) (assert (not ok) message) err)

  (fn period-records-parse-format []
    (local p (Temporal.period.from {:years 1 :months 2 :weeks 3 :days 4}))
    (assert (= p.kind :period))
    (assert (= (Temporal.period.format p) "P1Y2M3W4D"))
    (assert (= (Temporal.period.format (Temporal.period.parse "P0D")) "P0D"))
    (assert (= (Temporal.period.format (Temporal.period.parse "-P1M")) "-P1M"))
    (assert (= (Temporal.period.format (Temporal.period.negate p)) "-P1Y2M3W4D")))

  (fn period-validation []
    (assert-error #(Temporal.period.from {:monthz 1}) "unknown period key should throw")
    (assert-error #(Temporal.period.from {:months 1.5}) "fractional period field should throw")
    (assert-error #(Temporal.period.from {:months 1 :days -1}) "mixed signs should throw")
    (assert-error #(Temporal.period.parse "PT1H") "time period should throw")
    (assert-error #(Temporal.period.parse "P1D2M") "reordered period should throw")
    (assert-error #(Temporal.duration.from {:months 1}) "duration months should still throw"))

  (fn period-plain-date-time-arithmetic []
    (local jan31 (Temporal.plain-date-time.parse "2026-01-31T10:11:12"))
    (local feb28 (Temporal.period.add-to-plain-date-time jan31 (Temporal.period.parse "P1M")))
    (assert (= (feb28:to-string) "2026-02-28T10:11:12"))
    (local leap (Temporal.plain-date-time.parse "2028-02-29T10:11:12"))
    (local next-year (Temporal.period.add-to-plain-date-time leap (Temporal.period.parse "P1Y")))
    (assert (= (next-year:to-string) "2029-02-28T10:11:12"))
    (local previous-month (Temporal.period.subtract-from-plain-date-time jan31 (Temporal.period.parse "P1M")))
    (assert (= (previous-month:to-string) "2025-12-31T10:11:12"))
    (assert-error #(Temporal.period.add-to-plain-date-time (Temporal.standard.parse-instant "2026-01-31T00:00:00Z") (Temporal.period.parse "P1M"))
                  "period target must be plain date-time"))
  ```

  Register the three tests and return `{:name "temporal-period" :tests tests :main main}` using the same runner style as other focused tests.

- [ ] **Step 4: Implement `assets/lua/temporal/period.fnl`.**
  Requirements:
  - Factory receives base `Temporal` table.
  - `from` validates keys `:years`, `:months`, `:weeks`, `:days`, defaults missing fields to `0`, requires finite integers, rejects mixed signs, and returns canonical records with all fields.
  - `parse` accepts only `P0D`, `P1Y`, `P1Y2M3W4D`, and negative forms with one leading `-`; it rejects `P`, `PT1H`, fractions, reordered fields, embedded signs, and unknown suffixes.
  - `format` emits `P0D` for zero and one leading `-` for negative periods.
  - `negate` flips all four fields.
  - `add-to-plain-date-time` validates the period and calls `plain:add-calendar`.
  - `subtract-from-plain-date-time` calls `add-to-plain-date-time` with `negate`.

- [ ] **Step 5: Export and register.**
  Update `assets/lua/temporal.fnl` to return `:period (create-period base)`. Add `:tests.test-temporal-period` to `assets/lua/tests/fast.fnl` near the other temporal tests.

- [ ] **Step 6: Validate focused binding/Fennel surface.**
  Run:

  ```bash
  make build
  ctest --test-dir build -R test_lua_temporal_core_binding --output-on-failure
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/period.fnl --file assets/lua/tests/test-temporal-period.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-period:main
  ```

  Expected: all pass.

- [ ] **Step 7: Commit after review approval.**
  Commit message: `feat(temporal): add calendar period facade`.

---

### Task 3: Developer Documentation

**Files:**
- Create: `docs/dev/features/temporal-calendar-periods.md`
- Modify: `docs/dev/features/index.md`
- Modify: `docs/dev/features/temporal.md`
- Modify: `docs/dev/features/temporal-intervals.md`
- Modify: `docs/dev/features/temporal-parsing-recurrence.md`

**Interfaces:**
- Consumes: public `Temporal.period` API from Task 2.
- Produces: developer documentation and updated deferral map.

- [ ] **Step 1: Create calendar periods feature page.**
  Create `docs/dev/features/temporal-calendar-periods.md` with sections: `# Temporal Calendar Periods`, `## Layering model`, `## Calendar arithmetic policy`, `## Temporal.period`, `## Unsupported forms and deferred scope`, and `## Validation`.

- [ ] **Step 2: Document examples and deferrals.**
  Include examples for `Temporal.period.parse`, `format`, `add-to-plain-date-time`, and `subtract-from-plain-date-time`. The deferred section must name native Period userdata, Instant/ZonedDateTime period arithmetic, DST-aware arithmetic, monthly/yearly recurrence expansion, ISO interval duration endpoint forms, Period.between, time-based fields, non-Gregorian calendars, localization, business calendars, and holiday calendars.

- [ ] **Step 3: Update existing docs.**
  Add the page to `docs/dev/features/index.md`. Update `docs/dev/features/temporal.md` to say exact `Duration` remains nanoseconds-only and calendar periods live in `Temporal.period`. Update `docs/dev/features/temporal-intervals.md` to state period records exist but ISO duration endpoint forms remain deferred. Update `docs/dev/features/temporal-parsing-recurrence.md` to say calendar period arithmetic exists while monthly/yearly recurrence expansion remains deferred.

- [ ] **Step 4: Run docs term check.**
  Run:

  ```bash
  rg "Temporal Calendar Periods|Temporal.period|calendar period|Duration remains nanoseconds|duration/start|monthly/yearly recurrence|ZonedDateTime period" docs/dev/features/temporal-calendar-periods.md docs/dev/features/index.md docs/dev/features/temporal.md docs/dev/features/temporal-intervals.md docs/dev/features/temporal-parsing-recurrence.md
  ```

  Expected: all terms are present.

- [ ] **Step 5: Commit after review approval.**
  Commit message: `docs(temporal): document calendar periods`.

---

### Task 4: Final Validation

**Files:**
- No source files expected unless validation reveals a reviewed fix is required.

**Interfaces:**
- Consumes: completed native helper, binding, Fennel facade, tests, and docs.
- Produces: final validation evidence.

- [ ] **Step 1: Build and native validation.**
  Run:

  ```bash
  make build
  ctest --test-dir build -R 'test_temporal_core|test_lua_temporal_core_binding' --output-on-failure
  ```

- [ ] **Step 2: Fennel validation.**
  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/period.fnl --file assets/lua/tests/test-temporal-period.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-period:main
  ```

- [ ] **Step 3: Full local suite.**
  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- [ ] **Step 4: Report coverage rationale.**
  Report that validation covers native civil arithmetic, Lua binding, Fennel API/tests, docs, and broad regression risk. PR CI remains the full integration gate.

---

## Final Acceptance

- `require :temporal` exposes `period`.
- Exact `Duration` remains nanoseconds-only; `Temporal.duration.from {:months 1}` still throws.
- `Temporal.period` supports canonical date-based records, parse/format, negate, add, and subtract.
- End-of-month clamp policy matches the spec.
- Unsupported forms fail loudly.
- Docs explain supported behavior and deferrals.
- Focused and broad validation pass.
