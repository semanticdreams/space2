# notify

## Canonical Import

```fennel
(local notify (require :notify))
```

## Source Files

- `src/lua_notify.cpp`
- `src/lua_runtime.cpp`

## What It Provides

`notify` sends desktop notifications through the compiled notification backend and exposes support information.

## API Summary

- `supported` is a table with `supported`, `backend`, and `reason`.
- `support()` returns fresh support info.
- `create()` returns a notification center object.
- Default-center functions: `send(summary [body] [icon] [options])`, `set-app-name(name)`, `last-error()`, and `backend()`.
- Notification objects support `send`, `set-app-name`, `last-error`, and `backend`.
- Options may include `timeout-ms`, `urgency`, `category`, `app-name`, `replace-key`, `desktop-entry`, `synchronous`, `resident`, `transient`, `suppress-sound`, `sound-file`, `actions`, `on-close`, and `hints` when the backend supports them.

## Examples

```fennel
(local notify (require :notify))

(if notify.supported.supported
    (notify.send "Space" "Build finished" nil {:timeout-ms 3000})
    (print "notifications unavailable:" notify.supported.reason))
```

## Errors and Platform Notes

`send` returns false and sets `last-error` for unsupported backends, invalid options, or notification backend failures. Backend availability is compile- and platform-dependent.

## Related Modules

- [`tray`](/sdk/modules/tray) for system tray integration.
- [`logging`](/sdk/modules/logging) for local status logs.

## Aliases and Search Terms

Search terms: desktop notification, libnotify, toast, alert.
