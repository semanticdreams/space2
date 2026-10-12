# OpenCode Permission Capabilities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce routine OpenCode permission friction by introducing guarded capability scripts, capability agents, policy checks, and sanitized permission-friction reporting without broadening existing role authority.

**Architecture:** Add a small Python guard layer that validates Space repository identity, safe branch names, command outcomes, and structured JSON responses. Route privileged Git, GitHub, and OpenCode-config verification through dedicated capability agents that can run only approved wrappers, while supervisor skills dispatch those agents at capability boundaries. Keep existing implementer/reviewer/web-researcher role boundaries intact and add policy tests that fail closed if unsafe permissions are introduced.

**Tech Stack:** Python 3 stdlib, pytest, Markdown/YAML-frontmatter text validation, OpenCode repo-local agent/skill files, Git/GitHub CLI wrappers.

## Global Constraints

- Replace routine `ask` prompts with pre-authorized, bounded capabilities while leaving truly destructive, credentialed, cross-project, or ambiguous operations blocked by design.
- Do not grant every subagent broad shell, GitHub, edit, web, or external directory access.
- Do not allow direct pushes to `origin/main`, force-push, history rewrite, broad branch deletion, `git reset`, `git clean`, broad recursive removal, package-manager/system changes, or credential/auth-file access.
- Do not inspect raw OpenCode database rows, raw logs, raw tool-output dumps, or secret-bearing files to diagnose permission friction.
- Do not solve every possible future permission prompt speculatively; add a framework and the highest-confidence capabilities first.
- Existing agents should remain narrow: reviewer no edit/bash/external; implementer no push/external; web-researcher web-only no local.
- Avoid broad grants: no direct main push, force-push, rebase, reset/clean, broad rm, sudo/package-manager, broad home/root access, broad `gh *`.
- Prefer guarded scripts and capability agents over broad `ask` rules.
- Actual implementation must go through implementer → reviewer → pass for production, test, script, docs/dev, and `.opencode/**` changes.
- Supervisor may directly write plan files only; production, test, script, docs/dev, and `.opencode/**` edits are not supervisor-direct.
- OpenCode must be restarted after `.opencode/**` changes before relying on new agents, skills, or permissions.
- Use Python stdlib only for new scripts; do not add package dependencies.

## Acceptance Criteria

- New wrappers emit structured JSON with `status`, `action`, `message`, and `evidence` keys, and fail closed with `HUMAN_DECISION_REQUIRED` or nonzero exit for unsafe states.
- `git-integrator`, `github-operator`, and `config-auditor` exist as narrow capability agents with `edit: deny`, no web access, no task dispatch, and only wrapper-specific bash permissions.
- Reviewer remains edit/bash/external-denied; implementer remains push/external-denied; web-researcher remains web-only with no local access.
- Supervisor and workflow skills route privileged Git/GitHub/config boundaries to capability agents instead of asking for direct permission.
- Policy checks reject direct main push, force/history rewrite, rebase, reset/clean, broad recursive removal, sudo/package-manager, broad home/root, and broad `gh *` grants.
- Weekly analyzer reports permission friction classes: `routine-project-scoped`, `privileged-bounded`, `role-mismatch`, and `destructive-ambiguous`.
- Docs/dev documents the capability model, wrapper commands, agent boundaries, restart requirement, and weekly permission-friction classes.

## Validation Ladder

1. Focused implementation checks:
   - `python3 -m pytest scripts/tests/test_opencode_capabilities.py -q`
   - `python3 -m pytest scripts/tests/test_opencode_git_integrate.py scripts/tests/test_opencode_pr_operator.py -q`
   - `python3 -m pytest scripts/tests/test_check_opencode_permissions.py -q`
   - `python3 scripts/check_opencode_permissions.py --repo-root .`
   - `python3 -m pytest scripts/tests/test_weekly_agent_workflow_analyzer.py -q`
2. Complete relevant local suite for this behavioral surface:
   - `python3 -m pytest scripts/tests/test_opencode_capabilities.py scripts/tests/test_opencode_git_integrate.py scripts/tests/test_opencode_pr_operator.py scripts/tests/test_check_opencode_permissions.py scripts/tests/test_weekly_agent_workflow_analyzer.py -q`
   - `python3 scripts/check_opencode_permissions.py --repo-root .`
3. Broader final checks justified by OpenCode workflow/config risk:
   - `python3 -m json.tool .opencode/opencode.json >/dev/null`
   - `rg -n "Permission capability model|OpenCode must be restarted|permission-friction classes|HUMAN_DECISION_REQUIRED" docs/dev/features/opencode-agent-workflow.md docs/dev/features/weekly-agent-workflow-automation.md`
   - `git diff --check origin/main...HEAD`
   - PR CI is the full integration gate.

## Out of Scope

- No artifact-auditor raw log/tool-output browsing capability in this increment.
- No package-manager, sudo, credential, auth-file, or global OpenCode config mutation support.
- No direct `origin/main` push, force-push, rebase, reset, clean, branch deletion, or broad `gh` command support.
- No GitHub branch protection or merge queue setting changes; wrappers report `HUMAN_DECISION_REQUIRED` when settings are missing.
- No migration of every future workflow; this increment routes finishing, daily devlog, and weekly workflow automation through the new capability boundary.

---

### Task 1: Shared Capability Guard Helpers and Config Audit Wrapper

**Files:**
- Create: `scripts/opencode_capabilities.py`
- Create: `scripts/verify_opencode_home_config.py`
- Test: `scripts/tests/test_opencode_capabilities.py`

**Interfaces:**
- Consumes: Space repository root, allowed branch naming policy, and OpenCode home path.
- Produces:
  - `CapabilityError(code: str, message: str, details: dict[str, object] | None = None)`
  - `CommandResult(args: list[str], returncode: int, stdout: str, stderr: str)`
  - `ensure_space_repo(repo_root: Path) -> Path`
  - `validate_branch_name(branch: str) -> str`
  - `run_command(args: Sequence[str], cwd: Path, check: bool = True) -> CommandResult`
  - `success(action: str, message: str, evidence: dict[str, object]) -> dict[str, object]`
  - `human_decision(action: str, message: str, evidence: dict[str, object]) -> dict[str, object]`
  - `failure(action: str, message: str, evidence: dict[str, object]) -> dict[str, object]`
  - `audit_opencode_home(repo_root: Path, opencode_home: Path) -> dict[str, object]`

- [ ] **Step 1: Add tests for repository, branch, JSON, and config-audit guards**

  In `scripts/tests/test_opencode_capabilities.py`, cover:
  - `ensure_space_repo` accepts a temp git repo with `AGENTS.md`, `.opencode/opencode.json`, and origin `git@example.com:semanticdreams/spacecore.git`.
  - `ensure_space_repo` rejects repos without Space markers.
  - `validate_branch_name` accepts `automation/daily-devlog/2026-08-05`, `automation/weekly-agent-workflow/2026-W32`, `opencode/workflow-debug/test-123`, `opencode/workflow-debug-pr/test-123`, `feature/opencode-capabilities`, `fix/permission-capabilities`, `docs/opencode-capabilities`, and `chore/opencode-capabilities`.
  - `validate_branch_name` rejects `main`, `origin/main`, `feature/../main`, `feature/bad lock`, `feature/name.lock`, and empty strings.
  - `audit_opencode_home` passes when `opencode.json`, `agents`, and `skills` in a temp OpenCode home are symlinks to repo `.opencode/**`, `plugins/rtk.ts` is preserved as a local global plugin file, and local `package.json` / `package-lock.json` remain allowed non-secret support files rather than required project symlinks.
  - `audit_opencode_home` returns `status: "human_decision_required"` when any expected symlink resolves outside the repo.
  - `audit_opencode_home` does not read `auth.json`; create an unreadable or secret-looking `auth.json` fixture and assert no secret text appears in serialized output.

- [ ] **Step 2: Run the new tests and confirm they fail before implementation**

  ```bash
  python3 -m pytest scripts/tests/test_opencode_capabilities.py -q
  ```

  Expected: failures for missing `opencode_capabilities` and `verify_opencode_home_config`.

- [ ] **Step 3: Implement `scripts/opencode_capabilities.py`**

  Implement the interfaces above using only Python stdlib. `ensure_space_repo` must resolve the repo root, verify git top-level, require `AGENTS.md` and `.opencode/opencode.json`, and require origin URL containing `semanticdreams/spacecore`. `validate_branch_name` must enforce the accepted branch patterns listed in Step 1 and reject traversal, whitespace, `.lock`, `main`, and `origin/main`.

- [ ] **Step 4: Implement `scripts/verify_opencode_home_config.py`**

  CLI contract:

  ```bash
  python3 scripts/verify_opencode_home_config.py --repo-root . --opencode-home ~/.config/opencode
  ```

  Behavior:
  - Calls `audit_opencode_home`.
  - Prints pretty JSON to stdout.
  - Exits `0` when `status == "pass"`.
  - Exits `2` when `status == "human_decision_required"`.
  - Exits `3` on local validation failure or unexpected exception.
  - Never reads `auth.json`, `auth.jsonc`, token files, raw OpenCode database files, tool-output, or logs.

- [ ] **Step 5: Run focused validation**

  ```bash
  python3 -m pytest scripts/tests/test_opencode_capabilities.py -q
  python3 scripts/verify_opencode_home_config.py --repo-root . --opencode-home .opencode
  ```

  Expected: tests pass; the direct `.opencode` audit may return `human_decision_required` because repo-local config is not a global symlink home, but it must emit structured JSON and no traceback.

- [ ] **Step 6: Commit Task 1**

  ```bash
  git add scripts/opencode_capabilities.py scripts/verify_opencode_home_config.py scripts/tests/test_opencode_capabilities.py
  git commit -m "feat(scripts): add OpenCode capability guard helpers"
  ```

### Task 2: Guarded Git and GitHub Operator Wrappers

**Files:**
- Create: `scripts/opencode_git_integrate.py`
- Create: `scripts/opencode_pr_operator.py`
- Test: `scripts/tests/test_opencode_git_integrate.py`
- Test: `scripts/tests/test_opencode_pr_operator.py`

**Interfaces:**
- Consumes:
  - `ensure_space_repo(repo_root: Path) -> Path`
  - `validate_branch_name(branch: str) -> str`
  - `run_command(args: Sequence[str], cwd: Path, check: bool = True) -> CommandResult`
  - JSON response helpers from `scripts/opencode_capabilities.py`
- Produces:
  - `git_status(repo_root: Path) -> dict[str, object]`
  - `fetch_origin(repo_root: Path) -> dict[str, object]`
  - `merge_origin_main(repo_root: Path) -> dict[str, object]`
  - `push_current(repo_root: Path) -> dict[str, object]`
  - `pr_auth_status(repo_root: Path) -> dict[str, object]`
  - `check_main_protection(repo_root: Path) -> dict[str, object]`
  - `create_pr(repo_root: Path, head: str) -> dict[str, object]`
  - `enable_auto_merge(repo_root: Path, branch: str) -> dict[str, object]`
  - `poll_merge_queue(repo_root: Path, branch: str, timeout_seconds: int, interval_seconds: int) -> dict[str, object]`

- [ ] **Step 1: Add Git wrapper tests**

  In `scripts/tests/test_opencode_git_integrate.py`, monkeypatch command execution and assert:
  - `status` reports branch, head SHA, dirty state, and `origin/main` merge-base evidence.
  - `merge-origin-main` refuses dirty worktrees.
  - `merge-origin-main` refuses branch `main`.
  - `merge-origin-main` runs only `git fetch origin main` then `git merge --no-edit origin/main`.
  - `push-current` refuses `main`, refuses invalid branch names, and runs only `git push origin HEAD:refs/heads/<current-branch>` for valid branches.
  - CLI emits JSON and returns nonzero on unsafe states.

- [ ] **Step 2: Add GitHub wrapper tests**

  In `scripts/tests/test_opencode_pr_operator.py`, monkeypatch command execution and assert:
  - `auth-status` runs only `gh auth status`.
  - `create` always uses `--base main`, validates `--head`, and rejects invalid branch names.
  - `enable-auto-merge` checks main protection before `gh pr merge --auto`.
  - `check-main-protection` returns `human_decision_required` when neither classic protection nor active rulesets prove required `test` and merge queue.
  - `poll-merge-queue` treats `queued`, `waiting`, `pending`, `in_progress`, `expected`, and missing conclusions as nonterminal.
  - `poll-merge-queue` returns pass only when PR `mergedAt` is present.
  - No test expects or permits broad `gh *`, direct `origin/main` push, force-push, rebase, reset, or clean.

- [ ] **Step 3: Run the wrapper tests and confirm they fail before implementation**

  ```bash
  python3 -m pytest scripts/tests/test_opencode_git_integrate.py scripts/tests/test_opencode_pr_operator.py -q
  ```

- [ ] **Step 4: Implement `scripts/opencode_git_integrate.py`**

  CLI contract:

  ```bash
  python3 scripts/opencode_git_integrate.py status --repo-root .
  python3 scripts/opencode_git_integrate.py fetch-origin --repo-root .
  python3 scripts/opencode_git_integrate.py merge-origin-main --repo-root .
  python3 scripts/opencode_git_integrate.py push-current --repo-root .
  ```

  Required invariants:
  - Always call `ensure_space_repo`.
  - Reject dirty worktree for `merge-origin-main` and `push-current`.
  - Reject current branch `main`.
  - Never run force-push, rebase, reset, clean, branch delete, or checkout discard.
  - Print structured JSON and exit `0` for pass, `2` for `human_decision_required`, `3` for local failure.

- [ ] **Step 5: Implement `scripts/opencode_pr_operator.py`**

  CLI contract:

  ```bash
  python3 scripts/opencode_pr_operator.py auth-status --repo-root .
  python3 scripts/opencode_pr_operator.py check-main-protection --repo-root .
  python3 scripts/opencode_pr_operator.py create --repo-root . --head feature/opencode-capabilities
  python3 scripts/opencode_pr_operator.py enable-auto-merge --repo-root . --branch feature/opencode-capabilities
  python3 scripts/opencode_pr_operator.py view --repo-root . --branch feature/opencode-capabilities
  python3 scripts/opencode_pr_operator.py poll-merge-queue --repo-root . --branch feature/opencode-capabilities --timeout-seconds 7200 --interval-seconds 100
  ```

  Required invariants:
  - Always call `ensure_space_repo`.
  - Validate branch names with `validate_branch_name`.
  - Always target base `main`.
  - Verify main protection/rulesets before auto-merge.
  - Return `human_decision_required` for missing auth, missing protection, missing merge queue, unsupported merge method requiring rebase, queue timeout, failed merge-group run, closed-unmerged PR, or ambiguous GitHub response.
  - Never expose a generic `gh` passthrough.

- [ ] **Step 6: Run focused validation**

  ```bash
  python3 -m pytest scripts/tests/test_opencode_capabilities.py scripts/tests/test_opencode_git_integrate.py scripts/tests/test_opencode_pr_operator.py -q
  ```

- [ ] **Step 7: Commit Task 2**

  ```bash
  git add scripts/opencode_git_integrate.py scripts/opencode_pr_operator.py scripts/tests/test_opencode_git_integrate.py scripts/tests/test_opencode_pr_operator.py
  git commit -m "feat(scripts): add guarded Git and GitHub operators"
  ```

### Task 3: Capability Agents, Supervisor Routing, and Permission Policy Checks

**Files:**
- Create: `.opencode/agents/git-integrator.md`
- Create: `.opencode/agents/github-operator.md`
- Create: `.opencode/agents/config-auditor.md`
- Create: `scripts/check_opencode_permissions.py`
- Create: `scripts/tests/test_check_opencode_permissions.py`
- Modify: `.opencode/agents/supervisor.md`
- Modify: `.opencode/skills/finishing-a-development-branch/SKILL.md`
- Modify: `.opencode/skills/daily-devlog-automation/SKILL.md`
- Modify: `.opencode/skills/weekly-agent-workflow-automation/SKILL.md`

**Interfaces:**
- Consumes:
  - Wrapper CLI commands from Tasks 1 and 2.
  - Existing OpenCode agent frontmatter format.
- Produces:
  - `check_repo(repo_root: Path) -> list[PolicyViolation]`
  - `PolicyViolation(path: str, code: str, message: str)`
  - CLI: `python3 scripts/check_opencode_permissions.py --repo-root .`
  - Capability agents callable by supervisor: `git-integrator`, `github-operator`, `config-auditor`.

- [ ] **Step 1: Add policy checker tests**

  In `scripts/tests/test_check_opencode_permissions.py`, assert:
  - Current repo passes after Task 3 changes.
  - A fixture reviewer with `bash: allow` fails.
  - A fixture implementer with `git push*: allow` fails.
  - A fixture web-researcher with `read: "*": allow` fails.
  - A fixture capability agent with `edit: allow` fails.
  - Any agent permission text containing `git push origin main: allow`, `git push *--force*: allow`, `git rebase*: ask`, `git reset*: ask`, `git clean*: allow`, `sudo *: ask`, `apt-get *: allow`, broad `gh *: allow`, or `external_directory: "*": allow` fails.
  - `.opencode/opencode.json` must parse as JSON and keep `"default_agent": "supervisor"`.
  - Every `.opencode/agents/*.md` has frontmatter with `description`, `mode`, `model`, and `permission`.
  - Every `.opencode/skills/*/SKILL.md` has frontmatter with `name` and `description`.

- [ ] **Step 2: Run policy tests and confirm they fail before implementation**

  ```bash
  python3 -m pytest scripts/tests/test_check_opencode_permissions.py -q
  ```

- [ ] **Step 3: Implement `scripts/check_opencode_permissions.py`**

  Use stdlib only. The checker may parse frontmatter structurally rather than using a YAML dependency. It must print either:

  ```json
  {"status": "pass", "violations": []}
  ```

  or:

  ```json
  {"status": "fail", "violations": [{"path": "...", "code": "...", "message": "..."}]}
  ```

  Exit `0` on pass and `1` on violations.

- [ ] **Step 4: Create `git-integrator` capability agent**

  Create `.opencode/agents/git-integrator.md` with:
  - subagent mode
  - no edit/task/web/external/question permissions
  - bash denied by default
  - bash allowed only for:
    - `python3 scripts/opencode_git_integrate.py status --repo-root .`
    - `python3 scripts/opencode_git_integrate.py fetch-origin --repo-root .`
    - `python3 scripts/opencode_git_integrate.py merge-origin-main --repo-root .`
    - `python3 scripts/opencode_git_integrate.py push-current --repo-root .`

  Prompt text must instruct the agent to return wrapper JSON evidence verbatim and to report `HUMAN_DECISION_REQUIRED` instead of asking the user when the wrapper refuses.

- [ ] **Step 5: Create `github-operator` capability agent**

  Create `.opencode/agents/github-operator.md` with:
  - subagent mode
  - `read`, `glob`, `grep`, `list`, `lsp`, `edit`, `task`, `external_directory`, `webfetch`, `websearch`, and `question` denied
  - bash denied by default
  - bash allowed only for the six `scripts/opencode_pr_operator.py` CLI shapes from Task 2

  Prompt text must forbid arbitrary `gh`, direct shell, branch protection mutation, direct merge, and rebase-only auto-merge.

- [ ] **Step 6: Create `config-auditor` capability agent**

  Create `.opencode/agents/config-auditor.md` with:
  - read access only to `.opencode/**`, `scripts/verify_opencode_home_config.py`, and `scripts/opencode_capabilities.py`
  - external access only to `~/.config/opencode/**`, with `auth.json`, `auth.jsonc`, and secret/token-looking files denied
  - edit/task/web/question denied
  - bash denied by default
  - bash allowed only for `python3 scripts/verify_opencode_home_config.py --repo-root . --opencode-home ~/.config/opencode`

  Prompt text must state that it verifies project-supplied symlinks and expected non-secret support files only; it must not require global `package.json`, `package-lock.json`, `plugins`, or `node_modules` to be symlinked into the project.

- [ ] **Step 7: Update supervisor routing and remove direct privileged asks**

  In `.opencode/agents/supervisor.md`:
  - Add `git-integrator`, `github-operator`, and `config-auditor` to the subagent table.
  - Add a `## Capability Boundary Routing` section before `## Core Workflow`.
  - State that privileged Git, GitHub, and OpenCode home config verification must be dispatched to capability agents instead of requesting direct permission.
  - Change destructive or ambiguous direct command asks to deny: direct main push, force-push, rebase, reset, clean, broad branch delete, broad recursive removal, sudo, su, doas, apt, apt-get, dnf, pacman, and brew.
  - Remove supervisor direct `gh pr create`, `gh pr merge`, `gh run list`, and `gh run watch` allows; those belong to `github-operator`.
  - Keep reviewer, implementer, and web-researcher role boundaries unchanged.

- [ ] **Step 8: Update finishing/daily/weekly skills to use capability agents**

  Modify:
  - `.opencode/skills/finishing-a-development-branch/SKILL.md`
  - `.opencode/skills/daily-devlog-automation/SKILL.md`
  - `.opencode/skills/weekly-agent-workflow-automation/SKILL.md`

  Required wording:
  - Safe base update and push steps dispatch `git-integrator`.
  - PR creation, protection checks, auto-merge enablement, and merge-queue polling dispatch `github-operator`.
  - OpenCode config verification, when needed, dispatches `config-auditor`.
  - If a capability wrapper returns `human_decision_required`, the supervisor reports `HUMAN_DECISION_REQUIRED` with wrapper evidence and does not ask for a one-off broad command permission.

- [ ] **Step 9: Run focused policy validation**

  ```bash
  python3 -m pytest scripts/tests/test_check_opencode_permissions.py -q
  python3 scripts/check_opencode_permissions.py --repo-root .
  python3 -m json.tool .opencode/opencode.json >/dev/null
  ```

- [ ] **Step 10: Commit Task 3**

  ```bash
  git add .opencode/agents/git-integrator.md .opencode/agents/github-operator.md .opencode/agents/config-auditor.md .opencode/agents/supervisor.md .opencode/skills/finishing-a-development-branch/SKILL.md .opencode/skills/daily-devlog-automation/SKILL.md .opencode/skills/weekly-agent-workflow-automation/SKILL.md scripts/check_opencode_permissions.py scripts/tests/test_check_opencode_permissions.py
  git commit -m "feat(opencode): add capability agents and permission policy checks"
  ```

### Task 4: Weekly Permission Classification and Docs

**Files:**
- Modify: `scripts/weekly_agent_workflow_analyzer.py`
- Modify: `scripts/tests/test_weekly_agent_workflow_analyzer.py`
- Modify: `docs/dev/features/opencode-agent-workflow.md`
- Modify: `docs/dev/features/weekly-agent-workflow-automation.md`

**Interfaces:**
- Consumes:
  - Existing analyzer `analyze(config: AnalyzerConfig) -> dict[str, Any]`
  - Existing sanitized excerpts and findings flow.
- Produces:
  - `classify_permission_friction(text: str) -> list[str]`
  - Permission finding payloads with `classes: dict[str, int]` and `session_refs_by_class: dict[str, list[str]]`
  - Docs for capability model and permission-friction classes.

- [ ] **Step 1: Add analyzer classification tests**

  Extend `scripts/tests/test_weekly_agent_workflow_analyzer.py` with tests asserting:
  - Permission text mentioning denied `make test`, `pytest`, `ctest`, `git status`, or `git diff` classifies as `routine-project-scoped`.
  - Permission text mentioning denied `git fetch origin main`, `git merge --no-edit origin/main`, `git push origin HEAD:refs/heads/feature/x`, `gh pr create`, `gh pr view`, `gh pr merge --auto`, `gh run list`, or `gh run watch` classifies as `privileged-bounded`.
  - Permission text mentioning reviewer edit/bash, implementer push/external, or web-researcher local read/bash classifies as `role-mismatch`.
  - Permission text mentioning force-push, rebase, reset, clean, `rm -rf`, sudo/package manager, direct `origin/main` push, auth files, tokens, or broad home/root access classifies as `destructive-ambiguous`.
  - A permission-friction finding includes `classes` and `session_refs_by_class`.
  - Serialized analyzer output still redacts secrets and raw session IDs.

- [ ] **Step 2: Run analyzer tests and confirm they fail before implementation**

  ```bash
  python3 -m pytest scripts/tests/test_weekly_agent_workflow_analyzer.py -q
  ```

- [ ] **Step 3: Implement permission classification**

  In `scripts/weekly_agent_workflow_analyzer.py`:
  - Add `PERMISSION_CLASS_PATTERNS` for the four class IDs: `routine-project-scoped`, `privileged-bounded`, `role-mismatch`, and `destructive-ambiguous`.
  - Add `classify_permission_friction(text: str) -> list[str]`.
  - Treat a general permission prompt with no specific match as `destructive-ambiguous` because it is ambiguous and should fail closed.
  - Extend `_findings` so the existing `permission-friction` finding includes class counts and session refs by class.
  - Preserve all existing redaction and bounded excerpt behavior.

- [ ] **Step 4: Document the capability model**

  Update `docs/dev/features/opencode-agent-workflow.md` with a `## Permission capability model` section covering:
  - Routine project-scoped operations stay with normal agents.
  - Privileged bounded operations go through `git-integrator`, `github-operator`, or `config-auditor`.
  - Role-breaking and destructive/ambiguous operations remain denied and surface as `HUMAN_DECISION_REQUIRED`.
  - Wrapper commands and their JSON evidence are the reviewable handoff.
  - OpenCode must be restarted after `.opencode/**` changes.

- [ ] **Step 5: Document weekly permission-friction classes**

  Update `docs/dev/features/weekly-agent-workflow-automation.md` with:
  - The four permission-friction classes.
  - A note that weekly reports use sanitized analyzer evidence only.
  - A note that raw OpenCode database rows, raw logs, raw tool-output dumps, and credential/auth files remain out of bounds.

- [ ] **Step 6: Run focused validation**

  ```bash
  python3 -m pytest scripts/tests/test_weekly_agent_workflow_analyzer.py -q
  python3 scripts/check_opencode_permissions.py --repo-root .
  rg -n "Permission capability model|permission-friction classes|OpenCode must be restarted|HUMAN_DECISION_REQUIRED" docs/dev/features/opencode-agent-workflow.md docs/dev/features/weekly-agent-workflow-automation.md
  ```

- [ ] **Step 7: Run complete relevant local validation**

  ```bash
  python3 -m pytest scripts/tests/test_opencode_capabilities.py scripts/tests/test_opencode_git_integrate.py scripts/tests/test_opencode_pr_operator.py scripts/tests/test_check_opencode_permissions.py scripts/tests/test_weekly_agent_workflow_analyzer.py -q
  python3 scripts/check_opencode_permissions.py --repo-root .
  python3 -m json.tool .opencode/opencode.json >/dev/null
  git diff --check origin/main...HEAD
  ```

- [ ] **Step 8: Commit Task 4**

  ```bash
  git add scripts/weekly_agent_workflow_analyzer.py scripts/tests/test_weekly_agent_workflow_analyzer.py docs/dev/features/opencode-agent-workflow.md docs/dev/features/weekly-agent-workflow-automation.md
  git commit -m "feat(scripts): classify OpenCode permission friction"
  ```
