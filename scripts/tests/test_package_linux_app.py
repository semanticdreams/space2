import importlib.util
import json
import stat
import tarfile
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[2]
PACKAGER = REPO_ROOT / "scripts" / "package-linux-app.py"


def load_packager():
    spec = importlib.util.spec_from_file_location("package_linux_app", PACKAGER)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_metadata(
    tmp_path: Path,
    *,
    linux_profile: str = "full",
    release_version: str = "v1.2.3",
    space_version: str = "v9.8.7",
) -> Path:
    assets = tmp_path / "app" / "assets"
    (assets / "lua").mkdir(parents=True)
    (assets / "lua" / "main.fnl").write_text("(fn main [] nil)\n", encoding="utf-8")
    metadata = {
        "app_name": "My Game",
        "app_id": "mygame",
        "entrypoint": "main",
        "assets_dir": str(assets),
        "icon_path": None,
        "linux_profile": linux_profile,
        "release_version": release_version,
        "package_version": release_version.removeprefix("v"),
        "space_version": space_version,
    }
    path = tmp_path / "metadata.json"
    path.write_text(json.dumps(metadata), encoding="utf-8")
    return path


def make_space_tarball(tmp_path: Path) -> Path:
    root = tmp_path / "space-root"
    (root / "bin").mkdir(parents=True)
    (root / "share" / "space" / "assets" / "lua").mkdir(parents=True)
    (root / "bin" / "space").write_text("space binary\n", encoding="utf-8")
    (root / "share" / "space" / "assets" / "lua" / "main.fnl").write_text(
        "(print :space)\n", encoding="utf-8"
    )
    tarball = tmp_path / "space-linux-x86_64.tar.gz"
    with tarfile.open(tarball, "w:gz") as archive:
        for path in root.rglob("*"):
            archive.add(path, arcname=path.relative_to(root))
    return tarball


def assert_executable(path: Path) -> None:
    assert path.is_file()
    assert path.stat().st_mode & stat.S_IXUSR


def test_package_root_is_app_only_and_generates_space_dependency_metadata(tmp_path: Path) -> None:
    packager = load_packager()
    metadata = packager.load_metadata(make_metadata(tmp_path))
    root = tmp_path / "pkgroot"

    packager.stage_package_root(metadata, root)
    control_text = packager.deb_control_text(metadata)
    spec_text = packager.rpm_spec_text(metadata)

    assert_executable(root / "usr" / "bin" / "mygame")
    assert (root / "usr" / "share" / "mygame" / "assets" / "lua" / "main.fnl").is_file()
    assert (root / "usr" / "share" / "applications" / "mygame.desktop").is_file()
    assert not (root / "usr" / "share" / "space" / "assets").exists()
    launcher = (root / "usr" / "bin" / "mygame").read_text(encoding="utf-8")
    assert 'SPACE_ASSETS_PATH="/usr/share/mygame/assets${SPACE_ASSETS_PATH:+:$SPACE_ASSETS_PATH}" exec /usr/bin/space -m main "$@"' in launcher
    assert "Depends: space (>= 9.8.7)" in control_text
    assert "Requires: space >= 9.8.7" in spec_text


def test_package_version_uses_app_release_but_space_dependency_uses_pinned_space_version(tmp_path: Path) -> None:
    packager = load_packager()
    metadata = packager.load_metadata(
        make_metadata(tmp_path, release_version="v4.5.6", space_version="v1.2.3")
    )

    control_text = packager.deb_control_text(metadata)
    spec_text = packager.rpm_spec_text(metadata)

    assert "Version: 4.5.6\n" in control_text
    assert "Depends: space (>= 1.2.3)\n" in control_text
    assert "Version: 4.5.6\n" in spec_text
    assert "Requires: space >= 1.2.3\n" in spec_text


def test_unsafe_dependency_version_falls_back_to_unversioned_space_dependency(tmp_path: Path) -> None:
    packager = load_packager()
    metadata = packager.load_metadata(make_metadata(tmp_path, space_version="nightly-main"))

    assert "Depends: space\n" in packager.deb_control_text(metadata)
    assert "Requires: space\n" in packager.rpm_spec_text(metadata)


def test_tarball_extraction_does_not_require_python_311_filter_argument(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    packager = load_packager()
    metadata = packager.load_metadata(make_metadata(tmp_path))
    original_extractall = tarfile.TarFile.extractall

    def python_310_extractall(self, path=".", members=None, *, numeric_owner=False):
        return original_extractall(self, path=path, members=members, numeric_owner=numeric_owner)

    monkeypatch.setattr(tarfile.TarFile, "extractall", python_310_extractall)

    root = tmp_path / "tarroot"

    packager.stage_tarball_root(metadata, make_space_tarball(tmp_path), root)

    assert (root / "bin" / "space").is_file()


def test_tarball_root_preserves_space_files_and_prepends_app_assets(tmp_path: Path) -> None:
    packager = load_packager()
    metadata = packager.load_metadata(make_metadata(tmp_path))
    root = tmp_path / "tarroot"

    packager.stage_tarball_root(metadata, make_space_tarball(tmp_path), root)

    assert (root / "bin" / "space").read_text(encoding="utf-8") == "space binary\n"
    assert (root / "share" / "space" / "assets" / "lua" / "main.fnl").is_file()
    assert (root / "share" / "mygame" / "assets" / "lua" / "main.fnl").is_file()
    assert_executable(root / "mygame")
    launcher = (root / "mygame").read_text(encoding="utf-8")
    assert 'SPACE_ASSETS_PATH="${APP_DIR}/share/mygame/assets:${APP_DIR}/share/space/assets${SPACE_ASSETS_PATH:+:$SPACE_ASSETS_PATH}"' in launcher
    assert 'exec "${APP_DIR}/bin/space" -m main "$@"' in launcher


def test_artifact_names_include_profile_only_for_self_contained_outputs(tmp_path: Path) -> None:
    packager = load_packager()
    full = packager.load_metadata(make_metadata(tmp_path / "full", linux_profile="full"))
    minimal = packager.load_metadata(make_metadata(tmp_path / "minimal", linux_profile="minimal"))

    assert packager.artifact_name(full, "deb") == "mygame-linux-amd64.deb"
    assert packager.artifact_name(full, "rpm") == "mygame-linux-x86_64.rpm"
    assert packager.artifact_name(full, "tarball") == "mygame-linux-x86_64.tar.gz"
    assert packager.artifact_name(full, "appimage") == "mygame-linux-x86_64.AppImage"
    assert packager.artifact_name(minimal, "deb") == "mygame-linux-amd64.deb"
    assert packager.artifact_name(minimal, "rpm") == "mygame-linux-x86_64.rpm"
    assert packager.artifact_name(minimal, "tarball") == "mygame-linux-x86_64-minimal.tar.gz"
    assert packager.artifact_name(minimal, "appimage") == "mygame-linux-x86_64-minimal.AppImage"


def test_manifest_lists_built_artifacts(tmp_path: Path) -> None:
    packager = load_packager()
    output_dir = tmp_path / "out"
    artifacts = [output_dir / "mygame-linux-amd64.deb", output_dir / "mygame-linux-x86_64.tar.gz"]
    output_dir.mkdir()
    for artifact in artifacts:
        artifact.write_text("artifact\n", encoding="utf-8")

    manifest = packager.write_manifest(output_dir, artifacts)

    assert manifest.read_text(encoding="utf-8") == "mygame-linux-amd64.deb\nmygame-linux-x86_64.tar.gz\n"


def test_deb_build_forces_root_payload_ownership(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    packager = load_packager()
    metadata = packager.load_metadata(make_metadata(tmp_path))
    package_root = tmp_path / "pkgroot"
    output_dir = tmp_path / "out"
    output_dir.mkdir()
    packager.stage_package_root(metadata, package_root)
    commands: list[list[str]] = []

    monkeypatch.setattr(packager, "require_tool", lambda name: None)

    def fake_run(command: list[str], check: bool) -> None:
        commands.append(command)
        Path(command[-1]).write_text("deb\n", encoding="utf-8")

    monkeypatch.setattr(packager.subprocess, "run", fake_run)

    output = packager.build_deb(metadata, package_root, output_dir)

    assert output == output_dir / "mygame-linux-amd64.deb"
    assert commands == [
        ["dpkg-deb", "--root-owner-group", "--build", str(package_root), str(output)]
    ]


def test_appimage_target_delegates_to_build_appimage_and_records_manifest(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    packager = load_packager()
    metadata_json = make_metadata(tmp_path)
    metadata = packager.load_metadata(metadata_json)
    output_dir = tmp_path / "out"
    output_dir.mkdir()
    commands: list[list[str]] = []
    environments: list[dict[str, str]] = []

    def fake_run(command: list[str], check: bool, env: dict[str, str]) -> None:
        commands.append(command)
        environments.append(env)
        Path(env["SPACE_BUILD_DIR"]).mkdir(parents=True, exist_ok=True)
        (Path(env["SPACE_BUILD_DIR"]) / "mygame-v1.2.3-x86_64.AppImage").write_text(
            "appimage\n", encoding="utf-8"
        )

    monkeypatch.setattr(packager.subprocess, "run", fake_run)

    artifacts = packager.package_linux_app(metadata, output_dir, ["appimage"], make_space_tarball(tmp_path), metadata_json)

    assert artifacts == [output_dir / "mygame-linux-x86_64.AppImage"]
    assert (output_dir / "mygame-linux-x86_64.AppImage").read_text(encoding="utf-8") == "appimage\n"
    assert (output_dir / "app-release-artifacts-linux.txt").read_text(encoding="utf-8") == "mygame-linux-x86_64.AppImage\n"
    assert commands == [[str(REPO_ROOT / "scripts" / "build-appimage.sh")]]
    assert environments[0]["SPACE_APP_METADATA_JSON"] == str(metadata_json)
