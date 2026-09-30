(local grammar (require :temporal/interval/grammar))

(fn has-key? [table key]
  (not (= (. table key) nil)))

(fn validate-endpoint-type [endpoint-type]
  (when (and (not (= endpoint-type :instant))
             (not (= endpoint-type :plain-date-time))
             (not (= endpoint-type :zoned-date-time)))
    (error "temporal interval type must be :instant, :plain-date-time, or :zoned-date-time")))

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

(fn zoned-instant [endpoint]
  (if (= (type endpoint.instant) :function)
      (endpoint.instant endpoint)
      endpoint.instant))

(fn zoned-zone-id [endpoint]
  (local zone-id (. endpoint :zone-id))
  (if (= (type zone-id) :function)
      (zone-id endpoint)
      zone-id))

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

(fn zoned-date-time-endpoint? [endpoint]
  (and endpoint
       endpoint.fields
       endpoint.instant
       endpoint.zone-id
       endpoint.to-string))

(fn validate-endpoint-matches-type [endpoint-type endpoint label]
  (when (not (if (= endpoint-type :instant)
                  (instant-endpoint? endpoint)
                  (= endpoint-type :plain-date-time)
                  (plain-date-time-endpoint? endpoint)
                  (zoned-date-time-endpoint? endpoint)))
    (error (.. "temporal interval " label " must match interval type"))))

(fn compare-endpoints [endpoint-type left right]
  (if (= endpoint-type :zoned-date-time)
      (compare (zoned-instant left) (zoned-instant right))
      (compare left right)))

(fn validate-matching-zone [start end]
  (when (not (= (zoned-zone-id start) (zoned-zone-id end)))
    (error "temporal zoned interval endpoints must use the same zone")))

(fn validate-range [endpoint-type start end]
  (when (= endpoint-type :zoned-date-time)
    (validate-matching-zone start end))
  (when (not (< (compare-endpoints endpoint-type start end) 0))
    (error "temporal interval start must be before end")))

(fn negated-exact-duration-text [text]
  (if (= (text:sub 1 1) "-")
      (text:sub 2)
      (.. "-" text)))

(fn endpoint-duration [endpoint-type start end]
  (if (= endpoint-type :zoned-date-time)
      (do
        (local end-instant (zoned-instant end))
        (local start-instant (zoned-instant start))
        (end-instant:since start-instant))
      (end:since start)))

(fn create [Temporal]
  (fn from [options]
    (validate-from-options options)
    (validate-endpoint-matches-type options.type options.start "start")
    (validate-endpoint-matches-type options.type options.end "end")
    (validate-range options.type options.start options.end)
    {:kind :interval
     :type options.type
     :start options.start
     :end options.end
     :bounds :half-open})

  (fn parse-endpoint [endpoint-type text]
    (if (= endpoint-type :instant)
        (Temporal.standard.parse-instant text)
        (= endpoint-type :plain-date-time)
        (Temporal.standard.parse-plain-date-time text)
        (Temporal.standard.parse-zoned-date-time text)))

  (fn exact-shift [endpoint-type endpoint duration]
    (if (= endpoint-type :zoned-date-time)
        (do
          (local instant (zoned-instant endpoint))
          (local shifted-instant (instant:add duration))
          (Temporal.zoned-date-time.from-instant shifted-instant (zoned-zone-id endpoint)))
        (endpoint:add duration)))

  (fn resolve-parse-endpoints [endpoint-type start-text end-text]
    (local start-kind (grammar.endpoint-kind start-text))
    (local end-kind (grammar.endpoint-kind end-text))
    (local start-derived? (not (= start-kind :concrete)))
    (local end-derived? (not (= end-kind :concrete)))
    (when (and start-derived? end-derived?)
      (error "temporal interval requires one concrete endpoint when using a derived endpoint"))
    (when (and (if (= start-kind :calendar-period) true (= end-kind :calendar-period))
                (not (= endpoint-type :plain-date-time)))
      (error "temporal interval period endpoint forms require :plain-date-time"))
    (if (= end-kind :calendar-period)
        (do
          (local start (parse-endpoint endpoint-type start-text))
          (local period (Temporal.period.parse end-text))
          (values start (Temporal.period.add-to-plain-date-time start period) :calendar-period period))
        (= start-kind :calendar-period)
        (do
          (local end (parse-endpoint endpoint-type end-text))
          (local period (Temporal.period.parse start-text))
          (values (Temporal.period.subtract-from-plain-date-time end period) end :calendar-period period))
        (= end-kind :exact-duration)
        (do
          (local start (parse-endpoint endpoint-type start-text))
          (local duration (grammar.parse-exact-duration Temporal.duration end-text))
          (values start (exact-shift endpoint-type start duration) :exact-duration duration))
        (= start-kind :exact-duration)
        (do
          (local end (parse-endpoint endpoint-type end-text))
          (local duration (grammar.parse-exact-duration Temporal.duration start-text))
          (local inverse-duration
            (grammar.parse-exact-duration Temporal.duration (negated-exact-duration-text start-text)))
          (values (exact-shift endpoint-type end inverse-duration) end :exact-duration duration))
        (do
          (local start (parse-endpoint endpoint-type start-text))
          (local end (parse-endpoint endpoint-type end-text))
          (values start end :exact-duration (endpoint-duration endpoint-type start end)))))

  (fn _parse-with-step [text options]
    (validate-parse-options options)
    (local (start-text end-text) (grammar.split-interval-text text))
    (local (start end step-kind step) (resolve-parse-endpoints options.type start-text end-text))
    (values (from {:type options.type
                   :start start
                   :end end})
            step-kind
            step))

  (fn parse [text options]
    (local (interval _step-kind _step) (_parse-with-step text options))
    interval)

  (fn format-endpoint [endpoint-type endpoint]
    (if (= endpoint-type :instant)
        (Temporal.standard.format-instant endpoint)
        (= endpoint-type :plain-date-time)
        (Temporal.standard.format-plain-date-time endpoint)
        (Temporal.standard.format-zoned-date-time endpoint)))

  (fn format [interval]
    (.. (format-endpoint interval.type interval.start)
        "/"
        (format-endpoint interval.type interval.end)))

  (fn duration [interval]
    (endpoint-duration interval.type interval.start interval.end))

  (fn contains [interval value]
    (if (= interval.type :zoned-date-time)
        (do
          (validate-endpoint-matches-type interval.type value "value")
          (local start-instant (zoned-instant interval.start))
          (local value-instant (zoned-instant value))
          (local end-instant (zoned-instant interval.end))
          (and (<= (compare start-instant value-instant) 0)
               (< (compare value-instant end-instant) 0)))
        (and (<= (compare interval.start value) 0)
             (< (compare value interval.end) 0))))

  (fn shift [interval duration]
    (from {:type interval.type
            :start (exact-shift interval.type interval.start duration)
            :end (exact-shift interval.type interval.end duration)}))

  {:from from
   :parse parse
   :format format
   :duration duration
   :contains contains
   :shift shift
   :_parse-with-step _parse-with-step})

create
