(local fs (require :fs))
(local Signal (require :signal))
(local J (require :json-utils))
(local R (require :reference-lifecycle/record-utils))
(local Plan (require :reference-lifecycle/plan))
(local Pending (require :reference-lifecycle/pending))
(local Migration (require :reference-lifecycle/migration))

;; The journal's path is diagnostic data, never an independent IO capability.
;; Re-derive each address through its canonical owner on every replay.
(local entity-fields {:string-entity "string-store" :code-entity "code-store" :list-entity "list-store"
                      :dict-entity "dict-store" :link-entity "link-store" :identity "identity-store"})
(fn owning-snapshot [self change worlds]
  (local (scheme id) (string.match change.address "^([^:]+):(.+)$"))
  (local field (. entity-fields scheme))
  (if field
      (do
        (assert (= change.owner (if (= scheme "identity") "identities" "entities")) "change owner/address mismatch")
        (assert (= change.format (if (= scheme "string-entity") "string" "json")) "change format mismatch")
        ((. (. self.stores field) :snapshot-entity) (. self.stores field) id))
      (= scheme "notebook")
      (do (assert (= change.owner "entities") "change owner/address mismatch")
          (assert (= change.format "json") "change format mismatch")
          (self.stores.notebook-store:snapshot-notebook id))
      (= scheme "workflow")
      (do (assert (= change.owner "workflows") "change owner/address mismatch")
          (assert (= change.format "json") "change format mismatch")
          (self.stores.workflow-store:snapshot-definition id))
      (do
        (assert (= change.owner "worlds") "unsupported durable change owner/address")
        (assert (= change.format "json") "world change format mismatch")
        (local record (assert (. worlds.records change.address) "world change address missing from owner inventory"))
        ;; World inventory supplies its schema-owned, confined snapshot location.
        (local path record.snapshot.path)
        (R.snapshot path "json" R.decode-json))))
(fn verified-snapshot [self change worlds]
  (local snapshot (owning-snapshot self change worlds))
  (assert (= snapshot.path change.path) (.. "change path mismatch: " change.address))
  snapshot)
(fn assert-state [change snapshot]
  (assert (or (= snapshot.check change.before-check) (= snapshot.check change.after-check))
          (.. "pending conflict at " change.address " (" change.path ")")))
(fn validate-change! [self change worlds paths]
  (assert (. self._owners change.owner) "unknown pending change owner")
  (assert (or (= change.phase "replacement") (= change.phase "incoming") (= change.phase "retire")) "invalid change phase")
  (assert (= (R.check-bytes change.after-bytes change.format) change.after-check) "frozen after-check mismatch")
  (assert (= (R.check-bytes change.before-check change.format) change.before-check) "noncanonical before-check")
  (local snapshot (verified-snapshot self change worlds))
  (local path (R.comparison-path snapshot.path))
  (assert (not (. paths path)) (.. "duplicate durable path: " path))
  (tset paths path true)
  (assert-state change snapshot))
(fn source-address [key]
  (local (scheme id) (Plan.target key))
  (if (= scheme "workflow-step") (.. "workflow:" (string.match id "^([^:]+):")) key))
(fn decoded-source [self key bytes]
  (local (scheme id) (Plan.target key))
  (local field (. entity-fields scheme))
  (if field ((. (. self.stores field) :decode-entity) (. self.stores field) bytes)
      (= scheme "notebook") (self.stores.notebook-store:decode-notebook bytes)
      (do
        (local definition (self.stores.workflow-store:decode-definition bytes))
        (local step-id (string.match id "^[^:]+:(.+)$"))
        (var source nil)
        (each [_ step (ipairs definition.steps)] (when (= step.id step-id) (set source step)))
        (assert source "pending source step absent from before-image"))))
(fn workflow-source? [intent change]
  (and (= (type intent.operation.source-key) :string)
       (= (string.sub intent.operation.source-key 1 14) "workflow-step:")
       (= change.address (source-address intent.operation.source-key))))
(fn requested-change [intent]
  (local address (source-address intent.request.source-key))
  (var source nil)
  (each [_ change (ipairs intent.changes)] (when (= change.address address) (set source change)))
  (assert source "pending source change missing"))
(fn assert-source-after! [self key bytes check]
  (local (scheme id) (Plan.target key))
  (if (= scheme "workflow-step")
      (do
        (assert (and (not (= bytes false)) (not (= check false))) "pending source definition must survive step deletion")
        ;; The owning pure decoder also rejects incident edges to absent steps.
        (local definition (self.stores.workflow-store:decode-definition bytes))
        (local (definition-id step-id) (string.match id "^([^:]+):([^:]+)$"))
        (assert (= definition.id definition-id) "pending source definition id mismatch")
        (each [_ step (ipairs definition.steps)]
          (assert (not (= step.id step-id)) "pending source step remains in after-image")))
      (assert (and (= bytes false) (= check false)) "pending source retirement requires absence")))
(fn validate-retirement! [intent change]
  (when (= change.phase "retire")
    (assert (or (and (= change.after-bytes false) (= change.after-check false))
                (workflow-source? intent change)) "pending retire change requires absence")))
(fn validate-source! [self intent]
  (local fingerprint intent.source-fingerprint)
  (if (= intent.operation.kind "migrate")
      (assert (= fingerprint false) "migration must not carry source fingerprint")
      (do
        (assert (= intent.operation.source-key intent.request.source-key) "pending source mismatch")
        (local source (requested-change intent))
        (assert (if (workflow-source? intent source)
                    (and (= intent.operation.kind "delete") (not (= source.phase "replacement")))
                    (= source.phase "retire")) "pending source change phase mismatch")
        (assert (and (= fingerprint.path source.path) (= fingerprint.format source.format)
                     (= fingerprint.before-check source.before-check)) "pending source fingerprint mismatch")
        (local record (decoded-source self intent.request.source-key source.before-check))
        (assert (= (J.stable-json record) (J.stable-json fingerprint.record)) "pending source record mismatch")
        (assert-source-after! self intent.request.source-key source.after-bytes source.after-check))))
(fn validate-preparations! [self intent]
  (local out {:changes [] :runtime-state []})
  (local paths {}) (local captures {})
  (each [_ owner (ipairs self.owners)]
    (local changes (icollect [_ change (ipairs intent.changes)] (when (= change.owner owner.id) change)))
    (local runtime-state (icollect [_ capture (ipairs intent.runtime-state)] (when (= capture.owner owner.id) capture)))
    (Plan.append! out paths captures owner {:changes changes :runtime-state runtime-state}))
  (assert (= (# out.runtime-state) (# intent.runtime-state)) "unknown runtime capture owner namespace")
  (R.decode-json (J.stable-json out)))
(fn validate-intent! [self intent]
  (assert (= intent.version 1) "unsupported pending intent version")
  (assert (= (type intent.operation-id) :string) "pending operation requires id")
  (assert (= intent.request.kind intent.operation.kind) "pending request/operation mismatch")
  (assert (or (= intent.operation.kind "migrate") (= intent.operation.kind "delete") (= intent.operation.kind "morph")) "unsupported pending operation")
  (R.require-array intent.changes) (R.require-array intent.runtime-state)
  (R.require-array intent.operation.reference-plan.rewrites)
  (R.require-array intent.operation.reference-plan.identities)
  (validate-preparations! self intent)
  (local worlds (self._owners.worlds:inventory))
  (local paths {})
  (validate-source! self intent)
  (each [_ change (ipairs intent.changes)]
    (validate-retirement! intent change)
    (validate-change! self change worlds paths))
  worlds)
(fn subset [intent changes]
  (local out (R.clone intent)) (set out.changes changes) out)
(fn apply-change! [self intent change worlds]
  (local snapshot (verified-snapshot self change worlds))
  (assert-state change snapshot)
  (local owner (. self._owners change.owner))
  (if (= snapshot.check change.after-check)
      (owner:reconcile! (subset intent [change]))
      (owner:apply! change))
  (assert (= (. (verified-snapshot self change worlds) :check) change.after-check)
          (.. "owner did not persist frozen after-image: " change.address)))
(fn source-change? [intent change]
  (and (not (= intent.source-fingerprint false)) (= change.path intent.source-fingerprint.path)))
(fn changes-before? [a b]
  (local rank {:replacement 1 :incoming 2 :retire 3})
  (if (= (. rank a.phase) (. rank b.phase)) (< a.address b.address)
      (< (. rank a.phase) (. rank b.phase))))
(fn verify-after! [self intent worlds source?]
  (each [_ change (ipairs intent.changes)]
    (when (or source? (not (source-change? intent change)))
      (assert (= (. (verified-snapshot self change worlds) :check) change.after-check)
              (.. "pending conflict verifying after-image: " change.address)))))
(fn migration-path [self]
  (R.record-path self.stores.base-dir (fs.join-path self.stores.base-dir "reference-lifecycle") "migration" ".json"))
(fn migration-report [self]
  (local snapshot (R.snapshot (migration-path self) "json" R.decode-json))
  (when snapshot.value
    (assert (= snapshot.value.version Migration.version) "unsupported migration version")
    (R.require-array snapshot.value.dangling)
    snapshot.value))
(fn mark-migration! [self intent]
  (when (= intent.operation.kind "migrate")
    (local report {:version Migration.version :dangling intent.dangling})
    (local current (migration-report self))
    (when current (assert (= (J.stable-json current) (J.stable-json report)) "migration completion conflict"))
    (when (not current) (J.write-json! (migration-path self) report))))
(fn result-for [self intent]
  (local operation intent.operation)
  (if (= operation.kind "migrate") {:version Migration.version :dangling intent.dangling}
      (= operation.kind "delete")
      {:status "deleted" :source-key operation.source-key :source-record (R.clone intent.source-fingerprint.record)
       :retired-keys (R.clone operation.retiring)}
      (do
        (local id operation.replacement.id)
        {:code-entity (self.stores.code-store:get-entity id) :code-key operation.target-key
         :target-key operation.target-key :target-type "code-entity"
         :updated-identity-keys (R.clone operation.updated-identity-keys)
         :source-key operation.source-key :source-id intent.source-fingerprint.record.id})))
(fn replay! [self intent]
  (local worlds (validate-intent! self intent))
  (local ordered (R.clone intent.changes))
  (table.sort ordered changes-before?)
  (each [_ change (ipairs ordered)]
    (when (not (source-change? intent change)) (apply-change! self intent change worlds)))
  (verify-after! self intent worlds false)
  ;; Runtime reconciliation consumes only frozen captures, never inventories or IO.
  (self._owners.runtime:reconcile! (subset intent []))
  (verify-after! self intent worlds false)
  (each [_ change (ipairs ordered)]
    (when (source-change? intent change) (apply-change! self intent change worlds)))
  (verify-after! self intent worlds true)
  (when (not (= intent.operation.kind "migrate"))
    (local actual (verified-snapshot self (requested-change intent) worlds))
    (assert-source-after! self intent.request.source-key actual.bytes actual.check))
  (mark-migration! self intent)
  (local result (result-for self intent))
  (self.committed:emit result)
  (self._pending:clear!)
  result)
(fn protected! [self f]
  (assert (not self._state.busy?) "reference lifecycle busy")
  (set self._state.busy? true)
  (local (ok result) (pcall f))
  (set self._state.busy? false)
  (if ok result (error result)))
(fn migration-intent [self]
  (local prepared (Migration.prepare self.owners self.stores))
  (local intent (Plan.intent {:kind "migrate"} prepared.operation false))
  (local paths {}) (local captures {})
  ;; Revalidate/copy Task 3's aggregated frozen preparation without recapturing.
  (each [_ owner (ipairs self.owners)]
    (local changes (icollect [_ change (ipairs prepared.changes)] (when (= change.owner owner.id) change)))
    (local runtime-state (icollect [_ capture (ipairs prepared.runtime-state)] (when (= capture.owner owner.id) capture)))
    (Plan.append! intent paths captures owner {:changes changes :runtime-state runtime-state}))
  (set intent.dangling prepared.dangling)
  intent)
(fn start! [self]
  (fn start []
    (Plan.validate-owners self.owners self.stores)
    (local pending (self._pending:read))
    (when pending (replay! self pending))
    (when (not (migration-report self))
      (local intent (migration-intent self))
      (validate-intent! self intent)
      (self._pending:write! intent)
      (replay! self intent))
    (set self._state.ready? true)
    (migration-report self))
  (protected! self start))
(fn command! [self request]
  (assert self._state.ready? "reference lifecycle not ready")
  (fn execute []
    (Plan.validate-owners self.owners self.stores)
    (local pending (self._pending:read))
    (if pending
        (do
          (assert (= (J.stable-json pending.request) (J.stable-json request))
                  (.. "pending operation " pending.operation-id " for " (tostring pending.operation.source-key)))
          (replay! self pending))
        (do
          (local prepared (Plan.prepare self.owners self.stores request))
          (if prepared.status prepared
              (do
                (validate-intent! self prepared)
                (self._pending:write! prepared)
                (replay! self prepared))))))
  (protected! self execute))
(fn delete! [self key] (command! self {:kind "delete" :source-key key}))
(fn replace! [self key payload] (command! self {:kind "morph" :source-key key :payload payload}))
(fn owns-store? [self scheme store] (Plan.owns-store? self.stores scheme store))
(fn Lifecycle [options]
  (local stores (assert options.stores "lifecycle requires canonical stores"))
  (local owners (assert options.owners "lifecycle requires five owners"))
  (local indexed (Plan.validate-owners owners stores))
  {:stores stores :owners owners :_owners indexed :_pending (Pending stores.base-dir)
   :_state {:ready? false :busy? false} :committed (Signal)
   :start! start! :delete! delete! :replace! replace! :owns-store? owns-store?})
Lifecycle
