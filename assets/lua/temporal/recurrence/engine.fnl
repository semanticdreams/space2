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
  (local occurrence-options (rule.normalize-occurrence-options options))
  (local bounds (rule.occurrence-bounds deps.standard recurrence-rule occurrence-options))
  (if (or (= recurrence-rule.freq :monthly) (= recurrence-rule.freq :yearly))
      (if (or recurrence-rule.by-month-day recurrence-rule.by-day)
          (expand-calendar-generator deps.period deps.plain-date-time recurrence-rule dtstart bounds)
          (expand-calendar deps.period recurrence-rule dtstart bounds))
      (= recurrence-rule.freq :daily)
      (expand-daily recurrence-rule dtstart bounds)
      (= recurrence-rule.freq :weekly)
      (expand-weekly recurrence-rule dtstart bounds)
      (error "unsupported temporal recurrence expansion")))

{:occurrences occurrences}
