import importlib.util
import json
import sys
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[2]
HELPER = REPO_ROOT / "scripts" / "build-windows-installer.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("build_windows_installer", HELPER)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_cpack_build_dir(tmp_path: Path) -> Path:
    build_dir = tmp_path / "build"
    build_dir.mkdir()
    (build_dir / "CPackConfig.cmake").write_text(
        'set(CPACK_PACKAGE_NAME "Space")\n'
        'set(CPACK_PACKAGE_VERSION "9.8.7")\n'
        'set(CPACK_DEBIAN_PACKAGE_MAINTAINER "Space Team")\n',
        encoding="utf-8",
    )
    (build_dir / "space.ico").write_text("ico\n", encoding="utf-8")
    return build_dir


def make_dist_dir(tmp_path: Path) -> Path:
    dist_dir = tmp_path / "dist-runtime"
    dist_dir.mkdir()
    (dist_dir / "space.exe").write_text("space\n", encoding="utf-8")
    return dist_dir


def make_metadata(tmp_path: Path, *, icon_path: str | None = None) -> Path:
    tmp_path.mkdir(parents=True, exist_ok=True)
    assets = tmp_path / "assets"
    assets.mkdir()
    metadata = {
        "app_name": "My Game",
        "app_id": "mygame",
        "entrypoint": "game.main",
        "assets_dir": str(assets),
        "icon_path": icon_path,
        "linux_profile": "full",
        "release_version": "v1.2.3",
        "package_version": "1.2.3",
        "space_version": "v9.8.7",
    }
    path = tmp_path / "metadata.json"
    path.write_text(json.dumps(metadata), encoding="utf-8")
    return path


def run_helper(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, *args: str) -> list[str]:
    helper = load_helper()
    output_dir = tmp_path / "out"
    iss_path = tmp_path / "windows-installer.iss"
    iss_path.write_text("script\n", encoding="utf-8")
    command_seen: list[str] = []

    def fake_run(command: list[str], check: bool) -> None:
        nonlocal command_seen
        command_seen = command
        output_base = next(item.removeprefix("/DOutputBaseFilename=") for item in command if item.startswith("/DOutputBaseFilename="))
        output_dir.mkdir(parents=True, exist_ok=True)
        (output_dir / f"{output_base}.exe").write_text("installer\n", encoding="utf-8")

    monkeypatch.setattr(helper.subprocess, "run", fake_run)
    monkeypatch.setattr(sys, "argv", ["build-windows-installer.py", "--output-dir", str(output_dir), "--iss-path", str(iss_path), "--iscc-path", str(tmp_path / "ISCC.exe"), *args])
    (tmp_path / "ISCC.exe").write_text("iscc\n", encoding="utf-8")

    assert helper.main() == 0
    return command_seen


def define_value(command: list[str], name: str) -> str | None:
    prefix = f"/D{name}="
    for item in command:
        if item.startswith(prefix):
            return item[len(prefix) :]
    return None


def test_default_space_mode_uses_cpack_metadata_and_existing_basename(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    command = run_helper(
        tmp_path,
        monkeypatch,
        "--build-dir",
        str(make_cpack_build_dir(tmp_path)),
        "--dist-dir",
        str(make_dist_dir(tmp_path)),
    )

    assert define_value(command, "AppName") == "Space"
    assert define_value(command, "AppVersion") == "9.8.7"
    assert define_value(command, "AppPublisher") == "Space Team"
    assert define_value(command, "OutputBaseFilename") == "space-windows-x86_64-setup"
    assert define_value(command, "AppExeArgs") == ""
    assert define_value(command, "AppId") is None


def test_app_metadata_mode_uses_deterministic_app_id_and_entrypoint_args(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    command = run_helper(
        tmp_path,
        monkeypatch,
        "--metadata-json",
        str(make_metadata(tmp_path)),
        "--dist-dir",
        str(make_dist_dir(tmp_path)),
    )

    assert define_value(command, "AppName") == "My Game"
    assert define_value(command, "AppExeName") == "space.exe"
    assert define_value(command, "AppExeArgs") == "-m game.main"
    assert define_value(command, "AppDirName") == "mygame"
    assert define_value(command, "AppGroupName") == "My Game"
    assert define_value(command, "OutputBaseFilename") == "mygame-windows-x86_64-setup"
    first_app_id = define_value(command, "AppId")
    assert first_app_id is not None
    assert first_app_id.startswith("{{") and first_app_id.endswith("}}")

    second = run_helper(
        tmp_path / "again",
        monkeypatch,
        "--metadata-json",
        str(make_metadata(tmp_path / "again")),
        "--dist-dir",
        str(make_dist_dir(tmp_path / "again")),
    )
    assert define_value(second, "AppId") == first_app_id


def test_missing_app_icon_omits_setup_icon_define(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    command = run_helper(
        tmp_path,
        monkeypatch,
        "--metadata-json",
        str(make_metadata(tmp_path)),
        "--dist-dir",
        str(make_dist_dir(tmp_path)),
    )

    assert define_value(command, "AppIconFile") is None


def test_app_ico_is_used_directly_and_png_delegates_to_icon_generator(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    helper = load_helper()
    ico = tmp_path / "icon.ico"
    png = tmp_path / "icon.png"
    ico.write_text("ico\n", encoding="utf-8")
    png.write_text("png\n", encoding="utf-8")
    output_dir = tmp_path / "out"
    commands: list[list[str]] = []

    def fake_run(command: list[str], check: bool) -> None:
        commands.append(command)
        Path(command[-1]).write_text("generated ico\n", encoding="utf-8")

    monkeypatch.setattr(helper.subprocess, "run", fake_run)

    assert helper.resolve_app_icon(ico, output_dir) == ico
    converted = helper.resolve_app_icon(png, output_dir)

    assert converted == output_dir / "app.ico"
    assert commands == [[sys.executable, str(REPO_ROOT / "scripts" / "generate_windows_icon.py"), "--input", str(png), "--output", str(converted)]]


def test_iss_template_targets_space_exe_with_optional_app_args_and_optional_icon() -> None:
    text = (REPO_ROOT / "scripts" / "windows-installer.iss").read_text(encoding="utf-8")

    assert "#ifdef AppIconFile" in text
    assert "SetupIconFile={#AppIconFile}" in text
    assert "Parameters: \"{#AppExeArgs}\"" in text
    assert "Filename: \"{app}\\{#AppExeName}\"" in text
