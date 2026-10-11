---
type: subsystem
tags:
  - subsystem
  - build
created: 2026-07-14
---

# Build and compilation system

CMake-based C++ build with cross-platform packaging (DEB/RPM/AppImage/tarball), GCC JIT runtime compilation bindings, C intermediate representation for code generation, and native build integration.

## Key files

- `cmake/` — CMake build system with platform dispatchers
- `src/lua_gccjit.h` — libgccjit bindings for runtime C compilation
- `assets/lua/c-builder.fnl`, `assets/lua/c-ir.fnl` — Fennel C compilation layer
- `assets/lua/native-build.fnl` — native build integration

## Dependencies

- Depends on: [Core Platform](/dev/features/core-platform)
- Optional native dependency: `libssh` via pkg-config enables the SSH backend when `SPACE_ENABLE_SSH=ON` (the default). There is no project-enforced minimum version floor; if CMake cannot find `libssh`, Space still builds and SSH operations report structured `unavailable-backend` errors.

## Dev notes

- [C Builder](/dev/notes/c-builder) — C compilation via GCC JIT
- [C Ir](/dev/notes/c-ir) — C intermediate representation
- [Gccjit](/dev/notes/gccjit) — libgccjit binding details
- [GitHub Actions Hygiene](/dev/notes/github-actions-hygiene) — CI workflow permissions, release publishing, and workflow hygiene checks
- [Native Build](/dev/notes/native-build) — native C build integration

## See also

- [Core Platform](/dev/features/core-platform)
- [Development Tooling](/dev/features/development-tooling)
- [Subsystems](/dev/subsystems/)
