# appdirs

## Canonical Import

```fennel
(local appdirs (require :appdirs))
```

## Source Files

- `src/lua_appdirs.cpp`
- `src/lua_runtime.cpp`

## What It Provides

`appdirs` resolves platform-appropriate user, site, home, temporary, cache, config, data, and log directories for Space apps.

## API Summary

- `user-data-dir([app-name])`, `user-config-dir([app-name])`, `user-cache-dir([app-name])`, `user-log-dir([app-name])` return per-user locations. The default app name is `space`.
- `site-data-dir([app-name])`, `site-config-dir([app-name])` return shared site-level locations.
- `home-dir()` and `tmp-dir()` return the current user's home directory and the process temporary directory.

## Examples

```fennel
(local appdirs (require :appdirs))

(local config-dir (appdirs.user-config-dir :my-tool))
(local cache-dir (appdirs.user-cache-dir :my-tool))
(print config-dir cache-dir)
```

## Errors and Platform Notes

Directory conventions are resolved by the native `appdirs` implementation and may differ by OS. Functions return path strings; callers are responsible for creating directories before writing into them.

## Related Modules

- [`fs`](/sdk/modules/fs) for creating directories and files at resolved paths.
- [`runtime`](/sdk/modules/runtime) for asset and Fennel search path information.

## Aliases and Search Terms

Search terms: application directories, config directory, cache directory, data directory, log directory, temp directory.
