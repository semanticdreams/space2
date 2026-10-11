# Windows CI Speedups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Speed Windows PR/merge-queue CI by removing packaging-only work from `test.yml`, preserving release/manual package generation in `build.yml`, and enabling faster Windows cross-builds.

**Architecture:** Keep CI validation and package generation as separate workflow responsibilities. `test.yml` keeps the Windows runtime cross-build plus native Windows fast-suite validation; `build.yml` keeps release/manual ZIP and installer packaging. Static Python tests enforce workflow boundaries because local validation should not run a full Windows build or installer job.

**Tech Stack:** GitHub Actions YAML, CMake, Ninja, vcpkg binary caching, ccache/sccache, Bash, Python pytest, PyYAML, Space repository workflow tests.

## Global Constraints

- `test.yml` is the validation workflow for PRs, pushes to `main`, and merge queue.
- `build.yml` remains the packaging/release workflow for `make release` tag pushes and existing manual `workflow_dispatch` use.
- Windows installer generation stays out of PR/merge-queue CI.
- Windows ZIP/release packaging input generation stays out of PR/merge-queue CI unless a test directly consumes it; the current native Windows test job consumes only the staged runtime directory.
- The release workflow keeps existing package generation behavior, including Linux release artifacts, Windows runtime ZIP, Windows installer generation and smoke test, GitHub Release uploads on tag builds, and existing `workflow_dispatch` behavior.
- No release artifact is removed or renamed.
- Both Windows cross-build jobs (`test.yml` and `build.yml`) should use `CMAKE_GENERATOR: Ninja`.
- `scripts/build-windows.sh` should use parallel CMake build execution, with `BUILD_JOBS` defaulting to `nproc` and validating positive integer input.
- Windows cross-build jobs should reliably restore/install the `sccache` binary so the existing `.sccache-windows` cache can be used by the Rust matrix build.
- GitHub Actions vcpkg binary caching should avoid rebuilding expensive vcpkg packages; for `test.yml`, pull requests should use read-only vcpkg cache access while trusted push/merge-group contexts may use read-write; `build.yml` may use read-write.
- Full confidence comes from PR CI: the Linux cross-build job and native Windows fast-suite job remain the integration gate.

---

## File Structure

- `.github/workflows/test.yml` — PR/push/merge-group validation workflow. Remove packaging-only Windows ZIP/installer work while preserving `build-windows` and native Windows `test-windows`.
- `.github/workflows/build.yml` — release/manual packaging workflow. Keep existing package generation and add the same Windows cross-build speed/cache settings.
- `scripts/build-windows.sh` — Windows cross-build entrypoint. Add build-job resolution, stale generator cache reset, and `cmake --build --parallel`.
- `scripts/tests/test_windows_ci_speedups.py` — new static tests enforcing the Windows CI validation/packaging boundary and cross-build speed settings.
- `scripts/tests/test_release_artifact_naming.py` — update the existing artifact-name test so Windows release artifact names are required in `build.yml` but not in PR `test.yml`.
- `docs/dev/notes/windows-wine-build-and-test.md` — update operational notes to describe the new validation-vs-packaging boundary and cache/parallelism improvements.

### Task 1: Add Static Tests for Windows CI Policy

**Files:**
- Create: `scripts/tests/test_windows_ci_speedups.py`
- Modify: `scripts/tests/test_release_artifact_naming.py:45-83`

**Interfaces:**
- Consumes: existing workflow files at `.github/workflows/test.yml` and `.github/workflows/build.yml`.
- Produces: pytest coverage that later tasks must satisfy: `load_workflow(relative_path: str) -> dict`, `read_repo_text(relative_path: str) -> str`, and tests documenting validation-vs-packaging boundaries.

- [ ] **Step 1: Create the workflow test helper and policy tests.**

  Create `scripts/tests/test_windows_ci_speedups.py` with this content:

  ```python
  from pathlib import Path

  import yaml


  REPO_ROOT = Path(__file__).resolve().parents[2]


  class WorkflowLoader(yaml.SafeLoader):
      pass


  for first_char, mappings in list(WorkflowLoader.yaml_implicit_resolvers.items()):
      WorkflowLoader.yaml_implicit_resolvers[first_char] = [
          (tag, regexp)
          for tag, regexp in mappings
          if tag != "tag:yaml.org,2002:bool"
      ]


  def read_repo_text(relative_path: str) -> str:
      return (REPO_ROOT / relative_path).read_text(encoding="utf-8")


  def load_workflow(relative_path: str) -> dict:
      return yaml.load(read_repo_text(relative_path), Loader=WorkflowLoader)


  def test_pr_ci_keeps_native_windows_fast_suite_and_has_no_installer_job() -> None:
      workflow = load_workflow(".github/workflows/test.yml")
      jobs = workflow["jobs"]
      text = read_repo_text(".github/workflows/test.yml")

      assert "build-windows" in jobs
      assert "test-windows" in jobs
      assert "build-windows-installer" not in jobs
      assert jobs["test-windows"]["needs"] == "build-windows"
      assert jobs["test-windows"]["runs-on"] == "windows-latest"
      assert "tests.fast:main" in text


  def test_pr_windows_cross_build_uploads_runtime_only_and_no_packaging_inputs() -> None:
      text = read_repo_text(".github/workflows/test.yml")

      assert "name: space-windows-runtime" in text
      assert "windows-packaging-inputs" not in text
      assert "Create Windows ZIP" not in text
      assert "Verify Windows ZIP contents" not in text
      assert "space-windows-x86_64.zip" not in text
      assert "space-windows-x86_64-setup.exe" not in text
      assert "scripts/build-windows-installer.py" not in text
      assert "choco install innosetup" not in text


  def test_release_workflow_keeps_windows_zip_and_installer_packaging_paths() -> None:
      workflow = load_workflow(".github/workflows/build.yml")
      jobs = workflow["jobs"]
      text = read_repo_text(".github/workflows/build.yml")

      assert "build-windows" in jobs
      assert "build-windows-installer" in jobs
      assert jobs["build-windows-installer"]["needs"] == "build-windows"
      assert "space-windows-x86_64.zip" in text
      assert "space-windows-x86_64-setup.exe" in text
      assert "choco install innosetup --no-progress -y" in text
      assert "python scripts/build-windows-installer.py" in text
      assert "softprops/action-gh-release@v2" in text
  ```

- [ ] **Step 2: Update release artifact naming expectations.**

  In `scripts/tests/test_release_artifact_naming.py`, keep the `expected_names` loop requiring Windows release names in `build.yml`, but replace lines 73-77 with a PR-workflow absence assertion:

  ```python
      for release_only_name in [
          "space-windows-x86_64.zip",
          "space-windows-x86_64-setup.exe",
      ]:
          assert_absent(test_workflow, release_only_name, ".github/workflows/test.yml")
  ```

  Keep the existing obsolete-name absence loop for `test_workflow`.

- [ ] **Step 3: Run the focused tests and observe the expected failures.**

  Run:

  ```bash
  python3 -m pytest \
    scripts/tests/test_windows_ci_speedups.py::test_pr_ci_keeps_native_windows_fast_suite_and_has_no_installer_job \
    scripts/tests/test_windows_ci_speedups.py::test_pr_windows_cross_build_uploads_runtime_only_and_no_packaging_inputs \
    scripts/tests/test_windows_ci_speedups.py::test_release_workflow_keeps_windows_zip_and_installer_packaging_paths \
    scripts/tests/test_release_artifact_naming.py::test_workflows_use_new_release_artifact_names \
    -q
  ```

  Expected: the release workflow test should pass or nearly pass; the PR workflow tests and artifact naming test should fail because `test.yml` still has Windows ZIP and installer packaging work.

- [ ] **Step 4: Commit the tests.**

  Commit only the test changes:

  ```bash
  git add scripts/tests/test_windows_ci_speedups.py scripts/tests/test_release_artifact_naming.py
  git commit -m "test(scripts): cover Windows CI packaging boundary"
  ```

### Task 2: Remove Packaging-Only Work from PR Windows CI

**Files:**
- Modify: `.github/workflows/test.yml:122-302`

**Interfaces:**
- Consumes: tests from Task 1.
- Produces: `test.yml` where `build-windows` uploads `space-windows-runtime` only, `test-windows` still depends on `build-windows`, and no PR/merge-queue Windows installer or release ZIP packaging remains.

- [ ] **Step 1: Remove Windows ZIP creation and verification from `test.yml`.**

  In `.github/workflows/test.yml`, delete the entire steps named:

  ```yaml
      - name: Create Windows ZIP
      - name: Verify Windows ZIP contents
  ```

  Do not remove `Prepare runtime bundle`, `Smoke test Windows package`, or `Upload Windows runtime`.

- [ ] **Step 2: Remove packaging-input upload from `test.yml`.**

  Delete the entire step named:

  ```yaml
      - name: Upload Windows packaging inputs
  ```

  This step is no longer needed because no PR/merge-queue job consumes installer packaging inputs.

- [ ] **Step 3: Remove the PR installer job from `test.yml`.**

  Delete the entire job block:

  ```yaml
    build-windows-installer:
  ```

  Remove all of its checkout, artifact download, Inno Setup install, installer build, and installer smoke-test steps.

- [ ] **Step 4: Keep the native Windows fast suite unchanged.**

  Confirm `.github/workflows/test.yml` still contains:

  ```yaml
    test-windows:
      needs: build-windows
      runs-on: windows-latest
  ```

  Confirm its final command remains:

  ```yaml
        run: .\build\dist\windows\space-cli.exe -m tests.fast:main
  ```

- [ ] **Step 5: Remove installer-only invalidators from the PR Windows ccache key.**

  In `.github/workflows/test.yml` under `jobs.build-windows.steps.Restore ccache.with.key`, remove these hash inputs because they no longer affect PR Windows validation:

  ```yaml
  scripts/build-windows-installer.py
  scripts/windows-installer.iss
  ```

  Keep build/runtime inputs such as `scripts/build-windows.sh`, `scripts/build-windows-from-linux.sh`, `scripts/setup-windows-build-host.sh`, `scripts/prepare-windows-runtime.sh`, `scripts/prepare-windows-wine-runtime.sh`, and `scripts/generate_windows_icon.py`.

- [ ] **Step 6: Run focused workflow boundary tests.**

  Run:

  ```bash
  python3 -m pytest \
    scripts/tests/test_windows_ci_speedups.py::test_pr_ci_keeps_native_windows_fast_suite_and_has_no_installer_job \
    scripts/tests/test_windows_ci_speedups.py::test_pr_windows_cross_build_uploads_runtime_only_and_no_packaging_inputs \
    scripts/tests/test_windows_ci_speedups.py::test_release_workflow_keeps_windows_zip_and_installer_packaging_paths \
    scripts/tests/test_release_artifact_naming.py::test_workflows_use_new_release_artifact_names \
    -q
  ```

  Expected: pass.

- [ ] **Step 7: Commit the workflow slimming change.**

  Commit only the PR workflow changes:

  ```bash
  git add .github/workflows/test.yml
  git commit -m "ci: remove Windows packaging from PR validation"
  ```

### Task 3: Enable Ninja, sccache, and vcpkg Binary Cache for Windows Cross-Build Jobs

**Files:**
- Modify: `.github/workflows/test.yml:122-181`
- Modify: `.github/workflows/build.yml:188-228`
- Modify: `scripts/tests/test_windows_ci_speedups.py`

**Interfaces:**
- Consumes: `scripts/build-windows.sh` support for `CMAKE_GENERATOR`.
- Produces: workflow-level environment and setup for faster Windows cross-builds in both validation and release/manual workflows.

- [ ] **Step 1: Add static tests for cross-build speed settings.**

  Append these tests to `scripts/tests/test_windows_ci_speedups.py`:

  ```python
  def test_windows_cross_build_jobs_enable_ninja_sccache_binary_and_vcpkg_cache() -> None:
      for workflow_path in [".github/workflows/test.yml", ".github/workflows/build.yml"]:
          workflow = load_workflow(workflow_path)
          job = workflow["jobs"]["build-windows"]
          env = job["env"]
          text = read_repo_text(workflow_path)

          assert job["permissions"]["contents"] == "read"
          assert job["permissions"]["actions"] == "write"
          assert env["CMAKE_GENERATOR"] == "Ninja"
          assert env["VCPKG_FEATURE_FLAGS"] == "binarycaching"
          assert "VCPKG_BINARY_SOURCES" in env
          assert "Restore sccache binary" in text
          assert "sccache-bin-${{ runner.os }}-0.16.0" in text
          assert "cargo install sccache --version 0.16.0 --locked" in text
          assert "Export GitHub Actions cache runtime for vcpkg" in text
          assert "ACTIONS_CACHE_URL" in text
          assert "ACTIONS_RESULTS_URL" in text
          assert "ACTIONS_RUNTIME_TOKEN" in text


  def test_pr_vcpkg_binary_cache_is_read_only_for_pull_requests() -> None:
      workflow = load_workflow(".github/workflows/test.yml")
      source = workflow["jobs"]["build-windows"]["env"]["VCPKG_BINARY_SOURCES"]

      assert "github.event_name == 'pull_request'" in source
      assert "clear;x-gha,read" in source
      assert "clear;x-gha,readwrite" in source
  ```

- [ ] **Step 2: Run the speed-setting tests and observe the expected failures.**

  Run:

  ```bash
  python3 -m pytest \
    scripts/tests/test_windows_ci_speedups.py::test_windows_cross_build_jobs_enable_ninja_sccache_binary_and_vcpkg_cache \
    scripts/tests/test_windows_ci_speedups.py::test_pr_vcpkg_binary_cache_is_read_only_for_pull_requests \
    -q
  ```

  Expected: fail because the Windows cross-build jobs do not yet set Ninja, vcpkg binary-cache settings, permissions, or reliable sccache binary install steps.

- [ ] **Step 3: Add speed/cache env and permissions to `test.yml` `build-windows`.**

  In `.github/workflows/test.yml`, under `jobs.build-windows`, add:

  ```yaml
    permissions:
      contents: read
      actions: write
  ```

  In the same job's `env`, add:

  ```yaml
      CMAKE_GENERATOR: Ninja
      VCPKG_FEATURE_FLAGS: binarycaching
      VCPKG_BINARY_SOURCES: ${{ github.event_name == 'pull_request' && 'clear;x-gha,read' || 'clear;x-gha,readwrite' }}
  ```

- [ ] **Step 4: Add speed/cache env and permissions to `build.yml` `build-windows`.**

  In `.github/workflows/build.yml`, under `jobs.build-windows`, add:

  ```yaml
    permissions:
      contents: read
      actions: write
  ```

  In the same job's `env`, add:

  ```yaml
      CMAKE_GENERATOR: Ninja
      VCPKG_FEATURE_FLAGS: binarycaching
      VCPKG_BINARY_SOURCES: clear;x-gha,readwrite
  ```

  Keep `workflow_dispatch` behavior unchanged.

- [ ] **Step 5: Add sccache binary restore/install to both Windows cross-build jobs.**

  In both workflows, after the `.sccache-windows` cache restore step and before `Setup Windows cross-build host`, add:

  ```yaml
      - name: Restore sccache binary
        uses: actions/cache@v5
        with:
          path: ~/.cargo/bin/sccache
          key: sccache-bin-${{ runner.os }}-0.16.0

      - name: Install sccache
        run: |
          if command -v sccache >/dev/null 2>&1; then
            sccache --version
          else
            cargo install sccache --version 0.16.0 --locked
          fi
  ```

- [ ] **Step 6: Export GitHub Actions cache runtime variables for vcpkg.**

  In both workflows, after `Install sccache` and before `Setup Windows cross-build host`, add:

  ```yaml
      - name: Export GitHub Actions cache runtime for vcpkg
        uses: actions/github-script@v8
        with:
          script: |
            core.exportVariable('ACTIONS_CACHE_URL', process.env.ACTIONS_CACHE_URL || '');
            core.exportVariable('ACTIONS_RESULTS_URL', process.env.ACTIONS_RESULTS_URL || '');
            core.exportVariable('ACTIONS_RUNTIME_TOKEN', process.env.ACTIONS_RUNTIME_TOKEN || '');
  ```

- [ ] **Step 7: Run focused speed-setting tests.**

  Run:

  ```bash
  python3 -m pytest \
    scripts/tests/test_windows_ci_speedups.py::test_windows_cross_build_jobs_enable_ninja_sccache_binary_and_vcpkg_cache \
    scripts/tests/test_windows_ci_speedups.py::test_pr_vcpkg_binary_cache_is_read_only_for_pull_requests \
    -q
  ```

  Expected: pass.

- [ ] **Step 8: Commit the workflow speed settings.**

  Commit the workflow and test changes:

  ```bash
  git add .github/workflows/test.yml .github/workflows/build.yml scripts/tests/test_windows_ci_speedups.py
  git commit -m "ci: cache and parallelize Windows cross builds"
  ```

### Task 4: Parallelize the Windows Build Script

**Files:**
- Modify: `scripts/build-windows.sh:18-315`
- Modify: `scripts/tests/test_windows_ci_speedups.py`

**Interfaces:**
- Consumes: optional environment variable `BUILD_JOBS`.
- Produces: `resolve_build_jobs() -> stdout positive integer or exits nonzero`; final CMake build command uses `--parallel "${BUILD_JOBS}"`.

- [ ] **Step 1: Add static tests for `scripts/build-windows.sh`.**

  Append these tests to `scripts/tests/test_windows_ci_speedups.py`:

  ```python
  def test_build_windows_script_builds_targets_in_parallel() -> None:
      script = read_repo_text("scripts/build-windows.sh")

      assert "resolve_build_jobs()" in script
      assert 'BUILD_JOBS="$(resolve_build_jobs)"' in script
      assert "BUILD_JOBS must be a positive integer" in script
      assert 'cmake --build "${BUILD_DIR}" --config Release --parallel "${BUILD_JOBS}" --target space space-cli' in script


  def test_build_windows_script_resets_stale_cache_when_generator_changes() -> None:
      script = read_repo_text("scripts/build-windows.sh")

      assert 'CMAKE_GENERATOR:INTERNAL=${CMAKE_GENERATOR}' in script
      assert 'Resetting ${BUILD_DIR} due to stale CMake cache.' in script
  ```

- [ ] **Step 2: Run the script tests and observe the expected failures.**

  Run:

  ```bash
  python3 -m pytest \
    scripts/tests/test_windows_ci_speedups.py::test_build_windows_script_builds_targets_in_parallel \
    scripts/tests/test_windows_ci_speedups.py::test_build_windows_script_resets_stale_cache_when_generator_changes \
    -q
  ```

  Expected: fail because `scripts/build-windows.sh` does not yet resolve `BUILD_JOBS`, reset on generator changes, or pass `--parallel`.

- [ ] **Step 3: Add `resolve_build_jobs` to `scripts/build-windows.sh`.**

  After the existing top-level variable declarations and before the first `if [ ! -d "${VCPKG_ROOT}" ]` check, add:

  ```bash
  resolve_build_jobs() {
      local jobs="${BUILD_JOBS:-}"
      if [ -z "${jobs}" ]; then
          if command -v nproc >/dev/null 2>&1; then
              jobs="$(nproc)"
          else
              jobs="2"
          fi
      fi

      case "${jobs}" in
          ''|*[!0-9]*|0)
              echo "BUILD_JOBS must be a positive integer; got '${jobs}'." >&2
              exit 1
              ;;
      esac

      printf '%s\n' "${jobs}"
  }
  ```

- [ ] **Step 4: Reset stale CMake cache when the requested generator changes.**

  In the existing `cache_file` block, after the `needs_reset=0` line and before the existing `CMAKE_SYSTEM_NAME` check, add:

  ```bash
      if [ -n "${CMAKE_GENERATOR:-}" ] \
          && grep -q '^CMAKE_GENERATOR:INTERNAL=' "${cache_file}" \
          && ! grep -Fxq "CMAKE_GENERATOR:INTERNAL=${CMAKE_GENERATOR}" "${cache_file}"; then
          needs_reset=1
      fi
  ```

  Keep the existing Windows toolchain and `VCPKG_CHAINLOAD_TOOLCHAIN_FILE` reset checks.

- [ ] **Step 5: Use `BUILD_JOBS` in the final CMake build command.**

  Replace the final build line:

  ```bash
  cmake --build "${BUILD_DIR}" --config Release --target space space-cli
  ```

  with:

  ```bash
  BUILD_JOBS="$(resolve_build_jobs)"
  cmake --build "${BUILD_DIR}" --config Release --parallel "${BUILD_JOBS}" --target space space-cli
  ```

- [ ] **Step 6: Run shell syntax and focused script tests.**

  Run:

  ```bash
  bash -n scripts/build-windows.sh
  python3 -m pytest \
    scripts/tests/test_windows_ci_speedups.py::test_build_windows_script_builds_targets_in_parallel \
    scripts/tests/test_windows_ci_speedups.py::test_build_windows_script_resets_stale_cache_when_generator_changes \
    -q
  ```

  Expected: pass.

- [ ] **Step 7: Commit the build script change.**

  Commit the script and test changes:

  ```bash
  git add scripts/build-windows.sh scripts/tests/test_windows_ci_speedups.py
  git commit -m "build(scripts): parallelize Windows cross builds"
  ```

### Task 5: Update Windows CI Operational Notes

**Files:**
- Modify: `docs/dev/notes/windows-wine-build-and-test.md:47-65`
- Modify: `docs/dev/notes/windows-wine-build-and-test.md:220-278`
- Modify: `docs/dev/notes/windows-wine-build-and-test.md:281-298`
- Modify: `scripts/tests/test_windows_ci_speedups.py`

**Interfaces:**
- Consumes: workflow policy from Tasks 2-4.
- Produces: docs that explain PR validation no longer generates packages, while `build.yml` keeps release/manual packaging.

- [ ] **Step 1: Add a static documentation test.**

  Append this test to `scripts/tests/test_windows_ci_speedups.py`:

  ```python
  def test_windows_wine_notes_document_validation_packaging_boundary_and_speedups() -> None:
      text = read_repo_text("docs/dev/notes/windows-wine-build-and-test.md")

      assert "PR/merge-queue validation path" in text
      assert "does not build the Windows installer" in text
      assert "does not create the release ZIP" in text
      assert "Release/manual packaging path" in text
      assert "existing `workflow_dispatch` behavior remains available" in text
      assert "vcpkg binary caching" in text
      assert "Ninja parallel builds" in text
  ```

- [ ] **Step 2: Run the docs test and observe the expected failure.**

  Run:

  ```bash
  python3 -m pytest scripts/tests/test_windows_ci_speedups.py::test_windows_wine_notes_document_validation_packaging_boundary_and_speedups -q
  ```

  Expected: fail because the notes still describe the old workflow and pending cache work.

- [ ] **Step 3: Update the “Final CI architecture” section.**

  In `docs/dev/notes/windows-wine-build-and-test.md`, update lines around “Final CI shape” so they say:

  ```markdown
  Final CI shape:

  - `test.yml` PR/merge-queue validation path
    - Linux job builds the Windows artifact with `scripts/setup-windows-build-host.sh` + `scripts/build-windows-from-linux.sh`
    - Linux job prepares and uploads only the runtime bundle needed by tests
    - native Windows job downloads that runtime bundle and runs the native Windows fast suite
    - this path does not build the Windows installer and does not create the release ZIP
  - `build.yml` release/manual packaging path
    - Linux job builds the Windows artifact the same way
    - Linux job smoke-tests the Windows binary under Wine
    - Linux job creates the Windows release ZIP
    - native Windows job builds and smoke-tests the installer
    - existing `workflow_dispatch` behavior remains available
  ```

- [ ] **Step 4: Update the Windows build performance notes.**

  Replace the old “current CI uses `ccache`, but ... vcpkg binary caching is the next meaningful optimization” limitation with:

  ```markdown
  - Windows cross-build CI uses `ccache`, `sccache`, GitHub Actions `vcpkg binary caching`, and Ninja parallel builds. The remaining bottlenecks are dependency cache misses, hosted-runner variance, and native Windows runner startup/installer work in the release/manual packaging path.
  ```

  Replace the pending “Windows build performance” bullet list with:

  ```markdown
  4. Windows build performance

  - keep `ccache`, `sccache`, GitHub Actions `vcpkg binary caching`, and Ninja parallel builds enabled for Windows cross-build jobs
  - use `SPACE_TEST_TIMINGS=1` in follow-up investigations if the native Windows fast suite becomes the dominant bottleneck
  - keep release ZIP and installer generation out of PR/merge-queue validation unless a future test directly consumes those package artifacts
  ```

- [ ] **Step 5: Run the docs test.**

  Run:

  ```bash
  python3 -m pytest scripts/tests/test_windows_ci_speedups.py::test_windows_wine_notes_document_validation_packaging_boundary_and_speedups -q
  ```

  Expected: pass.

- [ ] **Step 6: Commit the documentation update.**

  Commit the docs and test changes:

  ```bash
  git add docs/dev/notes/windows-wine-build-and-test.md scripts/tests/test_windows_ci_speedups.py
  git commit -m "docs: describe Windows CI packaging boundary"
  ```

### Task 6: Final Static Validation

**Files:**
- Validate: `.github/workflows/test.yml`
- Validate: `.github/workflows/build.yml`
- Validate: `scripts/build-windows.sh`
- Validate: `scripts/tests/test_windows_ci_speedups.py`
- Validate: `scripts/tests/test_release_artifact_naming.py`
- Validate: `docs/dev/notes/windows-wine-build-and-test.md`

**Interfaces:**
- Consumes: all prior task outputs.
- Produces: validation evidence for workflow/script/docs changes before PR CI runs.

- [ ] **Step 1: Run shell syntax checks.**

  Run:

  ```bash
  bash -n scripts/build-windows.sh scripts/build-windows-from-linux.sh scripts/setup-windows-build-host.sh
  ```

  Expected: pass.

- [ ] **Step 2: Run focused static tests.**

  Run:

  ```bash
  python3 -m pytest \
    scripts/tests/test_windows_ci_speedups.py \
    scripts/tests/test_release_artifact_naming.py::test_workflows_use_new_release_artifact_names \
    scripts/tests/test_windows_build_host_setup.py::test_build_windows_passes_masm_settings_to_cmake_when_env_is_set \
    -q
  ```

  Expected: pass.

- [ ] **Step 3: Run the complete relevant local script-test suite.**

  Run:

  ```bash
  python3 -m pytest scripts/tests -q
  ```

  Expected: pass.

- [ ] **Step 4: Check whitespace and accidental conflict markers.**

  Run:

  ```bash
  git diff --check
  rg '<<<<<<<|=======|>>>>>>>' .github/workflows scripts/tests scripts/build-windows.sh docs/dev/notes/windows-wine-build-and-test.md
  ```

  Expected: `git diff --check` exits 0 and `rg` finds no conflict markers.

- [ ] **Step 5: Inspect the final workflow diff.**

  Confirm these facts in the diff:

  - `.github/workflows/test.yml` has no `build-windows-installer` job.
  - `.github/workflows/test.yml` still has `test-windows` on `windows-latest` running `tests.fast:main`.
  - `.github/workflows/test.yml` no longer creates `space-windows-x86_64.zip` or uploads `windows-packaging-inputs`.
  - `.github/workflows/build.yml` still creates `space-windows-x86_64.zip`.
  - `.github/workflows/build.yml` still has `build-windows-installer`.
  - Existing `workflow_dispatch` behavior in `.github/workflows/build.yml` is unchanged.
  - Both Windows cross-build jobs use `CMAKE_GENERATOR: Ninja`, vcpkg binary caching, sccache binary restore/install, and GitHub Actions cache runtime export.

## Acceptance Criteria

- PR/push/merge-group `test.yml` no longer runs or defines `build-windows-installer`.
- PR/push/merge-group `test.yml` keeps native Windows `test-windows` fast-suite coverage.
- PR/push/merge-group `test.yml` no longer creates or uploads `space-windows-x86_64.zip`.
- PR/push/merge-group `test.yml` no longer uploads `windows-packaging-inputs`.
- `build.yml` still builds the Windows runtime ZIP and Windows installer for release/manual packaging paths.
- Existing `workflow_dispatch` behavior in `build.yml` remains unchanged.
- Windows cross-build jobs use Ninja and CMake parallel build execution.
- Windows cross-build jobs configure GitHub Actions vcpkg binary caching safely, with pull requests read-only in `test.yml`.
- Static tests document and enforce the new CI/release packaging boundary.
- `docs/dev/notes/windows-wine-build-and-test.md` describes the new operational policy.
- PR CI remains the full integration gate.

## Validation Ladder

1. Focused checks during implementation:
   - `bash -n scripts/build-windows.sh scripts/build-windows-from-linux.sh scripts/setup-windows-build-host.sh`
   - `python3 -m pytest scripts/tests/test_windows_ci_speedups.py -q`
   - `python3 -m pytest scripts/tests/test_release_artifact_naming.py::test_workflows_use_new_release_artifact_names -q`
2. Complete relevant local suite:
   - `python3 -m pytest scripts/tests -q`
3. Static hygiene:
   - `git diff --check`
   - `rg '<<<<<<<|=======|>>>>>>>' .github/workflows scripts/tests scripts/build-windows.sh docs/dev/notes/windows-wine-build-and-test.md`
4. Remote integration:
   - PR CI is the full integration gate.

## Out of Scope

- Running a full local Windows cross-build or installer build as validation.
- Removing or weakening native Windows `test-windows` fast-suite coverage.
- Removing Windows ZIP or installer artifacts from release/manual packaging workflows.
- Changing `make release`.
- Changing existing `.github/workflows/build.yml` `workflow_dispatch` behavior.
- Changing package names, installer metadata, vcpkg ports, triplets, or dependency versions.
- Reworking unrelated Linux CI jobs.

## Self-Review

- Spec coverage: every requirement from `docs/specs/2026-10-08-windows-ci-speedups-design.md` maps to Tasks 1-6.
- Placeholder scan: no TBD/TODO/implement-later placeholders remain; all code/test snippets are explicit.
- Type consistency: helper names `read_repo_text` and `load_workflow` are introduced once and reused consistently.
