# Temporal ICS/iCalendar Interoperability Design

## Context

The temporal roadmap has landed provider registry, standalone RFC5545 recurrence,
recurrence sets with explicit-zone expansion, and full selected ISO intervals.
The next ordered track is ICS/iCalendar interoperability. Prior tracks built the
semantic primitives that ICS should normalize into: `Temporal.recurrence`,
`Temporal.recurrence-set`, `Temporal.interval`, `Temporal.repeating-interval`,
`Temporal.standard`, and core `Instant`, `PlainDateTime`, and `ZonedDateTime`.

The dependency/data foundation reserved a future `temporal_ical` adapter and a
`libical` manifest, but no source has been selected or vendored. This track
therefore establishes the public `Temporal.ics` API and finite production corpus
as a Fennel facade first. `libical` remains the future conformance-expansion gate
for arbitrary custom `VTIMEZONE` observance evaluation, Windows timezone aliases,
broader component coverage, or client-specific quirks that exceed this selected
corpus.

The design preserves temporal invariants:

- no host-local timezone defaults;
- exact `Duration` remains nanoseconds-only;
- all-day/date-only values remain calendar concepts, not exact durations;
- native temporal core remains independent from ICS grammar, providers,
  localization, business calendars, and scheduler policy;
- runtime ICS parsing/export does not fetch network data;
- canonical option keys only;
- unsupported components/properties/timezone semantics fail loudly.

## Goals

- Add a public `Temporal.ics` namespace for parsing, formatting, and expanding a
  selected production ICS/VEVENT corpus.
- Support `VCALENDAR` and `VEVENT` records with deterministic normalized record
  shapes.
- Support timed UTC, floating, and IANA-zoned events, plus all-day date-only
  events.
- Support `DTSTART`, `DTEND`, `DURATION`, `RRULE`, `RDATE`, `EXDATE`, `EXRULE`,
  `UID`, `SUMMARY`, `DESCRIPTION`, `STATUS`, `SEQUENCE`, and `RECURRENCE-ID`.
- Parse `VTIMEZONE` declarations as metadata for selected fixtures while using
  explicit IANA `TZID` values and Space tzdb for actual zone resolution.
- Compose recurrence properties into existing recurrence-set behavior.
- Support recurrence overrides and cancellations by `UID` and normalized
  `RECURRENCE-ID`.
- Export canonical ICS text with deterministic property order, escaping, line
  folding, and CRLF line endings by default.
- Provide focused fixtures and docs so the acceptance matrix can treat this track
  as complete after local validation and PR CI pass.

## Non-goals

- Do not claim arbitrary/full RFC5545 or client-quirk conformance beyond the
  selected supported corpus.
- Do not vendor libical or enable `SPACE_TEMPORAL_ENABLE_ICAL_ADAPTER` in this
  track.
- Do not evaluate arbitrary custom `VTIMEZONE` STANDARD/DAYLIGHT observance rules
  in Fennel.
- Do not support Windows/non-IANA timezone aliases, host-local timezone fallback,
  or implicit UTC fallback.
- Do not implement `VALARM`, `VTODO`, `VJOURNAL`, `VFREEBUSY`, attendee/organizer
  scheduling workflow, location/geographic metadata, attachments, categories,
  URL handling, alarms, or calendar-server semantics.
- Do not add localization, non-Gregorian calendars, business calendars,
  natural-language parsing, timestamp migrations, scheduler behavior, or interval
  algebra.
- Do not treat all-day/date-only values as exact nanosecond intervals.

## Considered approaches

### Approach A: Native libical adapter now

This is rejected for this track. A native adapter is the likely long-term path for
broader RFC5545 and client conformance, but the exact version, source URL,
checksum, license compliance path, build strategy, runtime data mode, and binding
shape are not yet selected. Importing libical before proving Space's public
record/API shape would add build and memory-management risk and may duplicate the
recurrence and interval semantics already implemented in Fennel.

### Approach B: Pure Fennel `Temporal.ics` facade

This is selected. It keeps ICS grammar and product policy above the native core,
composes existing recurrence/interval/zoned primitives, and supports a finite
production corpus with loud failures outside that corpus. It also keeps the
libical manifest honest: `planned`, not pseudo-integrated.

### Approach C: Native no-op adapter plus Fennel facade

This is rejected. A no-op `temporal_ical` adapter would add surface area without
behavior and risks locking in a binding shape before the real dependency is
chosen. Throwing native stubs provide no value over Fennel loud failures.

## Public API

Add `Temporal.ics` with these functions:

```fennel
(Temporal.ics.parse text {:unknown-property-policy :reject})
(Temporal.ics.format calendar {:line-ending :crlf})
(Temporal.ics.expand calendar {:zone-id "America/New_York"
                               :disambiguation :reject
                               :limit 100})
```

Canonical option keys:

- `:unknown-property-policy` — parse option; `:reject` default, `:preserve`
  allowed only for unsupported `X-...` properties retained as metadata.
- `:line-ending` — format option; `:crlf` default, `:lf` allowed for focused
  tests.
- `:zone-id` — expand option required for floating event expansion.
- `:disambiguation` — expand option for floating/zoned local resolution;
  accepted values are `:reject`, `:earliest`, and `:latest`; default `:reject`.
- `:limit` — expand option required when any active recurrence is unbounded.

Unknown option keys throw. No aliases such as `:timezone`, `:tz`, `:ics-text`, or
`:ical` are accepted.

## Record shapes

### Calendar records

Parsed calendars are plain Fennel records:

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

`VERSION:2.0` is required. `CALSCALE` defaults to `GREGORIAN` if absent and must
be `GREGORIAN` when present. `PRODID` is preserved when present and uses the
Space value when formatting constructed records that omit it.

### Event records

```fennel
{:kind :temporal-ics-event
 :uid "event-id"
 :sequence 0
 :status :confirmed|:cancelled|:tentative
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

`UID` and `DTSTART` are required for supported events. `DTEND` and `DURATION` are
mutually exclusive. `STATUS` defaults to `:confirmed`; unsupported statuses throw.
Unknown constructed record keys throw during format/expand.

### ICS date/time values

ICS date/time values are wrappers so date-only, floating, UTC, and zoned
semantics do not collapse into host-local assumptions:

```fennel
{:kind :temporal-ics-date-time
 :value-type :date
 :date {:year 2026 :month 10 :day 1}}

{:kind :temporal-ics-date-time
 :value-type :date-time
 :time-mode :floating
 :plain <PlainDateTime>}

{:kind :temporal-ics-date-time
 :value-type :date-time
 :time-mode :utc
 :instant <Instant>}

{:kind :temporal-ics-date-time
 :value-type :date-time
 :time-mode :zoned
 :zone-id "America/New_York"
 :plain <PlainDateTime>}
```

All-day `DTEND` remains exclusive per iCalendar. Date-only expansion returns
date-shaped occurrence records, not exact-duration intervals. Floating expansion
requires caller `:zone-id` and never defaults to the host environment.

## Supported ICS grammar and properties

### VCALENDAR

Supported calendar properties/components:

- `BEGIN:VCALENDAR`
- `END:VCALENDAR`
- `VERSION:2.0`
- `PRODID`
- `CALSCALE:GREGORIAN`
- `METHOD`
- `VTIMEZONE` declarations as metadata
- `VEVENT`

Unsupported components throw under `:unknown-property-policy :reject`.

### VEVENT

Supported properties:

- `UID`
- `SUMMARY`
- `DESCRIPTION`
- `STATUS`
- `SEQUENCE`
- `DTSTART`
- `DTEND`
- `DURATION`
- `RRULE`
- `RDATE`
- `EXDATE`
- `EXRULE`
- `RECURRENCE-ID`
- `DTSTAMP` as preserved metadata only
- `X-...` properties only when `:unknown-property-policy :preserve`

Supported parser behavior:

- CRLF and LF input.
- RFC line unfolding.
- Property parameters for `VALUE=DATE` and `TZID=<IANA zone>`.
- Escaped text values for summary/description.
- Comma-separated `RDATE` and `EXDATE` values.
- Repeated recurrence/date properties.

## Timezone and VTIMEZONE policy

`TZID` values must be IANA timezone ids accepted by Space's existing tzdb-backed
zoned conversion. `VTIMEZONE` blocks are parsed as declarations and retained for
formatting/metadata in selected fixtures, but their custom observance rules are
not evaluated in this Fennel track. If an event references a non-IANA or unknown
TZID, parsing or expansion throws a loud unsupported-zone error.

Exporter behavior:

- UTC date-times export with `Z`.
- Floating date-times export without `TZID` or `Z`.
- IANA-zoned date-times export with `TZID=<zone>` parameters.
- All-day values export with `VALUE=DATE`.
- The Fennel exporter does not synthesize full custom `VTIMEZONE` observance
  blocks. Preserved declarations may be emitted for parsed calendars when they do
  not imply unsupported timezone behavior.

## Recurrence, overrides, and cancellations

Recurrence properties compose existing temporal modules:

- `RRULE` and `EXRULE` parse through `Temporal.recurrence.parse-rrule`.
- `RDATE` and `EXDATE` parse into ICS date/time wrappers matching the event value
  mode.
- Timed floating/zoned recurrence expansion uses `Temporal.recurrence-set`.
- UTC recurrence expansion filters by instant using existing recurrence-set UTC
  `UNTIL` support where applicable.
- All-day recurrence expansion returns date-shaped occurrences.

Event grouping rules:

- VEVENTs are grouped by `UID`.
- A VEVENT without `RECURRENCE-ID` is the master.
- A VEVENT with `RECURRENCE-ID` and non-cancelled `STATUS` is an override.
- A VEVENT with `RECURRENCE-ID` and `STATUS:CANCELLED` cancels that occurrence.
- A master with `STATUS:CANCELLED` yields no active occurrences.
- Override matching uses normalized recurrence-id values, not raw strings alone.
- `SEQUENCE` is preserved but does not silently discard conflicting events in this
  track; ambiguous duplicate overrides throw.

`Temporal.ics.expand` returns occurrence records:

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

For timed occurrences, implementation may include a `:zoned-interval` or
`:instant-interval` field when the endpoint mode can produce one through
`Temporal.interval`, but date-only occurrences remain date-shaped.

## Formatting and round trips

`Temporal.ics.format` emits canonical ICS for supported records:

- CRLF by default; LF only when requested for tests.
- Long lines folded deterministically.
- Stable property order: VCALENDAR header, VTIMEZONE declarations, VEVENTs,
  VCALENDAR end.
- Uppercase property names.
- Stable RRULE serialization through existing recurrence serializer.
- Escaped text for comma, semicolon, backslash, and newline.
- Exclusive all-day `DTEND` preserved.

Round-trip contract: `parse -> format -> parse` produces semantically equivalent
calendar/event records for supported fields. Byte-identical round trips are not
required.

## Fixture corpus

Initial fixtures are hand-authored production-shaped ICS snippets modeled after
common Google/Apple/Thunderbird VEVENT structures. They contain no PII and do not
depend on actual client-export license/provenance.

Required fixture families:

1. Single UTC timed VEVENT.
2. Single floating timed VEVENT.
3. Single IANA-zoned VEVENT.
4. Single-day all-day VEVENT.
5. Multi-day all-day VEVENT with exclusive `DTEND`.
6. Timed VEVENT with `DURATION:PT...`.
7. All-day VEVENT with `DURATION:P...`.
8. Weekly RRULE event.
9. RRULE plus RDATE and EXDATE.
10. EXRULE exclusion.
11. UTC `UNTIL` recurrence.
12. Recurring event with one override.
13. Recurring event with one cancelled occurrence.
14. Cancelled master event.
15. Folded lines and escaped text.
16. Unsupported custom/non-IANA TZID failure.
17. Unsupported component/property failure under strict policy.

## Dependency manifest treatment

For this track:

- Keep `external/temporal/libical/DEPENDENCY_MANIFEST.json` at
  `"status": "planned"`.
- Do not add libical source.
- Do not enable `SPACE_TEMPORAL_ENABLE_ICAL_ADAPTER`.
- Update docs to state that `Temporal.ics` is a selected-corpus Fennel facade and
  libical remains the future conformance-expansion gate.

If later work requires custom `VTIMEZONE`, Windows TZID mapping, broader
component support, or conformance comparison, that later track must update the
manifest to `vendored` with exact version, source, license, checksum, and
validation evidence.

## Diagnostics

Errors must identify the rejected component/property/parameter where practical.
Loud failures are required for:

- missing `VERSION:2.0`;
- unsupported `CALSCALE`;
- unsupported components;
- unknown properties under strict policy;
- missing `UID` or `DTSTART`;
- both `DTEND` and `DURATION` on one event;
- malformed content lines or parameters;
- invalid escaped text;
- invalid date/date-time values;
- non-IANA or unknown `TZID`;
- unsupported custom `VTIMEZONE` observance evaluation;
- invalid recurrence rules/dates;
- unbounded recurrence expansion without `:limit`;
- duplicate masters or ambiguous duplicate overrides.

## Documentation and acceptance

Add or update developer documentation for `Temporal.ics`, including API examples,
supported properties, value modes, expansion behavior, VTIMEZONE limits,
round-trip guarantees, and non-goals.

Update `docs/dev/features/temporal-complete-acceptance.md` with fixture,
round-trip, override/cancellation, invalid-input, focused-suite, and PR CI
evidence. Update `docs/dev/features/temporal-complete-library.md` status after
implementation lands.

## Testing strategy

- Add focused Fennel tests for parsing, formatting, semantic round trips, and
  expansion across every fixture family.
- Register the focused ICS suite in the fast tests.
- Preserve existing recurrence-set, recurrence, interval, and natural tests.
- Add strict failure tests for unsupported components/properties/TZIDs and
  invalid event shapes.
- Validate dependency manifests still pass with libical planned and no source
  import.
- Run Space Fennel validation ladder: compile check, constraints, focused ICS
  tests, adjacent recurrence/recurrence-set/interval tests where touched, and
  broader suite when finishing.

## Acceptance criteria

- `Temporal.ics.parse`, `Temporal.ics.format`, and `Temporal.ics.expand` are
  exported from the public temporal facade.
- Supported VCALENDAR/VEVENT fixtures parse into deterministic records.
- Supported records export to canonical ICS and parse back to semantically
  equivalent records.
- UTC, floating, IANA-zoned, and all-day events retain distinct value semantics.
- Recurrence, RDATE/EXDATE/EXRULE, overrides, cancellations, and cancelled master
  behavior match this spec.
- Floating expansion requires explicit caller `:zone-id`; no host-local defaults
  are introduced.
- Unsupported components/properties/timezones/VTIMEZONE semantics fail loudly.
- Libical remains planned with no source import in this track.
- Focused ICS tests, compile checks, constraints, broader validation, PR CI, and
  merge queue pass.
