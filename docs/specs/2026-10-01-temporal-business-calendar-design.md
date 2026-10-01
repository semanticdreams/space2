# Temporal Business Calendar Design

## Purpose

Track 9 adds a production `Temporal.business-calendar` surface for deterministic holiday lookup and business-day arithmetic. It closes the business and holiday calendar category in the temporal roadmap with a deliberately small packaged corpus, public docs, focused tests, and an extension path for later jurisdictions.

## Invariants

- Runtime temporal work must not fetch network data.
- Business days are policy/calendar concepts, not exact `Duration` values.
- Exact `Duration` remains nanoseconds-only; business-day arithmetic uses plain-date day stepping.
- Holiday policy must not enter native temporal primitives, timezone conversion, ICU/CLDR presentation, recurrence policy, or scheduler semantics.
- All option keys are canonical; unsupported keys and unsupported data fail loudly.
- No host-local timezone, locale, or holiday defaults are allowed.

## Design choice

Use a checked-in deterministic holiday seed dataset and a pure Fennel facade.

### Considered approaches

1. **Checked-in seed data with pure Fennel facade — selected.**
   - Pros: deterministic, no network, small reviewable scope, satisfies packaged-data acceptance, works with current asset/runtime packaging, and keeps the native core independent.
   - Cons: initial jurisdiction/year coverage is intentionally small.
2. **Vendor a broad holiday library now.**
   - Pros: broad coverage sooner.
   - Cons: dependency/license/build review is larger than this PR-sized track, and runtime integration choices would obscure the core API shape.
3. **Rules-only runtime generation with no checked-in snapshot.**
   - Pros: minimal data files.
   - Cons: does not satisfy the roadmap's deterministic packaged holiday snapshot gate and weakens fixture/provenance evidence.

## Initial packaged corpus

- Dataset id: `us-federal-holidays-seed`.
- Provider id: `space.temporal.us-federal-holidays`.
- Jurisdiction: `US-FED` only.
- Year range: observed holiday dates in calendar years `2026` and `2027`.
- Weekend policy: ISO weekdays `6` and `7` are non-business days.
- Source basis: U.S. federal holiday rules from 5 U.S.C. § 6103 plus OPM federal holiday calendars for 2026 and 2027.
- License/provenance: U.S. Government/public-domain source material. If implementation cannot document this provenance clearly, it must stop for human review rather than substituting an unreviewed data source.
- Generation command: `python3 scripts/generate-temporal-us-federal-holidays.py --start-year 2026 --end-year 2027 --output assets/temporal/holidays/us-federal-seed/holidays.json`.

The checked-in data lives under `assets/temporal/holidays/us-federal-seed/`:

- `manifest.json` records schema version, provider id, supported jurisdictions, year range, source/provenance, no-network runtime invariant, and generator command.
- `holidays.json` records jurisdiction order, weekend ISO weekdays, year range, and holiday records with canonical dates and observed dates.

`external/temporal/holidays/DEPENDENCY_MANIFEST.json` becomes `packaged`, not `vendored`: the runtime ships a curated data snapshot, not a holiday-library source import. `assets/temporal/manifest.json` lists the holiday dataset beside the existing CLDR seed dataset.

## Public API

`Temporal.business-calendar` exposes these operations:

- `supported-jurisdictions() -> array<string>`
- `holidays(options) -> array<table>` where `options` is `{:jurisdiction string, :year integer}`
- `is-holiday(plain, options) -> boolean` where `options` is `{:jurisdiction string}`
- `is-business-day(plain, options) -> boolean` where `options` is `{:jurisdiction string}`
- `add-business-days(plain, count, options) -> PlainDateTime` where `count` is an integer and `options` is `{:jurisdiction string}`
- `business-days-between(start, end, options) -> integer` where the range is half-open `[start, end)` and `options` is `{:jurisdiction string}`

`plain`, `start`, and `end` are `PlainDateTime` values. Date predicates and arithmetic use only the ISO date portion; the returned `PlainDateTime` from `add-business-days` preserves the input time fields while moving the date by whole ISO days.

## Holiday record shape

Public holiday records returned from `holidays` include:

- `:jurisdiction` — currently `"US-FED"`.
- `:year` — calendar year containing the observed date.
- `:id` — stable lowercase identifier such as `"independence-day"`.
- `:name` — English source name.
- `:date` — statutory ISO date.
- `:observed-date` — observed ISO date.
- `:observed?` — true when `:observed-date` differs from `:date`.

Returned arrays and records are defensive copies so callers cannot mutate cached seed state.

## Error handling

The facade and loader fail loudly for:

- missing `SPACE_ASSETS_PATH` or missing packaged files;
- malformed manifests, mismatched provider ids, non-unique observed dates, unsupported schema versions, invalid year ranges, or network-enabled metadata;
- unsupported jurisdictions or years;
- unknown option keys;
- non-integer `:year` or business-day counts;
- invalid `PlainDateTime` inputs;
- descending `business-days-between` ranges.

Unsupported jurisdictions and years are errors, not false holiday results. This avoids silent scheduling mistakes.

## Provider extension path

The existing `Temporal.providers` registry already accepts providers with `:business-calendar` operational fields. This track adds a dispatcher:

`Temporal.providers.business-calendar(operation, request)`

The dispatcher searches providers with `:business-calendar` capability using deterministic priority/id ordering. Providers may expose either:

- a function: `provider.business-calendar(operation, request)`; or
- a table of handlers: `provider.business-calendar[operation](request)`.

Provider dispatch is an extension seam only. The built-in `Temporal.business-calendar` facade remains deterministic over the packaged seed and is not auto-overridden by registered providers.

## Data flow

1. `holiday-seed` reads `assets/temporal/holidays/us-federal-seed/manifest.json` and `holidays.json` through the normal asset path.
2. The loader validates metadata and records once, caches immutable internal data, and returns defensive copies.
3. `Temporal.business-calendar` validates public inputs and delegates holiday lookup to the loader.
4. Business-day arithmetic steps one ISO date at a time with `PlainDateTime:add-days`, excluding weekends and observed holidays for the requested jurisdiction.
5. Provider-registry dispatch is separate and explicit through `Temporal.providers.business-calendar`.

## Tests and acceptance evidence

Focused acceptance requires:

- holiday seed manifest/data validator tests;
- focused Fennel loader/facade tests;
- exact fixture tests for `US-FED` 2026 and 2027;
- observed-holiday tests for Independence Day 2026, Juneteenth 2027, Independence Day 2027, and Christmas 2027;
- business-day arithmetic tests for weekends, observed holidays, zero-day identity, positive/negative addition, and half-open days-between;
- provider dispatcher tests for function providers, table providers, deterministic ordering, invalid requests/operations, provider errors, and missing handlers;
- public export smoke tests and fast-suite registration.

Validation commands:

```bash
make fennel-check
make constraints
python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-business-calendar:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-provider-registry:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Run `make build` first if `./build/space` is missing or stale.

## Out of scope

- Jurisdictions beyond `US-FED`.
- Years outside `2026` and `2027`.
- Regional/state holidays, market/exchange calendars, school calendars, custom weekends, partial business days, business hours, settlement calendars, and locale display names.
- Runtime network data updates.
- Vendored holiday source libraries or native holiday adapters.
- Scheduler integration and natural-language business-date parsing.
- Automatic provider override of the built-in facade.

Future corpus expansion can add jurisdictions and year windows by extending the packaged seed and manifest evidence without changing the public architecture unless a new capability category is required.
