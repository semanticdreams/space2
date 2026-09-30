(local constructor-keys {:dtstart true :rrules true :rdates true :exdates true :exrules true})
(local occurrence-option-keys {:zone-id true :disambiguation true :limit true})
(local valid-disambiguation {:reject true :earliest true :latest true})

(fn positive-integer? [value]
  (and (= (type value) :number) (= value (math.floor value)) (> value 0)))

(fn validate-plain-date-time [value name]
  (when (not (and value value.compare value.to-string value.fields))
    (error (.. "invalid temporal recurrence-set " name)))
  value)

(fn validate-rule [deps value name]
  (when (not= (type value) :table)
    (error (.. "invalid temporal recurrence-set " name)))
  (deps.recurrence.from value))

(fn copy-normalized-list [value name item-validator]
  (if (= value nil)
      []
      (do
        (when (not= (type value) :table)
          (error (.. "invalid temporal recurrence-set " name)))
        (local result [])
        (each [_index item (ipairs value)]
          (table.insert result (item-validator item)))
        result)))

(fn validate-known-keys [value valid-keys context]
  (when (not= (type value) :table)
    (error (.. "temporal recurrence-set " context " must be a table")))
  (each [key _value (pairs value)]
    (when (not (. valid-keys key))
      (error (.. "unknown temporal recurrence-set " context " option: " (tostring key))))))

(fn list-nonempty? [items]
  (> (# items) 0))

(fn create [deps]
  (when (not (and deps deps.recurrence deps.recurrence.from))
    (error "temporal recurrence-set requires recurrence dependency"))
  (when (not (and deps.zoned-date-time deps.zoned-date-time.from-plain))
    (error "temporal recurrence-set requires zoned-date-time dependency"))
  (fn from [options]
    (validate-known-keys options constructor-keys "constructor")
    (local dtstart (validate-plain-date-time options.dtstart "dtstart"))
    (local rrules
      (copy-normalized-list
        options.rrules
        "rrules"
        #(validate-rule deps $1 "rrules")))
    (local rdates
      (copy-normalized-list
        options.rdates
        "rdates"
        #(validate-plain-date-time $1 "rdates")))
    (local exdates
      (copy-normalized-list
        options.exdates
        "exdates"
        #(validate-plain-date-time $1 "exdates")))
    (local exrules
      (copy-normalized-list
        options.exrules
        "exrules"
        #(validate-rule deps $1 "exrules")))
    (when (not (or (list-nonempty? rrules) (list-nonempty? rdates)))
      (error "invalid temporal recurrence-set inclusion sources"))
    {:kind :temporal-recurrence-set
     :dtstart dtstart
     :rrules rrules
     :rdates rdates
     :exdates exdates
     :exrules exrules})
  (fn occurrences [recurrence-set options]
    (when (not (and (= (type recurrence-set) :table)
                    (= recurrence-set.kind :temporal-recurrence-set)))
      (error "invalid temporal recurrence-set"))
    (validate-known-keys options occurrence-option-keys "occurrence")
    (when (not= (type options.zone-id) :string)
      (error "invalid temporal recurrence-set zone-id"))
    (local disambiguation
      (if (= options.disambiguation nil)
          :reject
          options.disambiguation))
    (when (not (. valid-disambiguation disambiguation))
      (error "invalid temporal recurrence-set disambiguation"))
    (when (and (not= options.limit nil) (not (positive-integer? options.limit)))
      (error "invalid temporal recurrence-set limit"))
    (when (or (list-nonempty? recurrence-set.rrules)
              (list-nonempty? recurrence-set.exdates)
              (list-nonempty? recurrence-set.exrules))
      (error "temporal recurrence-set occurrences currently support RDATE-only expansion"))
    (local result [])
    (var count 0)
    (each [_index candidate (ipairs recurrence-set.rdates)]
      (when (or (= options.limit nil) (< count options.limit))
        (table.insert result
                      (deps.zoned-date-time.from-plain
                        candidate
                        options.zone-id
                        {:disambiguation disambiguation}))
        (set count (+ count 1))))
    result)
  {:from from :occurrences occurrences})

create
