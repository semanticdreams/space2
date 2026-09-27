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

(fn numeric-occurrence-limit [rule options]
  (when options.has-limit
    (validate-positive-integer options.limit "limit"))
  (if (and rule.count options.has-limit)
      (math.min rule.count options.limit)
      rule.count
      rule.count
      options.limit))

(fn occurrence-bounds [standard rule options]
  (local limit (numeric-occurrence-limit rule options))
  (var until nil)
  (when rule.until
    (local parsed (parse-until standard rule.until))
    (if (= parsed.kind :plain-date-time)
        (set until parsed.value)
        (= parsed.kind :instant)
        (error "unsupported temporal recurrence UNTIL")))
  (when (and (= limit nil) (= until nil))
    (error "temporal recurrence expansion requires count, limit, or until"))
  {:limit limit :until until})

(fn weekly-day-allowed? [rule weekday default-weekday]
  (if rule.by-day
      (do
        (var allowed false)
        (each [_ day (ipairs rule.by-day)]
          (when (= (. day-to-number day) weekday)
            (set allowed true)))
        allowed)
      (= weekday default-weekday)))

(fn by-day-allowed? [days weekday]
  (var allowed false)
  (each [_ day (ipairs days)]
    (when (= (. day-to-number day) weekday)
      (set allowed true)))
  allowed)

(fn gcd [a b]
  (var x (math.abs a))
  (var y (math.abs b))
  (while (not= y 0)
    (local next (% x y))
    (set x y)
    (set y next))
  x)

(fn plain-month [plain]
  (local fields (plain:fields))
  fields.month)

(fn plain-day [plain]
  (local fields (plain:fields))
  fields.day)

(fn by-month-allowed? [months month]
  (var allowed false)
  (each [_ value (ipairs months)]
    (when (= value month)
      (set allowed true)))
  allowed)

(fn month-filter-allowed? [rule candidate]
  (if rule.by-month
      (by-month-allowed? rule.by-month (plain-month candidate))
      true))

(fn by-month-day-allowed? [days day]
  (var allowed false)
  (each [_ value (ipairs days)]
    (when (= value day)
      (set allowed true)))
  allowed)

(fn month-day-filter-allowed? [rule candidate]
  (if rule.by-month-day
      (by-month-day-allowed? rule.by-month-day (plain-day candidate))
      true))

(fn candidate-calendar-filters-allowed? [rule candidate]
  (and (month-filter-allowed? rule candidate)
       (month-day-filter-allowed? rule candidate)))

(fn limit-reached? [results bounds]
  (and bounds.limit (>= (# results) bounds.limit)))

(fn within-until? [candidate until]
  (if (= until nil)
      true
      (<= (candidate:compare until) 0)))

(fn assert-daily-by-day-satisfiable [rule dtstart]
  (when (and rule.by-day (= (% rule.interval 7) 0)
             (not (by-day-allowed? rule.by-day (dtstart:iso-weekday))))
    (error "unsupported temporal recurrence expansion")))

(fn assert-daily-filters-satisfiable [rule dtstart]
  (when (or rule.by-month rule.by-month-day)
    (local cycle (/ 146097 (gcd rule.interval 146097)))
    (var current dtstart)
    (var offset 0)
    (var satisfiable false)
    (while (and (< offset cycle) (not satisfiable))
      (when (and (candidate-calendar-filters-allowed? rule current)
                 (if rule.by-day
                     (by-day-allowed? rule.by-day (current:iso-weekday))
                     true))
        (set satisfiable true))
      (set current (current:add-days rule.interval))
      (set offset (+ offset 1)))
    (when (not satisfiable)
      (error "unsupported temporal recurrence expansion"))))

(fn assert-weekly-filters-satisfiable [rule dtstart]
  (when (or rule.by-month rule.by-month-day)
    (local selected-week-cycle (/ 20871 (gcd rule.interval 20871)))
    (local default-weekday (dtstart:iso-weekday))
    (local allowed-weekdays
      (if rule.by-day
          rule.by-day
          [(. number-to-day default-weekday)]))
    (var selected-week-index 0)
    (var satisfiable false)
    (while (and (< selected-week-index selected-week-cycle) (not satisfiable))
      (local week-start (dtstart:add-days (* selected-week-index rule.interval 7)))
      (each [_ day (ipairs allowed-weekdays)]
        (local weekday-number (. day-to-number day))
        (var offset (- weekday-number default-weekday))
        (when (< offset 0)
          (set offset (+ offset 7)))
        (local candidate (week-start:add-days offset))
        (when (and (not satisfiable)
                   (candidate-calendar-filters-allowed? rule candidate))
          (set satisfiable true)))
      (set selected-week-index (+ selected-week-index 1)))
    (when (not satisfiable)
      (error "unsupported temporal recurrence expansion"))))

(fn calendar-step-period [freq offset]
  (if (= freq :monthly)
      {:months offset}
      (= freq :yearly)
      {:years offset}
      (error "unsupported temporal recurrence expansion")))

(fn calendar-filter-cycle [rule]
  (if (= rule.freq :monthly)
      (if rule.by-month-day
          (/ 4800 (gcd rule.interval 4800))
          (/ 12 (gcd rule.interval 12)))
      (= rule.freq :yearly)
      (/ 400 (gcd rule.interval 400))
      (error "unsupported temporal recurrence expansion")))

(fn assert-calendar-filters-satisfiable [period rule dtstart]
  (when (or rule.by-month rule.by-month-day)
    (local cycle (calendar-filter-cycle rule))
    (var index 0)
    (var satisfiable false)
    (while (and (< index cycle) (not satisfiable))
      (local candidate
        (if (= index 0)
            dtstart
            (period.add-to-plain-date-time
              dtstart
              (calendar-step-period rule.freq (* index rule.interval)))))
      (when (candidate-calendar-filters-allowed? rule candidate)
        (set satisfiable true))
      (set index (+ index 1)))
    (when (not satisfiable)
      (error "unsupported temporal recurrence expansion"))))

(fn expand-calendar [period rule dtstart bounds]
  (when rule.by-day
    (error "unsupported temporal recurrence expansion"))
  (period.add-to-plain-date-time dtstart (calendar-step-period rule.freq 0))
  (assert-calendar-filters-satisfiable period rule dtstart)
  (local results [])
  (var index 0)
  (var done false)
  (while (and (not done) (not (limit-reached? results bounds)))
    (local candidate
      (if (= index 0)
          dtstart
          (period.add-to-plain-date-time
            dtstart
            (calendar-step-period rule.freq (* index rule.interval)))))
    (if (not (within-until? candidate bounds.until))
        (set done true)
        (do
          (when (candidate-calendar-filters-allowed? rule candidate)
            (table.insert results candidate))
          (set index (+ index 1)))))
  results)

(fn expand-daily [rule dtstart bounds]
  (local results [])
  (var current dtstart)
  (if rule.by-day
      (do
        (assert-daily-by-day-satisfiable rule dtstart)
        (assert-daily-filters-satisfiable rule dtstart)
        (var day-offset 0)
        (while (and (not (limit-reached? results bounds))
                    (within-until? current bounds.until))
          (when (and (= (% day-offset rule.interval) 0)
                     (by-day-allowed? rule.by-day (current:iso-weekday))
                     (candidate-calendar-filters-allowed? rule current))
            (table.insert results current))
          (set current (current:add-days 1))
          (set day-offset (+ day-offset 1))))
      (do
        (assert-daily-filters-satisfiable rule dtstart)
        (while (and (not (limit-reached? results bounds))
                    (within-until? current bounds.until))
          (when (candidate-calendar-filters-allowed? rule current)
            (table.insert results current))
          (set current (current:add-days rule.interval)))))
  results)

(fn expand-weekly [rule dtstart bounds]
  (local results [])
  (var current dtstart)
  (var day-offset 0)
  (local default-weekday (dtstart:iso-weekday))
  (assert-weekly-filters-satisfiable rule dtstart)
  (while (and (not (limit-reached? results bounds))
              (within-until? current bounds.until))
    (local week-offset (math.floor (/ day-offset 7)))
    (when (and (= (% week-offset rule.interval) 0)
               (weekly-day-allowed? rule (current:iso-weekday) default-weekday)
               (candidate-calendar-filters-allowed? rule current))
      (table.insert results current))
    (set current (current:add-days 1))
    (set day-offset (+ day-offset 1)))
  results)

(fn occurrences [period standard input-rule dtstart options]
  (local rule (from input-rule))
  (local occurrence-options (normalize-occurrence-options options))
  (local bounds (occurrence-bounds standard rule occurrence-options))
  (if (or (= rule.freq :monthly) (= rule.freq :yearly))
      (expand-calendar period rule dtstart bounds)
      (= rule.freq :daily)
      (expand-daily rule dtstart bounds)
      (= rule.freq :weekly)
      (expand-weekly rule dtstart bounds)
      (error "unsupported temporal recurrence expansion")))

(fn create [deps]
  (when (not (and deps deps.period deps.period.add-to-plain-date-time))
    (error "temporal recurrence requires period dependency"))
  (when (not (and deps.standard deps.standard.parse-plain-date-time))
    (error "temporal recurrence requires standard dependency"))
  (local period deps.period)
  (local standard deps.standard)
  {:from from
   :parse-rrule parse-rrule
   :to-rrule to-rrule
   :occurrences (fn [rule dtstart options]
                   (occurrences period standard rule dtstart options))})

create
