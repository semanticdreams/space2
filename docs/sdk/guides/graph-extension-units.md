# Graph Extension Units

Graph extension units add graph-exposed node types through descriptors. A descriptor tells the host which graph unit is being installed, which schemes it supports, and how loader registrations are installed.

Registrations go through `app.graph-extension-registry`. Keep registration ownership explicit so reload and unload paths can release every handle the extension created.

Descriptor fields must include:

- `:id` — the descriptor identity used for registration and diagnostics.
- `:unit-id` — the graph extension unit identity exposed to hosts.
- `:schemes` — a non-empty collection of supported graph key schemes.
- `:install-loaders` — the function that installs loader registrations and returns handles for cleanup.

Extension-owned data stays behind extension keys, and graph topology remains key-only. Avoid coupling graph structure to view objects or app-local mutable state; let graph keys describe relationships and let extensions resolve their own data behind those keys.

Reload and unload paths must unregister handles. Duplicate active registrations and failed refreshes should fail loudly so extension authors can see conflicting descriptors, leaked handles, or invalid loader state immediately.

See [Graph Extension Descriptors](/sdk/reference/graph-extension-descriptors), [Reloadable Graph Extension Units](/dev/features/reloadable-graph-extension-units), [Graph Foundation](/dev/features/graph-foundation), and [Graph Maps](/dev/graph-maps) for the current contracts and internals.
