# GitHub Workflow Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden and simplify the root GitHub workflows so release publishing, permissions, stateful automation, Git trust, dependency pins, and workflow hygiene are explicit and maintainable.

**Architecture:** Keep the existing workflow boundaries and triggers, but extract duplicated cache setup into local composite actions and centralize release writes into final `publish-release` jobs. Add a small stdlib-only static checker plus maintainer documentation so the hygiene rules are visible and regressions are caught locally.

**Tech Stack:** GitHub Actions YAML, local composite actions, Bash, PowerShell, Python 3 standard library, `actionlint` when available.

## Global Constraints

- Preserve existing workflow triggers, build matrices, package contents, and release asset filenames.
- Default workflow permissions to read-only; grant `contents: write` only to jobs that publish releases or deploy Pages.
- Use only repository-owned local composite actions for new workflow abstractions; do not add new marketplace actions.
- Pin `sccache` to version `0.16.0` everywhere it is installed by workflows.
- Pin Inno Setup Chocolatey installs to exact version `6.4.3`.
- Pin Pillow installs to exact version `11.3.0`.
- Keep Pages-specific actions on their currently supported majors unless validation shows a safe first-party major update is available.
- Use focused static validation only unless implementation unexpectedly changes runtime code, tests, assets, or behavioral build scripts.

---

## File Structure

- Create `.github/actions/setup-linux-compiler-cache/action.yml` — local composite action that restores Linux `ccache`, restores Linux `sccache`, restores the cached `sccache` binary, and installs pinned `sccache` when missing.
- Create `.github/actions/setup-windows-cross-cache/action.yml` — local composite action that restores Windows cross-build cache directories, installs pinned `sccache` when missing, and optionally exports GitHub Actions cache runtime values for `vcpkg`.
- Modify `.github/workflows/test.yml` — consume local composite actions, scope CI Git configuration, keep merge-queue behavior unchanged.
- Modify `.github/workflows/build.yml` — consume local composite actions, add explicit least-privilege permissions, convert builder jobs to workflow-artifact upload, and add centralized release publishing.
- Modify `.github/workflows/bundle.yml` — add explicit least-privilege permissions, centralize app release publishing, pin packaging dependencies.
- Modify `.github/workflows/devlog-publish.yml` — add stateful automation concurrency and normalize first-party action majors.
- Modify `.github/workflows/docs-pages.yml` — normalize `actions/checkout` major only.
- Create `scripts/check-github-workflow-hygiene.py` — stdlib-only static checker for the workflow hygiene invariants in this plan.
- Create `docs/dev/notes/github-actions-hygiene.md` — maintainer policy note for workflow design.
- Modify `docs/dev/notes/index.md` and `docs/dev/subsystems/build.md` — link the new note.

---

### Task 1: Extract compiler cache setup into local composite actions

**Files:**
- Create: `.github/actions/setup-linux-compiler-cache/action.yml`
- Create: `.github/actions/setup-windows-cross-cache/action.yml`
- Modify: `.github/workflows/test.yml`
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: workflow env values `CCACHE_DIR`, `SCCACHE_DIR`, `CCACHE_MAXSIZE`, `SCCACHE_CACHE_SIZE`, `CCACHE_BASEDIR`, `VCPKG_BINARY_SOURCES`.
- Produces: local action `./.github/actions/setup-linux-compiler-cache` with inputs `cache-scope`, `ccache-path`, `sccache-path`, `ccache-key-files`, `sccache-key-files`, `sccache-version`.
- Produces: local action `./.github/actions/setup-windows-cross-cache` with inputs `cache-scope`, `ccache-path`, `sccache-path`, `ccache-key-files`, `sccache-key-files`, `sccache-version`, `export-vcpkg-cache-runtime`.

- [ ] **Step 1: Create the Linux compiler-cache composite action**

  Add `.github/actions/setup-linux-compiler-cache/action.yml` with this shape:

  ```yaml
  name: Setup Linux compiler cache
  description: Restore ccache, restore sccache, and install pinned sccache for Linux jobs.
  inputs:
    cache-scope:
      required: true
      description: Cache scope suffix such as linux.
    ccache-path:
      required: true
      description: Path restored by the ccache cache action.
    sccache-path:
      required: true
      description: Path restored by the sccache cache action.
    ccache-key-files:
      required: true
      description: Hash file patterns for the ccache key.
    sccache-key-files:
      required: true
      description: Hash file patterns for the sccache key.
    sccache-version:
      required: false
      default: 0.16.0
      description: Exact sccache version installed when missing.
  runs:
    using: composite
    steps:
      - name: Restore ccache
        uses: actions/cache@v5
        with:
          path: ${{ inputs.ccache-path }}
          key: ccache-${{ runner.os }}-${{ inputs.cache-scope }}-${{ github.ref }}-${{ hashFiles(inputs.ccache-key-files) }}
          restore-keys: |
            ccache-${{ runner.os }}-${{ inputs.cache-scope }}-${{ github.ref }}-
            ccache-${{ runner.os }}-${{ inputs.cache-scope }}-
            ccache-${{ runner.os }}-

      - name: Restore sccache
        uses: actions/cache@v5
        with:
          path: ${{ inputs.sccache-path }}
          key: sccache-${{ runner.os }}-${{ inputs.cache-scope }}-${{ github.ref }}-${{ hashFiles(inputs.sccache-key-files) }}
          restore-keys: |
            sccache-${{ runner.os }}-${{ inputs.cache-scope }}-${{ github.ref }}-
            sccache-${{ runner.os }}-${{ inputs.cache-scope }}-
            sccache-${{ runner.os }}-

      - name: Restore sccache binary
        uses: actions/cache@v5
        with:
          path: ~/.cargo/bin/sccache
          key: sccache-bin-${{ runner.os }}-${{ inputs.sccache-version }}

      - name: Install sccache
        shell: bash
        run: |
          set -euo pipefail
          if command -v sccache >/dev/null 2>&1; then
            sccache --version
          else
            cargo install sccache --version "${{ inputs.sccache-version }}" --locked
          fi
  ```

- [ ] **Step 2: Create the Windows cross-cache composite action**

  Add `.github/actions/setup-windows-cross-cache/action.yml` with the same cache and install pattern as the Linux action, but use `cache-scope` values such as `windows-cross` and add this final optional step:

  ```yaml
      - name: Export GitHub Actions cache runtime for vcpkg
        if: inputs.export-vcpkg-cache-runtime == 'true'
        uses: actions/github-script@v8
        with:
          script: |
            core.exportVariable('ACTIONS_CACHE_URL', process.env.ACTIONS_CACHE_URL || '');
            core.exportVariable('ACTIONS_RESULTS_URL', process.env.ACTIONS_RESULTS_URL || '');
            core.exportVariable('ACTIONS_RUNTIME_TOKEN', process.env.ACTIONS_RUNTIME_TOKEN || '');
  ```

- [ ] **Step 3: Replace Linux cache blocks in `test.yml`**

  Replace the `Restore ccache`, `Restore sccache`, `Restore sccache binary`, and `Install sccache` steps in the Linux `test` job with:

  ```yaml
      - name: Setup compiler cache
        uses: ./.github/actions/setup-linux-compiler-cache
        with:
          cache-scope: linux
          ccache-path: .ccache
          sccache-path: .sccache
          ccache-key-files: |
            **/CMakeLists.txt
            **/*.cmake
            scripts/build-linux.sh
            scripts/build-appimage.sh
            Makefile
          sccache-key-files: |
            ffi/matrix/Cargo.lock
            ffi/matrix/Cargo.toml
            external/wallet-core/rust/Cargo.lock
            external/wallet-core/rust/Cargo.toml
            CMakeLists.txt
  ```

- [ ] **Step 4: Replace Linux cache blocks in `build.yml`**

  Replace the same repeated Linux cache and `sccache` install sequence in the `build-linux` job with the same local action call from Step 3.

- [ ] **Step 5: Replace Windows cross-cache blocks in `test.yml` and `build.yml`**

  Replace the Windows cross-build `Restore ccache`, `Restore sccache`, `Restore sccache binary`, `Install sccache`, and `Export GitHub Actions cache runtime for vcpkg` steps with:

  ```yaml
      - name: Setup Windows cross-build cache
        uses: ./.github/actions/setup-windows-cross-cache
        with:
          cache-scope: windows-cross
          ccache-path: .ccache-windows
          sccache-path: .sccache-windows
          export-vcpkg-cache-runtime: true
          ccache-key-files: |
            **/CMakeLists.txt
            **/*.cmake
            apps/space/windows_app.rc.in
            scripts/build-windows.sh
            scripts/build-windows-from-linux.sh
            scripts/setup-windows-build-host.sh
            scripts/prepare-windows-runtime.sh
            scripts/prepare-windows-wine-runtime.sh
            scripts/generate_windows_icon.py
          sccache-key-files: |
            ffi/matrix/Cargo.lock
            ffi/matrix/Cargo.toml
            external/wallet-core/rust/Cargo.lock
            external/wallet-core/rust/Cargo.toml
            CMakeLists.txt
            scripts/build-windows.sh
            scripts/build-windows-from-linux.sh
            scripts/setup-windows-build-host.sh
  ```

  In `build.yml`, include `scripts/build-windows-installer.py` and `scripts/windows-installer.iss` in the Windows `ccache-key-files` input because the release workflow already includes them in the cache key.

- [ ] **Step 6: Run focused checks for this task**

  Run:

  ```bash
  python3 - <<'PY'
  import pathlib
  try:
      import yaml
  except Exception:
      raise SystemExit('PyYAML is not available; skip YAML parse here and rely on actionlint/static review')
  for path in [
      '.github/workflows/test.yml',
      '.github/workflows/build.yml',
      '.github/actions/setup-linux-compiler-cache/action.yml',
      '.github/actions/setup-windows-cross-cache/action.yml',
  ]:
      yaml.safe_load(pathlib.Path(path).read_text())
      print(f'parsed {path}')
  PY
  if command -v actionlint >/dev/null 2>&1; then actionlint .github/workflows/test.yml .github/workflows/build.yml; else echo 'actionlint not available'; fi
  ```

  Expected: YAML parse succeeds when PyYAML is available; actionlint passes when installed or prints that it is unavailable.

---

### Task 2: Centralize `build.yml` release publishing and permissions

**Files:**
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: release artifact manifests `build/release-artifacts-${{ matrix.profile }}.txt` and Windows installer outputs under `build/dist`.
- Produces: workflow artifacts `space-linux-release-${{ matrix.profile }}` and `space-windows-release`.
- Produces: `publish-release` job with `contents: write` that uploads release assets once per tag run.

- [ ] **Step 1: Add explicit top-level permissions**

  Add this block near the top of `build.yml`, after `env` or before `jobs`:

  ```yaml
  permissions:
    contents: read
  ```

- [ ] **Step 2: Keep Windows cross-build cache permissions scoped**

  Leave the `build-windows` job permission block with:

  ```yaml
      permissions:
        contents: read
        actions: write
  ```

  This job needs `actions: write` for GitHub Actions cache-backed `vcpkg` binary caching.

- [ ] **Step 3: Convert Linux release upload to workflow artifacts**

  Replace the direct `Upload to GitHub Release` step in the `build-linux` matrix job with:

  ```yaml
      - name: Upload Linux release artifacts
        uses: actions/upload-artifact@v5
        with:
          name: space-linux-release-${{ matrix.profile }}
          path: ${{ steps.linux-release-artifacts.outputs.files }}
          if-no-files-found: error
  ```

- [ ] **Step 4: Convert Windows installer release upload to workflow artifacts**

  Replace the direct `Upload to GitHub Release` step in `build-windows-installer` with:

  ```yaml
      - name: Upload Windows release artifacts
        uses: actions/upload-artifact@v5
        with:
          name: space-windows-release
          path: |
            build/dist/space-windows-x86_64.zip
            build/dist/space-windows-x86_64-setup.exe
          if-no-files-found: error
  ```

- [ ] **Step 5: Add centralized `publish-release` job**

  Add a final job after `build-windows-installer`:

  ```yaml
    publish-release:
      runs-on: ubuntu-22.04
      needs:
        - build-linux
        - build-windows-installer
      if: github.ref_type == 'tag'
      permissions:
        contents: write
      steps:
        - name: Download release artifacts
          uses: actions/download-artifact@v5
          with:
            pattern: space-*-release*
            path: build/release-artifacts
            merge-multiple: true

        - name: Verify downloaded release artifacts
          shell: bash
          run: |
            set -euo pipefail
            find build/release-artifacts -type f -print | sort
            test -n "$(find build/release-artifacts -type f -print -quit)"

        - name: Upload to GitHub Release
          uses: softprops/action-gh-release@v2
          with:
            files: build/release-artifacts/**
          env:
            GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  ```

- [ ] **Step 6: Run focused checks for this task**

  Run:

  ```bash
  python3 - <<'PY'
  from pathlib import Path
  text = Path('.github/workflows/build.yml').read_text()
  assert 'permissions:\n  contents: read' in text
  assert text.count('uses: softprops/action-gh-release@v2') == 1
  assert 'publish-release:' in text
  assert 'name: space-linux-release-${{ matrix.profile }}' in text
  assert 'name: space-windows-release' in text
  print('build workflow release publishing checks passed')
  PY
  if command -v actionlint >/dev/null 2>&1; then actionlint .github/workflows/build.yml; else echo 'actionlint not available'; fi
  ```

  Expected: one release action remains in `build.yml`, and it is in `publish-release`.

---

### Task 3: Centralize `bundle.yml` release publishing and pin packaging tools

**Files:**
- Modify: `.github/workflows/bundle.yml`

**Interfaces:**
- Consumes: Linux app package manifest `build/linux-dist/app-release-artifacts-linux.txt` and Windows app package manifest `build/windows-dist/app-release-artifacts-windows.txt`.
- Produces: workflow artifacts `space-app-linux-release` and `space-app-windows-release`.
- Produces: `publish-release` job with `contents: write` that uploads app release assets once per caller tag run.

- [ ] **Step 1: Add pinned dependency env values**

  Add top-level env values after the `permissions` block or before `jobs`:

  ```yaml
  env:
    INNOSETUP_CHOCO_VERSION: 6.4.3
    PILLOW_VERSION: 11.3.0
  ```

- [ ] **Step 2: Narrow top-level permissions**

  Change top-level permissions from `contents: write` to:

  ```yaml
  permissions:
    contents: read
  ```

- [ ] **Step 3: Convert Linux app release upload to workflow artifact**

  Replace `Upload Linux app artifacts to GitHub Release` with:

  ```yaml
      - name: Upload Linux app release artifacts
        uses: actions/upload-artifact@v5
        with:
          name: space-app-linux-release
          path: ${{ steps.linux-release-artifacts.outputs.files }}
          if-no-files-found: error
  ```

- [ ] **Step 4: Pin Windows packaging tool installs**

  Change the Inno Setup and Pillow install steps to:

  ```yaml
      - name: Install Inno Setup
        shell: pwsh
        run: choco install innosetup --version $env:INNOSETUP_CHOCO_VERSION --no-progress -y

      - name: Install Pillow for icon conversion
        shell: pwsh
        run: python -m pip install "Pillow==$env:PILLOW_VERSION"
  ```

- [ ] **Step 5: Convert Windows app release upload to workflow artifact**

  Replace `Upload Windows app artifacts to GitHub Release` with:

  ```yaml
      - name: Upload Windows app release artifacts
        uses: actions/upload-artifact@v5
        with:
          name: space-app-windows-release
          path: ${{ steps.windows-release-artifacts.outputs.files }}
          if-no-files-found: error
  ```

- [ ] **Step 6: Add centralized app `publish-release` job**

  Add a final job after `bundle-windows`:

  ```yaml
    publish-release:
      name: Publish app release artifacts
      runs-on: ubuntu-22.04
      needs:
        - bundle-linux
        - bundle-windows
      if: github.ref_type == 'tag'
      permissions:
        contents: write
      steps:
        - name: Download app release artifacts
          uses: actions/download-artifact@v5
          with:
            pattern: space-app-*-release
            path: build/app-release-artifacts
            merge-multiple: true

        - name: Verify app release artifacts
          shell: bash
          run: |
            set -euo pipefail
            find build/app-release-artifacts -type f -print | sort
            test -n "$(find build/app-release-artifacts -type f -print -quit)"

        - name: Upload app artifacts to GitHub Release
          uses: softprops/action-gh-release@v2
          with:
            files: build/app-release-artifacts/**
          env:
            GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  ```

- [ ] **Step 7: Run focused checks for this task**

  Run:

  ```bash
  python3 - <<'PY'
  from pathlib import Path
  text = Path('.github/workflows/bundle.yml').read_text()
  assert 'contents: read' in text
  assert 'contents: write' in text
  assert text.count('uses: softprops/action-gh-release@v2') == 1
  assert 'publish-release:' in text
  assert '--version $env:INNOSETUP_CHOCO_VERSION' in text
  assert 'Pillow==$env:PILLOW_VERSION' in text
  print('bundle workflow checks passed')
  PY
  if command -v actionlint >/dev/null 2>&1; then actionlint .github/workflows/bundle.yml; else echo 'actionlint not available'; fi
  ```

  Expected: one release action remains in `bundle.yml`, and it is in `publish-release`.

---

### Task 4: Add workflow guardrails for state, Git trust, versions, and static checks

**Files:**
- Modify: `.github/workflows/devlog-publish.yml`
- Modify: `.github/workflows/test.yml`
- Modify: `.github/workflows/docs-pages.yml`
- Modify: `.github/workflows/build.yml`
- Create: `scripts/check-github-workflow-hygiene.py`

**Interfaces:**
- Consumes: root workflow files under `.github/workflows`.
- Produces: command `python3 scripts/check-github-workflow-hygiene.py` that exits `0` on hygiene pass and nonzero with actionable messages on regression.

- [ ] **Step 1: Serialize devlog publication**

  Add this top-level block to `.github/workflows/devlog-publish.yml` after `permissions` or before `jobs`:

  ```yaml
  concurrency:
    group: devlog-publish
    cancel-in-progress: false
  ```

- [ ] **Step 2: Scope CI Git configuration in `test.yml`**

  Replace the `Configure git for test directories` step body with:

  ```yaml
        run: |
          set -euo pipefail
          git_config="${RUNNER_TEMP}/gitconfig"
          git config --file "${git_config}" user.name "CI Test"
          git config --file "${git_config}" user.email "ci@test.local"
          git config --file "${git_config}" --add safe.directory "${GITHUB_WORKSPACE}"
          git config --file "${git_config}" --add safe.directory /tmp/space/tests
          git config --file "${git_config}" protocol.file.allow always
          echo "GIT_CONFIG_GLOBAL=${git_config}" >> "${GITHUB_ENV}"
          echo "=== CI git config safe.directory ==="
          git config --file "${git_config}" --get-all safe.directory
          echo "=== CI git config protocol.file.allow ==="
          git config --file "${git_config}" protocol.file.allow
  ```

  Do not keep `safe.directory '*'` or `git config --global protocol.file.allow always`.

- [ ] **Step 3: Normalize first-party action majors**

  Make these direct substitutions where they appear in root workflows:

  ```text
  actions/checkout@v4 -> actions/checkout@v5
  actions/github-script@v7 -> actions/github-script@v8
  actions/upload-artifact@v4 -> actions/upload-artifact@v5
  actions/download-artifact@v4 -> actions/download-artifact@v5
  ```

  Do not change `actions/configure-pages@v4`, `actions/upload-pages-artifact@v3`, or `actions/deploy-pages@v4` as part of this step.

- [ ] **Step 4: Pin Inno Setup in `build.yml`**

  Add this top-level env value alongside the existing release smoke env values:

  ```yaml
    INNOSETUP_CHOCO_VERSION: 6.4.3
  ```

  Change the installer job install command to:

  ```yaml
        run: choco install innosetup --version $env:INNOSETUP_CHOCO_VERSION --no-progress -y
  ```

- [ ] **Step 5: Add the stdlib-only hygiene checker**

  Create `scripts/check-github-workflow-hygiene.py` with executable Python 3 code that:

  ```python
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
      if "choco install innosetup --version $env:INNOSETUP_CHOCO_VERSION" not in build:
          fail(errors, "build.yml: Inno Setup Chocolatey install must be pinned")
      build_publish = workflow_job_block(build, "publish-release")
      if build.count("uses: softprops/action-gh-release@v2") != 1 or "softprops/action-gh-release@v2" not in build_publish:
          fail(errors, "build.yml: release publishing must be centralized in publish-release")

      bundle = read(".github/workflows/bundle.yml")
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
  ```

  Keep the script stdlib-only. Adjust the `workflow_job_block` helper during implementation if actionlint or script self-test shows the regex does not capture the final job block correctly.

- [ ] **Step 6: Run focused checks for this task**

  Run:

  ```bash
  python3 scripts/check-github-workflow-hygiene.py
  rtk rg "safe\.directory ['\"]?\*|git config --global protocol\.file\.allow always" .github/workflows || true
  rtk rg "choco install innosetup(?! --version)" .github/workflows || true
  rtk rg "pip install Pillow(?!==)" .github/workflows || true
  if command -v actionlint >/dev/null 2>&1; then actionlint .github/workflows/*.yml; else echo 'actionlint not available'; fi
  ```

  Expected: hygiene script passes; the three `rg` commands print no matching workflow regressions; actionlint passes when installed or prints that it is unavailable.

---

### Task 5: Document the GitHub Actions workflow policy

**Files:**
- Create: `docs/dev/notes/github-actions-hygiene.md`
- Modify: `docs/dev/notes/index.md`
- Modify: `docs/dev/subsystems/build.md`

**Interfaces:**
- Consumes: the workflow policy implemented by Tasks 1 through 4.
- Produces: maintainer-facing documentation linked from the development notes index and build subsystem page.

- [ ] **Step 1: Create the workflow hygiene note**

  Add `docs/dev/notes/github-actions-hygiene.md` with these sections:

  ```markdown
  ---
  type: note
  tags:
    - ci
    - github-actions
    - build
  ---

  # GitHub Actions Hygiene

  Space workflows use least-privilege permissions, centralized release publishing,
  scoped CI Git configuration, and pinned release-time tools. These rules keep CI
  behavior understandable and make release failures easier to diagnose.

  ## Permissions

  Workflows default to `contents: read`. Jobs request broader scopes only when a
  step needs them. Release publisher jobs request `contents: write`; Windows
  cross-build jobs that use GitHub Actions cache-backed `vcpkg` binary caching
  request `actions: write`.

  ## Release publishing

  Builder jobs verify package outputs and upload workflow artifacts. A final
  `publish-release` job downloads those artifacts and writes to the GitHub
  Release. This avoids multiple builders racing to create or update the same
  release.

  ## Stateful scheduled automation

  Devlog publication is serialized with a dedicated concurrency group and
  `cancel-in-progress: false` so state restoration, notification delivery, and
  state upload cannot overlap.

  ## CI Git configuration

  CI must not use wildcard `safe.directory` or broad global Git mutation. Tests
  that need Git trust exceptions write a job-local config under `${RUNNER_TEMP}`
  and point `GIT_CONFIG_GLOBAL` at that file.

  ## Pinned release-time tools

  Workflows pin release-critical package installs such as Inno Setup, Pillow, and
  `sccache`. If a pin becomes unavailable, choose a new exact version in review
  instead of silently returning to a floating install.

  ## Local validation

  Run `python3 scripts/check-github-workflow-hygiene.py` after workflow edits.
  Run `actionlint .github/workflows/*.yml` when `actionlint` is available. PR CI
  remains the authoritative integration gate for GitHub-hosted behavior.
  ```

- [ ] **Step 2: Link the note from the notes index**

  Add this bullet in alphabetical position in `docs/dev/notes/index.md`:

  ```markdown
  - [GitHub Actions Hygiene](./github-actions-hygiene)
  ```

- [ ] **Step 3: Link the note from the build subsystem page**

  Add this bullet under `## Dev notes` in `docs/dev/subsystems/build.md`:

  ```markdown
  - [GitHub Actions Hygiene](/dev/notes/github-actions-hygiene) — CI workflow permissions, release publishing, and workflow hygiene checks
  ```

- [ ] **Step 4: Run documentation checks**

  Run:

  ```bash
  rtk rg "GitHub Actions Hygiene|github-actions-hygiene" docs/dev
  ```

  Expected: matches appear in the new note, the notes index, and the build subsystem page.

---

## Final Validation

After all tasks pass review, run:

```bash
python3 scripts/check-github-workflow-hygiene.py
python3 - <<'PY'
from pathlib import Path
try:
    import yaml
except Exception:
    raise SystemExit('PyYAML is not available; YAML parse skipped')
for pattern in ['.github/workflows/*.yml', '.github/actions/*/action.yml']:
    for path in sorted(Path('.').glob(pattern)):
        yaml.safe_load(path.read_text())
        print(f'parsed {path}')
PY
if command -v actionlint >/dev/null 2>&1; then actionlint .github/workflows/*.yml; else echo 'actionlint not available'; fi
rtk rg "safe\.directory ['\"]?\*|git config --global protocol\.file\.allow always" .github/workflows || true
rtk rg "GitHub Actions Hygiene|github-actions-hygiene" docs/dev
```

Expected results:

- hygiene script passes;
- YAML parse passes when PyYAML is available or reports that parse was skipped because PyYAML is unavailable;
- actionlint passes when installed or reports that it is unavailable;
- broad Git trust search prints no workflow regressions;
- documentation link search finds the new note and both links.

## Acceptance Criteria

- Root workflows have explicit least-privilege permissions.
- Only centralized `publish-release` jobs have release-upload write permissions.
- Release asset names and tag-trigger behavior are unchanged.
- `devlog-publish.yml` serializes stateful runs.
- `test.yml` no longer uses wildcard `safe.directory` or broad global Git protocol mutation.
- Repeated compiler cache setup is represented by local composite actions.
- Inno Setup, Pillow, and `sccache` workflow installs are pinned to exact versions.
- First-party action majors are consistent for checkout, cache, github-script, upload-artifact, and download-artifact.
- `python3 scripts/check-github-workflow-hygiene.py` passes.
- Documentation explains the workflow policy and links from the notes index and build subsystem page.
