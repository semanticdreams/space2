# engine

## Canonical Import

```fennel
(local engine (require :engine))
```

## Source Files

- `src/lua_engine.cpp`
- `src/engine.cpp`
- `src/lua_runtime.cpp`

## What It Provides

`engine` creates and controls the Space engine instance used by app hosts, including lifecycle, asset path lookup, event access, and frame timing.

## API Summary

- `Engine([options])` returns an engine table. Options include `headless`, positive `width` and `height`, non-empty `title`, and `window-mode` of `windowed`, `maximized`, or `fullscreen`.
- Engine instances expose `events`, `frame-id`, `get-asset-path(path)`, `now-ms()`, `start()`, `run()`, `shutdown()`, `is-started()`, and `is-shutdown()`.

## Examples

```fennel
(local engine (require :engine))

(local app (engine.Engine {:headless true :title "Tool host"}))
(when (app:start)
  (print "assets" (app:get-asset-path ""))
  (app:shutdown))
```

## Errors and Platform Notes

Invalid `options.title` or `options.window-mode` raises a Lua error. `run` does nothing until `start` succeeds, and lifecycle calls are guarded after shutdown. Window behavior depends on the platform and engine build.

## Related Modules

- [`runtime`](/sdk/modules/runtime) for Lua/Fennel runtime paths.
- [`input-state`](/sdk/modules/input-state) for input state objects used by engine-facing code.

## Aliases and Search Terms

Search terms: app host, game loop, engine lifecycle, asset path, window mode.
