(local tests [])
(local fs (require :fs))
(local json (require :json))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "temporal-business-calendar"))

(fn assert= [actual expected message]
  (assert (= actual expected)
          (.. message ": expected " (tostring expected) ", got " (tostring actual))))

(fn assert-error-contains [f fragment message]
  (local (ok err) (pcall f))
  (assert (not ok) message)
  (assert (err:match fragment)
           (.. message ": expected error containing " fragment ", got " (tostring err)))
  err)

(fn with-restored-app-fields [keys f]
  (local snapshot {})
  (each [_ key (ipairs keys)]
    (local parts [])
    (each [seg (key:gmatch "[^%.]+")]
      (table.insert parts seg))
    (var src _G)
    (var all-exist true)
    (for [i 1 (- (length parts) 1)]
      (set src (. src (. parts i)))
      (when (= nil src)
        (set all-exist false)
        (lua :break)))
    (tset snapshot key (if all-exist
                           (. src (. parts (length parts)))
                           nil)))
  (local (ok result) (pcall f))
  (each [_ key (ipairs keys)]
    (local parts [])
    (each [seg (key:gmatch "[^%.]+")]
      (table.insert parts seg))
    (var dst _G)
    (var all-exist true)
    (for [i 1 (- (length parts) 1)]
      (set dst (. dst (. parts i)))
      (when (= nil dst)
        (set all-exist false)
        (lua :break)))
    (when all-exist
      (tset dst (. parts (length parts)) (. snapshot key))))
  (if ok
      result
      (error result)))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "seed-" (os.time) "-" temp-counter)))

(fn seed-record [observed-date]
  {:date "2026-01-01"
   :id "new-years-day"
   :name "New Year's Day"
   :observed false
   :observed_date observed-date})

(fn seed-holidays [opts]
  (local years {})
  (local observed-date (if opts.observed-date
                           opts.observed-date
                           "2026-01-01"))
  (tset years "2026" [(seed-record observed-date)])
  (tset years "2027" [{:date "2027-01-01"
                        :id "new-years-day"
                        :name "New Year's Day"
                        :observed false
                        :observed_date "2027-01-01"}])
  (when opts.extra-year?
    (tset years "2028" []))
  {:schema_version 1
   :provider_id "space.temporal.us-federal-holidays"
   :year_start 2026
   :year_end 2027
   :jurisdiction_order ["US-FED"]
   :weekend_iso_weekdays [6 7]
   :jurisdictions {"US-FED" {:name "United States federal holidays"
                              :years years}}})

(fn write-seed-fixture [root opts]
  (local seed-dir (fs.join-path root "temporal" "holidays" "us-federal-seed"))
  (fs.create-dirs seed-dir)
  (fs.write-file (fs.join-path seed-dir "manifest.json")
                 (json.dumps {:schema_version 1
                              :id "us-federal-holidays-seed"
                              :provider_id "space.temporal.us-federal-holidays"
                              :supported_jurisdictions ["US-FED"]
                              :year_start 2026
                              :year_end 2027
                              :runtime_network_fetch_allowed false}))
  (fs.write-file (fs.join-path seed-dir "holidays.json")
                 (json.dumps (seed-holidays opts))))

(fn with-temp-seed [opts f]
  (local root (make-temp-dir))
  (when (fs.exists root)
    (fs.remove-all root))
  (write-seed-fixture root opts)
  (with-restored-app-fields ["package.loaded.temporal/holiday-seed"]
    (fn []
      (local original-getenv os.getenv)
      (fn temporary-getenv [name]
        (if (= name "SPACE_ASSETS_PATH")
            root
            (original-getenv name)))
      (set os.getenv temporary-getenv)
      (tset package.loaded "temporal/holiday-seed" nil)
      (local (ok result) (pcall f))
      (set os.getenv original-getenv)
      (fs.remove-all root)
      (if ok
          result
          (error result)))))

(fn load-holiday-seed []
  (local seed (require :temporal/holiday-seed))
  (seed.load))

(fn assert-extra-year-load-rejected []
  (assert-error-contains load-holiday-seed
                         "unsupported temporal holiday year"
                         "extra year buckets should fail loudly"))

(fn assert-out-of-bucket-load-rejected []
  (assert-error-contains load-holiday-seed
                         "observed date outside temporal holiday year"
                         "out-of-bucket observed dates should fail loudly"))

(fn seed-exposes-supported-jurisdictions-defensively []
  (local seed (require :temporal/holiday-seed))
  (local jurisdictions (seed.supported-jurisdictions))
  (assert= (length jurisdictions) 1 "seed should expose exactly one jurisdiction")
  (assert= (. jurisdictions 1) "US-FED" "seed jurisdiction should be US-FED")
  (tset jurisdictions 1 "mutated")
  (assert= (. (seed.supported-jurisdictions) 1) "US-FED" "supported jurisdictions should be defensive copies"))

(fn seed-rejects-unsupported-jurisdiction-loudly []
  (local seed (require :temporal/holiday-seed))
  (assert-error-contains #(seed.jurisdiction-data "CA-FED")
                         "unsupported temporal holiday jurisdiction"
                         "unsupported jurisdiction data should fail loudly")
  (assert-error-contains #(seed.holidays-for-year "CA-FED" 2026)
                         "unsupported temporal holiday jurisdiction"
                         "unsupported jurisdiction year lookup should fail loudly")
  (assert-error-contains #(seed.holiday-on-date "CA-FED" "2026-01-01")
                         "unsupported temporal holiday jurisdiction"
                         "unsupported jurisdiction date lookup should fail loudly"))

(fn seed-returns-holidays-for-supported-year []
  (local seed (require :temporal/holiday-seed))
  (local holidays (seed.holidays-for-year "US-FED" 2026))
  (assert= (length holidays) 11 "2026 should have federal observed holiday records")
  (local first (. holidays 1))
  (assert= first.jurisdiction "US-FED" "holiday record should include jurisdiction")
  (assert= first.year 2026 "holiday record should include observed year")
  (assert= first.id "new-years-day" "first 2026 holiday id should match seed")
  (assert= first.name "New Year's Day" "first 2026 holiday name should match seed")
  (assert= first.date "2026-01-01" "first 2026 statutory date should match seed")
  (assert= first.observed-date "2026-01-01" "first 2026 observed date should match seed")
  (assert= first.observed? false "first 2026 holiday should not be shifted")
  (tset first :id "mutated")
  (assert= (. (seed.holidays-for-year "US-FED" 2026) 1 :id)
           "new-years-day"
           "holiday records should be defensive copies"))

(fn seed-finds-observed-holiday-by-date []
  (local seed (require :temporal/holiday-seed))
  (local holiday (seed.holiday-on-date "US-FED" "2026-07-03"))
  (assert holiday "observed Independence Day should be found")
  (assert= holiday.id "independence-day" "observed holiday id should match seed")
  (assert= holiday.date "2026-07-04" "statutory date should remain July 4")
  (assert= holiday.observed-date "2026-07-03" "observed date should be July 3")
  (assert= holiday.observed? true "observed flag should be true")
  (tset holiday :id "mutated")
  (local holiday-again (seed.holiday-on-date "US-FED" "2026-07-03"))
  (assert= holiday-again.id "independence-day" "holiday lookup should return defensive copies"))

(fn seed-rejects-extra-supported-year-buckets []
  (with-temp-seed {:extra-year? true}
    assert-extra-year-load-rejected))

(fn seed-rejects-observed-dates-outside-year-bucket []
  (with-temp-seed {:observed-date "2028-01-01"}
    assert-out-of-bucket-load-rejected))

(table.insert tests {:name "seed exposes supported jurisdictions defensively" :fn seed-exposes-supported-jurisdictions-defensively})
(table.insert tests {:name "seed rejects unsupported jurisdiction loudly" :fn seed-rejects-unsupported-jurisdiction-loudly})
(table.insert tests {:name "seed returns holidays for supported year" :fn seed-returns-holidays-for-supported-year})
(table.insert tests {:name "seed finds observed holiday by date" :fn seed-finds-observed-holiday-by-date})
(table.insert tests {:name "seed rejects extra supported year buckets" :fn seed-rejects-extra-supported-year-buckets})
(table.insert tests {:name "seed rejects observed dates outside year bucket" :fn seed-rejects-observed-dates-outside-year-bucket})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-business-calendar"
                       :tests tests})))

{:name "temporal-business-calendar"
 :tests tests
 :main main}
