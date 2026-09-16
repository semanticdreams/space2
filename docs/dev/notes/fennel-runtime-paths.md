# Fennel Runtime Paths

Space's embedded runtime owns the default Fennel asset search path. Normal app launch must not rely on shell wrappers setting `FENNEL_PATH` or `FENNEL_MACRO_PATH` for modules under `assets/lua`.

The canonical runtime path pattern for each asset root is:

```text
<asset-root>/lua/?.fnl;<asset-root>/lua/?/init.fnl
```

Asset roots are ordered by the runtime asset overlay search order. Flat files intentionally take precedence over directory `init.fnl` modules within each root, and earlier roots shadow later roots. See [Runtime Asset Overlays](./runtime-asset-overlays) for the full root order.

`LuaRuntime` applies this path to both `fennel.path` and `fennel["macro-path"]` before loading app modules. The runtime also exposes the same value as `runtime.fennel-path` for child processes and user-code tooling that need to extend the project path.

Direct test and tool commands may still set `FENNEL_PATH` and `FENNEL_MACRO_PATH` explicitly, especially when running outside the normal executable startup path. Those environment variables are conveniences for direct invocation, not requirements for normal embedded app launch.
