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


def install_valid_holiday_seed(root: Path) -> None:
    seed_root = root / "assets/temporal/holidays/us-federal-seed"
    seed_root.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schema_version": 1,
        "id": "us-federal-holidays-seed",
        "provider_id": "space.temporal.us-federal-holidays",
        "supported_jurisdictions": ["US-FED"],
        "year_start": 2026,
        "year_end": 2027,
        "runtime_network_fetch_allowed": False,
        "source": "U.S. federal holiday rules from 5 U.S.C. § 6103 and OPM calendars.",
        "provenance": "Public-domain U.S. Government source material.",
        "generator_command": (
            "python3 scripts/generate-temporal-us-federal-holidays.py --start-year 2026 "
            "--end-year 2027 --output assets/temporal/holidays/us-federal-seed/holidays.json"
        ),
    }
    holidays = {
        "schema_version": 1,
        "provider_id": "space.temporal.us-federal-holidays",
        "jurisdiction_order": ["US-FED"],
        "year_start": 2026,
        "year_end": 2027,
        "weekend_iso_weekdays": [6, 7],
        "jurisdictions": {
            "US-FED": {
                "name": "United States federal holidays",
                "years": {
                    "2026": [
                        {
                            "id": "new-years-day",
                            "name": "New Year's Day",
                            "date": "2026-01-01",
                            "observed_date": "2026-01-01",
                            "observed": False,
                        }
                    ],
                    "2027": [
                        {
                            "id": "new-years-day",
                            "name": "New Year's Day",
                            "date": "2027-01-01",
                            "observed_date": "2027-01-01",
                            "observed": False,
                        }
                    ],
                },
            }
        },
    }
    (seed_root / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (seed_root / "holidays.json").write_text(json.dumps(holidays, indent=2) + "\n", encoding="utf-8")
    runtime_path = root / "assets/temporal/manifest.json"
    runtime = json.loads(runtime_path.read_text())
    runtime["packaged_data_sets"].append(
        {
            "id": "us-federal-holidays-seed",
            "provider_id": "space.temporal.us-federal-holidays",
            "version": "US-FED-2026-2027-seed",
            "root": "assets/temporal/holidays/us-federal-seed",
            "manifest": "assets/temporal/holidays/us-federal-seed/manifest.json",
            "runtime_network_fetch_allowed": False,
            "files": ["holidays.json"],
        }
    )
    runtime_path.write_text(json.dumps(runtime, indent=2) + "\n", encoding="utf-8")


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


def test_holiday_seed_requires_holidays_file(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    install_valid_holiday_seed(root)
    (root / "assets/temporal/holidays/us-federal-seed/holidays.json").unlink()
    errors = checker.validate_repo(root)
    assert any("holidays.json" in error for error in errors)


def test_holiday_seed_rejects_jurisdiction_mismatch(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    install_valid_holiday_seed(root)
    manifest_path = root / "assets/temporal/holidays/us-federal-seed/manifest.json"
    data = json.loads(manifest_path.read_text())
    data["supported_jurisdictions"] = ["CA-FED"]
    manifest_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("supported_jurisdictions" in error for error in errors)


def test_holiday_seed_rejects_runtime_network_fetch(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    install_valid_holiday_seed(root)
    manifest_path = root / "assets/temporal/holidays/us-federal-seed/manifest.json"
    data = json.loads(manifest_path.read_text())
    data["runtime_network_fetch_allowed"] = True
    manifest_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("runtime_network_fetch_allowed" in error for error in errors)


def test_holiday_seed_requires_record_fields(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    install_valid_holiday_seed(root)
    holidays_path = root / "assets/temporal/holidays/us-federal-seed/holidays.json"
    data = json.loads(holidays_path.read_text())
    del data["jurisdictions"]["US-FED"]["years"]["2026"][0]["observed_date"]
    holidays_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("observed_date" in error for error in errors)


def test_holiday_seed_rejects_duplicate_observed_dates(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    install_valid_holiday_seed(root)
    holidays_path = root / "assets/temporal/holidays/us-federal-seed/holidays.json"
    data = json.loads(holidays_path.read_text())
    duplicate = dict(data["jurisdictions"]["US-FED"]["years"]["2026"][0])
    duplicate["id"] = "duplicate-new-years-day"
    data["jurisdictions"]["US-FED"]["years"]["2026"].append(duplicate)
    holidays_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("duplicate observed_date" in error for error in errors)


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
