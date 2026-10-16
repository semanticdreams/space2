(local zmq (require :zmq))
(local logging (require :logging))
(local FennelEvaluator (require :fennel-evaluator))

(var request-counter 0)
(local results {})

(fn next-request-id []
  (set request-counter (+ request-counter 1))
  (.. (os.time) "-" (math.floor (* (os.clock) 1000000)) "-" request-counter))

(fn ensure-entry [id action]
  (local entry (. results id))
  (if (not entry)
      (do
        (logging.warn (.. "[remote-control] " action " unknown id: " (tostring id)))
        nil)
      entry))

(fn expose-api []
  (set _G.remote_control
       {:create (fn []
                  (local id (next-request-id))
                  (set (. results id) {:status "pending"})
                  id)
        :resolve (fn [id value]
                   (local entry (ensure-entry id "resolve"))
                   (if (not entry)
                       nil
                       (do
                         (when (not (= entry.status "pending"))
                           (logging.warn
                             (.. "[remote-control] resolve already finished: " (tostring id))))
                         (set (. results id) {:status "ok" :value value}))))
        :reject (fn [id err]
                  (local entry (ensure-entry id "reject"))
                  (if (not entry)
                      nil
                      (do
                        (when (not (= entry.status "pending"))
                          (logging.warn
                            (.. "[remote-control] reject already finished: " (tostring id))))
                        (set (. results id) {:status "error" :error err}))))
        :poll (fn [id keep?]
                (local entry (ensure-entry id "poll"))
                (if (not entry)
                    {:status "error"
                     :error (.. "[remote-control] poll unknown id: " (tostring id))}
                    (do
                      (when (and (not keep?) (not (= entry.status "pending")))
                        (set (. results id) nil))
                      entry)))}))

(fn RemoteControl [options]
  (assert (and options options.endpoint) "RemoteControl requires :endpoint")
  (local endpoint options.endpoint)
  (local socket-types (. zmq :socket-types))
  (local recv-flags (. zmq :recv-flags))
  (var ctx (zmq.Context 1))
  (var socket (ctx:socket socket-types.REP))
  (socket:set-option-int "linger" 0)
  (socket:bind endpoint)
  (logging.info (string.format "[space] remote control listening on %s" endpoint))
  (var closed false)
  (expose-api)

  (fn send-error [err]
    (socket:send (.. "error " (FennelEvaluator.format-error err))))

  (fn send-ok [value]
    (socket:send (.. "ok " (FennelEvaluator.format-result value))))

  (fn handle-message [msg]
    (local (ok err)
      (pcall
        (fn []
          (local source (msg:to-string))
          (local result (FennelEvaluator.eval-source source))
          (if result.ok
              (send-ok result.result)
              (send-error result.result)))))
    (when (not ok)
      (logging.error (.. "[remote-control] unexpected handler error: " (tostring err)))
      (send-error err)))

  (fn tick [_self limit]
    (assert (or (= limit nil) (and (= (type limit) :number)
                                  (= limit (math.floor limit)) (> limit 0)))
            "RemoteControl.tick limit must be a positive integer")
    (var handled 0)
    (when (not closed)
      (var msg (socket:recv recv-flags.DONTWAIT))
      (while msg
        (handle-message msg)
        (set handled (+ handled 1))
        (set msg (if (and limit (>= handled limit)) nil
                     (socket:recv recv-flags.DONTWAIT)))))
    handled)

  (fn drop []
    (when (not closed)
      (set closed true)
      (when socket
        (socket:close)
        (set socket nil))
      (when ctx
        (ctx:close)
        (set ctx nil))))

  {:endpoint endpoint
   :tick tick
   :drop drop})
