(local allowed-option-keys {:calendar true})
(local allowed-record-keys {:kind true
                            :calendar true
                            :era true
                            :year true
                            :month true
                            :day true
                            :hour true
                            :minute true
                            :second true
                            :nanosecond true})

(fn reject-unknown-keys [record allowed message]
  (when (not (= (type record) :table))
    (error message))
  (each [key _ (pairs record)]
    (when (not (. allowed key))
      (error (.. message ": " (tostring key))))))

(fn integer? [value]
  (and (= (type value) :number)
       (= value (math.floor value))))

(fn require-integer-field [record key]
  (local value (. record key))
  (when (not (integer? value))
    (error (.. "invalid calendar field type: " (tostring key))))
  value)

(fn require-string-field [record key]
  (local value (. record key))
  (when (not (= (type value) :string))
    (error (.. "invalid calendar field type: " (tostring key))))
  value)

(fn validate-kind [record]
  (when (not (= record.kind :temporal-calendar-fields))
    (error "invalid calendar field type: kind")))

(fn date-key [year month day]
  (+ (* year 10000) (* month 100) day))

(fn parse-iso-date-key [iso]
  (local year (tonumber (iso:sub 1 4)))
  (local month (tonumber (iso:sub 6 7)))
  (local day (tonumber (iso:sub 9 10)))
  (date-key year month day))

(fn extract-fields [plain]
  (when (not (and plain plain.fields))
    (error "invalid PlainDateTime"))
  (plain:fields))

(fn record-from-fields [calendar era year fields]
  {:kind :temporal-calendar-fields
   :calendar calendar
   :era era
   :year year
   :month fields.month
   :day fields.day
   :hour fields.hour
   :minute fields.minute
   :second fields.second
   :nanosecond fields.nanosecond})

(fn calendar-supported? [seed calendar]
  (not (= (seed.calendar-data calendar) nil)))

(fn require-calendar-option [seed options]
  (when (= options nil)
    (error "missing calendar"))
  (reject-unknown-keys options allowed-option-keys "unknown calendar option")
  (local calendar options.calendar)
  (when (= calendar nil)
    (error "missing calendar"))
  (when (not (= (type calendar) :string))
    (error "invalid calendar option type: calendar"))
  (when (not (calendar-supported? seed calendar))
    (error (.. "unsupported calendar: " calendar)))
  calendar)

(fn require-record-calendar [seed record]
  (local calendar (require-string-field record :calendar))
  (when (not (calendar-supported? seed calendar))
    (error (.. "unsupported calendar: " calendar)))
  calendar)

(fn validate-record [seed record]
  (reject-unknown-keys record allowed-record-keys "unknown calendar record key")
  (validate-kind record)
  (local calendar (require-record-calendar seed record))
  (local era (require-string-field record :era))
  (local year (require-integer-field record :year))
  (local month (require-integer-field record :month))
  (local day (require-integer-field record :day))
  (local hour (require-integer-field record :hour))
  (local minute (require-integer-field record :minute))
  (local second (require-integer-field record :second))
  (local nanosecond (require-integer-field record :nanosecond))
  {:calendar calendar
   :era era
   :year year
   :month month
   :day day
   :hour hour
   :minute minute
   :second second
   :nanosecond nanosecond})

(fn era-by-id [calendar-data id]
  (var found nil)
  (each [_ era (ipairs calendar-data.eras)]
    (when (= era.id id)
      (set found era)))
  found)

(fn calendar-label [calendar]
  (if (= calendar "gregory")
      "Gregorian"
      (= calendar "buddhist")
      "Buddhist"
      calendar))

(fn date-in-era-range? [fields era]
  (local date (date-key fields.year fields.month fields.day))
  (local start (parse-iso-date-key era.start_iso))
  (local end (and era.end_iso (parse-iso-date-key era.end_iso)))
  (and (>= date start)
       (if (= end nil)
           true
           (<= date end))))

(fn require-iso-in-seed-era [seed calendar fields]
  (local calendar-data (seed.calendar-data calendar))
  (var in-range? false)
  (each [_ era (ipairs calendar-data.eras)]
    (when (date-in-era-range? fields era)
      (set in-range? true)))
  (when (not in-range?)
    (error (.. "unsupported " (calendar-label calendar) " era range"))))

(fn japanese-era-for-iso [seed fields]
  (local date (date-key fields.year fields.month fields.day))
  (local calendar-data (seed.calendar-data "japanese"))
  (var found nil)
  (each [_ era (ipairs calendar-data.eras)]
    (local start (parse-iso-date-key era.start_iso))
    (local end (and era.end_iso (parse-iso-date-key era.end_iso)))
    (when (and (>= date start)
               (or (= end nil) (<= date end)))
      (set found era)))
  (if found
      found
      (error "unsupported Japanese era range")))

(fn from-gregory [seed fields]
  (require-iso-in-seed-era seed "gregory" fields)
  (record-from-fields "gregory" "ce" fields.year fields))

(fn to-gregory [seed plain-date-time record]
  (when (not (= record.era "ce"))
    (error "inconsistent Gregorian era/date fields"))
  (local iso-fields {:year record.year
                     :month record.month
                     :day record.day
                     :hour record.hour
                     :minute record.minute
                     :second record.second
                     :nanosecond record.nanosecond})
  (require-iso-in-seed-era seed "gregory" iso-fields)
  (plain-date-time.from-fields iso-fields))

(fn from-buddhist [seed fields]
  (require-iso-in-seed-era seed "buddhist" fields)
  (record-from-fields "buddhist" "be" (+ fields.year 543) fields))

(fn to-buddhist [seed plain-date-time record]
  (when (not (= record.era "be"))
    (error "inconsistent Buddhist era/date fields"))
  (local iso-fields {:year (- record.year 543)
                     :month record.month
                     :day record.day
                     :hour record.hour
                     :minute record.minute
                     :second record.second
                     :nanosecond record.nanosecond})
  (require-iso-in-seed-era seed "buddhist" iso-fields)
  (plain-date-time.from-fields iso-fields))

(fn from-japanese [seed fields]
  (local era (japanese-era-for-iso seed fields))
  (record-from-fields "japanese" era.id (+ (- fields.year era.iso_start_year) 1) fields))

(fn to-japanese [seed plain-date-time record]
  (local calendar-data (seed.calendar-data "japanese"))
  (local era (era-by-id calendar-data record.era))
  (when (= era nil)
    (error "unsupported Japanese era range"))
  (local iso-year (+ era.iso_start_year record.year -1))
  (local iso-fields {:year iso-year
                     :month record.month
                     :day record.day
                     :hour record.hour
                     :minute record.minute
                     :second record.second
                     :nanosecond record.nanosecond})
  (local actual-era (japanese-era-for-iso seed iso-fields))
  (when (not (= actual-era.id record.era))
    (error "inconsistent Japanese era/date fields"))
  (plain-date-time.from-fields iso-fields))

(fn create-calendar [deps]
  (when (not (= (type deps) :table))
    (error "Temporal.calendar dependencies must be a table"))
  (local plain-date-time deps.plain-date-time)
  (local seed deps.seed)
  (when (not (= (type plain-date-time) :table))
    (error "Temporal.calendar requires plain-date-time dependency"))
  (when (not (= (type seed) :table))
    (error "Temporal.calendar requires seed dependency"))
  (fn supported-calendars []
    (seed.supported-calendars))
  (fn from-iso [plain options]
    (local calendar (require-calendar-option seed options))
    (local fields (extract-fields plain))
    (if (= calendar "gregory")
        (from-gregory seed fields)
        (= calendar "buddhist")
        (from-buddhist seed fields)
        (= calendar "japanese")
        (from-japanese seed fields)
        (error (.. "unsupported calendar: " calendar))))
  (fn to-iso [record]
    (local valid-record (validate-record seed record))
    (if (= valid-record.calendar "gregory")
        (to-gregory seed plain-date-time valid-record)
        (= valid-record.calendar "buddhist")
        (to-buddhist seed plain-date-time valid-record)
        (= valid-record.calendar "japanese")
        (to-japanese seed plain-date-time valid-record)
        (error (.. "unsupported calendar: " valid-record.calendar))))
  {:supported-calendars supported-calendars
   :from-iso from-iso
   :to-iso to-iso})

create-calendar
