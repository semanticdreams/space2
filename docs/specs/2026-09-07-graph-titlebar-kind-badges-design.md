# Graph Titlebar Kind Badges Design

## Purpose

Graph preview cards and full node views should make the kind of graph-exposed object visible without relying only on node color. Compact graph points should remain unchanged because their current color encoding is sufficient at that scale.

## User-Facing Behavior

- Expanded preview cards show a compact kind badge immediately before the title in the titlebar.
- Full node-view dialogs show the same kind badge immediately before the title in the titlebar.
- Compact graph points keep their current layered point rendering, colors, sizes, labels, selection rings, and focus outlines.
- Nodes without badge metadata still render valid titlebars with the existing title layout.

## Architecture

Kind badges are graph node adapter presentation metadata. A node adapter may expose `kind-badge` data alongside existing presentation fields such as `color`, `accent`, `preview`, and `view`. The graph core does not own badge semantics and does not persist badge data in graph topology state.

The graph view and dialog UI consume badge metadata at render time:

- preview/card titlebars render the badge before the title;
- full node-view dialogs receive a reusable title-prefix widget/builder;
- compact point rendering ignores the badge entirely.

This keeps the graph as an exposure/adaptor layer over domain systems while making graph-visible objects easier to scan in preview and view contexts.

## Badge Metadata Shape

The implementation should support a small normalized badge shape:

- `text`: required non-empty display text after normalization;
- optional visual fields such as background and foreground colors may default from existing node presentation colors;
- an explicit `false` opt-out remains possible for adapters that should not show a badge.

No centralized global kind taxonomy or style registry is required for this change. Existing adapters can opt into curated text over time. When an adapter does not provide explicit badge metadata, default badge text should be derived from the stable key scheme before the first `:` and uppercased, such as `fs:/tmp/a.txt` becoming `FS`. If a key has no scheme, the node should render without a badge unless the adapter provides one explicitly.

## Error Handling

Malformed explicit badge metadata should fail loudly during node construction or rendering with a clear error. Missing badge metadata is not an error and should preserve existing titlebar behavior.

## Testing and Validation

Focused validation should cover:

- badge metadata normalization and opt-out behavior;
- graph topology capture/persistence remaining free of badge metadata;
- preview/card titlebar ordering with the badge before the title;
- full node-view dialog title prefix behavior;
- compact point rendering remaining unchanged for badged nodes;
- no-badge nodes preserving existing titlebar structure.

Because this is Fennel UI work, validation should run the Space Fennel compile check, constraints, focused graph/dialog tests, and broader UI/runtime validation if shared dialog infrastructure changes.

## Out of Scope

- Changing compact point shape, color, geometry, label behavior, or focus/selection treatment.
- Adding icon badges.
- Exhaustively curating every existing adapter kind in one pass.
- Persisting badge data in graph topology state.
- Moving domain object data or semantics into graph core.
