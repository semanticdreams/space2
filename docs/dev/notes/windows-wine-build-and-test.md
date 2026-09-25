---
type: dev-note
tags:
  - note
---

# Windows Build + Wine Validation Notes

This document summarizes the Windows build and Wine validation work completed in this cycle, including decisions, trade-offs, known limitations, and follow-up work.

## Scope

Goals covered:

- make Windows build scripts match current dependency/build setup
- make the setup reproducible on other Linux machines
- validate Windows artifacts under Wine
- keep Windows coverage as high as possible in `tests.fast`, with explicit and minimal skips
- keep optional modules (notably libtorrent and ffmpeg) enabled by default for Windows
- align local Windows-from-Linux builds and CI as closely as practical
- replace the unstable Windows-host MinGW CI path with the Linux cross-build path

## What Changed

### 1) Reproducible Windows-from-Linux toolchain flow

Added/updated scripts:

- `scripts/setup-windows-build-host.sh`
- `scripts/build-windows-from-linux.sh`
- `scripts/build-windows.sh`
- `scripts/prepare-windows-runtime.sh`
- `scripts/prepare-windows-wine-runtime.sh`
- `scripts/test-windows-under-wine.sh`
- `scripts/build-wine-bcryptprimitives-mock.sh`
- `scripts/vcpkg-triplets/*`
- `scripts/vcpkg-ports/openal-soft/portfile.cmake`

Result:

- one-time host setup is isolated
- build and test steps are repeatable across machines
- Wine runtime prep resolves/copies dependent DLLs automatically and stages `matrix.dll` when present
- local and CI Windows builds now share the same core build entrypoint (`scripts/build-windows.sh`)
- `scripts/build-windows.sh` uses `vcpkg install --recurse` so local cross-builds also work on non-pristine machines

### 1.1) Final CI architecture

The original attempt used a native Windows-host MinGW build in GitHub Actions. That path turned out to be the least stable part of the system:

- repeated upstream vcpkg/MinGW resource compilation failures
- Windows-host tool naming/path mismatches
- long failure cycles with poor feedback

Final CI shape:

- `test.yml`
  - Linux job builds the Windows artifact with `scripts/setup-windows-build-host.sh` + `scripts/build-windows-from-linux.sh`
  - Linux job prepares a runtime bundle with `scripts/package-windows-runtime.sh`
  - Windows job downloads that runtime bundle and runs the native Windows fast suite
- `build.yml`
  - Linux job builds the Windows artifact the same way
  - Linux job smoke-tests the Windows binary under Wine
  - Linux job packages the Windows release payload

Why this architecture was chosen:

- it matches the already-working local Windows-from-Linux build path
- it removes the least reliable environment (Windows-host MinGW dependency builds) from CI
- it still keeps native Windows runtime validation in CI, which matters for production confidence

### 2) Windows feature/dependency defaults

Final policy for Windows build:

- `libtorrent`: enabled by default
- `ffmpeg`: enabled by default
- `cef`: not available on Windows in current codebase (Linux-only integration path)

Notes:

- libtorrent package naming:
  - upstream library: **libtorrent-rasterbar**
  - vcpkg package name used here: `libtorrent`
  - Fennel/Lua module exposed by engine: `libtorrent`
  - these refer to the same underlying library integration in this project context

### 3) Runtime fixes for Windows/Wine execution

- implemented Windows process backend in `src/lua_process_windows.cpp` (instead of unsupported stubs)
- added Windows shell/process support (`src/lua_shell_windows.cpp` and runtime wiring)
- added Wine `bcryptprimitives.dll` workaround path for environments missing it
- fixed OpenAL driver defaults in `src/audio.cpp`:
  - Windows default drivers: `dsound,wave`
  - Linux default drivers: `pipewire,pulse,alsa`

This removed Wine startup noise/failure pattern:

- previous: `Failed to open OpenAL device.`
- now: Windows binary under Wine initializes audio without forcing Linux backends

### 4) Test architecture and skip policy

Windows skip policy is centralized in:

- `assets/lua/tests/runner.fnl`

Key design:

- keep module-level skips explicit and minimal
- keep feature-level skips local to tests when appropriate (using existing skip idioms)
- avoid broad blanket skips unless technically required

Important refactor:

- moved the input external-editor integration test from `test-input` to `test-external-editor`
- unskipped `test-input` on Windows
- left `test-external-editor` skipped on Windows (shell-dependent `sh` behavior)

Files:

- `assets/lua/tests/test-input.fnl`
- `assets/lua/tests/test-external-editor.fnl`

Stability tweak:

- input context-menu clipboard assertions now use a local clipboard stub in test code to avoid Wine clipboard flakiness while still validating behavior.

Additional cleanup:

- terminal widget tests now restore their terminal stub correctly even if a test body throws
- terminal widget tests that assert raw grid or pointer behavior explicitly set `:frame-padding 0` instead of depending on old implicit layout assumptions

### 5) Kernel subprocess expectations under Wine

- `tests.test-kernels` subprocess integration remains skipped on Windows/Wine due Python runtime availability in Wine environments used for CI-style validation.
- this is an environment constraint, not a product-direction decision about kernel support in principle.

## Decisions and Trade-offs

1. Prioritize real Windows support over broad test exclusion

- decision: implement Windows process/shell support rather than skip whole suites
- trade-off: higher implementation effort now, much better long-term coverage and confidence

2. Keep skips explicit and centralized

- decision: define module-level Windows skips in `tests/runner.fnl`
- trade-off: slightly more maintenance in one list, but much easier to audit and reduce over time

3. Separate shell-integration tests from core widget behavior

- decision: external-editor path moved out of `test-input`
- trade-off: one extra module, but clearer ownership and platform handling

4. Reproducibility over ad-hoc local fixes

- decision: script host setup/build/runtime prep instead of manual commands
- trade-off: more scripts to maintain, but repeatable onboarding and CI/dev parity

4.1. Prefer the stable build environment over the nominally native one

- decision: build Windows artifacts on Linux in CI instead of building them on a Windows host
- trade-off: native Windows no longer compiles the dependency graph in CI, but native Windows still validates the produced artifact
- rationale: production confidence comes from reproducible builds plus native runtime validation, not from forcing the least stable host/toolchain combination through every dependency build

5. Wine-specific compatibility shim (`bcryptprimitives.dll`)

- decision: include mock-path support for Wine where needed
- trade-off: additional moving part only for Wine validation; native Windows remains the source of truth for actual platform behavior

## Problems Encountered and Resolutions

1. Matrix DLL discovery/runtime path mismatch

- symptom: matrix-related runtime loading issues for Windows artifact runs
- resolution: CMake copies the Rust artifact into the build tree, and `scripts/prepare-windows-runtime.sh` stages `matrix.dll` from there alongside the dependency scan

2. OpenAL device open failures under Wine

- symptom: `Failed to open OpenAL device.`
- root cause: Windows build forced Linux OpenAL drivers
- resolution: Windows driver defaults switched to `dsound,wave` in `src/audio.cpp`

3. Input suite failing under Wine after unskip

- symptom: clipboard assertions flaky/failing under Wine
- resolution: use test-local clipboard stub in `test-input` context-menu tests

4. External editor integration in mixed suite

- symptom: shell-dependent behavior caused platform-specific instability in `test-input`
- resolution: moved that case into `test-external-editor`, keep module skip on Windows

5. Windows-host MinGW CI instability

- symptom: repeated failures in upstream MinGW/vcpkg dependency builds on Windows-host CI
- root causes included:
  - resource compiler (`.rc`) failures in several upstream ports
  - tool-discovery and prefixed-bin naming mismatches
  - slow iteration loop with poor signal
- resolution: pivot CI to Linux cross-build for Windows artifacts, keep native Windows only for runtime validation

6. Terminal fast-suite regressions after unrelated CI iteration

- symptom: Linux `space_fnl_tests` started failing in terminal widget/scrollback tests
- root cause:
  - one terminal widget test had an outdated layout expectation after default frame padding changes
  - test helper `with-terminal-stub` leaked the stubbed terminal binding when a test failed, contaminating later terminal tests
- resolution:
  - make the helper restore the original binding even on failure
  - make raw grid/pointer tests opt into `:frame-padding 0`

7. `llm-tools bash runs command` Linux CI timeout

- symptom: bash integration test timed out in CI (`exit_code=143`, `timed_out=true`)
- root cause: test timeout margin was too tight for loaded CI runners
- resolution: widen the test timeout from `3` to `10` seconds for the bash tool integration checks

## Current Known Limitations

- CEF is still Linux-only in current engine integration path.
- `test-external-editor` remains skipped on Windows due shell-command assumptions (`sh`-driven behavior).
- kernel subprocess integration test is skipped on Windows/Wine test environments lacking Python runtime.
- Wine is validation support, not a complete substitute for native Windows verification.
- current CI uses `ccache`, but the main remaining Windows build time bottleneck is likely outside cacheable compilation; `vcpkg` binary caching is the next meaningful optimization, not more `ccache` tuning alone.

## Validation Snapshot

Validated in this cycle:

Linux / CI:

- `test.yml` green with:
  - Linux `test`
  - Linux `build-windows`
  - native Windows `test-windows`

Local:

- local Windows cross-build from Linux succeeded
- focused Linux `tests.test-llm-tools:main` succeeded after timeout fix
- focused terminal runner path covering:
  - `tests.test-terminal-widget`
  - `tests.test-terminal-renderer`
  - `tests.test-terminal-scrollback`
  - all passed after test helper/layout fixes

Windows binary under Wine:

- `tests.test-process:main` passing
- `tests.test-input:main` passing after refactor
- `tests.fast:main` passing with current explicit Windows skip policy
- audio smoke path no longer emits OpenAL device-open failure after driver fix

## Pending Work

1. Native Windows verification pass

- keep running the native Windows fast suite in CI
- later, validate release/workflow parity in `build.yml` on manual dispatch or tagged release

2. Reduce skip surface further

- revisit `test-external-editor` for Windows-friendly editor harness (no `sh` assumptions)
- re-evaluate remaining module skips over time (`terminal`, `ripgrep`, `flamegraph`, `llm-tools`) as platform support improves

3. CEF Windows implementation

- implement Windows platform handler in CEF setup/runtime path
- add Windows packaging/runtime asset flow for CEF payload

4. Windows build performance

- add `ccache -z` before CI builds so per-run cache stats are meaningful
- add `vcpkg` binary caching for the Linux Windows cross-build path
- keep `ccache`, but do not expect it alone to materially change total Windows build time

## Reproducible Workflow (Current)

For OpenCode Windows CI failure reproduction, use the guarded wrapper sequence:

```bash
python3 scripts/opencode_windows_ci_repro.py preflight --repo-root .
python3 scripts/opencode_windows_ci_repro.py setup-host --repo-root .
python3 scripts/opencode_windows_ci_repro.py reproduce --repo-root .
```

Run `setup-host` only when prerequisite evidence says the host needs it. The
wrapper is intended to reproduce `build-windows`, `test-windows`, and
`build-windows-installer` failures locally with a Linux cross-build + Wine loop
before another push. Wine validation is not a substitute for native Windows CI;
native Windows CI remains authoritative for Windows-host-only behavior,
installer behavior, and final integration.

Host setup:

```bash
scripts/setup-windows-build-host.sh
```

Build Windows artifacts from Linux:

```bash
scripts/build-windows-from-linux.sh
```

Prepare native Windows runtime payload (for packaging):

```bash
scripts/package-windows-runtime.sh
```

Run Windows fast suite under Wine:

```bash
scripts/test-windows-under-wine.sh
```

Run a specific module under Wine:

```bash
SPACE_TEST_MODULE=tests.test-input:main scripts/test-windows-under-wine.sh
```


## See also

- [Cross Platform](/dev/subsystems/cross-platform)
