(local Signal (require :signal))
(local appdirs (require :appdirs))
(local fs (require :fs))
(local Uuid (require :uuid))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local IdentityStore (require :entities/identity))

(fn ensure-dir [path]
  (when (and path fs fs.create-dirs)
    (fs.create-dirs path))
  path)

(fn table-or-empty [value]
  (if (= (type value) "table") value {}))

(fn default-string [value]
  (if (= value nil) "" value))

(fn default-number [value]
  (local n (tonumber value))
  (if n n 0))

(fn option-table [opts]
  (if (= (type opts) "table") opts {}))

(fn non-empty-string? [value]
  (and (not (= value nil)) (> (string.len (tostring value)) 0)))

(fn normalize-items [items identity-store]
  (local out {})
  (each [key value (pairs (table-or-empty items))]
    (local item-key (tostring key))
    (local item-value (tostring value))
    (when (and (non-empty-string? item-key)
               (non-empty-string? item-value))
      (set (. out item-key) (if identity-store (identity-store:ensure-key item-value) item-value))))
  out)

(fn item-count [items]
  (var count 0)
  (each [_ _ (pairs (table-or-empty items))]
    (set count (+ count 1)))
  count)

(fn items-equal? [a b]
  (local left (table-or-empty a))
  (local right (table-or-empty b))
  (if (not (= (item-count left) (item-count right)))
      false
      (do
        (var same? true)
        (each [key value (pairs left)]
          (when (not (= value (. right key)))
            (set same? false)))
        same?)))

(fn required-item-key [value context]
  (when (= value nil)
    (error (.. context " requires item key")))
  (local key (tostring value))
  (when (= (string.len key) 0)
    (error (.. context " requires non-empty item key")))
  key)

(fn required-item-value [value context]
  (when (= value nil)
    (error (.. context " requires item value")))
  (local item-value (tostring value))
  (when (= (string.len item-value) 0)
    (error (.. context " requires non-empty item value")))
  item-value)

(fn entity-path [store id]
  (and store.entities-dir (fs.join-path store.entities-dir (.. (tostring id) ".json"))))

(fn persisted-entity [entity]
  {:id entity.id
   :name entity.name
   :items (normalize-items entity.items)
   :created-at entity.created-at
   :updated-at entity.updated-at})

(fn decoded-entity [data]
  {:id (default-string data.id)
   :name (default-string data.name)
   :items (normalize-items data.items)
   :created-at (default-number data.created-at)
   :updated-at (default-number data.updated-at)})

(fn read-entity [path]
  (fn decode []
    (local data (json.loads (fs.read-file path)))
    (assert (= (type data) :table) "dict record must be an object")
    (decoded-entity data))
  (when (and path fs fs.exists (fs.exists path))
    (local (ok result) (pcall decode))
    (assert ok (.. "dict read failed at " path ": " (tostring result)))
    result))

(fn copy-record [record] (collect [key value (pairs record)] key value))

(fn publish! [store candidate]
  (local held (. store.cache candidate.id))
  (if held
      (do (each [key value (pairs candidate)] (tset held key value)) held)
      (do (tset store.cache candidate.id candidate) candidate)))

(fn write-entity [store entity]
  (when entity
    (local path (entity-path store entity.id))
    (when path
      (ensure-dir store.entities-dir)
      (JsonUtils.write-json! path (persisted-entity entity))))
  entity)

(fn remove-entity-file! [path]
  (when (and path fs fs.remove (fs.exists path))
    (local (ok err) (pcall fs.remove path))
    (when (not ok)
      (error (.. "failed to delete dict entity file " path ": " (tostring err))))))

(fn load-entity [store id]
  (when id
    (local key (tostring id))
    (if (. store.cache key)
        (. store.cache key)
        (do
          (local data (read-entity (entity-path store key)))
          (when data
            (set (. store.cache key) data))
          data))))

(fn emit-items-changed [store entity]
  (store.dict-entity-items-changed:emit {:id entity.id :items entity.items}))

(fn apply-updates! [entity updates identity-store]
  (var changed? false)
  (var items-changed? false)
  (each [k v (pairs (table-or-empty updates))]
    (local items-key? (if (= k :items) true (= k "items")))
    (local current (. entity k))
    (local next-value (if items-key? (normalize-items v identity-store) v))
    (local different? (if items-key?
                          (not (items-equal? current next-value))
                          (not (= current next-value))))
    (when different?
      (set changed? true)
      (when items-key?
        (set items-changed? true))
      (set (. entity k) next-value)))
  (values changed? items-changed?))

(fn get-entity [self id]
  (load-entity self id))

(fn create-entity [self opts]
  (local create-opts (option-table opts))
  (local id (tostring (if create-opts.id create-opts.id (Uuid.v4))))
  (local now (os.time))
  (local entity {:id id
                 :name (default-string create-opts.name)
                  :items (normalize-items create-opts.items self.identity-store)
                 :created-at (if create-opts.created-at create-opts.created-at now)
                 :updated-at (if create-opts.updated-at create-opts.updated-at now)})
  (write-entity self entity)
  (local published (publish! self entity))
  (self.dict-entity-created:emit published)
  published)

(fn commit-update! [self entity candidate items-changed?]
  (set candidate.updated-at (os.time))
  (write-entity self candidate)
  (publish! self candidate)
  (self.dict-entity-updated:emit entity)
  (when items-changed? (emit-items-changed self entity))
  entity)

(fn update-entity [self id updates]
  (local entity (load-entity self id))
  (when entity
    (local candidate (copy-record entity))
    (local (changed? items-changed?) (apply-updates! candidate updates self.identity-store))
    (when changed?
      (commit-update! self entity candidate items-changed?)))
  entity)

(fn delete-entity [self id]
  (local entity (load-entity self id))
  (when entity
    (local path (entity-path self id))
    (remove-entity-file! path)
    (set (. self.cache (tostring id)) nil)
    (self.dict-entity-deleted:emit entity))
  entity)

(fn list-entities [self]
  (local candidates [])
  (each [_ entry (ipairs (fs.list-dir self.entities-dir false))]
    (when (and entry.is-file (string.match entry.name "%.json$"))
      (local data (read-entity entry.path))
      (assert data (.. "dict record disappeared at " entry.path))
      (table.insert candidates data)))
  (local entities (icollect [_ candidate (ipairs candidates)] (publish! self candidate)))
  (table.sort entities
              (fn [a b]
                (> (if a.updated-at a.updated-at 0)
                   (if b.updated-at b.updated-at 0))))
  entities)

(fn get-item [self id item-key]
  (local entity (load-entity self id))
  (when entity
    (. entity.items (tostring item-key))))

(fn set-item [self id item-key node-key]
  (local key (required-item-key item-key "dict set-item"))
  (local raw (required-item-value node-key "dict set-item"))
  (local entity (load-entity self id))
  (when entity
    (local value (self.identity-store:ensure-key raw))
    (when (not (= (. entity.items key) value))
      (local candidate (copy-record entity))
      (set candidate.items (copy-record entity.items))
      (tset candidate.items key value)
      (commit-update! self entity candidate true)))
  entity)

(fn remove-item [self id item-key]
  (local key (required-item-key item-key "dict remove-item"))
  (local entity (load-entity self id))
  (when entity
    (when (not (= (. entity.items key) nil))
      (local candidate (copy-record entity))
      (set candidate.items (copy-record entity.items))
      (tset candidate.items key nil)
      (commit-update! self entity candidate true)))
  entity)

(fn rename-item [self id old-key new-key]
  (local old (required-item-key old-key "dict rename-item"))
  (local new (required-item-key new-key "dict rename-item"))
  (local entity (load-entity self id))
  (when entity
    (when (not (= old new))
      (local value (. entity.items old))
      (when (not (= value nil))
        (when (not (= (. entity.items new) nil))
          (error (.. "dict rename-item item key already exists: " new)))
        (local candidate (copy-record entity))
        (set candidate.items (copy-record entity.items))
        (tset candidate.items old nil)
        (tset candidate.items new value)
        (commit-update! self entity candidate true))))
  entity)

(fn DictEntityStore [opts]
  (local options (option-table opts))
  (local base-dir (fs.absolute (if options.base-dir options.base-dir (appdirs.user-data-dir "space"))))
  (local identity-store (if options.identity-store options.identity-store
                            (IdentityStore.IdentityStore {:base-dir base-dir})))
  (assert (= identity-store.base-dir base-dir) "DictEntityStore identity-store base-dir mismatch")
  (local root (fs.join-path base-dir "entities"))
  (local entities-dir (fs.join-path root "dict"))
  (ensure-dir entities-dir)
  {:base-dir base-dir
   :identity-store identity-store
   :root root
   :entities-dir entities-dir
   :cache {}
   :dict-entity-created (Signal)
   :dict-entity-updated (Signal)
   :dict-entity-deleted (Signal)
   :dict-entity-items-changed (Signal)
   :get-entity get-entity
   :create-entity create-entity
   :update-entity update-entity
   :delete-entity delete-entity
   :list-entities list-entities
   :get-item get-item
   :set-item set-item
   :remove-item remove-item
   :rename-item rename-item})

(var default-store nil)

(fn get-default [opts]
  (local options (option-table opts))
  (when default-store
    (assert (or (not options.base-dir) (= (fs.absolute options.base-dir) default-store.base-dir))
            "DictEntityStore default base-dir mismatch")
    (assert (or (not options.identity-store) (= options.identity-store default-store.identity-store))
            "DictEntityStore default identity-store mismatch"))
  (when (not default-store)
    (local base-dir (fs.absolute (or options.base-dir (appdirs.user-data-dir "space"))))
    (local identity-store (or options.identity-store (IdentityStore.get-default {:base-dir base-dir})))
    (set default-store (DictEntityStore {:base-dir base-dir :identity-store identity-store})))
  default-store)

{:DictEntityStore DictEntityStore
 :get-default get-default}
