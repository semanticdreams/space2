# Temporal Persisted Timestamp Migrations

Track 11 adds the developer-facing contract for persisted JSON timestamps and the first executable migration boundary. Persisted timestamp fields use a canonical UTC `Instant:to-string()` string such as `"1970-01-01T00:00:00Z"`; legacy numeric values are accepted only as integer Unix epoch seconds at explicit migration or workflow load boundaries.

The goal is an explicit, idempotent, and loud migration path. Runtime temporal work does not fetch network data, no host-local timezone default is inferred, and broad user-data rewrites do not run automatically at app startup.

## Public API

`Temporal.migrations` is exported from `(require :temporal)` and exposes:

- `timestamp->instant(value, options) -> Instant|nil`
- `timestamp->epoch-seconds(value, options) -> number|nil`
- `instant->timestamp(value, options) -> string|nil`
- `migrate-json-file!(path, schema, options) -> table`
- `migrate-json-tree!(root, schema, options) -> table`
- `schemas.workflow-definition`
- `schemas.workflow-run`

Allowed option keys are canonical only:

- `:schema-id` — schema identifier for standalone conversion diagnostics.
- `:field-path` — field or JSON path for diagnostics.
- `:file-path` — file path for diagnostics.
- `:optional?` — permits nil when the schema marks a timestamp optional.
- `:dry-run?` — reports conversions without writing during file or tree migrations.

Unknown option keys are errors; do not add aliases or compatibility shims.

## Conversion rules

- Canonical strings are parsed as `Instant` values and formatted through `Instant:to-string()`.
- Legacy numeric values are interpreted only as integer Unix epoch seconds.
- Fractional numbers, booleans, tables, malformed strings, and missing required fields are malformed data.
- Optional fields may be nil only when the schema or call site passes `:optional? true`.
- Workflow in-memory records remain numeric epoch seconds in this slice for compatibility with existing workflow runner behavior.

## File and tree migration flow

Use `migrate-json-file!` for a single JSON object file and `migrate-json-tree!` for a non-recursive sorted scan of `*.json` files under a schema-specific root. Both helpers validate the full schema-described payload before writing. JSON rewrites use `assets/lua/json-utils.fnl` atomic writes and happen only when conversions are needed and `:dry-run?` is not set.

A typical safe flow is:

1. Run a `:dry-run? true` migration for the selected schema and inspect the result table.
2. Fix any malformed-data diagnostics before rewriting.
3. Run the same migration without `:dry-run?` for the selected file or directory.
4. Rerun the migration to confirm idempotent no-change behavior.

The helpers are idempotent: canonical files report no conversions and are not rewritten. A malformed file fails before any write, and failures are not converted into silent no-ops.

## Diagnostics

Migration failures include `temporal migration` plus the schema, field/path, and file path when available. Examples of invalid input that must fail loudly include fractional epoch seconds, malformed timestamp strings, missing required timestamp fields, non-object JSON roots, and unsupported timestamp value types.

## Integrated workflow behavior

Workflows are the only executable/integrated persisted timestamp schemas in this slice.

- New writes under `workflows/definitions/*.json` and `workflows/runs/*.json` persist canonical UTC instant strings.
- Workflow loads accept canonical strings and legacy integer seconds.
- Normalized in-memory workflow records keep numeric epoch seconds.
- Save paths build JSON payload copies and do not mutate cached workflow records to strings.
- A legacy numeric workflow file is rewritten only when normal workflow save/update code touches it or when an explicit migration helper is called.

## Schema inventory

| Family | Files | Timestamp fields | Track 11 status |
| --- | --- | --- | --- |
| Workflow definitions | `workflows/definitions/*.json` | `created-at`, `updated-at` | Executable/integrated via `Temporal.migrations.schemas.workflow-definition` and workflow store load/save call sites. |
| Workflow runs | `workflows/runs/*.json` | `created-at`, `started-at`, `finished-at`, `steps.*.started-at`, `steps.*.finished-at`, `events[].created-at` | Executable/integrated via `Temporal.migrations.schemas.workflow-run` and workflow store load/save call sites. |
| Legacy agent sessions | `agent-sessions/*.json` | top-level `created-at`, `updated-at`; `items[].created-at`, `items[].updated-at`; known nested provider timestamp fields such as `data.runtime-context.last-live-connection-at` | Inventory-only follow-up work. |
| Code entities | `entities/code/*.json` | `created-at`, `updated-at` | Inventory-only follow-up work. |
| Conversations | `llm/conversations/*.json` | `created_at`, `updated_at`, `archived_at` | Inventory-only follow-up work. |
| Messages | `llm/messages/*.json` | `created_at`, `updated_at` | Inventory-only follow-up work. |

Future slices should integrate the inventory-only families one subsystem at a time, using the same explicit dry-run, idempotent rewrite, atomic-write, and loud-diagnostic contract.

## Validation

Focused Track 11 validation runs the Fennel compile gate, constraints, migration helper tests, workflow runner tests, and the broader local suite when preparing final acceptance. Docs-only edits can additionally be checked with:

```bash
rg "Temporal.migrations|canonical persisted timestamp|workflows/definitions|agent-sessions|entities/code|llm/conversations|dry-run|idempotent" docs/dev/features/temporal-migrations.md docs/dev/features/temporal.md docs/dev/features/index.md docs/dev/features/temporal-complete-acceptance.md docs/dev/features/temporal-complete-library.md
```
