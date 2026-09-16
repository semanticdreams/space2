# Fennel Runtime Paths

Space's embedded runtime owns the default Fennel asset search path. Normal app launch must not rely on shell wrappers setting `FENNEL_PATH` or `FENNEL_MACRO_PATH` for modules under `assets/lua`.

The canonical runtime path order is:

```text
assets/lua/?.fnl;assets/lua/?/init.fnl
```

Flat files intentionally take precedence over directory `init.fnl` modules.

`LuaRuntime` applies this path to both `fennel.path` and `fennel["macro-path"]` before loading app modules. The runtime also exposes the same value as `runtime.fennel-path` for child processes and user-code tooling that need to extend the project path.

Direct test and tool commands may still set `FENNEL_PATH` and `FENNEL_MACRO_PATH` explicitly, especially when running outside the normal executable startup path. Those environment variables are conveniences for direct invocation, not requirements for normal embedded app launch.
