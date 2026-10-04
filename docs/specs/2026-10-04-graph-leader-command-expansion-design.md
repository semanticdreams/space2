# Graph Leader Command Expansion Design

## Context

Graph leader commands currently cover selected preview presentation through
`SPC g p ...` and focused-node selection editing through `SPC g s ...`. The
documented graph command namespace also reserves `SPC g n ...` for focused graph
node actions, `SPC g v ...` for graph view/camera/layout operations, and
`SPC g m ...` for graph map and topology operations.

Many graph interactions are already available through pointer UI: node context
menus, node menu actions, full node opening, sidebar map controls, Add Start,
node finder reveal/open, and layout/view controls. Keyboard workflows should be
able to perform these stable interactions without reaching for the mouse. The
first expansion should also add two map operations not currently exposed as
leader commands: creating a new graph map from the selected nodes and clearing
the active graph map.

Graph doctrine still applies: graph nodes are adapters over owning systems,
`GraphMap` owns map-local interaction/topology state, and graph core persists
topology only. Keyboard commands must not silently delete backing domain objects.

## Requirements

- Preserve existing `SPC g p ...` and `SPC g s ...` bindings and semantics.
- Add `SPC g n ...` focused-node commands for stable node UI parity:
  - open focused node full view;
  - open focused node context menu;
  - toggle focused node preview;
  - copy focused node key;
  - remove focused node from the active graph map, non-destructively;
  - run focused-node action slots `1` through `9` using the same action list as
    the context menu.
- Add `SPC g v ...` graph view commands for stable view/layout parity:
  - center/reveal focused node;
  - start graph layout.
- Add `SPC g m ...` graph map/topology commands:
  - add the `start` node to the active graph map;
  - create and switch to a new empty graph map;
  - create and switch to a new graph map containing the selected nodes;
  - clear the active graph map.
- Creating a map from selection copies map-local topology only: selected visible
  node keys, explicit edges whose endpoints are both selected, selection/focus
  limited to included nodes, and presentation islands only when all island
  members are included.
- Clearing a graph map removes map-local nodes, explicit edges, islands,
  selection, and focus, but must not delete domain objects or backing records.
- Commands must resolve the current graph view, active `GraphMap`, and
  `GraphMapManager` at run time rather than capturing stale instances.
- Node action command slots and pointer context menus must share the same action
  construction path so keyboard and mouse behavior stay aligned.
- Missing required dependencies should fail explicitly or make commands
  unavailable; no silent topology no-ops for unavailable graph context.
- Document bindings and graph map command semantics.

## Approach Options

1. **Phased keyboard parity with new map primitives.** Extract focused-node
   action construction into a reusable graph-view helper, add graph map methods
   for clear and subgraph capture, bind stable node/view/map commands, and defer
   riskier reposition/delete/rename commands. This covers the requested keyboard
   parity and named new operations while keeping implementation bounded.
2. **Build a generic command/action palette for every graph action.** This could
   eventually expose all actions uniformly, but it would require broader UI and
   picker design before the stable graph command set is proven.
3. **Expose every existing sidebar/menu action immediately.** This maximizes
   parity, but binding map delete and placeholder rename before confirmation and
   rename UX exists creates avoidable accidental-loss and rough-edge risk.

The recommended approach is option 1.

## Design

### Focused node commands

`GraphView` should expose a focused-node action boundary. The existing local
node menu action construction should move into a small helper that returns the
same action table shape used by context menus: `:name`, optional presentation
metadata, and `:fn`. Right-click context menus and `SPC g n 1..9` should consume
that same list.

Default focused-node commands should call graph-view methods rather than
duplicating menu behavior in the command provider. `SPC g n o` opens the focused
node full view, `SPC g n m` opens its context menu, `SPC g n t` toggles its
preview, `SPC g n y` copies its key, and `SPC g n r` removes it from the active
map. Removal is map-local only and must not invoke backing-object deletion.

### View commands

`SPC g v c` should reveal and center the focused node through the existing graph
view reveal path. `SPC g v l` should start graph layout through the existing
layout start path. These commands are view/controller operations and should not
write graph core state directly.

Keyboard repositioning is useful, but should be a follow-up phase. Discrete
nudge commands can fight force layout and require careful persistence/label sync
testing, so this design defers `h/j/k/l` node movement until after the core
keyboard parity is stable.

### Map commands

Graph map commands should operate on `GraphMap` and `GraphMapManager`, not shared
graph core. `SPC g m a` adds `start` to the active map using the same key-loader
path as the sidebar Add Start action. `SPC g m n` creates and switches to a new
empty graph map.

`SPC g m s` creates and switches to a new graph map from the current selection.
The source map should produce a subgraph state from selected keys: included node
keys, explicit included-to-included edges, selected/focused keys restricted to
the included set, and complete islands only when every island member is included.
It should not copy panels, camera state, high-churn metadata, or backing domain
data.

`SPC g m c` clears the active map by restoring an empty map-local topology and
interaction state. The command is explicit topology removal, not domain object
deletion. It should be unavailable for an already empty map.

Active map delete and rename are intentionally not included in this phase. The
sidebar delete operation is currently direct and documented as needing a better
confirm/cancel UX; leader-key delete would make accidental map loss too easy.

### Command provider

The graph command provider should keep static namespace prefixes for hints and
availability, but resolve graph view/map/manager dependencies at command run and
availability time. If dynamic focused-node action labels are needed for numeric
slots, graph activity may install a provider function so hints can reflect the
current focused node action list.

## Error Handling

- Commands requiring a focused node are unavailable when no focused graph node is
  present.
- Numeric action slots are unavailable when the focused node has no action at
  that index or the action has no runnable function.
- Map commands requiring a selected set are unavailable when selection is empty.
- Clear-map is unavailable when the active graph map has no visible topology or
  island state to clear.
- Missing active graph map or map manager should fail loudly in tests and command
  wiring rather than silently returning success.
- Node action function errors should propagate through the command path, matching
  the current explicit-action behavior.

## Testing

Focused tests should cover:

- Existing preview and selection command bindings remain unchanged.
- `SPC g` hints expose `preview`, `selection`, `node`, `view`, and `map` when
  applicable.
- Focused-node command methods require focus and call the same action list used
  by the context menu.
- Numeric action slots execute the corresponding focused-node action functions.
- `remove focused from map` removes only the map-local node reference and does
  not delete the backing object.
- View commands call existing reveal/center and layout-start paths.
- Graph map subgraph capture includes selected nodes, selected-to-selected
  explicit edges, restricted selection/focus, and complete islands only.
- Creating a graph map from selection creates/switches to a new map with only
  the selected visible topology.
- Clear-map empties map-local topology, selection, focus, and islands without
  deleting domain data.
- Add Start via leader command matches sidebar Add Start behavior.

Validation should follow the Space Fennel ladder: touched-file compile check,
constraints, focused graph command/map/view/manager tests, and broader relevant
graph suites when command/activity integration changes.

## Out of Scope

- Deleting backing domain objects.
- Active map delete and rename leader commands.
- Confirmation dialogs or picker/autocomplete redesign.
- Search-based Add to Map.
- Keyboard node repositioning/nudging in the first phase.
- A generic cross-system command palette.
- Reworking graph core persistence beyond map-local topology helpers.
