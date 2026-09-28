(local rule (require :temporal/recurrence/rule))
(local day-to-number rule.day-to-number)
(local number-to-day rule.number-to-day)

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

(fn by-day-filter-allowed? [rule candidate]
  (if rule.by-day
      (by-day-allowed? rule.by-day (candidate:iso-weekday))
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

(fn month-weekday-candidates [plain-date-time rule dtstart year month]
  (local generated [])
  (var day 1)
  (while (<= day 31)
    (local candidate (build-generated-candidate plain-date-time dtstart year month day))
    (when (and candidate
               (by-day-filter-allowed? rule candidate))
      (table.insert generated candidate))
    (set day (+ day 1)))
  generated)

(fn monthly-generated-candidates [plain-date-time rule dtstart anchor]
  (local fields (plain-fields anchor))
  (local generated [])
  (when (month-filter-allowed? rule anchor)
    (if rule.by-month-day
        (each [_ day (ipairs rule.by-month-day)]
          (local candidate (build-generated-candidate plain-date-time dtstart fields.year fields.month day))
          (when (and candidate (by-day-filter-allowed? rule candidate))
            (table.insert generated candidate)))
        rule.by-day
        (each [_ candidate (ipairs (month-weekday-candidates plain-date-time rule dtstart fields.year fields.month))]
          (table.insert generated candidate))))
  generated)

(fn yearly-generated-months [rule dtstart]
  (if rule.by-month
      rule.by-month
      [(plain-month dtstart)]))

(fn yearly-generated-candidates [plain-date-time rule dtstart anchor]
  (local fields (plain-fields anchor))
  (local generated [])
  (each [_ month (ipairs (yearly-generated-months rule dtstart))]
    (if rule.by-month-day
        (each [_ day (ipairs rule.by-month-day)]
          (local candidate (build-generated-candidate plain-date-time dtstart fields.year month day))
          (when (and candidate (by-day-filter-allowed? rule candidate))
            (table.insert generated candidate)))
        rule.by-day
        (each [_ candidate (ipairs (month-weekday-candidates plain-date-time rule dtstart fields.year month))]
          (table.insert generated candidate))))
  generated)

(fn append-generated-candidates [results bounds dtstart candidates]
  (each [_ candidate (ipairs candidates)]
    (when (and (not (limit-reached? results bounds))
               (not (before-dtstart? candidate dtstart))
               (within-until? candidate bounds.until))
      (table.insert results candidate))))

(fn generated-candidates-for-anchor [plain-date-time rule dtstart anchor]
  (if (= rule.freq :monthly)
      (monthly-generated-candidates plain-date-time rule dtstart anchor)
      (= rule.freq :yearly)
      (yearly-generated-candidates plain-date-time rule dtstart anchor)
      []))

(fn generator-cycle [rule]
  (if (= rule.freq :monthly)
      (/ 4800 (gcd rule.interval 4800))
      (= rule.freq :yearly)
      (/ 400 (gcd rule.interval 400))
      (error "unsupported temporal recurrence expansion")))

(fn assert-generator-filters-satisfiable [period plain-date-time rule dtstart]
  (local cycle (generator-cycle rule))
  (var index 0)
  (var satisfiable false)
  (while (and (< index cycle) (not satisfiable))
    (local anchor
      (if (= index 0)
          dtstart
          (period.add-to-plain-date-time
            dtstart
            (calendar-step-period rule.freq (* index rule.interval)))))
    (each [_ candidate (ipairs (generated-candidates-for-anchor plain-date-time rule dtstart anchor))]
      (when candidate
        (set satisfiable true)))
    (set index (+ index 1)))
  (when (not satisfiable)
    (error "unsupported temporal recurrence expansion")))

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

(fn expand-calendar-generator [period plain-date-time rule dtstart bounds]
  (period.add-to-plain-date-time dtstart (calendar-step-period rule.freq 0))
  (assert-generator-filters-satisfiable period plain-date-time rule dtstart)
  (local results [])
  (var index 0)
  (var done false)
  (while (and (not done) (not (limit-reached? results bounds)))
    (local anchor
      (if (= index 0)
          dtstart
          (period.add-to-plain-date-time
            dtstart
            (calendar-step-period rule.freq (* index rule.interval)))))
    (append-generated-candidates
      results
      bounds
      dtstart
      (generated-candidates-for-anchor plain-date-time rule dtstart anchor))
    (when (and bounds.until (> (anchor:compare bounds.until) 0))
      (set done true))
    (when (not done)
      (set index (+ index 1))))
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

(fn occurrences [period standard plain-date-time input-rule dtstart options]
  (local recurrence-rule (rule.from input-rule))
  (local occurrence-options (rule.normalize-occurrence-options options))
  (local bounds (rule.occurrence-bounds standard recurrence-rule occurrence-options))
  (if (or (= recurrence-rule.freq :monthly) (= recurrence-rule.freq :yearly))
      (if (or recurrence-rule.by-month-day recurrence-rule.by-day)
          (expand-calendar-generator period plain-date-time recurrence-rule dtstart bounds)
          (expand-calendar period recurrence-rule dtstart bounds))
      (= recurrence-rule.freq :daily)
      (expand-daily recurrence-rule dtstart bounds)
      (= recurrence-rule.freq :weekly)
      (expand-weekly recurrence-rule dtstart bounds)
      (error "unsupported temporal recurrence expansion")))

(fn create [deps]
  (when (not (and deps deps.period deps.period.add-to-plain-date-time))
    (error "temporal recurrence requires period dependency"))
  (when (not (and deps.standard deps.standard.parse-plain-date-time))
    (error "temporal recurrence requires standard dependency"))
  (when (not (and deps.plain-date-time deps.plain-date-time.from-fields))
    (error "temporal recurrence requires plain-date-time dependency"))
  (local period deps.period)
  (local standard deps.standard)
  (local plain-date-time deps.plain-date-time)
  {:from rule.from
   :parse-rrule rule.parse-rrule
   :to-rrule rule.to-rrule
   :occurrences (fn [rule dtstart options]
                    (occurrences period standard plain-date-time rule dtstart options))})

create
