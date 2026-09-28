# Temporal Dependency/Data Packaging Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the manifest-first dependency/data packaging foundation for ICU/CLDR, iCalendar, and holiday data without vendoring large third-party source or generated runtime data in this track.

**Architecture:** Add metadata and runtime-data roots first, then validate them with a Python checker and CTest hook. Keep native temporal primitives unchanged; future ICU/libical adapters and holiday snapshots will update the manifests from `planned` to `vendored` or `packaged` in later reviewed tracks. Default CMake configuration remains green while premature adapter options fail loudly.

**Tech Stack:** Markdown, JSON manifests, Python 3, pytest, CMake/CTest, existing Space asset packaging paths.

## Global Constraints

- This track establishes metadata/layout/scaffolding only.
- Do not vendor ICU4C source or generated ICU/CLDR data.
- Do not vendor libical source or build iCalendar adapters.
- Do not generate or check in holiday snapshots.
- Do not implement `temporal_localization`, `temporal_ical`, `Temporal.ics`, `Temporal.localization`, `Temporal.calendar`, `Temporal.business-calendar`, recurrence changes, Fennel bindings, or runtime API behavior.
- Do not change existing date/tz timezone packaging.
- Runtime parsing, formatting, scheduling, and migration must not perform network fetches.
- Third-party standards/data dependencies must be pinned, reviewed, packaged, and tested before future runtime use.
- For `planned` manifests, exact `version`, `source_url`, and checksum may be absent.
- For `vendored` or `packaged` manifests, require non-empty `version`, `source_url`, `license`, and either `checksum_sha256` or `reproducible_provenance`.
- CMake options `SPACE_TEMPORAL_ENABLE_ICU_ADAPTER` and `SPACE_TEMPORAL_ENABLE_ICAL_ADAPTER` must default `OFF` and must fail loudly if enabled in this foundation track.
- Required validation for the completed track: manifest pytest, `make cmake`, focused CTest, script-suite pytest with the Windows build host setup test, and no unintended third-party source/data additions.

---

## File Structure

- Create `docs/dev/notes/temporal-dependency-data-packaging.md`: developer operating contract for manifests, runtime data roots, no-network policy, update policy, and validation commands.
- Modify `docs/dev/features/temporal-complete-library.md`: link the new packaging note from the dependency policy section.
- Modify `docs/dev/features/temporal-complete-acceptance.md`: clarify that this foundation track delivers metadata/layout/scaffolding and that source/data imports remain later gates.
- Create `external/temporal/README.md`: explains metadata-first temporal dependency area.
- Create `external/temporal/icu/DEPENDENCY_MANIFEST.json`: planned ICU4C/CLDR manifest.
- Create `external/temporal/libical/DEPENDENCY_MANIFEST.json`: planned libical/iCalendar manifest.
- Create `external/temporal/holidays/DEPENDENCY_MANIFEST.json`: planned holiday snapshot manifest.
- Create `assets/temporal/README.md`: explains runtime temporal data roots.
- Create `assets/temporal/manifest.json`: aggregate runtime temporal data manifest.
- Create `assets/temporal/icu/README.md`, `assets/temporal/ical/README.md`, `assets/temporal/holidays/README.md`: intentionally-empty runtime roots.
- Create `scripts/check-temporal-dependency-manifests.py`: manifest validator CLI and importable function.
- Create `scripts/tests/test_temporal_dependency_manifests.py`: pytest coverage for validator behavior.
- Create `cmake/temporal-deps.cmake`: manifest path variables, existence checks, future adapter options, and CTest registration helper.
- Modify `CMakeLists.txt`: include temporal dependency scaffolding near existing dependency setup and register the focused CTest.

---

### Task 1: Developer Documentation Contract

**Files:**
- Create: `docs/dev/notes/temporal-dependency-data-packaging.md`
- Modify: `docs/dev/features/temporal-complete-library.md`
- Modify: `docs/dev/features/temporal-complete-acceptance.md`

**Interfaces:**
- Consumes: `docs/specs/2026-09-28-temporal-dependency-data-packaging-foundation-design.md`
- Produces: documentation that later manifest, validator, and CMake tasks must match.

- [ ] **Step 1: Create the developer note**

Create `docs/dev/notes/temporal-dependency-data-packaging.md` with these sections and content:

```markdown
# Temporal Dependency/Data Packaging

## Purpose

The temporal dependency/data packaging foundation records planned third-party dependency families and reserves deterministic runtime data roots before ICU/CLDR, iCalendar, or holiday data is imported. This keeps future source and data imports reviewable, reproducible, and separate from the native temporal core.

## Current foundation scope

This foundation track provides manifests, runtime data directories, validation tooling, and CMake/CTest scaffolding only. It does not vendor ICU4C, generated ICU/CLDR data, libical source, generated holiday snapshots, native adapters, Fennel bindings, or runtime temporal behavior.

## Dependency families

- ICU4C/CLDR: planned localization and non-Gregorian calendar candidate behind `temporal_localization`, `Temporal.localization`, and `Temporal.calendar`.
- libical or equivalent vetted iCalendar library: planned RFC5545/ICS/VEVENT/VTIMEZONE candidate behind `temporal_ical` and `Temporal.ics`.
- Holiday snapshots: planned checked-in deterministic business-calendar data behind `Temporal.business-calendar`.

## Manifest locations

- `external/temporal/icu/DEPENDENCY_MANIFEST.json`
- `external/temporal/libical/DEPENDENCY_MANIFEST.json`
- `external/temporal/holidays/DEPENDENCY_MANIFEST.json`
- `assets/temporal/manifest.json`

## Runtime data roots

- `assets/temporal/icu/`
- `assets/temporal/ical/`
- `assets/temporal/holidays/`

These directories are intentionally empty except for README files in the foundation track. Future tracks may add deterministic packaged data only after they update the manifests with source, license, version, checksum or reproducible provenance, and validation coverage.

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

A future track that imports source or generated data must update the relevant manifest from `planned` to `vendored` or `packaged`, add exact provenance, expand validation, and keep the native temporal core independent from ICU, iCalendar, holiday, provider, and product scheduling policy.
```

- [ ] **Step 2: Link the note from the complete roadmap**

In `docs/dev/features/temporal-complete-library.md`, append this sentence to the `## Dependency policy` section:

```markdown
The manifest and runtime data layout for these dependencies is defined in [Temporal Dependency/Data Packaging](../notes/temporal-dependency-data-packaging).
```

- [ ] **Step 3: Update acceptance matrix wording**

In `docs/dev/features/temporal-complete-acceptance.md`, change the `Dependency/data packaging` row's required evidence cell so it includes:

```markdown
manifest/layout foundation, no-network validator, CMake/CTest registration, version/license/source/checksum docs before source/data import
```

Keep the row's category, public surface, and track columns intact.

- [ ] **Step 4: Validate docs text**

Run:

```bash
rg "Temporal Dependency/Data Packaging|Current foundation scope|No-network invariant|Future source/data import rule" docs/dev/notes/temporal-dependency-data-packaging.md
rg "temporal-dependency-data-packaging|manifest/layout foundation|no-network validator" docs/dev/features/temporal-complete-library.md docs/dev/features/temporal-complete-acceptance.md
git diff --check
```

Expected: both `rg` commands find matches and `git diff --check` reports no whitespace errors.

- [ ] **Step 5: Commit Task 1**

Commit only Task 1 files:

```bash
git add docs/dev/notes/temporal-dependency-data-packaging.md docs/dev/features/temporal-complete-library.md docs/dev/features/temporal-complete-acceptance.md
git commit -m "docs(temporal): document dependency data packaging"
```

---

### Task 2: Manifests and Runtime Data Roots

**Files:**
- Create: `external/temporal/README.md`
- Create: `external/temporal/icu/DEPENDENCY_MANIFEST.json`
- Create: `external/temporal/libical/DEPENDENCY_MANIFEST.json`
- Create: `external/temporal/holidays/DEPENDENCY_MANIFEST.json`
- Create: `assets/temporal/README.md`
- Create: `assets/temporal/manifest.json`
- Create: `assets/temporal/icu/README.md`
- Create: `assets/temporal/ical/README.md`
- Create: `assets/temporal/holidays/README.md`

**Interfaces:**
- Consumes: docs from Task 1.
- Produces: manifest files and runtime roots consumed by `scripts/check-temporal-dependency-manifests.py` in Task 3 and CMake checks in Task 4.

- [ ] **Step 1: Create external metadata README**

Create `external/temporal/README.md`:

```markdown
# Temporal Dependency Metadata

This directory records temporal dependency-family metadata before large source or data imports occur. The foundation track contains manifests only. Future tracks may add vendored source after legal/build review and manifest updates.

Runtime data belongs under `assets/temporal/` so normal Space asset packaging can include deterministic snapshots.
```

- [ ] **Step 2: Create ICU manifest**

Create `external/temporal/icu/DEPENDENCY_MANIFEST.json`:

```json
{
  "schema_version": 1,
  "id": "icu-cldr",
  "status": "planned",
  "purpose": "Localization, localized temporal parsing/formatting, and non-Gregorian calendar data",
  "candidate": "ICU4C/CLDR",
  "license_policy": "Unicode License v3",
  "adapter_boundary": "temporal_localization",
  "public_surfaces": ["Temporal.localization", "Temporal.calendar"],
  "runtime_data_root": "assets/temporal/icu",
  "runtime": {
    "network_fetch_allowed": false
  },
  "follow_up_gate": "Choose exact ICU4C/CLDR version, data packaging mode, license notice handling, and adapter build strategy before importing source or data."
}
```

- [ ] **Step 3: Create libical manifest**

Create `external/temporal/libical/DEPENDENCY_MANIFEST.json`:

```json
{
  "schema_version": 1,
  "id": "libical",
  "status": "planned",
  "purpose": "RFC5545 recurrence, ICS, VEVENT, and VTIMEZONE interoperability",
  "candidate": "libical or equivalent vetted iCalendar library",
  "license_policy": "MPL-2.0 OR LGPL-2.1 for libical unless a later spec selects an equivalent alternative",
  "adapter_boundary": "temporal_ical",
  "public_surfaces": ["Temporal.ics", "Temporal.recurrence", "Temporal.recurrence-set"],
  "runtime_data_root": "assets/temporal/ical",
  "runtime": {
    "network_fetch_allowed": false
  },
  "follow_up_gate": "Choose exact iCalendar library/version, license compliance path, builtin timezone data mode, and adapter build strategy before importing source or data."
}
```

- [ ] **Step 4: Create holiday manifest**

Create `external/temporal/holidays/DEPENDENCY_MANIFEST.json`:

```json
{
  "schema_version": 1,
  "id": "holiday-snapshots",
  "status": "planned",
  "purpose": "Deterministic business and holiday calendar data snapshots",
  "candidate": "Generated checked-in snapshots from MIT-compatible sources such as Python holidays/Vacanza or Workalendar",
  "license_policy": "MIT-compatible checked-in generated snapshots only; avoid CC BY-SA or live API terms for runtime data",
  "adapter_boundary": "Temporal.business-calendar",
  "public_surfaces": ["Temporal.business-calendar"],
  "runtime_data_root": "assets/temporal/holidays",
  "runtime": {
    "network_fetch_allowed": false
  },
  "follow_up_gate": "Choose initial jurisdictions, year range, source package/version, license review result, and snapshot generation command before adding data."
}
```

- [ ] **Step 5: Create runtime data README and manifest**

Create `assets/temporal/README.md`:

```markdown
# Temporal Runtime Data

This directory reserves deterministic runtime data roots for the complete temporal library. The foundation track contains only metadata and README files. Future tracks may add packaged ICU/CLDR, iCalendar, or holiday data after manifest provenance is recorded and validation is expanded.
```

Create `assets/temporal/manifest.json`:

```json
{
  "schema_version": 1,
  "runtime_network_fetch_allowed": false,
  "packaged_data_sets": []
}
```

- [ ] **Step 6: Create runtime root README files**

Create `assets/temporal/icu/README.md`:

```markdown
# ICU/CLDR Runtime Data

Reserved for future deterministic ICU/CLDR runtime data. This foundation track intentionally does not include generated ICU data.
```

Create `assets/temporal/ical/README.md`:

```markdown
# iCalendar Runtime Data

Reserved for future deterministic iCalendar or VTIMEZONE runtime data. This foundation track intentionally does not include libical source or generated iCalendar data.
```

Create `assets/temporal/holidays/README.md`:

```markdown
# Holiday Runtime Data

Reserved for future deterministic holiday and business-calendar snapshots. This foundation track intentionally does not include generated holiday data.
```

- [ ] **Step 7: Validate no unintended source/data import**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
for root in [Path('external/temporal'), Path('assets/temporal')]:
    for path in sorted(root.rglob('*')):
        if path.is_file():
            print(path)
PY
```

Expected file list contains only the README, manifest, and `DEPENDENCY_MANIFEST.json` files created by this task.

- [ ] **Step 8: Commit Task 2**

Commit only Task 2 files:

```bash
git add external/temporal assets/temporal
git commit -m "chore(temporal): add dependency data manifests"
```

---

### Task 3: Manifest Validator and Tests

**Files:**
- Create: `scripts/check-temporal-dependency-manifests.py`
- Create: `scripts/tests/test_temporal_dependency_manifests.py`

**Interfaces:**
- Consumes:
  - `external/temporal/*/DEPENDENCY_MANIFEST.json`
  - `assets/temporal/manifest.json`
- Produces:
  - Python function `validate_repo(repo_root: pathlib.Path) -> list[str]`
  - CLI `python3 scripts/check-temporal-dependency-manifests.py --repo-root .`

- [ ] **Step 1: Write validator tests first**

Create `scripts/tests/test_temporal_dependency_manifests.py` with these test names and assertions:

```python
import importlib.util
import json
import shutil
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts" / "check-temporal-dependency-manifests.py"


def load_checker():
    spec = importlib.util.spec_from_file_location("temporal_manifest_checker", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def copy_foundation(tmp_path: Path) -> Path:
    root = tmp_path / "repo"
    for rel in ["external/temporal", "assets/temporal"]:
        src = REPO_ROOT / rel
        dst = root / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(src, dst)
    return root


def test_current_repo_manifests_are_valid():
    checker = load_checker()
    assert checker.validate_repo(REPO_ROOT) == []


def test_missing_dependency_manifest_fails(tmp_path):
    checker = load_checker()
    root = copy_foundation(tmp_path)
    (root / "external/temporal/icu/DEPENDENCY_MANIFEST.json").unlink()
    errors = checker.validate_repo(root)
    assert any("missing required manifest" in error and "icu" in error for error in errors)


def test_runtime_network_fetch_is_forbidden(tmp_path):
    checker = load_checker()
    root = copy_foundation(tmp_path)
    path = root / "external/temporal/libical/DEPENDENCY_MANIFEST.json"
    data = json.loads(path.read_text())
    data["runtime"]["network_fetch_allowed"] = True
    path.write_text(json.dumps(data, indent=2) + "\n")
    errors = checker.validate_repo(root)
    assert any("network_fetch_allowed must be false" in error for error in errors)


def test_planned_manifest_may_omit_version_and_checksum(tmp_path):
    checker = load_checker()
    root = copy_foundation(tmp_path)
    path = root / "external/temporal/icu/DEPENDENCY_MANIFEST.json"
    data = json.loads(path.read_text())
    data.pop("version", None)
    data.pop("checksum_sha256", None)
    data.pop("reproducible_provenance", None)
    path.write_text(json.dumps(data, indent=2) + "\n")
    assert checker.validate_repo(root) == []


def test_packaged_manifest_requires_provenance(tmp_path):
    checker = load_checker()
    root = copy_foundation(tmp_path)
    path = root / "external/temporal/holidays/DEPENDENCY_MANIFEST.json"
    data = json.loads(path.read_text())
    data["status"] = "packaged"
    data["version"] = "2026-test"
    data["source_url"] = "https://example.invalid/holidays"
    data["license"] = "MIT"
    data.pop("checksum_sha256", None)
    data.pop("reproducible_provenance", None)
    path.write_text(json.dumps(data, indent=2) + "\n")
    errors = checker.validate_repo(root)
    assert any("checksum_sha256 or reproducible_provenance" in error for error in errors)
```

- [ ] **Step 2: Run tests to confirm checker is missing**

Run:

```bash
python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q
```

Expected: fails because `scripts/check-temporal-dependency-manifests.py` does not exist yet.

- [ ] **Step 3: Implement the validator**

Create `scripts/check-temporal-dependency-manifests.py` with executable Python 3 code that:

```python
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


REQUIRED_DEPENDENCY_MANIFESTS = [
    Path("external/temporal/icu/DEPENDENCY_MANIFEST.json"),
    Path("external/temporal/libical/DEPENDENCY_MANIFEST.json"),
    Path("external/temporal/holidays/DEPENDENCY_MANIFEST.json"),
]
RUNTIME_MANIFEST = Path("assets/temporal/manifest.json")
REQUIRED_PLANNED_FIELDS = [
    "schema_version",
    "id",
    "status",
    "purpose",
    "candidate",
    "license_policy",
    "adapter_boundary",
    "runtime_data_root",
    "runtime",
    "follow_up_gate",
]


def load_json(path: Path, errors: list[str]) -> dict:
    try:
        data = json.loads(path.read_text())
    except Exception as exc:
        errors.append(f"{path}: invalid JSON: {exc}")
        return {}
    if not isinstance(data, dict):
        errors.append(f"{path}: top-level JSON value must be an object")
        return {}
    return data


def require_false(value: object, path: Path, field: str, errors: list[str]) -> None:
    if value is not False:
        errors.append(f"{path}: {field} must be false")


def validate_dependency_manifest(repo_root: Path, rel_path: Path, errors: list[str]) -> None:
    path = repo_root / rel_path
    if not path.exists():
        errors.append(f"missing required manifest: {rel_path}")
        return
    data = load_json(path, errors)
    if not data:
        return
    for field in REQUIRED_PLANNED_FIELDS:
        if field not in data:
            errors.append(f"{rel_path}: missing required field {field}")
    runtime = data.get("runtime")
    if not isinstance(runtime, dict):
        errors.append(f"{rel_path}: runtime must be an object")
    else:
        require_false(runtime.get("network_fetch_allowed"), rel_path, "runtime.network_fetch_allowed", errors)
    runtime_root = data.get("runtime_data_root")
    if isinstance(runtime_root, str):
        if not (repo_root / runtime_root).exists():
            errors.append(f"{rel_path}: runtime_data_root does not exist: {runtime_root}")
    else:
        errors.append(f"{rel_path}: runtime_data_root must be a string")
    status = data.get("status")
    if status not in {"planned", "vendored", "packaged"}:
        errors.append(f"{rel_path}: status must be planned, vendored, or packaged")
    if status in {"vendored", "packaged"}:
        for field in ["version", "source_url", "license"]:
            if not data.get(field):
                errors.append(f"{rel_path}: {status} manifest requires non-empty {field}")
        if not data.get("checksum_sha256") and not data.get("reproducible_provenance"):
            errors.append(f"{rel_path}: {status} manifest requires checksum_sha256 or reproducible_provenance")


def validate_runtime_manifest(repo_root: Path, errors: list[str]) -> None:
    path = repo_root / RUNTIME_MANIFEST
    if not path.exists():
        errors.append(f"missing required manifest: {RUNTIME_MANIFEST}")
        return
    data = load_json(path, errors)
    if not data:
        return
    require_false(data.get("runtime_network_fetch_allowed"), RUNTIME_MANIFEST, "runtime_network_fetch_allowed", errors)
    if "packaged_data_sets" not in data or not isinstance(data.get("packaged_data_sets"), list):
        errors.append(f"{RUNTIME_MANIFEST}: packaged_data_sets must be an array")


def validate_repo(repo_root: Path) -> list[str]:
    repo_root = repo_root.resolve()
    errors: list[str] = []
    for rel_path in REQUIRED_DEPENDENCY_MANIFESTS:
        validate_dependency_manifest(repo_root, rel_path, errors)
    validate_runtime_manifest(repo_root, errors)
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate temporal dependency/data manifests")
    parser.add_argument("--repo-root", default=".", help="Repository root to validate")
    args = parser.parse_args(argv)
    errors = validate_repo(Path(args.repo_root))
    for error in errors:
        print(error, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run validator tests**

Run:

```bash
python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q
python3 scripts/check-temporal-dependency-manifests.py --repo-root .
```

Expected: pytest passes and direct checker exits 0 with no output.

- [ ] **Step 5: Commit Task 3**

Commit only Task 3 files:

```bash
git add scripts/check-temporal-dependency-manifests.py scripts/tests/test_temporal_dependency_manifests.py
git commit -m "test(temporal): validate dependency manifests"
```

---

### Task 4: CMake and CTest Scaffolding

**Files:**
- Create: `cmake/temporal-deps.cmake`
- Modify: `CMakeLists.txt`

**Interfaces:**
- Consumes:
  - `scripts/check-temporal-dependency-manifests.py`
  - `external/temporal/*/DEPENDENCY_MANIFEST.json`
  - `assets/temporal/manifest.json`
- Produces:
  - CMake options `SPACE_TEMPORAL_ENABLE_ICU_ADAPTER` and `SPACE_TEMPORAL_ENABLE_ICAL_ADAPTER`, default `OFF`.
  - CTest `test_temporal_dependency_manifests`.

- [ ] **Step 1: Create temporal CMake helper**

Create `cmake/temporal-deps.cmake`:

```cmake
set(SPACE_TEMPORAL_DEPENDENCY_MANIFESTS
    "${CMAKE_CURRENT_SOURCE_DIR}/external/temporal/icu/DEPENDENCY_MANIFEST.json"
    "${CMAKE_CURRENT_SOURCE_DIR}/external/temporal/libical/DEPENDENCY_MANIFEST.json"
    "${CMAKE_CURRENT_SOURCE_DIR}/external/temporal/holidays/DEPENDENCY_MANIFEST.json"
)

set(SPACE_TEMPORAL_RUNTIME_MANIFEST
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/temporal/manifest.json")

foreach(SPACE_TEMPORAL_MANIFEST IN LISTS SPACE_TEMPORAL_DEPENDENCY_MANIFESTS)
    if(NOT EXISTS "${SPACE_TEMPORAL_MANIFEST}")
        message(FATAL_ERROR "Missing temporal dependency manifest: ${SPACE_TEMPORAL_MANIFEST}")
    endif()
endforeach()

if(NOT EXISTS "${SPACE_TEMPORAL_RUNTIME_MANIFEST}")
    message(FATAL_ERROR "Missing temporal runtime manifest: ${SPACE_TEMPORAL_RUNTIME_MANIFEST}")
endif()

option(SPACE_TEMPORAL_ENABLE_ICU_ADAPTER "Enable future ICU temporal adapter" OFF)
option(SPACE_TEMPORAL_ENABLE_ICAL_ADAPTER "Enable future iCalendar temporal adapter" OFF)

if(SPACE_TEMPORAL_ENABLE_ICU_ADAPTER)
    message(FATAL_ERROR "SPACE_TEMPORAL_ENABLE_ICU_ADAPTER is reserved for a later temporal localization adapter track; this foundation only validates manifests.")
endif()

if(SPACE_TEMPORAL_ENABLE_ICAL_ADAPTER)
    message(FATAL_ERROR "SPACE_TEMPORAL_ENABLE_ICAL_ADAPTER is reserved for a later temporal iCalendar adapter track; this foundation only validates manifests.")
endif()
```

- [ ] **Step 2: Include helper from root CMake**

Modify root `CMakeLists.txt` near existing dependency option/setup includes to add:

```cmake
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/temporal-deps.cmake)
```

Place it before targets that need tests registered and after `cmake_minimum_required` / project initialization so `${CMAKE_CURRENT_SOURCE_DIR}` is defined.

- [ ] **Step 3: Register focused CTest**

In root `CMakeLists.txt`, near other script or integration test registrations, add:

```cmake
add_test(
    NAME test_temporal_dependency_manifests
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/scripts/check-temporal-dependency-manifests.py --repo-root ${CMAKE_CURRENT_SOURCE_DIR}
)
```

If `Python3_EXECUTABLE` is not available at that point, add or move a `find_package(Python3 REQUIRED COMPONENTS Interpreter)` call using the existing repo pattern.

- [ ] **Step 4: Run configure validation**

Run:

```bash
make cmake
```

Expected: CMake configuration succeeds with default adapter options OFF.

- [ ] **Step 5: Run focused CTest**

Run:

```bash
ctest --test-dir build -R '^test_temporal_dependency_manifests$' --output-on-failure
```

Expected: the focused CTest passes.

- [ ] **Step 6: Verify adapter options fail loudly**

Run this in `/tmp/opencode` so the repo build directory is not disturbed:

```bash
cmake -S . -B /tmp/opencode/space-temporal-icu-option-check -DSPACE_TEMPORAL_ENABLE_ICU_ADAPTER=ON
```

Expected: command fails and stderr/stdout contains `SPACE_TEMPORAL_ENABLE_ICU_ADAPTER is reserved for a later temporal localization adapter track`.

Then run:

```bash
cmake -S . -B /tmp/opencode/space-temporal-ical-option-check -DSPACE_TEMPORAL_ENABLE_ICAL_ADAPTER=ON
```

Expected: command fails and stderr/stdout contains `SPACE_TEMPORAL_ENABLE_ICAL_ADAPTER is reserved for a later temporal iCalendar adapter track`.

- [ ] **Step 7: Commit Task 4**

Commit only Task 4 files:

```bash
git add cmake/temporal-deps.cmake CMakeLists.txt
git commit -m "build(temporal): register dependency manifest checks"
```

---

### Task 5: Final Validation and Acceptance

**Files:**
- No source edits expected. If validation reveals a defect in previous tasks, fix the defect in the owning file and report why the fix belongs to this track.

**Interfaces:**
- Consumes: Tasks 1-4 outputs.
- Produces: final local validation evidence for branch finishing.

- [ ] **Step 1: Run manifest pytest**

Run:

```bash
python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q
```

Expected: all tests pass.

- [ ] **Step 2: Run CMake configure**

Run with a 10 minute timeout:

```bash
make cmake
```

Expected: configuration succeeds.

- [ ] **Step 3: Run focused CTest**

Run:

```bash
ctest --test-dir build -R '^test_temporal_dependency_manifests$' --output-on-failure
```

Expected: focused CTest passes.

- [ ] **Step 4: Run related script tests**

Run:

```bash
python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py scripts/tests/test_windows_build_host_setup.py -q
```

Expected: both script test files pass.

- [ ] **Step 5: Verify no large dependency/data import**

Run:

```bash
git diff --name-only origin/main...HEAD
```

Expected changed file list contains docs, manifests, README files, the validator script/test, `cmake/temporal-deps.cmake`, and `CMakeLists.txt`; it does not contain ICU/libical source directories, source archives, generated ICU data files, or holiday snapshot files.

- [ ] **Step 6: Run whitespace check**

Run:

```bash
git diff origin/main...HEAD --check
```

Expected: no whitespace errors.

- [ ] **Step 7: Commit final validation fix only if needed**

If Steps 1-6 pass with no file edits, do not create an empty commit. If a validation defect required a file edit, commit the reviewed fix with:

Use `git status --short` to identify the edited file paths, stage only files that belong to this plan, and commit with:

```bash
git commit -m "fix(temporal): complete dependency manifest validation"
```

The final report must include all commands, results, and why this local validation covers the changed build/script/docs surface.
