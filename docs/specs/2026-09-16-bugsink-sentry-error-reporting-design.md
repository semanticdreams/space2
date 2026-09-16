# Bugsink/Sentry Error Reporting Design

Date: 2026-09-16

## Goal

Add Bugsink-compatible error reporting through the Sentry Native SDK. Space will vendor the native SDK as a required dependency, expose a small native-backed module to Fennel, and let each Fennel entrypoint decide whether to initialize reporting and which DSN to use. After an entrypoint initializes reporting, both C++ side and Fennel/Lua side failures must be reported through the same SDK instance.

The canonical `main.fnl` entrypoint will initialize reporting with the Bugsink DSN provided for the main app:

```text
https://1f1673528e9b4e8cae1d0a722e435170@bugsink.narlun.com/1
```

Tests must never send events to the production Bugsink server. Test coverage will use disabled capture paths and/or local HTTP DSNs served by test fixtures.

## Context

Space starts in `apps/space/main.cpp`, constructs `LuaRuntime`, installs Fennel, and then runs a command, file, module, or module function. Top-level Lua/Fennel failures already pass through `sol::error` catch blocks there. `LuaRuntime::install_base_bindings` is the central place for exposing C++ services through `package.preload`, and `assets/lua/main.fnl` is the canonical application entrypoint with early logging setup.

The project already vendors native dependencies under `external/`, configures them from the root `CMakeLists.txt`, and links them into `space_lib`. This integration should follow that pattern rather than introducing a system package requirement.

## Design Direction

Use a required vendored `sentry-native` dependency and wrap it in a small native `error_reporting` service. Fennel will not talk to the Sentry SDK directly; instead it will require a strict `error-reporting` module backed by C++.

Initialization is explicit and entrypoint-owned:

```fennel
(local error-reporting (require :error-reporting))
(error-reporting.init {:dsn "https://1f1673528e9b4e8cae1d0a722e435170@bugsink.narlun.com/1"})
```

Requiring the module alone does not initialize reporting. C++ must not implicitly initialize from environment variables before the Fennel entrypoint runs, because different entrypoints may choose different DSNs or choose no reporting at all.

Once initialized, shared native capture hooks become active for both native and Fennel-originated failures.

## Components

### Vendored SDK

- Add Sentry Native SDK source under `external/sentry-native`.
- Configure it from `CMakeLists.txt` with SDK tests/examples/tools disabled.
- Link the SDK target into `space_lib`.
- Treat it as a required dependency: configure/build failures should fail the Space build rather than silently disabling reporting support.

### Native wrapper

Add `src/error_reporting.h` and `src/error_reporting.cpp` with a narrow API:

- `init(options)` validates DSN/options and initializes Sentry Native SDK.
- `enabled()` reports whether the SDK is initialized.
- `capture_message(level, logger, message)` reports explicit messages.
- `capture_exception(type, value, stacktrace, tags)` reports exception-style events.
- `flush(timeout_ms)` drains pending events.
- `shutdown()` shuts down idempotently during normal process teardown.
- `install_terminate_handler()` reports uncaught native exceptions after initialization.

The wrapper owns idempotency and lifecycle rules. Capture calls before initialization are safe no-ops returning `false`; invalid initialization options fail loudly.

### Fennel module

Add a `package.preload` binding named `error-reporting` with canonical Fennel option keys:

- `(init {:dsn string :environment string? :release string? :database-path string? :debug boolean?}) -> true`
- `(enabled?) -> boolean`
- `(capture-message level logger message) -> boolean`
- `(capture-error {:type string :message string :stacktrace string? :tags table?}) -> boolean`
- `(flush timeout-ms) -> boolean`
- `(shutdown) -> nil`

Options are strict: `:dsn` is required for `init`, unknown aliases are not accepted, and invalid types raise an error through the binding. Supported levels are `"fatal"`, `"error"`, `"warning"`, `"warn"`, `"info"`, and `"debug"`; `"warn"` normalizes to warning.

### Canonical app entrypoint

`assets/lua/main.fnl` will initialize `error-reporting` early, near existing logging setup, using the main Bugsink DSN. Optional metadata such as release/environment may come from environment variables, but the DSN decision remains in Fennel code for the entrypoint.

Alternate entrypoints can opt in with their own DSN by requiring `:error-reporting` and calling `init`. Entrypoints that do not initialize reporting send no events.

## Capture Seams

The clean seams are the existing central failure paths plus native terminate handling:

1. **Top-level Fennel/Lua errors:** in the existing `sol::error` catch blocks in `apps/space/main.cpp` for REPL startup, command/stdin, file execution, module loading, and module function execution. Capture before preserving current log/stderr/exit behavior.
2. **Fatal Lua traceback:** in `LuaRuntime::install_fatal_traceback`, capture the traceback before the existing abort path and flush briefly.
3. **Callback errors that are currently logged but do not terminate:** in callback dispatch code, capture the callback exception while preserving the current continue/log behavior.
4. **Native uncaught exceptions/terminate:** install a terminate handler that captures active native exception text when reporting is enabled, flushes briefly, and then delegates to the previous terminate behavior or aborts.
5. **Native crash handling:** enable Sentry Native SDK crash handling/minidump support through the wrapper as supported by the vendored SDK/platform.

Failures before Fennel initializes reporting are intentionally out of scope. That is the trade-off required for entrypoint-owned DSN selection.

## Error Handling and Privacy

- Initialization with an empty/invalid DSN fails loudly.
- SDK initialization failure is surfaced to Fennel as an error; it must not degrade into a quiet no-op.
- Capture before initialization returns `false` and does not implicitly initialize.
- Existing stderr, logging, and exit-code behavior must remain unchanged.
- Tests and local development validation must not use the production Bugsink DSN.
- The implementation should avoid adding broad user-data context automatically; any future PII policy or user-consent UI is outside this initial scope.

## Testing Strategy

Focused tests should cover:

- Native wrapper disabled behavior before initialization.
- Native wrapper delivery to a local HTTP test server using a local DSN.
- Fennel module exports and strict option validation.
- Fennel capture functions returning `false` before initialization.
- Top-level Fennel startup error reporting after Fennel initializes with a local test DSN.
- Callback error reporting after Fennel initializes with a local test DSN.
- Existing Lua module error integration behavior remains unchanged.

Validation ladder for implementation:

1. `make cmake` after dependency/CMake changes.
2. `make build` because this touches native dependencies, C++ runtime, bindings, and startup.
3. `make fennel-check` after Fennel changes.
4. `make constraints` after compile success.
5. Focused C++/CTest coverage for wrapper and Lua error integration.
6. Focused Fennel test for `error-reporting` module.
7. Full `make test` with the repository's standard test hygiene because the change affects startup, runtime bindings, and top-level error paths.

## Out of Scope

- Reporting failures that happen before a Fennel entrypoint initializes reporting.
- CEF/browser JavaScript error reporting.
- User-facing telemetry settings UI.
- Automated symbol upload pipeline.
- Broad PII scrubbing policy beyond avoiding new automatic user-data context in this initial integration.
