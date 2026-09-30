(local rule-utils (require :temporal/recurrence/rule))

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
        (var count 0)
        (var max-index 0)
        (each [key _item (pairs value)]
          (when (not (and (= (type key) :number)
                          (= key (math.floor key))
                          (> key 0)))
            (error (.. "invalid temporal recurrence-set " name)))
          (set count (+ count 1))
          (when (> key max-index)
            (set max-index key)))
        (when (not= count max-index)
          (error (.. "invalid temporal recurrence-set " name)))
        (local result [])
        (var index 1)
        (while (<= index max-index)
          (table.insert result (item-validator (. value index)))
          (set index (+ index 1)))
        result)))

(fn validate-known-keys [value valid-keys context]
  (when (not= (type value) :table)
    (error (.. "temporal recurrence-set " context " must be a table")))
  (each [key _value (pairs value)]
    (when (not (. valid-keys key))
      (error (.. "unknown temporal recurrence-set " context " option: " (tostring key))))))

(fn list-nonempty? [items]
  (> (# items) 0))

(fn local-key [plain]
  (plain:to-string))

(fn sorted-local [items]
  (when (not= (type items) :table)
    (error "invalid temporal recurrence-set local list"))
  (table.sort items #(< ($1:compare $2) 0))
  items)

(fn bounded-rule? [rule options]
  (when (not= (type rule) :table)
    (error "invalid temporal recurrence-set rule"))
  (when (not= (type options) :table)
    (error "invalid temporal recurrence-set rule options"))
  (if rule.count
      true
      rule.until
      true
      options.local-until
      true
      options.limit
      true
      false))

(fn rule-occurrence-options [options]
  (when (not= (type options) :table)
    (error "invalid temporal recurrence-set rule occurrence options"))
  (if options.limit {:limit options.limit} {}))

(fn two-digit [value]
  (if (< value 10)
      (.. "0" value)
      (tostring value)))

(fn compact-until-from-plain [plain]
  (local fields (plain:fields))
  (.. fields.year
      (two-digit fields.month)
      (two-digit fields.day)
      "T"
      (two-digit fields.hour)
      (two-digit fields.minute)
      (two-digit fields.second)))

(fn clone-rule [rule]
  (local cloned {})
  (each [key value (pairs rule)]
    (if (= (type value) :table)
        (do
          (local copied [])
          (each [nested-key nested-value (pairs value)]
            (set (. copied nested-key) nested-value))
          (set (. cloned key) copied))
        (set (. cloned key) value)))
  cloned)

(fn utc-until-instant [deps rule]
  (when (and rule.until (rule-utils.compact-utc-until? rule.until))
    (rule-utils.parse-utc-until deps.instant rule.until)))

(fn validate-until-form [deps rule]
  (when rule.until
    (if (rule-utils.compact-utc-until? rule.until)
        true
        (do
          (local (ok _value) (pcall rule-utils.parse-until deps.standard rule.until))
          (when (not ok)
            (error "invalid temporal recurrence UNTIL"))))))

(fn local-rule-for-generation [deps rule options until-instant]
  (if until-instant
      (do
        (local zdt (deps.zoned-date-time.from-instant until-instant options.zone-id))
        (local local-until (deps.plain-date-time.from-fields (zdt:fields)))
        (local conservative-until (local-until:add-days 1))
        (local cloned (clone-rule rule))
        (set cloned.until (compact-until-from-plain conservative-until))
        cloned)
      (and options.local-until (not rule.until))
      (do
        (local cloned (clone-rule rule))
        (set cloned.until (compact-until-from-plain options.local-until))
        cloned)
      rule))

(fn candidate-within-utc-until? [deps candidate options until-instant]
  (if (= until-instant nil)
      true
      (do
        (local zdt (deps.zoned-date-time.from-plain candidate options.zone-id {:disambiguation options.disambiguation}))
        (local candidate-instant (zdt:instant))
        (<= (candidate-instant:compare until-instant) 0))))

(fn exrule-occurrence-options [rule options latest-candidate]
  (when (not= (type rule) :table)
    (error "invalid temporal recurrence-set exrule occurrence options"))
  (when (not= (type options) :table)
    (error "invalid temporal recurrence-set exrule occurrence options"))
  (if rule.count
      {}
      rule.until
      {}
      latest-candidate
      {:local-until latest-candidate}
      {}))

(fn zoned-entry [deps candidate options]
  (validate-plain-date-time candidate "zoned candidate")
  (when (not (and deps deps.zoned-date-time deps.zoned-date-time.from-plain))
    (error "temporal recurrence-set requires zoned-date-time dependency"))
  (when (not= (type options) :table)
    (error "invalid temporal recurrence-set zoned options"))
  (local zdt
    (deps.zoned-date-time.from-plain
      candidate
      options.zone-id
      {:disambiguation options.disambiguation}))
  {:local candidate :zoned zdt :instant (zdt:instant)})

(fn add-local-once [items seen candidate name]
  (when (not= (type items) :table)
    (error "invalid temporal recurrence-set local list"))
  (when (not= (type seen) :table)
    (error "invalid temporal recurrence-set local map"))
  (validate-plain-date-time candidate name)
  (local key (local-key candidate))
  (when (not (. seen key))
    (set (. seen key) true)
    (table.insert items candidate))
  items)

(fn assert-finite-rule [rule options name]
  (when (not (bounded-rule? rule options))
    (error (.. "unbounded temporal recurrence-set " name)))
  rule)

(fn expand-rule-local [deps rule dtstart options name]
  (validate-until-form deps rule)
  (local until-instant (utc-until-instant deps rule))
  (local generation-rule (local-rule-for-generation deps rule options until-instant))
  (assert-finite-rule generation-rule options name)
  (local generated (deps.recurrence.occurrences generation-rule dtstart (rule-occurrence-options options)))
  (when (not= (type generated) :table)
    (error (.. "invalid temporal recurrence-set " name " expansion")))
  (if (= until-instant nil)
      generated
      (do
        (local filtered [])
        (each [_index candidate (ipairs generated)]
          (when (candidate-within-utc-until? deps candidate options until-instant)
            (table.insert filtered candidate)))
        filtered)))

(fn local-inclusions [deps recurrence-set options]
  (when (not (= recurrence-set.kind :temporal-recurrence-set))
    (error "invalid temporal recurrence-set inclusions"))
  (local result [])
  (local seen {})
  (each [_index rule (ipairs recurrence-set.rrules)]
    (each [_generated-index candidate (ipairs (expand-rule-local deps rule recurrence-set.dtstart options "rrules"))]
      (add-local-once result seen candidate "rrules")))
  (each [_index candidate (ipairs recurrence-set.rdates)]
    (add-local-once result seen candidate "rdates"))
  (sorted-local result))

(fn latest-local-candidate [candidates]
  (when (not= (type candidates) :table)
    (error "invalid temporal recurrence-set candidate list"))
  (var latest nil)
  (each [_index candidate (ipairs candidates)]
    (when (or (= latest nil) (> (candidate:compare latest) 0))
      (set latest candidate)))
  latest)

(fn local-exclusion-map [deps recurrence-set options inclusion-candidates]
  (when (not (= recurrence-set.kind :temporal-recurrence-set))
    (error "invalid temporal recurrence-set exclusions"))
  (local exclusions {})
  (local latest-candidate (latest-local-candidate inclusion-candidates))
  (when latest-candidate
    (each [_index rule (ipairs recurrence-set.exrules)]
      (each [_generated-index candidate (ipairs (expand-rule-local deps rule recurrence-set.dtstart (exrule-occurrence-options rule options latest-candidate) "exrules"))]
        (validate-plain-date-time candidate "exrules")
        (set (. exclusions (local-key candidate)) true))))
  (each [_index candidate (ipairs recurrence-set.exdates)]
    (validate-plain-date-time candidate "exdates")
    (set (. exclusions (local-key candidate)) true))
  exclusions)

(fn apply-exclusions [candidates exclusions]
  (when (not= (type candidates) :table)
    (error "invalid temporal recurrence-set candidate list"))
  (when (not= (type exclusions) :table)
    (error "invalid temporal recurrence-set exclusion map"))
  (local result [])
  (each [_index candidate (ipairs candidates)]
    (when (not (. exclusions (local-key candidate)))
      (table.insert result candidate)))
  result)

(fn limited [items options]
  (when (not= (type items) :table)
    (error "invalid temporal recurrence-set limited list"))
  (if (= options.limit nil)
      items
      (do
        (local result [])
        (var index 1)
        (while (and (<= index (# items)) (<= index options.limit))
          (table.insert result (. items index))
          (set index (+ index 1)))
        result)))

(fn sort-zoned-entries [entries]
  (when (not= (type entries) :table)
    (error "invalid temporal recurrence-set zoned entry list"))
  (table.sort
    entries
    (fn [left right]
      (local instant-order (left.instant:compare right.instant))
      (if (not= instant-order 0)
          (< instant-order 0)
          (< (left.local:compare right.local) 0))))
  entries)

(fn zoned-results [deps candidates options]
  (when (not= (type candidates) :table)
    (error "invalid temporal recurrence-set zoned candidates"))
  (local entries [])
  (each [_index candidate (ipairs candidates)]
    (table.insert entries (zoned-entry deps candidate options)))
  (sort-zoned-entries entries)
  (local result [])
  (each [_index entry (ipairs entries)]
    (table.insert result entry.zoned))
  result)

(fn create [deps]
  (when (not (and deps deps.recurrence deps.recurrence.from deps.recurrence.occurrences))
    (error "temporal recurrence-set requires recurrence dependency"))
  (when (not (and deps.zoned-date-time deps.zoned-date-time.from-plain))
    (error "temporal recurrence-set requires zoned-date-time dependency"))
  (when (not (and deps.instant deps.instant.parse))
    (error "temporal recurrence-set requires instant dependency"))
  (when (not (and deps.plain-date-time deps.plain-date-time.from-fields))
    (error "temporal recurrence-set requires plain-date-time dependency"))
  (when (not deps.zoned-date-time.from-instant)
    (error "temporal recurrence-set requires zoned-date-time from-instant dependency"))
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
    (local normalized-options {:zone-id options.zone-id
                               :disambiguation disambiguation
                               :limit options.limit})
    (local inclusion-candidates (local-inclusions deps recurrence-set normalized-options))
    (zoned-results
      deps
      (limited
        (apply-exclusions
          inclusion-candidates
          (local-exclusion-map deps recurrence-set normalized-options inclusion-candidates))
        normalized-options)
      normalized-options))
  {:from from :occurrences occurrences})

create
