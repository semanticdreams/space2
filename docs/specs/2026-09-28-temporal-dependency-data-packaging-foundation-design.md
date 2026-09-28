# Temporal Dependency/Data Packaging Foundation Design

## Purpose

This track establishes the packaging foundation for the complete temporal platform before importing large standards libraries or generated data snapshots. It creates the dependency metadata layout, runtime data directories, validation tooling, and CMake/CTest hooks that later ICU/CLDR, iCalendar, and holiday-data tracks must satisfy.

The goal is to make future dependency imports reviewable and deterministic, not to vendor ICU4C, libical, generated ICU data, or holiday snapshots in this PR.

## Scope

In scope for this track:

- Dependency metadata directories under `external/temporal/` for ICU/CLDR, iCalendar, and holiday-data candidates.
- Runtime data directories under `assets/temporal/` so future data snapshots use existing asset copy/install/package paths.
- JSON manifests that record planned dependency candidates, adapter boundaries, runtime data roots, licenses, no-network policy, and future required provenance fields.
- A Python validator for temporal dependency/data manifests.
- Script-level tests for validator behavior.
- Lightweight CMake scaffolding that registers manifest paths, exposes OFF-by-default future adapter options, fails loudly if those options are enabled before adapters exist, and registers a focused CTest for the validator.
- Developer documentation linking the foundation from the complete temporal roadmap and acceptance matrix.

Out of scope for this track:

- Vendoring ICU4C source or generated ICU/CLDR data.
- Vendoring libical source or building iCalendar adapters.
- Generating or checking in holiday snapshots.
- Implementing `temporal_localization`, `temporal_ical`, `Temporal.ics`, `Temporal.localization`, `Temporal.calendar`, `Temporal.business-calendar`, recurrence changes, Fennel bindings, or runtime API behavior.
- Changing existing date/tz timezone packaging.

## Dependency Direction

The approved candidate directions are:

- **ICU4C/CLDR** for localization, localized parsing/formatting, and non-Gregorian calendar support. The adapter boundary is `temporal_localization`; future public facades are `Temporal.localization` and `Temporal.calendar`. License metadata records Unicode License v3. Runtime data must be deterministic and packaged; runtime network fetches are forbidden.
- **libical or an equivalent vetted iCalendar library** for RFC5545/ICS/`VEVENT`/`VTIMEZONE` interoperability. The adapter boundary is `temporal_ical`; future public facade is `Temporal.ics`, with recurrence integration through `Temporal.recurrence` and `Temporal.recurrence-set`. License metadata records `MPL-2.0 OR LGPL-2.1` for libical unless a later spec chooses an equivalent alternative. Runtime network fetches are forbidden.
- **MIT-compatible checked-in generated holiday snapshots** for business and holiday calendars. The future public facade is `Temporal.business-calendar`. Candidate generation may use tools such as Python `holidays`/Vacanza or Workalendar in later tracks, but runtime data must be checked in with source/license/version/provenance and no runtime network fetches.

The exact ICU4C/CLDR version, libical version/build mode, holiday jurisdictions, year ranges, data source, and legal/build acceptance are track-level gates for later vendoring/data-import specs.

## Manifest Model

Each dependency family has a manifest at:

- `external/temporal/icu/DEPENDENCY_MANIFEST.json`
- `external/temporal/libical/DEPENDENCY_MANIFEST.json`
- `external/temporal/holidays/DEPENDENCY_MANIFEST.json`

Each manifest includes:

- `schema_version`: integer schema version, initially `1`.
- `id`: stable dependency family id.
- `status`: initially `planned`; later `vendored` or `packaged` when source/data is imported.
- `purpose`: short description of what the dependency family enables.
- `candidate`: chosen candidate direction, such as `ICU4C/CLDR`, `libical`, or `generated holiday snapshots`.
- `license_policy`: expected license or compatible-license policy.
- `adapter_boundary`: native adapter or Fennel facade boundary.
- `runtime_data_root`: repo-relative runtime data root under `assets/temporal/`.
- `runtime`: object containing `network_fetch_allowed: false`.
- `follow_up_gate`: finite decisions required before source/data import.

For `planned` manifests, exact `version`, `source_url`, and checksum may be absent because the future vendoring/data-import spec chooses them. For `vendored` or `packaged` manifests, the validator requires non-empty `version`, `source_url`, `license`, and either `checksum_sha256` or `reproducible_provenance`.

The aggregate runtime manifest lives at `assets/temporal/manifest.json` and includes:

- `schema_version`: `1`.
- `runtime_network_fetch_allowed`: `false`.
- `packaged_data_sets`: empty array in this foundation track.

## Runtime Data Layout

Future runtime data roots are reserved as:

- `assets/temporal/icu/`
- `assets/temporal/ical/`
- `assets/temporal/holidays/`

Each directory contains a README in this foundation track explaining that it is intentionally empty until a later reviewed source/data import. Keeping these roots under `assets/` lets existing asset copy/install/package behavior include future deterministic data without inventing a separate packaging path.

## Validator

Create `scripts/check-temporal-dependency-manifests.py` with:

- `validate_repo(repo_root: pathlib.Path) -> list[str]`, returning validation error strings.
- CLI option `--repo-root`, defaulting to the current working directory.
- nonzero exit when validation errors exist.
- stderr output for validation errors.

The validator checks:

- all required dependency manifests exist;
- `assets/temporal/manifest.json` exists;
- no dependency or runtime manifest allows runtime network fetches;
- required fields exist for planned manifests;
- packaged/vendored manifests include version, source URL, license, and checksum/provenance;
- every dependency manifest's `runtime_data_root` exists in the repo.

Script tests live in `scripts/tests/test_temporal_dependency_manifests.py` and cover missing manifests, forbidden network fetches, planned manifest leniency for future version/checksum choices, and stricter packaged/vendored requirements.

## CMake and CTest Scaffolding

Create `cmake/temporal-deps.cmake` and include it from the root `CMakeLists.txt` near existing dependency setup.

The CMake scaffold provides:

- canonical variables for temporal dependency manifests and runtime data roots;
- configure-time existence checks for foundation manifest files;
- options `SPACE_TEMPORAL_ENABLE_ICU_ADAPTER` and `SPACE_TEMPORAL_ENABLE_ICAL_ADAPTER`, both default `OFF`;
- clear fatal errors if either adapter option is enabled before a later adapter/vendoring track provides implementation;
- CTest registration for `test_temporal_dependency_manifests` using the Python validator.

Default configuration must continue to succeed. Enabling future adapter options before implementation must fail loudly and intentionally.

## Error Handling

- Missing manifests or runtime roots are validation errors.
- Any manifest allowing runtime network fetches is a validation error.
- Packaged/vendored manifests without provenance are validation errors.
- Premature CMake adapter enablement is a configure-time fatal error with instructions to wait for the relevant adapter track.
- Existing tzdata packaging and runtime errors are unchanged.

## Testing and Acceptance

Required local validation for this track:

- `python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q`
- `make cmake`
- `ctest --test-dir build -R '^test_temporal_dependency_manifests$' --output-on-failure`
- `python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py scripts/tests/test_windows_build_host_setup.py -q`

Acceptance criteria:

- Developer docs explain that this foundation is metadata/layout/scaffolding only.
- Dependency manifests and runtime data roots exist.
- Manifest validator passes on the repo and fails on representative invalid fixtures in tests.
- CMake default configure succeeds.
- Focused CTest is registered and passes.
- Future adapter options are OFF by default and fail loudly when prematurely enabled.
- No ICU/libical source, source archives, generated ICU data, or holiday snapshots are added.
- Existing date/tz timezone packaging remains unchanged.

## Follow-Up Tracks

Later tracks may use this foundation to:

- choose and import a pinned ICU4C/CLDR source/data package;
- choose and import a pinned libical source/build configuration;
- generate and check in approved holiday snapshots;
- implement native adapters and Fennel facades.

Those tracks must update manifests from `planned` to `vendored` or `packaged`, add exact provenance, and expand validation before shipping runtime behavior.
