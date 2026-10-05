# SSH Real Backend Validation and Examples Design

## Summary

The SSH foundation now exists, but follow-up work is needed to close the gap
between optional local builds and required integration confidence. This design
makes real `libssh` validation mandatory in Linux PR CI, wires platform
dependency expectations for Linux/macOS/Windows, and adds tested SDK examples so
Space app authors can use SSH without reverse-engineering the implementation.

SSH remains optional for normal local builds: if `libssh` is absent, the module
continues to compile and returns structured `unavailable-backend` errors. CI,
however, must prove the real backend on Linux by installing `libssh` and OpenSSH
fixture tools and by failing if the SSH fixture or backend is unavailable.

## Goals

- Make Linux PR CI run real `libssh` + disposable OpenSSH fixture validation.
- Keep local builds without `libssh` working through the existing unavailable
  backend.
- Add Linux dependency packages to the documented CI dependency block used by
  workflows.
- Wire Windows cross-build dependency requests through vcpkg for `libssh` and
  verify the pkg-config module before CMake configuration.
- Document dependency expectations for Linux, macOS/Homebrew, and Windows/vcpkg.
- Add an indexed SDK SSH module page with copyable examples for low-level SSH
  exec and fleet execution.
- Back the documented examples with focused tests.

## Non-goals

- No macOS CI workflow in this slice.
- No native Windows real OpenSSH fixture test in this slice.
- No custom vcpkg overlay port for `libssh` without a later human decision.
- No new product features such as jump hosts, SCP, rsync, server mode, or UI
  onboarding.
- No public SSH API key renames or compatibility aliases.

## Existing Context

- `CMakeLists.txt` currently discovers `libssh` with pkg-config and falls back to
  a structured unavailable backend when absent.
- Linux CI installs packages by extracting the `CI_DEPS` block from
  `docs/dev/building.md`; that block does not yet include `libssh-dev` or
  OpenSSH server tooling.
- Windows cross-build dependencies are controlled by `scripts/build-windows.sh`
  `VCPKG_PACKAGES` and pkg-config preflight lists; `libssh` is not currently in
  either list.
- `tests/ssh_fixture.py` already creates a disposable localhost `sshd` fixture
  and skips when fixture tools are missing.
- `assets/lua/tests/test-ssh-integration.fnl` already skips when fixture env vars
  are absent or when the backend reports `unavailable-backend`.
- `docs/dev/subsystems/ssh.md` documents the SSH subsystem, but there is no
  `docs/sdk/modules/ssh.md` page for app authors.

## Evaluated Approaches

### Option A: Documentation-only dependency update

This is low risk but insufficient. CI could continue to pass via fixture/backend
skips, leaving the primary `libssh` backend unproven. Rejected.

### Option B: Full cross-platform real SSH validation immediately

This would add Linux, macOS, and Windows real-backend CI at once. It offers the
strongest confidence, but macOS CI does not currently exist and native Windows
fixture behavior is larger than a dependency-wiring follow-up. Rejected for this
slice.

### Option C: Mandatory Linux real backend, platform dependency wiring, tested docs

This keeps local optionality, makes Linux PR CI prove the primary backend, wires
Windows build dependencies through the existing vcpkg path, and documents macOS
dependencies without adding new CI. This is selected.

## Design

### Linux CI real-backend gate

Add `libssh-dev`, `openssh-server`, and `openssh-client` to the `CI_DEPS` block
in `docs/dev/building.md`. The existing test workflow reads that block, so Linux
CI will install the backend and fixture dependencies without duplicating package
lists in workflow YAML.

Add two opt-in strictness environment variables:

- `SPACE_TEST_REQUIRE_SSH_FIXTURE=1`: `tests/ssh_fixture.py` fails instead of
  skipping when fixture tools are missing.
- `SPACE_TEST_REQUIRE_SSH_BACKEND=1`: `test-ssh-integration.fnl` fails instead
  of skipping when SSH reports `unavailable-backend`.

Set both variables on the Linux test workflow so PR CI cannot silently pass
without real SSH coverage. Keep defaults permissive for developer machines.

### Windows dependency wiring

Add `libssh` to `scripts/build-windows.sh` default `VCPKG_PACKAGES` and to the
pkg-config preflight list. This makes the Windows cross-build request `libssh`
through the existing vcpkg mechanism and fail early if the package does not
provide the expected pkg-config module.

If vcpkg cannot provide usable `libssh` for the current triplet, stop with
`HUMAN_DECISION_REQUIRED` rather than adding a custom overlay port in this slice.

### macOS dependency documentation

Document Homebrew `libssh` as the expected macOS dependency path. No macOS CI is
added here.

### Tested SDK examples

Create `docs/sdk/modules/ssh.md` following the existing SDK module style:
canonical import, source files, what it provides, API summary, examples,
security/error notes, related modules, and search aliases.

Include at least:

- low-level connect/exec with callback/event handling and known-host policy;
- fleet exec using `ssh.fleet` with bounded concurrency and structured results.

Tests should include named coverage that corresponds to these examples:

- real-fixture low-level connect/exec example in `test-ssh-integration.fnl`,
  which still skips locally when fixture/backend requirements are absent unless
  strict CI env vars are set;
- fake-transport fleet example in `test-ssh-fleet.fnl`.

## Error Handling

- Strict CI mode reports explicit errors when fixture tools or real backend are
  unavailable.
- Local default mode preserves clear skip messages for missing fixture tools or
  unavailable backend.
- Windows dependency checks fail early during build setup if `libssh` is missing
  from pkg-config after vcpkg installation.
- Examples must not include credential literals, secrets, or compatibility key
  aliases.

## Testing

- Compile/build freshness: `make build` when direct `./build/space` checks are
  used.
- Fennel compile: `make fennel-check`.
- Constraints: `make constraints`.
- Focused Fennel tests: `tests.test-ssh`, `tests.test-ssh-fleet`, and
  `tests.test-ssh-integration`.
- Fixture CTest: `space_ssh_integration`, with strict env vars in CI.
- Script syntax checks: `python3 -m py_compile tests/ssh_fixture.py` and
  `bash -n scripts/build-windows.sh`.
- Full local suite because workflows/tests/build docs are changing: standard
  `make test` command with test hygiene env vars.
- Windows cross-build validation when vcpkg/Wine environment is available.

## Acceptance Criteria

- Linux PR CI installs `libssh-dev`, `openssh-server`, and `openssh-client` from
  the documented CI dependency block.
- Linux PR CI fails if SSH fixture dependencies are unavailable or if SSH reports
  `unavailable-backend`.
- Local builds/tests without `libssh` still pass through structured unavailable
  backend behavior and default fixture skips.
- Windows cross-build scripts request `libssh` through vcpkg and require a
  `libssh` pkg-config module.
- SSH subsystem/build docs document Linux, macOS, and Windows dependency paths.
- `docs/sdk/modules/ssh.md` exists, is indexed, and contains examples covered by
  named tests.
