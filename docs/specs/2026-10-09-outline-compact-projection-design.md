# Outline Mode as a Compact GraphView Projection

## Summary

Outline mode should not be a list widget that happens to draw graph-looking
circles. It is an alternate projection of the active `GraphMap` and must use
the same compact graph-node interaction semantics as spatial `GraphView`.

The current outline implementation derives the right rows from graph-map
topology, but it still registers full-width row rectangles as clickable,
selectable, and focusable targets. That keeps producing behavioral drift:
clicking row whitespace can focus a node, historical click behavior mutated
selection, and fixes have repeatedly patched row-specific semantics instead of
sharing the GraphView compact-node model.

This design resets outline internals around compact node presentations. Outline
continues to provide deterministic tree positions and labels, but the compact
node point owns interaction handles. Rows and labels are layout/visual artifacts
only.

## Goals

- Make outline mode feel like the same graph view arranged in a tree, not a
  separate list control.
- Reuse or extract compact GraphView node behavior so spatial and outline modes
  cannot drift on click, selection, focus, rings, right-click, double-click, and
  teardown semantics.
- Preserve outline projection doctrine: ordered roots, outgoing visible
  graph-map edges only, first occurrence wins, no hidden materialization.
- Preserve `GraphMap` ownership of selected and focused graph node keys.
- Keep implementation bounded to GraphView runtime/rendering code and tests.

## Non-goals

- No graph core or graph-map persistence format redesign.
- No hidden relationship expansion or topology materialization.
- No board migration or unrelated graph-map UI work.
- No global changes to clickables, intersectables, focus manager, ObjectSelector,
  or theme systems.
- No label/row click affordance in this pass. If label clicks are desired later,
  they must be specified as a deliberate UX extension rather than treated as
  GraphView parity.

## Current Problems

`assets/lua/graph/view/outline.fnl` currently computes outline rows correctly,
but then creates a row target with `row-width`/`row-height` hit testing and
registers that row with clickables, selector, and focus bounds. The compact point
is only a visual child of the row record.

Spatial `GraphView` does the opposite: `GraphNodePresentation.compact-point` is
the presentation object and is the clickable/selectable/focusable target. Click
requests focus only. Object selection owns selection. Right-click focuses and
opens node actions. Double-click uses the compact node expansion behavior.

The mismatch means outline mode can pass tests that exercise row behavior while
still failing the user's expectation that outline is simply the graph view laid
out differently.

## Design Direction

Use a shared compact graph-node projection runtime for both spatial and outline
compact nodes.

The runtime should own the lifecycle of compact node presentations:

- create `GraphNodePresentation.compact-point` with the same layer order, depth
  offsets, focus ring sizing, selection ring sizing, and theme colors as current
  spatial `GraphView`;
- register the point presentation, not a row proxy, with `Clickables`;
- register the point presentation, not a row proxy, with `ObjectSelector`;
- create and attach a focus node whose bounds follow the point/card
  presentation;
- wire click to focus only;
- wire right-click to focus and open the same node action menu path;
- wire double-click/activation to the same compact node expansion semantics;
- update visual layers when selection or focus changes;
- unregister clickables, selector entries, focus nodes, and presentation handles
  on detach/drop/rebuild.

Spatial `GraphView` will keep its ForceLayout, edge layout, labels, movables,
island presenters, persistence, and expanded-card policy. The shared runtime
only covers compact node presentation/interaction lifecycle.

Outline mode will keep `GraphOutline.build-rows` and deterministic tree
positioning. For each visible row it will attach a compact projection at the row
point position. The row record may retain metadata for ordering and label
placement, but it must not be the hit target, selectable, or focus target.

## Outline Interaction Contract

- Clicking the compact point focuses that graph node and does not change
  selection.
- Clicking row whitespace or label area outside the compact point does nothing.
- Box/object selection selects outline compact points and synchronizes
  `GraphMap.selected_node_keys`.
- Right-clicking an outline compact point focuses the graph node and opens the
  same node action menu path as spatial compact nodes.
- Double-clicking or activating an outline compact point uses compact graph-node
  expansion semantics, not row/full-view-open semantics.
- Explicit selection commands still mutate selection: reveal with `select?`,
  select all visible nodes, clear selection, select focused node, add/remove
  focused node from selection, and selector-to-map synchronization.
- Rebuilds remove stale compact point handles before creating new visible
  projection handles.

## Data and Ownership

- `GraphMap` owns `view_mode`, `outline_root_keys`, `selected_node_keys`, and
  `focused_node_key`.
- `GraphOutline.build-rows` derives visible row order and depth from graph-map
  topology only.
- The shared compact projection runtime owns render handles, click registrations,
  selector registrations, focus nodes, and compact presentation handles.
- Outline labels are render-only and derive their position from the current point
  presentation size/position. They do not own interaction state.

## Testing Strategy

Tests must lock behavior before implementation:

- Unit real-hit-testing should prove compact point hits focus, while row
  background/label hits do not focus, select, open, or menu.
- Unit selector/focus tests should prove selector entries are compact point
  presentations rather than row proxy objects.
- Unit lifecycle tests should prove rebuild/drop unregister compact point
  clickables/selectables/focus nodes and leave no stale row targets.
- Non-snapshot E2E tests should use the real app harness and pointer path to
  prove point-only click/focus behavior and row-whitespace non-interaction.
- Spatial GraphView selection/focus tests must continue to pass because the
  shared runtime touches spatial compact nodes.

Validation order follows Space Fennel policy: compile check, constraints,
focused Fennel tests, focused E2E repros, then broader `make test` because the
shared compact runtime is used by both spatial and outline renderers.

## Risks and Mitigations

- **Risk: extracting too much from spatial GraphView.** Keep ForceLayout, edges,
  labels, movables, islands, and persistence in spatial GraphView. Extract only
  compact presentation/interaction lifecycle.
- **Risk: breaking expanded-card behavior.** Treat current spatial compact
  double-click/activation behavior as the source of truth and preserve it while
  moving code.
- **Risk: stale handles on outline rebuild.** Add lifecycle tests for clickables,
  selector entries, focus nodes, and drop cleanup.
- **Risk: accidental label click affordance.** Add negative tests for row
  background/label coordinates.

## Acceptance Criteria

- Outline compact point click focuses the node and preserves selection.
- Outline row whitespace and labels outside the point do not focus or select.
- Outline selector entries are compact point presentations, not row targets.
- Outline focus bounds match compact point/card bounds, not full row rectangles.
- Right-click and double-click on outline points match spatial compact node
  behavior.
- Spatial compact node behavior remains unchanged.
- Existing outline topology projection behavior remains unchanged.
- Documentation states that outline rows/labels are visual layout only and that
  compact node presentations own interaction.
