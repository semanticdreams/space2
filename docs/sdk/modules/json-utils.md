# json-utils

## Canonical Import

```fennel
(local json-utils (require :json-utils))
```

## Source Files

- `assets/lua/json-utils.fnl`
- `src/lua_json.cpp`
- `src/lua_fs.cpp`

## What It Provides

`json-utils` adds small persistence helpers on top of [`json`](/sdk/modules/json) and [`fs`](/sdk/modules/fs): atomic JSON writes and deterministic JSON string generation.

## API Summary

- `write-json!(path data [opts])` serializes `data` with `json.dumps` and writes it to `path`. By default it writes to `path .. ".tmp"` and renames the temporary file into place. Pass `{:atomic? false}` to write directly.
- `stable-json(value)` returns deterministic compact JSON text by sorting table keys lexicographically and preserving array order.

## Examples

```fennel
(local json-utils (require :json-utils))

(json-utils.write-json! "/tmp/space-settings.json"
                        {:theme "dark" :recent ["alpha" "beta"]})

(print (json-utils.stable-json {:b 2 :a 1}))
```

## Errors and Platform Notes

The module asserts that `fs` and `json` are available. Atomic writes use a sibling `.tmp` file and `fs.rename`; if the rename fails, `json-utils` attempts to remove the temporary file and raises an explicit error. `stable-json` sorts keys by their string representation, so mixed key types are deterministic but should still be chosen deliberately.

## Related Modules

- [`json`](/sdk/modules/json) for raw JSON parse and serialize operations.
- [`fs`](/sdk/modules/fs) for lower-level file operations and atomic replacement helpers.

## Aliases and Search Terms

Search terms: JSON utilities, stable JSON, deterministic JSON, atomic JSON write, write-json.
