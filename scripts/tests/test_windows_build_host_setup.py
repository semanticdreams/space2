from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def read_repo_text(relative_path: str) -> str:
    return (REPO_ROOT / relative_path).read_text(encoding="utf-8")


def test_windows_smoke_rg_dependency_is_installed_and_guarded() -> None:
    setup_script = read_repo_text("scripts/setup-windows-build-host.sh")
    workflows = [
        ".github/workflows/test.yml",
        ".github/workflows/build.yml",
    ]

    for workflow_path in workflows:
        workflow = read_repo_text(workflow_path)
        assert "scripts/setup-windows-build-host.sh" in workflow
        assert "| rg " in workflow

    assert "ripgrep" in setup_script
    assert "command -v rg" in setup_script
    assert "Missing ripgrep after setup." in setup_script
