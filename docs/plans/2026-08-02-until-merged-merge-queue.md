# Until-Merged Merge Queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Space's required CI and OpenCode workflows support GitHub merge queue end-to-end, with agents monitoring PRs until they are actually merged.

**Architecture:** Add `merge_group` to the required GitHub Actions `test` workflow, then update repo policy, developer docs, and repo-local OpenCode skills so pre-PR validation remains strict while post-PR freshness is handled by merge queue. Agents poll GitHub until `mergedAt` is present and only modify branches for actionable blockers.

**Tech Stack:** GitHub Actions YAML, GitHub merge queue, GitHub CLI, OpenCode repo-local Markdown agents/skills, Node.js `node:test`, VitePress docs.

## Global Constraints

- Required repo check name remains exactly `test`.
- `.github/workflows/test.yml` must trigger on `merge_group`.
- Pull requests target `main`; use `origin/main`, not local `main`, for base freshness checks.
- Before PR creation, keep strict current-base validation against `origin/main`.
- After PR creation/queueing, do not update the PR branch solely because `origin/main` advanced.
- Agents must poll until the PR is merged; success is `mergedAt` present or equivalent merged state, not queue handoff alone.
- Queue conflicts, required-check failures, missing active merge queue, permission failures, closed-unmerged PRs, and queue timeouts are actionable blockers.
- Repository fixes go through `systematic-debugging`, then `implementer` → `reviewer` → pass, then validation from current `origin/main`, push, and requeue.
- Rebase and force-push remain forbidden unless the human explicitly requests them.
- OpenCode users must restart after `.opencode/**` changes.
- No `.fnl` files are in scope for this plan; Fennel validation ladder is not required unless implementation unexpectedly touches Fennel.
- HUMAN_DECISION_REQUIRED: GitHub repository settings must have an active merge-queue rule for `semanticdreams/spacecore:main`. Current API evidence shows active ruleset `19817562` lacks `merge_queue`, while disabled ruleset `20232493` includes it.

---

### Task 1: Add Merge-Group CI Trigger and Config Test

**Files:**
- Modify: `.github/workflows/test.yml`
- Modify: `docs/scripts/test-opencode-automation-config.mjs`
- Test: `cd docs && npm run test:scripts`

**Interfaces:**
- Consumes: existing required workflow name `test` and job `test`
- Produces: `test.yml` runs for GitHub merge queue `merge_group` events, guarded by a script test

- [ ] **Step 1: Add a failing script test for the merge-group trigger**

  In `docs/scripts/test-opencode-automation-config.mjs`, extend `loadFiles()` with a module-level variable and file read:

  ```js
  let testWorkflowContent = ''
  ```

  and inside `loadFiles()`:

  ```js
  testWorkflowContent = await readFile(join(repoRoot, '.github', 'workflows', 'test.yml'), 'utf8')
  ```

  Add this test near the other workflow/config tests:

  ```js
  test('required test workflow runs for merge queue merge_group events', async () => {
      await loadFiles()
      assert.match(testWorkflowContent, /^\s*merge_group:\s*$/m,
          'test.yml should include an on.merge_group trigger so required checks run for merge queue candidates')
  })
  ```

- [ ] **Step 2: Run the focused test to verify it fails**

  Run:

  ```bash
  cd docs && npm run test:scripts
  ```

  Expected before workflow edit: FAIL with the new assertion saying `test.yml` should include an `on.merge_group` trigger.

- [ ] **Step 3: Add `merge_group` to the workflow trigger**

  In `.github/workflows/test.yml`, change only the `on:` block so it includes:

  ```yaml
  on:
    push:
      branches:
        - main
    pull_request:
      branches:
        - main
    merge_group:
  ```

  Preserve all existing jobs, job names, environment variables, and the `build-windows` `if: github.event_name == 'push'` guard.

- [ ] **Step 4: Run focused validation**

  Run:

  ```bash
  cd docs && npm run test:scripts
  rtk git diff --check .github/workflows/test.yml docs/scripts/test-opencode-automation-config.mjs
  ```

  Expected: tests pass and whitespace check is clean.

- [ ] **Step 5: Commit Task 1**

  Commit only the workflow and script-test changes:

  ```bash
  git add .github/workflows/test.yml docs/scripts/test-opencode-automation-config.mjs
  git commit -m "ci: run required test workflow for merge queue"
  ```

---

### Task 2: Update Repository Policy and Developer Docs

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/dev/features/opencode-agent-workflow.md`
- Modify: `docs/scripts/test-opencode-automation-config.mjs`
- Test: `cd docs && npm run test:scripts`

**Interfaces:**
- Consumes: merge-group trigger from Task 1
- Produces: human- and agent-facing policy for polling until PR merge

- [ ] **Step 1: Add failing policy tests**

  In `docs/scripts/test-opencode-automation-config.mjs`, add module-level reads for policy files if they are not already loaded:

  ```js
  let agentsContent = ''
  let opencodeWorkflowContent = ''
  ```

  In `loadFiles()` add:

  ```js
  agentsContent = await readFile(join(repoRoot, 'AGENTS.md'), 'utf8')
  opencodeWorkflowContent = await readFile(join(repoRoot, 'docs', 'dev', 'features', 'opencode-agent-workflow.md'), 'utf8')
  ```

  Add this test:

  ```js
  test('repository policy requires agents to poll merge queue until PR merge', async () => {
      await loadFiles()
      const combined = `${agentsContent}\n${opencodeWorkflowContent}`
      const oneLine = combined.replace(/\s+/g, ' ')

      assert.match(oneLine, /poll.{0,160}(?:mergedAt|merged)/i,
          'policy should tell agents to poll until mergedAt or merged state')
      assert.match(combined, /gh pr view/i,
          'policy should document gh pr view for PR polling')
      assert.match(combined, /gh run list --workflow test\.yml --event merge_group/i,
          'policy should document merge_group run inspection')
      assert.match(oneLine, /do not update.{0,180}origin\/main advanced/i,
          'policy should keep the stale-branch update-loop prohibition')
      assert.doesNotMatch(oneLine, /Stop after successful merge-queue handoff/i,
          'policy should not treat merge-queue handoff as the terminal success state')
  })
  ```

- [ ] **Step 2: Run the focused test to verify it fails**

  Run:

  ```bash
  cd docs && npm run test:scripts
  ```

  Expected before policy edits: FAIL because current policy says to stop after queue handoff and lacks the full polling command contract.

- [ ] **Step 3: Update `AGENTS.md` branch policy**

  In `AGENTS.md`, replace stop-after-queue-handoff semantics with a section that states:

  - after PR creation and merge-queue/auto-merge request, agents keep running until the PR is merged;
  - success is `mergedAt` present or equivalent merged state;
  - agents poll with:

    ```bash
    gh pr view <pr-or-branch> --json state,mergedAt,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,headRefName,headRefOid,url
    gh run list --workflow test.yml --event merge_group --limit 20 --json databaseId,headBranch,headSha,status,conclusion,event,url,displayTitle,createdAt
    gh run watch <run-id> --exit-status --interval 100
    ```

  - queued/waiting/pending/in-progress/expected/null-conclusion states are non-terminal;
  - merge conflicts, failed required `test`, missing/disabled queue, permission failures, closed-unmerged PRs, and queue timeouts are blockers;
  - repository fixes use `systematic-debugging` and `implementer` → `reviewer` → pass;
  - do not update solely because `origin/main` advanced, and do not rebase/force-push unless explicitly requested.

- [ ] **Step 4: Update developer docs**

  In `docs/dev/features/opencode-agent-workflow.md`, mirror the same until-merged policy in the branch/PR or merge-queue section. Include the active GitHub setting caveat:

  ```text
  The `main` ruleset must actively require merge queue; a disabled ruleset that contains merge_queue is not sufficient.
  ```

- [ ] **Step 5: Run focused validation and commit**

  Run:

  ```bash
  cd docs && npm run test:scripts
  rtk rg -n 'mergedAt|gh pr view|gh run list --workflow test.yml --event merge_group|origin/main advanced|systematic-debugging|force-push' AGENTS.md docs/dev/features/opencode-agent-workflow.md
  rtk git diff --check AGENTS.md docs/dev/features/opencode-agent-workflow.md docs/scripts/test-opencode-automation-config.mjs
  ```

  Expected: tests pass, required concepts are present, and whitespace check is clean.

  Commit:

  ```bash
  git add AGENTS.md docs/dev/features/opencode-agent-workflow.md docs/scripts/test-opencode-automation-config.mjs
  git commit -m "docs: require agents to monitor merge queue until merged"
  ```

---

### Task 3: Align OpenCode Supervisor and Skills

**Files:**
- Modify: `.opencode/agents/supervisor.md`
- Modify: `.opencode/skills/finishing-a-development-branch/SKILL.md`
- Modify: `.opencode/skills/daily-devlog-automation/SKILL.md`
- Modify: `.opencode/skills/weekly-agent-workflow-automation/SKILL.md`
- Modify: `docs/scripts/test-opencode-automation-config.mjs`
- Test: `cd docs && npm run test:scripts`

**Interfaces:**
- Consumes: until-merged policy from Task 2
- Produces: repo-local OpenCode runtime instructions and permissions for polling until PR merge

- [ ] **Step 1: Add failing OpenCode policy tests**

  In `docs/scripts/test-opencode-automation-config.mjs`, add module-level reads if needed:

  ```js
  let finishingContent = ''
  let weeklySkillContent = ''
  ```

  In `loadFiles()` add:

  ```js
  finishingContent = await readFile(join(repoRoot, '.opencode', 'skills', 'finishing-a-development-branch', 'SKILL.md'), 'utf8')
  weeklySkillContent = await readFile(join(repoRoot, '.opencode', 'skills', 'weekly-agent-workflow-automation', 'SKILL.md'), 'utf8')
  ```

  Add this test:

  ```js
  test('opencode workflows monitor queued PRs until merged', async () => {
      await loadFiles()
      const files = [
          ['supervisor', supervisorContent],
          ['finishing', finishingContent],
          ['daily', skillContent],
          ['weekly', weeklySkillContent],
      ]

      for (const [name, content] of files) {
          const oneLine = content.replace(/\s+/g, ' ')
          assert.match(oneLine, /poll.{0,180}(?:mergedAt|merged)/i,
              `${name} should poll until mergedAt or merged state`)
          assert.match(content, /gh pr view/i,
              `${name} should mention gh pr view polling`)
          assert.match(oneLine, /do not (?:safe-merge|update).{0,220}origin\/main advanced/i,
              `${name} should preserve stale-branch loop prohibition`)
          assert.doesNotMatch(oneLine, /Stop after successful merge-queue handoff/i,
              `${name} should not stop after queue handoff`)
      }
  })
  ```

  Add a supervisor permission test:

  ```js
  test('supervisor permissions allow merge queue polling commands', async () => {
      await loadFiles()
      assert.ok(supervisorContent.includes('gh pr view * --json state,mergedAt,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,headRefName,headRefOid,url'),
          'supervisor should allow gh pr view merge-queue polling')
      assert.ok(supervisorContent.includes('gh run list --workflow test.yml --event merge_group --limit * --json databaseId,headBranch,headSha,status,conclusion,event,url,displayTitle,createdAt'),
          'supervisor should allow merge_group run listing')
      assert.ok(supervisorContent.includes('gh run watch * --exit-status --interval 100'),
          'supervisor should allow watching merge_group runs')
  })
  ```

- [ ] **Step 2: Run focused tests to verify they fail**

  Run:

  ```bash
  cd docs && npm run test:scripts
  ```

  Expected before skill edits: FAIL because OpenCode files still contain stop-after-handoff semantics and lack polling permissions.

- [ ] **Step 3: Update supervisor permissions and completion discipline**

  In `.opencode/agents/supervisor.md`, keep the broad `gh *: deny` rule and add these narrower allow rules after it:

  ```yaml
  "gh pr view * --json state,mergedAt,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,headRefName,headRefOid,url": allow
  "gh pr checks * --watch": allow
  "gh run list --workflow test.yml --event merge_group --limit * --json databaseId,headBranch,headSha,status,conclusion,event,url,displayTitle,createdAt": allow
  "gh run watch * --exit-status --interval 100": allow
  ```

  Update completion discipline so after PR creation/queue request the supervisor polls until merged, handles blockers, and does not update solely because `origin/main` advanced.

- [ ] **Step 4: Update finishing skill**

  In `.opencode/skills/finishing-a-development-branch/SKILL.md`, replace stop-after-handoff language with until-merged polling. Include the exact `gh pr view`, `gh run list`, and `gh run watch` commands from Task 2. Ensure queue/check failures route through `systematic-debugging` and reviewed fixes.

- [ ] **Step 5: Update daily and weekly automation skills**

  In both automation skills, replace stop-after-handoff language with until-merged polling while preserving:

  - branch naming;
  - reviewer and validation requirements;
  - merge method selection from branch rules;
  - no direct pushes to `origin/main`;
  - no rebase or force-push unless explicitly requested.

- [ ] **Step 6: Run focused validation and commit**

  Run:

  ```bash
  cd docs && npm run test:scripts
  FILES='.opencode/agents/supervisor.md .opencode/skills/finishing-a-development-branch/SKILL.md .opencode/skills/daily-devlog-automation/SKILL.md .opencode/skills/weekly-agent-workflow-automation/SKILL.md docs/scripts/test-opencode-automation-config.mjs'
  rtk rg -n 'mergedAt|gh pr view|gh run list --workflow test.yml --event merge_group|gh run watch|origin/main advanced|systematic-debugging|force-push|Stop after successful merge-queue handoff' $FILES
  rtk git diff --check $FILES
  ```

  Expected: tests pass; required concepts are present; `Stop after successful merge-queue handoff` has no matches in active policy text; whitespace check is clean.

  Commit:

  ```bash
  git add .opencode/agents/supervisor.md .opencode/skills/finishing-a-development-branch/SKILL.md .opencode/skills/daily-devlog-automation/SKILL.md .opencode/skills/weekly-agent-workflow-automation/SKILL.md docs/scripts/test-opencode-automation-config.mjs
  git commit -m "docs(opencode): monitor merge queue until PRs merge"
  ```

---

### Task 4: Verify GitHub Rules and Final Validation

**Files:**
- Test: `.github/workflows/test.yml`
- Test: `AGENTS.md`
- Test: `.opencode/agents/supervisor.md`
- Test: `.opencode/skills/finishing-a-development-branch/SKILL.md`
- Test: `.opencode/skills/daily-devlog-automation/SKILL.md`
- Test: `.opencode/skills/weekly-agent-workflow-automation/SKILL.md`
- Test: `docs/dev/features/opencode-agent-workflow.md`
- Test: `docs/scripts/test-opencode-automation-config.mjs`

**Interfaces:**
- Consumes: Tasks 1–3
- Produces: acceptance evidence and external GitHub settings report

- [ ] **Step 1: Verify effective GitHub rules**

  Run:

  ```bash
  rtk gh api repos/semanticdreams/spacecore/rulesets
  rtk gh api repos/semanticdreams/spacecore/rulesets/19817562
  rtk gh api repos/semanticdreams/spacecore/rulesets/20232493
  rtk gh api repos/semanticdreams/spacecore/rules/branches/main
  ```

  Expected for complete external setup: an active/effective ruleset for `main` includes `merge_queue` and required status check `test`. If active rules still lack `merge_queue`, report `HUMAN_DECISION_REQUIRED` with this exact guidance:

  ```text
  Enable ruleset 20232493 or add the merge_queue rule to active ruleset 19817562 for semanticdreams/spacecore:main. A disabled ruleset that contains merge_queue is not sufficient.
  ```

- [ ] **Step 2: Run focused policy/config tests**

  Run:

  ```bash
  cd docs && npm run test:scripts
  ```

  Expected: PASS.

- [ ] **Step 3: Run docs build**

  Run:

  ```bash
  cd docs && npm run docs:build
  ```

  Expected: PASS. Existing Fennel syntax-highlighting fallback warnings or chunk-size warnings may be reported as non-blocking if the build exits zero.

- [ ] **Step 4: Run whitespace and focused grep checks**

  Run:

  ```bash
  rtk git diff --check
  rtk rg -n 'merge_group|mergedAt|gh pr view|gh run list --workflow test.yml --event merge_group|gh run watch|origin/main advanced|systematic-debugging|force-push' .github/workflows/test.yml AGENTS.md docs/dev/features/opencode-agent-workflow.md .opencode/agents/supervisor.md .opencode/skills/finishing-a-development-branch/SKILL.md .opencode/skills/daily-devlog-automation/SKILL.md .opencode/skills/weekly-agent-workflow-automation/SKILL.md docs/scripts/test-opencode-automation-config.mjs
  rtk rg -n 'Stop after successful merge-queue handoff' AGENTS.md docs/dev/features/opencode-agent-workflow.md .opencode/agents/supervisor.md .opencode/skills/finishing-a-development-branch/SKILL.md .opencode/skills/daily-devlog-automation/SKILL.md .opencode/skills/weekly-agent-workflow-automation/SKILL.md || true
  ```

  Expected: required concepts are present; stop-after-handoff phrase has no matches in active policy files; whitespace check is clean.

- [ ] **Step 5: Run final relevant suite**

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: PASS. If it fails, invoke `systematic-debugging` and route any repository fix through `implementer` → `reviewer` → pass.

- [ ] **Step 6: Report restart and settings requirements**

  The final handoff must include:

  - `.github/workflows/test.yml` now includes `merge_group`;
  - agents now monitor until `mergedAt` / merged state;
  - stale-branch update loops remain forbidden;
  - whether GitHub active ruleset verification passed or needs human action;
  - OpenCode must be restarted after `.opencode/**` changes.

## Out of Scope

- Creating a separate merge steward service.
- Renaming the required check from `test`.
- Broad CI redesign beyond adding `merge_group` to `.github/workflows/test.yml`.
- Direct pushes to `main`.
- Rebasing or force-pushing branches.
- Production runtime behavior changes.

## Self-Review Notes

- Spec coverage: merge-group trigger, until-merged polling, blocker handling, OpenCode permissions, tests, docs, and GitHub ruleset verification are covered.
- Placeholder scan: no placeholder implementation steps remain.
- Type/signature consistency: this is documentation/configuration work; command strings are repeated consistently across tasks and tests.
