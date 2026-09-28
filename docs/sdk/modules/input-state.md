# input-state

## Canonical Import

```fennel
(local input-state (require :input-state))
```

## Source Files

- `src/lua_input_state.cpp`
- `src/lua_runtime.cpp`

## What It Provides

`input-state` exposes keyboard, mouse, gamepad, touch, and pen state objects plus constants for key, pen axis, and pen input flags.

## API Summary

- Constants: `KeyStatus`, `PenAxis`, and `PenInputFlags`.
- `InputState()` creates an input state object.
- Keyboard, mouse, gamepad, touch, and pen state types expose state predicates such as `is-up`, `is-free`, `is-just-pressed`, `is-down`, `is-held`, and `is-just-released` plus device-specific fields.
- `InputState` methods and properties include `keyboard`, `mouse`, `gamepad-count`, `primary-gamepad-id`, `touch-count`, `pen-count`, `begin-frame`, event ingestion methods, `gamepad-by-id`, `gamepad-ids`, `gamepads`, `touch-by-id`, `touch-ids`, `touches`, `pen-by-id`, `pen-ids`, `pens`, `pen-events`, and `pen-axis-values`.

## Examples

```fennel
(local input-state (require :input-state))

(local input (input-state.InputState))
(input:begin-frame)
(local mouse input.mouse)
(print (mouse:x) (mouse:y))
```

## Errors and Platform Notes

Input state reflects SDL-backed events supplied by the host; a newly created state has no live input until event methods are driven. Device ids and pen axes depend on available hardware and platform support.

## Related Modules

- [`dial-type`](/sdk/modules/dial-type) for chorded gamepad/input interpretation.
- [`engine`](/sdk/modules/engine) for the runtime that usually owns input event flow.

## Aliases and Search Terms

Search terms: keyboard, mouse, gamepad, touch, pen, SDL input.
