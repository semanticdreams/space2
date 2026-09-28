# SDK Docs

## Purpose

The SDK docs are centered on consumer-facing module reference pages for the Space ecosystem. They should answer which modules are available, how builders import them, what functions and types they expose, which errors or platform constraints apply, and what real usage looks like.

Existing tutorials, guides, examples, and app/host contract reference pages remain valuable secondary material. Module pages should link to developer docs when implementation detail is useful, but they should not require readers to understand maintainer workflows before using a module.

## Selected Information Architecture

Use flat canonical module pages under `docs/sdk/modules/`:

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

Group modules by category in `docs/sdk/modules/index.md` and the VitePress SDK sidebar. Categories are navigation aids only; they do not define import names or URL paths.

The initial categories are:

- Runtime and platform
- Data, storage, and parsing
- Rendering, media, and graphics
- Audio
- Physics and world systems
- Networking and services
- Wallet and identity
- Advanced/native tooling

## Rejected Information Architecture Alternatives

### Category Folders

Category folders such as `docs/sdk/modules/runtime/appdirs.md` would mirror conceptual grouping, but they would make URLs churn when categories change and would handle cross-category modules poorly.

### Family Pages With Anchors

Family pages such as `docs/sdk/modules/runtime.md#appdirs` would reduce file count, but they would make lookup, deep-linking, examples, and per-module review weaker.

## Source-of-Truth Policy

Module reference pages should be derived from:

- Native binding registration and APIs in `src/lua_*.cpp`.
- Runtime registration in `src/lua_runtime.cpp` and `src/lua_engine.cpp`.
- Public Fennel facades under `assets/lua/**/*.fnl`.
- Tests and examples for usage patterns.
- Existing `docs/dev/**` pages only for implementation context.

`assets/python/` is historical prototype material and must not define SDK module contracts.

When a Fennel facade wraps a native core binding, document the facade as the primary consumer module and document the native core separately when useful. Examples include `temporal` plus `temporal-core`, and `wallet` plus `wallet-core`.

## Alias Policy

Use canonical import names in page titles, filenames, examples, and sidebar entries. Put non-canonical names in `docs/sdk/modules/aliases.md` and in each relevant module page's “Aliases and Search Terms” section.

Known alias mappings:

- `physics` → `bt`
- `graphics`, `rendering` → rendering/media modules such as `gl`, `shaders`, `textures`, `vector-buffer`, `image-io`, `glm`, `colors`, and `cgltf`
- `treesitter` → `tree-sitter`
- `yojimbo` → `realtime`
- `sqlite` → `lsqlite3` and `sql-builder`
- `jpeg`, `jpg` → `image-io` and `textures`
- `xml` → no canonical SDK module found; do not invent one

## XML and No-Canonical-Module Policy

Do not create a module reference page for a name unless a canonical SDK module or source file identifies that module contract. For `xml`, no canonical SDK module has been identified, so document it only as a search term in `docs/sdk/modules/aliases.md` until a canonical source exists.

The same rule applies to other search terms: do not create fake import pages for `physics`, `graphics`, `treesitter`, `yojimbo`, `sqlite`, `jpeg`, `jpg`, or similar aliases. Point readers to the canonical module pages instead.

## Shared Module Page Template

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
