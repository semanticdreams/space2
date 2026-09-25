# Hostable Space Apps Design

## Context

Space recently gained an independent Snake example under `examples/snake/`. The
example demonstrates that a Fennel app can be packaged and launched as its own
desktop program while reusing the Space runtime. The current Snake entrypoint is
already safe to import in a limited sense: `examples/snake/assets/lua/main.fnl`
exports `:main` and only starts the game when `app-config.run-main` is true.

The remaining boundary is deeper. `snake/app.fnl` currently owns standalone
runtime responsibilities: it creates `Engine`, initializes `app.renderers`,
builds an `OrthographicUiSurface`, installs `app.active-world-runtime`, connects
engine events, runs the engine loop, drops renderers, and shuts the engine down.
That is correct for an independently published game, but it cannot be imported
directly into the default Space app without colliding with Space's already active
engine, renderer, input routing, presentation graph, and debugging tools.

The product goal is broader than embedding a toy example. Space should be usable
as an IDE for Space-runtime games: a developer can play a game inside Space,
pause on an arbitrary frame, inspect plain game state, attach moldable views and
live controls, then publish the same game independently with the standalone
harness. Arbitrary native Linux application embedding is not the primary goal;
it is only relevant as a comparison point or future fallback strategy.

## Goals

- Determine whether Space-runtime apps can share one entry module that is both
  independently runnable and importable/hostable by Space.
- Define a minimal host interface that avoids app-owned engine and renderer
  ownership in embedded mode.
- Preserve independent publishing for apps such as Snake.
- Enable the Space IDE use case: play, pause, step, inspect state, route input,
  render inside Space, and attach developer views.
- Keep the MVP focused on trusted in-process Space/Fennel apps, while documenting
  alternatives and known risks.

## Non-goals

- Do not host arbitrary native executables as part of the MVP.
- Do not revive wlroots/Xwayland compositor embedding for this feature.
- Do not sandbox untrusted apps in-process.
- Do not design a full app marketplace, launcher, or persistent discovery UI.
- Do not promise long-term public API stability before the Snake MVP proves the
  contract.
- Do not require independent apps to depend on Space's default HUD, graph,
  wallet, LLM, or default `main` app modules.

## Existing architecture fit

Several current pieces make an in-process host interface feasible:

- App distribution already supports an app-owned `assets/lua/main.fnl` entrypoint
  launched with `space -m main` and app asset roots before the repository/runtime
  asset root.
- The Snake game model is already separated from runtime boot code in
  `snake/game.fnl`.
- Snake's view already renders through `OrthographicUiSurface`, which produces a
  presentation target similar to HUD/canvas targets.
- Space rendering already consumes presentation targets from
  `app.active-world-runtime.presentation:render-targets()`.
- Space UI has plausible host surfaces: HUD panels/dialogs, canvas activity
  slots, activity presentation, and lower-level renderer sub-app hooks.

The main missing piece is a lifecycle split: standalone mode may own the engine;
embedded mode must return a host-owned session object.

## Considered approaches

### Approach A: trusted in-process lifecycle interface

Apps export a `create(host)` function. Standalone `main` still creates and owns
`Engine`, renderers, event connections, and shutdown. Embedded `create(host)`
returns a session object that never starts an engine and never replaces
Space-owned globals. Space owns timing, pause, input routing, viewport changes,
render collection, inspection surfaces, and teardown.

Benefits:

- Best fit for Space-runtime games and internal live-development tools.
- No texture streaming, compositor, IPC, or multi-process input protocol needed.
- Pause/step/state inspection can operate on real Fennel objects in the same
  runtime, while snapshots expose plain data to tools.
- Snake can prove the pattern with small, focused changes because its game logic
  and orthographic UI surface are already separable.

Costs and risks:

- Hosted apps are trusted code and can still mutate global `app` unless the
  contract and tests make that boundary explicit.
- Module namespace and asset-root collisions remain possible when multiple apps
  are loaded into one runtime.
- Teardown must be disciplined: no leaking widgets, surfaces, event handlers, or
  references into Space's renderer.
- The host API needs versioning later if external game repositories depend on it.

### Approach B: separate Space process with a runtime bridge

The game remains a separately running Space process. It exposes a live protocol
for state snapshots, pause/step controls, input injection, and possibly a render
stream that Space consumes. Space IDE tools talk to the child process rather than
importing the game into the default app process.

Benefits:

- Better isolation and crash containment.
- Avoids global `app` sharing and module-cache collisions.
- Closer to how independently published games actually run.

Costs and risks:

- Requires a protocol for input, timing, state serialization, lifecycle, and
  errors.
- Rendering is the hard part: Space would need texture streaming, frame capture,
  or another shared presentation mechanism.
- Pause/step/debug semantics become asynchronous and harder to make exact.
- More infrastructure than needed to validate the Snake/Space-runtime IDE use
  case.

This is a credible later path when isolation matters, especially if built on
Space's existing remote-control ideas, but it should not be the MVP.

### Approach C: external compositor or wlroots-style embedding

Space runs the game as an external window/application and embeds that surface in
Space through compositor integration.

Benefits:

- In theory, it could host many graphical programs without app-specific changes.
- It preserves process boundaries and standalone behavior.

Costs and risks:

- This repository's previous wlroots attempt is paused and removed. The status
  note documents DMA-BUF import failures, unreliable readback/black textures,
  fragile headless output commits, Xwayland socket collisions, and teardown
  crashes.
- It solves display embedding but not Space-specific IDE needs such as structured
  game snapshots, moldable controls, semantic pause/step, or in-runtime tools.
- It is overpowered for trusted Space-runtime apps and underpowered for semantic
  live development.

This approach is not recommended for the MVP.

## Decision

Use Approach A for the MVP: define a trusted in-process host lifecycle interface
for Space-runtime apps. Keep Approach B as a future isolation strategy and defer
Approach C until compositor integration has a separate, stable reason to exist.

The interface should be proven by Snake first. Snake should be refactored so its
standalone harness and hostable session share the same game/view code, while only
the standalone harness owns `Engine` and global renderer lifecycle.

## Hostable entry module contract

A hostable app entry module should export:

```fennel
{:metadata {:id "examples.snake"
            :title "Snake"}
 :main main
 :create create}
```

- `metadata` is plain data suitable for launchers, debug tools, and docs.
- `main` runs the app independently through the standalone harness.
- `create(host)` returns a hosted session and must not create, start, run, shut
  down, or drop an `Engine`.

The host table is intentionally small for the MVP:

```fennel
{:mode :embedded
 :viewport viewport
 :metadata host-metadata
 :request-quit request-quit-fn}
```

The host may grow later with explicit services such as logging, file access,
debug registry, or tool panels. Missing required host fields must fail loudly.

## Hosted session contract

`create(host)` returns a session table with these methods:

- `render-targets(self) -> table[]`: return presentation targets for Space's
  renderer to draw.
- `update(self, delta-ms:number) -> boolean`: advance app simulation when not
  paused and return whether visible state changed.
- `handle-input(self, event-name:string|keyword, payload:table) -> boolean`:
  process host-routed input and return whether it was handled.
- `on-viewport-changed(self, viewport:table) -> nil`: update surfaces when the
  host embedding rectangle changes.
- `set-paused(self, paused?:boolean) -> boolean`: set or toggle pause state and
  return the new pause state.
- `step-once(self) -> boolean`: advance exactly one simulation step while
  retaining paused mode.
- `snapshot(self) -> table`: return plain data for inspectors and moldable views.
- `drop(self) -> nil`: release widgets/surfaces/session-owned resources exactly
  once.

The MVP session does not expose live widget objects through `snapshot`. Debug
tools that need richer access can add explicit inspected views later, but the
base contract should stay serializable and safe to display.

## Ownership and lifecycle rules

- Space owns the process engine, renderer, main update loop, input routing,
  top-level presentation composition, and final shutdown in embedded mode.
- A hosted app owns its model, view widgets, surfaces, and app-local subscriptions
  created inside the session.
- A hosted app must not replace `app.engine`, `app.renderers`, or
  `app.active-world-runtime` directly.
- A hosted app must not subscribe directly to engine event signals in embedded
  mode. The host adapter routes updates and input into the session.
- Paused hosted apps remain drawable; pause only stops simulation advancement.
- Teardown must be deterministic and idempotent or fail with a documented explicit
  error. Silent no-op failure paths are not acceptable.

## Space host adapter

Space should provide a small adapter module that consumes a hostable module and
returns a controller suitable for IDE surfaces and tests.

The controller should expose:

- `runtime(self) -> table`: returns a runtime shape whose
  `presentation.render-targets` delegates to the hosted session.
- `update(self, delta-ms:number) -> boolean`.
- `dispatch-input(self, event-name, payload) -> boolean`.
- `set-paused(self, paused?) -> boolean`.
- `step(self, delta-ms?) -> boolean`.
- `snapshot(self) -> table`.
- `drop(self) -> nil`.

This adapter is the seam between Space's IDE tools and a game session. It also
keeps tests independent from a full HUD/canvas product UI.

## Snake MVP design

Snake should gain an engine-free session module that owns only game/session
state:

- Create `snake/session.fnl` for game state, elapsed tick accumulation, surface,
  screen widget, input mapping, pause/step, snapshot, viewport updates, and drop.
- Keep `snake/app.fnl` as the standalone harness: create engine, initialize
  renderers, create a session, connect engine events, run the engine loop,
  disconnect events, drop the session, drop standalone renderers, and shut down
  the engine.
- Update `examples/snake/assets/lua/main.fnl` to export `:create` and
  `:metadata` while preserving the existing `app-config.run-main` guard.
- Add focused tests proving that hosted Snake does not own an engine, still
  returns a presentation target, can pause/step, handles input, snapshots plain
  state, updates viewport, and drops cleanly.

This gives Space a concrete app that can run independently today and also be
hosted by a generic adapter tomorrow.

## IDE integration path

The first product surface should be deliberately modest: a test-proven controller
and a simple host smoke path are more important than choosing the final UI shell.
Once the lifecycle contract is proven, Space can mount the controller in one or
more surfaces:

- HUD/dialog panel for quick live-development tools.
- Canvas activity slot for an IDE-style embedded play surface.
- Sandbox/world activity later if the hosted app should coexist with spatial
  objects.
- Graph/debug nodes later for state snapshots, controls, and moldable views.

The host contract should not bake in one surface. It should expose presentation,
input, timing, and snapshot seams that any Space surface can consume.

## Error handling

- Requiring a hostable module without `create` must raise an explicit error.
- `create(host)` must validate required host fields and fail loudly on invalid
  input.
- The adapter must report failed `require` calls rather than falling back to an
  empty session.
- Hosted sessions must surface invalid viewport or input payload problems when
  they cannot be handled safely.
- Teardown errors should be explicit; hidden partial cleanup is worse than a
  visible failure during IDE development.

## Testing and validation

Implementation should use Space-native Fennel validation:

1. Build first if `./build/space` is missing or stale.
2. Compile-check touched `.fnl` files with `tools.fennel-check` using asset paths
   that include `examples/snake/assets` before repository `assets` when validating
   Snake files.
3. Run `make constraints` after compile checks.
4. Run existing Snake focused tests.
5. Add and run hosted-session and hosted-runtime focused tests.
6. Run broader `make test` only if implementation touches Space startup, global
   input routing, renderers, C++ bindings, or other high-risk shared runtime
   surfaces.

## Acceptance criteria

- The feasibility decision is documented as: in-process hosting is feasible and
  recommended for trusted Space-runtime apps; process-boundary hosting is future
  work; wlroots/compositor embedding is deferred.
- A hostable app entry module can be both independently runnable and importable.
- The minimal hosted session contract supports render targets, update, pause,
  single-step, input, viewport changes, snapshots, and teardown.
- Snake can be refactored to implement the contract without losing its standalone
  launch behavior.
- The design explicitly protects Space-owned engine, renderer, input loop, and
  top-level runtime ownership in embedded mode.
- The first implementation can be validated with focused Fennel compile checks,
  constraints, and focused Snake/host adapter tests.

## Open questions for later productization

- What is the trust and security model for third-party in-process hosted apps?
- How should Space discover external app asset roots and avoid module-name
  collisions across multiple loaded apps?
- Which IDE surface should become the default: canvas activity, HUD/dialog,
  graph node, sandbox, or a dedicated app workspace?
- How should the host lifecycle API be versioned once external repositories use
  it?
- Which state-inspection conventions should moldable views use beyond the plain
  `snapshot` table?
