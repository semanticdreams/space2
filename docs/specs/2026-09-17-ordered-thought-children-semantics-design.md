# Ordered Thought Children Semantics Design

## Purpose

Space should support Logseq-style nested thought structure as a semantic foundation built from existing primitive entity types. The goal is ordered nested bullets/children, not UX polish. Users should be able to compose thought hierarchies from basic elements now and preserve a clear migration path to specialized outline, block, or knowledge-management entity types later.

The core semantic need is ordering: existing string entities can already be connected through link entities, but multiple child strings connected to the same parent are currently unordered.

## Design Direction

Use list entities as the authoritative primitive for ordered child membership.

- A string entity remains the primitive for thought text/content.
- A list entity represents an ordered collection of child graph keys.
- A parent thought can be associated with a child-list entity whose items are direct child string entity keys.
- Link entities remain available for semantic references, backlinks, citations, named relationships, or graph-visible relationship objects, but they are not the source of sibling order.
- Graph-visible parent/child edges may be derived from the list-backed containment relation, but graph topology and `GraphMap` state must not own child order.

This gives Space a foundation analogous to composing with `str`, `list`, and explicit references before introducing custom classes. A future specialized outline/block entity can recognize or migrate the constellation of string + list + link primitives without undoing overloaded link semantics.

## Semantic Model

For the initial foundation, ordered children are direct list items:

```text
parent string entity
  child-list -> list entity
    items -> [string-entity:<child-a>, string-entity:<child-b>, string-entity:<child-c>]
```

The child-list association is domain metadata owned by the relevant entity subsystem, not by graph core. The list entity owns ordering. The string entity owns text. Links, when present, own explicit relationships independent from order.

Occurrence/member indirection is intentionally out of scope for the first semantic layer. The same child key may eventually appear in more than one parent-associated list if transclusion/multi-placement is desired, but the initial model does not require distinct occurrence entities. If future requirements need repeated appearances in the same list, per-occurrence metadata, local aliases, collapse state per appearance, or collaborative sequence metadata, a later migration can introduce membership/occurrence entities.

## Approaches Considered

1. **Position metadata on link entities:** Directly adding `pos` or rank metadata to parent-child links keeps traversal simple, but overloads links with relationship, containment, ordering, and possibly occurrence semantics. Position is only meaningful within a scope, so every consumer would need conventions such as link kind, parent key, and conflict rules. This makes future migration harder because outline semantics are scattered across many relationship records.
2. **Parent-associated list entity (recommended):** Order is represented by the primitive whose purpose is ordered membership. Reordering is a list operation, containment remains distinct from references, and future specialized outline/block types can migrate from a well-bounded child collection.
3. **Dedicated outline/block entity immediately:** This could model Logseq semantics directly, but it prematurely commits to a custom class before the primitive composition model has been exercised. It should remain a future morph target, not the first foundation.

## Invariants and Constraints

- There is exactly one authoritative source for ordered children of a parent: the associated list entity.
- Graph core persists topology only; it does not persist child order.
- `GraphMap` owns presentation and interaction context, not ordered-child domain data.
- Links must not implicitly become ordered merely because they connect a parent to a child.
- Containment and reference are distinct semantics:
  - containment is ordered child membership in a parent-associated list;
  - reference is a link entity or another explicit relationship primitive.
- Reparenting is a logical move between parent-associated lists: remove the child key from the old child list and insert it into the new child list at the requested position.
- Child identity is preserved during moves; content is not cloned unless an explicit duplicate operation is requested.
- Direct child-key lists are acceptable for the first layer; occurrence entities are deferred.

## Future Compatibility

This design leaves room for later specialization:

- **Outline/block entity:** can absorb a parent string and its child list into a richer block model.
- **Membership/occurrence entities:** can be introduced if Space needs repeated child appearances, per-occurrence metadata, local display state, or collaboration-oriented sequence data.
- **Derived graph edges:** can expose list-backed containment to graph traversal and visualization without making graph topology authoritative.
- **Indexes:** can provide parent-to-children and child-to-parent-list queries for efficient traversal.
- **Typed relationships:** link entities can evolve toward richer references without carrying sibling-order semantics.

The design intentionally avoids generic `link.metadata.pos` as the foundation. Ordered relationships may still become useful later, but they should be introduced as an explicit ordered-relationship or membership concept rather than as an implicit convention on arbitrary links.

## Error Handling

Operations that create, associate, reorder, or move child lists should fail loudly when required stores or records are missing. They should not silently fall back to unordered links or no-op behavior. In particular, failures to create or resolve a child-list entity, child string entity, or associated key should surface explicit errors.

## Testing and Validation

Focused semantic tests should cover:

- creating or resolving a parent-associated child list;
- preserving child order across persistence reloads;
- appending children in deterministic order;
- reordering child keys through list operations;
- moving a child key between two parent-associated lists;
- keeping link entities independent from child ordering;
- ensuring any graph-visible parent/child edges are derived from the list-backed source of truth rather than persisted as authoritative map topology.

Because implementation will touch Space Fennel entity/graph code, validation should include project-native Fennel compile checks for touched files, constraints, and focused entity/graph tests.

## Out of Scope

- UX for editing, indentation, keyboard shortcuts, or Logseq-style block interactions.
- A dedicated block/outline entity type.
- Occurrence/membership entity indirection.
- Collaboration/CRDT ordering.
- Local per-occurrence collapse state, aliases, or display metadata.
- Treating generic link positions as ordered-child semantics.
