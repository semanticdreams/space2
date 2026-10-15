(local Uuid (require :uuid))
(local J (require :json-utils))
(local R (require :reference-lifecycle/record-utils))

;; Fixed coordination protocol, not a type registry or a persistence dispatcher.
(local owner-ids ["entities" "identities" "workflows" "worlds" "runtime"])
(local fields {:string-entity "string-store" :code-entity "code-store" :list-entity "list-store"
               :dict-entity "dict-store" :link-entity "link-store" :identity "identity-store"
               :notebook "notebook-store" :workflow-step "workflow-store"})
(local holders {:list-entity true :dict-entity true :link-entity true :notebook true})
(local eligible {:list-item true :notebook-item true :dict-slot true :link-source true :link-target true :board-subject true})
(fn sorted-keys [items]
  (local keys (icollect [key _ (pairs items)] key)) (table.sort keys) keys)
(fn owns-store? [stores scheme store]
  (local field (. fields scheme))
  (if (and field (= store (. stores field)) (= (type store) :table) (= (type store.base-dir) :string)
           (= (R.comparison-path store.base-dir) (R.comparison-path stores.base-dir))
           (if (. holders scheme)
               (and (= store.identity-store stores.identity-store)
                    (= (R.comparison-path stores.identity-store.base-dir) (R.comparison-path stores.base-dir)))
               true)) true false))
(fn validate-owners [owners stores]
  (R.require-array owners)
  (local indexed {})
  (each [_ owner (ipairs owners)]
    (assert (and (= (type owner) :table) (not (. indexed owner.id))) "invalid or duplicate owner")
    (tset indexed owner.id owner))
  (assert (= (# owners) 5) "lifecycle requires all five fixed owners")
  (each [_ id (ipairs owner-ids)]
    (local owner (assert (. indexed id) (.. "missing lifecycle owner: " id)))
    (assert (= (R.comparison-path owner.base-dir) (R.comparison-path stores.base-dir)) "owner root mismatch")
    (each [_ method (ipairs ["preflight!" "inventory" "expand" "prepare" "apply!" "reconcile!"])]
      (assert (= (type (. owner method)) :function) (.. "missing owner capability: " method)))
    (assert (owner:preflight!) (.. "owner preflight failed: " id)))
  (each [scheme field (pairs fields)]
    (assert (owns-store? stores scheme (. stores field)) (.. "canonical store root/identity mismatch: " field)))
  (assert (= indexed.entities.stores stores) "entities owner canonical stores mismatch")
  (assert (= indexed.identities.store stores.identity-store) "identities owner canonical store mismatch")
  (assert (= indexed.workflows.store stores.workflow-store) "workflows owner canonical store mismatch")
  indexed)
(fn inventories [owners stores]
  (local indexed (validate-owners owners stores))
  (local entries [])
  (local records {})
  (each [_ id (ipairs owner-ids)]
    (local owner (. indexed id))
    (local inventory (owner:inventory))
    (assert (and inventory.records inventory.sites) "owner requires Inventory")
    (table.insert entries {:owner owner :inventory inventory})
    (each [key record (pairs inventory.records)]
      (assert (not (. records key)) (.. "duplicate inventory key: " key))
      (tset records key record)))
  (values entries records))
(fn target [key]
  (assert (= (type key) :string) "unsupported lifecycle target")
  (local (scheme id) (string.match key "^([^:]+):(.+)$"))
  (assert (. fields scheme) (.. "unsupported lifecycle target: " key))
  (if (= scheme "workflow-step")
      (do
        (local (definition step) (string.match id "^([^:]+):([^:]+)$"))
        (assert (and definition step) (.. "unsupported workflow-step target: " key))
        (R.require-id definition) (R.require-id step))
      (R.require-id id))
  (values scheme id))
(fn resolve [records key]
  (var current key)
  (local visited {})
  (var depth 0)
  (while (= (string.sub current 1 9) "identity:")
    (assert (not (. visited current)) (.. "identity cycle: " current))
    (tset visited current true)
    (local record (. records current))
    (when (or (not record) (= record.value.target-key "")) (lua "return current"))
    (assert (< depth 32) (.. "identity depth exhausted: " current))
    (set current record.value.target-key)
    (set depth (+ depth 1)))
  current)
(fn validate-references! [entries records]
  (each [key _ (pairs records)] (when (= (string.sub key 1 9) "identity:") (resolve records key)))
  (each [_ entry (ipairs entries)]
    (each [_ site (ipairs entry.inventory.sites)]
      (local terminal (resolve records site.target-key))
      (local scheme (string.match terminal "^([^:]+):"))
      (when (. fields scheme) (target terminal)))))
(fn closure! [entries operation]
  (local visited {})
  (tset visited operation.source-key true)
  (var grew? true)
  (while grew?
    (set grew? false)
    (set operation.retiring (sorted-keys visited))
    (each [_ entry (ipairs entries)]
      (each [_ key (ipairs (entry.owner:expand entry.inventory operation))]
        (target key)
        (when (not (. visited key)) (tset visited key true) (set grew? true)))))
  (set operation.retiring (sorted-keys visited)))
(fn validate-payload [payload source]
  (assert (= (type payload) :table) "morph requires payload")
  (assert (and (= (type payload.name) :string) (= payload.language "fnl")
               (= (type payload.source) :string)
               (or (= (type payload.kernel) :number) (= (type payload.kernel) :string))) "unsupported morph payload")
  (assert (= payload.source source.value) "morph source payload does not match current source")
  (each [key _ (pairs payload)]
    (assert (or (= key "name") (= key "language") (= key "source") (= key "kernel")) "unsupported morph payload field")))
(fn morph-operation! [entries records operation payload]
  (validate-payload payload (. records operation.source-key :value))
  (local id (Uuid.v4))
  (set operation.target-key (.. "code-entity:" id))
  (assert (not (. records operation.target-key)) "replacement id collision")
  (set operation.replacement (R.clone payload))
  (set operation.replacement.id id)
  (set operation.replacement.created-at operation.timestamp)
  (set operation.replacement.updated-at operation.timestamp)
  (local direct {})
  (each [_ key (ipairs (sorted-keys records))]
    (when (= (string.sub key 1 9) "identity:")
      (local target-key (. records key :value :target-key))
      (when (not (. direct target-key)) (tset direct target-key key))
      (when (= target-key operation.source-key) (table.insert operation.updated-identity-keys key))))
  (local raw {})
  (local reserved {})
  (each [_ entry (ipairs entries)]
    (each [_ site (ipairs entry.inventory.sites)]
      (local key site.target-key)
      (local scheme (string.match key "^([^:]+):"))
      (when (and (. eligible site.kind) (not (= key "")) (not (= scheme "identity"))
                 (or (not (. fields scheme)) (. records key))) (tset raw key true))))
  (each [_ key (ipairs (sorted-keys raw))]
    (var stable (. direct key))
    (when (not stable)
      (local identity-id (Uuid.v4))
      (set stable (.. "identity:" identity-id))
      (assert (and (not (. records stable)) (not (. reserved stable))) "reserved identity collision")
      (tset reserved stable true)
      (table.insert operation.reference-plan.identities
        {:id identity-id :target-key (if (= key operation.source-key) operation.target-key key)
         :created-at operation.timestamp :updated-at operation.timestamp :metadata {}}))
    (table.insert operation.reference-plan.rewrites {:from-key key :to-key stable}))
  (table.sort operation.reference-plan.identities (fn by-id [a b] (< a.id b.id))))
(fn source-fingerprint [key record]
  (var source record.value)
  (when (= (string.sub key 1 14) "workflow-step:")
    (local step-id (string.match key "^workflow%-step:[^:]+:(.+)$"))
    (set source nil)
    (each [_ step (ipairs record.value.steps)] (when (= step.id step-id) (set source step)))
    (assert source "source step missing from inventory"))
  {:path record.snapshot.path :format (if (= (string.sub key 1 14) "string-entity:") "string" "json")
   :before-check record.snapshot.check :record (R.clone source)})
(fn capture! [out captures owner capture]
  (assert (= capture.owner owner.id) "runtime capture owner namespace mismatch")
  (assert (= owner.id "runtime") "only runtime owner may capture transient state")
  (R.require-id capture.world-id)
  (when (not (= capture.map-id false)) (R.require-id capture.map-id))
  ;; Check individually: ipairs would silently stop at a missing before/after.
  (assert (and (= (type capture.before) :table) (= (type capture.after) :table))
          "runtime capture requires before/after state")
  (local namespace (J.stable-json [owner.id capture.world-id capture.map-id]))
  (assert (not (. captures namespace)) "duplicate runtime capture")
  (tset captures namespace true)
  (each [_ state (ipairs [capture.before capture.after])]
    (each [key _ (pairs state)]
      (assert (or (= key "board") (= key "maps") (= key "views") (= key "metadata")) "unsupported runtime capture schema")))
  (each [_ role (ipairs ["board" "maps" "views" "metadata"])]
    (assert (= (= (. capture.before role) nil) (= (. capture.after role) nil))
            "runtime capture role presence mismatch"))
  (table.insert out.runtime-state (R.clone capture)))
(fn append! [out paths captures owner preparation]
  (R.require-array preparation.changes) (R.require-array preparation.runtime-state)
  (each [_ change (ipairs preparation.changes)]
    (assert (= change.owner owner.id) "change owner namespace mismatch")
    (assert (not (= owner.id "runtime")) "runtime owner cannot produce durable changes")
    (local path (R.comparison-path change.path))
    (assert (not (. paths path)) (.. "duplicate durable path: " path))
    (tset paths path true)
    (assert (= (R.check-bytes change.after-bytes change.format) change.after-check) "invalid frozen after-check")
    (assert (or (= change.before-check false) (= (type change.before-check) :string)) "invalid before-check")
    (assert (or (= change.phase "replacement") (= change.phase "incoming") (= change.phase "retire")) "invalid change phase")
    (table.insert out.changes (R.clone change)))
  (each [_ capture (ipairs preparation.runtime-state)] (capture! out captures owner capture)))
(fn intent [request operation fingerprint]
  {:version 1 :operation-id (Uuid.v4) :request (R.clone request) :operation (R.clone operation)
   :source-fingerprint fingerprint :changes [] :runtime-state [] :phase "prepared"})
(fn aggregate! [out entries]
  (local paths {}) (local captures {})
  (each [_ entry (ipairs entries)]
    (append! out paths captures entry.owner (entry.owner:prepare entry.inventory out.operation)))
  ;; A native JSON round-trip rejects adapter/functions/nonserializable captures.
  (R.decode-json (J.stable-json out))
  out)
(fn prepare [owners stores request]
  (assert (or (= request.kind "delete") (= request.kind "morph")) "unsupported lifecycle request")
  (local (scheme _) (target request.source-key))
  (when (= request.kind "morph") (assert (= scheme "string-entity") "unsupported morph source"))
  (local (entries records) (inventories owners stores))
  (validate-references! entries records)
  (local source (. records request.source-key))
  (when (not source)
    (assert (= request.kind "delete") "morph source absent")
    (lua "return {status='absent', ['source-key']=request['source-key'], ['source-record']=false, ['retired-keys']={}}"))
  (local operation {:kind request.kind :source-key request.source-key :target-key false
                    :retiring [request.source-key] :updated-identity-keys [] :replacement false
                    :reference-plan {:rewrites [] :identities []} :timestamp (os.time)})
  (if (= request.kind "delete") (closure! entries operation)
      (morph-operation! entries records operation request.payload))
  (aggregate! (intent request operation (source-fingerprint request.source-key source)) entries))

{:prepare prepare :validate-owners validate-owners :owns-store? owns-store?
 :append! append! :intent intent :target target}
