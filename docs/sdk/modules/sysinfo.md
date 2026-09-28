# sysinfo

## Canonical Import

```fennel
(local sysinfo (require :sysinfo))
```

## Source Files

- `src/lua_sysinfo.cpp`
- `src/lua_runtime.cpp`

## What It Provides

`sysinfo` reports platform information, wall-clock timing helpers, system CPU and memory usage, and process information.

## API Summary

- `platform()` returns `os`, `arch`, optional `lua`, and `features`.
- `system()` returns a system handle.
- `sleep(seconds)` sleeps the current thread for positive durations.
- `now-ms()` returns steady-clock milliseconds.
- System methods include `refresh`, `cpu-usage`, `cpu-times`, `mem-virtual`, `process-current`, `process(pid)`, and `process-list([opts])`.
- Process methods include `pid`, `exists`, `name`, `refresh`, `cpu`, `cpu-times`, and `mem`.

## Examples

```fennel
(local sysinfo (require :sysinfo))

(local system (sysinfo.system))
(system:refresh)
(sysinfo.sleep 0.05)
(local cpu (system:cpu-usage))
(print (sysinfo.platform).os cpu.percent)
```

## Errors and Platform Notes

Many metric methods return empty or warmup tables when OS data is unavailable or a baseline is not ready. Process and per-core capabilities vary by Linux, Windows, and macOS and are advertised through `platform().features`.

## Related Modules

- [`process`](/sdk/modules/process) for launching and controlling processes.
- [`runtime`](/sdk/modules/runtime) for runtime environment paths.

## Aliases and Search Terms

Search terms: system info, CPU, memory, process list, platform, sleep, time.
