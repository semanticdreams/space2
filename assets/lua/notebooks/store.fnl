(local Signal (require :signal))
(local appdirs (require :appdirs))
(local fs (require :fs))
(local Uuid (require :uuid))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local IdentityStore (require :entities/identity))
(local R (require :reference-lifecycle/record-utils))

(fn normalize-name [value]
  (if (or (= value nil) (= value :nil)) "" (tostring value)))

(fn copy-record [record] (collect [key value (pairs record)] key value))

;; Pure when decoding/serializing; writes explicitly supply the owning dependency.
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

(fn notebook-path [store id]
  (R.record-path store.base-dir store.notebooks-dir id ".json"))

(fn decode-notebook [_self bytes]
    (local data (R.decode-json bytes))
    (assert (= (type data) :table) "notebook record must be an object")
    (local items (R.require-array (R.field data :items :table [])))
    (each [_ key (ipairs items)] (assert (= (type key) :string) "notebook item must be a reference string"))
    {:id (R.require-id data.id) :name (R.field data :name :string "")
      :items (R.clone items)
      :created-at (R.field data :created-at :number 0)
      :updated-at (R.field data :updated-at :number 0)})

(fn serialize-notebook [_self record]
  (json.dumps {:id (R.require-id record.id) :name record.name :items record.items
               :created-at record.created-at :updated-at record.updated-at}))
(fn snapshot-notebook [self id]
  (fn decode [bytes] (decode-notebook self bytes))
  (local snapshot (R.snapshot (notebook-path self id) "json" decode))
  (when snapshot.value (assert (= snapshot.value.id id) (.. "notebook record id mismatch at " snapshot.path)))
  snapshot)

(fn publish! [store candidate]
  (local held (. store.cache candidate.id))
  (if held
      (do (each [key value (pairs candidate)] (tset held key value)) held)
      (do (tset store.cache candidate.id candidate) candidate)))

(fn write-notebook [store notebook]
  (notebook-path store notebook.id)
  (fs.create-dirs store.notebooks-dir)
  (JsonUtils.write-json! (notebook-path store notebook.id)
                        {:id notebook.id :name notebook.name :items notebook.items
                          :created-at notebook.created-at :updated-at notebook.updated-at}))

(fn persist-notebook! [self id bytes check]
  (local candidate (decode-notebook self bytes))
  (R.verify-candidate id candidate (serialize-notebook self candidate) check "json")
  (local existed? (not (= (. (snapshot-notebook self id) :bytes) false)))
  (write-notebook self candidate)
  (local published (publish! self candidate))
  (local signal (if existed? self.notebook-updated self.notebook-created))
  (signal:emit published)
  (self.notebook-items-changed:emit {:id id :items published.items})
  published)

(fn reconcile-notebook! [self id bytes before-check after-check]
  (assert (= (. (snapshot-notebook self id) :check) after-check) "notebook reconciliation after-image mismatch")
  (assert (= (R.check-bytes bytes "json") after-check) "notebook frozen after-check mismatch")
  (local candidate (decode-notebook self (if (= bytes false) before-check bytes)))
  (local check (if (= bytes false) before-check after-check))
  (R.verify-candidate id candidate (if (= bytes false) before-check (serialize-notebook self candidate)) check "json")
  (if (= bytes false)
      (do
        (local held (or (. self.cache id) candidate))
        (tset self.cache id nil)
        (self.notebook-deleted:emit held)
        held)
      (do
        (local published (publish! self candidate))
        (local signal (if (= before-check false) self.notebook-created self.notebook-updated))
        (signal:emit published)
        (self.notebook-items-changed:emit {:id id :items published.items})
        published)))

(fn load-notebook [store id]
  (when id
    (local key (tostring id))
    (if (. store.cache key) (. store.cache key)
        (do
          (local candidate (. (snapshot-notebook store key) :value))
          (when candidate (publish! store candidate))))))

(fn commit-update! [store notebook candidate items-changed?]
  (set candidate.updated-at (os.time))
  (write-notebook store candidate)
  (publish! store candidate)
  (store.notebook-updated:emit notebook)
  (when items-changed?
    (store.notebook-items-changed:emit {:id notebook.id :items notebook.items}))
  notebook)

(fn create-notebook [self opts]
  (assert (or (= opts nil) (= (type opts) :table)) "notebook create requires options table")
  (local options (or opts {}))
  (local now (os.time))
  (local id (R.require-id (tostring (or options.id (Uuid.v4)))))
  (notebook-path self id)
  (local notebook {:id id
                   :name (normalize-name options.name)
                   :items (normalize-items options.items self.identity-store)
                   :created-at (or options.created-at now) :updated-at (or options.updated-at now)})
  (write-notebook self notebook)
  (local published (publish! self notebook))
  (self.notebook-created:emit published)
  published)

(fn update-notebook [self id updates]
  (assert (or (= updates nil) (= (type updates) :table)) "notebook update requires options table")
  (assert (or (not updates) (not updates.id) (= updates.id id)) "update-notebook cannot change id")
  (local notebook (load-notebook self id))
  (when notebook
    (local candidate (copy-record notebook))
    (var changed? false)
    (var items-changed? false)
    (each [key value (pairs (or updates {}))]
      (assert (or (not (= key :id)) (= value id)) "update-notebook cannot change id")
      (local next-value (if (= key :items) (normalize-items value self.identity-store)
                            (= key :name) (normalize-name value) value))
      (local different? (if (= key :items) (not (items-equal? notebook.items next-value))
                            (not (= (. notebook key) next-value))))
      (when different?
        (set changed? true)
        (when (= key :items) (set items-changed? true))
        (tset candidate key next-value)))
    (when changed? (commit-update! self notebook candidate items-changed?)))
  notebook)

(fn retire-notebook! [self id]
  (local notebook (load-notebook self id))
  (when notebook
    (local path (notebook-path self id))
    (when (fs.exists path) (fs.remove path))
    (tset self.cache (tostring id) nil)
    (self.notebook-deleted:emit notebook))
  notebook)

(fn list-notebooks [self]
  (local candidates [])
  (each [_ entry (ipairs (R.record-entries self.notebooks-dir ".json"))]
    (when (and entry.is-file (string.match entry.name "%.json$"))
      (local candidate (. (snapshot-notebook self (string.sub entry.name 1 -6)) :value))
      (assert candidate (.. "notebook record disappeared at " entry.path))
      (table.insert candidates candidate)))
  (local notebooks (icollect [_ candidate (ipairs candidates)] (publish! self candidate)))
  (fn newest-first? [a b] (> a.updated-at b.updated-at))
  (table.sort notebooks newest-first?)
  notebooks)

(fn replace-items! [self notebook items normalize?]
  (local next-items (if normalize? (normalize-items items self.identity-store) items))
  (when (not (items-equal? notebook.items next-items))
    (local candidate (copy-record notebook))
    (set candidate.items next-items)
    (commit-update! self notebook candidate true))
  notebook)

(fn add-item [self id node-key]
  (local notebook (load-notebook self id))
  (when notebook
    (local items (normalize-items notebook.items))
    (table.insert items (tostring node-key))
    (replace-items! self notebook items true))
  notebook)

(fn remove-item [self id node-key]
  (local notebook (load-notebook self id))
  (when notebook
    (local key (tostring node-key))
    (local existing
      (when (not (= (string.sub key 1 9) "identity:"))
        (self.identity-store:find-by-target-key key)))
    (local stable-key (and existing (.. "identity:" existing.id)))
    (local items (normalize-items notebook.items))
    (var removed? false)
    (each [i value (ipairs items) &until removed?]
      (when (or (= value key) (= value stable-key))
        (table.remove items i)
        (set removed? true)))
    (when removed? (replace-items! self notebook items false)))
  notebook)

(fn reorder-items [self id new-order]
  (local notebook (load-notebook self id))
  (when notebook (replace-items! self notebook new-order true))
  notebook)

(fn move-item [self id from-index to-index]
  (local notebook (load-notebook self id))
  (when notebook
    (local items (normalize-items notebook.items))
    (local from (tonumber from-index))
    (local to (tonumber to-index))
    (when (and from to (>= from 1) (<= from (length items))
               (>= to 1) (<= to (length items)) (not (= from to)))
      (local value (. items from))
      (table.remove items from)
      (table.insert items to value)
      (replace-items! self notebook items true)))
  notebook)

(fn NotebookStore [opts]
  (local options (or opts {}))
  (local base-dir (fs.absolute (or options.base-dir (appdirs.user-data-dir "space"))))
  (local identity-store (or options.identity-store (IdentityStore.IdentityStore {:base-dir base-dir})))
  (assert (= identity-store.base-dir base-dir) "NotebookStore identity-store base-dir mismatch")
  (local notebooks-dir (fs.join-path base-dir "notebooks"))
  (fs.create-dirs notebooks-dir)
  {:base-dir base-dir :notebooks-dir notebooks-dir :identity-store identity-store :cache {}
   :notebook-created (Signal) :notebook-updated (Signal) :notebook-deleted (Signal)
   :notebook-items-changed (Signal)
   :get-notebook load-notebook :create-notebook create-notebook :update-notebook update-notebook
   :retire-notebook! retire-notebook! :list-notebooks list-notebooks :add-item add-item
   :remove-item remove-item :reorder-items reorder-items :move-item move-item
   :snapshot-notebook snapshot-notebook :serialize-notebook serialize-notebook
   :decode-notebook decode-notebook :persist-notebook! persist-notebook! :reconcile-notebook! reconcile-notebook!})

(var default-store nil)

(fn get-default [opts]
  (local options (or opts {}))
  (when default-store
    (assert (or (not options.base-dir) (= (fs.absolute options.base-dir) default-store.base-dir))
            "NotebookStore default base-dir mismatch")
    (assert (or (not options.identity-store) (= options.identity-store default-store.identity-store))
            "NotebookStore default identity-store mismatch"))
  (when (not default-store)
    (local base-dir (fs.absolute (or options.base-dir (appdirs.user-data-dir "space"))))
    (local identity-store (or options.identity-store (IdentityStore.get-default {:base-dir base-dir})))
    (set default-store (NotebookStore {:base-dir base-dir :identity-store identity-store})))
  default-store)

{:NotebookStore NotebookStore :get-default get-default}
