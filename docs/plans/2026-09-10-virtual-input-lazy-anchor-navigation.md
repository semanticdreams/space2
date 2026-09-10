# VirtualInput Lazy Anchor Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ordinary `h/l/j/k` navigation in `VirtualInput` remain bounded after far lazy-line caret and horizontal-scroll movement.

**Architecture:** Keep `Input`/`InputModel` fallback behavior unchanged. Make `VirtualInput` the authoritative owner of logical cursor and viewport anchor caches, add bounded anchor-relative `LazyTextBuffer` APIs, and route only `VirtualInput` ordinary navigation hot paths through those APIs while exact `$`, `A`, and `G` continue to use exact logical paths.

**Tech Stack:** Space Fennel, `LazyTextBuffer`, `VirtualInput`, `TextState`, Fennel unit tests, file-viewer E2E tests, `docs/dev/features/lazy-text-buffer-virtual-input.md`.

## Global Constraints

- Start from current committed branch HEAD `191f9ef`.
- The uncommitted failed R5 follow-up was reverted; do not resurrect that patch.
- Keep `Input`/`InputModel` fallback behavior unchanged.
- `VirtualInput` owns authoritative cached logical cursor tuple: `cursor-byte`, `cursor-line`, `cursor-column`, plus validity/update rules.
- `VirtualInput` owns viewport horizontal anchor/cache: viewport-start byte/line/column keyed by `scroll-line`/`scroll-column`, plus per-row anchors when available.
- `LazyTextBuffer` exposes bounded anchor-relative APIs for adjacent codepoint movement within a line, target line/column movement from a nearby anchor or line start, and viewport row construction from a known start byte/column anchor.
- `TextState` hot paths for logical `VirtualInput` skip pre-command full clamp and call bounded methods for ordinary `h/l/j/k`.
- Exact `$`, `A`, and `G` can keep exact paths.
- Post-command caret visibility/refresh must consume/update cached anchors, not call full `line-column-for-byte` or `byte-for-line-column` scans from line start for ordinary movement.
- Add RED tests before changing production code.
- Use `local` instead of `let` in new Fennel code.
- Unsupported bounded-navigation states must fail explicitly or return an explicit unbounded result; no silent no-ops.
- Do not add compatibility aliases for option keys or method names.
- PR CI is the full integration gate.

---

## File Structure

- `assets/lua/lazy-text-buffer.fnl`: add anchor-relative bounded movement and anchored viewport-row APIs.
- `assets/lua/virtual-input.fnl`: own cursor/viewport anchor caches and expose bounded ordinary navigation methods.
- `assets/lua/text-state.fnl`: skip pre-command clamp for bounded `VirtualInput` hot keys and delegate `h/l/j/k` to the bounded facade when present.
- `assets/lua/tests/test-lazy-text-buffer.fnl`: RED and regression coverage for bounded anchor APIs.
- `assets/lua/tests/test-virtual-input.fnl`: RED and regression coverage for far-line `h/l/j/k`, cached viewport refresh, and exact command compatibility.
- `assets/lua/tests/e2e/test-fs-file-viewer-virtual-input.fnl`: extend file-viewer E2E coverage for far horizontal scroll plus ordinary navigation.
- `docs/dev/features/lazy-text-buffer-virtual-input.md`: document cursor/viewport anchor invariants and validation expectations.

## Observable Acceptance Criteria

- After exact `$` on a huge single lazy line, immediate `h` and `l` complete without calling `buffer:get-line-summary` or `buffer:line-column-for-byte`.
- Repeated `h/l` far into a huge line stays bounded and keeps caret visibility correct.
- `j/k` from a far logical source column into huge target lines uses cached/nearby anchors, preserves preferred logical column when bounded, and clamps explicitly when the target line is shorter.
- Far horizontal viewport refresh uses cached or supplied row-start anchors and does not materialize the prefix from line start.
- Exact `$`, `A`, and `G` still work.
- Existing `tests.test-input` and `tests.test-input-model` pass unchanged.
- `docs/dev/features/lazy-text-buffer-virtual-input.md` describes the new anchor-cache contract.

## Validation Ladder

- Runtime/freshness prerequisite when `./build/space` is missing or stale: `make build`.
- Focused Fennel compile check first:
  ```bash
  make fennel-check
  ```
- Constraints second:
  ```bash
  make constraints
  ```
- Focused tests third:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-lazy-text-buffer:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-input-model:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-input:main
  ```
- Focused E2E check after file-viewer E2E edits:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.e2e:main
  ```
- Broader local suite is justified because this changes modal text routing, lazy buffers, and file-viewer behavior:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```
- If Fennel delimiter or parse errors occur, inspect the nearest enclosing form around the reported location first; if needed, move nested logic into local helpers before retrying `make fennel-check`.
- PR CI is the full integration gate.

## Out of Scope

- No changes to `Input` or `InputModel` behavior.
- No syntax highlighting, search/replace, undo/redo, multi-cursor, binary editing, or CRDT work.
- No broad modal-editor parity beyond bounded ordinary `h/l/j/k` and preserving existing exact command behavior.
- No native C++ binding changes.
- No new persistence format for anchor caches beyond in-memory `LazyTextBuffer`/`VirtualInput` state.

---

### Task 1: RED LazyTextBuffer Anchor API Tests

**Files:**
- Modify: `assets/lua/tests/test-lazy-text-buffer.fnl`

**Interfaces:**
- Consumes: existing `LazyTextBuffer`, `LazyTextSource`, `call-with-large-concat-disabled`, `source-for-file`, and temp-file helpers.
- Produces failing tests for `buffer:adjacent-codepoint-from-anchor(anchor: table, delta: number) -> table`, `buffer:move-to-line-column-from-anchor(anchor: table, target-line: number, target-column: number, opts: table|nil) -> table`, and `buffer:build-viewport-row-from-anchor(anchor: table, columns: number) -> table`.

- [ ] **Step 1: Add a read spy helper near existing test helpers.**

  Add `instrument-source-reads` that wraps `source.read-range` and records `read-count`, `bytes-requested`, and `max-requested` on the source table. Each test creates a fresh source, so no restore function is required.

- [ ] **Step 2: Add RED test `lazy-text-buffer-adjacent-codepoint-from-anchor-stays-within-line`.**

  Required setup:
  - File text: `"abc\nxyz"`.
  - Anchor at line `0`, column `2`, byte `2`.
  - Call `(buffer:adjacent-codepoint-from-anchor {:byte 2 :line 0 :column 2} -1)` and assert result has `bounded? true`, `moved? true`, `byte 1`, `line 0`, `column 1`.
  - Call with anchor at line `0`, column `2`, byte `2` and delta `1`; assert `byte 3`, `column 3`, and no newline crossing.
  - Call with anchor at line `0`, column `3`, byte `3` and delta `1`; assert `bounded? true`, `moved? false`, `line-end? true`, `byte 3`, `column 3`.

- [ ] **Step 3: Add RED test `lazy-text-buffer-line-column-from-near-anchor-is-bounded`.**

  Required setup:
  - File text: one line of `(string.rep "a" 100000)`.
  - Anchor at byte `99990`, line `0`, column `99990`.
  - Call `(buffer:move-to-line-column-from-anchor anchor 0 99995 {:max-codepoints 16})`.
  - Assert `bounded? true`, `byte 99995`, `line 0`, `column 99995`, `clamped? false`.
  - Assert source reads remain bounded with `source.max-requested <= (math.max 16 buffer.chunk-bytes)`.

- [ ] **Step 4: Add RED test `lazy-text-buffer-line-column-from-far-line-start-reports-unbounded`.**

  Required setup:
  - File text: one line of `(string.rep "a" 100000)`.
  - Anchor at byte `0`, line `0`, column `0`.
  - Call `(buffer:move-to-line-column-from-anchor anchor 0 99995 {:max-codepoints 16})`.
  - Assert result has `bounded? false`, `reason :anchor-too-far`, and does not move `buffer.cursor-byte`.
  - Assert source reads remain bounded.

- [ ] **Step 5: Add RED test `lazy-text-buffer-builds-viewport-row-from-anchor-without-prefix-materialization`.**

  Required setup:
  - File text: one line of `(string.rep "a" 100000)`.
  - Anchor at byte `99990`, line `0`, column `99990`.
  - Use `call-with-large-concat-disabled 4096`.
  - Call `(buffer:build-viewport-row-from-anchor anchor 5)`.
  - Assert row has `line 0`, `start-byte 99990`, `start-column 99990`, `text "aaaaa"`, `column-byte-offsets [0 1 2 3 4 5]`, and `partial? true`.

- [ ] **Step 6: Register the new tests in the existing `tests` table.**

- [ ] **Step 7: Run RED validation.**

  Run:
  ```bash
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-lazy-text-buffer:main
  ```
  Expected: the new tests fail because the anchor APIs do not exist.

---

### Task 2: RED VirtualInput Hot-Path Tests

**Files:**
- Modify: `assets/lua/tests/test-virtual-input.fnl`

**Interfaces:**
- Consumes: existing `with-virtual-input-states`, `lazy-buffer`, `build-input`, `narrow-layout!`, `assert-caret-visible-inside`, and `key`.
- Produces failing tests that prove ordinary `h/l/j/k` no longer call full logical scans after far exact navigation.

- [ ] **Step 1: Add `instrument-logical-scans` helper near `record-viewport-calls`.**

  Required behavior:
  - Wrap `buffer.get-line-summary` and increment `state.get-line-summary-calls`.
  - Wrap `buffer.line-column-for-byte` and increment `state.line-column-for-byte-calls`.
  - Wrap `buffer.get-viewport` and increment `state.get-viewport-calls`.
  - Return the buffer with `buffer.state.logical-scan-calls` counters initialized.

- [ ] **Step 2: Add RED test `virtual-input-h-l-after-exact-dollar-on-huge-line-stays-bounded`.**

  Required setup:
  - Use `(string.rep "a" 100000)`.
  - Build `VirtualInput` with `line-count 1`, `column-count 4`, narrow layout to 4 columns.
  - Focus input, enter text state, execute shifted `$`.
  - Reset scan counters.
  - Execute `h`, then `l`.
  - Assert both commands are handled.
  - Assert `get-line-summary-calls == 0`.
  - Assert `line-column-for-byte-calls == 0`.
  - Assert caret remains visible and `scroll-column > 0`.

- [ ] **Step 3: Add RED test `virtual-input-repeated-h-l-far-into-huge-line-stays-bounded`.**

  Required setup:
  - Move exactly to line `0`, column `90000` using `input:move-caret-to-line-column`.
  - Reset scan counters.
  - Execute 25 alternating `h` and `l` commands through `TextState`.
  - Assert cursor column remains between `89999` and `90000`.
  - Assert no `get-line-summary` or `line-column-for-byte` calls during the loop.

- [ ] **Step 4: Add RED test `virtual-input-j-k-from-far-column-uses-cached-target-anchors`.**

  Required setup:
  - File text: three huge lines separated by newline, each `(string.rep "a" 100000)`.
  - Move exactly to line `1`, column `90000`.
  - Refresh viewport at `scroll-line 1`, `scroll-column 89997` so current row anchor is cached.
  - Seed target row anchors by calling the new bounded buffer API directly for line `0` and line `2` from nearby anchors created by exact moves, then return to line `1`, column `90000`.
  - Reset scan counters.
  - Execute `j`, assert cursor line `2`, cursor column `90000`, preferred column preserved, caret visible.
  - Execute `k`, assert cursor line `1`, cursor column `90000`, caret visible.
  - Assert no full `get-line-summary` or `line-column-for-byte` calls during `j/k`.

- [ ] **Step 5: Add RED test `virtual-input-refresh-after-far-horizontal-scroll-uses-cached-viewport-anchor`.**

  Required setup:
  - File text: `(string.rep "a" 100000)`.
  - Move exactly to line `0`, column `90000`.
  - Set or confirm `scroll-column` near `89997`.
  - Reset scan counters.
  - Call `input:refresh-viewport`.
  - Assert the rendered row starts at or near `scroll-column`.
  - Assert no `get-line-summary` or `line-column-for-byte` calls.
  - Assert source reads remain bounded if read instrumentation is present.

- [ ] **Step 6: Add RED exact-command compatibility test `virtual-input-exact-dollar-A-G-still-work-with-anchor-cache`.**

  Required assertions:
  - `$` on a long line lands at the last logical character.
  - `A` enters insert mode and places caret after line end.
  - Escape returns to text mode as existing tests expect.
  - `G` lands on the final logical line.
  - `input.cursor-index`, `input.cursor-line`, and `input.cursor-column` match `buffer.cursor-byte` and expected logical coordinates after each exact command.

- [ ] **Step 7: Register the new tests in the existing `tests` table.**

- [ ] **Step 8: Run RED validation.**

  Run:
  ```bash
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  ```
  Expected: the new hot-path tests fail because `TextState` still pre-clamps and `VirtualInput` still refreshes logical caret state through full scans.

---

### Task 3: LazyTextBuffer Anchor-Relative APIs

**Files:**
- Modify: `assets/lua/lazy-text-buffer.fnl`
- Test: `assets/lua/tests/test-lazy-text-buffer.fnl`

**Interfaces:**
- Consumes: RED tests from Task 1.
- Produces `buffer:adjacent-codepoint-from-anchor(anchor: table, delta: number) -> table`, `buffer:move-to-line-column-from-anchor(anchor: table, target-line: number, target-column: number, opts: table|nil) -> table`, and `buffer:build-viewport-row-from-anchor(anchor: table, columns: number) -> table`.

- [ ] **Step 1: Add `normalize-anchor` helper.**

  Requirements:
  - Assert `anchor.byte`, `anchor.line`, and `anchor.column` are numbers.
  - Clamp byte to `[0, buffer.size]`.
  - Floor line and column to non-negative integers.
  - Return `{ :byte byte :line line :column column }`.

- [ ] **Step 2: Add `adjacent-codepoint-from-anchor`.**

  Requirements:
  - Accept only `delta` values `-1` and `1`; reject other deltas with `LazyTextBuffer adjacent-codepoint-from-anchor requires delta -1 or 1`.
  - For `delta -1`, if `anchor.column <= 0`, return `{:bounded? true :moved? false :line-start? true :byte anchor.byte :line anchor.line :column anchor.column}` without crossing to the previous line.
  - For `delta -1`, use `previous-codepoint-boundary` from `anchor.byte`, update column by `-1`, and return bounded result.
  - For `delta 1`, read only the next composed codepoint bytes from `anchor.byte`; if newline or EOF is next, return `moved? false` and `line-end? true`.
  - Never call `get-line-summary`, `line-column-for-byte`, or `byte-for-line-column`.

- [ ] **Step 3: Add bounded forward/backward scan from an anchor to a target column.**

  Requirements:
  - Helper name: `scan-line-column-from-anchor`.
  - Inputs: `buffer`, normalized `anchor`, `target-column`, `max-codepoints`.
  - If absolute column delta exceeds `max-codepoints`, return `{:bounded? false :reason :anchor-too-far :byte anchor.byte :line anchor.line :column anchor.column}` before scanning.
  - For forward scans, stop at newline/EOF and return `clamped? true` if the requested column is beyond the discovered line end.
  - For backward scans, use `previous-codepoint-boundary` and stop at column `0`.
  - Keep reads bounded by codepoint delta and chunk size.
  - Preserve UTF-8 boundary behavior and invalid-byte replacement semantics already used by row building.

- [ ] **Step 4: Add `move-to-line-column-from-anchor`.**

  Requirements:
  - Assert numeric `target-line` and `target-column`.
  - Default `opts.max-codepoints` to `(math.max 1 (* 2 (or buffer.chunk-bytes 1)))`.
  - If `target-line == anchor.line`, use `scan-line-column-from-anchor`.
  - If `target-line` differs from `anchor.line`, require `opts.line-anchor` or `opts.target-anchor`; otherwise return `{:bounded? false :reason :missing-line-anchor :byte anchor.byte :line anchor.line :column anchor.column}`.
  - When `opts.target-anchor` is supplied, scan from that anchor to `target-column`.
  - When `opts.line-anchor` is supplied, scan from line start only if target-column is within `max-codepoints`; otherwise return `anchor-too-far`.
  - On bounded success, update `buffer.cursor-byte` to result byte and return `{:bounded? true :byte byte :line line :column column :clamped? clamped?}`.
  - On unbounded result, do not move `buffer.cursor-byte`.

- [ ] **Step 5: Add `build-viewport-row-from-anchor`.**

  Requirements:
  - Normalize the anchor.
  - Call existing row-building logic from `anchor.byte` for exactly `columns`.
  - Add `row.start-column = anchor.column`.
  - Preserve `row.line`, `row.start-byte`, `row.end-byte`, `row.column-byte-offsets`, `row.display-byte-offsets`, `row.partial?`, `row.line-end-known?`, and `row.newline-bytes`.
  - Never compute start byte from line start.

- [ ] **Step 6: Export the three methods from the `LazyTextBuffer` object literal.**

- [ ] **Step 7: Run focused validation.**

  ```bash
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-lazy-text-buffer:main
  ```

---

### Task 4: VirtualInput Authoritative Cursor and Viewport Anchor Cache

**Files:**
- Modify: `assets/lua/virtual-input.fnl`
- Test: `assets/lua/tests/test-virtual-input.fnl`

**Interfaces:**
- Consumes `buffer:adjacent-codepoint-from-anchor(anchor, delta) -> table`, `buffer:move-to-line-column-from-anchor(anchor, target-line, target-column, opts) -> table`, and `buffer:build-viewport-row-from-anchor(anchor, columns) -> table`.
- Produces `input.bounded-logical-navigation? = true`, `input:move-caret-horizontal-bounded(delta: number, opts: table|nil) -> boolean`, `input:move-caret-vertical-bounded(delta: number, opts: table|nil) -> boolean`, and authoritative `input.cursor-index`, `input.cursor-line`, `input.cursor-column`.

- [ ] **Step 1: Add cursor cache helpers.**

  Required helpers:
  - `cursor-anchor [self] -> {:byte self.cursor-index :line self.cursor-line :column self.cursor-column}`
  - `set-cached-caret! [self byte line column]`
  - `invalidate-anchor-caches! [self]`
  - `sync-buffer-cursor-from-cache! [self]`

  Requirements:
  - `set-cached-caret!` updates `self.cursor-index`, `self.cursor-line`, `self.cursor-column`, `self.model.cursor-index`, `self.model.cursor-line`, `self.model.cursor-column`, and `self.buffer.cursor-byte`.
  - Do not call `line-column-for-byte` from these helpers.

- [ ] **Step 2: Add viewport anchor cache helpers.**

  Required fields:
  - `self.viewport-anchor-cache`, keyed by string `"<line>:<column>"`.
  - `self.viewport-row-anchor-cache`, keyed by string `"<line>:<column>"`.

  Required helpers:
  - `anchor-cache-key [line column] -> string`
  - `store-viewport-row-anchor! [self row start-column]`
  - `lookup-viewport-row-anchor [self line column] -> table|nil`
  - `store-viewport-anchors! [self snapshot]`

- [ ] **Step 3: Update `refresh-viewport` to use cached anchors.**

  Requirements:
  - If buffer exposes `build-viewport-row-from-anchor` and a matching row anchor exists for `scroll-line`/`scroll-column`, build the first row from that anchor.
  - If existing `buffer:get-viewport` is used for exact/fallback refresh, store row anchors from every returned row.
  - For ordinary movement refreshes, pass an option such as `{:anchored? true}` and require anchor-based refresh; if no matching anchor exists, keep bounded behavior by rendering the previous cached viewport and return explicit `false` to the caller rather than scanning from line start.
  - `sync-model-state` must copy cached cursor state into `model` and must not call `refresh-logical-caret-state` after ordinary bounded moves.

- [ ] **Step 4: Replace ordinary horizontal movement with cached anchor movement.**

  Requirements:
  - `move-caret-horizontal-bounded` calls `buffer:adjacent-codepoint-from-anchor (cursor-anchor self) delta`.
  - On bounded moved result, call `set-cached-caret!`, update selection, keep column visible from cached column, store a viewport row anchor for the new `scroll-column`, mark caret dirty, and refresh viewport through anchored path.
  - If result is line start/end with no movement, return `false`.
  - Never call `keep-caret-visible` if it would call `refresh-logical-caret-state`.

- [ ] **Step 5: Replace ordinary vertical movement with cached anchor movement.**

  Requirements:
  - `move-caret-vertical-bounded` uses `self.__preferred-column` or cached cursor column.
  - It looks for target-line anchors at the preferred column, current `scroll-column`, or line start in that order.
  - It calls `buffer:move-to-line-column-from-anchor` with a bounded `max-codepoints` based on `visible-column-count + 2`.
  - On bounded success, update cached caret and preferred column, keep line/column visible from cached values, update selection, and refresh via anchored path.
  - On unbounded result, return `false` and preserve cursor state.

- [ ] **Step 6: Preserve exact path behavior while updating caches.**

  Requirements:
  - `apply-caret-line-column` may keep calling `buffer:move-caret-to-line-column`.
  - After an exact move succeeds, set cached cursor directly from requested line/column and `buffer.cursor-byte`.
  - For exact line-end commands, cache the exact final logical column passed to the move.
  - After exact movement adjusts `scroll-column`, derive a viewport-start anchor by moving left from the cursor anchor at most `visible-column-count + 1` codepoints, then store it for `scroll-line`/`scroll-column`.

- [ ] **Step 7: Make edit paths invalidate or repair caches explicitly.**

  Requirements:
  - Insert/delete paths may use exact refresh after mutation.
  - They must call `invalidate-anchor-caches!` before exact resync.
  - They must leave `selection-anchor-byte` consistent with `buffer.cursor-byte`.

- [ ] **Step 8: Run focused validation.**

  ```bash
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  ```

---

### Task 5: TextState Bounded Hot-Path Routing

**Files:**
- Modify: `assets/lua/text-state.fnl`
- Test: `assets/lua/tests/test-virtual-input.fnl`
- Test: `assets/lua/tests/test-input-model.fnl`
- Test: `assets/lua/tests/test-input.fnl`

**Interfaces:**
- Consumes `input.bounded-logical-navigation?`, `input:move-caret-horizontal-bounded(delta, opts) -> boolean`, and `input:move-caret-vertical-bounded(delta, opts) -> boolean`.
- Produces `TextState` dispatch that keeps `Input`/`InputModel` behavior unchanged while skipping full pre-command clamp for bounded `VirtualInput` `h/l/j/k`.

- [ ] **Step 1: Add helper `bounded-hot-key?`.**

  It must return true only for `h`, `l`, `j`, `k`, `SDLK_LEFT`, and `SDLK_RIGHT` when active input has `bounded-logical-navigation?`.

- [ ] **Step 2: Update `handle-text-key`.**

  Requirements:
  - Resolve key before calling `clamp-caret-to-current-line`.
  - If `bounded-hot-key?` is true, do not call `clamp-caret-to-current-line`.
  - For all other inputs and keys, preserve the existing clamp-before-command behavior.

- [ ] **Step 3: Update `move-horizontal`.**

  Requirements:
  - If input has `bounded-logical-navigation?` and `move-caret-horizontal-bounded`, call it directly.
  - On success, call `remember-column input nil`.
  - Otherwise execute the existing implementation unchanged.

- [ ] **Step 4: Update `move-vertical`.**

  Requirements:
  - If input has `bounded-logical-navigation?` and `move-caret-vertical-bounded`, call it directly with delta.
  - Preserve preferred-column behavior by calling `remember-column input nil` before the bounded call.
  - Otherwise execute the existing implementation unchanged.

- [ ] **Step 5: Run focused compatibility validation.**

  ```bash
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-input-model:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-input:main
  ```

---

### Task 6: File-Viewer E2E Anchor Navigation Coverage

**Files:**
- Modify: `assets/lua/tests/e2e/test-fs-file-viewer-virtual-input.fnl`

**Interfaces:**
- Consumes: bounded `VirtualInput` navigation from Tasks 4 and 5.
- Produces: E2E coverage that the graph file viewer remains usable after far horizontal navigation.

- [ ] **Step 1: Extend the existing expanded file-viewer VirtualInput E2E flow.**

  Add a large single-line file fixture using a generated string with at least `100000` ASCII characters.

- [ ] **Step 2: Navigate to far horizontal position through existing routed input.**

  Required flow:
  - Open the file-viewer node.
  - Focus the exposed `view.virtual-input`.
  - Enter text mode.
  - Use exact `$` or existing routed command path to move to far line end.
  - Assert `view.virtual-input.scroll-column > 0`.

- [ ] **Step 3: Exercise ordinary `h/l` after exact far movement.**

  Required assertions:
  - Routed `h` is handled.
  - Routed `l` is handled.
  - `view.virtual-input.cursor-column` changes by one and then returns.
  - Caret remains visible after a layout pass.

- [ ] **Step 4: Run focused E2E validation.**

  ```bash
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.e2e:main
  ```

---

### Task 7: Developer Documentation

**Files:**
- Modify: `docs/dev/features/lazy-text-buffer-virtual-input.md`

**Interfaces:**
- Consumes: final API and invariants from Tasks 3-6.
- Produces: canonical developer documentation for lazy anchor navigation.

- [ ] **Step 1: Update the “Viewport snapshots” section.**

  Document:
  - anchor-relative viewport-row construction;
  - row anchors include byte, line, and logical column;
  - far horizontal viewport refresh must use a cached row anchor or explicitly report that bounded refresh is unavailable.

- [ ] **Step 2: Update the “VirtualInput widget” section.**

  Document:
  - authoritative cached cursor tuple: `cursor-index`, `cursor-line`, `cursor-column`;
  - ordinary `h/l/j/k` uses cached anchors;
  - exact `$`, `A`, and `G` may still perform exact scans and must update caches afterward.

- [ ] **Step 3: Update the “Testing expectations” section.**

  Add focused checks for:
  - `tests.test-lazy-text-buffer`;
  - `tests.test-virtual-input`;
  - `tests.test-input`;
  - `tests.test-input-model`;
  - file-viewer E2E when file-viewer routing changes.

- [ ] **Step 4: Validate docs and code together.**

  ```bash
  rg "anchor" docs/dev/features/lazy-text-buffer-virtual-input.md
  make fennel-check
  make constraints
  ```

---

### Task 8: Final Integration Validation

**Files:**
- Modify: no production files unless validation exposes a defect.
- Test: focused and broader suites listed below.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: clean, validated branch ready for PR CI.

- [ ] **Step 1: Confirm no discarded R5 patch artifacts remain.**

  Run:
  ```bash
  git diff --name-only origin/main...HEAD
  rg "R5|hot-path patch|failed follow-up" assets/lua docs/dev docs/plans
  ```
  Expected: no production references to the failed R5 follow-up.

- [ ] **Step 2: Run the full focused validation ladder.**

  ```bash
  make build
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-lazy-text-buffer:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-input-model:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-input:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.e2e:main
  ```

- [ ] **Step 3: Run broader local suite.**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- [ ] **Step 4: Treat PR CI as the full integration gate.**

  PR CI must pass before claiming ready-to-merge.
