import json
import subprocess
import sys
from pathlib import Path

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_ROOT))

import opencode_capabilities as capabilities
import opencode_windows_ci_repro as windows_ci_repro


def make_space_repo(tmp_path: Path) -> Path:
    repo = tmp_path / "space"
    repo.mkdir()
    subprocess.run(["git", "init"], cwd=repo, check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["git", "remote", "add", "origin", "git@github.com:semanticdreams/space2.git"], cwd=repo, check=True)
    (repo / "AGENTS.md").write_text("# Repository Guidelines\n", encoding="utf-8")
    (repo / ".opencode").mkdir()
    (repo / ".opencode" / "opencode.json").write_text("{}\n", encoding="utf-8")
    return repo


def install_required_scripts(repo: Path) -> None:
    scripts = repo / "scripts"
    scripts.mkdir(exist_ok=True)
    for relative in windows_ci_repro.REQUIRED_SCRIPTS:
        path = repo / relative
        path.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")


def install_fake_vcpkg(repo: Path) -> None:
    path = repo / "external" / "vcpkg" / "vcpkg"
    path.parent.mkdir(parents=True)
    path.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")


def install_fake_windows_outputs(repo: Path) -> None:
    for relative in (
        "build/dist/windows/space.exe",
        "build/dist/windows/space-cli.exe",
        "build/windows/CPackConfig.cmake",
        "build/windows/space.ico",
        "scripts/windows-installer.iss",
    ):
        path = repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("placeholder\n", encoding="utf-8")


def command_result(args: list[str], stdout: str = "", returncode: int = 0, stderr: str = "") -> capabilities.CommandResult:
    return capabilities.CommandResult(args=args, returncode=returncode, stdout=stdout, stderr=stderr)


def monkeypatch_required_tools_present(monkeypatch) -> None:
    monkeypatch.setattr(windows_ci_repro.shutil, "which", lambda name: f"/usr/bin/{name}")


def monkeypatch_required_tools_missing(monkeypatch, *, missing: set[str]) -> None:
    monkeypatch.setattr(windows_ci_repro.shutil, "which", lambda name: None if name in missing else f"/usr/bin/{name}")


def monkeypatch_rust_target(monkeypatch, *, installed: bool) -> None:
    target_output = f"{windows_ci_repro.WINDOWS_RUST_TARGET}\n" if installed else "x86_64-unknown-linux-gnu\n"

    def fake_run_command(args, cwd: Path, check: bool = True):
        del cwd, check
        if list(args) == ["rustup", "target", "list", "--installed"]:
            return command_result(list(args), stdout=target_output)
        return command_result(list(args))

    monkeypatch.setattr(windows_ci_repro, "run_command", fake_run_command)


def monkeypatch_linux_ubuntu_with_sudo(monkeypatch) -> None:
    monkeypatch.setattr(windows_ci_repro.sys, "platform", "linux")
    monkeypatch.setattr(windows_ci_repro, "_is_ubuntu_host", lambda: True)
    monkeypatch.setattr(windows_ci_repro.shutil, "which", lambda name: "/usr/bin/sudo" if name == "sudo" else f"/usr/bin/{name}")


def capture_run_command_calls(monkeypatch, module):
    calls: list[list[str]] = []

    def fake_run_command(args, cwd: Path, check: bool = True):
        del cwd, check
        calls.append(list(args))
        return command_result(list(args))

    monkeypatch.setattr(module, "run_command", fake_run_command)
    return calls


def monkeypatch_preflight_pass(monkeypatch, module) -> None:
    monkeypatch.setattr(module, "preflight", lambda repo_root: capabilities.success("preflight", "ok", {"missing": []}))


def monkeypatch_run_command_failure(monkeypatch, module, *, failing_args: list[str]) -> None:
    def fake_run_command(args, cwd: Path, check: bool = True):
        del cwd, check
        args = list(args)
        if args == failing_args:
            return command_result(args, stdout="line1\nline2\n", stderr="error1\nerror2\n", returncode=17)
        return command_result(args)

    monkeypatch.setattr(module, "run_command", fake_run_command)


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


def test_cli_invalid_repo_returns_structured_fail_json_without_traceback(tmp_path):
    not_space_repo = tmp_path / "not-space"
    not_space_repo.mkdir()

    completed = subprocess.run(
        [
            sys.executable,
            str(SCRIPT_ROOT / "opencode_windows_ci_repro.py"),
            "preflight",
            "--repo-root",
            str(not_space_repo),
        ],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    result = json.loads(completed.stdout)
    assert completed.returncode == 3
    assert result["status"] == "fail"
    assert result["action"] == "preflight"
    assert set(result) == {"status", "action", "message", "evidence"}
    assert result["evidence"]["code"] in {"command_failed", "invalid_repo"}
    assert "Traceback" not in completed.stderr


def test_direct_operations_return_structured_failures_for_invalid_repo(monkeypatch, tmp_path):
    invalid_repo = tmp_path / "not-space"
    invalid_repo.mkdir()

    def reject_repo(repo_root: Path) -> Path:
        raise capabilities.CapabilityError("invalid_repo", "Repository is not trusted", {"repo_root": str(repo_root)})

    monkeypatch.setattr(windows_ci_repro, "ensure_space_repo", reject_repo)

    for action, operation in (
        ("preflight", windows_ci_repro.preflight),
        ("setup-host", windows_ci_repro.setup_host),
        ("reproduce", windows_ci_repro.reproduce),
    ):
        result = operation(invalid_repo)

        assert result["status"] == "fail"
        assert result["action"] == action
        assert set(result) == {"status", "action", "message", "evidence"}
        assert result["evidence"]["code"] == "invalid_repo"
