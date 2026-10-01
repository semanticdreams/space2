(local tests [])

(fn assert-error-contains [f fragment message]
  (local (ok err) (pcall f))
  (assert (not ok) message)
  (assert (err:match fragment) (.. message ": expected error containing " fragment ", got " (tostring err)))
  err)

(fn assert-array= [actual expected message]
  (assert (= (length actual) (length expected)) message)
  (each [index expected-value (ipairs expected)]
    (assert (= (. actual index) expected-value) message)))

(fn plain [Temporal iso]
  (Temporal.plain-date-time.parse iso))

(fn assert-local-fields [actual expected message]
  (each [key expected-value (pairs expected)]
    (assert (= (. actual key) expected-value)
            (.. message ": expected " (tostring key) "=" (tostring expected-value)
                ", got " (tostring (. actual key))))))

(fn supported-calendars-are-exact []
  (local Temporal (require :temporal))
  (assert-array= (Temporal.calendar.supported-calendars) ["buddhist" "gregory" "japanese"]
                 "supported calendars should be exact and sorted"))

(fn gregorian-round-trip []
  (local Temporal (require :temporal))
  (local iso (plain Temporal "2026-10-01T09:30:00"))
  (local localized (Temporal.calendar.from-iso iso {:calendar "gregory"}))
  (assert-local-fields localized
                       {:kind :temporal-calendar-date-time
                        :calendar "gregory"
                        :era "ce"
                        :year 2026
                        :month 10
                        :day 1
                        :hour 9
                        :minute 30
                        :second 0
                        :nanosecond 0}
                       "gregory from-iso")
  (local round-tripped (Temporal.calendar.to-iso localized))
  (assert (= (round-tripped:to-string) "2026-10-01T09:30:00")))

(fn buddhist-round-trip []
  (local Temporal (require :temporal))
  (local iso (plain Temporal "2026-10-01T09:30:00"))
  (local localized (Temporal.calendar.from-iso iso {:calendar "buddhist"}))
  (assert-local-fields localized {:calendar "buddhist" :era "be" :year 2569}
                       "buddhist from-iso")
  (local round-tripped (Temporal.calendar.to-iso localized))
  (assert (= (round-tripped:to-string) "2026-10-01T09:30:00")))

(fn assert-japanese-date [Temporal iso era year]
  (local localized (Temporal.calendar.from-iso (plain Temporal iso) {:calendar "japanese"}))
  (assert-local-fields localized {:calendar "japanese" :era era :year year}
                       (.. "japanese from-iso " iso))
  (local round-tripped (Temporal.calendar.to-iso localized))
  (assert (= (round-tripped:to-string) iso)))

(fn japanese-era-boundaries []
  (local Temporal (require :temporal))
  (assert-japanese-date Temporal "1926-12-25T00:00:00" "showa" 1)
  (assert-japanese-date Temporal "1989-01-07T00:00:00" "showa" 64)
  (assert-japanese-date Temporal "1989-01-08T00:00:00" "heisei" 1)
  (assert-japanese-date Temporal "2019-04-30T00:00:00" "heisei" 31)
  (assert-japanese-date Temporal "2019-05-01T00:00:00" "reiwa" 1)
  (assert-japanese-date Temporal "2026-10-01T09:30:00" "reiwa" 8))

(fn japanese-errors-are-loud []
  (local Temporal (require :temporal))
  (assert-error-contains #(Temporal.calendar.from-iso (plain Temporal "1926-12-24T00:00:00")
                                                     {:calendar "japanese"})
                         "unsupported Japanese era range"
                         "pre-Showa date should throw")
  (assert-error-contains #(Temporal.calendar.to-iso {:kind :temporal-calendar-date-time
                                                    :calendar "japanese"
                                                    :era "reiwa"
                                                    :year 1
                                                    :month 4
                                                    :day 30
                                                    :hour 0
                                                    :minute 0
                                                    :second 0
                                                    :nanosecond 0})
                         "inconsistent Japanese era/date fields"
                         "Reiwa date before start should throw"))

(fn validation-errors-are-loud []
  (local Temporal (require :temporal))
  (local iso (plain Temporal "2026-10-01T09:30:00"))
  (assert-error-contains #(Temporal.calendar.from-iso iso nil)
                         "missing calendar"
                         "from-iso should require options with calendar")
  (assert-error-contains #(Temporal.calendar.from-iso iso {})
                         "missing calendar"
                         "from-iso should require calendar option")
  (assert-error-contains #(Temporal.calendar.from-iso iso {:calendar "gregory" :locale "en-US"})
                         "unknown calendar option"
                         "from-iso should reject unknown option keys")
  (assert-error-contains #(Temporal.calendar.to-iso {:kind :temporal-calendar-date-time
                                                    :calendar "gregory"
                                                    :era "ce"
                                                    :year 2026
                                                    :month 10
                                                    :day 1
                                                    :hour 9
                                                    :minute 30
                                                    :second 0
                                                    :nanosecond 0
                                                    :locale "en-US"})
                         "unknown calendar record key"
                         "to-iso should reject unknown record keys")
  (assert-error-contains #(Temporal.calendar.from-iso iso {:calendar "islamic"})
                         "unsupported calendar"
                         "unsupported calendar should throw")
  (assert-error-contains #(Temporal.calendar.to-iso {:kind :temporal-calendar-date-time
                                                    :calendar "gregory"
                                                    :era "ce"
                                                    :year "2026"
                                                    :month 10
                                                    :day 1
                                                    :hour 9
                                                    :minute 30
                                                    :second 0
                                                    :nanosecond 0})
                         "invalid calendar field type"
                         "invalid field type should throw"))

(fn seed-era-ranges-are-loud []
  (local Temporal (require :temporal))
  (local pre-seed {:fields (fn [_self]
                            {:year 0
                             :month 12
                             :day 31
                             :hour 0
                             :minute 0
                             :second 0
                             :nanosecond 0})})
  (assert-error-contains #(Temporal.calendar.from-iso pre-seed {:calendar "gregory"})
                         "unsupported Gregorian era range"
                         "Gregorian from-iso before seed era start should throw")
  (assert-error-contains #(Temporal.calendar.from-iso pre-seed {:calendar "buddhist"})
                         "unsupported Buddhist era range"
                         "Buddhist from-iso before seed era start should throw")
  (assert-error-contains #(Temporal.calendar.to-iso {:kind :temporal-calendar-date-time
                                                    :calendar "gregory"
                                                    :era "ce"
                                                    :year 0
                                                    :month 12
                                                    :day 31
                                                    :hour 0
                                                    :minute 0
                                                    :second 0
                                                    :nanosecond 0})
                         "unsupported Gregorian era range"
                         "Gregorian localized date before seed era start should throw")
  (assert-error-contains #(Temporal.calendar.to-iso {:kind :temporal-calendar-date-time
                                                    :calendar "buddhist"
                                                    :era "be"
                                                    :year 543
                                                    :month 12
                                                    :day 31
                                                    :hour 0
                                                    :minute 0
                                                    :second 0
                                                    :nanosecond 0})
                         "unsupported Buddhist era range"
                         "Buddhist localized date before seed era start should throw"))

(table.insert tests {:name "supported calendars are exact" :fn supported-calendars-are-exact})
(table.insert tests {:name "gregorian round trip" :fn gregorian-round-trip})
(table.insert tests {:name "buddhist round trip" :fn buddhist-round-trip})
(table.insert tests {:name "japanese era boundaries" :fn japanese-era-boundaries})
(table.insert tests {:name "japanese errors are loud" :fn japanese-errors-are-loud})
(table.insert tests {:name "validation errors are loud" :fn validation-errors-are-loud})
(table.insert tests {:name "seed era ranges are loud" :fn seed-era-ranges-are-loud})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-calendar"
                       :tests tests})))

{:name "temporal-calendar"
 :tests tests
 :main main}
