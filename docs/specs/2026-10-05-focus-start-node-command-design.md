# Focus Start Node Command Design

## Problem

Space recently gained Spacemacs-style graph commands for preview, selection,
focused-node, view, and map actions. The active graph map already has an `Add
Start` button and a `SPC g m a` command that ensure the canonical `start` node is
present through `GraphMap:add-start-node!`. Users also need a faster navigation
command that focuses the start node from graph view context. If `start` is not
currently in the active map, the command must add it through the same Add Start
path before focusing it.

## Design Direction

Add a new graph view command:

- Command id: `graph.view.focus-start`
- Binding: `SPC g v s`
- Label: `start`
- Behavior: require an active graph view and active graph map, call
  `GraphMap:add-start-node!`, then call `GraphView:reveal-node` with the returned
  node and explicit `{ :select? true :focus? true :center? true }` options.

This keeps node creation/map membership in `GraphMap`, keeps focus/selection/
camera behavior in `GraphView`, and avoids direct persistence or domain-object
mutation. The binding lives under `SPC g v` because the user's intent is view
navigation/focus; the map ensuring step is an implementation prerequisite reused
from the Add Start behavior.

## Alternatives Considered

1. **Command-only orchestration in `graph/commands.fnl` (recommended).** Reuse
   `GraphMap:add-start-node!` and `GraphView:reveal-node` directly from a new
   command runner. This is small, explicit, easy to test with existing command
   provider stubs, and does not introduce new graph-view/map coupling.
2. **Add a new `GraphView:focus-start-node` method.** This would make the command
   runner thinner, but it would move map membership concerns into the view API or
   require another cross-object helper. That expands the public surface for one
   command and is not necessary yet.
3. **Chain existing commands (`graph.map.add-start` then center/reveal).** The
   current command system does not provide a stable command-composition contract
   with returned node handoff, and chaining would make error handling and tests
   less direct.

## Components and Data Flow

1. The leader command provider exposes `graph.view.focus-start` and binds it to
   `SPC g v s`.
2. Availability is true only when an active graph view, active graph map,
   `GraphMap:add-start-node!`, and `GraphView:reveal-node` are available. It does
   not require an existing focused node.
3. Running the command asserts the required methods, calls
   `graph-map:add-start-node!`, and passes the returned node to
   `graph-view:reveal-node`.
4. `GraphMap:add-start-node!` remains responsible for loading/ensuring the
   canonical `start` graph node, including existing loud failures when the start
   loader is unavailable.
5. `GraphView:reveal-node` remains responsible for selection, focus, and camera
   centering.

## Error Handling

Missing graph map/view dependencies or required methods should fail loudly with
assertions, matching existing graph command and Add Start behavior. The command
must not silently no-op if the start loader fails or if the returned node cannot
be revealed.

## Testing

Add focused Fennel coverage for:

- command provider availability and execution in `assets/lua/tests/test-commands.fnl`;
- leader routing of `SPC g v s` in `assets/lua/tests/test-states.fnl`;
- preservation of existing `SPC g v c`, `SPC g v l`, and `SPC g m a` behavior.

Validation should follow the Space Fennel ladder: targeted `tools.fennel-check`,
`make constraints`, then focused command/state tests.

## Documentation

Update `docs/dev/features/leader-command-system.md` to list `SPC g v s` in the
graph view commands table. Update `docs/dev/graph-maps.md` near the Add Start
description to note that `SPC g v s` uses the same start-node ensuring path before
revealing the node.

## Out of Scope

- New graph map persistence or schema changes.
- Automatic start-node seeding for every new map.
- Alternate bindings or compatibility aliases.
- Changes to the existing Add Start button behavior.
