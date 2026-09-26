(local tests [])
(local Temporal (require :temporal))

(fn assert-error [f message]
  (local (ok err) (pcall f))
  (assert (not ok) message)
  err)

(fn standard-instant-round-trip []
  (local instant (Temporal.standard.parse-instant "2026-09-25T08:34:56-04:00"))
  (assert (= (Temporal.standard.format-instant instant) "2026-09-25T12:34:56Z"))
  (assert-error #(Temporal.standard.parse-instant "2026-09-25T12:34:56")
                "standard instant requires explicit offset"))

(fn standard-plain-round-trip []
  (local plain (Temporal.standard.parse-plain-date-time "2026-09-25T12:34:56"))
  (assert (= (Temporal.standard.format-plain-date-time plain)
             "2026-09-25T12:34:56")))

(fn standard-zoned-round-trip []
  (local zdt (Temporal.standard.parse-zoned-date-time
               "2026-11-01T01:30:00-04:00[America/New_York]"))
  (local instant (zdt:instant))
  (assert (= (instant:to-string) "2026-11-01T05:30:00Z"))
  (assert (= (Temporal.standard.format-zoned-date-time zdt)
             "2026-11-01T01:30:00-04:00[America/New_York]"))
  (assert-error #(Temporal.standard.parse-zoned-date-time
                    "2026-11-01T01:30:00-03:00[America/New_York]")
                "mismatched offset should throw"))

(fn standard-zoned-fractional-round-trip []
  (local instant (Temporal.standard.parse-instant "2026-09-25T12:34:56.5Z"))
  (local zdt (Temporal.zoned-date-time.from-instant instant "America/New_York"))
  (local formatted (Temporal.standard.format-zoned-date-time zdt))
  (assert (= formatted "2026-09-25T08:34:56.5-04:00[America/New_York]"))
  (local reparsed (Temporal.standard.parse-zoned-date-time formatted))
  (local reparsed-instant (reparsed:instant))
  (assert (= (reparsed-instant:to-string) "2026-09-25T12:34:56.5Z"))
  (assert (= (Temporal.standard.format-zoned-date-time reparsed) formatted)))

(fn pattern-plain-date-time-round-trip []
  (local pattern (Temporal.pattern.compile "yyyy/MM/dd HH:mm:ss"))
  (local plain (Temporal.pattern.parse pattern "2026/09/25 12:34:56"
                                       {:type :plain-date-time}))
  (assert (= (plain:to-string) "2026-09-25T12:34:56"))
  (assert (= (Temporal.pattern.format pattern plain) "2026/09/25 12:34:56")))

(fn pattern-literals-and-rejections []
  (local pattern (Temporal.pattern.compile "yyyy-MM-dd'T'HH:mm:ss"))
  (local plain (Temporal.pattern.parse pattern "2026-09-25T12:34:56"
                                       {:type :plain-date-time}))
  (assert (= (plain:to-string) "2026-09-25T12:34:56"))
  (assert-error #(Temporal.pattern.compile "yyyy MMM dd")
                "unsupported pattern token should throw")
  (assert-error #(Temporal.pattern.parse pattern "2026-09-25X12:34:56"
                                        {:type :plain-date-time})
                "literal mismatch should throw"))

(table.insert tests {:name "standard instant round trip" :fn standard-instant-round-trip})
(table.insert tests {:name "standard plain round trip" :fn standard-plain-round-trip})
(table.insert tests {:name "standard zoned round trip" :fn standard-zoned-round-trip})
(table.insert tests {:name "standard zoned fractional round trip" :fn standard-zoned-fractional-round-trip})
(table.insert tests {:name "pattern plain date time round trip" :fn pattern-plain-date-time-round-trip})
(table.insert tests {:name "pattern literals and rejections" :fn pattern-literals-and-rejections})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-parsing-recurrence"
                       :tests tests})))

{:name "temporal-parsing-recurrence"
 :tests tests
 :main main}
