# Snake Space App Template

This example is a copyable independent Space/Fennel app template. It demonstrates the app-distribution repository layout, a default `main` entrypoint, pure game logic with a focused Fennel test, and the small release workflow a downstream app repository can call.

The runtime display is intentionally terminal/text based. That keeps the example independent from Space's default app rendering, HUD, graph, LLM, wallet, and other default-app modules.

## Directory layout

```text
snake/
├── assets/
│   └── lua/
│       ├── main.fnl
│       ├── snake/
│       │   ├── app.fnl
│       │   └── game.fnl
│       └── tests/
│           └── test-snake-game.fnl
└── .github/
    └── workflows/
        └── release.yml
```

`assets/lua/main.fnl` is the default `entrypoint: main` bridge. `snake/game.fnl` is pure Snake logic; `snake/app.fnl` owns the Space engine runtime glue.

## Local development

From a copied app repository root where `assets/` is the app assets directory:

```sh
space -m main
```

From the Space repository root:

```sh
SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" ./build/space -m main
```

Run the focused Snake logic test from the Space repository root:

```sh
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/examples/snake/assets:$(pwd)/assets ./build/space -m tests.test-snake-game:main
```

## Copying into a new app repository

1. Copy the contents of `examples/snake/` into a new repository.
2. Preserve the `assets/` tree so `assets/lua/main.fnl` remains the default entrypoint.
3. Preserve `.github/workflows/release.yml` if the repository should publish Space app bundles from tags.
4. Update names, ids, game code, and release pins for your app.

## Publishing releases

The included workflow is illustrative:

```yaml
jobs:
  bundle:
    uses: semanticdreams/space2/.github/workflows/bundle.yml@v1
    with:
      space-version: v1.2.3
      app-name: Snake
      app-id: snake
```

In a copied repository, deliberately pin both the reusable workflow ref (`@v1`) and `space-version` (`v1.2.3`) to the Space release you want to package against.
