# Fast-Dev Local Main Wrap-Up Design

## Purpose

The first `fast-dev` implementation intentionally optimized interactive local
iteration while delegating final integration to the strict `supervisor`. That is
safe for feature-branch work, but it leaves one important workflow underspecified:
the human wants to use `fast-dev` on a local `main` branch for quick vertical
slices, then have the system package that reviewed local work into the same safe
PR and merge-queue path used by strict supervisor work.

This design adds explicit local-main wrap-up rules so `fast-dev` can support
interactive development on local `main` without ever pushing directly to
`origin/main` or bypassing review.

## Goals

- Preserve fast interactive development on a local `main` branch.
- Preserve hierarchical review loops during development: every repository
  mutation still routes through `implementer` -> `reviewer` -> pass.
- Preserve proper project commits for accepted changes.
- Convert reviewed local-main work into a feature branch before integration.
- Reuse the strict supervisor finishing flow for final validation, PR creation,
  auto-merge, and merge-queue polling.
- Support vertical-slice handoff from `fast-dev` to strict supervisor for larger
  follow-on work.

## Non-Goals

- Do not allow direct pushes to `origin/main`.
- Do not allow `fast-dev` to run raw privileged Git or GitHub commands.
- Do not replace the strict supervisor as final integration authority.
- Do not rebase, reset, force-push, clean, or delete branches.
- Do not automatically merge local `main` into remote `main`.
- Do not weaken the existing implementer/reviewer gate.

## Design Principles

### Local `main` is a workspace, not an integration target

When `fast-dev` is used on local `main`, local commits are treated as a working
vertical slice. Wrap-up converts that slice to a named feature branch before any
push or PR action. The system must never push local `main` directly.

### Wrap-up is capability-routed

`fast-dev` may coordinate the handoff, but branch status, branch creation,
fetching, safe merging, pushing, and PR/merge-queue actions continue to use the
existing capability agents:

- `git-integrator` for fetch/status, safe merge from `origin/main`, deterministic
  branch creation, and push;
- `github-operator` for PR creation, protection checks, auto-merge, and
  merge-queue polling;
- `pr-recovery-operator` only for existing stale merged PR recovery paths.

### The strict supervisor owns finish and integration

When the user asks `fast-dev` to wrap up, finish, PR, or merge queue the work,
`fast-dev` hands off to the strict supervisor/finishing flow. The supervisor must
detect whether the current branch is local `main` and, if so, create or request a
feature-branch conversion before continuing.

### Vertical slices are first-class handoffs

For larger features, `fast-dev` can produce a reviewed vertical slice and a
handoff note. The handoff note lets the strict supervisor review the design and
architecture before expanding the slice through the normal spec/plan/SDD flow.

## Local Main Wrap-Up Behavior

### Detection

Before final integration, the strict supervisor/finishing flow must identify the
current branch:

- If the current branch is not `main`, use the existing branch finishing flow.
- If the current branch is `main`, do not push or create a PR from `main`.
- If local `main` is clean and has no local commits beyond `origin/main`, report
  that there is no local work to wrap up.
- If local `main` has local commits beyond `origin/main`, convert those commits
  into a feature branch before integration.

The comparison must use current `origin/main`, not stale local `main` state.

### Feature branch conversion

When local `main` contains reviewed local commits, wrap-up creates a deterministic
feature branch from the current local `main` `HEAD` before any push:

```text
fast-dev/local-main-<short-head-sha>
```

Topic support is deferred and out of scope for this workflow. The conversion uses
the dedicated `create-local-main-wrapup-branch` Git integration wrapper; it does
not reuse the existing follow-up branch capability.

The conversion must refuse when:

- the worktree is dirty;
- the current branch is detached;
- the target branch already exists locally or on origin;
- the target branch name fails safe branch policy;
- local `main` lacks local commits to wrap;
- current `origin/main` cannot be fetched or compared.

### Current-base handling

After conversion, the feature branch must be evaluated against current
`origin/main`:

- If `origin/main` is an ancestor of the feature branch, continue to validation.
- If the feature branch is behind current `origin/main`, safe-merge
  `origin/main` through `git-integrator`.
- Any merge conflicts or repository fixes after the merge route through
  `implementer` -> `reviewer` -> pass before validation continues.
- Rebase and force-push remain forbidden.

### Validation and PR integration

Once the feature branch is clean and current with `origin/main`, the normal
strict finishing flow continues:

1. Run required final validation for the changed surface.
2. Push the feature branch through `git-integrator`.
3. Create or update a PR targeting `main` through `github-operator`.
4. Enable auto-merge or enter merge queue when branch protection allows it.
5. Poll until `mergedAt` is present or an actionable blocker is established.

Merge queue remains the post-PR freshness authority.

## Fast-Dev Development Loop Additions

`fast-dev` should explicitly support interactive local-main development while
remaining coordinator-only:

- It may work on local `main` when the user chooses that workflow.
- It should remind the user that final wrap-up will convert local-main commits to
  a feature branch and PR, not push `main`.
- It still dispatches `implementer` for each mutation and `reviewer` for each
  accepted change.
- It should encourage coherent local commits after reviewer pass.
- It must escalate to strict supervisor for wrap-up, final validation, branch
  conversion, PR creation, merge queue, or any unsafe branch state.

## Vertical Slice Handoff

When the user wants strict supervisor to expand on a fast-dev vertical slice,
`fast-dev` should prepare a concise handoff note instead of guessing the next
architecture step. The note should include:

- branch or commit range;
- problem solved by the vertical slice;
- current abstraction ownership;
- validation evidence;
- design risks already avoided;
- known limits and proposed expansion seams;
- whether the slice is ready for PR integration or should become input to a new
  strict supervisor spec/plan.

The strict supervisor may then use the handoff as context for brainstorming and
writing-plans, preserving clean design before broadening the work.

## Configuration and Documentation Changes

Implementation should update:

- `.opencode/agents/fast-dev.md` with local-main development and wrap-up
  escalation rules.
- `.opencode/agents/supervisor.md` with finishing classification for local
  `main` conversion before integration.
- Git integration wrapper docs/tests/scripts if a new bounded local-main branch
  conversion action is needed.
- `docs/dev/features/opencode-agent-workflow.md` with the local-main wrap-up and
  vertical-slice handoff behavior.

Because `.opencode/**`, scripts, tests, and workflow docs affect agent behavior,
implementation must route through `implementer` -> `reviewer` -> pass.

## Validation Strategy

- Run `make opencode-check` after `.opencode/**` or capability-wrapper changes.
- Add or update focused tests for any new Git integration wrapper action.
- Use focused text checks to confirm local `main` is never pushed directly and
  that wrap-up language routes to feature branch + PR.
- Use `git diff --check` for documentation/config changes.
- PR CI remains the authoritative final integration gate.

## Acceptance Criteria

- `fast-dev` documents that local-main work wraps into a feature branch, never a
  direct `origin/main` push.
- Strict supervisor finishing documentation detects local `main` and converts it
  before push/PR integration.
- Any new branch conversion capability is bounded, tested, and refuses dirty,
  detached, duplicate-branch, stale-unknown, and no-local-work states.
- Final integration still uses strict finishing validation, PR creation, and
  merge-queue polling.
- The workflow supports a fast-dev vertical slice handoff to strict supervisor
  for larger features.
