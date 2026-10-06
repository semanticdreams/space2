# Fast-Dev Local Main Wrap-Up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a guarded local-`main` wrap-up path that converts reviewed fast-dev commits on local `main` into a deterministic feature branch before any push or PR integration.

**Architecture:** Extend the existing Python Git capability wrapper with one bounded command, `create-local-main-wrapup-branch`, and expose only that exact command through `git-integrator`. Update supervisor/finishing/fast-dev instructions and workflow docs so local-`main` work always routes through feature-branch conversion, strict validation, PR creation, and merge-queue polling.

**Tech Stack:** Python 3, argparse/json CLI wrappers, pytest, OpenCode agent/skill Markdown, repository permission checker, `docs/dev` workflow documentation.

## Global Constraints

- Preserve fast interactive development on a local `main` branch.
- Preserve hierarchical review loops during development: every repository mutation still routes through `implementer` -> `reviewer` -> pass.
- Preserve proper project commits for accepted changes.
- Convert reviewed local-main work into a feature branch before integration.
- Reuse the strict supervisor finishing flow for final validation, PR creation, auto-merge, and merge-queue polling.
- Support vertical-slice handoff from `fast-dev` to strict supervisor for larger follow-on work.
- Do not allow direct pushes to `origin/main`.
- Do not allow `fast-dev` to run raw privileged Git or GitHub commands.
- Do not replace the strict supervisor as final integration authority.
- Do not rebase, reset, force-push, clean, or delete branches.
- Do not automatically merge local `main` into remote `main`.
- Do not weaken the existing implementer/reviewer gate.
- Use deterministic branch naming: `fast-dev/local-main-<short-head-sha>`.
- Defer optional topic support; no topic parameter is added in this implementation.
- The wrapper must fetch `origin/main`, compare current local `main` `HEAD` against current `origin/main`, create the branch at current `HEAD`, and not push or merge.
- The wrapper must refuse dirty worktree, detached HEAD, non-`main` branch, no local commits beyond `origin/main`, existing target local/remote, unsafe target, and fetch/compare inability.
- OpenCode users must restart after `.opencode/**` changes.

---

### Task 1: Guarded Local-Main Wrap-Up Wrapper

**Files:**
- Modify: `scripts/opencode_git_integrate.py`
- Test: `scripts/tests/test_opencode_git_integrate.py`

**Interfaces:**
- Consumes: existing `ensure_space_repo(repo_root: Path) -> Path`, `run_command(args, cwd, check=True) -> CommandResult`, `validate_branch_name(branch: str) -> str`, `_dirty_output(repo: Path) -> str`, `_current_branch(repo: Path) -> str`, `_local_branch_exists(repo: Path, branch: str) -> bool`, `_remote_branch_exists(repo: Path, branch: str) -> bool`.
- Produces:
  - `_derive_local_main_wrapup_branch_name(short_head_sha: str) -> str`
  - `_local_commits_beyond_origin_main(repo: Path) -> int`
  - `create_local_main_wrapup_branch(repo_root: Path) -> dict[str, object]`
  - CLI subcommand: `create-local-main-wrapup-branch --repo-root <path>`
  - JSON success evidence keys: `source_branch`, `wrapup_branch`, `short_head_sha`, `source_head_sha`, `origin_main_sha`, `local_commits_beyond_origin_main`, `args`.

- [ ] **Step 1: Strengthen the test runner helper to support checked command failures**

  In `scripts/tests/test_opencode_git_integrate.py`, update `GitRunner.__call__` so checked nonzero `CommandResult` values raise `CapabilityError`, while `check=False` still returns the result:

  ```python
  if isinstance(output, capabilities.CommandResult):
      if check and output.returncode != 0:
          raise capabilities.CapabilityError(
              "command_failed",
              "Command failed while evaluating capability guard",
              {"args": output.args, "returncode": output.returncode, "stderr": output.stderr.strip()},
          )
      return output
  ```

  Run:

  ```bash
  python3 -m pytest scripts/tests/test_opencode_git_integrate.py -q
  ```

  Expected: existing tests still pass.

- [ ] **Step 2: Add failing tests for deterministic branch naming and successful conversion**

  Add tests requiring:

  ```python
  def test_derive_local_main_wrapup_branch_name_uses_fast_dev_local_main_prefix() -> None:
      assert git_integrate._derive_local_main_wrapup_branch_name("caad43f") == "fast-dev/local-main-caad43f"
  ```

  And a happy-path wrapper test where:
  - current branch is `main`
  - worktree is clean
  - wrapper fetches `origin/main`
  - `origin/main..HEAD` has local commits
  - local and remote target branches are absent
  - wrapper runs only `git switch -c fast-dev/local-main-caad43f`
  - wrapper does not push, merge, rebase, reset, clean, or delete.

  Required command order:

  ```python
  [
      ["git", "status", "--porcelain"],
      ["git", "branch", "--show-current"],
      ["git", "fetch", "origin", "main"],
      ["git", "rev-parse", "--short=7", "HEAD"],
      ["git", "rev-parse", "HEAD"],
      ["git", "rev-parse", "origin/main"],
      ["git", "rev-list", "--count", "origin/main..HEAD"],
      ["git", "show-ref", "--verify", "--quiet", "refs/heads/fast-dev/local-main-caad43f"],
      ["git", "ls-remote", "--exit-code", "--heads", "origin", "fast-dev/local-main-caad43f"],
      ["git", "switch", "-c", "fast-dev/local-main-caad43f"],
  ]
  ```

  Run:

  ```bash
  python3 -m pytest scripts/tests/test_opencode_git_integrate.py::test_derive_local_main_wrapup_branch_name_uses_fast_dev_local_main_prefix scripts/tests/test_opencode_git_integrate.py::test_create_local_main_wrapup_branch_switches_to_deterministic_branch_from_clean_main -q
  ```

  Expected: FAIL because the helper/function/CLI do not exist yet.

- [ ] **Step 3: Add failing refusal tests for all guarded states**

  Add focused tests requiring `create_local_main_wrapup_branch()` to return `human_decision_required` and not run `git switch -c` for:
  - dirty worktree;
  - detached HEAD (`git branch --show-current` returns blank);
  - current branch not `main`;
  - zero local commits from `git rev-list --count origin/main..HEAD`;
  - unsafe derived target branch name via monkeypatching `_derive_local_main_wrapup_branch_name`;
  - local target branch exists;
  - remote target branch exists.

  Add tests requiring status `fail` and no `git switch -c` for:
  - `git fetch origin main` command failure;
  - `git rev-list --count origin/main..HEAD` command failure or unparsable output.

  Run:

  ```bash
  python3 -m pytest scripts/tests/test_opencode_git_integrate.py -q
  ```

  Expected: FAIL only on newly added local-main wrap-up expectations.

- [ ] **Step 4: Add failing CLI test**

  Add a CLI test requiring:

  ```python
  exit_code = git_integrate.main(["create-local-main-wrapup-branch", "--repo-root", str(trusted_repo)])
  payload = json.loads(capsys.readouterr().out)

  assert exit_code == 0
  assert payload["status"] == "pass"
  assert payload["action"] == "create_local_main_wrapup_branch"
  assert payload["evidence"]["wrapup_branch"] == "fast-dev/local-main-caad43f"
  ```

  Run:

  ```bash
  python3 -m pytest scripts/tests/test_opencode_git_integrate.py::test_cli_create_local_main_wrapup_branch_emits_json_and_returns_success -q
  ```

  Expected: FAIL because argparse does not expose the command yet.

- [ ] **Step 5: Implement wrapper helpers and operation**

  In `scripts/opencode_git_integrate.py`, add:

  ```python
  def _derive_local_main_wrapup_branch_name(short_head_sha: str) -> str:
      return f"fast-dev/local-main-{short_head_sha}"


  def _local_commits_beyond_origin_main(repo: Path) -> int:
      raw = run_command(["git", "rev-list", "--count", "origin/main..HEAD"], repo).stdout.strip()
      try:
          return int(raw)
      except ValueError as error:
          raise CapabilityError(
              "command_failed",
              "Command failed while evaluating local-main wrap-up commit range",
              {"args": ["git", "rev-list", "--count", "origin/main..HEAD"], "stdout": raw},
          ) from error
  ```

  Add `create_local_main_wrapup_branch(repo_root: Path) -> dict[str, object]` with these exact guard stages:
  1. `ensure_space_repo`;
  2. reject dirty worktree with `human_decision_required`;
  3. reject detached HEAD with `human_decision_required`;
  4. reject any branch other than `main` with `human_decision_required`;
  5. run `git fetch origin main`;
  6. read short `HEAD`, full `HEAD`, and `origin/main` SHAs;
  7. compute `local_commits_beyond_origin_main`;
  8. reject `0` local commits with `human_decision_required`;
  9. derive `fast-dev/local-main-<short-head-sha>`;
  10. call `validate_branch_name(target_branch)`;
  11. reject existing local target;
  12. reject existing remote target;
  13. run `git switch -c <target_branch>`;
  14. return `success(...)`.

  The implementation must not call `git push`, `git merge`, `git rebase`, `git reset`, `git clean`, `git branch -d`, or `gh`.

- [ ] **Step 6: Wire argparse and operation dispatch**

  Add `create-local-main-wrapup-branch` to `_parse_args()` subcommands and map it in `operations`:

  ```python
  "create-local-main-wrapup-branch": create_local_main_wrapup_branch,
  ```

- [ ] **Step 7: Run focused wrapper validation**

  Run:

  ```bash
  python3 -m pytest scripts/tests/test_opencode_git_integrate.py -q
  ```

  Expected: PASS.

---

### Task 2: Capability Permission Allowlist Exposure

**Files:**
- Modify: `scripts/check_opencode_permissions.py`
- Modify: `scripts/tests/test_check_opencode_permissions.py`
- Modify: `.opencode/agents/git-integrator.md`

**Interfaces:**
- Consumes: Task 1 CLI command `python3 scripts/opencode_git_integrate.py create-local-main-wrapup-branch --repo-root .`.
- Produces: permission checker allowlist and `git-integrator` frontmatter permit exactly that wrapper command and no raw privileged Git/GitHub command.

- [ ] **Step 1: Add failing permission-checker test expectations**

  In `scripts/tests/test_check_opencode_permissions.py`, update all expected git-integrator allowlist sets and test fixture permissions to include exactly:

  ```text
  python3 scripts/opencode_git_integrate.py create-local-main-wrapup-branch --repo-root .
  ```

  Keep existing exact commands unchanged.

  Update tests that inject extra entries by replacing after the new final wrapper command or by appending to the fixture string without removing any required command.

  Run:

  ```bash
  python3 -m pytest scripts/tests/test_check_opencode_permissions.py::test_git_integrator_allows_exact_guarded_git_wrapper_commands scripts/tests/test_check_opencode_permissions.py::test_current_repo_policy_passes_after_task_3_changes -q
  ```

  Expected: FAIL until the checker constant and agent frontmatter are updated.

- [ ] **Step 2: Update checker allowlist**

  In `scripts/check_opencode_permissions.py`, add this exact string to `GIT_INTEGRATOR_ALLOWED_WRAPPER_COMMANDS`:

  ```python
  "python3 scripts/opencode_git_integrate.py create-local-main-wrapup-branch --repo-root .",
  ```

  Do not add wildcard permissions, raw `git switch`, raw `git fetch`, raw `git push`, or any `gh` command.

- [ ] **Step 3: Update git-integrator permission frontmatter**

  In `.opencode/agents/git-integrator.md`, add exactly one allowed bash entry:

  ```yaml
      "python3 scripts/opencode_git_integrate.py create-local-main-wrapup-branch --repo-root .": allow
  ```

  Preserve the leading `"*": deny` rule and existing exact wrapper command rules.

- [ ] **Step 4: Update git-integrator body instructions**

  In `.opencode/agents/git-integrator.md`, document that:
  - `create-local-main-wrapup-branch` is only for clean local `main` with reviewed local commits beyond current `origin/main`;
  - it creates and switches to `fast-dev/local-main-<short-head-sha>`;
  - it does not push or merge;
  - `human_decision_required` evidence must be returned verbatim.

- [ ] **Step 5: Run focused capability validation**

  Run:

  ```bash
  python3 -m pytest scripts/tests/test_check_opencode_permissions.py -q
  python3 scripts/check_opencode_permissions.py --repo-root .
  ```

  Expected: PASS.

---

### Task 3: Supervisor, Fast-Dev, Finishing, and Workflow Documentation

**Files:**
- Modify: `.opencode/agents/fast-dev.md`
- Modify: `.opencode/agents/supervisor.md`
- Modify: `.opencode/skills/finishing-a-development-branch/SKILL.md`
- Modify: `docs/dev/features/opencode-agent-workflow.md`
- Test: `scripts/tests/test_check_opencode_permissions.py`

**Interfaces:**
- Consumes: Task 1 wrapper CLI `create-local-main-wrapup-branch`.
- Consumes: Task 2 `git-integrator` permission and routing.
- Produces: documented local-main wrap-up workflow and vertical-slice handoff contract for agents and humans.

- [ ] **Step 1: Add failing workflow text coverage**

  In `scripts/tests/test_check_opencode_permissions.py`, add a focused test similar to:

  ```python
  def test_local_main_wrapup_and_vertical_slice_handoff_are_documented():
      required = {
          REPO_ROOT / ".opencode" / "agents" / "fast-dev.md": [
              "local `main`",
              "feature branch",
              "strict supervisor",
              "vertical slice handoff",
          ],
          REPO_ROOT / ".opencode" / "agents" / "supervisor.md": [
              "create-local-main-wrapup-branch",
              "fast-dev/local-main-",
              "local `main`",
              "git-integrator",
          ],
          REPO_ROOT / ".opencode" / "skills" / "finishing-a-development-branch" / "SKILL.md": [
              "create-local-main-wrapup-branch",
              "fast-dev/local-main-",
              "local `main`",
              "Do not push",
          ],
          REPO_ROOT / "docs" / "dev" / "features" / "opencode-agent-workflow.md": [
              "Local main wrap-up",
              "create-local-main-wrapup-branch",
              "fast-dev/local-main-<short-head-sha>",
              "Vertical slice handoff",
          ],
      }

      for path, terms in required.items():
          text = path.read_text(encoding="utf-8")
          missing = [term for term in terms if term not in text]
          assert missing == [], f"{path.relative_to(REPO_ROOT)} missing {missing}"
  ```

  Run:

  ```bash
  python3 -m pytest scripts/tests/test_check_opencode_permissions.py::test_local_main_wrapup_and_vertical_slice_handoff_are_documented -q
  ```

  Expected: FAIL until documentation and prompts are updated.

- [ ] **Step 2: Update fast-dev local-main rules**

  In `.opencode/agents/fast-dev.md`, add a section under responsibilities/escalation that states:
  - fast-dev may work on local `main` when the human chooses that workflow;
  - local `main` is a workspace, not an integration target;
  - final wrap-up converts reviewed local-main commits to a feature branch and PR;
  - fast-dev must not push, create PRs, run merge queue, or run raw privileged Git/GitHub;
  - wrap-up/final validation/PR/merge queue requests escalate to strict supervisor;
  - fast-dev should encourage coherent local commits after reviewer pass.

- [ ] **Step 3: Add fast-dev vertical slice handoff template**

  In `.opencode/agents/fast-dev.md`, add a “Vertical slice handoff” subsection requiring the note to include:
  - branch or commit range;
  - problem solved by the vertical slice;
  - current abstraction ownership;
  - validation evidence;
  - design risks already avoided;
  - known limits and proposed expansion seams;
  - whether the slice is ready for PR integration or should become input to a new strict supervisor spec/plan.

- [ ] **Step 4: Update supervisor capability routing and finishing classification**

  In `.opencode/agents/supervisor.md`, update capability routing and finishing discipline so:
  - before push/PR/ready-to-merge, supervisor detects current branch;
  - if current branch is not `main`, existing finishing flow continues;
  - if current branch is `main`, supervisor must not push or create a PR from `main`;
  - supervisor dispatches `git-integrator` for `create-local-main-wrapup-branch`;
  - on wrapper `pass`, supervisor continues normal finishing from the newly created `fast-dev/local-main-<short-head-sha>` branch;
  - on wrapper `human_decision_required` or `fail`, supervisor reports wrapper evidence and does not request raw Git permission.

- [ ] **Step 5: Update finishing skill local-main Step 0/Step 1 flow**

  In `.opencode/skills/finishing-a-development-branch/SKILL.md`, add a local-main conversion step before current-base validation:
  - after clean tree verification, identify branch;
  - if branch is `main`, dispatch `git-integrator create-local-main-wrapup-branch`;
  - do not run push/PR from `main`;
  - if conversion passes, restart finishing from clean-tree/current-base checks on the new feature branch;
  - if no local commits exist, report that there is no local work to wrap up;
  - keep rebase/reset/force-push/clean/delete forbidden.

- [ ] **Step 6: Update developer workflow documentation**

  In `docs/dev/features/opencode-agent-workflow.md`, add focused sections:
  - “Local main wrap-up” under fast interactive development or branch policy;
  - exact wrapper command:
    ```bash
    python3 scripts/opencode_git_integrate.py create-local-main-wrapup-branch --repo-root .
    ```
  - deterministic branch name:
    ```text
    fast-dev/local-main-<short-head-sha>
    ```
  - conversion refuses dirty, detached, non-main, no-local-work, duplicate target, unsafe target, and fetch/compare failure states;
  - after conversion, strict finishing continues with current-base validation, push through `git-integrator`, PR through `github-operator`, and merge-queue polling;
  - “Vertical slice handoff” with the required handoff fields.

- [ ] **Step 7: Run focused docs/prompt validation**

  Run:

  ```bash
  python3 -m pytest scripts/tests/test_check_opencode_permissions.py -q
  rg -n "create-local-main-wrapup-branch|fast-dev/local-main-|Local main wrap-up|Vertical slice handoff" \
    .opencode/agents/fast-dev.md \
    .opencode/agents/supervisor.md \
    .opencode/skills/finishing-a-development-branch/SKILL.md \
    docs/dev/features/opencode-agent-workflow.md
  ```

  Expected: pytest PASS and `rg` shows the required workflow terms in the intended files.

---

### Task 4: Integrated OpenCode Workflow Validation

**Files:**
- Modify: none expected beyond Tasks 1–3.
- Test: repository OpenCode workflow checks.

**Interfaces:**
- Consumes: wrapper implementation, permission allowlist, prompt updates, docs updates.
- Produces: final local validation evidence for the implementation branch.

- [ ] **Step 1: Run focused wrapper and permission tests**

  ```bash
  python3 -m pytest scripts/tests/test_opencode_git_integrate.py scripts/tests/test_check_opencode_permissions.py -q
  ```

  Expected: PASS.

- [ ] **Step 2: Run canonical OpenCode check**

  ```bash
  make opencode-check
  ```

  Expected: PASS.

- [ ] **Step 3: Run focused text safety checks**

  Confirm the exact wrapper command is documented and allowed:

  ```bash
  rg -n "python3 scripts/opencode_git_integrate.py create-local-main-wrapup-branch --repo-root \." \
    .opencode/agents/git-integrator.md \
    scripts/check_opencode_permissions.py \
    scripts/tests/test_check_opencode_permissions.py \
    docs/dev/features/opencode-agent-workflow.md
  ```

  Confirm raw direct main push is not added as an allowed permission:

  ```bash
  python3 - <<'PY'
  from pathlib import Path

  paths = [
      Path(".opencode/agents/git-integrator.md"),
      Path(".opencode/agents/fast-dev.md"),
  ]
  forbidden_allowed = [
      '"git push origin main": allow',
      '"git push origin HEAD:refs/heads/main": allow',
      '"git push origin HEAD:main": allow',
      '"gh *": allow',
      '"git rebase*": allow',
      '"git reset*": allow',
      '"git clean*": allow',
      '"git push *--force*": allow',
  ]
  for path in paths:
      text = path.read_text(encoding="utf-8")
      for needle in forbidden_allowed:
          assert needle not in text, f"{path} unexpectedly allows {needle}"
  PY
  ```

  Expected: both commands PASS.

- [ ] **Step 4: Run whitespace diff check**

  ```bash
  git diff --check
  ```

  Expected: PASS.

- [ ] **Step 5: Document validation scope in the handoff**

  The implementer handoff must state that full app suites are not required because this change is limited to Python OpenCode wrappers, pytest coverage, OpenCode agent/skill prompts, and workflow documentation. PR CI remains the full integration gate.

---

## Acceptance Criteria

- `scripts/opencode_git_integrate.py create-local-main-wrapup-branch --repo-root .` exists and emits structured JSON.
- On clean local `main` with commits beyond current `origin/main`, the wrapper fetches `origin/main`, creates `fast-dev/local-main-<short-head-sha>` at current `HEAD`, switches to it, and does not push or merge.
- The wrapper refuses dirty, detached, non-`main`, no-local-work, unsafe target, duplicate local target, duplicate remote target, and fetch/compare failure states.
- `git-integrator` allows only exact guarded wrapper commands, including the new local-main wrap-up command.
- `fast-dev` documents that local-main work wraps into a feature branch and never directly pushes `origin/main`.
- Supervisor and finishing instructions detect local `main` and convert it before push/PR integration.
- `docs/dev/features/opencode-agent-workflow.md` documents local-main wrap-up and vertical-slice handoff behavior.
- Focused pytest, `make opencode-check`, focused text checks, and `git diff --check` pass.
- PR CI remains the authoritative final integration gate.

## Validation Ladder

1. Focused implementation checks:
   ```bash
   python3 -m pytest scripts/tests/test_opencode_git_integrate.py -q
   python3 -m pytest scripts/tests/test_check_opencode_permissions.py -q
   ```

2. Complete relevant local OpenCode suite:
   ```bash
   make opencode-check
   ```

3. Focused text/format checks:
   ```bash
   rg -n "create-local-main-wrapup-branch|fast-dev/local-main-|Local main wrap-up|Vertical slice handoff" \
     .opencode/agents/fast-dev.md \
     .opencode/agents/supervisor.md \
     .opencode/agents/git-integrator.md \
     .opencode/skills/finishing-a-development-branch/SKILL.md \
     docs/dev/features/opencode-agent-workflow.md

   git diff --check
   ```

4. Broader final checks:
   - Full Space app suites are not required locally because this change does not touch C++, Fennel, runtime initialization, bindings, packaging, or app behavior.
   - **PR CI** is the full integration gate.

## Out of Scope

- Optional topic parameter for branch names.
- Direct push to `origin/main`.
- Raw privileged `git` or `gh` permissions.
- Rebase, reset, force-push, clean, or branch deletion workflows.
- Automatic merge of local `main` into remote `main`.
- Changes to GitHub branch protection or merge queue configuration.
- Full app/runtime test suites for this Python/docs/OpenCode workflow change.
