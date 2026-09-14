# VirtualInput Shared Input Policies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `VirtualInput` reuse the working eager `Input` interaction, focus, caret, and geometry policies while preserving lazy file-backed rendering.

**Architecture:** Extract small policy modules from accepted eager `Input` behavior. `Input` continues to use materialized `InputModel`; `VirtualInput` adapts lazy `LazyTextBuffer` rows, byte anchors, and bounded movement into the same shared policies. Normal commands stay on `text-normal-commands`/`text-editing-port`.

**Tech Stack:** Space Fennel, `Input`, `InputModel`, `VirtualInput`, `LazyTextBuffer`, `TextState`, `InsertState`, `InputStateRouter`, existing widget/layout primitives, project-native Fennel validation.

## Global Constraints

- Eager `Input`/`InputModel` behavior is the compatibility oracle.
- `VirtualInput` must not materialize huge files; per-row lazy rendering, byte anchors, and bounded APIs remain storage-specific.
- Normal-mode command routing remains shared through `assets/lua/text-normal-commands.fnl` and `assets/lua/text-editing-port.fnl`.
- Do not add dependencies.
- Do not edit `assets/python/`.
- Do not add legacy option aliases or compatibility shims.
- Fennel style: use `local`, factory functions, multi-branch `if`, and explicit errors for missing required data.
- Use project-native validation only: `tools.fennel-check`, constraints, focused Fennel tests, `make test`, and E2E where required.

---

## File Structure

- Create `assets/lua/text-input-focus-policy.fnl`: shared focus/request/blur/disconnect lifecycle functions for Input-like widgets.
- Create `assets/lua/text-input-caret-policy.fnl`: shared caret visibility, color, width, line-height, column-width, and height decisions.
- Create `assets/lua/text-input-key-policy.fnl`: shared direct key handling policy for active-input shortcuts that are allowed outside the normal command engine.
- Create `assets/lua/text-input-geometry.fnl`: shared storage-neutral row/column/local-point geometry helpers.
- Modify `assets/lua/input.fnl`: consume focus and caret policies without changing eager behavior.
- Modify `assets/lua/virtual-input.fnl`: consume focus, caret, key, and geometry policies; keep lazy row rendering and byte resolution local.
- Modify `assets/lua/tests/test-input.fnl`: preserve/strengthen eager oracle tests after extraction.
- Modify `assets/lua/tests/test-virtual-input.fnl`: cover state-routed behavior and direct-key mode gating.
- Modify `assets/lua/tests/virtual-input-parity.fnl`: add file-backed lazy parity tests that force lazy paths.
- Modify `assets/lua/tests/e2e/test-fs-file-viewer-virtual-input.fnl`: add/maintain real pointer-routing coverage for file viewer VirtualInput.
- Create `docs/dev/features/text-input-policies.md`: document shared policies and lazy boundaries.

---

### Task 1: Shared Focus Lifecycle Policy

**Files:**
- Create: `assets/lua/text-input-focus-policy.fnl`
- Modify: `assets/lua/input.fnl`
- Modify: `assets/lua/virtual-input.fnl`
- Test: `assets/lua/tests/test-input.fnl`
- Test: `assets/lua/tests/test-virtual-input.fnl`
- Test: `assets/lua/tests/virtual-input-parity.fnl`

**Interfaces:**
- Consumes: widget fields `focus-node`, `focus-manager`, `focused?`, `connected?`, `enter-normal-mode`, `update-focus-visual`, `on-state-connected`, `on-state-disconnected`, plus existing `InputStateRouter`.
- Produces:
  - `FocusPolicy.request-focus(input) -> boolean`
  - `FocusPolicy.handle-focus(input) -> boolean`
  - `FocusPolicy.handle-blur(input) -> boolean`
  - `FocusPolicy.connect-focus-listeners(input) -> nil`
  - `FocusPolicy.disconnect-focus-listeners(input) -> nil`

- [ ] **Step 1: Write failing focus parity tests.**
  Add tests proving both widgets hide the caret when unfocused and that file-backed `VirtualInput` follows eager lifecycle semantics:

  ```fennel
  (fn virtual-input-file-backed-focus-lifecycle-matches-input []
    (with-virtual-input-states
      (fn [env]
        (local states (. env :states))
        (local buffer (lazy-buffer "focus-parity" "alpha\nbravo" {:chunk-bytes 4}))
        (local input (build-input {:buffer buffer :line-count 2 :column-count 8}))
        (narrow-layout! input 8 2)
        (assert (= input.focused? false) "VirtualInput should start unfocused like Input")
        (assert (= input.caret.visible? false) "unfocused VirtualInput caret should be hidden")
        (input:on-click {:row-index 1 :column 0})
        (input.layout:layouter)
        (assert (= (states:active-name) :text) "click should enter text state")
        (assert (= input.focused? true) "click/focus should mark VirtualInput focused")
        (assert input.caret.visible? "focused VirtualInput caret should be visible")
        (input:on-state-disconnected {:state :text})
        (input.layout:layouter)
        (assert (= input.focused? false) "disconnect should clear focused flag")
        (assert (= input.mode :normal) "disconnect should normalize mode")
        (assert (= input.caret.visible? false) "blurred VirtualInput caret should hide")
        (input:drop))))
  ```

- [ ] **Step 2: Run RED focused tests.**
  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  ```

  Expected before implementation: failure showing `VirtualInput` does not start or remain focus/caret-hidden like eager `Input`.

- [ ] **Step 3: Implement `text-input-focus-policy.fnl`.**
  Move the eager focus semantics into shared functions. The implementation shape is:

  ```fennel
  (local InputState (require :input-state-router))

  (fn set-focused [input focused?]
    (set input.focused? (not (not focused?)))
    (when input.update-focus-visual
      (input:update-focus-visual {:mark-layout-dirty? true})))

  (fn request-focus [input]
    (assert input "FocusPolicy.request-focus requires input")
    (when input.focus-node
      (input.focus-node:request-focus))
    true)
  ```

  The full module must expose the interface listed above and must connect/disconnect through `InputStateRouter` exactly once for the active input.

- [ ] **Step 4: Update `Input` to call the shared policy.**
  Replace local duplicate focus request/blur/listener functions with `FocusPolicy` calls. Keep existing public method names and behavior.

- [ ] **Step 5: Update `VirtualInput` to call the shared policy.**
  Add `focused? false` to the widget state. Ensure `request-focus` requests focus and the shared focus handler performs active-input connection/state transition. Ensure disconnect/blur hides caret and normalizes mode.

- [ ] **Step 6: Validate and commit.**
  Run touched-file `tools.fennel-check`, `make constraints`, focused `tests.test-input:main`, focused `tests.test-virtual-input:main`, then commit:

  ```bash
  git add assets/lua/text-input-focus-policy.fnl assets/lua/input.fnl assets/lua/virtual-input.fnl assets/lua/tests/test-input.fnl assets/lua/tests/test-virtual-input.fnl assets/lua/tests/virtual-input-parity.fnl
  git commit -m "refactor(ui): share text input focus policy"
  ```

---

### Task 2: Shared Caret Metrics and Visual Policy

**Files:**
- Create: `assets/lua/text-input-caret-policy.fnl`
- Modify: `assets/lua/input.fnl`
- Modify: `assets/lua/virtual-input.fnl`
- Test: `assets/lua/tests/test-input.fnl`
- Test: `assets/lua/tests/virtual-input-parity.fnl`

**Interfaces:**
- Consumes: `colors`, `mode`, `focused?`, `TextStyle`, `fallback-glyph`, `line-height`, `resolve-mark-flag`, current visible codepoint provider.
- Produces:
  - `CaretPolicy.resolve-line-height(text-style, fallback-height) -> number`
  - `CaretPolicy.resolve-column-width(text-style, caret-width) -> number`
  - `CaretPolicy.caret-color(colors, mode) -> glm.vec4`
  - `CaretPolicy.caret-visible?(input) -> boolean`
  - `CaretPolicy.mode-caret-width(text-style, codepoint, caret-width, mode) -> number`
  - `CaretPolicy.caret-height(line-height, inner-height) -> number`
  - `CaretPolicy.apply-caret-visual(input, opts) -> nil`

- [ ] **Step 1: Write failing caret parity tests.**
  Strengthen file-backed parity tests so `VirtualInput` and eager `Input` agree on hidden/unhidden caret, normal color/width, insert color/width, and normal-restored color/width over the same current glyph.

- [ ] **Step 2: Run RED focused tests.**
  Run `tests.test-virtual-input:main`. Expected before implementation: failures show caret policy remains local or focus-hidden semantics are incomplete.

- [ ] **Step 3: Extract eager caret decisions.**
  Move mode-to-color and mode-to-width logic from eager `Input` into `text-input-caret-policy.fnl`. The width helper must take a current codepoint so eager and virtual callers supply storage-specific lookup without materializing full files.

- [ ] **Step 4: Update `Input`.**
  Replace local `caret-width-for-mode`, line-height/column-width duplication where practical, and `update-caret-visual` decisions with `CaretPolicy`. Keep eager text wrapping and prefix-width geometry in `Input`.

- [ ] **Step 5: Update `VirtualInput`.**
  Use `CaretPolicy` for color, visibility, width, line-height, and column-width. Keep lazy row/current-codepoint lookup local and fail explicitly if required row/style data is missing.

- [ ] **Step 6: Validate and commit.**
  Run touched-file `tools.fennel-check`, `make constraints`, `tests.test-input:main`, `tests.test-virtual-input:main`, then commit:

  ```bash
  git add assets/lua/text-input-caret-policy.fnl assets/lua/input.fnl assets/lua/virtual-input.fnl assets/lua/tests/test-input.fnl assets/lua/tests/virtual-input-parity.fnl
  git commit -m "refactor(ui): share text input caret policy"
  ```

---

### Task 3: Shared Direct Key Policy and Mode-Gated Editing

**Files:**
- Create: `assets/lua/text-input-key-policy.fnl`
- Modify: `assets/lua/virtual-input.fnl`
- Test: `assets/lua/tests/test-virtual-input.fnl`
- Test: `assets/lua/tests/virtual-input-parity.fnl`

**Interfaces:**
- Consumes: `input.mode`, `input.save`, `input.copy-selection`, `input.scroll-lines`, `input.visible-line-count`, `input.multiline?`.
- Produces:
  - `KeyPolicy.handle-direct-key(input, payload) -> boolean`

- [ ] **Step 1: Write failing mode-gating tests.**
  Add tests proving direct `VirtualInput:on-key-down` in normal mode does not insert newlines, delete text, or move via raw arrow/edit branches. State-routed normal commands must still work through `TextState` and `text-normal-commands`.

  ```fennel
  (fn virtual-input-direct-normal-keys-do-not-edit []
    (local buffer (lazy-buffer "direct-normal-gate" "abc\ndef" {:chunk-bytes 4}))
    (local input (build-input {:buffer buffer :line-count 2 :column-count 8}))
    (narrow-layout! input 8 2)
    (local before (snapshot-text buffer))
    (assert (= (input:on-key-down {:key 8}) false) "direct backspace should not edit in normal mode")
    (assert (= (input:on-key-down {:key 127}) false) "direct delete should not edit in normal mode")
    (assert (= (input:on-key-down {:key 13}) false) "direct return should not insert newline in normal mode")
    (assert (= (snapshot-text buffer) before) "normal-mode direct keys should not mutate lazy text")
    (input:drop))
  ```

- [ ] **Step 2: Run RED focused tests.**
  Expected before implementation: direct normal-mode edit keys return handled or mutate because `VirtualInput:on-key-down` contains private edit branches.

- [ ] **Step 3: Implement `text-input-key-policy.fnl`.**
  Keep only direct shortcuts that are valid outside text normal commands: Ctrl+S, Ctrl+C, and PageUp/PageDown when intentionally supported. Do not put Backspace/Delete/Return/arrow character movement here; those belong to `InsertState` or `TextState`.

- [ ] **Step 4: Replace `VirtualInput:on-key-down`.**
  Remove private edit/navigation branches that bypass mode. `VirtualInput` keeps callable methods (`insert-text`, deletes, movement) for state and port users.

- [ ] **Step 5: Validate and commit.**
  Run touched-file `tools.fennel-check`, `make constraints`, `tests.test-virtual-input:main`, `tests.test-text-normal-commands:main`, `tests.test-text-editing-port:main`, then commit:

  ```bash
  git add assets/lua/text-input-key-policy.fnl assets/lua/virtual-input.fnl assets/lua/tests/test-virtual-input.fnl assets/lua/tests/virtual-input-parity.fnl
  git commit -m "refactor(ui): share text input key policy"
  ```

---

### Task 4: Shared Geometry Helpers and Lazy Parity Coverage

**Files:**
- Create: `assets/lua/text-input-geometry.fnl`
- Modify: `assets/lua/input.fnl`
- Modify: `assets/lua/virtual-input.fnl`
- Modify: `assets/lua/tests/virtual-input-parity.fnl`
- Modify: `assets/lua/tests/test-virtual-input.fnl`
- Modify: `assets/lua/tests/e2e/test-fs-file-viewer-virtual-input.fnl`

**Interfaces:**
- Consumes: widget `layout`, `padding`, `line-height`, `column-width`, `scroll-line`, `scroll-column`, visible rows.
- Produces:
  - `Geometry.local-point-from-event(input, event) -> glm.vec3`
  - `Geometry.row-y-offset(size, padding, line-height, visible-row) -> number`
  - `Geometry.row-index-for-point(input, local-point) -> integer`
  - `Geometry.column-for-x(column-width, local-x, row-length) -> integer`
  - `Geometry.screen-point-for-row-column(input, row, column) -> glm.vec3` for test/E2E helpers when useful.

- [ ] **Step 1: Write failing large-file geometry parity tests.**
  Use a file-backed `LazyTextBuffer` with tiny `chunk-bytes` and content containing a 100k-character line plus neighboring short lines. Assert click row/column mapping, caret y alignment with row widgets, row order, horizontal scroll after repeated `l`, and bounded scan counters.

- [ ] **Step 2: Run RED focused tests.**
  Expected before implementation: tests fail where geometry remains private or helper behavior differs between unit and E2E paths.

- [ ] **Step 3: Implement `text-input-geometry.fnl`.**
  Extract the storage-neutral math only. Keep lazy byte resolution in `VirtualInput`.

- [ ] **Step 4: Update `VirtualInput` and E2E helpers.**
  Use geometry helpers for row layout, caret y, click row mapping, and E2E screen-point synthesis. Keep `byte-for-column`, viewport-anchor lookup, and row refresh local to `VirtualInput`.

- [ ] **Step 5: Evaluate shadow model state.**
  If no code needs `VirtualInput.model.lines`, remove only the unused shadow projection. Keep public cache fields `cursor-index`, `cursor-line`, `cursor-column`, `scroll-line`, and `scroll-column` because tests and adapters use them.

- [ ] **Step 6: Validate and commit.**
  Run touched-file `tools.fennel-check`, `make constraints`, `tests.test-virtual-input:main`, focused E2E `tests.e2e.test-fs-file-viewer-virtual-input:main`, then commit:

  ```bash
  git add assets/lua/text-input-geometry.fnl assets/lua/input.fnl assets/lua/virtual-input.fnl assets/lua/tests/virtual-input-parity.fnl assets/lua/tests/test-virtual-input.fnl assets/lua/tests/e2e/test-fs-file-viewer-virtual-input.fnl
  git commit -m "refactor(ui): share text input geometry"
  ```

---

### Task 5: Documentation and Final Validation

**Files:**
- Create: `docs/dev/features/text-input-policies.md`
- Modify: `docs/dev/features/shared-text-interaction-engine.md`
- Modify: `docs/dev/features/lazy-text-buffer-virtual-input.md`

**Interfaces:**
- Consumes: shared policy module names and boundaries from Tasks 1-4.
- Produces: developer documentation for eager/virtual text input policy sharing.

- [ ] **Step 1: Document the oracle.**
  State that eager `Input`/`InputModel` define accepted interaction and caret behavior.

- [ ] **Step 2: Document shared policies.**
  List focus, caret, key, geometry, and normal-command responsibilities and the modules that own them.

- [ ] **Step 3: Document lazy boundaries.**
  State that VirtualInput owns file-backed storage, viewport rows, byte anchors, bounded movement APIs, selection, save, and per-row rendering.

- [ ] **Step 4: Document validation expectations.**
  Require file-backed lazy parity tests for future VirtualInput changes and forbid using eager full materialization for huge-file behavior.

- [ ] **Step 5: Validate and commit docs.**
  Run focused text searches for stale claims, touched-file `tools.fennel-check` if code changed in this task, `make constraints`, and docs diff review. Commit:

  ```bash
  git add docs/dev/features/text-input-policies.md docs/dev/features/shared-text-interaction-engine.md docs/dev/features/lazy-text-buffer-virtual-input.md
  git commit -m "docs(ui): document text input policies"
  ```

---

## Final Acceptance Criteria

- `VirtualInput` caret visibility is gated by `focused?` and matches eager `Input`.
- `VirtualInput` caret color and normal/insert width are computed through shared policy and match eager `Input`.
- `VirtualInput` no longer performs private direct edit/navigation key handling that bypasses mode.
- Normal-mode commands route through `text-normal-commands`/`text-editing-port`; insert edits route through `InsertState`.
- File-backed lazy tests prove large inputs stay bounded and do not require full-file materialization.
- Real pointer-routing E2E proves screen coordinates target the intended file-backed VirtualInput row/column.
- Documentation explains the shared policy boundary and lazy storage boundary.

## Final Validation Scope

Run these after all tasks pass review and are committed:

```bash
make build
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-input:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-input-model:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-text-normal-commands:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-text-editing-port:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test-e2e
```

If any validation fails, invoke systematic debugging, establish root cause, route the fix through implementer and reviewer, then rerun validation from a clean current-base tree.
