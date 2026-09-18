# Graphical Snake Example Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Snake example's terminal board with a simple graphical 2D Space widget app.

**Architecture:** Keep `snake/game.fnl` as pure model logic. Add a retained Snake view built from Space widgets and a minimal standalone surface that exposes render contexts to Space renderers. `snake/app.fnl` remains the runtime shell for engine startup, input, ticking, syncing, rendering, and shutdown.

**Tech Stack:** Space Fennel, `Rectangle`, `WidgetCuboid`, `Text`, `Layout`, `LayoutRoot`, `BuildContext`, Space `renderers`, Space engine events, focused Fennel tests.

## Global Constraints

- Use Space Fennel validation only; do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- If `./build/space` is missing or stale, run `make build` with `timeout: 14400000` before Fennel validation.
- Compile-check changed `.fnl` files before constraints/tests.
- Run `make constraints` after compile checks and before focused Fennel tests.
- Direct Fennel test commands must set `SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets`.
- Test commands must set `SPACE_DISABLE_AUDIO=1`, `XDG_DATA_HOME=/tmp/space/tests/xdg-data`, and `SKIP_KEYRING_TESTS=1`.
- Keep `examples/snake/` copyable/independent: app-owned code stays under `examples/snake/assets/lua` and may rely on Space-owned reusable modules through the secondary repository `assets` path.
- Preserve `examples/snake/assets/lua/snake/game.fnl` as pure game logic with no engine/UI/rendering dependency.
- `examples/snake/assets/lua/snake/app.fnl` must not terminal-render the board; remove ANSI clear-screen writes and per-frame board `print` output.
- Use Space widgets/rendering for presentation; do not implement raw OpenGL or direct vector batching for Snake cells.
- Fennel style: use `local`, factory functions, explicit assertions for required context, and owned `drop` methods for widgets/layouts.
- Out of scope: high scores, persistence, audio, touch controls, mobile layout, custom art assets, C++ changes, CMake changes, and release workflow changes.

---

## File Structure

- `examples/snake/assets/lua/snake/game.fnl` — remains the pure Snake model. No planned behavioral changes unless tests expose a model bug.
- `examples/snake/assets/lua/snake/view.fnl` — new retained graphical widgets for the board and screen. Owns colors, widget creation, `sync`, and `drop`.
- `examples/snake/assets/lua/snake/surface.fnl` — new minimal render surface. Owns `LayoutRoot`, `BuildContext`, projection/view methods, root entity attachment, layout updates, and presentation target creation.
- `examples/snake/assets/lua/snake/app.fnl` — runtime shell. Removes terminal rendering, creates engine/game/surface/screen, handles keys and ticks, calls sync/layout/renderers update, and drops owned runtime objects.
- `examples/snake/assets/lua/tests/test-snake-view.fnl` — new focused graphical view tests.
- `examples/snake/assets/lua/tests/test-snake-game.fnl` — existing logic/runtime helper tests. Preserve existing assertions and rename local callback variables/messages from render to `on-step` when updating `app.fnl`.
- `examples/snake/README.md` — describe graphical runtime, controls, and validation.
- `docs/dev/features/app-distribution.md` — document that copyable app examples can use Space reusable UI/rendering modules through the secondary assets path.

---

### Task 1: Retained Graphical Snake View

**Files:**
- Create: `examples/snake/assets/lua/snake/view.fnl`
- Create: `examples/snake/assets/lua/tests/test-snake-view.fnl`

**Interfaces:**
- Consumes: `Snake.create(opts) -> game` from `snake/game.fnl`.
- Consumes: game methods/fields `game.width`, `game.height`, `game.score`, `game.game-over?`, and `game:cell-kind(x, y)`.
- Produces: `SnakeView.SnakeBoard(opts) -> build(ctx) -> board` where `opts.game` is required.
- Produces: `board.layout`, `board.cells`, `board:sync() -> nil`, and `board:drop() -> nil`.
- Produces: `SnakeView.SnakeScreen(opts) -> build(ctx) -> screen` where `opts.game` is required.
- Produces: `screen.layout`, `screen.board`, `screen:sync() -> nil`, and `screen:drop() -> nil`.

- [ ] **Step 1: Write the failing board construction test**

  Add `examples/snake/assets/lua/tests/test-snake-view.fnl` with this initial test structure:

  ```fennel
  (local Runner (require :tests/runner))
  (local BuildContext (require :build-context))
  (local Snake (require :snake/game))
  (local SnakeView (require :snake/view))
  (local tests [])

  (fn add-test [name test-fn]
    (table.insert tests {:name name :fn test-fn}))

  (add-test "snake board builds one cell per coordinate"
    (fn []
      (local game (Snake.create {:width 4 :height 3
                                 :initial-snake [{:x 2 :y 2} {:x 1 :y 2}]
                                 :initial-food {:x 4 :y 3}}))
      (local ctx (BuildContext {}))
      (local board ((SnakeView.SnakeBoard {:game game :cell-size 1.0}) ctx))
      (assert board "SnakeBoard should build a board")
      (assert board.layout "SnakeBoard should expose layout")
      (assert (= (length board.cells) 3) "SnakeBoard should create one row per y")
      (assert (= (length (. board.cells 1)) 4) "SnakeBoard should create one cell per x")
      (board:drop)))

  (fn main []
    (Runner.run-tests {:name "snake-view" :tests tests}))

  {:main main :tests tests}
  ```

- [ ] **Step 2: Run the view test to verify it fails**

  Run:

  ```sh
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-view:main
  ```

  Expected: FAIL because `snake/view` does not exist.

- [ ] **Step 3: Implement `SnakeBoard`**

  Create `examples/snake/assets/lua/snake/view.fnl` with these requirements:

  - Require `glm`, `layout`, `rectangle`, `text`, `flex`, `padding`, and `widget-cuboid`.
  - Define local colors for board background, empty cell, snake body, snake head, food, text, and panel background.
  - Build one background `Rectangle` and one cell widget per board coordinate.
  - Store cells as `cells[y][x]` tables with at least `widget` and `kind` fields.
  - Implement `kind-color(kind)` returning colors for `"head"`, `"snake"`, `"food"`, and `"empty"`.
  - Implement `board:sync()` by looping `y=1..game.height`, `x=1..game.width`, reading `(game:cell-kind x y)`, setting the cell widget color, showing non-empty cells, and hiding empty cells.
  - Implement one custom `Layout` named `snake-board` whose children include background layout plus all cell layouts.
  - In the board layouter, assign background position/size/rotation/depth/clip, then assign each cell size/position/rotation/depth/clip directly and call each child layouter.
  - Implement `board:drop()` to drop background, every cell widget, and the board layout.
  - Return exports as `{:SnakeBoard SnakeBoard}` until `SnakeScreen` is added.

- [ ] **Step 4: Run the board construction test to verify it passes**

  Run the same focused command from Step 2.

  Expected: PASS.

- [ ] **Step 5: Add failing sync and screen tests**

  Extend `test-snake-view.fnl` with these tests:

  ```fennel
  (add-test "snake board sync reflects model cell kinds"
    (fn []
      (local game (Snake.create {:width 4 :height 3
                                 :initial-snake [{:x 2 :y 2} {:x 1 :y 2}]
                                 :initial-food {:x 4 :y 3}}))
      (local ctx (BuildContext {}))
      (local board ((SnakeView.SnakeBoard {:game game :cell-size 1.0}) ctx))
      (board:sync)
      (local head-cell (. (. board.cells 2) 2))
      (local body-cell (. (. board.cells 2) 1))
      (local food-cell (. (. board.cells 3) 4))
      (local empty-cell (. (. board.cells 1) 1))
      (assert (= head-cell.kind "head") "head cell should sync")
      (assert (= body-cell.kind "snake") "body cell should sync")
      (assert (= food-cell.kind "food") "food cell should sync")
      (assert (= empty-cell.kind "empty") "empty cell should sync")
      (board:drop)))

  (add-test "snake screen sync updates status text"
    (fn []
      (local game (Snake.create {:width 4 :height 3
                                 :initial-snake [{:x 4 :y 2} {:x 3 :y 2}]
                                 :initial-food {:x 1 :y 1}}))
      (local ctx (BuildContext {}))
      (local screen ((SnakeView.SnakeScreen {:game game}) ctx))
      (assert screen.board "SnakeScreen should own a board")
      (assert screen.status-text "SnakeScreen should expose status text")
      (screen:sync)
      (game:step)
      (screen:sync)
      (assert (string.find screen.status-content "Game Over" 1 true)
              "screen status should show game over")
      (screen:drop)))
  ```

  Run the focused test command. Expected: FAIL until `SnakeScreen` and status sync exist.

- [ ] **Step 6: Implement `SnakeScreen`**

  Extend `snake/view.fnl` with these requirements:

  - `SnakeScreen(opts)` requires `opts.game`.
  - Build a title `Text`, a status `Text`, a controls `Text`, and a `SnakeBoard`.
  - Use `Flex` with `FlexChild` entries and `Padding` to arrange the title, board, status, and controls in a readable vertical panel.
  - Implement `status-text(game)` returning exactly:
    - `Score: <score>\nStatus: Game Over\nPress Space or Enter to restart` when `game.game-over?` is true.
    - `Score: <score>\nStatus: Playing` when `game.game-over?` is false.
  - Implement `screen:sync()` to call `board:sync()`, store the latest status string in `screen.status-content`, and update `status-text` via the Text widget's existing `set-text` method.
  - Implement `screen:drop()` to drop all owned widgets/layouts.
  - Export both `SnakeBoard` and `SnakeScreen`.

- [ ] **Step 7: Run focused view validation**

  Run:

  ```sh
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-view:main
  ```

  Expected: PASS.

---

### Task 2: Standalone Render Surface and Runtime Wiring

**Files:**
- Create: `examples/snake/assets/lua/snake/surface.fnl`
- Modify: `examples/snake/assets/lua/snake/app.fnl`
- Modify: `examples/snake/assets/lua/tests/test-snake-game.fnl`

**Interfaces:**
- Consumes: `SnakeView.SnakeScreen(opts) -> build(ctx) -> screen` from Task 1.
- Produces: `SnakeSurface.create(opts) -> surface`.
- Produces: `surface:build(builder) -> entity`, `surface:update-viewport(viewport) -> nil`, `surface:update() -> nil`, `surface:presentation-target() -> target`, and `surface:drop() -> nil`.
- Preserves: `SnakeApp.test-utils.advance-game(game, delta-ms, elapsed, on-step) -> next-elapsed`.
- Preserves: `SnakeApp.test-utils.delta-ms->seconds(delta-ms) -> seconds`.

- [ ] **Step 1: Write failing surface tests in `test-snake-view.fnl`**

  Add this import:

  ```fennel
  (local SnakeSurface (require :snake/surface))
  ```

  Add this test:

  ```fennel
  (add-test "snake surface exposes render presentation target"
    (fn []
      (local surface (SnakeSurface.create {:viewport {:x 0 :y 0 :width 640 :height 480}}))
      (local entity (surface:build (fn [_ctx]
                                     {:layout nil
                                      :update (fn [_self] nil)
                                      :drop (fn [_self] nil)})))
      (assert entity "surface should return built entity")
      (surface:update)
      (local target (surface:presentation-target))
      (assert target "surface should expose presentation target")
      (assert (= target.kind :hud) "snake surface should render as a HUD-like orthographic target")
      (assert target.projection "surface target should expose projection")
      (assert (= (length (target:get-render-contexts)) 1)
              "surface target should expose one render context")
      (surface:drop)))
  ```

  Run the focused view test command. Expected: FAIL because `snake/surface` does not exist.

- [ ] **Step 2: Implement `snake/surface.fnl`**

  Create `examples/snake/assets/lua/snake/surface.fnl` with these requirements:

  - Require `glm`, `layout`, `build-context`, `lighting-view-state`, and `viewport-utils`.
  - Create `identity-view` as `(glm.mat4 1)`.
  - `create(opts)` accepts optional `:viewport`; default to `{:x 0 :y 0 :width 800 :height 600}`.
  - Construct `LayoutRoot` and `BuildContext {:layout-root layout-root :quad-unlit? true}`.
  - Store `projection`, `viewport`, `entity`, `layout-root`, and `build-context` on the surface.
  - `update-viewport` converts viewport via `viewport-utils.to-table`, computes safe width/height, and sets `projection` using `(glm.ortho 0 safe-width safe-height 0 -100.0 100.0)` when `glm.ortho` exists, otherwise identity.
  - `build(builder)` asserts builder exists, calls builder with the surface build context, stores the entity, and returns it.
  - `update()` calls `entity:update` when present and then `layout-root:update`.
  - Render context methods delegate to `build-context`: `get-triangle-vector`, `get-triangle-batches`, `get-line-vector`, `get-point-vector`, `get-line-strips`, `get-image-batches`, `get-instanced-color-mesh-batches`, `get-quad-draw-list`, and `get-text-ssbo-draw-list`.
  - `get-view-matrix()` returns identity.
  - `get-lighting-view-state()` returns `(LightingViewState.orthographic (glm.vec3 0 0 -1))`.
  - `presentation-target()` returns a table with `:kind :hud`, `:surface self`, `:projection self.projection`, `:get-view-matrix`, `:get-lighting-view-state`, and `:get-render-contexts` returning `[self]`.
  - `drop()` drops the entity when present and clears it.

- [ ] **Step 3: Run surface tests to verify they pass**

  Run:

  ```sh
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-view:main
  ```

  Expected: PASS.

- [ ] **Step 4: Update runtime helper tests before app rewiring**

  In `examples/snake/assets/lua/tests/test-snake-game.fnl`, keep the existing timing tests but rename local callback variables from `render` to `on-step` if the production helper parameter is renamed. Add this assertion inside `runtime-waits-for-150ms-before-step` after the 150ms advance:

  ```fennel
  (assert (= render-count 1) "one accumulated tick should invoke sync callback once")
  ```

  Run the focused game test. Expected: PASS before rewiring if the helper signature still accepts the callback argument.

- [ ] **Step 5: Replace terminal rendering in `snake/app.fnl`**

  Modify `examples/snake/assets/lua/snake/app.fnl` with these requirements:

  - Remove `clear-screen` and the old `render` function.
  - Require `app-bootstrap`, `app-viewport`, `renderers`, `snake/view`, and `snake/surface` through reusable Space modules.
  - Keep key constants and direction mapping.
  - Keep `tick-interval` at `0.15`.
  - Rename the fourth `advance-game` parameter to `on-step` and call it only after at least one game step occurs.
  - In `run`, create `app.engine` with `EngineModule.Engine {:width 800 :height 600}` and assert `engine:start` succeeds.
  - Initialize viewport state from an 800x600 viewport and call renderer viewport update.
  - Initialize themes and renderers with `AppBootstrap.init-themes` and `AppBootstrap.init-renderers`.
  - Create `game`, `surface`, and `screen` by building `(SnakeView.SnakeScreen {:game game})` into the surface.
  - Install `app.active-world-runtime` with `presentation.render-targets` returning `[(surface:presentation-target)]` so `app.renderers:update()` draws the Snake surface.
  - Define `sync-screen` to call `screen:sync`, `surface:update`, and `app.renderers:update`.
  - On accepted direction input, call `game:turn` and then `sync-screen`.
  - On restart input when `game.game-over?`, call `game:restart`, reset elapsed to `0`, and call `sync-screen`.
  - On each update event, call `advance-game game delta elapsed sync-screen`; if no step occurred, still call `surface:update` and `app.renderers:update` so the window refreshes.
  - On shutdown, drop screen/surface/renderers and call `engine:shutdown`.

- [ ] **Step 6: Run focused runtime helper and view tests**

  Run:

  ```sh
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-game:main
  ```

  Then run:

  ```sh
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-view:main
  ```

  Expected: both PASS.

---

### Task 3: Documentation and Validation Ladder

**Files:**
- Modify: `examples/snake/README.md`
- Modify: `docs/dev/features/app-distribution.md`

**Interfaces:**
- Consumes: runtime command `SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m main`.
- Produces: documentation that describes Snake as a graphical widget-based example.

- [ ] **Step 1: Update the Snake README**

  Modify `examples/snake/README.md` so lines describing terminal/text rendering are replaced with:

  ```markdown
  This example is a copyable independent Space/Fennel app template. It demonstrates the app-distribution repository layout, a default `main` entrypoint, pure game logic with focused Fennel tests, a small graphical widget-based runtime, and the release workflow a downstream app repository can call.

  The runtime display is a simple 2D graphical Snake board rendered with Space widgets and rendering systems. The pure game rules stay separate from the view/runtime code so the example remains easy to copy and test.
  ```

  Add controls text under Local development:

  ```markdown
  Controls: arrows/WASD move, Space/Enter restart after game over, and Q/Escape quit.
  ```

- [ ] **Step 2: Update app-distribution developer docs**

  Modify `docs/dev/features/app-distribution.md` under `## Copyable example template` so it says:

  ```markdown
  See `examples/snake/` for a small independent graphical Snake app template that can be copied into a new repository. It demonstrates the expected `assets/lua/main.fnl` default entrypoint, pure app-owned game logic, a small widget/rendering surface that uses Space reusable UI modules through the runtime asset path, focused Fennel tests under the app assets tree, and the small caller workflow needed to invoke Space's reusable bundle workflow.
  ```

- [ ] **Step 3: Run touched-file compile check**

  If `./build/space` is missing, first run:

  ```sh
  make build
  ```

  with `timeout: 14400000`.

  Then run:

  ```sh
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets FENNEL_PATH=$(pwd)/examples/snake/assets/lua/?.fnl\;$(pwd)/examples/snake/assets/lua/?/init.fnl\;$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl FENNEL_MACRO_PATH=$(pwd)/examples/snake/assets/lua/?.fnl\;$(pwd)/examples/snake/assets/lua/?/init.fnl\;$(pwd)/assets/lua/?.fnl\;$(pwd)/assets/lua/?/init.fnl ./build/space -m tools.fennel-check:main -- --target files --file examples/snake/assets/lua/main.fnl --file examples/snake/assets/lua/snake/app.fnl --file examples/snake/assets/lua/snake/game.fnl --file examples/snake/assets/lua/snake/view.fnl --file examples/snake/assets/lua/snake/surface.fnl --file examples/snake/assets/lua/tests/test-snake-game.fnl --file examples/snake/assets/lua/tests/test-snake-view.fnl
  ```

  Expected: PASS.

- [ ] **Step 4: Run constraints**

  Run:

  ```sh
  make constraints
  ```

  Expected: PASS.

- [ ] **Step 5: Run focused Snake tests**

  Run:

  ```sh
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-game:main
  ```

  Then run:

  ```sh
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-view:main
  ```

  Expected: both PASS.

- [ ] **Step 6: Run graphical smoke check**

  Run outside sandbox when graphical display access is available:

  ```sh
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m main
  ```

  Expected: a graphical Snake board appears in the Space window; arrows/WASD move; Space/Enter restarts after game over; Q/Escape quits; the terminal does not redraw an ASCII board.

- [ ] **Step 7: Commit after review, not before**

  The supervisor must commit reviewed implementation changes after the implementer → reviewer loop passes. Use a message such as:

  ```text
  fix(assets): render snake example graphically
  ```

  Include compile, constraints, focused tests, smoke-check status, and constraint-impact note in the commit body.
