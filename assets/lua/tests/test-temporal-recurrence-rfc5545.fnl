(local tests [])
(local Temporal (require :temporal))

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

(fn assert-strings [actual expected]
  (assert= (# actual) (# expected))
  (each [index value (ipairs expected)]
    (local occurrence (. actual index))
    (assert= (occurrence:to-string) value)))

(fn parses-sub-daily-frequencies []
  (assert= (. (Temporal.recurrence.parse-rrule "RRULE:FREQ=SECONDLY;COUNT=2") :freq) :secondly)
  (assert= (. (Temporal.recurrence.parse-rrule "RRULE:FREQ=MINUTELY;COUNT=2") :freq) :minutely)
  (assert= (. (Temporal.recurrence.parse-rrule "RRULE:FREQ=HOURLY;COUNT=2") :freq) :hourly))

(fn parses-new-selector-lists []
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;BYSECOND=0,30;BYMINUTE=5;BYHOUR=9,17;BYYEARDAY=1,-1;BYWEEKNO=1,-1;BYMONTH=1,12;BYSETPOS=1,-1;WKST=SU"))
  (assert= (. rule :by-second 2) 30)
  (assert= (. rule :by-minute 1) 5)
  (assert= (. rule :by-hour 2) 17)
  (assert= (. rule :by-year-day 2) -1)
  (assert= (. rule :by-week-no 2) -1)
  (assert= (. rule :by-set-pos 2) -1)
  (assert= rule.week-start :su))

(fn parses-ordinal-byday []
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYDAY=1MO,-1FR;COUNT=4"))
  (assert= (. rule :by-day 1 :weekday) :mo)
  (assert= (. rule :by-day 1 :ordinal) 1)
  (assert= (. rule :by-day 2 :weekday) :fr)
  (assert= (. rule :by-day 2 :ordinal) -1))

(fn serializes-full-field-order []
  (assert= (Temporal.recurrence.to-rrule {:freq :hourly :interval 2 :count 3 :by-second [0 30] :by-minute [15] :by-hour [9] :by-day [:mo] :by-month-day [1 -1] :by-year-day [1 -1] :by-week-no [1] :by-month [1] :by-set-pos [1 -1] :week-start :su})
           "RRULE:FREQ=HOURLY;INTERVAL=2;COUNT=3;BYSECOND=0,30;BYMINUTE=15;BYHOUR=9;BYDAY=MO;BYMONTHDAY=1,-1;BYYEARDAY=1,-1;BYWEEKNO=1;BYMONTH=1;BYSETPOS=1,-1;WKST=SU"))

(fn rejects-invalid-rfc5545-rule-fields []
  (each [_ rrule (ipairs ["RRULE:FREQ=DAILY;BYSECOND=60"
                         "RRULE:FREQ=DAILY;BYMINUTE=60"
                         "RRULE:FREQ=DAILY;BYHOUR=24"
                         "RRULE:FREQ=YEARLY;BYYEARDAY=0"
                         "RRULE:FREQ=YEARLY;BYYEARDAY=367"
                         "RRULE:FREQ=YEARLY;BYWEEKNO=0"
                         "RRULE:FREQ=YEARLY;BYWEEKNO=54"
                         "RRULE:FREQ=MONTHLY;BYSETPOS=0"
                         "RRULE:FREQ=MONTHLY;BYSETPOS=367"
                         "RRULE:FREQ=MONTHLY;BYDAY=1"
                         "RRULE:FREQ=MONTHLY;BYDAY=MO1"
                         "RRULE:FREQ=WEEKLY;WKST=MO;WKST=SU"])]
    (assert-error #(Temporal.recurrence.parse-rrule rrule)
                   (.. rrule " should throw"))))

(fn reports-rfc5545-diagnostic-boundaries []
  (each [_ diagnostic (ipairs [{:rrule "RRULE:FREQ=DAILY;BYSECOND=60" :fragment "BYSECOND"}
                               {:rrule "RRULE:FREQ=DAILY;WKST=XX" :fragment "WKST"}
                               {:rrule "RRULE:FREQ=DAILY;BYDAY=0MO" :fragment "BYDAY"}
                               {:rrule "RRULE:FREQ=DAILY;BYSETPOS=0" :fragment "BYSETPOS"}])]
    (assert-error-contains #(Temporal.recurrence.parse-rrule diagnostic.rrule)
                           diagnostic.fragment
                           (.. diagnostic.rrule " should identify " diagnostic.fragment)))
  (local dtstart (Temporal.plain-date-time.parse "2026-01-01T00:00:00"))
  (local utc-until-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;COUNT=2;UNTIL=20260101T000000Z"))
  (assert-error-contains #(Temporal.recurrence.occurrences utc-until-rule dtstart)
                         "UTC UNTIL"
                         "UTC UNTIL should report the unsupported boundary")
  (local unbounded-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY"))
  (local unbounded-error (assert-error #(Temporal.recurrence.occurrences unbounded-rule dtstart)
                                       "unbounded expansion should throw"))
  (local text (tostring unbounded-error))
  (assert (text:find "COUNT" 1 true))
  (assert (text:find "local UNTIL" 1 true))
  (assert (text:find ":limit" 1 true)))

(fn expands-last-friday-of-month []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYDAY=-1FR;COUNT=3"))
  (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-30T09:00:00" "2026-02-27T09:00:00" "2026-03-27T09:00:00"]))

(fn expands-negative-month-day []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=3"))
  (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-31T09:00:00" "2026-02-28T09:00:00" "2026-03-31T09:00:00"]))

(fn applies-bysetpos-after-sorting []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=4"))
  (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-01T09:00:00" "2026-01-30T09:00:00" "2026-02-02T09:00:00" "2026-02-27T09:00:00"]))

(fn expands-year-day-selectors []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;BYYEARDAY=1,-1;COUNT=4"))
  (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-01T09:00:00" "2026-12-31T09:00:00" "2027-01-01T09:00:00" "2027-12-31T09:00:00"]))

(fn expands-yearly-bymonth-buckets-with-default-month-day []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;BYMONTH=3;COUNT=2"))
  (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-03-01T09:00:00" "2027-03-01T09:00:00"]))

(fn orders-generated-month-day-candidates-chronologically []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-31T10:11:12"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;COUNT=4;BYMONTHDAY=15,1"))
  (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-02-01T10:11:12" "2026-02-15T10:11:12" "2026-03-01T10:11:12" "2026-03-15T10:11:12"]))

(fn expands-negative-week-number-selectors []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;BYWEEKNO=-1;BYDAY=MO;COUNT=2"))
  (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-12-28T09:00:00" "2027-12-27T09:00:00"]))

(fn applies-week-start-to-weekly-intervals []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-07T09:00:00"))
  (local monday-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=SU;COUNT=3"))
  (local sunday-rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=SU;COUNT=3;WKST=SU"))
  (assert-strings (Temporal.recurrence.occurrences monday-rule dtstart) ["2026-01-11T09:00:00" "2026-01-25T09:00:00" "2026-02-08T09:00:00"])
  (assert-strings (Temporal.recurrence.occurrences sunday-rule dtstart) ["2026-01-18T09:00:00" "2026-02-01T09:00:00" "2026-02-15T09:00:00"]))

(fn applies-default-week-start-to-weekly-byday-intervals []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-07T09:00:00"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO;COUNT=3"))
  (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-19T09:00:00" "2026-02-02T09:00:00" "2026-02-16T09:00:00"]))

(fn applies-yearly-ordinal-byday-within-bymonth []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU;COUNT=1"))
  (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-03-08T09:00:00"]))

(fn rejects-unsatisfiable-count-only-selector-intersections []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;BYYEARDAY=366;BYMONTH=2;COUNT=1"))
  (local err (assert-error #(Temporal.recurrence.occurrences rule dtstart)))
  (assert (tostring err):find "unsupported temporal recurrence expansion" 1 true))

(fn expands-hourly-frequency []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-01T09:30:00"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=HOURLY;INTERVAL=2;COUNT=4"))
  (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-01T09:30:00" "2026-01-01T11:30:00" "2026-01-01T13:30:00" "2026-01-01T15:30:00"]))

(fn expands-minutely-frequency-across-hour []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-01T23:58:00"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MINUTELY;COUNT=4"))
  (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-01T23:58:00" "2026-01-01T23:59:00" "2026-01-02T00:00:00" "2026-01-02T00:01:00"]))

(fn expands-secondly-frequency-across-minute []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-01T00:00:58"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=SECONDLY;COUNT=4"))
  (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-01T00:00:58" "2026-01-01T00:00:59" "2026-01-01T00:01:00" "2026-01-01T00:01:01"]))

(fn applies-time-selectors []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-01T00:00:00"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;BYHOUR=9,17;BYMINUTE=15;BYSECOND=30;COUNT=4"))
  (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-01T09:15:30" "2026-01-01T17:15:30" "2026-01-02T09:15:30" "2026-01-02T17:15:30"]))

(fn applies-date-selectors-to-sub-daily-candidates []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-05T09:00:00"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=HOURLY;BYDAY=TU;COUNT=1"))
  (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-06T00:00:00"]))

(fn rejects-unsupported-sub-daily-date-selectors []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-05T09:00:00"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=HOURLY;BYMONTH=2;COUNT=1"))
  (local err (assert-error #(Temporal.recurrence.occurrences rule dtstart)))
  (assert (tostring err):find "unsupported temporal recurrence expansion" 1 true))

(fn expands-hourly-byminute-candidates-before-until []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-01T09:30:00"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=HOURLY;BYMINUTE=0;UNTIL=20260101T101500"))
  (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-01T10:00:00"]))

(fn expands-minutely-bysecond-candidates-before-until []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-01T09:00:30"))
  (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=MINUTELY;BYSECOND=0;UNTIL=20260101T090115"))
  (assert-strings (Temporal.recurrence.occurrences rule dtstart) ["2026-01-01T09:01:00"]))

(fn combines-count-limit-and-until-bounds []
  (local dtstart (Temporal.plain-date-time.parse "2026-01-01T09:00:00"))
  (local count-first (Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;COUNT=2"))
  (assert-strings (Temporal.recurrence.occurrences count-first dtstart {:limit 5})
                  ["2026-01-01T09:00:00" "2026-01-02T09:00:00"])
  (local limit-first (Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;COUNT=5"))
  (assert-strings (Temporal.recurrence.occurrences limit-first dtstart {:limit 2})
                  ["2026-01-01T09:00:00" "2026-01-02T09:00:00"])
  (local inclusive-until (Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;UNTIL=20260102T090000"))
  (assert-strings (Temporal.recurrence.occurrences inclusive-until dtstart)
                  ["2026-01-01T09:00:00" "2026-01-02T09:00:00"])
  (local selector-heavy (Temporal.recurrence.parse-rrule "RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;UNTIL=20260227T090000"))
  (assert-strings (Temporal.recurrence.occurrences selector-heavy dtstart)
                  ["2026-01-30T09:00:00" "2026-02-27T09:00:00"]))

(table.insert tests {:name "parses sub daily frequencies" :fn parses-sub-daily-frequencies})
(table.insert tests {:name "parses new selector lists" :fn parses-new-selector-lists})
(table.insert tests {:name "parses ordinal BYDAY" :fn parses-ordinal-byday})
(table.insert tests {:name "serializes full field order" :fn serializes-full-field-order})
(table.insert tests {:name "rejects invalid RFC5545 rule fields" :fn rejects-invalid-rfc5545-rule-fields})
(table.insert tests {:name "reports RFC5545 diagnostic boundaries" :fn reports-rfc5545-diagnostic-boundaries})
(table.insert tests {:name "expands last Friday of month" :fn expands-last-friday-of-month})
(table.insert tests {:name "expands negative month day" :fn expands-negative-month-day})
(table.insert tests {:name "applies BYSETPOS after sorting" :fn applies-bysetpos-after-sorting})
(table.insert tests {:name "expands year day selectors" :fn expands-year-day-selectors})
(table.insert tests {:name "expands yearly BYMONTH buckets with default month day" :fn expands-yearly-bymonth-buckets-with-default-month-day})
(table.insert tests {:name "orders generated month day candidates chronologically" :fn orders-generated-month-day-candidates-chronologically})
(table.insert tests {:name "expands negative week number selectors" :fn expands-negative-week-number-selectors})
(table.insert tests {:name "applies week start to weekly intervals" :fn applies-week-start-to-weekly-intervals})
(table.insert tests {:name "applies default week start to weekly BYDAY intervals" :fn applies-default-week-start-to-weekly-byday-intervals})
(table.insert tests {:name "applies yearly ordinal BYDAY within BYMONTH" :fn applies-yearly-ordinal-byday-within-bymonth})
(table.insert tests {:name "rejects unsatisfiable count-only selector intersections" :fn rejects-unsatisfiable-count-only-selector-intersections})
(table.insert tests {:name "expands hourly frequency" :fn expands-hourly-frequency})
(table.insert tests {:name "expands minutely frequency across hour" :fn expands-minutely-frequency-across-hour})
(table.insert tests {:name "expands secondly frequency across minute" :fn expands-secondly-frequency-across-minute})
(table.insert tests {:name "applies time selectors" :fn applies-time-selectors})
(table.insert tests {:name "applies date selectors to sub daily candidates" :fn applies-date-selectors-to-sub-daily-candidates})
(table.insert tests {:name "rejects unsupported sub daily date selectors" :fn rejects-unsupported-sub-daily-date-selectors})
(table.insert tests {:name "expands hourly BYMINUTE candidates before UNTIL" :fn expands-hourly-byminute-candidates-before-until})
(table.insert tests {:name "expands minutely BYSECOND candidates before UNTIL" :fn expands-minutely-bysecond-candidates-before-until})
(table.insert tests {:name "combines COUNT limit and UNTIL bounds" :fn combines-count-limit-and-until-bounds})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-recurrence-rfc5545"
                       :tests tests})))

{:name "temporal-recurrence-rfc5545"
 :tests tests
 :main main}
