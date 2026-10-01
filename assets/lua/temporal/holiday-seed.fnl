(local fs (require :fs))
(local json (require :json))

(local dataset-id "us-federal-holidays-seed")
(local provider-id "space.temporal.us-federal-holidays")
(local expected-jurisdictions ["US-FED"])
(local expected-year-start 2026)
(local expected-year-end 2027)
(local expected-weekend-iso-weekdays [6 7])
(local missing-data-message "missing or malformed temporal holiday seed data")
(local no-assets-message "Temporal holiday seed requires SPACE_ASSETS_PATH or runtime assets-path")

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
  (fs.join-path (asset-root) "temporal" "holidays" "us-federal-seed" file-name))

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

(fn array-of-numbers? [value]
  (local count (array-length-or-nil value))
  (if (= count nil)
      false
      (do
        (var valid? true)
        (each [_ item (ipairs value)]
          (when (not (= (type item) :number))
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
    (error (.. "temporal holiday seed runtime network fetches must be disabled: " context))))

(fn same-array? [actual expected]
  (and (= (array-length-or-nil actual) (array-length-or-nil expected))
       (do
         (var same? true)
         (each [index expected-value (ipairs expected)]
           (when (not (= (. actual index) expected-value))
             (set same? false)))
         same?)))

(fn same-string-array? [actual expected]
  (and (array-of-strings? actual)
       (same-array? actual expected)))

(fn same-number-array? [actual expected]
  (and (array-of-numbers? actual)
       (same-array? actual expected)))

(fn supported-jurisdiction? [jurisdiction]
  (var found? false)
  (each [_ supported (ipairs expected-jurisdictions)]
    (when (= jurisdiction supported)
      (set found? true)))
  found?)

(fn supported-year? [year]
  (and (= (type year) :number)
       (= year (math.floor year))
       (>= year expected-year-start)
       (<= year expected-year-end)))

(fn supported-year-key? [year-key]
  (var found? false)
  (each [_ year (ipairs [expected-year-start expected-year-end])]
    (when (= year-key (tostring year))
      (set found? true)))
  found?)

(fn require-provider! [record context]
  (when (not (= (require-field record :provider_id :string context) provider-id))
    (fail-missing (.. context ".provider_id"))))

(fn require-schema-version! [record context]
  (when (not (= (require-field record :schema_version :number context) 1))
    (fail-missing (.. context ".schema_version"))))

(fn validate-year-range! [record context]
  (when (not (= (require-field record :year_start :number context) expected-year-start))
    (fail-missing (.. context ".year_start")))
  (when (not (= (require-field record :year_end :number context) expected-year-end))
    (fail-missing (.. context ".year_end"))))

(fn validate-manifest! [manifest]
  (when (not (= (type manifest) :table))
    (fail-missing "manifest"))
  (require-schema-version! manifest "manifest")
  (when (not (= (require-field manifest :id :string "manifest") dataset-id))
    (fail-missing "manifest.id"))
  (require-provider! manifest "manifest")
  (when (not (same-string-array? (require-field manifest :supported_jurisdictions :table "manifest")
                                 expected-jurisdictions))
    (error "temporal holiday seed supported jurisdiction mismatch"))
  (validate-year-range! manifest "manifest")
  (require-false (require-field manifest :runtime_network_fetch_allowed :boolean "manifest")
                 "manifest.runtime_network_fetch_allowed")
  manifest)

(fn valid-iso-date? [value]
  (and (= (type value) :string)
       (not (= (value:match "^%d%d%d%d%-%d%d%-%d%d$") nil))))

(fn observed-date-in-year? [observed-date year]
  (= (observed-date:sub 1 4) (tostring year)))

(fn validate-record! [record year context]
  (when (not (= (type record) :table))
    (fail-missing context))
  (require-field record :id :string context)
  (require-field record :name :string context)
  (local date (require-field record :date :string context))
  (local observed-date (require-field record :observed_date :string context))
  (require-field record :observed :boolean context)
  (when (not (valid-iso-date? date))
    (fail-missing (.. context ".date")))
  (when (not (valid-iso-date? observed-date))
    (fail-missing (.. context ".observed_date")))
  (when (not (observed-date-in-year? observed-date year))
    (error "observed date outside temporal holiday year"))
  record)

(fn validate-year-records! [records year context]
  (when (= (array-length-or-nil records) nil)
    (fail-missing context))
  (local observed-dates {})
  (each [index record (ipairs records)]
    (validate-record! record year (.. context "." (tostring index)))
    (when (. observed-dates record.observed_date)
      (error "temporal holiday seed duplicate observed date"))
    (tset observed-dates record.observed_date true)))

(fn validate-year-keys! [years context]
  (each [year-key _ (pairs years)]
    (when (not (supported-year-key? year-key))
      (error "unsupported temporal holiday year")))
  (each [_ year (ipairs [expected-year-start expected-year-end])]
    (local year-key (tostring year))
    (when (= (. years year-key) nil)
      (fail-missing (.. context "." year-key)))))

(fn validate-holidays! [holidays]
  (when (not (= (type holidays) :table))
    (fail-missing "holidays"))
  (require-schema-version! holidays "holidays")
  (require-provider! holidays "holidays")
  (validate-year-range! holidays "holidays")
  (when (not (same-string-array? (require-field holidays :jurisdiction_order :table "holidays")
                                 expected-jurisdictions))
    (error "temporal holiday seed supported jurisdiction mismatch"))
  (when (not (same-number-array? (require-field holidays :weekend_iso_weekdays :table "holidays")
                                 expected-weekend-iso-weekdays))
    (error "temporal holiday seed weekend policy mismatch"))
  (local jurisdictions (require-field holidays :jurisdictions :table "holidays"))
  (each [jurisdiction _ (pairs jurisdictions)]
    (when (not (supported-jurisdiction? jurisdiction))
      (error "temporal holiday seed supported jurisdiction mismatch")))
  (each [_ jurisdiction (ipairs expected-jurisdictions)]
    (local data (. jurisdictions jurisdiction))
    (when (not (= (type data) :table))
      (fail-missing (.. "holidays.jurisdictions." jurisdiction)))
    (require-field data :name :string (.. "holidays.jurisdictions." jurisdiction))
    (local years (require-field data :years :table (.. "holidays.jurisdictions." jurisdiction)))
    (validate-year-keys! years (.. "holidays.jurisdictions." jurisdiction ".years"))
    (each [_ year (ipairs [expected-year-start expected-year-end])]
      (local year-key (tostring year))
      (validate-year-records! (. years year-key)
                              year
                              (.. "holidays.jurisdictions." jurisdiction ".years." year-key))))
  holidays)

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
    (local holidays (validate-holidays! (read-json-file "holidays.json")))
    (set cache {:manifest manifest
                :holidays holidays}))
  cache)

(fn deep-copy [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [key item (pairs value)]
          (tset out key (deep-copy item)))
        out)
      value))

(fn load []
  (deep-copy (ensure-loaded)))

(fn copy-array [items]
  (local out [])
  (each [_ item (ipairs items)]
    (table.insert out item))
  out)

(fn copy-holiday-record [jurisdiction year record]
  {:jurisdiction jurisdiction
   :year year
   :id record.id
   :name record.name
   :date record.date
   :observed-date record.observed_date
   :observed? record.observed})

(fn require-supported-jurisdiction! [jurisdiction]
  (when (not (supported-jurisdiction? jurisdiction))
    (error (.. "unsupported temporal holiday jurisdiction: " (tostring jurisdiction)))))

(fn require-supported-year! [year]
  (when (not (supported-year? year))
    (error (.. "unsupported temporal holiday year: " (tostring year)))))

(fn supported-jurisdictions []
  (local loaded (ensure-loaded))
  (copy-array loaded.manifest.supported_jurisdictions))

(fn raw-jurisdiction-data [jurisdiction]
  (local loaded (ensure-loaded))
  (. loaded.holidays.jurisdictions jurisdiction))

(fn holidays-for-year [jurisdiction year]
  (require-supported-jurisdiction! jurisdiction)
  (require-supported-year! year)
  (local data (raw-jurisdiction-data jurisdiction))
  (local records (. data.years (tostring year)))
  (local out [])
  (each [_ record (ipairs records)]
    (table.insert out (copy-holiday-record jurisdiction year record)))
  out)

(fn jurisdiction-data [jurisdiction]
  (require-supported-jurisdiction! jurisdiction)
  (local data (raw-jurisdiction-data jurisdiction))
  (local years {})
  (each [_ year (ipairs [expected-year-start expected-year-end])]
    (tset years (tostring year) (holidays-for-year jurisdiction year)))
  {:jurisdiction jurisdiction
   :name data.name
   :years years})

(fn holiday-on-date [jurisdiction iso-date]
  (require-supported-jurisdiction! jurisdiction)
  (when (not (valid-iso-date? iso-date))
    (error (.. "invalid temporal holiday ISO date: " (tostring iso-date))))
  (local loaded (ensure-loaded))
  (var found nil)
  (each [_ year (ipairs [expected-year-start expected-year-end])]
    (local records (. loaded.holidays.jurisdictions jurisdiction :years (tostring year)))
    (each [_ record (ipairs records)]
      (when (= record.observed_date iso-date)
        (set found (copy-holiday-record jurisdiction year record)))))
  found)

{:load load
 :supported-jurisdictions supported-jurisdictions
 :jurisdiction-data jurisdiction-data
 :holidays-for-year holidays-for-year
 :holiday-on-date holiday-on-date}
