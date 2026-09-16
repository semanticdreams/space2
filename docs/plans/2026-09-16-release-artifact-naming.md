# Release Artifact Naming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Standardize release-facing artifact names across Linux packaging, Windows packaging, release workflow checks, and download documentation.

**Architecture:** Keep naming responsibility in the existing release authorities: `scripts/build-linux.sh` constructs Linux stable names and manifests, `.github/workflows/build.yml` names workflow-produced Windows artifacts and validates upload paths, and `scripts/build-windows-installer.py` supplies the default installer basename. Add focused static pytest coverage for release-facing names so the naming grammar is checked without running heavyweight packaging jobs.

**Tech Stack:** Bash, GitHub Actions YAML, Python 3, pytest, Markdown documentation.

## Global Constraints

- Use the stable hierarchy grammar: `space-<os>-<arch>[-<role>][-<variant>].<ext>`.
- The full profile omits a variant token.
- The minimal profile appends `-minimal` after any role token and before the extension.
- Role tokens describe artifact purpose when the extension is not enough; the Windows installer keeps `setup` as its role token.
- Linux tarball names must become `space-linux-x86_64.tar.gz` and `space-linux-x86_64-minimal.tar.gz`.
- AppImage names must become `space-linux-x86_64.AppImage` and `space-linux-x86_64-minimal.AppImage`.
- DEB names must become `space-linux-amd64.deb` and `space-linux-amd64-minimal.deb`.
- RPM names must become `space-linux-x86_64.rpm` and `space-linux-x86_64-minimal.rpm`.
- Windows ZIP name must become `space-windows-x86_64.zip`.
- Windows installer name must become `space-windows-x86_64-setup.exe`.
- Do not publish duplicate compatibility artifacts with the old names.
- Do not change package contents, installation behavior, signing behavior, or version calculation.
- Do not rename internal CI-only artifact names unless they are release-facing or required by the packaging data flow.
- Missing or stale artifact names must continue to fail loudly in workflow smoke checks and upload steps.
- The committed design spec is `docs/specs/2026-09-16-release-artifact-naming-design.md`; old names may remain there as historical context.

## Acceptance Criteria

- `scripts/build-linux.sh` writes full-profile release manifest entries for `build/dist/space-linux-x86_64.tar.gz`, `build/space-linux-x86_64.AppImage`, `build/space-linux-amd64.deb`, and `build/space-linux-x86_64.rpm`.
- `scripts/build-linux.sh` writes minimal-profile release manifest entries for `build/dist/space-linux-x86_64-minimal.tar.gz`, `build/space-linux-x86_64-minimal.AppImage`, `build/space-linux-amd64-minimal.deb`, and `build/space-linux-x86_64-minimal.rpm`.
- Flavored Linux package outputs put the flavor after the architecture and before the optional variant, for example `space-linux-amd64-ubuntu-24.04.deb` and `space-linux-amd64-ubuntu-24.04-minimal.deb`.
- `.github/workflows/build.yml` smoke checks and release uploads reference only the new release-facing names.
- `scripts/build-windows-installer.py` defaults to `space-windows-x86_64-setup`.
- `docs/dev/building.md` and `docs/user/quick-start.md` use only the new release-facing download names.
- Targeted search finds no old release-facing names in implementation, workflow, or release documentation files.

## Validation Ladder

1. Focused task checks:
   - `python3 -m pytest scripts/tests/test_release_artifact_naming.py -v`
   - `bash -n scripts/build-linux.sh`
   - `python3 -m py_compile scripts/build-windows-installer.py`
2. Complete relevant local suite for this naming surface:
   - `python3 -m pytest scripts/tests/test_release_artifact_naming.py scripts/tests/test_makefile_build_workflow.py -v`
3. Static old-name search:
   - `rg 'space-minimal-linux|-bin\.tar\.gz|space-windows\.zip|space-windows-setup\.exe' scripts/build-linux.sh .github/workflows/build.yml scripts/build-windows-installer.py docs/dev/building.md docs/user/quick-start.md`
   - Expected: no matches. `rg` exits 1 when no matches are found; that exit code is acceptable for this check.
4. Release-packaging integration gate:
   - PR CI is the full integration gate.
   - The next tag-triggered release workflow is the artifact-production gate for the changed release names.

## Out of Scope

- Compatibility copies or aliases with old artifact names.
- Package contents, install layout, signing, version calculation, CPack metadata, or runtime code.
- Windows minimal artifacts.
- Broad refactors of release packaging beyond local name construction cleanup.

---

### Task 1: Linux stable artifact names

**Files:**
- Create: `scripts/tests/test_release_artifact_naming.py`
- Modify: `scripts/build-linux.sh`
- Test: `scripts/tests/test_release_artifact_naming.py`

**Interfaces:**
- Consumes: Existing `scripts/build-linux.sh` arguments `--profile`, `--deb-flavor`, `--rpm-flavor`, and existing manifest variable `RELEASE_MANIFEST`.
- Produces: Bash variables `VARIANT_SUFFIX`, `DEB_FLAVOR_SUFFIX`, `RPM_FLAVOR_SUFFIX`, `BIN_TAR_NAME`, `STABLE_APPIMAGE_NAME`, `STABLE_DEB_NAME`, and `STABLE_RPM_NAME` using the stable hierarchy grammar.

- [ ] **Step 1: Add the failing Linux naming test**

Create `scripts/tests/test_release_artifact_naming.py` with:

```python
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def read_repo_text(relative_path: str) -> str:
    return (REPO_ROOT / relative_path).read_text(encoding="utf-8")


def assert_absent(text: str, unexpected: str, source: str) -> None:
    assert unexpected not in text, f"{unexpected!r} must not appear in {source}"


def test_linux_packaging_names_follow_stable_hierarchy() -> None:
    script = read_repo_text("scripts/build-linux.sh")

    required_fragments = [
        'VARIANT_SUFFIX=""',
        'VARIANT_SUFFIX="-minimal"',
        'DEB_FLAVOR_SUFFIX=""',
        'RPM_FLAVOR_SUFFIX=""',
        'DEB_FLAVOR_SUFFIX="-${DEB_FLAVOR}"',
        'RPM_FLAVOR_SUFFIX="-${RPM_FLAVOR}"',
        'BIN_TAR_NAME="space-linux-x86_64${VARIANT_SUFFIX}.tar.gz"',
        'STABLE_APPIMAGE_NAME="space-linux-x86_64${VARIANT_SUFFIX}.AppImage"',
        'STABLE_DEB_NAME="space-linux-amd64${DEB_FLAVOR_SUFFIX}${VARIANT_SUFFIX}.deb"',
        'STABLE_RPM_NAME="space-linux-x86_64${RPM_FLAVOR_SUFFIX}${VARIANT_SUFFIX}.rpm"',
    ]

    for fragment in required_fragments:
        assert fragment in script

    assert_absent(script, "space-linux-x86_64-bin.tar.gz", "scripts/build-linux.sh")
    assert_absent(script, "space-minimal-linux", "scripts/build-linux.sh")
```

- [ ] **Step 2: Run the test and verify it fails for the current old names**

Run:

```bash
python3 -m pytest scripts/tests/test_release_artifact_naming.py::test_linux_packaging_names_follow_stable_hierarchy -v
```

Expected: FAIL because `scripts/build-linux.sh` still contains `space-linux-x86_64-bin.tar.gz` and `space-minimal-linux-*` stable names.

- [ ] **Step 3: Replace duplicated Linux name branches with grammar-based construction**

In `scripts/build-linux.sh`, replace the existing full/minimal branch that sets `BIN_TAR_NAME`, `APPIMAGE_BASE`, `STABLE_APPIMAGE_NAME`, `STABLE_DEB_NAME`, and `STABLE_RPM_NAME` with:

```bash
VARIANT_SUFFIX=""
APPIMAGE_BASE="space"
if [[ "${PROFILE}" == "minimal" ]]; then
    VARIANT_SUFFIX="-minimal"
    APPIMAGE_BASE="space-minimal"
fi

DEB_FLAVOR_SUFFIX=""
RPM_FLAVOR_SUFFIX=""
if [[ -n "${DEB_FLAVOR}" ]]; then
    DEB_FLAVOR_SUFFIX="-${DEB_FLAVOR}"
fi
if [[ -n "${RPM_FLAVOR}" ]]; then
    RPM_FLAVOR_SUFFIX="-${RPM_FLAVOR}"
fi

BIN_TAR_NAME="space-linux-x86_64${VARIANT_SUFFIX}.tar.gz"
STABLE_APPIMAGE_NAME="space-linux-x86_64${VARIANT_SUFFIX}.AppImage"
STABLE_DEB_NAME="space-linux-amd64${DEB_FLAVOR_SUFFIX}${VARIANT_SUFFIX}.deb"
STABLE_RPM_NAME="space-linux-x86_64${RPM_FLAVOR_SUFFIX}${VARIANT_SUFFIX}.rpm"
```

Keep `APPIMAGE_BASE="space-minimal"` for the minimal internal AppImage intermediate because `scripts/build-appimage.sh` still produces versioned intermediate names from `SPACE_APPIMAGE_BASENAME`; only the copied stable release name changes.

- [ ] **Step 4: Run focused Linux script validation**

Run:

```bash
bash -n scripts/build-linux.sh
python3 -m pytest scripts/tests/test_release_artifact_naming.py::test_linux_packaging_names_follow_stable_hierarchy -v
rg 'space-minimal-linux|-bin\.tar\.gz' scripts/build-linux.sh
```

Expected: `bash -n` passes, pytest passes, and `rg` finds no matches. The no-match `rg` exit code 1 is acceptable.

- [ ] **Step 5: Commit Task 1**

```bash
git add scripts/build-linux.sh scripts/tests/test_release_artifact_naming.py
git commit -m "fix(scripts): standardize linux release artifact names"
```

---

### Task 2: Workflow and Windows artifact names

**Files:**
- Modify: `scripts/tests/test_release_artifact_naming.py`
- Modify: `.github/workflows/build.yml`
- Modify: `scripts/build-windows-installer.py`
- Test: `scripts/tests/test_release_artifact_naming.py`

**Interfaces:**
- Consumes: Task 1 helpers `read_repo_text(relative_path: str) -> str` and `assert_absent(text: str, unexpected: str, source: str) -> None`.
- Produces: Workflow paths for `space-windows-x86_64.zip`, `space-windows-x86_64-setup.exe`, and the new Linux smoke-check artifact names.

- [ ] **Step 1: Add failing workflow and Windows installer naming tests**

Append to `scripts/tests/test_release_artifact_naming.py`:

```python
def test_workflow_uses_new_release_artifact_names() -> None:
    workflow = read_repo_text(".github/workflows/build.yml")

    expected_names = [
        "space-linux-x86_64.tar.gz",
        "space-linux-x86_64-minimal.tar.gz",
        "space-linux-amd64.deb",
        "space-linux-amd64-minimal.deb",
        "space-linux-x86_64.rpm",
        "space-linux-x86_64-minimal.rpm",
        "space-windows-x86_64.zip",
        "space-windows-x86_64-setup.exe",
    ]

    for expected_name in expected_names:
        assert expected_name in workflow

    for obsolete_name in [
        "space-linux-x86_64-bin.tar.gz",
        "space-minimal-linux",
        "space-windows.zip",
        "space-windows-setup.exe",
    ]:
        assert_absent(workflow, obsolete_name, ".github/workflows/build.yml")


def test_windows_installer_default_basename_includes_architecture() -> None:
    helper = read_repo_text("scripts/build-windows-installer.py")

    assert 'default="space-windows-x86_64-setup"' in helper
    assert_absent(helper, 'default="space-windows-setup"', "scripts/build-windows-installer.py")
```

- [ ] **Step 2: Run the new tests and verify they fail**

Run:

```bash
python3 -m pytest \
  scripts/tests/test_release_artifact_naming.py::test_workflow_uses_new_release_artifact_names \
  scripts/tests/test_release_artifact_naming.py::test_windows_installer_default_basename_includes_architecture \
  -v
```

Expected: FAIL because the workflow and installer helper still reference old Windows names and old Linux minimal/tarball names.

- [ ] **Step 3: Update Linux artifact references in `.github/workflows/build.yml`**

Replace workflow references as follows:

```text
build/dist/space-linux-x86_64-bin.tar.gz -> build/dist/space-linux-x86_64.tar.gz
build/dist/space-minimal-linux-x86_64-bin.tar.gz -> build/dist/space-linux-x86_64-minimal.tar.gz
space-linux-x86_64-bin.tar.gz -> space-linux-x86_64.tar.gz
space-minimal-linux-x86_64-bin.tar.gz -> space-linux-x86_64-minimal.tar.gz
space-minimal-linux-amd64.deb -> space-linux-amd64-minimal.deb
space-minimal-linux-x86_64.rpm -> space-linux-x86_64-minimal.rpm
```

Do not change workflow logic or smoke-test behavior beyond expected paths.

- [ ] **Step 4: Update Windows ZIP creation, artifact staging, smoke test, and release upload paths**

In `.github/workflows/build.yml`, replace release-facing Windows paths:

```text
build/dist/space-windows.zip -> build/dist/space-windows-x86_64.zip
build/dist/space-windows-setup.exe -> build/dist/space-windows-x86_64-setup.exe
```

This includes Python `zipfile.ZipFile(...)` output, `actions/upload-artifact` packaging input paths, PowerShell installer smoke-test paths, and `softprops/action-gh-release` files lists. Do not rename the internal CI artifact named `windows-packaging-inputs`.

- [ ] **Step 5: Update the Windows installer helper default basename**

In `scripts/build-windows-installer.py`, change:

```python
parser.add_argument("--output-basename", default="space-windows-setup")
```

to:

```python
parser.add_argument("--output-basename", default="space-windows-x86_64-setup")
```

- [ ] **Step 6: Run focused workflow and helper validation**

Run:

```bash
python3 -m py_compile scripts/build-windows-installer.py
python3 -m pytest scripts/tests/test_release_artifact_naming.py -v
rg 'space-minimal-linux|-bin\.tar\.gz|space-windows\.zip|space-windows-setup\.exe' .github/workflows/build.yml scripts/build-windows-installer.py
```

Expected: Python compile passes, pytest passes, and `rg` finds no matches. The no-match `rg` exit code 1 is acceptable.

- [ ] **Step 7: Commit Task 2**

```bash
git add .github/workflows/build.yml scripts/build-windows-installer.py scripts/tests/test_release_artifact_naming.py
git commit -m "fix(ci): publish architecture-qualified release artifacts"
```

---

### Task 3: Release documentation names

**Files:**
- Modify: `scripts/tests/test_release_artifact_naming.py`
- Modify: `docs/dev/building.md`
- Modify: `docs/user/quick-start.md`
- Test: `scripts/tests/test_release_artifact_naming.py`

**Interfaces:**
- Consumes: Task 1 helpers `read_repo_text(relative_path: str) -> str` and `assert_absent(text: str, unexpected: str, source: str) -> None`.
- Produces: Updated developer and user download documentation using the new artifact grammar.

- [ ] **Step 1: Add failing documentation naming tests**

Append to `scripts/tests/test_release_artifact_naming.py`:

```python
def test_release_docs_use_new_public_download_names() -> None:
    doc_files = [
        "docs/dev/building.md",
        "docs/user/quick-start.md",
    ]
    expected_public_names = [
        "space-linux-x86_64.tar.gz",
        "space-linux-x86_64-minimal.tar.gz",
        "space-linux-x86_64.AppImage",
        "space-linux-x86_64-minimal.AppImage",
        "space-linux-amd64.deb",
        "space-linux-amd64-minimal.deb",
        "space-linux-x86_64.rpm",
        "space-linux-x86_64-minimal.rpm",
        "space-windows-x86_64.zip",
        "space-windows-x86_64-setup.exe",
    ]
    obsolete_public_names = [
        "space-linux-x86_64-bin.tar.gz",
        "space-minimal-linux",
        "space-windows.zip",
        "space-windows-setup.exe",
    ]

    for doc_file in doc_files:
        text = read_repo_text(doc_file)

        for expected_name in expected_public_names:
            assert expected_name in text, f"{expected_name!r} missing from {doc_file}"

        for obsolete_name in obsolete_public_names:
            assert_absent(text, obsolete_name, doc_file)
```

- [ ] **Step 2: Run the documentation test and verify it fails**

Run:

```bash
python3 -m pytest scripts/tests/test_release_artifact_naming.py::test_release_docs_use_new_public_download_names -v
```

Expected: FAIL because both docs still contain old Windows names, old `-bin` tarball names, and old `space-minimal-linux-*` names.

- [ ] **Step 3: Update direct download lists in both docs**

In `docs/dev/building.md` and `docs/user/quick-start.md`, update direct download link text and URLs to these artifact names:

```markdown
- Windows installer (.exe): `space-windows-x86_64-setup.exe`
- Windows (.zip): `space-windows-x86_64.zip`
- AppImage: `space-linux-x86_64.AppImage`
- Debian/Ubuntu (.deb): `space-linux-amd64.deb`
- Fedora/openSUSE Tumbleweed (.rpm): `space-linux-x86_64.rpm`
- Tarball (.tar.gz): `space-linux-x86_64.tar.gz`
- Minimal AppImage: `space-linux-x86_64-minimal.AppImage`
- Minimal Debian/Ubuntu (.deb): `space-linux-amd64-minimal.deb`
- Minimal Fedora/openSUSE Tumbleweed (.rpm): `space-linux-x86_64-minimal.rpm`
- Minimal Tarball (.tar.gz): `space-linux-x86_64-minimal.tar.gz`
```

Keep the existing release URL prefix in each link and change only the filename segments.

- [ ] **Step 4: Update Windows install guidance in both docs**

In both docs, change install guidance to reference:

```markdown
- Windows installer: run `space-windows-x86_64-setup.exe` and follow the installer.
- Windows: extract `space-windows-x86_64.zip` and run `space.exe`.
```

- [ ] **Step 5: Update developer build output examples**

In `docs/dev/building.md`, update the stable output examples to use:

```markdown
Stable outputs are written as:
- Full default names: `build/space-linux-x86_64.AppImage`, `build/space-linux-amd64.deb`, `build/space-linux-x86_64.rpm`, `build/dist/space-linux-x86_64.tar.gz`
- Minimal default names: `build/space-linux-x86_64-minimal.AppImage`, `build/space-linux-amd64-minimal.deb`, `build/space-linux-x86_64-minimal.rpm`, `build/dist/space-linux-x86_64-minimal.tar.gz`
- Distro-flavored outputs use the selected flavor after the architecture and before the optional variant, such as `build/space-linux-amd64-ubuntu-24.04.deb`, `build/space-linux-x86_64-fedora.rpm`, or `build/space-linux-amd64-ubuntu-24.04-minimal.deb`.

Windows release builds currently publish:
- `space-windows-x86_64-setup.exe`
- `space-windows-x86_64.zip`
```

- [ ] **Step 6: Run focused documentation validation**

Run:

```bash
python3 -m pytest scripts/tests/test_release_artifact_naming.py::test_release_docs_use_new_public_download_names -v
rg 'space-minimal-linux|-bin\.tar\.gz|space-windows\.zip|space-windows-setup\.exe' docs/dev/building.md docs/user/quick-start.md
```

Expected: pytest passes and `rg` finds no matches. The no-match `rg` exit code 1 is acceptable.

- [ ] **Step 7: Run complete relevant local validation**

Run:

```bash
bash -n scripts/build-linux.sh
python3 -m py_compile scripts/build-windows-installer.py
python3 -m pytest scripts/tests/test_release_artifact_naming.py scripts/tests/test_makefile_build_workflow.py -v
rg 'space-minimal-linux|-bin\.tar\.gz|space-windows\.zip|space-windows-setup\.exe' scripts/build-linux.sh .github/workflows/build.yml scripts/build-windows-installer.py docs/dev/building.md docs/user/quick-start.md
git diff --check
```

Expected: syntax and pytest checks pass, `rg` finds no matches with exit code 1, and `git diff --check` reports no whitespace errors.

- [ ] **Step 8: Commit Task 3**

```bash
git add docs/dev/building.md docs/user/quick-start.md scripts/tests/test_release_artifact_naming.py
git commit -m "docs: update release artifact download names"
```
