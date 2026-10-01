# Temporal Localization Calendar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic, packaged CLDR seed-backed public `Temporal.calendar` and `Temporal.localization` Fennel facades for the initial locale/calendar corpus.

**Architecture:** Implement pure Fennel facades that load checked-in JSON seed data from `assets/temporal/icu/cldr-seed/`, validate it loudly, and expose stable public APIs through `assets/lua/temporal.fnl`. Calendar conversion remains separate from duration and period arithmetic; localization delegates calendar conversion to `Temporal.calendar` and only supports exact selected seed patterns.

**Tech Stack:** Space Fennel, existing `Temporal.plain-date-time` facade, checked-in JSON seed data, Python manifest validation tests, Space Fennel fast tests.

## Global Constraints

- No host locale or host timezone defaults.
- Exact `Duration` remains nanoseconds-only.
- Localized calendars are separate from exact duration and period arithmetic.
- Native temporal core remains independent from ICU/CLDR presentation, provider policy, business calendars, natural language, and scheduler behavior.
- Runtime localization and calendar conversion do not fetch network data.
- Canonical option keys only; no aliases or compatibility shims.
- Unsupported locales, calendars, options, styles, eras, date ranges, and malformed localized text fail loudly.
- Do not vendor ICU4C source in this slice.
- Do not enable `SPACE_TEMPORAL_ENABLE_ICU_ADAPTER`.
- Do not add a native `temporal_localization` adapter or C++ bindings.
- Do not import full generated CLDR data.
- Initial supported locales are exactly `en-US`, `fr-FR`, and `ja-JP`.
- Initial supported calendars are exactly `gregory`, `buddhist`, and `japanese`.
- Supported `:date-style` values are exactly `:short` and `:long`.
- Locale ids are exact and case-sensitive in this slice.
- The built-in seed corpus provider identity is `space.temporal.cldr-seed`.

---

## File Structure

- Create `assets/temporal/icu/cldr-seed/manifest.json`: deterministic CLDR seed provenance, supported lists, no-network flag, and file list.
- Create `assets/temporal/icu/cldr-seed/calendars.json`: finite `gregory`, `buddhist`, and `japanese` calendar era/conversion data.
- Create `assets/temporal/icu/cldr-seed/locales.json`: finite locale/calendar/style format token data.
- Modify `assets/temporal/manifest.json`: add `packaged_data_sets` entry for `cldr-seed`.
- Modify `external/temporal/icu/DEPENDENCY_MANIFEST.json`: mark selected seed data `packaged` while keeping ICU4C/native adapter future-gated.
- Modify `assets/temporal/icu/README.md`: document the checked-in seed corpus under the reserved ICU root.
- Create `assets/lua/temporal/cldr-seed.fnl`: load and validate seed JSON through explicit project asset path.
- Create `assets/lua/temporal/calendar.fnl`: public calendar conversion facade.
- Create `assets/lua/temporal/localization.fnl`: public locale format/parse facade.
- Modify `assets/lua/temporal.fnl`: export `Temporal.calendar` and `Temporal.localization`.
- Create `assets/lua/tests/test-temporal-calendar.fnl`: focused calendar API tests.
- Create `assets/lua/tests/test-temporal-localization.fnl`: focused localization API tests.
- Modify `assets/lua/tests/test-temporal.fnl`: assert public exports exist.
- Modify `assets/lua/tests/fast.fnl`: register focused tests in the fast suite.
- Modify `scripts/check-temporal-dependency-manifests.py`: validate packaged CLDR seed files and no-network metadata.
- Modify `scripts/tests/test_temporal_dependency_manifests.py`: add manifest/package regression tests.
- Create `docs/dev/features/temporal-localization-calendar.md`: canonical feature documentation.
- Modify `docs/dev/features/temporal.md`: link new feature page.
- Modify `docs/dev/features/temporal-complete-library.md`: update current status.
- Modify `docs/dev/features/temporal-complete-acceptance.md`: update localization/calendar row and evidence.
- Modify `docs/dev/notes/temporal-dependency-data-packaging.md`: describe CLDR seed packaged data and future ICU4C boundary.

## Record Shapes and Public Interfaces

### Seed manifest shape

`assets/temporal/icu/cldr-seed/manifest.json` must contain:

```json
{
  "schema_version": 1,
  "id": "cldr-seed",
  "provider_id": "space.temporal.cldr-seed",
  "version": "CLDR-46-selected-seed",
  "source_url": "https://unicode.org/Public/cldr/46/",
  "license": "Unicode License v3",
  "runtime_network_fetch_allowed": false,
  "supported_locales": ["en-US", "fr-FR", "ja-JP"],
  "supported_calendars": ["gregory", "buddhist", "japanese"],
  "reproducible_provenance": "Hand-curated selected corpus derived from CLDR 46 locale date patterns, month names, and era identifiers; every supported value is represented in focused Temporal.localization and Temporal.calendar tests.",
  "files": [
    {"path": "locales.json", "kind": "locale-date-patterns"},
    {"path": "calendars.json", "kind": "calendar-era-data"}
  ]
}
```

### Runtime manifest packaged data set shape

`assets/temporal/manifest.json` must contain:

```json
{
  "schema_version": 1,
  "runtime_network_fetch_allowed": false,
  "packaged_data_sets": [
    {
      "id": "cldr-seed",
      "provider_id": "space.temporal.cldr-seed",
      "version": "CLDR-46-selected-seed",
      "root": "assets/temporal/icu/cldr-seed",
      "manifest": "assets/temporal/icu/cldr-seed/manifest.json",
      "runtime_network_fetch_allowed": false,
      "files": ["locales.json", "calendars.json"]
    }
  ]
}
```

### Calendar field record shape

`Temporal.calendar.from-iso` returns and `Temporal.calendar.to-iso` accepts only:

```fennel
{:kind :temporal-calendar-fields
 :calendar "japanese"
 :era "reiwa"
 :year 8
 :month 10
 :day 1
 :hour 9
 :minute 30
 :second 0
 :nanosecond 0}
```

Allowed record keys are exactly `:kind`, `:calendar`, `:era`, `:year`, `:month`, `:day`, `:hour`, `:minute`, `:second`, and `:nanosecond`.

### Public Fennel interfaces

```fennel
(Temporal.calendar.supported-calendars) ; sequential array<string>, sorted lexically
(Temporal.calendar.from-iso plain-date-time {:calendar "japanese"}) ; calendar field record
(Temporal.calendar.to-iso calendar-fields) ; PlainDateTime

(Temporal.localization.supported-locales) ; sequential array<string>, sorted lexically
(Temporal.localization.supported-combinations)
; sequential array<table>, sorted by locale, calendar, date-style:
; {:locale "en-US" :calendar "gregory" :date-style :short}

(Temporal.localization.format-plain-date-time
  plain-date-time
  {:locale "fr-FR" :calendar "gregory" :date-style :long}) ; string

(Temporal.localization.parse-plain-date-time
  "1 octobre 2026"
  {:locale "fr-FR" :calendar "gregory" :date-style :long}) ; PlainDateTime at midnight
```

---

### Task 1: Deterministic CLDR Seed Data and Manifest Packaging

**Files:**
- Create: `assets/temporal/icu/cldr-seed/manifest.json`
- Create: `assets/temporal/icu/cldr-seed/calendars.json`
- Create: `assets/temporal/icu/cldr-seed/locales.json`
- Modify: `assets/temporal/manifest.json`
- Modify: `external/temporal/icu/DEPENDENCY_MANIFEST.json`
- Modify: `assets/temporal/icu/README.md`

**Interfaces:**
- Consumes: Existing temporal data roots `assets/temporal/icu/` and manifest checker conventions.
- Produces: Packaged seed data consumed by `temporal/cldr-seed.fnl`; runtime manifest entry consumed by `scripts/check-temporal-dependency-manifests.py`.

- [ ] **Step 1: Write the seed manifest file**

  Create `assets/temporal/icu/cldr-seed/manifest.json` with exactly the seed manifest shape defined above.

- [ ] **Step 2: Write `calendars.json`**

  Create `assets/temporal/icu/cldr-seed/calendars.json` with this exact content:

  ```json
  {
    "schema_version": 1,
    "provider_id": "space.temporal.cldr-seed",
    "calendar_order": ["gregory", "buddhist", "japanese"],
    "calendars": {
      "gregory": {"eras": [{"id": "ce", "start_iso": "0001-01-01", "year_offset": 0}]},
      "buddhist": {"eras": [{"id": "be", "start_iso": "0001-01-01", "year_offset": 543}]},
      "japanese": {"eras": [
        {"id": "showa", "code": "S", "name_ja": "昭和", "start_iso": "1926-12-25", "end_iso": "1989-01-07", "iso_start_year": 1926},
        {"id": "heisei", "code": "H", "name_ja": "平成", "start_iso": "1989-01-08", "end_iso": "2019-04-30", "iso_start_year": 1989},
        {"id": "reiwa", "code": "R", "name_ja": "令和", "start_iso": "2019-05-01", "iso_start_year": 2019}
      ]}
    }
  }
  ```

- [ ] **Step 3: Write `locales.json`**

  Create `assets/temporal/icu/cldr-seed/locales.json` with `schema_version: 1`, provider id `space.temporal.cldr-seed`, `locale_order` `['en-US', 'fr-FR', 'ja-JP']`, English/French month-name arrays, and exactly these supported combinations/styles:
  - `en-US` + `gregory`: short `MM/DD/YYYY`, long `Month D, YYYY`.
  - `fr-FR` + `gregory`: short `DD/MM/YYYY`, long `D month YYYY`.
  - `ja-JP` + `gregory`: short `YYYY/MM/DD`, long `YYYY年M月D日`.
  - `en-US` + `buddhist`: short `MM/DD/YYYY BE`, long `Month D, YYYY BE`.
  - `ja-JP` + `japanese`: short `R8/10/01`-style `era-code year/MM/DD`, long `令和8年10月1日`-style `era-name year年M月D日`.

- [ ] **Step 4: Update the runtime temporal manifest**

  Replace `assets/temporal/manifest.json` with the runtime manifest packaged data set shape defined above.

- [ ] **Step 5: Update the ICU dependency manifest**

  Modify `external/temporal/icu/DEPENDENCY_MANIFEST.json` so:
  - `status` is `"packaged"`;
  - `candidate` remains `"ICU4C/CLDR"`;
  - `adapter_boundary` remains `"temporal_localization"`;
  - `runtime.network_fetch_allowed` remains `false`;
  - add `"version": "CLDR-46-selected-seed"`;
  - add `"source_url": "https://unicode.org/Public/cldr/46/"`;
  - add `"license": "Unicode License v3"`;
  - add `"reproducible_provenance": "Hand-curated selected CLDR 46 seed corpus checked in under assets/temporal/icu/cldr-seed; full ICU4C source and generated data are not included in this slice."`;
  - update `follow_up_gate` to `"Full ICU4C source, generated CLDR data, license notice handling, and adapter build strategy remain future work before enabling temporal_localization native adapter support."`.

- [ ] **Step 6: Update the ICU runtime data README**

  Replace `assets/temporal/icu/README.md` with:

  ```markdown
  # ICU/CLDR Runtime Data

  This directory contains the deterministic `cldr-seed` corpus used by the first
  `Temporal.localization` and `Temporal.calendar` Fennel facades.

  The seed corpus is a hand-curated selected subset derived from CLDR 46 date
  patterns, month names, and era identifiers. Runtime network fetches are not
  allowed. Full ICU4C source, generated CLDR data, and the native
  `temporal_localization` adapter remain future work.
  ```

- [ ] **Step 7: Run JSON/package smoke checks**

  ```bash
  python3 -m json.tool assets/temporal/icu/cldr-seed/manifest.json >/tmp/cldr-seed-manifest.json
  python3 -m json.tool assets/temporal/icu/cldr-seed/calendars.json >/tmp/cldr-seed-calendars.json
  python3 -m json.tool assets/temporal/icu/cldr-seed/locales.json >/tmp/cldr-seed-locales.json
  python3 -m json.tool assets/temporal/manifest.json >/tmp/temporal-manifest.json
  python3 -m json.tool external/temporal/icu/DEPENDENCY_MANIFEST.json >/tmp/icu-dependency-manifest.json
  ```

  Expected: all commands exit `0`.

- [ ] **Step 8: Commit Task 1**

  ```bash
  git add assets/temporal/icu/cldr-seed/manifest.json assets/temporal/icu/cldr-seed/calendars.json assets/temporal/icu/cldr-seed/locales.json assets/temporal/manifest.json external/temporal/icu/DEPENDENCY_MANIFEST.json assets/temporal/icu/README.md
  git commit -m "feat(assets): package temporal CLDR seed data"
  ```

---

### Task 2: Manifest Validator Expansion

**Files:**
- Modify: `scripts/check-temporal-dependency-manifests.py`
- Modify: `scripts/tests/test_temporal_dependency_manifests.py`

**Interfaces:**
- Consumes: Packaged data shapes from Task 1.
- Produces: `validate_repo(repo_root: Path) -> list[str]` diagnostics that reject missing CLDR seed files, malformed packaged data set entries, and runtime network fetches.

- [ ] **Step 1: Add failing Python tests for packaged CLDR seed validation**

  Add tests named:
  - `test_runtime_manifest_requires_packaged_seed_files`: delete `assets/temporal/icu/cldr-seed/locales.json` from a copied foundation and assert a diagnostic containing `packaged data file does not exist` and `locales.json`.
  - `test_runtime_packaged_data_set_network_fetch_is_forbidden`: set the first runtime packaged data set's `runtime_network_fetch_allowed` to `true` and assert a diagnostic containing `packaged_data_sets[0].runtime_network_fetch_allowed must be false`.
  - `test_cldr_seed_manifest_supported_lists_match_data`: change seed `supported_locales` to `['en-US']` and assert a diagnostic containing `cldr-seed supported_locales must match locales.json locale_order`.
  - `test_icu_manifest_is_packaged_for_cldr_seed`: assert ICU manifest `status`, `version`, `source_url`, `license`, no-network flag, and follow-up gate values from Task 1.

- [ ] **Step 2: Run the tests and verify failure before validator implementation**

  ```bash
  python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q
  ```

  Expected before implementation: new validation tests fail because CLDR seed cross-file validation is not implemented.

- [ ] **Step 3: Implement packaged data set validation helpers**

  In `scripts/check-temporal-dependency-manifests.py`, add helper functions:
  - `require_string(data: dict, key: str, path: Path, errors: list[str]) -> str | None`;
  - `require_string_array(data: dict, key: str, path: Path, errors: list[str]) -> list[str] | None`.

  Both helpers must append diagnostics naming the manifest path and key when values are missing or malformed.

- [ ] **Step 4: Implement CLDR seed cross-file validation**

  Add `validate_cldr_seed(repo_root: Path, dataset: dict, index: int, errors: list[str]) -> None` that:
  - validates `root`, `manifest`, and `files` fields;
  - rejects missing root, manifest, or listed files;
  - loads seed manifest, `locales.json`, and `calendars.json`;
  - requires seed `runtime_network_fetch_allowed` to be false;
  - requires seed `id` to be `cldr-seed`;
  - requires seed `provider_id` to be `space.temporal.cldr-seed`;
  - requires seed `supported_locales` to equal `locales.locale_order`;
  - requires seed `supported_calendars` to equal `calendars.calendar_order`.

- [ ] **Step 5: Call packaged data set validation from `validate_runtime_manifest`**

  Extend `validate_runtime_manifest` so each `packaged_data_sets` entry:
  - must be an object;
  - must have `runtime_network_fetch_allowed` exactly `false`;
  - must have non-empty `id`, `provider_id`, `version`, `root`, and `manifest`;
  - must have `files` as an array of non-empty strings;
  - calls `validate_cldr_seed(...)` when `id == "cldr-seed"`.

- [ ] **Step 6: Run focused manifest tests**

  ```bash
  python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q
  ```

  Expected: pass.

- [ ] **Step 7: Run CTest manifest check if build exists**

  ```bash
  ctest --test-dir build -R '^test_temporal_dependency_manifests$' --output-on-failure
  ```

  Expected when `build/` exists: pass.

- [ ] **Step 8: Commit Task 2**

  ```bash
  git add scripts/check-temporal-dependency-manifests.py scripts/tests/test_temporal_dependency_manifests.py
  git commit -m "test(scripts): validate packaged temporal CLDR seed manifests"
  ```

---

### Task 3: CLDR Seed Loader Module

**Files:**
- Create: `assets/lua/temporal/cldr-seed.fnl`

**Interfaces:**
- Consumes: `assets/temporal/icu/cldr-seed/*.json` from Task 1.
- Produces: `seed.load`, `seed.supported-locales`, `seed.supported-calendars`, `seed.find-combination`, and `seed.calendar-data`.

- [ ] **Step 1: Create module skeleton with explicit asset root resolution**

  Create `assets/lua/temporal/cldr-seed.fnl` that requires `:json`, resolves `SPACE_ASSETS_PATH` or runtime assets path, reads `temporal/icu/cldr-seed/manifest.json`, `locales.json`, and `calendars.json`, and throws `Temporal CLDR seed requires SPACE_ASSETS_PATH or runtime assets-path` when no asset root is available.

- [ ] **Step 2: Add validation helpers**

  Add helper functions:
  - `array-of-strings? [value] -> boolean`;
  - `require-field [record key expected-type context] -> value`;
  - `require-false [value context]`;
  - `validate-manifest! [manifest]`;
  - `validate-calendars! [calendars]`;
  - `validate-locales! [locales]`.

  Required diagnostics include `missing or malformed CLDR seed data`, `CLDR seed runtime network fetches must be disabled`, `CLDR seed supported locale mismatch`, and `CLDR seed supported calendar mismatch`.

- [ ] **Step 3: Implement cached load**

  Implement `(load)` that reads and validates all three JSON files once, stores them in local `cache`, and returns `{:manifest manifest :locales locales :calendars calendars}` on every call.

- [ ] **Step 4: Implement lookup functions**

  Implement and export:
  - `supported-locales []` returns a sorted copy of `manifest.supported_locales`;
  - `supported-calendars []` returns a sorted copy of `manifest.supported_calendars`;
  - `calendar-data [calendar]` returns `calendars.calendars[calendar]` or nil;
  - `find-combination [locale calendar]` returns the matching locale/calendar combination from `locales.combinations` or nil.

- [ ] **Step 5: Focused compile check**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/cldr-seed.fnl
  ```

  Expected: pass.

- [ ] **Step 6: Commit Task 3**

  ```bash
  git add assets/lua/temporal/cldr-seed.fnl
  git commit -m "feat(lua): load temporal CLDR seed data"
  ```

---

### Task 4: `Temporal.calendar` Facade

**Files:**
- Create: `assets/lua/temporal/calendar.fnl`
- Modify: `assets/lua/temporal.fnl`
- Create: `assets/lua/tests/test-temporal-calendar.fnl`
- Modify: `assets/lua/tests/test-temporal.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: seed module from Task 3 and `base.plain-date-time` from `assets/lua/temporal.fnl`.
- Produces: `Temporal.calendar.supported-calendars`, `Temporal.calendar.from-iso`, and `Temporal.calendar.to-iso`.

- [ ] **Step 1: Write failing calendar tests**

  Create `assets/lua/tests/test-temporal-calendar.fnl` with tests for:
  - supported calendars exactly `['buddhist', 'gregory', 'japanese']`;
  - Gregorian round trip for `2026-10-01T09:30:00`;
  - Buddhist round trip yielding year `2569` and era `be`;
  - Japanese boundaries: `1926-12-25` Showa 1, `1989-01-07` Showa 64, `1989-01-08` Heisei 1, `2019-04-30` Heisei 31, `2019-05-01` Reiwa 1, `2026-10-01` Reiwa 8;
  - Japanese date before `1926-12-25` throws `unsupported Japanese era range`;
  - Reiwa `1-04-30` throws `inconsistent Japanese era/date fields`;
  - missing `:calendar`, unknown option keys, unknown record keys, unsupported calendar, and invalid field types throw.

- [ ] **Step 2: Register the new test in the fast suite**

  Add `:tests.test-temporal-calendar` near the other temporal tests in `assets/lua/tests/fast.fnl`.

- [ ] **Step 3: Verify the tests fail because the facade is missing**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-calendar:main
  ```

  Expected before implementation: fail with missing `Temporal.calendar`.

- [ ] **Step 4: Implement calendar module helpers**

  Create `assets/lua/temporal/calendar.fnl` with allowed option keys exactly `:calendar`, allowed record keys exactly `:kind`, `:calendar`, `:era`, `:year`, `:month`, `:day`, `:hour`, `:minute`, `:second`, `:nanosecond`, plus helpers for unknown-key rejection, type checks, ISO date key creation, date comparison, and extracting `PlainDateTime` fields.

- [ ] **Step 5: Implement conversion functions**

  Implement `gregory`, `buddhist`, and `japanese` conversion functions following the spec:
  - Gregorian uses era `ce` and same year.
  - Buddhist uses era `be` and ISO year plus/minus 543.
  - Japanese selects Showa/Heisei/Reiwa by inclusive date range and validates era/date consistency on reverse conversion.

- [ ] **Step 6: Implement public factory**

  Export `(create-calendar deps)` returning `{:supported-calendars supported-calendars :from-iso from-iso :to-iso to-iso}`. `deps` must contain `:plain-date-time` and `:seed`.

- [ ] **Step 7: Wire the facade into `assets/lua/temporal.fnl`**

  Require `:temporal/cldr-seed` and `:temporal/calendar`, instantiate the calendar facade after `base` exists, and add `:calendar calendar` to the public temporal table.

- [ ] **Step 8: Add export assertion to base temporal tests**

  In `assets/lua/tests/test-temporal.fnl`, assert `Temporal.calendar` and its three public functions exist.

- [ ] **Step 9: Run focused Fennel validation ladder**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/cldr-seed.fnl --file assets/lua/temporal/calendar.fnl --file assets/lua/temporal.fnl --file assets/lua/tests/test-temporal-calendar.fnl --file assets/lua/tests/test-temporal.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-calendar:main
  ```

  Expected: all pass.

- [ ] **Step 10: Commit Task 4**

  ```bash
  git add assets/lua/temporal/calendar.fnl assets/lua/temporal.fnl assets/lua/tests/test-temporal-calendar.fnl assets/lua/tests/test-temporal.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(lua): add Temporal.calendar facade"
  ```

---

### Task 5: `Temporal.localization` Facade

**Files:**
- Create: `assets/lua/temporal/localization.fnl`
- Modify: `assets/lua/temporal.fnl`
- Create: `assets/lua/tests/test-temporal-localization.fnl`
- Modify: `assets/lua/tests/test-temporal.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `Temporal.calendar` facade from Task 4 and seed module from Task 3.
- Produces: `Temporal.localization.supported-locales`, `supported-combinations`, `format-plain-date-time`, and `parse-plain-date-time`.

- [ ] **Step 1: Write failing localization tests**

  Create `assets/lua/tests/test-temporal-localization.fnl` with tests asserting:
  - supported locales exactly `['en-US', 'fr-FR', 'ja-JP']`;
  - supported combinations include exactly ten rows: five locale/calendar pairs times two date styles;
  - format examples: `10/01/2026`, `October 1, 2026`, `01/10/2026`, `1 octobre 2026`, `2026/10/01`, `2026年10月1日`, `10/01/2569 BE`, `October 1, 2569 BE`, `R8/10/01`, and `令和8年10月1日`;
  - parsing each emitted string returns the expected ISO date at midnight;
  - unsupported locale, unsupported calendar, unsupported combination, unsupported style, missing option keys, unknown option keys, malformed localized text, invalid month name, and invalid era name throw loud diagnostics.

- [ ] **Step 2: Register the new test in the fast suite**

  Add `:tests.test-temporal-localization` near `:tests.test-temporal-calendar` in `assets/lua/tests/fast.fnl`.

- [ ] **Step 3: Verify tests fail because the facade is missing**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-localization:main
  ```

  Expected before implementation: fail with missing `Temporal.localization`.

- [ ] **Step 4: Implement localization module option validation**

  Create `assets/lua/temporal/localization.fnl` with allowed option keys exactly `:locale`, `:calendar`, and `:date-style`. Implement `validate-options` diagnostics containing `missing temporal localization locale`, `missing temporal localization calendar`, `missing temporal localization date-style`, `unknown temporal localization option`, `unsupported temporal locale`, `unsupported temporal calendar`, `unsupported temporal locale/calendar combination`, and `unsupported temporal date style`.

- [ ] **Step 5: Implement token formatting**

  Implement token formatting for fields `year`, `month`, `day`, `month-name`, `era`, `era-code`, `era-name`, and `literal`, including two-digit padding only when `width == 2`.

- [ ] **Step 6: Implement exact token parsing**

  Implement token parsing that consumes the entire input, accepts only exact seed month and era strings, returns calendar fields with midnight time, and throws `malformed localized text`, `invalid month name`, or `invalid era name` where appropriate.

- [ ] **Step 7: Implement public localization functions**

  Implement and export `supported-locales`, `supported-combinations`, `format-plain-date-time`, and `parse-plain-date-time`. `supported-combinations` must return `:short` before `:long` for each locale/calendar pair and be sorted by locale then calendar then date-style.

- [ ] **Step 8: Wire localization into `assets/lua/temporal.fnl`**

  Require `:temporal/localization`, instantiate it with `{:calendar calendar :seed seed}`, and add `:localization localization` to the public temporal table.

- [ ] **Step 9: Add export assertions to base temporal tests**

  In `assets/lua/tests/test-temporal.fnl`, assert `Temporal.localization` and its four public functions exist.

- [ ] **Step 10: Run focused Fennel validation ladder**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/localization.fnl --file assets/lua/temporal.fnl --file assets/lua/tests/test-temporal-localization.fnl --file assets/lua/tests/test-temporal.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-localization:main
  ```

  Expected: all pass.

- [ ] **Step 11: Commit Task 5**

  ```bash
  git add assets/lua/temporal/localization.fnl assets/lua/temporal.fnl assets/lua/tests/test-temporal-localization.fnl assets/lua/tests/test-temporal.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(lua): add Temporal.localization facade"
  ```

---

### Task 6: Documentation Updates

**Files:**
- Create: `docs/dev/features/temporal-localization-calendar.md`
- Modify: `docs/dev/features/temporal.md`
- Modify: `docs/dev/features/temporal-complete-library.md`
- Modify: `docs/dev/features/temporal-complete-acceptance.md`
- Modify: `docs/dev/notes/temporal-dependency-data-packaging.md`

**Interfaces:**
- Consumes: Public APIs, supported corpus, seed provenance, and validation commands from Tasks 1-5.
- Produces: Canonical docs/dev documentation for the behavior, architecture boundary, workflow, and operational assumptions.

- [ ] **Step 1: Create feature documentation page**

  Create `docs/dev/features/temporal-localization-calendar.md` with sections `# Temporal Localization and Calendar Seed`, `## Public APIs`, `## Supported seed corpus`, `## Calendar conversion rules`, `## Localization format and parse rules`, `## Packaged data and no-network behavior`, `## Native ICU4C adapter boundary`, and `## Validation commands`. Include the exact supported combinations table from the spec.

- [ ] **Step 2: Update temporal feature index**

  In `docs/dev/features/temporal.md`, add a link to `Temporal Localization and Calendar Seed`.

- [ ] **Step 3: Update complete library status**

  In `docs/dev/features/temporal-complete-library.md`, mark localization/calendar seed facade as implemented for the selected corpus and state full ICU4C/native adapter work remains future work.

- [ ] **Step 4: Update acceptance evidence page**

  In `docs/dev/features/temporal-complete-acceptance.md`, update the localization/calendar row with local evidence: `tests.test-temporal-calendar`, `tests.test-temporal-localization`, `python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q`, Space Fennel compile check, and `make constraints`.

- [ ] **Step 5: Update dependency packaging note**

  In `docs/dev/notes/temporal-dependency-data-packaging.md`, state that the selected CLDR seed is now packaged under `assets/temporal/icu/cldr-seed/`, while full ICU4C source/generated data remain future work.

- [ ] **Step 6: Validate docs references**

  ```bash
  rg "temporal-localization-calendar" docs/dev
  rg "cldr-seed" docs/dev assets/temporal external/temporal
  rg "SPACE_TEMPORAL_ENABLE_ICU_ADAPTER|temporal_localization" docs/dev/features/temporal-localization-calendar.md docs/dev/notes/temporal-dependency-data-packaging.md external/temporal/icu/DEPENDENCY_MANIFEST.json
  ```

  Expected: all commands find the new references.

- [ ] **Step 7: Commit Task 6**

  ```bash
  git add docs/dev/features/temporal-localization-calendar.md docs/dev/features/temporal.md docs/dev/features/temporal-complete-library.md docs/dev/features/temporal-complete-acceptance.md docs/dev/notes/temporal-dependency-data-packaging.md
  git commit -m "docs: document temporal localization calendar seed"
  ```

---

### Task 7: Final Integration Validation

**Files:**
- Modify only if validation exposes a reviewed defect in files from Tasks 1-6.

**Interfaces:**
- Consumes: Completed Tasks 1-6.
- Produces: Evidence that acceptance criteria are met before PR CI.

- [ ] **Step 1: Ensure build/runtime freshness**

  ```bash
  make build
  ```

- [ ] **Step 2: Run Fennel compile check first**

  ```bash
  make fennel-check
  ```

- [ ] **Step 3: Run constraints second**

  ```bash
  make constraints
  ```

- [ ] **Step 4: Run focused calendar test**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-calendar:main
  ```

- [ ] **Step 5: Run focused localization test**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-localization:main
  ```

- [ ] **Step 6: Run manifest/package tests**

  ```bash
  python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q
  ```

- [ ] **Step 7: Run broader local suite**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- [ ] **Step 8: Verify adapter remains disabled/out of scope**

  ```bash
  rg "SPACE_TEMPORAL_ENABLE_ICU_ADAPTER" CMakeLists.txt src apps external docs
  rg "temporal_localization" src assets/lua docs external
  ```

  Expected: no new C++ adapter, native binding, or enabled ICU adapter implementation is present.

- [ ] **Step 9: Review final diff for scope**

  ```bash
  git diff --stat origin/main...HEAD
  git diff --name-only origin/main...HEAD
  ```

  Expected changed paths are limited to the files named in this plan.

- [ ] **Step 10: Commit any reviewed validation fixes**

  Only if validation required fixes after implementer/reviewer routing:

  ```bash
  git add assets/temporal/icu/cldr-seed assets/temporal/manifest.json external/temporal/icu/DEPENDENCY_MANIFEST.json assets/temporal/icu/README.md assets/lua/temporal/cldr-seed.fnl assets/lua/temporal/calendar.fnl assets/lua/temporal/localization.fnl assets/lua/temporal.fnl assets/lua/tests/test-temporal-calendar.fnl assets/lua/tests/test-temporal-localization.fnl assets/lua/tests/test-temporal.fnl assets/lua/tests/fast.fnl scripts/check-temporal-dependency-manifests.py scripts/tests/test_temporal_dependency_manifests.py docs/dev/features/temporal-localization-calendar.md docs/dev/features/temporal.md docs/dev/features/temporal-complete-library.md docs/dev/features/temporal-complete-acceptance.md docs/dev/notes/temporal-dependency-data-packaging.md
  git commit -m "fix(lua): stabilize temporal localization calendar seed"
  ```

---

## Acceptance Criteria

- `Temporal.calendar` and `Temporal.localization` are exported from the public temporal facade.
- CLDR seed data is checked in under `assets/temporal/icu/cldr-seed/` with manifest/provenance and no-network metadata.
- ICU dependency manifest status is `packaged` with required provenance fields; full ICU4C source and adapter remain future work.
- Runtime temporal manifest lists the CLDR seed packaged data set.
- Supported calendar conversions round trip for `gregory`, `buddhist`, and the finite Japanese era corpus.
- Supported localization format/parse examples pass for `en-US`, `fr-FR`, and `ja-JP` selected combinations.
- Unsupported locales, calendars, styles, combinations, malformed localized text, invalid eras, and unknown option/record keys fail loudly.
- Native temporal core and C++ bindings remain unchanged.
- `SPACE_TEMPORAL_ENABLE_ICU_ADAPTER` continues to hard-fail in this slice.
- Focused tests, manifest validation, compile checks, constraints, broader local validation, PR CI, and merge queue pass.

## Out of Scope

- Vendoring ICU4C source.
- Enabling `SPACE_TEMPORAL_ENABLE_ICU_ADAPTER`.
- Adding a native `temporal_localization` adapter or C++ bindings.
- Importing full generated CLDR data.
- BCP47 locale negotiation, fallback chains, plural rules, range formatting, relative-time formatting, localized timezone names, and numbering-system substitution.
- Lunar or algorithmically complex calendars such as Islamic, Hebrew, or Chinese calendars.
- Arbitrary natural-language date parsing.
- Business calendars, holiday calendars, natural-language providers, timestamp migrations, and scheduler behavior.

## Validation Ladder

- Runtime/freshness prerequisite when `./build/space` may be missing or stale: `make build`.
- Focused Fennel compile check first: `make fennel-check`, or touched-file `tools.fennel-check` commands during Tasks 3-5.
- Constraints second: `make constraints`.
- Focused Fennel tests third: `tests.test-temporal-calendar` and `tests.test-temporal-localization`.
- Packaging validation: `python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q` and `ctest --test-dir build -R '^test_temporal_dependency_manifests$' --output-on-failure` when build exists.
- Broader local suite justified by public temporal facade and fast-suite surface: `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test`.
- Full integration gate: PR CI and merge queue.
- If Fennel delimiter or parse errors occur, inspect the nearest enclosing form around the reported location, split nested logic into helper functions, rerun compile check first, then constraints and focused tests.

## Self-Review Checklist

- [x] Spec coverage: plan covers public APIs, seed data, manifests, Fennel modules, tests, docs, validation, and native-adapter non-goals.
- [x] Placeholder scan: no TBD/implement-later placeholders remain.
- [x] Type consistency: seed functions, calendar APIs, localization APIs, record keys, option keys, and file paths are consistent across tasks.
- [x] Scope check: one PR-sized selected-corpus Track 8A slice; full ICU4C/native adapter remains future work.
