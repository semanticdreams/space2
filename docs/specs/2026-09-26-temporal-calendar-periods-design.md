# Temporal Calendar Periods Design

## Context

Space now has exact temporal primitives, strict parsing/formatting facades,
recurrence records, structured temporal expressions, half-open intervals, and
bounded repeating intervals. Exact `Duration` remains elapsed nanoseconds. The
next foundational gap is civil calendar periods such as one month, one year, or
two weeks.

Calendar periods are not exact elapsed durations. Adding one month depends on the
starting civil date and an explicit end-of-month policy. Space needs this model
before implementing full ISO interval duration endpoints, monthly/yearly
recurrence expansion, or broader natural-language date ranges.

## Goals

- Add a bounded calendar `Period` layer for ISO proleptic Gregorian civil date
  arithmetic.
- Keep exact `Duration` nanoseconds-only and unchanged.
- Keep public period records in Fennel while using native helpers for
  correctness-critical civil arithmetic on `PlainDateTime`.
- Support canonical period fields `:years`, `:months`, `:weeks`, and `:days`.
- Support date-only ISO-like parsing and formatting such as `P1Y2M3W4D`, `P0D`,
  and `-P1M`.
- Apply periods only to `PlainDateTime` in this slice.
- Make all invalid or unsupported forms fail loudly.
- Preserve all existing temporal APIs and behavior.

## Non-goals for this slice

- Do not add native C++ `Period` userdata.
- Do not add calendar units to exact `Duration`.
- Do not apply periods to `Instant` or `ZonedDateTime`.
- Do not add DST-aware or timezone-aware period arithmetic.
- Do not implement monthly/yearly recurrence expansion.
- Do not implement ISO interval `duration/start`, `start/duration`, or
  `duration/end` forms.
- Do not implement `Period.between` or calendar diffing.
- Do not add time-based period fields such as hours, minutes, seconds, or
  nanoseconds.
- Do not add non-Gregorian calendars, localization, business calendars, holiday
  calendars, ICU, CLDR, or new third-party runtime dependencies.

## Considered approaches

### Approach A: Native `Period` userdata

Implement a native C++ `Period` value type and expose it through `temporal-core`.

This gives strong native type boundaries but expands core API surface before the
project has designed full period semantics, period differences, recurrence
integration, or zoned period behavior. It also risks blurring the existing
boundary where public syntax and facade policy live in Fennel.

### Approach B: Fennel-only period records

Represent periods entirely in Fennel and implement all civil arithmetic in
Fennel code.

This keeps the native core untouched, but end-of-month clamping and local-date
range checks are correctness-critical. Duplicating that arithmetic outside the
native temporal core would be fragile and harder to test against existing civil
validation behavior.

### Approach C: Fennel records with native civil helper

Add a small native `PlainDateTime` civil-calendar helper, then expose public
period records and parsing/formatting in Fennel.

This matches the interval slice's hybrid pattern. Native code owns Gregorian
calendar arithmetic and range checks. Fennel owns public records, ISO-like text,
validation policy, and documentation.

## Decision

Use Approach C.

The native temporal core gains one dependency-free semantic helper:

```cpp
PlainDateTime PlainDateTime::add_calendar(std::int64_t years,
                                          std::int64_t months,
                                          std::int64_t weeks,
                                          std::int64_t days) const;
```

The Fennel layer gains one public namespace:

```fennel
Temporal.period
```

No native `Period` userdata is introduced. Exact `Duration` behavior remains
unchanged.

## Calendar arithmetic policy

Period addition to `PlainDateTime` follows this deterministic order:

1. Combine `years` and `months` into one total-month shift.
2. Apply the total-month shift to the civil year/month.
3. Clamp the day-of-month once to the last valid day in the target month.
4. Add `weeks * 7 + days` as calendar days after month/year clamping.
5. Preserve hour, minute, second, and nanosecond fields.
6. Throw on arithmetic overflow or out-of-range local date-time.

Required examples:

```text
2026-01-31T10:11:12 + P1M => 2026-02-28T10:11:12
2028-01-31T10:11:12 + P1M => 2028-02-29T10:11:12
2028-02-29T10:11:12 + P1Y => 2029-02-28T10:11:12
2026-01-31T10:11:12 + P2M => 2026-03-31T10:11:12
2026-03-31T10:11:12 - P1M => 2026-02-28T10:11:12
```

This policy avoids iterative month-by-month clamping surprises. For example,
`2026-01-31 + P2M` becomes `2026-03-31`, not `2026-03-28`.

## Public API direction

Existing temporal namespaces keep their current names and behavior. The new
public namespace is:

```fennel
Temporal.period.from
Temporal.period.parse
Temporal.period.format
Temporal.period.negate
Temporal.period.add-to-plain-date-time
Temporal.period.subtract-from-plain-date-time
```

Period record shape:

```fennel
{:kind :period
 :years integer
 :months integer
 :weeks integer
 :days integer}
```

`Temporal.period.from` accepts only canonical keys `:years`, `:months`,
`:weeks`, and `:days`. Missing fields default to `0`. Values must be finite
integers. Mixed-sign public periods are rejected so formatting and arithmetic
stay easy to reason about. A zero period is valid.

`Temporal.period.parse` supports date-only ISO-like period text:

```text
P0D
P1Y
P1Y2M3W4D
-P1M
```

It rejects empty `P`, time components such as `PT1H`, fractional fields,
reordered fields, unknown suffixes, embedded signs, and mixed-sign text.

`Temporal.period.format` emits date-only ISO-like text. Zero formats as `P0D`.
Negative periods use one leading `-`.

## Error handling

Errors must be explicit and loud for:

- missing or non-table options;
- unknown period keys;
- non-integer, infinite, or NaN values;
- mixed signs among nonzero fields;
- invalid period text;
- unsupported time-based period fields;
- applying periods to anything other than `PlainDateTime`;
- native calendar arithmetic overflow or out-of-range results.

No API may silently default to host-local timezone behavior.

## Documentation updates

Add `docs/dev/features/temporal-calendar-periods.md` and link it from temporal
feature docs. Existing interval and recurrence docs should explain that calendar
period arithmetic now exists, but full ISO interval duration endpoint forms and
monthly/yearly recurrence expansion remain separate deferred slices.

## Validation expectations

Because this slice touches native temporal arithmetic, Lua bindings, public
Fennel APIs, fast-suite registration, and docs, validation must include:

- `make build` after native edits;
- focused native temporal core and Lua binding CTests;
- touched-file Fennel compile check;
- `make constraints` after Fennel compile check;
- focused Fennel period tests;
- full `make test` before finishing.

Direct Fennel test runs must use the project-native runtime and paths documented
in `AGENTS.md`; system `fennel` and system `lua` are not validation oracles.

## Acceptance criteria

- `require :temporal` exposes a `period` namespace.
- Exact `Duration` remains nanoseconds-only, and `Temporal.duration.from
  {:months 1}` still throws.
- `Temporal.period.from`, `parse`, `format`, and `negate` handle canonical
  date-based periods.
- `Temporal.period.add-to-plain-date-time` and `subtract-from-plain-date-time`
  apply the documented calendar arithmetic policy.
- Invalid or unsupported period forms throw loudly.
- Existing interval, recurrence, parsing, and core temporal APIs remain
  compatible.
- Docs clearly state supported behavior and deferred continuation paths.
- Focused and broad validation pass.
