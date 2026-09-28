# json

## Canonical Import

```fennel
(local json (require :json))
```

## Source Files

- `src/lua_json.cpp`

## What It Provides

`json` converts between JSON text and Lua/Fennel values using the native `nlohmann::json` binding.

## API Summary

- `loads(json-string)` parses JSON text into Lua values. JSON objects become tables with string keys; arrays become 1-indexed array tables; strings, booleans, and numbers become native Lua values; JSON `null` becomes `nil`.
- `dumps(value)` serializes a Lua value to compact JSON text. Array-like tables with contiguous integer keys starting at 1 become JSON arrays; other tables become JSON objects.

## Examples

```fennel
(local json (require :json))

(local payload (json.loads "{\"name\":\"Space\",\"tags\":[\"sdk\",\"docs\"]}"))
(table.insert payload.tags "json")

(print (json.dumps payload))
```

## Errors and Platform Notes

`loads` raises a Lua error prefixed with `json.loads parse error` when parsing fails. `dumps` follows the binding's Lua table conversion rules; object keys must be string-compatible, array keys must be contiguous integer positions, and unsupported Lua values are serialized as JSON `null`.

## Related Modules

- [`json-utils`](/sdk/modules/json-utils) for atomic JSON file writes and stable JSON text.
- [`fs`](/sdk/modules/fs) for reading and writing JSON files yourself.

## Aliases and Search Terms

Search terms: JSON, parse JSON, encode JSON, decode JSON, loads, dumps, nlohmann json.
