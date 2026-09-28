# jobs

## Canonical Import

```fennel
(local jobs (require :jobs))
```

## Source Files

- `src/lua_jobs.cpp`
- `src/engine.cpp`

## What It Provides

`jobs` submits work to the engine job system and polls completed Lua-owned job results.

## API Summary

- `submit(kind payload [callback])` or `submit({:kind ... :payload ... :callback ...})` returns a job id.
- `poll([max-results])` returns completed job result tables.
- Result tables include `id`, `ok`, `kind`, `result`, and `error`. Some engine jobs attach extra fields such as GLTF data, texture dimensions, binary payloads, or aux values.

## Examples

```fennel
(local jobs (require :jobs))
(local callbacks (require :callbacks))

(local id (jobs.submit "example" "payload" (fn [result]
  (print "job complete" result.id result.ok))))
(callbacks.dispatch)
(print "submitted" id)
```

## Errors and Platform Notes

`jobs.submit` requires a string kind. `jobs.poll` rejects negative `max-results`. The module is bound by the engine host; use it when the engine job system is active.

## Related Modules

- [`callbacks`](/sdk/modules/callbacks) for callback delivery.
- [`engine`](/sdk/modules/engine) for the host that installs the job system binding.

## Aliases and Search Terms

Search terms: background jobs, worker jobs, async work, job system.
