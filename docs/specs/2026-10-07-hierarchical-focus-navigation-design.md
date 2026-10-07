# Hierarchical Focus Navigation Design

## Context

Space already has focus nodes, focus scopes, flat `Tab` traversal, directional
`h/j/k/l` and arrow traversal, and graph node focus targets. Graph view uses a
single `graph-node-points` focus scope and creates one stable focus node per
graph node. That node represents the graph node itself: graph-node commands,
selection commands, preview expansion, and context-menu actions all key off that
focused graph node.

Expanded graph node previews are built with the ambient widget build context.
If preview content creates focusable widgets, those widgets attach to the
current focus context scope, not to a graph-node-specific child scope. This
means the system has focus hierarchy primitives, but graph previews are not yet
modeled as an explicit container entry point with an interior focus scope.

The desired behavior is to distinguish focus on a container-like thing from
focus inside that thing. For example, when a graph node preview is focused,
graph-node actions should be available. When the user explicitly enters the
preview, focus should move to widgets inside the preview and widget-local
actions should apply. The user should also be able to exit back to the graph
node focus target.

## Requirements

- Add generic focus hierarchy semantics; do not make graph previews a one-off
  special case.
- Do not introduce a separate "shell node" type. A normal focus node may
  optionally advertise an entry scope.
- Allow arbitrary nesting: a focus node can be a child of one container's scope
  while also being the entry point for another scope.
- Preserve the graph invariant that graph-node commands target a graph node only
  when that graph node's own focus node is focused.
- Provide explicit one-shot leader commands under a focus namespace:
  - `Space f i` / `focus.into`
  - `Space f o` / `focus.out`
  - `Space f n` / `focus.next`
  - `Space f p` / `focus.previous`
  - `Space f h/j/k/l` / directional focus aliases
- Keep existing direct shortcuts: `Tab`, `Shift+Tab`, and direct directional
  focus where already wired remain available.
- Focus entry should prefer the last focused descendant in the entry scope when
  available; otherwise it should choose the first traversable focus node in that
  scope.
- Focus exit should return to the nearest owning/exit node for the current
  focus branch.
- Parent-level traversal should not accidentally enter a child entry scope. A
  user enters that scope through `focus.into`; once inside, next/previous and
  directional traversal operate at that interior level until `focus.out` returns
  to the owner node.

## Non-Goals

- Do not add a persistent focus mode. `Space f ...` is a one-shot leader
  namespace.
- Do not overload plain `Enter`; activation remains distinct from entering a
  focus hierarchy.
- Do not make focus nodes parent other focus nodes directly. Scopes remain the
  tree structure; entry/exit relationships are explicit links across that tree.
- Do not move graph topology or domain ownership into focus or graph view code.

## Design

### Focus hierarchy model

The generic model is an optional relationship between a normal focus node and a
normal focus scope:

```text
focus node --enter-scope--> focus scope
focus scope --exit-node--> focus node
```

"Shell" is only descriptive language for a node being used as a container entry
point in some context. It is not a new node kind. A focus node with no entry
scope behaves as a leaf. A focus node with an entry scope can be entered by an
explicit command. That same focus node may live inside another scope and may be
entered/exited as part of deeper nesting.

Scopes should remember their last focused descendant when focus leaves the
scope. Existing `focused-child` state helps track the live branch, but entry
needs a stable remembered target so re-entering a preview or dialog can restore
the user's previous interior position.

Entry scopes are traversal boundaries for their parent level. From outside an
entry scope, flat and directional traversal should see the owner node, not the
entry scope's interior descendants. After `focus-into`, traversal should use the
entered scope as the active traversal level so `Tab`, previous, and directional
movement cycle among interior descendants rather than leaking immediately back
to graph nodes or other outer siblings. `focus-out` restores traversal to the
scope containing the owner node.

### Focus manager commands

The focus manager should expose semantic operations:

- `focus-into`: requires a currently focused node with an enter scope. It moves
  focus to the remembered traversable descendant in that scope, or the first
  traversable descendant if there is no valid remembered target.
- `focus-out`: climbs from the currently focused node through ancestor scopes
  until it finds a scope with an exit node, then focuses that exit node.
- `focus-next` with `{:backwards? true}` remains the primitive for previous
  traversal, but it should honor the current active traversal level.
- `focus-direction` remains the primitive for directional traversal and should
  honor the same active traversal level.

The focus manager should fail loudly on inconsistent relationships during setup
or invocation where appropriate: entry scopes must belong to the same manager,
exit nodes must belong to the same manager, and unavailable commands should be
reported as unavailable rather than silently no-oping in command availability
checks.

The manager also needs a clear way to resolve the active traversal level from
the current focus branch. The implementation may store explicit entered-scope
state or derive it from ancestor entry scopes, but parent traversal must not
collect descendants of unopened entry scopes.

### Leader command namespace

Add a command provider for generic focus actions under the existing leader
system:

```text
Space f i    focus into
Space f o    focus out
Space f n    next focus
Space f p    previous focus
Space f h    focus left
Space f j    focus down
Space f k    focus up
Space f l    focus right
```

The command labels should be concise (`into`, `out`, `next`, `prev`, `left`,
`down`, `up`, `right`) and grouped under a `focus` prefix. Availability should
hide `into` when the focused node has no usable entry scope and hide `out` when
there is no enclosing exit node. Direction commands should follow the same text
input guard used by direct directional focus handling.

### Graph preview integration

Graph view should create per-node focus structure for expanded preview cards:

```text
graph-node-points scope
  graph-node-<key> scope
    graph-node-<key> focus node
    graph-node-<key>-preview scope
      preview child focus nodes...
```

The graph node focus node remains the graph-node action target and remains in
`node-by-focus`, so `focused-node` is set only when that node itself is focused.
The preview child scope is entered explicitly by `focus.into`; when preview
children are focused, graph-node commands should not pretend the graph node
shell is focused.

When building an expanded card preview, graph view should temporarily set the
build context focus scope to that node's preview scope and restore the previous
scope afterward. Child widgets then attach naturally to the preview scope using
existing widget focus patterns. Collapsing or replacing a presentation must drop
or detach the preview focus subtree cleanly so stale descendants cannot remain
focused.

Graph node focus bounds remain attached to the current compact point or expanded
card presentation. Preview child widgets own their own focus bounds as usual.

## Testing

Focused tests should cover:

- Generic focus manager `focus-into` enters a node's entry scope and chooses the
  first traversable child when there is no remembered child.
- Re-entering a scope restores the last focused descendant when that descendant
  is still attached and traversable.
- `focus-out` returns from a nested child to the nearest owning exit node.
- Arbitrary nesting works: a node can be inside one scope and enter another.
- Leader command hints expose the `focus` prefix and the expected one-shot
  bindings with availability tied to current focus state.
- Graph expanded previews attach child widget focus nodes to the node-specific
  preview scope.
- Graph-node commands are available when the graph node focus node is focused
  and not merely because one of its preview children is focused.

Validation should follow the Space Fennel ladder: project-native Fennel compile
check, constraints, focused focus/commands/graph-view tests, and broader tests
only if implementation scope warrants them.
