# temporal-core

## Canonical Import

```fennel
(local temporal-core (require :temporal-core))
```

## Source Files

- `src/lua_temporal_core.cpp`
- `src/temporal.h`

## What It Provides

`temporal-core` exposes the native temporal object bindings used by the higher-level [`temporal`](/sdk/modules/temporal) module: durations, instants, plain date-times, zoned date-times, clocks, and tzdb metadata.

## API Summary

- `duration.from-nanoseconds(nanoseconds)`, `duration.from-seconds(seconds)`, `duration.from-parts(parts)` create `TemporalDuration` values.
- `instant.parse(text)` and `instant.from-unix(epoch-seconds [nanosecond])` create `TemporalInstant` values.
- `plain-date-time.parse(text)` and `plain-date-time.from-fields(fields)` create `TemporalPlainDateTime` values.
- `zoned-date-time.from-plain(plain zone-id [disambiguation])` and `zoned-date-time.from-instant(instant zone-id)` create `TemporalZonedDateTime` values.
- `clock.system()` and `clock.fixed(instant)` create clock objects; clock objects provide `:now()`.
- `tzdb.version()` returns the native time-zone database version string.
- `TemporalDuration` methods/properties: `:nanoseconds()`, `:compare(other)`, `:to-string()`.
- `TemporalInstant` methods/properties: `:epoch-seconds()`, `:nanosecond()`, `:to-string()`, `:compare(other)`, `:add(duration)`, `:since(earlier)`.
- `TemporalPlainDateTime` methods: `:fields()`, `:to-string()`, `:compare(other)`, `:add(duration)`, `:since(earlier)`, `:add-days(days)`, `:add-calendar(fields)`, `:iso-weekday()`.
- `TemporalZonedDateTime` methods/properties: `:instant()`, `:zone-id()`, `:fields()`, `:offset-string()`, `:to-string()`.

## Examples

```fennel
(local temporal-core (require :temporal-core))

(local instant (temporal-core.instant.parse "2026-09-28T12:00:00Z"))
(local duration (temporal-core.duration.from-parts {:seconds 30}))
(local later (instant:add duration))

(print (later:to-string))
(print (temporal-core.tzdb.version))
```

## Errors and Platform Notes

Factory functions and methods raise errors for invalid field types, missing required fields, unsupported disambiguation values, parse failures, and invalid calendar arithmetic. `plain-date-time.from-fields` requires `year`, `month`, and `day`; time fields default to zero. Calendar additions accept only `years`, `months`, `weeks`, and `days`, require finite safe integer values, and reject mixed signs. `zoned-date-time.from-plain` disambiguation is a string at the core layer (`"reject"`, `"earliest"`, or `"latest"`).

## Related Modules

- [`temporal`](/sdk/modules/temporal) for higher-level Fennel helpers and keyword-friendly wrappers.

## Aliases and Search Terms

Search terms: native temporal, TemporalDuration, TemporalInstant, TemporalPlainDateTime, TemporalZonedDateTime, clock, tzdb.
