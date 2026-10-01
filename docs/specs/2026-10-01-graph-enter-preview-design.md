# Graph Enter Preview Activation Design

## Context

Graph view currently has two activation paths for a graph node:

- A compact node point handles double-click by expanding into an inline preview card.
- Keyboard Enter on the focused graph node activates the node focus target and opens the full node view.

The context menu already exposes both actions. The desired behavior is for Enter to match the quick-preview intent of double-click, leaving full view opening as an explicit menu or card-header action.

The visible compact point is replaced when a node is expanded, but GraphView also maintains a stable focus node for each graph node. That focus node attaches its bounds dynamically from `registry.points[node]`, so after expansion the same graph-node focus target can refer to the card presentation rather than the original point.

## Requirements

- Pressing Enter on a focused compact graph node expands its inline preview card.
- Pressing Enter when the node is already represented by an expanded preview card is idempotent: it leaves the card expanded and does not collapse it.
- Pressing Enter must not open the full node view.
- Full node view opening remains available through explicit context-menu and expanded-card header actions.
- Existing Alt+Enter and Alt+double-click linked-frontier behavior remains unchanged.
- The change stays in the graph view/presentation interaction layer; graph core and domain node persistence do not own this behavior.

## Approach Options

1. **Change Enter to reuse the existing presentation toggle.** This is small, but it would make repeated Enter collapse the card, which is not how focus should behave once the compact point has been replaced.
2. **Special-case the Enter key in normal input handling.** This would avoid changing GraphView focus activation, but it would bypass the existing focus manager path and duplicate graph-specific behavior in generic input code.
3. **Add an idempotent GraphView preview-expand path and route graph-node focus activation through it.** This keeps graph interaction behavior inside GraphView, preserves generic focus activation, and cleanly separates preview expansion from explicit full-view opening.

The recommended approach is option 3.

## Design

GraphView should expose or internally use an idempotent `expand node inline` helper. The helper checks the current presentation for the graph node. If the node is already expanded, it returns successfully without replacing the card. If the node is compact, it reuses the existing expansion mechanics that build the preview card, update presentation registration, pin state, labels, persistence, and layout.

The non-Alt branch of graph-node focus activation should call this helper rather than `views:open node`. The Alt branch should continue to perform linked-frontier expansion. Any graph activity fallback that currently invokes full opening for the focused graph node should also route to the new preview-expansion path so Enter behavior is consistent whether activation comes through the focus manager or the activity hook.

Context-menu `Open` and expanded-card header open actions should continue to call the full view opener. This preserves an explicit route to the full view while making default keyboard activation lightweight and spatially local.

## Testing

Focused tests should cover:

- Enter/focus activation on a compact graph node expands the inline preview and does not call the full view builder/opener.
- A second Enter while already expanded is a no-op: the card stays expanded and is not collapsed.
- The same graph-node focus association survives compact-to-card replacement.
- The explicit header/context full-open path remains available.
- Alt+Enter linked-frontier behavior remains unchanged.

Validation should follow the Space Fennel ladder: project-native Fennel compile check, constraints, then focused graph view/activity tests.
