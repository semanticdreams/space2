# OpenCode Agent Workflow

This page documents Space's shared Orca / OpenCode workflow for collaborators using the repo-local configuration. It describes how to set up a working agent environment, what the repository expects from agent-driven changes, and which pieces of the personal VM setup note are intentionally excluded from this shared guide.

## Official Orca documentation

Orca and OpenCode provide the agent runtime and development environment. The official documentation covers platform installation, session management, and remote-server workflows:

- [Ways to run Orca](https://www.onorca.dev/docs/ways-to-run)
- [Orca SSH](https://www.onorca.dev/docs/ssh)
- [Orca remote servers](https://www.onorca.dev/docs/remote-servers)

## Supported setups

Space does not require one specific arrangement. Two patterns are supported:

- **Local Orca plus remote SSH checkout.** You run Orca on your local machine, connect to a remote development VM over SSH, and open the Space checkout on that VM. This keeps the heavy build toolchain on the remote host while your local Orca session orchestrates OpenCode.
- **Orca running on the remote VM.** You install Orca directly on the remote development machine and use a local Orca session only to view or connect to that remote session. This works well when your local environment is thin or when you prefer to keep everything on one host.

The local Orca plus remote SSH checklist below is one possible path; it is not a project requirement. Choose whichever arrangement fits your environment.

## Local Orca plus remote SSH checklist

If you choose the local-Orca-plus-remote-SSH setup, work through these points:

1. **Remote VM reachable.** Confirm you can SSH into the remote VM from your local machine.
2. **Build and dev tools.** Install common tooling on the remote VM: `git`, `nodejs` and `npm`, `python3`, `make`, `g++`, `curl`, `clangd`, and `rsync`. These are typically available through the system package manager.
3. **OpenCode on the remote VM.** Install OpenCode and make sure it is on `PATH` for non-interactive SSH sessions so that Orca can invoke it automatically.
4. **GitHub SSH access.** Configure SSH key access for GitHub on the remote VM so the agent can push branches and create pull requests. Test with `ssh -T git@github.com`.
5. **Clone Space on the remote VM.** Clone the repository into a working directory the SSH user can write to.
6. **Add the host in Orca.** Add the SSH host and repository path in Orca's remote-server workflow so it can open the checkout.
7. **Rely on the checked-out repository.** Once the checkout is opened, the agent reads `AGENTS.md` and `.opencode/**` from the repository itself — no external configuration repository is needed.
8. **Final checks.** Run `command -v git node npm clangd opencode` on the remote VM to confirm the expected tools are available, then verify SSH connectivity with `ssh -T git@github.com`.

### Optional: warm new worktrees from the main build

When creating a fresh `git worktree` for agent-driven work, you can warm the
new worktree from a cached main-checkout build instead of running a full
`make build` from scratch. This is a cache warm-start, not a substitute for
validation; agents must still run the normal Space validation ladder.

**When to use:** Run only on a freshly created, clean worktree before any
agent edits begin. The script assumes the same machine and toolchain as the
main checkout and a valid, up-to-date main-checkout build directory.

**When not to use:** Skip this on worktrees that already contain divergent
changes, or when the main-checkout build may be stale relative to the target
branch. If anything behaves unexpectedly after warming, delete the copied
build directory and run `make build`.

The script copies build artifacts from the main checkout's `build/` directory
into the new worktree, then rewrites CMake-generated absolute paths (source and
build directories) to point at the new worktree. After repathing, it re-runs
`cmake` so generated files are refreshed for the new location, then builds the
main target. It preserves the build profile and CEF settings from the main
checkout's cache.

**Safety notes:**
- Run only for a freshly created, clean worktree before agent work begins.
- Assumes the same machine/toolchain and a valid main-checkout `build/`.
- Does not copy credentials. Repaths only generated text files; binary
  artifacts are skipped (detected by the presence of null bytes).
- Re-runs `cmake` after rewriting the cache so CMake refreshes generated
  files for the new worktree.
- Copies build files with fresh mtimes (`rsync --no-times`) so copied
  artifacts appear newer than checkout files. This is safe because the
  script requires identical HEADs; if HEADs differ, it refuses to run
  rather than hiding rebuilds.

Paste the script below into Orca's per-project or per-worktree setup step.
Adjust the `SPACE_MAIN_CHECKOUT` and `ORCA_WORKTREE` environment variables
(or the script's default paths) to match your environment.

```bash
#!/usr/bin/env bash
set -euo pipefail

main_checkout="${SPACE_MAIN_CHECKOUT:-$HOME/space/space}"
worktree="${ORCA_WORKTREE:-$PWD}"
main_checkout="$(cd "$main_checkout" && pwd)"
worktree="$(cd "$worktree" && pwd)"

if [ "$main_checkout" = "$worktree" ]; then
  echo "Refusing to seed the main checkout from itself: $worktree" >&2
  exit 1
fi

src_build="$main_checkout/build"
dst_build="$worktree/build"

if [ ! -f "$src_build/CMakeCache.txt" ]; then
  echo "No reusable build cache at $src_build; run make build in $main_checkout first." >&2
  exit 1
fi

if [ -n "$(git -C "$worktree" status --porcelain)" ]; then
  echo "Worktree is not clean; run this only before agent edits begin." >&2
  exit 1
fi

src_head="$(git -C "$main_checkout" rev-parse HEAD)"
dst_head="$(git -C "$worktree" rev-parse HEAD)"
if [ "$src_head" != "$dst_head" ]; then
  echo "Worktree HEAD ($dst_head) differs from main-checkout HEAD ($src_head)." >&2
  echo "The warm-start script is only safe when the new worktree starts from the same commit as the main checkout." >&2
  echo "For a divergent branch, run make build or warm from a checkout at the same commit." >&2
  exit 1
fi

mkdir -p "$dst_build"
rsync -a --delete --no-times \
  --exclude '/logs/' \
  --exclude '/Testing/Temporary/' \
  "$src_build/" "$dst_build/"

python3 - "$main_checkout" "$worktree" <<'PY'
import sys
from pathlib import Path

old_src = Path(sys.argv[1]).resolve()
new_src = Path(sys.argv[2]).resolve()
old_build = old_src / "build"
new_build = new_src / "build"
replacements = [
    (str(old_build).encode(), str(new_build).encode()),
    (str(old_src).encode(), str(new_src).encode()),
]

for path in new_build.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    try:
        data = path.read_bytes()
    except OSError:
        continue
    if b"\0" in data:
        continue
    updated = data
    for old, new in replacements:
        updated = updated.replace(old, new)
    if updated != data:
        path.write_bytes(updated)
PY

profile="$(awk -F= '/^SPACE_BUILD_PROFILE:STRING=/{print $2}' "$dst_build/CMakeCache.txt" || true)"
cef="$(awk -F= '/^SPACE_ENABLE_CEF:BOOL=/{print $2}' "$dst_build/CMakeCache.txt" || true)"
cmake_args=(-S "$worktree" -B "$dst_build" -DCMAKE_BUILD_TYPE=Release)
[ -n "$profile" ] && cmake_args+=("-DSPACE_BUILD_PROFILE=$profile")
[ -n "$cef" ] && cmake_args+=("-DSPACE_ENABLE_CEF=$cef")
cmake "${cmake_args[@]}"

cmake --build "$dst_build" --target space -- -j"${BUILD_JOBS:-1}"
```

## Remote-VM Orca alternative

When running Orca entirely on the remote VM fits your environment better, install Orca on that host and launch your agent sessions there. Use your local Orca session only as a viewer or connector — some collaborators keep a local Orca window open that connects to the remote instance.

See Orca's [remote servers](https://www.onorca.dev/docs/remote-servers) documentation for details on managing remote Orca instances.

## Space workflow expectations

Once your agent environment is connected to a Space checkout, these repository conventions apply:

- **`AGENTS.md`** is the always-on repository guidance. Agents read it on startup and follow its rules for every session. It covers branch conventions, build commands, test invocation, coding style, and project structure.
- **`.opencode/**`** is the repo-local source for Space agents, skills, and OpenCode configuration. It includes agent definitions, skill files that provide specialized guidance for Fennel, UI, testing, and graph work, and the OpenCode configuration file. This in-repo configuration is canonical for this repository — no separate global config repository is needed.
- **Restart OpenCode after `.opencode/**` changes.** When you add or modify agents, skills, or configuration under `.opencode/`, restart OpenCode so the updated definitions and workflow instruction changes take effect. OpenCode loads these files at startup and does not hot-reload them.
- **Follow repository validation expectations from `AGENTS.md`.** Agents must respect the validation ladder: for Fennel work, run compile checks first, then constraints, then focused Fennel tests. Broader local validation (such as `make test`) is required only when the change is high-risk or the plan/reviewer requires it. Required validation failures are debugging tasks, not items to bypass.
- **Targeted local validation by default.** Agents run the narrowest meaningful checks for the changed behavioral surface rather than the full suite before every checkpoint commit. The expected validation depends on what changed:

  - **Fennel/UI/layout behavior:** compile check first (`make fennel-check` or touched-file `tools.fennel-check`), then constraints (`make constraints` or explicit-file constraints), then focused Fennel tests.
  - **C++ behind Fennel bindings:** build first, then focused Fennel tests through the binding surface.
  - **Pure C++ utility behavior:** build the relevant target and/or focused CTest.
  - **Docs/prompt-only changes:** focused text searches, diff review, and formatting checks.
  - **Build, package, startup, runtime initialization, broad binding/API, or other high-risk changes:** broaden local validation, including `make test` when that is the relevant local gate.

- **`make build`** remains the runtime/freshness prerequisite when the built Space runtime (`./build/space`) may be missing or stale, or when C++, CMake, runtime initialization, bindings, or host scaffolding changed.
- The standard full-suite command is documented for high-risk or explicitly required local validation:
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```
- **PR CI** is the full integration gate. Do not claim ready-to-merge until the applicable PR CI gate is green.
- **Required validation failures**: see [Validation continuation and current base](#validation-continuation-and-current-base) for the full contract.

### Internal Space agent artifact handoffs

Internal Space agent sessions get a session-scoped artifact directory under
`~/.local/share/space/agent-artifacts/<agent-session-id>/`. Implementer,
reviewer, and supervisor reports should be written there; `report.md` in that
directory is the preferred handoff path when an explicit report file is not
otherwise assigned.

Report validation sections must state either `validation-mode: live` or
`validation-mode: disk-only`. Use `validation-mode: live` only when validation
included a successful live MCP reload or smoke check against the running app.
Use `validation-mode: disk-only` for compile checks, constraints, focused tests,
and other checks that did not exercise the running app. Disk-only reports are
not live app validation, so supervisors must not describe the running app as
validated until a live reload or smoke step succeeds.

Internal SpaceAgent OpenCode reconnect is advisory and bounded. If a saved
OpenCode session lookup reports a stale-session or connect-style error, Space
refreshes the bridge config and OpenCode provider once, then creates a fresh
session for that turn. Prompt submission is not blindly retried: prompt failures
are reported as blockers. If a live OpenCode session cannot be established, the
agent report must not claim live validation; use `validation-mode: disk-only`
until a later live MCP reload or smoke check succeeds.

## Permission capability model

Space uses guarded capabilities to reduce routine OpenCode permission friction without broadening normal agent authority.

- **Routine project-scoped operations** stay with normal agents when they are already part of the assigned role and repository workflow, such as focused validation commands and local Git inspection (`git status`, `git diff`).
- **Privileged bounded operations** go through capability agents instead of broad direct permissions. `git-integrator` handles reviewed Git integration boundaries, `github-operator` handles bounded GitHub PR/check/merge-queue operations, and `config-auditor` verifies repo-local OpenCode policy and configuration.
- **Role-breaking or destructive/ambiguous operations** remain denied. Reviewer edit/bash, implementer push or external-directory access, web-researcher local read/bash, force-push, reset/clean, direct `origin/main` pushes, credential access, and similarly unsafe requests surface as `HUMAN_DECISION_REQUIRED` rather than being auto-approved.
- **Wrapper JSON evidence is the reviewable handoff.** Capability wrappers emit structured JSON with `status`, `action`, `message`, and `evidence` so supervisors, reviewers, and weekly automation can inspect what happened without granting a broad shell or GitHub capability.
- **OpenCode must be restarted after `.opencode/**` changes.** Agent definitions, skill instructions, and permission rules are startup-loaded, so restart OpenCode before relying on changed capability agents or policy rules.

### Merged old PR follow-up branch recovery

If `github-operator create-current` reports `human_decision_required` because
the current branch already has an existing PR whose `pr_state` is `MERGED` and
whose `pr_head` differs from `current_head`, the supervisor uses the guarded
follow-up branch recovery path instead of broad GitHub or raw `gh --head`
permission.

The recovery branch name is deterministic:
`<current-branch>-followup-<short-head-sha>`. The `git-integrator
create-followup-branch` wrapper refuses unless the worktree is clean, the source
branch is named and not `main`, `HEAD` already contains current `origin/main`,
the source and follow-up branch names satisfy the safe branch policy, and the
target follow-up branch is absent both locally and on `origin`.

The normal sequence is: create the follow-up branch through `git-integrator
create-followup-branch`, push the current branch through `git-integrator
push-current`, then create the current PR through `github-operator
create-current`. Preserve wrapper evidence such as `branch`, `current_head`,
`pr_head`, `pr_state`, and `pr_url` in handoffs. OpenCode must be restarted
after `.opencode/**` changes before relying on updated routing or capability
instructions.

### Capability preflight

Privileged Git, GitHub, and OpenCode configuration operations route through
capability agents and repo-local wrapper scripts, not through broad direct Git or
GitHub commands. Run `make opencode-check` before finishing integration work and
after merging or otherwise changing `.opencode/**` files so missing capability
agents, missing wrappers, or stale wrapper references are caught locally before
handoff.

If OpenCode or an agent reports a missing wrapper such as
`scripts/opencode_git_integrate.py`, the likely cause is branch/config skew: the
active OpenCode configuration references a capability file that is absent from
the checked-out branch. Update the branch from `origin/main` when permitted and
rerun the preflight rather than bypassing the capability boundary with direct Git
commands. After any `.opencode/**` change lands in the working tree, restart OpenCode
so the startup-loaded agents, skills, and permission rules match the repository
files.

## Validation continuation and current base

Required validation failures are active debugging work, not a terminal workflow
state. When a required suite fails, agents capture the failing command, failing
tests, relevant output, current branch state, and `git status --porcelain`;
invoke `systematic-debugging`; and continue investigating even when the failure
appears unrelated, flaky, timing-dependent, or environmental.

Repository fixes, generated-file repairs, and conflict resolutions go through
`implementer` → `reviewer` → pass before commit. Agents rerun validation from a
clean tree and proceed only when the required suite is green, or when systematic
debugging establishes a true human-input blocker such as missing credentials,
inaccessible infrastructure, an unsafe git-history decision, unreproducible
behavior after reasonable evidence gathering, or a product/API/data/architecture
choice.

Before final validation, PR creation, or a ready-to-merge claim, agents fetch
`origin` and evaluate the branch against current `origin/main`. If the branch is
behind, they use a safe merge from `origin/main` when permitted, route resulting
fixes through review, and rerun validation. Agents do not rebase or force-push
unless the human explicitly requests it.

## Branch and pull request policy

All agent-driven changes follow these branch and PR rules. The canonical source
repository is `https://github.com/semanticdreams/space2`.

### Pre-PR current-base validation

- Pull requests target `main`.
- Final validation and PR creation require a branch that is current with `origin/main`. Diff/base checks always use `origin/main`, not local `main`. Local `main` may be stale or contain unrelated local commits.
- Before final validation, PR creation, or a ready-to-merge claim, fetch `origin` and evaluate the branch against current `origin/main`. If the branch is behind, use a safe merge from `origin/main` when permitted, route resulting fixes through review, and rerun validation.
- Do not push directly to `main`. Always work on a feature branch and open a pull request.

### Post-PR merge queue

After implementation is complete — reviewed, committed, all tests passing, and
the tree clean — the default integration action is to push the current branch,
create a pull request targeting `main`, and enable auto-merge to hand the PR off
to GitHub's merge queue.

After the PR is open and queued, agents keep running and poll until the PR is
actually merged. Queue handoff alone is not success; success means the PR is
merged (`mergedAt` present or equivalent merged state).

Agents poll through `github-operator` wrapper actions such as `view-current`
and `poll-merge-queue-current`. The supervisor treats the wrapper JSON evidence
as the source of truth and does not run raw GitHub CLI polling commands.

The following states are non-terminal: `queued`, `waiting`, `pending`,
`in-progress`, `expected`, or `null`/missing conclusion on merge-group runs.

The following are actionable blockers: merge conflicts, failed required `test`
check, missing or disabled queue, permission failures, closed-unmerged PRs, and
queue timeouts.

- **Do not update the branch** solely because `origin/main` advanced. The
  merge queue's merge-group checks are the post-PR integration freshness gate.
- **Stale-branch update loops are forbidden.** The queue, not the agent, owns
  post-PR freshness.
- **Queue failures are actionable blockers.** Merge conflicts and merge-group
  required-check failures trigger `systematic-debugging`. Repository fixes follow
  the standard `implementer` → `reviewer` → pass flow. After reviewed fixes are
  committed, validation passes against current `origin/main`, and the branch is
  pushed, requeue the PR.
- If merge queue is not enabled or cannot be verified, agents report
  `HUMAN_DECISION_REQUIRED` with the exact GitHub setting needed and do not
  enter a stale-branch polling loop.

The `main` ruleset must actively require merge queue; a disabled ruleset that
contains merge_queue is not sufficient.

### GitHub admin requirement

A repository admin must enable merge queue for `main` in the GitHub branch
ruleset, ensure the required `test` check runs for merge-group candidates, and
relax any rule that forces every PR branch to be updated after `main` moves if
that rule blocks queue entry.

If required validation fails after implementation, review, or commit, see [Validation continuation and current base](#validation-continuation-and-current-base). Do not finish, push, create a PR, merge, or clean up the branch while validation is red.

## Exclusions

This shared Space guide intentionally does not document:

- Laptop-specific notify plugin setup — this varies across machines and is not a project requirement.
- The obsolete separate `opencode-config` repository as an active requirement — Space configuration lives in `.opencode/**` within the repository.
- Copying, migrating, or sharing `auth.json` — credential files are personal and should never be shared or checked into the repository.
