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
   :by-day true})

(local valid-occurrence-options
  {:limit true})

(local day-to-rrule {:mo "MO" :tu "TU" :we "WE" :th "TH" :fr "FR" :sa "SA" :su "SU"})
(local rrule-to-day {"MO" :mo "TU" :tu "WE" :we "TH" :th "FR" :fr "SA" :sa "SU" :su})
(local freq-to-rrule {:daily "DAILY" :weekly "WEEKLY" :monthly "MONTHLY" :yearly "YEARLY"})
(local rrule-to-freq {"DAILY" :daily "WEEKLY" :weekly "MONTHLY" :monthly "YEARLY" :yearly})
(local day-to-number {:mo 1 :tu 2 :we 3 :th 4 :fr 5 :sa 6 :su 7})

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

(fn to-rrule [rule]
  (local normalized (from rule))
  (local parts [(.. "FREQ=" (. freq-to-rrule normalized.freq))])
  (when (not= normalized.interval 1)
    (table.insert parts (.. "INTERVAL=" normalized.interval)))
  (when normalized.count
    (table.insert parts (.. "COUNT=" normalized.count)))
  (when normalized.until
    (table.insert parts (.. "UNTIL=" normalized.until)))
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

(fn occurrence-limit [rule options]
  (when (and (= rule.count nil) (not options.has-limit))
    (error "temporal recurrence expansion requires count or limit"))
  (when options.has-limit
    (validate-positive-integer options.limit "limit"))
  (if (and rule.count options.has-limit)
      (math.min rule.count options.limit)
      rule.count
      rule.count
      options.limit))

(fn weekly-day-allowed? [rule weekday default-weekday]
  (if rule.by-day
      (do
        (var allowed false)
        (each [_ day (ipairs rule.by-day)]
          (when (= (. day-to-number day) weekday)
            (set allowed true)))
        allowed)
      (= weekday default-weekday)))

(fn occurrences [input-rule dtstart options]
  (local rule (from input-rule))
  (when (or (= rule.freq :monthly) (= rule.freq :yearly))
    (error "unsupported temporal recurrence expansion"))
  (local occurrence-options (normalize-occurrence-options options))
  (local limit (occurrence-limit rule occurrence-options))
  (local results [])
  (if (= rule.freq :daily)
      (do
        (var current dtstart)
        (while (< (# results) limit)
          (table.insert results current)
          (set current (current:add-days rule.interval))))
      (= rule.freq :weekly)
      (do
        (var current dtstart)
        (var day-offset 0)
        (local default-weekday (dtstart:iso-weekday))
        (while (< (# results) limit)
          (local week-offset (math.floor (/ day-offset 7)))
          (when (and (= (% week-offset rule.interval) 0)
                     (weekly-day-allowed? rule (current:iso-weekday) default-weekday))
            (table.insert results current))
          (set current (current:add-days 1))
          (set day-offset (+ day-offset 1))))
      (error "unsupported temporal recurrence expansion"))
  results)

{:from from
 :parse-rrule parse-rrule
 :to-rrule to-rrule
 :occurrences occurrences}
