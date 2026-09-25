# Temporal Ecosystem Design

## Context

Space does not yet have a canonical date/time facility. Current temporal behavior
is scattered across Lua `os.time`, `os.date`, and `os.clock`, C++
`std::chrono::steady_clock`, `app.engine.now-ms`, `sysinfo.now-ms`, file modified
timestamps, workflow `started-at` / `finished-at` seconds, and Fennel runtime
timers. These primitives solve local needs, but they do not provide a coherent
model for instants, civil date-times, time zones, daylight-saving gaps and
overlaps, deterministic clocks, or robust parsing and formatting.

The target is a clean-slate temporal ecosystem for the C++/Lua/Fennel stack. The
first implementation must land a production-quality semantic core rather than a
thin wrapper around a legacy API. The architecture must also leave deliberate
extension points for later natural-language parsing, recurrence rules,
localization, ICU-backed formatting, and additional calendar systems.

## Goals

- Establish the canonical temporal model for Space applications and libraries.
- Provide typed, immutable values for instants, durations, plain civil
  date-times, zoned date-times, and injectable clocks.
- Make timezone and DST behavior explicit, deterministic, and tested.
- Expose an ergonomic Lua/Fennel API while keeping correctness-critical
  calendar/timezone machinery in native code.
- Support ISO/RFC3339 parsing and formatting in the first implementation.
- Keep external context explicit: clocks and time zones must be supplied rather
  than silently read from ambient state when determinism matters.
- Include conformance-style tests for invalid fields, DST gaps and overlaps,
  invalid zones, parsing, formatting, arithmetic, and fixed clocks.
- Document semantic boundaries so future recurrence, localization, calendars,
  and arbitrary human-date parsing can compose with the core without replacing
  it.

## Non-goals for the first implementation

- Do not implement natural-language or arbitrary human date-string parsing.
- Do not implement recurrence rules or schedules.
- Do not implement localized formatting, localized parsing, or CLDR data.
- Do not implement non-Gregorian calendars.
- Do not redesign existing runtime timer APIs, media clocks, `engine.now-ms`, or
  `sysinfo.now-ms`.
- Do not silently migrate existing persisted timestamp schemas in this first PR.
- Do not make host-local timezone assumptions part of the public API.

These are future layers, not rejected capabilities. The first PR should make
them easier by giving them stable typed values and explicit context objects to
consume and produce.

## Considered approaches

### Approach A: Pure Lua/Fennel temporal library

A pure Lua/Fennel implementation would be easy to load, simple to inspect, and
avoid a native dependency. It would fit Space's Fennel ergonomics well for small
duration and date helpers.

This approach is not suitable as the production core. Correct IANA timezone
handling, DST gaps and overlaps, historical offset changes, future tzdb updates,
and parsing edge cases are difficult to implement and maintain in Fennel without
recreating a mature native timezone engine. It would also risk drifting from
platform filesystem/process timestamps that originate in C++.

### Approach B: Native C++ temporal engine with Fennel ergonomics

The native layer owns the low-level semantic engine: POSIX instants, precise
durations, ISO proleptic Gregorian civil values, timezone lookup, DST ambiguity
resolution, parsing, formatting, and clock implementations. Lua receives typed
userdata through a `temporal-core` binding, and Fennel exposes the public
ergonomic `temporal` namespace.

For C++17, Howard Hinnant `date/tz` is the best first dependency candidate. It
is mature, chrono-compatible, MIT-licensed, and directly influenced C++20 chrono
calendar/timezone design. The project should configure it to use the OS tzdb and
disable remote downloading so timezone data is deterministic and deployment
policy remains explicit.

This approach balances correctness and API ownership. Space's public API remains
ours, while the hard timezone machinery comes from a mature component.

### Approach C: ICU-first temporal subsystem

ICU provides excellent internationalization, CLDR-backed formatting, localized
names, timezone data, and calendar support. An ICU-first implementation would be
well-positioned for localized display and non-Gregorian calendars.

It is too large for the first foundation PR. ICU introduces substantial data
packaging and API surface area, and using it as the core arithmetic model risks
coupling fundamental temporal semantics to formatting/localization concerns.
ICU should remain a future optional layer for localized formatting, parsing, and
calendar-specific display, not the first core abstraction.

## Decision

Use Approach B. Build a native C++ temporal core, expose it through a small Lua
binding named `temporal-core`, and provide the canonical Fennel/Lua API in
`assets/lua/temporal.fnl`.

The first implementation should vendor Howard Hinnant `date/tz` for C++17 IANA
timezone behavior, configured for local OS tzdb data with remote download paths
disabled. Space's public semantic model should follow the separation used by
ECMAScript Temporal, Noda Time, and `java.time`: absolute instants are distinct
from plain civil values, offsets, zoned date-times, durations, and clocks.

## Semantic model

### `Instant`

An `Instant` is an absolute point on the Unix/POSIX timeline. It is independent
of calendars, time zones, and localization. Instants can be parsed from and
formatted as RFC3339/ISO strings with `Z` or an explicit numeric offset.

Leap seconds are rejected explicitly in the first implementation. They must not
be silently normalized to the next minute or hidden behind host-library behavior.

### `Duration`

A `Duration` is an exact elapsed amount of time represented with nanosecond
precision. It is appropriate for measuring elapsed time and adding exact amounts
to instants. It is not a calendar period: one month, one year, and one civil day
across a DST transition are future `Period`/calendar-arithmetic concerns, not
`Duration` aliases.

### `PlainDateTime`

A `PlainDateTime` is an ISO proleptic Gregorian civil date and wall-clock time
without a timezone or UTC offset. It cannot identify an instant by itself.
Converting it to an instant requires an explicit zone id and a disambiguation
policy.

The first implementation focuses on combined date-time values because they are
the minimum useful civil type for timezone conversion. The architecture should
allow later `PlainDate`, `PlainTime`, `YearMonth`, and calendar-specific civil
types without changing `Instant` or `ZonedDateTime` semantics.

### `ZonedDateTime`

A `ZonedDateTime` pairs an `Instant` with an IANA timezone id. Formatting and
field projection happen through the zone rules. Constructing a `ZonedDateTime`
from a `PlainDateTime` must handle daylight-saving gaps and overlaps explicitly.

Disambiguation policies:

- `:reject` — throw on ambiguous or nonexistent local times. This is the default.
- `:earliest` — choose the earliest valid instant in an overlap or the first
  valid instant after a gap.
- `:latest` — choose the latest valid instant in an overlap or the last valid
  instant before a gap when supported by the native engine.

No API should silently use the machine's local timezone for zoned operations.
Callers must provide a zone id such as `"America/New_York"`.

### `Clock`

A `Clock` produces instants. The core should provide at least:

- `clock.system()` for real system time;
- `clock.fixed(instant)` for deterministic tests and replay.

Clock-dependent APIs should accept a clock object rather than hard-coding global
time reads. This makes tests deterministic and prevents hidden dependencies on
external context.

## API shape

The native Lua binding should be a lower-level module named `temporal-core`.
It should expose userdata-backed immutable values and factory namespaces, not raw
constructors. The Fennel module `temporal` should be the ergonomic public API:

```fennel
(local Temporal (require :temporal))

(local instant (Temporal.instant.parse "2026-09-25T12:34:56Z"))
(local clock (Temporal.clock.fixed instant))
(local now (clock:now))
(local dt (Temporal.plain-date-time.parse "2026-11-01T01:30:00"))
(local zdt (Temporal.zoned-date-time.from-plain
             dt
             "America/New_York"
             {:disambiguation :earliest}))
```

Canonical first-pass namespaces:

- `Temporal.duration`
- `Temporal.instant`
- `Temporal.plain-date-time`
- `Temporal.zoned-date-time`
- `Temporal.clock`

The Fennel layer should be intentionally thin: naming, argument validation,
friendly tables, and idiomatic return surfaces belong there; calendar arithmetic,
timezone resolution, offset lookup, and parsing correctness belong in C++.

## Extension architecture

The core must not be designed as a dead end. Future features should attach as
layers around typed values and explicit context objects:

- **Natural-language parsing:** a future parser can accept text plus a parse
  context containing locale, reference instant/date, default zone, and ambiguity
  policy. It should return typed core values or structured parse candidates, not
  raw timestamp numbers.
- **Recurrence:** recurrence rules should operate on explicit start values,
  zones, and calendar policies. They should produce `Instant`, `PlainDateTime`,
  or `ZonedDateTime` sequences according to declared semantics.
- **Localization and ICU:** ICU should layer on display formatting, localized
  parsing, localized names, and CLDR calendars. It should not replace the core
  instant/duration/timezone model.
- **Additional calendars:** non-Gregorian calendars should be explicit calendar
  types or calendar-aware civil values. They must not change what `Instant` means
  or make `PlainDateTime` silently calendar-polymorphic.
- **Calendar arithmetic:** future `Period` types should be separate from exact
  `Duration` so adding one month and adding thirty days cannot be confused.
- **Timezone data policy:** the native core should expose a tzdb version/status
  query when available. Packaging decisions for bundled tzdb snapshots or
  update tools can evolve without changing public temporal value semantics.

## Error handling

Temporal errors must be explicit and loud:

- invalid calendar fields throw;
- invalid duration units or overflow throw;
- invalid parse strings throw;
- leap-second inputs throw in the first implementation;
- missing tzdb data throws with a diagnostic that identifies the timezone data
  problem;
- unknown zone ids throw;
- ambiguous or nonexistent local times throw under `:reject`.

The API should not return quietly normalized values for invalid input, and it
should not convert failures into nil/no-op behavior unless a future explicit
`try-parse` API is added with structured error results.

## Testing and validation

The first implementation should include native and Fennel tests:

- C++ tests for value construction, parse/format round trips, arithmetic,
  timezone conversion, gap/overlap disambiguation, invalid zones, leap-second
  rejection, and fixed clocks.
- Fennel tests for the public `temporal` API and representative edge cases.
- DST conformance cases should include `America/New_York` spring-forward and
  fall-back transitions.
- Tests should assert explicit failures for invalid input rather than merely
  checking successful happy paths.

Fennel-facing validation must follow the project ladder:

1. build first when `./build/space` is missing or stale;
2. `make fennel-check`;
3. `make constraints`;
4. focused `tests.test-temporal` run through `./build/space` with the standard
   Space test environment;
5. broader `make test` for final validation because the work touches C++, CMake,
   native bindings, Fennel modules, and fast-suite registration.

## Acceptance criteria

- `require :temporal` succeeds from Fennel.
- `Instant`, `Duration`, `PlainDateTime`, `ZonedDateTime`, and `Clock` exist as
  documented public concepts.
- Instant parsing and formatting require explicit UTC/offset information.
- Zoned conversion requires explicit IANA zone ids.
- DST gaps and overlaps are deterministic and covered by tests.
- Invalid parses, invalid fields, leap seconds, missing/invalid zones, and
  rejected ambiguous/nonexistent times fail loudly.
- Fixed clocks make clock-dependent code deterministic without global mutable
  test state.
- Existing `engine.now-ms`, `sysinfo.now-ms`, runtime timers, and profiling
  clocks continue to behave as before.
- Developer documentation explains first-pass semantics and how advanced parsing,
  recurrence, localization, ICU, and additional calendars will layer on the core.
