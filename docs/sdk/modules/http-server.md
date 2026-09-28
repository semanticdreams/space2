# http_server

## Canonical Import

```fennel
(local http-server (require :http_server))
```

## Source Files

- `src/lua_http_server.cpp`

## What It Provides

`http_server` creates native HTTP servers, registers GET/POST handlers before listening, and supports server-sent event streams.

## API Summary

- `HttpServer()` constructs a server handle.
- `HttpServer:route(method path handler)` registers a `"GET"` or `"POST"` route before the server starts. `handler(request)` returns a response table, string, or `nil`.
- `HttpServer:route_sse(path handler)` registers a GET SSE route. `handler(request)` can use `request.stream:send(data)`, `request.stream:close()`, and `request.stream:on-close(fn)`.
- `HttpServer:listen(hostname port)` binds the server, starts its native thread, and returns the actual port. Passing `0` chooses an available port.
- `HttpServer:stop()` stops the server, closes active streams, and fails pending requests with status `503`.
- `HttpServer:port()` returns the bound port.
- Route requests expose `method`, `path`, `body`, `headers`, `query_params`, and, for SSE routes, `stream`.

## Examples

```fennel
(local http-server (require :http_server))

(local server (http-server.HttpServer))
(server:route "GET" "/health"
  (fn [request]
    {:status 200
     :headers {:Content-Type "text/plain"}
     :body (.. "ok " request.path)}))

(local port (server:listen "127.0.0.1" 0))
(print "listening" port)
```

## Errors and Platform Notes

Routes must be registered before `listen`; registering after start raises `HTTP server: routes must be registered before listen`. `listen` can only be called once per server and raises on bind failure. Only `GET` and `POST` are accepted by `route`. Handler errors become HTTP 500 responses. Native lifecycle diagnostics may write `space-http-lifecycle` lines to stderr unless disabled with `SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0`.

## Related Modules

- [`http`](/sdk/modules/http) for making client requests to HTTP services.
- [`callbacks`](/sdk/modules/callbacks) for dispatching pending route/SSE callbacks in non-app test loops.

## Aliases and Search Terms

Search terms: HTTP server, http-server, http_server, route, SSE, server-sent events, httplib. The page path is `/sdk/modules/http-server`, but the canonical import is `http_server`.
