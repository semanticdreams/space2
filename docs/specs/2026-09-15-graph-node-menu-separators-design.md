# Graph Node Menu Separators Design

Date: 2026-09-15

## Summary

Graph node context menus should present graph-view/general actions before node-specific actions. The menu should visually separate those groups so users can distinguish universal graph actions from actions provided by a particular graph node adapter.

## Current Behavior

`GraphView` composes node context menu actions in `assets/lua/graph/view/init.fnl`. The current order is:

1. `Open`
2. `Expand` or `Collapse`
3. `cube`
4. node-specific actions from `node.actions`
5. `Remove from Map`

The generic menu widget in `assets/lua/menu.fnl` renders every entry as a `Button` and requires every entry to have a name. `assets/lua/menu-manager.fnl` wraps only action-like fields and does not preserve a separator/discriminator field. There is no first-class context-menu separator today.

## Desired Behavior

Graph node context menus should be ordered as:

1. `Open`
2. `Copy key`
3. `Expand` or `Collapse`
4. `cube`
5. `Remove from Map`
6. separator
7. node-specific actions from `node.actions`

The separator is always present for graph node context menus, even when the node has no node-specific actions.
`Copy key` copies `(tostring node.key)` to the clipboard through the existing `gl.clipboard-set` binding and is treated as a general graph-view action.

## Architecture

Add first-class separator support to the generic menu path rather than encoding separators as fake actions.

- `MenuManager` should preserve separator entries when wrapping actions for display.
- `Menu` should accept the separator entry shape `{:type :separator}` without requiring a name or click handler.
- `Menu` should render separator entries as non-clickable divider rows, not `Button`s.
- `GraphView` should own graph-node menu composition, including the `Copy key` action, and insert the separator between general graph actions and node-specific actions.

This keeps graph node adapters responsible only for their own `node.actions`; the graph view remains responsible for graph-map interaction actions such as open, expand/collapse, cube presentation, and removal.

## Components and Data Flow

1. A graph node point/card receives a right-click or menu-button event.
2. `GraphView` calls `node-menu-actions node`.
3. `node-menu-actions` builds general graph actions first, including `Copy key`, appends a separator entry, then appends validated node-specific actions.
4. `MenuManager:open` wraps action entries while preserving separators.
5. `Menu` normalizes the mixed menu-entry list and renders buttons for actions and a divider layout child for separators.

## Error Handling and Constraints

- Action entries still require a resolved name.
- Separator entries do not require a name or handler.
- Unknown nameless entries should continue to fail loudly instead of silently rendering empty menu rows.
- `Copy key` should fail loudly if the clipboard binding fails; it should not swallow clipboard errors.
- Separator rows should not be clickable and should not invoke menu close behavior.
- The implementation should follow Space Fennel UI ownership rules: composite widgets own and drop their direct children, and layout transforms are written during layout passes.

## Testing

Focused validation should cover:

- generic menu normalization/rendering accepts separator entries without names;
- separators do not create clickable action buttons;
- menu actions before and after a separator keep their order and remain invokable;
- `GraphView` node point context menus place general actions, including `Copy key`, before the separator and node-specific actions after it;
- `Copy key` writes the string form of `node.key` to the clipboard;
- graph node menus still include the separator when no node-specific actions exist;
- expanded graph node presentation menu behavior follows the same composition.

Fennel validation should run the touched-file compile check, constraints, and focused menu/graph-view tests.
