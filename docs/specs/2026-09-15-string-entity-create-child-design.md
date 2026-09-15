# String Entity Create Child Action Design

## Purpose

String entity graph nodes should support a direct node-specific action named `Create child`. The action lets a user grow a string-entity hierarchy from an existing string entity node without leaving the graph map or manually creating both the child string entity and the link entity.

## User-Facing Behavior

- The context menu for string entity nodes includes `Create child`.
- Invoking `Create child` on a string entity node creates a new string entity with the store default contents.
- The action creates a link entity from the current string entity node to the new child string entity node:
  - `source-key` is the current node key, such as `string-entity:<parent-id>`.
  - `target-key` is the new child key, such as `string-entity:<child-id>`.
- The new child string entity is added to the same active/containing `GraphMap` as the parent node.
- Existing derived link-edge behavior displays the relationship when both endpoint nodes are visible.

## Architecture

The recommended implementation is a node-local capability on the string entity graph node adapter. String entity nodes already expose node-specific actions, and mounted nodes receive their containing `GraphMap` through `node.graph`. Keeping the action on the node makes the user gesture explicit while preserving graph doctrine boundaries:

- `StringEntityStore` owns the new string entity data.
- `LinkEntityStore` owns the relationship entity.
- `GraphMap` owns only the materialized visible child node reference and map-local adapter state.
- Graph core does not persist entity contents or link relationships.

The action should create the child string entity, create the link entity, then call `GraphMap:load-by-key` for the child key. It should not add a manual map edge. Link-entity derived-edge recomputation should remain the only source of the visible parent-child edge, and derived edges must remain omitted from `GraphMap:capture-state`.

## Approaches Considered

1. **Node-local string entity action (recommended):** small, follows the existing `Delete Entity` node-action pattern, and keeps the graph map as the action's interaction context.
2. **Shared entity-action helper:** could reduce duplication if more entity node actions appear later, but introduces abstraction before there is reuse.
3. **GraphMap-level child creation API:** centralizes mutation but would push string/link store domain knowledge into `GraphMap`, conflicting with graph-as-exposure-layer doctrine.

## Error Handling

The action must fail loudly rather than silently doing nothing when required context is unavailable. Clear errors should cover at least:

- the node is not mounted in a graph map;
- the mounted graph-like object cannot `load-by-key`;
- the string store fails to return a child entity id;
- the link store fails to return a link entity id;
- the child key cannot be loaded into the graph map.

## Testing and Validation

Focused coverage should assert that invoking `Create child` from a mounted string entity node:

- creates one new string entity in the string entity store;
- creates one link entity in the link entity store;
- stores the parent node key as `source-key` and new child node key as `target-key`;
- materializes the child node in the same `GraphMap`;
- produces the expected derived link edge without persisting that edge in captured map topology;
- preserves existing string entity actions, including `Delete Entity`.

Failure-path tests should cover unmounted nodes and graph-like contexts without `load-by-key`.

Because this is Space Fennel graph/entity work, validation should run the touched-file Fennel compile check, constraints, focused string/link/graph map tests or a dedicated node-action test, and the fast Fennel suite when the new test is registered there.

## Out of Scope

- Positioning the child next to the parent beyond existing graph layout behavior.
- Prompting for initial child text.
- Link labels, metadata editing, or typed relationship UI.
- Creating multiple children at once.
- Changing root graph actions for string or link entity creation.
- Persisting derived link edges as explicit graph map edges.
