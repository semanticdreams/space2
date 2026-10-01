(local weekend-iso-weekdays {6 true 7 true})

(fn integer? [value]
  (and (= (type value) :number)
       (= value (math.floor value))))

(fn validate-options [options allowed context]
  (when (not (= (type options) :table))
    (error (.. "temporal business-calendar " context " options must be a table")))
  (each [key _ (pairs options)]
    (when (not (. allowed key))
      (error (.. "unsupported temporal business-calendar option: " (tostring key)))))
  options)

(fn require-jurisdiction [options context]
  (validate-options options {:jurisdiction true} context)
  (when (not (= (type options.jurisdiction) :string))
    (error "temporal business-calendar jurisdiction must be a string"))
  options.jurisdiction)

(fn plain-fields [plain]
  (local (ok fields-or-error) (pcall #(plain:fields)))
  (when (not ok)
    (error (.. "invalid temporal business-calendar plain date-time: " (tostring fields-or-error))))
  (when (not (= (type fields-or-error) :table))
    (error "invalid temporal business-calendar plain date-time fields"))
  fields-or-error)

(fn plain-iso-weekday [plain]
  (local (ok weekday-or-error) (pcall #(plain:iso-weekday)))
  (when (not ok)
    (error (.. "invalid temporal business-calendar plain date-time: " (tostring weekday-or-error))))
  (when (not (integer? weekday-or-error))
    (error "invalid temporal business-calendar ISO weekday"))
  weekday-or-error)

(fn plain-add-days [plain days]
  (local (ok result-or-error) (pcall #(plain:add-days days)))
  (if ok
      result-or-error
      (error (.. "invalid temporal business-calendar plain date-time: " (tostring result-or-error)))))

(fn iso-date [plain]
  (local fields (plain-fields plain))
  (when (or (not (integer? fields.year))
            (not (integer? fields.month))
            (not (integer? fields.day)))
    (error "invalid temporal business-calendar plain date-time fields"))
  (string.format "%04d-%02d-%02d" fields.year fields.month fields.day))

(fn date-key [plain]
  (local fields (plain-fields plain))
  (when (or (not (integer? fields.year))
            (not (integer? fields.month))
            (not (integer? fields.day)))
    (error "invalid temporal business-calendar plain date-time fields"))
  (+ (* fields.year 10000) (* fields.month 100) fields.day))

(fn create-business-calendar [deps]
  (when (not (= (type deps) :table))
    (error "temporal business-calendar dependencies must be a table"))
  (local seed deps.seed)
  (when (not (= (type seed) :table))
    (error "temporal business-calendar seed dependency is required"))

  (fn supported-jurisdictions []
    (seed.supported-jurisdictions))

  (fn holidays [options]
    (validate-options options {:jurisdiction true :year true} "holidays")
    (when (not (= (type options.jurisdiction) :string))
      (error "temporal business-calendar jurisdiction must be a string"))
    (when (not (integer? options.year))
      (error "temporal business-calendar year must be an integer"))
    (seed.holidays-for-year options.jurisdiction options.year))

  (fn is-holiday [plain options]
    (local jurisdiction (require-jurisdiction options "is-holiday"))
    (not (= nil (seed.holiday-on-date jurisdiction (iso-date plain)))))

  (fn is-business-day [plain options]
    (local jurisdiction (require-jurisdiction options "is-business-day"))
    (and (not (. weekend-iso-weekdays (plain-iso-weekday plain)))
         (not (is-holiday plain {:jurisdiction jurisdiction}))))

  (fn add-business-days [plain count options]
    (local jurisdiction (require-jurisdiction options "add-business-days"))
    (when (not (integer? count))
      (error "temporal business-calendar business-day count must be an integer"))
    (plain-fields plain)
    (var current plain)
    (var remaining (math.abs count))
    (local direction (if (< count 0) -1 1))
    (while (> remaining 0)
      (set current (plain-add-days current direction))
      (when (is-business-day current {:jurisdiction jurisdiction})
        (set remaining (- remaining 1))))
    current)

  (fn business-days-between [start end options]
    (local jurisdiction (require-jurisdiction options "business-days-between"))
    (local start-key (date-key start))
    (local end-key (date-key end))
    (when (> start-key end-key)
      (error "descending temporal business-day range"))
    (var current start)
    (var count 0)
    (while (< (date-key current) end-key)
      (when (is-business-day current {:jurisdiction jurisdiction})
        (set count (+ count 1)))
      (set current (plain-add-days current 1)))
    count)

  {:supported-jurisdictions supported-jurisdictions
   :holidays holidays
   :is-holiday is-holiday
   :is-business-day is-business-day
   :add-business-days add-business-days
   :business-days-between business-days-between})

create-business-calendar
