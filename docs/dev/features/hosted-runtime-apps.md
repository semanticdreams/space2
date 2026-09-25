# Hosted Runtime Apps

Space-runtime apps are hostable when their entry module exports a runtime composition factory.

```fennel
{:metadata {:id "examples.snake" :title "Snake" :host-api 1}
 :create create
 :main main}
```

`create(host)` returns a runtime composition object. It must not create, start, run, shut down, or drop `Engine` directly. It must not replace `app.engine`, `app.renderers`, or `app.active-world-runtime`.

## Host capabilities

The host provides services such as `viewport`, `surfaces`, `presentation`, `scheduler`, `input`, `inspectors`, `commands`, `assets`, `logging`, and `lifecycle`. Apps require capabilities by name and fail loudly when required services are absent. Apps do not receive or branch on a hosted-vs-standalone mode flag.

Embedded Space workspace hosts provide the same generic services plus optional
Space surface adapters when the shell exposes them:

- `host.hud` proxies `app.hud` panel insertion/removal.
- `host.canvas` proxies `app.canvas` panel insertion/removal.
- `host.scene` proxies `app.scene` panel insertion/removal.

Adapters own children added through them. Dropping the embedded host removes
those owned HUD/canvas/scene panel children exactly once; children removed
through the adapter are no longer removed again during host teardown.

## Runtime composition facets

A runtime may expose:

- `metadata`: plain metadata.
- `presentation`: existing Space presentation provider methods such as `render-targets`, `input-controls`, `screen-pos-ray`, and `camera`.
- `lifecycle`: deterministic teardown such as `drop`.
- `scheduler`: app simulation registrations.
- `inspectors`: plain-data or moldable inspector registrations.
- `commands`: command registrations for tools and live controls.

The core entry API does not add a new required method for every game feature.

## Pause, step, and inspection

Hosts pause and step scheduler lanes. Apps register pausable work with `host.scheduler`. Apps expose state through `host.inspectors` or an `inspectors` runtime facet. Pause, step, and inspection are not required methods on every app.

## Standalone and embedded hosts

Standalone launch and embedded mounting construct different generic hosts, then call the same `create(host)` app factory. App logic is shared.

In standalone mode `host.lifecycle:quit()` exits through the standalone engine.
In embedded workspace mode `host.lifecycle:quit()` closes the workspace mount via
the host's close callback; it does not quit the Space process and does not
replace `app.active-world-runtime`, `app.renderers`, or global renderer state.
Apps should request capabilities from the host rather than checking a
hosted-vs-standalone flag.

## Deferred alternatives

Process-isolated hosting and compositor embedding are future work. wlroots/Xwayland embedding remains deferred because the previous attempt was unstable in headless rendering, DMA-BUF import, readback, socket lifecycle, and teardown.
