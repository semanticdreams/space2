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

`engine` creates and controls the Space engine instance used by app hosts. The instance starts with lifecycle, asset path, event, and timing helpers; `start()` initializes SDL/window or headless runtime state and attaches the frame loop controls, input/audio/physics objects, callback/job/keyring helpers, mouse constants, dial-type hooks, and browser surface helpers used by apps.

## API Summary

- `Engine([options])` returns an engine table. Options include `headless`, positive `width` and `height`, non-empty `title`, and `window-mode` of `windowed`, `maximized`, or `fullscreen`.
- Before `start()`, instances expose:
  - `events`: the `engine-events` signal table.
  - `frame-id`: current rendered frame id, initially `0`.
  - `get-asset-path(path)`: resolves a runtime asset path.
  - `now-ms()`: monotonic time in milliseconds.
  - Lifecycle methods: `start()`, `run()`, `shutdown()`, `is-started()`, and `is-shutdown()`.
- `start()` initializes SDL/window or headless runtime state and returns whether startup succeeded. After successful startup the instance also exposes:
  - Window/runtime properties: `window-mode`, `width`, `height`, `pixel-width`, and `pixel-height` where a window exists.
  - Loop control: `quit()`, `request-frame()`, `set-target-fps(fps)`, `get-target-fps()`, and `target-fps`.
  - Pause flags: `set-physics-paused(bool)`, `get-physics-paused()`, `physics-paused`, `set-input-paused(bool)`, `get-input-paused()`, `input-paused`, `set-ui-paused(bool)`, `get-ui-paused()`, and `ui-paused`.
  - Cursor/text input: `set-system-cursor(name)` with built-in cursor names `arrow`, `hand`, and `ibeam`; `set-text-input-enabled(bool)` for SDL text input events.
  - Power/screensaver/video helpers: `set-screen-locked(bool)`, `is-on-battery()`, `has-active-video-playback()`, `set-screensaver-inhibited(bool)`, `screensaver-enabled()`, and `screensaver-inhibited`.
  - Engine-owned objects: `physics`, `audio`, and `input`.
  - Engine-bound helper tables from related modules: `callbacks`, `jobs`, `keyring`, and `mouse-buttons` (`left`, `middle`, `right`, `x1`, `x2`).
  - Dial-type hooks: `dial-type-activate(instance-id)`, `dial-type-deactivate(instance-id)`, `dial-type-on-input(instance-id callback)`, and `dial-type-off-input(callback-id)`.
  - `browser` subtable for CEF-backed offscreen surfaces, with `create-surface(options)`, `destroy-surface(id)`, `set-url(id url)`, `set-visible(id bool)`, `set-focus(id bool)`, `send-mouse-move(id x y [leave?])`, `send-mouse-click(id x y button mouse-up [click-count])`, `send-mouse-wheel(id x y dx dy)`, `texture-name(id)`, `texture-info(id)`, `surface-stats(id)`, and `list-surfaces()`.
- `events` contains signals including `engine-tick`, `updated`, keyboard/mouse/touch/pen/gamepad/text events, window mode/size/focus/minimize/visibility/occlusion events, app suspension, screen lock, battery, and video playback activity changes.
- During `run()`, the loop polls and emits input/window events, dispatches callbacks/jobs/process/http work, updates physics unless paused, updates audio/video, emits `engine-tick`, emits `events.updated` when rendering is enabled, increments `frame-id`, and delays to the target FPS when applicable.

## Examples

```fennel
(local engine (require :engine))

(local app (engine.Engine {:headless true :title "Tool host"}))
(when (app:start)
  (print "assets" (app:get-asset-path ""))
  (app:shutdown))
```

```fennel
(local engine (require :engine))

(local app (engine.Engine {:title "Interactive host" :window-mode "windowed"}))
(when (app:start)
  (app.set-target-fps 0) ; wait for events/request-frame instead of continuous FPS
  (app.set-system-cursor "hand")
  (app.set-text-input-enabled true)
  (app.events.text-input:connect
    (fn [payload]
      (print "typed" payload.text)
      (app.request-frame)))
  (app.events.engine-tick:connect
    (fn [payload]
      (print "frame" payload.frame-id "dt" payload.dt)))
  (app:run)
  (app:shutdown))
```

```fennel
(local engine (require :engine))

(local app (engine.Engine {:title "Browser surface"}))
(when (app:start)
  (local create-surface (assert (. app.browser "create-surface")))
  (local texture-name (assert (. app.browser "texture-name")))
  (local destroy-surface (assert (. app.browser "destroy-surface")))
  (create-surface
    {:id "docs" :url "https://example.invalid" :width 800 :height 600})
  (print "browser texture" (texture-name "docs"))
  (destroy-surface "docs")
  (app:shutdown))
```

## Errors and Platform Notes

Invalid `options.title`, `options.window-mode`, or invalid browser surface options raise Lua errors. `run` does nothing until `start` succeeds, and lifecycle calls are guarded after shutdown. Methods and properties attached by `start()` are unavailable before successful startup. Window-only helpers such as cursor changes, text input, browser surfaces, and screensaver inhibition depend on a non-headless SDL window; inhibiting the screensaver without a window raises an error. Setting an unknown system cursor logs a warning and leaves the cursor unchanged. `request-frame()` returns `false` when its SDL event type cannot be allocated. `target-fps` values less than or equal to zero put the loop into event-driven wait mode where `request-frame()` can force an `updated` emission.

## Related Modules

- [`runtime`](/sdk/modules/runtime) for Lua/Fennel runtime paths.
- [`input-state`](/sdk/modules/input-state) for input state objects used by engine-facing code.

## Aliases and Search Terms

Search terms: app host, game loop, engine lifecycle, asset path, window mode.
