# OpenCode CI Diagnostics Tooling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve guarded OpenCode tooling so failed CI logs are diagnosable and Windows CI repro can bootstrap repo-local vcpkg without sudo when host tools already exist.

**Architecture:** Keep GitHub and Windows repro operations behind existing Python capability wrappers. `poll_merge_queue` stays bounded by default but adds automatic `[FAIL]` marker evidence; explicit PR-operator log commands provide tail, slice, literal search, full output, and repo-local failed-log bundles. Windows repro gains a non-sudo `bootstrap-vcpkg` command plus categorized preflight evidence so local-vcpkg-only gaps do not require system setup.

**Tech Stack:** Python 3 stdlib, GitHub CLI `gh`, pytest, OpenCode agent markdown permissions, repo-local shell scripts.

## Global Constraints

- Do not grant raw `gh`, `sudo`, `apt-get`, package-manager, or broad shell permissions to any agent.
- Do not change GitHub Actions workflow definitions in this slice.
- Do not implement Windows system package provisioning without `setup-host`.
- Do not allow `bootstrap-vcpkg` to write to an arbitrary external `VCPKG_ROOT`.
- Do not add regex search to restricted agent commands; literal search is enough and safer for logs.
- Do not solve the current PR #191 Windows failure by guessing. The tooling fix should produce the evidence needed for the next diagnostic step.
- Keep wrapper responses structured as JSON with `status`, `action`, `message`, and `evidence`.
- OpenCode agent/config changes require users to restart OpenCode before a running session can use new permissions.

---

## File Structure

- Modify `scripts/opencode_pr_operator.py`: add log slicing/search/full helpers, automatic `[FAIL]` marker extraction for failed checks, `actions-log` CLI command, and `failed-actions-log-bundle-current` CLI command.
- Modify `scripts/tests/test_opencode_pr_operator.py`: add unit coverage for marker extraction, log modes, invalid arguments, and bundle output.
- Modify `scripts/opencode_windows_ci_repro.py`: add categorized preflight evidence and `bootstrap-vcpkg` CLI command.
- Modify `scripts/tests/test_opencode_windows_ci_repro.py`: add unit coverage for local-vcpkg-only preflight and bootstrap paths.
- Modify `.opencode/agents/github-operator.md`: allow only the exact failed-log bundle command.
- Modify `.opencode/agents/windows-ci-reproducer.md`: allow only the exact vcpkg bootstrap command in addition to existing Windows repro commands.
- Modify `scripts/check_opencode_permissions.py`: require/permit the new exact guarded commands and reject broad unsafe log permissions.
- Modify `scripts/tests/test_check_opencode_permissions.py`: add permission checker coverage.
- Modify `.opencode/skills/github-workflow-debug/SKILL.md`, `.opencode/skills/space-testing-runtime/SKILL.md`, and `.opencode/skills/finishing-a-development-branch/SKILL.md`: mention safe log bundle and vcpkg bootstrap paths where relevant.
- Modify `docs/dev/features/opencode-agent-workflow.md`: document guarded CI log diagnostics.
- Modify `docs/dev/notes/windows-wine-build-and-test.md`: document non-sudo vcpkg bootstrap.

---

### Task 1: PR Operator Log Diagnostics

**Files:**
- Modify: `scripts/opencode_pr_operator.py`
- Test: `scripts/tests/test_opencode_pr_operator.py`

**Interfaces:**
- Consumes: existing `run_command(["gh", "run", "view", run_id, "--job", job_id, "--log"], repo, check=False)` behavior.
- Produces:
  - `actions_log(repo_root: Path, run_id: str, job_id: str, *, tail_lines: int | None, start_line: int | None, line_count: int | None, contains: str | None, context_lines: int, max_matches: int, full: bool) -> dict[str, object]`
  - `failed_actions_log_bundle_current(repo_root: Path) -> dict[str, object]`
  - `failure_markers` field on failed-check evidence returned by `poll_merge_queue`.
  - CLI: `python3 scripts/opencode_pr_operator.py actions-log --repo-root . --run-id <id> --job-id <id> [--tail-lines N | --start-line N --line-count M | --contains TEXT --context-lines N --max-matches M | --full]`
  - CLI: `python3 scripts/opencode_pr_operator.py failed-actions-log-bundle-current --repo-root .`

- [ ] **Step 1: Add failing tests for automatic `[FAIL]` markers**

  In `scripts/tests/test_opencode_pr_operator.py`, add a test named `test_poll_merge_queue_failed_check_includes_fail_markers_outside_tail`. Construct a fake log with more than `MAX_FAILED_CHECK_LOG_LINES` lines where these lines are earlier than the tail:

  ```text
  setup
  [FAIL] recurrence windows boundary
  expected Tuesday, got Monday
  ...many filler lines...
  Lua error: lua: error: tests/runner.fnl:397: 1 Lua test(s) failed
  ```

  Assert that `poll_merge_queue(...)` still includes `log_excerpt`, and that `failed_check["failure_markers"]` contains an entry with:

  ```python
  {
      "line": 2,
      "match": "[FAIL] recurrence windows boundary",
      "context": ["setup", "[FAIL] recurrence windows boundary", "expected Tuesday, got Monday"],
  }
  ```

- [ ] **Step 2: Add failing tests for explicit log modes**

  Add tests that call `pr_operator.actions_log(...)` directly:

  ```python
  result = pr_operator.actions_log(trusted_repo, "123", "456", tail_lines=2, start_line=None, line_count=None, contains=None, context_lines=2, max_matches=20, full=False)
  assert result["evidence"]["mode"] == "tail"
  assert result["evidence"]["log"] == "line4\nline5"

  result = pr_operator.actions_log(trusted_repo, "123", "456", tail_lines=None, start_line=2, line_count=2, contains=None, context_lines=2, max_matches=20, full=False)
  assert result["evidence"]["mode"] == "slice"
  assert result["evidence"]["start_line"] == 2
  assert result["evidence"]["log"] == "line2\nline3"

  result = pr_operator.actions_log(trusted_repo, "123", "456", tail_lines=None, start_line=None, line_count=None, contains="[FAIL]", context_lines=1, max_matches=2, full=False)
  assert result["evidence"]["mode"] == "search"
  assert result["evidence"]["matches"][0]["match"] == "[FAIL] bad test"

  result = pr_operator.actions_log(trusted_repo, "123", "456", tail_lines=None, start_line=None, line_count=None, contains=None, context_lines=2, max_matches=20, full=True)
  assert result["evidence"]["mode"] == "full"
  assert result["evidence"]["log"] == full_log_without_nuls
  ```

  Add invalid-bound tests proving non-digit run/job ids, `start_line < 1`, `line_count < 1`, `tail_lines < 1`, `context_lines < 0`, and `max_matches < 1` return structured `status == "fail"` with a specific code in evidence.

- [ ] **Step 3: Add failing tests for failed-log bundle output**

  Add a test named `test_failed_actions_log_bundle_current_writes_full_logs_and_markers`. Fake `gh pr view <current-branch>` to return a failed check with a parseable Actions URL and fake `gh run view --log` to return a log containing `[FAIL]`. Assert:

  - status is `pass`;
  - evidence includes one `logs` entry;
  - the entry has `run_id`, `job_id`, `path` equal to `build/opencode/actions-logs/<run>-<job>.log`;
  - the file is written under the repo with the full log;
  - the entry includes `failure_markers`.

- [ ] **Step 4: Implement shared log helpers**

  In `scripts/opencode_pr_operator.py`, implement helper functions:

  ```python
  def _valid_numeric_id(value: str) -> bool: ...
  def _clean_log_text(text: str) -> str: ...
  def _line_slice(lines: list[str], start_line: int, line_count: int) -> tuple[str, int, int]: ...
  def _search_log_lines(lines: list[str], contains: str, context_lines: int, max_matches: int) -> list[dict[str, object]]: ...
  def _fail_markers(log_text: str) -> list[dict[str, object]]: ...
  def _fetch_actions_log(repo: Path, run_id: str, job_id: str) -> tuple[str | None, dict[str, object] | None]: ...
  ```

  Use literal substring search for `contains`. Strip NUL bytes. Keep default/tail/search/slice output bounded by existing constants unless `full=True` is explicitly requested or a full bundle is written to disk.

- [ ] **Step 5: Wire markers into failed-check evidence**

  Update `_failed_check_evidence` so when `gh run view --log` succeeds it returns both:

  ```python
  evidence["log_excerpt"] = _bounded_log_excerpt(log_text)
  evidence["failure_markers"] = _fail_markers(log_text)
  ```

  Omit `failure_markers` or return an empty list only when no marker exists; do not enlarge `log_excerpt`.

- [ ] **Step 6: Add CLI commands**

  Extend `_parse_args` and `main` with `actions-log` and `failed-actions-log-bundle-current`. Keep `actions-log` argument combinations explicit:

  - `--full` cannot combine with `--tail-lines`, `--start-line`, `--line-count`, or `--contains`.
  - `--contains` cannot combine with `--start-line`, `--line-count`, or `--tail-lines`.
  - `--start-line` requires `--line-count`.
  - default mode is `--tail-lines MAX_FAILED_CHECK_LOG_LINES`.

- [ ] **Step 7: Run focused tests and commit**

  Run:

  ```bash
  python3 -m pytest scripts/tests/test_opencode_pr_operator.py -q
  git diff --check
  ```

  Expected: pass.

  Commit:

  ```bash
  git add scripts/opencode_pr_operator.py scripts/tests/test_opencode_pr_operator.py
  git commit -m "feat(scripts): add guarded CI log diagnostics"
  ```

---

### Task 2: Windows Repro Non-Sudo vcpkg Bootstrap

**Files:**
- Modify: `scripts/opencode_windows_ci_repro.py`
- Test: `scripts/tests/test_opencode_windows_ci_repro.py`

**Interfaces:**
- Consumes: existing `preflight(repo_root: Path) -> dict[str, object]`.
- Produces:
  - `bootstrap_vcpkg(repo_root: Path) -> dict[str, object]`
  - CLI: `python3 scripts/opencode_windows_ci_repro.py bootstrap-vcpkg --repo-root .`
  - Preflight evidence key `missing_by_category`.

- [ ] **Step 1: Add failing tests for preflight categorization**

  In `scripts/tests/test_opencode_windows_ci_repro.py`, add `test_preflight_reports_local_vcpkg_bootstrap_when_only_vcpkg_missing`. Arrange all required tools/scripts/wine/rust target present, no `VCPKG_ROOT`, and no `repo/vcpkg/vcpkg`. Assert:

  ```python
  assert result["status"] == "fail"
  assert result["evidence"]["code"] == "missing_local_vcpkg"
  assert result["evidence"]["missing_by_category"]["vcpkg"] == ["vcpkg/vcpkg"]
  assert result["evidence"]["bootstrap_vcpkg_command"] == "python3 scripts/opencode_windows_ci_repro.py bootstrap-vcpkg --repo-root ."
  assert "setup_capability_command" not in result["evidence"]
  ```

  Update the existing missing-prerequisites test to assert system-tool gaps still return `missing_windows_ci_repro_prerequisites` and include `setup_capability_command`.

- [ ] **Step 2: Add failing tests for bootstrap-vcpkg**

  Add tests for these cases:

  - missing `repo/vcpkg/` runs:
    ```python
    ["git", "clone", "--branch", "2025.03.19", "https://github.com/microsoft/vcpkg", str(repo / "vcpkg")]
    [str(repo / "vcpkg" / "bootstrap-vcpkg.sh")]
    ```
  - existing `repo/vcpkg/` without binary runs only bootstrap;
  - existing executable `repo/vcpkg/vcpkg` returns pass without commands;
  - `VCPKG_ROOT` set to a path outside the repo returns `human_decision_required` with code `external_vcpkg_root_not_bootstrapped`.

- [ ] **Step 3: Implement preflight categorization**

  Preserve the existing `missing` list. Add:

  ```python
  missing_by_category = {
      "system_tools": [],
      "scripts": [],
      "vcpkg": [],
      "wine": [],
      "rust_targets": [],
  }
  ```

  Put required command gaps in `system_tools`, missing scripts in `scripts`, missing vcpkg binary in `vcpkg`, missing Wine in `wine`, and missing Rust target in `rust_targets`. When the only missing item is default repo-local `vcpkg/vcpkg`, return `failure(..., evidence={"code": "missing_local_vcpkg", "bootstrap_vcpkg_command": ...})`.

- [ ] **Step 4: Implement `bootstrap_vcpkg`**

  Add:

  ```python
  VCPKG_BRANCH = "2025.03.19"
  _BOOTSTRAP_VCPKG_COMMAND = "python3 scripts/opencode_windows_ci_repro.py bootstrap-vcpkg --repo-root ."
  ```

  `bootstrap_vcpkg(repo_root)` must:

  - call `ensure_space_repo`;
  - resolve the default repo-local vcpkg root;
  - if `VCPKG_ROOT` is set and does not resolve under the repo, return `human_decision_required`;
  - if `<root>/vcpkg` already exists, return `pass` with no command calls;
  - if root directory is absent, run `git clone --branch 2025.03.19 https://github.com/microsoft/vcpkg <root>`;
  - if binary is still missing, run `<root>/bootstrap-vcpkg.sh`;
  - return structured failure evidence for clone/bootstrap failures using `_command_evidence`.

  Do not call `sudo`, `apt-get`, or `scripts/setup-windows-build-host.sh`.

- [ ] **Step 5: Wire CLI parsing**

  Add `bootstrap-vcpkg` to `_parse_args` and dispatch it in `main`. Preserve return code mapping.

- [ ] **Step 6: Run focused tests and commit**

  Run:

  ```bash
  python3 -m pytest scripts/tests/test_opencode_windows_ci_repro.py -q
  git diff --check
  ```

  Expected: pass.

  Commit:

  ```bash
  git add scripts/opencode_windows_ci_repro.py scripts/tests/test_opencode_windows_ci_repro.py
  git commit -m "feat(scripts): bootstrap Windows repro vcpkg locally"
  ```

---

### Task 3: OpenCode Permissions and Workflow Docs

**Files:**
- Modify: `.opencode/agents/github-operator.md`
- Modify: `.opencode/agents/windows-ci-reproducer.md`
- Modify: `.opencode/skills/github-workflow-debug/SKILL.md`
- Modify: `.opencode/skills/space-testing-runtime/SKILL.md`
- Modify: `.opencode/skills/finishing-a-development-branch/SKILL.md`
- Modify: `scripts/check_opencode_permissions.py`
- Test: `scripts/tests/test_check_opencode_permissions.py`
- Modify: `docs/dev/features/opencode-agent-workflow.md`
- Modify: `docs/dev/notes/windows-wine-build-and-test.md`

**Interfaces:**
- Consumes: Task 1 `failed-actions-log-bundle-current` command.
- Consumes: Task 2 `bootstrap-vcpkg` command.
- Produces: exact OpenCode permissions and docs for the new guarded commands.

- [ ] **Step 1: Add failing permission-check tests**

  In `scripts/tests/test_check_opencode_permissions.py`, update expected allowlists and add assertions that:

  - `github-operator.md` must allow exactly:
    `python3 scripts/opencode_pr_operator.py failed-actions-log-bundle-current --repo-root .`
  - `windows-ci-reproducer.md` must allow exactly:
    `python3 scripts/opencode_windows_ci_repro.py bootstrap-vcpkg --repo-root .`
  - A wildcard permission such as `python3 scripts/opencode_pr_operator.py actions-log --repo-root . --run-id * --job-id * --full` is rejected for `github-operator` unless the checker explicitly allows a future reviewed shape.

- [ ] **Step 2: Update permission checker**

  In `scripts/check_opencode_permissions.py`, add the exact new allowed commands to the relevant allowlist. Keep `actions-log` out of the restricted agent allowlist. Ensure existing unsafe wildcard detection still flags raw `gh`, broad PR-operator, and broad Windows repro permissions.

- [ ] **Step 3: Update OpenCode agent files**

  In `.opencode/agents/github-operator.md`, add the exact bundle command under `permission.bash`. In `.opencode/agents/windows-ci-reproducer.md`, add exact `bootstrap-vcpkg` command.

  Do not add broad command globs.

- [ ] **Step 4: Update OpenCode skill text**

  Update skill text so future supervisors know:

  - if `poll_merge_queue` evidence lacks enough log details, dispatch `github-operator` to run `failed-actions-log-bundle-current`;
  - if Windows repro preflight returns `missing_local_vcpkg`, dispatch `windows-ci-reproducer` or run the guarded `bootstrap-vcpkg` path before `setup-host`;
  - `.opencode/**` changes require restarting OpenCode.

- [ ] **Step 5: Update developer docs**

  In `docs/dev/features/opencode-agent-workflow.md`, document guarded CI log diagnostics and repo-local log bundle paths under `build/opencode/actions-logs/`. In `docs/dev/notes/windows-wine-build-and-test.md`, document `bootstrap-vcpkg`, when it is safe, and when `setup-host` remains required.

- [ ] **Step 6: Run focused tests and commit**

  Run:

  ```bash
  python3 -m pytest scripts/tests/test_check_opencode_permissions.py -q
  python3 -m pytest scripts/tests/test_opencode_pr_operator.py scripts/tests/test_opencode_windows_ci_repro.py scripts/tests/test_check_opencode_permissions.py -q
  git diff --check
  ```

  Expected: pass.

  Commit:

  ```bash
  git add .opencode/agents/github-operator.md .opencode/agents/windows-ci-reproducer.md .opencode/skills/github-workflow-debug/SKILL.md .opencode/skills/space-testing-runtime/SKILL.md .opencode/skills/finishing-a-development-branch/SKILL.md scripts/check_opencode_permissions.py scripts/tests/test_check_opencode_permissions.py docs/dev/features/opencode-agent-workflow.md docs/dev/notes/windows-wine-build-and-test.md
  git commit -m "chore(opencode): allow guarded CI diagnostics"
  ```

---

## Final Review and Validation

After Task 3 passes review, run final whole-branch review. Required final validation before integration:

```bash
python3 -m pytest scripts/tests/test_opencode_pr_operator.py scripts/tests/test_opencode_windows_ci_repro.py scripts/tests/test_check_opencode_permissions.py -q
python3 -m pytest scripts/tests -q
python3 scripts/opencode_pr_operator.py actions-log --repo-root . --run-id 36468645616 --job-id 109097138152 --contains "[FAIL]" --context-lines 2 --max-matches 10
python3 scripts/opencode_windows_ci_repro.py preflight --repo-root .
git diff --check
```

The `actions-log` command may return `human_decision_required` or `fail` if GitHub log access is unavailable, but it must return structured JSON without traceback. `preflight` may still fail if local vcpkg or system prerequisites are missing, but it must categorize the gap and provide the correct remediation command.

Then use the finishing-a-development-branch workflow: clean tree, current `origin/main`, push, PR, auto-merge/merge queue, and poll until merged.
