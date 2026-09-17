import os
import stat
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
VERIFY_SCRIPT = REPO_ROOT / "scripts" / "verify-app-package-layout.sh"


def make_executable(path: Path, content: str = "#!/usr/bin/env sh\nexit 0\n") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def make_package_root(root: Path) -> None:
    make_executable(
        root / "usr" / "bin" / "mygame",
        "#!/usr/bin/env sh\n"
        'SPACE_ASSETS_PATH="/usr/share/mygame/assets${SPACE_ASSETS_PATH:+:$SPACE_ASSETS_PATH}" exec /usr/bin/space -m main "$@"\n',
    )
    (root / "usr" / "share" / "mygame" / "assets" / "lua").mkdir(parents=True)
    (root / "usr" / "share" / "mygame" / "assets" / "lua" / "main.fnl").write_text(
        "(print :app)\n", encoding="utf-8"
    )
    (root / "usr" / "share" / "applications").mkdir(parents=True)
    (root / "usr" / "share" / "applications" / "mygame.desktop").write_text(
        "[Desktop Entry]\nExec=mygame\n", encoding="utf-8"
    )


def make_tarball_root(root: Path) -> None:
    make_executable(root / "bin" / "space")
    (root / "share" / "mygame" / "assets" / "lua").mkdir(parents=True)
    (root / "share" / "mygame" / "assets" / "lua" / "main.fnl").write_text(
        "(print :app)\n", encoding="utf-8"
    )
    (root / "share" / "space" / "assets" / "lua").mkdir(parents=True)
    (root / "share" / "space" / "assets" / "lua" / "main.fnl").write_text(
        "(print :space)\n", encoding="utf-8"
    )
    make_executable(
        root / "mygame",
        "#!/usr/bin/env sh\n"
        "SPACE_ASSETS_PATH=\"${APP_DIR}/share/mygame/assets:${APP_DIR}/share/space/assets${SPACE_ASSETS_PATH:+:$SPACE_ASSETS_PATH}\"\n"
        "exec \"${APP_DIR}/bin/space\" -m main \"$@\"\n",
    )


def run_verify(root: Path, layout: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            str(VERIFY_SCRIPT),
            "--root",
            str(root),
            "--layout",
            layout,
            "--app-id",
            "mygame",
            "--entrypoint",
            "main",
        ],
        cwd=REPO_ROOT,
        env=os.environ.copy(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def assert_failed_with(result: subprocess.CompletedProcess[str], expected: str) -> None:
    assert result.returncode != 0
    assert expected in result.stderr


def test_package_layout_passes_with_app_assets_launcher_and_desktop_file(tmp_path: Path) -> None:
    root = tmp_path / "root"
    make_package_root(root)

    result = run_verify(root, "package")

    assert result.returncode == 0, result.stderr


def test_package_layout_fails_when_space_assets_are_present(tmp_path: Path) -> None:
    root = tmp_path / "root"
    make_package_root(root)
    (root / "usr" / "share" / "space" / "assets").mkdir(parents=True)

    result = run_verify(root, "package")

    assert_failed_with(result, "unexpected bundled Space assets")


def test_tarball_layout_fails_when_bundled_space_binary_is_missing(tmp_path: Path) -> None:
    root = tmp_path / "root"
    make_tarball_root(root)
    (root / "bin" / "space").unlink()

    result = run_verify(root, "tarball")

    assert_failed_with(result, "missing executable bundled Space binary")


def test_tarball_layout_fails_when_app_assets_are_not_before_space_assets(tmp_path: Path) -> None:
    root = tmp_path / "root"
    make_tarball_root(root)
    (root / "mygame").write_text(
        "#!/usr/bin/env sh\n"
        "SPACE_ASSETS_PATH=\"${APP_DIR}/share/space/assets:${APP_DIR}/share/mygame/assets\"\n"
        "exec \"${APP_DIR}/bin/space\" -m main \"$@\"\n",
        encoding="utf-8",
    )

    result = run_verify(root, "tarball")

    assert_failed_with(result, "app assets must precede bundled Space assets")
