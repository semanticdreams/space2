(fn has-key? [table key]
  (not (= (. table key) nil)))

(fn positive-integer? [value]
  (and (= (type value) :number)
       (= value value)
       (< value math.huge)
       (= value (math.floor value))
       (< 0 value)))

(fn validate-count [count]
  (when (and (not (= count nil))
             (not (positive-integer? count)))
    (error "temporal repeating interval count must be a positive integer")))

(fn validate-from-options [options]
  (assert (= (type options) :table) "temporal repeating interval options must be a table")
  (each [key _value (pairs options)]
    (when (and (not (= key :interval))
               (not (= key :count))
               (not (= key :step-kind))
               (not (= key :step)))
      (error (.. "invalid temporal repeating interval option: " (tostring key)))))
  (when (not (has-key? options :interval))
    (error "temporal repeating interval requires interval"))
  (validate-count options.count)
  (when (and (not (= options.step-kind nil))
             (not (= options.step-kind :exact-duration))
             (not (= options.step-kind :calendar-period)))
    (error "temporal repeating interval step-kind must be :exact-duration or :calendar-period"))
  (when (and (not (= options.step-kind nil))
             (= options.step nil))
    (error "temporal repeating interval requires step when step-kind is provided"))
  (when (and (= options.step-kind nil)
             (not (= options.step nil)))
    (error "temporal repeating interval step requires step-kind")))

(fn valid-disambiguation? [value]
  (if (= value :reject)
      true
      (= value :earliest)
      true
      (= value :latest)
      true
      false))

(fn validate-occurrence-options [options]
  (assert (= (type options) :table) "temporal repeating interval occurrence options must be a table")
  (each [key _value (pairs options)]
    (when (and (not (= key :limit))
               (not (= key :disambiguation)))
      (error (.. "invalid temporal repeating interval occurrence option: " (tostring key)))))
  (when (and (has-key? options :limit)
              (not (positive-integer? options.limit)))
    (error "temporal repeating interval limit must be a positive integer"))
  (when (and (not (= options.disambiguation nil))
             (not (valid-disambiguation? options.disambiguation)))
    (error "invalid temporal repeating interval disambiguation")))

(fn parse-repeat-prefix [prefix]
  (when (not (= (prefix:sub 1 1) "R"))
    (error "temporal repeating interval text must begin with R"))
  (local count-text (prefix:sub 2))
  (if (= count-text "")
      nil
      (count-text:match "^%d+$")
      (do
        (local count (tonumber count-text))
        (validate-count count)
        count)
      (error "temporal repeating interval repeat prefix is malformed")))

(fn period-field [period key]
  (local value (. period key))
  (if (= value nil)
      0
      (= (type value) :number)
      value
      (error (.. "temporal repeating interval period step field must be numeric: " (tostring key)))))

(fn period-format [period]
  (local negative? (if (< (period-field period :years) 0)
                       true
                       (< (period-field period :months) 0)
                       true
                       (< (period-field period :weeks) 0)
                       true
                       (< (period-field period :days) 0)
                       true
                       false))
  (local parts [])
  (fn append-field [value suffix]
    (when (not= value 0)
      (table.insert parts (.. (tostring (math.abs value)) suffix))))
  (append-field (period-field period :years) "Y")
  (append-field (period-field period :months) "M")
  (append-field (period-field period :weeks) "W")
  (append-field (period-field period :days) "D")
  (if (= (length parts) 0)
      "P0D"
      (.. (if negative? "-" "") "P" (table.concat parts ""))))

(fn interval-end-text [text]
  (var bracket-depth 0)
  (var separator-index nil)
  (for [index 1 (length text)]
    (local char (text:sub index index))
    (if (= char "[")
        (set bracket-depth (+ bracket-depth 1))
        (= char "]")
        (set bracket-depth (- bracket-depth 1))
        (and (= char "/") (= bracket-depth 0))
        (set separator-index index)))
  (when (= separator-index nil)
    (error "temporal repeating interval occurrence could not split interval text"))
  (text:sub (+ separator-index 1)))

(fn occurrence-step-kind [repeating]
  (if (= repeating.step-kind nil)
      :exact-duration
      repeating.step-kind))

(fn occurrence-step [Temporal repeating]
  (if (= repeating.step nil)
      (Temporal.interval.duration repeating.interval)
      repeating.step))

(fn occurrence-disambiguation [options]
  (if (= options.disambiguation nil)
      :reject
      options.disambiguation))

(fn calendar-next-interval [Temporal current step options]
  (when (and (not (= current.type :plain-date-time))
             (not (= current.type :zoned-date-time)))
    (error "temporal repeating interval calendar steps require :plain-date-time or :zoned-date-time"))
  (local parse-options {:type current.type})
  (when (= current.type :zoned-date-time)
    (set parse-options.disambiguation (occurrence-disambiguation options)))
  (Temporal.interval.parse
    (.. (interval-end-text (Temporal.interval.format current))
        "/"
        (period-format step))
    parse-options))

(fn next-interval [Temporal current step-kind step options]
  (if (= step-kind :exact-duration)
      (Temporal.interval.shift current step)
      (= step-kind :calendar-period)
      (calendar-next-interval Temporal current step options)
      (error "invalid temporal repeating interval step-kind")))

(fn create [Temporal]
  (fn from [options]
    (validate-from-options options)
    (if (= options.step-kind nil)
        {:kind :repeating-interval
         :interval options.interval
         :count options.count}
        {:kind :repeating-interval
         :interval options.interval
         :count options.count
         :step-kind options.step-kind
         :step options.step}))

  (fn parse [text options]
    (assert (= (type text) :string) "temporal repeating interval text must be a string")
    (local slash-at (text:find "/" 1 true))
    (when (= slash-at nil)
      (error "temporal repeating interval text requires interval"))
    (local prefix (text:sub 1 (- slash-at 1)))
    (local count (parse-repeat-prefix prefix))
    (local interval-text (text:sub (+ slash-at 1)))
    (local (interval step-kind step) (Temporal.interval._parse-with-step interval-text options))
    (from {:interval interval
           :count count
           :step-kind step-kind
           :step step}))

  (fn format [repeating]
    (.. "R"
        (if (= repeating.count nil) "" (tostring repeating.count))
        "/"
        (Temporal.interval.format repeating.interval)))

  (fn expansion-size [repeating options]
    (if (and (not (= repeating.count nil)) (has-key? options :limit))
        (math.min repeating.count options.limit)
        (not (= repeating.count nil))
        repeating.count
        (has-key? options :limit)
        options.limit
        (error "temporal repeating interval expansion requires limit")))

  (fn occurrences [repeating options]
    (validate-occurrence-options options)
    (local total (expansion-size repeating options))
    (local step-kind (occurrence-step-kind repeating))
    (local step (occurrence-step Temporal repeating))
    (local result [])
    (var current repeating.interval)
    (for [index 1 total]
      (table.insert result current)
      (set current (next-interval Temporal current step-kind step options)))
    result)

  {:from from
   :parse parse
   :format format
   :occurrences occurrences})

create
