(local tests [])
(local Temporal (require :temporal))

(fn assert-error [f message]
  (local (ok err) (pcall f))
  (assert (not ok) message)
  err)

(fn period-records-parse-format []
  (local p (Temporal.period.from {:years 1 :months 2 :weeks 3 :days 4}))
  (assert (= p.kind :period))
  (assert (= (Temporal.period.format p) "P1Y2M3W4D"))
  (assert (= (Temporal.period.format (Temporal.period.parse "P0D")) "P0D"))
  (assert (= (Temporal.period.format (Temporal.period.parse "-P1M")) "-P1M"))
  (assert (= (Temporal.period.format (Temporal.period.negate p)) "-P1Y2M3W4D")))

(fn period-validation []
  (assert-error #(Temporal.period.from {:monthz 1}) "unknown period key should throw")
  (assert-error #(Temporal.period.from {:years false}) "boolean period field should throw")
  (assert-error #(Temporal.period.from {:months 1.5}) "fractional period field should throw")
  (assert-error #(Temporal.period.from {:years 1e20}) "too-large period field should throw")
  (assert-error #(Temporal.period.from {:months 1 :days -1}) "mixed signs should throw")
  (assert-error #(Temporal.period.parse "PT1H") "time period should throw")
  (assert-error #(Temporal.period.parse "P1D2M") "reordered period should throw")
  (assert-error #(Temporal.duration.from {:months 1}) "duration months should still throw"))

(fn period-plain-date-time-arithmetic []
  (local jan31 (Temporal.plain-date-time.parse "2026-01-31T10:11:12"))
  (local feb28 (Temporal.period.add-to-plain-date-time jan31 (Temporal.period.parse "P1M")))
  (assert (= (feb28:to-string) "2026-02-28T10:11:12"))
  (local leap (Temporal.plain-date-time.parse "2028-02-29T10:11:12"))
  (local next-year (Temporal.period.add-to-plain-date-time leap (Temporal.period.parse "P1Y")))
  (assert (= (next-year:to-string) "2029-02-28T10:11:12"))
  (local previous-month (Temporal.period.subtract-from-plain-date-time jan31 (Temporal.period.parse "P1M")))
  (assert (= (previous-month:to-string) "2025-12-31T10:11:12"))
  (assert-error #(Temporal.period.add-to-plain-date-time (Temporal.standard.parse-instant "2026-01-31T00:00:00Z") (Temporal.period.parse "P1M"))
                "period target must be plain date-time"))

(table.insert tests {:name "period records parse and format" :fn period-records-parse-format})
(table.insert tests {:name "period validation" :fn period-validation})
(table.insert tests {:name "period plain date time arithmetic" :fn period-plain-date-time-arithmetic})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-period"
                       :tests tests})))

{:name "temporal-period"
 :tests tests
 :main main}
