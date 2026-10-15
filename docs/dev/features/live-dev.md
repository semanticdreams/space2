# Live development runtime

The process owns development control above the reloadable `main` application
root. This document describes the runtime/provenance protocol; the checkout
lifecycle CLI and primary-agent workflow build on this protocol separately.

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
