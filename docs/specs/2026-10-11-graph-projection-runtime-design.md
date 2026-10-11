# Graph Projection Runtime Design

## Context

`GraphView` currently dispatches between two largely separate view implementations:

- spatial graph view in `assets/lua/graph/view/init.fnl`;
- outline graph view in `assets/lua/graph/view/outline.fnl`.

Both are projections over the same `GraphMap`, but they do not share a formal runtime contract. Spatial graph view owns the most complete lifecycle machinery: persistence, camera capture/restore, initial camera policy, selection/focus helpers, node views, state capture/restore, and teardown. Outline separately implements only the methods it needed for rows, compact points, focus/selection, and commands. This asymmetry caused outline to miss graph-view lifecycle behavior such as camera state capture, even though outline should have separate camera state rather than share spatial camera state.

The goal is to clean up the architecture without moving outline into its own activity. Outline remains a `GraphMap.view_mode`; the graph activity remains the owner of activity integration.

## Design Goals

- Keep `GraphMap` as the owner of graph-map interaction state: `view_mode`, `outline_root_keys`, `selected_node_keys`, and `focused_node_key`.
- Keep graph topology and domain data out of view/runtime persistence.
- Make spatial and outline projections share graph-view lifecycle mechanisms through one explicit runtime contract.
- Keep projection-specific behavior separate: spatial layout/edges/islands/LOD and outline row/compact-point layout should remain in their projection modules.
- Keep spatial and outline camera/view state separate while using the same capture/restore mechanism.
- Preserve existing graph commands and graph activity behavior.

## Non-Goals

- Do not move outline into a separate activity in this pass.
- Do not change graph topology, graph persistence, key loaders, or graph terminology.
- Do not rewrite spatial layout, island handling, or compact-point rendering beyond contract integration.
- Do not make outline rows persistent graph topology.

## Recommended Architecture

Introduce a shared graph projection runtime layer under `assets/lua/graph/view/`.

### Runtime Contract

Create `graph/view/runtime.fnl` as the shared lifecycle shell. It should install the public graph-view contract on both spatial and outline views:

- update/drop and dropped-state assertions;
- node-view construction and capture/restore delegation;
- graph-map selection/focus state capture;
- graph-view state capture/restore shape;
- camera state methods;
- node actions and focused action integration;
- shared remove/open/reveal wrappers where projection adapters provide the projection-specific behavior.

The graph activity should consume this required contract instead of probing optional view internals such as `view.persistence` or optional `capture-camera-state!` hooks.

### Projection Adapters

Spatial and outline remain separate projection implementations, but each supplies adapters into the runtime:

- current mode key (`"spatial"` or `"outline"`);
- visible nodes;
- selected/focused node resolution;
- selection/focus mutation;
- reveal/open behavior;
- projection update/start-layout behavior;
- projection-specific state capture/restore;
- initial camera policy;
- projection-specific drop logic.

This keeps the spatial view free to own ForceLayout, edges, labels, islands, movables, and LOD, while outline owns row construction, compact projections, row focus nodes, and expanded-card behavior.

### Shared Selection and Focus Helpers

Move duplicated selection/focus command behavior into an adapter-based helper, likely `graph/view/projection-selection.fnl`. Both projections should use the same implementation for:

- selected-node count;
- select all visible;
- clear selection;
- focused-node selected checks;
- select/add/remove/toggle focused node;
- focus selected node.

`graph/view/focused-actions.fnl` should expose a generic dependency shape so both projections can share focused node action slots, menu opening, copy key, remove from map, and reveal focused node, while preserving projection-specific menu position and reveal behavior.

### Mode-Specific State

Persist projection state by mode. Spatial and outline must not share camera state, but they should use the same mechanism.

The canonical persisted shape should include a mode-state table, for example:

```fennel
{:mode_states
 {"spatial" {:camera ... :projection ...}
  "outline" {:camera ... :projection ...}}
 :selected_node_keys [...]
 :focused_node_key "..."}
```

Legacy spatial camera metadata should continue to load and migrate into spatial mode state. Malformed mode state should fail loudly with graph-view/persistence context.

### Graph Activity Integration

`graph-activity-unit.fnl` remains the activity integration point. It should continue to:

- activate the graph scene/canvas slots;
- set the graph background from the active theme;
- instantiate the current projection through `graph/view.fnl`;
- handle map switching and view-mode switching;
- provide graph commands, sidebar, root actions, and update hooks.

However, it should call required runtime contract methods such as `view:saved-camera-state`, `view:capture-camera-state!`, `view:capture-state`, and `view:restore-state`, rather than depending on spatial-only internals.

## Data Flow

1. `GraphView(options)` continues to dispatch on `graph-map.view_mode`.
2. The chosen projection creates projection-specific local state.
3. The projection initializes `GraphViewRuntime` with shared dependencies: `graph-map`, `ctx`, `selector`, `focus`, `node-views`, `persistence`, `camera`, and `data-dir`.
4. The projection passes adapter functions to the runtime.
5. Runtime installs shared public methods and state/camera handling.
6. Activity code interacts with the shared public contract regardless of mode.

## Error Handling

- Missing required adapter methods should assert with explicit graph-view runtime context.
- Activity code should fail loudly when a constructed graph view does not implement the required contract.
- Malformed persisted camera/mode state should fail with `GraphViewPersistence` context.
- Projection drop must remain idempotent and avoid double-dropping compact points, focus nodes, selector entries, or node views.

## Testing Strategy

Focused tests should define the shared contract before implementation proceeds:

- Both spatial and outline expose the same required public lifecycle methods.
- Outline has camera methods through the shared runtime even when its initial camera policy is intentionally a no-op.
- Spatial and outline camera states persist separately.
- Switching spatial ⇄ outline preserves `GraphMap` selection/focus while retaining mode-specific state.
- Existing outline compact point interaction and teardown tests continue to pass.
- Existing spatial camera persistence, layout, islands, labels, and graph activity tests continue to pass.

Validation order for implementation:

1. `make fennel-check`
2. `make constraints`
3. focused graph view, outline, camera persistence, compact projection, and graph activity tests
4. broader `make test` because this changes graph activity lifecycle and graph view contracts

## Rollout Plan

Implement incrementally to avoid a giant rewrite:

1. Add tests and mode-specific camera persistence support.
2. Introduce the runtime contract and selection/focus helper modules.
3. Migrate outline to the shared runtime first, because it is smaller and exposes the current contract gaps.
4. Migrate spatial to the shared runtime while preserving spatial internals.
5. Tighten graph activity to require the contract instead of optional hook duck typing.
6. Update graph docs with the projection runtime contract and mode-state ownership.

## Acceptance Criteria

- Spatial and outline are still selected by `GraphMap.view_mode` through `graph/view.fnl`.
- Both projections implement the same graph-view runtime contract.
- Spatial and outline camera state are separate but share capture/restore logic.
- Graph activity no longer relies on spatial-only `persistence` internals for camera handling.
- Existing graph commands work in both modes.
- Graph core/topology and `GraphMap` ownership boundaries remain unchanged.
