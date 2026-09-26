# Hosted App Inspector Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a first read-only hosted app inspector panel slice that exposes mounted app inspector/command registry snapshots without adding app-specific APIs or editing behavior.

**Architecture:** Add a focused `app-host.workspace-inspector-snapshot` helper that converts host inspector and command registries into plain snapshot data. Extend `app-host.workspace-panel` descriptors/sessions to expose the snapshot while preserving the existing mount/control/teardown lifecycle. Keep visual rendering minimal in this slice and document editor/command execution follow-ups.

**Tech Stack:** Space Fennel, `app-host` registry services, hosted workspace panel, HUD panel descriptors, focused Fennel tests, `tools.fennel-check`, `make constraints`.

## Global Constraints

- Add a first read-only hosted app inspector panel slice.
- Preserve `WorkspacePanel.open(opts)` and the existing session API: `mount`, `pause`, `resume`, `step`, and idempotent `close`.
- Read inspector and command data from the embedded host registries.
- Represent plain-data inspectors in a stable snapshot shape.
- Surface inspector read failures explicitly instead of silently omitting them.
- Keep command entries metadata-only; do not execute commands in this slice.
- Preserve existing workspace mount ownership and teardown behavior.
- Document the new read-only inspector capability and follow-up boundaries.
- Do not add a new hosted app entrypoint method.
- Do not add app-specific inspector methods or Snake-specific UI.
- Do not add mutation/editing controls.
- Do not execute commands from the panel.
- Do not introduce a custom moldable renderer protocol.
- Do not add graph nodes, graph persistence, launcher UX, app discovery, or persistent editor state.
- Do not change generic runtime-controller inspector/command facet semantics unless tests reveal a bug in the existing registry contract.
- Missing `host.inspectors:list` or `host.commands:list` fails loudly with an `app-host.workspace-inspector-snapshot` error.
- Inspector `read` failures are captured as explicit `:error` entries so one bad inspector does not hide the rest of the mounted app state.
- Workspace panel mount/HUD failure behavior remains unchanged: HUD add failure drops the mount; missing HUD fails before mounting.
- Widget/UI code must follow Space Fennel UI guidance: builders receive context, widgets own explicit layouts, composite widgets drop children, and missing required context fails loudly.
- Use `local` instead of `let` in Fennel.
- Use factory functions instead of `.new` constructors.
- For Fennel work, compile-check first with project-native `tools.fennel-check`/`make fennel-check`, then run `make constraints`, then focused Fennel tests.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- For direct test runs, set `SKIP_KEYRING_TESTS=1`, `XDG_DATA_HOME=/tmp/space/tests/xdg-data`, `SPACE_DISABLE_AUDIO=1`, `SPACE_ASSETS_PATH=$(pwd)/assets`, `FENNEL_PATH=$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl`, and the same value for `FENNEL_MACRO_PATH`.

---

## File Structure

- `assets/lua/app-host/workspace-inspector-snapshot.fnl`: new helper that validates host registries and returns plain snapshot data for inspectors and commands.
- `assets/lua/tests/test-app-host-workspace-inspector-snapshot.fnl`: focused tests for snapshot extraction, read errors, unsupported inspectors, command metadata, and malformed registry failures.
- `assets/lua/app-host/workspace-panel.fnl`: add snapshot access to the existing descriptor/session while preserving controls and teardown.
- `assets/lua/tests/test-hosted-app-workspace-panel.fnl`: extend existing workspace panel tests for snapshot access and regression coverage.
- `docs/dev/features/hosted-runtime-apps.md`: document read-only inspector snapshot behavior and explicit non-goals.

---

### Task 1: Inspector Snapshot Helper

**Files:**
- Create: `assets/lua/app-host/workspace-inspector-snapshot.fnl`
- Create: `assets/lua/tests/test-app-host-workspace-inspector-snapshot.fnl`

**Interfaces:**
- Produces: `Snapshot.read-host(host: table) -> snapshot: table`.
- Snapshot shape:
  - `snapshot.inspectors`: sequential list of `{:id any :title string|nil :status :ok|:error|:unsupported :data any|nil :error string|nil}`.
  - `snapshot.commands`: sequential list of `{:id any :title string|nil :description string|nil :status :metadata}`.
- Consumes host registries with `host.inspectors:list()` and `host.commands:list()`.

- [ ] **Step 1: Write focused snapshot test scaffolding**

Create `assets/lua/tests/test-app-host-workspace-inspector-snapshot.fnl`:

```fennel
(local Runner (require :tests/runner))
(local Snapshot (require :app-host.workspace-inspector-snapshot))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn assert-error-contains [f expected]
  (local (ok err) (pcall f))
  (assert (= ok false) "expected call to fail")
  (assert (string.find (tostring err) expected 1 true)
          (.. "expected error to contain " expected ", got " (tostring err))))

(fn registry [items]
  {:list (fn [_self]
           (local out [])
           (each [_ item (ipairs items)]
             (table.insert out item))
           out)})

(fn host-with [inspectors commands]
  {:inspectors (registry inspectors)
   :commands (registry commands)})

(fn main []
  (Runner.run-tests {:name "app-host-workspace-inspector-snapshot" :tests tests}))

{:main main :tests tests}
```

- [ ] **Step 2: Add failing tests for successful inspector and command metadata snapshots**

Add:

```fennel
(fn test-readable-inspector-and-command-metadata []
  (var command-ran? false)
  (local host
    (host-with [{:id :snake-state
                 :title "Snake State"
                 :read (fn [_self]
                         {:score 3 :game-over? false})}]
               [{:id :restart
                 :title "Restart"
                 :description "Restart the app"
                 :run (fn [_self]
                        (set command-ran? true))}]))
  (local snapshot (Snapshot.read-host host))
  (assert (= (# snapshot.inspectors) 1) "snapshot should include inspector")
  (assert (= (. snapshot.inspectors 1 :id) :snake-state))
  (assert (= (. snapshot.inspectors 1 :title) "Snake State"))
  (assert (= (. snapshot.inspectors 1 :status) :ok))
  (assert (= (. snapshot.inspectors 1 :data :score) 3))
  (assert (= (# snapshot.commands) 1) "snapshot should include command metadata")
  (assert (= (. snapshot.commands 1 :id) :restart))
  (assert (= (. snapshot.commands 1 :status) :metadata))
  (assert (= command-ran? false) "snapshot must not execute commands"))

(add-test "readable inspector and command metadata" test-readable-inspector-and-command-metadata)
```

Run and expect failure because the module does not exist:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-inspector-snapshot:main
```

- [ ] **Step 3: Add failing tests for unsupported inspectors, read errors, and malformed registries**

Add:

```fennel
(fn test-unsupported-and-error-inspectors-are-explicit []
  (local host
    (host-with [{:id :metadata-only :title "Metadata Only"}
                {:id :broken
                 :title "Broken"
                 :read (fn [_self]
                         (error "inspector failed"))}]
               []))
  (local snapshot (Snapshot.read-host host))
  (assert (= (# snapshot.inspectors) 2))
  (assert (= (. snapshot.inspectors 1 :status) :unsupported))
  (assert (= (. snapshot.inspectors 2 :status) :error))
  (assert (string.find (. snapshot.inspectors 2 :error) "inspector failed" 1 true)))

(fn test-missing-registries-fail-loudly []
  (assert-error-contains #(Snapshot.read-host {}) "inspectors")
  (assert-error-contains #(Snapshot.read-host {:inspectors (registry [])}) "commands"))

(add-test "unsupported and error inspectors are explicit" test-unsupported-and-error-inspectors-are-explicit)
(add-test "missing registries fail loudly" test-missing-registries-fail-loudly)
```

- [ ] **Step 4: Implement `workspace-inspector-snapshot.fnl`**

Create `assets/lua/app-host/workspace-inspector-snapshot.fnl`:

```fennel
(fn snapshot-error [message]
  (error (.. "[app-host.workspace-inspector-snapshot] " message)))

(fn require-list [host registry-name]
  (local registry (. host registry-name))
  (when (not (= (type registry) :table))
    (snapshot-error (.. (tostring registry-name) " registry is required")))
  (local list-fn registry.list)
  (when (not (= (type list-fn) :function))
    (snapshot-error (.. (tostring registry-name) " registry requires list")))
  (list-fn registry))

(fn inspector-entry [facet]
  (if (= (type facet.read) :function)
      (do
        (local (ok result) (pcall facet.read facet))
        (if ok
            {:id facet.id :title facet.title :status :ok :data result}
            {:id facet.id :title facet.title :status :error :error (tostring result)}))
      {:id facet.id :title facet.title :status :unsupported}))

(fn command-entry [facet]
  {:id facet.id
   :title facet.title
   :description facet.description
   :status :metadata})

(fn read-host [host]
  (when (not (= (type host) :table))
    (snapshot-error "read-host requires host table"))
  (local inspector-facets (require-list host :inspectors))
  (local command-facets (require-list host :commands))
  (local inspectors [])
  (each [_ facet (ipairs inspector-facets)]
    (table.insert inspectors (inspector-entry facet)))
  (local commands [])
  (each [_ facet (ipairs command-facets)]
    (table.insert commands (command-entry facet)))
  {:inspectors inspectors :commands commands})

{:read-host read-host}
```

- [ ] **Step 5: Validate and commit Task 1**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/workspace-inspector-snapshot.fnl --file assets/lua/tests/test-app-host-workspace-inspector-snapshot.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-inspector-snapshot:main
```

Commit:

```bash
git add assets/lua/app-host/workspace-inspector-snapshot.fnl assets/lua/tests/test-app-host-workspace-inspector-snapshot.fnl
git commit -m "feat(apps): add hosted app inspector snapshots"
```

---

### Task 2: Workspace Panel Snapshot Access

**Files:**
- Modify: `assets/lua/app-host/workspace-panel.fnl`
- Modify: `assets/lua/tests/test-hosted-app-workspace-panel.fnl`

**Interfaces:**
- Consumes: `Snapshot.read-host(host) -> snapshot` from Task 1.
- Produces: existing `WorkspacePanel.open(opts) -> session`, plus `session:read-inspector-snapshot() -> snapshot` and descriptor/widget snapshot access.

- [ ] **Step 1: Extend fake mount with host registries**

In `test-hosted-app-workspace-panel.fnl`, add a `registry` helper and update `make-fake-mount` so each fake mount has `host.inspectors` and `host.commands` registries:

```fennel
(fn registry [items]
  {:list (fn [_self]
           (local out [])
           (each [_ item (ipairs items)]
             (table.insert out item))
           out)})
```

Update `make-fake-mount` to include:

```fennel
:host {:inspectors (registry [{:id :state
                               :title "State"
                               :read (fn [_self] {:value 42})}])
       :commands (registry [{:id :restart :title "Restart"}])}
```

- [ ] **Step 2: Add failing session and descriptor snapshot tests**

Add:

```fennel
(fn test-session_exposes_read_only_inspector_snapshot []
  (local hud (make-fake-hud))
  (local fake-mount (make-fake-mount))
  (local fixture (install-panel-module fake-mount))
  (local session (fixture.WorkspacePanel.open (panel-opts hud)))
  (local snapshot (session:read-inspector-snapshot))
  (assert (= (. snapshot.inspectors 1 :id) :state))
  (assert (= (. snapshot.inspectors 1 :data :value) 42))
  (assert (= (. snapshot.commands 1 :id) :restart))
  (fixture:restore))

(fn test_descriptor_and_built_widget_expose_snapshot_reader []
  (local hud (make-builder-hud))
  (local fake-mount (make-fake-mount))
  (local fixture (install-panel-module fake-mount))
  (local session (fixture.WorkspacePanel.open (panel-opts hud)))
  (local descriptor-snapshot (hud.descriptor:read-inspector-snapshot))
  (local widget-snapshot ((. hud.children 1 :hosted-app-workspace-panel):read-inspector-snapshot))
  (assert (= (. descriptor-snapshot.inspectors 1 :id) :state))
  (assert (= (. widget-snapshot.inspectors 1 :id) :state))
  (session:close)
  (fixture:restore))
```

Add them to the test list. Run `tests.test-hosted-app-workspace-panel:main` and expect failure because the method does not exist.

- [ ] **Step 3: Update `workspace-panel.fnl` to add snapshot access**

Require the snapshot helper:

```fennel
(local Snapshot (require :app-host.workspace-inspector-snapshot))
```

Inside `open`, add:

```fennel
(fn read-inspector-snapshot [_self]
  (Snapshot.read-host mount.host))
```

Add `:read-inspector-snapshot read-inspector-snapshot` to both `session` and `descriptor`.

- [ ] **Step 4: Preserve widget descriptor snapshot access**

Update `make-panel-widget` so the widget keeps the descriptor with snapshot reader intact:

```fennel
{:layout layout
 :drop (fn [self]
         (self.layout:drop))
 :hosted-app-workspace-panel descriptor}
```

If this shape already exists, leave it unchanged and rely on the new descriptor method.

- [ ] **Step 5: Validate existing lifecycle tests still pass**

Run the full workspace panel focused test; it must still pass the existing tests for pause/resume/step, close idempotence, HUD add failure cleanup, and missing HUD failure.

- [ ] **Step 6: Validate and commit Task 2**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/workspace-panel.fnl --file assets/lua/tests/test-hosted-app-workspace-panel.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-inspector-snapshot:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hosted-app-workspace-panel:main
```

Commit:

```bash
git add assets/lua/app-host/workspace-panel.fnl assets/lua/tests/test-hosted-app-workspace-panel.fnl
git commit -m "feat(apps): expose inspector snapshots from workspace panel"
```

---

### Task 3: Docs and Final Validation

**Files:**
- Modify: `docs/dev/features/hosted-runtime-apps.md`

**Interfaces:**
- Consumes: snapshot helper and workspace panel snapshot access from Tasks 1 and 2.
- Produces: docs and validation evidence for branch finishing.

- [ ] **Step 1: Update hosted runtime docs**

In `docs/dev/features/hosted-runtime-apps.md`, replace the “minimal workspace controls” follow-up paragraph with content that says:

```markdown
The workspace panel also exposes a read-only inspector snapshot from the embedded host registries. Snapshot rows include readable inspector data, explicit inspector read errors, unsupported inspector markers, and command metadata. The panel does not execute commands or mutate app state.

Command execution, editable controls, custom moldable inspector renderers, graph integration, persistent app discovery, and launcher UX remain follow-up subprojects.
```

- [ ] **Step 2: Run final compile and constraints**

Run:

```bash
make fennel-check
make constraints
```

- [ ] **Step 3: Run focused tests**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-inspector-snapshot:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hosted-app-workspace-panel:main
```

- [ ] **Step 4: Run adjacent hosted runtime/workspace tests**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hosted-app-workspace-mount:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-runtime-controller:main
```

- [ ] **Step 5: Confirm acceptance criteria and clean tree**

Confirm in the report:

- workspace sessions expose read-only inspector snapshots;
- readable inspector data appears in stable snapshot shape;
- inspector read failures appear as explicit error entries;
- commands are metadata-only and not executed;
- existing workspace panel controls/teardown pass;
- no new app entrypoint or editor mutation protocol was added.

Run:

```bash
git status --short
```

Expected: clean tree after reviewed commits.

- [ ] **Step 6: Commit docs if not already committed**

If Task 3 made only docs changes and validation passed, commit:

```bash
git add docs/dev/features/hosted-runtime-apps.md
git commit -m "docs(apps): document hosted inspector snapshots"
```
