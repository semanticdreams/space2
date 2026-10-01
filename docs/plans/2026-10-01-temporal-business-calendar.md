# Temporal Business Calendar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic packaged `US-FED` holiday data and a public `Temporal.business-calendar` API for holiday lookup and business-day arithmetic.

**Architecture:** Check in a small generated holiday seed under `assets/temporal/holidays/us-federal-seed/`, validate it with the existing manifest validator, load it through a pure Fennel `holiday-seed` module, and expose it through a pure Fennel `Temporal.business-calendar` facade. Keep provider dispatch explicit through `Temporal.providers.business-calendar`; do not auto-override the built-in facade.

**Tech Stack:** Space Fennel modules/tests, JSON packaged asset data, Python manifest validation/generation scripts, existing `PlainDateTime` methods, existing Space validation commands.

## Global Constraints

- Runtime temporal work must not fetch network data.
- Business days are policy/calendar concepts, not exact `Duration` values.
- Exact `Duration` remains nanoseconds-only; business-day arithmetic uses plain-date day stepping.
- Holiday policy must not enter native temporal primitives, timezone conversion, ICU/CLDR presentation, recurrence policy, or scheduler semantics.
- All option keys are canonical; unsupported keys and unsupported data fail loudly.
- No host-local timezone, locale, or holiday defaults are allowed.
- Initial jurisdiction is exactly `US-FED`.
- Initial year range is exactly observed holiday dates in calendar years `2026` and `2027`.
- Weekend policy is exactly ISO weekdays `6` and `7`.
- `external/temporal/holidays/DEPENDENCY_MANIFEST.json` becomes `packaged`, not `vendored`.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.

---

## File Structure

- `scripts/generate-temporal-us-federal-holidays.py` generates the deterministic 2026-2027 `US-FED` JSON snapshot from embedded public-domain federal holiday rules.
- `assets/temporal/holidays/us-federal-seed/manifest.json` records seed identity, provenance, supported jurisdiction/year range, generator command, and no-network metadata.
- `assets/temporal/holidays/us-federal-seed/holidays.json` contains `US-FED` records with statutory and observed dates.
- `assets/lua/temporal/holiday-seed.fnl` loads and validates the checked-in seed through `SPACE_ASSETS_PATH`.
- `assets/lua/temporal/business-calendar.fnl` exposes public business-calendar operations over `PlainDateTime`.
- `assets/lua/temporal/provider-registry.fnl` gains an explicit business-calendar dispatcher for registered providers.
- `assets/lua/temporal.fnl` exports `Temporal.business-calendar`.
- `assets/lua/tests/test-temporal-business-calendar.fnl` covers loader, fixture, observed-holiday, and business-day arithmetic behavior.
- `assets/lua/tests/test-temporal-provider-registry.fnl` gains provider dispatcher tests.
- `assets/lua/tests/test-temporal.fnl` gains public export smoke coverage.
- `assets/lua/tests/fast.fnl` registers the focused business-calendar suite.
- `scripts/check-temporal-dependency-manifests.py` validates holiday seed data and manifest references.
- `scripts/tests/test_temporal_dependency_manifests.py` covers the validator behavior.
- `docs/dev/features/temporal-business-calendar.md`, `docs/dev/features/temporal.md`, `docs/dev/features/temporal-complete-library.md`, `docs/dev/features/temporal-complete-acceptance.md`, and `docs/dev/notes/temporal-dependency-data-packaging.md` document the Track 9 surface and evidence.

---

### Task 1: Holiday Seed Data and Manifest Validation

**Files:**
- Create: `scripts/generate-temporal-us-federal-holidays.py`
- Create: `assets/temporal/holidays/us-federal-seed/manifest.json`
- Create: `assets/temporal/holidays/us-federal-seed/holidays.json`
- Modify: `assets/temporal/manifest.json`
- Modify: `external/temporal/holidays/DEPENDENCY_MANIFEST.json`
- Modify: `scripts/check-temporal-dependency-manifests.py`
- Test: `scripts/tests/test_temporal_dependency_manifests.py`

**Interfaces:**
- Consumes: existing manifest validator entry point `validate_repo(repo_root: Path) -> list[str]`.
- Produces: packaged dataset id `us-federal-holidays-seed`; provider id `space.temporal.us-federal-holidays`; JSON files `manifest.json` and `holidays.json`; validator coverage for the holiday seed.

- [ ] **Step 1: Add failing validator tests for the holiday seed.**

  Add tests that copy `external/temporal` and `assets/temporal` into a temporary repo root, then assert errors for missing `assets/temporal/holidays/us-federal-seed/holidays.json`, mismatched supported jurisdictions, invalid `runtime_network_fetch_allowed`, missing required holiday record fields, and duplicate observed dates. Example assertions to include:

  ```python
  def test_holiday_seed_requires_holidays_file(tmp_path: Path) -> None:
      root = copy_temporal_tree(tmp_path)
      (root / "assets/temporal/holidays/us-federal-seed/holidays.json").unlink()
      errors = manifests.validate_repo(root)
      assert any("holidays.json" in error for error in errors)
  ```

  ```python
  def test_holiday_seed_rejects_jurisdiction_mismatch(tmp_path: Path) -> None:
      root = copy_temporal_tree(tmp_path)
      manifest_path = root / "assets/temporal/holidays/us-federal-seed/manifest.json"
      data = json.loads(manifest_path.read_text())
      data["supported_jurisdictions"] = ["CA-FED"]
      manifest_path.write_text(json.dumps(data), encoding="utf-8")
      errors = manifests.validate_repo(root)
      assert any("supported_jurisdictions" in error for error in errors)
  ```

- [ ] **Step 2: Run the new validator tests and capture RED evidence.**

  Run: `python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q`

  Expected: failures naming the missing holiday seed files or missing holiday validation behavior.

- [ ] **Step 3: Add the deterministic generator script.**

  Implement `scripts/generate-temporal-us-federal-holidays.py` with no third-party imports and no network calls. The script accepts:

  ```text
  --start-year 2026 --end-year 2027 --output assets/temporal/holidays/us-federal-seed/holidays.json
  ```

  It writes sorted JSON with this top-level shape:

  ```json
  {
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
          "2026": [],
          "2027": []
        }
      }
    }
  }
  ```

  Each holiday record contains `id`, `name`, `date`, `observed_date`, and `observed`.

- [ ] **Step 4: Generate and check in the holiday seed files.**

  Run the generator command from the spec. Ensure the checked-in 2026 and 2027 records include observed holiday cases:
  - `2026-07-04` observed on `2026-07-03` for Independence Day.
  - `2027-06-19` observed on `2027-06-18` for Juneteenth.
  - `2027-07-04` observed on `2027-07-05` for Independence Day.
  - `2027-12-25` observed on `2027-12-24` for Christmas Day.

- [ ] **Step 5: Add `manifest.json` for the seed.**

  Include `schema_version: 1`, `id: "us-federal-holidays-seed"`, `provider_id: "space.temporal.us-federal-holidays"`, `supported_jurisdictions: ["US-FED"]`, `year_start: 2026`, `year_end: 2027`, `runtime_network_fetch_allowed: false`, source/provenance text, and the exact generator command.

- [ ] **Step 6: Update the repository manifests.**

  Update `assets/temporal/manifest.json` with a packaged data set entry:

  ```json
  {
    "id": "us-federal-holidays-seed",
    "provider_id": "space.temporal.us-federal-holidays",
    "version": "US-FED-2026-2027-seed",
    "root": "assets/temporal/holidays/us-federal-seed",
    "manifest": "assets/temporal/holidays/us-federal-seed/manifest.json",
    "runtime_network_fetch_allowed": false,
    "files": ["holidays.json"]
  }
  ```

  Update `external/temporal/holidays/DEPENDENCY_MANIFEST.json` to `status: "packaged"` with non-empty `version`, `source_url`, `license`, and `reproducible_provenance` fields. Keep `runtime.network_fetch_allowed` false and keep the dependency as metadata/data only.

- [ ] **Step 7: Extend the validator.**

  Add holiday-specific checks in `scripts/check-temporal-dependency-manifests.py` that validate the packaged data set, seed manifest, seed file presence, exact jurisdiction order, exact year range, exact weekend weekdays, record fields, ISO date string shape, observed date uniqueness per jurisdiction/year, and no-network fields.

- [ ] **Step 8: Run validator tests and commit.**

  Run: `python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q`

  Expected: pass.

  Commit message: `feat(assets): add temporal holiday seed data`

---

### Task 2: Holiday Seed Loader

**Files:**
- Create: `assets/lua/temporal/holiday-seed.fnl`
- Test: `assets/lua/tests/test-temporal-business-calendar.fnl`

**Interfaces:**
- Consumes: `assets/temporal/holidays/us-federal-seed/manifest.json` and `holidays.json` from Task 1.
- Produces: `holiday-seed.load()`, `holiday-seed.supported-jurisdictions()`, `holiday-seed.jurisdiction-data(jurisdiction)`, `holiday-seed.holidays-for-year(jurisdiction, year)`, and `holiday-seed.holiday-on-date(jurisdiction, iso-date)`.

- [ ] **Step 1: Add the focused test module with failing loader tests.**

  Create `assets/lua/tests/test-temporal-business-calendar.fnl` following existing temporal test style. Include tests named:
  - `seed exposes supported jurisdictions defensively`
  - `seed rejects unsupported jurisdiction loudly`
  - `seed returns holidays for supported year`
  - `seed finds observed holiday by date`

  Example expected checks:

  ```fennel
  (local seed (require :temporal/holiday-seed))
  (local jurisdictions (seed.supported-jurisdictions))
  (assert= (. jurisdictions 1) "US-FED")
  (tset jurisdictions 1 "mutated")
  (assert= (. (seed.supported-jurisdictions) 1) "US-FED")
  ```

- [ ] **Step 2: Run the focused test and capture RED evidence.**

  Run with the full Fennel runtime environment:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-business-calendar:main
  ```

  Expected: failure because `temporal/holiday-seed` is not defined.

- [ ] **Step 3: Implement the loader.**

  Mirror the asset-reading and validation style from `assets/lua/temporal/cldr-seed.fnl`. Validate provider id, schema version, supported jurisdiction order, year range, weekend weekdays, record fields, and no-network metadata. Cache the loaded dataset and return defensive copies from public helpers.

- [ ] **Step 4: Run compile, constraints, focused tests, and commit.**

  Run:

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-business-calendar:main
  ```

  Expected: pass.

  Commit message: `feat(lua): load temporal holiday seed data`

---

### Task 3: Public `Temporal.business-calendar` Facade

**Files:**
- Create: `assets/lua/temporal/business-calendar.fnl`
- Modify: `assets/lua/temporal.fnl`
- Modify: `assets/lua/tests/test-temporal.fnl`
- Test: `assets/lua/tests/test-temporal-business-calendar.fnl`

**Interfaces:**
- Consumes: Task 2 `holiday-seed` helpers and `PlainDateTime` values from `Temporal.plain-date-time`.
- Produces: `Temporal.business-calendar.supported-jurisdictions`, `holidays`, `is-holiday`, `is-business-day`, `add-business-days`, and `business-days-between`.

- [ ] **Step 1: Add failing public facade tests.**

  Extend `test-temporal-business-calendar.fnl` to require `Temporal` and assert:
  - `Temporal.business-calendar` is exported.
  - `supported-jurisdictions()` returns `"US-FED"` defensively.
  - `holidays {:jurisdiction "US-FED" :year 2026}` returns New Year's Day and Independence Day records.
  - `is-holiday` is true for `2026-07-03T09:00:00` and false for `2026-07-06T09:00:00`.
  - `is-business-day` excludes Saturday, Sunday, and observed holidays.
  - `add-business-days` handles `0`, positive, and negative counts.
  - `business-days-between` is half-open and rejects descending ranges.

- [ ] **Step 2: Run the focused test and capture RED evidence.**

  Expected: failure because `Temporal.business-calendar` is not exported.

- [ ] **Step 3: Implement `business-calendar.fnl`.**

  Add option validation with only these allowed option keys:
  - `:jurisdiction` for predicates and arithmetic.
  - `:jurisdiction` and `:year` for `holidays`.

  Use `PlainDateTime:fields`, `:iso-weekday`, and `:add-days`. Preserve time fields when returning from `add-business-days`. Reject unsupported jurisdiction/year, invalid plain values, non-integer counts, unknown options, and descending ranges with explicit error strings.

- [ ] **Step 4: Export the facade.**

  In `assets/lua/temporal.fnl`, require `:temporal/holiday-seed` and `:temporal/business-calendar`, instantiate the facade with `{ :plain-date-time base.plain-date-time :seed holiday-seed }`, and add `:business-calendar business-calendar` to the public table.

- [ ] **Step 5: Update public export smoke tests.**

  In `assets/lua/tests/test-temporal.fnl`, add an assertion that `Temporal.business-calendar.supported-jurisdictions` is a function.

- [ ] **Step 6: Run validation and commit.**

  Run `make fennel-check`, `make constraints`, and the focused business-calendar test command.

  Expected: pass.

  Commit message: `feat(lua): add temporal business calendar facade`

---

### Task 4: Provider Registry Business-Calendar Dispatcher

**Files:**
- Modify: `assets/lua/temporal/provider-registry.fnl`
- Test: `assets/lua/tests/test-temporal-provider-registry.fnl`

**Interfaces:**
- Consumes: existing provider registration with `:capabilities ["business-calendar"]` and `:business-calendar` function or table.
- Produces: `Temporal.providers.business-calendar(operation: string, request: table) -> any`.

- [ ] **Step 1: Add failing provider dispatcher tests.**

  Add tests covering:
  - function provider called as `provider.business-calendar(operation, request)`;
  - table provider called as `provider.business-calendar[operation](request)`;
  - lower priority wins before higher priority, then provider id tie-breaker;
  - invalid operation type errors loudly;
  - invalid request type errors loudly;
  - provider error is surfaced with provider id context;
  - missing handler errors loudly.

- [ ] **Step 2: Run the provider test and capture RED evidence.**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-provider-registry:main
  ```

  Expected: failure because the dispatcher is not exported.

- [ ] **Step 3: Implement dispatcher.**

  Reuse `ordered-providers` and capability filtering. For each provider with `"business-calendar"` capability, dispatch to the function or table handler. Return the first successful handler result. If no provider can handle the operation, error with the operation name. Do not auto-register the built-in seed provider.

- [ ] **Step 4: Run validation and commit.**

  Run `make fennel-check`, `make constraints`, and the focused provider-registry test command.

  Expected: pass.

  Commit message: `feat(lua): dispatch temporal business calendar providers`

---

### Task 5: Docs, Fast Suite Registration, and Acceptance Matrix

**Files:**
- Create: `docs/dev/features/temporal-business-calendar.md`
- Modify: `docs/dev/features/temporal.md`
- Modify: `docs/dev/features/temporal-complete-library.md`
- Modify: `docs/dev/features/temporal-complete-acceptance.md`
- Modify: `docs/dev/notes/temporal-dependency-data-packaging.md`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: public API and packaged data from Tasks 1-4.
- Produces: documented Track 9 behavior and fast-suite coverage.

- [ ] **Step 1: Register focused tests in the fast suite.**

  Add `:tests.test-temporal-business-calendar` to `assets/lua/tests/fast.fnl` near the other temporal suites.

- [ ] **Step 2: Add feature documentation.**

  Create `docs/dev/features/temporal-business-calendar.md` documenting API operations, canonical options, exact `US-FED` 2026-2027 scope, observed holiday policy, data provenance, unsupported cases, provider extension path, and validation commands.

- [ ] **Step 3: Update feature indexes and roadmap status.**

  Update `docs/dev/features/temporal.md` with the new feature page. Update `temporal-complete-library.md` current status to include Track 9 and keep remaining later-track exclusions explicit. Update `temporal-complete-acceptance.md` with concrete Track 9 evidence commands.

- [ ] **Step 4: Update dependency packaging docs.**

  Update `docs/dev/notes/temporal-dependency-data-packaging.md` so holiday data is listed as packaged under `assets/temporal/holidays/us-federal-seed/` with no runtime network fetches.

- [ ] **Step 5: Run focused searches and commit.**

  Run:

  ```bash
  rg "business-calendar|US-FED|holiday" docs/dev assets/temporal external/temporal
  rg "runtime_network_fetch_allowed|network_fetch_allowed" assets/temporal external/temporal docs/dev/notes/temporal-dependency-data-packaging.md
  make fennel-check
  make constraints
  ```

  Expected: searches show consistent docs/data references; compile and constraints pass.

  Commit message: `docs(assets): document temporal business calendars`

---

### Task 6: Final Track Validation

**Files:**
- No production file changes; validation-only task.

**Interfaces:**
- Consumes: all previous task outputs.
- Produces: final local validation evidence for finishing the branch.

- [ ] **Step 1: Ensure runtime freshness.**

  Run `make build` with a 4-hour timeout if `./build/space` may be missing or stale. For this public Fennel/data surface, running it is acceptable final evidence.

- [ ] **Step 2: Run the Fennel compile check.**

  Run: `make fennel-check`

  Expected: pass.

- [ ] **Step 3: Run constraints.**

  Run: `make constraints`

  Expected: pass.

- [ ] **Step 4: Run focused Python manifest tests.**

  Run: `python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q`

  Expected: pass.

- [ ] **Step 5: Run focused Fennel tests.**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-business-calendar:main
  ```

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-provider-registry:main
  ```

  Expected: both focused suites pass.

- [ ] **Step 6: Run the full local suite.**

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: pass.

- [ ] **Step 7: Handoff to finishing workflow.**

  Confirm `git status --porcelain` is clean, record validation evidence, and use the finishing workflow to fetch `origin/main`, safe-merge if required, rerun required validation after any merge, push, create/update the PR, enable auto-merge/queue, and poll until merged.
