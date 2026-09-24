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
model: openai/gpt-5.5
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
    )
    write_file(
        root / ".opencode" / "agents" / "git-integrator.md",
        agent("git-integrator", git_integrator_permissions),
    )
    write_file(
        root / ".opencode" / "agents" / "github-operator.md",
        agent(
            "github-operator",
            '  edit: deny\n  task: deny\n  external_directory: deny\n  webfetch: deny\n  websearch: deny\n  question: deny\n  bash:\n    "python3 scripts/opencode_pr_operator.py auth-status --repo-root .": allow\n',
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
    for script in [
        "opencode_capabilities.py",
        "opencode_git_integrate.py",
        "opencode_pr_operator.py",
        "opencode_pr_recovery.py",
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
    }


def test_pr_recovery_operator_allows_only_exact_guarded_recovery_command():
    bash_entries = permission_entries(REPO_ROOT, "pr-recovery-operator", "bash")

    allowed_entries = {pattern for pattern, action in bash_entries.items() if action == "allow"}
    assert allowed_entries == {
        "python3 scripts/opencode_pr_recovery.py create-current-with-followup-recovery --repo-root ."
    }


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


def test_merged_old_pr_followup_recovery_is_documented_in_workflow_files():
    required_terms = [
        "pr_head",
        "current_head",
        "MERGED",
        "create-followup-branch",
        "follow-up branch",
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


def test_workflow_docs_do_not_recommend_raw_github_polling_commands():
    forbidden_commands = [
        "gh pr view",
        "gh run list",
        "gh run watch",
    ]
    documented_paths = [
        REPO_ROOT / ".opencode" / "skills" / "finishing-a-development-branch" / "SKILL.md",
        REPO_ROOT / ".opencode" / "agents" / "supervisor.md",
        REPO_ROOT / "docs" / "dev" / "features" / "opencode-agent-workflow.md",
    ]

    for path in documented_paths:
        text = path.read_text(encoding="utf-8")
        if text.startswith("---\n"):
            text = text.split("---\n", 2)[2]
        present_commands = [command for command in forbidden_commands if command in text]
        assert present_commands == [], f"{path.relative_to(REPO_ROOT)} recommends {present_commands}"


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
            '    "python3 scripts/opencode_git_integrate.py create-followup-branch --repo-root .": allow\n    "git switch -c *": allow\n',
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
            '    "python3 scripts/opencode_git_integrate.py create-followup-branch --repo-root .": allow\n' + extra_entry,
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
