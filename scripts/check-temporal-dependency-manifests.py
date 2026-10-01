#!/usr/bin/env python3
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
REQUIRED_CLDR_SEED_FILES = ["locales.json", "calendars.json"]
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
