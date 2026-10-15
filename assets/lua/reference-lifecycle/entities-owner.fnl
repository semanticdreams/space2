(local fs (require :fs))
(local R (require :reference-lifecycle/record-utils))
(local J (require :json-utils))

;; Fixed internal owning domains, not an extensible CRUD registry.
(local domains [["string-entity" "string-store" ".md"] ["code-entity" "code-store" ".json"]
               ["list-entity" "list-store" ".json"] ["dict-entity" "dict-store" ".json"]
               ["link-entity" "link-store" ".json"] ["notebook" "notebook-store" ".json"]])

(fn contains? [items key]
  (var found false)
  (each [_ item (ipairs items)] (when (= item key) (set found true)))
  found)
(fn domain-for [address]
  (local scheme (string.match address "^([^:]+):"))
  (var found nil)
  (each [_ domain (ipairs domains)] (when (= (. domain 1) scheme) (set found domain)))
  (assert found (.. "unsupported entity address: " address)))
(fn store-snapshot [store scheme id]
  (if (= scheme "notebook") (store:snapshot-notebook id) (store:snapshot-entity id)))
(fn store-bytes [store scheme value]
  (if (= scheme "notebook") (store:serialize-notebook value) (store:serialize-entity value)))

(fn preflight! [self]
  (each [_ domain (ipairs domains)]
    (local store (assert (. self.stores (. domain 2)) "missing canonical owning store"))
    (assert (= store.base-dir self.base-dir) "entities owner base-dir mismatch")
    (local notebook? (= (. domain 1) "notebook"))
     (each [_ method (ipairs (if notebook? ["snapshot-notebook" "serialize-notebook" "decode-notebook" "persist-notebook!" "delete-notebook" "reconcile-notebook!"]
                                 ["snapshot-entity" "serialize-entity" "decode-entity" "persist-entity!" "delete-entity" "reconcile-entity!"]))]
      (assert (= (type (. store method)) :function) (.. "missing store capability: " method)))
    (when (contains? ["list-entity" "dict-entity" "link-entity" "notebook"] (. domain 1))
      (assert (= store.identity-store self.stores.identity-store) "entities owner identity-store mismatch")))
  true)

(fn add-site! [sites address field target kind]
  (assert (= (type target) :string) (.. "reference must be a string at " address))
  (when (not (= target ""))
    (table.insert sites {:address address :field field :target-key target :kind kind})))
(fn record-sites! [sites scheme address value]
  (assert (= (type value) :table) "entity inventory requires owning record")
  (if (or (= scheme "list-entity") (= scheme "notebook"))
      (each [index key (ipairs value.items)]
        (add-site! sites address ["items" index] key (if (= scheme "notebook") "notebook-item" "list-item")))
      (= scheme "dict-entity")
      (do
        (local keys (icollect [key _ (pairs value.items)] key))
        (table.sort keys)
        (each [_ key (ipairs keys)] (add-site! sites address ["items" key] (. value.items key) "dict-slot")))
      (= scheme "link-entity")
      (do (add-site! sites address ["source-key"] value.source-key "link-source")
          (add-site! sites address ["target-key"] value.target-key "link-target"))))
(fn inventory [self]
  (preflight! self)
  (local records {})
  (local sites [])
  (each [_ domain (ipairs domains)]
    (local (scheme field extension) (table.unpack domain))
    (local store (. self.stores field))
    (local directory (if (= scheme "notebook") store.notebooks-dir store.entities-dir))
    (each [_ entry (ipairs (R.record-entries directory extension))]
      (local id (string.sub entry.name 1 (- (- (# extension)) 1)))
      (local snapshot (store-snapshot store scheme id))
      (assert snapshot.value (.. "record disappeared: " entry.path))
      (local address (.. scheme ":" id))
      (tset records address {:address address :value snapshot.value :snapshot snapshot})
      (record-sites! sites scheme address snapshot.value)))
  {:records records :sites sites})
(fn expand [_self inventory operation]
  (assert (= (type operation.retiring) :table) "operation requires retiring keys")
  (local keys [])
  (when (= operation.kind "delete")
    (each [_ site (ipairs inventory.sites)]
      (when (and (or (= site.kind "link-source") (= site.kind "link-target"))
                 (contains? operation.retiring site.target-key)
                 (not (contains? keys site.address)))
        (table.insert keys site.address))))
  (table.sort keys)
  keys)

(fn rewrite [operation key]
  (var result key)
  (each [_ mapping (ipairs operation.reference-plan.rewrites)]
    (when (= mapping.from-key key) (set result mapping.to-key)))
  result)
(fn transformed-items [items operation ordered?]
  (assert (= (type items) :table) "container items must be a table")
  (local out {})
  (local seen {})
  (each [slot key (pairs items)]
    (when (or (not (= operation.kind "delete")) (not (contains? operation.retiring key)))
      (when (not ordered?) (tset out slot (rewrite operation key)))))
  (when ordered?
    (each [_ key (ipairs items)]
      (local next-key (rewrite operation key))
      (local unique? (and (not (= operation.kind "delete")) (= (string.sub next-key 1 9) "identity:")))
      (when (and (or (not (= operation.kind "delete")) (not (contains? operation.retiring key)))
                 (not (and unique? (. seen next-key))))
        (tset seen next-key true)
        (table.insert out next-key))))
  out)
(fn changed-value [scheme value operation]
  (assert (= (type value) :table) "entity transformation requires owning record")
  (local candidate (R.clone value))
  (if (or (= scheme "list-entity") (= scheme "notebook") (= scheme "dict-entity"))
      (set candidate.items (transformed-items candidate.items operation (not (= scheme "dict-entity"))))
      (= scheme "link-entity")
      (do (set candidate.source-key (rewrite operation candidate.source-key))
          (set candidate.target-key (rewrite operation candidate.target-key))))
  candidate)
(fn prepare-record [self record operation]
  (local domain (domain-for record.address))
  (local scheme (. domain 1))
  (local format (if (= scheme "string-entity") "string" "json"))
  (local store (. self.stores (. domain 2)))
  (if (contains? operation.retiring record.address)
      (R.make-change self.id record.address record.snapshot false format "retire")
      (do
        (local candidate (changed-value scheme record.value operation))
        (when (not (= (J.stable-json candidate) (J.stable-json record.value)))
          (when candidate.updated-at (set candidate.updated-at operation.timestamp))
          (R.make-change self.id record.address record.snapshot (store-bytes store scheme candidate) format "incoming")))))
(fn prepare [self inventory operation]
  (assert (contains? ["delete" "morph" "migrate"] operation.kind) "unsupported lifecycle operation")
  (local changes [])
  (local addresses (icollect [key _ (pairs inventory.records)] key))
  (table.sort addresses)
  (each [_ address (ipairs addresses)]
    (local change (prepare-record self (. inventory.records address) operation))
    (when change (table.insert changes change)))
  (when (and (= operation.kind "morph") operation.replacement)
    (local domain (domain-for operation.target-key))
    (local store (. self.stores (. domain 2)))
    (local id (string.match operation.target-key "^[^:]+:(.+)$"))
    (assert (= operation.replacement.id id) "morph replacement id mismatch")
    (local snapshot (store-snapshot store (. domain 1) id))
    (assert (= snapshot.bytes false) "morph replacement already exists")
    (table.insert changes (R.make-change self.id operation.target-key snapshot
                                        (store-bytes store (. domain 1) operation.replacement) "json" "replacement")))
  {:changes changes :runtime-state []})
(fn apply! [self change]
  (assert (= change.owner self.id) "wrong change owner")
  (local domain (domain-for change.address))
  (local store (. self.stores (. domain 2)))
  (local id (string.match change.address "^[^:]+:(.+)$"))
  (local snapshot (store-snapshot store (. domain 1) id))
  (assert (= change.path snapshot.path) "entity change path mismatch")
  (if (= change.after-bytes false)
      (if (= (. domain 1) "notebook") (store:delete-notebook id) (store:delete-entity id))
      (= (. domain 1) "notebook") (store:persist-notebook! id change.after-bytes change.after-check)
      (store:persist-entity! id change.after-bytes change.after-check))
  nil)
(fn reconcile! [self intent]
  (each [_ change (ipairs intent.changes)]
    (assert (= change.owner self.id) "wrong reconciliation owner")
    (local domain (domain-for change.address))
    (local store (. self.stores (. domain 2)))
    (local id (string.match change.address "^[^:]+:(.+)$"))
    (local snapshot (store-snapshot store (. domain 1) id))
    (assert (= change.path snapshot.path) "entity reconciliation path mismatch")
    (if (= (. domain 1) "notebook")
        (store:reconcile-notebook! id change.after-bytes change.before-check change.after-check)
        (store:reconcile-entity! id change.after-bytes change.before-check change.after-check)))
  nil)
(fn EntitiesOwner [stores]
  (local base-dir (fs.absolute stores.base-dir))
  (assert (= base-dir stores.base-dir) "entities owner requires canonical base-dir")
  (local self {:id "entities" :base-dir base-dir :stores stores
              :preflight! preflight! :inventory inventory :expand expand :prepare prepare
              :apply! apply! :reconcile! reconcile!})
  (preflight! self)
  self)
EntitiesOwner
