(local tests [])

(fn assert= [actual expected message]
  (assert (= actual expected)
          (.. message ": expected " (tostring expected) ", got " (tostring actual))))

(fn assert-error-contains [f fragment message]
  (local (ok err) (pcall f))
  (assert (not ok) message)
  (assert (err:match fragment)
          (.. message ": expected error containing " fragment ", got " (tostring err)))
  err)

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

(table.insert tests {:name "seed exposes supported jurisdictions defensively" :fn seed-exposes-supported-jurisdictions-defensively})
(table.insert tests {:name "seed rejects unsupported jurisdiction loudly" :fn seed-rejects-unsupported-jurisdiction-loudly})
(table.insert tests {:name "seed returns holidays for supported year" :fn seed-returns-holidays-for-supported-year})
(table.insert tests {:name "seed finds observed holiday by date" :fn seed-finds-observed-holiday-by-date})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-business-calendar"
                       :tests tests})))

{:name "temporal-business-calendar"
 :tests tests
 :main main}
