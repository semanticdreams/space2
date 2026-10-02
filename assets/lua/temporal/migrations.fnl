(local core (require :temporal-core))
(local fs (require :fs))
(local json (require :json))
(local JsonUtils (require :json-utils))

(local allowed-option-keys
  {:schema-id true
   :field-path true
   :file-path true
   :optional? true
   :dry-run? true})

(fn option-table [options]
  (if (= options nil)
      {}
      (do
        (assert (= (type options) :table) "temporal migration options must be a table")
        options)))

(fn validate-options [options]
  (local opts (option-table options))
  (each [key _value (pairs opts)]
    (when (not (. allowed-option-keys key))
      (error (.. "temporal migration unknown option: " (tostring key)))))
  opts)

(fn context-message [message options]
  (local opts (validate-options options))
  (local parts ["temporal migration" message])
  (when opts.schema-id
    (table.insert parts (.. "schema=" (tostring opts.schema-id))))
  (when opts.field-path
    (table.insert parts (.. "field=" (tostring opts.field-path))))
  (when opts.file-path
    (table.insert parts (.. "file=" (tostring opts.file-path))))
  (table.concat parts " "))

(fn fail [message options]
  (error (context-message message options)))

(fn integer? [value]
  (and (= (type value) :number)
       (= value (math.floor value))))

(fn to-string-method [value]
  value.to-string)

(fn instant-like? [value]
  (if (= value nil)
      false
      (= (type value) :number)
      false
      (= (type value) :string)
      false
      (= (type value) :boolean)
      false
      (do
        (local (ok method) (pcall to-string-method value))
        (and ok (= (type method) :function)))))

(fn epoch-seconds [instant]
  (local value (. instant :epoch-seconds))
  (if (= (type value) :function)
      (value instant)
      value))

(fn timestamp->instant [value options]
  (local opts (validate-options options))
  (if (= value nil)
      (if opts.optional?
          nil
          (fail "missing required timestamp" opts))
      (= (type value) :number)
      (if (integer? value)
          (core.instant.from-unix value)
          (fail "timestamp must be integer Unix epoch seconds" opts))
      (= (type value) :string)
      (do
        (local (ok parsed-or-error) (pcall core.instant.parse value))
        (if ok
            parsed-or-error
            (fail (.. "malformed timestamp string: " (tostring parsed-or-error)) opts)))
      (instant-like? value)
      value
      (fail (.. "unsupported timestamp value type: " (type value)) opts)))

(fn timestamp->epoch-seconds [value options]
  (local instant (timestamp->instant value options))
  (when instant
    (epoch-seconds instant)))

(fn instant->timestamp [value options]
  (local opts (validate-options options))
  (if (= value nil)
      (if opts.optional?
          nil
          (fail "missing required timestamp" opts))
      (instant-like? value)
      (value:to-string)
      (do
        (local instant (timestamp->instant value opts))
        (when instant
          (instant:to-string)))))

(fn deep-copy [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [key item (pairs value)]
          (tset out key (deep-copy item)))
        out)
      value))

(fn object-root? [value]
  (and (= (type value) :table)
       (= (length value) 0)))

(fn segment->string [segment]
  (tostring segment))

(fn extend-path [base segment]
  (if (= base "")
      (segment->string segment)
      (.. base "." (segment->string segment))))

(fn extend-array-path [base index]
  (.. base "[" index "]"))

(fn path-options [base-options schema field-path optional?]
  {:schema-id schema.id
   :field-path field-path
   :file-path base-options.file-path
   :optional? optional?})

(fn require-container [value field-path base-options schema]
  (when (not (= (type value) :table))
    (fail "timestamp container must be an object" (path-options base-options schema field-path false))))

(fn convert-leaf! [node key field-path schema field base-options]
  (require-container node field-path base-options schema)
  (local old-value (. node key))
  (local new-value (instant->timestamp old-value (path-options base-options schema field-path field.optional?)))
  (if (= new-value old-value)
      0
      (do
        (tset node key new-value)
        1)))

(fn apply-path! [node path index field-path schema field base-options]
  (local segment (. path index))
  (local last? (= index (length path)))
  (if (= segment "*")
      (do
        (if (= node nil)
            0
            (do
              (require-container node field-path base-options schema)
              (var count 0)
              (each [key child (pairs node)]
                (set count (+ count (apply-path! child path (+ index 1) (extend-path field-path key) schema field base-options))))
              count)))
      (= segment "[]")
      (do
        (if (= node nil)
            0
            (do
              (require-container node field-path base-options schema)
              (var count 0)
              (each [array-index child (ipairs node)]
                (set count (+ count (apply-path! child path (+ index 1) (extend-array-path field-path array-index) schema field base-options))))
              count)))
      last?
      (convert-leaf! node segment (extend-path field-path segment) schema field base-options)
      (do
        (require-container node field-path base-options schema)
        (local child (. node segment))
        (if (= child nil)
            0
            (apply-path! child path (+ index 1) (extend-path field-path segment) schema field base-options)))))

(fn migrate-json-record [record schema options]
  (local working (deep-copy record))
  (var conversions 0)
  (each [_ field (ipairs schema.fields)]
    (set conversions (+ conversions (apply-path! working field.path 1 "" schema field options))))
  (values working conversions))

(fn read-json-file [path context-options]
  (local (read-ok content-or-error) (pcall fs.read-file path))
  (when (not read-ok)
    (fail (.. "failed to read JSON: " (tostring content-or-error)) context-options))
  (local (parse-ok parsed-or-error) (pcall json.loads content-or-error))
  (when (not parse-ok)
    (fail (.. "failed to parse JSON: " (tostring parsed-or-error)) context-options))
  parsed-or-error)

(fn migrate-json-file! [path schema options]
  (assert path "temporal migration requires a file path")
  (assert schema "temporal migration requires a schema")
  (local opts (validate-options options))
  (local file-options {:file-path path :dry-run? opts.dry-run?})
  (local record (read-json-file path {:schema-id schema.id :field-path "$" :file-path path}))
  (when (not (object-root? record))
    (fail "JSON root must be an object" {:schema-id schema.id :file-path path :field-path "$"}))
  (local (migrated conversions) (migrate-json-record record schema file-options))
  (local changed? (> conversions 0))
  (when (and changed? (not opts.dry-run?))
    (JsonUtils.write-json! path migrated))
  {:file-path path
   :schema-id schema.id
   :changed? changed?
   :written? (and changed? (not opts.dry-run?))
   :dry-run? opts.dry-run?
   :conversions conversions})

(fn sorted-json-files [root]
  (local files [])
  (when (and (fs.exists root) fs.list-dir)
    (each [_ entry (ipairs (fs.list-dir root false))]
      (when (and entry.is-file (string.match entry.name "%.json$"))
        (table.insert files entry.path))))
  (table.sort files)
  files)

(fn migrate-json-tree! [root schema options]
  (local opts (validate-options options))
  (local results [])
  (local summary {:root root
                  :schema-id schema.id
                  :files 0
                  :changed-files 0
                  :conversions 0
                  :errors 0
                  :results results})
  (each [_ path (ipairs (sorted-json-files root))]
    (set summary.files (+ summary.files 1))
    (local (ok result-or-error) (pcall migrate-json-file! path schema opts))
    (if ok
        (do
          (table.insert results result-or-error)
          (when result-or-error.changed?
            (set summary.changed-files (+ summary.changed-files 1)))
          (set summary.conversions (+ summary.conversions result-or-error.conversions)))
        (do
          (set summary.errors (+ summary.errors 1))
          (table.insert results {:file-path path :error (tostring result-or-error)}))))
  summary)

(local schemas
  {:workflow-definition {:id :workflow-definition
                         :fields [{:path ["created-at"]}
                                  {:path ["updated-at"]}]}
   :workflow-run {:id :workflow-run
                  :fields [{:path ["created-at"]}
                           {:path ["started-at"] :optional? true}
                           {:path ["finished-at"] :optional? true}
                           {:path ["steps" "*" "started-at"] :optional? true}
                           {:path ["steps" "*" "finished-at"] :optional? true}
                           {:path ["events" "[]" "created-at"]}]}})

{:timestamp->instant timestamp->instant
 :timestamp->epoch-seconds timestamp->epoch-seconds
 :instant->timestamp instant->timestamp
 :migrate-json-file! migrate-json-file!
 :migrate-json-tree! migrate-json-tree!
 :schemas schemas}
