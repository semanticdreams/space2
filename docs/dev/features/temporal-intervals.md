# Temporal Intervals

Temporal intervals add half-open bounded interval records and bounded repeating interval expansion above the native temporal core. They are public through `Temporal.interval` and `Temporal.repeating-interval` on `(require :temporal)`.

## Layering model

Intervals are deliberately a Fennel-facing layer, not native core userdata. The native core remains small and dependency-free: it owns temporal value comparison and exact `PlainDateTime`/`Instant` duration arithmetic. Interval parsing, interval records, repeat-prefix parsing, validation policy, formatting, and expansion limits stay above the core beside the other temporal facade modules.

This keeps the core independent from ISO interval grammar choices, recurrence product policy, natural-language parsing, ICU/CLDR, localization, and scheduler UX. No interval API silently defaults to host-local timezone behavior.

## Half-open interval semantics

Every interval is half-open: `[start, end)`. The start is included, the end is excluded, and zero-length or reversed ranges throw.

Endpoints must have the same declared type. The initial slice supports only `:instant` and `:plain-date-time` intervals; mixed endpoints and unsupported endpoint types throw. `Temporal.interval.duration` returns an exact `Duration`, and `Temporal.interval.shift` moves both endpoints by an exact duration while preserving the endpoint type and half-open bounds.

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

## Temporal.interval

`Temporal.interval` creates, parses, formats, measures, checks, and shifts bounded start/end intervals.

- `Temporal.interval.from {:type type :start start :end end}` builds a record with `:kind :interval` and `:bounds :half-open` after validating endpoint type and ordering.
- `Temporal.interval.parse text {:type type}` accepts only `start/end` text. `:instant` endpoints use `Temporal.standard.parse-instant`; `:plain-date-time` endpoints use `Temporal.standard.parse-plain-date-time`.
- `Temporal.interval.format interval` returns canonical `start/end` text.
- `Temporal.interval.duration interval` returns the exact elapsed `Duration` from start to end.
- `Temporal.interval.contains interval value` applies half-open containment.
- `Temporal.interval.shift interval duration` returns a new half-open interval shifted by the exact duration.

```fennel
(local meeting
  (Temporal.interval.parse "2026-09-25T12:00:00/2026-09-25T13:00:00"
                           {:type :plain-date-time}))

((Temporal.interval.duration meeting):to-string) ; => "PT1H"

(local later
  (Temporal.interval.shift meeting (Temporal.duration.from {:seconds 7200})))

(Temporal.interval.format later)
; => "2026-09-25T14:00:00/2026-09-25T15:00:00"
```

## Temporal.repeating-interval

`Temporal.repeating-interval` wraps one bounded interval with an ISO-style repeat prefix. `R<count>` means the total number of occurrences returned. `R/` creates an unbounded repeating interval record, but expansion requires a canonical positive integer `{:limit n}` option.

- `Temporal.repeating-interval.from {:interval interval :count count}` builds a repeating interval record. `:count` may be omitted for an unbounded record.
- `Temporal.repeating-interval.parse text {:type type}` parses `R<count>/start/end` or `R/start/end`, delegating the bounded `start/end` portion to `Temporal.interval.parse`.
- `Temporal.repeating-interval.format repeating` returns canonical repeat text.
- `Temporal.repeating-interval.occurrences repeating options` returns concrete half-open intervals. If both record `:count` and `{:limit n}` are present, expansion returns the smaller number.

Each next occurrence starts by shifting the previous interval by its exact duration. This is exact elapsed-time expansion for `Instant` and exact plain-date-time duration expansion for `PlainDateTime`; it is not DST-aware zoned expansion.

```fennel
(local repeating
  (Temporal.repeating-interval.parse
    "R3/2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"
    {:type :instant}))

(local occurrences (Temporal.repeating-interval.occurrences repeating {}))
(Temporal.interval.format (. occurrences 2))
; => "2026-09-25T13:00:00Z/2026-09-25T14:00:00Z"

(local unbounded
  (Temporal.repeating-interval.parse
    "R/2026-09-25T12:00:00/2026-09-25T13:00:00"
    {:type :plain-date-time}))

(# (Temporal.repeating-interval.occurrences unbounded {:limit 2})) ; => 2
```

## Unsupported forms and deferred scope

The interval layer intentionally supports only bounded `start/end` intervals and bounded expansion of repeating intervals in this slice. The following remain deferred and must fail loudly when presented to current APIs:

- native interval userdata in the C++ temporal core.
- full ISO interval grammar.
- `duration/start` forms.
- `duration/end` forms.
- zoned intervals.
- DST-aware interval expansion.
- calendar periods containing years, months, business days, or locale calendars.
- Localization, ICU/CLDR formatting, and locale data.
- Broad natural-language intervals.
- interval algebra such as set operations, overlap merging, and gap queries.

These deferrals preserve the native core layering boundary and leave product-specific grammar, calendar, localization, and scheduler semantics for separately designed layers.

## Validation

For docs-only interval changes, run the focused term check required by the implementation plan:

```bash
rg "Temporal Intervals|Temporal.interval|Temporal.repeating-interval|half-open|duration/start|duration/end|zoned intervals|calendar periods|interval algebra" docs/dev/features/temporal-intervals.md docs/dev/features/temporal.md docs/dev/features/temporal-parsing-recurrence.md docs/dev/features/index.md
```

If interval behavior changes, validate the Fennel surface with the project-native compile check, constraints, and focused temporal interval tests in that order.
