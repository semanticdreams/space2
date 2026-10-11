# Windows Main CI Design

Date: 2026-10-09

## Context

The current `test` workflow runs both Linux validation and Windows validation on
pull requests, pushes to `main`, and merge queue groups. The Windows path is much
slower than Linux because it performs a Linux-hosted Windows cross-build,
runtime packaging, Wine smoke testing, artifact transfer, and a native Windows
fast-suite job. Since day-to-day development happens on Linux, this makes every
PR and merge-queue run wait for a platform that is not the primary development
environment.

We still publish Windows artifacts, so Windows validation should not become
release-only. If Windows breaks only at release time, several changes may have
accumulated and the original context for the regression may be lost.

## Design Goals

1. Keep PR and merge-queue feedback fast by making `test.yml` Linux-only.
2. Keep Windows regressions close to the responsible change by running Windows
   validation on every push to `main`.
3. Keep a manual Windows validation entry point for maintainers.
4. Avoid scheduled Windows runs for now.
5. Preserve the existing Windows validation behavior when the Windows workflow
   runs: cross-build, package, Wine smoke, artifact upload/download, and native
   Windows fast suite.
6. Keep release packaging in `build.yml` unchanged.

## Chosen Direction

Split Windows validation out of `.github/workflows/test.yml` into a dedicated
workflow. The required PR/merge-queue `test` workflow should contain only the
Linux job. The new Windows workflow should run on `push` to `main` and
`workflow_dispatch`, with the same two-job structure that exists today:

- `build-windows` on Ubuntu performs the cross-build, runtime package assembly,
  Wine smoke check, cache stats, and uploads the `space-windows-runtime`
  artifact.
- `test-windows` on `windows-latest` downloads the runtime artifact, smoke tests
  the CLI binary, and runs `tests.fast:main` with the packaged assets.

There should be no `pull_request`, `merge_group`, or `schedule` trigger in the
new Windows workflow.

## Error Handling

The Windows workflow should continue to fail loudly when setup, cross-build,
packaging, Wine smoke, artifact transfer, native smoke, or the fast suite fails.
No failures should be converted into warnings or soft skips.

The Linux `test` workflow remains the merge-queue integration gate. The Windows
workflow is post-merge signal: if it fails on `main`, the next fix should be a
normal reviewed PR with the failed `main` run as context.

## Validation

Local validation is workflow/static-policy focused:

- parse changed workflow YAML files;
- run `scripts/check-github-workflow-hygiene.py`;
- run `actionlint` when available;
- run static searches confirming Windows jobs no longer live in `test.yml` and
  the new Windows workflow has only `push` to `main` and `workflow_dispatch`.

Runtime `make build` or `make test` is not required because this changes GitHub
workflow routing only, not source code, assets, tests, or packaging scripts.

## Out of Scope

- Changing Windows build commands, dependency sets, package contents, or test
  commands.
- Adding scheduled Windows validation.
- Changing release `build.yml`.
- Changing branch protection settings in repository configuration; that must be
  handled outside the workflow diff if GitHub still requires removed Windows job
  names.
