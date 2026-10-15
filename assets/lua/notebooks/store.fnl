(local Signal (require :signal))
(local appdirs (require :appdirs))
(local fs (require :fs))
(local Uuid (require :uuid))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local IdentityStore (require :entities/identity))

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
  (fs.join-path store.notebooks-dir (.. (tostring id) ".json")))

(fn read-notebook [path]
  (fn decode []
    (local data (json.loads (fs.read-file path)))
    (assert (= (type data) :table) "notebook record must be an object")
    {:id (tostring (or data.id "")) :name (normalize-name data.name)
     :items (normalize-items data.items)
     :created-at (tonumber (or data.created-at 0))
     :updated-at (tonumber (or data.updated-at 0))})
  (when (fs.exists path)
    (local (ok result) (pcall decode))
    (assert ok (.. "notebook read failed at " path ": " (tostring result)))
    result))

(fn publish! [store candidate]
  (local held (. store.cache candidate.id))
  (if held
      (do (each [key value (pairs candidate)] (tset held key value)) held)
      (do (tset store.cache candidate.id candidate) candidate)))

(fn write-notebook [store notebook]
  (fs.create-dirs store.notebooks-dir)
  (JsonUtils.write-json! (notebook-path store notebook.id)
                        {:id notebook.id :name notebook.name :items notebook.items
                         :created-at notebook.created-at :updated-at notebook.updated-at}))

(fn load-notebook [store id]
  (when id
    (local key (tostring id))
    (if (. store.cache key) (. store.cache key)
        (do
          (local candidate (read-notebook (notebook-path store key)))
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
  (local options (or opts {}))
  (local now (os.time))
  (local notebook {:id (tostring (or options.id (Uuid.v4)))
                   :name (normalize-name options.name)
                   :items (normalize-items options.items self.identity-store)
                   :created-at (or options.created-at now) :updated-at (or options.updated-at now)})
  (write-notebook self notebook)
  (local published (publish! self notebook))
  (self.notebook-created:emit published)
  published)

(fn update-notebook [self id updates]
  (assert (or (= updates nil) (= (type updates) :table)) "notebook update requires options table")
  (local notebook (load-notebook self id))
  (when notebook
    (local candidate (copy-record notebook))
    (var changed? false)
    (var items-changed? false)
    (each [key value (pairs (or updates {}))]
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

(fn delete-notebook [self id]
  (local notebook (load-notebook self id))
  (when notebook
    (local path (notebook-path self id))
    (when (fs.exists path) (fs.remove path))
    (tset self.cache (tostring id) nil)
    (self.notebook-deleted:emit notebook))
  notebook)

(fn list-notebooks [self]
  (local candidates [])
  (each [_ entry (ipairs (fs.list-dir self.notebooks-dir false))]
    (when (and entry.is-file (string.match entry.name "%.json$"))
      (local candidate (read-notebook entry.path))
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
   :delete-notebook delete-notebook :list-notebooks list-notebooks :add-item add-item
   :remove-item remove-item :reorder-items reorder-items :move-item move-item})

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
