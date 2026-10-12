---
type: feature
status: shipped
parent-goal: core-platform
tags:
  - feature
  - layout
  - widget
  - ui
created: 2026-10-12
updated: 2026-10-12
---

# TreeView widget

## Summary

`assets/lua/tree-view.fnl` is a reusable old-widget-stack tree layout widget. It flattens caller-provided hierarchical data into visible row metadata, builds one row widget per visible row, and lays those row widgets out from their measured heights. It is intentionally domain-agnostic: callers adapt their own records into the tree API and keep domain behavior in their row widgets or owning view.

## Adapter API

`TreeView` is constructed with an options table and returns a normal widget build closure. Required options:

- `:roots` — array of root items supplied by the caller.
- `:key` — function `(item) -> string` used for stable row identity.
- `:children` — function `(item) -> array` returning child items, or `nil` for no children.
- `:row-builder` — function `(row, ctx) -> widget` that builds the visible row widget.

Optional options:

- `:name` — layout name; defaults to `"tree-view"`.
- `:row-gap` — vertical gap between measured row widgets; defaults to `0`.
- `:default-expanded?` — function receiving row metadata and returning the default expansion state when no stored state exists.
- `:expanded-keys` and `:on-expanded-change` — caller-owned expansion table and callback. If `:expanded-keys` is supplied, `:on-expanded-change` is required.

The built widget exposes `layout`, `refresh`, `set-roots`, `set-expanded`, `expanded?`, `visible-rows`, and `drop`.

## Row metadata

`TreeView` passes each visible row builder a metadata table:

- `:key` — stable key from the caller adapter.
- `:item` — original caller item.
- `:depth` — zero-based nesting depth.
- `:index` — one-based visible row index after flattening.
- `:parent-key` — parent row key or `nil` for roots.
- `:expanded?` — resolved expansion state for the row.
- `:has-children?` — whether the adapter reported children.
- `:toggle!` — callback that flips the row expansion state and refreshes the tree.

This metadata is visual/layout metadata for the tree. It does not imply ownership of caller records or application state.

## Expansion ownership

By default, `TreeView` owns only a private in-memory expansion table for the lifetime of the built widget. Callers that need explicit expansion control may pass `:expanded-keys` and handle `:on-expanded-change`; in that mode the caller owns the expansion table and any persistence policy.

Expansion state is UI projection state. Domain stores and graph topology should not persist `TreeView` internals. Callers decide whether expansion is ephemeral, view-local, or derived from row metadata.

## Row builder contract

The row builder owns all row-specific visuals and interactions. It must return a widget-like table with:

- `layout` — explicit `Layout` object with working `measurer` and `layouter` callbacks.
- `drop` — teardown method for any row-owned children, registrations, render resources, or interaction handles.

`TreeView` does not inspect row internals beyond `layout` and `drop`. Row widgets should keep domain actions, click routing, focus, selection, context menus, and activation semantics in the row widget or owning view.

## Layout and measurement behavior

`TreeView` measures every visible row widget before computing its own size. Its measured width is the maximum row width; its measured height is the sum of row heights plus `:row-gap` between rows.

During layout, rows are placed top-to-bottom within the tree layout using their measured heights. The tree assigns each row the tree's width and the row's measured height, then invokes the row's layouter. This supports variable-height rows, including rows that expand to include cards or other child widgets, without fixed-stride placement.

Refreshing roots or expansion state rebuilds visible row widgets and marks the tree layout dirty so the next layout pass remeasures and repositions rows.

## Lifecycle and drop ownership

`TreeView` owns the row widget instances it builds. Refreshing drops all previous visible row widgets before building the next visible set. Dropping the tree drops all current rows and then drops its own layout. Public methods fail after drop rather than silently operating on released widgets.

Callers still own the input data, adapter functions, and any caller-owned expansion table. Row widgets own their direct visual/interaction resources.

## Non-goals

- No virtualization or incremental windowing of very large trees.
- No graph-specific knowledge: no graph maps, graph nodes, topology, selection/focus keys, or graph commands.
- No domain data persistence.
- No legacy compatibility aliases for adapter option names.
- No automatic row interaction policy; row widgets provide interactions explicitly.

## Related

- [Layout widget engine](/dev/features/layout-widget-engine)
- [Graph doctrine](/dev/notes/graph)
