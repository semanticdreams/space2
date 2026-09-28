(local valid-freq
  {:daily true
   :weekly true
   :monthly true
   :yearly true})

(local valid-options
  {:freq true
   :interval true
   :count true
   :until true
   :by-day true
   :by-month true
   :by-month-day true})

(local valid-occurrence-options
  {:limit true})

(local day-to-rrule {:mo "MO" :tu "TU" :we "WE" :th "TH" :fr "FR" :sa "SA" :su "SU"})
(local rrule-to-day {"MO" :mo "TU" :tu "WE" :we "TH" :th "FR" :fr "SA" :sa "SU" :su})
(local freq-to-rrule {:daily "DAILY" :weekly "WEEKLY" :monthly "MONTHLY" :yearly "YEARLY"})
(local rrule-to-freq {"DAILY" :daily "WEEKLY" :weekly "MONTHLY" :monthly "YEARLY" :yearly})
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

(fn validate-month [month]
  (when (not (and (= (type month) :number)
                  (= month (math.floor month))
                  (>= month 1)
                  (<= month 12)))
    (error "invalid temporal recurrence BYMONTH"))
  month)

(fn normalize-by-day [days]
  (when (not= days nil)
    (when (not= (type days) :table)
      (error "invalid temporal recurrence BYDAY"))
    (local normalized [])
    (each [_ day (ipairs days)]
      (table.insert normalized (validate-day day)))
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

(fn validate-month-day [day]
  (when (not (and (= (type day) :number)
                  (= day (math.floor day))
                  (>= day 1)
                  (<= day 31)))
    (error "invalid temporal recurrence BYMONTHDAY"))
  day)

(fn normalize-by-month-day [days]
  (when (not= days nil)
    (when (not= (type days) :table)
      (error "invalid temporal recurrence BYMONTHDAY"))
    (local normalized [])
    (each [_ day (ipairs days)]
      (table.insert normalized (validate-month-day day)))
    (when (= (# normalized) 0)
      (error "invalid temporal recurrence BYMONTHDAY"))
    normalized))

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
  (local rule {:freq options.freq :interval interval})
  (when (not= options.count nil)
    (set rule.count (validate-positive-integer options.count "count")))
  (when (not= options.until nil)
    (when (not= (type options.until) :string)
      (error "invalid temporal recurrence UNTIL"))
    (set rule.until options.until))
  (local by-day (normalize-by-day options.by-day))
  (when by-day
    (set rule.by-day by-day))
  (local by-month (normalize-by-month options.by-month))
  (when by-month
    (set rule.by-month by-month))
  (local by-month-day (normalize-by-month-day options.by-month-day))
  (when by-month-day
    (set rule.by-month-day by-month-day))
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

(fn parse-by-day [text]
  (local days [])
  (each [_ item (ipairs (split-nonempty text ","))]
    (local day (. rrule-to-day item))
    (when (not day)
      (error "invalid RRULE BYDAY"))
    (table.insert days day))
  days)

(fn parse-by-month [text]
  (local months [])
  (each [_ item (ipairs (split-nonempty text ","))]
    (table.insert months (validate-month (parse-positive-integer item "BYMONTH"))))
  months)

(fn parse-by-month-day [text]
  (local days [])
  (each [_ item (ipairs (split-nonempty text ","))]
    (table.insert days (validate-month-day (parse-positive-integer item "BYMONTHDAY"))))
  days)

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
        (= key "BYDAY")
        (set options.by-day (parse-by-day value))
        (= key "BYMONTH")
        (set options.by-month (parse-by-month value))
        (= key "BYMONTHDAY")
        (set options.by-month-day (parse-by-month-day value))
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
  (each [_ day (ipairs days)]
    (table.insert parts (. day-to-rrule (validate-day day))))
  (join parts ","))

(fn serialize-by-month [months]
  (local parts [])
  (each [_ month (ipairs months)]
    (table.insert parts (tostring (validate-month month))))
  (join parts ","))

(fn serialize-by-month-day [days]
  (local parts [])
  (each [_ day (ipairs days)]
    (table.insert parts (tostring (validate-month-day day))))
  (join parts ","))

(fn to-rrule [rule]
  (local normalized (from rule))
  (local parts [(.. "FREQ=" (. freq-to-rrule normalized.freq))])
  (when (not= normalized.interval 1)
    (table.insert parts (.. "INTERVAL=" normalized.interval)))
  (when normalized.count
    (table.insert parts (.. "COUNT=" normalized.count)))
  (when normalized.until
    (table.insert parts (.. "UNTIL=" normalized.until)))
  (when normalized.by-month
    (table.insert parts (.. "BYMONTH=" (serialize-by-month normalized.by-month))))
  (when normalized.by-month-day
    (table.insert parts (.. "BYMONTHDAY=" (serialize-by-month-day normalized.by-month-day))))
  (when normalized.by-day
    (table.insert parts (.. "BYDAY=" (serialize-by-day normalized.by-day))))
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
        (error "unsupported temporal recurrence UNTIL")))
  (when (and (= limit nil) (= until nil))
    (error "temporal recurrence expansion requires count, limit, or until"))
  {:limit limit :until until})

{:from from
 :parse-rrule parse-rrule
 :to-rrule to-rrule
 :parse-until parse-until
 :normalize-occurrence-options normalize-occurrence-options
 :occurrence-bounds occurrence-bounds
 :day-to-number day-to-number
 :number-to-day number-to-day}
