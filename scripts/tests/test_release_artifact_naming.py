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
