# Temporal Monthly and Yearly Recurrence Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add bounded monthly and yearly expansion to `Temporal.recurrence.occurrences` using existing `Temporal.period` calendar arithmetic.

**Architecture:** Convert recurrence to a dependency-injected Fennel factory that receives `Temporal.period`, matching the existing interval factory pattern. Generate monthly/yearly occurrences anchor-based from the original `dtstart`, using `Temporal.period.add-to-plain-date-time` with multiplied month/year offsets so month-end and leap-day clamping does not drift.

**Tech Stack:** Space Fennel modules, existing `Temporal.period` API, native `PlainDateTime:add-calendar` through existing bindings, project-native Fennel validation through `tools.fennel-check`, constraints, and focused Fennel tests.

## Global Constraints

- Expand simple `:monthly` recurrence rules in `Temporal.recurrence.occurrences`.
- Expand simple `:yearly` recurrence rules in `Temporal.recurrence.occurrences`.
- Preserve existing `Temporal.recurrence.from`, `parse-rrule`, and `to-rrule` public behavior.
- Reuse `Temporal.period.add-to-plain-date-time` for calendar arithmetic.
- Preserve `dtstart` time-of-day in monthly/yearly occurrences.
- Keep expansion bounded by `rule.count`, `options.limit`, or the smaller of both.
- Reject monthly/yearly `BYDAY` during occurrence expansion.
- Full RFC5545 monthly/yearly selector support is out of scope.
- `BYMONTH`, `BYMONTHDAY`, ordinal `BYDAY`, `BYSETPOS`, week-number, or set-position support is out of scope.
- Applying `BYDAY` filters to monthly/yearly expansion is out of scope.
- Making `UNTIL` an expansion bound is out of scope.
- Timezone-aware or DST-aware recurrence is out of scope.
- Recurrence over `Instant` or `ZonedDateTime` values is out of scope.
- C++ temporal core changes or native recurrence APIs are out of scope.
- Native `Period` userdata is out of scope.
- Public compatibility shims for direct `require :temporal/recurrence` or `require :temporal/natural` consumers outside the public `(require :temporal)` facade are out of scope.

---

## File Structure

- `assets/lua/temporal.fnl`
  - Owns construction of the public `Temporal` facade.
  - Instantiate `period`, `recurrence`, and `natural` in dependency order.
- `assets/lua/temporal/recurrence.fnl`
  - Owns recurrence rule normalization, RRULE parse/format, and occurrence expansion.
  - Convert export to a factory receiving `{:period period}`.
  - Add monthly/yearly calendar expansion in Task 2.
- `assets/lua/temporal/natural.fnl`
  - Owns the tiny deterministic natural parser.
  - Convert export to a factory receiving `{:recurrence recurrence}` so `every Tuesday` keeps using the instantiated recurrence module.
- `assets/lua/tests/test-temporal-parsing-recurrence.fnl`
  - Owns focused tests for standard/pattern/recurrence/expression/natural behavior.
  - Add monthly/yearly recurrence regression tests.
- `docs/dev/features/temporal-parsing-recurrence.md`
  - Canonical parsing/recurrence documentation.
- `docs/dev/features/temporal-calendar-periods.md`
  - Canonical period documentation and cross-reference for recurrence period arithmetic.

---

### Task 1: Factory Wiring for Recurrence and Natural

**Files:**
- Modify: `assets/lua/temporal.fnl`
- Modify: `assets/lua/temporal/recurrence.fnl`
- Modify: `assets/lua/temporal/natural.fnl`
- Test: `assets/lua/tests/test-temporal-parsing-recurrence.fnl`

**Interfaces:**
- Consumes:
  - `period.add-to-plain-date-time(plain, period-table) -> PlainDateTime`
  - Existing recurrence table functions: `from`, `parse-rrule`, `to-rrule`, `occurrences`
- Produces:
  - `create-recurrence(deps: {:period table}) -> recurrence table`
  - `create-natural(deps: {:recurrence table}) -> natural table`
  - Public facade still exposes `Temporal.recurrence` and `Temporal.natural` through `(require :temporal)`.

- [ ] **Step 1: Convert recurrence export to a factory without changing behavior.**

  In `assets/lua/temporal/recurrence.fnl`, replace the final table export:

  ```fennel
  {:from from
   :parse-rrule parse-rrule
   :to-rrule to-rrule
   :occurrences occurrences}
  ```

  with a factory that validates the dependency and returns the same public table:

  ```fennel
  (fn create [deps]
    (when (not (and deps deps.period deps.period.add-to-plain-date-time))
      (error "temporal recurrence requires period dependency"))
    {:from from
     :parse-rrule parse-rrule
     :to-rrule to-rrule
     :occurrences occurrences})

  create
  ```

  Do not remove the current monthly/yearly unsupported check in this task.

- [ ] **Step 2: Convert natural export to a factory.**

  In `assets/lua/temporal/natural.fnl`, remove:

  ```fennel
  (local recurrence (require :temporal/recurrence))
  ```

  Wrap `parse-every-weekday` and `parse` in a factory so they close over the injected recurrence:

  ```fennel
  (fn create [deps]
    (when (not (and deps deps.recurrence deps.recurrence.from))
      (error "temporal natural parser requires recurrence dependency"))
    (local recurrence deps.recurrence)

    (fn parse-every-weekday [text]
      (local weekday (parse-weekday-expression text "every"))
      (when weekday
        {:kind :recurrence
         :rule (recurrence.from {:freq :weekly :by-day [weekday]})}))

    (fn parse [input]
      (when (not= (type input) :string)
        (unsupported))
      (local trimmed (trim input))
      (local text (trimmed:lower))
      (local relative (parse-relative text))
      (local next-weekday (parse-next-weekday text))
      (local every-weekday (parse-every-weekday text))
      (if (= text "today")
          {:kind :relative-date :amount 0 :unit :day}
          (= text "tomorrow")
          {:kind :relative-date :amount 1 :unit :day}
          relative
          relative
          next-weekday
          next-weekday
          every-weekday
          every-weekday
          (unsupported)))

    {:parse parse})

  create
  ```

  Keep the existing `parse` decision logic exactly the same inside the factory. Do not introduce `let`, `cond`, or direct mutation outside existing style.

- [ ] **Step 3: Update the public temporal facade assembly.**

  In `assets/lua/temporal.fnl`:

  - Change `(local recurrence (require :temporal/recurrence))` to:

    ```fennel
    (local create-recurrence (require :temporal/recurrence))
    ```

  - Change `(local natural (require :temporal/natural))` to:

    ```fennel
    (local create-natural (require :temporal/natural))
    ```

  - After `period` is created, instantiate recurrence and natural:

    ```fennel
    (local standard (create-standard base))
    (local period (create-period base))
    (local recurrence (create-recurrence {:period period}))
    (local natural (create-natural {:recurrence recurrence}))
    (local interval (create-interval {:standard standard :period period}))
    ```

  - Keep the public return table keys `:period period`, `:recurrence recurrence`, and `:natural natural`.

- [ ] **Step 4: Run focused validation for unchanged behavior.**

  Compile check:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/recurrence.fnl --file assets/lua/temporal/natural.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  ```

  Focused tests:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected: existing tests pass; monthly/yearly still unsupported.

- [ ] **Step 5: Commit Task 1.**

  ```bash
  git add assets/lua/temporal.fnl assets/lua/temporal/recurrence.fnl assets/lua/temporal/natural.fnl
  git commit -m "refactor(temporal): inject recurrence dependencies"
  ```

  The report must include compile-check evidence, focused-test evidence, constraint-impact note `not applicable`, and coverage rationale.

---

### Task 2: Monthly and Yearly Occurrence Expansion

**Files:**
- Modify: `assets/lua/temporal/recurrence.fnl`
- Modify: `assets/lua/tests/test-temporal-parsing-recurrence.fnl`

**Interfaces:**
- Consumes:
  - Injected `period.add-to-plain-date-time(plain, period-table) -> PlainDateTime`
  - Existing `occurrence-limit(rule, options) -> positive integer`
- Produces:
  - `Temporal.recurrence.occurrences(rule, dtstart, options) -> PlainDateTime[]` supports `:monthly` and `:yearly`.

- [ ] **Step 1: Add failing monthly/yearly recurrence tests.**

  In `assets/lua/tests/test-temporal-parsing-recurrence.fnl`, add these helpers near the recurrence tests:

  ```fennel
  (fn assert-occurrence-strings [actual expected]
    (assert (= (# actual) (# expected)))
    (each [index value (ipairs expected)]
      (assert (= ((. actual index):to-string) value))))
  ```

  Add a monthly test:

  ```fennel
  (fn recurrence-monthly-anchor-clamps-without-drift []
    (local dtstart (Temporal.plain-date-time.parse "2026-01-31T10:11:12"))
    (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=4"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences rule dtstart {})
      ["2026-01-31T10:11:12"
       "2026-02-28T10:11:12"
       "2026-03-31T10:11:12"
       "2026-04-30T10:11:12"]))
  ```

  Add a yearly test:

  ```fennel
  (fn recurrence-yearly-leap-day-anchor-clamps-without-drift []
    (local dtstart (Temporal.plain-date-time.parse "2028-02-29T10:11:12"))
    (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;COUNT=5"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences rule dtstart {})
      ["2028-02-29T10:11:12"
       "2029-02-28T10:11:12"
       "2030-02-28T10:11:12"
       "2031-02-28T10:11:12"
       "2032-02-29T10:11:12"]))
  ```

  Add interval/limit/UNTIL/BYDAY boundary test:

  ```fennel
  (fn recurrence-monthly-yearly-bounds-and-rejections []
    (local monthly-start (Temporal.plain-date-time.parse "2026-01-31T10:11:12"))
    (local every-two-months (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;INTERVAL=2;COUNT=3"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences every-two-months monthly-start {})
      ["2026-01-31T10:11:12"
       "2026-03-31T10:11:12"
       "2026-05-31T10:11:12"])

    (local yearly-start (Temporal.plain-date-time.parse "2028-02-29T10:11:12"))
    (local yearly (Temporal.recurrence.from {:freq :yearly :interval 2}))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences yearly yearly-start {:limit 2})
      ["2028-02-29T10:11:12"
       "2030-02-28T10:11:12"])

    (local until-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=3;UNTIL=20260131T000000Z"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences until-rule monthly-start {})
      ["2026-01-31T10:11:12"
       "2026-02-28T10:11:12"
       "2026-03-31T10:11:12"])

    (assert-error #(Temporal.recurrence.occurrences
                     (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=1;BYDAY=MO")
                     monthly-start
                     {})
                  "monthly BYDAY expansion should throw"))
  ```

  Register the three tests near the existing recurrence tests.

- [ ] **Step 2: Run the focused test and verify the failure.**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected before implementation: failure containing `unsupported temporal recurrence expansion` for monthly/yearly expansion.

- [ ] **Step 3: Make `occurrences` close over the injected period dependency.**

  In `assets/lua/temporal/recurrence.fnl`, move the `occurrences` function inside `create` or make it call a private helper that receives `deps.period`. The implementation must use the injected dependency, not direct `require`.

- [ ] **Step 4: Add monthly/yearly helpers.**

  Add helper logic equivalent to:

  ```fennel
  (fn calendar-step-period [freq offset]
    (if (= freq :monthly)
        {:months offset}
        (= freq :yearly)
        {:years offset}
        (error "unsupported temporal recurrence expansion")))

  (fn expand-calendar [period rule dtstart limit]
    (when rule.by-day
      (error "unsupported temporal recurrence expansion"))
    (local results [])
    (var index 0)
    (while (< index limit)
      (if (= index 0)
          (table.insert results dtstart)
          (do
            (local offset (* index rule.interval))
            (table.insert results
                          (period.add-to-plain-date-time
                            dtstart
                            (calendar-step-period rule.freq offset)))))
      (set index (+ index 1)))
    results)
  ```

  Keep `calendar-step-period` private.

- [ ] **Step 5: Route monthly/yearly through the new helper.**

  In `occurrences`, remove the early monthly/yearly unsupported check. After computing `rule`, `occurrence-options`, and `limit`, extend the existing multi-branch `if` so the first branch is:

  ```fennel
  (or (= rule.freq :monthly) (= rule.freq :yearly))
  (expand-calendar period rule dtstart limit)
  ```

  The existing `:daily` branch body, `:weekly` branch body, and final `(error "unsupported temporal recurrence expansion")` branch must remain byte-for-byte equivalent except for indentation required by the new outer branch.

- [ ] **Step 6: Run focused validation for Task 2.**

  Compile check:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/recurrence.fnl --file assets/lua/temporal/natural.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  ```

  Constraints:

  ```bash
  make constraints
  ```

  Focused tests:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

- [ ] **Step 7: Commit Task 2.**

  ```bash
  git add assets/lua/temporal/recurrence.fnl assets/lua/tests/test-temporal-parsing-recurrence.fnl
  git commit -m "feat(temporal): expand monthly yearly recurrences"
  ```

  The report must include failing-test evidence, compile-check evidence, constraints evidence with constraint-impact note, focused-test evidence, and coverage rationale.

---

### Task 3: Developer Documentation

**Files:**
- Modify: `docs/dev/features/temporal-parsing-recurrence.md`
- Modify: `docs/dev/features/temporal-calendar-periods.md`

**Interfaces:**
- Consumes:
  - Final monthly/yearly recurrence semantics from Task 2.
- Produces:
  - Docs that distinguish supported bounded monthly/yearly expansion from deferred RFC5545 selector support.

- [ ] **Step 1: Update recurrence docs.**

  In `docs/dev/features/temporal-parsing-recurrence.md`, replace statements that monthly/yearly expansion is deferred with wording that says:

  ```markdown
  Occurrence expansion supports bounded daily, weekly, monthly, and yearly rules. Monthly and yearly rules use anchor-based `Temporal.period` calendar arithmetic from the original `dtstart`, preserve time-of-day, and require `COUNT` or `options.limit`. `UNTIL` remains parse/serialize-only and is not an expansion bound in this slice. Monthly/yearly `BYDAY` and broader RFC5545 selectors remain unsupported during expansion.
  ```

- [ ] **Step 2: Update calendar period docs.**

  In `docs/dev/features/temporal-calendar-periods.md`, remove any blanket statement that monthly/yearly recurrence expansion remains deferred. Add:

  ```markdown
  `Temporal.recurrence.occurrences` reuses `Temporal.period.add-to-plain-date-time` for bounded plain-date-time monthly and yearly expansion. Full RFC5545 selectors, timezone-aware recurrence, and DST-aware recurrence remain deferred.
  ```

- [ ] **Step 3: Run docs-focused validation.**

  ```bash
  rg "monthly|yearly|UNTIL|BYDAY|anchor|Temporal.period.add-to-plain-date-time|RFC5545" docs/dev/features/temporal-parsing-recurrence.md docs/dev/features/temporal-calendar-periods.md
  ```

- [ ] **Step 4: Run final local validation for the docs task.**

  Compile check:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/recurrence.fnl --file assets/lua/temporal/natural.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  ```

  Constraints:

  ```bash
  make constraints
  ```

  Focused tests:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

- [ ] **Step 5: Commit Task 3.**

  ```bash
  git add docs/dev/features/temporal-parsing-recurrence.md docs/dev/features/temporal-calendar-periods.md
  git commit -m "docs(temporal): document monthly yearly recurrence"
  ```

  The report must include docs-search evidence, compile/constraints/focused-test evidence, constraint-impact note `not applicable`, and coverage rationale.

---

## Final Review and Finishing Validation

After all tasks pass reviewer gates, request a whole-branch reviewer pass against:

- `docs/specs/2026-09-27-temporal-monthly-yearly-recurrence-design.md`
- `docs/plans/2026-09-27-temporal-monthly-yearly-recurrence.md`
- `assets/lua/temporal.fnl`
- `assets/lua/temporal/recurrence.fnl`
- `assets/lua/temporal/natural.fnl`
- `assets/lua/tests/test-temporal-parsing-recurrence.fnl`
- `docs/dev/features/temporal-parsing-recurrence.md`
- `docs/dev/features/temporal-calendar-periods.md`

Then invoke finishing-a-development-branch. Required final validation should include at least:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/recurrence.fnl --file assets/lua/temporal/natural.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
rg "monthly|yearly|UNTIL|BYDAY|anchor|Temporal.period.add-to-plain-date-time|RFC5545" docs/dev/features/temporal-parsing-recurrence.md docs/dev/features/temporal-calendar-periods.md
```

Because this changes public temporal facade wiring, finishing should also run the broader local suite unless current project conditions make that impossible:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```
