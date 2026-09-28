# SDK Reference

These pages are lookup references for current SDK-facing contracts. They describe how Space app modules, host capabilities, runtime facets, commands, scene access, packaging, and graph extension descriptors work today without formal stability guarantees.

Use `/sdk/reference/` for app and host contracts. Use the [module reference](/sdk/modules/) for reusable Space ecosystem modules, canonical imports, API summaries, examples, aliases, and platform notes.

- [App Module Contract](/sdk/reference/app-module-contract) — exported module shape, app creation, runtime composition, and host ownership boundaries.
- [Host Capabilities](/sdk/reference/host-capabilities) — capabilities an app can request from a host and how missing optional or required capabilities behave.
- [Runtime Facets](/sdk/reference/runtime-facets) — runtime metadata exposed back to a host.
- [Commands](/sdk/reference/commands) — synchronous and asynchronous command metadata, payload schemas, confirmations, and errors.
- [Scene Capability](/sdk/reference/scene-capability) — app-owned scene handles and supported scene operations.
- [Packaging Workflow](/sdk/reference/packaging-workflow) — packaging inputs, validation failures, and repository boundaries.
- [Graph Extension Descriptors](/sdk/reference/graph-extension-descriptors) — descriptor fields, loader ownership, rollback, and graph topology rules.
