# Temporal RRULE BYMONTH Design

## Summary

This slice adds bounded RRULE `BYMONTH` support to `Temporal.recurrence` as the
first RFC5545 maturity step after monthly/yearly recurrence expansion.
`BYMONTH` will parse, normalize, serialize, and filter occurrence expansion for
the existing supported frequencies.

The scope is intentionally narrow. `BYMONTH` is an inclusion filter over the
candidate stream that Space already generates for `DAILY`, `WEEKLY`, `MONTHLY`,
and `YEARLY` rules. This slice does not introduce full RFC5545 candidate-set
generation, additional yearly months, `BYMONTHDAY`, `BYSETPOS`, `WKST`,
`RDATE`, `EXDATE`, or timezone-aware recurrence.

## Goals

- Add canonical recurrence option key `:by-month`.
- Parse RRULE `BYMONTH=<month-list>` where each month is an integer `1..12`.
- Serialize normalized `:by-month` values as `BYMONTH=1,3,12`.
- Validate malformed, empty, non-integer, and out-of-range month values loudly.
- Apply `BYMONTH` as a bounded inclusion filter during occurrence expansion.
- Preserve existing `FREQ`, `INTERVAL`, `COUNT`, `UNTIL`, and `BYDAY` behavior.
- Preserve monthly/yearly anchor-based `Temporal.period` expansion semantics.
- Avoid unbounded scans for unsatisfiable filters.
- Document the supported `BYMONTH` subset and the remaining RFC5545 boundaries.

## Non-Goals

- Full RFC5545 recurrence semantics.
- `BYMONTHDAY`, `BYSETPOS`, `WKST`, `RDATE`, `EXDATE`, `BYWEEKNO`, or ordinal
  `BYDAY` support.
- Timezone-aware `DTSTART` or DST-aware recurrence.
- Making `UNTIL` an expansion bound.
- Changing monthly/yearly `BYDAY` rejection.
- Changing `YEARLY+BYMONTH` into generator semantics that creates additional
  months inside each year.
- C++ temporal core changes.
- Public recurrence-set APIs.

## Current Behavior

`Temporal.recurrence` currently accepts only `:freq`, `:interval`, `:count`,
`:until`, and `:by-day` as canonical options. RRULE parsing accepts `FREQ`,
`INTERVAL`, `COUNT`, `UNTIL`, and `BYDAY`. Unknown options and unknown RRULE keys
throw.

Occurrence expansion supports bounded daily, weekly, monthly, and yearly rules.
Daily and weekly rules can use `BYDAY`. Monthly and yearly rules are
anchor-based from the original `dtstart` through `Temporal.period` arithmetic and
reject `BYDAY` during expansion. `UNTIL` parses and serializes but does not bound
expansion.

## Design

### Normalized rule shape

`Temporal.recurrence.from` will accept `:by-month` as a canonical option:

```fennel
{:freq :monthly
 :interval 1
 :count 3
 :by-month [1 3 5]}
```

Validation rules:

- `:by-month` must be a table when present.
- The table must be non-empty.
- Each value must be an integer in `1..12`.
- Values are preserved in caller-provided order; this slice does not deduplicate
  or sort.

RRULE parsing accepts `BYMONTH=1,3,12` and rejects empty members such as
`BYMONTH=1,,2`, non-numeric members such as `BYMONTH=JAN`, and out-of-range
members such as `0` or `13`.

RRULE serialization emits `BYMONTH` after `UNTIL` and before `BYDAY`, preserving
the normalized list order.

### Occurrence semantics

`BYMONTH` is an inclusion filter over the existing candidate stream:

- Daily candidates are the same dates produced by the current daily rule stream,
  then filtered by candidate month.
- Weekly candidates are the same interval-selected weekly candidates produced by
  the current weekly rule stream, then filtered by candidate month.
- Monthly candidates remain anchor-based month offsets from `dtstart`, then
  filtered by candidate month.
- Yearly candidates remain anchor-based year offsets from `dtstart`, then
  filtered by candidate month.

`COUNT` and `options.limit` count returned occurrences after filtering, as users
expect from RRULE selectors. If both are present, the smaller returned-occurrence
bound is used. If neither is present, expansion still throws.

`YEARLY+BYMONTH` intentionally does not generate additional months in each year.
For example, a yearly rule anchored in February with `BYMONTH=3` is unsatisfiable
in this slice and throws instead of producing March occurrences.

### Unsatisfiable filter safety

Filtering can otherwise create unbounded searches. Expansion must detect obvious
unsatisfiable bounded cycles and throw `unsupported temporal recurrence
expansion` instead of hanging:

- Daily filters check one Gregorian 400-year day cycle for the current interval
  step and active filters.
- Weekly filters check one Gregorian 400-year week cycle for the current interval
  step, current weekly weekday semantics, and active filters.
- Monthly filters check the month cycle `12 / gcd(interval, 12)`.
- Yearly filters check the anchored `dtstart` month.

This keeps the slice deterministic without introducing full RFC5545 candidate-set
machinery.

## Alternatives Considered

### A. Inclusion filter over existing candidate streams — chosen

This is the smallest useful `BYMONTH` slice. It composes with current daily,
weekly, monthly, and yearly expansion behavior while preserving existing anchor
semantics and bounded safeguards.

### B. Full generator semantics for yearly `BYMONTH`

This would align more closely with full RFC5545 for `YEARLY+BYMONTH`, but it
requires candidate-set expansion, ordering, duplicate handling, future
interaction with `BYMONTHDAY`/`BYSETPOS`, and explicit day-clamping policy. That
belongs in a later RFC5545 candidate-set slice.

### C. Parse/serialize only

Parse-only support would avoid occurrence complexity but would be less useful and
would create another accepted-but-unexpandable RRULE path. The selected bounded
filter semantics provide real behavior while staying explicit about limits.

## Error Handling

- Unknown RRULE keys other than the newly supported `BYMONTH` still throw.
- Invalid `BYMONTH` values throw during parsing or normalization.
- Monthly/yearly `BYDAY` still throws during occurrence expansion, including when
  `BYMONTH` is present.
- Unsatisfiable `BYMONTH` filters throw `unsupported temporal recurrence
  expansion` instead of looping indefinitely.
- `UNTIL` remains parse/serialize-only and does not affect expansion.

## Testing

Focused Fennel tests in `assets/lua/tests/test-temporal-parsing-recurrence.fnl`
will cover:

- `BYMONTH` parse/serialize round trip.
- Programmatic `:by-month` normalization.
- Invalid RRULE and programmatic month values.
- Daily filtering into a later allowed month.
- Weekly filtering with `BYDAY` and `BYMONTH`.
- Monthly anchor stream filtering.
- Yearly anchor stream filtering.
- Unsatisfiable yearly `BYMONTH` filter rejection.
- Monthly/yearly `BYDAY` rejection still winning when `BYMONTH` is present.

Validation order:

1. Touched-file `tools.fennel-check` for recurrence and recurrence tests.
2. `make constraints`.
3. Focused `tests.test-temporal-parsing-recurrence:main`.
4. PR CI remains the full integration gate.

## Documentation

Update `docs/dev/features/temporal-parsing-recurrence.md` to state:

- The bounded RRULE subset supports `BYMONTH`.
- `BYMONTH` accepts integer months `1..12`.
- `BYMONTH` acts as an inclusion filter over existing candidate streams.
- `YEARLY+BYMONTH` does not generate additional months in this slice.
- Full RFC5545 candidate-set expansion and remaining selectors are deferred.

## Acceptance Criteria

- `RRULE:FREQ=YEARLY;COUNT=2;BYMONTH=1,3,12` parses and serializes with
  `:by-month [1 3 12]`.
- Invalid `BYMONTH` values throw loudly.
- Daily, weekly, monthly, and yearly occurrence expansion can filter by month.
- Unsatisfiable month filters throw instead of hanging.
- Existing daily/weekly/monthly/yearly behavior without `BYMONTH` remains
  unchanged.
- No C++ changes or full RFC5545 candidate-set machinery are introduced.
