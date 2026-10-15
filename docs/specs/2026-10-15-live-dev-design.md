# Live development with explicit app-root reload

## Intent and approved direction

Add a user-selected `live-dev` primary similar to `fast-dev`, intended to edit
Space while the desktop application remains running. The agent decides when a
coherent edit is ready, validates it, explicitly refreshes the application, and
verifies the result. Filesystem changes must never trigger reload in this mode.

The user approved a small process-lifetime control layer above the reloadable
app root. Reuse the existing reload transaction rather than build another
reloader. This is one connected feature: runtime control, instance lifecycle,
and the agent consuming those interfaces.

## Global constraints

- Linux first.
- Scope instance discovery and actions to the current checkout/worktree.
- Ask the user to select an instance when more than one matching app exists.
- Automatically start a missing app using normal user data/settings.
- Never request confirmation for start, reload, rebuild, restart, or transient state loss.
- Explicitly trigger broad app-root reload after coherent validated changes; no filesystem watching in live-dev mode.
- Rebuild/restart for native changes; restart for changes to preserved reload/control infrastructure.
- Keep direct edits and local commits on `live-dev/<topic>`; no publishing until explicit wrap-up authorization.
- Keep `supervisor` as the default primary and preserve unrelated agent boundaries.
- No legacy-instance compatibility or migration machinery.

The user will not be doing active work while the agent operates. Absence of
lifecycle confirmation does not authorize guessing between multiple instances,
discarding unrelated source changes, unsafe Git operations, or hiding failures.

## Architecture

### Process-lifetime control

Introduce a focused Fennel coordinator owned by the process, not by the app
root. It owns instance identity, remote-control transport, operation status,
and deferred reload scheduling. The engine/process and this coordinator survive
an app-root reload. The app root continues to own worlds, UI, and ordinary
application services. Final process shutdown explicitly drops persistent
resources exactly once.

Retain the existing unit snapshot/unload/invalidate/load/restore and rollback
transaction. Separate the watcher event source from execution: manual mode
constructs no watcher and explicitly selects the root, regardless of narrower
unit ownership. Existing opt-in watcher workflows outside live-dev remain
supported. Attaching live-dev must establish manual mode before editing.

Move remote-control ownership out of root teardown and avoid duplicate tick
subscriptions or resetting persistent coordinator references during module
evaluation. A request is acknowledged before reload begins; execution happens
after the request handler unwinds. Control polling and deferred execution must
continue when rendering/engine ticks are idle. Use the existing native callback
pump where appropriate rather than adding a new background daemon.

Operation IDs and terminal results survive reload. A successful request reply
only means accepted: success requires completed root initialization/restoration
and a health check. Expose failure, rollback outcome, generation, and process
identity so the agent can distinguish success, failed reload, unverified
timeout, and process replacement. Repeated polling must not cause another
reload. Reuse of a request ID must not execute the transaction twice.

### Instance discovery and Linux lifecycle tooling

Provide a small repository CLI for discovery, start, explicit reload, status,
and restart. Return machine-readable results and nonzero exit status for
failures or unresolved ambiguity. Use the existing remote-control transport;
do not introduce another network service.

Updated app instances publish atomic, per-user instance records with canonical
checkout/source identity, instance ID, PID/process-start identity, endpoint,
capabilities, and readiness. Store records and IPC endpoints in an appropriate
private user runtime directory; endpoints must be unique per instance. Do not
identify worktrees by branch name or shared Git common directory. Do not
publish credentials or environment dumps.

Verify process identity and the live control handshake before acting. Endpoint
timeout is not proof of process death. Remove only proven-stale owned records;
PID reuse, another worktree, malformed records, or an unrelated endpoint must
never lead to signaling the wrong process. Multiple candidates are returned
for user selection, not silently resolved by recency. Remember an explicit
selection for subsequent commands while verifying it remains the same process.

No compatibility scanning or special migration for old, unregistered apps is
required. The user will update and relaunch those apps. Updated instances with
missing or unavailable control capability are reported explicitly rather than
treated as absent and replaced by a duplicate.

Start the visible app persistently, independently of the short-lived tooling
process, with normal user settings, desktop environment, and file-backed logs.
Serialize launch decisions within a checkout to avoid duplicate auto-starts.
Use unique endpoints for ordinary development startup as well as agent startup,
while retaining foreground behavior for ordinary `make run`.

For restart, establish the selected process's verified launch recipe before
stopping it: executable, argument array, working directory, relevant launch
environment, and build configuration. Retain sensitive launch context privately
or in memory rather than exposing it in discover output or logs. Preserve
normal/full build profiles rather than silently replacing one with a minimal
build. A restart succeeds only after the old identity exits and a new matching
instance is ready. Refuse an unverifiable restart with diagnostics; do not ask
for broad process permissions or guess a replacement recipe.

### Agent workflow and integration

Add `.opencode/agents/live-dev.md` with the same direct-development autonomy as
fast-dev and an exact identity-scoped process/permission exception. Keep
technical Space skills and validation guidance. Do not relax other agents.

The interactive loop is: discover/select/start; establish manual mode; edit;
run risk-appropriate checks; request root reload or rebuild/restart; verify
terminal outcome and application health; make coherent local checkpoints.
Failed checks do not trigger reload. Reload machinery and its preserved
dependencies are part of the restart-required boundary even when Fennel.

On reload failure, retain diagnostics, diagnose and fix, then retry or restart
without confirmation. If rollback also fails, capture evidence before a bounded
recovery restart. Do not hide failure behind a successful restart, claim an
unverified reload succeeded, or introduce an endless automatic recovery loop.
Report an actual blocker when evidence or access is insufficient.

Reuse the existing explicit-wrap-up skill and observational whole-branch
reviewer, extending their named callers and branch matching to live-dev rather
than copying integration logic. Ordinary completion and commit requests remain
local-only. Wrap-up retains fetched `origin/main` checks, required validation,
review and direct fixes, PR/merge-queue monitoring, and actual merge evidence.
Restart OpenCode to load the new agent and changed skills.

## Alternatives considered

1. Persistent Fennel control outside app root: selected; reliable request and
   completion lifetime with targeted ownership refactoring.
2. Root-owned control plus disconnect/reconnect and external operation journal:
   rejected because initialization failure and rollback complicate evidence.
3. Always restart, or introduce a native supervisor: rejected respectively for
   losing in-process reload and for unnecessary scope/dependency growth.

## Validation and acceptance

- Manual mode neither constructs nor polls a filesystem watcher; edits alone
  never reload. Existing watcher behavior remains covered outside this mode.
- An explicit root reload refreshes edited app behavior without changing PID
  or losing the persistent control channel; repeated reloads do not leak owners.
- Control works during idle/zero-FPS operation. Request acknowledgement occurs
  before teardown, and success is recorded only after initialization/restore.
- Cover reload and rollback failures, snapshot failures, duplicate IDs,
  overlapping requests, timeouts, and final shutdown.
- Cover checkout identity, sibling-worktree exclusion, symlinks, stale records,
  PID reuse, endpoint mismatch, launch races, multi-instance selection, start,
  and restart with arguments/build profile preserved.
- Real-app coverage verifies edited behavior after reload and new identity after
  restart, with isolated test settings and no dependency on the user's app.
- Exact live-dev permission/policy tests retain fast-dev behavior and reject
  lookalike broad-permission agents. Exercise local-only and wrap-up prompts
  without publishing demo branches.
- Build before testing native/bootstrap changes. Run Fennel compile checks,
  constraints, focused runtime tests, focused Python/policy tests, real-app
  coverage, and the full suite because startup/root lifetime is high risk.
- Report constraint impact, commands/results, `git diff --check`, and required
  integration evidence. Register new integration coverage in the actual suite.

## Non-goals

Filesystem watching in live-dev mode; finer-grained reload selection; replacing
the Lua VM/engine during reload; guaranteed preservation of transient UI state;
remote-machine discovery; Windows/macOS launcher support; legacy-process
inspection/migration; a general supervisor framework; crash-recovery watchdogs;
new dependency-graph invalidation; duplicated wrap-up workflows.
