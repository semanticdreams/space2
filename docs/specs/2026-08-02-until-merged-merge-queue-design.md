# Until-Merged Merge Queue Workflow Design

## Context

Space now lives at `https://github.com/semanticdreams/spacecore`, an
organization-owned repository where GitHub merge queue can be used. The previous
merge-queue workflow update moved agents away from repeatedly updating stale PR
branches after PR creation, but it intentionally stopped after queue handoff.

The desired behavior is stronger: once an OpenCode worker has created a PR and
requested auto-merge/merge-queue integration, the worker should keep running
until the PR is actually merged into `main` or until an actionable blocker needs
human input or reviewed repository fixes.

Repository exploration found two concrete gaps:

- `.github/workflows/test.yml` defines the required check workflow named `test`,
  but its `on:` block only includes `push` and `pull_request`; it does not run
  on `merge_group`, so merge-queue candidates will not receive the required
  check.
- GitHub ruleset inspection shows active ruleset `19817562` requires PRs and
  required status check `test`, but does not include `merge_queue`. Disabled
  ruleset `20232493` includes a `merge_queue` rule with `test`. A repository
  admin must enable an active merge-queue rule for `main`.

## Explored Approaches

### Approach A: Keep stop-after-handoff

Agents would validate, open the PR, request merge queue, and then exit. GitHub
would eventually merge or report failure.

This prevents stale-branch CI loops, but it does not satisfy the new requirement
that the agent stay alive and handle queue/check failures without manual
intervention.

### Approach B: Monitor the queued PR until merged

Agents would keep pre-PR validation strict, request auto-merge/merge queue, then
poll PR and merge-group status until `mergedAt` is present. They would keep
waiting for queued, pending, in-progress, expected, or null-conclusion states.
They would only modify the branch when GitHub reports an actionable blocker such
as a conflict or failing required check.

This satisfies the requirement while preserving the main benefit of merge queue:
agents do not update branches merely because `origin/main` advanced.

### Approach C: Central merge steward

A separate steward process would monitor all ready PRs and dispatch repairs. This
could reduce duplicated polling across many Orca sessions, but it is custom
orchestration and is not needed now that each session can use GitHub merge queue
as the serialized integration point.

## Recommended Direction

Use Approach B.

The contract is:

1. Before final validation and PR creation, fetch `origin` and ensure the branch
   has accounted for current `origin/main`.
2. Run required validation and create the PR.
3. Request auto-merge/merge queue.
4. Poll until the PR is merged, using `mergedAt` or equivalent merged state as
   the only success condition.
5. Do not update the branch solely because `origin/main` advanced while the PR is
   queued.
6. If GitHub reports merge conflicts, required-check failures, queue permission
   failures, missing active merge queue, or a closed-unmerged PR, handle those as
   blockers. Repository fixes go through `systematic-debugging`, `implementer` →
   `reviewer` → pass, commit, validation from current `origin/main`, and requeue.

## Design

### Architecture

- GitHub Actions `test.yml` must run on `merge_group` so the required `test`
  check appears for merge-queue candidates.
- Repository policy in `AGENTS.md` describes the until-merged queue-polling
  contract.
- Developer docs mirror the policy for humans using Orca/OpenCode.
- OpenCode supervisor and finishing/automation skills use the same polling and
  blocker-handling rules.
- OpenCode supervisor permissions allow only the minimum GitHub CLI polling
  commands needed to inspect PR state, check status, merge-group runs, and watch
  runs.
- Focused config tests in `docs/scripts/test-opencode-automation-config.mjs`
  guard against regressing to stop-after-handoff language or omitting the
  `merge_group` trigger.

### Polling Contract

Agents should use GitHub CLI state as the integration source of truth, for
example:

```bash
gh pr view <pr-or-branch> --json state,mergedAt,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,headRefName,headRefOid,url
gh run list --workflow test.yml --event merge_group --limit 20 --json databaseId,headBranch,headSha,status,conclusion,event,url,displayTitle,createdAt
gh run watch <run-id> --exit-status --interval 100
```

Success is the PR being merged, preferably represented by a non-null `mergedAt`.
Green PR checks or a successful merge-group run are not terminal by themselves;
they are evidence to continue polling until GitHub records the PR as merged.

Continue polling for non-terminal states such as queued, waiting, pending,
expected, in progress, null conclusion, or checks that have not started.

### Error Handling

Actionable blockers:

- merge conflict or non-mergeable PR;
- required `test` check failure on the PR or merge-group candidate;
- merge queue missing, disabled, or unavailable on the active `main` ruleset;
- missing GitHub authentication or permission to queue/merge;
- PR closed without being merged;
- queue timeout or missing merge-group run after enough polling evidence.

Repository fixes must go through `systematic-debugging` before diagnosis and
`implementer` → `reviewer` → pass before commit. After a reviewed fix, agents
rerun validation from current `origin/main`, push the branch, and requeue. Rebase
and force-push remain forbidden unless explicitly requested.

Missing or disabled GitHub merge queue is `HUMAN_DECISION_REQUIRED`, not a reason
to bypass branch protection or manually update stale PR branches.

### Testing

- Add a focused script test that asserts `.github/workflows/test.yml` includes a
  `merge_group` trigger.
- Add focused script tests that assert AGENTS/docs/OpenCode workflow text uses
  until-merged polling, includes `mergedAt`/`gh pr view`/merge-group run
  inspection, and does not retain stop-after-handoff terminal language.
- Run `cd docs && npm run test:scripts`.
- Run `cd docs && npm run docs:build`.
- Run `git diff --check` on changed files.
- Inspect GitHub rules via API; report if active rules still lack `merge_queue`.

## Scope

In scope:

- Adding `merge_group` to the required `test` GitHub Actions workflow.
- Updating repo policy, docs, supervisor, and OpenCode skills to monitor until
  PR merge.
- Adding config/script tests for the merge-queue workflow contract.
- Reporting the active/disabled GitHub ruleset state.

Out of scope:

- Building a separate merge steward service.
- Renaming checks or broad CI redesign.
- Direct pushes to `main`.
- Rebasing or force-pushing branches.
- Editing production runtime behavior.

## Self-Review Notes

- No placeholders remain.
- The design explicitly reverses the prior stop-after-handoff terminal behavior
  while preserving the no-stale-branch-update loop.
- The required `merge_group` CI trigger and active GitHub ruleset follow-up are
  both captured.
