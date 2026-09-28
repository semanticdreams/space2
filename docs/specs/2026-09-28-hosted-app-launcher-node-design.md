# Hosted App Launcher Graph Node Design

## Context

Space now has a hosted app runtime, workspace mount path, command controls, async
progress/cancellation, result rendering, and recent run history. Those pieces prove
that a hostable app can run inside the active Space workspace, but there is still
no graph-level affordance for taking something the user is already looking at in a
graph map and launching it as a hosted app.

The desired shape is not a hosted app registry, catalog, marketplace, or search
system. Hosted apps may eventually live in arbitrary local folders, packages,
repos, peers, or remote systems. A central registry would either be incomplete or
become a second source of truth. Likewise, filesystem nodes should not grow
hosted-app-specific actions; that would couple the filesystem feature to hosted
runtime policy.

The graph already supports UX-purpose nodes: graph-visible operation surfaces that
own no domain records, read graph-map interaction context, and perform explicit
actions. A hosted app launcher fits that pattern: it is a graph-exposed tool that
looks at the active graph selection and offers a launch button when the selected
object can be resolved as a hosted app source.

## Goals

- Add a UX-purpose graph node for hosted app launching.
- Make the launcher reachable from the `start` node so users can discover it
  without entering raw graph keys.
- Render the launcher as a preview/view with status text and a `Host selected app`
  button.
- Read the active `GraphMap` selection and enable launching only for exactly one
  selected filesystem node that resolves by strict first-slice rules.
- Support both selected `.fnl` module files and selected directories through
  deterministic conventions, because the user is unsure which source shape will
  feel better in practice.
- Launch through the existing hosted workspace panel/mount stack.
- Keep graph topology persistence limited to graph keys, explicit map edges, and
  map-local interaction state; no hosted app source data is stored in graph
  topology.

## Non-Goals

- No hosted app registry, catalog, index, marketplace, or search.
- No app discovery scan across projects, directories, packages, networks, or
  remote machines.
- No hosted-app-specific actions on `fs:` nodes.
- No new hosted app manifest format in this slice.
- No launchables integration and no scanning `assets/lua/launchables/*.fnl`.
- No remote/non-filesystem source adapter yet.
- No persistence of launched app history or app source metadata.
- No sandboxing, permissions, approvals, process isolation, or auth policy.
- No replacement for the existing workspace panel controls, command controls, or
  hosted runtime contract.

## Approaches Considered

### 1. UX-purpose launcher node over graph selection (chosen)

Add a singleton graph node such as `hosted-app-launcher:workspace`. The start node
can materialize it like other top-level targets. Its preview/view reads the active
graph-map selection, explains whether the current selection can be hosted, and
launches the selected source through `app-host.workspace-panel` when the user
clicks the button.

Benefits:

- Fits graph doctrine: the graph exposes a focused operation surface, not a new
  owner for hosted app data.
- Keeps the dependency one-way: launcher reads graph selection; filesystem nodes
  do not know about hosted apps.
- Makes the launcher discoverable through `start` without adding catalog/search.
- Leaves future source kinds free to provide graph nodes of their own, as long as
  the launcher learns how to resolve those selected keys.

Costs:

- Requires a reliable live selection contract or refresh path from `GraphMap` to
  the launcher UI.
- A selected source cannot be proven hostable without loading code on explicit
  launch, so the pre-launch state can only say "resolvable candidate".

### 2. Hosted actions directly on filesystem nodes

Add `Open as hosted app` actions to `fs:` nodes when the path looks like a Fennel
module or project directory.

Benefits:

- Very direct for filesystem-backed apps.
- Avoids a separate launcher node.

Costs:

- Couples filesystem graph nodes to hosted app runtime policy.
- Does not generalize cleanly to non-filesystem sources.
- Makes app launching feel like a filesystem feature rather than a Space hosted
  runtime affordance.

### 3. Registry/catalog/search node

Create a hosted app registry/catalog and expose catalog/search result nodes.

Benefits:

- Could eventually support global browsing and remote app directories.

Costs:

- Introduces a false source of truth before Space has package/distribution
  semantics.
- Encourages background scanning/search and persistence that are explicitly not
  needed for the first graph launcher slice.
- Conflates "where apps can come from" with "how a selected graph object is
  launched".

## Decision

Use Approach 1. Add a graph-exposed hosted app launcher node that can be reached
from the start node, observes active graph-map selection, and launches a selected
filesystem source through the existing hosted workspace panel. The first slice
supports `.fnl` files and directories through deterministic conventions, but does
not scan, index, or persist discovered apps.

## Design

### Graph node and discoverability

The launcher is a UX-purpose graph node with stable key:

```text
hosted-app-launcher:workspace
```

It should be installed by the built-in graph extension mechanism rather than by a
one-off global. The node adapter owns runtime UI state only:

- current selection status;
- latest launch status or error;
- signal subscriptions needed to refresh the view;
- methods used by its preview/view, such as `refresh-selection` and
  `open-selected`.

The `start` node should include a `Hosted App Launcher` target so users can add
the launcher to any graph map through the same start-node workflow used for other
top-level graph surfaces. A root graph action to add the launcher may be useful,
but the start-node target is required.

### Selection input

The launcher reads the active graph-map selection. It enables launch only when all
of the following are true:

1. exactly one node is selected;
2. the selected key uses the `fs:` scheme;
3. the selected graph node or key resolves to a concrete filesystem path;
4. the path resolves to a first-slice hosted app source candidate.

Invalid states are user-visible launcher statuses, not silent no-ops:

- no selection;
- multiple selections;
- selected node is not an `fs:` node;
- selected path does not exist;
- selected file is not a supported `.fnl` source;
- selected directory has no supported entry;
- selected directory is ambiguous.

If current graph selection changes are not emitted from `GraphMap` today, add a
small graph-map selection signal/setter so UX-purpose nodes can observe selection
without relying on `app.graph-view` globals. This signal is interaction context,
not domain data, and remains part of map-local graph state.

### Source resolution

Add a focused hosted app source resolver that converts a selected `fs:` source to
a launch candidate. The resolver does not mount or execute apps while merely
checking selection state.

File rule:

- support `.fnl` files;
- derive a module name relative to the nearest `assets/lua` root when present;
- otherwise derive a conservative single-module root for the selected file;
- reject unsupported extensions explicitly.

Directory rule:

- support a directory only when exactly one recognized entry exists;
- recognized entries are deliberately small and deterministic, such as
  `assets/lua/main.fnl`, `main.fnl`, or `init.fnl`;
- do not recurse and do not scan for arbitrary app-looking files;
- reject zero matches as not launchable and multiple matches as ambiguous.

The resolver returns either an explicit success record with source kind, selected
path, entry path, Lua/Fennel root, module name, and display label, or an explicit
error record with a stable reason and message. It must not throw for ordinary
invalid selections.

### Launching

On button click, the launcher converts the current source candidate into a hosted
module wrapper and calls the existing workspace panel open path. The wrapper:

- temporarily adjusts Fennel module resolution for the selected source root;
- suppresses standalone-main execution using the existing app suppression
  convention when loading the module;
- requires the selected module;
- validates that it exposes `create(host)`;
- calls `create(host)` through the existing hosted runtime contract;
- restores all temporary process/global state on success and error.

Launch failures update the launcher status visibly and do not silently no-op.
Successful launch should report the launched label/module and then let the
existing workspace panel own pause/resume/step/close, hosted command controls,
result display, async progress/cancel, and run history.

### View and widget behavior

The launcher preview/view should be intentionally small:

- title: `Hosted App Launcher`;
- status text describing the current graph selection;
- source summary when enabled;
- `Host selected app` button with a clear launcher icon;
- latest launch success/error message.

The view owns its direct child widgets and drops signal subscriptions/buttons on
teardown. Missing required context should assert loudly rather than falling back
silently.

### Graph persistence

Persisting a graph map containing the launcher stores only normal graph topology,
such as the launcher node key and explicit edge from `start` if the user created
one. It must not persist selected source paths as hosted app records, discovered
app metadata, or launch history.

If a selected `fs:` node later disappears, normal graph-map hydration/fs node
resolution rules apply and the launcher reports an explicit unavailable status
when asked to launch.

## Error Handling

- Missing graph-map context is a structural error.
- Ordinary unsupported selections return disabled/error statuses.
- Directory ambiguity is an explicit error; the launcher must not pick one entry
  silently.
- Module load failures and missing `create(host)` are explicit launch errors.
- Temporary `fennel.path` and app suppression state are restored on all launch
  paths.
- Workspace panel open failures are surfaced in the launcher status.

## Testing

- Graph-map selection tests cover live selected-key updates and selection-change
  emission if a new signal/setter is needed.
- Source resolver tests cover no selection, multiple selection, non-`fs:` keys,
  missing paths, unsupported files, selected `.fnl` files, nested module files,
  directory success, directory no-entry, and directory ambiguity.
- Launcher node tests cover built-in key-loader resolution, start-node target
  availability, disabled statuses, enabled statuses, launch success through a
  fake workspace panel, and launch failure status.
- View/widget tests cover button enabled/disabled state and status refresh if the
  existing widget harness can validate it narrowly.
- Validation order follows Space Fennel rules: compile check, constraints,
  focused graph/hosted launcher tests, then broader relevant tests because this
  crosses graph, widgets, and hosted runtime.

## Acceptance Criteria

- `hosted-app-launcher:workspace` resolves through the built-in graph extension
  loader.
- The `start` node exposes a `Hosted App Launcher` target that materializes the
  launcher in the active graph map.
- The launcher preview/view displays current selection status and a `Host selected
  app` button.
- The button enables only for exactly one selected `fs:` source that resolves by
  first-slice file or directory rules.
- Clicking the button opens the hosted app through the existing workspace panel
  path.
- Invalid selections and launch failures produce explicit launcher status.
- No hosted app registry, catalog, search, fs-node hosted action, manifest format,
  launchable scan, or hidden graph expansion is introduced.
- Graph topology persistence remains limited to node keys, edge keys, and
  map-local interaction state.

## Follow-Up Work

- Additional source kinds, such as package nodes, git repo nodes, remote URL nodes,
  or peer Space nodes, can be added by teaching the launcher to resolve those
  graph-selected source keys.
- A manifest format may be useful once app packaging/distribution decisions are
  made.
- Richer launch configuration, permissions, process isolation, and durable app
  sessions remain separate product slices.
