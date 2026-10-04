(local tests [])

(local required-env ["SPACE_TEST_SSH_HOST" "SPACE_TEST_SSH_PORT" "SPACE_TEST_SSH_USER"
                     "SPACE_TEST_SSH_KEY" "SPACE_TEST_SSH_KNOWN_HOSTS" "SPACE_TEST_SSH_ROOT"])

(fn env [name]
  (os.getenv name))

(fn fixture-config []
  (local missing [])
  (each [_ name (ipairs required-env)]
    (when (not (env name))
      (table.insert missing name)))
  (if (> (# missing) 0)
      (values nil (.. "SSH integration fixture not configured; missing " (table.concat missing ", ")))
      {:host (env "SPACE_TEST_SSH_HOST")
       :port (assert (tonumber (env "SPACE_TEST_SSH_PORT")) "SPACE_TEST_SSH_PORT must be numeric")
       :username (env "SPACE_TEST_SSH_USER")
       :key-path (env "SPACE_TEST_SSH_KEY")
       :known-hosts-path (env "SPACE_TEST_SSH_KNOWN_HOSTS")
       :root (env "SPACE_TEST_SSH_ROOT")
       :echo-host (env "SPACE_TEST_SSH_ECHO_HOST")
        :echo-port (and (env "SPACE_TEST_SSH_ECHO_PORT")
                        (tonumber (env "SPACE_TEST_SSH_ECHO_PORT")))
        :local-tunnel-port (and (env "SPACE_TEST_SSH_LOCAL_TUNNEL_PORT")
                                (tonumber (env "SPACE_TEST_SSH_LOCAL_TUNNEL_PORT")))
        :remote-tunnel-port (and (env "SPACE_TEST_SSH_REMOTE_TUNNEL_PORT")
                                 (tonumber (env "SPACE_TEST_SSH_REMOTE_TUNNEL_PORT")))}))

(fn terminal-event? [event]
  (if (= event.kind "operation-success")
      true
      (= event.kind "operation-error")
      true
      (= event.kind "operation-timeout")
      true
      (= event.kind "operation-cancelled")))

(fn write-file [path data]
  (local file (assert (io.open path :wb) (.. "open for write: " path)))
  (file:write data)
  (file:close))

(fn read-file [path]
  (local file (assert (io.open path :rb) (.. "open for read: " path)))
  (local data (file:read :*a))
  (file:close)
  data)

(fn shell-quote [value]
  (.. "'" (string.gsub (tostring value) "'" "'\\''") "'"))

(fn python-tcp-round-trip [host port payload]
  (local script "import socket,sys,time; last=None\nfor _ in range(50):\n    try:\n        s=socket.create_connection((sys.argv[1], int(sys.argv[2])), 0.2); break\n    except OSError as exc:\n        last=exc; time.sleep(0.05)\nelse:\n    raise last\ndata=sys.argv[3].encode('utf-8'); s.sendall(data); s.shutdown(socket.SHUT_WR); out=s.recv(1024); s.close(); sys.stdout.buffer.write(out)")
  (local command (.. "python3 -c " (shell-quote script) " " (shell-quote host) " " (shell-quote port) " " (shell-quote payload)))
  (local pipe (assert (io.popen command :r) "open python tcp client"))
  (local output (pipe:read :*a))
  (local (ok _why _code) (pipe:close))
  (assert ok "python tcp client should exit successfully")
  output)

(fn operation-events [events operation-id]
  (local result [])
  (each [_ event (ipairs events)]
    (when (= event.operation-id operation-id)
      (table.insert result event)))
  result)

(fn find-event [events operation-id kind]
  (var found nil)
  (each [_ event (ipairs events)]
    (when (and (= event.operation-id operation-id)
               (= event.kind kind))
      (set found event)))
  found)

(fn poll-ssh-until-match [ssh predicate collected state]
  (local events (ssh.poll))
  (each [_ event (ipairs events)]
    (table.insert collected event)
    (when (and (not state.matched) (predicate event collected))
      (set state.matched event)))
  (not (= state.matched nil)))

(fn wait-for [ssh predicate message timeout-ms]
  (local callbacks (require :callbacks))
  (local collected [])
  (local state {:matched nil})
  (fn until-match []
    (poll-ssh-until-match ssh predicate collected state))
  (local ok
    (callbacks.run-loop
      {:poll-jobs false
       :poll-http false
       :poll-process false
       :sleep-ms 5
       :timeout-ms (or timeout-ms 10000)
       :until until-match}))
  (assert ok message)
  (values state.matched collected))

(fn kind-matches? [operation-id kind event]
  (and (= event.operation-id operation-id)
       (= event.kind kind)))

(fn terminal-matches? [operation-id event]
  (and (= event.operation-id operation-id)
       (terminal-event? event)))

(fn wait-for-kind [ssh operation-id kind message]
  (wait-for ssh
            (fn [event _events]
              (kind-matches? operation-id kind event))
            message))

(fn wait-for-terminal [ssh operation-id message]
  (wait-for ssh
            (fn [event _events]
              (terminal-matches? operation-id event))
            message))

(fn connect-options [fixture policy]
  (local options {:target {:host fixture.host :port fixture.port :username fixture.username}
                  :auth-methods [{:type "private-key" :key-path fixture.key-path}]
                  :known-hosts-path fixture.known-hosts-path
                  :timeout-ms 10000})
  (when policy
    (tset options :known-host-policy policy))
  options)

(fn maybe-skip-unavailable [terminal]
  (when (and (= terminal.kind "operation-error")
             (= terminal.error-code "unavailable-backend"))
    (print "SKIP SSH integration fixture: SSH backend unavailable in this build")
    true))

(fn assert-success [event message]
  (assert (= event.kind "operation-success") (.. message ": " (tostring event.kind) " " (tostring event.error-code))))

(fn connect-with-known-host-acceptance [ssh fixture]
  (local rejected-op (ssh.connect (connect-options fixture nil)))
  (local (rejected) (wait-for-terminal ssh rejected-op "default known-host rejection should finish"))
  (if (maybe-skip-unavailable rejected)
      (values nil true)
      (do
        (assert (= rejected.kind "operation-error") "unknown host should be rejected by default")
        (assert (= rejected.error-code "unknown-host") "unknown host rejection should be structured")

        (local connect-op (ssh.connect (connect-options fixture "ask")))
        (local (challenge) (wait-for-kind ssh connect-op "known-host-challenge" "known-host challenge should be emitted"))
        (assert (= challenge.error-code "unknown-host") "known-host challenge should identify unknown host")
        (assert (= challenge.fields.host fixture.host) "known-host challenge should include target host")
        (assert (= challenge.fields.port (tostring fixture.port)) "known-host challenge should include target port")
        (assert (= challenge.fields.username fixture.username) "known-host challenge should include username")
        (assert (= challenge.fields.known-hosts-path fixture.known-hosts-path) "known-host challenge should include known-hosts path")
        (assert (= challenge.fields.known-hosts-source "configured") "known-host challenge should identify known-hosts source")
        (assert (= challenge.fields.reason "unknown-host") "known-host challenge should include reason")
        (assert (and challenge.fields.key-type (> (# challenge.fields.key-type) 0)) "known-host challenge should include key type")
        (assert (and challenge.fields.fingerprint (> (# challenge.fields.fingerprint) 0)) "known-host challenge should include fingerprint")
        (assert (ssh.resolve-known-host connect-op "accept-and-store") "known-host decision should be accepted")
        (local (_terminal events) (wait-for-terminal ssh connect-op "accepted known-host connect should finish"))
        (local connected (find-event events connect-op "connected"))
        (local success (find-event events connect-op "operation-success"))
        (assert connected "accepted connection should emit connected event")
        (assert-success success "accepted connection should succeed")
        (values connected.session-id false))))

(fn exec-nonzero [ssh session-id]
  (local op (ssh.exec session-id {:command "printf stdout-ok; printf stderr-ok >&2; exit 7" :timeout-ms 10000}))
  (local (_terminal events) (wait-for-terminal ssh op "exec should finish"))
  (local stdout (find-event events op "exec-stdout"))
  (local stderr (find-event events op "exec-stderr"))
  (local complete (find-event events op "exec-complete"))
  (local success (find-event events op "operation-success"))
  (assert stdout "exec should emit stdout")
  (assert stderr "exec should emit stderr")
  (assert complete "exec should emit completion")
  (assert-success success "nonzero exec transport should succeed")
  (assert (= stdout.fields.data "stdout-ok") "exec stdout should match")
  (assert (= stderr.fields.data "stderr-ok") "exec stderr should match")
  (assert (= complete.fields.exit-status "7") "exec exit status should be captured"))

(fn exec-env [ssh session-id]
  (local op (ssh.exec session-id {:command "printf %s \"$SPACE_SSH_ENV_PROBE\"" :env {:SPACE_SSH_ENV_PROBE "env-ok"} :timeout-ms 10000}))
  (local (_terminal events) (wait-for-terminal ssh op "exec env should finish"))
  (local stdout (find-event events op "exec-stdout"))
  (local success (find-event events op "operation-success"))
  (assert stdout "exec env should emit stdout")
  (assert-success success "exec env transport should succeed")
  (assert (= stdout.fields.data "env-ok") "exec env should be visible to remote command"))

(fn sftp-round-trip [ssh fixture session-id]
  (local payload (.. "space\0ssh\255payload\n" (string.char 1 2 3 250)))
  (local local-path (.. fixture.root "/local-payload.bin"))
  (local download-path (.. fixture.root "/download-payload.bin"))
  (local remote-path (.. fixture.root "/remote-payload.bin"))
  (write-file local-path payload)
  (local upload-op (ssh.sftp-upload session-id {:local-path local-path :remote-path remote-path :timeout-ms 10000}))
  (local (upload-terminal) (wait-for-terminal ssh upload-op "sftp upload should finish"))
  (assert-success upload-terminal "sftp upload should succeed")
  (local download-op (ssh.sftp-download session-id {:local-path download-path :remote-path remote-path :timeout-ms 10000}))
  (local (download-terminal) (wait-for-terminal ssh download-op "sftp download should finish"))
  (assert-success download-terminal "sftp download should succeed")
  (assert (= (read-file download-path) payload) "sftp binary payload should round trip exactly"))

(fn shell-round-trip [ssh session-id]
  (local shell-op (ssh.open-shell session-id {:request-pty false :timeout-ms 10000}))
  (local (_terminal events) (wait-for-terminal ssh shell-op "shell open should finish"))
  (local opened (find-event events shell-op "shell-opened"))
  (assert opened "shell should emit shell-opened")
  (local channel-id opened.channel-id)
  (local write-op (ssh.channel-write channel-id "printf shell-ok\\n\nexit\n"))
  (local (write-terminal) (wait-for-terminal ssh write-op "shell write should finish"))
  (assert-success write-terminal "shell write should succeed")
  (wait-for ssh
            (fn [event _events]
              (and (= event.kind "channel-data")
                   (= event.channel-id channel-id)
                   event.fields
                   event.fields.data
                   (string.find event.fields.data "shell-ok" 1 true)))
            "shell should return command output")
  (local close-op (ssh.channel-close channel-id))
  (local (close-terminal) (wait-for-terminal ssh close-op "shell close should finish"))
  (assert-success close-terminal "shell close should succeed"))

(fn local-tunnel-round-trip [ssh fixture session-id]
  (if (not (and fixture.echo-host fixture.echo-port fixture.local-tunnel-port))
      (print "SKIP SSH local tunnel payload relay: fixture echo endpoint not provided")
      (do
        (local tunnel-op (ssh.open-local-tunnel session-id {:local-host "127.0.0.1"
                                                           :local-port fixture.local-tunnel-port
                                                           :remote-host fixture.echo-host
                                                           :remote-port fixture.echo-port
                                                           :timeout-ms 10000}))
        (local (_terminal events) (wait-for-terminal ssh tunnel-op "local tunnel should open"))
        (local opened (find-event events tunnel-op "tunnel-opened"))
        (local success (find-event events tunnel-op "operation-success"))
        (assert opened "local tunnel should emit tunnel-opened")
        (assert-success success "local tunnel should succeed")
        (assert (= (python-tcp-round-trip "127.0.0.1" fixture.local-tunnel-port "tunnel-ok") "tunnel-ok")
                "local tunnel should relay a TCP payload to fixture echo endpoint")
        (local close-op (ssh.close-tunnel opened.tunnel-id))
        (local (close-terminal) (wait-for-terminal ssh close-op "local tunnel close should finish"))
        (assert-success close-terminal "local tunnel close should succeed"))))

(fn remote-tunnel [ssh fixture session-id]
  (assert fixture.remote-tunnel-port "remote tunnel fixture listen port must be provided")
  (assert (> fixture.remote-tunnel-port 0) "remote tunnel fixture port must be positive")
  (local op (ssh.open-remote-tunnel session-id {:remote-host "127.0.0.1"
                                                :remote-port fixture.remote-tunnel-port
                                                :local-host "127.0.0.1"
                                                :local-port 9
                                                :timeout-ms 10000}))
  (local (terminal) (wait-for-terminal ssh op "remote tunnel should return terminal state"))
  (if (= terminal.kind "operation-success")
      true
      (do
        (assert (= terminal.kind "operation-error") "remote tunnel failure should be structured")
        (assert (= terminal.error-code "unsupported") "remote tunnel unsupported should be explicit"))))

(fn cancel-long-running-exec [ssh session-id]
  (local op (ssh.exec session-id {:command "sleep 30" :timeout-ms 60000}))
  (assert (ssh.cancel op) "cancel should accept active long-running exec")
  (local (terminal) (wait-for-terminal ssh op "cancelled exec should finish"))
  (assert (= terminal.kind "operation-cancelled") "cancelled exec should emit operation-cancelled")
  (assert (= terminal.error-code "cancelled") "cancelled exec should use cancelled error-code"))

(fn real-ssh-fixture-covers-foundation []
  (local (fixture skip-message) (fixture-config))
  (if (not fixture)
      (print (.. "SKIP " skip-message))
      (do
        (local ssh (require :ssh))
        (local (session-id unavailable?) (connect-with-known-host-acceptance ssh fixture))
        (when (not unavailable?)
          (exec-nonzero ssh session-id)
          (exec-env ssh session-id)
          (sftp-round-trip ssh fixture session-id)
          (shell-round-trip ssh session-id)
          (local-tunnel-round-trip ssh fixture session-id)
          (remote-tunnel ssh fixture session-id)
          (cancel-long-running-exec ssh session-id)
          (ssh.close-session session-id)))))

(table.insert tests {:name "SSH integration fixture covers real SSH operations or skips clearly"
                     :fn real-ssh-fixture-covers-foundation})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "ssh-integration" :tests tests})))

{:name "ssh-integration" :tests tests :main main}
