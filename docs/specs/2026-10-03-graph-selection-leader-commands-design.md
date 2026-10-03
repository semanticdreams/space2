# Graph Selection Leader Commands Design

## Context

Graph leader commands already expose selected-node presentation actions under
`SPC g p ...`; for example, `SPC g p e` expands the previews for the current
graph selection. Users can create graph selections through pointer/box selection,
but there is no Spacemacs-style keyboard command for adding or removing the
focused graph node from the selection.

Graph selection is map-local interaction state. Runtime selection is owned by
`GraphViewSelection` and the point-oriented `ObjectSelector`, while persisted
interaction state lives on `GraphMap.selected_node_keys`. Graph core and domain
node adapters do not own selection behavior.

The same keyboard shape should be usable later for analogous systems, such as
scene object selection, without forcing a generic selection framework before the
second implementation exists.

## Requirements

- Add Spacemacs-style graph selection editing commands under the documented
  `SPC g s ...` graph namespace.
- Commands target the currently focused graph node, not hover or pointer
  position, so keyboard-driven workflows are deterministic.
- Provide these graph bindings:
  - `SPC g s s`: select the focused graph node only.
  - `SPC g s a`: add the focused graph node to the existing selection.
  - `SPC g s r`: remove/deselect the focused graph node from the selection.
  - `SPC g s t`: toggle the focused graph node in the selection.
  - `SPC g s c`: clear graph selection.
- Mutations keep `ObjectSelector.selected`, `GraphViewSelection.selected-nodes`,
  and `GraphMap.selected_node_keys` coherent.
- Remove/deselect commands must not remove a node from the graph map and must
  not delete any backing domain object.
- Future systems should reuse the terminal verbs `s`, `a`, `r`, `t`, and `c`
  under their own command namespace, implemented against their native selection
  controller.

## Approach Options

1. **Graph-native focused-node commands with shared key verbs.** Add graph view
   selection-editing methods and bind them from the existing graph command
   provider. Document the terminal verbs for future systems. This fits current
   ownership and avoids premature abstraction.
2. **Introduce a generic selection command framework now.** This could make the
   eventual scene selection feature share more code, but it would require a
   cross-system selection contract before scene selection requirements are known.
3. **Target the hovered or pointer-nearest node.** This might be convenient for
   mouse-driven use, but it makes leader-key behavior depend on pointer state and
   is less predictable than focused-node keyboard semantics.

The recommended approach is option 1.

## Design

GraphView should expose a small graph-specific selection editing API. The API
resolves the currently focused graph node, translates selected nodes to their
current render point handles, updates the `ObjectSelector`, then applies the
same node list through `GraphViewSelection`. The existing
`selected-nodes-changed` path remains responsible for syncing selected node keys
back into the active `GraphMap`.

The graph command provider should add a `SPC g s` prefix labeled `selection` and
bind command descriptors for select-only, add, remove, toggle, and clear. Command
availability should reflect the active graph view state: focused-node commands
need a focused graph node, remove should only be available when that focused node
is selected, and clear should only be available when selection is non-empty.

The implementation should stay in the graph view/command layer. Graph core
continues to persist topology only, and domain node adapters remain unaware of
view selection. The design intentionally documents reusable key verbs without
adding a generic selection abstraction until another concrete system needs it.

## Error Handling

Commands should be unavailable when there is no active graph view or no valid
target for the requested operation. Selection mutation helpers should be
idempotent: adding an already-selected focused node, removing an unselected
focused node, or clearing an empty selection should not corrupt state or emit
unnecessary work. If focused-node or selector state is internally inconsistent,
the command should fail explicitly in tests rather than silently mutating graph
topology.

## Testing

Focused tests should cover:

- GraphView selection editing keeps selected nodes, selected point handles, and
  `GraphMap.selected_node_keys` synchronized.
- Add preserves the previous selection while including the focused node.
- Select-only replaces the previous selection with the focused node.
- Remove only deselects the focused node and does not remove the node from the
  graph map.
- Toggle adds when absent and removes when present.
- Clear removes all selected nodes.
- Graph command provider hints and availability expose `SPC g s ...` commands
  alongside the existing `SPC g p ...` preview commands.
- Leader-state routing invokes the graph selection commands and does not mutate
  selection when unavailable.

Validation should follow the Space Fennel ladder: touched-file compile check,
constraints, then focused graph view, command provider, and leader-state tests.

## Out of Scope

- Scene/object selection commands.
- A generic cross-system selection framework.
- Graph map topology removal commands.
- Destructive domain object deletion.
- Search or picker-based bulk selection commands.
