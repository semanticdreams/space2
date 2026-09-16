import json
import sys
from pathlib import Path

import pytest

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_ROOT))

import opencode_capabilities as capabilities
import opencode_pr_operator as pr_operator


def command_result(args: list[str], stdout: str = "", returncode: int = 0, stderr: str = "") -> capabilities.CommandResult:
    return capabilities.CommandResult(args=args, returncode=returncode, stdout=stdout, stderr=stderr)


class GhRunner:
    def __init__(self, outputs: dict[tuple[str, ...], str | capabilities.CommandResult]) -> None:
        self.outputs = outputs
        self.calls: list[list[str]] = []

    def __call__(self, args, cwd: Path, check: bool = True):
        del cwd, check
        args = list(args)
        self.calls.append(args)
        output = self.outputs.get(tuple(args), "")
        if isinstance(output, capabilities.CommandResult):
            return output
        return command_result(args, output)


@pytest.fixture
def trusted_repo(monkeypatch, tmp_path: Path) -> Path:
    repo = tmp_path / "space"
    repo.mkdir()
    monkeypatch.setattr(pr_operator, "ensure_space_repo", lambda repo_root: repo)
    return repo


def test_auth_status_runs_only_gh_auth_status(monkeypatch, trusted_repo: Path) -> None:
    runner = GhRunner({("gh", "auth", "status"): "Logged in\n"})
    monkeypatch.setattr(pr_operator, "run_command", runner)

    result = pr_operator.pr_auth_status(trusted_repo)

    assert result["status"] == "pass"
    assert runner.calls == [["gh", "auth", "status"]]


def test_create_always_targets_base_main_validates_head_and_rejects_invalid_branch(monkeypatch, trusted_repo: Path) -> None:
    runner = GhRunner(
        {
            (
                "gh",
                "pr",
                "create",
                "--base",
                "main",
                "--head",
                "feature/opencode-capabilities",
                "--fill",
            ): "https://github.com/semanticdreams/space2/pull/123\n"
        }
    )
    monkeypatch.setattr(pr_operator, "run_command", runner)

    result = pr_operator.create_pr(trusted_repo, "feature/opencode-capabilities")

    invalid = pr_operator.create_pr(trusted_repo, "bad branch")


    assert result["status"] == "pass"
    assert invalid["status"] == "human_decision_required"
    assert runner.calls == [
        [
            "gh",
            "pr",
            "create",
            "--base",
            "main",
            "--head",
            "feature/opencode-capabilities",
            "--fill",
        ]
    ]


def test_create_current_uses_validated_current_branch_without_cli_branch_argument(monkeypatch, trusted_repo: Path) -> None:
    runner = GhRunner(
        {
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
            (
                "gh",
                "pr",
                "view",
                "feature/opencode-capabilities",
                "--json",
                "state,mergedAt,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,headRefName,headRefOid,url",
            ): command_result(
                ["gh", "pr", "view", "feature/opencode-capabilities", "--json", pr_operator.PR_VIEW_FIELDS],
                returncode=1,
                stderr="no pull requests found",
            ),
            (
                "gh",
                "pr",
                "create",
                "--base",
                "main",
                "--head",
                "feature/opencode-capabilities",
                "--fill",
            ): "https://github.com/semanticdreams/space2/pull/123\n",
        }
    )
    monkeypatch.setattr(pr_operator, "run_command", runner)

    result = pr_operator.create_current_pr(trusted_repo)

    assert result["status"] == "pass"
    assert runner.calls == [
        ["git", "branch", "--show-current"],
        [
            "gh",
            "pr",
            "view",
            "feature/opencode-capabilities",
            "--json",
            "state,mergedAt,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,headRefName,headRefOid,url",
        ],
        ["gh", "pr", "create", "--base", "main", "--head", "feature/opencode-capabilities", "--fill"],
    ]


def test_create_current_returns_existing_pr_without_creating(monkeypatch, trusted_repo: Path) -> None:
    head = "31c62bc214b483adc95cbe234ce826b085f66225"
    pr = {"url": "https://github.com/semanticdreams/space2/pull/123", "state": "OPEN", "headRefOid": head}
    runner = GhRunner(
        {
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
            ("git", "rev-parse", "HEAD"): f"{head}\n",
            (
                "gh",
                "pr",
                "view",
                "feature/opencode-capabilities",
                "--json",
                "state,mergedAt,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,headRefName,headRefOid,url",
            ): json.dumps(pr),
        }
    )
    monkeypatch.setattr(pr_operator, "run_command", runner)

    result = pr_operator.create_current_pr(trusted_repo)

    assert result["status"] == "pass"
    assert result["evidence"]["url"] == pr["url"]
    assert result["evidence"]["pr"] == pr
    assert runner.calls == [
        ["git", "branch", "--show-current"],
        ["gh", "pr", "view", "feature/opencode-capabilities", "--json", pr_operator.PR_VIEW_FIELDS],
        ["git", "rev-parse", "HEAD"],
    ]


def test_create_current_rejects_stale_existing_pr_with_different_head(monkeypatch, trusted_repo: Path) -> None:
    current_head = "31c62bc214b483adc95cbe234ce826b085f66225"
    pr_head = "ef51e29ec41341b874e5528b5634a22497192100"
    pr = {
        "url": "https://github.com/semanticdreams/space2/pull/119",
        "state": "MERGED",
        "mergedAt": "2026-09-15T12:34:56Z",
        "headRefOid": pr_head,
    }
    runner = GhRunner(
        {
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
            ("git", "rev-parse", "HEAD"): f"{current_head}\n",
            (
                "gh",
                "pr",
                "view",
                "feature/opencode-capabilities",
                "--json",
                "state,mergedAt,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,headRefName,headRefOid,url",
            ): json.dumps(pr),
        }
    )
    monkeypatch.setattr(pr_operator, "run_command", runner)

    result = pr_operator.create_current_pr(trusted_repo)

    assert result["status"] == "human_decision_required"
    assert result["evidence"] == {
        "branch": "feature/opencode-capabilities",
        "current_head": current_head,
        "pr_head": pr_head,
        "pr_state": "MERGED",
        "pr_url": "https://github.com/semanticdreams/space2/pull/119",
        "args": ["gh", "pr", "view", "feature/opencode-capabilities", "--json", pr_operator.PR_VIEW_FIELDS],
    }
    assert runner.calls == [
        ["git", "branch", "--show-current"],
        ["gh", "pr", "view", "feature/opencode-capabilities", "--json", pr_operator.PR_VIEW_FIELDS],
        ["git", "rev-parse", "HEAD"],
    ]


def test_create_current_rejects_matching_head_pr_that_is_not_open(monkeypatch, trusted_repo: Path) -> None:
    head = "31c62bc214b483adc95cbe234ce826b085f66225"
    pr = {
        "url": "https://github.com/semanticdreams/space2/pull/119",
        "state": "MERGED",
        "mergedAt": "2026-09-15T12:34:56Z",
        "headRefOid": head,
    }
    runner = GhRunner(
        {
            ("git", "branch", "--show-current"): "feature/opencode-capabilities\n",
            ("git", "rev-parse", "HEAD"): f"{head}\n",
            (
                "gh",
                "pr",
                "view",
                "feature/opencode-capabilities",
                "--json",
                pr_operator.PR_VIEW_FIELDS,
            ): json.dumps(pr),
        }
    )
    monkeypatch.setattr(pr_operator, "run_command", runner)

    result = pr_operator.create_current_pr(trusted_repo)

    assert result["status"] == "human_decision_required"
    assert result["evidence"]["branch"] == "feature/opencode-capabilities"
    assert result["evidence"]["current_head"] == head
    assert result["evidence"]["pr_head"] == head
    assert result["evidence"]["pr_state"] == "MERGED"
    assert result["evidence"]["pr_url"] == "https://github.com/semanticdreams/space2/pull/119"


def test_create_current_creates_when_view_reports_no_existing_pr(monkeypatch, trusted_repo: Path) -> None:
    calls: list[tuple[list[str], bool]] = []

    def fake_run(args, cwd: Path, check: bool = True):
        del cwd
        args = list(args)
        calls.append((args, check))
        if args == ["git", "branch", "--show-current"]:
            return command_result(args, "feature/opencode-capabilities\n")
        if args == ["gh", "pr", "view", "feature/opencode-capabilities", "--json", pr_operator.PR_VIEW_FIELDS]:
            return command_result(args, returncode=1, stderr="no pull requests found for branch feature/opencode-capabilities")
        if args == ["gh", "pr", "create", "--base", "main", "--head", "feature/opencode-capabilities", "--fill"]:
            return command_result(args, "https://github.com/semanticdreams/space2/pull/124\n")
        raise AssertionError(args)

    monkeypatch.setattr(pr_operator, "run_command", fake_run)

    result = pr_operator.create_current_pr(trusted_repo)

    assert result["status"] == "pass"
    assert result["evidence"]["url"] == "https://github.com/semanticdreams/space2/pull/124"
    assert calls == [
        (["git", "branch", "--show-current"], True),
        (["gh", "pr", "view", "feature/opencode-capabilities", "--json", pr_operator.PR_VIEW_FIELDS], False),
        (["gh", "pr", "create", "--base", "main", "--head", "feature/opencode-capabilities", "--fill"], False),
    ]


def test_create_current_unsafe_view_failure_preserves_command_details_and_does_not_create(monkeypatch, trusted_repo: Path) -> None:
    calls: list[list[str]] = []

    def fake_run(args, cwd: Path, check: bool = True):
        del cwd, check
        args = list(args)
        calls.append(args)
        if args == ["git", "branch", "--show-current"]:
            return command_result(args, "feature/opencode-capabilities\n")
        if args == ["gh", "pr", "view", "feature/opencode-capabilities", "--json", pr_operator.PR_VIEW_FIELDS]:
            return command_result(args, returncode=2, stderr="HTTP 401: credential expired\nauth detail from gh")
        raise AssertionError(args)

    monkeypatch.setattr(pr_operator, "run_command", fake_run)

    result = pr_operator.create_current_pr(trusted_repo)

    assert result["status"] == "human_decision_required"
    assert result["evidence"]["returncode"] == 2
    assert result["evidence"]["stderr"] == "HTTP 401: credential expired\nauth detail from gh"
    assert result["evidence"]["args"] == ["gh", "pr", "view", "feature/opencode-capabilities", "--json", pr_operator.PR_VIEW_FIELDS]
    assert calls == [
        ["git", "branch", "--show-current"],
        ["gh", "pr", "view", "feature/opencode-capabilities", "--json", pr_operator.PR_VIEW_FIELDS],
    ]


def test_create_current_generic_not_found_view_failure_does_not_create(monkeypatch, trusted_repo: Path) -> None:
    calls: list[list[str]] = []

    def fake_run(args, cwd: Path, check: bool = True):
        del cwd, check
        args = list(args)
        calls.append(args)
        if args == ["git", "branch", "--show-current"]:
            return command_result(args, "feature/opencode-capabilities\n")
        if args == ["gh", "pr", "view", "feature/opencode-capabilities", "--json", pr_operator.PR_VIEW_FIELDS]:
            return command_result(args, returncode=1, stderr="HTTP 404: Not Found")
        raise AssertionError(f"unexpected create attempt: {args}")

    monkeypatch.setattr(pr_operator, "run_command", fake_run)

    result = pr_operator.create_current_pr(trusted_repo)

    assert result["status"] == "human_decision_required"
    assert result["evidence"]["returncode"] == 1
    assert result["evidence"]["stderr"] == "HTTP 404: Not Found"
    assert result["evidence"]["args"] == ["gh", "pr", "view", "feature/opencode-capabilities", "--json", pr_operator.PR_VIEW_FIELDS]
    assert calls == [
        ["git", "branch", "--show-current"],
        ["gh", "pr", "view", "feature/opencode-capabilities", "--json", pr_operator.PR_VIEW_FIELDS],
    ]


def test_create_current_create_failure_preserves_command_details(monkeypatch, trusted_repo: Path) -> None:
    calls: list[list[str]] = []

    def fake_run(args, cwd: Path, check: bool = True):
        del cwd, check
        args = list(args)
        calls.append(args)
        if args == ["git", "branch", "--show-current"]:
            return command_result(args, "feature/opencode-capabilities\n")
        if args == ["gh", "pr", "view", "feature/opencode-capabilities", "--json", pr_operator.PR_VIEW_FIELDS]:
            return command_result(args, returncode=1, stderr="no pull requests found")
        if args == ["gh", "pr", "create", "--base", "main", "--head", "feature/opencode-capabilities", "--fill"]:
            return command_result(args, returncode=1, stderr="GraphQL: Validation failed")
        raise AssertionError(args)

    monkeypatch.setattr(pr_operator, "run_command", fake_run)

    result = pr_operator.create_current_pr(trusted_repo)

    assert result["status"] == "human_decision_required"
    assert result["evidence"]["returncode"] == 1
    assert result["evidence"]["stderr"] == "GraphQL: Validation failed"
    assert result["evidence"]["args"] == ["gh", "pr", "create", "--base", "main", "--head", "feature/opencode-capabilities", "--fill"]
    assert calls == [
        ["git", "branch", "--show-current"],
        ["gh", "pr", "view", "feature/opencode-capabilities", "--json", pr_operator.PR_VIEW_FIELDS],
        ["gh", "pr", "create", "--base", "main", "--head", "feature/opencode-capabilities", "--fill"],
    ]


def test_enable_auto_merge_checks_main_protection_before_auto_merge(monkeypatch, trusted_repo: Path) -> None:
    protection = json.dumps({"required_status_checks": {"contexts": ["test"]}})
    rulesets = json.dumps(
        [
            {
                "enforcement": "active",
                "conditions": {"ref_name": {"include": ["refs/heads/main"]}},
                "rules": [{"type": "merge_queue"}],
            }
        ]
    )
    runner = GhRunner(
        {
            ("gh", "api", "repos/semanticdreams/space2/branches/main/protection"): protection,
            ("gh", "api", "repos/semanticdreams/space2/rulesets"): rulesets,
            (
                "gh",
                "pr",
                "merge",
                "feature/opencode-capabilities",
                "--auto",
                "--merge",
            ): "",
        }
    )
    monkeypatch.setattr(pr_operator, "run_command", runner)

    result = pr_operator.enable_auto_merge(trusted_repo, "feature/opencode-capabilities")

    assert result["status"] == "pass"
    assert runner.calls == [
        ["gh", "api", "repos/semanticdreams/space2/branches/main/protection"],
        ["gh", "api", "repos/semanticdreams/space2/rulesets"],
        ["gh", "pr", "merge", "feature/opencode-capabilities", "--auto", "--merge"],
    ]


def test_check_main_protection_requires_test_status_and_merge_queue(monkeypatch, trusted_repo: Path) -> None:
    runner = GhRunner(
        {
            ("gh", "api", "repos/semanticdreams/space2/branches/main/protection"): json.dumps(
                {"required_status_checks": {"contexts": ["lint"]}}
            ),
            ("gh", "api", "repos/semanticdreams/space2/rulesets"): json.dumps([{"rules": []}]),
        }
    )
    monkeypatch.setattr(pr_operator, "run_command", runner)

    result = pr_operator.check_main_protection(trusted_repo)

    assert result["status"] == "human_decision_required"


@pytest.mark.parametrize(
    "ruleset",
    [
        {
            "name": "test",
            "enforcement": "disabled",
            "conditions": {"ref_name": {"include": ["refs/heads/main"]}},
            "rules": [{"type": "required_status_checks", "parameters": {"required_status_checks": [{"context": "test"}]}}, {"type": "merge_queue"}],
        },
        {
            "name": "test",
            "enforcement": "active",
            "conditions": {"ref_name": {"include": ["refs/heads/dev"]}},
            "rules": [{"type": "required_status_checks", "parameters": {"required_status_checks": [{"context": "test"}]}}, {"type": "merge_queue"}],
        },
        {
            "name": "test",
            "enforcement": "active",
            "conditions": {"ref_name": {"include": ["refs/heads/main"]}},
            "rules": [{"type": "merge_queue"}],
        },
    ],
)
def test_check_main_protection_ignores_disabled_non_main_and_unrelated_test_strings(
    monkeypatch,
    trusted_repo: Path,
    ruleset: dict[str, object],
) -> None:
    runner = GhRunner(
        {
            ("gh", "api", "repos/semanticdreams/space2/branches/main/protection"): json.dumps(
                {"required_status_checks": {"contexts": ["lint"]}}
            ),
            ("gh", "api", "repos/semanticdreams/space2/rulesets"): json.dumps([ruleset]),
        }
    )
    monkeypatch.setattr(pr_operator, "run_command", runner)

    result = pr_operator.check_main_protection(trusted_repo)

    assert result["status"] == "human_decision_required"


def test_check_main_protection_accepts_active_main_ruleset_with_required_test_and_merge_queue(
    monkeypatch,
    trusted_repo: Path,
) -> None:
    runner = GhRunner(
        {
            ("gh", "api", "repos/semanticdreams/space2/branches/main/protection"): json.dumps(
                {"required_status_checks": {"contexts": ["lint"]}}
            ),
            ("gh", "api", "repos/semanticdreams/space2/rulesets"): json.dumps(
                [
                    {
                        "enforcement": "active",
                        "conditions": {"ref_name": {"include": ["refs/heads/main"]}},
                        "rules": [
                            {
                                "type": "required_status_checks",
                                "parameters": {"required_status_checks": [{"context": "test"}]},
                            },
                            {"type": "merge_queue"},
                        ],
                    }
                ]
            ),
        }
    )
    monkeypatch.setattr(pr_operator, "run_command", runner)

    result = pr_operator.check_main_protection(trusted_repo)

    assert result["status"] == "pass"


def test_check_main_protection_accepts_effective_main_rules_when_ruleset_list_is_summary_only(
    monkeypatch,
    trusted_repo: Path,
) -> None:
    runner = GhRunner(
        {
            ("gh", "api", "repos/semanticdreams/space2/branches/main/protection"): json.dumps(
                {"required_status_checks": {"contexts": ["lint"]}}
            ),
            ("gh", "api", "repos/semanticdreams/space2/rulesets"): json.dumps(
                [
                    {
                        "id": 20232493,
                        "enforcement": "active",
                        "conditions": None,
                    }
                ]
            ),
            ("gh", "api", "repos/semanticdreams/space2/rules/branches/main"): json.dumps(
                [
                    {"type": "pull_request"},
                    {"type": "merge_queue"},
                    {
                        "type": "required_status_checks",
                        "parameters": {"required_status_checks": [{"context": "test"}]},
                    },
                ]
            ),
        }
    )
    monkeypatch.setattr(pr_operator, "run_command", runner)

    result = pr_operator.check_main_protection(trusted_repo)

    assert result["status"] == "pass"
    assert result["evidence"]["effective_branch_rules_available"] is True
    assert result["evidence"]["effective_branch_rules_required_test_check_proven"] is True
    assert result["evidence"]["effective_branch_rules_merge_queue_proven"] is True


def test_check_main_protection_accepts_detailed_ruleset_when_effective_rules_are_unavailable(
    monkeypatch,
    trusted_repo: Path,
) -> None:
    runner = GhRunner(
        {
            ("gh", "api", "repos/semanticdreams/space2/branches/main/protection"): json.dumps(
                {"required_status_checks": {"contexts": ["lint"]}}
            ),
            ("gh", "api", "repos/semanticdreams/space2/rulesets"): json.dumps(
                [
                    {
                        "id": 20232493,
                        "enforcement": "active",
                        "conditions": None,
                    }
                ]
            ),
            ("gh", "api", "repos/semanticdreams/space2/rules/branches/main"): command_result(
                ["gh", "api", "repos/semanticdreams/space2/rules/branches/main"],
                returncode=404,
            ),
            ("gh", "api", "repos/semanticdreams/space2/rulesets/20232493"): json.dumps(
                {
                    "id": 20232493,
                    "enforcement": "active",
                    "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
                    "rules": [
                        {
                            "type": "required_status_checks",
                            "parameters": {"required_status_checks": [{"context": "test"}]},
                        },
                        {"type": "merge_queue"},
                    ],
                }
            ),
        }
    )
    monkeypatch.setattr(pr_operator, "run_command", runner)

    result = pr_operator.check_main_protection(trusted_repo)

    assert result["status"] == "pass"
    assert result["evidence"]["detailed_rulesets_available"] is True
    assert result["evidence"]["detailed_rulesets_required_test_check_proven"] is True
    assert result["evidence"]["detailed_rulesets_merge_queue_proven"] is True


def test_poll_merge_queue_treats_pending_states_as_nonterminal_until_merged(monkeypatch, trusted_repo: Path) -> None:
    states = iter(
        [
            {"mergedAt": None, "state": "OPEN", "mergeStateStatus": "queued", "statusCheckRollup": []},
            {"mergedAt": None, "state": "OPEN", "mergeStateStatus": "waiting", "statusCheckRollup": []},
            {"mergedAt": None, "state": "OPEN", "mergeStateStatus": "pending", "statusCheckRollup": []},
            {"mergedAt": None, "state": "OPEN", "mergeStateStatus": "in_progress", "statusCheckRollup": []},
            {"mergedAt": None, "state": "OPEN", "mergeStateStatus": "expected", "statusCheckRollup": []},
            {"mergedAt": None, "state": "OPEN", "mergeStateStatus": None, "statusCheckRollup": [{"conclusion": None}]},
            {"mergedAt": "2026-08-06T00:00:00Z", "state": "MERGED", "mergeStateStatus": "clean", "statusCheckRollup": []},
        ]
    )

    def fake_run(args, cwd: Path, check: bool = True):
        del cwd, check
        assert list(args) == [
            "gh",
            "pr",
            "view",
            "feature/opencode-capabilities",
            "--json",
            "state,mergedAt,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,headRefName,headRefOid,url",
        ]
        return command_result(list(args), json.dumps(next(states)))

    monkeypatch.setattr(pr_operator, "run_command", fake_run)
    monkeypatch.setattr(pr_operator.time, "sleep", lambda seconds: None)

    result = pr_operator.poll_merge_queue(trusted_repo, "feature/opencode-capabilities", 60, 1)

    assert result["status"] == "pass"
    assert result["evidence"]["merged_at"] == "2026-08-06T00:00:00Z"


def test_poll_merge_queue_waits_for_open_clean_mergeable_pr_with_successful_checks(
    monkeypatch,
    trusted_repo: Path,
) -> None:
    states = iter(
        [
            {
                "mergedAt": None,
                "state": "OPEN",
                "mergeStateStatus": "CLEAN",
                "mergeable": "MERGEABLE",
                "statusCheckRollup": [
                    {
                        "__typename": "CheckRun",
                        "name": "test",
                        "workflowName": "test",
                        "status": "COMPLETED",
                        "conclusion": "SUCCESS",
                    }
                ],
            },
            {
                "mergedAt": "2026-08-08T00:00:00Z",
                "state": "MERGED",
                "mergeStateStatus": "CLEAN",
                "mergeable": "MERGEABLE",
                "statusCheckRollup": [],
            },
        ]
    )
    calls = []

    def fake_run(args, cwd: Path, check: bool = True):
        del cwd, check
        calls.append(list(args))
        return command_result(list(args), json.dumps(next(states)))

    monkeypatch.setattr(pr_operator, "run_command", fake_run)
    monkeypatch.setattr(pr_operator.time, "sleep", lambda seconds: None)

    result = pr_operator.poll_merge_queue(trusted_repo, "feature/opencode-capabilities", 60, 1)

    assert result["status"] == "pass"
    assert result["evidence"]["merged_at"] == "2026-08-08T00:00:00Z"
    assert len(calls) == 2


def test_poll_merge_queue_waits_for_open_unknown_mergeability_with_successful_checks(
    monkeypatch,
    trusted_repo: Path,
) -> None:
    states = iter(
        [
            {
                "mergedAt": None,
                "state": "OPEN",
                "mergeStateStatus": "UNKNOWN",
                "mergeable": "UNKNOWN",
                "statusCheckRollup": [
                    {
                        "__typename": "CheckRun",
                        "name": "test",
                        "workflowName": "test",
                        "status": "COMPLETED",
                        "conclusion": "SUCCESS",
                    }
                ],
            },
            {
                "mergedAt": "2026-08-08T01:00:00Z",
                "state": "MERGED",
                "mergeStateStatus": "CLEAN",
                "mergeable": "MERGEABLE",
                "statusCheckRollup": [],
            },
        ]
    )
    calls = []

    def fake_run(args, cwd: Path, check: bool = True):
        del cwd, check
        calls.append(list(args))
        return command_result(list(args), json.dumps(next(states)))

    monkeypatch.setattr(pr_operator, "run_command", fake_run)
    monkeypatch.setattr(pr_operator.time, "sleep", lambda seconds: None)

    result = pr_operator.poll_merge_queue(trusted_repo, "feature/opencode-capabilities", 60, 1)

    assert result["status"] == "pass"
    assert result["evidence"]["merged_at"] == "2026-08-08T01:00:00Z"
    assert len(calls) == 2


def test_poll_merge_queue_rejects_conflict_even_with_pending_rollup(
    monkeypatch,
    trusted_repo: Path,
) -> None:
    calls = []

    def fake_run(args, cwd: Path, check: bool = True):
        del cwd, check
        calls.append(list(args))
        return command_result(
            list(args),
            json.dumps(
                {
                    "mergedAt": None,
                    "state": "OPEN",
                    "mergeStateStatus": "DIRTY",
                    "mergeable": "CONFLICTING",
                    "statusCheckRollup": [
                        {
                            "__typename": "CheckRun",
                            "name": "test",
                            "workflowName": "test",
                            "status": "IN_PROGRESS",
                            "conclusion": None,
                        }
                    ],
                }
            ),
        )

    monkeypatch.setattr(pr_operator, "run_command", fake_run)
    monkeypatch.setattr(pr_operator.time, "sleep", lambda seconds: pytest.fail("conflict should not wait"))

    result = pr_operator.poll_merge_queue(trusted_repo, "feature/opencode-capabilities", 0, 1)

    assert result["status"] == "human_decision_required"
    assert result["message"] == "Pull request has merge conflicts or is not mergeable"
    assert len(calls) == 1


def test_poll_merge_queue_treats_blocked_in_progress_check_with_blank_conclusion_as_nonterminal(
    monkeypatch,
    trusted_repo: Path,
) -> None:
    states = iter(
        [
            {
                "mergedAt": None,
                "state": "OPEN",
                "mergeStateStatus": "BLOCKED",
                "statusCheckRollup": [
                    {
                        "__typename": "CheckRun",
                        "name": "test",
                        "workflowName": "test",
                        "status": "IN_PROGRESS",
                        "conclusion": "",
                        "completedAt": "0001-01-01T00:00:00Z",
                    }
                ],
            },
            {"mergedAt": "2026-08-07T00:00:00Z", "state": "MERGED", "mergeStateStatus": "clean", "statusCheckRollup": []},
        ]
    )
    calls = []

    def fake_run(args, cwd: Path, check: bool = True):
        del cwd, check
        calls.append(list(args))
        return command_result(list(args), json.dumps(next(states)))

    monkeypatch.setattr(pr_operator, "run_command", fake_run)
    monkeypatch.setattr(pr_operator.time, "sleep", lambda seconds: None)

    result = pr_operator.poll_merge_queue(trusted_repo, "feature/opencode-capabilities", 60, 1)

    assert result["status"] == "pass"
    assert result["evidence"]["merged_at"] == "2026-08-07T00:00:00Z"
    assert len(calls) == 2


def test_poll_merge_queue_rejects_blocked_state_with_non_pending_rollup_missing_conclusion(
    monkeypatch,
    trusted_repo: Path,
) -> None:
    runner = GhRunner(
        {
            (
                "gh",
                "pr",
                "view",
                "feature/opencode-capabilities",
                "--json",
                "state,mergedAt,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,headRefName,headRefOid,url",
            ): json.dumps(
                {
                    "mergedAt": None,
                    "state": "OPEN",
                    "mergeStateStatus": "BLOCKED",
                    "statusCheckRollup": [{"__typename": "StatusContext", "state": "SUCCESS"}],
                }
            )
        }
    )
    monkeypatch.setattr(pr_operator, "run_command", runner)

    result = pr_operator.poll_merge_queue(trusted_repo, "feature/opencode-capabilities", 0, 1)

    assert result["status"] == "human_decision_required"
    assert result["message"] == "Pull request merge queue state is ambiguous or unsupported"


@pytest.mark.parametrize("conclusion", ["TIMED_OUT", "ACTION_REQUIRED"])
def test_poll_merge_queue_rejects_completed_terminal_failed_check_conclusions(
    monkeypatch,
    trusted_repo: Path,
    conclusion: str,
) -> None:
    runner = GhRunner(
        {
            (
                "gh",
                "pr",
                "view",
                "feature/opencode-capabilities",
                "--json",
                "state,mergedAt,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,headRefName,headRefOid,url",
            ): json.dumps(
                {
                    "mergedAt": None,
                    "state": "OPEN",
                    "mergeStateStatus": "pending",
                    "statusCheckRollup": [
                        {
                            "__typename": "CheckRun",
                            "name": "test",
                            "workflowName": "test",
                            "status": "COMPLETED",
                            "conclusion": conclusion,
                        }
                    ],
                }
            )
        }
    )
    monkeypatch.setattr(pr_operator, "run_command", runner)

    result = pr_operator.poll_merge_queue(trusted_repo, "feature/opencode-capabilities", 0, 1)

    assert result["status"] == "human_decision_required"
    assert result["message"] == "Required merge queue check failed"


def test_poll_merge_queue_requires_merged_at_for_success(monkeypatch, trusted_repo: Path) -> None:
    runner = GhRunner(
        {
            (
                "gh",
                "pr",
                "view",
                "feature/opencode-capabilities",
                "--json",
                "state,mergedAt,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,headRefName,headRefOid,url",
            ): json.dumps({"mergedAt": None, "state": "CLOSED", "mergeStateStatus": "clean", "statusCheckRollup": []})
        }
    )
    monkeypatch.setattr(pr_operator, "run_command", runner)

    result = pr_operator.poll_merge_queue(trusted_repo, "feature/opencode-capabilities", 0, 1)

    assert result["status"] == "human_decision_required"


def test_cli_emits_json_and_returns_human_decision_for_invalid_branch(monkeypatch, trusted_repo: Path, capsys) -> None:
    exit_code = pr_operator.main(["create", "--repo-root", str(trusted_repo), "--head", "bad branch"])

    payload = json.loads(capsys.readouterr().out)
    assert exit_code == 2
    assert payload["status"] == "human_decision_required"
    assert set(payload) == {"status", "action", "message", "evidence"}


def test_cli_current_branch_operations_take_no_untrusted_branch_or_timeout_arguments(monkeypatch, trusted_repo: Path, capsys) -> None:
    calls = []

    def fake_create_current(repo_root: Path):
        calls.append(repo_root)
        return {"status": "pass", "action": "create_pr", "message": "ok", "evidence": {}}

    monkeypatch.setattr(pr_operator, "create_current_pr", fake_create_current)

    exit_code = pr_operator.main(["create-current", "--repo-root", str(trusted_repo)])

    payload = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert payload["status"] == "pass"
    assert calls == [trusted_repo]
