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

(fn expand-fixture [name options]
  (Temporal.ics.expand (Temporal.ics.parse (read-fixture name)) (if (= options nil) {} options)))

(fn expand-text [text options]
  (Temporal.ics.expand (Temporal.ics.parse text) (if (= options nil) {} options)))

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

(fn formatter-emits-canonical-single-event []
  (local calendar (Temporal.ics.parse (read-fixture "single-utc")))
  (local formatted (Temporal.ics.format calendar {:line-ending :lf}))
  (assert (= nil (formatted:find "\r" 1 true)) "LF formatting should not contain CR")
  (assert= formatted
           "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nCALSCALE:GREGORIAN\nBEGIN:VEVENT\nUID:single-utc@example.test\nSEQUENCE:0\nSTATUS:CONFIRMED\nDTSTART:20261001T130000Z\nDTEND:20261001T140000Z\nSUMMARY:UTC standup\nEND:VEVENT\nEND:VCALENDAR\n"))

(fn formatter-defaults-to-crlf []
  (local calendar (Temporal.ics.parse (read-fixture "single-utc")))
  (local formatted (Temporal.ics.format calendar))
  (assert (formatted:find "\r\n" 1 true) "default formatting should contain CRLF")
  (assert (= nil (formatted:find "[^\r]\n")) "default formatting should not contain bare LF"))

(fn formatter-round-trips-supported-fixtures []
  (each [_ name (ipairs successful-fixtures)]
    (local original (Temporal.ics.parse (read-fixture name)))
    (local reparsed (Temporal.ics.parse (Temporal.ics.format original)))
    (assert= reparsed.kind original.kind (.. name " calendar kind should survive"))
    (assert= (# reparsed.events) (# original.events) (.. name " event count should survive"))
    (assert= (. (. reparsed.events 1) :uid) (. (. original.events 1) :uid)
             (.. name " first UID should survive"))))

(fn formatter-rejects-unknown-record-keys []
  (local calendar (Temporal.ics.parse (read-fixture "single-utc")))
  (set calendar.timezone {:tzid "America/New_York"})
  (assert-error-contains #(Temporal.ics.format calendar {:line-ending :lf})
                         "timezone"
                         "unknown calendar key should fail loudly"))

(fn formatter-validates-options []
  (local calendar (Temporal.ics.parse (read-fixture "single-utc")))
  (assert-error-contains #(Temporal.ics.format calendar {:newline :lf})
                         "newline"
                         "newline alias should be rejected")
  (assert-error-contains #(Temporal.ics.format calendar {:line-ending :native})
                         "line-ending"
                         "invalid line-ending should be rejected"))

(fn formatter-requires-explicit-version []
  (local calendar (Temporal.ics.parse (read-fixture "single-utc")))
  (set calendar.version nil)
  (assert-error-contains #(Temporal.ics.format calendar {:line-ending :lf})
                         "VERSION"
                         "formatter should not default missing VERSION"))

(fn formatter-rejects-unsupported-x-property-names []
  (local calendar (Temporal.ics.parse (read-fixture "single-utc")))
  (table.insert (. (. calendar.events 1) :x-properties)
                {:name "LOCATION" :params {} :value "Room 1" :source-order 99})
  (assert-error-contains #(Temporal.ics.format calendar {:line-ending :lf})
                         "LOCATION"
                         "formatter should reject unsupported event property names")
  (local calendar-property (Temporal.ics.parse (read-fixture "single-utc")))
  (set calendar-property.x-properties [{:name "LOCATION" :params {} :value "Room 1" :source-order 3}])
  (assert-error-contains #(Temporal.ics.format calendar-property {:line-ending :lf})
                         "LOCATION"
                         "formatter should reject unsupported calendar property names"))

(fn formatter-validates-context-specific-preserved-properties []
  (local calendar-dtstamp (Temporal.ics.parse (read-fixture "single-utc")))
  (set calendar-dtstamp.x-properties [{:name "DTSTAMP" :params {} :value "20261001T120000Z" :source-order 3}])
  (assert-error-contains #(Temporal.ics.format calendar-dtstamp {:line-ending :lf})
                         "DTSTAMP"
                         "formatter should reject calendar-level DTSTAMP")
  (local event-dtstamp (Temporal.ics.parse (read-fixture "single-utc")))
  (table.insert (. (. event-dtstamp.events 1) :x-properties)
                {:name "DTSTAMP" :params {} :value "20261001T120000Z" :source-order 99})
  (local formatted (Temporal.ics.format event-dtstamp {:line-ending :lf}))
  (assert (formatted:find "DTSTAMP:20261001T120000Z" 1 true)
          "formatter should allow parser-supported event-level DTSTAMP"))

(fn formatter-rejects-constructed-vtimezone-records []
  (local calendar (Temporal.ics.parse (read-fixture "single-utc")))
  (table.insert calendar.timezones {:kind :temporal-ics-timezone
                                    :tzid "America/New_York"
                                    :raw-lines []})
  (assert-error-contains #(Temporal.ics.format calendar {:line-ending :lf})
                         "VTIMEZONE"
                         "formatter should reject timezones without preserved raw lines")
  (local mismatched (Temporal.ics.parse (read-fixture "single-utc")))
  (table.insert mismatched.timezones {:kind :temporal-ics-timezone
                                      :tzid "America/Chicago"
                                      :raw-lines ["TZID:America/New_York"]})
  (assert-error-contains #(Temporal.ics.format mismatched {:line-ending :lf})
                         "TZID"
                         "formatter should reject timezone record/raw TZID mismatch"))

(fn formatter-rejects-mixed-date-time-modes []
  (local utc-end (value.parse-date-time Temporal {} "20261001T140000Z"))
  (local utc-id (value.parse-date-time Temporal {} "20261001T130000Z"))
  (local utc-date (value.parse-date-time Temporal {} "20261002T130000Z"))
  (local bad-dtend (Temporal.ics.parse (read-fixture "single-floating")))
  (local bad-dtend-event (. bad-dtend.events 1))
  (set bad-dtend-event.dtend utc-end)
  (assert-error-contains #(Temporal.ics.format bad-dtend {:line-ending :lf})
                         "DTEND"
                         "formatter should reject DTEND mode mismatch")
  (local bad-recurrence-id (Temporal.ics.parse (read-fixture "single-floating")))
  (local bad-recurrence-id-event (. bad-recurrence-id.events 1))
  (set bad-recurrence-id-event.recurrence-id utc-id)
  (assert-error-contains #(Temporal.ics.format bad-recurrence-id {:line-ending :lf})
                         "RECURRENCE-ID"
                         "formatter should reject RECURRENCE-ID mode mismatch")
  (local bad-rdate (Temporal.ics.parse (read-fixture "single-floating")))
  (table.insert (. (. bad-rdate.events 1) :rdates) utc-date)
  (assert-error-contains #(Temporal.ics.format bad-rdate {:line-ending :lf})
                         "RDATE"
                         "formatter should reject RDATE mode mismatch")
  (local bad-exdate (Temporal.ics.parse (read-fixture "single-floating")))
  (table.insert (. (. bad-exdate.events 1) :exdates) utc-date)
  (assert-error-contains #(Temporal.ics.format bad-exdate {:line-ending :lf})
                          "EXDATE"
                          "formatter should reject EXDATE mode mismatch"))

(fn expand-single-event-modes []
  (local utc (. (expand-fixture "single-utc") 1))
  (assert= utc.kind :temporal-ics-occurrence)
  (assert= utc.start.time-mode :utc)
  (assert= (utc.start.instant:to-string) "2026-10-01T13:00:00Z")
  (assert= utc.instant-interval.type :instant)
  (local floating (. (expand-fixture "single-floating" {:zone-id "America/New_York"}) 1))
  (assert= floating.start.time-mode :floating)
  (assert= (floating.start.plain:to-string) "2026-10-01T09:00:00")
  (assert= floating.instant-interval nil "floating occurrences should not expose exact interval fields")
  (local zoned (. (expand-fixture "single-zoned") 1))
  (assert= zoned.start.time-mode :zoned)
  (assert= zoned.start.zone-id "America/New_York")
  (assert= zoned.zoned-interval.type :zoned-date-time)
  (local all-day (. (expand-fixture "single-all-day") 1))
  (assert= all-day.start.value-type :date)
  (assert= all-day.start.date.day 1)
  (assert= all-day.end.value-type :date)
  (assert= all-day.end.date.day 2)
  (assert= all-day.instant-interval nil)
  (assert= all-day.zoned-interval nil))

(fn expand-requires-zone-for-floating-events []
  (assert-error-contains #(expand-fixture "single-floating")
                         "zone-id"
                         "floating expansion without zone-id should fail")
  (assert-error-contains #(expand-fixture "single-floating" {:timezone "America/New_York"})
                         "timezone"
                         "timezone alias should be rejected"))

(fn expand-duration-events []
  (local timed (. (expand-fixture "timed-duration" {:zone-id "America/New_York"}) 1))
  (assert= (timed.end.plain:to-string) "2026-10-01T10:30:00")
  (local all-day (. (expand-fixture "all-day-duration") 1))
  (assert= all-day.end.value-type :date)
  (assert= all-day.end.date.day 3))

(fn expand-recurrence-fixtures []
  (assert= (# (expand-fixture "weekly-rrule" {:zone-id "America/New_York"})) 3)
  (assert= (# (expand-fixture "rrule-rdate-exdate" {:zone-id "America/New_York"})) 3)
  (assert= (# (expand-fixture "exrule" {:zone-id "America/New_York"})) 3)
  (assert= (# (expand-fixture "utc-until")) 3))

(fn expand-unbounded-recurrence-requires-limit []
  (local text "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:unbounded@example.test\nDTSTART:20261001T090000\nRRULE:FREQ=DAILY\nSUMMARY:Unbounded daily\nEND:VEVENT\nEND:VCALENDAR\n")
  (local calendar (Temporal.ics.parse text))
  (assert-error-contains #(Temporal.ics.expand calendar {:zone-id "America/New_York"})
                         "limit"
                         "unbounded recurrence should require limit")
  (assert= (# (Temporal.ics.expand calendar {:zone-id "America/New_York" :limit 2})) 2))

(fn expand-unbounded-recurrence-error-mentions-limit []
  (local text "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:unbounded-message@example.test\nDTSTART:20261001T090000\nRRULE:FREQ=DAILY\nEXDATE:20261001T090000\nSUMMARY:Unbounded daily with exclusion\nEND:VEVENT\nEND:VCALENDAR\n")
  (local calendar (Temporal.ics.parse text))
  (assert-error-contains #(Temporal.ics.expand calendar {:zone-id "America/New_York"})
                         "limit"
                         "ICS expander should rethrow unbounded recurrence errors with limit guidance"))

(fn expand-zoned-duration-honors-disambiguation []
  (local overlap-text "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:overlap-duration@example.test\nDTSTART;TZID=America/New_York:20261101T013000\nDURATION:PT1H\nSUMMARY:Overlap duration\nEND:VEVENT\nEND:VCALENDAR\n")
  (local overlap (. (Temporal.ics.expand (Temporal.ics.parse overlap-text) {:disambiguation :latest}) 1))
  (assert= overlap.start.time-mode :zoned)
  (assert= (overlap.end.plain:to-string) "2026-11-01T02:30:00")
  (local gap-text "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:gap-duration@example.test\nDTSTART;TZID=America/New_York:20260308T023000\nDURATION:PT1H\nSUMMARY:Gap duration\nEND:VEVENT\nEND:VCALENDAR\n")
  (local gap (. (Temporal.ics.expand (Temporal.ics.parse gap-text) {:disambiguation :earliest}) 1))
  (assert= gap.start.time-mode :zoned)
  (assert= (gap.end.plain:to-string) "2026-03-08T04:00:00"))

(fn expand-limit-applies-after-exrule-exclusions []
  (local occurrences (expand-fixture "exrule" {:zone-id "America/New_York" :limit 3}))
  (assert= (# occurrences) 3)
  (local first-start (. (. (. occurrences 1) :start) :plain))
  (local third-start (. (. (. occurrences 3) :start) :plain))
  (assert= (first-start:to-string) "2026-10-03T09:00:00")
  (assert= (third-start:to-string) "2026-10-05T09:00:00"))

(fn expand-backfills-past-large-exrule-exclusions []
  (local text "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:large-exrule@example.test\nDTSTART:20261001T090000\nRRULE:FREQ=DAILY\nEXRULE:FREQ=DAILY;COUNT=128\nSUMMARY:Large exclusion prefix\nEND:VEVENT\nEND:VCALENDAR\n")
  (local occurrences (Temporal.ics.expand (Temporal.ics.parse text) {:zone-id "America/New_York" :limit 1}))
  (assert= (# occurrences) 1)
  (local start (. (. (. occurrences 1) :start) :plain))
  (assert= (start:to-string) "2027-02-06T09:00:00"))

(fn expand-recurrence-includes-dtstart-with-rdate-and-exdate []
  (local rdate-text "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:rdate-only@example.test\nDTSTART:20261001T090000\nRDATE:20261003T090000\nSUMMARY:RDATE only\nEND:VEVENT\nEND:VCALENDAR\n")
  (local rdate-occurrences (Temporal.ics.expand (Temporal.ics.parse rdate-text) {:zone-id "America/New_York"}))
  (assert= (# rdate-occurrences) 2)
  (local rdate-first-start (. (. (. rdate-occurrences 1) :start) :plain))
  (local rdate-second-start (. (. (. rdate-occurrences 2) :start) :plain))
  (assert= (rdate-first-start:to-string) "2026-10-01T09:00:00")
  (assert= (rdate-second-start:to-string) "2026-10-03T09:00:00")
  (local exdate-text "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:exdate-only@example.test\nDTSTART:20261001T090000\nEXDATE:20261001T090000\nSUMMARY:EXDATE only\nEND:VEVENT\nEND:VCALENDAR\n")
  (local exdate-occurrences (Temporal.ics.expand (Temporal.ics.parse exdate-text) {:zone-id "America/New_York"}))
  (assert= (# exdate-occurrences) 0))

(fn expand-applies-overrides-and-cancellations []
  (local override-text "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:override-inline@example.test\nDTSTART:20261001T090000\nRRULE:FREQ=DAILY;COUNT=3\nSUMMARY:Recurring master\nEND:VEVENT\nBEGIN:VEVENT\nUID:override-inline@example.test\nRECURRENCE-ID:20261002T090000\nDTSTART:20261002T110000\nDTEND:20261002T120000\nSUMMARY:Moved recurring event\nEND:VEVENT\nEND:VCALENDAR\n")
  (local overrides (expand-text override-text {:zone-id "America/New_York"}))
  (assert= (# overrides) 3)
  (local moved (. overrides 2))
  (assert= moved.summary "Moved recurring event")
  (assert= (moved.start.plain:to-string) "2026-10-02T11:00:00")
  (assert= (moved.recurrence-id.plain:to-string) "2026-10-02T09:00:00")
  (local cancelled (expand-fixture "cancelled-occurrence" {:zone-id "America/New_York"}))
  (assert= (# cancelled) 2)
  (each [_ occurrence (ipairs cancelled)]
    (assert (not= (occurrence.recurrence-id.plain:to-string) "2026-10-02T09:00:00")
            "cancelled recurrence id should be absent"))
  (assert= (# (expand-fixture "cancelled-master" {:zone-id "America/New_York"})) 0)
  (local outside-text "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:outside-override@example.test\nDTSTART:20261001T090000\nRRULE:FREQ=DAILY;COUNT=2\nSUMMARY:Recurring master\nEND:VEVENT\nBEGIN:VEVENT\nUID:outside-override@example.test\nRECURRENCE-ID:20261005T090000\nDTSTART:20261005T100000\nSUMMARY:Late override\nEND:VEVENT\nEND:VCALENDAR\n")
  (local outside (expand-text outside-text {:zone-id "America/New_York"}))
  (assert= (# outside) 3)
  (assert= (. (. outside 3) :summary) "Late override")
  (local orphan-text "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:orphan-override@example.test\nRECURRENCE-ID:20261005T090000\nDTSTART:20261005T100000\nSUMMARY:Orphan override\nEND:VEVENT\nEND:VCALENDAR\n")
  (assert= (# (expand-text orphan-text {:zone-id "America/New_York"})) 0))

(fn expand-rejects-ambiguous-duplicate-events []
  (local duplicate-master "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:duplicate@example.test\nDTSTART:20261001T090000\nSUMMARY:First\nEND:VEVENT\nBEGIN:VEVENT\nUID:duplicate@example.test\nDTSTART:20261002T090000\nSUMMARY:Second\nEND:VEVENT\nEND:VCALENDAR\n")
  (assert-error-contains #(expand-text duplicate-master {:zone-id "America/New_York"})
                         "duplicate master"
                         "duplicate masters should fail loudly")
  (local duplicate-override "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:duplicate-override@example.test\nDTSTART:20261001T090000\nRRULE:FREQ=DAILY;COUNT=3\nSUMMARY:Master\nEND:VEVENT\nBEGIN:VEVENT\nUID:duplicate-override@example.test\nRECURRENCE-ID:20261002T090000\nDTSTART:20261002T110000\nSUMMARY:Moved\nEND:VEVENT\nBEGIN:VEVENT\nUID:duplicate-override@example.test\nRECURRENCE-ID:20261002T090000\nDTSTART:20261002T090000\nSTATUS:CANCELLED\nSUMMARY:Cancelled\nEND:VEVENT\nEND:VCALENDAR\n")
  (assert-error-contains #(expand-text duplicate-override {:zone-id "America/New_York"})
                         "duplicate override"
                         "duplicate overrides should fail loudly"))

(fn expand-rejects-override-recurrence-id-mode-mismatch []
  (local mismatched-override "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:mismatched-override@example.test\nDTSTART:20261001T090000\nRRULE:FREQ=DAILY;COUNT=2\nSUMMARY:Floating master\nEND:VEVENT\nBEGIN:VEVENT\nUID:mismatched-override@example.test\nRECURRENCE-ID:20261002T090000Z\nDTSTART:20261002T110000Z\nSUMMARY:UTC override\nEND:VEVENT\nEND:VCALENDAR\n")
  (local err (assert-error #(expand-text mismatched-override {:zone-id "America/New_York"})
                           "override recurrence id mode should match master DTSTART mode"))
  (assert (tostring err):find "RECURRENCE-ID" 1 true)
  (assert (tostring err):find "master DTSTART mode" 1 true)
  (local cancelled-master-mismatch "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal//EN\nBEGIN:VEVENT\nUID:cancelled-master-mismatch@example.test\nDTSTART:20261001T090000\nSTATUS:CANCELLED\nSUMMARY:Cancelled floating master\nEND:VEVENT\nBEGIN:VEVENT\nUID:cancelled-master-mismatch@example.test\nRECURRENCE-ID:20261002T090000Z\nDTSTART:20261002T110000Z\nSUMMARY:UTC override\nEND:VEVENT\nEND:VCALENDAR\n")
  (local cancelled-err (assert-error #(expand-text cancelled-master-mismatch {:zone-id "America/New_York"})
                                     "cancelled master override recurrence id mode should match master DTSTART mode"))
  (assert (tostring cancelled-err):find "RECURRENCE-ID" 1 true)
  (assert (tostring cancelled-err):find "master DTSTART mode" 1 true))

(fn temporal-ics-acceptance-smoke []
  (local folded (Temporal.ics.parse (read-fixture "folded-escaped")))
  (local reparsed (Temporal.ics.parse (Temporal.ics.format folded)))
  (assert= (. (. reparsed.events 1) :summary)
           "This summary is deliberately long so it can be folded across a linecontinuation")
  (assert= (# (expand-fixture "weekly-rrule" {:zone-id "America/New_York"})) 3)
  (assert= (# (expand-fixture "cancelled-occurrence" {:zone-id "America/New_York"})) 2)
  (assert-error-contains #(Temporal.ics.parse (read-fixture "unsupported-component"))
                         "VTODO"
                         "unsupported component should remain loud"))

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
(table.insert tests {:name "formatter emits canonical single event"
                     :fn formatter-emits-canonical-single-event})
(table.insert tests {:name "formatter defaults to crlf"
                     :fn formatter-defaults-to-crlf})
(table.insert tests {:name "formatter round trips supported fixtures"
                     :fn formatter-round-trips-supported-fixtures})
(table.insert tests {:name "formatter rejects unknown record keys"
                     :fn formatter-rejects-unknown-record-keys})
(table.insert tests {:name "formatter validates options"
                     :fn formatter-validates-options})
(table.insert tests {:name "formatter requires explicit version"
                     :fn formatter-requires-explicit-version})
(table.insert tests {:name "formatter rejects unsupported x property names"
                     :fn formatter-rejects-unsupported-x-property-names})
(table.insert tests {:name "formatter validates context specific preserved properties"
                     :fn formatter-validates-context-specific-preserved-properties})
(table.insert tests {:name "formatter rejects constructed vtimezone records"
                     :fn formatter-rejects-constructed-vtimezone-records})
(table.insert tests {:name "formatter rejects mixed date time modes"
                      :fn formatter-rejects-mixed-date-time-modes})
(table.insert tests {:name "expand single event modes"
                     :fn expand-single-event-modes})
(table.insert tests {:name "expand requires zone for floating events"
                     :fn expand-requires-zone-for-floating-events})
(table.insert tests {:name "expand duration events"
                     :fn expand-duration-events})
(table.insert tests {:name "expand recurrence fixtures"
                     :fn expand-recurrence-fixtures})
(table.insert tests {:name "expand unbounded recurrence requires limit"
                     :fn expand-unbounded-recurrence-requires-limit})
(table.insert tests {:name "expand unbounded recurrence error mentions limit"
                     :fn expand-unbounded-recurrence-error-mentions-limit})
(table.insert tests {:name "expand zoned duration honors disambiguation"
                     :fn expand-zoned-duration-honors-disambiguation})
(table.insert tests {:name "expand limit applies after exrule exclusions"
                     :fn expand-limit-applies-after-exrule-exclusions})
(table.insert tests {:name "expand backfills past large exrule exclusions"
                     :fn expand-backfills-past-large-exrule-exclusions})
(table.insert tests {:name "expand recurrence includes dtstart with rdate and exdate"
                      :fn expand-recurrence-includes-dtstart-with-rdate-and-exdate})
(table.insert tests {:name "expand applies overrides and cancellations"
                     :fn expand-applies-overrides-and-cancellations})
(table.insert tests {:name "expand rejects ambiguous duplicate events"
                     :fn expand-rejects-ambiguous-duplicate-events})
(table.insert tests {:name "expand rejects override recurrence id mode mismatch"
                     :fn expand-rejects-override-recurrence-id-mode-mismatch})
(table.insert tests {:name "temporal ics acceptance smoke"
                     :fn temporal-ics-acceptance-smoke})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-ics" :tests tests})))

{:name "temporal-ics" :tests tests :main main}
