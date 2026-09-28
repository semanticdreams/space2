# App Layout

A Space app repository should make its entrypoint, app-owned modules, assets, tests, and release workflow easy to find. A small app can start with this layout:

```text
mygame/
├── assets/
│   └── lua/
│       ├── main.fnl
│       └── mygame/
│           └── app.fnl
└── .github/
    └── workflows/
        └── release.yml
```

`assets/lua/main.fnl` is the app entrypoint the runtime loads. Keep it thin: resolve app modules, pass the host into the app module contract, and surface startup failures instead of hiding them.

Place app code in namespaced modules such as `assets/lua/mygame/app.fnl`. Namespacing keeps builder-owned modules separate from host modules and makes it clear which code belongs to the package.

Keep app assets near the app package. Scripts, textures, sounds, fixtures, and metadata should be arranged so the host can resolve them predictably when the package is run or distributed.

Add focused tests for app-owned behavior before broad runtime checks. Tests should cover the inputs your app requires, expected failure cases for missing capabilities, and the commands or lifecycle hooks your package exposes.

Use `.github/workflows/release.yml` for the release workflow that builds and publishes the app package. Keep packaging inputs explicit so missing metadata, assets, or workflow credentials fail loudly.

See [App Module Contract](/sdk/reference/app-module-contract), [Packaging Workflow](/sdk/reference/packaging-workflow), and [App Distribution](/dev/features/app-distribution) for the current contracts and maintainer details.
