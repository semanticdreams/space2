# VirtualInput Navigation Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `VirtualInput` text navigation and caret behavior match the working `Input` widget while preserving lazy, clipped rendering for large file nodes.

**Architecture:** Keep `TextState` as the shared modal navigation layer, but stop feeding it clipped viewport state from `VirtualInput`. Add a small logical navigation facade backed by `LazyTextBuffer` full-line queries, then teach `TextState` to prefer that facade when present while retaining the existing `InputModel` path.

**Tech Stack:** Space Fennel widgets, `LazyTextBuffer`, `VirtualInput`, `TextState`/`InsertState`, Fennel unit tests, graph file-viewer E2E harness.

## Global Constraints

- Existing `Input` and `InputModel` behavior must remain unchanged.
- `VirtualInput` must not load whole file contents into an `InputModel`, one string, or one `Text` widget.
- Rendered `VirtualInput` rows must remain bounded by visible viewport rows and columns.
- Text navigation must use full logical document line/column coordinates, not clipped viewport coordinates.
- Add RED tests before changing production code.
- Use project-native Fennel validation only: touched-file `tools.fennel-check`, then `rtk make constraints`, then focused tests.
- Use `local` instead of `let` in new Fennel code.
- Assert or raise explicit errors for required lazy-buffer APIs; do not silently fall back.
- Do not broaden `TextState` beyond the optional logical-navigation hooks required for `VirtualInput` parity.
- PR CI remains the full integration gate.

---

## File Structure

- `assets/lua/lazy-text-buffer.fnl`: add bounded full-logical-line query helpers over composed piece-table data.
- `assets/lua/virtual-input.fnl`: expose logical navigation facade methods and use them for cursor sync, movement, edit visibility, and disconnect mode normalization.
- `assets/lua/text-state.fnl`: prefer the logical facade when available; keep the existing `InputModel` path unchanged.
- `assets/lua/tests/test-virtual-input.fnl`: add parity tests for full-line navigation, clipped long lines, page/goto movement, edit visibility, delete clamp, and disconnect mode normalization.
- `assets/lua/tests/e2e/test-fs-file-viewer-virtual-input.fnl`: extend the expanded graph file-viewer routed path with representative navigation/caret assertions.

---

### Task 1: Add RED VirtualInput Navigation Parity Tests

**Files:**
- Modify: `assets/lua/tests/test-virtual-input.fnl`

**Interfaces:**
- Consumes: existing `with-virtual-input-states`, `lazy-buffer`, `build-input`, `snapshot-text` test helpers.
- Produces failing tests that describe full logical navigation semantics for later tasks.

- [ ] **Step 1: Add local test helpers near existing helpers.**

```fennel
(fn key [value]
  (string.byte value))

(fn narrow-layout! [input columns lines]
  (input.layout:measurer)
  (set input.layout.size
       (glm.vec3 (+ (* 2 input.padding.x) (* columns input.column-width))
                 (+ (* 2 input.padding.y) (* lines input.line-height))
                 0))
  (input.layout:layouter)
  input)

(fn assert-caret-visible-inside [input message]
  (input.layout:layouter)
  (assert input.caret.visible? (.. message ": caret should be visible"))
  (local local-x (- input.caret.layout.position.x input.layout.position.x))
  (local local-y (- input.caret.layout.position.y input.layout.position.y))
  (assert (>= local-x input.padding.x) (.. message ": caret should be inside left edge"))
  (assert (<= local-x (- input.layout.size.x input.padding.x))
          (.. message ": caret should be inside right edge"))
  (assert (>= local-y input.padding.y) (.. message ": caret should be inside bottom edge"))
  (assert (<= local-y (- input.layout.size.y input.padding.y))
          (.. message ": caret should be inside top edge")))
```

- [ ] **Step 2: Add a RED test proving line-edge commands use the full logical line, not the clipped segment.**

```fennel
(fn virtual-input-text-state-line-edges-use-full-logical-long-line []
  (with-virtual-input-states
    (fn [env]
      (local states (. env :states))
      (local text-state (. env :text-state))
      (local insert-state (. env :insert-state))
      (local buffer (lazy-buffer "text-state-full-line-edges"
                                 "  abcdefghijklmnopqrstuvwxyz\nshort\n"))
      (buffer:move-caret-to-line-column 0 8)
      (local input (build-input {:buffer buffer :line-count 1 :column-count 4}))
      (narrow-layout! input 4 1)
      (input:refresh-viewport)
      (states:set-state :text)
      (assert (text-state:on-key-down {:key (key "0")})
              "0 should move to full logical line start")
      (assert (= buffer.cursor-byte 0) "0 should land at byte 0, not viewport start")
      (assert (= input.cursor-column 0) "0 should sync logical column 0")
      (assert (= input.scroll-column 0) "0 should reveal logical start")
      (assert (text-state:on-key-down {:key (key "$") :mod 1})
              "$ should move to full logical line end")
      (assert (= input.cursor-column 27) "$ should use full line length")
      (assert (= buffer.cursor-byte 27) "$ should place caret on last logical character")
      (assert (> input.scroll-column 0) "$ should reveal logical line end")
      (assert-caret-visible-inside input "$")
      (assert (text-state:on-key-down {:key (key "^") :mod 1})
              "^ should move to first nonblank in full logical line")
      (assert (= input.cursor-column 2) "^ should ignore leading spaces")
      (assert (= buffer.cursor-byte 2) "^ should land at first nonblank byte")
      (assert (text-state:on-key-down {:key (key "A")})
              "A should append after full logical line end")
      (assert (= input.mode :insert) "A should enter insert mode")
      (assert (= buffer.cursor-byte 28) "A should place insert caret after full line")
      (assert-caret-visible-inside input "A")
      (assert (insert-state:on-key-down {:key 27}) "Escape should leave A insert mode")
      (assert (text-state:on-key-down {:key (key "I")})
              "I should insert at first nonblank of full logical line")
      (assert (= input.mode :insert) "I should enter insert mode")
      (assert (= buffer.cursor-byte 2) "I should land at first nonblank byte")
      (input:drop))))
```

- [ ] **Step 3: Add a RED test proving `j`/`k` preserve logical columns across clipped long lines.**

```fennel
(fn virtual-input-text-state-j-k-preserve-logical-column-over-clipped-lines []
  (with-virtual-input-states
    (fn [env]
      (local text-state (. env :text-state))
      (local buffer (lazy-buffer "text-state-clipped-vertical"
                                 "0123456789ABCDEFGHIJ\nabcdefghijklmnopqrst\nUVWXYZ0123456789abcd\n"))
      (buffer:move-caret-to-line-column 0 8)
      (local input (build-input {:buffer buffer :line-count 2 :column-count 4}))
      (narrow-layout! input 4 2)
      (input:refresh-viewport)
      (assert (text-state:on-key-down {:key (key "j")}) "j should move down")
      (assert (= input.cursor-line 1) "j should move to logical line 1")
      (assert (= input.cursor-column 8) "j should preserve logical column 8")
      (assert (> input.scroll-column 0) "j should keep clipped logical column visible")
      (assert-caret-visible-inside input "j")
      (assert (text-state:on-key-down {:key (key "k")}) "k should move up")
      (assert (= input.cursor-line 0) "k should return to logical line 0")
      (assert (= input.cursor-column 8) "k should preserve logical column 8")
      (assert-caret-visible-inside input "k")
      (input:drop))))
```

- [ ] **Step 4: Add RED tests for `gg`, `G`, and page movement using logical lines.**

```fennel
(fn virtual-input-text-state-goto-and-page-movement-use-logical-lines []
  (with-virtual-input-states
    (fn [env]
      (local text-state (. env :text-state))
      (local buffer (lazy-buffer "text-state-goto-page"
                                 "line0\nline1\nline2\nline3\nline4\nline5\n"))
      (local input (build-input {:buffer buffer :line-count 2 :column-count 8}))
      (narrow-layout! input 8 2)
      (input:on-click {:row-index 1 :column 0})
      (assert (text-state:on-key-down {:key (key "G")}) "G should move to final logical line")
      (assert (= input.cursor-line 6) "G should include trailing empty logical line")
      (assert (= input.scroll-line 5) "G should reveal final line in two-line viewport")
      (assert-caret-visible-inside input "G")
      (assert (text-state:on-key-down {:key (key "g")}) "first g should enter prefix")
      (assert (text-state:on-key-down {:key (key "g")}) "gg should move to first line")
      (assert (= input.cursor-line 0) "gg should return to logical line 0")
      (assert (= input.scroll-line 0) "gg should reveal first line")
      (assert-caret-visible-inside input "gg")
      (assert (input:on-key-down {:key 1073741902}) "PageDown should be handled")
      (assert (= input.cursor-line 2) "PageDown should move by visible logical lines")
      (assert (= input.scroll-line 2) "PageDown should scroll by visible logical lines")
      (assert-caret-visible-inside input "PageDown")
      (input:drop))))
```

- [ ] **Step 5: Add RED tests for edit visibility, delete clamp, and disconnect normalization.**

```fennel
(fn virtual-input-editing-maintains-horizontal-and-vertical-visibility []
  (local buffer (lazy-buffer "edit-both-axis-visibility" "row0\nrow1\nabcdefghij\n"))
  (buffer:move-caret-to-line-column 2 8)
  (local input (build-input {:buffer buffer :line-count 2 :column-count 4}))
  (narrow-layout! input 4 2)
  (set input.scroll-line 1)
  (set input.scroll-column 5)
  (input:refresh-viewport)
  (assert (input:insert-text "\nZ") "insert should mutate lazy buffer")
  (assert (= input.cursor-line 3) "inserted newline should update logical line")
  (assert (= input.cursor-column 1) "inserted text should update logical column")
  (assert (= input.scroll-line 2) "insert should keep new line visible")
  (assert (= input.scroll-column 1) "insert should keep new column visible")
  (assert-caret-visible-inside input "insert")
  (input:drop))

(fn virtual-input-text-state-x-deletes-clamps-and-keeps-caret-visible []
  (with-virtual-input-states
    (fn [env]
      (local text-state (. env :text-state))
      (local buffer (lazy-buffer "delete-clamp-visible" "abcdefghij"))
      (buffer:move-caret-to-line-column 0 9)
      (local input (build-input {:buffer buffer :line-count 1 :column-count 4}))
      (narrow-layout! input 4 1)
      (set input.scroll-column 6)
      (input:refresh-viewport)
      (assert (text-state:on-key-down {:key (key "x")}) "x should delete at cursor")
      (assert (= (snapshot-text buffer) "abcdefghi") "x should delete final character")
      (assert (= input.cursor-column 8) "x should clamp to new final logical char")
      (assert (= buffer.cursor-byte 8) "x should clamp buffer cursor")
      (assert-caret-visible-inside input "x")
      (input:drop))))

(fn virtual-input-disconnect-normalizes-mode-like-input []
  (local buffer (lazy-buffer "disconnect-normal-mode" "abc"))
  (local input (build-input {:buffer buffer :line-count 1 :column-count 8}))
  (input:enter-insert-mode)
  (input:on-state-connected {})
  (input:on-state-disconnected {})
  (assert (= input.connected? false) "disconnect should clear connected flag")
  (assert (= input.mode :normal) "disconnect should normalize VirtualInput mode")
  (input:drop))
```

- [ ] **Step 6: Register all new tests in the test list.**

```fennel
(table.insert tests {:name "VirtualInput TextState line edges use full logical long line" :fn virtual-input-text-state-line-edges-use-full-logical-long-line})
(table.insert tests {:name "VirtualInput TextState j/k preserve logical column over clipped lines" :fn virtual-input-text-state-j-k-preserve-logical-column-over-clipped-lines})
(table.insert tests {:name "VirtualInput TextState goto and page movement use logical lines" :fn virtual-input-text-state-goto-and-page-movement-use-logical-lines})
(table.insert tests {:name "VirtualInput editing maintains horizontal and vertical visibility" :fn virtual-input-editing-maintains-horizontal-and-vertical-visibility})
(table.insert tests {:name "VirtualInput TextState x deletes clamps and keeps caret visible" :fn virtual-input-text-state-x-deletes-clamps-and-keeps-caret-visible})
(table.insert tests {:name "VirtualInput disconnect normalizes mode like Input" :fn virtual-input-disconnect-normalizes-mode-like-input})
```

- [ ] **Step 7: Run RED validation.**

Run:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
```

Expected: FAIL on the new navigation/caret parity assertions, not a Fennel parse error.

---

### Task 2: Add LazyTextBuffer Full Logical Query Helpers

**Files:**
- Modify: `assets/lua/lazy-text-buffer.fnl`

**Interfaces:**
- Produces: `get-line-summary`, `get-line-count`, `line-column-for-byte`, and `byte-for-codepoint-position` methods on lazy buffers.
- Consumes: existing composed-piece read helpers and line-anchor helpers in `lazy-text-buffer.fnl`.

- [ ] **Step 1: Add chunked scanner helpers in `lazy-text-buffer.fnl`.**

Implement local helpers that scan composed bytes/codepoints from a starting byte without building the whole file:

```fennel
(local logical-scan-chunk-bytes 4096)

(fn whitespace-codepoint? [codepoint]
  (or (= codepoint 9)
      (= codepoint 10)
      (= codepoint 11)
      (= codepoint 12)
      (= codepoint 13)
      (= codepoint 32)))
```

The scanner must repeatedly call the existing composed-range reader with `logical-scan-chunk-bytes`, advance by UTF-8 codepoint boundaries, and stop at LF, CR, CRLF, or EOF.

- [ ] **Step 2: Implement `get-line-summary`.**

Required method contract:

```fennel
(buffer:get-line-summary line)
;; returns {:line line
;;          :known? true
;;          :start-byte start-byte
;;          :line-end-byte end-byte-before-newline
;;          :line-end-known? true
;;          :newline-bytes 0-or-1-or-2
;;          :codepoint-count count-before-newline
;;          :first-nonblank-column first-nonblank-or-line-length}
```

Clamp `line` to a zero-based integer. For an empty buffer, return a single line with start/end byte `0`, `codepoint-count 0`, and `first-nonblank-column 0`. Assert that `line` is numeric.

- [ ] **Step 3: Implement `get-line-count`.**

Required method contract:

```fennel
(buffer:get-line-count)
;; empty text => 1
;; "a" => 1
;; "a\n" => 2
;; "a\nb" => 2
```

Scan chunks from byte `0` to EOF, count LF/CR/CRLF as one logical line separator, and include the trailing empty logical line after a trailing newline.

- [ ] **Step 4: Implement `line-column-for-byte`.**

Required method contract:

```fennel
(local (line column known?) (buffer:line-column-for-byte byte))
```

Clamp `byte` into `[0, buffer.size]`. Return zero-based logical line and codepoint column containing that byte. Return `known? true` for normal in-memory and file-backed scans. Use nearest existing line anchor when available; otherwise scan from byte `0`.

- [ ] **Step 5: Implement `byte-for-codepoint-position`.**

Required method contract:

```fennel
(buffer:byte-for-codepoint-position position)
```

Clamp negative positions to byte `0`. Treat position as a full-document codepoint index with newline codepoints included. Return `buffer.size` when position is beyond EOF.

- [ ] **Step 6: Attach the four methods to the buffer object.**

Add these keys where the buffer object is assembled:

```fennel
:get-line-summary get-line-summary
:get-line-count get-line-count
:line-column-for-byte line-column-for-byte
:byte-for-codepoint-position byte-for-codepoint-position
```

- [ ] **Step 7: Run touched-file compile validation.**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/lazy-text-buffer.fnl
```

Expected: PASS.

---

### Task 3: Add VirtualInput Logical Facade and TextState Integration

**Files:**
- Modify: `assets/lua/virtual-input.fnl`
- Modify: `assets/lua/text-state.fnl`

**Interfaces:**
- Consumes from Task 2: `buffer:get-line-summary`, `buffer:get-line-count`, `buffer:line-column-for-byte`, `buffer:byte-for-codepoint-position`.
- Produces on `VirtualInput`: `text-line-count`, `text-line-length`, `text-line-first-nonblank`, `text-cursor-line-column`, `move-caret-to-line-column`.

- [ ] **Step 1: Add required-buffer-api checks in `virtual-input.fnl`.**

```fennel
(fn require-logical-buffer-api [self method]
  (assert self "VirtualInput logical navigation requires input")
  (assert self.buffer "VirtualInput logical navigation requires buffer")
  (when (not (. self.buffer method))
    (error (.. "VirtualInput requires buffer:" (tostring method) " for logical navigation"))))
```

- [ ] **Step 2: Add logical cursor sync and visibility helpers in `virtual-input.fnl`.**

```fennel
(fn refresh-logical-caret-state [self]
  (require-logical-buffer-api self :line-column-for-byte)
  (local (line column known?) (self.buffer:line-column-for-byte (or self.buffer.cursor-byte 0)))
  (when known?
    (set self.cursor-line line)
    (set self.cursor-column column)
    (set self.cursor-index 0)
    (set self.model.cursor-line line)
    (set self.model.cursor-column column)
    (set self.model.cursor-index 0))
  (values line column known?))

(fn keep-caret-visible [self]
  (local (line column known?) (refresh-logical-caret-state self))
  (when known?
    (keep-line-visible self line)
    (keep-column-visible self column))
  known?)
```

- [ ] **Step 3: Change `sync-model-state` so logical cursor state does not come from clipped viewport rows.**

After refreshing viewport rows, keep `self.lines` as the visible row cache, but set `self.model.lines` to `nil` and call `refresh-logical-caret-state`. This prevents `TextState` from treating clipped rows as full document lines.

- [ ] **Step 4: Add the public logical facade methods to `virtual-input.fnl`.**

```fennel
(fn text-line-count [self]
  (require-logical-buffer-api self :get-line-count)
  (self.buffer:get-line-count))

(fn text-line-length [self line]
  (require-logical-buffer-api self :get-line-summary)
  (local summary (self.buffer:get-line-summary line))
  (or summary.codepoint-count 0))

(fn text-line-first-nonblank [self line]
  (require-logical-buffer-api self :get-line-summary)
  (local summary (self.buffer:get-line-summary line))
  (or summary.first-nonblank-column 0))

(fn text-cursor-line-column [self]
  (local (line column known?) (refresh-logical-caret-state self))
  (if known?
      (values line column)
      (values (or self.cursor-line 0) (or self.cursor-column 0))))

(fn move-caret-to-line-column [self line column opts]
  (apply-caret-line-column self line column (and opts opts.extend-selection?)))
```

- [ ] **Step 5: Update successful VirtualInput movement and edit paths to use `keep-caret-visible`.**

Update these functions after successful movement or mutation: `apply-caret-byte`, `apply-caret-line-column`, `insert-text`, `delete-active-selection`, `delete-before-cursor`, `delete-at-cursor`, `apply-horizontal-caret-move`, and `scroll-lines`. Preserve existing selection-anchor behavior, then refresh logical cursor, apply both vertical and horizontal visibility, mark caret dirty, and refresh the viewport.

- [ ] **Step 6: Make `move-caret-to(position)` use full-document codepoint position.**

```fennel
(fn move-caret-to [self position]
  (require-logical-buffer-api self :byte-for-codepoint-position)
  (apply-caret-byte self (self.buffer:byte-for-codepoint-position position) false))
```

- [ ] **Step 7: Make `VirtualInput :end` movement use full logical line length.**

For `delta :end`, compute the current logical line and move to `max(0, text-line-length - 1)`, not the visible row width.

- [ ] **Step 8: Normalize mode on state disconnect.**

```fennel
(fn on-state-disconnected [self _event]
  (set self.connected? false)
  (self:enter-normal-mode))
```

- [ ] **Step 9: Add facade methods to the `input` table.**

```fennel
:text-line-count text-line-count
:text-line-length text-line-length
:text-line-first-nonblank text-line-first-nonblank
:text-cursor-line-column text-cursor-line-column
:move-caret-to-line-column move-caret-to-line-column
```

- [ ] **Step 10: Add optional logical helper functions in `text-state.fnl`.**

```fennel
(fn has-logical-navigation? [input]
  (and input input.text-line-count input.text-line-length
       input.text-line-first-nonblank input.text-cursor-line-column
       input.move-caret-to-line-column))

(fn logical-current-line-index [input]
  (if (has-logical-navigation? input)
      (do
        (local (line _column) (input:text-cursor-line-column))
        (math.max 0 (or line 0)))
      (current-line-index input)))

(fn logical-current-column [input]
  (if (has-logical-navigation? input)
      (do
        (local (_line column) (input:text-cursor-line-column))
        (math.max 0 (or column 0)))
      (current-column input)))

(fn logical-line-count [input lines]
  (if (has-logical-navigation? input)
      (input:text-line-count)
      (line-count lines)))

(fn logical-line-length [input lines idx]
  (if (has-logical-navigation? input)
      (input:text-line-length idx)
      (line-length lines idx)))
```

- [ ] **Step 11: Update `move-to-line-column` in `text-state.fnl` to prefer the facade.**

For logical inputs, clamp `line-index` to `[0, input:text-line-count - 1]`, clamp `column` with `input:text-line-length`, call `input:move-caret-to-line-column`, and `remember-column` using the clamped logical column. For non-logical inputs, preserve the existing flat `model.lines`/`line-start-index` code path.

- [ ] **Step 12: Update only the affected `text-state.fnl` helpers to use logical helpers.**

Update `move-to-line-edge`, `move-to-first-nonblank`, `move-to-last-line`, `move-horizontal`, `move-vertical`, `clamp-caret-to-current-line`, and `open-line-above`. Required mapping:

```fennel
current-line-index -> logical-current-line-index
current-column -> logical-current-column
line-count -> logical-line-count
line-length -> logical-line-length
first nonblank -> input:text-line-first-nonblank when has-logical-navigation?
```

- [ ] **Step 13: Run compile and focused unit validation.**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/lazy-text-buffer.fnl --file assets/lua/virtual-input.fnl --file assets/lua/text-state.fnl --file assets/lua/tests/test-virtual-input.fnl
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
```

Expected: compile PASS and focused tests PASS.

---

### Task 4: Extend Expanded Graph File-Viewer E2E

**Files:**
- Modify: `assets/lua/tests/e2e/test-fs-file-viewer-virtual-input.fnl`

**Interfaces:**
- Consumes: existing routed expanded graph test helpers and the logical buffer facade from Tasks 2-3.
- Produces: representative real-path E2E coverage for long-line text navigation and caret visibility.

- [ ] **Step 1: Extend `run-expanded-graph-routed-click` after existing focus/mode assertions.**

Add representative assertions:

```fennel
  (for [_ 1 12]
    (assert (active-key-down {:key (string.byte "l")})
            "expanded file viewer should route repeated l navigation"))
  (assert (> view.virtual-input.scroll-column 0)
          "expanded routed long-line navigation should scroll horizontally")
  (assert-caret-inside-input view.virtual-input)

  (assert (active-key-down {:key (string.byte "0")})
          "expanded routed 0 should move to full logical line start")
  (assert (= view.virtual-input.cursor-column 0)
          "expanded routed 0 should set logical cursor column 0")
  (assert (= view.virtual-input.scroll-column 0)
          "expanded routed 0 should reveal logical line start")
  (assert-caret-inside-input view.virtual-input)

  (assert (active-key-down {:key (string.byte "$") :mod 1})
          "expanded routed $ should move to full logical line end")
  (local first-summary (view.virtual-input.buffer:get-line-summary 0))
  (assert (= view.virtual-input.cursor-column
             (math.max 0 (- first-summary.codepoint-count 1)))
          "expanded routed $ should use full logical line length")
  (assert-caret-inside-input view.virtual-input)
```

- [ ] **Step 2: Run the focused E2E validation.**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.e2e.test-fs-file-viewer-virtual-input:main
```

Expected: PASS.

---

### Task 5: Validation and Review Readiness

**Files:**
- Test: `assets/lua/lazy-text-buffer.fnl`
- Test: `assets/lua/virtual-input.fnl`
- Test: `assets/lua/text-state.fnl`
- Test: `assets/lua/tests/test-virtual-input.fnl`
- Test: `assets/lua/tests/e2e/test-fs-file-viewer-virtual-input.fnl`

**Interfaces:**
- Consumes: all code and tests from Tasks 1-4.
- Produces: validation evidence for review and integration.

- [ ] **Step 1: Run touched-file Fennel compile check.**

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/lazy-text-buffer.fnl --file assets/lua/virtual-input.fnl --file assets/lua/text-state.fnl --file assets/lua/tests/test-virtual-input.fnl --file assets/lua/tests/e2e/test-fs-file-viewer-virtual-input.fnl
```

Expected: PASS.

- [ ] **Step 2: Run constraints.**

```bash
rtk make constraints
```

Expected: PASS with `constraints: pass (0 diagnostics)`.

- [ ] **Step 3: Run focused unit tests.**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
```

Expected: PASS.

- [ ] **Step 4: Run focused expanded file-viewer E2E.**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.e2e.test-fs-file-viewer-virtual-input:main
```

Expected: PASS.

- [ ] **Step 5: Escalate to broader validation if reviewer requests it or implementation touches more than the planned files.**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Expected when run: PASS.

---

## Acceptance Criteria

- `VirtualInput` text navigation reads full logical lazy-buffer lines, not clipped viewport rows.
- `0`, `$`, `^`, `A`, and `I` operate on the full logical line when the line is horizontally clipped.
- `j` and `k` preserve logical column across long clipped lines.
- `gg`, `G`, PageUp, and PageDown use logical document lines and keep the caret visible.
- Insert, Backspace, Delete, and `x` update logical cursor state, clamp correctly, and keep the caret visible after horizontal or vertical viewport changes.
- `VirtualInput` disconnect normalizes mode to `:normal` like `InputModel`.
- Expanded graph file-viewer E2E covers focus, textnav non-insertion, insert routing, long-line navigation, line-edge navigation, caret visibility, and save routing through the real graph path.
- `Input`/`InputModel` tests remain green without intentional behavior changes.

## Explicitly Out of Scope

- Undo/redo.
- Word navigation (`w`, `b`, `e`), because current `TextState` does not implement those bindings.
- Multi-cursor editing.
- Syntax highlighting.
- Whole-file search/replace.
- Replacing `Input`/`InputModel`.
- Loading file-scale documents into a full in-memory model for navigation.
