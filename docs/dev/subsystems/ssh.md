---
type: subsystem
tags:
  - subsystem
  - ssh
  - networking
created: 2026-10-04
---

# SSH subsystem

Space owns a backend-neutral SSH transport service for asynchronous SSH client operations. The public C++, Lua, and Fennel APIs expose Space concepts and structured events rather than `libssh` handles or callback conventions.

## Layers

- `src/ssh_types.h` defines Space-owned IDs, options, events, errors, known-host policy values, and transfer/tunnel concepts.
- `src/ssh_service.*` owns operation lifecycles, opaque session/channel/tunnel IDs, cancellation, timeouts, event queues, and handle bookkeeping.
- `src/ssh_backend.h` is the backend boundary. Public Space headers do not expose `libssh` types.
- `src/ssh_backend_libssh.cpp` implements the real backend when `libssh` is found.
- `src/ssh_backend_unavailable.cpp` preserves the same API when no backend is compiled and reports `unavailable-backend` errors.
- `src/lua_ssh.*` binds the native `ssh` Lua module. `assets/lua/ssh/init.fnl` is the thin Fennel require façade, and `assets/lua/ssh/fleet.fnl` adds fleet exec helpers.

## Build dependency

SSH support is optional and controlled by `SPACE_ENABLE_SSH` (default `ON`). CMake discovers `libssh` through pkg-config. If `libssh` is unavailable, Space still builds and the SSH API returns structured `operation-error` events with `error-code="unavailable-backend"`.

## Public C++ concepts

- `OperationId` identifies every long-running operation.
- `SessionId`, `ChannelId`, and `TunnelId` are opaque Space IDs allocated by the service.
- `ConnectOptions` includes `target`, `auth_methods`, `known_hosts_path`, `known_host_policy`, and `timeout_ms`.
- `ExecOptions`, `SftpTransferOptions`, `ShellOptions`, and `TunnelOptions` describe backend-neutral operations.
- Terminal states are explicit: `operation-success`, `operation-error`, `operation-timeout`, `operation-cancelled`, and close-specific events where applicable.

## Lua API

The native `ssh` module uses canonical kebab-case keys only and rejects malformed or unknown options loudly.

- `connect(opts[, callback]) -> operation-id`
- `resolve-known-host(operation-id, decision) -> boolean`
- `close-session(session-id) -> operation-id`
- `exec(session-id, opts[, callback]) -> operation-id`
- `sftp-upload(session-id, opts[, callback]) -> operation-id`
- `sftp-download(session-id, opts[, callback]) -> operation-id`
- `open-shell(session-id[, opts][, callback]) -> operation-id`
- `channel-write(channel-id, data) -> operation-id`
- `channel-resize(channel-id, cols, rows) -> operation-id`
- `channel-close(channel-id) -> operation-id`
- `open-local-tunnel(session-id, opts[, callback]) -> operation-id`
- `open-remote-tunnel(session-id, opts[, callback]) -> operation-id`
- `close-tunnel(tunnel-id) -> operation-id`
- `cancel(operation-id) -> boolean`
- `poll([max-results]) -> events`

Important option keys include `target.host`, `target.port`, `target.username`, `auth-methods`, `type`, `key-path`, `passphrase`, `password`, `known-host-policy`, `known-hosts-path`, `timeout-ms`, `command`, `env`, `local-path`, `remote-path`, `request-pty`, `term`, `cols`, `rows`, `local-host`, `local-port`, `remote-host`, and `remote-port`.

## Known-host policy

The default policy is `reject`: unknown or changed host keys fail with structured errors such as `unknown-host` or `changed-host-key`. Callers can request `ask` to receive a `known-host-challenge` and then call `resolve-known-host` with `reject`, `accept-once`, or `accept-and-store`. `accept-and-store` updates the configured known-hosts file.

## Credentials and errors

Credential material must not appear in URLs, logs, structured errors, or result tables. Event fields are redacted by the binding, and fleet helpers redact configured passwords/passphrases from returned error strings.

## Cancellation and timeouts

Every long-running operation returns an operation ID. Callers can cancel with `ssh.cancel`, and per-operation `timeout-ms` values produce explicit timeout terminal states. Cancellation reports `operation-cancelled` with `error-code="cancelled"`.

## Fennel fleet helper

`(require :ssh.fleet)` exposes `exec` and `cancel`. `ssh.fleet.exec` accepts a host array plus `{ :command ... :concurrency ... :timeout-ms ... :env ... }` and returns one result per host with `host`, `port`, `username`, `ok`, `exit-status`, `stdout`, `stderr`, `error-code`, `error`, and `duration-ms`.

## Integration fixture

CTest target `space_ssh_integration` runs a disposable local OpenSSH server when `sshd`, `ssh-keygen`, and `ssh-keyscan` are available:

```bash
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ctest --test-dir build -R space_ssh_integration --output-on-failure
```

The fixture creates all files under `/tmp/space/tests/ssh-fixture-*`, generates ephemeral user and host keys, supplies fixture environment variables to `tests.test-ssh-integration:main`, including positive preallocated local and remote tunnel listen ports, and exits successfully with a clear skip message only when OpenSSH tools are unavailable. After the tools are present, fixture startup failures are reported as nonzero errors.

## Phase 1 non-goals

Phase 1 does not implement a Space SSH server, jump hosts, SCP, rsync, X11 forwarding, GSSAPI/Kerberos, hardware-token UX, OpenSSH config emulation, long-term secret storage, or main UI onboarding for SSH hosts.
