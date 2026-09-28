# zmq

## Canonical Import

```fennel
(local zmq (require :zmq))
```

## Source Files

- `src/lua_zmq.cpp`

## What It Provides

`zmq` exposes ZeroMQ contexts, sockets, messages, polling, socket type constants, flag constants, and common context/socket options.

## API Summary

- `Context([io-threads])` creates a `ZmqContext`; methods include `socket(type)`, `shutdown()`, `close()`, `is-closed()`, `get-option-int(name)`, and `set-option-int(name value)`.
- `ZmqSocket` methods include `bind(endpoint)`, `connect(endpoint)`, `unbind(endpoint)`, `disconnect(endpoint)`, `close()`, `is-closed()`, `send(data [flags])`, `recv([flags])`, `recv-multipart([flags])`, integer/string option getters and setters.
- `Message([data])` creates a `ZmqMessage`; methods include `size()` and `to-string()`.
- `poll(items [timeout-ms])` polls items shaped like `{ :socket sock :events zmq.poll-events.IN }` and returns tables containing `revents`.
- Constants: `socket-types`, `send-flags`, `recv-flags`, and `poll-events`.
- `version()` returns `{ :major n :minor n :patch n }`.

## Examples

```fennel
(local zmq (require :zmq))

(local ctx (zmq.Context 1))
(local receiver (ctx:socket (. zmq.socket-types :PULL)))
(receiver:bind "inproc://example")

(local sender (ctx:socket (. zmq.socket-types :PUSH)))
(sender:connect "inproc://example")
(sender:send "hello")

(local message (receiver:recv))
(print (message:to-string))
```

## Errors and Platform Notes

Using a closed context or socket raises an action-specific error. Unsupported option names raise `zmq.* unsupported option` errors. `send` accepts a string, `ZmqMessage`, or a multipart table of strings/messages; empty multipart sends raise an error. `recv` and `recv-multipart` return `nil` when no message is available under the selected flags/timeouts.

## Related Modules

- [`realtime`](/sdk/modules/realtime) for higher-level realtime client/server transport.
- [`http`](/sdk/modules/http) for request/response networking.

## Aliases and Search Terms

Search terms: ZeroMQ, zmq, messaging, pub/sub, req/rep, multipart, socket, poll.
