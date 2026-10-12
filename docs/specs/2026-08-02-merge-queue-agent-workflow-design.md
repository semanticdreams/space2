# Merge Queue Agent Workflow Design

## Context

Space uses Orca to run multiple OpenCode sessions in separate worktrees. The
repository has moved from `https://github.com/semanticdreams/space` to
`https://github.com/semanticdreams/spacecore` so it can be organization-owned and
eligible for GitHub merge queue. Repository references now need to point at the
new canonical URL.

Each session currently finishes by validating against `origin/main`, opening a
pull request, and enabling auto-merge. That works for one branch, but concurrent
PRs become stale after the first one lands. The current remedy is manual branch
updates, which rerun required checks repeatedly and can turn a batch of N ready
PRs into roughly 1 + 2 + ... + N CI runs.

Repository inspection after the transfer found that `main` is still governed by
a repository ruleset rather than classic branch protection. The ruleset still
requires pull requests and a required status check named `test`, with strict
up-to-date status checks enabled. It does not currently expose a merge-queue
rule through the branch rules API. This strict current-base requirement is the
source of the manual update loop until merge queue is enabled.

## Explored Approaches

### Approach A: Worker sessions keep updating until merged

Each OpenCode session would continue after PR creation, merge `origin/main` when
the PR becomes stale, wait for checks, and repeat until GitHub merges it.

This preserves safety but amplifies CI usage and keeps many agent sessions open
doing low-value polling. It also creates poor behavior under concurrent work:
later PRs pay for every earlier PR that lands.

### Approach B: Native GitHub merge queue

Agents validate against current `origin/main` before initial PR creation, then
handoff freshness to GitHub's merge queue. Once a PR is open, green, and queued,
agents stop chasing `origin/main`. The queue creates merge-group candidates and
runs required checks against the proposed merge result.

This preserves branch protection and required checks while removing per-agent
stale-branch loops. It still runs integration checks, but those checks are owned
by one queue instead of duplicated by every worker branch.

### Approach C: Dedicated merge steward

A single long-running steward agent would serialize ready PRs, updating and
merging one at a time.

This can remove manual labor without GitHub merge queue, but it is custom
orchestration. It still reruns CI once per PR after each mainline movement and
adds a bespoke operational component.

### Approach D: Batch integration branch

A bot would merge multiple ready branches into an integration branch, run CI
once, and merge the batch if green.

This can minimize CI runs, but weakens per-PR protection semantics, complicates
failure attribution, and makes conflict repair harder. It is too much custom
process for the current pain point.

## Recommended Direction

Use Approach B: GitHub merge queue as the post-PR integration freshness gate.

The agent contract becomes:

1. Before final validation and initial PR creation, fetch `origin` and make sure
   the branch has accounted for current `origin/main`.
2. Run required validation on that current-base branch.
3. Push the branch, open the PR, and enable auto-merge/add it to the merge
   queue.
4. After the PR is open and queued, do not update the branch solely because
   another PR merged to `main`.
5. Resume work only when GitHub reports an actionable blocker: merge conflict,
   merge-group required-check failure, missing merge-queue protection, missing
   permissions, or another queue error.

## Design

### Architecture

- Repository URL references point to the canonical organization-owned URL:
  `https://github.com/semanticdreams/spacecore`.
- GitHub owns post-PR freshness through a merge queue on `main`.
- OpenCode workers remain responsible for implementation, review, commits,
  pre-PR current-base validation, and PR creation.
- Repository policy in `AGENTS.md` documents the split between pre-PR freshness
  and post-PR merge-queue freshness.
- The finishing workflow skill instructs agents not to safe-merge `origin/main`
  after PR creation merely because `main` advanced.
- Automation skills that create auto-merge PRs use the same rule and verify that
  merge queue protection is available before relying on it.
- Developer documentation explains the workflow to humans using Orca/OpenCode.

### GitHub Configuration Required

A GitHub repository admin needs to update the `main` branch ruleset:

- Enable **Require merge queue** for `main`.
- Keep pull requests required.
- Keep the required status check named `test`.
- Ensure the `test` check runs for merge-queue merge groups. If `test` is a
  GitHub Actions workflow, its workflow trigger must include `merge_group` in
  addition to the existing pull request/push triggers.
- Replace or relax any rule that forces every PR branch to be updated after
  `main` moves if that rule blocks queue entry. The merge queue should be the
  freshness gate, not repeated branch-head updates.
- Keep direct pushes to `main` blocked.

The repository has no `.github/workflows/**` files in this checkout, so this
design does not include workflow-file edits. If the required `test` check is
configured outside this repository or generated elsewhere, that external system
must support merge-group checks.

### Agent Behavior

Before PR creation, the existing strict behavior remains: agents fetch
`origin/main`, merge it safely when permitted if the branch is behind, route any
conflicts or fixes through `implementer` → `reviewer` → pass, and rerun required
validation from a clean tree.

After PR creation, the behavior changes: agents do not keep updating stale PR
branches solely because `origin/main` advanced. If merge queue is enabled, the
queue's merge-group checks are the evidence that the PR can integrate with the
current base.

If the queue reports a conflict or required-check failure, the agent treats that
as a normal debugging/repair task: invoke `systematic-debugging`, identify root
cause or limits of evidence, route repository fixes through `implementer` →
`reviewer` → pass, commit, rerun validation from current `origin/main`, and
requeue.

### Error Handling

- If merge queue is not enabled or cannot be verified, agents report
  `HUMAN_DECISION_REQUIRED` with the exact GitHub setting needed instead of
  entering a stale-branch polling loop.
- If queue permissions are missing, agents report the permission blocker and do
  not bypass branch protection.
- If merge-group `test` does not run or never reports, agents report that the
  GitHub check configuration must be updated.
- Rebase and force-push remain forbidden unless the human explicitly requests
  them.

### Testing

Validation is documentation/configuration focused:

- Inspect GitHub branch rules and capture whether merge queue is enabled.
- Focused text review of `AGENTS.md`, the finishing workflow, automation skills,
  and OpenCode workflow docs for merge-queue wording.
- `git diff --check` on changed documentation and `.opencode/**` files.
- Docs build with `cd docs && npm run docs:build` for developer documentation.
- Skill/config changes go through `implementer` → `reviewer` → pass; the
  supervisor does not directly edit `.opencode/**` or `AGENTS.md`.

## Scope

In scope:

- Updating tracked references from `semanticdreams/space` to
  `semanticdreams/spacecore` where they refer to the canonical repository, release
  page, Actions badges, discussions, source links, clone URLs, or test fixtures.
- Updating repository policy and docs for merge-queue-based PR integration.
- Updating OpenCode finishing and automation instructions so agents stop after
  queue handoff rather than chasing stale PR heads.
- Documenting the required GitHub branch ruleset changes.

Out of scope:

- Creating a custom merge steward.
- Creating an integration-train branch.
- Editing production runtime code, Fennel files, or tests.
- Editing GitHub Actions workflows unless the human confirms where the required
  `test` check is defined and that workflow needs merge-group triggers.
- Rebasing or force-pushing agent branches.

## Self-Review Notes

- No placeholders remain.
- The design keeps pre-PR validation strict while moving post-PR freshness to
  the merge queue.
- The GitHub settings that require human/admin action are explicit.
- The design avoids direct supervisor edits to `.opencode/**` and `AGENTS.md`.
