# OpenCode CI Diagnostics Tooling Design

## Context

PR #191 exposed two tooling blockers while diagnosing a failed Windows merge-queue
check:

1. The guarded GitHub PR wrapper can fetch failed GitHub Actions logs, but
   `poll_merge_queue` returns only a tail excerpt. Space's Fennel test runner
   prints `[FAIL] <test name>` at the point of failure, often earlier than the
   final tail, so the supervisor can see only `6 Lua test(s) failed` and cannot
   identify root cause.
2. The guarded Windows CI reproduction wrapper reports local reproduction as
   unavailable when `vcpkg/vcpkg` is missing. The existing remediation,
   `setup-host`, calls `scripts/setup-windows-build-host.sh`, which uses
   `sudo apt-get` before cloning/bootstraping vcpkg. That is appropriate for
   provisioning a new host, but it is too broad when only repo-local vcpkg is
   missing and all system prerequisites already exist.

Both problems are capability-boundary issues, not temporal-feature issues. The
fix should make the guarded tooling powerful enough to diagnose CI and reproduce
Windows failures while preserving the safety model: no raw `gh *`, no broad shell
permissions, no sudo/package-manager escalation, and no writes outside the trusted
repo unless a human makes that decision outside the agent workflow.

## Goals

- Add guarded CI log retrieval that supports bounded default output, full logs,
  arbitrary line slices, and literal search with context.
- Ensure `poll_merge_queue` automatically includes useful `[FAIL]` marker context
  for failed checks when the full log is fetchable.
- Add a safe full-log bundle command for the GitHub operator agent so future
  debugging can save complete failed-check logs under a repo-local ignored
  artifact directory.
- Distinguish missing repo-local vcpkg from missing system Windows-build
  prerequisites in Windows repro preflight evidence.
- Add a non-sudo `bootstrap-vcpkg` wrapper command that clones/bootstrapes only
  repo-local vcpkg when host tools are already installed.
- Update OpenCode agent permissions, permission checks, and workflow docs for the
  new exact guarded commands.

## Non-goals

- Do not grant raw `gh`, `sudo`, `apt-get`, package-manager, or broad shell
  permissions to any agent.
- Do not change GitHub Actions workflow definitions in this slice.
- Do not implement Windows system package provisioning without `setup-host`.
- Do not allow `bootstrap-vcpkg` to write to an arbitrary external `VCPKG_ROOT`.
- Do not add regex search to restricted agent commands; literal search is enough
  and safer for logs.
- Do not solve the current PR #191 Windows failure by guessing. The tooling fix
  should produce the evidence needed for the next diagnostic step.

## Considered approaches

### Approach A: Enlarge `poll_merge_queue` tail excerpts

Increasing the tail limit is simple, but it still misses failures when logs are
large and failure lines are far from the end. It also bloats every queue failure
response.

Rejected as insufficient.

### Approach B: Allow agents to run raw `gh run view --log`

Raw GitHub CLI access would solve log retrieval quickly, but it violates the
capability-boundary model and makes it easy to broaden into unsafe GitHub
operations.

Rejected.

### Approach C: Add precise wrapper log commands and marker extraction

Selected. The PR wrapper already safely parses run/job IDs and fetches logs. It
should gain reusable log slicing/search helpers, automatic `[FAIL]` marker
evidence in failed-check summaries, and explicit CLI commands for bounded/full
diagnostic retrieval.

### Approach D: Use `setup-host` for all Windows repro gaps

This keeps one command, but it forces a sudo/package-manager path for a local
repo artifact gap. In the current environment, that creates a blocker even when
system tools are present.

Rejected.

### Approach E: Add repo-local vcpkg bootstrap

Selected. `bootstrap-vcpkg` should clone the pinned vcpkg branch and run
`bootstrap-vcpkg.sh` inside the repository without sudo. Preflight should point
to this command only when the missing category is the default repo-local vcpkg.

## Design

### PR operator log diagnostics

`scripts/opencode_pr_operator.py` will keep `poll_merge_queue` bounded by
default but improve failed-check evidence:

- Continue returning `log_excerpt` as a bounded tail.
- Add `failure_markers` when full log fetch succeeds. Markers contain 1-indexed
  line numbers, the matched `[FAIL]` line, and small surrounding context. Marker
  count and context are bounded.
- Leave `log_excerpt` limits in place to keep routine poll responses manageable.

The wrapper will add explicit log commands:

- `actions-log --repo-root . --run-id <id> --job-id <id>`: bounded tail by
  default.
- `actions-log --repo-root . --run-id <id> --job-id <id> --start-line N --line-count M`:
  1-indexed line slice.
- `actions-log --repo-root . --run-id <id> --job-id <id> --contains TEXT --context-lines N --max-matches M`:
  literal substring search with context.
- `actions-log --repo-root . --run-id <id> --job-id <id> --full`: full log in JSON
  output for direct supervised use when explicitly invoked.
- `failed-actions-log-bundle-current --repo-root .`: discovers failed checks for
  the current branch PR, writes full logs under `build/opencode/actions-logs/`,
  and returns repo-relative log paths plus marker metadata.

The restricted `github-operator` agent should receive only the exact bundle
command permission, not wildcard arbitrary `actions-log` permissions. The
supervisor can then ask the capability agent for a safe failed-log bundle without
granting raw `gh` access.

### Windows repro non-sudo vcpkg bootstrap

`scripts/opencode_windows_ci_repro.py preflight` will preserve the existing
`missing` list and add `missing_by_category`:

- `system_tools`
- `scripts`
- `vcpkg`
- `wine`
- `rust_targets`

When the only missing category is default repo-local vcpkg, preflight returns a
specific `missing_local_vcpkg` code and a `bootstrap_vcpkg_command` instead of
making `setup-host` the primary remediation.

`bootstrap-vcpkg --repo-root .` will:

- require a trusted Space repo;
- refuse to write to external `VCPKG_ROOT` locations;
- clone `https://github.com/microsoft/vcpkg` at branch `2025.03.19` into
  `<repo>/vcpkg` when missing;
- run `<repo>/vcpkg/bootstrap-vcpkg.sh` when the binary is missing;
- return success immediately when `<repo>/vcpkg/vcpkg` already exists;
- return structured command evidence for clone/bootstrap failures.

It must not call `sudo`, `apt-get`, or `scripts/setup-windows-build-host.sh`.

### OpenCode permissions and docs

Project OpenCode agent files and permission checker tests must be updated so the
new commands are intentionally allowed:

- `github-operator`: exact permission for
  `python3 scripts/opencode_pr_operator.py failed-actions-log-bundle-current --repo-root .`.
- `windows-ci-reproducer`: exact permission for
  `python3 scripts/opencode_windows_ci_repro.py bootstrap-vcpkg --repo-root .`.

Docs should explain that OpenCode must be restarted after `.opencode/**` changes.
Workflow docs should instruct agents to use the log bundle when poll evidence is
insufficient and to run `bootstrap-vcpkg` before `setup-host` for
`missing_local_vcpkg`.

## Testing strategy

- Add pytest coverage for PR operator marker extraction, tail/slice/search/full
  modes, invalid bounds, and full failed-log bundle file output.
- Add pytest coverage for categorized Windows preflight, local-vcpkg-only
  remediation, bootstrap clone/bootstrap/no-op paths, and external `VCPKG_ROOT`
  refusal.
- Add permission checker tests for exact new commands and continued rejection of
  broad unsafe log commands.
- Run focused script tests and the full `scripts/tests` suite.

## Acceptance criteria

- Failed merge-queue evidence includes `[FAIL]` marker context when fetched logs
  contain test-runner failure lines outside the tail excerpt.
- A guarded command can retrieve full logs, arbitrary line slices, and literal
  search results for a run/job.
- Restricted GitHub operator permissions expose only the exact failed-log bundle
  command, not raw or wildcard `gh`/`actions-log` access.
- Windows repro preflight identifies local-vcpkg-only gaps separately from system
  prerequisite gaps.
- `bootstrap-vcpkg` can create repo-local vcpkg without sudo and refuses external
  writes.
- Permission and workflow docs reflect the new safe paths.
