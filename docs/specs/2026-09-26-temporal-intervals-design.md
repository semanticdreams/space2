# Temporal Intervals and Repeating Intervals Design

## Context

Space now has a layered temporal foundation: native C++ core value types, Lua
bindings, and Fennel modules for strict standard text, explicit patterns,
recurrence rules, structured expressions, and a small natural grammar. The next
useful production slice is an explicit interval model that can represent ranges
and bounded repeated ranges without overloading recurrence rules or durations.

Intervals are a foundational concept for scheduling, timeline selection, and
future natural-language phrases such as "from Monday to Friday". They should be
typed and deterministic before Space attempts broader RFC5545, localized
intervals, or ambiguous natural-language ranges.

## Goals

- Add explicit half-open temporal interval records above the temporal core.
- Add bounded repeating interval records and ISO-style repeat parsing for
  start/end intervals.
- Keep native core changes small, dependency-free, and semantic: comparisons and
  exact plain-date-time duration arithmetic only.
- Keep interval parsing, formatting, validation policy, and repeating syntax in
  Fennel layers beside the existing temporal facade modules.
- Support intervals over `Instant` and `PlainDateTime` endpoints in the first
  slice.
- Make all invalid or unsupported forms fail loudly.
- Preserve existing `duration`, `instant`, `plain-date-time`, `zoned-date-time`,
  `standard`, `pattern`, `recurrence`, `expression`, and `natural` APIs.

## Non-goals for this slice

- Do not add native C++ `Interval` or `RepeatingInterval` userdata.
- Do not implement the full ISO 8601 interval grammar.
- Do not support duration/start or duration/end interval forms.
- Do not support zoned-date-time intervals or DST-aware interval expansion.
- Do not add calendar periods containing years, months, business days, or locale
  calendars.
- Do not add interval set algebra, overlap merging, gap queries, or scheduler UX.
- Do not add broad natural-language interval parsing.
- Do not add ICU, CLDR, localization data, or new third-party runtime
  dependencies.

These are deferred so the first interval slice remains small, reviewable, and
production-safe.

## Considered approaches

### Approach A: Native interval userdata

Implement `Interval` and `RepeatingInterval` directly in C++ and expose them to
Lua/Fennel as first-class userdata.

This gives strong native typing but moves external syntax and higher-level range
policy into the core. It also forces early decisions about zoned intervals,
calendar periods, and ISO grammar coverage. That conflicts with the existing
layering rule that the core remains independent from parsing facades and broad
product semantics.

### Approach B: Fennel-only interval records

Represent intervals entirely as Fennel tables and implement all ordering,
duration, and shift behavior in Fennel.

This minimizes native changes, but it risks duplicating exact temporal math in
Fennel. Interval correctness depends on comparing endpoints, calculating exact
duration, and shifting endpoints consistently. Those primitives belong close to
the core values that already own exact nanosecond representation.

### Approach C: Hybrid primitives plus Fennel facade

Add only small native primitives for value comparison and exact
plain-date-time-duration math. Implement public interval and repeating-interval
records, ISO parsing/formatting, validation policy, and occurrence expansion in
Fennel.

This keeps the core clean while giving the Fennel layer safe building blocks. It
matches the prior temporal parsing/recurrence architecture and gives future
slices room to add native userdata only if proven necessary.

## Decision

Use Approach C.

The native core gains dependency-free primitives:

- compare exact `Duration` values;
- compare `Instant` values;
- compare `PlainDateTime` values;
- add an exact `Duration` to a `PlainDateTime`;
- calculate the exact local `Duration` between two `PlainDateTime` values.

The Fennel layer gains two public namespaces:

- `Temporal.interval` for half-open intervals;
- `Temporal.repeating-interval` for bounded repeated intervals.

## Semantics

### Interval bounds

All intervals are half-open: `[start, end)`.

An interval contains its start endpoint and excludes its end endpoint. Zero-length
and reversed intervals are invalid. This avoids ambiguous overlap semantics and
matches common scheduling practice.

### Supported endpoint types

The first slice supports two endpoint types:

- `:instant` for exact timeline intervals;
- `:plain-date-time` for civil local intervals without a zone.

Start and end endpoints must have the same type. Mixed endpoints throw. Zoned
date-time intervals are deferred because production DST behavior needs a separate
design covering wall-time versus instant expansion.

### Duration and shift

`Temporal.interval.duration(interval)` returns an exact `Duration`:

- instant intervals use exact timeline duration;
- plain-date-time intervals use exact local nanosecond difference between local
  date-times.

`Temporal.interval.shift(interval, duration)` shifts both endpoints by an exact
duration and returns another half-open interval of the same endpoint type.

Calendar periods such as one month or one year are not durations in this slice.

### ISO interval forms

The first slice supports only start/end forms:

```text
<start>/<end>
```

The caller supplies the endpoint type through canonical options:

```fennel
{:type :instant}
{:type :plain-date-time}
```

Instant endpoints use `Temporal.standard.parse-instant`. Plain date-time
endpoints use `Temporal.standard.parse-plain-date-time`. Formatting emits the
canonical start/end form using the matching standard formatter.

Unsupported ISO forms throw explicitly:

- `<start>/<duration>`;
- `<duration>/<end>`;
- bare duration intervals;
- repeating intervals without the repeating namespace;
- zoned interval text;
- localized interval text.

### Repeating intervals

Repeating intervals are separate from recurrence rules. They repeat an interval
by shifting it by its exact duration.

Supported forms:

```text
R<count>/<start>/<end>
R/<start>/<end>
```

`R<count>` means the total number of interval occurrences returned. `R/` means
an unbounded repeating interval record. Unbounded records may be represented, but
expansion requires a canonical `{:limit n}` option.

If both a record count and expansion limit are present, expansion returns the
smaller number. Count and limit must be positive integers. `R0`, negative counts,
unknown options, missing bounds, and malformed repeat prefixes throw.

Repeating expansion preserves interval type and half-open bounds. It does not use
`Temporal.recurrence`; recurrence rules and repeating intervals remain separate
semantic subsystems.

## Public API direction

The existing `temporal` module gains namespaces without changing existing ones:

```fennel
Temporal.interval.from
Temporal.interval.parse
Temporal.interval.format
Temporal.interval.duration
Temporal.interval.contains
Temporal.interval.shift

Temporal.repeating-interval.from
Temporal.repeating-interval.parse
Temporal.repeating-interval.format
Temporal.repeating-interval.occurrences
```

Interval record shape:

```fennel
{:kind :interval
 :type :instant|:plain-date-time
 :start value
 :end value
 :bounds :half-open}
```

Repeating interval record shape:

```fennel
{:kind :repeating-interval
 :interval interval
 :count positive-integer-or-nil}
```

## Error handling

Errors must be explicit and loud for:

- missing or unknown option keys;
- unsupported endpoint type;
- mixed endpoint types;
- zero-length or reversed intervals;
- malformed interval text;
- unsupported ISO forms;
- malformed repeating prefixes;
- `R0`, negative counts, and non-integer counts;
- unbounded repeating expansion without `:limit`;
- non-positive or non-integer expansion limits;
- arithmetic overflow while shifting endpoints.

No API may silently default to host-local timezone behavior.

## Documentation updates

Add a new developer page for temporal intervals. Existing temporal docs should
link to it and update the deferred map: bounded ISO start/end intervals and
repeating intervals are no longer deferred, while full ISO grammar, calendar
periods, zoned intervals, localization, and interval algebra remain deferred.

## Validation expectations

Because this slice touches C++, Lua bindings, Fennel public APIs, focused tests,
fast-suite registration, and docs, validation must include:

- `make build` after native edits;
- focused CTests for native temporal core and Lua binding behavior;
- Fennel compile check for touched temporal modules/tests;
- `make constraints` after Fennel compile check;
- focused Fennel interval tests;
- full `make test` before finishing.

Direct Fennel test runs must use the project-native runtime with
`SPACE_ASSETS_PATH`, `FENNEL_PATH`, and `FENNEL_MACRO_PATH` set as documented in
`AGENTS.md`; system `fennel` or system `lua` are not validation oracles.

## Acceptance criteria

- `require :temporal` exposes `interval` and `repeating-interval` namespaces.
- Existing temporal public namespaces keep their current names and behavior.
- Native core changes are limited to comparison and exact local duration helpers.
- `Temporal.interval` creates, parses, formats, measures, contains, and shifts
  valid instant/plain-date-time intervals.
- `Temporal.repeating-interval` parses, formats, represents, and expands bounded
  repeating start/end intervals.
- Unsupported interval forms fail loudly instead of being guessed.
- Docs explain supported behavior and deferred continuation paths.
- Focused and broad validation pass.
