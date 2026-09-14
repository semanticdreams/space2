# Shared Text Interaction Engine Design

## Purpose

Space is going to grow from a small set of modal text commands into a much larger Vim/Neovim-like editing surface: word motions, operators, selections, selected-text transformations, search, marks, repeat, text objects, and commands beyond traditional Vim. The current split between `Input` and `VirtualInput` is not safe enough for that future because storage-specific implementation details can leak into interaction behavior and cause divergence.

This design creates an explicit shared text interaction layer so new commands are implemented once and run against both eager `Input` and lazy file-scale `VirtualInput` through storage-specific adapters.

## Compatibility Principle

The existing `Input` widget and `InputModel` behavior are the compatibility oracle for current commands because they are older, have been tested for a longer period, and have been accepted in real use. `VirtualInput` is newer and may still contain bugs despite recent lazy-anchor fixes. When `Input` and `VirtualInput` disagree, the default assumption is that `VirtualInput` should be corrected to match `Input`, unless a file-scale difference is explicitly documented in this spec or developer docs.

This does not mean `VirtualInput` should reuse eager storage internals. It means user-facing command semantics should be shared and storage-specific performance work should live behind a protocol.

## Current Architecture Summary

- `assets/lua/input-model.fnl` owns eager in-memory text storage, line/codepoint derived state, cursor position, selection, scroll state, insert/delete operations, and simple caret movement.
- `assets/lua/input.fnl` wraps `InputModel` as a widget, handles layout/caret rendering/focus, and delegates text operations to the model.
- `assets/lua/lazy-text-buffer.fnl` owns file-scale byte/piece-table storage and lazy anchor-relative movement/rendering APIs.
- `assets/lua/virtual-input.fnl` wraps `LazyTextBuffer` as a widget, owns lazy cursor/viewport anchor caches, and currently mirrors enough model-like shape for existing state code.
- `assets/lua/text-state.fnl` owns much of normal-mode command behavior today, but also contains backend-specific branching for logical or bounded navigation.
- `assets/lua/insert-state.fnl` owns insert-mode key handling and currently routes basic editing keys through active inputs.
- `assets/lua/input-state-router.fnl` tracks the active input and dispatches events; it should not own editing semantics.

## Chosen Approach

Use a **shared command engine over an explicit text-editing port**.

The command engine owns user-facing text interaction semantics. The port owns storage-specific primitives. `Input`/`InputModel` can satisfy the port using eager codepoint/line state. `VirtualInput`/`LazyTextBuffer` can satisfy the same port using lazy byte anchors, cached logical cursor state, and bounded movement APIs.

### Alternatives Considered

1. **Shared command engine + text-editing port — chosen.**
   - Pros: one implementation of command semantics, storage-specific performance remains isolated, future commands have a clear home, parity tests can run across backends.
   - Cons: requires introducing a protocol and migrating existing `TextState` helpers carefully.

2. **Force `InputModel` and `LazyTextBuffer` into one storage API.**
   - Pros: fewer adapter concepts in theory.
   - Cons: eager codepoint storage and lazy byte/piece storage have fundamentally different performance constraints; forcing them together risks either loading whole files or overcomplicating small inputs.

3. **Keep separate behavior implementations with parity tests.**
   - Pros: lowest immediate refactor cost.
   - Cons: accepts ongoing divergence risk; every future Vim-like command would need duplicate implementation discipline.

## Components

### `text-editing-port.fnl`

New module. Converts an active input into a backend-neutral port.

Responsibilities:
- Detect the input backend shape privately.
- Expose required movement, query, mode, edit, and selection primitives through one interface.
- Preserve eager `Input` behavior as the default semantic oracle.
- Isolate `VirtualInput` lazy/bounded details behind port methods.
- Error clearly when a required method is missing; do not silently no-op.

Initial port surface:
- `line-count() -> integer`
- `line-length(line) -> integer`
- `line-first-nonblank(line) -> integer`
- `cursor-line-column() -> line, column`
- `move-to-line-column(line, column, opts) -> boolean`
- `move-horizontal(delta, opts) -> boolean`
- `move-vertical(delta, opts) -> boolean`
- `move-to-line-edge(edge, opts) -> boolean`, where `edge` is `:start` or `:end`
- `move-to-first-nonblank(opts) -> boolean`
- `move-to-first-line(opts) -> boolean`
- `move-to-last-line(opts) -> boolean`
- `clamp-caret-to-current-line(opts) -> boolean`
- `insert-text(text, opts) -> any`
- `delete-at-cursor(opts) -> boolean`
- `enter-insert-mode(opts) -> any`
- `enter-normal-mode(opts) -> any`
- `submit(payload) -> any`
- `move-next-word-start(opts) -> boolean`

The port may expose additional explicit capability metadata later, but command code should prefer required methods over direct backend inspection.

### `text-normal-commands.fnl`

New module. Owns normal-mode command definitions, key resolution, prefix handling, and command hint entries.

Responsibilities:
- Implement normal-mode commands against `text-editing-port` only.
- Keep command names, hint labels, key bindings, and mode transitions centralized.
- Avoid direct access to `input.model`, `input.lines`, `VirtualInput` anchor caches, or `LazyTextBuffer` internals.
- Preserve current behavior for existing commands.

`TextState` should become a routing shell that tracks active input, control-key handling, F1 hints, command prefixes, submit behavior, and mode synchronization. It should delegate normal-mode command execution to `text-normal-commands`.

### Existing Widgets and Storage

`Input` and `InputModel` remain eager and should not be rewritten around `LazyTextBuffer`.

`VirtualInput` and `LazyTextBuffer` remain lazy and must not materialize whole files, huge lines, or large prefixes to satisfy ordinary commands. Their storage-specific work belongs in port methods and lazy buffer APIs, not command handlers.

`InsertState` is not the primary migration target for the first pass. It may be adjusted only where needed to preserve behavior through the new port boundary.

## Proving Case: Lowercase `w`

The first implementation should include one new command: lowercase normal-mode `w`.

Why `w`:
- It is a real Vim-style motion, not a trivial alias.
- It exercises command semantics, storage traversal, cursor updates, and backend parity.
- It is useful groundwork for future operators like `dw` and text-object behavior.
- It can be scoped tightly enough to avoid implementing counts, operator-pending state, visual mode, or full Vim keyword configuration immediately.

Initial `w` semantics:
- No counts.
- No operators.
- No visual-mode behavior.
- Forward only.
- Move to the first codepoint of the next word run.
- Whitespace codepoints: `9`, `10`, `11`, `12`, `13`, and `32`.
- Keyword codepoints: ASCII `A-Z`, `a-z`, `0-9`, and `_`.
- Punctuation: any other non-whitespace codepoint.
- From a non-whitespace run, skip the current run, then skip whitespace, then land on the next non-whitespace run.
- From whitespace, skip whitespace and land on the next non-whitespace run.
- If no next word exists, do not move.
- For `VirtualInput`, scanning must be streaming and lazy: it may read successive chunks until it finds the next word or EOF, but it must not build a whole-file string, whole-line string, eager `InputModel`, or accumulated prefix string.

## Data Flow

Normal-mode key input should flow as:

1. `InputStateRouter` provides the active input.
2. `TextState` receives the key event and handles state-level concerns such as F1, submit shortcuts, control fallback, and command prefixes.
3. `TextState` passes normal-mode command keys to `text-normal-commands`.
4. `text-normal-commands` creates or receives a `text-editing-port` for the active input.
5. Command handlers call port methods only.
6. The port delegates to eager `Input`/`InputModel` or lazy `VirtualInput`/`LazyTextBuffer` primitives.
7. Widgets update rendering, focus, caret, selection, and dirty state through their existing backend-specific mechanisms.

## Error Handling

- Missing required port operations must raise explicit errors naming the missing operation and input kind.
- Unsupported bounded lazy movement must return explicit false/unbounded results at the port/backend boundary, not a silent successful no-op.
- Command handlers may treat a false movement result as “not handled movement” only when that matches existing `Input` behavior.
- New commands must document whether they require exact scans, bounded scans, or both.

## Testing Strategy

- Add `tests.test-text-editing-port` to exercise the port against eager and virtual-style inputs.
- Preserve existing `Input`/`InputModel` tests as the compatibility oracle.
- Add parity tests that run the same command scenarios against `Input` and `VirtualInput` where feasible.
- Keep lazy performance tests for `VirtualInput` and `LazyTextBuffer`; command parity is not enough if the lazy backend materializes whole files.
- Add proving-case tests for `w` against both eager and lazy backends: within a word, from whitespace, over punctuation, across newline, and at EOF/no next word.
- Run Space-native validation only: `make fennel-check`, `make constraints`, focused Fennel tests, and broader `make test` when central command routing changes.

## Out of Scope for First Pass

- Counts such as `3w`.
- Operators such as `dw`, `cw`, `d$`.
- Operator-pending mode.
- Visual mode or selected-text manipulation.
- Text objects.
- Repeat command `.`.
- Search.
- Marks and jumps.
- Unicode or configurable Vim `iskeyword` semantics.
- Replacing `InputModel` storage with `LazyTextBuffer`.
- Broad rewrite of `InsertState` beyond compatibility adjustments needed for the port.

## Acceptance Criteria

- Existing accepted `Input` behavior for current commands remains unchanged.
- Existing `VirtualInput` command behavior continues to match `Input` where the behavior is shared.
- `TextState` no longer contains backend-specific navigation branching for normal-mode commands.
- Normal-mode command implementations do not inspect eager or lazy storage internals directly.
- Lowercase `w` works through the shared command path for both `Input` and `VirtualInput`.
- `VirtualInput` `w` scans lazily without materializing whole files, huge lines, eager `InputModel` state, or accumulated prefixes.
- Developer docs explain the port, command engine, compatibility oracle, and initial `w` semantics.
