# Merged PR Follow-Up Branch Recovery Design

## Problem

The finishing workflow can get stuck after a pull request has already merged at
an older branch head. If reviewed follow-up commits are later pushed to the same
branch, GitHub still resolves that branch name to the merged PR. The guarded PR
operator refuses to create another PR because the existing PR head does not match
the current branch head, and the guarded Git integrator has no allowed operation
for creating a fresh branch. The supervisor must stop with
`HUMAN_DECISION_REQUIRED` even though the safe recovery is mechanical.

## Goal

Allow future finishing runs to recover automatically by creating a fresh,
collision-checked follow-up branch from the reviewed current `HEAD`, then using
the existing current-branch PR path.

## Non-Goals

- No broad Git or GitHub permission expansion.
- No rebase, reset, force-push, branch deletion, or direct main push.
- No `gh pr create --head *` wildcard permission.
- No bypass of final validation, review, clean-tree, or current-base checks.

## Design

Add a narrow guarded Git wrapper action for the `git-integrator` capability:
create and switch to a follow-up branch from the current `HEAD`.

The action is available only when all guards pass:

- current worktree is clean;
- current branch is named and is not `main`;
- current `HEAD` already contains current `origin/main`;
- source branch name and derived branch name satisfy the existing safe branch
  policy;
- the target branch name does not already exist locally or on `origin`.

The target branch name is deterministic:

```text
<current-branch>-followup-<short-head-sha>
```

For example:

```text
juicyrebel/test-workflow-artifact-names-followup-caad43f
```

The wrapper creates and switches to that branch locally. The existing guarded
`push-current` operation then pushes the new current branch. The existing guarded
GitHub `create-current` operation then creates the PR from the fresh branch
without adding broad `--head` permissions.

## Workflow Integration

When the GitHub operator reports that an existing PR for the current branch is
`MERGED` and `pr_head != current_head`, the supervisor should:

1. confirm the tree is clean and current with `origin/main`;
2. dispatch `git-integrator` to create/switch to the deterministic follow-up
   branch;
3. dispatch `git-integrator` to push the new current branch;
4. dispatch `github-operator` to create/queue the PR using the normal
   current-branch flow;
5. poll PR/merge-queue state as usual.

Any wrapper refusal remains a true `HUMAN_DECISION_REQUIRED` state with wrapper
evidence.

## Validation

Add unit/static tests for:

- deterministic branch-name derivation;
- refusal on dirty tree;
- refusal from `main` or detached `HEAD`;
- refusal when target branch already exists locally or remotely;
- successful creation/switch command shape;
- permission-policy allowance for only the new guarded wrapper command;
- workflow documentation mentioning the merged-old-PR recovery path.

No application runtime behavior changes are expected.
