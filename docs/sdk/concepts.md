# SDK Concepts

## App

An app is a builder-owned unit that Space can launch through an entrypoint such as `space -m main`. An app usually brings its own `assets`, code, `lifecycle` hooks, and user-facing `commands`, then asks the host for the capabilities it needs.

## Host

The host is the Space runtime process that loads an app, resolves `assets`, exposes runtime facets, runs the `scheduler`, and reports failures when required inputs or capabilities are missing.

## Capability

A capability is a named contract an app or extension expects the host to provide. Capabilities should make required inputs explicit and fail loudly when unavailable. Common capability areas include `commands`, `input`, `presentation`, `scene`, `metadata`, and `inspectors`.

## Runtime Facet

A runtime facet is one builder-facing surface of the host, such as `scheduler`, `input`, `presentation`, `scene`, asset loading, or command registration. Facets group related operations so an app can request only the host behavior it needs.

## Modules vs. App Contracts

Modules are reusable Space ecosystem libraries that builders import directly. Use the [module reference](/sdk/modules/) to find canonical import names, APIs, examples, aliases, and platform notes.

App contracts describe how an app talks to the Space host. Use the [app/host reference](/sdk/reference/) for app module shape, host capabilities, runtime facets, commands, scene access, packaging, and graph extension descriptors.

## Command

A command is an invocable action exposed by an app, extension, or host facet. `commands` should document required arguments, expected results, and failure behavior so malformed invocations are visible during development.

## Scene Capability

A scene capability lets an app create or update spatial objects, world views, and scene-backed presentation. Builders use it when app state needs to appear in the 3D `scene` rather than only in non-spatial UI.

## Graph Extension Unit

A graph extension unit is a packaged addition to Space's graph-oriented environment. It can contribute graph behavior, `metadata`, `inspectors`, commands, or presentation surfaces while keeping graph internals in the developer docs.

## Package

A package is the distributable shape of an app, extension, widget, world, workflow, or independent application. A package should include the `assets`, entrypoints, metadata, and host requirements needed to run predictably.

## Example

An example is a copyable starting point that demonstrates a focused app shape or capability in context. Examples are not a substitute for reference contracts, but they show how `lifecycle`, assets, presentation, scene behavior, and commands fit together.

## Next Steps

- [Reference](/sdk/reference/) — look up current contracts and required inputs.
- [Guides](/sdk/guides/) — solve task-focused builder problems.
- [Developer Docs](/dev/) — read internals and maintenance details when SDK pages link deeper.
