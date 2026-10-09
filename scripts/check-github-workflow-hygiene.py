#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"

EXPECTED_ACTION_MAJORS = {
    "actions/checkout": "v5",
    "actions/cache": "v5",
    "actions/github-script": "v8",
    "actions/upload-artifact": "v5",
    "actions/download-artifact": "v5",
}


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def fail(errors, message):
    errors.append(message)


def workflow_job_block(text, job_name):
    match = re.search(rf"^  {re.escape(job_name)}:\n(?P<body>(?:    .+\n|\n)+)", text, re.MULTILINE)
    return match.group("body") if match else ""


def require_exact_env(text, workflow_name, env_name, value, errors):
    if f"  {env_name}: {value}" not in text:
        fail(errors, f"{workflow_name}: {env_name} must be pinned to {value}")


def main():
    errors = []

    for path in sorted(WORKFLOWS.glob("*.yml")):
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)
        if "safe.directory '*'" in text or 'safe.directory "*"' in text:
            fail(errors, f"{rel}: wildcard safe.directory is forbidden")
        if "git config --global protocol.file.allow always" in text:
            fail(errors, f"{rel}: global file protocol allowance is forbidden")
        for action, major in EXPECTED_ACTION_MAJORS.items():
            for found in re.findall(rf"uses:\s*{re.escape(action)}@(v\d+)", text):
                if found != major:
                    fail(errors, f"{rel}: {action} uses {found}, expected {major}")

    devlog = read(".github/workflows/devlog-publish.yml")
    if "concurrency:\n  group: devlog-publish\n  cancel-in-progress: false" not in devlog:
        fail(errors, "devlog-publish.yml: missing serial devlog-publish concurrency")

    build = read(".github/workflows/build.yml")
    require_exact_env(build, "build.yml", "INNOSETUP_CHOCO_VERSION", "6.4.3", errors)
    if "choco install innosetup --version $env:INNOSETUP_CHOCO_VERSION" not in build:
        fail(errors, "build.yml: Inno Setup Chocolatey install must be pinned")
    build_publish = workflow_job_block(build, "publish-release")
    if build.count("uses: softprops/action-gh-release@v2") != 1 or "softprops/action-gh-release@v2" not in build_publish:
        fail(errors, "build.yml: release publishing must be centralized in publish-release")

    bundle = read(".github/workflows/bundle.yml")
    require_exact_env(bundle, "bundle.yml", "INNOSETUP_CHOCO_VERSION", "6.4.3", errors)
    require_exact_env(bundle, "bundle.yml", "PILLOW_VERSION", "11.3.0", errors)
    if "choco install innosetup --version $env:INNOSETUP_CHOCO_VERSION" not in bundle:
        fail(errors, "bundle.yml: Inno Setup Chocolatey install must be pinned")
    if "Pillow==$env:PILLOW_VERSION" not in bundle:
        fail(errors, "bundle.yml: Pillow install must be pinned")
    bundle_publish = workflow_job_block(bundle, "publish-release")
    if bundle.count("uses: softprops/action-gh-release@v2") != 1 or "softprops/action-gh-release@v2" not in bundle_publish:
        fail(errors, "bundle.yml: release publishing must be centralized in publish-release")

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print("GitHub workflow hygiene checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
