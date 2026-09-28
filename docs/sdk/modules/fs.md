# fs

## Canonical Import

```fennel
(local fs (require :fs))
```

## Source Files

- `src/lua_fs.cpp`
- `src/lua_runtime.cpp`

## What It Provides

`fs` exposes filesystem path, metadata, reading, writing, directory, copy, remove, and disk-space helpers.

## API Summary

- Path helpers: `cwd()`, `set-cwd(path)`, `absolute(path)`, `relative(path [base])`, `parent(path)`, `join-path(...)`.
- Metadata and listing: `exists(path)`, `stat(path)`, `file-token(path)`, `list-dir(path [include-hidden?])`, `space([path])`.
- Reads: `read-file(path)`, `read-text-window(path offset max-bytes)`, `read-byte-range(path offset max-bytes)`.
- Writes and mutation: `write-file(path contents)`, `append-file(path contents)`, `atomic-replace-if-current(path segments expected-token [opts])`, `create-dir(path)`, `create-dirs(path)`, `remove(path)`, `remove-all(path)`, `rename(from to)`, `copy-file(from to [overwrite?])`, `copy(from to [recursive?] [overwrite?])`, `touch(path)`.

## Examples

```fennel
(local fs (require :fs))

(local path (fs.join-path (fs.cwd) "notes.txt"))
(fs.write-file path "hello\n")
(print (fs.read-file path))
(local info (fs.stat path))
(print info.type)
```

## Errors and Platform Notes

Many operations raise Lua errors with `fs.<function>` prefixes on invalid arguments or OS failures. Text and byte windows are capped at 262144 bytes. `stat` returns an error-shaped table for symlink status failures instead of throwing.

## Related Modules

- [`appdirs`](/sdk/modules/appdirs) for platform directories.
- [`file-watch`](/sdk/modules/file-watch) for change notifications.

## Aliases and Search Terms

Search terms: filesystem, files, directories, paths, atomic write, file metadata.
