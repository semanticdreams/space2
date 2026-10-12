# Merge Queue Agent Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update Space's repository references for `semanticdreams/spacecore` and teach the OpenCode finishing workflows to rely on GitHub merge queue after PR creation.

**Architecture:** This is a repository-policy, documentation, and process-configuration change. Tracked URLs move to the new canonical GitHub repository, while pre-PR validation remains strict and post-PR freshness moves to GitHub merge queue. OpenCode config/skill edits must be implemented by subagents and reviewed before commit.

**Tech Stack:** Markdown, OpenCode repo-local agents/skills, GitHub rulesets, GitHub CLI/API, Python test fixtures, Space Fennel test fixtures, VitePress docs.

## Global Constraints

- Canonical repository URL: `https://github.com/semanticdreams/spacecore`.
- Canonical SSH repository URL: `git@github.com:semanticdreams/spacecore.git`.
- Historical canonical repository references to `https://github.com/semanticdreams/space`, `git@github.com:semanticdreams/space.git`, and `semanticdreams/space` must be updated when they point at the active Space repository, releases, Actions, discussions, source files, clone instructions, badges, or test fixtures.
- The local `origin` remote has already been updated to `https://github.com/semanticdreams/spacecore.git` for this worktree.
- Keep pre-PR behavior strict: before final validation and initial PR creation, agents fetch `origin` and verify the branch has accounted for current `origin/main`.
- Change post-PR behavior: once a PR is open and queued, agents must not update the PR branch solely because `origin/main` advanced.
- GitHub merge queue is the post-PR freshness gate. Queue conflicts or required-check failures trigger `systematic-debugging` and reviewed fixes.
- Rebase and force-push remain forbidden unless the human explicitly requests them.
- `.opencode/**`, `AGENTS.md`, source, and test edits must go through `implementer` → `reviewer` → pass before commit.
- Fennel-facing validation uses `space-fennel`: compile check first, constraints second, focused Fennel tests third, broader suite last when required.
- Test/runtime validation uses `space-testing-runtime` hygiene: `SKIP_KEYRING_TESTS=1`, `XDG_DATA_HOME=/tmp/space/tests/xdg-data`, `SPACE_DISABLE_AUDIO=1`, and `SPACE_ASSETS_PATH=$(pwd)/assets` where applicable.
- HUMAN_DECISION_REQUIRED: a GitHub repository admin must enable **Require merge queue** for `main` and ensure the required `test` check runs for merge-group candidates.

---

### Task 1: Update Canonical Repository References

**Files:**
- Modify: `README.md`
- Modify: `docs/user/quick-start.md`
- Modify: `docs/dev/index.md`
- Modify: `docs/dev/building.md`
- Modify: `docs/dev/repository-workbench.md`
- Modify: `docs/dev/notes/test-harness-cleanup.md`
- Modify: `docs/dev/notes/sub_world.md`
- Modify: `docs/dev/notes/depth-precision-long-distance.md`
- Modify: `docs/dev/notes/link-entities.md`
- Modify: `docs/dev/notes/terrain-physics-debugging.md`
- Modify: `docs/dev/notes/sandbox-interaction-toolbar.md`
- Modify: `docs/dev/notes/string-entities.md`
- Modify: `docs/plans/2026-07-25-readme-slimdown.md`
- Modify: `docs/plans/2026-07-31-weekly-agent-workflow-automation.md`
- Modify: `scripts/tests/test_weekly_agent_workflow_analyzer.py`
- Modify: `assets/lua/tests/test-repo-remote.fnl`
- Test: focused repository-reference grep
- Test: focused Python/Fennel fixture checks where practical

**Interfaces:**
- Consumes: canonical URL `https://github.com/semanticdreams/spacecore` and SSH URL `git@github.com:semanticdreams/spacecore.git`
- Produces: tracked docs/tests/scripts no longer reference the old canonical `semanticdreams/space` repository

- [ ] **Step 1: Reproduce the stale-reference baseline**

  Run:

  ```bash
  rtk rg -n 'github\.com/semanticdreams/space|semanticdreams/space\.git|git@example\.com:semanticdreams/space\.git|semanticdreams/space(\b|/)' README.md docs scripts assets/lua/tests/test-repo-remote.fnl
  ```

  Expected before edits: matches include `README.md`, docs pages/notes/plans, `scripts/tests/test_weekly_agent_workflow_analyzer.py`, and `assets/lua/tests/test-repo-remote.fnl`.

- [ ] **Step 2: Replace HTTPS GitHub links**

  In the files listed above, replace active repository links beginning with:

  ```text
  https://github.com/semanticdreams/space
  ```

  with:

  ```text
  https://github.com/semanticdreams/spacecore
  ```

  This covers Actions badges, workflow links, release links, discussion links, source-file links, and README references.

- [ ] **Step 3: Replace SSH and fixture remote URLs**

  Replace:

  ```text
  git@github.com:semanticdreams/space.git
  git@example.com:semanticdreams/space.git
  ```

  with:

  ```text
  git@github.com:semanticdreams/spacecore.git
  git@example.com:semanticdreams/spacecore.git
  ```

  Preserve the `git@example.com:` host in test fixtures that intentionally use a fake host; only the owner/repo path changes.

- [ ] **Step 4: Replace owner/repo text references**

  Replace user-facing source labels and owner/repo strings that refer to the active repository:

  ```text
  semanticdreams/space
  ```

  with:

  ```text
  semanticdreams/spacecore
  ```

  Do not rename the product, executable, package artifacts, domain `spaceui.org`, or asset filenames that intentionally contain `space` as the product name.

- [ ] **Step 5: Verify stale references are gone**

  Run:

  ```bash
  rtk rg -n 'github\.com/semanticdreams/space([^2]|$)|semanticdreams/space\.git|git@example\.com:semanticdreams/space\.git|semanticdreams/space(\b|/)' README.md docs scripts assets/lua/tests/test-repo-remote.fnl
  ```

  Expected: no matches for the old repository slug. If any match is intentionally historical and should remain, document the exact file and reason in the implementer handoff.

- [ ] **Step 6: Run focused fixture validation**

  Run the Python analyzer test if the local test dependencies are available:

  ```bash
  python3 -m pytest scripts/tests/test_weekly_agent_workflow_analyzer.py
  ```

  For the touched Fennel test fixture, run the narrow compile check first:

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-repo-remote.fnl
  ```

  If `./build/space` is unavailable, report that the Fennel compile check was not runnable and defer to broader validation after build availability is restored.

---

### Task 2: Add Merge Queue Repository Policy

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/dev/features/opencode-agent-workflow.md`
- Test: focused policy grep

**Interfaces:**
- Consumes: spec `docs/specs/2026-08-02-merge-queue-agent-workflow-design.md`
- Produces: human- and agent-facing repository policy that distinguishes pre-PR current-base validation from post-PR merge-queue freshness

- [ ] **Step 1: Reproduce current policy gap**

  Run:

  ```bash
  rtk rg -n 'merge queue|merge-group|queued|already-open PR|post-PR' AGENTS.md docs/dev/features/opencode-agent-workflow.md
  ```

  Expected before edits: no policy-level merge queue guidance or only incidental matches from this plan/spec.

- [ ] **Step 2: Update `AGENTS.md` branch convention**

  In `AGENTS.md`, keep the existing requirement that final validation and initial PR creation use current `origin/main`. Add policy text with these exact behavioral points:

  - after a PR is open and queued by GitHub merge queue, do not update the PR branch solely because `origin/main` advanced;
  - merge-group checks are the post-PR integration freshness gate;
  - queue conflicts, missing merge queue protection, or merge-group `test` failures are actionable blockers;
  - actionable blockers use `systematic-debugging` and `implementer` → `reviewer` → pass for repository fixes;
  - rebase and force-push remain forbidden unless explicitly requested.

- [ ] **Step 3: Update the OpenCode workflow docs**

  In `docs/dev/features/opencode-agent-workflow.md`, update the branch and pull request policy section to document:

  - canonical source repository `https://github.com/semanticdreams/spacecore`;
  - pre-PR current-base validation against `origin/main`;
  - PR creation followed by auto-merge/merge-queue handoff;
  - no stale-branch update loop after PR creation merely because another PR merged;
  - queue failure handling for conflict and merge-group required-check failures;
  - GitHub admin requirement to enable merge queue for `main`.

- [ ] **Step 4: Verify policy wording**

  Run:

  ```bash
  rtk rg -n 'semanticdreams/spacecore|merge queue|merge-group|origin/main|systematic-debugging|implementer.*reviewer|rebase|force-push|HUMAN_DECISION_REQUIRED' AGENTS.md docs/dev/features/opencode-agent-workflow.md
  rtk git diff --check AGENTS.md docs/dev/features/opencode-agent-workflow.md
  ```

  Expected: all required concepts are present and whitespace checks pass.

---

### Task 3: Update OpenCode Finishing and Automation Skills

**Files:**
- Modify: `.opencode/agents/supervisor.md`
- Modify: `.opencode/skills/finishing-a-development-branch/SKILL.md`
- Modify: `.opencode/skills/daily-devlog-automation/SKILL.md`
- Modify: `.opencode/skills/weekly-agent-workflow-automation/SKILL.md`
- Test: focused skill-policy grep

**Interfaces:**
- Consumes: repository policy from Task 2
- Produces: running OpenCode agents that do not chase stale PR heads after merge-queue handoff

- [ ] **Step 1: Reproduce current skill gap**

  Run:

  ```bash
  rtk rg -n 'branch is behind|safe-merge `origin/main`|auto-merge|merge queue|merge-group' .opencode/agents/supervisor.md .opencode/skills/finishing-a-development-branch/SKILL.md .opencode/skills/daily-devlog-automation/SKILL.md .opencode/skills/weekly-agent-workflow-automation/SKILL.md
  ```

  Expected before edits: skills require current-base checks before push/PR but do not describe merge queue as the post-PR freshness gate.

- [ ] **Step 2: Update supervisor completion discipline**

  In `.opencode/agents/supervisor.md`, preserve pre-PR current-base checks. Add wording that after a PR is open and accepted into GitHub merge queue, the supervisor must not safe-merge `origin/main` solely because `main` advanced. It should wait for queue results and resume only for conflicts, required-check failures, missing queue protection, or permission blockers.

- [ ] **Step 3: Update finishing-a-development-branch**

  In `.opencode/skills/finishing-a-development-branch/SKILL.md`, update Step 2 / integration policy behavior so the automatic action becomes:

  - push current branch;
  - create PR targeting `main`;
  - enable auto-merge or queue the PR when branch protection allows it;
  - stop after successful queue handoff;
  - do not continue polling/updating solely because `origin/main` advanced after PR creation.

  Add failure handling: queue conflicts and merge-group `test` failures trigger `systematic-debugging`, then any repo fix uses `implementer` → `reviewer` → pass, commit, current-base validation, and requeue.

- [ ] **Step 4: Update daily automation skill**

  In `.opencode/skills/daily-devlog-automation/SKILL.md`, keep the pre-push and pre-PR current-base checks. Extend branch protection verification to require merge queue when the automation relies on post-PR freshness. After PR creation and auto-merge/queue handoff, state that later `origin/main` movement is handled by merge queue, not repeated automation branch updates.

- [ ] **Step 5: Update weekly automation skill**

  In `.opencode/skills/weekly-agent-workflow-automation/SKILL.md`, apply the same rule as daily automation: keep initial current-base validation, verify merge queue before relying on it, stop after queue handoff, and resume only for actionable queue blockers.

- [ ] **Step 6: Verify skill wording**

  Run:

  ```bash
  FILES='.opencode/agents/supervisor.md .opencode/skills/finishing-a-development-branch/SKILL.md .opencode/skills/daily-devlog-automation/SKILL.md .opencode/skills/weekly-agent-workflow-automation/SKILL.md'
  rtk rg -n 'merge queue|merge-group|origin/main|systematic-debugging|implementer.*reviewer|rebase|force-push|HUMAN_DECISION_REQUIRED|auto-merge' $FILES
  rtk git diff --check $FILES
  ```

  Expected: all required concepts are present and whitespace checks pass.

---

### Task 4: Validate Repository State and GitHub Follow-Up

**Files:**
- Test: all files changed by Tasks 1–3
- Test: GitHub rules for `semanticdreams/spacecore/main`

**Interfaces:**
- Consumes: completed Tasks 1–3
- Produces: reviewed, validated workflow/reference update and a clear human GitHub settings checklist

- [ ] **Step 1: Verify changed-file scope**

  Run:

  ```bash
  rtk git diff --name-only
  ```

  Expected: changed files are limited to the files named in Tasks 1–3 plus this plan/spec if coordination artifacts are still in the branch.

- [ ] **Step 2: Verify stale repository references**

  Run:

  ```bash
  rtk rg -n 'github\.com/semanticdreams/space([^2]|$)|semanticdreams/space\.git|git@example\.com:semanticdreams/space\.git|semanticdreams/space(\b|/)' README.md docs scripts assets/lua/tests/test-repo-remote.fnl .opencode AGENTS.md
  ```

  Expected: no old canonical repository references remain. Product-name uses such as `space`, `spaceui.org`, package filenames, and paths are not errors.

- [ ] **Step 3: Inspect GitHub rules**

  Run:

  ```bash
  rtk gh api repos/semanticdreams/spacecore/rules/branches/main
  rtk gh api repos/semanticdreams/spacecore/branches/main/protection || true
  ```

  Expected before the human GitHub settings change: rules require pull requests and `test`, but no merge queue rule is visible. Record `HUMAN_DECISION_REQUIRED` unless merge queue is already present.

- [ ] **Step 4: Run docs build**

  Run:

  ```bash
  cd docs && npm run docs:build
  ```

  Expected: VitePress build succeeds.

- [ ] **Step 5: Run final relevant suite**

  If Task 1 changed the Fennel fixture, run the compile check first when `./build/space` exists:

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-repo-remote.fnl
  ```

  Then run the repository's standard full suite unless the plan reviewer narrows validation because changes are documentation/configuration-only:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: required validation passes, or failures are handled through `systematic-debugging` and reviewed fixes.

- [ ] **Step 6: Report GitHub settings needed**

  Include this human checklist in the final handoff if merge queue is not already enabled:

  - In `semanticdreams/spacecore`, open the `main` branch ruleset.
  - Enable **Require merge queue**.
  - Keep required status check `test`.
  - Ensure the CI provider runs `test` for merge-group candidates (`merge_group` for GitHub Actions or `gh-readonly-queue/main` support for external CI).
  - Keep pull requests required and direct pushes blocked.

## Out of Scope

- Renaming the product, executable, package artifacts, or `spaceui.org` domain.
- Creating a custom merge steward or integration-train branch.
- Changing production runtime behavior.
- Editing GitHub Actions workflows unless the human identifies the required `test` workflow file and asks for merge-group trigger edits.
- Rebasing or force-pushing any branch.

## Self-Review Notes

- Spec coverage: URL migration, merge-queue workflow, OpenCode behavior, automation skills, validation, and GitHub human action are each covered by tasks.
- Placeholder scan: no deferred implementation placeholders remain.
- Type/signature consistency: this plan changes text/configuration and test fixtures only; no runtime API signatures are introduced.
