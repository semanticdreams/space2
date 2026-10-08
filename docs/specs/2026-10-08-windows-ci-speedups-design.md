# Windows CI Speedups Design

## Goal

Speed up Windows CI while preserving Windows runtime confidence and release packaging guarantees.

## Context

The current `test.yml` PR/merge-queue workflow performs Windows validation and packaging work in the same path:

- Linux cross-builds the Windows runtime.
- Native Windows downloads that runtime and runs `tests.fast:main`.
- The PR workflow also creates a Windows ZIP, uploads packaging inputs, and runs a native Windows installer job.

That makes normal PR validation pay release-packaging costs. The release workflow, `.github/workflows/build.yml`, already owns package generation for tag pushes created by `make release`, and `workflow_dispatch` remains an acceptable manual release/build path. The PR workflow only needs enough Windows artifact staging to execute the native Windows fast suite.

## Design Direction

Separate validation from packaging:

- `test.yml` is the validation workflow for PRs, pushes to `main`, and merge queue.
- `build.yml` remains the packaging/release workflow for `make release` tag pushes and existing manual `workflow_dispatch` use.
- Windows installer generation stays out of PR/merge-queue CI.
- Windows ZIP/release packaging input generation stays out of PR/merge-queue CI unless a test directly consumes it; the current native Windows test job consumes only the staged runtime directory.

## Components

### PR / merge-queue workflow: `.github/workflows/test.yml`

The Windows PR path keeps:

- Linux `build-windows` cross-build.
- Runtime staging with `scripts/package-windows-runtime.sh`.
- Runtime smoke checks needed to ensure `space.exe` and `space-cli.exe` are valid.
- Upload of `space-windows-runtime` for the native Windows job.
- Native Windows `test-windows` job running `space-cli.exe -m tests.fast:main`.

The Windows PR path removes:

- Windows ZIP creation.
- Windows ZIP verification.
- `windows-packaging-inputs` upload.
- `build-windows-installer` job.

### Release/manual packaging workflow: `.github/workflows/build.yml`

The release workflow keeps existing package generation behavior:

- Linux release artifacts.
- Windows runtime ZIP.
- Windows installer generation and smoke test.
- GitHub Release uploads on tag builds.
- Existing `workflow_dispatch` behavior remains in place.

No release artifact is removed or renamed.

### Windows cross-build speed settings

Both Windows cross-build jobs (`test.yml` and `build.yml`) should use the same speed-oriented configuration:

- `CMAKE_GENERATOR: Ninja`, because `scripts/setup-windows-build-host.sh` already installs `ninja-build` and `scripts/build-windows.sh` already passes `CMAKE_GENERATOR` through to CMake.
- Parallel CMake build execution in `scripts/build-windows.sh`, with `BUILD_JOBS` defaulting to `nproc` and validating positive integer input.
- A reliable `sccache` binary install/restore path for Windows cross-build jobs so the existing `.sccache-windows` cache can actually be used by the Rust matrix build.
- GitHub Actions vcpkg binary caching to avoid rebuilding expensive vcpkg packages when inputs are unchanged. For `test.yml`, pull requests should use read-only vcpkg cache access; trusted push/merge-group contexts may use read-write. `build.yml` may use read-write.

### Static policy tests

Because full Windows builds and installer generation are not suitable local validation for this change, static tests should enforce the intended policy:

- `test.yml` has no `build-windows-installer` job.
- `test.yml` does not create/upload Windows release ZIP or packaging inputs.
- `test.yml` still has native Windows fast-suite coverage.
- `build.yml` still contains Windows ZIP and installer generation.
- Windows cross-build jobs expose Ninja, sccache binary restore/install, and vcpkg binary-cache configuration.
- `scripts/build-windows.sh` invokes CMake with `--parallel`.

## Data / Artifact Flow

PR and merge queue:

1. Linux cross-build creates `build/windows/space.exe` and `build/windows/space-cli.exe`.
2. Runtime staging creates `build/dist/windows`.
3. `space-windows-runtime` is uploaded.
4. Native Windows downloads `space-windows-runtime`.
5. Native Windows runs `tests.fast:main` from the staged runtime.

Release/manual packaging:

1. `build.yml` cross-builds Windows runtime.
2. `build.yml` creates `space-windows-x86_64.zip`.
3. `build.yml` uploads packaging inputs for the installer job.
4. Native Windows installer job builds and smoke-tests `space-windows-x86_64-setup.exe`.
5. Tag releases upload ZIP and installer to GitHub Release.

## Error Handling

- Windows PR failures in `build-windows` or `test-windows` continue to route through the guarded Windows CI reproduction path.
- Installer failures are release/manual packaging failures, not PR/merge-queue validation failures. They should be diagnosed from `build.yml` logs and fixed through the normal implementer/reviewer flow.
- vcpkg cache configuration must not allow untrusted pull requests to write to the shared GitHub Actions binary cache.
- `scripts/build-windows.sh` should fail fast with a clear error if `BUILD_JOBS` is not a positive integer.

## Testing Strategy

Local validation should focus on static and script-level checks:

- New/updated pytest checks under `scripts/tests/` for workflow policy.
- `bash -n` for touched shell scripts.
- Existing script tests that cover workflow naming, Windows setup assumptions, and OpenCode Windows CI policy docs.
- `git diff --check` and conflict-marker scan.

Full confidence comes from PR CI: the Linux cross-build job and native Windows fast-suite job remain the integration gate.

## Acceptance Criteria

- `test.yml` no longer defines or runs `build-windows-installer`.
- `test.yml` no longer creates Windows release ZIPs or uploads `windows-packaging-inputs`.
- `test.yml` still runs native Windows `tests.fast:main` from the cross-built runtime.
- `build.yml` still builds Windows ZIP and installer artifacts for release/manual packaging paths.
- Both Windows cross-build jobs use Ninja, vcpkg binary caching, and a reliable sccache binary setup.
- `scripts/build-windows.sh` builds in parallel by default.
- Static tests enforce the workflow boundary so packaging work does not drift back into PR CI unnoticed.

## Self-Review

- Placeholder scan: no placeholders or deferred decisions remain.
- Internal consistency: validation workflow and packaging workflow are separated consistently across artifact flow, tests, and acceptance criteria.
- Scope check: this is one focused workflow/script/docs change set; no C++/Fennel runtime changes are included.
- Ambiguity check: `workflow_dispatch` remains untouched in `build.yml` per user instruction; release/manual packaging behavior is preserved there.
