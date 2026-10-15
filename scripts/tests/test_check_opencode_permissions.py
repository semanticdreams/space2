from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[2]
CHECKER = REPO_ROOT / "scripts" / "check_opencode_permissions.py"


def load_checker():
    assert CHECKER.exists(), "policy checker script should exist"
    spec = importlib.util.spec_from_file_location("check_opencode_permissions", CHECKER)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write_file(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def agent(name: str, permission_text: str) -> str:
    return f"""---
description: Test {name} agent
mode: subagent
model: openai/gpt-6.1-sol
permission:
{permission_text}
---

Test agent body.
"""


def skill(name: str) -> str:
    return f"""---
name: {name}
description: Use when testing {name}
---

# {name}
"""


def write_capability_files(root: Path) -> None:
    git_integrator_permissions = (
        '  edit: deny\n'
        '  task: deny\n'
        '  external_directory: deny\n'
        '  webfetch: deny\n'
        '  websearch: deny\n'
        '  question: deny\n'
        '  bash:\n'
        '    "python3 scripts/opencode_git_integrate.py status --repo-root .": allow\n'
        '    "python3 scripts/opencode_git_integrate.py fetch-origin --repo-root .": allow\n'
        '    "python3 scripts/opencode_git_integrate.py merge-origin-main --repo-root .": allow\n'
        '    "python3 scripts/opencode_git_integrate.py push-current --repo-root .": allow\n'
        '    "python3 scripts/opencode_git_integrate.py create-followup-branch --repo-root .": allow\n'
        '    "python3 scripts/opencode_git_integrate.py create-local-main-wrapup-branch --repo-root .": allow\n'
    )
    write_file(
        root / ".opencode" / "agents" / "git-integrator.md",
        agent("git-integrator", git_integrator_permissions),
    )
    write_file(
        root / ".opencode" / "agents" / "github-operator.md",
        agent(
            "github-operator",
            '  edit: deny\n  task: deny\n  external_directory: deny\n  webfetch: deny\n  websearch: deny\n  question: deny\n  bash:\n    "python3 scripts/opencode_pr_operator.py auth-status --repo-root .": allow\n    "python3 scripts/opencode_pr_operator.py check-main-protection --repo-root .": allow\n    "python3 scripts/opencode_pr_operator.py create-current --repo-root .": allow\n    "python3 scripts/opencode_pr_operator.py enable-auto-merge-current --repo-root .": allow\n    "python3 scripts/opencode_pr_operator.py view-current --repo-root .": allow\n    "python3 scripts/opencode_pr_operator.py poll-merge-queue-current --repo-root .": allow\n    "python3 scripts/opencode_pr_operator.py failed-actions-log-bundle-current --repo-root .": allow\n',
        ),
    )
    write_file(
        root / ".opencode" / "agents" / "config-auditor.md",
        agent(
            "config-auditor",
            '  edit: deny\n  task: deny\n  webfetch: deny\n  websearch: deny\n  question: deny\n  external_directory:\n    "~/.config/opencode/**": allow\n    "~/.config/opencode/**/*auth.json*": deny\n    "~/.config/opencode/**/*auth.jsonc*": deny\n    "~/.config/opencode/**/*secret*": deny\n    "~/.config/opencode/**/*token*": deny\n  bash:\n    "python3 scripts/verify_opencode_home_config.py --repo-root . --require-clean": allow\n',
        ),
    )
    write_file(
        root / ".opencode" / "agents" / "pr-recovery-operator.md",
        agent(
            "pr-recovery-operator",
            '  edit: deny\n  task: deny\n  external_directory: deny\n  webfetch: deny\n  websearch: deny\n  question: deny\n  bash:\n    "python3 scripts/opencode_pr_recovery.py create-current-with-followup-recovery --repo-root .": allow\n',
        ),
    )
    write_file(
        root / ".opencode" / "agents" / "windows-ci-reproducer.md",
        agent(
            "windows-ci-reproducer",
            '  edit: deny\n  task: deny\n  external_directory: deny\n  webfetch: deny\n  websearch: deny\n  question: deny\n  bash:\n    "python3 scripts/opencode_windows_ci_repro.py preflight --repo-root .": allow\n    "python3 scripts/opencode_windows_ci_repro.py setup-host --repo-root .": allow\n    "python3 scripts/opencode_windows_ci_repro.py bootstrap-vcpkg --repo-root .": allow\n    "python3 scripts/opencode_windows_ci_repro.py reproduce --repo-root .": allow\n',
        ),
    )
    for script in [
        "opencode_capabilities.py",
        "opencode_git_integrate.py",
        "opencode_pr_operator.py",
        "opencode_pr_recovery.py",
        "opencode_windows_ci_repro.py",
        "verify_opencode_home_config.py",
    ]:
        write_file(root / "scripts" / script, "#!/usr/bin/env python3\n")


def make_repo(tmp_path: Path, *, agent_name: str = "example-agent", permission_text: str = "  bash: deny\n") -> Path:
    root = tmp_path / "repo"
    write_file(root / ".opencode" / "opencode.json", json.dumps({"default_agent": "supervisor"}))
    write_capability_files(root)
    write_file(root / ".opencode" / "agents" / f"{agent_name}.md", agent(agent_name, permission_text))
    write_file(root / ".opencode" / "skills" / "example" / "SKILL.md", skill("example"))
    return root


def violation_codes(repo: Path) -> set[str]:
    checker = load_checker()
    return {violation.code for violation in checker.check_repo(repo)}


def permission_entries(repo: Path, agent_name: str, parent: str) -> dict[str, str]:
    checker = load_checker()
    path = repo / ".opencode" / "agents" / f"{agent_name}.md"
    _, raw = checker._frontmatter(path.read_text(encoding="utf-8"))
    assert raw is not None
    return dict(checker._mapping_entries(raw, parent))


def test_current_repo_policy_passes_after_task_3_changes():
    checker = load_checker()
    assert checker.check_repo(REPO_ROOT) == []


def test_git_integrator_allows_exact_guarded_git_wrapper_commands():
    bash_entries = permission_entries(REPO_ROOT, "git-integrator", "bash")

    allowed_entries = {pattern for pattern, action in bash_entries.items() if action == "allow"}
    assert allowed_entries == {
        "python3 scripts/opencode_git_integrate.py status --repo-root .",
        "python3 scripts/opencode_git_integrate.py fetch-origin --repo-root .",
        "python3 scripts/opencode_git_integrate.py merge-origin-main --repo-root .",
        "python3 scripts/opencode_git_integrate.py push-current --repo-root .",
        "python3 scripts/opencode_git_integrate.py create-followup-branch --repo-root .",
        "python3 scripts/opencode_git_integrate.py create-local-main-wrapup-branch --repo-root .",
    }


def test_pr_recovery_operator_allows_only_exact_guarded_recovery_command():
    bash_entries = permission_entries(REPO_ROOT, "pr-recovery-operator", "bash")

    allowed_entries = {pattern for pattern, action in bash_entries.items() if action == "allow"}
    assert allowed_entries == {
        "python3 scripts/opencode_pr_recovery.py create-current-with-followup-recovery --repo-root ."
    }


def test_github_operator_allows_exact_guarded_wrapper_commands():
    bash_entries = permission_entries(REPO_ROOT, "github-operator", "bash")

    allowed_entries = {pattern for pattern, action in bash_entries.items() if action == "allow"}
    assert allowed_entries == {
        "python3 scripts/opencode_pr_operator.py auth-status --repo-root .",
        "python3 scripts/opencode_pr_operator.py check-main-protection --repo-root .",
        "python3 scripts/opencode_pr_operator.py create-current --repo-root .",
        "python3 scripts/opencode_pr_operator.py enable-auto-merge-current --repo-root .",
        "python3 scripts/opencode_pr_operator.py view-current --repo-root .",
        "python3 scripts/opencode_pr_operator.py poll-merge-queue-current --repo-root .",
        "python3 scripts/opencode_pr_operator.py failed-actions-log-bundle-current --repo-root .",
    }


def test_windows_ci_reproducer_allows_exact_guarded_wrapper_commands():
    bash_entries = permission_entries(REPO_ROOT, "windows-ci-reproducer", "bash")

    allowed_entries = {pattern for pattern, action in bash_entries.items() if action == "allow"}
    assert allowed_entries == {
        "python3 scripts/opencode_windows_ci_repro.py preflight --repo-root .",
        "python3 scripts/opencode_windows_ci_repro.py setup-host --repo-root .",
        "python3 scripts/opencode_windows_ci_repro.py bootstrap-vcpkg --repo-root .",
        "python3 scripts/opencode_windows_ci_repro.py reproduce --repo-root .",
    }


def test_windows_ci_reproducer_agent_is_required(tmp_path: Path):
    repo = make_repo(tmp_path)
    (repo / ".opencode" / "agents" / "windows-ci-reproducer.md").unlink(missing_ok=True)

    checker = load_checker()
    issues = checker.check_repo(repo)

    assert any(
        violation.code == "capability-dependency"
        and ".opencode/agents/windows-ci-reproducer.md" in violation.message
        for violation in issues
    )


def test_windows_ci_reproducer_allows_only_wrapper_commands(tmp_path: Path):
    repo = make_repo(tmp_path)
    write_file(repo / "scripts" / "opencode_windows_ci_repro.py", "#!/usr/bin/env python3\n")
    windows_permissions = (
        '  edit: deny\n'
        '  task: deny\n'
        '  external_directory: deny\n'
        '  webfetch: deny\n'
        '  websearch: deny\n'
        '  question: deny\n'
        '  bash:\n'
        '    "python3 scripts/opencode_windows_ci_repro.py preflight --repo-root .": allow\n'
        '    "python3 scripts/opencode_windows_ci_repro.py setup-host --repo-root .": allow\n'
        '    "python3 scripts/opencode_windows_ci_repro.py bootstrap-vcpkg --repo-root .": allow\n'
        '    "python3 scripts/opencode_windows_ci_repro.py reproduce --repo-root .": allow\n'
        '    "gh *": allow\n'
    )
    write_file(
        repo / ".opencode" / "agents" / "windows-ci-reproducer.md",
        agent("windows-ci-reproducer", windows_permissions),
    )

    assert "capability-boundary" in violation_codes(repo)


def test_windows_ci_reproducer_requires_wrapper_script(tmp_path: Path):
    repo = make_repo(tmp_path)
    (repo / "scripts" / "opencode_windows_ci_repro.py").unlink(missing_ok=True)

    checker = load_checker()
    issues = checker.check_repo(repo)

    assert any(
        violation.code == "capability-dependency"
        and "scripts/opencode_windows_ci_repro.py" in violation.message
        for violation in issues
    )


@pytest.mark.parametrize(
    "extra_entry",
    [
        '    "git switch -c *": allow\n',
        '    "git push *": allow\n',
        '    "gh pr create *": allow\n',
        '    "python3 scripts/opencode_pr_recovery.py *": allow\n',
        '    "python3 scripts/opencode_pr_recovery.py create-current-with-followup-recovery --repo-root *": allow\n',
    ],
)
def test_pr_recovery_operator_rejects_extra_bash_allow(tmp_path: Path, extra_entry: str):
    repo = make_repo(tmp_path)
    write_file(repo / "scripts" / "opencode_pr_recovery.py", "#!/usr/bin/env python3\n")
    recovery_permissions = (
        '  edit: deny\n'
        '  task: deny\n'
        '  external_directory: deny\n'
        '  webfetch: deny\n'
        '  websearch: deny\n'
        '  question: deny\n'
        '  bash:\n'
        '    "python3 scripts/opencode_pr_recovery.py create-current-with-followup-recovery --repo-root .": allow\n'
        + extra_entry
    )
    write_file(
        repo / ".opencode" / "agents" / "pr-recovery-operator.md",
        agent("pr-recovery-operator", recovery_permissions),
    )

    assert "capability-boundary" in violation_codes(repo)


def test_stale_merged_pr_recovery_routes_through_recovery_operator():
    required_terms = [
        "pr-recovery-operator",
        "create-current-with-followup-recovery",
        "stale merged PR",
    ]
    documented_paths = [
        REPO_ROOT / ".opencode" / "skills" / "finishing-a-development-branch" / "SKILL.md",
        REPO_ROOT / ".opencode" / "agents" / "supervisor.md",
        REPO_ROOT / "docs" / "dev" / "features" / "opencode-agent-workflow.md",
    ]

    for path in documented_paths:
        text = path.read_text(encoding="utf-8")
        missing_terms = [term for term in required_terms if term not in text]
        assert missing_terms == [], f"{path.relative_to(REPO_ROOT)} missing {missing_terms}"


def test_legacy_strict_local_main_recovery_remains_documented():
    required = {
        REPO_ROOT / ".opencode" / "agents" / "supervisor.md": [
            "create-local-main-wrapup-branch",
            "fast-dev/local-main-",
            "local `main`",
            "git-integrator",
        ],
        REPO_ROOT / ".opencode" / "skills" / "finishing-a-development-branch" / "SKILL.md": [
            "create-local-main-wrapup-branch",
            "fast-dev/local-main-",
            "local `main`",
            "Do not push",
        ],
        REPO_ROOT / "docs" / "dev" / "features" / "opencode-agent-workflow.md": [
            "Legacy strict-flow local-main recovery",
            "create-local-main-wrapup-branch",
            "fast-dev/local-main-<short-head-sha>",
        ],
    }

    for path, terms in required.items():
        text = path.read_text(encoding="utf-8")
        missing = [term for term in terms if term not in text]
        assert missing == [], f"{path.relative_to(REPO_ROOT)} missing {missing}"


def test_strict_workflow_does_not_recommend_raw_github_polling_commands():
    forbidden_commands = [
        "gh pr view",
        "gh run list",
        "gh run watch",
    ]
    documented_paths = [
        REPO_ROOT / ".opencode" / "skills" / "finishing-a-development-branch" / "SKILL.md",
        REPO_ROOT / ".opencode" / "agents" / "supervisor.md",
    ]

    for path in documented_paths:
        text = path.read_text(encoding="utf-8")
        if text.startswith("---\n"):
            text = text.split("---\n", 2)[2]
        present_commands = [command for command in forbidden_commands if command in text]
        assert present_commands == [], f"{path.relative_to(REPO_ROOT)} recommends {present_commands}"


def scalar_agent(name: str, mode: str, action: str) -> str:
    return agent(name, "  bash: deny\n").replace(
        "mode: subagent", f"mode: {mode}"
    ).replace("permission:\n  bash: deny", f"permission: {action}")


@pytest.mark.parametrize("name", ["fast-dev", "live-dev"])
def test_direct_primary_accepts_scalar_allow(tmp_path: Path, name: str):
    repo = make_repo(tmp_path)
    write_file(repo / f".opencode/agents/{name}.md", scalar_agent(name, "primary", "allow"))
    assert load_checker().check_repo(repo) == []


@pytest.mark.parametrize(
    "name,mode,action",
    [
        ("example-agent", "primary", "allow"),
        ("fast-dev-copy", "primary", "allow"),
        ("fast-dev", "subagent", "allow"),
        ("fast-dev", "all", "allow"),
        ("fast-dev", "primary", "ask"),
        ("fast-dev", "primary", "deny"),
        ("live-dev-copy", "primary", "allow"),
        ("live-dev", "subagent", "allow"),
        ("live-dev", "all", "allow"),
        ("live-dev", "primary", "ask"),
        ("live-dev", "primary", "deny"),
        ("example-agent", "subagent", "ask"),
    ],
)
def test_direct_scalar_grant_is_exact_name_mode_and_action_only(tmp_path: Path, name: str, mode: str, action: str):
    repo = make_repo(tmp_path)
    write_file(repo / f".opencode/agents/{name}.md", scalar_agent(name, mode, action))
    assert "permission-profile" in violation_codes(repo)


@pytest.mark.parametrize("name", ["fast-dev", "live-dev"])
def test_direct_primary_requires_broad_scalar_profile(tmp_path: Path, name: str):
    repo = make_repo(tmp_path, agent_name=name)
    assert "permission-profile" in violation_codes(repo)


FAST_DEV_REVIEWER_PERMISSIONS = (
    "  read: allow\n  glob: allow\n  grep: allow\n  list: allow\n  lsp: allow\n"
    "  edit: deny\n  task: deny\n  external_directory: deny\n"
    "  webfetch: deny\n  websearch: deny\n  question: deny\n  bash: allow\n"
)


def test_fast_dev_reviewer_observational_profile_passes(tmp_path: Path):
    repo = make_repo(tmp_path, agent_name="fast-dev-reviewer", permission_text=FAST_DEV_REVIEWER_PERMISSIONS)
    assert load_checker().check_repo(repo) == []


@pytest.mark.parametrize("key", ["edit", "task", "external_directory", "webfetch", "websearch", "question"])
def test_fast_dev_reviewer_rejects_operational_grants(tmp_path: Path, key: str):
    permissions = FAST_DEV_REVIEWER_PERMISSIONS.replace(f"  {key}: deny", f"  {key}: allow")
    repo = make_repo(tmp_path, agent_name="fast-dev-reviewer", permission_text=permissions)
    assert "role-boundary" in violation_codes(repo)


@pytest.mark.parametrize("key", ["read", "glob", "grep", "list", "lsp", "bash"])
def test_fast_dev_reviewer_requires_inspection_access(tmp_path: Path, key: str):
    permissions = FAST_DEV_REVIEWER_PERMISSIONS.replace(f"  {key}: allow", f"  {key}: deny")
    repo = make_repo(tmp_path, agent_name="fast-dev-reviewer", permission_text=permissions)
    assert "role-boundary" in violation_codes(repo)


def test_fast_dev_reviewer_requires_subagent_mode(tmp_path: Path):
    repo = make_repo(tmp_path)
    text = agent("fast-dev-reviewer", FAST_DEV_REVIEWER_PERMISSIONS).replace("mode: subagent", "mode: primary")
    write_file(repo / ".opencode/agents/fast-dev-reviewer.md", text)
    assert "role-boundary" in violation_codes(repo)


def test_fast_dev_primary_contract_is_direct_branch_scoped_and_local_only():
    text = (REPO_ROOT / ".opencode/agents/fast-dev.md").read_text(encoding="utf-8")
    keys, _ = load_checker()._frontmatter(text)
    assert keys["permission"] == "allow"
    assert keys["mode"] == "primary"
    for term in ["fast-dev/<topic>", "origin/main", "before edits", "unmerged", "dirty", "local only", "explicit", "fast-dev-wrap-up", "space-fennel", "space-graph-doctrine"]:
        assert term in text
    for term in ["supervisor", "micro-design", "dispatch `implementer`", "capability agents", "vertical slice handoff"]:
        assert term not in text.lower()


def test_fast_dev_reviewer_contract_covers_all_commits_without_operations():
    text = (REPO_ROOT / ".opencode/agents/fast-dev-reviewer.md").read_text(encoding="utf-8")
    for term in ["base/head SHAs", "every accumulated commit", "final diff", "file/line", "coverage gaps", "Do not run tests", "GitHub", "process artifacts"]:
        assert term in text
    assert "supervisor" not in text.lower()


def test_fast_dev_wrap_up_contract_requires_review_direct_fixes_and_fetched_main_proof():
    text = (REPO_ROOT / ".opencode/skills/fast-dev-wrap-up/SKILL.md").read_text(encoding="utf-8")
    for term in [
        "explicit", "commit request", "git fetch origin", "git merge origin/main",
        "git log origin/main..HEAD", "git diff origin/main...HEAD", "base/head SHAs",
        "fast-dev-reviewer", "one independent review", "Fix findings", "self-review",
        "no mandatory independent re-review", "gh pr create", "gh pr merge", "--auto",
        "gh pr view", "gh run list", "gh run watch", "100", "mergedAt", "mergeCommit",
        "git merge-base --is-ancestor <merge-sha> origin/main", "merge queue", "required `test`",
        "space-testing-runtime", "unresolved material", "required validation failures",
    ]:
        assert term in text
    assert "supervisor" not in text.lower()


def test_fast_dev_agents_exception_retains_technical_guidance_and_overrides_imported_process():
    text = (REPO_ROOT / "AGENTS.md").read_text(encoding="utf-8")
    exception = text.split("## Fast-dev workflow exception", 1)[1].split("## Branch Convention", 1)[0]
    for term in ["selected `fast-dev` primary", "imported by domain skills", "planning", "review", "commit", "explicit", "technical", "evidence", "unresolved material", "required validation failures"]:
        assert term in exception


def live_dev_prompt() -> str:
    path = REPO_ROOT / ".opencode/agents/live-dev.md"
    assert path.exists(), "the user-selected live-dev primary must exist"
    return path.read_text(encoding="utf-8")


def test_live_dev_primary_is_exact_direct_local_only_profile():
    text = live_dev_prompt()
    keys, _ = load_checker()._frontmatter(text)
    assert {key: keys[key] for key in ("mode", "model", "variant", "steps", "permission")} == {
        "mode": "primary", "model": "openai/gpt-6.1-sol", "variant": "medium",
        "steps": "180", "permission": "allow",
    }
    for term in [
        "live-dev/<topic>", "before edits", "freshly fetched `origin/main`", "unmerged",
        "dirty", "local only", "task completion", "commit request", "PR creation",
        "explicit user wrap-up/integration", "fast-dev-wrap-up", "space-fennel",
        "space-fennel-ui", "space-graph-doctrine", "space-testing-runtime",
        "quit and restart OpenCode",
    ]:
        assert term in text


def test_live_dev_loop_establishes_manual_mode_before_edits_and_validates_before_refresh():
    text = live_dev_prompt()
    for term in [
        "discover --repo-root .", "start --repo-root .", "normal user data/settings",
        "more than one", "ask the user to select", "select --repo-root . --instance <instance-id>",
        "manual --repo-root .", "confirm `mode: manual` before editing",
        "no filesystem watching", "no hooks", "Validate before refresh",
        "reload --repo-root .", "broad app-root", "restart --repo-root . --rebuild",
        "preserved", "restart --repo-root .", "macros.fnl", "Never request confirmation",
        "transient state loss", "status --repo-root . --request-id <request-id>",
        "terminal", "health", "acceptance alone is not success", "nonzero",
        "both the failed reload and recovery", "Diagnose", "fix directly",
    ]:
        assert term in text
    assert text.index("manual --repo-root .") < text.index("Validate before refresh") < text.index("reload --repo-root .")


def test_live_dev_scoped_exception_preserves_default_and_other_agent_contracts():
    text = (REPO_ROOT / "AGENTS.md").read_text(encoding="utf-8")
    exception = text.split("## Fast-dev workflow exception", 1)[1].split("## Branch Convention", 1)[0]
    for term in [
        "selected `fast-dev` primary", "selected `live-dev` primary", "`live-dev/<topic>`",
        "exact identities", "default `supervisor`", "local only", "explicit user wrap-up",
        "imported by domain skills", "technical", "no filesystem watching",
        "all other agents", "already-running agent",
    ]:
        assert term in exception
    config = json.loads((REPO_ROOT / ".opencode/opencode.json").read_text(encoding="utf-8"))
    assert config["default_agent"] == "supervisor"


def test_shared_wrap_up_matches_selected_caller_to_its_own_branch_only():
    text = (REPO_ROOT / ".opencode/skills/fast-dev-wrap-up/SKILL.md").read_text(encoding="utf-8")
    keys, _ = load_checker()._frontmatter(text)
    assert keys["description"] == (
        "Use ONLY when the selected fast-dev or live-dev primary receives explicit user wrap-up/integration authorization."
    )
    for term in [
        "| `fast-dev` | `fast-dev/<topic>` |", "| `live-dev` | `live-dev/<topic>` |",
        "selected caller", "mismatch", "Do not switch primaries", "not interchangeable",
        "ordinary task completion", "commit request", "do not authorize publishing",
    ]:
        assert term in text
    assert not (REPO_ROOT / ".opencode/skills/live-dev-wrap-up").exists()
    reviewer = (REPO_ROOT / ".opencode/agents/fast-dev-reviewer.md").read_text(encoding="utf-8")
    assert "fast-dev and live-dev" in reviewer


@pytest.mark.parametrize("path", ["docs/dev/features/opencode-agent-workflow.md", "docs/dev/features/live-dev.md"])
def test_live_dev_documented_local_loop_and_shared_explicit_wrap_up(path: str):
    text = (REPO_ROOT / path).read_text(encoding="utf-8")
    for term in [
        "live-dev/<topic>", "local only", "fast-dev-wrap-up", "fast-dev-reviewer",
        "manual", "before editing", "validated", "more than one", "select",
        "no filesystem watching", "confirmation", "failed reload", "recovery",
        "Restart OpenCode", "origin/main",
    ]:
        assert term in text


def test_finishing_skill_does_not_recommend_branch_deletion():
    path = REPO_ROOT / ".opencode" / "skills" / "finishing-a-development-branch" / "SKILL.md"
    text = path.read_text(encoding="utf-8")

    assert "git branch -d" not in text
    assert "Cleanup Branch" not in text
    assert "| 1. Merge locally | yes | — | — | yes |" not in text


def test_git_integrator_rejects_extra_bash_allow(tmp_path: Path):
    repo = make_repo(tmp_path)
    agent_path = repo / ".opencode" / "agents" / "git-integrator.md"
    agent_text = agent_path.read_text(encoding="utf-8")
    agent_path.write_text(
        agent_text.replace(
            '    "python3 scripts/opencode_git_integrate.py create-followup-branch --repo-root .": allow\n',
            '    "python3 scripts/opencode_git_integrate.py create-followup-branch --repo-root .": allow\n    "python3 scripts/opencode_git_integrate.py create-local-main-wrapup-branch --repo-root .": allow\n    "git switch -c *": allow\n',
        ),
        encoding="utf-8",
    )

    assert "capability-boundary" in violation_codes(repo)


@pytest.mark.parametrize(
    "extra_entry",
    [
        '    "git switch -c *": "allow"\n',
        '    "git switch -c *": allow # broad raw git permission\n',
        '    "git switch -c *": "allow" # broad raw git permission\n',
        "    'git switch -c *': 'ask' # broad raw git permission\n",
    ],
)
def test_git_integrator_rejects_extra_bash_allow_or_ask_with_quotes_or_comments(tmp_path: Path, extra_entry: str):
    repo = make_repo(tmp_path)
    agent_path = repo / ".opencode" / "agents" / "git-integrator.md"
    agent_text = agent_path.read_text(encoding="utf-8")
    agent_path.write_text(
        agent_text.replace(
            '    "python3 scripts/opencode_git_integrate.py create-followup-branch --repo-root .": allow\n',
            '    "python3 scripts/opencode_git_integrate.py create-followup-branch --repo-root .": allow\n    "python3 scripts/opencode_git_integrate.py create-local-main-wrapup-branch --repo-root .": allow\n' + extra_entry,
        ),
        encoding="utf-8",
    )

    assert "capability-boundary" in violation_codes(repo)


def test_check_repo_fails_when_permission_frontmatter_contains_ask(tmp_path: Path):
    repo = make_repo(tmp_path, permission_text='  bash:\n    "*": ask\n')

    checker = load_checker()
    issues = checker.check_repo(repo)

    assert any(
        violation.code == "no-ask-permission"
        and '.opencode/agents/example-agent.md' in violation.message
        and 'bash "*": ask' in violation.message
        for violation in issues
    )


def test_supervisor_allows_routine_bash_by_default_and_denies_capability_commands():
    bash_entries = permission_entries(REPO_ROOT, "supervisor", "bash")

    assert bash_entries["*"] == "allow"
    assert bash_entries["git push*"] == "deny"
    assert bash_entries["git fetch*"] == "deny"
    assert bash_entries["git pull*"] == "deny"
    assert bash_entries["git merge*"] == "deny"
    assert bash_entries["git -C * fetch*"] == "deny"
    assert bash_entries["git -C * pull*"] == "deny"
    assert bash_entries["git -C * merge*"] == "deny"
    assert bash_entries["git -C * push*"] == "deny"
    assert bash_entries["gh *"] == "deny"


def test_supervisor_denies_destructive_branch_bash_operations():
    bash_entries = permission_entries(REPO_ROOT, "supervisor", "bash")

    for pattern in [
        "git branch -d*",
        "git branch -D*",
        "git branch --delete*",
        "git switch -C*",
        "git checkout -B*",
        "git -C * branch -d*",
        "git -C * branch -D*",
        "git -C * branch --delete*",
        "git -C * switch -C*",
        "git -C * checkout -B*",
    ]:
        assert bash_entries[pattern] == "deny"


def test_supervisor_denies_secret_env_reads_and_broad_external_directories():
    read_entries = permission_entries(REPO_ROOT, "supervisor", "read")
    external_entries = permission_entries(REPO_ROOT, "supervisor", "external_directory")

    assert read_entries["*.env"] == "deny"
    assert read_entries["*.env.*"] == "deny"
    assert read_entries["*.env.example"] == "allow"
    assert external_entries["*"] == "deny"


@pytest.mark.parametrize(
    "permission_text",
    [
        "  bash: ask # trailing comment\n",
        "  bash: 'ask'\n",
        "  bash: \"ask\" # trailing comment\n",
        "  bash:\n    \"*\": ask # trailing comment\n",
        "  bash:\n    \"*\": 'ask'\n",
        "  bash:\n    \"*\": \"ask\" # trailing comment\n",
    ],
)
def test_check_repo_fails_when_permission_frontmatter_contains_ask_variants(tmp_path: Path, permission_text: str):
    repo = make_repo(tmp_path, permission_text=permission_text)

    assert "no-ask-permission" in violation_codes(repo)


def test_cli_emits_pass_or_fail_json(tmp_path: Path):
    repo = make_repo(tmp_path)
    result = subprocess.run(
        [sys.executable, str(CHECKER), "--repo-root", str(repo)],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    payload = json.loads(result.stdout)
    assert result.returncode == 0
    assert payload == {"status": "pass", "violations": []}
    assert result.stderr == ""


def test_check_repo_fails_when_required_capability_agent_missing(tmp_path: Path):
    repo = make_repo(tmp_path)
    (repo / ".opencode" / "agents" / "git-integrator.md").unlink()

    checker = load_checker()
    issues = checker.check_repo(repo)

    assert any(
        violation.code == "capability-dependency"
        and ".opencode/agents/git-integrator.md" in violation.message
        for violation in issues
    )


def test_check_repo_fails_when_required_wrapper_missing(tmp_path: Path):
    repo = make_repo(tmp_path)
    (repo / "scripts" / "opencode_git_integrate.py").unlink()

    checker = load_checker()
    issues = checker.check_repo(repo)

    assert any(
        violation.code == "capability-dependency"
        and "scripts/opencode_git_integrate.py" in violation.message
        for violation in issues
    )


def test_check_repo_fails_when_agent_allowlist_references_missing_wrapper(tmp_path: Path):
    repo = make_repo(tmp_path)
    agent_path = repo / ".opencode" / "agents" / "git-integrator.md"
    agent_text = agent_path.read_text(encoding="utf-8")
    agent_path.write_text(
        agent_text.replace(
            '    "python3 scripts/opencode_git_integrate.py status --repo-root .": allow\n',
            '    "python3 scripts/opencode_git_integrate.py status --repo-root .": allow\n    "python3 scripts/missing_wrapper.py status --repo-root .": allow\n',
        ),
        encoding="utf-8",
    )

    checker = load_checker()
    issues = checker.check_repo(repo)

    assert any(
        violation.code == "capability-dependency"
        and "missing wrapper script" in violation.message
        and "scripts/missing_wrapper.py" in violation.message
        for violation in issues
    )


def test_reviewer_with_bash_allow_fails(tmp_path: Path):
    repo = make_repo(tmp_path, agent_name="reviewer", permission_text="  bash: allow\n")
    assert "role-boundary" in violation_codes(repo)


def test_implementer_with_git_push_allow_fails(tmp_path: Path):
    repo = make_repo(tmp_path, agent_name="implementer", permission_text="  bash:\n    \"git push*\": allow\n")
    assert "role-boundary" in violation_codes(repo)


def test_web_researcher_with_local_read_fails(tmp_path: Path):
    repo = make_repo(tmp_path, agent_name="web-researcher", permission_text="  read:\n    \"*\": allow\n")
    assert "role-boundary" in violation_codes(repo)


def test_capability_agent_with_edit_allow_fails(tmp_path: Path):
    repo = make_repo(tmp_path, agent_name="git-integrator", permission_text="  edit: allow\n  bash: deny\n")
    assert "capability-boundary" in violation_codes(repo)


@pytest.mark.parametrize(
    "permission_text",
    [
        '  bash:\n    "git push origin main": allow\n',
        '  bash:\n    "git -C * push origin main": allow\n',
        '  bash:\n    "git push origin HEAD:refs/heads/main": allow\n',
        '  bash:\n    "git push origin HEAD:main": allow\n',
        '  bash:\n    "git push origin refs/heads/main": allow\n',
        '  bash:\n    "git -C * push origin HEAD:refs/heads/main": ask\n',
        '  bash:\n    "git -C * push origin HEAD:main": ask\n',
        '  bash:\n    "git -C * push origin refs/heads/main": ask\n',
        "  bash:\n    'git push origin main': ask\n",
        '  bash:\n    "git push *--force*": allow\n',
        '  bash:\n    "git -C * push *--force*": allow\n',
        "  bash:\n    'git push -f *': ask\n",
        '  bash:\n    "git commit --amend*": allow\n',
        '  bash:\n    "git -C * commit --amend*": allow\n',
        '  bash:\n    "git rebase*": allow\n',
        '  bash:\n    "git -C * rebase*": allow\n',
        "  bash:\n    'git rebase*': ask\n",
        "  bash:\n    'git -C * rebase*': ask\n",
        '  bash:\n    "git reset*": allow\n',
        '  bash:\n    "git -C * reset*": allow\n',
        "  bash:\n    'git reset*': ask\n",
        "  bash:\n    'git -C * reset*': ask\n",
        '  bash:\n    "git clean*": allow\n',
        '  bash:\n    "git -C * clean*": allow\n',
        "  bash:\n    'git clean*': ask\n",
        '  bash:\n    "git push origin --delete *": allow\n',
        '  bash:\n    "rm -rf*": allow\n',
        "  bash:\n    'rm -r*': ask\n",
        '  bash:\n    "find * -delete*": allow\n',
        '  bash:\n    "sudo *": allow\n',
        "  bash:\n    'sudo *': ask\n",
        '  bash:\n    "su *": allow\n',
        '  bash:\n    "doas *": ask\n',
        '  bash:\n    "apt *": allow\n',
        "  bash:\n    'apt-get *': ask\n",
        '  bash:\n    "dnf *": allow\n',
        '  bash:\n    "pacman *": ask\n',
        '  bash:\n    "brew *": allow\n',
        '  bash:\n    "gh *": ask\n',
        "  bash:\n    'gh *': allow\n",
        '  external_directory:\n    "*": allow\n',
        "  external_directory:\n    '~/**': ask\n",
        '  external_directory:\n    "/**": allow\n',
        '  external_directory:\n    "/home/**": ask\n',
    ],
)
def test_each_unsafe_permission_pattern_fails_independently(tmp_path: Path, permission_text: str):
    repo = make_repo(tmp_path, agent_name="supervisor", permission_text=permission_text)
    codes = violation_codes(repo)
    assert "unsafe-permission" in codes


def test_opencode_json_must_parse_and_keep_supervisor_default(tmp_path: Path):
    repo = make_repo(tmp_path)
    write_file(repo / ".opencode" / "opencode.json", '{"default_agent":"implementer"}')
    assert "opencode-json" in violation_codes(repo)


def test_agent_and_skill_frontmatter_required(tmp_path: Path):
    repo = make_repo(tmp_path)
    write_file(repo / ".opencode" / "agents" / "broken.md", "---\ndescription: Broken\n---\n")
    write_file(repo / ".opencode" / "skills" / "broken" / "SKILL.md", "---\nname: broken\n---\n")
    codes = violation_codes(repo)
    assert "agent-frontmatter" in codes
    assert "skill-frontmatter" in codes


@pytest.mark.parametrize(
    "permission_text",
    [
        '  edit: deny\n  task: deny\n  external_directory: deny\n  webfetch: deny\n  websearch: deny\n  question: deny\n  bash:\n    "python3 scripts/opencode_pr_operator.py create --repo-root . --head *": allow\n',
        '  edit: deny\n  task: deny\n  external_directory: deny\n  webfetch: deny\n  websearch: deny\n  question: deny\n  bash:\n    "python3 scripts/opencode_pr_operator.py enable-auto-merge --repo-root . --branch *": allow\n',
        '  edit: deny\n  task: deny\n  external_directory: deny\n  webfetch: deny\n  websearch: deny\n  question: deny\n  bash:\n    "python3 scripts/opencode_pr_operator.py poll-merge-queue --repo-root . --branch * --timeout-seconds * --interval-seconds *": allow\n',
    ],
)
def test_github_operator_rejects_wrapper_bash_permissions_with_untrusted_suffix_wildcards(
    tmp_path: Path, permission_text: str
):
    repo = make_repo(tmp_path, agent_name="github-operator", permission_text=permission_text)

    codes = violation_codes(repo)

    assert "capability-boundary" in codes


def test_github_operator_rejects_actions_log_wildcard_permission(tmp_path: Path):
    repo = make_repo(tmp_path)
    github_permissions = (
        '  edit: deny\n'
        '  task: deny\n'
        '  external_directory: deny\n'
        '  webfetch: deny\n'
        '  websearch: deny\n'
        '  question: deny\n'
        '  bash:\n'
        '    "python3 scripts/opencode_pr_operator.py auth-status --repo-root .": allow\n'
        '    "python3 scripts/opencode_pr_operator.py check-main-protection --repo-root .": allow\n'
        '    "python3 scripts/opencode_pr_operator.py create-current --repo-root .": allow\n'
        '    "python3 scripts/opencode_pr_operator.py enable-auto-merge-current --repo-root .": allow\n'
        '    "python3 scripts/opencode_pr_operator.py view-current --repo-root .": allow\n'
        '    "python3 scripts/opencode_pr_operator.py poll-merge-queue-current --repo-root .": allow\n'
        '    "python3 scripts/opencode_pr_operator.py failed-actions-log-bundle-current --repo-root .": allow\n'
        '    "python3 scripts/opencode_pr_operator.py actions-log --repo-root . --run-id * --job-id * --full": allow\n'
    )
    write_file(
        repo / ".opencode" / "agents" / "github-operator.md",
        agent("github-operator", github_permissions),
    )

    assert "capability-boundary" in violation_codes(repo)
