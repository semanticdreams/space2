---
name: space-testing-runtime
description: Use when running, adding, or debugging Space tests, E2E snapshots, remote-control debugging, profiling, build commands, or runtime harnesses.
---

# Space Testing Runtime

## Use When

Running, adding, or debugging Space tests, E2E snapshots, remote-control debugging, profiling, build commands, or runtime harnesses.

## Canonical Commands

`AGENTS.md` is the canonical source for build/test command spellings and timeout expectations.

## Runtime Test Environment

- Default full suite: `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test`.
- Use absolute `SPACE_ASSETS_PATH=$(pwd)/assets` for direct Lua/Fennel test runs.

## Constraints

- For Fennel-facing work, run `make fennel-check` before `make constraints`; use `./build/space -m tools.fennel-check:main -- --target files --file <path>` for narrow touched-file compile checks.
- `make constraints` is the structural pre-test gate after the compile check; run it before narrowed Fennel test commands when feasible.
- `make test` already depends on constraints, so do not duplicate the gate immediately before a full-suite run unless early feedback is useful.
- Use `docs/dev/constraints.md` for runner statuses, targets, and baseline policy.
- For delimiter errors, inspect the nearest enclosing form and rerun the compile check before constraints/tests.

## E2E Snapshots

- E2E snapshots use `make test-e2e`.
- Goldens live under `assets/lua/tests/data/snapshots/`.
- PNGs must be visually inspected after snapshot changes.

## Remote Control And Profiling

- Remote-control debugging uses the running app endpoint and `tools.remote-control-client`.
- Profilers run through `make prof target=<name>`.

## Windows CI Local Reproduction

For non-infrastructure Windows CI failures, agents must dispatch `windows-ci-reproducer`;
do not run ad-hoc setup commands or invoke the wrapper
directly. The capability's underlying/manual wrapper command sequence is:

```bash
python3 scripts/opencode_windows_ci_repro.py preflight --repo-root .
python3 scripts/opencode_windows_ci_repro.py setup-host --repo-root .
python3 scripts/opencode_windows_ci_repro.py reproduce --repo-root .
```

See `docs/dev/notes/windows-wine-build-and-test.md` for the Windows-from-Linux
build and Wine validation flow. Wine evidence helps reproduce CI failures, but
Wine is not native Windows CI; native Windows CI remains authoritative for
Windows-host-only behavior and final integration.

## Canonical References

- `AGENTS.md`
- `docs/dev/constraints.md`
- `docs/dev/features/development-tooling.md`
