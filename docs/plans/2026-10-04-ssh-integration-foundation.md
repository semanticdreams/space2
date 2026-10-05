# SSH Integration Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Space-owned SSH client transport APIs across C++, Lua, and Fennel with an isolated `libssh` backend, async operations, fleet helpers, tests, fixture support, and developer docs.

**Architecture:** Add a backend-neutral `space::ssh` C++ service with opaque IDs, structured events/errors, and an abstract backend boundary. Implement `libssh` behind that boundary when available, while preserving a compiled unavailable-backend path. Expose the service through a native Lua `ssh` module, thin Fennel façade/fleet helpers, and runtime dispatch hooks that follow existing callback/poll patterns.

**Tech Stack:** C++17, Sol2 Lua bindings, Space Fennel under `assets/lua`, `libssh` via pkg-config when available, OpenSSH fixture tools for Linux integration validation.

## Global Constraints

- Use `libssh` as the primary backend.
- The public API must be Space-owned rather than a direct `libssh` binding.
- Public Space headers must not expose `libssh` types, and build documentation must make the dependency explicit.
- Builds without SSH support still compile and return structured unavailable-backend errors through the same API.
- SSH operations are asynchronous from the Lua/Fennel caller perspective.
- Every long-running operation has an operation ID and supports cancellation and timeouts.
- Operation terminal states are explicit: success, error, timeout, cancelled, or closed as appropriate.
- The SSH core is policy-driven.
- It defaults to rejecting unknown or changed hosts unless a caller supplies a policy decision.
- Functions use canonical kebab-case keys only and reject malformed options loudly.
- No Space SSH server or jump-host implementation in phase 1.
- No main Space UI for SSH host onboarding in this slice.
- No promise of Windows or macOS runtime validation in phase 1, beyond keeping the public API and backend boundary cross-platform-ready.
- No direct public exposure of `libssh` handles, types, constants, or callback conventions.
- No SCP, rsync, X11 forwarding, GSSAPI/Kerberos, hardware-token UX, OpenSSH config emulation, or long-term secret storage in phase 1.
- No credential material in URLs, logs, structured errors, or operation result tables.
- Implementation must use subagent-driven-development task-by-task; the supervisor must not edit production or test code directly.
- Fennel work must follow Space validation order: `make fennel-check`, then `make constraints`, then focused Fennel tests.
- Any validation command using `./build/space` requires `make build` first when the binary may be missing or stale.

---

## File Structure

**Create C++ SSH core:**
- `src/ssh_types.h` — backend-neutral public structs/enums, opaque ID typedefs, event/error vocabulary, secret-redaction helpers.
- `src/ssh_backend.h` — abstract backend interface and operation sink/cancellation interfaces; no `libssh` includes.
- `src/ssh_service.h` — service façade consumed by C++ and Lua binding.
- `src/ssh_service.cpp` — ID generation, validation, async worker queue, poll ordering, callbacks, cancellation, timeout and shutdown behavior.
- `src/ssh_backend_unavailable.cpp` — backend implementation used when `libssh` is disabled or not found.
- `src/ssh_backend_libssh.h` — declaration-only libssh backend factory/class without including libssh headers.
- `src/ssh_backend_libssh.cpp` — the only production file that includes `libssh` headers.
- `src/lua_ssh.h` — binding installer, dispatch, and drop declarations.
- `src/lua_ssh.cpp` — native Lua `ssh` module, option validation, table conversion, callback registration.

**Modify C++ runtime/build:**
- `CMakeLists.txt` — optional `libssh` detection/linking and SSH test registrations.
- `src/lua_runtime.h` — own `space::ssh::Service`.
- `src/lua_runtime.cpp` — create/bind/drop SSH service.
- `src/lua_callbacks.cpp` — poll SSH in `callbacks.run-loop`.
- `src/engine.cpp` — poll/drop SSH during engine loop and shutdown.

**Create native tests:**
- `tests/test_ssh_service.cpp` — fake-backend service tests.
- `tests/test_lua_ssh_binding.cpp` — Sol2 module shape, validation, events, callback dispatch, unavailable backend behavior.

**Create Fennel modules/tests:**
- `assets/lua/ssh/init.fnl` — thin Fennel-facing façade over native module.
- `assets/lua/ssh/fleet.fnl` — bounded-concurrency fleet execution helpers.
- `assets/lua/tests/test-ssh.fnl` — façade/native API fast tests that do not require an external SSH server.
- `assets/lua/tests/test-ssh-fleet.fnl` — fake-module fleet helper tests.
- `assets/lua/tests/test-ssh-integration.fnl` — real SSH integration tests that skip loudly when fixture env is absent.
- `assets/lua/tests/fast.fnl` — include fast SSH tests.
- `assets/lua/tests/integration.fnl` — include SSH integration test module.

**Create integration fixture/docs:**
- `tests/ssh_fixture.py` — disposable Linux OpenSSH fixture runner with dependency detection.
- `docs/dev/subsystems/ssh.md` — SSH architecture, dependency, API, policy, validation, and fixture docs.
- `docs/dev/subsystems/index.md` — link SSH subsystem docs.
- `docs/dev/subsystems/build.md` — document optional `libssh` package/build behavior.

**Acceptance Criteria:**
- Public C++ SSH headers contain no `libssh` includes, symbols, handles, constants, or callback conventions.
- `require("ssh")` exposes `connect`, `resolve-known-host`, `close-session`, `exec`, `sftp-upload`, `sftp-download`, `open-shell`, `channel-write`, `channel-resize`, `channel-close`, `open-local-tunnel`, `open-remote-tunnel`, `close-tunnel`, `cancel`, and `poll`.
- Builds with no `libssh` still compile and produce structured `unavailable-backend` errors.
- Unknown and changed host keys are rejected by default unless a caller explicitly resolves the known-host challenge.
- Exec streams stdout/stderr and produces exactly one terminal event.
- SFTP upload/download preserve bytes in integration tests.
- Shell channels support open/write/resize/close and reject invalid or closed channel IDs.
- Local and remote tunnel APIs exist and either work through the fixture or emit structured `unsupported`/backend errors.
- Fleet helpers return per-host tables containing `host`, `port`, `username`, `ok`, `exit-status`, `stdout`, `stderr`, `error-code`, `error`, and `duration-ms`.
- Secrets never appear in events, errors, result tables, fixture logs, or docs examples.
- `make test` is justified and required before integration handoff because this changes CMake, native bindings, runtime dispatch, async networking, and security-sensitive behavior.
- PR CI is the full integration gate after local validation.

**Out of Scope:**
- Space SSH server behavior.
- Jump-host routing.
- Main app host-onboarding UI.
- OpenSSH config emulation.
- Long-term secret storage.
- SCP, rsync, X11 forwarding, GSSAPI/Kerberos, hardware-token UX.
- Windows/macOS runtime validation beyond keeping public APIs and build branches cross-platform-ready.

---

### Task 1: Backend-Neutral Core Service

**Files:**
- Create: `src/ssh_types.h`
- Create: `src/ssh_backend.h`
- Create: `src/ssh_service.h`
- Create: `src/ssh_service.cpp`
- Create: `src/ssh_backend_unavailable.cpp`
- Create: `tests/test_ssh_service.cpp`
- Modify: `CMakeLists.txt`

**Interfaces:**
- Consumes: Existing CMake test style and C++ assertion-style tests.
- Produces:
  - `namespace space::ssh`
  - `using OperationId = uint64_t; using SessionId = uint64_t; using ChannelId = uint64_t; using TunnelId = uint64_t;`
  - `enum class AuthMethodType { Agent, PrivateKey, Password };`
  - `enum class KnownHostPolicy { Reject, Ask, AcceptOnce, AcceptAndStore };`
  - `enum class KnownHostDecision { Reject, AcceptOnce, AcceptAndStore };`
  - `enum class ErrorCode { None, UnavailableBackend, MalformedOptions, InvalidId, UnknownHost, ChangedHostKey, AuthFailed, Timeout, Cancelled, Closed, Unsupported, LocalFileError, RemoteFileError, TunnelBindFailed, BackendError };`
  - `enum class EventKind { OperationStarted, KnownHostChallenge, Connected, SessionClosed, ExecStdout, ExecStderr, ExecComplete, SftpProgress, SftpComplete, ShellOpened, ChannelData, ChannelClosed, TunnelOpened, TunnelClosed, OperationSuccess, OperationError, OperationTimeout, OperationCancelled };`
  - `struct Target { std::string host; uint16_t port { 22 }; std::string username; };`
  - `struct AuthMethod { AuthMethodType type; std::string key_path; std::string passphrase; std::string password; };`
  - `struct ConnectOptions { Target target; std::vector<AuthMethod> auth_methods; std::string known_hosts_path; uint64_t timeout_ms { 0 }; KnownHostPolicy known_host_policy { KnownHostPolicy::Reject }; };`
  - `struct ExecOptions { std::string command; std::map<std::string, std::string> env; uint64_t timeout_ms { 0 }; };`
  - `struct SftpTransferOptions { std::string local_path; std::string remote_path; uint64_t timeout_ms { 0 }; };`
  - `struct ShellOptions { bool request_pty { false }; std::string term; uint32_t cols { 80 }; uint32_t rows { 24 }; uint64_t timeout_ms { 0 }; };`
  - `struct TunnelOptions { std::string local_host; uint16_t local_port { 0 }; std::string remote_host; uint16_t remote_port { 0 }; uint64_t timeout_ms { 0 }; };`
  - `struct Event { EventKind kind; OperationId operation_id; SessionId session_id; ChannelId channel_id; TunnelId tunnel_id; std::map<std::string, std::string> fields; ErrorCode error_code; std::string message; };`
  - `class Backend`
  - `class Service`
  - `Service` methods: `connect`, `resolve_known_host`, `close_session`, `exec`, `sftp_upload`, `sftp_download`, `open_shell`, `channel_write`, `channel_resize`, `channel_close`, `open_local_tunnel`, `open_remote_tunnel`, `close_tunnel`, `cancel`, `poll`, `shutdown`.

- [ ] **Step 1: Add RED service tests for ID generation, poll ordering, unavailable backend, invalid IDs, cancellation, timeout, and known-host challenge flow**
  - In `tests/test_ssh_service.cpp`, use an in-file fake backend implementing `space::ssh::Backend`.
  - Test names and assertions:
    - `connect_returns_monotonic_operation_ids`: first two `Service::connect` calls return `1` and `2`.
    - `poll_preserves_event_order`: fake backend emits three events; `poll(0)` returns them in emission order.
    - `unavailable_backend_returns_structured_error`: unavailable backend connect returns an `OperationError` with `ErrorCode::UnavailableBackend`.
    - `invalid_session_operations_fail_loudly`: `exec(999, ...)`, `close_session(999)`, `channel_write(999, "x")`, and `close_tunnel(999)` each produce or throw structured `InvalidId` errors, not success.
    - `cancel_emits_cancelled_terminal_event`: canceling an active fake operation emits exactly one `OperationCancelled`.
    - `timeout_emits_timeout_terminal_event`: an operation with `timeout_ms=1` emits exactly one `OperationTimeout`.
    - `known_host_challenge_blocks_until_resolution`: fake backend emits `KnownHostChallenge`, then `resolve_known_host(op, AcceptOnce)` allows `Connected`.
  - Confirm no test references `libssh`.

- [ ] **Step 2: Register the failing service test in CMake**
  - In `CMakeLists.txt`, add:
    - `add_executable(test_ssh_service tests/test_ssh_service.cpp src/ssh_service.cpp src/ssh_backend_unavailable.cpp)`
    - `target_include_directories(test_ssh_service PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)`
    - `add_test(NAME test_ssh_service COMMAND test_ssh_service)`
    - `set_tests_properties(test_ssh_service PROPERTIES WORKING_DIRECTORY ${CMAKE_BINARY_DIR})`

- [ ] **Step 3: Run RED validation**
  - Run: `make cmake` with timeout `600000`.
  - Run: `make build` with timeout `14400000`.
  - Run: `ctest --test-dir build -R test_ssh_service --output-on-failure`.
  - Expected before implementation: build or test failure because SSH core files/types are missing.

- [ ] **Step 4: Implement backend-neutral types and invariants**
  - `src/ssh_types.h` must define all public structs/enums listed in **Interfaces**.
  - Default `Target.port` to `22`.
  - Use opaque integer IDs only.
  - Include no `libssh` headers or symbols.
  - Include helper functions `std::string error_code_to_string(ErrorCode)` and `std::string event_kind_to_string(EventKind)`.
  - Include a helper that redacts secret fields from maps before events are created.

- [ ] **Step 5: Implement the abstract backend boundary**
  - `src/ssh_backend.h` must declare `class Backend` with virtual methods matching every `Service` operation.
  - Declare an operation sink interface used by backends to emit events.
  - Declare a cancellation/timeout token that backends can check.
  - Include no `libssh` headers or symbols.

- [ ] **Step 6: Implement `Service` core behavior**
  - `src/ssh_service.cpp` must allocate IDs monotonically from `1`.
  - Validate non-empty host for connect and non-empty command for exec.
  - Create operation IDs for every long-running operation.
  - Track known sessions/channels/tunnels.
  - Queue events under a mutex and return them from `poll(max_results)`.
  - Preserve FIFO event ordering.
  - Support `cancel(operation_id)` returning `true` only for active operations.
  - Convert timeout expiration to one terminal `OperationTimeout`.
  - Call backend work off the Lua/main thread.
  - Ensure `shutdown()` cancels pending work, joins workers, clears handles, and prevents callbacks/events after shutdown.

- [ ] **Step 7: Implement unavailable backend**
  - `src/ssh_backend_unavailable.cpp` must produce structured `OperationError` events with:
    - `error_code = ErrorCode::UnavailableBackend`;
    - `fields["error-code"] = "unavailable-backend"`;
    - message containing the missing/disabled backend reason;
    - no silent no-ops.

- [ ] **Step 8: Run GREEN focused validation**
  - Run: `make build` with timeout `14400000`.
  - Run: `ctest --test-dir build -R test_ssh_service --output-on-failure`.
  - Expected: `test_ssh_service` passes.

- [ ] **Step 9: Commit Task 1**
  ```bash
  git add CMakeLists.txt src/ssh_types.h src/ssh_backend.h src/ssh_service.h src/ssh_service.cpp src/ssh_backend_unavailable.cpp tests/test_ssh_service.cpp
  git commit -m "feat(ssh): add backend-neutral SSH service core"
  ```

---

### Task 2: Optional `libssh` Backend and Build Integration

**Files:**
- Create: `src/ssh_backend_libssh.h`
- Create: `src/ssh_backend_libssh.cpp`
- Modify: `CMakeLists.txt`
- Modify: `src/ssh_service.h`
- Modify: `src/ssh_service.cpp`
- Test: `tests/test_ssh_service.cpp`

**Interfaces:**
- Consumes:
  - `space::ssh::Backend`
  - `space::ssh::Service`
  - `ConnectOptions`, `KnownHostDecision`, `KnownHostPolicy`, `Event`
- Produces:
  - `std::unique_ptr<space::ssh::Backend> make_default_backend();`
  - `std::unique_ptr<space::ssh::Backend> make_libssh_backend();` when `SPACE_HAS_LIBSSH=1`
  - Structured connect/auth/known-host behavior behind the existing `Backend` interface.

- [ ] **Step 1: Add RED tests for backend factory behavior**
  - Extend `tests/test_ssh_service.cpp` with:
    - `default_backend_factory_never_returns_null`;
    - `default_backend_reports_unavailable_when_libssh_missing`;
    - `public_headers_do_not_include_libssh_symbols`, implemented by reading `src/ssh_types.h`, `src/ssh_backend.h`, and `src/ssh_service.h` and asserting they do not contain `libssh`, `ssh_session`, `ssh_channel`, or `ssh_scp`.
  - The test must pass both with and without `libssh` installed.

- [ ] **Step 2: Add optional CMake detection**
  - Near existing pkg-config dependency detection in `CMakeLists.txt`, add:
    - `option(SPACE_ENABLE_SSH "Build SSH integration when libssh is available" ON)`
    - `set(SPACE_HAS_LIBSSH OFF)`
    - `pkg_check_modules(LIBSSH IMPORTED_TARGET libssh)` only when `SPACE_ENABLE_SSH` is `ON`.
    - Set `SPACE_HAS_LIBSSH ON` only when `LIBSSH_FOUND`.
    - Print a warning, not a fatal error, when SSH is enabled but `libssh` is not found.
  - Link `${PROJECT_NAME}_lib` to `PkgConfig::LIBSSH` and define `SPACE_HAS_LIBSSH=1` only when found.
  - Do not introduce a minimum `libssh` version floor in this task.

- [ ] **Step 3: Add backend factory**
  - `src/ssh_backend_libssh.h` must declare the factory without including `libssh` headers.
  - `src/ssh_backend_libssh.cpp` must be the only production file with `#include <libssh/...>`.
  - `make_default_backend()` must return:
    - `make_libssh_backend()` when `SPACE_HAS_LIBSSH=1`;
    - unavailable backend with reason `"libssh backend not available"` otherwise.

- [ ] **Step 4: Implement connect/auth lifecycle in `libssh` backend**
  - Support auth methods in caller-provided order: agent, private key path with optional passphrase, and password.
  - For connect, apply `Target.host`, `Target.port`, `Target.username`, `known_hosts_path`, and `timeout_ms`.
  - Emit `KnownHostChallenge` for unknown/changed host when policy is `Ask`.
  - Reject unknown/changed host by default when policy is `Reject`.
  - Accept once/store only when caller decision is explicit.
  - Emit structured `AuthFailed`, `UnknownHost`, `ChangedHostKey`, `Timeout`, `Cancelled`, or `BackendError` events.
  - Never copy `password` or `passphrase` into event fields, messages, logs, exceptions, or test failure strings.

- [ ] **Step 5: Preserve service invariants**
  - Confirm that connect success registers exactly one `SessionId`.
  - Confirm that close-session removes the session and emits `SessionClosed`.
  - Confirm that closing an unknown session emits `InvalidId`.

- [ ] **Step 6: Run focused validation**
  - Run: `make cmake` with timeout `600000`.
  - Run: `make build` with timeout `14400000`.
  - Run: `ctest --test-dir build -R test_ssh_service --output-on-failure`.
  - Run header isolation check:
    ```bash
    ! rg "libssh|ssh_session|ssh_channel|ssh_scp" src/ssh_types.h src/ssh_backend.h src/ssh_service.h
    ```

- [ ] **Step 7: Commit Task 2**
  ```bash
  git add CMakeLists.txt src/ssh_backend_libssh.h src/ssh_backend_libssh.cpp src/ssh_service.h src/ssh_service.cpp tests/test_ssh_service.cpp
  git commit -m "feat(ssh): add optional libssh backend"
  ```

---

### Task 3: SSH Operations, Channels, SFTP, Tunnels, Cancellation, and Timeouts

**Files:**
- Modify: `src/ssh_types.h`
- Modify: `src/ssh_backend.h`
- Modify: `src/ssh_service.h`
- Modify: `src/ssh_service.cpp`
- Modify: `src/ssh_backend_libssh.cpp`
- Modify: `tests/test_ssh_service.cpp`

**Interfaces:**
- Consumes:
  - `Service` and `Backend` from Tasks 1–2.
  - Active `SessionId` returned by connect success.
- Produces:
  - Exec events: `ExecStdout`, `ExecStderr`, `ExecComplete`.
  - SFTP events: `SftpProgress`, `SftpComplete`.
  - Shell events: `ShellOpened`, `ChannelData`, `ChannelClosed`.
  - Tunnel events: `TunnelOpened`, `TunnelClosed`, structured `Unsupported` or `TunnelBindFailed`.
  - Stable invalid-ID handling for all operation families.

- [ ] **Step 1: Add RED service tests for operation semantics with fake backend**
  - Extend `tests/test_ssh_service.cpp` with:
    - `exec_streams_stdout_stderr_then_single_terminal_event`;
    - `exec_cancel_closes_operation_once`;
    - `sftp_progress_precedes_completion`;
    - `sftp_upload_download_errors_are_structured`;
    - `open_shell_returns_channel_id_and_accepts_write_resize_close`;
    - `closed_channel_write_fails_with_invalid_id_or_closed`;
    - `local_tunnel_open_close_lifecycle`;
    - `remote_tunnel_unsupported_is_structured`;
    - `shutdown_cancels_sessions_channels_tunnels_and_workers`.
  - The fake backend must simulate events without requiring a real server.

- [ ] **Step 2: Implement service-level operation state**
  - Track operation terminal state so success/error/timeout/cancelled is emitted exactly once.
  - Track session/channel/tunnel ownership so IDs are scoped to the service.
  - Reject malformed operation options before backend dispatch:
    - empty command for exec;
    - empty local/remote path for SFTP;
    - zero rows/cols when shell PTY is requested;
    - empty remote host or zero remote port for tunnel requests.

- [ ] **Step 3: Implement exec in libssh backend**
  - Open a channel for each exec operation.
  - Stream stdout and stderr separately as events.
  - Emit `ExecComplete` with `fields["exit-status"]`.
  - On cancel/timeout, close the channel and emit `OperationCancelled` or `OperationTimeout`.
  - Keep command text out of error messages when it could contain secrets; use operation ID and stable error code instead.

- [ ] **Step 4: Implement SFTP upload/download**
  - Upload and download must copy bytes exactly.
  - Emit progress when total size is known with `fields["bytes"]` and `fields["total-bytes"]`.
  - Surface local filesystem failures as `LocalFileError`.
  - Surface remote filesystem/SFTP failures as `RemoteFileError`.
  - Cancel/timeout must close file handles and SFTP sessions.

- [ ] **Step 5: Implement shell channel lifecycle**
  - `open_shell` must optionally request PTY using `request_pty`, `term`, `cols`, and `rows`.
  - `channel_write` sends bytes to the remote channel.
  - `channel_resize` resizes an open PTY channel.
  - `channel_close` closes the remote channel and marks the channel ID closed.
  - Unknown or closed channel IDs must fail explicitly.

- [ ] **Step 6: Implement tunnel API surface**
  - `open_local_tunnel` attempts to bind a local listener and forward accepted connections through SSH.
  - `open_remote_tunnel` requests remote forwarding when backend/platform supports it.
  - If a tunnel shape is unavailable in the backend/platform, emit `ErrorCode::Unsupported`.
  - Bind failures emit `ErrorCode::TunnelBindFailed`.
  - `close_tunnel` stops accepting new connections, closes active relay sockets, and emits `TunnelClosed`.

- [ ] **Step 7: Run focused validation**
  - Run: `make build` with timeout `14400000`.
  - Run: `ctest --test-dir build -R test_ssh_service --output-on-failure`.

- [ ] **Step 8: Commit Task 3**
  ```bash
  git add src/ssh_types.h src/ssh_backend.h src/ssh_service.h src/ssh_service.cpp src/ssh_backend_libssh.cpp tests/test_ssh_service.cpp
  git commit -m "feat(ssh): implement SSH operation lifecycles"
  ```

---

### Task 4: Lua Binding and Runtime Dispatch

**Files:**
- Create: `src/lua_ssh.h`
- Create: `src/lua_ssh.cpp`
- Create: `tests/test_lua_ssh_binding.cpp`
- Modify: `CMakeLists.txt`
- Modify: `src/lua_runtime.h`
- Modify: `src/lua_runtime.cpp`
- Modify: `src/lua_callbacks.cpp`
- Modify: `src/engine.cpp`

**Interfaces:**
- Consumes:
  - `space::ssh::Service`
  - `space::ssh::Event`
  - `lua_callbacks_register`, `lua_callbacks_enqueue`, `lua_callbacks_dispatch`, `lua_callbacks_unregister`
- Produces:
  - `void lua_bind_ssh(sol::state& lua, std::shared_ptr<space::ssh::Service> service);`
  - `void lua_ssh_dispatch(sol::state& lua);`
  - `void lua_ssh_drop(sol::state& lua);`
  - Native Lua module `require("ssh")` exposing:
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

- [ ] **Step 1: Add RED Lua binding tests**
  - In `tests/test_lua_ssh_binding.cpp`, create a `sol::state`, bind SSH with a fake service/backend, and run Lua assertions.
  - Assert:
    - `require("ssh")` returns a table.
    - Every function listed in **Interfaces** is present.
    - `connect({})` fails because `target.host` is missing.
    - `connect({ target = { host = "h" }, ["auth-methods"] = { { type = "password", password = "secret" } } })` returns a numeric operation ID.
    - `poll()` returns event tables with kebab-case keys: `kind`, `operation-id`, `session-id`, `channel-id`, `tunnel-id`, `fields`, `error-code`, `message`.
    - Password/passphrase strings do not appear in event tables.
    - Unknown option keys such as `authMethods` or `timeout_ms` fail loudly.
    - Callback passed as second arg receives the terminal event after `lua_ssh_dispatch`.
    - `resolve-known-host(op, "accept-once")` maps to `KnownHostDecision::AcceptOnce`.
    - `cancel(999999)` returns false or emits `invalid-id`, but never succeeds silently.

- [ ] **Step 2: Register Lua SSH binding test in CMake**
  - Add:
    - `add_executable(test_lua_ssh_binding tests/test_lua_ssh_binding.cpp src/lua_ssh.cpp src/ssh_service.cpp src/ssh_backend_unavailable.cpp)`
    - Include `src` and link the same Sol2/Lua support libraries used by neighboring Lua binding tests.
    - `add_test(NAME test_lua_ssh_binding COMMAND test_lua_ssh_binding)`

- [ ] **Step 3: Implement Lua option parsing**
  - Use canonical kebab-case keys only.
  - Reject unknown camelCase/snake_case aliases.
  - Validate option shapes:
    - `target` table with non-empty `host`, optional positive `port`, optional `username`;
    - `auth-methods` array with `type` one of `agent`, `private-key`, `password`;
    - `known-host-policy` one of `reject`, `ask`, `accept-once`, `accept-and-store`;
    - positive numeric `timeout-ms` when present.
  - Convert malformed options to `sol::error` with a message naming the failing key.

- [ ] **Step 4: Implement Lua event conversion**
  - Convert event kind/error code to stable kebab-case strings.
  - Use numeric IDs in `operation-id`, `session-id`, `channel-id`, and `tunnel-id`; use `nil` for absent IDs.
  - Convert fields map to a Lua table.
  - Redact all `password`, `passphrase`, and secret-like fields before Lua conversion.

- [ ] **Step 5: Implement callback registration and dispatch**
  - When a Lua SSH function receives a callback, register it with `lua_callbacks_register`.
  - Associate callback IDs with operation IDs.
  - `lua_ssh_dispatch` must poll the service, enqueue callback payloads, unregister terminal callbacks, and buffer events without callbacks for `ssh.poll`.
  - `ssh.poll(max-results)` must consume buffered events first, then newly polled events, respecting `max-results`.
  - Runtime shutdown must unregister callbacks and drop the module state.

- [ ] **Step 6: Wire runtime and engine dispatch**
  - In `LuaRuntime::init`, create `ssh = std::make_shared<space::ssh::Service>(space::ssh::make_default_backend())` or the closest constructor shape produced by Tasks 1–2.
  - In `install_base_bindings`, call `lua_bind_ssh(lua, ssh)`.
  - In `LuaRuntime` cleanup, call `lua_ssh_drop(lua)` and `ssh->shutdown()` before callback shutdown.
  - In `lua_callbacks.cpp`, poll SSH in `callbacks.run-loop`.
  - In `engine.cpp`, call `lua_ssh_dispatch(*lua_state)` in the main dispatch loop and `lua_ssh_drop(*lua_state)` during shutdown before `lua_callbacks_shutdown()`.

- [ ] **Step 7: Run focused validation**
  - Run: `make cmake` with timeout `600000`.
  - Run: `make build` with timeout `14400000`.
  - Run: `ctest --test-dir build -R 'test_lua_ssh_binding|test_ssh_service' --output-on-failure`.

- [ ] **Step 8: Commit Task 4**
  ```bash
  git add CMakeLists.txt src/lua_ssh.h src/lua_ssh.cpp src/lua_runtime.h src/lua_runtime.cpp src/lua_callbacks.cpp src/engine.cpp tests/test_lua_ssh_binding.cpp
  git commit -m "feat(lua): expose SSH runtime binding"
  ```

---

### Task 5: Fennel Façade and Fleet Helpers

**Files:**
- Create: `assets/lua/ssh/init.fnl`
- Create: `assets/lua/ssh/fleet.fnl`
- Create: `assets/lua/tests/test-ssh.fnl`
- Create: `assets/lua/tests/test-ssh-fleet.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes:
  - Native Lua module `require("ssh")` from Task 4.
  - `callbacks.run-loop` for async polling in tests.
- Produces:
  - Fennel façade module `ssh` that re-exports native functions without renaming keys.
  - Fleet module API:
    - `(exec hosts opts)` returning per-host result tables.
    - `(cancel token-or-operation-id)` for caller-driven cancellation.
  - Fleet host input fields: `host`, `port`, `username`, `auth-methods`, `known-host-policy`, `known-hosts-path`.
  - Fleet result fields: `host`, `port`, `username`, `ok`, `exit-status`, `stdout`, `stderr`, `error-code`, `error`, `duration-ms`.

- [ ] **Step 1: Add RED Fennel tests for façade module**
  - `assets/lua/tests/test-ssh.fnl` must assert:
    - `(require :ssh)` returns a table;
    - all native function names are present with kebab-case names;
    - invalid connect options raise an error;
    - unavailable backend poll result contains `error-code` `"unavailable-backend"` when `libssh` is absent;
    - façade does not introduce camelCase or snake_case aliases.

- [ ] **Step 2: Add RED Fennel tests for fleet module using an injected fake SSH table**
  - `assets/lua/tests/test-ssh-fleet.fnl` must load `ssh.fleet` with fake transport functions.
  - Assert:
    - concurrency limit is honored;
    - results include `host`, `port`, `username`, `ok`, `exit-status`, `stdout`, `stderr`, `error-code`, `error`, `duration-ms`;
    - per-host timeout produces `ok=false` and `error-code="timeout"`;
    - cancellation produces `ok=false` and `error-code="cancelled"`;
    - known-host policy options are passed through unchanged;
    - no password/passphrase appears in result tables.

- [ ] **Step 3: Add tests to fast suite**
  - Add `:tests.test-ssh` and `:tests.test-ssh-fleet` to `assets/lua/tests/fast.fnl`.

- [ ] **Step 4: Run RED Fennel validation**
  - Ensure runtime freshness first if `./build/space` is missing or stale: run `make build` with timeout `14400000`.
  - First focused compile check:
    ```bash
    ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/ssh/init.fnl --file assets/lua/ssh/fleet.fnl --file assets/lua/tests/test-ssh.fnl --file assets/lua/tests/test-ssh-fleet.fnl
    ```
  - Then constraints:
    ```bash
    make constraints
    ```
  - Then focused tests:
    ```bash
    SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-ssh:main
    SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-ssh-fleet:main
    ```
  - Expected before implementation: focused tests fail.

- [ ] **Step 5: Implement `assets/lua/ssh/init.fnl`**
  - Re-export the native SSH function table.
  - Do not rename keys.
  - Do not add compatibility aliases.
  - Do not catch native errors or convert them to success values.

- [ ] **Step 6: Implement `assets/lua/ssh/fleet.fnl`**
  - Implement bounded concurrency using the public SSH API only.
  - Preserve caller-supplied known-host policy per host.
  - Accumulate stdout/stderr from streaming events.
  - Produce exactly one result table per host.
  - Enforce per-host timeouts and cancellation through `ssh.cancel`.
  - Redact credential fields from results and error strings.

- [ ] **Step 7: Repair Fennel delimiter/parse errors using enclosing-form isolation if needed**
  - If `tools.fennel-check` reports delimiter or parse errors, inspect the nearest enclosing form around the reported location.
  - If the blamed line looks innocent, temporarily remove chunks of the file until it compiles, then re-add them step by step.
  - Prefer moving nested logic into helper functions over adding more nested delimiters.

- [ ] **Step 8: Run GREEN Fennel validation**
  - Run compile check first:
    ```bash
    ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/ssh/init.fnl --file assets/lua/ssh/fleet.fnl --file assets/lua/tests/test-ssh.fnl --file assets/lua/tests/test-ssh-fleet.fnl
    ```
  - Run constraints second:
    ```bash
    make constraints
    ```
  - Run focused tests third:
    ```bash
    SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-ssh:main
    SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-ssh-fleet:main
    ```

- [ ] **Step 9: Commit Task 5**
  ```bash
  git add assets/lua/ssh/init.fnl assets/lua/ssh/fleet.fnl assets/lua/tests/test-ssh.fnl assets/lua/tests/test-ssh-fleet.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(ssh): add Fennel facade and fleet helpers"
  ```

---

### Task 6: Integration Fixture, Real SSH Coverage, and Developer Docs

**Files:**
- Create: `tests/ssh_fixture.py`
- Create: `assets/lua/tests/test-ssh-integration.fnl`
- Create: `docs/dev/subsystems/ssh.md`
- Modify: `assets/lua/tests/integration.fnl`
- Modify: `CMakeLists.txt`
- Modify: `docs/dev/subsystems/index.md`
- Modify: `docs/dev/subsystems/build.md`

**Interfaces:**
- Consumes:
  - Native `ssh` module from Task 4.
  - Fennel test runner.
  - `tests/ssh_fixture.py` environment variables:
    - `SPACE_TEST_SSH_HOST`
    - `SPACE_TEST_SSH_PORT`
    - `SPACE_TEST_SSH_USER`
    - `SPACE_TEST_SSH_KEY`
    - `SPACE_TEST_SSH_KNOWN_HOSTS`
    - `SPACE_TEST_SSH_ROOT`
- Produces:
  - CTest integration target `space_ssh_integration`.
  - Linux fixture that starts disposable local OpenSSH server when `sshd` and `ssh-keygen` are available.
  - Docs page `docs/dev/subsystems/ssh.md`.

- [ ] **Step 1: Add RED integration test module**
  - `assets/lua/tests/test-ssh-integration.fnl` must:
    - skip with a passing test and clear message when fixture env vars are absent;
    - connect using private-key auth;
    - assert default unknown-host rejection before accepting/storing;
    - resolve known-host challenge with `"accept-and-store"`;
    - exec a command that writes stdout, stderr, and exits with a nonzero status;
    - upload and download a binary payload and compare byte equality;
    - open shell, write `printf shell-ok\n`, read output, and close channel;
    - open local tunnel and relay a simple TCP payload if fixture provides an echo endpoint;
    - attempt remote tunnel and accept either success or structured `unsupported`;
    - cancel a long-running exec and assert `error-code="cancelled"`.

- [ ] **Step 2: Add fixture runner**
  - `tests/ssh_fixture.py` must:
    - detect `sshd`, `ssh-keygen`, and `ssh-keyscan`;
    - exit `0` with a skip message if dependencies are unavailable;
    - create all fixture files under `/tmp/space/tests/ssh-fixture-*`;
    - generate an ephemeral user key;
    - create temporary `sshd_config`, host key, authorized keys, known-hosts file, and writable SFTP root;
    - start `sshd` on localhost with an allocated port;
    - run the Space command passed by CTest with fixture env vars;
    - terminate `sshd` and remove temp files on normal exit or failure;
    - never print private key or passphrase contents.

- [ ] **Step 3: Register CTest integration target**
  - In `CMakeLists.txt`, add `space_ssh_integration` that runs:
    ```bash
    ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/ssh_fixture.py --space $<TARGET_FILE:${SPACE_TEST_COMMAND_TARGET}> --assets ${CMAKE_SOURCE_DIR}/assets --module tests.test-ssh-integration:main
    ```
  - Set environment consistently with existing Fennel tests:
    - `SKIP_KEYRING_TESTS=1`
    - `XDG_DATA_HOME=/tmp/space/tests/xdg-data`
    - `SPACE_DISABLE_AUDIO=1`
    - `SPACE_LOG_DIR=/tmp/space/tests/log`
    - `SPACE_ASSETS_PATH=${CMAKE_SOURCE_DIR}/assets`
    - `FENNEL_PATH=${CMAKE_SOURCE_DIR}/assets/lua/?.fnl;${CMAKE_SOURCE_DIR}/assets/lua/?/init.fnl`
    - `FENNEL_MACRO_PATH=${CMAKE_SOURCE_DIR}/assets/lua/?.fnl;${CMAKE_SOURCE_DIR}/assets/lua/?/init.fnl`

- [ ] **Step 4: Add integration test to Fennel integration suite**
  - Add `:tests.test-ssh-integration` to `assets/lua/tests/integration.fnl`.
  - The module must pass without fixture env vars by reporting a skip, so `make test` remains usable on hosts without OpenSSH server tooling.

- [ ] **Step 5: Create SSH developer docs**
  - `docs/dev/subsystems/ssh.md` must document:
    - backend-neutral service layers;
    - optional `libssh` dependency and unavailable-backend behavior;
    - public C++ concepts;
    - Lua API function list and option keys;
    - known-host policy model and default rejection behavior;
    - credential redaction invariant;
    - cancellation/timeouts;
    - Fennel fleet helper result fields;
    - integration fixture command;
    - phase-1 non-goals.
  - Update `docs/dev/subsystems/index.md` with a link to SSH.
  - Update `docs/dev/subsystems/build.md` to mention the optional `libssh` build dependency and no minimum version floor.

- [ ] **Step 6: Run Fennel and integration focused validation**
  - Ensure runtime freshness:
    ```bash
    make build
    ```
    with timeout `14400000`.
  - First focused Fennel compile check:
    ```bash
    ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-ssh-integration.fnl
    ```
  - Then constraints:
    ```bash
    make constraints
    ```
  - Then focused integration module without fixture env:
    ```bash
    SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-ssh-integration:main
    ```
  - Then fixture-backed CTest:
    ```bash
    SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ctest --test-dir build -R space_ssh_integration --output-on-failure
    ```

- [ ] **Step 7: Commit Task 6**
  ```bash
  git add CMakeLists.txt tests/ssh_fixture.py assets/lua/tests/test-ssh-integration.fnl assets/lua/tests/integration.fnl docs/dev/subsystems/ssh.md docs/dev/subsystems/index.md docs/dev/subsystems/build.md
  git commit -m "test(ssh): add integration fixture and docs"
  ```

---

### Task 7: Final Validation, Security Review, and Handoff

**Files:**
- Modify only if validation uncovers reviewed fixes in files from Tasks 1–6.
- Test: all SSH test files and relevant full local suite.

**Interfaces:**
- Consumes:
  - Completed SSH C++ service/backend.
  - Completed Lua binding/runtime dispatch.
  - Completed Fennel façade/fleet.
  - Completed integration fixture/docs.
- Produces:
  - Clean branch with reviewed commits.
  - Local validation evidence.
  - PR-ready state; PR CI remains the full integration gate.

- [ ] **Step 1: Verify public header isolation**
  ```bash
  ! rg "libssh|ssh_session|ssh_channel|ssh_scp|LIBSSH" src/ssh_types.h src/ssh_backend.h src/ssh_service.h src/lua_ssh.h
  ```

- [ ] **Step 2: Verify no obvious secret leakage terms in tests/docs output paths**
  ```bash
  rg "password|passphrase|private key" src/ssh_* src/lua_ssh.* tests/test_ssh_service.cpp tests/test_lua_ssh_binding.cpp assets/lua/ssh assets/lua/tests/test-ssh*.fnl docs/dev/subsystems/ssh.md
  ```
  - Acceptable matches must be field names, validation text, or explicit redaction documentation.
  - No match may log or assert an actual credential value such as `"secret"` in an event/result message.

- [ ] **Step 3: Refresh build system and binary**
  ```bash
  make cmake
  make build
  ```
  - `make cmake` timeout: `600000`.
  - `make build` timeout: `14400000`.

- [ ] **Step 4: Run first Fennel compile gate**
  ```bash
  make fennel-check
  ```

- [ ] **Step 5: Run constraints second**
  ```bash
  make constraints
  ```

- [ ] **Step 6: Run focused native tests**
  ```bash
  ctest --test-dir build -R 'test_ssh_service|test_lua_ssh_binding' --output-on-failure
  ```

- [ ] **Step 7: Run focused Fennel SSH tests third**
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-ssh:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-ssh-fleet:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-ssh-integration:main
  ```

- [ ] **Step 8: Run fixture-backed SSH integration**
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ctest --test-dir build -R space_ssh_integration --output-on-failure
  ```
  - If fixture dependencies are unavailable, the test must exit `0` with a skip message naming the missing tool.
  - If fixture dependencies are available, real SSH behavior must run and pass.

- [ ] **Step 9: Run complete relevant local suite**
  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```
  - This broader suite is required because the work changes CMake, native bindings, runtime dispatch, async networking, callback lifecycle, and security-sensitive transport behavior.

- [ ] **Step 10: Inspect branch state**
  ```bash
  git status --porcelain
  git log --oneline --decorate -n 12
  ```
  - Working tree must be clean before handoff.

- [ ] **Step 11: Route any validation fixes through the reviewed fix loop**
  - If any command in Task 7 fails because of repository behavior, stop this task and invoke `systematic-debugging`.
  - Route the diagnosed repository fix through `implementer` and `reviewer` before committing.
  - After the reviewed fix commit lands, rerun Task 7 from Step 1.
  - Do not commit generated build artifacts.

- [ ] **Step 12: Final integration gate**
  - Report local validation commands and results.
  - State explicitly: `PR CI is the full integration gate`.
  - Do not claim ready-to-merge until applicable PR CI is green.
