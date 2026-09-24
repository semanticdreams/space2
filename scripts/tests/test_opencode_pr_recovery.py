import json
import sys
from pathlib import Path

import pytest

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_ROOT))

import opencode_pr_recovery as recovery


def test_recovery_passthrough_when_create_current_passes(monkeypatch, tmp_path: Path) -> None:
    calls = []
    monkeypatch.setattr(recovery.pr_operator, "create_current_pr", lambda repo: {"status": "pass", "url": "https://example/pr/1"})
    monkeypatch.setattr(recovery.git_integrate, "git_status", lambda repo: calls.append("git_status"))

    result = recovery.recover_merged_current(tmp_path)

    assert result["status"] == "pass"
    assert calls == []


def test_recovery_passthrough_for_non_stale_human_decision(monkeypatch, tmp_path: Path) -> None:
    original = {"status": "human_decision_required", "action": "create_pr", "evidence": {"pr_state": "OPEN"}}
    monkeypatch.setattr(recovery.pr_operator, "create_current_pr", lambda repo: original)

    result = recovery.recover_merged_current(tmp_path)

    assert result is original


def test_recovery_creates_followup_branch_pushes_and_creates_new_pr(monkeypatch, tmp_path: Path) -> None:
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

    def create_current(repo: Path) -> dict[str, object]:
        calls.append("create_current_pr")
        return stale if calls.count("create_current_pr") == 1 else fresh

    monkeypatch.setattr(recovery.pr_operator, "create_current_pr", create_current)
    monkeypatch.setattr(
        recovery.git_integrate,
        "git_status",
        lambda repo: calls.append("git_status") or {"status": "pass", "evidence": {"branch": "juicyrebel/bass", "dirty": False, "origin_main_is_ancestor_of_head": True}},
    )
    monkeypatch.setattr(
        recovery.git_integrate,
        "create_followup_branch",
        lambda repo: calls.append("create_followup_branch") or {"status": "pass", "evidence": {"branch": "juicyrebel/bass-followup-abcdef1"}},
    )
    monkeypatch.setattr(
        recovery.git_integrate,
        "push_current",
        lambda repo: calls.append("push_current") or {"status": "pass", "evidence": {"branch": "juicyrebel/bass-followup-abcdef1"}},
    )

    result = recovery.recover_merged_current(tmp_path)

    assert result["status"] == "pass"
    assert result["url"] == "https://example/new/2"
    assert result["recovery"]["stale_pr"] == stale["evidence"]
    assert calls == ["create_current_pr", "git_status", "create_followup_branch", "push_current", "create_current_pr"]


@pytest.mark.parametrize(
    "status_evidence",
    [
        {"branch": "juicyrebel/bass", "dirty": True, "origin_main_is_ancestor_of_head": True},
        {"branch": "juicyrebel/bass", "dirty": False, "origin_main_is_ancestor_of_head": False},
        {"branch": "other/branch", "dirty": False, "origin_main_is_ancestor_of_head": True},
    ],
)
def test_recovery_refuses_unsafe_status_before_mutation(monkeypatch, tmp_path: Path, status_evidence: dict[str, object]) -> None:
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


@pytest.mark.parametrize(
    ("operation", "phase"),
    [
        ("create_followup_branch", "create_followup_branch"),
        ("push_current", "push_current"),
        ("second_create_current_pr", "create_current_pr_after_recovery"),
    ],
)
def test_recovery_refuses_when_recovery_step_does_not_pass(monkeypatch, tmp_path: Path, operation: str, phase: str) -> None:
    calls = []
    stale = {"status": "human_decision_required", "evidence": {"branch": "juicyrebel/bass", "current_head": "abcdef1", "pr_head": "1111111", "pr_state": "MERGED"}}
    fresh = {"status": "pass", "evidence": {"branch": "juicyrebel/bass-followup-abcdef1"}}
    unsafe = {"status": "human_decision_required", "evidence": {"reason": operation}}

    def create_current(repo: Path) -> dict[str, object]:
        calls.append("create_current_pr")
        if calls.count("create_current_pr") == 1:
            return stale
        return unsafe if operation == "second_create_current_pr" else fresh

    def step(name: str) -> dict[str, object]:
        calls.append(name)
        return unsafe if operation == name else fresh

    monkeypatch.setattr(recovery.pr_operator, "create_current_pr", create_current)
    monkeypatch.setattr(recovery.git_integrate, "git_status", lambda repo: calls.append("git_status") or {"status": "pass", "evidence": {"branch": "juicyrebel/bass", "dirty": False, "origin_main_is_ancestor_of_head": True}})
    monkeypatch.setattr(recovery.git_integrate, "create_followup_branch", lambda repo: step("create_followup_branch"))
    monkeypatch.setattr(recovery.git_integrate, "push_current", lambda repo: step("push_current"))

    result = recovery.recover_merged_current(tmp_path)

    assert result["status"] == "human_decision_required"
    assert result["phase"] == phase
    assert result["stale_pr"] == stale["evidence"]


def test_cli_supports_only_recovery_command_and_maps_exit_codes(monkeypatch, tmp_path: Path, capsys) -> None:
    calls = []

    def fake_recover(repo_root: Path) -> dict[str, object]:
        calls.append(repo_root)
        return {"status": "human_decision_required", "action": "create_current_with_followup_recovery", "evidence": {}}

    monkeypatch.setattr(recovery, "recover_merged_current", fake_recover)

    exit_code = recovery.main(["create-current-with-followup-recovery", "--repo-root", str(tmp_path)])

    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 2
    assert payload["status"] == "human_decision_required"
    assert calls == [tmp_path]
