# Snake Example Template Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `examples/snake/` as a copyable independent Space/Fennel Snake game template that demonstrates the app-distribution layout and workflow.

**Architecture:** Keep the example independent from Space's default app by placing all app-owned source under `examples/snake/assets/lua`. Split pure Snake rules into `snake/game.fnl`, runtime glue into `snake/app.fnl`, and the Space entrypoint bridge into `main.fnl`; validate the rules with a focused Fennel test and document the template workflow in `examples/snake/README.md`.

**Tech Stack:** Space Fennel, Space `engine` module and `engine-events` signals for runtime glue, existing `tests/runner` for focused Fennel tests, reusable app-distribution workflow caller YAML.

## Global Constraints

- Add `examples/snake/` as a copyable independent Space app template.
- Make the example a small playable Snake game, not just a compile fixture.
- Keep the example independent from Space's default `assets/lua/main.fnl`, HUD, graph, LLM, wallet, and other default-app modules.
- Demonstrate the app repository layout expected by the reusable bundle workflow.
- Include documentation for local development, copying the template into a new repository, and publishing releases through Space's reusable workflow.
- Validate the example with Space-native Fennel checks, constraints, and a focused logic test.
- Do not redesign Space runtime asset lookup, CLI entrypoint behavior, or the app-distribution workflow.
- Do not move the existing default `main` app out of Space.
- Do not add packaging functionality beyond showing the caller workflow a copied app would use.
- Do not introduce heavy UI/game abstractions for this one example.
- Do not depend on system `fennel`, system `lua`, `fnlfmt`, or `fennel-ls` for validation.
- Use Fennel project idioms: `local` instead of `let`, factory functions instead of `.new`, and no default-app global `app` dependency in `snake/game.fnl`.

---

### Task 1: Pure Snake Game Logic and Focused Test

**Files:**
- Create: `examples/snake/assets/lua/snake/game.fnl`
- Create: `examples/snake/assets/lua/tests/test-snake-game.fnl`

**Interfaces:**
- Produces module `snake/game` with:
  - `directions`: table containing `:up`, `:down`, `:left`, `:right` direction vectors.
  - `create(opts) -> game`: factory. `opts` supports `:width`, `:height`, `:initial-snake`, `:initial-direction`, `:initial-food`, and `:food-sequence` for deterministic tests.
  - `game:turn(direction-name) -> boolean`: accepts `:up|:down|:left|:right`, rejects direct reversal, returns whether the direction changed.
  - `game:step() -> table`: advances one tick and returns an event table with `:status` (`:moved`, `:ate`, `:wall-hit`, `:self-hit`) and current `:score`.
  - `game:restart() -> nil`: resets to a fresh initial state.
  - `game:cell-kind(x y) -> string`: returns `"snake"`, `"head"`, `"food"`, or `"empty"`.
  - `game:board-lines() -> table`: returns text rows for README/runtime display.
  - Readable game fields: `width`, `height`, `score`, `game-over?`, `direction`, `snake`, `food`.
- Produces test module `tests/test-snake-game` with `:main` using `tests/runner`.

- [ ] **Step 1: Write focused game tests first**
  - Create `examples/snake/assets/lua/tests/test-snake-game.fnl` using this structure:

    ```fennel
    (local Runner (require :tests/runner))
    (local Snake (require :snake/game))
    (local tests [])

    (fn add-test [name fn]
      (table.insert tests {:name name :fn fn}))

    (add-test "moves-right-by-default"
      (fn []
        (local game (Snake.create {:width 8 :height 6
                                   :initial-snake [{:x 3 :y 3} {:x 2 :y 3}]
                                   :initial-food {:x 6 :y 3}}))
        (local event (game:step))
        (local head (. game.snake 1))
        (assert (= event.status :moved) "first step should move")
        (assert (= head.x 4) "head x should advance right")
        (assert (= head.y 3) "head y should stay constant")))

    (add-test "rejects-direct-reversal"
      (fn []
        (local game (Snake.create {:width 8 :height 6
                                   :initial-snake [{:x 3 :y 3} {:x 2 :y 3}]
                                   :initial-food {:x 6 :y 3}}))
        (assert (= (game:turn :left) false) "right-moving snake cannot reverse left")
        (assert (= game.direction :right) "direction should remain right")
        (assert (= (game:turn :up) true) "perpendicular turn should be accepted")
        (assert (= game.direction :up) "direction should change to up")))

    (add-test "eats-food-and-grows"
      (fn []
        (local game (Snake.create {:width 8 :height 6
                                   :initial-snake [{:x 3 :y 3} {:x 2 :y 3}]
                                   :initial-food {:x 4 :y 3}
                                   :food-sequence [{:x 1 :y 1}]}))
        (local event (game:step))
        (assert (= event.status :ate) "step into food should eat")
        (assert (= game.score 1) "score should increment")
        (assert (= (length game.snake) 3) "snake should grow by one")
        (assert (= game.food.x 1) "next deterministic food x should be used")
        (assert (= game.food.y 1) "next deterministic food y should be used")))

    (add-test "detects-wall-hit"
      (fn []
        (local game (Snake.create {:width 5 :height 5
                                   :initial-snake [{:x 5 :y 3} {:x 4 :y 3}]
                                   :initial-food {:x 1 :y 1}}))
        (local event (game:step))
        (assert (= event.status :wall-hit) "moving beyond width should hit wall")
        (assert game.game-over? "wall hit should end game")))

    (add-test "detects-self-hit"
      (fn []
        (local game (Snake.create {:width 8 :height 8
                                   :initial-snake [{:x 4 :y 4} {:x 4 :y 5} {:x 3 :y 5} {:x 3 :y 4} {:x 3 :y 3}]
                                   :initial-direction :up
                                   :initial-food {:x 8 :y 8}}))
        (game:turn :left)
        (local event (game:step))
        (assert (= event.status :self-hit) "head should collide with body")
        (assert game.game-over? "self hit should end game")))

    (fn main []
      (Runner.run-tests {:name "snake-game" :tests tests}))

    {:main main}
    ```

- [ ] **Step 2: Run focused test to verify RED**
  - Run:
    `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-game:main`
  - Expected: FAIL because `snake/game` does not exist yet.

- [ ] **Step 3: Implement pure game logic**
  - Create `examples/snake/assets/lua/snake/game.fnl` with a `create` factory returning a final `self` table containing fields and methods.
  - Use 1-indexed `x`/`y` grid coordinates.
  - Default board: width `24`, height `16`, initial snake centered horizontally, initial direction `:right`.
  - Default food placement: scan row-major for the first empty cell when no deterministic food is supplied; use `food-sequence` before scan placement when provided.
  - `turn` must reject the opposite direction of the current direction.
  - `step` must no-op with status `:game-over` if `game-over?` is already true.
  - `board-lines` should return strings using `#` for walls, `@` for the head, `o` for body, `*` for food, and spaces for empty cells.

- [ ] **Step 4: Run compile and focused test GREEN**
  - Compile check first:
    `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file examples/snake/assets/lua/snake/game.fnl --file examples/snake/assets/lua/tests/test-snake-game.fnl`
  - Focused test:
    `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-game:main`
  - Expected: both PASS.

- [ ] **Step 5: Commit Task 1**
  - `git add examples/snake/assets/lua/snake/game.fnl examples/snake/assets/lua/tests/test-snake-game.fnl`
  - `git commit -m "feat(assets): add snake example game logic"`

---

### Task 2: Snake Runtime Template, Workflow, and Documentation

**Files:**
- Create: `examples/snake/assets/lua/main.fnl`
- Create: `examples/snake/assets/lua/snake/app.fnl`
- Create: `examples/snake/.github/workflows/release.yml`
- Create: `examples/snake/README.md`
- Modify: `docs/dev/features/app-distribution.md`

**Interfaces:**
- Consumes Task 1 `Snake.create(opts)` and `game:board-lines()`.
- Produces a runnable example with default `entrypoint: main` and a README that explains copying the directory into a new repo.
- `main.fnl` exports `{:main main}` and calls `main` only when `app-config.run-main` is true.

- [ ] **Step 1: Create the entrypoint bridge**
  - `examples/snake/assets/lua/main.fnl` should:
    - require `:app-config`;
    - require `:snake/app`;
    - define `(fn main [] (SnakeApp.run))`;
    - call `(main)` only when `AppConfig.run-main` is true;
    - return `{:main main}`.

- [ ] **Step 2: Create minimal runtime shell**
  - `examples/snake/assets/lua/snake/app.fnl` should:
    - require `:engine` and `:snake/game`;
    - define `run` that creates `(EngineModule.Engine {:width 800 :height 600})`;
    - store the engine in `app.engine` only for compatibility with low-level modules, without requiring Space's default `:main`;
    - create a `Snake.create {}` game;
    - connect `engine.events.key-down` to support arrow keys, WASD, Escape/Q quit, and Space/Enter restart after game over;
    - connect `engine.events.engine-tick` or `engine.events.updated` to advance at a fixed interval such as `0.15` seconds;
    - print `game:board-lines()` and score to stdout after each tick using simple ANSI clear-screen text output;
    - start and run the engine, then shutdown on return if needed.
  - Keep rendering intentionally text-based in the template README because a minimal standalone graphical render stack is outside this example's scope.

- [ ] **Step 3: Add illustrative release workflow**
  - Create `examples/snake/.github/workflows/release.yml`:

    ```yaml
    name: Release

    on:
      push:
        tags:
          - "v*"

    permissions:
      contents: write

    jobs:
      bundle:
        uses: semanticdreams/space2/.github/workflows/bundle.yml@v1
        with:
          space-version: v1.2.3
          app-name: Snake
          app-id: snake
    ```

  - The README must state that `space-version` and the workflow ref are placeholders to pin deliberately in a copied repository.

- [ ] **Step 4: Add README template documentation**
  - `examples/snake/README.md` must include:
    - what the example demonstrates;
    - directory layout;
    - local run from the copied app root: `space -m main`;
    - local run from the Space repository root: `SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" ./build/space -m main`;
    - focused test command: `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-game:main`;
    - copy instructions for a new repo, preserving `assets/` and `.github/workflows/release.yml`;
    - note that the runtime display is intentionally terminal/text based to avoid default-app rendering dependencies.

- [ ] **Step 5: Link the example from app-distribution docs**
  - Add a short section to `docs/dev/features/app-distribution.md` pointing to `examples/snake/` as a copyable template.
  - State that it demonstrates `assets/lua/main.fnl`, a focused Fennel logic test, and the small caller workflow.

- [ ] **Step 6: Run validation ladder**
  - If `./build/space` is missing or stale, run `make build` with timeout `14400000`.
  - Compile check first:
    `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file examples/snake/assets/lua/main.fnl --file examples/snake/assets/lua/snake/app.fnl --file examples/snake/assets/lua/snake/game.fnl --file examples/snake/assets/lua/tests/test-snake-game.fnl`
  - Constraints second:
    `make constraints`
  - Focused test third:
    `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-game:main`
  - Metadata smoke:
    `python3 scripts/normalize-app-metadata.py --repo-root examples/snake --space-version v1.2.3 --app-name Snake --release-version 0.1.0 --output /tmp/snake-example-metadata.json`
  - Documentation/static check:
    `python3 -m pytest scripts/tests/test_bundle_workflow.py scripts/tests/test_release_artifact_naming.py`

- [ ] **Step 7: Commit Task 2**
  - `git add examples/snake/assets/lua/main.fnl examples/snake/assets/lua/snake/app.fnl examples/snake/.github/workflows/release.yml examples/snake/README.md docs/dev/features/app-distribution.md`
  - `git commit -m "docs(assets): add snake app template example"`
