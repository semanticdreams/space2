# Temporal ICS/iCalendar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a selected-corpus Fennel `Temporal.ics` API for parsing, formatting, and expanding supported ICS `VCALENDAR`/`VEVENT` records.

**Architecture:** Implement `Temporal.ics` as a pure Fennel facade under `assets/lua/temporal/ics/`, composed from existing temporal core, recurrence, recurrence-set, period, and interval modules. Keep ICS grammar and product policy out of native C++ and fail loudly for unsupported components, properties, timezones, options, and event shapes.

**Tech Stack:** Space Fennel, project-native `tools.fennel-check`, Fennel fast test runner, existing `Temporal.recurrence`, `Temporal.recurrence-set`, `Temporal.period`, `Temporal.interval`, and native tzdb-backed `Instant`/`PlainDateTime`/`ZonedDateTime`.

## Global Constraints

- no host-local timezone defaults;
- exact `Duration` remains nanoseconds-only;
- all-day/date-only values remain calendar concepts, not exact durations;
- native temporal core remains independent from ICS grammar, providers, localization, business calendars, and scheduler policy;
- runtime ICS parsing/export does not fetch network data;
- canonical option keys only;
- unsupported components/properties/timezone semantics fail loudly.
- Do not vendor libical or enable `SPACE_TEMPORAL_ENABLE_ICAL_ADAPTER` in this track.
- Keep `external/temporal/libical/DEPENDENCY_MANIFEST.json` at `"status": "planned"`.
- Unknown option keys throw. No aliases such as `:timezone`, `:tz`, `:ics-text`, or `:ical` are accepted.
- `VERSION:2.0` is required.
- `CALSCALE` defaults to `GREGORIAN` if absent and must be `GREGORIAN` when present.
- `UID` and `DTSTART` are required for supported events.
- `DTEND` and `DURATION` are mutually exclusive.
- `STATUS` defaults to `:confirmed`; unsupported statuses throw.
- Floating expansion requires caller `:zone-id` and never defaults to the host environment.
- HUMAN_DECISION_REQUIRED: none for this selected-corpus Fennel track.

---

## File Structure

### Production files

- Create: `assets/lua/temporal/ics/grammar.fnl` — content-line parsing/unfolding, parameter parsing, text escaping/unescaping, canonical line folding.
- Create: `assets/lua/temporal/ics/value.fnl` — ICS date/date-time wrappers, date arithmetic helpers, ICS `DURATION` parsing/formatting, normalized keys.
- Create: `assets/lua/temporal/ics/parser.fnl` — `VCALENDAR`, `VEVENT`, and metadata-only `VTIMEZONE` parser.
- Create: `assets/lua/temporal/ics/formatter.fnl` — canonical serializer with deterministic property order, escaping, folding, and CRLF/LF line endings.
- Create: `assets/lua/temporal/ics/expand.fnl` — event grouping, recurrence-set composition, all-day expansion, overrides, cancellations, and occurrence records.
- Create: `assets/lua/temporal/ics.fnl` — factory facade returning public `parse`, `format`, and `expand`.
- Modify: `assets/lua/temporal.fnl` — wire `Temporal.ics` into the public temporal facade.

### Test and fixture files

- Create: `assets/lua/tests/test-temporal-ics.fnl` — focused grammar, parse, format, round-trip, expansion, override/cancellation, diagnostics, and acceptance smoke tests.
- Modify: `assets/lua/tests/fast.fnl` — register `:tests.test-temporal-ics` near the other temporal suites.
- Create fixture directory `assets/lua/tests/data/temporal/ics/` with these files: `single-utc.ics`, `single-floating.ics`, `single-zoned.ics`, `single-all-day.ics`, `multi-day-all-day.ics`, `timed-duration.ics`, `all-day-duration.ics`, `weekly-rrule.ics`, `rrule-rdate-exdate.ics`, `exrule.ics`, `utc-until.ics`, `override.ics`, `cancelled-occurrence.ics`, `cancelled-master.ics`, `folded-escaped.ics`, `unsupported-tzid.ics`, and `unsupported-component.ics`.

### Documentation files

- Create: `docs/dev/features/temporal-ics.md`.
- Modify: `docs/dev/features/temporal.md`.
- Modify: `docs/dev/features/temporal-complete-acceptance.md`.
- Modify: `docs/dev/features/temporal-complete-library.md`.

### Record shapes

Calendar record:

```fennel
{:kind :temporal-ics-calendar
 :version "2.0"
 :prod-id "-//Space//Temporal//EN"
 :calscale "GREGORIAN"
 :method nil
 :timezones [timezone-record ...]
 :events [event-record ...]
 :x-properties [property-record ...]}
```

Event record:

```fennel
{:kind :temporal-ics-event
 :uid "event-id"
 :sequence 0
 :status :confirmed
 :summary "Title"
 :description "Body"
 :dtstart ics-date-time
 :dtend ics-date-time
 :duration duration-or-period-record
 :rrules [recurrence-rule ...]
 :rdates [ics-date-time ...]
 :exdates [ics-date-time ...]
 :exrules [recurrence-rule ...]
 :recurrence-id ics-date-time
 :source-order 1
 :x-properties [property-record ...]}
```

ICS date/time wrappers:

```fennel
{:kind :temporal-ics-date-time :value-type :date :date {:year 2026 :month 10 :day 1}}
{:kind :temporal-ics-date-time :value-type :date-time :time-mode :floating :plain <PlainDateTime>}
{:kind :temporal-ics-date-time :value-type :date-time :time-mode :utc :instant <Instant>}
{:kind :temporal-ics-date-time :value-type :date-time :time-mode :zoned :zone-id "America/New_York" :plain <PlainDateTime>}
```

Occurrence record:

```fennel
{:kind :temporal-ics-occurrence
 :uid "event-id"
 :event event-record
 :recurrence-id ics-date-time
 :start ics-date-time
 :end ics-date-time
 :status :confirmed
 :summary "Title"
 :description "Body"}
```

Timed UTC occurrences may also include `:instant-interval`; timed zoned occurrences may also include `:zoned-interval`; date-only occurrences must not include exact interval fields.

---

### Task 1: ICS Grammar, Folding, Escaping, and Test Harness

**Files:**
- Create: `assets/lua/temporal/ics/grammar.fnl`
- Create: `assets/lua/tests/test-temporal-ics.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: none.
- Produces: `grammar.unfold-lines`, `grammar.parse-content-line`, `grammar.parse-content-lines`, `grammar.unescape-text`, `grammar.escape-text`, `grammar.fold-line`, `grammar.emit-content-line`.
- Content-line shape: `{:kind :temporal-ics-content-line :name "DTSTART" :params {"TZID" "America/New_York"} :value "20261001T090000" :source-order 1}`.

- [ ] **Step 1: Write failing grammar tests**

  Create `assets/lua/tests/test-temporal-ics.fnl` with helpers `assert=`, `assert-error`, and `assert-error-contains`. Add tests named:
  - `grammar unfolds CRLF and LF lines`: verifies `"SUMMARY:Alpha\r\n beta\r\nDTSTART:20261001T090000\r\n"` and the LF variant unfold to `"SUMMARY:Alphabeta"` and `"DTSTART:20261001T090000"`.
  - `grammar parses names params and values`: verifies `DTSTART;TZID=America/New_York:20261001T090000` parses uppercase property/param names and `SUMMARY:Review\, plan\; ship\\done\nNext` unescapes to `Review, plan; ship\done` plus newline plus `Next`.
  - `grammar rejects malformed lines and escapes`: verifies missing colon, invalid property name containing a space, unknown escape `\q`, and trailing backslash throw errors containing `content line`, `property`, or `escape`.
  - `grammar emits folded content lines`: verifies `grammar.emit-content-line` escapes comma/semicolon/backslash/newline and folds a long `DESCRIPTION` line with newline plus leading space.

- [ ] **Step 2: Run the focused test and verify it fails**

  If `./build/space` is missing or stale, run `make build` with timeout 14400000. Then run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-ics:main
  ```

  Expected: failure because `temporal/ics/grammar` does not exist.

- [ ] **Step 3: Implement grammar helpers**

  Implement `assets/lua/temporal/ics/grammar.fnl` with this contract:
  - Accept CRLF and LF input.
  - RFC-unfold by removing a line break followed by one space or tab.
  - Reject malformed content lines without `:`.
  - Uppercase parsed property and parameter names.
  - Store parameters as scalar string values in an uppercase string-keyed table.
  - Reject duplicate parameters on one content line.
  - `unescape-text` supports `\\`, `\,`, `\;`, `\n`, and `\N`.
  - `escape-text` emits canonical escapes for backslash, comma, semicolon, CR, and LF.
  - `fold-line` folds lines longer than 75 bytes with CRLF plus leading space; `emit-content-line` converts line endings to `:crlf` or `:lf`.
  - Unknown line endings or non-string inputs throw loud errors naming the bad boundary.

- [ ] **Step 4: Register the focused test suite**

  Add `:tests.test-temporal-ics` to `assets/lua/tests/fast.fnl` immediately after the temporal recurrence suites.

- [ ] **Step 5: Validate Task 1**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files \
    --file assets/lua/temporal/ics/grammar.fnl \
    --file assets/lua/tests/test-temporal-ics.fnl \
    --file assets/lua/tests/fast.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-ics:main
  ```

- [ ] **Step 6: Commit Task 1**

  ```bash
  git add assets/lua/temporal/ics/grammar.fnl assets/lua/tests/test-temporal-ics.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(assets): add temporal ICS grammar helpers"
  ```

---

### Task 2: ICS Date/Time and Duration Values

**Files:**
- Create: `assets/lua/temporal/ics/value.fnl`
- Modify: `assets/lua/tests/test-temporal-ics.fnl`

**Interfaces:**
- Consumes: `Temporal` public facade and grammar helpers.
- Produces: `value.parse-date-time`, `value.format-date-time`, `value.parse-duration`, `value.format-duration`, `value.date-key`, `value.normalized-key`, `value.same-mode?`, `value.start-plus-duration`, `value.default-end`, `value.date->plain`, and `value.plain->date`.

- [ ] **Step 1: Add failing value tests**

  Extend `test-temporal-ics.fnl` with tests named:
  - `value parses date time modes`: asserts `VALUE=DATE` `20261001` returns date wrapper; `20261001T090000` returns floating wrapper; `20261001T130000Z` returns UTC wrapper; `TZID=America/New_York` plus `20261001T090000` returns zoned wrapper.
  - `value formats date time modes`: formats those wrappers back to `VALUE=DATE`, UTC `Z`, floating no-parameter, and zoned `TZID` forms.
  - `value parses and formats supported durations`: asserts timed `PT1H30M` returns exact duration equal to 5400 seconds and all-day `P2D` returns a `Temporal.period` formatted as `P2D`.
  - `value rejects unsupported date time boundaries`: asserts unknown `TZID=Custom/Local`, `VALUE=DATE-TIME`, `TZID` on date values, mixed `P1DT2H`, and all-day `PT1H` throw loud errors.

- [ ] **Step 2: Run focused test and verify it fails**

  Expected: failure because `temporal/ics/value` does not exist.

- [ ] **Step 3: Implement `value.fnl`**

  Required behavior:
  - Parse `YYYYMMDD` only with `VALUE=DATE`.
  - Parse `YYYYMMDDTHHMMSS` as floating date-time.
  - Parse `YYYYMMDDTHHMMSSZ` as UTC instant.
  - Parse `TZID=<IANA zone>` plus `YYYYMMDDTHHMMSS` as zoned date-time and validate the zone by attempting conversion for a fixed known date.
  - Reject numeric offsets, fractional seconds, unsupported `VALUE`, and unknown parameters.
  - Timed `DURATION` supports exact `PT...` hours/minutes/seconds only and returns `Temporal.duration`.
  - All-day `DURATION` supports date-only `P...` periods and returns `Temporal.period`.
  - Reject mixed `P...T...` durations in this track.
  - `default-end` returns next day for date-only values and same wrapper for timed values without `DTEND`/`DURATION`.
  - `start-plus-duration` preserves wrapper mode.
  - `normalized-key` emits `DATE:yyyy-mm-dd`, `FLOATING:<plain>`, `UTC:<instant>`, or `ZONED:<zone>:<plain>`.

- [ ] **Step 4: Validate Task 2**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files \
    --file assets/lua/temporal/ics/value.fnl \
    --file assets/lua/tests/test-temporal-ics.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-ics:main
  ```

- [ ] **Step 5: Commit Task 2**

  ```bash
  git add assets/lua/temporal/ics/value.fnl assets/lua/tests/test-temporal-ics.fnl
  git commit -m "feat(assets): add temporal ICS value parsing"
  ```

---

### Task 3: Public Facade and VCALENDAR/VEVENT Parser

**Files:**
- Create: `assets/lua/temporal/ics/parser.fnl`
- Create: `assets/lua/temporal/ics.fnl`
- Modify: `assets/lua/temporal.fnl`
- Modify: `assets/lua/tests/test-temporal-ics.fnl`
- Create: `assets/lua/tests/data/temporal/ics/*.ics`

**Interfaces:**
- Consumes: grammar helpers, value helpers, and `Temporal.recurrence.parse-rrule`.
- Produces: `parser.parse-calendar` and public `Temporal.ics.parse`. Public `Temporal.ics.format` and `Temporal.ics.expand` exist as loud placeholders until later tasks.

- [ ] **Step 1: Create the fixture corpus**

  Add the 17 fixture files listed in File Structure. Minimum content requirements:
  - Every successful fixture has `BEGIN:VCALENDAR`, `VERSION:2.0`, `PRODID:-//Space//Temporal//EN`, one or more `VEVENT`, and `END:VCALENDAR`.
  - `single-utc.ics` uses `DTSTART:20261001T130000Z` and `DTEND:20261001T140000Z`.
  - `single-floating.ics` uses `DTSTART:20261001T090000` and `DTEND:20261001T100000`.
  - `single-zoned.ics` includes metadata `VTIMEZONE` with `TZID:America/New_York` and event `DTSTART;TZID=America/New_York:20261001T090000`.
  - `single-all-day.ics` uses `DTSTART;VALUE=DATE:20261001`.
  - `multi-day-all-day.ics` uses `DTSTART;VALUE=DATE:20261001` and `DTEND;VALUE=DATE:20261004`.
  - `timed-duration.ics` uses `DURATION:PT1H30M`.
  - `all-day-duration.ics` uses `DURATION:P2D`.
  - `weekly-rrule.ics` uses `RRULE:FREQ=WEEKLY;COUNT=3`.
  - `rrule-rdate-exdate.ics` uses `RRULE:FREQ=DAILY;COUNT=3`, `RDATE:20261005T090000`, and `EXDATE:20261002T090000`.
  - `exrule.ics` uses `RRULE:FREQ=DAILY;COUNT=5` and `EXRULE:FREQ=DAILY;COUNT=2`.
  - `utc-until.ics` uses UTC `DTSTART` and `RRULE:FREQ=DAILY;UNTIL=20261003T130000Z`.
  - `override.ics` uses a recurring master plus non-cancelled override with same `UID` and `RECURRENCE-ID:20261002T090000`.
  - `cancelled-occurrence.ics` uses a recurring master plus override with `STATUS:CANCELLED`.
  - `cancelled-master.ics` uses master `STATUS:CANCELLED`.
  - `folded-escaped.ics` includes folded `SUMMARY` and escaped `DESCRIPTION`.
  - `unsupported-tzid.ics` uses `TZID=Custom/Local`.
  - `unsupported-component.ics` contains a `VTODO` component.

- [ ] **Step 2: Add failing parser and facade tests**

  Add a fixture helper that reads from `$(SPACE_ASSETS_PATH)/lua/tests/data/temporal/ics/<name>.ics`. Add tests named:
  - `parser exports public temporal ics`: asserts `Temporal.ics.parse`, `.format`, and `.expand` are functions.
  - `parser parses supported fixture records`: parses `single-zoned` and asserts calendar kind/version/calscale/timezone and event uid/status/sequence/zoned start/summary.
  - `parser parses all required fixture families`: loops through all successful fixtures and asserts at least one event.
  - `parser preserves x properties only under preserve policy`: strict rejects `X-SPACE-*`; preserve stores property records.
  - `parser rejects invalid calendar and event shapes`: missing `VERSION`, bad `CALSCALE`, missing `UID`, missing `DTSTART`, unsupported component, unsupported TZID, `DTEND` plus `DURATION`, and unknown `LOCATION` all throw named errors.

- [ ] **Step 3: Run focused test and verify it fails**

  Expected: `Temporal.ics` is nil or parser module missing.

- [ ] **Step 4: Implement parser**

  `parser.parse-calendar Temporal text options` must:
  - Validate only `:unknown-property-policy`, default `:reject`, allowed `:reject`/`:preserve`.
  - Require one top-level `BEGIN:VCALENDAR` and matching `END:VCALENDAR`.
  - Accept top-level `VERSION`, `PRODID`, `CALSCALE`, `METHOD`, `VTIMEZONE`, and `VEVENT`.
  - Parse `VTIMEZONE` as metadata retaining raw unfolded lines and extracting `TZID`.
  - Parse event `UID`, `SUMMARY`, `DESCRIPTION`, `STATUS`, `SEQUENCE`, `DTSTART`, `DTEND`, `DURATION`, `RRULE`, `RDATE`, `EXDATE`, `EXRULE`, `RECURRENCE-ID`, `DTSTAMP`, and `X-...` under preserve policy.
  - Preserve `DTSTAMP` as an event `x-properties` record.
  - Use text unescaping for `SUMMARY`/`DESCRIPTION`.
  - Parse repeated `RRULE`, `RDATE`, `EXDATE`, and `EXRULE` into arrays; parse comma-separated `RDATE`/`EXDATE` values.
  - Enforce `RDATE`/`EXDATE` mode compatibility with `DTSTART`.
  - Default `STATUS` to `:confirmed`; accept only `CONFIRMED`, `CANCELLED`, and `TENTATIVE`.
  - Default `SEQUENCE` to `0`; reject non-integer sequence.
  - Reject duplicate scalar event properties except repeated recurrence/date lists.
  - Reject unsupported components outside `VTIMEZONE`.

- [ ] **Step 5: Implement facade wiring**

  Create `assets/lua/temporal/ics.fnl` as a factory that receives the public `Temporal` table and returns `{:parse parse :format format :expand expand}`. `parse` calls `parser.parse-calendar`; placeholders for `format` and `expand` throw `Temporal.ics.format is not implemented` and `Temporal.ics.expand is not implemented`. Modify `assets/lua/temporal.fnl` to require this factory and attach `:ics` to the returned public table without introducing a circular partial table bug.

- [ ] **Step 6: Validate Task 3**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files \
    --file assets/lua/temporal.fnl \
    --file assets/lua/temporal/ics.fnl \
    --file assets/lua/temporal/ics/parser.fnl \
    --file assets/lua/tests/test-temporal-ics.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-ics:main
  ```

- [ ] **Step 7: Commit Task 3**

  ```bash
  git add assets/lua/temporal.fnl assets/lua/temporal/ics.fnl assets/lua/temporal/ics/parser.fnl assets/lua/tests/test-temporal-ics.fnl assets/lua/tests/data/temporal/ics
  git commit -m "feat(assets): parse selected temporal ICS records"
  ```

---

### Task 4: Canonical ICS Formatter and Round Trips

**Files:**
- Create: `assets/lua/temporal/ics/formatter.fnl`
- Modify: `assets/lua/temporal/ics.fnl`
- Modify: `assets/lua/tests/test-temporal-ics.fnl`

**Interfaces:**
- Consumes: grammar emit/escape, value formatters, `Temporal.recurrence.to-rrule`, parser records.
- Produces: `formatter.format-calendar` and public `Temporal.ics.format`.

- [ ] **Step 1: Add failing formatter tests**

  Add tests named:
  - `formatter emits canonical single event`: parsing `single-utc` then formatting with `{:line-ending :lf}` emits VCALENDAR header, VEVENT with UID/SEQUENCE/STATUS/DTSTART/DTEND/SUMMARY, and no CRLF.
  - `formatter defaults to crlf`: default formatting contains CRLF and no bare LF.
  - `formatter round trips supported fixtures`: parse/format/parse all successful fixtures and assert kind, event count, and first UID survive.
  - `formatter rejects unknown record keys`: adding `calendar.timezone` throws error containing `timezone`.
  - `formatter validates options`: `:newline` alias and invalid `:line-ending :native` throw.

- [ ] **Step 2: Run focused test and verify it fails**

  Expected: `Temporal.ics.format is not implemented`.

- [ ] **Step 3: Implement formatter**

  Required behavior:
  - Validate only `:line-ending`; default `:crlf`; allowed `:crlf` and `:lf`.
  - Validate known record keys for calendar, event, timezone, property, and date-time wrappers.
  - Emit deterministic calendar order: `BEGIN:VCALENDAR`, `VERSION`, `PRODID`, `CALSCALE`, optional `METHOD`, calendar x-properties, preserved VTIMEZONE records by source order, VEVENT records by source order, `END:VCALENDAR`.
  - Emit deterministic event order: `BEGIN:VEVENT`, `UID`, `SEQUENCE`, `STATUS`, optional `RECURRENCE-ID`, `DTSTART`, optional `DTEND`, optional `DURATION`, `RRULE`, `RDATE`, `EXDATE`, `EXRULE`, optional `SUMMARY`, optional `DESCRIPTION`, x-properties, `END:VEVENT`.
  - Use uppercase property names and `Temporal.recurrence.to-rrule` for RRULE/EXRULE.
  - Emit one comma-separated `RDATE` line and one comma-separated `EXDATE` line per event when non-empty.
  - Escape `SUMMARY` and `DESCRIPTION`.
  - Preserve all-day exclusive `DTEND`.
  - Default missing constructed `prod-id` to `"-//Space//Temporal//EN"` during format only.
  - Re-emit preserved VTIMEZONE raw lines with canonical line-ending conversion; do not synthesize observance blocks.

- [ ] **Step 4: Wire formatter into facade**

  Replace the `format` placeholder in `assets/lua/temporal/ics.fnl` with `formatter.format-calendar Temporal calendar (or options {})`.

- [ ] **Step 5: Validate Task 4**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files \
    --file assets/lua/temporal/ics.fnl \
    --file assets/lua/temporal/ics/formatter.fnl \
    --file assets/lua/tests/test-temporal-ics.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-ics:main
  ```

- [ ] **Step 6: Commit Task 4**

  ```bash
  git add assets/lua/temporal/ics.fnl assets/lua/temporal/ics/formatter.fnl assets/lua/tests/test-temporal-ics.fnl
  git commit -m "feat(assets): format canonical temporal ICS records"
  ```

---

### Task 5: Non-Override Expansion

**Files:**
- Create: `assets/lua/temporal/ics/expand.fnl`
- Modify: `assets/lua/temporal/ics.fnl`
- Modify: `assets/lua/tests/test-temporal-ics.fnl`

**Interfaces:**
- Consumes: parser records, value helpers, `Temporal.recurrence-set`, `Temporal.interval`, and native temporal primitives.
- Produces: `expand.expand-calendar` and public `Temporal.ics.expand` for single events and recurrence sets before override replacement.

- [ ] **Step 1: Add failing expansion tests**

  Add helper `expand-fixture` that parses a fixture and calls `Temporal.ics.expand`. Add tests named:
  - `expand single event modes`: UTC occurrence has UTC start and `:instant-interval`; floating occurrence requires provided zone but remains floating; zoned occurrence has `America/New_York` and `:zoned-interval`; all-day occurrence has date start/end and no exact interval fields.
  - `expand requires zone for floating events`: missing `:zone-id` and alias `:timezone` throw.
  - `expand duration events`: timed duration ends at `2026-10-01T10:30:00`; all-day `P2D` ends on day 3.
  - `expand recurrence fixtures`: weekly count yields 3, RRULE/RDATE/EXDATE yields 3, EXRULE fixture yields 3, UTC UNTIL yields 3.
  - `expand unbounded recurrence requires limit`: unbounded daily recurrence throws without `:limit` and yields 2 with `:limit 2`.

- [ ] **Step 2: Run focused test and verify it fails**

  Expected: `Temporal.ics.expand is not implemented`.

- [ ] **Step 3: Implement expansion option validation**

  Allowed keys are `:zone-id`, `:disambiguation`, and `:limit`. `:disambiguation` defaults to `:reject` and accepts `:reject`, `:earliest`, and `:latest`. `:limit` must be a positive integer when present. Unknown keys throw naming the key. Floating timed expansion requires string `:zone-id`; zoned, UTC, and date-only expansion do not.

- [ ] **Step 4: Implement base occurrence expansion**

  Group by `UID`; reject duplicate masters and duplicate `RECURRENCE-ID` keys for now. A non-recurring non-cancelled master yields one occurrence. A cancelled master yields none. End calculation order is `DTEND`, then `DURATION`, then `value.default-end`. Copy summary/description from the selected event. Add exact interval fields only for UTC and zoned timed occurrences when start precedes end.

- [ ] **Step 5: Implement recurrence expansion**

  If an event has no `RRULE`, `RDATE`, `EXDATE`, or `EXRULE`, use simple expansion. Timed floating and zoned recurrences use `Temporal.recurrence-set`; UTC recurrences use the recurrence set with zone id `UTC` and map results back to UTC wrappers; all-day recurrences use midnight `PlainDateTime` internally but return date wrappers. `RDATE`/`EXDATE` must match `DTSTART` mode. `EXRULE` applies before output truncation. UTC `UNTIL` uses existing recurrence-set UTC support. Unbounded active recurrence without `:limit` throws a message containing `limit`.

- [ ] **Step 6: Wire expander into facade**

  Replace the `expand` placeholder with `expand.expand-calendar Temporal calendar (or options {})`.

- [ ] **Step 7: Validate Task 5**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files \
    --file assets/lua/temporal/ics.fnl \
    --file assets/lua/temporal/ics/expand.fnl \
    --file assets/lua/tests/test-temporal-ics.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-ics:main
  ```

- [ ] **Step 8: Commit Task 5**

  ```bash
  git add assets/lua/temporal/ics.fnl assets/lua/temporal/ics/expand.fnl assets/lua/tests/test-temporal-ics.fnl
  git commit -m "feat(assets): expand selected temporal ICS events"
  ```

---

### Task 6: Overrides, Cancellations, Duplicate Diagnostics, and Acceptance Smoke

**Files:**
- Modify: `assets/lua/temporal/ics/expand.fnl`
- Modify: `assets/lua/tests/test-temporal-ics.fnl`

**Interfaces:**
- Consumes: `expand.expand-calendar` and `value.normalized-key`.
- Produces: override replacement, cancellation removal, duplicate diagnostics, and final focused acceptance smoke.

- [ ] **Step 1: Add failing override/cancellation tests**

  Add tests named:
  - `expand applies overrides and cancellations`: `override` yields 3 occurrences and second occurrence summary `Moved recurring event`, start `2026-10-02T11:00:00`, recurrence id `2026-10-02T09:00:00`; `cancelled-occurrence` yields 2 and lacks cancelled recurrence id; `cancelled-master` yields 0.
  - `expand rejects ambiguous duplicate events`: duplicate masters throw `duplicate master`; duplicate overrides for same recurrence id throw `duplicate override`.
  - `temporal ics acceptance smoke`: folded/escaped fixture parse-format-parse keeps summary, weekly recurrence yields 3, cancelled occurrence yields 2, unsupported component remains loud.

- [ ] **Step 2: Run focused test and verify it fails**

  Expected: override/cancellation assertions fail or duplicate diagnostics are missing.

- [ ] **Step 3: Implement override and cancellation grouping**

  Required behavior:
  - Group all events by `UID`.
  - Allow exactly zero or one master per UID; duplicate masters throw `duplicate master`.
  - Key `RECURRENCE-ID` events by `value.normalized-key`.
  - Duplicate recurrence-id events for one UID throw `duplicate override` even if one is cancelled.
  - Cancelled recurrence-id event removes generated master occurrence with that key.
  - Non-cancelled recurrence-id event replaces generated occurrence with override start/end, summary fallback, description fallback, `:event` set to override, and `:recurrence-id` set to the original recurrence id.
  - Overrides outside the generated window are included as standalone occurrences only when their UID has a master and status is not cancelled.
  - Sort final occurrences deterministically by instant when available, otherwise floating resolved with caller zone then local string, otherwise date key, then UID, then source order.

- [ ] **Step 4: Validate Task 6**

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files \
    --file assets/lua/temporal/ics/expand.fnl \
    --file assets/lua/tests/test-temporal-ics.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-ics:main
  ```

- [ ] **Step 5: Commit Task 6**

  ```bash
  git add assets/lua/temporal/ics/expand.fnl assets/lua/tests/test-temporal-ics.fnl
  git commit -m "feat(assets): handle temporal ICS overrides"
  ```

---

### Task 7: Documentation and Dependency Manifest Guard

**Files:**
- Create: `docs/dev/features/temporal-ics.md`
- Modify: `docs/dev/features/temporal.md`
- Modify: `docs/dev/features/temporal-complete-acceptance.md`
- Modify: `docs/dev/features/temporal-complete-library.md`
- Modify: `assets/lua/tests/test-temporal-ics.fnl`

**Interfaces:**
- Consumes: complete public `Temporal.ics` API.
- Produces: developer documentation and test guard proving libical remains planned and not imported.

- [ ] **Step 1: Add manifest guard test**

  Add `dependency manifest keeps libical planned`: read `$(SPACE_ASSETS_PATH)/../external/temporal/libical/DEPENDENCY_MANIFEST.json`, assert the text contains `"status": "planned"`, and assert it does not contain `"status": "vendored"`.

- [ ] **Step 2: Run focused test and verify the guard passes before docs**

  The test should pass with the current manifest. If it fails, fix path/assertion; do not mark libical vendored.

- [ ] **Step 3: Create `docs/dev/features/temporal-ics.md`**

  Include sections: `# Temporal ICS/iCalendar`, `## Public API`, `## Supported corpus`, `## Value modes`, `## Recurrence, overrides, and cancellations`, `## Formatting contract`, `## VTIMEZONE and libical boundary`, `## Non-goals`, and `## Validation`. API examples must show `Temporal.ics.parse`, `Temporal.ics.format`, and `Temporal.ics.expand` with canonical option keys. The libical section must state `VTIMEZONE` is metadata-only, Space tzdb resolves IANA `TZID`, custom observance evaluation is unsupported, and libical remains the future conformance-expansion gate.

- [ ] **Step 4: Update existing temporal docs**

  - In `docs/dev/features/temporal.md`, add and link `Temporal.ics` in the higher-level temporal layer.
  - In `docs/dev/features/temporal-complete-acceptance.md`, update the ICS row with fixture corpus, parse/export round trips, override/cancellation tests, invalid diagnostics, focused suite, and PR CI requirement.
  - In `docs/dev/features/temporal-complete-library.md`, update current implementation status to include selected-corpus `Temporal.ics`; keep broader conformance/client quirks/libical/custom `VTIMEZONE` as unsupported future expansion.

- [ ] **Step 5: Validate Task 7**

  ```bash
  rg "Temporal\.ics|temporal-ics|libical remains|selected-corpus|VTIMEZONE" \
    docs/dev/features/temporal-ics.md \
    docs/dev/features/temporal.md \
    docs/dev/features/temporal-complete-acceptance.md \
    docs/dev/features/temporal-complete-library.md
  ./build/space -m tools.fennel-check:main -- --target files \
    --file assets/lua/tests/test-temporal-ics.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-ics:main
  ```

- [ ] **Step 6: Commit Task 7**

  ```bash
  git add docs/dev/features/temporal-ics.md docs/dev/features/temporal.md docs/dev/features/temporal-complete-acceptance.md docs/dev/features/temporal-complete-library.md assets/lua/tests/test-temporal-ics.fnl
  git commit -m "docs(assets): document temporal ICS facade"
  ```

---

### Task 8: Final Focused and Broad Validation

**Files:**
- Modify only if validation exposes reviewed defects in files from Tasks 1-7.

**Interfaces:**
- Consumes: complete `Temporal.ics` implementation and registered focused/fast tests.
- Produces: final local validation evidence and PR CI readiness.

- [ ] **Step 1: Ensure runtime freshness**

  ```bash
  make build
  ```

- [ ] **Step 2: Run Fennel compile check first**

  ```bash
  make fennel-check
  ```

- [ ] **Step 3: Run constraints second**

  ```bash
  make constraints
  ```

- [ ] **Step 4: Run focused ICS suite third**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-ics:main
  ```

- [ ] **Step 5: Run adjacent temporal suites**

  Justification: `Temporal.ics` composes recurrence, recurrence-set, interval, period, and the public temporal facade.

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-recurrence-rfc5545:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-recurrence-set:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-intervals:main
  ```

- [ ] **Step 6: Run full relevant local suite**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- [ ] **Step 7: Use enclosing-form repair workflow for Fennel parse/delimiter errors**

  If any Fennel parse or delimiter failure appears, inspect the nearest enclosing form around the reported location. If the form is deeply nested, move logic into helper functions instead of guessing closing delimiters. Rerun `make fennel-check` before constraints or tests. Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e`.

- [ ] **Step 8: Confirm observable acceptance criteria**

  Verify evidence shows public `Temporal.ics` exports, all 17 fixture families parse, semantic round trips pass, value modes remain distinct, recurrence/RDATE/EXDATE/EXRULE/UTC UNTIL/overrides/cancellations pass, floating expansion rejects missing `:zone-id`, unsupported components/properties/non-IANA TZIDs fail loudly, libical remains planned, no libical source is added, and docs cover API/support/non-goals/validation.

- [ ] **Step 9: Commit any reviewed validation fixes**

  Only if Task 8 required changes:

  ```bash
  git add assets/lua/temporal.fnl assets/lua/temporal/ics.fnl assets/lua/temporal/ics assets/lua/tests/test-temporal-ics.fnl assets/lua/tests/fast.fnl assets/lua/tests/data/temporal/ics docs/dev/features/temporal-ics.md docs/dev/features/temporal.md docs/dev/features/temporal-complete-acceptance.md docs/dev/features/temporal-complete-library.md
  git commit -m "fix(assets): stabilize temporal ICS validation"
  ```

- [ ] **Step 10: Treat PR CI as the full integration gate**

  Local validation is necessary but not sufficient. The full integration gate is PR CI targeting `main`, followed by the repository merge queue when enabled.

## Self-Review Checklist and Coverage Notes

- [x] **Spec coverage:** This plan covers public `Temporal.ics` API, record shapes, supported `VCALENDAR`/`VEVENT` properties, date/time modes, metadata-only `VTIMEZONE`, recurrence composition, overrides/cancellations, canonical formatting, fixture corpus, dependency manifest policy, diagnostics, docs, and acceptance validation.
- [x] **Out-of-scope preserved:** The plan does not vendor libical, enable native `temporal_ical`, evaluate custom `VTIMEZONE` observances, support unsupported components, add timezone aliases, or introduce scheduler/localization/business-calendar behavior.
- [x] **Type consistency:** Later tasks consume the exact function names and record shapes produced by earlier tasks: `grammar.*`, `value.*`, `parser.parse-calendar`, `formatter.format-calendar`, `expand.expand-calendar`, and public `Temporal.ics.{parse,format,expand}`.
- [x] **Validation order:** Every Fennel-facing task validates with compile check first, constraints second, focused Fennel tests third; broader validation is limited to final Task 8 due public surface and fast-suite risk.
- [x] **Docs/dev requirement:** Behavior and architecture changes are documented in new `docs/dev/features/temporal-ics.md` and linked/status-updated from existing temporal docs.
- [x] **HUMAN_DECISION_REQUIRED:** None currently; the selected-corpus pure Fennel facade is fully specified. Future libical source/version/license/build choices remain out of scope for this track.
