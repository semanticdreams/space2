(local fs (require :fs))
(local json (require :json))
(local J (require :json-utils))

(fn clone [value]
  (if (= (type value) :table)
      (collect [key item (pairs value)] key (clone item))
      value))

;; The native bridge maps JSON null to Lua nil, losing object members and array
;; slots (including trailing slots). Strict owning records cannot accept that
;; lossy representation. This is only a quoted-token guard; json.loads remains
;; the parser, and its global behavior is unchanged.
(fn decode-json [bytes]
  (var quoted? false)
  (var escaped? false)
  (for [index 1 (# bytes)]
    (local char (string.sub bytes index index))
    (if escaped? (set escaped? false)
        (and quoted? (= char "\\")) (set escaped? true)
        (= char "\"") (set quoted? (not quoted?))
        (and (not quoted?) (= (string.sub bytes index (+ index 3)) "null"))
        (error (.. "unsupported JSON null in strict record at byte " index "; native bridge cannot preserve null"))))
  (json.loads bytes))

;; Defaults apply only to absent optional fields, never to present false values.
;; Used only at strict persisted-record decoder boundaries, not public coercing APIs.
(fn field [data key kind default]
  (assert (= (type data) :table) "persisted record must be an object")
  (local value (. data key))
  (if (= value nil) default
      (do (assert (= (type value) kind) (.. "persisted field " key " must be " kind)) value)))

(fn check-bytes [bytes format]
  (assert (or (= format "json") (= format "string")) "unsupported record format")
  (assert (or (= bytes false) (= (type bytes) :string)) "record bytes must be string or false")
  (if (= bytes false) false
      (= format "json") (J.stable-json (decode-json bytes))
      bytes))

(fn snapshot [path format decode]
  (assert (= (type decode) :function) "snapshot requires pure decoder")
  (check-bytes false format)
  (if (not (fs.exists path))
      {:path path :bytes false :value false :check false}
      (do
        (fn read-required []
          (local status (fs.stat path))
          (assert (not status.error) (tostring status.error))
          (assert status.is-file "record must be a regular file")
          (local bytes (fs.read-file path))
          (local value (decode bytes))
          (assert (= (type value) :table) "decoded record must be a table")
          {:path path :bytes bytes :value value :check (check-bytes bytes format)})
        (local (ok result) (pcall read-required))
        (assert ok (.. "record read failed at " path ": " (tostring result)))
        result)))

(fn make-change [owner address before after-bytes format phase]
  (assert (or (= phase "replacement") (= phase "incoming") (= phase "retire")) "invalid change phase")
  {:owner owner :address address :path before.path :format format :phase phase
   :before-check (check-bytes before.bytes format)
   :after-check (check-bytes after-bytes format) :after-bytes after-bytes})

;; Owning record IDs are single filename components, not filesystem paths.
(fn require-id [id]
  (assert (and (= (type id) :string) (> (# id) 0)
               (not (= id ".")) (not (= id ".."))
               (not (string.find id "[/\\:%z]"))) "invalid record id")
  id)

(fn require-array [value]
  (assert (= (type value) :table) "record array must be a table")
  (local size (# value))
  (var count 0)
  (each [index _ (pairs value)]
    (assert (and (= (type index) :number) (= index (math.floor index))
                 (>= index 1) (<= index size)) "record array must have contiguous numeric indices")
    (set count (+ count 1)))
  (assert (= count size) "record array must have contiguous numeric indices without holes")
  value)

(fn comparison-path [path]
  (var current (fs.absolute path))
  (local separator (string.sub package.config 1 1))
  (while (= (string.sub current -1) separator)
    (local parent (fs.parent current))
    ;; Keep filesystem/volume roots intact, rather than stripping their separator.
    (when (= parent current) (lua "return current"))
    (set current parent))
  current)

;; Pure native path formation/confinement, separate from ancestor IO so even a
;; filesystem/volume root can be tested without touching that root's contents.
(fn record-location [base directory id extension]
  (require-id id)
  (local path (comparison-path (fs.join-path directory (.. id extension))))
  (local root (comparison-path base))
  (local prefix (fs.join-path root ""))
  (assert (= (string.sub path 1 (# prefix)) prefix) (.. "record path escapes root: " path))
  (values path root))

(fn record-path [base directory id extension]
  (local (path root) (record-location base directory id extension))
  (var current path)
  (while (not (= current root))
    (local exists? (fs.exists current))
    (local status (fs.stat current))
    ;; exists throws on IO errors. Only its confirmed absence allows stat's
    ;; missing-path error; a dangling symlink is still an unsupported record.
    (when exists? (assert (not status.error) (.. current ": " (tostring status.error))))
    (assert (not status.is-symlink) (.. "record symlink unsupported: " current))
    (local parent (comparison-path (fs.parent current)))
    (assert (not (= parent current)) (.. "record ancestor did not reach root: " path))
    (set current parent))
  path)

(fn record-entries [directory extension]
  (local entries [])
  (fn enumerate-required []
    (when (fs.exists directory)
      (local status (fs.stat directory))
      (assert (and (not status.error) status.is-dir) "unsupported record directory")
      (each [_ entry (ipairs (fs.list-dir directory true true))]
        (assert (not entry.error) (.. entry.path ": " (tostring entry.error)))
        (when (= (string.sub entry.name (- (# extension))) extension)
          (assert entry.is-file (.. "unsupported record path: " entry.path))
          (table.insert entries entry)))))
  (local (ok result) (pcall enumerate-required))
  (assert ok (.. "record enumeration failed at " directory ": " (tostring result)))
  (table.sort entries (fn by-name [a b] (< a.name b.name)))
  entries)

(fn verify-candidate [id candidate bytes check format]
  (require-id id)
  (assert (= candidate.id id) "record id does not match persistence target")
  (assert (= (check-bytes bytes format) check) "prepared record after-check mismatch")
  candidate)

{:snapshot snapshot :check-bytes check-bytes :make-change make-change :clone clone
 :require-id require-id :record-path record-path :record-entries record-entries
 :verify-candidate verify-candidate :require-array require-array
  :decode-json decode-json :field field :record-location record-location :comparison-path comparison-path}
