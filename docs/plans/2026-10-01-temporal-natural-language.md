# Temporal Natural Language Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic packaged `Temporal.natural` candidate parsing for `en-US`, `fr-FR`, and `ja-JP`, preserving existing unambiguous English parse behavior while adding ambiguity, context diagnostics, and provider integration.

**Architecture:** Package a reviewed JSON phrase corpus under `assets/temporal/natural/seed/`, validate it through the temporal manifest checker, load it with a focused Fennel corpus module, and match phrases in a pure Fennel `Temporal.natural` facade. Register the built-in parser as a local `Temporal.providers` natural provider; do not add native C++ parsing or network/model integration.

**Tech Stack:** Space Fennel modules/tests, JSON packaged asset data, Python manifest validation, existing `Temporal.expression.resolve`, existing `Temporal.providers` dispatch, Space validation commands.

## Global Constraints

- Runtime temporal work must not fetch network data.
- Natural-language parsing remains policy/provider behavior, not native temporal core behavior.
- No host locale, host timezone, or host calendar defaults are allowed.
- Exact `Duration` remains nanoseconds-only; natural parsing may produce expressions and recurrence rules, not implicit business-day or fuzzy-duration values.
- All option keys are canonical; unsupported option keys and unsupported locales fail loudly.
- Ambiguous input must produce explicit candidates or an ambiguity error; it must not be resolved by guessing.
- Missing context for resolution must be diagnosed explicitly.
- Initial locales are exactly `en-US`, `fr-FR`, and `ja-JP`.
- Initial phrase families are exactly relative literals, relative count offsets, next weekday, weekly weekday recurrence, and bare weekday ambiguity.
- Provider id is exactly `space.temporal.natural-seed`.
- Dataset id is exactly `natural-phrase-seed`.
- Version is exactly `natural-phrase-seed-2026-10-track10`.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.

---

## File Structure

- `assets/temporal/natural/seed/manifest.json`: seed metadata, locale list, provenance, version, no-network flag.
- `assets/temporal/natural/seed/phrases.json`: locale phrase families and weekday symbols.
- `assets/temporal/manifest.json`: runtime packaged dataset registration.
- `scripts/check-temporal-dependency-manifests.py`: natural seed validator.
- `scripts/tests/test_temporal_dependency_manifests.py`: natural seed validator tests.
- `assets/lua/temporal/natural-corpus.fnl`: focused corpus loader/validator.
- `assets/lua/temporal/natural.fnl`: candidate matcher, parse compatibility, resolve helper, provider manifest.
- `assets/lua/temporal.fnl`: inject corpus/expression/providers and register built-in provider.
- `assets/lua/tests/test-temporal-natural-language.fnl`: focused Track 10 natural tests.
- `assets/lua/tests/test-temporal-parsing-recurrence.fnl`: keep or update old compatibility expectations if needed.
- `assets/lua/tests/test-temporal-provider-registry.fnl`: default built-in provider integration tests.
- `assets/lua/tests/fast.fnl`: focused suite registration.
- `docs/dev/features/temporal-natural-language.md`: Track 10 feature docs.
- `docs/dev/features/temporal.md`, `docs/dev/features/temporal-complete-library.md`, `docs/dev/features/temporal-complete-acceptance.md`, and `docs/dev/notes/temporal-dependency-data-packaging.md`: feature index/status/evidence/packaging docs.

---

### Task 1: Package Natural Phrase Corpus and Manifest Validation

**Files:**
- Create: `assets/temporal/natural/seed/manifest.json`
- Create: `assets/temporal/natural/seed/phrases.json`
- Modify: `assets/temporal/manifest.json`
- Modify: `assets/temporal/README.md`
- Modify: `scripts/check-temporal-dependency-manifests.py`
- Test: `scripts/tests/test_temporal_dependency_manifests.py`

**Interfaces:**
- Consumes: existing `validate_repo(repo_root: Path) -> list[str]` temporal manifest checker.
- Produces: packaged dataset `natural-phrase-seed`, provider `space.temporal.natural-seed`, version `natural-phrase-seed-2026-10-track10`, and `phrases.json` for Task 2.

- [ ] **Step 1: Add failing Python tests for the natural seed.**

  Add tests to `scripts/tests/test_temporal_dependency_manifests.py` using the existing temporal-tree copy helper. Cover:
  - missing `assets/temporal/natural/seed/phrases.json`;
  - locale mismatch between `manifest.json` `supported_locales` and `phrases.json` `locale_order`;
  - `runtime_network_fetch_allowed: true` in the natural seed manifest;
  - missing `natural-phrase-seed` entry from `assets/temporal/manifest.json`;
  - duplicate `natural-phrase-seed` entry.

  Example expected assertion:

  ```python
  def test_natural_seed_requires_phrases_file(tmp_path: Path) -> None:
      root = copy_temporal_tree(tmp_path)
      (root / "assets/temporal/natural/seed/phrases.json").unlink()
      errors = manifests.validate_repo(root)
      assert any("natural-phrase-seed" in error and "phrases.json" in error for error in errors)
  ```

- [ ] **Step 2: Run the tests and capture RED evidence.**

  Run: `python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q`

  Expected: failures because natural seed files/validation do not exist yet.

- [ ] **Step 3: Add the natural seed manifest.**

  Create `assets/temporal/natural/seed/manifest.json` with:

  ```json
  {
    "schema_version": 1,
    "id": "natural-phrase-seed",
    "provider_id": "space.temporal.natural-seed",
    "version": "natural-phrase-seed-2026-10-track10",
    "supported_locales": ["en-US", "fr-FR", "ja-JP"],
    "runtime_network_fetch_allowed": false,
    "source": "Hand-authored Space temporal natural-language seed corpus",
    "license": "Project license",
    "update_process": "Update phrases.json and this manifest in the same reviewed change; runtime parsing must remain deterministic and offline."
  }
  ```

- [ ] **Step 4: Add the phrase corpus.**

  Create `assets/temporal/natural/seed/phrases.json` with top-level fields:
  - `schema_version: 1`
  - `provider_id: "space.temporal.natural-seed"`
  - `version: "natural-phrase-seed-2026-10-track10"`
  - `locale_order: ["en-US", "fr-FR", "ja-JP"]`
  - `weekday_symbols: ["mo", "tu", "we", "th", "fr", "sa", "su"]`
  - `locales` object keyed by locale.

  Each locale contains phrase family entries for:
  - `relative_literals`: today/tomorrow equivalents.
  - `relative_count_offsets`: day/week singular/plural patterns using ASCII digits.
  - `next_weekday`: prefix plus localized weekday names.
  - `weekly_weekday_recurrence`: prefix plus localized weekday names.
  - `bare_weekday_ambiguity`: localized weekday names.

- [ ] **Step 5: Register the dataset.**

  Add this entry to `assets/temporal/manifest.json`:

  ```json
  {
    "id": "natural-phrase-seed",
    "provider_id": "space.temporal.natural-seed",
    "version": "natural-phrase-seed-2026-10-track10",
    "root": "assets/temporal/natural/seed",
    "manifest": "assets/temporal/natural/seed/manifest.json",
    "runtime_network_fetch_allowed": false,
    "files": ["phrases.json"]
  }
  ```

  Update `assets/temporal/README.md` to mention the packaged natural phrase seed.

- [ ] **Step 6: Extend the manifest validator.**

  In `scripts/check-temporal-dependency-manifests.py`, add constants for natural seed id/provider/version/locales. Validate exactly one runtime dataset entry; validate required files; load seed manifest and phrase corpus; require no-network flags, matching provider/version, exact locale order, required families, and `weekday_symbols` exactly `['mo', 'tu', 'we', 'th', 'fr', 'sa', 'su']`.

- [ ] **Step 7: Run validator tests and commit.**

  Run: `python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q`

  Expected: pass.

  Commit message: `feat(assets): add temporal natural phrase seed`

---

### Task 2: Corpus Loader, Candidate Parser, and Provider

**Files:**
- Create: `assets/lua/temporal/natural-corpus.fnl`
- Modify: `assets/lua/temporal/natural.fnl`
- Modify: `assets/lua/temporal.fnl`
- Test: `assets/lua/tests/test-temporal-natural-language.fnl`
- Test: `assets/lua/tests/test-temporal-parsing-recurrence.fnl`

**Interfaces:**
- Consumes: Task 1 natural seed files and existing `Temporal.expression.resolve` / recurrence expression shapes.
- Produces: `Temporal.natural.candidates(text, options)`, `Temporal.natural.parse(text, options)`, `Temporal.natural.resolve(text, context)`, and `Temporal.natural.provider()`.

- [ ] **Step 1: Add focused natural-language test module with RED tests.**

  Create `assets/lua/tests/test-temporal-natural-language.fnl` with helper assertions and tests for:
  - `Temporal.natural.parse "today"` returns current `:relative-date` expression shape;
  - `Temporal.natural.parse "in 2 weeks"` remains compatible;
  - `Temporal.natural.candidates "today" {:locale "en-US"}` returns candidate schema fields;
  - `Temporal.natural.candidates` handles `fr-FR` and `ja-JP` relative literals;
  - bare weekday text returns at least two candidates and `parse` throws ambiguity;
  - unsupported locale throws;
  - unknown option key throws;
  - `Temporal.natural.resolve` rejects missing context.

- [ ] **Step 2: Run focused tests and capture RED evidence.**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-natural-language:main
  ```

  Expected: failure because the new APIs/module do not exist yet.

- [ ] **Step 3: Implement `natural-corpus.fnl`.**

  Follow the existing seed loader style from `cldr-seed.fnl` and `holiday-seed.fnl`. Expose:
  - `load() -> table`
  - `supported-locales() -> array<string>`
  - `locale-data(locale: string) -> table`

  Validate schema/provider/version/locale order/required phrase families/no-network metadata and return defensive copies from public helpers.

- [ ] **Step 4: Implement candidate parsing in `natural.fnl`.**

  Accept only option key `:locale`. For candidate records use exactly:
  - `:kind :natural-candidate`
  - `:provider-id "space.temporal.natural-seed"`
  - `:locale`
  - `:phrase-id`
  - `:family`
  - `:matched-text`
  - `:rank`
  - `:expression`
  - `:requires-context`

  Preserve existing English `parse` return expressions for unambiguous phrases. Return `[]` from `candidates` for unsupported text. Throw `unsupported temporal natural expression` from `parse` for unsupported text and `ambiguous temporal natural expression` for ambiguous text.

- [ ] **Step 5: Implement resolve and provider APIs.**

  `resolve(text, context)` must require a table context and call `Temporal.expression.resolve` on the unambiguous expression. It throws `temporal natural resolve context is required` for nil/non-table context and `temporal natural resolve context requires reference plain date-time or reference instant with zone id` when reference data is missing.

  `provider()` returns a manifest with id/version/priority/capabilities and parse function. The parse function returns candidate arrays.

- [ ] **Step 6: Wire the facade.**

  In `assets/lua/temporal.fnl`, require `:temporal/natural-corpus`, create natural with dependencies including `recurrence`, `expression`, and corpus, then register `natural.provider()` with `providers`. Ensure the provider registry is created before registration and that no native C++ changes are made.

- [ ] **Step 7: Update old natural tests if necessary.**

  Keep compatibility expectations in `assets/lua/tests/test-temporal-parsing-recurrence.fnl`. If current tests import the old parser, update only to preserve existing unambiguous behavior and add no broad new expectations there.

- [ ] **Step 8: Run validation and commit.**

  Run:

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-natural-language:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected: pass.

  Commit message: `feat(lua): add temporal natural language candidates`

---

### Task 3: Provider Integration Tests, Fast Suite, and Docs

**Files:**
- Modify: `assets/lua/tests/test-temporal-provider-registry.fnl`
- Modify: `assets/lua/tests/fast.fnl`
- Create: `docs/dev/features/temporal-natural-language.md`
- Modify: `docs/dev/features/temporal.md`
- Modify: `docs/dev/features/temporal-complete-library.md`
- Modify: `docs/dev/features/temporal-complete-acceptance.md`
- Modify: `docs/dev/notes/temporal-dependency-data-packaging.md`

**Interfaces:**
- Consumes: Task 2 `Temporal.natural` and default provider registration.
- Produces: provider acceptance coverage, fast-suite registration, and docs/status updates.

- [ ] **Step 1: Add provider integration tests.**

  In `test-temporal-provider-registry.fnl`, add tests asserting:
  - `Temporal.providers.parse "today" {:locale "en-US"}` returns at least one candidate;
  - returned candidate has `provider-id` equal to `space.temporal.natural-seed`;
  - repeated calls return deterministic order;
  - unsupported text returns an empty array through provider parse rather than throwing.

- [ ] **Step 2: Register the focused suite in fast tests.**

  Add `:tests.test-temporal-natural-language` to `assets/lua/tests/fast.fnl` near other temporal suites.

- [ ] **Step 3: Add feature documentation.**

  Create `docs/dev/features/temporal-natural-language.md` documenting supported locales, phrase families, candidate schema, ambiguity behavior, missing-context diagnostics, provider integration, no-network/no-host-default invariants, validation commands, and out-of-scope items.

- [ ] **Step 4: Update status and packaging docs.**

  Update `docs/dev/features/temporal.md` with the new feature page. Update `temporal-complete-library.md` current status to include Track 10 while keeping remaining Track 11-13 exclusions explicit. Update `temporal-complete-acceptance.md` with concrete Track 10 evidence. Update `docs/dev/notes/temporal-dependency-data-packaging.md` with `assets/temporal/natural/seed/`.

- [ ] **Step 5: Run searches and validation, then commit.**

  Run:

  ```bash
  rg "natural-phrase-seed|space.temporal.natural-seed|Temporal.natural" docs/dev assets/temporal assets/lua/tests
  rg "host locale|network|ambiguous temporal natural expression|temporal natural resolve context" docs/dev assets/lua/temporal assets/lua/tests
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-provider-registry:main
  ```

  Expected: searches show consistent docs/code references; validation passes.

  Commit message: `docs(lua): document temporal natural language parsing`

---

### Task 4: Final Track Validation

**Files:**
- No production file changes; validation-only task.

**Interfaces:**
- Consumes: all prior task outputs.
- Produces: final local validation evidence for SDD and finishing workflow.

- [ ] **Step 1: Ensure runtime freshness.**

  Run `make build` with a 4-hour timeout if `./build/space` may be missing or stale. Running it is acceptable final evidence because this changes public Fennel/data surfaces.

- [ ] **Step 2: Run compile check.**

  Run: `make fennel-check`

  Expected: pass.

- [ ] **Step 3: Run constraints.**

  Run: `make constraints`

  Expected: pass.

- [ ] **Step 4: Run Python manifest tests.**

  Run: `python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q`

  Expected: pass.

- [ ] **Step 5: Run focused Fennel suites.**

  Run natural-language, provider-registry, and existing temporal parsing/recurrence focused suites with `SPACE_DISABLE_AUDIO=1`, `SKIP_KEYRING_TESTS=1`, `XDG_DATA_HOME=/tmp/space/tests/xdg-data`, absolute `SPACE_ASSETS_PATH=$(pwd)/assets`, and Fennel paths:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-natural-language:main
  ```

  Repeat for `tests.test-temporal-provider-registry:main` and `tests.test-temporal-parsing-recurrence:main`.

- [ ] **Step 6: Run broader suite.**

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: pass.

- [ ] **Step 7: Handoff to finishing workflow.**

  Confirm clean tree, record validation evidence, and use finishing workflow to fetch `origin/main`, safe-merge if required, rerun validation after any merge, push, create/update PR, enable auto-merge/queue, and poll until merged.
