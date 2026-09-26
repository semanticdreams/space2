# 3D Snake Scene View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a first 3D Snake slice by mirroring the existing Snake game state into `host.scene` app-owned scene objects while preserving the current 2D UI and hostable runtime contract.

**Architecture:** Keep pure Snake game logic unchanged. Add a focused `snake/scene-view.fnl` adapter that consumes a `host.scene` capability and the existing game object, owns Snake scene handles, and synchronizes head/body/food cells into embedded-compatible `:custom` object spawns. Wire `snake.app` to require `host.scene`, sync the scene view with the existing screen sync path, and drop scene handles during runtime teardown.

**Tech Stack:** Space Fennel, `host.scene`, Snake example runtime, Cuboid/Rectangle/Sized scene builders, focused Fennel tests, `tools.fennel-check`, `make constraints`.

## Global Constraints

- Add a first 3D Snake slice using `host.scene`.
- Preserve the existing 2D Snake UI and controls.
- Keep Snake game logic host-independent and reusable.
- Require scene access through `Capabilities.require host :scene`.
- Mirror Snake cells into app-owned scene handles with semantic tags.
- Use embedded-compatible scene spawns: concrete objects for `:custom`/`:cube`, not registry-only fake handles.
- Clean up all Snake-owned scene handles on runtime drop.
- Test scene synchronization independently and through hosted runtime creation.
- Do not add a new hosted app entrypoint or Snake-specific host API.
- Do not branch app behavior on hosted-vs-standalone mode.
- Do not remove the current orthographic Snake UI surface.
- Do not add camera controls, scene persistence, terrain/raycast gameplay, physics integration, or moldable inspectors in this slice.
- Do not change the generic `host.scene` API unless tests reveal a capability bug that must be fixed for this app.
- Board/base and boundary markers are not required for this first slice.
- `snake.scene-view:drop()` must not call `host.scene:drop()`.
- Use `local` instead of `let` in Fennel.
- Use factory functions instead of `.new` constructors.
- For Fennel work, compile-check first with project-native `tools.fennel-check`/`make fennel-check`, then run `make constraints`, then focused Fennel tests.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- For direct test runs, set `SKIP_KEYRING_TESTS=1`, `XDG_DATA_HOME=/tmp/space/tests/xdg-data`, `SPACE_DISABLE_AUDIO=1`, `SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets`, `FENNEL_PATH=$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl`, and the same value for `FENNEL_MACRO_PATH`.

---

## File Structure

- `examples/snake/assets/lua/snake/scene-view.fnl`: new scene synchronization module. Owns Snake scene handles, creates concrete cuboid-like scene objects, syncs game cells to `host.scene`, and despawns owned handles.
- `examples/snake/assets/lua/snake/app.fnl`: require `host.scene`, instantiate scene view, sync scene view wherever the 2D screen syncs, and drop scene view during runtime teardown.
- `examples/snake/assets/lua/tests/test-snake-scene-view.fnl`: focused unit tests for scene-view spawn specs, diffing, transform updates, and teardown.
- `examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl`: update fake hosts with a scene capability, assert runtime scene handles are created/dropped, and assert missing scene fails loudly.
- `examples/snake/assets/lua/tests/test-snake-standalone-entry.fnl`: keep hostable entrypoint coverage; add no scene-specific branching assertions unless runtime wiring requires it.
- `examples/snake/README.md`: document the 3D scene mirror and new focused test command.
- `docs/dev/features/hosted-runtime-apps.md`: update the 3D Snake note now that this first scene-capability consumer exists.

---

### Task 1: Snake Scene View Module

**Files:**
- Create: `examples/snake/assets/lua/snake/scene-view.fnl`
- Create: `examples/snake/assets/lua/tests/test-snake-scene-view.fnl`

**Interfaces:**
- Consumes: `Snake.create(opts) -> game` from `examples/snake/assets/lua/snake/game.fnl`.
- Consumes: `scene` capability with `spawn`, `despawn`, `set-transform`, `list-owned` methods.
- Produces: `SceneView.create(opts: table) -> scene-view`.
- `opts` shape: `{:scene scene-capability :game snake-game :cell-size number|nil :origin table|nil}`.
- `scene-view` methods: `sync(self) -> true`, `drop(self) -> nil`.

- [ ] **Step 1: Write fake scene test scaffolding**

Create `examples/snake/assets/lua/tests/test-snake-scene-view.fnl` with a fake scene that records spawn/despawn/set-transform calls and rejects embedded-incompatible custom spawns:

```fennel
(local Runner (require :tests/runner))
(local Snake (require :snake/game))
(local SceneView (require :snake/scene-view))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn make-fake-scene []
  (local state {:spawns [] :despawns [] :transforms [] :owned []})
  (local scene {})
  (set scene.spawn
       (fn [_self spec]
         (assert (= spec.kind :custom) "Snake scene cells should use embedded-compatible custom objects")
         (assert spec.object "Snake custom scene cells must include a concrete object")
         (assert spec.position "Snake scene cells must include a position")
         (assert spec.size "Snake scene cells must include a size")
         (local handle {:id spec.id :kind spec.kind :tags spec.tags :spec spec})
         (table.insert state.spawns spec)
         (table.insert state.owned handle)
         handle))
  (set scene.despawn
       (fn [_self handle]
         (table.insert state.despawns handle)
         (for [i (# state.owned) 1 -1]
           (when (= (. state.owned i) handle)
             (table.remove state.owned i)))
         true))
  (set scene.set-transform
       (fn [_self handle transform]
         (table.insert state.transforms {:handle handle :transform transform})
         transform))
  (set scene.list-owned
       (fn [_self]
         (local out [])
         (each [_ handle (ipairs state.owned)]
           (table.insert out handle))
         out))
  (values scene state))

(fn main []
  (Runner.run-tests {:name "snake-scene-view" :tests tests}))

{:main main :tests tests}
```

- [ ] **Step 2: Add failing initial sync test**

Add this test to the same file:

```fennel
(fn has-tag? [tags expected]
  (var found? false)
  (each [_ tag (ipairs (or tags []))]
    (when (= tag expected)
      (set found? true)))
  found?)

(fn find-spawn-with-tag [spawns tag]
  (var found nil)
  (each [_ spec (ipairs spawns)]
    (when (and (not found) (has-tag? spec.tags tag))
      (set found spec)))
  found)

(fn test-initial-sync-spawns-head-body-and-food []
  (local (scene state) (make-fake-scene))
  (local game (Snake.create {:width 8 :height 6
                             :initial-snake [{:x 3 :y 3} {:x 2 :y 3}]
                             :initial-food {:x 6 :y 3}}))
  (local view (SceneView.create {:scene scene :game game}))
  (view:sync)
  (assert (= (# state.spawns) 3) "initial sync should spawn head, body, and food")
  (assert (find-spawn-with-tag state.spawns :head) "initial sync should tag a head")
  (assert (find-spawn-with-tag state.spawns :body) "initial sync should tag a body")
  (assert (find-spawn-with-tag state.spawns :food) "initial sync should tag food")
  (view:drop))

(add-test "initial sync spawns head body and food" test-initial-sync-spawns-head-body-and-food)
```

Run and expect failure because `snake/scene-view` does not exist:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snake-scene-view:main
```

- [ ] **Step 3: Add failing sync diff and drop tests**

Add these tests:

```fennel
(fn test-sync-reuses-existing-cell_handles_and_despawns_obsolete_cells []
  (local (scene state) (make-fake-scene))
  (local game (Snake.create {:width 8 :height 6
                             :initial-snake [{:x 3 :y 3} {:x 2 :y 3}]
                             :initial-food {:x 6 :y 3}}))
  (local view (SceneView.create {:scene scene :game game}))
  (view:sync)
  (local first-spawn-count (# state.spawns))
  (game:step)
  (view:sync)
  (assert (> (# state.spawns) first-spawn-count) "moving should spawn new visible cells")
  (assert (> (# state.despawns) 0) "moving should despawn obsolete cells")
  (assert (= (# state.owned) 3) "owned visible cells should remain head body food")
  (view:drop))

(fn test-drop-is-idempotent-and_despawns_owned_handles_once []
  (local (scene state) (make-fake-scene))
  (local game (Snake.create {:width 8 :height 6
                             :initial-snake [{:x 3 :y 3} {:x 2 :y 3}]
                             :initial-food {:x 6 :y 3}}))
  (local view (SceneView.create {:scene scene :game game}))
  (view:sync)
  (view:drop)
  (view:drop)
  (assert (= (# state.despawns) 3) "drop should despawn each scene cell once")
  (assert (= (# state.owned) 0) "drop should leave no Snake-owned scene handles"))

(add-test "sync reuses and despawns cells" test-sync-reuses-existing-cell_handles_and_despawns_obsolete_cells)
(add-test "drop despawns owned handles once" test-drop-is-idempotent-and_despawns_owned_handles_once)
```

- [ ] **Step 4: Implement scene-view helpers**

Create `examples/snake/assets/lua/snake/scene-view.fnl`. Implement these helpers:

```fennel
(local glm (require :glm))
(local Cuboid (require :cuboid))
(local Rectangle (require :rectangle))
(local Sized (require :sized))

(fn scene-view-error [message]
  (error (.. "[snake.scene-view] " message)))

(fn require-method [service method]
  (local value (. service method))
  (when (not (= (type value) :function))
    (scene-view-error (.. "scene missing method: " (tostring method))))
  value)

(fn color-for-role [role]
  (if (= role :head)
      (glm.vec4 0.2 1.0 0.25 1.0)
      (= role :body)
      (glm.vec4 0.1 0.55 0.15 1.0)
      (= role :food)
      (glm.vec4 1.0 0.15 0.1 1.0)
      (glm.vec4 1.0 1.0 1.0 1.0)))

(fn make-cuboid-builder [role]
  (local color (color-for-role role))
  (Sized {:size (glm.vec3 1 1 1)
          :child (Cuboid {:children [(Rectangle {:color color})
                                     (Rectangle {:color color})
                                     (Rectangle {:color color})
                                     (Rectangle {:color color})
                                     (Rectangle {:color color})
                                     (Rectangle {:color color})]})}))

(fn make-scene-object [role]
  (local object {})
  (set object.scene-object-options
       (fn [_self]
         {:builder (make-cuboid-builder role)
          :skip-cuboid true
          :skip-physics true}))
  object)
```

- [ ] **Step 5: Implement coordinate mapping and cell collection**

Continue in `scene-view.fnl`:

```fennel
(fn option-number [value fallback label]
  (if (= value nil)
      fallback
      (if (= (type value) :number)
          value
          (scene-view-error (.. label " must be a number")))))

(fn origin-vector [origin]
  (if origin
      [(or (. origin 1) 0) (or (. origin 2) 0) (or (. origin 3) 0)]
      [0 0 0]))

(fn cell-key [role x y index]
  (if (= role :body)
      (.. "body-" (tostring index) "-" (tostring x) "-" (tostring y))
      (.. (tostring role) "-" (tostring x) "-" (tostring y))))

(fn cell-position [game origin cell-size cell]
  [ (+ (. origin 1) (* (- cell.x (/ (+ game.width 1) 2)) cell-size))
    (+ (. origin 2) (/ cell-size 2))
    (+ (. origin 3) (* (- cell.y (/ (+ game.height 1) 2)) cell-size)) ])

(fn cell-size-vector [cell-size]
  [cell-size cell-size cell-size])

(fn collect-cells [game origin cell-size]
  (local cells [])
  (each [index segment (ipairs game.snake)]
    (local role (if (= index 1) :head :body))
    (table.insert cells {:key (cell-key role segment.x segment.y index)
                         :role role
                         :x segment.x
                         :y segment.y
                         :position (cell-position game origin cell-size segment)
                         :size (cell-size-vector cell-size)}))
  (when game.food
    (table.insert cells {:key (cell-key :food game.food.x game.food.y 1)
                         :role :food
                         :x game.food.x
                         :y game.food.y
                         :position (cell-position game origin cell-size game.food)
                         :size (cell-size-vector cell-size)}))
  cells)
```

- [ ] **Step 6: Implement `create`, `sync`, and `drop`**

Finish `scene-view.fnl`:

```fennel
(fn make-spawn-spec [cell]
  {:kind :custom
   :id cell.key
   :tags [:snake cell.role]
   :position cell.position
   :size cell.size
   :object (make-scene-object cell.role)
   :solid? true})

(fn create [opts]
  (when (not (= (type opts) :table))
    (scene-view-error "create requires opts table"))
  (local scene (or opts.scene (scene-view-error "create requires :scene")))
  (local game (or opts.game (scene-view-error "create requires :game")))
  (require-method scene :spawn)
  (require-method scene :despawn)
  (require-method scene :set-transform)
  (local cell-size (option-number opts.cell-size 1 "cell-size"))
  (local origin (origin-vector opts.origin))
  (local handles-by-key {})
  (var dropped? false)

  (fn despawn-key [key]
    (local entry (. handles-by-key key))
    (when entry
      (scene:despawn entry.handle)
      (set (. handles-by-key key) nil)))

  (fn sync [_self]
    (when dropped?
      (scene-view-error "sync after drop"))
    (local next-keys {})
    (each [_ cell (ipairs (collect-cells game origin cell-size))]
      (set (. next-keys cell.key) true)
      (local existing (. handles-by-key cell.key))
      (if existing
          (do
            (scene:set-transform existing.handle {:position cell.position :size cell.size})
            (set existing.cell cell))
          (do
            (local handle (scene:spawn (make-spawn-spec cell)))
            (set (. handles-by-key cell.key) {:handle handle :cell cell}))))
    (local stale [])
    (each [key _entry (pairs handles-by-key)]
      (when (not (. next-keys key))
        (table.insert stale key)))
    (each [_ key (ipairs stale)]
      (despawn-key key))
    true)

  (fn drop [_self]
    (when (not dropped?)
      (local keys [])
      (each [key _entry (pairs handles-by-key)]
        (table.insert keys key))
      (each [_ key (ipairs keys)]
        (despawn-key key))
      (set dropped? true))
    nil)

  {:sync sync :drop drop})

{:create create}
```

- [ ] **Step 7: Validate and commit Task 1**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file examples/snake/assets/lua/snake/scene-view.fnl --file examples/snake/assets/lua/tests/test-snake-scene-view.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snake-scene-view:main
```

Commit:

```bash
git add examples/snake/assets/lua/snake/scene-view.fnl examples/snake/assets/lua/tests/test-snake-scene-view.fnl
git commit -m "feat(apps): add Snake scene view"
```

---

### Task 2: Snake Runtime Scene Wiring

**Files:**
- Modify: `examples/snake/assets/lua/snake/app.fnl`
- Modify: `examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl`

**Interfaces:**
- Consumes: `SceneView.create {:scene scene :game game} -> scene-view` from Task 1.
- Produces: `SnakeMain.create(host)` requires `host.scene`, calls `scene-view:sync()` with existing screen sync, and calls `scene-view:drop()` during runtime teardown.

- [ ] **Step 1: Add scene capability to hosted runtime fake host**

In `test-snake-hosted-runtime.fnl`, require the generic scene capability and add it to `fake-host`:

```fennel
(local SceneCapability (require :app-host.scene-capability))
```

Inside `fake-host`, add:

```fennel
:scene (or options.scene (SceneCapability.create {}))
```

- [ ] **Step 2: Add failing runtime scene ownership test**

Add:

```fennel
(fn test-snake-runtime-spawns-and-drops-scene-handles []
  (local host (fake-host))
  (local runtime (SnakeMain.create host))
  (assert (> (# (host.scene:list-owned)) 0) "Snake runtime should spawn scene handles")
  (runtime.lifecycle:drop)
  (assert (= (# (host.scene:list-owned)) 0) "Snake runtime drop should despawn scene handles"))

(add-test "snake runtime spawns and drops scene handles" test-snake-runtime-spawns-and-drops-scene-handles)
```

Run `tests.test-snake-hosted-runtime:main` and expect failure because `snake.app` has not created a scene view yet.

- [ ] **Step 3: Add failing missing scene capability test**

Add:

```fennel
(fn test-missing-scene-errors-loudly []
  (local host (fake-host))
  (set host.scene nil)
  (local (ok err) (pcall #(SnakeMain.create host)))
  (assert (not ok) "Snake create must fail when required scene capability is missing")
  (assert (string.find (tostring err) "scene" 1 true) "missing scene error should name scene capability"))

(add-test "missing scene errors loudly" test-missing-scene-errors-loudly)
```

- [ ] **Step 4: Update app creation to require scene and create scene view**

In `examples/snake/assets/lua/snake/app.fnl`, add:

```fennel
(local SceneView (require :snake/scene-view))
```

Inside `create`, require scene before registrations:

```fennel
(local scene (Capabilities.require host :scene))
```

After `game` exists, create:

```fennel
(local scene-view (SceneView.create {:scene scene :game game}))
```

- [ ] **Step 5: Sync scene view with screen**

Update `sync-screen` so it calls scene view sync after the 2D screen sync:

```fennel
(fn sync-screen []
  (screen:sync)
  (surface:update)
  (scene-view:sync))
```

Do not call `scene-view:sync()` from `refresh-screen`, because refresh without game state changes should not touch scene handles.

- [ ] **Step 6: Drop scene view during lifecycle teardown**

Inside runtime `drop`, after unregistering facets and before dropping the surface, call:

```fennel
(scene-view:drop)
```

Keep the existing `dropped?` guard so scene view drop is called once.

- [ ] **Step 7: Validate and commit Task 2**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file examples/snake/assets/lua/snake/app.fnl --file examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snake-scene-view:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snake-hosted-runtime:main
```

Commit:

```bash
git add examples/snake/assets/lua/snake/app.fnl examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl
git commit -m "feat(apps): wire Snake runtime to scene view"
```

---

### Task 3: Snake Scene Documentation

**Files:**
- Modify: `examples/snake/README.md`
- Modify: `docs/dev/features/hosted-runtime-apps.md`

**Interfaces:**
- Consumes: scene behavior from Tasks 1 and 2.
- Produces: developer-facing docs for the first 3D Snake slice and hosted scene capability example.

- [ ] **Step 1: Update Snake README summary and layout**

Update `examples/snake/README.md` so the opening says Snake now includes both:

```markdown
The runtime display keeps the simple 2D graphical Snake board rendered with Space widgets and also mirrors the gameplay state into `host.scene` as app-owned 3D scene objects. The pure game rules stay separate from the view/runtime code so the example remains easy to copy and test.
```

Add `scene-view.fnl` and `test-snake-scene-view.fnl` to the directory tree.

- [ ] **Step 2: Document scene capability behavior**

In the README, after the host modes list, add:

```markdown
Snake requires `host.scene` and uses it without checking whether the app is standalone or embedded. The scene view spawns concrete custom objects tagged as `:snake`, `:head`, `:body`, and `:food`, then despawns those handles during runtime teardown. The 2D surface remains the visible controls/status presentation for this first slice; 3D camera controls and terrain-aware gameplay are follow-up work.
```

- [ ] **Step 3: Add scene-view test command**

Add this command near the existing focused test commands:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snake-scene-view:main
```

- [ ] **Step 4: Update hosted runtime docs**

In `docs/dev/features/hosted-runtime-apps.md`, replace the line saying 3D Snake is future work with:

```markdown
The Snake example uses this capability as the first app-level scene consumer: its runtime mirrors grid gameplay into app-owned scene handles while keeping the same `create(host)` path for standalone and embedded hosts. Embedded custom objects provide concrete `spec.object` values because registry-only fake handles are not enough for real Space scene insertion.
```

- [ ] **Step 5: Validate and commit Task 3**

Run focused text checks:

```bash
git diff --check
```

Commit:

```bash
git add examples/snake/README.md docs/dev/features/hosted-runtime-apps.md
git commit -m "docs(apps): document Snake scene view"
```

---

### Task 4: Final Validation

**Files:**
- Test: all files changed by Tasks 1 through 3.

**Interfaces:**
- Consumes: scene view module, runtime scene wiring, docs.
- Produces: validation evidence for finishing the branch.

- [ ] **Step 1: Run compile check**

Run:

```bash
make fennel-check
```

- [ ] **Step 2: Run constraints**

Run:

```bash
make constraints
```

- [ ] **Step 3: Run focused Snake scene/runtime tests**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snake-scene-view:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snake-hosted-runtime:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snake-standalone-entry:main
```

- [ ] **Step 4: Run broader Snake tests**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snake-game:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets FENNEL_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snake-view:main
```

- [ ] **Step 5: Confirm acceptance criteria and clean tree**

Confirm in the report:

- initial Snake creation spawns scene-owned handles;
- moving/restarting updates handles;
- dropped runtimes leave no Snake-owned scene handles;
- missing `host.scene` fails loudly;
- no code branches on hosted-vs-standalone;
- existing 2D Snake UI tests still pass.

Run:

```bash
git status --short
```

Expected: clean tree after all reviewed commits.
