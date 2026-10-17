# Reference Lifecycle Deferred Morph Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resume matching pending native morph/workflow-step actions even after their source was retired.

**Architecture:** Extend the one replacement interface to accept a deferred read-only payload builder. Matching pending admission stays inside the existing serialized coordinator boundary and reuses the frozen intent; a separate resume probe would split admission across calls.

**Tech Stack:** Native Fennel lifecycle coordinator, existing frozen intent/replay and native test runner.

## Global Constraints

- Existing strict table-payload matching remains unchanged. No journal schema migration, compatibility alias, new resume method, generic transaction framework or adapter private-journal access.
- Builders are synchronous/read-only; no yielding, store mutation or lifecycle commands. Never serialize a function in request/operation/capture/intent.
- Readiness/ownership/root/dependency/busy checks remain before builder invocation and all effects. Preserve all MorphResult fields, frozen reservations/captures and at-least-once notification semantics.
- Preserve dirty atomic Task7 BASE753cc2e/index/evidence; no worker stage/commit/integration or partial checkpoint. No new/increased baseline allowances.
- Required fresh full suite and independent review remain mandatory. This amendment fixes accepted R1-1; Board rollback R1-2 is separately accepted, noise R1-3 deferred.

### Task 7 Review Fix: Guarded Deferred Admission

**Files:** `assets/lua/reference-lifecycle/init.fnl`; `assets/lua/morphs/string-entity-to-code-entity.fnl`; `assets/lua/graph/nodes/workflow-step.fnl`; existing lifecycle recovery/composition tests; short `docs/dev/notes/graph.md` contract note. Plan validator stays authoritative/read-only.

**Interfaces:** `Lifecycle:replace!(key,payload-or-builder)->MorphResult`; MorphPayload `{name:string,language:"fnl",source:string,kernel:number|string}`, PayloadBuilder `()->MorphPayload`. Internal `command!(self,request,payload-builder?)` never persists the function. delete! unchanged; workflow delete frontend still returns frozen result.source-record.

- [ ] Independent interface/plan review pass before implementation. Reviewer checks this against current command admission, pending replay and native frontend failure states.
- [ ] Declare seven `reference lifecycle recovery deferred ` cases before native RED: fresh freeze; unrelated pending; matching conflict; serialized builder; builder failures; admission checks; strict table matching.
- [ ] Declare four `reference lifecycle composition action retry ` cases: morph committed; morph pending clear; workflow step committed; workflow step pending clear. Actual ordinary adapter action, real failure after source retirement, same adapter retries through valid explicit/mounted dependency.
- [ ] Inside protected serialized command retain owner validation/readiness, read pending before builder. Pending table requests compare complete materialized request exactly as before; pending builder requests require exact morph kind/source, replay existing validated intent without callback. Unrelated pending keeps existing conflict error, no builder/effects.
- [ ] No pending: validate Plan.target and string-entity target before callback, invoke once, require table, clone immediately into request.payload, then existing Plan.prepare/intent validation/write/replay. Invalid argument types explicit error. Callback failure releases busy and creates no intent/domain writes. Reentrancy from callback to start!/delete!/either replace form remains busy.
- [ ] Keep morph ownership/service resolution first; defer only live canonical string read and payload construction:

```fennel
(service:replace! source.key
  (fn []
    (local entity (assert (service.stores.string-store:get-entity source.entity-id)
                          "string->code morph missing source entity"))
    {:name "" :language "fnl" :source entity.value :kernel 0}))
```

- [ ] Remove only workflow delete frontend's premature get-step assertion. Keep service ownership resolution, delegation, successful graph removal and result.source-record; Show Code/loader validation unchanged.
- [ ] Seven service tests verify: one callback per fresh preparation attempt/materialized payload only; matching frozen replay callback0; same-source-delete/other-source-morph conflict callback0; external third-state conflict zero writes; nested commands busy and nested builders0; throw/non-table/invalid fields explicit errors/no writes and later success; not-ready/foreign dependencies/unsupported target callback0; changed table payload still conflicts and identical table payload replays across either creation form.
- [ ] Four frontend retries retain exact frozen target/identity reservations/payload/timestamps/captures and original result, clear pending, create one replacement/closure, never recapture/recreate source; workflow preserves unrelated steps/history. Both post-commit and pending-clear failure boundaries covered.
- [ ] Document intentional kind/key frozen resumption for builder form, unchanged strict table matching, read-only callback and at-least-once committed notifications. Once means per fresh preparation attempt, not across pre-journal failures.
- [ ] Native compile first, canonical repo constraints0 second, actual audited7+4 focused tests third; then existing lifecycle/morph/workflow/startup guards. Runtime rebuild only if missing/stale (make build timeout14400000); native macro/assets paths/audio-off/keyring-skip/externalXDG required.
- [ ] Fresh standard `make test` (timeout14400000), complete fix-only/original-reviewed snapshot diff plus full BASE diff/hashes/baseline/index/caller audit, independent targeted review before atomic checkpoint. Earlier full green cannot validate amended code. PR CI/current-origin/Task8 remain open.

## Self-Review

This preserves existing explicit table conflict behavior and journal schema while letting frontends intentionally defer reads until admission. Frozen matching replay never computes new payload/reserves identities/prepares/recaptures; existing replay checks remain authoritative. Busy scope encloses callback execution. Review the sole adapter builder for purity rather than promising arbitrary user callback enforcement. No product decision or additional representation type is introduced.
