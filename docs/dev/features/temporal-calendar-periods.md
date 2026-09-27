# Temporal Calendar Periods

Temporal calendar periods add bounded ISO proleptic Gregorian civil date arithmetic above the native temporal core. They are public through `Temporal.period` on `(require :temporal)` and cover date-based period records with years, months, weeks, and days.

## Layering model

Calendar periods are Fennel-facing records, not native C++ userdata. The native core continues to own correctness-critical temporal primitives and exact `PlainDateTime` calendar addition, while the public Fennel layer owns period record construction, date-only ISO-like parsing and formatting, validation policy, and dispatch to plain-date-time arithmetic.

This keeps exact elapsed time separate from calendar math: `Duration` remains nanoseconds-only, and period APIs do not add calendar units to `Temporal.duration`. No period API silently defaults to host-local timezone behavior.

## Calendar arithmetic policy

Calendar periods apply only to `PlainDateTime` in this slice. Adding a period combines `:years` and `:months` into one total-month shift, clamps the day-of-month once, then adds `:weeks` and `:days`. The time-of-day and nanoseconds are preserved.

Examples:

```fennel
(local Temporal (require :temporal))

(local jan31 (Temporal.plain-date-time.parse "2026-01-31T10:11:12"))
(local plus-month
  (Temporal.period.add-to-plain-date-time jan31 (Temporal.period.parse "P1M")))
(plus-month:to-string) ; => "2026-02-28T10:11:12"

(local minus-month
  (Temporal.period.subtract-from-plain-date-time jan31 (Temporal.period.parse "P1M")))
(minus-month:to-string) ; => "2025-12-31T10:11:12"
```

## Temporal.period

`Temporal.period` creates, parses, formats, negates, and applies bounded calendar period records.

- `Temporal.period.from {:years y :months m :weeks w :days d}` builds a record with `:kind :period` after validating canonical field names and integer field values.
- `Temporal.period.parse text` accepts date-only ISO-like period text such as `P1Y2M3W4D`, `P0D`, and `-P1M`.
- `Temporal.period.format period` returns canonical date-only period text.
- `Temporal.period.negate period` returns a period with all non-zero fields negated.
- `Temporal.period.add-to-plain-date-time plain period` applies the calendar arithmetic policy above.
- `Temporal.period.subtract-from-plain-date-time plain period` applies the negated period.

```fennel
(local p (Temporal.period.from {:years 1 :months 2 :weeks 3 :days 4}))
(Temporal.period.format p) ; => "P1Y2M3W4D"

(Temporal.period.format (Temporal.period.parse "P0D")) ; => "P0D"
(Temporal.period.format (Temporal.period.negate p)) ; => "-P1Y2M3W4D"
```

`Temporal.recurrence.occurrences` reuses `Temporal.period.add-to-plain-date-time` for bounded plain-date-time monthly and yearly expansion. Full RFC5545 selectors, timezone-aware recurrence, and DST-aware recurrence remain deferred.

## Unsupported forms and deferred scope

Current APIs fail loudly for unsupported forms. Deferred scope includes:

- native Period userdata in the C++ temporal core.
- Instant/ZonedDateTime period arithmetic, including ZonedDateTime period expansion.
- DST-aware arithmetic and timezone-aware period arithmetic.
- Date-only `start/period` and `period/end` endpoint forms are supported only by `Temporal.interval.parse` for plain date-times. Repeating interval period endpoints, instant period endpoints, zoned interval period endpoints, time-based `PT...` period text, and full ISO interval grammar beyond those two plain date-time forms remain deferred.
- `Period.between` and calendar diffing.
- time-based fields such as hours, minutes, seconds, milliseconds, microseconds, or nanoseconds.
- non-Gregorian calendars.
- localization, ICU/CLDR formatting, business calendars, and holiday calendars.

These deferrals preserve the boundary between exact elapsed time, civil calendar periods, intervals, recurrence policy, and product-specific scheduling semantics.

## Validation

For docs-only calendar period changes, run the focused term check from the implementation plan:

```bash
rg "start/period|period/end|Temporal.period|repeating interval period endpoint|instant period endpoint|Temporal.interval.parse" docs/dev/features/temporal-intervals.md docs/dev/features/temporal-calendar-periods.md docs/dev/features/temporal-parsing-recurrence.md
```

If period behavior changes, validate the Fennel surface with the project-native compile check, constraints, and focused temporal period tests in that order.
