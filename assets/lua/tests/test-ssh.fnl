(local tests [])

(local native-names
  ["connect" "resolve-known-host" "close-session" "exec"
   "sftp-upload" "sftp-download" "open-shell" "channel-write"
   "channel-resize" "channel-close" "open-local-tunnel"
   "open-remote-tunnel" "close-tunnel" "cancel" "poll"])

(fn require-ssh-returns-table []
  (local ssh (require :ssh))
  (assert (= (type ssh) :table) "ssh module should return a table"))

(fn native-functions-use-kebab-case []
  (local ssh (require :ssh))
  (each [_ name (ipairs native-names)]
    (assert (= (type (. ssh name)) :function)
            (.. "ssh." name " should be present"))))

(fn invalid-connect-options-raise []
  (local ssh (require :ssh))
  (local (ok err) (pcall (fn []
                           (ssh.connect {:target {:host "example.invalid"}
                                         :authMethods []}))))
  (assert (= ok false) "invalid camelCase option should raise")
  (assert (string.find (tostring err) "authMethods" 1 true)
          "error should identify the invalid option"))

(fn terminal-ssh-event? [event]
  (if (= event.kind "operation-error")
      true
      (= event.kind "operation-success")
      true
      (= event.kind "operation-timeout")
      true
      (= event.kind "operation-cancelled")))

(fn terminal-event-callback [set-terminal]
  (fn [event]
    (when (terminal-ssh-event? event)
      (set-terminal event))))

(fn terminal-ready? [get-terminal]
  (fn []
    (not (= (get-terminal) nil))))

(fn read-existing-file! [paths]
  (var contents nil)
  (each [_ path (ipairs paths)]
    (when (not contents)
      (local file (io.open path :r))
      (when file
        (set contents (assert (file:read :*a) (.. "failed to read " path)))
        (file:close))))
  (assert contents (.. "failed to open any CMake cache path: " (table.concat paths ", ")))
  contents)

(fn cmake-cache-enabled? [contents key]
  (not (= (string.match contents (.. key ":BOOL=ON")) nil)))

(fn cmake-cache-found? [contents key]
  (not (= (string.match contents (.. key ":INTERNAL=1")) nil)))

(fn ssh-backend-available-from-cmake-cache? []
  (local contents (read-existing-file! ["CMakeCache.txt" "build/CMakeCache.txt"]))
  (and (cmake-cache-enabled? contents "SPACE_ENABLE_SSH")
       (cmake-cache-found? contents "LIBSSH_FOUND")))

(fn unavailable-backend-callback-result-is-structured []
  (local ssh (require :ssh))
  (local callbacks (require :callbacks))
  (var terminal nil)
  (local set-terminal (fn [event] (set terminal event)))
  (local get-terminal (fn [] terminal))
  (local operation-id (ssh.connect {:target {:host "example.invalid"}}
                                   (terminal-event-callback set-terminal)))
  (local completed (callbacks.run-loop {:poll-jobs false
                                        :poll-http false
                                        :poll-process false
                                        :sleep-ms 1
                                        :timeout-ms 200
                                        :until (terminal-ready? get-terminal)}))
  (assert completed "ssh connect should produce a terminal callback event")
  (assert (= terminal.operation-id operation-id)
          "terminal backend event should include the operation id")
  (when (not (ssh-backend-available-from-cmake-cache?))
    (assert (= terminal.kind "operation-error")
            "unavailable backend should be reported as operation-error")
    (assert (= terminal.error-code "unavailable-backend")
            "unavailable backend should use structured error-code")))

(fn no-compatibility-aliases []
  (local ssh (require :ssh))
  (each [_ name (ipairs ["resolveKnownHost" "closeSession" "sftpUpload"
                         "sftpDownload" "openShell" "channelWrite"
                         "channelResize" "channelClose" "openLocalTunnel"
                         "openRemoteTunnel" "closeTunnel" "auth_methods"
                         "timeout_ms"])]
    (assert (= (. ssh name) nil) (.. "ssh facade should not expose alias " name))))

(table.insert tests {:name "SSH facade require returns table" :fn require-ssh-returns-table})
(table.insert tests {:name "SSH facade exposes native kebab-case functions" :fn native-functions-use-kebab-case})
(table.insert tests {:name "SSH facade invalid connect options raise" :fn invalid-connect-options-raise})
(table.insert tests {:name "SSH facade unavailable backend callback result is structured" :fn unavailable-backend-callback-result-is-structured})
(table.insert tests {:name "SSH facade does not introduce compatibility aliases" :fn no-compatibility-aliases})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "ssh" :tests tests})))

{:name "ssh" :tests tests :main main}
