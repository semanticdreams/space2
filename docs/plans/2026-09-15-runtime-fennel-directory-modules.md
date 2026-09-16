# Runtime Fennel Directory Modules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make normal embedded Space launches resolve Fennel directory modules and macros without requiring external `FENNEL_PATH` or `FENNEL_MACRO_PATH`.

**Architecture:** `LuaRuntime` owns the canonical Space Fennel asset path and exposes the same value through `runtime.fennel-path`. The runtime path contains flat modules first and directory `init.fnl` modules second, and `install_fennel` applies it to both `fennel.path` and `fennel["macro-path"]` before application modules load.

**Tech Stack:** C++17, sol2/Lua, embedded Fennel, Space Fennel tests, CMake/CTest, Markdown docs.

## Global Constraints

- Canonical Fennel asset path order is `assets/lua/?.fnl;assets/lua/?/init.fnl`.
- Preserve flat-file precedence over directory `init.fnl` modules.
- Normal embedded app launch must not require external `FENNEL_PATH` or `FENNEL_MACRO_PATH` for project modules under `assets/lua`.
- Do not rename or flatten `assets/lua/graph/extensions/builtins/init.fnl`.
- Do not change graph extension semantics, descriptor precedence, or duplicate handling.
- Do not make `make run` or other shell wrappers responsible for required embedded runtime paths.
- Do not broaden Lua `package.path` behavior beyond the existing `.lua` asset path.
- Use project-native validation only for Fennel-facing checks: `make fennel-check`, then `make constraints`, then focused runtime/Fennel tests.
- Run `make build` first when `./build/space` may be stale because runtime C++ changed.

---

## File Structure

- `src/lua_runtime.cpp`: runtime-owned canonical Fennel asset path construction and Fennel installer setup.
- `assets/lua/main.fnl`: remove startup macro-path repair if the runtime now applies macro-path before app modules load.
- `assets/lua/tests/test-runtime-fennel-path.fnl`: focused executable test proving directory modules and macro imports work without external Fennel path variables.
- `CMakeLists.txt`: register the focused runtime path test with an environment that omits `FENNEL_PATH` and `FENNEL_MACRO_PATH`.
- `docs/dev/notes/fennel-runtime-paths.md`: developer note documenting the runtime-owned path contract.

---

### Task 1: Runtime-Owned Fennel Asset Paths

**Files:**
- Modify: `src/lua_runtime.cpp:91-101`
- Modify: `src/lua_runtime.cpp:283-290`
- Modify: `assets/lua/main.fnl:37-45`

**Interfaces:**
- Consumes: `AssetManager::getAssetPath("lua") -> std::string`
- Produces: `LuaRuntime::fennel_path() const -> const std::string&` exposing `<assets>/lua/?.fnl;<assets>/lua/?/init.fnl` through the existing `runtime.fennel-path` preload
- Produces: `LuaRuntime::install_fennel(bool correlate)` prepending the canonical path to both `fennel.path` and `fennel["macro-path"]`

- [ ] **Step 1: Add the path helper**

  In `src/lua_runtime.cpp`, add an anonymous-namespace helper near the top of the file after the includes and before binding declarations:

  ```cpp
  namespace
  {
  std::string make_fennel_asset_search_path(const std::string& lua_path)
  {
      return lua_path + "/?.fnl;" + lua_path + "/?/init.fnl";
  }
  }
  ```

- [ ] **Step 2: Use the helper for runtime Fennel path construction**

  In `LuaRuntime::configure_package_paths()`, keep the existing Lua package path behavior and change only the Fennel path assignment:

  ```cpp
  void LuaRuntime::configure_package_paths()
  {
      assets_path_value = AssetManager::getAssetPath("");
      std::string lua_path = AssetManager::getAssetPath("lua");
      std::string package_path = lua_path + "/?.lua";
      fennel_path_value = make_fennel_asset_search_path(lua_path);
      lua["package"]["path"] = lua["package"]["path"].get<std::string>() + ";" + package_path;
  }
  ```

- [ ] **Step 3: Apply the runtime path to macro resolution before Fennel install**

  In `LuaRuntime::install_fennel(bool correlate)`, update the Lua script so it prepends the same value to both Fennel fields:

  ```cpp
  lua.script(
      "app = app or {}\n"
      "local fennel = require(\"fennel\")\n"
      "fennel.path = __SPACE_FENNEL_PATH .. \";\" .. fennel.path\n"
      "fennel[\"macro-path\"] = __SPACE_FENNEL_PATH .. \";\" .. fennel[\"macro-path\"]\n"
      "fennel.install({ correlate = __SPACE_FENNEL_CORRELATE })\n"
      "__SPACE_FENNEL_PATH = nil\n"
      "__SPACE_FENNEL_CORRELATE = nil\n");
  ```

- [ ] **Step 4: Remove app-level macro-path repair**

  In `assets/lua/main.fnl`, delete the startup line:

  ```fennel
  (set fennel.macro-path runtime.fennel-path)
  ```

  Keep `(local runtime (require :runtime))` because `main.fnl` uses `runtime.assets-path` and `runtime.fennel-path` elsewhere.

- [ ] **Step 5: Run build freshness for the runtime change**

  Run: `make build`

  Use timeout `14400000`.

  Expected: build succeeds.

- [ ] **Step 6: Run a direct env-independent smoke check**

  Run from repo root:

  ```bash
  env -u FENNEL_PATH -u FENNEL_MACRO_PATH \
    SPACE_DISABLE_AUDIO=1 \
    SPACE_ASSETS_PATH=$(pwd)/assets \
    ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/graph/extensions/builtins/init.fnl
  ```

  Expected: pass. This confirms the executable can reach the directory module dependency tree without external Fennel path variables.

- [ ] **Step 7: Commit Task 1**

  Stage only `src/lua_runtime.cpp` and `assets/lua/main.fnl`.

  Commit message:

  ```text
  fix(lua): configure runtime Fennel init paths
  ```

---

### Task 2: Env-Independent Runtime Regression Test

**Files:**
- Create: `assets/lua/tests/test-runtime-fennel-path.fnl`
- Modify: `CMakeLists.txt:725-750`

**Interfaces:**
- Consumes: runtime-configured `fennel.path`, `fennel["macro-path"]`, and existing `tests/runner`
- Produces: Fennel module `tests.test-runtime-fennel-path` with `main` entrypoint
- Produces: CTest `${PROJECT_NAME}_runtime_fennel_paths`

- [ ] **Step 1: Create the failing Fennel runtime path test**

  Create `assets/lua/tests/test-runtime-fennel-path.fnl` with this structure:

  ```fennel
  (local Runner (require :tests/runner))

  (local tests [])

  (fn directory-module-require-loads-built-in-graph-extensions []
    (local Builtins (require :graph/extensions/builtins))
    (assert (= (type Builtins) "table") "built-in graph extensions module should return a table")
    (assert (= (type Builtins.descriptors) "function") "built-in graph extensions should expose descriptors")
    (assert (= (type Builtins.register!) "function") "built-in graph extensions should expose register!"))

  (fn macro-import-module-loads-with-runtime-macro-path []
    (local FlexModule (require :flex))
    (assert (= (type FlexModule) "table") "flex module should return a table")
    (assert (= (type FlexModule.Flex) "function") "flex module should expose Flex")
    (assert (= (type FlexModule.FlexChild) "function") "flex module should expose FlexChild"))

  (table.insert tests {:name "directory-module-require-loads-built-in-graph-extensions"
                       :fn directory-module-require-loads-built-in-graph-extensions})
  (table.insert tests {:name "macro-import-module-loads-with-runtime-macro-path"
                       :fn macro-import-module-loads-with-runtime-macro-path})

  (fn main []
    (Runner.run tests))

  {:main main}
  ```

- [ ] **Step 2: Run the test without external Fennel path variables**

  Run from repo root:

  ```bash
  env -u FENNEL_PATH -u FENNEL_MACRO_PATH \
    SKIP_KEYRING_TESTS=1 \
    XDG_DATA_HOME=/tmp/space/tests/xdg-data \
    SPACE_DISABLE_AUDIO=1 \
    SPACE_ASSETS_PATH=$(pwd)/assets \
    ./build/space -m tests.test-runtime-fennel-path:main
  ```

  Expected before Task 1: fail with `module 'graph/extensions/builtins' not found` or macro resolution failure.

  Expected after Task 1: pass.

- [ ] **Step 3: Register the CTest**

  In `CMakeLists.txt`, add this block after `${PROJECT_NAME}_constraints` and before C++ test executables:

  ```cmake
  add_test(NAME ${PROJECT_NAME}_runtime_fennel_paths
      COMMAND space -m tests.test-runtime-fennel-path:main
  )
  set_tests_properties(${PROJECT_NAME}_runtime_fennel_paths PROPERTIES
      WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
      ENVIRONMENT "SKIP_KEYRING_TESTS=1;XDG_DATA_HOME=/tmp/space/tests/xdg-data;SPACE_DISABLE_AUDIO=1;SPACE_LOG_DIR=/tmp/space/tests/log;SPACE_ASSETS_PATH=${CMAKE_SOURCE_DIR}/assets"
  )
  ```

  Do not include `FENNEL_PATH` or `FENNEL_MACRO_PATH` in this test's environment.

- [ ] **Step 4: Reconfigure if CMake test registration is stale**

  Run: `make cmake`

  Use timeout `600000`.

  Expected: CMake config succeeds.

- [ ] **Step 5: Run focused CTest**

  Run:

  ```bash
  ctest --test-dir build -R '^space_runtime_fennel_paths$' --output-on-failure
  ```

  Expected: pass.

- [ ] **Step 6: Run Fennel compile check for the new test file**

  Run:

  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-runtime-fennel-path.fnl
  ```

  Expected: pass.

- [ ] **Step 7: Commit Task 2**

  Stage only `assets/lua/tests/test-runtime-fennel-path.fnl` and `CMakeLists.txt`.

  Commit message:

  ```text
  test(lua): cover runtime Fennel init paths
  ```

---

### Task 3: Document the Runtime Fennel Path Contract

**Files:**
- Create: `docs/dev/notes/fennel-runtime-paths.md`

**Interfaces:**
- Consumes: Task 1 runtime behavior and Task 2 regression test behavior
- Produces: developer-facing documentation for embedded Fennel path ownership

- [ ] **Step 1: Create the developer note**

  Create `docs/dev/notes/fennel-runtime-paths.md` with this content:

  ~~~markdown
  # Fennel Runtime Paths

  Space's embedded runtime owns the default Fennel asset search path. Normal app launch must not rely on shell wrappers setting `FENNEL_PATH` or `FENNEL_MACRO_PATH` for modules under `assets/lua`.

  The canonical runtime path order is:

  ```text
  assets/lua/?.fnl;assets/lua/?/init.fnl
  ```

  Flat files intentionally take precedence over directory `init.fnl` modules.

  `LuaRuntime` applies this path to both `fennel.path` and `fennel["macro-path"]` before loading app modules. The runtime also exposes the same value as `runtime.fennel-path` for child processes and user-code tooling that need to extend the project path.

  Direct test and tool commands may still set `FENNEL_PATH` and `FENNEL_MACRO_PATH` explicitly, especially when running outside the normal executable startup path. Those environment variables are conveniences for direct invocation, not requirements for normal embedded app launch.
  ~~~

- [ ] **Step 2: Commit Task 3**

  Stage only `docs/dev/notes/fennel-runtime-paths.md`.

  Commit message:

  ```text
  docs(lua): document Fennel runtime paths
  ```

---

### Task 4: Validation and Acceptance

**Files:**
- Validate: `src/lua_runtime.cpp`
- Validate: `assets/lua/main.fnl`
- Validate: `assets/lua/tests/test-runtime-fennel-path.fnl`
- Validate: `CMakeLists.txt`
- Validate: `docs/dev/notes/fennel-runtime-paths.md`

**Interfaces:**
- Consumes: Tasks 1-3
- Produces: validation evidence that runtime module loading works and existing suites still pass

- [ ] **Step 1: Build runtime freshness**

  Run: `make build`

  Use timeout `14400000`.

  Expected: pass.

- [ ] **Step 2: Run broad Fennel compile check**

  Run: `make fennel-check`

  Expected: pass.

- [ ] **Step 3: Run constraints**

  Run: `make constraints`

  Expected: pass.

- [ ] **Step 4: Run focused env-independent runtime test**

  Run:

  ```bash
  env -u FENNEL_PATH -u FENNEL_MACRO_PATH \
    SKIP_KEYRING_TESTS=1 \
    XDG_DATA_HOME=/tmp/space/tests/xdg-data \
    SPACE_DISABLE_AUDIO=1 \
    SPACE_ASSETS_PATH=$(pwd)/assets \
    ./build/space -m tests.test-runtime-fennel-path:main
  ```

  Expected: pass.

- [ ] **Step 5: Run focused registered CTest**

  Run:

  ```bash
  ctest --test-dir build -R '^space_runtime_fennel_paths$' --output-on-failure
  ```

  Expected: pass.

- [ ] **Step 6: Run full relevant local suite**

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 \
    XDG_DATA_HOME=/tmp/space/tests/xdg-data \
    SPACE_DISABLE_AUDIO=1 \
    SPACE_ASSETS_PATH=$(pwd)/assets \
    make test
  ```

  Expected: pass.

- [ ] **Step 7: Report acceptance evidence**

  The implementation is acceptable when the focused test proves directory modules and macro imports work without external path variables, normal compile/constraints pass, and `make test` passes.
