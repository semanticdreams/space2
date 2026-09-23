# Independent graph island bodies

## Context

Graph presentation islands are map-local presentation records persisted by
`GraphMap` and rendered by `GraphView` presenters by island `:kind`. The first
concrete presenter, `ordered-list`, is used by list entity nodes to present list
items vertically in graph space.

The current list-created island behavior derives a new island origin from the
list node position and stores list-specific source anchoring details such as the
list key. That worked as a first slice, but it leaves an ongoing conceptual
coupling between the source node and the island position.

## Goal

Make every graph presentation island an independent map-local layout body. An
island has its own persisted body position in graph space, and a presenter lays
out its members relative to that body. The node or action that creates an island
may choose the initial body position, but the island does not remain implicitly
source-relative after creation.

## Non-goals

- Do not make islands own domain data. List order remains owned by the list
  entity store.
- Do not add user-facing island policy controls in this slice.
- Do not implement domain reordering through drag operations.
- Do not require richer member role records unless a concrete presenter needs
  them later.

## Design

### Island body position

Island presenter state uses `state.position` as the island body's absolute graph
position. For `ordered-list`, the first item is placed at `state.position`, and
later items are offset vertically by `state.spacing`.

If an island is created by a node action, that action may initialize
`state.position` near the creating node for convenience. After creation, the
stored island position is authoritative and independent.

### Source nodes

The creating/source node is not a hidden spatial anchor. If a future presenter
needs the source node to visually participate in the island, it should make that
relationship explicit by including the source node in the island's presented
membership or by introducing a documented presenter-owned role convention. This
slice does not add role semantics.

Existing metadata such as `state.list-key` can remain as non-spatial presenter
metadata only where needed for compatibility or diagnostics, but presenters must
not use it to derive positions when `state.position` is missing. For restored
legacy records with no `state.position`, presenters should fall back to an
island-local default or existing member position rather than re-anchoring to a
source node.

### Force layout participation

The immediate implementation treats island bodies as independent static bodies
with persisted positions. This establishes the invariant needed for a later
force-layout integration: the layout engine can eventually move island bodies as
single units and then ask presenters to reconcile members relative to the new
body position.

This slice does not require full force-layout body simulation. It removes the
source-relative assumption so force-layout island bodies can be added without
changing presenter semantics again.

### List entity behavior

`ListEntityNode:expand-items-as-island` should:

- materialize current item nodes through the mounted `GraphMap`;
- upsert an `ordered-list` island whose members are item node keys in stored
  list order;
- preserve an existing island's `state.position` on refresh;
- initialize a new island's `state.position` near the list node only as an
  initial placement convenience;
- refresh existing islands when list items or identity targets change;
- remove an existing island when it has no members.

The list node may remain outside the island membership. Removing the island does
not remove the list entity or item entities.

## Data flow

1. A list node action requests expansion.
2. The list node resolves item keys to visible graph keys and loads them into
   the active `GraphMap`.
3. The list node upserts an `ordered-list` island with absolute `state.position`.
4. `GraphMap` emits island add/update signals.
5. `GraphView` reconciles the island through the ordered-list presenter.
6. The presenter positions/pins member nodes relative to island body position.

## Error handling

- Missing mounted graph map or island APIs should fail loudly.
- Missing presenter kinds should continue to fail visibly in `GraphView`.
- Invalid island position shapes should continue to raise explicit errors during
  normalization or presenter conversion.

## Testing

Focused tests should cover:

- list-created ordered-list islands preserve absolute island body position;
- unrelated drag-end reconciliation does not re-anchor the island to the list
  node;
- restored old-format islands without `state.position` do not overlap/re-anchor
  to the list node by source-key logic;
- existing list item/order/identity refresh behavior still works;
- GraphView island presenter tests still verify member positioning, pinning,
  label refresh, and removal cleanup.

Validation should follow the Space Fennel ladder: touched-file compile check,
constraints, focused Fennel tests, then broader validation if the implementation
surface expands.
