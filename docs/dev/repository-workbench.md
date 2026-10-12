# Repository Workbench

A general system for cloning, editing, testing, and opening pull requests against
remote Git repositories from inside Space. Space edits Space by being one repo
profile, not a special case.

This document describes the design and current implementation of the Repository
Workbench feature.

## Motivation

The internal agent and unit system already let users create, edit, reload, and
test runtime Fennel modules inside the app. That path works well for user units
that extend the canvas, shell, or agent tools.

We now want the ability to work on full codebases — including Space itself —
from within the running app. The hard problem is **self-hosting safety**: a
running Space instance must not depend on the files it actively edits. If the
agent introduces an error in the app bootstrap or C++ bindings, the supervisor
cannot silently hot-reload into a crash.

Instead of treating "editing Space" as a one-off, we generalise to **any
remote Git repository**. The running Space instance stays a stable supervisor.
Every change happens in an isolated clone/worktree under Space's data
directory. The agent reads, patches, builds, tests, commits, pushes, and opens
pull requests — all without touching the supervisor's own runtime assets.

## Principles

1. **The running app is a supervisor, never the edit target.** Runtime assets
   are not assumed to be editable source code.

2. **Remote repos only.** No local attachment. Repositories are cloned from
   remote URLs into Space's data directory. This avoids ambiguity about whether
   the current checkout, a sibling checkout, or something else is the "source
   of truth."

3. **Tasks are isolated.** Every agent task gets its own git worktree on a
   dedicated branch. The task never edits the cache clone's checked-out branch
   or any other task's worktree.

4. **Space is the policy boundary.** Native agent tools stay denied. The agent
   sees only Space MCP tools. Path policy, allowlisted checks, and hash-gated
   writes run inside Space, not in an uncontrolled external process.

5. **PRs are the integration boundary.** Every task produces a branch, a set of
   commits, and a pull request. CI on the remote is the source of truth for
   "safe enough."

6. **Repo knowledge lives in profiles.** A generic profile supports any Git
   repo. Space gets a profile that knows `make build`, `make test`,
   `SPACE_ASSETS_PATH`, candidate launch, and restart requirements.

## Architecture

### Storage layout

Everything lives under Space's user data directory:

```
<user-data-dir>/repositories/
  registry.json                 persisted repo metadata
  clones/
    <repo-id>/                  normal clone (cache, never edited directly)
  worktrees/
    <repo-id>/
      <task-id>/                checked-out worktree for one task
  tasks/
    <task-id>.json              task record
  logs/
    <task-id>/                  check stdout/stderr
```

### Core modules

| Module | Role |
|---|---|
| `repo/remote.fnl` | Parse/normalise remote URLs, derive stable repo ids. |
| `repo/git.fnl` | Safe git wrapper using `process.run` with argv arrays. Never shells out. |
| `repo/store.fnl` | Persist registry and tasks via atomic JSON writes. |
| `repo/workspace.fnl` | Clone, fetch, worktree, task lifecycle. |
| `repo/path-policy.fnl` | Validate repo-relative paths; reject escapes, symlinks, `.git/`. |
| `repo/checks.fnl` | Profile check definitions and subprocess execution. |
| `repo/profiles.fnl` | Generic profile plus Space-specific profile. |
| `repo/display.fnl` | Shared safe display URL construction and repo summary. |
| `repo/workbench-view.fnl` | User-facing Repository Workbench panel widget. |
| `launchables/repository-workbench.fnl` | Launcher entry point; opens the workbench panel on the HUD. |
| `llm/presets/builtins/repo.fnl` | MCP tool adapters, preset registrations, agent prompt fragments. |

### Key objects

**Repository**
```fennel
{:id "github.com-owner-repo"
 :remote-url "git@github.com:owner/repo.git"
 :host :github       ;; :github, :gitlab, :unknown
 :owner "owner"
 :name "repo"
 :default-branch "main"
 :clone-path "..."   ;; absolute path to clones/<id>
 :profile :generic   ;; :generic, :space, :unknown
 :created-at 1718700000}
```

**Task**
```fennel
{:id "task-<uuid>"
 :repo-id "github.com-owner-repo"
 :prompt "original agent prompt for this task"
 :base-branch "main"
 :branch "space-agent/task-<uuid>-<short-slug>"
 :worktree-path "..."               ;; absolute path to the checked-out worktree
 :base-commit "abc123"
 :base-file-hashes {"src/foo.cpp" "sha256:..."}  ;; recorded at task start
 :status :working                    ;; :working, :committed, :pushed, :pr-open, :merged, :closed
 :agent-session-id nil
 :created-at 1718700000
 :committed-at nil
 :pr-url nil}
```

**Check definition** (static, per profile)
```fennel
{:id :build
 :label "Build"
 :argv ["make" "build"]
 :cwd :worktree         ;; resolved to worktree path at runtime
 :env {:SPACE_ASSETS_PATH :worktree/assets}
 :timeout 300
 :risk :shell}
```

## Repo lifecycle

### 1. Clone

```
space_repo_clone {url "git@github.com:semanticdreams/spacecore.git"}
```

- Parse URL to derive `repo-id` (host + owner + name).
- Check registry for existing entry; if present, skip clone.
- Clone into `clones/<repo-id>/` via `git clone <url>`.
- Detect default branch via `git -C <clone-path> symbolic-ref refs/remotes/origin/HEAD`.
- Autodetect profile:
  - Space: see [Space profile](#space-profile).
  - Generic: everything else.
- Persist to `registry.json`.
- Fetch on each use: `git -C <clone-path> fetch --prune origin`.

No local attachment. No inference from `SPACE_ASSETS_PATH` or `fs.cwd`.

### 2. Task creation

```
space_repo_create_task {repo-id "..." prompt "..." base-branch "main"}
```

- Create task id.
- Derive branch name: `space-agent/<task-id>-<slug from prompt>`.
- Create worktree from the cache clone:
  ```
  git -C <clone-path> worktree add <worktrees/repo-id/task-id> -b <branch> origin/<base-branch>
  ```
- Record base commit and file hashes for every tracked file in the worktree.
- Persist task record.

### 3. Agent work

Agent reads, searches, and patches files through Space MCP tools. All paths are
repo-relative (relative to the task worktree root).

### 4. Checks

Agent requests checks through `space_repo_run_check`. Only checks defined in
the repo profile are available. Checks run as subprocesses with the worktree as
cwd.

### 5. Commit

Agent calls `space_repo_commit {task-id "..." message "..."}`. Space commits
the diff in the task worktree.

### 6. Push and PR

```
space_repo_push {task-id "..."}
space_repo_open_pr {task-id "..." title "..." body "..."}
```

- Push uses `git push origin <branch>`.
- PR uses `gh pr create` targeting the repo's default branch. Draft by default;
  set `draft=false` to mark ready.
- PR body includes task prompt, files changed, checks run, and a summary.

Agent decides when to push and open PR. No UI confirmation required per action.
The approval policy (risk gating through `AgentApprovals`) is the control
point. Push and open-PR are classified as `shell` risk initially and gated
through the existing approval system.

### 7. CI polling

```
space_repo_pr_status {task-id "..."}
```

- Resolves the task's PR URL, fetches CI status via `gh pr checks` or
  `gh pr view --json statusCheckRollup`.
- Returns pass/fail/pending for each check.
- Agent can iterate on failures by applying new patches and force-pushing
  (via `--force-with-lease`).

## Path policy

All repo file tools accept repo-relative paths only.

Rules enforced by `repo/path-policy.fnl`:

- Path must be a non-empty string.
- No absolute paths (must not start with `/`).
- No `..` segments.
- No NUL bytes.
- Resolved path must be inside the task worktree root.
- For reads: file must exist and not be inside `.git/`.
- For writes: file must not be a symlink; no ancestor may be a symlink.
  New files must resolve entirely within the worktree with no symlink
  ancestors.
- For writes to existing files: the file's current content hash must match
  the recorded base hash. This prevents the agent from editing a file that
  changed since last read.

Hash lifecycle:
- `space_repo_read_file` returns a `sha256` field with the content hash
  alongside the file content.
- `space_repo_apply_patch` requires `expected-hashes {"path" "sha256:..."}`
  for every existing file the patch touches. The tool computes the current
  hash, compares it to `expected-hashes`, and rejects the patch on mismatch.
- After a successful patch, the task's `base-file-hashes` entry for each
  modified file is updated to the post-patch hash. The agent can then apply
  further patches against the file without re-reading.
- `space_repo_diff` also returns per-file hashes so the agent can reconcile
  after a stale-hash rejection.

Writes are denied to:
- `.git/`
- Task metadata directories.
- Any path that escapes the worktree, even via symlink.

## MCP tools

All tools follow the existing `ToolAdapterRegistry` convention: stable
capability id, `mcp-name` prefixed `space_`, `inputSchema`, and `make-run`
closure.

### Repo management

| Tool | Description |
|---|---|
| `space_repo_clone` | Clone and register a remote repository. |
| `space_repo_list` | List registered repositories. |

### Tasks

| Tool | Description |
|---|---|
| `space_repo_create_task` | Create a task worktree and branch for a repo. |
| `space_repo_status` | Git status for the task worktree. |
| `space_repo_diff` | Unstaged and staged diff for the task worktree, with per-file hashes. |

### File operations

| Tool | Description |
|---|---|
| `space_repo_read_file` | Read a repo-relative file. Returns content and `sha256` hash. Optional line range. |
| `space_repo_search` | Grep/glob search inside the task worktree. |
| `space_repo_apply_patch` | Apply a unified diff patch. Requires `expected-hashes` for every existing file touched. |

### Checks

| Tool | Description |
|---|---|
| `space_repo_run_check` | Run a profile-defined check and return output. |
| `space_repo_list_checks` | List available checks for the repo profile. |

### Git and PR

| Tool | Description |
|---|---|
| `space_repo_commit` | Commit the current task diff with a message. |
| `space_repo_push` | Push the task branch to origin. |
| `space_repo_open_pr` | Open a pull request (draft by default). |
| `space_repo_pr_status` | Poll CI status for the task's PR. |

Security: No `space_repo_run_shell` in V1. The only subprocess execution is
through profile-defined checks with fixed argv arrays.

## User-facing access

A Repository Workbench panel is available from the Launcher (HUD Apps button
or leader-mode `p`). The panel provides:

- **Clone Remote Repo** — enter a URL and click Clone.
- **Repository list** — shows all registered repos; click to select.
- **Selected repo details** — owner/name, default branch, profile.
- **Task list** — shows tasks for the selected repo.
- **Create task** — enter a prompt and optional base branch.

The panel directly uses the workspace module (same backing store as the MCP
tools). Clone and task creation are immediate.

The launchable is defined in `launchables/repository-workbench.fnl` and uses
HUD panel persistence, same as the Chat and Launcher panels.

## Agent integration

### Preset registration

A new builtin `repo` preset group registers with the existing preset pipeline
in `main.fnl`, following the same pattern as `AgentBuiltinUnits.register`:

```fennel
(AgentBuiltinRepo.register app.agent-presets)
```

### Preset defaults

| Preset | Group | Default state | Risk | Tools |
|---|---|---|---|---|---|
| `repo-bootstrap-tools` | repo | `auto` | `shell` | `repo.clone`, `repo.list` |
| `repo-discover-tools` | repo | `auto` | `filesystem-read` | `repo.status`, `repo.read-file`, `repo.search`, `repo.diff`, `repo.list-checks` |
| `repo-edit-tools` | repo | `auto` | `filesystem-write` | `repo.apply-patch`, `repo.create-task`, `repo.commit` |
| `repo-check-tools` | repo | `auto` | `shell` | `repo.run-check` |
| `repo-pr-tools` | repo | `auto` | `shell` | `repo.push`, `repo.open-pr`, `repo.pr-status` |

`repo-bootstrap-tools` is always active so the agent can clone the first repo.
All other repo presets are gated on a `repos-available?` context field, updated
whenever the repo store changes. This avoids a bootstrap deadlock where the
clone tool is inaccessible until a repo exists.

### System prompt

A prompt fragment (similar to the unit system prompt in
`llm/presets/builtins/units.fnl`) describing:

- Repository Workbench concepts: clone, task, worktree, branch, PR.
- Available tools and when to use each.
- Path rules: repo-relative only, no `..`, no symlinks.
- Commitment flow: read, patch, run checks, review diff, commit, push, open PR.
- Profile-specific check commands and expected output.
- The agent should not push or open a PR until checks pass.
- For Space repos: which commands rebuild, which files require restart.

### Approval policy

The existing `AgentApprovals` system gates every tool execution. The default
policy for the repo preset group:

- `filesystem-read` (status, read, search, diff): ask on first use; the user
  can grant "always approve" after reviewing.
- `filesystem-write` (patch, commit): ask each time or fingerprint-grant.
- `shell` (checks, push, PR): ask with clear preview of command/remote action.

The agent can call `space_agent_request_tool_approval` to pre-request approval
with exact arguments before invoking a gated tool.

## Git wrapper

`repo/git.fnl` wraps `process.run` with argv arrays. No shell interpolation.

```fennel
(fn git [clone-path & args]
  (process.run {:args (icollect [_ a (ipairs ["git" "-C" clone-path])]
                         a)
                :timeout 30}))
```

Key operations:
- `git-clone`: `git clone <url> <path>`
- `git-fetch`: `git -C <clone-path> fetch --prune origin`
- `git-default-branch`: `git -C <clone-path> symbolic-ref refs/remotes/origin/HEAD`
- `git-worktree-add`: `git -C <clone-path> worktree add <path> -b <branch> origin/<base>`
- `git-status`: `git -C <worktree> status --porcelain`
- `git-diff`: `git -C <worktree> diff`
- `git-add`: `git -C <worktree> add -A`
- `git-commit`: `git -C <worktree> commit -m <message>`
- `git-push`: `git -C <worktree> push origin <branch>`
- `git-push-force`: `git -C <worktree> push --force-with-lease origin <branch>`
- `git-worktree-remove`: `git -C <clone-path> worktree remove <path> --force`

## Profiles

### Generic profile

Any repository that does not match a known profile.

Checks:
- None by default. The profile does not define build or test commands.

The agent can read, search, patch, commit, and push. For GitHub-hosted repos
it can also open PRs; for unknown-host repos PR tools are unavailable (see
[Remote URL handling](#remote-url-handling)). Checks are unavailable unless the
user configures custom checks in a future version.

### Space profile

Detected by markers in the repository root:

- `CMakeLists.txt` with `project(space`.
- `assets/lua/main.fnl`.
- `src/lua_runtime.cpp`.
- `AGENTS.md`.

Checks — all run with `cwd` set to the worktree root. Each uses a fixed argv
array and an env map; no shell strings. The `SPACE_ASSETS_PATH` value is
computed from the worktree path at runtime.

| Check id | Argv | Env | Timeout |
|---|---|---|---|
| `build` | `["make" "build"]` | — | 600s |
| `test` | `["make" "test"]` | `SKIP_KEYRING_TESTS=1`, `XDG_DATA_HOME=/tmp/space/tests/xdg-data`, `SPACE_DISABLE_AUDIO=1`, `SPACE_ASSETS_PATH=<worktree>/assets` | 300s |
| `e2e` | `["make" "test-e2e"]` | `SPACE_DISABLE_AUDIO=1`, `SPACE_ASSETS_PATH=<worktree>/assets` | 600s |

Space profile also understands:
- Which files require a full rebuild (C++, CMake, bindings, `main.fnl`).
- Which files can be hot-reloaded (user units, Fennel-only modules).
- When a task must include `make build` before `make test`.
- When a task changes boot/core files and a restart is required.

Future: candidate launch. After a successful build, Space can launch the
new `build/space` binary as a subprocess with an isolated data directory and
run remote-control smoke tests against it.

## Remote URL handling

`repo/remote.fnl` parses URLs into structured data:

```
git@github.com:owner/repo.git    → host=github, owner=owner, name=repo
https://github.com/owner/repo    → host=github, owner=owner, name=repo
ssh://git@gitlab.com/owner/repo  → host=gitlab, owner=owner, name=repo
```

Repo id: `<host>-<owner>-<repo>` (slugified, alphanumeric with hyphens).

For example, `github.com-semanticdreams-spacecore`.

Host detection enables:
- `gh` CLI path for GitHub.
- Future `glab` CLI path for GitLab.
- `:unknown` host for everything else (PR tools unavailable).

## Task lifecycle

```
[working] --commit--> [committed] --push--> [pushed] --open-pr--> [pr-open]
    |                     |                   |                      |
    +---close--> [closed] +---close--> [closed]+---close--> [closed] +---close--> [closed]
```

- **working**: worktree exists, agent is editing.
- **committed**: at least one commit on the task branch.
- **pushed**: branch exists on remote.
- **pr-open**: pull request exists.
- **closed**: task is done; worktree may be removed.

Transitions:
- Commit moves working → committed.
- Push moves committed → pushed.
- Open PR moves pushed → pr-open.
- Close moves any state → closed.

Closing a task should offer to delete the worktree and the local branch, but
preserve the remote branch and PR.

## Implementation plan

### Phase 1 — Foundation (no agent integration yet)

1. `repo/remote.fnl`: parse URLs, derive repo ids.
2. `repo/git.fnl`: clone, fetch, default-branch, worktree-add.
3. `repo/store.fnl`: registry.json and task persistence.
4. `repo/path-policy.fnl`: path validation with symlink detection.
5. Tests: remote parsing, clone, fetch, worktree creation, path policy
   rejection cases.

### Phase 2 — Read and search

6. `repo/workspace.fnl`: full workspace lifecycle (clone + task create/close).
7. `repo/status.fnl`: porcelain status, diff, base-hash recording.
8. `space_repo_clone`, `space_repo_list`, `space_repo_create_task`.
9. `space_repo_status`, `space_repo_read_file`, `space_repo_search`,
   `space_repo_diff`.
10. Tests: clone from local test remotes, status, read, search, diff accuracy.

### Phase 3 — Write and checks

11. `repo/checks.fnl`: check definitions, subprocess execution, output capture.
12. `repo/profiles.fnl`: generic and Space profile definitions.
13. `space_repo_apply_patch`: hash-gated patch application.
14. `space_repo_run_check`, `space_repo_list_checks`.
15. Tests: patch apply with hash match/mismatch, check execution,
    profile autodetection.

### Phase 4 — Git and PR

16. `space_repo_commit`, `space_repo_push`.
17. `space_repo_open_pr` (via `gh` CLI).
18. `space_repo_pr_status` (via `gh` CLI).
19. Tests: commit/push/PR flow with local or mock GitHub.

### Phase 5 — Agent integration

20. `llm/presets/builtins/repo.fnl`: adapters and presets.
21. Register in `main.fnl` alongside existing builtins.
22. Context gate: `repos-available?` field.
23. Agent prompt fragment covering repository workflow.
24. Tests: preset resolution, tool execution through the surface, approval
    gating.

### Phase 6 — Space profile

25. Space profile checks: `build`, `test`, `e2e`.
26. File classification: restart-required vs hot-reloadable.
27. Environment computation for `SPACE_ASSETS_PATH` from worktree.
28. Tests: Space profile detection, check commands, env correctness.

### Phase 7 — Polish and iteration

29. CI polling with agent repair loop.
30. Task close with worktree cleanup.
31. Task summary for PR body generation.
32. Error recovery: stale clones, partial worktrees, failed pushes.

### Future phases (not in V1)

- Candidate launch and remote-control smoke testing for Space profile.
- GitLab support via `glab` CLI.
- Custom check configuration per repo.
- Non-GitHub PR support.
- UI: attached repo list, task status, diff viewer, PR browser.

## Tests

All tests live under `assets/lua/tests/` and follow the existing pattern
(register in `tests/fast.fnl` or online suites).

Key test areas:

- `test-repo-remote.fnl`: URL parsing, id derivation, edge cases.
- `test-repo-git.fnl`: clone, fetch, worktree create/remove (against temporary
  local repos).
- `test-repo-path-policy.fnl`: path rejection (absolute, `..`, `.git/`,
  symlinks), path acceptance.
- `test-repo-workspace.fnl`: full task lifecycle end-to-end.
- `test-repo-checks.fnl`: check definitions, subprocess execution, output.
- `test-repo-presets.fnl`: adapter registration, preset resolution, surface
  integration.
- `test-repo-space-profile.fnl`: Space profile detection and check commands.

## References

- [Reloadable Units And Hot Reload](/dev/reloadable-units)
- [Agent Preset Control Panel](/dev/agent-preset-control-panel)
- `assets/lua/llm/presets/builtins/units.fnl` — existing unit tool adapters
  and system prompt (pattern to follow for repo tools).
- `assets/lua/llm/presets/builtins/general.fnl` — general tools including
  process execution.
- `assets/lua/llm/agent/approvals.fnl` — risk gating and persistent grants.
- `assets/lua/llm/agent/tool-surface.fnl` — MCP tool surface with approval
  integration.
- `assets/lua/llm/presets/init.fnl` — PresetManager with override and context
  gating.
