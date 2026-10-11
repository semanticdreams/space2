# Dict Entity Design

## Purpose

Space's entity system needs a keyed collection primitive that complements the
existing ordered `list` entity. The goal is a small, composable knowledge
management basis where higher-level objects are assembled from primitives rather
than new bespoke stores for every domain concept.

The accepted primitive set is:

- `string` — text-bearing scalar content.
- `code` — executable/source content.
- `list` — ordered collection of graph-addressable references.
- `dict` — keyed collection of graph-addressable references.
- `link` — relation between graph-addressable things.
- `identity` — durable indirection/stable reference.

## Core semantics

A dict entity is a persistent keyed collection whose values are graph-addressable
keys. It does not store inline scalars or tagged value payloads. Scalar-like
values are represented by referenced scalar entities, normally `string-entity`
or `code-entity`; nested ordered or keyed structures are represented by
referenced `list-entity` or `dict-entity` values.

Canonical shape:

```fennel
{:id "..."
 :name "Alice profile"
 :items
 {"name" "string-entity:..."
  "role" "string-entity:..."
  "manager" "identity:bob"
  "projects" "list-entity:..."}
 :created-at ...
 :updated-at ...}
```

The `:items` field mirrors list entities. For `list`, `:items` is an ordered
array of references. For `dict`, `:items` is a string-keyed table mapping item
names to references.

Dict values accept any graph-addressable key, not only canonical entity keys.
Graph-facing add/select flows should use the same durability posture as list
entities: wrap or resolve through identity where the graph layer already does so
for node references.

## Storage layer

Add `assets/lua/entities/dict.fnl` following the `entities/list.fnl` store
pattern.

Persistence:

- Directory: `{user-data-dir}/entities/dict/`
- Format: one JSON file per entity, named `<uuid>.json`
- Required fields: `id`, `name`, `items`, `created-at`, `updated-at`

Store API:

```fennel
:get-entity id
:create-entity opts
:update-entity id updates
:delete-entity id
:list-entities
:get-item id item-key
:set-item id item-key node-key
:remove-item id item-key
:rename-item id old-key new-key
```

Signals:

```fennel
dict-entity-created
dict-entity-updated
dict-entity-deleted
dict-entity-items-changed
```

Normalization rules:

- Item keys are stringified and empty keys are invalid for mutating item
  operations; callers receive an explicit error rather than a successful no-op.
- Item values are stringified graph keys and empty values are invalid for
  mutating item operations; callers receive an explicit error rather than a
  successful no-op.
- `:items` is always a table keyed by item key, not an array.
- Updating unchanged values is a no-op and should avoid unnecessary update/item
  signals where practical, matching the no-op behavior in list entity item
  operations.

## Graph nodes and loaders

Add graph adapters mirroring list entities:

- `assets/lua/graph/nodes/dict-entity.fnl`
- `assets/lua/graph/nodes/dict-entity-list.fnl`
- `assets/lua/graph/view/views/dict-entity.fnl`
- `assets/lua/graph/view/views/dict-entity-list.fnl`

Key scheme:

```text
dict-entity:<id>
dict-entity-list
```

The built-in graph entity extension should register loaders for both schemes.
The root `EntitiesNode` should expose a `dict` type next to `string`, `link`,
and `list`.

`DictEntityNode` responsibilities:

- Label by custom `name`; fall back to raw id like list entities.
- Maintain `compact-label` behavior analogous to list entity compact labels.
- Expose `get-entity`, `update-name`, `get-item`, `set-item`, `remove-item`,
  `rename-item`, and `delete-entity` methods.
- Emit `items-changed`, `changed`, and `entity-deleted` signals.
- Attempt to materialize edges from the dict node to referenced values when the
  referenced node can be resolved, following list entity's graph-addressable
  reference behavior. Unresolved references remain stored and do not block node
  creation.

`DictEntityListNode` responsibilities:

- List all dict entities sorted by `updated-at` descending.
- Show labels with item counts.
- Create new dict entities.
- Refresh on create/update/delete/items-changed signals.

## UI behavior

The initial dict entity view should stay intentionally simple and parallel to
the list entity view:

- Name input.
- Item count label.
- Scrollable item list with key, referenced graph key, focus/open action, rename
  or edit controls, and remove action.
- Add/update row for item key + selected/current graph node reference.
- Delete dict action.

The first version does not need a schema system, inline scalar editor, table
editor, source-backed claims, or provenance model. Those are higher-level
systems that can be built on top of dict/list/string/link/identity.

## Error handling

Dict entity code should follow existing Space entity constraints:

- Do not silently convert invalid required state into successful no-ops when the
  caller has supplied malformed required data.
- Surface persistence failures that would lose data.
- Keep graph adapters tolerant of references that are not currently visible or
  loadable; unresolved references remain stored as keys and may resolve later.

## Testing and validation

Unit coverage should mirror `test-list-entities.fnl`:

- store create/get/update/delete/list behavior;
- JSON persistence and reload;
- item set/get/remove/rename behavior;
- item normalization and unchanged-operation behavior;
- create/update/delete/items-changed signal emission;
- node construction, labels, compact labels, store-signal refresh, deletion;
- list node collection and create/open behavior;
- built-in key loader resolution for `dict-entity:<id>` and `dict-entity-list`;
- root entities browser includes dict.

Validation ladder for implementation:

1. Focused touched-file `tools.fennel-check` compile checks.
2. Relevant constraints for touched Fennel files, or `make constraints` if the
   touched-file path is not sufficient.
3. Focused Fennel tests for dict entities and affected entity browser/loaders.
4. Broader validation only if implementation touches shared graph loading,
   rendering, or runtime initialization beyond the dict-entity surface.

## Out of scope

- Inline scalar values inside dict entities.
- Typed value payloads such as `{:type "string" :value "..."}`.
- Schema/type systems for dict item names.
- Source-backed claim/provenance/confidence entities.
- General table/row UI; tables can be composed later from list/dict entities.
