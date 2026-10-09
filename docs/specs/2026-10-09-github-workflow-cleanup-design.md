# GitHub Workflow Cleanup Design

Date: 2026-10-09

## Context

The root GitHub workflows already cover the important integration surfaces: the
test workflow participates in merge queue via `merge_group`, release builds smoke
test Linux and Windows artifacts, and the Pages workflow uses narrow deploy
permissions. A clean-design audit found several maintainability and reliability
gaps that should be fixed together because they share the same workflow-policy
boundary:

- release upload permissions are implicit in `build.yml`;
- release publication is spread across multiple builder jobs;
- `devlog-publish.yml` updates state without a concurrency guard;
- `test.yml` configures broad Git trust globally;
- cache, `sccache`, and Windows cross-build setup are duplicated;
- release-time tools include floating package installs;
- first-party action major versions are inconsistent.

This work is workflow/static-policy work. It does not change product behavior,
runtime assets, Fennel code, C++ code, or test semantics.

## Design Goals

1. Make least privilege explicit: default workflows to read-only permissions and
   grant write scopes only to jobs that publish releases or deploy Pages.
2. Centralize release publication so all package builders produce workflow
   artifacts and one publish job owns writes to the GitHub Release.
3. Serialize stateful scheduled automation to prevent duplicate devlog publishes
   and stale state overwrites.
4. Replace broad CI Git trust with job-local, scoped configuration.
5. Reduce duplication using local repository-owned abstractions, not new
   marketplace dependencies.
6. Pin release-time dependency installs where practical.
7. Add static guardrails so the same hygiene regressions are easy to catch.

## Approaches Considered

### Option A: Minimal hardening only

Patch explicit permissions, devlog concurrency, Git trust, and pinned packages
directly in the existing workflows. This is low risk and fast, but leaves the
release publication race and the duplicated cache/setup blocks in place.

### Option B: Bounded native refactor

Centralize release publishing and extract repeated cache/setup sequences into
local composite actions under `.github/actions`. Add a small stdlib-only static
hygiene checker. This addresses all audited issues while keeping the current
workflow shape, triggers, artifact names, and packaging scripts.

### Option C: Reusable-workflow redesign

Move most build/test/release logic into reusable workflows. This maximizes DRY,
but it is too broad for the current goal and would add unnecessary migration risk
around release and merge-queue behavior.

## Chosen Direction

Use Option B. The implementation should be a bounded native refactor: keep the
existing workflows recognizable, preserve triggers and release artifact names,
and introduce only repository-owned helper boundaries where they reduce drift.

## Architecture

### Local composite actions

Create local composite actions for repeated compiler-cache setup:

- `setup-linux-compiler-cache` restores `ccache`, restores `sccache`, restores a
  pinned `sccache` binary cache, and installs the pinned `sccache` version only
  when missing.
- `setup-windows-cross-cache` does the same for Windows cross-build cache paths
  and optionally exports the GitHub Actions cache runtime variables needed by
  `vcpkg` binary caching.

The workflows remain responsible for build/test/package commands. The composite
actions own only repeatable setup mechanics.

### Centralized release publication

Builder jobs in `build.yml` and `bundle.yml` should verify package outputs and
upload them as workflow artifacts. A final `publish-release` job, gated to tag
refs, downloads those artifacts and performs the release write. Only that job
needs `contents: write`.

This keeps release creation/update serialized per workflow run and avoids
multiple jobs racing to mutate the same GitHub Release.

### Stateful automation concurrency

`devlog-publish.yml` should use a top-level concurrency group with
`cancel-in-progress: false`. The goal is to queue overlapping manual/scheduled
runs rather than cancel a run after it has restored or written state.

### Scoped Git configuration

`test.yml` should avoid `safe.directory '*'` and broad global mutation. The CI
job can write a temporary Git config file under `${RUNNER_TEMP}`, export it via
`GIT_CONFIG_GLOBAL`, and add only the workspace and known test directories.
Protocol exceptions should stay inside that job-local config.

### Dependency pinning and action consistency

Release-time installs should pin exact versions for tools that are currently
floating and directly affect package outputs, including Inno Setup and Pillow.
Existing first-party action major versions should be normalized where the same
action is already used elsewhere in the repo. Pages-specific actions can remain
on their current supported majors unless validation indicates an available safe
update.

### Static guardrails

Add a stdlib-only workflow hygiene checker under `scripts/` to verify the most
important invariants:

- no wildcard `safe.directory`;
- no broad global `protocol.file.allow always`;
- devlog publish has concurrency;
- known first-party action majors are not downgraded;
- Inno Setup and Pillow installs are pinned;
- release publishing is centralized to `publish-release` jobs in release
  workflows.

## Error Handling

Workflow steps should keep failing loudly. If package manifests are missing,
release artifacts are absent, package installs fail, or release uploads fail, the
workflow should exit nonzero. No new silent skip behavior should be added beyond
existing intentional gates such as tag-only release publication.

If an exact pinned package version is unavailable during validation, the change
should not silently broaden to a floating install; it should stop for a human
decision about the acceptable version.

## Validation

Local validation should stay focused on workflow/static-policy changes:

- parse changed workflow and local action YAML files;
- run the new workflow hygiene checker;
- run `actionlint` if available;
- use text checks to confirm removed broad Git trust and pinned package installs.

No `make build`, `make test`, Fennel checks, or runtime tests are required for
this workflow-only cleanup unless implementation changes unexpectedly touch
runtime code, tests, assets, or build scripts whose behavior requires broader
validation. PR CI remains the authoritative integration gate for GitHub-hosted
workflow permissions, artifacts, reusable workflow behavior, and merge queue.

## Out of Scope

- Pinning every GitHub Action by SHA.
- Changing package contents, release asset names, build matrices, or release
  triggers.
- Rewriting workflows into a reusable-workflow architecture.
- Changing C++, Fennel, runtime assets, or test semantics.
