(local Signal (require :signal))
(local appdirs (require :appdirs))
(local fs (require :fs))
(local Uuid (require :uuid))
(local R (require :reference-lifecycle/record-utils))

(fn serialize-entity [_self entity]
  (assert (= (type entity.value) :string) "string value must be text")
  (R.require-id entity.id)
  (table.concat ["---" (.. "id: " entity.id)
                 (.. "created-at: " entity.created-at)
                 (.. "updated-at: " entity.updated-at) "---" "" entity.value] "\n"))

(fn decode-entity [_self bytes]
  (local (frontmatter body) (string.match bytes "^%-%-%-\n(.-)\n%-%-%-\n(.*)$"))
  (assert frontmatter "string record requires frontmatter")
  (local fields {})
  (each [line (string.gmatch frontmatter "[^\n]+")]
    (local (key value) (string.match line "^([^:]+):%s*(.*)$"))
    (assert key "malformed string frontmatter")
    (tset fields key value))
  ;; The existing serializer owns one separator blank line. Remove that one
  ;; newline only, never whitespace belonging to the user's source.
  (local source (if (= (string.sub body 1 1) "\n") (string.sub body 2) body))
  {:id (R.require-id fields.id) :value source
   :created-at (assert (tonumber fields.created-at) "invalid string created-at")
   :updated-at (assert (tonumber fields.updated-at) "invalid string updated-at")})

(fn entity-path [store id] (R.record-path store.base-dir store.entities-dir id ".md"))
(fn snapshot-entity [self id]
  (fn decode [bytes] (decode-entity self bytes))
  (local snapshot (R.snapshot (entity-path self id) "string" decode))
  (when snapshot.value (assert (= snapshot.value.id id) (.. "string record id mismatch at " snapshot.path)))
  snapshot)

(fn publish! [store candidate]
  (local held (. store.cache candidate.id))
  (if held
      (do (each [key value (pairs candidate)] (tset held key value)) held)
      (do (tset store.cache candidate.id candidate) candidate)))

(fn write-entity [store candidate]
  (local path (entity-path store candidate.id))
  (fs.create-dirs store.entities-dir)
  (fs.write-file path (serialize-entity store candidate)))

(fn persist-entity! [self id bytes check]
  (local candidate (decode-entity self bytes))
  (R.verify-candidate id candidate (serialize-entity self candidate) check "string")
  (local existed? (not (= (. (snapshot-entity self id) :bytes) false)))
  (write-entity self candidate)
  (local published (publish! self candidate))
  (local signal (if existed? self.string-entity-updated self.string-entity-created))
  (signal:emit published)
  published)

(fn reconcile-entity! [self id bytes before-check after-check]
  (assert (= (. (snapshot-entity self id) :check) after-check) "string reconciliation after-image mismatch")
  (assert (= (R.check-bytes bytes "string") after-check) "string frozen after-check mismatch")
  (local candidate (decode-entity self (if (= bytes false) before-check bytes)))
  (local check (if (= bytes false) before-check after-check))
  (R.verify-candidate id candidate (if (= bytes false) before-check (serialize-entity self candidate)) check "string")
  (if (= bytes false)
      (do
        (local held (or (. self.cache id) candidate))
        (tset self.cache id nil)
        (self.string-entity-deleted:emit held)
        held)
      (do
        (local published (publish! self candidate))
        (local signal (if (= before-check false) self.string-entity-created self.string-entity-updated))
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
  (assert (or (= opts nil) (= (type opts) :table)) "string create requires options table")
  (local options (or opts {}))
  (local timestamp (os.time))
  (local candidate {:id (tostring (or options.id (Uuid.v4))) :value (or options.value "")
                   :created-at (or options.created-at timestamp) :updated-at (or options.updated-at timestamp)})
  (write-entity self candidate)
  (local published (publish! self candidate))
  (self.string-entity-created:emit published)
  published)

(fn update-entity [self id updates]
  (local entity (get-entity self id))
  (when entity
    (local candidate (R.clone entity))
    (each [key value (pairs (or updates {}))] (tset candidate key value))
    (assert (= candidate.id id) "update-entity cannot change id")
    (set candidate.updated-at (os.time))
    (write-entity self candidate)
    (publish! self candidate)
    (self.string-entity-updated:emit entity))
  entity)

(fn delete-entity [self id]
  (local entity (get-entity self id))
  (when entity
    (local path (entity-path self id))
    (when (fs.exists path) (fs.remove path))
    (tset self.cache id nil)
    (self.string-entity-deleted:emit entity))
  entity)

(fn list-entities [self]
  (local candidates [])
  (each [_ entry (ipairs (R.record-entries self.entities-dir ".md"))]
    (table.insert candidates (. (snapshot-entity self (string.sub entry.name 1 -4)) :value)))
  (local records (icollect [_ candidate (ipairs candidates)] (publish! self candidate)))
  (table.sort records (fn newest-first [a b] (> a.updated-at b.updated-at)))
  records)

(fn StringEntityStore [opts]
  (local options (or opts {}))
  (local base-dir (fs.absolute (or options.base-dir (appdirs.user-data-dir "space"))))
  (local root (fs.join-path base-dir "entities"))
  (local entities-dir (fs.join-path root "string"))
  (fs.create-dirs entities-dir)
  {:base-dir base-dir :root root :entities-dir entities-dir :cache {}
   :string-entity-created (Signal) :string-entity-updated (Signal) :string-entity-deleted (Signal)
   :get-entity get-entity :create-entity create-entity :update-entity update-entity
   :delete-entity delete-entity :list-entities list-entities
   :snapshot-entity snapshot-entity :serialize-entity serialize-entity
   :decode-entity decode-entity :persist-entity! persist-entity! :reconcile-entity! reconcile-entity!})

(var default-store nil)
(fn get-default [opts]
  (when (not default-store) (set default-store (StringEntityStore opts)))
  default-store)
{:StringEntityStore StringEntityStore :get-default get-default}
