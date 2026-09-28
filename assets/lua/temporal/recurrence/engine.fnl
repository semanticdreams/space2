(local rule (require :temporal/recurrence/rule))
(local day-to-number rule.day-to-number)
(local number-to-day rule.number-to-day)

(fn weekly-day-allowed? [recurrence-rule weekday default-weekday]
  (if recurrence-rule.by-day
      (do
        (var allowed false)
        (each [_ day (ipairs recurrence-rule.by-day)]
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

(fn plain-fields [plain]
  (plain:fields))

(fn build-generated-candidate [plain-date-time dtstart year month day]
  (local source-fields (plain-fields dtstart))
  (local (ok value)
    (pcall plain-date-time.from-fields
           {:year year
            :month month
            :day day
            :hour source-fields.hour
            :minute source-fields.minute
            :second source-fields.second
            :nanosecond source-fields.nanosecond}))
  (if ok value nil))

(fn before-dtstart? [candidate dtstart]
  (< (candidate:compare dtstart) 0))

(fn by-month-allowed? [months month]
  (var allowed false)
  (each [_ value (ipairs months)]
    (when (= value month)
      (set allowed true)))
  allowed)

(fn month-filter-allowed? [recurrence-rule candidate]
  (if recurrence-rule.by-month
      (by-month-allowed? recurrence-rule.by-month (plain-month candidate))
      true))

(fn by-month-day-allowed? [days day]
  (var allowed false)
  (each [_ value (ipairs days)]
    (when (= value day)
      (set allowed true)))
  allowed)

(fn month-day-filter-allowed? [recurrence-rule candidate]
  (if recurrence-rule.by-month-day
      (by-month-day-allowed? recurrence-rule.by-month-day (plain-day candidate))
      true))

(fn by-day-filter-allowed? [recurrence-rule candidate]
  (if recurrence-rule.by-day
      (by-day-allowed? recurrence-rule.by-day (candidate:iso-weekday))
      true))

(fn candidate-calendar-filters-allowed? [recurrence-rule candidate]
  (and (month-filter-allowed? recurrence-rule candidate)
       (month-day-filter-allowed? recurrence-rule candidate)))

(fn has-ordinal-by-day? [days]
  (var found false)
  (when days
    (each [_ day (ipairs days)]
      (when (= (type day) :table)
        (set found true))))
  found)

(fn has-negative-month-day? [days]
  (var found false)
  (when days
    (each [_ day (ipairs days)]
      (when (< day 0)
        (set found true))))
  found)

(fn assert-supported-expansion-surface [recurrence-rule]
  (when (or recurrence-rule.by-second
             recurrence-rule.by-minute
             recurrence-rule.by-hour)
    (error "unsupported temporal recurrence expansion")))

(fn limit-reached? [results bounds]
  (and bounds.limit (>= (# results) bounds.limit)))

(fn within-until? [candidate until]
  (if (= until nil)
      true
      (<= (candidate:compare until) 0)))

(fn assert-daily-by-day-satisfiable [recurrence-rule dtstart]
  (when (and recurrence-rule.by-day (= (% recurrence-rule.interval 7) 0)
             (not (by-day-allowed? recurrence-rule.by-day (dtstart:iso-weekday))))
    (error "unsupported temporal recurrence expansion")))

(fn assert-daily-filters-satisfiable [recurrence-rule dtstart]
  (when (or recurrence-rule.by-month recurrence-rule.by-month-day)
    (local cycle (/ 146097 (gcd recurrence-rule.interval 146097)))
    (var current dtstart)
    (var offset 0)
    (var satisfiable false)
    (while (and (< offset cycle) (not satisfiable))
      (when (and (candidate-calendar-filters-allowed? recurrence-rule current)
                 (if recurrence-rule.by-day
                     (by-day-allowed? recurrence-rule.by-day (current:iso-weekday))
                     true))
        (set satisfiable true))
      (set current (current:add-days recurrence-rule.interval))
      (set offset (+ offset 1)))
    (when (not satisfiable)
      (error "unsupported temporal recurrence expansion"))))

(fn assert-weekly-filters-satisfiable [recurrence-rule dtstart]
  (when (or recurrence-rule.by-month recurrence-rule.by-month-day)
    (local selected-week-cycle (/ 20871 (gcd recurrence-rule.interval 20871)))
    (local default-weekday (dtstart:iso-weekday))
    (local allowed-weekdays
      (if recurrence-rule.by-day
          recurrence-rule.by-day
          [(. number-to-day default-weekday)]))
    (var selected-week-index 0)
    (var satisfiable false)
    (while (and (< selected-week-index selected-week-cycle) (not satisfiable))
      (local week-start (dtstart:add-days (* selected-week-index recurrence-rule.interval 7)))
      (each [_ day (ipairs allowed-weekdays)]
        (local weekday-number (. day-to-number day))
        (var offset (- weekday-number default-weekday))
        (when (< offset 0)
          (set offset (+ offset 7)))
        (local candidate (week-start:add-days offset))
        (when (and (not satisfiable)
                   (candidate-calendar-filters-allowed? recurrence-rule candidate))
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

(fn calendar-filter-cycle [recurrence-rule]
  (if (= recurrence-rule.freq :monthly)
      (if recurrence-rule.by-month-day
          (/ 4800 (gcd recurrence-rule.interval 4800))
          (/ 12 (gcd recurrence-rule.interval 12)))
      (= recurrence-rule.freq :yearly)
      (/ 400 (gcd recurrence-rule.interval 400))
      (error "unsupported temporal recurrence expansion")))

(fn assert-calendar-filters-satisfiable [period recurrence-rule dtstart]
  (when (or recurrence-rule.by-month recurrence-rule.by-month-day)
    (local cycle (calendar-filter-cycle recurrence-rule))
    (var index 0)
    (var satisfiable false)
    (while (and (< index cycle) (not satisfiable))
      (local candidate
        (if (= index 0)
            dtstart
            (period.add-to-plain-date-time
              dtstart
              (calendar-step-period recurrence-rule.freq (* index recurrence-rule.interval)))))
      (when (candidate-calendar-filters-allowed? recurrence-rule candidate)
        (set satisfiable true))
      (set index (+ index 1)))
    (when (not satisfiable)
      (error "unsupported temporal recurrence expansion"))))

(fn month-weekday-candidates [plain-date-time recurrence-rule dtstart year month]
  (local generated [])
  (var day 1)
  (while (<= day 31)
    (local candidate (build-generated-candidate plain-date-time dtstart year month day))
    (when (and candidate
               (by-day-filter-allowed? recurrence-rule candidate))
      (table.insert generated candidate))
    (set day (+ day 1)))
  generated)

(fn monthly-generated-candidates [plain-date-time recurrence-rule dtstart anchor]
  (local fields (plain-fields anchor))
  (local generated [])
  (when (month-filter-allowed? recurrence-rule anchor)
    (if recurrence-rule.by-month-day
        (each [_ day (ipairs recurrence-rule.by-month-day)]
          (local candidate (build-generated-candidate plain-date-time dtstart fields.year fields.month day))
          (when (and candidate (by-day-filter-allowed? recurrence-rule candidate))
            (table.insert generated candidate)))
        recurrence-rule.by-day
        (each [_ candidate (ipairs (month-weekday-candidates plain-date-time recurrence-rule dtstart fields.year fields.month))]
          (table.insert generated candidate))))
  generated)

(fn yearly-generated-months [recurrence-rule dtstart]
  (if recurrence-rule.by-month
      recurrence-rule.by-month
      [(plain-month dtstart)]))

(fn yearly-generated-candidates [plain-date-time recurrence-rule dtstart anchor]
  (local fields (plain-fields anchor))
  (local generated [])
  (each [_ month (ipairs (yearly-generated-months recurrence-rule dtstart))]
    (if recurrence-rule.by-month-day
        (each [_ day (ipairs recurrence-rule.by-month-day)]
          (local candidate (build-generated-candidate plain-date-time dtstart fields.year month day))
          (when (and candidate (by-day-filter-allowed? recurrence-rule candidate))
            (table.insert generated candidate)))
        recurrence-rule.by-day
        (each [_ candidate (ipairs (month-weekday-candidates plain-date-time recurrence-rule dtstart fields.year month))]
          (table.insert generated candidate))))
  generated)

(fn append-generated-candidates [results bounds dtstart candidates]
  (each [_ candidate (ipairs candidates)]
    (when (and (not (limit-reached? results bounds))
               (not (before-dtstart? candidate dtstart))
               (within-until? candidate bounds.until))
      (table.insert results candidate))))

(fn generated-candidates-for-anchor [plain-date-time recurrence-rule dtstart anchor]
  (if (= recurrence-rule.freq :monthly)
      (monthly-generated-candidates plain-date-time recurrence-rule dtstart anchor)
      (= recurrence-rule.freq :yearly)
      (yearly-generated-candidates plain-date-time recurrence-rule dtstart anchor)
      []))

(fn generator-cycle [recurrence-rule]
  (if (= recurrence-rule.freq :monthly)
      (/ 4800 (gcd recurrence-rule.interval 4800))
      (= recurrence-rule.freq :yearly)
      (/ 400 (gcd recurrence-rule.interval 400))
      (error "unsupported temporal recurrence expansion")))

(fn assert-generator-filters-satisfiable [period plain-date-time recurrence-rule dtstart]
  (local cycle (generator-cycle recurrence-rule))
  (var index 0)
  (var satisfiable false)
  (while (and (< index cycle) (not satisfiable))
    (local anchor
      (if (= index 0)
          dtstart
          (period.add-to-plain-date-time
            dtstart
            (calendar-step-period recurrence-rule.freq (* index recurrence-rule.interval)))))
    (each [_ candidate (ipairs (generated-candidates-for-anchor plain-date-time recurrence-rule dtstart anchor))]
      (when candidate
        (set satisfiable true)))
    (set index (+ index 1)))
  (when (not satisfiable)
    (error "unsupported temporal recurrence expansion")))

(fn expand-calendar [period recurrence-rule dtstart bounds]
  (when recurrence-rule.by-day
    (error "unsupported temporal recurrence expansion"))
  (period.add-to-plain-date-time dtstart (calendar-step-period recurrence-rule.freq 0))
  (assert-calendar-filters-satisfiable period recurrence-rule dtstart)
  (local results [])
  (var index 0)
  (var done false)
  (while (and (not done) (not (limit-reached? results bounds)))
    (local candidate
      (if (= index 0)
          dtstart
          (period.add-to-plain-date-time
            dtstart
            (calendar-step-period recurrence-rule.freq (* index recurrence-rule.interval)))))
    (if (not (within-until? candidate bounds.until))
        (set done true)
        (do
          (when (candidate-calendar-filters-allowed? recurrence-rule candidate)
            (table.insert results candidate))
          (set index (+ index 1)))))
  results)

(fn expand-calendar-generator [period plain-date-time recurrence-rule dtstart bounds]
  (period.add-to-plain-date-time dtstart (calendar-step-period recurrence-rule.freq 0))
  (assert-generator-filters-satisfiable period plain-date-time recurrence-rule dtstart)
  (local results [])
  (var index 0)
  (var done false)
  (while (and (not done) (not (limit-reached? results bounds)))
    (local anchor
      (if (= index 0)
          dtstart
          (period.add-to-plain-date-time
            dtstart
            (calendar-step-period recurrence-rule.freq (* index recurrence-rule.interval)))))
    (append-generated-candidates
      results
      bounds
      dtstart
      (generated-candidates-for-anchor plain-date-time recurrence-rule dtstart anchor))
    (when (and bounds.until (> (anchor:compare bounds.until) 0))
      (set done true))
    (when (not done)
      (set index (+ index 1))))
  results)

(fn expand-daily [recurrence-rule dtstart bounds]
  (local results [])
  (var current dtstart)
  (if recurrence-rule.by-day
      (do
        (assert-daily-by-day-satisfiable recurrence-rule dtstart)
        (assert-daily-filters-satisfiable recurrence-rule dtstart)
        (var day-offset 0)
        (while (and (not (limit-reached? results bounds))
                    (within-until? current bounds.until))
          (when (and (= (% day-offset recurrence-rule.interval) 0)
                     (by-day-allowed? recurrence-rule.by-day (current:iso-weekday))
                     (candidate-calendar-filters-allowed? recurrence-rule current))
            (table.insert results current))
          (set current (current:add-days 1))
          (set day-offset (+ day-offset 1))))
      (do
        (assert-daily-filters-satisfiable recurrence-rule dtstart)
        (while (and (not (limit-reached? results bounds))
                    (within-until? current bounds.until))
          (when (candidate-calendar-filters-allowed? recurrence-rule current)
            (table.insert results current))
          (set current (current:add-days recurrence-rule.interval)))))
  results)

(fn expand-weekly [recurrence-rule dtstart bounds]
  (local results [])
  (var current dtstart)
  (var day-offset 0)
  (local default-weekday (dtstart:iso-weekday))
  (assert-weekly-filters-satisfiable recurrence-rule dtstart)
  (while (and (not (limit-reached? results bounds))
              (within-until? current bounds.until))
    (local week-offset (math.floor (/ day-offset 7)))
    (when (and (= (% week-offset recurrence-rule.interval) 0)
               (weekly-day-allowed? recurrence-rule (current:iso-weekday) default-weekday)
               (candidate-calendar-filters-allowed? recurrence-rule current))
      (table.insert results current))
    (set current (current:add-days 1))
    (set day-offset (+ day-offset 1)))
  results)

(fn compare-candidates [left right]
  (< (left:compare right) 0))

(fn sort-candidates [candidates]
  (table.sort candidates compare-candidates)
  candidates)

(fn same-date? [left right]
  (local left-fields (plain-fields left))
  (local right-fields (plain-fields right))
  (and (= left-fields.year right-fields.year)
       (= left-fields.month right-fields.month)
       (= left-fields.day right-fields.day)))

(fn candidate-present? [candidates candidate]
  (var found false)
  (each [_ existing (ipairs candidates)]
    (when (same-date? existing candidate)
      (set found true)))
  found)

(fn insert-candidate-once [candidates candidate]
  (when (and candidate (not (candidate-present? candidates candidate)))
    (table.insert candidates candidate)))

(fn days-in-month [plain-date-time year month]
  (var day 31)
  (var found nil)
  (while (and (not found) (>= day 28))
    (local (ok _value)
      (pcall plain-date-time.from-fields {:year year :month month :day day :hour 0 :minute 0 :second 0 :nanosecond 0}))
    (when ok
      (set found day))
    (set day (- day 1)))
  found)

(fn leap-year? [year]
  (if (= (% year 400) 0)
      true
      (= (% year 100) 0)
      false
      (= (% year 4) 0)
      true
      false))

(fn days-in-year [year]
  (if (leap-year? year) 366 365))

(fn day-of-year [plain-date-time candidate]
  (local fields (plain-fields candidate))
  (local month-lengths [31 28 31 30 31 30 31 31 30 31 30 31])
  (when (leap-year? fields.year)
    (set (. month-lengths 2) 29))
  (var total fields.day)
  (var month 1)
  (while (< month fields.month)
    (set total (+ total (. month-lengths month)))
    (set month (+ month 1)))
  total)

(fn weekday-offset-from-week-start [weekday week-start]
  (local start (. day-to-number week-start))
  (var offset (- weekday start))
  (when (< offset 0)
    (set offset (+ offset 7)))
  offset)

(fn start-of-week [candidate week-start]
  (candidate:add-days (- (weekday-offset-from-week-start (candidate:iso-weekday) week-start))))

(fn week-one-start [plain-date-time year week-start dtstart]
  (local jan1 (build-generated-candidate plain-date-time dtstart year 1 1))
  (local start (start-of-week jan1 week-start))
  (if (> (weekday-offset-from-week-start (jan1:iso-weekday) week-start) 3)
      (start:add-days 7)
      start))

(fn weeks-in-week-year [plain-date-time year week-start dtstart]
  (local this-start (week-one-start plain-date-time year week-start dtstart))
  (local next-start (week-one-start plain-date-time (+ year 1) week-start dtstart))
  (var weeks 0)
  (var current this-start)
  (while (< (current:compare next-start) 0)
    (set weeks (+ weeks 1))
    (set current (current:add-days 7)))
  weeks)

(fn week-number [plain-date-time candidate week-start dtstart]
  (local fields (plain-fields candidate))
  (local this-start (week-one-start plain-date-time fields.year week-start dtstart))
  (local next-start (week-one-start plain-date-time (+ fields.year 1) week-start dtstart))
  (if (< (candidate:compare this-start) 0)
      (weeks-in-week-year plain-date-time (- fields.year 1) week-start dtstart)
      (>= (candidate:compare next-start) 0)
      1
      (do
        (local candidate-week-start (start-of-week candidate week-start))
        (var week 1)
        (var current this-start)
        (var keep-counting true)
        (while keep-counting
          (local next (current:add-days 7))
          (if (<= (next:compare candidate-week-start) 0)
              (do
                (set current next)
                (set week (+ week 1)))
              (set keep-counting false)))
        week)))

(fn numeric-list-contains? [items value]
  (var found false)
  (each [_ item (ipairs items)]
    (when (= item value)
      (set found true)))
  found)

(fn resolved-month-day-allowed? [plain-date-time days candidate]
  (local fields (plain-fields candidate))
  (local month-days (days-in-month plain-date-time fields.year fields.month))
  (var allowed false)
  (each [_ value (ipairs days)]
    (local resolved (if (< value 0) (+ month-days value 1) value))
    (when (= fields.day resolved)
      (set allowed true)))
  allowed)

(fn resolved-year-day-allowed? [plain-date-time days candidate]
  (local fields (plain-fields candidate))
  (local year-days (days-in-year fields.year))
  (local candidate-day (day-of-year plain-date-time candidate))
  (var allowed false)
  (each [_ value (ipairs days)]
    (local resolved (if (< value 0) (+ year-days value 1) value))
    (when (= candidate-day resolved)
      (set allowed true)))
  allowed)

(fn resolved-week-no-allowed? [plain-date-time weeks candidate week-start dtstart]
  (local fields (plain-fields candidate))
  (local total-weeks (weeks-in-week-year plain-date-time fields.year week-start dtstart))
  (local candidate-week (week-number plain-date-time candidate week-start dtstart))
  (var allowed false)
  (each [_ value (ipairs weeks)]
    (local resolved (if (< value 0) (+ total-weeks value 1) value))
    (when (= candidate-week resolved)
      (set allowed true)))
  allowed)

(fn ordinal-by-day-allowed? [plain-date-time entry candidate yearly?]
  (local fields (plain-fields candidate))
  (local weekday (. day-to-number entry.weekday))
  (if (not= (candidate:iso-weekday) weekday)
      false
      (do
        (var ordinal 0)
        (var reverse-ordinal 0)
        (if yearly?
            (do
              (var day 1)
              (var current (build-generated-candidate plain-date-time candidate fields.year 1 1))
              (while (<= day (day-of-year plain-date-time candidate))
                (when (= (current:iso-weekday) weekday)
                  (set ordinal (+ ordinal 1)))
                (set current (current:add-days 1))
                (set day (+ day 1)))
              (var remaining (candidate:add-days 7))
              (while (= (. (plain-fields remaining) :year) fields.year)
                (when (= (remaining:iso-weekday) weekday)
                  (set reverse-ordinal (- reverse-ordinal 1)))
                (set remaining (remaining:add-days 7))))
            (do
              (var day 1)
              (while (<= day fields.day)
                (local current (build-generated-candidate plain-date-time candidate fields.year fields.month day))
                (when (= (current:iso-weekday) weekday)
                  (set ordinal (+ ordinal 1)))
                (set day (+ day 1)))
              (var day2 (days-in-month plain-date-time fields.year fields.month))
              (while (> day2 fields.day)
                (local current (build-generated-candidate plain-date-time candidate fields.year fields.month day2))
                (when (= (current:iso-weekday) weekday)
                  (set reverse-ordinal (- reverse-ordinal 1)))
                (set day2 (- day2 1)))))
        (if (> entry.ordinal 0)
            (= ordinal entry.ordinal)
            (= (- reverse-ordinal 1) entry.ordinal)))))

(fn date-by-day-allowed? [plain-date-time recurrence-rule candidate dtstart yearly?]
  (if recurrence-rule.by-day
      (do
        (var allowed false)
        (each [_ entry (ipairs recurrence-rule.by-day)]
          (if (= (type entry) :table)
              (when (ordinal-by-day-allowed? plain-date-time entry candidate yearly?)
                (set allowed true))
              (when (= (. day-to-number entry) (candidate:iso-weekday))
                (set allowed true))))
        allowed)
      (= recurrence-rule.freq :weekly)
      (= (candidate:iso-weekday) (dtstart:iso-weekday))
      true))

(fn date-selectors-allowed? [plain-date-time recurrence-rule candidate dtstart yearly?]
  (local fields (plain-fields candidate))
  (and (if recurrence-rule.by-month
           (numeric-list-contains? recurrence-rule.by-month fields.month)
           true)
       (if recurrence-rule.by-month-day
           (resolved-month-day-allowed? plain-date-time recurrence-rule.by-month-day candidate)
           true)
       (if recurrence-rule.by-year-day
           (resolved-year-day-allowed? plain-date-time recurrence-rule.by-year-day candidate)
           true)
       (if recurrence-rule.by-week-no
           (resolved-week-no-allowed? plain-date-time recurrence-rule.by-week-no candidate recurrence-rule.week-start dtstart)
           true)
       (date-by-day-allowed? plain-date-time recurrence-rule candidate dtstart yearly?)))

(fn apply-by-set-pos [recurrence-rule candidates]
  (sort-candidates candidates)
  (if recurrence-rule.by-set-pos
      (do
        (local selected [])
        (each [_ position (ipairs recurrence-rule.by-set-pos)]
          (local index (if (< position 0) (+ (# candidates) position 1) position))
          (when (and (>= index 1) (<= index (# candidates)))
            (insert-candidate-once selected (. candidates index))))
        (sort-candidates selected))
      candidates))

(fn build-day-candidates [plain-date-time recurrence-rule dtstart start days yearly?]
  (local candidates [])
  (var offset 0)
  (while (< offset days)
    (local candidate (start:add-days offset))
    (when (date-selectors-allowed? plain-date-time recurrence-rule candidate dtstart yearly?)
      (table.insert candidates candidate))
    (set offset (+ offset 1)))
  (apply-by-set-pos recurrence-rule candidates))

(fn expand-daily-candidates [plain-date-time recurrence-rule dtstart bounds]
  (local results [])
  (var current dtstart)
  (while (and (not (limit-reached? results bounds)) (within-until? current bounds.until))
    (append-generated-candidates results bounds dtstart (build-day-candidates plain-date-time recurrence-rule dtstart current 1 false))
    (set current (current:add-days recurrence-rule.interval)))
  results)

(fn expand-weekly-candidates [plain-date-time recurrence-rule dtstart bounds]
  (local results [])
  (var start (start-of-week dtstart recurrence-rule.week-start))
  (var done false)
  (while (and (not done) (not (limit-reached? results bounds)))
    (append-generated-candidates results bounds dtstart (build-day-candidates plain-date-time recurrence-rule dtstart start 7 false))
    (when (and bounds.until (> (start:compare bounds.until) 0))
      (set done true))
    (set start (start:add-days (* recurrence-rule.interval 7))))
  results)

(fn expand-monthly-candidates [period plain-date-time recurrence-rule dtstart bounds]
  (local results [])
  (var index 0)
  (var done false)
  (while (and (not done) (not (limit-reached? results bounds)))
    (local anchor (period.add-to-plain-date-time dtstart {:months (* index recurrence-rule.interval)}))
    (local fields (plain-fields anchor))
    (local start (build-generated-candidate plain-date-time dtstart fields.year fields.month 1))
    (append-generated-candidates results bounds dtstart (build-day-candidates plain-date-time recurrence-rule dtstart start (days-in-month plain-date-time fields.year fields.month) false))
    (when (and bounds.until (> (anchor:compare bounds.until) 0))
      (set done true))
    (set index (+ index 1)))
  results)

(fn expand-yearly-candidates [period plain-date-time recurrence-rule dtstart bounds]
  (local results [])
  (var index 0)
  (var done false)
  (while (and (not done) (not (limit-reached? results bounds)))
    (local anchor (period.add-to-plain-date-time dtstart {:years (* index recurrence-rule.interval)}))
    (local fields (plain-fields anchor))
    (local start (build-generated-candidate plain-date-time dtstart fields.year 1 1))
    (append-generated-candidates results bounds dtstart (build-day-candidates plain-date-time recurrence-rule dtstart start (days-in-year fields.year) true))
    (when (and bounds.until (> (anchor:compare bounds.until) 0))
      (set done true))
    (set index (+ index 1)))
  results)

(fn needs-candidate-selector-engine? [recurrence-rule]
  (if recurrence-rule.by-year-day
      true
      recurrence-rule.by-week-no
      true
      recurrence-rule.by-set-pos
      true
      (not= recurrence-rule.week-start :mo)
      true
      (has-ordinal-by-day? recurrence-rule.by-day)
      true
      (has-negative-month-day? recurrence-rule.by-month-day)
      true
      false))

(fn validate-deps [deps]
  (when (not (and deps deps.period deps.period.add-to-plain-date-time))
    (error "temporal recurrence requires period dependency"))
  (when (not (and deps.standard deps.standard.parse-plain-date-time))
    (error "temporal recurrence requires standard dependency"))
  (when (not (and deps.plain-date-time deps.plain-date-time.from-fields))
    (error "temporal recurrence requires plain-date-time dependency")))

(fn occurrences [deps input-rule dtstart options]
  (validate-deps deps)
  (local recurrence-rule (rule.from input-rule))
  (assert-supported-expansion-surface recurrence-rule)
  (local occurrence-options (rule.normalize-occurrence-options options))
  (local bounds (rule.occurrence-bounds deps.standard recurrence-rule occurrence-options))
  (if (and (= recurrence-rule.freq :daily) (needs-candidate-selector-engine? recurrence-rule))
      (expand-daily-candidates deps.plain-date-time recurrence-rule dtstart bounds)
      (and (= recurrence-rule.freq :weekly) (needs-candidate-selector-engine? recurrence-rule))
      (expand-weekly-candidates deps.plain-date-time recurrence-rule dtstart bounds)
      (and (= recurrence-rule.freq :monthly) (needs-candidate-selector-engine? recurrence-rule))
      (expand-monthly-candidates deps.period deps.plain-date-time recurrence-rule dtstart bounds)
      (and (= recurrence-rule.freq :yearly) (needs-candidate-selector-engine? recurrence-rule))
      (expand-yearly-candidates deps.period deps.plain-date-time recurrence-rule dtstart bounds)
      (or (= recurrence-rule.freq :monthly) (= recurrence-rule.freq :yearly))
      (if (or recurrence-rule.by-month-day recurrence-rule.by-day)
          (expand-calendar-generator deps.period deps.plain-date-time recurrence-rule dtstart bounds)
          (expand-calendar deps.period recurrence-rule dtstart bounds))
      (= recurrence-rule.freq :daily)
      (expand-daily recurrence-rule dtstart bounds)
      (= recurrence-rule.freq :weekly)
      (expand-weekly recurrence-rule dtstart bounds)
      (error "unsupported temporal recurrence expansion")))

{:occurrences occurrences}
