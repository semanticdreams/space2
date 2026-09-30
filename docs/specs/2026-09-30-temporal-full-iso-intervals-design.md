# Temporal Full ISO Intervals and Repeating Intervals Design

## Context

The temporal roadmap has landed provider registry, full standalone RFC5545
recurrence, and recurrence-set explicit-zone expansion. The next ordered track is
full ISO intervals and repeating intervals. Space already has partial
`Temporal.interval` and `Temporal.repeating-interval` Fennel facades: bounded
`start/end` intervals for `:instant` and `:plain-date-time`, plain date-time
`start/period` and `period/end` parsing, and bounded repeating expansion by
exact duration.

This track promotes that partial interval layer into the production Track 6
surface while preserving temporal invariants:

- no host-local timezone defaults;
- exact `Duration` remains nanoseconds-only;
- calendar periods remain separate from exact durations;
- native temporal core remains independent from interval grammar, recurrence,
  ICS, localization, business calendars, providers, and scheduler policy;
- canonical option keys only;
- unsupported grammar and invalid temporal data fail loudly.

## Goals

- Extend `Temporal.interval` to support Space's full selected ISO interval
  grammar for concrete `start/end`, `start/derived`, and `derived/end` forms.
- Add `:zoned-date-time` interval support using explicit bracketed IANA-zone
  endpoints and resolved-instant ordering.
- Add exact `PT...` duration endpoint forms for instant, plain date-time, and
  zoned date-time intervals.
- Keep calendar `P...` period endpoint forms separate from exact durations and
  allow them only for plain date-time and zoned date-time intervals.
- Extend `Temporal.repeating-interval` so period-derived and exact-duration
  interval forms preserve the correct repeat step semantics.
- Add DST-aware zoned interval and repeating expansion policy through explicit
  `:disambiguation`, defaulting to `:reject`.
- Preserve existing `Temporal.interval` and `Temporal.repeating-interval` API
  names and compatibility for current instant/plain start-end callers.
- Update interval docs, roadmap status, and acceptance evidence.

## Non-goals

- Do not implement exhaustive ISO 8601-1/-2 conformance beyond this selected
  production grammar.
- Do not implement open intervals, anchorless interval expansion, date-only or
  all-day intervals, week-date or ordinal-date endpoints, offset-only zoned
  intervals, non-Gregorian calendars, business-day intervals, natural-language
  intervals, ICS/VEVENT/VTIMEZONE parsing, interval algebra, localization, or
  scheduler behavior.
- Do not treat `P1D` as exact 24 hours. Calendar `P...` periods remain separate
  from exact `PT...` durations.
- Do not add host-local timezone fallback, implicit UTC fallback, or option-key
  aliases.
- Do not move interval grammar or policy into the native C++ temporal core.

## Considered approaches

### Approach A: Extend existing Fennel interval facades

This is selected. `Temporal.interval` and `Temporal.repeating-interval` are the
roadmap public surfaces. They already own interval grammar and expansion policy
above native primitives, so extending them keeps callers stable and lets future
ICS/iCalendar work target one interval record shape.

If implementation density grows, private helper modules under
`assets/lua/temporal/interval/` may be introduced, but the public namespace stays
`Temporal.interval` and `Temporal.repeating-interval`.

### Approach B: Add separate public zoned or period interval modules

This is rejected as a public API. Separate `Temporal.zoned-interval` or
`Temporal.period-interval` surfaces would fragment the roadmap, duplicate
contains/format/duration behavior, and complicate future ICS parsing. Type-
specific helpers are acceptable only as private implementation details.

### Approach C: Defer full intervals to a native adapter or library

This is rejected for Track 6. The needed behavior is Space interval grammar,
half-open policy, repeat-step semantics, and explicit DST policy. Existing native
primitives already provide instant, plain date-time, zoned date-time, timezone,
duration, and calendar-period operations. Third-party/native standards adapters
remain more appropriate for the later ICS/iCalendar track.

## Public API

Keep the existing public functions:

```fennel
(Temporal.interval.from {:type :instant|:plain-date-time|:zoned-date-time
                         :start start
                         :end end})

(Temporal.interval.parse text
  {:type :instant|:plain-date-time|:zoned-date-time
   :disambiguation :reject|:earliest|:latest})

(Temporal.interval.format interval)
(Temporal.interval.duration interval)
(Temporal.interval.contains interval value)
(Temporal.interval.shift interval duration)

(Temporal.repeating-interval.from {:interval interval
                                   :count count
                                   :step-kind :exact-duration|:calendar-period
                                   :step step})
(Temporal.repeating-interval.parse text options)
(Temporal.repeating-interval.format repeating)
(Temporal.repeating-interval.occurrences repeating options)
```

Compatibility rules:

- `:type` remains required for interval parsing and interval construction.
- `:start` and `:end` remain concrete endpoints on interval records.
- Existing records with only `:interval` and `:count` remain valid repeating
  records. They behave as exact-duration repeats using
  `Temporal.interval.duration`.
- Unknown option keys throw.
- Mixed endpoint types throw.
- Zero-length and reversed intervals throw.
- Formatting canonicalizes intervals to concrete `start/end` text; it does not
  preserve original `start/P...`, `P.../end`, `start/PT...`, or `PT.../end`
  spelling.

## Endpoint types and comparisons

Supported interval endpoint types:

| Type | Concrete parser | Comparison | Duration |
| --- | --- | --- | --- |
| `:instant` | `Temporal.standard.parse-instant` | instant compare | exact duration |
| `:plain-date-time` | `Temporal.standard.parse-plain-date-time` | plain date-time compare | exact duration between local fields |
| `:zoned-date-time` | `Temporal.standard.parse-zoned-date-time` | underlying instant compare | exact duration between instants |

Zoned interval records must use endpoints with the same explicit zone id. Zoned
formatting uses `Temporal.standard.format-zoned-date-time`, and containment
compares by resolved instant. Concrete zoned endpoint text must include an
explicit numeric offset and bracketed IANA zone id, such as:

```text
2026-11-01T01:30:00-04:00[America/New_York]
```

The parser must never infer a zone from the host environment and must not add a
`:zone-id` option for interval parsing. The zone comes from endpoint text.

## Interval grammar

### Separator parsing

Interval parsing must use one top-level `/` outside bracketed zone ids. IANA zone
names contain `/`, so the current naive slash count must be replaced by a
bracket-aware splitter.

Examples:

```text
2026-09-25T09:00:00-04:00[America/New_York]/2026-09-25T10:00:00-04:00[America/New_York]
2026-01-31T10:00:00/P1M
PT1H/2026-09-25T13:00:00Z
```

Unbalanced brackets, missing separators, empty endpoints, and multiple top-level
separators throw.

### Concrete and derived endpoint forms

Support these bounded interval forms:

- `start/end`
- `start/calendar-period`
- `calendar-period/end`
- `start/exact-duration`
- `exact-duration/end`

At least one concrete endpoint is required. `period/duration`,
`duration/period`, `period/period`, `duration/duration`, and other anchorless
forms throw.

### Calendar periods: `P...` without `T`

Calendar periods are parsed by `Temporal.period` and may include years, months,
weeks, and days. They are supported for `:plain-date-time` and
`:zoned-date-time` intervals only.

Examples:

```text
P1Y
P2M
P3W
P4D
P1Y2M3W4D
-P1M
P0D
```

Calendar periods are rejected for `:instant` intervals because they are not exact
nanosecond durations.

### Exact durations: `PT...`

Exact durations are nanosecond-only duration values and are supported for all
endpoint types. This track supports hour, minute, and second components, with
fractional seconds up to nine digits:

```text
PT1H
PT30M
PT45S
PT1H30M
PT0.5S
PT1.123456789S
-PT1H
PT0S
```

Unsupported exact-duration grammar throws, including `PT` with no fields,
fractional hours or minutes, mixed calendar/time grammar such as `P1DT2H`, and
calendar fields inside `PT...`.

## Derived endpoint semantics

### Plain date-time intervals

- `start/P...` computes `end` by adding the calendar period to `start`.
- `P.../end` computes `start` by subtracting the calendar period from `end`.
- `start/PT...` computes `end` by exact duration addition.
- `PT.../end` computes `start` by exact duration subtraction.

### Instant intervals

- `start/PT...` computes `end` by exact instant addition.
- `PT.../end` computes `start` by exact instant subtraction.
- Calendar `P...` endpoint forms throw.

### Zoned date-time intervals

For concrete `start/end`, parse both endpoints, validate offsets against their
zones, require matching zone ids, and compare by instant.

For calendar periods:

1. Parse the concrete zoned endpoint.
2. Extract its local `PlainDateTime` fields.
3. Add or subtract the calendar period in local civil time.
4. Resolve the derived local value back into the same explicit zone with
   `:disambiguation`.
5. Validate half-open ordering by instant.

For exact durations:

1. Parse the concrete zoned endpoint.
2. Add or subtract the exact duration on the endpoint's underlying instant.
3. Reproject the computed instant into the same explicit zone.
4. Validate half-open ordering by instant.

`Temporal.interval.parse` accepts `:disambiguation` only for
`:zoned-date-time` derived calendar-period endpoints. The default is `:reject`,
and accepted values are `:reject`, `:earliest`, and `:latest`. Exact-duration
derived endpoints do not use disambiguation because they move on the instant
timeline.

## Repeating interval semantics

`Temporal.repeating-interval` keeps the existing repeat prefix rules:

- `R<count>/...` returns at most `count` occurrences.
- `R/...` creates an unbounded record; expansion requires `{:limit n}`.
- If both record `:count` and expansion `:limit` are present, expansion returns
  the smaller count.

Repeating records add optional step metadata:

```fennel
{:kind :repeating-interval
 :interval first-interval
 :count count-or-nil
 :step-kind :exact-duration|:calendar-period
 :step duration-or-period}
```

Existing records without step metadata use `:exact-duration` with
`Temporal.interval.duration interval`.

### Exact-duration repeat steps

Used for `start/end`, `start/PT...`, `PT.../end`, and legacy records. Each next
occurrence shifts the previous interval by the exact duration step.

- Instant intervals add exact durations to instants.
- Plain date-time intervals add exact durations to plain date-times.
- Zoned date-time intervals add exact durations to endpoint instants and
  reproject into the interval's explicit zone.

Across DST transitions, exact-duration zoned repeats preserve elapsed time; local
wall-clock time may change.

### Calendar-period repeat steps

Used for `start/P...` and `P.../end`. Allowed only for plain date-time and zoned
date-time intervals. Each next occurrence shifts both endpoints by the calendar
period step.

- Plain intervals add the period to local endpoints.
- Zoned intervals add the period to each endpoint's local fields, then resolve
  through the same explicit zone using expansion option `:disambiguation`,
  defaulting to `:reject`.

Across DST transitions, calendar-period zoned repeats preserve local wall-clock
cadence while exact elapsed duration may vary.

For `P.../end`, the first interval is computed as `end - period` to `end`, then
expansion proceeds forward from that first concrete interval. This track does
not add backward expansion semantics.

## Diagnostics and error boundaries

Errors should name the rejected key, endpoint type, or grammar boundary where
practical. Loud failures are required for:

- unknown option keys;
- missing `:type`;
- unsupported interval types;
- mixed endpoint types;
- missing concrete anchor endpoint;
- empty endpoint text;
- zero or multiple top-level separators;
- unbalanced bracketed zone ids;
- two derived endpoints;
- calendar period endpoints for `:instant`;
- `PT...` grammar with calendar fields, fractional non-second units, or no
  fields;
- mixed `P...T...` duration grammar;
- zoned offset/zone mismatch;
- zoned interval endpoints with different zone ids;
- DST gap/overlap under `:disambiguation :reject`;
- zero-length or reversed intervals;
- unbounded repeating expansion without `:limit`.

## Documentation and acceptance

Update `docs/dev/features/temporal-intervals.md` to describe full Track 6
support, examples, supported grammar, DST policy, and remaining non-goals.

Update `docs/dev/features/temporal-parsing-recurrence.md` only where it names
interval deferred boundaries, so recurrence/interval docs agree.

Update `docs/dev/features/temporal-complete-acceptance.md` with concrete Track 6
evidence after implementation. Update `docs/dev/features/temporal-complete-library.md`
status after the PR lands.

## Testing strategy

- Preserve existing interval and repeating interval tests.
- Add focused tests for bracket-aware interval splitting with IANA zones that
  contain `/`.
- Cover zoned `start/end` parse, format, contains, duration, same-zone
  validation, and offset mismatch diagnostics.
- Cover plain, instant, and zoned `start/PT...` and `PT.../end` exact-duration
  endpoint forms, including fractional seconds and rejection of invalid duration
  grammar.
- Cover plain and zoned `start/P...` and `P.../end` calendar-period endpoint
  forms, including rejection for instant intervals.
- Cover repeating interval parsing and expansion for exact-duration and
  calendar-period step metadata.
- Cover zoned exact-duration repeat across a DST transition and zoned
  calendar-period repeat across a DST transition with `:reject`, `:earliest`, and
  `:latest` behavior.
- Run Space Fennel validation ladder: touched-file compile check, constraints,
  focused interval tests, and broader suite when finishing.

## Acceptance criteria

- `Temporal.interval` supports `:instant`, `:plain-date-time`, and
  `:zoned-date-time` concrete `start/end` intervals.
- `Temporal.interval.parse` supports selected `start/end`, `start/P...`,
  `P.../end`, `start/PT...`, and `PT.../end` grammar with canonical option keys.
- Calendar periods remain separate from exact durations; `P1D` is not accepted as
  exact 24 hours for instant intervals.
- Zoned intervals require explicit bracketed IANA zones and never use host-local
  defaults.
- DST gap/overlap handling for derived zoned calendar endpoints is governed by
  explicit `:disambiguation`, defaulting to `:reject`.
- `Temporal.repeating-interval` preserves exact-duration and calendar-period
  repeat semantics with bounded expansion and limit enforcement.
- Unsupported ISO variants, ICS, localization, business calendars, natural
  language, scheduler behavior, and interval algebra remain loud failures or
  documented non-goals.
- Focused interval tests, compile checks, constraints, broader validation, PR CI,
  and merge queue pass.
