(local tests [])
(local Capabilities (require :app-host.capabilities))
(local RuntimeController (require :app-host.runtime-controller))

(fn required-capability-errors-loudly []
  (local (ok err) (pcall #(Capabilities.require {} :scheduler)))
  (assert (= ok false))
  (assert (string.find (tostring err) "scheduler" 1 true)))

(fn required-capability-returns-service []
  (local service {:register (fn [] nil)})
  (assert (= (Capabilities.require {:scheduler service} :scheduler) service)))

(fn fake-scheduler-register [self registration]
  (set self.registration registration))

(fn fake-scheduler-unregister [self registration]
  (when (= self.registration registration)
    (set self.registration nil)
    true))

(fn fake-scheduler-update [self delta]
  (when (and self.registration (not self.paused?))
    (set self.updates (+ self.updates 1))
    (self.registration:update delta))
  (not self.paused?))

(fn fake-scheduler-set-paused [self paused]
  (set self.paused? paused)
  self.paused?)

(fn fake-scheduler-step [self delta]
  (when self.registration
    (set self.steps (+ self.steps 1))
    (self.registration:update delta))
  true)

(fn fake-register-item [self item]
  (table.insert self.items item))

(fn fake-host []
  {:scheduler {:paused? false
               :updates 0
                :steps 0
                :register fake-scheduler-register
                :unregister fake-scheduler-unregister
                :update fake-scheduler-update
                :set-paused fake-scheduler-set-paused
                :step fake-scheduler-step}
    :inspectors {:items []
                 :register fake-register-item
                 :unregister (fn [self item]
                               (for [i (# self.items) 1 -1]
                                 (when (= (. self.items i) item)
                                   (table.remove self.items i)))
                               true)}
    :commands {:items []
               :register fake-register-item
               :unregister (fn [self item]
                             (for [i (# self.items) 1 -1]
                               (when (= (. self.items i) item)
                                 (table.remove self.items i)))
                             true)}
    :lifecycle {:drops 0}})

(fn fake-render-targets [self]
  self.targets)

(fn fake-runtime-update [self delta]
  (table.insert self.state.update-deltas delta)
  true)

(fn fake-inspector-read []
  {:ok true})

(fn fake-command-run []
  true)

(fn fake-runtime-drop [self]
  (set self.state.drop-calls (+ self.state.drop-calls 1)))

(fn make-hostable-create [expected-host target state]
  (fn [given-host]
    (assert (= given-host expected-host))
    {:metadata {:id "fake-runtime"}
     :presentation {:targets [target]
                    :render-targets fake-render-targets}
     :scheduler {:state state
                 :update fake-runtime-update}
     :inspectors [{:id :state :read fake-inspector-read}]
     :commands [{:id :reset :run fake-command-run}]
     :lifecycle {:state state
                 :drop fake-runtime-drop}}))

(fn test-controller-mounts-runtime-facets []
  (local host (fake-host))
  (local target {:kind :hud})
  (local state {:update-deltas []
                :drop-calls 0})
  (local module {:metadata {:id "fake" :title "Fake" :host-api 1}
                 :create (make-hostable-create host target state)})
  (local controller (RuntimeController.create {:module module :host host}))
  (local runtime (controller:runtime))
  (assert (= runtime.metadata.id "fake-runtime"))
  (assert (= (# (controller:render-targets)) 1))
  (assert (= (. (controller:render-targets) 1) target))
  (assert (= (# host.inspectors.items) 1))
  (assert (= (# host.commands.items) 1))
  (assert (= (# (controller:inspectors)) 1))
  (assert (= (# (controller:commands)) 1))
  (controller:update 16)
  (assert (= host.scheduler.updates 1))
  (assert (= (. state.update-deltas 1) 16))
  (controller:set-paused true)
  (controller:update 16)
  (assert (= host.scheduler.updates 1))
  (controller:step 32)
  (assert (= host.scheduler.steps 1))
  (assert (= (. state.update-deltas 2) 32))
  (controller:drop)
  (controller:drop)
  (assert (= state.drop-calls 1)))

(fn test-controller-drop-unregisters-runtime-facets-once []
  (local host (fake-host))
  (local target {:kind :hud})
  (local state {:update-deltas []
                :drop-calls 0})
  (local module {:metadata {:id "fake" :title "Fake" :host-api 1}
                 :create (make-hostable-create host target state)})
  (local controller (RuntimeController.create {:module module :host host}))
  (assert host.scheduler.registration "scheduler facet should be registered before drop")
  (assert (= (# host.inspectors.items) 1) "inspector facet should be registered before drop")
  (assert (= (# host.commands.items) 1) "command facet should be registered before drop")
  (controller:drop)
  (controller:drop)
  (assert (= host.scheduler.registration nil) "drop must unregister scheduler facet")
  (assert (= (# host.inspectors.items) 0) "drop must unregister inspector facets")
  (assert (= (# host.commands.items) 0) "drop must unregister command facets")
  (controller:update 16)
  (assert (= (# state.update-deltas) 0) "unregistered scheduler facet must not update after drop")
  (assert (= state.drop-calls 1) "runtime lifecycle drop must run exactly once"))

(fn module-with-runtime [runtime]
  {:metadata {:id "malformed" :title "Malformed" :host-api 1}
   :create (fn [_host] runtime)})

(fn assert-create-errors [runtime expected]
  (local (ok err)
    (pcall #(RuntimeController.create {:module (module-with-runtime runtime)
                                       :host (fake-host)})))
  (assert (= ok false) "malformed runtime should fail during controller creation")
  (assert (string.find (tostring err) "[app-host]" 1 true))
  (assert (string.find (tostring err) expected 1 true)))

(fn rejects-malformed-presentation-facet []
  (assert-create-errors {:presentation {:render-targets true}}
                        "presentation"))

(fn rejects-keyed-inspector-and-command-facets []
  (assert-create-errors {:inspectors {:state {:id :state
                                              :read fake-inspector-read}}}
                        "inspectors")
  (assert-create-errors {:commands {:reset {:id :reset
                                            :run fake-command-run}}}
                        "commands"))

(fn rejects-scheduler-facet-without-update []
  (assert-create-errors {:scheduler {:enabled? true}}
                        "scheduler"))

(table.insert tests {:name "required capability errors loudly"
                     :fn required-capability-errors-loudly})
(table.insert tests {:name "required capability returns service"
                     :fn required-capability-returns-service})
(table.insert tests {:name "controller mounts runtime facets"
                      :fn test-controller-mounts-runtime-facets})
(table.insert tests {:name "controller drop unregisters runtime facets once"
                      :fn test-controller-drop-unregisters-runtime-facets-once})
(table.insert tests {:name "controller rejects malformed presentation facet"
                     :fn rejects-malformed-presentation-facet})
(table.insert tests {:name "controller rejects keyed inspector and command facets"
                     :fn rejects-keyed-inspector-and-command-facets})
(table.insert tests {:name "controller rejects scheduler facet without update"
                     :fn rejects-scheduler-facet-without-update})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "app-host-runtime-controller"
                       :tests tests})))

{:main main}
