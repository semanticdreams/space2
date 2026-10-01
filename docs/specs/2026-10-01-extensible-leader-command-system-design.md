# Extensible Leader Command System Design

## Context

Space currently has a Vim/Spacemacs-inspired modal interaction model, but the leader state is still a small fixed set of one-key commands. Graph view now supports keyboard Enter to expand a focused node preview, and the next need is keyboard-driven collapse/expand commands that operate on selected graph nodes instead of whichever preview child widget currently has focus.

Space will need many more active key bindings over time. Bindings may depend on the active activity, active graph view, current selection, focused graph node, focused widget, or other contextual state. The system should make those bindings easy to add, discover, and remap without scattering conditional key logic across state handlers.

## Requirements

- Support nested Spacemacs-style leader sequences such as `SPC g p e`.
- Keep command availability contextual: graph commands are available only when a graph command provider is active, and graph preview commands are available only when selected graph nodes exist.
- Preview commands operate on selected graph nodes only. They must not fall back to focused, hovered, or child-widget focus targets.
- Commands should be reusable outside graph activity. If another context embeds a graph view later, that context should be able to contribute the same graph command provider with a different graph-view resolver.
- Key bindings should be remappable by changing declarative keymap data, not by rewriting command execution functions.
- Command hints should be derived from the active command/keymap data so hints and actual bindings do not drift.
- Do not introduce a mandatory generic “target scope” abstraction for all commands. Use namespace conventions and command-local availability/resolution logic instead.
- Preserve existing leader behavior: `SPC q`, `SPC c`, and `SPC p` continue to work.
- Preserve existing normal-mode behavior: `Enter`, `Delete`, F4, and activity input dispatch remain separate from leader command dispatch.

## Approach Options

### Option 1: Add graph-specific leader conditionals directly to `leader-state.fnl`

`leader-state.fnl` could manually track sequences like `g p c` and call graph functions directly.

Pros: smallest immediate change.

Cons: does not scale, makes graph activity special in a global state, makes remapping hard, and duplicates command-hint metadata.

### Option 2: Extend activity input handlers to implement leader sequences per activity

Each activity could receive leader key events and implement its own nested commands.

Pros: activity-local and avoids global graph conditionals.

Cons: every activity would reinvent prefix tracking, hints, availability, remapping, and conflict behavior.

### Option 3: Add a reusable command/keymap layer with contextual providers

Create a small command subsystem. Command providers contribute command descriptors and keymap entries when their context is active. Leader state resolves key sequences through the composed active keymap, executes available commands, and derives prefix/command hints from the same data.

Pros: modular, remappable, reusable for graph views outside graph activity, and scales to future activity/widget/focus providers.

Cons: more initial design work than a direct graph-specific handler.

The recommended approach is option 3.

## Design

### Command descriptors

A command descriptor is a plain table with:

- `:id` — stable command id such as `graph.preview.expand-selected`.
- `:label` — human-readable hint label.
- `:run` — function receiving a command context and returning truthy when handled.
- `:available?` — optional predicate receiving the same context. When false, the command is not executable or shown as an available command hint.

The descriptor does not need a universal target field. Each command owns its own resolution rules. For example, graph preview commands ask their graph view for selected nodes and reject empty selections.

### Keymaps

Keymaps are declarative tables mapping key sequences to command ids or prefixes. The default leader keymap keeps existing bindings and adds graph namespaces:

```text
SPC q       quit mode
SPC c       camera mode
SPC p       launcher
SPC g p e   graph.preview.expand-selected
SPC g p c   graph.preview.collapse-selected
SPC g p t   graph.preview.toggle-selected
```

The graph namespace convention reserves room for future work:

```text
SPC g p ...   graph preview / presentation
SPC g s ...   graph selection editing
SPC g n ...   focused graph node actions
SPC g v ...   graph view, camera, and layout
SPC g m ...   graph map and topology
```

These are conventions, not hard-coded target-scope mechanics.

### Command providers

A provider contributes commands and keymap fragments for the current context. Initial providers should include:

- Core leader commands for existing global leader actions.
- Graph command provider factory that accepts a `graph-view` resolver.

Graph activity installs a graph provider by passing a resolver for its active graph view. If a future panel or activity embeds a graph view outside graph activity, it can install the same provider with its own resolver.

Provider composition should be explicit and ordered. For the first slice, global/core provider plus active activity providers are enough. Future providers can be added for focused widgets or focused graph nodes without changing leader dispatch itself.

### Leader sequence resolution

Leader state should hold the current prefix sequence after `SPC`. On each key:

1. Append the key to the current sequence.
2. Resolve against the composed active keymap.
3. If the sequence is a prefix, remain in leader state and show prefix-specific hints.
4. If the sequence resolves to an available command, execute it, mark command executed, and return to normal state.
5. If the sequence resolves to an unavailable command, show a clear status/no-op result and return to normal state.
6. If the sequence is unknown, return to normal state without running a command.
7. `Esc` always cancels leader state and returns to normal.

The first implementation can use single-key events only; it does not need text input, chords, or timeout behavior.

### Command hints

Command hints should be generated from the same active command descriptors and keymap entries that leader dispatch uses. In normal mode, hints can show `space leader`. In leader mode, hints show available commands for the current prefix, including graph prefixes only when a graph provider is active. Prefix hints should help discover `g`, `g p`, and final commands.

For graph preview commands, hints appear only when the graph provider is active and selected graph nodes exist. That keeps the UX predictable: if no selection exists, the preview commands are not advertised as actionable.

### Graph preview commands

Graph view should expose selection-based preview presentation methods:

- Expand selected previews.
- Collapse selected previews.
- Toggle selected previews.

These methods operate only on selected graph nodes. Empty selection returns false and performs no fallback. Full node view opening remains an explicit context-menu/header/focused-node command and is not part of preview collapse behavior.

## Testing

Focused tests should cover:

- Nested leader resolution for existing one-key leader commands.
- Prefix resolution and hints for `SPC g` and `SPC g p` when graph provider is active.
- Graph preview commands are unavailable/no-op when no graph selection exists.
- `SPC g p e` expands selected compact graph nodes.
- `SPC g p c` collapses selected expanded graph nodes.
- `SPC g p t` toggles selected graph node presentations.
- Preview commands do not act on focused or hovered nodes when selection is empty.
- Graph command provider can be constructed with an arbitrary graph-view resolver so it is reusable outside graph activity.

Validation should follow the Space Fennel ladder: touched-file compile check, constraints, focused command/leader/graph tests, then broader validation as risk requires.
