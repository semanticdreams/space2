# Snackbar System

The snackbar system provides scoped, transient HUD messages without coupling
notification state to retained widgets. The public facade lives in
`assets/lua/snackbar.fnl`.

## Scopes

Use `Snackbar.create-scope opts` to create an independent manager/host pair:

- `scope.manager` is a `SnackbarManager` instance.
- `scope.host-builder` builds a `SnackbarHost` bound to that manager.
- `scope:drop()` drops the manager and prevents further use.

Each scope owns its own entries, queue, timers, handles, and subscriptions. The
HUD snackbar scope is the default app integration, not a singleton requirement.

## Manager responsibilities

`SnackbarManager` is widget-free. It owns normalized entries, visible and queued
policy, replacement and overflow behavior, runtime timers, dismiss handles, and
change subscriptions. Calls to `manager:show` accept text via `:text` or
`:message`, action descriptors, `:content-builder`, ids, replacement keys,
priority, duration, and persistence. Subscribers receive visible/queued entry
snapshots when state changes.

Theme policy is resolved from `ctx.theme.snackbar` where the HUD passes active
theme data into manager creation. Snackbar tokens configure placement, spacing,
padding, max width, default duration, visible/queued limits, and variant colors.

## Host responsibilities

`SnackbarHost` owns rendered snackbar widgets. It subscribes to manager changes,
reconciles the current visible entries, rebuilds replacement children, and drops
removed or remaining children exactly once during teardown. The host controls
placement and max-width layout, while the manager remains unaware of widgets.

The first implementation intentionally has no scrollable snackbar host. Overflow
is handled by manager policy (`:queue`, `:drop`, or `:replace`) rather than by a
notification history view.

## Content paths

The default content builder supports:

- simple text snackbars;
- text with action buttons from `:actions` descriptors;
- variant styling from `ctx.theme.snackbar.variants`.

An entry-level `:content-builder` overrides the default path for arbitrary widget
content. Builders receive `(ctx entry handle)` and must return a widget with a
layout.

## HUD integration

The default HUD host is mounted by the HUD layout builder inside the
center/middle region. This keeps snackbars within dynamically measured scene
bounds so they do not cover the control panel, status panel, top toolbar, or side
rails/docks. Default placement is `:top-right` and can be changed through
`ctx.theme.snackbar.placement` or host options for custom scopes.

## Validation

For snackbar or HUD-facing changes, run the Fennel validation ladder first:

```bash
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snackbar-manager:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-snackbar-host:main
```

When changing HUD mounting or layout bounds, also run focused HUD coverage:

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud-layout:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hud:main
```
