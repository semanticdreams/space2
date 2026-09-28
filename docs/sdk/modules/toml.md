# toml

## Canonical Import

```fennel
(local toml (require :toml))
```

## Source Files

- `src/lua_toml.cpp`

## What It Provides

`toml` converts between TOML text and Lua/Fennel tables using the native `toml++` binding.

## API Summary

- `loads(toml-string)` parses TOML text into Lua tables. TOML tables become string-keyed tables; arrays become 1-indexed array tables; strings, integers, floats, and booleans become native Lua values.
- `dumps(table)` serializes a Lua table into TOML text. The root value must be a table. String-keyed tables become TOML tables; contiguous numeric array tables become TOML arrays.

## Examples

```fennel
(local toml (require :toml))

(local config (toml.loads "title = \"Space\"\n[window]\nwidth = 1280\n"))
(set config.window.height 720)

(print (toml.dumps config))
```

## Errors and Platform Notes

Parse failures raise errors from `toml++`. `dumps` raises if the root value is not a table, if object keys are not strings, if arrays are not contiguous numeric sequences starting at 1, or if a TOML value is unsupported. TOML date, time, and date-time values are currently rejected when parsing, and Lua `nil` cannot be emitted as a TOML value.

## Related Modules

- [`fs`](/sdk/modules/fs) for reading and writing TOML files.
- [`json`](/sdk/modules/json) for JSON data exchange.

## Aliases and Search Terms

Search terms: TOML, toml++, configuration, config file, loads, dumps.
