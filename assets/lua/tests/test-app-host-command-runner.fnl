(local Runner (require :tests/runner))
(local CommandRunner (require :app-host.command-runner))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn assert-error-contains [f expected]
  (local (ok err) (pcall f))
  (assert (= ok false) "expected call to fail")
  (assert (string.find (tostring err) expected 1 true)
          (.. "expected error to contain " expected ", got " (tostring err))))

(fn registry-list [self]
  (local out [])
  (each [_ item (ipairs self.items)]
    (table.insert out item))
  out)

(fn registry [items]
  {:items items :list registry-list})

(fn host-with-commands [commands]
  {:commands (registry commands)})

(fn no-op-command-run []
  true)

(fn exploding-command-run [_self _payload]
  (error "boom"))

(fn restart-command-run [self payload]
  (set self.state.ran-restart? true)
  (set self.state.received-payload payload)
  {:self-id self.id :payload-value payload.value})

(fn other-command-run [self _payload]
  (set self.state.ran-other? true))

(fn run-host-with-missing-host []
  (CommandRunner.run-host nil :restart {}))

(fn run-host-with-missing-commands []
  (CommandRunner.run-host {} :restart {}))

(fn run-host-with-missing-list []
  (CommandRunner.run-host {:commands {}} :restart {}))

(fn run-host-with-missing-command-id []
  (CommandRunner.run-host (host-with-commands []) nil {}))

(fn run-host-with-unknown-command []
  (CommandRunner.run-host (host-with-commands []) :missing {}))

(fn run-host-with-duplicate-command []
  (CommandRunner.run-host (host-with-commands [{:id :dup :run no-op-command-run}
                                                {:id :dup :run no-op-command-run}]) :dup {}))

(fn run-host-with-command-missing-run []
  (CommandRunner.run-host (host-with-commands [{:id :bad}]) :bad {}))

(fn test-runs-matching-command-with-payload []
  (local state {:ran-restart? false :ran-other? false :received-payload nil})
  (local restart-command {:id :restart
                          :state state
                          :run restart-command-run})
  (local host (host-with-commands [restart-command
                                   {:id :other
                                    :state state
                                    :run other-command-run}]))
  (local result (CommandRunner.run-host host :restart {:value 42}))
  (assert (= result.id :restart))
  (assert (= result.status :ok))
  (assert (= result.value.self-id :restart))
  (assert (= result.value.payload-value 42))
  (assert (= state.ran-restart? true))
  (assert (= state.ran-other? false) "non-matching commands must not run")
  (assert (= state.received-payload.value 42)))

(add-test "runs matching command with payload" test-runs-matching-command-with-payload)

(fn test-command-handler-errors-return-error-result []
  (local host (host-with-commands [{:id :explode
                                    :run exploding-command-run}]))
  (local result (CommandRunner.run-host host :explode {:why :test}))
  (assert (= result.id :explode))
  (assert (= result.status :error))
  (assert (string.find result.error "boom" 1 true)))

(add-test "command handler errors return error result" test-command-handler-errors-return-error-result)

(fn test-structural-command-failures-are-loud []
  (assert-error-contains run-host-with-missing-host "host table")
  (assert-error-contains run-host-with-missing-commands "commands")
  (assert-error-contains run-host-with-missing-list "list")
  (assert-error-contains run-host-with-missing-command-id "command id")
  (assert-error-contains run-host-with-unknown-command "not found")
  (assert-error-contains run-host-with-duplicate-command "duplicate")
  (assert-error-contains run-host-with-command-missing-run "run"))

(add-test "structural command failures are loud" test-structural-command-failures-are-loud)

(fn main []
  (Runner.run-tests {:name "app-host-command-runner" :tests tests}))

{:main main :tests tests}
