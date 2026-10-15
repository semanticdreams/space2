# Entity type catalog and code browsing

## Intent and approved direction

Replace the Entities node's duplicated, hard-coded menu with one explicit
catalog of browsable entity types. Menu exposure is automatic from the catalog;
type declaration remains intentional. Add code browsing alongside string,
link, list, and dict. The user approved this direction after a read-only audit.

## Existing behavior

`assets/lua/graph/nodes/entities.fnl` repeats type knowledge in rows, actions,
and constructor dispatch. Code records and `code-entity:<id>` loaders already
exist, but there is no code-list browser. Start directly constructs Entities,
bypassing extension injection. App startup constructs its own code store, so a
browser using the default code store could miss app-store signals.

## Alternatives

1. Keep the hard-coded menu: simple, but independent lists already drifted.
2. Infer types from stored files or graph loaders: incomplete for empty stores
   and incorrect because graph schemes are not an entity-type inventory.
3. Explicit shared catalog, automatic menu: recommended and approved. Keep it
   immutable for an app lifetime rather than introducing a second hot-reload
   registry with ownership, rollback, and UI invalidation machinery.

## Architecture and contract

Add `entities/type-catalog.fnl`, a factory accepting `{:types descriptors}`.
Each descriptor has canonical nonempty string fields `id`, `label`,
`action-name`, `icon`, and `browser-key`. Validate dense ordered input and
unique IDs. Copy input and output descriptors so callers cannot mutate catalog
contents. `list-types` returns descriptors in declaration order; `get-type`
raises on unknown IDs. No registration/removal API, signal, store, or node
instance belongs in this catalog.

The built-in entity integration exports one explicit descriptor sequence:

| ID | Action | Icon | Browser key |
| --- | --- | --- | --- |
| string | String Entities | text_fields | string-entity-list |
| link | Link Entities | link | link-entity-list |
| list | List Entities | list | list-entity-list |
| dict | Dict Entities | data_object | dict-entity-list |
| code | Code Entities | code | code-entity-list |

Labels equal IDs. Preserve this declaration/action order; SearchView retains
its existing alphabetical search presentation. Validate icon availability.

App composition owns `app.entity-type-catalog`. Construct the default once or
accept an explicit `:entity-type-catalog` option; pass the same catalog to
built-in extensions. Publish only after successful registration. Repeated
initialization reuses it and rejects conflicting explicit replacement while
built-ins are installed. Runtime creation/uninstallation does not change it.
Tests use isolated catalogs. Teardown releases the app reference.

`EntitiesNode` requires `:entity-type-catalog`. Generate rows, actions, and
dispatch from descriptors, retaining `collect-types`, `emit-types`, and
`types-changed`. Selection resolves `browser-key` through the containing
GraphMap, adds an explicit display edge, and returns the browser adapter.
Do not import concrete browser constructors or use global app graph state.
Start advertises the Entities target as its canonical graph key and resolves
it only when selected. Preserve other Start target behavior.

Graph extension descriptors remain the sole loader installation mechanism.
Catalog entries describe browsing, not domain ownership or loader installation.
Custom startup composition can include a descriptor and separately install its
browser loader; Entities needs no changes. An advertised but unresolved browser
is an explicit error, not a hidden row or silent no-op. Unknown type, missing
catalog, invalid metadata, and missing map navigation context also fail loudly.

## Code browser

Add a store-injected `code-entity-list` node and SearchView-based view. Register
its exact-key loader beside `code-entity`, capturing the same resolved code
store. The browser lists records using `list-entities`; labels are bounded,
single-line names with an ID/language fallback, never source code payloads.
Opening a row loads `code-entity:<id>` through its containing map and adds an
explicit display edge. Reopening does not replace existing adapters or duplicate
topology. Provide Refresh; creation and execution remain existing surfaces.

The node owns subscriptions to create/update/delete signals, emits refreshed
items, and disconnects on drop. Views own SearchView children and their own
signal connections, not the node/store. Multiple views and multiple maps work
independently. New Fennel self objects use final literals with methods included;
affected legacy code is simplified only as needed for this change.

## Scope and compatibility

Preserve existing graph keys, action labels, entity storage formats, and persisted
topology. `code-entity-list` is additive. No graph-core persistence changes,
C++ changes, filesystem discovery, generic CRUD framework, identity browser,
notebook-menu migration, live catalog membership changes, or unrelated browser
refactoring. The catalog inventories browsable types, not every domain store.
Document descriptor composition and its separation from live loader registration.

## Acceptance and validation

- Catalog validation, deterministic order, duplicates, unknown lookup, and
  mutation isolation have focused tests.
- Rows and actions agree; a custom descriptor works without editing Entities.
- Start reaches catalog-injected Entities; each advertised built-in browser
  resolves through the correct map and injected stores.
- Code listing, row click/submission, mutation refresh, callback cleanup, and
  multiple map/view behavior are tested using isolated stores.
- Missing browser/context errors are observable and contain useful keys.
- Relevant entity and extension fixture tests are migrated to explicit injection.

Runtime is currently absent. Build first when needed (`make build`, four-hour
timeout), then native touched-file/repo compile check, constraints, focused
Fennel suites, and final `make test` because initialization and shared runtime
fixtures change. Use absolute asset/macro paths, disable audio, skip keyring,
and put test data outside the repo. Constraints are blocking. Preserve evidence
of each gate and diagnose failures rather than bypassing them.

Final integration requires reviewed commits, a clean tree, evaluation against
fresh `origin/main`, green required validation, and the repository's PR/merge
queue workflow. No rebase or force push.
