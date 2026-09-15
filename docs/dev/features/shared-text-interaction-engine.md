# Shared Text Interaction Engine

The shared text interaction engine keeps modal text commands consistent across
small eager `Input` widgets and file-scale `VirtualInput` widgets. Normal-mode
commands live in `assets/lua/text-normal-commands.fnl` and run through the
backend-neutral port in `assets/lua/text-editing-port.fnl`; widget-specific
storage details stay behind that port.

## Compatibility oracle

Existing `Input` widget and `InputModel` behavior are the compatibility oracle
for shared commands, interaction lifecycle, and caret behavior. They are older,
more proven, and covered by accepted tests. When `Input` and `VirtualInput`
disagree on behavior that both support, assume `VirtualInput` or a shared policy
is the part to fix unless a file-scale difference is explicitly documented in the
spec or developer docs.

`VirtualInput` is newer and less proven. It must match shared `Input` semantics
without adopting eager `InputModel` storage, whole-buffer assumptions, or
whole-file materialization for huge-file behavior.

See [Text Input Policies](text-input-policies.md) for the focus, caret, direct
key, geometry, and lazy-storage boundaries shared by this engine.

## Shared input policies

The command engine is one part of the shared text input architecture. Storage-
neutral interaction rules live in small policy modules extracted from eager
`Input` behavior:

- `text-input-focus-policy.fnl` handles focus request, focus/blur, active input
  connection, text-state entry, disconnect normalization, and focus visuals.
- `text-input-caret-policy.fnl` handles focus-gated visibility, normal/insert
  color, mode width, line/column metrics, and caret height.
- `text-input-key-policy.fnl` handles only direct shortcuts that are valid
  outside normal commands, such as save, copy, and page scrolling.
- `text-input-geometry.fnl` handles storage-neutral pointer, row, column, and
  row-y/screen-point geometry.

Normal-mode text editing remains owned by `text-normal-commands.fnl` and routed
through `text-editing-port.fnl`; insert-mode edits route through `InsertState`
and the active input methods.

## Text-editing port

`text-editing-port.fnl` is the storage-aware adapter layer. It detects the
active input kind and exposes explicit operations for command code, including
cursor movement, line-edge movement, insert/delete primitives, normal/insert
mode sync, submit handling, and word motion.

Missing required port operations must fail loudly with errors that name both the
missing operation and the input kind. Command handlers should depend on required
port methods rather than probing widget internals or silently treating missing
behavior as success.

## Normal-mode command engine

`text-normal-commands.fnl` owns normal-mode key bindings, command hints, prefix
state, command execution, and shared command semantics. `TextState` should remain
a routing shell for the active input, submit shortcuts, command hints, mode sync,
control fallback, and lifecycle events.

Architecture invariant: `text-normal-commands.fnl` must not inspect
`input.model`, `input.lines`, `VirtualInput` anchor caches, or `LazyTextBuffer`
internals directly. Storage-specific behavior belongs in
`text-editing-port.fnl`, `virtual-input.fnl`, and `lazy-text-buffer.fnl`.

## Lowercase w word motion

Lowercase `w` is the proving command for the shared engine. It is implemented
once as a normal-mode command and calls the port's next-word-start operation for
both eager and lazy backends.

Current limits:

- No counts such as `3w`.
- No operators such as `dw` or `cw`.
- No visual-mode behavior.
- Forward only.

Codepoint classes:

- Whitespace codepoints: `9`, `10`, `11`, `12`, `13`, and `32`.
- Keyword codepoints: ASCII `A-Z`, `a-z`, `0-9`, and `_`.
- Punctuation: any other non-whitespace codepoint.

Movement rules:

- From a non-whitespace run, skip the current run, then skip whitespace, then
  land on the next non-whitespace run.
- From whitespace, skip whitespace and land on the next non-whitespace run.
- If no next word exists, do not move.

## Lazy backend invariants

`VirtualInput` and `LazyTextBuffer` must preserve file-scale laziness while
participating in the shared engine. Lowercase `w` for `VirtualInput` may stream
chunks until the next word or EOF, but it must not build a whole-file string,
whole-line string, eager `InputModel`, or accumulated prefix string.

Lazy movement should use `VirtualInput` cursor/viewport anchors and
`LazyTextBuffer` streaming or bounded movement primitives. Exact file-scale
differences must be documented; otherwise shared behavior should follow the
`Input` compatibility oracle.

## Testing expectations

For changes to this engine, validate the full command-routing surface:

- Run `make fennel-check` before constraints and tests.
- Run `make constraints` as the structural gate.
- Run focused tests for `tests.test-text-editing-port`,
  `tests.test-text-normal-commands`, `tests.test-states`, `tests.test-input`,
  `tests.test-input-model`, `tests.test-lazy-text-buffer`, and
  `tests.test-virtual-input`.
- Run the broad `make test` suite when central command routing changes.

Regression coverage should prove that existing `Input` behavior still passes,
`VirtualInput` matches shared `Input` behavior where shared, lowercase `w` works
for both eager and lazy inputs, and lazy word motion does not materialize whole
files, whole lines, eager models, or accumulated prefixes.
