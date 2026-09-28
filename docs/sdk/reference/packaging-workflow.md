# Packaging Workflow

The app packaging workflow turns an app repository into a distributable package using a pinned Space release. App repositories do not compile Space in this packaging path.

## Required Inputs

- `space-version`
- `app-name`

## Optional Inputs

- `app-id`
- `entrypoint`
- `assets-dir`
- `icon-path`
- `linux-profile`
- `release-version`

App repositories do not need and must not add a required root-level `space-app.json`. Packaging should rely on the workflow inputs and app files instead of introducing that repository-level contract.

Missing app assets, invalid app ids, invalid entrypoints, missing pinned Space release assets, and unsupported package targets fail before packaging begins.

See [Publish an App](/sdk/tutorials/publish-an-app) for the tutorial path and [App Distribution](/dev/features/app-distribution) for maintainer-facing details.
