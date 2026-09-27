# Temporal RRULE BYMONTHDAY Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add bounded positive RRULE `BYMONTHDAY` support as a filter over existing temporal recurrence candidate streams.

**Architecture:** Mirror the existing `BYMONTH` implementation: normalize, parse, and serialize `:by-month-day`, then apply it as a conjunctive calendar filter over already-generated `PlainDateTime` candidates. Daily and weekly scanners continue to scan existing day streams; monthly and yearly rules remain anchor-based through `Temporal.period`. Bounded satisfiability guards prevent impossible filters from scanning forever.

**Tech Stack:** Space Fennel, `assets/lua/temporal/recurrence.fnl`, project temporal `PlainDateTime:fields`, `Temporal.period.add-to-plain-date-time`, project-native `tools.fennel-check`, `make constraints`, and focused Fennel recurrence tests.

## Global Constraints

- Add canonical recurrence option key `:by-month-day`.
- Parse RRULE month-day lists such as `BYMONTHDAY=1,15,31`.
- Serialize normalized `:by-month-day` values as `BYMONTHDAY=1,15,31`.
- Accept only positive integer month days `1..31`.
- Preserve caller/list order for parse/serialize; do not sort or deduplicate values.
- Apply `BYMONTHDAY` as an inclusion filter over existing candidates for `DAILY`, `WEEKLY`, `MONTHLY`, and `YEARLY` frequencies.
- Filter by the actual candidate day after monthly/yearly anchor clamping.
- Preserve existing `BYMONTH` filter behavior and allow `BYMONTH` and `BYMONTHDAY` to combine conjunctively.
- Preserve existing `BYDAY` behavior for daily/weekly rules and existing monthly/yearly `BYDAY` rejection.
- Preserve existing `COUNT`, `options.limit`, and local `UNTIL` behavior: numeric bounds count returned occurrences after filters, and `UNTIL` stops candidate scanning inclusively.
- Avoid unbounded scans for unsatisfiable filters by extending the existing satisfiability guards.
- `BYMONTHDAY=0`, `BYMONTHDAY=32`, negative values such as `BYMONTHDAY=-1`, empty members, and non-integer values throw.
- Programmatic `:by-month-day` must be a non-empty table of integers in `1..31`; non-table or empty values throw.
- Unknown RRULE keys still throw.
- Unsatisfiable `BYMONTHDAY` filter combinations throw `unsupported temporal recurrence expansion` instead of hanging.
- Exclude negative `BYMONTHDAY` semantics such as `-1` for the last day of the month.
- Exclude monthly/yearly generator semantics that create requested month days inside each period.
- Exclude full RFC5545 candidate-set expansion.
- Exclude `BYSETPOS`, `WKST`, `RDATE`, `EXDATE`, `BYWEEKNO`, and ordinal `BYDAY`.
- Exclude timezone-aware recurrence and DST handling.
- Exclude native C++ temporal core changes.
- Exclude natural-language recurrence changes.
- Exclude public recurrence-set APIs.
- Use project-native Fennel validation only: touched-file `tools.fennel-check`, then `make constraints`, then focused Fennel tests.

---

## File Structure

- `assets/lua/temporal/recurrence.fnl` owns RRULE normalization, parsing, serialization, satisfiability guards, and occurrence expansion. This slice adds private `BYMONTHDAY` helpers and combines calendar filters.
- `assets/lua/tests/test-temporal-parsing-recurrence.fnl` is the focused temporal recurrence test suite. This slice adds parse/serialize, filter behavior, and unsatisfiable-filter tests.
- `docs/dev/features/temporal-parsing-recurrence.md` is the public developer documentation for recurrence semantics. This slice documents positive filter-only `BYMONTHDAY` and deferred negative/generator semantics.

### Task 1: Positive BYMONTHDAY Parse, Serialize, and Filtering

**Files:**
- Modify: `assets/lua/temporal/recurrence.fnl`
- Test: `assets/lua/tests/test-temporal-parsing-recurrence.fnl`

**Interfaces:**
- Consumes: existing `Temporal.recurrence.from(options) -> rule`.
- Consumes: existing `Temporal.recurrence.parse-rrule(text) -> rule`.
- Consumes: existing `Temporal.recurrence.to-rrule(rule) -> text`.
- Consumes: existing `Temporal.recurrence.occurrences(rule, dtstart, options) -> PlainDateTime[]`.
- Consumes: existing `PlainDateTime:fields() -> {:year number :month number :day number :hour number :minute number :second number :nanosecond number}`.
- Consumes: existing `period.add-to-plain-date-time(dtstart, period-table) -> PlainDateTime`.
- Produces: normalized optional rule field `rule.by-month-day` containing a non-empty list of integers in `1..31`.
- Produces: private helpers `validate-month-day`, `normalize-by-month-day`, `parse-by-month-day`, `serialize-by-month-day`, `plain-day`, `by-month-day-allowed?`, `month-day-filter-allowed?`, and `candidate-calendar-filters-allowed?`.

- [ ] **Step 1: Add failing parse/serialize tests.**

  In `assets/lua/tests/test-temporal-parsing-recurrence.fnl`, add this function after `recurrence-bymonth-parse-and-serialize`:

  ```fennel
  (fn recurrence-bymonthday-parse-and-serialize []
    (local rule
      (Temporal.recurrence.parse-rrule
        "RRULE:FREQ=MONTHLY;COUNT=2;BYMONTH=2;BYMONTHDAY=1,29;BYDAY=MO"))
    (assert (= rule.freq :monthly))
    (assert (= rule.count 2))
    (assert (= (. rule.by-month 1) 2))
    (assert (= (. rule.by-month-day 1) 1))
    (assert (= (. rule.by-month-day 2) 29))
    (assert (= (. rule.by-day 1) :mo))
    (assert (= (Temporal.recurrence.to-rrule rule)
               "RRULE:FREQ=MONTHLY;COUNT=2;BYMONTH=2;BYMONTHDAY=1,29;BYDAY=MO"))

    (local from-rule (Temporal.recurrence.from {:freq :daily :by-month-day [31]}))
    (assert (= (. from-rule.by-month-day 1) 31))

    (assert-error #(Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYMONTHDAY=0")
                  "BYMONTHDAY=0 should throw")
    (assert-error #(Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYMONTHDAY=32")
                  "BYMONTHDAY=32 should throw")
    (assert-error #(Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYMONTHDAY=-1")
                  "negative BYMONTHDAY should throw")
    (assert-error #(Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYMONTHDAY=1,,2")
                  "BYMONTHDAY with empty member should throw")
    (assert-error #(Temporal.recurrence.from {:freq :monthly :by-month-day []})
                  "empty by-month-day should throw")
    (assert-error #(Temporal.recurrence.from {:freq :monthly :by-month-day 1})
                  "non-table by-month-day should throw"))
  ```

  Register it near the existing BYMONTH registration:

  ```fennel
  (table.insert tests {:name "recurrence BYMONTHDAY parse and serialize" :fn recurrence-bymonthday-parse-and-serialize})
  ```

- [ ] **Step 2: Add failing occurrence filter tests.**

  In the same test file, add this function after `recurrence-bymonth-filters-occurrences`:

  ```fennel
  (fn recurrence-bymonthday-filters-occurrences []
    (local daily-start (Temporal.plain-date-time.parse "2026-01-30T09:00:00"))
    (local daily-rule
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;COUNT=3;BYMONTHDAY=31"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences daily-rule daily-start {})
      ["2026-01-31T09:00:00"
       "2026-03-31T09:00:00"
       "2026-05-31T09:00:00"])

    (local weekly-start (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
    (local weekly-rule
      (Temporal.recurrence.parse-rrule
        "RRULE:FREQ=WEEKLY;COUNT=2;BYDAY=MO;BYMONTH=2;BYMONTHDAY=2,16"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences weekly-rule weekly-start {})
      ["2026-02-02T09:00:00"
       "2026-02-16T09:00:00"])

    (local monthly-start (Temporal.plain-date-time.parse "2026-01-31T10:11:12"))
    (local monthly-rule
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=2;BYMONTHDAY=30"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences monthly-rule monthly-start {})
      ["2026-04-30T10:11:12"
       "2026-06-30T10:11:12"])

    (local yearly-start (Temporal.plain-date-time.parse "2028-02-29T10:11:12"))
    (local yearly-rule
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;COUNT=2;BYMONTHDAY=29"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences yearly-rule yearly-start {})
      ["2028-02-29T10:11:12"
       "2032-02-29T10:11:12"])

    (local yearly-clamped
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;COUNT=2;BYMONTHDAY=28"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences yearly-clamped yearly-start {})
      ["2029-02-28T10:11:12"
       "2030-02-28T10:11:12"]))
  ```

  Register it near the BYMONTH filter test registration:

  ```fennel
  (table.insert tests {:name "recurrence BYMONTHDAY filters occurrences" :fn recurrence-bymonthday-filters-occurrences})
  ```

- [ ] **Step 3: Add failing unsatisfiable filter tests.**

  Add this function after `recurrence-bymonthday-filters-occurrences`:

  ```fennel
  (fn recurrence-bymonthday-unsatisfiable-filters-throw []
    (local daily-start (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
    (local daily-rule
      (Temporal.recurrence.parse-rrule
        "RRULE:FREQ=DAILY;INTERVAL=146097;COUNT=1;BYMONTHDAY=2"))
    (local daily-err
      (assert-error #(Temporal.recurrence.occurrences daily-rule daily-start {})
                    "unsatisfiable daily BYMONTHDAY should throw instead of hanging"))
    (assert (tostring daily-err):find "unsupported temporal recurrence expansion" 1 true)

    (local weekly-start (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
    (local weekly-rule
      (Temporal.recurrence.parse-rrule
        "RRULE:FREQ=WEEKLY;INTERVAL=20871;COUNT=1;BYDAY=FR;BYMONTHDAY=3"))
    (local weekly-err
      (assert-error #(Temporal.recurrence.occurrences weekly-rule weekly-start {})
                    "unsatisfiable weekly BYMONTHDAY should throw instead of hanging"))
    (assert (tostring weekly-err):find "unsupported temporal recurrence expansion" 1 true)

    (local monthly-start (Temporal.plain-date-time.parse "2026-01-31T10:11:12"))
    (local monthly-rule
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=1;BYMONTHDAY=15"))
    (local monthly-err
      (assert-error #(Temporal.recurrence.occurrences monthly-rule monthly-start {})
                    "unsatisfiable monthly BYMONTHDAY should throw instead of hanging"))
    (assert (tostring monthly-err):find "unsupported temporal recurrence expansion" 1 true)

    (local yearly-start (Temporal.plain-date-time.parse "2028-02-29T10:11:12"))
    (local yearly-rule
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;COUNT=1;BYMONTHDAY=31"))
    (local yearly-err
      (assert-error #(Temporal.recurrence.occurrences yearly-rule yearly-start {})
                    "unsatisfiable yearly BYMONTHDAY should throw instead of hanging"))
    (assert (tostring yearly-err):find "unsupported temporal recurrence expansion" 1 true))
  ```

  Register it:

  ```fennel
  (table.insert tests {:name "recurrence BYMONTHDAY unsatisfiable filters throw" :fn recurrence-bymonthday-unsatisfiable-filters-throw})
  ```

- [ ] **Step 4: Run the focused test to verify the RED state.**

  Run:

  ```bash
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected result before implementation: the focused recurrence test fails because `BYMONTHDAY` is not yet recognized as a recurrence option or RRULE key.

- [ ] **Step 5: Add canonical option validation and normalization.**

  In `assets/lua/temporal/recurrence.fnl`, add `:by-month-day true` to `valid-options` after `:by-month true`.

  Add these helpers after `normalize-by-month`:

  ```fennel
  (fn validate-month-day [day]
    (when (not (and (= (type day) :number)
                    (= day (math.floor day))
                    (>= day 1)
                    (<= day 31)))
      (error "invalid temporal recurrence BYMONTHDAY"))
    day)

  (fn normalize-by-month-day [days]
    (when (not= days nil)
      (when (not= (type days) :table)
        (error "invalid temporal recurrence BYMONTHDAY"))
      (local normalized [])
      (each [_ day (ipairs days)]
        (table.insert normalized (validate-month-day day)))
      (when (= (# normalized) 0)
        (error "invalid temporal recurrence BYMONTHDAY"))
      normalized))
  ```

  In `from`, after `by-month` normalization, add:

  ```fennel
  (local by-month-day (normalize-by-month-day options.by-month-day))
  (when by-month-day
    (set rule.by-month-day by-month-day))
  ```

- [ ] **Step 6: Add RRULE parse/serialize support.**

  Add this parser helper after `parse-by-month`:

  ```fennel
  (fn parse-by-month-day [text]
    (local days [])
    (each [_ item (ipairs (split-nonempty text ","))]
      (table.insert days (validate-month-day (parse-positive-integer item "BYMONTHDAY"))))
    days)
  ```

  In `parse-rrule`, add this branch after `BYMONTH` and before `BYDAY`:

  ```fennel
  (= key "BYMONTHDAY")
  (set options.by-month-day (parse-by-month-day value))
  ```

  Add this serializer helper after `serialize-by-month`:

  ```fennel
  (fn serialize-by-month-day [days]
    (local parts [])
    (each [_ day (ipairs days)]
      (table.insert parts (tostring (validate-month-day day))))
    (join parts ","))
  ```

  In `to-rrule`, insert after the `BYMONTH` serialization and before `BYDAY`:

  ```fennel
  (when normalized.by-month-day
    (table.insert parts (.. "BYMONTHDAY=" (serialize-by-month-day normalized.by-month-day))))
  ```

- [ ] **Step 7: Add day-of-month filter helpers.**

  Near existing `plain-month` and `month-filter-allowed?`, add:

  ```fennel
  (fn plain-day [plain]
    (local fields (plain:fields))
    fields.day)

  (fn by-month-day-allowed? [days day]
    (var allowed false)
    (each [_ value (ipairs days)]
      (when (= value day)
        (set allowed true)))
    allowed)

  (fn month-day-filter-allowed? [rule candidate]
    (if rule.by-month-day
        (by-month-day-allowed? rule.by-month-day (plain-day candidate))
        true))

  (fn candidate-calendar-filters-allowed? [rule candidate]
    (and (month-filter-allowed? rule candidate)
         (month-day-filter-allowed? rule candidate)))
  ```

- [ ] **Step 8: Apply the combined filter to daily and weekly expansion.**

  In `expand-daily`, replace both occurrences of:

  ```fennel
  (month-filter-allowed? rule current)
  ```

  with:

  ```fennel
  (candidate-calendar-filters-allowed? rule current)
  ```

  In `expand-weekly`, replace:

  ```fennel
  (month-filter-allowed? rule current)
  ```

  with:

  ```fennel
  (candidate-calendar-filters-allowed? rule current)
  ```

- [ ] **Step 9: Extend daily and weekly satisfiability guards.**

  In `assert-daily-filters-satisfiable`, change:

  ```fennel
  (when rule.by-month
  ```

  to:

  ```fennel
  (when (or rule.by-month rule.by-month-day)
  ```

  In the same helper, replace:

  ```fennel
  (month-filter-allowed? rule current)
  ```

  with:

  ```fennel
  (candidate-calendar-filters-allowed? rule current)
  ```

  In `assert-weekly-filters-satisfiable`, change:

  ```fennel
  (when rule.by-month
  ```

  to:

  ```fennel
  (when (or rule.by-month rule.by-month-day)
  ```

  In the same helper, replace:

  ```fennel
  (month-filter-allowed? rule candidate)
  ```

  with:

  ```fennel
  (candidate-calendar-filters-allowed? rule candidate)
  ```

- [ ] **Step 10: Extend monthly/yearly satisfiability guards.**

  Replace the current `assert-calendar-filters-satisfiable` helper with these helpers:

  ```fennel
  (fn calendar-filter-cycle [rule]
    (if (= rule.freq :monthly)
        (if rule.by-month-day
            (/ 4800 (gcd rule.interval 4800))
            (/ 12 (gcd rule.interval 12)))
        (= rule.freq :yearly)
        (/ 400 (gcd rule.interval 400))
        (error "unsupported temporal recurrence expansion")))

  (fn assert-calendar-filters-satisfiable [period rule dtstart]
    (when (or rule.by-month rule.by-month-day)
      (local cycle (calendar-filter-cycle rule))
      (var index 0)
      (var satisfiable false)
      (while (and (< index cycle) (not satisfiable))
        (local candidate
          (if (= index 0)
              dtstart
              (period.add-to-plain-date-time
                dtstart
                (calendar-step-period rule.freq (* index rule.interval)))))
        (when (candidate-calendar-filters-allowed? rule candidate)
          (set satisfiable true))
        (set index (+ index 1)))
      (when (not satisfiable)
        (error "unsupported temporal recurrence expansion"))))
  ```

  The `4800` month cycle covers 400 Gregorian years of monthly anchored clamping. The `400` yearly cycle covers the Gregorian leap-year cycle.

- [ ] **Step 11: Apply the combined filter to monthly/yearly expansion.**

  In `expand-calendar`, replace:

  ```fennel
  (when (month-filter-allowed? rule candidate)
    (table.insert results candidate))
  ```

  with:

  ```fennel
  (when (candidate-calendar-filters-allowed? rule candidate)
    (table.insert results candidate))
  ```

- [ ] **Step 12: Run the Fennel compile check.**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/recurrence.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  ```

  Expected result after implementation: `status` is `pass` and diagnostics are empty.

- [ ] **Step 13: Run constraints.**

  Run with a 600000 ms timeout:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets make constraints
  ```

  Expected result after implementation: `constraints: pass (0 diagnostics)`.

- [ ] **Step 14: Run the focused recurrence test.**

  Run:

  ```bash
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected result after implementation: all tests pass and the output includes the full count of executed Lua tests.

- [ ] **Step 15: Commit Task 1.**

  Commit exactly the implementation and test files:

  ```bash
  git add assets/lua/temporal/recurrence.fnl assets/lua/tests/test-temporal-parsing-recurrence.fnl
  git commit -m "feat(temporal): add bounded BYMONTHDAY recurrence filters"
  ```

  The implementer report must include RED evidence, compile-check evidence, constraints evidence with a constraint-impact note, focused-test evidence, and coverage rationale.

### Task 2: Documentation and Final Focused Validation

**Files:**
- Modify: `docs/dev/features/temporal-parsing-recurrence.md`

**Interfaces:**
- Consumes: Task 1 behavior for positive filter-only `BYMONTHDAY`, conjunctive `BYMONTH` plus `BYMONTHDAY`, unsatisfiable-filter rejection, and unchanged `COUNT`/`limit`/`UNTIL` bounds.
- Produces: public developer documentation matching the supported `BYMONTHDAY` slice and deferred full-RFC5545 boundaries.

- [ ] **Step 1: Update the supported RRULE subset paragraph.**

  In `docs/dev/features/temporal-parsing-recurrence.md`, replace the current recurrence subset paragraph with this wording:

  ```markdown
  The bounded RRULE subset supports `FREQ` values `DAILY`, `WEEKLY`, `MONTHLY`, and `YEARLY`, plus `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY`, `BYMONTH`, and `BYMONTHDAY`. `BYMONTH` accepts integer months `1..12`; `BYMONTHDAY` accepts positive integer month days `1..31`. Both act as inclusion filters over the existing daily, weekly, monthly, or yearly candidate stream and combine conjunctively. Compact local `UNTIL=YYYYMMDDTHHMMSS` bounds occurrence expansion inclusively and can satisfy the finite-bound requirement without `COUNT` or `options.limit`; `COUNT`, `options.limit`, and `UNTIL` stop expansion at the earliest reached bound. Compact UTC `UNTIL=YYYYMMDDTHHMMSSZ` remains parse/serialize-compatible but is unsupported for expansion until timezone-aware recurrence exists. Monthly and yearly rules remain anchor-based through `Temporal.period`; `YEARLY+BYMONTH` and `MONTHLY+BYMONTHDAY` do not generate additional candidate months or month days in this slice.
  ```

- [ ] **Step 2: Update the deferred full-RFC5545 bullet.**

  Replace the existing `Full RFC5545` bullet with this wording:

  ```markdown
  - **Full RFC5545:** Deferred. The current RRULE subset is intentionally small; timezone-aware recurrence, UTC/instant `UNTIL` expansion, date-only `UNTIL`, fractional `UNTIL`, negative `BYMONTHDAY`, generator-style monthly/yearly candidate expansion, `BYSETPOS`, `WKST`, `RDATE`, `EXDATE`, and full RFC5545 candidate-set expansion require separate semantics and compatibility tests.
  ```

- [ ] **Step 3: Run focused documentation checks.**

  Run:

  ```bash
  rtk rg "BYMONTHDAY|BYMONTH|UNTIL|Full RFC5545|candidate-set" docs/dev/features/temporal-parsing-recurrence.md docs/specs/2026-09-27-temporal-rrule-bymonthday-design.md docs/plans/2026-09-27-temporal-rrule-bymonthday.md
  ```

  Expected result: the feature doc describes positive `BYMONTHDAY` as supported and filter-only, and the deferred bullet still excludes negative/generator/full-RFC5545 semantics.

- [ ] **Step 4: Run final Fennel compile check.**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/recurrence.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  ```

  Expected result: `status` is `pass` and diagnostics are empty.

- [ ] **Step 5: Run final constraints.**

  Run with a 600000 ms timeout:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets make constraints
  ```

  Expected result: `constraints: pass (0 diagnostics)`.

- [ ] **Step 6: Run final focused recurrence tests.**

  Run:

  ```bash
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected result: all tests pass and the output includes the full count of executed Lua tests.

- [ ] **Step 7: Commit Task 2.**

  Commit the documentation file:

  ```bash
  git add docs/dev/features/temporal-parsing-recurrence.md
  git commit -m "docs(temporal): document bounded BYMONTHDAY recurrence"
  ```

  The implementer report must include documentation check evidence, compile-check evidence, constraints evidence with a constraint-impact note, focused-test evidence, and coverage rationale.
