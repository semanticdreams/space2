# Graphical Snake Example Design

## Context

The current `examples/snake` app launches a Space engine window, but its Snake
presentation is terminal-based. `snake/app.fnl` clears stdout and prints
`game:board-lines`; it never builds a Space widget tree or registers a graphical
render target. As a result, the window remains at the engine's cleared/default
background while the playable board appears in the terminal.

The example should instead demonstrate a small, copyable, graphical Space app: a
simple 2D Snake game built with Space's Fennel UI/rendering primitives while
keeping game rules testable and separate from runtime/rendering glue.

## Goals

- Replace terminal board rendering with a graphical Snake board in the Space
  window.
- Use Space widgets/rendering systems for presentation: retained widgets,
  layouts, rectangles/cuboids, text, build context, and renderers.
- Preserve the existing controls: arrows/WASD to move, Space/Enter to restart
  after game over, and Q/Escape to quit.
- Preserve `snake/game.fnl` as pure game logic with no engine/UI dependencies.
- Keep the example copyable as an independent app under `examples/snake/assets`.
- Add focused view/runtime test coverage for graphical construction and sync
  behavior.
- Update docs so the example is described as graphical, not intentionally
  terminal/text based.

## Non-goals

- Do not add high scores, persistence, networking, audio, custom sprites, mobile
  controls, or new external assets.
- Do not redesign Space's default app shell, asset lookup, or release workflow.
- Do not change C++, CMake, renderer internals, or shared widget implementation
  unless implementation proves the example cannot be built with existing APIs.
- Do not import the repository's default `assets/lua/main.fnl` application as the
  example runtime shell.

## Considered approaches

### Approach A: Full default Space app integration

The Snake game could be implemented like Tetris, as a `DeepDialog`/launchable
inside the default Space app shell. This would reuse mature HUD, focus, dialog,
and presentation plumbing and would make the result visually polished.

Trade-off: it would no longer be a minimal copyable independent app template. It
would also teach new app authors to depend on the full default Space product
shell rather than the smaller reusable UI/rendering layer.

### Approach B: Raw quad rendering

The app could draw the board directly through raw rectangle/quad batchers without
building widgets or layouts. This is technically direct and would avoid some UI
surface setup.

Trade-off: it bypasses the widget/lifecycle patterns the example is supposed to
demonstrate, and it risks becoming a bespoke renderer rather than a Space app
example.

### Approach C: Standalone retained widget surface

Keep the example's independent runtime shell, but add a small Snake-specific
view layer built from Space widgets. The view prebuilds board cell widgets,
syncs their color/visibility from `snake/game.fnl`, and renders through a
minimal presentation surface owned by the example runtime.

Trade-off: this requires a little presentation-surface wiring in the example,
but it keeps the app copyable and demonstrates the reusable Space UI/rendering
path without importing the full default app shell.

## Decision

Use Approach C.

The graphical Snake app will consist of three layers:

1. **Pure model** — `snake/game.fnl` remains responsible only for grid state,
   movement, food, scoring, restart, and collision rules.
2. **Graphical view** — a new `snake/view.fnl` builds retained widgets for the
   board, cells, score/status, and controls text. It reads model state and
   exposes idempotent `sync`/`drop` methods, but it never advances the game.
3. **Standalone runtime surface** — `snake/app.fnl` owns the engine loop, input,
   ticking, and shutdown. A small `snake/surface.fnl` module owns
   `BuildContext`, layout root/projection, and render-target accessors so Space
   renderers can draw the Snake widgets in the app window.

## User experience

Running the documented command should open a graphical Snake window. The board
should be simple but intentionally visual: dark board/panel background, colored
snake body, distinct snake head, red food, score/status text, and visible control
instructions. The terminal should no longer redraw the board every tick.

On game over, the graphical status text should indicate that the round ended and
that Space/Enter restarts. Restart should refresh the graphical board and score.
Quit keys should still close the app.

## Components and data flow

- `Snake.create(opts)` produces game state.
- `SnakeView.SnakeBoard {:game game}` builds board widgets and exposes
  `board:sync()` to read `game:cell-kind x y` and update cell visibility/color.
- `SnakeView.SnakeScreen {:game game}` wraps the board with score/status/control
  text and exposes `screen:sync()`.
- `SnakeApp.run` creates the engine, game, graphical screen, and render surface.
- Engine key events mutate game direction/restart/quit state, then call
  `screen:sync()` when the presentation should change.
- Engine update events accumulate frame delta, call `game:step` at the fixed
  Snake tick interval, sync the screen after game steps, update layout, then
  call Space renderers.

## Error handling and lifecycle

- Required context, game, layout root, and renderer pieces should be asserted
  with explicit messages rather than silently skipped.
- View objects own and drop their widgets/layouts.
- Runtime shutdown drops the screen/surface/renderers before shutting down the
  engine.
- Double-drop may assert; silent cleanup fallbacks are not required.

## Testing and validation

Focused tests should cover:

- Existing pure game behavior remains unchanged.
- `SnakeBoard` builds one cell widget per board coordinate.
- `SnakeBoard:sync()` reflects head/body/food/empty cells without stepping the
  game.
- `SnakeScreen:sync()` updates score/status text after state changes.
- Runtime tick helper behavior remains compatible with the existing 150ms tick
  tests.

Validation order:

1. Run `make build` first if `./build/space` is missing or stale.
2. Run touched-file `tools.fennel-check` for changed Snake `.fnl` files with
   both example and repository asset paths.
3. Run `make constraints`.
4. Run focused Snake tests, including the existing game test and new view test.
5. Run a runtime smoke check of `examples/snake` to verify a graphical board is
   visible and terminal board redraws are gone.

## Acceptance criteria

- `SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" ./build/space -m main`
  opens a graphical Snake board rather than a blue-only window.
- The terminal no longer displays the board as the primary game presentation.
- Movement, restart, game-over, score, and quit behavior still work.
- The implementation uses Space Fennel widgets/layout/rendering rather than a
  bespoke CLI or raw OpenGL renderer.
- Documentation describes the example as a graphical widget-based Space app.
- Focused compile, constraints, and Snake tests pass.
