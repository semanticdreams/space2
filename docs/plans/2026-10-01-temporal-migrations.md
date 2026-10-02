# Temporal Persisted Timestamp Migrations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add explicit persisted timestamp migration helpers and integrate workflow JSON persistence so new workflow writes use canonical UTC instant strings while legacy numeric workflow timestamps still load safely.

**Architecture:** Introduce a pure Fennel `Temporal.migrations` module for timestamp conversion, schema-directed JSON file/tree migrations, and workflow schemas. Integrate only the workflow store call sites in this slice: load paths accept canonical strings or legacy integer seconds into numeric in-memory records; save paths write canonical strings through `JsonUtils.write-json!` without mutating cached records.

**Tech Stack:** Space Fennel modules/tests, native `temporal-core` `Instant`, `assets/lua/json-utils.fnl`, existing workflow store JSON persistence, Space validation commands.

## Global Constraints

- Runtime temporal work must not fetch network data.
- No host-local timezone defaults are allowed.
- Persisted timestamp migrations must be explicit, idempotent, and loud on malformed data.
- Existing in-memory workflow timestamp fields remain numeric epoch seconds in this slice for compatibility.
- Broad user-data rewrites must not run automatically at app startup.
- JSON rewrites must use `assets/lua/json-utils.fnl` atomic writes.
- Canonical option keys only; do not add aliases or compatibility shims.
- Migration errors must identify the schema, field/path, and file path when available.
- Canonical persisted timestamp representation is a UTC `Instant:to-string()` string, for example `"1970-01-01T00:00:00Z"`.
- Legacy numeric timestamps are interpreted only as integer Unix epoch seconds.
- Only workflow schemas and workflow store call sites are executable/integrated in this slice; other schema families are documented inventory only.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.

---

## File Structure

- `assets/lua/temporal/migrations.fnl`: public migration helpers, timestamp conversions, workflow schemas, file/tree migration helpers.
- `assets/lua/temporal.fnl`: exports `Temporal.migrations`.
- `assets/lua/workflows/store.fnl`: first integrated persistence call site for canonical timestamp JSON writes and legacy reads.
- `assets/lua/tests/test-temporal-migrations.fnl`: focused conversion, migration-helper, and workflow integration tests.
- `assets/lua/tests/fast.fnl`: focused suite registration.
- `docs/dev/features/temporal-migrations.md`: Track 11 feature docs and schema inventory.
- `docs/dev/features/temporal.md`: feature index link from temporal overview.
- `docs/dev/features/index.md`: global feature index link.
- `docs/dev/features/temporal-complete-library.md`: current roadmap status update.
- `docs/dev/features/temporal-complete-acceptance.md`: Track 11 evidence update.

---

### Task 1: `Temporal.migrations` API and Focused Tests

**Files:**
- Create: `assets/lua/temporal/migrations.fnl`
- Modify: `assets/lua/temporal.fnl`
- Modify: `assets/lua/tests/fast.fnl`
- Test: `assets/lua/tests/test-temporal-migrations.fnl`

**Interfaces:**
- Consumes: `temporal-core.instant.parse`, `temporal-core.instant.from-unix`, `Instant:to-string`, `Instant:epoch-seconds`, and `JsonUtils.write-json!`.
- Produces:
  - `Temporal.migrations.timestamp->instant(value, options) -> Instant|nil`
  - `Temporal.migrations.timestamp->epoch-seconds(value, options) -> number|nil`
  - `Temporal.migrations.instant->timestamp(value, options) -> string|nil`
  - `Temporal.migrations.migrate-json-file!(path, schema, options) -> table`
  - `Temporal.migrations.migrate-json-tree!(root, schema, options) -> table`
  - `Temporal.migrations.schemas.workflow-definition`
  - `Temporal.migrations.schemas.workflow-run`

- [ ] **Step 1: Add failing migration API tests.**

  Create `assets/lua/tests/test-temporal-migrations.fnl` following existing temporal test style. Include tests for:
  - numeric `0` converts to instant string `"1970-01-01T00:00:00Z"`;
  - canonical string remains unchanged through `instant->timestamp` / `timestamp->epoch-seconds` round trip;
  - nil with `{:optional? true}` returns nil;
  - nil without optional throws a `temporal migration` error;
  - fractional numeric timestamp throws;
  - malformed string throws and includes field/schema context;
  - unknown option key throws;
  - `migrate-json-file!` dry-run reports changes but does not write;
  - successful file migration rewrites integer seconds to canonical strings;
  - rerunning migration reports no changes;
  - malformed file data fails without rewriting;
  - workflow-run nested schema converts `events[]` and `steps` map timestamps.

- [ ] **Step 2: Register the focused suite.**

  Add `:tests.test-temporal-migrations` to `assets/lua/tests/fast.fnl` near the other temporal suites.

- [ ] **Step 3: Run focused tests and capture RED evidence.**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-migrations:main
  ```

  Expected: failure because `Temporal.migrations` does not exist yet.

- [ ] **Step 4: Implement conversion helpers.**

  Create `assets/lua/temporal/migrations.fnl`. Require `:temporal-core` and `:json-utils` directly; do not require `:temporal` from inside this module. Implement option validation for exact keys `:schema-id`, `:field-path`, `:file-path`, `:optional?`, and `:dry-run?`. Numeric values must be integers. Strings must parse as `Instant`. Nil is allowed only with `:optional? true`. Invalid values throw messages containing `temporal migration`, schema id, field path, and file path when supplied.

- [ ] **Step 5: Implement schema definitions.**

  Add `schemas.workflow-definition` for required fields `created-at` and `updated-at`. Add `schemas.workflow-run` for required `created-at`, optional `started-at` and `finished-at`, nested `steps.*.started-at` / `steps.*.finished-at`, and nested `events[].created-at`.

- [ ] **Step 6: Implement JSON migration helpers.**

  `migrate-json-file!` must read JSON, require an object root, convert only schema-described fields, write atomically via `JsonUtils.write-json!` only after all conversions succeed, and skip writes when `:dry-run? true` or no changes are needed. `migrate-json-tree!` must scan non-recursive `*.json` files in sorted order and aggregate file/change/conversion/error counts.

- [ ] **Step 7: Export the module.**

  In `assets/lua/temporal.fnl`, require `:temporal/migrations` and expose it as `:migrations migrations` in the public temporal table without changing existing namespaces.

- [ ] **Step 8: Run validation and commit.**

  Run:

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-migrations:main
  ```

  Expected: pass.

  Commit message: `feat(lua): add temporal migration helpers`

---

### Task 2: Workflow Store Persistence Call-Site Integration

**Files:**
- Modify: `assets/lua/workflows/store.fnl`
- Test: `assets/lua/tests/test-temporal-migrations.fnl`

**Interfaces:**
- Consumes:
  - `Temporal.migrations.timestamp->epoch-seconds(value, options) -> number|nil`
  - `Temporal.migrations.instant->timestamp(value, options) -> string|nil`
  - `Temporal.migrations.schemas.workflow-definition`
  - `Temporal.migrations.schemas.workflow-run`
- Produces: workflow JSON files with canonical string timestamps while preserving numeric in-memory workflow timestamp fields.

- [ ] **Step 1: Add failing workflow integration tests.**

  Extend `assets/lua/tests/test-temporal-migrations.fnl` to create a `WorkflowStore` in a temporary base dir, create/update a workflow definition, create/update a run, append an event, read raw JSON files under `workflows/definitions` and `workflows/runs`, and assert persisted timestamp fields are strings ending in `Z`. Also seed legacy numeric workflow definition/run JSON manually and assert a fresh `WorkflowStore` loads numeric in-memory fields.

- [ ] **Step 2: Run focused test and capture RED evidence.**

  Run the focused `tests.test-temporal-migrations:main` command from Task 1. Expected: failure because workflow store still persists numeric timestamps.

- [ ] **Step 3: Normalize workflow definition loads.**

  In `assets/lua/workflows/store.fnl`, require `:temporal`, bind `Temporal.migrations`, and update definition normalization so `created-at` and `updated-at` accept canonical strings or legacy integer seconds and return numeric seconds in memory. Missing or malformed required fields must fail loudly with schema/path/file context.

- [ ] **Step 4: Normalize workflow run loads.**

  Update run normalization so top-level `created-at` is required, top-level `started-at` / `finished-at` are optional, `steps.*.started-at` / `steps.*.finished-at` are optional, and `events[].created-at` is required. All in-memory normalized fields remain numeric seconds or nil.

- [ ] **Step 5: Convert definitions before saving.**

  Before `write-definition!` calls `JsonUtils.write-json!`, build a non-mutating JSON payload copy with `created-at` and `updated-at` converted to canonical strings via `instant->timestamp`. Do not mutate cached records to strings.

- [ ] **Step 6: Convert runs before saving.**

  Before `write-run!` calls `JsonUtils.write-json!`, build a non-mutating JSON payload copy with top-level, step, and event timestamp fields converted to canonical strings. Optional nil fields remain nil/absent according to the existing JSON shape.

- [ ] **Step 7: Run validation and commit.**

  Run:

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-migrations:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-workflow-runner:main
  ```

  Expected: pass.

  Commit message: `feat(lua): persist workflow timestamps canonically`

---

### Task 3: Developer Docs, Schema Inventory, and Validation

**Files:**
- Create: `docs/dev/features/temporal-migrations.md`
- Modify: `docs/dev/features/temporal.md`
- Modify: `docs/dev/features/index.md`
- Modify: `docs/dev/features/temporal-complete-library.md`
- Modify: `docs/dev/features/temporal-complete-acceptance.md`

**Interfaces:**
- Consumes: public `Temporal.migrations` API and workflow store behavior from Tasks 1-2.
- Produces: canonical Track 11 documentation and final local validation evidence.

- [ ] **Step 1: Add feature documentation.**

  Create `docs/dev/features/temporal-migrations.md` documenting canonical persisted timestamp representation, explicit helper APIs, dry-run/per-file migration flow, malformed-data diagnostics, idempotency, and the guarantee that this slice does not run broad automatic user-data rewrites.

- [ ] **Step 2: Add schema inventory.**

  In the new doc, include the inventory from the design: workflow definitions/runs, legacy agent sessions, code entities, conversations, and messages. Mark workflow schemas as executable/integrated in this slice and all other families as inventory-only follow-up work.

- [ ] **Step 3: Link docs and update roadmap status.**

  Add the temporal migrations page to `docs/dev/features/index.md`. Link it from `docs/dev/features/temporal.md`. Update `docs/dev/features/temporal-complete-library.md` current status to include Track 11 and keep Track 12-13 exclusions explicit. Update `docs/dev/features/temporal-complete-acceptance.md` with concrete Track 11 evidence commands.

- [ ] **Step 4: Run documentation search checks.**

  Run:

  ```bash
  rg "Temporal.migrations|canonical persisted timestamp|workflows/definitions|agent-sessions|entities/code|llm/conversations|dry-run|idempotent" docs/dev/features/temporal-migrations.md docs/dev/features/temporal.md docs/dev/features/index.md docs/dev/features/temporal-complete-acceptance.md docs/dev/features/temporal-complete-library.md
  ```

  Expected: output shows the new docs and links consistently mention the migration scope.

- [ ] **Step 5: Run complete relevant local validation.**

  Run:

  ```bash
  make build
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-migrations:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-workflow-runner:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: pass.

- [ ] **Step 6: Commit docs and validation evidence.**

  Commit message: `docs(lua): document temporal timestamp migrations`

---

### Task 4: Final Track Validation

**Files:**
- No production file changes; validation-only task.

**Interfaces:**
- Consumes: all previous task outputs.
- Produces: final local validation evidence for SDD and finishing workflow.

- [ ] **Step 1: Verify clean validation-only start.**

  Confirm no uncommitted production/test/doc changes are present before validation.

- [ ] **Step 2: Run build and Fennel gates.**

  Run:

  ```bash
  make build
  make fennel-check
  make constraints
  ```

  Expected: pass.

- [ ] **Step 3: Run focused suites.**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH=$(pwd)/assets \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-temporal-migrations:main
  ```

  Repeat for `tests.test-workflow-runner:main`.

- [ ] **Step 4: Run broad suite.**

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: pass.

- [ ] **Step 5: Handoff to finishing workflow.**

  Confirm clean tree, record validation evidence, and use the finishing workflow to fetch `origin/main`, safe-merge if required, rerun validation after any merge, push, create/update PR, enable auto-merge/queue, and poll until merged.
