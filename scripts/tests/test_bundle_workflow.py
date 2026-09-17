from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "bundle.yml"


class WorkflowLoader(yaml.SafeLoader):
    pass


for first_char, mappings in list(WorkflowLoader.yaml_implicit_resolvers.items()):
    WorkflowLoader.yaml_implicit_resolvers[first_char] = [
        (tag, regexp)
        for tag, regexp in mappings
        if tag != "tag:yaml.org,2002:bool"
    ]


def read_workflow_text() -> str:
    return WORKFLOW_PATH.read_text(encoding="utf-8")


def load_workflow() -> dict:
    return yaml.load(read_workflow_text(), Loader=WorkflowLoader)


def workflow_inputs() -> dict:
    workflow = load_workflow()
    return workflow["on"]["workflow_call"]["inputs"]


def test_bundle_workflow_exposes_required_and_optional_inputs() -> None:
    inputs = workflow_inputs()

    assert inputs["space-version"]["required"] == "true"
    assert inputs["app-name"]["required"] == "true"
    assert inputs["space-version"]["type"] == "string"
    assert inputs["app-name"]["type"] == "string"

    optional_inputs = {name for name, config in inputs.items() if config.get("required") != "true"}
    assert optional_inputs == {
        "app-id",
        "entrypoint",
        "assets-dir",
        "icon-path",
        "linux-profile",
        "release-version",
    }
    assert inputs["app-id"]["default"] == ""
    assert inputs["entrypoint"]["default"] == "main"
    assert inputs["assets-dir"]["default"] == "assets"
    assert inputs["icon-path"]["default"] == ""
    assert inputs["linux-profile"]["default"] == "full"
    assert inputs["release-version"]["default"] == ""


def test_bundle_workflow_checks_out_caller_app_and_space_packaging_ref() -> None:
    text = read_workflow_text()

    assert "path: app" in text
    assert "path: space-packaging" in text
    assert "github.workflow_ref" in text
    assert "SPACE_WORKFLOW_REPO" in text
    assert "SPACE_WORKFLOW_REF" in text
    assert "repository: ${{ steps.space-workflow-ref.outputs.repository }}" in text
    assert "ref: ${{ steps.space-workflow-ref.outputs.ref }}" in text


def test_bundle_workflow_downloads_pinned_space_release_artifacts() -> None:
    text = read_workflow_text()

    assert "gh release download" in text
    assert "${{ inputs.space-version }}" in text
    assert "--repo semanticdreams/space2" in text
    assert "space-linux-x86_64.tar.gz" in text
    assert "space-linux-x86_64-minimal.tar.gz" in text
    assert "space-windows-x86_64.zip" in text
    assert "space-linux-x86_64${SPACE_PROFILE_SUFFIX}.tar.gz" in text


def test_bundle_workflow_does_not_compile_space_or_use_manifests() -> None:
    text = read_workflow_text()

    forbidden_fragments = [
        "make build",
        "cmake --build",
        "scripts/build-linux.sh",
        "scripts/build-windows-from-linux.sh",
        "space-app.json",
    ]
    for fragment in forbidden_fragments:
        assert fragment not in text


def test_bundle_workflow_invokes_script_owned_packagers_and_uploads_release_artifacts() -> None:
    text = read_workflow_text()

    assert "space-packaging/scripts/normalize-app-metadata.py" in text
    assert "space-packaging/scripts/package-linux-app.py" in text
    assert "--targets deb,rpm,tarball,appimage" in text
    assert "space-packaging/scripts/package-windows-app.py" in text
    assert "--targets zip,installer-stage" in text
    assert "space-packaging/scripts/build-windows-installer.py" in text
    assert "app-release-artifacts-linux.txt" in text
    assert "app-release-artifacts-windows.txt" in text
    assert "softprops/action-gh-release@v2" in text
    assert "if: github.ref_type == 'tag'" in text
