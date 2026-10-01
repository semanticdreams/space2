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
    runtime["packaged_data_sets"] = [
        dataset
        for dataset in runtime["packaged_data_sets"]
        if dataset.get("id") != "us-federal-holidays-seed"
    ]
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


def install_valid_natural_seed(root: Path) -> None:
    seed_root = root / "assets/temporal/natural/seed"
    seed_root.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schema_version": 1,
        "id": "natural-phrase-seed",
        "provider_id": "space.temporal.natural-seed",
        "version": "natural-phrase-seed-2026-10-track10",
        "supported_locales": ["en-US", "fr-FR", "ja-JP"],
        "runtime_network_fetch_allowed": False,
        "source": "Hand-authored Space temporal natural-language seed corpus",
        "license": "Project license",
        "update_process": (
            "Update phrases.json and this manifest in the same reviewed change; runtime parsing must "
            "remain deterministic and offline."
        ),
    }
    phrases = {
        "schema_version": 1,
        "provider_id": "space.temporal.natural-seed",
        "version": "natural-phrase-seed-2026-10-track10",
        "locale_order": ["en-US", "fr-FR", "ja-JP"],
        "weekday_symbols": ["mo", "tu", "we", "th", "fr", "sa", "su"],
        "locales": {
            locale: {
                "relative_literals": [{"phrase_id": f"{locale}-today", "text": "today", "offset_days": 0}],
                "relative_count_offsets": [
                    {"phrase_id": f"{locale}-in-count-days", "pattern": "in {count} days", "unit": "day"}
                ],
                "next_weekday": [{"phrase_id": f"{locale}-next-monday", "text": "next monday", "weekday": "mo"}],
                "weekly_weekday_recurrence": [
                    {"phrase_id": f"{locale}-every-monday", "text": "every monday", "weekday": "mo"}
                ],
                "bare_weekday_ambiguity": [
                    {"phrase_id": f"{locale}-bare-monday", "text": "monday", "weekday": "mo"}
                ],
            }
            for locale in ["en-US", "fr-FR", "ja-JP"]
        },
    }
    (seed_root / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (seed_root / "phrases.json").write_text(json.dumps(phrases, indent=2) + "\n", encoding="utf-8")
    runtime_path = root / "assets/temporal/manifest.json"
    runtime = json.loads(runtime_path.read_text())
    runtime["packaged_data_sets"] = [
        dataset
        for dataset in runtime["packaged_data_sets"]
        if dataset.get("id") != "natural-phrase-seed"
    ]
    runtime["packaged_data_sets"].append(
        {
            "id": "natural-phrase-seed",
            "provider_id": "space.temporal.natural-seed",
            "version": "natural-phrase-seed-2026-10-track10",
            "root": "assets/temporal/natural/seed",
            "manifest": "assets/temporal/natural/seed/manifest.json",
            "runtime_network_fetch_allowed": False,
            "files": ["phrases.json"],
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


def test_runtime_manifest_requires_holiday_seed_dataset_entry(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    runtime_path = root / "assets/temporal/manifest.json"
    data = json.loads(runtime_path.read_text())
    data["packaged_data_sets"] = [
        dataset
        for dataset in data["packaged_data_sets"]
        if dataset.get("id") != "us-federal-holidays-seed"
    ]
    runtime_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("us-federal-holidays-seed" in error and "exactly one" in error for error in errors)


def test_runtime_manifest_rejects_duplicate_holiday_seed_dataset_entries(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    runtime_path = root / "assets/temporal/manifest.json"
    data = json.loads(runtime_path.read_text())
    holiday_dataset = next(
        dataset
        for dataset in data["packaged_data_sets"]
        if dataset.get("id") == "us-federal-holidays-seed"
    )
    data["packaged_data_sets"].append(dict(holiday_dataset))
    runtime_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("us-federal-holidays-seed" in error and "exactly one" in error for error in errors)


def test_holiday_seed_rejects_unsupported_jurisdiction_data(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    install_valid_holiday_seed(root)
    holidays_path = root / "assets/temporal/holidays/us-federal-seed/holidays.json"
    data = json.loads(holidays_path.read_text())
    data["jurisdictions"]["CA-FED"] = {
        "name": "Unsupported Canadian federal holidays",
        "years": {"2026": [], "2027": []},
    }
    holidays_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("jurisdictions keys" in error and "US-FED" in error for error in errors)


def test_holiday_seed_rejects_jurisdiction_order_policy_change(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    install_valid_holiday_seed(root)
    holidays_path = root / "assets/temporal/holidays/us-federal-seed/holidays.json"
    data = json.loads(holidays_path.read_text())
    data["jurisdiction_order"] = ["CA-FED"]
    holidays_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("jurisdiction_order" in error and "US-FED" in error for error in errors)


def test_holiday_seed_rejects_year_start_policy_change(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    install_valid_holiday_seed(root)
    holidays_path = root / "assets/temporal/holidays/us-federal-seed/holidays.json"
    data = json.loads(holidays_path.read_text())
    data["year_start"] = 2025
    holidays_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("year_start" in error and "2026" in error for error in errors)


def test_holiday_seed_rejects_year_end_policy_change(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    install_valid_holiday_seed(root)
    holidays_path = root / "assets/temporal/holidays/us-federal-seed/holidays.json"
    data = json.loads(holidays_path.read_text())
    data["year_end"] = 2028
    holidays_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("year_end" in error and "2027" in error for error in errors)


def test_holiday_seed_rejects_weekend_policy_change(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    install_valid_holiday_seed(root)
    holidays_path = root / "assets/temporal/holidays/us-federal-seed/holidays.json"
    data = json.loads(holidays_path.read_text())
    data["weekend_iso_weekdays"] = [7]
    holidays_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("weekend_iso_weekdays" in error and "[6, 7]" in error for error in errors)


def test_holiday_dependency_manifest_requires_packaged_status(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    manifest_path = root / "external/temporal/holidays/DEPENDENCY_MANIFEST.json"
    data = json.loads(manifest_path.read_text())
    data["status"] = "planned"
    manifest_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("status must be packaged" in error for error in errors)


def test_holiday_dependency_manifest_requires_version(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    manifest_path = root / "external/temporal/holidays/DEPENDENCY_MANIFEST.json"
    data = json.loads(manifest_path.read_text())
    data.pop("version", None)
    manifest_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("requires non-empty version" in error for error in errors)


def test_holiday_dependency_manifest_requires_source_url(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    manifest_path = root / "external/temporal/holidays/DEPENDENCY_MANIFEST.json"
    data = json.loads(manifest_path.read_text())
    data.pop("source_url", None)
    manifest_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("requires non-empty source_url" in error for error in errors)


def test_holiday_dependency_manifest_requires_license(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    manifest_path = root / "external/temporal/holidays/DEPENDENCY_MANIFEST.json"
    data = json.loads(manifest_path.read_text())
    data.pop("license", None)
    manifest_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("requires non-empty license" in error for error in errors)


def test_holiday_dependency_manifest_requires_reproducible_provenance(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    manifest_path = root / "external/temporal/holidays/DEPENDENCY_MANIFEST.json"
    data = json.loads(manifest_path.read_text())
    data["checksum_sha256"] = "0" * 64
    data.pop("reproducible_provenance", None)
    manifest_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("reproducible_provenance" in error for error in errors)


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


def test_natural_seed_requires_phrases_file(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    install_valid_natural_seed(root)
    (root / "assets/temporal/natural/seed/phrases.json").unlink()
    errors = checker.validate_repo(root)
    assert any("natural-phrase-seed" in error and "phrases.json" in error for error in errors)


def test_natural_seed_supported_locales_match_phrase_locale_order(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    install_valid_natural_seed(root)
    phrases_path = root / "assets/temporal/natural/seed/phrases.json"
    phrases = json.loads(phrases_path.read_text())
    phrases["locale_order"] = ["en-US", "ja-JP", "fr-FR"]
    phrases_path.write_text(json.dumps(phrases, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("natural-phrase-seed" in error and "supported_locales" in error for error in errors)


def test_natural_seed_rejects_runtime_network_fetch(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    install_valid_natural_seed(root)
    manifest_path = root / "assets/temporal/natural/seed/manifest.json"
    data = json.loads(manifest_path.read_text())
    data["runtime_network_fetch_allowed"] = True
    manifest_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("natural-phrase-seed" in error and "runtime_network_fetch_allowed" in error for error in errors)


def test_runtime_manifest_requires_natural_seed_dataset_entry(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    install_valid_natural_seed(root)
    runtime_path = root / "assets/temporal/manifest.json"
    data = json.loads(runtime_path.read_text())
    data["packaged_data_sets"] = [
        dataset
        for dataset in data["packaged_data_sets"]
        if dataset.get("id") != "natural-phrase-seed"
    ]
    runtime_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("natural-phrase-seed" in error and "exactly one" in error for error in errors)


def test_runtime_manifest_rejects_duplicate_natural_seed_dataset_entries(tmp_path: Path) -> None:
    checker = load_checker()
    root = copy_foundation(tmp_path)
    install_valid_natural_seed(root)
    runtime_path = root / "assets/temporal/manifest.json"
    data = json.loads(runtime_path.read_text())
    natural_dataset = next(
        dataset
        for dataset in data["packaged_data_sets"]
        if dataset.get("id") == "natural-phrase-seed"
    )
    data["packaged_data_sets"].append(dict(natural_dataset))
    runtime_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    errors = checker.validate_repo(root)
    assert any("natural-phrase-seed" in error and "exactly one" in error for error in errors)


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
