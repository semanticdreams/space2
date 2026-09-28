# App Module Contract

A Space app module exports metadata plus entry points that let a host create and run the app without giving the app ownership of the engine lifecycle.

```fennel
{:metadata {:id "examples.snake" :title "Snake" :host-api 1}
 :create create
 :main main}
```

## Fields

- `:metadata` identifies the app and the host API level it expects. Hosts use this data for discovery, presentation, validation, and compatibility checks.
- `:create` points at `create(host)`, the factory a host calls to build the app runtime.
- `:main` is the standalone entry point used when the app is launched directly instead of embedded by another host.

## `create(host)`

`create(host)` receives the host interface and requests the capabilities the app needs. The returned value is the app's runtime composition: presentation facets, lifecycle hooks, scheduler work, inspectors, commands, and other host-visible pieces the host can mount.

Apps should build against host capabilities rather than assuming they own windows, render loops, input routing, or shutdown. The host owns the engine lifecycle directly; an app contributes runtime behavior that the host activates and later tears down.

If an app requires a host capability and that capability is missing, creation should fail loudly at the boundary instead of silently disabling behavior.

See [Hostable Runtime Apps](/sdk/guides/hostable-runtime-apps) for usage guidance and [Hosted Runtime Apps](/dev/features/hosted-runtime-apps) for maintainer-facing internals.
