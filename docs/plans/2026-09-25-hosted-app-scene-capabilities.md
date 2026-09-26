# Hosted App Scene Capabilities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a generic `host.scene` capability for hosted apps to create, transform, query, and clean up app-owned scene objects without depending on Space default-app or sandbox internals.

**Architecture:** Introduce a focused `app-host.scene-capability` service that owns app-created handles and supports registry-backed queries. Wire this service into standalone hosts and Space embedded hosts. The Space host adapter proxies available scene operations such as panel/object creation and terrain query methods while keeping app-facing handles semantic and owned by the capability.

**Tech Stack:** Space Fennel, app-host services, Space host capabilities, existing scene add/remove/query APIs, focused Fennel tests, `tools.fennel-check`, `make constraints`.

## Global Constraints

- Public app contract remains `metadata`, `create(host)`, and optional `main`.
- App code must not branch on hosted-vs-standalone mode.
- New scene/game features must use `host.scene` capabilities, not new required app entrypoint methods.
- Do not expose raw `app.scene`, sandbox activity internals, graph modules, or default-app-only modules to hosted app code.
- `host.scene` methods operate on host-owned handles, not raw Space entities.
- Missing `host.scene` must fail through `Capabilities.require` in apps that need scene support.
- Unsupported spawn kinds must fail loudly.
- Invalid handles passed to `despawn`, `set-transform`, or `get-transform` must fail loudly unless explicitly documented as idempotent cleanup.
- `drop()` must remove owned objects exactly once and surface cleanup failures.
- Query methods must not silently convert backend errors into empty results.
- Standalone hosts must provide the same `host.scene` capability shape as embedded hosts for app logic tests.
- Do not implement 3D Snake in this subproject.
- Do not implement generic moldable inspector/editor UI in this subproject.
- Do not implement a full physics query abstraction beyond minimal object/terrain queries that existing Space APIs can support.
- Use `local` instead of `let` in new Fennel code.
- Use factory functions instead of `.new` constructors.
- Validate Fennel work with project-native `tools.fennel-check`, then `make constraints`, then focused Fennel tests.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- Disable audio for CLI tests with `SPACE_DISABLE_AUDIO=1`; set `XDG_DATA_HOME=/tmp/space/tests/xdg-data`; set `SKIP_KEYRING_TESTS=1`.
- Build first with `make build` timeout `14400000` when `./build/space` is missing or stale.

---

## File Structure

- `assets/lua/app-host/scene-capability.fnl`: generic scene capability service with handle ownership, transform storage, semantic object queries, terrain query delegation, and cleanup.
- `assets/lua/app-host/space-host.fnl`: creates `host.scene` using `scene-capability` when a Space scene target is available; preserves HUD/canvas adapters.
- `assets/lua/standalone-app-runtime.fnl`: creates a standalone/fake-backed `host.scene` capability.
- `docs/dev/features/hosted-runtime-apps.md`: documents the `host.scene` capability and policies.
- Tests:
  - `assets/lua/tests/test-app-host-scene-capability.fnl`
  - `assets/lua/tests/test-app-host-space-host.fnl`
  - `assets/lua/tests/test-standalone-app-runtime.fnl`
  - existing `assets/lua/tests/test-hosted-app-workspace-mount.fnl`

---

### Task 1: Generic Scene Capability Service

**Files:**
- Create: `assets/lua/app-host/scene-capability.fnl`
- Create: `assets/lua/tests/test-app-host-scene-capability.fnl`

**Interfaces:**
- Produces `SceneCapability.create(opts?: table) -> scene-service`.
- `scene-service` methods:
  - `spawn(self, spec: table) -> handle: table`
  - `despawn(self, handle: table) -> boolean`
  - `set-transform(self, handle: table, transform: table) -> table`
  - `get-transform(self, handle: table) -> table`
  - `list-owned(self) -> table[]`
  - `query-volume(self, bounds: table, opts?: table) -> table[]`
  - `raycast-terrain(self, ray: table, opts?: table) -> table|nil`
  - `height-at(self, point: table, opts?: table) -> number|nil`
  - `drop(self) -> nil`

- [ ] **Step 1: Write failing tests for spawn/list/transform/drop**

Create `assets/lua/tests/test-app-host-scene-capability.fnl` with tests equivalent to:

```fennel
(local SceneCapability (require :app-host.scene-capability))

(fn test-spawn_transform_list_and_drop []
  (local scene (SceneCapability.create {}))
  (local handle (scene:spawn {:kind :custom
                              :id :snake-head
                              :tags [:snake :head]
                              :position [1 2 3]
                              :size [1 1 1]}))
  (assert (= handle.id :snake-head))
  (assert (= handle.kind :custom))
  (assert (= (# (scene:list-owned)) 1))
  (scene:set-transform handle {:position [4 5 6] :rotation nil :size [2 2 2]})
  (local transform (scene:get-transform handle))
  (assert (= (. transform.position 1) 4))
  (scene:drop)
  (assert (= (# (scene:list-owned)) 0)))
```

Run and expect failure because `app-host.scene-capability` does not exist:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-app-host-scene-capability:main
```

- [ ] **Step 2: Write failing tests for query policies and errors**

Extend the test file with:

```fennel
(fn assert-error-contains [f expected]
  (local (ok err) (pcall f))
  (assert (= ok false))
  (assert (string.find (tostring err) expected 1 true)))

(fn test-query_volume_filters_by_tags []
  (local scene (SceneCapability.create {}))
  (scene:spawn {:kind :custom :id :wall :tags [:solid :wall] :position [0 0 0] :size [1 1 1]})
  (scene:spawn {:kind :custom :id :food :tags [:pickup :food] :position [5 0 0] :size [1 1 1]})
  (local hits (scene:query-volume {:center [0 0 0] :size [2 2 2]} {:tags [:solid]}))
  (assert (= (# hits) 1))
  (local hit (. hits 1))
  (assert (= hit.id :wall)))

(fn test-invalid_handles_and_unsupported_kinds_fail_loudly []
  (local scene (SceneCapability.create {}))
  (assert-error-contains #(scene:spawn {:kind :unknown}) "unsupported spawn kind")
  (assert-error-contains #(scene:get-transform {:id :missing}) "invalid scene handle"))
```

- [ ] **Step 3: Write failing terrain delegation tests**

Add fake backend coverage:

```fennel
(fn test-terrain_queries_delegate_to_backend []
  (local backend {:height-at (fn [_self point _opts]
                               (+ (. point 1) (. point 3)))
                  :raycast-terrain (fn [_self ray _opts]
                                     {:hit? true :ray ray})})
  (local scene (SceneCapability.create {:backend backend}))
  (assert (= (scene:height-at [2 0 3]) 5))
  (local hit (scene:raycast-terrain {:origin [0 1 0] :direction [0 -1 0]}))
  (assert (= hit.hit? true)))
```

- [ ] **Step 4: Implement `scene-capability.fnl`**

Implement a registry-backed scene service:

- supported spawn kinds for Task 1: `:custom`, `:panel`, `:cube`;
- handle fields: `:id`, `:kind`, `:tags`, and private owned token fields if needed;
- transforms stored as plain tables with `:position`, `:rotation`, `:size`;
- `query-volume` returns semantic result tables with `:handle`, `:id`, `:kind`, `:tags`, `:solid?`, `:position`, `:source :owned`;
- tag filtering uses `opts.tags` as “any tag matches”;
- simple axis-aligned volume overlap over `:center`/`:size` or `:min`/`:max` bounds;
- `drop` despawns all owned handles exactly once;
- terrain methods delegate to backend methods when present and return `nil` when absent.

- [ ] **Step 5: Validate Task 1**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/scene-capability.fnl --file assets/lua/tests/test-app-host-scene-capability.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-app-host-scene-capability:main
```

- [ ] **Step 6: Commit after review passes**

```bash
git add assets/lua/app-host/scene-capability.fnl assets/lua/tests/test-app-host-scene-capability.fnl
git commit -m "feat(apps): add hosted scene capability"
```

---

### Task 2: Standalone Host Scene Capability

**Files:**
- Modify: `assets/lua/standalone-app-runtime.fnl`
- Modify: `assets/lua/tests/test-standalone-app-runtime.fnl`

**Interfaces:**
- Consumes: `SceneCapability.create(opts) -> scene-service` from Task 1.
- Produces: `StandaloneRuntime.create-host(opts).scene` with the documented scene capability shape.

- [ ] **Step 1: Write failing standalone host test**

Extend `assets/lua/tests/test-standalone-app-runtime.fnl` with:

```fennel
(fn test-create_host_exposes_scene_capability []
  (local host (StandaloneRuntime.create-host {:viewport {:x 0 :y 0 :width 100 :height 100}}))
  (assert host.scene)
  (local handle (host.scene:spawn {:kind :custom :id :standalone-object :position [0 0 0] :size [1 1 1]}))
  (assert (= handle.id :standalone-object))
  (assert (= (# (host.scene:list-owned)) 1))
  (host.scene:drop)
  (assert (= (# (host.scene:list-owned)) 0)))
```

- [ ] **Step 2: Implement standalone scene service wiring**

Require `app-host.scene-capability` in `standalone-app-runtime.fnl` and add:

```fennel
:scene (SceneCapability.create {:backend options.scene-backend})
```

to `create-host` output. Preserve all existing host fields and tests.

- [ ] **Step 3: Validate Task 2**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/standalone-app-runtime.fnl --file assets/lua/tests/test-standalone-app-runtime.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-standalone-app-runtime:main
```

- [ ] **Step 4: Commit after review passes**

```bash
git add assets/lua/standalone-app-runtime.fnl assets/lua/tests/test-standalone-app-runtime.fnl
git commit -m "feat(apps): expose scene capability in standalone host"
```

---

### Task 3: Embedded Space Scene Capability Adapter

**Files:**
- Modify: `assets/lua/app-host/space-host.fnl`
- Modify: `assets/lua/tests/test-app-host-space-host.fnl`
- Modify: `docs/dev/features/hosted-runtime-apps.md`

**Interfaces:**
- Consumes: `SceneCapability.create(opts) -> scene-service`.
- Produces: `SpaceHost.create(opts).scene` as a scene capability when `opts.app.scene` or global `app.scene` exists.

- [ ] **Step 1: Replace panel-adapter scene test with scene capability tests**

Update `assets/lua/tests/test-app-host-space-host.fnl` so scene no longer expects only `add-panel-child`. Add a fake scene backend:

```fennel
(fn fake-scene-target []
  (local panels [])
  {:panels panels
   :add-panel-child (fn [_self spec]
                      (local child {:spec spec})
                      (table.insert panels child)
                      child)
   :remove-panel-child (fn [_self child]
                         (for [i (# panels) 1 -1]
                           (when (= (. panels i) child)
                             (table.remove panels i))))
   :height-at (fn [_self point _opts] (+ (. point 1) (. point 3)))})
```

Assert `host.scene:spawn {:kind :panel ...}` creates a handle, adds one panel, `height-at` delegates, and `host:drop` removes the panel.

- [ ] **Step 2: Implement embedded scene backend in `space-host.fnl`**

Create scene capability with a backend wrapping `shell.scene`:

- `spawn` backend for `:panel` uses `scene:add-panel-child(spec)` and stores raw child for cleanup;
- `despawn` backend removes raw child through `scene:remove-panel-child(child)` when available;
- `height-at` delegates to `scene:height-at`, `scene:height-at-world-point`, or returns `nil` when absent;
- `raycast-terrain` delegates to `scene:raycast-terrain` when present or returns `nil` when absent.

Keep HUD and canvas as panel adapters. `host.scene` should be the scene capability, not a raw scene target.

- [ ] **Step 3: Preserve optional adapter behavior**

If no shell scene exists, `host.scene` is nil. Missing scene must fail only when an app explicitly requires it with `Capabilities.require host :scene`.

- [ ] **Step 4: Update hosted runtime docs**

Add a `Scene capability` section to `docs/dev/features/hosted-runtime-apps.md` describing:

- `host.scene` methods;
- app-owned handles;
- embedded proxy to Space scene APIs;
- standalone registry-backed parity;
- 3D Snake as a follow-up user of this capability.

- [ ] **Step 5: Validate Task 3**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/space-host.fnl --file assets/lua/tests/test-app-host-space-host.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-app-host-space-host:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-hosted-app-workspace-mount:main
```

- [ ] **Step 6: Commit after review passes**

```bash
git add assets/lua/app-host/space-host.fnl assets/lua/tests/test-app-host-space-host.fnl docs/dev/features/hosted-runtime-apps.md
git commit -m "feat(apps): wire scene capability into Space host"
```

---

### Task 4: Final Validation

**Files:**
- Review: all files changed by Tasks 1 through 3.

**Interfaces:**
- Consumes: scene capability service, standalone host scene capability, embedded Space scene capability adapter, hosted runtime docs.
- Produces: validation evidence for finishing the branch.

- [ ] **Step 1: Run compile checks**

Run:

```bash
make fennel-check
```

- [ ] **Step 2: Run constraints**

Run:

```bash
make constraints
```

- [ ] **Step 3: Run focused tests**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-app-host-scene-capability:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-app-host-space-host:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-standalone-app-runtime:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-hosted-app-workspace-mount:main
```

- [ ] **Step 4: Run broader relevant scene/host tests**

Because this changes scene host capability wiring, run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-scene-activity-slots:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-terrain-query:main
```

- [ ] **Step 5: Confirm clean tree**

Run:

```bash
git status --short
```

Expected: no uncommitted changes after reviewed corrections are committed.
