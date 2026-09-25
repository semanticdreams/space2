(local tests [])
(local Services (require :app-host.services))

(fn assert-error-contains [f expected]
  (local (ok err) (pcall f))
  (assert (= ok false))
  (assert (string.find (tostring err) expected 1 true)))

(fn test-registry_register_unregister_list_clear []
  (local registry (Services.make-registry "widgets"))
  (local item {:id :a})
  (assert (= (registry:register item) item))
  (assert (= (# (registry:list)) 1))
  (assert (= (registry:unregister item) true))
  (assert (= (# (registry:list)) 0))
  (registry:register item)
  (assert (= (registry:clear) true))
  (assert (= (# (registry:list)) 0)))

(fn test-scheduler_pause_update_and_step []
  (local scheduler (Services.make-scheduler))
  (local calls [])
  (local facet {:update (fn [_self delta] (table.insert calls delta))})
  (scheduler:register facet)
  (scheduler:update 16)
  (scheduler:set-paused true)
  (scheduler:update 32)
  (scheduler:step 48)
  (assert (= (# calls) 2))
  (assert (= (. calls 1) 16))
  (assert (= (. calls 2) 48)))

(fn test-input_dispatches_registered_handlers []
  (local input (Services.make-input))
  (var seen nil)
  (local handler {:key-down (fn [_self payload] (set seen payload.key))})
  (input:register handler)
  (input:dispatch :key-down {:key 81})
  (assert (= seen 81)))

(fn test-services_fail_loudly_on_invalid_payloads []
  (local registry (Services.make-registry "widgets"))
  (assert-error-contains #(registry:register nil) "widgets:register requires a facet")
  (local scheduler (Services.make-scheduler))
  (assert-error-contains #(scheduler:register nil) "scheduler:register requires a facet table")
  (local input (Services.make-input))
  (assert-error-contains #(input:register nil) "input:register requires a handler table"))

(table.insert tests {:name "registry register unregister list clear"
                     :fn test-registry_register_unregister_list_clear})
(table.insert tests {:name "scheduler pause update and step"
                     :fn test-scheduler_pause_update_and_step})
(table.insert tests {:name "input dispatches registered handlers"
                     :fn test-input_dispatches_registered_handlers})
(table.insert tests {:name "services fail loudly on invalid payloads"
                     :fn test-services_fail_loudly_on_invalid_payloads})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "app-host-services"
                       :tests tests})))

{:name "app-host-services"
 :tests tests
 :main main}
