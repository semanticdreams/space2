---
type: dev-note
tags:
  - note
---

# Graph Identity Nodes

See also:
- [morphs](./morphs)

## Purpose

Identity nodes provide stable references for graph content whose concrete key/type may change over time.

Example:
- A notebook item currently points to `string-entity:abc`.
- Later, that entity is morphed into another type with a new key.
- If the notebook item points to `identity:xyz` instead, only the identity target changes and the notebook reference stays stable.

## Current Implementation

### New identity entity store
- File: `assets/lua/entities/identity.fnl`
- Data model:
  - `id`
  - `target-key`
  - `created-at`
  - `updated-at`
  - `metadata`
- API:
  - `create-entity`
  - `get-entity`
  - `update-entity`
  - `delete-entity`
  - `list-entities`
  - `find-by-target-key` (used for dedupe)

### New identity graph node + view
- Node: `assets/lua/graph/nodes/identity.fnl`
- View: `assets/lua/graph/view/views/identity.fnl`
- Key format: `identity:<id>`
- Node behavior:
  - exposes `identity-target-key`
  - updates target via store
  - supports opening target from identity node

### Loader registration
- Built-in descriptor family: `assets/lua/graph/extensions/builtins/entities.fnl`
- The `identity` scheme loader is installed through the app graph extension registry.

### Graph-level resolution
- File: `assets/lua/graph/core.fnl`
- New APIs:
  - `graph:resolve-key(key)`:
    - follows identity chains
    - includes cycle detection and max-depth guard
  - `graph:resolve-node(key-or-node)`:
    - resolves final key then returns/loads node
  - `graph:create-identity(target-key, opts)`:
    - creates identity entity and node
  - `graph:ensure-identity-key(target-key, opts)`:
    - returns existing identity key for target if one exists
    - otherwise creates and returns new identity key

### Identity-aware integrations
- Link entities:
  - link edge building now resolves `source-key` and `target-key` through identity before connecting edges.
  - identity update/delete events refresh affected link edges.
  - File: `assets/lua/graph/core.fnl`
- Notebook node:
  - item-edge construction resolves item keys via `graph:resolve-node`.
  - add-item now auto-wraps non-identity keys into identity keys.
  - dedupes by reusing existing identity for same target key.
  - File: `assets/lua/graph/nodes/notebook.fnl`
- Notebook preview view:
  - item preview resolves via `graph:resolve-node`.
  - File: `assets/lua/graph/view/views/notebook.fnl`
- List entity node:
  - item-edge construction resolves via `graph:resolve-node`.
  - add-item now auto-wraps non-identity keys into identity keys.
  - dedupes by reusing existing identity for same target key.
  - File: `assets/lua/graph/nodes/list-entity.fnl`

## Notebook Auto-Wrap Policy (Current)

When adding an item to a notebook:
1. If key already starts with `identity:`, store it unchanged.
2. Otherwise, wrap to an identity key.
3. Reuse existing identity for same target-key if present.

This gives notebooks stable references by default.

## Tests Added/Updated

- `assets/lua/tests/test-identity-entities.fnl`
  - store create/update/signal behavior
  - `find-by-target-key`
- `assets/lua/tests/test-graph-core.fnl`
  - resolve identity key to target
  - link edges resolve identity endpoints
  - create-identity behavior
  - ensure-identity-key dedupe behavior
- `assets/lua/tests/test-graph-loaders.fnl`
  - identity loader/module export coverage
- `assets/lua/tests/test-notebooks.fnl`
  - notebook add-item wraps non-identity key
  - notebook dedupes identity wrapper for same target
  - notebook add-string-entity now expects stored identity key
- `assets/lua/tests/test-list-entities.fnl`
  - list add-item wraps non-identity key
  - list dedupes identity wrapper for same target
- Included in fast suite:
  - `assets/lua/tests/fast.fnl` includes `:tests.test-identity-entities`

## What Is Still Left To Do

### 1. Add more morph targets
- Current morph infra exists and includes `string-entity -> code-entity`.
- Next work is adding additional type-to-type morphs using the same event contract.

### 2. Expand morph e2e coverage
- Notebook/list now refresh on identity updates and post-morph graph events.
- Add explicit end-to-end visual regression coverage for notebook/list preview/type-label updates after morph.

### 3. Decide list-entity write policy
- List add-item now auto-wraps to identity keys.
- Remaining decision: whether to migrate existing list rows that still contain raw keys.

### 4. Migration strategy for persisted data
- Existing notebook/list/link data may contain direct non-identity keys.
- Decide whether to:
  - migrate lazily on write, or
  - run one-time migration script.

### 5. UX entry points for creating identity
- Add explicit UI actions (start/entities/context menu) for creating identity wrappers.
- Currently identity creation is available via graph APIs and notebook auto-wrap behavior.

### 6. Clarify identity graph semantics
- Decide if identity nodes should always be visible graph nodes, or optionally hidden implementation references.
- Current implementation treats identity as normal nodes.

## Notes

- Identity wrappers improve key stability but do not by themselves enforce correct morph behavior. Stable references depend on updating identity `target-key` during morph/rekey events.

## See also

- [Graph Foundation](/dev/features/graph-foundation), [Graph Notebooks](/dev/features/graph-notebooks)
