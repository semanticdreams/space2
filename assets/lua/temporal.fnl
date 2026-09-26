(local core (require :temporal-core))
(local create-standard (require :temporal/standard))
(local create-interval (require :temporal/interval))
(local create-pattern (require :temporal/pattern))
(local recurrence (require :temporal/recurrence))
(local expression (require :temporal/expression))
(local natural (require :temporal/natural))

(fn disambiguation-to-core [value]
  (if (= value :reject)
      "reject"
      (= value :earliest)
      "earliest"
      (= value :latest)
      "latest"
      (error "invalid temporal disambiguation")))

(local duration-fields
  {:seconds true
   :milliseconds true
   :microseconds true
   :nanoseconds true})

(fn validate-duration-parts [parts]
  (each [key _value (pairs parts)]
    (when (not (. duration-fields key))
      (error (.. "invalid temporal duration field: " (tostring key))))))

(fn duration-from [parts]
  (validate-duration-parts parts)
  (core.duration.from-parts
    {:seconds parts.seconds
     :milliseconds parts.milliseconds
     :microseconds parts.microseconds
     :nanoseconds parts.nanoseconds}))

(fn option-disambiguation [options]
  (if (= options nil)
      :reject
      (= options.disambiguation nil)
      :reject
      options.disambiguation))

(fn from-zoned-plain [plain zone-id options]
  (assert (= (type zone-id) :string) "temporal zone id must be a string")
  (core.zoned-date-time.from-plain
    plain
    zone-id
    (disambiguation-to-core (option-disambiguation options))))

(fn from-zoned-instant [instant zone-id]
  (assert (= (type zone-id) :string) "temporal zone id must be a string")
  (core.zoned-date-time.from-instant instant zone-id))

(local base
  {:duration {:from duration-from
              :from-nanoseconds core.duration.from-nanoseconds
              :from-seconds core.duration.from-seconds}
   :instant {:parse core.instant.parse
             :from-unix core.instant.from-unix}
   :plain-date-time {:parse core.plain-date-time.parse
                     :from-fields core.plain-date-time.from-fields}
   :zoned-date-time {:from-plain from-zoned-plain
                     :from-instant from-zoned-instant}
   :clock {:system core.clock.system
           :fixed core.clock.fixed}
   :tzdb {:version core.tzdb.version}})

(local standard (create-standard base))
(local interval (create-interval {:standard standard}))

{:duration base.duration
 :instant base.instant
 :plain-date-time base.plain-date-time
 :zoned-date-time base.zoned-date-time
 :clock base.clock
 :tzdb base.tzdb
 :standard standard
 :interval interval
 :pattern (create-pattern base)
 :recurrence recurrence
 :expression expression
 :natural natural}
