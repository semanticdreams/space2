# tray

## Canonical Import

```fennel
(local tray (require :tray))
```

## Source Files

- `src/lua_tray.cpp`
- `src/lua_runtime.cpp`

## What It Provides

`tray` creates and drives a platform tray icon with menu items, callbacks, update, loop, and support information.

## API Summary

- `supported` is a table with `supported`, `backend`, and `reason`.
- `support()` returns support info.
- `create(spec)` returns a tray handle. `spec.icon` is a string and `spec.menu` is an array of menu item tables.
- Menu entries include `text`, optional `disabled`, `checked`, `checkable`, `cb`, and nested `submenu`.
- Handle methods: `start()`, `update([spec])`, `loop(blocking?)`, `exit()`, `last-error()`, and `backend()`.

## Examples

```fennel
(local tray (require :tray))

(when tray.supported.supported
  (local t (tray.create {:icon "icon.png"
                         :menu [{:text "Quit" :cb (fn [_] (print "quit"))}]}))
  (t:start)
  (t:loop false))
```

## Errors and Platform Notes

Invalid specs raise errors. `start` returns false and stores `last-error` when the backend is unavailable or missing runtime tray dependencies. Tray behavior depends on OS desktop environment support.

## Related Modules

- [`notify`](/sdk/modules/notify) for desktop notifications.
- [`callbacks`](/sdk/modules/callbacks) for callback-driven app loops.

## Aliases and Search Terms

Search terms: system tray, status icon, tray menu, menu callbacks.
