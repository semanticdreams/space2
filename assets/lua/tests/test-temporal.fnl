(local tests [])

(fn assert-error [f message]
  (local (ok err) (pcall f))
  (assert (not ok) message)
  err)

(fn temporal-module-loads []
  (local Temporal (require :temporal))
  (assert Temporal.duration)
  (assert Temporal.instant)
  (assert Temporal.plain-date-time)
  (assert Temporal.zoned-date-time)
  (assert Temporal.clock)
  (assert Temporal.tzdb))

(fn instant-parse-and-format-require-explicit-offset []
  (local Temporal (require :temporal))
  (local instant (Temporal.instant.parse "2026-09-25T08:34:56-04:00"))
  (assert (= (instant:to-string) "2026-09-25T12:34:56Z"))
  (assert-error #(Temporal.instant.parse "2026-09-25T12:34:56")
                "instant parse without offset should fail")
  (assert-error #(Temporal.instant.parse "2026-12-31T23:59:60Z")
                "leap second should fail"))

(fn duration-factories-and-instant-arithmetic []
  (local Temporal (require :temporal))
  (local base (Temporal.instant.parse "2026-09-25T12:34:56Z"))
  (local duration (Temporal.duration.from {:seconds 90 :milliseconds 500}))
  (local added (base:add duration))
  (assert (= (added:to-string) "2026-09-25T12:36:26.5Z")))

(fn plain-date-time-parses-fields []
  (local Temporal (require :temporal))
  (local plain (Temporal.plain-date-time.parse "2026-11-01T01:30:00"))
  (assert (= (plain:to-string) "2026-11-01T01:30:00"))
  (local plain-fields (plain:fields))
  (assert (= plain-fields.year 2026)))

(fn zoned-date-time-handles-new-york-overlap []
  (local Temporal (require :temporal))
  (local plain (Temporal.plain-date-time.parse "2026-11-01T01:30:00"))
  (local earliest
    (Temporal.zoned-date-time.from-plain
      plain
      "America/New_York"
      {:disambiguation :earliest}))
  (local latest
    (Temporal.zoned-date-time.from-plain
      plain
      "America/New_York"
      {:disambiguation :latest}))
  (local earliest-instant (earliest:instant))
  (local latest-instant (latest:instant))
  (assert (= (earliest-instant:to-string) "2026-11-01T05:30:00Z"))
  (assert (= (latest-instant:to-string) "2026-11-01T06:30:00Z")))

(fn zoned-date-time-rejects-gaps-by-default []
  (local Temporal (require :temporal))
  (local plain (Temporal.plain-date-time.parse "2026-11-01T01:30:00"))
  (assert-error #(Temporal.zoned-date-time.from-plain plain "America/New_York")
                "ambiguous overlap should reject by default")
  (local gap (Temporal.plain-date-time.parse "2026-03-08T02:30:00"))
  (assert-error #(Temporal.zoned-date-time.from-plain gap "America/New_York")
                "nonexistent gap should reject by default"))

(fn zoned-date-time-resolves-new-york-spring-gap []
  (local Temporal (require :temporal))
  (local gap (Temporal.plain-date-time.parse "2026-03-08T02:30:00"))
  (local gap-earliest
    (Temporal.zoned-date-time.from-plain
      gap
      "America/New_York"
      {:disambiguation :earliest}))
  (local gap-latest
    (Temporal.zoned-date-time.from-plain
      gap
      "America/New_York"
      {:disambiguation :latest}))
  (local gap-earliest-instant (gap-earliest:instant))
  (local gap-latest-instant (gap-latest:instant))
  (assert (= (gap-earliest-instant:to-string) "2026-03-08T07:00:00Z"))
  (assert (= (gap-latest-instant:to-string) "2026-03-08T06:59:59.999999999Z")))

(fn fixed-clock-returns-deterministic-instant []
  (local Temporal (require :temporal))
  (local base (Temporal.instant.parse "2026-09-25T12:34:56Z"))
  (local clock (Temporal.clock.fixed base))
  (local fixed-now-a (clock:now))
  (local fixed-now-b (clock:now))
  (assert (= (fixed-now-a:to-string) "2026-09-25T12:34:56Z"))
  (assert (= (fixed-now-b:to-string) "2026-09-25T12:34:56Z")))

(fn invalid-inputs-throw-loudly []
  (local Temporal (require :temporal))
  (local plain (Temporal.plain-date-time.parse "2026-11-01T01:30:00"))
  (assert-error #(Temporal.zoned-date-time.from-plain plain "Mars/Base")
                "invalid zone should throw")
  (local plain-zone-error
    (assert-error #(Temporal.zoned-date-time.from-plain plain 42)
                  "zone id should be a string"))
  (assert (plain-zone-error:match "zone id must be a string"))
  (local instant (Temporal.instant.parse "2026-09-25T12:34:56Z"))
  (local instant-zone-error
    (assert-error #(Temporal.zoned-date-time.from-instant instant 42)
                  "instant zone id should be a string"))
  (assert (instant-zone-error:match "zone id must be a string"))
  (local duration-field-error
    (assert-error #(Temporal.duration.from {:millisecondz 500})
                  "unknown duration field should throw"))
  (assert (duration-field-error:match "invalid temporal duration field"))
  (assert-error #(Temporal.zoned-date-time.from-plain plain "America/New_York" {:disambiguation :middle})
                "invalid disambiguation should throw"))

(table.insert tests {:name "temporal module loads" :fn temporal-module-loads})
(table.insert tests {:name "instant parse and format require explicit offset" :fn instant-parse-and-format-require-explicit-offset})
(table.insert tests {:name "duration factories and instant arithmetic" :fn duration-factories-and-instant-arithmetic})
(table.insert tests {:name "plain date time parses fields" :fn plain-date-time-parses-fields})
(table.insert tests {:name "zoned date time handles New York overlap" :fn zoned-date-time-handles-new-york-overlap})
(table.insert tests {:name "zoned date time rejects gaps by default" :fn zoned-date-time-rejects-gaps-by-default})
(table.insert tests {:name "zoned date time resolves New York spring gap" :fn zoned-date-time-resolves-new-york-spring-gap})
(table.insert tests {:name "fixed clock returns deterministic instant" :fn fixed-clock-returns-deterministic-instant})
(table.insert tests {:name "invalid inputs throw loudly" :fn invalid-inputs-throw-loudly})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal"
                       :tests tests})))

{:name "temporal"
 :tests tests
 :main main}
