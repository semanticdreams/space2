# Reference Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve logical relationships and presentation through string-to-code morphing, and durably remove every supported live incoming reference when an object is genuinely deleted.

**Architecture:** Extend the existing IdentityStore with graph-independent stable-reference operations, normalize references at owning-store write boundaries, and coordinate logical deletion and morphing through one explicitly composed application service. Five fixed owners cover entities/containers, identities, workflow definitions, persisted worlds, and loaded presentation runtimes; a small durable pending intent makes interrupted operations resumable without claiming multi-file atomicity. Keep the existing catalog, lazy default-store APIs, graph-node action names, and store ownership boundaries.

**Tech Stack:** Space-native Fennel/Lua, C++17 filesystem bindings, existing Signal and JSON utilities, native `tests.fast` runner, CTest/Make, GitHub PR CI.

## Global Constraints

- “Morph preserves links, ordered container membership, and presentation context.”
- “Map-only removal never edits owning-domain records.”
- “Distinct explicit identities are not merged simply because their current target happens to match.”
- “Root/instance mismatches during composition are explicit errors.”
- “No compatibility option aliases or new default-publication framework are introduced.”
- “Store caches/signals publish only after successful persistence; required enumeration/read/write/remove failures are surfaced immediately.”
- “Generic external graph keys remain valid reference values without implying filesystem/session deletion support.”
- “Histories, execution events, logs, and provenance snapshots are not live incoming references.”
- “Changes span files, so do not promise atomic multi-file transactions.”
- “Use existing atomic JSON utilities and a single-writer, serialized-operation contract; do not introduce a CLI, general transaction engine, cross-process atomicity, or automatic concurrent-writer merging.”
- “This change requires the full local test suite before finishing, plus applicable PR CI.”

**Authority and staging**

- Source of truth: `docs/specs/2026-10-15-reference-lifecycle-design.md`, committed in `f2002a6`; repository evidence includes the `524a2ab9` catalog/composition boundary. The catalog is browsing metadata, not a CRUD registry.
- This document persists the full read-only planner response with bounded documentation self-review corrections. Plan review must pass before the supervisor commits `docs/plans/2026-10-15-reference-lifecycle.md` or starts production edits. No commands or experiments were run by the planner; persistence is not implementation or validation evidence.
- Execute Tasks 1–8 in order. Before each stage, reread the relevant source and spec, inspect branch changes, and verify the preceding task’s exported contracts. Report evidence drift before changing the contract.
- These are reviewed staging commits for one feature, not independently shippable partial lifecycle guarantees. Do not activate lifecycle commands in Main until all five real owners exist.
- Every checkpoint requires focused GREEN evidence and `implementer` → `reviewer` → pass. The supervisor owns commits; implementers do not commit unreviewed changes.
- Every task extraction must include this Shared implementation contracts section and the common validation helper verbatim, plus that task's Interfaces; implementers must not need to reread the entire plan to reconstruct cross-stage contracts.
- New factories construct a final `self` literal containing their methods. Keep helpers focused; do not introduce constructor/factory pairs, per-store lifecycle binding infrastructure, monkeypatched production methods, a universal registry, or a default-store publication module.
- Existing graph-node adapter extension idioms need not be broadly rewritten. Local changes remain production-ready because persistence stays with existing owners and coordination is explicit and bounded.

**Shared implementation contracts**

- `Stores` is `{base-dir, string-store, code-store, list-store, dict-store, link-store, identity-store, notebook-store, workflow-store}`. All paths use one normalized `fs.absolute(base-dir)`; all reference-bearing stores share the identical IdentityStore object.
- `Snapshot` is `{path: string, bytes: string|false, value: table|false, check: string|false}`. `RecordUtils.snapshot(path,format,decode)->Snapshot` requires an explicit pure function `decode(bytes:string)->owning-domain-record` for every format, including JSON. `value` is that decoded domain record, not the serialized representation; `bytes` preserves the original raw persisted bytes. `check` always comes from `RecordUtils.check-bytes(bytes,format)`, independently of the decoder: stable JSON of parsed original bytes for JSON, exact original bytes for string/Markdown. An absent record returns `bytes=value=check=false` without invoking `decode`; unreadable/malformed required records throw with the path. The generic helper never dispatches on paths or imports domain modules; stores supply their own pure decoders, and WorldOwner explicitly supplies `json.loads` for world/metadata records.
- `Site` is `{address: string, field: array, target-key: string, kind: string}`. Fields identify documented schema locations, never arbitrary recursive string matches.
- `Inventory` is `{records: {graph-key: {address, value, snapshot}}, sites: [Site]}`.
- Fixed owner IDs are `"entities"`, `"identities"`, `"workflows"`, `"worlds"`, `"runtime"`. `Owner` has `id: string`, `base-dir: string`, and the following methods: `preflight!() -> true`, `inventory() -> Inventory`, `expand(inventory, operation) -> [graph-key]`, `prepare(inventory, operation) -> Preparation`, `apply!(change) -> nil`, and `reconcile!(intent) -> nil`. Factories validate their injected canonical stores/root; empty test owners expose this same contract.
- `Preparation` is `{changes:[Change], runtime-state:[RuntimeCapture]}`. Every owner returns both arrays, including empty arrays; entities/identities/workflows and WorldOwner return an empty `runtime-state`. RuntimeOwner returns empty `changes` and the frozen transient captures. Migration adds its `operation` and `dangling:[Site]` to the aggregated Preparation.
- `RuntimeCapture` is JSON-safe `{owner:string, world-id:string, map-id:string|false, before:ReferenceState, after:ReferenceState}`. The returning owner supplies its fixed ID; Plan validates/tags this namespace and rejects duplicate `(owner,world-id,map-id)` captures. IDs are persisted native world/map IDs, never adapter tables, generated runtime identities or paths. `ReferenceState` is `{board?:native-board-state, maps?:native-graph-state, views?:native-view-state, metadata?:native-map-metadata}`; absent fields mean that schema is not captured, not arbitrary extension keys.
- Capture fields keep native schema roles: `board` contains ordered items (IDs, subject keys/types, transform/state) and connectors with semantic link IDs; `maps` contains the native map records (IDs, node keys, explicit edge endpoints/attributes, selected/focused keys, outline roots, island members and ordered-list `state.list-key`); `views` contains native `open-views`, graph-owned panels/`extra_panels`, selected/focused keys and `mode_states.spatial` panel/focus state, retaining cameras; `metadata` contains native representation-keyed `positions`, `sizes`, `presentations`, `panels` and `extra_panels` node keys. A `map-id=false` capture holds world/board/session state; a map capture holds that map's topology/view/metadata, not unrelated maps. These are schema-owned records, not recursive arbitrary-key rewriting.
- Capture mirror roles are explicit: the world/board capture retains distinct native board model, `state.board`, `runtime.board-state`, `activity.sessions.board.board-state` and the board slot of `runtime.activity-session-state`; it does not collapse them into one anonymous table. Map/view captures retain their map's native view, `views.open-views`, graph-owned canvas/HUD panels, `activity.sessions.graph.graph-view-states`/`graph-view-state` and corresponding retained runtime graph/session snapshots as separate schema-role records within `views`. `metadata` retains that map's native persistence cache, not another durable path writer. Before/after use identical role structure and JSON-safe native serialization; role presence is frozen during preparation, with no adapter objects and no later discovery of arbitrary keys.
- `Change` is `{owner, address, path, format:"json"|"string", phase:"replacement"|"incoming"|"retire", before-check:string|false, after-check:string|false, after-bytes:string|false}`. `after-bytes` is the frozen owner-serialized representation, never a domain table. Before/after checks are computed only with `RecordUtils.check-bytes` on persisted snapshot bytes/frozen serialized bytes. Every durable change is journaled before application. One owner record/path receives one aggregated change even when several sites change; duplicate normalized persistence paths after aggregation are an ownership error, never last-writer-wins.
- Prepared store persistence decodes `after-bytes` through pure `decode-entity(bytes)`, `decode-notebook(bytes)` or `decode-definition(bytes)`, without generating timestamps or wrapping references, then verifies that reserialization's `check-bytes` equals `after-check` before writing. Writes use the canonical serialized payload and existing atomic JSON utility (JSON whitespace may vary but the stable check must match). Publish the decoded candidate only after successful persistence, preserving any held cached record's identity; failed writes leave it unchanged, and failed publication/signals leave an explicit pending operation. The journal stores serialized workflow ISO timestamps, not in-memory numeric timestamps.
- WorldOwner exclusively prepares/applies durable `world.json` and map `metadata.json` Changes, merging loaded **nonpersisting** snapshots into those after-images before serialization. RuntimeOwner emits no durable Changes: it captures transient native state during preparation and reconciles only supplied `intent.runtime-state`, without recapture or saving. Live/model/cache/view installation is nonpersisting, limited to still-loaded matching world/map IDs, and never activates missing worlds/maps. Startup with no loaded maps safely skips transient installation; durable WorldOwner after-images remain the source of truth on later activation. Reconciliation failure retains the pending intent.
- `Operation` is `{kind: "delete"|"morph"|"migrate", source-key: string|false, target-key: string|false, retiring: [graph-key], updated-identity-keys: [graph-key], replacement: table|false, reference-plan: ReferencePlan, timestamp: number}`.
- `ReferencePlan` is `{rewrites: [{from-key: string, to-key: string}], identities: [{id: string, target-key: string, created-at: number, updated-at: number, metadata: table}]}`. Every operation carries both arrays; delete uses empty arrays. Each `to-key` is `identity:<id>`. Sort rewrites by `from-key` and reserved identities by ID. Reserve complete records/timestamps once without mutating a store; reuse the lexicographically lowest existing direct identity. Preserve supplied explicit identities/chains. `replacement` remains the morph representation record, never an overloaded reservation container.
- Only the canonical Site kinds `list-item` (`items[index]`), `notebook-item` (`items[index]`), `dict-slot` (`items[name]`), `link-source` (`source-key`), `link-target` (`target-key`), and `board-subject` (`subject-key`) consume stable-key rewrites. Identity targets, typed workflow code IDs, board semantic-link IDs, and concrete graph representation keys do not; their deletion/replacement transformations remain owner-specific. IdentitiesOwner consumes `reference-plan.identities` to prepare identity-creation Changes; the other owners consume the applicable `rewrites` without calling ensure-key or synthesizing records into Inventory.
- Owner inventories and preparations are read-only. They must not call today’s persistence-producing GraphView capture or inactive-map hydration paths.
- The service’s fixed-owner protocol is internal coordination, not an extensible registration API. Persistence primitives exported by stores are **INTERNAL by contract**; application/user deletion must not call them.
- `Lifecycle:owns-store?(scheme:string, store:table)->boolean` checks exact canonical store identity for the supported scheme, including reference-holder identity-store dependency and normalized root equality; no equivalent-root substitute/default fallback is accepted. Fixed mapping: `string-entity/code-entity/list-entity/dict-entity/link-entity` to the respective Stores field, `identity` to identity-store, `notebook` to notebook-store, and `workflow-step` to workflow-store; unsupported schemes return false. Graph and GraphMap expose `reference-lifecycle` from canonical `:lifecycle` options; a map inherits its shared Graph's instance and rejects explicit conflicts. A node action chooses explicit node lifecycle or its mounted graph's lifecycle, rejects conflicting instances and ownership/root/dependency mismatches before writes, and errors if detached without explicit injection. Browser factories keep existing exports; mounted acquisition is the deliberate child-node path.
- Until Task 7's same-commit user-intent cutover, keep existing default durable-cleanup projection callbacks. Task 6 adds projection-only reconciliation paths but does not remove/disable those callbacks. Task 7 removes their graph-node-removed/identity-deleted persistence writes when every genuine delete action switches to lifecycle; no staging commit may newly dangle explicit identity deletions.
- New method signatures are defined in these shared contracts or the producing task’s Interfaces before use. Existing native APIs retain their current signatures unless a task explicitly changes them.

**Validation commands used by every task**

Run from the repository root in Bash. First establish runtime freshness: if `./build/space` is missing/stale, run `make build` with the execution tool’s explicit `timeout: 14400000`. Task 3 changes C++ and therefore always requires that build. No CMake changes are planned; if necessary after reviewed CMake changes, `make cmake` requires `timeout: 600000`.

```bash
set -e
export SPACE_ASSETS_PATH="$(pwd)/assets"
export FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl"
export FENNEL_MACRO_PATH="$FENNEL_PATH"
export SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1
export XDG_DATA_HOME=/tmp/space/tests/xdg-data

run_focused() {
    local filter="$1" expected_count="${2:-}" module="${3:-tests.fast:main}"
    TEST_FILTER="$filter" TEST_VERBOSE=1 python3 - "$filter" "$expected_count" "$module" <<'PY'
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

literal_filter, expected, module = sys.argv[1:]
# Runtime freshness already established that the ignored build/ parent exists.
with tempfile.NamedTemporaryFile(mode="w", prefix="reference-lifecycle-focused-",
                                 suffix=".log", dir="build", delete=False) as log:
    log_path = Path(log.name)
    result = subprocess.run(["./build/space", "-m", module],
                            env=os.environ, stdout=log, stderr=subprocess.STDOUT)
text = log_path.read_text(encoding="utf-8", errors="replace")
sys.stdout.write(text)
print(f"Focused evidence log: {log_path}")
# Preserve native failure before attempting count/selection validation.
if result.returncode:
    sys.exit(result.returncode if result.returncode > 0 else 128 - result.returncode)
names = re.findall(r"^\[RUN\] (.+)$", text, flags=re.MULTILINE)
counts = re.findall(r"^Executed (\d+) Lua tests\s*$", text, flags=re.MULTILINE)
if len(counts) != 1:
    sys.exit("focused audit: missing or ambiguous Executed N Lua tests summary")
count = int(counts[0])
if count <= 0 or len(names) != count:
    sys.exit(f"focused audit: invalid count {count}, [RUN] names {len(names)}")
if any(literal_filter not in name for name in names):
    sys.exit(f"focused audit: [RUN] name outside literal filter {literal_filter!r}")
if expected and (not expected.isdecimal() or count != int(expected)):
    sys.exit(f"focused audit: expected {expected} tests, executed {count}")
print(f"Focused audit PASS: {count} tests matching {literal_filter!r}")
PY
}

check_stage() {
    local filter="$1"; shift
    local file
    local -a compile=(--target files)
    for file in "$@"; do
        compile+=(--file "assets/lua/$file")
    done
    ./build/space -m tools.fennel-check:main -- "${compile[@]}" &&
    ./build/space -m constraints.runner:main -- --target repo --output json &&
    run_focused "$filter" "${FOCUSED_EXPECTED_COUNT:-}"
}
```

`check_stage` accepts a test filter followed by paths relative to `assets/lua/`; it builds explicit `--target files --file <repo-relative-path>` arguments for compilation, then runs the canonical baseline-aware repository constraints gate. The constraints runner intentionally omits repository baselines for explicit-file targets, which expose accepted pre-existing debt in unchanged Graph factories. Repository validation still blocks new, stale, or worsened findings; it is not a filter or bypass. Fix new-code findings rather than baseline them. Any maintenance of existing line-sensitive baseline fingerprints requires independent review of actual data, unchanged or reduced measures, and no new exceptions. The first check is native compilation, constraints are second, audited focused Fennel tests third. `run_focused(filter, expected_count?)` preserves native exit status and rejects missing/zero execution, mismatched `[RUN]`/summary counts and names outside the literal filter. Logs stay under ignored `build/`; this is a plan-local Bash/Python snippet, not a new CLI/tool or production API. Each task’s command below enumerates its compile targets explicitly. Run it for RED after adding tests and again for GREEN; RED must be the intended behavioral failure, not a parse or unrelated bootstrap failure. Register new test modules in `assets/lua/tests/fast.fnl`, with the literal test-name prefixes given below.

Before each new-prefix RED run, declare its planned **named test roster** and count in the implementation report. Record actual `[RUN]` names and count from the retained log for RED/GREEN, and reject discrepancies at the reviewed stage rather than choosing arbitrary future counts. Set `FOCUSED_EXPECTED_COUNT` to that roster's reviewed count when invoking `check_stage`, or pass it as `run_focused`'s second argument. Its optional third argument selects an existing native module entry point; the default is `tests.fast:main`. The exact workflow-store baseline guard is `run_focused 'workflow-store' 9 tests.test-workflow-store:main`. Task 5 empirically confirmed that the same filter in the fast aggregator also selects two descriptor/start-node tests (eleven total); do not force that broader selection to nine. `workflow store` instead selects temporal tests and is not this guard. Preserve the module and actual roster in validation evidence.

For GREEN validation blocks, use a fresh root Bash shell with `set -e` so a failed compile, constraint, focused check or later command cannot be masked by a subsequent success. The guard loops below also explicitly propagate each failing test’s status with `|| exit $?`. Capture expected RED separately with its nonzero result; never reinterpret a parser/constraint failure as behavioral RED.

For delimiter/parse failures, inspect the nearest enclosing form, isolate the malformed construct, and simplify nested logic into small helpers; rerun compile before constraints/tests. Do not use system Lua/Fennel or unsupported compile flags as an oracle. Record commands, RED/GREEN outcomes, coverage rationale, and constraint impact at every review checkpoint. Before each feature stage’s production edits, record genuine native/user-action integration RED for the affected surface, not only a missing future module/method; preserve those assertions through coordinator cutover. Task 5 specifically requires legacy-path board/inactive-map RED before owner-adapter implementation.

**Observable final acceptance**

| Requirement | Implementation and permanent evidence |
| --- | --- |
| Graph-free identity reuse, distinct aliases, cycle/depth rejection | Tasks 1–2 |
| Every owning relationship write normalized; shared canonical ownership | Tasks 2 and 7 |
| Unopened containers, links-to-links, aliases, relationship cycles | Tasks 3–4 and 8 |
| Workflow code cascade without member/endpoint/history deletion | Tasks 3–4 and 8 |
| Preflight, actual IO failures, pending intent, retry/restart conflicts | Tasks 3–5 and 8 |
| Active/inactive boards, worlds, maps, metadata and session mirrors | Tasks 5–6 and 8 |
| Real authoring/actions, canonical code cache, physical API migration | Tasks 2 and 7–8 |
| Byte-preserved domain data after ordinary map-only removal | Tasks 6–8; default callback cutover in Task 7 |
| Connectivity and native provenance reported separately | Tasks 6 and 8 |
| Startup recovery/migration before world exposure; full integration gate | Tasks 7–8 |

**Explicitly out of scope:** Additional morph types; filesystem/session deletion; history rewriting; a code editor; readonly-Input simulation; universal CRUD/type registration; default-publication redesign; reverse indexes; new CLI tooling; cross-process transactions; broad filesystem/security frameworks; broad graph-edge identity/provenance redesign; performance claims without measurements. Keep existing ignored `build/reference-probe/` diagnostics ignored and unmodified; old diagnostic evaluators are not release gates.

---

### Task 1: Shared Identity Operations and Reusable Native Test Fixtures

**Files:**
- Modify: `assets/lua/entities/identity.fnl`, `assets/lua/graph/core.fnl`, `assets/lua/graph/map.fnl`, `assets/lua/tests/fast.fnl`
- Create: `assets/lua/tests/test-reference-lifecycle-helpers.fnl`, `assets/lua/tests/test-reference-lifecycle-identity.fnl`
- Test: `assets/lua/tests/test-identity-entities.fnl`, `assets/lua/tests/test-reference-lifecycle-identity.fnl`

**Interfaces:**
- Consumes: Existing `IdentityStore`, `get-default(opts)`, `JsonUtils.write-json!`, `fs`, and `Signal`.
- Produces: `IdentityStore:ensure-key(key: string, opts?: table) -> string`; `IdentityStore:resolve-key(key: string, opts?: {max-depth?: number, visited?: table}) -> (terminal-key: string, traversed-identity-keys: [string])`.
- Produces: Existing `Graph:ensure-identity-key` and Graph/GraphMap `resolve-key` delegate to these graph-free operations; ordinary explicit `Graph:create-identity` remains an explicit exposure action.
- Produces test helpers: `with-root(f(root)->any)->any`, `stores(root)->Stores`, `assert-error(fragment,f)->string`, `snapshot-tree(root)->{relative-path:bytes}`, `with-fs-failure(method,path,f)->any`. Helpers create isolated factories, never substitute default getters, and restore native fs functions/resources even after assertions. `with-fs-failure` temporarily wraps only the named entry of the existing native `fs` table, delegates nonmatching paths to the saved native function, and restores the original through protected cleanup before returning or rethrowing the callback error. Do not replace the native table, permanently monkeypatch it, or introduce production monkeypatches/test switches.

- [ ] **Step 1: Add native RED tests, importing future behavior inside test functions.** Use test prefix `"reference lifecycle identity"`. Include a same-root fixture with all existing stores, sharing one explicit IdentityStore; no factory is a default publication mechanism.

```fennel
(local H (require :tests/test-reference-lifecycle-helpers))
(local tests [])
(table.insert tests
  {:name "reference lifecycle identity preserves aliases and deterministic reuse"
   :fn (fn []
         (H.with-root
           (fn [root]
             (local s (H.stores root))
             (s.identity-store:create-entity {:id "z" :target-key "string-entity:s"})
             (s.identity-store:create-entity {:id "a" :target-key "string-entity:s"})
             (assert (= (s.identity-store:ensure-key "string-entity:s") "identity:a"))
             (assert (= (s.identity-store:ensure-key "identity:z") "identity:z"))
             (local (terminal chain) (s.identity-store:resolve-key "identity:z"))
             (assert (= terminal "string-entity:s"))
             (assert (= (. chain 1) "identity:z")))))})
```

- [ ] **Step 2: Add cycle/depth and publication RED cases.** Cover self-cycle, two-record cycle, upstream chain, exactly 32 traversals succeeding, 33 failing, explicit smaller limits, empty identity drafts, missing identity records, and generic external keys. Assert errors contain `"resolve-key identity cycle detected"` or `"resolve-key identity depth exhausted"` and leave files/topology unchanged.
- [ ] **Step 3: Implement ensure/resolve in IdentityStore with small local helpers.** Resolve only identity records, never load graph nodes. Missing/empty identities terminate at their own key; cycles and exhausted limits throw, never return a partial target. For raw-key ensure, sort matching direct identities lexicographically by ID; preserve supplied identity keys exactly.
- [ ] **Step 4: Make identity persistence strict before publishing.** Stop swallowing directory/read/parse/remove errors. Prepare updated copies, persist atomically with JsonUtils, then update the existing cached record in place and emit. Failed create must not cache; failed update/retirement must not mutate held cache records or emit success.
- [ ] **Step 5: Delegate graph helpers without auto-exposing wrappers.** `ensure-identity-key` returns the store key only; ordinary relationship creation must not add identity nodes. Preserve the existing Graph/GraphMap resolver return’s first value and cycle-error wording.
- [ ] **Step 6: Validate RED/GREEN, review, then request supervisor checkpoint.**

```bash
check_stage 'reference lifecycle identity' entities/identity.fnl graph/core.fnl graph/map.fnl \
  tests/fast.fnl tests/test-reference-lifecycle-helpers.fnl \
  tests/test-reference-lifecycle-identity.fnl tests/test-identity-entities.fnl
run_focused 'identity'
```

Acceptance: identity operations have no graph imports or topology effects; all three identity/cache failure checks pass. Suggested reviewed checkpoint: `feat(lua): add graph-independent stable identity operations`.

### Task 2: Owning Reference Write Boundaries and Canonical Identity Injection

**Files:**
- Modify: `assets/lua/entities/list.fnl`, `assets/lua/entities/dict.fnl`, `assets/lua/entities/link.fnl`, `assets/lua/notebooks/store.fnl`
- Modify: `assets/lua/graph/nodes/list-entity.fnl`, `assets/lua/graph/nodes/dict-entity.fnl`, `assets/lua/graph/nodes/notebook.fnl`, `assets/lua/board/view.fnl`, `assets/lua/graph-activity-actions.fnl`
- Modify: `assets/lua/tests/test-reference-lifecycle-helpers.fnl`, `assets/lua/tests/fast.fnl`
- Create: `assets/lua/tests/test-reference-lifecycle-writes.fnl`
- Test/modify: `assets/lua/tests/test-list-entities.fnl`, `assets/lua/tests/test-dict-entities.fnl`, `assets/lua/tests/test-link-entities.fnl`, `assets/lua/tests/test-notebooks.fnl`, `assets/lua/tests/test-string-entity-create-child.fnl`, `assets/lua/tests/test-graph-map.fnl`, `assets/lua/tests/test-board.fnl`, `assets/lua/tests/test-board-activity-string-entities.fnl`, `assets/lua/tests/test-ordered-list-islands.fnl`, `assets/lua/tests/test-graph-view-islands.fnl`, `assets/lua/tests/test-link-entity-crash.fnl`

**Interfaces:**
- Consumes: Task 1 `IdentityStore:ensure-key` and `:resolve-key`.
- Produces: All four reference-bearing factories accept/expose `:identity-store`; isolated fallback is `(IdentityStore.IdentityStore {:base-dir same-root})`, not `get-default`.
- Produces: Existing default getters inject `(IdentityStore.get-default {:base-dir base-dir})`, preserve their names/signatures, and reject explicit root or identity-instance conflicts with an already cached default.
- Preserves: Store create/update/add/set/reorder signatures; dictionary slot names; link empty endpoints; typed workflow IDs; identity target pointers.
- Preserves: Link query signatures `find-edges-for-nodes(node-keys)` and `find-entities-for-key(key)`, now matching resolved endpoints and traversed identity dependencies.

- [ ] **Step 1: Add write-path RED cases with prefix `"reference lifecycle writes"`.** Before changing owning-store production paths, also run real selected-list/link creation, child creation and list/notebook add actions against same-root shared stores to demonstrate the normalization/visibility defect through user-facing integration, not only future APIs.

```fennel
(H.with-root
  (fn [root]
    (local s (H.stores root))
    (s.identity-store:create-entity {:id "s" :target-key "string-entity:s"})
    (local list (s.list-store:create-entity
                  {:id "l" :items ["string-entity:s" "identity:s" "fs:/external"]}))
    (assert (= (length list.items) 2))
    (assert (= (. list.items 1) "identity:s"))
    (s.list-store:add-item "l" "string-entity:s")
    (local stored-list (s.list-store:get-entity "l"))
    (assert (= (length stored-list.items) 2))
    (local draft (s.link-store:create-entity {:id "draft"}))
    (assert (= draft.source-key ""))
    (assert (= draft.target-key ""))
    (assert (= s.list-store.identity-store s.identity-store))))
```

- [ ] **Step 2: Normalize before uniqueness on every insertion/replacement path.** Cover list/notebook create, update, add, reorder and move; dictionary create, update and set; populated link endpoints on create/update. Preserve first normalized occurrence and order; preserve two deliberately distinct explicit aliases and two named dictionary slots.
- [ ] **Step 3: Separate decoding from normalization.** Reads remain side-effect-free and preserve legacy raw references until owner migration. Removal resolves an existing raw-to-direct-identity mapping without creating a new identity merely to remove a missing item.
- [ ] **Step 4: Move node-level insertion normalization into stores.** Remove duplicate node ensure implementations. Node identity ownership comes from its owning store; explicitly supplied mismatching instances error. Update multi-store fixtures to share DI, and replace raw-key expectations with both stable-key and terminal-meaning assertions.
- [ ] **Step 5: Keep current runtime paths working in this commit.** Make link queries identity-chain aware so existing Graph/GraphMap discovery still works. Board connector validation/reconciliation compares resolved meaning instead of raw endpoint strings. “Show link entities” uses the active graph’s owning link/identity stores and resolved keys rather than a separate default/raw comparison.
- [ ] **Step 6: Make affected mutation paths persist candidates before cache/signal publication.** Do not mutate cached arrays/tables before write succeeds. No normal relationship insertion may expose hidden identity nodes.
- [ ] **Step 7: Validate and review the whole affected authoring surface before checkpoint.**

```bash
check_stage 'reference lifecycle writes' entities/list.fnl entities/dict.fnl entities/link.fnl \
  notebooks/store.fnl graph/nodes/list-entity.fnl graph/nodes/dict-entity.fnl graph/nodes/notebook.fnl \
  board/view.fnl graph-activity-actions.fnl tests/fast.fnl tests/test-reference-lifecycle-helpers.fnl \
  tests/test-reference-lifecycle-writes.fnl tests/test-list-entities.fnl tests/test-dict-entities.fnl \
  tests/test-link-entities.fnl tests/test-notebooks.fnl tests/test-string-entity-create-child.fnl \
  tests/test-graph-map.fnl tests/test-board.fnl tests/test-board-activity-string-entities.fnl \
  tests/test-ordered-list-islands.fnl tests/test-graph-view-islands.fnl tests/test-link-entity-crash.fnl
for filter in entity notebook GraphMap Board OrderedList; do
  run_focused "$filter" || exit $?
done
```

Acceptance: the permanent suite expects normalized owning records, not historical diagnostic raw keys. Real selected-list/link, child creation, board linking, and list/notebook add paths retain meaning and visibility. Suggested checkpoint: `feat(lua): normalize references at owning store writes`.

### Task 3: Explicit Domain Owners, Strict IO, and Prepared Migration

**Files:**
- Modify: `src/lua_fs.cpp`
- Modify: `assets/lua/entities/string.fnl`, `assets/lua/entities/code.fnl`, `assets/lua/entities/list.fnl`, `assets/lua/entities/dict.fnl`, `assets/lua/entities/link.fnl`, `assets/lua/entities/identity.fnl`, `assets/lua/notebooks/store.fnl`, `assets/lua/workflows/store.fnl`
- Create: `assets/lua/reference-lifecycle/record-utils.fnl`, `assets/lua/reference-lifecycle/entities-owner.fnl`, `assets/lua/reference-lifecycle/identities-owner.fnl`, `assets/lua/reference-lifecycle/workflows-owner.fnl`, `assets/lua/reference-lifecycle/migration.fnl`
- Create: `assets/lua/tests/test-reference-lifecycle-owners.fnl`
- Modify: `assets/lua/tests/test-reference-lifecycle-helpers.fnl`, `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: Tasks 1–2 stores, ownership and normalization; shared Snapshot/Inventory/Site/Change/Preparation/RuntimeCapture contracts, including mandatory `RecordUtils.snapshot(path,format,decode)` with a pure owning-domain decoder and checks from original raw bytes. Each `Owner:prepare(inventory,operation)->Preparation` returns `{changes, runtime-state}`; these three domain owners return `runtime-state=[]`, never WorldOwner paths or transient adapter state.
- Produces: `EntitiesOwner(Stores)`, `IdentitiesOwner(Stores)`, `WorkflowsOwner(Stores)` implementing the fixed owner protocol.
- Produces store-internal entity primitives: `snapshot-entity(id)->Snapshot`, `serialize-entity(record:table)->string`, `decode-entity(bytes:string)->table`, `persist-entity!(id:string, after-bytes:string, after-check:string)->record`.
- Produces notebook primitives: `snapshot-notebook(id)->Snapshot`, `serialize-notebook(record:table)->string`, `decode-notebook(bytes:string)->table`, `persist-notebook!(id:string, after-bytes:string, after-check:string)->record`.
- Produces workflow primitives: `snapshot-definition(id)->Snapshot`, `serialize-definition(record:table)->string`, `decode-definition(bytes:string)->table`, `persist-definition!(id:string, after-bytes:string, after-check:string)->record`. All decoders are pure, use native persisted schemas/timestamp conversion, and never normalize references or generate timestamps. Prepared persistence verifies the decoded candidate's reserialized byte-check equals the frozen `after-check` before writing; cache identity/publication follows the shared contract. `after-bytes=false` is physical retirement, not an argument to these write primitives.
- Each store's `snapshot-entity`, `snapshot-notebook` or `snapshot-definition` delegates to `RecordUtils.snapshot(path,format,decode)` with its **own** pure `decode-entity`, `decode-notebook` or `decode-definition` function (bind the owning store if its decoder is a method). String decoding uses the existing record frontmatter ID and body schema, preserving exact source text; workflow decoding converts canonical persisted ISO timestamps into native numeric memory timestamps. No generic path dispatch, domain imports, decoder default or new registry is introduced.
- Produces: `WorkflowStore:prepare-step-removal(definition:table, step-ids:[string], opts:{delete-dependent-edges?:boolean})->table`, a pure transformation shared by existing step deletion and lifecycle preparation.
- Produces: `RecordUtils.snapshot(path:string,format:"json"|"string",decode:function(bytes:string)->owning-domain-record)->Snapshot`, `check-bytes(bytes:string|false,format:"json"|"string")->string|false`, `make-change(owner,address,snapshot,after-bytes:string|false,format,phase)->Change`, `clone(value)->value`. The decoder is required even for JSON, runs only for present records and never determines `snapshot.check`; absence returns false fields without a decoder call. Snapshot checks use original raw bytes through `check-bytes`. `make-change` consumes already owner-serialized bytes, not domain records or an unknown serializer; it computes `before-check` from `snapshot.bytes` and `after-check` from `after-bytes` using `check-bytes`. JSON checks parse and stable-encode serialized JSON; string/Markdown checks use exact bytes; false means only absence.
- Produces: `Migration.prepare(owners:[Owner], stores:Stores)->{operation:Operation, changes:[Change], runtime-state:[RuntimeCapture], dangling:[Site]}`, `Migration.version = 1`. Aggregate owner Preparations without duplicating normalized durable paths; namespace captures by owner/world/map IDs, never adapter references.
- Reservation handoff: `Migration.prepare` builds the shared `operation.reference-plan` before calling each unchanged `Owner.prepare(inventory, operation)`. New identity records are complete proposed creations, not already-persisted Inventory entries. Pure preparation and serialized replay use this same payload; dangling known-domain raw keys have no rewrite and remain unchanged, while generic external keys remain eligible.
- Produces: `fs.list-dir(path, include-hidden?, strict?: boolean)->entries`; existing two-argument behavior remains compatible, while `strict=true` does not skip permission-denied enumeration. Required owner inventories use the explicit third argument.
- Produces test helpers: `domain-owners(stores)->[Owner]`, `empty-owner(id,root)->Owner`, `apply-preparation!(owners,preparation)->nil`. Empty owners are test doubles only, not production feature flags.

- [ ] **Step 1: Add RED tests with prefix `"reference lifecycle owners"`.** Verify inventory is complete without loading graph nodes; migration preparation itself performs no writes.

```fennel
(H.with-root
  (fn [root]
    (local s (H.stores root))
    (local path (fs.join-path root "entities" "list" "legacy.json"))
    (JsonUtils.write-json! path {:id "legacy" :name "" :items ["string-entity:s"]
                                 :created-at 1 :updated-at 1})
    (s.string-store:create-entity {:id "s" :value "(+ 1 2)"})
    (local owners (H.domain-owners s))
    (local before (H.snapshot-tree root))
    (local Migration (require :reference-lifecycle/migration))
    (local migration (Migration.prepare owners s))
    (assert (= (JsonUtils.stable-json before)
               (JsonUtils.stable-json (H.snapshot-tree root))))
    (H.apply-preparation! owners migration)
    (local again (Migration.prepare owners s))
    (assert (= (length again.changes) 0))))
```

- [ ] **Step 2: Close the demonstrated binding IO gaps.** In `lua_fs.cpp`, add only the optional strict enumeration argument; do not change default directory browsing semantics. The existing permission-skipping enumeration can silently hide required owner records, so strict mode must surface that failure while preserving two-argument callers. Check read stream failures and write flush/close failures rather than accepting an opened-but-failed stream. No new filesystem framework or test-only production switch.
- [ ] **Step 3: Finish strict store persistence.** Required reads/parses/listings/writes/removals throw; absent individual IDs remain normal absence, empty new roots remain valid. Export the snapshot/serialize/decode/frozen-byte persistence primitives above. Owners serialize complete prepared domain candidates once, then `make-change` freezes those bytes. On apply, decode frozen bytes without new timestamp/reference wrapping, verify reserialization with `check-bytes` before writing, persist canonical serialized payload through the existing atomic JSON utility (or native string persistence), then publish the decoded candidate into the held cache record without changing its identity. Failed writes publish nothing; signal failures must propagate to retain pending progress once coordinated. JSON formatting whitespace may differ, never semantic after-checks.
- [ ] **Step 4: Make WorkflowStore’s affected definition operations copy-before-write.** Extract `prepare-step-removal` so existing `delete-step(...,{delete-dependent-edges? true})` and prepared lifecycle cleanup use identical step/incident-edge semantics. Keep numeric timestamps only in decoded memory; journal `serialize-definition`'s canonical ISO-string payload and compute `after-check` from those bytes, never from the numeric domain table. Add pure decode → serialize → check round-trip and restart tests, including multiple dependent steps/edges aggregated into one definition write, with matching canonical ISO timestamp after-checks. Never touch runs/events/history during live-reference cleanup.
- [ ] **Step 4a: Require the workflow Snapshot decoder regression.** In `test-reference-lifecycle-owners.fnl`, use a persisted workflow `definition` fixture whose native `created-at` is numeric and whose serializer emits its canonical ISO timestamp. Assert the snapshot exposes numeric `.value.created-at` while its unchanged original `.bytes` contains that canonical ISO string; the byte-derived check must equal the decoded record's canonical reserialization check and agree with replay after-checks after restart. Also assert an absent snapshot never calls its supplied decoder, and retain Step 7's exact string-body/frontmatter cold-round-trip test.

```fennel
(local canonical-bytes (s.workflow-store:serialize-definition definition))
(local persisted (json.loads canonical-bytes))
(local snapshot (s.workflow-store:snapshot-definition definition.id))
(assert (= (type snapshot.value.created-at) "number"))
(assert (= snapshot.value.created-at definition.created-at))
(assert (= snapshot.bytes (fs.read-file snapshot.path)))
(assert (= (type persisted.created-at) "string"))
(assert (string.find snapshot.bytes persisted.created-at 1 true))
(local RecordUtils (require :reference-lifecycle/record-utils))
(assert (= snapshot.check (RecordUtils.check-bytes snapshot.bytes "json")))
(local round-trip (s.workflow-store:serialize-definition snapshot.value))
(assert (= snapshot.check (RecordUtils.check-bytes round-trip "json")))
```

- [ ] **Step 5: Implement the three owners using explicit schemas.** Entity owner inventories string/code/list/dict/link/notebook records; list/notebook membership and dictionary slots are incoming sites; each populated link endpoint is a site. Identity owner inventories representation pointers without wrapping them. Workflow owner exposes step targets as `workflow-step:<definition-id>:<step-id>` and code sites as `code-entity:<code-entity-id>`; group all affected steps/edges into one prepared definition write.
- [ ] **Step 6: Prepare idempotent migration without calling write-producing ensure.** Inventory/validate first; deterministically reuse direct identities or reserve IDs in memory for recoverable raw keys; pass the sorted mapping and complete proposed identities through `operation.reference-plan`, then include identity creation and eligible owner rewrites in the same Preparation. Verify that preparing twice before application reserves independently without writes, while applying once and preparing again produces zero changes. Preserve IDs/order/slots/metadata and existing explicit aliases. Report dangling known-domain targets with owner/address/field; retain them unchanged. External schemes remain valid references. Cycles, malformed required records, and missing capabilities stop before writes.
- [ ] **Step 7: Exercise actual native IO failures.** Use real directory/file collisions, malformed JSON and unreadable files; on Linux use permission-denied directories with modes restored in protected cleanup. Assert strict listing fails instead of returning an empty root. Keep portable collision cases on every platform. Verify failed persistence leaves held cache objects/signals unchanged, and preserve string value text through a cold store round-trip and morph preparation, including whitespace/newlines.
- [ ] **Step 8: Rebuild, then validate and review.**

```bash
# Required after src/lua_fs.cpp changes; execution-tool timeout: 14400000.
make build
check_stage 'reference lifecycle owners' entities/string.fnl entities/code.fnl entities/list.fnl \
  entities/dict.fnl entities/link.fnl entities/identity.fnl notebooks/store.fnl workflows/store.fnl \
  reference-lifecycle/record-utils.fnl reference-lifecycle/entities-owner.fnl \
  reference-lifecycle/identities-owner.fnl reference-lifecycle/workflows-owner.fnl \
  reference-lifecycle/migration.fnl tests/test-reference-lifecycle-owners.fnl \
  tests/test-reference-lifecycle-helpers.fnl tests/fast.fnl
run_focused 'workflow-store' 9 tests.test-workflow-store:main
```

Acceptance: strict enumeration is verified through the binding; preparation is read-only; applying migration twice yields zero second-pass changes. Main still uses the old application paths. Suggested checkpoint: `feat(lua): prepare explicit reference owner changes`.

### Task 4: Durable Pending Intent and Lifecycle Coordinator

**Files:**
- Create: `assets/lua/reference-lifecycle/plan.fnl`, `assets/lua/reference-lifecycle/pending.fnl`, `assets/lua/reference-lifecycle/init.fnl`
- Create: `assets/lua/tests/test-reference-lifecycle-commands.fnl`, `assets/lua/tests/test-reference-lifecycle-recovery.fnl`
- Modify: `assets/lua/tests/test-reference-lifecycle-helpers.fnl`, `assets/lua/tests/fast.fnl`
- Modify: `assets/lua/entities/string.fnl`, `assets/lua/entities/code.fnl`, `assets/lua/entities/list.fnl`, `assets/lua/entities/dict.fnl`, `assets/lua/entities/link.fnl`, `assets/lua/entities/identity.fnl`, `assets/lua/notebooks/store.fnl`, `assets/lua/workflows/store.fnl`
- Modify: `assets/lua/reference-lifecycle/entities-owner.fnl`, `assets/lua/reference-lifecycle/identities-owner.fnl`, `assets/lua/reference-lifecycle/workflows-owner.fnl`

**Interfaces:**
- Consumes: Task 3 owners/migration and shared Stores/Preparation/RuntimeCapture/frozen-byte Change contracts: every `Owner:prepare(inventory,operation)->{changes:[Change],runtime-state:[RuntimeCapture]}`; changes contain `after-bytes:string|false` and byte-derived checks, never domain tables. WorldOwner alone owns durable world/metadata paths; RuntimeOwner has no durable changes and reconciles frozen captures only.
- Produces: `Plan.prepare(owners, stores, request)->Intent|DeleteResult`; requests are `{kind="delete",source-key}` or `{kind="morph",source-key,payload}`.
- Produces: `Pending(base-dir)` with `read()->Intent|nil`, `write!(intent)->true`, `clear!()->true`; paths are `<base-dir>/reference-lifecycle/pending.json` and `migration.json`.
- Produces: `Lifecycle({stores, owners})->service` with `start!()->MigrationReport`, `delete!(key)->DeleteResult`, `replace!(source-key,payload)->MorphResult`, `committed:Signal`, and `stores:Stores`. `MigrationReport` is `{version:number, dangling:[Site]}` using the completed migration version and reported dangling sites.
- Produces: `Lifecycle:owns-store?(scheme:string, store:table)->boolean`, comparing exact canonical store object, normalized root and (for list/dict/link/notebook reference holders) the identical canonical identity dependency. Unknown schemes or mismatches return false; node callers assert true before any action writes. This is a fixed canonical ownership check, not a general CRUD registry.
- Produces internal nonpersisting store methods: entity stores `reconcile-entity!`, notebooks `reconcile-notebook!`, workflows `reconcile-definition!`, each `(id:string, after-bytes:string|false, before-check:string|false, after-check:string|false)->record|nil`. Validate the actual owning file already matches `after-check`, pure-decode/verify the frozen image, then reuse owning cache publication and existing signals without any durable write, timestamp generation, reference normalization or ensure-key call. Definition retirement is rejected. `before-check=false` selects create notification, `after-bytes=false` selects delete, otherwise update; retain container item-change signals. Cold deletion reconstructs the payload from the held record or the owning decoder applied to the original canonical-JSON/exact-Markdown `before-check`. Workflow publication preserves held definition and surviving child identities.
- Domain `Owner:reconcile!(intent)` validates owner/address/path and processes only the coordinator-selected `intent.changes` already at their after-images, dispatching those internal store methods. The coordinator passes a bounded intent copy containing that subset, never an invented Inventory record. Changes whose `apply!` just completed normally are not reconciled again; this avoids duplicate ordinary notifications. Retries may deliver notifications at least once. World verification and RuntimeOwner frozen-capture reconciliation remain their separate phases and are not owning-store publication substitutes.
- `DeleteResult = {status:"deleted"|"absent", source-key, source-record:table|false, retired-keys:[string]}`.
- `payload = {name:string, language:"fnl", source:string, kernel:number|string}`; only string→code is accepted.
- `MorphResult` preserves `code-entity`, `code-key`, `target-key`, `target-type`, `updated-identity-keys`, `source-key`, `source-id`.
- Intent JSON version 1 contains `operation-id`, `request`, `operation`, `source-fingerprint`, `changes:[Change]`, `runtime-state:[RuntimeCapture]` and `phase`. Replacement includes the one reserved ID and complete payload. `Plan.prepare` copies every owner's Preparation into the intent **before any write**, tags/validates capture namespaces by `(owner,world-id,map-id)`, rejects duplicate namespaces or normalized persistence paths, and freezes owner-serialized `after-bytes` with byte-derived before/after-checks. No functions, adapter tables or mixed workflow timestamp domains are serialized.
- `source-fingerprint` is `{path:string, format:string, before-check:string, record:table}` for an existing requested target and false for root migration. Freeze the logical source record for retry return values; a workflow-step target freezes the matched step while its byte fingerprint covers the containing definition. Owner/address/path checks still govern effects; journal paths are never trusted as independent write capabilities.
- Produces test helper: `lifecycle(stores, world-owner?, runtime-owner?)->service`; it supplies real domain owners and explicit empty world/runtime doubles only in isolated tests.

- [ ] **Step 1: Add command RED tests with prefix `"reference lifecycle commands"`.** Assert an unstarted service rejects commands and all five owner IDs/capabilities/root relationships are validated before readiness. Include ownership-check cases for exact same-root canonical objects versus same-root substitutes, mismatched identity dependencies and different roots; assert rejection precedes writes. Assert duplicate durable paths/capture namespaces fail preparation, the journal contains complete frozen runtime-state before application, and empty owners still return both Preparation arrays.

```fennel
(H.with-root
  (fn [root]
    (local s (H.stores root))
    (s.string-store:create-entity {:id "s" :value "source"})
    (s.list-store:create-entity {:id "l" :items ["string-entity:s"]})
    (local service (H.lifecycle s))
    (H.assert-error "not ready" #(service:delete! "string-entity:s"))
    (service:start!)
    (local result (service:delete! "string-entity:s"))
    (assert (= result.status "deleted"))
    (local list (s.list-store:get-entity "l"))
    (assert (= (length list.items) 0))
    (local repeated (service:delete! "string-entity:s"))
    (assert (= repeated.status "absent"))))
```

- [ ] **Step 2: Implement deterministic closure before destructive writes.** Build inventories once, resolve identity chains, and process a sorted visited worklist. Incoming aliases, invalidated links, links referencing invalidated links, and workflow steps using retiring code extend deletion closure. Container members, dictionary values, notebook children and surviving link endpoints do not become retiring targets.
- [ ] **Step 3: Distinguish explicit identity deletion from represented-object deletion.** `delete!("identity:x")` retires that record and its dependent aliases/sites, not its independently owned terminal target. Callers acting on an ordinary reference resolve it before invoking `delete!`. Unsupported mutating schemes, malformed workflow-step keys and cross-root/capability errors fail before any operation writes.
- [ ] **Step 4: Freeze morph preparation.** Verify supported source/payload against the current source record; reserve one code ID and timestamps; serialize creation, direct-identity retargets, supported raw-reference migration, presentation participation and source retirement before application. Deep-copy the complete `operation.reference-plan` into the intent before pending persistence; a newly reserved identity for the morph source must target the reserved replacement key, not the retiring source. Existing direct aliases are retargeted without changing their IDs, and upstream aliases retain their direct targets. Copy all owner Preparations into intent changes/runtime-state before pending persistence, rejecting duplicate normalized paths and namespaced captures; the source of captures is owner preparation, never replay-time recapture. Never regenerate IDs, timestamps, payloads or captures while replaying.
- [ ] **Step 5: Implement pending replay using byte-derived before/after checks, not rollback.** Persist intent atomically after complete preflight. For each change, `RecordUtils.check-bytes(current-bytes,format)==after-check` means already persisted: reconcile only that selected subset through its owning nonpersisting methods. Equality to `before-check` permits `apply!`; any other value is an explicit conflict. Apply frozen owner-serialized `after-bytes` through owner decoding/verification/persistence, never rebuild from domain tables; false retires via its owner. Do not re-reconcile changes whose `apply!` just returned successfully. Apply replacement, all incoming cleanup including dependent-object retirement, runtime reconciliation, and the requested source change last, regardless of lexical ordering. A requested workflow-step deletion's aggregated definition write is its final source change even though the definition file survives. Recheck incoming after-state before the source change and verify all durable after-states/reconciliation before clearing intent and reporting success. Reconcile caches without rewriting files when persistence already matches after-state, including recovery after a signal error; leave pending intent on notification failure.
- [ ] **Step 6: Enforce serialized operation and restart semantics.** The same request resumes its pending intent; a different request is blocked with operation/source diagnostics. `start!` recovers pending work before migration, writes migration completion only after verification, and becomes ready only on success. RuntimeOwner installs only supplied captures for still-loaded matching IDs, nonpersistingly and without activation/recapture; no loaded maps at startup is a safe transient skip, since WorldOwner's durable after-images govern later activation. Retain pending on reconciliation/signal failure; do not recreate sources, silently roll back, or swallow retirement/signal/reconciliation errors.
- [ ] **Step 7: Add recovery RED/GREEN tests at actual filesystem boundaries.** Prefix `"reference lifecycle recovery"`. Fail pending write, identity/container write, replacement write, retirement, reconciliation and pending removal; assert the requested source survives every incoming-cleanup failure. Retry with the same service and freshly reconstructed stores, checking one replacement ID/source and explicit conflicts after external edits. Include actual path-collision failures, not only injected exceptions. Verify workflow ISO-byte after-check round-trip and restart after a multi-step aggregate definition update; verify durable world after-images plus a failed transient reconciliation resume without recapture or duplicate metadata writes, including restart with no maps loaded.
- [ ] **Step 7a: Prove after-image publication does not persist.** For all eight stores, retain a real already-persisted after-image and guard native write/rename operations to fail if called. Reconcile into held and cold caches; assert zero writes, existing record/workflow-child identity preservation, exact create/update/delete payloads and item-change signals, and unchanged files. Inject a notification error and verify pending retry, while an ordinary newly applied change emits once without redundant reconciliation. Capture this missing owning-publication capability as RED before adding the internal methods; the coordinator must not duplicate store-specific publication logic.

```fennel
(H.with-fs-failure
  "remove" (fs.join-path root "entities" "string" "s.md")
  (fn []
    (H.assert-error "s.md" #(service:delete! "string-entity:s"))))
(assert (fs.exists (fs.join-path root "reference-lifecycle" "pending.json")))
(local restarted (H.lifecycle (H.stores root)))
(restarted:start!)
(local restarted-string-store restarted.stores.string-store)
(assert (= (restarted-string-store:get-entity "s") nil))
```

- [ ] **Step 8: Validate, review and checkpoint; do not wire Main yet.**

```bash
check_stage 'reference lifecycle commands' reference-lifecycle/plan.fnl reference-lifecycle/pending.fnl \
  reference-lifecycle/init.fnl tests/test-reference-lifecycle-commands.fnl \
  tests/test-reference-lifecycle-recovery.fnl tests/test-reference-lifecycle-helpers.fnl tests/fast.fnl \
  entities/string.fnl entities/code.fnl entities/list.fnl entities/dict.fnl entities/link.fnl \
  entities/identity.fnl notebooks/store.fnl workflows/store.fnl \
  reference-lifecycle/entities-owner.fnl reference-lifecycle/identities-owner.fnl \
  reference-lifecycle/workflows-owner.fnl
run_focused 'reference lifecycle recovery'
```

Acceptance: both directions of links, alias chains, K1/K2 relationship cycles, code-step cascades and non-cascading container deletion pass in isolated tests; real IO/restart evidence supports recovery claims. Suggested checkpoint: `feat(lua): coordinate resumable reference lifecycle commands`.

### Task 5: Board and Persisted-World Owners, Including Inactive Map Metadata

**Files:**
- Create: `assets/lua/reference-lifecycle/world-owner.fnl`, `assets/lua/graph/reference-state.fnl`, `assets/lua/board/reference-state.fnl`, `assets/lua/board/builtin-code-entity.fnl`
- Modify: `assets/lua/world-manager.fnl`, `assets/lua/home-world.fnl`, `assets/lua/board/core.fnl`, `assets/lua/board/view.fnl`, `assets/lua/board/builtin-string-entity.fnl`, `assets/lua/board-activity-unit.fnl`
- Modify: `assets/lua/graph/map-manager.fnl`, `assets/lua/graph/map.fnl`, `assets/lua/graph/view/persistence.fnl`, `assets/lua/graph/view/runtime.fnl`, `assets/lua/graph/view/init.fnl`
- Create: `assets/lua/tests/test-reference-lifecycle-worlds.fnl`
- Modify: `assets/lua/tests/test-reference-lifecycle-helpers.fnl`, `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: Task 4 lifecycle/intent protocol, shared Preparation/RuntimeCapture/frozen-byte Change contracts, Task 3 `RecordUtils.snapshot(path,format,decode)->Snapshot` with a required pure decoder, and existing native Board, HomeWorld, GraphMapManager and graph-view ownership. `Owner:prepare(inventory,operation)->{changes:[Change],runtime-state:[RuntimeCapture]}` applies unchanged.
- Produces: `WorldOwner({stores, world-manager})->Owner` with ID `"worlds"`; `prepare` returns `{changes:durable-world-and-metadata-changes,runtime-state:[]}`. It exclusively owns production/application of all affected `world.json` and `graph/maps/<id>/metadata.json` Changes. Changes carry canonical JSON `after-bytes` and `RecordUtils.check-bytes` checks, never domain-table after-images; no RuntimeOwner path overlap is allowed.
- WorldOwner explicitly calls `(RecordUtils.snapshot world-path "json" json.loads)` and `(RecordUtils.snapshot metadata-path "json" json.loads)` for the respective persisted JSON records. This dispatch belongs to WorldOwner, not a hidden converter in RecordUtils; absent paths do not invoke `json.loads`, and checks still use original persisted bytes independently of decoded values.
- Produces: `WorldManager:list-reference-worlds()->[{id,dir,world:HomeWorld|nil}]`, enumerating persisted world directories plus loaded entries without activating worlds.
- Produces: `HomeWorld:snapshot-reference-state()->table` and `:install-reference-state!(state)->true`; both are nonpersisting and include native board/map/view/session mirrors. WorldOwner consumes the snapshot for durable preparation; RuntimeOwner uses installation for frozen transient reconciliation only.
- Produces: `GraphMapManager:snapshot-reference-state()->graph-state`, `:install-reference-state!(graph-state)->true`; both are nonpersisting, do not activate worlds/maps, and do not hydrate inactive maps during snapshot.
- Produces early for Task 6 reuse: `GraphMap:install-reference-state!(state)->true`, a lifecycle-specific nonpersisting delta that preserves surviving native adapters/explicit edge rows and avoids ordinary full-restore pruning against an installed metadata after-image. Task 5 active-view regressions established this prerequisite for coherent WorldOwner publication; it cannot safely wait until the next stage.
- Produces pure functions: `GraphReferenceState.rewrite-map(state,operation)->state`, `rewrite-metadata(metadata,operation)->metadata`, `rewrite-view(state,operation)->state`; `BoardReferenceState.rewrite(state,operation,identity-store)->state`.
- Produces: GraphView `snapshot-reference-state()->view-state`; persistence `snapshot-state()->metadata`, `install-state!(metadata)->true`; all are nonpersisting snapshot/cache operations. A future ordinary save must see installed after-state, but lifecycle reconciliation itself must not save.
- Produces: Board `update-item-subject(item-id,subject-key,item-type)->item`; `BuiltinCodeEntity.register(owner)`, `unregister(owner)`, `item-type="code-entity"`.

- [ ] **Step 1: Establish native RED evidence before implementing adapters.** Add tests prefixed `"reference lifecycle worlds"` using real Board, native graph loaders/GraphMapManager and HomeWorld persistence. First run the existing string→code path with same-root injected stores: board subjects remain retired strings and inactive maps fail to retain replacement participation. RED must demonstrate those losses, not merely a missing WorldOwner import.
- [ ] **Step 2: Preserve those assertions when moving their trigger to the coordinator.** Include a native inactive map fixture with source node, explicit edge, selection/focus, outline root and island; separately write map metadata containing position/size/presentation/panels and reopen after morph. Example required native assertion:

```fennel
(local captured (manager:snapshot-reference-state))
(local inactive (. captured.maps 2))
(assert (= (. inactive.nodes 1) result.code-key))
(assert (= inactive.focused_node_key result.code-key))
(assert (= (. inactive.selected_node_keys 1) result.code-key))
(assert (= (. inactive.outline_root_keys 1) result.code-key))
(assert (= (. inactive.islands 1 :members 1) result.code-key))
(local metadata (json.loads (fs.read-file metadata-path)))
(assert (. metadata.positions result.code-key))
(assert (= (. metadata.positions source-key) nil))
```

- [ ] **Step 3: Implement explicit presentation schema transforms.** Rewrite/remove map `nodes`, edge `source/target`, selected/focused keys, outline roots, island `members` and ordered-list `state.list-key`. Rewrite keyed metadata `positions`, `sizes`, `presentations`, `panels[].node-key`, `extra_panels[].node-key`; retain unrelated metadata, cameras, map IDs and edge attributes. Remove empty islands only where their native invariant requires it.
- [ ] **Step 4: Include retained graph-view schemas, not only topology.** Handle `views.open-views` including its documented panel node key, `extra_panels`, selected/focused state and `mode_states.spatial` panel/focus fields; preserve mode cameras. Transform `activity.sessions.graph.graph-view-states` and `graph-view-state`, plus native retained equivalents. No recursive search-and-replace of arbitrary strings.
- [ ] **Step 5: Split pure snapshot from persistence where required.** Today GraphView capture writes metadata and map-manager capture hydrates/prunes inactive maps. Extract nonpersisting snapshots for lifecycle preflight while keeping ordinary capture/save behavior. World inventories include every known persisted `world.json` and corresponding `graph/maps/<id>/metadata.json`, not just active tabs; malformed required records and enumeration failures stop preflight. Merge loaded nonpersisting model/view/session/metadata snapshots into the same WorldOwner prepared durable record, retain unrelated native fields, then transform and serialize once. Aggregate each durable path into one `after-bytes` Change; RuntimeOwner must not produce a second version of that path. Verify owner-serialized JSON after-checks using `RecordUtils.check-bytes` before atomic JSON writes.
- [ ] **Step 6: Implement nondestructive board cleanup and code rendering.** Normalize recoverable board subjects through migration, retain semantic-link ID format, remove connectors for retiring link IDs, and remove only items whose subjects retire. Morph preserves item ID/order/transform/state and all surviving connectors. Code items use existing `(Text {:text entity.source})` with proper child layout/drop ownership; strings retain the existing editable Input widget. Do not add an editor or toggle Input readonly.
- [ ] **Step 7: Prepare coherent durable and retained world state.** Include `state.board`, `activity.sessions.board.board-state`, loaded `runtime.board-state`, native board model and `runtime.activity-session-state`; include graph-view snapshots and pending canvas/HUD graph-owned panels. WorldOwner alone freezes/persists the merged native world/metadata after-images. Provide the nonpersisting snapshot/install adapters for Task 6's RuntimeOwner to capture transient `ReferenceState` before/after pairs with stable world/map IDs and later install **supplied intent captures**, not recapture. WorldOwner's `reconcile!` verifies its durable after-images; live/cache/view installation belongs only to RuntimeOwner. Later activity capture, deactivation, suspend/drop and reopen must not restore old references. Cleanup never calls destructive `BoardView:remove-item`.
- [ ] **Step 8: Keep activation staged.** Add identity-aware subject rendering and resolved board comparisons, but defer global board authoring normalization and destructive-action cutover to Task 7. Remove silent stale-string pruning from the future lifecycle path: historical dangling subjects are reported, not quietly deleted.
- [ ] **Step 9: Validate native loaded/unopened cases, IO conflicts and cold reopen; review.**

```bash
check_stage 'reference lifecycle worlds' reference-lifecycle/world-owner.fnl graph/reference-state.fnl \
  board/reference-state.fnl board/builtin-code-entity.fnl world-manager.fnl home-world.fnl \
  board/core.fnl board/view.fnl board/builtin-string-entity.fnl board-activity-unit.fnl \
  graph/map-manager.fnl graph/map.fnl graph/view/persistence.fnl graph/view/runtime.fnl graph/view/init.fnl \
  tests/test-reference-lifecycle-worlds.fnl tests/test-reference-lifecycle-helpers.fnl tests/fast.fnl
for filter in Board HomeWorld GraphMapManager; do
  run_focused "$filter" || exit $?
done
```

Acceptance: first RED and final GREEN evidence covers durable native board retention/reopen, inactive world/map replacement, every named metadata field, merged loaded snapshot preparation without writes, unrelated-world preservation and failed-world-write recovery. Verify exactly one WorldOwner Change per world/metadata path; transient live installation is completed by Task 6, not a second durable writer here. Suggested checkpoint: `feat(lua): preserve reference lifecycle across persisted worlds`.

### Task 6: Loaded Map Participation and Identity-Aware Projection Reconciliation

**Files:**
- Create: `assets/lua/reference-lifecycle/runtime-owner.fnl`
- Modify: `assets/lua/graph/core.fnl`, `assets/lua/graph/map.fnl`, `assets/lua/graph/map-manager.fnl`
- Modify: `assets/lua/graph/nodes/list-entity.fnl`, `assets/lua/graph/nodes/dict-entity.fnl`, `assets/lua/graph/nodes/notebook.fnl`
- Modify: `assets/lua/graph/view/runtime.fnl`, `assets/lua/graph/view/init.fnl`, `assets/lua/graph/view/persistence.fnl`
- Create: `assets/lua/tests/test-reference-lifecycle-projections.fnl`
- Modify: `assets/lua/tests/test-reference-lifecycle-helpers.fnl`, `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: Task 5 nonpersisting snapshots/installers/rewriters, Task 4 frozen intent, Task 1 terminal/chain resolution, and shared Preparation/RuntimeCapture/frozen-byte Change contracts. WorldOwner is the **only** durable world/metadata writer.
- Produces: `RuntimeOwner({stores,world-manager})->Owner` with ID `"runtime"`; it inventories native loaded runtimes without creating worlds/maps. `prepare(inventory,operation)->{changes:[],runtime-state:[RuntimeCapture]}` captures JSON-safe native `board/maps/views/metadata` before/after records keyed by stable world/map IDs and owner namespace. It emits **no** durable Changes and cannot apply a world/metadata write.
- Produces: `RuntimeOwner:reconcile!(intent)->nil`, consuming only the frozen `intent.runtime-state` captures for its owner namespace; it never recaptures or saves, and installs only into still-loaded matching IDs. Missing runtime IDs are skipped without activation; a startup with no maps loaded relies on durable WorldOwner after-images when those maps are later activated. A genuine installation/reconciliation error propagates and leaves the durable pending intent.
- Produces: Graph/GraphMap `reconcile-link-projections!()->true`; consumes and strengthens Task 5's existing GraphMap `install-reference-state!(state)->true` for prepared participation while preserving native adapter ownership. Do not reintroduce full restore or a second competing installation path. Metadata/presentation cache installation uses Task 5's nonpersisting methods.
- Preserves: Existing node/front-end APIs, explicit map removal, link IDs, unrelated authored edges and the existing default durable-cleanup callbacks until Task 7's same-commit routing cutover.

- [ ] **Step 1: Add native RED tests with prefix `"reference lifecycle projections"`.** Capture a participating map, a second participating inactive map, and an unrelated map before retiring the string. Use incoming and outgoing links, two direct aliases, an upstream alias, duplicate endpoint pairs with different link IDs, and an unrelated explicit edge.

```fennel
(local before-bytes (H.snapshot-tree root))
(local result (service:replace! source-key
                {:name "" :language "fnl" :source "(+ 1 2)" :kernel 0}))
(assert (participating:lookup result.code-key))
(assert (not (unrelated:lookup result.code-key)))
(local ids {})
(each [_ edge (ipairs participating.edges)]
  (when (and edge._opts edge._opts.from-link-entity)
    (set (. ids edge._opts.from-link-entity) true)))
(assert (. ids "incoming"))
(assert (. ids "outgoing"))
(assert (. ids "upstream"))
```

Here `participating`/`unrelated` are real GraphMaps in the test fixture; author the three named links through the shared LinkEntityStore and keep their exact IDs.

- [ ] **Step 2: Capture membership before old-record signals erase it.** Return JSON-safe transient native before/after state in RuntimeOwner's Preparation, keyed by persisted world/map IDs and owner namespace; Plan copies it into intent before the first write. WorldOwner separately merges the same loaded nonpersisting snapshot roles into its exclusively owned durable after-images. After durable incoming changes and replacement creation, reconcile the supplied intent captures only, installing replacement in previously participating **still-loaded** matching maps; source physical retirement occurs afterward. Never recapture on apply/retry, save metadata/world state, activate missing runtimes or serialize adapter tables. Retry installation must be idempotent; missing loaded maps at startup safely defer to persisted after-images.
- [ ] **Step 3: Reconcile links by resolved terminal keys and exact link IDs.** Scan the fixed link store when identity changes can affect upstream aliases; do not rely on exact endpoint-string lookup. Rebuild derived edges only where both endpoints already participate. Never load unrelated endpoints to repair a projection. Remove a retired link’s derived edges by ID, not all equal-endpoint edges.
- [ ] **Step 4: Add projection-only reconciliation without removing legacy cleanup yet.** Add refresh paths for list/notebook/dictionary projections from committed owning records and alias-chain refresh after committed identity changes/replacement installation. Keep current default graph-node-removed/identity-deleted durable-cleanup callbacks through this stage; their removal is Task 7's atomic user-intent cutover. Explicit user remove-item/set-item actions remain owning mutations. Test real explicit identity deletion on the existing frontend path now and assert legacy cleanup is not newly lost; Task 7 repeats it through central semantics. Isolated new-service tests use explicitly composed canonical stores/owners and the new reconciliation paths, not test-only flags or production monkeypatches. Coordinator incoming cleanup precedes callback observation/identity retirement; normalized wrapped references must not be pruned merely because a morph retires a raw representation. Do not create a staging commit with newly dangling identity deletion or double durable edits.
- [ ] **Step 5: Preserve map-local state and persistence caches.** Install the supplied capture's prepared metadata into still-loaded persistence objects and apply its transformed view state after replacement adapters exist, without persistence or fresh capture. Synchronize selector/focus and retained mode/session mirrors so a subsequent ordinary capture cannot write stale keys. Disconnect added handlers through existing drop lifecycle. Cover pending retention on reconciliation error, replay of the identical capture without recapture, and restart with no loaded maps followed by normal activation from durable after-images.
- [ ] **Step 6: Add byte-comparison map-only tests.** The new explicitly owned projection-only paths must leave all owning entity/notebook/workflow files byte-identical on removal/clear, and mounted/unopened containers must yield identical coordinated deletion results. Keep the final ordinary default-path map-only regression staged for Task 7 when legacy cleanup callbacks are actually removed; do not falsely claim that final default-path invariant here or disable callbacks early just to make it green. Record connectivity separately from native list-edge tags/dictionary slot provenance.
- [ ] **Step 7: Keep provenance scope narrow.** If a derived-edge capture defect is necessary for these regressions, fix only derived/explicit classification and add an explicit-edge preservation regression. Do not redesign edge identity. Record previously observed lost list tags and equal-endpoint dictionary coalescing as parked findings; do not weaken new lifecycle assertions or force old ignored evaluators green.
- [ ] **Step 8: Validate and review.**

```bash
check_stage 'reference lifecycle projections' reference-lifecycle/runtime-owner.fnl graph/core.fnl \
  graph/map.fnl graph/map-manager.fnl graph/nodes/list-entity.fnl graph/nodes/dict-entity.fnl \
  graph/nodes/notebook.fnl graph/view/runtime.fnl graph/view/init.fnl graph/view/persistence.fnl \
  tests/test-reference-lifecycle-projections.fnl tests/test-reference-lifecycle-helpers.fnl tests/fast.fnl
for filter in GraphMap OrderedList island; do
  run_focused "$filter" || exit $?
done
```

Acceptance: frozen captured participation survives retirement/retry, exact derived link IDs reconcile through alias chains, no unrelated/unloaded map is populated or activated, and the new reconciliation paths perform no durable writes. WorldOwner alone owns world/metadata changes. Existing default callbacks and explicit identity-delete behavior remain intact until Task 7; removal/default map-only acceptance is gated there. Suggested checkpoint: `feat(lua): reconcile lifecycle presentation without domain side effects`.

### Task 7: Atomic Application Cutover, Physical API Rename and Morph Wiring

**Files:**
- Modify: `assets/lua/graph/core.fnl`, `assets/lua/graph/map.fnl` (canonical lifecycle constructor/field propagation), `assets/lua/graph/nodes/list-entity.fnl`, `assets/lua/graph/nodes/dict-entity.fnl`, `assets/lua/graph/nodes/notebook.fnl` (legacy cleanup callback cutover).
- Modify: `assets/lua/main.fnl`, `assets/lua/home-world.fnl`, `assets/lua/graph/extensions/builtins/composition.fnl`, `assets/lua/graph/extensions/builtins/entities.fnl`, `assets/lua/graph/extensions/builtins/workflows.fnl`
- Modify: `assets/lua/entities/string.fnl`, `assets/lua/entities/code.fnl`, `assets/lua/entities/list.fnl`, `assets/lua/entities/dict.fnl`, `assets/lua/entities/link.fnl`, `assets/lua/entities/identity.fnl`, `assets/lua/notebooks/store.fnl`
- Modify: `assets/lua/graph/nodes/string-entity.fnl`, `assets/lua/graph/nodes/code-entity.fnl`, `assets/lua/graph/nodes/list-entity.fnl`, `assets/lua/graph/nodes/dict-entity.fnl`, `assets/lua/graph/nodes/link-entity.fnl`, `assets/lua/graph/nodes/identity.fnl`, `assets/lua/graph/nodes/notebook.fnl`, `assets/lua/graph/nodes/workflow-step.fnl`
- Modify: `assets/lua/board/view.fnl`, `assets/lua/board/builtin-string-entity.fnl`, `assets/lua/board-activity-unit.fnl`, `assets/lua/workflows/templates.fnl`, `assets/lua/graph/nodes/workflow-definition.fnl`, `assets/lua/graph/nodes/workflows.fnl`, `assets/lua/morphs/string-entity-to-code-entity.fnl`
- Modify: `assets/lua/reference-lifecycle/entities-owner.fnl`, `assets/lua/reference-lifecycle/identities-owner.fnl`
- Create: `assets/lua/tests/test-reference-lifecycle-composition.fnl`, `assets/lua/tests/test-reference-lifecycle-browsers.fnl`
- Test/modify: `assets/lua/tests/test-entities-browser.fnl`, `assets/lua/tests/test-code-entity-list.fnl`, `assets/lua/tests/test-identity-entities.fnl`, `assets/lua/tests/test-graph-map.fnl`, `assets/lua/tests/test-list-entities.fnl`, `assets/lua/tests/test-dict-entities.fnl`, `assets/lua/tests/test-notebooks.fnl` (browser-created children, explicit identity deletion and final ordinary map-only byte checks).
- Read-only browser factory inventory; production exports remain unchanged: `assets/lua/graph/nodes/string-entity-list.fnl`, `assets/lua/graph/nodes/list-entity-list.fnl`, `assets/lua/graph/nodes/dict-entity-list.fnl`, `assets/lua/graph/nodes/link-entity-list.fnl`, `assets/lua/graph/nodes/notebooks.fnl`, `assets/lua/graph/nodes/code-entity-list.fnl`.
- Modify: `assets/lua/tests/fast.fnl`, `assets/lua/tests/test-reference-lifecycle-helpers.fnl`, `assets/lua/tests/test-morphs.fnl`, `assets/lua/tests/test-workflow-graph.fnl`, `assets/lua/tests/test-builtin-graph-extensions.fnl`, `assets/lua/tests/test-graph-extension-runtime-plumbing.fnl`
- Test/modify physical-call inventory: `assets/lua/tests/test-string-entities.fnl`, `assets/lua/tests/test-code-entities.fnl`, `assets/lua/tests/test-list-entities.fnl`, `assets/lua/tests/test-dict-entities.fnl`, `assets/lua/tests/test-link-entities.fnl`, `assets/lua/tests/test-identity-entities.fnl`, `assets/lua/tests/test-notebooks.fnl`, `assets/lua/tests/test-board.fnl`, `assets/lua/tests/test-board-activity-string-entities.fnl`, `assets/lua/tests/test-graph-map.fnl`, `assets/lua/tests/test-code-entity-list.fnl`

**Interfaces:**
- Consumes: All five real owners and Lifecycle from Tasks 3–6, including `Lifecycle:owns-store?(scheme,store)->boolean`, shared Preparation/RuntimeCapture/frozen-byte Change contracts and the retained default cleanup callbacks from Task 6. This is one reviewed application/API cutover, not a multi-file atomic persistence promise.
- Produces: Main’s `app.reference-lifecycle`, canonical owning store fields and `(= app.code-store (CodeEntityStore.get-default {:base-dir app.user-data-dir}))`, with explicit root assertion.
- Produces: Entity physical primitive `retire-entity!(id)->record|nil`; notebook physical primitive `retire-notebook!(id)->record|nil`. Remove store `delete-entity`/`delete-notebook` exports with **no aliases**.
- Preserves: Ordinary node `delete-entity()`/`delete-notebook()` names, board removal frontend names and workflow `delete-step-from-graph(opts)`; adapt their return values from `DeleteResult.source-record` where previously returning the deleted record.
- Produces: Explicit `:lifecycle` dependency through built-in extension options, standard node loaders, graph runtimes and BoardView. `Graph(opts)` exposes `reference-lifecycle=opts.lifecycle`; `GraphMap(opts)` exposes its shared Graph's `reference-lifecycle`, accepts the same explicit `opts.lifecycle`, and asserts if both instances differ. A standalone map's explicit lifecycle must own its configured stores. Wire those fields in `graph/core.fnl` and `graph/map.fnl`, not browser export changes.
- Produces: Destructive entity/notebook node factories retain optional `:lifecycle` as `node.lifecycle` and provide `node:resolve-reference-lifecycle!()->service`. The resolver chooses explicit node lifecycle or `node.graph.reference-lifecycle`, asserts both are identical when present, errors if neither exists, and asserts `(service:owns-store? scheme node.store)` including normalized root and reference-holder identity dependency **before writes**. Workflow-step delegates validate the owning WorkflowStore through the same fixed ownership check. Detached nodes require explicit service injection. No `app`, global service, default-store or equal-root-instance fallback is permitted.
- Preserves: Browser `get-node`/add-child exports. Direct browser factories may construct children without `:lifecycle`; when the existing graph add-node/add-edge path mounts a child into the real Graph/GraphMap, that child resolves the graph field at action time. Standard loaders still explicitly inject `:lifecycle`; all conflicts are errors rather than preference/fallback rules.
- Produces: String→code morph adapter delegates to `Lifecycle:replace!`, consuming its canonical string store and preserving every existing MorphResult field.

- [ ] **Step 1: Add composition/action RED tests with prefix `"reference lifecycle composition"`.** Assert exact store object identity, not only equal root paths. Cover Main code-cache coherence, custom same-root stores, mismatching roots/instances, all frontend delete delegates, migration/recovery ordering and blocked startup on conflict. Declare the named roster/count before running the new prefix; include the browser module's tests below. Repeat Task 6's real explicit identity deletion through the central path and verify dependent sites disappear without deleting the represented object; final ordinary map-only removal/clear must leave domain files byte-identical after listener cutover.

```fennel
(local CodeEntityStore (require :entities/code))
(local canonical-code-store (CodeEntityStore.get-default {:base-dir app.user-data-dir}))
(assert (= app.code-store canonical-code-store))
(assert (= app.list-store.identity-store app.identity-store))
(assert (= app.link-store.identity-store app.identity-store))
(assert (= app.notebook-store.identity-store app.identity-store))
(local node (graph-map:load-by-key "code-entity:c"))
(node:delete-entity)
(assert (= (app.code-store:get-entity "c") nil))
(assert (= (canonical-code-store:get-entity "c") nil))
```

- [ ] **Step 1a: Exercise actual browser-created children, not only standard key loaders.** Register `test-reference-lifecycle-browsers.fnl` in `tests/fast.fnl` with prefix `"reference lifecycle composition browser"`. In both canonical and custom same-root shared-store graphs, open each real browser below, invoke its native child construction/add action (including view `get-node` callbacks where used), let the native GraphMap mount the child, and invoke the child's ordinary delete frontend. Assert `resolve-reference-lifecycle!` selects the mounted graph service even when the child has no explicit lifecycle, and durable incoming cleanup uses the exact canonical stores. Test code-browser canonical cache coherence too. Explicit node-versus-graph service conflict, GraphMap-versus-shared-Graph conflict, same-root different store/identity dependency, different root and detached-without-service must error before byte changes. A detached node with an explicitly matching service remains supported.

| Real browser key | Production factory kept unchanged | Required permanent test case name |
| --- | --- | --- |
| `string-entity-list` | `graph/nodes/string-entity-list.fnl` | `reference lifecycle composition browser string child delete` |
| `list-entity-list` | `graph/nodes/list-entity-list.fnl` | `reference lifecycle composition browser list child delete` |
| `dict-entity-list` | `graph/nodes/dict-entity-list.fnl` | `reference lifecycle composition browser dict child delete` |
| `link-entity-list` | `graph/nodes/link-entity-list.fnl` | `reference lifecycle composition browser link child delete` |
| `notebooks` | `graph/nodes/notebooks.fnl` | `reference lifecycle composition browser notebook child delete` |
| `code-entity-list` | `graph/nodes/code-entity-list.fnl` | `reference lifecycle composition browser code child delete` |

Each named browser test exercises both canonical and explicitly composed custom-store mounts; include separately named conflict/detached cases in the reviewed roster. These six are required cases, not a fabricated total suite count.

- [ ] **Step 2: Freeze and reconcile the caller inventory before renaming.** User-facing delegates are six entity nodes, notebook node and `BoardView:remove-item`—eight sites—plus workflow-step deletion. Trusted physical sites are string-child rollback’s two calls, workflow templates’ two calls, board-create rollback, board-link rollback, workflow-definition rollback, workflows rollback and morph source retirement—nine sites before the morph delegates its retirement to lifecycle.
- [ ] **Step 3: Audit the human “28 test calls / 11 files” inventory using the exact eleven files above.** The read-only source search exposed 27 call-bearing lines; count actual expressions and report any revision/count difference rather than inventing a missing call. Distinguish direct store operations from assertions/calls on ordinary node methods. Every actual store call must migrate in this same reviewed task.

```bash
rg -n 'delete-entity|delete-notebook' \
  assets/lua/tests/test-string-entities.fnl assets/lua/tests/test-code-entities.fnl \
  assets/lua/tests/test-list-entities.fnl assets/lua/tests/test-dict-entities.fnl \
  assets/lua/tests/test-link-entities.fnl assets/lua/tests/test-identity-entities.fnl \
  assets/lua/tests/test-notebooks.fnl assets/lua/tests/test-board.fnl \
  assets/lua/tests/test-board-activity-string-entities.fnl assets/lua/tests/test-graph-map.fnl \
  assets/lua/tests/test-code-entity-list.fnl
```

- [ ] **Step 4: Compose canonical stores without replacing lazy defaults.** Initialize identity first, inject it into reference-store defaults, obtain code through its existing `get-default` plus root assertion, and compose workflow executor/runner with that same code object. Assert all injected roots/instances. Extend existing built-in composition options, not the immutable entity catalog. Propagate canonical `:lifecycle` to Graph's final `reference-lifecycle` field and GraphMap inheritance with explicit conflict assertions; keep standard loader injection and implement the checked node action resolver so direct browser children acquire ownership only from their mounted graph. Do not modify browser APIs/exports or introduce a global fallback.
- [ ] **Step 5: Install startup gating at the existing boundary.** After WorldManager exists but before `activate-first`, construct all five owners, create the service and call `start!`. Only after recovery and migration succeed may built-in runtimes/worlds be exposed. HomeWorld graph construction receives the canonical stores/lifecycle instead of silently creating different integration defaults.
- [ ] **Step 6: Rename physical APIs, route actions and remove legacy durable listeners in the same reviewed commit.** Update definitions/exports, owner calls, nine trusted-path inventory entries and all test callers in one task. Keep rollback paths physically retiring only their just-created representation. Route every genuine frontend intent centrally through the checked explicit-or-mounted lifecycle resolver; workflow-step deletion uses closure cleanup, not only native graph removal. **Now**, not in Task 6, disable/remove graph-node-removed and identity-deleted callbacks' owning membership writes in list/dict/notebook projections; retain their projection-only refresh paths. Update existing listener/map-removal tests in this same commit and verify ordinary map-only byte preservation plus real explicit identity deletion before (legacy evidence) and after (coordinated semantics). Do not leave a delegate-only/listener-removal-only intermediate commit with newly dangling identity deletion.
- [ ] **Step 7: Finish board and morph cutover.** Board authoring supplies canonical `:string-store`/`:identity-store` dependencies and stable subjects; board destructive removal resolves the represented subject and calls lifecycle. Remove the old delete-then-recreate rollback. Morph preparation reads through `lifecycle.stores.string-store`, invokes `replace!`, and emits only after completion; migrate existing morph tests from separate-root/store options to one explicit lifecycle composition.
- [ ] **Step 8: Verify no broken intermediate API remains, then validate/review the whole cutover.** Remaining old deletion names must be intentional node/frontend APIs only. Do not merge a rename-only or delegate-only partial commit.

```bash
check_stage 'reference lifecycle composition' main.fnl home-world.fnl \
  graph/core.fnl graph/map.fnl \
  graph/extensions/builtins/composition.fnl graph/extensions/builtins/entities.fnl \
  graph/extensions/builtins/workflows.fnl entities/string.fnl entities/code.fnl entities/list.fnl \
  entities/dict.fnl entities/link.fnl entities/identity.fnl notebooks/store.fnl \
  graph/nodes/string-entity.fnl graph/nodes/code-entity.fnl graph/nodes/list-entity.fnl \
  graph/nodes/dict-entity.fnl graph/nodes/link-entity.fnl graph/nodes/identity.fnl \
  graph/nodes/notebook.fnl graph/nodes/workflow-step.fnl board/view.fnl \
  board/builtin-string-entity.fnl board-activity-unit.fnl workflows/templates.fnl \
  graph/nodes/workflow-definition.fnl graph/nodes/workflows.fnl morphs/string-entity-to-code-entity.fnl \
  reference-lifecycle/entities-owner.fnl reference-lifecycle/identities-owner.fnl \
  tests/test-reference-lifecycle-composition.fnl tests/test-reference-lifecycle-browsers.fnl \
  tests/test-entities-browser.fnl tests/fast.fnl tests/test-reference-lifecycle-helpers.fnl \
  tests/test-morphs.fnl tests/test-workflow-graph.fnl tests/test-builtin-graph-extensions.fnl \
  tests/test-graph-extension-runtime-plumbing.fnl tests/test-string-entities.fnl \
  tests/test-code-entities.fnl tests/test-list-entities.fnl tests/test-dict-entities.fnl \
  tests/test-link-entities.fnl tests/test-identity-entities.fnl tests/test-notebooks.fnl \
  tests/test-board.fnl tests/test-board-activity-string-entities.fnl tests/test-graph-map.fnl \
  tests/test-code-entity-list.fnl
for filter in 'reference lifecycle' morph workflow entity notebook Board; do
  run_focused "$filter" || exit $?
done
rg -n 'delete-entity|delete-notebook|retire-entity!|retire-notebook!' assets/lua
```

Acceptance: startup never exposes unrecovered worlds, canonical cache identity holds, all user deletes (including six real browser child routes) coordinate with checked canonical ownership, trusted retirement remains explicit, and legacy physical method exports are absent. Listener cutover and default map-only byte preservation are green in this same commit, with explicit identity deletion preserved throughout staging. Suggested checkpoint: `feat(lua): activate canonical reference lifecycle commands`.

### Task 8: Permanent Integration Matrix, Developer Documentation and Final Gates

**Files:**
- Create: `assets/lua/tests/test-reference-lifecycle-integration.fnl`, `docs/dev/features/reference-lifecycle.md`
- Modify: `assets/lua/tests/fast.fnl`, `assets/lua/tests/test-reference-lifecycle-helpers.fnl`, `docs/dev/graph-maps.md`
- Modify: `docs/dev/notes/graph-identity.md`, `docs/dev/notes/morphs.md`, `docs/dev/notes/string-entities.md`, `docs/dev/features/entity-type-catalog.md`
- Review against: `docs/specs/2026-10-15-reference-lifecycle-design.md`, `docs/plans/2026-10-15-reference-lifecycle.md`

**Interfaces:**
- Consumes: Final canonical composition, public lifecycle/node actions, native authoring/runtime/persistence APIs.
- Produces: Registered permanent integration tests with prefix `"reference lifecycle integration"` and canonical developer documentation of live-owner coverage, recovery assumptions, internal retirement APIs and presentation-only removal.

- [ ] **Step 1: Complete the permanent matrix using actual authoring and frontend commands.** Cover selected-link/list creation, store mutation paths, both link directions, logical duplicate prevention, shared identity DI, direct aliases/upstream chains, cycles/depth, loaded/unopened containers, link dependency cycles, container deletion without member deletion, explicit identity deletion without target deletion and missing/unsupported targets.
- [ ] **Step 2: Add code/workflow and history byte assertions.** Create multiple steps across definitions sharing retiring code, unrelated steps/code, incident and unrelated edges, runs/events and provenance snapshots. Delete through the ordinary code-node API; assert every dependent step and incident edge disappears while all independent records and history bytes survive.
- [ ] **Step 3: Add retained/native and fresh-process reopen coverage.** Exercise active board, inactive board slot, unopened world, inactive map, selection/focus/outline/islands, keyed metadata and graph-owned panels. Follow morph/delete with capture, suspend/drop, reactivation and cold reopen. Preserve board item identity/transforms/state/connectors on morph and verify code uses Text, not Input.
- [ ] **Step 4: Extend the existing recovery tests through the integrated owners.** Fail world metadata writes and source retirement after incoming cleanup, restart into `start!`, and verify no duplicate replacement or resurrected source. External byte-derived before/after conflicts block startup with operation/owner/path diagnostics. Include empty roots, drafts, malformed records and real permission/path-collision failures with cleanup restored. Verify one WorldOwner durable change per path, RuntimeOwner's empty durable-change array, frozen namespaced capture replay without recapture, reconciliation-error pending retention and safe no-loaded-map restart/activation from durable after-images. Verify workflow decode/serialize ISO after-checks after multi-step aggregated cleanup and restart.

```fennel
(local history-before (fs.read-file run-path))
(local unrelated-before (fs.read-file unrelated-code-path))
(code-node:delete-entity)
(assert (= (fs.read-file run-path) history-before))
(assert (= (fs.read-file unrelated-code-path) unrelated-before))
(local fresh-stores (H.stores root))
(local fresh-service (H.lifecycle fresh-stores world-owner runtime-owner))
(fresh-service:start!)
(assert (= (fresh-stores.code-store:get-entity "retired") nil))
```

Use newly constructed real owners bound to `fresh-stores` for the cold-reopen variant; do not reuse old cached owners. Preserve all core semantic regressions permanently; ancillary provenance findings are separately labeled and documented, not silently omitted.

- [ ] **Step 5: Document the feature and operational contract.** In `docs/dev/features/reference-lifecycle.md`, document canonical store identity/root requirements, checked mounted lifecycle acquisition for browser children/detached errors, all five owners and exact schemas, shared Preparation/RuntimeCapture, exclusive WorldOwner durable persistence versus nonpersisting RuntimeOwner reconciliation, frozen serialized-byte checks/decoder timestamp domains, normalization/deduplication, logical versus physical deletion, workflow cascade, morph result compatibility, pending/migration files, single-writer replay/conflicts, dangling-reference reports and startup order. Link this page from `docs/dev/graph-maps.md`; clarify metadata/inactive-map coherence and presentation-only removal without claiming a general board-to-graph migration. Update the existing graph-identity and morph notes, string-store API notes, and entity-type-catalog startup/ownership guidance to remove superseded raw-reference migration, physical deletion, and separate code-store assumptions.
- [ ] **Step 6: Run focused validation, then the full relevant local suite.** The full suite is required because startup, filesystem bindings, persisted records, caches, workflows and multiple retained UI owners changed.

```bash
check_stage 'reference lifecycle integration' tests/test-reference-lifecycle-integration.fnl \
  tests/test-reference-lifecycle-helpers.fnl tests/fast.fnl
run_focused 'reference lifecycle'
make fennel-check
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH="$(pwd)/assets" make test
git diff --check
```

- [ ] **Step 7: Review the acceptance matrix and scope.** Attach RED/GREEN evidence for identity, owner migration, recovery, native board/inactive-world, browser-created children, listener cutover and projection gates. Report compile → constraints → audited focused tests (planned named roster, actual `[RUN]` names/count and retained log) → full-suite results and constraint impact. Reject zero/missing/mismatched execution and native failures; `workflow-store` must match its source-reviewed nine-test baseline, not temporal `workflow store` matches. No skipped semantic regression, ignored diagnostic output, provenance-only assertion or queue handoff counts as feature completion.
- [ ] **Step 8: Have the supervisor commit only after review pass and focused/full validation.** Suggested final checkpoint: `test(lua): verify reference lifecycle integration and recovery`.
- [ ] **Step 9: Perform current-base final validation and integration safely.** Fetch `origin`; compare against current `origin/main`, not local `main`. Before PR creation, safely merge `origin/main` if behind, route conflicts/fixes through implementer → reviewer → pass, commit reviewed changes and rerun applicable validation from a clean tree. Never rebase or force-push without explicit human instruction.

```bash
git fetch origin
git status --porcelain
git rev-list --left-right --count origin/main...HEAD
git diff --check origin/main...HEAD
git diff --stat origin/main...HEAD
```

- [ ] **Step 10: Treat PR CI as the full integration gate.** Once reviewed, committed, clean and locally green, the supervisor pushes the branch and creates a PR targeting `main`. Applicable **PR CI** must be green before any ready-to-merge claim; continue polling merge queue until the PR is actually merged. Do not update the PR merely because `origin/main` advances after queueing.

```bash
gh pr view <pr-or-branch> --json state,mergedAt,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,headRefName,headRefOid,url
gh run list --workflow test.yml --event merge_group --limit 20 --json databaseId,headBranch,headSha,status,conclusion,event,url,displayTitle,createdAt
gh run watch <run-id> --exit-status --interval 100
```

If any required validation fails, stop integration, capture the command/output/branch state and `git status --porcelain`, invoke systematic-debugging, and obtain reviewed fixes plus a green rerun. If merge queue is disabled or cannot be verified, report **HUMAN_DECISION_REQUIRED** for enabling/verifying GitHub’s merge queue on `main`; do not claim completion or enter a stale-branch polling loop. No unresolved product/API choice is otherwise required by the approved spec.
