# Your First Space App

Goal: run and inspect a small app without learning maintainer internals first.

This tutorial uses the [Snake example](https://github.com/semanticdreams/space2/tree/main/examples/snake) as the smallest current app-shaped starting point.

## Run the Example

From a Space checkout, build the runtime and launch Snake with its assets before the shared Space assets:

```sh
make build
SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" ./build/space -m main
```

The first asset root supplies the app. The second asset root supplies shared runtime assets that the host still needs.

## Inspect the App Shape

Open the Snake example and trace these files first:

- `assets/lua/main.fnl` is the default entrypoint loaded by `space -m main`.
- `assets/lua/snake/app.fnl` is the hostable module that connects the app to the Space host.
- `assets/lua/snake/game.fnl` is pure app-owned logic for state and rules.

Keep app-owned logic separate from host-facing setup where possible. That separation makes it easier to test state changes, replace presentation, and understand which parts depend on host capabilities.

## Next Steps

- [App Layout Guide](/sdk/guides/app-layout) — understand the expected repository and asset layout.
- [App Module Contract](/sdk/reference/app-module-contract) — look up the current entrypoint and hostable-module contract.
- [Examples](/sdk/examples/) — compare curated starting points.
