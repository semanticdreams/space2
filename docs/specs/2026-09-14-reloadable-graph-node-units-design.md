# Reloadable Graph Node Units Design

## Context

Space already has reloadable units with explicit `owned-paths`, a `load` / `unload` / `snapshot` / `restore` lifecycle, and root-level fallback reload. The graph architecture is intentionally split: graph core and graph maps preserve graph-visible topology, graph node adapters expose domain objects, and graph views own presentation/runtime UI. The next goal is to let runtime units add new graph node types and associated previews, full views, and morphs without reloading the root app or rebuilding the whole graph.

The implementation must prove the full loop in one vertical path rather than in separate horizontal slices. If loader registration, morph registration, adapter refresh, and unit lifecycle are designed independently, we will not know whether the abstractions are suitable for real runtime node-type loading.

## Decision

Use **reloadable graph extension units** as the primary seam. A graph extension unit owns one node type or a tightly related node-type family. It may define node adapters, key loaders, previews, full node views, graph actions, morph registrations, and any unit-owned signal subscriptions required by that node type.

Root reload remains a fallback boundary only. The existing graph activity unit remains responsible for graph activity UI/runtime behavior such as `GraphView`, the graph sidebar, camera/view state, and activity activation. It should not become the owner of all graph node types.

The first implementation must be an end-to-end runtime extension prototype that demonstrates a new graph key scheme, node adapter, preview, full view, optional morph, reload, unload, and visible-node adapter refresh in one coherent flow.

## Architecture

### Graph extension registry

Add a small runtime registry, exposed from app/world runtime plumbing, that lets units register graph extension descriptors. A descriptor includes:

- extension id and owning unit id;
- one or more graph key schemes;
- loader installer functions for graph instances;
- optional morph installers;
- optional refresh metadata for visible graph maps.

The registry installs an extension into all live world graph runtimes and into future world graph runtimes when they are created. It stores registration handles per runtime so unload can cleanly remove everything the unit installed.

### Owner-safe graph loader lifecycle

Graph core needs registration handles for key loaders. Existing call sites that use `graph:register-key-loader(scheme, loader-fn)` can keep working, but the method should return a registration handle and support owner metadata. A matching unregister operation must remove only the current matching registration. Duplicate schemes should continue to fail loudly unless the previous owner has unregistered.

This is required because a reloadable unit cannot safely replace a key loader while stale closures remain installed.

### Owner-safe morph lifecycle

The morph registry needs the same owner-safe registration shape. A unit that registers `from-scheme -> to-scheme` morphs must receive handles and unregister them during unload. Duplicate active morph registrations should fail loudly unless the previous registration is removed by its owner.

### Visible adapter refresh

Graph topology should remain stable across extension reload. Visible nodes with the extension's key schemes should keep their keys and edges, but their adapter records should be rebuilt through the new loader after reload. GraphMap already has node replacement behavior and replacement signals; the extension reload path should use that seam instead of dropping the whole graph or graph activity.

The refresh API should operate by scheme over active/live graph maps. If a visible key cannot be recreated after an explicit refresh, the failure should be surfaced rather than silently leaving a stale adapter.

### Prototype extension unit

Build a small but real reloadable graph extension unit. It should be loaded as a runtime/user unit rather than as a hardcoded built-in graph node. The prototype should define a scheme such as `demo-node:<id>` and include:

- node adapter construction;
- a preview builder;
- a full node view builder;
- a morph or equivalent association that exercises morph registration if practical;
- load/unload behavior that registers and unregisters extension handles;
- restore/reload behavior that refreshes visible adapters for owned schemes.

The unit may live in test fixtures or a controlled user-code test directory as long as it exercises the same loading/reloading seam external units use.

## Data Flow

1. Runtime starts and creates world graph runtimes.
2. User/runtime graph extension unit loads.
3. The unit registers an extension descriptor with the app-level graph extension registry.
4. The registry installs loader/morph registrations into all live graph runtimes and records handles.
5. A graph map loads a key owned by the extension scheme, creating a graph node adapter through the loader.
6. GraphView opens the node preview/full view from the adapter's `:preview` and `:view` functions.
7. The unit reloads after source changes.
8. Unload unregisters old handles; load registers new handles; restore/registry refresh rebuilds visible adapters for owned schemes.
9. Graph topology, graph map edges, selection, and open view state remain keyed by node keys while behavior comes from the newly loaded adapter/view code.

## Error Handling

- Duplicate active key-loader or morph registrations fail loudly.
- Unregistering a handle that is already inactive is safe/idempotent for the same handle, but trying to remove another owner's active registration fails loudly.
- Extension installation into a live runtime must either complete with recorded handles or roll back registrations installed during the failed attempt.
- Explicit adapter refresh must report visible nodes that cannot be rebuilt for their registered schemes.
- Unit unload must disconnect signal subscriptions and remove registry handles; stale closures should not remain installed after reload.

## Testing Strategy

Use test-driven development with a vertical lifecycle test as the anchor. Tests should cover both the full flow and the seams that make the abstraction safe:

- registration handle behavior for graph key loaders;
- duplicate/stale-owner failure behavior;
- morph registration/unregistration behavior;
- extension registry installation into live and future graph runtimes;
- visible GraphMap adapter refresh by scheme preserving keys, edges, selection/focus where applicable;
- prototype extension load, node creation, view/preview behavior, reload behavior change, and unload cleanup;
- hot reload/path ownership routing where feasible for the prototype unit.

Validation for Fennel work must follow the Space ladder: touched-file compile check, constraints, focused Fennel tests, then broader relevant tests. Because this touches graph core, graph maps, morphs, units, and runtime loading, final validation should include the broader relevant Fennel suite and project test gate before integration.

## Out of Scope

- Sandboxed plugin security.
- A dependency graph for hot reload routing.
- Automatic marketplace/discovery UX for graph extension units beyond what is needed for the vertical prototype.
- Root-reload escalation when extension reload fails.
- Persisting graph node domain data in graph topology state.

## Acceptance Criteria

- A runtime graph extension unit can add a new graph node key scheme with adapter, preview, full view, and associated morph behavior at runtime.
- Editing/reloading that unit updates visible node adapter/view behavior without root reload or whole-graph teardown.
- Existing graph topology for visible nodes survives reload by key.
- Unit unload removes loaders, morphs, and signal subscriptions cleanly.
- Tests prove both the end-to-end lifecycle and the lifecycle seams.
