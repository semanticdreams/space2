# Stale Merged PR Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically recover from reused-branch stale merged PRs by creating/pushing a deterministic follow-up branch and opening a fresh PR through one guarded recovery capability.

**Architecture:** Keep normal GitHub PR operations in `scripts/opencode_pr_operator.py` and Git mutation in `scripts/opencode_git_integrate.py`. Add a small explicit recovery wrapper that composes those existing guarded functions only for the stale merged PR mismatch case, expose it through a dedicated capability agent, and update supervisor/finishing instructions to dispatch that agent instead of stopping for the human.

**Tech Stack:** Python 3 wrapper scripts and pytest tests, OpenCode project agents/skills under `.opencode/**`, existing Git/GitHub capability wrappers, project workflow documentation.

## Global Constraints

- Add a guarded stale-merged-PR recovery path for OpenCode finishing.
- Recovery verifies the working tree is clean and current with `origin/main`.
- Recovery creates a deterministic follow-up branch from the current head.
- Recovery pushes that fresh branch.
- Recovery creates a new PR for the fresh branch.
- Recovery returns structured evidence for the supervisor to continue normal auto-merge and merge-queue polling.
- Do not hide branch creation or pushing inside the normal GitHub-only `create-current` PR operation.
- Do not broaden Git or GitHub permissions.
- Do not rebase, force-push, reset, delete branches, or push directly to `main`.
- Do not recover ambiguous stale PR states such as open PRs with mismatched heads, closed-unmerged PRs, matching-head merged PRs, dirty worktrees, stale bases, or existing follow-up branch targets.
- Do not move auto-merge or merge-queue polling into the recovery wrapper.
- The recovery capability may orchestrate the single stale-merged-PR recovery case and must expose only one exact command.
- No agent gets raw `git`, raw `gh`, wildcard branch operations, or shell access as part of this change.
- If recovery refuses at any safety gate, the supervisor reports `HUMAN_DECISION_REQUIRED` with the wrapper evidence.

---

## File Structure

- `scripts/opencode_pr_recovery.py`
  - New explicit cross-boundary recovery wrapper for stale merged current-branch PRs.
  - Imports and composes existing guarded wrapper functions instead of adding raw broad Git/GitHub logic.
- `scripts/tests/test_opencode_pr_recovery.py`
  - Unit tests for pass-through, stale merged recovery, and safety-gate refusal behavior.
- `scripts/tests/test_opencode_pr_operator.py`
  - Keeps the existing normal PR wrapper stale-PR refusal test intact so `create-current` stays GitHub-only/non-mutating.
- `.opencode/agents/pr-recovery-operator.md`
  - New capability agent with one exact allowed command.
- `scripts/check_opencode_permissions.py`
  - Capability permission verifier updated for the new agent/file.
- `scripts/tests/test_check_opencode_permissions.py`
  - Tests that recovery permissions are exact and workflow docs point agents at the new automatic recovery path.
- `.opencode/agents/supervisor.md`
  - Supervisor routing updated to dispatch the recovery operator for stale merged PR evidence.
- `.opencode/skills/finishing-a-development-branch/SKILL.md`
  - Finishing flow updated to use the recovery operator instead of manual human-decision handoff.
- `docs/dev/features/opencode-agent-workflow.md`
  - Canonical developer documentation for the recovery command, invariants, and restart requirement.

## Validation Environment

Use repository-root commands. These are script/doc/config changes, so focused Python wrapper tests and permission checks are the primary local validation. OpenCode users must restart after `.opencode/**` changes.

---

### Task 1: Add explicit stale merged PR recovery wrapper

**Files:**
- Create: `scripts/opencode_pr_recovery.py`
- Create: `scripts/tests/test_opencode_pr_recovery.py`
- Test: `scripts/tests/test_opencode_pr_operator.py`
- Test: `scripts/tests/test_opencode_git_integrate.py`

**Interfaces:**
- Consumes: `opencode_pr_operator.create_current_pr(repo_root: Path) -> dict[str, object]`
- Consumes: `opencode_git_integrate.git_status(repo_root: Path) -> dict[str, object]`
- Consumes: `opencode_git_integrate.create_followup_branch(repo_root: Path) -> dict[str, object]`
- Consumes: `opencode_git_integrate.push_current(repo_root: Path) -> dict[str, object]`
- Produces: `recover_merged_current(repo_root: Path) -> dict[str, object]`
- Produces CLI: `python3 scripts/opencode_pr_recovery.py create-current-with-followup-recovery --repo-root .`

- [ ] **Step 1: Add failing tests for pass-through and recovery detection**

Create `scripts/tests/test_opencode_pr_recovery.py` with monkeypatched fake wrapper functions. Include these tests:

```python
from pathlib import Path

import scripts.opencode_pr_recovery as recovery


def test_recovery_passthrough_when_create_current_passes(monkeypatch, tmp_path):
    calls = []
    monkeypatch.setattr(recovery.pr_operator, "create_current_pr", lambda repo: {"status": "pass", "url": "https://example/pr/1"})
    monkeypatch.setattr(recovery.git_integrate, "git_status", lambda repo: calls.append("git_status"))
    result = recovery.recover_merged_current(tmp_path)
    assert result["status"] == "pass"
    assert calls == []


def test_recovery_passthrough_for_non_stale_human_decision(monkeypatch, tmp_path):
    original = {"status": "human_decision_required", "action": "create_pr", "evidence": {"pr_state": "OPEN"}}
    monkeypatch.setattr(recovery.pr_operator, "create_current_pr", lambda repo: original)
    result = recovery.recover_merged_current(tmp_path)
    assert result is original
```

Run:

```bash
python3 -m pytest scripts/tests/test_opencode_pr_recovery.py -q
```

Expected RED: import or attribute failure because the recovery module does not exist.

- [ ] **Step 2: Add failing tests for the stale merged recovery sequence**

Add this test to `scripts/tests/test_opencode_pr_recovery.py`:

```python
def test_recovery_creates_followup_branch_pushes_and_creates_new_pr(monkeypatch, tmp_path):
    calls = []
    stale = {
        "status": "human_decision_required",
        "action": "create_pr",
        "evidence": {
            "branch": "juicyrebel/bass",
            "current_head": "abcdef1234567890",
            "pr_head": "1111111111111111",
            "pr_state": "MERGED",
            "pr_url": "https://example/old/1",
        },
    }
    fresh = {"status": "pass", "url": "https://example/new/2", "evidence": {"branch": "juicyrebel/bass-followup-abcdef1"}}

    def create_current(repo):
        calls.append("create_current_pr")
        return stale if calls.count("create_current_pr") == 1 else fresh

    monkeypatch.setattr(recovery.pr_operator, "create_current_pr", create_current)
    monkeypatch.setattr(recovery.git_integrate, "git_status", lambda repo: calls.append("git_status") or {"status": "pass", "evidence": {"branch": "juicyrebel/bass", "dirty": False, "origin_main_is_ancestor_of_head": True}})
    monkeypatch.setattr(recovery.git_integrate, "create_followup_branch", lambda repo: calls.append("create_followup_branch") or {"status": "pass", "evidence": {"branch": "juicyrebel/bass-followup-abcdef1"}})
    monkeypatch.setattr(recovery.git_integrate, "push_current", lambda repo: calls.append("push_current") or {"status": "pass", "evidence": {"branch": "juicyrebel/bass-followup-abcdef1"}})

    result = recovery.recover_merged_current(tmp_path)

    assert result["status"] == "pass"
    assert result["url"] == "https://example/new/2"
    assert calls == ["create_current_pr", "git_status", "create_followup_branch", "push_current", "create_current_pr"]
```

- [ ] **Step 3: Add failing tests for safety-gate refusals**

Add parameterized tests proving recovery refuses before mutation when status evidence is unsafe:

```python
import pytest


@pytest.mark.parametrize(
    "status_evidence",
    [
        {"branch": "juicyrebel/bass", "dirty": True, "origin_main_is_ancestor_of_head": True},
        {"branch": "juicyrebel/bass", "dirty": False, "origin_main_is_ancestor_of_head": False},
        {"branch": "other/branch", "dirty": False, "origin_main_is_ancestor_of_head": True},
    ],
)
def test_recovery_refuses_unsafe_status_before_mutation(monkeypatch, tmp_path, status_evidence):
    calls = []
    stale = {"status": "human_decision_required", "evidence": {"branch": "juicyrebel/bass", "current_head": "abcdef1", "pr_head": "1111111", "pr_state": "MERGED"}}
    monkeypatch.setattr(recovery.pr_operator, "create_current_pr", lambda repo: stale)
    monkeypatch.setattr(recovery.git_integrate, "git_status", lambda repo: {"status": "pass", "evidence": status_evidence})
    monkeypatch.setattr(recovery.git_integrate, "create_followup_branch", lambda repo: calls.append("create_followup_branch"))
    monkeypatch.setattr(recovery.git_integrate, "push_current", lambda repo: calls.append("push_current"))

    result = recovery.recover_merged_current(tmp_path)

    assert result["status"] == "human_decision_required"
    assert result["phase"] == "preflight"
    assert calls == []
```

Also add tests for `create_followup_branch`, `push_current`, and second `create_current_pr` returning non-pass; each result should be `human_decision_required` with `phase` set to `create_followup_branch`, `push_current`, or `create_current_pr_after_recovery`.

- [ ] **Step 4: Implement `scripts/opencode_pr_recovery.py`**

Implement the wrapper with this shape:

```python
#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import opencode_git_integrate as git_integrate
import opencode_pr_operator as pr_operator


def _evidence(result: dict[str, Any]) -> dict[str, Any]:
    evidence = result.get("evidence")
    return evidence if isinstance(evidence, dict) else {}


def _is_stale_merged_pr(result: dict[str, Any]) -> bool:
    evidence = _evidence(result)
    current_head = evidence.get("current_head")
    pr_head = evidence.get("pr_head")
    return (
        result.get("status") == "human_decision_required"
        and evidence.get("pr_state") == "MERGED"
        and isinstance(current_head, str)
        and isinstance(pr_head, str)
        and bool(current_head)
        and bool(pr_head)
        and current_head != pr_head
    )


def _refusal(phase: str, stale_result: dict[str, Any], result: dict[str, Any], message: str) -> dict[str, Any]:
    return {
        "status": "human_decision_required",
        "action": "create_current_with_followup_recovery",
        "phase": phase,
        "message": message,
        "stale_pr": _evidence(stale_result),
        "evidence": result,
    }


def recover_merged_current(repo_root: Path) -> dict[str, Any]:
    first = pr_operator.create_current_pr(repo_root)
    if not _is_stale_merged_pr(first):
        return first

    stale = _evidence(first)
    status = git_integrate.git_status(repo_root)
    status_evidence = _evidence(status)
    if (
        status.get("status") != "pass"
        or status_evidence.get("dirty") is not False
        or status_evidence.get("origin_main_is_ancestor_of_head") is not True
        or status_evidence.get("branch") != stale.get("branch")
    ):
        return _refusal("preflight", first, status, "Current branch is not safe for stale merged PR recovery")

    followup = git_integrate.create_followup_branch(repo_root)
    if followup.get("status") != "pass":
        return _refusal("create_followup_branch", first, followup, "Failed to create follow-up branch")

    pushed = git_integrate.push_current(repo_root)
    if pushed.get("status") != "pass":
        return _refusal("push_current", first, pushed, "Failed to push follow-up branch")

    second = pr_operator.create_current_pr(repo_root)
    if second.get("status") != "pass":
        return _refusal("create_current_pr_after_recovery", first, second, "Failed to create PR after follow-up recovery")
    second.setdefault("recovery", {"stale_pr": stale, "followup": _evidence(followup), "push": _evidence(pushed)})
    return second
```

Add a CLI `main()` supporting exactly `create-current-with-followup-recovery --repo-root <path>` and printing JSON. Exit `0` for `pass`, `2` for `human_decision_required`, and `1` for other failures.

- [ ] **Step 5: Preserve normal PR operator stale refusal behavior**

Run the existing stale PR test and do not change production behavior in `scripts/opencode_pr_operator.py`:

```bash
python3 -m pytest scripts/tests/test_opencode_pr_operator.py::test_create_current_rejects_stale_existing_pr_with_different_head -q
```

- [ ] **Step 6: Run focused wrapper validation**

```bash
python3 -m pytest \
  scripts/tests/test_opencode_pr_recovery.py \
  scripts/tests/test_opencode_pr_operator.py::test_create_current_rejects_stale_existing_pr_with_different_head \
  scripts/tests/test_opencode_git_integrate.py::test_create_followup_branch_switches_to_deterministic_absent_target
```

- [ ] **Step 7: Commit Task 1**

```bash
git add scripts/opencode_pr_recovery.py \
        scripts/tests/test_opencode_pr_recovery.py \
        scripts/tests/test_opencode_pr_operator.py
git commit -m "feat(scripts): recover stale merged PR followups"
```

---

### Task 2: Add recovery capability agent and permission checks

**Files:**
- Create: `.opencode/agents/pr-recovery-operator.md`
- Modify: `scripts/check_opencode_permissions.py`
- Modify: `scripts/tests/test_check_opencode_permissions.py`

**Interfaces:**
- Consumes: CLI `python3 scripts/opencode_pr_recovery.py create-current-with-followup-recovery --repo-root .`
- Produces: OpenCode capability agent `pr-recovery-operator` with exactly one allowed bash command.

- [ ] **Step 1: Add failing permission/config tests**

In `scripts/tests/test_check_opencode_permissions.py`, add tests that assert:

```python
def test_pr_recovery_operator_allows_only_exact_guarded_recovery_command():
    bash_entries = permission_entries(REPO_ROOT, "pr-recovery-operator", "bash")

    allowed_entries = {pattern for pattern, action in bash_entries.items() if action == "allow"}
    assert allowed_entries == {
        "python3 scripts/opencode_pr_recovery.py create-current-with-followup-recovery --repo-root ."
    }


@pytest.mark.parametrize(
    "extra_entry",
    [
        '    "git switch -c *": allow\n',
        '    "git push *": allow\n',
        '    "gh pr create *": allow\n',
        '    "python3 scripts/opencode_pr_recovery.py *": allow\n',
        '    "python3 scripts/opencode_pr_recovery.py create-current-with-followup-recovery --repo-root *": allow\n',
    ],
)
def test_pr_recovery_operator_rejects_extra_bash_allow(tmp_path: Path, extra_entry: str):
    repo = make_repo(tmp_path)
    write_file(repo / "scripts" / "opencode_pr_recovery.py", "#!/usr/bin/env python3\n")
    recovery_permissions = (
        '  edit: deny\n'
        '  task: deny\n'
        '  external_directory: deny\n'
        '  webfetch: deny\n'
        '  websearch: deny\n'
        '  question: deny\n'
        '  bash:\n'
        '    "python3 scripts/opencode_pr_recovery.py create-current-with-followup-recovery --repo-root .": allow\n'
        + extra_entry
    )
    write_file(
        repo / ".opencode" / "agents" / "pr-recovery-operator.md",
        agent("pr-recovery-operator", recovery_permissions),
    )

    assert "capability-boundary" in violation_codes(repo)
```

Also update `write_capability_files` in the same test file so synthetic valid repos include the new `pr-recovery-operator.md` and `scripts/opencode_pr_recovery.py` fixture. Run:

```bash
python3 -m pytest scripts/tests/test_check_opencode_permissions.py -q
```

Expected RED: checker does not know about `pr-recovery-operator` yet.

- [ ] **Step 2: Create `.opencode/agents/pr-recovery-operator.md`**

Create the agent with frontmatter matching existing capability-agent style. It must be a subagent and allow only this exact bash command:

```yaml
"python3 scripts/opencode_pr_recovery.py create-current-with-followup-recovery --repo-root .": allow
```

All unrelated capabilities must be denied. The body must say the agent is only for stale merged current-branch PR recovery and must return wrapper JSON verbatim.

- [ ] **Step 3: Update `scripts/check_opencode_permissions.py`**

Add the new capability file to the required file list and validate that `pr-recovery-operator` has exactly one allowed bash command:

```text
python3 scripts/opencode_pr_recovery.py create-current-with-followup-recovery --repo-root .
```

Reject any extra `git`, `gh`, wildcard, or suffix-wildcard command for this agent.

- [ ] **Step 4: Run focused permission validation**

```bash
python3 -m pytest scripts/tests/test_check_opencode_permissions.py
```

- [ ] **Step 5: Commit Task 2**

```bash
git add .opencode/agents/pr-recovery-operator.md \
        scripts/check_opencode_permissions.py \
        scripts/tests/test_check_opencode_permissions.py
git commit -m "feat(scripts): add stale PR recovery capability"
```

---

### Task 3: Wire supervisor, finishing skill, and workflow docs

**Files:**
- Modify: `.opencode/agents/supervisor.md`
- Modify: `.opencode/skills/finishing-a-development-branch/SKILL.md`
- Modify: `docs/dev/features/opencode-agent-workflow.md`
- Modify: `scripts/tests/test_check_opencode_permissions.py`

**Interfaces:**
- Consumes: `pr-recovery-operator` capability agent.
- Produces: supervisor/finishing instructions that dispatch recovery automatically for stale merged PR evidence.

- [ ] **Step 1: Add failing workflow documentation tests**

In `scripts/tests/test_check_opencode_permissions.py`, update the existing workflow-doc checks or add focused assertions that require these exact concepts to appear in the relevant files:

```text
pr-recovery-operator
create-current-with-followup-recovery
stale merged PR
```

For `.opencode/agents/supervisor.md` and `.opencode/skills/finishing-a-development-branch/SKILL.md`, tests should fail while they still describe the manual `git-integrator create-followup-branch` / push / `github-operator create-current` sequence as the primary recovery path.

Run:

```bash
python3 -m pytest scripts/tests/test_check_opencode_permissions.py -q
```

Expected RED: docs/instructions do not yet name the recovery operator path.

- [ ] **Step 2: Update supervisor routing**

In `.opencode/agents/supervisor.md`, replace the reused-branch stale merged PR manual recovery instructions with:

```markdown
If `github-operator` reports an existing merged PR whose `pr_head` differs from
current `HEAD`, dispatch `pr-recovery-operator` to run the guarded
`create-current-with-followup-recovery` wrapper. If it returns `pass`, continue
with GitHub auto-merge/merge-queue polling for the returned PR. If it returns
`human_decision_required`, report that wrapper evidence to the human.
```

Keep all existing prohibitions on raw `git`, raw `gh`, rebase, force-push, direct main push, and branch deletion.

- [ ] **Step 3: Update finishing skill**

In `.opencode/skills/finishing-a-development-branch/SKILL.md`, update the PR creation section so stale merged current-branch PR evidence is handled by dispatching `pr-recovery-operator`, not by stopping immediately or expecting the supervisor to manually assemble the recovery steps.

Make sure the skill still says to poll merge queue through `github-operator` after a successful recovered PR and to report `HUMAN_DECISION_REQUIRED` if the recovery wrapper refuses.

- [ ] **Step 4: Update canonical workflow docs**

In `docs/dev/features/opencode-agent-workflow.md`, document:

- the stale merged PR symptom;
- the exact recovery command;
- safety gates;
- why normal `opencode_pr_operator.py create-current` remains GitHub-only;
- that OpenCode users must restart after `.opencode/**` changes.

- [ ] **Step 5: Run focused docs/config validation**

```bash
python3 -m pytest scripts/tests/test_check_opencode_permissions.py
```

- [ ] **Step 6: Commit Task 3**

```bash
git add .opencode/agents/supervisor.md \
        .opencode/skills/finishing-a-development-branch/SKILL.md \
        docs/dev/features/opencode-agent-workflow.md \
        scripts/tests/test_check_opencode_permissions.py
git commit -m "docs(scripts): route stale PR recovery automatically"
```

---

### Task 4: Final focused validation

**Files:**
- Test: `scripts/tests/test_opencode_pr_recovery.py`
- Test: `scripts/tests/test_opencode_pr_operator.py`
- Test: `scripts/tests/test_opencode_git_integrate.py`
- Test: `scripts/tests/test_check_opencode_permissions.py`

**Interfaces:**
- Consumes: wrapper, capability agent, and workflow documentation from Tasks 1-3.
- Produces: final local validation evidence for the OpenCode recovery workflow.

- [ ] **Step 1: Run relevant wrapper and capability tests**

```bash
python3 -m pytest \
  scripts/tests/test_opencode_pr_recovery.py \
  scripts/tests/test_opencode_pr_operator.py \
  scripts/tests/test_opencode_git_integrate.py \
  scripts/tests/test_check_opencode_permissions.py
```

- [ ] **Step 2: Run project OpenCode validation target if available**

```bash
make opencode-check
```

If the target is unavailable, report the exact `make` error and rely on the focused Python tests above; do not substitute unrelated validation.

- [ ] **Step 3: Verify acceptance criteria**

Confirm in the report:

- stale merged current-branch PR recovery succeeds through one explicit recovery command;
- `scripts/opencode_pr_operator.py create-current` still has no Git mutation side effects;
- recovery never runs for non-merged stale PRs, dirty worktrees, stale `origin/main` bases, unsafe branch names, or existing follow-up branch targets;
- capability permissions remain exact and non-wildcarded;
- documentation names `docs/dev/features/opencode-agent-workflow.md` as the canonical workflow page;
- OpenCode restart after `.opencode/**` changes is documented.

- [ ] **Step 4: Commit Task 4 if validation/docs changed**

If Task 4 only runs validation and changes no files, do not create an empty commit. If it fixes docs/tests, commit only the changed reviewed files. Example for a test-only follow-up:

```bash
git add scripts/tests/test_opencode_pr_recovery.py scripts/tests/test_check_opencode_permissions.py
git commit -m "test(scripts): validate stale PR recovery workflow"
```

---

## Acceptance Criteria

- Reused-session stale merged PR recovery no longer requires a human decision when the stale evidence is exactly merged/different-head and the branch is clean/current.
- The recovery path creates a deterministic follow-up branch, pushes it, and creates a fresh PR.
- Existing `scripts/opencode_pr_operator.py create-current` remains GitHub-only and returns `human_decision_required` for stale merged PRs.
- The new capability agent exposes exactly one recovery command and no raw/broad GitHub or Git permissions.
- Supervisor and finishing instructions dispatch the recovery agent automatically and only report `HUMAN_DECISION_REQUIRED` when the recovery wrapper refuses.
- Focused wrapper, git integration, PR operator, and permission tests pass.
- The final user-facing report reminds that OpenCode must be restarted after `.opencode/**` changes.
