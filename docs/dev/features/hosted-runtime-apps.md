# Hosted Runtime Apps

Space-runtime apps are hostable when their entry module exports a runtime composition factory.

```fennel
{:metadata {:id "examples.snake" :title "Snake" :host-api 1}
 :create create
 :main main}
```

`create(host)` returns a runtime composition object. It must not create, start, run, shut down, or drop `Engine` directly. It must not replace `app.engine`, `app.renderers`, or `app.active-world-runtime`.

## Host capabilities

The host provides services such as `viewport`, `surfaces`, `presentation`, `scheduler`, `input`, `inspectors`, `commands`, `assets`, `logging`, and `lifecycle`. Apps require capabilities by name and fail loudly when required services are absent. Apps do not receive or branch on a hosted-vs-standalone mode flag.

Embedded Space workspace hosts provide the same generic services plus optional
Space surface adapters when the shell exposes them:

- `host.hud` proxies `app.hud` panel insertion/removal.
- `host.canvas` proxies `app.canvas` panel insertion/removal.
- `host.scene` provides the generic scene capability when a Space scene is
  available.

Adapters own children added through them. Dropping the embedded host removes
those owned HUD/canvas panel children exactly once; children removed through the
adapter are no longer removed again during host teardown. Scene objects are owned
by the scene capability handles described below.

## Scene capability

Apps that need scene access should require `host.scene` through capabilities and
then use its generic methods: `spawn`, `despawn`, `set-transform`,
`get-transform`, `list-owned`, `query-volume`, `height-at`, `raycast-terrain`,
and `drop`. `spawn` returns an app-owned handle; app code passes that handle
back to scene methods instead of retaining raw Space scene entities or backend
objects. Invalid handles and unsupported spawn kinds fail loudly.

Embedded Space hosts expose `host.scene` when `app.scene` exists. The embedded
adapter proxies panel spawns to the Space scene's panel APIs and terrain queries
to Space scene methods such as `height-at`, `height-at-world-point`, and
`raycast-terrain`. Dropping the host drops the capability, despawning owned
objects and removing app-owned Space scene children exactly once.

Standalone hosts expose the same capability shape with a registry-backed owned
object model, so app logic tests can exercise scene spawning, transforms, owned
object listing, volume queries, and optional terrain backend queries without
branching on hosted-vs-standalone mode.

The Snake example uses this capability as the first app-level scene consumer: its runtime mirrors grid gameplay into app-owned scene handles while keeping the same `create(host)` path for standalone and embedded hosts. Embedded custom objects provide concrete `spec.object` values because registry-only fake handles are not enough for real Space scene insertion.

## Runtime composition facets

A runtime may expose:

- `metadata`: plain metadata.
- `presentation`: existing Space presentation provider methods such as `render-targets`, `input-controls`, `screen-pos-ray`, and `camera`.
- `lifecycle`: deterministic teardown such as `drop`.
- `scheduler`: app simulation registrations.
- `inspectors`: plain-data or moldable inspector registrations.
- `commands`: command registrations for tools and live controls.

The core entry API does not add a new required method for every game feature.

## Pause, step, and inspection

Hosts pause and step scheduler lanes. Apps register pausable work with `host.scheduler`. Apps expose state through `host.inspectors` or an `inspectors` runtime facet. Pause, step, and inspection are not required methods on every app.

## Standalone and embedded hosts

Standalone launch and embedded mounting construct different generic hosts, then call the same `create(host)` app factory. App logic is shared.

In standalone mode `host.lifecycle:quit()` exits through the standalone engine.
In embedded workspace mode `host.lifecycle:quit()` closes the workspace mount via
the host's close callback; it does not quit the Space process and does not
replace `app.active-world-runtime`, `app.renderers`, or global renderer state.
Apps should request capabilities from the host rather than checking a
hosted-vs-standalone flag.

## Workspace mounting

Workspace embedding uses `HostedRuntime.mount-in-workspace(opts)`, which delegates
to `app-host.workspace-mount` and returns a mount table:

```fennel
(local HostedRuntime (require :hosted-app-runtime))
(local mount (HostedRuntime.mount-in-workspace {:runtime runtime
                                                :app app-shell
                                                :module app-module}))
```

`WorkspaceMount.mount(opts)` accepts the same app module options as
`HostedRuntime.mount` plus a Space runtime and shell. It creates the embedded
Space host, mounts the app through the shared runtime controller, and registers
the resulting mount in `runtime.hosted-app-mounts`. The runtime owns that list:
workspace code should treat it as the active mount registry and should not use it
to replace `app.active-world-runtime` or global renderer state.

Activity presentation composes targets from the active runtime in stable order:
scene target, canvas target, each hosted workspace mount target, then the shell
HUD target. Dropping a mount removes it from `runtime.hosted-app-mounts`, so its
targets disappear from presentation composition without mutating renderers.

Mount teardown is idempotent. `mount:drop()` removes the mount from the runtime
registry, drops the app controller, and drops the embedded host so adapter-owned
HUD/canvas/scene children are removed exactly once. `host.lifecycle:quit()` for
an embedded host calls the same mount drop path. If app creation fails after the
embedded host has been created, workspace mounting cleans up the host before
rethrowing the original mount error.

## Minimal workspace controls

`app-host.workspace-panel` provides the first Space-hosted control surface:

```fennel
(local WorkspacePanel (require :app-host.workspace-panel))
(local session (WorkspacePanel.open {:runtime runtime
                                     :app app-shell
                                     :module app-module}))
```

`WorkspacePanel.open(opts)` requires `opts.app.hud` or global `app.hud`, mounts
the app through `WorkspaceMount.mount(opts)`, and adds one HUD panel child that
describes the hosted app session. The returned session exposes `session.mount`
plus `session:pause()`, `session:resume()`, `session:step(delta-ms)`, and
idempotent `session:close()` controls. Pause, resume, and step delegate to the
generic runtime controller; close removes the HUD child and drops the workspace
mount exactly once.

This panel is intentionally only a minimal control/session descriptor. Richer
inspector/editor rendering and persistent app discovery or launcher UX are
follow-up subprojects, not part of the workspace mount contract.

## Deferred alternatives

Process-isolated hosting and compositor embedding are future work. wlroots/Xwayland embedding remains deferred because the previous attempt was unstable in headless rendering, DMA-BUF import, readback, socket lifecycle, and teardown.
