#!/usr/bin/env python3
"""Guarded Windows CI local reproduction capability for OpenCode agents."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from pathlib import Path
from typing import Sequence

from opencode_capabilities import CapabilityError, CommandResult, ensure_space_repo, failure, human_decision, run_command, success


REQUIRED_TOOLS = (
    "cmake",
    "git",
    "pkg-config",
    "nasm",
    "llvm-ml-14",
    "curl",
    "zip",
    "pwsh",
    "autoconf",
    "x86_64-w64-mingw32-gcc-posix",
    "x86_64-w64-mingw32-g++-posix",
    "rustc",
)
REQUIRED_SCRIPTS = (
    "scripts/setup-windows-build-host.sh",
    "scripts/build-windows-from-linux.sh",
    "scripts/package-windows-runtime.sh",
    "scripts/test-windows-under-wine.sh",
)
WINDOWS_RUST_TARGET = "x86_64-pc-windows-gnu"

_WINDOWS_OUTPUTS = (
    "build/dist/windows/space.exe",
    "build/dist/windows/space-cli.exe",
    "build/windows/CPackConfig.cmake",
    "build/windows/space.ico",
    "scripts/windows-installer.iss",
)
_SETUP_COMMAND = "python3 scripts/opencode_windows_ci_repro.py setup-host --repo-root ."


def _exit_code_for(status: str) -> int:
    return {"pass": 0, "human_decision_required": 2, "fail": 3}.get(status, 3)


def _tail(output: str, *, limit: int = 4000) -> str:
    if len(output) <= limit:
        return output
    return output[-limit:]


def _command_evidence(result: CommandResult) -> dict[str, object]:
    return {
        "args": result.args,
        "returncode": result.returncode,
        "stdout_tail": _tail(result.stdout),
        "stderr_tail": _tail(result.stderr),
    }


def _script_exists(repo: Path, relative: str) -> bool:
    return (repo / relative).is_file()


def _wine_available() -> bool:
    configured_wine = os.environ.get("WINE_CMD")
    if configured_wine and shutil.which(configured_wine) is not None:
        return True
    return shutil.which("wine64") is not None or shutil.which("wine") is not None


def _vcpkg_binary(repo: Path) -> Path:
    vcpkg_root = os.environ.get("VCPKG_ROOT")
    if vcpkg_root:
        return Path(vcpkg_root) / "vcpkg"
    return repo / "vcpkg" / "vcpkg"


def _display_path(repo: Path, path: Path) -> str:
    try:
        return str(path.relative_to(repo))
    except ValueError:
        return str(path)


def _rust_target_installed(repo: Path) -> bool:
    try:
        result = run_command(["rustup", "target", "list", "--installed"], repo, check=False)
    except OSError:
        return False
    if result.returncode != 0:
        return False
    return WINDOWS_RUST_TARGET in {line.strip() for line in result.stdout.splitlines()}


def _response(action: str, result: dict[str, object]) -> dict[str, object]:
    adjusted = dict(result)
    adjusted["action"] = action
    return adjusted


def _is_ubuntu_host() -> bool:
    try:
        lines = Path("/etc/os-release").read_text(encoding="utf-8").splitlines()
    except OSError:
        return False
    values = dict(line.split("=", 1) for line in lines if "=" in line)
    return values.get("ID", "").strip('"') == "ubuntu"


def preflight(repo_root: Path) -> dict[str, object]:
    try:
        repo = ensure_space_repo(repo_root)
    except CapabilityError as error:
        return _failure_for_exception("preflight", error)
    missing: list[str] = []

    missing.extend(tool for tool in REQUIRED_TOOLS if shutil.which(tool) is None)
    missing.extend(script for script in REQUIRED_SCRIPTS if not _script_exists(repo, script))
    vcpkg_binary = _vcpkg_binary(repo)
    if not vcpkg_binary.is_file():
        missing.append(_display_path(repo, vcpkg_binary))
    if not _wine_available():
        missing.append("wine")
    if not _rust_target_installed(repo):
        missing.append(f"rust-target:{WINDOWS_RUST_TARGET}")

    evidence: dict[str, object] = {"repo_root": str(repo), "missing": sorted(missing)}
    if not missing:
        return success("preflight", "Windows CI reproduction prerequisites are available", evidence)

    evidence["code"] = "missing_windows_ci_repro_prerequisites"
    evidence["setup_capability_command"] = _SETUP_COMMAND
    return failure("preflight", "Windows CI reproduction prerequisites are missing", evidence)


def setup_host(repo_root: Path) -> dict[str, object]:
    try:
        repo = ensure_space_repo(repo_root)
    except CapabilityError as error:
        return _failure_for_exception("setup-host", error)
    if sys.platform != "linux" or not _is_ubuntu_host() or shutil.which("sudo") is None:
        return human_decision(
            "setup-host",
            "Windows CI reproduction host setup requires an Ubuntu Linux host with sudo",
            {
                "code": "unsupported_windows_ci_setup_host",
                "platform": sys.platform,
                "ubuntu": _is_ubuntu_host(),
                "sudo_available": shutil.which("sudo") is not None,
            },
        )

    result = run_command(["scripts/setup-windows-build-host.sh"], repo, check=False)
    evidence = _command_evidence(result)
    if result.returncode == 0:
        return success("setup-host", "Windows CI reproduction host setup completed", evidence)
    evidence["code"] = "windows_ci_setup_host_failed"
    return human_decision("setup-host", "Windows CI reproduction host setup failed", evidence)


def _fail_for_command(action: str, step: str, result: CommandResult) -> dict[str, object]:
    evidence = _command_evidence(result)
    evidence["failing_step"] = step
    return failure(action, "Windows CI reproduction step failed", evidence)


def _verify_windows_outputs(repo: Path) -> list[str]:
    return [relative for relative in _WINDOWS_OUTPUTS if not (repo / relative).is_file()]


def reproduce(repo_root: Path) -> dict[str, object]:
    preflight_result = preflight(repo_root)
    if preflight_result["status"] != "pass":
        return _response("reproduce", preflight_result)

    try:
        repo = ensure_space_repo(repo_root)
    except CapabilityError as error:
        return _failure_for_exception("reproduce", error)
    steps: tuple[tuple[str, list[str]], ...] = (
        ("build-windows-from-linux", ["scripts/build-windows-from-linux.sh"]),
        ("package-windows-runtime", ["scripts/package-windows-runtime.sh"]),
    )
    for step, args in steps:
        result = run_command(args, repo, check=False)
        if result.returncode != 0:
            return _fail_for_command("reproduce", step, result)

    missing_outputs = _verify_windows_outputs(repo)
    if missing_outputs:
        return failure(
            "reproduce",
            "Windows CI reproduction outputs are missing after packaging",
            {
                "code": "missing_windows_ci_repro_outputs",
                "failing_step": "verify-windows-outputs",
                "args": [],
                "returncode": 1,
                "stdout_tail": "",
                "stderr_tail": "",
                "missing": missing_outputs,
            },
        )

    wine_result = run_command(["scripts/test-windows-under-wine.sh"], repo, check=False)
    if wine_result.returncode != 0:
        return _fail_for_command("reproduce", "test-windows-under-wine", wine_result)

    return success(
        "reproduce",
        "Windows CI reproduction completed successfully",
        {"repo_root": str(repo), "checked_outputs": list(_WINDOWS_OUTPUTS)},
    )


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("preflight", "setup-host", "reproduce"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("--repo-root", required=True, type=Path)
    return parser.parse_args(argv)


def _failure_for_exception(action: str, error: Exception) -> dict[str, object]:
    if isinstance(error, CapabilityError):
        return failure(action, error.message, {"code": error.code, "details": error.details})
    return failure(
        action,
        "Windows CI reproduction wrapper failed unexpectedly",
        {"code": "unexpected_windows_ci_repro_error", "error_type": type(error).__name__, "error": str(error)},
    )


def main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        if args.command == "preflight":
            result = preflight(args.repo_root)
        elif args.command == "setup-host":
            result = setup_host(args.repo_root)
        else:
            result = reproduce(args.repo_root)
    except Exception as error:
        result = _failure_for_exception(args.command, error)
    print(json.dumps(result, sort_keys=True))
    return _exit_code_for(str(result["status"]))


if __name__ == "__main__":
    raise SystemExit(main())
