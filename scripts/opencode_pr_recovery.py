#!/usr/bin/env python3
"""Guarded stale merged PR recovery for OpenCode finishing."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import opencode_git_integrate as git_integrate
import opencode_pr_operator as pr_operator


def _exit_code_for(result: dict[str, object]) -> int:
    if result.get("status") == "pass":
        return 0
    if result.get("status") == "human_decision_required":
        return 2
    return 1


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


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparser = parser.add_subparsers(dest="command", required=True)
    recovery = subparser.add_parser("create-current-with-followup-recovery")
    recovery.add_argument("--repo-root", required=True, type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        result = recover_merged_current(args.repo_root)
    except Exception as error:  # noqa: BLE001 - CLIs must fail closed with structured JSON.
        result = {
            "status": "fail",
            "action": "create_current_with_followup_recovery",
            "message": "Local stale merged PR recovery wrapper failed unexpectedly",
            "evidence": {"error_type": type(error).__name__, "error": str(error)},
        }
    print(json.dumps(result, indent=2, sort_keys=True))
    return _exit_code_for(result)


if __name__ == "__main__":
    raise SystemExit(main())
