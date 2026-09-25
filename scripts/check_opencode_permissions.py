#!/usr/bin/env python3
"""Fail-closed policy checks for repo-local OpenCode permissions."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass(frozen=True)
class PolicyViolation:
    path: str
    code: str
    message: str


REQUIRED_AGENT_KEYS = {"description", "mode", "model", "permission"}
REQUIRED_SKILL_KEYS = {"name", "description"}
CAPABILITY_AGENTS = {"git-integrator", "github-operator", "config-auditor", "pr-recovery-operator", "windows-ci-reproducer"}
GIT_INTEGRATOR_ALLOWED_WRAPPER_COMMANDS = {
    "python3 scripts/opencode_git_integrate.py status --repo-root .",
    "python3 scripts/opencode_git_integrate.py fetch-origin --repo-root .",
    "python3 scripts/opencode_git_integrate.py merge-origin-main --repo-root .",
    "python3 scripts/opencode_git_integrate.py push-current --repo-root .",
    "python3 scripts/opencode_git_integrate.py create-followup-branch --repo-root .",
}
PR_RECOVERY_ALLOWED_WRAPPER_COMMAND = "python3 scripts/opencode_pr_recovery.py create-current-with-followup-recovery --repo-root ."
WINDOWS_CI_REPRODUCER_ALLOWED_WRAPPER_COMMANDS = {
    "python3 scripts/opencode_windows_ci_repro.py preflight --repo-root .",
    "python3 scripts/opencode_windows_ci_repro.py setup-host --repo-root .",
    "python3 scripts/opencode_windows_ci_repro.py reproduce --repo-root .",
}
REQUIRED_CAPABILITY_FILES = (
    ".opencode/agents/git-integrator.md",
    ".opencode/agents/github-operator.md",
    ".opencode/agents/config-auditor.md",
    ".opencode/agents/pr-recovery-operator.md",
    ".opencode/agents/windows-ci-reproducer.md",
    "scripts/opencode_capabilities.py",
    "scripts/opencode_git_integrate.py",
    "scripts/opencode_pr_operator.py",
    "scripts/opencode_pr_recovery.py",
    "scripts/opencode_windows_ci_repro.py",
    "scripts/verify_opencode_home_config.py",
)
SECRET_EXTERNAL_PATTERNS = ("auth.json", "auth.jsonc", "secret", "token")
BLOCKED_ACTIONS = {"allow", "ask"}
WRAPPER_REFERENCE_RE = re.compile(r"(?<![\w/.-])(scripts/[A-Za-z0-9_.-]+\.py)(?![\w/.-])")


def _rel(repo_root: Path, path: Path) -> str:
    try:
        return path.relative_to(repo_root).as_posix()
    except ValueError:
        return path.as_posix()


def _frontmatter(text: str) -> tuple[dict[str, str], str | None]:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, None
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            raw = "\n".join(lines[1:index])
            keys: dict[str, str] = {}
            for line in lines[1:index]:
                if line.startswith((" ", "\t")) or ":" not in line:
                    continue
                key, value = line.split(":", 1)
                keys[key.strip()] = value.strip().strip('"\'')
            return keys, raw
    return {}, None


def _has_scalar_permission(raw: str, key: str, action: str) -> bool:
    return re.search(rf"(?m)^\s{{2}}{re.escape(key)}:\s*{re.escape(action)}\s*$", raw) is not None


def _has_mapping_action(raw: str, parent: str, pattern: str, action: str) -> bool:
    return (pattern, action) in _mapping_entries(raw, parent)


def _mapping_entries(raw: str, parent: str) -> list[tuple[str, str]]:
    parent_match = re.search(rf"(?m)^\s{{2}}{re.escape(parent)}:\s*$", raw)
    if not parent_match:
        return []
    tail = raw[parent_match.end() :]
    block_lines = []
    for line in tail.splitlines():
        if line.startswith("  ") and not line.startswith("    ") and line.strip():
            break
        block_lines.append(line)
    entries: list[tuple[str, str]] = []
    for line in block_lines:
        match = re.match(r"^\s{4}([\"']?)(.*?)\1:\s*([\"']?)(allow|ask|deny)\3\s*(?:#.*)?$", line)
        if match:
            entries.append((match.group(2), match.group(4)))
    return entries


def _normalized_command(pattern: str) -> str:
    command = " ".join(pattern.strip().lower().split())
    parts = command.split()
    if len(parts) > 3 and parts[0] == "git" and parts[1] == "-c":
        return "git " + " ".join(parts[3:])
    return command


def _is_forbidden_bash_pattern(pattern: str) -> bool:
    command = _normalized_command(pattern)
    if _pushes_to_main(command):
        return True
    if command.startswith("git push origin --delete"):
        return True
    if command.startswith("git branch -d") or command.startswith("git branch --delete"):
        return True
    if command.startswith("git push") and ("--force" in command or re.search(r"(^|\s)-f($|\s|\*)", command)):
        return True
    if command.startswith(("git rebase", "git reset", "git clean", "git commit --amend")):
        return True
    if command.startswith(("rm -rf", "rm -fr", "rm -r")):
        return True
    if command.startswith("find ") and " -delete" in command:
        return True
    if command == "sudo" or command.startswith("sudo "):
        return True
    if command == "su" or command.startswith("su "):
        return True
    if command == "doas" or command.startswith("doas "):
        return True
    for manager in ("apt", "apt-get", "dnf", "pacman", "brew"):
        if command == manager or command.startswith(f"{manager} "):
            return True
    return command in {"gh", "gh *", "gh*"}


def _pushes_to_main(command: str) -> bool:
    tokens = command.split()
    if len(tokens) < 4 or tokens[0] != "git" or tokens[1] != "push":
        return False
    remote_index = 2
    while remote_index < len(tokens) and tokens[remote_index].startswith("-"):
        remote_index += 1
    if remote_index >= len(tokens) or tokens[remote_index] != "origin":
        return False
    for refspec in tokens[remote_index + 1 :]:
        if refspec.startswith("-"):
            continue
        target = refspec.rsplit(":", 1)[-1]
        if target.startswith("refs/heads/"):
            target = target.removeprefix("refs/heads/")
        if target == "main":
            return True
    return False


def _has_untrusted_suffix_wildcard(pattern: str) -> bool:
    command = _normalized_command(pattern)
    return command.startswith("python3 scripts/opencode_pr_operator.py ") and command.rstrip().endswith("*")


def _is_forbidden_external_pattern(pattern: str, action: str) -> bool:
    normalized = pattern.strip().lower()
    if action == "allow" and normalized in {"*", "**", "/*", "/**"}:
        return True
    return normalized in {"~", "~/", "~/*", "~/**", "/", "/*", "/**", "/home/*", "/home/**", "/users/*", "/users/**"}


def _violation(path: Path, repo_root: Path, code: str, message: str) -> PolicyViolation:
    return PolicyViolation(_rel(repo_root, path), code, message)


def _check_opencode_json(repo_root: Path) -> list[PolicyViolation]:
    path = repo_root / ".opencode" / "opencode.json"
    violations: list[PolicyViolation] = []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [_violation(path, repo_root, "opencode-json", f".opencode/opencode.json must parse as JSON: {error}")]
    if data.get("default_agent") != "supervisor":
        violations.append(_violation(path, repo_root, "opencode-json", 'opencode.json must keep "default_agent": "supervisor"'))
    return violations


def _check_required_capability_files(repo_root: Path) -> list[PolicyViolation]:
    violations: list[PolicyViolation] = []
    for relative_path in REQUIRED_CAPABILITY_FILES:
        path = repo_root / relative_path
        if not path.exists():
            violations.append(_violation(path, repo_root, "capability-dependency", f"missing capability dependency: {relative_path}"))
    return violations


def _check_agent_wrapper_references(repo_root: Path) -> list[PolicyViolation]:
    agents_dir = repo_root / ".opencode" / "agents"
    violations: list[PolicyViolation] = []
    for agent_path in sorted(agents_dir.glob("*.md")):
        text = agent_path.read_text(encoding="utf-8")
        _, raw = _frontmatter(text)
        if raw is None:
            continue
        referenced_scripts = set()
        for pattern, action in _mapping_entries(raw, "bash"):
            if action == "allow":
                referenced_scripts.update(WRAPPER_REFERENCE_RE.findall(pattern))
        for script_path in sorted(referenced_scripts):
            if not (repo_root / script_path).exists():
                violations.append(
                    _violation(
                        agent_path,
                        repo_root,
                        "capability-dependency",
                        f"missing wrapper script referenced by {_rel(repo_root, agent_path)}: {script_path}",
                    )
                )
    return violations


def _check_unsafe_text(path: Path, repo_root: Path, raw: str) -> list[PolicyViolation]:
    violations = []
    for pattern, action in _mapping_entries(raw, "bash"):
        if action in BLOCKED_ACTIONS and _is_forbidden_bash_pattern(pattern):
            violations.append(_violation(path, repo_root, "unsafe-permission", f"Unsafe bash permission must be denied: {pattern}: {action}"))
    if re.search(r'(?m)^\s+external_directory:\s*(allow|ask)\s*$', raw):
        violations.append(_violation(path, repo_root, "unsafe-permission", "external_directory must not be a broad scalar allow/ask"))
    for pattern, action in _mapping_entries(raw, "external_directory"):
        if action in BLOCKED_ACTIONS and _is_forbidden_external_pattern(pattern, action):
            violations.append(_violation(path, repo_root, "unsafe-permission", f"Unsafe external_directory permission must be denied: {pattern}: {action}"))
    return violations


def _check_no_ask_actions(path: Path, repo_root: Path, raw: str) -> list[PolicyViolation]:
    violations: list[PolicyViolation] = []
    parent = None
    ask_value = r"(?:ask|[\"']ask[\"'])"
    suffix = r"(?:\s*(?:#.*)?)$"
    for line in raw.splitlines():
        parent_match = re.match(r"^\s{2}([A-Za-z0-9_-]+):\s*$", line)
        if parent_match:
            parent = parent_match.group(1)
            continue
        scalar_match = re.match(rf"^\s{{2}}([A-Za-z0-9_-]+):\s*{ask_value}{suffix}", line)
        if scalar_match:
            key = scalar_match.group(1)
            violations.append(
                _violation(path, repo_root, "no-ask-permission", f"{_rel(repo_root, path)} permission must not use ask actions: {key}: ask")
            )
            parent = None
            continue
        mapping_match = re.match(rf"^\s{{4}}([\"']?)(.*?)\1:\s*{ask_value}{suffix}", line)
        if mapping_match:
            key = mapping_match.group(2)
            prefix = f"{parent} " if parent else ""
            violations.append(
                _violation(path, repo_root, "no-ask-permission", f'{_rel(repo_root, path)} permission must not use ask actions: {prefix}"{key}": ask')
            )
    return violations


def _check_role_boundaries(path: Path, repo_root: Path, name: str, raw: str) -> list[PolicyViolation]:
    violations: list[PolicyViolation] = []
    if name == "reviewer":
        for key in ("edit", "task", "external_directory", "webfetch", "websearch", "question", "bash"):
            if not _has_scalar_permission(raw, key, "deny"):
                violations.append(_violation(path, repo_root, "role-boundary", f"reviewer must keep {key}: deny"))
    elif name == "implementer":
        if not _has_scalar_permission(raw, "external_directory", "deny"):
            violations.append(_violation(path, repo_root, "role-boundary", "implementer must keep external_directory: deny"))
        if not _has_mapping_action(raw, "bash", "git push*", "deny"):
            violations.append(_violation(path, repo_root, "role-boundary", "implementer must deny git push*"))
    elif name == "web-researcher":
        for key in ("read", "glob", "grep", "list", "lsp", "edit", "task", "external_directory", "question", "bash"):
            if not _has_scalar_permission(raw, key, "deny"):
                violations.append(_violation(path, repo_root, "role-boundary", f"web-researcher must keep local {key}: deny"))
        for key in ("webfetch", "websearch"):
            if not _has_scalar_permission(raw, key, "allow"):
                violations.append(_violation(path, repo_root, "role-boundary", f"web-researcher must keep {key}: allow"))
    return violations


def _check_capability_boundary(path: Path, repo_root: Path, name: str, raw: str) -> list[PolicyViolation]:
    if name not in CAPABILITY_AGENTS:
        return []
    violations: list[PolicyViolation] = []
    for key in ("edit", "task", "webfetch", "websearch", "question"):
        if not _has_scalar_permission(raw, key, "deny"):
            violations.append(_violation(path, repo_root, "capability-boundary", f"{name} must keep {key}: deny"))
    if name != "config-auditor" and not _has_scalar_permission(raw, "external_directory", "deny"):
        violations.append(_violation(path, repo_root, "capability-boundary", f"{name} must deny external_directory"))
    if name == "config-auditor":
        if not _has_mapping_action(raw, "external_directory", "~/.config/opencode/**", "allow"):
            violations.append(_violation(path, repo_root, "capability-boundary", "config-auditor external access must be limited to ~/.config/opencode/**"))
        for secret in SECRET_EXTERNAL_PATTERNS:
            if secret not in raw:
                violations.append(_violation(path, repo_root, "capability-boundary", f"config-auditor must deny {secret}-looking OpenCode home paths"))
    if name == "github-operator":
        for pattern, action in _mapping_entries(raw, "bash"):
            if action in BLOCKED_ACTIONS and _has_untrusted_suffix_wildcard(pattern):
                violations.append(_violation(path, repo_root, "capability-boundary", f"github-operator wrapper permission must not end in an untrusted wildcard: {pattern}: {action}"))
    if name == "git-integrator":
        bash_entries = _mapping_entries(raw, "bash")
        bash_actions = dict(bash_entries)
        for command in sorted(GIT_INTEGRATOR_ALLOWED_WRAPPER_COMMANDS):
            if bash_actions.get(command) != "allow":
                violations.append(_violation(path, repo_root, "capability-boundary", f"git-integrator must allow guarded wrapper command exactly: {command}"))
        for pattern, action in bash_entries:
            if action in BLOCKED_ACTIONS and pattern not in GIT_INTEGRATOR_ALLOWED_WRAPPER_COMMANDS:
                violations.append(_violation(path, repo_root, "capability-boundary", f"git-integrator bash permission must be limited to approved wrapper commands: {pattern}: {action}"))
    if name == "pr-recovery-operator":
        bash_entries = _mapping_entries(raw, "bash")
        bash_actions = dict(bash_entries)
        if bash_actions.get(PR_RECOVERY_ALLOWED_WRAPPER_COMMAND) != "allow":
            violations.append(
                _violation(
                    path,
                    repo_root,
                    "capability-boundary",
                    f"pr-recovery-operator must allow guarded wrapper command exactly: {PR_RECOVERY_ALLOWED_WRAPPER_COMMAND}",
                )
            )
        for pattern, action in bash_entries:
            if action in BLOCKED_ACTIONS and pattern != PR_RECOVERY_ALLOWED_WRAPPER_COMMAND:
                violations.append(
                    _violation(
                        path,
                        repo_root,
                        "capability-boundary",
                        f"pr-recovery-operator bash permission must be limited to approved wrapper command: {pattern}: {action}",
                    )
                )
    if name == "windows-ci-reproducer":
        bash_entries = _mapping_entries(raw, "bash")
        bash_actions = dict(bash_entries)
        for command in sorted(WINDOWS_CI_REPRODUCER_ALLOWED_WRAPPER_COMMANDS):
            if bash_actions.get(command) != "allow":
                violations.append(
                    _violation(
                        path,
                        repo_root,
                        "capability-boundary",
                        f"windows-ci-reproducer must allow guarded wrapper command exactly: {command}",
                    )
                )
        for pattern, action in bash_entries:
            if action in BLOCKED_ACTIONS and pattern not in WINDOWS_CI_REPRODUCER_ALLOWED_WRAPPER_COMMANDS:
                violations.append(
                    _violation(
                        path,
                        repo_root,
                        "capability-boundary",
                        f"windows-ci-reproducer bash permission must be limited to approved wrapper commands: {pattern}: {action}",
                    )
                )
    return violations


def _check_agents(repo_root: Path) -> list[PolicyViolation]:
    agents_dir = repo_root / ".opencode" / "agents"
    violations: list[PolicyViolation] = []
    for path in sorted(agents_dir.glob("*.md")):
        text = path.read_text(encoding="utf-8")
        keys, raw = _frontmatter(text)
        name = path.stem
        if raw is None:
            violations.append(_violation(path, repo_root, "agent-frontmatter", "agent file must start with frontmatter"))
            continue
        missing = REQUIRED_AGENT_KEYS - set(keys)
        if missing:
            violations.append(_violation(path, repo_root, "agent-frontmatter", f"agent frontmatter missing: {', '.join(sorted(missing))}"))
        violations.extend(_check_no_ask_actions(path, repo_root, raw))
        violations.extend(_check_unsafe_text(path, repo_root, raw))
        violations.extend(_check_role_boundaries(path, repo_root, name, raw))
        violations.extend(_check_capability_boundary(path, repo_root, name, raw))
    return violations


def _check_skills(repo_root: Path) -> list[PolicyViolation]:
    skills_dir = repo_root / ".opencode" / "skills"
    violations: list[PolicyViolation] = []
    for path in sorted(skills_dir.glob("*/SKILL.md")):
        text = path.read_text(encoding="utf-8")
        keys, raw = _frontmatter(text)
        if raw is None:
            violations.append(_violation(path, repo_root, "skill-frontmatter", "skill file must start with frontmatter"))
            continue
        missing = REQUIRED_SKILL_KEYS - set(keys)
        if missing:
            violations.append(_violation(path, repo_root, "skill-frontmatter", f"skill frontmatter missing: {', '.join(sorted(missing))}"))
    return violations


def check_repo(repo_root: Path) -> list[PolicyViolation]:
    repo_root = repo_root.resolve()
    violations: list[PolicyViolation] = []
    violations.extend(_check_opencode_json(repo_root))
    violations.extend(_check_required_capability_files(repo_root))
    violations.extend(_check_agent_wrapper_references(repo_root))
    violations.extend(_check_agents(repo_root))
    violations.extend(_check_skills(repo_root))
    return violations


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", required=True, type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    violations = check_repo(args.repo_root)
    status = "fail" if violations else "pass"
    print(json.dumps({"status": status, "violations": [asdict(violation) for violation in violations]}, sort_keys=True))
    return 1 if violations else 0


if __name__ == "__main__":
    raise SystemExit(main())
