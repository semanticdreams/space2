# Space Application Distribution Design

## Context

Space is both a C++ desktop runtime and, today, the home of the default Fennel
application loaded from `assets/lua/main.fnl`. The current release workflow
already produces useful Space distributions:

- Linux binary tarballs, Debian packages, RPM packages, and AppImages from
  `.github/workflows/build.yml` through `scripts/build-linux.sh` and
  `scripts/build-appimage.sh`.
- Windows ZIP and installer artifacts from `scripts/package-windows-runtime.sh`,
  `scripts/build-windows-installer.py`, and `scripts/windows-installer.iss`.
- Full and minimal Linux profiles, with the minimal profile preserving the
  existing CEF-free Space build variant.
- Stable public artifact names, recently standardized as
  `space-<os>-<arch>[-role][-minimal].<ext>`.

Runtime lookup is already suitable for Space-as-runtime development. Space builds
Lua and Fennel module paths from ordered asset roots: explicit
`SPACE_ASSETS_PATH` entries, `cwd/assets`, user data, executable-relative
assets, install-relative `share/space/assets`, bundle `Resources/assets`, and
finally `/usr/share/space/assets`. That means an external app can provide its own
asset root ahead of Space's runtime assets without changing C++ lookup behavior.

The release/distribution gap is packaging. Independent application repositories
should not compile Space or copy bespoke packaging workflows. They should pin a
released Space runtime and call a reusable workflow maintained by Space.

## Goals

- Add a reusable GitHub Actions workflow in Space for packaging independent
  Fennel desktop applications/games.
- Keep application repositories small, platform-neutral, and free of Space build
  steps.
- Reuse and generalize the existing packaging scripts instead of moving
  substantial package assembly logic into YAML.
- Preserve existing Space release functionality, artifact names, resource lookup,
  default launch behavior, and the minimal Space build variant.
- Support the same relevant distribution formats currently produced for Space:
  Linux `.tar.gz`, Debian package, RPM package, AppImage, Windows ZIP, and
  Windows installer.
- Use system-installed Space for app Debian/RPM packages, and bundle a pinned
  Space GitHub Release artifact for self-contained formats.
- Make the eventual extraction of the current `main` application straightforward,
  without creating the new repository in this task.

## Non-goals

- Renaming or reshaping existing Space release artifacts.
- Redesigning `AssetManager`, Lua/Fennel module search paths, or runtime resource
  lookup order.
- Removing `assets/lua/main.fnl` from Space in this task.
- Making downstream applications compile Space.
- Creating per-application bundle repositories.
- Adding macOS packaging, signing, package repository publishing, auto-update, or
  a compatibility/version-management layer beyond a pinned Space release tag.
- Duplicating packaging implementation in every application repository.

## Current architecture findings

### Space release flow

`.github/workflows/build.yml` is the current release workflow. On tags it builds
Linux full/minimal artifacts, smoke-tests tarballs and packages, resolves the
manifest from `scripts/build-linux.sh`, and uploads the listed artifacts to the
GitHub Release. Windows builds cross-compile `space.exe` and `space-cli.exe`,
stage `build/dist/windows`, create `space-windows-x86_64.zip`, then build and
upload `space-windows-x86_64-setup.exe` on a Windows runner.

`scripts/build-linux.sh` is already the authority for stable Linux artifact names
and the release manifest. It configures CMake, invokes CPack for DEB/RPM, creates
an install tree, writes a top-level `space` launcher for tarballs, delegates
AppImage assembly to `scripts/build-appimage.sh`, and copies generated artifacts
to the stable public names.

`scripts/build-appimage.sh` can package either a CMake install tree or raw build
outputs. Its generated `AppRun` currently sets `SPACE_ASSETS_PATH` to bundled
Space assets and executes `usr/bin/space`.

Windows packaging is runtime-directory based. `scripts/package-windows-runtime.sh`
copies both executables, DLLs, and `assets/` into `build/dist/windows`.
`scripts/build-windows-installer.py` is already partly parameterized, while
`scripts/windows-installer.iss` still has Space defaults such as a fixed AppId
and shortcuts that launch the app executable with no arguments.

### Runtime and launch assumptions

`apps/space/main.cpp` defaults to `-m main` when no entrypoint is provided, but it
also supports `-m module` and `-m module:function`. Existing Space desktop and
installer launchers rely on the no-argument default. Application packages should
not change that default; they should launch their app explicitly with
`space -m <entrypoint>`.

Linux Space packages install Space assets under `/usr/share/space/assets`.
`scripts/verify-linux-package-layout.sh` currently requires
`share/space/assets/lua/main.fnl`, which is correct while Space still ships the
default app. External app packaging should get a separate verifier instead of
weakening the Space verifier.

### Current `main` boundary

`assets/lua/main.fnl` is a large application composition root. It initializes the
engine, settings, app dirs, world manager, HUD/canvas/activity units, graph
extensions, workflows, wallet, agent/MCP integrations, tray/notifications, remote
control, and lifecycle hooks. It returns library exports for tests and tools, but
it only starts the full application loop when `app-config.run-main` is true.

Likely default-application-owned files include `assets/lua/main.fnl`, world and
activity composition modules, HUD/canvas units, built-in graph/drawing/board/
sandbox activity modules, workflow/LLM/MCP/wallet integrations, and default app
content assets. Likely Space-runtime-owned files include the C++ host/runtime,
Fennel loader/compiler support, generic utilities, generic UI/layout/rendering
widgets, generic state/input/focus/hot-reload primitives, fonts, icon metadata,
shaders, and other assets used by reusable runtime modules. Several domains need
file-by-file review before extraction because generic-looking modules currently
depend on global `app` services or default app conventions.

This task should document and exercise the external-app packaging path; it should
not attempt the full `main` extraction.

## Considered approaches

### Approach A: reusable workflow plus script-owned app packaging toolkit

Add a `workflow_call` workflow in Space. The workflow checks out the caller app,
checks out Space packaging scripts at the reusable workflow revision, downloads a
pinned Space release artifact, and invokes generalized scripts that assemble app
packages. Public workflow inputs stay small, and most policy lives in scripts and
tests.

Trade-offs: this adds a few packaging scripts and tests, but it best matches the
existing architecture, keeps YAML thin, keeps packaging behavior testable, and
lets apps release without compiling Space.

### Approach B: scripts only, with copied caller workflow snippets

Generalize scripts and document how every app repository should call them from a
custom workflow.

Trade-offs: this is initially smaller in Space, but it duplicates release logic
in app repositories and does not satisfy the goal of shared workflow ownership by
Space.

### Approach C: CMake/CPack product mode for each app

Teach the existing Space build to package branded app products directly.

Trade-offs: this would reuse CPack heavily but violates the constraint that app
repositories should not build Space. It also couples application releases to the
Space source tree and is a larger refactor than needed.

## Decision

Use Approach A: add a reusable workflow backed by small, testable packaging
scripts. The workflow interface should be convention-first and version the
workflow separately from the Space runtime release.

### Public reusable workflow inputs

Required inputs:

- `space-version`: Space GitHub Release tag to download, for example `v1.2.3`.
  This is the pinned runtime input for reproducible self-contained app releases.
- `app-name`: display name used for release metadata, desktop entries, and
  installer UI.

Optional inputs with defaults:

- `app-id`: package-safe application id. If omitted, packaging scripts derive a
  lowercase id from `app-name`.
- `entrypoint`: Space module or module function passed to `space -m`. Defaults to
  `main`.
- `assets-dir`: application asset root in the caller repository. Defaults to
  `assets`.
- `icon-path`: optional path to a PNG/ICO source icon in the app repository. If
  omitted, packages are still valid but may use generic/default icon behavior.
- `linux-profile`: `full` or `minimal` Space runtime artifact for
  self-contained Linux outputs. Defaults to `full`.
- `release-version`: application version. Defaults to the tag name that invoked
  the caller workflow, normalized by removing a leading `v` when package formats
  require it.

The workflow should not expose a large packaging API. It can add hidden/internal
defaults for repository name, architecture, output directory, and targets. If a
future application needs richer metadata, that can be added after the first
external app proves the need.

The workflow's own revision is selected by the caller's `uses:` ref, while
`space-version` selects the runtime release artifacts. Those concepts remain
separate.

## Application layout convention

The natural runtime convention is an app-owned asset root containing Fennel under
`lua/`, because Space derives module paths from asset roots. A minimal app should
look like this:

```text
mygame/
├── assets/
│   ├── lua/
│   │   └── main.fnl
│   └── pics/
│       └── mygame.png
└── .github/
    └── workflows/
        └── release.yml
```

`assets/lua/main.fnl` is only a convention. Apps may use a namespaced entrypoint,
such as `assets/lua/mygame/main.fnl` with workflow input
`entrypoint: mygame.main`, when they want to avoid module-name collisions.

During development against an installed Space, a developer can run from the app
repository root:

```bash
space -m main
```

or, for a namespaced entrypoint:

```bash
space -m mygame.main
```

Because `cwd/assets` is already an asset root, no extra environment variable is
needed for the conventional development layout. Developers can still use
`SPACE_ASSETS_PATH=/path/to/mygame/assets space -m main` when launching from a
different working directory or composing multiple asset roots.

## Packaging model

### Shared packaging metadata

Add a small packaging metadata normalizer/validator used by the reusable workflow
and app packaging scripts. It should resolve `app-name`, `app-id`, `entrypoint`,
`assets-dir`, optional icon, `release-version`, and `space-version`, fail loudly
on missing assets or invalid identifiers, and write a normalized JSON file for
downstream scripts. This keeps app repository requirements simple while keeping
script interfaces explicit and testable.

### Debian and RPM app packages

Application DEB/RPM packages should be app-only packages. They should not embed
Space. They should install:

```text
/usr/bin/<app-id>
/usr/share/<app-id>/assets/...
/usr/share/applications/<app-id>.desktop
/usr/share/icons/hicolor/.../apps/<app-id>.png   # when an icon is provided
```

The wrapper at `/usr/bin/<app-id>` should prepend the application asset root and
then execute system Space explicitly:

```sh
SPACE_ASSETS_PATH="/usr/share/<app-id>/assets${SPACE_ASSETS_PATH:+:$SPACE_ASSETS_PATH}" \
  exec /usr/bin/space -m <entrypoint> "$@"
```

Because `/usr/share/space/assets` is already a fallback root, app-only packages
do not need to copy Space runtime assets. The DEB should declare a dependency on
`space`, preferably constrained by the pinned Space package version when the tag
can be normalized safely. The RPM should declare `Requires: space` with the same
best-effort version constraint.

### Linux binary tarball

The reusable workflow should download the pinned Space Linux tarball from the
Space GitHub Release, extract it, preserve its contents, and add app-specific
assets and a top-level launcher:

```text
<app-id>
bin/space
share/space/assets/...
share/<app-id>/assets/...
```

The app launcher should set both app and Space asset roots, with app assets first,
then execute the bundled Space binary with `-m <entrypoint>`. The existing Space
launcher in the tarball should remain untouched for diagnostics and runtime reuse.

### AppImage

Generalize `scripts/build-appimage.sh` so it can still build Space AppImages with
current defaults, and can also assemble an app AppImage from a downloaded Space
runtime tree plus app metadata. The app `AppRun` should set
`SPACE_ASSETS_PATH` to include the app asset root before bundled Space assets,
set the existing library paths, and execute `usr/bin/space -m <entrypoint>`.

The implementation should preserve existing `space-linux-x86_64*.AppImage`
behavior and names for Space releases.

### Windows ZIP

The reusable workflow should download `space-windows-x86_64.zip` from the pinned
Space release, extract it, preserve `space.exe`, `space-cli.exe`, DLLs, and base
`assets/`, then add the application assets under the staged runtime's `assets/`
tree. This matches executable-sibling asset lookup on Windows.

The ZIP should include an app launcher command file such as `<app-id>.cmd` that
starts `space.exe -m <entrypoint>`. The Space executables should remain available
inside the archive.

### Windows installer

Generalize `scripts/build-windows-installer.py` and `scripts/windows-installer.iss`
so app packaging can pass explicit metadata instead of requiring CPack metadata.
For Space's own installer, current defaults should keep working.

Application installers should install the self-contained staged runtime and app
assets. Start Menu, desktop, and postinstall launch entries should target the
bundled `space.exe` with `-m <entrypoint>`. The installer AppId should be
app-specific and deterministic from `app-id` unless a future real app needs an
explicit override.

## Reusable caller workflow

A minimal app repository caller should be:

```yaml
name: Release

on:
  push:
    tags:
      - "v*"

permissions:
  contents: write

jobs:
  release:
    uses: semanticdreams/space2/.github/workflows/bundle.yml@v1
    with:
      space-version: v1.2.3
      app-name: MyGame
```

Apps with non-default layout can add only the inputs they need, for example
`entrypoint: mygame.main` or `assets-dir: game-assets`.

## Existing `main` extraction preparation

The current `main` app should eventually become an ordinary app repository that
uses the same reusable workflow. The extraction inventory should be documented in
the app-distribution developer docs during implementation:

- Move out: `assets/lua/main.fnl`, default app composition modules, activity/world
  composition, HUD/canvas units, app-specific graph/drawing/board/sandbox
  activities, workflows/LLM/MCP/wallet integrations that are not intended as
  platform APIs, and default application media/content after file-by-file review.
- Keep in Space: C++ runtime and bindings, Fennel loader/cache support, generic
  utilities, generic UI/layout/render primitives, generic runtime systems,
  shaders, fonts, icon metadata, and assets required by reusable modules.
- Revisit before moving: modules that look generic but depend on global `app`,
  default app settings, graph extension registries, or concrete owned-path hot
  reload assumptions.

Once extraction happens, the new `main` repository should follow the same layout
as any other app and should not receive special treatment from Space packaging.
At that point, Space's no-argument launcher behavior and package verifier may
need a separate design decision: either keep a minimal Space-owned `main` module
as a runtime/demo shell, or stop requiring `main` in runtime-only Space packages.
That decision is intentionally deferred because this task preserves existing
Space release behavior.

## Error handling

- Missing app assets, invalid app ids, invalid entrypoints, missing pinned Space
  release assets, or unsupported package targets should fail before packaging.
- Downloaded release artifacts must come from the requested `space-version`, not
  from latest workflow artifacts.
- Packaging scripts should validate expected outputs and write explicit manifests
  like the existing Space release script.
- App packagers get their own layout verifier; Space's existing verifier should
  remain strict for Space release artifacts.
- Self-contained launchers should fail loudly if the bundled Space executable is
  missing rather than silently falling back to system Space.

## Testing and validation

Focused validation should include:

- Unit tests for packaging metadata normalization and validation.
- Script tests for Linux app package roots, wrappers, desktop files, dependencies,
  and self-contained launcher layout.
- Python tests for Windows staging and installer metadata generation.
- Existing release artifact naming tests to ensure Space artifact names remain
  unchanged.
- A fixture app with `assets/lua/main.fnl` or a namespaced entrypoint that can be
  launched through `./build/space -m <entrypoint>`.

Because the implementation touches packaging and Fennel-facing app launch paths,
local validation should follow the project ladder: build first if `./build/space`
is stale, run Fennel compile checks for touched fixture `.fnl` files, run
constraints when Fennel files are added, run focused fixture-launch and packaging
script tests, then run broader validation justified by release/distribution risk.
Windows installer validation may only be fully practical in GitHub Actions; local
reports should clearly distinguish tested Linux/script behavior from Windows paths
that require CI.

## Acceptance criteria

- `.github/workflows/bundle.yml` exists and is callable from external app
  repositories with a small input set.
- The workflow downloads pinned Space GitHub Release artifacts and does not build
  Space for app releases.
- App DEB/RPM packages install app assets only and declare a Space package
  dependency.
- App tarball/AppImage/Windows ZIP/Windows installer bundle the selected Space
  release plus app assets and launch `space -m <entrypoint>`.
- Existing Space release workflow behavior, artifact names, runtime lookup, and
  minimal profile are preserved.
- Documentation shows the public workflow inputs, a complete minimal caller
  workflow, the expected app directory structure, developer run command, per-format
  assembly model, and the current `main` extraction inventory.
