# logging

## Canonical Import

```fennel
(local logging (require :logging))
```

## Source Files

- `src/lua_logging.cpp`
- `src/lua_runtime.cpp`

## What It Provides

`logging` writes structured Space log messages, configures global and named logger levels, and controls the log output file lifecycle.

## API Summary

- Message functions: `debug(...)`, `info(...)`, `warn(...)`, `error(...)`; an optional first table is formatted as fields.
- Level controls: `set-level(level)` or `set-level(name level)`, `get-level(name)`.
- Named loggers: `get(name)` returns a logger with `debug`, `info`, `warn`, `error`, `set-level`, `get-level`, and `flush`.
- Lifecycle: `init({:path ... :restart ... :level ...})`, `get-output-path()`, `flush()`, `shutdown()`.

## Examples

```fennel
(local logging (require :logging))

(logging.init {:level "info"})
(logging.info {:module "demo" :attempt 1} "starting work")
(local log (logging.get "sdk-example"))
(log:warn "using fallback path")
```

## Errors and Platform Notes

Unknown log levels make `set-level` return false; `init` ignores invalid level strings and otherwise delegates to native log configuration. Empty messages with no fields are skipped.

## Related Modules

- [`error-reporting`](/sdk/modules/error-reporting) for external error capture.
- [`appdirs`](/sdk/modules/appdirs) for log directory discovery.

## Aliases and Search Terms

Search terms: logs, logger, structured logging, log level, trace output.
