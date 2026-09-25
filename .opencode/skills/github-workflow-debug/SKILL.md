---
name: github-workflow-debug
description: Debug a GitHub Actions workflow end-to-end using a temporary branch, temporarily enable the workflow for that branch, commit/push/poll in 100-second intervals until green, review and simplify the resulting fix commits, then squash-merge the final result onto a dedicated PR branch, push it, and create a GitHub PR.
---

# GitHub Workflow Debug Loop

Use this skill when the user wants a GitHub Actions workflow fixed autonomously in CI, not just locally.

Use the bundled helper first:
- Script: `.opencode/skills/github-workflow-debug/scripts/gh-workflow-debug.sh`
- It provides deterministic branch naming, remote branch SHA checks, run lookup by workflow/branch/SHA, failed-job lookup, and 100-second polling.

This skill is for the full loop:
- create a throwaway branch automatically
- temporarily enable the target workflow on that branch
- push and poll every `100s`
- fix failures in a commit/push/poll loop until green
- review all workflow-fix commits for correctness, cleanliness, and simplification
- if worthwhile, improve and re-run the loop until green again
- land the final result on a dedicated PR branch, push it, and create a GitHub PR
- delete the throwaway branch locally

## Completion Contract (non-negotiable)

- **Never return a final answer while any workflow run is pending.** If a run
  is queued, in_progress, or waiting, continue polling — do not summarize,
  do not suggest the user check later, do not produce a "Remaining Tasks"
   list. The skill is not done until the debug-branch CI is green, reviews
   pass, and a final squash commit exists on a dedicated PR branch, is pushed, and a GitHub PR URL has been returned.
- Use `gh-workflow-debug.sh wait-run` as the default polling mechanism.
  It blocks until the run completes (default 2h timeout) and returns the
  conclusion.
- The only legitimate stop conditions are:
  - Final squash commit is created on the PR branch, reviewed, pushed, and a PR URL has been returned.
  - A permission prompt requires human approval.
  - The `requires_human` escalation path is triggered.
- **"I'll let the user check CI later" is a violation.** Poll now.
- When calling `wait-run`, use a bash tool timeout that exceeds the
  `--timeout` value (e.g. `--timeout 7200` with bash timeout 7500000ms)
  so the shell is not killed before the helper finishes.

## Inputs to establish up front

- Workflow file or workflow name, for example `.github/workflows/test.yml`
- Base branch: default to `main`
- Temporary branch name:
  - `opencode/workflow-debug/<workflow-stem>-<utc-timestamp>`

If the workflow target is ambiguous, ask once before doing any branch work.

## Safety rules

- Use non-interactive git commands only.
- Do not amend or force-push unless the user explicitly asks.
- Keep the throwaway branch isolated from `main` until the final squash.
- Do not leave the throwaway branch in workflow triggers on the final landed commit.
- Use `wait-run` to poll every 100s — the helper handles the loop.
- Prefer `gh run` for status/log inspection.
- Always identify workflow runs by throwaway branch and, when possible, by the pushed commit SHA. Do not assume the latest run in the repo is the right one.

## Trigger enablement

Before the first debug push, dispatch the **implementer** subagent to edit the target workflow so the throwaway branch will trigger it. Give the implementer the workflow file, throwaway branch name, and the trigger shape to preserve. After implementer commits, verify with `git log --oneline -1` before pushing.

Preferred approach:
- If the workflow already has `on.push.branches`, add the throwaway branch to that list.
- If the workflow only has tag-based `push` triggers, add a temporary branch entry for the throwaway branch while preserving the existing tag trigger.
- If the workflow already has `workflow_dispatch`, keep it; do not rely on it for the main loop unless push triggering is impossible.

Common shapes in this repo:
- `push.branches` only:
  - add the throwaway branch under `on.push.branches`
- `workflow_dispatch` plus `push.tags`:
  - keep `workflow_dispatch`
  - preserve `push.tags`
  - add `push.branches` with the throwaway branch instead of replacing `tags`
- `push.branches: [main]`:
  - expand it to a multi-line list and add the throwaway branch alongside `main`

The throwaway-branch trigger change is temporary and must not survive the final squash onto the PR branch.

## Main loop

1. Create and switch to the throwaway branch from `main`.
   - Prefer: `.opencode/skills/github-workflow-debug/scripts/gh-workflow-debug.sh branch-name <workflow>`
2. Dispatch **implementer** to add the temporary workflow trigger change, then verify the implementer commit with `git log --oneline -1`.
3. Push the verified implementer commit. (The implementer already committed in step 2; do not create an additional commit.)
   - Verify the remote branch SHA if needed:
     - `.opencode/skills/github-workflow-debug/scripts/gh-workflow-debug.sh remote-branch-sha <throwaway-branch>`
4. Poll the workflow until it completes. Use `wait-run` — it blocks, so you
   do not need a manual `sleep 100` loop. Prefer filtering by the throwaway
   branch and the pushed commit SHA:
     - `.opencode/skills/github-workflow-debug/scripts/gh-workflow-debug.sh wait-run --workflow <workflow> --branch <throwaway-branch> --sha <pushed-sha> --timeout 7200 --json`
     - When invoking `bash`, set `timeout` to at least `7500000` milliseconds
       so the shell outlives the helper's `--timeout`.
      - If the bash call times out but the workflow may still be running,
        re-check with `latest-run-id` and restart polling — do not summarize
        or stop.
      - If no run appears after a reasonable wait, treat that as a workflow-trigger failure:
        - verify the workflow trigger edit (check `git log --oneline` on the throwaway branch)
        - verify the push reached the remote branch (use `remote-branch-sha`)
        - if the trigger is correct but no run appeared, the problem may be a
          workflow file syntax error or YAML parse issue: dispatch
          **implementer** to fix it, verify the commit, then push and restart
          polling
        - if the trigger itself is wrong, dispatch **implementer** to correct
          it, verify the commit, then push and restart polling
5. If it fails:
    - inspect the failing job log
    - prefer selecting the first failed job deterministically:
      - `.opencode/skills/github-workflow-debug/scripts/gh-workflow-debug.sh first-failed-job-id --run-id <run-id>`
    - if the failed job is `build-windows`, `test-windows`, or
      `build-windows-installer` and is not obviously CI infrastructure-only,
      dispatch `windows-ci-reproducer` before the next push; obtain local Linux
      cross-build + Wine reproduction evidence before pushing another fix
    - if `windows-ci-reproducer` evidence says prerequisites are missing, run
      guarded `setup-host` once through `windows-ci-reproducer`, then rerun
      reproduction; do not use raw setup commands
    - identify the first real blocker
    - dispatch the **implementer** subagent with a focused fix instruction for any required file change, including workflow files, source, tests, config, package/build files, or scripts. After implementer commits, verify (`git log --oneline -1`), then push and go to step 4
6. If it passes:
   - proceed to the simplification pass (below)

### Simplification pass

Clean up the throwaway branch as if preparing a final PR:

- remove brittle or overly specific workarounds if a cleaner general fix is available
- collapse repeated patterns into the right shared layer
- prefer environment/setup fixes over per-port/per-call hacks when the problem is systemic
- verify every retained commit contributed to the final design
- remove dead attempts and partial work from the final landed result

For any simplification that changes repository files — workflow, source, test, config, package/build files, or scripts — dispatch the **implementer** subagent with a focused instruction. After implementer commits, verify (`git log --oneline -1`), then push.

If changes were made during simplification, re-enter the commit/push/poll
loop until green. If no simplification was needed, proceed to reviewer
verification.

### Reviewer verification

Before landing, dispatch the **reviewer** subagent in CI DEBUG REVIEW MODE
for independent verification.

1. Ensure the CI artifact directory exists (keeps review files out of git):
   ```
   .opencode/skills/github-workflow-debug/scripts/ci-artifact-dir.sh
   ```

2. Generate a review package of the full branch diff:
   ```
   .opencode/skills/subagent-driven-development/scripts/review-package \
     /dev/null <merge-base> <throwaway-branch> .superpowers/sdd/ci-review-pack.diff
   ```
   (The 4-arg form writes to the explicit path; `/dev/null` satisfies the
   required plan-file argument without pulling in SDD workspace machinery.)

3. Write a short fix summary for the reviewer:
   - what CI failures were observed (include root causes)
   - what fixes were applied and why
   - what simplification was done
   - CI evidence: the last green run's conclusion and any relevant failure log excerpts

4. Dispatch the **reviewer** with CI DEBUG REVIEW MODE:
   ```
   You are reviewing CI debug fixes using CI DEBUG REVIEW MODE.

   Workflow: [WORKFLOW_FILE]
   Throwaway branch: [BRANCH_NAME]
   Review package (full branch diff): .superpowers/sdd/ci-review-pack.diff
   Fix summary: [summary from step 3]

   Note: the branch diff includes a temporary workflow trigger for the
   throwaway branch. This is expected — it will be removed in the final
   staged-review before landing. Do not flag it as a finding.
   ```

5. Handle the result:
   - **pass** → proceed to Final landing
   - **candidates_found** → dispatch **implementer** to fix the findings,
     including workflow findings; after implementer commits, push, poll until
     green, then re-review
   - **requires_human** → present the findings to the human; do not land

## Polling commands

Typical commands:

```bash
.opencode/skills/github-workflow-debug/scripts/gh-workflow-debug.sh branch-name .github/workflows/test.yml
.opencode/skills/github-workflow-debug/scripts/gh-workflow-debug.sh remote-branch-sha <branch>
.opencode/skills/github-workflow-debug/scripts/gh-workflow-debug.sh latest-run-id --workflow test.yml --branch <branch> --sha <sha>
.opencode/skills/github-workflow-debug/scripts/gh-workflow-debug.sh first-failed-job-id --run-id <run-id>
.opencode/skills/github-workflow-debug/scripts/gh-workflow-debug.sh wait-run --workflow test.yml --branch <branch> --sha <sha> --json
gh run list --workflow <workflow-file> --limit 5
gh run view <run-id> --json jobs
gh run view <run-id> --job <job-id> --log
```

Bias toward:
- checking the latest run for the throwaway branch
- matching the run to the pushed commit SHA when multiple runs are plausible
- focusing on the first failed job
- reading the narrowest useful log before changing code

## Commit discipline on the throwaway branch

- Make small, single-purpose commits during debugging.
- Use clear `ci` or `fix(ci)` style subjects.
- If commit wording matters, also use the local `git-commit` skill.
- During the review/simplification phase, keep committing normally on the throwaway branch; do not try to curate history there.

The throwaway branch is allowed to have many debugging commits. `main` is not.

## Final landing through a PR branch

Once reviewer verification passes (status `pass`):

1. Fetch `origin/main`.
2. Create or switch to `opencode/workflow-debug-pr/<workflow-stem>-<utc-timestamp>` from `origin/main`; do not require checking out local `main`.
3. Squash-merge the throwaway debug branch into the final PR branch.
4. Dispatch **implementer** to remove the temporary throwaway-branch workflow
   trigger from the workflow file while keeping all real workflow/build/test
   fixes. Instruct implementer to stage the result. Verify the staged diff
   before continuing.

5. Generate the staged diff and dispatch the reviewer for staged verification:
   ```
   .opencode/skills/github-workflow-debug/scripts/ci-artifact-dir.sh
   git diff --staged > .superpowers/sdd/ci-staged.diff
   ```
   Dispatch the reviewer for staged review (CI DEBUG REVIEW MODE):
   ```
   You are performing a CI DEBUG REVIEW. The branch fixes were previously
   reviewed and approved (see branch review package). Confirm that the staged
   squash-commit diff matches the approved fixes minus the temporary workflow
   trigger.

   Branch review package (approved): .superpowers/sdd/ci-review-pack.diff
   Staged squash diff: .superpowers/sdd/ci-staged.diff

   Check: no debug scaffolding remains in the staged diff, no real fixes
   were dropped from the squash, and the only difference from the approved
   branch diff is the trigger removal.
   ```
   - **pass** → proceed to step 6
   - **candidates_found** → assess the findings:
     - If the issues are mechanical (missing trigger removal, leftover debug
       scaffolding, dropped fix in squash): dispatch **implementer** to fix the
       staged diff, then re-review.
     - If the issues are substantive (a source, test, build, or workflow
       behavior problem): abort the landing, return to the throwaway branch,
       dispatch **implementer** to fix, verify the commit, push, poll until
       green, then restart the full reviewer verification step.

6. On staged-review pass, create exactly one final squash commit on the PR
   branch. Use the `git-commit` skill when available.

7. Verify no `.superpowers/sdd/ci-*` artifacts are staged or tracked and the
   final workflow file no longer includes the temporary debug branch trigger.

8. Push with:
   ```
   git push origin HEAD:refs/heads/<final-pr-branch>
   ```

9. Create the PR with:
   ```
   gh pr create --base main --head <final-pr-branch> --fill
   ```

10. Return the PR URL plus an optional cleanup command for the remote debug
    branch:
    ```
    PR landed: <pr-url>
    To clean up the remote debug branch: git push origin --delete <throwaway-branch>
    ```

Direct pushes to `main` are branch-protection incompatible for this repo. The
final workflow-debug fix must land through a PR.

## Cleanup

After the final PR branch commit and PR are created:

- delete the throwaway branch locally: `git branch -D <throwaway-branch>`
- the remote debug branch (`origin/<throwaway-branch>`) remains for now;
  include the deletion command in the final report

## Final verification

Before reporting done:

- confirm the throwaway branch no longer exists locally
- confirm the workflow file on the final PR branch no longer includes the throwaway branch in its triggers
- confirm the final single commit on the PR branch contains all intended fixes
- confirm no CI review artifacts (`.superpowers/sdd/ci-*`) are staged or tracked
