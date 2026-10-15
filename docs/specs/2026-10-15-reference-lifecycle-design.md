# Stable references, morphing, and logical deletion

## Intent and approved behavior

Users work with entities, not identity wrappers. Morph changes an entity's
representation while preserving its logical relationships. Deletion removes the
logical entity and its live incoming references, including references belonging
to unopened containers. Removing a node from a map changes presentation only.

The approved rules are:

- Morph preserves links, ordered container membership, and presentation context.
- Genuine deletion removes incoming memberships and dictionary slots, invalid
  link entities, and references to those invalidated link entities.
- Deleting a list, dictionary, notebook, or link does not delete its independently
  owned members, values, or surviving endpoints.
- Deleting code removes every workflow step using it and each such step's
  incident workflow edges. Other steps, definitions, shared unrelated code, and
  historical runs/events remain intact. This cascade was explicitly approved.
- Map-only removal never edits owning-domain records.
- Identities are reused implementation records, not additional visible nodes
  automatically inserted when a user creates a relationship.

## Evidence and remaining empirical gates

The initial investigation reproduced realistic authoring, morph, deletion, and
fresh-process reopen workflows twice at revision `4810b202`. After updating to
`origin/main` revision `524a2ab9`, focused native experiments verified the current
catalog/composition boundary and these additional cases:

| Observation | Consequence for the design |
| --- | --- |
| Selected link/list creation stores concrete keys; list add-item wraps identities | Normalize at the owning write boundary, not individual buttons |
| Raw list cleanup differs between mounted and unopened owners | Presentation listeners cannot own durable cleanup |
| Identity meaning survives morph while link projections disappear | Persistence integrity and projection reconciliation need separate tests |
| Loaded identity lists follow morph; unopened identity notebooks retain valid meaning | Reuse the existing identity mechanism rather than replace it |
| Mixed raw and identity membership creates a logical duplicate | Normalize before ordered uniqueness checks |
| Genuine deletion leaves identity/list/dict/link/notebook references dangling | Add coordinated incoming-reference cleanup |
| Direct aliases and an upstream alias resolve through morph but retain dangling references after deletion | Traverse identity dependency closure, not only exact endpoint strings |
| Self/two-identity cycles raise the specific errors in both tested resolvers | Preserve explicit cycle rejection; relationship cycles are a different case |
| Deleting K1 in a K1/K2 relationship cycle leaves K2 | Dependency deletion needs a visited worklist |
| Deleting code leaves three dependent steps and six incident workflow edges | Use definition-owner cleanup, not just graph-node removal |
| Canonical code deletion leaves a separate default cache readable until restart | Compose one canonical owning instance and propagate it consistently |

The current-head cycle check produced all six expected errors with unchanged
domain/topology state. A preceding whole-child timeout occurred before fixture
evidence; its exact cause was not established and is not called a resolver loop.

The detailed, reviewed diagnostic records remain ignored artifacts under
`build/reference-probe/`. They are investigation evidence, not the permanent
regression suite or proof that the proposed implementation works.

Board/unopened-world cleanup, inactive-map replacement, and failure/restart
behavior require new RED tests before their respective production changes.
Existing lost list-edge tags and dictionary equal-endpoint slot coalescing are
separately observed provenance limitations, not vanished domain relationships.
Those observations must remain visible rather than be normalized away.

## Architecture and alternatives

Use the existing persisted identities, a bounded graph-independent application
lifecycle service, and explicit adapters for known reference owners. Domain
stores continue to own records; graphs continue to own exposure/topology.

Rejected as the default design:

1. Repair each consumer inside every morph: dependencies grow with every new
   reference holder and conversion.
2. Promote all raw references only at morph time: requires complete discovery and
   many writes during every first replacement, while leaving ordinary authoring
   and deduplication inconsistent.
3. Replace concrete keys with a new redirect mechanism or universal CRUD/store
   registry: duplicates existing identity semantics and exceeds the demonstrated
   problem. The immutable entity-type catalog remains browsing metadata.

### Stable references at store writes

IdentityStore supplies shared graph-independent ensure/resolve operations.
Resolution returns the terminal key and traversed identities, rejects cycles,
and reports depth exhaustion explicitly rather than returning a partial target.
Ensuring a raw key reuses an existing direct identity deterministically or creates
one; a supplied identity key retains its exact identity. Distinct explicit
identities are not merged simply because their current target happens to match.

List items, dictionary values, notebook items, and populated link endpoints are
normalized on all owning-store creation/update/add/set paths. List/notebook
uniqueness runs after normalization, preserving the first occurrence and order.
Named dictionary slots remain distinct. Empty link draft endpoints remain empty.
Identity target fields are representation pointers and are not recursively
wrapped. Typed workflow code IDs and board semantic-link IDs retain their formats.

Reference-bearing factories accept the canonical `:identity-store` dependency.
An explicitly constructed isolated store may construct an isolated identity store
in its own data root; its caller must inject shared identity ownership when
composing several stores. Default getters supply the canonical identity store.
Root/instance mismatches during composition are explicit errors. No compatibility
option aliases or new default-publication framework are introduced.

### Application commands versus physical retirement

Introduce application-level logical delete and morph coordination over explicitly
injected canonical stores. Preserve existing node-facing delete methods, but
route their user intent, board destructive removal, and workflow-step deletion
through the coordinator.

Rename the six entity stores' physical deletion primitive to `retire-entity!` and
the notebook primitive to `retire-notebook!`, without old-name aliases. These are
internal persistence operations used by the coordinator and trusted rollback or
representation-retirement paths. They are not logical deletion commands.
Migrate every production and test caller deliberately. No method monkeypatching,
constructor-pair returns, or global replacement of lazy default factories is
needed. Ordinary node actions retain their existing frontend names.

Main composes the canonical identity and owning stores, obtains its code store
through the canonical default/root contract, constructs lifecycle services, and
injects them through the existing extension/runtime composition. Custom injected
stores remain supported through explicit ownership, not silent fallback to a
different default. Store caches/signals publish only after successful persistence;
required enumeration/read/write/remove failures are surfaced immediately.

### Explicit live-reference owners

The fixed owner set inventories and prepares changes for:

- list membership, dictionary slots, link endpoints, and notebook membership;
- identity targets, including upstream aliases and multiple direct identities;
- workflow definition steps referencing code and dependencies on retired steps;
- board item subjects and semantic connector IDs across persisted worlds;
- graph presentation state across loaded and inactive maps/worlds, including
  node keys, explicit edges, selection/focus/outline/island references, and
  representation-keyed node metadata.

Histories, execution events, logs, and provenance snapshots are not live incoming
references. Do not rewrite arbitrary strings recursively. Enumerate documented
schemas using their owning systems. The initial supported destructive targets are
the six entity schemes, notebooks, and workflow-step keys; unknown mutating target
schemes fail explicitly. Generic external graph keys remain valid reference values
without implying filesystem/session deletion support.

An explicitly selected identity record can itself be deleted without deleting its
independently owned target. Ordinary object deletion reached through a reference
operates on the represented object, not a hidden wrapper.

### Deletion and dependency closure

Prepare and validate the complete affected closure before destructive writes.
Use a deterministic visited worklist: incoming link invalidation adds that link
as a retiring target; aliases and dependent workflow steps likewise extend the
closure. This terminates on relationship cycles without treating them as invalid
identity-resolution cycles. Invalid identity cycles stop preflight explicitly.

Owners remove reference sites or dependent objects, not unrelated targets.
Workflow cleanup reuses the existing step-removal semantics with dependent-edge
removal. Container members and history remain byte-preserved except documented
owner metadata such as an edited definition's update timestamp.

Keep the requested target available until durable incoming cleanup succeeds.
Retire it physically only through its owning provider. Finish cache/projection
reconciliation and persistence checks before reporting success. Repeating a
completed deletion is a defined no-op with no fabricated success for IO failure.

### Morph coordination

Conversion-specific code prepares the new representation; shared coordination
owns identity retargeting, supported legacy-reference migration, source
retirement, and replacement notifications. String-to-code remains the only new
conversion in scope. Keep its existing result information available to callers.

Reserve one replacement ID, create one code record preserving the original text,
and retarget every direct identity for the old representation. Upstream identity
IDs/chains remain intact while resolving to that replacement. Migration covers
recoverable raw reference sites before source retirement. No consumer-specific
repair is embedded in an individual morph.

### Presentation and persisted-world coherence

Capture participation before store removal can erase it. Replace the source only
in maps that contained it; preserve relevant explicit topology, keyed metadata,
selection/focus and island state. Do not fill unrelated maps with endpoints.
Update inactive persisted topology through its owner so reopening cannot restore
the retired representation or lose known replacement participation.

Reconcile link projections against resolved identities and link IDs after
replacement installation, including upstream-alias consumers. Lists/notebooks/
dicts refresh from committed domain state. Graph-node removal and identity
projection listeners no longer persist container membership edits.

Board cleanup uses nondestructive board model operations; it must not invoke the
view's existing subject-deleting removal as a cleanup primitive. Synchronize live
models, retained snapshots, activity-session mirrors and persisted world state so
later capture/drop cannot restore stale references. Board subjects use stable
identity meaning. String subjects retain their editable widget; a morphed code
subject can use existing Text rendering of source, preserving item ID, transform,
state and connectors without inventing a code editor or a pseudo-readonly Input.

Do not bundle a general graph-edge identity redesign. New lifecycle behavior must
preserve authored relationships and explicitly distinguish connectivity from
native provenance. Any narrowly required derived-edge capture fix must preserve
unrelated explicit edges and receive its own regression coverage.

## Existing data and failure behavior

Run an idempotent, versioned migration through the same owners before relying on
the new reference invariant. Normalize recoverable raw references; preserve
distinct identities, owner IDs, order, positions and named slots. A second pass
makes no changes. Already-dangling historical references are reported, not guessed
at, silently deleted, or redirected to an unrelated replacement.

Changes span files, so do not promise atomic multi-file transactions. A minimal
durable pending intent records the operation/source fingerprint, prepared closure
and before/after checks, and the reserved morph replacement ID/payload. Persist
it before applying changes. Failures report the operation and affected owner;
they do not silently roll back, recreate deleted entities, or discard progress.

The same target action resumes its existing pending intent. Startup recovers
pending work before exposing affected worlds; conflicting external edits or IO
failures stop with explicit diagnostics rather than overwriting changed data.
Validate this contract with injected write/retirement/restart failures before
claiming recovery. Use existing atomic JSON utilities and a single-writer,
serialized-operation contract; do not introduce a CLI, general transaction engine,
cross-process atomicity, or automatic concurrent-writer merging.

## Acceptance and delivery gates

Promote the diagnostic workflows into permanent native tests, retaining observed
RED evidence before implementing each behavior. Cover real authoring paths,
loaded/unopened owners, both link directions, shared identities, multiple direct
aliases and alias chains, identity-cycle rejection, relationship-cycle deletion,
logical duplicate prevention, container-member preservation, code/workflow cleanup
with unchanged history, boards in inactive worlds, inactive maps, and cold reopen.

Test ordinary map-only removal with byte comparisons. Test owning-store identity
and cache coherence, not only equal directories. Exercise empty roots and drafts,
missing/malformed inputs, unsupported target errors, and failure/restart conflict
handling. Record connectivity and provenance separately. Board and inactive-world
RED tests precede their owner-adapter design/implementation.

Validation order is native Fennel compile, blocking constraints, focused tests,
then broader validation appropriate to persistence/startup risk. This change
requires the full local test suite before finishing, plus applicable PR CI.
Use the canonical absolute asset/macro paths and isolated test-data settings.
Re-evaluate against current `origin/main` before final validation/integration.

## Out of scope

Additional morph types, filesystem/session deletion, rewriting history, new code
editing UI, universal CRUD/type registration, default-store publication redesign,
persisted reverse indexes, unmeasured performance claims, broad edge/provenance
redesign, and cross-process transaction guarantees are excluded. Evidence gaps
remain explicit until their corresponding tests run; no diagnostic RED result is
an implementation or release pass.
