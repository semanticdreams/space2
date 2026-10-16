(local tests [])
(local fs (require :fs))
(local zmq (require :zmq))
(local RemoteControl (require :remote-control))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "remote-control"))

(fn next-path []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "rc-" (os.time) "-" temp-counter ".sock")))

(fn with-endpoint [f]
  (when (not (fs.exists temp-root))
    (fs.create-dirs temp-root))
  (local path (next-path))
  (when (fs.exists path)
    (fs.remove path))
  (local endpoint (.. "ipc://" path))
  (local (ok result) (pcall f endpoint path))
  (when (fs.exists path)
    (fs.remove path))
  (if ok
      result
      (error result)))

(fn read-reply [client rc timeout-ms]
  "Wait for a reply on the client socket using zmq.poll with bounded tick,
  up to timeout-ms.  Returns the reply message or nil on timeout."
  (local sysinfo (require :sysinfo))
  (local recv-flags (. zmq :recv-flags))
  (local poll-events (. zmq :poll-events))
  (local deadline (+ (sysinfo.now-ms) timeout-ms))
  (var reply nil)
  (while (and (not reply) (< (sysinfo.now-ms) deadline))
    (rc:tick)
    ;; Poll for readability, capping the interval to the remaining budget
    (local remaining (- deadline (sysinfo.now-ms)))
    (local poll-timeout (math.min 50 (math.max 0 remaining)))
    (local ready (zmq.poll [{:socket client :events poll-events.IN}] poll-timeout))
    (local entry (. ready 1))
    (when (and entry entry.revents (> entry.revents 0))
      (set reply (client:recv recv-flags.DONTWAIT))))
  reply)

(fn permitted? [err-msg]
  "Return true if the error message indicates a known permission/protocol issue
  that should skip the test rather than fail."
  (if (string.find err-msg "Operation not permitted" 1 true) true
      (string.find err-msg "Permission denied" 1 true) true
      (string.find err-msg "Protocol not supported" 1 true) true))

(fn remote-control-ok []
  (with-endpoint
    (fn [endpoint _path]
      (local socket-types (. zmq :socket-types))
      (local (ok rc-or-error) (pcall (fn [] (RemoteControl {:endpoint endpoint}))))
      (when (not ok)
        (when (permitted? rc-or-error)
          (print "Skipping remote control test: ipc bind not permitted")
          (lua "return true"))
        (error rc-or-error))
      (local rc rc-or-error)
      (local ctx (zmq.Context 1))
      (local client (ctx:socket socket-types.REQ))
      (client:connect endpoint)
      (client:send "(+ 1 2)")
      (local reply (read-reply client rc 2000))
      (assert reply "expected reply")
      (assert (= (reply:to-string) "ok 3"))
      (client:close)
      (ctx:close)
      (rc:drop))))

(fn remote-control-error []
  (with-endpoint
    (fn [endpoint _path]
      (local socket-types (. zmq :socket-types))
      (local (ok rc-or-error) (pcall (fn [] (RemoteControl {:endpoint endpoint}))))
      (when (not ok)
        (when (permitted? rc-or-error)
          (print "Skipping remote control test: ipc bind not permitted")
          (lua "return true"))
        (error rc-or-error))
      (local rc rc-or-error)
      (local ctx (zmq.Context 1))
      (local client (ctx:socket socket-types.REQ))
      (client:connect endpoint)
      (client:send "(error \"boom\")")
      (local reply (read-reply client rc 2000))
      (assert reply "expected reply")
      (local reply-text (reply:to-string))
      (assert (= (string.sub reply-text 1 6) "error "))
      (client:close)
      (ctx:close)
      (rc:drop))))

(table.insert tests {:name "remote control executes code" :fn remote-control-ok})
(table.insert tests {:name "remote control reports errors" :fn remote-control-error})

(fn check-bounded-tick [endpoint _path]
  (local rc (RemoteControl {:endpoint endpoint}))
  (assert (= (rc:tick 1) 0) "idle tick must return handled count")
  (local ctx (zmq.Context 1))
  (local clients [])
  (for [_ 1 2]
    (local client (ctx:socket (. zmq.socket-types :REQ)))
    (client:set-option-int "linger" 0)
    (client:connect endpoint)
    (client:send "(remote_control.create)")
    (table.insert clients client))
  (local sysinfo (require :sysinfo))
  (local deadline (+ (sysinfo.now-ms) 2000))
  (var handled 0)
  (while (and (< handled 2) (< (sysinfo.now-ms) deadline))
    (local count (rc:tick 1))
    (assert (and (>= count 0) (<= count 1)) "bounded tick handled more than one request")
    (set handled (+ handled count)))
  (assert (= handled 2))
  (each [_ client (ipairs clients)]
    (local reply (read-reply client rc 2000))
    (assert reply)
    (local text (reply:to-string))
    (assert (= (string.sub text 1 3) "ok "))
    (local id (string.sub text 4))
    (assert (= (. (_G.remote_control.poll id true) :status) "pending"))
    (_G.remote_control.resolve id "survives")
    (assert (= (. (_G.remote_control.poll id) :value) "survives"))
    (client:close))
  (ctx:close)
  (rc:drop)
  (assert (= (rc:tick 1) 0)))

(fn bounded-tick [] (with-endpoint check-bounded-tick))
(table.insert tests {:name "remote control bounded tick counts requests and preserves async API" :fn bounded-tick})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "remote-control"
                       :tests tests})))

{:name "remote-control"
 :tests tests
 :main main}
