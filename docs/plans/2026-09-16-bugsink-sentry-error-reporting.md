# Bugsink/Sentry Error Reporting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add required vendored Sentry Native SDK support so Fennel entrypoints can initialize Bugsink reporting by DSN and, after initialization, report both C++ and Fennel/Lua errors.

**Architecture:** Vendor `sentry-native` as a required CMake dependency and hide it behind a focused C++ `error_reporting` wrapper. Expose the wrapper through a strict Fennel module named `error-reporting`; Fennel owns initialization and DSN choice, while C++ owns SDK lifecycle, native crash/terminate hooks, and central Lua error capture seams.

**Tech Stack:** C++17, CMake 3.18, Sentry Native SDK `0.16.6`, Bugsink/Sentry DSN protocol, sol2, Fennel, CTest, local HTTP test fixtures.

## Global Constraints

- Vendor Sentry Native SDK `0.16.6` under `external/sentry-native`; keep upstream MIT `LICENSE` in the vendored tree.
- Sentry Native SDK is required for normal builds; do not add an optional unavailable-module path.
- Fennel entrypoints decide whether to initialize reporting and which DSN to use.
- Requiring `:error-reporting` alone must not initialize the SDK.
- C++ must not implicitly initialize error reporting from environment variables before the Fennel entrypoint runs.
- After a Fennel entrypoint initializes reporting, both C++ side and Fennel/Lua side errors must report through the same SDK instance.
- Capture calls before initialization must be safe no-ops returning `false`.
- Invalid DSNs, invalid option types, and SDK initialization failures must fail loudly.
- Existing CLI entry modes, stderr messages, logs, and exit codes must remain unchanged except for additional reporting side effects after initialization.
- Tests must never send events to `bugsink.narlun.com` or use the production Bugsink DSN.
- Test event delivery must use local HTTP DSNs served by test fixtures.
- Fennel code must follow project idioms: `local`, strict canonical keys, no compatibility aliases, and project-native validation commands.

---

## File Structure

- `external/sentry-native/`: vendored Sentry Native SDK `0.16.6` release source including upstream `LICENSE`.
- `CMakeLists.txt`: configures vendored Sentry options, adds `external/sentry-native`, links `sentry::sentry`, installs or copies `crashpad_handler` when the target exists, and registers new tests.
- `src/error_reporting.h`: small C++ interface consumed by runtime and binding code.
- `src/error_reporting.cpp`: Sentry Native SDK lifecycle, event construction, flush/shutdown, and terminate handler implementation.
- `src/lua_error_reporting.cpp`: sol2 binding for `(require :error-reporting)`.
- `src/lua_runtime.cpp`: declaration and call for `lua_bind_error_reporting`; fatal traceback capture seam.
- `apps/space/main.cpp`: terminate-handler installation, top-level `sol::error` capture helpers, and normal shutdown call.
- `src/lua_callbacks.cpp`: callback error capture where dispatch currently logs and continues.
- `tests/test_error_reporting.cpp`: C++ wrapper tests using a local HTTP server fixture.
- `tests/test_lua_module_error_integration.cpp`: existing integration test extended with local DSN delivery assertions.
- `assets/lua/tests/test-error-reporting.fnl`: Fennel module API tests that never initialize a production DSN.
- `assets/lua/tests/error-reporting-startup-error.fnl`: fixture that initializes from test-only environment variables and raises.
- `assets/lua/tests/error-reporting-callback-error.fnl`: fixture that initializes from test-only environment variables, triggers a callback failure, flushes, and exits successfully.
- `assets/lua/tests/fast.fnl`: includes the new API test module.
- `assets/lua/main.fnl`: canonical main-app initialization with the provided Bugsink DSN.
- `docs/dev/features/error-reporting.md`: developer documentation for initialization, capture seams, and test safety.

---

### Task 1: Vendored SDK, Native Wrapper, and Local Delivery Test

**Files:**
- Create/import: `external/sentry-native/`
- Create: `src/error_reporting.h`
- Create: `src/error_reporting.cpp`
- Modify: `CMakeLists.txt`
- Test: `tests/test_error_reporting.cpp`

**Interfaces:**
- Consumes: Sentry Native C API from `external/sentry-native/include/sentry.h`.
- Produces:
  - `namespace error_reporting`
  - `enum class Level { Fatal, Error, Warning, Info, Debug };`
  - `struct InitOptions { std::string dsn; std::string environment; std::string release; std::string database_path; bool debug = false; };`
  - `bool init(const InitOptions& options, std::string* error_message = nullptr);`
  - `bool is_enabled();`
  - `bool capture_message(Level level, const std::string& logger, const std::string& message);`
  - `bool capture_exception(const std::string& type, const std::string& value, const std::string& stacktrace, const std::vector<std::pair<std::string, std::string>>& tags = {});`
  - `bool flush(int timeout_ms);`
  - `void shutdown();`
  - `void install_terminate_handler();`

- [ ] **Step 1: Vendor the approved SDK release**

  Import Sentry Native SDK `0.16.6` under `external/sentry-native` from the upstream release archive. Keep the upstream directory layout and `LICENSE` file intact. Confirm the vendored tree contains `CMakeLists.txt`, `include/sentry.h`, and `LICENSE`.

- [ ] **Step 2: Add CMake dependency wiring**

  Near the other vendored dependencies in `CMakeLists.txt`, add this configuration before `add_subdirectory(external/sentry-native)`:

  ```cmake
  set(SENTRY_BUILD_TESTS OFF CACHE BOOL "Disable sentry-native tests" FORCE)
  set(SENTRY_BUILD_EXAMPLES OFF CACHE BOOL "Disable sentry-native examples" FORCE)
  set(SENTRY_BUILD_BENCHMARKS OFF CACHE BOOL "Disable sentry-native benchmarks" FORCE)
  set(SENTRY_BUILD_SHARED_LIBS OFF CACHE BOOL "Build sentry-native statically" FORCE)
  if(UNIX AND NOT APPLE)
      set(SENTRY_BACKEND crashpad CACHE STRING "Use crashpad backend for sentry-native" FORCE)
      set(SENTRY_TRANSPORT curl CACHE STRING "Use curl transport for sentry-native" FORCE)
  endif()
  add_subdirectory(external/sentry-native)
  space_suppress_target_warnings(sentry)
  ```

  Add `sentry::sentry` to `target_link_libraries(${PROJECT_NAME}_lib ...)`. If `sentry::sentry` is unavailable but target `sentry` exists in this release, link `sentry` and keep a comment naming the expected upstream alias.

- [ ] **Step 3: Add crashpad runtime helper copying**

  After `add_executable(${PROJECT_NAME} apps/space/main.cpp)`, add a post-build copy for the crashpad helper only when CMake target `crashpad_handler` exists:

  ```cmake
  if(TARGET crashpad_handler)
      add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
          COMMAND ${CMAKE_COMMAND} -E copy_if_different
              $<TARGET_FILE:crashpad_handler>
              $<TARGET_FILE_DIR:${PROJECT_NAME}>/crashpad_handler
          VERBATIM)
  endif()
  ```

  This keeps Linux crash handling usable without requiring a global install path.

- [ ] **Step 4: Write the wrapper header**

  Create `src/error_reporting.h` with this public surface:

  ```cpp
  #pragma once

  #include <string>
  #include <utility>
  #include <vector>

  namespace error_reporting {

  enum class Level { Fatal, Error, Warning, Info, Debug };

  struct InitOptions {
      std::string dsn;
      std::string environment;
      std::string release;
      std::string database_path;
      bool debug { false };
  };

  bool init(const InitOptions& options, std::string* error_message = nullptr);
  bool is_enabled();
  bool capture_message(Level level, const std::string& logger, const std::string& message);
  bool capture_exception(const std::string& type,
                         const std::string& value,
                         const std::string& stacktrace,
                         const std::vector<std::pair<std::string, std::string>>& tags = {});
  bool flush(int timeout_ms);
  void shutdown();
  void install_terminate_handler();

  } // namespace error_reporting
  ```

- [ ] **Step 5: Implement lifecycle state and validation**

  In `src/error_reporting.cpp`, keep wrapper state in an anonymous namespace:

  ```cpp
  #include "error_reporting.h"

  #include <atomic>
  #include <cstdlib>
  #include <exception>
  #include <mutex>
  #include <sstream>

  #include <sentry.h>

  namespace {
  std::mutex g_mutex;
  bool g_enabled = false;
  std::string g_dsn;
  std::terminate_handler g_previous_terminate = nullptr;
  std::atomic<bool> g_terminate_installed { false };

  void set_error(std::string* out, const std::string& message)
  {
      if (out) {
          *out = message;
      }
  }
  }
  ```

  `init` must reject an empty `options.dsn`, return success when called again with the same active DSN, reject a different DSN while enabled, create `sentry_options_t*`, set DSN/debug/release/environment/database path when present, set the crashpad handler path to `crashpad_handler` beside the executable when practical, call `sentry_init`, and set `g_enabled` only after `sentry_init` returns `0`.

- [ ] **Step 6: Implement event capture functions**

  Map levels with a helper using Sentry constants:

  ```cpp
  sentry_level_t to_sentry_level(error_reporting::Level level)
  {
      switch (level) {
      case error_reporting::Level::Fatal: return SENTRY_LEVEL_FATAL;
      case error_reporting::Level::Error: return SENTRY_LEVEL_ERROR;
      case error_reporting::Level::Warning: return SENTRY_LEVEL_WARNING;
      case error_reporting::Level::Info: return SENTRY_LEVEL_INFO;
      case error_reporting::Level::Debug: return SENTRY_LEVEL_DEBUG;
      }
      return SENTRY_LEVEL_ERROR;
  }
  ```

  `capture_message` must return `false` when disabled and otherwise call `sentry_capture_event(sentry_value_new_message_event(...))`. `capture_exception` must create an event object, set `exception.values[0].type`, `exception.values[0].value`, add `extra.stacktrace`, apply string tags, capture the event, and return `true` when enabled.

- [ ] **Step 7: Implement flush, shutdown, and terminate hook**

  `flush(timeout_ms)` returns `false` when disabled and otherwise returns whether `sentry_flush(timeout_ms)` reports success according to the SDK return value. `shutdown()` must call `sentry_close()` only when enabled, clear state, and be safe when repeated. `install_terminate_handler()` must install exactly once with `std::set_terminate`; the handler captures `std::current_exception()` text as `NativeTerminate`, flushes for `2000` ms, then calls the previous terminate handler if present or `std::abort()`.

- [ ] **Step 8: Add a local C++ delivery test**

  Create `tests/test_error_reporting.cpp` using `httplib::Server` from `external/cpp-httplib`. The test must contain concrete C++ with this structure:

  ```cpp
  bool check(bool condition, const std::string& message)
  {
      if (!condition) {
          std::cerr << "FAIL: " << message << "\n";
          return false;
      }
      return true;
  }

  bool wait_for_body_containing(const std::vector<std::string>& bodies,
                               std::mutex& mutex,
                               const std::string& needle)
  {
      const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
      while (std::chrono::steady_clock::now() < deadline) {
          {
              std::lock_guard<std::mutex> lock(mutex);
              for (const std::string& body : bodies) {
                  if (body.find(needle) != std::string::npos) {
                      return true;
                  }
              }
          }
          std::this_thread::sleep_for(std::chrono::milliseconds(50));
      }
      return false;
  }

  int main()
  {
      if (!check(!error_reporting::capture_message(error_reporting::Level::Info, "test", "disabled"),
                 "capture before init returns false")) {
          return 1;
      }

      httplib::Server server;
      std::mutex mutex;
      std::vector<std::string> bodies;
      server.Post(R"(.*)", [&](const httplib::Request& req, httplib::Response& res) {
          std::lock_guard<std::mutex> lock(mutex);
          if (req.body.find("bugsink.narlun.com") != std::string::npos) {
              res.status = 500;
              return;
          }
          bodies.push_back(req.body);
          res.status = 200;
          res.set_content("{}", "application/json");
      });
      int port = server.bind_to_any_port("127.0.0.1");
      if (!check(port > 0, "bind local server")) {
          return 1;
      }
      std::thread thread([&]() { server.listen_after_bind(); });

      error_reporting::InitOptions options;
      options.dsn = "http://public@127.0.0.1:" + std::to_string(port) + "/1";
      options.database_path = (std::filesystem::temp_directory_path() / "space-error-reporting-wrapper-test").string();
      std::string error_message;
      bool ok = error_reporting::init(options, &error_message);
      ok = ok && error_reporting::capture_exception("TestException", "space local test exception", "stack line", {{"test", "error-reporting"}});
      error_reporting::flush(5000);
      error_reporting::shutdown();
      server.stop();
      thread.join();
      return check(ok, error_message) && check(wait_for_body_containing(bodies, mutex, "space local test exception"), "local event received") ? 0 : 1;
  }
  ```

  The implementer may adjust the exact bind/listen calls to match `cpp-httplib` APIs available in the vendored header, but the final test must bind only `127.0.0.1`, initialize with a local DSN, and fail immediately if any received request body indicates `bugsink.narlun.com`.

- [ ] **Step 9: Register the wrapper test**

  Add to `CMakeLists.txt` near other C++ tests:

  ```cmake
  add_executable(test_error_reporting tests/test_error_reporting.cpp)
  target_link_libraries(test_error_reporting ${PROJECT_NAME}_lib)
  target_include_directories(test_error_reporting PRIVATE external/cpp-httplib)
  add_test(NAME test_error_reporting COMMAND test_error_reporting)
  ```

- [ ] **Step 10: Validate Task 1**

  Run:

  ```bash
  make cmake
  make build
  python3 scripts/ctest-summary.py --test-dir build --output-on-failure -R test_error_reporting
  ```

  Expected: configure succeeds with required sentry-native, build succeeds, and `test_error_reporting` passes without external network use.

- [ ] **Step 11: Commit Task 1**

  Commit only the SDK import, wrapper, CMake changes, and C++ wrapper test:

  ```bash
  git add external/sentry-native CMakeLists.txt src/error_reporting.h src/error_reporting.cpp tests/test_error_reporting.cpp
  git commit -m "feat(engine): add native error reporting wrapper"
  ```

---

### Task 2: Fennel-Facing `error-reporting` Module

**Files:**
- Create: `src/lua_error_reporting.cpp`
- Modify: `src/lua_runtime.cpp`
- Test: `assets/lua/tests/test-error-reporting.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: Task 1 `error_reporting` namespace.
- Produces `(require :error-reporting)` with:
  - `(init {:dsn string :environment string? :release string? :database-path string? :debug boolean?}) -> true`
  - `(enabled?) -> boolean`
  - `(capture-message level logger message) -> boolean`
  - `(capture-error {:type string :message string :stacktrace string? :tags table?}) -> boolean`
  - `(flush timeout-ms) -> boolean`
  - `(shutdown) -> nil`

- [ ] **Step 1: Write the Fennel API test first**

  Create `assets/lua/tests/test-error-reporting.fnl`:

  ```fennel
  (local reporting (require :error-reporting))

  (fn assert-eq [actual expected message]
    (when (not= actual expected)
      (error (.. message " expected=" (tostring expected) " actual=" (tostring actual)))))

  (fn assert-error [f message]
    (local (ok err) (pcall f))
    (when ok
      (error message))
    err)

  (fn main []
    (assert-eq (type reporting.init) :function "init export")
    (assert-eq (type reporting.enabled?) :function "enabled? export")
    (assert-eq (type reporting.capture-message) :function "capture-message export")
    (assert-eq (type reporting.capture-error) :function "capture-error export")
    (assert-eq (type reporting.flush) :function "flush export")
    (assert-eq (type reporting.shutdown) :function "shutdown export")
    (assert-eq (reporting.enabled?) false "reporting disabled before init")
    (assert-eq (reporting.capture-message :error :test "disabled message") false "message capture disabled before init")
    (assert-eq (reporting.capture-error {:type :Disabled :message "disabled"}) false "error capture disabled before init")
    (assert-error #(reporting.init {}) "empty init options must fail")
    (assert-error #(reporting.init {:dsn 42}) "numeric dsn must fail")
    (assert-error #(reporting.capture-message :verbose :test "bad level") "invalid level must fail")
    true)

  {:main main}
  ```

- [ ] **Step 2: Add the test to the fast suite**

  Add `:tests.test-error-reporting` to `assets/lua/tests/fast.fnl` beside other small binding/module tests.

- [ ] **Step 3: Verify the test fails before the binding exists**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-error-reporting:main
  ```

  Expected: failure because `error-reporting` is not found or exports are missing.

- [ ] **Step 4: Implement the binding module**

  Create `src/lua_error_reporting.cpp` following the `lua_logging.cpp` preload style. Include `error_reporting.h` and expose one table through `package.preload["error-reporting"]`. Use helpers with these behaviors:

  ```cpp
  error_reporting::Level parse_level(const std::string& level)
  {
      if (level == "fatal") return error_reporting::Level::Fatal;
      if (level == "error") return error_reporting::Level::Error;
      if (level == "warning" || level == "warn") return error_reporting::Level::Warning;
      if (level == "info") return error_reporting::Level::Info;
      if (level == "debug") return error_reporting::Level::Debug;
      throw sol::error("error-reporting invalid level: " + level);
  }
  ```

  `init` must require a table, require non-empty string key `dsn`, accept only string `environment`, string `release`, string `database-path`, and boolean `debug`, call `error_reporting::init`, and throw `sol::error("error-reporting init failed: " + error_message)` when the wrapper returns `false`.

- [ ] **Step 5: Register the binding in `LuaRuntime`**

  In `src/lua_runtime.cpp`, add `void lua_bind_error_reporting(sol::state&);` near other binding declarations and call `lua_bind_error_reporting(lua);` near `lua_bind_logging(lua);` inside `LuaRuntime::install_base_bindings()`.

- [ ] **Step 6: Validate Task 2**

  Run:

  ```bash
  make build
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-error-reporting:main
  ```

  Expected: build, Fennel compile, constraints, and focused Fennel test pass. Constraint impact note: changed, because a new Fennel test file and fast-suite registration are added.

- [ ] **Step 7: Commit Task 2**

  ```bash
  git add src/lua_error_reporting.cpp src/lua_runtime.cpp assets/lua/tests/test-error-reporting.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(lua): expose error reporting to Fennel"
  ```

---

### Task 3: Capture C++ and Fennel/Lua Error Seams

**Files:**
- Modify: `apps/space/main.cpp`
- Modify: `src/lua_runtime.cpp`
- Modify: `src/lua_callbacks.cpp`
- Modify: `tests/test_lua_module_error_integration.cpp`
- Create: `assets/lua/tests/error-reporting-startup-error.fnl`
- Create: `assets/lua/tests/error-reporting-callback-error.fnl`

**Interfaces:**
- Consumes: Task 1 wrapper and Task 2 Fennel module.
- Produces reporting side effects for top-level Lua errors, fatal Lua tracebacks, callback errors, and native terminate after initialization.

- [ ] **Step 1: Add test-only Fennel startup fixture**

  Create `assets/lua/tests/error-reporting-startup-error.fnl`:

  ```fennel
  (local reporting (require :error-reporting))

  (fn main []
    (local dsn (os.getenv :SPACE_TEST_ERROR_REPORTING_DSN))
    (local db (os.getenv :SPACE_TEST_ERROR_REPORTING_DB))
    (when (or (not dsn) (= dsn ""))
      (error "SPACE_TEST_ERROR_REPORTING_DSN is required"))
    (when (or (not db) (= db ""))
      (error "SPACE_TEST_ERROR_REPORTING_DB is required"))
    (reporting.init {:dsn dsn :database-path db :environment "test" :release "space-test"})
    (error "tests.error-reporting startup failure"))

  {:main main}
  ```

- [ ] **Step 2: Add test-only callback fixture**

  Create `assets/lua/tests/error-reporting-callback-error.fnl`:

  ```fennel
  (local reporting (require :error-reporting))
  (local callbacks (require :callbacks))

  (fn main []
    (local dsn (os.getenv :SPACE_TEST_ERROR_REPORTING_DSN))
    (local db (os.getenv :SPACE_TEST_ERROR_REPORTING_DB))
    (when (or (not dsn) (= dsn ""))
      (error "SPACE_TEST_ERROR_REPORTING_DSN is required"))
    (when (or (not db) (= db ""))
      (error "SPACE_TEST_ERROR_REPORTING_DB is required"))
    (reporting.init {:dsn dsn :database-path db :environment "test" :release "space-test"})
    (local id (callbacks.register (fn [_payload] (error "tests.error-reporting callback failure"))))
    (callbacks.enqueue id {})
    (callbacks.dispatch 1)
    (reporting.flush 5000)
    (reporting.shutdown)
    true)

  {:main main}
  ```

- [ ] **Step 3: Extend integration test with local server helper**

  In `tests/test_lua_module_error_integration.cpp`, add `#include "httplib.h"`, `<atomic>`, `<mutex>`, `<thread>`, and `<chrono>`. Add a local fixture type in the anonymous namespace:

  ```cpp
  struct LocalEnvelopeServer {
      httplib::Server server;
      std::thread thread;
      std::mutex mutex;
      std::vector<std::string> bodies;
      int port { 0 };

      bool start();
      void stop();
      bool contains(const std::string& needle);
      std::string dsn() const;
  };
  ```

  `start()` must bind to `127.0.0.1` with port `0`, record the assigned port, register `Post(R"(.*)", ...)` to append `req.body`, and run `listen_after_bind()` on a thread. `dsn()` returns `http://public@127.0.0.1:<port>/1`. `contains` scans captured bodies for a substring.

- [ ] **Step 4: Add startup and callback delivery cases**

  In `main()` of the integration test, after the existing failure cases, create `LocalEnvelopeServer server;` and require `server.start()`. Set:

  ```cpp
  set_env_var("SPACE_TEST_ERROR_REPORTING_DSN", server.dsn());
  set_env_var("SPACE_TEST_ERROR_REPORTING_DB", (fs::temp_directory_path() / "space-error-reporting-test-db").string());
  ```

  Run `space -m tests.error-reporting-startup-error:main`, assert nonzero exit, assert stdout/stderr still contains `tests.error-reporting startup failure`, then wait up to 5 seconds for `server.contains("tests.error-reporting startup failure")`.

  Run `space -m tests.error-reporting-callback-error:main`, assert zero exit, assert output still contains `[callbacks] invocation failed`, then wait up to 5 seconds for `server.contains("tests.error-reporting callback failure")`.

  Stop the server before returning.

- [ ] **Step 5: Add top-level Lua error capture in main**

  In `apps/space/main.cpp`, include `error_reporting.h`. Add a helper near other local helpers:

  ```cpp
  void capture_lua_error(const std::string& entry_mode, const std::string& target, const sol::error& error)
  {
      error_reporting::capture_exception(
          "LuaError",
          error.what(),
          error.what(),
          {{"entry_mode", entry_mode}, {"entry_target", target}});
      error_reporting::flush(2000);
  }
  ```

  Call `error_reporting::install_terminate_handler();` before creating `LuaRuntime`. In each existing `catch (const sol::error& e)` block, call `capture_lua_error(...)` before current `log_write_file_only`, `std::cerr`, and `return 1` behavior.

- [ ] **Step 6: Add normal shutdown**

  At the end of `apps/space/main.cpp`, after existing runtime/resource cleanup, call `error_reporting::shutdown();`. Keep it outside Lua-engine cleanup branches so it runs once on successful process exit.

- [ ] **Step 7: Capture fatal Lua traceback**

  In `src/lua_runtime.cpp`, include `error_reporting.h`. In `LuaRuntime::install_fatal_traceback()`, after `std::cerr << traced << "\n";` and before `std::abort();`, add:

  ```cpp
  error_reporting::capture_exception("LuaFatalTraceback", traced, traced, {{"entry_mode", "fatal_traceback"}});
  error_reporting::flush(2000);
  ```

- [ ] **Step 8: Capture callback errors while preserving behavior**

  In `src/lua_callbacks.cpp`, include `error_reporting.h`. Add helper:

  ```cpp
  void capture_callback_error(uint64_t id, const sol::error& error)
  {
      error_reporting::capture_exception(
          "LuaCallbackError",
          error.what(),
          error.what(),
          {{"callback_id", std::to_string(id)}});
  }
  ```

  In both `lua_callbacks_dispatch` and `lua_callbacks_dispatch_ids`, call `capture_callback_error(item.id, err);` immediately before the existing `std::cerr << "[callbacks] invocation failed..."` line.

- [ ] **Step 9: Validate Task 3**

  Run:

  ```bash
  make build
  make fennel-check
  make constraints
  python3 scripts/ctest-summary.py --test-dir build --output-on-failure -R test_lua_module_error_integration
  ```

  Expected: build, compile check, constraints, and integration test pass; local server receives startup and callback events; no request targets `bugsink.narlun.com`.

- [ ] **Step 10: Commit Task 3**

  ```bash
  git add apps/space/main.cpp src/lua_runtime.cpp src/lua_callbacks.cpp tests/test_lua_module_error_integration.cpp assets/lua/tests/error-reporting-startup-error.fnl assets/lua/tests/error-reporting-callback-error.fnl
  git commit -m "feat(lua): report runtime error seams"
  ```

---

### Task 4: Main Entrypoint Initialization and Developer Documentation

**Files:**
- Modify: `assets/lua/main.fnl`
- Create: `docs/dev/features/error-reporting.md`

**Interfaces:**
- Consumes: Task 2 `(require :error-reporting)` module.
- Produces: canonical main-app Bugsink initialization and developer docs.

- [ ] **Step 1: Add main entrypoint initialization near logging setup**

  In `assets/lua/main.fnl`, require `:error-reporting` near early logging requires. Add a small helper near the existing early logging initialization:

  ```fennel
  (local error-reporting (require :error-reporting))

  (fn init-error-reporting []
    (local dsn "https://1f1673528e9b4e8cae1d0a722e435170@bugsink.narlun.com/1")
    (local environment (os.getenv :SPACE_ERROR_REPORTING_ENVIRONMENT))
    (local release (os.getenv :SPACE_ERROR_REPORTING_RELEASE))
    (local has-environment (and environment (not= environment "")))
    (local has-release (and release (not= release "")))
    (local opts
      (if (and has-environment has-release) {:dsn dsn :environment environment :release release}
          has-environment {:dsn dsn :environment environment}
          has-release {:dsn dsn :release release}
          {:dsn dsn}))
    (error-reporting.init opts))
  ```

  Call `(init-error-reporting)` immediately after native logging initialization succeeds, before later app startup work.

- [ ] **Step 2: Keep tests off the production DSN**

  Ensure existing test runners that require `:main` do not invoke the full app loop path with production reporting. The existing `app-config.run-main` behavior should prevent `main.fnl` app startup in focused tests that require main as a library. If a test directly executes `-m main`, it must either run with network disabled and assert no crash, or be adjusted to use a non-main module fixture.

- [ ] **Step 3: Add developer documentation**

  Create `docs/dev/features/error-reporting.md` with these sections and concrete content:

  ```markdown
  # Error Reporting

  Space uses the vendored Sentry Native SDK to report Bugsink-compatible events.
  Fennel entrypoints own initialization and DSN choice. Requiring `:error-reporting` does not initialize reporting.

  ## Main entrypoint

  `assets/lua/main.fnl` initializes reporting with the main Bugsink DSN during app startup. Tests must not use that DSN.

  ## Fennel API

  - `(init {:dsn string :environment string? :release string? :database-path string? :debug boolean?})`
  - `(enabled?)`
  - `(capture-message level logger message)`
  - `(capture-error {:type string :message string :stacktrace string? :tags table?})`
  - `(flush timeout-ms)`
  - `(shutdown)`

  ## Capture seams

  After initialization, C++ reports top-level Lua errors, fatal Lua tracebacks, callback errors, native terminate events, and SDK-supported native crashes.

  ## Test safety

  Tests use local DSNs such as `http://public@127.0.0.1:<port>/1` and must never send to `bugsink.narlun.com`.
  ```

- [ ] **Step 4: Validate Task 4**

  Run:

  ```bash
  make fennel-check
  make constraints
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-error-reporting:main
  ```

  Expected: Fennel compile, constraints, and focused module test pass. Constraint impact note: changed, because `main.fnl` changed.

- [ ] **Step 5: Commit Task 4**

  ```bash
  git add assets/lua/main.fnl docs/dev/features/error-reporting.md
  git commit -m "feat(assets): initialize Bugsink reporting from main"
  ```

---

### Task 5: Full Validation and Polish

**Files:**
- Modify only files needed to fix issues found by validation.

**Interfaces:**
- Consumes all prior tasks.
- Produces a locally validated feature branch ready for finishing workflow.

- [ ] **Step 1: Run full validation**

  Run the required broad suite because this changed native dependencies, CMake, runtime startup/shutdown, Lua bindings, Fennel files, and top-level error paths:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: full test suite passes and no test sends traffic to `bugsink.narlun.com`.

- [ ] **Step 2: Inspect for production DSN use in tests**

  Run:

  ```bash
  rg "bugsink\.narlun\.com|1f1673528e9b4e8cae1d0a722e435170" tests assets/lua/tests
  ```

  Expected: no matches under `tests` or `assets/lua/tests`.

- [ ] **Step 3: Inspect diff for accidental optional dependency paths**

  Run:

  ```bash
  rg "SPACE_ENABLE_.*SENTRY|available.*false|missing-reason.*sentry|missing-reason.*error-reporting" CMakeLists.txt src assets/lua
  ```

  Expected: no matches that make `sentry-native` optional or expose an unavailable module.

- [ ] **Step 4: Fix any validation failures through the normal loop**

  If validation fails, capture the failing command, failing tests, relevant output, current branch, and `git status --porcelain`; invoke systematic debugging before changing code. Route fixes through implementer and reviewer, then rerun the failed validation command and any narrower command that covers the changed surface.

- [ ] **Step 5: Commit validation fixes when needed**

  If Step 4 required repository changes, commit only the reviewed files changed by the validation fix:

  ```bash
  git status --short
  git add path/to/validated/fix.cpp path/to/validated/fix.fnl
  git commit -m "fix(engine): stabilize error reporting integration"
  ```

  Replace the two `git add` example paths with the exact reviewed files from the fix before running the command. If Step 4 required no changes, do not create a commit for validation alone.
