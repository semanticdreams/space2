import json
import os
import stat
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
BUILD_APPIMAGE = REPO_ROOT / "scripts" / "build-appimage.sh"


def write_metadata(tmp_path: Path, *, icon_path: Path | None = None) -> Path:
    assets = tmp_path / "app" / "assets"
    (assets / "lua").mkdir(parents=True)
    (assets / "lua" / "main.fnl").write_text("(fn main [] nil)\n", encoding="utf-8")
    metadata = {
        "app_name": "My Game",
        "app_id": "mygame",
        "entrypoint": "main",
        "assets_dir": str(assets),
        "icon_path": str(icon_path) if icon_path else None,
        "linux_profile": "full",
        "release_version": "v1.2.3",
        "package_version": "1.2.3",
        "space_version": "v9.8.7",
    }
    path = tmp_path / "metadata.json"
    path.write_text(json.dumps(metadata), encoding="utf-8")
    return path


def make_space_runtime(tmp_path: Path, *, with_space: bool = True, with_space_icon: bool = True) -> Path:
    runtime = tmp_path / "space-runtime"
    (runtime / "bin").mkdir(parents=True)
    (runtime / "share" / "space" / "assets" / "lua").mkdir(parents=True)
    (runtime / "share" / "space" / "assets" / "lua" / "main.fnl").write_text(
        "(print :space)\n", encoding="utf-8"
    )
    if with_space_icon:
        (runtime / "share" / "space" / "assets" / "pics").mkdir(parents=True)
        (runtime / "share" / "space" / "assets" / "pics" / "space.png").write_bytes(b"png")
    if with_space:
        space = runtime / "bin" / "space"
        space.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        space.chmod(space.stat().st_mode | stat.S_IXUSR)
    return runtime


def run_stage_only(tmp_path: Path, metadata_json: Path | None = None, runtime: Path | None = None) -> subprocess.CompletedProcess[str]:
    build_dir = tmp_path / "build"
    env = os.environ.copy()
    env.update(
        {
            "SPACE_BUILD_DIR": str(build_dir),
            "SPACE_APPIMAGE_STAGE_ONLY": "1",
        }
    )
    if metadata_json is not None:
        env["SPACE_APP_METADATA_JSON"] = str(metadata_json)
    if runtime is not None:
        env["SPACE_INSTALL_PREFIX"] = str(runtime)
    return subprocess.run(
        ["bash", str(BUILD_APPIMAGE)],
        cwd=REPO_ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def appdir(tmp_path: Path) -> Path:
    return tmp_path / "build" / "appimage" / "AppDir"


def test_default_space_mode_apprun_preserves_argument_forwarding_without_forced_entrypoint(tmp_path: Path) -> None:
    build_dir = tmp_path / "build"
    build_dir.mkdir()
    space = build_dir / "space"
    space.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    space.chmod(space.stat().st_mode | stat.S_IXUSR)

    result = run_stage_only(tmp_path)

    assert result.returncode == 0, result.stderr
    apprun = (appdir(tmp_path) / "AppRun").read_text(encoding="utf-8")
    assert 'exec "$HERE/usr/bin/space" "$@"' in apprun
    assert " -m " not in apprun


def test_app_mode_stages_app_assets_and_desktop_metadata(tmp_path: Path) -> None:
    metadata = write_metadata(tmp_path)
    runtime = make_space_runtime(tmp_path)

    result = run_stage_only(tmp_path, metadata, runtime)

    assert result.returncode == 0, result.stderr
    root = appdir(tmp_path)
    assert (root / "usr" / "share" / "mygame" / "assets" / "lua" / "main.fnl").is_file()
    desktop = (root / "usr" / "share" / "applications" / "mygame.desktop").read_text(encoding="utf-8")
    assert "Name=My Game\n" in desktop
    assert "Exec=mygame %U\n" in desktop
    assert "Icon=mygame\n" in desktop
    assert (root / "usr" / "share" / "icons" / "hicolor" / "256x256" / "apps" / "mygame.png").read_bytes() == b"png"


def test_app_mode_apprun_prepends_app_assets_before_bundled_space_assets(tmp_path: Path) -> None:
    metadata = write_metadata(tmp_path)
    runtime = make_space_runtime(tmp_path)

    result = run_stage_only(tmp_path, metadata, runtime)

    assert result.returncode == 0, result.stderr
    apprun = (appdir(tmp_path) / "AppRun").read_text(encoding="utf-8")
    assert 'SPACE_ASSETS_PATH="$HERE/usr/share/mygame/assets:$HERE/usr/share/space/assets' in apprun
    assert 'exec "$HERE/usr/bin/space" -m main "$@"' in apprun


def test_app_mode_fails_loudly_when_bundled_space_binary_is_missing(tmp_path: Path) -> None:
    metadata = write_metadata(tmp_path)
    runtime = make_space_runtime(tmp_path, with_space=False)

    result = run_stage_only(tmp_path, metadata, runtime)

    assert result.returncode != 0
    assert "bundled Space runtime is missing bin/space" in result.stderr


def test_app_mode_fails_when_no_app_icon_or_pinned_runtime_icon_exists(tmp_path: Path) -> None:
    metadata = write_metadata(tmp_path)
    runtime = make_space_runtime(tmp_path, with_space_icon=False)

    result = run_stage_only(tmp_path, metadata, runtime)

    assert result.returncode != 0
    assert "app mode requires either icon_path or bundled Space runtime icon" in result.stderr
