# Temporal Dependency/Data Packaging

## Purpose

The temporal dependency/data packaging foundation records planned third-party dependency families and reserves deterministic runtime data roots before ICU/CLDR, iCalendar, or holiday data is imported. This keeps future source and data imports reviewable, reproducible, and separate from the native temporal core.

## Current foundation scope

This foundation now includes the selected CLDR `cldr-seed` packaged data used by the first `Temporal.localization` and `Temporal.calendar` Fennel facades, the generated `US-FED` holiday seed used by `Temporal.business-calendar`, and the hand-authored natural phrase seed used by `Temporal.natural`. It does not vendor ICU4C source, full generated ICU/CLDR data, libical source, native adapters, broader holiday corpora, broad natural-language grammar data, or runtime scheduler behavior.

## Dependency families

- ICU4C/CLDR: selected CLDR seed data is packaged under `assets/temporal/icu/cldr-seed/` for `Temporal.localization` and `Temporal.calendar`; full ICU4C source, generated CLDR data, and the native `temporal_localization` adapter remain future work.
- libical or equivalent vetted iCalendar library: planned RFC5545/ICS/VEVENT/VTIMEZONE candidate behind `temporal_ical` and `Temporal.ics`.
- Holiday snapshots: packaged checked-in deterministic `US-FED` 2026-2027 business-calendar seed data under `assets/temporal/holidays/us-federal-seed/` behind `Temporal.business-calendar`.
- Natural-language phrase corpora: packaged checked-in deterministic `natural-phrase-seed` data under `assets/temporal/natural/seed/` behind `Temporal.natural` and provider `space.temporal.natural-seed`.

## Manifest locations

- `external/temporal/icu/DEPENDENCY_MANIFEST.json`
- `external/temporal/libical/DEPENDENCY_MANIFEST.json`
- `external/temporal/holidays/DEPENDENCY_MANIFEST.json`
- `assets/temporal/manifest.json`

## Runtime data roots

- `assets/temporal/icu/` including the packaged selected `cldr-seed` corpus at `assets/temporal/icu/cldr-seed/`
- `assets/temporal/ical/`
- `assets/temporal/holidays/`
- `assets/temporal/natural/` including the packaged selected natural phrase corpus at `assets/temporal/natural/seed/`

The ICU root now contains the deterministic selected `cldr-seed` corpus with manifest provenance, supported locale/calendar lists, file metadata, and no-network metadata. The holidays root now contains the deterministic packaged `us-federal-holidays-seed` corpus at `assets/temporal/holidays/us-federal-seed/`, with manifest provenance, exact `US-FED` support, 2026-2027 year range, weekend policy, generated `holidays.json`, and no-network metadata. The natural root now contains the deterministic packaged `natural-phrase-seed` corpus at `assets/temporal/natural/seed/`, with manifest provenance, exact `en-US`, `fr-FR`, and `ja-JP` locale support, initial phrase-family scope, `phrases.json`, and no-network metadata. Other reserved roots remain empty except for README files until future tracks add deterministic packaged data with source, license, version, checksum or reproducible provenance, and validation coverage.

## No-network invariant

Temporal parsing, formatting, scheduling, localization, iCalendar handling, migration, and business-calendar behavior must not fetch runtime network data. Every manifest must keep runtime network fetches disabled.

The holiday dependency manifest is `packaged`, not `vendored`: Space ships a
curated JSON snapshot, not a holiday-library source import. Expanding beyond the
initial `US-FED` 2026-2027 seed requires updated source/provenance review,
regeneration, and validator coverage before runtime exposure.

## Validation commands

```bash
python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q
make cmake
ctest --test-dir build -R '^test_temporal_dependency_manifests$' --output-on-failure
python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py scripts/tests/test_windows_build_host_setup.py -q
```

## Future source/data import rule

A future track that imports source or generated data must update the relevant manifest from `planned` to `vendored` or `packaged`, add exact provenance, expand validation, and keep the native temporal core independent from ICU, iCalendar, holiday, provider, and product scheduling policy. The current CLDR seed packaged-data status does not enable `SPACE_TEMPORAL_ENABLE_ICU_ADAPTER`; full ICU4C source/generated data and adapter build strategy remain future work.
