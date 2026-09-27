# Temporal RRULE BYMONTHDAY Generator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add bounded monthly/yearly generator semantics for positive RRULE `BYMONTHDAY` while preserving daily/weekly filter-only behavior.

**Architecture:** Keep the existing recurrence parser and validator, but split calendar expansion when monthly/yearly rules include `BYMONTHDAY`. Daily and weekly keep using `BYMONTHDAY` as a filter; monthly/yearly generate requested days inside anchor-derived period buckets using `PlainDateTime.from-fields`, skipping invalid dates and pre-`DTSTART` dates. Existing `COUNT`, `options.limit`, and local `UNTIL` bounds continue to count returned occurrences after generation and filtering.

**Tech Stack:** Space Fennel, `assets/lua/temporal.fnl`, `assets/lua/temporal/recurrence.fnl`, native `PlainDateTime:fields`, native `Temporal.plain-date-time.from-fields`, project-native `tools.fennel-check`, `make constraints`, focused Fennel recurrence tests, and full local `make test` validation.

## Global Constraints

- Keep canonical option key `:by-month-day` and existing positive validation for integers `1..31`.
- Keep RRULE parse/serialize order: `FREQ`, optional `INTERVAL`, optional `COUNT`, optional `UNTIL`, optional `BYMONTH`, optional `BYMONTHDAY`, optional `BYDAY`.
- Daily and weekly `BYMONTHDAY` remain inclusion filters over existing daily/weekly candidates.
- Monthly `BYMONTHDAY` generates requested positive month days inside each selected monthly period bucket.
- Yearly `BYMONTHDAY` generates requested positive month days inside selected yearly period buckets.
- Monthly and yearly period buckets remain anchor-based from original `DTSTART` through `Temporal.period.add-to-plain-date-time`; no iterative drift is introduced.
- Generated candidates preserve the original `DTSTART` time-of-day and nanosecond fields.
- Generated candidates before `DTSTART` are skipped.
- Invalid generated dates such as February 30 or April 31 are skipped, not clamped and not surfaced as errors when the recurrence has at least one possible generated candidate in its bounded cycle.
- Generated candidates after local compact `UNTIL` are not emitted; `UNTIL` remains inclusive.
- `COUNT` and caller `options.limit` count returned occurrences after generated-date skipping, `DTSTART` lower-bound skipping, all filters, and `UNTIL` exclusion.
- Preserve caller-provided `BYMONTHDAY` order within each generated month; do not sort or deduplicate month days.
- For yearly rules with `BYMONTHDAY`, use `BYMONTH` as the generated month list when present; otherwise use the `DTSTART` anchor month.
- Preserve caller-provided `BYMONTH` order for yearly generated months.
- Monthly `BYMONTH` remains a filter over the monthly anchor grid; it does not generate extra months for monthly rules.
- Yearly `BYMONTH` without `BYMONTHDAY` remains existing filter-only behavior.
- Monthly/yearly `BYDAY` remains unsupported and throws before attempting generation.
- Unsatisfiable monthly/yearly generator combinations throw `unsupported temporal recurrence expansion` instead of hanging.
- Exclude negative `BYMONTHDAY` semantics such as `-1` for the last day of the month.
- Exclude full RFC5545 candidate-set expansion.
- Exclude `BYSETPOS`, `WKST`, `RDATE`, `EXDATE`, `BYWEEKNO`, and ordinal `BYDAY`.
- Exclude timezone-aware recurrence, DST handling, UTC `UNTIL` expansion, and recurrence over `Instant` or `ZonedDateTime`.
- Exclude natural-language recurrence changes.
- Exclude native C++ temporal core changes.
- Exclude public recurrence-set APIs.
- Use project-native Fennel validation only: touched-file `tools.fennel-check`, then `make constraints`, then focused Fennel tests.
- Run the full local suite during final validation because recurrence factory wiring and public recurrence behavior change.

---

## File Structure

- `assets/lua/temporal.fnl` wires the recurrence factory. This slice injects `base.plain-date-time` so recurrence can construct generated `PlainDateTime` candidates.
- `assets/lua/temporal/recurrence.fnl` owns recurrence expansion. This slice adds generator helpers and routes monthly/yearly `BYMONTHDAY` rules through generator expansion.
- `assets/lua/tests/test-temporal-parsing-recurrence.fnl` is the focused recurrence suite. This slice replaces monthly/yearly filter-only assertions with generator assertions while preserving daily/weekly filter assertions.
- `docs/dev/features/temporal-parsing-recurrence.md` documents public recurrence behavior. This slice updates frequency-dependent `BYMONTHDAY` semantics.

### Task 1: Monthly/Yearly BYMONTHDAY Generator Behavior

**Files:**
- Modify: `assets/lua/temporal.fnl`
- Modify: `assets/lua/temporal/recurrence.fnl`
- Test: `assets/lua/tests/test-temporal-parsing-recurrence.fnl`

**Interfaces:**
- Consumes: `period.add-to-plain-date-time(plain, period-table) -> PlainDateTime`.
- Consumes: `plain-date-time.from-fields(fields-table) -> PlainDateTime`, throwing for invalid dates.
- Consumes: `PlainDateTime:fields() -> table` with `year`, `month`, `day`, `hour`, `minute`, `second`, and `nanosecond` keys.
- Consumes: `PlainDateTime:compare(other) -> -1 | 0 | 1`.
- Produces: recurrence factory dependency shape `create-recurrence {:period period :standard standard :plain-date-time base.plain-date-time}`.
- Produces: monthly/yearly generator semantics for `rule.by-month-day` during `Temporal.recurrence.occurrences`.

- [ ] **Step 1: Add failing monthly/yearly generator tests.**

  In `assets/lua/tests/test-temporal-parsing-recurrence.fnl`, update `recurrence-bymonthday-filters-occurrences` so daily and weekly cases remain filter-only, and monthly/yearly cases assert generator behavior:

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
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=3;BYMONTHDAY=15"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences monthly-rule monthly-start {})
      ["2026-02-15T10:11:12"
       "2026-03-15T10:11:12"
       "2026-04-15T10:11:12"])

    (local monthly-ordered
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=4;BYMONTHDAY=15,1"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences monthly-ordered monthly-start {})
      ["2026-02-15T10:11:12"
       "2026-02-01T10:11:12"
       "2026-03-15T10:11:12"
       "2026-03-01T10:11:12"])

    (local monthly-invalid-days
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=3;BYMONTHDAY=31"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences monthly-invalid-days monthly-start {})
      ["2026-01-31T10:11:12"
       "2026-03-31T10:11:12"
       "2026-05-31T10:11:12"])

    (local yearly-start (Temporal.plain-date-time.parse "2026-01-31T10:11:12"))
    (local yearly-rule
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;COUNT=2;BYMONTH=2;BYMONTHDAY=14"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences yearly-rule yearly-start {})
      ["2026-02-14T10:11:12"
       "2027-02-14T10:11:12"])

    (local anchor-month-start (Temporal.plain-date-time.parse "2026-05-20T10:11:12"))
    (local yearly-anchor-month
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;COUNT=2;BYMONTHDAY=15"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences yearly-anchor-month anchor-month-start {})
      ["2027-05-15T10:11:12"
       "2028-05-15T10:11:12"]))
  ```

- [ ] **Step 2: Add failing bounds and unsatisfiable generator tests.**

  Add this function after `recurrence-bymonthday-filters-occurrences`:

  ```fennel
  (fn recurrence-bymonthday-generator-bounds-and-rejections []
    (local monthly-start (Temporal.plain-date-time.parse "2026-01-31T10:11:12"))
    (local monthly-until
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;UNTIL=20260315T101112;BYMONTHDAY=15"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences monthly-until monthly-start {})
      ["2026-02-15T10:11:12"
       "2026-03-15T10:11:12"])

    (local monthly-limit
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=5;BYMONTHDAY=1,15"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences monthly-limit monthly-start {:limit 3})
      ["2026-02-01T10:11:12"
       "2026-02-15T10:11:12"
       "2026-03-01T10:11:12"])

    (local yearly-start (Temporal.plain-date-time.parse "2026-01-31T10:11:12"))
    (local yearly-unsat
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;COUNT=1;BYMONTH=2;BYMONTHDAY=31"))
    (local yearly-err
      (assert-error #(Temporal.recurrence.occurrences yearly-unsat yearly-start {})
                    "unsatisfiable yearly generated BYMONTHDAY should throw instead of hanging"))
    (assert (tostring yearly-err):find "unsupported temporal recurrence expansion" 1 true)

    (local monthly-unsat-start (Temporal.plain-date-time.parse "2026-02-01T10:11:12"))
    (local monthly-unsat
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;INTERVAL=12;COUNT=1;BYMONTHDAY=31"))
    (local monthly-err
      (assert-error #(Temporal.recurrence.occurrences monthly-unsat monthly-unsat-start {})
                    "unsatisfiable monthly generated BYMONTHDAY should throw instead of hanging"))
    (assert (tostring monthly-err):find "unsupported temporal recurrence expansion" 1 true))
  ```

  Register it near the other recurrence registrations:

  ```fennel
  (table.insert tests {:name "recurrence BYMONTHDAY generator bounds and rejections" :fn recurrence-bymonthday-generator-bounds-and-rejections})
  ```

- [ ] **Step 3: Run RED validation.**

  Run compile first:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/recurrence.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  ```

  Then run focused tests:

  ```bash
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected before implementation: monthly/yearly generator assertions fail because the current implementation is filter-only.

- [ ] **Step 4: Wire `plain-date-time` into the recurrence factory.**

  In `assets/lua/temporal.fnl`, change recurrence creation from:

  ```fennel
  (local recurrence (create-recurrence {:period period :standard standard}))
  ```

  to:

  ```fennel
  (local recurrence (create-recurrence {:period period :standard standard :plain-date-time plain-date-time}))
  ```

  In `assets/lua/temporal/recurrence.fnl`, update `create` to require `deps.plain-date-time.from-fields`, bind `(local plain-date-time deps.plain-date-time)`, and call the private occurrence dispatcher as `(occurrences period standard plain-date-time rule dtstart options)`.

- [ ] **Step 5: Add generated candidate helpers.**

  In `assets/lua/temporal/recurrence.fnl`, near the existing `plain-month` / `plain-day` helpers, add helpers with these exact responsibilities:

  ```fennel
  (fn plain-fields [plain]
    (plain:fields))

  (fn build-generated-candidate [plain-date-time dtstart year month day]
    (local source-fields (plain-fields dtstart))
    (local (ok value)
      (pcall plain-date-time.from-fields
             {:year year
              :month month
              :day day
              :hour source-fields.hour
              :minute source-fields.minute
              :second source-fields.second
              :nanosecond source-fields.nanosecond}))
    (if ok value nil))

  (fn before-dtstart? [candidate dtstart]
    (< (candidate:compare dtstart) 0))
  ```

- [ ] **Step 6: Add generator bucket helpers.**

  Add helpers that produce candidates for a period bucket:

  ```fennel
  (fn monthly-generated-candidates [plain-date-time rule dtstart anchor]
    (local fields (plain-fields anchor))
    (local generated [])
    (when (month-filter-allowed? rule anchor)
      (each [_ day (ipairs rule.by-month-day)]
        (local candidate (build-generated-candidate plain-date-time dtstart fields.year fields.month day))
        (when candidate
          (table.insert generated candidate))))
    generated)

  (fn yearly-generated-months [rule dtstart]
    (if rule.by-month
        rule.by-month
        [(plain-month dtstart)]))

  (fn yearly-generated-candidates [plain-date-time rule dtstart anchor]
    (local fields (plain-fields anchor))
    (local generated [])
    (each [_ month (ipairs (yearly-generated-months rule dtstart))]
      (each [_ day (ipairs rule.by-month-day)]
        (local candidate (build-generated-candidate plain-date-time dtstart fields.year month day))
        (when candidate
          (table.insert generated candidate))))
    generated)
  ```

- [ ] **Step 7: Add generator bound helpers.**

  Add a helper for candidate insertion:

  ```fennel
  (fn append-generated-candidates [results bounds dtstart candidates]
    (each [_ candidate (ipairs candidates)]
      (when (and (not (limit-reached? results bounds))
                 (not (before-dtstart? candidate dtstart))
                 (within-until? candidate bounds.until))
        (table.insert results candidate))))
  ```

  Do not stop within a bucket on the first candidate after `UNTIL`, because caller-provided `BYMONTHDAY` order can be non-chronological.

- [ ] **Step 8: Add generator satisfiability checks.**

  Add helpers that scan finite Gregorian cycles:

  ```fennel
  (fn generated-candidates-for-anchor [plain-date-time rule dtstart anchor]
    (if (= rule.freq :monthly)
        (monthly-generated-candidates plain-date-time rule dtstart anchor)
        (= rule.freq :yearly)
        (yearly-generated-candidates plain-date-time rule dtstart anchor)
        []))

  (fn generator-cycle [rule]
    (if (= rule.freq :monthly)
        (/ 4800 (gcd rule.interval 4800))
        (= rule.freq :yearly)
        (/ 400 (gcd rule.interval 400))
        (error "unsupported temporal recurrence expansion")))

  (fn assert-generator-filters-satisfiable [period plain-date-time rule dtstart]
    (local cycle (generator-cycle rule))
    (var index 0)
    (var satisfiable false)
    (while (and (< index cycle) (not satisfiable))
      (local anchor
        (if (= index 0)
            dtstart
            (period.add-to-plain-date-time
              dtstart
              (calendar-step-period rule.freq (* index rule.interval)))))
      (each [_ candidate (ipairs (generated-candidates-for-anchor plain-date-time rule dtstart anchor))]
        (when candidate
          (set satisfiable true)))
      (set index (+ index 1)))
    (when (not satisfiable)
      (error "unsupported temporal recurrence expansion")))
  ```

- [ ] **Step 9: Add generator calendar expansion.**

  Add `expand-calendar-generator` near `expand-calendar`:

  ```fennel
  (fn expand-calendar-generator [period plain-date-time rule dtstart bounds]
    (when rule.by-day
      (error "unsupported temporal recurrence expansion"))
    (period.add-to-plain-date-time dtstart (calendar-step-period rule.freq 0))
    (assert-generator-filters-satisfiable period plain-date-time rule dtstart)
    (local results [])
    (var index 0)
    (var done false)
    (while (and (not done) (not (limit-reached? results bounds)))
      (local anchor
        (if (= index 0)
            dtstart
            (period.add-to-plain-date-time
              dtstart
              (calendar-step-period rule.freq (* index rule.interval)))))
      (when (and bounds.until (> (anchor:compare bounds.until) 0))
        (set done true))
      (when (not done)
        (append-generated-candidates
          results
          bounds
          dtstart
          (generated-candidates-for-anchor plain-date-time rule dtstart anchor))
        (set index (+ index 1))))
    results)
  ```

  The `anchor > UNTIL` stop is safe for later period buckets because monthly/yearly anchor buckets are monotonic by period index; within a bucket, individual generated candidates are still checked independently.

- [ ] **Step 10: Route monthly/yearly BYMONTHDAY rules through generator expansion.**

  Change the private `occurrences` signature to include `plain-date-time`.

  In the monthly/yearly dispatch, use:

  ```fennel
  (if (or (= rule.freq :monthly) (= rule.freq :yearly))
      (if rule.by-month-day
          (expand-calendar-generator period plain-date-time rule dtstart bounds)
          (expand-calendar period rule dtstart bounds))
      (= rule.freq :daily)
      (expand-daily rule dtstart bounds)
      (= rule.freq :weekly)
      (expand-weekly rule dtstart bounds)
      (error "unsupported temporal recurrence expansion"))
  ```

  Keep daily/weekly dispatch unchanged so daily/weekly `BYMONTHDAY` remains filter-only.

- [ ] **Step 11: Run GREEN validation.**

  Compile check:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/recurrence.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  ```

  Constraints with a 600000 ms timeout:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets make constraints
  ```

  Focused recurrence tests:

  ```bash
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

- [ ] **Step 12: Commit Task 1.**

  ```bash
  git add assets/lua/temporal.fnl assets/lua/temporal/recurrence.fnl assets/lua/tests/test-temporal-parsing-recurrence.fnl
  git commit -m "feat(temporal): generate monthly yearly BYMONTHDAY recurrences"
  ```

  The implementer report must include RED evidence, compile-check evidence, constraints evidence with a constraint-impact note, focused-test evidence, and coverage rationale.

### Task 2: Documentation and Final Validation

**Files:**
- Modify: `docs/dev/features/temporal-parsing-recurrence.md`

**Interfaces:**
- Consumes: Task 1 monthly/yearly generator behavior.
- Produces: docs explaining frequency-dependent `BYMONTHDAY`, invalid-day skipping, bounds, and deferred full-RFC5545 behavior.

- [ ] **Step 1: Update recurrence support docs.**

  In `docs/dev/features/temporal-parsing-recurrence.md`, replace the current RRULE subset paragraph with text that states:

  ```markdown
  The bounded RRULE subset supports `FREQ` values `DAILY`, `WEEKLY`, `MONTHLY`, and `YEARLY`, plus `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY`, `BYMONTH`, and `BYMONTHDAY`. `BYMONTH` accepts integer months `1..12`. `BYMONTHDAY` accepts positive integer month days `1..31`: daily and weekly rules use it as an inclusion filter over existing candidates, while monthly and yearly rules generate requested valid month days inside selected period buckets. Invalid generated dates such as February 31 are skipped, not clamped. Generated candidates before `DTSTART` are skipped. Yearly `BYMONTHDAY` uses `BYMONTH` months when present and otherwise uses the `DTSTART` anchor month; monthly `BYMONTH` filters the monthly anchor grid rather than generating extra months. Compact local `UNTIL=YYYYMMDDTHHMMSS` bounds occurrence expansion inclusively and can satisfy the finite-bound requirement without `COUNT` or `options.limit`; `COUNT`, `options.limit`, and `UNTIL` stop expansion at the earliest reached bound.
  ```

- [ ] **Step 2: Update deferred full-RFC5545 bullet.**

  Replace the existing `Full RFC5545` bullet with:

  ```markdown
  - **Full RFC5545:** Deferred. The current RRULE subset is intentionally small; timezone-aware recurrence, UTC/instant `UNTIL` expansion, date-only `UNTIL`, fractional `UNTIL`, negative `BYMONTHDAY`, ordinal `BYDAY`, `BYSETPOS`, `WKST`, `RDATE`, `EXDATE`, and full RFC5545 candidate-set expansion require separate semantics and compatibility tests.
  ```

- [ ] **Step 3: Run docs consistency check.**

  ```bash
  rtk rg "BYMONTHDAY|generate|filter|Full RFC5545|negative BYMONTHDAY" docs/dev/features/temporal-parsing-recurrence.md docs/specs/2026-09-27-temporal-rrule-bymonthday-generator-design.md docs/plans/2026-09-27-temporal-rrule-bymonthday-generator.md
  ```

- [ ] **Step 4: Run final compile check.**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/recurrence.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  ```

- [ ] **Step 5: Run final constraints.**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets make constraints
  ```

- [ ] **Step 6: Run final focused recurrence tests.**

  ```bash
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

- [ ] **Step 7: Run full local suite.**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- [ ] **Step 8: Commit Task 2.**

  ```bash
  git add docs/dev/features/temporal-parsing-recurrence.md
  git commit -m "docs(temporal): document BYMONTHDAY generator semantics"
  ```

  The implementer report must include docs check evidence, compile-check evidence, constraints evidence with a constraint-impact note, focused-test evidence, full-suite evidence, and coverage rationale.
