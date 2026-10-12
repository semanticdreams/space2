# Outline Marker Box Stability Design

## Problem

The graph outline now uses measured `TreeView` row layout, which is the correct
architecture, but the compact graph marker inside each row currently exposes
state-dependent visual size to row measurement. Two visual issues follow:

- a row label with taller glyph bounds can make the compact point appear coupled
  to the label's measured height;
- selecting or focusing a row increases the compact point's focus/selection
  layer sizes, which can change the row's measured height and shift descendant
  rows.

The desired behavior is not uniform row height. Rows may still be taller when
their content is taller or when an expanded card is visible. The desired
invariant is that compact marker layout is stable: focus/selection chrome and
label glyph variation must not resize the point's layout footprint or reflow
other rows.

## Goals

- Keep `TreeView` generic and unchanged: it stacks whatever row widgets measure.
- Keep raw `LayeredPoint` layout-free for spatial graph performance.
- Add a reusable layout wrapper for contexts that need a layered point to
  participate in widget layout.
- Keep graph interaction ownership in `CompactNodeProjection` and graph outline,
  not in generic marker layout code.
- Make outline marker measurement stable across focus/selection state changes.
- Keep point and label top-aligned in outline summary rows.
- Preserve current graph outline behavior: compact point click/focus/select/menu
  semantics, row whitespace non-interaction, expanded-card behavior, teardown,
  and all-visible outline rows.

## Non-goals

- Do not make `LayeredPoint` itself a widget or give every spatial graph point a
  `Layout` node.
- Do not add shared row metrics or uniform row-height behavior to `TreeView`.
- Do not change graph topology traversal, graph persistence, outline root
  semantics, selection/focus ownership, or graph commands.
- Do not change spatial graph layout behavior.
- Do not introduce virtualization or port outline rendering to `next-app`.

## Design

### LayeredPoint remains a layout-free render primitive

`assets/lua/layered-point.fnl` should continue to create and manage layered
point render records directly. Spatial graph views can keep using compact point
presentations without per-point layout overhead.

### Add a measured LayeredPointBox widget

Introduce a reusable widget wrapper, `LayeredPointBox`, for layout contexts. The
box owns:

- an explicit `Layout`;
- one raw `LayeredPoint`;
- a stable reserved size that represents the maximum chrome footprint expected
  for that point in this layout context.

The box measures to `reserved-size` on both axes. The raw point draws inside that
reserved square. Current focus/selection layer state may change the rendered
layers, but it must not change the box's measure unless the caller explicitly
changes the reserved size.

If a caller attempts to set visual layers larger than the reserved size, the
layout wrapper should fail loudly or require an explicit reserved-size update.
Silent overflow that changes visual behavior without an ownership decision is
not acceptable.

### Add a caller-owned point seam to CompactNodeProjection

`CompactNodeProjection.attach!` currently creates the compact point it binds.
Outline rows need the point to be owned by `LayeredPointBox`, while projection
still owns graph interactions. Extend the projection seam so callers may provide
a LayeredPoint-like point:

- default path: `attach!` creates and owns the compact point, preserving spatial
  graph behavior;
- layout path: `attach!` or a small helper accepts a caller-owned point and binds
  clickables, selector entries, focus bounds, menu routing, activation, and
  visual layer refresh to it without dropping the point by default.

The ownership flag must be explicit. Projection teardown should always unregister
interaction handles and focus/selectable state, but should only drop the point
when the projection created it.

### Compose OutlineRowWidget from marker box and label

`OutlineRowWidget` should stop deriving layout from
`CompactNodeProjection.visible-size`, because that value is inherently current
visual state. Instead:

- create a `LayeredPointBox` whose reserved size is based on the node's base size
  plus the maximum selection/focus chrome allowance used by the outline;
- bind `CompactNodeProjection` to the box's raw point;
- measure the compact summary row as
  `max(marker-box.measure.y, label.layout.measure.y) + vertical-padding * 2`;
- lay out marker box and label as a horizontal top-aligned row;
- place the marker at the row's top edge, not vertically centered against a tall
  label;
- use the marker box's stable reserved width for label x-offset;
- when selection/focus changes, refresh projection layers and marker visuals but
  do not let that state change row measure.

Expanded rows still add the expanded card's measured height below the compact
summary row. Expanded-card selection/focus behavior remains graph-owned via the
outline row widget and compact projection seams.

## Data and ownership boundaries

- `TreeView` owns tree flattening and stacking only.
- `LayeredPointBox` owns layout footprint and raw point lifetime in layout
  contexts.
- `LayeredPoint` owns raw render-layer records only.
- `CompactNodeProjection` owns graph compact interaction registrations,
  selector membership, focus-node bindings, activation/menu callbacks, and
  layer refresh.
- `OutlineRowWidget` composes marker box, label, projection record, and optional
  expanded card for graph outline rows.
- `GraphMap` remains the owner of view mode, outline roots, selected keys, and
  focused key.
- Graph core persists topology only.

## Testing strategy

Focused tests should prove:

- `LayeredPointBox` measures to a stable reserved size and lays out the raw point
  inside that box.
- `LayeredPointBox` drops its owned point and layout exactly once.
- `CompactNodeProjection` preserves existing internally-created point behavior.
- `CompactNodeProjection` can bind interactions to a caller-owned point without
  dropping it by default.
- Outline row focus/selection layer changes do not change row height or move
  descendant compact points.
- Outline label glyph height can make the row taller, but the marker remains a
  stable size and top-aligned.
- Row whitespace and label area remain non-graph-node interaction zones.
- Expanded row measurement and collapse/re-expand teardown still pass.

E2E validation should include the graph outline snapshots and click/focus repros
after any visual update, with generated snapshots visually inspected before
commit.

## Validation requirements

For Fennel/UI/layout graph work, run validation in this order:

1. project-native Fennel compile check for touched files or `make fennel-check`;
2. `make constraints`;
3. focused Fennel tests for `LayeredPointBox`, compact projection, and graph
   outline;
4. graph outline E2E snapshot/click validation when visuals change;
5. broader `make test` when reusable widget or graph interaction behavior
   changes.

Do not use system Fennel/Lua or non-project compiler paths as validation
oracles.
