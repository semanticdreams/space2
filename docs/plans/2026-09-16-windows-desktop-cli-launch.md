# Windows Desktop and CLI Launch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Windows `space.exe` launch as a no-terminal desktop app while preserving reliable console workflows through `space-cli.exe`.

**Architecture:** Windows builds will produce two executables from the same `apps/space/main.cpp` startup path: GUI-subsystem `space.exe` for Explorer, installer shortcuts, desktop shortcuts, and alternate GUI `-m` entries; console-subsystem `space-cli.exe` for terminals, scripts, tests, CI, and captured output. Non-Windows builds continue producing the existing single `space` executable.

**Tech Stack:** CMake 3.18.0, C++17, SDL3 `SDL_main`, CLI11, MinGW/vcpkg Windows cross-build scripts, Wine smoke tests, GitHub Actions, Inno Setup, Markdown docs.

## Global Constraints

- Windows `space.exe` must be a Windows GUI-subsystem executable and must not open a terminal window when launched from Explorer or shortcuts.
- Windows `space.exe` must keep the full existing argument parser, including `-m mod[:fn]`, for alternate GUI entry points.
- Windows `space-cli.exe` must be a Windows console-subsystem executable for PowerShell/cmd, scripts, tests, CI, stdout/stderr capture, stdin, and shell-friendly waiting.
- Both Windows executables must build from `apps/space/main.cpp` and link to the existing runtime library.
- Non-Windows builds must continue to produce only the existing `space` executable.
- Windows icon and version resources must remain attached to desktop `space.exe`; `space-cli.exe` does not need desktop shell metadata.
- Installer, Start Menu, desktop, and post-install launch actions must continue to target `space.exe`.
- Windows terminal smoke tests and Fennel/CLI test entry points must use `space-cli.exe`.
- Do not change Fennel module loading, CLI parsing semantics, Linux/macOS binary names, or Windows CEF support.
- Do not add new third-party dependencies, `.bat`, or `.cmd` wrappers.
- Preserve existing target properties and build patterns; do not add unrelated compile/link options.

---

## File Structure

- `CMakeLists.txt` owns executable target construction, CTest command routing, install targets, and PE subsystem selection.
- `apps/space/main.cpp` owns startup error reporting and keeps all entry-mode parsing shared by both Windows executables.
- `tests/test_lua_module_error_integration.cpp`, `tests/test_runtime_asset_discovery_integration.cpp`, and `tests/test_native_logging_integration.cpp` spawn the built executable and must use `space-cli.exe` on Windows.
- `scripts/build-windows.sh` builds Windows release targets.
- `scripts/package-windows-runtime.sh` stages the portable Windows runtime folder.
- `scripts/test-windows-under-wine.sh` runs Windows Fennel tests under Wine.
- `.github/workflows/build.yml` and `.github/workflows/test.yml` validate Windows artifacts and installer behavior in CI.
- `docs/dev/building.md` and `docs/user/quick-start.md` explain the Windows launch split.

---

### Task 1: Split Windows executable targets and route local tests

**Files:**
- Modify: `CMakeLists.txt`
- Modify: `tests/test_lua_module_error_integration.cpp`
- Modify: `tests/test_runtime_asset_discovery_integration.cpp`
- Modify: `tests/test_native_logging_integration.cpp`

**Interfaces:**
- Consumes: existing `${PROJECT_NAME}_lib`, `apps/space/main.cpp`, and current CTest definitions.
- Produces: Windows GUI target `${PROJECT_NAME}` outputting `space.exe`; Windows console target `space-cli` outputting `space-cli.exe`; non-Windows target `${PROJECT_NAME}` unchanged; CTest command target variable using `space-cli` on Windows and `${PROJECT_NAME}` otherwise.

- [ ] **Step 1: Factor common app target setup in `CMakeLists.txt`.**

  Near the existing `add_executable(${PROJECT_NAME} apps/space/main.cpp)` block, introduce a helper function that applies the existing app target setup to a supplied target:

  ```cmake
  function(space_configure_app_target target_name)
      target_link_libraries(${target_name} ${PROJECT_NAME}_lib)
      set_target_properties(${target_name} PROPERTIES
          INSTALL_RPATH "\$ORIGIN/../lib"
      )
      target_include_directories(${target_name} SYSTEM PRIVATE ${CMAKE_CURRENT_LIST_DIR}/external/CLI11/include)
      if(SPACE_ENABLE_CEF)
          target_compile_definitions(${target_name} PUBLIC SPACE_ENABLE_CEF=1)
          space_setup_cef_for_target(${target_name})
      endif()
      target_compile_options(${target_name} PRIVATE -O2 -g)
      target_link_options(${target_name} PRIVATE -O2 -g)
      set_target_properties(${target_name} PROPERTIES CXX_VISIBILITY_PRESET hidden)
  endfunction()
  ```

- [ ] **Step 2: Create platform-specific app targets.**

  Replace the old single target setup with:

  ```cmake
  if(WIN32)
      add_executable(${PROJECT_NAME} WIN32 apps/space/main.cpp)
      target_compile_definitions(${PROJECT_NAME} PRIVATE SPACE_WINDOWS_GUI_SUBSYSTEM=1)
      space_configure_app_target(${PROJECT_NAME})

      add_executable(space-cli apps/space/main.cpp)
      space_configure_app_target(space-cli)
  else()
      add_executable(${PROJECT_NAME} apps/space/main.cpp)
      space_configure_app_target(${PROJECT_NAME})
  endif()
  ```

  Remove the now-duplicated standalone `target_link_libraries`, `target_include_directories`, `SPACE_ENABLE_CEF`, `target_compile_options`, `target_link_options`, and `CXX_VISIBILITY_PRESET` statements for `${PROJECT_NAME}`.

- [ ] **Step 3: Keep Windows resources on the desktop target only.**

  Leave the existing Windows icon/resource generation under `if(WIN32)`, and keep:

  ```cmake
  target_sources(${PROJECT_NAME} PRIVATE "${SPACE_WINDOWS_ICON_FILE}" "${SPACE_WINDOWS_RC_FILE}")
  ```

  Do not attach the `.ico` or `.rc` file to `space-cli`.

- [ ] **Step 4: Install both Windows targets.**

  Replace the existing install block with a target list:

  ```cmake
  set(SPACE_INSTALL_TARGETS ${PROJECT_NAME})
  if(WIN32)
      list(APPEND SPACE_INSTALL_TARGETS space-cli)
  endif()

  install(TARGETS ${SPACE_INSTALL_TARGETS}
      RUNTIME DESTINATION bin
  )
  ```

- [ ] **Step 5: Route CTest Fennel commands through the console executable on Windows.**

  Before the three CTest definitions for `${PROJECT_NAME}_fnl_tests`, `${PROJECT_NAME}_fnl_tests_integration`, and `${PROJECT_NAME}_constraints`, define:

  ```cmake
  set(SPACE_TEST_COMMAND_TARGET ${PROJECT_NAME})
  if(WIN32)
      set(SPACE_TEST_COMMAND_TARGET space-cli)
  endif()
  ```

  Change the three commands from `COMMAND space ...` to:

  ```cmake
  COMMAND $<TARGET_FILE:${SPACE_TEST_COMMAND_TARGET}> -m tests.fast:main
  COMMAND $<TARGET_FILE:${SPACE_TEST_COMMAND_TARGET}> -m tests.integration:main
  COMMAND $<TARGET_FILE:${SPACE_TEST_COMMAND_TARGET}> -m constraints.runner:main -- --output summary --target repo
  ```

- [ ] **Step 6: Update spawned-executable integration tests.**

  In `tests/test_lua_module_error_integration.cpp`, `tests/test_runtime_asset_discovery_integration.cpp`, and `tests/test_native_logging_integration.cpp`, change only the Windows executable path from `space.exe` to `space-cli.exe`. Keep non-Windows lookup as `space`.

- [ ] **Step 7: Validate task 1.**

  Run:

  ```bash
  make cmake
  make build
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets python3 scripts/ctest-summary.py --test-dir build --output-on-failure -R "test_lua_module_error_integration|test_runtime_asset_discovery_integration|test_native_logging_integration|space_constraints|space_fnl_tests"
  ```

- [ ] **Step 8: Commit task 1.**

  ```bash
  git add CMakeLists.txt tests/test_lua_module_error_integration.cpp tests/test_runtime_asset_discovery_integration.cpp tests/test_native_logging_integration.cpp
  git commit -m "build(engine): split Windows desktop and CLI targets"
  ```

---

### Task 2: Surface Windows GUI startup errors visibly

**Files:**
- Modify: `apps/space/main.cpp`

**Interfaces:**
- Consumes: `SPACE_WINDOWS_GUI_SUBSYSTEM=1` from the Windows GUI target.
- Produces: `report_top_level_error(const std::string& message) -> void`, preserving stderr behavior everywhere and adding a Windows message box only for GUI-subsystem top-level failures.

- [ ] **Step 1: Add Windows message-box support behind the GUI marker.**

  Near the include block in `apps/space/main.cpp`, add:

  ```cpp
  #if defined(_WIN32) && defined(SPACE_WINDOWS_GUI_SUBSYSTEM)
  #ifndef WIN32_LEAN_AND_MEAN
  #define WIN32_LEAN_AND_MEAN
  #endif
  #include <windows.h>
  #endif
  ```

- [ ] **Step 2: Add the reporting helper.**

  Near `read_stdin()`, add:

  ```cpp
  void report_top_level_error(const std::string& message)
  {
      std::cerr << message;
      if (message.empty() || message.back() != '\n') {
          std::cerr << "\n";
      }

  #if defined(_WIN32) && defined(SPACE_WINDOWS_GUI_SUBSYSTEM)
      MessageBoxA(nullptr, message.c_str(), "Space", MB_OK | MB_ICONERROR | MB_TASKMODAL);
  #endif
  }
  ```

- [ ] **Step 3: Replace explicit top-level error writes.**

  Replace direct `std::cerr` writes with `report_top_level_error(...)` for:

  - logging initialization failure;
  - missing `--dotenv` value;
  - missing `-c` value;
  - missing `-m` value;
  - invalid `-m` `mod[:fn]` format;
  - REPL startup errors;
  - Lua/runtime errors from command, stdin, file, module, and module-function entry modes.

  Leave warning-only messages, including failed optional dotenv load warnings, as `std::cerr` only.

- [ ] **Step 4: Preserve parsing and return codes.**

  Confirm the patch does not change argument parsing order, `entry_mode`, `entry_target`, `fennel_args`, `lua["arg"]`, or return codes. CLI misuse stays `2`; runtime/startup failures stay `1`; success stays `0`.

- [ ] **Step 5: Validate task 2.**

  Run:

  ```bash
  make build
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets python3 scripts/ctest-summary.py --test-dir build --output-on-failure -R "test_lua_module_error_integration|test_native_logging_integration"
  ```

- [ ] **Step 6: Commit task 2.**

  ```bash
  git add apps/space/main.cpp
  git commit -m "fix(engine): surface Windows GUI startup errors visibly"
  ```

---

### Task 3: Update Windows build, package, and Wine scripts

**Files:**
- Modify: `scripts/build-windows.sh`
- Modify: `scripts/package-windows-runtime.sh`
- Modify: `scripts/test-windows-under-wine.sh`

**Interfaces:**
- Consumes: Windows build outputs `build/windows/space.exe` and `build/windows/space-cli.exe`.
- Produces: Windows build scripts build both executables, runtime packages include both, and Wine terminal tests run `space-cli.exe`.

- [ ] **Step 1: Build both Windows targets.**

  In `scripts/build-windows.sh`, replace the final build command with:

  ```bash
  cmake --build "${BUILD_DIR}" --config Release --target space space-cli
  ```

- [ ] **Step 2: Require and prepare both executables during packaging.**

  In `scripts/package-windows-runtime.sh`, keep:

  ```bash
  TARGET_EXE="${BUILD_DIR}/space.exe"
  ```

  Add:

  ```bash
  CLI_EXE="${BUILD_DIR}/space-cli.exe"
  ```

  Require both files to exist. Run `scripts/prepare-windows-runtime.sh` for both `TARGET_EXE` and `CLI_EXE` so dependency DLLs for both executables are staged.

- [ ] **Step 3: Copy both executables into the runtime package.**

  Ensure the package copies both:

  ```bash
  cp "${TARGET_EXE}" "${DIST_DIR}/"
  cp "${CLI_EXE}" "${DIST_DIR}/"
  ```

  Keep the existing assets and DLL copy behavior unchanged.

- [ ] **Step 4: Run Wine tests through `space-cli.exe`.**

  In `scripts/test-windows-under-wine.sh`, add:

  ```bash
  CLI_EXE="${BUILD_DIR}/space-cli.exe"
  ```

  Prepare and execute that binary:

  ```bash
  "${ROOT_DIR}/scripts/prepare-windows-wine-runtime.sh" "${CLI_EXE}"
  wine64 "${CLI_EXE}" -m "${TEST_MODULE}"
  ```

- [ ] **Step 5: Validate task 3.**

  Run:

  ```bash
  bash -n scripts/build-windows.sh scripts/package-windows-runtime.sh scripts/test-windows-under-wine.sh
  ```

  When the Windows cross-build toolchain and Wine are available, also run:

  ```bash
  scripts/build-windows-from-linux.sh
  test -f build/windows/space.exe
  test -f build/windows/space-cli.exe
  x86_64-w64-mingw32-objdump -p build/windows/space.exe | rg "Subsystem.*Windows GUI"
  x86_64-w64-mingw32-objdump -p build/windows/space-cli.exe | rg "Subsystem.*Windows CUI"
  scripts/package-windows-runtime.sh
  test -f build/dist/windows/space.exe
  test -f build/dist/windows/space-cli.exe
  scripts/prepare-windows-wine-runtime.sh build/windows/space-cli.exe
  timeout 60s wine64 build/windows/space-cli.exe --help >/dev/null
  ```

  If the cross-build toolchain or Wine is unavailable locally, record the missing dependency and rely on PR CI for those Windows-specific checks.

- [ ] **Step 6: Commit task 3.**

  ```bash
  git add scripts/build-windows.sh scripts/package-windows-runtime.sh scripts/test-windows-under-wine.sh
  git commit -m "build(scripts): package Windows desktop and CLI executables"
  ```

---

### Task 4: Update GitHub Actions Windows checks

**Files:**
- Modify: `.github/workflows/build.yml`
- Modify: `.github/workflows/test.yml`

**Interfaces:**
- Consumes: packaged `space.exe` and `space-cli.exe`.
- Produces: CI checks that terminal-style Windows execution uses `space-cli.exe`, PE subsystem bits are asserted, and installer smoke still validates `space.exe` shortcuts/launch behavior.

- [ ] **Step 1: Use `space-cli.exe` for Windows artifact terminal tests in `test.yml`.**

  Change Windows `--help` smoke tests from `space.exe` to:

  ```powershell
  .\build\dist\windows\space-cli.exe --help | Out-Null
  ```

  Change the Windows fast suite from `space.exe -m tests.fast:main` to:

  ```powershell
  .\build\dist\windows\space-cli.exe -m tests.fast:main
  ```

- [ ] **Step 2: Assert both packaged executables and subsystem bits in `build.yml`.**

  Add checks equivalent to:

  ```bash
  test -f build/dist/windows/space.exe
  test -f build/dist/windows/space-cli.exe
  x86_64-w64-mingw32-objdump -p build/windows/space.exe | rg "Subsystem.*Windows GUI"
  x86_64-w64-mingw32-objdump -p build/windows/space-cli.exe | rg "Subsystem.*Windows CUI"
  ```

- [ ] **Step 3: Use `space-cli.exe` for Wine terminal smoke in `build.yml`.**

  Change Wine preparation and `--help` smoke commands to target `build/windows/space-cli.exe`, not `build/windows/space.exe`.

- [ ] **Step 4: Keep installer shortcut behavior on `space.exe`.**

  In installer smoke checks, verify both installed executables exist, run terminal `--help` smoke through installed `space-cli.exe`, and keep installer shortcut/post-install configuration targeting `space.exe`.

- [ ] **Step 5: Validate task 4.**

  Run:

  ```bash
  rg "space\.exe --help|space\.exe -m tests\.fast:main|wine64 build/windows/space\.exe" .github/workflows
  rg "space-cli\.exe" .github/workflows
  ```

  Expected: Windows terminal/test smoke checks use `space-cli.exe`; installer shortcut configuration still references `space.exe`.

- [ ] **Step 6: Commit task 4.**

  ```bash
  git add .github/workflows/build.yml .github/workflows/test.yml
  git commit -m "ci(build): use Windows CLI executable for console checks"
  ```

---

### Task 5: Document Windows desktop and CLI launch modes

**Files:**
- Modify: `docs/dev/building.md`
- Modify: `docs/user/quick-start.md`

**Interfaces:**
- Consumes: final Windows executable names and usage conventions.
- Produces: developer and user documentation that normal launch uses `space.exe`, alternate GUI shortcuts can use `space.exe -m ...`, and console workflows use `space-cli.exe`.

- [ ] **Step 1: Update `docs/dev/building.md`.**

  In the Windows build/release guidance, document:

  - Windows ZIP and installer packages include both `space.exe` and `space-cli.exe`.
  - Explorer, Start Menu, desktop shortcuts, and installer launch actions use `space.exe`.
  - Alternate GUI shortcuts can pass entries such as `space.exe -m some.gui.entry:main` without opening a terminal.
  - PowerShell/cmd, scripts, CI, tests, `--help`, `-m tests.fast:main`, file execution, stdin, and `-c` use `space-cli.exe`.
  - Linux and macOS remain single-executable platforms.

- [ ] **Step 2: Update `docs/user/quick-start.md`.**

  Keep normal Windows user guidance as “run `space.exe`”. Add a concise note that terminal/script users should use `space-cli.exe`, while GUI shortcuts can still pass alternate entries to `space.exe` with `-m`.

- [ ] **Step 3: Validate task 5.**

  Run:

  ```bash
  rg "space-cli\.exe|space\.exe -m|Windows release builds" docs/dev/building.md docs/user/quick-start.md
  ```

- [ ] **Step 4: Commit task 5.**

  ```bash
  git add docs/dev/building.md docs/user/quick-start.md
  git commit -m "docs: explain Windows desktop and CLI launch modes"
  ```

---

### Task 6: Final validation and integration readiness

**Files:**
- Test: build, scripts, docs, Windows cross-build/package checks when available, and PR CI.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: validation evidence for local correctness and PR readiness.

- [ ] **Step 1: Run focused local validation.**

  ```bash
  bash -n scripts/build-windows.sh scripts/package-windows-runtime.sh scripts/test-windows-under-wine.sh
  make cmake
  make build
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets python3 scripts/ctest-summary.py --test-dir build --output-on-failure -R "test_lua_module_error_integration|test_runtime_asset_discovery_integration|test_native_logging_integration|space_constraints|space_fnl_tests"
  ```

- [ ] **Step 2: Run the full local suite.**

  Because app target construction, top-level startup paths, and test executable routing changed, run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- [ ] **Step 3: Run Windows cross-build/package validation when available.**

  ```bash
  scripts/build-windows-from-linux.sh
  test -f build/windows/space.exe
  test -f build/windows/space-cli.exe
  x86_64-w64-mingw32-objdump -p build/windows/space.exe | rg "Subsystem.*Windows GUI"
  x86_64-w64-mingw32-objdump -p build/windows/space-cli.exe | rg "Subsystem.*Windows CUI"
  scripts/package-windows-runtime.sh
  test -f build/dist/windows/space.exe
  test -f build/dist/windows/space-cli.exe
  scripts/prepare-windows-wine-runtime.sh build/windows/space-cli.exe
  timeout 60s wine64 build/windows/space-cli.exe --help >/dev/null
  ```

  If a dependency is unavailable locally, record the missing dependency and confirm the same check exists in PR CI.

- [ ] **Step 4: Run final search checks.**

  ```bash
  git status --porcelain
  rg "space\.exe --help|space\.exe -m tests\.fast:main|wine64 build/windows/space\.exe" .github scripts
  rg "space-cli\.exe|space\.exe -m" CMakeLists.txt scripts .github docs
  ```

  Expected: working tree is clean after the final implementation commit; Windows terminal/test workflows use `space-cli.exe`; installer and shortcut configuration still targets `space.exe`; documentation mentions GUI `space.exe -m ...`.

- [ ] **Step 5: Treat PR CI as the full integration gate.**

  Required CI evidence:

  - Linux build/test remains green.
  - Windows cross-build produces both executables.
  - Windows PE subsystem checks pass.
  - Windows artifact fast suite runs through `space-cli.exe`.
  - Windows installer smoke installs both executables and terminal smoke uses `space-cli.exe`.
  - Release ZIP contains both executables.
