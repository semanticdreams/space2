# Windows Packaged Fast-Suite Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix PR #127 Windows packaged `tests.fast` failures by making test child-process, path, and fixture assumptions portable under the packaged runtime.

**Architecture:** Add one test-only runtime binary resolver and use it from tests that spawn child Space processes. Keep production graph architecture unchanged; fix only the runner basename bug and test/helper assumptions around Windows separators and packaged asset mutability. Windows CI will pass the explicit packaged executable path through `SPACE_BIN`.

**Tech Stack:** Space Fennel, project-native `./build/space` Fennel validation, GitHub Actions Windows packaged runtime, existing `fs`, `process`, `app.engine.get-asset-path`, and test runner modules.

## Global Constraints

- No backward-compatible artifact aliases; Windows runtime binary in CI is `build/dist/windows/space-cli.exe`.
- Fennel validation ladder: compile check for touched files, constraints, focused tests, then CI/pushed Windows job.
- Use project-native Fennel validation only; no system Lua/Fennel.
- Avoid silent fallbacks; tests should fail explicitly when executable/asset lookup cannot resolve.
- Graph doctrine: keep graph adapters decoupled; these are tests/helper fixes plus one runner path bug, not graph architecture changes.
- Before any command that invokes `./build/space`, run `make build` first if the binary may be missing or stale.
- On Fennel delimiter or parse errors, inspect the nearest enclosing form, simplify into helpers if needed, then rerun the touched-file compile check before constraints/tests.

---

## Acceptance Criteria

- PR #127 Windows `test-windows` job runs `build/dist/windows/space-cli.exe -m tests.fast:main` successfully.
- `test-lazy-text-buffer` and `test-fs` child processes use the resolved Space executable and fail with an explicit lookup error if none is available.
- Windows CI sets `SPACE_BIN` to <code v-pre>${{ github.workspace }}\build\dist\windows\space-cli.exe</code>.
- Agent permission assertions remain complete but compare path patterns slash-normalized.
- Agent runner default artifact root treats both `/agent-sessions` and `\agent-sessions` as the special sibling-artifact case.
- Workflow graph and graph view tests do not read or write repo-relative/package-relative mutable paths under packaged assets.
- `docs/dev/features/development-tooling.md` documents the packaged fast-suite `SPACE_BIN` expectation.

## Out of Scope

- No graph node, graph map, graph persistence, or graph adapter redesign.
- No artifact alias creation or packaged binary rename.
- No writable packaged-assets assumption or asset-copy workaround.
- No broad test harness rewrite.
- No system Lua/Fennel validation.

---

### Task 1: Portable Test Runtime Binary Resolution

**Files:**
- Create: `assets/lua/tests/runtime-bin.fnl`
- Create: `assets/lua/tests/test-runtime-bin.fnl`
- Modify: `assets/lua/tests/test-lazy-text-buffer.fnl`
- Modify: `assets/lua/tests/test-fs.fnl`
- Modify: `assets/lua/tests/fast.fnl`
- Modify: `.github/workflows/test.yml`
- Modify: `docs/dev/features/development-tooling.md`

**Interfaces:**
- Consumes: `fs.exists`, `fs.cwd`, `fs.join-path`, `os.getenv`.
- Produces: `tests.runtime-bin.resolve(opts?: table) -> string`
  - Honors `SPACE_BIN` first.
  - If `SPACE_BIN` is set, asserts that path exists.
  - Otherwise searches only supported local/package candidates, including `build/dist/windows/space-cli.exe`.
  - Raises an explicit error when no executable resolves.

- [ ] **Step 1: Add the RED tests for runtime binary resolution.**
  Create `assets/lua/tests/test-runtime-bin.fnl` with fake `fs`/`getenv` dependencies covering:
  - explicit `SPACE_BIN` wins;
  - explicit missing `SPACE_BIN` errors;
  - packaged Windows candidate `build/dist/windows/space-cli.exe` resolves;
  - no candidates errors with `could not locate space binary`.

- [ ] **Step 2: Register the new test module in the fast suite.**
  Add `:tests.test-runtime-bin` near `:tests.test-lazy-text-buffer` in `assets/lua/tests/fast.fnl`.

- [ ] **Step 3: Run RED validation for the new test.**
  If needed first run `make build` with timeout `14400000`. Then run:
  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-runtime-bin.fnl --file assets/lua/tests/fast.fnl
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-runtime-bin:main
  ```
  Expected before implementation: compile or test failure because `tests.runtime-bin` does not exist.

- [ ] **Step 4: Implement `assets/lua/tests/runtime-bin.fnl`.**
  Export `{:resolve resolve}`. Candidate order must include:
  - `SPACE_BIN` if set, with existence assertion;
  - `build/space`;
  - `build/space.exe`;
  - `build/dist/windows/space-cli.exe`;
  - `space`;
  - `space.exe`;
  - `../build/space`;
  - `../build/space.exe`.

- [ ] **Step 5: Replace duplicated helpers.**
  In `test-lazy-text-buffer.fnl` and `test-fs.fnl`, require `tests.runtime-bin`, replace local `space-bin` fallback logic with `RuntimeBin.resolve`, and pass `SPACE_BIN` into child `process.run` env as the resolved executable.

- [ ] **Step 6: Set `SPACE_BIN` in Windows CI.**
  In `.github/workflows/test.yml`, add to the `Run Windows fast suite` env:
  ```yaml
  SPACE_BIN: ${{ github.workspace }}\build\dist\windows\space-cli.exe
  ```

- [ ] **Step 7: Document the workflow contract.**
  Update `docs/dev/features/development-tooling.md` under the test harness/tooling design notes to state that packaged fast-suite child-process tests resolve the runtime through `SPACE_BIN`, and Windows CI sets it to `build/dist/windows/space-cli.exe`.

- [ ] **Step 8: Run GREEN validation for Task 1.**
  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/runtime-bin.fnl --file assets/lua/tests/test-runtime-bin.fnl --file assets/lua/tests/test-lazy-text-buffer.fnl --file assets/lua/tests/test-fs.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-runtime-bin:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-lazy-text-buffer:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fs:main
  ```

---

### Task 2: Windows-Safe Agent Artifact and Permission Path Assertions

**Files:**
- Modify: `assets/lua/llm/agent/runner.fnl`
- Modify: `assets/lua/tests/test-agent-layer.fnl`

**Interfaces:**
- Consumes: existing runner session lifecycle and `tests.path-utils`.
- Produces: no new public interface. Internal `default-artifact-root(data-dir: string) -> string` must recognize `agent-sessions` after either slash style.

- [ ] **Step 1: Add RED expectations in `test-agent-layer.fnl`.**
  Update the OpenCode MCP bridge config test with local helpers:
  - `slash-path(path) -> string`, replacing `\` with `/`;
  - `permission-value(permissions, expected-pattern) -> string|nil`, matching keys by slash-normalized pattern;
  - `assert-pattern-permission(permissions, expected-pattern, expected-value, message)`.
  Use these helpers for every allowed root and every secret deny pattern so assertions remain exhaustive.

- [ ] **Step 2: Update artifact path assertions.**
  In `test-runner-default-artifacts-nested-under-non-session-data-dir` and `test-runner-default-artifacts-sibling-for-agent-sessions-data-dir`, use `PathUtils.paths-eq` for `root` and `session-dir` comparisons while keeping `fs.exists expected-session-dir`.

- [ ] **Step 3: Run RED/focused check for agent tests.**
  If needed first run `make build` with timeout `14400000`. Then run:
  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-agent-layer.fnl
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-layer:main
  ```
  Expected on Windows before the runner fix: sibling artifact root assertion still fails.

- [ ] **Step 4: Fix runner basename logic.**
  In `assets/lua/llm/agent/runner.fnl`, normalize `data-dir` separators before extracting basename:
  ```fennel
  (local normalized-data-dir (string.gsub data-dir "\\" "/"))
  (local basename (string.match normalized-data-dir "[^/]+$"))
  ```
  Keep `fs.parent data-dir` and `fs.join-path` on the original path.

- [ ] **Step 5: Run GREEN validation for Task 2.**
  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/llm/agent/runner.fnl --file assets/lua/tests/test-agent-layer.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-layer:main
  ```

---

### Task 3: Package-Safe Workflow Graph and Graph View Test Fixtures

**Files:**
- Modify: `assets/lua/tests/test-workflow-graph.fnl`
- Modify: `assets/lua/tests/test-graph-view.fnl`

**Interfaces:**
- Consumes: `app.engine.get-asset-path(relative-path: string) -> string`, existing `with-temp-dir`, existing `PathUtils.paths-eq`.
- Produces: no new public interface.

- [ ] **Step 1: Fix workflow graph read-only source lookup.**
  In `workflow-run-node-and-preview-have-no-generic-details-leftovers-case`, replace:
  ```fennel
  (fs.read-file "assets/lua/graph/nodes/workflow-run.fnl")
  ```
  with:
  ```fennel
  (fs.read-file (app.engine.get-asset-path "lua/graph/nodes/workflow-run.fnl"))
  ```

- [ ] **Step 2: Move relative text viewer fixture out of packaged assets.**
  In `fs-node-relative-text-viewer-uses-absolute-key`, replace `assets/lua/tests/data/fs-node-relative-viewer.md` with a writable relative temp path under `.tmp/space-tests/`, ensure its parent directory is created, and clean it up after the graph drops. Preserve assertions that:
  - interaction path is absolute;
  - target key uses the absolute path;
  - opening the entry returns the absolute-key viewer node.

- [ ] **Step 3: Move relative directory fixture out of packaged assets.**
  In `fs-node-relative-directory-open-entry-preserves-relative-child-key`, replace `assets/lua/tests/data/fs-node-relative-dir` with a writable relative temp directory under `.tmp/space-tests/`, ensure cleanup on success and failure, and preserve assertions that:
  - the child is listed;
  - the child path remains relative by raw comparison against its absolute form;
  - slash/case-normalized path equality matches the expected child path;
  - opening the child adds the expected relative `fs:` key, comparing via the actual `fs.join-path` result.

- [ ] **Step 4: Run GREEN validation for Task 3.**
  If needed first run `make build` with timeout `14400000`. Then run:
  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-workflow-graph.fnl --file assets/lua/tests/test-graph-view.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  ```

---

### Task 4: Final Validation and PR #127 Windows CI Verification

**Files:**
- Test: all files modified by Tasks 1-3.

**Interfaces:**
- Consumes: all Task 1-3 changes.
- Produces: validated PR #127 branch with Windows packaged fast-suite passing in PR CI.

- [ ] **Step 1: Ensure runtime freshness.**
  ```bash
  make build
  ```

- [ ] **Step 2: Run touched-file Fennel compile check.**
  ```bash
  ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/runtime-bin.fnl --file assets/lua/tests/test-runtime-bin.fnl --file assets/lua/tests/test-lazy-text-buffer.fnl --file assets/lua/tests/test-fs.fnl --file assets/lua/tests/fast.fnl --file assets/lua/llm/agent/runner.fnl --file assets/lua/tests/test-agent-layer.fnl --file assets/lua/tests/test-workflow-graph.fnl --file assets/lua/tests/test-graph-view.fnl
  ```

- [ ] **Step 3: Run constraints.**
  ```bash
  make constraints
  ```

- [ ] **Step 4: Run focused Fennel tests.**
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-runtime-bin:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-lazy-text-buffer:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fs:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-agent-layer:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-workflow-graph:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  ```

- [ ] **Step 5: Run the complete relevant local suite.**
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
  ```

- [ ] **Step 6: Push PR #127 branch and verify PR CI.**
  PR CI is the full integration gate. After pushing, poll the `test.yml` run for PR #127 and require the Windows `test-windows` job to pass:
  ```bash
  gh pr checks 127 --watch
  gh run list --workflow test.yml --limit 10 --json databaseId,headBranch,headSha,status,conclusion,url
  gh run watch <run-id> --exit-status --interval 100
  ```
  If GitHub access or PR check visibility is unavailable, report `HUMAN_DECISION_REQUIRED` with the exact missing permission or unavailable check name.
