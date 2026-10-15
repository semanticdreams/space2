# Live development runtime

The process owns development control above the reloadable `main` application
root. The Linux checkout lifecycle CLI uses the runtime/provenance protocol
below. It never scans processes or probes legacy endpoints.

## User-selected live-dev primary

`supervisor` remains the default. Select the exact `live-dev` primary to edit,
debug, validate, refresh, and checkpoint directly on `live-dev/<topic>`. New topics
start from freshly fetched `origin/main`; preserve unrelated dirty work and do not
adopt unrelated commits. The exact fast-dev primary remains on `fast-dev/<topic>`.
Both have scalar `permission: allow` for appropriately isolated environments, not
a security sandbox; no other agent's permissions or process boundaries change.

Discover instances in this checkout/worktree before editing. Automatically start
a missing app with normal user data/settings only when no uncertain/unavailable
identity blocks startup. If more than one matches, ask the user to select even
if a saved preference exists. Establish `manual` mode and verify status before
editing: no filesystem watching and no hooks. After coherent validated changes,
explicitly reload the broad app root; native changes require rebuild/restart,
and preserved infrastructure requires restart. Reestablish manual mode after a
replacement. Never request confirmation for start, reload, rebuild, restart, or
transient state loss; instance choice is not lifecycle approval.

Inspect terminal operation results and current ready/fault/health evidence.
Retain both a failed reload and recovery outcome: recovery success never erases
the original failure. Diagnose/fix directly and revalidate before another refresh.
Use Space technical guidance and compile → constraints → focused-test order for
Fennel, without imported mandatory planning/worker/advisor/per-change review gates.

Ordinary completion and commit requests are **local only**: no push, PR, or
auto-merge until explicit user wrap-up/integration authorization. That authorization
loads the existing shared `fast-dev-wrap-up` skill and observational `fast-dev-reviewer`,
without switching primary or duplicating the lifecycle. Caller-prefix matching is
exact: live-dev uses only `live-dev/<topic>`, fast-dev only `fast-dev/<topic>`.
Wrap-up reviews every accumulated commit and final diff, fixes directly, revalidates,
then uses the protected PR/merge queue. Completion requires actual PR merge and
proof that its merge SHA is in freshly fetched `origin/main`; queue entry is not done.
See [OpenCode workflow](opencode-agent-workflow.md#fast-interactive-development-flow).

Restart OpenCode after `.opencode/**` changes to load the updated agents/skill.
Already-running sessions keep their loaded rules; this future live-dev exception
does not change an ongoing strict supervisor implementation/integration workflow.

## Checkout lifecycle CLI (Linux)

Run from the checkout/worktree you intend to develop, or supply its path:

```bash
python3 scripts/live_dev.py discover --repo-root .
python3 scripts/live_dev.py start --repo-root .
python3 scripts/live_dev.py select --repo-root . --instance <instance-id>
python3 scripts/live_dev.py status --repo-root .
python3 scripts/live_dev.py manual --repo-root .
python3 scripts/live_dev.py reload --repo-root . --timeout 30
python3 scripts/live_dev.py status --repo-root . --request-id <request-id>
python3 scripts/live_dev.py restart --repo-root .
python3 scripts/live_dev.py restart --repo-root . --rebuild
```

Every command emits JSON. Errors, ambiguity, failed operations, and timeout or
unverified outcomes exit nonzero. `discover` lists verified instances. Git
resolves the canonical checkout, including symlink aliases; sibling worktrees
have different private partitions. More than one instance requires an explicit
`--instance` or a still-valid saved selection. Candidate identities are returned
on ambiguity; the CLI never chooses arbitrarily. `select` saves only public
identity, verified again on each use. An explicit stale `--instance` remains an
error. A saved identity is a preference: only a proven dead/reused preference
may be discarded. With no candidates or blockers, `start` then launches and
saves the replacement; multiple remaining candidates still require selection.
A live but missing/unavailable saved identity blocks duplicate startup.

`start` holds a private checkout flock and discovers again before launching.
It launches only with no candidates and no unavailable/uncertain records. A
registered app that times out, has disabled RC, or cannot be controlled after
an update blocks duplicate startup. Only proven dead/reused kernel identities
are removed, and only their owned private socket can be cleaned up. A timeout
does not mean the app is absent.

New apps are persistent, detached `build/space -m main --remote-control=auto`
processes with ordinary build cwd and inherited user/display environment.
Normal user data/settings/audio are preserved: production launch does **not**
inject the test fixture's XDG or audio settings. Assets and Fennel/macro paths
are absolute and checkout-first (existing asset fallbacks are retained).
Stdout/stderr and build diagnostics go to private checkout logs. Startup wait
defaults to 30 seconds; `--timeout` controls bounded startup, operation, lock,
and shutdown waits. A timed-out launch may still exist; rediscover it rather
than assuming failure means absence. Remote subprocess waits include a short
client teardown allowance. Build subprocesses have a separate four-hour limit.

If the default runtime is missing, an existing CMake cache is built without
reconfiguration, preserving full/CEF/custom options. Only a checkout without
an existing cache gets the default Release/minimal/CEF-off configuration.
`restart --rebuild` requires the recorded native source to match this checkout,
and validates native build-cache source/profile/CEF provenance **before stop**.
It uses `cmake --build <recorded-build-root> --parallel <BUILD_JOBS-or-1>`;
it never forces an existing full/CEF configuration to minimal. A fixture with
copied Lua and a binary compiled elsewhere may reload/restart but not rebuild.

`manual` converts an existing watcher-enabled app without restarting it.
After coherent validated Lua/Fennel edits, `reload` explicitly reloads the
broad app root. It prefetches the private native recipe before requesting a
deferred operation, then polls its retained result. `status --request-id`
inspects the operation; acceptance alone is not success. Checkout mutations
serialize ID allocation/submission (including restart quit), and replies must
match instance, request ID and action. A conflicting deduplicated action is a
failure, never success or permission for recovery. Every operation RPC uses
the remaining original deadline; an expired status query cannot submit work.
Settings and process control survive reload; application runtime state follows the existing root
snapshot/restore contract.

Native changes require rebuild/restart. Changes to preserved control/reload
modules or `macros.fnl` require restart, not root reload (see boundary below).
Restart fetches the exact private native launch recipe before stopping,
requests deferred quit, waits for exit, and launches with the original
executable, argv, cwd, and environment. It verifies a new ready instance ID
while preserving other verified instances in the checkout; restarting selected
A never stops or mistakes healthy B for a replacement conflict.
The peer authorization set is captured before waiting for restart ownership
(or before the reload that may require recovery) and checked again under the
lock. A replacement/newcomer cannot be adopted as a preauthorized peer, so a
stale concurrent restart cannot launch a second replacement. A verified target
exit can still be recovered when that original peer authorization is unchanged.
Restart peer checks do not require RC from the exact selected recovery target:
its full recorded metadata and kernel executable identity must match instead.
All other uncertain/unavailable registrations remain blockers.
Escalation uses a held, identity-verified pidfd where supported; without one,
the CLI refuses PID-only signaling. Kernel executable identity is verified at
handle acquisition and before escalation; an exec to another image is never
signaled as the old app. An unlinked old image is accepted only when its
recorded inode/stat still match `/proc/<pid>/exe`. No guessed recipes or
confirmations for start, reload, rebuild, restart, or transient state loss are used.

A faulted or unverified reload permits at most one recovery restart. Successful
recovery does **not** turn the failed reload into success: output retains both
`reload` diagnostics and `recovery` outcome, with nonzero exit. A healthy
rollback remains a failed reload without unnecessary restart. A
`restart-required` boundary rejection likewise leaves the current process
running until an explicit restart.

### Privacy and isolated validation

Launch recipes contain secrets. They remain in native memory and transient CLI
memory, never registry/selection files or CLI output/errors. The native recipe
uses `argv`; public verified identity supplies build provenance. Do not publish
recipes, inspect process environments/argv, or enable RC on untrusted endpoints.
Registry, selection, and lifecycle logs are owner-only (0700 directories,
0600 files). `make run` now uses private auto endpoints; explicitly supplied
`--remote-control=ipc://...` or other existing endpoints still take precedence.

Focused validation:

```bash
python3 -m pytest scripts/tests/test_live_dev.py -q
# After runtime freshness, Fennel compile, and repo constraints:
xvfb-run -a ctest --test-dir build -R '^space_live_dev_integration$' --output-on-failure
make test-live-hot-reload
```

The Linux `space_live_dev_integration` CTest requires the constraints fixture.
It runs the actual normal main in a temporary Git checkout, not a user's app:
copied Lua, linked supplied binary, fallback non-code assets, isolated
HOME/XDG/config/cache/runtime/log paths, disabled audio and core dumps. Copied
main installs the fixture-only offline reporting initializer **before** normal
startup can initialize reporting; tests also query the native disabled state.
Its test-only CLI observer transfers actual app-spawn kernel provenance and a
held pidfd over a private Unix socket before waiting for publication. Launch
intent is recorded before spawning; a pre-publication hang is terminated by
that verified handle, and any unaccounted launch fails cleanup explicitly with
artifacts retained. No recipe argv/environment is persisted by the observer.
Native startup unit cases run in a temporary checkout and isolated private
runtime root with real allocation/protection/publication; Linux-only cases do
not allocate on Windows.
It never reads crash dumps or attaches to a user registry/source. A missing
display is a diagnosed failure, not a skip. Python unit tests are included in
`make opencode-check`; these are not a replacement for actual app coverage.

## Ownership and scheduling

Normal startup starts the engine, starts one `live-dev-runtime` coordinator,
initializes the root, checks its current `app.check-runtime-health()` method,
and marks the instance ready before entering the engine loop. Finalization
attempts root drop, coordinator stop, and engine shutdown in that order, even
when initialization, readiness, running, or an earlier finalizer throws. Errors
are surfaced, including additional cleanup errors.

`app.remote-control`, `app.remote-control-endpoint`, and
`app.hot-reload-controller` are borrowed inspection references. Root init/drop
must not reset, construct, poll, or destroy these process-owned objects.
The coordinator re-enqueues one native callback after polling at most one RC
message. Mutations run in a separate callback only after acceptance/reply has
unwound. Native callback dispatch takes a snapshot, so newly queued operations
yield to the next dispatch even at zero FPS. `app.next-frame` is not involved.

`manual` disables watching and clears queued watcher work. `reload` explicitly
reloads the broad app root using the existing transactional reload controller.
Watching remains optional for ordinary development (`SPACE_HOT_RELOAD`); manual
mode does not acquire a watcher on root reinitialization.

Ordinary watcher requests use structured `reload-pending!` with the canonical
[reload boundary contract](../reloadable-units.md): owned paths select a candidate,
then `narrow-reload-unit-ids` determines eligibility before module collection or
lifecycle mutation. Omitted/empty means app-root only; built-in children are never
silently opted in. Set `app.hot-reload-config.narrow-reload-unit-ids` before
process control starts to opt an audited child in. The coordinator forwards this
list and discovers children from the current root's manager on each transaction.
Explicit live-dev `reload` always uses `reload-root!`, regardless of that list.
Watcher child success is health checked but does not advance root generation.

Health checks resolve the *current* root method after reload and require the
engine, initialized root services, and required root subscription references.
Only health-checked successful root initialization advances `generation`.
Snapshot/load failure with a healthy restored root does not advance it. Failed
rollback, health failure, or an unexpected controller failure latches a fault:
root updates and controller updates are suppressed, but RC/status/quit remain
available. A fault requires process recovery rather than more root mutations.

## Native launch provenance and private registry

`app-config.live-dev` contains a native bootstrap. Before dotenv, logging, and
audio change the environment, native startup captures cwd, executable, argv
excluding argv[0], and the exact inherited environment. The private launch
recipe remains in native memory; registry/status never contain argv or env.

`describe-source(path)` canonicalizes the Fennel-resolved main source and finds
its nearest enclosing `.git` directory **or file**. Thus worktrees are distinct
checkouts. Runtime `source-root`/`checkout-root` are independent of the compiled
`native-source-root`/`native-build-root`, build profile and CEF flag. Identity is
self-only: PID, UID, Linux boot ID, process start ticks, executable and executable
file identity. No legacy-process discovery or process enumeration is used.

On Linux checkout runs, `private-paths(checkout, instance-id)` allocates:

```
<base>/<checkout-key>/instances/<instance-id>.json
```

Base is an owned mode-0700 `space-live-dev` directory below mode-0700
`XDG_RUNTIME_DIR`, or `/tmp/space-live-dev-<uid>` when unset/too long for a socket.
Unsafe ownership, permissions and symlinks are rejected. Child directories are
0700; records and atomic-write temporary files are protected as 0600.
Endpoints use short random socket names directly under the private base.
An explicit `--remote-control` endpoint continues to take precedence.

Checkout key is UUIDv5 in the URL namespace for
`"space-live-dev:" + canonical-checkout`. Python-compatible vector:

```python
uuid.uuid5(uuid.NAMESPACE_URL, "space-live-dev:/example/checkout")
# dc103dda-5118-536d-9064-deb650dfc937
```

Publication uses `json-utils` atomic writes. Cleanup removes the instance's
record. Non-Linux/non-checkout runs retain ordinary app/RC operation and do not
publish Linux registry records. An absent transport is explicitly `false`.

## Schema version 1

All JSON keys are hyphenated. Registry records and `status` contain:

- `schema-version` (1), `instance-id`, `checkout-root`, `source-root`, `main-source`;
- `pid`, `uid`, `boot-id`, `process-start` (Linux start-tick string), `executable`;
- `native-source-root`, `native-build-root`, `build-profile`, `cef-enabled`;
- `endpoint` (string or false), `ready`, `mode` (`watch` or `manual`), `generation`;
- `capabilities`, `next-request-id`, `faulted`, and an error when faulted.

Linux-only identity/checkout fields are absent when unavailable. The native
descriptor additionally supplies `executable-identity` for restart checks.

`live-dev-runtime.rpc(request)` requires `expected-instance-id` on **every**
request, including read-only queries. Supported actions:

- `status`: public instance state;
- `operation` with `request-id`: retained operation state;
- `launch-recipe`: private executable/cwd/argv/environment (trusted RC only);
- `manual`, `reload`, `quit` with numeric `request-id`: deferred operation.

Acceptance returns `pending`, not completion. Poll `operation` afterwards.
Operations contain `request-id`, `action`, `instance-id`, `generation`, `status`
(`pending`, `running`, `succeeded`, `failed`), `phase`, `error`, `rollback`,
`rollback-error`, and `recovery-required`. Error fields are false when absent.
Retained duplicate IDs return the existing operation without executing again.
Overlap is rejected. Per-instance IDs are positive safe integers increasing
above a high-water mark; only the newest 64 terminal results are retained.
Expired IDs are rejected even after their result has been evicted. Restarting
creates a new instance ID and ID space.

## Restart-required boundary

`live-dev-runtime.preserved-modules` is the authoritative fixed list:
`live-dev-runtime`, `remote-control`, `fennel-evaluator`, `hot-reload`, `units`,
`fennel-cache`, `path-utils`, `json-utils`, `fennel`, and retained `cli-args`.
Their resolved source paths/bytes, `macros.fnl`, and native executable identity
are retained at startup. Explicit mutation checks compare them again; changes
fail with phase `restart-required` instead of reloading stale control code.
Quit remains available. There are no background infrastructure checks, filesystem
watchers in manual mode, or generalized dependency graph.
