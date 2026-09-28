# Temporal RRULE BYDAY Generator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Support simple non-ordinal `BYDAY` generation for monthly and yearly recurrence rules.

**Architecture:** Reuse the existing monthly/yearly generator path that was added for positive `BYMONTHDAY`. Keep parsing and serialization unchanged because simple weekday `BYDAY` already parses; remove the monthly/yearly expansion-time rejection and generate matching weekday candidates inside anchor-derived calendar buckets. Bounds, lower-bound skipping, `BYMONTHDAY` intersection, and invalid-date skipping continue through existing generator helpers.

**Tech Stack:** Space Fennel, `assets/lua/temporal/recurrence.fnl`, `assets/lua/tests/test-temporal-parsing-recurrence.fnl`, native `PlainDateTime:fields`, native `PlainDateTime:iso-weekday`, native `plain-date-time.from-fields`, project-native `tools.fennel-check`, `make constraints`, focused Fennel recurrence tests, and full local `make test` validation.

## Global Constraints

- Keep existing `BYDAY` parse/serialize shape for simple weekdays only: `MO`, `TU`, `WE`, `TH`, `FR`, `SA`, `SU`.
- Daily and weekly `BYDAY` behavior remains unchanged.
- Monthly `BYDAY` generates matching weekdays inside selected monthly buckets.
- Yearly `BYDAY` generates matching weekdays inside selected yearly buckets.
- Monthly/yearly period buckets remain anchor-based from original `DTSTART` through `Temporal.period.add-to-plain-date-time`; no iterative drift is introduced.
- Generated weekday candidates preserve the original `DTSTART` time-of-day and nanosecond fields.
- Generated candidates before `DTSTART` are skipped.
- Generated candidates after local compact `UNTIL` are not emitted; `UNTIL` remains inclusive.
- `COUNT` and caller `options.limit` count returned occurrences after generated-date skipping, `DTSTART` lower-bound skipping, all filters, and `UNTIL` exclusion.
- For monthly rules, `BYMONTH` continues to filter the monthly anchor grid; it does not generate extra months.
- For yearly rules, `BYMONTH` supplies the generated month list when present; otherwise yearly `BYDAY` uses the `DTSTART` anchor month.
- Preserve caller-provided `BYMONTH` order for yearly generated months.
- When `BYDAY` and positive `BYMONTHDAY` are both present on monthly/yearly rules, generated candidates must satisfy both selectors.
- Positive `BYMONTHDAY` generation semantics remain unchanged.
- Unsatisfiable monthly/yearly generator combinations throw `unsupported temporal recurrence expansion` instead of hanging.
- Ordinal `BYDAY` strings such as `1MO` and `-1FR` continue to throw `invalid RRULE BYDAY` during parse.
- Unknown weekday tokens and empty `BYDAY` members continue to throw.
- Existing monthly/yearly rules without `BYDAY` and without `BYMONTHDAY` continue to use the existing anchor/filter expansion path.
- Exclude ordinal `BYDAY` semantics such as `1MO` and `-1FR`.
- Exclude `BYSETPOS`, `WKST`, `RDATE`, `EXDATE`, `BYWEEKNO`, and recurrence sets.
- Exclude full RFC5545 candidate-set expansion.
- Exclude timezone-aware recurrence, DST handling, UTC `UNTIL` expansion, and recurrence over `Instant` or `ZonedDateTime`.
- Exclude natural-language recurrence changes.
- Exclude native C++ temporal core changes.
- Exclude public recurrence-set APIs.
- Use project-native Fennel validation only: touched-file `tools.fennel-check`, then `make constraints`, then focused Fennel tests.
- Run the full local suite during final validation because public recurrence behavior changes.

---

## File Structure

- `assets/lua/temporal/recurrence.fnl` owns recurrence generation. This slice extends generator helpers and routes monthly/yearly simple `BYDAY` through generator expansion.
- `assets/lua/tests/test-temporal-parsing-recurrence.fnl` is the focused temporal recurrence suite. This slice replaces monthly/yearly `BYDAY` rejection assertions with generation coverage, while adding ordinal rejection coverage.
- `docs/dev/features/temporal-parsing-recurrence.md` documents supported recurrence behavior and deferred RFC5545 boundaries.

### Task 1: Monthly/Yearly Simple BYDAY Generator Behavior

**Files:**
- Modify: `assets/lua/temporal/recurrence.fnl`
- Test: `assets/lua/tests/test-temporal-parsing-recurrence.fnl`

**Interfaces:**
- Consumes: existing `build-generated-candidate(plain-date-time, dtstart, year, month, day) -> PlainDateTime|nil`.
- Consumes: existing `by-day-allowed?(days, weekday) -> boolean`.
- Consumes: existing `yearly-generated-months(rule, dtstart) -> integer[]`.
- Consumes: existing `append-generated-candidates(results, bounds, dtstart, candidates)`.
- Produces: monthly/yearly occurrence support for non-ordinal `rule.by-day`.
- Produces: helper `by-day-filter-allowed?(rule, candidate) -> boolean`.
- Produces: helper `month-weekday-candidates(plain-date-time, rule, dtstart, year, month) -> PlainDateTime[]`.

- [ ] **Step 1: Replace monthly/yearly BYDAY rejection assertions.**

  In `assets/lua/tests/test-temporal-parsing-recurrence.fnl`, edit `recurrence-monthly-yearly-bounds-and-rejections` and remove the two assertions that currently expect these rules to throw:

  ```fennel
  "RRULE:FREQ=MONTHLY;COUNT=1;BYDAY=MO"
  "RRULE:FREQ=YEARLY;COUNT=1;BYDAY=MO"
  ```

  Keep the preceding monthly interval, yearly interval, and UTC `UNTIL` assertions unchanged.

- [ ] **Step 2: Replace the BYMONTH-plus-BYDAY rejection with generation coverage.**

  In `recurrence-bymonth-filters-occurrences`, replace the final assertion that currently expects `RRULE:FREQ=MONTHLY;COUNT=1;BYMONTH=1;BYDAY=MO` to throw with this assertion:

  ```fennel
  (local monthly-byday-with-bymonth
    (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=2;BYMONTH=2;BYDAY=MO"))
  (assert-occurrence-strings
    (Temporal.recurrence.occurrences monthly-byday-with-bymonth monthly-start {})
    ["2027-02-01T10:11:12"
     "2027-02-08T10:11:12"])
  ```

  This pins monthly `BYMONTH` as a filter over the monthly anchor grid: starting from January 2026 with monthly interval 1, February 2026 is before the January 31 lower bound for February Mondays, so the first generated matching bucket is February 2027 because the anchor grid reaches February again.

- [ ] **Step 3: Add monthly BYDAY generation tests.**

  Add this function near the other recurrence occurrence tests:

  ```fennel
  (fn recurrence-monthly-byday-generates-weekdays []
    (local dtstart (Temporal.plain-date-time.parse "2026-01-14T09:00:00"))
    (local monday-rule
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=4;BYDAY=MO"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences monday-rule dtstart {})
      ["2026-01-19T09:00:00"
       "2026-01-26T09:00:00"
       "2026-02-02T09:00:00"
       "2026-02-09T09:00:00"])

    (local ordered-rule
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=4;BYDAY=WE,MO"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences ordered-rule dtstart {})
      ["2026-01-14T09:00:00"
       "2026-01-19T09:00:00"
       "2026-01-21T09:00:00"
       "2026-01-26T09:00:00"]))
  ```

  Register it near the other recurrence tests:

  ```fennel
  (table.insert tests {:name "recurrence monthly BYDAY generates weekdays" :fn recurrence-monthly-byday-generates-weekdays})
  ```

- [ ] **Step 4: Add yearly BYDAY generation tests.**

  Add this function after the monthly BYDAY test:

  ```fennel
  (fn recurrence-yearly-byday-generates-weekdays []
    (local november-start (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
    (local november-thursdays
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;COUNT=4;BYMONTH=11;BYDAY=TH"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences november-thursdays november-start {})
      ["2026-11-05T09:00:00"
       "2026-11-12T09:00:00"
       "2026-11-19T09:00:00"
       "2026-11-26T09:00:00"])

    (local anchor-month-start (Temporal.plain-date-time.parse "2026-05-20T09:00:00"))
    (local anchor-month-fridays
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;COUNT=3;BYDAY=FR"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences anchor-month-fridays anchor-month-start {})
      ["2026-05-22T09:00:00"
       "2026-05-29T09:00:00"
       "2027-05-07T09:00:00"]))
  ```

  Register it:

  ```fennel
  (table.insert tests {:name "recurrence yearly BYDAY generates weekdays" :fn recurrence-yearly-byday-generates-weekdays})
  ```

- [ ] **Step 5: Add BYDAY and BYMONTHDAY intersection tests.**

  Add this function after the yearly BYDAY test:

  ```fennel
  (fn recurrence-calendar-byday-combines-with-bymonthday []
    (local monthly-start (Temporal.plain-date-time.parse "2026-05-20T09:00:00"))
    (local monthly-rule
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=2;BYMONTHDAY=1,15;BYDAY=MO"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences monthly-rule monthly-start {})
      ["2026-06-01T09:00:00"
       "2026-06-15T09:00:00"])

    (local yearly-start (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
    (local yearly-rule
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;COUNT=2;BYMONTH=6;BYMONTHDAY=1,15;BYDAY=MO"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences yearly-rule yearly-start {})
      ["2026-06-01T09:00:00"
       "2026-06-15T09:00:00"]))
  ```

  Register it:

  ```fennel
  (table.insert tests {:name "recurrence calendar BYDAY combines with BYMONTHDAY" :fn recurrence-calendar-byday-combines-with-bymonthday})
  ```

- [ ] **Step 6: Add unsatisfiable and ordinal exclusion tests.**

  Add this function after the intersection test:

  ```fennel
  (fn recurrence-calendar-byday-unsatisfiable-and-ordinal-rejections []
    (local monthly-start (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
    (local monthly-unsat
      (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;INTERVAL=12;COUNT=1;BYMONTH=2;BYDAY=MO"))
    (local monthly-err
      (assert-error #(Temporal.recurrence.occurrences monthly-unsat monthly-start {})
                    "unsatisfiable monthly BYDAY should throw instead of hanging"))
    (assert (tostring monthly-err):find "unsupported temporal recurrence expansion" 1 true)

    (assert-error #(Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYDAY=1MO")
                  "ordinal monthly BYDAY should remain unsupported")
    (assert-error #(Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;BYDAY=-1FR")
                  "negative ordinal yearly BYDAY should remain unsupported"))
  ```

  Register it:

  ```fennel
  (table.insert tests {:name "recurrence calendar BYDAY unsatisfiable and ordinal rejections" :fn recurrence-calendar-byday-unsatisfiable-and-ordinal-rejections})
  ```

- [ ] **Step 7: Run RED validation.**

  First run the touched-file compile check:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/recurrence.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  ```

  Then run the focused recurrence suite:

  ```bash
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected before implementation: monthly/yearly `BYDAY` generation assertions fail because expansion currently throws `unsupported temporal recurrence expansion`.

- [ ] **Step 8: Add a BYDAY predicate for generated candidates.**

  In `assets/lua/temporal/recurrence.fnl`, near `candidate-calendar-filters-allowed?`, add:

  ```fennel
  (fn by-day-filter-allowed? [rule candidate]
    (if rule.by-day
        (by-day-allowed? rule.by-day (candidate:iso-weekday))
        true))
  ```

- [ ] **Step 9: Add weekday generation for a target month.**

  Near existing generator helpers, add:

  ```fennel
  (fn month-weekday-candidates [plain-date-time rule dtstart year month]
    (local generated [])
    (var day 1)
    (while (<= day 31)
      (local candidate (build-generated-candidate plain-date-time dtstart year month day))
      (when (and candidate (by-day-filter-allowed? rule candidate))
        (table.insert generated candidate))
      (set day (+ day 1)))
    generated)
  ```

- [ ] **Step 10: Update `monthly-generated-candidates`.**

  Replace `monthly-generated-candidates` with logic equivalent to:

  ```fennel
  (fn monthly-generated-candidates [plain-date-time rule dtstart anchor]
    (local fields (plain-fields anchor))
    (local generated [])
    (when (month-filter-allowed? rule anchor)
      (if rule.by-month-day
          (each [_ day (ipairs rule.by-month-day)]
            (local candidate (build-generated-candidate plain-date-time dtstart fields.year fields.month day))
            (when (and candidate (by-day-filter-allowed? rule candidate))
              (table.insert generated candidate)))
          rule.by-day
          (each [_ candidate (ipairs (month-weekday-candidates plain-date-time rule dtstart fields.year fields.month))]
            (table.insert generated candidate))))
    generated)
  ```

  This preserves `BYMONTHDAY` caller order when present, and uses ascending month-day order when generating all weekdays from `BYDAY` alone.

- [ ] **Step 11: Update `yearly-generated-candidates`.**

  Replace `yearly-generated-candidates` with logic equivalent to:

  ```fennel
  (fn yearly-generated-candidates [plain-date-time rule dtstart anchor]
    (local fields (plain-fields anchor))
    (local generated [])
    (each [_ month (ipairs (yearly-generated-months rule dtstart))]
      (if rule.by-month-day
          (each [_ day (ipairs rule.by-month-day)]
            (local candidate (build-generated-candidate plain-date-time dtstart fields.year month day))
            (when (and candidate (by-day-filter-allowed? rule candidate))
              (table.insert generated candidate)))
          rule.by-day
          (each [_ candidate (ipairs (month-weekday-candidates plain-date-time rule dtstart fields.year month))]
            (table.insert generated candidate))))
    generated)
  ```

- [ ] **Step 12: Route monthly/yearly BYDAY through generator expansion.**

  In `expand-calendar-generator`, remove the `when rule.by-day` rejection. In private `occurrences`, change the monthly/yearly dispatch from checking only `rule.by-month-day` to:

  ```fennel
  (if (or rule.by-month-day rule.by-day)
      (expand-calendar-generator period plain-date-time rule dtstart bounds)
      (expand-calendar period rule dtstart bounds))
  ```

  Keep `expand-calendar` rejecting `BYDAY` so unsupported routing mistakes still fail loudly.

- [ ] **Step 13: Run GREEN validation.**

  Compile check:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/recurrence.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  ```

  Constraints with a 600000 ms timeout:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets make constraints
  ```

  Focused recurrence suite:

  ```bash
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

- [ ] **Step 14: Commit Task 1.**

  ```bash
  git add assets/lua/temporal/recurrence.fnl assets/lua/tests/test-temporal-parsing-recurrence.fnl
  git commit -m "feat(temporal): generate monthly yearly BYDAY recurrences"
  ```

  The implementer report must include RED evidence, compile-check evidence, constraints evidence with a constraint-impact note, focused-test evidence, and coverage rationale.

### Task 2: Documentation and Final Validation

**Files:**
- Modify: `docs/dev/features/temporal-parsing-recurrence.md`

**Interfaces:**
- Consumes: Task 1 monthly/yearly simple `BYDAY` generator behavior.
- Produces: docs explaining simple `BYDAY` support across all supported frequencies and deferred ordinal/full-RFC5545 boundaries.

- [ ] **Step 1: Update recurrence docs.**

  In `docs/dev/features/temporal-parsing-recurrence.md`, replace the current bounded RRULE subset paragraph with this text:

  ```markdown
  The bounded RRULE subset supports `FREQ` values `DAILY`, `WEEKLY`, `MONTHLY`, and `YEARLY`, plus `INTERVAL`, `COUNT`, `UNTIL`, simple non-ordinal `BYDAY`, `BYMONTH`, and positive `BYMONTHDAY`. `BYDAY` accepts weekday values `MO`, `TU`, `WE`, `TH`, `FR`, `SA`, and `SU`: daily and weekly rules keep their existing scan/filter semantics, while monthly and yearly rules generate matching weekdays inside selected period buckets. `BYMONTH` accepts integer months `1..12`. `BYMONTHDAY` accepts positive integer month days `1..31`: daily and weekly rules use it as an inclusion filter over existing candidates, while monthly and yearly rules generate requested valid month days inside selected period buckets. Monthly/yearly `BYDAY` and `BYMONTHDAY` combine by intersection. Invalid generated dates such as February 31 are skipped, not clamped. Generated candidates before `DTSTART` are skipped. Yearly `BYDAY` and `BYMONTHDAY` use `BYMONTH` months when present and otherwise use the `DTSTART` anchor month; monthly `BYMONTH` filters the monthly anchor grid rather than generating extra months. Compact local `UNTIL=YYYYMMDDTHHMMSS` bounds occurrence expansion inclusively and can satisfy the finite-bound requirement without `COUNT` or `options.limit`; `COUNT`, `options.limit`, and `UNTIL` stop expansion at the earliest reached bound.
  ```

- [ ] **Step 2: Update deferred full-RFC5545 bullet.**

  Replace the existing `Full RFC5545` bullet with:

  ```markdown
  - **Full RFC5545:** Deferred. The current RRULE subset is intentionally small; timezone-aware recurrence, UTC/instant `UNTIL` expansion, date-only `UNTIL`, fractional `UNTIL`, negative `BYMONTHDAY`, ordinal `BYDAY`, `BYSETPOS`, `WKST`, `RDATE`, `EXDATE`, recurrence sets, and full RFC5545 candidate-set expansion require separate semantics and compatibility tests.
  ```

- [ ] **Step 3: Run docs consistency check.**

  ```bash
  rtk rg "BYDAY|BYMONTHDAY|BYSETPOS|WKST|RDATE|EXDATE|timezone-aware recurrence|recurrence sets" docs/dev/features/temporal-parsing-recurrence.md docs/specs/2026-09-28-temporal-rrule-byday-generator-design.md docs/plans/2026-09-28-temporal-rrule-byday-generator.md
  ```

- [ ] **Step 4: Run final compile check.**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/recurrence.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
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
  git commit -m "docs(temporal): document BYDAY generator semantics"
  ```

  The implementer report must include docs check evidence, compile-check evidence, constraints evidence with a constraint-impact note, focused-test evidence, full-suite evidence, and coverage rationale.
