import json
import sys
from pathlib import Path

import pytest

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_ROOT))

import opencode_capabilities as capabilities
import opencode_git_integrate as git_integrate


def command_result(args: list[str], stdout: str = "", returncode: int = 0, stderr: str = "") -> capabilities.CommandResult:
    return capabilities.CommandResult(args=args, returncode=returncode, stdout=stdout, stderr=stderr)


class GitRunner:
    def __init__(self, outputs: dict[tuple[str, ...], str | capabilities.CommandResult]) -> None:
        self.outputs = outputs
        self.calls: list[list[str]] = []
        self.checks: list[bool] = []

    def __call__(self, args, cwd: Path, check: bool = True):
        del cwd
        args = list(args)
        self.calls.append(args)
        self.checks.append(check)
        output = self.outputs.get(tuple(args), "")
        if isinstance(output, capabilities.CommandResult):
            return output
        return command_result(args, output)


@pytest.fixture
def trusted_repo(monkeypatch, tmp_path: Path) -> Path:
    repo = tmp_path / "space"
    repo.mkdir()
    monkeypatch.setattr(git_integrate, "ensure_space_repo", lambda repo_root: repo)
    return repo


def test_status_reports_expanded_freshness_evidence_when_current_with_origin_main(monkeypatch, trusted_repo: Path) -> None:
    runner = GitRunner(
        {
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
            ("git", "rev-parse", "HEAD"): "abc123\n",
            ("git", "rev-parse", "origin/main"): "base456\n",
            ("git", "status", "--porcelain"): " M file.py\n",
            ("git", "merge-base", "HEAD", "origin/main"): "base456\n",
            ("git", "merge-base", "--is-ancestor", "origin/main", "HEAD"): command_result(
                ["git", "merge-base", "--is-ancestor", "origin/main", "HEAD"],
                returncode=0,
            ),
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    result = git_integrate.git_status(trusted_repo)

    assert result["status"] == "pass"
    assert result["evidence"] == {
        "branch": "feature/opencode-capabilities",
        "head_sha": "abc123",
        "dirty": True,
        "origin_main_merge_base": "base456",
        "origin_main_sha": "base456",
        "origin_main_is_ancestor_of_head": True,
        "branch_current_with_origin_main": True,
        "safe_merge_needed": False,
    }
    assert [call for call in runner.calls if call[:3] == ["git", "merge-base", "--is-ancestor"]] == [
        ["git", "merge-base", "--is-ancestor", "origin/main", "HEAD"]
    ]
    assert runner.checks[runner.calls.index(["git", "merge-base", "--is-ancestor", "origin/main", "HEAD"])] is False


def test_status_reports_merge_needed_when_origin_main_is_not_ancestor_of_head(monkeypatch, trusted_repo: Path) -> None:
    runner = GitRunner(
        {
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
            ("git", "rev-parse", "HEAD"): "abc123\n",
            ("git", "rev-parse", "origin/main"): "def789\n",
            ("git", "status", "--porcelain"): "",
            ("git", "merge-base", "HEAD", "origin/main"): "base456\n",
            ("git", "merge-base", "--is-ancestor", "origin/main", "HEAD"): command_result(
                ["git", "merge-base", "--is-ancestor", "origin/main", "HEAD"],
                returncode=1,
            ),
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    result = git_integrate.git_status(trusted_repo)

    assert result["status"] == "pass"
    assert result["evidence"]["origin_main_sha"] == "def789"
    assert result["evidence"]["origin_main_is_ancestor_of_head"] is False
    assert result["evidence"]["branch_current_with_origin_main"] is False
    assert result["evidence"]["safe_merge_needed"] is True


def test_status_fails_closed_on_unexpected_origin_main_ancestor_return_code(monkeypatch, trusted_repo: Path) -> None:
    runner = GitRunner(
        {
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
            ("git", "rev-parse", "HEAD"): "abc123\n",
            ("git", "rev-parse", "origin/main"): "def789\n",
            ("git", "status", "--porcelain"): "",
            ("git", "merge-base", "HEAD", "origin/main"): "base456\n",
            ("git", "merge-base", "--is-ancestor", "origin/main", "HEAD"): command_result(
                ["git", "merge-base", "--is-ancestor", "origin/main", "HEAD"],
                returncode=128,
                stderr="fatal: not a valid object name origin/main\n",
            ),
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    result = git_integrate.git_status(trusted_repo)

    assert result["status"] == "fail"
    assert result["evidence"]["code"] == "command_failed"
    assert result["evidence"]["details"]["args"] == ["git", "merge-base", "--is-ancestor", "origin/main", "HEAD"]
    assert result["evidence"]["details"]["returncode"] == 128


def test_merge_origin_main_refuses_dirty_worktree(monkeypatch, trusted_repo: Path) -> None:
    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): " M task.py\n",
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    result = git_integrate.merge_origin_main(trusted_repo)

    assert result["status"] == "human_decision_required"
    assert ["git", "fetch", "origin", "main"] not in runner.calls
    assert ["git", "merge", "--no-edit", "origin/main"] not in runner.calls


def test_merge_origin_main_refuses_main_branch(monkeypatch, trusted_repo: Path) -> None:
    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): "",
            ("git", "branch", "--show-current"): "main\n",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    result = git_integrate.merge_origin_main(trusted_repo)

    assert result["status"] == "human_decision_required"
    assert ["git", "fetch", "origin", "main"] not in runner.calls


def test_merge_origin_main_runs_only_fetch_origin_main_then_no_edit_merge(monkeypatch, trusted_repo: Path) -> None:
    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): "",
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
            ("git", "fetch", "origin", "main"): "",
            ("git", "merge", "--no-edit", "origin/main"): "Already up to date.\n",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    result = git_integrate.merge_origin_main(trusted_repo)

    assert result["status"] == "pass"
    assert runner.calls == [
        ["git", "status", "--porcelain"],
        ["git", "branch", "--show-current"],
        ["git", "fetch", "origin", "main"],
        ["git", "merge", "--no-edit", "origin/main"],
    ]


def test_push_current_refuses_main_invalid_branch_and_pushes_only_head_to_current_branch(monkeypatch, trusted_repo: Path) -> None:
    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): "",
            ("git", "branch", "--show-current"): "main\n",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)
    assert git_integrate.push_current(trusted_repo)["status"] == "human_decision_required"

    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): "",
            ("git", "branch", "--show-current"): "bad branch\n",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)
    assert git_integrate.push_current(trusted_repo)["status"] == "human_decision_required"

    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): "",
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
            ("git", "push", "origin", "HEAD:refs/heads/feature/opencode-capabilities"): "",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)
    result = git_integrate.push_current(trusted_repo)

    assert result["status"] == "pass"
    assert runner.calls == [
        ["git", "status", "--porcelain"],
        ["git", "branch", "--show-current"],
        ["git", "push", "origin", "HEAD:refs/heads/feature/opencode-capabilities"],
    ]


def test_derive_followup_branch_name_appends_followup_suffix() -> None:
    assert (
        git_integrate._derive_followup_branch_name("juicyrebel/test-workflow-artifact-names", "caad43f")
        == "juicyrebel/test-workflow-artifact-names-followup-caad43f"
    )


def test_create_followup_branch_refuses_dirty_worktree(monkeypatch, trusted_repo: Path) -> None:
    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): " M task.py\n",
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    result = git_integrate.create_followup_branch(trusted_repo)

    assert result["status"] == "human_decision_required"
    assert [call for call in runner.calls if call[:3] == ["git", "switch", "-c"]] == []


def test_create_followup_branch_refuses_main_branch(monkeypatch, trusted_repo: Path) -> None:
    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): "",
            ("git", "branch", "--show-current"): "main\n",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    result = git_integrate.create_followup_branch(trusted_repo)

    assert result["status"] == "human_decision_required"
    assert [call for call in runner.calls if call[:3] == ["git", "switch", "-c"]] == []


def test_create_followup_branch_refuses_detached_head(monkeypatch, trusted_repo: Path) -> None:
    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): "",
            ("git", "branch", "--show-current"): "\n",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    result = git_integrate.create_followup_branch(trusted_repo)

    assert result["status"] == "human_decision_required"
    assert [call for call in runner.calls if call[:3] == ["git", "switch", "-c"]] == []


def test_create_followup_branch_refuses_when_origin_main_not_in_head(monkeypatch, trusted_repo: Path) -> None:
    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): "",
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
            ("git", "rev-parse", "--short=7", "HEAD"): "caad43f\n",
            ("git", "merge-base", "--is-ancestor", "origin/main", "HEAD"): command_result(
                ["git", "merge-base", "--is-ancestor", "origin/main", "HEAD"],
                returncode=1,
            ),
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    result = git_integrate.create_followup_branch(trusted_repo)

    assert result["status"] == "human_decision_required"
    assert [call for call in runner.calls if call[:3] == ["git", "switch", "-c"]] == []
    assert runner.checks[runner.calls.index(["git", "merge-base", "--is-ancestor", "origin/main", "HEAD"])] is False


def test_create_followup_branch_refuses_when_local_target_exists(monkeypatch, trusted_repo: Path) -> None:
    target = "feature/opencode-capabilities-followup-caad43f"
    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): "",
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
            ("git", "rev-parse", "--short=7", "HEAD"): "caad43f\n",
            ("git", "merge-base", "--is-ancestor", "origin/main", "HEAD"): command_result(
                ["git", "merge-base", "--is-ancestor", "origin/main", "HEAD"],
                returncode=0,
            ),
            ("git", "show-ref", "--verify", "--quiet", f"refs/heads/{target}"): command_result(
                ["git", "show-ref", "--verify", "--quiet", f"refs/heads/{target}"],
                returncode=0,
            ),
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    result = git_integrate.create_followup_branch(trusted_repo)

    assert result["status"] == "human_decision_required"
    assert [call for call in runner.calls if call[:3] == ["git", "switch", "-c"]] == []
    assert runner.checks[runner.calls.index(["git", "show-ref", "--verify", "--quiet", f"refs/heads/{target}"])] is False


def test_create_followup_branch_refuses_when_remote_target_exists(monkeypatch, trusted_repo: Path) -> None:
    target = "feature/opencode-capabilities-followup-caad43f"
    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): "",
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
            ("git", "rev-parse", "--short=7", "HEAD"): "caad43f\n",
            ("git", "merge-base", "--is-ancestor", "origin/main", "HEAD"): command_result(
                ["git", "merge-base", "--is-ancestor", "origin/main", "HEAD"],
                returncode=0,
            ),
            ("git", "show-ref", "--verify", "--quiet", f"refs/heads/{target}"): command_result(
                ["git", "show-ref", "--verify", "--quiet", f"refs/heads/{target}"],
                returncode=1,
            ),
            ("git", "ls-remote", "--exit-code", "--heads", "origin", target): command_result(
                ["git", "ls-remote", "--exit-code", "--heads", "origin", target],
                returncode=0,
            ),
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    result = git_integrate.create_followup_branch(trusted_repo)

    assert result["status"] == "human_decision_required"
    assert [call for call in runner.calls if call[:3] == ["git", "switch", "-c"]] == []
    assert runner.checks[runner.calls.index(["git", "ls-remote", "--exit-code", "--heads", "origin", target])] is False


def test_create_followup_branch_switches_to_deterministic_absent_target(monkeypatch, trusted_repo: Path) -> None:
    target = "feature/opencode-capabilities-followup-caad43f"
    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): "",
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
            ("git", "rev-parse", "--short=7", "HEAD"): "caad43f\n",
            ("git", "merge-base", "--is-ancestor", "origin/main", "HEAD"): command_result(
                ["git", "merge-base", "--is-ancestor", "origin/main", "HEAD"],
                returncode=0,
            ),
            ("git", "show-ref", "--verify", "--quiet", f"refs/heads/{target}"): command_result(
                ["git", "show-ref", "--verify", "--quiet", f"refs/heads/{target}"],
                returncode=1,
            ),
            ("git", "ls-remote", "--exit-code", "--heads", "origin", target): command_result(
                ["git", "ls-remote", "--exit-code", "--heads", "origin", target],
                returncode=2,
            ),
            ("git", "switch", "-c", target): "",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    result = git_integrate.create_followup_branch(trusted_repo)

    assert result["status"] == "pass"
    assert result["evidence"]["source_branch"] == "feature/opencode-capabilities"
    assert result["evidence"]["followup_branch"] == target
    assert runner.calls == [
        ["git", "status", "--porcelain"],
        ["git", "branch", "--show-current"],
        ["git", "rev-parse", "--short=7", "HEAD"],
        ["git", "merge-base", "--is-ancestor", "origin/main", "HEAD"],
        ["git", "show-ref", "--verify", "--quiet", f"refs/heads/{target}"],
        ["git", "ls-remote", "--exit-code", "--heads", "origin", target],
        ["git", "switch", "-c", target],
    ]


def test_cli_create_followup_branch_emits_json_and_returns_success(monkeypatch, trusted_repo: Path, capsys) -> None:
    target = "feature/opencode-capabilities-followup-caad43f"
    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): "",
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
            ("git", "rev-parse", "--short=7", "HEAD"): "caad43f\n",
            ("git", "merge-base", "--is-ancestor", "origin/main", "HEAD"): command_result(
                ["git", "merge-base", "--is-ancestor", "origin/main", "HEAD"],
                returncode=0,
            ),
            ("git", "show-ref", "--verify", "--quiet", f"refs/heads/{target}"): command_result(
                ["git", "show-ref", "--verify", "--quiet", f"refs/heads/{target}"],
                returncode=1,
            ),
            ("git", "ls-remote", "--exit-code", "--heads", "origin", target): command_result(
                ["git", "ls-remote", "--exit-code", "--heads", "origin", target],
                returncode=2,
            ),
            ("git", "switch", "-c", target): "",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    exit_code = git_integrate.main(["create-followup-branch", "--repo-root", str(trusted_repo)])

    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 0
    assert payload["status"] == "pass"
    assert payload["action"] == "create_followup_branch"
    assert payload["evidence"]["followup_branch"] == target


def test_cli_emits_json_and_returns_nonzero_on_unsafe_state(monkeypatch, trusted_repo: Path, capsys) -> None:
    runner = GitRunner(
        {
            ("git", "status", "--porcelain"): "",
            ("git", "branch", "--show-current"): "main\n",
        }
    )
    monkeypatch.setattr(git_integrate, "run_command", runner)

    exit_code = git_integrate.main(["push-current", "--repo-root", str(trusted_repo)])

    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 2
    assert payload["status"] == "human_decision_required"
    assert set(payload) == {"status", "action", "message", "evidence"}
