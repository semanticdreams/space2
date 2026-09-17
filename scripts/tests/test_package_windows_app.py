import importlib.util
import json
import zipfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PACKAGER = REPO_ROOT / "scripts" / "package-windows-app.py"


def load_packager():
    spec = importlib.util.spec_from_file_location("package_windows_app", PACKAGER)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_metadata(tmp_path: Path, *, entrypoint: str = "main") -> Path:
    assets = tmp_path / "app" / "assets"
    (assets / "lua").mkdir(parents=True)
    (assets / "lua" / "main.fnl").write_text("(fn main [] nil)\n", encoding="utf-8")
    metadata = {
        "app_name": "My Game",
        "app_id": "mygame",
        "entrypoint": entrypoint,
        "assets_dir": str(assets),
        "icon_path": None,
        "linux_profile": "full",
        "release_version": "v1.2.3",
        "package_version": "1.2.3",
        "space_version": "v9.8.7",
    }
    path = tmp_path / "metadata.json"
    path.write_text(json.dumps(metadata), encoding="utf-8")
    return path


def make_space_zip(tmp_path: Path) -> Path:
    runtime = tmp_path / "runtime"
    (runtime / "assets" / "lua").mkdir(parents=True)
    (runtime / "assets" / "pics").mkdir(parents=True)
    (runtime / "space.exe").write_text("space binary\n", encoding="utf-8")
    (runtime / "space-cli.exe").write_text("space cli\n", encoding="utf-8")
    (runtime / "SDL3.dll").write_text("dll\n", encoding="utf-8")
    (runtime / "assets" / "lua" / "space-runtime.fnl").write_text("runtime\n", encoding="utf-8")
    (runtime / "assets" / "pics" / "space.png").write_text("icon\n", encoding="utf-8")
    archive = tmp_path / "space-windows-x86_64.zip"
    with zipfile.ZipFile(archive, "w") as zip_file:
        for path in runtime.rglob("*"):
            zip_file.write(path, path.relative_to(runtime).as_posix())
    return archive


def test_zip_target_preserves_runtime_merges_app_assets_and_writes_cmd_launcher(tmp_path: Path) -> None:
    packager = load_packager()
    metadata_json = make_metadata(tmp_path, entrypoint="game.start")
    metadata = packager.load_metadata(metadata_json)
    output_dir = tmp_path / "out"

    artifacts = packager.package_windows_app(
        metadata,
        output_dir,
        ["zip"],
        make_space_zip(tmp_path),
    )

    assert artifacts == [output_dir / "mygame-windows-x86_64.zip"]
    assert (output_dir / "app-release-artifacts-windows.txt").read_text(encoding="utf-8") == (
        "mygame-windows-x86_64.zip\n"
    )
    with zipfile.ZipFile(artifacts[0]) as zip_file:
        names = set(zip_file.namelist())
        assert "space.exe" in names
        assert "space-cli.exe" in names
        assert "SDL3.dll" in names
        assert "assets/lua/space-runtime.fnl" in names
        assert "assets/pics/space.png" in names
        assert "assets/lua/main.fnl" in names
        launcher = zip_file.read("mygame.cmd").decode("utf-8")
    assert '"%~dp0space.exe" -m game.start %*' in launcher


def test_manifest_lists_zip_and_installer_stage_when_requested(tmp_path: Path) -> None:
    packager = load_packager()
    metadata = packager.load_metadata(make_metadata(tmp_path))
    output_dir = tmp_path / "out"

    artifacts = packager.package_windows_app(
        metadata,
        output_dir,
        ["zip", "installer-stage"],
        make_space_zip(tmp_path),
    )

    assert artifacts == [
        output_dir / "mygame-windows-x86_64.zip",
        output_dir / "installer-stage",
    ]
    assert (output_dir / "installer-stage" / "space.exe").is_file()
    assert (output_dir / "installer-stage" / "mygame.cmd").is_file()
    assert (output_dir / "app-release-artifacts-windows.txt").read_text(encoding="utf-8") == (
        "mygame-windows-x86_64.zip\nmygame-windows-x86_64-setup.exe\n"
    )


def test_invalid_entrypoint_fails_before_windows_runtime_staging(tmp_path: Path) -> None:
    packager = load_packager()
    metadata_json = make_metadata(tmp_path, entrypoint="main & del *")

    try:
        packager.load_metadata(metadata_json)
    except packager.MetadataError as error:
        assert "invalid entrypoint" in str(error)
    else:
        raise AssertionError("invalid entrypoint should fail before packaging")

    assert not (tmp_path / "out").exists()
