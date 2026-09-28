# Temporal RFC5545 Recurrence Engine Design

## Context

Space's temporal roadmap now has the dependency/data packaging foundation and
`Temporal.providers` registry in place. The next scheduled track is the full
RFC5545 recurrence engine. The existing `Temporal.recurrence` facade already
parses and expands a useful bounded subset of RRULEs over `PlainDateTime`, but it
does not yet implement the full RRULE selector model required by RFC5545.

This track upgrades `Temporal.recurrence` from a patched collection of
frequency-specific loops into a production RRULE engine while preserving the
public API:

- `Temporal.recurrence.from`
- `Temporal.recurrence.parse-rrule`
- `Temporal.recurrence.to-rrule`
- `Temporal.recurrence.occurrences`

The engine remains a Fennel policy layer over Space temporal primitives. Native
temporal core types remain independent from recurrence policy, natural language,
localization, provider loading, ICS parsing, and runtime scheduling.

## Goals

- Implement full in-scope RFC5545 RRULE parsing, serialization, validation, and
  occurrence expansion for `PlainDateTime` rules.
- Support all RRULE frequencies: `SECONDLY`, `MINUTELY`, `HOURLY`, `DAILY`,
  `WEEKLY`, `MONTHLY`, and `YEARLY`.
- Support all RRULE selectors that apply to a standalone RRULE expansion:
  `INTERVAL`, `COUNT`, local/floating `UNTIL`, `BYSECOND`, `BYMINUTE`, `BYHOUR`,
  `BYDAY`, `BYMONTHDAY`, `BYYEARDAY`, `BYWEEKNO`, `BYMONTH`, `BYSETPOS`, and
  `WKST`.
- Implement candidate-set semantics: expand each frequency interval, apply
  selector filters, sort deterministically, apply `BYSETPOS`, then apply
  occurrence bounds.
- Preserve current public API compatibility and existing recurrence/natural
  tests.
- Keep unsupported or out-of-scope temporal behavior as explicit errors, never
  silent no-ops or host-local defaults.
- Add focused RFC5545 tests and docs so the acceptance matrix can treat this
  track as complete once PR CI passes.

## Non-goals

- Do not implement `Temporal.recurrence-set`, `RDATE`, `EXDATE`, `EXRULE`, or
  inclusion/exclusion merging in this track.
- Do not implement ICS/VEVENT parsing, export, `VTIMEZONE`, or libical-backed
  interoperability in this track.
- Do not implement explicit-zone recurrence expansion, DST gap/overlap policy,
  or UTC/instant `UNTIL` expansion in this track.
- Do not broaden natural-language grammar beyond preserving existing recurrence
  phrase behavior.
- Do not add ICU/CLDR, business calendars, non-Gregorian calendars, timestamp
  migrations, or runtime scheduler redesign.
- Do not accept `BYSECOND=60` unless a later explicit leap-second policy is
  designed; current `PlainDateTime` cannot represent it, so it must fail loudly.

## Considered approaches

### Approach A: Incrementally patch existing generators

The current module has separate loops for daily, weekly, monthly, and yearly
rules. Each selector could be patched into those paths individually.

This is rejected. Full RFC5545 semantics require ordered candidate sets within
frequency intervals, especially for ordinal `BYDAY`, negative month/year/week
selectors, and `BYSETPOS`. Patching the existing loops would defer the required
architecture and make later selectors brittle.

### Approach B: Native or libical-backed recurrence engine now

Space could move RRULE expansion to C++ or bind a third-party iCalendar library
for recurrence.

This is rejected for this track. The existing public surface is a Fennel policy
layer over `PlainDateTime`, and standalone RRULE expansion can be implemented
without adding native dependency, packaging, and ICS value-type decisions. Those
decisions belong to the later ICS/iCalendar interoperability track.

### Approach C: Fennel candidate-set RRULE engine

This is selected. The track introduces focused recurrence modules that normalize
rules and expand ordered candidate sets while keeping the existing facade stable.
It is the smallest architecture that matches RFC5545 selector semantics and gives
later recurrence-set and zoned-expansion tracks a stable primitive to compose.

## Design

### Module boundaries

The current `assets/lua/temporal/recurrence.fnl` should become a facade over
focused internal modules:

- `temporal/recurrence/rule.fnl` owns normalized rule construction, RRULE
  parsing, RRULE serialization, validation, deterministic canonical field order,
  and invalid-rule diagnostics.
- `temporal/recurrence/engine.fnl` owns occurrence expansion over
  `PlainDateTime`, candidate-set generation, selector application, deterministic
  ordering, `BYSETPOS`, and bounds.
- `temporal/recurrence.fnl` preserves the public API by delegating to the rule
  and engine modules.

The split is internal. Callers continue using `Temporal.recurrence`.

### Normalized rule shape

Rules remain plain Fennel tables using canonical keyword option keys. Existing
keys remain valid:

```fennel
{:freq :daily
 :interval 1
 :count 10
 :until "20260201T000000"
 :by-day [:mo :tu]
 :by-month [1 2]
 :by-month-day [1 15]}
```

This track extends the model with:

```fennel
{:freq :secondly|:minutely|:hourly|:daily|:weekly|:monthly|:yearly
 :by-second [0 30]
 :by-minute [0 15 30 45]
 :by-hour [9 17]
 :by-day [:mo {:weekday :fr :ordinal -1}]
 :by-month-day [1 -1]
 :by-year-day [1 -1]
 :by-week-no [1 -1]
 :by-set-pos [1 -1]
 :week-start :mo}
```

The exact internal representation for ordinal weekdays may be adjusted by the
implementation plan, but it must be normalized, documented by tests, and not
leak alternate legacy aliases.

### RRULE parsing and serialization

`parse-rrule` accepts `RRULE:` text and rejects malformed, duplicated, unknown,
or unsupported fields loudly. `to-rrule` emits deterministic field order:

1. `FREQ`
2. `INTERVAL` when not `1`
3. `COUNT`
4. `UNTIL`
5. `BYSECOND`
6. `BYMINUTE`
7. `BYHOUR`
8. `BYDAY`
9. `BYMONTHDAY`
10. `BYYEARDAY`
11. `BYWEEKNO`
12. `BYMONTH`
13. `BYSETPOS`
14. `WKST` when not the default

List ordering is deterministic. The engine may preserve caller order in the
normalized rule for round-trip friendliness, but occurrence generation must sort
candidates by actual `PlainDateTime` before `BYSETPOS` and final output.

### Expansion model

Occurrence expansion is bounded by `COUNT`, local/floating `UNTIL`, caller
`:limit`, or a combination of those bounds. Unbounded expansion remains an
explicit error.

For each frequency interval, the engine:

1. Finds the current interval bucket relative to `DTSTART` and `INTERVAL`.
2. Generates candidate `PlainDateTime` values at the frequency granularity.
3. Applies applicable BY* selectors.
4. Sorts candidates deterministically by `PlainDateTime` value.
5. Applies positive and negative `BYSETPOS` within the bucket.
6. Drops candidates before `DTSTART` for the first bucket.
7. Applies `UNTIL`, `COUNT`, and caller `:limit` bounds.

`WKST` affects weekly interval grouping and week-number calculations. It must not
introduce host-local timezone behavior.

### Date and time semantics

Expansion operates on `PlainDateTime`. Date selectors use the proleptic Gregorian
calendar behavior already provided by Space temporal primitives and helper
functions. Time selectors preserve the nanosecond component of `DTSTART` unless a
selector explicitly changes the selected second/minute/hour field.

UTC `UNTIL` values, zoned comparisons, and DST transitions are rejected in this
track with explicit messages because they require the next explicit-zone
recurrence track.

### Diagnostics

Diagnostics may remain string exceptions, but they must identify the rejected
RRULE key or invalid value. Tests must cover duplicate keys, unknown keys,
out-of-range values, malformed ordinal weekdays, unsupported `BYSECOND=60`,
unbounded expansion, UTC/instant `UNTIL` expansion, and impossible selector
combinations that would otherwise risk infinite loops.

### Documentation and acceptance

`docs/dev/features/temporal-parsing-recurrence.md` must be updated from bounded
subset language to full RFC5545 RRULE language for this track, while explicitly
pointing recurrence sets and zoned/DST expansion to the next roadmap track.

`docs/dev/features/temporal-complete-acceptance.md` must record that the RFC5545
recurrence row has full selector tests, invalid-rule diagnostics, focused suite
coverage, and PR CI evidence after the implementation lands.

## Testing strategy

- Preserve all existing recurrence tests.
- Add a focused `tests.test-temporal-recurrence-rfc5545` module registered in the
  fast suite.
- Cover parser and serializer behavior for every in-scope RRULE field.
- Cover representative RFC5545 examples, including ordinal weekdays, negative
  month/year/week selectors, `WKST`, `BYSETPOS`, sub-daily frequencies, and
  combined date/time selectors.
- Cover bounds interactions for `COUNT`, `UNTIL`, and caller `:limit`.
- Run the Space Fennel validation ladder: touched-file compile check, constraints,
  focused recurrence tests, existing recurrence regression tests, broader suite,
  and PR CI.

## Acceptance criteria

- Public `Temporal.recurrence` API names remain stable.
- Current recurrence and natural-language recurrence behavior remains compatible.
- All in-scope RRULE frequencies and selectors parse, serialize, validate, and
  expand over `PlainDateTime`.
- Candidate ordering is deterministic and `BYSETPOS` is applied after selector
  filtering inside each frequency interval.
- Unsupported recurrence-set, ICS, explicit-zone, DST, UTC/instant `UNTIL`, and
  leap-second behaviors fail loudly.
- Docs and acceptance matrix describe the completed RRULE scope and the remaining
  recurrence-set/zoned boundaries.
- Required local validation and PR CI pass.
