# CI Prebuilt Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Speed up pull-request `test` status checks for assets/Fennel-only changes by reusing a trusted minimal Linux runtime built on `main`, while keeping native-impacting and merge-queue checks on the full build/test path.

**Architecture:** The required `test` job keeps its existing job name and decides one of three modes from changed paths: docs-only skip, prebuilt-runtime validation, or full native validation. Main push runs still build from source and upload the `build/space` runtime artifact for future PRs; PRs that can use that artifact download only from successful `main` push runs and fall back to full native validation if artifact resolution fails.

**Tech Stack:** GitHub Actions, Bash, GitHub CLI (`gh`), Python 3 unit tests for path classification, CMake/Ninja, `ccache`, `sccache`, Space native `./build/space` Fennel validation commands.

## Global Constraints

- Keep the required GitHub status check job named `test`; do not replace it with differently named required jobs.
- `merge_group` always runs the full native build and test suite; do not use prebuilt runtime artifacts for merge queue.
- `push` to `main` always runs the full native build and test suite, then uploads the runtime artifact only after a successful build step.
- Only `pull_request` events may use the prebuilt runtime fast path.
- The prebuilt runtime must come from a successful `test.yml` `push` run on `main`; never download artifacts from PR or merge-group runs.
- If prebuilt artifact lookup, download, or install fails, fall back to full native validation rather than passing or failing early.
- Docs-only PRs may skip native validation only when every changed path is under `docs/` or is a root `*.md` file.
- Prebuilt-runtime PRs may skip native compilation only when every changed path is under `assets/`, `docs/`, or is a root `*.md` file.
- Any change to `.github/`, `scripts/`, `src/`, `apps/`, `external/`, `ffi/`, `tests/`, `CMakeLists.txt`, `Makefile`, `*.cmake`, or any other non-asset/non-doc path requires full native validation.
- For prebuilt-runtime validation, set `SPACE_ASSETS_PATH` to <code v-pre>${{ github.workspace }}/assets</code> and set `FENNEL_PATH`/`FENNEL_MACRO_PATH` to <code v-pre>${{ github.workspace }}/assets/lua/?.fnl;${{ github.workspace }}/assets/lua/?/init.fnl</code>.
- Keep recent Ninja and per-run compiler cache stat improvements unless review finds a correctness issue.

---

## File Structure

- Create `scripts/ci_test_scope.py`: pure Python path-classification helper and optional CLI that converts an event name plus changed paths into GitHub-output-friendly keys.
- Create `scripts/tests/test_ci_test_scope.py`: unit tests for docs-only, prebuilt-runtime, full-native, empty-change, push, and merge-group classification behavior.
- Modify `.github/workflows/test.yml`: call `scripts/ci_test_scope.py`, add artifact upload on successful `main` push builds, add prebuilt-runtime artifact download/fallback, and add direct Fennel/assets validation using the prebuilt runtime.
- Modify `.github/workflows/build.yml`: keep/verify Linux Ninja and current-run compiler-cache stat reset changes for release builds.

---

### Task 1: Tested CI scope classifier

**Files:**
- Create: `scripts/ci_test_scope.py`
- Create: `scripts/tests/test_ci_test_scope.py`

**Interfaces:**
- Produces: `classify(event_name: str, changed_paths: Iterable[str]) -> ScopeDecision`
- Produces: `ScopeDecision.mode`, one of `"docs-only"`, `"prebuilt-runtime"`, or `"full-native"`
- Produces CLI output lines for GitHub Actions: `mode=...`, `run-native=true|false`, `use-prebuilt-runtime=true|false`, `run-runtime-tests=true|false`, `reason=...`

- [ ] **Step 1: Write failing tests**

Create `scripts/tests/test_ci_test_scope.py` with these tests:

```python
from scripts.ci_test_scope import classify


def test_pull_request_docs_only_skips_native_validation():
    decision = classify(
        "pull_request",
        ["docs/dev/notes/opencode-mcp-bridges.md", "README.md"],
    )
    assert decision.mode == "docs-only"
    assert decision.run_native is False
    assert decision.use_prebuilt_runtime is False
    assert decision.run_runtime_tests is False


def test_pull_request_assets_use_prebuilt_runtime_validation():
    decision = classify(
        "pull_request",
        ["assets/lua/tree-view.fnl", "assets/lua/tests/test-tree-view.fnl"],
    )
    assert decision.mode == "prebuilt-runtime"
    assert decision.run_native is False
    assert decision.use_prebuilt_runtime is True
    assert decision.run_runtime_tests is True


def test_pull_request_mixed_assets_and_docs_use_prebuilt_runtime_validation():
    decision = classify(
        "pull_request",
        ["assets/lua/tree-view.fnl", "docs/dev/features/tree-view-widget.md"],
    )
    assert decision.mode == "prebuilt-runtime"
    assert decision.use_prebuilt_runtime is True


def test_pull_request_native_path_requires_full_validation():
    decision = classify("pull_request", ["src/lua_engine.cpp"])
    assert decision.mode == "full-native"
    assert decision.run_native is True
    assert decision.use_prebuilt_runtime is False
    assert decision.run_runtime_tests is True
    assert "src/lua_engine.cpp" in decision.reason


def test_pull_request_workflow_path_requires_full_validation():
    decision = classify("pull_request", [".github/workflows/test.yml"])
    assert decision.mode == "full-native"
    assert decision.run_native is True
    assert decision.use_prebuilt_runtime is False


def test_push_to_main_never_uses_prebuilt_runtime_even_for_assets():
    decision = classify("push", ["assets/lua/tree-view.fnl"])
    assert decision.mode == "full-native"
    assert decision.run_native is True
    assert decision.use_prebuilt_runtime is False


def test_merge_group_never_uses_prebuilt_runtime_even_for_assets():
    decision = classify("merge_group", ["assets/lua/tree-view.fnl"])
    assert decision.mode == "full-native"
    assert decision.run_native is True
    assert decision.use_prebuilt_runtime is False


def test_empty_change_list_runs_full_validation():
    decision = classify("pull_request", [])
    assert decision.mode == "full-native"
    assert decision.run_native is True
    assert decision.use_prebuilt_runtime is False
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
python3 -m pytest scripts/tests/test_ci_test_scope.py -q
```

Expected before implementation: FAIL because `scripts.ci_test_scope` does not exist.

- [ ] **Step 3: Implement classifier**

Create `scripts/ci_test_scope.py` with:

```python
#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass
from typing import Iterable


@dataclass(frozen=True)
class ScopeDecision:
    mode: str
    run_native: bool
    use_prebuilt_runtime: bool
    run_runtime_tests: bool
    reason: str


def _is_docs_only_path(path: str) -> bool:
    return path.startswith("docs/") or ("/" not in path and path.endswith(".md"))


def _is_asset_runtime_path(path: str) -> bool:
    return path.startswith("assets/") or _is_docs_only_path(path)


def classify(event_name: str, changed_paths: Iterable[str]) -> ScopeDecision:
    paths = [path for path in changed_paths if path]
    if not paths:
        return ScopeDecision(
            mode="full-native",
            run_native=True,
            use_prebuilt_runtime=False,
            run_runtime_tests=True,
            reason="no changed files detected; running full suite",
        )

    if event_name != "pull_request":
        return ScopeDecision(
            mode="full-native",
            run_native=True,
            use_prebuilt_runtime=False,
            run_runtime_tests=True,
            reason=f"full suite required for {event_name}",
        )

    if all(_is_docs_only_path(path) for path in paths):
        return ScopeDecision(
            mode="docs-only",
            run_native=False,
            use_prebuilt_runtime=False,
            run_runtime_tests=False,
            reason="docs-only change",
        )

    for path in paths:
        if not _is_asset_runtime_path(path):
            return ScopeDecision(
                mode="full-native",
                run_native=True,
                use_prebuilt_runtime=False,
                run_runtime_tests=True,
                reason=f"native-impacting change: {path}",
            )

    return ScopeDecision(
        mode="prebuilt-runtime",
        run_native=False,
        use_prebuilt_runtime=True,
        run_runtime_tests=True,
        reason="assets-only change; validating with trusted main runtime",
    )


def _bool(value: bool) -> str:
    return "true" if value else "false"


def main() -> int:
    parser = argparse.ArgumentParser(description="Classify CI validation scope from changed paths.")
    parser.add_argument("--event", required=True)
    parser.add_argument("--changed-file", action="append", default=[])
    args = parser.parse_args()
    decision = classify(args.event, args.changed_file)
    print(f"mode={decision.mode}")
    print(f"run-native={_bool(decision.run_native)}")
    print(f"use-prebuilt-runtime={_bool(decision.use_prebuilt_runtime)}")
    print(f"run-runtime-tests={_bool(decision.run_runtime_tests)}")
    print(f"reason={decision.reason}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run tests to verify GREEN**

Run:

```bash
python3 -m pytest scripts/tests/test_ci_test_scope.py -q
```

Expected: PASS.

---

### Task 2: Wire prebuilt runtime mode into required `test` workflow

**Files:**
- Modify: `.github/workflows/test.yml`

**Interfaces:**
- Consumes: `scripts/ci_test_scope.py --event <event> --changed-file <path>` output keys from Task 1.
- Produces: artifact named `space-linux-minimal-runtime` on successful `push` runs to `main`.
- Produces: PR fast path that downloads that artifact only from successful `test.yml` `push` runs on `main`.

- [ ] **Step 1: Update changed-file classification to use the script**

Replace inline path classification in `Determine test scope` with a shell step that gathers changed files, then calls the classifier. Preserve conservative fallback if base fetch fails.

Required shell shape:

```bash
set -euo pipefail

changed_files=""
classification_args=(--event "${EVENT_NAME}")

if [[ "${EVENT_NAME}" == "pull_request" ]]; then
  if git fetch --no-tags --depth=1 origin "${BASE_REF}:refs/remotes/origin/${BASE_REF}"; then
    changed_files="$(git diff --name-only "origin/${BASE_REF}"...HEAD)"
  fi
elif [[ "${EVENT_NAME}" == "push" && -n "${BEFORE_SHA}" && ! "${BEFORE_SHA}" =~ ^0+$ ]]; then
  if git fetch --no-tags --depth=1 origin "${BEFORE_SHA}"; then
    changed_files="$(git diff --name-only "${BEFORE_SHA}" HEAD)"
  fi
fi

while IFS= read -r path; do
  if [[ -n "${path}" ]]; then
    classification_args+=(--changed-file "${path}")
  fi
done <<< "${changed_files}"

python3 scripts/ci_test_scope.py "${classification_args[@]}" | tee "${RUNNER_TEMP}/test-scope.env"
cat "${RUNNER_TEMP}/test-scope.env" >> "${GITHUB_OUTPUT}"
```

- [ ] **Step 2: Keep docs-only skip, but key it from `mode`**

Use:

```yaml
if: steps.test-scope.outputs.mode == 'docs-only'
```

for the docs-only message step.

- [ ] **Step 3: Install runtime dependencies for full-native and prebuilt-runtime modes**

Run dependency installation when:

```yaml
if: steps.test-scope.outputs.run-runtime-tests == 'true'
```

Keep `ninja-build` installed. Keep compiler-cache restore, compiler-cache stat reset, `make opencode-check`, and `make build` limited to:

```yaml
if: steps.test-scope.outputs.run-native == 'true'
```

- [ ] **Step 4: Upload trusted runtime artifact from main push builds**

After `Build` and before tests, add:

```yaml
      - name: Upload prebuilt Linux runtime
        if: github.event_name == 'push' && github.ref == 'refs/heads/main' && steps.test-scope.outputs.run-native == 'true'
        uses: actions/upload-artifact@v5
        with:
          name: space-linux-minimal-runtime
          path: build/space
          if-no-files-found: error
          retention-days: 7
```

- [ ] **Step 5: Download prebuilt runtime for eligible PRs, falling back to full native**

Add a `Resolve prebuilt runtime` step with `id: prebuilt-runtime`, running when `steps.test-scope.outputs.use-prebuilt-runtime == 'true'`. It must:

1. Use <code v-pre>GH_TOKEN: ${{ github.token }}</code>.
2. Query latest successful `test.yml` push run on `main`.
3. Download only artifact `space-linux-minimal-runtime` from that run.
4. Install it to `build/space` and `chmod +x build/space`.
5. Output `available=true` on success and `available=false` on any lookup/download/install failure.

Required shell shape:

```bash
set -euo pipefail
mkdir -p build
run_id="$(gh run list \
  --repo "${GITHUB_REPOSITORY}" \
  --workflow test.yml \
  --branch main \
  --event push \
  --status success \
  --json databaseId \
  --jq '.[0].databaseId // empty')"

if [[ -z "${run_id}" ]]; then
  echo "available=false" >> "${GITHUB_OUTPUT}"
  echo "No successful main test.yml push run found; falling back to full native validation."
  exit 0
fi

if gh run download "${run_id}" \
  --repo "${GITHUB_REPOSITORY}" \
  --name space-linux-minimal-runtime \
  --dir prebuilt-runtime; then
  cp prebuilt-runtime/space build/space
  chmod +x build/space
  echo "available=true" >> "${GITHUB_OUTPUT}"
else
  echo "available=false" >> "${GITHUB_OUTPUT}"
  echo "Unable to download prebuilt runtime from run ${run_id}; falling back to full native validation."
fi
```

- [ ] **Step 6: Add fallback native build when prebuilt runtime is unavailable**

Ensure compiler-cache setup, stat reset, `make opencode-check`, and `Build` also run when `steps.prebuilt-runtime.outputs.available == 'false'`. Use a consistent expression equivalent to:

```yaml
if: steps.test-scope.outputs.run-native == 'true' || steps.prebuilt-runtime.outputs.available == 'false'
```

Do not run compiler-cache setup for docs-only mode.

- [ ] **Step 7: Add prebuilt-runtime validation commands**

Before the full CTest step, add a step named `Run prebuilt runtime validation` that runs only when `steps.prebuilt-runtime.outputs.available == 'true'`.

Required commands:

```bash
set -euo pipefail
export SPACE_ASSETS_PATH="${GITHUB_WORKSPACE}/assets"
export FENNEL_PATH="${GITHUB_WORKSPACE}/assets/lua/?.fnl;${GITHUB_WORKSPACE}/assets/lua/?/init.fnl"
export FENNEL_MACRO_PATH="${GITHUB_WORKSPACE}/assets/lua/?.fnl;${GITHUB_WORKSPACE}/assets/lua/?/init.fnl"
./build/space -m tools.fennel-check:main -- --output summary --target repo
./build/space -m constraints.runner:main -- --output summary --target repo
xvfb-run -a ./build/space -m tests.fast:main
```

Then let the existing `Run e2e test suite` step run when either full-native validation has built from source or `steps.prebuilt-runtime.outputs.available == 'true'`.

- [ ] **Step 8: Verify workflow syntax and classifier tests**

Run:

```bash
python3 -m pytest scripts/tests/test_ci_test_scope.py -q
python3 - <<'PY'
import pathlib
import yaml
for name in ['.github/workflows/test.yml', '.github/workflows/build.yml']:
    yaml.safe_load(pathlib.Path(name).read_text())
    print(f'{name}: yaml ok')
PY
git diff --check -- .github/workflows/test.yml .github/workflows/build.yml scripts/ci_test_scope.py scripts/tests/test_ci_test_scope.py
```

Expected: all commands pass. If PyYAML is unavailable, record that and run the pytest plus `git diff --check` commands.

---

### Task 3: Review current release workflow speedups

**Files:**
- Modify/verify: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: existing release Linux build job.
- Produces: Linux release build still uses compiler cache launchers, now with `CMAKE_GENERATOR: Ninja` and zeroed cache stats before the build.

- [ ] **Step 1: Preserve the intended release workflow changes**

Ensure `build-linux` has:

```yaml
      CMAKE_GENERATOR: Ninja
```

and dependency installation includes:

```bash
sudo apt-get install -y ${deps} ccache ninja-build rpm
```

- [ ] **Step 2: Preserve current-run cache stat reset**

Ensure a step before `Configure and Build` contains:

```bash
ccache -z
if command -v sccache >/dev/null 2>&1; then
  sccache --zero-stats
fi
```

- [ ] **Step 3: Verify workflow syntax**

Run the YAML and `git diff --check` validation from Task 2 Step 8.

Expected: PASS.

---

## Self-Review

- Spec coverage: The plan covers docs-only skip, asset/Fennel-only prebuilt runtime use, main artifact production, conservative merge queue/full-native fallback, Ninja, and per-run cache stats.
- Placeholder scan: No task contains TBD/TODO/implement-later language; each implementation step includes exact files, commands, or shell shape.
- Type consistency: `ScopeDecision` and the CLI output keys are defined in Task 1 and consumed consistently by Task 2.
