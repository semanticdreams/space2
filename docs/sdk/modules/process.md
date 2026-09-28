# process

## Canonical Import

```fennel
(local process (require :process))
```

## Source Files

- `src/lua_process.cpp`
- `src/lua_process_windows.cpp`
- `src/lua_runtime.cpp`

## What It Provides

`process` runs and manages subprocesses with captured stdout/stderr, environment overrides, stdin, timeouts, polling, callbacks, and platform-specific process termination.

## API Summary

- `run(opts)` executes synchronously. `opts.args` is a non-empty string array. Optional keys include `cwd`, `env`, `clear-env`, `timeout`, `stdin`, and `merge-stderr`.
- `spawn(opts [callback])` starts asynchronously and returns an id.
- `write(id data)`, `close-stdin(id)`, `kill(id [signal])`, `running(id)`, `read(id)`, `poll([max-results])`, and `wait(id)` manage spawned processes.
- Result tables include `exit-code`, `signal`, `timed-out`, `stdout`, `stderr`, and `duration-ms`; `poll` also includes `id`.

## Examples

```fennel
(local process (require :process))

(local result (process.run {:args ["printf" "hello"] :timeout 2}))
(print result.exit-code result.stdout)
```

## Errors and Platform Notes

Invalid opts raise errors. Unix builds use process groups and POSIX signals; Windows builds use `CreateProcessW` and termination ignores the optional signal value. Missing executables generally produce exit code 127-style results or exec failure text.

## Related Modules

- [`shell`](/sdk/modules/shell) for Bash command strings on supported platforms.
- [`callbacks`](/sdk/modules/callbacks) for async completion callbacks.

## Aliases and Search Terms

Search terms: subprocess, command execution, spawn, exec, stdout, stderr.
