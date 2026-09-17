from __future__ import annotations

import dataclasses
import json
import os
import re
from pathlib import Path


APP_ID_PATTERN = re.compile(r"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$")
ENTRYPOINT_PATTERN = re.compile(
    r"^[A-Za-z_][A-Za-z0-9_-]*(?:\.[A-Za-z_][A-Za-z0-9_-]*)*(?::[A-Za-z_][A-Za-z0-9_-]*)?$"
)


@dataclasses.dataclass(frozen=True)
class AppMetadata:
    app_name: str
    app_id: str
    entrypoint: str
    assets_dir: str
    icon_path: str | None
    linux_profile: str
    release_version: str
    package_version: str
    space_version: str

    def to_json_dict(self) -> dict[str, str | None]:
        return dataclasses.asdict(self)


class MetadataError(ValueError):
    pass


def derive_app_id(app_name: str) -> str:
    app_id = re.sub(r"[^a-z0-9]+", "-", app_name.lower()).strip("-")
    app_id = re.sub(r"-+", "-", app_id)
    if not app_id:
        raise MetadataError("unable to derive app-id from app-name")
    return app_id


def validate_app_id(app_id: str) -> None:
    if not APP_ID_PATTERN.fullmatch(app_id):
        raise MetadataError(
            "invalid app-id: use lowercase letters, digits, and single hyphen-separated words"
        )


def validate_entrypoint(entrypoint: str) -> None:
    if not ENTRYPOINT_PATTERN.fullmatch(entrypoint):
        raise MetadataError("invalid entrypoint: use a Space module or module:function string")


def normalize_package_version(release_version: str) -> str:
    if (
        release_version.startswith("v")
        and len(release_version) > 1
        and release_version[1].isdigit()
    ):
        return release_version[1:]
    return release_version


def ref_name_from_environment() -> str:
    ref_name = os.environ.get("GITHUB_REF_NAME", "")
    if ref_name:
        return ref_name

    github_ref = os.environ.get("GITHUB_REF", "")
    prefix = "refs/tags/"
    if github_ref.startswith(prefix):
        return github_ref[len(prefix) :]
    return ""


def resolve_existing_dir(repo_root: Path, relative_or_absolute: str, description: str) -> Path:
    path = Path(relative_or_absolute)
    if not path.is_absolute():
        path = repo_root / path
    path = path.resolve()
    if not path.is_dir():
        raise MetadataError(f"{description} does not exist: {path}")
    return path


def resolve_existing_file(repo_root: Path, relative_or_absolute: str, description: str) -> Path:
    path = Path(relative_or_absolute)
    if not path.is_absolute():
        path = repo_root / path
    path = path.resolve()
    if not path.is_file():
        raise MetadataError(f"{description} does not exist: {path}")
    return path


def normalize_metadata(
    *,
    repo_root: str | Path,
    space_version: str,
    app_name: str,
    app_id: str | None = None,
    entrypoint: str = "main",
    assets_dir: str = "assets",
    icon_path: str | None = None,
    linux_profile: str = "full",
    release_version: str | None = None,
    ref_name: str | None = None,
) -> AppMetadata:
    root = Path(repo_root).resolve()
    if not root.is_dir():
        raise MetadataError(f"repo root does not exist: {root}")

    normalized_app_id = app_id or derive_app_id(app_name)
    validate_app_id(normalized_app_id)
    validate_entrypoint(entrypoint)

    if linux_profile not in {"full", "minimal"}:
        raise MetadataError("linux-profile must be 'full' or 'minimal'")

    resolved_assets_dir = resolve_existing_dir(root, assets_dir, "assets directory")
    resolved_icon_path = None
    if icon_path:
        resolved_icon_path = str(resolve_existing_file(root, icon_path, "icon path"))

    normalized_release_version = release_version or ref_name or ref_name_from_environment()
    if not normalized_release_version:
        raise MetadataError("release-version is required when no tag/ref name is available")

    return AppMetadata(
        app_name=app_name,
        app_id=normalized_app_id,
        entrypoint=entrypoint,
        assets_dir=str(resolved_assets_dir),
        icon_path=resolved_icon_path,
        linux_profile=linux_profile,
        release_version=normalized_release_version,
        package_version=normalize_package_version(normalized_release_version),
        space_version=space_version,
    )


def write_metadata_json(metadata: AppMetadata, output_path: str | Path) -> Path:
    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(metadata.to_json_dict(), indent=2, sort_keys=True) + "\n"
    output.write_text(text, encoding="utf-8")
    return output
