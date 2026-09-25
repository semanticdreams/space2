from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text()


def test_supervisor_routes_windows_ci_failures_to_reproducer():
    text = read(".opencode/agents/supervisor.md")
    assert "windows-ci-reproducer" in text
    assert "build-windows" in text
    assert "test-windows" in text
    assert "build-windows-installer" in text
    assert "not obviously CI infrastructure-only" in text
    assert "Linux cross-build + Wine" in text


def test_finishing_and_github_workflow_debug_require_local_windows_reproduction():
    for path in [
        ".opencode/skills/finishing-a-development-branch/SKILL.md",
        ".opencode/skills/github-workflow-debug/SKILL.md",
    ]:
        text = read(path)
        assert "windows-ci-reproducer" in text
        assert "before pushing another" in text or "before another push" in text
        assert "not obviously CI infrastructure-only" in text


def test_runtime_and_dev_docs_name_wrapper_commands():
    for path in [
        ".opencode/skills/space-testing-runtime/SKILL.md",
        "docs/dev/features/opencode-agent-workflow.md",
        "docs/dev/notes/windows-wine-build-and-test.md",
    ]:
        text = read(path)
        assert "opencode_windows_ci_repro.py" in text
        assert "preflight --repo-root ." in text
        assert "setup-host --repo-root ." in text
        assert "reproduce --repo-root ." in text
