# SSH Integration Foundation Design

## Summary

Space will add a reusable SSH foundation for the broader Space ecosystem. The
foundation provides stable C++ and Lua/Fennel APIs for SSH client transport work
now, while preserving a credible path for later Space-as-SSH-server, jump-host,
or control-plane features. The selected implementation uses `libssh` as the
primary embedded backend because it supports both client and server use cases,
has the required channel/SFTP/tunnel/auth primitives, and its LGPL dependency is
acceptable for this project.

The public API must be Space-owned rather than a direct `libssh` binding. Native
headers and Lua/Fennel modules expose backend-neutral sessions, operations,
channels, tunnels, events, and policy hooks. `libssh` remains isolated behind a
backend interface so independent Space-based apps can rely on stable APIs and so
future backends, mocks, OpenSSH subprocess compatibility, or server mode can be
added without replacing app code.

## Goals

- Provide first-class public SSH APIs for both C++ and Lua/Fennel consumers.
- Support independent Space-based apps, not only the main Space app.
- Implement a full phase-1 transport foundation: connect/auth/session lifecycle,
  known-host policy hooks, command execution with streaming output, SFTP
  upload/download, cancellation/timeouts, interactive shell channels, local and
  remote tunnels, SSH agent/private-key/password auth, parallel/fleet execution,
  and structured per-host results.
- Preserve a future path for Space to act as an SSH server, jump host, or remote
  control plane without redesigning the public vocabulary.
- Design cross-platform APIs from day one while implementing and validating on
  Linux first.
- Let each app choose host-key and credential policy. The core supplies policy
  hooks and safe defaults, while the Space main app can implement OpenSSH-like
  onboarding and automation apps can choose explicit fleet policies.
- Keep errors loud and structured. Unknown hosts, changed host keys, auth
  failures, unavailable backends, timeouts, cancellation, and channel/tunnel
  failures must not become silent no-ops.

## Non-goals

- No Space SSH server or jump-host implementation in phase 1.
- No main Space UI for SSH host onboarding in this slice.
- No promise of Windows or macOS runtime validation in phase 1, beyond keeping
  the public API and backend boundary cross-platform-ready.
- No direct public exposure of `libssh` handles, types, constants, or callback
  conventions.
- No SCP, rsync, X11 forwarding, GSSAPI/Kerberos, hardware-token UX, OpenSSH
  config emulation, or long-term secret storage in phase 1.
- No credential material in URLs, logs, structured errors, or operation result
  tables.

## Existing Context

- Native modules live under `src/` and are linked into the Space engine library
  through the existing CMake structure.
- Lua bindings use Sol2 and typically expose modules through `package.preload`,
  with binding installers called by `LuaRuntime::install_base_bindings()`.
- Existing native async integrations such as HTTP, process, keyring, callbacks,
  and the engine run loop provide patterns for native handles, polling, callback
  dispatch, and shutdown cleanup.
- `process` and terminal APIs can already invoke external programs, but process
  wrapping is not a sufficient foundation for structured SSH sessions, host-key
  policy, SFTP, channel lifecycle, or tunnels.
- A cross-platform keyring abstraction exists and can be used by app-level
  credential flows, but the SSH core itself must not persist secrets.
- No comprehensive SSH module currently exists. Existing SSH-specific behavior is
  limited to parsing remote repository URLs and rejecting embedded credentials.

## Evaluated Approaches

### Option A: Wrap the OpenSSH CLI

Wrapping `ssh`, `sftp`, and related OpenSSH tools would provide excellent
operational compatibility and reuse existing user configuration. It would also
inherit mature OpenSSH behavior for jump hosts, agents, known-hosts, forwarding,
and server operation.

This is not the selected foundation. Process wrapping makes structured sessions,
streaming events, cancellation, prompt handling, credentials, quoting, cross-
platform packaging, and error classification harder to make reliable. It should
remain available as a later compatibility or diagnostic backend, not the primary
API contract.

### Option B: Bind `libssh` directly to Lua/Fennel

Direct bindings would be faster to prototype and expose most needed primitives.
However, that would leak `libssh` concepts into app APIs, couple independent
Space apps to LGPL/backend details, and make future server-mode or alternate
backend work a breaking migration.

This is rejected. The public API must be Space-owned and backend-neutral.

### Option C: Backend-isolated Space SSH service using `libssh`

This approach creates C++ SSH types and a service façade with no public `libssh`
types. A `libssh` backend implements the transport. Lua/Fennel bindings expose
the same Space concepts through a stable `ssh` module, and a thin Fennel fleet
layer builds parallel host operations on top.

This is the selected approach. It fits existing Space native binding and dispatch
patterns, supports fake-backend tests, isolates `libssh`, and preserves the path
to OpenSSH fallback or future server/jump-host backends.

## Dependency Decision

Use `libssh` as the primary backend. It is preferred over `libssh2` because the
project explicitly wants a future server/jump-host path, and `libssh2` is a
client-focused library. `libssh` also covers the required phase-1 capabilities:
channels, command execution, shell sessions, SFTP, local/reverse forwarding,
known-host APIs, agent/private-key/password authentication, nonblocking behavior,
and server-side APIs for future work.

The LGPL license is acceptable. Public Space headers must not expose `libssh`
types, and build documentation must make the dependency explicit. If packaging or
CI later requires a minimum version floor, choose one based on the oldest Linux
distribution version Space intends to support and document it in developer docs.

## Architecture

### Native layers

Add a `space::ssh` namespace with three layers:

1. **Public types**: backend-neutral structs/enums for targets, auth methods,
   known-host challenges, operation options, events, structured errors, session
   IDs, channel IDs, tunnel IDs, and operation IDs.
2. **Backend interface**: an abstract `Backend` with methods for connect,
   known-host resolution, close, exec, SFTP, shell/channel control, tunnels,
   cancellation, polling, and shutdown.
3. **Service façade**: a `Service` that owns a backend, generates stable IDs,
   validates requests, preserves poll ordering, exposes a simple C++ API, and is
   the only object consumed by the Lua binding.

Only the backend implementation includes `libssh` headers. The default backend
is `libssh` when the dependency is available and the feature is enabled. Builds
without SSH support still compile and return structured unavailable-backend
errors through the same API.

### Runtime and dispatch model

SSH operations are asynchronous from the Lua/Fennel caller perspective. Native
worker code performs blocking or nonblocking `libssh` work off the main Lua
thread, then queues events. The Space run loop and callback dispatch poll the
SSH service similarly to existing HTTP/process integrations.

Every long-running operation has an operation ID and supports cancellation and
timeouts. Operation terminal states are explicit: success, error, timeout,
cancelled, or closed as appropriate. Shutdown cancels pending work, closes
sessions/channels/tunnels, joins workers, and prevents callbacks after the
runtime has dropped the service.

### Policy model

The SSH core is policy-driven. It defaults to rejecting unknown or changed hosts
unless a caller supplies a policy decision. It emits a structured known-host
challenge containing the host, port, username when relevant, key type,
fingerprint, known-hosts source, and reason. The app responds with one of:

- reject
- accept once
- accept and store

The Space main app can implement OpenSSH-like first-use onboarding on top of
this hook. Automation apps can preseed known-hosts files, pin fingerprints, use
cloud metadata, or deliberately opt into permissive ephemeral-host policies. The
core must make insecure choices explicit in options and events.

### Public C++ API shape

The exact implementation may refine field names, but the public C++ surface must
be centered on stable Space concepts:

- `Target { host, port, username }`
- `AuthMethod { type, key_path, passphrase, password }` where secrets are never
  included in events or logs
- `ConnectOptions { target, auth_methods, known_hosts_path, timeout_ms,
  known_host_policy }`
- `ExecOptions { command, env, timeout_ms }`
- `SftpTransferOptions { local_path, remote_path, timeout_ms }`
- `ShellOptions { request_pty, term, cols, rows, timeout_ms }`
- `TunnelOptions { local_host, local_port, remote_host, remote_port,
  timeout_ms }`
- `Event { kind, operation_id, session_id, channel_id, tunnel_id, fields,
  error_code, message }`
- `Service` methods for connect, resolve known host, close session, exec, SFTP
  upload/download, open shell, channel write/resize/close, open/close tunnels,
  cancel, poll, and shutdown.

IDs are opaque integers scoped to the service. Public headers expose no backend
handles and no `libssh` symbols.

### Public Lua/Fennel API shape

Expose `require("ssh")` as the native Lua module. Functions use canonical
kebab-case keys only and reject malformed options loudly:

- `connect(opts[, callback])`
- `resolve-known-host(operation-id, decision)`
- `close-session(session-id)`
- `exec(session-id, opts[, callback])`
- `sftp-upload(session-id, opts[, callback])`
- `sftp-download(session-id, opts[, callback])`
- `open-shell(session-id, opts[, callback])`
- `channel-write(channel-id, data)`
- `channel-resize(channel-id, cols, rows)`
- `channel-close(channel-id)`
- `open-local-tunnel(session-id, opts[, callback])`
- `open-remote-tunnel(session-id, opts[, callback])`
- `close-tunnel(tunnel-id)`
- `cancel(operation-id)`
- `poll([max-results])`

Create `assets/lua/ssh/init.fnl` as a thin Fennel façade that re-exports the
native module without changing key names, and `assets/lua/ssh/fleet.fnl` for
parallel host execution. Fleet results contain host, port, username, ok,
exit-status, stdout, stderr, error-code, error, and duration-ms. The fleet layer
honors concurrency limits, cancellation, per-host timeouts, and the caller's
known-host policy.

## Feature Behavior

### Connection and authentication

Callers provide ordered auth methods. The backend attempts them in order and
returns structured auth errors without secrets. Supported phase-1 methods are
agent, private-key path with optional passphrase, and password. Apps may use the
existing keyring module to retrieve secrets, but the SSH core does not store
credentials.

### Command execution

Exec operations stream stdout and stderr as events and finish with exactly one
terminal result carrying the remote exit status or a structured failure. Cancels
close the remote channel and emit cancellation.

### SFTP

SFTP upload/download operations report progress when total size is known and
surface local filesystem, remote filesystem, timeout, and cancellation failures.
Byte-preserving transfer is part of the acceptance criteria.

### Interactive shell channels

Shell channels support optional PTY allocation, writes, resize, close, and
output events. Unknown or closed channel IDs fail explicitly.

### Tunnels

Local tunnel APIs open a local listener and forward accepted connections through
SSH to a remote host/port. Remote tunnel APIs request remote forwarding and relay
accepted connections back to a local host/port. If a platform/backend cannot
support a tunnel shape, the operation emits a structured unsupported/error event.

### Fleet operations

Fleet helpers are a convenience layer, not a separate transport. They compose the
public SSH API to connect and execute across hosts with bounded concurrency,
structured per-host results, cancellation, and no hidden trust policy.

## Error Handling and Observability

- All failures include a stable error code and human-readable message.
- Secret fields are redacted from logs, errors, and result tables.
- Unknown hosts, changed host keys, failed auth, unavailable backend, malformed
  options, invalid IDs, tunnel bind failures, file transfer failures, timeouts,
  and cancellation are observable.
- Public APIs never convert required data or failed operations into quiet
  success.
- The SSH service must clean up remote channels, local sockets, workers, and
  queued callbacks during shutdown.

## Testing Strategy

- Unit-test the backend-neutral service with a fake backend: ID generation, poll
  ordering, unavailable backend errors, known-host challenge flow, cancellation,
  and timeout behavior.
- Test the Lua binding with a fake service/backend: module shape, option
  validation, event table fields, callback dispatch, and known-host policy
  resolution.
- Add Fennel tests for the façade and fleet helpers without requiring an
  external SSH server in the fast suite.
- Add Linux-first integration tests behind feature/fixture detection using a
  disposable local OpenSSH server or equivalent fixture: private-key auth,
  reject/accept known-host flow, exec stdout/stderr/exit status, SFTP
  upload/download byte equality, shell channel interaction, local tunnel relay,
  remote tunnel when fixture permits, and cancellation.
- Run Fennel compile and constraints checks for touched Fennel files, targeted
  native tests, focused Fennel tests, and broader `make test` because this work
  touches CMake, native bindings, runtime dispatch, async networking, and
  security-sensitive behavior.

## Future Server and Jump-Host Path

Phase 1 reserves shared vocabulary for sessions, channels, tunnels, events,
known-host/client identity policy, and structured errors. Later server work can
add listener/session-accept APIs using the same concepts without changing client
callers. The backend interface should remain general enough to support inbound
server sessions, jump-host routing, and policy callbacks for authenticating
remote clients, but no server behavior is implemented in this phase.

## Acceptance Criteria

- `libssh` is selected and isolated behind a backend interface.
- Public C++ SSH headers expose no `libssh` types.
- `require("ssh")` exposes the documented stable Lua API.
- C++ and Lua/Fennel callers can connect, authenticate, handle known-host
  challenges, exec commands with streaming output, transfer files via SFTP, use
  interactive channels, open tunnel APIs, cancel operations, and poll events.
- Unknown or changed host keys are never silently accepted by the core.
- App-specific host-key policies are supported without hard-coding the Space main
  app's onboarding policy.
- Fleet execution returns structured per-host results and honors concurrency,
  timeouts, and cancellation.
- Builds without SSH support fail loudly through structured unavailable-backend
  errors rather than missing modules or silent no-ops.
- Linux integration tests cover real SSH behavior when fixture dependencies are
  available.
