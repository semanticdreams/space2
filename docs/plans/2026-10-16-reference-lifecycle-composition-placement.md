# Reference Lifecycle Composition Placement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete approved lifecycle Task7 without increasing accepted structural debt or changing application ownership/startup behavior.

**Architecture:** Place new explicit store/five-owner helpers in the existing built-in composition module; Main still controls sequencing. Extract HomeWorld's existing graph/temporary-loader/map-manager construction into one focused helper, analogous to its existing canvas-runtime separation.

**Tech Stack:** Native Space Fennel, existing canonical stores/owners, GraphExtensionRegistry and GraphMapManager.

## Global Constraints

- Existing Task7 brief remains authoritative; no product/public behavior/ownership change.
- BASE `753cc2e7577d4f3dee690af1c9f294ae201f7bf9`; preserve all existing dirty work and empty index. Workers never stage/commit/integrate/reset/rebase/clean.
- No new/increased baseline exceptions, suppressions, threshold changes or whitespace compression to game measures.
- No registry/default-publication framework, global service fallback, default resets or process-control change. Preserve upstream live-dev ownership.
- New helper module/functions have zero raw findings and no baseline exceptions. Refresh existing fingerprints only with source-continuous unchanged/reduced measures.
- Supervisor commits this bounded technical refinement with the independently reviewed atomic Task7 implementation, not an incomplete API/listener checkpoint.

## Diagnosis

Evidence `.superpowers/sdd/2026-10-15-reference-lifecycle-29954b47/task-7-architecture-evidence.md`: compile53 passes; Main module2244→2275/drop160→163 and HomeWorld module1294→1299/factory820→825 cannot receive increased allowances. Planner selected the bounded placement below; it changes organization, not approved lifecycle semantics.

### Task 7 Addendum: Explicit Composition and Graph Runtime Placement

**Files:** Modify `assets/lua/main.fnl`, `assets/lua/graph/extensions/builtins/composition.fnl`, `assets/lua/home-world.fnl`; create `assets/lua/home-world-graph-runtime.fnl`. Existing Task7 Board/test/baseline scope remains. Briefly document the explicit composition/temporary-loader boundary in `docs/dev/notes/graph.md` through implementer and review.

**Interfaces:** Composition exports `init-reference-stores!(application)->Stores`, `start-reference-lifecycle!(application,stores)->MigrationReport`, `clear-reference-composition!(application)->nil`, preserving existing `ensure!`. New helper exports `create(world,ctx,registry)->(Graph,GraphMapManager,GraphMap)` as native multiple return values.

- [ ] Move exactly current new Main `init-reference-stores` and `init-reference-lifecycle` into existing composition module, renaming/exporting as above and replacing global app references with explicit application. Preserve Identity-first lazy defaults, all published store fields, normalized roots/exact providers, fixed five-owner order and publication of service before start so failed startup cleanup can see it. Return actual start result.
- [ ] Main calls composition at existing boundaries: WorldManager exists → service.start! succeeds → built-in extensions → user code → activate-first. Reuse the composition import for existing ensure wrapper; do not touch run-app or process control.
- [ ] Replace only Main's current store/lifecycle-clear block after WorldManager drop and before existing activity/extension teardown with:

```fennel
(fn clear-reference-composition! [application]
  (when application.reference-lifecycle
    (application.reference-lifecycle.committed:clear))
  (set application.reference-lifecycle nil)
  (each [_ field (ipairs [:string-store :code-store :identity-store :list-store
                          :dict-store :link-store :notebook-store :workflow-store])]
    (tset application field nil))
  nil)
```

- [ ] Move HomeWorld's coherent Graph/temporary restore-runtime install/GraphMapManager construction/uninstall block into new helper. Keep substantial functions focused and preserve all original error boundaries, including graph drop on install/manager failure and propagated uninstall failure. Manager constructs active map while temporary loaders exist; never manually restore or construct competing GraphMap. HomeWorld consumes `(local (graph graph-map-manager graph-map) (HomeWorldGraphRuntime.create world ctx app.graph-extension-registry))`.
- [ ] Preserve permanent runtime installation/context fields and teardown: permanent registry uninstall → scene drop → maps-change disconnect → manager drop → graph drop. No store ownership or inactive-map hydration policy changes. Graph receives same explicit string/link/identity stores and lifecycle as already-approved Task7 wiring.
- [ ] Correct two new Board silent-fallback findings via explicit required-data checks/canonical optional normalization, not baselines or changed frontend semantics. Require Main module≤2244/drop≤160, HomeWorld module<1294/factory<820; no structural debt transferred to helper/composition.
- [ ] Native compile all changed/untracked Fennel first, canonical repo constraints second, focused startup5/Board3/action12/browser6 third using existing task7-check helper. Keep all genuine preimplementation RED assertions and both canonical/custom browser variants. Any changed source invalidates downstream snapshot claims.
- [ ] Run exact plumbing7 and workflow-store9 through its direct native module; derive/audit actual nonzero rosters for lifecycle/morph/workflow/entity/notebook/Board/main-events/reload/live-dev/startup guards. Preserve map-only byte comparisons, explicit identity delete semantics, checked provider conflict and startup recovery cases.
- [ ] Since startup is high risk, run standard audio-disabled/keyring-skipped/external-XDG `make test` after focused gates. Unexpected required failure requires systematic diagnosis/advisor, not bypass. Full feature Task8/PR CI/current-origin finishing still apply.
- [ ] Produce complete BASE-relative tracked+untracked diff/source SHA256, exact command/roster audits, baseline continuity accounting and unchanged-index check; independent Task7 reviewer covers this addendum and complete atomic cutover together. No partial commit/readiness claim.

## Validation and Self-Review

Existing fresh native executable remains valid unless native scaffolding changes; otherwise make build timeout14400000 (configuration600000). Use absolute assets/Fennel/macro paths, audio disabled, keyring skipped, external XDG. Native commands go through tools.fennel-check and constraints.runner repo target; no system compiler or explicit-file baseline bypass.

This one bounded placement task implements existing approved responsibilities without changing sequencing, loader lifetime, ownership or public APIs. No genuine human product/data/API decision remains. Broader extraction/new debt/default framework would require renewed planning rather than silently expanding scope.
