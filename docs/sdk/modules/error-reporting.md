# error-reporting

## Canonical Import

```fennel
(local error-reporting (require :error-reporting))
```

## Source Files

- `src/lua_error_reporting.cpp`
- `src/lua_runtime.cpp`

## What It Provides

`error-reporting` configures and uses the native error reporting backend for messages, exceptions, flushing, and shutdown.

## API Summary

- `init(options)` enables reporting. Required `options.dsn` must be a non-empty string; optional keys are `environment`, `release`, `database-path`, and `debug`.
- `enabled?()` returns whether reporting is enabled.
- `capture-message(level logger message)` captures a message at `fatal`, `error`, `warning`/`warn`, `info`, or `debug`.
- `capture-error({:type ... :message ... [:stacktrace ...] [:tags {...}]})` captures an error payload.
- `flush(timeout-ms)` and `shutdown()` flush or close reporting.

## Examples

```fennel
(local error-reporting (require :error-reporting))

(when (not (error-reporting.enabled?))
  ;; Supply a project DSN in real apps.
  (print "error reporting not enabled"))

(error-reporting.capture-error
  {:type "ExampleError" :message "Something failed" :tags {:area "docs"}})
```

## Errors and Platform Notes

Invalid option keys, missing/empty `dsn`, wrong option types, invalid levels, and malformed capture payloads raise Lua errors. `init` raises when the native backend rejects initialization.

## Related Modules

- [`logging`](/sdk/modules/logging) for local logging.
- [`callbacks`](/sdk/modules/callbacks) for callback error capture behavior.

## Aliases and Search Terms

Search terms: errors, exceptions, Sentry, crash reporting, telemetry.
