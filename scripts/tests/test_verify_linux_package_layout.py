import os
import stat
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
VERIFY_SCRIPT = REPO_ROOT / "scripts" / "verify-linux-package-layout.sh"


def make_executable(path: Path, content: str = "#!/usr/bin/env sh\nexit 0\n") -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def make_minimal_root(root: Path) -> None:
    (root / "bin").mkdir(parents=True)
    (root / "lib").mkdir(parents=True)
    (root / "share" / "space" / "assets" / "lua").mkdir(parents=True)
    make_executable(root / "space")
    make_executable(root / "bin" / "space")
    (root / "share" / "space" / "assets" / "lua" / "main.fnl").write_text(
        "(print :ok)\n", encoding="utf-8"
    )
    (root / "lib" / "libSDL3.so.0").write_text("fake sdl\n", encoding="utf-8")


def make_minimal_package_root(root: Path) -> None:
    (root / "bin").mkdir(parents=True)
    (root / "share" / "space" / "assets" / "lua").mkdir(parents=True)
    make_executable(root / "bin" / "space")
    (root / "share" / "space" / "assets" / "lua" / "main.fnl").write_text(
        "(print :ok)\n", encoding="utf-8"
    )


def run_verify(
    root: Path,
    profile: str = "minimal",
    layout: str | None = "tarball",
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    command = [str(VERIFY_SCRIPT), "--root", str(root), "--profile", profile]
    if layout is not None:
        command.extend(["--layout", layout])

    return subprocess.run(
        command,
        cwd=REPO_ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def assert_failed_with(result: subprocess.CompletedProcess[str], expected: str) -> None:
    assert result.returncode != 0
    assert expected in result.stderr


def test_valid_minimal_install_tree_with_launcher_and_sdl3_passes(tmp_path: Path) -> None:
    root = tmp_path / "root"
    make_minimal_root(root)

    result = run_verify(root)

    assert result.returncode == 0, result.stderr


def test_package_layout_allows_distro_root_without_launcher_or_bundled_sdl3(
    tmp_path: Path,
) -> None:
    root = tmp_path / "usr"
    make_minimal_package_root(root)

    package_result = run_verify(root, layout="package")
    tarball_result = run_verify(root, layout="tarball")

    assert package_result.returncode == 0, package_result.stderr
    assert_failed_with(tarball_result, "missing executable top-level launcher")


def test_default_layout_preserves_package_root_callers(tmp_path: Path) -> None:
    root = tmp_path / "usr"
    make_minimal_package_root(root)

    result = run_verify(root, layout=None)

    assert result.returncode == 0, result.stderr


def test_missing_top_level_launcher_fails(tmp_path: Path) -> None:
    root = tmp_path / "root"
    make_minimal_root(root)
    (root / "space").unlink()

    result = run_verify(root)

    assert_failed_with(result, "missing executable top-level launcher")


def test_missing_lib_directory_fails_with_explicit_lib_error(tmp_path: Path) -> None:
    root = tmp_path / "root"
    make_minimal_root(root)
    (root / "lib" / "libSDL3.so.0").unlink()
    (root / "lib").rmdir()

    result = run_verify(root)

    assert_failed_with(result, "missing bundled library directory")


def test_missing_sdl3_runtime_fails_with_explicit_sdl3_error(tmp_path: Path) -> None:
    root = tmp_path / "root"
    make_minimal_root(root)
    (root / "lib" / "libSDL3.so.0").unlink()

    result = run_verify(root)

    assert_failed_with(result, "missing bundled SDL3 runtime library")


def test_full_profile_still_requires_cef_runtime_files(tmp_path: Path) -> None:
    root = tmp_path / "root"
    make_minimal_root(root)

    result = run_verify(root, profile="full")

    assert_failed_with(result, "missing executable CEF helper")


def test_matrix_library_required_when_space_binary_needs_it(tmp_path: Path) -> None:
    root = tmp_path / "root"
    make_minimal_root(root)
    fake_bin = tmp_path / "fake-bin"
    fake_bin.mkdir()
    make_executable(
        fake_bin / "readelf",
        "#!/usr/bin/env sh\n"
        "cat <<'EOF'\n"
        " 0x0000000000000001 (NEEDED)             Shared library: [libmatrix.so]\n"
        "EOF\n",
    )
    env = os.environ.copy()
    env["PATH"] = f"{fake_bin}{os.pathsep}{env.get('PATH', '')}"

    result = run_verify(root, env=env)

    assert_failed_with(result, "missing bundled Matrix runtime library")
