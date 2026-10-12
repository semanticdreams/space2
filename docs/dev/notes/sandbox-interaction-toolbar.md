---
type: dev-note
tags:
  - note
---

# Sandbox Interaction Toolbar

This note describes the Sandbox-owned center-column activity toolbar and its canonical interaction model. Sandbox exposes exactly one active interaction mode at a time: **Fly** (`:flight`), **Walk** (`:walk`), **Move** (`:move`), or **Grab** (`:grab`). Navigation, object dragging, persistence, and physics behavior all derive from that single mode.

## Layout

The Sandbox toolbar is contributed by the active activity and laid out in the HUD center column between full-height left and right rails.

- **`hud-layout.fnl`** reserves a top-toolbar slot in the center column only, placed above the scene stack. It does not appear in the left or right rails.
- **`activity-top-toolbar-view.fnl`** is a Layout wrapper that tracks `app.activity-top-toolbar-builder`. When the builder changes (for example, activation or deactivation), it drops the previous toolbar and builds the new one. Its measured height is stored in `app.activity-top-toolbar-height`.
- **Expanded sidebar panels** query `app.activity-top-toolbar-height` so their content area reserves that height. The rails retain full height.
- **Left and right rails** remain full-height general HUD controls outside Sandbox ownership. Non-Sandbox activities have no toolbar by default; the toolbar slot is empty until an activity contributes a builder.

## Canonical Modes

| Mode | Keyword | Toolbar label | Behavior |
|---|---|---|---|
| Fly | `:flight` | Fly | Existing free camera controls. No object drag starts from this mode. |
| Walk | `:walk` | Walk | Grounded camera controls: WASD movement, arrow-key yaw/pitch, Space jump, terrain grounding, and pitch limits. No object drag starts from this mode. |
| Move | `:move` | Move | Direct object movement. The clicked object follows the normal movable drag target path. |
| Grab | `:grab` | Grab | Physics-backed object manipulation using a Bullet point-to-point constraint at the clicked surface point. |

Only the active mode button uses the primary button variant. Selecting another toolbar button calls `state:set-interaction-mode` and replaces the active mode; modes are not independent toggles.

Holding Alt while dragging is not an object movement path. Sandbox object movement starts only in Move or Grab mode through the activity object-drag mode provider.

## Activity Hooks

The activity activation context (`ctx`) in `activities.fnl` exposes the Sandbox toolbar and object-drag hooks used by this model:

### `ctx:set-top-toolbar-builder!(builder)`

Sets the current activity's top-toolbar builder. The builder must be a function `(fn [ctx] -> widget)` that produces a Layout-compatible widget tree. Sandbox sets this to `(SandboxToolbarView toolbar-state)`. The toolbar is built when the builder reference changes; the retained child is measured and laid out on subsequent frames.

### `ctx:set-object-drag-mode-provider!(provider)`

Sets a zero-argument function that returns the current object-drag mode for the activity: `nil`, `:move`, or `:grab`. Sandbox installs `(fn [] (toolbar-state:object-drag-mode))`.

`state-runtime.fnl` exposes `Runtime.activity-object-drag-mode`, which returns the provider result and fails loudly if the provider returns any other value. `pointer.fnl` allows `MovableMouseButtonDown` only when this runtime helper returns `:move` or `:grab`.

All activity runtime hooks are cleared by `clear-activity-runtime-hooks!` during activity deactivation, including `app.activity-top-toolbar-builder` and `app.activity-object-drag-mode-provider`.

## Sandbox Toolbar State

**File:** `assets/lua/sandbox-toolbar-state.fnl`

`(SandboxToolbarState opts)` creates a toolbar state table with one canonical property and a `Signal` for change notifications.

### Property

| Property | Type | Default | Valid Values |
|---|---|---|---|
| `interaction-mode` | keyword | `:flight` | `:flight`, `:walk`, `:move`, `:grab` |

The field is exposed through metatable `__index` as `state.interaction-mode`.

### Key Methods

- **`state:set-interaction-mode(mode)`** — validates and activates one of the four canonical modes. Emits `changed` when the mode changes.
- **`state:navigation-mode()`** — returns `:flight` or `:walk` for navigation modes; returns `nil` in Move or Grab.
- **`state:object-drag-mode()`** — returns `:move` or `:grab` for object-drag modes; returns `nil` in Fly or Walk.
- **`state:capture-state()`** — returns `{:interaction-mode "flight"/"walk"/"move"/"grab"}` for persistence.
- **`state:restore-state(payload)`** — restores the canonical persisted payload, or migrates legacy restore payloads as described below. Accepts `nil` as a no-op.
- **`state.changed`** — a `Signal` emitted whenever the active mode changes. `SandboxToolbarView` connects to it to update button variants.

### Errors

- Invalid construction options fail immediately; only `:interaction-mode` is accepted.
- Invalid mode values in options, setters, or restore payloads raise descriptive errors.
- Invalid legacy migration payload fields raise descriptive errors instead of silently falling back.

### Legacy Migration

Restore-time migration accepts persisted payloads written before the four-mode model. This is the only supported legacy compatibility surface; old runtime aliases and old construction options are intentionally absent.

Legacy payload mapping:

- `object-move-enabled? == true` and `drag-attachment == "anchor"` restores to `:grab`.
- `object-move-enabled? == true` with any other valid attachment restores to `:move`.
- Otherwise, `camera-mode == "grounded"` restores to `:walk`.
- Otherwise the payload restores to `:flight`.

Legacy fields are validated while migrating. Invalid legacy values fail loudly, and `capture-state` writes only the canonical `interaction-mode` field.

## Sandbox Toolbar View

**File:** `assets/lua/sandbox-toolbar-view.fnl`

`(SandboxToolbarView state)` returns a builder function `(fn [ctx] -> root-widget)`. The builder creates a horizontal `Flex` inside the HUD chrome card containing four mutually-exclusive `Button` widgets:

| Button | Icon | Layout name |
|---|---|---|
| Fly | `flight` | `sandbox-toolbar-mode-flight` |
| Walk | `directions_walk` | `sandbox-toolbar-mode-walk` |
| Move | `open_with` | `sandbox-toolbar-mode-move` |
| Grab | `pan_tool` | `sandbox-toolbar-mode-grab` |

### Update Cycle

The view connects to `state.changed`. On any mode change, it re-resolves theme colors and updates each button variant so only the active mode is primary. Layout is marked dirty when button background colors change.

### Cleanup

`root.drop` disconnects from `state.changed` before delegating to the Card's original `drop`, preventing stale callbacks on rebuilt toolbars.

## Object Dragging

`state-runtime.fnl` asks the active activity for an object-drag mode. If no activity installs a provider, or the provider returns `nil`, movable object dragging does not start from pointer input. The pointer must use left button down while Sandbox is in Move or Grab, and the existing drag threshold is preserved before a drag session engages.

### Move Mode

Move mode uses the existing direct movable target path. In `layout-physics-bodies.fnl`, Move returns `false` from the physics-backed `on-drag-update`, allowing the default target-position movement path to apply.

### Grab Mode

Grab mode uses `assets/lua/physics-point-grab.fnl` and the narrow Bullet binding for `bt.Point2PointConstraint`.

**Mechanism:**

1. On drag start, `layout-physics-bodies.fnl` requires a physics-backed entry and creates `drag.point-grab` with `PhysicsPointGrab.create`.
2. `PhysicsPointGrab.create` computes the local pivot from the clicked world-space hit point, creates a Bullet point-to-point constraint, and adds it to the physics world.
3. On drag update, the drag session calls `drag.point-grab:update-target update.hit`, which updates the constraint's target pivot.
4. On drag end, the point-grab session is destroyed and removed from the physics world before the layout position and rotation are synced from the body's final transform.

**Failure behavior:**

- Missing physics world, missing body, missing hit point, missing Bullet point-to-point binding, or missing `addConstraint`/`removeConstraint` support raises an explicit error.
- Grab update requires an active point-grab session and an update hit point.
- The Bullet binding remains narrow: it exposes the explicit point-to-point constructor and methods needed by Grab rather than a broad constraint framework.

## Walk Camera Controls

**File:** `assets/lua/sandbox-camera-controls.fnl`

`SandboxCameraControls` wraps `FirstPersonControls`. It delegates all handlers in Fly mode and provides terrain-following grounded movement in Walk mode.

### Dependencies

- `camera` — the scene camera (required)
- `toolbar-state` — `SandboxToolbarState` instance (required)
- `flight-controls` — a `FirstPersonControls` instance (required)
- `terrain-sampler` — an object with `:height-at-world-point(world-point)` method (required for Walk mode)

### Terrain Sampler

The Scene (`scene.fnl`) implements `:height-at-world-point` by querying `TerrainQuery.surface-info-at-world-point` and returning the world-space Y of the surface point, or 0.0 when no surface is found.

### Failure Behavior

- Missing terrain sampler at construction with Walk active fails immediately.
- Missing terrain sampler after construction causes every handler that touches Walk state (`update`, `on-key-down`, `on-key-up`, `on-mouse-button-down`, `on-mouse-button-up`, `on-mouse-motion`) to fail before camera or state mutation.
- Invalid `delta-unit` raises an error with the expected values.

### Movement

- **Horizontal:** WASD-style movement actions (`move-left`/`move-right`/`move-forward`/`move-backward`) move the camera at the configured `movement-speed` along the horizontal projection of the camera's forward and right vectors.
- **Look:** Arrow-key look actions adjust yaw and pitch. Left-button mouse look also adjusts yaw and pitch when the camera controls receive the drag.
- **Pitch clamp:** Accumulated pitch is clamped to `[pitch-min, pitch-max]` (default `[-1.2, 1.2]` radians). The pitch accumulator is tracked internally and reset on `drop`.

### Jump and Gravity

- **Jump:** Pressing Space sets `vertical-velocity` to `jump-speed` (default 8.0) and marks the camera airborne. Jumps are only possible from the grounded state.
- **Gravity:** While airborne, `vertical-velocity` decreases by `gravity * delta-seconds` (default gravity: 18.0). Position is integrated directly.
- **Landing:** When downward movement reaches the terrain plus eye-height threshold, the camera snaps to the terrain and clears airborne state.
- **Terrain following:** While grounded, a `CameraAnimation.scalar-channel` with smoothing rate 8.0 smoothly adjusts the camera Y to follow terrain height changes. The channel uses exponential easing (`alpha = 1 - exp(-rate * delta-seconds)`).

### What It's Not

- Walk mode is terrain-following camera movement, not a full character controller. There is no collision detection, no step-up, no crouch, and no slope handling beyond the terrain height query.
- `on-mouse-wheel` is a no-op in Walk mode.
- Gamepad controls delegate to flight controls; Walk mode has no native gamepad support.

### Additional Options

| Option | Default | Description |
|---|---|---|
| `eye-height` | 2.0 | Height above terrain for camera |
| `gravity` | 18.0 | Downward acceleration |
| `jump-speed` | 8.0 | Initial vertical speed on jump |
| `pitch-min` | -1.2 | Minimum pitch angle (radians) |
| `pitch-max` | 1.2 | Maximum pitch angle (radians) |
| `movement-speed` | 10.0 | Horizontal movement speed |
| `mouse-look-speed` | 0.001 | Mouse-look sensitivity |
| `delta-unit` | `:milliseconds` | Unit for delta (`:milliseconds` or `:seconds`) |

## Camera Animation

**File:** `assets/lua/camera-animation.fnl`

`CameraAnimation.scalar-channel(opts)` is a lightweight easing helper used by Walk mode for smooth terrain following.

- `channel:value` — returns the current scalar value
- `channel:set-target(n)` — sets the target value; returns `true`
- `channel:snap(n)` — sets both current and target to `n`; returns `true`
- `channel:update(delta-seconds)` — approaches target exponentially via `alpha = 1 - exp(-rate * delta)`; snaps when distance < 1e-5
- All inputs are validated; non-numeric values raise errors.

## See Also

- [Sandbox interaction mode design](../../specs/2026-08-06-sandbox-interaction-modes-design.md)
- [Activity Retention Tests](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/tests/test-activity-retention.fnl) — tests for hook lifecycle
- [Scene Drag Tests](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/tests/test-scene-drag.fnl) — tests for provider-gated dragging
- [Layout Physics Bodies Tests](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/tests/test-layout-physics-bodies.fnl) — tests for Move/Grab physics-backed dragging
- [Sandbox Camera Controls Tests](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/tests/test-sandbox-camera-controls.fnl) — tests for Fly/Walk camera behavior
- [Camera Animation Tests](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/tests/test-camera-animation.fnl) — tests for scalar channel
