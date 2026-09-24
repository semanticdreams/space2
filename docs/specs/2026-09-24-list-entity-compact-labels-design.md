# List entity compact label suppression

## Context

List entity graph node adapters currently derive `node.label` from the custom
list name when present, otherwise from the raw entity id. Compact/collapsed graph
labels render that label, so unnamed list entities show implementation-oriented
ids in the graph view. Those ids are useful for debugging and copy-key workflows,
but they are not semantically meaningful to normal users and visually pollute the
collapsed graph.

The graph remains an exposure layer: list entity data is owned by the list entity
store, graph node adapters project that domain object into graph-addressable
form, and `graph/view/labels` owns compact label rendering.

## Goal

When a list entity graph node is collapsed, show a compact graph label only if
the list entity has a non-empty custom name. If the list entity is unnamed, show
no compact label at all; the node color is sufficient to identify it as a list,
and users can open the preview/full view or use the copy-key context action when
they need the key/id.

Named list entities should continue to show their custom name in collapsed graph
labels with the existing truncation behavior.

## Non-goals

- Do not change list entity persistence or storage schema.
- Do not remove raw keys from copy-key, preview, full-view, debugging, or other
  explicit access paths.
- Do not change ordered-list island layout, list item rendering, or list entity
  membership behavior.
- Do not change compact label behavior for other node families except as needed
  to support a generic opt-out mechanism.
- Do not persist compact-label presentation metadata into graph topology state.

## Design

### Recommended approach: compact-label presentation metadata

Introduce a small compact-label rendering contract for graph node adapters:

- `node.compact-label == false` means `graph/view/labels` renders no compact
  label for that node.
- a non-nil string `node.compact-label` is the compact label text base.
- `nil` preserves current fallback behavior: compact labels use `node.label` or
  the node key.

`ListEntityNode` should keep its current `node.label` behavior for non-compact
surfaces: custom name when present, otherwise raw entity id. It should also set
and refresh `node.compact-label` from the custom name only. For unnamed lists,
`compact-label` is `false`. On rename, the existing label refresh path should
refresh both fields and emit the existing node-changed signal so compact labels
appear or disappear immediately.

This keeps the visual rule in `graph/view/labels` while letting the domain
adapter expose render-time metadata derived from domain state. Graph topology
persistence remains unchanged because compact-label metadata is runtime
presentation data, not graph topology state.

### Alternatives considered

1. **Change `node.label` to nil/empty for unnamed list entities.** This is too
   blunt: `node.label` feeds expanded card headers, default previews, dialogs,
   selection-oriented surfaces, and any non-compact display code. The requested
   behavior is specifically about collapsed graph clutter, not about removing id
   access everywhere.
2. **Add a dynamic compact-label method/hook.** A hook would work but is more
   flexible than needed. The list entity adapter already refreshes state and
   emits change signals on store/name updates, so a simple field is easier to
   test and reason about.
3. **Special-case list entities directly inside `graph/view/labels`.** This
   would couple generic label rendering to one node family and make future
   compact-label policies harder to add cleanly.

## Components and data flow

1. `ListEntityNode` resolves the backing list entity from the list entity store.
2. It computes `node.label` as today: custom name or raw entity id fallback.
3. It computes `node.compact-label` as truncated custom name or `false` when no
   custom name exists.
4. `GraphViewLabels` resolves compact label text for each collapsed node. If the
   resolved value is `false`, it drops any existing label span and skips span
   creation for that node.
5. Rename/store update paths refresh both labels and emit the existing change
   signal, causing the graph view to recreate, update, or drop the compact label.

## Error handling

- Missing `compact-label` metadata is not an error; it means existing label
  fallback behavior remains active.
- `compact-label == false` is the only opt-out sentinel. Empty strings should not
  be introduced by `ListEntityNode`; custom names should continue to be tested
  for non-empty content before becoming compact labels.
- Missing required graph view build context should continue to assert as it does
  today; this feature should not add silent UI fallbacks.

## Testing

Focused tests should cover:

- `GraphViewLabels` creates no text span for a collapsed node whose
  `compact-label` is `false`.
- Nodes without `compact-label` preserve existing fallback behavior.
- `ListEntityNode` keeps `node.label` as the raw id fallback for unnamed lists
  while setting `node.compact-label` to `false`.
- Named list entities set both `node.label` and `node.compact-label` to the
  custom name.
- Clearing or setting a list entity name refreshes compact-label metadata and
  emits the existing node change flow.

Validation should follow the Space Fennel ladder: targeted `tools.fennel-check`
for touched Fennel files, constraints, focused graph/list entity tests, and a
broader graph/Fennel suite if shared label infrastructure risk warrants it.
