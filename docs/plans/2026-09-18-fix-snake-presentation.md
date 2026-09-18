# Fix Snake Presentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix `examples/snake` so text is upright, the game is centered and scaled to the viewport, repeated unchanged status syncs are stable, and the SDL window title uses `Snake`.

**Architecture:** Keep Snake on the existing Space Fennel UI/rendering path. Change the Snake surface to a non-inverted orthographic projection, make the Snake screen explicitly lay out a centered/scaled board, and pass a canonical engine `:title` option through the C++ Lua binding into `WindowSdl`. Treat the text flicker root cause as unconfirmed; add deterministic stability/idempotence coverage and make Snake status sync avoid unchanged text updates.

**Tech Stack:** Space Fennel widgets/layout (`Layout`, `Rectangle`, `Text`, `BuildContext`, `glm`), C++17 engine/Lua binding (`sol`, `EngineConfig`, `WindowSdl`, SDL3), CMake/CTest, Space-native Fennel checks and constraints.

## Global Constraints

- Use `space-fennel`, `space-fennel-ui`, and `space-testing-runtime` rules.
- Fennel uses `local`, factory functions, direct multiple-value bindings, and no silent fallbacks.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- Direct test runs need `SPACE_DISABLE_AUDIO=1`, `SKIP_KEYRING_TESTS=1`, `XDG_DATA_HOME=/tmp/space/tests/xdg-data`, `SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets`, and example+repo `FENNEL_PATH`/`FENNEL_MACRO_PATH`.
- Build is currently missing; C++/binding changes require `make build` with timeout `14400000`.
- Do not add legacy engine option aliases such as `:window-title`; the canonical option is `:title`.
- If Fennel parse errors occur, inspect the nearest enclosing form, simplify nested forms into helpers, then rerun touched-file `tools.fennel-check` before constraints/tests.

---

## File Structure

- `examples/snake/assets/lua/snake/surface.fnl`: owns Snake’s standalone render surface, root layout sizing, viewport-to-world scale, and projection.
- `examples/snake/assets/lua/snake/view.fnl`: owns Snake board widgets, screen text widgets, layout policy, and model-to-view sync.
- `examples/snake/assets/lua/snake/app.fnl`: owns Snake runtime startup and should pass `:title "Snake"` when creating the engine.
- `examples/snake/assets/lua/tests/test-snake-view.fnl`: focused Fennel tests for surface projection, board centering/scaling, and status sync stability.
- `src/engine.h`, `src/lua_engine.cpp`, `src/engine.cpp`: engine config and Lua option plumbing for the canonical `:title` option.
- `src/window_sdl.h`, `src/window_sdl.cpp`: SDL window title factory and FPS title formatting.
- `CMakeLists.txt`, `tests/test_window_title.cpp`: focused C++ regression coverage for window title formatting/factory defaults.

---

### Task 1: Snake surface projection and viewport-aware layout

**Files:**
- Modify: `examples/snake/assets/lua/snake/surface.fnl`
- Modify: `examples/snake/assets/lua/snake/view.fnl`
- Test: `examples/snake/assets/lua/tests/test-snake-view.fnl`

**Interfaces:**
- Consumes: `SnakeSurface.create(opts)`, `surface:update-viewport(viewport)`, `surface:build(builder)`, `surface:update()`, `SnakeView.SnakeBoard(opts)`, `SnakeView.SnakeScreen(opts)`.
- Produces: `SnakeSurface` with non-inverted projection bounds `(left=0, right=world-width, bottom=0, top=world-height)`; `SnakeBoard {:fit-to-layout? true}` support; `SnakeScreen` that centers/scales its board and skips unchanged status `Text:set-text` calls.

- [ ] **Step 1: Add failing projection/layout/status tests**

  In `examples/snake/assets/lua/tests/test-snake-view.fnl`, add helper functions near the existing helpers:

  ```fennel
  (fn approx= [a b epsilon]
    (<= (math.abs (- a b)) (or epsilon 1e-5)))

  (fn assert-approx [actual expected label]
    (assert (approx= actual expected 1e-4)
            (string.format "%s should be %.4f, got %.4f" label expected actual)))

  (fn assert-centered-x [layout root-width label]
    (local center-x (+ layout.position.x (/ layout.size.x 2)))
    (assert-approx center-x (/ root-width 2) label))
  ```

  Add a projection test:

  ```fennel
  (add-test "snake surface projection uses non-inverted y for upright text"
    (fn []
      (local surface (SnakeSurface.create {:viewport {:x 0 :y 0 :width 640 :height 480}}))
      (local world-height 24)
      (local bottom (* surface.projection (glm.vec4 0 0 0 1)))
      (local top (* surface.projection (glm.vec4 0 world-height 0 1)))
      (assert (< bottom.y top.y)
              "non-inverted projection should map higher world y above lower world y")
      (assert-approx bottom.y -1 "projection bottom y")
      (assert-approx top.y 1 "projection top y")
      (surface:drop)))
  ```

  Add a centered/scaled board test:

  ```fennel
  (add-test "snake screen centers and expands board within viewport"
    (fn []
      (local game (Snake.create {:width 24 :height 16}))
      (local surface (SnakeSurface.create {:viewport {:x 0 :y 0 :width 800 :height 600}}))
      (local screen (surface:build (SnakeView.SnakeScreen {:game game})))
      (surface:update)
      (assert screen.board "SnakeScreen should expose board")
      (assert (> screen.board.layout.position.x 1)
              "board should not be anchored to the left edge")
      (assert (> screen.board.layout.position.y 1)
              "board should not be anchored to the bottom edge")
      (assert (> screen.board.layout.size.x 30)
              "board should use available viewport width")
      (assert (> screen.board.layout.size.y 20)
              "board should use available viewport height")
      (assert-centered-x screen.board.layout 40 "board center x")
      (surface:drop)))
  ```

  Add an unchanged-status stability test:

  ```fennel
  (add-test "snake screen sync skips unchanged status text updates"
    (fn []
      (local game (Snake.create {:width 4 :height 3
                                 :initial-snake [{:x 2 :y 2} {:x 1 :y 2}]
                                 :initial-food {:x 4 :y 3}}))
      (local surface (SnakeSurface.create {:viewport {:x 0 :y 0 :width 800 :height 600}}))
      (local screen (surface:build (SnakeView.SnakeScreen {:game game})))
      (surface:update)
      (local original-set-text screen.status-text.set-text)
      (var set-text-count 0)
      (set screen.status-text.set-text
           (fn [self text opts]
             (set set-text-count (+ set-text-count 1))
             (original-set-text self text opts)))
      (local board-x screen.board.layout.position.x)
      (local board-y screen.board.layout.position.y)
      (local status-x screen.status-text.layout.position.x)
      (local status-y screen.status-text.layout.position.y)
      (screen:sync)
      (surface:update)
      (assert (= set-text-count 0)
              "unchanged status sync should not call Text:set-text")
      (assert-approx screen.board.layout.position.x board-x "stable board x")
      (assert-approx screen.board.layout.position.y board-y "stable board y")
      (assert-approx screen.status-text.layout.position.x status-x "stable status x")
      (assert-approx screen.status-text.layout.position.y status-y "stable status y")
      (surface:drop)))
  ```

- [ ] **Step 2: Run focused Snake view tests and capture RED evidence**

  Ensure runtime exists first:

  ```bash
  make build
  ```

  Use timeout `14400000`. Then run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-snake-view:main
  ```

  Expected before implementation: FAIL on projection and/or board placement/size assertions.

- [ ] **Step 3: Change SnakeSurface projection to non-inverted coordinates**

  In `examples/snake/assets/lua/snake/surface.fnl`, change the `glm.ortho` call in `update-viewport` to:

  ```fennel
  (if glm.ortho
      (set self.projection (glm.ortho 0 world-size.x 0 world-size.y -100.0 100.0))
      (set self.projection identity-view))
  ```

  Keep root layout size based on viewport world size and root position `(glm.vec3 0 0 0)`.

- [ ] **Step 4: Make SnakeBoard optionally fill its assigned layout size**

  In `SnakeBoard`, bind:

  ```fennel
  (local fit-to-layout? (not (not options.fit-to-layout?)))
  ```

  In the board layouter, preserve fixed-size behavior by default, but when `fit-to-layout?` is true, use `self.size` for the board and derive cell dimensions:

  ```fennel
  (local natural-size (glm.vec3 (* game.width cell-size)
                                (* game.height cell-size)
                                cell-size))
  (local board-size (if fit-to-layout?
                        (glm.vec3 self.size.x self.size.y
                                  (math.min (/ self.size.x game.width)
                                            (/ self.size.y game.height)))
                        natural-size))
  (local actual-cell-width (/ board-size.x game.width))
  (local actual-cell-height (/ board-size.y game.height))
  (local actual-cell-depth (math.min actual-cell-width actual-cell-height))
  ```

  Use `actual-cell-width`, `actual-cell-height`, and `actual-cell-depth` for cell positions/sizes, and `board-size` for the background.

- [ ] **Step 5: Replace SnakeScreen fixed Flex/Padding layout with explicit centered layout**

  In `examples/snake/assets/lua/snake/view.fnl`, keep `Rectangle`, `Text`, and `SnakeBoard`, but make `SnakeScreen` own direct children: background, title, board, status, controls. Add constants near existing module constants:

  ```fennel
  (local screen-padding 1.0)
  (local screen-gap 0.4)
  (local minimum-cell-size 0.2)
  ```

  Build the board with:

  ```fennel
  (local board-builder
    (SnakeBoard {:game game
                 :cell-size (or options.cell-size default-cell-size)
                 :fit-to-layout? true}))
  ```

  In the `snake-screen` layouter:
  - Set background `size`, `position`, `rotation`, `depth-offset-index`, and `clip-region` from `self`, then call `background.layout:layouter`.
  - Call text child `:measurer` methods before using `layout.measure`.
  - Compute `available-width = max(1, self.size.x - (* 2 screen-padding))`.
  - Compute `available-height = max(1, self.size.y - title-height - status-height - controls-height - (* 3 screen-gap) - (* 2 screen-padding))`.
  - Compute `next-cell-size = max(minimum-cell-size, min(available-width / game.width, available-height / game.height))`.
  - Compute `board-size = glm.vec3(game.width * next-cell-size, game.height * next-cell-size, next-cell-size)`.
  - Center title, board, status, and controls horizontally with `x = self.position.x + ((self.size.x - child-width) / 2)`.
  - Center the whole stack vertically when there is extra room with `base-y = self.position.y + ((self.size.y - stack-height) / 2)`.
  - Directly assign child layout fields in the layouter; do not call dirtying setters during layout.

- [ ] **Step 6: Make SnakeScreen status syncing idempotent**

  Replace the status update inside `screen:sync` with:

  ```fennel
  (local next-status (status-text game))
  (when (not (= next-status self.status-content))
    (set self.status-content next-status)
    (self.status-text:set-text next-status))
  ```

  Keep `self.board:sync` unconditional.

- [ ] **Step 7: Run Task 1 validation**

  Touched-file compile check:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tools.fennel-check:main -- --target files \
    --file examples/snake/assets/lua/snake/surface.fnl \
    --file examples/snake/assets/lua/snake/view.fnl \
    --file examples/snake/assets/lua/tests/test-snake-view.fnl
  ```

  Constraints:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m constraints.runner:main -- --target files \
    --file "$(pwd)/examples/snake/assets/lua/snake/surface.fnl" \
    --file "$(pwd)/examples/snake/assets/lua/snake/view.fnl" \
    --file "$(pwd)/examples/snake/assets/lua/tests/test-snake-view.fnl"
  ```

  Focused test:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-snake-view:main
  ```

  Expected: all pass.

- [ ] **Step 8: Commit Task 1 after reviewer approval**

  ```bash
  git add examples/snake/assets/lua/snake/surface.fnl \
          examples/snake/assets/lua/snake/view.fnl \
          examples/snake/assets/lua/tests/test-snake-view.fnl
  git commit -m "fix(ui): correct snake surface layout"
  ```

---

### Task 2: Engine window title option and Snake app title

**Files:**
- Modify: `src/engine.h`
- Modify: `src/lua_engine.cpp`
- Modify: `src/engine.cpp`
- Modify: `src/window_sdl.h`
- Modify: `src/window_sdl.cpp`
- Modify: `examples/snake/assets/lua/snake/app.fnl`
- Modify: `CMakeLists.txt`
- Create: `tests/test_window_title.cpp`

**Interfaces:**
- Consumes: existing Fennel engine factory `EngineModule.Engine(options)`.
- Produces: `EngineConfig::title` defaulting to `"space"`; `WindowSdl::create(std::string title = "space")`; `format_window_title_with_fps(const std::string& title, double fps)`; Fennel engine option `:title "Snake"`.

- [ ] **Step 1: Add failing C++ title test**

  Create `tests/test_window_title.cpp`:

  ```cpp
  #include "window_sdl.h"

  #include <cassert>
  #include <memory>
  #include <string>

  int main()
  {
      const std::string formatted = format_window_title_with_fps("Snake", 60.0);
      assert(formatted.rfind("Snake @ fps:", 0) == 0);
      assert(formatted.find("space @ fps:") == std::string::npos);

      std::unique_ptr<WindowSdl> window = WindowSdl::create("Snake");
      assert(window != nullptr);

      return 0;
  }
  ```

  Expected before implementation: compile fails because the formatting function and `WindowSdl::create(std::string)` do not exist.

- [ ] **Step 2: Register the C++ test in CMake**

  In `CMakeLists.txt`, near the other C++ test registrations, add:

  ```cmake
  add_executable(test_window_title
      tests/test_window_title.cpp
  )
  target_include_directories(test_window_title PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
  target_link_libraries(test_window_title ${PROJECT_NAME}_lib)
  add_test(NAME test_window_title COMMAND test_window_title)
  set_tests_properties(test_window_title PROPERTIES
      WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
  )
  ```

- [ ] **Step 3: Run CMake/build enough to capture RED evidence**

  ```bash
  make cmake
  ```

  Use timeout `600000`.

  ```bash
  make build
  ```

  Use timeout `14400000`. Expected: build fails at `tests/test_window_title.cpp` on missing title APIs.

- [ ] **Step 4: Add engine title config and parse `:title`**

  In `src/engine.h`, add to `EngineConfig`:

  ```cpp
  std::string title { "space" };
  ```

  In `src/lua_engine.cpp`, inside `parse_engine_config`, parse the canonical title option:

  ```cpp
  sol::optional<std::string> title = opts["title"];
  if (title) {
      if (title->empty()) {
          throw sol::error("engine.Engine options.title must be a non-empty string");
      }
      config.title = *title;
  }
  ```

- [ ] **Step 5: Thread title through WindowSdl**

  In `src/window_sdl.h`, declare:

  ```cpp
  std::string format_window_title_with_fps(const std::string& title, double fps);
  ```

  Change the factory declaration to:

  ```cpp
  static std::unique_ptr<WindowSdl> create(std::string title = "space");
  ```

  In `src/window_sdl.cpp`, implement:

  ```cpp
  std::string format_window_title_with_fps(const std::string& title, double fps)
  {
      char tmp[128];
  #if __linux__
      snprintf(tmp, sizeof(tmp), "%s @ fps: %.2f", title.c_str(), fps);
  #else
      sprintf_s(tmp, "%s @ fps: %.2f", title.c_str(), fps);
  #endif
      return std::string(tmp);
  }
  ```

  Update `WindowSdl::updateFpsCounter` to call `format_window_title_with_fps(title, fps)` and pass that string to `SDL_SetWindowTitle`.

  Update the factory implementation to:

  ```cpp
  std::unique_ptr<WindowSdl> WindowSdl::create(std::string title)
  {
      return std::make_unique<WindowSdl>(std::move(title));
  }
  ```

  In `src/engine.cpp`, change `window = WindowSdl::create();` to:

  ```cpp
  window = WindowSdl::create(config.title);
  ```

- [ ] **Step 6: Pass the Snake title from the example app**

  In `examples/snake/assets/lua/snake/app.fnl`, change engine creation to:

  ```fennel
  (local engine (EngineModule.Engine {:width 800 :height 600
                                      :title "Snake"}))
  ```

- [ ] **Step 7: Run Task 2 validation**

  ```bash
  make cmake
  ```

  Use timeout `600000`.

  ```bash
  make build
  ```

  Use timeout `14400000`.

  ```bash
  ctest --test-dir build -R '^test_window_title$' --output-on-failure
  ```

  Expected: all pass.

  Then run touched-file Fennel compile check for the app file:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tools.fennel-check:main -- --target files \
    --file examples/snake/assets/lua/snake/app.fnl
  ```

  Expected: PASS.

- [ ] **Step 8: Run focused Snake game tests**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-snake-game:main
  ```

  Expected: PASS.

- [ ] **Step 9: Commit Task 2 after reviewer approval**

  ```bash
  git add src/engine.h src/lua_engine.cpp src/engine.cpp \
          src/window_sdl.h src/window_sdl.cpp \
          examples/snake/assets/lua/snake/app.fnl \
          CMakeLists.txt tests/test_window_title.cpp
  git commit -m "fix(engine): support custom window titles"
  ```

---

### Task 3: Final validation and manual presentation check

**Files:**
- Validate: all files changed by Tasks 1 and 2.

**Interfaces:**
- Consumes: Task 1 and Task 2 outputs.
- Produces: validation evidence that the Snake presentation meets user-observable acceptance criteria and is ready for PR CI.

- [ ] **Step 1: Ensure runtime freshness**

  ```bash
  make build
  ```

  Use timeout `14400000`. Expected: PASS.

- [ ] **Step 2: Run touched-file Fennel compile check**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tools.fennel-check:main -- --target files \
    --file examples/snake/assets/lua/snake/surface.fnl \
    --file examples/snake/assets/lua/snake/view.fnl \
    --file examples/snake/assets/lua/snake/app.fnl \
    --file examples/snake/assets/lua/tests/test-snake-view.fnl \
    --file examples/snake/assets/lua/tests/test-snake-game.fnl
  ```

  Expected: PASS.

- [ ] **Step 3: Run touched-file constraints**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m constraints.runner:main -- --target files \
    --file "$(pwd)/examples/snake/assets/lua/snake/surface.fnl" \
    --file "$(pwd)/examples/snake/assets/lua/snake/view.fnl" \
    --file "$(pwd)/examples/snake/assets/lua/snake/app.fnl" \
    --file "$(pwd)/examples/snake/assets/lua/tests/test-snake-view.fnl" \
    --file "$(pwd)/examples/snake/assets/lua/tests/test-snake-game.fnl"
  ```

  Expected: PASS.

- [ ] **Step 4: Run focused Snake and C++ tests**

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-snake-view:main
  ```

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-snake-game:main
  ```

  ```bash
  ctest --test-dir build -R '^test_window_title$' --output-on-failure
  ```

  Expected: all pass.

- [ ] **Step 5: Run broader local suite because engine/window and UI layout changed**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" make test
  ```

  Expected: PASS.

- [ ] **Step 6: Manual Snake presentation check**

  Run outside sandbox if a graphical display is required:

  ```bash
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m main
  ```

  Expected observable result:
  - all text is upright;
  - board and text stack are centered, not bottom-left anchored;
  - board visibly uses the available window area;
  - window title begins with `Snake @ fps:`;
  - unchanged status text does not visibly jump between positions.

  If text still flickers after these deterministic guards, record exact reproduction evidence and invoke `systematic-debugging`; do not claim the idempotence guard proved the original flicker root cause.

---

## Acceptance Criteria

- Text in `examples/snake` is upright under the Snake surface projection.
- Snake board is centered and not anchored at `(0, 0)` / bottom-left.
- Snake board scales larger than its fixed natural size and uses available viewport space.
- Repeated `SnakeScreen:sync` calls with unchanged status do not call `Text:set-text` and do not change board/status layout positions.
- Snake window title uses `Snake @ fps: ...`; default engine title remains `space` when `:title` is omitted.
- Focused Snake tests, focused C++ title test, relevant Fennel checks/constraints, broader local suite, and PR CI pass.

## Out of Scope

- Snake gameplay rules, controls, scoring, or model data.
- Global `Text:set-text` idempotence outside the Snake example.
- Shader, SSBO batcher, glyph atlas, or renderer pipeline rewrites.
- E2E snapshot golden creation.
- Python prototype changes under `assets/python/`.
- Legacy engine option aliases such as `:window-title`.
