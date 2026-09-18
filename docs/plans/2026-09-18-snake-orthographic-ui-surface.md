# Snake Orthographic UI Surface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Snake's one-off custom presentation surface with a reusable Space orthographic UI surface so the example uses supported HUD-style rendering instead of partial custom infrastructure.

**Architecture:** Add `assets/lua/orthographic-ui-surface.fnl` as a minimal retained orthographic presentation target that owns `LayoutRoot`, `BuildContext`, viewport scaling, and the renderer target contract. Migrate Snake to consume that shared module and remove `examples/snake/assets/lua/snake/surface.fnl`. Keep Snake standalone and copyable; do not import the full product HUD or Canvas.

**Tech Stack:** Space Fennel, Space widget/layout engine, `BuildContext`, `LayoutRoot`, `viewport-utils`, `LightingViewState`, `glm.ortho`, Space renderer presentation targets, Space-native Fennel checks/constraints/tests.

## Global Constraints

- Snake should remain a standalone/copyable example under `examples/snake` while allowing it to depend on reusable modules from `assets/lua`.
- Do not import the full main Space product shell into Snake.
- Do not use Canvas for Snake's board/text UI.
- Do not redesign Snake gameplay, scoring, controls, colors, or assets.
- Do not change renderers, shaders, text batching internals, or C++ engine code.
- Do not add generalized HUD panels, focus traversal, click handling, persistence, movable/resizable support, or activity-slot support.
- Projection invariant: world coordinates are lower-left origin and non-inverted: `(glm.ortho 0 world-width 0 world-height -100.0 100.0)`.
- The reusable surface must not depend on product HUD globals, Canvas activity slots, or main app shell state.
- Fennel uses `local`, factory functions, direct multiple-value bindings, and no silent fallbacks.
- Run Space-native validation only: touched-file `tools.fennel-check`, constraints, focused Fennel tests, and broader validation where required.

---

## File Structure

- `assets/lua/orthographic-ui-surface.fnl`: new reusable retained orthographic UI presentation surface.
- `assets/lua/tests/test-orthographic-ui-surface.fnl`: focused tests for the reusable surface contract.
- `examples/snake/assets/lua/snake/app.fnl`: imports and instantiates the shared surface.
- `examples/snake/assets/lua/tests/test-snake-view.fnl`: migrates surface setup assertions from `SnakeSurface` to `OrthographicUiSurface` while preserving Snake layout/stability coverage.
- `examples/snake/assets/lua/snake/surface.fnl`: removed after migration.
- `examples/snake/README.md`: documents that Snake uses the shared orthographic UI surface.
- `docs/dev/features/orthographic-ui-surface.md`: developer documentation for the new primitive.
- `docs/dev/features/index.md`: links the new developer documentation.

---

### Task 1: Reusable Orthographic UI Surface

**Files:**
- Create: `assets/lua/orthographic-ui-surface.fnl`
- Create: `assets/lua/tests/test-orthographic-ui-surface.fnl`

**Interfaces:**
- Consumes: `BuildContext`, `LayoutRoot`, `viewport-utils.to-table`, `LightingViewState.orthographic`, and `glm.ortho`.
- Produces: module table `{:create create}`.
- Produces surface fields: `projection`, `viewport`, `world-units-per-pixel`, `entity`, `layout-root`, `build-context`.
- Produces surface methods:
  - `surface:update-viewport(viewport)` updates viewport state, projection, and root layout size.
  - `surface:build(builder)` builds one retained root entity with the surface build context.
  - `surface:update()` updates the retained entity and layout root.
  - `surface:presentation-target()` returns a HUD-like renderer target.
  - `surface:drop()` drops the retained entity and clears it.

- [ ] **Step 1: Write focused tests before implementation**

  Create `assets/lua/tests/test-orthographic-ui-surface.fnl` with this structure:

  ```fennel
  (local Runner (require :tests/runner))
  (local glm (require :glm))
  (local {: Layout} (require :layout))
  (local OrthographicUiSurface (require :orthographic-ui-surface))
  (local tests [])

  (fn add-test [name test-fn]
    (table.insert tests {:name name :fn test-fn}))

  (fn approx= [a b epsilon]
    (<= (math.abs (- a b)) (if (= epsilon nil) 1e-5 epsilon)))

  (fn assert-approx [actual expected label]
    (assert (approx= actual expected 1e-4)
            (string.format "%s should be %.4f, got %.4f" label expected actual)))

  (fn noop-update [_self]
    nil)

  (fn drop-layout-probe [self]
    (set self.dropped? true)
    (when self.layout
      (self.layout:drop)))

  (fn render-target-probe-builder [_ctx]
    {:layout nil
     :update noop-update
     :drop noop-update})

  (fn layout-probe-builder [_ctx]
    {:layout (Layout {:name "orthographic-ui-surface-probe"})
     :update noop-update
     :drop drop-layout-probe})

  (fn assert-layout-size [layout width height label]
    (assert (= layout.size.x width)
            (string.format "%s width should be %.2f, got %.2f" label width layout.size.x))
    (assert (= layout.size.y height)
            (string.format "%s height should be %.2f, got %.2f" label height layout.size.y)))

  (add-test "orthographic surface exposes hud presentation target"
    (fn []
      (local surface (OrthographicUiSurface.create {:viewport {:x 0 :y 0 :width 640 :height 480}}))
      (local entity (surface:build render-target-probe-builder))
      (assert entity "surface should return built entity")
      (surface:update)
      (local target (surface:presentation-target))
      (assert (= target.kind :hud) "surface should present as hud target")
      (assert target.projection "surface target should expose projection")
      (assert (= (length (target:get-render-contexts)) 1)
              "surface target should expose one render context")
      (surface:drop)))

  (add-test "orthographic surface scales root layout to viewport world units"
    (fn []
      (local surface (OrthographicUiSurface.create {:viewport {:x 0 :y 0 :width 640 :height 480}}))
      (local entity (surface:build layout-probe-builder))
      (assert-layout-size entity.layout 32 24 "default surface root")
      (surface:update-viewport {:x 0 :y 0 :width 800 :height 600})
      (assert-layout-size entity.layout 40 30 "resized surface root")
      (surface:drop)))

  (add-test "orthographic surface projection uses non-inverted y"
    (fn []
      (local surface (OrthographicUiSurface.create {:viewport {:x 0 :y 0 :width 640 :height 480}}))
      (local bottom (* surface.projection (glm.vec4 0 0 0 1)))
      (local top (* surface.projection (glm.vec4 0 24 0 1)))
      (assert (< bottom.y top.y)
              "higher world y should map higher on screen")
      (assert-approx bottom.y -1 "projection bottom y")
      (assert-approx top.y 1 "projection top y")
      (surface:drop)))

  (add-test "orthographic surface rejects invalid world scale"
    (fn []
      (each [_ opts (ipairs [{:world-units-per-pixel false}
                             {:world-units-per-pixel 0}
                             {:world-units-per-pixel -1}])]
        (local (ok err) (pcall OrthographicUiSurface.create opts))
        (assert (not ok) "invalid world scale should fail")
        (assert (string.find (tostring err) "world-units-per-pixel" 1 true)
                "invalid world scale error should name world-units-per-pixel"))))

  (add-test "orthographic surface drops previous entity on rebuild"
    (fn []
      (local surface (OrthographicUiSurface.create {}))
      (local first (surface:build layout-probe-builder))
      (local second (surface:build layout-probe-builder))
      (assert first.dropped? "rebuild should drop previous entity")
      (assert (not (= first second)) "rebuild should attach a new entity")
      (surface:drop)
      (assert second.dropped? "surface drop should drop current entity")))

  (fn main []
    (Runner.run-tests {:name "orthographic-ui-surface" :tests tests}))

  {:main main :tests tests}
  ```

- [ ] **Step 2: Run the focused test to capture RED evidence**

  Run after `make build` if `./build/space` is missing or stale:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-orthographic-ui-surface:main
  ```

  Expected before implementation: FAIL because `orthographic-ui-surface` cannot be required.

- [ ] **Step 3: Implement the reusable surface**

  Create `assets/lua/orthographic-ui-surface.fnl` using these implementation requirements:

  ```fennel
  (local glm (require :glm))
  (local {: LayoutRoot} (require :layout))
  (local BuildContext (require :build-context))
  (local LightingViewState (require :lighting-view-state))
  (local viewport-utils (require :viewport-utils))
  ```

  Required constants:

  ```fennel
  (local identity-view (glm.mat4 1))
  (local default-viewport {:x 0 :y 0 :width 800 :height 600})
  (local default-world-units-per-pixel 0.05)
  ```

  Required behavior:
  - assert `opts` is nil or a table;
  - assert viewport dimensions are numeric when present;
  - assert `:world-units-per-pixel` is a positive number;
  - compute world size from safe viewport dimensions with minimum `1` pixel;
  - set root layout size to world size and position `(glm.vec3 0 0 0)`;
  - set projection to `(glm.ortho 0 world-size.x 0 world-size.y -100.0 100.0)`;
  - create `BuildContext {:layout-root layout-root :quad-unlit? true}`;
  - delegate draw-list methods from `self.build-context`, including text SSBO draw list;
  - `build` drops an existing entity before attaching a new one;
  - `presentation-target` asserts projection exists and returns `:kind :hud` plus identity view and orthographic lighting;
  - `drop` drops current entity and clears it;
  - export `{:create create}`.

- [ ] **Step 4: Run Task 1 validation**

  Compile check:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tools.fennel-check:main -- --target files \
    --file assets/lua/orthographic-ui-surface.fnl \
    --file assets/lua/tests/test-orthographic-ui-surface.fnl
  ```

  Constraints:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m constraints.runner:main -- --target files \
    --file "$(pwd)/assets/lua/orthographic-ui-surface.fnl" \
    --file "$(pwd)/assets/lua/tests/test-orthographic-ui-surface.fnl"
  ```

  Focused test:

  ```bash
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-orthographic-ui-surface:main
  ```

  Expected: PASS.

- [ ] **Step 5: Commit Task 1 after reviewer approval**

  ```bash
  git add assets/lua/orthographic-ui-surface.fnl assets/lua/tests/test-orthographic-ui-surface.fnl
  git commit -m "feat(ui): add orthographic ui surface"
  ```

---

### Task 2: Migrate Snake to the Reusable Surface

**Files:**
- Modify: `examples/snake/assets/lua/snake/app.fnl`
- Modify: `examples/snake/assets/lua/tests/test-snake-view.fnl`
- Modify: `examples/snake/README.md`
- Delete: `examples/snake/assets/lua/snake/surface.fnl`

**Interfaces:**
- Consumes: `OrthographicUiSurface.create(opts)` from `:orthographic-ui-surface`.
- Produces: Snake app runtime using the shared surface with no Snake-specific presentation surface module.

- [ ] **Step 1: Replace the Snake app surface require and construction**

  In `examples/snake/assets/lua/snake/app.fnl`, replace:

  ```fennel
  (local SnakeSurface (require :snake/surface))
  ```

  with:

  ```fennel
  (local OrthographicUiSurface (require :orthographic-ui-surface))
  ```

  Replace surface construction:

  ```fennel
  (local surface (SnakeSurface.create {:viewport viewport}))
  ```

  with:

  ```fennel
  (local surface (OrthographicUiSurface.create {:viewport viewport}))
  ```

- [ ] **Step 2: Migrate Snake view tests**

  In `examples/snake/assets/lua/tests/test-snake-view.fnl`, replace:

  ```fennel
  (local SnakeSurface (require :snake/surface))
  ```

  with:

  ```fennel
  (local OrthographicUiSurface (require :orthographic-ui-surface))
  ```

  Replace every `SnakeSurface.create` with `OrthographicUiSurface.create`.

  Preserve these existing assertions:
  - presentation target kind/projection/render context count;
  - root layout scaling;
  - non-inverted projection;
  - centered/scaled board;
  - title/board/status/controls stack order;
  - game up maps to higher rendered Y;
  - unchanged status sync skips `Text:set-text`;
  - invalid world scale rejection.

  Update assertion text from “snake surface” to “orthographic surface” where that text names the surface module.

- [ ] **Step 3: Delete the custom Snake surface**

  Delete:

  ```text
  examples/snake/assets/lua/snake/surface.fnl
  ```

  Verify there are no remaining references:

  ```bash
  rg "snake/surface|SnakeSurface" examples/snake assets/lua
  ```

  Expected: no matches.

- [ ] **Step 4: Update the Snake README**

  In `examples/snake/README.md`:
  - remove `snake/surface.fnl` from any file layout list;
  - add one sentence: `The graphical presentation uses Space's shared orthographic-ui-surface module from assets/lua for retained HUD-style rendering.`
  - preserve existing run/test commands and copyable example guidance.

- [ ] **Step 5: Run Task 2 validation**

  Compile check:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tools.fennel-check:main -- --target files \
    --file assets/lua/orthographic-ui-surface.fnl \
    --file examples/snake/assets/lua/snake/app.fnl \
    --file examples/snake/assets/lua/tests/test-snake-view.fnl
  ```

  Constraints:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m constraints.runner:main -- --target files \
    --file "$(pwd)/assets/lua/orthographic-ui-surface.fnl" \
    --file "$(pwd)/examples/snake/assets/lua/snake/app.fnl" \
    --file "$(pwd)/examples/snake/assets/lua/tests/test-snake-view.fnl"
  ```

  Focused Snake view test:

  ```bash
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-snake-view:main
  ```

  Expected: PASS.

- [ ] **Step 6: Commit Task 2 after reviewer approval**

  ```bash
  git add examples/snake/assets/lua/snake/app.fnl \
          examples/snake/assets/lua/tests/test-snake-view.fnl \
          examples/snake/README.md
  git rm examples/snake/assets/lua/snake/surface.fnl
  git commit -m "fix(ui): migrate snake to orthographic ui surface"
  ```

---

### Task 3: Documentation and Final Validation

**Files:**
- Create: `docs/dev/features/orthographic-ui-surface.md`
- Modify: `docs/dev/features/index.md`

**Interfaces:**
- Consumes: `OrthographicUiSurface.create(opts)` from Task 1 and Snake migration from Task 2.
- Produces: developer documentation explaining when to use `orthographic-ui-surface` instead of product HUD or Canvas.

- [ ] **Step 1: Create developer docs**

  Create `docs/dev/features/orthographic-ui-surface.md` with this content:

  ```markdown
  # Orthographic UI Surface

  `orthographic-ui-surface` is a small retained presentation surface for
  standalone Space UI examples and simple apps. It owns a `LayoutRoot`, a
  `BuildContext`, viewport-scaled world units, and a HUD-like renderer
  presentation target.

  Use it when an example needs normal Space widgets, text, rectangles, and
  layout without importing the full product HUD shell.

  Do not use it for product HUD panels, command hints, focus/movable/resizable
  registries, activity slots, world cameras, or Canvas rendering.

  ## API

  ```fennel
  (local OrthographicUiSurface (require :orthographic-ui-surface))
  (local surface (OrthographicUiSurface.create {:viewport viewport}))
  (local entity (surface:build builder))
  (surface:update-viewport viewport)
  (surface:update)
  (surface:presentation-target)
  (surface:drop)
  ```

  `builder` receives the surface `BuildContext` and should return a retained
  widget/entity with `:layout`, optional `:update`, and optional `:drop`.

  ## Coordinates

  The surface uses a lower-left origin and non-inverted Y projection:

  ```fennel
  (glm.ortho 0 world-width 0 world-height -100.0 100.0)
  ```

  Higher world Y renders higher on screen. Text remains upright.

  ## Example

  `examples/snake` uses this surface for its board, title, status, and controls
  while remaining a standalone example app.
  ```

- [ ] **Step 2: Link docs index**

  In `docs/dev/features/index.md`, add a bullet or table entry for:

  ```markdown
  - [Orthographic UI Surface](orthographic-ui-surface.md) — standalone retained orthographic UI target for examples and simple apps.
  ```

  Match the surrounding formatting in the index file.

- [ ] **Step 3: Run final validation**

  Runtime freshness:

  ```bash
  make build
  ```

  Use timeout `14400000`.

  Compile check:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tools.fennel-check:main -- --target files \
    --file assets/lua/orthographic-ui-surface.fnl \
    --file assets/lua/tests/test-orthographic-ui-surface.fnl \
    --file examples/snake/assets/lua/snake/app.fnl \
    --file examples/snake/assets/lua/tests/test-snake-view.fnl \
    --file examples/snake/assets/lua/tests/test-snake-game.fnl
  ```

  Constraints:

  ```bash
  make constraints
  ```

  Focused tests:

  ```bash
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-orthographic-ui-surface:main
  ```

  ```bash
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-snake-view:main
  ```

  ```bash
  SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m tests.test-snake-game:main
  ```

  Expected: all pass.

- [ ] **Step 4: Manual acceptance check if a graphical display is available**

  Run outside sandbox if needed:

  ```bash
  SPACE_DISABLE_AUDIO=1 \
  SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" \
  FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
  ./build/space -m main
  ```

  Verify normal play, game over, and restart show title, board, status, and
  controls separated with no persistent text flicker or overlap. If the
  environment is headless, record that manual visual acceptance was not
  available and do not claim it passed.

- [ ] **Step 5: Commit Task 3 after reviewer approval**

  ```bash
  git add docs/dev/features/orthographic-ui-surface.md docs/dev/features/index.md
  git commit -m "docs(ui): document orthographic ui surface"
  ```

---

## Acceptance Criteria

- `examples/snake/assets/lua/snake/surface.fnl` is removed.
- Snake imports `:orthographic-ui-surface` directly.
- The reusable module has focused test coverage.
- Snake view tests cover projection, layout, stack order, game-up direction, and status sync stability.
- Running Snake on an inspectable display shows separated, stable title/status/control text with no persistent flicker or overlap.
- Developer docs explain when to choose orthographic UI surface, HUD, or Canvas.

## Out of Scope

- Canvas integration.
- Full product HUD adoption by Snake.
- Renderer, shader, text batching, or C++ changes.
- Snake gameplay changes or visual redesign beyond removing the custom surface.
