# Link Endpoint Presentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix PR269's confirmed snapshot regression without exposing generated reference UUIDs or replacing deliberate aliases.

**Architecture:** Resolve endpoint meaning through the owning LinkStore's IdentityStore only for display. Keep canonical records untouched by rendering and use side-specific authoring handlers with scoped presentation guards. Current-reference Swap reads the stored pair before either write.

**Tech Stack:** Native Space Fennel, existing Input/Signal widgets and LinkEntityStore, native Xvfb E2E, repository constraints.

## Global Constraints

- Advisor confirmed root cause/policy; evidence `.superpowers/sdd/2026-10-15-reference-lifecycle-29954b47/ci-link-snapshot-debug-evidence.md`. No human product ambiguity remains: passive terminal meaning and deliberate verbatim aliases are distinct.
- Modify only the two link modules, existing link tests and exact affected baseline rows if necessary. No store, generic adapter, Input framework, E2E fixture/golden/tolerance, registry or dependency changes.
- Rendering/refresh performs zero owning writes/signals/identity allocation. Edits remain immediate, verbatim and side-specific; untouched explicit aliases stay exact, including same-terminal aliases.
- Swap exchanges current canonical strings, not displayed terminals/constructor snapshots. Preserve existing two-write boundary, no transaction invention.
- No new/increased baseline allowance, broad regeneration, swallowed resolution errors or typing/submission-policy changes.
- Workers preserve all diagnostics/actual images and never stage/commit/push/fetch/merge/rebase/reset/clean. Supervisor commits only reviewed changes and handles capabilities/PR269.

### Task 1: Alias-Safe Presentation and Native Validation

**Files:** `assets/lua/graph/nodes/link-entity.fnl`; `assets/lua/graph/view/views/link-entity.fnl`; `assets/lua/tests/test-link-entities.fnl`; existing affected entries only in `assets/lua/constraints/baseline-data.fnl`. No additional documentation rewrite is needed for this correction; this plan records its presentation contract.

**Interfaces:** Preserve node canonical get-entity/update-source/update-target/update-metadata and view exports/layout. Add node:endpoint-text(key:string|nil)->string delegating to owning IdentityStore.resolve-key without ensure. make-label(store,entity) resolves both endpoints before existing20-character truncation/separator/incomplete fallback. View-private state holds node/inputs/presenting?; top-level named handlers keep builders focused.

- [ ] Verify branch/head/index and save original golden/actual/comparison hashes in a fresh ignored build/ci-link-snapshot subdirectory. Do not overwrite prior diagnostic artifacts.
- [ ] Declare11 `link endpoint presentation ` cases below before native behavioral RED. Existing17 cases remain; new unfiltered roster28. Real stores/widgets and scoped delegating observation, protected teardown, no fake normalization.
- [ ] Add display helper; resolve errors propagate, absent/empty-target identity semantics remain explicit. Never mutate returned canonical entity or replace its authored references with display values.
- [ ] Resolve both initial display strings before Input construction, supply constructor text and remove authoring set-text initialization. No node.changed subscription that replaces typed alias text.
- [ ] Extract focused named view handlers, retaining existing returned literal/drop ownership. Programmatic display wraps input:set-text in a pcall-restored per-view guard; actual changes invoke only matching node:update-source/target with exact text.

```fennel
(fn set-presented-text! [state input text]
  (local previous state.presenting?)
  (set state.presenting? true)
  (local (ok err) (pcall input.set-text input text {:reset-cursor? false}))
  (set state.presenting? previous)
  (when (not ok) (error err 0)))
```

- [ ] Use Selected resolves intended display before persistence, authors exact selected key once on its side, then guarded display. Zero/multiple selections retain existing no-op behavior and opposite reference/input.
- [ ] Swap reads/copies both current stored strings at click time, resolves reversed displays before writes, calls update-source(old-target)/update-target(old-source) once each, then guarded display. Deliberate typed aliases remain untouched while editing.
- [ ] Fix new-code constraints via named helpers, not exceptions. Only source-continuous original rule/function rows with unchanged/reduced measures may move/remove; retain complete before/current mapping and baseline self-length accounting.
- [ ] Run validation below and self-review field/write counts, exact disk/held aliases, error/guard restoration, unchanged layout/golden and full scope. Independent full review/fix loop precedes supervisor commit.

## Permanent Eleven-Case Roster

1. `construction and refresh preserve distinct aliases without writes`: distinct Z/A same terminal, open twice/layout/update/label refresh, terminal display but exact stored pair, zero update/JSON-write/identity-created/link-updated and identical bytes; fresh random IDs yield identical display.
2. `source edit preserves target alias`: source-only submitted fields, nonlowest opposite exact in held/store/disk.
3. `target edit preserves source alias`: symmetric side-only preservation.
4. `metadata preserves both aliases`: metadata Input replacement does not author, explicit metadata update submits metadata only and retains exact endpoints.
5. `swap preserves distinct same-terminal keys`: stored Z/A→A/Z despite equal display, exactly two side writes.
6. `swap reads current source after edit`: edit source C then Swap→A/C.
7. `swap reads current target after edit`: edit target C then Swap→C/Z; current external update participates too.
8. `explicit typed aliases retain exact identity`: replacement/native text-input completion preserves nonlowest alias and typed text across label refresh.
9. `selection authoring is side specific`: actual callbacks explicit Z versus raw terminal normalize appropriately once, opposite unchanged; zero/multiple selection no update.
10. `empty and unresolved endpoints stay explicit`: empty/missing identity/empty-target identity/raw legacy read-only cases render without allocation, retain exact opposite refs through edits/metadata, Swap exact values.
11. `resolver failures surface without presentation writes`: self/two-node cycles/depth>32 fail explicitly without bytes changing; pre-resolution fails before authoring; injected presentation error restores guard and subsequent real edits work.

## Validation Ladder and Integration

Use absolute assets/Fennel/macro paths, audio disabled/keyring skipped/external XDG; remove snapshot-update/test-filter overrides except intentional selections. Runtime is fresh; rebuild only missing/stale/native changes with timeout14400000. Native compile first (touched files or make fennel-check), canonical repo constraints second (timeout600000), focused tests third. Syntax/depth repairs inspect nearest enclosing forms/name helpers, not baseline new findings.

Verified unit entry exists: `TEST_VERBOSE=1 TEST_FILTER='link endpoint presentation ' xvfb-run -a ./build/space -m tests.test-link-entities:main` must actually execute11 unique names, then unfiltered module28. Run existing identity/write/link/projection guards with actual nonzero roster audits. Native runner allows zero matches, so reject zero or count/name mismatch.

Run `SPACE_SNAPSHOT_OUTPUT_DIR=<fresh-output> SDL_VIDEODRIVER=x11 xvfb-run -a -s '-screen 0 1280x720x24' ./build/space -m tests.e2e.test-link-entity-view:main` twice with independent fresh stores/output directories. Require exactly one fixture/capture per run, decoded pixel equality with unchanged golden and between both runs; inspect captures visually. Golden SHA256 must remain `fc2857cc7256109dd4a29bfeccf3428fe8a00901e4b222cb41913a973c648b1d`.

Then full native `make test-e2e` under authorized Xvfb/host harness (no update flag/tolerance adjustment) and standard `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test`, generous timeout14400000 for transitive builds/full checks. Unexpected failures require diagnostic/advisor loop before speculative fixes. Store exact commands/native statuses/positive names/counts/source+binary+golden hashes and complete frozen diff/manifest.

After review pass and commit, validate clean/current origin through guarded capability and rerun required tests, push reviewed fix/requeue PR269 and poll until mergedAt. Do not merge origin solely for post-queue advancement, rebase/force-push, suppress gates or claim success at queue handoff. PR CI remains authoritative.

## Self-Review

One coherent presentation correction preserves existing authoring/alias/store responsibilities, fixes both passive writes and UUID leakage, and protects all editing paths rather than blessing a screenshot. Scope is four source files at most; no unrequested fifth-file note cleanup or generic framework. All added interfaces are defined above and each observable contract has a named native case.
