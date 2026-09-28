# lsqlite3

## Canonical Import

```fennel
(local lsqlite3 (require :lsqlite3))
```

## Source Files

- `src/lua_runtime.cpp`
- `external/sqlite/lsqlite3.c`
- `external/sqlite/sqlite3.h`

## What It Provides

`lsqlite3` is the bundled LuaSQLite3 binding for SQLite databases. Space registers the native module at runtime with `require :lsqlite3`; the API surface is the upstream LuaSQLite3 API rather than a Space-specific wrapper.

## API Summary

- Module-level open helpers include the upstream database constructors such as `open(...)`, `open_memory(...)`, and `open_ptr(...)` when provided by the bundled LuaSQLite3 source.
- Database handles expose the upstream methods for executing SQL, preparing statements, transactions, hooks/callbacks, extension loading, error inspection, and closing database handles.
- Statement handles expose the upstream methods for binding values, stepping through rows, reading columns, resetting, and finalizing prepared statements.
- SQLite result codes and constants are provided by the upstream binding table.

## Examples

```fennel
(local lsqlite3 (require :lsqlite3))

(local db (lsqlite3.open_memory))
(db:exec "CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT)")
(db:exec "INSERT INTO notes (body) VALUES ('hello from sqlite')")

(each [row (db:nrows "SELECT id, body FROM notes ORDER BY id")]
  (print row.id row.body))

(db:close)
```

## Errors and Platform Notes

Space does not add a compatibility alias named `sqlite`; use `lsqlite3` for the SQLite binding. API details, edge cases, return conventions, and compile-time omissions follow the bundled upstream LuaSQLite3 and SQLite sources. Consult upstream LuaSQLite3 documentation for the complete method list and SQLite documentation for SQL syntax, locking, threading, and extension-loading limits. When using database handles across concurrent work, respect SQLite and LuaSQLite3 thread-safety rules and close statements/databases explicitly.

## Related Modules

- [`sql-builder`](/sdk/modules/sql-builder) for generating SQLite-oriented SQL strings and bind parameters.
- [`fs`](/sdk/modules/fs) for locating and managing database files.

## Aliases and Search Terms

Search terms: sqlite, SQLite, database, SQL, LuaSQLite3, lsqlite, embedded database.
