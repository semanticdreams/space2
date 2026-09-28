# dial-type

## Canonical Import

```fennel
(local dial-type (require :dial-type))
```

## Source Files

- `src/lua_dial_type.cpp`
- `src/lua_runtime.cpp`

## What It Provides

`dial-type` interprets paired stick/dial input into pending left/right integer sequences and can integrate with `input-state` gamepad data.

## API Summary

- `DialType()` creates a low-level dial interpreter with methods `update`, `poll`, `has-input`, `dump`, and `reset`.
- `InputDialType(input-state)` creates an input-backed interpreter with `update`, `update-primary`, `update-gamepad`, `has-input`, `has-input-for`, `poll-primary`, `poll-gamepad`, `gamepad-ids`, and `reset`.
- `poll` methods return `nil` or a two-element table of left and right integer arrays.
- `dump()` returns stick state, `has-input`, and optional pending input.

## Examples

```fennel
(local dial-type (require :dial-type))

(local dial (dial-type.DialType))
(dial:update 0.0 1.0 1.0 0.0)
(local pending (dial:poll))
(when pending
  (print "left count" (length (. pending 1))))
```

## Errors and Platform Notes

`InputDialType` expects an `InputState` userdata from `input-state`. Returned pending values are low-level integer arrays whose meaning is defined by the dial-type native implementation.

## Related Modules

- [`input-state`](/sdk/modules/input-state) for input-backed dial interpretation.
- [`engine`](/sdk/modules/engine) for host input events.

## Aliases and Search Terms

Search terms: dial input, chorded input, gamepad sticks, input typing.
