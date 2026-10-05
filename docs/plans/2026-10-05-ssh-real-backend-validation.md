# SSH Real Backend Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Linux CI prove the real SSH backend, wire platform dependency expectations, and add tested SDK SSH examples.

**Architecture:** Keep SSH optional for normal local builds, but enable strict real-backend validation in Linux PR CI with opt-in environment variables. Use existing dependency authorities (`docs/dev/building.md` for Ubuntu CI packages and `scripts/build-windows.sh` for vcpkg) rather than duplicating package lists. Add SDK documentation whose examples map to named Fennel tests.

**Tech Stack:** CMake, GitHub Actions, pkg-config `libssh`, OpenSSH fixture tools, vcpkg, Fennel tests, Space SDK docs.

## Global Constraints

- SSH remains optional for normal local builds: if `libssh` is absent, the module continues to compile and returns structured `unavailable-backend` errors.
- CI must prove the real backend on Linux by installing `libssh` and OpenSSH fixture tools and by failing if the SSH fixture or backend is unavailable.
- No macOS CI workflow in this slice.
- No native Windows real OpenSSH fixture test in this slice.
- No custom vcpkg overlay port for `libssh` without a later human decision.
- No new product features such as jump hosts, SCP, rsync, server mode, or UI onboarding.
- No public SSH API key renames or compatibility aliases.
- Examples must not include credential literals, secrets, or compatibility key aliases.
- Fennel work must follow Space validation order: compile check first, constraints second, focused Fennel tests third.
- PR CI is the full integration gate.

---

## File Structure

- Modify `docs/dev/building.md`: Linux CI dependency block, Windows vcpkg notes, macOS/Homebrew dependency note.
- Modify `.github/workflows/test.yml`: strict SSH fixture/backend env for Linux test step only.
- Modify `tests/ssh_fixture.py`: optional strict fixture requirement env.
- Modify `assets/lua/tests/test-ssh-integration.fnl`: optional strict backend requirement and named SDK low-level example test.
- Modify `scripts/build-windows.sh`: default vcpkg packages and pkg-config required module list include `libssh`.
- Modify `docs/dev/subsystems/ssh.md`: platform dependency notes and SDK docs link.
- Create `docs/sdk/modules/ssh.md`: SDK SSH module reference and examples.
- Modify `docs/sdk/modules/index.md`: add SSH under Networking and services.
- Modify `assets/lua/tests/test-ssh-fleet.fnl`: named SDK fleet example coverage.

## Acceptance Criteria

- Linux PR CI installs `libssh-dev`, `openssh-server`, and `openssh-client` via the documented CI dependency block.
- Linux PR CI fails if SSH fixture dependencies are unavailable or if SSH reports `unavailable-backend`.
- Local default behavior still skips cleanly when fixture tools or `libssh` are absent.
- Windows cross-build script requests `libssh` through vcpkg and verifies pkg-config module `libssh` before CMake.
- Linux/macOS/Windows SSH dependencies are documented.
- `docs/sdk/modules/ssh.md` is indexed and examples are backed by named tests.

---

### Task 1: Linux CI Strict Real-Backend Gate

**Files:**
- Modify: `docs/dev/building.md`
- Modify: `.github/workflows/test.yml`
- Modify: `tests/ssh_fixture.py`
- Modify: `assets/lua/tests/test-ssh-integration.fnl`

**Interfaces:**
- Consumes: existing CTest target `space_ssh_integration`; existing fixture env vars `SPACE_TEST_SSH_HOST`, `SPACE_TEST_SSH_PORT`, `SPACE_TEST_SSH_USER`, `SPACE_TEST_SSH_KEY`, `SPACE_TEST_SSH_KNOWN_HOSTS`, `SPACE_TEST_SSH_ROOT`.
- Produces: `SPACE_TEST_REQUIRE_SSH_FIXTURE=1` and `SPACE_TEST_REQUIRE_SSH_BACKEND=1` strict modes.

- [ ] **Step 1: Add RED fixture strict-mode tests**
  - Add Python-level or subprocess test coverage in `tests/ssh_fixture.py` for missing fixture tools when `SPACE_TEST_REQUIRE_SSH_FIXTURE=1`.
  - Expected strict behavior: exit nonzero and print `ERROR space_ssh_integration:`.
  - Expected default behavior: exit zero and print `SKIP space_ssh_integration:`.

- [ ] **Step 2: Add RED backend strict-mode test in Fennel**
  - Update `assets/lua/tests/test-ssh-integration.fnl` so unavailable backend handling can be exercised with `SPACE_TEST_REQUIRE_SSH_BACKEND=1`.
  - Expected strict behavior: unavailable backend raises/fails the test with a message naming `unavailable-backend`.
  - Expected default behavior: unavailable backend prints the existing skip message and passes.

- [ ] **Step 3: Run RED validation**
  - Run `python3 -m py_compile tests/ssh_fixture.py`.
  - Run focused Fennel compile check for `assets/lua/tests/test-ssh-integration.fnl` after ensuring `make build` freshness if needed.
  - Run the focused integration module without fixture env to confirm default skip still passes.

- [ ] **Step 4: Implement fixture strict mode**
  - In `tests/ssh_fixture.py`, read `SPACE_TEST_REQUIRE_SSH_FIXTURE`.
  - Missing `sshd`, `ssh-keygen`, or `ssh-keyscan` should return zero only when strict mode is off.
  - Missing fixture tools in strict mode should return nonzero with `ERROR space_ssh_integration: missing required fixture tool: <tool-list>`.

- [ ] **Step 5: Implement backend strict mode**
  - In `assets/lua/tests/test-ssh-integration.fnl`, read `SPACE_TEST_REQUIRE_SSH_BACKEND`.
  - When backend is unavailable and strict mode is off, keep the current skip behavior.
  - When backend is unavailable and strict mode is on, fail loudly with a message containing `unavailable-backend` and `SPACE_TEST_REQUIRE_SSH_BACKEND`.

- [ ] **Step 6: Add Linux CI dependencies and strict env**
  - Add `libssh-dev`, `openssh-server`, and `openssh-client` to the `CI_DEPS` block in `docs/dev/building.md`.
  - Set `SPACE_TEST_REQUIRE_SSH_FIXTURE=1` and `SPACE_TEST_REQUIRE_SSH_BACKEND=1` on the Linux test workflow step in `.github/workflows/test.yml` that runs the test suite.

- [ ] **Step 7: Run GREEN validation**
  - Run `python3 -m py_compile tests/ssh_fixture.py`.
  - Run `make build` with timeout `14400000` if `./build/space` may be stale.
  - Run compile check first:
    ```bash
    ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-ssh-integration.fnl
    ```
  - Run constraints second:
    ```bash
    make constraints
    ```
  - Run focused default integration test third:
    ```bash
    SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-ssh-integration:main
    ```
  - If local `libssh` and OpenSSH fixture tools are available, also run:
    ```bash
    SPACE_TEST_REQUIRE_SSH_FIXTURE=1 SPACE_TEST_REQUIRE_SSH_BACKEND=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ctest --test-dir build -R space_ssh_integration --output-on-failure -V
    ```
  - If local `libssh` is unavailable, report that strict real-backend validation is deferred to Linux PR CI.

- [ ] **Step 8: Commit Task 1**
  ```bash
  git add docs/dev/building.md .github/workflows/test.yml tests/ssh_fixture.py assets/lua/tests/test-ssh-integration.fnl
  git commit -m "test(ssh): require real backend in Linux CI"
  ```

---

### Task 2: Windows Dependency Wiring and Platform Docs

**Files:**
- Modify: `scripts/build-windows.sh`
- Modify: `docs/dev/building.md`
- Modify: `docs/dev/subsystems/ssh.md`

**Interfaces:**
- Consumes: `VCPKG_PACKAGES`, `required_pc_modules`, CMake `pkg_check_modules(LIBSSH IMPORTED_TARGET libssh)`.
- Produces: Windows cross-build requests vcpkg package `libssh` and requires pkg-config module `libssh`.

- [ ] **Step 1: Add RED script checks**
  - Add or update script/docs checks so `scripts/build-windows.sh` is expected to contain `libssh` in both default `VCPKG_PACKAGES` and the pkg-config required module list.
  - If no script test harness exists, document the explicit grep checks in the task report and run them before implementation to show failure.

- [ ] **Step 2: Wire Windows vcpkg dependency**
  - Add `libssh` to the default `VCPKG_PACKAGES` in `scripts/build-windows.sh`.
  - Add `libssh` to `required_pc_modules` in `scripts/build-windows.sh`.
  - Preserve user override behavior for `VCPKG_PACKAGES`.

- [ ] **Step 3: Document platform dependencies**
  - In `docs/dev/building.md`, document Linux package names, macOS/Homebrew `libssh`, and Windows/vcpkg `libssh`.
  - In `docs/dev/subsystems/ssh.md`, add a dependency section covering Linux `libssh-dev` + OpenSSH tools, macOS `brew install libssh`, and Windows vcpkg `libssh`.
  - State that macOS has docs only in this slice and no macOS CI.

- [ ] **Step 4: Validate script and docs changes**
  - Run:
    ```bash
    bash -n scripts/build-windows.sh
    ```
  - Run grep checks for `libssh` in the vcpkg package list and `required_pc_modules`.
  - If a Windows vcpkg/Wine environment is available, run the guarded Windows CI reproducer preflight/reproduction through `windows-ci-reproducer`; if vcpkg cannot provide `libssh`, report `HUMAN_DECISION_REQUIRED` with wrapper evidence.

- [ ] **Step 5: Commit Task 2**
  ```bash
  git add scripts/build-windows.sh docs/dev/building.md docs/dev/subsystems/ssh.md
  git commit -m "build(ssh): wire platform libssh dependencies"
  ```

---

### Task 3: Tested SDK SSH Examples

**Files:**
- Create: `docs/sdk/modules/ssh.md`
- Modify: `docs/sdk/modules/index.md`
- Modify: `docs/dev/subsystems/ssh.md`
- Modify: `assets/lua/tests/test-ssh-fleet.fnl`
- Modify: `assets/lua/tests/test-ssh-integration.fnl`

**Interfaces:**
- Consumes: `(require :ssh)`, `(require :ssh.fleet)`, callbacks run-loop, existing SSH fixture helpers.
- Produces: SDK page `/sdk/modules/ssh`; named test coverage for documented low-level exec and fleet examples.

- [ ] **Step 1: Add RED example coverage tests**
  - In `assets/lua/tests/test-ssh-fleet.fnl`, add a named test `SDK fleet exec example returns structured per-host results` using the existing fake SSH transport.
  - In `assets/lua/tests/test-ssh-integration.fnl`, add or rename a named low-level connect/exec fixture test `SDK low-level exec example runs command`.
  - These tests should describe the examples that will appear in the docs and must use canonical kebab-case keys only.

- [ ] **Step 2: Run RED Fennel validation**
  - Run focused compile check for touched Fennel test files.
  - Run `make constraints`.
  - Run focused tests for `tests.test-ssh-fleet:main` and `tests.test-ssh-integration:main`.
  - Expected before docs/example implementation: new example expectations fail if they refer to missing helper behavior; if they pass because behavior already exists, record that the tests are characterization coverage.

- [ ] **Step 3: Create SDK SSH module page**
  - Create `docs/sdk/modules/ssh.md` with sections:
    - `# ssh`
    - canonical imports `(require :ssh)` and `(require :ssh.fleet)`;
    - source files;
    - availability fields `ssh.available` and `ssh["missing-reason"]`;
    - API summary;
    - low-level connect/exec example;
    - fleet exec example;
    - known-host policy and credential safety notes;
    - related modules;
    - aliases/search terms.
  - Do not include real passwords, private keys, or host credentials.

- [ ] **Step 4: Index and cross-link docs**
  - Add `ssh` under Networking and services in `docs/sdk/modules/index.md`.
  - Link the SDK page from `docs/dev/subsystems/ssh.md` and state that examples are covered by SSH Fennel tests.

- [ ] **Step 5: Run GREEN Fennel/docs validation**
  - Run compile check first:
    ```bash
    ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-ssh-fleet.fnl --file assets/lua/tests/test-ssh-integration.fnl
    ```
  - Run constraints second:
    ```bash
    make constraints
    ```
  - Run focused tests third:
    ```bash
    SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-ssh-fleet:main
    SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-ssh-integration:main
    ```
  - Run `git diff --check` for docs whitespace.

- [ ] **Step 6: Commit Task 3**
  ```bash
  git add docs/sdk/modules/ssh.md docs/sdk/modules/index.md docs/dev/subsystems/ssh.md assets/lua/tests/test-ssh-fleet.fnl assets/lua/tests/test-ssh-integration.fnl
  git commit -m "docs(ssh): add tested SDK examples"
  ```

---

### Task 4: Final Validation and Handoff

**Files:**
- Modify only if validation uncovers reviewed fixes.

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces: reviewed branch ready for finishing workflow and PR CI.

- [ ] **Step 1: Run focused script checks**
  ```bash
  python3 -m py_compile tests/ssh_fixture.py
  bash -n scripts/build-windows.sh
  ```

- [ ] **Step 2: Run build and Fennel gates**
  ```bash
  make build
  make fennel-check
  make constraints
  ```
  - `make build` timeout: `14400000`.

- [ ] **Step 3: Run focused SSH tests**
  ```bash
  ctest --test-dir build -R 'test_ssh_service|test_lua_ssh_binding|space_ssh_integration' --output-on-failure
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-ssh:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-ssh-fleet:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-ssh-integration:main
  ```

- [ ] **Step 4: Run full local suite**
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```
  - Required because CI workflow behavior, build dependency scripts, fixture behavior, and Fennel tests changed.

- [ ] **Step 5: Run Windows dependency preflight when safe**
  - Dispatch `windows-ci-reproducer` for guarded preflight/reproduction if Windows cross-build validation is available.
  - If vcpkg `libssh` cannot provide pkg-config module for the current triplet, report `HUMAN_DECISION_REQUIRED` with wrapper evidence.

- [ ] **Step 6: Inspect branch state**
  ```bash
  git diff --check
  git status --porcelain
  git log --oneline --decorate -n 12
  ```

- [ ] **Step 7: Commit any reviewed validation fixes**
  - Any code/test/docs fix discovered here must go through implementer and reviewer before completion.
  - Do not commit generated build artifacts.

- [ ] **Step 8: Report final validation scope**
  - Include whether local strict real-backend validation ran or is deferred to Linux PR CI due missing local `libssh`.
  - State that PR CI remains the full integration gate.
