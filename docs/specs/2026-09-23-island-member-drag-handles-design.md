# Island member drag handles

## Context

Graph presentation islands are independent map-local layout bodies. For
`ordered-list` islands, the presenter lays members out vertically from the
island body position stored in `island.state.position`.

Today, normal member drag remains effectively snap-back: `GraphView` moves the
dragged node while the pointer is down, then island reconciliation rewrites all
member positions from the presenter's island body. Legacy ordered-list islands
without `state.position` also use the first member as a fallback origin, which
can make the first member behave like an accidental island handle while other
members snap back.

## Goal

Allow alt-dragging any member of an island to move the whole island, with the
whole-island movement applied only on drag end. During the drag, only the
dragged member follows the pointer. On drag end, the island presenter derives a
new island body state from the dropped member position, `GraphMap` persists that
state, and normal island reconciliation places all members relative to the new
body.

## Non-goals

- Do not add user-facing configuration for island drag policies in this slice.
- Do not move the whole island live while the pointer is dragging.
- Do not implement list reordering through graph node drag.
- Do not make `GraphView` understand ordered-list index or spacing math.
- Do not change ownership of domain list data; list order remains owned by the
  list entity store.

## Design

### Presenter-owned drag-end state

Island movement is presenter-owned. `GraphView` detects that an alt-drag ended
on a graph node, finds any islands containing that node, and delegates the state
derivation to the island host/presenter. The presenter answers the question:
"Given this member's dropped graph position, what should the island state be so
the member remains there after reconciliation?"

This keeps generic graph interaction code independent from each island kind's
layout rules. Future island presenters can choose their own math or decline to
participate by not implementing the hook.

The intended hook shape is:

```fennel
presenter.member-drag-end-state(island host request) -> state-table-or-nil
```

Where `request` includes at least:

- `member-key`: the dragged member node key;
- `position`: the dropped member graph position.

The returned state is a complete replacement `island.state` table suitable for
`GraphMap:update-island`. A `nil` return means the presenter does not handle
that member/request.

### Ordered-list behavior

The ordered-list presenter should derive the new body position from its current
layout, not from hardcoded math in `GraphView`.

For a member dropped at `P`:

1. Compute the member's current expected placement `L` using the existing
   ordered-list layout function.
2. Compute `delta = P - L`.
3. Compute the current island body position `B` using the presenter's existing
   base-position rules.
4. Return copied state with `position = B + delta` as a JSON-safe `[x y z]`
   array.

For ordered-list layouts this is equivalent to index/spacing math, but it is
more future-proof because it derives from the presenter's own layout result.
Dragging the second item down by 100 units moves the island body down by 100
units; after reconciliation, the second item remains at the drop location and
the first/other members are repositioned around it.

Legacy ordered-list islands without `state.position` should continue to use the
first-member fallback until a member is alt-dragged. Alt-dragging such an island
upgrades it by writing an explicit `state.position`.

### GraphView data flow

1. Movables begin an alt-drag on a graph node and `GraphView` records that the
   active drag is alt-modified.
2. During drag, `GraphView` updates only the dragged node position as it does
   today.
3. On drag end, before island reconciliation, `GraphView` asks the island host
   for next island state for each island containing the dragged node.
4. For each non-nil state, `GraphView` updates the island through
   `GraphMap:update-island`.
5. Existing island reconciliation runs and applies the new presenter state to
   all members.

Normal non-alt drags keep current snap-back behavior.

## Error handling

- Missing presenter kinds should fail visibly, matching existing island
  reconciliation behavior.
- Missing `GraphMap:update-island` should fail loudly when an alt island move is
  attempted.
- Invalid request data, missing member keys, and invalid positions should raise
  explicit errors at the host/presenter boundary.
- Presenters without the optional drag-end hook should be treated as not
  supporting this interaction, not as an error.

## Testing

Focused tests should cover:

- ordered-list presenter derives a new state position from dragging the first,
  second, or later member;
- existing state keys such as `list-key`, `interaction-policy`, and `spacing`
  are preserved;
- a legacy island without `state.position` receives an explicit position after
  alt-drag;
- island host delegates to the presenter hook and handles presenters without the
  hook;
- GraphView alt-dragging a non-first member updates `island.state.position` on
  drag end, then reconciliation keeps the dragged member at its dropped position
  and moves other members around it;
- non-alt member drag continues to snap back.

Validation should follow the Space Fennel ladder: compile check, constraints,
focused graph island tests, then broader validation as required by the change
surface.
