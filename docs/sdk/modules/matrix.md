# matrix

## Canonical Import

```fennel
(local matrix (require :matrix))
```

## Source Files

- `src/lua_matrix.cpp`
- `assets/lua/tests/test-matrix.fnl`

## What It Provides

`matrix` exposes an optional asynchronous Matrix client binding for creating a client, logging in with a password, syncing once, listing rooms, closing the client, and checking handle state.

## API Summary

- `create-client(opts)` starts asynchronous client creation and returns the registered callback id. `opts.homeserver-url` is required; `homeserver` is accepted by the binding as a fallback source key. `opts.callback` or `opts.cb` is required.
- Client creation callbacks receive `{ :ok bool :error error-or-nil :client client-or-nil }`.
- `MatrixClient:login-password(username password callback)` asynchronously logs in and calls back with `ok`, `error`, and `user-id`.
- `MatrixClient:sync-once(callback)` performs one sync and calls back with `ok` and `error`.
- `MatrixClient:rooms(callback)` fetches joined rooms and calls back with `ok`, `error`, and a `rooms` array.
- `MatrixClient:close()` frees the native client; `is-closed()` reports whether it is closed.

## Examples

```fennel
(local matrix (require :matrix))

(matrix.create-client
  {:homeserver-url "https://matrix.example.org"
   :callback (fn [payload]
               (if payload.ok
                   (print "client ready")
                   (print payload.error.message)))})
```

## Errors and Platform Notes

When Matrix support is not built, `create-client` raises `matrix library not built; enable SPACE_BUILD_MATRIX`. Client creation requires `homeserver-url` and a callback. Operations on a closed client raise `matrix client is closed: <action>`. Callback payload errors include numeric `code` and string `message` fields when the native Matrix layer reports a failure.

## Related Modules

- [`callbacks`](/sdk/modules/callbacks) for dispatching asynchronous Matrix callbacks in tests.
- [`http`](/sdk/modules/http) for lower-level HTTP requests when not using the Matrix client binding.

## Aliases and Search Terms

Search terms: Matrix, homeserver, login, sync, rooms, chat, federated messaging.
