# Error Reporting

Space uses the vendored Sentry Native SDK to report Bugsink-compatible events.
Fennel entrypoints own initialization and DSN choice. Requiring `:error-reporting` does not initialize reporting.

## Main entrypoint

`assets/lua/main.fnl` initializes reporting with the main Bugsink DSN during app startup. Tests must not use that DSN.

## Fennel API

- `(init {:dsn string :environment string? :release string? :database-path string? :debug boolean?})`
- `(enabled?)`
- `(capture-message level logger message)`
- `(capture-error {:type string :message string :stacktrace string? :tags table?})`
- `(flush timeout-ms)`
- `(shutdown)`

## Capture seams

After initialization, C++ reports top-level Lua errors, fatal Lua tracebacks, callback errors, native terminate events, and SDK-supported native crashes.

## Test safety

Tests use local DSNs such as `http://public@127.0.0.1:<port>/1` and must never send to `bugsink.narlun.com`.
