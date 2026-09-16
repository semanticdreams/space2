# Merged PR Follow-Up Branch Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a guarded OpenCode Git recovery path that creates a deterministic follow-up branch when the current branch resolves to an already-merged PR at an older head.

**Architecture:** Extend the existing `git-integrator` wrapper with one narrow `create-followup-branch` action that validates the current repository state, derives `<current-branch>-followup-<short-head-sha>`, proves the target branch is absent locally and remotely, then runs `git switch -c`. Keep GitHub permissions unchanged: after the wrapper switches branches, existing `push-current` and `github-operator create-current` workflows continue to operate on the current branch.

**Tech Stack:** Python 3 standard library, pytest, Git CLI, OpenCode Markdown agent/skill files, repo-local static permission checker.

## Global Constraints

- No broad Git or GitHub permission expansion.
- No rebase, reset, force-push, branch deletion, or direct main push.
- No `gh pr create --head *` wildcard permission.
- No bypass of final validation, review, clean-tree, or current-base checks.
- The target branch name is deterministic: `<current-branch>-followup-<short-head-sha>`.
- The guarded action is available only when the current worktree is clean.
- The guarded action is available only when the current branch is named and is not `main`.
- The guarded action is available only when current `HEAD` already contains current `origin/main`.
- The source branch name and derived branch name must satisfy the existing safe branch policy.
- The target branch name must not already exist locally or on `origin`.
- Supervisor cannot edit production/test code; implementation must go through `implementer` → `reviewer` → pass.
- TDD required: add tests first.
- OpenCode users must restart after `.opencode/**` changes.
- No application runtime behavior changes are expected.

---

## File Structure

- `scripts/opencode_git_integrate.py` — add the guarded `create-followup-branch` action and supporting local helpers.
- `scripts/tests/test_opencode_git_integrate.py` — add unit tests for deterministic branch derivation, all refusal guards, CLI wiring, and successful command shape.
- `.opencode/agents/git-integrator.md` — allow exactly the new wrapper command and document its evidence/usage.
- `scripts/check_opencode_permissions.py` — statically enforce the exact `git-integrator` allowed wrapper command set.
- `scripts/tests/test_check_opencode_permissions.py` — add static tests for the new permission boundary and workflow documentation.
- `.opencode/skills/finishing-a-development-branch/SKILL.md` — document the merged-old-PR recovery sequence.
- `.opencode/agents/supervisor.md` — document supervisor routing for merged PR/head mismatch recovery.
- `docs/dev/features/opencode-agent-workflow.md` — canonical dev documentation for the OpenCode capability workflow change.

## Acceptance Criteria

- `python3 scripts/opencode_git_integrate.py create-followup-branch --repo-root .` exists and emits structured JSON.
- The new action refuses dirty trees, `main`, detached `HEAD`, stale `origin/main` ancestry, unsafe branch names, existing local target branches, and existing remote target branches.
- The success path runs `git switch -c <current-branch>-followup-<short-head-sha>` only after all guards pass.
- `.opencode/agents/git-integrator.md` allows the exact new wrapper command and does not add raw Git or GitHub permissions.
- `github-operator` permissions remain unchanged; no `gh pr create --head *` permission is added.
- Finishing workflow docs tell supervisors to recover from `pr_state == "MERGED"` with `pr_head != current_head` by creating the follow-up branch, pushing it, and running normal current-branch PR creation.
- `make opencode-check` passes.
- PR CI is the full integration gate.

## Validation Ladder

1. Focused wrapper tests:
   ```bash
   python3 -m pytest scripts/tests/test_opencode_git_integrate.py -q
   ```
2. Focused permission/static workflow tests:
   ```bash
   python3 -m pytest scripts/tests/test_check_opencode_permissions.py -q
   python3 scripts/check_opencode_permissions.py --repo-root .
   ```
3. Complete relevant local OpenCode capability suite:
   ```bash
   make opencode-check
   ```
4. Final lightweight repository checks:
   ```bash
   git diff --check
   rg "create-followup-branch|pr_head|current_head|follow-up branch|MERGED" \
     .opencode/agents/git-integrator.md \
     .opencode/agents/supervisor.md \
     .opencode/skills/finishing-a-development-branch/SKILL.md \
     docs/dev/features/opencode-agent-workflow.md
   ```
5. Broader runtime validation is not required locally because this changes only Python wrappers, OpenCode config/docs, and static tests; no Space runtime, C++, Fennel, assets, or `./build/space` behavior changes. PR CI is the full integration gate.

## Out of Scope

- Do not modify `scripts/opencode_pr_operator.py` unless an existing test unexpectedly proves its current mismatch evidence is unusable.
- Do not modify `.opencode/agents/github-operator.md`.
- Do not add branch-name parameters to GitHub wrapper permissions.
- Do not add rebases, force-pushes, resets, deletes, direct main pushes, or raw `gh` permissions.
- Do not automate PR creation from arbitrary `--head` values.

---

### Task 1: Guarded Follow-Up Branch Wrapper

**Files:**
- Modify: `scripts/opencode_git_integrate.py`
- Test: `scripts/tests/test_opencode_git_integrate.py`

**Interfaces:**
- Consumes: `validate_branch_name(branch: str) -> str`, `run_command(args, cwd, check=True) -> CommandResult`, `success(...)`, `human_decision(...)`, `failure(...)`.
- Produces: `_derive_followup_branch_name(source_branch: str, short_head_sha: str) -> str`.
- Produces: `create_followup_branch(repo_root: Path) -> dict[str, object]`.
- Produces CLI command: `python3 scripts/opencode_git_integrate.py create-followup-branch --repo-root <path>`.

- [ ] **Step 1: Add failing tests for branch-name derivation and refusal guards**

  In `scripts/tests/test_opencode_git_integrate.py`, add tests that assert:
  - `_derive_followup_branch_name("juicyrebel/test-workflow-artifact-names", "caad43f") == "juicyrebel/test-workflow-artifact-names-followup-caad43f"`.
  - `create_followup_branch(...)` returns `human_decision_required` and does not call `git switch -c` when `git status --porcelain` is non-empty.
  - `create_followup_branch(...)` returns `human_decision_required` from `main`.
  - `create_followup_branch(...)` returns `human_decision_required` from detached `HEAD` when `git branch --show-current` returns `"\n"`.
  - `create_followup_branch(...)` returns `human_decision_required` when `git merge-base --is-ancestor origin/main HEAD` returns code `1`.

- [ ] **Step 2: Add failing tests for target collisions**

  Add tests that use `GitRunner` to assert:
  - local target exists when `git show-ref --verify --quiet refs/heads/<target>` returns `0`;
  - remote target exists when `git ls-remote --exit-code --heads origin <target>` returns `0`;
  - both cases return `human_decision_required` and never call `git switch -c`.

- [ ] **Step 3: Add failing success-path and CLI tests**

  Add a success test expecting this exact command order for branch `feature/opencode-capabilities` and short head `caad43f`:
  ```text
  git status --porcelain
  git branch --show-current
  git rev-parse --short=7 HEAD
  git merge-base --is-ancestor origin/main HEAD
  git show-ref --verify --quiet refs/heads/feature/opencode-capabilities-followup-caad43f
  git ls-remote --exit-code --heads origin feature/opencode-capabilities-followup-caad43f
  git switch -c feature/opencode-capabilities-followup-caad43f
  ```

  Also add a CLI test for:
  ```bash
  python3 scripts/opencode_git_integrate.py create-followup-branch --repo-root <trusted_repo>
  ```

- [ ] **Step 4: Run wrapper tests and verify RED**

  ```bash
  python3 -m pytest scripts/tests/test_opencode_git_integrate.py -q
  ```

  Expected: failures because `create_followup_branch`, `_derive_followup_branch_name`, and the CLI command do not exist yet.

- [ ] **Step 5: Implement helper functions and guarded action**

  In `scripts/opencode_git_integrate.py`:
  - Add `_derive_followup_branch_name(source_branch: str, short_head_sha: str) -> str`.
  - Add local/remote existence helpers that treat local `show-ref` return code `1` as absent and remote `ls-remote` return code `2` as absent; any other unexpected nonzero code fails closed with `CapabilityError`.
  - Add `create_followup_branch(repo_root: Path) -> dict[str, object]` with action name `create_followup_branch`.
  - Guard order: clean non-main named branch, short `HEAD`, `origin/main` ancestry, target branch derivation, source/target `validate_branch_name`, local absence, remote absence, then `git switch -c`.

- [ ] **Step 6: Wire the CLI**

  Add `create-followup-branch` to `_parse_args` and `main(...)` operations.

- [ ] **Step 7: Run focused wrapper tests and verify GREEN**

  ```bash
  python3 -m pytest scripts/tests/test_opencode_git_integrate.py -q
  ```

---

### Task 2: Git-Integrator Permission Boundary

**Files:**
- Modify: `.opencode/agents/git-integrator.md`
- Modify: `scripts/check_opencode_permissions.py`
- Test: `scripts/tests/test_check_opencode_permissions.py`

**Interfaces:**
- Consumes: CLI command `python3 scripts/opencode_git_integrate.py create-followup-branch --repo-root .`.
- Produces: static checker enforcement that `git-integrator` allows only the approved `scripts/opencode_git_integrate.py` wrapper commands.

- [ ] **Step 1: Add failing permission tests**

  In `scripts/tests/test_check_opencode_permissions.py`:
  - Update the synthetic `write_capability_files(...)` helper so its `git-integrator` fixture includes the full intended wrapper allowlist:
    ```text
    python3 scripts/opencode_git_integrate.py status --repo-root .
    python3 scripts/opencode_git_integrate.py fetch-origin --repo-root .
    python3 scripts/opencode_git_integrate.py merge-origin-main --repo-root .
    python3 scripts/opencode_git_integrate.py push-current --repo-root .
    python3 scripts/opencode_git_integrate.py create-followup-branch --repo-root .
    ```
  - Add `test_git_integrator_allows_exact_guarded_git_wrapper_commands` against `REPO_ROOT`.
  - Add `test_git_integrator_rejects_extra_bash_allow` using a synthetic `git-integrator` with an extra allowed raw command such as `"git switch -c *": allow`.

- [ ] **Step 2: Run permission tests and verify RED**

  ```bash
  python3 -m pytest scripts/tests/test_check_opencode_permissions.py -q
  ```

  Expected: failures because the real agent does not yet allow the new command and the checker does not yet enforce the exact git-integrator allowlist.

- [ ] **Step 3: Update `git-integrator` agent permissions and text**

  In `.opencode/agents/git-integrator.md`:
  - Add the exact allowed command:
    ```yaml
    "python3 scripts/opencode_git_integrate.py create-followup-branch --repo-root .": allow
    ```
  - Update the description/body to state that this creates and switches to a guarded deterministic follow-up branch from current `HEAD`.
  - Keep `edit`, `task`, `external_directory`, `webfetch`, `websearch`, and `question` denied.
  - Do not add raw `git switch`, raw `git checkout`, raw `git push`, or any GitHub command permissions.

- [ ] **Step 4: Implement exact static boundary check**

  In `scripts/check_opencode_permissions.py`:
  - Add a constant set for the five allowed `git-integrator` wrapper commands.
  - Extend `_check_capability_boundary(...)` for `name == "git-integrator"` so:
    - each required wrapper command must be present with `allow`;
    - any other `allow` or `ask` bash entry is a `capability-boundary` violation;
    - broad/raw Git commands remain rejected by existing unsafe-permission checks.

- [ ] **Step 5: Run focused permission/static checks and verify GREEN**

  ```bash
  python3 -m pytest scripts/tests/test_check_opencode_permissions.py -q
  python3 scripts/check_opencode_permissions.py --repo-root .
  ```

---

### Task 3: Workflow Documentation and Supervisor Routing

**Files:**
- Modify: `.opencode/skills/finishing-a-development-branch/SKILL.md`
- Modify: `.opencode/agents/supervisor.md`
- Modify: `docs/dev/features/opencode-agent-workflow.md`
- Test: `scripts/tests/test_check_opencode_permissions.py`

**Interfaces:**
- Consumes: `github-operator create-current` mismatch evidence fields: `branch`, `current_head`, `pr_head`, `pr_state`, `pr_url`.
- Consumes: `git-integrator create-followup-branch`.
- Produces: documented recovery sequence for `pr_state == "MERGED"` and `pr_head != current_head`.

- [ ] **Step 1: Add failing static documentation test**

  In `scripts/tests/test_check_opencode_permissions.py`, add a test that reads:
  - `.opencode/skills/finishing-a-development-branch/SKILL.md`
  - `.opencode/agents/supervisor.md`
  - `docs/dev/features/opencode-agent-workflow.md`

  The test should assert each file mentions the recovery evidence/operation terms:
  ```text
  pr_head
  current_head
  MERGED
  create-followup-branch
  follow-up branch
  ```

- [ ] **Step 2: Run static documentation test and verify RED**

  ```bash
  python3 -m pytest scripts/tests/test_check_opencode_permissions.py -q
  ```

- [ ] **Step 3: Update finishing skill recovery path**

  In `.opencode/skills/finishing-a-development-branch/SKILL.md`, add the merged-old-PR recovery rule under the automatic PR creation flow:
  - If `github-operator create-current` returns `human_decision_required` because an existing PR is `MERGED` and `pr_head != current_head`, do not request broad `gh` or `--head` permission.
  - Confirm clean/current-base state through `git-integrator`.
  - Dispatch `git-integrator` `create-followup-branch`.
  - Dispatch `git-integrator` `push-current`.
  - Dispatch `github-operator` `create-current`.
  - Continue auto-merge/merge-queue polling as usual.
  - Any wrapper refusal remains `HUMAN_DECISION_REQUIRED` with wrapper evidence.

- [ ] **Step 4: Update supervisor routing**

  In `.opencode/agents/supervisor.md`:
  - Update the `git-integrator` subagent summary to include guarded follow-up branch creation.
  - Add a routing rule in capability boundary guidance for `pr_state == "MERGED"` with `pr_head != current_head`.
  - Preserve the rule that the supervisor never edits production/test code and does not request broad Git/GitHub permissions.

- [ ] **Step 5: Update dev documentation**

  In `docs/dev/features/opencode-agent-workflow.md`, add a short section under the capability model documenting:
  - deterministic target branch format `<current-branch>-followup-<short-head-sha>`;
  - guards: clean tree, named non-main branch, current with `origin/main`, safe branch policy, local/remote target absence;
  - normal sequence: create follow-up branch → push current → create current PR;
  - restart OpenCode after `.opencode/**` changes.

- [ ] **Step 6: Run focused static checks and verify GREEN**

  ```bash
  python3 -m pytest scripts/tests/test_check_opencode_permissions.py -q
  rg "create-followup-branch|pr_head|current_head|follow-up branch|MERGED" \
    .opencode/agents/supervisor.md \
    .opencode/skills/finishing-a-development-branch/SKILL.md \
    docs/dev/features/opencode-agent-workflow.md
  ```

---

### Task 4: Complete OpenCode Capability Validation

**Files:**
- Test: `scripts/tests/test_opencode_git_integrate.py`
- Test: `scripts/tests/test_check_opencode_permissions.py`
- Test: `scripts/tests/test_opencode_capabilities.py`
- Test: `scripts/tests/test_opencode_pr_operator.py`

**Interfaces:**
- Consumes: all changes from Tasks 1-3.
- Produces: local validation evidence for the OpenCode workflow/capability surface.

- [ ] **Step 1: Run focused wrapper and permission tests**

  ```bash
  python3 -m pytest scripts/tests/test_opencode_git_integrate.py -q
  python3 -m pytest scripts/tests/test_check_opencode_permissions.py -q
  python3 scripts/check_opencode_permissions.py --repo-root .
  ```

- [ ] **Step 2: Run the complete relevant local suite**

  ```bash
  make opencode-check
  ```

- [ ] **Step 3: Run final text/diff checks**

  ```bash
  git diff --check
  rg "create-followup-branch|pr_head|current_head|follow-up branch|MERGED" \
    .opencode/agents/git-integrator.md \
    .opencode/agents/supervisor.md \
    .opencode/skills/finishing-a-development-branch/SKILL.md \
    docs/dev/features/opencode-agent-workflow.md
  ```

- [ ] **Step 4: Record operational note in handoff**

  State in the implementation handoff that OpenCode users must restart after `.opencode/**` changes before relying on the new `git-integrator` permission and workflow instructions.
