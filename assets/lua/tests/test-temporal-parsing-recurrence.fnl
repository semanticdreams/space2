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

(fn recurrence-rrule-round-trip []
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=WEEKLY;COUNT=3;BYDAY=TU"))
  (assert (= rule.freq :weekly))
  (assert (= rule.count 3))
  (assert (= (. rule.by-day 1) :tu))
  (assert (= (Temporal.recurrence.to-rrule rule)
             "RRULE:FREQ=WEEKLY;COUNT=3;BYDAY=TU"))
  (assert-error #(Temporal.recurrence.parse-rrule "RRULE:FREQ=WEEKLY;FREQ=DAILY")
                "duplicate RRULE key should throw")
  (assert-error #(Temporal.recurrence.parse-rrule "RRULE:FREQ=WEEKLY;BYHOUR=9")
                "unknown RRULE key should throw"))

(fn recurrence-bymonth-parse-and-serialize []
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;COUNT=2;BYMONTH=1,3,12"))
  (assert (= rule.freq :yearly))
  (assert (= rule.count 2))
  (assert (= (. rule.by-month 1) 1))
  (assert (= (. rule.by-month 2) 3))
  (assert (= (. rule.by-month 3) 12))
  (assert (= (Temporal.recurrence.to-rrule rule)
             "RRULE:FREQ=YEARLY;COUNT=2;BYMONTH=1,3,12"))

  (local from-rule (Temporal.recurrence.from {:freq :monthly :by-month [2 4]}))
  (assert (= (. from-rule.by-month 1) 2))
  (assert (= (. from-rule.by-month 2) 4))

  (assert-error #(Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYMONTH=0")
                "BYMONTH=0 should throw")
  (assert-error #(Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYMONTH=13")
                "BYMONTH=13 should throw")
  (assert-error #(Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYMONTH=JAN")
                "BYMONTH=JAN should throw")
  (assert-error #(Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYMONTH=1,,2")
                "BYMONTH with empty member should throw")
  (assert-error #(Temporal.recurrence.from {:freq :monthly :by-month []})
                "empty by-month should throw")
  (assert-error #(Temporal.recurrence.from {:freq :monthly :by-month 1})
                "non-table by-month should throw"))

(fn assert-occurrence-strings [actual expected]
  (assert (= (# actual) (# expected)))
  (each [index value (ipairs expected)]
    (local occurrence (. actual index))
    (assert (= (occurrence:to-string) value))))

(fn temporal-factory-wiring-keeps-public-recurrence-and-natural []
  (local create-recurrence (require :temporal/recurrence))
  (local create-natural (require :temporal/natural))
  (assert (= (type create-recurrence) :function))
  (assert (= (type create-natural) :function))
  (assert-error #(create-recurrence {})
                "recurrence factory should require period dependency")
  (assert-error #(create-natural {})
                "natural factory should require recurrence dependency")
  (local parsed (Temporal.natural.parse "every Tuesday"))
  (assert (= parsed.kind :recurrence))
  (assert (= parsed.rule.freq :weekly))
  (assert (= (. parsed.rule.by-day 1) :tu)))

(fn recurrence-weekly-occurrences []
  (local dtstart (Temporal.plain-date-time.parse "2026-09-22T09:00:00"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=WEEKLY;COUNT=3;BYDAY=TU"))
  (local occ (Temporal.recurrence.occurrences rule dtstart {}))
  (assert (= (# occ) 3))
  (local first (. occ 1))
  (local second (. occ 2))
  (local third (. occ 3))
  (assert (= (first:to-string) "2026-09-22T09:00:00"))
  (assert (= (second:to-string) "2026-09-29T09:00:00"))
  (assert (= (third:to-string) "2026-10-06T09:00:00")))

(fn recurrence-weekly-without-by-day-uses-dtstart-weekday []
  (local dtstart (Temporal.plain-date-time.parse "2026-09-22T09:00:00"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=WEEKLY;COUNT=3"))
  (local occ (Temporal.recurrence.occurrences rule dtstart {}))
  (assert (= (# occ) 3))
  (local first (. occ 1))
  (local second (. occ 2))
  (local third (. occ 3))
  (assert (= (first:to-string) "2026-09-22T09:00:00"))
  (assert (= (second:to-string) "2026-09-29T09:00:00"))
  (assert (= (third:to-string) "2026-10-06T09:00:00")))

(fn recurrence-monthly-anchor-clamps-without-drift []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-31T10:11:12"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=4"))
  (assert-occurrence-strings
    (Temporal.recurrence.occurrences rule dtstart {})
    ["2026-01-31T10:11:12"
     "2026-02-28T10:11:12"
     "2026-03-31T10:11:12"
     "2026-04-30T10:11:12"]))

(fn recurrence-yearly-leap-day-anchor-clamps-without-drift []
  (local dtstart (Temporal.plain-date-time.parse "2028-02-29T10:11:12"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;COUNT=5"))
  (assert-occurrence-strings
    (Temporal.recurrence.occurrences rule dtstart {})
    ["2028-02-29T10:11:12"
     "2029-02-28T10:11:12"
     "2030-02-28T10:11:12"
     "2031-02-28T10:11:12"
     "2032-02-29T10:11:12"]))

(fn recurrence-monthly-yearly-bounds-and-rejections []
  (local monthly-start (Temporal.plain-date-time.parse "2026-01-31T10:11:12"))
  (local every-two-months (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;INTERVAL=2;COUNT=3"))
  (assert-occurrence-strings
    (Temporal.recurrence.occurrences every-two-months monthly-start {})
    ["2026-01-31T10:11:12"
     "2026-03-31T10:11:12"
     "2026-05-31T10:11:12"])

  (local yearly-start (Temporal.plain-date-time.parse "2028-02-29T10:11:12"))
  (local yearly (Temporal.recurrence.from {:freq :yearly :interval 2}))
  (assert-occurrence-strings
    (Temporal.recurrence.occurrences yearly yearly-start {:limit 2})
    ["2028-02-29T10:11:12"
     "2030-02-28T10:11:12"])

  (local until-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=3;UNTIL=20260131T000000Z"))
  (assert-occurrence-strings
    (Temporal.recurrence.occurrences until-rule monthly-start {})
    ["2026-01-31T10:11:12"
     "2026-02-28T10:11:12"
     "2026-03-31T10:11:12"])

  (assert-error #(Temporal.recurrence.occurrences
                   (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=1;BYDAY=MO")
                   monthly-start
                   {})
                "monthly BYDAY expansion should throw")
  (assert-error #(Temporal.recurrence.occurrences
                   (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;COUNT=1;BYDAY=MO")
                   yearly-start
                   {})
                 "yearly BYDAY expansion should throw"))

(fn recurrence-bymonth-filters-occurrences []
  (local daily-start (Temporal.plain-date-time.parse "2026-01-30T09:00:00"))
  (local daily-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;COUNT=3;BYMONTH=2"))
  (assert-occurrence-strings
    (Temporal.recurrence.occurrences daily-rule daily-start {})
    ["2026-02-01T09:00:00"
     "2026-02-02T09:00:00"
     "2026-02-03T09:00:00"])

  (local weekly-start (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
  (local weekly-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=WEEKLY;COUNT=3;BYDAY=MO;BYMONTH=2"))
  (assert-occurrence-strings
    (Temporal.recurrence.occurrences weekly-rule weekly-start {})
    ["2026-02-02T09:00:00"
     "2026-02-09T09:00:00"
     "2026-02-16T09:00:00"])

  (local monthly-start (Temporal.plain-date-time.parse "2026-01-31T10:11:12"))
  (local monthly-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=3;BYMONTH=1,3,5"))
  (assert-occurrence-strings
    (Temporal.recurrence.occurrences monthly-rule monthly-start {})
    ["2026-01-31T10:11:12"
     "2026-03-31T10:11:12"
     "2026-05-31T10:11:12"])

  (local yearly-start (Temporal.plain-date-time.parse "2028-02-29T10:11:12"))
  (local yearly-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;COUNT=3;BYMONTH=2"))
  (assert-occurrence-strings
    (Temporal.recurrence.occurrences yearly-rule yearly-start {})
    ["2028-02-29T10:11:12"
     "2029-02-28T10:11:12"
     "2030-02-28T10:11:12"])

  (assert-error #(Temporal.recurrence.occurrences
                   (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;COUNT=1;BYMONTH=3")
                   yearly-start
                   {})
                "yearly BYMONTH excluding anchor month should throw")
  (assert-error #(Temporal.recurrence.occurrences
                   (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=1;BYMONTH=1;BYDAY=MO")
                   monthly-start
                   {})
                "monthly BYDAY with BYMONTH should still throw"))

(fn recurrence-monthly-yearly-validate-first-dtstart []
  (assert-error #(Temporal.recurrence.occurrences
                   (Temporal.recurrence.from {:freq :monthly :count 1})
                   {}
                   {})
                "monthly count=1 should validate invalid DTSTART")
  (assert-error #(Temporal.recurrence.occurrences
                   (Temporal.recurrence.from {:freq :yearly})
                   "not a plain date time"
                   {:limit 1})
                "yearly limit=1 should validate invalid DTSTART"))

(fn recurrence-daily-limits-and-rejections []
  (local dtstart (Temporal.plain-date-time.parse "2026-09-22T09:00:00"))
  (local rule (Temporal.recurrence.from {:freq :daily :interval 2}))
  (local occ (Temporal.recurrence.occurrences rule dtstart {:limit 2}))
  (local first (. occ 1))
  (local second (. occ 2))
  (assert (= (# occ) 2))
  (assert (= (first:to-string) "2026-09-22T09:00:00"))
  (assert (= (second:to-string) "2026-09-24T09:00:00"))
  (assert-error #(Temporal.recurrence.from {:freq :daily :bogus true})
                "unknown recurrence option should throw")
  (assert-error #(Temporal.recurrence.occurrences {:freq :daily :count 2} dtstart {:limt 10})
                "unknown occurrence option should throw")
  (assert-error #(Temporal.recurrence.occurrences {:freq :daily :count 2} dtstart {:limit false})
                "invalid occurrence limit should throw")
  (assert-error #(Temporal.recurrence.occurrences rule dtstart {})
                "unbounded recurrence expansion should throw")
  (assert-error #(Temporal.recurrence.occurrences {:freq :monthly} dtstart {})
                "unbounded monthly recurrence expansion should throw"))

(fn recurrence-daily-by-day-filters-nonmatching-dtstart []
  (local dtstart (Temporal.plain-date-time.parse "2026-09-21T09:00:00"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;COUNT=2;BYDAY=TU"))
  (local occ (Temporal.recurrence.occurrences rule dtstart {}))
  (assert (= (# occ) 2))
  (local first (. occ 1))
  (local second (. occ 2))
  (assert (= (first:to-string) "2026-09-22T09:00:00"))
  (assert (= (second:to-string) "2026-09-29T09:00:00")))

(fn recurrence-daily-by-day-unsatisfiable-interval-throws []
  (local dtstart (Temporal.plain-date-time.parse "2026-09-21T09:00:00"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;INTERVAL=7;COUNT=1;BYDAY=TU"))
  (local err (assert-error #(Temporal.recurrence.occurrences rule dtstart {})
                           "unsatisfiable daily BYDAY recurrence should throw instead of hanging"))
  (assert (tostring err):find "unsupported temporal recurrence expansion" 1 true))

(fn natural-relative-resolution []
  (local reference (Temporal.plain-date-time.parse "2026-09-25T15:30:00"))
  (local ctx (Temporal.expression.context {:reference-plain-date-time reference
                                            :zone-id "America/New_York"}))
  (local today-result (Temporal.expression.resolve (Temporal.natural.parse "today") ctx))
  (local tomorrow-result (Temporal.expression.resolve (Temporal.natural.parse "tomorrow") ctx))
  (local in-two-weeks-result (Temporal.expression.resolve (Temporal.natural.parse "in 2 weeks") ctx))
  (assert (= (today-result.value:to-string) "2026-09-25T00:00:00"))
  (assert (= (tomorrow-result.value:to-string) "2026-09-26T00:00:00"))
  (assert (= (in-two-weeks-result.value:to-string) "2026-10-09T00:00:00")))

(fn expression-reference-instant-projects-through-zone []
  (local instant (Temporal.instant.parse "2026-09-25T00:30:00Z"))
  (local ny-ctx (Temporal.expression.context {:reference-instant instant
                                              :zone-id "America/New_York"}))
  (local tokyo-ctx (Temporal.expression.context {:reference-instant instant
                                                 :zone-id "Asia/Tokyo"}))
  (local ny-today (Temporal.expression.resolve (Temporal.natural.parse "today") ny-ctx))
  (local tokyo-today (Temporal.expression.resolve (Temporal.natural.parse "today") tokyo-ctx))
  (assert (= (ny-today.value:to-string) "2026-09-24T00:00:00"))
  (assert (= (tokyo-today.value:to-string) "2026-09-25T00:00:00")))

(fn natural-next-weekday-and-recurrence []
  (local reference (Temporal.plain-date-time.parse "2026-09-25T15:30:00"))
  (local ctx (Temporal.expression.context {:reference-plain-date-time reference
                                            :zone-id "America/New_York"}))
  (local next-tu (Temporal.expression.resolve (Temporal.natural.parse "next Tuesday") ctx))
  (assert (= (next-tu.value:to-string) "2026-09-29T00:00:00"))
  (local recurring (Temporal.natural.parse "every Tuesday"))
  (assert (= recurring.kind :recurrence))
  (assert (= recurring.rule.freq :weekly))
  (assert (= (. recurring.rule.by-day 1) :tu))
  (assert-error #(Temporal.natural.parse "around lunch sometime")
                "unsupported natural expression should throw"))

(table.insert tests {:name "standard instant round trip" :fn standard-instant-round-trip})
(table.insert tests {:name "standard plain round trip" :fn standard-plain-round-trip})
(table.insert tests {:name "standard zoned round trip" :fn standard-zoned-round-trip})
(table.insert tests {:name "standard zoned fractional round trip" :fn standard-zoned-fractional-round-trip})
(table.insert tests {:name "pattern plain date time round trip" :fn pattern-plain-date-time-round-trip})
(table.insert tests {:name "pattern literals and rejections" :fn pattern-literals-and-rejections})
(table.insert tests {:name "recurrence RRULE round trip" :fn recurrence-rrule-round-trip})
(table.insert tests {:name "recurrence BYMONTH parse and serialize" :fn recurrence-bymonth-parse-and-serialize})
(table.insert tests {:name "temporal factory wiring keeps public recurrence and natural" :fn temporal-factory-wiring-keeps-public-recurrence-and-natural})
(table.insert tests {:name "recurrence weekly occurrences" :fn recurrence-weekly-occurrences})
(table.insert tests {:name "recurrence weekly without BYDAY uses DTSTART weekday" :fn recurrence-weekly-without-by-day-uses-dtstart-weekday})
(table.insert tests {:name "recurrence monthly anchor clamps without drift" :fn recurrence-monthly-anchor-clamps-without-drift})
(table.insert tests {:name "recurrence yearly leap day anchor clamps without drift" :fn recurrence-yearly-leap-day-anchor-clamps-without-drift})
(table.insert tests {:name "recurrence monthly yearly bounds and rejections" :fn recurrence-monthly-yearly-bounds-and-rejections})
(table.insert tests {:name "recurrence BYMONTH filters occurrences" :fn recurrence-bymonth-filters-occurrences})
(table.insert tests {:name "recurrence monthly yearly validate first DTSTART" :fn recurrence-monthly-yearly-validate-first-dtstart})
(table.insert tests {:name "recurrence daily limits and rejections" :fn recurrence-daily-limits-and-rejections})
(table.insert tests {:name "recurrence daily BYDAY filters nonmatching DTSTART" :fn recurrence-daily-by-day-filters-nonmatching-dtstart})
(table.insert tests {:name "recurrence daily BYDAY unsatisfiable interval throws" :fn recurrence-daily-by-day-unsatisfiable-interval-throws})
(table.insert tests {:name "natural relative resolution" :fn natural-relative-resolution})
(table.insert tests {:name "expression reference instant projects through zone" :fn expression-reference-instant-projects-through-zone})
(table.insert tests {:name "natural next weekday and recurrence" :fn natural-next-weekday-and-recurrence})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-parsing-recurrence"
                       :tests tests})))

{:name "temporal-parsing-recurrence"
 :tests tests
 :main main}
