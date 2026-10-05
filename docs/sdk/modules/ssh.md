# ssh

## Canonical Imports

```fennel
(local ssh (require :ssh))
(local fleet (require :ssh.fleet))
```

## Source Files

- `src/ssh_types.h`
- `src/ssh_service.cpp`
- `src/ssh_backend_libssh.cpp`
- `src/ssh_backend_unavailable.cpp`
- `src/lua_ssh.cpp`
- `assets/lua/ssh/init.fnl`
- `assets/lua/ssh/fleet.fnl`

## Availability

`ssh.available` is true when Space was built with a real SSH backend. When the backend is not compiled in, `ssh.available` is false and `ssh["missing-reason"]` explains why. The API still loads in unavailable builds; operations finish with structured `operation-error` events whose `error-code` is `"unavailable-backend"`.

## API Summary

- `connect(opts[, callback]) -> operation-id` starts a connection. `opts.target.host`, `opts.target.port`, and `opts.target.username` identify the target. Optional keys include `auth-methods`, `known-host-policy`, `known-hosts-path`, and `timeout-ms`.
- `resolve-known-host(operation-id, decision) -> boolean` answers an `ask` known-host challenge with `reject`, `accept-once`, or `accept-and-store`.
- `exec(session-id, opts[, callback]) -> operation-id` runs a command. `opts.command` is required; optional keys include `env` and `timeout-ms`.
- `sftp-upload`, `sftp-download`, `open-shell`, `channel-write`, `channel-resize`, `channel-close`, `open-local-tunnel`, `open-remote-tunnel`, `close-tunnel`, `close-session`, `cancel`, and `poll` expose the rest of the client transport surface.
- `ssh.fleet.exec(hosts, opts) -> results` connects to multiple hosts, runs one command, and returns per-host result tables with `host`, `port`, `username`, `ok`, `exit-status`, `stdout`, `stderr`, `error-code`, `error`, and `duration-ms`.

## Low-level connect/exec example

Covered by the Fennel test named `SDK low-level exec example runs command`.

```fennel
(local ssh (require :ssh))
(local callbacks (require :callbacks))

(local events [])
(var session-id nil)
(var exec-done false)

(fn on-event [event]
  (table.insert events event))

(local connect-op
  (ssh.connect
    {:target {:host (os.getenv "SPACE_SSH_HOST")
              :port (tonumber (os.getenv "SPACE_SSH_PORT"))
              :username (os.getenv "SPACE_SSH_USER")}
     :auth-methods [{:type "private-key"
                     :key-path (os.getenv "SPACE_SSH_KEY_PATH")}]
     :known-host-policy "accept-once"
     :known-hosts-path (os.getenv "SPACE_SSH_KNOWN_HOSTS_PATH")
     :timeout-ms 10000}
    on-event))

(callbacks.run-loop {:poll-jobs false
                     :poll-http false
                     :poll-process false
                     :timeout-ms 10000
                     :until (fn []
                              (each [_ event (ipairs events)]
                                (when (and (= event.operation-id connect-op)
                                           (= event.kind "connected"))
                                  (set session-id event.session-id)))
                              (not (= session-id nil)))})

(local exec-op
  (ssh.exec session-id {:command "printf sdk-ssh-ok"
                        :timeout-ms 10000}
            on-event))

(callbacks.run-loop {:poll-jobs false
                     :poll-http false
                     :poll-process false
                     :timeout-ms 10000
                     :until (fn []
                              (each [_ event (ipairs events)]
                                (when (and (= event.operation-id exec-op)
                                           (= event.kind "operation-success"))
                                  (set exec-done true)))
                              exec-done)})
```

## Fleet exec example

Covered by the Fennel test named `SDK fleet exec example returns structured per-host results`.

```fennel
(local fleet (require :ssh.fleet))

(local hosts [{:host "web-1.example.test"
               :port 22
               :username "deploy"
               :auth-methods [{:type "private-key"
                               :key-path (os.getenv "SPACE_SSH_KEY_PATH")}]
               :known-host-policy "accept-once"
               :known-hosts-path (os.getenv "SPACE_SSH_KNOWN_HOSTS_PATH")}
              {:host "web-2.example.test"
               :port 2222
               :username "deploy"
               :auth-methods [{:type "private-key"
                               :key-path (os.getenv "SPACE_SSH_KEY_PATH")}]
               :known-host-policy "accept-once"
               :known-hosts-path (os.getenv "SPACE_SSH_KNOWN_HOSTS_PATH")}])

(local results (fleet.exec hosts {:command "uname -s"
                                  :concurrency 2
                                  :timeout-ms 10000
                                  :env {:SPACE_SSH_EXAMPLE "1"}}))

(each [_ result (ipairs results)]
  (if result.ok
      (print result.host result.exit-status result.stdout)
      (print result.host result.error-code result.error)))
```

## Known-host policy and credential safety

The default `known-host-policy` is `reject`. Use `ask` when the caller can inspect a `known-host-challenge` event and then call `resolve-known-host`, or use `accept-once` for ephemeral trust that must not update a known-hosts file. Use `accept-and-store` only with a caller-owned `known-hosts-path`.

Keep credentials out of source files and logs. Read key paths, passphrases, and other secrets from the environment or a secret provider, and pass them with canonical keys such as `auth-methods`, `key-path`, `passphrase`, and `password`. Do not copy credential material from errors or result tables.

## Related Modules

- [`callbacks`](/sdk/modules/callbacks) for command-line run loops that wait for SSH events.
- [`process`](/sdk/modules/process) for local subprocess execution.
- [`http`](/sdk/modules/http) for asynchronous network requests over HTTP.

## Aliases and Search Terms

Search terms: SSH, secure shell, remote command, exec, SFTP, tunnel, known hosts, libssh, fleet.
