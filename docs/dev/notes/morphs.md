---
type: dev-note
tags:
  - note
---

# Morphs Architecture

This document describes the morph system used to transform one graph node/entity type into another while keeping references stable through identity nodes.

## Goals

- Allow controlled type changes (for example `string-entity -> code-entity`).
- Keep stable references via `identity:*` keys.
- Keep morph logic store/domain-focused and decoupled from graph/view internals.
- Ensure open views (for example notebook/list item previews) refresh immediately after morph.

## Current Scope

- Implemented source type: `string-entity`
- Implemented target type: `code-entity`
- `identity:*` sources are intentionally non-morphable.

## Key Modules

- Morph registry: `assets/lua/morphs/init.fnl`
- String->Code morph: `assets/lua/morphs/string-entity-to-code-entity.fnl`
- Morph UI: `assets/lua/morph-view.fnl`
- Morph launchable: `assets/lua/launchables/morphs.fnl`
- Graph morph adapter: `assets/lua/graph/core.fnl`
- Lifecycle coordinator/owners: `assets/lua/reference-lifecycle/`
- [Operational contract and permanent matrix](../features/reference-lifecycle.md)

Related entity/node modules:

- Code entity store: `assets/lua/entities/code.fnl`
- Code node: `assets/lua/graph/nodes/code-entity.fnl`
- Code node view: `assets/lua/graph/view/views/code-entity.fnl`

## Morph Registry Contract

`Morphs.register(from-scheme, to-scheme, morph-fn, meta)` registers a morph function.

`Morphs.target-items(source-node)` returns available targets for a single source node.

`Morphs.apply(source-node, target, opts)`:

1. Validates source/target.
2. Rejects identity sources.
3. Runs the registered morph function.
4. Emits `morphs.morphed` event.

### `morphs.morphed` payload

The event includes:

- `source-node`
- `source-key`
- `from-scheme`
- `to-scheme`
- `result` (morph-specific structured result)

## String -> Code Morph Behavior

Implemented in `assets/lua/morphs/string-entity-to-code-entity.fnl`.

Given `string-entity:<id>`:

1. Resolves explicit or checked mounted canonical lifecycle ownership. Detached
   actions without explicit injection and conflicting providers fail before reads/writes.
2. Supplies a deferred read-only builder of the source string's code payload:
   - `name = ""`
   - `language = "fnl"`
   - `source = <string value>`
   - `kernel = 0`
3. Lifecycle freezes one replacement ID/payload/timestamps, stable-reference plan,
   owner Changes and runtime captures in a durable pending intent. All direct
   identities retarget; upstream chains and ordered membership retain meaning.
4. WorldOwner writes durable world/map metadata after-images; RuntimeOwner installs
   only frozen transient native captures, without persistence or inactive hydration.
   Participating map keys/topology/metadata/panels and board subjects follow the
   replacement; unrelated maps gain no hidden participation.
5. Retires the source physically **last**, after incoming cleanup and runtime
   reconciliation. Store retirement is INTERNAL, not the application command.
6. Returns the compatible result payload:
   - `source-key`
   - `target-key`
   - `target-type`
   - `updated-identity-keys`
   - `source-id`
   - `code-key`
   - `code-entity` (canonical store record)

Note: this morph function does not mutate graph state directly.

## Graph Adapter (Event-Driven)

The lifecycle captures participation before store signals can remove adapters.
Its frozen nonpersisting installation preserves native survivors and explicit
edge attributes. The existing graph morph event path remains for adapter notifications:

1. Remove old source node (if present).
2. Resolve replacement participation rather than populate unrelated maps.
3. Emit `graph.node-morphed` with `source-key`, `target-key`, and original payload.

The conversion-specific morph does not repair each consumer or write graph state.
Durable unopened/inactive cleanup is owned by lifecycle, not event listeners.

## Notebook/List View Refresh Behavior

Notebook/list nodes subscribe to both:

- identity store updates (`identity-updated` / `identity-deleted`)
- graph morph completion (`graph.node-morphed`)

Why both:

- Identity update can happen before graph node replacement is fully visible.
- `node-morphed` provides a post-reconciliation refresh point.
- This avoids stale type labels/previews in already-open notebook/list views.

Relevant files:

- `assets/lua/graph/nodes/notebook.fnl`
- `assets/lua/graph/nodes/list-entity.fnl`

## UI Behavior

Morph view (`assets/lua/morph-view.fnl`):

- Reads currently selected graph node (exactly one required).
- Shows morph target search list.
- Applies morph on selection.
- Displays status text for success/failure.

## Testing

Primary tests:

- `assets/lua/tests/test-morphs.fnl`
- `assets/lua/tests/test-notebooks.fnl`
- `assets/lua/tests/test-list-entities.fnl`
- `assets/lua/tests/test-reference-lifecycle-integration.fnl`
- `assets/lua/tests/test-reference-lifecycle-board.fnl`
- `assets/lua/tests/test-reference-lifecycle-projections.fnl`
- `assets/lua/tests/test-reference-lifecycle-recovery.fnl`

Coverage includes:

- target registration and listing
- string->code morph result
- identity target-key retargeting
- source deletion + target creation expectations
- notebook/list edge refresh on identity updates
- notebook/list refresh on `graph.node-morphed`

## Constraints and Decisions

- Identity nodes are non-morphable by design.
- The string→code payload uses `fnl`; the general CodeStore language field is not
  a declaration of additional supported morph conversions.
- Raw recoverable owning sites normalize through the reserved stable-reference
  plan. Explicit aliases remain distinct; morph is not limited to prewrapped sources.
- Code on boards renders with Text, not readonly Input. Item identity, transforms,
  state and connectors survive; there is no new code-editing surface.

## Deferred retry and failure contract

`Lifecycle:replace!(key, payload-or-builder)` preserves strict complete matching
for table payload retries. A builder is synchronous/read-only and runs once per
fresh preparation attempt inside admission checks, never on matching pending
morph-kind/source replay. Its function is never serialized. This lets the actual
frontend resume after source retirement without reading or recreating that source.
Other pending operations conflict; reentrancy is busy. Failures keep pending;
startup recovers before exposing worlds, refusing conflicting third-state bytes.

There is no multi-file atomicity or exactly-once notification guarantee. Committed
callbacks occur before pending clear and may repeat after failure. Canonical
single-writer ownership and frozen-byte checks, not caches or current callbacks,
govern replay. See the lifecycle page for explicit schemas and diagnostics.

## Next Work

1. Add additional morph targets.
2. Evaluate a shared result schema only when more conversions are approved.
3. Optionally add dedicated metrics/logging around morph lifecycle events.
4. Add e2e coverage for notebook/list visual update after morph.


## See also

- [Core Platform](/dev/features/core-platform)
