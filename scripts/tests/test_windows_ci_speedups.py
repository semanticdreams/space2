from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]


class WorkflowLoader(yaml.SafeLoader):
    pass


for first_char, mappings in list(WorkflowLoader.yaml_implicit_resolvers.items()):
    WorkflowLoader.yaml_implicit_resolvers[first_char] = [
        (tag, regexp)
        for tag, regexp in mappings
        if tag != "tag:yaml.org,2002:bool"
    ]


def read_repo_text(relative_path: str) -> str:
    return (REPO_ROOT / relative_path).read_text(encoding="utf-8")


def load_workflow(relative_path: str) -> dict:
    return yaml.load(read_repo_text(relative_path), Loader=WorkflowLoader)


def test_pr_ci_keeps_native_windows_fast_suite_and_has_no_installer_job() -> None:
    workflow = load_workflow(".github/workflows/test.yml")
    jobs = workflow["jobs"]
    text = read_repo_text(".github/workflows/test.yml")

    assert "build-windows" in jobs
    assert "test-windows" in jobs
    assert "build-windows-installer" not in jobs
    assert jobs["test-windows"]["needs"] == "build-windows"
    assert jobs["test-windows"]["runs-on"] == "windows-latest"
    assert "tests.fast:main" in text


def test_pr_windows_cross_build_uploads_runtime_only_and_no_packaging_inputs() -> None:
    text = read_repo_text(".github/workflows/test.yml")

    assert "name: space-windows-runtime" in text
    assert "windows-packaging-inputs" not in text
    assert "Create Windows ZIP" not in text
    assert "Verify Windows ZIP contents" not in text
    assert "space-windows-x86_64.zip" not in text
    assert "space-windows-x86_64-setup.exe" not in text
    assert "scripts/build-windows-installer.py" not in text
    assert "choco install innosetup" not in text


def test_release_workflow_keeps_windows_zip_and_installer_packaging_paths() -> None:
    workflow = load_workflow(".github/workflows/build.yml")
    jobs = workflow["jobs"]
    text = read_repo_text(".github/workflows/build.yml")

    assert "build-windows" in jobs
    assert "build-windows-installer" in jobs
    assert jobs["build-windows-installer"]["needs"] == "build-windows"
    assert "space-windows-x86_64.zip" in text
    assert "space-windows-x86_64-setup.exe" in text
    assert "choco install innosetup --no-progress -y" in text
    assert "python scripts/build-windows-installer.py" in text
    assert "softprops/action-gh-release@v2" in text
