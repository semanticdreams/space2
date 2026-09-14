# Shared Text Interaction Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor Space Fennel text interaction so `Input` and `VirtualInput` share one normal-mode command engine over an explicit text-editing port, with lowercase `w` as the proving command.

**Architecture:** Introduce `text-editing-port.fnl` as the only storage-aware adapter layer and `text-normal-commands.fnl` as the shared normal-mode command engine. `TextState` becomes a routing shell for active input, submit handling, command hints, mode sync, and control fallback; it delegates normal-mode commands to the command engine. Lazy word motion for `VirtualInput` is implemented through `VirtualInput`/`LazyTextBuffer` streaming primitives without materializing whole files, whole lines, eager `InputModel`s, or accumulated prefixes.

**Tech Stack:** Space Fennel modules under `assets/lua`, Space-native Fennel validation through `./build/space`, Fennel test runner modules under `assets/lua/tests`, `LazyTextBuffer` piece-table storage, `InputModel` eager storage.

## Global Constraints

- Existing `Input` widget and `InputModel` behavior are the compatibility oracle for current commands.
- When `Input` and `VirtualInput` disagree, the default assumption is that `VirtualInput` should be corrected to match `Input`, unless a file-scale difference is explicitly documented in the spec or developer docs.
- New commands should be implemented once against a port, not separately per storage backend.
- Create `assets/lua/text-editing-port.fnl` and `assets/lua/text-normal-commands.fnl`.
- `TextState` should become a routing shell with no backend-specific navigation branching for normal-mode commands.
- `VirtualInput` and `LazyTextBuffer` remain lazy.
- Lowercase `w` for `VirtualInput` may stream chunks until next word or EOF but must not build a whole-file string, whole-line string, eager `InputModel`, or accumulated prefix string.
- Proving command `w` semantics: no counts/operators/visual mode; forward only.
- Whitespace codepoints: `9`, `10`, `11`, `12`, `13`, and `32`.
- Keyword codepoints: ASCII `A-Z`, `a-z`, `0-9`, and `_`.
- Punctuation: any other non-whitespace codepoint.
- From a non-whitespace run, skip the current run, then skip whitespace, then land on the next non-whitespace run.
- From whitespace, skip whitespace and land on the next non-whitespace run.
- If no next word exists, do not move.
- Missing required port operations must raise explicit errors naming the missing operation and input kind.
- Use `local` instead of `let` in Fennel.
- Use Space-native validation only: `make fennel-check`, `make constraints`, focused Fennel tests, and broader `make test` because central command routing changes.
- Out of scope: counts such as `3w`; operators such as `dw`, `cw`, `d$`; operator-pending mode; visual mode or selected-text manipulation; text objects; repeat command `.`; search; marks and jumps; Unicode or configurable Vim `iskeyword` semantics; replacing `InputModel` storage with `LazyTextBuffer`; broad rewrite of `InsertState` beyond compatibility adjustments needed for the port.
- Implementers do not commit inside tasks. The supervisor commits only after implementer → reviewer → pass.

---

## File Structure

- Create `assets/lua/text-editing-port.fnl`: backend-neutral text-editing adapter. This is the only new module allowed to inspect eager `Input`/`InputModel` shape or lazy `VirtualInput`/`LazyTextBuffer` shape.
- Create `assets/lua/text-normal-commands.fnl`: shared normal-mode command definitions, key resolution, prefix state, command hints, and command dispatch. This module must call only `text-editing-port` methods and must not inspect storage internals.
- Create `assets/lua/tests/test-text-editing-port.fnl`: focused port protocol tests for eager and virtual-style inputs, including explicit missing-operation errors.
- Create `assets/lua/tests/test-text-normal-commands.fnl`: focused command-engine tests, including preserved command behavior and lowercase `w` proving cases.
- Modify `assets/lua/text-state.fnl`: remove command implementations and backend navigation helpers; route normal-mode key handling and command hints through `text-normal-commands`.
- Modify `assets/lua/lazy-text-buffer.fnl`: add streaming word-start scan primitive used by lazy ports.
- Modify `assets/lua/virtual-input.fnl`: expose lazy `move-next-word-start` widget method that updates cached byte/line/column state and viewport anchors.
- Modify `assets/lua/tests/fast.fnl`: register `:tests.test-text-editing-port` and `:tests.test-text-normal-commands`.
- Modify existing focused tests as needed: `assets/lua/tests/test-states.fnl`, `assets/lua/tests/test-input.fnl`, `assets/lua/tests/test-virtual-input.fnl`, and `assets/lua/tests/test-lazy-text-buffer.fnl`.
- Create `docs/dev/features/shared-text-interaction-engine.md`: canonical developer documentation for the port, command engine, compatibility oracle, and `w` semantics.
- Modify `docs/dev/features/lazy-text-buffer-virtual-input.md`: link to the shared text interaction engine page and update outdated wording that says `VirtualInput` exposes only a small `TextState` facade.

## Observable Acceptance Criteria

- `assets/lua/text-editing-port.fnl` exists and is the only new module responsible for backend detection and storage-specific command primitives.
- `assets/lua/text-normal-commands.fnl` exists and contains shared normal-mode command definitions.
- `assets/lua/text-state.fnl` no longer contains backend-specific navigation helpers or normal-mode command implementations.
- Current accepted `Input`/`InputModel` normal-mode behavior remains green in focused tests.
- `VirtualInput` shared command behavior matches `Input` for migrated commands unless a file-scale difference is documented.
- Lowercase `w` works through the shared command path for eager `Input` and lazy `VirtualInput`.
- Lazy `w` streams through chunks and tests fail if it materializes whole files, huge lines, eager `InputModel`s, or accumulated prefixes.
- Developer documentation exists at `docs/dev/features/shared-text-interaction-engine.md`.

## Validation Ladder

1. Runtime/freshness prerequisite: if `./build/space` may be missing or stale, run `make build` with timeout `14400000`.
2. Focused during implementation: run touched-file `tools.fennel-check` first for edited `.fnl` files.
3. Constraints: run `make constraints` second.
4. Focused tests: run the task-specific `./build/space -m tests.<module>:main` commands listed in each task third.
5. Complete relevant local suite: run `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test` after docs/final validation because command routing is central behavior.
6. Full integration gate: PR CI is the full integration gate. Do not claim ready-to-merge until PR CI is green.

---

### Task 1: Text Editing Port Protocol

**Files:**
- Create: `assets/lua/text-editing-port.fnl`
- Create: `assets/lua/tests/test-text-editing-port.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: existing `InputModel`-style objects with `model`, `lines`, `codepoints`, `move-caret`, `move-caret-to`, `insert-text`, `delete-at-cursor`, `enter-insert-mode`, `enter-normal-mode`, and `submit`; existing `VirtualInput`-style objects with logical methods such as `text-line-count`, `text-line-length`, `text-line-first-nonblank`, `text-cursor-line-column`, `move-caret-to-line-column`, bounded movement methods, editing methods, and mode methods.
- Produces: `TextEditingPort.from-input(input: table) -> port: table`.
- Produces port methods: `line-count`, `line-length`, `line-first-nonblank`, `cursor-line-column`, `move-to-line-column`, `move-horizontal`, `move-vertical`, `move-to-line-edge`, `move-to-first-nonblank`, `move-to-first-line`, `move-to-last-line`, `clamp-caret-to-current-line`, `insert-text`, `delete-at-cursor`, `enter-insert-mode`, `enter-normal-mode`, `submit`, and `move-next-word-start`.

- [ ] **Step 1: Add RED tests for eager input behavior.** In `assets/lua/tests/test-text-editing-port.fnl`, create an eager fake or real `InputModel`-backed input and assert: line count, line length, first nonblank, cursor line/column, line-edge moves, first/last-line moves, vertical preferred-column behavior, and delete clamps match existing `Input` behavior.
- [ ] **Step 2: Add RED tests for virtual-style logical behavior.** In the same test module, use a stub input implementing `text-line-count`, `text-line-length`, `text-line-first-nonblank`, `text-cursor-line-column`, `move-caret-to-line-column`, `move-caret-horizontal-bounded`, `move-caret-vertical-bounded`, editing methods, and mode methods. Assert the port calls the logical/bounded methods rather than reading eager model fields.
- [ ] **Step 3: Add RED tests for explicit missing-operation errors.** Assert missing required methods raise errors containing both `text-editing-port missing` and the missing operation name, such as `line-count`, `move-horizontal`, or `insert-text`.
- [ ] **Step 4: Register the RED test module in `assets/lua/tests/fast.fnl`.** Insert `:tests.test-text-editing-port` near existing text/input modules around `:tests.test-input-model`, `:tests.test-lazy-text-buffer`, `:tests.test-virtual-input`, and `:tests.test-input`.
- [ ] **Step 5: Run the RED focused test.**
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-text-editing-port:main
  ```
  Expected: fail because `text-editing-port` does not exist.
- [ ] **Step 6: Implement `assets/lua/text-editing-port.fnl`.** Move current eager/logical navigation logic out of `text-state.fnl` into this adapter module without changing behavior. Keep helper functions private, including whitespace detection, line-start index calculation, line length clamping, preferred-column storage on the input object, and backend detection.
- [ ] **Step 7: Implement explicit operation checks.** Add a helper that raises errors shaped like `text-editing-port missing <operation> for <kind>`, where `<kind>` is `:input-model`, `:input`, `:virtual-input`, or `:unknown`.
- [ ] **Step 8: Keep virtual bounded navigation lazy.** For `VirtualInput`-style objects, route ordinary `move-horizontal` and `move-vertical` through existing bounded methods when available, and return `false` for unsupported bounded movement instead of silently reporting success.
- [ ] **Step 9: Keep `move-next-word-start` unsupported until Task 3.** The method must raise an explicit unsupported error containing `text-editing-port missing move-next-word-start`. Do not return `false` for this method until Task 3 implements real `w` behavior.
- [ ] **Step 10: Run touched-file compile check first.**
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --output summary --target files --file assets/lua/text-editing-port.fnl --file assets/lua/tests/test-text-editing-port.fnl --file assets/lua/tests/fast.fnl
  ```
- [ ] **Step 11: Run constraints second.**
  ```bash
  make constraints
  ```
- [ ] **Step 12: Run focused port tests third.**
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-text-editing-port:main
  ```

---

### Task 2: Shared Normal-Mode Command Engine and TextState Routing Shell

**Files:**
- Create: `assets/lua/text-normal-commands.fnl`
- Create: `assets/lua/tests/test-text-normal-commands.fnl`
- Modify: `assets/lua/text-state.fnl`
- Modify: `assets/lua/tests/test-states.fnl`
- Modify: `assets/lua/tests/test-input.fnl`
- Modify: `assets/lua/tests/test-virtual-input.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `TextEditingPort.from-input(input) -> port` from Task 1.
- Produces: `TextNormalCommands.make-state() -> command-state: table`.
- Produces: `TextNormalCommands.handle-key(ctx: table, command-state: table, input: table, payload: table) -> boolean`.
- Produces: `TextNormalCommands.command-hint-entries(command-state: table, payload: table) -> entries: table, prefix-meta: table|nil`.
- Produces: `TextNormalCommands.sync-mode(input: table) -> boolean`.
- Maintains: existing command keys `i`, `a`, `A`, `I`, `o`, `O`, `g g`, `G`, `h`, `j`, `k`, `l`, `0`, `$`, `^`, `x`, left-arrow, and right-arrow.

- [ ] **Step 1: Add RED command-engine tests.** In `assets/lua/tests/test-text-normal-commands.fnl`, cover existing accepted behavior through the new module API: `i`, `a`, `A`, `I`, `o`, `O`, `h/l/j/k`, arrows, `0`, `$`, `^`, `x`, `g g`, `G`, prefix cancellation/fallback, and command hints.
- [ ] **Step 2: Register the RED command test module.** Add `:tests.test-text-normal-commands` to `assets/lua/tests/fast.fnl` near `:tests.test-text-editing-port`.
- [ ] **Step 3: Run the RED focused command-engine test.**
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-text-normal-commands:main
  ```
  Expected: fail because `text-normal-commands` does not exist.
- [ ] **Step 4: Implement `assets/lua/text-normal-commands.fnl`.** Move normal-mode command definitions, shifted key resolution, keymap construction, prefix handling, binding application, command hint entries, and mode sync out of `text-state.fnl`. All handlers must create a port with `TextEditingPort.from-input(input)` and call port methods only.
- [ ] **Step 5: Preserve command hint labels and priorities.** Keep existing labels and relative priorities: `i` `insert` priority `10`, `a` `append-after` priority `11`, `A` `append-line-end` priority `12`, `I` `insert-line-start` priority `13`, `o` `open-below` priority `14`, `O` `open-above` priority `15`, `g` `goto` priority `20`, `G` `last-line` priority `21`, `h/l/j/k` priorities `30` through `33`, `0` `line-start` priority `40`, `$` `line-end` priority `41`, `^` `first-nonblank` priority `42`, `x` `delete-char` priority `50`, and `g g` prefix title `GOTO` with `first-line` and `esc cancel-prefix`.
- [ ] **Step 6: Refactor `assets/lua/text-state.fnl` into a routing shell.** Keep state routing, active input lookup, submit handling, F1/control fallback, command hint provider wiring, and mode synchronization. Remove backend-specific helpers and command handlers from `text-state.fnl`.
- [ ] **Step 7: Keep submit behavior unchanged.** `Ctrl+Enter` in `TextState` must still call active input `submit(payload)`, mark the command executed, and return `true`.
- [ ] **Step 8: Preserve existing `TextState` tests as compatibility tests.** Update test helpers only where needed to satisfy the port protocol, not to weaken assertions. Existing tests in `test-states.fnl`, `test-input.fnl`, and `test-virtual-input.fnl` must continue to assert accepted behavior.
- [ ] **Step 9: Prove command engine does not inspect backend internals.**
  ```bash
  rg "input\.model|LazyTextBuffer|bounded-logical-navigation|text-line-count|text-line-length|move-caret-horizontal-bounded|move-caret-vertical-bounded" assets/lua/text-normal-commands.fnl assets/lua/text-state.fnl
  ```
  Expected: no matches.
- [ ] **Step 10: Run touched-file compile check first.**
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --output summary --target files --file assets/lua/text-normal-commands.fnl --file assets/lua/text-state.fnl --file assets/lua/tests/test-text-normal-commands.fnl --file assets/lua/tests/test-states.fnl --file assets/lua/tests/test-input.fnl --file assets/lua/tests/test-virtual-input.fnl --file assets/lua/tests/fast.fnl
  ```
- [ ] **Step 11: Run constraints second.**
  ```bash
  make constraints
  ```
- [ ] **Step 12: Run focused tests third.**
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-text-normal-commands:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-states:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-input:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  ```

---

### Task 3: Lowercase `w` Word Motion Proving Case

**Files:**
- Modify: `assets/lua/text-editing-port.fnl`
- Modify: `assets/lua/text-normal-commands.fnl`
- Modify: `assets/lua/lazy-text-buffer.fnl`
- Modify: `assets/lua/virtual-input.fnl`
- Modify: `assets/lua/tests/test-text-editing-port.fnl`
- Modify: `assets/lua/tests/test-text-normal-commands.fnl`
- Modify: `assets/lua/tests/test-lazy-text-buffer.fnl`
- Modify: `assets/lua/tests/test-virtual-input.fnl`

**Interfaces:**
- Consumes: `TextEditingPort.from-input(input) -> port` and `TextNormalCommands.handle-key(ctx, command-state, input, payload) -> boolean` from Tasks 1 and 2.
- Produces: working `port:move-next-word-start(opts?: table) -> boolean`.
- Produces: `LazyTextBuffer:next-word-start-from-anchor(anchor: {byte: integer, line: integer, column: integer}, opts?: table) -> result: {bounded?: boolean, moved?: boolean, byte: integer, line: integer, column: integer}|false`.
- Produces: `VirtualInput:move-next-word-start(opts?: table) -> boolean`.

- [ ] **Step 1: Add RED eager command tests for lowercase `w`.** In `assets/lua/tests/test-text-normal-commands.fnl`, include these exact scenarios: `"alpha beta"` cursor `0` lands at column `6`; `"alpha  beta"` cursor at column `5` lands at column `7`; `"foo.bar baz"` cursor `0` first `w` lands at column `3`, second at column `4`, third at column `8`; `"alpha\nbeta"` cursor `0` lands on line `1`, column `0`; `"alpha"` cursor `0` returns `false` and cursor remains line `0`, column `0`.
- [ ] **Step 2: Add RED port parity tests.** In `assets/lua/tests/test-text-editing-port.fnl`, run the same text/cursor/expected-position table against an eager `InputModel`-backed input and a virtual-style input that implements `move-next-word-start`.
- [ ] **Step 3: Add RED lazy streaming tests.** In `assets/lua/tests/test-lazy-text-buffer.fnl`, add a file containing `(string.rep "a" 100000) .. " next"`, `chunk-bytes 16`, and existing `call-with-large-concat-disabled 4096`. Assert `buffer:next-word-start-from-anchor {:byte 0 :line 0 :column 0}` returns `moved? true`, returned column is `100001`, source `max-requested <= 16`, and no `table.concat` call materializes more than `4096` bytes.
- [ ] **Step 4: Add RED VirtualInput tests.** In `assets/lua/tests/test-virtual-input.fnl`, cover `w` through `TextState` for real `VirtualInput` over `LazyTextBuffer`: within word, from whitespace, punctuation boundaries, across newline, EOF/no next word no-move, and a huge-line case proving no full logical scans or prefix materialization using existing lazy instrumentation helpers.
- [ ] **Step 5: Run RED focused tests.**
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-text-normal-commands:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-lazy-text-buffer:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  ```
  Expected: fail because `w` is not implemented.
- [ ] **Step 6: Implement word classification once in `text-editing-port.fnl`.** Use exactly the codepoint classes from Global Constraints.
- [ ] **Step 7: Implement eager `port:move-next-word-start`.** Scan `InputModel` codepoints/line metadata without changing storage, compute the target line/column, and call `move-to-line-column` only when a next word exists.
- [ ] **Step 8: Implement `LazyTextBuffer:next-word-start-from-anchor`.** Stream forward from the supplied anchor using existing chunked composed-read helpers. Maintain only scalar scan state: byte, line, column, current class, and phase. Do not build a whole-file string, whole-line string, eager `InputModel`, or accumulated prefix string.
- [ ] **Step 9: Implement `VirtualInput:move-next-word-start`.** Call `buffer:next-word-start-from-anchor` from the current cursor anchor. On `moved? true`, update cached caret byte/line/column, clear or update selection consistently with other non-selection movement, keep caret visible, refresh anchors/viewport, and return `true`. On no next word, leave all cursor state unchanged and return `false`.
- [ ] **Step 10: Bind lowercase `w` in `text-normal-commands.fnl`.** Add key `w` only. Do not add `W`, counts, operators, visual mode behavior, or repeat support. Add a root command hint label `next-word` with priority `34`.
- [ ] **Step 11: Prove command engine remains storage-neutral.**
  ```bash
  rg "input\.model|LazyTextBuffer|next-word-start-from-anchor|buffer" assets/lua/text-normal-commands.fnl
  ```
  Expected: no output.
- [ ] **Step 12: Run touched-file compile check first.**
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --output summary --target files --file assets/lua/text-editing-port.fnl --file assets/lua/text-normal-commands.fnl --file assets/lua/lazy-text-buffer.fnl --file assets/lua/virtual-input.fnl --file assets/lua/tests/test-text-editing-port.fnl --file assets/lua/tests/test-text-normal-commands.fnl --file assets/lua/tests/test-lazy-text-buffer.fnl --file assets/lua/tests/test-virtual-input.fnl
  ```
- [ ] **Step 13: Run constraints second.**
  ```bash
  make constraints
  ```
- [ ] **Step 14: Run focused tests third.**
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-text-editing-port:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-text-normal-commands:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-lazy-text-buffer:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  ```

---

### Task 4: Developer Documentation and Final Validation

**Files:**
- Create: `docs/dev/features/shared-text-interaction-engine.md`
- Modify: `docs/dev/features/lazy-text-buffer-virtual-input.md`
- Modify: `docs/specs/2026-09-14-shared-text-interaction-engine-design.md` only if implementation reveals a documented file-scale behavior difference from the spec.

**Interfaces:**
- Consumes: final public behavior from Tasks 1-3.
- Produces: developer documentation describing the shared text-editing port, normal command engine, `Input` compatibility oracle, lazy backend constraints, and lowercase `w` semantics.

- [ ] **Step 1: Create `docs/dev/features/shared-text-interaction-engine.md`.** Include sections named `# Shared Text Interaction Engine`, `## Compatibility oracle`, `## Text-editing port`, `## Normal-mode command engine`, `## Lowercase w word motion`, `## Lazy backend invariants`, and `## Testing expectations`.
- [ ] **Step 2: Document exact `w` semantics.** Copy the codepoint classes and movement rules from Global Constraints into the docs page, including the no-counts/no-operators/no-visual-mode limits.
- [ ] **Step 3: Document the architecture invariant.** State that `text-normal-commands.fnl` must not inspect `input.model`, `input.lines`, `VirtualInput` anchor caches, or `LazyTextBuffer` internals directly; storage-specific behavior belongs in `text-editing-port.fnl`, `virtual-input.fnl`, and `lazy-text-buffer.fnl`.
- [ ] **Step 4: Update `docs/dev/features/lazy-text-buffer-virtual-input.md`.** Replace wording that describes `VirtualInput` as only a small `TextState` compatibility facade with wording that says it participates in the shared text interaction engine through the text-editing port, while preserving lazy viewport and file-scale invariants. Add a link to `docs/dev/features/shared-text-interaction-engine.md`.
- [ ] **Step 5: Run documentation and architecture text checks.**
  ```bash
  rg "Shared Text Interaction Engine|Text-editing port|Lowercase w word motion|InputModel behavior" docs/dev/features/shared-text-interaction-engine.md docs/dev/features/lazy-text-buffer-virtual-input.md
  rg "input\.model|LazyTextBuffer|bounded-logical-navigation|text-line-count|move-caret-horizontal-bounded" assets/lua/text-normal-commands.fnl assets/lua/text-state.fnl
  ```
  Expected: first command finds the documented sections; second command has no output.
- [ ] **Step 6: Run `make build` as runtime/freshness prerequisite if `./build/space` may be missing or stale.** Use timeout `14400000`.
  ```bash
  make build
  ```
- [ ] **Step 7: Run broad Fennel compile check first.**
  ```bash
  make fennel-check
  ```
- [ ] **Step 8: Run constraints second.**
  ```bash
  make constraints
  ```
- [ ] **Step 9: Run focused tests third.**
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-text-editing-port:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-text-normal-commands:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-states:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-input:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-input-model:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-lazy-text-buffer:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  ```
- [ ] **Step 10: Run the complete relevant local suite.**
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```
- [ ] **Step 11: Verify acceptance criteria manually from the final diff.** Confirm `TextState` has no backend-specific navigation branching for normal-mode commands, `text-normal-commands.fnl` implements commands through `text-editing-port` only, existing accepted `Input` tests still pass, existing `VirtualInput` command behavior still matches shared `Input` behavior where shared, lowercase `w` works for both eager and lazy inputs, lazy `w` tests prove no whole-file/line/eager-model/prefix materialization, and developer docs explain the port/engine/oracle/`w` semantics.
