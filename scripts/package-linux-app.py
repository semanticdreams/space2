#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from app_packaging import (  # noqa: E402
    AppMetadata,
    MetadataError,
    desktop_escape,
    linux_artifact_name,
    load_metadata_json,
    normalize_package_version,
    safe_copy_tree,
    safe_dependency_version,
    write_executable,
)


MANIFEST_NAME = "app-release-artifacts-linux.txt"
SUPPORTED_TARGETS = {"deb", "rpm", "tarball", "appimage"}


def load_metadata(path: str | Path) -> AppMetadata:
    return load_metadata_json(path)


def package_launcher_text(metadata: AppMetadata) -> str:
    return (
        "#!/usr/bin/env sh\n"
        "set -eu\n"
        f'SPACE_ASSETS_PATH="/usr/share/{metadata.app_id}/assets${{SPACE_ASSETS_PATH:+:$SPACE_ASSETS_PATH}}" '
        f'exec /usr/bin/space -m {metadata.entrypoint} "$@"\n'
    )


def tarball_launcher_text(metadata: AppMetadata) -> str:
    return (
        "#!/usr/bin/env sh\n"
        "set -eu\n"
        'APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)\n'
        f'SPACE_ASSETS_PATH="${{APP_DIR}}/share/{metadata.app_id}/assets:${{APP_DIR}}/share/space/assets${{SPACE_ASSETS_PATH:+:$SPACE_ASSETS_PATH}}"\n'
        "export SPACE_ASSETS_PATH\n"
        f'exec "${{APP_DIR}}/bin/space" -m {metadata.entrypoint} "$@"\n'
    )


def desktop_file_text(metadata: AppMetadata) -> str:
    return (
        "[Desktop Entry]\n"
        "Type=Application\n"
        f"Name={desktop_escape(metadata.app_name)}\n"
        f"Exec={desktop_escape(metadata.app_id)}\n"
        "Terminal=false\n"
        "Categories=Game;\n"
    )


def stage_package_root(metadata: AppMetadata, root: str | Path) -> Path:
    root_path = Path(root)
    if root_path.exists():
        shutil.rmtree(root_path)
    assets_destination = root_path / "usr" / "share" / metadata.app_id / "assets"
    safe_copy_tree(metadata.assets_dir, assets_destination)
    write_executable(root_path / "usr" / "bin" / metadata.app_id, package_launcher_text(metadata))
    desktop_path = root_path / "usr" / "share" / "applications" / f"{metadata.app_id}.desktop"
    desktop_path.parent.mkdir(parents=True, exist_ok=True)
    desktop_path.write_text(desktop_file_text(metadata), encoding="utf-8")
    return root_path


def _safe_extract_tarball(tarball: Path, root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    resolved_root = root.resolve()
    with tarfile.open(tarball, "r:gz") as archive:
        for member in archive.getmembers():
            _validate_tar_member(member, resolved_root)
        for member in archive.getmembers():
            _extract_tar_member(archive, member, root, resolved_root)


def _validate_tar_member(member: tarfile.TarInfo, resolved_root: Path) -> None:
    destination = (resolved_root / member.name).resolve()
    try:
        destination.relative_to(resolved_root)
    except ValueError as error:
        raise MetadataError(f"unsafe path in Space tarball: {member.name}") from error
    if member.issym() or member.islnk():
        link_base = destination.parent if member.issym() else resolved_root
        link_target = (link_base / member.linkname).resolve()
        try:
            link_target.relative_to(resolved_root)
        except ValueError as error:
            raise MetadataError(f"unsafe link in Space tarball: {member.name}") from error
    elif not (member.isdir() or member.isfile()):
        raise MetadataError(f"unsupported entry in Space tarball: {member.name}")


def _extract_tar_member(
    archive: tarfile.TarFile, member: tarfile.TarInfo, root: Path, resolved_root: Path
) -> None:
    destination = (resolved_root / member.name).resolve()
    if member.isdir():
        destination.mkdir(parents=True, exist_ok=True)
        destination.chmod(member.mode)
    elif member.isfile():
        destination.parent.mkdir(parents=True, exist_ok=True)
        source = archive.extractfile(member)
        if source is None:
            raise MetadataError(f"unable to read file from Space tarball: {member.name}")
        with source, destination.open("wb") as output:
            shutil.copyfileobj(source, output)
        destination.chmod(member.mode)
    elif member.issym():
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists() or destination.is_symlink():
            destination.unlink()
        os.symlink(member.linkname, destination)
    elif member.islnk():
        destination.parent.mkdir(parents=True, exist_ok=True)
        link_target = (resolved_root / member.linkname).resolve()
        if destination.exists() or destination.is_symlink():
            destination.unlink()
        os.link(link_target, destination)


def stage_tarball_root(metadata: AppMetadata, space_tarball: str | Path, root: str | Path) -> Path:
    root_path = Path(root)
    if root_path.exists():
        shutil.rmtree(root_path)
    tarball_path = Path(space_tarball)
    if not tarball_path.is_file():
        raise MetadataError(f"Space tarball does not exist: {tarball_path}")
    _safe_extract_tarball(tarball_path, root_path)
    safe_copy_tree(metadata.assets_dir, root_path / "share" / metadata.app_id / "assets")
    write_executable(root_path / metadata.app_id, tarball_launcher_text(metadata))
    return root_path


def dependency_text(metadata: AppMetadata, debian: bool) -> str:
    version = safe_dependency_version(normalize_package_version(metadata.space_version))
    if not version:
        return "space"
    if debian:
        return f"space (>= {version})"
    return f"space >= {version}"


def deb_control_text(metadata: AppMetadata) -> str:
    return (
        f"Package: {metadata.app_id}\n"
        f"Version: {metadata.package_version}\n"
        "Section: games\n"
        "Priority: optional\n"
        "Architecture: amd64\n"
        f"Depends: {dependency_text(metadata, debian=True)}\n"
        "Maintainer: Space App Packager <noreply@example.invalid>\n"
        f"Description: {metadata.app_name}\n"
    )


def rpm_spec_text(metadata: AppMetadata) -> str:
    return (
        f"Name: {metadata.app_id}\n"
        f"Version: {metadata.package_version}\n"
        "Release: 1%{?dist}\n"
        f"Summary: {metadata.app_name}\n"
        "License: Proprietary\n"
        "BuildArch: x86_64\n"
        f"Requires: {dependency_text(metadata, debian=False)}\n"
        "\n%description\n"
        f"{metadata.app_name}\n"
        "\n%files\n"
        f"/usr/bin/{metadata.app_id}\n"
        f"/usr/share/{metadata.app_id}\n"
        f"/usr/share/applications/{metadata.app_id}.desktop\n"
    )


def artifact_name(metadata: AppMetadata, target: str) -> str:
    return linux_artifact_name(metadata.app_id, target, metadata.linux_profile)


def require_tool(name: str) -> None:
    if shutil.which(name) is None:
        raise MetadataError(f"required tool not found: {name}")


def build_deb(metadata: AppMetadata, package_root: Path, output_dir: Path) -> Path:
    require_tool("dpkg-deb")
    debian_dir = package_root / "DEBIAN"
    debian_dir.mkdir(parents=True, exist_ok=True)
    (debian_dir / "control").write_text(deb_control_text(metadata), encoding="utf-8")
    output = output_dir / artifact_name(metadata, "deb")
    subprocess.run(
        ["dpkg-deb", "--root-owner-group", "--build", str(package_root), str(output)],
        check=True,
    )
    return output


def build_rpm(metadata: AppMetadata, package_root: Path, output_dir: Path) -> Path:
    require_tool("rpmbuild")
    with tempfile.TemporaryDirectory(prefix="space-app-rpmbuild-") as tmp:
        topdir = Path(tmp)
        for directory in ("BUILD", "BUILDROOT", "RPMS", "SOURCES", "SPECS", "SRPMS"):
            (topdir / directory).mkdir()
        spec_path = topdir / "SPECS" / f"{metadata.app_id}.spec"
        install_section = f"\n%install\nmkdir -p %{{buildroot}}\ncp -a {package_root}/usr %{{buildroot}}/\n"
        spec_path.write_text(
            rpm_spec_text(metadata).replace("\n%files\n", install_section + "\n%files\n", 1),
            encoding="utf-8",
        )
        subprocess.run(
            ["rpmbuild", "-bb", "--define", f"_topdir {topdir}", str(spec_path)],
            check=True,
        )
        output = output_dir / artifact_name(metadata, "rpm")
        built = next((topdir / "RPMS").glob("**/*.rpm"), None)
        if built is None:
            raise MetadataError("rpmbuild completed without producing an RPM")
        shutil.copy2(built, output)
        return output


def build_tarball(metadata: AppMetadata, tarball_root: Path, output_dir: Path) -> Path:
    output = output_dir / artifact_name(metadata, "tarball")
    with tarfile.open(output, "w:gz") as archive:
        for path in sorted(tarball_root.rglob("*")):
            archive.add(path, arcname=path.relative_to(tarball_root))
    return output


def build_appimage(metadata: AppMetadata, metadata_json: str | Path, runtime_root: Path, output_dir: Path) -> Path:
    build_dir = runtime_root.parent / "appimage-build"
    if build_dir.exists():
        shutil.rmtree(build_dir)
    build_dir.mkdir(parents=True)
    env = os.environ.copy()
    env.update(
        {
            "SPACE_APP_METADATA_JSON": str(metadata_json),
            "SPACE_INSTALL_PREFIX": str(runtime_root),
            "SPACE_BUILD_DIR": str(build_dir),
            "SPACE_APPIMAGE_BASENAME": metadata.app_id,
        }
    )
    subprocess.run([str(SCRIPT_DIR / "build-appimage.sh")], check=True, env=env)
    generated = sorted(build_dir.glob(f"{metadata.app_id}-*-x86_64.AppImage"))
    if not generated:
        raise MetadataError(f"build-appimage.sh completed without producing an AppImage in {build_dir}")
    output = output_dir / artifact_name(metadata, "appimage")
    shutil.copy2(generated[0], output)
    return output


def write_manifest(output_dir: str | Path, artifacts: list[Path]) -> Path:
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    for artifact in artifacts:
        if artifact.parent != output_path:
            raise MetadataError(f"artifact is outside output directory: {artifact}")
        if not artifact.is_file():
            raise MetadataError(f"artifact listed in manifest does not exist: {artifact}")
    manifest = output_path / MANIFEST_NAME
    manifest.write_text("".join(f"{artifact.name}\n" for artifact in artifacts), encoding="utf-8")
    return manifest


def parse_targets(value: str) -> list[str]:
    targets = [target.strip() for target in value.split(",") if target.strip()]
    unsupported = sorted(set(targets) - SUPPORTED_TARGETS)
    if unsupported:
        raise MetadataError(f"unsupported Linux package target: {', '.join(unsupported)}")
    if not targets:
        raise MetadataError("at least one target is required")
    return targets


def package_linux_app(
    metadata: AppMetadata,
    output_dir: str | Path,
    targets: list[str],
    space_tarball: str | Path,
    metadata_json: str | Path,
) -> list[Path]:
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    artifacts: list[Path] = []
    with tempfile.TemporaryDirectory(prefix="space-app-linux-") as tmp:
        tmp_path = Path(tmp)
        package_root = stage_package_root(metadata, tmp_path / "package-root")
        if "deb" in targets:
            artifacts.append(build_deb(metadata, package_root, output_path))
        if "rpm" in targets:
            artifacts.append(build_rpm(metadata, package_root, output_path))
        if "tarball" in targets:
            tarball_root = stage_tarball_root(metadata, space_tarball, tmp_path / "tarball-root")
            artifacts.append(build_tarball(metadata, tarball_root, output_path))
        if "appimage" in targets:
            appimage_root = tmp_path / "appimage-root"
            stage_tarball_root(metadata, space_tarball, appimage_root)
            shutil.rmtree(appimage_root / "share" / metadata.app_id, ignore_errors=True)
            appimage_launcher = appimage_root / metadata.app_id
            if appimage_launcher.exists():
                appimage_launcher.unlink()
            artifacts.append(build_appimage(metadata, metadata_json, appimage_root, output_path))
    write_manifest(output_path, artifacts)
    return artifacts


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Assemble Linux Space app packages.")
    parser.add_argument("--metadata-json", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--targets", required=True)
    parser.add_argument("--space-tarball", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        metadata = load_metadata(args.metadata_json)
        targets = parse_targets(args.targets)
        artifacts = package_linux_app(metadata, args.output_dir, targets, args.space_tarball, args.metadata_json)
    except (MetadataError, OSError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    for artifact in artifacts:
        print(artifact)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
