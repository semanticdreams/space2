# Hostable Space Apps Design

## Context

Space can already run independent Fennel applications such as the Snake example
under `examples/snake/`. Snake proves the packaging and launch path, but it is a
very small game. Real games will use more Space features: multiple presentation
surfaces, input contexts, audio, assets, storage, tool panels, debug inspectors,
commands, and app-specific editor views.

The important design constraint is therefore not “make Snake embeddable.” It is:
an independently publishable Space-runtime app should be the same program whether
it is launched as its own desktop app or mounted inside Space for live
development. If every new game requires new mandatory host methods, or if app
code branches on “hosted vs standalone,” the feature has failed.

The right boundary is a stable runtime-composition contract. App code builds a
runtime out of host-provided capabilities. Standalone launch and in-Space hosting
are different generic host implementations, not different app implementations.

## Goals

- Define a hostable app contract that does not grow a new required method for
  every game feature.
- Ensure standalone and embedded paths call the same app factory and execute the
  same app logic.
- Move hosted-vs-standalone conditional behavior into generic hosts/harnesses,
  not game code.
- Support real games that use multiple Space surfaces and services.
- Preserve independent publishing for apps such as Snake.
- Enable Space IDE workflows: play, pause, step, inspect state, attach moldable
  views, route input, and render inside Space.

## Non-goals

- Do not host arbitrary native executables as part of the MVP.
- Do not revive wlroots/Xwayland compositor embedding for this feature.
- Do not sandbox untrusted in-process apps.
- Do not design a full app marketplace, launcher, or persistent discovery UI.
- Do not promise long-term public API stability before the runtime-composition
  MVP proves the contract.
- Do not require independent apps to depend on Space's default HUD, graph,
  wallet, LLM, or default `main` app modules.

## Design principle

The app API should be small and stable:

```fennel
{:metadata {:id "examples.snake"
            :title "Snake"
            :host-api 1}
 :create create
 :main main}
```

`create(host)` returns a **runtime composition object**, not a bespoke game
session API. The host interacts with protocol facets on that runtime when they
exist. New capabilities appear as host services or optional runtime facets; they
do not become new required app entrypoint methods.

Standalone launch is just:

```fennel
(fn main []
  (StandaloneRuntime.run {:module AppModule}))
```

In-Space hosting is just:

```fennel
(HostedRuntime.mount {:module AppModule :host space-host})
```

Both paths call the same `AppModule.create(host)`. App code does not receive a
`:mode :embedded` flag and should not branch on hosted-vs-standalone state.

## Host capabilities

The host is a capability table. It represents the services available to an app in
either standalone or embedded mode:

```fennel
{:api-version 1
 :metadata host-metadata
 :viewport viewport-service
 :surfaces surface-factory-service
 :presentation presentation-composition-service
 :scheduler scheduler-service
 :input input-routing-service
 :inspectors inspector-registry-service
 :commands command-registry-service
 :assets asset-service
 :logging logging-service
 :lifecycle lifecycle-service}
```

The list can grow without changing the app factory signature. Apps request the
capabilities they need and fail loudly when a required service is absent. Optional
features are detected by capability presence, not by hosted-vs-standalone mode.

Examples:

- A simple Snake game may require `viewport`, `surfaces`, `scheduler`, `input`,
  and `presentation`.
- A larger game may also require `assets`, `commands`, `inspectors`, audio, save
  data, or multiple surface factories.
- Space IDE hosts can add extra capabilities for moldable tools while standalone
  hosts can provide no-op-free, real equivalents or fail explicitly when a game
  requires an unsupported capability.

## Runtime composition object

`create(host)` returns a table composed of protocol facets. The minimum useful
runtime shape is:

```fennel
{:metadata metadata
 :presentation presentation-provider
 :lifecycle lifecycle-provider
 :scheduler scheduler-registrations
 :inspectors inspector-provider
 :commands command-provider}
```

Only `metadata`, `presentation`, and `lifecycle` are expected for the Snake MVP.
Other facets are optional and become useful as games mature. The host should
query and mount known facets, not require a game-specific interface.

The `presentation` facet should reuse existing Space protocols where possible,
especially:

```fennel
:render-targets(self) -> table[]
:input-controls(self) -> table|nil
:screen-pos-ray(self, pos, opts) -> ray|nil
:camera(self, opts) -> camera|nil
```

This fits current renderer behavior, which already consumes
`runtime.presentation:render-targets()`.

The `lifecycle` facet should expose deterministic teardown, such as:

```fennel
:drop(self) -> nil
```

Scheduler, inspector, and command facets should be generic registries rather than
per-game methods.

## Pause, step, and inspection

Pause, step, and inspection are IDE host behavior, not bespoke app entrypoint
methods.

- Apps register simulation work with `host.scheduler` as pausable work.
- The host pauses scheduler lanes; rendering remains active.
- The host steps pausable scheduler lanes by one frame or one registered tick.
- Apps register inspectors through `host.inspectors` or return an `inspectors`
  facet.
- Inspectors expose plain data or moldable views through a registry; the core app
  API does not require every game to implement `snapshot`, `set-paused`, or
  `step-once` methods.

Snake may expose a simple game-state inspector as the first example, but that is
an inspector registration, not a special required method on every app.

## Ownership and lifecycle rules

- App logic constructs a runtime composition from host capabilities.
- Standalone hosts own a process engine, renderer, main update loop, and shutdown.
- Embedded Space hosts reuse the existing process engine, renderer, update loop,
  input routing, and shutdown.
- App code must not create/start/run/shut down `Engine` directly.
- App code must not replace `app.engine`, `app.renderers`, or
  `app.active-world-runtime` directly.
- App code must not connect directly to engine signals. It registers through host
  scheduler/input/lifecycle services.
- Runtime teardown drops app-owned widgets, surfaces, registrations, and local
  resources exactly once.
- Missing required capabilities, invalid payloads, failed module loads, and
  teardown failures surface explicit errors.

## Considered approaches

### Approach A: runtime composition over host capabilities

Apps export `create(host) -> runtime`. Hosts provide capabilities; apps return
known protocol facets. Standalone and embedded hosts differ internally but expose
the same capability surface.

Benefits:

- Stable public app entry shape.
- No hosted-vs-standalone branch in app logic.
- Real games can use more surfaces and services without expanding required app
  methods.
- Fits current Space presentation patterns.
- Keeps pause/step/inspection as host services that can improve over time.

Costs and risks:

- Requires designing a good initial host capability table.
- Existing Snake must move engine ownership out of app composition and into a
  standalone host/harness.
- Service boundaries must fail loudly; silent missing services would make apps
  behave differently across hosts.

### Approach B: bespoke hosted session methods

Apps export `create(host) -> session` with fixed methods such as `update`,
`handle-input`, `set-paused`, `step-once`, `snapshot`, and `drop`.

Benefits:

- Easy to prove with Snake.
- Small initial implementation.

Costs and risks:

- Too Snake-shaped and likely to grow for every real game feature.
- Encourages the app API to become a grab bag of host requests.
- Makes pause/step/inspection app-specific rather than host-level IDE behavior.

This approach is rejected as the long-term contract.

### Approach C: separate process or compositor embedding

The game stays in a separate process and Space consumes pixels or a runtime
bridge.

Benefits:

- Better isolation and closer to published app execution.

Costs and risks:

- Requires input, timing, state, lifecycle, and rendering protocols.
- Pixel embedding does not provide semantic IDE tools by itself.
- The previous wlroots path is paused due DMA-BUF/readback/headless/Xwayland
  lifecycle failures.

This remains future work for isolation, not the MVP.

## Decision

Use Approach A. The public contract is:

```text
entry module exports metadata, create(host), and optional main
create(host) returns a runtime composition object
hosts provide capabilities and mount known runtime facets
```

Standalone and embedded behavior differ only in generic host implementations.
Game/app code builds one runtime composition and does not branch on host mode.

## Snake MVP design

Snake should prove the contract without becoming the contract:

- `snake/app.fnl` becomes the app composition module. Its `create(host)` builds
  game state, an orthographic surface, presentation facet, scheduler
  registration, input registration, lifecycle facet, and a simple inspector.
- `main.fnl` remains a small entry bridge that delegates standalone launch to a
  reusable standalone host/harness.
- A generic hosted runtime adapter mounts any `create(host) -> runtime` app by
  providing Space capabilities and attaching known runtime facets.
- Snake-specific tests prove standalone launch still works and hosted mounting
  uses the same `create(host)` path.

## IDE integration path

The first product surface should mount a runtime composition through the generic
host adapter. Later UI choices can be independent of the app contract:

- Canvas activity slot for an embedded play surface.
- HUD/dialog panel for quick tools.
- Graph/debug nodes for inspectors, commands, and moldable views.
- Sandbox/world activity if the app should coexist spatially with other objects.

## Testing and validation

Implementation should use Space-native Fennel validation:

1. Build first if `./build/space` is missing or stale.
2. Compile-check touched `.fnl` files with `tools.fennel-check`.
3. Run `make constraints` after compile checks.
4. Run focused tests for host capabilities, runtime mounting, scheduler pause and
   step, inspector registration, Snake hosted mounting, and existing Snake logic
   and view behavior.
5. Run broader `make test` only if implementation touches Space startup, global
   input routing, renderers, C++ bindings, or other high-risk shared runtime
   surfaces.

## Acceptance criteria

- Public app contract has only stable entry shape: `metadata`, `create(host)`,
  and optional `main`.
- `create(host)` returns a runtime composition with known protocol facets, not a
  bespoke game session method list.
- App code does not check hosted-vs-standalone mode.
- Standalone and embedded paths construct different generic hosts and call the
  same app factory.
- Multiple surfaces/features are accessed through host capabilities and runtime
  facets, not new required app methods.
- Pause/step/inspection are implemented by scheduler, inspector, and command
  services.
- Snake remains independently runnable and becomes hostable without app-owned
  engine/renderers in embedded mode.

## Open questions for later productization

- Which host capabilities are mandatory for API version 1, and which are optional
  extensions?
- How should external app asset roots and module namespaces be isolated when
  multiple apps are mounted in one Space process?
- Which IDE surface should become the default: canvas activity, HUD/dialog,
  graph node, sandbox, or a dedicated app workspace?
- How should capability and runtime facet versions be negotiated once external
  repositories depend on the API?
- What inspector registry shape best supports moldable views beyond plain data?
