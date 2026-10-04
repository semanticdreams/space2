(local ssh (require :ssh))
(local callbacks (require :callbacks))

(fn now-ms []
  (* (os.clock) 1000.0))

(fn positive-integer [value fallback]
  (if (and (= (type value) :number) (>= value 1))
      (math.floor value)
      fallback))

(fn has-key? [tbl key]
  (not (= (. tbl key) nil)))

(fn assert-allowed-keys [tbl allowed label]
  (each [key _value (pairs tbl)]
    (assert (= (type key) :string) (.. label " keys must be strings"))
    (assert (has-key? allowed key) (.. label " contains unsupported option " key))))

(fn valid-timeout? [value]
  (and (= (type value) :number) (>= value 0)))

(fn valid-positive-integer? [value]
  (and (= (type value) :number) (>= value 1) (= value (math.floor value))))

(fn validate-host [host index]
  (assert (= (type host) :table) (.. "ssh.fleet host " index " must be a table"))
  (assert-allowed-keys host {:host true
                             :port true
                             :username true
                             :auth-methods true
                             :known-host-policy true
                             :known-hosts-path true
                             :timeout-ms true}
                       (.. "ssh.fleet host " index))
  (assert (and (= (type host.host) :string) (> (# host.host) 0))
          (.. "ssh.fleet host " index " requires string host"))
  (when (not (= host.port nil))
    (assert (and (valid-positive-integer? host.port) (<= host.port 65535))
            (.. "ssh.fleet host " index " port must be an integer from 1 to 65535")))
  (when (not (= host.username nil))
    (assert (= (type host.username) :string)
            (.. "ssh.fleet host " index " username must be a string")))
  (when (not (= host.auth-methods nil))
    (assert (= (type host.auth-methods) :table)
            (.. "ssh.fleet host " index " auth-methods must be a table")))
  (when (not (= host.known-host-policy nil))
    (assert (or (= (type host.known-host-policy) :string)
                (= (type host.known-host-policy) :table))
            (.. "ssh.fleet host " index " known-host-policy must be a string or table")))
  (when (not (= host.known-hosts-path nil))
    (assert (= (type host.known-hosts-path) :string)
            (.. "ssh.fleet host " index " known-hosts-path must be a string")))
  (when (not (= host.timeout-ms nil))
    (assert (valid-timeout? host.timeout-ms)
            (.. "ssh.fleet host " index " timeout-ms must be a non-negative number"))))

(fn validate-inputs [hosts opts]
  (assert (= (type hosts) :table) "ssh.fleet.exec requires hosts")
  (assert (= (type opts) :table) "ssh.fleet.exec opts must be a table")
  (assert-allowed-keys opts {:command true
                             :concurrency true
                             :timeout-ms true
                             :env true}
                       "ssh.fleet opts")
  (assert (and (= (type opts.command) :string) (> (# opts.command) 0))
          "ssh.fleet.exec requires opts.command")
  (when (not (= opts.concurrency nil))
    (assert (valid-positive-integer? opts.concurrency)
            "ssh.fleet opts concurrency must be a positive integer"))
  (when (not (= opts.timeout-ms nil))
    (assert (valid-timeout? opts.timeout-ms)
            "ssh.fleet opts timeout-ms must be a non-negative number"))
  (when (not (= opts.env nil))
    (assert (= (type opts.env) :table)
            "ssh.fleet opts env must be a table"))
  (each [index host (ipairs hosts)]
    (validate-host host index)))

(fn host-port [host]
  (if (= host.port nil)
      22
      host.port))

(fn copy-auth-methods [host]
  (if host.auth-methods
      host.auth-methods
      nil))

(fn connect-options [host timeout-ms]
  (local opts {:target {:host host.host
                        :port (host-port host)
                        :username host.username}})
  (when host.auth-methods
    (set opts.auth-methods (copy-auth-methods host)))
  (when host.known-host-policy
    (set opts.known-host-policy host.known-host-policy))
  (when host.known-hosts-path
    (set opts.known-hosts-path host.known-hosts-path))
  (when timeout-ms
    (set opts.timeout-ms timeout-ms))
  opts)

(fn exec-options [opts timeout-ms]
  (local command (assert opts.command "ssh.fleet.exec requires opts.command"))
  (local out {:command command})
  (when opts.env
    (set out.env opts.env))
  (when timeout-ms
    (set out.timeout-ms timeout-ms))
  out)

(fn credential-values [value out]
  (when (= (type value) :table)
    (each [k v (pairs value)]
      (if (and (= (type k) :string)
               (if (string.find k "password" 1 true)
                   true
                   (not (= (string.find k "passphrase" 1 true) nil))))
          (when (and (= (type v) :string) (> (# v) 0))
            (table.insert out v))
          (= (type v) :table)
          (credential-values v out)))))

(fn redact [message host]
  (var result (tostring (if (= message nil) "" message)))
  (local secrets [])
  (credential-values host secrets)
  (each [_ secret (ipairs secrets)]
    (var start 1)
    (var next-start nil)
    (var next-end nil)
    (local pieces [])
    (while (do
             (local (found-start found-end) (string.find result secret start true))
             (set next-start found-start)
             (set next-end found-end)
             next-start)
      (table.insert pieces (string.sub result start (- next-start 1)))
      (table.insert pieces "[redacted]")
      (set start (+ next-end 1)))
    (when (> (length pieces) 0)
      (table.insert pieces (string.sub result start))
      (set result (table.concat pieces ""))))
  result)

(fn base-result [host started-at]
  {:host host.host
   :port (host-port host)
   :username host.username
   :ok false
   :exit-status nil
   :stdout ""
   :stderr ""
   :error-code nil
   :error nil
   :duration-ms (math.max 0 (- (now-ms) started-at))})

(fn terminal-kind? [kind]
  (if (= kind "operation-success")
      true
      (= kind "operation-error")
      true
      (= kind "operation-timeout")
      true
      (= kind "operation-cancelled")))

(fn failure-code [event]
  (if (= event.kind "operation-timeout")
      "timeout"
      (= event.kind "operation-cancelled")
      "cancelled"
      (not (= event.error-code nil))
      event.error-code
      (and event.fields (not (= (. event.fields :error-code) nil)))
      (. event.fields :error-code)
      "backend-error"))

(fn remove-active [active state]
  (var removed false)
  (var index 1)
  (while (and (not removed) (<= index (length active)))
    (if (= (. active index) state)
        (do
          (table.remove active index)
          (set removed true))
        (set index (+ index 1)))))

(fn finish [state results active op-states ok? error-code error-message]
  (local result (base-result state.host state.started-at))
  (set result.ok ok?)
  (set result.stdout state.stdout)
  (set result.stderr state.stderr)
  (set result.exit-status state.exit-status)
  (set result.error-code error-code)
  (set result.error (and error-message (redact error-message state.host)))
  (set result.duration-ms (math.max 0 (- (now-ms) state.started-at)))
  (set (. results state.index) result)
  (when state.connect-op
    (set (. op-states state.connect-op) nil))
  (when state.exec-op
    (set (. op-states state.exec-op) nil))
  (remove-active active state))

(fn enqueue-event [event-queue]
  (fn [event]
    (table.insert event-queue event)))

(fn event-queued? [event-queue]
  (fn []
    (> (length event-queue) 0)))

(fn has-work? [hosts next-index active]
  (if (<= next-index (length hosts))
      true
      (> (length active) 0)))

(fn start-host [host index opts active op-states event-queue]
  (local timeout-ms (if (= host.timeout-ms nil) opts.timeout-ms host.timeout-ms))
  (local state {:host host
                :index index
                :started-at (now-ms)
                :timeout-ms timeout-ms
                :stdout ""
                :stderr ""
                :exit-status nil
                :phase :connect
                :connect-op nil
                :exec-op nil
                :current-op nil})
  (local operation-id (ssh.connect (connect-options host timeout-ms) (enqueue-event event-queue)))
  (set state.connect-op operation-id)
  (set state.current-op operation-id)
  (set (. op-states operation-id) state)
  (table.insert active state))

(fn start-ready-hosts [hosts opts next-index active op-states event-queue]
  (local concurrency (positive-integer opts.concurrency 4))
  (var index next-index)
  (while (and (<= index (length hosts)) (< (length active) concurrency))
    (start-host (. hosts index) index opts active op-states event-queue)
    (set index (+ index 1)))
  index)

(fn handle-event [event opts results active op-states event-queue]
  (local state (. op-states event.operation-id))
  (when state
    (if (= event.kind "connected")
        (do
          (set state.session-id event.session-id)
          (set state.phase :exec)
          (local exec-op (ssh.exec event.session-id (exec-options opts state.timeout-ms) (enqueue-event event-queue)))
          (set state.exec-op exec-op)
        (set state.current-op exec-op)
        (set (. op-states exec-op) state))
        (= event.kind "exec-stdout")
        (set state.stdout (.. state.stdout (if (and event.fields (not (= (. event.fields :data) nil)))
                                               (. event.fields :data)
                                               "")))
        (= event.kind "exec-stderr")
        (set state.stderr (.. state.stderr (if (and event.fields (not (= (. event.fields :data) nil)))
                                               (. event.fields :data)
                                               "")))
        (= event.kind "exec-complete")
        (set state.exit-status (tonumber (if (and event.fields (not (= (. event.fields :exit-status) nil)))
                                             (. event.fields :exit-status)
                                             0)))
        (and (= event.kind "operation-success") (= event.operation-id state.exec-op))
        (finish state results active op-states true nil nil)
        (and (terminal-kind? event.kind) (not (= event.kind "operation-success")))
        (finish state results active op-states false (failure-code event) event.message))))

(fn enforce-timeouts [results active op-states]
  (local expired [])
  (each [_ state (ipairs active)]
    (when (and state.timeout-ms (> state.timeout-ms 0)
               (>= (- (now-ms) state.started-at) state.timeout-ms))
      (table.insert expired state)))
  (each [_ state (ipairs expired)]
    (ssh.cancel state.current-op)
    (finish state results active op-states false "timeout" "operation timed out")))

(fn exec [hosts opts]
  (local run-opts (if (= opts nil) {} opts))
  (validate-inputs hosts run-opts)
  (local results [])
  (local active [])
  (local op-states {})
  (local event-queue [])
  (var next-index (start-ready-hosts hosts run-opts 1 active op-states event-queue))
  (while (has-work? hosts next-index active)
    (while (> (length event-queue) 0)
      (local event (table.remove event-queue 1))
      (handle-event event run-opts results active op-states event-queue))
    (enforce-timeouts results active op-states)
    (set next-index (start-ready-hosts hosts run-opts next-index active op-states event-queue))
    (when (and (= (length event-queue) 0) (> (length active) 0))
      (callbacks.run-loop {:poll-jobs false
                           :poll-http false
                           :poll-process false
                           :sleep-ms 0
                           :timeout-ms 1
                           :until (event-queued? event-queue)})))
  results)

(fn cancel [token-or-operation-id]
  (local operation-id (if (= (type token-or-operation-id) :table)
                          token-or-operation-id.operation-id
                          token-or-operation-id))
  (ssh.cancel operation-id))

{:exec exec
 :cancel cancel}
