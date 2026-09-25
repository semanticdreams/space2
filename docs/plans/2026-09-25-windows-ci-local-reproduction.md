# Windows CI Local Reproduction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make OpenCode agents run a guarded Linux cross-build + Wine Windows reproduction loop before pushing fixes for non-infrastructure Windows CI failures.

**Architecture:** Add a narrow Python capability wrapper plus a `windows-ci-reproducer` capability agent. The wrapper runs existing Windows setup/build/package/Wine scripts and emits structured evidence; skills and supervisor instructions route Windows CI failures through that wrapper before another push.

**Tech Stack:** Python 3, pytest, Bash scripts, OpenCode agent/skill Markdown, MinGW/vcpkg Windows cross-build, Wine, GitHub Actions `test.yml`.

## Global Constraints

- Do not rewrite the GitHub Actions Windows workflow.
- Do not replace guarded Git/GitHub capability agents with unrestricted agents.
- Do not make Wine a substitute for native Windows CI.
- Do not add broad `sudo`, package-manager, or raw shell permissions to existing agents.
- Add a guarded Windows CI reproduction capability instead of granting agents broad `sudo`, package-manager, GitHub, or shell access.
- The capability exposes exactly three operations: `preflight`, `setup-host`, and `reproduce`.
- Agents must use this capability when Windows CI jobs fail and the failure is not obviously CI infrastructure-only.
- The wrapper returns structured JSON with `status`, `action`, `message`, and `evidence`.
- Native Windows CI remains authoritative for Windows-host-only behavior, installer behavior, and final integration.
- OpenCode users must restart after `.opencode/**` changes.

---

### Task 1: Windows CI Reproduction Wrapper

**Files:**
- Create: `scripts/opencode_windows_ci_repro.py`
- Create: `scripts/tests/test_opencode_windows_ci_repro.py`

**Interfaces:**
- Consumes:
  - `opencode_capabilities.ensure_space_repo(repo_root: Path) -> Path`
  - `opencode_capabilities.run_command(args: Sequence[str], cwd: Path, check: bool = True) -> CommandResult`
  - `opencode_capabilities.success(action: str, message: str, evidence: dict) -> dict`
  - `opencode_capabilities.failure(action: str, message: str, evidence: dict) -> dict`
  - `opencode_capabilities.human_decision(action: str, message: str, evidence: dict) -> dict`
- Produces:
  - `preflight(repo_root: Path) -> dict[str, object]`
  - `setup_host(repo_root: Path) -> dict[str, object]`
  - `reproduce(repo_root: Path) -> dict[str, object]`
  - CLI: `python3 scripts/opencode_windows_ci_repro.py preflight --repo-root .`
  - CLI: `python3 scripts/opencode_windows_ci_repro.py setup-host --repo-root .`
  - CLI: `python3 scripts/opencode_windows_ci_repro.py reproduce --repo-root .`
  - Exit code mapping: `pass=0`, `human_decision_required=2`, `fail=3`.

- [ ] **Step 1: Write failing preflight tests**

Create `scripts/tests/test_opencode_windows_ci_repro.py` with tests that monkeypatch tool/filesystem checks. Cover:

```python
def test_preflight_passes_when_windows_ci_repro_prerequisites_exist(tmp_path, monkeypatch):
    repo = make_space_repo(tmp_path)
    install_required_scripts(repo)
    install_fake_vcpkg(repo)
    monkeypatch_required_tools_present(monkeypatch)
    monkeypatch_rust_target(monkeypatch, installed=True)

    result = windows_ci_repro.preflight(repo)

    assert result["status"] == "pass"
    assert result["action"] == "preflight"
    assert result["evidence"]["missing"] == []


def test_preflight_fails_with_setup_command_when_prerequisites_missing(tmp_path, monkeypatch):
    repo = make_space_repo(tmp_path)
    install_required_scripts(repo)
    monkeypatch_required_tools_missing(monkeypatch, missing={"wine", "x86_64-w64-mingw32-gcc-posix"})
    monkeypatch_rust_target(monkeypatch, installed=False)

    result = windows_ci_repro.preflight(repo)

    assert result["status"] == "fail"
    assert result["evidence"]["code"] == "missing_windows_ci_repro_prerequisites"
    assert result["evidence"]["setup_capability_command"] == "python3 scripts/opencode_windows_ci_repro.py setup-host --repo-root ."
```

Use local helpers in the test file to create a minimal trusted Space repo with `AGENTS.md`, `.opencode/opencode.json`, and trusted origin metadata following existing capability test patterns.

- [ ] **Step 2: Write failing setup-host tests**

Add tests:

```python
def test_setup_host_requires_linux_ubuntu(tmp_path, monkeypatch):
    repo = make_space_repo(tmp_path)
    install_required_scripts(repo)
    monkeypatch.setattr(windows_ci_repro.sys, "platform", "darwin")

    result = windows_ci_repro.setup_host(repo)

    assert result["status"] == "human_decision_required"
    assert result["evidence"]["code"] == "unsupported_windows_ci_setup_host"


def test_setup_host_runs_existing_setup_script_on_supported_host(tmp_path, monkeypatch):
    repo = make_space_repo(tmp_path)
    install_required_scripts(repo)
    monkeypatch_linux_ubuntu_with_sudo(monkeypatch)
    calls = capture_run_command_calls(monkeypatch, windows_ci_repro)

    result = windows_ci_repro.setup_host(repo)

    assert result["status"] == "pass"
    assert calls == [["scripts/setup-windows-build-host.sh"]]
```

- [ ] **Step 3: Write failing reproduce tests**

Add tests:

```python
def test_reproduce_runs_build_package_verify_and_wine_steps_in_order(tmp_path, monkeypatch):
    repo = make_space_repo(tmp_path)
    install_required_scripts(repo)
    install_fake_windows_outputs(repo)
    monkeypatch_preflight_pass(monkeypatch, windows_ci_repro)
    calls = capture_run_command_calls(monkeypatch, windows_ci_repro)

    result = windows_ci_repro.reproduce(repo)

    assert result["status"] == "pass"
    assert calls == [
        ["scripts/build-windows-from-linux.sh"],
        ["scripts/package-windows-runtime.sh"],
        ["scripts/test-windows-under-wine.sh"],
    ]


def test_reproduce_reports_first_failing_step_with_bounded_output(tmp_path, monkeypatch):
    repo = make_space_repo(tmp_path)
    install_required_scripts(repo)
    monkeypatch_preflight_pass(monkeypatch, windows_ci_repro)
    monkeypatch_run_command_failure(monkeypatch, windows_ci_repro, failing_args=["scripts/package-windows-runtime.sh"])

    result = windows_ci_repro.reproduce(repo)

    assert result["status"] == "fail"
    assert result["evidence"]["failing_step"] == "package-windows-runtime"
    assert result["evidence"]["args"] == ["scripts/package-windows-runtime.sh"]
    assert "stdout_tail" in result["evidence"]
    assert "stderr_tail" in result["evidence"]
```

- [ ] **Step 4: Run tests and verify RED**

Run:

```bash
python3 -m pytest scripts/tests/test_opencode_windows_ci_repro.py -q
```

Expected: fails because `scripts/opencode_windows_ci_repro.py` does not exist.

- [ ] **Step 5: Implement wrapper helpers and response handling**

Create `scripts/opencode_windows_ci_repro.py` with:

```python
REQUIRED_TOOLS = (
    "cmake", "git", "pkg-config", "nasm", "llvm-ml-14", "curl", "zip", "pwsh",
    "autoconf", "x86_64-w64-mingw32-gcc-posix", "x86_64-w64-mingw32-g++-posix", "rustc",
)
REQUIRED_SCRIPTS = (
    "scripts/setup-windows-build-host.sh",
    "scripts/build-windows-from-linux.sh",
    "scripts/package-windows-runtime.sh",
    "scripts/test-windows-under-wine.sh",
)
WINDOWS_RUST_TARGET = "x86_64-pc-windows-gnu"
```

Implement `_exit_code_for`, `_tail`, `_command_evidence`, `_script_exists`, `_wine_available`, `_vcpkg_binary`, `_rust_target_installed`, and `_response` helpers.

- [ ] **Step 6: Implement `preflight`**

Behavior:

- call `ensure_space_repo(repo_root)` first;
- collect missing tools, scripts, vcpkg binary, Wine command, and Rust target;
- return `success("preflight", "Windows CI reproduction prerequisites are available", evidence)` when nothing is missing;
- return `failure("preflight", "Windows CI reproduction prerequisites are missing", evidence)` when anything is missing;
- include `evidence.code == "missing_windows_ci_repro_prerequisites"` and `setup_capability_command` on missing prerequisites.

- [ ] **Step 7: Implement `setup_host`**

Behavior:

- call `ensure_space_repo(repo_root)` first;
- require Linux platform;
- require `/etc/os-release` with `ID=ubuntu`;
- require `sudo` on PATH;
- run exactly `scripts/setup-windows-build-host.sh` through `run_command(["scripts/setup-windows-build-host.sh"], repo, check=False)`;
- return pass on zero, otherwise human decision with command evidence.

- [ ] **Step 8: Implement `reproduce`**

Behavior:

- call `preflight(repo_root)`;
- if preflight is not pass, return that result with action adjusted to `reproduce` and evidence preserved;
- run:
  1. `scripts/build-windows-from-linux.sh`
  2. `scripts/package-windows-runtime.sh`
  3. verify files:
     - `build/dist/windows/space.exe`
     - `build/dist/windows/space-cli.exe`
     - `build/windows/CPackConfig.cmake`
     - `build/windows/space.ico`
     - `scripts/windows-installer.iss`
  4. `scripts/test-windows-under-wine.sh`
- fail on the first failing step with `failing_step`, `args`, `returncode`, `stdout_tail`, and `stderr_tail`.

- [ ] **Step 9: Implement CLI and exit codes**

Add argparse with subcommands `preflight`, `setup-host`, and `reproduce`, each requiring `--repo-root`. Print JSON with sorted keys and exit via `_exit_code_for`.

- [ ] **Step 10: Verify GREEN**

Run:

```bash
python3 -m pytest scripts/tests/test_opencode_windows_ci_repro.py -q
```

Expected: pass.

- [ ] **Step 11: Commit Task 1**

```bash
git add scripts/opencode_windows_ci_repro.py scripts/tests/test_opencode_windows_ci_repro.py
git commit -m "feat(scripts): add guarded Windows CI reproducer"
```

---

### Task 2: Windows CI Reproducer Capability Agent and Static Policy

**Files:**
- Create: `.opencode/agents/windows-ci-reproducer.md`
- Modify: `scripts/check_opencode_permissions.py`
- Modify: `scripts/tests/test_check_opencode_permissions.py`
- Modify: `Makefile`

**Interfaces:**
- Consumes:
  - `python3 scripts/opencode_windows_ci_repro.py preflight --repo-root .`
  - `python3 scripts/opencode_windows_ci_repro.py setup-host --repo-root .`
  - `python3 scripts/opencode_windows_ci_repro.py reproduce --repo-root .`
- Produces:
  - Capability agent `.opencode/agents/windows-ci-reproducer.md`.
  - Static policy checks enforcing only the three wrapper commands.
  - `make opencode-check` includes the new wrapper tests.

- [ ] **Step 1: Write failing static policy tests**

In `scripts/tests/test_check_opencode_permissions.py`, add tests:

```python
def test_windows_ci_reproducer_agent_is_required(repo_copy):
    (repo_copy / ".opencode/agents/windows-ci-reproducer.md").unlink(missing_ok=True)
    result = run_checker(repo_copy)
    assert_has_violation(result, "capability-dependency", ".opencode/agents/windows-ci-reproducer.md")


def test_windows_ci_reproducer_allows_only_wrapper_commands(repo_copy):
    agent = repo_copy / ".opencode/agents/windows-ci-reproducer.md"
    agent.write_text(agent.read_text() + "\n    \"gh *\": allow\n")
    result = run_checker(repo_copy)
    assert_has_violation(result, "capability-boundary", "windows-ci-reproducer")


def test_windows_ci_reproducer_requires_wrapper_script(repo_copy):
    (repo_copy / "scripts/opencode_windows_ci_repro.py").unlink(missing_ok=True)
    result = run_checker(repo_copy)
    assert_has_violation(result, "capability-dependency", "scripts/opencode_windows_ci_repro.py")
```

Match existing helper names in the test file; if names differ, adapt to the established pattern.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
python3 -m pytest scripts/tests/test_check_opencode_permissions.py -q
```

Expected: fails because the capability agent/policy does not exist.

- [ ] **Step 3: Add the capability agent**

Create `.opencode/agents/windows-ci-reproducer.md`:

```markdown
---
description: Runs only guarded Space Windows CI local reproduction wrapper operations for preflight, setup, and Linux cross-build + Wine validation.
mode: subagent
model: openai/gpt-5.5
temperature: 0.1
steps: 30
permission:
  read: deny
  glob: deny
  grep: deny
  list: deny
  lsp: deny
  edit: deny
  task: deny
  external_directory: deny
  webfetch: deny
  websearch: deny
  question: deny
  bash:
    "*": deny
    "python3 scripts/opencode_windows_ci_repro.py preflight --repo-root .": allow
    "python3 scripts/opencode_windows_ci_repro.py setup-host --repo-root .": allow
    "python3 scripts/opencode_windows_ci_repro.py reproduce --repo-root .": allow
---

You are the Windows CI reproduction capability agent. You may run only the
guarded `scripts/opencode_windows_ci_repro.py` wrapper commands explicitly
allowed in your permissions.

Return wrapper JSON evidence verbatim. For normal reproduction requests, run
`preflight` first, then `reproduce` when preflight passes. If reproduction or
preflight reports missing prerequisites, run `setup-host` at most once when the
supervisor requested setup permission through this capability, then rerun
`preflight` and `reproduce`.

Do not run raw `sudo`, package-manager, Wine, GitHub, Git, or broad shell
commands. The wrapper is the only boundary for Windows CI local reproduction.

If a wrapper returns `human_decision_required`, report `HUMAN_DECISION_REQUIRED`
with the wrapper evidence.
```

- [ ] **Step 4: Extend static policy checker**

In `scripts/check_opencode_permissions.py`:

- add `windows-ci-reproducer` to capability-agent expectations;
- require `.opencode/agents/windows-ci-reproducer.md`;
- require `scripts/opencode_windows_ci_repro.py`;
- enforce exact bash allowlist:
  - `python3 scripts/opencode_windows_ci_repro.py preflight --repo-root .`
  - `python3 scripts/opencode_windows_ci_repro.py setup-host --repo-root .`
  - `python3 scripts/opencode_windows_ci_repro.py reproduce --repo-root .`

- [ ] **Step 5: Wire new tests into `make opencode-check`**

In `Makefile`, update the `opencode-check` pytest command to include:

```make
scripts/tests/test_opencode_windows_ci_repro.py
```

- [ ] **Step 6: Verify GREEN**

Run:

```bash
python3 -m pytest scripts/tests/test_check_opencode_permissions.py scripts/tests/test_opencode_windows_ci_repro.py -q
python3 scripts/check_opencode_permissions.py --repo-root .
make opencode-check
```

Expected: all pass.

- [ ] **Step 7: Commit Task 2**

```bash
git add .opencode/agents/windows-ci-reproducer.md scripts/check_opencode_permissions.py scripts/tests/test_check_opencode_permissions.py Makefile
git commit -m "feat(ci): add Windows CI reproducer capability"
```

---

### Task 3: Agent, Skill, and Developer Documentation Routing

**Files:**
- Modify: `.opencode/agents/supervisor.md`
- Modify: `.opencode/skills/finishing-a-development-branch/SKILL.md`
- Modify: `.opencode/skills/github-workflow-debug/SKILL.md`
- Modify: `.opencode/skills/space-testing-runtime/SKILL.md`
- Modify: `docs/dev/features/opencode-agent-workflow.md`
- Modify: `docs/dev/notes/windows-wine-build-and-test.md`
- Create: `scripts/tests/test_opencode_windows_ci_policy_docs.py`
- Modify: `Makefile`

**Interfaces:**
- Consumes: `windows-ci-reproducer` capability agent from Task 2.
- Produces: Tested routing text requiring local Windows reproduction before another push for non-infrastructure Windows CI failures.

- [ ] **Step 1: Write failing documentation/routing tests**

Create `scripts/tests/test_opencode_windows_ci_policy_docs.py` with tests:

```python
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text()


def test_supervisor_routes_windows_ci_failures_to_reproducer():
    text = read(".opencode/agents/supervisor.md")
    assert "windows-ci-reproducer" in text
    assert "build-windows" in text
    assert "test-windows" in text
    assert "build-windows-installer" in text
    assert "not obviously CI infrastructure-only" in text
    assert "Linux cross-build + Wine" in text


def test_finishing_and_github_workflow_debug_require_local_windows_reproduction():
    for path in [
        ".opencode/skills/finishing-a-development-branch/SKILL.md",
        ".opencode/skills/github-workflow-debug/SKILL.md",
    ]:
        text = read(path)
        assert "windows-ci-reproducer" in text
        assert "before pushing another" in text or "before another push" in text
        assert "not obviously CI infrastructure-only" in text


def test_runtime_and_dev_docs_name_wrapper_commands():
    for path in [
        ".opencode/skills/space-testing-runtime/SKILL.md",
        "docs/dev/features/opencode-agent-workflow.md",
        "docs/dev/notes/windows-wine-build-and-test.md",
    ]:
        text = read(path)
        assert "opencode_windows_ci_repro.py" in text
        assert "preflight --repo-root ." in text
        assert "setup-host --repo-root ." in text
        assert "reproduce --repo-root ." in text
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
python3 -m pytest scripts/tests/test_opencode_windows_ci_policy_docs.py -q
```

Expected: fails because routing text does not exist yet.

- [ ] **Step 3: Update supervisor routing**

In `.opencode/agents/supervisor.md`:

- add `windows-ci-reproducer` to the subagent table;
- add a capability-boundary bullet saying dispatch `windows-ci-reproducer` for guarded local Windows CI preflight/setup/reproduction;
- add a Windows CI failure rule:
  - when `build-windows`, `test-windows`, or `build-windows-installer` fails and it is not obviously CI infrastructure-only, dispatch `windows-ci-reproducer` for Linux cross-build + Wine reproduction before pushing another fix;
  - if prerequisites are missing, run guarded setup once through the same capability;
  - if setup/reproduction cannot run safely, report `HUMAN_DECISION_REQUIRED` with wrapper evidence.

- [ ] **Step 4: Update finishing skill**

In `.opencode/skills/finishing-a-development-branch/SKILL.md`, add to PR CI failure handling:

```markdown
For Windows CI failures in `build-windows`, `test-windows`, or
`build-windows-installer` that are not obviously CI infrastructure-only,
dispatch `windows-ci-reproducer` and obtain local Linux cross-build + Wine
reproduction evidence before pushing another fix or requeueing. If prerequisites
are missing, run guarded `setup-host` once through `windows-ci-reproducer`, then
rerun reproduction. Native Windows PR CI remains authoritative.
```

- [ ] **Step 5: Update GitHub workflow debug skill**

In `.opencode/skills/github-workflow-debug/SKILL.md`, add a failed-job branch:

- inspect logs first;
- if Windows job and not obviously CI infrastructure-only, dispatch `windows-ci-reproducer` before the next push;
- run setup-host once when prerequisite evidence requests it;
- do not use raw setup commands.

- [ ] **Step 6: Update space-testing-runtime skill**

Add a Windows CI local reproduction section naming:

```bash
python3 scripts/opencode_windows_ci_repro.py preflight --repo-root .
python3 scripts/opencode_windows_ci_repro.py setup-host --repo-root .
python3 scripts/opencode_windows_ci_repro.py reproduce --repo-root .
```

Mention `docs/dev/notes/windows-wine-build-and-test.md` and that Wine is not native Windows CI.

- [ ] **Step 7: Update developer docs**

In `docs/dev/features/opencode-agent-workflow.md`, add a subsection documenting:

- trigger jobs `build-windows`, `test-windows`, `build-windows-installer`;
- the `windows-ci-reproducer` capability;
- setup-host behavior for first-time machines;
- expected evidence before pushing another fix.

In `docs/dev/notes/windows-wine-build-and-test.md`, add the wrapper command sequence and the limitation that native Windows installer behavior remains CI-covered.

- [ ] **Step 8: Wire docs test into `make opencode-check`**

In `Makefile`, add `scripts/tests/test_opencode_windows_ci_policy_docs.py` to `opencode-check`.

- [ ] **Step 9: Verify GREEN**

Run:

```bash
python3 -m pytest scripts/tests/test_opencode_windows_ci_policy_docs.py -q
make opencode-check
git diff --check
```

Expected: all pass.

- [ ] **Step 10: Commit Task 3**

```bash
git add .opencode/agents/supervisor.md .opencode/skills/finishing-a-development-branch/SKILL.md .opencode/skills/github-workflow-debug/SKILL.md .opencode/skills/space-testing-runtime/SKILL.md docs/dev/features/opencode-agent-workflow.md docs/dev/notes/windows-wine-build-and-test.md scripts/tests/test_opencode_windows_ci_policy_docs.py Makefile
git commit -m "docs(ci): require local Windows CI reproduction"
```

---

## Acceptance Criteria

- A guarded wrapper can preflight, setup, and reproduce Windows CI locally through exact CLI commands.
- A capability agent can run only the exact Windows reproduction wrapper commands.
- Static OpenCode policy checks fail if the capability agent is missing, references a missing wrapper, or gains broad/raw shell permissions.
- Supervisor and relevant skills route non-infrastructure Windows CI failures through local reproduction before another push.
- Docs explain setup path, Wine limitations, and expected evidence.
- `make opencode-check` covers wrapper, capability policy, and instruction/doc routing checks.

## Validation Ladder

1. Wrapper tests:

   ```bash
   python3 -m pytest scripts/tests/test_opencode_windows_ci_repro.py -q
   ```

2. Capability/static policy tests:

   ```bash
   python3 -m pytest scripts/tests/test_check_opencode_permissions.py -q
   ```

3. Routing docs tests:

   ```bash
   python3 -m pytest scripts/tests/test_opencode_windows_ci_policy_docs.py -q
   ```

4. Static permission checker:

   ```bash
   python3 scripts/check_opencode_permissions.py --repo-root .
   ```

5. Aggregate OpenCode check:

   ```bash
   make opencode-check
   ```

6. Diff hygiene:

   ```bash
   git diff --check
   ```

7. Full integration gate: PR CI.

## Out of Scope

- Rewriting `.github/workflows/test.yml`.
- Replacing guarded Git/GitHub agents with unrestricted agents.
- Making Wine a substitute for native Windows CI.
- Adding broad `sudo`, package-manager, or raw shell permissions.
- Running the full Windows cross-build locally as part of every normal PR; it is for Windows CI failure reproduction.

## HUMAN_DECISION_REQUIRED

None expected during implementation. If the actual host setup script cannot safely run through the guarded wrapper on a future machine, the wrapper must report `HUMAN_DECISION_REQUIRED` with evidence.
