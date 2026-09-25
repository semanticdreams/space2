# Hosted App Workspace Adapters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the first production Space workspace host path for embedded hostable apps: shared host services, HUD/canvas/scene host adapters, workspace mounting, presentation composition, and minimal hosted-app controls.

**Architecture:** Extract reusable host services from the standalone runtime, then build a Space host capability factory over existing HUD/canvas/scene APIs. Workspace mounts register hosted app controllers on the active runtime without replacing `app.active-world-runtime`, and `activity-presentation` includes hosted mount render targets. A minimal HUD control panel mounts an app and delegates pause/resume/step/close through the generic controller.

**Tech Stack:** Space Fennel, `app-host.runtime-controller`, existing HUD/canvas/scene surface APIs, activity presentation, focused Fennel tests, `tools.fennel-check`, `make constraints`.

## Global Constraints

- Public app contract remains `metadata`, `create(host)`, and optional `main`.
- App code must not branch on hosted-vs-standalone mode.
- Standalone and embedded paths must call the same app factory.
- App code must not create/start/run/shut down `Engine` directly.
- Embedded mode must not create, replace, or drop global `app.renderers`.
- App code must not replace `app.engine`, `app.renderers`, or `app.active-world-runtime` directly.
- New game features must use host capabilities or optional runtime facets, not new required per-game API methods.
- Missing required host capabilities must fail loudly; no silent fallback/no-op services.
- Use `local` instead of `let` in new Fennel code.
- Use factory functions instead of `.new` constructors.
- Update `docs/dev/features/hosted-runtime-apps.md` for the new Space host capabilities and workspace mount behavior.
- Out of scope for this PR: richer 3D world APIs, 3D Snake, generic moldable inspector/editor UI, app marketplace/discovery, persistent launcher UX, render-to-texture panel embedding, process isolation, wlroots/Xwayland.
- Validate Fennel work with project-native `tools.fennel-check`, then `make constraints`, then focused Fennel tests.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- Disable audio for CLI tests with `SPACE_DISABLE_AUDIO=1`; set `XDG_DATA_HOME=/tmp/space/tests/xdg-data`; set `SKIP_KEYRING_TESTS=1`.
- Build first with `make build` timeout `14400000` when `./build/space` is missing or stale.

---

## File Structure

- `assets/lua/app-host/services.fnl`: shared registry, scheduler, input, assets, and logging services used by standalone and embedded hosts.
- `assets/lua/app-host/space-host.fnl`: embedded Space host capability factory over `app.hud`, `app.canvas`, `app.scene`, plus generic services.
- `assets/lua/app-host/workspace-mount.fnl`: lifecycle object that owns a Space host and hosted controller and registers render targets on an active runtime.
- `assets/lua/app-host/workspace-panel.fnl`: minimal HUD control panel session for hosted app pause/resume/step/close.
- `assets/lua/standalone-app-runtime.fnl`: migrated to use shared host services without changing public behavior.
- `assets/lua/hosted-app-runtime.fnl`: gains `mount-in-workspace(opts)` while preserving existing `mount(opts)`.
- `assets/lua/activity-presentation.fnl`: includes render targets from active runtime hosted mounts.
- `docs/dev/features/hosted-runtime-apps.md`: documents Space host capabilities, workspace mounts, embedded quit behavior, and minimal controls.
- Tests:
  - `assets/lua/tests/test-app-host-services.fnl`
  - `assets/lua/tests/test-app-host-space-host.fnl`
  - `assets/lua/tests/test-hosted-app-workspace-mount.fnl`
  - `assets/lua/tests/test-hosted-app-workspace-panel.fnl`
  - existing `assets/lua/tests/test-standalone-app-runtime.fnl`
  - existing `examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl`

---

### Task 1: Shared Host Services Extraction

**Files:**
- Create: `assets/lua/app-host/services.fnl`
- Create: `assets/lua/tests/test-app-host-services.fnl`
- Modify: `assets/lua/standalone-app-runtime.fnl`
- Modify: `assets/lua/tests/test-standalone-app-runtime.fnl`

**Interfaces:**
- Consumes: existing private registry/scheduler/input/assets/logging helpers in `standalone-app-runtime.fnl`.
- Produces:
  - `Services.copy-list(items: table) -> table`
  - `Services.make-registry(label: string) -> registry`
  - `Services.make-scheduler(opts?: table) -> scheduler`
  - `Services.make-input(opts?: table) -> input`
  - `Services.make-assets(opts?: table) -> assets`
  - `Services.make-logging(opts?: table) -> logging`

- [ ] **Step 1: Write failing shared-service tests**

Create `assets/lua/tests/test-app-host-services.fnl` with tests equivalent to:

```fennel
(local Services (require :app-host.services))

(fn test-registry_register_unregister_list_clear []
  (local registry (Services.make-registry "widgets"))
  (local item {:id :a})
  (assert (= (registry:register item) item))
  (assert (= (# (registry:list)) 1))
  (assert (= (registry:unregister item) true))
  (assert (= (# (registry:list)) 0))
  (registry:register item)
  (assert (= (registry:clear) true))
  (assert (= (# (registry:list)) 0)))

(fn test-scheduler_pause_update_and_step []
  (local scheduler (Services.make-scheduler))
  (local calls [])
  (local facet {:update (fn [_self delta] (table.insert calls delta))})
  (scheduler:register facet)
  (scheduler:update 16)
  (scheduler:set-paused true)
  (scheduler:update 32)
  (scheduler:step 48)
  (assert (= (# calls) 2))
  (assert (= (. calls 1) 16))
  (assert (= (. calls 2) 48)))

(fn test-input_dispatches_registered_handlers []
  (local input (Services.make-input))
  (var seen nil)
  (local handler {:key-down (fn [_self payload] (set seen payload.key))})
  (input:register handler)
  (input:dispatch :key-down {:key 81})
  (assert (= seen 81)))
```

Run and expect failure because `app-host.services` does not exist yet:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-app-host-services:main
```

- [ ] **Step 2: Add explicit-error tests**

Extend the test file with invalid payload checks:

```fennel
(fn assert-error-contains [f expected]
  (local (ok err) (pcall f))
  (assert (= ok false))
  (assert (string.find (tostring err) expected 1 true)))

(fn test-services_fail_loudly_on_invalid_payloads []
  (local registry (Services.make-registry "widgets"))
  (assert-error-contains #(registry:register nil) "widgets:register requires a facet")
  (local scheduler (Services.make-scheduler))
  (assert-error-contains #(scheduler:register nil) "scheduler:register requires a facet table")
  (local input (Services.make-input))
  (assert-error-contains #(input:register nil) "input:register requires a handler table"))
```

- [ ] **Step 3: Implement `app-host/services.fnl`**

Move the generic helper logic from `standalone-app-runtime.fnl` into `services.fnl`. Export exactly:

```fennel
{:copy-list copy-list
 :make-registry make-registry
 :make-scheduler make-scheduler
 :make-input make-input
 :make-assets make-assets
 :make-logging make-logging}
```

Keep error prefixes explicit, e.g. `[app-host.services] scheduler:register requires a facet table`.

- [ ] **Step 4: Migrate standalone runtime to shared services**

Replace private service helpers in `standalone-app-runtime.fnl` with `Services.make-*` calls. Preserve `StandaloneRuntime.create-host(opts)` shape and existing standalone tests.

- [ ] **Step 5: Validate Task 1**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/services.fnl --file assets/lua/standalone-app-runtime.fnl --file assets/lua/tests/test-app-host-services.fnl --file assets/lua/tests/test-standalone-app-runtime.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-app-host-services:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-standalone-app-runtime:main
```

- [ ] **Step 6: Commit after review passes**

```bash
git add assets/lua/app-host/services.fnl assets/lua/standalone-app-runtime.fnl assets/lua/tests/test-app-host-services.fnl assets/lua/tests/test-standalone-app-runtime.fnl
git commit -m "refactor(apps): share hosted app host services"
```

---

### Task 2: Space Host Capability Factory

**Files:**
- Create: `assets/lua/app-host/space-host.fnl`
- Create: `assets/lua/tests/test-app-host-space-host.fnl`
- Modify: `docs/dev/features/hosted-runtime-apps.md`

**Interfaces:**
- Consumes: `Services.make-registry`, `Services.make-scheduler`, `Services.make-input`, `Services.make-assets`, `Services.make-logging`.
- Produces:
  - `SpaceHost.create(opts: table) -> host`
  - `host:drop() -> nil`
  - optional adapter capabilities `host.hud`, `host.canvas`, `host.scene`
  - embedded `host.lifecycle:quit() -> any`

- [ ] **Step 1: Write failing tests for host capabilities and lifecycle quit**

Create `assets/lua/tests/test-app-host-space-host.fnl` with tests equivalent to:

```fennel
(local SpaceHost (require :app-host.space-host))

(fn test-space_host_exposes_required_services []
  (local runtime {})
  (local host (SpaceHost.create {:runtime runtime :app {}}))
  (each [_ name (ipairs [:viewport :surfaces :scheduler :input :inspectors :commands :assets :logging :lifecycle])]
    (assert (. host name)))
  (host:drop))

(fn test-embedded_quit_uses_close_callback []
  (var closed? false)
  (local host (SpaceHost.create {:runtime {} :app {} :on-quit (fn [_host] (set closed? true))}))
  (host.lifecycle:quit)
  (assert (= closed? true))
  (host:drop))
```

Run and expect failure because `app-host.space-host` does not exist.

- [ ] **Step 2: Add adapter proxy and cleanup tests**

Extend tests with fake HUD/canvas/scene objects:

```fennel
(fn fake-target []
  (local children [])
  {:children children
   :add-panel-child (fn [_self child] (table.insert children child) child)
   :remove-panel-child (fn [_self child]
                         (for [i (# children) 1 -1]
                           (when (= (. children i) child)
                             (table.remove children i))))})

(fn test_hud_adapter_adds_and_drops_owned_panel []
  (local hud (fake-target))
  (local host (SpaceHost.create {:runtime {} :app {:hud hud}}))
  (local child {:id :panel})
  (assert (= (host.hud:add-panel-child child) child))
  (assert (= (# hud.children) 1))
  (host:drop)
  (assert (= (# hud.children) 0)))
```

Add analogous canvas/scene proxy coverage for the existing API shape where feasible with fakes.

- [ ] **Step 3: Implement `SpaceHost.create`**

Implement `SpaceHost.create(opts)` so it:

- requires `opts.runtime`;
- uses `opts.app` or global `app` as the Space shell source;
- creates shared generic services;
- exposes optional `hud`, `canvas`, and `scene` adapters only when corresponding shell objects exist;
- tracks children created through adapters and removes them in `host:drop()` exactly once;
- implements `lifecycle:quit()` as `opts.on-quit(host)` when supplied, otherwise raises `[space-host] lifecycle:quit requires on-quit callback`.

- [ ] **Step 4: Document Space host capabilities**

Update `docs/dev/features/hosted-runtime-apps.md` with:

- embedded Space host capabilities;
- HUD/canvas/scene adapter ownership;
- embedded `lifecycle:quit` closes the mount, not the process;
- no hosted-vs-standalone mode flag.

- [ ] **Step 5: Validate Task 2**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/space-host.fnl --file assets/lua/tests/test-app-host-space-host.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-app-host-space-host:main
```

- [ ] **Step 6: Commit after review passes**

```bash
git add assets/lua/app-host/space-host.fnl assets/lua/tests/test-app-host-space-host.fnl docs/dev/features/hosted-runtime-apps.md
git commit -m "feat(apps): add Space host capabilities"
```

---

### Task 3: Workspace Mount and Presentation Composition

**Files:**
- Create: `assets/lua/app-host/workspace-mount.fnl`
- Create: `assets/lua/tests/test-hosted-app-workspace-mount.fnl`
- Modify: `assets/lua/hosted-app-runtime.fnl`
- Modify: `assets/lua/activity-presentation.fnl`
- Modify: `examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl`

**Interfaces:**
- Consumes: `SpaceHost.create(opts) -> host`, `HostedRuntime.mount(opts) -> controller`, `controller:render-targets() -> table[]`, `controller:drop() -> nil`.
- Produces:
  - `WorkspaceMount.mount(opts: table) -> mount`
  - `mount.controller`
  - `mount.host`
  - `mount:render-targets() -> table[]`
  - `mount:drop() -> nil`
  - `HostedRuntime.mount-in-workspace(opts: table) -> mount`

- [ ] **Step 1: Write failing mount registration test**

Create `assets/lua/tests/test-hosted-app-workspace-mount.fnl` with a fake module returning one presentation target. Assert:

```fennel
(local WorkspaceMount (require :app-host.workspace-mount))

(fn test_mount_registers_without_replacing_runtime []
  (local runtime {:presentation {:render-targets (fn [_self] [{:kind :scene :id :base}])}})
  (local module {:create (fn [_host]
                           {:presentation {:render-targets (fn [_self] [{:kind :hud :id :hosted}])}
                            :lifecycle {:drop (fn [_self] nil)}})})
  (local app-shell {})
  (local mount (WorkspaceMount.mount {:runtime runtime :app app-shell :module module}))
  (assert (= (. runtime :hosted-app-mounts 1) mount))
  (assert (= (# (mount:render-targets)) 1))
  (mount:drop)
  (assert (= (# runtime.hosted-app-mounts) 0)))
```

- [ ] **Step 2: Write failing presentation composition test**

Add a test using `ActivityPresentation.for-runtime(runtime)` asserting base targets remain and hosted targets appear after base scene/canvas and before HUD where applicable. Use fake runtime fields consistent with existing `test-activity-presentation.fnl` patterns.

- [ ] **Step 3: Implement `WorkspaceMount.mount`**

Implement mount lifecycle:

- ensure `runtime.hosted-app-mounts` sequential list exists;
- create `SpaceHost` with `on-quit` wired to `mount:drop()`;
- call `HostedRuntime.mount {:module module :module-name module-name :host host}`;
- append mount to runtime list;
- `drop` removes mount from runtime list, then drops controller, then drops host;
- drop is idempotent.

- [ ] **Step 4: Extend `hosted-app-runtime.fnl`**

Preserve existing `mount(opts)`. Add:

```fennel
(fn mount-in-workspace [opts]
  ((require :app-host.workspace-mount).mount opts))
```

Export both `:mount` and `:mount-in-workspace`.

- [ ] **Step 5: Extend `activity-presentation.fnl`**

When collecting render targets for a runtime, include each non-dropped hosted app mount’s `:render-targets()` after existing scene/canvas targets and before the HUD target. Do not mutate renderers or active runtime identity.

- [ ] **Step 6: Validate with Snake hosted test**

Extend `examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl` to mount Snake through `HostedRuntime.mount-in-workspace` with a fake runtime and assert hosted targets are contributed then removed after drop.

- [ ] **Step 7: Validate Task 3**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/workspace-mount.fnl --file assets/lua/hosted-app-runtime.fnl --file assets/lua/activity-presentation.fnl --file assets/lua/tests/test-hosted-app-workspace-mount.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-hosted-app-workspace-mount:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-hosted-runtime:main
```

- [ ] **Step 8: Commit after review passes**

```bash
git add assets/lua/app-host/workspace-mount.fnl assets/lua/hosted-app-runtime.fnl assets/lua/activity-presentation.fnl assets/lua/tests/test-hosted-app-workspace-mount.fnl examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl
git commit -m "feat(apps): mount hosted apps in workspaces"
```

---

### Task 4: Minimal Hosted App Control UI

**Files:**
- Create: `assets/lua/app-host/workspace-panel.fnl`
- Create: `assets/lua/tests/test-hosted-app-workspace-panel.fnl`
- Modify: `docs/dev/features/hosted-runtime-apps.md`

**Interfaces:**
- Consumes: `WorkspaceMount.mount(opts) -> mount`, HUD `add-panel-child/remove-panel-child`, controller methods `set-paused`, `step`, `drop`.
- Produces:
  - `WorkspacePanel.open(opts: table) -> panel-session`
  - `panel-session.mount`
  - `panel-session:pause() -> any`
  - `panel-session:resume() -> any`
  - `panel-session:step(delta-ms?: number) -> any`
  - `panel-session:close() -> nil`

- [ ] **Step 1: Write failing panel session tests**

Create `assets/lua/tests/test-hosted-app-workspace-panel.fnl` with fake HUD and fake module/controller behavior. Assert:

- opening adds exactly one HUD panel child;
- pause calls `controller:set-paused true`;
- resume calls `controller:set-paused false`;
- step calls `controller:step`;
- close removes the HUD child and drops the mount exactly once;
- missing HUD fails loudly.

- [ ] **Step 2: Implement `WorkspacePanel.open`**

Implement a minimal panel session that:

- requires `opts.app.hud` or global `app.hud`;
- calls `WorkspaceMount.mount(opts)`;
- adds one HUD panel child containing a simple table/controller descriptor acceptable to existing HUD tests;
- exposes pause/resume/step/close methods;
- makes close idempotent.

Do not implement generic inspector/editor rendering in this task.

- [ ] **Step 3: Document minimal controls**

Update `docs/dev/features/hosted-runtime-apps.md` to describe the minimal workspace panel and state that inspector/editor rendering is a follow-up subproject.

- [ ] **Step 4: Validate Task 4**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/workspace-panel.fnl --file assets/lua/tests/test-hosted-app-workspace-panel.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-hosted-app-workspace-panel:main
```

- [ ] **Step 5: Commit after review passes**

```bash
git add assets/lua/app-host/workspace-panel.fnl assets/lua/tests/test-hosted-app-workspace-panel.fnl docs/dev/features/hosted-runtime-apps.md
git commit -m "feat(apps): add hosted app workspace panel"
```

---

### Task 5: Final Validation

**Files:**
- Review: all files changed by Tasks 1 through 4.

**Interfaces:**
- Consumes: shared services, Space host adapters, workspace mount, presentation composition, workspace panel, Snake hosted runtime.
- Produces: validation evidence for finishing the branch.

- [ ] **Step 1: Run compile checks**

Run:

```bash
make fennel-check
```

Run explicit example checks:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets FENNEL_PATH='$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl' FENNEL_MACRO_PATH='$(pwd)/examples/snake/assets/lua/?.fnl;$(pwd)/examples/snake/assets/lua/?/init.fnl;$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl' ./build/space -m tools.fennel-check:main -- --target files --file examples/snake/assets/lua/tests/test-snake-hosted-runtime.fnl
```

- [ ] **Step 2: Run constraints**

```bash
make constraints
```

- [ ] **Step 3: Run focused tests**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-app-host-services:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-app-host-space-host:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-hosted-app-workspace-mount:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-hosted-app-workspace-panel:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-standalone-app-runtime:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-hosted-runtime:main
```

- [ ] **Step 4: Run broader relevant suite**

Because this changes presentation/runtime composition, run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.fast:main
```

- [ ] **Step 5: Confirm clean tree**

```bash
git status --short
```

Expected: no uncommitted changes after reviewed corrections are committed.
