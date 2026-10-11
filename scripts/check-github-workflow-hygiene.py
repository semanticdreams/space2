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


def top_level_block(text, block_name):
    match = re.search(rf"^{re.escape(block_name)}:\n(?P<body>(?:  .+\n|\n)+)", text, re.MULTILINE)
    return match.group("body") if match else ""


def require_exact_env(text, workflow_name, env_name, value, errors):
    if f"  {env_name}: {value}" not in text:
        fail(errors, f"{workflow_name}: {env_name} must be pinned to {value}")


def require_windows_routing(errors):
    test = read(".github/workflows/test.yml")
    for job_name in ("build-windows", "test-windows"):
        if f"{job_name}:" in test:
            fail(errors, f"test.yml: {job_name} must live in windows.yml, not test.yml")

    windows_path = WORKFLOWS / "windows.yml"
    if not windows_path.exists():
        fail(errors, "windows.yml: missing dedicated Windows workflow")
        return

    windows = windows_path.read_text(encoding="utf-8")
    for job_name in ("build-windows", "test-windows"):
        if f"{job_name}:" not in windows:
            fail(errors, f"windows.yml: missing {job_name} job")

    for trigger in ("pull_request:", "merge_group:", "schedule:", "cron:"):
        if trigger in windows:
            fail(errors, f"windows.yml: forbidden trigger or schedule entry {trigger}")

    if "workflow_dispatch:" not in windows:
        fail(errors, "windows.yml: missing workflow_dispatch trigger")

    on_block = top_level_block(windows, "on")
    trigger_names = set(re.findall(r"(?m)^  ([A-Za-z0-9_-]+):", on_block))
    expected_triggers = {"push", "workflow_dispatch"}
    if trigger_names != expected_triggers:
        found = ", ".join(sorted(trigger_names)) or "none"
        expected = ", ".join(sorted(expected_triggers))
        fail(errors, f"windows.yml: triggers must be exactly {expected}; found {found}")

    push_match = re.search(
        r"(?ms)^  push:\n(?P<body>(?:    .+\n|\n)*?)(?=^  \S|\Z)",
        on_block,
    )
    push_body = push_match.group("body") if push_match else ""
    branches_match = re.search(
        r"(?ms)^    branches:\n(?P<body>(?:      .+\n|\n)*?)(?=^    \S|^  \S|\Z)",
        push_body,
    )
    branch_body = branches_match.group("body") if branches_match else ""
    branches = re.findall(r"(?m)^      - (.+)$", branch_body)
    if branches != ["main"]:
        found = ", ".join(branches) or "none"
        fail(errors, f"windows.yml: push branches must be exactly main; found {found}")


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

    docs_pages = read(".github/workflows/docs-pages.yml")
    docs_permissions = top_level_block(docs_pages, "permissions")
    if "contents: read" not in docs_permissions:
        fail(errors, "docs-pages.yml: workflow permissions must default to contents: read")
    if "pages: write" in docs_permissions or "id-token: write" in docs_permissions:
        fail(errors, "docs-pages.yml: Pages deploy permissions must be scoped to deploy job")
    docs_deploy = workflow_job_block(docs_pages, "deploy")
    if "permissions:\n      pages: write\n      id-token: write" not in docs_deploy:
        fail(errors, "docs-pages.yml: deploy job must request pages: write and id-token: write")

    require_windows_routing(errors)

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print("GitHub workflow hygiene checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
