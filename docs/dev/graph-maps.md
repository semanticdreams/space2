# Graph Maps

Graph Maps are the abstraction for multiple persistent graph interaction contexts over the same shared graph-addressable objects.

Status: implemented through map manager, graph view attachment, map switching UI, and panel scoping. Board migration remains future work.

## Summary

The graph is intended to provide one uniform interface to many kinds of things: files, code, entities, worlds, terrain tools, conversations, kernels, and future object types. A single current graph state becomes hard to use when different tasks require different expansions, layouts, selections, and open panels.

`GraphMap` is the named, persistent interaction context for a task or workflow. A graph map owns the visible references, display edges, arrangement, and interaction state that a user has explicitly materialized. It does not own the underlying objects.

This keeps the existing graph-as-universal-model direction while avoiding multiple independent `Graph` instances that duplicate shared store subscriptions and registry-installed key-loader behavior.

## Current Status

Implemented:

- `GraphMap` provides map-local node/edge membership, selection/focus state, unresolved restored state, mount/unmount behavior, and capture/restore/drop APIs.
- Shared `Graph:create-node-by-key` creates node adapter instances without mutating shared graph state.
- `GraphMap:load-by-key` resolves keys through the shared graph and inserts fresh map-local adapters.
- `GraphMap:refresh-adapters-by-scheme` rebuilds visible map-local adapters for a key scheme during graph extension unit reload, preserving topology keys while replacing runtime adapter tables and retargeting explicit map edges.
- Related objects are added explicitly by preview/view/action/search controls that load selected keys into the active map; graph maps do not perform hidden relationship-hook expansion.
- `GraphMapManager` owns map records, active map id, legacy migration, create/rename/delete/switch, hydration pruning, capture, and metadata cleanup.
- `GraphView` attaches to the active `GraphMap`, scopes persistence by map id, and captures/drops/restores runtime view state around map switching.
- Graph canvas context exposes `graph-map`; root actions and node menu actions mutate the active graph map instead of the shared graph.
- Graph map sidebar is installed as the graph mode left dock and exposes map list, switching, new/rename/delete actions, active stats, and selected count.
- Graph node panel persistence includes `graph-map-id`; restore only applies to the active map and hydration prunes stale panel records.
- The root `Add to Map` action opens a dialog that loads an entered graph key into the active map and preserves target-owned close lifecycle handling.
- String entity nodes expose a `Create child` action that creates a child string entity, creates a link entity from parent key to child key, and loads the child key into the containing `GraphMap`.
- Fast tests cover the main GraphMap, manager, sidebar, GraphView persistence/panel, and menu action behavior.

Remaining:

- Board migration is intentionally deferred.
- Sidebar UX is functional but minimal; `Rename` is still an inline placeholder behavior rather than a proper rename dialog.
- `Delete Map` is implemented as a direct action; confirm/cancel UX is still worth adding before broader use.
- `Add to Map` accepts raw graph keys only; search/autocomplete/pickers are future UX improvements.
- Some transitional globals (`app.graph`, `app.graph-map`, `app.graph-view`) remain for compatibility while canvas-mode context is the preferred path.
- E2E/manual visual smoke has not been confirmed for the new graph map UI.

## Terminology

- `Graph`: the shared graph-addressable object resolver/catalog. It exposes the low-level key-loader registration primitive used by graph extension descriptor installers and provides shared backing-store integration. During the migration, keep the existing module name and avoid a broad rename.
- `GraphMap`: a persistent interaction context over shared graph-addressable objects. It owns included node keys, explicit map edges, map-local node adapter instances, layout, expanded cards, selection/focus, and graph-owned panels.
- `GraphView`: runtime renderer/controller for the active graph map. It owns rendering handles, force-layout instance, focus/click/movable registrations, drag state, and batching.
- `Remove from Map`: non-destructive operation. Removes a node reference and its map-local UI state from the active graph map.
- `Delete Underlying Object`: destructive operation. Deletes the backing object through an explicit node/object-specific capability.

Avoid using bare `map` in implementation code because Fennel/Lua tables often use `*-map` names for dictionaries. Prefer `graph-map`, `active-graph-map`, and `GraphMap`.

## Why Not Multiple Graphs

The current `Graph` is not only a local subset container. It also owns shared integration:

- Key loaders for schemes such as `fs:`, `string-entity:`, `world:`, `terrain:`, `llm-conversation:`, and `kernel:`.
- Backing stores: string/list/link/identity/code/notebook/LLM/kernel/world data.
- Identity resolution through the shared identity store.
- Link-entity semantics and link edge bookkeeping.
- Store event subscriptions for link, string entity, identity, and morph events.
- Shared node constructors and node type behavior.

If each graph map used a separate `Graph` instance, every map would duplicate store subscriptions and react independently to the same backing-store events. That makes shared object events look map-local and risks duplicate work, inconsistent state, and expensive deletes.

Graph maps should share the key/object universe but keep their own interaction state.

## State Ownership

### Shared Graph State

Shared between all graph maps:

- Key namespace and key semantics.
- Key-loader handles installed by graph extension descriptors through the registry.
- Backing stores and persisted objects.
- Identity resolution.
- Link entities as underlying relationships.
- Node type constructors, previews, views, actions, and validation logic.
- Store event streams.
- Destructive object operations.

### Graph Map State

Owned per graph map:

- Map id and name.
- Included node keys.
- Explicit map edges.
- User-materialized visible topology only; domain records and hidden relationships stay in their owning systems until an explicit control exposes them.
- Unresolved restored keys/edges until hydration resolves or prunes them.
- Map-local node adapter instances.
- Positions.
- Expanded/collapsed presentation state.
- Card sizes.
- Selected node keys.
- Focused node key.
- Open graph node panels.

#### Presentation islands

`GraphMap` persists presentation islands as map-local presentation state over
graph-exposed objects. Domain stores continue to own domain data; island records
only describe how already-exposed graph members should be presented in this map.

Persisted island records use the generic shape:

```text
{:id string
 :kind string
 :members [graph-key ...]
 :state presenter-owned-table}
```

For presenters that lay out graph members spatially, `state.position` is the
island body's absolute graph-space position. A node action may choose an initial
body position near the creating node, but after creation the stored island body
position is authoritative and must not be recomputed from source-node metadata.

`GraphView` hosts presenters by island `:kind`. Presenter behavior such as
`ordered-list` is registered through the island presenter host rather than a
hardcoded list-entity branch in GraphView. The `ordered-list` presenter places
the first member at `state.position` and offsets later members vertically by
`state.spacing`; legacy records with no `state.position` fall back to an existing
member position or the presenter's default origin, not a list/source-node anchor.

Removing an island removes only the map-local presentation record. It does not
delete member nodes or any backing domain entities. Initial `ordered-list`
islands provide snap-back vertical presentation in stored list order; they are
not domain reorder controls.

### Graph View State

Runtime only:

- Render point handles and edge line handles.
- Force-layout instance and indices.
- Clickable, selectable, focus, movable, and resizable registrations.
- Label widgets.
- Open dialog/widget instances.
- Drag in progress.
- Batched update flags.

## Node Adapter Instances

Do not share node tables across graph maps.

Current graph nodes store mutable state and assume `node.graph` is the object to mutate for interaction operations. Examples:

- `FsNode.include-hidden?` is local UI state.
- Node methods call `self.graph:add-edge` to expand from a node into a child node.
- Node deletion handlers call `node.graph:remove-nodes` when their backing object disappears.
- LLM conversation nodes mutate state and add message/tool nodes via `self.graph`.

Therefore each graph map should have its own node adapter instance for a key. The adapter can point at the same backing object, but it must be mounted into exactly one graph map.

`GraphMap` should present the graph-like mutation API to nodes:

- `add-node`
- `add-edge`
- `remove-nodes`
- `lookup`
- `load-by-key`
- `resolve-key`
- `resolve-node`

When a node is mounted into a map, `node.graph` should be the `GraphMap`, not the shared `Graph`.

## Shared Graph API Changes

The existing `Graph.load-by-key` currently resolves a key and mutates `Graph.nodes`. Graph maps need key resolution without mutating a shared graph node set.

Add a factory/resolver operation to shared `Graph`:

```fennel
(graph:create-node-by-key key)
```

Expected behavior:

- Return a new node adapter instance for `key` when possible.
- Return nil if the key cannot be resolved.
- Validate that returned node has the requested key.
- Do not insert the node into shared `Graph.nodes`.
- Do not emit map-local node signals.

During migration, `Graph.load-by-key` can continue to exist for compatibility, but new graph-map code should call `create-node-by-key`.

`GraphMap:load-by-key` should call `graph:create-node-by-key`, then insert the node into the map.

## Graph Map API

Initial `GraphMap` should be intentionally close to current `Graph` so `GraphView` can move with small changes.

Required fields/signals:

```fennel
{:id id
 :name name
 :graph shared-graph
 :nodes nodes
 :edges edges
 :edge-map edge-map
 :node-added node-added
 :node-removed node-removed
 :node-replaced node-replaced
 :node-morphed node-morphed
 :edge-added edge-added
 :edge-removed edge-removed}
```

Required methods:

```fennel
(graph-map:add-node node opts)
(graph-map:add-edge edge opts)
(graph-map:remove-nodes nodes)
(graph-map:lookup key)
(graph-map:load-by-key key)
(graph-map:resolve-key key opts)
(graph-map:resolve-node key-or-node opts)
(graph-map:refresh-adapters-by-scheme scheme)
(graph-map:capture-state)
(graph-map:restore-state state)
(graph-map:drop)
```

`add-node` should mount the node into the map. `remove-nodes` should unmount/drop map-local node adapter instances, prune explicit edges, clear map-local state for removed nodes, and emit signals for the active view.

## Derived Edges

Link-entity edges should be recomputed, not persisted.

Persist:

- Explicit map edges that the user or a node preview/action/search row created as part of making related records visible.
- Map node membership.
- Layout/presentation/panel/selection state.

Do not persist:

- Automatically inferred link-entity edges.
- Store-event-derived edges.
- Edges that can be recomputed deterministically from shared backing stores.

When both endpoints of a link entity are present in a graph map, the map may create a derived edge record for display. Derived edge records should be distinguishable from explicit map edges so capture skips them.

String entity `Create child` relies on link-entity derived-edge recomputation. The created link entity owns the parent-child relationship, and the visible edge remains omitted from `GraphMap:capture-state`.

Workflow display edges follow the same visibility rule: workflow definitions, runs, run steps, and events are loaded only by explicit workflow controls, and workflow-derived display edges are not the canonical workflow topology. The workflow store owns definition edges, run records, run-step records, and event records.

Workflow-derived display edges can be added by explicit actions such as **Reveal All Steps**, **Show Run Steps**, or timeline/event materialization. Mark those edges with `from-workflow-edge` so graph-map capture skips them and the workflow store remains the canonical owner.

UX-purpose nodes such as `workflow-step-explorer:<definition-id>` and `workflow-run-timeline:<run-id>` are graph-map topology only. They own no workflow records; they adapt workflow stores, run records, events, and active graph-map context into a focused surface.

Hidden relationship expansion and graph trigger APIs are forbidden. Workflow topology enters a graph map only through user-directed controls that say what nodes or edges they materialize.

## Deleted Or Invalid Objects

Avoid making backing-object deletion scale with the number of graph maps.

Policy:

- Active graph map: if a mounted node observes its backing object was deleted, remove that node from the active map immediately.
- Inactive graph maps: do not scan or mutate all maps on delete.
- On opening/hydrating a graph map: validate/load persisted node keys. Prune keys that no longer resolve, along with affected edges, selection, focused-node state, and panels.
- On next save: persist the pruned state.

This treats graph maps as reference sets. References can go stale, and stale references are cleaned when the map is used.

## Persistence

Current legacy shape:

```fennel
{:graph {:graph {:nodes [...]
                 :edges [...]}}}
```

Target shape:

```fennel
{:graph {:active_map_id "main"
         :next_map_id 2
         :maps [{:id "main"
                 :name "Main"
                 :nodes [...]
                 :edges [...]
                 :selected_node_keys [...]
                 :focused_node_key nil}]}}
```

Keep high-churn layout/presentation data out of `world.json` initially. Store it per map under the world directory:

```text
graph/maps/<graph-map-id>/metadata.json
```

Metadata shape:

```fennel
{:positions {node-key [x y z]}
 :presentations {node-key :expanded}
 :sizes {node-key [w h]}
 :panels [{:node-key node-key
           :panel panel-state}]}
```

Graph map camera state is interaction/view metadata, not graph topology. Each
map stores its camera transform in `graph/maps/<graph-map-id>/metadata.json`:

    :camera {:position [x y z]
             :rotation [w x y z]}

When switching maps, Graph captures the outgoing map camera and restores the
target map camera into the stable graph canvas slot camera. Maps without saved
camera state reset to the default camera and center the first/start node once.

Current graph map view metadata lives under `graph/maps/<graph-map-id>/metadata.json`.
Legacy `graph-view/metadata.json` data is migration input only, not the current
write location for graph map metadata.

### Activity-aware world scene key migration

Older graph map state could contain world-level scene topology keys for the
former default 3D workspace. During `GraphMapManager` hydration and metadata
pruning, those persisted topology references are migrated once to the canonical
Sandbox activity surface keys. This is a topology migration only: graph maps keep
node membership, explicit edges, selection/focus, panels, and view metadata; the
owning activity session remains responsible for persisted scene data.

Category keys migrate deterministically by inserting the `sandbox` activity id:

| Legacy key | Canonical key |
| --- | --- |
| `background:<world-id>` | `activity-background:<world-id>:sandbox` |
| `skybox:<world-id>` | `activity-skybox:<world-id>:sandbox` |
| `lights:<world-id>` | `activity-lights:<world-id>:sandbox` |
| `terrains:<world-id>` | `activity-terrains:<world-id>:sandbox` |
| `scene-panels:<world-id>` | `activity-scene-panels:<world-id>:sandbox` |

Scene detail descendants use the same parseable rule and preserve the original
detail identifiers after the inserted activity id:

| Legacy detail key | Canonical detail key |
| --- | --- |
| `light-type:<world-id>:<type-key>` | `activity-light-type:<world-id>:sandbox:<type-key>` |
| `light:<world-id>:<type-key>:<light-id>` | `activity-light:<world-id>:sandbox:<type-key>:<light-id>` |
| `terrain:<world-id>:<terrain-id>` | `activity-terrain:<world-id>:sandbox:<terrain-id>` |
| `terrain-editor:<world-id>:<terrain-id>` | `activity-terrain-editor:<world-id>:sandbox:<terrain-id>` |
| `terrain-tool:<world-id>:<terrain-id>:<tool-id>` | `activity-terrain-tool:<world-id>:sandbox:<terrain-id>:<tool-id>` |
| `scene-panel:<world-id>:<panel-index>` | `activity-scene-panel:<world-id>:sandbox:<panel-index>` |

Long-term legacy key loader aliases are intentionally not kept. After persisted
map topology is normalized, live graph exposure should use the activity-aware
world/activity/surface hierarchy.

## Panel Ownership

Graph node panels are graph-map-specific.

Panel persistence should include `graph-map-id`:

```fennel
{:kind "graph-node-view"
 :graph-map-id "main"
 :node-key "..."
 :restorer-module "graph/view/node-view-panel-restorer"}
```

Restore rule:

- Only restore graph node panels for the active graph map.
- If a restored panel references a node key that prunes during map hydration, drop that panel from the map metadata.
- If map switching is implemented later while panels are open, capture/drop active-map panels before switching and restore the target map's panels after switching.

Duplicating maps is not required initially. If added later, duplication should copy panels as map-local state.

## Graph Map Manager

Add a runtime-owned manager:

```fennel
(GraphMapManager {:graph graph
                  :state graph-state
                  :data-dir world-dir})
```

Responsibilities:

- Own graph map records and active map id.
- Create the default map during migration.
- Load/hydrate the active graph map.
- Switch maps.
- Capture active map state.
- Persist map list/active map id into world state.
- Provide the current `active-graph-map` to graph canvas mode.

Runtime fields should avoid conflicting with old board globals:

```fennel
runtime.graph-map-manager
runtime.active-graph-map
runtime.graph-view
```

Global compatibility can keep `app.graph` and `app.graph-view` during the transition, but new code should prefer graph context supplied by canvas mode actions.

## Graph View Changes

`GraphView` attaches to a `GraphMap`, not a shared/raw `Graph`. The transitional
constructor key `:graph` and raw-Graph compatibility path have been removed; all
callers must pass a real `GraphMap` via `:graph-map`.

Required runtime contract:

- Construct `GraphView` with `:graph-map` set to the active graph map.
- Require the supplied graph map to expose GraphMap island APIs such as `list-islands`.
- Store map id on the view.
- Construct `GraphViewPersistence` with `:graph-map-id` or a per-map data directory.
- `capture-state` should capture selected/focused keys and delegate panel state to the map-specific node-view manager.

Later cleanup:

- Reduce reliance on globals such as `app.graph-view` in node views and tools.

## Sidebar UX

Graph mode should expose maps through an always-visible left dock, similar technically to drawing mode's sidebar but not semantically as layers.

Use canvas mode `ctx:set-left-dock-builder!` to install a graph map sidebar.

Initial sidebar contents:

- Title: `Graph Maps`
- Map list with active marker.
- `New` action.
- `Rename` action for active map.
- `Delete` action for active map, disabled if only one map exists.
- Active map stats: node count and edge count.
- Selected count.
- `Add Start` action, always visible and idempotent; it adds the `start` node to the active map when absent and does not duplicate it when present.
- `Find Node` search/list for nodes in the active map.
- Finder single-click reveals a node by selecting, focusing, and centering it in the active GraphView.
- Finder double-click opens the node panel/view after reveal behavior.

Do not include layer-like controls initially:

- No up/down ordering buttons.
- No visibility toggles.
- No simultaneous display controls.

User-facing labels:

- `Switch Map`
- `Add to Map`
- `Remove from Map`
- `Delete Map`
- `Delete Underlying Object`

## Action Semantics

Change generic node menu action `Remove` to `Remove from Map`.

Destructive object actions should remain explicit and node-specific:

- `Delete Entity`
- `Delete Notebook`
- `Delete Kernel`
- `Delete Conversation`
- future `Delete Underlying Object` only if backed by a declared capability.

Do not silently delete backing objects when removing from a map.

`Add Start` is map membership recovery, not automatic start-node re-seeding. It uses the registry-installed `start` key loader through the active `GraphMap` and does not delete or mutate backing domain objects.

String entity `Create child` is a node-specific domain action. It mutates `StringEntityStore` and `LinkEntityStore`, then materializes the new child node in the containing `GraphMap`; it does not add an explicit map edge.

## Migration Phases

### Phase 1: Introduce Single Graph Map

Status: complete.

- Add `graph/map.fnl`.
- Add shared `Graph:create-node-by-key`.
- Add tests for map add/remove/capture/restore.
- Route current graph mode through a single default graph map.
- Preserve existing behavior with one map.

### Phase 2: Persistence Migration

Status: complete.

- Add `graph/map-manager.fnl`.
- Migrate legacy `world.state.graph.graph` into default map state.
- Preserve unresolved keys/edges through map capture until hydration prunes or resolves them.
- Scope `GraphViewPersistence` by map id.

### Phase 3: Graph View Attachment

Status: complete, with transitional globals still present.

- Make `GraphView` consume the active graph map.
- Ensure node mounting sets `node.graph` to the graph map.
- Ensure `GraphView` drop/switch captures current map runtime state.
- Update graph canvas mode context enricher to expose `graph-map`.

### Phase 4: Map Switching UI

Status: functionally complete; UX polish remains.

- Add graph left dock.
- Implement create/rename/delete active map.
- Implement map switching with capture/drop/restore around the graph view.
- Keep only one graph map visible at a time.

### Phase 5: Panel Scoping

Status: complete.

- Include `graph-map-id` in graph node panel persistence.
- Restore only active-map panels.
- Prune panel records for invalid node keys during map hydration.

### Phase 6: Board Migration Later

Status: not started; still explicitly future work.

- Identify old board workflows to replace with graph map workflows.
- Move useful board item/connector behavior into graph nodes/actions.
- Remove old board mode only when equivalent graph map workflows are natural.

## Tests

Fast Fennel tests cover:

- `GraphMap` can add/remove nodes without deleting shared backing objects.
- `GraphMap` mounts nodes with `node.graph == graph-map`.
- Two graph maps load the same key into separate node adapter instances.
- Removing a node from one map does not remove it from another map.
- Derived link-entity edges are recomputed and not captured as explicit edges.
- Invalid persisted keys are pruned during hydration.
- Legacy graph state migrates into a default map.
- GraphView persistence uses map-specific metadata paths.
- Panel persistence includes and respects `graph-map-id`.
- Graph sidebar switches maps without leaving stale clickables/focus/movables.
- String entity `Create child` creates store-owned child/link entities, materializes the child in the containing graph map, and leaves the derived link edge out of captured topology.

Standard verification command:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

## Risks

Node code currently uses globals such as `app.graph-view` in several view modules. Map switching must not leave those globals pointing to a dropped view.

Store-event handling currently lives in `Graph`. Moving map-local behavior out of `Graph` must not lose useful active-map reactions, especially backing-object deletion of currently mounted nodes.

The migration should avoid compatibility shims beyond legacy persisted world state. New APIs should use canonical names once call sites are migrated.

Graph map delete must be explicit and non-destructive. It deletes the map artifact and its metadata, not backing objects.

## Open Questions

- Should manual edges and derived edges have different visual styling?
- Should graph map names be unique per world?

Resolved decisions:

- Map metadata is compacted during hydration when node keys prune.
- Active map selection/focus is captured with map state in `world.json`; high-churn layout/presentation/panel data stays in per-map metadata.
- New-format empty maps remain empty; legacy empty map state seeds `start` for compatibility.
