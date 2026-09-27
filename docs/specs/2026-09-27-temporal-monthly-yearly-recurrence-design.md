# Temporal Monthly and Yearly Recurrence Expansion Design

## Summary

`Temporal.recurrence.occurrences` will expand bounded simple monthly and yearly
rules for plain date-time starts. The implementation will reuse existing
`Temporal.period` calendar arithmetic and keep the RRULE surface unchanged.

This is a deliberately narrow recurrence slice. It supports `FREQ=MONTHLY` and
`FREQ=YEARLY` with `INTERVAL`, `COUNT`, and `options.limit`. It does not add full
RFC5545 monthly/yearly selector semantics, timezone-aware recurrence, or `UNTIL`
bounded expansion.

## Goals

- Expand simple `:monthly` recurrence rules in `Temporal.recurrence.occurrences`.
- Expand simple `:yearly` recurrence rules in `Temporal.recurrence.occurrences`.
- Preserve existing `Temporal.recurrence.from`, `parse-rrule`, and `to-rrule`
  public behavior.
- Reuse `Temporal.period.add-to-plain-date-time` for calendar arithmetic.
- Preserve `dtstart` time-of-day in monthly/yearly occurrences.
- Keep expansion bounded by `rule.count`, `options.limit`, or the smaller of both.
- Reject monthly/yearly `BYDAY` during occurrence expansion.
- Document which monthly/yearly recurrence behavior is now supported and which
  RFC5545 features remain deferred.

## Non-Goals

- Full RFC5545 monthly/yearly selector support.
- `BYMONTH`, `BYMONTHDAY`, ordinal `BYDAY`, `BYSETPOS`, week-number, or
  set-position support.
- Applying `BYDAY` filters to monthly/yearly expansion.
- Making `UNTIL` an expansion bound.
- Timezone-aware or DST-aware recurrence.
- Recurrence over `Instant` or `ZonedDateTime` values.
- C++ temporal core changes or native recurrence APIs.
- Native `Period` userdata.
- Public compatibility shims for direct `require :temporal/recurrence` or
  `require :temporal/natural` consumers outside the public `(require :temporal)`
  facade.

## Current Behavior

`Temporal.recurrence.from` already accepts `:monthly` and `:yearly` frequencies,
and RRULE parsing/serialization already round-trips `FREQ=MONTHLY` and
`FREQ=YEARLY`. However, `Temporal.recurrence.occurrences` currently throws
`unsupported temporal recurrence expansion` for monthly and yearly rules.

Daily and weekly expansion are already bounded and supported. Daily `BYDAY`
filters scan day by day, and weekly rules use either explicit `BYDAY` values or
the `dtstart` weekday as the default weekly day. This slice must not alter those
behaviors.

`Temporal.period` already implements date-based calendar arithmetic for plain
date-times through native `PlainDateTime:add-calendar`. It handles month-end and
leap-day clamping while preserving time-of-day.

## Design

### Dependency wiring

`assets/lua/temporal/recurrence.fnl` will become a factory that receives an
instantiated `Temporal.period` dependency. This follows the existing pattern used
by higher-level temporal modules that depend on sibling temporal facades, such as
`Temporal.interval`.

Because `Temporal.natural` currently requires recurrence directly, it will also
become a small factory receiving the already-instantiated recurrence module. The
public facade remains unchanged:

```fennel
(local Temporal (require :temporal))
Temporal.recurrence
Temporal.natural
```

### Monthly expansion semantics

Monthly recurrence uses anchor-based expansion from the original `dtstart`, not
iterative addition from the previous occurrence.

For occurrence index `i` starting at `0`:

```fennel
offset-months = (* i rule.interval)
occurrence = Temporal.period.add-to-plain-date-time dtstart {:months offset-months}
```

The first occurrence is exactly `dtstart`. Anchor-based expansion prevents clamp
drift after short months. For example, monthly recurrence from
`2026-01-31T10:11:12` with interval `1` produces:

- `2026-01-31T10:11:12`
- `2026-02-28T10:11:12`
- `2026-03-31T10:11:12`
- `2026-04-30T10:11:12`

### Yearly expansion semantics

Yearly recurrence is also anchor-based from the original `dtstart`.

For occurrence index `i` starting at `0`:

```fennel
offset-years = (* i rule.interval)
occurrence = Temporal.period.add-to-plain-date-time dtstart {:years offset-years}
```

Leap-day anchoring follows the same no-drift policy. For example, yearly
recurrence from `2028-02-29T10:11:12` with interval `1` and count `5` produces
February 28 for non-leap years and returns to February 29 in `2032`.

### Bounds and unsupported selectors

Monthly/yearly expansion uses the existing `occurrence-limit` behavior:

- `COUNT` only: return `COUNT` results.
- `options.limit` only: return `limit` results.
- both present: return the smaller value.
- neither present: throw.

`UNTIL` remains accepted and serialized but does not bound expansion in this
slice. This mirrors the current daily/weekly behavior and avoids mixing an
additional semantic change into the monthly/yearly slice.

Monthly/yearly rules with `BYDAY` throw `unsupported temporal recurrence
expansion`. Parsing and serialization can continue to round-trip `BYDAY`, but
expansion does not attempt partial RFC5545 monthly/yearly selector semantics.

## Alternatives Considered

### A. Recurrence factory receiving `Temporal.period` — chosen

This reuses the canonical calendar-period arithmetic and matches the dependency
injection pattern used by `Temporal.interval`. It keeps recurrence arithmetic
centralized and avoids duplicating `add-calendar` logic.

### B. Directly require period inside recurrence

`temporal/period.fnl` is a factory, not a ready public module. Directly requiring
and instantiating it inside recurrence would create a second construction path
and tighter coupling than the rest of the higher-level temporal modules use.

### C. Duplicate period arithmetic or add native recurrence helpers

Duplicating calendar arithmetic risks diverging from `Temporal.period`. Native
helpers are unnecessary because the existing period facade already delegates to
the native plain-date-time calendar helper.

## Error Handling

- Monthly/yearly expansion without `COUNT` or `options.limit` continues to throw.
- Invalid `options.limit` continues to throw through existing positive-integer
  validation.
- Monthly/yearly `BYDAY` throws `unsupported temporal recurrence expansion`.
- Unsupported future RRULE selectors remain parse-time errors because the parser
  still rejects unknown RRULE keys.
- Invalid or incompatible `dtstart` values fail through existing plain-date-time
  operations.

## Testing

Focused Fennel tests in `assets/lua/tests/test-temporal-parsing-recurrence.fnl`
will cover:

- Monthly count expansion from month-end with anchor-based clamp/no-drift.
- Yearly count expansion from leap day with anchor-based clamp/no-drift.
- Monthly `INTERVAL=2` expansion.
- Yearly expansion bounded by `options.limit` when no `COUNT` is present.
- `UNTIL` still not acting as an expansion bound.
- Monthly/yearly `BYDAY` expansion rejection.
- Existing daily, weekly, natural expression, and RRULE tests still pass.

Validation order:

1. Touched-file `tools.fennel-check` for temporal facade, recurrence, natural,
   and recurrence test files.
2. `make constraints`.
3. Focused `tests.test-temporal-parsing-recurrence:main`.
4. Broader validation during final branch finishing because the public temporal
   facade wiring changes.

## Documentation

Update:

- `docs/dev/features/temporal-parsing-recurrence.md` to describe bounded daily,
  weekly, monthly, and yearly expansion; anchor-based period arithmetic;
  time-of-day preservation; `COUNT`/`limit` bounds; `UNTIL` parse/serialize-only;
  and monthly/yearly `BYDAY` rejection.
- `docs/dev/features/temporal-calendar-periods.md` to remove blanket
  monthly/yearly recurrence deferral and explain that recurrence uses
  `Temporal.period.add-to-plain-date-time` for this slice.

## Acceptance Criteria

- `RRULE:FREQ=MONTHLY;COUNT=4` from `2026-01-31T10:11:12` yields January 31,
  February 28, March 31, and April 30 at `10:11:12`.
- `RRULE:FREQ=YEARLY;COUNT=5` from `2028-02-29T10:11:12` yields February 29,
  February 28, February 28, February 28, and February 29 at `10:11:12`.
- `INTERVAL` and `options.limit` work for monthly/yearly rules.
- `UNTIL` still round-trips but does not bound expansion.
- Monthly/yearly `BYDAY` rules throw during expansion.
- Existing daily/weekly recurrence behavior remains unchanged.
- No native C++ changes are introduced.
- Required focused and final validation pass before integration.
