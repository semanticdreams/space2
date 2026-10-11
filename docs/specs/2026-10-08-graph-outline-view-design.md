# Graph Outline View Design

## Summary

Add an alternate graph presentation mode that renders the active `GraphMap` as an indented outline. The outline uses the same graph-addressable objects and map-local interaction context as the existing spatial graph view, but it projects only nodes reachable from user-selected root keys by following outgoing graph-map edges. Nodes appear once at their first traversal position; later cycle or shared-node encounters are skipped.

This is a view mode for the same active graph map, not a companion panel. Existing graph activity behavior that is not spatial-renderer-specific should continue to work: map switching, selection/focus, opening node views, node action menus, graph map sidebar state, and graph leader commands where their semantics apply.

## Goals

- Let users switch the active graph map between the existing spatial graph view and a compact indented outline view.
- Let users dynamically set the outline root from the current focused node or exactly one selected node.
- Persist outline mode and outline root keys per `GraphMap`, because they are task/map-local interaction state.
- Preserve graph doctrine: graph core remains an exposure/adaptor layer, graph maps own visible topology and interaction context, and renderers own runtime UI handles.
- Avoid forcing general graph topology into a tree model; outline rows are a projection over graph-map edges.

## Non-Goals

- No companion/sidebar outline in this phase.
- No inline preview cards inside outline rows.
- No outline-specific domain persistence or graph-core persistence.
- No graph edge reordering UI.
- No multi-root editing UI beyond internal support and persisted state.
- No hidden relationship expansion; the outline traverses only graph-map visible edges and nodes.

## User Experience

The graph activity gains an outline mode toggle. In spatial mode, behavior remains unchanged. In outline mode, the graph canvas area is replaced by compact rows:

```text
Root node
  Child A
    Grandchild A1
  Child B
    Grandchild B1
```

Rows show node identity using the same display concepts as compact graph labels where possible: label text, kind badge/status affordances when available, selected/focused state, and action/open affordances. Row activation opens the full node view or panel through existing graph node-view wiring. Row context menus reuse node action construction, excluding inline-preview-specific actions.

The initial root command replaces the outline root list with the focused node key. If no node is focused and exactly one node is selected, the selected node becomes the root. If no focused node exists and selection is empty or ambiguous, the command fails loudly or reports explicit graph-native status instead of silently choosing.

Internally the root state is a list, so later UI can support multiple roots without changing persistence or traversal contracts. The first UI only sets/replaces the list with one key.

## Architecture

### Ownership

- `Graph` remains the shared key-loader/resolver/adaptor layer. It does not store outline state.
- `GraphMap` owns map-local outline interaction state:
  - `view_mode`: `"spatial"` or `"outline"`.
  - `outline_root_keys`: ordered list of visible graph node keys.
- A pure outline projection module reads `GraphMap.nodes` and `GraphMap.edges` and produces row records.
- A new outline renderer/controller owns outline row widgets, clickable/focusable registrations, and runtime lifecycle.
- The existing spatial `GraphView` remains the default and continues to own force layout, points, labels, edge lines, movables, camera, and spatial persistence.

This separation keeps traversal/persistence in the map layer, rendering in the view layer, and domain data in owning systems.

### View Mode Dispatch

The graph activity continues to construct a graph view for the active `GraphMap`. The `GraphView` factory dispatches by `graph-map.view_mode`:

- `"spatial"` or missing: existing spatial renderer.
- `"outline"`: outline renderer.

When the active graph map's `view_mode` changes while graph activity is active, the activity captures applicable state, drops the current renderer, and rebuilds the renderer for the same active graph map. Map switching already follows capture/drop/restore patterns and should read the target map's persisted view mode.

### Outline Projection

The outline projection is deterministic and side-effect-free:

1. Normalize roots to visible, unique graph-map node keys in input order.
2. Build outgoing child lists from visible graph-map edges.
3. Traverse roots depth-first in root order.
4. Follow outgoing edges only.
5. Emit each node the first time it is reached.
6. Skip missing targets, unreachable graph-map nodes, repeated nodes, and cycle encounters.

Child order follows graph-map edge insertion/order. If an implementation path cannot guarantee stable edge enumeration for a group, it falls back to target label/key order for deterministic rendering.

Rows include at least:

```text
{:key string
 :node graph-node-adapter
 :depth integer
 :parent-key string-or-nil}
```

If future multi-root or duplicate-row needs arise, row identity can grow to include a path or row id, but the initial first-occurrence rule keeps node-key selection/focus semantics simple.

### Selection and Focus

Graph-map selection and focus stay node-key-based. Clicking a row selects/focuses that node in the active `GraphMap`. Commands such as open focused node, copy focused key, remove from map, and focused node actions should work through shared focused-action helpers rather than spatial-only internals.

`select-all-visible-nodes` in outline mode selects only nodes currently visible in the outline projection, not every node in the graph map. `reveal-node` succeeds only if the node is visible under the current roots; otherwise it reports an explicit not-visible condition rather than materializing or changing roots implicitly.

### Node Actions and Open Behavior

Node action construction should be reusable between spatial and outline renderers. Spatial mode includes preview-card actions. Outline mode excludes inline-preview actions but keeps graph-map and node actions such as Open, Copy key, Remove from Map, node-provided actions, and Set Outline Root.

Opening a row delegates to existing graph node-view/panel wiring. Graph nodes continue to expose plain view constructors and actions; they do not track renderer instances.

### Persistence

`GraphMap:capture-state` includes `view_mode` and `outline_root_keys`. Restore defaults missing legacy state to `"spatial"` and an empty root list. Root restore validates against visible restored nodes, preserving only roots that remain visible in the graph map. Removing nodes from a graph map prunes removed keys from outline roots.

This is map-local interaction state. It is not graph core state and not domain data.

## Edge Cases

- **No roots:** outline mode renders an explicit empty state with guidance to set a root from focus/selection.
- **Root removed or invalid after restore:** the root is pruned; if no roots remain, the empty state is shown.
- **Cycle:** traversal stops when it reaches a previously emitted key.
- **Shared child:** the child appears under the first parent encountered by traversal order and is skipped for later parents.
- **Unreachable map nodes:** hidden in outline mode but still present in the active graph map and visible again in spatial mode or after root changes.
- **Incoming-only relationship:** ignored unless the target is reached through some outgoing path from a root.

## Testing Strategy

Focused tests should cover:

- Pure outline projection: root ordering, outgoing-edge-only traversal, hidden unreachable nodes, cycle handling, repeated-node first occurrence, missing roots/targets, and deterministic child order.
- `GraphMap` state: default spatial mode, root normalization, signal emission, capture/restore, map manager persistence, and root pruning on node removal.
- Outline renderer: row count/order/depth, compact-only behavior, selection/focus updates, row activation opening node views, node action menu availability, and absence of preview-card actions.
- Commands/activity: toggling view mode, setting root from focus/selection, rebuilding active renderer on view-mode change, and preserving mode/roots across map switching.
- Regression: existing spatial graph view, graph map, graph map manager, graph selection/focus commands, and graph activity tests remain green.

Validation should follow Space Fennel workflow: `make fennel-check`, `make constraints`, focused graph tests, and broader `make test` because the change touches graph view construction, activity lifecycle, command routing, and map persistence.

## Risks and Mitigations

- **Accidentally coupling outline to force-layout internals:** keep outline renderer separate and share only focused-action/node-action helpers.
- **Treating graph topology as a tree:** document and test first-occurrence traversal over a general directed graph.
- **Losing graph activity features:** extract shared non-spatial action/focus behavior instead of duplicating spatial-only code.
- **Persisting view state in the wrong layer:** keep `view_mode` and `outline_root_keys` on `GraphMap`; keep runtime row handles in the renderer only.
- **Silent invalid root behavior:** filter during restore/removal, but user-initiated commands should report invalid or ambiguous selection explicitly.

## Acceptance Criteria

- Users can toggle the active graph map between spatial and outline modes.
- Users can set the outline root from the focused node or exactly one selected node.
- Outline mode displays compact indented rows reachable from roots by outgoing graph-map edges.
- Nodes in cycles or shared paths appear only at their first traversal position.
- Unreachable graph-map nodes are hidden in outline mode without being removed from the map.
- Row selection/focus, opening full node views, and node action menus work in outline mode.
- Each graph map restores its own view mode and outline roots when switching maps.
- Existing spatial graph behavior remains the default and passes existing tests.
