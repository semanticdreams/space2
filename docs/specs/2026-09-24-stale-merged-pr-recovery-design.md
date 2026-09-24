# Stale merged PR recovery for reused OpenCode sessions

## Context

OpenCode finishing normally pushes the current branch and asks the GitHub PR
wrapper to create or reuse a pull request. In reused sessions, the same branch
name may already have a merged PR from earlier work. When new follow-up work is
committed and pushed to that branch, GitHub still resolves the branch name to the
old merged PR. The current PR wrapper detects that the old PR head differs from
the current branch head and returns `human_decision_required`.

The manual recovery is reliable but repetitive: create a deterministic follow-up
branch from the current head, push it, then create the PR from that fresh branch.
We want this recovery to happen automatically while preserving the repository's
capability boundaries.

## Goal

Add a guarded stale-merged-PR recovery path for OpenCode finishing. When the PR
wrapper reports an existing merged PR whose head does not match current `HEAD`,
OpenCode should be able to dispatch one explicit recovery capability that:

1. verifies the working tree is clean and current with `origin/main`;
2. creates a deterministic follow-up branch from the current head;
3. pushes that fresh branch;
4. creates a new PR for the fresh branch;
5. returns structured evidence for the supervisor to continue normal auto-merge
   and merge-queue polling.

## Non-goals

- Do not hide branch creation or pushing inside the normal GitHub-only
  `create-current` PR operation.
- Do not broaden Git or GitHub permissions.
- Do not rebase, force-push, reset, delete branches, or push directly to `main`.
- Do not recover ambiguous stale PR states such as open PRs with mismatched
  heads, closed-unmerged PRs, matching-head merged PRs, dirty worktrees, stale
  bases, or existing follow-up branch targets.
- Do not move auto-merge or merge-queue polling into the recovery wrapper.

## Design

### Explicit recovery capability

Introduce a dedicated recovery wrapper command, exposed through a dedicated
capability agent, for exactly this condition:

- the normal PR creation attempt returns `human_decision_required`;
- the evidence says an existing PR is `MERGED`;
- `pr_head` and `current_head` are both present;
- `pr_head != current_head`.

All other PR-wrapper refusals remain human-decision-required.

The recovery wrapper should compose existing guarded operations rather than
duplicate broad Git/GitHub behavior:

- inspect the current branch and base status through the existing git integration
  wrapper functions;
- create the follow-up branch through the existing deterministic follow-up branch
  logic;
- push the current branch through the existing push logic;
- call the existing PR creation logic again from the fresh branch.

The deterministic branch name remains:

```text
<source-branch>-followup-<short-current-head-sha>
```

This makes repeated recovery attempts idempotent enough to fail safely if the
target branch already exists instead of inventing unbounded branch names.

### Capability boundaries

Normal roles stay narrow:

- `git-integrator` owns current-branch Git status, safe merge, branch creation,
  and push decisions.
- `github-operator` owns GitHub PR creation, protection checks, auto-merge, and
  merge-queue polling.
- the new recovery capability may orchestrate the single stale-merged-PR recovery
  case and must expose only one exact command.

No agent gets raw `git`, raw `gh`, wildcard branch operations, or shell access as
part of this change.

### Supervisor flow

During finishing, if `github-operator` reports stale merged PR evidence for a
current branch, the supervisor should dispatch the recovery capability instead of
stopping for the human. If recovery succeeds and returns a new PR URL, the
supervisor resumes the existing GitHub finishing path: enable auto-merge/queue
and poll until merged or an actionable blocker appears.

If recovery refuses at any safety gate, the supervisor reports
`HUMAN_DECISION_REQUIRED` with the wrapper evidence.

## Error handling

Recovery must fail closed with structured evidence when:

- the worktree is dirty;
- the current branch is detached or `main`;
- current `HEAD` has not incorporated current `origin/main`;
- the derived follow-up branch is invalid;
- the derived branch already exists locally or remotely;
- branch creation, push, or final PR creation fails;
- the stale PR evidence does not exactly match the merged/different-head case.

## Testing

Focused tests should prove:

- normal successful PR creation passes through without recovery;
- non-recovery refusals pass through unchanged;
- stale merged PR evidence triggers the sequence: status check, follow-up branch
  creation, push, fresh PR creation;
- each safety gate refuses before later mutations;
- the normal PR wrapper still returns `human_decision_required` for stale merged
  PRs and does not mutate Git state;
- capability permission checks allow only the exact recovery command and reject
  broad Git/GitHub commands;
- workflow documentation names the automatic recovery behavior and restart
  requirement for `.opencode/**` changes.
