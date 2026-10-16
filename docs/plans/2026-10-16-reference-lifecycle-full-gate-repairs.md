# Reference Lifecycle Full-Gate Repairs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve Task7 full-suite failures without weakening native coverage or approved lifecycle semantics.

**Architecture:** Complete the existing mock's finite FXAA contract, correct four fixture ownership/normalization mismatches, and omit only duplicated outline selection from both capture paths. Keep real renderer startup, canonical ownership checks and opaque-state preservation.

**Tech Stack:** Native Space Fennel, existing OpenGL/shader bindings, test runner and Make/CTest.

## Global Constraints

- Evidence: `.superpowers/sdd/2026-10-15-reference-lifecycle-29954b47/task-7-debug-evidence-6.md`; advisor confirmed A–E, distinguished F's selection ownership from Task5-approved opaque preservation; planner bounded this task.
- Preserve BASE753cc2e, all dirty Task7 work, empty index and ignored evidence. No worker staging, commits, integration or destructive Git operations.
- No new abstraction, broad mock dispatcher, production fallback, validator relaxation, dependency, compatibility alias or new/increased baseline debt.
- Preserve all original behavior assertions except the explicitly contradictory expectation that an undocumented opaque `stale?` field disappears.
- Full local suite must pass before the atomic Task7 checkpoint; independent full reviewer covers all cutover changes and amendments, not just this repair.

### Task 7 Addendum: Harness, Fixture and Outline Corrections

**Files:** `assets/lua/mock-opengl.fnl`; `assets/lua/tests/test-reference-lifecycle-composition.fnl`; `assets/lua/tests/test-menu.fnl`; `assets/lua/tests/test-graph-loaders.fnl`; `assets/lua/tests/test-entities-browser.fnl`; `assets/lua/tests/test-link-entity-crash.fnl`; `assets/lua/graph/view/runtime.fnl`; `assets/lua/tests/test-graph-outline-view.fnl`; source-continuous existing baseline maintenance; short `docs/dev/notes/graph.md` clarification. No new module or registration.

**Interfaces:** Preserve native signatures: glGenTextures(n)→number; glDeleteTextures(texture) and glDeleteRenderbuffers(renderbuffer) take single handles; glTexImage2D has eight positional arguments without data pointer; glTexParameteri three; glFramebufferTexture2D five; shader:setVector2f(uniform,x,y); checkFramebuffer(). Preserve capture-state and snapshot-reference-state exports, removing only mode_states.outline.selected_node_keys.

- [ ] Freeze hashes/index/rosters and reproduce unchanged failures, including separately `outline runtime capture retains other mode states`. Native child status, not diagnostic Python wrapper exit, is authoritative.
- [ ] Add `reference lifecycle composition renderer nonzero viewport FXAA contract`: scoped fresh mock/real fxaa,640×480 allocate, same-size no reallocate,800×600 replace, render/drop, exact allocation/attachment dimensions/constants/reciprocal texelStep/draw args/single-handle resource deletion, protected cleanup. Obtain actual RED before mock edits.
- [ ] Complete only finite FXAA surface in mock, including constants RGB/UNSIGNED_BYTE/MIN+MAG_FILTER/LINEAR/WRAP_S+T/CLAMP_TO_EDGE/DEPTH_COMPONENT; allocation/texture/framebuffer operations, shader vector setter and resource teardown. Use focused private FXAA installer so existing381-line mock factory does not grow. No catch-all stub. Scope real startup tests to nonzero viewport and restore afterward; no renderer replacement/zero-viewport workaround.
- [ ] Menu fixture passes custom LinkStore's exact IdentityStore to Graph; retain both filtering paths/counts/node identity checks.
- [ ] Builtin loader fixture uses existing H.stores(fs.absolute(dir)) normalized canonical bundle for Graph and builtin helper; retain real loader/browser/preview/native assertions and explicit kernels/LLM/HackerNews dependencies. No helper redesign/unneeded lifecycle startup.
- [ ] Browser isolation captures original normalized target and persisted bytes before navigation; afterward require exact same target/bytes, identity prefix and terminal code-entity-list through that store's IdentityStore. Retain unrelated record count1, edges1/0 and exact store identity.
- [ ] Link crash fixture passes store.identity-store to Graph; retain immediate synchronous edge count1 and actual native view:update crash regression without waits/substitute views.
- [ ] Add `outline reference snapshot keeps graph-map selection owner`: top-level selection/focus/presence, omitted duplicate outline selection, retained opaque true/false fields/spatial/cameras, snapshot source nonmutation/no durable IO. Keep existing ordinary selection-owner assertion. Change only old stale? disappearance expectation to preservation.
- [ ] After assembling each cloned ordinary/reference capture result, remove only nested outline.selected_node_keys when outline table exists. No clearing arbitrary mode fields, source mutation, restore policy change or removal of cameras/spatial/top-level selection/focus.
- [ ] Existing baseline rows only native-confirmed source-continuous remap/reduction/removal; no helper debt transfer or self-measure increase. Document GraphMap sole selection ownership and opaque mode/nonpersisting snapshot contract.
- [ ] Native compile touched files first, canonical repo constraints pass0 second, exact focused tests third. Unique RED/GREEN labels retain exact source/binary hashes. Then affected guards and standard required make test; unexpected failures follow diagnostic/advisor process, not bypass.
- [ ] Final complete BASE-relative diff/snapshots/hashes/caller inventory/baseline mappings/index audit; independent full Task7 review and fix loop before checkpoint. No partial API/listener cutover commit.

## Validation Surface

Use existing task7-check.py with absolute assets/Fennel/macro paths, audio disabled, keyring skipped and external XDG. Build first only if native executable missing/stale; make build timeout14400000. Compile/constraints precede all native test evidence.

Exact individual filters: new renderer case1; composition startup5; Menu root show link entities adds related nodes1; built-in graph extensions register and load nodes1; Entities fixture ignores unrelated default-store links1; test-graph-view-crash-reproduction1; outline restore keeps graph-map selection owner1; outline runtime capture retains other mode states1; new outline reference snapshot case1. Preserve actual resize→startup sequence using native invocation directly: diagnostic wrapper does not propagate child exit. Require exact RUN/PASS and native exit0 after fix.

Rerun actual audited lifecycle/composition/morph/workflow/entity/notebook/Board/startup guards, main-events, live-dev25, reload21, plumbing7, renderers and outline modules. Exact direct workflow-store guard9 uses tests.test-workflow-store:main. Reconcile any roster drift with source, not historical guessed totals. New renderer case adds one lifecycle/composition name; new outline case is separate.

Mandatory final command (timeout14400000): `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test`. Retain full output/status, constraints and CTest/Lua summaries. No whole-feature readiness until later Task8/current-origin/PR CI gates.

## Self-Review and Scope

The bounded changes address observed failure sources, preserve actual renderer behavior and owner validation, and separate owned selection fields from opaque extension data as already approved. No product/API decision remains. C++/renderer implementation changes, shared runner redesign, broader projection cleanup, new tools or unrelated fixture migrations require renewed evidence/planning.
