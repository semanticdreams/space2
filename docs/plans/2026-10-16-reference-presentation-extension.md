# Reference Presentation Extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore list terminal labels and correctly owned notebook previews without rewriting canonical references or authoring data.

**Architecture:** Resolve display through each container's owning IdentityStore; actions retain canonical keys. Notebook previews obtain concrete adapters through the existing graph's registered loaders, never another default store. Existing String preview initialization becomes silent while real editing stays immediate.

**Tech Stack:** Native Space Fennel, existing widgets/stores/graph loaders, repository constraints, native Xvfb E2E.

## Global Constraints

- Evidence `.superpowers/sdd/2026-10-16-link-endpoint-presentation-72d8bee0/{task-1-report,list-snapshot-debug-evidence,notebook-snapshot-debug-evidence}.md`; advisors confirmed both causes and existing identity-invisible/exact-authored-alias policy. No new product decision.
- This extends the original four-file link plan. Its full-E2E requirement becomes a GLOBAL completion gate after Tasks2–3: known RED remains blocking, not waived. Task1 functional contract remains unchanged.
- Passive presentation causes zero domain writes/success signals/identity allocation, preserves held records/bytes, and keeps distinct same-terminal aliases/order/callbacks/layout. Existing equal-name store no-ops need not become zero method calls.
- No store/generic Graph/Input framework/registry/dependency/fixture/golden/tolerance changes, new module/API/framework, navigation action or automatic alias subscription system.
- Baseline only necessary existing source-continuous same-rule/function unchanged/reduced rows/removals/self tightening; preserve frozen Task1 delta, no debt transfer/new allowance/regeneration.
- One implementer at a time. Frozen Task1 review → Task2 implementation/review → Task3 implementation/review → combined review/full gates. No implementation commits/push until reviewed combined delta is fully green. Workers never stage/commit/remotely integrate/reset/clean.
- Supervisor commits this plan path alone; existing dirty implementation and PNG evidence remain untouched. Expected plan-only HEAD advance is allowed; never reset to source BASEc90e7fa.

## Preflight and Task1 Review

- [ ] Preserve original link actual and new list/notebook actual images in ignored evidence. Verify frozen4 sources against task1 report/current hashes before shared baseline changes.
- [ ] Independent reviewer inspects frozen Task1 four-file delta/native11+28/guards92/unchanged-golden link2runs/fullmake test30 evidence. Task1 checkpoint review does not claim known list/notebook full E2E passes. Three link files stay frozen afterward; shared baseline additions remain separately attributable.

### Task 2: List Item Presentation

**Files:** `assets/lua/graph/view/views/list-entity.fnl`, `assets/lua/tests/test-list-entities.fnl`, exact existing baseline entries only if necessary.

**Interfaces:** Private build-item-rows(identity-store,items)→array `{index,total,key,text}`; public view unchanged. Consume owning target.store.identity-store.resolve-key; existing remove/move/add/name/focus APIs unchanged.

- [ ] Add8 `list item presentation ` cases before native RED, retaining28 old cases (8selected/36all): passive display preserves canonical aliases; duplicate semantics retain distinct aliases; move callbacks preserve exact order after refresh; remove targets canonical alias only; selection authoring preserves explicit references; focus uses canonical existing key without opening/loading; name-only edit preserves membership; unresolved and resolver errors do not author.
- [ ] Cases use real stores/widgets/actual callbacks, current order/indices/boundaries/first-occurrence normalization, same-terminal explicit Z/A, unchanged bytes/signals/allocations on repeat open/refresh/draw, canonical focus lookup reason list-entity with no loads, exact metadata/name payload, raw/missing/empty-target/chains/cycles/depth/read errors. Capture real expected behavior RED; compatibility guards may already pass, report honestly.
- [ ] Resolve complete row array before publishing item/count. Truncate text28 characters, not key; never ensure/sort/dedup/load/mutate. Canonical keys remain remove/focus callback arguments, moves use current index/total. Selection/name/delete and lifecycle/drop subscriptions unchanged; focused helpers/final literal avoid debt.

```fennel
(fn build-item-rows [identity-store items]
  (local total (length items))
  (icollect [i key (ipairs items)]
    (local text (identity-store:resolve-key key))
    {:index i :total total :key key :text text}))
```

- [ ] Native compile touched files→canonical repo constraints0→audited8/36→two fresh list E2Es pixel-exact unchanged golden. Freeze input-relative diff/sources/commands/native statuses/baseline mapping/hash/visual evidence; independent Task2 review before Task3. No implementation commit while notebook global blocker remains.

### Task 3: Notebook Preview Ownership and Silent String Initialization

**Files:** `assets/lua/graph/view/views/notebook.fnl`, `assets/lua/graph/view/previews/string-entity.fnl`, `assets/lua/tests/test-notebooks.fnl`; necessary exact existing baseline rows only. One focused canonical provider/presentation clarification in existing `docs/dev/features/reference-lifecycle.md` is authorized, no companion page/unrelated cleanup.

**Interfaces:** Private rows `{index,total,key,terminal-key}` through owning NotebookStore.IdentityStore. resolve-preview-node(target,terminal-key)→graph-owned adapter|nil via containing graph:load-by-key; preserve registered loader's exact content provider/root/lifecycle. Existing view/preview exports/builders/fields/drop contract unchanged; no substitute defaults.

- [ ] Add10 `notebook preview presentation ` cases, retaining29 old cases (10selected/39all). Module returns bare array, no :main. Roster: owning identity and configured concrete content provider; passive construction and refresh never author content; alias chains resolve current concrete type without reauthoring; distinct aliases keep canonical remove and move identities; metadata and content edits use isolated payloads; selection and string creation retain canonical ownership; missing targets use explicit nonauthoring fallback; cycles and depth exhaustion surface before preview authoring; required concrete preview failures surface; refresh teardown preserves adapter and callback ownership.
- [ ] Real callback/provider tests distinguish registered content store from same-ID graph/node default decoys; repeated open/refresh/layout/drop zero writes/signals/allocation, source/decoy bytes unchanged; exact canonical action order/aliases, name-only vs concrete value-only payloads; explicit string creation legitimately owns new content/membership; adapter lifecycle remains graph-owned after row widget drop/disconnect.
- [ ] Native RED proves wrong owning resolver and passive String preview initialization writes independently. Compile/constraints block setup errors; don't treat missing API/parse as behavioral RED.
- [ ] Resolve all row keys with notebook owner before preview publication. For concrete terminal key invoke existing graph load path, not graph identity re-resolution or replacement provider. Missing/empty-target identity, absent graph, genuinely nil load and unknown scheme retain explicit terminal/unresolved Text fallback (existing42-char truncation); derive type from terminal key. Cycles/depth/required owner/read/loader/invalid preview/builder/layout errors propagate, never swallowed as absence.
- [ ] Available adapters must provide callable preview/builder with layout; reuse graph-owned adapter but own/drop preview widgets exactly once. Keep canonical remove/move/select/open and separate name/content authoring payloads. No new navigation/subscriptions.
- [ ] Initialize existing String Input directly via constructor text from real node; remove authoring set-text initialization, retain ordinary on-change update-value/options. No generic Input policy change.

```fennel
(local input
  ((Input {:text (or (and entity entity.value) "") :placeholder "Value..."
           :multiline? true :min-lines 3 :max-lines 3
           :on-change (fn [_input text]
                        (when (and target target.update-value) (target:update-value text)))}) build-ctx))
```

- [ ] Compile→constraints0→audited10/39→two fresh notebook E2Es pixel-exact unchanged golden. Freeze Task3 diff relative Task2 snapshot, all source/evidence/baseline hashes; independent Task3 and final combined review before commit.

## Native Validation and Global Completion

Use absolute assets/Fennel/macro paths, audio disabled/keyring skipped/external XDG, isolated log roots; unset accidental filters/update flags. Runtime fresh; rebuild only missing/stale/native changes (make build timeout14400000). All standalone constraints timeout600000, compile first then canonical repo constraints, tests third.

List selected: `TEST_VERBOSE=1 TEST_FILTER='list item presentation ' xvfb-run -a ./build/space -m tests.test-list-entities:main`, then module unfiltered36. Notebook selected/all use `./build/space -c '((. (require :tests/runner) :run-modules) {:name "notebook-preview" :modules [:tests.test-notebooks]})'`, TEST_FILTER prefix selects10; unfiltered39. Explicitly audit bare-array registrations/unique RUN/PASS/summary/native exit, reject zero/mismatch.

For fixture list-entity/notebook separately, two fresh native processes: `SPACE_SNAPSHOT_OUTPUT_DIR=<new-output> SDL_VIDEODRIVER=x11 xvfb-run -a -s '-screen 0 1280x720x24' ./build/space -m tests.e2e.test-<fixture>-view:main`. Delegating capture observer may prove exactly1 capture, no behavior replacement. Read both images visually; decoded RGBA golden/run1/run2 must be exactly equal, not merely within tolerance.

Unchanged golden SHA256: link `fc2857cc7256109dd4a29bfeccf3428fe8a00901e4b222cb41913a973c648b1d`; list `ffe0e32190ce3d95cddfcf8ee64256b7f2e40eabf21327e6af35cfde084cbeee`; notebook `446fa6008d4b9b2111452bd62430c4233b0706bf97df1c124326d79feee45405`.

Rerun28 link cases and current identity/write/projection/link-crash guards (previous92/module4/21/30/36/1, reconcile actual names if source changes). Mandatory combined full `make test-e2e` with fresh output and no update flag, then standard audio-off/keyring-skip/external-XDG/absolute-assets `make test`, timeout14400000. Source E2E roster has42 fixture-main calls; rederive counts, not guessed13. Prior12-after-list diagnostics included notebook (11passed/1failed),18passingPNGs pixel0; FS viewer intentionally0captures. They are diagnostic evidence, not combined full-green.

Required failure returns diagnostic/advisor loop, not ready/partial commit. After all reviewed combined green, supervisor commits exact reviewed source/doc paths, verifies clean/current origin and relevant/full checks, guarded push/requeue PR269, polls until mergedAt. No rebase/force-push/origin chase solely queue advancement; PR CI authoritative.

## Self-Review

Each of18 new cases has concrete native entry/count and alias/provider/write/error assertions. Shared baseline edits have task-specific snapshots; link functional hashes remain frozen across list/notebook work. Responsibility stays in existing views/preview, no general framework or golden blessing. This explicit extension retains all earlier contracts while moving only the known shared full-suite gate to the final combined checkpoint.
