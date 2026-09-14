# VirtualInput Shared Input Policies Design

## Problem

`Input`/`InputModel` are the accepted text-widget behavior oracle. `VirtualInput`
exists to keep file-backed and huge-buffer editing lazy, but it still reimplements
too much `Input` behavior: focus lifecycle, caret visibility, caret mode styling,
click geometry, direct key handling, and cursor/scroll projection. That duplication
has repeatedly produced user-visible divergence.

The goal is not to patch another isolated symptom. `VirtualInput` should reuse the
same interaction and caret policies as `Input` wherever the policy is independent
of storage size. Lazy file storage and bounded viewport materialization remain
VirtualInput-specific.

## Design Direction

Use small shared policy modules extracted from the working eager `Input` behavior.
`Input` continues to use `InputModel` for materialized text. `VirtualInput`
continues to use `LazyTextBuffer`, byte anchors, viewport rows, clipping, and
bounded movement APIs. Both widgets call shared policies for behavior that should
not depend on storage backend.

Do not wrap a huge file in eager `InputModel`, and do not continue expanding
bespoke `VirtualInput` copies of `Input` logic.

## Shared Policies

### Focus lifecycle

Create a shared focus policy for request/focus/blur/disconnect behavior:

- focused widgets set `focused?` consistently;
- focus connects the active input and enters text mode through the existing input
  state router;
- blur/disconnect releases active input, normalizes the widget to normal mode,
  updates focus visuals, and hides the caret;
- `Input` and `VirtualInput` use the same lifecycle entry points.

`VirtualInput` must stop showing the caret merely because a visible row contains
the cursor. Caret visibility is focus-gated like `Input`.

### Caret policy

Create a shared caret policy for mode-dependent caret decisions:

- normal mode uses `colors.caret-normal` and a glyph/block-width caret;
- insert mode uses `colors.caret-insert` and the configured thin caret width;
- caret height is bounded to the line/inner height using the eager `Input` rule;
- missing required style/font data fails explicitly rather than silently falling
  back in new code.

Geometry inputs remain widget-specific: eager `Input` computes x/y from its
materialized text and wrapping model; `VirtualInput` computes x/y from lazy
viewport rows and bounded anchors. The color/visibility/width policy is shared.

### Key handling and mode gating

Normal-mode commands stay routed through `text-normal-commands` and
`text-editing-port`. Insert-mode editing stays routed through `InsertState` and
the active input methods.

`VirtualInput:on-key-down` must not perform editing or navigation in normal mode
through private branches that bypass the shared command engine or mode checks.
Direct widget key handling should be limited to shared extra shortcuts that eager
and virtual widgets intentionally support, such as save/copy/page movement where
those are already part of the active-input contract.

### Geometry policy

Create shared geometry helpers for storage-neutral coordinate math:

- local point extraction from pointer events;
- row index from local y using the project top-to-bottom convention;
- column index from local x and column width;
- visible row y offset.

`VirtualInput` uses those helpers for row layout, caret y, and click hit testing.
The byte-resolution step from row/column to lazy buffer offset remains
VirtualInput-specific.

## Storage-Specific Boundaries

The following stay outside shared policies:

- eager `InputModel` storage and full codepoint arrays;
- `LazyTextBuffer` file-backed pieces, byte offsets, anchors, and bounded scans;
- `VirtualInput` per-row rendering, viewport clipping, and anchor caches;
- virtual-only selection/save behavior unless a later design gives eager `Input`
  equivalent semantics;
- file conflict and save-token behavior;
- new editor features or keybindings.

## Tests

Parity tests must use the eager widget as oracle and file-backed lazy fixtures for
`VirtualInput`. Fixtures can be small in developer readability, but must force
lazy-specific behavior using tiny chunks, narrow viewports, long lines, or files
large enough to require bounded viewport/anchor logic.

Required coverage:

- initial unfocused caret hidden for both widgets;
- focus/click enters text mode, sets `focused?`, and shows the caret;
- blur/disconnect hides caret, clears active input, and normalizes mode;
- normal and insert caret width/color match eager `Input`;
- direct normal-mode `VirtualInput:on-key-down` does not edit text or bypass the
  shared normal command engine;
- state-routed normal and insert commands still edit/navigate through the shared
  port/state path;
- lazy large-file click/caret/scroll sequences remain bounded and match eager
  cursor/mode expectations where eager materialization is safe for the fixture;
- E2E pointer routing covers real screen coordinates for an expanded file viewer.

## Acceptance Criteria

- `VirtualInput` reuses shared focus, caret, key, and geometry policies rather
  than maintaining independent copies of those rules.
- `Input` behavior does not regress; it remains the compatibility oracle.
- `VirtualInput` never materializes huge files to gain parity.
- The test suite contains file-backed lazy parity tests that would fail if
  `VirtualInput` reintroduces private caret/focus/key/geometry behavior.
- No status-line fix is made unless a deterministic app-state/input-mode desync
  is reproduced; otherwise status consistency is covered through state/mode
  parity tests.

## Validation

Validation follows Space Fennel order:

1. `make build` when the runtime may be stale.
2. Touched-file or broad `make fennel-check`.
3. `make constraints`.
4. Focused input/virtual-input/file-viewer tests.
5. `make test` for central state/input behavior.
6. `make test-e2e` for real pointer/rendering behavior before integration.
