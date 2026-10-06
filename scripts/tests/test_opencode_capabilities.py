import json
import stat
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_ROOT))

import opencode_capabilities as capabilities
import verify_opencode_home_config as verify_config


def init_git_repo(path: Path, *, origin: str = "git@github.com:semanticdreams/space2.git") -> Path:
    path.mkdir(parents=True)
    subprocess.run(["git", "init"], cwd=path, check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["git", "remote", "add", "origin", origin], cwd=path, check=True)
    return path


def add_space_markers(repo: Path) -> None:
    (repo / "AGENTS.md").write_text("# Repository Guidelines\n", encoding="utf-8")
    opencode = repo / ".opencode"
    opencode.mkdir()
    (opencode / "opencode.json").write_text("{}\n", encoding="utf-8")


def create_repo_opencode_tree(repo: Path) -> None:
    add_space_markers(repo)
    for directory in ("agents", "skills", "plugins"):
        (repo / ".opencode" / directory).mkdir()
    (repo / ".opencode" / "plugins" / "rtk.ts").write_text("export default async () => ({})\n", encoding="utf-8")


def test_ensure_space_repo_accepts_space_repo_with_markers(tmp_path: Path) -> None:
    repo = init_git_repo(tmp_path / "space")
    add_space_markers(repo)

    assert capabilities.ensure_space_repo(repo) == repo.resolve()


def test_ensure_space_repo_rejects_repo_without_space_markers(tmp_path: Path) -> None:
    repo = init_git_repo(tmp_path / "not-space")

    with pytest.raises(capabilities.CapabilityError) as excinfo:
        capabilities.ensure_space_repo(repo)

    assert excinfo.value.code == "invalid_repo"


@pytest.mark.parametrize(
    "branch",
    [
        "automation/daily-devlog/2026-08-05",
        "automation/weekly-agent-workflow/2026-W32",
        "opencode/workflow-debug/test-123",
        "opencode/workflow-debug-pr/test-123",
        "feature/opencode-capabilities",
        "fix/permission-capabilities",
        "docs/opencode-capabilities",
        "chore/opencode-capabilities",
        "fast-dev/local-main-caad43f",
        "juicyrebel/weever",
        "juicyrebel/hud-right-rail-strip-fix",
    ],
)
def test_validate_branch_name_accepts_allowed_policy(branch: str) -> None:
    assert capabilities.validate_branch_name(branch) == branch


@pytest.mark.parametrize(
    "branch",
    [
        "main",
        "origin/main",
        "feature/../main",
        "feature/bad lock",
        "feature/name.lock",
        "",
        "juicyrebel/../main",
        "juicyrebel/bad lock",
        "juicyrebel/name.lock",
        "juicyrebel/",
        "other/weever",
    ],
)
def test_validate_branch_name_rejects_unsafe_names(branch: str) -> None:
    with pytest.raises(capabilities.CapabilityError):
        capabilities.validate_branch_name(branch)


@pytest.mark.parametrize(
    ("builder", "status"),
    [
        (capabilities.success, "pass"),
        (capabilities.human_decision, "human_decision_required"),
        (capabilities.failure, "fail"),
    ],
)
def test_json_response_helpers_emit_required_structured_keys(builder, status: str) -> None:
    result = builder("sample_action", "sample message", {"detail": "value"})

    assert set(result) == {"status", "action", "message", "evidence"}
    assert result == {
        "status": status,
        "action": "sample_action",
        "message": "sample message",
        "evidence": {"detail": "value"},
    }


def make_opencode_home(tmp_path: Path, repo: Path) -> Path:
    home = tmp_path / "opencode-home"
    home.mkdir()
    (home / "opencode.json").symlink_to(repo / ".opencode" / "opencode.json")
    (home / "agents").symlink_to(repo / ".opencode" / "agents", target_is_directory=True)
    (home / "skills").symlink_to(repo / ".opencode" / "skills", target_is_directory=True)
    plugins = home / "plugins"
    plugins.mkdir()
    (plugins / "rtk.ts").write_text("export default async () => ({})\n", encoding="utf-8")
    (home / "package.json").write_text('{"type":"module"}\n', encoding="utf-8")
    (home / "package-lock.json").write_text("{}\n", encoding="utf-8")
    return home


def test_audit_opencode_home_passes_for_expected_project_symlinks_and_allowed_support_files(tmp_path: Path) -> None:
    repo = init_git_repo(tmp_path / "space")
    create_repo_opencode_tree(repo)
    home = make_opencode_home(tmp_path, repo)

    result = capabilities.audit_opencode_home(repo, home)

    assert result["status"] == "pass"
    assert result["action"] == "audit_opencode_home"
    assert result["evidence"]["local_support_files"] == ["package-lock.json", "package.json", "plugins/rtk.ts"]


def test_audit_opencode_home_accepts_home_symlinks_to_trusted_main_checkout_from_worktree_repo(tmp_path: Path) -> None:
    active_repo = init_git_repo(tmp_path / "active-worktree")
    main_checkout = init_git_repo(tmp_path / "main-checkout")
    create_repo_opencode_tree(active_repo)
    create_repo_opencode_tree(main_checkout)
    home = make_opencode_home(tmp_path, main_checkout)

    result = capabilities.audit_opencode_home(active_repo, home)

    assert result["status"] == "pass"
    assert result["action"] == "audit_opencode_home"
    assert result["evidence"]["checked_symlinks"] == {
        "opencode.json": str((main_checkout / ".opencode" / "opencode.json").resolve()),
        "agents": str((main_checkout / ".opencode" / "agents").resolve()),
        "skills": str((main_checkout / ".opencode" / "skills").resolve()),
    }


def test_audit_opencode_home_fails_closed_when_expected_symlink_resolves_outside_repo(tmp_path: Path) -> None:
    repo = init_git_repo(tmp_path / "space")
    create_repo_opencode_tree(repo)
    home = make_opencode_home(tmp_path, repo)
    outside = tmp_path / "outside"
    outside.mkdir()
    (home / "agents").unlink()
    (home / "agents").symlink_to(outside, target_is_directory=True)

    result = capabilities.audit_opencode_home(repo, home)

    assert result["status"] == "human_decision_required"
    assert result["action"] == "audit_opencode_home"
    assert "agents" in json.dumps(result)


def test_audit_opencode_home_fails_closed_when_trusted_checkout_symlink_points_to_wrong_opencode_entry(tmp_path: Path) -> None:
    active_repo = init_git_repo(tmp_path / "active-worktree")
    main_checkout = init_git_repo(tmp_path / "main-checkout")
    create_repo_opencode_tree(active_repo)
    create_repo_opencode_tree(main_checkout)
    wrong_target = main_checkout / ".opencode" / "plugins"
    home = make_opencode_home(tmp_path, main_checkout)
    (home / "agents").unlink()
    (home / "agents").symlink_to(wrong_target, target_is_directory=True)

    result = capabilities.audit_opencode_home(active_repo, home)

    serialized = json.dumps(result)
    assert result["status"] == "human_decision_required"
    assert "agents" in serialized
    assert "symlink_target_not_project_opencode_entry" in serialized


def test_audit_opencode_home_fails_closed_for_spoofed_outside_checkout_origin(tmp_path: Path) -> None:
    active_repo = init_git_repo(tmp_path / "active-worktree")
    spoofed_checkout = init_git_repo(
        tmp_path / "spoofed-checkout",
        origin="git@example.com:attacker/semanticdreams/space2-fake.git",
    )
    create_repo_opencode_tree(active_repo)
    create_repo_opencode_tree(spoofed_checkout)
    home = make_opencode_home(tmp_path, spoofed_checkout)

    result = capabilities.audit_opencode_home(active_repo, home)

    serialized = json.dumps(result)
    assert result["status"] == "human_decision_required"
    assert "opencode.json" in serialized
    assert "symlink_target_not_project_opencode_entry" in serialized


def test_audit_opencode_home_fails_closed_for_symlinked_package_support_file(tmp_path: Path) -> None:
    repo = init_git_repo(tmp_path / "space")
    create_repo_opencode_tree(repo)
    home = make_opencode_home(tmp_path, repo)
    outside = tmp_path / "outside-package.json"
    outside.write_text('{"type":"module"}\n', encoding="utf-8")
    (home / "package.json").unlink()
    (home / "package.json").symlink_to(outside)

    result = capabilities.audit_opencode_home(repo, home)

    serialized = json.dumps(result)
    assert result["status"] == "human_decision_required"
    assert "package.json" in serialized
    assert "support_entry_is_symlink" in serialized


def test_audit_opencode_home_fails_closed_for_symlinked_plugins_directory_without_traversing_it(
    tmp_path: Path,
) -> None:
    repo = init_git_repo(tmp_path / "space")
    create_repo_opencode_tree(repo)
    home = make_opencode_home(tmp_path, repo)
    outside_plugins = tmp_path / "outside-plugins"
    outside_plugins.mkdir()
    (outside_plugins / "rtk.ts").write_text("external plugin content must not be inspected\n", encoding="utf-8")
    (home / "plugins" / "rtk.ts").unlink()
    (home / "plugins").rmdir()
    (home / "plugins").symlink_to(outside_plugins, target_is_directory=True)

    result = capabilities.audit_opencode_home(repo, home)

    serialized = json.dumps(result)
    assert result["status"] == "human_decision_required"
    assert "plugins" in serialized
    assert "support_entry_is_symlink" in serialized
    assert "rtk.ts" not in serialized
    assert "external plugin content" not in serialized


def test_audit_opencode_home_fails_closed_for_symlinked_rtk_plugin_file(tmp_path: Path) -> None:
    repo = init_git_repo(tmp_path / "space")
    create_repo_opencode_tree(repo)
    home = make_opencode_home(tmp_path, repo)
    outside_plugin = tmp_path / "external-rtk.ts"
    outside_plugin.write_text("export default async () => ({})\n", encoding="utf-8")
    (home / "plugins" / "rtk.ts").unlink()
    (home / "plugins" / "rtk.ts").symlink_to(outside_plugin)

    result = capabilities.audit_opencode_home(repo, home)

    serialized = json.dumps(result)
    assert result["status"] == "human_decision_required"
    assert "plugins/rtk.ts" in serialized
    assert "support_entry_is_symlink" in serialized


def test_audit_opencode_home_does_not_read_auth_json_or_leak_secret_text(tmp_path: Path) -> None:
    repo = init_git_repo(tmp_path / "space")
    create_repo_opencode_tree(repo)
    home = make_opencode_home(tmp_path, repo)
    secret = "sk-live-secret-must-not-appear"
    auth = home / "auth.json"
    auth.write_text(f'{{"token":"{secret}"}}\n', encoding="utf-8")
    auth.chmod(0)

    try:
        result = capabilities.audit_opencode_home(repo, home)
    finally:
        auth.chmod(stat.S_IRUSR | stat.S_IWUSR)

    serialized = json.dumps(result, sort_keys=True)
    assert result["status"] == "pass"
    assert secret not in serialized
    assert "auth.json" not in serialized


def test_verify_cli_status_to_exit_code_mapping() -> None:
    assert verify_config.exit_code_for({"status": "pass"}) == 0
    assert verify_config.exit_code_for({"status": "human_decision_required"}) == 2
    assert verify_config.exit_code_for({"status": "fail"}) == 3
