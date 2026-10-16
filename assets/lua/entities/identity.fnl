(local Signal (require :signal))
(local appdirs (require :appdirs))
(local fs (require :fs))
(local Uuid (require :uuid))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local R (require :reference-lifecycle/record-utils))

(fn normalize-target-key [value]
  (if (= value nil) "" (= value :nil) "" (tostring value)))

(fn normalize-metadata [value]
  (if (= (type value) :table) value {}))

(fn copy-record [record]
  (collect [key value (pairs record)] key value))

(fn options-table [opts]
  (local options (or opts {}))
  (assert (= (type options) :table) "identity options must be a table")
  options)

(fn publish! [cache candidate]
  (local held (. cache candidate.id))
  (if held
      (do
        (each [key value (pairs candidate)] (tset held key value))
        held)
      (do (tset cache candidate.id candidate) candidate)))

(fn decode-entity [_self bytes]
    (local data (R.decode-json bytes))
    (assert (= (type data) :table) "identity record must be an object")
    {:id (R.require-id data.id)
     :target-key (R.field data :target-key :string "")
     :created-at (R.field data :created-at :number 0)
     :updated-at (R.field data :updated-at :number 0)
     :metadata (R.field data :metadata :table {})})

(fn serialize-entity [_self entity]
  (json.dumps {:id (R.require-id entity.id) :target-key entity.target-key
               :created-at entity.created-at :updated-at entity.updated-at :metadata entity.metadata}))
(fn snapshot-entity [self id]
  (fn decode [bytes] (decode-entity self bytes))
  (local path (R.record-path self.base-dir self.entities-dir id ".json"))
  (local snapshot (R.snapshot path "json" decode))
  (when snapshot.value (assert (= snapshot.value.id id) (.. "identity record id mismatch at " path)))
  snapshot)

(fn write-entity [entities-dir path entity]
  (fs.create-dirs entities-dir)
  (JsonUtils.write-json! path {:id (tostring entity.id)
                              :target-key (normalize-target-key entity.target-key)
                              :created-at entity.created-at
                              :updated-at entity.updated-at
                              :metadata (normalize-metadata entity.metadata)}))

(fn make-entity [opts]
  (local options (or opts {}))
  (assert (= (type options) :table) "identity create requires options table")
  (local now (os.time))
  {:id (tostring (or options.id (Uuid.v4)))
   :target-key (normalize-target-key options.target-key)
   :created-at (or options.created-at now)
   :updated-at (or options.updated-at now)
    :metadata (normalize-metadata options.metadata)})

(fn persist-entity! [self id bytes check]
  (local candidate (decode-entity self bytes))
  (R.verify-candidate id candidate (serialize-entity self candidate) check "json")
  (local before (snapshot-entity self id))
  (write-entity self.entities-dir before.path candidate)
  (local published (publish! self.cache candidate))
  (local signal (if before.value self.identity-updated self.identity-created))
  (signal:emit published)
  published)

(fn reconcile-entity! [self id bytes before-check after-check]
  (assert (= (. (snapshot-entity self id) :check) after-check) "identity reconciliation after-image mismatch")
  (assert (= (R.check-bytes bytes "json") after-check) "identity frozen after-check mismatch")
  (local candidate (decode-entity self (if (= bytes false) before-check bytes)))
  (local check (if (= bytes false) before-check after-check))
  (R.verify-candidate id candidate (if (= bytes false) before-check (serialize-entity self candidate)) check "json")
  (if (= bytes false)
      (do
        (local held (or (. self.cache id) candidate))
        (tset self.cache id nil)
        (self.identity-deleted:emit held)
        held)
      (do
        (local published (publish! self.cache candidate))
        (local signal (if (= before-check false) self.identity-created self.identity-updated))
        (signal:emit published)
        published)))

(fn apply-updates! [candidate updates]
  (var changed? false)
  (each [key value (pairs updates)]
    (assert (or (not (= key :id)) (= value candidate.id)) "update-entity cannot change id")
    (local next-value (if (= key :target-key) (normalize-target-key value)
                          (= key :metadata) (normalize-metadata value)
                          value))
    (when (not (= (. candidate key) next-value))
      (set changed? true)
      (tset candidate key next-value)))
  changed?)

(fn identity-key? [key]
  (and (= (type key) :string) (= (string.sub key 1 9) "identity:")))

(fn resolve-key [self key opts]
  (local options (or opts {}))
  (local max-depth (or options.max-depth 32))
  (assert (and (= (type max-depth) :number) (>= max-depth 0)
               (= max-depth (math.floor max-depth))) "resolve-key requires nonnegative integer max-depth")
  (local visited (copy-record (or options.visited {})))
  (local chain [])
  (var current key)
  (var depth 0)
  (while (identity-key? current)
    (assert (not (. visited current)) (.. "resolve-key identity cycle detected at " current))
    (tset visited current true)
    (table.insert chain current)
    (local entity (self:get-entity (string.sub current 10)))
    (local target (and entity entity.target-key))
    (when (or (not target) (= target "")) (lua "return current, chain"))
    (assert (< depth max-depth) (.. "resolve-key identity depth exhausted at " current))
    (set current target)
    (set depth (+ depth 1)))
  (values current chain))

(fn ensure-key [self key opts]
  (assert (= (type key) :string) "ensure-key requires string key")
  (if (or (= key "") (identity-key? key))
      key
      (do
        (local existing (self:find-by-target-key key))
        (if existing
            (.. "identity:" existing.id)
            (do
              (local options (copy-record (or opts {})))
              (set options.target-key key)
              (.. "identity:" (. (self:create-entity options) :id)))))))

(fn IdentityStore [opts]
  (local options (options-table opts))
  (local requested-dir (or options.base-dir (appdirs.user-data-dir "space")))
  (assert (= (type requested-dir) :string) "IdentityStore requires a base directory")
  (local base-dir (fs.absolute requested-dir))
  (local root (fs.join-path base-dir "entities"))
  (local entities-dir (fs.join-path root "identity"))
  (fs.create-dirs entities-dir)
  (local cache {})
  (local identity-created (Signal))
  (local identity-updated (Signal))
  (local identity-deleted (Signal))

  (fn entity-path [id]
    (R.record-path base-dir entities-dir id ".json"))

  (fn read-entity [path]
    (fn decode [bytes] (decode-entity nil bytes))
    (local value (. (R.snapshot path "json" decode) :value))
    (when value
      (assert (= (entity-path value.id) path) (.. "identity record id mismatch at " path))
      value))

  (fn load-entity [id]
    (local key (tostring id))
    (if (. cache key) (. cache key)
        (do
          (local data (read-entity (entity-path key)))
          (when data (publish! cache data)))))

  (fn get-entity [_self id]
    (when id (load-entity id)))

  (fn create-entity [_self opts]
    (local entity (make-entity opts))
    (write-entity entities-dir (entity-path entity.id) entity)
    (local published (publish! cache entity))
    (identity-created:emit published)
    published)

  (fn update-entity [_self id updates]
    (local entity (load-entity id))
    (when entity
      (local candidate (copy-record entity))
      (when (apply-updates! candidate (options-table updates))
        (set candidate.updated-at (os.time))
        (write-entity entities-dir (entity-path candidate.id) candidate)
        (publish! cache candidate)
        (identity-updated:emit entity)))
    entity)

  (fn retire-entity! [_self id]
    (local entity (load-entity id))
    (when entity
      (local path (entity-path id))
      (when (fs.exists path) (fs.remove path))
      (tset cache (tostring id) nil)
      (identity-deleted:emit entity))
    entity)

  (fn list-entities [_self]
    (local candidates [])
    (each [_ entry (ipairs (R.record-entries entities-dir ".json"))]
      (when (and entry.is-file (string.match entry.name "%.json$"))
        (local data (read-entity entry.path))
        (assert data (.. "identity record disappeared at " entry.path))
        (table.insert candidates data)))
    (local items (icollect [_ data (ipairs candidates)] (publish! cache data)))
    (fn newest-first? [a b] (> a.updated-at b.updated-at))
    (table.sort items newest-first?)
    items)

  (fn find-by-target-key [self target-key]
    (local matches [])
    (each [_ entity (ipairs (list-entities self))]
      (when (and (not (= target-key "")) (= entity.target-key target-key))
        (table.insert matches entity)))
    (fn id-before? [a b] (< a.id b.id))
    (table.sort matches id-before?)
    (. matches 1))

  {:base-dir base-dir
   :root root
    :entities-dir entities-dir
    :cache cache
   :identity-created identity-created
   :identity-updated identity-updated
   :identity-deleted identity-deleted
   :get-entity get-entity
   :create-entity create-entity
   :update-entity update-entity
   :retire-entity! retire-entity!
   :list-entities list-entities
   :find-by-target-key find-by-target-key
   :ensure-key ensure-key
    :resolve-key resolve-key
    :snapshot-entity snapshot-entity :serialize-entity serialize-entity
     :decode-entity decode-entity :persist-entity! persist-entity! :reconcile-entity! reconcile-entity!})

(var default-store nil)

(fn get-default [opts]
  (if default-store default-store
      (do
        (set default-store (IdentityStore opts))
        default-store)))

{:IdentityStore IdentityStore
 :get-default get-default}
