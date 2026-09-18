# Space App Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an additive, reusable Space-maintained packaging path for independent Fennel desktop apps that download pinned Space releases instead of compiling Space.

**Architecture:** Keep runtime behavior unchanged and put app packaging policy in small Python/shell scripts exercised by tests. A new reusable workflow checks out the caller app plus Space packaging scripts, normalizes workflow inputs into JSON, downloads pinned Space GitHub Release artifacts, and invokes script-owned packagers for Linux and Windows outputs.

**Tech Stack:** GitHub Actions reusable workflows, Python 3 stdlib packaging helpers, Bash verifiers/launchers, existing `build-appimage.sh`, Inno Setup, dpkg/rpmbuild, Space Fennel runtime validation.

## Global Constraints

- Required public inputs are `space-version` and `app-name`; optional inputs are `app-id`, `entrypoint`, `assets-dir`, `icon-path`, `linux-profile`, `release-version`.
- Do not introduce a root-level `space-app.json` manifest requirement.
- Preserve existing Space release artifacts and existing Space workflows.
- App packaging is additive/backward-compatible.
- Do not redesign runtime resource lookup or default `-m main`.
- App repos must not compile Space.
- Self-contained app artifacts must download pinned Space GitHub Release artifacts.
- Debian/RPM app packages are app-only and depend on system `space`.
- Support Linux `.tar.gz`, Debian package, RPM package, AppImage, Windows ZIP, and Windows installer.
- Preserve existing `space-<os>-<arch>[-role][-minimal].<ext>` Space artifact names.
- Preserve the full and minimal Linux profiles, including the existing CEF-free minimal Space build variant.
- Missing app assets, invalid app ids, invalid entrypoints, missing pinned Space release assets, or unsupported package targets must fail before packaging.
- Downloaded release artifacts must come from the requested `space-version`, not from latest workflow artifacts.
- No macOS packaging, signing, package repository publishing, auto-update, or compatibility/version-management layer beyond a pinned Space release tag.

## Acceptance Criteria

- `.github/workflows/bundle.yml` is callable by an external repository using only the required small input set.
- The reusable workflow downloads pinned Space GitHub Release artifacts and contains no Space compile/build step for app releases.
- App DEB/RPM packages install app assets only and declare a `space` package dependency.
- App tarball/AppImage/Windows ZIP/Windows installer bundle the selected Space release plus app assets and launch `space -m <entrypoint>`.
- Existing Space release workflow behavior, artifact names, runtime lookup, default no-argument launch behavior, and minimal profile remain unchanged.
- `docs/dev/features/app-distribution.md` documents public inputs, minimal caller workflow, expected `mygame` directory, developer run command, per-format assembly, and the future `main` extraction inventory.

## Validation Ladder

- Focused script checks during implementation:
  - `python3 -m pytest scripts/tests/test_app_packaging_metadata.py`
  - `python3 -m pytest scripts/tests/test_package_linux_app.py scripts/tests/test_verify_app_package_layout.py`
  - `python3 -m pytest scripts/tests/test_build_appimage_app_mode.py`
  - `python3 -m pytest scripts/tests/test_package_windows_app.py scripts/tests/test_build_windows_installer_metadata.py`
  - `python3 -m pytest scripts/tests/test_bundle_workflow.py scripts/tests/test_release_artifact_naming.py`
  - `bash -n scripts/verify-app-package-layout.sh && bash -n scripts/build-appimage.sh`
- Fennel/runtime freshness prerequisite: run `make build` with timeout `14400000` if `./build/space` is missing or stale.
- Fennel-facing focused checks, in order:
  - `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file scripts/tests/fixtures/mygame/assets/lua/main.fnl`
  - `make constraints`
  - `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/scripts/tests/fixtures/mygame/assets ./build/space -m main`
- If Fennel delimiter or parse errors appear, inspect the nearest enclosing form around the reported location first; if the reported binding looks innocent, temporarily isolate chunks of the fixture until the real bad form is found.
- Complete relevant local suite after all packaging/script/workflow changes because release distribution behavior is high risk:
  - `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test`
- Broader final checks:
  - Existing Linux/Windows package behavior that requires platform-specific tooling is fully gated by PR CI.
  - PR CI is the full integration gate and must be green before ready-to-merge claims.

## Out of Scope

- Moving `assets/lua/main.fnl` out of Space.
- Creating a downstream application repository.
- Making downstream apps compile Space.
- Redesigning `AssetManager`, Lua/Fennel module search paths, runtime resource lookup order, or default no-argument `-m main`.
- Renaming or reshaping existing Space release artifacts.
- macOS packaging, signing, update systems, or package repository publishing.

---

### Task 1: App Metadata Normalizer and Fixture App

**Files:**
- Create: `scripts/app_packaging.py`
- Create: `scripts/normalize-app-metadata.py`
- Create: `scripts/tests/test_app_packaging_metadata.py`
- Create: `scripts/tests/fixtures/mygame/assets/lua/main.fnl`

**Interfaces:**
- Consumes: workflow/script inputs `space-version`, `app-name`, optional `app-id`, `entrypoint`, `assets-dir`, `icon-path`, `linux-profile`, `release-version`.
- Produces:
  - `AppMetadata` dataclass with JSON fields `app_name`, `app_id`, `entrypoint`, `assets_dir`, `icon_path`, `linux_profile`, `release_version`, `package_version`, `space_version`.
  - `normalize_metadata(...) -> AppMetadata`.
  - CLI: `scripts/normalize-app-metadata.py --repo-root <path> --space-version <tag> --app-name <name> --output <metadata.json> [...]`.

- [ ] **Step 1: Write metadata tests first**
  - Cover deriving `app_id` from `My Game!` as `my-game`.
  - Cover defaults: `entrypoint: main`, `assets-dir: assets`, `linux-profile: full`.
  - Cover `release-version` default from ref/tag `v1.2.3` becoming package version `1.2.3`.
  - Cover invalid `linux-profile`, missing assets dir, invalid explicit `app-id`, invalid entrypoint, and missing icon path failing loudly.
  - Cover that no test or implementation reads `space-app.json`.

- [ ] **Step 2: Add fixture Fennel app**
  - `scripts/tests/fixtures/mygame/assets/lua/main.fnl` should export a `:main` function that prints a short success line and returns without starting the full Space app loop.

- [ ] **Step 3: Run failing tests**
  - Run: `python3 -m pytest scripts/tests/test_app_packaging_metadata.py`
  - Expected: FAIL because `scripts/app_packaging.py` and the CLI do not exist yet.

- [ ] **Step 4: Implement metadata normalization**
  - Use Python stdlib only.
  - Validate `app_id` with a conservative lowercase package-safe pattern.
  - Validate `entrypoint` as a Space module or `module:function` string.
  - Resolve `assets_dir` and optional `icon_path` relative to `--repo-root`.
  - Validate `linux_profile` is exactly `full` or `minimal`.
  - Write deterministic, pretty JSON for downstream scripts.
  - If `release-version` is omitted and no tag/ref name is available, fail with an explicit error.

- [ ] **Step 5: Run focused metadata tests**
  - Run: `python3 -m pytest scripts/tests/test_app_packaging_metadata.py`
  - Expected: PASS.

- [ ] **Step 6: Run Fennel fixture checks**
  - If needed first run: `make build` with timeout `14400000`.
  - Run touched-file compile check:
    `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file scripts/tests/fixtures/mygame/assets/lua/main.fnl`
  - Run constraints second: `make constraints`
  - Run focused launch third:
    `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/scripts/tests/fixtures/mygame/assets ./build/space -m main`

- [ ] **Step 7: Commit**
  - `git add scripts/app_packaging.py scripts/normalize-app-metadata.py scripts/tests/test_app_packaging_metadata.py scripts/tests/fixtures/mygame/assets/lua/main.fnl`
  - `git commit -m "feat(scripts): add app packaging metadata normalizer"`

---

### Task 2: Linux App Package and Tarball Assembly

**Files:**
- Create: `scripts/package-linux-app.py`
- Create: `scripts/verify-app-package-layout.sh`
- Create: `scripts/tests/test_package_linux_app.py`
- Create: `scripts/tests/test_verify_app_package_layout.py`
- Modify: `scripts/app_packaging.py`

**Interfaces:**
- Consumes: normalized metadata JSON from Task 1.
- Produces:
  - CLI: `scripts/package-linux-app.py --metadata-json <metadata.json> --output-dir <dir> --targets deb,rpm,tarball --space-tarball <space-linux-x86_64[-minimal].tar.gz>`.
  - Manifest: `<output-dir>/app-release-artifacts-linux.txt`.
  - App package launcher content using:
    `SPACE_ASSETS_PATH="/usr/share/<app-id>/assets${SPACE_ASSETS_PATH:+:$SPACE_ASSETS_PATH}" exec /usr/bin/space -m <entrypoint> "$@"`.
  - Tarball launcher content that prepends bundled app assets before bundled Space assets and executes bundled `bin/space`.

- [ ] **Step 1: Write Linux packaging tests first**
  - Verify app-only package root contains `/usr/bin/<app-id>`, `/usr/share/<app-id>/assets`, and `/usr/share/applications/<app-id>.desktop`.
  - Verify package root does not copy `/usr/share/space/assets`.
  - Verify DEB control declares `Depends: space` and uses `space (>= <package_version>)` when the pinned tag normalizes safely.
  - Verify RPM spec declares `Requires: space` and uses `space >= <package_version>` when safe.
  - Verify self-contained tarball root preserves bundled Space files and adds `share/<app-id>/assets` plus a top-level `<app-id>` launcher.
  - Verify output artifact names:
    - `<app-id>-linux-amd64.deb`
    - `<app-id>-linux-x86_64.rpm`
    - `<app-id>-linux-x86_64.tar.gz`
    - include `-minimal` for self-contained Linux outputs when `linux_profile` is `minimal`.

- [ ] **Step 2: Write app layout verifier tests first**
  - Package layout should pass with app assets, app launcher, and desktop file.
  - Package layout should fail if `/usr/share/space/assets` appears in an app-only root.
  - Tarball layout should fail if bundled `bin/space` is missing.
  - Tarball layout should fail if app assets are not before Space assets in the launcher.

- [ ] **Step 3: Run failing tests**
  - Run: `python3 -m pytest scripts/tests/test_package_linux_app.py scripts/tests/test_verify_app_package_layout.py`
  - Expected: FAIL because scripts do not exist yet.

- [ ] **Step 4: Implement Linux staging helpers**
  - Add shared helpers in `scripts/app_packaging.py` for safe recursive copy, executable writes, desktop file escaping, artifact naming, and dependency version normalization.
  - Implement package-root staging in `scripts/package-linux-app.py`.
  - Implement tarball-root staging by extracting the pinned Space tarball and preserving all existing contents.

- [ ] **Step 5: Implement package builders**
  - Build DEB with `dpkg-deb --build` when target includes `deb`.
  - Build RPM with `rpmbuild -bb` when target includes `rpm`.
  - Fail explicitly when required external tools are missing.
  - Keep unit tests hermetic by testing staged roots and generated metadata directly; integration packaging tool invocations can be covered where the tools are available.
  - Always write and validate `app-release-artifacts-linux.txt`.

- [ ] **Step 6: Implement app layout verifier**
  - `scripts/verify-app-package-layout.sh --root <root> --layout package|tarball --app-id <app-id> --entrypoint <entrypoint>`.
  - Keep `scripts/verify-linux-package-layout.sh` unchanged for Space release artifacts.

- [ ] **Step 7: Run focused Linux packaging tests**
  - Run: `python3 -m pytest scripts/tests/test_package_linux_app.py scripts/tests/test_verify_app_package_layout.py`
  - Run: `bash -n scripts/verify-app-package-layout.sh`
  - Expected: PASS.

- [ ] **Step 8: Commit**
  - `git add scripts/app_packaging.py scripts/package-linux-app.py scripts/verify-app-package-layout.sh scripts/tests/test_package_linux_app.py scripts/tests/test_verify_app_package_layout.py`
  - `git commit -m "feat(scripts): assemble Linux app packages"`

---

### Task 3: AppImage App Mode

**Files:**
- Modify: `scripts/build-appimage.sh`
- Modify: `scripts/package-linux-app.py`
- Modify: `scripts/tests/test_release_artifact_naming.py`
- Create: `scripts/tests/test_build_appimage_app_mode.py`

**Interfaces:**
- Consumes: normalized metadata JSON and an extracted pinned Space runtime tree.
- Produces:
  - `SPACE_APP_METADATA_JSON=<metadata.json>` app mode for `scripts/build-appimage.sh`.
  - `SPACE_APPIMAGE_STAGE_ONLY=1` internal test mode that stages `AppDir` and exits before downloading/running linuxdeploy/appimagetool.
  - `package-linux-app.py --targets appimage` delegates to `scripts/build-appimage.sh`.
  - App `AppRun` sets app assets first, bundled Space assets second, preserves library path setup, and executes `usr/bin/space -m <entrypoint>`.

- [ ] **Step 1: Write AppImage tests first**
  - Verify default Space mode still writes an `AppRun` that executes `usr/bin/space "$@"` without forcing `-m`.
  - Verify app mode stages `usr/share/<app-id>/assets`.
  - Verify app mode desktop file uses app name/id.
  - Verify app mode `AppRun` has app asset root before `usr/share/space/assets`.
  - Verify app mode `AppRun` fails loudly if bundled `usr/bin/space` is missing.
  - Verify `scripts/tests/test_release_artifact_naming.py` still asserts unchanged Space artifact names.

- [ ] **Step 2: Run failing AppImage tests**
  - Run: `python3 -m pytest scripts/tests/test_build_appimage_app_mode.py scripts/tests/test_release_artifact_naming.py`
  - Expected: FAIL for new app mode tests.

- [ ] **Step 3: Generalize `build-appimage.sh`**
  - Preserve existing behavior when `SPACE_APP_METADATA_JSON` is unset.
  - In app mode, require `SPACE_INSTALL_PREFIX` to point to the extracted Space runtime tree.
  - Copy app assets to `AppDir/usr/share/<app-id>/assets`.
  - Use provided PNG icon when available; otherwise use bundled Space icon only as generic AppImage tooling input.
  - Use `release_version` from metadata instead of requiring `CPackConfig.cmake` in app mode.
  - Keep existing `space-linux-x86_64*.AppImage` behavior and names for Space releases.

- [ ] **Step 4: Wire AppImage target into Linux app packager**
  - Add `appimage` to accepted targets in `scripts/package-linux-app.py`.
  - Reuse extracted pinned tarball runtime tree.
  - Add generated AppImage path to `app-release-artifacts-linux.txt`.

- [ ] **Step 5: Run focused AppImage tests**
  - Run: `python3 -m pytest scripts/tests/test_build_appimage_app_mode.py scripts/tests/test_package_linux_app.py scripts/tests/test_release_artifact_naming.py`
  - Run: `bash -n scripts/build-appimage.sh`
  - Expected: PASS.

- [ ] **Step 6: Commit**
  - `git add scripts/build-appimage.sh scripts/package-linux-app.py scripts/tests/test_build_appimage_app_mode.py scripts/tests/test_release_artifact_naming.py`
  - `git commit -m "feat(scripts): support app AppImage assembly"`

---

### Task 4: Windows ZIP and Installer Assembly

**Files:**
- Create: `scripts/package-windows-app.py`
- Create: `scripts/tests/test_package_windows_app.py`
- Create: `scripts/tests/test_build_windows_installer_metadata.py`
- Modify: `scripts/build-windows-installer.py`
- Modify: `scripts/windows-installer.iss`

**Interfaces:**
- Consumes: normalized metadata JSON and pinned `space-windows-x86_64.zip`.
- Produces:
  - CLI: `scripts/package-windows-app.py --metadata-json <metadata.json> --space-zip <space-windows-x86_64.zip> --output-dir <dir> --targets zip,installer-stage`.
  - Manifest: `<output-dir>/app-release-artifacts-windows.txt`.
  - Windows ZIP with preserved `space.exe`, `space-cli.exe`, DLLs/base assets, app assets, and `<app-id>.cmd`.
  - Installer metadata mode: `scripts/build-windows-installer.py --metadata-json <metadata.json> --dist-dir <staged-runtime> --output-dir <dir>`.

- [ ] **Step 1: Write Windows packaging tests first**
  - Verify ZIP staging preserves `space.exe` and `space-cli.exe`.
  - Verify app assets are copied under the staged runtime assets tree without deleting Space runtime assets.
  - Verify `<app-id>.cmd` runs `space.exe -m <entrypoint> %*`.
  - Verify artifact name `<app-id>-windows-x86_64.zip`.
  - Verify `app-release-artifacts-windows.txt` includes the ZIP and installer when requested.

- [ ] **Step 2: Write installer metadata tests first**
  - Verify default Space installer mode still reads CPack metadata and uses `space-windows-x86_64-setup`.
  - Verify app metadata mode passes deterministic app-specific `AppId`.
  - Verify Start Menu, desktop, and postinstall run entries target `space.exe` with `-m <entrypoint>`.
  - Verify missing icon is valid and does not require `SetupIconFile`.
  - Verify `.ico` is used directly and `.png` is converted through existing `scripts/generate_windows_icon.py` when Pillow is available.

- [ ] **Step 3: Run failing tests**
  - Run: `python3 -m pytest scripts/tests/test_package_windows_app.py scripts/tests/test_build_windows_installer_metadata.py`
  - Expected: FAIL for missing app packager/app metadata mode.

- [ ] **Step 4: Implement Windows ZIP staging**
  - Extract the pinned Space ZIP into a staging directory.
  - Preserve all existing runtime files.
  - Copy app assets after Space assets so app files are available in the executable-sibling asset tree.
  - Write `<app-id>.cmd` with explicit `space.exe -m <entrypoint>`.
  - Create `<app-id>-windows-x86_64.zip`.

- [ ] **Step 5: Generalize installer helper and ISS template**
  - Add `--metadata-json` to `scripts/build-windows-installer.py`.
  - Keep existing Space defaults when metadata JSON is not supplied.
  - Define `AppExeArgs` for app mode and leave it empty for Space mode.
  - Make `AppIconFile` optional in `scripts/windows-installer.iss`.
  - Use deterministic UUIDv5-style AppId from `app_id` for app installers.
  - Use `<app-id>-windows-x86_64-setup.exe` for app installers.

- [ ] **Step 6: Run focused Windows packaging tests**
  - Run: `python3 -m pytest scripts/tests/test_package_windows_app.py scripts/tests/test_build_windows_installer_metadata.py`
  - Expected: PASS.

- [ ] **Step 7: Commit**
  - `git add scripts/package-windows-app.py scripts/build-windows-installer.py scripts/windows-installer.iss scripts/tests/test_package_windows_app.py scripts/tests/test_build_windows_installer_metadata.py`
  - `git commit -m "feat(scripts): assemble Windows app packages"`

---

### Task 5: Reusable App Bundle Workflow

**Files:**
- Create: `.github/workflows/bundle.yml`
- Create: `scripts/tests/test_bundle_workflow.py`

**Interfaces:**
- Consumes: public workflow inputs `space-version`, `app-name`, optional `app-id`, `entrypoint`, `assets-dir`, `icon-path`, `linux-profile`, `release-version`.
- Produces: reusable `workflow_call` workflow that uploads app release artifacts to the caller repository release.

- [ ] **Step 1: Write workflow static tests first**
  - Assert workflow has `on.workflow_call.inputs.space-version.required: true`.
  - Assert workflow has `on.workflow_call.inputs.app-name.required: true`.
  - Assert optional public inputs are exactly `app-id`, `entrypoint`, `assets-dir`, `icon-path`, `linux-profile`, `release-version`.
  - Assert workflow checks out the caller app and separately checks out the Space workflow repository/scripts at the reusable workflow ref parsed from `github.workflow_ref`.
  - Assert workflow uses `gh release download <space-version> --repo semanticdreams/space2`.
  - Assert workflow downloads exact pinned artifact names for Linux and Windows.
  - Assert workflow does not run `make build`, `cmake --build`, `scripts/build-linux.sh`, or `scripts/build-windows-from-linux.sh`.
  - Assert workflow never references `space-app.json`.

- [ ] **Step 2: Run failing workflow tests**
  - Run: `python3 -m pytest scripts/tests/test_bundle_workflow.py`
  - Expected: FAIL because workflow does not exist.

- [ ] **Step 3: Implement workflow-call interface**
  - Add required inputs `space-version` and `app-name`.
  - Add optional inputs and defaults:
    - `app-id`: empty string.
    - `entrypoint`: `main`.
    - `assets-dir`: `assets`.
    - `icon-path`: empty string.
    - `linux-profile`: `full`.
    - `release-version`: empty string, resolved by metadata normalizer from tag/ref when omitted.
  - Add permissions guidance compatible with release upload: caller must grant `contents: write`.

- [ ] **Step 4: Implement Linux workflow job**
  - Checkout caller app into `app/`.
  - Parse <code v-pre>${{ github.workflow_ref }}</code> to checkout Space packaging scripts into `space-packaging/`.
  - Normalize metadata to `build/app-metadata.json`.
  - Download `space-linux-x86_64.tar.gz` or `space-linux-x86_64-minimal.tar.gz` from the requested `space-version`.
  - Install packaging tools needed for app DEB/RPM/AppImage staging.
  - Run `space-packaging/scripts/package-linux-app.py` for `deb,rpm,tarball,appimage`.
  - Upload listed artifacts to the caller release on tag builds.

- [ ] **Step 5: Implement Windows workflow job**
  - Checkout caller app into `app/`.
  - Checkout Space packaging scripts into `space-packaging/`.
  - Normalize metadata to `build/app-metadata.json`.
  - Download `space-windows-x86_64.zip` from the requested `space-version`.
  - Install Inno Setup.
  - Install Pillow only for PNG-to-ICO conversion support.
  - Run `space-packaging/scripts/package-windows-app.py` for `zip,installer-stage`.
  - Run `space-packaging/scripts/build-windows-installer.py --metadata-json ...`.
  - Upload listed artifacts to the caller release on tag builds.

- [ ] **Step 6: Run workflow and regression tests**
  - Run: `python3 -m pytest scripts/tests/test_bundle_workflow.py scripts/tests/test_release_artifact_naming.py`
  - Expected: PASS.

- [ ] **Step 7: Commit**
  - `git add .github/workflows/bundle.yml scripts/tests/test_bundle_workflow.py`
  - `git commit -m "feat(ci): add reusable app bundle workflow"`

---

### Task 6: App Distribution Developer Documentation

**Files:**
- Create: `docs/dev/features/app-distribution.md`
- Modify: `docs/dev/features/index.md`

**Interfaces:**
- Consumes: implemented workflow/script behavior from Tasks 1-5.
- Produces: canonical developer documentation for app distribution.

- [ ] **Step 1: Draft docs with required public inputs**
  - Document required inputs `space-version` and `app-name`.
  - Document optional inputs `app-id`, `entrypoint`, `assets-dir`, `icon-path`, `linux-profile`, `release-version`.
  - State that app repos do not need and must not add a required root-level `space-app.json`.

- [ ] **Step 2: Add minimal caller workflow**
  - Include the exact minimal external repository workflow shape:
    - `on.push.tags: "v*"`
    - `permissions.contents: write`
    - `uses: semanticdreams/space2/.github/workflows/bundle.yml@v1`
    - `with.space-version`
    - `with.app-name`

- [ ] **Step 3: Document expected app directory**
  - Include the `mygame/` layout with `assets/lua/main.fnl`, optional media under assets, and `.github/workflows/release.yml`.
  - Explain namespaced entrypoints such as `mygame.main`.

- [ ] **Step 4: Document developer run command**
  - Include:
    - `space -m main`
    - `space -m mygame.main`
    - `SPACE_ASSETS_PATH=/path/to/mygame/assets space -m main` for non-root launches.
  - Explicitly state no runtime lookup redesign is part of this feature.

- [ ] **Step 5: Document per-format assembly**
  - DEB/RPM: app-only, install app assets, wrapper calls system `/usr/bin/space`, package depends on `space`.
  - Tarball: downloaded Space tarball preserved, app assets added under `share/<app-id>/assets`, app launcher prepends app assets.
  - AppImage: downloaded Space runtime staged, app assets added, `AppRun` executes `space -m <entrypoint>`.
  - Windows ZIP: downloaded Space ZIP preserved, app assets added, `<app-id>.cmd` launches `space.exe -m <entrypoint>`.
  - Windows installer: same staged runtime as ZIP, shortcuts/postinstall launch `space.exe -m <entrypoint>`.

- [ ] **Step 6: Document future `main` extraction inventory**
  - Move out: `assets/lua/main.fnl`, default app composition modules, activity/world composition, HUD/canvas units, app-specific graph/drawing/board/sandbox activities, workflows/LLM/MCP/wallet integrations not intended as platform APIs, and default application media/content after file-by-file review.
  - Keep in Space: C++ runtime and bindings, Fennel loader/cache support, generic utilities, generic UI/layout/render primitives, generic runtime systems, shaders, fonts, icon metadata, and assets required by reusable modules.
  - Revisit before moving: modules that look generic but depend on global `app`, default app settings, graph extension registries, or concrete owned-path hot reload assumptions.
  - State that the extraction decision about preserving a minimal Space-owned `main` is deferred.

- [ ] **Step 7: Link docs page from feature index**
  - Add `App Distribution` to `docs/dev/features/index.md`.

- [ ] **Step 8: Run documentation/static checks**
  - Run: `python3 -m pytest scripts/tests/test_bundle_workflow.py scripts/tests/test_release_artifact_naming.py`
  - Run: `rg "space-app.json" docs/dev/features/app-distribution.md .github/workflows/bundle.yml scripts`
  - Expected: only explanatory non-requirement references to `space-app.json`.

- [ ] **Step 9: Commit**
  - `git add docs/dev/features/app-distribution.md docs/dev/features/index.md`
  - `git commit -m "docs: document app distribution workflow"`
