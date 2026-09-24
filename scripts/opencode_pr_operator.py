#!/usr/bin/env python3
"""Guarded GitHub PR operations for OpenCode capability agents."""

from __future__ import annotations

import argparse
import fnmatch
import json
import re
import sys
import time
from pathlib import Path
from typing import Any

from opencode_capabilities import CapabilityError, ensure_space_repo, failure, human_decision, run_command, success, validate_branch_name

SPACE_REPO = "semanticdreams/space2"
PR_VIEW_FIELDS = "state,mergedAt,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,headRefName,headRefOid,url"
NONTERMINAL_STATES = {"queued", "waiting", "pending", "in_progress", "in-progress", "expected", "clean", "unknown", None}
PENDING_ROLLUP_STATUSES = {"queued", "pending", "in-progress", "expected"}
FAILED_ROLLUP_CONCLUSIONS = {"failure", "failed", "cancelled", "timed-out", "action-required"}
DEFAULT_POLL_TIMEOUT_SECONDS = 7200
DEFAULT_POLL_INTERVAL_SECONDS = 100
MAX_RULESET_DETAIL_FETCHES = 5
MAX_FAILED_CHECK_LOG_LINES = 80
MAX_FAILED_CHECK_LOG_CHARS = 12000
GITHUB_ACTIONS_JOB_URL = re.compile(r"^https://github\.com/[^/]+/[^/]+/actions/runs/(\d+)/job/(\d+)(?:[/?#].*)?$")


def _exit_code_for(result: dict[str, object]) -> int:
    if result.get("status") == "pass":
        return 0
    if result.get("status") == "human_decision_required":
        return 2
    return 3


def _safe_branch(action: str, branch: str) -> tuple[str | None, dict[str, object] | None]:
    try:
        return validate_branch_name(branch), None
    except CapabilityError as error:
        return None, human_decision(action, error.message, {"code": error.code, "details": error.details, "branch": branch})


def _current_branch(repo: Path) -> str:
    return run_command(["git", "branch", "--show-current"], repo).stdout.strip()


def _current_head(repo: Path) -> str:
    return run_command(["git", "rev-parse", "HEAD"], repo).stdout.strip()


def _safe_current_branch(action: str, repo: Path) -> tuple[str | None, dict[str, object] | None]:
    return _safe_branch(action, _current_branch(repo))


def _json_loads(text: str) -> Any:
    return json.loads(text) if text.strip() else None


def _command_result_evidence(result: Any, branch: str) -> dict[str, object]:
    return {"branch": branch, "args": result.args, "returncode": result.returncode, "stderr": result.stderr.strip()}


def _is_no_pr_view_result(result: Any) -> bool:
    if result.returncode == 0:
        return False
    output = f"{result.stdout}\n{result.stderr}".lower()
    no_pr_markers = (
        "no pull requests found",
        "no pull request found",
        "could not find any pull requests",
        "could not find any pull request",
    )
    return any(marker in output for marker in no_pr_markers)


def _existing_pr_reuse_evidence(data: dict[str, Any], branch: str, current_head: str, args: list[str]) -> dict[str, object]:
    return {
        "branch": branch,
        "current_head": current_head,
        "pr_head": data.get("headRefOid"),
        "pr_state": data.get("state"),
        "pr_url": data.get("url"),
        "args": args,
    }


def _required_checks_include_test(required_checks: Any) -> bool:
    if not isinstance(required_checks, dict):
        return False
    contexts = required_checks.get("contexts")
    if isinstance(contexts, list) and "test" in contexts:
        return True
    checks = required_checks.get("checks")
    if isinstance(checks, list):
        for check in checks:
            if isinstance(check, dict) and check.get("context") == "test":
                return True
    return False


def _classic_protection_requires_test(protection: Any) -> bool:
    if not isinstance(protection, dict):
        return False
    return _required_checks_include_test(protection.get("required_status_checks"))


def _ruleset_applies_to_main(ruleset: dict[str, Any]) -> bool:
    if ruleset.get("enforcement") != "active":
        return False
    conditions = ruleset.get("conditions")
    if not isinstance(conditions, dict):
        return False
    ref_name = conditions.get("ref_name", {})
    if not isinstance(ref_name, dict):
        return False
    include = ref_name.get("include")
    exclude = ref_name.get("exclude", [])
    if not isinstance(include, list) or not isinstance(exclude, list):
        return False
    main_ref = "refs/heads/main"
    aliases = {"main", "refs/heads/main", "~DEFAULT_BRANCH"}
    included = any(pattern in aliases or fnmatch.fnmatch(main_ref, str(pattern)) for pattern in include)
    excluded = any(pattern in aliases or fnmatch.fnmatch(main_ref, str(pattern)) for pattern in exclude)
    return included and not excluded


def _ruleset_rule_requires_test(rule: Any) -> bool:
    if not isinstance(rule, dict) or rule.get("type") != "required_status_checks":
        return False
    parameters = rule.get("parameters")
    if not isinstance(parameters, dict):
        return False
    required = parameters.get("required_status_checks")
    if not isinstance(required, list):
        return False
    for check in required:
        if check == "test":
            return True
        if isinstance(check, dict) and check.get("context") == "test":
            return True
    return False


def _rule_list_proofs(rules: Any) -> tuple[bool, bool]:
    if not isinstance(rules, list):
        return False, False
    requires_test = any(_ruleset_rule_requires_test(rule) for rule in rules)
    has_merge_queue = any(isinstance(rule, dict) and rule.get("type") == "merge_queue" for rule in rules)
    return requires_test, has_merge_queue


def _active_main_ruleset_proofs(rulesets: Any) -> tuple[bool, bool]:
    if not isinstance(rulesets, list):
        return False, False
    requires_test = False
    has_merge_queue = False
    for ruleset in rulesets:
        if not isinstance(ruleset, dict) or not _ruleset_applies_to_main(ruleset):
            continue
        ruleset_requires_test, ruleset_has_merge_queue = _rule_list_proofs(ruleset.get("rules"))
        requires_test = requires_test or ruleset_requires_test
        has_merge_queue = has_merge_queue or ruleset_has_merge_queue
    return requires_test, has_merge_queue


def _ruleset_detail_path(ruleset: dict[str, Any]) -> str | None:
    ruleset_id = ruleset.get("id")
    if isinstance(ruleset_id, int) or (isinstance(ruleset_id, str) and ruleset_id.isdigit()):
        return f"repos/{SPACE_REPO}/rulesets/{ruleset_id}"
    links = ruleset.get("_links")
    self_link = links.get("self") if isinstance(links, dict) else None
    href = self_link.get("href") if isinstance(self_link, dict) else self_link
    if not isinstance(href, str):
        return None
    api_prefix = "https://api.github.com/"
    path = href.removeprefix(api_prefix)
    allowed_prefix = f"repos/{SPACE_REPO}/rulesets/"
    if path.startswith(allowed_prefix):
        return path
    return None


def _ruleset_detail_paths(rulesets: Any) -> list[str]:
    if not isinstance(rulesets, list):
        return []
    paths: list[str] = []
    seen: set[str] = set()
    for ruleset in rulesets:
        if not isinstance(ruleset, dict):
            continue
        path = _ruleset_detail_path(ruleset)
        if path is None or path in seen:
            continue
        paths.append(path)
        seen.add(path)
        if len(paths) >= MAX_RULESET_DETAIL_FETCHES:
            break
    return paths


def pr_auth_status(repo_root: Path) -> dict[str, object]:
    action = "pr_auth_status"
    try:
        repo = ensure_space_repo(repo_root)
        result = run_command(["gh", "auth", "status"], repo, check=False)
        if result.returncode != 0:
            return human_decision(action, "GitHub CLI authentication is missing or invalid", {"returncode": result.returncode})
        return success(action, "GitHub CLI authentication is available", {"args": result.args})
    except CapabilityError as error:
        return failure(action, error.message, {"code": error.code, "details": error.details})


def check_main_protection(repo_root: Path) -> dict[str, object]:
    action = "check_main_protection"
    try:
        repo = ensure_space_repo(repo_root)
        protection_result = run_command(["gh", "api", f"repos/{SPACE_REPO}/branches/main/protection"], repo, check=False)
        rulesets_result = run_command(["gh", "api", f"repos/{SPACE_REPO}/rulesets"], repo, check=False)
        protection = _json_loads(protection_result.stdout) if protection_result.returncode == 0 else None
        rulesets = _json_loads(rulesets_result.stdout) if rulesets_result.returncode == 0 else None
    except (CapabilityError, json.JSONDecodeError) as error:
        details = {"error_type": type(error).__name__, "error": str(error)}
        if isinstance(error, CapabilityError):
            details = {"code": error.code, "details": error.details}
        return human_decision(action, "Could not prove required main protection and merge queue from GitHub responses", details)

    classic_has_test = _classic_protection_requires_test(protection)
    ruleset_has_test, ruleset_has_queue = _active_main_ruleset_proofs(rulesets)
    effective_rules = None
    if not (classic_has_test or ruleset_has_test) or not ruleset_has_queue:
        try:
            effective_rules_result = run_command(["gh", "api", f"repos/{SPACE_REPO}/rules/branches/main"], repo, check=False)
            effective_rules = _json_loads(effective_rules_result.stdout) if effective_rules_result.returncode == 0 else None
        except (CapabilityError, json.JSONDecodeError):
            effective_rules = None
    effective_has_test, effective_has_queue = _rule_list_proofs(effective_rules)
    detailed_rulesets: list[dict[str, Any]] = []
    if not (classic_has_test or ruleset_has_test or effective_has_test) or not (ruleset_has_queue or effective_has_queue):
        for path in _ruleset_detail_paths(rulesets):
            try:
                detail_result = run_command(["gh", "api", path], repo, check=False)
                detail = _json_loads(detail_result.stdout) if detail_result.returncode == 0 else None
            except (CapabilityError, json.JSONDecodeError):
                detail = None
            if isinstance(detail, dict):
                detailed_rulesets.append(detail)
    detailed_has_test, detailed_has_queue = _active_main_ruleset_proofs(detailed_rulesets)
    has_test = classic_has_test or ruleset_has_test or effective_has_test or detailed_has_test
    has_queue = ruleset_has_queue or effective_has_queue or detailed_has_queue
    evidence = {
        "classic_protection_available": protection is not None,
        "rulesets_available": rulesets is not None,
        "effective_branch_rules_available": effective_rules is not None,
        "detailed_rulesets_available": len(detailed_rulesets) > 0,
        "detailed_rulesets_checked": len(detailed_rulesets),
        "classic_required_test_check_proven": classic_has_test,
        "active_main_ruleset_required_test_check_proven": ruleset_has_test,
        "active_main_ruleset_merge_queue_proven": ruleset_has_queue,
        "effective_branch_rules_required_test_check_proven": effective_has_test,
        "effective_branch_rules_merge_queue_proven": effective_has_queue,
        "detailed_rulesets_required_test_check_proven": detailed_has_test,
        "detailed_rulesets_merge_queue_proven": detailed_has_queue,
        "required_test_check_proven": has_test,
        "merge_queue_proven": has_queue,
    }
    if not has_test or not has_queue:
        return human_decision(action, "Main protection does not prove both required test and merge queue", evidence)
    return success(action, "Main protection proves required test and merge queue", evidence)


def create_pr(repo_root: Path, head: str) -> dict[str, object]:
    action = "create_pr"
    try:
        repo = ensure_space_repo(repo_root)
    except CapabilityError as error:
        return failure(action, error.message, {"code": error.code, "details": error.details})
    branch, unsafe = _safe_branch(action, head)
    if unsafe is not None:
        return unsafe
    try:
        result = run_command(["gh", "pr", "create", "--base", "main", "--head", branch, "--fill"], repo)
        return success(action, "Created pull request targeting main", {"branch": branch, "url": result.stdout.strip(), "args": result.args})
    except CapabilityError as error:
        return human_decision(action, error.message, {"code": error.code, "details": error.details, "branch": branch})


def create_current_pr(repo_root: Path) -> dict[str, object]:
    action = "create_pr"
    try:
        repo = ensure_space_repo(repo_root)
        branch, unsafe = _safe_current_branch(action, repo)
        if unsafe is not None:
            return unsafe
        view_result = run_command(["gh", "pr", "view", branch, "--json", PR_VIEW_FIELDS], repo, check=False)
        if view_result.returncode == 0:
            data = _json_loads(view_result.stdout)
            if not isinstance(data, dict):
                return human_decision(action, "GitHub PR view response was ambiguous", _command_result_evidence(view_result, branch))
            current_head = _current_head(repo)
            reuse_evidence = _existing_pr_reuse_evidence(data, branch, current_head, view_result.args)
            if data.get("headRefOid") != current_head:
                return human_decision(action, "Existing pull request does not match current branch HEAD", reuse_evidence)
            if data.get("state") != "OPEN":
                return human_decision(action, "Existing pull request is not open for the current branch HEAD", reuse_evidence)
            return success(
                action,
                "Pull request already exists targeting main",
                {"branch": branch, "url": data.get("url"), "state": data.get("state"), "pr": data, "args": view_result.args},
            )
        if not _is_no_pr_view_result(view_result):
            return human_decision(action, "Could not determine whether pull request already exists", _command_result_evidence(view_result, branch))
        result = run_command(["gh", "pr", "create", "--base", "main", "--head", branch, "--fill"], repo, check=False)
        if result.returncode != 0:
            return human_decision(action, "Could not create pull request safely", _command_result_evidence(result, branch))
        return success(action, "Created pull request targeting main", {"branch": branch, "url": result.stdout.strip(), "args": result.args})
    except CapabilityError as error:
        return human_decision(action, error.message, {"code": error.code, "details": error.details})


def enable_auto_merge(repo_root: Path, branch: str) -> dict[str, object]:
    action = "enable_auto_merge"
    try:
        repo = ensure_space_repo(repo_root)
    except CapabilityError as error:
        return failure(action, error.message, {"code": error.code, "details": error.details})
    safe, unsafe = _safe_branch(action, branch)
    if unsafe is not None:
        return unsafe
    protection = check_main_protection(repo_root)
    if protection.get("status") != "pass":
        return human_decision(action, "Auto-merge requires proven main protection and merge queue", {"branch": safe, "protection": protection})
    try:
        result = run_command(["gh", "pr", "merge", safe, "--auto", "--merge"], repo, check=False)
        output = f"{result.stdout}\n{result.stderr}".lower()
        if result.returncode != 0 or "rebase" in output:
            return human_decision(action, "Auto-merge could not be enabled safely", {"branch": safe, "returncode": result.returncode})
        return success(action, "Enabled auto-merge with merge commits", {"branch": safe, "args": result.args})
    except CapabilityError as error:
        return human_decision(action, error.message, {"code": error.code, "details": error.details, "branch": safe})


def enable_auto_merge_current(repo_root: Path) -> dict[str, object]:
    action = "enable_auto_merge"
    try:
        repo = ensure_space_repo(repo_root)
        safe, unsafe = _safe_current_branch(action, repo)
        if unsafe is not None:
            return unsafe
        return enable_auto_merge(repo_root, safe)
    except CapabilityError as error:
        return failure(action, error.message, {"code": error.code, "details": error.details})


def view_pr(repo_root: Path, branch: str) -> dict[str, object]:
    action = "view_pr"
    try:
        repo = ensure_space_repo(repo_root)
    except CapabilityError as error:
        return failure(action, error.message, {"code": error.code, "details": error.details})
    safe, unsafe = _safe_branch(action, branch)
    if unsafe is not None:
        return unsafe
    try:
        result = run_command(["gh", "pr", "view", safe, "--json", PR_VIEW_FIELDS], repo)
        data = _json_loads(result.stdout)
        if not isinstance(data, dict):
            return human_decision(action, "GitHub PR view response was ambiguous", {"branch": safe})
        return success(action, "Loaded pull request status", {"branch": safe, "pr": data})
    except (CapabilityError, json.JSONDecodeError) as error:
        return human_decision(action, "Could not load pull request status safely", {"error_type": type(error).__name__, "error": str(error), "branch": safe})


def view_current_pr(repo_root: Path) -> dict[str, object]:
    action = "view_pr"
    try:
        repo = ensure_space_repo(repo_root)
        safe, unsafe = _safe_current_branch(action, repo)
        if unsafe is not None:
            return unsafe
        return view_pr(repo_root, safe)
    except CapabilityError as error:
        return failure(action, error.message, {"code": error.code, "details": error.details})


def _failed_rollup_checks(data: dict[str, Any]) -> list[dict[str, Any]]:
    failed_checks = []
    for check in data.get("statusCheckRollup") or []:
        if not isinstance(check, dict):
            continue
        conclusion = _normalized_rollup_value(check.get("conclusion"))
        if conclusion in FAILED_ROLLUP_CONCLUSIONS:
            failed_checks.append(check)
    return failed_checks


def _bounded_log_excerpt(log_text: str) -> str:
    lines = log_text.replace("\x00", "").splitlines()
    excerpt = "\n".join(lines[-MAX_FAILED_CHECK_LOG_LINES:])
    if len(excerpt) > MAX_FAILED_CHECK_LOG_CHARS:
        return excerpt[-MAX_FAILED_CHECK_LOG_CHARS:]
    return excerpt


def _failed_check_metadata(check: dict[str, Any]) -> dict[str, object]:
    fields = ("name", "workflowName", "status", "conclusion", "detailsUrl", "startedAt", "completedAt")
    return {field: check[field] for field in fields if field in check}


def _actions_run_job_ids(details_url: Any) -> tuple[str, str] | None:
    if not isinstance(details_url, str):
        return None
    match = GITHUB_ACTIONS_JOB_URL.fullmatch(details_url)
    if match is None:
        return None
    return match.group(1), match.group(2)


def _failed_check_evidence(check: dict[str, Any], repo: Path) -> dict[str, object]:
    evidence = _failed_check_metadata(check)
    details_url = check.get("detailsUrl")
    run_job_ids = _actions_run_job_ids(details_url)
    if run_job_ids is None:
        if details_url:
            evidence["log_unavailable"] = "detailsUrl did not contain a parseable GitHub Actions run/job id"
        else:
            evidence["log_unavailable"] = "detailsUrl was missing"
        return evidence

    run_id, job_id = run_job_ids
    evidence["run_id"] = run_id
    evidence["job_id"] = job_id
    log_result = run_command(["gh", "run", "view", run_id, "--job", job_id, "--log"], repo, check=False)
    if log_result.returncode == 0:
        evidence["log_excerpt"] = _bounded_log_excerpt(log_result.stdout)
        return evidence
    evidence["log_unavailable"] = "gh run view --job failed"
    evidence["log_command"] = {"args": log_result.args, "returncode": log_result.returncode, "stderr": log_result.stderr.strip()}
    return evidence


def _failed_rollup_evidence(data: dict[str, Any], repo: Path) -> list[dict[str, object]]:
    return [_failed_check_evidence(check, repo) for check in _failed_rollup_checks(data)]


def _normalized_rollup_value(value: Any) -> Any:
    if not isinstance(value, str):
        return value
    return value.strip().lower().replace("_", "-")


def _rollup_check_is_completed(check: dict[str, Any]) -> bool:
    return _normalized_rollup_value(check.get("status")) == "completed"


def _rollup_check_is_check_run(check: dict[str, Any]) -> bool:
    return check.get("__typename") == "CheckRun"


def _rollup_conclusion_is_blank_or_missing(check: dict[str, Any]) -> bool:
    conclusion = check.get("conclusion")
    return conclusion is None or (isinstance(conclusion, str) and conclusion.strip() == "")


def _rollup_has_explicit_pending_state(check: dict[str, Any]) -> bool:
    return (
        _normalized_rollup_value(check.get("status")) in PENDING_ROLLUP_STATUSES
        or _normalized_rollup_value(check.get("state")) in PENDING_ROLLUP_STATUSES
    )


def _has_pending_rollup_check(data: dict[str, Any]) -> bool:
    for check in data.get("statusCheckRollup") or []:
        if not isinstance(check, dict):
            continue
        if _rollup_has_explicit_pending_state(check):
            return True
        if _rollup_check_is_check_run(check) and _rollup_conclusion_is_blank_or_missing(check) and not _rollup_check_is_completed(check):
            return True
    return False


def poll_merge_queue(repo_root: Path, branch: str, timeout_seconds: int, interval_seconds: int) -> dict[str, object]:
    action = "poll_merge_queue"
    try:
        repo = ensure_space_repo(repo_root)
    except CapabilityError as error:
        return failure(action, error.message, {"code": error.code, "details": error.details})
    safe, unsafe = _safe_branch(action, branch)
    if unsafe is not None:
        return unsafe
    deadline = time.monotonic() + max(timeout_seconds, 0)
    attempts = 0
    try:
        while True:
            attempts += 1
            result = run_command(["gh", "pr", "view", safe, "--json", PR_VIEW_FIELDS], repo)
            data = _json_loads(result.stdout)
            if not isinstance(data, dict):
                return human_decision(action, "GitHub PR view response was ambiguous", {"branch": safe, "attempts": attempts})
            if data.get("mergedAt"):
                return success(action, "Pull request has merged", {"branch": safe, "merged_at": data.get("mergedAt"), "attempts": attempts})
            if data.get("state") == "CLOSED":
                return human_decision(action, "Pull request closed without mergedAt", {"branch": safe, "attempts": attempts})
            failed_checks = _failed_rollup_evidence(data, repo)
            if failed_checks:
                return human_decision(action, "Required merge queue check failed", {"branch": safe, "attempts": attempts, "failed_checks": failed_checks})
            merge_state = data.get("mergeStateStatus")
            normalized_merge_state = merge_state.lower() if isinstance(merge_state, str) else merge_state
            mergeable = data.get("mergeable")
            normalized_mergeable = mergeable.lower() if isinstance(mergeable, str) else mergeable
            if normalized_merge_state == "dirty" or normalized_mergeable == "conflicting":
                return human_decision(
                    action,
                    "Pull request has merge conflicts or is not mergeable",
                    {"branch": safe, "merge_state": merge_state, "mergeable": mergeable, "attempts": attempts},
                )
            if normalized_merge_state not in NONTERMINAL_STATES and not _has_pending_rollup_check(data):
                return human_decision(action, "Pull request merge queue state is ambiguous or unsupported", {"branch": safe, "merge_state": merge_state, "attempts": attempts})
            if time.monotonic() >= deadline:
                return human_decision(action, "Timed out waiting for merge queue to merge pull request", {"branch": safe, "attempts": attempts})
            time.sleep(interval_seconds)
    except (CapabilityError, json.JSONDecodeError) as error:
        return human_decision(action, "Could not poll merge queue safely", {"error_type": type(error).__name__, "error": str(error), "branch": safe})


def poll_current_merge_queue(repo_root: Path) -> dict[str, object]:
    action = "poll_merge_queue"
    try:
        repo = ensure_space_repo(repo_root)
        safe, unsafe = _safe_current_branch(action, repo)
        if unsafe is not None:
            return unsafe
        return poll_merge_queue(repo_root, safe, DEFAULT_POLL_TIMEOUT_SECONDS, DEFAULT_POLL_INTERVAL_SECONDS)
    except CapabilityError as error:
        return failure(action, error.message, {"code": error.code, "details": error.details})


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("auth-status", "check-main-protection", "create-current", "enable-auto-merge-current", "view-current", "poll-merge-queue-current"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("--repo-root", required=True, type=Path)
    create = subparsers.add_parser("create")
    create.add_argument("--repo-root", required=True, type=Path)
    create.add_argument("--head", required=True)
    for command in ("enable-auto-merge", "view"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("--repo-root", required=True, type=Path)
        subparser.add_argument("--branch", required=True)
    poll = subparsers.add_parser("poll-merge-queue")
    poll.add_argument("--repo-root", required=True, type=Path)
    poll.add_argument("--branch", required=True)
    poll.add_argument("--timeout-seconds", required=True, type=int)
    poll.add_argument("--interval-seconds", required=True, type=int)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        if args.command == "auth-status":
            result = pr_auth_status(args.repo_root)
        elif args.command == "check-main-protection":
            result = check_main_protection(args.repo_root)
        elif args.command == "create-current":
            result = create_current_pr(args.repo_root)
        elif args.command == "enable-auto-merge-current":
            result = enable_auto_merge_current(args.repo_root)
        elif args.command == "view-current":
            result = view_current_pr(args.repo_root)
        elif args.command == "poll-merge-queue-current":
            result = poll_current_merge_queue(args.repo_root)
        elif args.command == "create":
            result = create_pr(args.repo_root, args.head)
        elif args.command == "enable-auto-merge":
            result = enable_auto_merge(args.repo_root, args.branch)
        elif args.command == "view":
            result = view_pr(args.repo_root, args.branch)
        else:
            result = poll_merge_queue(args.repo_root, args.branch, args.timeout_seconds, args.interval_seconds)
    except Exception as error:  # noqa: BLE001 - CLIs must fail closed with structured JSON.
        result = failure(args.command.replace("-", "_"), "Local GitHub capability wrapper failed unexpectedly", {"error_type": type(error).__name__, "error": str(error)})
    print(json.dumps(result, indent=2, sort_keys=True))
    return _exit_code_for(result)


if __name__ == "__main__":
    raise SystemExit(main())
