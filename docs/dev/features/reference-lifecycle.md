# Reference lifecycle: stable relationships, morph and logical delete

The graph exposes domain objects; it does not own them. `reference-lifecycle`
coordinates stable relationships and genuine deletion across five fixed owners.
The immutable [entity-type catalog](entity-type-catalog.md) is browsing metadata,
not a CRUD or owner registry. See also [Graph Maps](../graph-maps.md),
[identity](../notes/graph-identity.md) and [morphs](../notes/morphs.md).

## Composition and startup

`Stores` contains `base-dir`, `identity-store`, `string-store`, `code-store`,
`list-store`, `dict-store`, `link-store`, `notebook-store`, and `workflow-store`.
Use one normalized `fs.absolute(base-dir)` and the **same IdentityStore object**
for every reference-bearing store. Equal roots do not make substitute instances
canonical: caches, signals and providers must agree by identity as well as root.

Main delegates canonical store composition to
`graph/extensions/builtins/composition.init-reference-stores!`. In particular,
`app.code-store` comes from `entities/code.get-default`, not a second independent
cache. Main constructs WorldManager, composes all five real owners, then calls
`start!` **before** ensuring built-in loaders and activating the first world.
Recovery/migration failures stop startup; affected worlds are not exposed.
Custom composition must provide the same five real owners and gating, not empty
stand-ins. The fixed-owner protocol is internal, not an extensible registration API.

Graph and GraphMap accept canonical `:lifecycle` and expose `reference-lifecycle`.
A map inherits its shared Graph's service and rejects a conflicting explicit
instance. A destructive node action resolves its explicit service or its mounted
graph's service, rejects conflicting services, then checks exact store ownership,
root and identity-store dependency. Detached nodes need explicit injection; they
must not fall back to an unrelated default. Browser-created children deliberately
acquire the mounted lifecycle after normal submission/mounting. Browser factories
retain their existing exports; not every child needs an explicit service field.
Loaded BoardView providers and native board identity are checked too.

## Authoring and identity normalization

IdentityStore's graph-independent `resolve-key` (terminal key plus traversed chain),
`find-by-target-key`, and `ensure-key` do not need graph exposure. Resolution
rejects cycles and depth exhaustion (32 identity hops); missing identities/empty
targets remain explicit unresolved references. `ensure-key` preserves a supplied
`identity:<id>` exactly; a raw key reuses the lexicographically lowest existing
direct identity or creates one. Explicit aliases/chains are not merged merely
because their terminal targets agree. Normalization never adds visible wrappers.

All list/notebook create/update/add/reorder paths, dictionary create/update/set
paths and populated link endpoint writes normalize at the **owning store**.
Ordered uniqueness runs after normalization, keeping first occurrence and order;
different explicit aliases remain different members. Dictionary slot names remain
distinct even when values match. Removing an explicit identity membership is exact;
raw-key removal is nonallocating. Empty draft link endpoints remain empty.
Identity target pointers, workflow code IDs and board semantic-link IDs keep
their native formats. Generic external graph keys can be relationship values;
this does not authorize deleting files, sessions or other external objects.

### Presentation and concrete preview providers

List labels and notebook previews resolve meaning through the containing store's
own IdentityStore, without normalizing or rewriting stored membership. Canonical
keys still identify ordered members and remove/move actions; distinct aliases
remain distinct even when they display the same terminal object. Notebook previews
pass the concrete terminal key to the containing Graph/GraphMap's registered load
path, retaining that adapter's configured content provider, root and lifecycle.
The notebook's identity owner and its StringStore for explicit creation are not
substitute preview providers. The graph/map owns adapters; rows own only their
preview widgets. Passive String preview initialization does not author content;
genuine inline edits still submit value-only updates through the concrete owner.
Unresolved/missing targets remain explicit nonauthoring text, while resolution,
read, loader and required-preview failures propagate rather than becoming absence.

## Logical versus physical operations

Use `Lifecycle:delete!(graph-key)` for supported six entity schemes, notebooks
and `workflow-step:<definition-id>:<step-id>`. Existing node/frontend action names
(`delete-entity`, `delete-notebook`, workflow delete, Board destructive removal)
delegate to this service. Unsupported destructive schemes error explicitly;
repeating an already completed deletion is a no-op, not an IO-failure escape.

A deterministic visited closure removes incoming list/notebook membership and
dictionary slots, invalidates incoming links, then follows references to those
links, aliases/upstream identities and dependent workflow steps. Relationship
cycles terminate; identity-resolution cycles are invalid and fail preflight.
Deleting a container/link does **not** delete independently owned members/values/
surviving endpoints. Deleting an explicit identity removes its upstream dependent
references but not its independent target. Deleting the represented object reached
through a reference uses that object's concrete key, not the hidden wrapper.

Deleting code removes **all** steps using that code across definitions and all
incident definition edges. Other steps, edges, definitions and code survive.
Runs, run steps, execution events, logs and provenance snapshots are historical,
not live incoming sites: their persisted bytes are not rewritten.

The six entity stores' `retire-entity!` and notebook store's `retire-notebook!`
are **INTERNAL physical persistence primitives**, with no old-name aliases.
Similarly, prepared persistence/reconciliation methods are internal owner tools.
They do not calculate logical closure. Only the coordinator and trusted,
attempt-owned authoring rollback/representation retirement may use them.
Board acquisition rollback removes only IDs allocated by that attempt, identities
before strings; cleanup failure is explicit and preserves the target for diagnosis.

`GraphMap:remove-nodes`, `clear!`, map deletion and nondestructive board-model
removal are presentation operations, not logical deletion. Ordinary map removal
and identity projection listeners never persist container cleanup. Domains retain
their bytes even if the map is empty. Graph core stores topology, never domain CRUD.

## The five owners and registered schema locations

An Inventory is `{records: {graph-key: {address, value, snapshot}}, sites: [Site]}`.
A Site is `{address, field: [schema-field...], target-key, kind}`. Locations are
schema-owned, not recursive arbitrary string matches.

| Fixed owner | Live locations / responsibility |
| --- | --- |
| `entities` | List `items[index]` (`list-item`); notebook `items[index]` (`notebook-item`); dictionary `items[name]` (`dict-slot`); link `source-key` / `target-key` (`link-source` / `link-target`). Owns string/code/container/link/notebook persistence and retirement. |
| `identities` | Identity `target-key` (`identity-target`), direct/upstream closure, reserved identity records. Targets are pointers, not recursively wrapped. |
| `workflows` | Definition `steps[index].code-entity-id` (`workflow-code`) and incident `edges` with `source-step-id` / `target-step-id`. Typed code IDs stay IDs. |
| `worlds` | Board subject sites (`board-subject`) and owner-specific graph/board/view/metadata transformations below; exclusive durable writer of `world.json` and map `metadata.json` during lifecycle operations. |
| `runtime` | Loaded native world/map participation and transient mirror installation only; no durable Changes, no persistence or activation. |

Only the six site kinds `list-item`, `notebook-item`, `dict-slot`, `link-source`,
`link-target`, `board-subject` consume stable-key rewrites. All others use their
own typed transformations. World schemas:

- Board `items[index].subject-key` across root `board`,
  `activity.sessions.board.board-state`, `runtime.board-state` and
  `runtime.activity-session-state.board.board-state`. Items retain ID/order,
  type, position/rotation/size and state. Connectors retain ID, source/target item
  IDs, kind, semantic-link ID and state; retirement removes incident connectors
  or retired semantic links, never deletes surviving endpoint subjects.
- Graph native map `nodes`, explicit `edges[].source/target` and attributes,
  `selected_node_keys`, `focused_node_key`, `outline_root_keys`, `islands[].members`
  and ordered-list `islands[].state.list-key`. Both current `graph.maps` and
  supported legacy graph-state shapes are read through the owner.
- View `views.open-views` panel node keys, `views.open-node-keys`,
  `extra_panels`, selection/focus and corresponding `mode_states.spatial` fields.
  Graph sessions retain per-map `graph-view-states` and current `graph-view-state`
  in activity and retained runtime/session records. Only `graph-node-view` panels
  in canvas/HUD shells participate; unrelated panel payloads remain opaque.
- Map metadata `positions`, `sizes`, `presentations` indexed by concrete
  representation key, and `panels` / `extra_panels` node keys (including nested
  `panel.node-key`). Cameras, mode-keyed camera state and arbitrary provenance
  text remain unchanged. If both representation keys already have metadata,
  unaffected target metadata wins.

## Preparation, frozen bytes and transient mirrors

Every Owner returns `Preparation = {changes: [Change], runtime-state: [RuntimeCapture]}`,
including both empty arrays when appropriate. Entities/identities/workflows and
WorldOwner return empty runtime-state. RuntimeOwner returns **empty changes**.
Inventories/preparation are read-only: no persistence-producing GraphView capture
or inactive-map hydration. Loaded nonpersisting snapshots merge into WorldOwner
after-images; one normalized durable path receives one aggregated Change.
Duplicate paths across owners are an error, not last-writer-wins.

```
Change = {owner, address, path, format: "json"|"string",
          phase: "replacement"|"incoming"|"retire",
          before-check: string|false, after-check: string|false,
          after-bytes: string|false}
RuntimeCapture = {owner, world-id, map-id: string|false,
                  before: ReferenceState, after: ReferenceState}
ReferenceState = {board?, maps?, views?, metadata?}
```

Captures use native persisted world/map IDs, not paths, adapter objects or
generated runtime IDs. Preparation validates the fixed owner namespace and rejects
duplicate `(owner,world-id,map-id)` tuples. A false map-id is world/board/shared
Core state; a map capture contains only that native map's state. Before/after
roles must match and be JSON-safe. No later arbitrary-key discovery.

Board captures keep **separate** native model, `state.board`, retained
`runtime.board-state`, activity-board and runtime activity-session board roles.
Map/view captures keep native current view, graph-owned canvas/HUD panels, retained
per-map/current view snapshots and activity/runtime graph-session snapshots as
separate roles. Metadata captures retain native per-map persistence caches, not
another durable path writer. Presence of each role freezes during preparation.
Replay installs supplied captures only into still-loaded matching IDs; it never
recaptures, hydrates absent maps, switches worlds or saves. A cold restart with
no loaded maps skips transient installation safely: later ordinary activation
uses WorldOwner's durable after-images. Reconciliation failure retains pending.

`RecordUtils.snapshot(path, format, decode)` takes an explicit pure owning decoder.
It preserves original raw `bytes`; `value` is the decoded owning-domain record;
`check` is independently derived from original bytes (stable parsed JSON for JSON,
exact bytes for strings/Markdown). Absent records have `bytes=value=check=false`.
Required malformed/unreadable records error with their path.

Prepared persistence decodes frozen `after-bytes` with the store's pure decoder,
then verifies reserialization against after-check before atomic persistence.
No new timestamps, references or payloads may be generated on replay. Workflow
JSON timestamps are ISO strings; decoded in-memory workflow timestamps are numeric.
Checks always use serialized bytes, never the in-memory numeric form. Publication
updates held cached records only after successful persistence, preserving their
identity. Failed writes leave caches unchanged; failed publication remains pending.

## String → code morph and frontend compatibility

The sole conversion remains string to code. The ordinary morph adapter resolves
canonical lifecycle ownership **before** reading the source. It calls
`replace!(source-key, payload-or-builder)` with a deferred synchronous read-only
builder for `{name: "", language: "fnl", source: original-text, kernel: 0}`.
The coordinator reserves one replacement and reference plan, retargets all direct
identities, preserves upstream chains and relationships, replaces participating
presentation keys, reconciles runtimes, then retires the requested source last.
Code uses native Text, not Input/a pretend code editor; board item identities,
transforms/state/connectors and surviving focus remain owned by their native UI.

MorphResult remains `{code-entity, code-key, target-key, target-type,
updated-identity-keys, source-key, source-id}`. Frontend delete methods retain
their owning source-record results. The morph registry still emits its normal
`morphed` event after successful application; owner reconciliation is not delegated
to that event. Map replacement never fills unrelated maps with new participation.

Table payload retries require the same complete request, unchanged. A matching
pending builder request intentionally matches morph kind/source, replays the
frozen intent **without invoking the builder or reading retired source**, and
returns its original result information. Unrelated pending requests conflict.
Without pending, the builder runs once per fresh preparation attempt inside the
busy/readiness/ownership checks; it must not yield, mutate stores or invoke
lifecycle commands. Builder functions are never serialized. Pre-journal failures
can lead to another fresh preparation attempt; there is no exactly-once promise.

## Pending intents, migration and operational recovery

`<base-dir>/reference-lifecycle/pending.json` freezes operation ID, source
fingerprint, dependency closure, replacement reservations/payload/timestamps,
reference plan, serialized Changes and RuntimeCaptures **before** applying them.
`migration.json` records version1 and dangling Site reports. Startup first checks
owner composition/preflight, then reads/replays pending, then performs versioned
migration if not completed. Migration normalizes recoverable raw sites while
retaining IDs/order/named slots/presentation; historical missing known targets are
reported, not guessed, deleted or redirected. Completed startup is idempotent.

Operations are serialized in one application **single writer**. Replay re-derives
paths through canonical owners, accepts only persisted before/after checks, and
verifies after-images. Third-state external edits stop recovery without clobbering
them or discarding pending. Atomic JSON replacement is per file: there is **no
multi-file atomicity**, cross-process transaction or concurrent-writer merge.
Do not delete a pending file to hide failure or manually recreate a retired source.
Inspect the intent and reported operation/owner/path, resolve the real IO/conflict
cause, then retry the same command or restart through `start!`.

Pending-aware validation/application/reconciliation failures add operation
ID/kind/source and known owner/address/path while retaining the full original
cause. Initial preflight failures happen before pending is read and report their
original explicit cause/path, not invented operation context. Both release the
busy guard and remain retryable. Committed notification precedes pending removal;
callback/clear failure may cause notification again on retry. Consumers must
allow **at-least-once** notification, not assume exactly once.

## Permanent validation matrix

All modules below are registered in `tests.fast`; the new integration prefix is
`reference lifecycle integration`. This is native regression evidence, not a
claim of general visual snapshot coverage or release/CI approval.

| Surface | Permanent modules in `assets/lua/tests/` |
| --- | --- |
| Graph-free identity, aliases/chains, cycle/depth, no wrapper exposure | `test-reference-lifecycle-identity.fnl` |
| Every owning write boundary, selected authoring, DI, ordered dedup/explicit removal | `test-reference-lifecycle-writes.fnl`, integration |
| Strict IO, migration/dangling reports, pure decoders, raw records | `test-reference-lifecycle-owners.fnl` |
| Link dependency cycles, container preservation, supported/missing targets, workflow closure | `test-reference-lifecycle-commands.fnl`, integration |
| Pending tampering/conflicts, deferred admission/source-last, zero-write publication | `test-reference-lifecycle-recovery.fnl`, integration |
| Persisted/unopened worlds, inactive maps, native metadata and mirrors | `test-reference-lifecycle-worlds.fnl`, integration |
| Native board Text/Input transition, opaque state, deactivation/slot reactivation | `test-reference-lifecycle-board.fnl` |
| Frozen capture nonrecapture/nonhydrate, live panels/focus, projection-only listeners | `test-reference-lifecycle-projections.fnl`, integration |
| Actual browser child deletion, startup gating/canonical providers/frontend retries | `test-reference-lifecycle-browsers.fnl`, `test-reference-lifecycle-composition.fnl`, integration |
| Code/frontend → multi-definition workflow cascade with exact history bytes; fresh native child restart | `test-reference-lifecycle-integration.fnl` |

Connectivity and provenance are distinct. Link IDs/explicit attributes and actual
surviving relationships are tested; historical list-edge tag loss and dictionary
same-endpoint slot provenance coalescing remain separately parked limitations.
They are not evidence of vanished domain relationships and are not claimed fixed.
This feature preserves existing boards; it is **not** a general board-to-graph
migration. Additional morph types, code editing, generic CRUD and external object
deletion remain out of scope.
