#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


REQUIRED_DEPENDENCY_MANIFESTS = [
    Path("external/temporal/icu/DEPENDENCY_MANIFEST.json"),
    Path("external/temporal/libical/DEPENDENCY_MANIFEST.json"),
    Path("external/temporal/holidays/DEPENDENCY_MANIFEST.json"),
]
RUNTIME_MANIFEST = Path("assets/temporal/manifest.json")
REQUIRED_CLDR_SEED_FILES = ["locales.json", "calendars.json"]
REQUIRED_HOLIDAY_SEED_FILES = ["holidays.json"]
HOLIDAY_SEED_ID = "us-federal-holidays-seed"
HOLIDAY_PROVIDER_ID = "space.temporal.us-federal-holidays"
HOLIDAY_JURISDICTIONS = ["US-FED"]
HOLIDAY_YEAR_START = 2026
HOLIDAY_YEAR_END = 2027
HOLIDAY_WEEKEND_ISO_WEEKDAYS = [6, 7]
HOLIDAY_RECORD_FIELDS = ["id", "name", "date", "observed_date", "observed"]
ISO_DATE_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}$")
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


def load_json(path: Path, errors: list[str]) -> dict | None:
    try:
        data = json.loads(path.read_text())
    except Exception as exc:
        errors.append(f"{path}: invalid JSON: {exc}")
        return None
    if not isinstance(data, dict):
        errors.append(f"{path}: top-level JSON value must be an object")
        return None
    return data


def require_false(value: object, path: Path, field: str, errors: list[str]) -> None:
    if value is not False:
        errors.append(f"{path}: {field} must be false")


def require_string(data: dict, key: str, path: Path, errors: list[str]) -> str | None:
    value = data.get(key)
    if not isinstance(value, str) or value == "":
        errors.append(f"{path}: {key} must be a non-empty string")
        return None
    return value


def require_string_array(data: dict, key: str, path: Path, errors: list[str]) -> list[str] | None:
    value = data.get(key)
    if not isinstance(value, list):
        errors.append(f"{path}: {key} must be an array of non-empty strings")
        return None
    strings: list[str] = []
    for index, item in enumerate(value):
        if not isinstance(item, str) or item == "":
            errors.append(f"{path}: {key}[{index}] must be a non-empty string")
            return None
        strings.append(item)
    return strings


def validate_dependency_manifest(repo_root: Path, rel_path: Path, errors: list[str]) -> None:
    path = repo_root / rel_path
    if not path.exists():
        errors.append(f"missing required manifest: {rel_path}")
        return
    data = load_json(path, errors)
    if data is None:
        return
    for field in REQUIRED_PLANNED_FIELDS:
        if field not in data:
            errors.append(f"{rel_path}: missing required field {field}")
    runtime = data.get("runtime")
    if not isinstance(runtime, dict):
        errors.append(f"{rel_path}: runtime must be an object")
        require_false(None, rel_path, "runtime.network_fetch_allowed", errors)
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
    if rel_path == Path("external/temporal/holidays/DEPENDENCY_MANIFEST.json") and status != "packaged":
        errors.append(f"{rel_path}: status must be packaged for holiday seed data")
    if status in {"vendored", "packaged"}:
        for field in ["version", "source_url", "license"]:
            if not data.get(field):
                errors.append(f"{rel_path}: {status} manifest requires non-empty {field}")
        if not data.get("checksum_sha256") and not data.get("reproducible_provenance"):
            errors.append(f"{rel_path}: {status} manifest requires checksum_sha256 or reproducible_provenance")


def validate_cldr_seed(repo_root: Path, dataset: dict, index: int, errors: list[str]) -> None:
    runtime_path = RUNTIME_MANIFEST
    prefix = f"packaged_data_sets[{index}]"
    root = require_string(dataset, "root", runtime_path, errors)
    manifest = require_string(dataset, "manifest", runtime_path, errors)
    files = require_string_array(dataset, "files", runtime_path, errors)

    root_path: Path | None = None
    if root is not None:
        root_path = repo_root / root
        if not root_path.exists():
            errors.append(f"{runtime_path}: {prefix}.root does not exist: {root}")
        elif not root_path.is_dir():
            errors.append(f"{runtime_path}: {prefix}.root must be a directory: {root}")

    manifest_path: Path | None = None
    if manifest is not None:
        manifest_path = repo_root / manifest
        if not manifest_path.exists():
            errors.append(f"{runtime_path}: {prefix}.manifest does not exist: {manifest}")

    if root_path is not None and root_path.is_dir() and files is not None:
        for file_index, filename in enumerate(files):
            file_path = root_path / filename
            if not file_path.exists():
                errors.append(
                    f"{runtime_path}: {prefix}.files[{file_index}] packaged data file does not exist: "
                    f"{root}/{filename}"
                )
        if files != REQUIRED_CLDR_SEED_FILES:
            errors.append(
                f"{runtime_path}: {prefix}.files must be exactly "
                f"{REQUIRED_CLDR_SEED_FILES!r} for cldr-seed"
            )
        listed_files = set(files)
        for filename in REQUIRED_CLDR_SEED_FILES:
            file_path = root_path / filename
            if filename not in listed_files and not file_path.exists():
                errors.append(
                    f"{runtime_path}: {prefix} required packaged data file does not exist: "
                    f"{root}/{filename}"
                )

    if manifest_path is None or not manifest_path.exists():
        return
    seed_manifest = load_json(manifest_path, errors)
    if seed_manifest is None:
        return

    require_false(
        seed_manifest.get("runtime_network_fetch_allowed"),
        manifest_path,
        "runtime_network_fetch_allowed",
        errors,
    )
    seed_id = require_string(seed_manifest, "id", manifest_path, errors)
    if seed_id is not None and seed_id != "cldr-seed":
        errors.append(f"{manifest_path}: id must be cldr-seed")
    provider_id = require_string(seed_manifest, "provider_id", manifest_path, errors)
    if provider_id is not None and provider_id != "space.temporal.cldr-seed":
        errors.append(f"{manifest_path}: provider_id must be space.temporal.cldr-seed")

    supported_locales = require_string_array(seed_manifest, "supported_locales", manifest_path, errors)
    supported_calendars = require_string_array(seed_manifest, "supported_calendars", manifest_path, errors)

    if root_path is None or not root_path.is_dir():
        return
    locales_path = root_path / "locales.json"
    calendars_path = root_path / "calendars.json"
    locales = load_json(locales_path, errors) if locales_path.exists() else None
    calendars = load_json(calendars_path, errors) if calendars_path.exists() else None

    if locales is not None and supported_locales is not None:
        locale_order = require_string_array(locales, "locale_order", locales_path, errors)
        if locale_order is not None and supported_locales != locale_order:
            errors.append(f"{manifest_path}: cldr-seed supported_locales must match locales.json locale_order")
    if calendars is not None and supported_calendars is not None:
        calendar_order = require_string_array(calendars, "calendar_order", calendars_path, errors)
        if calendar_order is not None and supported_calendars != calendar_order:
            errors.append(f"{manifest_path}: cldr-seed supported_calendars must match calendars.json calendar_order")


def validate_common_packaged_paths(
    repo_root: Path,
    dataset: dict,
    index: int,
    required_files: list[str],
    errors: list[str],
) -> tuple[Path | None, Path | None, list[str] | None]:
    runtime_path = RUNTIME_MANIFEST
    prefix = f"packaged_data_sets[{index}]"
    root = require_string(dataset, "root", runtime_path, errors)
    manifest = require_string(dataset, "manifest", runtime_path, errors)
    files = require_string_array(dataset, "files", runtime_path, errors)

    root_path: Path | None = None
    if root is not None:
        root_path = repo_root / root
        if not root_path.exists():
            errors.append(f"{runtime_path}: {prefix}.root does not exist: {root}")
        elif not root_path.is_dir():
            errors.append(f"{runtime_path}: {prefix}.root must be a directory: {root}")

    manifest_path: Path | None = None
    if manifest is not None:
        manifest_path = repo_root / manifest
        if not manifest_path.exists():
            errors.append(f"{runtime_path}: {prefix}.manifest does not exist: {manifest}")

    if root_path is not None and root_path.is_dir() and files is not None:
        for file_index, filename in enumerate(files):
            file_path = root_path / filename
            if not file_path.exists():
                errors.append(
                    f"{runtime_path}: {prefix}.files[{file_index}] packaged data file does not exist: "
                    f"{root}/{filename}"
                )
        if files != required_files:
            errors.append(
                f"{runtime_path}: {prefix}.files must be exactly {required_files!r} "
                f"for {dataset.get('id', '<unknown>')}"
            )
        listed_files = set(files)
        for filename in required_files:
            file_path = root_path / filename
            if filename not in listed_files or not file_path.exists():
                errors.append(
                    f"{runtime_path}: {prefix} required packaged data file does not exist: "
                    f"{root}/{filename}"
                )
    return root_path, manifest_path, files


def require_exact_int(data: dict, key: str, expected: int, path: Path, errors: list[str]) -> None:
    value = data.get(key)
    if value != expected:
        errors.append(f"{path}: {key} must be exactly {expected}")


def require_exact_array(data: dict, key: str, expected: list, path: Path, errors: list[str]) -> list | None:
    value = data.get(key)
    if value != expected:
        errors.append(f"{path}: {key} must be exactly {expected!r}")
        return None
    return value


def validate_iso_date(value: object, path: Path, field: str, errors: list[str]) -> str | None:
    if not isinstance(value, str) or ISO_DATE_PATTERN.match(value) is None:
        errors.append(f"{path}: {field} must be an ISO date string YYYY-MM-DD")
        return None
    return value


def validate_holiday_records(holidays_path: Path, data: dict, errors: list[str]) -> None:
    jurisdictions = data.get("jurisdictions")
    if not isinstance(jurisdictions, dict):
        errors.append(f"{holidays_path}: jurisdictions must be an object")
        return
    jurisdiction_data = jurisdictions.get("US-FED")
    if not isinstance(jurisdiction_data, dict):
        errors.append(f"{holidays_path}: jurisdictions.US-FED must be an object")
        return
    if not isinstance(jurisdiction_data.get("name"), str) or jurisdiction_data.get("name") == "":
        errors.append(f"{holidays_path}: jurisdictions.US-FED.name must be a non-empty string")
    years = jurisdiction_data.get("years")
    if not isinstance(years, dict):
        errors.append(f"{holidays_path}: jurisdictions.US-FED.years must be an object")
        return
    expected_years = [str(year) for year in range(HOLIDAY_YEAR_START, HOLIDAY_YEAR_END + 1)]
    if list(years.keys()) != expected_years:
        errors.append(f"{holidays_path}: jurisdictions.US-FED.years keys must be exactly {expected_years!r}")
    for year in expected_years:
        records = years.get(year)
        if not isinstance(records, list):
            errors.append(f"{holidays_path}: jurisdictions.US-FED.years.{year} must be an array")
            continue
        observed_dates: set[str] = set()
        for index, item in enumerate(records):
            record_path = f"jurisdictions.US-FED.years.{year}[{index}]"
            if not isinstance(item, dict):
                errors.append(f"{holidays_path}: {record_path} must be an object")
                continue
            for field in HOLIDAY_RECORD_FIELDS:
                if field not in item:
                    errors.append(f"{holidays_path}: {record_path} missing required field {field}")
            for field in ["id", "name"]:
                if field in item and (not isinstance(item.get(field), str) or item.get(field) == ""):
                    errors.append(f"{holidays_path}: {record_path}.{field} must be a non-empty string")
            date_value = validate_iso_date(item.get("date"), holidays_path, f"{record_path}.date", errors)
            observed_date = validate_iso_date(
                item.get("observed_date"), holidays_path, f"{record_path}.observed_date", errors
            )
            if isinstance(observed_date, str) and observed_date[:4] != year:
                errors.append(f"{holidays_path}: {record_path}.observed_date must be in calendar year {year}")
            if "observed" in item and not isinstance(item.get("observed"), bool):
                errors.append(f"{holidays_path}: {record_path}.observed must be a boolean")
            if date_value is not None and observed_date is not None and isinstance(item.get("observed"), bool):
                if item["observed"] != (date_value != observed_date):
                    errors.append(f"{holidays_path}: {record_path}.observed must match date/observed_date difference")
            if observed_date is not None:
                if observed_date in observed_dates:
                    errors.append(f"{holidays_path}: {record_path} duplicate observed_date {observed_date}")
                observed_dates.add(observed_date)


def validate_holiday_seed(repo_root: Path, dataset: dict, index: int, errors: list[str]) -> None:
    runtime_path = RUNTIME_MANIFEST
    prefix = f"packaged_data_sets[{index}]"
    provider_id = dataset.get("provider_id")
    if provider_id != HOLIDAY_PROVIDER_ID:
        errors.append(f"{runtime_path}: {prefix}.provider_id must be {HOLIDAY_PROVIDER_ID}")
    version = dataset.get("version")
    if version != "US-FED-2026-2027-seed":
        errors.append(f"{runtime_path}: {prefix}.version must be US-FED-2026-2027-seed")
    root = dataset.get("root")
    if root != "assets/temporal/holidays/us-federal-seed":
        errors.append(f"{runtime_path}: {prefix}.root must be assets/temporal/holidays/us-federal-seed")
    manifest = dataset.get("manifest")
    if manifest != "assets/temporal/holidays/us-federal-seed/manifest.json":
        errors.append(
            f"{runtime_path}: {prefix}.manifest must be assets/temporal/holidays/us-federal-seed/manifest.json"
        )
    root_path, manifest_path, _ = validate_common_packaged_paths(
        repo_root, dataset, index, REQUIRED_HOLIDAY_SEED_FILES, errors
    )
    if manifest_path is not None and manifest_path.exists():
        seed_manifest = load_json(manifest_path, errors)
        if seed_manifest is not None:
            require_exact_int(seed_manifest, "schema_version", 1, manifest_path, errors)
            seed_id = require_string(seed_manifest, "id", manifest_path, errors)
            if seed_id is not None and seed_id != HOLIDAY_SEED_ID:
                errors.append(f"{manifest_path}: id must be {HOLIDAY_SEED_ID}")
            seed_provider_id = require_string(seed_manifest, "provider_id", manifest_path, errors)
            if seed_provider_id is not None and seed_provider_id != HOLIDAY_PROVIDER_ID:
                errors.append(f"{manifest_path}: provider_id must be {HOLIDAY_PROVIDER_ID}")
            require_exact_array(seed_manifest, "supported_jurisdictions", HOLIDAY_JURISDICTIONS, manifest_path, errors)
            require_exact_int(seed_manifest, "year_start", HOLIDAY_YEAR_START, manifest_path, errors)
            require_exact_int(seed_manifest, "year_end", HOLIDAY_YEAR_END, manifest_path, errors)
            require_false(
                seed_manifest.get("runtime_network_fetch_allowed"),
                manifest_path,
                "runtime_network_fetch_allowed",
                errors,
            )
            require_string(seed_manifest, "source", manifest_path, errors)
            require_string(seed_manifest, "provenance", manifest_path, errors)
            generator_command = require_string(seed_manifest, "generator_command", manifest_path, errors)
            expected_command = (
                "python3 scripts/generate-temporal-us-federal-holidays.py --start-year 2026 "
                "--end-year 2027 --output assets/temporal/holidays/us-federal-seed/holidays.json"
            )
            if generator_command is not None and generator_command != expected_command:
                errors.append(f"{manifest_path}: generator_command must be exactly {expected_command!r}")
    if root_path is None or not root_path.is_dir():
        return
    holidays_path = root_path / "holidays.json"
    if not holidays_path.exists():
        return
    holidays = load_json(holidays_path, errors)
    if holidays is None:
        return
    require_exact_int(holidays, "schema_version", 1, holidays_path, errors)
    holidays_provider_id = require_string(holidays, "provider_id", holidays_path, errors)
    if holidays_provider_id is not None and holidays_provider_id != HOLIDAY_PROVIDER_ID:
        errors.append(f"{holidays_path}: provider_id must be {HOLIDAY_PROVIDER_ID}")
    require_exact_array(holidays, "jurisdiction_order", HOLIDAY_JURISDICTIONS, holidays_path, errors)
    require_exact_int(holidays, "year_start", HOLIDAY_YEAR_START, holidays_path, errors)
    require_exact_int(holidays, "year_end", HOLIDAY_YEAR_END, holidays_path, errors)
    require_exact_array(holidays, "weekend_iso_weekdays", HOLIDAY_WEEKEND_ISO_WEEKDAYS, holidays_path, errors)
    validate_holiday_records(holidays_path, holidays, errors)


def validate_runtime_manifest(repo_root: Path, errors: list[str]) -> None:
    path = repo_root / RUNTIME_MANIFEST
    if not path.exists():
        errors.append(f"missing required manifest: {RUNTIME_MANIFEST}")
        return
    data = load_json(path, errors)
    if data is None:
        return
    require_false(data.get("runtime_network_fetch_allowed"), RUNTIME_MANIFEST, "runtime_network_fetch_allowed", errors)
    if "packaged_data_sets" not in data or not isinstance(data.get("packaged_data_sets"), list):
        errors.append(f"{RUNTIME_MANIFEST}: packaged_data_sets must be an array")
        return
    for index, dataset in enumerate(data["packaged_data_sets"]):
        prefix = f"packaged_data_sets[{index}]"
        if not isinstance(dataset, dict):
            errors.append(f"{RUNTIME_MANIFEST}: {prefix} must be an object")
            continue
        require_false(
            dataset.get("runtime_network_fetch_allowed"),
            RUNTIME_MANIFEST,
            f"{prefix}.runtime_network_fetch_allowed",
            errors,
        )
        dataset_id = require_string(dataset, "id", RUNTIME_MANIFEST, errors)
        require_string(dataset, "provider_id", RUNTIME_MANIFEST, errors)
        require_string(dataset, "version", RUNTIME_MANIFEST, errors)
        require_string(dataset, "root", RUNTIME_MANIFEST, errors)
        require_string(dataset, "manifest", RUNTIME_MANIFEST, errors)
        require_string_array(dataset, "files", RUNTIME_MANIFEST, errors)
        if dataset_id == "cldr-seed":
            validate_cldr_seed(repo_root, dataset, index, errors)
        elif dataset_id == HOLIDAY_SEED_ID:
            validate_holiday_seed(repo_root, dataset, index, errors)


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
