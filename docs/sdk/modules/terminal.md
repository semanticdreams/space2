# terminal

## Canonical Import

```fennel
(local terminal (require :terminal))
```

## Source Files

- `src/lua_terminal.cpp`
- `src/lua_runtime.cpp`

## What It Provides

`terminal` exposes a virtual terminal object with screen cells, dirty regions, cursor state, pty interaction, scrollback, and update callbacks when the build includes terminal support.

## API Summary

- `Terminal(rows cols)` creates a terminal.
- Data types expose fields for `TerminalCell`, `TerminalRect`, `TerminalSize`, and `TerminalCursor`.
- Terminal methods include `get-row`, `get-cell`, `get-screen`, `get-dirty-regions`, `clear-dirty-regions`, `get-size`, `get-cursor`, `get-title`, `is-alt-screen`, `is-pty-available`, `is-scrollback-supported`, `get-id`, `get-scrollback-size`, `get-scrollback-line`, `send-text`, `send-key`, `send-mouse`, `resize`, `set-scrollback-limit`, `inject-output`, and `update`.
- Signal fields include `on-screen-updated`, `on-cursor-moved`, `on-title-changed`, and `on-bell`.

## Examples

```fennel
(local terminal (require :terminal))

(local term (terminal.Terminal 24 80))
(term:inject-output "hello\n")
(term:update)
(print (: (term:get-size) :rows))
```

## Errors and Platform Notes

The module is only bound when Space is built with terminal support. PTY and scrollback behavior depend on the terminal backend and platform.

## Related Modules

- [`process`](/sdk/modules/process) for subprocess management.
- [`shell`](/sdk/modules/shell) for Bash command execution.

## Aliases and Search Terms

Search terms: vterm, terminal emulator, pty, scrollback, cursor.
