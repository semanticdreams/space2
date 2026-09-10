# Lazy Text Buffer and Virtual Input

## Use cases

The lazy editor stack supports file-scale text viewing and editing without loading the whole file into a Fennel string, an `InputModel`, or a single `Text` widget. Use it for graph filesystem file viewer nodes and other features that must open large source, log, or plain-text files while keeping reads and rendered widgets bounded to the active viewport.

This stack is intentionally plain text only in this iteration. `VirtualInput` provides a bounded `TextState`/`InsertState` compatibility facade for the file viewer, but the lazy editor stack does not provide full modal-editor features such as syntax highlighting, undo/redo history, multi-cursor behavior, whole-file search/replace, binary editing, or collaborative editing.

## File source and save primitives

`LazyTextSource.file(path, opts)` normalizes the path, captures a filesystem token with `fs.file-token`, and exposes bounded reads through `fs.read-byte-range`. The source keeps the baseline token that represents the file version the buffer was opened from and can refresh that baseline after a successful save.

Native filesystem saves use `fs.atomic-replace-if-current(path, segments, expected-token)`. Segment tables may reference unchanged byte ranges from the original source file or provide inserted text. The native primitive validates that the current file still matches `expected-token`, writes the composed content to a temporary replacement, applies temp-file setup such as permissions, revalidates the token immediately before `rename`, and reports a conflict instead of replacing a known changed file.

## Piece table buffer

`LazyTextBuffer {:source source}` represents the document as a piece table. Original pieces reference byte ranges in the file source, while inserted text is appended to an add buffer. Insert and delete operations rewrite piece metadata and leave unchanged file content on disk instead of copying the complete file into memory.

The buffer tracks byte-position caret state, optional selection ranges, dirty state, and the current scroll line. Editing methods fail loudly for unsupported or invalid input, including invalid UTF-8 inserted text.

## Sparse line index

Line navigation is backed by sparse byte anchors. The buffer starts with a line-zero anchor and discovers additional line starts only as viewport, caret, or navigation requests require them. This keeps indexing work proportional to the explored region rather than requiring an eager scan of the entire file.

When edits change document structure, line anchors reset to the beginning so later navigation rebuilds the sparse index against the current piece table.

## Viewport snapshots

`buffer:get-viewport {:line line :column column :lines lines :columns columns}` returns a bounded snapshot containing only requested rows and visible columns. Rows include text/codepoints for display plus byte offsets needed for caret movement and selection. `VirtualInput` records those row anchors as byte, line, and logical column tuples so later caret and viewport work can resume from a known nearby position.

Viewport construction reads composed ranges in bounded chunks and marks long rows as partial when the row exceeds the scan budget. Anchor-relative refresh may rebuild each visible row with `buffer:build-viewport-row-from-anchor(anchor, columns)` when cached row anchors exist for the current `scroll-line`/`scroll-column`. Far horizontal viewport refresh must use a cached row anchor for the requested logical column or explicitly report that bounded refresh is unavailable; the editor must not fall back to whole-file reads when lazy indexing or row discovery is incomplete.

## VirtualInput widget

`VirtualInput` is the file-scale text widget. It renders a bounded set of visible rows by feeding each visible row's codepoints to child `Text` widgets, routes keyboard editing to `LazyTextBuffer`, tracks viewport scroll, handles selection/copy, and exposes save handling for buffers that support saving.

`VirtualInput` exposes a deliberately small `Input`-compatible facade for the existing `TextState` and `InsertState` modal routes. The facade supports Vim-style `i`, `h`, `j`, `k`, `l`, and `x` in text mode, Escape and Return handling in insert mode, multiline insertion for Return, and Ctrl+S routing for file-viewer saves. File-scale editors should rely on this bounded facade instead of converting the document into an `InputModel`.

`VirtualInput` owns the authoritative cached logical cursor tuple: `cursor-index` (byte offset), `cursor-line`, and `cursor-column`. It mirrors that tuple to the compatibility model after updates, but ordinary file-scale navigation should treat the widget cache as the source of truth. Ordinary `h`, `l`, `j`, and `k` navigation uses the cached cursor and viewport anchors to call bounded `LazyTextBuffer` movement APIs such as adjacent-codepoint and line/column-from-anchor movement. Exact commands that intentionally need document-wide knowledge, including `$`, `A`, and `G`, may still use exact scan paths, but they must update the cached cursor tuple and viewport anchors afterward before returning to ordinary navigation.

The configured `:line-count` and `:column-count` are preferred maximum viewport dimensions. The allocated layout size determines the current visible row/column counts, so containers can shrink a file viewer without forcing the widget to render or request more lazy-buffer data than fits. All rendered children — background, row text, and caret — receive a `VirtualInput`-local clip region intersected with any parent clip bounds so narrow allocations clip consistently.

Horizontal caret movement updates `scroll-column` to keep the caret visible inside the allocated input bounds. This visibility invariant is maintained through lazy viewport requests and caret-row discovery, not by eagerly reading or indexing the whole file.

`VirtualInput` builders require an explicit build context and a lazy buffer. It must be used for file-scale text because it virtualizes both data access and child rendering; no new large-file path should pass a whole file or whole composed document to `Text` or `Input`.

## Save and conflict behavior

Saves follow a pragmatic Neovim/Vim-style save-safety contract: they do not blindly overwrite known stale external changes, and detected conflicts preserve the user's in-memory edits. Before the graph file viewer saves, it compares the current file token with the buffer source baseline token and reports a conflict if the file changed externally. The buffer save itself delegates to `atomic-replace-if-current`, which repeats the token check at the native filesystem boundary after composing the replacement and immediately before replacing the file.

This is not a strict race-free compare-and-replace guarantee for arbitrary non-cooperating writers. POSIX/Linux path replacement cannot prevent another process from changing the target in the tiny gap between final validation and `rename`; callers should describe this as normal stale-change detection, not mathematical CAS semantics.

On successful save, the buffer refreshes its baseline token, collapses pieces back to a single original-file piece, clears the add buffer, and marks itself clean. On conflict or error, the buffer remains dirty so the caller can report the problem and preserve the user's in-memory edits.

## Compatibility with Input/InputModel

`Input` and `InputModel` remain the correct widgets for small in-memory controls such as labels, prompts, forms, and compact text fields. They keep their existing whole-buffer codepoint behavior and compatibility tests.

`VirtualInput` is required for file-scale text. Existing whole-buffer input controls must not be repurposed for large files, and the lazy stack exists beside them rather than replacing their small-control responsibilities.

## Testing expectations

Validation for this stack should cover the full ladder because it spans native filesystem primitives, lazy Fennel buffers, UI input behavior, and graph file interactions:

- `make build` after native binding or runtime changes.
- `make fennel-check` before constraints and Fennel tests.
- `make constraints` as the structural gate.
- Focused lazy-anchor navigation checks for `tests.test-lazy-text-buffer`, `tests.test-virtual-input`, `tests.test-input`, and `tests.test-input-model` whenever bounded buffer APIs or `TextState`/`VirtualInput` routing changes.
- Focused file-source and graph integration checks for `tests.test-fs` and `tests.test-fs-file-viewer` when save/source behavior changes.
- File-viewer E2E coverage when file-viewer routing changes, especially for far-line and far-horizontal caret movement through the graph file viewer.
- The standard full `make test` command with keyring skipped, audio disabled, and `SPACE_ASSETS_PATH` set to the absolute assets directory.

Regression tests should prove bounded reads, piece-table editing, viewport-only rendering, save success, conflict detection with `file changed` errors, graph viewer integration, and continued `Input`/`InputModel` compatibility.
