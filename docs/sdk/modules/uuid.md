# uuid

## Canonical Import

```fennel
(local uuid (require :uuid))
```

## Source Files

- `src/lua_uuid.cpp`
- `src/lua_runtime.cpp`

## What It Provides

`uuid` generates UUID strings.

## API Summary

- `v4()` returns a randomly generated UUID version 4 string.

## Examples

```fennel
(local uuid (require :uuid))

(local id (uuid.v4))
(print id)
```

## Errors and Platform Notes

UUID generation uses Boost's random UUID generator. The returned value is a lowercase UUID string.

## Related Modules

- [`random`](/sdk/modules/random) for general random values.

## Aliases and Search Terms

Search terms: GUID, identifier, random id, UUID v4.
