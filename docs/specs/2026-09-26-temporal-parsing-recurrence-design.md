# Temporal Parsing, Formatting, and Recurrence Design

## Context

Space now has a canonical temporal core with native C++17 value types, a Lua
`temporal-core` binding, and an ergonomic Fennel `temporal` API. That core
intentionally excludes higher-level parsing, localization, natural language, and
recurrence so the fundamental model remains small and correct.

The next layer should extend the ecosystem without contaminating core semantics.
External representations such as ISO strings, user-specified patterns, natural
phrases, and RRULE text should translate into typed temporal concepts or
structured expressions. They must not become hidden timestamp semantics inside
the core.

## Goals

- Add a coherent parsing, formatting, and recurrence architecture above the
  existing temporal core.
- Keep `Instant`, `Duration`, `PlainDateTime`, `ZonedDateTime`, `Clock`, and
  timezone conversion independent from natural language, recurrence, ICU, CLDR,
  locale data, and app-specific grammars.
- Provide strict standard/interchange parsing and formatting as a facade over
  core parse/format behavior.
- Add an explicit pattern API shape with deterministic numeric tokens.
- Model natural parsing as structured temporal expressions that require explicit
  context for resolution.
- Treat recurrence as its own semantic subsystem with programmatic rule objects,
  RRULE parsing/serialization, and deterministic occurrence expansion.
- Make the first implementation slice useful while documenting every deferred
  continuation path.

## Non-goals for this slice

- Do not add ICU, CLDR data, or localized date/time formatting/parsing.
- Do not implement broad natural-language parsing beyond a small deterministic
  English grammar.
- Do not implement non-Gregorian calendars.
- Do not implement full RFC5545 recurrence expansion.
- Do not add cron, ISO repeating interval expansion, or business-calendar rules.
- Do not add host-local timezone defaults.
- Do not migrate existing timestamp schemas or redesign runtime timers.
- Do not add a new third-party runtime dependency in this slice.

These capabilities are deferred, not rejected. Their intended architecture and
required decisions are documented below.

## Considered approaches

### Approach A: Native monolith

All strict parsing, pattern parsing, natural parsing, recurrence, and formatting
could be implemented directly in C++ beside the temporal core.

This would give direct access to native types but would blur boundaries. Optional
features such as natural language, locale data, and recurrence would become part
of the core build and review surface. Adding ICU or CLDR later would require
threading heavyweight dependencies through core code.

### Approach B: Layered subsystem over the core

The C++ core remains the primitive semantic layer. It may gain small civil-date
helpers that are fundamental and dependency-free, but parsing layers live in
focused Fennel modules:

- `temporal.standard` for strict interchange formats;
- `temporal.pattern` for explicit pattern parse/format;
- `temporal.recurrence` for programmatic recurrence and RRULE;
- `temporal.expression` for structured expression/context resolution;
- `temporal.natural` for the small deterministic natural grammar.

This matches Space's current Lua/Fennel API style, keeps optional heavy layers
replaceable, and still lets higher-level code consume typed temporal values.

### Approach C: Provider/plugin-first parsing framework

The project could first design parser providers for ICU, CLDR, Duckling-style
natural language, app-specific grammars, and recurrence engines.

This is attractive long-term but premature for the first extension. Provider
abstraction is easier to design once the typed expression, recurrence, and
context records are stable.

## Decision

Use Approach B. Implement a layered subsystem above the existing temporal core.
The first slice should establish concrete modules and semantics while leaving
heavy localization and broad natural language as documented future providers.

The core remains independent. Parsers and formatters translate external forms to
core values or structured temporal expressions. Recurrence is a first-class
semantic subsystem, not a side effect of natural language parsing.

## Layer boundaries

### Core layer

The core owns fundamental temporal concepts and operations:

- exact `Instant` and `Duration` behavior;
- `PlainDateTime` validation and simple civil arithmetic needed by higher
  layers;
- `ZonedDateTime` conversion and DST disambiguation;
- deterministic clocks;
- canonical strict parsing already provided by the native core.

The core must not depend on natural-language modules, recurrence modules,
locales, ICU, CLDR, or pattern grammars.

### Standard parse/format layer

`temporal.standard` is the strict interchange facade. It should expose named
operations for instants, plain date-times, and zoned date-times. It may use the
native core's strict parsing for instants/plain date-times and add a strict
zoned text shape such as:

```text
YYYY-MM-DDTHH:mm:ss[.fraction](Z|+HH:MM|-HH:MM)[Zone/Id]
```

For zoned input, the layer must verify that the supplied numeric offset is valid
for the zone at the resolved instant. A mismatched offset is an error.

### Pattern layer

`temporal.pattern` accepts explicit developer-provided patterns. The first slice
supports only a small deterministic numeric token set:

- `yyyy`
- `MM`
- `dd`
- `HH`
- `mm`
- `ss`
- quoted literals with single quotes

Unsupported tokens fail loudly. This layer establishes API shape without
pretending to implement localized pattern syntax. Future localized patterns can
be provided by ICU/CLDR-backed modules.

### Recurrence layer

`temporal.recurrence` owns recurrence semantics. It exposes normalized rule
records, RRULE parsing/serialization, and occurrence expansion. Natural-language
recurrence phrases become one frontend that emits recurrence rules.

First-slice normalized rule shape:

```fennel
{:freq :daily|:weekly|:monthly|:yearly
 :interval 1
 :count 10
 :until plain-or-instant
 :by-day [:mo :tu]}
```

First-slice RRULE support should include `FREQ`, `INTERVAL`, `COUNT`, `UNTIL`,
and `BYDAY`, with deterministic serialization and strict duplicate/unknown key
rejection. Occurrence expansion should support bounded daily and weekly rules.
Unsupported expansion must throw explicit errors.

### Structured expression layer

`temporal.expression` defines structured temporal expression records and context
resolution. Expression records are not timestamps. They represent parse results
that need context:

```fennel
{:kind :relative-date :amount 1 :unit :day}
{:kind :next-weekday :weekday :tu}
{:kind :recurrence :rule recurrence-rule}
```

Resolution requires a context with an explicit reference and timezone policy:

```fennel
{:reference-plain-date-time plain
 :zone-id "America/New_York"
 :default-time {:hour 0 :minute 0 :second 0 :nanosecond 0}}
```

If a reference instant is used instead, the caller must provide `:zone-id` so the
instant can be projected deterministically. Missing context is an error.

### Natural layer

`temporal.natural` parses a small deterministic English grammar into structured
expressions. First-slice forms:

- `today`
- `tomorrow`
- `next Tuesday`
- `in 3 days`
- `in 2 weeks`
- `every Tuesday`

The parser should not immediately return instants. It returns expression records.
Applications call `temporal.expression.resolve` with explicit context to obtain
typed results.

## Public API direction

The existing `temporal` module should gain namespaces without breaking existing
ones:

```fennel
Temporal.standard.parse-instant
Temporal.standard.format-instant
Temporal.standard.parse-plain-date-time
Temporal.standard.format-plain-date-time
Temporal.standard.parse-zoned-date-time
Temporal.standard.format-zoned-date-time

Temporal.pattern.compile
Temporal.pattern.parse
Temporal.pattern.format

Temporal.recurrence.from
Temporal.recurrence.parse-rrule
Temporal.recurrence.to-rrule
Temporal.recurrence.occurrences

Temporal.expression.context
Temporal.expression.resolve

Temporal.natural.parse
```

The umbrella remains ergonomic, but each subsystem is a separate module so
applications can require only what they need later if dependency weight grows.

## Error handling

- Strict standard parsing throws for invalid or mismatched offset/zone input.
- Pattern compilation throws for unsupported tokens and malformed quotes.
- Pattern parsing throws for invalid fields or text that does not match.
- RRULE parsing throws for duplicate keys, unknown keys, invalid values, and
  unsupported date forms.
- Occurrence expansion throws for unsupported frequencies or unbounded requests.
- Natural parsing throws for unsupported grammar.
- Expression resolution throws when required context is missing.

Future `try-parse` APIs may return structured errors, but this slice follows the
current temporal policy of loud failures for invalid input.

## Deferred continuation map

### ICU/CLDR and localization

Deferred until the project chooses data packaging and binary-size policy.
Future work should add `temporal.localized` or provider-backed pattern modules
without replacing the core, recurrence, or expression record model. Localized
formatting/parsing may consume and produce core values or structured
expressions, but it must not introduce host-local timezone defaults.

### Broad natural language

Deferred until supported locales/languages, ambiguity UX, and dependency model
are decided. Candidate inspirations include Duckling and Chrono, but the public
API should remain Space expression records plus explicit context. Broad natural
parsers should return candidates with confidence/evidence and required context,
not silently choose one timestamp.

### Full RFC5545 recurrence

Deferred expansion includes `BYMONTH`, `BYMONTHDAY`, `BYSETPOS`, `WKST`, `RDATE`,
`EXDATE`, timezone-aware DTSTART handling, and full occurrence iteration rules.
The first slice's normalized recurrence records should be compatible with these
fields.

### ISO 8601 intervals and repeating intervals

Deferred. Future interval support should introduce explicit `Interval` and
possibly `RepeatingInterval` concepts rather than overloading recurrence rules.

### Calendar periods and calendar arithmetic

Deferred. Future `Period` types should remain distinct from exact `Duration` so
calendar additions cannot be confused with elapsed nanoseconds.

### Non-Gregorian calendars

Deferred. Future calendars should be explicit calendar-aware civil types or
localized display layers. They must not make current `PlainDateTime` silently
calendar-polymorphic.

### Parser providers/plugins

Deferred until the first subsystem records stabilize. Future providers can wrap
ICU, CLDR, Duckling-like services, app-specific grammars, or domain parsers, but
they should produce the same core values, recurrence rules, or expression
records.

## Testing strategy

- Native tests cover any added core helper primitives.
- Lua binding tests cover added helper methods.
- Fennel tests cover public `temporal.standard`, `temporal.pattern`,
  `temporal.recurrence`, `temporal.expression`, and `temporal.natural` APIs.
- Tests must use fixed reference date-times and explicit zones for deterministic
  expression resolution.
- Recurrence tests must cover both parsing/serialization and occurrence
  expansion.
- Unsupported forms must have negative tests proving loud failures.

## Acceptance criteria

- Existing temporal API remains compatible.
- The core remains independent of parsing/recurrence/natural/localization
  modules.
- `require :temporal` exposes `standard`, `pattern`, `recurrence`, `expression`,
  and `natural` namespaces.
- Standard strict parse/format facade round-trips supported values.
- Pattern parse/format supports the first token subset and rejects unsupported
  tokens.
- Natural parse returns structured expressions for the first grammar subset.
- Expression resolution requires explicit context and returns typed records.
- Recurrence supports programmatic rules, RRULE parse/serialize, and bounded
  daily/weekly occurrence expansion.
- Deferred localization, broad natural language, full recurrence, intervals,
  periods, calendars, and providers are documented clearly enough for follow-up
  specs/plans.
