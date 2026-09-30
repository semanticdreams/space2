# Temporal Intervals

Temporal intervals add half-open bounded interval records and repeating interval expansion above the native temporal core. They are public through `Temporal.interval` and `Temporal.repeating-interval` on `(require :temporal)`.

## Layering model

Intervals are deliberately a Fennel-facing layer, not native core userdata. The native core remains small and dependency-free: it owns temporal value comparison, exact duration arithmetic, plain date-time and zoned date-time primitives, and timezone conversion. Interval grammar, bracket-aware splitting, derived endpoint policy, repeat-prefix parsing, validation, formatting, and expansion limits stay above the core beside the other temporal facade modules.

This keeps the core independent from ISO interval grammar choices, recurrence product policy, natural-language parsing, ICS/iCalendar, ICU/CLDR, localization, business calendars, and scheduler UX. No interval API silently defaults to host-local timezone behavior.

## Half-open interval semantics

Every interval is half-open: `[start, end)`. The start is included, the end is excluded, and zero-length or reversed ranges throw.

Endpoints must have the same declared type. Track 6 supports `:instant`, `:plain-date-time`, and `:zoned-date-time` interval endpoints. `Temporal.interval.duration` returns an exact `Duration`, and `Temporal.interval.shift` moves both endpoints by an exact duration while preserving the endpoint type and half-open bounds.

```fennel
(local Temporal (require :temporal))

(local interval
  (Temporal.interval.parse "2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"
                           {:type :instant}))

(Temporal.interval.contains interval
                            (Temporal.standard.parse-instant "2026-09-25T12:00:00Z"))
; => true

(Temporal.interval.contains interval
                            (Temporal.standard.parse-instant "2026-09-25T13:00:00Z"))
; => false
```

## Supported Track 6 grammar

`Temporal.interval.parse text {:type type}` supports exactly these bounded forms:

- `start/end`
- `start/P...`
- `P.../end`
- `start/PT...`
- `PT.../end`

Parsing uses one top-level `/` outside bracketed IANA zone ids, so zoned endpoint text such as `America/New_York` does not split the interval. At least one endpoint must be concrete. Anchorless forms such as `P.../PT...`, `PT.../P...`, `P.../P...`, and `PT.../PT...` are unsupported and fail loudly.

Concrete endpoint parsing is selected by the required canonical `:type` option:

- `:instant` uses strict instant text with explicit `Z` or numeric offset.
- `:plain-date-time` uses strict plain date-time text.
- `:zoned-date-time` uses strict zoned date-time text with an explicit numeric offset and bracketed IANA zone id, for example `2026-09-25T09:00:00-04:00[America/New_York]`.

Zoned interval endpoints must name the same explicit zone id, their supplied offsets must be valid for their local times, and ordering/containment compare the resolved instants. The parser never infers a zone from the host environment and does not accept a `:zone-id` fallback option for intervals.

## Exact durations versus calendar periods

Exact duration endpoint text is `PT...` and is parsed into a nanosecond `Duration`. It is supported for `:instant`, `:plain-date-time`, and `:zoned-date-time` intervals:

```fennel
(Temporal.interval.format
  (Temporal.interval.parse "2026-09-25T12:00:00Z/PT1H"
                           {:type :instant}))
; => "2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"
```

Calendar period endpoint text is `P...` without `T` and remains separate from exact durations. Calendar periods may include years, months, weeks, and days, and are supported only for `:plain-date-time` and `:zoned-date-time` intervals. They are rejected for `:instant` intervals because `P1D` is not an exact 24-hour duration.

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

`Temporal.interval.format` always emits canonical concrete `start/end` text; it does not preserve the caller's derived endpoint spelling.

## DST policy for zoned calendar periods

Zoned calendar-period derived endpoints resolve local civil results through `Temporal.zoned-date-time.from-plain`. The optional canonical `:disambiguation` key is accepted only for zoned calendar-period endpoint parsing and defaults to `:reject`. Accepted values are `:reject`, `:earliest`, and `:latest`.

- `:reject` throws for DST gaps and overlaps.
- `:earliest` selects the earliest valid instant when the local time is ambiguous or moves forward to the first valid local time for a gap.
- `:latest` selects the latest valid instant when the local time is ambiguous or moves forward to the first valid local time for a gap.

Exact `PT...` zoned intervals use instant arithmetic and do not accept `:disambiguation`.

## Temporal.repeating-interval

`Temporal.repeating-interval` wraps one bounded interval with an ISO-style repeat prefix. `R<count>` means the total number of occurrences returned. `R/` creates an unbounded repeating interval record, but expansion requires a canonical positive integer `{:limit n}` option.

- `Temporal.repeating-interval.from {:interval interval :count count :step-kind kind :step step}` builds a repeating interval record. `:count` may be omitted for an unbounded record. Existing records without explicit step metadata remain valid and expand by the interval's exact duration.
- `Temporal.repeating-interval.parse text {:type type}` parses `R<count>/...` or `R/...`, delegating the bounded interval portion to `Temporal.interval.parse` and preserving derived endpoint step metadata.
- `Temporal.repeating-interval.format repeating` returns canonical repeat text.
- `Temporal.repeating-interval.occurrences repeating options` returns concrete half-open intervals. If both record `:count` and `{:limit n}` are present, expansion returns the smaller number.

Repeating intervals preserve the parsed step semantics:

- Concrete `start/end` and exact `PT...` endpoint forms use `:step-kind :exact-duration`; each occurrence advances by exact elapsed duration.
- Calendar `P...` endpoint forms use `:step-kind :calendar-period`; each occurrence advances local endpoint fields by the calendar period. For zoned date-times, occurrence expansion resolves shifted local fields with `:disambiguation`, defaulting to `:reject`.

```fennel
(local repeating
  (Temporal.repeating-interval.parse
    "R2/2026-01-31T10:00:00/P1M"
    {:type :plain-date-time}))

(Temporal.interval.format
  (. (Temporal.repeating-interval.occurrences repeating {}) 2))
; => "2026-02-28T10:00:00/2026-03-28T10:00:00"
```

## Unsupported forms and non-goals

The Track 6 interval layer is intentionally not exhaustive ISO 8601-1/-2 conformance. Unsupported grammar and invalid temporal data fail loudly instead of being guessed. Out-of-scope forms include:

- native interval userdata in the C++ temporal core.
- open intervals and anchorless interval expansion.
- date-only or all-day intervals.
- week-date or ordinal-date endpoints.
- offset-only zoned intervals and host-local or implicit UTC zone fallback.
- non-Gregorian calendars, business-day intervals, natural-language intervals, localization, ICS/VEVENT/VTIMEZONE parsing, scheduler behavior, and interval algebra.
- option-key aliases or compatibility shims beyond the documented canonical keys.

## Validation

For interval behavior changes, validate the Fennel surface with the project-native compile check, constraints, focused temporal interval tests, and broader suite when public parsing/repeating behavior changed:

```bash
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-intervals:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```
