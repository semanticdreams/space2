# Text Input Policies

Shared text input policies keep eager `Input` widgets and file-backed
`VirtualInput` widgets aligned where behavior is independent of storage size.
Eager `Input` and `InputModel` are the behavioral oracle for accepted text
interaction, focus, caret, and command semantics. When shared behavior differs,
fix `VirtualInput` or the shared policy unless a lazy storage difference is
explicitly documented.

`VirtualInput` must not become eager to gain parity. It keeps file-backed
storage, viewport rows, byte anchors, bounded movement APIs, selection, save,
and per-row rendering in the lazy stack.

## Policy ownership

- `assets/lua/text-input-focus-policy.fnl` owns focus request, focus/blur,
  active-input connection, text-state entry, disconnect normalization, and
  focus-visual updates for Input-like widgets.
- `assets/lua/text-input-caret-policy.fnl` owns focus-gated caret visibility,
  normal/insert caret color, mode-dependent caret width, line-height and
  column-width resolution, and bounded caret height rules.
- `assets/lua/text-input-key-policy.fnl` owns direct widget shortcuts that are
  valid outside the normal-command engine, currently save, copy, and page
  scrolling. It must not grow private normal-mode edit or navigation handling.
- `assets/lua/text-input-geometry.fnl` owns storage-neutral pointer/local-point,
  row, column, row-y, and screen-point geometry math.
- `assets/lua/text-normal-commands.fnl` owns normal-mode command semantics.
  Commands call `assets/lua/text-editing-port.fnl`, which adapts eager
  `InputModel` and lazy `VirtualInput` operations without exposing storage
  internals to command code.

## Lazy boundaries

Shared policies do not own file-scale data access. `VirtualInput` and
`LazyTextBuffer` own the lazy boundaries:

- file-backed piece-table storage and save/conflict behavior;
- sparse line anchors, byte offsets, and viewport row anchors;
- bounded cursor movement and row/column-to-byte resolution;
- selection/copy state for the file-backed widget;
- viewport sizing, clipping, child `Text` row construction, and per-row
  rendering;
- exact scan paths for commands that intentionally require document-wide
  knowledge.

Future policy changes should pass storage-specific data into shared helpers
rather than materializing huge files into strings, eager `InputModel` instances,
or whole-line caches.

## Validation expectations

For future `VirtualInput` interaction changes, add or update file-backed lazy
parity tests. Fixtures should force lazy paths with tiny chunks, narrow
viewports, long rows, far horizontal scroll, or enough content to exercise
bounded anchor discovery. Tests may compare against eager `Input` for safe small
fixtures, but huge-file behavior must never be implemented or validated by
loading the whole file into eager storage.

Use project-native validation in this order for Fennel-facing behavior: compile
check, constraints, then focused input/virtual-input tests. Broader `make test`
or E2E validation is appropriate when command routing, file viewer pointer
routing, or central runtime behavior changes.
