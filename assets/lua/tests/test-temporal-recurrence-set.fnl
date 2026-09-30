(local tests [])
(local Temporal (require :temporal))

(fn assert-error [f message]
  (local (ok err) (pcall f))
  (assert (not ok) message)
  err)

(fn assert-error-contains [f fragment message]
  (local err (assert-error f message))
  (assert (tostring err):find fragment 1 true)
  err)

(fn p [text]
  (Temporal.plain-date-time.parse text))

(fn assert-zoned-strings [actual expected]
  (assert (= (# actual) (# expected)))
  (each [index value (ipairs expected)]
    (local occurrence (. actual index))
    (assert (= (occurrence:to-string) value))
    (assert occurrence.instant)))

(fn exports-recurrence-set-and-expands-rdate-only []
  (assert Temporal.recurrence-set)
  (assert (= (type Temporal.recurrence-set.from) :function))
  (assert (= (type Temporal.recurrence-set.occurrences) :function))
  (local recurrence-set
    (Temporal.recurrence-set.from
      {:dtstart (p "2026-03-06T01:30:00")
       :rdates [(p "2026-03-10T01:30:00")]}))
  (assert (= recurrence-set.kind :temporal-recurrence-set))
  (assert-zoned-strings
    (Temporal.recurrence-set.occurrences recurrence-set {:zone-id "America/New_York"})
    ["2026-03-10T01:30:00-04:00[America/New_York]"]))

(fn validates-constructor-and-occurrence-options []
  (assert-error-contains
    #(Temporal.recurrence-set.from {:rdates [(p "2026-01-01T09:00:00")]})
    "dtstart"
    "missing dtstart should identify dtstart")
  (assert-error-contains
    #(Temporal.recurrence-set.from {:dtstart (p "2026-01-01T09:00:00")})
    "inclusion"
    "missing inclusion source should identify inclusion")
  (assert-error-contains
    #(Temporal.recurrence-set.from {:dtstart (p "2026-01-01T09:00:00")
                                    :rrule []})
    "rrule"
    "singular rrule alias should be rejected")
  (assert-error-contains
    #(Temporal.recurrence-set.from {:dtstart (p "2026-01-01T09:00:00")
                                    :rdates (p "2026-01-01T09:00:00")})
    "rdates"
    "non-list rdates should identify rdates")
  (local recurrence-set
    (Temporal.recurrence-set.from
      {:dtstart (p "2026-01-01T09:00:00")
       :rdates [(p "2026-01-01T09:00:00")]}))
  (assert-error-contains
    #(Temporal.recurrence-set.occurrences recurrence-set {})
    "zone-id"
    "missing zone-id should identify zone-id")
  (assert-error-contains
    #(Temporal.recurrence-set.occurrences recurrence-set {:zone-id "America/New_York"
                                                          :timezone "America/New_York"})
    "timezone"
    "unknown occurrence option should identify the rejected key")
  (assert-error-contains
    #(Temporal.recurrence-set.occurrences recurrence-set {:zone-id "America/New_York"
                                                          :disambiguation :middle})
    "disambiguation"
    "invalid disambiguation should identify disambiguation"))

(table.insert tests {:name "exports recurrence-set and expands RDATE-only"
                     :fn exports-recurrence-set-and-expands-rdate-only})
(table.insert tests {:name "validates constructor and occurrence options"
                     :fn validates-constructor-and-occurrence-options})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-recurrence-set" :tests tests})))

{:name "temporal-recurrence-set" :tests tests :main main}
