(local tests [])
(local Temporal (require :temporal))

(fn assert= [actual expected message]
  (assert (= actual expected) (or message (.. "expected " (tostring expected) ", got " (tostring actual)))))

(fn assert-error [f message]
  (local (ok err) (pcall f))
  (assert (not ok) message)
  err)

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

(fn rejects-unsupported-rfc5545-occurrence-selectors []
  (local dtstart (Temporal.plain-date-time.parse "2026-09-22T09:00:00"))
  (each [_ rrule (ipairs ["RRULE:FREQ=DAILY;COUNT=1;BYSECOND=30"
                         "RRULE:FREQ=DAILY;COUNT=1;BYMINUTE=30"
                         "RRULE:FREQ=DAILY;COUNT=1;BYHOUR=17"
                         "RRULE:FREQ=YEARLY;COUNT=1;BYYEARDAY=1"
                         "RRULE:FREQ=YEARLY;COUNT=1;BYWEEKNO=1"
                         "RRULE:FREQ=MONTHLY;COUNT=1;BYSETPOS=1"
                         "RRULE:FREQ=WEEKLY;COUNT=1;WKST=SU"
                         "RRULE:FREQ=MONTHLY;COUNT=1;BYDAY=1MO"
                         "RRULE:FREQ=MONTHLY;COUNT=1;BYMONTHDAY=-1"])]
    (local err
      (assert-error #(Temporal.recurrence.occurrences
                       (Temporal.recurrence.parse-rrule rrule)
                       dtstart
                       {})
                    (.. rrule " should throw during occurrence expansion")))
    (assert (tostring err):find "unsupported temporal recurrence expansion" 1 true)))

(table.insert tests {:name "parses sub daily frequencies" :fn parses-sub-daily-frequencies})
(table.insert tests {:name "parses new selector lists" :fn parses-new-selector-lists})
(table.insert tests {:name "parses ordinal BYDAY" :fn parses-ordinal-byday})
(table.insert tests {:name "serializes full field order" :fn serializes-full-field-order})
(table.insert tests {:name "rejects invalid RFC5545 rule fields" :fn rejects-invalid-rfc5545-rule-fields})
(table.insert tests {:name "rejects unsupported RFC5545 occurrence selectors" :fn rejects-unsupported-rfc5545-occurrence-selectors})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-recurrence-rfc5545"
                       :tests tests})))

{:name "temporal-recurrence-rfc5545"
 :tests tests
 :main main}
