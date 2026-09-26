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
               (not (= key :count)))
      (error (.. "invalid temporal repeating interval option: " (tostring key)))))
  (when (not (has-key? options :interval))
    (error "temporal repeating interval requires interval"))
  (validate-count options.count))

(fn validate-occurrence-options [options]
  (assert (= (type options) :table) "temporal repeating interval occurrence options must be a table")
  (each [key _value (pairs options)]
    (when (not (= key :limit))
      (error (.. "invalid temporal repeating interval occurrence option: " (tostring key)))))
  (when (and (has-key? options :limit)
             (not (positive-integer? options.limit)))
    (error "temporal repeating interval limit must be a positive integer")))

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

(fn create [Temporal]
  (fn from [options]
    (validate-from-options options)
    {:kind :repeating-interval
     :interval options.interval
     :count options.count})

  (fn parse [text options]
    (assert (= (type text) :string) "temporal repeating interval text must be a string")
    (local slash-at (text:find "/" 1 true))
    (when (= slash-at nil)
      (error "temporal repeating interval text requires interval"))
    (local prefix (text:sub 1 (- slash-at 1)))
    (local count (parse-repeat-prefix prefix))
    (local interval-text (text:sub (+ slash-at 1)))
    (from {:interval (Temporal.interval.parse interval-text options)
           :count count}))

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
    (local step (Temporal.interval.duration repeating.interval))
    (local result [])
    (var current repeating.interval)
    (for [index 1 total]
      (table.insert result current)
      (set current (Temporal.interval.shift current step)))
    result)

  {:from from
   :parse parse
   :format format
   :occurrences occurrences})

create
