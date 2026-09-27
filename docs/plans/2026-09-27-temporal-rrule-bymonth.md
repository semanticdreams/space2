# Temporal RRULE BYMONTH Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add bounded RRULE `BYMONTH` support to `Temporal.recurrence` parsing, serialization, validation, and occurrence expansion.

**Architecture:** Treat `BYMONTH` as an inclusion filter over the existing daily, weekly, monthly, and yearly candidate streams. Keep the slice bounded: no full RFC5545 candidate-set machinery, no generator-style yearly month expansion, and no new native APIs.

**Tech Stack:** Space Fennel modules in `assets/lua/temporal`, focused Fennel tests in `assets/lua/tests`, project-native validation via `tools.fennel-check`, `make constraints`, and focused recurrence tests.

## Global Constraints

- Add canonical recurrence option key `:by-month`.
- Parse RRULE month lists such as `BYMONTH=1,3,12` where each month is an integer `1..12`.
- Serialize normalized `:by-month` values as `BYMONTH=1,3,12`.
- Validate malformed, empty, non-integer, and out-of-range month values loudly.
- Apply `BYMONTH` as a bounded inclusion filter during occurrence expansion.
- Preserve existing `FREQ`, `INTERVAL`, `COUNT`, `UNTIL`, and `BYDAY` behavior.
- Preserve monthly/yearly anchor-based `Temporal.period` expansion semantics.
- Avoid unbounded scans for unsatisfiable filters.
- Full RFC5545 recurrence semantics are out of scope.
- `BYMONTHDAY`, `BYSETPOS`, `WKST`, `RDATE`, `EXDATE`, `BYWEEKNO`, or ordinal `BYDAY` support is out of scope.
- Timezone-aware `DTSTART` or DST-aware recurrence is out of scope.
- Making `UNTIL` an expansion bound is out of scope.
- Changing monthly/yearly `BYDAY` rejection is out of scope.
- Changing `YEARLY+BYMONTH` into generator semantics that creates additional months inside each year is out of scope.
- C++ temporal core changes are out of scope.
- Public recurrence-set APIs are out of scope.

---

## File Structure

- `assets/lua/temporal/recurrence.fnl`
  - Owns recurrence rule normalization, RRULE parse/format, and occurrence expansion.
  - Add `:by-month` validation, RRULE parse/serialization, and occurrence filtering.
- `assets/lua/tests/test-temporal-parsing-recurrence.fnl`
  - Owns focused temporal parsing/recurrence tests.
  - Add `BYMONTH` parse/serialize and occurrence tests.
- `docs/dev/features/temporal-parsing-recurrence.md`
  - Canonical recurrence feature documentation.
  - Document supported `BYMONTH` filter semantics and deferred RFC5545 features.

---

### Task 1: BYMONTH Parse, Normalize, and Serialize

**Files:**
- Modify: `assets/lua/temporal/recurrence.fnl`
- Modify: `assets/lua/tests/test-temporal-parsing-recurrence.fnl`

**Interfaces:**
- Consumes:
  - Existing `Temporal.recurrence.from(options:table) -> recurrence-rule`
  - Existing `Temporal.recurrence.parse-rrule(text:string) -> recurrence-rule`
  - Existing `Temporal.recurrence.to-rrule(rule:table) -> string`
- Produces:
  - `:by-month` normalized rule field as a non-empty sequence of integers in `1..12`.
  - RRULE `BYMONTH` parse and serialization support.
  - Occurrence expansion may still ignore `:by-month` until Task 2.

- [ ] **Step 1: Add failing BYMONTH parse/serialize tests.**

  In `assets/lua/tests/test-temporal-parsing-recurrence.fnl`, add this function after `recurrence-rrule-round-trip`:

  ```fennel
  (fn recurrence-bymonth-parse-and-serialize []
    (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;COUNT=2;BYMONTH=1,3,12"))
    (assert (= rule.freq :yearly))
    (assert (= rule.count 2))
    (assert (= (. rule.by-month 1) 1))
    (assert (= (. rule.by-month 2) 3))
    (assert (= (. rule.by-month 3) 12))
    (assert (= (Temporal.recurrence.to-rrule rule)
               "RRULE:FREQ=YEARLY;COUNT=2;BYMONTH=1,3,12"))

    (local from-rule (Temporal.recurrence.from {:freq :monthly :by-month [2 4]}))
    (assert (= (. from-rule.by-month 1) 2))
    (assert (= (. from-rule.by-month 2) 4))

    (assert-error #(Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYMONTH=0")
                  "BYMONTH=0 should throw")
    (assert-error #(Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYMONTH=13")
                  "BYMONTH=13 should throw")
    (assert-error #(Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYMONTH=JAN")
                  "BYMONTH=JAN should throw")
    (assert-error #(Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYMONTH=1,,2")
                  "BYMONTH with empty member should throw")
    (assert-error #(Temporal.recurrence.from {:freq :monthly :by-month []})
                  "empty by-month should throw")
    (assert-error #(Temporal.recurrence.from {:freq :monthly :by-month 1})
                  "non-table by-month should throw"))
  ```

  Register it immediately after the existing RRULE round-trip test:

  ```fennel
  (table.insert tests {:name "recurrence BYMONTH parse and serialize" :fn recurrence-bymonth-parse-and-serialize})
  ```

- [ ] **Step 2: Run the focused test and verify failure.**

  If `./build/space` is missing or stale, first run:

  ```bash
  make build
  ```

  Then run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected before implementation: failure from unknown RRULE key `BYMONTH` or unknown option `:by-month`.

- [ ] **Step 3: Add BYMONTH validation helpers.**

  In `assets/lua/temporal/recurrence.fnl`:

  - Add `:by-month true` to `valid-options`.
  - Add helpers after `validate-day`:

  ```fennel
  (fn validate-month [month]
    (when (not (and (= (type month) :number)
                    (= month (math.floor month))
                    (>= month 1)
                    (<= month 12)))
      (error "invalid temporal recurrence BYMONTH"))
    month)

  (fn normalize-by-month [months]
    (when (not= months nil)
      (when (not= (type months) :table)
        (error "invalid temporal recurrence BYMONTH"))
      (local normalized [])
      (each [_ month (ipairs months)]
        (table.insert normalized (validate-month month)))
      (when (= (# normalized) 0)
        (error "invalid temporal recurrence BYMONTH"))
      normalized))
  ```

- [ ] **Step 4: Normalize programmatic `:by-month`.**

  In `from`, after `by-day` normalization, add:

  ```fennel
  (local by-month (normalize-by-month options.by-month))
  (when by-month
    (set rule.by-month by-month))
  ```

  Keep existing `:by-day` behavior unchanged.

- [ ] **Step 5: Add RRULE BYMONTH parse and serialize helpers.**

  Add these helpers near `parse-by-day` and `serialize-by-day`:

  ```fennel
  (fn parse-by-month [text]
    (local months [])
    (each [_ item (ipairs (split-nonempty text ","))]
      (table.insert months (validate-month (parse-positive-integer item "BYMONTH"))))
    months)

  (fn serialize-by-month [months]
    (local parts [])
    (each [_ month (ipairs months)]
      (table.insert parts (tostring (validate-month month))))
    (join parts ","))
  ```

  In `parse-rrule`, add a branch:

  ```fennel
  (= key "BYMONTH")
  (set options.by-month (parse-by-month value))
  ```

  In `to-rrule`, serialize after `UNTIL` and before `BYDAY`:

  ```fennel
  (when normalized.by-month
    (table.insert parts (.. "BYMONTH=" (serialize-by-month normalized.by-month))))
  ```

- [ ] **Step 6: Run Task 1 validation.**

  Compile check:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/recurrence.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  ```

  Constraints:

  ```bash
  make constraints
  ```

  Focused recurrence tests:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

- [ ] **Step 7: Commit Task 1.**

  ```bash
  git add assets/lua/temporal/recurrence.fnl assets/lua/tests/test-temporal-parsing-recurrence.fnl
  git commit -m "feat(temporal): parse RRULE BYMONTH"
  ```

  The report must include RED evidence, compile-check evidence, constraints evidence with constraint-impact note, focused-test evidence, and coverage rationale.

---

### Task 2: BYMONTH Occurrence Filter Semantics

**Files:**
- Modify: `assets/lua/temporal/recurrence.fnl`
- Modify: `assets/lua/tests/test-temporal-parsing-recurrence.fnl`

**Interfaces:**
- Consumes:
  - `rule.by-month` normalized by Task 1.
  - Existing `dtstart` plain-date-time operations: `add-days`, `iso-weekday`, `fields`.
  - Existing monthly/yearly anchor expansion through injected `period.add-to-plain-date-time`.
- Produces:
  - `Temporal.recurrence.occurrences` filters candidates by allowed months for daily, weekly, monthly, and yearly frequencies.

- [ ] **Step 1: Add failing BYMONTH occurrence tests.**

  In `assets/lua/tests/test-temporal-parsing-recurrence.fnl`, add this function near the recurrence expansion tests:

  ```fennel
  (fn recurrence-bymonth-filters-occurrences []
    (local daily-start (Temporal.plain-date-time.parse "2026-01-30T09:00:00"))
    (local daily-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;COUNT=3;BYMONTH=2"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences daily-rule daily-start {})
      ["2026-02-01T09:00:00"
       "2026-02-02T09:00:00"
       "2026-02-03T09:00:00"])

    (local weekly-start (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
    (local weekly-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=WEEKLY;COUNT=3;BYDAY=MO;BYMONTH=2"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences weekly-rule weekly-start {})
      ["2026-02-02T09:00:00"
       "2026-02-09T09:00:00"
       "2026-02-16T09:00:00"])

    (local monthly-start (Temporal.plain-date-time.parse "2026-01-31T10:11:12"))
    (local monthly-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=3;BYMONTH=1,3,5"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences monthly-rule monthly-start {})
      ["2026-01-31T10:11:12"
       "2026-03-31T10:11:12"
       "2026-05-31T10:11:12"])

    (local yearly-start (Temporal.plain-date-time.parse "2028-02-29T10:11:12"))
    (local yearly-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;COUNT=3;BYMONTH=2"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences yearly-rule yearly-start {})
      ["2028-02-29T10:11:12"
       "2029-02-28T10:11:12"
       "2030-02-28T10:11:12"])

    (assert-error #(Temporal.recurrence.occurrences
                     (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;COUNT=1;BYMONTH=3")
                     yearly-start
                     {})
                  "yearly BYMONTH excluding anchor month should throw")
    (assert-error #(Temporal.recurrence.occurrences
                     (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=1;BYMONTH=1;BYDAY=MO")
                     monthly-start
                     {})
                  "monthly BYDAY with BYMONTH should still throw"))
  ```

  Register it near the other recurrence tests:

  ```fennel
  (table.insert tests {:name "recurrence BYMONTH filters occurrences" :fn recurrence-bymonth-filters-occurrences})
  ```

- [ ] **Step 2: Run the focused test and verify failure.**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected before implementation: occurrence assertions fail because `BYMONTH` is not filtering candidate streams yet.

- [ ] **Step 3: Add month and math helpers.**

  In `assets/lua/temporal/recurrence.fnl`, add private helpers near the other occurrence helpers:

  ```fennel
  (local number-to-day [:mo :tu :we :th :fr :sa :su])

  (fn gcd [a b]
    (var x (math.abs a))
    (var y (math.abs b))
    (while (not= y 0)
      (local next (% x y))
      (set x y)
      (set y next))
    x)

  (fn plain-month [plain]
    (local fields (plain:fields))
    fields.month)

  (fn by-month-allowed? [months month]
    (var allowed false)
    (each [_ value (ipairs months)]
      (when (= value month)
        (set allowed true)))
    allowed)

  (fn month-filter-allowed? [rule candidate]
    (if rule.by-month
        (by-month-allowed? rule.by-month (plain-month candidate))
        true))
  ```

- [ ] **Step 4: Add finite cycle satisfiability helpers.**

  Add helpers:

  ```fennel
  (fn assert-daily-filters-satisfiable [rule dtstart]
    (when rule.by-month
      (local cycle (/ 146097 (gcd rule.interval 146097)))
      (var current dtstart)
      (var offset 0)
      (var satisfiable false)
      (while (and (< offset cycle) (not satisfiable))
        (when (and (month-filter-allowed? rule current)
                   (if rule.by-day
                       (by-day-allowed? rule.by-day (current:iso-weekday))
                       true))
          (set satisfiable true))
        (set current (current:add-days rule.interval))
        (set offset (+ offset 1)))
      (when (not satisfiable)
        (error "unsupported temporal recurrence expansion"))))

  (fn assert-weekly-filters-satisfiable [rule dtstart]
    (when rule.by-month
      (local selected-week-cycle (/ 20871 (gcd rule.interval 20871)))
      (local default-weekday (dtstart:iso-weekday))
      (local allowed-weekdays
        (if rule.by-day
            rule.by-day
            [(. number-to-day default-weekday)]))
      (var selected-week-index 0)
      (var satisfiable false)
      (while (and (< selected-week-index selected-week-cycle) (not satisfiable))
        (local week-start (dtstart:add-days (* selected-week-index rule.interval 7)))
        (each [_ day allowed-weekdays]
          (local weekday-number (. day-to-number day))
          (var offset (- weekday-number default-weekday))
          (when (< offset 0)
            (set offset (+ offset 7)))
          (local candidate (week-start:add-days offset))
          (when (and (not satisfiable)
                     (month-filter-allowed? rule candidate))
            (set satisfiable true)))
        (set selected-week-index (+ selected-week-index 1)))
      (when (not satisfiable)
        (error "unsupported temporal recurrence expansion"))))

  (fn assert-calendar-filters-satisfiable [rule dtstart]
    (when rule.by-month
      (if (= rule.freq :monthly)
          (do
            (local cycle (/ 12 (gcd rule.interval 12)))
            (var index 0)
            (var satisfiable false)
            (while (and (< index cycle) (not satisfiable))
              (local candidate
                (if (= index 0)
                    dtstart
                    (period.add-to-plain-date-time
                      dtstart
                      (calendar-step-period rule.freq (* index rule.interval)))))
              (when (month-filter-allowed? rule candidate)
                (set satisfiable true))
              (set index (+ index 1)))
            (when (not satisfiable)
              (error "unsupported temporal recurrence expansion")))
          (= rule.freq :yearly)
          (when (not (month-filter-allowed? rule dtstart))
            (error "unsupported temporal recurrence expansion")))))
  ```

  For the calendar helper, either keep it nested inside `expand-calendar` where `period` is already in scope, or define it at top level with parameters `[period rule dtstart]` and use the concrete helper body shown in Step 4. Do not use global mutable state.

- [ ] **Step 5: Apply BYMONTH filtering in daily expansion.**

  In `expand-daily`, call `assert-daily-filters-satisfiable` after the existing daily BYDAY satisfiability guard and before the loop. Then ensure insertion requires both existing BYDAY logic and `month-filter-allowed?`.

  For the no-`BYDAY` path, preserve interval stepping but only insert when the month filter passes:

  ```fennel
  (while (< (# results) limit)
    (when (month-filter-allowed? rule current)
      (table.insert results current))
    (set current (current:add-days rule.interval)))
  ```

  For the `BYDAY` path, add `(month-filter-allowed? rule current)` to the existing `when` condition.

- [ ] **Step 6: Apply BYMONTH filtering in weekly expansion.**

  In `expand-weekly`, call `assert-weekly-filters-satisfiable` before the loop. Add `(month-filter-allowed? rule current)` to the existing insertion condition. Preserve chronological order and the existing rule that candidates before `dtstart` are never emitted.

- [ ] **Step 7: Apply BYMONTH filtering in monthly/yearly expansion.**

  In `expand-calendar`, keep the current `BYDAY` rejection first. Then call a calendar satisfiability helper before the loop. During the loop, compute the candidate and insert it only when `(month-filter-allowed? rule candidate)` is true. Preserve first occurrence identity for valid unfiltered starts by inserting `dtstart` when `index` is zero and allowed.

- [ ] **Step 8: Run Task 2 validation.**

  Compile check:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/recurrence.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  ```

  Constraints:

  ```bash
  make constraints
  ```

  Focused recurrence tests:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

- [ ] **Step 9: Commit Task 2.**

  ```bash
  git add assets/lua/temporal/recurrence.fnl assets/lua/tests/test-temporal-parsing-recurrence.fnl
  git commit -m "feat(temporal): filter recurrences by month"
  ```

  The report must include RED evidence, compile-check evidence, constraints evidence with constraint-impact note, focused-test evidence, and coverage rationale.

---

### Task 3: BYMONTH Documentation and Final Focused Validation

**Files:**
- Modify: `docs/dev/features/temporal-parsing-recurrence.md`

**Interfaces:**
- Consumes:
  - Final `BYMONTH` parse/serialize behavior from Task 1.
  - Final `BYMONTH` occurrence filter behavior from Task 2.
- Produces:
  - Public docs that distinguish supported `BYMONTH` filter semantics from deferred full RFC5545 candidate-set expansion.

- [ ] **Step 1: Update recurrence subset documentation.**

  In `docs/dev/features/temporal-parsing-recurrence.md`, update the recurrence paragraph so it says:

  ```markdown
  The bounded RRULE subset supports `FREQ` values `DAILY`, `WEEKLY`, `MONTHLY`, and `YEARLY`, plus `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY`, and `BYMONTH`. `BYMONTH` accepts integer months `1..12` and acts as an inclusion filter over the existing daily, weekly, monthly, or yearly candidate stream. Monthly and yearly rules remain anchor-based through `Temporal.period`; `YEARLY+BYMONTH` does not generate additional months in this slice. `UNTIL` remains parse/serialize-only and is not an expansion bound.
  ```

- [ ] **Step 2: Update deferred map wording.**

  Ensure the deferred map still explicitly mentions:

  - `BYMONTHDAY`
  - `BYSETPOS`
  - `WKST`
  - `RDATE`
  - `EXDATE`
  - timezone-aware recurrence
  - full RFC5545 candidate-set expansion

- [ ] **Step 3: Run docs search validation.**

  ```bash
  rg "BYMONTH|BYMONTHDAY|BYSETPOS|WKST|RDATE|EXDATE|timezone-aware recurrence|full RFC5545" docs/dev/features/temporal-parsing-recurrence.md
  ```

- [ ] **Step 4: Run final focused validation for the docs task.**

  Compile check:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/recurrence.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  ```

  Constraints:

  ```bash
  make constraints
  ```

  Focused recurrence tests:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

- [ ] **Step 5: Commit Task 3.**

  ```bash
  git add docs/dev/features/temporal-parsing-recurrence.md
  git commit -m "docs(temporal): document RRULE BYMONTH support"
  ```

  The report must include docs-search evidence, compile-check evidence, constraints evidence, focused-test evidence, constraint-impact note `not applicable`, and coverage rationale.

---

## Final Review and Finishing Validation

After all tasks pass reviewer gates, request a whole-branch reviewer pass against:

- `docs/specs/2026-09-27-temporal-rrule-bymonth-design.md`
- `docs/plans/2026-09-27-temporal-rrule-bymonth.md`
- `assets/lua/temporal/recurrence.fnl`
- `assets/lua/tests/test-temporal-parsing-recurrence.fnl`
- `docs/dev/features/temporal-parsing-recurrence.md`

Then invoke finishing-a-development-branch. Required final validation should include at least:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/recurrence.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
rg "BYMONTH|BYMONTHDAY|BYSETPOS|WKST|RDATE|EXDATE|timezone-aware recurrence|full RFC5545" docs/dev/features/temporal-parsing-recurrence.md
```

Broader `make test` is not required by default because this slice is isolated to the Fennel recurrence subsystem and the focused recurrence suite covers the public behavior. Run broader validation if reviewer requests it, if focused validation exposes cross-surface risk, or if finishing policy requires it.
