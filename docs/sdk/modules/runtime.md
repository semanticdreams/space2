# runtime

## Canonical Import

```fennel
(local runtime (require :runtime))
```

## Source Files

- `src/lua_runtime.cpp`

## What It Provides

`runtime` exposes the active Space asset root and Fennel module search path configured by the host runtime.

## API Summary

- `assets-path` is the resolved asset root path.
- `fennel-path` is the semicolon-separated Fennel search path assembled from asset roots.

## Examples

```fennel
(local runtime (require :runtime))

(print "assets:" runtime.assets-path)
(print "fennel search:" runtime.fennel-path)
```

## Errors and Platform Notes

The table is created after the runtime configures package paths. Values reflect the host process asset roots and environment, so they may differ between development, packaged apps, and tests.

## Related Modules

- [`engine`](/sdk/modules/engine) for engine-level asset lookup.
- [`fs`](/sdk/modules/fs) for path inspection and file operations.

## Aliases and Search Terms

Search terms: assets path, Fennel path, package path, runtime paths.
