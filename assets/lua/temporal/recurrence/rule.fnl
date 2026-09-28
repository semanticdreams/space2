(local valid-freq
  {:secondly true
   :minutely true
   :hourly true
   :daily true
   :weekly true
   :monthly true
   :yearly true})

(local valid-options
  {:freq true
   :interval true
    :count true
    :until true
    :by-second true
    :by-minute true
    :by-hour true
    :by-day true
    :by-month true
    :by-month-day true
    :by-year-day true
    :by-week-no true
    :by-set-pos true
    :week-start true})

(local valid-occurrence-options
  {:limit true})

(local day-to-rrule {:mo "MO" :tu "TU" :we "WE" :th "TH" :fr "FR" :sa "SA" :su "SU"})
(local rrule-to-day {"MO" :mo "TU" :tu "WE" :we "TH" :th "FR" :fr "SA" :sa "SU" :su})
(local freq-to-rrule {:secondly "SECONDLY" :minutely "MINUTELY" :hourly "HOURLY" :daily "DAILY" :weekly "WEEKLY" :monthly "MONTHLY" :yearly "YEARLY"})
(local rrule-to-freq {"SECONDLY" :secondly "MINUTELY" :minutely "HOURLY" :hourly "DAILY" :daily "WEEKLY" :weekly "MONTHLY" :monthly "YEARLY" :yearly})
(local day-to-number {:mo 1 :tu 2 :we 3 :th 4 :fr 5 :sa 6 :su 7})
(local number-to-day [:mo :tu :we :th :fr :sa :su])

(fn positive-integer? [value]
  (and (= (type value) :number)
       (= value (math.floor value))
       (> value 0)))

(fn validate-positive-integer [value name]
  (when (not (positive-integer? value))
    (error (.. "invalid temporal recurrence " name)))
  value)

(fn validate-day [day]
  (when (not (. day-to-rrule day))
    (error "invalid temporal recurrence BYDAY"))
  day)

(fn integer? [value]
  (and (= (type value) :number)
       (= value (math.floor value))))

(fn validate-integer-range [value name min max]
  (when (not (and (integer? value)
                  (>= value min)
                  (<= value max)))
    (error (.. "invalid temporal recurrence " name)))
  value)

(fn validate-nonzero-integer-range [value name min max]
  (when (not (and (integer? value)
                  (not= value 0)
                  (>= value min)
                  (<= value max)))
    (error (.. "invalid temporal recurrence " name)))
  value)

(fn validate-week-start [day]
  (when (not (. day-to-rrule day))
    (error "invalid temporal recurrence WKST"))
  day)

(fn validate-by-day-entry [entry]
  (if (= (type entry) :table)
      (do
        (validate-day entry.weekday)
        (validate-nonzero-integer-range entry.ordinal "BYDAY" -53 53)
        {:weekday entry.weekday :ordinal entry.ordinal})
      (validate-day entry)))

(fn validate-month [month]
  (validate-integer-range month "BYMONTH" 1 12))

(fn validate-second [second]
  (validate-integer-range second "BYSECOND" 0 59))

(fn validate-minute [minute]
  (validate-integer-range minute "BYMINUTE" 0 59))

(fn validate-hour [hour]
  (validate-integer-range hour "BYHOUR" 0 23))

(fn validate-month-day [day]
  (validate-nonzero-integer-range day "BYMONTHDAY" -31 31))

(fn validate-year-day [day]
  (validate-nonzero-integer-range day "BYYEARDAY" -366 366))

(fn validate-week-no [week]
  (validate-nonzero-integer-range week "BYWEEKNO" -53 53))

(fn validate-set-pos [position]
  (validate-nonzero-integer-range position "BYSETPOS" -366 366))

(fn normalize-integer-list [items name validator]
  (when (not= items nil)
    (when (not= (type items) :table)
      (error (.. "invalid temporal recurrence " name)))
    (local normalized [])
    (each [_ value (ipairs items)]
      (table.insert normalized (validator value)))
    (when (= (# normalized) 0)
      (error (.. "invalid temporal recurrence " name)))
    normalized))

(fn normalize-by-day [days]
  (when (not= days nil)
    (when (not= (type days) :table)
      (error "invalid temporal recurrence BYDAY"))
    (local normalized [])
    (each [_ day (ipairs days)]
      (table.insert normalized (validate-by-day-entry day)))
    (when (= (# normalized) 0)
      (error "invalid temporal recurrence BYDAY"))
    normalized))

(fn normalize-by-month [months]
  (when (not= months nil)
    (when (not= (type months) :table)
      (error "invalid temporal recurrence BYMONTH"))
    (local normalized [])
    (each [_ month (ipairs months)]
      (table.insert normalized (validate-month month)))
    (when (= (# normalized) 0)
      (error "invalid temporal recurrence BYMONTH"))
    normalized))

(fn normalize-by-month-day [days]
  (normalize-integer-list days "BYMONTHDAY" validate-month-day))

(fn from [options]
  (when (not= (type options) :table)
    (error "temporal recurrence options must be a table"))
  (each [key _value (pairs options)]
    (when (not (. valid-options key))
      (error (.. "unknown temporal recurrence option: " (tostring key)))))
  (when (not (. valid-freq options.freq))
    (error "invalid temporal recurrence frequency"))
  (local interval (if (= options.interval nil)
                       1
                       (validate-positive-integer options.interval "interval")))
  (local week-start (if (= options.week-start nil)
                        :mo
                        (validate-week-start options.week-start)))
  (local rule {:freq options.freq :interval interval :week-start week-start})
  (when (not= options.count nil)
    (set rule.count (validate-positive-integer options.count "count")))
  (when (not= options.until nil)
    (when (not= (type options.until) :string)
      (error "invalid temporal recurrence UNTIL"))
    (set rule.until options.until))
  (local by-second (normalize-integer-list options.by-second "BYSECOND" validate-second))
  (when by-second
    (set rule.by-second by-second))
  (local by-minute (normalize-integer-list options.by-minute "BYMINUTE" validate-minute))
  (when by-minute
    (set rule.by-minute by-minute))
  (local by-hour (normalize-integer-list options.by-hour "BYHOUR" validate-hour))
  (when by-hour
    (set rule.by-hour by-hour))
  (local by-day (normalize-by-day options.by-day))
  (when by-day
    (set rule.by-day by-day))
  (local by-month (normalize-by-month options.by-month))
  (when by-month
    (set rule.by-month by-month))
  (local by-month-day (normalize-by-month-day options.by-month-day))
  (when by-month-day
    (set rule.by-month-day by-month-day))
  (local by-year-day (normalize-integer-list options.by-year-day "BYYEARDAY" validate-year-day))
  (when by-year-day
    (set rule.by-year-day by-year-day))
  (local by-week-no (normalize-integer-list options.by-week-no "BYWEEKNO" validate-week-no))
  (when by-week-no
    (set rule.by-week-no by-week-no))
  (local by-set-pos (normalize-integer-list options.by-set-pos "BYSETPOS" validate-set-pos))
  (when by-set-pos
    (set rule.by-set-pos by-set-pos))
  rule)

(fn split-nonempty [text separator]
  (local parts [])
  (var start 1)
  (var done false)
  (while (not done)
    (local found (text:find separator start true))
    (local part (if found
                    (text:sub start (- found 1))
                    (text:sub start)))
    (when (= part "")
      (error "invalid RRULE"))
    (table.insert parts part)
    (if found
        (set start (+ found 1))
        (set done true)))
  parts)

(fn parse-positive-integer [text name]
  (when (or (= text "") (not (text:match "^%d+$")))
    (error (.. "invalid RRULE " name)))
  (validate-positive-integer (tonumber text) name))

(fn parse-signed-integer [text name]
  (when (or (= text "") (not (text:match "^[+-]?%d+$")))
    (error (.. "invalid RRULE " name)))
  (tonumber text))

(fn parse-integer-list [text name validator]
  (local parsed [])
  (each [_ item (ipairs (split-nonempty text ","))]
    (table.insert parsed (validator (parse-signed-integer item name))))
  parsed)

(fn parse-by-day-token [item]
  (local simple (. rrule-to-day item))
  (if simple
      simple
      (do
        (local ordinal-text (item:match "^([+-]?%d+)[A-Z][A-Z]$"))
        (local weekday-text (item:match "^[+-]?%d+([A-Z][A-Z])$"))
        (when (or (not ordinal-text) (not weekday-text))
          (error "invalid RRULE BYDAY"))
        (local weekday (. rrule-to-day weekday-text))
        (when (not weekday)
          (error "invalid RRULE BYDAY"))
        {:weekday weekday
         :ordinal (validate-nonzero-integer-range (parse-signed-integer ordinal-text "BYDAY") "BYDAY" -53 53)})))

(fn parse-by-day [text]
  (local days [])
  (each [_ item (ipairs (split-nonempty text ","))]
    (table.insert days (parse-by-day-token item)))
  days)

(fn parse-by-month [text]
  (local months [])
  (each [_ item (ipairs (split-nonempty text ","))]
    (table.insert months (validate-month (parse-positive-integer item "BYMONTH"))))
  months)

(fn parse-by-month-day [text]
  (parse-integer-list text "BYMONTHDAY" validate-month-day))

(fn compact-local-until? [text]
  (and (= (type text) :string)
       (not= (text:match "^%d%d%d%d%d%d%d%dT%d%d%d%d%d%d$") nil)))

(fn compact-utc-until? [text]
  (and (= (type text) :string)
       (not= (text:match "^%d%d%d%d%d%d%d%dT%d%d%d%d%d%dZ$") nil)))

(fn compact-local-until->iso [text]
  (.. (text:sub 1 4)
      "-"
      (text:sub 5 6)
      "-"
      (text:sub 7 8)
      "T"
      (text:sub 10 11)
      ":"
      (text:sub 12 13)
      ":"
      (text:sub 14 15)))

(fn parse-local-until [standard text]
  (local (ok value) (pcall standard.parse-plain-date-time (compact-local-until->iso text)))
  (when (not ok)
    (error "invalid temporal recurrence UNTIL"))
  value)

(fn parse-until [standard text]
  (if (compact-local-until? text)
      {:kind :plain-date-time :value (parse-local-until standard text)}
      (compact-utc-until? text)
      {:kind :instant}
      (error "invalid temporal recurrence UNTIL")))

(fn parse-rrule [text]
  (assert (= (type text) :string) "RRULE text must be a string")
  (when (not= (text:sub 1 6) "RRULE:")
    (error "invalid RRULE prefix"))
  (local body (text:sub 7))
  (when (= body "")
    (error "invalid RRULE"))
  (local seen {})
  (local options {})
  (each [_ pair (ipairs (split-nonempty body ";"))]
    (local equals (pair:find "=" 1 true))
    (when (not equals)
      (error "invalid RRULE"))
    (local key (pair:sub 1 (- equals 1)))
    (local value (pair:sub (+ equals 1)))
    (when (or (= key "") (= value ""))
      (error "invalid RRULE"))
    (when (. seen key)
      (error "duplicate RRULE key"))
    (set (. seen key) true)
    (if (= key "FREQ")
        (do
          (local freq (. rrule-to-freq value))
          (when (not freq)
            (error "invalid RRULE FREQ"))
          (set options.freq freq))
        (= key "INTERVAL")
        (set options.interval (parse-positive-integer value "INTERVAL"))
        (= key "COUNT")
        (set options.count (parse-positive-integer value "COUNT"))
        (= key "UNTIL")
        (set options.until value)
        (= key "BYSECOND")
        (set options.by-second (parse-integer-list value "BYSECOND" validate-second))
        (= key "BYMINUTE")
        (set options.by-minute (parse-integer-list value "BYMINUTE" validate-minute))
        (= key "BYHOUR")
        (set options.by-hour (parse-integer-list value "BYHOUR" validate-hour))
        (= key "BYDAY")
        (set options.by-day (parse-by-day value))
        (= key "BYMONTH")
        (set options.by-month (parse-by-month value))
        (= key "BYMONTHDAY")
        (set options.by-month-day (parse-by-month-day value))
        (= key "BYYEARDAY")
        (set options.by-year-day (parse-integer-list value "BYYEARDAY" validate-year-day))
        (= key "BYWEEKNO")
        (set options.by-week-no (parse-integer-list value "BYWEEKNO" validate-week-no))
        (= key "BYSETPOS")
        (set options.by-set-pos (parse-integer-list value "BYSETPOS" validate-set-pos))
        (= key "WKST")
        (do
          (local week-start (. rrule-to-day value))
          (when (not week-start)
            (error "invalid RRULE WKST"))
          (set options.week-start week-start))
        (error "unknown RRULE key")))
  (from options))

(fn join [parts separator]
  (var result "")
  (each [index part (ipairs parts)]
    (if (= index 1)
        (set result part)
        (set result (.. result separator part))))
  result)

(fn serialize-by-day [days]
  (local parts [])
  (each [_ entry (ipairs days)]
    (local day (validate-by-day-entry entry))
    (if (= (type day) :table)
        (table.insert parts (.. day.ordinal (. day-to-rrule day.weekday)))
        (table.insert parts (. day-to-rrule day))))
  (join parts ","))

(fn serialize-integer-list [items validator]
  (local parts [])
  (each [_ value (ipairs items)]
    (table.insert parts (tostring (validator value))))
  (join parts ","))

(fn serialize-by-month [months]
  (serialize-integer-list months validate-month))

(fn serialize-by-month-day [days]
  (serialize-integer-list days validate-month-day))

(fn to-rrule [rule]
  (local normalized (from rule))
  (local parts [(.. "FREQ=" (. freq-to-rrule normalized.freq))])
  (when (not= normalized.interval 1)
    (table.insert parts (.. "INTERVAL=" normalized.interval)))
  (when normalized.count
    (table.insert parts (.. "COUNT=" normalized.count)))
  (when normalized.until
    (table.insert parts (.. "UNTIL=" normalized.until)))
  (when normalized.by-second
    (table.insert parts (.. "BYSECOND=" (serialize-integer-list normalized.by-second validate-second))))
  (when normalized.by-minute
    (table.insert parts (.. "BYMINUTE=" (serialize-integer-list normalized.by-minute validate-minute))))
  (when normalized.by-hour
    (table.insert parts (.. "BYHOUR=" (serialize-integer-list normalized.by-hour validate-hour))))
  (when normalized.by-day
    (table.insert parts (.. "BYDAY=" (serialize-by-day normalized.by-day))))
  (when normalized.by-month-day
    (table.insert parts (.. "BYMONTHDAY=" (serialize-by-month-day normalized.by-month-day))))
  (when normalized.by-year-day
    (table.insert parts (.. "BYYEARDAY=" (serialize-integer-list normalized.by-year-day validate-year-day))))
  (when normalized.by-week-no
    (table.insert parts (.. "BYWEEKNO=" (serialize-integer-list normalized.by-week-no validate-week-no))))
  (when normalized.by-month
    (table.insert parts (.. "BYMONTH=" (serialize-by-month normalized.by-month))))
  (when normalized.by-set-pos
    (table.insert parts (.. "BYSETPOS=" (serialize-integer-list normalized.by-set-pos validate-set-pos))))
  (when (not= normalized.week-start :mo)
    (table.insert parts (.. "WKST=" (. day-to-rrule (validate-week-start normalized.week-start)))))
  (.. "RRULE:" (join parts ";")))

(fn normalize-occurrence-options [options]
  (if (= options nil)
      {:has-limit false}
      (do
        (when (not= (type options) :table)
          (error "temporal recurrence occurrence options must be a table"))
        (var has-limit false)
        (each [key _value (pairs options)]
          (when (not (. valid-occurrence-options key))
            (error (.. "unknown temporal recurrence occurrence option: " (tostring key))))
          (when (= key :limit)
            (set has-limit true)))
        {:limit options.limit :has-limit has-limit})))

(fn numeric-occurrence-limit [recurrence-rule options]
  (when options.has-limit
    (validate-positive-integer options.limit "limit"))
  (if (and recurrence-rule.count options.has-limit)
      (math.min recurrence-rule.count options.limit)
      recurrence-rule.count
      recurrence-rule.count
      options.limit))

(fn occurrence-bounds [standard recurrence-rule options]
  (local limit (numeric-occurrence-limit recurrence-rule options))
  (var until nil)
  (when recurrence-rule.until
    (local parsed (parse-until standard recurrence-rule.until))
    (if (= parsed.kind :plain-date-time)
        (set until parsed.value)
        (= parsed.kind :instant)
        (error "unsupported temporal recurrence UTC UNTIL")))
  (when (and (= limit nil) (= until nil))
    (error "temporal recurrence expansion requires COUNT, local UNTIL, or :limit"))
  {:limit limit :until until})

{:from from
 :parse-rrule parse-rrule
 :to-rrule to-rrule
 :parse-until parse-until
 :normalize-occurrence-options normalize-occurrence-options
 :occurrence-bounds occurrence-bounds
 :day-to-number day-to-number
 :number-to-day number-to-day}
