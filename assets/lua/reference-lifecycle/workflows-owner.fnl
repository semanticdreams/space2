(local fs (require :fs))
(local R (require :reference-lifecycle/record-utils))

(fn contains? [keys key]
  (var found false)
  (each [_ value (ipairs keys)] (when (= value key) (set found true)))
  found)
(fn preflight! [self]
  (assert (= self.store.base-dir self.base-dir) "workflows owner base-dir mismatch")
  (each [_ method (ipairs ["snapshot-definition" "serialize-definition" "decode-definition" "persist-definition!" "prepare-step-removal" "reconcile-definition!"])]
    (assert (= (type (. self.store method)) :function) (.. "missing workflow capability: " method)))
  true)
(fn inventory [self]
  (preflight! self)
  (local records {})
  (local sites [])
  (each [_ entry (ipairs (R.record-entries self.store.definitions-dir ".json"))]
    (local id (string.sub entry.name 1 -6))
    (local snapshot (self.store:snapshot-definition id))
    (assert snapshot.value (.. "workflow disappeared: " entry.path))
    (local address (.. "workflow:" id))
    (local record {:address address :value snapshot.value :snapshot snapshot})
    (tset records address record)
    (each [index step (ipairs snapshot.value.steps)]
      (local key (.. "workflow-step:" id ":" step.id))
      ;; Step keys name supported targets, but the definition is the only writer.
      (tset records key record)
      (table.insert sites {:address address :field ["steps" index "code-entity-id"]
                           :target-key (.. "code-entity:" step.code-entity-id) :kind "workflow-code"})))
  {:records records :sites sites})
(fn removed-steps [definition operation]
  (assert (= (type definition.steps) :table) "workflow requires steps")
  (local ids [])
  (when (= operation.kind "delete")
    (each [_ step (ipairs definition.steps)]
      (when (or (contains? operation.retiring (.. "code-entity:" step.code-entity-id))
                (contains? operation.retiring (.. "workflow-step:" definition.id ":" step.id)))
        (table.insert ids step.id))))
  ids)
(fn definitions [inventory]
  (local addresses [])
  (each [key record (pairs inventory.records)]
    (when (= key record.address) (table.insert addresses key)))
  (table.sort addresses)
  addresses)
(fn expand [_self inventory operation]
  (local keys [])
  (each [_ address (ipairs (definitions inventory))]
    (local value (. inventory.records address :value))
    (each [_ id (ipairs (removed-steps value operation))]
      (table.insert keys (.. "workflow-step:" value.id ":" id))))
  keys)
(fn prepare [self inventory operation]
  (assert (contains? ["delete" "morph" "migrate"] operation.kind) "unsupported lifecycle operation")
  (local changes [])
  (each [_ address (ipairs (definitions inventory))]
    (local record (. inventory.records address))
    (local ids (removed-steps record.value operation))
    (when (> (# ids) 0)
      (local candidate (self.store:prepare-step-removal record.value ids {:delete-dependent-edges? true}))
      (set candidate.updated-at operation.timestamp)
      (table.insert changes (R.make-change self.id address record.snapshot
                                          (self.store:serialize-definition candidate) "json" "incoming"))))
  {:changes changes :runtime-state []})
(fn apply! [self change]
  (assert (= change.owner self.id) "wrong change owner")
  (local id (string.match change.address "^workflow:(.+)$"))
  (assert id "unsupported workflow address")
  (local snapshot (self.store:snapshot-definition id))
  (assert (= snapshot.path change.path) "workflow change path mismatch")
  (assert (not (= change.after-bytes false)) "workflow owner cannot retire definitions")
  (self.store:persist-definition! id change.after-bytes change.after-check)
  nil)
(fn reconcile! [self intent]
  (each [_ change (ipairs intent.changes)]
    (assert (= change.owner self.id) "wrong reconciliation owner")
    (local id (assert (string.match change.address "^workflow:(.+)$") "unsupported workflow address"))
    (assert (= (. (self.store:snapshot-definition id) :path) change.path) "workflow reconciliation path mismatch")
    (self.store:reconcile-definition! id change.after-bytes change.before-check change.after-check))
  nil)
(fn WorkflowsOwner [stores]
  (local base-dir (fs.absolute stores.base-dir))
  (assert (= base-dir stores.base-dir) "workflows owner requires canonical base-dir")
  (local self {:id "workflows" :base-dir base-dir :store (assert stores.workflow-store "missing workflow-store")
              :preflight! preflight! :inventory inventory :expand expand :prepare prepare
              :apply! apply! :reconcile! reconcile!})
  (preflight! self)
  self)
WorkflowsOwner
