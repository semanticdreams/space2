#!/usr/bin/env python3
"""Guard helpers for bounded OpenCode capability scripts."""

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


class CapabilityError(Exception):
    """Raised when a capability precondition fails closed."""

    def __init__(self, code: str, message: str, details: dict[str, object] | None = None) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.details = details or {}


_TRUSTED_SPACE_REMOTES = (
    re.compile(r"^git@github\.com:semanticdreams/space2(?:\.git)?$"),
    re.compile(r"^ssh://git@github\.com/semanticdreams/space2(?:\.git)?$"),
    re.compile(r"^https://github\.com/semanticdreams/space2(?:\.git)?$"),
)


@dataclass(frozen=True)
class CommandResult:
    args: list[str]
    returncode: int
    stdout: str
    stderr: str


def _response(status: str, action: str, message: str, evidence: dict[str, object]) -> dict[str, object]:
    return {"status": status, "action": action, "message": message, "evidence": evidence}


def success(action: str, message: str, evidence: dict[str, object]) -> dict[str, object]:
    return _response("pass", action, message, evidence)


def human_decision(action: str, message: str, evidence: dict[str, object]) -> dict[str, object]:
    return _response("human_decision_required", action, message, evidence)


def failure(action: str, message: str, evidence: dict[str, object]) -> dict[str, object]:
    return _response("fail", action, message, evidence)


def run_command(args: Sequence[str], cwd: Path, check: bool = True) -> CommandResult:
    completed = subprocess.run(
        list(args),
        cwd=cwd,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    result = CommandResult(list(args), completed.returncode, completed.stdout, completed.stderr)
    if check and result.returncode != 0:
        raise CapabilityError(
            "command_failed",
            "Command failed while evaluating capability guard",
            {"args": result.args, "returncode": result.returncode, "stderr": result.stderr.strip()},
        )
    return result


def _is_trusted_space_origin(origin: str) -> bool:
    return any(pattern.fullmatch(origin) for pattern in _TRUSTED_SPACE_REMOTES)


def ensure_space_repo(repo_root: Path) -> Path:
    resolved = repo_root.expanduser().resolve()
    if not resolved.exists():
        raise CapabilityError("invalid_repo", "Repository root does not exist", {"repo_root": str(resolved)})

    top_level = run_command(["git", "rev-parse", "--show-toplevel"], resolved).stdout.strip()
    if Path(top_level).resolve() != resolved:
        raise CapabilityError(
            "invalid_repo",
            "Repository root is not the git top-level",
            {"repo_root": str(resolved), "git_top_level": top_level},
        )

    missing = [str(path.relative_to(resolved)) for path in (resolved / "AGENTS.md", resolved / ".opencode" / "opencode.json") if not path.exists()]
    if missing:
        raise CapabilityError("invalid_repo", "Repository is missing Space markers", {"missing": missing})

    origin = run_command(["git", "remote", "get-url", "origin"], resolved).stdout.strip()
    if not _is_trusted_space_origin(origin):
        raise CapabilityError("invalid_repo", "Repository origin is not trusted Space remote", {"origin": origin})

    return resolved


_BRANCH_PATTERNS = [
    re.compile(r"^automation/daily-devlog/\d{4}-\d{2}-\d{2}$"),
    re.compile(r"^automation/weekly-agent-workflow/\d{4}-W\d{2}$"),
    re.compile(r"^opencode/workflow-debug/[A-Za-z0-9][A-Za-z0-9._-]*$"),
    re.compile(r"^opencode/workflow-debug-pr/[A-Za-z0-9][A-Za-z0-9._-]*$"),
    re.compile(r"^fast-dev/local-main-[A-Fa-f0-9]{7}$"),
    re.compile(r"^(feature|fix|docs|chore)/[A-Za-z0-9][A-Za-z0-9._/-]*$"),
    re.compile(r"^juicyrebel/[A-Za-z0-9][A-Za-z0-9._/-]*$"),
]


def validate_branch_name(branch: str) -> str:
    if not branch:
        raise CapabilityError("invalid_branch", "Branch name is empty")
    if branch in {"main", "origin/main"}:
        raise CapabilityError("invalid_branch", "Branch name targets protected main", {"branch": branch})
    if re.search(r"\s", branch):
        raise CapabilityError("invalid_branch", "Branch name contains whitespace", {"branch": branch})
    parts = branch.split("/")
    if any(part in {"", ".", ".."} for part in parts) or branch.startswith("/"):
        raise CapabilityError("invalid_branch", "Branch name contains traversal or empty path segments", {"branch": branch})
    if branch.endswith(".lock") or any(part.endswith(".lock") for part in parts):
        raise CapabilityError("invalid_branch", "Branch name uses a forbidden .lock suffix", {"branch": branch})
    if not any(pattern.fullmatch(branch) for pattern in _BRANCH_PATTERNS):
        raise CapabilityError("invalid_branch", "Branch name is outside the allowed capability policy", {"branch": branch})
    return branch


def _is_inside(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
    except ValueError:
        return False
    return True


def _safe_relative(path: Path, root: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return "<outside-repo>"


def _git_top_level_containing(path: Path) -> Path | None:
    if not path.exists():
        return None
    cwd = path if path.is_dir() else path.parent
    result = run_command(["git", "rev-parse", "--show-toplevel"], cwd, check=False)
    if result.returncode != 0:
        return None
    return Path(result.stdout.strip()).resolve()


def _trusted_opencode_entry_target(resolved: Path, relative_name: str) -> Path | None:
    top_level = _git_top_level_containing(resolved)
    if top_level is None:
        return None
    try:
        trusted_repo = ensure_space_repo(top_level)
    except CapabilityError:
        return None
    expected_target = (trusted_repo / ".opencode" / relative_name).resolve()
    if resolved != expected_target:
        return None
    return expected_target


def _is_sensitive_entry(path: Path) -> bool:
    name = path.name.lower()
    lowered = str(path).lower()
    if name in {"auth.json", "auth.jsonc"}:
        return True
    if "token" in name or "secret" in name or "credential" in name:
        return True
    if name.endswith((".db", ".sqlite", ".sqlite3", ".log")):
        return True
    return "tool-output" in lowered or "tool_output" in lowered or "logs" in lowered


def audit_opencode_home(repo_root: Path, opencode_home: Path) -> dict[str, object]:
    action = "audit_opencode_home"
    try:
        repo = ensure_space_repo(repo_root)
    except CapabilityError as error:
        return failure(action, error.message, {"code": error.code, "details": error.details})

    home = opencode_home.expanduser().resolve()
    expected = ("opencode.json", "agents", "skills")

    if not home.exists() or not home.is_dir():
        return human_decision(action, "OpenCode home is missing or is not a directory", {"opencode_home": str(home)})

    checked: dict[str, str] = {}
    unsafe: list[dict[str, str]] = []
    for relative_name in expected:
        entry = home / relative_name
        if not entry.is_symlink():
            unsafe.append({"entry": relative_name, "reason": "expected_symlink_missing"})
            continue
        resolved = entry.resolve()
        trusted_target = _trusted_opencode_entry_target(resolved, relative_name)
        if trusted_target is None:
            top_level = _git_top_level_containing(resolved)
            if top_level is None:
                unsafe.append({"entry": relative_name, "reason": "symlink_target_outside_repo"})
                continue
            unsafe.append(
                {
                    "entry": relative_name,
                    "reason": "symlink_target_not_project_opencode_entry",
                    "target": _safe_relative(resolved, top_level),
                }
            )
            continue
        checked[relative_name] = (
            _safe_relative(trusted_target, repo) if _is_inside(trusted_target, repo) else str(trusted_target)
        )

    allowed_support = {"package.json", "package-lock.json", "plugins/rtk.ts"}
    local_support: list[str] = []
    skipped_sensitive_count = 0
    unexpected: list[str] = []
    for entry in home.iterdir():
        if entry.name in expected:
            continue
        if _is_sensitive_entry(entry):
            skipped_sensitive_count += 1
            continue
        if entry.name in {"package.json", "package-lock.json"}:
            if entry.is_symlink():
                unsafe.append({"entry": entry.name, "reason": "support_entry_is_symlink"})
            elif entry.is_file():
                local_support.append(entry.name)
            else:
                unsafe.append({"entry": entry.name, "reason": "support_entry_is_not_regular_file"})
            continue
        if entry.name == "plugins":
            if entry.is_symlink():
                unsafe.append({"entry": entry.name, "reason": "support_entry_is_symlink"})
                continue
            if not entry.is_dir():
                unsafe.append({"entry": entry.name, "reason": "support_entry_is_not_local_directory"})
                continue
            plugin = entry / "rtk.ts"
            if plugin.is_symlink():
                unsafe.append({"entry": "plugins/rtk.ts", "reason": "support_entry_is_symlink"})
            elif plugin.exists() and plugin.is_file():
                local_support.append("plugins/rtk.ts")
            elif plugin.exists():
                unsafe.append({"entry": "plugins/rtk.ts", "reason": "support_entry_is_not_regular_file"})
            plugin_unexpected = [child.name for child in entry.iterdir() if child.name != "rtk.ts" and not _is_sensitive_entry(child)]
            unexpected.extend(f"plugins/{name}" for name in plugin_unexpected)
            continue
        unexpected.append(entry.name)

    evidence: dict[str, object] = {
        "opencode_home": str(home),
        "repo_root": str(repo),
        "checked_symlinks": checked,
        "local_support_files": sorted(name for name in local_support if name in allowed_support),
        "sensitive_entries_skipped": skipped_sensitive_count,
    }
    if unsafe:
        evidence["unsafe_entries"] = unsafe
        return human_decision(action, "OpenCode home has config links that are missing or outside the approved repo", evidence)
    if unexpected:
        evidence["unexpected_entries"] = sorted(unexpected)
        return human_decision(action, "OpenCode home contains unexpected non-secret entries", evidence)
    return success(action, "OpenCode home config points at the Space project config", evidence)
