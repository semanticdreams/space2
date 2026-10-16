---
type: dev-note
tags:
  - note
---

# Graph Identity Nodes

See also:
- [morphs](./morphs)
- [Reference lifecycle](../features/reference-lifecycle.md)

## Purpose

Identity nodes provide stable references for graph content whose concrete key/type may change over time.

Example:
- A notebook item currently points to `string-entity:abc`.
- Later, that entity is morphed into another type with a new key.
- If the notebook item points to `identity:xyz` instead, only the identity target changes and the notebook reference stays stable.

## Current Implementation

### Graph-independent identity entity store
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
  - `retire-entity!` (INTERNAL physical primitive, not application deletion)
  - `list-entities`
  - `find-by-target-key` (used for dedupe)
  - `ensure-key` (raw key → stable key; supplied explicit identity unchanged)
  - `resolve-key` (terminal key plus traversed chain; cycle/depth guards)

Use the canonical IdentityStore shared by list/dict/link/notebook stores. Equal
paths do not substitute for exact store identity in composed lifecycle actions.
The public identity node's `delete-entity` delegates to logical deletion, removing
upstream live references without deleting the independent represented target.

### Identity graph node + view
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
- APIs:
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

## Owning-store stable-reference policy

On list/notebook items, dictionary values and populated link endpoint writes:
1. If key already starts with `identity:`, store it unchanged.
2. Otherwise, wrap to an identity key.
3. Reuse the lexicographically lowest existing direct identity for that raw target
   if present; otherwise create one without adding a visible wrapper node.

List/notebook uniqueness runs after normalization and keeps first occurrence and
order. Different supplied aliases remain distinct even with equal terminal
meaning; dictionaries retain distinct slot names. Identity targets themselves
are not recursively wrapped. Store create/update/add/set/reorder paths share this
rule, not just graph buttons. Explicit identity removal is exact; raw membership
removal is nonallocating. Default link drafts retain empty endpoints.

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

## Migration, morph and deletion

Main starts the five-owner lifecycle before exposing worlds. Startup replays any
pending intent, then runs versioned raw-reference migration if needed. Recoverable
raw sites become stable; IDs/order/named slots and explicit aliases/chains survive.
Historical dangling known references are reported in migration.json, not guessed
or silently removed. This is not a separate migration CLI or a lazy graph-loader
cleanup. See the lifecycle page for exact files and single-writer recovery rules.

String→code morph reserves one replacement, retargets every direct identity and
leaves upstream chains intact. Deletion follows the incoming dependency closure
across unopened owners as well as loaded ones. Identity cycles/depth exhaustion
fail explicitly; relationship cycles are valid and terminate via a visited closure.
Presentation listeners refresh projections only and never persist container edits.

Permanent `test-reference-lifecycle-identity`, `-writes`, `-commands`, `-projections`
and `-integration` modules cover these boundaries in addition to the tests above.
Additional morph targets and dedicated visual snapshots remain outside this work.

## Notes

- Identity wrappers improve key stability but do not by themselves enforce correct morph behavior. Stable references depend on updating identity `target-key` during morph/rekey events.

## See also

- [Graph Foundation](/dev/features/graph-foundation), [Graph Notebooks](/dev/features/graph-notebooks)
