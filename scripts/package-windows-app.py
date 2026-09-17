#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from app_packaging import AppMetadata, MetadataError, load_metadata_json  # noqa: E402


MANIFEST_NAME = "app-release-artifacts-windows.txt"
SUPPORTED_TARGETS = {"zip", "installer-stage"}


def load_metadata(path: str | Path) -> AppMetadata:
    return load_metadata_json(path)


def artifact_name(metadata: AppMetadata, target: str) -> str:
    if target == "zip":
        return f"{metadata.app_id}-windows-x86_64.zip"
    if target == "installer":
        return f"{metadata.app_id}-windows-x86_64-setup.exe"
    raise MetadataError(f"unsupported Windows package target: {target}")


def cmd_launcher_text(metadata: AppMetadata) -> str:
    return f'@echo off\r\n"%~dp0space.exe" -m {metadata.entrypoint} %*\r\n'


def _ensure_safe_zip_member(root: Path, member_name: str) -> None:
    destination = (root / member_name).resolve()
    try:
        destination.relative_to(root.resolve())
    except ValueError as error:
        raise MetadataError(f"unsafe path in Space Windows ZIP: {member_name}") from error


def extract_space_zip(space_zip: str | Path, root: Path) -> None:
    archive_path = Path(space_zip)
    if not archive_path.is_file():
        raise MetadataError(f"Space Windows ZIP does not exist: {archive_path}")
    root.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive_path) as archive:
        for info in archive.infolist():
            _ensure_safe_zip_member(root, info.filename)
        archive.extractall(root)


def merge_assets(source: str | Path, destination: Path) -> None:
    src = Path(source)
    if not src.is_dir():
        raise MetadataError(f"source directory does not exist: {src}")
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src, destination, dirs_exist_ok=True, symlinks=True)


def stage_runtime(metadata: AppMetadata, space_zip: str | Path, root: str | Path) -> Path:
    root_path = Path(root)
    if root_path.exists():
        shutil.rmtree(root_path)
    extract_space_zip(space_zip, root_path)
    for required in ("space.exe", "space-cli.exe"):
        if not (root_path / required).is_file():
            raise MetadataError(f"Space Windows ZIP is missing {required}")
    merge_assets(metadata.assets_dir, root_path / "assets")
    (root_path / f"{metadata.app_id}.cmd").write_text(cmd_launcher_text(metadata), encoding="utf-8")
    return root_path


def build_zip(metadata: AppMetadata, staged_runtime: Path, output_dir: Path) -> Path:
    output = output_dir / artifact_name(metadata, "zip")
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(staged_runtime.rglob("*")):
            archive.write(path, path.relative_to(staged_runtime).as_posix())
    return output


def write_manifest(output_dir: str | Path, artifact_names: list[str]) -> Path:
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    manifest = output_path / MANIFEST_NAME
    manifest.write_text("".join(f"{artifact_name}\n" for artifact_name in artifact_names), encoding="utf-8")
    return manifest


def parse_targets(value: str) -> list[str]:
    targets = [target.strip() for target in value.split(",") if target.strip()]
    unsupported = sorted(set(targets) - SUPPORTED_TARGETS)
    if unsupported:
        raise MetadataError(f"unsupported Windows package target: {', '.join(unsupported)}")
    if not targets:
        raise MetadataError("at least one target is required")
    return targets


def package_windows_app(
    metadata: AppMetadata,
    output_dir: str | Path,
    targets: list[str],
    space_zip: str | Path,
) -> list[Path]:
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    artifacts: list[Path] = []
    manifest_entries: list[str] = []
    with tempfile.TemporaryDirectory(prefix="space-app-windows-") as tmp:
        staged_runtime = stage_runtime(metadata, space_zip, Path(tmp) / "runtime")
        if "zip" in targets:
            zip_artifact = build_zip(metadata, staged_runtime, output_path)
            artifacts.append(zip_artifact)
            manifest_entries.append(zip_artifact.name)
        if "installer-stage" in targets:
            installer_stage = output_path / "installer-stage"
            if installer_stage.exists():
                shutil.rmtree(installer_stage)
            shutil.copytree(staged_runtime, installer_stage, symlinks=True)
            artifacts.append(installer_stage)
            manifest_entries.append(artifact_name(metadata, "installer"))
    write_manifest(output_path, manifest_entries)
    return artifacts


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Assemble Windows Space app packages.")
    parser.add_argument("--metadata-json", required=True)
    parser.add_argument("--space-zip", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--targets", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        metadata = load_metadata(args.metadata_json)
        targets = parse_targets(args.targets)
        artifacts = package_windows_app(metadata, args.output_dir, targets, args.space_zip)
    except (MetadataError, OSError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    for artifact in artifacts:
        print(artifact)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
