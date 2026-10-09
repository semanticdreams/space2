---
type: note
tags:
  - ci
  - github-actions
  - build
---

# GitHub Actions Hygiene

Space workflows use least-privilege permissions, centralized release publishing,
scoped CI Git configuration, and pinned release-time tools. These rules keep CI
behavior understandable and make release failures easier to diagnose.

## Permissions

Workflows default to `contents: read`. Jobs request broader scopes only when a
step needs them. Release publisher jobs request `contents: write`; Windows
cross-build jobs that use GitHub Actions cache-backed `vcpkg` binary caching
request `actions: write`.

## Release publishing

Builder jobs verify package outputs and upload workflow artifacts. A final
`publish-release` job downloads those artifacts and writes to the GitHub
Release. This avoids multiple builders racing to create or update the same
release.

## Stateful scheduled automation

Devlog publication is serialized with a dedicated concurrency group and
`cancel-in-progress: false` so state restoration, notification delivery, and
state upload cannot overlap.

## CI Git configuration

CI must not use wildcard `safe.directory` or broad global Git mutation. Tests
that need Git trust exceptions write a job-local config under `${RUNNER_TEMP}`
and point `GIT_CONFIG_GLOBAL` at that file.

## Pinned release-time tools

Workflows pin release-critical package installs such as Inno Setup, Pillow, and
`sccache`. If a pin becomes unavailable, choose a new exact version in review
instead of silently returning to a floating install.

## Local validation

Run `python3 scripts/check-github-workflow-hygiene.py` after workflow edits.
Run `actionlint .github/workflows/*.yml` when `actionlint` is available. PR CI
remains the authoritative integration gate for GitHub-hosted behavior.
