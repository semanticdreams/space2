# Remote Control (Debugging)

Run the app with a ZeroMQ endpoint to evaluate Fennel code inside the live process:

```
SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m main --remote-control=ipc:///tmp/space-rc.sock
```

Send code from another process using the bundled Fennel client:

```
./build/space -m tools.remote-control-client:main -- --endpoint ipc:///tmp/space-rc.sock -c "(+ 1 2)"
```

This executes in `_G` (so `app`, `logging`, etc. are available) and replies with `ok ...` or `error ...`.
Only enable this on trusted machines; it executes arbitrary code in the running app.

The transport now belongs to the process-lifetime `live-dev-runtime` coordinator,
not the reloadable application root. Root reloads preserve the same REP socket,
eval environment, and async helper results. Normal non-Linux/non-checkout runs
still accept an explicitly configured endpoint without creating a Linux registry.
Linux checkout runs also allocate a private checkout-scoped endpoint when none
was supplied; see [Live development runtime](features/live-dev.md) for discovery,
identity checks, and the structured operation protocol.

`RemoteControl:tick()` retains its unbounded drain behavior and returns the
number of handled messages. `RemoteControl:tick(limit)` accepts a positive
integer and handles at most that many messages. The coordinator uses a bound of
one, then yields through native callbacks, including while the renderer is idle.

Async results are supported via the `remote_control` helper exposed to the eval environment:

```
;; returns a request id immediately
(local id (remote_control.create))
(app.engine.events.window-resized:connect
  (fn [e]
    (remote_control.resolve id {:width e.width :height e.height})))
id
```

Poll from a client:

```
./build/space -m tools.remote-control-client:main -- --endpoint ipc:///tmp/space-rc.sock \
  -c "(remote_control.poll \"<id>\")"
```

To exercise the async flow against a live app, run the heavy test script:

```
scripts/remote-control-heavy.sh ipc:///tmp/space-rc.sock
```

The historical `remote_control.create/resolve/reject/poll` API and `ok ...` /
`error ...` wire framing are unchanged. These string IDs are separate from the
coordinator's numeric operation IDs. Structured clients should evaluate an
expression returning JSON, rather than depend on the evaluator's abbreviated
table preview, for example:

```fennel
((. (require :json) :dumps)
  ((. (require :live-dev-runtime) :rpc)
    {:expected-instance-id "<verified-instance-id>" :action "status"}))
```
