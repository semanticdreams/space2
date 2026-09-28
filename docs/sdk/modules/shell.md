# shell

## Canonical Import

```fennel
(local shell (require :shell))
```

## Source Files

- `src/lua_shell.cpp`
- `src/lua_shell_windows.cpp`
- `src/lua_runtime.cpp`

## What It Provides

`shell` runs bounded Bash command strings and returns captured output and timing information.

## API Summary

- `bash(command timeout)` runs `bash -lc command` with a positive timeout in seconds.
- `bash({:command ... :timeout ... [:cwd ...]})` also supports a working directory.
- The result table includes `command`, `timeout`, `cwd`, `exit_code`, `signal`, `timed_out`, `stdout`, `stderr`, and `duration_ms`.

## Examples

```fennel
(local shell (require :shell))

(local out (shell.bash {:command "printf docs" :timeout 2}))
(print out.exit_code out.stdout)
```

## Errors and Platform Notes

`command` must be a non-empty string and `timeout` must be greater than zero. Windows builds expose the module but `bash` raises `shell.bash is not supported on Windows builds`.

## Related Modules

- [`process`](/sdk/modules/process) for argument-vector subprocess execution.
- [`cli-args`](/sdk/modules/cli-args) for parsing CLI arguments in tools.

## Aliases and Search Terms

Search terms: bash, command shell, shell command, terminal command.
