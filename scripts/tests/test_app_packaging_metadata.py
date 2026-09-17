import json
import os
import subprocess
import sys
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[2]
CLI = REPO_ROOT / "scripts" / "normalize-app-metadata.py"
sys.path.insert(0, str(REPO_ROOT / "scripts"))


def make_app_repo(tmp_path: Path) -> Path:
    repo = tmp_path / "mygame"
    (repo / "assets" / "lua").mkdir(parents=True)
    (repo / "assets" / "lua" / "main.fnl").write_text("(fn main [] nil)\n", encoding="utf-8")
    return repo


def run_cli(
    repo: Path,
    output: Path,
    *extra: str,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    command = [
        sys.executable,
        str(CLI),
        "--repo-root",
        str(repo),
        "--space-version",
        "v9.8.7",
        "--app-name",
        "My Game!",
        "--output",
        str(output),
    ]
    command.extend(extra)

    merged_env = os.environ.copy()
    if env is not None:
        merged_env.update(env)

    return subprocess.run(
        command,
        cwd=REPO_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=merged_env,
        check=False,
    )


def read_json(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def assert_cli_failed_with(result: subprocess.CompletedProcess[str], expected: str) -> None:
    assert result.returncode != 0
    assert expected in result.stderr


def test_cli_derives_app_id_defaults_and_package_version_from_ref(tmp_path: Path) -> None:
    repo = make_app_repo(tmp_path)
    output = tmp_path / "metadata.json"

    result = run_cli(repo, output, env={"GITHUB_REF_NAME": "v1.2.3"})

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == str(output)
    metadata = read_json(output)
    assert metadata == {
        "app_name": "My Game!",
        "app_id": "my-game",
        "entrypoint": "main",
        "assets_dir": str(repo / "assets"),
        "icon_path": None,
        "linux_profile": "full",
        "release_version": "v1.2.3",
        "package_version": "1.2.3",
        "space_version": "v9.8.7",
    }
    assert output.read_text(encoding="utf-8").endswith("\n")


def test_explicit_release_version_does_not_require_ref(tmp_path: Path) -> None:
    repo = make_app_repo(tmp_path)
    output = tmp_path / "metadata.json"

    result = run_cli(repo, output, "--release-version", "2026.09.17", env={"GITHUB_REF_NAME": ""})

    assert result.returncode == 0, result.stderr
    metadata = read_json(output)
    assert metadata["release_version"] == "2026.09.17"
    assert metadata["package_version"] == "2026.09.17"


@pytest.mark.parametrize(
    ("extra", "expected"),
    [
        (("--linux-profile", "tiny"), "linux-profile must be 'full' or 'minimal'"),
        (("--assets-dir", "missing-assets"), "assets directory does not exist"),
        (("--app-id", "Bad_ID"), "invalid app-id"),
        (("--entrypoint", "main;rm"), "invalid entrypoint"),
        (("--icon-path", "missing.png"), "icon path does not exist"),
    ],
)
def test_cli_fails_loudly_for_invalid_inputs(
    tmp_path: Path,
    extra: tuple[str, ...],
    expected: str,
) -> None:
    repo = make_app_repo(tmp_path)
    output = tmp_path / "metadata.json"

    result = run_cli(repo, output, *extra, env={"GITHUB_REF_NAME": "v1.2.3"})

    assert_cli_failed_with(result, expected)
    assert not output.exists()


def test_release_version_requires_explicit_value_or_ref_name(tmp_path: Path) -> None:
    repo = make_app_repo(tmp_path)
    output = tmp_path / "metadata.json"

    result = run_cli(repo, output, env={"GITHUB_REF_NAME": "", "GITHUB_REF": ""})

    assert_cli_failed_with(result, "release-version is required when no tag/ref name is available")


@pytest.mark.parametrize(
    ("extra", "app_name"),
    [
        (("--app-id", "space"), "My Game!"),
        ((), "Space"),
    ],
)
def test_space_app_id_is_reserved_and_fails_before_packaging(
    tmp_path: Path,
    extra: tuple[str, ...],
    app_name: str,
) -> None:
    repo = make_app_repo(tmp_path)
    output = tmp_path / "metadata.json"
    command = [
        sys.executable,
        str(CLI),
        "--repo-root",
        str(repo),
        "--space-version",
        "v9.8.7",
        "--app-name",
        app_name,
        "--output",
        str(output),
        *extra,
    ]

    result = subprocess.run(
        command,
        cwd=REPO_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env={**os.environ, "GITHUB_REF_NAME": "v1.2.3"},
        check=False,
    )

    assert_cli_failed_with(result, "reserved app-id")
    assert not output.exists()


@pytest.mark.parametrize(
    ("extra", "expected"),
    [
        (("--assets-dir", ".."), "assets directory must be inside repo root"),
        (("--assets-dir", "/tmp"), "assets directory must be inside repo root"),
    ],
)
def test_assets_dir_must_remain_inside_repo_root(
    tmp_path: Path,
    extra: tuple[str, ...],
    expected: str,
) -> None:
    repo = make_app_repo(tmp_path)
    output = tmp_path / "metadata.json"

    result = run_cli(repo, output, *extra, env={"GITHUB_REF_NAME": "v1.2.3"})

    assert_cli_failed_with(result, expected)
    assert not output.exists()


@pytest.mark.parametrize(
    ("icon_path", "expected"),
    [
        ("../icon.png", "icon path must be inside repo root"),
        ("__absolute_outside_icon__", "icon path must be inside repo root"),
    ],
)
def test_icon_path_must_remain_inside_repo_root(
    tmp_path: Path,
    icon_path: str,
    expected: str,
) -> None:
    repo = make_app_repo(tmp_path)
    (tmp_path / "icon.png").write_text("outside icon\n", encoding="utf-8")
    if icon_path == "__absolute_outside_icon__":
        icon_path = str(tmp_path / "icon.png")
    output = tmp_path / "metadata.json"

    result = run_cli(
        repo,
        output,
        "--icon-path",
        icon_path,
        env={"GITHUB_REF_NAME": "v1.2.3"},
    )

    assert_cli_failed_with(result, expected)
    assert not output.exists()


def test_normalizer_does_not_read_space_app_json(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    repo = make_app_repo(tmp_path)
    (repo / "space-app.json").write_text("not json", encoding="utf-8")
    output = tmp_path / "metadata.json"

    real_read_text = Path.read_text

    def fail_on_space_app_json(self: Path, *args: object, **kwargs: object) -> str:
        if self.name == "space-app.json":
            raise AssertionError("normalizer must not read space-app.json")
        return real_read_text(self, *args, **kwargs)

    monkeypatch.setattr(Path, "read_text", fail_on_space_app_json)

    from app_packaging import normalize_metadata, write_metadata_json

    metadata = normalize_metadata(
        repo_root=repo,
        space_version="v9.8.7",
        app_name="My Game!",
        ref_name="v1.2.3",
    )
    write_metadata_json(metadata, output)

    assert read_json(output)["app_id"] == "my-game"
    assert callable(write_metadata_json)
