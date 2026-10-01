(fn assert-table [value label]
  (when (not= (type value) :table)
    (error (.. "temporal ICS " label " must be a table")))
  value)

(fn assert-string [value label]
  (when (not= (type value) :string)
    (error (.. "temporal ICS " label " must be a string")))
  value)

(fn pad2 [value]
  (string.format "%02d" value))

(fn pad4 [value]
  (string.format "%04d" value))

(fn date-text [date]
  (.. (pad4 date.year) (pad2 date.month) (pad2 date.day)))

(fn date-key [date]
  (.. (pad4 date.year) "-" (pad2 date.month) "-" (pad2 date.day)))

(fn plain-text [plain]
  (local fields (plain:fields))
  (.. (date-text fields) "T" (pad2 fields.hour) (pad2 fields.minute) (pad2 fields.second)))

(fn plain-iso-text [year month day hour minute second]
  (.. (pad4 year) "-" (pad2 month) "-" (pad2 day)
      "T" (pad2 hour) ":" (pad2 minute) ":" (pad2 second)))

(fn validate-params [params]
  (local table-params (if (= params nil) {} params))
  (assert-table table-params "date-time parameters")
  (each [key _value (pairs table-params)]
    (when (and (not= key "VALUE") (not= key "TZID"))
      (error (.. "unknown temporal ICS date-time parameter: " (tostring key)))))
  table-params)

(fn date->plain [Temporal date]
  (assert-table date "date value")
  (Temporal.plain-date-time.from-fields {:year date.year
                                         :month date.month
                                         :day date.day
                                         :hour 0
                                         :minute 0
                                         :second 0}))

(fn plain->date [plain]
  (local fields (plain:fields))
  {:year fields.year :month fields.month :day fields.day})

(fn parse-date [Temporal text]
  (local (year month day) (text:match "^(%d%d%d%d)(%d%d)(%d%d)$"))
  (when (not year)
    (error "invalid temporal ICS DATE value"))
  (local date {:year (tonumber year) :month (tonumber month) :day (tonumber day)})
  (date->plain Temporal date)
  date)

(fn parse-plain [Temporal text]
  (local (year month day hour minute second)
    (text:match "^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)$"))
  (when (not year)
    (error "invalid temporal ICS DATE-TIME value"))
  (Temporal.plain-date-time.parse
    (plain-iso-text (tonumber year) (tonumber month) (tonumber day)
                    (tonumber hour) (tonumber minute) (tonumber second))))

(fn validate-zone-id [Temporal zone-id]
  (assert-string zone-id "TZID")
  (when (zone-id:match "^[%+%-]%d%d:?%d%d$")
    (error (.. "unsupported temporal ICS TZID numeric offset: " zone-id)))
  (local known (Temporal.plain-date-time.parse "2026-01-15T00:00:00"))
  (local (ok err) (pcall #(Temporal.zoned-date-time.from-plain known zone-id)))
  (when (not ok)
    (error (.. "unsupported temporal ICS TZID: " zone-id " (" (tostring err) ")")))
  zone-id)

(fn parse-date-time [Temporal params text]
  (local p (validate-params params))
  (local raw (assert-string text "date-time value"))
  (local value-param p.VALUE)
  (local zone-id p.TZID)
  (if (= value-param "DATE")
      (do
        (when zone-id
          (error "temporal ICS DATE value must not include TZID"))
        {:kind :temporal-ics-date-time
         :value-type :date
         :date (parse-date Temporal raw)})
      (and value-param (not= value-param nil))
      (error (.. "unsupported temporal ICS VALUE parameter: " value-param))
      zone-id
      {:kind :temporal-ics-date-time
       :value-type :date-time
       :time-mode :zoned
       :zone-id (validate-zone-id Temporal zone-id)
       :plain (parse-plain Temporal raw)}
      (raw:match "Z$")
      (do
        (local plain-part (raw:sub 1 (- (length raw) 1)))
        (local plain (parse-plain Temporal plain-part))
        {:kind :temporal-ics-date-time
         :value-type :date-time
         :time-mode :utc
         :instant (Temporal.instant.parse (.. (plain:to-string) "Z"))})
      {:kind :temporal-ics-date-time
       :value-type :date-time
       :time-mode :floating
       :plain (parse-plain Temporal raw)}))

(fn format-date-time [wrapper]
  (assert-table wrapper "date-time wrapper")
  (if (= wrapper.value-type :date)
      (values {:VALUE "DATE"} (date-text wrapper.date))
      (= wrapper.time-mode :floating)
      (values {} (plain-text wrapper.plain))
      (= wrapper.time-mode :utc)
      (do
        (local instant-text (wrapper.instant:to-string))
        (local formatted (instant-text:gsub "[-:]" ""))
        (values {} formatted))
      (= wrapper.time-mode :zoned)
      (values {:TZID wrapper.zone-id} (plain-text wrapper.plain))
      (error "unsupported temporal ICS date-time wrapper mode")))

(fn parse-exact-duration [Temporal text]
  (var fields (assert-string text "duration value"))
  (when (not (fields:match "^PT"))
    (error "invalid temporal ICS timed DURATION"))
  (set fields (fields:sub 3))
  (when (= fields "")
    (error "invalid temporal ICS timed DURATION"))
  (var total 0)
  (var consumed "")
  (var saw? false)
  (local hours (fields:match "^(%d+)H"))
  (when hours
    (set total (+ total (* (tonumber hours) 3600)))
    (set consumed (.. consumed hours "H"))
    (set saw? true))
  (local remaining-after-hours (fields:sub (+ (length consumed) 1)))
  (local minutes (remaining-after-hours:match "^(%d+)M"))
  (when minutes
    (set total (+ total (* (tonumber minutes) 60)))
    (set consumed (.. consumed minutes "M"))
    (set saw? true))
  (local remaining-after-minutes (fields:sub (+ (length consumed) 1)))
  (local seconds (remaining-after-minutes:match "^(%d+)S$"))
  (when seconds
    (set total (+ total (tonumber seconds)))
    (set consumed (.. consumed seconds "S"))
    (set saw? true))
  (when (or (not saw?) (not= consumed fields))
    (error "invalid temporal ICS timed DURATION"))
  (Temporal.duration.from-seconds total))

(fn parse-duration [Temporal text all-day?]
  (local raw (assert-string text "duration value"))
  (when (raw:match "^%-")
    (error "negative temporal ICS DURATION is not supported"))
  (when (raw:match "^P.*T")
    (if (raw:match "^PT")
        nil
        (error "mixed temporal ICS DURATION values are not supported")))
  (if all-day?
      (do
        (when (raw:match "^PT")
          (error "all-day temporal ICS DURATION must be a calendar period"))
        (Temporal.period.parse raw))
      (do
        (when (and (raw:match "^P") (not (raw:match "^PT")))
          (error "timed temporal ICS DURATION must be exact"))
        (parse-exact-duration Temporal raw))))

(fn exact-duration-nanoseconds [duration]
  (local text (duration:to-string))
  (local ns (text:match "^(%d+)ns$"))
  (when (not ns)
    (error "unsupported temporal ICS DURATION value"))
  (tonumber ns))

(fn format-exact-duration [duration]
  (local ns (exact-duration-nanoseconds duration))
  (when (not= (% ns 1000000000) 0)
    (error "temporal ICS DURATION only supports whole seconds"))
  (var seconds (/ ns 1000000000))
  (local hours (math.floor (/ seconds 3600)))
  (set seconds (- seconds (* hours 3600)))
  (local minutes (math.floor (/ seconds 60)))
  (set seconds (- seconds (* minutes 60)))
  (local parts [])
  (when (> hours 0)
    (table.insert parts (.. (tostring hours) "H")))
  (when (> minutes 0)
    (table.insert parts (.. (tostring minutes) "M")))
  (when (> seconds 0)
    (table.insert parts (.. (tostring seconds) "S")))
  (when (= (# parts) 0)
    (table.insert parts "0S"))
  (.. "PT" (table.concat parts "")))

(fn format-period-field [parts value suffix]
  (when (not= value 0)
    (table.insert parts (.. (tostring value) suffix))))

(fn period-field [period key]
  (local value (. period key))
  (if (= value nil)
      0
      value))

(fn format-period [period]
  (assert-table period "period duration")
  (local parts [])
  (format-period-field parts (period-field period :years) "Y")
  (format-period-field parts (period-field period :months) "M")
  (format-period-field parts (period-field period :weeks) "W")
  (format-period-field parts (period-field period :days) "D")
  (if (= (# parts) 0)
      "P0D"
      (.. "P" (table.concat parts ""))))

(fn format-duration [duration all-day?]
  (if all-day?
      (format-period duration)
      (format-exact-duration duration)))

(fn same-mode? [left right]
  (and (= left.value-type right.value-type)
       (if (= left.value-type :date)
           true
           (and (= left.time-mode right.time-mode)
                (if (= left.time-mode :zoned)
                    (= left.zone-id right.zone-id)
                    true)))))

(fn normalized-key [wrapper]
  (if (= wrapper.value-type :date)
      (.. "DATE:" (date-key wrapper.date))
      (= wrapper.time-mode :floating)
      (.. "FLOATING:" (wrapper.plain:to-string))
      (= wrapper.time-mode :utc)
      (.. "UTC:" (wrapper.instant:to-string))
      (= wrapper.time-mode :zoned)
      (.. "ZONED:" wrapper.zone-id ":" (wrapper.plain:to-string))
      (error "unsupported temporal ICS date-time wrapper mode")))

(fn start-plus-duration [Temporal start duration]
  (if (= start.value-type :date)
      {:kind :temporal-ics-date-time
       :value-type :date
       :date (plain->date (Temporal.period.add-to-plain-date-time (date->plain Temporal start.date) duration))}
      (= start.time-mode :floating)
      {:kind :temporal-ics-date-time
       :value-type :date-time
       :time-mode :floating
       :plain (start.plain:add duration)}
      (= start.time-mode :utc)
      {:kind :temporal-ics-date-time
       :value-type :date-time
       :time-mode :utc
       :instant (start.instant:add duration)}
      (= start.time-mode :zoned)
      {:kind :temporal-ics-date-time
       :value-type :date-time
       :time-mode :zoned
       :zone-id start.zone-id
       :plain (start.plain:add duration)}
      (error "unsupported temporal ICS date-time wrapper mode")))

(fn default-end [Temporal start]
  (if (= start.value-type :date)
      {:kind :temporal-ics-date-time
       :value-type :date
       :date (plain->date ((date->plain Temporal start.date):add-days 1))}
      start))

{:parse-date-time parse-date-time
 :format-date-time format-date-time
 :parse-duration parse-duration
 :format-duration format-duration
 :date-key date-key
 :normalized-key normalized-key
 :same-mode? same-mode?
 :start-plus-duration start-plus-duration
 :default-end default-end
 :date->plain date->plain
 :plain->date plain->date}
