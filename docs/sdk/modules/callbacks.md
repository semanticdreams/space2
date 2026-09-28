# callbacks

## Canonical Import

```fennel
(local callbacks (require :callbacks))
```

## Source Files

- `src/lua_callbacks.cpp`
- `src/lua_runtime.cpp`

## What It Provides

`callbacks` registers Lua callbacks, queues payloads by id, dispatches pending callbacks, and drives polling loops for asynchronous subsystems.

## API Summary

- `register(fn)` returns a numeric callback id.
- `unregister(id)` removes a registered callback and returns whether it existed.
- `enqueue(id payload)` queues a payload for a registered callback.
- `dispatch([max-results])` invokes pending callbacks.
- `run-loop([opts])` repeatedly polls jobs, HTTP, process, HTTP server, and callbacks until an optional `until` function succeeds or `timeout-ms` expires. Options include `poll-jobs`, `poll-http`, `poll-process`, `sleep-ms`, `timeout-ms`, and `until`.

## Examples

```fennel
(local callbacks (require :callbacks))

(local id (callbacks.register (fn [payload] (print "payload" payload))))
(callbacks.enqueue id {:ok true})
(callbacks.dispatch)
(callbacks.unregister id)
```

## Errors and Platform Notes

`run-loop` rejects non-numeric or negative timing values. Callback invocation errors are captured through `error-reporting` and printed to stderr; dispatch continues for other callbacks.

## Related Modules

- [`jobs`](/sdk/modules/jobs) for async job callbacks.
- [`process`](/sdk/modules/process) for spawned process callbacks.

## Aliases and Search Terms

Search terms: async callbacks, event loop, polling, dispatch queue.
