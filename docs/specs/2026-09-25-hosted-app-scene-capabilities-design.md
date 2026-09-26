# Hosted App Scene Capabilities Design

## Context

Hosted Space apps can now mount into the active workspace through Space host
capabilities and workspace presentation composition. The next dependency for 3D
games is a generic scene/world capability layer. A future 3D Snake app should be
able to create snake body objects, move them in the scene, query terrain/objects,
and respond to collisions or semantic object tags without importing Space's
default app, sandbox activity internals, graph modules, or any Snake-specific host
API.

The key design constraint remains unchanged: apps implement `create(host) ->
runtime` and use host capabilities. A hosted game must not branch on whether it
is standalone or embedded, and new game features must not expand the required app
entrypoint surface.

## Goals

- Add generic scene/world host capabilities for hosted apps.
- Let apps create, update, query, and remove app-owned scene objects through a
  capability wrapper.
- Let apps query terrain height/rays and semantic objects without depending on
  Space internals.
- Preserve ownership: the host owns Space scene slots/runtime; hosted apps own
  only resources allocated through their capability instance.
- Provide fake-backed tests first, then wire to existing scene slot APIs where
  present.
- Prepare for a later 3D Snake example without adding Snake-specific methods.

## Non-goals

- Do not implement the 3D Snake example in this subproject.
- Do not build generic moldable inspector/editor UI in this subproject.
- Do not implement a full physics query abstraction beyond minimal object/terrain
  queries that existing Space APIs can support.
- Do not expose raw `app.scene` or sandbox activity internals to hosted apps.
- Do not add process isolation, render-to-texture embedding, or native external
  app mounting.

## Existing architecture fit

- Scene activity slots already provide isolated camera/render target/focus context
  and activation/deactivation APIs.
- Scene supports `add-panel-child`, `add-object`, `build`, presentation targets,
  terrain ray/height helpers, and sandbox activity patterns.
- Terrain modules expose flat/perlin/heightfield physics and query helpers.
- Hosted apps already receive `host.scene` as an optional adapter capability from
  Space host creation; this subproject should evolve that adapter from a thin
  proxy into a documented capability.

## Capability shape

The embedded host should expose a `host.scene` capability with stable operations:

```fennel
{:spawn spawn
 :despawn despawn
 :set-transform set-transform
 :get-transform get-transform
 :list-owned list-owned
 :query-volume query-volume
 :raycast-terrain raycast-terrain
 :height-at height-at
 :drop drop}
```

All methods operate on host-owned handles, not raw Space entities. Handles should
be plain tables containing at least:

```fennel
{:id id
 :kind kind
 :tags tags}
```

The host may store raw scene objects internally, but app code receives handles and
semantic query results.

## Object ownership

`host.scene:spawn(spec)` creates an app-owned object and returns a handle. The
spec should support:

```fennel
{:kind :cube|:panel|:custom
 :id optional-id
 :tags [:snake :body]
 :position [x y z]
 :rotation rotation-or-nil
 :size [x y z]
 :builder builder-or-nil
 :object object-or-nil}
```

The capability should track every object it creates and remove those objects on
`despawn(handle)` or `drop()`.

The first implementation can support a minimal fake-backed object shape and proxy
to existing `scene:add-panel-child` / `scene:add-object` when available. It should
fail loudly when asked to spawn a kind the backing scene cannot support.

## Queries

The query surface should be deliberately semantic and conservative:

- `query-volume(bounds, opts)` returns objects/handles whose tags/layers match the
  query when the backing host can answer.
- `height-at(point, opts)` returns terrain height or `nil` when terrain is absent.
- `raycast-terrain(ray, opts)` returns terrain hit info or `nil` when absent.

For the MVP, object-volume query can be registry-based over app-owned handles and
host-supplied semantic objects. It does not need full Bullet overlap queries yet.
Future physics/collision integration can extend the capability implementation
without changing the app entrypoint.

## Interaction with unrelated Space scene objects

Apps should not inspect arbitrary Space objects directly. The scene capability is
responsible for converting host scene state into semantic query results:

```fennel
{:handle handle-or-nil
 :id id
 :kind kind
 :tags tags
 :solid? boolean
 :position position
 :source :owned|:host}
```

Unknown host objects should be ignored unless they expose host-provided tags or a
solid/collision semantic. A later policy can choose whether unknown solids block
3D Snake by default; this subproject should make the policy explicit and tested
for the adapter.

## Standalone parity

Standalone hosted apps should receive the same `host.scene` capability shape from
a standalone scene service. The standalone implementation may be registry/fake
backed initially; that is enough for app logic tests and future 3D Snake logic.
Embedded Space hosts can proxy existing scene APIs.

## Error handling

- Missing `host.scene` must fail through `Capabilities.require` in apps that need
  scene support.
- Unsupported spawn kinds must fail loudly.
- Invalid handles passed to `despawn`, `set-transform`, or `get-transform` must
  fail loudly unless explicitly documented as idempotent cleanup.
- `drop()` must remove owned objects exactly once and surface cleanup failures.
- Query methods must not silently convert backend errors into empty results.

## Testing and validation

Implementation should use Space-native Fennel validation:

1. Build first if `./build/space` is missing or stale.
2. Compile-check touched `.fnl` files with `tools.fennel-check`.
3. Run `make constraints`.
4. Run focused tests for standalone/fake scene capability behavior and embedded
   scene host adapter behavior.
5. Run existing scene activity slot and hosted app workspace mount tests to ensure
   integration remains stable.
6. Run broader relevant local tests if scene presentation or activity slot code is
   touched.

## Acceptance criteria

- `host.scene` exposes documented object ownership and query methods.
- Hosted apps can spawn, transform, list, query, and drop app-owned scene objects
  through handles.
- Terrain query methods delegate to existing scene terrain helpers where present
  and fail/return `nil` according to documented policy when terrain is absent.
- Embedded scene objects created through the capability are removed on mount/host
  drop.
- Standalone hosts can provide the same scene capability shape for app logic tests.
- No new required app entrypoint methods are added.
- No app code depends on sandbox/default-app internals.

## Follow-up

After this subproject, build the 3D Snake example against `host.scene`. The 3D
Snake implementation should validate whether the capability needs richer physics
or semantic object policies before committing to a larger world API.
