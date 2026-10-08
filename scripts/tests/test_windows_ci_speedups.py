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


def test_windows_cross_build_jobs_enable_ninja_sccache_binary_and_vcpkg_cache() -> None:
    for workflow_path in [".github/workflows/test.yml", ".github/workflows/build.yml"]:
        workflow = load_workflow(workflow_path)
        job = workflow["jobs"]["build-windows"]
        env = job["env"]
        text = read_repo_text(workflow_path)

        assert job["permissions"]["contents"] == "read"
        assert job["permissions"]["actions"] == "write"
        assert env["CMAKE_GENERATOR"] == "Ninja"
        assert env["VCPKG_FEATURE_FLAGS"] == "binarycaching"
        assert "VCPKG_BINARY_SOURCES" in env
        assert "Restore sccache binary" in text
        assert "sccache-bin-${{ runner.os }}-0.16.0" in text
        assert "cargo install sccache --version 0.16.0 --locked" in text
        assert "Export GitHub Actions cache runtime for vcpkg" in text
        assert "ACTIONS_CACHE_URL" in text
        assert "ACTIONS_RESULTS_URL" in text
        assert "ACTIONS_RUNTIME_TOKEN" in text


def test_pr_vcpkg_binary_cache_is_read_only_for_pull_requests() -> None:
    workflow = load_workflow(".github/workflows/test.yml")
    source = workflow["jobs"]["build-windows"]["env"]["VCPKG_BINARY_SOURCES"]

    assert "github.event_name == 'pull_request'" in source
    assert "clear;x-gha,read" in source
    assert "clear;x-gha,readwrite" in source


def test_build_windows_script_builds_targets_in_parallel() -> None:
    script = read_repo_text("scripts/build-windows.sh")

    assert "resolve_build_jobs()" in script
    assert 'BUILD_JOBS="$(resolve_build_jobs)"' in script
    assert "BUILD_JOBS must be a positive integer" in script
    assert 'cmake --build "${BUILD_DIR}" --config Release --parallel "${BUILD_JOBS}" --target space space-cli' in script


def test_build_windows_script_resets_stale_cache_when_generator_changes() -> None:
    script = read_repo_text("scripts/build-windows.sh")

    assert 'CMAKE_GENERATOR:INTERNAL=${CMAKE_GENERATOR}' in script
    assert 'Resetting ${BUILD_DIR} due to stale CMake cache.' in script


def test_windows_wine_notes_document_validation_packaging_boundary_and_speedups() -> None:
    text = read_repo_text("docs/dev/notes/windows-wine-build-and-test.md")

    assert "PR/merge-queue validation path" in text
    assert "does not build the Windows installer" in text
    assert "does not create the release ZIP" in text
    assert "Release/manual packaging path" in text
    assert "existing `workflow_dispatch` behavior remains available" in text
    assert "vcpkg binary caching" in text
    assert "Ninja parallel builds" in text
