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

(table.insert tests {:name "standard instant round trip" :fn standard-instant-round-trip})
(table.insert tests {:name "standard plain round trip" :fn standard-plain-round-trip})
(table.insert tests {:name "standard zoned round trip" :fn standard-zoned-round-trip})
(table.insert tests {:name "standard zoned fractional round trip" :fn standard-zoned-fractional-round-trip})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-parsing-recurrence"
                       :tests tests})))

{:name "temporal-parsing-recurrence"
 :tests tests
 :main main}
