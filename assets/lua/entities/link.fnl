(local Signal (require :signal))
(local appdirs (require :appdirs))
(local fs (require :fs))
(local Uuid (require :uuid))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local IdentityStore (require :entities/identity))
(local R (require :reference-lifecycle/record-utils))

(fn copy-record [record] (collect [key value (pairs record)] key value))

(fn entity-path [store id]
  (R.record-path store.base-dir store.entities-dir id ".json"))

(fn decode-entity [_self bytes]
    (local data (R.decode-json bytes))
    (assert (= (type data) :table) "link record must be an object")
    {:id (R.require-id data.id) :source-key (R.field data :source-key :string "") :target-key (R.field data :target-key :string "")
     :created-at (R.field data :created-at :number 0) :metadata (R.field data :metadata :table {})})

(fn serialize-entity [_self entity]
  (json.dumps {:id (R.require-id entity.id) :source-key entity.source-key :target-key entity.target-key
               :created-at entity.created-at :metadata entity.metadata}))
(fn snapshot-entity [self id]
  (fn decode [bytes] (decode-entity self bytes))
  (local snapshot (R.snapshot (entity-path self id) "json" decode))
  (when snapshot.value (assert (= snapshot.value.id id) (.. "link record id mismatch at " snapshot.path)))
  snapshot)

(fn publish! [store candidate]
  (local held (. store.cache candidate.id))
  (if held
      (do (each [key value (pairs candidate)] (tset held key value)) held)
      (do (tset store.cache candidate.id candidate) candidate)))

(fn write-entity [store entity]
  (entity-path store entity.id)
  (fs.create-dirs store.entities-dir)
  (JsonUtils.write-json! (entity-path store entity.id)
                        {:id entity.id :source-key entity.source-key :target-key entity.target-key
                          :created-at entity.created-at :metadata entity.metadata}))

(fn persist-entity! [self id bytes check]
  (local candidate (decode-entity self bytes))
  (R.verify-candidate id candidate (serialize-entity self candidate) check "json")
  (local existed? (not (= (. (snapshot-entity self id) :bytes) false)))
  (write-entity self candidate)
  (local published (publish! self candidate))
  (local signal (if existed? self.link-entity-updated self.link-entity-created))
  (signal:emit published)
  published)

(fn load-entity [store id]
  (when id
    (local key (tostring id))
    (if (. store.cache key) (. store.cache key)
        (do
          (local candidate (. (snapshot-entity store key) :value))
          (when candidate (publish! store candidate))))))

(fn create-entity [self opts]
  (assert (or (= opts nil) (= (type opts) :table)) "link create requires options table")
  (local options (or opts {}))
  (local id (R.require-id (tostring (or options.id (Uuid.v4)))))
  (entity-path self id)
  (local entity {:id id
                 :source-key (self.identity-store:ensure-key (or options.source-key ""))
                 :target-key (self.identity-store:ensure-key (or options.target-key ""))
                 :created-at (or options.created-at (os.time)) :metadata (or options.metadata {})})
  (write-entity self entity)
  (local published (publish! self entity))
  (self.link-entity-created:emit published)
  published)

(fn update-entity [self id updates]
  (assert (or (= updates nil) (= (type updates) :table)) "link update requires options table")
  (assert (or (not updates) (not updates.id) (= updates.id id)) "update-entity cannot change id")
  (local entity (load-entity self id))
  (when entity
    (local candidate (copy-record entity))
    (each [key value (pairs (or updates {}))]
      (assert (or (not (= key :id)) (= value id)) "update-entity cannot change id")
      (local next-value (if (or (= key :source-key) (= key :target-key))
                            (self.identity-store:ensure-key value) value))
      (tset candidate key next-value))
    (write-entity self candidate)
    (publish! self candidate)
    (self.link-entity-updated:emit entity))
  entity)

(fn delete-entity [self id]
  (local entity (load-entity self id))
  (when entity
    (local path (entity-path self id))
    (when (fs.exists path) (fs.remove path))
    (tset self.cache (tostring id) nil)
    (self.link-entity-deleted:emit entity))
  entity)

(fn list-entities [self]
  (local candidates [])
  (each [_ entry (ipairs (R.record-entries self.entities-dir ".json"))]
    (when (and entry.is-file (string.match entry.name "%.json$"))
      (local candidate (. (snapshot-entity self (string.sub entry.name 1 -6)) :value))
      (assert candidate (.. "link record disappeared at " entry.path))
      (table.insert candidates candidate)))
  (local entities (icollect [_ candidate (ipairs candidates)] (publish! self candidate)))
  (fn newest-first? [a b] (> a.created-at b.created-at))
  (table.sort entities newest-first?)
  entities)

;; Match both current meaning and every traversed dependency. Refresh by an
;; inner alias must still find links authored against an upstream alias.
(fn matches-key? [store endpoint key terminal]
  (assert (= (type endpoint) :string) "link endpoint must be a string")
  (local (resolved chain) (store:resolve-key endpoint))
  (var matches? (or (= endpoint key) (= resolved terminal)))
  (each [_ dependency (ipairs chain)]
    (when (= dependency key) (set matches? true)))
  matches?)

(fn endpoint-in-nodes? [store endpoint nodes]
  (var found? false)
  (each [_ key (ipairs nodes) &until found?]
    (when (matches-key? store endpoint key (store:resolve-key key)) (set found? true)))
  found?)

(fn find-edges-for-nodes [self node-keys]
  (local keys (or node-keys []))
  (local results [])
  (each [_ entity (ipairs (list-entities self))]
    (when (and (not (= entity.source-key "")) (not (= entity.target-key ""))
               (endpoint-in-nodes? self.identity-store entity.source-key keys)
               (endpoint-in-nodes? self.identity-store entity.target-key keys))
      (table.insert results entity)))
  results)

(fn find-entities-for-key [self key]
  (local key-str (tostring key))
  (local terminal (self.identity-store:resolve-key key-str))
  (local results [])
  (each [_ entity (ipairs (list-entities self))]
    (when (or (matches-key? self.identity-store entity.source-key key-str terminal)
              (matches-key? self.identity-store entity.target-key key-str terminal))
      (table.insert results entity)))
  results)

(fn LinkEntityStore [opts]
  (local options (or opts {}))
  (local base-dir (fs.absolute (or options.base-dir (appdirs.user-data-dir "space"))))
  (local identity-store (or options.identity-store (IdentityStore.IdentityStore {:base-dir base-dir})))
  (assert (= identity-store.base-dir base-dir) "LinkEntityStore identity-store base-dir mismatch")
  (local root (fs.join-path base-dir "entities"))
  (local entities-dir (fs.join-path root "link"))
  (fs.create-dirs entities-dir)
  {:base-dir base-dir :root root :entities-dir entities-dir :identity-store identity-store :cache {}
   :link-entity-created (Signal) :link-entity-updated (Signal) :link-entity-deleted (Signal)
   :get-entity load-entity :create-entity create-entity :update-entity update-entity
   :delete-entity delete-entity :list-entities list-entities
   :find-edges-for-nodes find-edges-for-nodes :find-entities-for-key find-entities-for-key
   :snapshot-entity snapshot-entity :serialize-entity serialize-entity
   :decode-entity decode-entity :persist-entity! persist-entity!})

(var default-store nil)

(fn get-default [opts]
  (local options (or opts {}))
  (when default-store
    (assert (or (not options.base-dir) (= (fs.absolute options.base-dir) default-store.base-dir))
            "LinkEntityStore default base-dir mismatch")
    (assert (or (not options.identity-store) (= options.identity-store default-store.identity-store))
            "LinkEntityStore default identity-store mismatch"))
  (when (not default-store)
    (local base-dir (fs.absolute (or options.base-dir (appdirs.user-data-dir "space"))))
    (local identity-store (or options.identity-store (IdentityStore.get-default {:base-dir base-dir})))
    (set default-store (LinkEntityStore {:base-dir base-dir :identity-store identity-store})))
  default-store)

{:LinkEntityStore LinkEntityStore :get-default get-default}
