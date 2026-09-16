from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def read_repo_text(relative_path: str) -> str:
    return (REPO_ROOT / relative_path).read_text(encoding="utf-8")


def assert_absent(text: str, unexpected: str, source: str) -> None:
    assert unexpected not in text, f"{unexpected!r} must not appear in {source}"


def test_linux_packaging_names_follow_stable_hierarchy() -> None:
    script = read_repo_text("scripts/build-linux.sh")

    required_fragments = [
        'VARIANT_SUFFIX=""',
        'VARIANT_SUFFIX="-minimal"',
        'DEB_FLAVOR_SUFFIX=""',
        'RPM_FLAVOR_SUFFIX=""',
        'DEB_FLAVOR_SUFFIX="-${DEB_FLAVOR}"',
        'RPM_FLAVOR_SUFFIX="-${RPM_FLAVOR}"',
        'BIN_TAR_NAME="space-linux-x86_64${VARIANT_SUFFIX}.tar.gz"',
        'STABLE_APPIMAGE_NAME="space-linux-x86_64${VARIANT_SUFFIX}.AppImage"',
        'STABLE_DEB_NAME="space-linux-amd64${DEB_FLAVOR_SUFFIX}${VARIANT_SUFFIX}.deb"',
        'STABLE_RPM_NAME="space-linux-x86_64${RPM_FLAVOR_SUFFIX}${VARIANT_SUFFIX}.rpm"',
    ]

    for fragment in required_fragments:
        assert fragment in script

    assert_absent(script, "space-linux-x86_64-bin.tar.gz", "scripts/build-linux.sh")
    assert_absent(script, "space-minimal-linux", "scripts/build-linux.sh")


def test_workflows_use_new_release_artifact_names() -> None:
    build_workflow = read_repo_text(".github/workflows/build.yml")
    test_workflow = read_repo_text(".github/workflows/test.yml")

    expected_names = [
        "space-linux-x86_64.tar.gz",
        "space-linux-x86_64-minimal.tar.gz",
        "space-linux-amd64.deb",
        "space-linux-amd64-minimal.deb",
        "space-linux-x86_64.rpm",
        "space-linux-x86_64-minimal.rpm",
        "space-windows-x86_64.zip",
        "space-windows-x86_64-setup.exe",
    ]

    obsolete_names = [
        "space-linux-x86_64-bin.tar.gz",
        "space-minimal-linux",
        "space-windows.zip",
        "space-windows-setup.exe",
    ]

    for expected_name in expected_names:
        assert expected_name in build_workflow

    for obsolete_name in obsolete_names:
        assert_absent(build_workflow, obsolete_name, ".github/workflows/build.yml")

    for expected_name in [
        "space-windows-x86_64.zip",
        "space-windows-x86_64-setup.exe",
    ]:
        assert expected_name in test_workflow, f"{expected_name!r} missing from .github/workflows/test.yml"

    for obsolete_name in [
        "space-windows.zip",
        "space-windows-setup.exe",
    ]:
        assert_absent(test_workflow, obsolete_name, ".github/workflows/test.yml")


def test_linux_package_layout_verifier_workflow_callers_choose_layout_mode() -> None:
    workflow = read_repo_text(".github/workflows/build.yml")

    assert (
        'scripts/verify-linux-package-layout.sh --root /tmp/space-tarball-smoke --layout tarball --profile "${{ matrix.profile }}"'
        in workflow
    )
    assert (
        '/scripts/verify-linux-package-layout.sh --root /tmp/space-smoke --layout tarball --profile "${PROFILE}"'
        in workflow
    )
    assert (
        '/scripts/verify-linux-package-layout.sh --root /usr --layout package --profile "${PROFILE}"'
        in workflow
    )
    assert (
        workflow.count(
            '/scripts/verify-linux-package-layout.sh --root /usr --layout package --profile "${PROFILE}"'
        )
        == 2
    )


def test_windows_installer_default_basename_includes_architecture() -> None:
    helper = read_repo_text("scripts/build-windows-installer.py")

    assert 'default="space-windows-x86_64-setup"' in helper
    assert_absent(helper, 'default="space-windows-setup"', "scripts/build-windows-installer.py")


def test_release_docs_use_new_public_download_names() -> None:
    doc_files = [
        "docs/dev/building.md",
        "docs/user/quick-start.md",
    ]
    expected_public_names = [
        "space-linux-x86_64.tar.gz",
        "space-linux-x86_64-minimal.tar.gz",
        "space-linux-x86_64.AppImage",
        "space-linux-x86_64-minimal.AppImage",
        "space-linux-amd64.deb",
        "space-linux-amd64-minimal.deb",
        "space-linux-x86_64.rpm",
        "space-linux-x86_64-minimal.rpm",
        "space-windows-x86_64.zip",
        "space-windows-x86_64-setup.exe",
    ]
    obsolete_public_names = [
        "space-linux-x86_64-bin.tar.gz",
        "space-minimal-linux",
        "space-windows.zip",
        "space-windows-setup.exe",
    ]

    for doc_file in doc_files:
        text = read_repo_text(doc_file)

        for expected_name in expected_public_names:
            assert expected_name in text, f"{expected_name!r} missing from {doc_file}"

        for obsolete_name in obsolete_public_names:
            assert_absent(text, obsolete_name, doc_file)
