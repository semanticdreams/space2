# Temporal Dependency/Data Packaging

## Purpose

The temporal dependency/data packaging foundation records planned third-party dependency families and reserves deterministic runtime data roots before ICU/CLDR, iCalendar, or holiday data is imported. This keeps future source and data imports reviewable, reproducible, and separate from the native temporal core.

## Current foundation scope

This foundation now includes the selected CLDR `cldr-seed` packaged data used by the first `Temporal.localization` and `Temporal.calendar` Fennel facades. It does not vendor ICU4C source, full generated ICU/CLDR data, libical source, generated holiday snapshots, native adapters, or holiday/runtime scheduler behavior.

## Dependency families

- ICU4C/CLDR: selected CLDR seed data is packaged under `assets/temporal/icu/cldr-seed/` for `Temporal.localization` and `Temporal.calendar`; full ICU4C source, generated CLDR data, and the native `temporal_localization` adapter remain future work.
- libical or equivalent vetted iCalendar library: planned RFC5545/ICS/VEVENT/VTIMEZONE candidate behind `temporal_ical` and `Temporal.ics`.
- Holiday snapshots: planned checked-in deterministic business-calendar data behind `Temporal.business-calendar`.

## Manifest locations

- `external/temporal/icu/DEPENDENCY_MANIFEST.json`
- `external/temporal/libical/DEPENDENCY_MANIFEST.json`
- `external/temporal/holidays/DEPENDENCY_MANIFEST.json`
- `assets/temporal/manifest.json`

## Runtime data roots

- `assets/temporal/icu/` including the packaged selected `cldr-seed` corpus at `assets/temporal/icu/cldr-seed/`
- `assets/temporal/ical/`
- `assets/temporal/holidays/`

The ICU root now contains the deterministic selected `cldr-seed` corpus with manifest provenance, supported locale/calendar lists, file metadata, and no-network metadata. Other reserved roots remain empty except for README files until future tracks add deterministic packaged data with source, license, version, checksum or reproducible provenance, and validation coverage.

## No-network invariant

Temporal parsing, formatting, scheduling, localization, iCalendar handling, migration, and business-calendar behavior must not fetch runtime network data. Every manifest must keep runtime network fetches disabled.

## Validation commands

```bash
python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q
make cmake
ctest --test-dir build -R '^test_temporal_dependency_manifests$' --output-on-failure
python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py scripts/tests/test_windows_build_host_setup.py -q
```

## Future source/data import rule

A future track that imports source or generated data must update the relevant manifest from `planned` to `vendored` or `packaged`, add exact provenance, expand validation, and keep the native temporal core independent from ICU, iCalendar, holiday, provider, and product scheduling policy. The current CLDR seed packaged-data status does not enable `SPACE_TEMPORAL_ENABLE_ICU_ADAPTER`; full ICU4C source/generated data and adapter build strategy remain future work.
