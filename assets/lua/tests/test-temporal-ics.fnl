(local tests [])
(local grammar (require :temporal/ics/grammar))
(local value (require :temporal/ics/value))
(local Temporal (require :temporal))

(local successful-fixtures
  ["single-utc" "single-floating" "single-zoned" "single-all-day"
   "multi-day-all-day" "timed-duration" "all-day-duration" "weekly-rrule"
   "rrule-rdate-exdate" "exrule" "utc-until" "override"
   "cancelled-occurrence" "cancelled-master" "folded-escaped"])

(fn assert= [actual expected message]
  (assert (= actual expected) (or message (.. "expected " (tostring expected) ", got " (tostring actual)))))

(fn assert-error [f message]
  (local (ok err) (pcall f))
  (assert (not ok) message)
  err)

(fn assert-error-contains [f fragment message]
  (local err (assert-error f message))
  (assert (tostring err):find fragment 1 true)
  err)

(fn assert-no-param [params key]
  (assert (= nil (. params key)) (.. "expected no " key " parameter")))

(fn assert-duration-seconds [duration seconds]
  (assert= (duration:compare (Temporal.duration.from-seconds seconds)) 0
           (.. "expected duration of " (tostring seconds) " seconds")))

(fn fixture-path [name]
  (local root (os.getenv "SPACE_ASSETS_PATH"))
  (assert root "SPACE_ASSETS_PATH must be set for temporal ICS fixture tests")
  (.. root "/lua/tests/data/temporal/ics/" name ".ics"))

(fn read-fixture [name]
  (local path (fixture-path name))
  (local file (assert (io.open path "rb") (.. "failed to open fixture: " path)))
  (local text (file:read "*a"))
  (file:close)
  text)

(fn grammar-unfolds-crlf-and-lf-lines []
  (local crlf-lines (grammar.unfold-lines "SUMMARY:Alpha\r\n beta\r\nDTSTART:20261001T090000\r\n"))
  (assert= (# crlf-lines) 2 "CRLF input should produce two unfolded lines")
  (assert= (. crlf-lines 1) "SUMMARY:Alphabeta")
  (assert= (. crlf-lines 2) "DTSTART:20261001T090000")
  (local lf-lines (grammar.unfold-lines "SUMMARY:Alpha\n beta\nDTSTART:20261001T090000\n"))
  (assert= (# lf-lines) 2 "LF input should produce two unfolded lines")
  (assert= (. lf-lines 1) "SUMMARY:Alphabeta")
  (assert= (. lf-lines 2) "DTSTART:20261001T090000"))

(fn grammar-parses-names-params-and-values []
  (local dtstart (grammar.parse-content-line "DTSTART;TZID=America/New_York:20261001T090000" 7))
  (assert= dtstart.kind :temporal-ics-content-line)
  (assert= dtstart.name "DTSTART")
  (assert= dtstart.params.TZID "America/New_York")
  (assert= dtstart.value "20261001T090000")
  (assert= dtstart.source-order 7)
  (local summary (grammar.parse-content-line "SUMMARY:Review\\, plan\\; ship\\\\done\\nNext" 8))
  (assert= summary.name "SUMMARY")
  (assert= summary.value "Review, plan; ship\\done\nNext"))

(fn grammar-rejects-malformed-lines-and-escapes []
  (assert-error-contains #(grammar.parse-content-line "SUMMARY no colon" 1)
                         "content line"
                         "missing colon should mention content line")
  (assert-error-contains #(grammar.parse-content-line "BAD NAME:value" 1)
                         "property"
                         "invalid property name should mention property")
  (assert-error-contains #(grammar.unescape-text "bad\\q")
                         "escape"
                         "unknown escape should mention escape")
  (assert-error-contains #(grammar.unescape-text "bad\\")
                         "escape"
                         "trailing backslash should mention escape"))

(fn grammar-emits-folded-content-lines []
  (local escaped (grammar.emit-content-line "SUMMARY" {} "Review, plan; ship\\done\nNext" {:line-ending :lf}))
  (assert= escaped "SUMMARY:Review\\, plan\\; ship\\\\done\\nNext")
  (local long-description (string.rep "a" 90))
  (local folded (grammar.emit-content-line "DESCRIPTION" {} long-description))
  (assert (folded:find "\r\n " 1 true))
  (assert (= (folded:sub 1 12) "DESCRIPTION:")))

(fn value-parses-date-time-modes []
  (local date (value.parse-date-time Temporal {:VALUE "DATE"} "20261001"))
  (assert= date.kind :temporal-ics-date-time)
  (assert= date.value-type :date)
  (assert= date.date.year 2026)
  (assert= date.date.month 10)
  (assert= date.date.day 1)
  (local floating (value.parse-date-time Temporal {} "20261001T090000"))
  (assert= floating.value-type :date-time)
  (assert= floating.time-mode :floating)
  (assert= (floating.plain:to-string) "2026-10-01T09:00:00")
  (local utc (value.parse-date-time Temporal {} "20261001T130000Z"))
  (assert= utc.value-type :date-time)
  (assert= utc.time-mode :utc)
  (assert= (utc.instant:to-string) "2026-10-01T13:00:00Z")
  (local zoned (value.parse-date-time Temporal {:TZID "America/New_York"} "20261001T090000"))
  (assert= zoned.value-type :date-time)
  (assert= zoned.time-mode :zoned)
  (assert= zoned.zone-id "America/New_York")
  (assert= (zoned.plain:to-string) "2026-10-01T09:00:00"))

(fn value-formats-date-time-modes []
  (local date (value.parse-date-time Temporal {:VALUE "DATE"} "20261001"))
  (local (date-params date-text) (value.format-date-time date))
  (assert= date-params.VALUE "DATE")
  (assert= date-text "20261001")
  (local utc (value.parse-date-time Temporal {} "20261001T130000Z"))
  (local (utc-params utc-text) (value.format-date-time utc))
  (assert-no-param utc-params "VALUE")
  (assert= utc-text "20261001T130000Z")
  (local floating (value.parse-date-time Temporal {} "20261001T090000"))
  (local (floating-params floating-text) (value.format-date-time floating))
  (assert-no-param floating-params "TZID")
  (assert= floating-text "20261001T090000")
  (local zoned (value.parse-date-time Temporal {:TZID "America/New_York"} "20261001T090000"))
  (local (zoned-params zoned-text) (value.format-date-time zoned))
  (assert= zoned-params.TZID "America/New_York")
  (assert= zoned-text "20261001T090000"))

(fn value-parses-and-formats-supported-durations []
  (local timed (value.parse-duration Temporal "PT1H30M" false))
  (assert-duration-seconds timed 5400)
  (assert= (value.format-duration timed false) "PT1H30M")
  (local all-day (value.parse-duration Temporal "P2D" true))
  (assert= (Temporal.period.format all-day) "P2D")
  (assert= (value.format-duration all-day true) "P2D"))

(fn value-rejects-unsupported-date-time-boundaries []
  (assert-error-contains #(value.parse-date-time Temporal {:TZID "Custom/Local"} "20261001T090000")
                         "TZID"
                         "custom TZID should fail loudly")
  (assert-error-contains #(value.parse-date-time Temporal {:VALUE "DATE-TIME"} "20261001T090000")
                         "VALUE"
                         "explicit DATE-TIME value should fail")
  (assert-error-contains #(value.parse-date-time Temporal {:VALUE "DATE" :TZID "America/New_York"} "20261001")
                         "TZID"
                         "TZID on DATE should fail")
  (assert-error-contains #(value.parse-duration Temporal "P1DT2H" false)
                         "mixed"
                         "mixed duration should fail")
  (assert-error-contains #(value.parse-duration Temporal "PT1H" true)
                         "all-day"
                         "timed duration for all-day should fail"))

(fn value-adds-zoned-durations-on-instant-timeline []
  (local start (value.parse-date-time Temporal {:TZID "America/New_York"} "20260308T013000"))
  (local shifted (value.start-plus-duration Temporal start (Temporal.duration.from-seconds 3600)))
  (assert= shifted.value-type :date-time)
  (assert= shifted.time-mode :zoned)
  (assert= shifted.zone-id "America/New_York")
  (assert= (shifted.plain:to-string) "2026-03-08T03:30:00"))

(fn value-rejects-fractional-second-date-time-formatting []
  (local fractional-plain (Temporal.plain-date-time.parse "2026-10-01T09:00:00.5"))
  (assert-error-contains #(value.format-date-time {:kind :temporal-ics-date-time
                                                   :value-type :date-time
                                                   :time-mode :floating
                                                   :plain fractional-plain})
                         "whole seconds"
                         "floating fractional seconds should fail")
  (assert-error-contains #(value.format-date-time {:kind :temporal-ics-date-time
                                                   :value-type :date-time
                                                   :time-mode :zoned
                                                   :zone-id "America/New_York"
                                                   :plain fractional-plain})
                         "whole seconds"
                         "zoned fractional seconds should fail")
  (local fractional-instant (Temporal.instant.parse "2026-10-01T13:00:00.5Z"))
  (assert-error-contains #(value.format-date-time {:kind :temporal-ics-date-time
                                                   :value-type :date-time
                                                   :time-mode :utc
                                                   :instant fractional-instant})
                          "whole seconds"
                          "UTC fractional seconds should fail"))

(fn parser-exports-public-temporal-ics []
  (assert= (type Temporal.ics.parse) :function "Temporal.ics.parse should be public")
  (assert= (type Temporal.ics.format) :function "Temporal.ics.format should be public")
  (assert= (type Temporal.ics.expand) :function "Temporal.ics.expand should be public"))

(fn parser-parses-supported-fixture-records []
  (local calendar (Temporal.ics.parse (read-fixture "single-zoned")))
  (assert= calendar.kind :temporal-ics-calendar)
  (assert= calendar.version "2.0")
  (assert= calendar.calscale "GREGORIAN")
  (assert= (. (. calendar.timezones 1) :tzid) "America/New_York")
  (local event (. calendar.events 1))
  (assert= event.uid "single-zoned@example.test")
  (assert= event.status :confirmed)
  (assert= event.sequence 0)
  (assert= event.dtstart.time-mode :zoned)
  (assert= event.dtstart.zone-id "America/New_York")
  (assert= (event.dtstart.plain:to-string) "2026-10-01T09:00:00")
  (assert= event.summary "New York standup"))

(fn parser-parses-all-required-fixture-families []
  (each [_ name (ipairs successful-fixtures)]
    (local calendar (Temporal.ics.parse (read-fixture name)))
    (assert (> (# calendar.events) 0) (.. name " should parse at least one event"))))

(fn parser-preserves-x-properties-only-under-preserve-policy []
  (local text "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:x-props@example.test\nDTSTART:20261001T090000\nX-SPACE-COLOR:blue\nEND:VEVENT\nEND:VCALENDAR\n")
  (assert-error-contains #(Temporal.ics.parse text) "X-SPACE-COLOR" "strict policy should reject X properties")
  (local calendar (Temporal.ics.parse text {:unknown-property-policy :preserve}))
  (local xprop (. (. (. calendar.events 1) :x-properties) 1))
  (assert= xprop.name "X-SPACE-COLOR")
  (assert= xprop.value "blue"))

(fn parser-parses-nested-vtimezone-metadata []
  (local text "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VTIMEZONE\nTZID:America/New_York\nBEGIN:STANDARD\nDTSTART:20261101T020000\nTZOFFSETFROM:-0400\nTZOFFSETTO:-0500\nTZNAME:EST\nEND:STANDARD\nEND:VTIMEZONE\nBEGIN:VEVENT\nUID:nested-zone@example.test\nDTSTART;TZID=America/New_York:20261001T090000\nSUMMARY:Nested timezone metadata\nEND:VEVENT\nEND:VCALENDAR\n")
  (local calendar (Temporal.ics.parse text))
  (local timezone (. calendar.timezones 1))
  (assert= timezone.tzid "America/New_York")
  (assert= (. timezone.raw-lines 2) "BEGIN:STANDARD")
  (assert= (. timezone.raw-lines 7) "END:STANDARD")
  (assert= (. (. calendar.events 1) :uid) "nested-zone@example.test"))

(fn parser-rejects-invalid-calendar-and-event-shapes []
  (assert-error-contains #(Temporal.ics.parse "BEGIN:VCALENDAR\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:missing-version@example.test\nDTSTART:20261001T090000\nEND:VEVENT\nEND:VCALENDAR\n")
                         "VERSION"
                         "missing VERSION should fail")
  (assert-error-contains #(Temporal.ics.parse "BEGIN:VCALENDAR\nVERSION:2.0\nCALSCALE:JULIAN\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:bad-calscale@example.test\nDTSTART:20261001T090000\nEND:VEVENT\nEND:VCALENDAR\n")
                         "CALSCALE"
                         "bad CALSCALE should fail")
  (assert-error-contains #(Temporal.ics.parse "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nDTSTART:20261001T090000\nEND:VEVENT\nEND:VCALENDAR\n")
                         "UID"
                         "missing UID should fail")
  (assert-error-contains #(Temporal.ics.parse "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:missing-start@example.test\nEND:VEVENT\nEND:VCALENDAR\n")
                         "DTSTART"
                         "missing DTSTART should fail")
  (assert-error-contains #(Temporal.ics.parse (read-fixture "unsupported-component"))
                         "VTODO"
                         "unsupported component should fail")
  (assert-error-contains #(Temporal.ics.parse (read-fixture "unsupported-tzid"))
                         "TZID"
                         "unsupported TZID should fail")
  (assert-error-contains #(Temporal.ics.parse "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:bad-end@example.test\nDTSTART:20261001T090000\nDTEND:20261001T100000\nDURATION:PT1H\nEND:VEVENT\nEND:VCALENDAR\n")
                         "DTEND"
                         "DTEND and DURATION should fail")
  (assert-error-contains #(Temporal.ics.parse "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:location@example.test\nDTSTART:20261001T090000\nLOCATION:Room 1\nEND:VEVENT\nEND:VCALENDAR\n")
                         "LOCATION"
                         "unknown LOCATION should fail"))

(table.insert tests {:name "grammar unfolds CRLF and LF lines"
                     :fn grammar-unfolds-crlf-and-lf-lines})
(table.insert tests {:name "grammar parses names params and values"
                     :fn grammar-parses-names-params-and-values})
(table.insert tests {:name "grammar rejects malformed lines and escapes"
                     :fn grammar-rejects-malformed-lines-and-escapes})
(table.insert tests {:name "grammar emits folded content lines"
                      :fn grammar-emits-folded-content-lines})
(table.insert tests {:name "value parses date time modes"
                     :fn value-parses-date-time-modes})
(table.insert tests {:name "value formats date time modes"
                     :fn value-formats-date-time-modes})
(table.insert tests {:name "value parses and formats supported durations"
                     :fn value-parses-and-formats-supported-durations})
(table.insert tests {:name "value rejects unsupported date time boundaries"
                     :fn value-rejects-unsupported-date-time-boundaries})
(table.insert tests {:name "value adds zoned durations on instant timeline"
                     :fn value-adds-zoned-durations-on-instant-timeline})
(table.insert tests {:name "value rejects fractional second date time formatting"
                      :fn value-rejects-fractional-second-date-time-formatting})
(table.insert tests {:name "parser exports public temporal ics"
                     :fn parser-exports-public-temporal-ics})
(table.insert tests {:name "parser parses supported fixture records"
                     :fn parser-parses-supported-fixture-records})
(table.insert tests {:name "parser parses all required fixture families"
                     :fn parser-parses-all-required-fixture-families})
(table.insert tests {:name "parser preserves x properties only under preserve policy"
                     :fn parser-preserves-x-properties-only-under-preserve-policy})
(table.insert tests {:name "parser parses nested vtimezone metadata"
                     :fn parser-parses-nested-vtimezone-metadata})
(table.insert tests {:name "parser rejects invalid calendar and event shapes"
                     :fn parser-rejects-invalid-calendar-and-event-shapes})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-ics" :tests tests})))

{:name "temporal-ics" :tests tests :main main}
