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
