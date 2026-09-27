# Hosted Command History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a bounded, session-local command run history to hosted workspace command controls.

**Architecture:** Add a pure `app-host.command-run-history` model for bounded entries, text summaries, timestamps, and trimming. Integrate it in `workspace-command-controls.fnl` because controls own the full user-facing lifecycle: confirmation, payload construction, sync/async dispatch, progress, cancellation, structural failures, and drop cleanup.

**Tech Stack:** Space Fennel, app-host command controls, `WrappedText`, existing `app-host.command-result-model.value-text`, Space Fennel tests, `tools.fennel-check`, constraints.

## Global Constraints

- Session-local/in-memory only.
- Bounded recent history, no persistence, no queues, no polling, no auth/permissions.
- Actual execution attempts only: confirmation first-clicks do not create history entries.
- Payload validation/structural invocation failures should create local failed entries only if they happen after execution click.
- Drop/close lifecycle cleanup should not create user-visible terminal history entries.
- Should work for sync and async commands; async progress may update active history row but not append every progress event as a separate row.
- Default history limit: 10 recent entries per controls widget; order is newest first.
- Run IDs are controls-local monotonically increasing integers; timestamps are `os.time()` seconds via injectable `:now` for deterministic tests.
- Store only bounded text summaries for payloads/results/errors/progress using existing deterministic value rendering; do not retain raw payload/result tables in history entries.
- Preserve existing latest-result behavior, button busy/cancel behavior, confirmation behavior, active-run-token stale-callback protection, and drop cleanup semantics.
- Documentation must update existing canonical page `docs/dev/features/hosted-runtime-apps.md`; no new docs/dev page is needed because this page already owns hosted workspace command behavior and deferred scope.
- Out of scope: persistence, global/cross-session logs, command queues, polling, background jobs, auth/permissions, durable pending handles, export/download, filtering/searching, and app-specific log APIs.
- Widget constructors return build closures.
- Builders receive renderer/build context and instantiate children with that context.
- Composite widgets own and drop their direct child widgets.
- Assert on missing required context instead of silently falling back.
- Use `local` instead of `let` in Fennel.
- Use factory functions instead of constructors (`.new`).
- Use project-native Fennel validation only: `make fennel-check` or touched-file `tools.fennel-check`, then `make constraints`, then focused Fennel tests.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.
- For direct test runs, set `SKIP_KEYRING_TESTS=1`, `XDG_DATA_HOME=/tmp/space/tests/xdg-data`, `SPACE_DISABLE_AUDIO=1`, `SPACE_ASSETS_PATH=$(pwd)/assets`, `FENNEL_PATH=$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl`, and the same value for `FENNEL_MACRO_PATH`.

---

## File Structure

- Create `assets/lua/app-host/command-run-history.fnl`: pure bounded history model. It owns run ids, timestamps, summaries, trimming, and display text. It must not require widgets or descriptors.
- Create `assets/lua/tests/test-app-host-command-run-history.fnl`: focused model tests for ordering, trimming, progress updates, terminal statuses, and no raw object retention.
- Modify `assets/lua/tests/fast.fnl`: register the new focused history model test.
- Modify `assets/lua/app-host/workspace-command-controls.fnl`: construct/run the history model, add one recent-runs `WrappedText`, and update entries through sync/async lifecycle hooks.
- Modify `assets/lua/tests/test-app-host-workspace-command-controls.fnl`: cover history integration for confirmation, payload errors, sync/async results, cancellation, drop, and trimming.
- Modify `docs/dev/features/hosted-runtime-apps.md`: document command history behavior and non-goals.

---

### Task 1: Command Run History Model

**Files:**
- Create: `assets/lua/app-host/command-run-history.fnl`
- Create: `assets/lua/tests/test-app-host-command-run-history.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `ResultModel.value-text(value) -> string|nil` from `app-host.command-result-model`.
- Produces:
  - `History.create(opts table|nil) -> history`
  - `History.start-run!(history table, command table) -> entry table`
  - `History.set-payload!(history table, run-id any, payload any) -> entry|nil`
  - `History.progress!(history table, run-id any, command table, progress table) -> entry|nil`
  - `History.finish!(history table, run-id any, command table, result table) -> entry|nil`
  - `History.fail!(history table, run-id any, command table, err any) -> entry|nil`
  - `History.entries(history table) -> sequential table`
  - `History.entry-text(entry table) -> string`
  - `History.list-text(history table) -> string`

- [ ] **Step 1: Add failing history model tests**

Create `assets/lua/tests/test-app-host-command-run-history.fnl` using the normal runner pattern:

```fennel
(local Runner (require :tests/runner))
(local History (require :app-host.command-run-history))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn make-clock []
  (local state {:now 100})
  {:state state
   :now (fn []
          (set state.now (+ state.now 1))
          state.now)})

(fn test-empty-history-text []
  (local history (History.create {:now (fn [] 1)}))
  (assert (= (History.list-text history) "Recent runs\nNo command runs yet"))
  (assert (= (# (History.entries history)) 0)))

(fn test-start-run-ids-and-timestamps []
  (local clock (make-clock))
  (local history (History.create {:now clock.now}))
  (local first (History.start-run! history {:id :save :title "Save"}))
  (local second (History.start-run! history {:id :reset :title "Reset"}))
  (assert (= first.run-id 1))
  (assert (= first.started-at 101))
  (assert (= first.updated-at 101))
  (assert (= second.run-id 2))
  (assert (= (. (History.entries history) 1 :command-id) :reset))
  (assert (= (. (History.entries history) 2 :command-id) :save)))

(fn test-limit-trims_oldest []
  (local clock (make-clock))
  (local history (History.create {:limit 2 :now clock.now}))
  (History.start-run! history {:id :one :title "One"})
  (History.start-run! history {:id :two :title "Two"})
  (History.start-run! history {:id :three :title "Three"})
  (local entries (History.entries history))
  (assert (= (# entries) 2))
  (assert (= (. entries 1 :command-id) :three))
  (assert (= (. entries 2 :command-id) :two))
  (assert (= (History.finish! history 1 {:id :one :title "One"} {:id :one :status :ok :value true}) nil)))

(fn test-progress-updates_existing_entry []
  (local clock (make-clock))
  (local history (History.create {:now clock.now}))
  (local entry (History.start-run! history {:id :export :title "Export"}))
  (History.progress! history entry.run-id {:id :export :title "Export"} {:message "halfway" :value 0.5})
  (local entries (History.entries history))
  (assert (= (# entries) 1))
  (assert (= (. entries 1 :status) :running))
  (assert (= (. entries 1 :progress-text) "halfway"))
  (assert (= (. entries 1 :progress-value) 0.5)))

(fn test-finish-statuses_and_text []
  (local clock (make-clock))
  (local history (History.create {:now clock.now}))
  (local ok (History.start-run! history {:id :ok :title "OK"}))
  (History.set-payload! history ok.run-id {:slot 1})
  (History.finish! history ok.run-id {:id :ok :title "OK"} {:id :ok :status :ok :value {:saved true}})
  (local err (History.start-run! history {:id :err :title "Err"}))
  (History.finish! history err.run-id {:id :err :title "Err"} {:id :err :status :error :error "boom"})
  (local cancelled (History.start-run! history {:id :cancel :title "Cancel"}))
  (History.finish! history cancelled.run-id {:id :cancel :title "Cancel"} {:id :cancel :status :cancelled :error "user cancelled"})
  (local unknown (History.start-run! history {:id :wait :title "Wait"}))
  (History.finish! history unknown.run-id {:id :wait :title "Wait"} {:id :wait :status :queued})
  (local text (History.list-text history))
  (assert (string.find text "OK" 1 true))
  (assert (string.find text "saved" 1 true))
  (assert (string.find text "boom" 1 true))
  (assert (string.find text "cancelled" 1 true))
  (assert (string.find text "queued" 1 true)))

(fn test-fail-and-no-raw-objects []
  (local history (History.create {:now (fn [] 10)}))
  (local entry (History.start-run! history {:id :bad :title "Bad"}))
  (History.set-payload! history entry.run-id {:large (string.rep "x" 700)})
  (History.fail! history entry.run-id {:id :bad :title "Bad"} "number field count is required")
  (local stored (. (History.entries history) 1))
  (assert (= stored.status :error))
  (assert (string.find stored.error-text "number field" 1 true))
  (assert (= stored.payload nil))
  (assert (= stored.result nil))
  (assert (= stored.command nil))
  (assert (<= (# stored.payload-text) 500)))

(add-test "empty history text" test-empty-history-text)
(add-test "start run ids and timestamps" test-start-run-ids-and-timestamps)
(add-test "limit trims oldest" test-limit-trims_oldest)
(add-test "progress updates existing entry" test-progress-updates_existing_entry)
(add-test "finish statuses and text" test-finish-statuses_and_text)
(add-test "fail and no raw objects" test-fail-and-no-raw-objects)

(fn main []
  (Runner.run-tests {:name "app-host-command-run-history" :tests tests}))

{:main main :tests tests}
```

- [ ] **Step 2: Run the focused history test and verify it fails because the module is missing**

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-run-history:main
```

Expected: FAIL with missing `app-host.command-run-history`.

- [ ] **Step 3: Implement `command-run-history.fnl`**

Implementation requirements:

- Require `app-host.command-result-model` as `ResultModel`.
- Use `ResultModel.value-text` for payload/result values.
- Convert errors/statuses with `tostring`, then pass through `ResultModel.value-text` when useful for bounding.
- Insert entries at index `1` and trim tail while over limit.
- Maintain `history.by-id` and remove evicted ids from lookup.
- Default limit is `10`; if `opts.limit` is missing, non-number, or less than `1`, use `10`.
- Default `now` is `(fn [] (os.time))`.
- `entries` returns `history.entries` for test inspection; callers must not mutate it.
- `finish!` maps statuses exactly: `:ok`, `:error`, `:cancelled`, otherwise `:unknown` with `result-status-text` containing the original status text.
- `list-text` always starts with `Recent runs`.

- [ ] **Step 4: Register the test in `assets/lua/tests/fast.fnl`**

Add `:tests.test-app-host-command-run-history` near other app-host or status/widget tests. Do not remove existing modules.

- [ ] **Step 5: Validate Task 1**

Run:

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/command-run-history.fnl --file assets/lua/tests/test-app-host-command-run-history.fnl --file assets/lua/tests/fast.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-run-history:main
```

- [ ] **Step 6: Commit Task 1**

```bash
git add assets/lua/app-host/command-run-history.fnl assets/lua/tests/test-app-host-command-run-history.fnl assets/lua/tests/fast.fnl
git commit -m "feat(lua): add hosted command run history"
```

---

### Task 2: Workspace Command Controls History Integration

**Files:**
- Modify: `assets/lua/app-host/workspace-command-controls.fnl`
- Modify: `assets/lua/tests/test-app-host-workspace-command-controls.fnl`

**Interfaces:**
- Consumes all `app-host.command-run-history` functions from Task 1.
- Produces:
  - `WorkspaceCommandControls({:descriptor descriptor :history-limit number|nil :now function|nil})`
  - `state.run-history`
  - `state.active-history-run-id`
  - `state.history-message`

- [ ] **Step 1: Add failing controls tests for no-entry and sync history**

Add focused tests to `test-app-host-workspace-command-controls.fnl`:

- `confirmation first click leaves history empty`: click a required-confirmation command once; assert `(# (History.entries state.run-history)) == 0` and `state.history-message` contains `No command runs yet`.
- `confirmed second click creates success history entry`: second click runs; assert one entry with status `:ok`, command id, and result text.
- `invalid payload creates failed history entry`: set invalid number, click execution, assert thrown `number field`, handler run count `0`, one entry status `:error`, error text contains `number field`.
- `sync structural error creates failed history entry`: descriptor `run-command` throws; assert rethrow, one history entry status `:error`, latest-result restoration remains as existing tests expect.

- [ ] **Step 2: Add failing controls tests for async history**

Add tests:

- `async progress updates active history entry`: start pending async command; assert one running entry; emit progress; assert still one entry and progress text/value updated.
- `async success finishes active history entry`: emit terminal ok; assert one entry status `:ok` and result text.
- `async cancel finishes active history entry`: click active Cancel; assert one entry status `:cancelled` and error text contains cancellation reason.
- `drop does not create terminal history entry`: start pending async command, call `widget:drop`, assert still one entry with status `:running` and no extra terminal row; late callback does not mutate it.
- `history trims to default limit`: run 11 or 12 simple sync commands through repeated clicks; assert exactly 10 entries and newest run id first.

- [ ] **Step 3: Wire history state into controls**

In `workspace-command-controls.fnl`:

- Require `app-host.command-run-history`.
- Create history in build:
  ```fennel
  (local run-history (History.create {:limit opts.history-limit :now opts.now}))
  ```
- Initialize state fields:
  - `:run-history run-history`
  - `:active-history-run-id nil`
  - `:history-message (History.list-text run-history)`
  - `:history-text nil` if needed for widget reference.
- Add `refresh-history-text` to update state and `WrappedText` when present.

- [ ] **Step 4: Render the recent-runs text block**

Add one `WrappedText` child below the existing result row. It should use `state.history-message`. Do not create per-entry widgets.

- [ ] **Step 5: Start entries only on execution click**

In the branch that actually executes a command, call `History.start-run!` after clearing confirmation and before payload construction. Do not touch history in first-click confirmation branch.

- [ ] **Step 6: Record payload and payload failures**

After successful payload build, call `History.set-payload!` and refresh. If payload build throws, call `History.fail!`, refresh, restore existing latest-result/buttons state, and rethrow.

- [ ] **Step 7: Record sync terminal and structural failures**

Pass `run-id` into sync execution. On returned result envelope, call `History.finish!` and refresh before or during terminal cleanup. On descriptor structural throw, call `History.fail!`, refresh, restore previous state, and rethrow.

- [ ] **Step 8: Record async progress, terminal, and user cancellation**

Pass `run-id` into async execution. Set `state.active-history-run-id`. In guarded progress callback, call `History.progress!` and refresh. In guarded terminal callback, call `History.finish!`, refresh, then clear active history id. In user cancellation, finish the entry with the same cancellation result used by latest-result UI and refresh.

- [ ] **Step 9: Preserve drop semantics**

In `drop`, do not call `History.finish!` or `History.fail!`. Existing active invocation drop and stale callback guards should prevent late history mutation.

- [ ] **Step 10: Validate Task 2**

Run:

```bash
./build/space -m tools.fennel-check:main -- --target files --file assets/lua/app-host/command-run-history.fnl --file assets/lua/app-host/workspace-command-controls.fnl --file assets/lua/tests/test-app-host-command-run-history.fnl --file assets/lua/tests/test-app-host-workspace-command-controls.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-run-history:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-command-controls:main
```

- [ ] **Step 11: Commit Task 2**

```bash
git add assets/lua/app-host/workspace-command-controls.fnl assets/lua/tests/test-app-host-workspace-command-controls.fnl
git commit -m "feat(ui): show hosted command run history"
```

---

### Task 3: Documentation and Final Validation

**Files:**
- Modify: `docs/dev/features/hosted-runtime-apps.md`
- No implementation changes expected during validation.

**Interfaces:**
- Consumes implemented history behavior from Tasks 1-2.
- Produces docs and final validation evidence.

- [ ] **Step 1: Document command history**

Update `docs/dev/features/hosted-runtime-apps.md` to state:

- command controls show a bounded recent run log below latest result;
- default limit is 10, newest first;
- run ids are controls-local and session-local;
- history is in-memory and cleared with the controls/session;
- first confirmation clicks do not create entries;
- payload validation and structural invocation failures create failed entries only after execution click;
- async progress updates the active row rather than appending rows;
- drop/close cleanup does not create terminal history entries;
- entries store bounded text summaries only, not raw payload/result objects;
- persistence, global history, queues, polling, durable jobs, auth/permissions, filtering, export, and app-specific history APIs remain out of scope.

- [ ] **Step 2: Run docs-focused search**

```bash
rg -n "Recent runs|history|run log|persistent|queue|polling|payload" docs/dev/features/hosted-runtime-apps.md
```

Confirm docs include the new behavior and no contradictory stale wording.

- [ ] **Step 3: Run final validation**

Run:

```bash
make fennel-check
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-run-history:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-workspace-command-controls:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-result-model:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-app-host-command-runner:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-hosted-app-workspace-panel:main
```

If validation fails, do not finish. Capture the failing command, relevant output, branch state, and `git status --porcelain`; supervisor must invoke systematic debugging.

- [ ] **Step 4: Commit Task 3 docs**

```bash
git add docs/dev/features/hosted-runtime-apps.md
git commit -m "docs: document hosted command run history"
```

If validation required no repository changes besides docs, commit docs only. Do not create an empty validation commit.

---

## Validation Summary

Minimum implementation-task validation:

```bash
./build/space -m tools.fennel-check:main -- --target files --file <touched-fennel-file> [...]
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m <focused-test-module>:main
```

Final validation uses `make fennel-check`, `make constraints`, focused history/controls tests, and broader hosted command focused tests. PR CI remains the full integration gate before ready-to-merge claims.
