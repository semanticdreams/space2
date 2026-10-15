# Independent Fast-Dev Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable direct interactive development with local checkpoints and defer review/integration until explicit wrap-up.

**Architecture:** A concise broad-permission primary, an on-demand wrap-up skill,
and one observational final reviewer. An identity-scoped AGENTS exception
resolves inherited process conflicts without changing shared skills or wrappers.

**Tech Stack:** OpenCode Markdown/YAML, Markdown skills, Python policy checker,
pytest, Git, GitHub CLI.

## Global Constraints

- Authoritative spec: `docs/specs/2026-10-15-fast-dev-independent-workflow-design.md`.
- "Environment isolation, not narrow tool permissions or operational worker agents, bounds its authority."
- "A commit request is local only."
- "There is no mandatory independent re-review per fix."
- "No direct main push, rebase, or force-push."
- "Keep other primary/subagent permissions, the default agent, shared skills, and capability wrappers unchanged."
- "No engine build is justified by this surface."
- This implementation uses the current strict workflow; new permissions do not apply to the running session.

## Task 1: Replace the Coupled Fast-Dev Contract

**Files:**
- Modify: `.opencode/agents/fast-dev.md`
- Create: `.opencode/agents/fast-dev-reviewer.md`
- Create: `.opencode/skills/fast-dev-wrap-up/SKILL.md`
- Modify: `AGENTS.md`
- Modify: `.opencode/agents/supervisor.md` (stale fast-dev descriptions only)
- Modify: `scripts/check_opencode_permissions.py`
- Test: `scripts/tests/test_check_opencode_permissions.py`
- Test: `docs/scripts/test-opencode-automation-config.mjs` (diagnosed stale strict-contract assertions)
- Modify: `docs/dev/features/opencode-agent-workflow.md`

**Interfaces:** Preserve `check_repo(repo_root: Path) -> list[PolicyViolation]`
and its CLI. The primary has scalar `permission: allow`. The reviewer consumes
user intent, recorded base/head SHAs, and validation evidence; it returns
reviewed SHAs, concrete file/line findings, and coverage gaps. The skill consumes
explicit wrap-up authorization and produces a merged PR plus fetched-main proof
or a specific human-owned blocker. These contracts form one coherent reviewable
deliverable rather than independently useful intermediate tasks.

- [ ] **1. Add failing profile/contract tests.** Use existing test fixtures to
  accept scalar broad permission only for canonical fast-dev in primary mode;
  reject that grant for another agent, wrong mode, or scalar ask. Cover the
  dedicated reviewer profile and retained existing role boundaries. Replace
  old assertions requiring escalation, local-main work, and vertical handoffs.
  Run `python3 -m pytest scripts/tests/test_check_opencode_permissions.py -k fast_dev`
  and record the expected failure before implementation.
- [ ] **2. Rewrite the primary prompt.** Preserve model/variant/steps; use
  `permission: allow`. Require direct work on `fast-dev/<topic>` before edits,
  fresh `origin/main` for new topics, deliberate reuse of current unmerged work,
  preservation/clarification of unrelated dirty state, short intent-focused
  local commits, optional exploration, relevant Space technical skills, and
  explicit-only wrap-up. Remove design/delegation/review gates and all awareness
  of other primary agents. No automatic push on task completion or commit request.
- [ ] **3. Scope inherited process in AGENTS.** Near the top, exempt selected
  fast-dev from mandatory planning/docs, workers, advisor gates, per-change
  review, verbose commit templates, and immediate integration, including process
  instructions imported by domain skills. Retain technical standards and
  evidence-based debugging, block integration with unresolved material defects
  or required failures, and preserve other agents' contracts.
- [ ] **4. Add the observational reviewer.** Use subagent mode, the approved
  model, read/search/Git inspection, `bash: allow`, and `edit: deny`, `task: deny`,
  external/web/question denies. Its prompt prohibits mutations, tests, GitHub,
  commits, and operations. Inspect every accumulated commit and final diff;
  verify supplied SHAs. Missing process artifacts are not review findings.
  No exact-command sandbox or operational worker role.
- [ ] **5. Add the on-demand skill.** Trigger only explicit wrap-up/integration,
  not ordinary completion or commit requests. Commit intended work; fetch
  `origin/main`; safely merge if needed; resolve directly; inspect
  `git log origin/main..HEAD` and `git diff origin/main...HEAD`; run proportional
  checks; request one full independent review. Fix findings/failures directly,
  commit, self-review and revalidate without mandatory independent re-review.
  Follow Space's build freshness and compile/constraints/focused-test ladder
  when relevant, rather than duplicating all technical guidance.
- [ ] **6. Define direct Git/GitHub finishing.** Confirm repository/PR identity,
  queue/test protection, clean tree, current base, resolved findings, green
  validation; push topic branch, create/reuse main-targeting PR, enable auto-merge.
  Poll PR and relevant merge-group checks at 100-second cadence; pending is not
  done. Diagnose/fix actionable failures directly. No main-only freshness merges
  after queue entry. Require `mergedAt`, merge SHA, fresh fetch and
  `git merge-base --is-ancestor <merge-sha> origin/main`. Preserve worktree/branch;
  report specific access/settings/ownership/decision/timeout blockers.
- [ ] **7. Implement checker profiles.** Recognize exactly canonical fast-dev's
  scalar grant with primary mode; reject scalar grants elsewhere. Enforce the
  observational reviewer contract, keeping existing generic and role checks.
  Do not add it to capability agents or change wrappers/config/defaults.
- [ ] **8. Align docs/descriptions.** Replace obsolete fast-dev documentation,
  scope strict-only prose and raw-GitHub prohibitions, and label retained
  local-main recovery as legacy strict flow. Update only stale peer descriptions
  in the existing strict primary. Document isolation assumptions and restart.
- [ ] **9. Test reference-skill scenarios.** The baseline evaluation already
  failed direct edit/commit-only behavior, self-contained wrap-up, and fetched
  origin/main completion. Re-evaluate the updated files read-only: ordinary
  edit/commit, explicit wrap-up, direct finding fixes, imported domain routing,
  queued PR, and actual merged-main proof. Refine demonstrated gaps only; these
  are instruction scenarios, not runtime permission tests or demo publishing.
- [ ] **10. Validate.** Run the commands below, then send all implementation
  changes plus spec/plan to independent review. Fix findings through the current
  strict loop before committing. No external-home inspection, live restarted
  permission testing, new eval framework, or engine build is required.

### Evidence-based validation scope extension

The required docs suite reproduced eight failures in the unchanged JS automation
test: it requires raw GitHub grants/polling that current strict agents and shared
skills explicitly deny/delegate. Diagnostic advisor confirmed this mismatch.
Update that single test file to assert existing guarded strict contracts and the
separate fast-dev lifecycle, preserving branch-protection/merge-queue coverage.
Do not change permissions/shared skills/wrappers to satisfy obsolete assertions.

```bash
python3 -m pytest scripts/tests/test_check_opencode_permissions.py
python3 scripts/check_opencode_permissions.py --repo-root .
make opencode-check
npm --prefix docs run test:scripts
git diff --check
```

## Finishing

After review passes, commit only reviewed files, fetch/evaluate current
`origin/main`, rerun relevant checks from a clean tree, push/create auto-merge
PR through the currently active strict capability flow, and poll to actual
merge. Report evidence accurately: static/config/scenario validation does not
prove a running OpenCode session loaded new permissions. Tell the user to restart.
