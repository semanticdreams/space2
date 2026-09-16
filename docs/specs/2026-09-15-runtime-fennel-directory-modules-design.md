# Runtime Fennel Directory Modules Design

## Problem

Normal Space app launch currently configures the embedded Fennel search path with only `assets/lua/?.fnl`. That supports flat modules such as `main.fnl`, but it does not support directory modules such as `assets/lua/graph/extensions/builtins/init.fnl`.

The built-in graph extension migration now requires `:graph/extensions/builtins` from `main.fnl`. Tests pass because the test environment sets `FENNEL_PATH` and `FENNEL_MACRO_PATH` to include both `assets/lua/?.fnl` and `assets/lua/?/init.fnl`, but normal app launch should not depend on those shell variables.

## Goals

- Make normal embedded app launch self-sufficient for Fennel directory modules.
- Keep Space's canonical Fennel asset path order as `assets/lua/?.fnl;assets/lua/?/init.fnl`.
- Preserve flat-file precedence over directory `init.fnl` modules.
- Apply the same canonical runtime path to macro resolution so modules with `(import-macros ...)` do not need launch-wrapper environment variables.
- Add a regression test that proves directory modules load without external `FENNEL_PATH` or `FENNEL_MACRO_PATH`.

## Non-goals

- Do not rename or flatten `graph/extensions/builtins/init.fnl`.
- Do not change graph extension semantics, descriptor precedence, or duplicate handling.
- Do not make `make run` or user shell wrappers responsible for required embedded runtime paths.
- Do not broaden Lua `package.path` behavior beyond the existing `.lua` asset path.

## Options Considered

### Option A: Add `FENNEL_PATH`/`FENNEL_MACRO_PATH` to `make run`

This would fix developer launches through `make run`, but it would leave direct binary startup, packaging, and other launch surfaces dependent on wrapper correctness. It treats the symptom instead of the runtime contract.

### Option B: Flatten `graph/extensions/builtins/init.fnl`

This would avoid the immediate missing module, but it fights the established Fennel directory-module convention already used by tests and user-code module paths. Future directory modules could hit the same launch failure.

### Option C: Make `LuaRuntime` own the canonical Fennel asset search path

The runtime already computes and exposes `runtime.fennel-path`. Expanding that value to include both flat and directory module patterns makes every embedded launch path consistent. Applying it to both `fennel.path` and `fennel.macro-path` before app modules load makes macro imports self-sufficient too.

## Decision

Use Option C.

`LuaRuntime` should construct the canonical Space Fennel asset path from the asset Lua root:

```text
<assets>/lua/?.fnl;<assets>/lua/?/init.fnl
```

It should expose that path through the existing runtime preload and install it into both runtime Fennel search fields during `install_fennel`. `main.fnl` should no longer need to repair macro-path after requiring `runtime` unless an implementation constraint proves the startup order requires it.

## Architecture

- `src/lua_runtime.cpp` remains the owner of embedded Lua/Fennel startup configuration.
- `configure_package_paths()` keeps Lua `.lua` package behavior unchanged and builds the canonical Fennel asset path for Fennel-only resolution.
- `install_fennel()` prepends the canonical path to both `fennel.path` and `fennel["macro-path"]` before `fennel.install(...)`.
- `runtime.fennel-path` continues to expose the canonical path for child processes, external user-code tooling, and tests.
- Regression coverage runs through the actual executable with external Fennel path variables absent, proving runtime self-sufficiency.

## Testing

Add focused runtime coverage that starts `./build/space` without `FENNEL_PATH` and without `FENNEL_MACRO_PATH`, then verifies:

- `(require :graph/extensions/builtins)` resolves the directory module.
- A module that imports macros, such as `:flex`, resolves successfully using the runtime macro path.

Because this changes runtime initialization and Fennel module loading, validation should include build freshness, Fennel compile checks, constraints, the focused runtime test, focused CTest registration, and the full relevant local test suite before integration.

## Acceptance Criteria

- Normal app startup no longer fails on `module 'graph/extensions/builtins' not found`.
- Embedded runtime does not require external `FENNEL_PATH` or `FENNEL_MACRO_PATH` for project modules under `assets/lua`.
- Existing test and user-code path conventions remain compatible.
- Graph extension behavior is unchanged except that directory-module loading works in normal launch.
