---
type: feature
status: planned
parent-goal: graph-foundation
tags:
  - feature
  - graph
  - ui
created: 2026-07-14
updated: 2026-09-15
---

# Graph browsing & editing

## Summary

Refine the graph browsing and editing experience so users can navigate, manipulate, and understand objects exposed through the graph fluently.

## Motivation

Currently objects exist and are visible in the graph, but navigating between them, inspecting their contents, and editing relationships is not yet smooth. This is central to making the graph the primary interface for everything.

## Design

- Improve the graph view widget for smoother navigation
- Add keyboard-driven browsing (search, jump, expand/collapse)
- Make node property inspection fast with inline editing
- Support drag-to-link between objects exposed in the graph
- Keep interaction model consistent with rest of space UI
- Order graph node context menus with graph-view actions first, including `Copy key`, then a first-class separator, then adapter-provided `node.actions`; graph-map actions such as open, expand/collapse, cube presentation, and removal stay owned by `GraphView`.

## Tasks

- [ ] Audit current graph browsing pain points
- [ ] Design improved navigation keybindings
- [ ] Implement keyboard-driven focus/selection in graph view
- [ ] Add inline property editing for graph nodes
- [ ] Implement drag-to-link between objects exposed in the graph
- [ ] Test with realistic-sized graphs

## Related

- Goal: [Graph Foundation](/dev/features/graph-foundation)
- Depends on: [Activities Architecture](/dev/features/activities) — graph browsing is exposed through the HomeWorld graph activity
- ADRs: [Graph as Universal Interface](/dev/adrs/adr-graph-as-universal-model), [Composable States](/dev/adrs/adr-composable-states)
- See: [Graph Identity](/dev/notes/graph-identity), [Graph View As Widget](/dev/notes/graph-view-as-widget), [Graph Vs Entities](/dev/notes/graph-vs-entities)
