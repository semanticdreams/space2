# Reload boundary contracts and conservative development reloads

## Approved direction

Space needs both dependable whole-app development reloads now and eventually
small independently replaceable behaviors, including multiple players editing
code while a game runs. Whole-app reload is acceptable for development today.
Preserve modular lifecycle ownership; do not imply independent reload safety
merely because a unit exists or owns source paths.

The user approved a documentation-first boundary contract, an audit of existing
boundaries, conservative routing backed by tests, and an explanation of how
OpenCode Reloaded and Cordis relate to Space. This specification scopes that
work to controller-driven reloads and truthful documentation of other entry
points. It does not introduce a service container or dependency graph.

## Concepts and guarantees

- A module is an importable source implementation.
- A lifecycle unit owns explicit initialization, teardown and optional state
  capture/restoration. It need not be safe to replace independently.
- An independently supported reload boundary has an explicit replacement
  contract, consumer/dependency policy, cleanup obligations and test evidence.
- Source ownership selects a candidate, not proof that all consumers of that
  code will be replaced. `parent-id` is not a runtime dependency declaration.
- App-root reload replaces the Fennel app lifecycle inside the existing native
  process. It is not a native restart or a transaction over all process state.
- Units remain trusted in-process code, not a sandbox for untrusted players.

## Runtime scope

The hot-reload controller owns independent-reload eligibility. Retain existing
longest-owned-path and common-ancestor candidate resolution. Add one canonical
controller option, `narrow-reload-unit-ids`, a list of explicitly eligible
non-root unit IDs. Omitted or empty means only the configured root is eligible.
After candidate resolution and before module collection, snapshots or teardown,
use that candidate if it is root or explicitly eligible; otherwise select root.
This is pre-execution routing policy, not failure-triggered escalation.

Do not remove child lifecycle units or infer eligibility from source type,
owned paths, discovery, snapshot exports or graph-extension registration. An
opt-in records a caller's audited contract, not automatic runtime certification.
Mixed changes still require an eligible common enclosing candidate; unrelated
eligible siblings must not cause only one sibling to reload.

Forward the option through `AppRootController` and the app's existing
`app.hot-reload-config` configuration path. Normal development configuration
does not opt built-in children in. Keep actual target observable through
existing controller debug evidence and logging. Do not add compatibility keys.

The existing explicit graph-extension seam remains available: narrow-reload
controller fixtures must opt their contracted unit in, and existing direct
extension lifecycle/refresh behavior must continue working. This is not blanket
approval of all discovered user units or arbitrary graph-related modules.

Direct `Unit:reload`, manager reload, agent edit/reload and external MCP edit/
reload are not controller routing. Leave their behavior unchanged in this
bounded change. Documentation must identify these as caller-managed/experimental
outside a specific tested contract, explain their weaker invalidation/recovery,
and not suggest they inherit controller policy. Their future convergence is
explicit follow-up work rather than a hidden claim of protection today.

## Safe execution point

App-root watcher reload must execute after the detecting update stack unwinds,
using main's registered callback. Initial investigation found main supplies
`on-reload-requested` but `AppRootController` does not forward it. Establish this
with a focused regression and repair option forwarding if confirmed, before
making root selection the normal route. Do not redesign the callback system.

## Documentation deliverables

Make `docs/dev/reloadable-units.md` the canonical contract. Reconcile its feature
overview in `docs/dev/features/hot-reload-units.md` and cross-reference the
existing `docs/dev/features/reloadable-graph-extension-units.md` contract.

Include:

1. The module/lifecycle/independent-boundary distinctions above.
2. A current inventory: app-root; HUD; canvas; sandbox, graph, drawing and board
   activities; filesystem-discovered user units; contracted graph extensions.
   Activities are siblings of canvas, not descendants. Describe root as the
   supported development baseline; built-in leaves as lifecycle-only for
   automatic reload policy with experimental direct lifecycle coverage; general
   user units as not independently certified; graph extensions as an explicit
   narrowly tested seam, not a guarantee for arbitrary extensions.
3. A practical review template for adding/enabling a boundary: code and resource
   ownership, retained consumers and dependencies, teardown order, retained state
   and snapshot representation, pending callbacks/timers/async work, publication
   consistency, failure/recovery limits, and freshness/cleanup/repetition tests.
   A valid answer is to reload an enclosing boundary rather than invent machinery.
4. The three ways to address cross-boundary implementation references: recreate
   consumers, explicitly late-bind a stable interface, or enlarge the boundary.
   Rebuilding a presentation alone does not prove its factory closures are fresh.
5. Current managed-signal cleanup, activity cleanup stacks, ownership-safe graph
   registration handles, fresh command composition and graph-adapter refresh;
   distinguish enforced behavior from author conventions and coverage gaps.
6. Controller eligibility configuration and all distinct direct reload entry
   points; no silent claim that agent/MCP operations become root-routed.
7. Recovery is in-place best effort over tracked modules and lifecycle state,
   not atomic reversal of globals, external effects or in-flight work. Direct
   reload is weaker than watcher/controller recovery.
8. Correct stale user-discovery and unit-inventory statements within these docs.
9. Future game/player replacement as a motivation, not implemented guarantees:
   host-owned game state, explicit replacement timing and state policy, stale
   work handling, and separate multiplayer coordination/security decisions.

## Relationship to external work

Link both requested sources and explain their different problem domains:

- https://anoma.ly/notes/opencode-reloaded/ describes stale contributions,
  policy overwrite, intermediate inconsistent state and repeated transforms
  caused by in-place shared-catalog mutation. Its ordered plugin-owned
  transformations rebuild from fresh state. Order can matter; individual
  transformations need not be idempotent when applied once to a fresh rebuild.
  Space already freshly composes commands, but does not provide a universal
  derived-state reconstruction mechanism. Persistent world/domain state should
  not be conflated with rebuildable catalogs.
- https://github.com/cordiverse/cordis provides explicit reversible-effect
  ownership and declared service dependencies with dependent lifecycle handling.
  Module hot replacement is a separate concern. Space has local cleanup/handle
  mechanisms, but no general effect scope, injected-service identity tracking or
  dependency-driven consumer restart. Neither approach automatically reverses
  arbitrary mutations or external effects; do not promise transactional reload.

Explain how these ideas inform a boundary contract without importing a JS/TS
runtime or claiming equivalent guarantees. External references are evolving;
distinguish source-described mechanisms from what Space currently implements.

## Acceptance criteria and validation

- Existing ownership matching alone cannot cause an unapproved child controller
  reload. Default/no opt-in child changes select root before lifecycle mutation.
- Explicit eligible single-child reload works; unapproved children, mixed sibling
  changes and unmatched paths route conservatively. Existing debug state reports
  the actual target. App wrapper/config forwarding is covered.
- App-root callback deferral is regression-tested; a live executable reload
  exercises the deferred path and supported snapshot restoration.
- Narrow graph-extension edit/cleanup/refresh and failure-recovery tests still
  demonstrate their contract with explicit controller opt-in.
- Tests retain useful targeted lifecycle coverage without labeling it universal
  freshness evidence. Add repeated-reload assertions for relevant registrations/
  handlers where meaningful; preserve documented supported snapshot data.
- Compile touched Fennel through project tooling, then constraints, then focused
  units/hot-reload integration/graph-extension suites. Because shared reload
  routing and root scheduling change, run the full relevant local test gate and
  the live hot-reload harness. Use standard absolute asset/macro paths, disabled
  audio, external temporary XDG data and skipped keyring tests.
- Docs contain a source-grounded comparison with both external links, a usable
  author checklist, current inventory and explicit limitations.

## Non-goals

No automatic import graph, declared dependency engine, selective multi-unit
executor, service container, universal disposer interception, state-transform
registry, direct-tool routing redesign, transactional swap, versioned state
migration, async quiescence protocol, sandbox or multiplayer synchronization.
No unrelated fixes to activity restore contracts or broad refactors.

## Diagnostic evidence: deferred callback forwarding

Observed by read-only source tracing at baseline
`524a2ab9044ae3d78c75cc9ef674fc9f4bfe68e1`, branch `juicyrebel/opah`, clean tree:

- `main.fnl:451-478` registers a callback that calls `reload-now!`, supplies
  `on-reload-requested`, and constructs `AppRootController`.
- `hot-reload.fnl:476-489` invokes that option if present, otherwise reloads
  inline from controller update.
- `hot-reload.fnl:528-558` constructs the generic controller without forwarding
  the callback. This differs from the generic controller's working option path
  and contradicts the documented root execution rule.
- Hypothesis: wrapper option loss prevents main's intended deferral. This is a
  static control-flow diagnosis, not a claim of a reproduced crash.
- Proposed minimal experiment: construct the root wrapper with a callback spy,
  drive a debounced change through a test watcher, verify a request occurs once
  and no unload occurs until explicit `reload-now!`. The baseline should fail.
- Proposed fix if confirmed by advisor: forward `on-reload-requested` unchanged;
  test the wrapper rather than only direct generic-controller construction.
- Confirm with focused unit/controller tests and `make test-live-hot-reload`.

## Implementation structure

Plan two sequential implementation slices: (1) controller eligibility and
confirmed callback forwarding with focused regression tests and explicit
extension opt-in; (2) canonical documentation and inventory/external comparison.
Each slice receives independent review. Finish with clean-tree validation
against current `origin/main`, then the repository's PR/merge-queue workflow.
