# Temporal Interval Period Endpoint Forms Design

## Summary

`Temporal.interval.parse` will support the ISO-style interval endpoint forms
`start/period` and `period/end` for plain date-time intervals. The period portion
uses the existing date-only `Temporal.period` grammar and arithmetic.

This slice is intentionally narrow. It computes concrete half-open plain
date-time intervals at parse time and leaves instant intervals, repeating
interval period expansion, zoned intervals, time-based durations, and broader ISO
grammar for later slices.

## Goals

- Add `start/period` support to `Temporal.interval.parse` with
  `{:type :plain-date-time}`.
- Add `period/end` support to `Temporal.interval.parse` with
  `{:type :plain-date-time}`.
- Reuse existing `Temporal.period.parse`,
  `Temporal.period.add-to-plain-date-time`, and
  `Temporal.period.subtract-from-plain-date-time`.
- Preserve canonical interval records with concrete `:start` and `:end`
  endpoints.
- Preserve half-open range validation: the computed `:start` must be strictly
  before the computed `:end`.
- Keep `Temporal.interval.format` canonical as `start/end` after parsing a
  period endpoint form.
- Ensure repeating intervals continue to reject period endpoint forms.
- Document the supported forms and the remaining unsupported forms precisely.

## Non-Goals

- Supporting period endpoint forms for `{:type :instant}` intervals.
- Supporting zoned interval period endpoint forms.
- Supporting `Temporal.interval.from` with period records as endpoints.
- Supporting `Temporal.repeating-interval.parse` with period endpoint forms.
- Adding calendar-period-driven repeating expansion.
- Adding time-based `PT...` duration endpoint text.
- Adding a public helper for endpoint-form parsing.
- Adding native C++ interval or period APIs.
- Implementing full ISO interval grammar beyond the two plain-date-time forms.

## Current Behavior

`Temporal.interval.parse` currently accepts only `start/end` text and rejects
endpoint text beginning with `P`. It delegates endpoint parsing by explicit type:
`:instant` endpoints use `Temporal.standard.parse-instant`, and
`:plain-date-time` endpoints use `Temporal.standard.parse-plain-date-time`.

`Temporal.period` already parses date-only period records such as `P1M`, `P2W`,
`P1Y2M3W4D`, `P0D`, and forms with a leading `-`. It can add to or subtract
from plain date-times through native calendar arithmetic. It deliberately rejects
time-based `PT...` text.

`Temporal.repeating-interval.parse` delegates its interval portion to
`Temporal.interval.parse`, then expands occurrences by exact interval duration.
Allowing period endpoints through that delegation would risk implying calendar
period recurrence semantics, which are not part of this slice.

## Design

### Interval parser behavior

`Temporal.interval.parse text {:type :plain-date-time}` will classify the two
endpoint strings after splitting on the single `/` separator:

- `start/end`: parse both endpoints as plain date-times, as today.
- `start/period`: parse `start` as a plain date-time, parse `period` with
  `Temporal.period.parse`, compute `end` with
  `Temporal.period.add-to-plain-date-time start period`.
- `period/end`: parse `end` as a plain date-time, parse `period` with
  `Temporal.period.parse`, compute `start` with
  `Temporal.period.subtract-from-plain-date-time end period`.

Period endpoint detection is private to the interval parser and recognizes text
starting with `P` or `-P`. Both endpoints being period text is invalid because at
least one concrete endpoint is required to compute a concrete interval.

After endpoint resolution, `Temporal.interval.parse` will call the existing
`Temporal.interval.from` path so endpoint type checks and strict `start < end`
range validation remain centralized.

### Negative and zero periods

Negative periods remain syntactically accepted by `Temporal.period.parse`, but
the computed interval must still have `start < end`.

- `start/-P1D` computes an end before the start and throws through range
  validation.
- `-P1D/end` computes a start after the end and throws through range validation.
- `P0D` computes equal endpoints and throws as a zero-length interval.

The parser does not need a special negative-period policy beyond preserving the
central interval range invariant.

### Repeating interval boundary

`Temporal.repeating-interval.parse` will reject interval text containing period
endpoint forms before delegating to `Temporal.interval.parse`. Existing repeating
interval occurrence expansion remains exact-duration shifting based on concrete
interval start/end values.

### Public API shape

No new public functions are added. `Temporal.interval.from` remains concrete-only
and continues to require both `:start` and `:end` endpoints. Parsed period forms
produce ordinary interval records:

```fennel
{:kind :interval
 :type :plain-date-time
 :start <plain-date-time>
 :end <plain-date-time>
 :bounds :half-open}
```

## Alternatives Considered

### A. Private endpoint-form detection in `interval.fnl` — chosen

This keeps the parser behavior close to existing interval text parsing, reuses
the period API, and avoids broadening public surface. It also keeps the concrete
interval record as the only downstream shape.

### B. Broaden `Temporal.interval.from` to accept period endpoints

This would blur the boundary between concrete interval construction and text
grammar conveniences. It would also require additional option shapes and create
more ways to express the same interval. The slice does not need it.

### C. Add a public helper or native method

A helper or native binding could be useful if multiple parsers needed this
classification, but this slice has a single consumer and existing APIs already
perform the required calendar arithmetic.

## Error Handling

- Non-string interval text remains an error.
- Repeating syntax passed to `Temporal.interval.parse` remains an error.
- Text without exactly one separator remains an error.
- Empty endpoint text remains an error.
- Two period endpoints throw because one concrete date-time endpoint is required.
- Period endpoint forms with `{:type :instant}` throw loudly.
- Invalid period text propagates `Temporal.period.parse` errors.
- Computed zero-length or reversed intervals throw through existing range
  validation.
- Repeating interval period endpoint forms throw before occurrence expansion.

## Testing

Focused tests in `assets/lua/tests/test-temporal-intervals.fnl` will cover:

- `2026-01-31T10:00:00/P1M` formats canonically as
  `2026-01-31T10:00:00/2026-02-28T10:00:00`.
- `P2W/2026-02-15T09:30:00` formats canonically as
  `2026-02-01T09:30:00/2026-02-15T09:30:00`.
- Negative and zero period endpoint forms throw when they do not satisfy
  `start < end`.
- Instant interval period endpoint forms throw.
- `Temporal.interval.from` still rejects period records as endpoints.
- `Temporal.repeating-interval.parse` rejects period endpoint forms.
- Existing repeating interval occurrence tests remain unchanged.

Validation order for implementation:

1. Touched-file `tools.fennel-check` for interval, repeating interval, umbrella,
   and interval test files.
2. `make constraints`.
3. Focused `tests.test-temporal-intervals:main`.
4. Broader validation during final branch finishing if required by review or
   policy.

## Documentation

Update the canonical temporal docs to replace blanket deferred wording:

- `docs/dev/features/temporal-intervals.md` documents supported
  `start/period` and `period/end` forms for plain date-time intervals, examples,
  canonical formatting, and unsupported forms.
- `docs/dev/features/temporal-calendar-periods.md` notes that date-only periods
  can be used by `Temporal.interval.parse` for plain date-time endpoint forms.
- `docs/dev/features/temporal-parsing-recurrence.md` clarifies that repeating
  intervals and recurrence expansion still do not use period endpoint semantics.

## Acceptance Criteria

- `Temporal.interval.parse "2026-01-31T10:00:00/P1M" {:type :plain-date-time}`
  succeeds and formats as `2026-01-31T10:00:00/2026-02-28T10:00:00`.
- `Temporal.interval.parse "P2W/2026-02-15T09:30:00" {:type
  :plain-date-time}` succeeds and formats as
  `2026-02-01T09:30:00/2026-02-15T09:30:00`.
- Instant period endpoint forms throw.
- Repeating interval period endpoint forms throw.
- `Temporal.interval.from` remains concrete endpoint-only.
- No native C++ changes or new public parser helpers are introduced.
- Docs accurately identify supported and unsupported forms.
- Required focused validation passes before handoff, and final branch validation
  passes before integration.
