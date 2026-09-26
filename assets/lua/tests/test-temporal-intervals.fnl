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
  (assert (= (elapsed:to-string) "PT1H"))
  (assert (= (Temporal.interval.format interval)
             "2026-09-25T12:00:00Z/2026-09-25T13:00:00Z")))

(fn plain-interval-parse-shift []
  (local interval (Temporal.interval.parse "2026-09-25T12:00:00/2026-09-25T13:00:00"
                                           {:type :plain-date-time}))
  (local shifted (Temporal.interval.shift interval (Temporal.duration.from {:seconds 7200})))
  (local elapsed (Temporal.interval.duration interval))
  (assert (= (Temporal.interval.format shifted)
             "2026-09-25T14:00:00/2026-09-25T15:00:00"))
  (assert (= (elapsed:to-string) "PT1H")))

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
  (assert-error #(Temporal.interval.parse "2026-09-25T12:00:00Z/PT1H" {:type :instant})
                "start/duration form should throw")
  (assert-error #(Temporal.interval.parse "2026-09-25T12:00:00Z/2026-09-25T13:00:00Z" {:kind :instant})
                "unknown option key should throw"))

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
(table.insert tests {:name "invalid intervals throw" :fn invalid-intervals-throw})
(table.insert tests {:name "repeating interval counted occurrences" :fn repeating-interval-counted-occurrences})
(table.insert tests {:name "repeating interval unbounded limit" :fn repeating-interval-unbounded-limit})
(table.insert tests {:name "repeating interval rejections" :fn repeating-interval-rejections})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-intervals" :tests tests})))

{:name "temporal-intervals" :tests tests :main main}
