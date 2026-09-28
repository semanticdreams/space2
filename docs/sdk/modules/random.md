# random

## Canonical Import

```fennel
(local random (require :random))
```

## Source Files

- `src/lua_random.cpp`
- `src/lua_runtime.cpp`

## What It Provides

`random` provides thread-local pseudo-random numbers, bytes, sequence selection, shuffling, and sampling.

## API Summary

- `seed([seed])` seeds from a number or platform entropy.
- Integers and floats: `randint(a b)`, `randrange(stop)`, `randrange(start stop)`, `randrange(start stop step)`, `random()`, and `uniform(a b)`.
- Bytes: `randbytes(n)` and `randbytes-hex(n)`.
- Sequences: `choice(seq)`, `shuffle(seq)`, and `sample(seq k)`.

## Examples

```fennel
(local random (require :random))

(random.seed 42)
(print (random.randint 1 6))
(print (random.choice ["red" "green" "blue"]))
```

## Errors and Platform Notes

Invalid ranges, non-integer `randrange` args, negative byte counts, empty choices, or oversize samples raise Lua errors. This is general-purpose randomness, not a documented cryptographic API.

## Related Modules

- [`uuid`](/sdk/modules/uuid) for UUID v4 identifiers.

## Aliases and Search Terms

Search terms: RNG, random bytes, sampling, shuffle, dice.
