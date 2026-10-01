(local fs (require :fs))
(local json (require :json))

(local provider-id "space.temporal.cldr-seed")
(local expected-locales ["en-US" "fr-FR" "ja-JP"])
(local expected-calendars ["gregory" "buddhist" "japanese"])
(local missing-data-message "missing or malformed CLDR seed data")
(local no-assets-message "Temporal CLDR seed requires SPACE_ASSETS_PATH or runtime assets-path")

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
  (fs.join-path (asset-root) "temporal" "icu" "cldr-seed" file-name))

(fn fail-missing [context]
  (error (.. missing-data-message ": " context)))

(fn array-length-or-nil [value]
  (when (= (type value) :table)
    (var count 0)
    (var max-index 0)
    (each [key _ (pairs value)]
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

(fn require-field [record key expected-type context]
  (when (not (= (type record) :table))
    (fail-missing context))
  (local value (. record key))
  (when (= value nil)
    (fail-missing (.. context "." (tostring key))))
  (when (not (= (type value) expected-type))
    (fail-missing (.. context "." (tostring key))))
  value)

(fn require-false [value context]
  (when (not (= value false))
    (error (.. "CLDR seed runtime network fetches must be disabled: " context))))

(fn same-string-array? [actual expected]
  (and (array-of-strings? actual)
       (= (array-length-or-nil actual) (array-length-or-nil expected))
       (do
         (var same? true)
         (each [index expected-value (ipairs expected)]
           (when (not (= (. actual index) expected-value))
             (set same? false)))
         same?)))

(fn supported-locale? [locale]
  (var found? false)
  (each [_ supported (ipairs expected-locales)]
    (when (= locale supported)
      (set found? true)))
  found?)

(fn supported-calendar? [calendar]
  (var found? false)
  (each [_ supported (ipairs expected-calendars)]
    (when (= calendar supported)
      (set found? true)))
  found?)

(fn require-provider! [record context]
  (when (not (= (require-field record :provider_id :string context) provider-id))
    (fail-missing (.. context ".provider_id"))))

(fn validate-manifest! [manifest]
  (when (not (= (type manifest) :table))
    (fail-missing "manifest"))
  (require-provider! manifest "manifest")
  (require-field manifest :schema_version :number "manifest")
  (require-field manifest :id :string "manifest")
  (require-field manifest :version :string "manifest")
  (require-field manifest :files :table "manifest")
  (require-false (require-field manifest :runtime_network_fetch_allowed :boolean "manifest")
                 "manifest.runtime_network_fetch_allowed")
  (when (not (same-string-array? (require-field manifest :supported_locales :table "manifest")
                                 expected-locales))
    (error "CLDR seed supported locale mismatch"))
  (when (not (same-string-array? (require-field manifest :supported_calendars :table "manifest")
                                 expected-calendars))
    (error "CLDR seed supported calendar mismatch"))
  manifest)

(fn validate-calendars! [calendars]
  (when (not (= (type calendars) :table))
    (fail-missing "calendars"))
  (require-provider! calendars "calendars")
  (require-field calendars :schema_version :number "calendars")
  (when (not (same-string-array? (require-field calendars :calendar_order :table "calendars")
                                 expected-calendars))
    (error "CLDR seed supported calendar mismatch"))
  (local records (require-field calendars :calendars :table "calendars"))
  (each [_ calendar (ipairs expected-calendars)]
    (when (not (= (type (. records calendar)) :table))
      (fail-missing (.. "calendars.calendars." calendar))))
  calendars)

(fn validate-combination! [combination]
  (when (not (= (type combination) :table))
    (fail-missing "locales.combinations"))
  (local locale (require-field combination :locale :string "locales.combinations"))
  (local calendar (require-field combination :calendar :string "locales.combinations"))
  (when (not (supported-locale? locale))
    (error "CLDR seed supported locale mismatch"))
  (when (not (supported-calendar? calendar))
    (error "CLDR seed supported calendar mismatch"))
  (require-field combination :styles :table "locales.combinations")
  combination)

(fn validate-locales! [locales]
  (when (not (= (type locales) :table))
    (fail-missing "locales"))
  (require-provider! locales "locales")
  (require-field locales :schema_version :number "locales")
  (when (not (same-string-array? (require-field locales :locale_order :table "locales")
                                 expected-locales))
    (error "CLDR seed supported locale mismatch"))
  (local combinations (require-field locales :combinations :table "locales"))
  (when (= (array-length-or-nil combinations) nil)
    (fail-missing "locales.combinations"))
  (each [_ combination (ipairs combinations)]
    (validate-combination! combination))
  locales)

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

(fn load []
  (when (= cache nil)
    (local manifest (validate-manifest! (read-json-file "manifest.json")))
    (local locales (validate-locales! (read-json-file "locales.json")))
    (local calendars (validate-calendars! (read-json-file "calendars.json")))
    (set cache {:manifest manifest
                :locales locales
                :calendars calendars}))
  cache)

(fn sorted-copy [items]
  (local out [])
  (each [_ item (ipairs items)]
    (table.insert out item))
  (table.sort out)
  out)

(fn supported-locales []
  (local loaded (load))
  (sorted-copy loaded.manifest.supported_locales))

(fn supported-calendars []
  (local loaded (load))
  (sorted-copy loaded.manifest.supported_calendars))

(fn calendar-data [calendar]
  (local loaded (load))
  (. loaded.calendars.calendars calendar))

(fn find-combination [locale calendar]
  (local loaded (load))
  (var found nil)
  (each [_ combination (ipairs loaded.locales.combinations)]
    (when (and (= combination.locale locale)
               (= combination.calendar calendar))
      (set found combination)))
  found)

{:load load
 :supported-locales supported-locales
 :supported-calendars supported-calendars
 :find-combination find-combination
 :calendar-data calendar-data}
