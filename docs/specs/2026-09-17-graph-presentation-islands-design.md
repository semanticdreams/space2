# Graph Presentation Islands Design

## Purpose

Space graph view should support richer graph-native presentations of related nodes without hardcoding domain-specific cases into graph view. The immediate motivating case is making ordered list entities usable for Logseq-style thought structures: a list entity should be able to present its item nodes as an ordered vertical structure in graph space. The design must remain general enough for other future node types, such as folders, timelines, workflows, galleries, generated clusters, and specialized knowledge-management entities.

## Design Direction

Introduce map-local **presentation islands**. An island is a graph-map-owned presentation object with independent identity, a presenter kind, member node keys, and presenter-owned state. Nodes may create or update islands through explicit actions or events, but no visible node instance exclusively owns an island after creation.

The generic graph infrastructure should know only enough to host islands:

- island id;
- island kind / presenter kind;
- member graph keys;
- persisted presentation state interpreted by the island kind;
- generic lifecycle hooks for reconciliation, layout, rendering, interaction, and pruning.

Domain-specific meaning belongs to the island kind, not to graph view. For example, an ordered-list island can store the relevant list key and order policy in its own state, while a freeform cluster island can store a label or manual arrangement state. GraphMap does not need generic concepts such as `created-by` or `subject`; island kinds can store any needed provenance or domain references inside their own state.

## Ownership Boundaries

### Node adapters

Node adapters may define actions that create, update, or request operations on islands. A list entity node can offer an action such as `Expand items as island`; a future timeline node can offer `Show events as timeline`; a workflow node can offer `Show steps as lanes`.

Node adapters should not own runtime island widgets, graph-view internals, or global force-layout state. They initiate semantic/presentation requests through graph-map APIs.

### GraphMap

GraphMap owns map-local topology and presentation state. It should persist island records because islands are interaction/presentation context over shared graph-addressable objects, not domain truth. A user may remove the node that originally created an island from the graph map while the island remains.

GraphMap should provide constrained operations for creating, updating, removing, and reconciling islands. It should not interpret island-specific state except for generic hosting concerns such as member keys and presenter kind.

### GraphView / presentation host

GraphView owns runtime rendering, widget lifetimes, graph-node handles, camera-space transforms, drag interaction plumbing, selection/focus integration, and force-layout integration. It instantiates island presenters by kind and asks them to lay out and render members through a constrained host interface.

GraphView should not contain hardcoded domain branches such as `if list entity then vertical stack`. It should host presenter implementations registered by island kind.

### Island presenters

An island presenter owns the local presentation and interaction semantics for an island kind. For an ordered-list island, the presenter can arrange member nodes vertically in list order and define how child dragging behaves. For a gallery island, the presenter can arrange members in a grid. For a workflow island, the presenter can arrange lanes or ports.

Presenter logic should operate through graph-owned host APIs rather than direct mutation of graph-view internals.

## Conceptual Island Record

The persisted map-local record should be intentionally small and generic:

```text
island:
  id: <stable map-local id>
  kind: <presenter kind>
  members: [<graph key>, ...]
  state: <presenter-owned map/table>
```

Example ordered-list island:

```text
island:
  id: island-1
  kind: ordered-list
  members:
    - string-entity:a
    - string-entity:b
    - string-entity:c
  state:
    list-key: list-entity:children
    collapsed: false
    position: <map-space position>
    interaction-policy: reorderable
```

Example freeform cluster island:

```text
island:
  id: island-2
  kind: freeform-cluster
  members:
    - string-entity:x
    - link-entity:y
  state:
    label: Research cluster
    position: <map-space position>
```

GraphMap hosts both the same way. The presenter kind interprets the state.

## Materialization and Presentation Requests

Materialization is node-specific. A node action or domain event can decide which related graph keys should be added to the active graph map and which island, if any, should present them.

The preferred flow is request-based:

1. A node action decides what should be shown.
2. The action requests graph-map materialization of specific graph keys.
3. The action requests creation or update of an island record.
4. GraphMap applies the request through constrained APIs.
5. GraphView reconciles runtime island presenters from the persisted graph-map state.

Graph view should not passively scan all nodes to discover hidden relationships or decide which related nodes to materialize. Expanding a node can automatically create an island only because expansion is already an explicit user action.

## Force Layout Integration

Presentation islands should be treated as structured graph-layout objects rather than as soft constraints scattered through the global force simulation. This keeps force-layout behavior predictable.

The intended model is:

- the global force layout interacts with an island as a compound object or grouped presentation unit;
- the island presenter computes deterministic local positions for its member nodes;
- member nodes remain real graph nodes for selection, edges, focus, node cards, and persistence;
- island presenters can expose bounds/anchors needed by the global layout;
- manual graph positions and island-local layout state are map-local presentation concerns.

This design intentionally does not start with soft force constraints for ordered lists. Soft constraints may be useful later, but they risk unpredictable interactions between repulsion, edge tension, ordering, spacing, user drags, and overlapping groups.

## Interaction Policy

Whether manual user actions can reorder, detach, override, or break an island should be defined by the island kind. GraphMap and GraphView should enforce those policies through constrained operations.

Possible interaction policies include:

- child drag reorders members;
- child drag creates a manual position override;
- child drag detaches from island presentation;
- child drag is forbidden;
- external drop adds a member;
- external drop is rejected;
- group drag moves the whole island.

The graph infrastructure should expose generic interaction events and constrained mutation APIs. Presenter kinds decide which operations are valid for their semantics.

## Widgets and Layout Algorithms

Normal widgets and flex layout remain appropriate inside node cards, panels, previews, and island-specific controls. They should not become the ownership substrate for graph presentation islands.

Graph islands live in graph/canvas space and must cooperate with graph-node handles, camera transforms, edges, selection, drag behavior, force layout, and GraphMap persistence. Island presenters may use flex-like algorithms as pure measurement/placement helpers, but the result should be graph-space positions for graph-node members, not ordinary widget-child ownership of graph topology.

## Lifecycle and Cleanup

Because islands are graph-map-owned presentation objects, lifecycle must be explicit:

- removing the node that originally created an island from the graph map does not automatically remove the island;
- removing an island from the graph map does not delete domain entities;
- deleting domain entities should be handled by the relevant domain deletion logic and/or island-kind validation;
- graph-map hydration should reconcile islands whose members cannot be loaded;
- presenter-kind reloads or missing presenter kinds should fail visibly rather than silently dropping state;
- invalid island records should be pruned or surfaced according to graph-map recovery policy.

Domain data remains owned by domain stores. Island state is map-local presentation state.

## Initial Ordered-List Use Case

The first concrete island kind should likely be an ordered-list presenter over existing list entities. A list entity node can request materialization of its item keys and create or update an ordered-list island whose members are the materialized item nodes.

The ordered-list island should make list-backed thought structures readable in graph view without creating Logseq-specific graph-view logic. It can arrange item nodes vertically in persisted list order while preserving each item as a normal graph node.

## Risks and Weaknesses to Watch

This design deliberately gives island presenters substantial local control. Implementation and testing should watch for these weaknesses:

- presenters becoming too powerful and bypassing GraphMap/GraphView ownership boundaries;
- stale island records after node removal, domain deletion, extension reload, or failed materialization;
- islands whose internal layout conflicts with global force layout or creates confusing edge routing;
- unclear user expectations about whether dragging edits domain order, presentation order, or both;
- overlapping islands or nodes that belong to multiple islands;
- presenter-kind proliferation without shared conventions;
- persistence schema drift if presenter-owned state becomes unstructured and unvalidated;
- difficulty testing layout presenters deterministically;
- performance problems when islands contain many members or update frequently;
- accessibility/discoverability issues if island controls are hidden inside graph gestures.

If these risks become concrete during implementation, the design should be narrowed rather than generalized further.

## Testing and Validation

Focused tests should cover:

- creating and persisting a generic island record;
- restoring island records during graph-map hydration;
- materializing list item nodes and adding them to an ordered-list island;
- removing the original list node from the graph map while the island remains;
- deleting/removing island presentation without deleting member entities;
- presenter-kind missing or invalid-state behavior;
- deterministic local layout for ordered-list members;
- interaction-policy enforcement for reorder, detach, and forbidden drag cases as those policies are implemented.

Because implementation will touch Space Fennel graph/view/widget code, validation should use project-native Fennel compile checks, constraints, and focused graph/list/presentation tests. If force-layout or C++ host behavior changes, validation should broaden to include the relevant build and runtime tests.

## Out of Scope

- A full Logseq-like outline activity.
- Specialized block/outline domain entities.
- Soft force constraints for ordered child lists.
- Making island state domain truth.
- Generic graph-view special cases for list entities.
- Occurrence/member indirection for ordered thought children.
