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
               :update fake-scheduler-update
               :set-paused fake-scheduler-set-paused
               :step fake-scheduler-step}
   :inspectors {:items []
                :register fake-register-item}
   :commands {:items []
              :register fake-register-item}
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

(table.insert tests {:name "required capability errors loudly"
                     :fn required-capability-errors-loudly})
(table.insert tests {:name "required capability returns service"
                     :fn required-capability-returns-service})
(table.insert tests {:name "controller mounts runtime facets"
                     :fn test-controller-mounts-runtime-facets})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "app-host-runtime-controller"
                       :tests tests})))

{:main main}
