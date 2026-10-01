# Temporal Business Calendars

Space ships a deterministic `US-FED` holiday seed for the public
`Temporal.business-calendar` facade. This layer covers observed holiday lookup
and business-day arithmetic as policy/calendar behavior above `PlainDateTime`;
it does not add business days to exact `Duration` values or native temporal
primitives.

## Public APIs

`(require :temporal)` exposes `Temporal.business-calendar` with these
operations:

- `supported-jurisdictions()` returns the supported jurisdiction ids as a
  defensive array. The initial result is exactly `"US-FED"`.
- `holidays({:jurisdiction "US-FED" :year 2026})` returns defensive holiday
  records for an exact supported jurisdiction/year pair.
- `is-holiday(plain-date-time, {:jurisdiction "US-FED"})` returns true when the
  ISO date portion matches an observed holiday date.
- `is-business-day(plain-date-time, {:jurisdiction "US-FED"})` excludes ISO
  Saturday/Sunday and observed holidays.
- `add-business-days(plain-date-time, count, {:jurisdiction "US-FED"})` steps
  whole ISO dates forward or backward by an integer business-day count and
  preserves the input time fields.
- `business-days-between(start, end, {:jurisdiction "US-FED"})` counts business
  days in the half-open range `[start, end)` and rejects descending ranges.

Options use canonical keys only. `holidays` accepts exactly `:jurisdiction` and
`:year`; predicate and arithmetic operations accept exactly `:jurisdiction`.
Unknown option keys, invalid `PlainDateTime` inputs, non-integer years, and
non-integer business-day counts fail loudly.

## Supported seed corpus

The initial packaged corpus is intentionally finite:

- Dataset id: `us-federal-holidays-seed`.
- Provider id: `space.temporal.us-federal-holidays`.
- Jurisdiction: exactly `US-FED`.
- Years: observed holiday dates in calendar years `2026` and `2027` only.
- Weekend policy: ISO weekdays `6` and `7`.

Unsupported jurisdictions and years are errors rather than false holiday results.
There is no host-local jurisdiction, locale, timezone, or holiday default.

## Holiday records and observed policy

Holiday records returned from `holidays` include `:jurisdiction`, `:year`,
`:id`, `:name`, `:date`, `:observed-date`, and `:observed?`. The statutory
`:date` may differ from `:observed-date` when a U.S. federal holiday falls on a
weekend. Public lookup and business-day arithmetic use observed dates.

Fixture evidence includes observed cases for Independence Day 2026
(`2026-07-04` observed on `2026-07-03`), Juneteenth 2027 (`2027-06-19` observed
on `2027-06-18`), Independence Day 2027 (`2027-07-04` observed on
`2027-07-05`), and Christmas Day 2027 (`2027-12-25` observed on `2027-12-24`).
The 2027 corpus also includes New Year's Day 2028 observed on `2027-12-31`
because the observed date falls inside calendar year 2027.

## Packaged data and provenance

The data is checked in under `assets/temporal/holidays/us-federal-seed/`:

- `manifest.json` records schema version, `US-FED` support, year range,
  no-network metadata, source/provenance text, and generator command.
- `holidays.json` records jurisdiction order, weekend ISO weekdays, year range,
  and holiday records.

The seed is generated from public-domain U.S. Government source material: U.S.
federal holiday rules in 5 U.S.C. § 6103 plus OPM federal holiday calendars for
2026 and 2027. Runtime temporal work does not fetch network data. The dependency
manifest in `external/temporal/holidays/DEPENDENCY_MANIFEST.json` is `packaged`,
not `vendored`, because Space ships a curated snapshot rather than a holiday
library source import.

## Provider extension path

`Temporal.providers.business-calendar(operation, request)` is the explicit
extension seam. Registered providers with the `business-calendar` capability may
expose either a function `provider.business-calendar(operation, request)` or a
table handler `provider.business-calendar[operation](request)`. The dispatcher
uses deterministic provider priority/id ordering.

The built-in `Temporal.business-calendar` facade remains deterministic over the
packaged seed and is not auto-overridden by registered providers.

## Out of scope

- Jurisdictions other than `US-FED`.
- Years outside observed holiday dates in calendar years `2026` and `2027`.
- Regional, market, school, settlement, custom-weekend, partial-day, or
  business-hours calendars.
- Runtime network updates, host-local defaults, scheduler semantics, natural
  language, recurrence policy, timezone conversion, ICU/CLDR presentation, or
  native holiday primitives.

## Validation commands

Use this focused ladder when changing the business-calendar surface:

```bash
rg "business-calendar|US-FED|holiday" docs/dev assets/temporal external/temporal
rg "runtime_network_fetch_allowed|network_fetch_allowed" assets/temporal external/temporal docs/dev/notes/temporal-dependency-data-packaging.md
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-business-calendar:main
```

Run `python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q`
when changing packaged holiday manifests or seed data.
