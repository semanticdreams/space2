# 3D Snake Scene View Design

## Context

Space now supports hosted app scene capabilities through `host.scene`. The next
step is to validate that capability with a concrete app: the existing Snake
example should mirror its gameplay into a 3D scene while preserving the current
runtime composition contract and existing 2D UI surface.

The current Snake app already exports `metadata`, `create(host)`, and `main`, and
its gameplay is cleanly separated into grid-based logic. This subproject should
reuse that logic and add a scene synchronization layer rather than replacing the
game or adding host-specific branches.

## Goals

- Add a first 3D Snake slice using `host.scene`.
- Preserve the existing 2D Snake UI and controls.
- Keep Snake game logic host-independent and reusable.
- Require scene access through `Capabilities.require host :scene`.
- Mirror Snake cells into app-owned scene handles with semantic tags.
- Use embedded-compatible scene spawns: concrete objects for `:custom`/`:cube`,
  not registry-only fake handles.
- Clean up all Snake-owned scene handles on runtime drop.
- Test scene synchronization independently and through hosted runtime creation.

## Non-goals

- Do not add a new hosted app entrypoint or Snake-specific host API.
- Do not branch app behavior on hosted-vs-standalone mode.
- Do not remove the current orthographic Snake UI surface.
- Do not add camera controls, scene persistence, terrain/raycast gameplay,
  physics integration, or moldable inspectors in this slice.
- Do not change the generic `host.scene` API unless tests reveal a capability bug
  that must be fixed for this app.

## Recommended approach

Use a dedicated `snake.scene-view` module that owns only Snake scene handles. The
module consumes the existing `snake.game` object and a `host.scene` capability,
then mirrors non-empty grid cells into scene objects:

- snake head;
- snake body segments;
- food.

Board/base and boundary markers are not required for this first slice; they can
be added later if camera or terrain work needs more spatial context.

This approach was chosen over two alternatives:

- Registry-only `:cube` spawns are too weak because embedded Space hosts require
  a concrete object for `:custom`/`:cube` spawns.
- Mounting the current 2D UI as a scene panel is compatible but not a meaningful
  3D validation of scene object ownership and transforms.

## Architecture

### Scene view module

`examples/snake/assets/lua/snake/scene-view.fnl` should expose:

```fennel
{:create create}
```

`create(opts)` accepts:

```fennel
{:scene scene-capability
 :game snake-game
 :cell-size optional-number
 :origin optional-[x y z]}
```

It returns a view object with:

```fennel
{:sync sync
 :drop drop}
```

`sync()` computes the current visual cells from the game state and updates the
scene. The first implementation should use deterministic diffing by logical cell
key: keep existing handles where the same object role remains, spawn new handles
for new cells, and despawn obsolete handles. If transforms need to change for an
existing handle, use `scene:set-transform` rather than creating duplicate
handles.

`drop()` despawns every handle created by this scene view exactly once. It must
not call `host.scene:drop()` because the host may own other app or adapter
resources.

### Scene objects

Spawn specs should use semantic tags and concrete objects:

```fennel
{:kind :custom
 :id "snake-head-12-8"
 :tags [:snake :head]
 :position [x y z]
 :size [sx sy sz]
 :object object}
```

The concrete object should be small and local to the Snake example. It only needs
to satisfy embedded Space scene object expectations well enough for
`host.scene:spawn` to proxy it through `scene:add-object`. Tests may use a fake
scene capability that validates object presence without rendering.

Positions map 2D Snake grid coordinates to a flat X/Z board:

- grid `x` maps to scene X;
- grid `y` maps to scene Z;
- scene Y is height above the board;
- food and head/body should use distinct colors/tags.

### Runtime integration

`snake.app.create(host)` should require `host.scene` alongside existing required
capabilities. It should create a scene view after the game object exists and call
`scene-view:sync()` wherever the screen is synchronized:

- initial runtime creation;
- successful direction turns;
- simulation steps;
- restart after game over.

Runtime drop should unregister existing scheduler/input/inspector/surface facets
as before and also call `scene-view:drop()` idempotently.

### Error handling

- Missing `host.scene` fails through `Capabilities.require` with a clear scene
  capability error.
- Missing scene methods fail loudly during `scene-view` creation or first sync.
- Unsupported embedded scene spawns should surface existing `host.scene` errors.
- Drop must surface despawn failures instead of silently hiding them.

## Testing strategy

Add focused scene-view tests under `examples/snake/assets/lua/tests/`:

- initial sync spawns head/body/food scene specs with concrete objects and tags;
- step/restart sync updates scene handles without leaks;
- drop is idempotent and despawns all scene-view-owned handles once;
- scene specs remain embedded-compatible by requiring `:object` on custom spawns.

Update hosted runtime tests:

- fake hosts include a scene capability;
- runtime creation spawns scene-owned handles;
- runtime drop leaves `host.scene:list-owned()` empty;
- missing scene capability fails loudly.

Validation should use Space-native Fennel commands:

1. `make fennel-check` or touched-file `tools.fennel-check`.
2. `make constraints`.
3. Focused Snake scene/runtime tests.
4. Broader Snake tests when app wiring changes.

## Acceptance criteria

- Snake uses `host.scene` through the generic capability, not a Snake-specific
  host API.
- The same Snake runtime path works in standalone and embedded hosts.
- Initial Snake creation spawns app-owned scene handles for visible gameplay
  state.
- Movement, restart, and game-over flows keep scene handles synchronized with the
  game state.
- Runtime drop removes every Snake-owned scene handle and leaves no stale render
  targets.
- Missing `host.scene` fails loudly.
- Existing 2D Snake UI/tests continue to pass.

## Follow-up

After this slice, richer 3D Snake work can add camera controls, terrain-aware
placement, collision policies against host semantic objects, and moldable scene
inspectors/editors. Those should remain separate subprojects.
