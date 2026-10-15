# Reload boundaries and lifecycle units

This is the canonical contract for authors and reviewers of Space reload
boundaries. **Controller-driven development reloads default to app-root.** Smaller
lifecycle units remain useful, but source ownership alone does not make them
independently replaceable. Units run trusted code in the existing process; they
are not a sandbox for untrusted plugins or players.

## Three different concepts

- A **module** is an importable source implementation.
- A **lifecycle unit** owns explicit load/unload and optional snapshot/restore
  operations. It can organize resources without being safe to replace alone.
- An **independently supported reload boundary** has an explicit replacement
  contract: which consumers are recreated, which dependencies remain, how cleanup
  and state work, and tests demonstrating fresh behavior and recovery limits.

App-root replaces the Fennel app lifecycle inside the existing native process.
It is the supported development baseline, not a native restart or a transaction
over all process state. The global `app`, native engine, preserved modules and
external systems are not universally reset.

`owned-paths` selects a routing candidate, not proof that all consumers of that
code will be replaced. `parent-id` supplies a lifecycle/routing hierarchy, **not
a runtime dependency declaration**. Clearing `package.loaded` cannot rewrite a
function, factory closure, adapter or module table already retained elsewhere.
For each such reference, choose one of three responses:

1. Recreate the consumer with the new implementation.
2. Explicitly late-bind through a stable interface whose implementation is updated.
3. Enlarge the reload boundary to include both provider and consumer.

Rebuilding a presentation is insufficient if its retained factory still closes
over old code. Reloading an enclosing boundary is a valid design, not a failure
to achieve finer granularity.

## Current inventory and discovery

All six built-in leaves below have `parent-id "app-root"`: activities are
**siblings of canvas**, not its descendants. The controller owns its root unit;
`app.unit-manager` registers the children and user units.

| Unit ID / category | Lifecycle responsibility | Independent reload status |
| --- | --- | --- |
| `app-root` | `main` initialization, teardown and shell snapshot/restoration | Supported controller development baseline |
| `hud` | HUD shell, focus scope and panel state | Lifecycle-only by default; experimental direct and explicit opt-in coverage |
| `canvas` | Canvas runtime over the active world's longer-lived state | Lifecycle-only by default; experimental direct and explicit opt-in coverage |
| `sandbox-activity` | Sandbox activity registration/session behavior | Lifecycle-only by default, not independently certified |
| `graph-activity` | Graph activity registration and presentation | Lifecycle-only by default; experimental opt-in coverage |
| `drawing-activity` | Drawing activity registration, actions and rendering | Lifecycle-only by default; experimental opt-in coverage |
| `board-activity` | Board activity registration and presentation | Lifecycle-only by default; experimental opt-in coverage |
| `user-<name>` | Filesystem-discovered user module lifecycle | Discovery is implemented, not independent reload certification |
| Contracted graph-extension units, e.g. `user-demo-extension` | Descriptor-owned loaders/morphs and explicit adapter refresh | A specific tested narrow seam, requiring controller opt-in; not blanket approval of graph-related code |

At initialization, `main.ensure-user-code-units!` scans immediate entries in
`app.code-dir` for flat `<name>.fnl` files (names without dots) and directories
containing `<name>/init.fnl`. A directory wins over a same-name flat file, including
module search precedence. Candidates load in name order as `ModuleUnit`s under
app-root. Flat units own their file; directory units own their directory and init
file. Failed loads are logged and unregistered. The built-in activity list is
still explicit, but user-unit startup discovery is not future work.

Discovery and watching are separate. Main's default watch root is the assets
`lua` directory; it does not automatically include `app.code-dir` or every
dependency. Configure all required watch roots. The watcher filters for Lua/Fennel
changes, ignores startup noise and does not treat add/created/unknown events as
reload requests. It is not a live unit-discovery service; a new unit needs an
initialization/discovery pass or explicit registration.

## Controller configuration and execution

Set configuration **before the controller is constructed** during app
initialization. Main retains the controller and callback ID across app-root
reloads; assigning a new config table does not reconfigure an existing watcher.
These examples run in a bootstrap context with `app.code-dir` initialized:

```fennel
(local fs (require :fs))
(local runtime (require :runtime))
(local lua-root (fs.join-path runtime.assets-path "lua"))

;; Root-only, including edits to discovered user-unit sources.
(set app.hot-reload-config
     {:enabled true :watch-paths [lua-root app.code-dir]})
```

For an audited extension contract, use this configuration **instead**:

```fennel
(local fs (require :fs))
(local runtime (require :runtime))
(local lua-root (fs.join-path runtime.assets-path "lua"))

(set app.hot-reload-config
     {:enabled true :watch-paths [lua-root app.code-dir]
      :narrow-reload-unit-ids ["user-demo-extension"]})
```

`narrow-reload-unit-ids` is the canonical optional list of eligible non-root IDs
in `HotReloadController`, `AppRootController` and `app.hot-reload-config`.
**Omitted or empty means only the configured root is eligible.** Normal
development configuration does not opt built-in children in. Listing an ID
records the caller's audit; it does not certify the unit at runtime.

The pipeline in `assets/lua/hot-reload.fnl` is:

1. Resolve a candidate by longest matching owned path; for multiple owners use
   their common ancestor, or root if none match.
2. Apply eligibility: use that candidate only if it is root or explicitly listed;
   otherwise select root. Listing siblings does not make their parent eligible.
3. Collect loaded modules under the **final target's** roots, excluding preserved
   modules, using current or remembered source paths.
4. Capture the target snapshot, unload, clear collected `package.loaded` entries
   and Fennel compiled caches, load, restore, then refresh its graph extensions.

This is pre-execution routing, **not failure-triggered escalation**. For example,
a HUD edit selects root by default, before any HUD-only snapshot or teardown.
Mixed sibling changes cannot be reduced to just one eligible sibling.
`controller:debug-state().last-target-unit-id` and `[hot-reload]` target logs
identify the actual execution target, not merely the ownership candidate.

Main's watcher flow debounces events and requests one deferred callback per
pending batch via `on-reload-requested`. The callback calls `reload-now!` after
the detecting update stack unwinds; `AppRootController` forwards this callback.
By contrast, `controller:reload-now!({:changes changes})` executes synchronously
and still applies eligibility. A generic controller without a callback executes
from its update method. Direct synchronous callers must choose a safe execution
point themselves.

### Recovery and distinct entry points

Controller recovery is in-place best effort: on a protected reload failure it
tries to unload a successfully loaded failed replacement, clear tracked modules,
restore backed-up module entries, load/restore the **same** target and refresh
its extensions. It returns `false` if recovery succeeds and throws if recovery
fails. Snapshot capture precedes that protected reload block. This is not a staged
swap: globals, newly introduced/untracked modules, external writes, native effects
and in-flight work are not universally reversed.

| Entry point | Routing / invalidation | Recovery responsibility |
| --- | --- | --- |
| Watcher/controller and controller `reload-now!` | Candidate → eligibility → target-owned loaded-module and Fennel-cache clearing | Same-target tracked-module/snapshot recovery above; no failure escalation |
| `Unit:reload` | Exactly that unit; snapshot → unload → load → restore → graph refresh; base Unit has no module invalidation | No controller backup/recovery wrapper |
| `ModuleUnit:reload` | Direct Unit protocol; unload clears remembered owned modules/caches. Configured `module-paths` tracks owned requires during lifecycle calls | Loader-specific clearing, not consumer/dependency invalidation or controller recovery |
| `SourceUnit:reload` | Direct Unit protocol; unload discards its evaluated module table, load evaluates its captured source | Does not invalidate imported dependencies or gain a controller backup |
| `UnitManager:reload-unit` | Direct unit reload, then attempts reactivation of the previously active activity and returns evidence | Unit errors throw; reactivation evidence is not a runtime rollback guarantee |
| Internal agent unit edit/reload tools | Direct manager/unit operations; edit helpers validate source/exports and use loader purge hooks | Edit-specific source restoration and recovery attempts; explicit reload has no edit backup |
| External `space_unit_apply_patch`, `space_unit_create_source`, `space_unit_reload` | External service calls the manager, not the controller; loader capability and source safety checks | Patch tries source restoration plus recovery reload; create tries removing the new file; explicit reload has no source backup |

**No direct path inherits controller root routing, eligibility, callback deferral
or module backup.** Outside a specific tested contract, these are caller-managed,
experimental replacement operations with weaker guarantees. A later watcher
event is not a protection for an earlier direct edit/reload. Internal reload uses
`id`; the external tool uses `unit_id` (and source tools use `source_id`).
See [External Unit MCP](./notes/external-unit-mcp) for its separate editing API.

## Existing mechanisms, not a universal effect system

- **Managed unit signals** (`units.fnl`): `unit:connect-signal` records named
  connections and disconnects them on unload or failed-load cleanup. Arbitrary
  `signal:connect` calls do not become unit-owned automatically. Base Unit also
  attempts its unload function after a failed load; authors must clean partial
  initialization correctly.
- **Activity cleanup stacks** (`activities.fnl`): activation can register explicit
  `ctx:defer-cleanup!` callbacks. Session teardown and activation-failure paths run
  recorded cleanup in reverse order and report failures. Retained sessions may
  outlive deactivation; this is not interception of every activity side effect.
- **Graph registration handles** (`graph/extension-registry.fnl`, `graph/core.fnl`,
  `morphs/init.fnl`): explicit descriptor/loader/morph handles protect ownership
  so stale handles cannot remove newer registrations. The registry reverses
  recorded installation handles on failure; authors must return/record handles
  and unregister their descriptor on drop. Untracked effects remain their job.
- **Fresh command composition** (`commands/core.fnl`, `leader-state.fnl`):
  composition builds new command/binding/prefix collections from ordered current
  providers rather than repeatedly mutating one catalog. Provider order still
  matters, and a retained provider closure can still contain stale code.
- **Graph adapter refresh**: the registry refreshes declared schemes in each live
  runtime's active map after unit reload. `graph/map.fnl` rebuilds map-local node
  adapters by key and rewires edges while retaining selection/focus keys. This is
  not reconstruction of all retained adapters, factories or domain data. The
  [extension contract](./features/reloadable-graph-extension-units) defines the seam.

These mechanisms enforce local bookkeeping once used. Choosing all resources,
consumers and cleanup obligations remains an author responsibility; Space has no
general effect scope or dependency-driven consumer restart engine.

### Root snapshot is data, not migration

`app.snapshot-app-state` (exported as `snapshot` by `main.fnl`) captures
`active-world-id`, `active-activity-id`,
`preferred-interaction-surface`, `active-interaction-surface`, `canvas-visible?`
and `debug-log-content`. Active world capture prefers `app.active-world-entry.id`
and falls back to the manager accessor. Restore activates the world/activity,
applies the preferred interaction surface and canvas visibility, and merges log
history; it does **not** separately restore the captured active interaction
surface. The root-reload branch of `app.drop` attempts to preserve tray/notify,
but re-evaluating `main.fnl` clears both references and initialization creates
replacements. That drop branch is not an end-to-end retention guarantee.

These fields describe current capture/restoration, not a promise of arbitrary
state preservation or versioned migration. Persistent world/domain state has its
own owners; snapshots must not accidentally retain executable references that
defeat replacement.

## Author / reviewer boundary checklist

Before adding an ID to `narrow-reload-unit-ids`, record answers and test evidence:

- [ ] **Ownership:** Which source roots, registrations, native resources and
  global mutations belong to this boundary? Do watch roots cover relevant edits?
- [ ] **Consumers/dependencies:** Who retains its functions, tables, factories or
  adapters? Which consumers are recreated, late-bound or included in a larger
  boundary? Do not treat `parent-id` as a dependency audit.
- [ ] **Teardown order:** Are consumers stopped before providers/resources vanish?
  Does drop clean partial initialization and only remove this owner's handles?
- [ ] **State:** Which data survives, resets or is rejected? Are snapshots data/keys
  rather than old closures or instances? What schema changes are unsupported?
- [ ] **Pending work:** What happens to queued callbacks, timers, async replies and
  native work from the old implementation? How are stale results rejected?
- [ ] **Publication:** Can observers see partially replaced registrations or
  catalogs? Which derived collections are rebuilt from fresh contributions, and
  when is the new behavior published?
- [ ] **Failure limits:** Which entry point is used, what is actually recoverable,
  and what requires explicit restart/operator action? Do not promise external-effect
  rollback or assume a child failure will escalate.
- [ ] **Evidence:** Edit behavior and prove existing consumers execute new code,
  not just that a new instance exists. Repeat success; assert singular handlers,
  descriptors and morphs; test failed load/refresh followed by valid success and
  cleanup of the old implementation. Check actual target evidence.
- [ ] **Fallback:** If any answer is incomplete, leave narrow eligibility off and
  use the supported enclosing boundary (normally app-root).

Future game/player behavior replacement motivates this contract, but is not an
implemented protocol. It still needs host-owned game state, explicit frame/tick
replacement timing, state preservation/reset policy and stale-work handling.
Multiple players also need separate coordination, authority and security
decisions; trusted in-process units provide none of that isolation.

## Lessons from OpenCode Reloaded and Cordis

External references below were accessed **2026-10-15**; branch links and upstream
APIs may evolve. These are comparisons, not dependencies adopted by Space.

### Rebuild derived catalogs, rather than accumulate mutations

[OpenCode Reloaded](https://anoma.ly/notes/opencode-reloaded/) describes stale
plugin contributions, overwritten policy, inconsistent intermediate states and
repeated transforms when plugins mutate a shared catalog in place. Its approach
associates transformations with plugins, removes them with their plugin, and
applies the remaining ordered transformations once to a fresh catalog per rebuild.
Order can matter; each transform need not be individually idempotent. The useful
property is avoiding accidental accumulation across rebuilds, not order independence.

Space's fresh command composition is a local parallel: rebuild a derived result
from the current providers. It is not a universal catalog reconstruction system,
and persistent world/domain state should not be treated as a disposable catalog.

### Own explicit effects and dependent lifetimes

[Cordis](https://github.com/cordiverse/cordis) associates explicit reversible
effects with plugin lifetimes and uses declared injected-service dependencies and
implementation identity to handle dependent lifetimes, including consumer teardown
before provider disposal. Its README links a
[Cordis primer](https://deepseek-harness.github.io/deepseek-harness/en/reference/cordis-primer)
for a vendored integration; that primer is not a promise of identical upstream APIs.
The upstream mechanisms are in
[`fiber.ts`](https://github.com/cordiverse/cordis/blob/main/packages/core/src/fiber.ts),
[`reflect.ts`](https://github.com/cordiverse/cordis/blob/main/packages/core/src/reflect.ts)
and [`events.ts`](https://github.com/cordiverse/cordis/blob/main/packages/core/src/events.ts).
Module code replacement is a separate mechanism in
[`packages/hmr`](https://github.com/cordiverse/cordis/blob/main/packages/hmr/src/index.ts).

Space has explicit signals, cleanup stacks and registration handles, but not
Cordis's general effect scope, injected-service identity tracking or automatic
dependent restart. The lesson is to declare ownership and consumer lifetimes,
not assume re-importing a module updates them. Neither explicit disposers nor
fresh catalogs imply automatic rollback of arbitrary mutations or external effects.

## Evidence and further reading

- `assets/lua/tests/test-units.fnl`: deterministic eligibility matrix, wrapper
  callback deferral, edited ModuleUnit behavior and deleted-module clearing.
- `assets/lua/tests/test-hot-reload-integration.fnl`: real main configuration,
  repeated default root reloads of main/HUD paths, active world/log preservation,
  stable controller/callback IDs and singular cache searcher; also experimental
  direct HUD/canvas and explicit opt-in child fixtures, not general freshness proof.
- `assets/lua/tests/test-graph-extension-units.fnl` and
  `test-graph-extension-runtime-plumbing.fnl`: the contracted extension seam,
  repeated registration/refresh cleanup, recovery and subsequent success.
- `assets/lua/tests/test-live-hot-reload.fnl`: real executable watcher/deferred
  reload with active-world preservation; Linux X11 under `xvfb` is required.
  Ordinary `make test` does not replace the explicit slow integration/live gates.

For runtime validation, use project-native compile checks, then constraints,
then focused tests as described in [Development Tooling](./features/development-tooling).
See also [Hot Reload Units](./features/hot-reload-units) and
[Lifecycle Centralization](./lifecycle-centralization).
