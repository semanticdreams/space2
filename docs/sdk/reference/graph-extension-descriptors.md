# Graph Extension Descriptors

Graph extension descriptors let an app or extension register graph-facing node loaders and morphs while keeping graph topology key-only.

```fennel
{:id "demo-extension"
 :unit-id "user-demo-extension"
 :schemes ["demo-node"]
 :install-loaders install-loaders}
```

## Required Fields

- `:id`
- `:unit-id`
- non-empty `:schemes`
- `:install-loaders`

## Optional Fields

- `:install-morphs`
- `:refresh-schemes`

Loader and morph installers return owner-safe handles. Runtime install failures roll back installed handles and rethrow the failure so callers see the original problem. Duplicate active key-loader or morph registrations fail loudly rather than replacing or shadowing an existing registration.

Graph topology remains key-only: descriptors expose how keys are loaded or morphed, but graph edges and stored topology continue to refer to keys rather than live runtime objects.

See [Graph Extension Units](/sdk/guides/graph-extension-units) for SDK usage and [Reloadable Graph Extension Units](/dev/features/reloadable-graph-extension-units) for maintainer-facing internals.
