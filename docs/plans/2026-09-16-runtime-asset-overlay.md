# Runtime Asset Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Space behave as a reusable runtime by resolving project asset overlays before built-in runtime assets while preserving packaged fallbacks.

**Architecture:** `AssetManager` will construct one deduplicated ordered list of asset roots and use it for single-asset lookup. `LuaRuntime` will consume the same ordered roots to compose Lua and Fennel module search paths across every overlay, so project modules can override built-ins while missing dependencies fall through to packaged roots. Focused C++ tests cover root ordering and containment, while a runtime integration test proves `space -m main` loads `cwd/assets/lua/main.fnl` without `SPACE_ASSETS_PATH`.

**Tech Stack:** C++17, `std::filesystem`, CMake/CTest, embedded Lua/Fennel runtime.

## Global Constraints

- `AssetManager::getAssetPath(relativePath)` continues to resolve only relative asset paths under candidate roots.
- Candidate roots are ordered overlays: the first root containing the requested path wins, and later roots provide defaults.
- Search order must be: `SPACE_ASSETS_PATH` entries, `<cwd>/assets`, `get_user_data_dir("space") / "assets"`, `<exe_dir>/assets`, `<exe_dir>/../share/space/assets`, `<exe_dir>/../Resources/assets`, `/usr/share/space/assets`.
- `SPACE_ASSETS_PATH` entries are asset roots, not project roots.
- On Unix-like platforms, `SPACE_ASSETS_PATH` entries are colon-separated, matching `PATH`; Windows code paths must use semicolon separators.
- Raw `cwd` must not become an asset root; the default project asset root is `cwd/assets`.
- Equivalent candidate roots must be deduplicated before probing and should not add duplicate diagnostic lines.
- Absolute requested asset paths remain invalid.
- Traversal attempts such as `../../sensitive.txt` must not return files outside a candidate root.
- Missing assets must fail loudly and include the requested relative path and searched candidate paths.
- Project roots may override every built-in Space asset by mirroring the same relative path.
- Do not introduce separate project/runtime asset APIs.
- Do not rename `SPACE_ASSETS_PATH` to `SPACE_PATH`.
- Preserve public compatibility for existing `AssetManager` methods and `LuaRuntime::assets_path()` / `LuaRuntime::fennel_path()`.

---

## File Structure

- `src/asset_manager.h`: add a public ordered-root accessor used by runtime path composition.
- `src/asset_manager.cpp`: centralize candidate construction, multi-entry environment parsing, deduplication, ordering, containment checks, and diagnostic assembly.
- `tests/test_asset_manager.cpp`: unit-level coverage for environment lists, CWD-before-runtime ordering, user-data fallback, deduplication, absolute-path rejection, and traversal rejection.
- `src/lua_runtime.cpp`: compose Lua and Fennel package paths from all ordered asset roots instead of only the first root containing `lua`.
- `tests/test_runtime_asset_discovery_integration.cpp`: integration coverage for `space --no-dotenv -m main` from a project directory with `assets/lua/main.fnl` and no `SPACE_ASSETS_PATH`.
- `docs/dev/notes/runtime-asset-overlays.md`: developer-facing asset overlay contract.
- `docs/dev/notes/index.md`: link the new note.
- `docs/dev/notes/fennel-runtime-paths.md`: update Fennel path docs to describe per-root composition.

---

### Task 1: AssetManager Ordered Root Builder

**Files:**
- Modify: `src/asset_manager.h`
- Modify: `src/asset_manager.cpp`
- Test: `tests/test_asset_manager.cpp`

**Interfaces:**
- Consumes: existing `AssetManager::getAssetPath(const std::string&)`, `setExecutablePath`, `clearExecutablePathForTests`, and `get_user_data_dir("space")`.
- Produces: `static std::vector<std::filesystem::path> AssetManager::getAssetRoots();` returning deduplicated ordered asset roots for Lua/Fennel path composition.

- [ ] **Step 1: Add failing tests for multi-entry environment roots**

  In `tests/test_asset_manager.cpp`, add helper functions in the anonymous namespace after `path_equals`:

  ```cpp
  char path_list_separator()
  {
  #if defined(_WIN32)
      return ';';
  #else
      return ':';
  #endif
  }

  std::string join_path_list(const std::vector<fs::path>& roots)
  {
      std::string result;
      for (size_t i = 0; i < roots.size(); i++) {
          if (i > 0) {
              result.push_back(path_list_separator());
          }
          result += roots[i].string();
      }
      return result;
  }

  size_t count_occurrences(const std::string& haystack, const std::string& needle)
  {
      size_t count = 0;
      size_t pos = 0;
      while ((pos = haystack.find(needle, pos)) != std::string::npos) {
          count++;
          pos += needle.size();
      }
      return count;
  }
  ```

  Add this test and call it from `main()` before `test_env_override_has_highest_priority()`:

  ```cpp
  bool test_space_assets_path_supports_multiple_ordered_roots()
  {
      fs::path root = make_temp_root("space_asset_env_list");
      ScopedEnv env("SPACE_ASSETS_PATH", join_path_list({
          root / "env_missing",
          root / "env_second",
          root / "env_third"
      }));
      ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
      fs::create_directories(root / "work");
      ScopedCwd cwd(root / "work");
      AssetManager::clearExecutablePathForTests();
      AssetManager::setExecutablePath(root / "bin" / "space");

      touch(root / "env_second" / "probe.txt");
      touch(root / "env_third" / "probe.txt");
      touch(root / "work" / "assets" / "probe.txt");

      return check(path_equals(AssetManager::getAssetPath("probe.txt"), root / "env_second" / "probe.txt"),
                   "second SPACE_ASSETS_PATH entry should win when the first entry lacks the asset");
  }
  ```

- [ ] **Step 2: Add failing tests for CWD overlay precedence and user-data fallback**

  Add these tests and call them from `main()` immediately after the environment tests:

  ```cpp
  bool test_cwd_assets_precede_user_data_and_executable_assets()
  {
      fs::path root = make_temp_root("space_asset_cwd_order");
      ScopedEnv env("SPACE_ASSETS_PATH", std::nullopt);
      ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
      fs::create_directories(root / "work");
      ScopedCwd cwd(root / "work");
      AssetManager::clearExecutablePathForTests();
      AssetManager::setExecutablePath(root / "bin" / "space");

      touch(root / "work" / "assets" / "probe.txt");
      touch(root / "xdg" / "space" / "assets" / "probe.txt");
      touch(root / "bin" / "assets" / "probe.txt");

      return check(path_equals(AssetManager::getAssetPath("probe.txt"), root / "work" / "assets" / "probe.txt"),
                   "cwd/assets should precede user-data and executable assets");
  }

  bool test_user_data_precedes_executable_assets_when_cwd_missing()
  {
      fs::path root = make_temp_root("space_asset_user_after_cwd");
      ScopedEnv env("SPACE_ASSETS_PATH", std::nullopt);
      ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
      fs::create_directories(root / "work");
      ScopedCwd cwd(root / "work");
      AssetManager::clearExecutablePathForTests();
      AssetManager::setExecutablePath(root / "bin" / "space");

      touch(root / "xdg" / "space" / "assets" / "probe.txt");
      touch(root / "bin" / "assets" / "probe.txt");

      return check(path_equals(AssetManager::getAssetPath("probe.txt"), root / "xdg" / "space" / "assets" / "probe.txt"),
                   "user-data assets should precede executable assets when cwd/assets lacks the asset");
  }
  ```

  Keep the existing `test_user_data_precedes_executable_assets()` or replace it with `test_user_data_precedes_executable_assets_when_cwd_missing()` if that keeps names clearer.

- [ ] **Step 3: Add failing tests for empty entries and deduped diagnostics**

  Add these tests and call them from `main()`:

  ```cpp
  bool test_space_assets_path_ignores_empty_entries()
  {
      fs::path root = make_temp_root("space_asset_env_empty");
      std::string value;
      value.push_back(path_list_separator());
      value += (root / "env").string();
      value.push_back(path_list_separator());

      ScopedEnv env("SPACE_ASSETS_PATH", value);
      ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
      fs::create_directories(root / "work");
      ScopedCwd cwd(root / "work");
      AssetManager::clearExecutablePathForTests();

      touch(root / "env" / "probe.txt");

      return check(path_equals(AssetManager::getAssetPath("probe.txt"), root / "env" / "probe.txt"),
                   "empty SPACE_ASSETS_PATH entries should be ignored");
  }

  bool test_deduplicates_equivalent_roots_in_missing_diagnostics()
  {
      fs::path root = make_temp_root("space_asset_dedup");
      fs::path workAssets = root / "work" / "assets";
      ScopedEnv env("SPACE_ASSETS_PATH", workAssets.string());
      ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
      fs::create_directories(workAssets);
      ScopedCwd cwd(root / "work");
      AssetManager::clearExecutablePathForTests();

      try {
          (void)AssetManager::getAssetPath("missing.asset");
      } catch (const std::runtime_error& e) {
          std::string message = e.what();
          std::string searchedPath = (workAssets / "missing.asset").string();
          return check(count_occurrences(message, searchedPath) == 1,
                       "deduplicated roots should appear once in missing diagnostics") &&
                 check(message.find("deduplicated") == std::string::npos,
                       "missing diagnostics should not include duplicate-root noise");
      }

      std::cerr << "FAIL: missing dedup asset should throw\n";
      return false;
  }
  ```

- [ ] **Step 4: Update existing diagnostic expectations to the new order**

  In `test_missing_error_lists_requested_asset_and_searched_paths`, ensure the expected list includes these strings:

  ```cpp
  std::vector<std::string> expected = {
      "Asset not found: missing.asset",
      (root / "env" / "missing.asset").string(),
      (root / "work" / "assets" / "missing.asset").string(),
      (root / "xdg" / "space" / "assets" / "missing.asset").string(),
      (root / "pkg" / "bin" / "assets" / "missing.asset").string(),
      (root / "pkg" / "share" / "space" / "assets" / "missing.asset").string(),
      (root / "pkg" / "Resources" / "assets" / "missing.asset").string(),
      "/usr/share/space/assets/missing.asset",
  };
  ```

- [ ] **Step 5: Run the focused test to confirm it fails for the intended reason**

  Run with timeout `14400000`:

  ```bash
  make build
  ```

  Run with timeout `600000`:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 ctest --test-dir build -R '^test_asset_manager$' --output-on-failure
  ```

  Expected: `test_asset_manager` fails on the newly added precedence/list/dedup assertions.

- [ ] **Step 6: Add the ordered root accessor**

  In `src/asset_manager.h`, add `<vector>` and declare:

  ```cpp
  static std::vector<std::filesystem::path> getAssetRoots();
  ```

- [ ] **Step 7: Centralize root construction in `src/asset_manager.cpp`**

  Move the local `Candidate` struct from `getAssetPath` into the anonymous namespace and add helpers with these signatures:

  ```cpp
  char path_list_separator();
  std::vector<fs::path> split_asset_path_list(const char* value);
  std::vector<Candidate> build_asset_candidates();
  ```

  Implement `build_asset_candidates()` so it adds candidates in this exact order and deduplicates by `dedup_key(root)` before pushing:

  ```text
  SPACE_ASSETS_PATH entry -> label "SPACE_ASSETS_PATH"
  fs::current_path() / "assets" -> label "cwd"
  fs::path(get_user_data_dir("space")) / "assets" -> label "user-data"
  executable parent / "assets" -> label "executable-sibling"
  executable parent / ".." / "share" / "space" / "assets" -> label "executable-share"
  executable parent / ".." / "Resources" / "assets" -> label "executable-resources"
  fs::path(systemAssetsRoot) -> label "system"
  ```

  `split_asset_path_list` must return no entries for `nullptr`, empty strings, and empty segments from leading/trailing or doubled separators.

- [ ] **Step 8: Implement `AssetManager::getAssetRoots()` and update lookup probing**

  Implement `getAssetRoots()` by returning the roots from `build_asset_candidates()` in order.

  Update `getAssetPath` to call `build_asset_candidates()`. For each candidate:

  ```cpp
  fs::path fullPath = (candidate.root / relativePath).lexically_normal();
  if (!is_contained_under(fullPath, candidate.root)) {
      searched.push_back(candidate.label + ": " + fullPath.string() + " (outside root)");
      continue;
  }
  std::error_code ec;
  if (fs::exists(fullPath, ec)) {
      return fs::absolute(fullPath).string();
  }
  searched.push_back(candidate.label + ": " + fullPath.string());
  ```

  Keep the absolute-path rejection and final `Asset not found: <relativePath>\nSearched paths:\n` format.

- [ ] **Step 9: Run focused AssetManager validation**

  Run with timeout `14400000`:

  ```bash
  make build
  ```

  Run with timeout `600000`:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 ctest --test-dir build -R '^test_asset_manager$' --output-on-failure
  ```

  Expected: `test_asset_manager` passes.

- [ ] **Step 10: Commit Task 1**

  ```bash
  git add src/asset_manager.h src/asset_manager.cpp tests/test_asset_manager.cpp
  git commit -m "feat(engine): implement ordered asset overlay roots"
  ```

---

### Task 2: LuaRuntime Overlay Path Composition

**Files:**
- Modify: `src/lua_runtime.cpp`
- Test: `tests/test_runtime_asset_discovery_integration.cpp`

**Interfaces:**
- Consumes: `AssetManager::getAssetRoots()` from Task 1.
- Produces: Lua `package.path` and Fennel path strings containing every ordered asset root's `lua` directory.

- [ ] **Step 1: Add a safe file-writing helper for the integration test**

  In `tests/test_runtime_asset_discovery_integration.cpp`, add `#include <fstream>` and this helper inside the anonymous namespace:

  ```cpp
  bool write_text_file(const fs::path& path, const std::string& content)
  {
      std::error_code ec;
      fs::create_directories(path.parent_path(), ec);
      if (ec) {
          std::cerr << "FAIL: create directories for " << path << ": " << ec.message() << "\n";
          return false;
      }
      std::ofstream out(path);
      if (!out) {
          std::cerr << "FAIL: open " << path << " for writing\n";
          return false;
      }
      out << content;
      if (!out) {
          std::cerr << "FAIL: write " << path << "\n";
          return false;
      }
      return true;
  }
  ```

- [ ] **Step 2: Refactor the existing integration test into named checks**

  Extract the current arbitrary-CWD `-c "(print (+ 5 3))"` body from `main()` into:

  ```cpp
  bool test_arbitrary_cwd_can_use_executable_relative_assets(const fs::path& executable)
  ```

  Preserve the existing command, environment setup, and assertions that the command exits `0` and output contains `8`.

- [ ] **Step 3: Add a failing project-overlay runtime smoke test**

  Add this test and call it from `main()` after the arbitrary-CWD check:

  ```cpp
  bool test_project_cwd_main_overlays_executable_assets(const fs::path& executable)
  {
      const fs::path projectCwd = fs::temp_directory_path() / "space_runtime_project_overlay";
      const fs::path xdgHome = fs::temp_directory_path() / "space_runtime_project_overlay_xdg";
      fs::remove_all(projectCwd);
      fs::remove_all(xdgHome);
      if (!write_text_file(projectCwd / "assets" / "lua" / "main.fnl",
                           "(print \"space-runtime-project-main-overlay\")\n")) {
          return false;
      }
      fs::create_directories(xdgHome);

      if (!unset_env_var("SPACE_ASSETS_PATH") ||
          !set_env_var("SPACE_DISABLE_AUDIO", "1") ||
          !set_env_var("XDG_DATA_HOME", xdgHome.string())) {
          std::cerr << "FAIL: failed to configure project overlay test environment\n";
          return false;
      }

      std::string command =
          "cd " + shell_quote(projectCwd.string()) + " && " +
          shell_quote(executable.string()) + " --no-dotenv -m main";

      std::string output;
      int exitCode = 1;
      if (!check(run_command_capture(command, output, exitCode), "run project cwd main overlay command")) {
          return false;
      }
      if (!check(exitCode == 0, "project cwd main overlay command should exit 0")) {
          std::cerr << output << "\n";
          return false;
      }
      if (!check(output.find("space-runtime-project-main-overlay") != std::string::npos,
                 "project cwd assets/lua/main.fnl should be loaded")) {
          std::cerr << output << "\n";
          return false;
      }
      return true;
  }
  ```

- [ ] **Step 4: Run the focused test to confirm it fails for fallback composition**

  Run with timeout `14400000`:

  ```bash
  make build
  ```

  Run with timeout `600000`:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 ctest --test-dir build -R '^test_runtime_asset_discovery_integration$' --output-on-failure
  ```

  Expected: the new `-m main` project-overlay case fails before Lua/Fennel path composition is updated, because project `assets/lua` wins but built-in runtime dependencies still need later roots.

- [ ] **Step 5: Compose Lua and Fennel paths from all asset roots**

  In `src/lua_runtime.cpp`, add the missing standard includes needed for `std::filesystem`, `std::ostringstream`, and `std::vector`.

  Replace `make_fennel_asset_search_path(const std::string& lua_path)` with:

  ```cpp
  std::string join_semicolon_paths(const std::vector<std::string>& paths)
  {
      std::ostringstream out;
      for (size_t i = 0; i < paths.size(); i++) {
          if (i > 0) {
              out << ";";
          }
          out << paths[i];
      }
      return out.str();
  }

  std::string make_lua_asset_search_path(const std::vector<std::filesystem::path>& asset_roots)
  {
      std::vector<std::string> paths;
      for (const std::filesystem::path& root : asset_roots) {
          paths.push_back((root / "lua" / "?.lua").string());
      }
      return join_semicolon_paths(paths);
  }

  std::string make_fennel_asset_search_path(const std::vector<std::filesystem::path>& asset_roots)
  {
      std::vector<std::string> paths;
      for (const std::filesystem::path& root : asset_roots) {
          paths.push_back((root / "lua" / "?.fnl").string());
          paths.push_back((root / "lua" / "?" / "init.fnl").string());
      }
      return join_semicolon_paths(paths);
  }
  ```

- [ ] **Step 6: Update `LuaRuntime::configure_package_paths()`**

  Change the function to use all ordered roots:

  ```cpp
  void LuaRuntime::configure_package_paths()
  {
      assets_path_value = AssetManager::getAssetPath("");
      std::vector<std::filesystem::path> asset_roots = AssetManager::getAssetRoots();
      std::string package_path = make_lua_asset_search_path(asset_roots);
      fennel_path_value = make_fennel_asset_search_path(asset_roots);
      lua["package"]["path"] = lua["package"]["path"].get<std::string>() + ";" + package_path;
  }
  ```

  Keep `runtime.assets-path` as the first resolved asset root for compatibility, even though module search paths now include every root.

- [ ] **Step 7: Run focused runtime validation**

  Run with timeout `14400000`:

  ```bash
  make build
  ```

  Run with timeout `600000`:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 ctest --test-dir build -R '^test_asset_manager$' --output-on-failure
  ```

  Run with timeout `600000`:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 ctest --test-dir build -R '^test_runtime_asset_discovery_integration$' --output-on-failure
  ```

  Expected: both focused tests pass.

- [ ] **Step 8: Commit Task 2**

  ```bash
  git add src/lua_runtime.cpp tests/test_runtime_asset_discovery_integration.cpp
  git commit -m "feat(lua): compose runtime asset overlay paths"
  ```

---

### Task 3: Developer Documentation

**Files:**
- Create: `docs/dev/notes/runtime-asset-overlays.md`
- Modify: `docs/dev/notes/index.md`
- Modify: `docs/dev/notes/fennel-runtime-paths.md`

**Interfaces:**
- Consumes: final behavior from Tasks 1 and 2.
- Produces: developer documentation for asset root overlays and Fennel path composition.

- [ ] **Step 1: Create the runtime asset overlay note**

  Create `docs/dev/notes/runtime-asset-overlays.md` with this content:

  ````markdown
  # Runtime Asset Overlays

  Space resolves assets through ordered roots. Earlier roots shadow later roots, so projects can override built-in runtime assets by mirroring the same relative path under `assets/`.

  Search order:

  1. Each non-empty `SPACE_ASSETS_PATH` entry, in order.
  2. `<cwd>/assets`.
  3. User data assets: `get_user_data_dir("space") / "assets"`.
  4. `<exe_dir>/assets`.
  5. `<exe_dir>/../share/space/assets`.
  6. `<exe_dir>/../Resources/assets`.
  7. `/usr/share/space/assets`.

  `SPACE_ASSETS_PATH` entries are asset roots, not project roots. On Unix-like systems the separator is `:`:

  ```bash
  SPACE_ASSETS_PATH=/game/assets:/shared/assets space -m main
  ```

  Requested asset paths remain relative to roots. Absolute paths and traversal that escapes a root are rejected loudly. Missing assets report the requested relative path and the candidate paths searched.

  Normal project launch uses:

  ```text
  project/
    assets/
      lua/main.fnl
  ```

  Running `space --no-dotenv -m main` from `project/` loads `project/assets/lua/main.fnl` before built-in modules. Lua and Fennel module search paths include every asset root in overlay order, so project modules can override built-ins while dependencies not present in the project still fall back to packaged runtime assets.
  ````

- [ ] **Step 2: Link the note from the dev notes index**

  In `docs/dev/notes/index.md`, add this line alphabetically after `Ripgrep`:

  ```markdown
  - [Runtime Asset Overlays](./runtime-asset-overlays)
  ```

- [ ] **Step 3: Update Fennel runtime path documentation**

  In `docs/dev/notes/fennel-runtime-paths.md`, replace lines 5-11 with:

  ````markdown
  The canonical runtime path pattern for each asset root is:

  ```text
  <asset-root>/lua/?.fnl;<asset-root>/lua/?/init.fnl
  ```

  Asset roots are ordered by the runtime asset overlay search order. Flat files intentionally take precedence over directory `init.fnl` modules within each root, and earlier roots shadow later roots. See [Runtime Asset Overlays](./runtime-asset-overlays) for the full root order.
  ````

- [ ] **Step 4: Validate documentation text**

  Run with timeout `600000`:

  ```bash
  rg -n "Runtime Asset Overlays|SPACE_ASSETS_PATH|<cwd>/assets|runtime-asset-overlays" docs/dev/notes/runtime-asset-overlays.md docs/dev/notes/index.md docs/dev/notes/fennel-runtime-paths.md
  ```

  Expected: matches appear in all three files.

- [ ] **Step 5: Commit Task 3**

  ```bash
  git add docs/dev/notes/runtime-asset-overlays.md docs/dev/notes/index.md docs/dev/notes/fennel-runtime-paths.md
  git commit -m "docs: document runtime asset overlays"
  ```

---

### Task 4: Final Local Validation

**Files:**
- Modify: none
- Test: build, focused CTest targets, full relevant local suite.

**Interfaces:**
- Consumes: completed Tasks 1-3.
- Produces: evidence for finishing-a-development-branch and PR CI.

- [ ] **Step 1: Verify the tree is clean before final validation**

  Run:

  ```bash
  git status --porcelain
  ```

  Expected: no output.

- [ ] **Step 2: Rebuild the runtime**

  Run with timeout `14400000`:

  ```bash
  make build
  ```

  Expected: build succeeds.

- [ ] **Step 3: Run focused C++ asset tests**

  Run with timeout `600000`:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 ctest --test-dir build -R '^test_asset_manager$' --output-on-failure
  ```

  Expected: pass.

- [ ] **Step 4: Run focused runtime startup tests**

  Run with timeout `600000`:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 ctest --test-dir build -R '^test_runtime_asset_discovery_integration$' --output-on-failure
  ```

  Expected: pass.

- [ ] **Step 5: Run the full relevant local suite**

  Run with timeout `14400000`:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: pass.

- [ ] **Step 6: Hand off to finishing-a-development-branch**

  After validation passes, invoke `finishing-a-development-branch` to fetch `origin`, evaluate against current `origin/main`, recover through systematic debugging if any required validation fails, push the branch, create the PR targeting `main`, and monitor the merge queue per project policy.
