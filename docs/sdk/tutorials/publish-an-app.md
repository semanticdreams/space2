# Publish an App

Goal: publish an independent app by calling Space's reusable bundle workflow.

App repositories can release against a pinned Space runtime by calling the reusable bundle workflow from a tag-triggered release workflow:

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

The required inputs are `space-version` and `app-name`. The `space-version` input selects the pinned Space release assets used for packaging, and `app-name` names the packaged app.

App repositories do not compile Space in this path. They provide app assets and metadata, then rely on the reusable workflow to assemble those inputs with an existing Space release.

Missing assets, invalid entrypoints, unsupported package targets, and missing pinned Space release assets should fail before packaging so the release does not silently publish an unusable app.

## Next Steps

- [Packaging Workflow Reference](/sdk/reference/packaging-workflow) — look up workflow inputs and expected failures.
- [App Layout Guide](/sdk/guides/app-layout) — confirm the repository shape that packaging expects.
- [App Distribution](/dev/features/app-distribution) — inspect maintainer-facing distribution details when you need internals.
