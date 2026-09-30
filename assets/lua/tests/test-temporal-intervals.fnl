(local tests [])
(local Temporal (require :temporal))

(fn assert-error [f message]
  (local (ok err) (pcall f))
  (assert (not ok) message)
  err)

(fn instant-interval-basic-behavior []
  (local start (Temporal.standard.parse-instant "2026-09-25T12:00:00Z"))
  (local end (Temporal.standard.parse-instant "2026-09-25T13:00:00Z"))
  (local interval (Temporal.interval.from {:type :instant :start start :end end}))
  (assert (= interval.kind :interval))
  (assert (= interval.type :instant))
  (assert (= interval.bounds :half-open))
  (assert (Temporal.interval.contains interval start))
  (assert (not (Temporal.interval.contains interval end)))
  (local elapsed (Temporal.interval.duration interval))
  (assert (= (elapsed:compare (Temporal.duration.from {:seconds 3600})) 0))
  (assert (= (Temporal.interval.format interval)
             "2026-09-25T12:00:00Z/2026-09-25T13:00:00Z")))

(fn plain-interval-parse-shift []
  (local interval (Temporal.interval.parse "2026-09-25T12:00:00/2026-09-25T13:00:00"
                                           {:type :plain-date-time}))
  (local shifted (Temporal.interval.shift interval (Temporal.duration.from {:seconds 7200})))
  (local elapsed (Temporal.interval.duration interval))
  (assert (= (Temporal.interval.format shifted)
             "2026-09-25T14:00:00/2026-09-25T15:00:00"))
  (assert (= (elapsed:compare (Temporal.duration.from {:seconds 3600})) 0)))

(fn plain-interval-period-endpoint-forms []
  (local by-start
    (Temporal.interval.parse "2026-01-31T10:00:00/P1M" {:type :plain-date-time}))
  (assert (= (Temporal.interval.format by-start)
             "2026-01-31T10:00:00/2026-02-28T10:00:00"))

  (local by-end
    (Temporal.interval.parse "P2W/2026-02-15T09:30:00" {:type :plain-date-time}))
  (assert (= (Temporal.interval.format by-end)
             "2026-02-01T09:30:00/2026-02-15T09:30:00"))

  (assert-error #(Temporal.interval.parse "2026-02-01T00:00:00/-P1D" {:type :plain-date-time})
                "negative start/period should throw when it reverses range")
  (assert-error #(Temporal.interval.parse "-P1D/2026-02-01T00:00:00" {:type :plain-date-time})
                "negative period/end should throw when it reverses range")
  (assert-error #(Temporal.interval.parse "2026-02-01T00:00:00/P0D" {:type :plain-date-time})
                "zero period endpoint should throw")
  (assert-error #(Temporal.interval.parse "2026-02-01T00:00:00Z/P1D" {:type :instant})
                "instant start/period should throw")
  (assert-error #(Temporal.interval.parse "P1D/2026-02-01T00:00:00Z" {:type :instant})
                "instant period/end should throw")
  (assert-error #(Temporal.interval.from {:type :plain-date-time
                                          :start (Temporal.period.parse "P1D")
                                          :end (Temporal.standard.parse-plain-date-time "2026-02-01T00:00:00")})
                "interval.from should reject period start endpoints"))

(fn invalid-intervals-throw []
  (local start (Temporal.standard.parse-instant "2026-09-25T12:00:00Z"))
  (local plain-start (Temporal.standard.parse-plain-date-time "2026-09-25T12:00:00"))
  (local plain-end (Temporal.standard.parse-plain-date-time "2026-09-25T13:00:00"))
  (assert-error #(Temporal.interval.from {:type :instant :start start :end start})
                "zero-length interval should throw")
  (assert-error #(Temporal.interval.from {:type :instant :start plain-start :end plain-end})
                "endpoint type mismatch should throw")
  (assert-error #(Temporal.interval.from {:type :instant :start start})
                "missing end should throw")
  (assert-error #(Temporal.interval.parse "2026-09-25T12:00:00Z/2026-09-25T13:00:00Z" {:kind :instant})
                "unknown option key should throw"))

(fn zoned-interval-concrete-start-end []
  (local text "2026-09-25T09:00:00-04:00[America/New_York]/2026-09-25T10:00:00-04:00[America/New_York]")
  (local interval (Temporal.interval.parse text {:type :zoned-date-time}))
  (assert (= interval.type :zoned-date-time))
  (assert (= (Temporal.interval.format interval) text))
  (local elapsed (Temporal.interval.duration interval))
  (assert (= (elapsed:compare (Temporal.duration.from {:seconds 3600})) 0))
  (assert (Temporal.interval.contains interval
                                      (Temporal.standard.parse-zoned-date-time
                                        "2026-09-25T09:30:00-04:00[America/New_York]")))
  (assert-error #(Temporal.interval.parse
                   "2026-09-25T09:00:00-05:00[America/New_York]/2026-09-25T10:00:00-04:00[America/New_York]"
                   {:type :zoned-date-time})
                "zoned offset mismatch should throw")
  (assert-error #(Temporal.interval.parse
                   "2026-09-25T09:00:00-04:00[America/New_York]/2026-09-25T10:00:00-05:00[America/Chicago]"
                   {:type :zoned-date-time})
                "zoned endpoints with different zones should throw"))

(fn interval-exact-duration-endpoints []
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse "2026-09-25T12:00:00Z/PT1H" {:type :instant}))
             "2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"))
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse "PT30M/2026-09-25T13:00:00Z" {:type :instant}))
             "2026-09-25T12:30:00Z/2026-09-25T13:00:00Z"))
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse "2026-09-25T12:00:00/PT0.5S" {:type :plain-date-time}))
             "2026-09-25T12:00:00/2026-09-25T12:00:00.5"))
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse
                 "2026-03-08T01:30:00-05:00[America/New_York]/PT1H"
                 {:type :zoned-date-time}))
             "2026-03-08T01:30:00-05:00[America/New_York]/2026-03-08T03:30:00-04:00[America/New_York]"))
  (assert-error #(Temporal.interval.parse "2026-09-25T12:00:00Z/P1D" {:type :instant})
                "calendar period endpoint for instant should throw")
  (assert-error #(Temporal.interval.parse "2026-09-25T12:00:00Z/PT" {:type :instant})
                "empty exact duration should throw")
  (assert-error #(Temporal.interval.parse "2026-09-25T12:00:00Z/PT0.5H" {:type :instant})
                "fractional hours should throw")
  (assert-error #(Temporal.interval.parse "P1D/PT1H" {:type :instant})
                "two derived endpoints should throw"))

(fn zoned-calendar-period-endpoints []
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse
                 "2026-01-31T10:00:00-05:00[America/New_York]/P1M"
                 {:type :zoned-date-time}))
             "2026-01-31T10:00:00-05:00[America/New_York]/2026-02-28T10:00:00-05:00[America/New_York]"))
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse
                 "P2W/2026-02-15T09:30:00-05:00[America/New_York]"
                 {:type :zoned-date-time}))
             "2026-02-01T09:30:00-05:00[America/New_York]/2026-02-15T09:30:00-05:00[America/New_York]"))
  (assert-error #(Temporal.interval.parse
                   "2026-03-07T02:30:00-05:00[America/New_York]/P1D"
                   {:type :zoned-date-time})
                "default reject should throw for DST gap")
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse
                 "2026-03-07T02:30:00-05:00[America/New_York]/P1D"
                 {:type :zoned-date-time :disambiguation :earliest}))
             "2026-03-07T02:30:00-05:00[America/New_York]/2026-03-08T03:00:00-04:00[America/New_York]"))
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse
                 "2026-10-31T01:30:00-04:00[America/New_York]/P1D"
                 {:type :zoned-date-time :disambiguation :earliest}))
             "2026-10-31T01:30:00-04:00[America/New_York]/2026-11-01T01:30:00-04:00[America/New_York]"))
  (assert (= (Temporal.interval.format
               (Temporal.interval.parse
                 "2026-10-31T01:30:00-04:00[America/New_York]/P1D"
                 {:type :zoned-date-time :disambiguation :latest}))
             "2026-10-31T01:30:00-04:00[America/New_York]/2026-11-01T01:30:00-05:00[America/New_York]")))

(fn interval-disambiguation-option-boundaries []
  (assert-error #(Temporal.interval.parse
                   "2026-09-25T12:00:00/2026-09-25T13:00:00"
                   {:type :plain-date-time :disambiguation :earliest})
                "plain intervals should reject disambiguation")
  (assert-error #(Temporal.interval.parse
                   "2026-09-25T09:00:00-04:00[America/New_York]/PT1H"
                   {:type :zoned-date-time :disambiguation :earliest})
                "exact-duration zoned intervals should reject disambiguation")
  (assert-error #(Temporal.interval.parse
                   "2026-09-25T09:00:00-04:00[America/New_York]/P1D"
                   {:type :zoned-date-time :disambiguation :compatible})
                "unknown disambiguation value should throw"))

(fn repeating-interval-counted-occurrences []
  (local repeating (Temporal.repeating-interval.parse
                     "R3/2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"
                     {:type :instant}))
  (assert (= repeating.kind :repeating-interval))
  (assert (= repeating.count 3))
  (assert (= (Temporal.repeating-interval.format repeating)
             "R3/2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"))
  (local occ (Temporal.repeating-interval.occurrences repeating {}))
  (assert (= (# occ) 3))
  (assert (= (Temporal.interval.format (. occ 1))
             "2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"))
  (assert (= (Temporal.interval.format (. occ 2))
             "2026-09-25T13:00:00Z/2026-09-25T14:00:00Z"))
  (assert (= (Temporal.interval.format (. occ 3))
             "2026-09-25T14:00:00Z/2026-09-25T15:00:00Z")))

(fn repeating-interval-unbounded-limit []
  (local repeating (Temporal.repeating-interval.parse
                     "R/2026-09-25T12:00:00/2026-09-25T13:00:00"
                     {:type :plain-date-time}))
  (assert (= repeating.count nil))
  (assert-error #(Temporal.repeating-interval.occurrences repeating {})
                "unbounded repeating interval requires limit")
  (local occ (Temporal.repeating-interval.occurrences repeating {:limit 2}))
  (assert (= (# occ) 2))
  (assert (= (Temporal.interval.format (. occ 2))
             "2026-09-25T13:00:00/2026-09-25T14:00:00")))

(fn repeating-interval-exact-duration-step-metadata []
  (local repeating (Temporal.repeating-interval.parse
                     "R3/2026-03-08T01:30:00-05:00[America/New_York]/PT1H"
                     {:type :zoned-date-time}))
  (assert (= repeating.step-kind :exact-duration))
  (assert (= (repeating.step:compare (Temporal.duration.from {:seconds 3600})) 0))
  (local occ (Temporal.repeating-interval.occurrences repeating {}))
  (assert (= (Temporal.interval.format (. occ 1))
             "2026-03-08T01:30:00-05:00[America/New_York]/2026-03-08T03:30:00-04:00[America/New_York]"))
  (assert (= (Temporal.interval.format (. occ 2))
             "2026-03-08T03:30:00-04:00[America/New_York]/2026-03-08T04:30:00-04:00[America/New_York]"))
  (assert (= (Temporal.interval.format (. occ 3))
             "2026-03-08T04:30:00-04:00[America/New_York]/2026-03-08T05:30:00-04:00[America/New_York]")))

(fn repeating-interval-calendar-period-step-metadata []
  (local repeating (Temporal.repeating-interval.parse
                     "R3/2026-10-31T01:30:00-04:00[America/New_York]/P1D"
                     {:type :zoned-date-time :disambiguation :latest}))
  (assert (= repeating.step-kind :calendar-period))
  (assert (= (Temporal.period.format repeating.step) "P1D"))
  (local occ (Temporal.repeating-interval.occurrences repeating {:disambiguation :latest}))
  (assert (= (Temporal.interval.format (. occ 1))
             "2026-10-31T01:30:00-04:00[America/New_York]/2026-11-01T01:30:00-05:00[America/New_York]"))
  (assert (= (Temporal.interval.format (. occ 2))
             "2026-11-01T01:30:00-05:00[America/New_York]/2026-11-02T01:30:00-05:00[America/New_York]"))
  (assert (= (Temporal.interval.format (. occ 3))
             "2026-11-02T01:30:00-05:00[America/New_York]/2026-11-03T01:30:00-05:00[America/New_York]")))

(fn repeating-interval-calendar-period-default-reject []
  (local repeating (Temporal.repeating-interval.parse
                     "R2/2026-03-06T02:30:00-05:00[America/New_York]/P1D"
                     {:type :zoned-date-time}))
  (assert-error #(Temporal.repeating-interval.occurrences repeating {})
                "calendar repeating occurrences should reject DST gaps by default")
  (local occ (Temporal.repeating-interval.occurrences repeating {:disambiguation :earliest}))
  (assert (= (Temporal.interval.format (. occ 2))
             "2026-03-07T02:30:00-05:00[America/New_York]/2026-03-08T03:00:00-04:00[America/New_York]")))

(fn repeating-interval-from-step-metadata []
  (local first (Temporal.interval.parse "2026-01-31T10:00:00/P1M" {:type :plain-date-time}))
  (local repeating (Temporal.repeating-interval.from
                     {:interval first :count 2 :step-kind :calendar-period :step (Temporal.period.parse "P1M")}))
  (local occ (Temporal.repeating-interval.occurrences repeating {}))
  (assert (= (Temporal.interval.format (. occ 2))
             "2026-02-28T10:00:00/2026-03-28T10:00:00"))
  (assert-error #(Temporal.repeating-interval.from {:interval first :count 2 :step-kind :calendar-period})
                "missing calendar step should throw")
  (assert-error #(Temporal.repeating-interval.occurrences repeating {:disambiguation :compatible})
                "invalid occurrence disambiguation should throw"))

(fn repeating-interval-rejections []
  (assert-error #(Temporal.repeating-interval.parse
                   "R0/2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"
                   {:type :instant})
                "R0 should throw")
  (assert-error #(Temporal.repeating-interval.parse
                   "RX/2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"
                   {:type :instant})
                "malformed repeat prefix should throw")
  (local repeating (Temporal.repeating-interval.parse
                     "R3/2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"
                     {:type :instant}))
  (assert-error #(Temporal.repeating-interval.from {:interval repeating.interval :count math.huge})
                "math.huge count should throw")
  (assert-error #(Temporal.repeating-interval.occurrences repeating {:limt 2})
                "unknown occurrence option should throw")
  (assert-error #(Temporal.repeating-interval.occurrences repeating {:limit math.huge})
                "math.huge limit should throw")
  (assert (= (# (Temporal.repeating-interval.occurrences repeating {:limit 2})) 2)))

(table.insert tests {:name "instant interval basic behavior" :fn instant-interval-basic-behavior})
(table.insert tests {:name "plain interval parse shift" :fn plain-interval-parse-shift})
(table.insert tests {:name "plain interval period endpoint forms" :fn plain-interval-period-endpoint-forms})
(table.insert tests {:name "invalid intervals throw" :fn invalid-intervals-throw})
(table.insert tests {:name "zoned interval concrete start end" :fn zoned-interval-concrete-start-end})
(table.insert tests {:name "interval exact duration endpoints" :fn interval-exact-duration-endpoints})
(table.insert tests {:name "zoned calendar period endpoints" :fn zoned-calendar-period-endpoints})
(table.insert tests {:name "interval disambiguation option boundaries" :fn interval-disambiguation-option-boundaries})
(table.insert tests {:name "repeating interval counted occurrences" :fn repeating-interval-counted-occurrences})
(table.insert tests {:name "repeating interval unbounded limit" :fn repeating-interval-unbounded-limit})
(table.insert tests {:name "repeating interval exact duration step metadata" :fn repeating-interval-exact-duration-step-metadata})
(table.insert tests {:name "repeating interval calendar period step metadata" :fn repeating-interval-calendar-period-step-metadata})
(table.insert tests {:name "repeating interval calendar period default reject" :fn repeating-interval-calendar-period-default-reject})
(table.insert tests {:name "repeating interval from step metadata" :fn repeating-interval-from-step-metadata})
(table.insert tests {:name "repeating interval rejections" :fn repeating-interval-rejections})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-intervals" :tests tests})))

{:name "temporal-intervals" :tests tests :main main}
