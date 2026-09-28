# realtime

## Canonical Import

```fennel
(local realtime (require :realtime))
```

## Source Files

- `src/lua_realtime.cpp`
- `src/realtime/auth_ticket.h`
- `src/realtime/core.h`

## What It Provides

`realtime` exposes Space's native realtime service: feature registries, server/client creation, development auth tickets, connect tokens, callbacks, and reliable/unreliable feature messages.

## API Summary

- Module fields/functions: `available`, `version()`, `Service()`, `FeatureRegistry()`, `make-dev-ticket(opts)`, and `verify-dev-ticket(opts)`.
- `FeatureRegistry:register-feature({ :id n :version n :name string })` registers an offered feature; `list-features()` returns feature tables.
- `RealtimeService:create-feature-registry()`, `create-server(opts)`, and `create-client(opts)` create registries and endpoints. Server opts include `registry`, `bind-address`, `max-clients`, `server-scope`, and `connect-addresses`. Client opts include `registry` and `bind-address`.
- `RealtimeServer` supports `set-callback`, `start`, `close`, `is-running`, `address`, `create-connect-token`, feature activation/deactivation, direct sends, and broadcasts.
- `RealtimeClient` supports `set-callback`, `connect`, `close`, `is-connected`, `send-reliable`, and `send-unreliable`.
- Server callbacks: `started`, `stopped`, `client-connected`, `client-disconnected`, `feature-activated`, `feature-deactivated`, `message`, and `error`.
- Client callbacks: `connected`, `disconnected`, `feature-offered`, `feature-activated`, `feature-deactivated`, `message`, and `error`.

## Examples

```fennel
(local realtime (require :realtime))

(local service (realtime.Service))
(local registry (realtime.FeatureRegistry))
(registry:register-feature {:id 1 :version 1 :name "chat"})

(local server (service:create-server {:registry registry
                                      :bind-address "127.0.0.1:0"
                                      :max-clients 4}))
(server:set-callback "started" (fn [event] (print event.address)))
(server:start)
```

## Errors and Platform Notes

Callback names are validated and unknown names raise errors. Closed or closing server/client handles reject operational calls. Client `connect` requires both `client-id` and `connect-token`. Development ticket helpers require the documented payload/signature/secret fields and validate hex-encoded connect tokens. `version()` returns the underlying realtime transport implementation version string.

## Related Modules

- [`zmq`](/sdk/modules/zmq) for lower-level messaging sockets.
- [`uuid`](/sdk/modules/uuid) for generating identifiers used in application protocols.

## Aliases and Search Terms

Search terms: realtime, multiplayer, reliable message, unreliable message, feature registry, auth ticket, yojimbo. `yojimbo` is an implementation/search alias only; use `realtime` as the import name.
