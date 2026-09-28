# http

## Canonical Import

```fennel
(local http (require :http))
```

## Source Files

- `src/lua_http.cpp`

## What It Provides

`http` submits asynchronous HTTP client requests through the engine-owned HTTP client and exposes polling, callbacks, cancellation, headers, timeouts, redirects, and streaming response chunks.

## API Summary

- `request(opts)` submits a request and returns a numeric request id. `opts.url` is required. Optional keys include `method`, `body`, `headers`, `timeout-ms`, `connect-timeout-ms`, `delay-ms`, `follow-redirects`, `user-agent`, `callback`/`cb`, and `stream`.
- `poll([max-results])` returns a 1-indexed table of completed responses and dispatches registered callbacks. A response has `id`, `ok`, `status`, `error`, `body`, and `headers` fields.
- `cancel(id)` asks the HTTP client to cancel a pending request and returns whether cancellation was accepted.
- Streaming requests require `stream true` and a callback. The callback receives `{ :chunk <bytes> }` events and a final `{ :done true }` event.

## Examples

```fennel
(local http (require :http))

(local id (http.request {:url "https://example.com"
                         :method "GET"
                         :headers {:Accept "text/plain"}}))

(each [_ response (ipairs (http.poll))]
  (when (= response.id id)
    (print response.status)
    (print response.body)))
```

## Errors and Platform Notes

`request` raises `http.request requires a url` when `opts.url` is empty. Streaming requests raise `http.request with stream=true requires a callback` when no callback is supplied. Callback delivery happens when the runtime dispatches/polls HTTP completions; non-callback completions are buffered until `poll` consumes them. Cancelled requests are reported with `error` set to `"cancelled"`.

## Related Modules

- [`http_server`](/sdk/modules/http-server) for in-process HTTP routes and SSE.
- [`callbacks`](/sdk/modules/callbacks) for explicit callback dispatch in tests or command-line modules.

## Aliases and Search Terms

Search terms: HTTP client, fetch, request, response, headers, streaming, redirects, curl.
