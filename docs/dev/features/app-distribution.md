# App Distribution

Space provides an additive packaging path for independent Fennel desktop apps. App repositories call the reusable Space bundle workflow, identify a pinned Space release, and upload app artifacts that either depend on a system `space` package or bundle the downloaded Space release. App repositories do not compile Space as part of this path.

This feature does not change runtime resource lookup or the default `space -m main` launch behavior.

## Reusable workflow inputs

Required inputs:

- `space-version`: the pinned Space GitHub Release tag to download, such as `v1.2.3`.
- `app-name`: the human-readable application name used for package metadata.

Optional inputs:

- `app-id`: package-safe lowercase app id. When omitted, packaging derives it from `app-name`.
- `entrypoint`: Space module or `module:function` entrypoint. Defaults to `main`.
- `assets-dir`: app assets directory relative to the caller repository. Defaults to `assets`.
- `icon-path`: optional app icon path relative to the caller repository.
- `linux-profile`: Space Linux release profile to bundle, either `full` or `minimal`. Defaults to `full`.
- `release-version`: app release version. When omitted, the workflow derives it from the caller tag/ref.

App repositories do not need and must not add a required root-level `space-app.json`; the workflow inputs are the public app packaging interface.

## Minimal caller workflow

An external app repository can publish app artifacts from tags with only the required inputs:

```yaml
name: Release

on:
  push:
    tags: "v*"

permissions:
  contents: write

jobs:
  bundle:
    uses: semanticdreams/space2/.github/workflows/bundle.yml@v1
    with:
      space-version: v1.2.3
      app-name: My Game
```

The reusable workflow checks out the caller app, checks out the Space packaging scripts at the workflow ref, normalizes the inputs into internal metadata, downloads Space release artifacts from `space-version`, and uploads the generated app artifacts to the caller repository release.

## Expected app directory

A small app can keep its Fennel code and media under one assets tree:

```text
mygame/
├── assets/
│   ├── lua/
│   │   └── main.fnl
│   ├── images/
│   │   └── player.png
│   └── audio/
│       └── theme.ogg
└── .github/
    └── workflows/
        └── release.yml
```

With this layout, the default `entrypoint: main` resolves `assets/lua/main.fnl`. Apps that want namespaced modules can use a layout such as `assets/lua/mygame/main.fnl` and set `entrypoint: mygame.main`.

## Copyable example template

See `examples/snake/` for a small independent Snake app template that can be copied into a new repository. It demonstrates the expected `assets/lua/main.fnl` default entrypoint, a focused Fennel logic test under the app assets tree, and the small caller workflow needed to invoke Space's reusable bundle workflow.

## Developer run commands

From an app repository whose working directory exposes `assets/` as the app assets root:

```sh
space -m main
```

For a namespaced module:

```sh
space -m mygame.main
```

When launching outside the app repository root, point Space at the app assets explicitly:

```sh
SPACE_ASSETS_PATH=/path/to/mygame/assets space -m main
```

No runtime lookup redesign is part of app distribution. These commands use the existing Space module and asset lookup behavior.

## Per-format assembly

- **DEB/RPM:** app-only packages. They install app assets under `/usr/share/<app-id>/assets`, install a wrapper in `/usr/bin/<app-id>`, launch the system `/usr/bin/space -m <entrypoint>`, and declare a dependency on the `space` package.
- **Tarball:** self-contained package based on the downloaded Space Linux tarball. The Space tarball contents are preserved, app assets are added under `share/<app-id>/assets`, and the app launcher prepends app assets before running the bundled `bin/space -m <entrypoint>`.
- **AppImage:** self-contained package that stages the downloaded Space runtime, adds app assets, and writes an `AppRun` that executes `space -m <entrypoint>`.
- **Windows ZIP:** self-contained package based on the downloaded `space-windows-x86_64.zip`. App assets are added to the staged runtime, and `<app-id>.cmd` launches `space.exe -m <entrypoint>`.
- **Windows installer:** uses the same staged runtime as the Windows ZIP. Installer metadata, shortcuts, and post-install launch behavior run `space.exe -m <entrypoint>`.

Linux tarball and AppImage names keep the selected profile suffix, so `linux-profile: minimal` produces minimal self-contained app artifacts. DEB/RPM app packages remain app-only and depend on the system `space` package instead of bundling Space.

## Future `main` extraction inventory

The current default Space app remains in this repository. A future extraction should happen only after file-by-file review.

Move out of Space into a downstream default app repository:

- `assets/lua/main.fnl`.
- Default app composition modules.
- Activity and world composition.
- HUD and canvas units.
- App-specific graph, drawing, board, and sandbox activities.
- Workflows, LLM, MCP, and wallet integrations that are not intended as platform APIs.
- Default application media and content after file-by-file review.

Keep in Space:

- C++ runtime and bindings.
- Fennel loader and cache support.
- Generic utilities.
- Generic UI, layout, and render primitives.
- Generic runtime systems.
- Shaders, fonts, icon metadata, and assets required by reusable modules.

Revisit before moving:

- Modules that look generic but depend on global `app` state.
- Modules that assume default app settings.
- Graph extension registries.
- Concrete owned-path hot reload assumptions.

The decision about preserving a minimal Space-owned `main` after extraction is deferred.
