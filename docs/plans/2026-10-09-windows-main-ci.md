# Windows Main CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Windows build/test validation out of the PR/merge-queue `test` workflow and into a dedicated post-merge/manual Windows workflow.

**Architecture:** Keep `test.yml` as the Linux-only PR, `main`, and merge-queue gate. Create a separate Windows workflow that reuses the existing Windows cross-build, packaging, Wine smoke, artifact transfer, and native fast-suite jobs, triggered only by `push` to `main` and `workflow_dispatch`.

**Tech Stack:** GitHub Actions YAML, local composite actions under `.github/actions`, Bash, PowerShell, Python stdlib static checks, `actionlint` when available.

## Global Constraints

- Keep PR and merge-queue feedback fast by making `test.yml` Linux-only.
- Keep Windows regressions close to the responsible change by running Windows validation on every push to `main`.
- Keep a manual Windows validation entry point for maintainers.
- Avoid scheduled Windows runs for now.
- Preserve the existing Windows validation behavior when the Windows workflow runs: cross-build, package, Wine smoke, artifact upload/download, and native Windows fast suite.
- Keep release packaging in `build.yml` unchanged.
- Do not change Windows build commands, dependency sets, package contents, or test commands.
- Do not change branch protection settings in repository configuration in this implementation.

---

## File Structure

- Modify `.github/workflows/test.yml` — remove `build-windows` and `test-windows`, leaving the Linux `test` job and existing PR/merge-queue/main triggers.
- Create `.github/workflows/windows.yml` — new workflow containing the existing Windows `build-windows` and `test-windows` jobs, triggered by `push` to `main` and `workflow_dispatch` only.
- Modify `scripts/check-github-workflow-hygiene.py` — add static guardrails that Windows jobs are not in `test.yml`, the Windows workflow has no PR/merge-group/schedule trigger, and expected Windows jobs are present in `windows.yml`.
- Modify `docs/dev/notes/github-actions-hygiene.md` — document that PR CI is Linux-only while Windows validation runs on main pushes/manual dispatch.

---

### Task 1: Split Windows validation into a main-push workflow

**Files:**
- Modify: `.github/workflows/test.yml`
- Create: `.github/workflows/windows.yml`

**Interfaces:**
- Consumes: existing Windows jobs from `.github/workflows/test.yml`: `build-windows` and `test-windows`.
- Produces: `.github/workflows/windows.yml` with jobs `build-windows` and `test-windows` and artifact `space-windows-runtime`.
- Produces: `.github/workflows/test.yml` with only the Linux `test` job under `jobs:`.

- [ ] **Step 1: Create the Windows workflow by moving existing jobs**

  Create `.github/workflows/windows.yml` with this workflow header:

  ```yaml
  name: windows

  on:
    push:
      branches:
        - main
    workflow_dispatch:

  concurrency:
    group: ${{ github.workflow }}-${{ github.ref }}
    cancel-in-progress: true

  permissions:
    contents: read

  env:
    FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true

  jobs:
  ```

  Under `jobs:`, move the existing `build-windows` and `test-windows` jobs from `.github/workflows/test.yml` without changing their commands, env, artifact name, cache inputs, or job dependency.

- [ ] **Step 2: Preserve Windows job permissions**

  In `windows.yml`, keep `build-windows` job permissions exactly as:

  ```yaml
      permissions:
        contents: read
        actions: write
  ```

  Leave `test-windows` without additional write permissions.

- [ ] **Step 3: Remove Windows jobs from `test.yml`**

  Remove the `build-windows` and `test-windows` jobs from `.github/workflows/test.yml`. Leave:

  ```yaml
  jobs:
    test:
  ```

  Keep existing `test.yml` triggers:

  ```yaml
  on:
    push:
      branches:
        - main
    pull_request:
      branches:
        - main
    merge_group:
  ```

  Keep existing Linux job steps unchanged.

- [ ] **Step 4: Run focused static checks for this task**

  Run:

  ```bash
  python3 - <<'PY'
  from pathlib import Path
  test = Path('.github/workflows/test.yml').read_text()
  windows = Path('.github/workflows/windows.yml').read_text()
  assert 'build-windows:' not in test
  assert 'test-windows:' not in test
  assert 'pull_request:' in test
  assert 'merge_group:' in test
  assert 'build-windows:' in windows
  assert 'test-windows:' in windows
  assert 'pull_request:' not in windows
  assert 'merge_group:' not in windows
  assert 'schedule:' not in windows
  assert 'workflow_dispatch:' in windows
  print('workflow split checks passed')
  PY
  python3 - <<'PY'
  from pathlib import Path
  try:
      import yaml
  except Exception:
      raise SystemExit('PyYAML is not available; YAML parse skipped')
  for path in ['.github/workflows/test.yml', '.github/workflows/windows.yml']:
      yaml.safe_load(Path(path).read_text())
      print(f'parsed {path}')
  PY
  if command -v actionlint >/dev/null 2>&1; then actionlint .github/workflows/test.yml .github/workflows/windows.yml; else echo 'actionlint not available'; fi
  ```

  Expected: static assertions pass; YAML parse passes when PyYAML is available or reports it is unavailable; actionlint passes when available or reports it is unavailable.

---

### Task 2: Add static guardrails and documentation

**Files:**
- Modify: `scripts/check-github-workflow-hygiene.py`
- Modify: `docs/dev/notes/github-actions-hygiene.md`

**Interfaces:**
- Consumes: `.github/workflows/test.yml` and `.github/workflows/windows.yml` from Task 1.
- Produces: `python3 scripts/check-github-workflow-hygiene.py` enforcing the Windows workflow routing policy.
- Produces: documentation that explains Linux PR CI and post-merge/manual Windows CI.

- [ ] **Step 1: Add hygiene checks for Windows workflow routing**

  Extend `scripts/check-github-workflow-hygiene.py` so it fails when:

  - `.github/workflows/test.yml` contains `build-windows:` or `test-windows:`;
  - `.github/workflows/windows.yml` is missing;
  - `.github/workflows/windows.yml` is missing `build-windows:` or `test-windows:`;
  - `.github/workflows/windows.yml` contains `pull_request:`, `merge_group:`, `schedule:`, or `cron:`;
  - `.github/workflows/windows.yml` does not contain `workflow_dispatch:`;
  - `.github/workflows/windows.yml` does not contain a `push` trigger for `main`.

  The check can use text assertions consistent with the existing checker style. Keep the script Python stdlib-only.

- [ ] **Step 2: Document workflow routing policy**

  In `docs/dev/notes/github-actions-hygiene.md`, add a section:

  ```markdown
  ## PR and Windows validation routing

  The `test` workflow is the PR and merge-queue gate and runs Linux validation.
  Windows validation lives in the `windows` workflow and runs on pushes to
  `main` plus manual dispatch. This keeps PR feedback fast while detecting
  Windows regressions immediately after merge with a small culprit range. Windows
  is intentionally not scheduled by default.
  ```

- [ ] **Step 3: Run focused validation**

  Run:

  ```bash
  python3 scripts/check-github-workflow-hygiene.py
  python3 -m py_compile scripts/check-github-workflow-hygiene.py
  python3 - <<'PY'
  from pathlib import Path
  try:
      import yaml
  except Exception:
      raise SystemExit('PyYAML is not available; YAML parse skipped')
  for path in ['.github/workflows/test.yml', '.github/workflows/windows.yml']:
      yaml.safe_load(Path(path).read_text())
      print(f'parsed {path}')
  PY
  rtk rg "build-windows:|test-windows:" .github/workflows/test.yml || true
  rtk rg "pull_request:|merge_group:|schedule:|cron:" .github/workflows/windows.yml || true
  rtk rg "PR and Windows validation routing|windows workflow" docs/dev/notes/github-actions-hygiene.md
  if command -v actionlint >/dev/null 2>&1; then actionlint .github/workflows/*.yml; else echo 'actionlint not available'; fi
  ```

  Expected: hygiene checker and py_compile pass; YAML parse passes when PyYAML is available or reports it is unavailable; the first two `rg` commands print no prohibited entries; docs search finds the new section; actionlint passes when available or reports it is unavailable.

---

## Final Validation

After all tasks pass review, run:

```bash
python3 scripts/check-github-workflow-hygiene.py
python3 -m py_compile scripts/check-github-workflow-hygiene.py
python3 - <<'PY'
from pathlib import Path
try:
    import yaml
except Exception:
    raise SystemExit('PyYAML is not available; YAML parse skipped')
for path in sorted(Path('.github/workflows').glob('*.yml')):
    yaml.safe_load(path.read_text())
    print(f'parsed {path}')
for path in sorted(Path('.github/actions').glob('*/action.yml')):
    yaml.safe_load(path.read_text())
    print(f'parsed {path}')
PY
rtk rg "build-windows:|test-windows:" .github/workflows/test.yml || true
rtk rg "pull_request:|merge_group:|schedule:|cron:" .github/workflows/windows.yml || true
rtk rg "PR and Windows validation routing|windows workflow" docs/dev/notes/github-actions-hygiene.md
rtk git diff --check origin/main...HEAD
if command -v actionlint >/dev/null 2>&1; then actionlint .github/workflows/*.yml; else echo 'actionlint not available'; fi
```

Expected results:

- hygiene checker passes;
- Python compile passes;
- YAML parse passes when PyYAML is available or reports it is unavailable;
- `test.yml` contains no Windows jobs;
- `windows.yml` contains no PR, merge-group, or schedule triggers;
- docs mention the routing policy;
- diff whitespace check passes;
- actionlint passes when available or reports it is unavailable.

## Acceptance Criteria

- `.github/workflows/test.yml` is Linux-only and keeps `push` to `main`, `pull_request` to `main`, and `merge_group` triggers.
- `.github/workflows/windows.yml` contains the existing Windows cross-build/package/Wine/native fast-suite jobs.
- `.github/workflows/windows.yml` runs only on `push` to `main` and `workflow_dispatch`.
- No scheduled Windows workflow is added.
- `scripts/check-github-workflow-hygiene.py` guards the Windows routing policy.
- Documentation explains the Linux PR gate and post-merge/manual Windows validation.
