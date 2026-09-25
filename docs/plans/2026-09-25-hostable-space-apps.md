# Hostable Space Apps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a future-proof MVP for hosting independently publishable Space-runtime apps by making apps return runtime compositions over host capabilities.

**Architecture:** Apps export `metadata`, `create(host)`, and optional `main`. `create(host)` returns a Space-style runtime composition with protocol facets such as `presentation`, `lifecycle`, scheduler registrations, inspectors, and commands. Standalone and embedded launch paths construct different generic hosts with the same capability surface, then call the same app factory; app code does not branch on hosted-vs-standalone mode.

**Tech Stack:** Space Fennel, host capability tables, Space presentation providers, `OrthographicUiSurface`, generic scheduler/input/inspector services, focused Fennel tests, `tools.fennel-check`, `make constraints`.

## Global Constraints

- Public app contract is stable: `metadata`, `create(host)`, and optional `main`.
- `create(host)` returns a runtime composition object, not a bespoke game session method list.
- App code must not check hosted-vs-standalone mode.
- Standalone and embedded paths must call the same app factory.
- App code must not create/start/run/shut down `Engine` directly.
- Embedded mode must not create, replace, or drop global `app.renderers`.
- App code must not replace `app.engine`, `app.renderers`, or `app.active-world-runtime` directly.
- App code must not connect directly to engine signals; it registers through host scheduler/input/lifecycle services.
- Multiple surfaces/features must be accessed through host capabilities and runtime facets, not new required app methods.
- Pause/step/inspection are host services: scheduler lanes, inspector registry, and command registry.
- Missing app exports, invalid host capabilities, failed module loads, invalid payloads, and teardown failures must surface explicit errors.
- Preserve independent Snake launch with `SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m main`.
- Use `local` instead of `let` in Fennel.
- Use factory functions instead of `.new` constructors.
- Validate Fennel work with project-native `tools.fennel-check`, then `make constraints`, then focused Fennel tests.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- Disable audio for CLI tests with `SPACE_DISABLE_AUDIO=1`; set `XDG_DATA_HOME=/tmp/space/tests/xdg-data`; set `SKIP_KEYRING_TESTS=1`.
- Build first with `make build` timeout `14400000` when `./build/space` is missing or stale.

---

## File Structure

- `docs/dev/features/hosted-runtime-apps.md`: developer-facing contract for runtime compositions, host capabilities, ownership rules, scheduler pause/step, inspectors, commands, and deferred alternatives.
- `docs/dev/features/app-distribution.md`: links app distribution to the hostable runtime contract.
- `assets/lua/app-host/capabilities.fnl`: small validation/helpers for host capability tables and required service lookup.
- `assets/lua/app-host/runtime-controller.fnl`: generic controller that mounts a module by calling `module.create(host)`, mounts known runtime facets, delegates presentation, exposes host-level pause/step/inspect/command operations, and drops lifecycle resources.
- `assets/lua/hosted-app-runtime.fnl`: embedded Space-facing wrapper that creates a host from Space-owned services and uses `runtime-controller`.
- `assets/lua/standalone-app-runtime.fnl`: standalone harness that owns `Engine`, renderers, event loop wiring, and host services, then calls the same app factory.
- `assets/lua/tests/test-app-host-runtime-controller.fnl`: focused tests for the capability/runtime controller using fake modules.
- `assets/lua/tests/test-standalone-app-runtime.fnl`: focused tests for standalone harness boundaries using fakes where possible.
- `examples/snake/assets/lua/snake/app.fnl`: Snake composition module; builds game state, orthographic surface, presentation facet, scheduler/input registrations, lifecycle facet, and inspector registration from host capabilities.
- `examples/snake/assets/lua/main.fnl`: public Snake entry bridge; exports metadata/create/main and delegates `main` to `standalone-app-runtime`.
- `examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl`: proves Snake mounts through the generic runtime controller.
- `examples/snake/assets/lua/tests/test-snake-standalone-entry.fnl`: proves Snake `main` delegates to the standalone harness without duplicating game logic.
- `examples/snake/README.md`: documents standalone and hosted development commands.

---

### Task 1: Document the Runtime Composition Contract

**Files:**
- Create: `docs/dev/features/hosted-runtime-apps.md`
- Modify: `docs/dev/features/app-distribution.md`

**Interfaces:**
- Consumes: `docs/specs/2026-09-25-hostable-space-apps-design.md`
- Produces: Canonical developer docs for `metadata`, `create(host) -> runtime`, host capabilities, runtime facets, ownership rules, scheduler pause/step, inspectors, commands, and deferred alternatives.

- [ ] **Step 1: Create hosted runtime apps docs**

Create `docs/dev/features/hosted-runtime-apps.md` with these exact contract points:

````markdown
# Hosted Runtime Apps

Space-runtime apps are hostable when their entry module exports a runtime composition factory.

```fennel
{:metadata {:id "examples.snake" :title "Snake" :host-api 1}
 :create create
 :main main}
```

`create(host)` returns a runtime composition object. It must not create, start, run, shut down, or drop `Engine` directly. It must not replace `app.engine`, `app.renderers`, or `app.active-world-runtime`.

## Host capabilities

The host provides services such as `viewport`, `surfaces`, `presentation`, `scheduler`, `input`, `inspectors`, `commands`, `assets`, `logging`, and `lifecycle`. Apps require capabilities by name and fail loudly when required services are absent. Apps do not receive or branch on a hosted-vs-standalone mode flag.

## Runtime composition facets

A runtime may expose:

- `metadata`: plain metadata.
- `presentation`: existing Space presentation provider methods such as `render-targets`, `input-controls`, `screen-pos-ray`, and `camera`.
- `lifecycle`: deterministic teardown such as `drop`.
- `scheduler`: app simulation registrations.
- `inspectors`: plain-data or moldable inspector registrations.
- `commands`: command registrations for tools and live controls.

The core entry API does not add a new required method for every game feature.

## Pause, step, and inspection

Hosts pause and step scheduler lanes. Apps register pausable work with `host.scheduler`. Apps expose state through `host.inspectors` or an `inspectors` runtime facet. Pause, step, and inspection are not required methods on every app.

## Standalone and embedded hosts

Standalone launch and embedded mounting construct different generic hosts, then call the same `create(host)` app factory. App logic is shared.

## Deferred alternatives

Process-isolated hosting and compositor embedding are future work. wlroots/Xwayland embedding remains deferred because the previous attempt was unstable in headless rendering, DMA-BUF import, readback, socket lifecycle, and teardown.
````

- [ ] **Step 2: Link from app distribution docs**

In `docs/dev/features/app-distribution.md`, add a section after developer run commands:

```markdown
## Hostable runtime apps

Independent Space apps can expose the same `create(host) -> runtime` composition used by Space IDE hosts. See [Hosted Runtime Apps](hosted-runtime-apps.md) for host capabilities, runtime facets, and ownership rules.
```

- [ ] **Step 3: Validate docs**

Run:

```bash
rg "Hosted Runtime Apps|create\(host\) -> runtime|Hostable runtime apps|runtime composition" docs/dev/features
```

Expected: output includes the new contract page and the app-distribution link.

- [ ] **Step 4: Commit after review passes**

After reviewer approval, commit only docs files:

```bash
git add docs/dev/features/hosted-runtime-apps.md docs/dev/features/app-distribution.md
git commit -m "docs: add hosted runtime app contract"
```

---

### Task 2: Add Host Capability and Runtime Controller Core

**Files:**
- Create: `assets/lua/app-host/capabilities.fnl`
- Create: `assets/lua/app-host/runtime-controller.fnl`
- Create: `assets/lua/tests/test-app-host-runtime-controller.fnl`

**Interfaces:**
- Consumes: A hostable module table with `create(host: table) -> runtime: table`.
- Produces: `Capabilities.require(host, name) -> service`; `RuntimeController.create(opts: table) -> controller: table`.

- [ ] **Step 1: Write failing tests for capability validation**

Create `assets/lua/tests/test-app-host-runtime-controller.fnl` with tests that assert:

```fennel
(local Capabilities (require :app-host.capabilities))

(fn test-required-capability_errors_loudly []
  (local (ok err) (pcall #(Capabilities.require {} :scheduler)))
  (assert (= ok false))
  (assert (string.find (tostring err) "scheduler" 1 true)))

(fn test-required-capability_returns_service []
  (local service {:register (fn [] nil)})
  (assert (= (Capabilities.require {:scheduler service} :scheduler) service)))
```

Run and expect failure because modules do not exist:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-app-host-runtime-controller:main
```

- [ ] **Step 2: Write failing tests for runtime controller mounting**

Extend the test file with a fake module and host:

```fennel
(local RuntimeController (require :app-host.runtime-controller))

(fn fake-host []
  {:scheduler {:paused? false
               :updates 0
               :register (fn [self registration]
                           (set self.registration registration))
               :update (fn [self delta]
                         (when (and self.registration (not self.paused?))
                           (set self.updates (+ self.updates 1))
                           (self.registration.update delta)))
               :set-paused (fn [self paused] (set self.paused? paused) self.paused?)
               :step (fn [self delta]
                       (when self.registration
                         (self.registration.update delta)))}}
   :inspectors {:items []
                :register (fn [self inspector]
                            (table.insert self.items inspector))}
   :commands {:items []
              :register (fn [self command]
                          (table.insert self.items command))}
   :lifecycle {:drops 0}})

(fn test-controller_mounts_runtime_facets []
  (local host (fake-host))
  (local target {:kind :hud})
  (var dropped? false)
  (local module {:metadata {:id "fake" :title "Fake" :host-api 1}
                 :create (fn [given-host]
                           (assert (= given-host host))
                           {:metadata {:id "fake-runtime"}
                            :presentation {:render-targets (fn [_self] [target])}
                            :scheduler {:update (fn [_delta] true)}
                            :inspectors [{:id :state :read (fn [] {:ok true})}]
                            :commands [{:id :reset :run (fn [] true)}]
                            :lifecycle {:drop (fn [_self] (set dropped? true))}})})
  (local controller (RuntimeController.create {:module module :host host}))
  (assert (= (# (controller:render-targets)) 1))
  (assert (= (# host.inspectors.items) 1))
  (assert (= (# host.commands.items) 1))
  (controller:update 16)
  (assert (= host.scheduler.updates 1))
  (controller:set-paused true)
  (controller:update 16)
  (assert (= host.scheduler.updates 1))
  (controller:step 16)
  (controller:drop)
  (controller:drop)
  (assert (= dropped? true)))
```

- [ ] **Step 3: Implement `app-host/capabilities.fnl`**

Export:

```fennel
{:require require-capability}
```

`require-capability(host, name)` must raise `[app-host] missing required capability: <name>` when absent and return the service when present.

- [ ] **Step 4: Implement `app-host/runtime-controller.fnl`**

Export `{:create create}`. `create(opts)` must accept either `opts.module` or `opts.module-name`, require a `host`, validate `module.create`, call `module.create(host)`, and store the returned runtime.

Controller methods:

```fennel
:runtime(self) -> table
:render-targets(self) -> table[]
:update(self, delta-ms:number) -> boolean
:set-paused(self, paused:boolean) -> boolean
:step(self, delta-ms:number) -> boolean
:inspectors(self) -> table[]
:commands(self) -> table[]
:drop(self) -> nil
```

These are host/controller operations, not app-required methods. `render-targets` delegates to `runtime.presentation:render-targets()` when present. `update`, `set-paused`, and `step` delegate to `host.scheduler`. `drop` calls `runtime.lifecycle:drop()` once when present. Inspector and command runtime facets are registered with host services when present.

- [ ] **Step 5: Validate Task 2**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/capabilities.fnl --file assets/lua/app-host/runtime-controller.fnl --file assets/lua/tests/test-app-host-runtime-controller.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-app-host-runtime-controller:main
```

- [ ] **Step 6: Commit after review passes**

```bash
git add assets/lua/app-host/capabilities.fnl assets/lua/app-host/runtime-controller.fnl assets/lua/tests/test-app-host-runtime-controller.fnl
git commit -m "feat(apps): add runtime composition controller"
```

---

### Task 3: Add Generic Hosted and Standalone Runtime Hosts

**Files:**
- Create: `assets/lua/hosted-app-runtime.fnl`
- Create: `assets/lua/standalone-app-runtime.fnl`
- Create: `assets/lua/tests/test-standalone-app-runtime.fnl`

**Interfaces:**
- Consumes: `RuntimeController.create(opts) -> controller` from Task 2.
- Produces: `HostedAppRuntime.mount(opts) -> controller`; `StandaloneAppRuntime.run(opts) -> nil`; `StandaloneAppRuntime.create-host(opts) -> host` for focused tests.

- [ ] **Step 1: Implement hosted wrapper with fake-service tests**

Add tests to `assets/lua/tests/test-app-host-runtime-controller.fnl` or create focused hosted tests proving `HostedAppRuntime.mount {:module module :host host}` calls `RuntimeController.create` and returns a controller. Keep this wrapper thin; it should not define game-specific methods.

- [ ] **Step 2: Implement standalone host service construction**

Create `assets/lua/standalone-app-runtime.fnl` with:

```fennel
{:create-host create-host
 :run run}
```

`create-host(opts)` builds the same capability names expected by app code: `viewport`, `surfaces`, `presentation`, `scheduler`, `input`, `inspectors`, `commands`, `assets`, `logging`, and `lifecycle`. For the MVP, simple in-memory registries are acceptable for `inspectors` and `commands`; scheduler/input services must connect to engine events only inside the standalone host.

`run(opts)` owns `Engine`, renderer initialization, event loop wiring, controller mounting, runtime presentation delegation, cleanup, renderer drop, and engine shutdown.

- [ ] **Step 3: Write standalone boundary tests**

Create `assets/lua/tests/test-standalone-app-runtime.fnl` with tests for `create-host` that do not need a real engine:

```fennel
(local StandaloneRuntime (require :standalone-app-runtime))

(fn test-create_host_exposes_required_capabilities []
  (local host (StandaloneRuntime.create-host {:viewport {:x 0 :y 0 :width 100 :height 100}}))
  (each [_ name (ipairs [:viewport :surfaces :presentation :scheduler :input :inspectors :commands :logging :lifecycle])]
    (assert (. host name))))
```

If `run` cannot be tested without a real engine, keep `run` covered by Snake's existing standalone command and document that boundary in the test file.

- [ ] **Step 4: Validate Task 3**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/hosted-app-runtime.fnl --file assets/lua/standalone-app-runtime.fnl --file assets/lua/tests/test-standalone-app-runtime.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-standalone-app-runtime:main
```

- [ ] **Step 5: Commit after review passes**

```bash
git add assets/lua/hosted-app-runtime.fnl assets/lua/standalone-app-runtime.fnl assets/lua/tests/test-standalone-app-runtime.fnl
git commit -m "feat(apps): add generic runtime hosts"
```

---

### Task 4: Convert Snake to Runtime Composition

**Files:**
- Modify: `examples/snake/assets/lua/snake/app.fnl`
- Modify: `examples/snake/assets/lua/main.fnl`
- Create: `examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl`
- Create: `examples/snake/assets/lua/tests/test-snake-standalone-entry.fnl`
- Modify: `examples/snake/README.md`

**Interfaces:**
- Consumes: Task 2 runtime controller and Task 3 generic hosts.
- Produces: Snake entry module exports `metadata`, `create(host) -> runtime`, and `main`; Snake app code uses host capabilities with no hosted-vs-standalone branch.

- [ ] **Step 1: Write failing hosted Snake test**

Create `examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl` using the generic controller and a fake host. Assert that:

- `SnakeMain.create(host)` returns a runtime with `presentation` and `lifecycle` facets.
- `RuntimeController.create {:module SnakeMain :host host}` returns one presentation target.
- Scheduler pause blocks simulation updates while rendering targets remain available.
- Host inspector registry receives a Snake state inspector with plain data such as score, head, snake body, food, and game-over state.
- `controller:drop()` drops Snake-owned widgets/surfaces once.

- [ ] **Step 2: Convert `snake/app.fnl`**

Refactor `snake/app.fnl` so `create(host)` does all game composition. It should require needed capabilities by name, create game state and `OrthographicUiSurface`, register simulation with `host.scheduler`, register input with `host.input`, register a plain-data inspector with `host.inspectors`, and return:

```fennel
{:metadata {:id "examples.snake" :title "Snake" :host-api 1}
 :presentation presentation-facet
 :lifecycle lifecycle-facet}
```

Remove direct engine creation, renderer creation/drop, global `app.active-world-runtime` replacement, and direct engine signal connections from app composition.

- [ ] **Step 3: Update `main.fnl`**

Modify `examples/snake/assets/lua/main.fnl` so it exports:

```fennel
{:metadata {:id "examples.snake" :title "Snake" :host-api 1}
 :create SnakeApp.create
 :main main}
```

`main` calls the generic standalone harness:

```fennel
(fn main []
  (StandaloneRuntime.run {:module SnakeApp}))
```

Keep the existing `app-config.run-main` import guard so `space -m main` still launches standalone Snake and `require :main` remains safe.

- [ ] **Step 4: Add standalone entry test**

Create `examples/snake/assets/lua/tests/test-snake-standalone-entry.fnl` that requires `main`, asserts exported metadata/create/main exist, and verifies requiring the module does not start an engine when `app-config.run-main` is false.

- [ ] **Step 5: Update README**

Document that Snake has one app composition path and two generic hosts: standalone launch and hosted development smoke test.

- [ ] **Step 6: Validate Task 4**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets FENNEL_PATH='$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl' FENNEL_MACRO_PATH='$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl' ./build/space -m tools.fennel-check:main -- --target files --file examples/snake/assets/lua/snake/app.fnl --file examples/snake/assets/lua/main.fnl --file examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl --file examples/snake/assets/lua/tests/test-snake-standalone-entry.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-hosted-runtime:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-standalone-entry:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-game:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-view:main
```

- [ ] **Step 7: Commit after review passes**

```bash
git add examples/snake/assets/lua/snake/app.fnl examples/snake/assets/lua/main.fnl examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl examples/snake/assets/lua/tests/test-snake-standalone-entry.fnl examples/snake/README.md
git commit -m "feat(apps): make Snake a runtime composition"
```

---

### Task 5: Final Focused Validation

**Files:**
- Review: all files changed by Tasks 1 through 4.

**Interfaces:**
- Consumes: Documentation, host capabilities, runtime controller, generic hosts, and Snake runtime composition.
- Produces: Validation evidence for finishing the development branch.

- [ ] **Step 1: Run compile checks**

Run repository compile checks:

```bash
make fennel-check
```

Run explicit example compile checks:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets FENNEL_PATH='$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl' FENNEL_MACRO_PATH='$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl' ./build/space -m tools.fennel-check:main -- --target files --file examples/snake/assets/lua/snake/app.fnl --file examples/snake/assets/lua/main.fnl --file examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl --file examples/snake/assets/lua/tests/test-snake-standalone-entry.fnl
```

Expected: both pass.

- [ ] **Step 2: Run constraints**

```bash
make constraints
```

Expected: pass.

- [ ] **Step 3: Run focused host/runtime tests**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-app-host-runtime-controller:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-standalone-app-runtime:main
```

Expected: both pass.

- [ ] **Step 4: Run focused Snake tests**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-hosted-runtime:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-standalone-entry:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-game:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-view:main
```

Expected: all pass.

- [ ] **Step 5: Decide whether broad suite is required**

If implementation touched only files listed in this plan, record that full `make test` is not required because the changed behavior is covered by compile checks, constraints, focused host/runtime tests, focused Snake hosted tests, and existing Snake tests.

If implementation also touched Space startup, global input routing, `renderers.fnl`, C++ bindings, or runtime initialization, run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Expected: pass before finishing.

- [ ] **Step 6: Confirm clean tree**

```bash
git status --short
```

Expected: no uncommitted changes after any reviewed corrections are committed.
