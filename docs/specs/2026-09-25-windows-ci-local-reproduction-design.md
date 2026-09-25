# Windows CI Local Reproduction Design

Date: 2026-09-25

## Context

Space's PR CI includes Linux validation plus Windows cross-build, native Windows fast-suite, and Windows installer jobs. When a Windows-specific job fails, the current agent workflow tends to patch, push, and wait for another full CI cycle. That is slow because each attempt must rebuild the Windows runtime and pass through merge/PR checks.

The repository already has a local reproduction path:

- `scripts/build-windows-from-linux.sh`
- `scripts/package-windows-runtime.sh`
- `scripts/test-windows-under-wine.sh`
- `docs/dev/notes/windows-wine-build-and-test.md`

The missing piece is agent workflow policy and a safe way to prepare hosts that do not yet have the Windows cross-build/Wine prerequisites.

## Decision

Add a guarded Windows CI reproduction capability instead of granting agents broad `sudo`, package-manager, GitHub, or shell access.

The capability will expose a small wrapper with three operations:

1. `preflight` — check whether the Linux host can run the Windows cross-build/Wine reproduction path.
2. `setup-host` — run the existing Windows build host setup script through a guarded wrapper when prerequisites are missing.
3. `reproduce` — run the local cross-build, package, and Wine test sequence and return structured evidence.

Agents must use this capability when Windows CI jobs fail and the failure is not obviously CI infrastructure-only.

## Alternatives Considered

### Documentation-only policy

This would update skills/docs to tell agents to run the existing scripts manually. It is simple, but easy to bypass under time pressure and conflicts with current restrictions on `sudo`/package-manager setup.

### Unrestricted Git/GitHub/shell subagent

This would maximize flexibility but weakens the capability-boundary model that protects the repository from accidental force-pushes, raw branch-protection changes, broad package-manager operations, and unsafe cleanup. It also solves more than the Windows CI problem and would be harder to audit.

### Guarded capability wrapper and subagent

This is the selected design. It keeps operations bounded, testable, and auditable while giving agents the local reproduction loop they need.

## Trigger Policy

When PR CI or merge-queue CI reports a failure in any of these jobs:

- `build-windows`
- `test-windows`
- `build-windows-installer`

the supervising workflow must inspect the failing logs. If the failure is clearly CI infrastructure-only, such as a GitHub runner outage, artifact service outage, cache service failure, or download/network outage unrelated to repository behavior, agents may treat it as CI infrastructure evidence.

Otherwise, before pushing another attempted fix, agents must run local Windows reproduction through the guarded capability.

## Capability Behavior

The wrapper returns structured JSON with `status`, `action`, `message`, and `evidence`.

### `preflight`

Checks required tools and files, including MinGW POSIX compilers, CMake, vcpkg, Rust Windows target, PowerShell, and Wine. Missing prerequisites return actionable evidence and the setup command to run.

### `setup-host`

Runs the existing setup script through a guard. It should only run on supported Linux hosts and should fail closed with `HUMAN_DECISION_REQUIRED` evidence if setup cannot run safely.

### `reproduce`

Runs the local reproduction sequence:

1. `scripts/build-windows-from-linux.sh`
2. `scripts/package-windows-runtime.sh`
3. verify Windows runtime/package inputs exist
4. `scripts/test-windows-under-wine.sh`

On failure, it reports the failing step plus bounded stdout/stderr evidence.

## Agent Workflow

- `supervisor` routes Windows CI failures to a `windows-ci-reproducer` capability agent.
- `github-workflow-debug` and `finishing-a-development-branch` require local Windows reproduction before another push/requeue for non-infrastructure Windows failures.
- `space-testing-runtime` documents the wrapper commands as the canonical local Windows CI reproduction path.
- The capability agent can run only the exact wrapper commands; it cannot run raw `sudo`, `apt`, `wine`, `gh`, or arbitrary shell.

## Testing Expectations

- Unit tests cover wrapper preflight, setup-host guards, reproduce step ordering, failure evidence, and exit/status mapping.
- Static policy tests ensure the capability agent exists, references the wrapper, and has only the exact allowed commands.
- Documentation/instruction tests ensure the Windows CI reproduction policy is present in supervisor/skills/docs.
- `make opencode-check` includes the new wrapper and policy tests.

## Limits

Wine reproduction is a fast local filter, not a replacement for native Windows CI. Native Windows CI remains authoritative for Windows-host-only behavior, installer behavior, and final integration.

## Non-Goals

- Do not rewrite the GitHub Actions Windows workflow.
- Do not replace guarded Git/GitHub capability agents with unrestricted agents.
- Do not make Wine a substitute for native Windows CI.
- Do not add broad `sudo`, package-manager, or raw shell permissions to existing agents.
