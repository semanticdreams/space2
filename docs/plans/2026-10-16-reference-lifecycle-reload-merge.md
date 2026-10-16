# Reference Lifecycle Reload Merge Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the pinned upstream merge without losing either parent's reload coverage or adding structural debt before lifecycle Task 7.

**Architecture:** Extract root-fixture ownership support and its runner regressions into one dependency-injected test-support module. Keep all 21 registrations, scenario wrappers, normal-startup case and public exports in the existing integration suite. Ownership regressions exercise the actual extracted cleanup implementations, not copies.

**Tech Stack:** Native Space Fennel compiler, constraints and runner; CTest; existing Python/pytest and isolated native startup fixtures.

## Global Constraints

- Pinned HEAD: `debad4505695dce453e627ef76a38e4f53bcf099`; MERGE_HEAD: `b255778eef6fc3690e8115a2f38cc607fc4b2dc1`.
- Preserve all 21 distinct test names, original order, assertions and exports exactly once through `tests.test-hot-reload-integration:main`.
- Change only `assets/lua/tests/test-hot-reload-integration.fnl`, `assets/lua/constraints/baseline-data.fnl`, and one new `assets/lua/tests/hot-reload-root-support.fnl`.
- Do not change production, runner, fast/slow registration or unrelated staged upstream bytes.
- Preserve real-renderer root fixtures, consumed-slot post-hook teardown, independent cleanup after errors, case-local 300-second budgets, explicit environment precedence including zero, and saved-engine once-only shutdown.
- Both test modules must satisfy the unchanged 1200-line native limit. New helper has zero raw findings and zero baseline exceptions.
- Existing baseline maintenance requires source continuity and unchanged/reduced measures; zero new exceptions, suppressions or limit changes.
- Workers never stage/commit/integrate or abort/reset/rebase/clean. Preserve ignored evidence.
- Supervisor commits the plan together with the reviewed merge resolution: an independent plan-only commit cannot be made while the already-started merge has unresolved index entries.

## Evidence and Diagnosis

Evidence: `.superpowers/sdd/2026-10-15-reference-lifecycle-29954b47/merge-b255778e-report.md` and `build/merge-b255778e-evidence/diagnosis.json`.
Fresh native build and repository compilation (1339 files) passed. Combining the parents' distinct 18-case suites produces 21 cases and a native module measure of 1354, exceeding 1200 without an existing allowance. Debug advisor confirmed this requires a bounded extraction rather than a new baseline exception. Planner independently specified the boundary below. This is technical merge repair, not a change to approved lifecycle behavior.

### Task 1: Extract, Validate and Review the Root Ownership Boundary

**Files:** The three-source whitelist above; this plan is supervisor-owned.

**Interfaces:** `tests.hot-reload-root-support` exports `{:create create}`. `create(deps)` returns a final literal containing callable `with-root-reload-fixture`, `teardown-root-fixture`, `runner-timeout-metadata-precedence-and-validation`, `runner-case-teardown-restores-hook-and-preserves-errors`, and `runner-saved-engine-scope-attempts-shutdown-once` fields. Dependencies are late-bound `get-app`, existing original-suite helpers `require-main!`, `start-test-control!`, `stop-test-control!`, `dispatch-control!`, `check-async-result!`, `test-hot-reload-config`, and the existing runner module.

- [ ] Capture pinned refs, full index/cached diff and outside-whitelist working hashes before edits; retain identical index/upstream bytes throughout.
- [ ] Relocate the exact existing forms: `count-searcher-occurrences`; `assert-root-reload-state!`; `assert-default-root-roundtrips!`; `run-cleanup-stages!`; `field-restoration`; `drain-cleanup-slot!`; `drop-owned-root-controller!`; `drop-owned-root-main!`; cleanup slot/teardown; `assert-manual-root-roundtrip!`; `with-root-reload-fixture`; the three named runner regression functions; `assert-root-cleanup-ownership!`.
- [ ] Keep substantial functions top-level with explicit dependencies/slot parameters. Allocate the consumed cleanup slot per support instance. Do not wrap all implementations in a large factory. Named closures replace nested anonymous callbacks where needed to avoid moving accepted structural debt into a new module.
- [ ] Keep root scenario wrappers and all registrations/exports in the original suite. Construct support once immediately after `test-hot-reload-config` and obtain `app` at execution time, not import time:

```fennel
(fn current-test-app [] app)
(local root-support
  (RootSupport.create
    {:get-app current-test-app :require-main! require-main!
     :start-test-control! start-test-control! :stop-test-control! stop-test-control!
     :dispatch-control! dispatch-control! :check-async-result! check-async-result!
     :test-hot-reload-config test-hot-reload-config :runner (require :tests/runner)}))
```

- [ ] Inspect ownership invariants: cleanup installed before initialization can fail; slot cleared before invocation; owned controller cleared before potentially throwing drop; borrowed/uninitialized objects not dropped; real fixture tears down owned Main, coordinator, restoration stages and temp directory in order, attempting all stages after errors; restore borrowed transport fields and FileWatcher too.
- [ ] Run native touched-file compile before canonical repository constraints. Maintain only existing source-continuous original-suite rows (20 expected location changes: 17 nesting and 3 style), recompute baseline self-length, and preserve lifecycle/upstream debt reductions. Do not copy a module-level exception to the helper.
- [ ] Recompile all three files and require canonical repository constraints status `pass`, zero diagnostics. Existing RED is the recorded native 1354-line failure; extraction is structural, not a new production behavior.
- [ ] Execute original unfiltered integration entry point and audit ordered RUN/PASS names against diagnosis's exact 21-name union. Verify each root teardown attempts/returns once and saved engine finalizes once.
- [ ] Run the first three `test runner` cases with explicit `SPACE_TEST_CASE_TIMEOUT_SECONDS=0`; verify retained timeout-selector assertions and all three pass. Run exported `probe-missing-module` as an intentional-negative child; require the original diagnostic, ordinary nonzero exit and once-only engine shutdown, not an arbitrary failure.
- [ ] Run merge-risk guards below, then generate complete parent-relative diffs, source snapshots/hashes, baseline row mapping, exact command/exit/roster audits and unchanged-index/outside-whitelist checks.
- [ ] Independent reviewer checks extraction plus both conflict resolutions, all ownership/coverage invariants and baseline continuity. Supervisor stages only approved resolution/helper/plan bytes, completes pinned merge and records ledger state before Task 7.

## Validation Commands and Coverage

Use the existing ignored recorder `python3 build/merge-b255778e-evidence.py LABEL COMMAND...`; retain logs/audits without overwriting blocked evidence. Set absolute `SPACE_ASSETS_PATH`, FENNEL_PATH/FENNEL_MACRO_PATH for assets/lua, audio disabled, keyring skipped, external XDG data, TEST_VERBOSE=1. Unset accidental TEST_FILTER, SPACE_TEST_CASE_TIMEOUT_SECONDS and startup selector except intentional cases.

Fresh native build already passed. Rebuild if missing/stale or native scaffolding changes (`make build`, timeout 14400000; configuration timeout 600000).

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-hot-reload-integration.fnl --file assets/lua/tests/hot-reload-root-support.fnl --file assets/lua/constraints/baseline-data.fnl --output summary
./build/space -m constraints.runner:main -- --target repo --output json
./build/space -m tests.test-hot-reload-integration:main
./build/space -m tests.test-live-dev-runtime:main
./build/space -m tests.test-units:main
./build/space -m tests.test-remote-control:main
./build/space -m tests.test-live-hot-reload:main
python3 -m pytest scripts/tests/test_live_dev.py
xvfb-run -a ctest --test-dir build --output-on-failure --no-tests=error -R '^(test_live_dev_bootstrap|test_asset_manager|test_runtime_asset_discovery_integration|space_runtime_fennel_paths|space_live_dev_integration)$'
```

Also run tests.fast literal filters `reference lifecycle`, `GraphMap`, `GraphView`; audit actual nonempty rosters/counts, not historical estimates. The live-dev module declares25 outer cases; distinguish actual native startup children from the outer summary. Use bounded observational child evidence where available; do not modify runner/test fixtures to manufacture audit output or add a tracing dependency solely for this repair.

Unexpected required failures return to systematic debugging/advisor before speculative fixes. No bypass of compile/constraints, weakening test assertions or claiming child observations not actually obtained. Full feature `make test`, current-origin evaluation and applicable PR CI remain lifecycle Task8/final finishing gates.

## Self-Review and Scope

This single reviewable task covers the confirmed merge-only structural violation and retains the original entry point, exact roster, real fixtures and cleanup ownership. No production API/data decision is introduced. No additional developer-document rewrite is necessary for this internal extraction; existing documentation obligations remain Task8. If correctness needs production/runner changes, independent registration or new accepted debt, return evidence for renewed planning instead of silently widening scope.
