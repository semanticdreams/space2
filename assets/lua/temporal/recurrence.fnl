(local rule (require :temporal/recurrence/rule))
(local engine (require :temporal/recurrence/engine))

(fn create [deps]
  (when (not (and deps deps.period deps.period.add-to-plain-date-time))
    (error "temporal recurrence requires period dependency"))
  (when (not (and deps.standard deps.standard.parse-plain-date-time))
    (error "temporal recurrence requires standard dependency"))
  (when (not (and deps.plain-date-time deps.plain-date-time.from-fields))
    (error "temporal recurrence requires plain-date-time dependency"))
  {:from rule.from
   :parse-rrule rule.parse-rrule
   :to-rrule rule.to-rrule
   :occurrences (fn [input-rule dtstart options]
                  (engine.occurrences deps input-rule dtstart options))})

create
