# SDK Documentation Section Design

## Summary

Add a first-class `docs/sdk/` section for people who want to build with the Space ecosystem rather than only use the main Space app or contribute to Space itself. The section should serve builders using Space as a library, framework, SDK, or host runtime for apps, extensions, widgets, worlds, workflows, and independent applications.

The recommended information architecture is a learning-path SDK shape: overview, getting started, tutorials, guides, reference, and examples. This keeps onboarding material separate from lookup material, minimizes duplication with `docs/dev/`, and gives SDK users a visible entry point from the documentation home page.

## Current Documentation Gap

The current docs have two clear audiences:

- `docs/user/` — people running and using the main Space app.
- `docs/dev/` — people developing the Space project itself, including architecture, subsystem, feature, work-tracking, and internal development docs.

Some builder-facing material exists today, but it is mixed into developer docs or examples. That makes SDK users infer which internals are relevant, which API contracts are safe to consume, and where tutorials versus reference live. The new `docs/sdk/` section should make this audience explicit.

## Audience Boundaries

### User Docs

User docs answer: “How do I install, run, and use Space?”

They should keep linking to SDK docs only when a user wants to start building apps, extensions, or workflows.

### SDK Docs

SDK docs answer: “How do I build something with Space?”

This includes app authors, extension authors, world builders, workflow/tool builders, and developers embedding or reusing Space runtime pieces for independent apps.

### Developer Docs

Developer docs answer: “How do I develop and maintain the Space project itself?”

SDK docs should link into developer docs for implementation internals, architecture history, ADRs, and subsystem details rather than duplicating them.

## Considered Structures

### Option A: Learning-Path Structure

```text
docs/sdk/
├── index.md
├── getting-started.md
├── concepts.md
├── tutorials/
├── guides/
├── reference/
└── examples/
```

This is the recommended structure. It is familiar to SDK users, supports both tutorials and lookup, and can grow without forcing early product-domain decisions. Its main cost is that some topics may appear in several forms: a tutorial, a deeper guide, and a reference page. That duplication should be controlled through short summaries and cross-links rather than copy-pasting content.

### Option B: Product-Domain Structure

```text
docs/sdk/
├── index.md
├── apps/
├── extensions/
├── runtime/
├── distribution/
└── reference/
```

This mirrors likely SDK domains and may fit later if each domain becomes large. It is less beginner-friendly now because tutorials, task guides, and reference pages would be scattered by subsystem.

### Option C: Persona Structure

```text
docs/sdk/
├── index.md
├── independent-apps/
├── space-extensions/
├── embedded-hosting/
└── reference/
```

This makes the target audience clear but risks repeating shared concepts across personas. It is useful as a lens for landing-page copy, but not as the primary file structure.

## Recommended Structure

Use Option A as the initial shape:

```text
docs/sdk/
├── index.md
├── getting-started.md
├── concepts.md
├── tutorials/
│   ├── index.md
│   ├── your-first-space-app.md
│   ├── add-a-command.md
│   └── publish-an-app.md
├── guides/
│   ├── index.md
│   ├── app-layout.md
│   ├── hostable-runtime-apps.md
│   ├── embedded-workspace-hosting.md
│   ├── graph-extension-units.md
│   └── ui-surfaces.md
├── reference/
│   ├── index.md
│   ├── app-module-contract.md
│   ├── host-capabilities.md
│   ├── runtime-facets.md
│   ├── commands.md
│   ├── scene-capability.md
│   ├── packaging-workflow.md
│   └── graph-extension-descriptors.md
└── examples/
    └── index.md
```

The section should launch with skeletal but useful pages rather than waiting for perfect reference coverage. Each page can start as a curated entry point that links to existing examples and developer internals, then become more complete over time.

## Page Roles

### `docs/sdk/index.md`

Defines the SDK audience and routes readers by task:

- Start here.
- Learn the model.
- Follow tutorials.
- Solve a task with guides.
- Look up contracts in reference.
- Browse examples.
- Find internal implementation details in developer docs.

### `docs/sdk/getting-started.md`

Explains the minimum path from repository checkout to running or inspecting an SDK example. It should avoid deep Space contributor setup unless required by the current state of the tooling.

### `docs/sdk/concepts.md`

Defines core SDK-facing vocabulary: app, host, capability, runtime facet, command, scene capability, graph extension unit, package, and example. Terms should be explained from the consumer perspective.

### `docs/sdk/tutorials/`

Goal-driven, copyable walkthroughs. Initial tutorials should include:

- Build or run your first Space app.
- Add a command.
- Package or publish an app.

Tutorials should prefer happy-path instructions and link to guides/reference for deeper detail.

### `docs/sdk/guides/`

Task and concept guides for SDK users. Initial guides should cover:

- App layout.
- Hostable runtime apps.
- Embedded workspace hosting.
- Graph extension units.
- UI surfaces.

Guides may link to `docs/dev/` for internals but should not require the reader to understand project-maintainer concerns first.

### `docs/sdk/reference/`

Lookup-oriented contracts, field names, invariants, command shapes, host capability expectations, and packaging workflow details. Reference pages should avoid broad architecture history and focus on what SDK consumers can depend on.

Initial reference pages should cover:

- App module contract.
- Host capabilities.
- Runtime facets.
- Commands.
- Scene capability.
- Packaging workflow.
- Graph extension descriptors.

The docs must not promise stable public API guarantees until the project explicitly decides what is stable.

### `docs/sdk/examples/`

A curated index of copyable examples. It should initially link to existing example material, explain what each example demonstrates, and avoid duplicating entire example READMEs.

## Navigation Changes

The SDK section should be visible as a peer to User and Developer Docs:

- Add an `SDK Docs` action to `docs/index.md`.
- Add `SDK` to the VitePress top navigation.
- Add a `/sdk/` sidebar in `docs/.vitepress/config.mts` with grouped Overview, Tutorials, Guides, Reference, and Examples links.
- Add short cross-links from `docs/user/index.md` and `docs/dev/index.md` clarifying the audience boundary.

## Content Principles

- Use consumer language first: app, host, capability, runtime facet, extension, command, package.
- Define project-specific terms before using them heavily.
- Use tutorials for learning, guides for task solving, reference for lookup, and examples for copyable starting points.
- Keep SDK docs focused on contracts and usage; link to `docs/dev/` for internals, rationale, and maintenance workflows.
- Do not duplicate large blocks from existing developer docs or example READMEs.
- Use kebab-case Markdown filenames and explicit index link lists, matching current documentation conventions.
- Avoid adding compatibility aliases or legacy terminology; use canonical names only.
- Avoid promising SDK stability or versioning guarantees until that policy is decided.

## Error Handling and Maintenance

Documentation should make missing capability behavior explicit: required SDK capabilities should fail loudly rather than silently doing nothing. Pages that describe commands, host capabilities, runtime facets, or packaging should call out required inputs, expected failures, and where users should look for debugging information.

The SDK section should stay maintainable by treating `docs/sdk/index.md` and each child `index.md` as canonical navigation pages. When new SDK pages are added, their parent index and VitePress sidebar should be updated in the same change.

## Validation

Implementation should be validated by:

- Reviewing all new SDK filenames for kebab-case.
- Confirming each SDK directory index links to all child pages.
- Confirming root, top nav, sidebar, user docs, and developer docs link to the SDK section where appropriate.
- Searching for accidental large copy-pastes from `docs/dev/`.
- Running the docs build with `cd docs && npm run docs:build`.

## Out of Scope

- Runtime or SDK behavior changes.
- New SDK examples beyond linking and curating existing examples.
- Moving or deleting existing `docs/dev/` content.
- Defining a formal SDK stability/versioning policy.
- Reorganizing the entire documentation site beyond adding the new SDK section and necessary navigation links.
