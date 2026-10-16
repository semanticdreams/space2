(local Signal (require :signal))
(local appdirs (require :appdirs))
(local fs (require :fs))
(local Uuid (require :uuid))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local IdentityStore (require :entities/identity))
(local R (require :reference-lifecycle/record-utils))

(fn copy-record [record] (collect [key value (pairs record)] key value))

;; Without an identity store this is a pure legacy decoder/serializer.
(fn normalize-items [items identity-store]
  (local seen {})
  (local out [])
  (each [_ value (ipairs (or items []))]
    (local raw (tostring value))
    (when (> (string.len raw) 0)
      (local key (if identity-store (identity-store:ensure-key raw) raw))
      (when (not (. seen key))
        (tset seen key true)
        (table.insert out key))))
  out)

(fn items-equal? [a b]
  (local left (or a []))
  (local right (or b []))
  (var same? (= (length left) (length right)))
  (each [i value (ipairs left)]
    (when (not (= value (. right i))) (set same? false)))
  same?)

(fn entity-path [store id]
  (R.record-path store.base-dir store.entities-dir id ".json"))

(fn decode-entity [_self bytes]
    (local data (R.decode-json bytes))
    (assert (= (type data) :table) "list record must be an object")
    (local items (R.require-array (R.field data :items :table [])))
    (each [_ key (ipairs items)] (assert (= (type key) :string) "list item must be a reference string"))
    {:id (R.require-id data.id) :name (R.field data :name :string "")
     :items (R.clone items)
     :created-at (R.field data :created-at :number 0)
     :updated-at (R.field data :updated-at :number 0)})

(fn serialize-entity [_self entity]
  (json.dumps {:id (R.require-id entity.id) :name entity.name :items entity.items
               :created-at entity.created-at :updated-at entity.updated-at}))
(fn snapshot-entity [self id]
  (fn decode [bytes] (decode-entity self bytes))
  (local snapshot (R.snapshot (entity-path self id) "json" decode))
  (when snapshot.value (assert (= snapshot.value.id id) (.. "list record id mismatch at " snapshot.path)))
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
                        {:id entity.id :name entity.name :items entity.items
                          :created-at entity.created-at :updated-at entity.updated-at}))

(fn persist-entity! [self id bytes check]
  (local candidate (decode-entity self bytes))
  (R.verify-candidate id candidate (serialize-entity self candidate) check "json")
  (local existed? (not (= (. (snapshot-entity self id) :bytes) false)))
  (write-entity self candidate)
  (local published (publish! self candidate))
  (local signal (if existed? self.list-entity-updated self.list-entity-created))
  (signal:emit published)
  (self.list-entity-items-changed:emit {:id id :items published.items})
  published)

(fn reconcile-entity! [self id bytes before-check after-check]
  (assert (= (. (snapshot-entity self id) :check) after-check) "list reconciliation after-image mismatch")
  (assert (= (R.check-bytes bytes "json") after-check) "list frozen after-check mismatch")
  (local candidate (decode-entity self (if (= bytes false) before-check bytes)))
  (local check (if (= bytes false) before-check after-check))
  (R.verify-candidate id candidate (if (= bytes false) before-check (serialize-entity self candidate)) check "json")
  (if (= bytes false)
      (do
        (local held (or (. self.cache id) candidate))
        (tset self.cache id nil)
        (self.list-entity-deleted:emit held)
        held)
      (do
        (local published (publish! self candidate))
        (local signal (if (= before-check false) self.list-entity-created self.list-entity-updated))
        (signal:emit published)
        (self.list-entity-items-changed:emit {:id id :items published.items})
        published)))

(fn load-entity [store id]
  (when id
    (local key (tostring id))
    (if (. store.cache key) (. store.cache key)
        (do
          (local candidate (. (snapshot-entity store key) :value))
          (when candidate (publish! store candidate))))))

(fn commit-update! [store entity candidate items-changed?]
  (set candidate.updated-at (os.time))
  (write-entity store candidate)
  (publish! store candidate)
  (store.list-entity-updated:emit entity)
  (when items-changed?
    (store.list-entity-items-changed:emit {:id entity.id :items entity.items}))
  entity)

(fn create-entity [self opts]
  (assert (or (= opts nil) (= (type opts) :table)) "list create requires options table")
  (local options (or opts {}))
  (local now (os.time))
  (local id (R.require-id (tostring (or options.id (Uuid.v4)))))
  (entity-path self id)
  (local entity {:id id
                 :name (or options.name "")
                 :items (normalize-items options.items self.identity-store)
                 :created-at (or options.created-at now) :updated-at (or options.updated-at now)})
  (write-entity self entity)
  (local published (publish! self entity))
  (self.list-entity-created:emit published)
  published)

(fn update-entity [self id updates]
  (assert (or (= updates nil) (= (type updates) :table)) "list update requires options table")
  (assert (or (not updates) (not updates.id) (= updates.id id)) "update-entity cannot change id")
  (local entity (load-entity self id))
  (when entity
    (local candidate (copy-record entity))
    (var changed? false)
    (var items-changed? false)
    (each [key value (pairs (or updates {}))]
      (assert (or (not (= key :id)) (= value id)) "update-entity cannot change id")
      (local next-value (if (= key :items) (normalize-items value self.identity-store) value))
      (local different? (if (= key :items) (not (items-equal? entity.items next-value))
                            (not (= (. entity key) next-value))))
      (when different?
        (set changed? true)
        (when (= key :items) (set items-changed? true))
        (tset candidate key next-value)))
    (when changed? (commit-update! self entity candidate items-changed?)))
  entity)

(fn retire-entity! [self id]
  (local entity (load-entity self id))
  (when entity
    (local path (entity-path self id))
    (when (fs.exists path) (fs.remove path))
    (tset self.cache (tostring id) nil)
    (self.list-entity-deleted:emit entity))
  entity)

(fn list-entities [self]
  (local candidates [])
  (each [_ entry (ipairs (R.record-entries self.entities-dir ".json"))]
    (when (and entry.is-file (string.match entry.name "%.json$"))
      (local candidate (. (snapshot-entity self (string.sub entry.name 1 -6)) :value))
      (assert candidate (.. "list record disappeared at " entry.path))
      (table.insert candidates candidate)))
  (local entities (icollect [_ candidate (ipairs candidates)] (publish! self candidate)))
  (fn newest-first? [a b] (> a.updated-at b.updated-at))
  (table.sort entities newest-first?)
  entities)

(fn replace-items! [self entity items normalize?]
  (local next-items (if normalize? (normalize-items items self.identity-store) items))
  (when (not (items-equal? entity.items next-items))
    (local candidate (copy-record entity))
    (set candidate.items next-items)
    (commit-update! self entity candidate true))
  entity)

(fn add-item [self id node-key]
  (local entity (load-entity self id))
  (when entity
    (local items (normalize-items entity.items))
    (table.insert items (tostring node-key))
    (replace-items! self entity items true))
  entity)

(fn remove-item [self id node-key]
  (local entity (load-entity self id))
  (when entity
    (local key (tostring node-key))
    (local existing
      (when (not (= (string.sub key 1 9) "identity:"))
        (self.identity-store:find-by-target-key key)))
    (local stable-key (and existing (.. "identity:" existing.id)))
    (local items (normalize-items entity.items))
    (var removed? false)
    (each [i value (ipairs items) &until removed?]
      (when (or (= value key) (= value stable-key))
        (table.remove items i)
        (set removed? true)))
    ;; Removal never normalizes remaining legacy values or allocates identities.
    (when removed? (replace-items! self entity items false)))
  entity)

(fn reorder-items [self id new-order]
  (local entity (load-entity self id))
  (when entity (replace-items! self entity new-order true))
  entity)

(fn move-item [self id from-index to-index]
  (local entity (load-entity self id))
  (when entity
    (local items (normalize-items entity.items))
    (local from (tonumber from-index))
    (local to (tonumber to-index))
    (when (and from to (>= from 1) (<= from (length items))
               (>= to 1) (<= to (length items)) (not (= from to)))
      (local value (. items from))
      (table.remove items from)
      (table.insert items to value)
      (replace-items! self entity items true)))
  entity)

(fn ListEntityStore [opts]
  (local options (or opts {}))
  (local base-dir (fs.absolute (or options.base-dir (appdirs.user-data-dir "space"))))
  (local identity-store (or options.identity-store (IdentityStore.IdentityStore {:base-dir base-dir})))
  (assert (= identity-store.base-dir base-dir) "ListEntityStore identity-store base-dir mismatch")
  (local root (fs.join-path base-dir "entities"))
  (local entities-dir (fs.join-path root "list"))
  (fs.create-dirs entities-dir)
  {:base-dir base-dir :root root :entities-dir entities-dir :identity-store identity-store :cache {}
   :list-entity-created (Signal) :list-entity-updated (Signal)
   :list-entity-deleted (Signal) :list-entity-items-changed (Signal)
   :get-entity load-entity :create-entity create-entity :update-entity update-entity
   :retire-entity! retire-entity! :list-entities list-entities :add-item add-item
   :remove-item remove-item :reorder-items reorder-items :move-item move-item
   :snapshot-entity snapshot-entity :serialize-entity serialize-entity
   :decode-entity decode-entity :persist-entity! persist-entity! :reconcile-entity! reconcile-entity!})

(var default-store nil)

(fn get-default [opts]
  (local options (or opts {}))
  (when default-store
    (assert (or (not options.base-dir) (= (fs.absolute options.base-dir) default-store.base-dir))
            "ListEntityStore default base-dir mismatch")
    (assert (or (not options.identity-store) (= options.identity-store default-store.identity-store))
            "ListEntityStore default identity-store mismatch"))
  (when (not default-store)
    (local base-dir (fs.absolute (or options.base-dir (appdirs.user-data-dir "space"))))
    (local identity-store (or options.identity-store (IdentityStore.get-default {:base-dir base-dir})))
    (set default-store (ListEntityStore {:base-dir base-dir :identity-store identity-store})))
  default-store)

{:ListEntityStore ListEntityStore :get-default get-default}
