(local tests [])

(fn contains? [value needle]
  (and (= (type value) :string)
       (not (= (string.find value needle 1 true) nil))))

(fn install-fake [fake f]
  (local previous-ssh (. package.loaded "ssh"))
  (local previous-fleet (. package.loaded "ssh.fleet"))
  (set (. package.loaded "ssh") fake)
  (set (. package.loaded "ssh.fleet") nil)
  (local (ok result) (pcall f))
  (if previous-ssh
      (set (. package.loaded "ssh") previous-ssh)
      (set (. package.loaded "ssh") nil))
  (if previous-fleet
      (set (. package.loaded "ssh.fleet") previous-fleet)
      (set (. package.loaded "ssh.fleet") nil))
  (if ok result (error result)))

(fn make-success-fake []
  (local fake {:next-op 1 :started 0 :finished 0 :max-active 0 :connect-options [] :exec-options [] :operations {} :cancelled {}})
  (set fake.connect
       (fn [opts]
         (local op fake.next-op)
         (set fake.next-op (+ fake.next-op 1))
         (set fake.started (+ fake.started 1))
         (set fake.max-active (math.max fake.max-active (- fake.started fake.finished)))
         (table.insert fake.connect-options opts)
         (set (. fake.operations op) {:phase :connect :session-id (+ 100 op)})
         op))
  (set fake.exec
       (fn [session-id opts]
         (local op fake.next-op)
         (set fake.next-op (+ fake.next-op 1))
         (table.insert fake.exec-options opts)
         (set (. fake.operations op) {:phase :exec :session-id session-id})
         op))
  (set fake.cancel
       (fn [op]
         (set (. fake.cancelled op) true)
         true))
  (set fake.poll
       (fn []
         (var selected-op nil)
         (var selected nil)
         (each [op state (pairs fake.operations)]
           (when (not selected-op)
             (set selected-op op)
             (set selected state)))
         (if (not selected-op)
             []
             (do
               (set (. fake.operations selected-op) nil)
               (if (= selected.phase :connect)
                   [{:kind "connected" :operation-id selected-op :session-id selected.session-id}
                    {:kind "operation-success" :operation-id selected-op :session-id selected.session-id}]
                   (do
                     (set fake.finished (+ fake.finished 1))
                     [{:kind "exec-stdout" :operation-id selected-op :fields {:data "out"}}
                      {:kind "exec-stderr" :operation-id selected-op :fields {:data "err"}}
                      {:kind "exec-complete" :operation-id selected-op :fields {:exit-status "7"}}
                      {:kind "operation-success" :operation-id selected-op :session-id selected.session-id}]))))))
  fake)

(fn fleet-concurrency-results-and-known-host-pass-through []
  (local fake (make-success-fake))
  (install-fake fake
    (fn []
      (local fleet (require :ssh.fleet))
      (local hosts [{:host "a" :port 22 :username "u1" :known-host-policy "accept-once" :known-hosts-path "/tmp/known"}
                    {:host "b" :port 2222 :username "u2"}])
      (local results (fleet.exec hosts {:command "uptime" :concurrency 1}))
      (assert (= fake.max-active 1) "fleet should honor concurrency limit")
      (assert (= (length results) 2) "fleet should return one result per host")
      (local first (. results 1))
      (assert (= first.host "a"))
      (assert (= first.port 22))
      (assert (= first.username "u1"))
      (assert (= first.ok true))
      (assert (= first.exit-status 7))
      (assert (= first.stdout "out"))
      (assert (= first.stderr "err"))
      (assert (= first.error-code nil))
      (assert (= first.error nil))
      (assert (= (type first.duration-ms) :number))
      (assert (= (. fake.connect-options 1 :known-host-policy) "accept-once"))
      (assert (= (. fake.connect-options 1 :known-hosts-path) "/tmp/known")))))

(fn make-idle-fake []
  (local fake {:next-op 1 :cancelled {}})
  (set fake.connect
       (fn [_opts]
         (local op fake.next-op)
         (set fake.next-op (+ fake.next-op 1))
         op))
  (set fake.exec (fn [_session-id _opts] (error "exec should not run before connect")))
  (set fake.cancel
       (fn [op]
         (set (. fake.cancelled op) true)
         true))
  (set fake.poll (fn [] []))
  fake)

(fn per-host-timeout-cancels-operation []
  (local fake (make-idle-fake))
  (install-fake fake
    (fn []
      (local fleet (require :ssh.fleet))
      (local results (fleet.exec [{:host "slow" :username "u"}] {:command "id" :timeout-ms 1 :concurrency 1}))
      (local result (. results 1))
      (assert (= result.ok false))
      (assert (= result.error-code "timeout"))
      (assert (= (. fake.cancelled 1) true) "timeout should call ssh.cancel"))))

(fn make-cancelling-fake []
  (local fake {:next-op 1 :cancelled {} :cancel-issued false})
  (set fake.connect
       (fn [_opts]
         (local op fake.next-op)
         (set fake.next-op (+ fake.next-op 1))
         (set fake.operation-id op)
         op))
  (set fake.exec (fn [_session-id _opts] (error "exec should not run after cancellation")))
  (set fake.cancel
       (fn [op]
         (set (. fake.cancelled op) true)
         true))
  (set fake.poll
       (fn []
         (if fake.cancel-issued
             []
             (do
               (set fake.cancel-issued true)
               (fake.cancel fake.operation-id)
               [{:kind "operation-cancelled" :operation-id fake.operation-id :error-code "cancelled" :message "cancelled"}]))))
  fake)

(fn cancellation-produces-cancelled-result []
  (local fake (make-cancelling-fake))
  (install-fake fake
    (fn []
      (local fleet (require :ssh.fleet))
      (local results (fleet.exec [{:host "cancel" :username "u"}] {:command "id" :concurrency 1}))
      (local result (. results 1))
      (assert (= result.ok false))
      (assert (= result.error-code "cancelled"))
      (assert (= (. fake.cancelled 1) true)))))

(fn make-secret-error-fake []
  (local fake {:next-op 1})
  (set fake.connect
       (fn [_opts]
         (local op fake.next-op)
         (set fake.next-op (+ fake.next-op 1))
         op))
  (set fake.exec (fn [_session-id _opts] (error "exec should not run after connect error")))
  (set fake.cancel (fn [_op] true))
  (set fake.poll
       (fn []
         [{:kind "operation-error" :operation-id 1 :error-code "auth-failed" :message "password secret failed"}]))
  fake)

(fn credential-material-is-redacted-from-results []
  (local fake (make-secret-error-fake))
  (install-fake fake
    (fn []
      (local fleet (require :ssh.fleet))
      (local results (fleet.exec [{:host "h" :username "u" :auth-methods [{:type "password" :password "secret"}]}]
                                 {:command "id" :concurrency 1}))
      (local result (. results 1))
      (assert (= result.ok false))
      (assert (= result.error-code "auth-failed"))
      (assert (not result.password) "password should not be copied to results")
      (assert (not (contains? result.error "secret")) "secret should be redacted from result error"))))

(table.insert tests {:name "SSH fleet honors concurrency and returns canonical result fields" :fn fleet-concurrency-results-and-known-host-pass-through})
(table.insert tests {:name "SSH fleet per-host timeout cancels active operation" :fn per-host-timeout-cancels-operation})
(table.insert tests {:name "SSH fleet cancellation produces cancelled result" :fn cancellation-produces-cancelled-result})
(table.insert tests {:name "SSH fleet omits credential material from results" :fn credential-material-is-redacted-from-results})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "ssh-fleet" :tests tests})))

{:name "ssh-fleet" :tests tests :main main}
