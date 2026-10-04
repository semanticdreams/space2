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

(fn unavailable-backend-poll-result-is-structured []
  (local ssh (require :ssh))
  (local operation-id (ssh.connect {:target {:host "example.invalid"}}))
  (var unavailable nil)
  (var attempts 0)
  (while (and (not unavailable) (< attempts 50))
    (set attempts (+ attempts 1))
    (each [_ event (ipairs (ssh.poll))]
      (when (and (= event.kind "operation-error")
                 (= event.error-code "unavailable-backend"))
        (set unavailable event))))
  (when unavailable
    (assert (= unavailable.operation-id operation-id)
            "unavailable backend event should include the operation id")
    (assert (= unavailable.error-code "unavailable-backend")
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
(table.insert tests {:name "SSH facade unavailable backend poll result is structured" :fn unavailable-backend-poll-result-is-structured})
(table.insert tests {:name "SSH facade does not introduce compatibility aliases" :fn no-compatibility-aliases})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "ssh" :tests tests})))

{:name "ssh" :tests tests :main main}
