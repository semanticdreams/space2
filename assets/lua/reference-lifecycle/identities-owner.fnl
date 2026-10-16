(local fs (require :fs))
(local R (require :reference-lifecycle/record-utils))

(fn contains? [keys key]
  (var found false)
  (each [_ value (ipairs keys)] (when (= value key) (set found true)))
  found)
(fn preflight! [self]
  (assert (= self.store.base-dir self.base-dir) "identities owner base-dir mismatch")
  (each [_ method (ipairs ["snapshot-entity" "serialize-entity" "decode-entity" "persist-entity!" "retire-entity!" "reconcile-entity!"])]
    (assert (= (type (. self.store method)) :function) (.. "missing identity capability: " method)))
  true)
(fn inventory [self]
  (preflight! self)
  (local records {})
  (local sites [])
  (each [_ entry (ipairs (R.record-entries self.store.entities-dir ".json"))]
    (local id (string.sub entry.name 1 -6))
    (local snapshot (self.store:snapshot-entity id))
    (assert snapshot.value (.. "identity record disappeared: " entry.path))
    (local address (.. "identity:" id))
    (tset records address {:address address :value snapshot.value :snapshot snapshot})
    (local target snapshot.value.target-key)
    (assert (= (type target) :string) (.. "invalid identity target at " entry.path))
    (when (not (= target ""))
      (table.insert sites {:address address :field ["target-key"] :target-key target :kind "identity-target"})))
  {:records records :sites sites})
(fn expand [_self inventory operation]
  (local keys [])
  (when (= operation.kind "delete")
    (each [_ site (ipairs inventory.sites)]
      (when (contains? operation.retiring site.target-key) (table.insert keys site.address))))
  (table.sort keys)
  keys)
(fn existing-change [self record operation]
  (if (contains? operation.retiring record.address)
      (R.make-change self.id record.address record.snapshot false "json" "retire")
      (and (= operation.kind "morph") (= record.value.target-key operation.source-key))
      (do
        (local candidate (R.clone record.value))
        (set candidate.target-key operation.target-key)
        (set candidate.updated-at operation.timestamp)
        (R.make-change self.id record.address record.snapshot (self.store:serialize-entity candidate) "json" "incoming"))))
(fn prepare [self inventory operation]
  (assert (contains? ["delete" "morph" "migrate"] operation.kind) "unsupported lifecycle operation")
  (local changes [])
  (local addresses (icollect [key _ (pairs inventory.records)] key))
  (table.sort addresses)
  (each [_ address (ipairs addresses)]
    (local change (existing-change self (. inventory.records address) operation))
    (when change (table.insert changes change)))
  (local reserved {})
  (each [_ candidate (ipairs operation.reference-plan.identities)]
    (R.require-id candidate.id)
    (assert (not (. reserved candidate.id)) "duplicate reserved identity id")
    (tset reserved candidate.id true)
    (local snapshot (self.store:snapshot-entity candidate.id))
    (assert (= snapshot.bytes false) "reserved identity already exists")
    (when (and (= operation.kind "morph") (= candidate.target-key operation.source-key))
      (error "reserved morph identity points to retiring representation"))
    (table.insert changes (R.make-change self.id (.. "identity:" candidate.id) snapshot
                                        (self.store:serialize-entity candidate) "json" "replacement")))
  {:changes changes :runtime-state []})
(fn apply! [self change]
  (assert (= change.owner self.id) "wrong change owner")
  (local id (string.match change.address "^identity:(.+)$"))
  (assert id "unsupported identity address")
  (local snapshot (self.store:snapshot-entity id))
  (assert (= snapshot.path change.path) "identity change path mismatch")
  (if (= change.after-bytes false) (self.store:retire-entity! id)
      (self.store:persist-entity! id change.after-bytes change.after-check))
  nil)
(fn reconcile! [self intent]
  (each [_ change (ipairs intent.changes)]
    (assert (= change.owner self.id) "wrong reconciliation owner")
    (local id (assert (string.match change.address "^identity:(.+)$") "unsupported identity address"))
    (assert (= (. (self.store:snapshot-entity id) :path) change.path) "identity reconciliation path mismatch")
    (self.store:reconcile-entity! id change.after-bytes change.before-check change.after-check))
  nil)
(fn IdentitiesOwner [stores]
  (local base-dir (fs.absolute stores.base-dir))
  (assert (= base-dir stores.base-dir) "identities owner requires canonical base-dir")
  (local self {:id "identities" :base-dir base-dir :store (assert stores.identity-store "missing identity-store")
              :preflight! preflight! :inventory inventory :expand expand :prepare prepare
              :apply! apply! :reconcile! reconcile!})
  (preflight! self)
  self)
IdentitiesOwner
