# Runtime Asset Overlay Search Order

## Context

Space is intended to operate as a reusable runtime: the `space` executable can be
launched from a project directory and run that project's app content. The current
asset discovery order favors executable-relative assets before the current
working directory's `assets/` tree. That is useful for packaged binaries, but it
makes the executable behave more like a self-contained app than a runtime that
loads the project in front of it.

The earlier runtime asset discovery design established executable-relative
fallbacks so direct binary execution works from arbitrary working directories.
This design keeps those packaged fallbacks, but changes the overlay semantics so
project assets can intentionally shadow every built-in Space asset.

## Goals

- Make `space -m main` launched from a project directory resolve
  `cwd/assets/lua/main.fnl` by default.
- Treat project assets as an overlay that may override any built-in runtime
  asset, including Lua/Fennel modules, icons, fonts, images, and defaults.
- Keep executable-relative and system asset roots as fallbacks so packaged and
  portable runtimes still work when no project override exists.
- Keep `SPACE_ASSETS_PATH` as the explicit highest-priority override and allow
  it to compose multiple ordered asset roots.
- Preserve loud failures with useful searched-path diagnostics when required
  assets are missing.

## Non-Goals

- Introducing a separate API for "runtime assets" versus "project assets".
  Overlay order is the contract: earlier roots shadow later roots.
- Using raw `cwd` as an asset root by default. The default project asset root is
  `cwd/assets` so repository metadata, docs, scripts, and build outputs do not
  become part of the runtime asset namespace.
- Renaming the environment variable to `SPACE_PATH`. `SPACE_ASSETS_PATH` remains
  preferred because it clearly describes ordered asset roots rather than an
  executable path, project root, module path, or generic configuration path.
- Making missing assets recoverable no-ops.

## Considered Approaches

### Keep executable-relative assets before CWD

This favors packaged-app stability: the binary loads assets shipped beside it
regardless of where it is launched. It is less suitable for a reusable runtime
because a project launched from its directory cannot override built-ins without
setting `SPACE_ASSETS_PATH`.

### Use raw CWD as the project asset root

This makes the whole project directory visible to asset lookup, so paths such as
`lua/main.fnl` could live at the repository root. It is simple but too broad: it
conflates source-control/project files with runtime-visible assets and increases
the chance of accidental path collisions.

### Use an explicit/project overlay before runtime fallbacks

This is the recommended approach. Asset lookup first honors explicit roots from
`SPACE_ASSETS_PATH`, then the conventional project root `cwd/assets`, then
falls back to user data and packaged runtime roots. It supports reusable-runtime
development while preserving direct packaged execution.

## Design

`AssetManager::getAssetPath(relativePath)` continues to resolve only relative
asset paths under candidate roots. Candidate roots are ordered overlays: the
first root containing the requested path wins, and later roots provide defaults.

The intended search order is:

1. Each non-empty entry in `SPACE_ASSETS_PATH`, in order.
2. Project assets: `<cwd>/assets`.
3. User data assets: `get_user_data_dir("space") / "assets"`.
4. Executable sibling assets: `<exe_dir>/assets`.
5. Install or portable layout: `<exe_dir>/../share/space/assets`.
6. Bundle layout: `<exe_dir>/../Resources/assets`.
7. System fallback: `/usr/share/space/assets`.

`SPACE_ASSETS_PATH` entries are asset roots, not project roots. For example:

```bash
SPACE_ASSETS_PATH=/game/assets:/shared/ui-assets:/mods/theme/assets
```

On Unix-like platforms, entries are colon-separated, matching `PATH`. If Windows
support is added or active for this code path, entries should be separated with
the platform path-list separator rather than hardcoding Unix syntax.

The default project layout remains:

```text
project/
  assets/
    lua/main.fnl
    pics/...
    fonts/...
```

Because project and explicit roots are searched before packaged roots, projects
may override everything shipped with Space by mirroring the built-in asset path
under `assets/` or under an earlier `SPACE_ASSETS_PATH` entry.

Equivalent candidate roots should still be deduplicated before probing to avoid
repeated filesystem checks and noisy diagnostics. Absolute requested asset paths
remain invalid. When no candidate contains the requested path, the thrown error
must include the requested relative path and the candidate paths that were
searched.

## Expected Behavior

- From a project directory, `space -m main` loads `./assets/lua/main.fnl` before
  any `main` module shipped with the executable.
- A project can override built-in runtime modules, icons, fonts, and default
  media by placing matching paths under `./assets`.
- `SPACE_ASSETS_PATH=/game/assets:/shared/assets space -m main` searches
  `/game/assets` first, then `/shared/assets`, then the default `cwd/assets` and
  runtime fallbacks.
- A packaged or portable runtime launched outside a project directory can still
  find executable-relative or system assets.
- Missing required assets fail loudly and report all searched candidates.

## Testing

Focused validation should cover:

- `AssetManager` unit tests for the revised order, especially `cwd/assets`
  winning over executable-relative roots.
- Multi-entry `SPACE_ASSETS_PATH` parsing and precedence.
- Deduplication when an environment entry, CWD assets, or executable-relative
  root resolves to the same directory.
- Rejection of absolute requested asset paths and path traversal attempts that
  escape a candidate root.
- A runtime smoke test showing `space -m main` can load `cwd/assets/lua/main.fnl`
  without setting `SPACE_ASSETS_PATH`.

Full runtime validation should be considered because asset search order affects
Lua/Fennel startup and every runtime asset lookup.
