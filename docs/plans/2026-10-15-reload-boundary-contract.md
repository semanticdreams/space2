# Reload Boundary Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Default controller-driven development reloads to root, preserve audited
narrow opt-ins, and document boundary contracts and the OpenCode/Cordis lessons.

**Architecture:** Preserve ownership/common-ancestor candidate selection, then
apply controller-owned eligibility before module collection or lifecycle work.
Forward eligibility through main and the root wrapper, repair confirmed callback
forwarding loss, and keep all direct lifecycle/tool behavior unchanged.

**Tech Stack:** Existing Fennel/Lua runtime, efsw, native callback queue, Fennel
tests and Markdown/VitePress; no new runtime dependency.

## Global Constraints

- Specification: `docs/specs/2026-10-15-reload-boundary-contract-design.md`.
- "Source ownership selects a candidate, not proof that all consumers of that code will be replaced."
- "`parent-id` is not a runtime dependency declaration."
- "Omitted or empty means only the configured root is eligible."
- "This is pre-execution routing policy, not failure-triggered escalation."
- "Normal development configuration does not opt built-in children in."
- "Do not add compatibility keys."
- "Do not redesign the callback system."
- "Direct reload is weaker than watcher/controller recovery."
- "No unrelated fixes to activity restore contracts or broad refactors."
- Preserve lifecycle units, explicit graph-extension contracts and current direct
  Unit/manager/internal-agent/external-MCP behavior. No dependency engine,
  container, transaction, universal effect tracking or multiplayer protocol.
- Each task goes implementer -> independent reviewer -> pass before commit.
- Advisor confirmed the callback forwarding diagnosis in the spec: wrapper
  option loss causes inline execution; this is not a reproduced crash claim.

## File responsibilities

| File | Responsibility |
|---|---|
| `assets/lua/hot-reload.fnl` | Candidate eligibility, actual execution target, root-wrapper forwarding |
| `assets/lua/main.fnl` | Forward user config through both existing configuration tables |
| `assets/lua/tests/test-units.fnl` | Deterministic policy and wrapper-scheduling regression coverage |
| `assets/lua/tests/test-hot-reload-integration.fnl` | Real main config chain, root baseline, explicitly experimental child cases |
| `assets/lua/tests/test-graph-extension-units.fnl` | Explicit opt-in and repeated extension success/recovery coverage |
| `docs/dev/reloadable-units.md` | Canonical contract, inventory, limits and external comparison |
| `docs/dev/features/hot-reload-units.md` | Accurate concise feature overview |
| `docs/dev/features/reloadable-graph-extension-units.md` | Contracted extension seam and opt-in |
| `docs/dev/lifecycle-centralization.md` | Qualify lifecycle ownership versus reload guarantees |
| `docs/dev/notes/external-unit-mcp.md` | Direct-tool safety and recovery distinctions |

## Validation commands

Run from repo root, with this environment for runtime commands:

```bash
export SKIP_KEYRING_TESTS=1
export XDG_DATA_HOME=/tmp/space/tests/xdg-data
export SPACE_DISABLE_AUDIO=1
export SPACE_LOG_DIR=/tmp/space/tests/log
export SPACE_ASSETS_PATH="$(pwd)/assets"
export FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"
export FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"
unset TEST_FILTER
```

If runtime missing/stale or freshness unestablished, run `make build` with tool
timeout **14400000 ms**. For `make cmake`, use **600000 ms**. Build can be cold.

Compile touched files first:

```bash
./build/space -m tools.fennel-check:main -- --output summary --target files \
  --file assets/lua/hot-reload.fnl \
  --file assets/lua/main.fnl \
  --file assets/lua/tests/test-units.fnl \
  --file assets/lua/tests/test-hot-reload-integration.fnl \
  --file assets/lua/tests/test-graph-extension-units.fnl
make constraints
./build/space -m tests.test-units:main
./build/space -m tests.test-hot-reload-integration:main
./build/space -m tests.test-graph-extension-units:main
./build/space -m tests.test-graph-extension-runtime-plumbing:main
```

Compile -> constraints -> focused tests is the order. `TEST_FILTER` is a literal
substring on registered test names; filtered runs must execute nonzero tests.
Never use system Lua/Fennel, `--compile` or `-e` as validation oracles. For parse
errors inspect the enclosing form; isolate/restructure the actual bad construct.
Constraint results other than `pass` block. Do not bypass new violations with
baselines. Any genuinely stale baseline update requires reviewed evidence.

Final relevant gates, with the same environment and no test filter:

```bash
make test
make test-live-hot-reload
```

Ordinary `make test` excludes the slow Fennel integration suite, so it does not
replace the explicit hot-reload integration command. The live executable test
requires Linux X11/xvfb and local IPC; a skip is not a passing live gate.

### Task 1: Conservative eligibility and deferred callback forwarding

**Files:** Modify the five Fennel files listed above; read unchanged
`tests/test-live-hot-reload.fnl`, `tests/test-graph-extension-runtime-plumbing.fnl`,
`units.fnl`, `unit-manager.fnl`, and `Makefile` for contracts/harnesses.

**Interfaces:**
- Consumes `HotReloadController(opts)`, `AppRootController(opts)`,
  `controller:reload-now!({:changes changes})`, `controller:update(delta)`,
  `controller:debug-state()`, existing Unit lifecycle and FileWatcher factory.
- Produces optional `narrow-reload-unit-ids: sequential-table<string>` in both
  controller factories and `app.hot-reload-config`.
- Preserves `on-reload-requested(controller)` and actual-target debug field
  `last-target-unit-id`; no new public registry or per-unit certification field.

- [ ] **1. Build a deterministic local fixture and scheduling regression.**
  In `test-units.fnl`, use existing temp-directory helpers, temporarily replace
  `FileWatch.FileWatcher` and `app.engine.now-ms`, and restore both in protected
  cleanup. The fake poll drains queued events. Keep a clock beyond the existing
  startup-ignore window; do not forward unrelated wrapper options.

  Construct `AppRootController` with a uniquely named cached module providing
  lifecycle spies and an `on-reload-requested` spy. Restore the module cache entry
  and drop the controller even on failure. Register the test as
  `app root wrapper defers watcher reload until requested execution`.

  Core expectations, adapted to the suite's syntax:

  ```fennel
  (set state.now-ms 6000)
  (set state.events [{:path changed-path :action "modified"}])
  (state.controller:update 0)
  (set state.now-ms 6011)
  (state.controller:update 0)
  (state.controller:update 0)
  (assert (= spy.requests 1))
  (assert (= spy.unloads 0))
  (assert (state.controller:reload-now!))
  (assert (= spy.unloads 1))
  (assert (= spy.restores 1))
  ```

  Verify callback receives the controller and one pending batch requests once;
  successful reload clears the batch. Capture RED on the baseline:

  ```bash
  TEST_VERBOSE=1 TEST_FILTER="app root wrapper defers watcher reload until requested execution" ./build/space -m tests.test-units:main
  ```

- [ ] **2. Fix the confirmed callback defect and obtain GREEN.**
  In the `AppRootController` options literal add exactly:

  ```fennel
  :on-reload-requested options.on-reload-requested
  ```

  Rerun compile, constraints and the filtered test; record expected RED/GREEN.

- [ ] **3. Add policy tests before production eligibility code.**
  Use counted synthetic units under a configured root ID `dev-root` (not
  `app-root`), a child `group` with children `a` and `b`, and sibling `other`.
  Give them distinct owned directories and snapshot/restore exports so those
  exports cannot accidentally imply eligibility. Record lifecycle and target ctx.

  | Allowlist | Changes | Expected execution |
  |---|---|---|
  | omitted / empty | a | dev-root |
  | a | a | a |
  | a | b or other | dev-root |
  | a,b | a and b | dev-root |
  | group | a and b | group |
  | a,other | a and other | dev-root |
  | a | root-owned, unmatched, or empty changes | dev-root |

  Every case asserts only final-target snapshot/unload/load/restore executes,
  its context identifies that target, and debug evidence agrees. Capture RED
  with a registered-name filter such as `hot reload eligibility`.

- [ ] **4. Implement controller-owned selection before module collection.**
  A small private helper is sufficient:

  ```fennel
  (fn select-eligible-target-unit [candidate root-unit narrow-unit-ids]
    (var eligible? (= candidate root-unit))
    (each [_ id (ipairs (or narrow-unit-ids [])) &until eligible?]
      (when (= id candidate.id) (set eligible? true)))
    (if eligible? candidate root-unit))
  ```

  In `perform-reload!`, find the configured root, resolve candidate with existing
  routing, apply this helper, then calculate `module-roots` from final target.
  Existing backup/logging/context/refresh/recovery must all use that target.
  Keep same-target failure recovery unchanged. Run the matrix to GREEN.

- [ ] **5. Forward configuration through wrapper and both main tables.**
  Add `:narrow-reload-unit-ids options.narrow-reload-unit-ids` to the wrapper,
  `(and override override.narrow-reload-unit-ids)` to resolved main config,
  and `config.narrow-reload-unit-ids` to its controller-config table. Do not
  populate built-ins, add aliases or change direct reload entry points.

- [ ] **6. Exercise real main construction and preserve experimental cases.**
  Extend the real root roundtrip to reload both a root-owned path and a HUD-owned
  path without opt-in. Require main's constructed controller (no masking fallback)
  and verify final target root, supported active-world state and debug-log marker,
  stable controller/callback IDs and singular Fennel cache searcher after repeats.
  Exercise an explicit HUD opt-in via `app.hot-reload-config`, not just a direct
  generic factory, to prove both forwarding hops.

  Existing narrow canvas, triangle-line, drawing render/actions, graph view and
  board fixtures explicitly list their tested target ID. Label these experimental
  opt-in evidence, not general freshness certification. Preserve direct HUD/canvas
  lifecycle and workspace-shell root coverage. Restore test globals/config safely;
  extract test-local assertions rather than deepening nested forms.

- [ ] **7. Keep the graph-extension seam narrow and test repetition.**
  Add `:narrow-reload-unit-ids ["user-demo-extension"]` in its controller fixture.
  Preserve direct manager coverage, zero root reload assertions, changed adapter
  behavior, cleanup, failed refresh recovery and subsequent successful reload.
  Repeat a valid controller reload and assert one descriptor and one expected
  morph registration remain, using existing fixture references/accessors. Assert
  final target stays the extension; do not add production inspection APIs.

- [ ] **8. Validate, independently review, then commit.**
  Run compile -> constraints -> all four focused suites. Report RED/GREEN,
  constraint impact and coverage rationale. Reviewer checks configuration chain,
  pre-mutation routing, scheduling, isolation and no direct-tool changes. Fix
  findings through implementer/reviewer; only after pass commit intended files as
  `feat(lua): default controller reloads to app root` with testing/risk body.

### Task 2: Canonical contract, inventory and external comparison

**Files:** Modify the five documentation files in the responsibility table.
Read their related implementation and Task 1 tests; no production changes here.

**Interfaces:** Consumes Task 1's eligibility option/default and callback behavior.
Produces a canonical author/reviewer contract, current inventory and entry-point
comparison linked from related pages. Direct APIs remain unchanged.

- [ ] **1. Explain concepts and current boundary inventory.**
  Distinguish module, lifecycle unit and independently supported boundary. Explain
  app-root in-process scope, path ownership versus dependencies, and three
  responses to retained implementation references: recreate consumers, late-bind
  a stable interface, or enlarge boundary. Include all six built-in leaves,
  app-root and user units with activities as siblings of canvas. Root is supported
  baseline; built-in leaves lifecycle-only by default with experimental direct/
  opt-in evidence; general user discovery is not certification; graph extensions
  are a specific contracted seam. Describe actual flat-file/directory discovery,
  directory precedence and configured watch-root limits.

- [ ] **2. Provide configuration and exact entry-point/recovery distinctions.**
  Show a root-only config and audited extension opt-in:

  ```fennel
  (set app.hot-reload-config
       {:enabled true :watch-paths [lua-root app.code-dir]
        :narrow-reload-unit-ids ["user-demo-extension"]})
  ```

  Define `lua-root` in the complete published example. Explain construction-time
  configuration, candidate -> eligibility -> module collection -> lifecycle,
  deferred watcher versus synchronous `reload-now!`, and final-target evidence.
  Compare controller, direct Unit/ModuleUnit/SourceUnit, manager, internal agent
  and external MCP edit/reload paths. No direct path inherits controller policy.
  Explain loader-specific invalidation, operation-specific recovery and weaker
  direct guarantees. Do not alter tool parameter names in docs.

- [ ] **3. Add the author/reviewer checklist and precise existing mechanisms.**
  Checklist covers ownership, retained consumers/dependencies, teardown order,
  data versus executable references in snapshots, pending/async work, publication,
  recovery limits, freshness, repeated cleanup, failure-then-success evidence and
  enclosing-boundary fallback. Explain managed signals, activity cleanup stacks,
  graph registration handles, fresh command composition and adapter refresh
  separately; no universal ownership/dependency/rollback claim. Correct snapshot
  fields from current `main` and distinguish captured data from migration promises.

- [ ] **4. Include the requested external comparison.**
  Link `https://anoma.ly/notes/opencode-reloaded/` and
  `https://github.com/cordiverse/cordis`. Use the spec and prior research; obtain
  narrowly scoped web research for additional claims or precise source permalinks.
  Article: stale contributions, overwritten policy, inconsistent intermediate
  states and repeated transforms; ordered plugin-owned transforms on fresh
  catalogs. Order can matter and transforms need not individually be idempotent.
  Compare Space's fresh command composition, not persistent domain state.
  Cordis: reversible effects and declared service dependencies/dependent lifetimes;
  module HMR is distinct. Space has local cleanup mechanisms, not a general effect
  scope or injected-service identity/restart engine. Neither implies arbitrary
  effect rollback. State access date and ground claims without adopting the runtime.

- [ ] **5. Reconcile related documentation and remove stale claims.**
  Feature overview: root default, full inventory, implemented discovery, recovery
  limits and canonical links. Extension feature: opt-in, distinct controller/direct
  behavior and compile/constraints/test ordering. Lifecycle page: ownership is a
  prerequisite rather than freshness proof; qualify managed-signal cleanup. MCP
  note: edit safety is not controller routing or transactional runtime restoration.
  Remove scratch-spec framing, obsolete discovery claims, old suite locations and
  active-canvas-feature snapshot claims where stale. Keep realtime game/player
  examples motivational with explicit timing/state/stale-work/security/coordination
  questions, not implemented guarantees.

- [ ] **6. Validate text and documentation build, review, commit.**
  Search touched docs for obsolete assertions (`independent reloadable`,
  `safe runtime code changes`, `external unit discovery`, `active canvas feature`)
  and verify required links/key/limitations. Run `git diff --check`.
  Run `npm run docs:build` with tool `workdir` set to `docs`, using existing locked
  dependencies and no unrelated package/generated-file churn. Investigate failures
  systematically. Independent review verifies source accuracy and external claims.
  After pass commit intended docs as `docs(lua): define reload boundary contracts`.

## Finishing

Fetch/evaluate current `origin/main` through git-integrator, safe-merge if needed,
route conflicts/fixes through implementer/reviewer, and rerun applicable gates.
Run full `make test` and live hot-reload gate from committed clean tree. Capture
and debug every required validation failure; do not bypass flaky/environmental
failures. Check complete diff and clean status. Push feature branch and create PR
through guarded capability agents; enable auto-merge and poll until merged.
Post-PR freshness belongs to merge queue; do not merge main merely because it
advanced. Missing queue/protection/permissions requires wrapper-backed human
decision. Never rebase or force-push. Local `main` requires guarded wrap-up branch.
