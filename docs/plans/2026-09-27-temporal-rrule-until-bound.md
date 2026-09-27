# Temporal RRULE UNTIL Bound Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add supported local RRULE `UNTIL` values as inclusive finite expansion bounds for temporal recurrence occurrences.

**Architecture:** Keep recurrence normalization and RRULE round-tripping compatible by preserving `rule.until` as a raw string. Parse `UNTIL` lazily inside `Temporal.recurrence.occurrences`, where expansion can decide whether the string is a supported local plain-date-time bound or a recognized-but-unsupported UTC instant bound. Apply the resulting bound to the existing daily, weekly, monthly, and yearly candidate streams without adding full RFC5545 candidate-set machinery.

**Tech Stack:** Space Fennel modules, native Temporal `PlainDateTime` comparison, `temporal.standard.parse-plain-date-time`, project-native `tools.fennel-check`, `make constraints`, and focused Fennel recurrence tests.

## Global Constraints

- Keep canonical option key `:until`.
- Keep `Temporal.recurrence.parse-rrule` storing `UNTIL` as the raw RRULE string.
- Keep `Temporal.recurrence.to-rrule` emitting the raw `UNTIL` string unchanged.
- During `Temporal.recurrence.occurrences`, parse compact local `UNTIL` values of the form `YYYYMMDDTHHMMSS` as `PlainDateTime` bounds.
- Treat `UNTIL` as inclusive: return candidates where `candidate <= until`.
- Allow supported local `UNTIL` to satisfy the finite-bound requirement without `COUNT` or `options.limit`.
- Combine `COUNT`, `options.limit`, and `UNTIL` by stopping at the earliest reached bound.
- Return an empty occurrence list when a supported local `UNTIL` is before `DTSTART`.
- Preserve existing `BYDAY` and `BYMONTH` filtering behavior; `COUNT` and `options.limit` continue to count returned occurrences after filters.
- Preserve monthly and yearly anchor-based expansion semantics.
- `Temporal.recurrence.from` validates only that `:until` is a string, preserving parse/serialize compatibility.
- Malformed `UNTIL` strings throw during occurrence expansion with a clear `invalid temporal recurrence UNTIL` error.
- Compact UTC `UNTIL=YYYYMMDDTHHMMSSZ` remains parse/serialize-compatible but throws during expansion with `unsupported temporal recurrence UNTIL` because recurrence candidates are currently plain date-times and no timezone context exists.
- Recurrence expansion with no `COUNT`, no `options.limit`, and no supported local `UNTIL` continues to throw a finite-bound error.
- Exclude timezone-aware recurrence and DST handling.
- Exclude comparing plain recurrence candidates against instants.
- Exclude date-only `UNTIL` values.
- Exclude fractional-second `UNTIL` values.
- Exclude offset `UNTIL` values other than the preserved-but-unsupported compact UTC `Z` form.
- Exclude full RFC5545 candidate-set expansion.
- Exclude `BYMONTHDAY`, `BYSETPOS`, `WKST`, `RDATE`, `EXDATE`, `BYWEEKNO`, and ordinal `BYDAY`.
- Exclude native C++ temporal core changes.
- Exclude public recurrence-set APIs.
- Use project-native Fennel validation only: touched-file `tools.fennel-check`, then `make constraints`, then focused Fennel tests.

---

## File Structure

- `assets/lua/temporal.fnl` wires the public `Temporal.recurrence` facade. This slice changes the recurrence factory call to inject the existing `standard` facade.
- `assets/lua/temporal/recurrence.fnl` owns RRULE parsing, normalization, serialization, and occurrence expansion. This slice adds private `UNTIL` parsing/bounds helpers and updates existing expansion loops.
- `assets/lua/tests/test-temporal-parsing-recurrence.fnl` is the focused behavioral test suite for temporal recurrence. This slice updates the existing parse-serialize-only `UNTIL` expectation and adds expansion-bound coverage.
- `docs/dev/features/temporal-parsing-recurrence.md` is the public developer documentation for the temporal parsing and recurrence feature. This slice replaces the parse/serialize-only `UNTIL` wording with supported local-bound semantics.

### Task 1: UNTIL-Aware Occurrence Expansion

**Files:**
- Modify: `assets/lua/temporal.fnl`
- Modify: `assets/lua/temporal/recurrence.fnl`
- Test: `assets/lua/tests/test-temporal-parsing-recurrence.fnl`

**Interfaces:**
- Consumes: existing `standard.parse-plain-date-time(text) -> PlainDateTime` from `assets/lua/temporal/standard.fnl`.
- Consumes: existing `PlainDateTime:compare(other) -> -1 | 0 | 1` native binding.
- Produces: recurrence factory dependency shape `create-recurrence {:period period :standard standard}`.
- Produces: private helper `parse-until standard text -> {:kind :plain-date-time :value PlainDateTime} | {:kind :instant}`.
- Produces: private helper `occurrence-bounds standard rule occurrence-options -> {:limit number-or-nil :until PlainDateTime-or-nil}`.
- Produces: `Temporal.recurrence.occurrences(rule, dtstart, options)` where supported local `rule.until` bounds expansion inclusively.

- [ ] **Step 1: Add focused failing tests for local UNTIL bounds.**

  In `assets/lua/tests/test-temporal-parsing-recurrence.fnl`, add this function after `recurrence-bymonth-filters-occurrences`:

  ```fennel
  (fn recurrence-until-bounds-occurrences []
    (local daily-start (Temporal.plain-date-time.parse "2026-09-22T09:00:00"))
    (local daily-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;UNTIL=20260924T090000"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences daily-rule daily-start {})
      ["2026-09-22T09:00:00"
       "2026-09-23T09:00:00"
       "2026-09-24T09:00:00"])

    (local before-start (Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;UNTIL=20260921T090000"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences before-start daily-start {})
      [])

    (local count-stops-after-until (Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;COUNT=10;UNTIL=20260923T090000"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences count-stops-after-until daily-start {})
      ["2026-09-22T09:00:00"
       "2026-09-23T09:00:00"])

    (assert-occurrence-strings
      (Temporal.recurrence.occurrences count-stops-after-until daily-start {:limit 1})
      ["2026-09-22T09:00:00"])

    (local weekly-start (Temporal.plain-date-time.parse "2026-09-22T09:00:00"))
    (local weekly-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=WEEKLY;BYDAY=TU;UNTIL=20261006T090000"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences weekly-rule weekly-start {})
      ["2026-09-22T09:00:00"
       "2026-09-29T09:00:00"
       "2026-10-06T09:00:00"])

    (local monthly-start (Temporal.plain-date-time.parse "2026-01-31T10:11:12"))
    (local monthly-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;UNTIL=20260228T101112"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences monthly-rule monthly-start {})
      ["2026-01-31T10:11:12"
       "2026-02-28T10:11:12"])

    (local yearly-start (Temporal.plain-date-time.parse "2028-02-29T10:11:12"))
    (local yearly-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;UNTIL=20300228T101112"))
    (assert-occurrence-strings
      (Temporal.recurrence.occurrences yearly-rule yearly-start {})
      ["2028-02-29T10:11:12"
       "2029-02-28T10:11:12"
       "2030-02-28T10:11:12"]))
  ```

  Add this registration near the other recurrence tests:

  ```fennel
  (table.insert tests {:name "recurrence UNTIL bounds occurrences" :fn recurrence-until-bounds-occurrences})
  ```

- [ ] **Step 2: Add focused failing tests for invalid and unsupported UNTIL.**

  In the existing `recurrence-monthly-yearly-bounds-and-rejections` function, replace the current `until-rule` assertion that expects ignored `UNTIL=20260131T000000Z` with this unsupported-UTC assertion:

  ```fennel
  (local until-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=3;UNTIL=20260131T000000Z"))
  (assert (= (Temporal.recurrence.to-rrule until-rule)
             "RRULE:FREQ=MONTHLY;COUNT=3;UNTIL=20260131T000000Z"))
  (local utc-err (assert-error #(Temporal.recurrence.occurrences until-rule monthly-start {})
                               "UTC UNTIL expansion should throw until timezone-aware recurrence exists"))
  (assert (tostring utc-err):find "unsupported temporal recurrence UNTIL" 1 true))
  ```

  In `recurrence-until-bounds-occurrences`, add malformed local checks before the closing parenthesis:

  ```fennel
  (local invalid-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;UNTIL=20260230T090000"))
  (local invalid-err (assert-error #(Temporal.recurrence.occurrences invalid-rule daily-start {})
                                   "invalid local UNTIL date should throw during expansion"))
  (assert (tostring invalid-err):find "invalid temporal recurrence UNTIL" 1 true)

  (local malformed-rule (Temporal.recurrence.from {:freq :daily :until "2026-09-24T09:00:00"}) )
  (local malformed-err (assert-error #(Temporal.recurrence.occurrences malformed-rule daily-start {})
                                     "non-compact UNTIL should throw during expansion"))
  (assert (tostring malformed-err):find "invalid temporal recurrence UNTIL" 1 true)
  ```

- [ ] **Step 3: Run the focused test to verify the RED state.**

  Run:

  ```bash
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected result before implementation: the new `recurrence UNTIL bounds occurrences` test fails because `UNTIL` alone is treated as unbounded and UTC `UNTIL` is not rejected during expansion.

- [ ] **Step 4: Wire the standard facade into recurrence creation.**

  In `assets/lua/temporal.fnl`, change the recurrence factory call from:

  ```fennel
  (local recurrence (create-recurrence {:period period}))
  ```

  to:

  ```fennel
  (local recurrence (create-recurrence {:period period :standard standard}))
  ```

- [ ] **Step 5: Require the standard dependency in the recurrence factory.**

  In `assets/lua/temporal/recurrence.fnl`, update the `create` function so it validates both dependencies and stores `standard`:

  ```fennel
  (fn create [deps]
    (when (not (and deps deps.period deps.period.add-to-plain-date-time))
      (error "temporal recurrence requires period dependency"))
    (when (not (and deps.standard deps.standard.parse-plain-date-time))
      (error "temporal recurrence requires standard dependency"))
    (local period deps.period)
    (local standard deps.standard)
    {:from from
     :parse-rrule parse-rrule
     :to-rrule to-rrule
     :occurrences (fn [rule dtstart options]
                    (occurrences period standard rule dtstart options))})
  ```

  Update the existing factory wiring test to expect `create-recurrence {}` to still throw; no new public assertion is required for the dependency message.

- [ ] **Step 6: Add private compact UNTIL helpers.**

  In `assets/lua/temporal/recurrence.fnl`, add these helpers near the existing parsing helpers:

  ```fennel
  (fn compact-local-until? [text]
    (and (= (type text) :string)
         (not= (text:match "^%d%d%d%d%d%d%d%dT%d%d%d%d%d%d$") nil)))

  (fn compact-utc-until? [text]
    (and (= (type text) :string)
         (not= (text:match "^%d%d%d%d%d%d%d%dT%d%d%d%d%d%dZ$") nil)))

  (fn compact-local-until->iso [text]
    (.. (text:sub 1 4)
        "-"
        (text:sub 5 6)
        "-"
        (text:sub 7 8)
        "T"
        (text:sub 10 11)
        ":"
        (text:sub 12 13)
        ":"
        (text:sub 14 15)))

  (fn parse-local-until [standard text]
    (local (ok value) (pcall standard.parse-plain-date-time (compact-local-until->iso text)))
    (when (not ok)
      (error "invalid temporal recurrence UNTIL"))
    value)

  (fn parse-until [standard text]
    (if (compact-local-until? text)
        {:kind :plain-date-time :value (parse-local-until standard text)}
        (compact-utc-until? text)
        {:kind :instant}
        (error "invalid temporal recurrence UNTIL")))
  ```

  Keep these helpers private to the module; do not export them from `create`.

- [ ] **Step 7: Replace numeric occurrence limits with bounds.**

  Replace the existing `occurrence-limit` helper with these helpers:

  ```fennel
  (fn numeric-occurrence-limit [rule options]
    (when options.has-limit
      (validate-positive-integer options.limit "limit"))
    (if (and rule.count options.has-limit)
        (math.min rule.count options.limit)
        rule.count
        rule.count
        options.limit))

  (fn occurrence-bounds [standard rule options]
    (local limit (numeric-occurrence-limit rule options))
    (var until nil)
    (when rule.until
      (local parsed (parse-until standard rule.until))
      (if (= parsed.kind :plain-date-time)
          (set until parsed.value)
          (= parsed.kind :instant)
          (error "unsupported temporal recurrence UNTIL")))
    (when (and (= limit nil) (= until nil))
      (error "temporal recurrence expansion requires count, limit, or until"))
    {:limit limit :until until})
  ```

- [ ] **Step 8: Add bound helper predicates for expansion loops.**

  Add these helpers near the expansion helpers:

  ```fennel
  (fn limit-reached? [results bounds]
    (and bounds.limit (>= (# results) bounds.limit)))

  (fn within-until? [candidate until]
    (or (= until nil)
        (<= (candidate:compare until) 0)))
  ```

- [ ] **Step 9: Update calendar expansion to stop at UNTIL.**

  Change the signature from:

  ```fennel
  (fn expand-calendar [period rule dtstart limit]
  ```

  to:

  ```fennel
  (fn expand-calendar [period rule dtstart bounds]
  ```

  Replace the result loop with this shape:

  ```fennel
  (local results [])
  (var index 0)
  (var done false)
  (while (and (not done) (not (limit-reached? results bounds)))
    (local candidate
      (if (= index 0)
          dtstart
          (period.add-to-plain-date-time
            dtstart
            (calendar-step-period rule.freq (* index rule.interval)))))
    (if (not (within-until? candidate bounds.until))
        (set done true)
        (do
          (when (month-filter-allowed? rule candidate)
            (table.insert results candidate))
          (set index (+ index 1)))))
  results
  ```

  Keep the existing `BYDAY` rejection, zero-step validation call, and `assert-calendar-filters-satisfiable` call before this loop.

- [ ] **Step 10: Update daily expansion to stop at UNTIL.**

  Change the signature from:

  ```fennel
  (fn expand-daily [rule dtstart limit]
  ```

  to:

  ```fennel
  (fn expand-daily [rule dtstart bounds]
  ```

  In the `rule.by-day` branch, replace `while (< (# results) limit)` with:

  ```fennel
  (while (and (not (limit-reached? results bounds))
              (within-until? current bounds.until))
  ```

  In the non-`BYDAY` branch, replace `while (< (# results) limit)` with the same bounded condition:

  ```fennel
  (while (and (not (limit-reached? results bounds))
              (within-until? current bounds.until))
  ```

  Preserve the existing `assert-daily-by-day-satisfiable`, `assert-daily-filters-satisfiable`, day offset, interval, `BYDAY`, and `BYMONTH` logic inside the loops.

- [ ] **Step 11: Update weekly expansion to stop at UNTIL.**

  Change the signature from:

  ```fennel
  (fn expand-weekly [rule dtstart limit]
  ```

  to:

  ```fennel
  (fn expand-weekly [rule dtstart bounds]
  ```

  Replace the loop condition with:

  ```fennel
  (while (and (not (limit-reached? results bounds))
              (within-until? current bounds.until))
  ```

  Preserve the existing `week-offset`, interval, weekday, and `BYMONTH` checks inside the loop.

- [ ] **Step 12: Pass bounds through `occurrences`.**

  Change the private `occurrences` signature from:

  ```fennel
  (fn occurrences [period input-rule dtstart options]
  ```

  to:

  ```fennel
  (fn occurrences [period standard input-rule dtstart options]
  ```

  Replace:

  ```fennel
  (local limit (occurrence-limit rule occurrence-options))
  ```

  with:

  ```fennel
  (local bounds (occurrence-bounds standard rule occurrence-options))
  ```

  Then pass `bounds` to `expand-calendar`, `expand-daily`, and `expand-weekly`.

- [ ] **Step 13: Run the Fennel compile check.**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/recurrence.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  ```

  Expected result after implementation: `status` is `pass` and diagnostics are empty.

- [ ] **Step 14: Run constraints.**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets make constraints
  ```

  Expected result after implementation: `constraints: pass (0 diagnostics)`.

- [ ] **Step 15: Run the focused recurrence test.**

  Run:

  ```bash
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected result after implementation: all tests pass and the output includes the full count of executed Lua tests.

- [ ] **Step 16: Commit Task 1.**

  Commit exactly the implementation and focused test files:

  ```bash
  git add assets/lua/temporal.fnl assets/lua/temporal/recurrence.fnl assets/lua/tests/test-temporal-parsing-recurrence.fnl
  git commit -m "feat(temporal): bound recurrences by UNTIL"
  ```

  The implementer report must include RED test evidence, compile-check evidence, constraints evidence with a constraint-impact note, focused-test evidence, and a coverage rationale.

### Task 2: Documentation and Final Focused Validation

**Files:**
- Modify: `docs/dev/features/temporal-parsing-recurrence.md`

**Interfaces:**
- Consumes: Task 1 behavior for local compact `UNTIL` bounds, unsupported compact UTC expansion, invalid `UNTIL` expansion errors, and `UNTIL` as a finite bound.
- Produces: public developer documentation matching the implemented recurrence slice.

- [ ] **Step 1: Update the recurrence support paragraph.**

  In `docs/dev/features/temporal-parsing-recurrence.md`, replace the paragraph sentence that currently says `UNTIL` remains parse/serialize-only with this wording:

  ```markdown
  The bounded RRULE subset supports `FREQ` values `DAILY`, `WEEKLY`, `MONTHLY`, and `YEARLY`, plus `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY`, and `BYMONTH`. `BYMONTH` accepts integer months `1..12` and acts as an inclusion filter over the existing daily, weekly, monthly, or yearly candidate stream. Compact local `UNTIL=YYYYMMDDTHHMMSS` bounds occurrence expansion inclusively and can satisfy the finite-bound requirement without `COUNT` or `options.limit`; `COUNT`, `options.limit`, and `UNTIL` stop expansion at the earliest reached bound. Compact UTC `UNTIL=YYYYMMDDTHHMMSSZ` remains parse/serialize-compatible but is unsupported for expansion until timezone-aware recurrence exists. Monthly and yearly rules remain anchor-based through `Temporal.period`; `YEARLY+BYMONTH` does not generate additional months in this slice.
  ```

- [ ] **Step 2: Update the deferred full-RFC5545 bullet.**

  Replace the existing `Full RFC5545` deferred bullet with this wording:

  ```markdown
  - **Full RFC5545:** Deferred. The current RRULE subset is intentionally small; timezone-aware recurrence, UTC/instant `UNTIL` expansion, date-only `UNTIL`, fractional `UNTIL`, `BYMONTHDAY`, `BYSETPOS`, `WKST`, `RDATE`, `EXDATE`, and full RFC5545 candidate-set expansion require separate semantics and compatibility tests.
  ```

- [ ] **Step 3: Run focused documentation checks.**

  Run:

  ```bash
  rtk rg "UNTIL|timezone-aware recurrence|UTC/instant UNTIL|parse/serialize-only" docs/dev/features/temporal-parsing-recurrence.md docs/specs/2026-09-27-temporal-rrule-until-bound-design.md docs/plans/2026-09-27-temporal-rrule-until-bound.md
  ```

  Expected result: the feature doc describes local compact `UNTIL` as an inclusive expansion bound, describes compact UTC expansion as deferred, and no longer says the current `UNTIL` behavior is parse/serialize-only.

- [ ] **Step 4: Run the final Fennel compile check.**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/recurrence.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  ```

  Expected result: `status` is `pass` and diagnostics are empty.

- [ ] **Step 5: Run final constraints.**

  Run:

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

- [ ] **Step 7: Run the full local suite for public temporal behavior.**

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected result: all registered tests pass. This broader local validation is justified because `UNTIL` changes public recurrence expansion behavior.

- [ ] **Step 8: Commit Task 2.**

  Commit the documentation file:

  ```bash
  git add docs/dev/features/temporal-parsing-recurrence.md
  git commit -m "docs(temporal): document RRULE UNTIL bounds"
  ```

  The implementer report must include documentation check evidence, compile-check evidence, constraints evidence with a constraint-impact note, focused-test evidence, full-suite evidence, and a coverage rationale.
