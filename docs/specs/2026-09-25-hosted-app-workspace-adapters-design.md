# Hosted App Workspace Adapters Design

## Context

Space now has a hostable app runtime contract: an app module exports `metadata`,
`create(host)`, and optional `main`; `create(host)` returns a runtime composition
over host capabilities. The Snake example proves the same app composition can run
standalone or through a generic hosted controller.

The next requested work is larger than one safe implementation unit:

1. Mount hostable apps into Space HUD, canvas, and scene workspaces.
2. Add richer scene/world capabilities for 3D games.
3. Build a 3D Snake example that uses those capabilities.
4. Add moldable inspector/editor views around hosted apps.

These are related but independently valuable. The first required subproject is a
real Space workspace host: without it, 3D capabilities, 3D Snake, and inspector UI
would have no production mount target to integrate with.

## Goals

- Add Space-owned host adapters for mounting hostable apps into the active Space
  workspace without replacing `app.active-world-runtime`.
- Support HUD, canvas, and scene destinations through host capabilities rather
  than new per-game app APIs.
- Compose hosted app presentation targets into the active runtime presentation.
- Provide a minimal HUD control panel for pause, resume, step, and close.
- Preserve the hostable app contract: app code does not branch on hosted vs
  standalone mode.
- Keep Snake working as the initial hosted app fixture.

## Non-goals

- Do not implement richer 3D terrain/object/collision capabilities in this first
  subproject.
- Do not build 3D Snake in this first subproject.
- Do not build a full generic moldable inspector/editor UI in this first
  subproject.
- Do not add app marketplace/discovery, persistent launcher UX, or package
  registry workflows.
- Do not add process isolation, render-to-texture embedding, wlroots/Xwayland, or
  native external app mounting.

## Decomposition roadmap

### Subproject 1: Workspace host adapters and minimal control UI

This spec. Build shared embedded host services, Space HUD/canvas/scene adapter
capabilities, workspace mount lifecycle, presentation composition, and a minimal
HUD control panel.

### Subproject 2: 3D scene/world app capabilities

Add generic host capabilities over scene object creation/removal, transforms,
terrain queries, collision/physics hooks, and scene event/query semantics. This
depends on Subproject 1 because it needs a real embedded mount host.

### Subproject 3: 3D Snake example

Add a separate 3D Snake app/example that uses scene/world capabilities for snake
body objects, food, terrain interaction, camera/presentation, and controls. It
must not require Snake-specific host methods.

### Subproject 4: Moldable hosted app inspectors/editors

Add generic UI to browse hosted inspectors and commands, likely through HUD/canvas
panels, graph/table views, and command/action surfaces. This depends on the
workspace mount registries and benefits from 3D Snake as a richer fixture.

## Existing architecture fit

- HUD supports `add-panel-child`, overlays, panel restorer APIs, and dialog
  builders.
- Canvas supports activity slots with isolated contexts, focus scopes, render
  target exposure, panel children, activation/deactivation, and teardown.
- Scene supports activity slots, scene presentation targets, panels/objects,
  terrain helpers, camera/input controls, and sandbox activity patterns.
- `activity-presentation.fnl` aggregates scene, canvas, and HUD render targets for
  an active runtime.
- `app-host.runtime-controller` already mounts runtime facets and delegates
  scheduler/input/inspector/command behavior through host services.

The missing piece is a Space shell host implementation that uses these existing
surfaces without replacing the active runtime or teaching apps about HUD/canvas/
scene modes.

## Considered approaches

### Approach A: active workspace mount registry

Create a workspace mount object that owns a hosted controller and host services,
registers itself on the active runtime, and lets `activity-presentation` include
hosted render targets alongside existing scene/canvas/HUD targets.

Benefits:

- Does not replace `app.active-world-runtime`.
- Allows multiple hosted mounts later.
- Keeps host adapter lifecycle explicit and testable.
- Works with current presentation target architecture.

Costs:

- Requires extending presentation aggregation to collect hosted mounts.
- Requires careful drop/unregister behavior to avoid stale targets.

### Approach B: hosted app as a synthetic activity

Model each hosted app as a Space activity and let existing activity switching own
presentation/input/update.

Benefits:

- Fits established activity patterns.
- Good eventual UX for full-screen app workspaces.

Costs:

- Too heavy for embedding apps in HUD/dialog/canvas/scene simultaneously.
- Pushes early work into app launcher/activity UX before the mounting foundation
  is proven.

### Approach C: render-to-texture panel embedding

Render hosted apps into offscreen textures, then put those textures in HUD,
canvas, or scene panels.

Benefits:

- Strong visual containment in panels.
- Could support complex layout transforms later.

Costs:

- Requires render-to-texture infrastructure and input coordinate remapping.
- Overkill for the first embedded host path.

## Decision

Use Approach A for the first subproject. Add a workspace mount registry and
Space host capability factory now. Defer synthetic activity UX and render-to-
texture containment until there is a proven workspace host path.

## Design

### Shared host services

Extract reusable host service factories from standalone runtime code:

- registry service for surfaces, inspectors, and commands;
- scheduler service with pause, update, step, register, unregister, and list;
- input service with register, unregister, dispatch, and list;
- assets and logging services.

The standalone runtime should use the shared services so standalone and embedded
hosts share behavior.

### Space host capability factory

Add `SpaceHost.create(opts) -> host` for embedded Space mounts. It should expose:

- `viewport`
- `surfaces`
- `scheduler`
- `input`
- `inspectors`
- `commands`
- `assets`
- `logging`
- `lifecycle`
- optional `hud`, `canvas`, and `scene` adapter capabilities

The embedded `lifecycle:quit` must close the hosted mount, not quit the Space
process. If no close callback is provided, it must fail loudly.

HUD/canvas/scene adapter capabilities should proxy existing surface APIs and own
cleanup for children they create.

### Workspace mount

Add `WorkspaceMount.mount(opts) -> mount`:

- builds a `SpaceHost`;
- calls `HostedRuntime.mount` with the same host;
- registers the mount on the active runtime without replacing the runtime;
- exposes `mount:render-targets()` and `mount:drop()`;
- makes drop idempotent and ordered: unregister from runtime, drop controller,
  then drop host.

`HostedRuntime` should gain a convenience wrapper such as
`mount-in-workspace(opts)` while keeping existing `mount(opts)` behavior.

### Presentation composition

`activity-presentation` should include hosted workspace mount render targets from
the active runtime. Existing scene/canvas/HUD targets must remain present. Dropped
mounts must not contribute targets.

The initial order should be:

1. existing scene targets;
2. existing canvas targets;
3. hosted app mount targets;
4. existing HUD target.

This keeps HUD chrome/control panels above hosted app targets while preserving the
current scene/canvas order.

### Minimal hosted app control panel

Add a small HUD panel session for development use:

- app title/status;
- Pause;
- Resume;
- Step;
- Close.

The panel should mount an app through `WorkspaceMount`, delegate pause/resume/step
to the controller, and drop the mount exactly once on close. It should fail loudly
when no HUD is available.

This is not the final moldable inspector/editor UI. It is just the minimal visible
control surface needed to prove real hosted development mounting.

## Error handling

- Missing host capabilities must raise explicit errors.
- Missing HUD/canvas/scene shell objects should fail only when that optional
  adapter is actually used.
- Embedded quit without a close callback must fail explicitly.
- Dropping a mount must unregister all hosted presentation/control state exactly
  once.
- Teardown errors must surface; cleanup should still attempt remaining owned
  resources.

## Testing and validation

Implementation should use Space-native Fennel validation:

1. Build first if `./build/space` is missing or stale.
2. Run `make fennel-check` or touched-file `tools.fennel-check` for narrow tasks.
3. Run `make constraints`.
4. Run focused tests for shared services, Space host adapters, workspace mount,
   workspace panel, standalone runtime, and Snake hosted runtime.
5. Because this touches presentation/runtime composition, run a broader relevant
   local suite such as `tests.fast:main` before final review.
6. PR CI remains the authoritative integration gate.

## Acceptance criteria

- A hostable app can be mounted into the active Space workspace without replacing
  `app.active-world-runtime`.
- Hosted app render targets are included by active runtime presentation and are
  removed after mount drop.
- Embedded `lifecycle:quit` closes the hosted mount; standalone `lifecycle:quit`
  still quits through the standalone host.
- HUD, canvas, and scene adapter capabilities proxy existing surface APIs and
  clean up host-created children where removal APIs exist.
- A minimal HUD control panel can pause, resume, step, and close a hosted app.
- Existing Snake hosted and standalone tests remain green without adding
  hosted-vs-standalone branches to Snake app code.
- No new per-game required app methods are added.

## Follow-up acceptance gates

Subproject 2 should not start until this subproject provides a tested scene host
adapter and workspace mount. Subproject 3 should not start until Subproject 2
defines scene/world capabilities. Subproject 4 should not start until this
subproject exposes stable hosted inspector/command registries in an embedded
workspace host.
