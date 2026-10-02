# Snackbar System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable, scoped Fennel snackbar system with a layout-native HUD default host in the center/middle region.

**Architecture:** Implement `SnackbarManager` as a widget-free state/policy object and `SnackbarHost` as the retained widget owner that subscribes to manager changes. Mount the default HUD host through `hud-layout.make-hud-builder` inside the center scene stack so HUD chrome and side rails are excluded by layout composition rather than offsets.

**Tech Stack:** Space Fennel widgets, retained `Layout`/`LayoutRoot`, `Signal`, `runtime-timers`, `Stack`, `Flex`, `Aligned`, `Padding`, `WrappedText`, `Button`, HUD Fennel tests.

## Global Constraints

- Provide a modern snackbar/toast system with clean manager, host, content, policy, and theme boundaries.
- Support independently scoped snackbar managers and hosts from the beginning. The global HUD snackbar scope is only the default, not the only supported usage.
- Default HUD placement is top-right and theme-configurable.
- Default HUD snackbars must not cover the control panel, status panel, top toolbar, or side rails/docks.
- Do not rely on static offsets to avoid HUD chrome; placement must follow dynamic layout bounds.
- Snackbar content may be simple text, text plus action buttons, or arbitrary widget content supplied by a builder.
- The manager must remain widget-free: it owns entries, queue policy, timers, handles, and change notifications, not rendered widgets.
- The host must own rendered snackbar widgets and drop them exactly once following Space widget ownership rules.
- Initial implementation should not include a scrollable snackbar host. Overflow is handled by policy, not by making transient snackbars a scroll view.
- Theme tokens should configure placement, spacing, padding, max width, default duration, visible/queued limits, and variant colors.
- Preserve existing HUD panel, overlay, command-hints, and layout behavior.
- Fennel code must use `local`, factory functions, widget build closures, explicit child ownership/drop, and no silent fallbacks for required context.
- If Fennel delimiter or parse errors occur, inspect the nearest enclosing form, simplify nested forms into helpers when needed, then rerun the compile check first.

---

## File Structure

- Create `assets/lua/snackbar-theme.fnl`: snackbar token defaults and resolution from `ctx.theme.snackbar`.
- Create `assets/lua/snackbar-manager.fnl`: widget-free snackbar scope state, normalization, policy, queueing, timers, handles, change subscriptions, and drop behavior.
- Create `assets/lua/snackbar-content.fnl`: default text/action card content builder.
- Create `assets/lua/snackbar-host.fnl`: retained host widget builder that renders visible manager entries, positions them inside its layout bounds, reconciles child widgets, and owns teardown.
- Create `assets/lua/snackbar.fnl`: public facade exporting `create-scope`, `SnackbarManager`, `SnackbarHost`, and theme helpers.
- Create `assets/lua/tests/test-snackbar-manager.fnl`: manager normalization, policy, queue, priority, replacement, timers, handles, and drop tests.
- Create `assets/lua/tests/test-snackbar-host.fnl`: host requirement, rendering, arbitrary content builder, action content, layout dirt, subscription, placement, and child-drop tests.
- Modify `assets/lua/hud-layout.fnl`: accept `:snackbar-host-builder`, mount it in the center/middle scene stack, return `:snackbar-host-root`, and update it.
- Modify `assets/lua/hud.fnl`: create the default snackbar scope, expose HUD convenience APIs, preserve the manager across theme/layout rebuilds, and drop the scope once.
- Modify `assets/lua/dark-theme.fnl`: add `:snackbar` tokens.
- Modify `assets/lua/light-theme.fnl`: add `:snackbar` tokens.
- Modify `assets/lua/tests/test-hud-layout.fnl`: prove snackbar host receives dynamic center/middle bounds excluding chrome, toolbar, and docks.
- Modify `assets/lua/tests/test-hud.fnl`: prove HUD convenience APIs delegate to the default manager and lifecycle drops the scope once.
- Modify `assets/lua/tests/fast.fnl`: register snackbar manager and host focused tests in the fast suite.
- Create `docs/dev/features/snackbar-system.md`: document scope, manager/host ownership, HUD placement, content paths, and no-scroll overflow policy.
- Modify `docs/dev/features/index.md`: link the snackbar system page.

---

### Task 1: Snackbar Theme Defaults and Manager Core

**Files:**
- Create: `assets/lua/snackbar-theme.fnl`
- Create: `assets/lua/snackbar-manager.fnl`
- Create: `assets/lua/tests/test-snackbar-manager.fnl`

**Interfaces:**
- Consumes: `Signal` from `assets/lua/signal.fnl`; `RuntimeTimers.Timeout(opts)` from `assets/lua/runtime-timers.fnl`.
- Produces: `SnackbarTheme.defaults() -> table`
- Produces: `SnackbarTheme.resolve(ctx-or-theme: table|nil, overrides: table|nil) -> table`
- Produces: `SnackbarManager(opts: table|nil) -> manager`
- Produces: `manager:show(request: table) -> handle`
- Produces: `manager:dismiss(id-or-handle: any, reason: any|nil) -> boolean`
- Produces: `manager:clear(reason: any|nil) -> integer`
- Produces: `manager:visible-entries() -> table`
- Produces: `manager:queued-entries() -> table`
- Produces: `manager:subscribe(listener: function) -> function`
- Produces: `manager:handle-for(id: any) -> handle|nil`
- Produces: `manager:drop() -> true`
- Produces: `handle.id: any`, `handle.entry: table`, `handle.dropped?: boolean`, `handle.drop-reason: keyword|nil`, `handle:dismiss(reason: any|nil) -> boolean`

- [ ] **Step 1: Write failing manager normalization and id tests**

  In `assets/lua/tests/test-snackbar-manager.fnl`, add tests that assert:
  - `manager:show {}` fails with `SnackbarManager.show requires :text, :message, or :content-builder`.
  - `manager:show {:message "Saved"}` normalizes `entry.text` to `"Saved"`.
  - `manager:show {:id "custom" :text "Saved"}` returns `handle.id == "custom"` and `entry.id == "custom"`.
  - generated ids are stable strings `snackbar-1`, `snackbar-2`.

- [ ] **Step 2: Run the focused test and verify failure**

  Run:
  ```bash
  make build
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snackbar-manager:main
  ```
  Expected: FAIL because `snackbar-manager` does not exist.

- [ ] **Step 3: Implement theme token defaults**

  Create `assets/lua/snackbar-theme.fnl` with these default tokens: `:placement :top-right`, `:spacing 0.3`, `:padding [0.45 0.35]`, `:max-width 18.0`, `:max-visible 3`, `:max-queued 20`, `:duration-ms 4000`, and variant tables for `:info`, `:success`, `:warning`, and `:error` with `:background`, `:foreground`, and `:border`.

  `resolve` must merge `ctx.theme.snackbar`, direct theme `.snackbar`, and explicit overrides without mutating any input table.

- [ ] **Step 4: Implement manager normalization, ids, handles, visible list, subscriptions, and drop guard**

  Create `assets/lua/snackbar-manager.fnl` so:
  - the constructor copies policy defaults from `SnackbarTheme.resolve(nil, opts)`;
  - public mutation after `drop` raises `SnackbarManager is dropped`;
  - `show` normalizes `:message` to `:text`, preserves `:metadata`, defaults `:variant` to `:info`, defaults `:duration-ms` from policy, and creates a stable handle;
  - `visible-entries` and `queued-entries` return copies;
  - `subscribe` returns a disconnect function;
  - every visible/queued change emits one change event.

- [ ] **Step 5: Verify manager normalization tests pass**

  Run:
  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snackbar-manager:main
  ```
  Expected: PASS for the normalization/id tests in this task.

---

### Task 2: Manager Policy, Queue, Replacement, Priority, and Timers

**Files:**
- Modify: `assets/lua/snackbar-manager.fnl`
- Modify: `assets/lua/tests/test-snackbar-manager.fnl`

**Interfaces:**
- Consumes: Task 1 `SnackbarManager(opts)` and handle API.
- Produces: policy opts `:max-visible`, `:max-queued`, `:newest-first?`, `:priority-order?`, `:overflow-mode`, `:default-duration-ms`.
- Produces: request fields `:priority`, `:duration-ms`, `:persistent?`, `:replace-key`, `:mode`.
- Produces: auto-dismiss only for visible non-persistent entries.

- [ ] **Step 1: Add failing policy tests**

  Extend `test-snackbar-manager.fnl` with tests for:
  - newest-first visible ordering with `:max-visible 3`;
  - max visible with queued overflow promotion after dismiss;
  - `:max-queued 1` causing the second queued overflow handle to have `dropped? == true` and `drop-reason == :queue-full`;
  - `:priority-order? true` ordering higher numeric priority before lower priority, with newer entries breaking priority ties;
  - `:replace-key` replacing an existing visible entry and an existing queued entry;
  - `:overflow-mode :drop` returning a dropped handle when visible capacity is full;
  - `:overflow-mode :replace` replacing the oldest visible entry when visible capacity is full.

- [ ] **Step 2: Add failing timer and drop tests**

  Extend the same test file with tests that:
  - reset `RuntimeTimers.clear` and `app.__runtime_timers`;
  - show two entries with `:max-visible 1`, first duration `100`, second duration `100`, emit `app.engine.events.updated:emit 100`, and assert the queued second entry only starts its timer after promotion;
  - show a persistent entry, emit elapsed time, and assert it remains visible;
  - call `manager:drop`, assert runtime timers are disconnected, and assert later `show`, `dismiss`, and `clear` each raise `SnackbarManager is dropped`.

- [ ] **Step 3: Run the focused test and verify failure**

  Run:
  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snackbar-manager:main
  ```
  Expected: FAIL on policy/timer assertions.

- [ ] **Step 4: Implement policy reconciliation**

  Update `snackbar-manager.fnl` so:
  - visible entries are sorted by newest-first unless `:newest-first? false`;
  - when `:priority-order? true`, visible and queued lists sort by priority descending then sequence descending;
  - `:queue` mode queues entries when visible is full;
  - queue-full returns a dropped handle with `:drop-reason :queue-full`;
  - `:drop` mode returns a dropped handle with `:drop-reason :visible-full`;
  - `:replace` overflow mode replaces the oldest visible entry;
  - `:replace-key` removes matching visible or queued entries before inserting the new entry.

- [ ] **Step 5: Implement timers and promotion**

  Update `snackbar-manager.fnl` so:
  - each non-persistent visible entry owns one `RuntimeTimers.Timeout`;
  - queued entries never start timers;
  - dismissing or replacing an entry cancels its timer;
  - dismissing a visible entry promotes queued entries until capacity is filled;
  - `drop` cancels all timers and clears subscriptions.

- [ ] **Step 6: Verify manager policy tests pass**

  Run:
  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snackbar-manager:main
  ```
  Expected: PASS.

---

### Task 3: Snackbar Host and Default Content

**Files:**
- Create: `assets/lua/snackbar-content.fnl`
- Create: `assets/lua/snackbar-host.fnl`
- Create: `assets/lua/snackbar.fnl`
- Create: `assets/lua/tests/test-snackbar-host.fnl`

**Interfaces:**
- Consumes: Task 1-2 `SnackbarManager`; Space widget builders.
- Produces: `SnackbarContent.default-builder(opts: table|nil) -> builder`
- Produces: `SnackbarHost(opts: table) -> builder`
- Produces: `Snackbar.create-scope(opts: table|nil) -> scope`
- Produces: `scope.manager`, `scope.host-builder`, `scope:drop() -> true`
- Produces: host opts `:manager`, `:theme`, `:placement`, `:spacing`, `:max-width`, `:content-builder`.
- Produces: entry `:content-builder` signature `(ctx: table, entry: table, handle: table) -> widget`.
- Produces: action callback signature `(entry: table, handle: table, button: table, event: table|nil) -> any`.

- [ ] **Step 1: Write failing host requirement and reconciliation tests**

  In `assets/lua/tests/test-snackbar-host.fnl`, add tests that assert:
  - `(SnackbarHost {})` build fails with `SnackbarHost requires :manager`;
  - a host renders one child for one visible entry and two children for two visible entries;
  - dismissing one visible entry drops that child exactly once;
  - `manager:clear` drops all rendered children exactly once;
  - host `drop` disconnects from manager and drops remaining children exactly once.

- [ ] **Step 2: Write failing content and layout tests**

  Add tests that assert:
  - simple text entries use the default content builder and produce a child with layout;
  - text/actions entries build one button per action, and invoking the button click invokes the action callback with `(entry handle button event)`;
  - an entry `:content-builder` is used instead of default content and receives `(ctx entry handle)`;
  - manager changes mark the host layout measure dirty;
  - `:placement :top-right` positions children inside the host layout’s right edge with configured spacing;
  - changing theme/host placement to `:top-left` positions children at the host layout’s left edge;
  - no `scroll-view` module or scroll host is required by `snackbar-host.fnl`.

- [ ] **Step 3: Run the focused host test and verify failure**

  Run:
  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snackbar-host:main
  ```
  Expected: FAIL because host/content/facade modules do not exist.

- [ ] **Step 4: Implement default content builder**

  Create `snackbar-content.fnl` using `Stack`, `Rectangle`, `Padding`, `Flex`, `FlexChild`, `WrappedText`, `Button`, and `TextStyle`.
  - Use `entry.text` for the message.
  - Use `entry.actions` as an array of descriptors with `:label` or `:text`, optional `:button-variant`, and optional `:on-click`.
  - Button click must call `action.on-click(entry, handle, button, event)` when present.
  - Use resolved snackbar variant colors for background, foreground, and border.
  - Do not dismiss automatically; action code can call `handle:dismiss`.

- [ ] **Step 5: Implement host widget builder**

  Create `snackbar-host.fnl` so:
  - building asserts `:manager`;
  - it subscribes to manager changes;
  - it reconciles rendered children by entry id;
  - it drops removed children exactly once;
  - it updates `layout.children` through `layout:add-child` and `layout:remove-child`;
  - it marks its own layout measure dirty after visible-set changes;
  - its custom layouter positions a non-scrollable stack within its assigned bounds for `:top-right`, `:top-left`, `:bottom-right`, and `:bottom-left`;
  - unsupported placement raises `Unsupported snackbar placement: <value>`;
  - `drop` disconnects the subscription and drops direct children exactly once.

- [ ] **Step 6: Implement public facade**

  Create `snackbar.fnl` exporting `:SnackbarManager`, `:SnackbarHost`, `:SnackbarTheme`, and `:create-scope`. `create-scope(opts)` must create one manager and one host builder configured with that manager, and `scope:drop()` must drop the manager once.

- [ ] **Step 7: Verify host tests pass**

  Run:
  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snackbar-host:main
  ```
  Expected: PASS.

---

### Task 4: HUD Layout-Native Host Mount

**Files:**
- Modify: `assets/lua/hud-layout.fnl`
- Modify: `assets/lua/tests/test-hud-layout.fnl`

**Interfaces:**
- Consumes: Task 3 `SnackbarHost(opts) -> builder`.
- Produces: `HudLayout.make-hud-builder(opts)` accepts optional `:snackbar-host-builder`.
- Produces: built HUD entity includes `:snackbar-host-root`.
- Produces: `:snackbar-host-root` is mounted inside the center scene stack above `float-root` and below `middle-overlay-root`.

- [ ] **Step 1: Add failing HUD layout tests**

  In `test-hud-layout.fnl`, add tests that:
  - pass a captured `snackbar-host-builder` to `HudLayout.make-hud-builder`;
  - include fixed control panel height `3`, status panel height `2`, left dock width `5`, right dock width `6`, and top toolbar height `4`;
  - lay out a `100 x 40` HUD;
  - assert `entity.snackbar-host-root.layout.size.x == 89` (`100 - 5 - 6`);
  - assert `entity.snackbar-host-root.layout.size.y == 31` (`40 - 3 - 2 - 4`);
  - assert the snackbar host x position equals the center column x position after the left dock;
  - assert the snackbar host y band excludes status panel, control panel, and toolbar;
  - assert `entity.middle-overlay-root` still exists and overlay tests continue to pass.

- [ ] **Step 2: Run focused HUD layout test and verify failure**

  Run:
  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-layout:main
  ```
  Expected: FAIL because `:snackbar-host-builder` is ignored.

- [ ] **Step 3: Mount the snackbar host in the scene stack**

  Update `hud-layout.fnl`:
  - read `local snackbar-host-builder options.snackbar-host-builder`;
  - build `local snackbar-host (and snackbar-host-builder (snackbar-host-builder ctx))`;
  - build `scene-stack` children as `[tiles, float, snackbar-host, middle-overlay]` when snackbar host exists and `[tiles, float, middle-overlay]` when absent;
  - include `:snackbar-host-root snackbar-host` in the returned entity;
  - call `snackbar-host:update` from the entity update path when present.

- [ ] **Step 4: Verify HUD layout tests pass**

  Run:
  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-layout:main
  ```
  Expected: PASS, including existing dock/toolbar/status tests.

---

### Task 5: HUD Default Scope, Convenience APIs, and Lifecycle

**Files:**
- Modify: `assets/lua/hud.fnl`
- Modify: `assets/lua/tests/test-hud.fnl`

**Interfaces:**
- Consumes: Task 3 `Snackbar.create-scope(opts)` and Task 4 `:snackbar-host-builder`.
- Produces: `hud.snackbar-scope`
- Produces: `hud.snackbar-manager`
- Produces: `hud:show-snackbar(request: table) -> handle`
- Produces: `hud:dismiss-snackbar(id-or-handle: any, reason: any|nil) -> boolean`
- Produces: `Hud:drop()` drops the snackbar scope exactly once.

- [ ] **Step 1: Add failing HUD convenience tests**

  In `test-hud.fnl`, add tests that:
  - `Hud {}` creates `hud.snackbar-manager`;
  - `hud:build-default` mounts `hud.entity.snackbar-host-root`;
  - `hud:show-snackbar {:text "Saved"}` adds one visible manager entry and returns a handle;
  - `hud:dismiss-snackbar handle` removes that entry;
  - rebuilding with `hud:build-default` preserves the same manager object and existing visible entry;
  - `hud:drop` drops the snackbar scope once and later `hud.snackbar-manager:show` raises `SnackbarManager is dropped`.

- [ ] **Step 2: Run focused HUD test and verify failure**

  Run:
  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud:main
  ```
  Expected: FAIL because HUD does not create a snackbar scope.

- [ ] **Step 3: Create the HUD snackbar scope**

  Update `hud.fnl`:
  - require `:snackbar`;
  - create `local snackbar-scope (Snackbar.create-scope {:theme ctx.theme})` during `Hud` construction after `ctx` exists;
  - set `self.snackbar-scope` and `self.snackbar-manager`;
  - add `show-snackbar` and `dismiss-snackbar` methods delegating to the manager.

- [ ] **Step 4: Inject the host builder into default HUD layout**

  Update `build-default` so it copies incoming opts into a new table and sets `:snackbar-host-builder` to `self.snackbar-scope.host-builder` unless the caller explicitly passed `:snackbar-host-builder false`.

- [ ] **Step 5: Drop the scope exactly once**

  Update `drop` so it calls `self.snackbar-scope:drop()` once, then clears `self.snackbar-scope` while leaving `self.snackbar-manager` available for dropped-state assertions.

- [ ] **Step 6: Verify HUD tests pass**

  Run:
  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud:main
  ```
  Expected: PASS.

---

### Task 6: Theme Tokens, Fast Suite Registration, and Dev Documentation

**Files:**
- Modify: `assets/lua/dark-theme.fnl`
- Modify: `assets/lua/light-theme.fnl`
- Modify: `assets/lua/tests/test-snackbar-host.fnl`
- Modify: `assets/lua/tests/fast.fnl`
- Create: `docs/dev/features/snackbar-system.md`
- Modify: `docs/dev/features/index.md`

**Interfaces:**
- Consumes: Task 1 `SnackbarTheme.resolve`.
- Produces: `ctx.theme.snackbar` in dark and light themes.
- Produces: fast suite modules `:tests.test-snackbar-manager` and `:tests.test-snackbar-host`.
- Produces: developer documentation for snackbar manager/host/content/HUD integration.

- [ ] **Step 1: Add failing theme token tests**

  Add assertions to `test-snackbar-host.fnl` that:
  - `(SnackbarTheme.resolve {:theme (require :dark-theme)})` includes `:placement :top-right`, `:max-visible 3`, `:max-queued 20`, and `:duration-ms 4000`;
  - light theme snackbar `:info.background` differs from dark theme snackbar `:info.background`;
  - host placement reads `ctx.theme.snackbar.placement`.

- [ ] **Step 2: Run focused tests and verify failure**

  Run:
  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snackbar-host:main
  ```
  Expected: FAIL because theme files do not expose snackbar tokens.

- [ ] **Step 3: Add snackbar tokens to dark and light themes**

  In both theme files add `:snackbar` with `:placement :top-right`, `:spacing 0.3`, `:padding [0.45 0.35]`, `:max-width 18.0`, `:max-visible 3`, `:max-queued 20`, `:duration-ms 4000`, and variant color tables for `:info`, `:success`, `:warning`, and `:error`.

- [ ] **Step 4: Register tests in the fast suite**

  Add `:tests.test-snackbar-manager` and `:tests.test-snackbar-host` near the HUD/widget tests in `assets/lua/tests/fast.fnl`.

- [ ] **Step 5: Create dev documentation**

  Create `docs/dev/features/snackbar-system.md` documenting:
  - `Snackbar.create-scope` for independent managers/hosts;
  - manager ownership of entries, policy, timers, and subscriptions;
  - host ownership of rendered widgets and teardown;
  - content paths for `:content-builder`, text, and text/actions;
  - HUD mounting inside center/middle layout bounds;
  - no scrollable snackbar host in the first implementation;
  - validation commands for snackbar/HUD changes.

- [ ] **Step 6: Link the dev documentation**

  Add `- [Snackbar System](./snackbar-system)` to `docs/dev/features/index.md`.

- [ ] **Step 7: Verify focused tests and docs references**

  Run:
  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snackbar-manager:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snackbar-host:main
  ```
  Expected: PASS.

---

## Acceptance Criteria

- Independent `Snackbar.create-scope` calls do not share entries, queues, timers, or subscriptions.
- `SnackbarManager` has no widget dependencies and owns policy, timers, handles, replacement, queueing, and drop behavior.
- `SnackbarHost` owns all rendered snackbar widgets, reconciles visible manager entries, and drops children exactly once.
- Default HUD snackbar host is mounted in the dynamically measured center/middle HUD region, not the full overlay.
- HUD snackbars do not cover the control panel, status panel, top toolbar, left dock, or right dock in layout tests.
- Default content supports simple text, text plus action buttons, and arbitrary `:content-builder`.
- Overflow is managed by policy; no scrollable snackbar host is introduced.
- Theme tokens under `ctx.theme.snackbar` control placement, spacing, padding, max width, duration, visible/queued limits, and variant colors.
- Existing HUD overlay, command-hints, panel, dock, toolbar, and layout tests continue to pass.
- Developer docs describe manager/host ownership and HUD placement.

## Validation Ladder

- Runtime/freshness prerequisite when `./build/space` is missing or stale:
  ```bash
  make build
  ```
- First focused check for Fennel-facing work:
  ```bash
  make fennel-check
  ```
- Second focused check:
  ```bash
  make constraints
  ```
- Focused Fennel tests:
  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snackbar-manager:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snackbar-host:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-layout:main
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud:main
  ```
- Broader local suite is justified because this changes HUD layout, theme tokens, shared widget behavior, and fast-suite registration:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```
- Full integration gate: PR CI.

## Out of Scope

- OS-level desktop notifications.
- Scrollable snackbar history or notification center UI.
- Cross-process or global portal broker routing.
- Animation system work beyond static layout-ready placement.
- Persistence of snackbar history across HUD/app reloads.
- Replacing command hints, dialogs, menus, or panel persistence.
