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


def test_empty_dependency_manifest_reports_missing_required_fields(tmp_path):
    checker = load_checker()
    root = copy_foundation(tmp_path)
    path = root / "external/temporal/icu/DEPENDENCY_MANIFEST.json"
    path.write_text("{}\n")
    errors = checker.validate_repo(root)
    assert any("missing required field schema_version" in error for error in errors)
    assert any("missing required field runtime" in error for error in errors)
    assert any("runtime.network_fetch_allowed must be false" in error for error in errors)


def test_empty_runtime_manifest_reports_missing_policy_fields(tmp_path):
    checker = load_checker()
    root = copy_foundation(tmp_path)
    path = root / "assets/temporal/manifest.json"
    path.write_text("{}\n")
    errors = checker.validate_repo(root)
    assert any("runtime_network_fetch_allowed must be false" in error for error in errors)
    assert any("packaged_data_sets must be an array" in error for error in errors)


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
    data["status"] = "planned"
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


def test_runtime_manifest_requires_packaged_seed_files(tmp_path):
    checker = load_checker()
    root = copy_foundation(tmp_path)
    (root / "assets/temporal/icu/cldr-seed/locales.json").unlink()
    errors = checker.validate_repo(root)
    assert any(
        "packaged data file does not exist" in error and "locales.json" in error
        for error in errors
    )


def test_runtime_manifest_requires_seed_files_even_when_file_list_omits_them(tmp_path):
    checker = load_checker()
    root = copy_foundation(tmp_path)
    path = root / "assets/temporal/manifest.json"
    data = json.loads(path.read_text())
    data["packaged_data_sets"][0]["files"] = ["calendars.json"]
    path.write_text(json.dumps(data, indent=2) + "\n")
    (root / "assets/temporal/icu/cldr-seed/locales.json").unlink()
    errors = checker.validate_repo(root)
    assert any(
        "packaged data file does not exist" in error and "locales.json" in error
        for error in errors
    )


def test_runtime_packaged_data_set_network_fetch_is_forbidden(tmp_path):
    checker = load_checker()
    root = copy_foundation(tmp_path)
    path = root / "assets/temporal/manifest.json"
    data = json.loads(path.read_text())
    data["packaged_data_sets"][0]["runtime_network_fetch_allowed"] = True
    path.write_text(json.dumps(data, indent=2) + "\n")
    errors = checker.validate_repo(root)
    assert any(
        "packaged_data_sets[0].runtime_network_fetch_allowed must be false" in error
        for error in errors
    )


def test_cldr_seed_manifest_supported_lists_match_data(tmp_path):
    checker = load_checker()
    root = copy_foundation(tmp_path)
    path = root / "assets/temporal/icu/cldr-seed/manifest.json"
    data = json.loads(path.read_text())
    data["supported_locales"] = ["en-US"]
    path.write_text(json.dumps(data, indent=2) + "\n")
    errors = checker.validate_repo(root)
    assert any(
        "cldr-seed supported_locales must match locales.json locale_order" in error
        for error in errors
    )


def test_icu_manifest_is_packaged_for_cldr_seed():
    path = REPO_ROOT / "external/temporal/icu/DEPENDENCY_MANIFEST.json"
    data = json.loads(path.read_text())
    assert data["status"] == "packaged"
    assert data["version"] == "CLDR-46-selected-seed"
    assert data["source_url"] == "https://unicode.org/Public/cldr/46/"
    assert data["license"] == "Unicode License v3"
    assert data["runtime"]["network_fetch_allowed"] is False
    assert data["follow_up_gate"] == (
        "Full ICU4C source, generated CLDR data, license notice handling, and adapter "
        "build strategy remain future work before enabling temporal_localization native "
        "adapter support."
    )
