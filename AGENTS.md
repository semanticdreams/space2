# Repository Guidelines

Be extra rigorous; I'm at risk of losing my job at my hospital.
Don't be afraid; Hesitancy will hold us back.
Clean design is important, refactor when reasonable.

## Fast-dev workflow exception

For the user-selected `fast-dev` primary and user-selected `live-dev` primary only,
their prompts and the shared `fast-dev-wrap-up` skill override conflicting process
rules below and those imported by domain skills. These exact identities edit,
debug, validate, and commit directly: fast-dev on `fast-dev/<topic>`, live-dev on
`live-dev/<topic>`. Checkpoints are local only; no
mandatory design/planning docs, implementation or capability workers, advisor
gates, per-change review, or verbose commit templates. Short intent-focused
local commits are sufficient. Ordinary completion or a commit request does not
authorize publishing; integration requires explicit user wrap-up authorization.
The selected caller must use its own corresponding branch prefix, not the other's.
Live-dev establishes manual mode before editing and explicitly refreshes after
validated changes, with no filesystem watching or lifecycle confirmation prompts.
The default `supervisor` is unchanged.
Wrap-up uses one observational `fast-dev-reviewer` review of the whole branch;
fixes are direct, followed by self-review and revalidation, not mandatory
independent re-review per fix. Use raw Git/GitHub for this authorized lifecycle.

Retain Space technical standards, domain guidance, validation commands, and
evidence-based debugging. Do not integrate with unresolved material defects or
required validation failures; diagnose and fix them rather than bypass them.
Environment isolation, not narrow tool permissions, bounds these primaries' authority.
For all other agents, retain their existing process and permission contracts; this
exception does not change an already-running agent's rules.

## Branch Convention

The default base branch for pull requests and merges is `main`.

For final validation and PR diff/base checks, use `origin/main` as the base
branch reference — not local `main`. Local `main` may be stale or contain
unrelated local commits. Use local `main` only when explicitly performing a
local merge or integration operation that requires it.

Before final validation, PR creation, or any ready-to-merge claim, fetch
`origin` and evaluate the branch against current `origin/main`. If the branch
is behind `origin/main` or remote integration would be rejected, update the
feature branch by a safe merge from `origin/main` when permitted, resolve any
conflicts through `implementer` → `reviewer` → pass, commit reviewed fixes, and
rerun validation from a clean tree. Do not rebase or force-push unless the human
explicitly requests it.

After implementation is complete — reviewed, committed, tests passing, tree
clean — the default integration action is to push the current branch and create a
pull request targeting `main`. Do this automatically; do not present an
integration menu or ask the user which action to take. Only deviate when the user
explicitly requests a different integration action or when the branch state is
unsafe (uncommitted changes, failing tests, unresolved merge conflicts with
`main`).

If required validation fails after implementation, review, or commit, do not
finish, push, create a pull request, merge, clean up the branch, or claim
ready-to-merge. Capture the failing command, failing tests, relevant output,
current branch state, and `git status --porcelain`. Invoke the
`systematic-debugging` skill and continue investigating even when the failure
appears unrelated, flaky, timing-dependent, or environmental. Establish root
cause or gather enough evidence to explain why root cause cannot be established
with available access. Route any repository fix through `implementer` →
`reviewer` → pass, commit reviewed fixes, rerun validation from a clean/current
`origin/main` base, and only proceed with the default integration action when
the required suite is green.

### Post-PR merge queue

After a pull request is open and queued by GitHub merge queue, agents keep running
and poll until the PR is actually merged. Queue handoff alone is not success;
success means the PR is merged (`mergedAt` present or equivalent merged state).

Agents poll with:

```bash
gh pr view <pr-or-branch> --json state,mergedAt,mergeStateStatus,mergeable,autoMergeRequest,statusCheckRollup,headRefName,headRefOid,url
gh run list --workflow test.yml --event merge_group --limit 20 --json databaseId,headBranch,headSha,status,conclusion,event,url,displayTitle,createdAt
gh run watch <run-id> --exit-status --interval 100
```

The following states are non-terminal and the agent should keep polling:
`queued`, `waiting`, `pending`, `in-progress`, `expected`, or
`null`/missing conclusion on merge-group runs.

The following are actionable blockers:

- **merge conflicts:** the merge queue cannot assemble or validate the merge
  group.
- **failed required `test` check:** the merge-group run completed with
  `failure`, `cancelled`, `timed_out`, or `action_required`.
- **missing or disabled queue:** merge queue is not active for `main` (neither
  the merge-group trigger fires nor the queue processes).
- **permission failures:** the agent cannot query PR status, list merge-group
  runs, or watch runs.
- **closed-unmerged PRs:** the PR was closed without being merged.
- **queue timeouts:** the merge-group run remains `queued` or `in_progress`
  beyond a reasonable window.

- Do not update the PR branch solely because `origin/main` advanced. The merge
  queue's merge-group checks are the post-PR integration freshness gate.
- Rebase and force-push remain forbidden unless the human explicitly requests
  them.
- For actionable blockers, invoke `systematic-debugging` to identify root cause
  or establish the limits of available evidence. Route any repository fix
  through `implementer` → `reviewer` → pass. After reviewed fixes are committed,
  rerun validation from current `origin/main`, push the PR branch, and requeue.
- If merge queue is not enabled or cannot be verified, report
  `HUMAN_DECISION_REQUIRED` with the exact GitHub setting needed instead of
  entering a stale-branch polling loop.

## Project Structure & Modules

- `src/` holds the C++17 engine modules (rendering, physics, audio, bindings). Add new systems as matching `.cpp`/`.h` pairs. Engine Lua bindings live in `src/lua_engine.cpp`.
- `apps/space/main.cpp` is the executable entry point; bootstrap other front ends here.
- `assets/` includes Lua, Fennel, Python, textures, and audio. Runtime and tests rely on `SPACE_ASSETS_PATH` pointing here.
- During the Python-to-Fennel/C++ migration, treat `assets/python/` as historical prototypes only. Reference them to understand behavior, but base new features, tests, and architecture decisions on the canonical Fennel modules in `assets/lua/` and the C++ engine in `src/`.
- `tests/` contains CTest targets; keep fixtures aligned with the asset layout.
- `scripts/` bundles utilities (`seed.py`), while `external/` houses vendored dependencies consumed by CMake.
- `archive/` contains some old python bindings that are no longer used but may be used for reference when building new features.

## OpenAI API Docs

- OpenAI API reference lives in `docs/dev/openai/`; start at `docs/dev/openai/index.md` for a map to chat/responses, assistants/threads/runs, uploads/vector stores, realtime events, and project/admin endpoints.
- Endpoint files follow the action name inside each folder (`create.md`, `list.md`, `object.md`, etc.). Use `rg "POST /responses"` (or similar) from the repo root to jump to the exact endpoint when wiring code to the API.

## Project-Specific OpenCode Skills

OpenCode users: restart after `.opencode/**` changes.

- Use `space-fennel-ui` for Fennel widgets, layout, rendering adapters, interaction widgets, widget lifecycle, or widget tests. See `docs/dev/fennel/style.md`.
- Use `space-graph-doctrine` for graph nodes, graph maps, graph views, graph persistence/topology, key loaders, or graph terminology. See `docs/dev/notes/graph.md`.
- Use `space-testing-runtime` for tests, E2E snapshots, remote-control debugging, profiling, build commands, or runtime harnesses. See `docs/dev/features/development-tooling.md`.

## Build, Run & Test

- `make cmake` primes the `build/` directory; rerun after editing CMake files.
- `make build` compiles a Release build in `build/`.
- **Build timeouts:** A cold `make build` can take hours. Always pass an explicit `timeout` parameter:
  - `make build`: `timeout: 14400000` (4 hours).
  - `make cmake`: `timeout: 600000` (10 minutes).
  - A killed build may leave partial artifacts; err on the high side rather than
    restarting from scratch.
- `make run` executes `space` with `SPACE_ASSETS_PATH=../assets` (via `./space -m main`).
- When running Lua/Fennel tests from the CLI, always set `SPACE_ASSETS_PATH` to the absolute `assets` path (e.g. ``SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.fast:main``) so path-sensitive suites like `FsView` can resolve fixtures correctly.
- Fennel macros live under `assets/lua`; when invoking tests directly with `./build/space -m ...` set `FENNEL_PATH` and `FENNEL_MACRO_PATH` to `$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl` to ensure `(import-macros ...)` resolves.
- **Targeted local validation by default:** Agents run the narrowest meaningful checks for the changed behavioral surface:
  - **Fennel/UI/layout behavior:** compile check first (`make fennel-check` or `./build/space -m tools.fennel-check:main -- --target files --file <path>` for touched `.fnl` files), then constraints (`make constraints` or explicit-file constraints), then focused Fennel tests. Compile/constraints/test evidence should be reported in handoffs.
  - **C++ behind Fennel bindings:** build first, then focused Fennel tests through the binding surface.
  - **Pure C++ utility behavior:** build the relevant target and/or focused CTest.
  - **Docs/prompt-only changes:** focused text searches, diff review, and formatting checks.
  - **Build, package, startup, runtime initialization, broad binding/API, or other high-risk changes:** broaden local validation, including `make test` when that is the relevant local gate.
- `make build` is the normal **runtime/freshness prerequisite** when `./build/space` may be missing or stale, or when C++, CMake, runtime initialization, bindings, or host scaffolding changed.
- Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles for Space Fennel. Use the project-native `tools.fennel-check` command and constraints/tests instead.
- For Fennel-facing work, `make constraints` runs after `make fennel-check` so constraint violations surface before slower debugging loops. The constraints gate is blocking; every result other than `pass` (`violations`, `fail`, or `interrupted`) exits nonzero and should be diagnosed and fixed through reviewed code or reviewed baseline data, not bypassed. See [Fennel Constraints](docs/dev/constraints.md).
- `make test` already depends on `make constraints`, so full-suite runs execute the constraints gate before normal Fennel tests; do not duplicate `make constraints` immediately before `make test` unless the early, faster feedback is useful.
- Disable audio for CLI test runs by default to avoid sandbox/PortAudio warnings: prefix commands with `SPACE_DISABLE_AUDIO=1` (e.g. `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.fast:main`).
- When running tests, point `XDG_DATA_HOME` outside the repo to avoid littering the workspace (use `XDG_DATA_HOME=/tmp/space/tests/xdg-data` unless otherwise specified). Agents should always skip keyring-backed tests (`SKIP_KEYRING_TESTS=1`). Standard full-suite command (use when full local validation is justified by risk or plan/reviewer requirement, not as a default before every checkpoint commit): `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test`.
- `make debug` configures `build/debug/` and launches `gdb ./space`.
- `make test` or `python3 scripts/ctest-summary.py --test-dir build --output-on-failure` runs all registered tests once the build is up to date.
- When Lua/Fennel work needs additional bindings or host scaffolding, update the relevant C++ (e.g. `apps/space/main.cpp`, `src/` modules) yourself and rerun `make build` to confirm the harness still compiles before handing the change back.
- On parentheses imbalance in Fennel code, especially when the code is deeply nested, inspect the nearest enclosing form around the reported location, then restructure the code by moving logic into helper functions in order to simplify the code structure and reduce nesting.
- Fennel parse errors often report the place where the parser finally got confused, not the form that actually caused the problem. If an innocent-looking binding such as `local build` or a closing delimiter is blamed, first isolate the bad form by temporarily removing chunks of logic until the file compiles, then re-add them step by step. Use that to find the real construct before doing broader restructuring.
- For live debugging, `space` supports `--remote-control=<zmq endpoint>` which evaluates Fennel code inside the running app; use `./build/space -m tools.remote-control-client:main -- --endpoint <endpoint> -c "<code>"` to send commands, and only enable it on trusted machines. The eval environment exposes `remote_control.create/resolve/reject/poll` for async results (create an id, resolve it inside a signal callback, then poll by id). Use `scripts/remote-control-heavy.sh` to exercise the async flow against a live app.
- When asked to debug a running app, prefer using the remote-control endpoint if the app was started with `--remote-control`; `make run` defaults to `ipc:///tmp/space-rc.sock`, otherwise ask for the endpoint, then send Fennel snippets via the client to inspect or modify state.
- Use `scripts/remote-control-debug.sh` for repeatable live-debug or live-inspect queries; update it as needed instead of ad-hoc client invocations, and run it outside the sandbox so IPC access works.
- `scripts/remote-control-debug.sh` should always contain only the latest debug query; replace its contents for new questions instead of adding flags or multiple modes.
- Use `app.next-frame` when remote-control scripts need to wait for a frame to render before reading state or running render-capture.
- E2E tests: `SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test-e2e` (must run outside sandbox).
- Add C++ tests under `tests/` with `CMakeLists.txt` registration; mirror runtime asset setup from `apps/space/main.cpp`.
- Profilers: `make prof target=<name>`; the `space-testing-runtime` skill covers profiling workflows.

## Coding Style & High-Risk Rules

- **No silent failures:** If required data, bindings, or operations fail, surface an explicit error immediately — never convert failures into quiet no-ops or clean exits.
- **Fennel classes:** Construct `self` in a final literal with all methods included; do not create early and mutate with `set`.
- Use `local` instead of `let` in Fennel.
- Use factory functions instead of constructors (`.new`).
- **Canonical option keys only:** Do not add legacy aliases or compatibility shims; migrate existing call sites instead.
- Use `assets/lua/json-utils.fnl` for atomic JSON writes.
- For C/C++: four-space indent, brace-on-new-line for functions, `std::unique_ptr`/`std::shared_ptr` over raw ownership, minimal headers.
- Fennel: multi-branch `if` forms instead of nesting; bind multiple return values directly with `local`.
- Graph nodes stay decoupled from views; use signals to emit updates.
- Fennel parse errors: the reported location is often misleading — isolate bad forms by temporarily removing chunks of logic.

## Commit Conventions

- Use the `type(scope)` format as described by the `git-commit` skill.
- Scopes (when useful): `engine`, `render`, `physics`, `audio`, `lua`, `ui`, `assets`, `scripts`.
- For Fennel-facing feature or bugfix handoffs, include a lightweight constraint-impact line when relevant: helped, obstructed/noisy, changed, or not applicable.
- Before checkpoint commits, run sufficient focused validation for the changed behavioral surface and record a short coverage rationale in your report.
- Escalate to broader local validation when the changed surface is high risk or the plan/reviewer requires it.
- Do not claim ready-to-merge until the applicable PR CI integration gate is green.

## Assets & Configuration Tips

- When adding assets, ensure `AssetManager::getAssetPath` can locate them and verify packaging copies from `assets/`.
- For icon names used by UI buttons/widgets, validate availability against `assets/material-design-icons/icons.txt` before committing. Use `rg` on that file and prefer exact icon-name matches from the start of each line.
