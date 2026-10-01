(local fs (require :fs))
(local json (require :json))

(local dataset-id "natural-phrase-seed")
(local provider-id "space.temporal.natural-seed")
(local version "natural-phrase-seed-2026-10-track10")
(local expected-locales ["en-US" "fr-FR" "ja-JP"])
(local expected-weekday-symbols ["mo" "tu" "we" "th" "fr" "sa" "su"])
(local required-families [:relative_literals :relative_count_offsets :next_weekday :weekly_weekday_recurrence :bare_weekday_ambiguity])
(local missing-data-message "missing or malformed temporal natural phrase seed data")
(local no-assets-message "Temporal natural phrase seed requires SPACE_ASSETS_PATH or runtime assets-path")

(var cache nil)

(fn runtime-assets-path []
  (and _G.runtime _G.runtime.assets-path))

(fn asset-root []
  (local root (or (os.getenv :SPACE_ASSETS_PATH)
                  (runtime-assets-path)))
  (if (and (= (type root) :string) (> (length root) 0))
      root
      (error no-assets-message)))

(fn seed-path [file-name]
  (fs.join-path (asset-root) "temporal" "natural" "seed" file-name))

(fn fail-missing [context]
  (error (.. missing-data-message ": " context)))

(fn array-length-or-nil [value]
  (when (= (type value) :table)
    (var count 0)
    (var max-index 0)
    (each [key _value (pairs value)]
      (if (and (= (type key) :number)
               (> key 0)
               (= key (math.floor key)))
          (do
            (set count (+ count 1))
            (when (> key max-index)
              (set max-index key)))
          (set count -1)))
    (when (= count max-index)
      count)))

(fn array-of-strings? [value]
  (local count (array-length-or-nil value))
  (if (= count nil)
      false
      (do
        (var valid? true)
        (each [_ item (ipairs value)]
          (when (not (= (type item) :string))
            (set valid? false)))
        valid?)))

(fn same-string-array? [actual expected]
  (and (array-of-strings? actual)
       (= (array-length-or-nil actual) (array-length-or-nil expected))
       (do
         (var same? true)
         (each [index expected-value (ipairs expected)]
           (when (not (= (. actual index) expected-value))
             (set same? false)))
         same?)))

(fn require-field [record key expected-type context]
  (when (not (= (type record) :table))
    (fail-missing context))
  (local value (. record key))
  (when (= value nil)
    (fail-missing (.. context "." (tostring key))))
  (when (not (= (type value) expected-type))
    (fail-missing (.. context "." (tostring key))))
  value)

(fn require-schema-version! [record context]
  (when (not (= (require-field record :schema_version :number context) 1))
    (fail-missing (.. context ".schema_version"))))

(fn require-provider-version! [record context]
  (when (not (= (require-field record :provider_id :string context) provider-id))
    (fail-missing (.. context ".provider_id")))
  (when (not (= (require-field record :version :string context) version))
    (fail-missing (.. context ".version"))))

(fn validate-manifest! [manifest]
  (require-schema-version! manifest "manifest")
  (when (not (= (require-field manifest :id :string "manifest") dataset-id))
    (fail-missing "manifest.id"))
  (require-provider-version! manifest "manifest")
  (when (not (same-string-array? (require-field manifest :supported_locales :table "manifest")
                                 expected-locales))
    (error "temporal natural phrase seed supported locale mismatch"))
  (when (not (= (require-field manifest :runtime_network_fetch_allowed :boolean "manifest") false))
    (error "temporal natural phrase seed runtime network fetches must be disabled"))
  manifest)

(fn supported-locale? [locale]
  (var found? false)
  (each [_ supported (ipairs expected-locales)]
    (when (= locale supported)
      (set found? true)))
  found?)

(fn supported-weekday? [weekday]
  (var found? false)
  (each [_ symbol (ipairs expected-weekday-symbols)]
    (when (= weekday symbol)
      (set found? true)))
  found?)

(fn validate-phrase-common! [record context]
  (require-field record :phrase_id :string context))

(fn validate-relative-literal! [record context]
  (validate-phrase-common! record context)
  (require-field record :text :string context)
  (require-field record :offset_days :number context))

(fn validate-count-offset! [record context]
  (validate-phrase-common! record context)
  (require-field record :pattern :string context)
  (local unit (require-field record :unit :string context))
  (when (if (= unit "day")
            false
            (= unit "week")
            false
            true)
    (fail-missing (.. context ".unit")))
  (when (not (= (require-field record :direction :number context) 1))
    (fail-missing (.. context ".direction"))))

(fn validate-weekday-record! [record context]
  (validate-phrase-common! record context)
  (require-field record :text :string context)
  (when (not (supported-weekday? (require-field record :weekday :string context)))
    (fail-missing (.. context ".weekday"))))

(fn validate-array! [items context validator]
  (when (= (array-length-or-nil items) nil)
    (fail-missing context))
  (each [index record (ipairs items)]
    (validator record (.. context "." (tostring index)))))

(fn validate-locale-data! [locale data]
  (when (not (= (type data) :table))
    (fail-missing (.. "locales." locale)))
  (each [_ family (ipairs required-families)]
    (when (= (. data family) nil)
      (fail-missing (.. "locales." locale "." (tostring family)))))
  (each [family _value (pairs data)]
    (var expected? false)
    (each [_ required (ipairs required-families)]
      (when (= family required)
        (set expected? true)))
    (when (not expected?)
      (fail-missing (.. "locales." locale "." (tostring family)))))
  (validate-array! data.relative_literals (.. "locales." locale ".relative_literals") validate-relative-literal!)
  (validate-array! data.relative_count_offsets (.. "locales." locale ".relative_count_offsets") validate-count-offset!)
  (validate-array! data.next_weekday (.. "locales." locale ".next_weekday") validate-weekday-record!)
  (validate-array! data.weekly_weekday_recurrence (.. "locales." locale ".weekly_weekday_recurrence") validate-weekday-record!)
  (validate-array! data.bare_weekday_ambiguity (.. "locales." locale ".bare_weekday_ambiguity") validate-weekday-record!))

(fn validate-phrases! [phrases]
  (require-schema-version! phrases "phrases")
  (require-provider-version! phrases "phrases")
  (when (not (same-string-array? (require-field phrases :locale_order :table "phrases") expected-locales))
    (error "temporal natural phrase seed supported locale mismatch"))
  (when (not (same-string-array? (require-field phrases :weekday_symbols :table "phrases") expected-weekday-symbols))
    (error "temporal natural phrase seed weekday symbol mismatch"))
  (local locales (require-field phrases :locales :table "phrases"))
  (each [locale _data (pairs locales)]
    (when (not (supported-locale? locale))
      (error "temporal natural phrase seed supported locale mismatch")))
  (each [_ locale (ipairs expected-locales)]
    (validate-locale-data! locale (. locales locale)))
  phrases)

(fn read-json-file [file-name]
  (local path (seed-path file-name))
  (when (not (fs.exists path))
    (fail-missing file-name))
  (local (read-ok content-or-error) (pcall fs.read-file path))
  (when (not read-ok)
    (fail-missing (.. file-name ": " (tostring content-or-error))))
  (local (parse-ok parsed-or-error) (pcall json.loads content-or-error))
  (if parse-ok
      parsed-or-error
      (fail-missing (.. file-name ": " (tostring parsed-or-error)))))

(fn ensure-loaded []
  (when (= cache nil)
    (local manifest (validate-manifest! (read-json-file "manifest.json")))
    (local phrases (validate-phrases! (read-json-file "phrases.json")))
    (set cache {:manifest manifest
                :phrases phrases}))
  cache)

(fn deep-copy [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [key item (pairs value)]
          (tset out key (deep-copy item)))
        out)
      value))

(fn copy-array [items]
  (local out [])
  (each [_ item (ipairs items)]
    (table.insert out item))
  out)

(fn load []
  (deep-copy (ensure-loaded)))

(fn supported-locales []
  (local loaded (ensure-loaded))
  (copy-array loaded.manifest.supported_locales))

(fn locale-data [locale]
  (when (not (supported-locale? locale))
    (error (.. "unsupported temporal natural locale: " (tostring locale))))
  (local loaded (ensure-loaded))
  (deep-copy (. loaded.phrases.locales locale)))

{:load load
 :supported-locales supported-locales
 :locale-data locale-data}
