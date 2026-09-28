# Getting Started with the Space SDK

## Choose a Starting Point

Start from an installed-runtime app repository when you want an application that depends on a local or packaged Space runtime. In that shape, the app repository provides its own assets and entrypoint, then launches the host with `space -m main`.

Start from a Space checkout when you want to inspect a working example next to the engine, shared assets, and developer tooling. The Snake example is the current copyable starting point for learning how an app is shaped without creating a new example from scratch.

## Run the Snake Example from a Space Checkout

```sh
make build
SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" ./build/space -m main
```

The asset path puts Snake assets first and shared Space assets second. That lets the Snake app resolve its own files before falling back to shared runtime assets from the checkout.

## Inspect the App Shape

Browse the [Snake example repository path](https://github.com/semanticdreams/space2/tree/main/examples/snake) to see how a small app is organized:

- `assets/lua/main.fnl` is the app entrypoint loaded by `space -m main`.
- `assets/lua/snake/app.fnl` wires the app-level lifecycle and runtime-facing setup.
- `assets/lua/snake/game.fnl` holds the game state and rules.
- `assets/lua/snake/view.fnl` translates game state into UI-facing presentation.
- `assets/lua/snake/scene-view.fnl` connects the game to scene rendering.
- `.github/workflows/release.yml` shows how the example is packaged for release.

## Where to Go Next

- [SDK Concepts](/sdk/concepts) — learn the vocabulary used by app, host, capability, and package docs.
- [Your First Space App](/sdk/tutorials/your-first-space-app) — build a first app when tutorials are available.
- [App Layout Guide](/sdk/guides/app-layout) — understand app repository structure when guides are available.
- [App Module Contract](/sdk/reference/app-module-contract) — look up the entrypoint contract when reference pages are available.
- [Examples](/sdk/examples/) — compare existing examples and starting points.

## If Something Fails

Missing required capabilities, invalid entrypoints, missing assets, and malformed commands should fail loudly rather than silently doing nothing. For build and runtime setup details, see [Building](/dev/building). For live inspection and debugging tools, see [Remote Control](/dev/remote-control).
