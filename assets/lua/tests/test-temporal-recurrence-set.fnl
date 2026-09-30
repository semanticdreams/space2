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

(fn r [text]
  (Temporal.recurrence.parse-rrule text))

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

(fn assembles-inclusions-exclusions-dedupes-and-orders []
  (local recurrence-set
    (Temporal.recurrence-set.from
      {:dtstart (p "2026-01-01T09:00:00")
       :rrules [(r "RRULE:FREQ=DAILY;COUNT=3")
                (r "RRULE:FREQ=WEEKLY;COUNT=2")]
       :rdates [(p "2026-01-03T09:00:00") (p "2026-01-04T09:00:00")]
       :exdates [(p "2026-01-02T09:00:00")]
       :exrules [(r "RRULE:FREQ=DAILY;INTERVAL=7;COUNT=1")]}))
  (assert-zoned-strings
    (Temporal.recurrence-set.occurrences recurrence-set {:zone-id "America/New_York"})
    ["2026-01-03T09:00:00-05:00[America/New_York]"
     "2026-01-04T09:00:00-05:00[America/New_York]"
     "2026-01-08T09:00:00-05:00[America/New_York]"]))

(fn allows-empty-results-after-exclusions []
  (local recurrence-set
    (Temporal.recurrence-set.from
      {:dtstart (p "2026-01-01T09:00:00")
       :rdates [(p "2026-01-01T09:00:00")]
       :exdates [(p "2026-01-01T09:00:00")]}))
  (assert-zoned-strings
    (Temporal.recurrence-set.occurrences recurrence-set {:zone-id "America/New_York"})
    []))

(fn applies-limit-without-backfill-after-exclusions []
  (local recurrence-set
    (Temporal.recurrence-set.from
      {:dtstart (p "2026-01-01T09:00:00")
       :rrules [(r "RRULE:FREQ=DAILY;COUNT=5")]
       :exdates [(p "2026-01-01T09:00:00")]}))
  (assert-zoned-strings
    (Temporal.recurrence-set.occurrences recurrence-set {:zone-id "America/New_York" :limit 2})
    ["2026-01-02T09:00:00-05:00[America/New_York]"]))

(fn bounded-exrule-excludes-later-rdate-before-output-limit []
  (local recurrence-set
    (Temporal.recurrence-set.from
      {:dtstart (p "2026-01-01T09:00:00")
       :rdates [(p "2026-01-10T09:00:00") (p "2026-01-11T09:00:00")]
       :exrules [(r "RRULE:FREQ=DAILY;COUNT=10")]}))
  (assert-zoned-strings
    (Temporal.recurrence-set.occurrences recurrence-set {:zone-id "America/New_York" :limit 2})
    ["2026-01-11T09:00:00-05:00[America/New_York]"]))

(fn enforces-finite-expansion []
  (local unbounded
    (Temporal.recurrence-set.from
      {:dtstart (p "2026-01-01T09:00:00")
       :rrules [(r "RRULE:FREQ=DAILY")]}))
  (assert-error-contains
    #(Temporal.recurrence-set.occurrences unbounded {:zone-id "America/New_York"})
    "unbounded"
    "unbounded recurrence-set should throw")
  (assert-zoned-strings
    (Temporal.recurrence-set.occurrences unbounded {:zone-id "America/New_York" :limit 2})
    ["2026-01-01T09:00:00-05:00[America/New_York]"
     "2026-01-02T09:00:00-05:00[America/New_York]"]))

(table.insert tests {:name "exports recurrence-set and expands RDATE-only"
                     :fn exports-recurrence-set-and-expands-rdate-only})
(table.insert tests {:name "validates constructor and occurrence options"
                      :fn validates-constructor-and-occurrence-options})
(table.insert tests {:name "assembles inclusions, exclusions, dedupes, and orders"
                     :fn assembles-inclusions-exclusions-dedupes-and-orders})
(table.insert tests {:name "allows empty results after exclusions"
                     :fn allows-empty-results-after-exclusions})
(table.insert tests {:name "applies limit without backfill after exclusions"
                      :fn applies-limit-without-backfill-after-exclusions})
(table.insert tests {:name "bounded EXRULE excludes later RDATE before output limit"
                     :fn bounded-exrule-excludes-later-rdate-before-output-limit})
(table.insert tests {:name "enforces finite expansion"
                      :fn enforces-finite-expansion})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-recurrence-set" :tests tests})))

{:name "temporal-recurrence-set" :tests tests :main main}
