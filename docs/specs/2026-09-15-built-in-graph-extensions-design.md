# Built-in Graph Extensions Design

## Context

Reloadable graph extension units now provide a runtime seam for adding graph-exposed node types without root reloads or whole-graph teardown. That seam is not yet the only way graph node types are installed: built-in graph node loaders are still aggregated by `assets/lua/graph/key-loaders.fnl` and installed directly by HomeWorld runtime creation.

This is unacceptable for the next milestone. The accepted design must have one graph node-type installation mechanism. Built-in node types and user/runtime node types must both use graph extension descriptors installed through `app.graph-extension-registry`. There must be no compatibility wrapper, fallback central registrar, or parallel HomeWorld registration path.

## Decision

Migrate all built-in graph node types to built-in graph extension descriptors. The graph extension registry becomes the only runtime mechanism that installs graph node type loaders into graph runtimes.

The low-level `graph:register-key-loader` API remains, but only as the primitive that extension descriptor installers call. App/runtime setup, tests, and docs must stop using `GraphKeyLoaders.register` or any equivalent centralized fallback. `assets/lua/graph/key-loaders.fnl` should be removed rather than kept as a forwarding module.

Use family-scoped descriptor modules rather than one monolithic built-in descriptor. Families should align with owning systems and runtime context requirements:

- entity/store-backed nodes;
- workflow/agent nodes;
- filesystem/source/module nodes;
- LLM nodes;
- Hacker News nodes;
- kernel nodes;
- world/activity/surface nodes;
- static/root/category nodes where they do not clearly belong to a richer owning system.

Each family descriptor owns its scheme list, loader installer, and refresh schemes. Descriptors adapt owning stores/systems into graph node adapters; they must not move domain persistence into graph code.

## Architecture

### Built-in descriptor module tree

Add a `graph/extensions/builtins/` module tree. Each family module exports descriptor tables. The aggregate `graph/extensions/builtins/init.fnl` exports:

- `descriptors(opts) -> sequential descriptor table`
- `register! registry opts -> sequential registration handles`
- scheme coverage/debug helpers for tests, if useful

`register!` must register descriptors through `GraphExtensionRegistry:register-extension` and roll back already registered descriptor handles if any later descriptor fails.

### Runtime startup

`main.fnl` creates `app.graph-extension-registry`, then registers built-in descriptor handles before user-code units and before worlds are activated. The built-in handles are stored on `app` and unregistered during app teardown before the registry is cleared.

`home-world.fnl` no longer imports or calls `graph/key-loaders`. It creates a graph and relies on the registry to install all existing extensions into both:

- the temporary pre-restore runtime used before `GraphMapManager` hydrates persisted map topology;
- the completed live runtime used for refresh/unload lifecycle.

This preserves saved graph topology for built-in and user extension keys through the same path.

### Removal of the old mechanism

Delete `assets/lua/graph/key-loaders.fnl`. Do not leave a module with the same name that forwards to descriptors. Tests and app code must install built-in node types through the registry only.

Existing individual node modules may keep focused `register-loader` helpers only if they are internal utilities used by descriptor installers and still return owner-safe handles. Tests should not use those helpers to recreate a second built-in installation mechanism except where a node module's helper itself is the unit under test. The accepted runtime/test setup path is descriptor registration through the registry.

### Graph core

Graph core should remain generic. Built-in schemes such as `start` are supplied by built-in descriptors. If graph core still auto-adds built-in nodes or imports built-in node modules for startup behavior, that behavior should be removed or constrained so node-type availability is descriptor-owned.

Graph core may keep low-level registration primitives and generic edge/node topology behavior.

## Data Flow

1. App init creates `app.graph-extension-registry`.
2. Built-in graph extension descriptors are registered with the registry.
3. User-code units register additional descriptors through the same registry.
4. HomeWorld creates a graph for a runtime.
5. Before persisted graph-map topology is hydrated, the registry installs all current descriptors into a temporary runtime containing that graph.
6. `GraphMapManager` restores key-only topology using built-in and user extension loaders from the same registry path.
7. The temporary runtime is uninstalled.
8. The completed runtime is installed into the registry for ongoing reload refresh and unload cleanup.
9. Unit reload refreshes visible adapters by scheme through the existing registry refresh path.

## Error Handling

- Duplicate schemes fail loudly through owner-safe loader registration.
- A built-in descriptor registration failure unregisters prior built-in descriptor handles before rethrowing.
- A runtime install failure rolls back handles installed during that attempt.
- Temporary pre-restore runtime installs are always uninstalled if map manager construction fails.
- No missing-store or missing-context fallback should silently skip a built-in family when the family is expected to be present. Optional subsystems may register only the schemes whose owning system is available, but the descriptor must make that conditionality explicit and tests must cover it.

## Testing Strategy

Tests must prove the absence of a second mechanism as well as behavior preservation:

- built-in descriptor coverage includes every existing built-in scheme exactly once;
- `graph/key-loaders.fnl` no longer exists and app/runtime code does not require it;
- HomeWorld hydration preserves persisted built-in and user extension keys through registry install before map restore;
- representative nodes from every built-in family still load with the same key schemes and labels/actions/views where currently tested;
- direct `GraphKeyLoaders.register` test setup is replaced by registry-backed built-in installation helpers;
- workflow conditional loader behavior remains explicit;
- final validation includes Fennel compile check, constraints, focused graph loader/world/workflow tests, `tests.fast`, and `make test`.

## Out of Scope

- Changing graph key schemes.
- Changing graph-map persistence format.
- Adding compatibility aliases or forwarding shims for `graph/key-loaders`.
- Adding sandbox/plugin security.
- Moving domain data ownership into graph descriptors.
- Adding new graph node types beyond descriptor migration.

## Acceptance Criteria

- All built-in graph node types are installed through `app.graph-extension-registry` descriptors.
- HomeWorld has no direct built-in key-loader registration path.
- `assets/lua/graph/key-loaders.fnl` is gone.
- Repository searches find no runtime/test setup using `GraphKeyLoaders.register` or requiring `:graph/key-loaders`.
- Existing saved graph topology hydrates with unchanged key schemes.
- User graph extension units and built-in graph node families use the same registry mechanism.
