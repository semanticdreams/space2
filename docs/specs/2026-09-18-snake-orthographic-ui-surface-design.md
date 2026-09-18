# Snake Orthographic UI Surface Design

## Context

The graphical Snake example currently owns a custom `snake/surface.fnl` module
that recreates part of Space's HUD presentation stack: viewport scaling,
orthographic projection, a `BuildContext`, a `LayoutRoot`, and a renderer
presentation target. This was intended to keep the example copyable, but it has
kept exposing presentation bugs that the main Space app does not have: upside
down text, incorrect stack order, and now persistent text flicker/overlap.

The main app is more complex, but its HUD path is more robust because it uses a
consistent retained presentation target, centralized renderer contract, stable
layout root, and explicit depth/text batching conventions. Snake should stop
teaching a one-off partial reimplementation of those patterns.

## Goals

- Replace Snake's one-off custom surface with a Space-provided reusable
  orthographic UI presentation primitive.
- Keep Snake as a standalone/copyable example under `examples/snake` while
  allowing it to depend on reusable modules from `assets/lua`.
- Preserve Snake's existing gameplay, controls, board layout, custom title, and
  graphical view behavior.
- Eliminate surface-caused text flicker/overlap by aligning Snake with Space's
  retained HUD-style rendering contract.
- Document when to use the new primitive versus the product HUD or Canvas.

## Non-Goals

- Do not import the full main Space product shell into Snake.
- Do not use Canvas for Snake's board/text UI.
- Do not redesign Snake gameplay, scoring, controls, colors, or assets.
- Do not change renderers, shaders, text batching internals, or C++ engine code.
- Do not add generalized HUD panels, focus traversal, click handling,
  persistence, movable/resizable support, or activity-slot support.

## Considered Approaches

### Approach A: Use `Hud` directly

`assets/lua/hud.fnl` is the robust main app path and can be instantiated in
tests, but it is coupled to product-shell concepts and app globals such as
clickable/hoverable registries, themes, command hints, focus/movable/resizable
state, and default HUD layout behavior. Using it directly would make Snake less
copyable and risk importing product UI behavior the example does not need.

### Approach B: Add a reusable orthographic UI surface

Create a small `assets/lua/orthographic-ui-surface.fnl` module that owns exactly
the reusable presentation-target pieces Snake needs:

- `LayoutRoot` and `BuildContext` ownership;
- viewport-to-world sizing;
- non-inverted orthographic projection;
- retained root entity lifecycle;
- render-context delegation for Space widgets/text/quads;
- presentation target compatible with `Renderers`.

Snake imports this shared module and deletes `examples/snake/assets/lua/snake/surface.fnl`.

This keeps the example standalone while making the surface a supported Space
primitive instead of a Snake-specific ad hoc copy.

### Approach C: Keep patching Snake's custom surface

This is the smallest code movement but keeps the underlying problem: Snake would
continue carrying a private partial HUD implementation. Future examples could
copy the same fragile pattern, and Snake would remain a special case.

## Decision

Use **Approach B**.

Add a reusable `orthographic-ui-surface` module under `assets/lua`, migrate Snake
to it, and remove Snake's custom surface. The new module should deliberately be
smaller than `Hud` and unrelated to `Canvas`.

## Architecture

### `assets/lua/orthographic-ui-surface.fnl`

The module exports `create(opts)` and returns a retained surface object with:

- `projection`, `viewport`, `world-units-per-pixel`, `entity`, `layout-root`,
  and `build-context` fields;
- `update-viewport(viewport)` to update viewport state, root layout size, and
  projection;
- `build(builder)` to instantiate one retained root entity with the surface's
  build context;
- `update()` to update the retained entity and layout root;
- `presentation-target()` to return a HUD-like renderer target;
- `drop()` to drop the retained entity.

Projection invariant: world coordinates are lower-left origin and non-inverted:

```fennel
(glm.ortho 0 world-width 0 world-height -100.0 100.0)
```

This keeps text upright and makes higher world Y render higher on screen.

The surface owns exactly one `BuildContext` and one `LayoutRoot`, so text SSBO
entries and widget layout state are retained consistently across frames. The
presentation target exposes exactly one render context: the surface/build
context. It must not depend on product HUD globals, Canvas activity slots, or
main app shell state.

### Snake Migration

Snake app startup changes from requiring `:snake/surface` to requiring
`:orthographic-ui-surface` from shared assets. It creates the surface with the
current viewport and keeps its existing presentation provider:

```fennel
(local surface (OrthographicUiSurface.create {:viewport viewport}))
...
{:presentation {:render-targets (fn [_self] [(surface:presentation-target)])}}
```

Snake view/layout remains responsible for board/text composition. Existing tests
continue to assert:

- non-inverted projection;
- centered/scaled board;
- correct game-up visual direction;
- title/board/status/controls stack order;
- unchanged status sync does not call `Text:set-text`;
- render target exposes the expected presentation contract.

### Documentation

Add a developer feature page explaining when to use `orthographic-ui-surface`:

- use it for examples, simple games, and standalone retained UI surfaces;
- do not use it for full Space product HUD panels;
- do not use it for camera/world/activity-slot rendering, where Canvas is the
  appropriate abstraction.

## Data Flow

1. Snake app starts the engine and initializes shared renderers.
2. Snake creates `OrthographicUiSurface` with the viewport.
3. Snake builds `SnakeScreen` into the surface's `BuildContext`.
4. Game/input events update the model and call `screen:sync` only when needed.
5. Each frame calls `surface:update` and `app.renderers:update`.
6. `Renderers` asks Snake's active runtime for presentation targets and renders
   the orthographic UI target through the standard Space target contract.

## Error Handling and Lifecycle

- Invalid `:world-units-per-pixel` values fail with explicit assertions.
- Missing builders or missing projection state fail explicitly.
- Rebuilding a surface drops the previous entity before attaching the next one.
- `drop()` drops the retained entity and clears it.
- No silent fallbacks for required context or invalid options.

## Testing

Add focused tests for the reusable surface:

- presentation target kind/projection/render-context contract;
- viewport-to-root scaling;
- non-inverted projection;
- invalid world scale rejection;
- old entity drop on rebuild.

Update Snake view tests to import `orthographic-ui-surface` and preserve the
existing layout/stability assertions. Final validation should run compile check,
constraints, focused orthographic surface tests, focused Snake view/game tests,
and relevant broader validation before integration.

Manual acceptance remains important: run Snake on an inspectable graphical
display and verify text does not flicker or overlap during normal play, game
over, and restart.

## Acceptance Criteria

- `examples/snake/assets/lua/snake/surface.fnl` is removed.
- Snake imports `:orthographic-ui-surface` directly.
- The new reusable module has focused test coverage.
- Snake view tests continue to pass and cover projection, layout, stack order,
  game-up direction, and status sync stability.
- Running Snake shows separated, stable title/status/control text with no
  persistent flicker or overlap.
- The developer docs explain when to choose orthographic UI surface, HUD, or
  Canvas.
