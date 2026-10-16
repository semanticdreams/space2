(local DEFAULT_WORKFLOW_NAME "Untitled Workflow")
(local DEFAULT_STEP_NAME "Start")
(local DEFAULT_CODE_NAME "Workflow Step")

(fn value-or [value default]
  (if (= value nil) default value))

(fn starter-source []
  "(fn [opts]\n  {:run\n   (fn [self ctx input state]\n     (ctx:succeed {:message \"workflow step completed\"\n                   :input input}))})")

(fn definition-has-step-code? [workflow-store definition-id code-entity-id]
  (var found? false)
  (when (and workflow-store.get-definition definition-id code-entity-id)
    (local (ok definition) (pcall workflow-store.get-definition workflow-store definition-id))
    (when (and ok definition)
      (each [_ step (ipairs (assert definition.steps "workflow definition requires steps"))]
        (when (= step.code-entity-id code-entity-id)
          (set found? true)))))
  found?)

(fn definition-step-code-entity-ids [workflow-store definition-id]
  (local definition (workflow-store:get-definition definition-id))
  (local ids [])
  (when definition
    (each [_ step (ipairs (assert definition.steps "workflow definition requires steps"))]
      (when step.code-entity-id
        (table.insert ids step.code-entity-id))))
  ids)

(fn create-template-code-entity [code-store opts]
  (local options (or opts {}))
  (assert code-store "create-template-code-entity requires code-store")
  (assert code-store.create-entity "create-template-code-entity requires code-store:create-entity")
  (code-store:create-entity {:name (value-or options.name DEFAULT_CODE_NAME)
                             :language "fnl"
                             :source (starter-source)}))

(fn create-template-step [workflow-store code-store definition-id opts]
  (local options (or opts {}))
  (assert workflow-store "create-template-step requires workflow-store")
  (assert workflow-store.add-step "create-template-step requires workflow-store:add-step")
  (assert code-store "create-template-step requires code-store")
  (assert definition-id "create-template-step requires definition-id")
  (local code-entity (create-template-code-entity code-store {:name (value-or options.code-name DEFAULT_CODE_NAME)}))
  (local (ok step-or-err)
    (pcall workflow-store.add-step workflow-store definition-id {:name (value-or options.step-name
                                                                                (value-or options.name DEFAULT_STEP_NAME))
                                                                :code-entity-id code-entity.id}))
  (if ok
      {:step step-or-err :code-entity code-entity}
      (do
        (when (not (definition-has-step-code? workflow-store definition-id code-entity.id))
          (assert code-store.retire-entity! "create-template-step rollback requires code-store:retire-entity!")
          (code-store:retire-entity! code-entity.id))
        (error step-or-err))))

(fn create-template-workflow [workflow-store code-store opts]
  (local options (or opts {}))
  (assert workflow-store "create-template-workflow requires workflow-store")
  (assert workflow-store.create-definition "create-template-workflow requires workflow-store:create-definition")
  (assert workflow-store.delete-definition "create-template-workflow rollback requires workflow-store:delete-definition")
  (assert workflow-store.get-definition "create-template-workflow requires workflow-store:get-definition")
  (local definition (workflow-store:create-definition {:name (value-or options.name DEFAULT_WORKFLOW_NAME)
                                                      :steps []
                                                      :edges []}))
  (local (ok step-result-or-err)
    (pcall create-template-step workflow-store code-store definition.id {:step-name options.step-name
                                                                        :code-name options.code-name}))
  (if ok
      {:definition (assert (workflow-store:get-definition definition.id)
                           "create-template-workflow failed to reload created definition")
       :step step-result-or-err.step
       :code-entity step-result-or-err.code-entity}
      (do
        (local code-entity-ids (definition-step-code-entity-ids workflow-store definition.id))
        (workflow-store:delete-definition definition.id)
        (when (> (length code-entity-ids) 0)
          (assert code-store "create-template-workflow rollback requires code-store")
          (assert code-store.retire-entity! "create-template-workflow rollback requires code-store:retire-entity!")
          (each [_ code-entity-id (ipairs code-entity-ids)]
            (code-store:retire-entity! code-entity-id)))
        (error step-result-or-err))))

{:starter-source starter-source
 :create-template-code-entity create-template-code-entity
 :create-template-step create-template-step
 :create-template-workflow create-template-workflow}
