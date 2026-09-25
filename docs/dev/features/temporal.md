# Temporal Core

The temporal core is Space's first production date/time layer. Correctness-critical semantics live in native C++17 using Howard Hinnant `date/tz`; Lua exposes immutable userdata through a small native binding, and the public Fennel/Lua API wraps that binding with ergonomic option shapes.

## Public modules

- `require :temporal` is the public Fennel/Lua API for application and feature code (written as `(require :temporal)` in Fennel). It exposes `duration`, `instant`, `plain-date-time`, `zoned-date-time`, `clock`, and `tzdb` namespaces.
- `require "temporal-core"` is the lower-level native Lua binding. Use it when testing or extending the binding layer directly; prefer `:temporal` elsewhere.

The public wrapper intentionally keeps timezone and calendar rules in C++ instead of reimplementing them in Fennel.

## Values

- **`Instant`** is an absolute Unix/POSIX timeline value with nanosecond precision. It can be parsed from timestamp text with an explicit offset or created from Unix epoch seconds plus an optional nanosecond field. Leap seconds are rejected instead of normalized.
- **`Duration`** is exact elapsed time with nanosecond precision. It is not a calendar period: months, years, business days, and daylight-saving-aware calendar math are outside this layer.
- **`PlainDateTime`** is an ISO proleptic Gregorian civil date-time without a zone or offset. It represents local fields only and cannot identify an instant until paired with a timezone and disambiguation policy.
- **`ZonedDateTime`** pairs an `Instant` with an explicit IANA timezone id such as `America/New_York`. It can expose local fields, the active offset, the zone id, and the underlying instant.

All invalid fields, invalid parses, overflow, invalid zones, missing tzdb data, leap seconds, and rejected DST gaps/overlaps are loud errors.

## Timezone policy

Timezone conversion requires an explicit IANA zone id. The API does not silently use host-local timezone defaults, because replay, tests, distributed sessions, and persisted state must not depend on the machine running Space.

The native core uses `date/tz` with deterministic timezone data and remote tzdb download/update disabled. Unix-like builds use the operating-system timezone database. Windows builds bundle the IANA tzdata snapshot plus pinned CLDR `windowsZones.xml` mapping recorded in `external/date/VENDORED_VERSION.md`; packaging copies them beside the executables as `tzdata/`, and `SPACE_TZDATA_PATH` may point tests or custom distributions at an equivalent provided snapshot. If Windows tzdata is missing or incomplete, temporal APIs throw an explicit `temporal timezone database unavailable:` error instead of falling back to host-local assumptions. `temporal.tzdb.version()` exposes the tzdb version reported by the selected runtime database.

## Disambiguation

Converting a `PlainDateTime` to a `ZonedDateTime` can encounter daylight-saving gaps or overlaps. The public API supports three disambiguation policies:

- `:reject` is the default and throws for nonexistent or ambiguous local times.
- `:earliest` resolves to the earliest valid matching instant, or to the first instant after a gap.
- `:latest` resolves to the latest valid matching instant, or to the last instant before a gap.

For example, `2026-11-01T01:30:00` in `America/New_York` occurs twice; callers must choose `:earliest`, `:latest`, or accept the default `:reject` error.

## Parsing and formatting

`Instant.parse` requires an ISO/RFC3339-style timestamp with an explicit `Z` or numeric offset and formats canonical UTC output through `:to-string`. `PlainDateTime.parse` accepts ISO proleptic Gregorian local date-time text without a zone or offset and formats the same civil fields through `:to-string`.

Leap seconds such as `23:59:60` are rejected explicitly in this implementation. The core does not include natural-language parsing.

## Clocks

- `temporal.clock.system()` returns a real-time clock backed by the native system clock.
- `temporal.clock.fixed(instant)` returns a deterministic clock whose `:now` method always returns the supplied instant, for tests and replay.

This feature does not change existing `engine.now-ms`, `sysinfo.now-ms`, media clocks, profiling clocks, or runtime timer behavior.

## Future layers

The temporal core intentionally excludes higher-level product features. Future layers include natural-language parsing, recurrence, localization, ICU formatting, CLDR data, non-Gregorian calendars, persisted timestamp migrations, and runtime timer redesign, and must be designed separately. Future timezone-related layers must preserve the invariant that zoned conversion never silently defaults to the host-local timezone.

## Validation

Use these commands when changing the temporal core, its Fennel wrapper, or its tests:

```bash
make build
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/tests/test-temporal.fnl --file assets/lua/tests/fast.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal:main
ctest --test-dir build -R 'test_temporal_core|test_lua_temporal_core_binding' --output-on-failure
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

For docs-only edits, a focused text search over this page and the feature index is sufficient to confirm the required public terms and links are present.
