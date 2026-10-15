# Reloadable Units And Hot Reload

This note documents the current reloadable unit system in `space`.

It is intentionally grounded in the implementation that exists today.
It is not a copy of the earlier scratch spec in `~/Desktop/space-units.md`.

That earlier note was useful for shaping the work, but several parts of the final design were simplified or changed during implementation.

## Goal

The immediate goal was not to turn the whole codebase into fine-grained hot-swappable subsystems on day one.

The actual goal was:

- make the whole app reloadable first
- preserve enough runtime state to make that usable during development
- prove the model with a small number of real child units
- build the file-watching and routing machinery now so finer units can be added later

This work is mainly for internal development velocity.
Units are trusted in-process code boundaries, not sandboxed plugins.

## Current Model

There are three practical layers:

1. `module`
   The source file or `require` target.

2. `unit`
   The live reload boundary.
   A unit can be loaded, unloaded, snapshotted, restored, and reloaded.

3. `hot reload controller`
   Optionally watches files, maps changed paths to a target unit or explicitly selects the root, clears loaded modules for that unit, and performs the reload cycle.

In the current system, changed files route to units by explicit path ownership, not by a module dependency graph.

## Why "Unit"

We already use `app` as the global runtime root, so "app" was the wrong name for a reloadable thing.

`unit` fits the actual role better:

- it is a loadable code/runtime boundary
- it is also the target of hot reload
- it does not imply plugin safety or compatibility guarantees

That unification matters.
The same abstraction now serves:

- full app reload
- child subsystem reload
- future finer-grained reload boundaries

## Core Decisions

### Global `app` stays global

We did not build a strict service container or plugin API.
Apps or units are trusted code and can mutate the shared global `app` directly.

This was a deliberate choice.
At this stage we care more about power and iteration speed than API stability or sandboxing.

The tradeoff is explicit:

- load order matters
- contracts are social
- refactors can break units
- unload correctness depends on discipline

### Lifecycle is `load`, `unload`, `snapshot`, `restore`

The earlier note discussed `load`, `start`, `stop`, `snapshot`, and `restore`.
We did not keep the separate `start` and `stop` phase.

The implemented lifecycle is:

- `load`
- `unload`
- `snapshot`
- `restore`

Reason:

- there is no useful dormant "loaded but not active" phase yet
- the simpler protocol was enough to get root reload and child reload working
- splitting the lifecycle earlier would have increased surface area before there was a real need

### Hard fail on child reload failure

We explicitly did not implement "reload child, then escalate to parent/root on failure".

Current behavior is:

- attempt reload of the chosen target unit
- if reload fails, attempt rollback to the previous runtime for that same unit
- if rollback also fails, `reload-now!` throws; `reload-root!` returns explicit failure evidence

We chose hard failure over silent escalation because:

- we do not yet have a robust mechanism to track, present, and reason about escalation paths
- silent fallback would hide real lifecycle bugs
- during development it is better to fail loudly than to mutate larger runtime scopes unexpectedly

### Explicit path ownership, not dependency tracking

Units currently declare `owned-paths`.
The hot reload router picks the most specific matching unit for a changed file path.

This is simpler than tracking:

- module import graphs
- dynamic runtime ownership
- dependency invalidation

It is also easier to reason about while the unit boundaries are still evolving.

The tradeoff is that ownership is manual.
If a unit owns behavior spread across files that are not listed under its owned roots, routing will miss that relationship.

### Root reload must not run inline from the same engine callback

One implementation lesson mattered enough to count as an architectural rule.

File-triggered root reload must not rebuild the app inline from the same engine callback stack that detected the change.

The current root flow defers actual reload execution through `callbacks` so the reload runs after the current update path unwinds.

Reason:

- rebuilding the root app inline during the live frame/update path was fragile
- the deferred boundary avoids re-entering teardown/build work from inside the signal stack that requested it

This is a concrete design decision, not just a test harness detail.

### Live test path uses X11 under `xvfb`

The real-app hot reload test runs the actual executable under `xvfb`.
It explicitly forces `SDL_VIDEODRIVER=x11`.

This was not cosmetic.
During debugging, the failing path turned out to be a Wayland/EGL swap hang in the test environment rather than a unit reload bug.

That setting is now part of the documented testing setup for live hot reload.

## Unit API

The base implementation lives in `assets/lua/units.fnl`.

`Unit` is a small wrapper around four functions:

```fennel
(Unit
  {:id "hud"
   :parent-id "app-root"
   :owned-paths ["/abs/path/to/assets/lua/hud.fnl"]
   :load load-fn
   :unload unload-fn
   :snapshot snapshot-fn
   :restore restore-fn})
```

Important details:

- `:id` is required
- `:load` and `:unload` are required
- `:snapshot` defaults to a no-op returning `nil`
- `:restore` defaults to a no-op returning `true`
- `:reload` is a convenience method that runs `snapshot -> unload -> load -> restore`

`UnitManager.reload-unit` wraps the unit reload and returns structured evidence:

```fennel
{:unit-id id
 :reloaded true
 :activity evidence-or-nil}
```

When an activity was active before reload, the manager attempts to reactivate
that same activity after the unit reload completes. The `:activity` evidence
records the active activity before and after reload, whether reactivation was
attempted, whether the activity is registered after reload, whether an active
session exists after reload, and any activation error. Unit reload failures still
throw; they are not converted into successful evidence responses.

`ModuleUnit` is a convenience wrapper for units backed by a Lua/Fennel module export table.

The root app reload uses `ModuleUnit` to call:

- `init`
- `drop`
- `snapshot`
- `restore`

from `assets/lua/main.fnl`.

## Hot Reload Controller

The implementation lives in `assets/lua/hot-reload.fnl`.

### File watching

Native file watching is provided by `efsw`, vendored under `external/efsw`, and exposed to Fennel through `src/lua_file_watch.cpp` as the `file-watch` module.

That gives Fennel:

- `FileWatcher`
- `add-watch`
- `start`
- `poll`
- `drop`

### Routing changed files to units

The controller watches one or more roots and polls filesystem events.
For each changed file:

1. normalize the path
2. ignore non-`.fnl` / non-`.lua` files
3. ignore startup watcher noise
4. find the unit whose `owned-paths` match the file with the longest path prefix

If multiple changed files map to multiple units in one batch, the controller resolves their common ancestor.
If nothing matches, it falls back to the root unit.

This is the current routing rule:

- most specific matching unit wins
- mixed changes reload the common ancestor
- no match reloads root

### Watcherless manual mode and explicit root reload

`HotReloadController` and `AppRootController` accept `:watch?`, a boolean that
defaults to `true`. With `:watch? false`, construction does not acquire a native
watcher or capture startup file stamps, and `update` does not poll files. Editing
files alone does not request or execute a reload. `:watch-paths` remains required:
these roots still provide module ownership when a unit has no explicit
`:owned-paths`; disabling watching does not disable module invalidation.

```fennel
(local controller
  (HotReload.AppRootController {:watch-paths ["/checkout/assets/lua"]
                                :watch? false}))
(local result (controller:reload-root!))
(assert result.ok result.error)
```

An existing watched controller can be permanently converted with
`controller:use-manual!() -> true`. Conversion drops its watcher once and clears
pending filesystem events, debounce deadline, and reload scheduling state.
Repeated conversion is safe; conversion after `drop` is an error. Root
initialization reuses the surviving controller rather than reenabling watching.
Any callback already queued by an external scheduler is still owned by that
scheduler; conversion does not cancel external callback queues.

`controller:reload-root!()` executes the existing transaction synchronously,
selecting the configured root rather than routing by changed file paths. It
returns:

```fennel
{:ok true
 :target-unit-id "app-root"
 :phase "complete"
 :rollback "not-needed"}
```

On failure, `:ok` is `false`, `:error` contains the error text, and `:phase`
identifies the failed forward phase: `"target-selection"`, `"collect-modules"`,
`"snapshot"`, `"unload"`, `"clear-modules"`, `"load"`, `"restore"`, or
`"refresh-extensions"`. If selection fails before a target is known,
`:target-unit-id` identifies the configured root fallback.

`:rollback` is `"not-needed"` for success or a pre-unload failure, `"restored"`
when rollback rebuilt the prior runtime, and `"failed"` when rollback itself
failed. The last case also includes `:rollback-error`. Snapshot/selection errors
do not unload or attempt rollback. The prior `app.__hot-reload-ctx` is restored
after success, pre-unload failure, and either rollback outcome; rollback retains
the transaction context while it runs so root infrastructure stays preserved.
Use after `drop` remains a lifecycle error, not a reload result.

`reload-now!` keeps path routing and its boolean/throw interface: `true` on
success, `false` on failure unless rollback failed, in which case it throws with
both errors. Both entry points share one transaction and module/cache handling.
`debug-state` reports `:watch?` and an empty `:watch-directories` list when there
is no watcher; `drop` remains idempotent in either mode.

`AppRootController` also forwards `:startup-ignore-ms` and
`:on-reload-requested`, in addition to `:watch?`, to the underlying controller.

### Reload algorithm

The reload algorithm is:

1. resolve target unit
2. collect currently loaded modules whose source paths live under that unit's owned roots
3. snapshot the target unit
4. unload the target unit
5. clear the collected `package.loaded` entries
6. load the target unit again
7. restore the snapshot

If reload fails:

1. restore the previous `package.loaded` entries
2. call `load`
3. call `restore` with the pre-reload snapshot

This gives us rollback, but it is not a staged "instantiate new runtime then commit" swap.
Reload still mutates the live process in place.

### Deferred execution

The controller can either reload immediately or request a reload callback.

The root app uses the callback path:

- file events are debounced
- `HotReloadController.update` requests reload
- `main` enqueues a callback
- the callback runs `reload-now!` later

This keeps root reload out of the current engine callback stack.

Explicit `reload-root!` does not enqueue itself. Live callers must defer it until
the requesting update/signal/remote-control stack has unwound, using the same
callback boundary. Disabling watching does not make inline root teardown safe.

## Current Unit Boundaries

### Root unit

The root unit is the whole app, implemented as a `ModuleUnit` targeting `main`.

Its exports are:

- `init`
- `drop`
- `snapshot`
- `restore`

The root unit is still the default fallback when routing cannot target a smaller unit.

### HUD unit

`assets/lua/hud-unit.fnl` is the first real child unit.

It owns the HUD runtime lifecycle:

- create and drop the HUD shell
- recreate the HUD focus scope
- snapshot persistent panel state
- restore panel state after reload
- rebind shared runtime context such as scene/layout/object-selector references

This proved that a subsystem smaller than the full app could reload while preserving meaningful user-visible state.

### Canvas unit

`assets/lua/canvas-unit.fnl` is the second real child unit.

It sits on top of the active world runtime rather than re-owning all world state directly.
The world runtime now exposes explicit canvas hooks from `assets/lua/home-world.fnl`:

- `load-canvas-runtime`
- `unload-canvas-runtime`
- `capture-canvas-unit-state`
- `restore-canvas-unit-state`

This is an important design shape.
The canvas unit is a reload boundary over shared world state, not a separate world replacement.

That separation lets the world continue to own longer-lived state such as:

- scene
- graph core
- drawing controller
- cameras
- object selector wiring

while the canvas surface/runtime can still be independently reloaded.

## Root State Preservation

Root reload currently preserves a small shell-level snapshot in `main`.

That snapshot includes:

- active world id
- active canvas feature
- preferred interaction surface
- active interaction surface
- canvas visibility

One implementation detail that mattered in practice:

- active world restoration now snapshots `app.active-world-entry.id` first
- it only falls back to `app.world-manager:active-world-id()` if needed

That fix was required because the live reload path could have a valid bound active world even when the world-manager accessor was not the strongest source of truth at snapshot time.

During app-root reload, `main` also preserves tray and notify setup instead of dropping and recreating them unconditionally.

## Testing Strategy

The current system is covered at two levels.

### Focused unit tests

`assets/lua/tests/test-units.fnl` covers watcher/controller and module-unit behavior:

- file watcher write/delete events
- module reload applying edited code and clearing deleted dependencies
- watcherless construction, passive edits, and explicit-root versus child-path selection
- manual conversion, pending-event discard, and idempotent teardown
- structured failure phases, context restoration, rollback, and legacy result handling
- AppRootController option forwarding

`assets/lua/tests/test-hot-reload-integration.fnl` covers real app/runtime behavior:

- full root app reload roundtrip
- HUD unit reload preserving panel state
- HUD file change routing to the HUD unit
- canvas unit reload
- canvas file change routing to the canvas unit

The root roundtrip converts the controller to manual mode and traps watcher
acquisition during root reinitialization. Integration tests use real app/runtime
code; focused controller tests also use small `Units.Unit` fixtures and a
deterministic watcher fixture for lifecycle/error-path coverage.

### Real-app live reload test

`assets/lua/tests/test-live-hot-reload.fnl` starts the actual `space` executable, enables hot reload, edits a watched copy of `main.fnl`, and verifies that live reload actually happens while preserving active world state.

Important properties of this test:

- it runs the real app, not a narrowed harness
- it uses the remote-control endpoint to inspect state in-process
- it preserves the temp directory on failure for debugging
- it forces `SDL_VIDEODRIVER=x11` under `xvfb-run`

This test matters because it catches issues that unit tests alone do not, especially lifecycle bugs that only appear in the actual running executable.

## What Is Still Missing

The current system is intentionally simpler than the original scratch design.

These pieces do not exist yet:

- no separate `start` / `stop` lifecycle phase
- no module dependency graph
- no explicit stale/invalidation state machine
- no automatic parent escalation on child reload failure
- no staged "build new instance, validate, then commit swap" reload transaction
- no versioned state migration layer beyond raw `snapshot` / `restore`
- no generalized unit registry or discovery system beyond the units we wire up directly

There is also still a social rather than enforced contract around teardown.
Units are responsible for undoing what they install into global `app`.
The framework does not track ownership for them.

## Current Imperfections

The current design is coherent and usable, but it is not perfect.

These are the main imperfections we are knowingly carrying:

### Units and activities are trusted imperative code

The unit system and the activity system both assume trusted in-process code.

That means:

- units can mutate global `app` directly
- activities can mutate shared runtime directly
- rollback can only reliably undo what goes through explicit unit unload paths or activity-context cleanup helpers

This is a deliberate tradeoff for development speed, but it means lifecycle safety is not guaranteed by construction.

### Built-in activity units are still bootstrapped explicitly

Graph, drawing, and board activities behave like ordinary registered activities at runtime, but their unit loading is still wired by a built-in list in `main`.

That means:

- built-in activity units are not discovered dynamically
- external or user-loaded activity units are not yet part of startup or reload configuration by default
- the host still knows which built-in activity units should exist at boot time

This is cleaner than hardcoding activity behavior in the host, but it is still not the final external-unit model.

### The system is consistent, but not yet fully generalized

The current model is now internally consistent:

- units own code lifetime
- activities own active workspace behavior
- persistence preserves explicit activity ids without inventing built-in defaults

But some surrounding code is still shaped around the built-in development workflow:

- tests commonly seed graph and drawing activities directly
- built-in activity units are still the only ones exercised by startup
- external unit discovery, loading, and configuration are still future work

So the architecture is clean for the built-ins we have, but it is not yet the full user-extensible story.

## Why Those Things Are Missing

Most of the missing pieces were omitted on purpose, not forgotten.

The early priority was:

- get real reload working
- prove it on the root app
- prove it on at least one or two meaningful child boundaries
- avoid overdesign before we knew where the hard lifecycle problems were

That was the right tradeoff.
If we had implemented dependency graphs, escalation logic, and staged transactions first, we would have been designing around hypothetical failures instead of real ones.

## Recommended Next Steps


### Units as Loader-Backed Runtime Objects

The unit system is intentionally loader-neutral at the abstraction layer. A unit
is a runtime object with an id, lifecycle exports (init/drop/snapshot/restore),
and a backing loader that owns the source of truth.

Today's user units are filesystem-backed: their source lives as `.fnl` files
under `app.code-dir`, their loader is `"filesystem"`, and their owned-paths
point to real files on disk. But that is an implementation detail. Future units
may be backed by database records, remote hosts, generated stores, or other
loaders.

Callers should use unit handles and source-ids instead of constructing raw
filesystem paths. The `ExternalUnitService` in
`assets/lua/llm/external-unit-mcp/service.fnl` classifies each unit's loader and
exposes loader-neutral operations (resolve, inspect, read-source, apply-patch,
create-source, reload). Operations fail loudly when the loader lacks a requested
capability rather than silently falling back to filesystem assumptions.

### External Editing Through MCP Tools

When external OpenCode sessions need to edit user units, they should use the
`space_unit_*` external MCP tools rather than direct filesystem edits:

- `space_unit_read_source` / `space_unit_apply_patch` / `space_unit_create_source`
  for source editing with stale-content protection, path containment, Fennel
  validation, and automatic reload.

- `space_unit_reload` for explicit reload operations.

- `space_unit_run_tests` for test execution in a subprocess.

- `space_unit_read_log` for inspecting the application log after edits.

Direct filesystem edits skip all of these protections: stale-content detection,
path containment enforcement, source validation, symlink rejection, and reload
integration. They are an escape hatch that requires explicit human approval and
a Space-reported local filesystem source handle.

The external unit MCP subsystem lives under `assets/lua/llm/external-unit-mcp/`
with a standalone entrypoint at `assets/lua/tools/external-unit-mcp-server.fnl`.
It boots a headless engine, creates an isolated OpenCode config, and exposes
loader-neutral unit tools on loopback. See [External Unit MCP](./notes/external-unit-mcp)
for the full workflow.


The next useful work is probably one of these:

### 1. Extract another meaningful child unit

Candidates:

- world-manager-adjacent shell state
- graph-view-facing UI/runtime state
- another subsystem with a clear snapshot/restore contract

This deepens confidence that the unit model scales beyond HUD and canvas.

### 2. Tighten reload failure visibility

We intentionally hard-fail today, but tooling around that can improve:

- clearer logs
- better surfaced target unit / owned paths / cleared modules
- tighter diagnostics in live reload failures

### 3. Decide whether path ownership is enough

`owned-paths` is simple and currently good enough.
Later we may want a richer mapping if units spread across less tidy source layouts.

That does not mean "build a full dependency graph now".
It means reevaluating only once the manual path model starts hurting.

### 4. Introduce state migration only when real versioning pressure exists

Right now units snapshot and restore within the same running development session.
That does not yet justify a heavier migration framework.

If units begin persisting richer long-lived state across larger architectural changes, migration can be added then.

## Summary

The current reloadable unit system is deliberately pragmatic.

It gives us:

- real native file watching
- whole-app hot reload
- unit-targeted child reloads
- state-preserving reload for real subsystems
- actual live executable coverage

It does not yet attempt to solve every future extension problem.
That is intentional.

The important thing is that the abstraction is now real:

- a unit is the thing we load
- a unit is the thing we unload
- a unit is the thing we snapshot and restore
- a unit is the thing hot reload targets

That is enough foundation to keep extracting more boundaries as the codebase needs them.
