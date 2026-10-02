# Temporal Persisted Timestamp Migrations Design

## Purpose

Track 11 adds the first production migration layer for persisted timestamp fields. It introduces `Temporal.migrations`, documents the persisted timestamp schema inventory, and integrates one durable store family (`workflows`) so new workflow JSON writes use canonical temporal strings while legacy numeric timestamp files still load safely.

## Invariants

- Runtime temporal work must not fetch network data.
- No host-local timezone defaults are allowed.
- Persisted timestamp migrations must be explicit, idempotent, and loud on malformed data.
- Existing in-memory workflow timestamp fields remain numeric epoch seconds in this slice for compatibility.
- Broad user-data rewrites must not run automatically at app startup.
- JSON rewrites must use `assets/lua/json-utils.fnl` atomic writes.
- Canonical option keys only; do not add aliases or compatibility shims.
- Migration errors must identify the schema, field/path, and file path when available.

## Design choice

Use canonical UTC instant strings for persisted JSON and explicit migration helpers for controlled rewrites.

### Considered approaches

1. **Canonical UTC instant strings — selected.**
   - Pros: human-readable, unambiguous, idempotent, aligns with `Instant:to-string`, and avoids host timezone interpretation.
   - Cons: existing stores using numeric seconds need conversion at load/save boundaries.
2. **Keep numeric epoch seconds everywhere.**
   - Pros: minimal code churn.
   - Cons: does not advance the persisted-data migration contract and remains ambiguous about precision/semantics in JSON.
3. **Structured timestamp objects such as `{epoch-seconds, nanosecond}`.**
   - Pros: explicit precision fields and future nanosecond support.
   - Cons: verbose for current second-resolution app data and harder to audit manually.

## Canonical representation

Persisted JSON timestamps use `Instant:to-string()` UTC strings, for example:

```json
"1970-01-01T00:00:00Z"
```

Legacy numeric timestamps are interpreted only as integer Unix epoch seconds. Fractional numbers, booleans, tables, malformed strings, and missing required timestamp fields are invalid. Optional timestamp fields may be nil only when a schema marks them optional.

In-memory workflow records keep numeric epoch seconds in this slice so existing workflow runner code and tests do not need broad semantic changes. Save paths convert numeric in-memory values to canonical strings immediately before writing JSON. Load paths convert canonical strings or legacy integer seconds to numeric in-memory values.

## Public API

`Temporal.migrations` exposes:

- `timestamp->instant(value, options) -> Instant|nil`
- `timestamp->epoch-seconds(value, options) -> number|nil`
- `instant->timestamp(value, options) -> string|nil`
- `migrate-json-file!(path, schema, options) -> result-table`
- `migrate-json-tree!(root, schema, options) -> summary-table`
- `schemas.workflow-definition`
- `schemas.workflow-run`

Allowed option keys are:

- `:schema-id` — diagnostic schema id when converting an isolated value.
- `:field-path` — diagnostic JSON path/field when converting an isolated value.
- `:file-path` — diagnostic file path for error messages.
- `:optional?` — permits nil for optional fields.
- `:dry-run?` — prevents writes in file/tree migration helpers.

Unknown option keys are errors. Helper result tables include enough information for tests and future tooling: file count, changed-file count, converted-field count, error count, and per-file status where applicable.

## Initial schema inventory

Track 11 inventories these persisted timestamp families:

- Workflow definitions: `workflows/definitions/*.json`
  - `created-at`, `updated-at`
- Workflow runs: `workflows/runs/*.json`
  - `created-at`, `started-at`, `finished-at`
  - `steps.*.started-at`, `steps.*.finished-at`
  - `events[].created-at`
- Legacy agent sessions: `agent-sessions/*.json`
  - top-level `created-at`, `updated-at`
  - `items[].created-at`, `items[].updated-at`
  - known nested provider timestamp fields such as `data.runtime-context.last-live-connection-at`
- Code entities: `entities/code/*.json`
  - `created-at`, `updated-at`
- Conversations/messages:
  - `llm/conversations/*.json`: `created_at`, `updated_at`, `archived_at`
  - `llm/messages/*.json`: `created_at`, `updated_at`

Only workflow schemas and workflow store call sites are executable/integrated in this slice. Other schema families are documented inventory for later per-subsystem migrations.

## Workflow call-site integration

`assets/lua/workflows/store.fnl` becomes the first integrated call site:

- Load/normalize paths accept both legacy integer seconds and canonical instant strings.
- In-memory workflow records remain numeric seconds.
- Save paths build a JSON payload copy with canonical string timestamps and write via `JsonUtils.write-json!`.
- Required fields fail loudly when missing or malformed.
- Optional fields such as `started-at` and `finished-at` may be nil.
- Nested workflow run timestamps in `steps` and `events` follow the same conversion rules.

This integration proves the migration boundary without automatically rewriting all user data. A legacy numeric workflow file is rewritten only when normal workflow save/update code touches it or when an explicit migration helper is called.

## Explicit migration helpers

`migrate-json-file!` reads one JSON file, validates the root object, converts fields described by the supplied schema, and writes atomically only after all conversions succeed. It skips writes for `:dry-run? true` and for already canonical files.

`migrate-json-tree!` scans non-recursive `*.json` files in sorted order and aggregates results. It does not delete, archive, or recursively traverse arbitrary user directories.

Both helpers are idempotent: rerunning against canonical files reports no changes and performs no write.

## Error handling

Malformed data fails before any write. Error messages include `temporal migration`, schema id, field/path, and file path when available. Examples of invalid data:

- fractional numeric timestamps;
- malformed timestamp strings;
- table/boolean timestamp values;
- missing required fields;
- non-object JSON roots for schema migrations.

No failure is converted into a silent no-op.

## Tests and acceptance evidence

Focused acceptance requires:

- conversion helper tests for numeric seconds, canonical strings, optional nil, malformed strings, fractional numbers, and invalid types;
- per-file migration tests for dry-run/no-write, successful rewrite, idempotent rerun, and malformed-data no-write behavior;
- workflow-run nested schema migration tests for `events[]` and `steps` map timestamps;
- workflow store integration tests proving canonical JSON writes and legacy numeric JSON loads;
- schema inventory docs;
- fast-suite registration.

Validation commands:

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
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Run `make build` first if `./build/space` is missing or stale.

## Out of scope

- Automatic app-start or whole-profile migration.
- Rewriting all existing user data trees in this slice.
- Code entity, conversation/message, graph, home-world, or legacy agent-session call-site integration.
- Runtime scheduler changes.
- Nanosecond-producing application timestamps beyond parsing/formatting canonical strings.
- CLI UX beyond callable helper APIs.
- Host timezone or locale inference.

Future slices can integrate additional schema families one subsystem at a time using the same explicit helper and test contract.
