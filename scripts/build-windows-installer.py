#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import pathlib
import re
import shutil
import subprocess
import sys
import uuid


def parse_args() -> argparse.Namespace:
    root_dir = pathlib.Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="Build the Windows installer with Inno Setup.")
    parser.add_argument("--root-dir", default=str(root_dir))
    parser.add_argument("--build-dir", default=None)
    parser.add_argument("--dist-dir", default=None)
    parser.add_argument("--output-dir", default=None)
    parser.add_argument("--iss-path", default=None)
    parser.add_argument("--metadata-json", default=None)
    parser.add_argument("--app-exe-name", default="space.exe")
    parser.add_argument("--output-basename", default="space-windows-x86_64-setup")
    parser.add_argument("--iscc-path", default=None)
    return parser.parse_args()


def require_file(path: pathlib.Path, description: str) -> pathlib.Path:
    if not path.is_file():
        raise SystemExit(f"Missing {description}: {path}")
    return path


def require_dir(path: pathlib.Path, description: str) -> pathlib.Path:
    if not path.is_dir():
        raise SystemExit(f"Missing {description}: {path}")
    return path


def parse_cpack_var(var_name: str, text: str) -> str:
    pattern = re.compile(rf'^set\({re.escape(var_name)}\s+"?([^\")]+)"?\)$', re.MULTILINE)
    match = pattern.search(text)
    return match.group(1) if match else ""


def resolve_iscc_path(explicit_path: str | None) -> pathlib.Path:
    candidates = []
    if explicit_path:
        candidates.append(pathlib.Path(explicit_path))

    which_path = shutil.which("ISCC.exe") or shutil.which("iscc")
    if which_path:
        candidates.append(pathlib.Path(which_path))

    for candidate in (
        pathlib.Path(r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe"),
        pathlib.Path(r"C:\Program Files\Inno Setup 6\ISCC.exe"),
    ):
        candidates.append(candidate)

    for candidate in candidates:
        if candidate.is_file():
            return candidate

    raise SystemExit("Unable to locate ISCC.exe. Install Inno Setup or pass --iscc-path.")


def deterministic_app_id(app_id: str) -> str:
    return "{{" + str(uuid.uuid5(uuid.NAMESPACE_URL, f"space-app:{app_id}")).upper() + "}}"


def resolve_app_icon(icon_path: str | pathlib.Path, output_dir: str | pathlib.Path) -> pathlib.Path:
    source = pathlib.Path(icon_path).resolve()
    if not source.is_file():
        raise SystemExit(f"Missing app icon: {source}")
    if source.suffix.lower() == ".ico":
        return source
    if source.suffix.lower() != ".png":
        raise SystemExit(f"Unsupported Windows app icon format: {source}")
    output = pathlib.Path(output_dir).resolve() / "app.ico"
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            sys.executable,
            str(pathlib.Path(__file__).resolve().parent / "generate_windows_icon.py"),
            "--input",
            str(source),
            "--output",
            str(output),
        ],
        check=True,
    )
    return output


def app_metadata_command_defines(metadata_json: pathlib.Path, output_dir: pathlib.Path) -> dict[str, str]:
    metadata = json.loads(metadata_json.read_text(encoding="utf-8"))
    required = ["app_name", "app_id", "entrypoint", "package_version"]
    missing = [key for key in required if not metadata.get(key)]
    if missing:
        raise SystemExit(f"Missing app metadata field(s): {', '.join(missing)}")
    defines = {
        "AppId": deterministic_app_id(str(metadata["app_id"])),
        "AppName": str(metadata["app_name"]),
        "AppVersion": str(metadata["package_version"]),
        "AppPublisher": str(metadata["app_name"]),
        "AppExeName": "space.exe",
        "AppExeArgs": f'-m {metadata["entrypoint"]}',
        "AppDirName": str(metadata["app_id"]),
        "AppGroupName": str(metadata["app_name"]),
        "OutputBaseFilename": f'{metadata["app_id"]}-windows-x86_64-setup',
    }
    icon_path = metadata.get("icon_path")
    if icon_path:
        defines["AppIconFile"] = str(resolve_app_icon(str(icon_path), output_dir))
    return defines


def space_command_defines(cpack_config: pathlib.Path, app_icon_path: pathlib.Path, app_exe_name: str, output_basename: str) -> dict[str, str]:
    require_file(cpack_config, "CPack config")
    require_file(app_icon_path, "generated Windows icon")
    cpack_text = cpack_config.read_text(encoding="utf-8")
    app_name = parse_cpack_var("CPACK_PACKAGE_NAME", cpack_text)
    app_version = parse_cpack_var("CPACK_PACKAGE_VERSION", cpack_text)
    app_publisher = parse_cpack_var("CPACK_DEBIAN_PACKAGE_MAINTAINER", cpack_text) or app_name
    if not app_name or not app_version:
        raise SystemExit(f"Failed to resolve package metadata from {cpack_config}")
    return {
        "AppName": app_name,
        "AppVersion": app_version,
        "AppPublisher": app_publisher,
        "AppExeName": app_exe_name,
        "AppExeArgs": "",
        "AppDirName": app_name,
        "AppGroupName": app_name,
        "OutputBaseFilename": output_basename,
        "AppIconFile": str(app_icon_path),
    }


def main() -> int:
    args = parse_args()
    root_dir = pathlib.Path(args.root_dir).resolve()
    build_dir = pathlib.Path(args.build_dir or root_dir / "build" / "windows").resolve()
    dist_dir = pathlib.Path(args.dist_dir or root_dir / "build" / "dist" / "windows").resolve()
    output_dir = pathlib.Path(args.output_dir or root_dir / "build" / "dist").resolve()
    iss_path = pathlib.Path(args.iss_path or root_dir / "scripts" / "windows-installer.iss").resolve()
    cpack_config = build_dir / "CPackConfig.cmake"
    app_icon_path = build_dir / "space.ico"

    require_dir(dist_dir, "packaged runtime directory")
    require_file(dist_dir / args.app_exe_name, "packaged Windows executable")
    require_file(iss_path, "Inno Setup script")
    output_dir.mkdir(parents=True, exist_ok=True)

    if args.metadata_json:
        defines = app_metadata_command_defines(pathlib.Path(args.metadata_json).resolve(), output_dir)
    else:
        require_dir(build_dir, "build directory")
        defines = space_command_defines(cpack_config, app_icon_path, args.app_exe_name, args.output_basename)

    iscc_path = resolve_iscc_path(args.iscc_path)
    command = [
        str(iscc_path),
        *[f"/D{name}={value}" for name, value in defines.items()],
        f"/DSourceDir={dist_dir}",
        f"/DOutputDir={output_dir}",
        str(iss_path),
    ]
    subprocess.run(command, check=True)

    installer_path = output_dir / f"{defines['OutputBaseFilename']}.exe"
    require_file(installer_path, "generated installer")
    print(installer_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
