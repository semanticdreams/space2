# Temporal Interval Period Endpoint Forms Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `start/period` and `period/end` parsing to `Temporal.interval.parse` for plain date-time intervals only.

**Architecture:** Keep interval records concrete by resolving period endpoint forms inside the Fennel interval parser before calling `Temporal.interval.from`. Use existing `Temporal.period` parse and plain-date-time add/subtract helpers; keep instant intervals, repeating intervals, public helpers, and native C++ unchanged.

**Tech Stack:** Space Fennel modules, existing `Temporal.period` API, native plain-date-time calendar arithmetic through existing bindings, project-native Fennel validation through `tools.fennel-check`, constraints, and focused Fennel tests.

## Global Constraints

- Add `start/period` support to `Temporal.interval.parse` with `{:type :plain-date-time}`.
- Add `period/end` support to `Temporal.interval.parse` with `{:type :plain-date-time}`.
- Reuse existing `Temporal.period.parse`, `Temporal.period.add-to-plain-date-time`, and `Temporal.period.subtract-from-plain-date-time`.
- Preserve canonical interval records with concrete `:start` and `:end` endpoints.
- Preserve half-open range validation: the computed `:start` must be strictly before the computed `:end`.
- Keep `Temporal.interval.format` canonical as `start/end` after parsing a period endpoint form.
- Ensure repeating intervals continue to reject period endpoint forms.
- Supporting period endpoint forms for `{:type :instant}` intervals is out of scope.
- Supporting zoned interval period endpoint forms is out of scope.
- Supporting `Temporal.interval.from` with period records as endpoints is out of scope.
- Supporting `Temporal.repeating-interval.parse` with period endpoint forms is out of scope.
- Adding calendar-period-driven repeating expansion is out of scope.
- Adding time-based `PT...` duration endpoint text is out of scope.
- Adding a public helper for endpoint-form parsing is out of scope.
- Adding native C++ interval or period APIs is out of scope.
- Implementing full ISO interval grammar beyond the two plain-date-time forms is out of scope.

---

## File Structure

- `assets/lua/temporal.fnl`
  - Owns construction of the public `Temporal` facade.
  - Instantiate `Temporal.period` once and pass it to `Temporal.interval`.
- `assets/lua/temporal/interval.fnl`
  - Owns interval construction, parsing, formatting, duration, containment, and exact shifting.
  - Add private endpoint-form detection and endpoint resolution.
- `assets/lua/temporal/repeating-interval.fnl`
  - Owns repeating interval parsing and exact-duration occurrence expansion.
  - Add a private guard that rejects period endpoint forms before delegating to `Temporal.interval.parse`.
- `assets/lua/tests/test-temporal-intervals.fnl`
  - Owns focused interval and repeating interval tests.
  - Add regression coverage for supported period endpoint forms and unsupported boundaries.
- `docs/dev/features/temporal-intervals.md`
  - Canonical interval documentation.
  - Document supported and unsupported period endpoint forms.
- `docs/dev/features/temporal-calendar-periods.md`
  - Canonical period documentation.
  - Cross-reference interval parser period endpoint support.
- `docs/dev/features/temporal-parsing-recurrence.md`
  - Canonical parsing/recurrence documentation.
  - Clarify that recurrence/repeating behavior does not gain period endpoint semantics.

---

### Task 1: Plain-Date-Time Period Endpoint Parsing

**Files:**
- Modify: `assets/lua/temporal.fnl`
- Modify: `assets/lua/temporal/interval.fnl`
- Modify: `assets/lua/tests/test-temporal-intervals.fnl`

**Interfaces:**
- Consumes:
  - `Temporal.period.parse(text:string) -> period-record`
  - `Temporal.period.add-to-plain-date-time(plain, period) -> PlainDateTime`
  - `Temporal.period.subtract-from-plain-date-time(plain, period) -> PlainDateTime`
  - Existing `Temporal.interval.from(options:table) -> interval-record`
- Produces:
  - Unchanged public API: `Temporal.interval.parse(text:string, options:table) -> interval-record`
  - `Temporal.interval.parse` accepts `start/period` and `period/end` only when `options.type` is `:plain-date-time`.
  - No new exported function.

- [ ] **Step 1: Add failing tests for supported and unsupported period endpoint forms.**

  In `assets/lua/tests/test-temporal-intervals.fnl`, add this function after `plain-interval-parse-shift`:

  ```fennel
  (fn plain-interval-period-endpoint-forms []
    (local by-start
      (Temporal.interval.parse "2026-01-31T10:00:00/P1M" {:type :plain-date-time}))
    (assert (= (Temporal.interval.format by-start)
               "2026-01-31T10:00:00/2026-02-28T10:00:00"))

    (local by-end
      (Temporal.interval.parse "P2W/2026-02-15T09:30:00" {:type :plain-date-time}))
    (assert (= (Temporal.interval.format by-end)
               "2026-02-01T09:30:00/2026-02-15T09:30:00"))

    (assert-error #(Temporal.interval.parse "2026-02-01T00:00:00/-P1D" {:type :plain-date-time})
                  "negative start/period should throw when it reverses range")
    (assert-error #(Temporal.interval.parse "-P1D/2026-02-01T00:00:00" {:type :plain-date-time})
                  "negative period/end should throw when it reverses range")
    (assert-error #(Temporal.interval.parse "2026-02-01T00:00:00/P0D" {:type :plain-date-time})
                  "zero period endpoint should throw")
    (assert-error #(Temporal.interval.parse "2026-02-01T00:00:00Z/P1D" {:type :instant})
                  "instant start/period should throw")
    (assert-error #(Temporal.interval.parse "P1D/2026-02-01T00:00:00Z" {:type :instant})
                  "instant period/end should throw")
    (assert-error #(Temporal.interval.from {:type :plain-date-time
                                            :start (Temporal.period.parse "P1D")
                                            :end (Temporal.standard.parse-plain-date-time "2026-02-01T00:00:00")})
                  "interval.from should reject period start endpoints"))
  ```

  Register it near the existing plain interval tests:

  ```fennel
  (table.insert tests {:name "plain interval period endpoint forms" :fn plain-interval-period-endpoint-forms})
  ```

- [ ] **Step 2: Run the focused test and verify the failure.**

  If `./build/space` is missing or stale, first run:

  ```bash
  make build
  ```

  Then run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-intervals:main
  ```

  Expected before implementation: failure for `2026-01-31T10:00:00/P1M`, currently from unsupported duration endpoint forms or plain-date-time parse failure.

- [ ] **Step 3: Instantiate `Temporal.period` once before `Temporal.interval`.**

  In `assets/lua/temporal.fnl`, replace the interval setup block with:

  ```fennel
  (local standard (create-standard base))
  (local period (create-period base))
  (local interval (create-interval {:standard standard :period period}))
  (local temporal-with-intervals {:standard standard :interval interval})
  ```

  In the returned public table, replace `:period (create-period base)` with:

  ```fennel
  :period period
  ```

- [ ] **Step 4: Remove the old duration-endpoint rejection from interval splitting.**

  In `assets/lua/temporal/interval.fnl`, keep `split-interval-text` responsible only for string type, repeating prefix rejection, separator count, and non-empty endpoints. Remove this block:

  ```fennel
  (when (or (start-text:match "^P")
            (end-text:match "^P"))
    (error "temporal interval duration endpoint forms are not supported"))
  ```

- [ ] **Step 5: Add private period endpoint detection.**

  In `assets/lua/temporal/interval.fnl`, add this helper after `split-interval-text`:

  ```fennel
  (fn period-endpoint-text? [text]
    (or (text:match "^P")
        (text:match "^%-P")))
  ```

- [ ] **Step 6: Add private endpoint resolution inside `create`.**

  Inside the `create` function, after `parse-endpoint`, add:

  ```fennel
  (fn resolve-parse-endpoints [endpoint-type start-text end-text]
    (local start-period? (period-endpoint-text? start-text))
    (local end-period? (period-endpoint-text? end-text))
    (when (and start-period? end-period?)
      (error "temporal interval requires one date-time endpoint when using a period endpoint"))
    (when (and (or start-period? end-period?)
               (not (= endpoint-type :plain-date-time)))
      (error "temporal interval period endpoint forms require :plain-date-time"))
    (if end-period?
        (do
          (local start (parse-endpoint endpoint-type start-text))
          (local period (Temporal.period.parse end-text))
          (values start (Temporal.period.add-to-plain-date-time start period)))
        start-period?
        (do
          (local end (parse-endpoint endpoint-type end-text))
          (local period (Temporal.period.parse start-text))
          (values (Temporal.period.subtract-from-plain-date-time end period) end))
        (values (parse-endpoint endpoint-type start-text)
                (parse-endpoint endpoint-type end-text))))
  ```

  Keep this helper private.

- [ ] **Step 7: Route `parse` through endpoint resolution.**

  Replace the body of `parse` after `validate-parse-options` with:

  ```fennel
  (local (start-text end-text) (split-interval-text text))
  (local (start end) (resolve-parse-endpoints options.type start-text end-text))
  (from {:type options.type
         :start start
         :end end})
  ```

- [ ] **Step 8: Run focused validation for Task 1.**

  Compile check:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/interval.fnl --file assets/lua/tests/test-temporal-intervals.fnl
  ```

  Constraints:

  ```bash
  make constraints
  ```

  Focused tests:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-intervals:main
  ```

- [ ] **Step 9: Commit Task 1.**

  ```bash
  git add assets/lua/temporal.fnl assets/lua/temporal/interval.fnl assets/lua/tests/test-temporal-intervals.fnl
  git commit -m "feat(temporal): parse plain interval period endpoints"
  ```

  The implementer report must include failing-test evidence, compile-check evidence, constraints evidence with constraint-impact note, focused-test evidence, and a short validation coverage rationale.

---

### Task 2: Repeating Interval Period Endpoint Guard

**Files:**
- Modify: `assets/lua/temporal/repeating-interval.fnl`
- Modify: `assets/lua/tests/test-temporal-intervals.fnl`

**Interfaces:**
- Consumes:
  - Existing `Temporal.interval.parse(text:string, options:table) -> interval-record`
  - Existing `Temporal.repeating-interval.parse(text:string, options:table) -> repeating-interval-record`
- Produces:
  - `Temporal.repeating-interval.parse` rejects period endpoint forms before delegating to interval parsing.
  - Existing exact-duration occurrence expansion remains unchanged.

- [ ] **Step 1: Add regression tests for repeating interval rejection.**

  In `assets/lua/tests/test-temporal-intervals.fnl`, add these assertions to `repeating-interval-rejections`:

  ```fennel
  (assert-error #(Temporal.repeating-interval.parse
                   "R3/2026-01-31T10:00:00/P1M"
                   {:type :plain-date-time})
                "repeating start/period should throw")
  (assert-error #(Temporal.repeating-interval.parse
                   "R3/P1M/2026-02-28T10:00:00"
                   {:type :plain-date-time})
                "repeating period/end should throw")
  ```

- [ ] **Step 2: Run the focused test and verify the failure.**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-intervals:main
  ```

  Expected before implementation: the new repeating rejection assertions fail because delegation accepts the plain-date-time period endpoint forms from Task 1.

- [ ] **Step 3: Add private helpers to detect period endpoint forms.**

  In `assets/lua/temporal/repeating-interval.fnl`, add these helpers near the other private parsing helpers:

  ```fennel
  (fn period-endpoint-text? [text]
    (or (text:match "^P")
        (text:match "^%-P")))

  (fn interval-text-has-period-endpoint? [text]
    (local (start-text end-text) (text:match "^([^/]*)/([^/]*)$"))
    (and start-text
         end-text
         (or (period-endpoint-text? start-text)
             (period-endpoint-text? end-text))))
  ```

- [ ] **Step 4: Reject period endpoint forms before interval delegation.**

  In `parse`, after `interval-text` is computed and before calling `Temporal.interval.parse`, add:

  ```fennel
  (when (interval-text-has-period-endpoint? interval-text)
    (error "temporal repeating interval period endpoint forms are not supported"))
  ```

- [ ] **Step 5: Run focused validation for Task 2.**

  Compile check:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/repeating-interval.fnl --file assets/lua/tests/test-temporal-intervals.fnl
  ```

  Constraints:

  ```bash
  make constraints
  ```

  Focused tests:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-intervals:main
  ```

- [ ] **Step 6: Commit Task 2.**

  ```bash
  git add assets/lua/temporal/repeating-interval.fnl assets/lua/tests/test-temporal-intervals.fnl
  git commit -m "fix(temporal): reject repeating interval period endpoints"
  ```

  The implementer report must include failing-test evidence, compile-check evidence, constraints evidence with constraint-impact note, focused-test evidence, and a short validation coverage rationale.

---

### Task 3: Developer Documentation for Interval Period Endpoints

**Files:**
- Modify: `docs/dev/features/temporal-intervals.md`
- Modify: `docs/dev/features/temporal-calendar-periods.md`
- Modify: `docs/dev/features/temporal-parsing-recurrence.md`

**Interfaces:**
- Consumes:
  - Final Task 1 behavior for `Temporal.interval.parse` plain date-time period endpoints.
  - Final Task 2 behavior rejecting repeating interval period endpoints.
- Produces:
  - Canonical documentation that matches supported and unsupported behavior.

- [ ] **Step 1: Update `temporal-intervals.md` support summary.**

  Replace blanket wording that says ISO interval duration endpoint forms are deferred with wording equivalent to:

  ```markdown
  Calendar period endpoint forms are supported only for `Temporal.interval.parse` with `{:type :plain-date-time}`. The supported forms are `start/period` and `period/end`; instant intervals and repeating intervals still reject period endpoint forms.
  ```

- [ ] **Step 2: Update the `Temporal.interval.parse` API documentation.**

  Add or adjust the API bullet to state:

  ```markdown
  - `Temporal.interval.parse text {:type type}` accepts `start/end` text for `:instant` and `:plain-date-time`. For `{:type :plain-date-time}` it also accepts `start/period` and `period/end`, where `period` is date-only `Temporal.period` text. `start/period` computes the end by adding the period to the start; `period/end` computes the start by subtracting the period from the end. The final interval must still be half-open with `start < end`.
  ```

- [ ] **Step 3: Add examples for period endpoints.**

  Add examples showing:

  ```fennel
  (Temporal.interval.format
    (Temporal.interval.parse "2026-01-31T10:00:00/P1M"
                             {:type :plain-date-time}))
  ; => "2026-01-31T10:00:00/2026-02-28T10:00:00"

  (Temporal.interval.format
    (Temporal.interval.parse "P2W/2026-02-15T09:30:00"
                             {:type :plain-date-time}))
  ; => "2026-02-01T09:30:00/2026-02-15T09:30:00"
  ```

- [ ] **Step 4: Update unsupported/deferred wording.**

  In `temporal-intervals.md`, state that unsupported forms include instant period endpoints, repeating interval period endpoints, `Temporal.interval.from` period endpoints, time-based `PT...` period text, zoned intervals, DST-aware expansion, and full ISO interval grammar beyond the two supported plain-date-time forms.

- [ ] **Step 5: Update related docs to remove contradictions.**

  In `temporal-calendar-periods.md` and `temporal-parsing-recurrence.md`, replace blanket statements that `start/duration` and `duration/end` remain deferred with precise wording: date-only `start/period` and `period/end` are supported only by `Temporal.interval.parse` for plain date-times; repeating, instant, zoned, time-based, and full ISO forms remain deferred.

- [ ] **Step 6: Run docs-focused validation.**

  ```bash
  rg "start/period|period/end|Temporal.period|repeating interval period endpoint|instant period endpoint|Temporal.interval.parse" docs/dev/features/temporal-intervals.md docs/dev/features/temporal-calendar-periods.md docs/dev/features/temporal-parsing-recurrence.md
  ```

- [ ] **Step 7: Commit Task 3.**

  ```bash
  git add docs/dev/features/temporal-intervals.md docs/dev/features/temporal-calendar-periods.md docs/dev/features/temporal-parsing-recurrence.md
  git commit -m "docs(temporal): document interval period endpoints"
  ```

  The implementer report must include docs/search evidence and a short validation coverage rationale. Constraint-impact note: not applicable.

---

## Final Review and Finishing Validation

After all tasks pass reviewer gates, request a whole-branch reviewer pass against:

- `docs/specs/2026-09-27-temporal-interval-period-endpoints-design.md`
- `docs/plans/2026-09-27-temporal-interval-period-endpoints.md`
- `assets/lua/temporal.fnl`
- `assets/lua/temporal/interval.fnl`
- `assets/lua/temporal/repeating-interval.fnl`
- `assets/lua/tests/test-temporal-intervals.fnl`
- `docs/dev/features/temporal-intervals.md`
- `docs/dev/features/temporal-calendar-periods.md`
- `docs/dev/features/temporal-parsing-recurrence.md`

Then invoke finishing-a-development-branch. Required final validation should include at least:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/interval.fnl --file assets/lua/temporal/repeating-interval.fnl --file assets/lua/tests/test-temporal-intervals.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-intervals:main
rg "start/period|period/end|Temporal.period|repeating interval period endpoint|instant period endpoint|Temporal.interval.parse" docs/dev/features/temporal-intervals.md docs/dev/features/temporal-calendar-periods.md docs/dev/features/temporal-parsing-recurrence.md
```

Broaden to `tests.fast:main` or full `make test` during finishing if reviewer requests it, if final integration policy requires it, or if focused validation exposes cross-surface risk.
