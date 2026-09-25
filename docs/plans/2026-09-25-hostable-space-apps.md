# Hostable Space Apps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the MVP foundation for hosting an independently publishable Space-runtime app inside Space, using Snake as the first proven app.

**Architecture:** Use a trusted in-process lifecycle interface. Standalone apps keep a `main`/`run` harness that owns `Engine` and renderers, while embedded mode exports `create(host)` and returns a host-owned session object. A generic Space adapter controls timing, pause, input, presentation-target delegation, snapshots, and teardown.

**Tech Stack:** Space Fennel, `OrthographicUiSurface`, Space presentation targets, focused Fennel tests, `tools.fennel-check`, `make constraints`.

## Global Constraints

- MVP hosting is for trusted in-process Space/Fennel apps.
- Standalone mode may own `Engine`; embedded mode must not create, start, run, shut down, or drop an `Engine`.
- Embedded mode must not create, replace, or drop global `app.renderers`.
- Embedded mode must not replace `app.active-world-runtime` directly.
- Embedded apps must not subscribe directly to engine event signals; the host adapter routes update and input events.
- Paused hosted apps remain drawable; pause only stops simulation advancement.
- `snapshot` returns plain data tables, not live widget, renderer, surface, or engine objects.
- Missing app exports, invalid host fields, failed module loads, invalid payloads, and teardown failures must surface explicit errors.
- Preserve independent Snake launch with `SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m main`.
- Use `local` instead of `let` in Fennel.
- Use factory functions instead of `.new` constructors.
- Validate Fennel work with project-native `tools.fennel-check`, then `make constraints`, then focused Fennel tests.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- Disable audio for CLI tests with `SPACE_DISABLE_AUDIO=1`; set `XDG_DATA_HOME=/tmp/space/tests/xdg-data`; set `SKIP_KEYRING_TESTS=1`.
- Build first with `make build` timeout `14400000` when `./build/space` is missing or stale.

---

## File Structure

- `docs/dev/features/hosted-runtime-apps.md`: developer-facing contract for hostable Space-runtime apps, session methods, ownership rules, and deferred alternatives.
- `docs/dev/features/app-distribution.md`: short link from existing app distribution docs to the hostable app contract.
- `examples/snake/assets/lua/snake/session.fnl`: engine-free Snake session that owns game state, orthographic surface, screen widget, pause/step state, input mapping, snapshots, viewport changes, and teardown.
- `examples/snake/assets/lua/snake/app.fnl`: standalone harness and Snake host entry; keeps engine/render ownership only in `run`, delegates embedded construction to the session.
- `examples/snake/assets/lua/main.fnl`: public Snake entry module; exports `:main`, `:create`, and `:metadata` while preserving the existing `app-config.run-main` guard.
- `assets/lua/hosted-app-runtime.fnl`: generic Space-side adapter that consumes a hostable module and returns a controller plus runtime presentation shape.
- `examples/snake/assets/lua/tests/test-snake-hosted-session.fnl`: focused tests for the engine-free Snake session.
- `assets/lua/tests/test-hosted-app-runtime.fnl`: focused tests for the generic adapter using fake app modules and fake sessions.
- `examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl`: integration smoke test proving Snake's public entry module works through the generic adapter.
- `examples/snake/README.md`: documents standalone and hosted validation commands.

---

### Task 1: Document the Hostable App Contract

**Files:**
- Create: `docs/dev/features/hosted-runtime-apps.md`
- Modify: `docs/dev/features/app-distribution.md`

**Interfaces:**
- Consumes: `docs/specs/2026-09-25-hostable-space-apps-design.md`
- Produces: Documentation naming the public app module exports `metadata`, `main`, and `create(host)`, plus hosted session methods `render-targets`, `update`, `handle-input`, `on-viewport-changed`, `set-paused`, `step-once`, `snapshot`, and `drop`.

- [ ] **Step 1: Add the hosted runtime apps page**

Create `docs/dev/features/hosted-runtime-apps.md` with these sections and decisions:

````markdown
# Hosted Runtime Apps

Space-runtime apps can be independently runnable and hostable by Space when their entry module separates standalone engine ownership from embedded session ownership.

## Entry module contract

A hostable app entry module exports `metadata`, `main`, and `create`.

```fennel
{:metadata {:id "examples.snake" :title "Snake"}
 :main main
 :create create}
```

- `main` runs the app through the standalone harness.
- `create(host)` returns a hosted session and must not create, start, run, shut down, or drop `Engine`.
- `metadata` is plain data for launchers and tools.

## Host table

The MVP host table is:

```fennel
{:mode :embedded
 :viewport viewport
 :metadata metadata
 :request-quit request-quit}
```

`create(host)` must raise an explicit error when required fields are missing.

## Hosted session methods

- `render-targets(self) -> table[]`
- `update(self, delta-ms:number) -> boolean`
- `handle-input(self, event-name:string|keyword, payload:table) -> boolean`
- `on-viewport-changed(self, viewport:table) -> nil`
- `set-paused(self, paused?:boolean) -> boolean`
- `step-once(self) -> boolean`
- `snapshot(self) -> table`
- `drop(self) -> nil`

## Ownership rules

- Space owns the process engine, renderer, main update loop, input routing, presentation composition, and shutdown in embedded mode.
- Hosted apps own their model, view widgets, surfaces, and app-local resources.
- Hosted apps must not replace `app.engine`, `app.renderers`, or `app.active-world-runtime`.
- Hosted apps must not connect directly to engine signals in embedded mode.
- Paused apps still render their current presentation targets.
- Snapshots contain plain data only.

## Deferred alternatives

Process-boundary hosting is future work for isolation and crash containment. It needs explicit input, timing, state, lifecycle, and render protocols.

External compositor embedding through wlroots/Xwayland is not the MVP path. The paused wlroots status note documents DMA-BUF import failures, unreliable readback, fragile headless output commits, Xwayland socket collisions, and teardown crashes.
````

- [ ] **Step 2: Link from app distribution docs**

In `docs/dev/features/app-distribution.md`, add a section after the developer run commands:

```markdown
## Hostable apps

Independent Space apps can also expose an embedded lifecycle for Space IDE workflows. See [Hosted Runtime Apps](hosted-runtime-apps.md) for the `create(host)` contract, hosted session methods, ownership rules, and the Snake MVP shape.
```

- [ ] **Step 3: Validate the docs text**

Run:

```bash
rg "Hosted Runtime Apps|create\(host\)|Hosted session methods|Hostable apps" docs/dev/features
```

Expected: output includes `docs/dev/features/hosted-runtime-apps.md` and the new `Hostable apps` section in `docs/dev/features/app-distribution.md`.

- [ ] **Step 4: Commit after review passes**

After the reviewer approves this task, commit only the two docs files:

```bash
git add docs/dev/features/hosted-runtime-apps.md docs/dev/features/app-distribution.md
git commit -m "docs: add hosted runtime app contract"
```

---

### Task 2: Extract the Engine-Free Snake Session

**Files:**
- Create: `examples/snake/assets/lua/snake/session.fnl`
- Create: `examples/snake/assets/lua/tests/test-snake-hosted-session.fnl`
- Modify: `examples/snake/assets/lua/snake/app.fnl`
- Modify: `examples/snake/assets/lua/main.fnl`

**Interfaces:**
- Consumes: `snake/game.fnl`, `snake/view.fnl`, `orthographic-ui-surface.fnl`, existing `SnakeApp.run` behavior.
- Produces: `SnakeSession.create(opts: table) -> session: table`; `SnakeApp.create(host: table) -> session: table`; `main.fnl` exports `:create` and `:metadata`.

- [ ] **Step 1: Add failing session tests for construction and presentation**

Create `examples/snake/assets/lua/tests/test-snake-hosted-session.fnl` with a runner structure matching existing Snake tests and assertions equivalent to:

```fennel
(local SnakeSession (require :snake/session))

(fn assert-eq [actual expected message]
  (when (not (= actual expected))
    (error (.. message " expected=" (tostring expected) " actual=" (tostring actual)))))

(fn test-create-does-not-own-engine []
  (local session (SnakeSession.create {:viewport {:x 0 :y 0 :width 320 :height 240}}))
  (assert-eq (= (type session.render-targets) :function) true "render-targets method")
  (assert-eq (= app.engine nil) true "session did not create global engine")
  (local targets (session:render-targets))
  (assert-eq (# targets) 1 "one presentation target")
  (assert-eq (. targets 1 :kind) :hud "orthographic surface target kind")
  (session:drop))
```

Run the test command and expect failure because `snake/session.fnl` does not exist yet:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-hosted-session:main
```

- [ ] **Step 2: Add failing session tests for pause, step, input, snapshot, viewport, and drop**

Extend `test-snake-hosted-session.fnl` with tests equivalent to:

```fennel
(fn test-pause-update-step-and-snapshot []
  (local session (SnakeSession.create {:viewport {:x 0 :y 0 :width 320 :height 240}}))
  (local before (session:snapshot))
  (assert-eq (session:set-paused true) true "paused state")
  (session:update 1000)
  (local paused-snapshot (session:snapshot))
  (assert-eq paused-snapshot.head.x before.head.x "paused update keeps x")
  (assert-eq paused-snapshot.head.y before.head.y "paused update keeps y")
  (session:step-once)
  (local stepped (session:snapshot))
  (assert-eq (not (= stepped.head.x before.head.x)) true "step changed x")
  (session:drop))

(fn test-input_viewport_and_drop []
  (local session (SnakeSession.create {:viewport {:x 0 :y 0 :width 320 :height 240}}))
  (assert-eq (session:handle-input :key-down {:key 1073741905}) true "down key handled")
  (session:on-viewport-changed {:x 0 :y 0 :width 640 :height 480})
  (local targets (session:render-targets))
  (assert-eq (# targets) 1 "target remains available after viewport change")
  (local snapshot (session:snapshot))
  (assert-eq (= (type snapshot.score) :number) true "snapshot score is plain number")
  (assert-eq (= (type snapshot.snake) :table) true "snapshot snake is plain table")
  (session:drop)
  (session:drop))
```

Expected: the command still fails until `snake/session.fnl` is implemented.

- [ ] **Step 3: Implement `snake/session.fnl` with engine-free lifecycle**

Create `examples/snake/assets/lua/snake/session.fnl` that requires only `snake/game`, `snake/view`, and `orthographic-ui-surface`. Implement these exports:

```fennel
{:create create
 :test-utils {:advance-game advance-game
              :delta-ms->seconds delta-ms->seconds}}
```

The session object returned by `create(opts)` must include methods named exactly:

```fennel
:render-targets
:update
:handle-input
:on-key-down
:on-viewport-changed
:set-paused
:step-once
:snapshot
:drop
```

Move the existing key mapping helpers, `tick-interval`, viewport helpers, `delta-ms->seconds`, `advance-game`, surface creation, screen sync, and drop behavior out of `snake/app.fnl` into this file. The `create` function should build:

```fennel
(local game (Snake.create {}))
(local surface (OrthographicUiSurface.create {:viewport viewport}))
(local screen (surface:build (SnakeView.SnakeScreen {:game game})))
```

Keep pause state with `(var paused? false)`, elapsed time with `(var elapsed 0)`, and dropped state with `(var dropped? false)`. `update` returns `false` while paused, advances with `advance-game` otherwise, refreshes the surface every call, and returns whether the game stepped. `step-once` advances one fixed `tick-interval` step and keeps `paused?` true. `snapshot` returns plain keys such as `:score`, `:game-over?`, `:direction`, `:head`, `:snake`, `:food`, and `:paused?`.

- [ ] **Step 4: Refactor `snake/app.fnl` to delegate to the session**

Modify `examples/snake/assets/lua/snake/app.fnl` so `run` keeps standalone ownership while delegating game/session behavior:

```fennel
(local SnakeSession (require :snake/session))

(fn create [host]
  (when (not host)
    (error "[snake] host is required"))
  (SnakeSession.create {:viewport host.viewport
                        :request-quit host.request-quit}))
```

In `run`, replace direct game/surface/screen construction with:

```fennel
(local session (SnakeSession.create {:viewport viewport
                                     :request-quit quit}))
```

Set `app.active-world-runtime.presentation.render-targets` to delegate to `session:render-targets`. Engine event handlers call `session:on-key-down`, `session:update`, and `session:on-viewport-changed`. Standalone cleanup disconnects events, drops `session`, drops standalone `app.renderers`, and shuts down `engine`.

- [ ] **Step 5: Update Snake main exports**

Modify `examples/snake/assets/lua/main.fnl` so the final export table is:

```fennel
{:metadata {:id "examples.snake" :title "Snake"}
 :main main
 :create SnakeApp.create}
```

Preserve:

```fennel
(when AppConfig.run-main
  (main))
```

- [ ] **Step 6: Run focused Snake validation**

If `./build/space` is missing or stale, run:

```bash
make build
```

with timeout `14400000`.

Run compile checks for touched Fennel files:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets FENNEL_PATH='$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl' FENNEL_MACRO_PATH='$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl' ./build/space -m tools.fennel-check:main -- --target files --file examples/snake/assets/lua/snake/session.fnl --file examples/snake/assets/lua/snake/app.fnl --file examples/snake/assets/lua/main.fnl --file examples/snake/assets/lua/tests/test-snake-hosted-session.fnl
```

Run:

```bash
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-hosted-session:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-game:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-view:main
```

- [ ] **Step 7: Commit after review passes**

After the reviewer approves this task, commit only the Snake session changes:

```bash
git add examples/snake/assets/lua/snake/session.fnl examples/snake/assets/lua/tests/test-snake-hosted-session.fnl examples/snake/assets/lua/snake/app.fnl examples/snake/assets/lua/main.fnl
git commit -m "feat(apps): add hostable Snake session"
```

---

### Task 3: Add the Generic Hosted App Runtime Adapter

**Files:**
- Create: `assets/lua/hosted-app-runtime.fnl`
- Create: `assets/lua/tests/test-hosted-app-runtime.fnl`

**Interfaces:**
- Consumes: A hostable module table with `create(host: table) -> session: table` and session methods from Task 2.
- Produces: `HostedAppRuntime.create(opts: table) -> controller: table` with methods `runtime`, `update`, `dispatch-input`, `set-paused`, `step`, `snapshot`, and `drop`.

- [ ] **Step 1: Add failing adapter tests for validation and host construction**

Create `assets/lua/tests/test-hosted-app-runtime.fnl` with tests equivalent to:

```fennel
(local HostedAppRuntime (require :hosted-app-runtime))

(fn assert-error [fn-under-test expected-substring]
  (local (ok err) (pcall fn-under-test))
  (when ok (error "expected error"))
  (when (not (string.find (tostring err) expected-substring 1 true))
    (error (.. "expected error containing " expected-substring " got " (tostring err)))))

(fn test-rejects-module-without-create []
  (assert-error #(HostedAppRuntime.create {:module {}}) "create"))

(fn test-passes-host-context []
  (var captured-host nil)
  (local fake-module {:metadata {:id "fake" :title "Fake"}
                      :create (fn [host]
                                (set captured-host host)
                                {:render-targets (fn [_self] [])
                                 :update (fn [_self _delta] false)
                                 :handle-input (fn [_self _event _payload] false)
                                 :on-viewport-changed (fn [_self _viewport] nil)
                                 :set-paused (fn [_self paused] (not (not paused)))
                                 :step-once (fn [_self] false)
                                 :snapshot (fn [_self] {:ok true})
                                 :drop (fn [_self] nil)})})
  (local controller (HostedAppRuntime.create {:module fake-module
                                              :viewport {:x 0 :y 0 :width 10 :height 10}}))
  (assert (= captured-host.mode :embedded))
  (assert (= captured-host.metadata.id "fake"))
  (controller:drop))
```

Run and expect failure because `hosted-app-runtime.fnl` does not exist:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-hosted-app-runtime:main
```

- [ ] **Step 2: Add failing adapter tests for delegation, pause, step, and drop**

Extend the same test file with a fake session that counts calls:

```fennel
(fn make-counting-module []
  (local calls {:updates 0 :inputs 0 :drops 0 :steps 0})
  (local target {:kind :hud})
  (local session {:render-targets (fn [_self] [target])
                  :update (fn [_self _delta] (set calls.updates (+ calls.updates 1)) true)
                  :handle-input (fn [_self _event _payload] (set calls.inputs (+ calls.inputs 1)) true)
                  :on-viewport-changed (fn [_self _viewport] nil)
                  :set-paused (fn [_self paused] (not (not paused)))
                  :step-once (fn [_self] (set calls.steps (+ calls.steps 1)) true)
                  :snapshot (fn [_self] {:updates calls.updates :inputs calls.inputs :steps calls.steps})
                  :drop (fn [_self] (set calls.drops (+ calls.drops 1)))})
  {:calls calls
   :module {:metadata {:id "counting" :title "Counting"}
            :create (fn [_host] session)}})

(fn test-runtime_delegates_and_pause_blocks_update []
  (local fixture (make-counting-module))
  (local controller (HostedAppRuntime.create {:module fixture.module
                                              :viewport {:x 0 :y 0 :width 100 :height 100}}))
  (local runtime (controller:runtime))
  (assert (= (# (runtime.presentation:render-targets)) 1))
  (assert (= (controller:update 16) true))
  (controller:set-paused true)
  (assert (= (controller:update 16) false))
  (assert (= fixture.calls.updates 1))
  (assert (= (controller:step) true))
  (assert (= fixture.calls.steps 1))
  (assert (= (controller:dispatch-input :key-down {:key 1}) true))
  (controller:drop)
  (controller:drop)
  (assert (= fixture.calls.drops 1)))
```

Expected: failure until the adapter is implemented.

- [ ] **Step 3: Implement `assets/lua/hosted-app-runtime.fnl`**

Create a module exporting `{:create create}`. `create(opts)` accepts either `opts.module` or `opts.module-name`. It must fail loudly when neither is present, when `require` fails, or when the module lacks `create`.

Controller construction should call:

```fennel
(local session (module.create {:mode :embedded
                               :viewport viewport
                               :metadata (or module.metadata {})
                               :request-quit request-quit}))
```

Validate that `session` has callable `render-targets`, `update`, `handle-input`, `set-paused`, `step-once`, `snapshot`, and `drop`. `on-viewport-changed` is required when the controller exposes viewport changes.

The controller must hold `(var paused? false)` and `(var dropped? false)`. `controller:update(delta-ms)` returns `false` without calling the session while paused. `controller:set-paused(paused)` updates local pause state and calls `session:set-paused`. `controller:step(delta-ms)` calls `session:step-once`; the optional `delta-ms` argument is accepted for host symmetry but not required by the session contract. `controller:drop()` calls `session:drop()` once.

`controller:runtime()` returns:

```fennel
{:presentation {:render-targets (fn [_presentation]
                                  (session:render-targets))}}
```

- [ ] **Step 4: Run focused adapter validation**

Run compile check:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/hosted-app-runtime.fnl --file assets/lua/tests/test-hosted-app-runtime.fnl
```

Run:

```bash
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-hosted-app-runtime:main
```

- [ ] **Step 5: Commit after review passes**

After the reviewer approves this task, commit only the generic adapter changes:

```bash
git add assets/lua/hosted-app-runtime.fnl assets/lua/tests/test-hosted-app-runtime.fnl
git commit -m "feat(apps): add hosted app runtime adapter"
```

---

### Task 4: Prove Snake Works Through the Generic Adapter

**Files:**
- Create: `examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl`
- Modify: `examples/snake/README.md`

**Interfaces:**
- Consumes: `main.fnl` exports from Task 2 and `HostedAppRuntime.create(opts)` from Task 3.
- Produces: A focused integration smoke test and README commands for the hosted Snake workflow.

- [ ] **Step 1: Add the hosted runtime smoke test**

Create `examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl` with assertions equivalent to:

```fennel
(local HostedAppRuntime (require :hosted-app-runtime))
(local SnakeMain (require :main))

(fn test-snake-main-hosts-through-runtime []
  (local controller (HostedAppRuntime.create {:module SnakeMain
                                              :viewport {:x 0 :y 0 :width 800 :height 600}}))
  (local runtime (controller:runtime))
  (local targets (runtime.presentation:render-targets))
  (assert (= (# targets) 1))
  (assert (= (. targets 1 :kind) :hud))
  (local before (controller:snapshot))
  (controller:set-paused true)
  (controller:update 1000)
  (local paused (controller:snapshot))
  (assert (= paused.head.x before.head.x))
  (assert (= paused.head.y before.head.y))
  (controller:step)
  (local stepped (controller:snapshot))
  (assert (or (not (= stepped.head.x before.head.x))
              (not (= stepped.head.y before.head.y))))
  (assert (= (controller:dispatch-input :key-down {:key 1073741905}) true))
  (controller:drop))
```

Run the test and expect failure until Tasks 2 and 3 are complete:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-hosted-runtime:main
```

- [ ] **Step 2: Update the Snake README**

Add a `Hosted development smoke test` section to `examples/snake/README.md`:

````markdown
## Hosted development smoke test

Snake's entry module is independently runnable and hostable. The hosted path uses Space's `hosted-app-runtime` adapter to create a session without starting a second engine.

```sh
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-hosted-runtime:main
```

This smoke test proves pause, single-step, input dispatch, plain snapshots, and presentation-target delegation. It is not an app launcher UI or external app discovery mechanism.
````

- [ ] **Step 3: Run focused smoke validation**

Run compile check:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets FENNEL_PATH='$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl' FENNEL_MACRO_PATH='$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl' ./build/space -m tools.fennel-check:main -- --target files --file examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl
```

Run:

```bash
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-hosted-runtime:main
```

- [ ] **Step 4: Commit after review passes**

After the reviewer approves this task, commit only the smoke test and README changes:

```bash
git add examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl examples/snake/README.md
git commit -m "test(apps): prove Snake hosted runtime path"
```

---

### Task 5: Final Focused Validation

**Files:**
- Review: all files changed by Tasks 1 through 4.

**Interfaces:**
- Consumes: Hostable app docs, Snake session, generic adapter, and hosted Snake smoke test.
- Produces: Validation evidence for finishing the development branch.

- [ ] **Step 1: Run compile checks for all touched Fennel files**

Run repository compile checks:

```bash
make fennel-check
```

Run an explicit compile check for example Snake files because example assets are outside the default repository asset root:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets FENNEL_PATH='$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl' FENNEL_MACRO_PATH='$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl' ./build/space -m tools.fennel-check:main -- --target files --file examples/snake/assets/lua/snake/session.fnl --file examples/snake/assets/lua/snake/app.fnl --file examples/snake/assets/lua/main.fnl --file examples/snake/assets/lua/tests/test-snake-hosted-session.fnl --file examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl
```

Expected: both commands pass.

- [ ] **Step 2: Run constraints**

Run:

```bash
make constraints
```

Expected: pass.

- [ ] **Step 3: Run focused hosted app tests**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-hosted-session:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-hosted-app-runtime:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-hosted-runtime:main
```

Expected: all pass.

- [ ] **Step 4: Run existing Snake regression tests**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-game:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-view:main
```

Expected: both pass.

- [ ] **Step 5: Decide whether the broad suite is required**

If implementation touched only the files listed in this plan, record that full `make test` is not required because the changed behavioral surface is covered by Fennel compile checks, constraints, focused adapter tests, focused Snake hosted tests, and existing Snake tests.

If implementation also touched Space startup, global input routing, `renderers.fnl`, C++ bindings, or runtime initialization, run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Expected: pass before finishing.

- [ ] **Step 6: Commit validation-only documentation changes if any were made**

If validation uncovered docs command corrections, commit those reviewed corrections. If no files changed, do not create an empty commit.

```bash
git status --short
```

Expected: no uncommitted changes after any required reviewed corrections are committed.
