# Temporal Closeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close Track 13 with a bounded cross-surface conformance smoke suite and docs that distinguish Space roadmap completion from full ecosystem-equivalent temporal breadth.

**Architecture:** Add one focused Fennel closeout suite that composes already-landed temporal surfaces through public APIs and asserts representative unsupported future behavior remains loud. Update the canonical roadmap and acceptance matrix to mark Track 13 closed while explicitly listing missing ecosystem-equivalent breadth as future conformance/data expansion.

**Tech Stack:** Space Fennel, `Temporal.*` modules, `RuntimeScheduler`, `RuntimeTimers`, existing Fennel test runner, Markdown docs under `docs/dev/features/`, project-native Fennel validation.

## Global Constraints

- No full libical-backed native iCalendar adapter.
- No custom `VTIMEZONE` observance evaluation beyond the selected supported fixture behavior.
- No full ICU4C/native localization adapter or generated full CLDR data import.
- No broad locale/calendar corpus beyond the current selected seed.
- No holiday jurisdictions or years beyond the packaged business-calendar seed.
- No broad natural-language phrase families or locales beyond the current seed corpus.
- No non-workflow timestamp migration call-site integration.
- No exhaustive ISO 8601-1/-2 interval conformance, open intervals, date-only/all-day intervals, week-date or ordinal-date endpoints, offset-only zoned intervals, business-day intervals, natural-language intervals, or interval algebra.
- No host-local timezone fallback, implicit zone guessing, runtime network temporal data fetches, or native temporal core policy expansion.
- Unsupported broad future behavior must fail loudly or return documented unsupported results; do not silently guess.
- Track 13 may close the bounded Space temporal roadmap, but must not claim full ecosystem-equivalent parity.
- Direct Fennel validation must use project-native `tools.fennel-check`, constraints, and test commands; do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.

---

### Task 1: Cross-Surface Temporal Closeout Smoke Suite

**Files:**
- Create: `assets/lua/tests/test-temporal-closeout.fnl`
- Modify: `assets/lua/tests/fast.fnl`
- Test: `assets/lua/tests/test-temporal-closeout.fnl`

**Interfaces:**
- Consumes: public `Temporal` export from `assets/lua/temporal.fnl`, `RuntimeScheduler.create(opts)`, and `RuntimeTimers` compatibility wrapper module.
- Produces: `tests.test-temporal-closeout:main`, registered in `tests.fast:main`.

- [ ] **Step 1: Create the closeout test module with helpers.**

Create `assets/lua/tests/test-temporal-closeout.fnl` with this structure:

```fennel
(local tests [])
(local Temporal (require :temporal))
(local RuntimeScheduler (require :runtime-scheduler))
(local RuntimeTimers (require :runtime-timers))

(fn assert-error-contains [f needle message]
  (local (ok err) (pcall f))
  (assert (not ok) message)
  (assert (string.find (tostring err) needle 1 true)
          (.. message ": expected " needle ", got " (tostring err))))

(fn assert= [actual expected message]
  (assert (= actual expected)
          (.. message ": expected " (tostring expected) ", got " (tostring actual))))

(fn plain [iso]
  (Temporal.plain-date-time.parse iso))

(fn duration-ms [ms]
  (Temporal.duration.from {:milliseconds ms}))
```

- [ ] **Step 2: Add a core/interval/recurrence composition smoke.**

Add a test named `core-interval-and-recurrence-surfaces-compose` that uses this shape:

```fennel
(fn core-interval-and-recurrence-surfaces-compose []
  (local instant (Temporal.instant.parse "2026-09-25T12:00:00Z"))
  (assert= ((instant:add (Temporal.duration.from {:seconds 90})):to-string)
           "2026-09-25T12:01:30Z"
           "duration arithmetic should remain public")
  (local pdt (plain "2026-01-31T10:00:00"))
  (local period (Temporal.period.from {:months 1}))
  (assert= ((Temporal.period.add-to-plain-date-time period pdt):to-string)
           "2026-02-28T10:00:00"
           "calendar period should clamp month-end")
  (assert= (Temporal.interval.format
             (Temporal.interval.parse "2026-09-25T12:00:00Z/PT1H" {:type :instant}))
           "2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"
           "instant interval exact duration endpoint should format")
  (local repeating (Temporal.repeating-interval.parse
                     "R2/2026-01-31T10:00:00/P1M"
                     {:type :plain-date-time}))
  (assert= (Temporal.interval.format (. (Temporal.repeating-interval.occurrences repeating {}) 2))
           "2026-02-28T10:00:00/2026-03-28T10:00:00"
           "repeating interval should preserve calendar-period stepping")
  (local recurrence-set
    (Temporal.recurrence-set.from
      {:dtstart (plain "2026-01-01T09:00:00")
       :rrules [(Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;COUNT=2")]
       :rdates [(plain "2026-01-03T09:00:00")]
       :exdates [(plain "2026-01-02T09:00:00")]}))
  (local occurrences (Temporal.recurrence-set.occurrences recurrence-set {:zone-id "America/New_York"}))
  (assert= (# occurrences) 2 "recurrence-set should dedupe/exclude and return two occurrences")
  (assert= ((. occurrences 1):to-string)
           "2026-01-01T09:00:00-05:00[America/New_York]"
           "recurrence-set should include dtstart through explicit zone"))
```

If `Temporal.period.from` or `Temporal.period.add-to-plain-date-time` has a different exported name, inspect `assets/lua/temporal/period.fnl` and use the existing public period constructor/add method without adding aliases.

- [ ] **Step 3: Add an interchange/presentation/data smoke.**

Add a test named `interchange-presentation-and-data-surfaces-compose` that verifies ICS, calendar/localization, business calendar, natural language, providers, and migrations:

```fennel
(fn interchange-presentation-and-data-surfaces-compose []
  (local calendar (Temporal.ics.parse "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal Closeout//EN\nBEGIN:VEVENT\nUID:closeout@example.test\nDTSTART:20261001T090000\nDURATION:PT1H\nSUMMARY:Closeout smoke\nEND:VEVENT\nEND:VCALENDAR\n"))
  (local expanded (Temporal.ics.expand calendar {:zone-id "America/New_York"}))
  (assert= (# expanded) 1 "ICS floating event should expand with explicit zone")
  (local iso (plain "2026-10-01T09:30:00"))
  (local japanese (Temporal.calendar.from-iso iso {:calendar "japanese"}))
  (assert= japanese.calendar "japanese" "calendar facade should expose Japanese seed calendar")
  (assert= japanese.era "reiwa" "calendar facade should return finite Japanese era")
  (local localized (Temporal.localization.format-plain-date-time
                     iso
                     {:locale "en-US" :calendar "gregory" :date-style :long}))
  (assert= localized "October 1, 2026" "localization should format selected CLDR seed text")
  (assert (Temporal.business-calendar.is-business-day
            (plain "2026-07-06T09:00:00")
            {:jurisdiction "US-FED"})
          "US-FED business calendar should classify Monday after observed holiday")
  (local natural-candidates (Temporal.natural.candidates "today" {:locale "en-US"}))
  (assert= (. natural-candidates 1 :provider-id)
           "space.temporal.natural-seed"
           "natural candidates should include seed provider id")
  (local provider-candidates (Temporal.providers.parse "today" {:locale "en-US"}))
  (assert= (. provider-candidates 1 :provider-id)
           "space.temporal.natural-seed"
           "provider registry should dispatch natural seed provider")
  (local instant (Temporal.migrations.timestamp->instant
                   0
                   {:schema-id :closeout :field-path "created-at"}))
  (assert= (instant:to-string)
           "1970-01-01T00:00:00Z"
           "migrations should convert legacy integer seconds to instant"))
```

- [ ] **Step 4: Add a runtime scheduler smoke.**

Add a test named `runtime-scheduling-surfaces-compose`:

```fennel
(fn runtime-scheduling-surfaces-compose []
  (local scheduler
    (RuntimeScheduler.create {:clock (Temporal.clock.fixed (Temporal.instant.parse "2026-01-01T00:00:00Z"))}))
  (local calls [])
  (scheduler:schedule-once {:delay (duration-ms 10)
                            :callback (fn [] (table.insert calls "once"))})
  (scheduler:advance (duration-ms 10))
  (assert= (. calls 1) "once" "RuntimeScheduler one-shot should fire")
  (local recurrence-set
    (Temporal.recurrence-set.from {:dtstart (plain "2026-01-01T00:00:00")
                                   :rdates [(plain "2026-01-01T00:00:01")]}))
  (scheduler:schedule-recurrence {:recurrence-set recurrence-set
                                  :zone-id "UTC"
                                  :limit 1
                                  :callback (fn [payload]
                                              (table.insert calls (payload.scheduled-at:to-string)))})
  (scheduler:advance (duration-ms 990))
  (assert= (. calls 2) "2026-01-01T00:00:01Z" "recurrence scheduler payload should expose scheduled-at")
  (RuntimeTimers.clear))
```

- [ ] **Step 5: Add representative unsupported future checks.**

Add a test named `ecosystem-equivalent-futures-remain-loud`:

```fennel
(fn ecosystem-equivalent-futures-remain-loud []
  (assert-error-contains #(Temporal.localization.format-plain-date-time
                            (plain "2026-10-01T09:30:00")
                            {:locale "es-ES" :calendar "gregory" :date-style :short})
                         "unsupported temporal locale"
                         "unsupported CLDR locale should remain loud")
  (assert-error-contains #(Temporal.calendar.from-iso
                            (plain "2026-10-01T09:30:00")
                            {:calendar "islamic"})
                         "unsupported calendar"
                         "unsupported calendar should remain loud")
  (assert-error-contains #(Temporal.business-calendar.holidays {:jurisdiction "CA-FED" :year 2026})
                         "unsupported temporal holiday jurisdiction"
                         "unsupported holiday jurisdiction should remain loud")
  (assert-error-contains #(Temporal.business-calendar.holidays {:jurisdiction "US-FED" :year 2028})
                         "unsupported temporal holiday year"
                         "unsupported holiday year should remain loud")
  (assert-error-contains #(Temporal.natural.candidates "hoy" {:locale "es-ES"})
                         "unsupported temporal natural locale"
                         "unsupported natural language locale should remain loud")
  (local unsupported-provider-text (Temporal.providers.parse "not a temporal phrase" {:locale "en-US"}))
  (assert= (# unsupported-provider-text) 0 "unsupported natural text should return no provider candidates")
  (assert-error-contains #(Temporal.ics.parse "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal Closeout//EN\nBEGIN:VTODO\nUID:todo@example.test\nEND:VTODO\nEND:VCALENDAR\n")
                         "VTODO"
                         "unsupported iCalendar component should remain loud")
  (assert-error-contains #(Temporal.interval.parse "2026-001T00:00:00Z/PT1H" {:type :instant})
                         "temporal interval"
                         "unsupported ordinal-date interval endpoint should remain loud"))
```

- [ ] **Step 6: Register tests and main.**

At the bottom of `test-temporal-closeout.fnl`, insert each test and expose `main`:

```fennel
(table.insert tests {:name "core interval and recurrence surfaces compose"
                     :fn core-interval-and-recurrence-surfaces-compose})
(table.insert tests {:name "interchange presentation and data surfaces compose"
                     :fn interchange-presentation-and-data-surfaces-compose})
(table.insert tests {:name "runtime scheduling surfaces compose"
                     :fn runtime-scheduling-surfaces-compose})
(table.insert tests {:name "ecosystem equivalent futures remain loud"
                     :fn ecosystem-equivalent-futures-remain-loud})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-closeout" :tests tests})))

{:name "temporal-closeout" :tests tests :main main}
```

- [ ] **Step 7: Register the suite in the fast test list.**

Modify `assets/lua/tests/fast.fnl` by adding `:tests.test-temporal-closeout` immediately after `:tests.test-temporal-ics` in the existing temporal block. Do not reorder unrelated test modules.

- [ ] **Step 8: Run focused validation.**

Run these commands in order:

```bash
make fennel-check
make constraints
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-closeout:main
```

Expected: compile check passes, constraints pass with 0 diagnostics, closeout suite passes. If the closeout suite fails because an example uses a stale method name, inspect the focused module and update the test to use the existing public API without adding aliases.

- [ ] **Step 9: Commit.**

```bash
git add assets/lua/tests/test-temporal-closeout.fnl assets/lua/tests/fast.fnl
git commit -m "test(lua): add temporal closeout smoke"
```

---

### Task 2: Track 13 Roadmap And Ecosystem-Gap Documentation

**Files:**
- Modify: `docs/dev/features/temporal-complete-library.md`
- Modify: `docs/dev/features/temporal-complete-acceptance.md`
- Test: `docs/dev/features/temporal-complete-library.md`
- Test: `docs/dev/features/temporal-complete-acceptance.md`

**Interfaces:**
- Consumes: `tests.test-temporal-closeout:main` from Task 1.
- Produces: canonical documentation stating Track 13 is closed and ecosystem-equivalent gaps remain explicit future work.

- [ ] **Step 1: Update current implementation status.**

In `docs/dev/features/temporal-complete-library.md`, replace the final sentence `Track 13 remains future work.` with text equivalent to:

```markdown
Track 13 closeout adds cross-surface temporal smoke coverage and marks the bounded Space temporal roadmap complete. This is a roadmap-completion claim for the documented Space surfaces, not a claim of full ecosystem-equivalent temporal breadth.
```

- [ ] **Step 2: Add an ecosystem-equivalent gap section.**

In `docs/dev/features/temporal-complete-library.md`, add a section after the current implementation status paragraphs:

```markdown
## Ecosystem-equivalent gaps

Space's bounded temporal roadmap is complete after Track 13, but mature ecosystem temporal libraries still cover broader data and conformance surfaces. The following remain future conformance or corpus-expansion work:

- exhaustive ISO 8601-1/-2 interval conformance, including open intervals, date-only/all-day intervals, week-date and ordinal-date endpoints, offset-only zoned intervals, business-day intervals, natural-language intervals, and interval algebra;
- broader RFC5545/iCalendar conformance, calendar-client quirks, libical-backed native adaptation, and custom `VTIMEZONE` observance evaluation;
- full ICU4C/native localization adaptation, generated CLDR data, and broader locale/calendar coverage;
- business-calendar jurisdictions and years beyond the packaged `US-FED` 2026-2027 seed;
- natural-language phrase families and locales beyond the Track 10 seed corpus;
- timestamp migration integration beyond workflow persistence call sites, including the inventory-only `agent-sessions`, `entities/code`, `llm/conversations`, and message families.

Unsupported inputs in these areas must continue to fail loudly or return documented unsupported results until a future reviewed track explicitly expands the surface.
```

Keep the existing unsupported-items paragraph visible; do not delete detail unless it is duplicated verbatim by the new section.

- [ ] **Step 3: Update the final closeout acceptance row.**

In `docs/dev/features/temporal-complete-acceptance.md`, update the `Final closeout` row to mention `tests.test-temporal-closeout`, ecosystem-gap docs audit, full `make test`, and PR CI/merge queue.

- [ ] **Step 4: Add Track 13 acceptance evidence commands.**

In `docs/dev/features/temporal-complete-acceptance.md`, add a section before `## Maintenance rule`:

````markdown
## Track 13 final closeout acceptance evidence

The final conformance and closeout track is accepted locally when these commands pass in order:

```bash
make fennel-check
make constraints
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-closeout:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

The closeout suite is a cross-surface smoke test. It does not replace focused per-track suites; it proves that public exports, packaged deterministic data, representative integrations, and loud unsupported behavior remain wired together after the roadmap closes. PR CI and the merge queue remain the integration gate.
````

- [ ] **Step 5: Run docs and focused closeout validation.**

Run:

```bash
make fennel-check
make constraints
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-closeout:main
```

Also run a text audit:

```bash
rg "Track 13|ecosystem-equivalent|libical|ICU4C|VTIMEZONE|US-FED|agent-sessions|tests.test-temporal-closeout" docs/dev/features/temporal-complete-library.md docs/dev/features/temporal-complete-acceptance.md
```

Expected: Fennel validation stays green, closeout suite passes, and the text audit shows Track 13 closed plus explicit ecosystem-equivalent gaps.

- [ ] **Step 6: Commit.**

```bash
git add docs/dev/features/temporal-complete-library.md docs/dev/features/temporal-complete-acceptance.md
git commit -m "docs(lua): close temporal roadmap"
```

---

### Task 3: Final Track 13 Validation

**Files:**
- Test: `assets/lua/tests/test-temporal-closeout.fnl`
- Test: `assets/lua/tests/fast.fnl`
- Test: `docs/dev/features/temporal-complete-library.md`
- Test: `docs/dev/features/temporal-complete-acceptance.md`

**Interfaces:**
- Consumes: Task 1 closeout suite and Task 2 docs.
- Produces: final validation evidence for SDD review and finishing workflow.

- [ ] **Step 1: Verify clean working tree before final validation.**

Run:

```bash
git status --porcelain
```

Expected: no output. If output is non-empty, report the exact files and resolve through the task before validation.

- [ ] **Step 2: Run final local validation in required order.**

Run:

```bash
make fennel-check
make constraints
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-closeout:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Expected: compile check passes, constraints pass with 0 diagnostics, closeout suite passes, and `make test` passes.

- [ ] **Step 3: Run final docs audit.**

Run:

```bash
rg "Track 13 closeout|bounded Space temporal roadmap|Ecosystem-equivalent gaps|tests.test-temporal-closeout|PR CI" docs/dev/features/temporal-complete-library.md docs/dev/features/temporal-complete-acceptance.md
```

Expected: output includes the closed-roadmap wording, ecosystem-equivalent gap section, closeout suite command, and PR CI integration-gate wording.

- [ ] **Step 4: Record validation evidence.**

In the implementer report, include:

- compile-check command/result;
- constraints command/result and constraint-impact note;
- focused closeout suite command/result;
- broad `make test` command/result;
- docs audit command/result;
- coverage rationale explaining that the closeout suite is shallow cross-surface coverage while focused per-track suites remain authoritative for deep behavior.

- [ ] **Step 5: Commit only if final validation required repository changes.**

If no repository changes are needed, create no commit and report `DONE`. If a validation-only docs/test fix was required, commit with a focused message:

```bash
git add assets/lua/tests/test-temporal-closeout.fnl assets/lua/tests/fast.fnl docs/dev/features/temporal-complete-library.md docs/dev/features/temporal-complete-acceptance.md
git commit -m "fix(lua): finalize temporal closeout evidence"
```
