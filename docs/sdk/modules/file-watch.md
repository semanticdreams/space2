# file-watch

## Canonical Import

```fennel
(local file-watch (require :file-watch))
```

## Source Files

- `src/lua_file_watch.cpp`
- `src/lua_runtime.cpp`

## What It Provides

`file-watch` creates file watchers backed by efsw and polls file add, delete, modify, move, and missed-event notifications.

## API Summary

- `FileWatcher([options])` creates a watcher. Options include `generic`, `generic?`, `follow-symlinks`, `follow-symlinks?`, `allow-out-of-scope-links`, and `allow-out-of-scope-links?`.
- Module values: `actions` table and `last-error()`.
- Watcher methods: `add-watch(directory [recursive?])`, `remove-watch(id)`, `start()`, `poll()`, `directories()`, `follow-symlinks(bool)`, `allow-out-of-scope-links(bool)`, `follow-symlinks-enabled?()`, `allow-out-of-scope-links?()`, `started?()`, and `drop()`.

## Examples

```fennel
(local file-watch (require :file-watch))

(local watcher (file-watch.FileWatcher {:generic false}))
(watcher:add-watch "." false)
(watcher:start)
(each [_ event (ipairs (watcher:poll))]
  (print event.action event.path))
```

## Errors and Platform Notes

Adding an empty directory or a watch that efsw rejects raises an error. Methods raise after `drop`. Events are delivered by polling and include fields such as `watch-id`, `dir`, `filename`, `path`, `action`, `missed`, `old-filename`, and `old-path`.

## Related Modules

- [`fs`](/sdk/modules/fs) for filesystem operations.
- [`callbacks`](/sdk/modules/callbacks) for app polling loops.

## Aliases and Search Terms

Search terms: file watcher, directory watcher, efsw, filesystem events.
