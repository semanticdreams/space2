(fn has-key? [table key]
  (not (= (. table key) nil)))

(fn validate-endpoint-type [endpoint-type]
  (when (and (not (= endpoint-type :instant))
             (not (= endpoint-type :plain-date-time)))
    (error "temporal interval type must be :instant or :plain-date-time")))

(fn validate-from-options [options]
  (assert (= (type options) :table) "temporal interval options must be a table")
  (each [key _value (pairs options)]
    (when (and (not (= key :type))
               (not (= key :start))
               (not (= key :end)))
      (error (.. "invalid temporal interval option: " (tostring key)))))
  (when (not (has-key? options :type))
    (error "temporal interval requires type"))
  (when (not (has-key? options :start))
    (error "temporal interval requires start"))
  (when (not (has-key? options :end))
    (error "temporal interval requires end"))
  (validate-endpoint-type options.type))

(fn validate-parse-options [options]
  (assert (= (type options) :table) "temporal interval parse options must be a table")
  (each [key _value (pairs options)]
    (when (not (= key :type))
      (error (.. "invalid temporal interval parse option: " (tostring key)))))
  (when (not (has-key? options :type))
    (error "temporal interval parse requires type"))
  (validate-endpoint-type options.type))

(fn compare [left right]
  (assert (and left left.compare) "temporal interval endpoint must support compare")
  (left:compare right))

(fn instant-endpoint? [endpoint]
  (and endpoint
       (. endpoint :epoch-seconds)
       (. endpoint :nanosecond)
       endpoint.compare
       endpoint.add
       endpoint.since))

(fn plain-date-time-endpoint? [endpoint]
  (and endpoint
       endpoint.fields
       (. endpoint :iso-weekday)
       endpoint.compare
       endpoint.add
       endpoint.since))

(fn validate-endpoint-matches-type [endpoint-type endpoint label]
  (when (not (if (= endpoint-type :instant)
                 (instant-endpoint? endpoint)
                 (plain-date-time-endpoint? endpoint)))
    (error (.. "temporal interval " label " must match interval type"))))

(fn validate-range [start end]
  (when (not (< (compare start end) 0))
    (error "temporal interval start must be before end")))

(fn split-interval-text [text]
  (assert (= (type text) :string) "temporal interval text must be a string")
  (when (text:match "^R")
    (error "temporal repeating interval syntax is not supported here"))
  (local (_ slash-count) (text:gsub "/" ""))
  (when (not (= slash-count 1))
    (error "temporal interval text must contain one separator"))
  (local (start-text end-text) (text:match "^([^/]*)/([^/]*)$"))
  (when (or (= start-text nil)
            (= end-text nil)
            (= start-text "")
            (= end-text ""))
    (error "temporal interval text requires start and end"))
  (when (or (start-text:match "^P")
            (end-text:match "^P"))
    (error "temporal interval duration endpoint forms are not supported"))
  (values start-text end-text))

(fn create [Temporal]
  (fn from [options]
    (validate-from-options options)
    (validate-endpoint-matches-type options.type options.start "start")
    (validate-endpoint-matches-type options.type options.end "end")
    (validate-range options.start options.end)
    {:kind :interval
     :type options.type
     :start options.start
     :end options.end
     :bounds :half-open})

  (fn parse-endpoint [endpoint-type text]
    (if (= endpoint-type :instant)
        (Temporal.standard.parse-instant text)
        (Temporal.standard.parse-plain-date-time text)))

  (fn parse [text options]
    (validate-parse-options options)
    (local (start-text end-text) (split-interval-text text))
    (from {:type options.type
           :start (parse-endpoint options.type start-text)
           :end (parse-endpoint options.type end-text)}))

  (fn format-endpoint [endpoint-type endpoint]
    (if (= endpoint-type :instant)
        (Temporal.standard.format-instant endpoint)
        (Temporal.standard.format-plain-date-time endpoint)))

  (fn format [interval]
    (.. (format-endpoint interval.type interval.start)
        "/"
        (format-endpoint interval.type interval.end)))

  (fn duration [interval]
    (interval.end:since interval.start))

  (fn contains [interval value]
    (and (<= (compare interval.start value) 0)
         (< (compare value interval.end) 0)))

  (fn shift [interval duration]
    (from {:type interval.type
           :start (interval.start:add duration)
           :end (interval.end:add duration)}))

  {:from from
   :parse parse
   :format format
   :duration duration
   :contains contains
   :shift shift})

create
