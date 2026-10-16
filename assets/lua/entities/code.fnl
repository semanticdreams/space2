(local Signal (require :signal))
(local appdirs (require :appdirs))
(local fs (require :fs))
(local Uuid (require :uuid))
(local json (require :json))
(local J (require :json-utils))
(local R (require :reference-lifecycle/record-utils))

(fn normalize-name [value] (if (or (= value nil) (= value :nil)) "" (tostring value)))
(fn normalize-language [value] (local result (normalize-name value)) (if (= result "") "fnl" result))
(fn normalize-source [value] (normalize-name value))
(fn normalize-kernel [value]
  (if (or (= value nil) (= value :nil) (= value "")) 0
      (= (type value) :number) value
      (tostring value)))

(fn record [data]
  {:id (R.require-id data.id) :name (normalize-name data.name) :language (normalize-language data.language)
   :source (normalize-source data.source) :kernel (normalize-kernel data.kernel)
   :created-at (assert (tonumber data.created-at) "invalid code created-at")
   :updated-at (assert (tonumber data.updated-at) "invalid code updated-at")})
(fn decode-entity [_self bytes]
  (local data (R.decode-json bytes))
  (assert (= (type data) :table) "code record must be an object")
  (assert (or (= data.kernel nil) (= (type data.kernel) :string) (= (type data.kernel) :number))
          "persisted field kernel must be string or number")
  (record {:id data.id :name (R.field data :name :string "")
           :language (R.field data :language :string "fnl") :source (R.field data :source :string "")
           :kernel data.kernel :created-at (R.field data :created-at :number nil)
           :updated-at (R.field data :updated-at :number nil)}))
(fn serialize-entity [_self entity] (json.dumps (record entity)))
(fn entity-path [self id] (R.record-path self.base-dir self.entities-dir id ".json"))
(fn snapshot-entity [self id]
  (fn decode [bytes] (decode-entity self bytes))
  (local snapshot (R.snapshot (entity-path self id) "json" decode))
  (when snapshot.value (assert (= snapshot.value.id id) (.. "code record id mismatch at " snapshot.path)))
  snapshot)

(fn publish! [self candidate]
  (local held (. self.cache candidate.id))
  (if held
      (do (each [key value (pairs candidate)] (tset held key value)) held)
      (do (tset self.cache candidate.id candidate) candidate)))
(fn write-entity [self candidate]
  (local path (entity-path self candidate.id))
  (fs.create-dirs self.entities-dir)
  (J.write-json! path (record candidate)))
(fn persist-entity! [self id bytes check]
  (local candidate (decode-entity self bytes))
  (R.verify-candidate id candidate (serialize-entity self candidate) check "json")
  (local existed? (not (= (. (snapshot-entity self id) :bytes) false)))
  (write-entity self candidate)
  (local published (publish! self candidate))
  (local signal (if existed? self.code-entity-updated self.code-entity-created))
  (signal:emit published)
  published)
(fn reconcile-entity! [self id bytes before-check after-check]
  (assert (= (. (snapshot-entity self id) :check) after-check) "code reconciliation after-image mismatch")
  (assert (= (R.check-bytes bytes "json") after-check) "code frozen after-check mismatch")
  (local candidate (decode-entity self (if (= bytes false) before-check bytes)))
  (local check (if (= bytes false) before-check after-check))
  (R.verify-candidate id candidate (if (= bytes false) before-check (serialize-entity self candidate)) check "json")
  (if (= bytes false)
      (do
        (local held (or (. self.cache id) candidate))
        (tset self.cache id nil)
        (self.code-entity-deleted:emit held)
        held)
      (do
        (local published (publish! self candidate))
        (local signal (if (= before-check false) self.code-entity-created self.code-entity-updated))
        (signal:emit published)
        published)))
(fn get-entity [self id]
  (when id
    (entity-path self id)
    (if (. self.cache id) (. self.cache id)
        (do
          (local candidate (. (snapshot-entity self id) :value))
          (when candidate (publish! self candidate))))))
(fn create-entity [self opts]
  (assert (or (= opts nil) (= (type opts) :table)) "code create requires options table")
  (local data (R.clone (or opts {})))
  (set data.id (tostring (or data.id (Uuid.v4))))
  (set data.created-at (or data.created-at (os.time)))
  (set data.updated-at (or data.updated-at (os.time)))
  (local candidate (record data))
  (write-entity self candidate)
  (local published (publish! self candidate))
  (self.code-entity-created:emit published)
  published)
(fn update-entity [self id updates]
  (local held (get-entity self id))
  (when held
    (local data (R.clone held))
    (each [key value (pairs (or updates {}))] (tset data key value))
    (assert (= data.id id) "update-entity cannot change id")
    (local candidate (record data))
    (when (not (= (J.stable-json held) (J.stable-json candidate)))
      (set candidate.updated-at (os.time))
      (write-entity self candidate)
      (publish! self candidate)
      (self.code-entity-updated:emit held)))
  held)
(fn retire-entity! [self id]
  (local held (get-entity self id))
  (when held
    (local path (entity-path self id))
    (when (fs.exists path) (fs.remove path))
    (tset self.cache id nil)
    (self.code-entity-deleted:emit held))
  held)
(fn list-entities [self]
  (local candidates [])
  (each [_ entry (ipairs (R.record-entries self.entities-dir ".json"))]
    (table.insert candidates (. (snapshot-entity self (string.sub entry.name 1 -6)) :value)))
  (local records (icollect [_ candidate (ipairs candidates)] (publish! self candidate)))
  (table.sort records (fn newest-first [a b] (> a.updated-at b.updated-at)))
  records)
(fn CodeEntityStore [opts]
  (local options (or opts {}))
  (local base-dir (fs.absolute (or options.base-dir (appdirs.user-data-dir "space"))))
  (local root (fs.join-path base-dir "entities"))
  (local entities-dir (fs.join-path root "code"))
  (fs.create-dirs entities-dir)
  {:base-dir base-dir :root root :entities-dir entities-dir :cache {}
   :code-entity-created (Signal) :code-entity-updated (Signal) :code-entity-deleted (Signal)
   :get-entity get-entity :create-entity create-entity :update-entity update-entity
   :retire-entity! retire-entity! :list-entities list-entities
   :snapshot-entity snapshot-entity :serialize-entity serialize-entity
   :decode-entity decode-entity :persist-entity! persist-entity! :reconcile-entity! reconcile-entity!})
(var default-store nil)
(fn get-default [opts]
  (when (not default-store) (set default-store (CodeEntityStore opts)))
  default-store)
{:CodeEntityStore CodeEntityStore :get-default get-default}
