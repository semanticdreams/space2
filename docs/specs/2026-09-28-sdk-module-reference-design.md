# SDK Module Reference Design

## Summary

Re-center `docs/sdk/` around comprehensive per-module reference documentation for the libraries and modules provided by the Space ecosystem. The SDK section should primarily answer: “What modules are available, how do I import them, what functions/types do they expose, what errors or platform constraints should I expect, and what does real usage look like?”

The existing SDK tutorials, guides, examples, and app/host contract reference remain useful, but they should become secondary learning and workflow material. The primary SDK entry point should lead to a module catalog at `docs/sdk/modules/`.

## Problem

The first SDK docs pass focused too much on app-building onboarding and host/app contracts. That misses the user's main need: a lookup reference for the ecosystem's reusable modules, including modules such as `appdirs`, `temporal`, `engine`, `audio`, `wallet`, `json`, `sqlite`, `tree-sitter`, `http`, `zmq`, `logging`, `toml`, `cli-args`, and the rest of the runtime/library surface.

The corrected SDK design must make module reference the center of gravity.

## Goals

- Provide complete per-module reference pages for Space ecosystem modules.
- Include practical code examples on every module page.
- Use canonical import names and document aliases/search terms separately.
- Group modules into understandable categories without making URLs depend on categories.
- Preserve existing SDK tutorials/guides/examples/app-contract pages as secondary content.
- Link to developer docs for implementation details, but keep SDK module pages consumer-facing.
- Avoid inventing APIs, compatibility aliases, or stability guarantees.

## Non-Goals

- No runtime, C++, Fennel, Lua, binding, or packaging behavior changes.
- No new module aliases or compatibility shims.
- No formal SDK stability/versioning policy.
- No invented XML reference page unless a canonical XML module/source is identified.
- No movement or deletion of existing `docs/dev/**` content.

## Information Architecture Options

### Option A: Flat Canonical Module Pages Under `docs/sdk/modules/`

```text
docs/sdk/modules/
├── index.md
├── aliases.md
├── appdirs.md
├── engine.md
├── temporal.md
├── json.md
├── http.md
└── ...
```

The index and sidebar group modules by category, but every module page lives at a stable flat URL.

**Pros:** Stable URLs, simple lookup, easy alias handling, easier to reorganize categories later.  
**Cons:** A large directory with many files.

### Option B: Category Folders

```text
docs/sdk/modules/runtime/appdirs.md
docs/sdk/modules/data/json.md
docs/sdk/modules/networking/http.md
```

**Pros:** Directory structure mirrors conceptual grouping.  
**Cons:** URLs churn when categories change; many modules cross category boundaries.

### Option C: Family Pages With Anchors

```text
docs/sdk/modules/runtime.md#appdirs
docs/sdk/modules/data.md#json
docs/sdk/modules/networking.md#http
```

**Pros:** Fewer pages to create.  
**Cons:** Worse lookup, harder deep-linking, examples become crowded, and per-module review is weaker.

## Recommended Design

Use **Option A**: flat canonical pages under `docs/sdk/modules/`, grouped by category in `docs/sdk/modules/index.md` and the VitePress sidebar.

This provides stable per-module URLs while allowing categories to evolve. It also keeps aliases honest: user-facing search terms such as “physics,” “graphics,” “sqlite,” “yojimbo,” and “treesitter” can point to canonical modules without pretending those aliases are importable module names.

## Canonical Module Page Template

Every module page should use this structure:

```markdown
# <canonical import>

## Canonical Import

How to import the module, using the exact canonical name.

## Source Files

Source-of-truth binding or Fennel files.

## What It Provides

Short consumer-facing purpose statement.

## API Summary

Functions, types, methods, constants, and important return shapes.

## Examples

At least one practical Fennel example using canonical imports.

## Errors and Platform Notes

Missing capability behavior, unavailable optional dependencies, failure modes, platform/build constraints.

## Related Modules

Nearby modules and relevant SDK/dev docs.

## Aliases and Search Terms

Non-canonical names users may search for.
```

## Source-of-Truth Policy

Module reference pages should be derived from:

- Native binding registration and APIs in `src/lua_*.cpp`.
- Runtime registration in `src/lua_runtime.cpp` and `src/lua_engine.cpp`.
- Public Fennel facades under `assets/lua/**/*.fnl`.
- Tests and examples for usage patterns.
- Existing `docs/dev/**` pages only for implementation context.

`assets/python/` is historical prototype material and must not define SDK module contracts.

When a Fennel facade wraps a native core binding, document the facade as the primary consumer module and document the native core separately when useful. Examples: `temporal` plus `temporal-core`; `wallet` plus `wallet-core`.

## Alias Policy

Use canonical import names in page titles, filenames, examples, and sidebar entries. Put non-canonical names in `docs/sdk/modules/aliases.md` and in the module page's “Aliases and Search Terms” section.

Known alias mappings:

- `physics` → `bt`
- `graphics`, `rendering` → rendering/media modules such as `gl`, `shaders`, `textures`, `vector-buffer`, `image-io`, `glm`, `colors`, and `cgltf`
- `treesitter` → `tree-sitter`
- `yojimbo` → `realtime`
- `sqlite` → `lsqlite3` and `sql-builder`
- `jpeg`, `jpg` → `image-io` and `textures`
- `xml` → no canonical SDK module found; do not invent one

## Initial Category Scheme

The catalog and sidebar should group modules into these categories:

- Runtime and platform
- Data, storage, and parsing
- Rendering, media, and graphics
- Audio
- Physics and world systems
- Networking and services
- Wallet and identity
- Advanced/native tooling

Categories are navigation aids only. They do not define import names or URL paths.

## Initial Module Coverage

The implementation should cover at least these modules discovered in the current repository:

### Runtime and Platform

- `appdirs`
- `engine`
- `runtime`
- `cli-args`
- `fs`
- `logging`
- `error-reporting`
- `callbacks`
- `jobs`
- `keyring`
- `process`
- `shell`
- `file-watch`
- `notify`
- `tray`
- `terminal`
- `sysinfo`
- `uuid`
- `random`
- `input-state`
- `dial-type`
- `webbrowser`

### Data, Storage, and Parsing

- `temporal`
- `temporal-core`
- `json`
- `json-utils`
- `toml`
- `lsqlite3`
- `sql-builder`
- `tree-sitter`

### Rendering, Media, and Graphics

- `gl`
- `shaders`
- `textures`
- `vector-buffer`
- `image-io`
- `glm`
- `colors`
- `cgltf`
- `ray-box`
- `graph-edge-batch`
- `force-layout`
- `msdf-atlas-gen`
- `video`

### Audio

- `audio`
- `audio-input`
- `aubio` family: `aubio/vec`, `aubio/spectral`, `aubio/temporal`, `aubio/io`, `aubio/synth`, `aubio/utils`

### Physics and World Systems

- `bt`
- `perlin-terrain-native`

### Networking and Services

- `http`
- `http_server`
- `zmq`
- `realtime`
- `libtorrent`
- `matrix`
- `xapian`

### Wallet and Identity

- `wallet`
- `wallet-core`

### Advanced/Native Tooling

- `gccjit`

## SDK Landing Page Changes

`docs/sdk/index.md` should make module reference the first and primary path. The first “Start Here” link should be `Module Reference` pointing to `/sdk/modules/`. Tutorials, guides, app/host reference, and examples remain linked but are secondary.

`docs/sdk/reference/index.md` should clarify that `/sdk/reference/` is for app/host contracts, while `/sdk/modules/` is for reusable ecosystem modules.

`docs/sdk/concepts.md` should clarify the difference between modules and app contracts.

## Error Handling and Platform Notes

Module pages should avoid silent or vague failure descriptions. If a module can be missing because of build options or platform support, say so. If required data or capabilities fail, describe the expected loud failure at a high level and link to source/dev docs where useful.

## Validation

Implementation should be validated with:

- `git diff --check`
- Search for placeholders and unsupported stability promises in `docs/sdk` and the SDK docs policy note.
- Search to ensure aliases such as `/sdk/modules/physics`, `/sdk/modules/graphics`, `/sdk/modules/treesitter`, `/sdk/modules/yojimbo`, `/sdk/modules/sqlite`, `/sdk/modules/jpeg`, and `/sdk/modules/xml` are not linked as canonical pages.
- Verify every `docs/sdk/modules/*.md` page is linked from the module index, alias index, or sidebar.
- `cd docs && npm run docs:build`

## Open Questions Resolved by Policy

- `xml`: no canonical SDK module was found, so document it only in aliases as “no canonical module found” until the project adds or identifies one.
- `sqlite`: document `lsqlite3` and `sql-builder`; do not create a fake `sqlite` import page.
- `yojimbo`: document `realtime`; mention yojimbo as implementation/search terminology.
- `physics`: document `bt`; mention physics as search terminology.
- `graphics`: use category grouping and specific rendering modules; do not create a fake `graphics` module.
