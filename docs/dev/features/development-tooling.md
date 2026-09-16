---
type: feature
status: shipped
parent-goal: core-platform
tags:
  - feature
  - tooling
  - profiling
  - testing
  - debug
created: 2026-07-14
updated: 2026-07-14
---

# Development tooling

## Summary

Developer infrastructure for profiling, testing, debugging, and observing the runtime. Includes stack-sampling flamegraph profilers, frame-level performance measurement, a 170+ unit Fennel test harness with 55 E2E snapshot tests, render capture for frame debugging, and CLI tools for remote control and torrent operations.

## Motivation

A 3D spatial computing platform with C++ and Fennel components needs specialized tooling beyond generic debuggers. Performance issues in layout, rendering, and physics require in-engine profiling. Regression prevention requires deterministic snapshot testing. Live debugging requires remote code evaluation.

## Design

- **Flamegraph profilers** (`flamegraph-profiler.fnl`): Stack-sampling profiler producing folded output for flamegraph SVG generation. Specific profiler scripts target hot paths: graph layout (`prof-graph-layout`), scroll performance (`prof-scroll`), terminal rendering (`prof-terminal`), scene rendering (`prof-scene`), update loop (`prof-update`). See [Prof Graph Layout](/dev/notes/prof-graph-layout), [Prof Scroll](/dev/notes/prof-scroll), [Prof Terminal](/dev/notes/prof-terminal).
- **Frame profiler** (`frame-profiler.fnl`): Per-frame timing breakdown.
- **Runtime performance** (`runtime-performance.fnl`): Runtime metrics collection.
- **Test harness** (`tests/runner.fnl`): Module-based test discovery, timeout management, assertions, and reporting. 170+ unit tests in `tests/fast.fnl`, 3 slow tests, 55 E2E snapshot tests with golden PNG comparison. See [Test Harness Cleanup](/dev/notes/test-harness-cleanup).
- **Packaged child-process test runtime** (`tests/runtime-bin.fnl`): Fast-suite tests that spawn child Space processes resolve the runtime through `SPACE_BIN` first. Windows CI sets `SPACE_BIN` to `build/dist/windows/space-cli.exe` so packaged tests run child modules through the CLI executable shipped in the runtime bundle.
- **HTTP client testing** (`dev-notes/testing-http-clients`): Infrastructure for testing HTTP-dependent code paths.
- **Render capture** (`render-capture.fnl`): `glReadPixels` + PNG output for frame-level debugging. Separate from the E2E snapshot system. See [Render Capture](/dev/notes/render-capture).
- **Remote control** (`remote-control.fnl`): ZeroMQ-based live Fennel evaluation for debugging running apps.
- **CLI tools** (`tools/`): Remote control client, MCP remote server, torrent download/upload scripts.
- OpenCode project guidance uses `AGENTS.md` for always-on repository facts and `.opencode/skills/space-*` for triggerable Space domain guidance; users must restart OpenCode after `.opencode/**` changes.
- After implementation/review/commit, failed required validation is handled as a debugging task: supervisors invoke `systematic-debugging`, route fixes through `implementer` → `reviewer`, rerun validation, and finish or PR only when green.

- **DEB/RPM packaging**: Per-distro DEB (ubuntu-22.04/24.04, debian-12/13) and RPM (fedora, opensuse-tumbleweed) packages via CMake/CPack. CEF runtime bundling in full-profile packages; minimal-profile packages exclude it. Distro smoke tests via xvfb + headless engine. AppImage and tarball distribution formats. See [Building space](/dev/building).

## Tasks

- [x] Stack-sampling flamegraph profiler
- [x] Per-goal profiler scripts (graph, scroll, terminal, scene, update)
- [x] Frame profiler with timing breakdown
- [x] Fennel test harness with module discovery and timeout management
- [x] 170+ unit tests
- [x] 55 E2E snapshot tests with golden comparison
- [x] Render capture (glReadPixels → PNG)
- [x] Remote control debug endpoint
- [x] CLI tools for remote control and torrent ops

## Related

- Goal: [Core Platform](/dev/features/core-platform)
- See: [Subsystems](/dev/subsystems/) — Tooling section
