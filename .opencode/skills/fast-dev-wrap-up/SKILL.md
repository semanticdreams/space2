---
name: fast-dev-wrap-up
description: Use ONLY when the selected fast-dev or live-dev primary receives explicit user wrap-up/integration authorization.
---

# Shared fast-dev / live-dev wrap-up

This one skill serves both named callers: ordinary task completion and a commit request
do not authorize publishing. Explicit user wrap-up/integration authorization does.
Keep the selected caller; do not reject live-dev merely because this skill's name
starts with fast-dev. Do not switch primaries to use it, even under deadline pressure.

| Selected primary | Required branch |
| --- | --- |
| `fast-dev` | `fast-dev/<topic>` |
| `live-dev` | `live-dev/<topic>` |

Verify the exact selected caller and its corresponding branch: prefixes are not interchangeable.
An unknown caller or caller/branch mismatch blocks this path; report the mismatch
and clarify ownership rather than silently renaming, switching, or adopting unrelated work.

Own finishing directly with raw `git` and `gh`. No direct main push, rebase,
force-push, branch deletion, or worktree cleanup.

## Prepare and review

- Confirm the selected caller's matching branch, intended scope, and ownership of dirty state.
  Inspect status and staged/unstaged diffs; commit only intended pending work.
- `git fetch origin`; use current `origin/main`, never local `main`. If behind,
  `git merge origin/main` safely; resolve conflicts directly, commit, and inspect
  the result. Do not overwrite unrelated work.
- Inspect **all commits** with `git log origin/main..HEAD` (including each
  commit's diff) and the final diff with `git diff origin/main...HEAD`.
  Run proportional checks and record commands/results. Follow `AGENTS.md` and
  relevant technical skills, including `space-testing-runtime`: build first if
  the runtime is missing/stale or host code changed; for Fennel, compile check,
  constraints, focused tests, then broader checks only when risk requires them.
  Prompt/docs-only work needs no engine build.
- Record base/head SHAs (`git rev-parse origin/main HEAD`), user intent, and
  validation evidence. Request one independent review from `fast-dev-reviewer`
  covering every accumulated commit and final diff at those SHAs.
- Fix findings and failing checks directly after evidence-based diagnosis;
  commit fixes, self-review the resulting commits/diff, and revalidate affected
  behavior. There is no mandatory independent re-review per fix. Do not integrate
  with unresolved material findings or required validation failures.
- Before publishing, fetch again. Reconcile any pre-PR base changes by safe
  merge, inspect all resulting changes, and revalidate as needed. Confirm clean
  tree, current base, resolved findings, and green validation.

## Publish and wait

Confirm `origin` and `gh repo view` identify the intended repository. Inspect
active main rules (`gh api repos/<owner>/<repo>/rules/branches/main` and branch
protection as needed): require merge queue and required `test` protection for
merge-group candidates. Missing/unverifiable settings need an admin, not bypass.

Push only the topic branch (`git push -u origin <topic-branch>`). Create with
`gh pr create --base main --head <topic-branch>` or reuse the matching open PR.
Verify repository, base `main`, head branch and SHA; do not reuse a closed or
stale merged PR. Enable auto-merge with `gh pr merge <pr> --auto --squash`.

Poll PR and relevant merge-group checks at **100-second cadence**:

```bash
gh pr view <pr> --json state,mergedAt,mergeCommit,baseRefName,headRefName,headRefOid,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,url
gh run list --workflow test.yml --event merge_group --limit 20 --json databaseId,headBranch,headSha,status,conclusion,event,url,createdAt
gh run watch <relevant-run-id> --exit-status --interval 100
```

Correlate runs to this PR's queue branch/SHA; unrelated green runs prove nothing.
Queued, waiting, pending, in-progress, expected, and missing conclusions are not
completion. After queue entry, do not merge main solely because it advances.
Diagnose conflicts or failed/cancelled/timed-out/action-required checks directly;
fix, commit, self-review, validate against current `origin/main`, push and requeue.
For access, disabled/missing queue, closed-unmerged PR, ownership/decision, or
reasonable timeout blockers, report the exact evidence and human action needed.

## Completion proof

Require PR `mergedAt` and `mergeCommit.oid` (the merge SHA), then run a fresh
`git fetch origin` and `git merge-base --is-ancestor <merge-sha> origin/main`.
Only success proves the merge is in fetched main. Report PR URL, merge SHA,
validation/review summary, and ancestry evidence. Preserve branch and worktree.
