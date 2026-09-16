#!/usr/bin/env python3
"""Guarded Git integration operations for OpenCode capability agents."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from opencode_capabilities import (
    CapabilityError,
    ensure_space_repo,
    failure,
    human_decision,
    run_command,
    success,
    validate_branch_name,
)


def _exit_code_for(result: dict[str, object]) -> int:
    if result.get("status") == "pass":
        return 0
    if result.get("status") == "human_decision_required":
        return 2
    return 3


def _current_branch(repo: Path) -> str:
    return run_command(["git", "branch", "--show-current"], repo).stdout.strip()


def _dirty_output(repo: Path) -> str:
    return run_command(["git", "status", "--porcelain"], repo).stdout


def _origin_main_is_ancestor_of_head(repo: Path) -> bool:
    result = run_command(["git", "merge-base", "--is-ancestor", "origin/main", "HEAD"], repo, check=False)
    if result.returncode == 0:
        return True
    if result.returncode == 1:
        return False
    raise CapabilityError(
        "command_failed",
        "Command failed while evaluating capability guard",
        {"args": result.args, "returncode": result.returncode, "stderr": result.stderr.strip()},
    )


def _derive_followup_branch_name(source_branch: str, short_head_sha: str) -> str:
    return f"{source_branch}-followup-{short_head_sha}"


def _local_branch_exists(repo: Path, branch: str) -> bool:
    ref = f"refs/heads/{branch}"
    result = run_command(["git", "show-ref", "--verify", "--quiet", ref], repo, check=False)
    if result.returncode == 0:
        return True
    if result.returncode == 1:
        return False
    raise CapabilityError(
        "command_failed",
        "Command failed while evaluating capability guard",
        {"args": result.args, "returncode": result.returncode, "stderr": result.stderr.strip()},
    )


def _remote_branch_exists(repo: Path, branch: str) -> bool:
    result = run_command(["git", "ls-remote", "--exit-code", "--heads", "origin", branch], repo, check=False)
    if result.returncode == 0:
        return True
    if result.returncode == 2:
        return False
    raise CapabilityError(
        "command_failed",
        "Command failed while evaluating capability guard",
        {"args": result.args, "returncode": result.returncode, "stderr": result.stderr.strip()},
    )


def _guard_clean_non_main(action: str, repo: Path) -> tuple[str | None, dict[str, object] | None]:
    dirty = _dirty_output(repo).strip()
    branch = _current_branch(repo)
    if dirty:
        return None, human_decision(action, "Worktree is dirty; privileged Git operation requires a clean tree", {"branch": branch, "dirty": True})
    if branch == "main":
        return None, human_decision(action, "Refusing privileged Git operation on protected main branch", {"branch": branch})
    try:
        validate_branch_name(branch)
    except CapabilityError as error:
        return None, human_decision(action, error.message, {"code": error.code, "details": error.details, "branch": branch})
    return branch, None


def git_status(repo_root: Path) -> dict[str, object]:
    action = "git_status"
    try:
        repo = ensure_space_repo(repo_root)
        branch = _current_branch(repo)
        head_sha = run_command(["git", "rev-parse", "HEAD"], repo).stdout.strip()
        origin_main_sha = run_command(["git", "rev-parse", "origin/main"], repo).stdout.strip()
        dirty = bool(_dirty_output(repo).strip())
        merge_base = run_command(["git", "merge-base", "HEAD", "origin/main"], repo).stdout.strip()
        origin_main_is_ancestor = _origin_main_is_ancestor_of_head(repo)
        return success(
            action,
            "Git status collected for bounded integration decision",
            {
                "branch": branch,
                "head_sha": head_sha,
                "dirty": dirty,
                "origin_main_merge_base": merge_base,
                "origin_main_sha": origin_main_sha,
                "origin_main_is_ancestor_of_head": origin_main_is_ancestor,
                "branch_current_with_origin_main": origin_main_is_ancestor,
                "safe_merge_needed": not origin_main_is_ancestor,
            },
        )
    except CapabilityError as error:
        return failure(action, error.message, {"code": error.code, "details": error.details})


def fetch_origin(repo_root: Path) -> dict[str, object]:
    action = "fetch_origin"
    try:
        repo = ensure_space_repo(repo_root)
        result = run_command(["git", "fetch", "origin", "main"], repo)
        return success(action, "Fetched origin/main for bounded integration", {"args": result.args})
    except CapabilityError as error:
        return failure(action, error.message, {"code": error.code, "details": error.details})


def merge_origin_main(repo_root: Path) -> dict[str, object]:
    action = "merge_origin_main"
    try:
        repo = ensure_space_repo(repo_root)
        branch, unsafe = _guard_clean_non_main(action, repo)
        if unsafe is not None:
            return unsafe
        fetch = run_command(["git", "fetch", "origin", "main"], repo)
        merge = run_command(["git", "merge", "--no-edit", "origin/main"], repo)
        return success(action, "Merged origin/main into current branch", {"branch": branch, "commands": [fetch.args, merge.args]})
    except CapabilityError as error:
        return failure(action, error.message, {"code": error.code, "details": error.details})


def push_current(repo_root: Path) -> dict[str, object]:
    action = "push_current"
    try:
        repo = ensure_space_repo(repo_root)
        branch, unsafe = _guard_clean_non_main(action, repo)
        if unsafe is not None:
            return unsafe
        destination = f"HEAD:refs/heads/{branch}"
        result = run_command(["git", "push", "origin", destination], repo)
        return success(action, "Pushed current branch to matching origin branch", {"branch": branch, "args": result.args})
    except CapabilityError as error:
        return failure(action, error.message, {"code": error.code, "details": error.details})


def create_followup_branch(repo_root: Path) -> dict[str, object]:
    action = "create_followup_branch"
    try:
        repo = ensure_space_repo(repo_root)
        dirty = _dirty_output(repo).strip()
        branch = _current_branch(repo)
        if dirty:
            return human_decision(action, "Worktree is dirty; follow-up branch creation requires a clean tree", {"branch": branch, "dirty": True})
        if not branch:
            return human_decision(action, "Refusing follow-up branch creation from detached HEAD", {"branch": branch})
        if branch == "main":
            return human_decision(action, "Refusing follow-up branch creation on protected main branch", {"branch": branch})

        short_head_sha = run_command(["git", "rev-parse", "--short=7", "HEAD"], repo).stdout.strip()
        if not _origin_main_is_ancestor_of_head(repo):
            return human_decision(
                action,
                "Current HEAD does not contain origin/main; update through the bounded merge workflow before creating a follow-up branch",
                {"branch": branch, "origin_main_is_ancestor_of_head": False},
            )

        target_branch = _derive_followup_branch_name(branch, short_head_sha)
        try:
            validate_branch_name(branch)
            validate_branch_name(target_branch)
        except CapabilityError as error:
            return human_decision(action, error.message, {"code": error.code, "details": error.details, "branch": branch, "followup_branch": target_branch})

        if _local_branch_exists(repo, target_branch):
            return human_decision(action, "Follow-up branch already exists locally", {"branch": branch, "followup_branch": target_branch})
        if _remote_branch_exists(repo, target_branch):
            return human_decision(action, "Follow-up branch already exists on origin", {"branch": branch, "followup_branch": target_branch})

        switch = run_command(["git", "switch", "-c", target_branch], repo)
        return success(
            action,
            "Created and switched to deterministic follow-up branch",
            {"source_branch": branch, "followup_branch": target_branch, "short_head_sha": short_head_sha, "args": switch.args},
        )
    except CapabilityError as error:
        return failure(action, error.message, {"code": error.code, "details": error.details})


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("status", "fetch-origin", "merge-origin-main", "push-current", "create-followup-branch"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("--repo-root", required=True, type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    operations = {
        "status": git_status,
        "fetch-origin": fetch_origin,
        "merge-origin-main": merge_origin_main,
        "push-current": push_current,
        "create-followup-branch": create_followup_branch,
    }
    try:
        result = operations[args.command](args.repo_root)
    except Exception as error:  # noqa: BLE001 - CLIs must fail closed with structured JSON.
        result = failure(args.command.replace("-", "_"), "Local Git capability wrapper failed unexpectedly", {"error_type": type(error).__name__, "error": str(error)})
    print(json.dumps(result, indent=2, sort_keys=True))
    return _exit_code_for(result)


if __name__ == "__main__":
    raise SystemExit(main())
