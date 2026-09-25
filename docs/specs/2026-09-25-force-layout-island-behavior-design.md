# Force-Layout Island Behavior Design

Date: 2026-09-25

## Context

Graph-view islands are new presentation objects that let a `GraphMap` group map-local node presentations without changing graph topology or domain ownership. Ordered-list islands currently participate in force layout as one aggregate participant, with unpinned members omitted as individual force bodies and repositioned from the island presenter.

The current behavior is usable but visually unnatural. The main observed gaps are:

- the aggregate force position is the ordered-list origin/first member, not the island's visual center;
- island movement expectations are implicit and only partially covered by tests;
- pinned or expanded members can make an island appear immobile unless the aggregate/pin exception is explicit.

## Decision

Treat each unpinned island as **one aggregate visual body** in force layout. The aggregate body should behave like a larger node/card whose **visual center** participates in force layout.

This is preferred over modeling the island as a rigid group of independently simulated member nodes. A rigid compound-body model could eventually support richer per-member physics, but it would require new solver semantics and more fragile tests. The aggregate-body model matches the existing `GraphMap` island record, presenter-owned placements, and `GraphViewLayout` aggregate participant seam.

## Expected Behavior

- An unpinned island contributes one aggregate force participant.
- The aggregate participant's force position represents the island body's visual center.
- Ordered-list presenters may continue placing members from an origin internally, but they must expose enough anchor information for `GraphViewLayout` to convert between force-center position and member placements.
- All unpinned island members move together by the aggregate body's delta and preserve presenter spacing.
- External edges connected to any unpinned island member affect the aggregate force participant.
- Explicitly pinned or expanded island members remain independent force participants and are not moved by aggregate refresh until they are unpinned/collapsed.
- Runtime island movement remains cached in the `GraphView` island layout runtime and is flushed to `GraphMap` state only through the existing capture path.

## Architecture

The graph doctrine remains unchanged:

- graph core/topology does not own island layout behavior;
- `GraphMap` persists map-local island records;
- presenters own island-specific placement rules;
- `GraphViewLayout` adapts presenter records into force-layout participants.

The implementation should extend the island aggregate layout contract rather than introduce domain-level graph semantics. A presenter can describe the relationship between its persisted body position, force anchor, and member placements. For ordered lists, the natural anchor is the bounding-box center of the vertical list.

## Data Flow

1. `GraphView` asks the island host for aggregate layout records.
2. The ordered-list presenter returns members, placement function, and center-anchor metadata/behavior.
3. `GraphViewLayout` adds one force participant for each island at the force-center position.
4. During force refresh, `GraphViewLayout` converts the moved force center back into the presenter's body/origin position, records the runtime island position, and applies member placements.
5. Unpinned members are updated as a unit; pinned members keep their independent positions.

## Testing Expectations

Add or update focused Fennel tests so the behavior is explicit:

- an unpinned ordered-list island moves as a force-layout unit;
- island member deltas remain equal and ordered-list spacing is preserved;
- a normal node and an island with the same visual center receive comparable force-layout movement in a symmetric setup;
- external edges to unpinned island members affect the aggregate body;
- pinned/expanded members are documented by tests as excluded from aggregate movement;
- runtime island body position remains preserved through reconciliation and membership refresh.

## Non-Goals

- Do not add compound-body physics or per-member rigid constraints to the C++ force solver.
- Do not change graph topology or make graph core own island layout semantics.
- Do not make pinned/expanded members follow aggregate movement.
- Do not eagerly persist runtime force movement outside the existing capture/flush path.

## Open Follow-Up

The persisted `state.position` field currently acts like an ordered-list origin. The implementation should avoid unnecessary state migration if possible by keeping persisted state as the presenter body/origin position and translating to/from a center force anchor inside the presenter/layout adapter. A future schema change can be considered only if center-as-persisted-position becomes broadly desirable.
