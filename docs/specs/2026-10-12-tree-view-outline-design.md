# Reusable TreeView for Graph Outline Design

## Problem

Graph outline mode currently lays out rows by hand in `assets/lua/graph/view/outline.fnl` with a fixed `row-height` stride and direct point/label placement. That is a design smell: outline is expressing a tree/list UI with raw coordinates instead of a reusable widget abstraction. The result is excessive vertical spacing today, and the deeper issue is that any future row sizing, expansion, indentation, scrolling, or reuse would have to be reimplemented inside the graph projection.

## Goals

- Introduce a reusable Fennel `TreeView` widget for hierarchical row layout.
- Replace graph outline fixed-stride row placement with widget-driven measured layout.
- Preserve graph outline behavior by default: all reachable outline rows remain visible unless a later feature explicitly opts into collapsed defaults.
- Keep graph-specific interaction semantics out of the generic tree widget.
- Preserve graph doctrine:
  - graph core persists topology only;
  - `GraphMap` owns `view_mode`, `outline_root_keys`, `selected_node_keys`, and `focused_node_key`;
  - outline rows are visual projection state, not topology or domain data;
  - compact graph node presentations own graph node click, focus, selection, menu, activation, and teardown semantics.

## Non-Goals

- Do not port outline rendering to `next-app` in this pass.
- Do not introduce virtualized tree rendering yet.
- Do not persist tree expansion state in graph core or `GraphMap`.
- Do not change graph topology traversal semantics or outline root semantics.
- Do not make the generic tree widget aware of graph maps, graph nodes, selectors, focus managers, or graph commands.

## Recommended Approach

Build `TreeView` on the existing old widget stack (`Layout`, `Flex`, and the existing widget builder/drop conventions), not on `next-app`.

This is the lowest-risk path because graph outline already uses old-stack graph presentation pieces:

- `GraphNodePresentation.compact-point` / `LayeredPoint`;
- `CompactNodeProjection` for compact graph node interaction;
- `GraphNodePresentation.card-builder` for expanded cards;
- existing clickables, selector, focus, menu, and graph view runtime systems.

`next-app` can remain a future migration target, but bridging graph compact presentations and focus/click lifecycle into `next-app` would broaden this work beyond the current outline layout problem.

## TreeView Contract

`TreeView(opts)` is a reusable old-style widget builder. It consumes generic tree data through adapter callbacks and calls a caller-provided row builder for visible rows.

Required options:

- `:roots` — initial root items or root keys.
- `:key` — `(fn [item] -> string)` stable key for an item.
- `:children` — `(fn [item] -> array)` child items for an expanded item.
- `:row-builder` — `(fn [row] -> builder|widget)` builds one visible row widget.

Optional options:

- `:has-children?` — explicit child indicator without loading children eagerly.
- `:expanded-keys` — caller-owned expansion lookup.
- `:on-expanded-change` — notification when expansion changes.
- `:default-expanded?` — default expansion policy for items not present in caller-owned state.
- `:indent-width`, `:row-gap`, `:scroll?` — visual/layout policy only.

Visible row metadata passed to `row-builder`:

```fennel
{:key key
 :item item
 :depth depth
 :index index
 :parent-key parent-key
 :expanded? expanded?
 :has-children? has-children?
 :toggle! toggle!}
```

`TreeView` public methods:

- `refresh` — recompute visible rows and update child widgets.
- `set-roots` — replace roots and refresh.
- `set-expanded` — set expansion for a key.
- `expanded?` — query expansion for a key.
- `visible-rows` — return current visible row metadata.
- `drop` — terminal teardown of owned row widgets and layout resources.

## Expansion State Ownership

Use a hybrid model:

- By default, `TreeView` owns transient expansion state internally.
- Callers may provide `expanded-keys` and `on-expanded-change` for caller-owned state retention.
- The widget never persists expansion by itself.

For graph outline integration, preserve current behavior by configuring graph outline rows as expanded by default so all reachable rows are visible. Collapsed tree behavior can be added later by supplying caller-owned outline expansion state outside graph topology.

## Graph Outline Integration

Graph outline should adapt the active `GraphMap` projection into `TreeView` without leaking graph concerns into the reusable widget.

Responsibilities remain split as follows:

### Generic TreeView owns

- Hierarchical flattening.
- Row order and depth metadata.
- Measured row/list layout.
- Expansion/collapse UI state.
- Direct ownership/drop of generic row widgets it creates.

### Graph outline owns

- Mapping active `GraphMap` roots and outgoing visible graph-map edges into tree items.
- Graph-specific row widget construction.
- `GraphMap` selected/focused key synchronization.
- Compact graph node projection callbacks.
- Node menus, reveal/open behavior, expanded graph cards, and graph projection runtime integration.

### Graph row widget owns

Create `assets/lua/graph/view/outline-row-widget.fnl` as a graph-specific row composite. Each row widget should own:

- its explicit `Layout`;
- a compact graph node projection for collapsed/compact state;
- a label widget;
- optional expanded graph card;
- direct child/handle teardown.

The row widget may receive graph-specific dependencies (`clickables`, `selector`, `focus`, `pointer-target`, callbacks), but those dependencies do not move into `TreeView`.

## Layout Behavior

Rows should be measured and laid out from content instead of using a global fixed stride.

Collapsed row height should derive from:

- compact point visible size;
- label measured height;
- configured vertical padding / row gap.

Expanded row height should derive from:

- compact summary row height;
- expanded card measured/layout size;
- configured gap between summary and details.

Indentation should be a visual layout concern based on row depth, not a graph topology mutation.

## Error Handling and Lifecycle

- `TreeView` asserts on missing required adapter callbacks and row builders.
- `TreeView` must fail loudly if public methods are called after `drop`.
- Composite row widgets drop direct child widgets and graph projection handles they own.
- `Layout.drop` is not treated as child widget teardown; owners explicitly drop owned children.
- Graph outline rebuilds must avoid double-dropping compact projections, focus nodes, selector entries, and expanded cards.

## Testing Strategy

### TreeView tests

- Depth-first visible row flattening.
- Expansion/collapse behavior.
- Default-expanded policy.
- Caller-owned `expanded-keys` and `on-expanded-change`.
- Row metadata fields (`key`, `item`, `depth`, `parent-key`, `expanded?`, `has-children?`).
- Variable row measurement/layout without graph dependencies.
- Drop behavior and post-drop guard failures.

### Graph outline tests

- Visible row order and depth match current outline traversal.
- Default graph outline remains fully expanded / all reachable rows visible.
- Row placement is no longer computed from hardcoded index stride.
- Selection, focus, selector sync, menu, reveal/open, activation, expanded-card, and empty-state behavior remain intact.
- Compact point whitespace behavior remains unchanged: compact node presentations own interaction; row whitespace does not become graph-node interaction.

### Validation order

For Fennel-facing implementation:

1. touched-file `tools.fennel-check` or `make fennel-check`;
2. `make constraints`;
3. focused `TreeView` and graph outline tests;
4. graph outline E2E/snapshot validation when visual placement or click routing changes;
5. broader `make test` because this touches shared UI and graph projection behavior.

## Acceptance Criteria

- A reusable `TreeView` exists and has tests with no graph dependencies.
- Graph outline uses `TreeView` / row widgets for layout instead of hardcoded index-based row stride.
- Graph outline preserves current all-visible default behavior.
- Graph-specific state ownership remains with `GraphMap` and graph outline adapters, not `TreeView`.
- Compact graph node interaction semantics remain owned by `CompactNodeProjection` / graph row widgets.
- Documentation explains the reusable tree view and graph doctrine boundary.
