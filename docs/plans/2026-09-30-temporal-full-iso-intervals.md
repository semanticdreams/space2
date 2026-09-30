# Temporal Full ISO Intervals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote `Temporal.interval` and `Temporal.repeating-interval` to the selected Track 6 ISO interval surface with explicit zoned endpoints, exact `PT...` endpoints, calendar periods, DST policy, and repeat-step metadata.

**Architecture:** Extend the existing Fennel interval facades and keep the native C++ temporal core independent of interval grammar. Add a private interval grammar helper for bracket-aware splitting, endpoint classification, and exact-duration parsing, then wire `Temporal.interval` and `Temporal.repeating-interval` through that helper. Preserve canonical concrete interval records while using private parse step metadata for repeating expansion semantics.

**Tech Stack:** Space Fennel modules in `assets/lua/temporal/**`, native temporal userdata already exposed through `temporal-core`, existing Fennel test runner in `assets/lua/tests/test-temporal-intervals.fnl`, docs in `docs/dev/features/**`.

## Global Constraints

- no host-local timezone defaults;
- exact `Duration` remains nanoseconds-only;
- calendar periods remain separate from exact durations;
- native temporal core remains independent from interval grammar, recurrence, ICS, localization, business calendars, providers, and scheduler policy;
- canonical option keys only;
- unsupported grammar and invalid temporal data fail loudly.
- Preserve existing `Temporal.interval` and `Temporal.repeating-interval` API names and compatibility for current instant/plain start-end callers.
- Do not implement exhaustive ISO 8601-1/-2 conformance beyond this selected production grammar.
- Do not implement open intervals, anchorless interval expansion, date-only or all-day intervals, week-date or ordinal-date endpoints, offset-only zoned intervals, non-Gregorian calendars, business-day intervals, natural-language intervals, ICS/VEVENT/VTIMEZONE parsing, interval algebra, localization, or scheduler behavior.
- Do not treat `P1D` as exact 24 hours.
- Do not add host-local timezone fallback, implicit UTC fallback, or option-key aliases.
- Do not move interval grammar or policy into the native C++ temporal core.

---

### Task 1: Shared Interval Grammar, Exact `PT...` Endpoints, and Concrete Zoned Start/End

**Files:**
- Create: `assets/lua/temporal/interval/grammar.fnl`
- Modify: `assets/lua/temporal.fnl`
- Modify: `assets/lua/temporal/interval.fnl`
- Test: `assets/lua/tests/test-temporal-intervals.fnl`

**Interfaces:**
- Consumes: existing `Temporal.standard.parse-instant`, `parse-plain-date-time`, `parse-zoned-date-time`, formatters, `Temporal.duration.from`, `Temporal.duration.from-nanoseconds`.
- Produces:
  - `grammar.split-interval-text(text:string) -> start-text:string, end-text:string`
  - `grammar.endpoint-kind(text:string) -> :concrete|:calendar-period|:exact-duration`
  - `grammar.parse-exact-duration(duration-api:table, text:string) -> TemporalDuration`
  - `Temporal.interval._parse-with-step(text:string, options:table) -> interval:table, step-kind:keyword, step:any`
  - `Temporal.interval` support for `:zoned-date-time` concrete `start/end` and `start/PT...`, `PT.../end` for `:instant`, `:plain-date-time`, and `:zoned-date-time`.

- [ ] **Step 1: Write failing tests for bracket-aware splitting, concrete zoned intervals, and exact-duration endpoints.**

Add representative tests to `assets/lua/tests/test-temporal-intervals.fnl` and register them in the `tests` table:

```fennel
(fn zoned-interval-concrete-start-end []
  (local text "2026-09-25T09:00:00-04:00[America/New_York]/2026-09-25T10:00:00-04:00[America/New_York]")
  (local interval (Temporal.interval.parse text {:type :zoned-date-time}))
  (assert (= interval.type :zoned-date-time))
  (assert (= (Temporal.interval.format interval) text))
  (assert (= ((Temporal.interval.duration interval):compare (Temporal.duration.from {:seconds 3600})) 0))
  (assert (Temporal.interval.contains interval
                                      (Temporal.standard.parse-zoned-date-time
                                        "2026-09-25T09:30:00-04:00[America/New_York]")))
  (assert-error #(Temporal.interval.parse
                   "2026-09-25T09:00:00-05:00[America/New_York]/2026-09-25T10:00:00-04:00[America/New_York]"
                   {:type :zoned-date-time})
                "zoned offset mismatch should throw")
  (assert-error #(Temporal.interval.parse
                   "2026-09-25T09:00:00-04:00[America/New_York]/2026-09-25T10:00:00-05:00[America/Chicago]"
                   {:type :zoned-date-time})
                "zoned endpoints with different zones should throw"))

(fn interval-exact-duration-endpoints []
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse "2026-09-25T12:00:00Z/PT1H" {:type :instant}))
             "2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"))
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse "PT30M/2026-09-25T13:00:00Z" {:type :instant}))
             "2026-09-25T12:30:00Z/2026-09-25T13:00:00Z"))
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse "2026-09-25T12:00:00/PT0.5S" {:type :plain-date-time}))
             "2026-09-25T12:00:00/2026-09-25T12:00:00.5"))
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse
                 "2026-03-08T01:30:00-05:00[America/New_York]/PT1H"
                 {:type :zoned-date-time}))
             "2026-03-08T01:30:00-05:00[America/New_York]/2026-03-08T03:30:00-04:00[America/New_York]"))
  (assert-error #(Temporal.interval.parse "2026-09-25T12:00:00Z/P1D" {:type :instant})
                "calendar period endpoint for instant should throw")
  (assert-error #(Temporal.interval.parse "2026-09-25T12:00:00Z/PT" {:type :instant})
                "empty exact duration should throw")
  (assert-error #(Temporal.interval.parse "2026-09-25T12:00:00Z/PT0.5H" {:type :instant})
                "fractional hours should throw")
  (assert-error #(Temporal.interval.parse "P1D/PT1H" {:type :instant})
                "two derived endpoints should throw"))
```

- [ ] **Step 2: Run focused failing test.**

If `./build/space` is missing or stale, first run `make build` with timeout `14400000`.

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-intervals:main
```

Expected: FAIL on unsupported `:zoned-date-time`, naive slash splitting, and/or unsupported `PT...` endpoint forms.

- [ ] **Step 3: Implement the grammar helper and exact-duration parsing.**

Create `assets/lua/temporal/interval/grammar.fnl` with bracket-aware top-level `/` splitting that rejects unbalanced brackets, empty endpoints, missing separators, and multiple top-level separators. Implement endpoint classification so `P...`/`-P...` without `T` is `:calendar-period`, `PT...`/`-PT...` is `:exact-duration`, and everything else is `:concrete`. Implement `parse-exact-duration` for `PT1H`, `PT30M`, `PT45S`, `PT1H30M`, `PT0.5S`, `PT1.123456789S`, `-PT1H`, and `PT0S`; reject `PT`, fractional hours/minutes, `P1DT2H`, calendar fields inside `PT...`, and more than nine fractional second digits.

- [ ] **Step 4: Wire `Temporal.interval` to the helper and add zoned endpoint operations.**

Modify `assets/lua/temporal.fnl` so `create-interval` receives `{:standard standard :period period :duration base.duration :plain-date-time base.plain-date-time :zoned-date-time base.zoned-date-time}`. In `assets/lua/temporal/interval.fnl`, allow endpoint type `:zoned-date-time`; parse/format via `Temporal.standard.parse-zoned-date-time` and `format-zoned-date-time`; validate zoned endpoints by requiring matching `:zone-id`; compare/contains/duration zoned intervals through endpoint `.instant`; shift exact zoned intervals by adding to instants and reprojecting through `Temporal.zoned-date-time.from-instant`.

- [ ] **Step 5: Run compile, constraints, and focused tests.**

If a Fennel parse error points at a delimiter or innocent binding, inspect the nearest enclosing form and reduce nesting by extracting helper functions before retrying.

```bash
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-intervals:main
```

Expected: PASS.

- [ ] **Step 6: Commit Task 1.**

```bash
git add assets/lua/temporal.fnl assets/lua/temporal/interval.fnl assets/lua/temporal/interval/grammar.fnl assets/lua/tests/test-temporal-intervals.fnl
git commit -m "feat(lua): add full interval grammar and exact endpoints"
```

---

### Task 2: Zoned Calendar Period Endpoints and DST Disambiguation

**Files:**
- Modify: `assets/lua/temporal/interval.fnl`
- Modify: `assets/lua/tests/test-temporal-intervals.fnl`

**Interfaces:**
- Consumes: `grammar.endpoint-kind`, `Temporal.period.parse`, `Temporal.period.add-to-plain-date-time`, `Temporal.period.subtract-from-plain-date-time`, `Temporal.zoned-date-time.from-plain`, `Temporal.plain-date-time.from-fields`.
- Produces:
  - `Temporal.interval.parse(text, {:type :zoned-date-time :disambiguation :reject|:earliest|:latest})`
  - `_parse-with-step` returns `step-kind :calendar-period` and `step period` for `start/P...` and `P.../end`.
  - `:disambiguation` is accepted only when resolving zoned calendar-period derived endpoints; default is `:reject`.

- [ ] **Step 1: Write failing tests for zoned calendar periods and DST policy.**

Add and register these representative tests:

```fennel
(fn zoned-calendar-period-endpoints []
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse
                 "2026-01-31T10:00:00-05:00[America/New_York]/P1M"
                 {:type :zoned-date-time}))
             "2026-01-31T10:00:00-05:00[America/New_York]/2026-02-28T10:00:00-05:00[America/New_York]"))
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse
                 "P2W/2026-02-15T09:30:00-05:00[America/New_York]"
                 {:type :zoned-date-time}))
             "2026-02-01T09:30:00-05:00[America/New_York]/2026-02-15T09:30:00-05:00[America/New_York]"))
  (assert-error #(Temporal.interval.parse
                   "2026-03-07T02:30:00-05:00[America/New_York]/P1D"
                   {:type :zoned-date-time})
                "default reject should throw for DST gap")
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse
                 "2026-03-07T02:30:00-05:00[America/New_York]/P1D"
                 {:type :zoned-date-time :disambiguation :earliest}))
             "2026-03-07T02:30:00-05:00[America/New_York]/2026-03-08T03:00:00-04:00[America/New_York]"))
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse
                 "2026-10-31T01:30:00-04:00[America/New_York]/P1D"
                 {:type :zoned-date-time :disambiguation :earliest}))
             "2026-10-31T01:30:00-04:00[America/New_York]/2026-11-01T01:30:00-04:00[America/New_York]"))
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse
                 "2026-10-31T01:30:00-04:00[America/New_York]/P1D"
                 {:type :zoned-date-time :disambiguation :latest}))
             "2026-10-31T01:30:00-04:00[America/New_York]/2026-11-01T01:30:00-05:00[America/New_York]")))

(fn interval-disambiguation-option-boundaries []
  (assert-error #(Temporal.interval.parse
                   "2026-09-25T12:00:00/2026-09-25T13:00:00"
                   {:type :plain-date-time :disambiguation :earliest})
                "plain intervals should reject disambiguation")
  (assert-error #(Temporal.interval.parse
                   "2026-09-25T09:00:00-04:00[America/New_York]/PT1H"
                   {:type :zoned-date-time :disambiguation :earliest})
                "exact-duration zoned intervals should reject disambiguation")
  (assert-error #(Temporal.interval.parse
                   "2026-09-25T09:00:00-04:00[America/New_York]/P1D"
                   {:type :zoned-date-time :disambiguation :compatible})
                "unknown disambiguation value should throw"))
```

- [ ] **Step 2: Run focused failing test.**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-intervals:main
```

Expected: FAIL on zoned calendar-period endpoint forms and disambiguation validation.

- [ ] **Step 3: Implement zoned calendar-period derivation.**

In `assets/lua/temporal/interval.fnl`, derive zoned `start/P...` and `P.../end` by extracting endpoint local fields, creating a `PlainDateTime` with `Temporal.plain-date-time.from-fields`, applying `Temporal.period.add-to-plain-date-time` or `subtract-from-plain-date-time`, and resolving with `Temporal.zoned-date-time.from-plain derived-local same-zone {:disambiguation value}`. Validate matching zone, zero-length, and reversed ranges by instant ordering.

- [ ] **Step 4: Enforce disambiguation option boundaries.**

Allow `:disambiguation` in parse options only for `:zoned-date-time` calendar-period derived endpoint forms. Default to `:reject`; accept only `:reject`, `:earliest`, and `:latest`; throw when provided for plain, instant, concrete zoned, or exact-duration zoned interval parsing.

- [ ] **Step 5: Run compile, constraints, and focused tests.**

```bash
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-intervals:main
```

Expected: PASS.

- [ ] **Step 6: Commit Task 2.**

```bash
git add assets/lua/temporal/interval.fnl assets/lua/tests/test-temporal-intervals.fnl
git commit -m "feat(lua): add zoned calendar interval disambiguation"
```

---

### Task 3: Repeating Interval Step Metadata and Exact/Calendar Expansion

**Files:**
- Modify: `assets/lua/temporal/repeating-interval.fnl`
- Modify: `assets/lua/tests/test-temporal-intervals.fnl`

**Interfaces:**
- Consumes: `Temporal.interval._parse-with-step(text, options) -> interval, step-kind, step`, `Temporal.interval.duration`, exact interval shifting, period shifting helpers from interval implementation.
- Produces:
  - `Temporal.repeating-interval.from {:interval interval :count count :step-kind :exact-duration|:calendar-period :step step}`
  - Existing records without `:step-kind` and `:step` remain valid and use `:exact-duration` with `Temporal.interval.duration`.
  - `Temporal.repeating-interval.occurrences(repeating, {:limit n :disambiguation :reject|:earliest|:latest}) -> [interval...]`.

- [ ] **Step 1: Write failing tests for exact and calendar repeat metadata.**

Add and register these representative tests:

```fennel
(fn repeating-interval-exact-duration-step-metadata []
  (local repeating (Temporal.repeating-interval.parse
                     "R3/2026-03-08T01:30:00-05:00[America/New_York]/PT1H"
                     {:type :zoned-date-time}))
  (assert (= repeating.step-kind :exact-duration))
  (assert (= ((repeating.step):compare (Temporal.duration.from {:seconds 3600})) 0))
  (local occ (Temporal.repeating-interval.occurrences repeating {}))
  (assert (= (Temporal.interval.format (. occ 1))
             "2026-03-08T01:30:00-05:00[America/New_York]/2026-03-08T03:30:00-04:00[America/New_York]"))
  (assert (= (Temporal.interval.format (. occ 2))
             "2026-03-08T03:30:00-04:00[America/New_York]/2026-03-08T04:30:00-04:00[America/New_York]"))
  (assert (= (Temporal.interval.format (. occ 3))
             "2026-03-08T04:30:00-04:00[America/New_York]/2026-03-08T05:30:00-04:00[America/New_York]")))

(fn repeating-interval-calendar-period-step-metadata []
  (local repeating (Temporal.repeating-interval.parse
                     "R3/2026-10-31T01:30:00-04:00[America/New_York]/P1D"
                     {:type :zoned-date-time :disambiguation :latest}))
  (assert (= repeating.step-kind :calendar-period))
  (assert (= (Temporal.period.format repeating.step) "P1D"))
  (local occ (Temporal.repeating-interval.occurrences repeating {:disambiguation :latest}))
  (assert (= (Temporal.interval.format (. occ 1))
             "2026-10-31T01:30:00-04:00[America/New_York]/2026-11-01T01:30:00-05:00[America/New_York]"))
  (assert (= (Temporal.interval.format (. occ 2))
             "2026-11-01T01:30:00-05:00[America/New_York]/2026-11-02T01:30:00-05:00[America/New_York]"))
  (assert (= (Temporal.interval.format (. occ 3))
             "2026-11-02T01:30:00-05:00[America/New_York]/2026-11-03T01:30:00-05:00[America/New_York]")))

(fn repeating-interval-from-step-metadata []
  (local first (Temporal.interval.parse "2026-01-31T10:00:00/P1M" {:type :plain-date-time}))
  (local repeating (Temporal.repeating-interval.from
                     {:interval first :count 2 :step-kind :calendar-period :step (Temporal.period.parse "P1M")}))
  (local occ (Temporal.repeating-interval.occurrences repeating {}))
  (assert (= (Temporal.interval.format (. occ 2))
             "2026-02-28T10:00:00/2026-03-28T10:00:00"))
  (assert-error #(Temporal.repeating-interval.from {:interval first :count 2 :step-kind :calendar-period})
                "missing calendar step should throw")
  (assert-error #(Temporal.repeating-interval.occurrences repeating {:disambiguation :compatible})
                "invalid occurrence disambiguation should throw"))
```

- [ ] **Step 2: Run focused failing test.**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-intervals:main
```

Expected: FAIL because repeating parsing currently rejects period endpoint forms and does not store `:step-kind`/`:step`.

- [ ] **Step 3: Implement repeating record validation and parsing.**

Update `assets/lua/temporal/repeating-interval.fnl` so `from` accepts only `:interval`, `:count`, `:step-kind`, and `:step`. Validate `:step-kind` is absent, `:exact-duration`, or `:calendar-period`; require `:step` when `:step-kind` is provided; reject unknown keys. Change `parse` to call `Temporal.interval._parse-with-step` and persist returned `step-kind` and `step`.

- [ ] **Step 4: Implement exact and calendar occurrence expansion.**

Keep legacy records without metadata working by deriving `:exact-duration` and `Temporal.interval.duration`. For `:exact-duration`, shift intervals by exact duration using existing interval exact shifting. For `:calendar-period`, support only `:plain-date-time` and `:zoned-date-time`; shift both endpoints by local calendar period, resolving zoned endpoints with occurrence `:disambiguation` default `:reject`.

- [ ] **Step 5: Run compile, constraints, and focused tests.**

```bash
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-intervals:main
```

Expected: PASS.

- [ ] **Step 6: Commit Task 3.**

```bash
git add assets/lua/temporal/repeating-interval.fnl assets/lua/tests/test-temporal-intervals.fnl
git commit -m "feat(lua): preserve repeating interval step semantics"
```

---

### Task 4: Documentation, Acceptance Evidence, and Final Validation

**Files:**
- Modify: `docs/dev/features/temporal-intervals.md`
- Modify: `docs/dev/features/temporal-parsing-recurrence.md`
- Modify: `docs/dev/features/temporal-complete-acceptance.md`
- Modify: `docs/dev/features/temporal-complete-library.md`
- Test: `assets/lua/tests/test-temporal-intervals.fnl`

**Interfaces:**
- Consumes: implemented public behavior from Tasks 1-3.
- Produces: docs that name supported grammar, DST policy, repeat-step semantics, non-goals, and concrete validation evidence.

- [ ] **Step 1: Add a final acceptance smoke test section to the interval test file.**

Add and register this compact acceptance test if the preceding tests do not already cover every assertion:

```fennel
(fn temporal-track6-acceptance-smoke []
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse "2026-09-25T12:00:00Z/PT1H" {:type :instant}))
             "2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"))
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse "2026-01-31T10:00:00/P1M" {:type :plain-date-time}))
             "2026-01-31T10:00:00/2026-02-28T10:00:00"))
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse
                 "2026-09-25T09:00:00-04:00[America/New_York]/2026-09-25T10:00:00-04:00[America/New_York]"
                 {:type :zoned-date-time}))
             "2026-09-25T09:00:00-04:00[America/New_York]/2026-09-25T10:00:00-04:00[America/New_York]"))
  (assert-error #(Temporal.interval.parse "2026-09-25T12:00:00Z/P1D" {:type :instant})
                "calendar period remains invalid for instant intervals")
  (local repeating (Temporal.repeating-interval.parse
                     "R2/2026-01-31T10:00:00/P1M"
                     {:type :plain-date-time}))
  (assert (= (Temporal.interval.format
               (. (Temporal.repeating-interval.occurrences repeating {}) 2))
             "2026-02-28T10:00:00/2026-03-28T10:00:00")))
```

- [ ] **Step 2: Run focused acceptance test.**

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-intervals:main
```

Expected: PASS.

- [ ] **Step 3: Update `docs/dev/features/temporal-intervals.md`.**

Document the supported Track 6 grammar exactly: `start/end`, `start/P...`, `P.../end`, `start/PT...`, `PT.../end`; endpoint types `:instant`, `:plain-date-time`, `:zoned-date-time`; explicit bracketed IANA zones; half-open bounds; exact duration versus calendar period separation; DST `:disambiguation` default `:reject`; repeating exact versus calendar step behavior; and loud-failure non-goals.

- [ ] **Step 4: Update recurrence and library status docs.**

In `docs/dev/features/temporal-parsing-recurrence.md`, remove or revise only statements that still describe these interval forms as deferred. In `docs/dev/features/temporal-complete-acceptance.md`, add concrete Track 6 acceptance evidence with the commands from this task. In `docs/dev/features/temporal-complete-library.md`, mark Track 6 full ISO intervals and repeating intervals as implemented while preserving documented non-goals.

- [ ] **Step 5: Run the final validation ladder.**

Runtime/freshness prerequisite when `./build/space` is missing or stale:

```bash
make build
```

Focused Fennel checks, in required order:

```bash
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-intervals:main
```

Broader local suite justified by broad public temporal parsing/repeating behavior:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Full integration gate: PR CI, including merge queue checks, must pass before ready-to-merge.

- [ ] **Step 6: Verify observable acceptance criteria.**

Confirm all are true from tests/docs: `:instant`, `:plain-date-time`, and `:zoned-date-time` concrete intervals parse; selected derived endpoint grammar parses; `P1D` is rejected for instant intervals; zoned parsing requires explicit bracketed IANA zones; DST gap/overlap behavior uses `:disambiguation` defaulting to `:reject`; repeating intervals preserve exact-duration and calendar-period step semantics; unbounded repeats still require `{:limit n}`; unsupported ISO variants and non-goals fail loudly or remain documented out of scope.

- [ ] **Step 7: Commit Task 4.**

```bash
git add assets/lua/tests/test-temporal-intervals.fnl docs/dev/features/temporal-intervals.md docs/dev/features/temporal-parsing-recurrence.md docs/dev/features/temporal-complete-acceptance.md docs/dev/features/temporal-complete-library.md
git commit -m "docs(lua): record temporal interval track 6 acceptance"
```
