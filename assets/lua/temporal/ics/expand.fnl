(local value (require :temporal/ics/value))

(local option-keys {:zone-id true :disambiguation true :limit true})
(local valid-disambiguation {:reject true :earliest true :latest true})
(local max-backfill-raw-limit 1048576)

(fn positive-integer? [candidate]
  (and (= (type candidate) :number)
       (= candidate (math.floor candidate))
       (> candidate 0)))

(fn validate-options [options]
  (local raw (or options {}))
  (when (not= (type raw) :table)
    (error "temporal ICS expand options must be a table"))
  (each [key _ (pairs raw)]
    (when (not (. option-keys key))
      (error (.. "unknown temporal ICS expand option: " (tostring key)))))
  (local disambiguation (or raw.disambiguation :reject))
  (when (not (. valid-disambiguation disambiguation))
    (error "invalid temporal ICS expand disambiguation"))
  (when (and (not= raw.limit nil) (not (positive-integer? raw.limit)))
    (error "invalid temporal ICS expand limit"))
  {:zone-id raw.zone-id
   :disambiguation disambiguation
   :limit raw.limit})

(fn list-nonempty? [items]
  (and (= (type items) :table) (> (# items) 0)))

(fn recurring-event? [event]
  (if (list-nonempty? event.rrules)
      true
      (list-nonempty? event.rdates)
      true
      (list-nonempty? event.exdates)
      true
      (list-nonempty? event.exrules)
      true
      false))

(fn copy-wrapper [wrapper]
  (local copied {})
  (each [key item (pairs wrapper)]
    (set (. copied key) item))
  copied)

(fn wrapper->plain [Temporal wrapper]
  (if (= wrapper.value-type :date)
      (value.date->plain Temporal wrapper.date)
      (= wrapper.time-mode :floating)
      wrapper.plain
      (= wrapper.time-mode :zoned)
      wrapper.plain
      (= wrapper.time-mode :utc)
      (do
        (local zdt (Temporal.zoned-date-time.from-instant wrapper.instant "UTC"))
        (Temporal.plain-date-time.from-fields (zdt:fields)))
      (error "unsupported temporal ICS recurrence value mode")))

(fn plain->wrapper [Temporal template plain]
  (if (= template.value-type :date)
      {:kind :temporal-ics-date-time
       :value-type :date
       :date (value.plain->date plain)}
      (= template.time-mode :floating)
      {:kind :temporal-ics-date-time
       :value-type :date-time
       :time-mode :floating
       :plain plain}
      (= template.time-mode :zoned)
      {:kind :temporal-ics-date-time
       :value-type :date-time
       :time-mode :zoned
       :zone-id template.zone-id
       :plain plain}
      (= template.time-mode :utc)
      (do
        (local zdt (Temporal.zoned-date-time.from-plain plain "UTC"))
        {:kind :temporal-ics-date-time
         :value-type :date-time
         :time-mode :utc
         :instant (zdt:instant)})
      (error "unsupported temporal ICS recurrence value mode")))

(fn zoned-endpoint [Temporal wrapper options]
  (Temporal.zoned-date-time.from-plain
    wrapper.plain
    wrapper.zone-id
    {:disambiguation options.disambiguation}))

(fn zoned-instant [zdt]
  (if (= (type zdt.instant) :function)
      (zdt:instant)
      zdt.instant))

(fn wrapper-instant [Temporal wrapper options]
  (if (= wrapper.value-type :date)
      nil
      (= wrapper.time-mode :utc)
      wrapper.instant
      (= wrapper.time-mode :zoned)
      (zoned-instant (zoned-endpoint Temporal wrapper options))
      (= wrapper.time-mode :floating)
      (zoned-instant
        (Temporal.zoned-date-time.from-plain
          wrapper.plain
          options.zone-id
          {:disambiguation options.disambiguation}))
      nil))

(fn wrapper-precedes? [Temporal start end options]
  (if (= start.value-type :date)
      (< ((value.date->plain Temporal start.date):compare (value.date->plain Temporal end.date)) 0)
      (= start.time-mode :utc)
      (< (start.instant:compare end.instant) 0)
      (= start.time-mode :zoned)
      (do
        (local start-zoned (zoned-endpoint Temporal start options))
        (local end-zoned (zoned-endpoint Temporal end options))
        (local start-instant (zoned-instant start-zoned))
        (local end-instant (zoned-instant end-zoned))
        (< (start-instant:compare end-instant) 0))
      (= start.time-mode :floating)
      (< (start.plain:compare end.plain) 0)
      false))

(fn exact-duration-between [Temporal start end options]
  (if (= start.time-mode :utc)
      (end.instant:since start.instant)
      (= start.time-mode :zoned)
      (do
        (local start-zoned (zoned-endpoint Temporal start options))
        (local end-zoned (zoned-endpoint Temporal end options))
        (local start-instant (zoned-instant start-zoned))
        (local end-instant (zoned-instant end-zoned))
        (end-instant:since start-instant))
      (= start.time-mode :floating)
      (end.plain:since start.plain)
      nil))

(fn start-plus-duration [Temporal start duration options]
  (if (= start.time-mode :zoned)
      (do
        (local zoned-start (zoned-endpoint Temporal start options))
        (local start-instant (zoned-instant zoned-start))
        (local shifted-instant (start-instant:add duration))
        (local shifted-zoned (Temporal.zoned-date-time.from-instant shifted-instant start.zone-id))
        {:kind :temporal-ics-date-time
         :value-type :date-time
         :time-mode :zoned
         :zone-id start.zone-id
         :plain (Temporal.plain-date-time.from-fields (shifted-zoned:fields))})
      (value.start-plus-duration Temporal start duration)))

(fn day-span [Temporal start-date end-date]
  (var current (value.date->plain Temporal start-date))
  (local target (value.date->plain Temporal end-date))
  (var days 0)
  (while (< (current:compare target) 0)
    (set current (current:add-days 1))
    (set days (+ days 1)))
  (when (not= (current:compare target) 0)
    (error "temporal ICS all-day DTEND must not precede DTSTART"))
  (Temporal.period.from {:days days}))

(fn default-end [Temporal start]
  (if (= start.value-type :date)
      (do
        (local plain (value.date->plain Temporal start.date))
        (local next-plain (plain:add-days 1))
        {:kind :temporal-ics-date-time
         :value-type :date
         :date (value.plain->date next-plain)})
      (value.default-end Temporal start)))

(fn event-duration [Temporal event options]
  (if event.duration
      event.duration
      event.dtend
      (if (= event.dtstart.value-type :date)
          (day-span Temporal event.dtstart.date event.dtend.date)
          (exact-duration-between Temporal event.dtstart event.dtend options))
      nil))

(fn occurrence-end-with-options [Temporal start event duration options]
  (if duration
      (start-plus-duration Temporal start duration options)
      (and event.dtend (not (recurring-event? event)))
      event.dtend
      (default-end Temporal start)))

(fn add-interval-fields! [Temporal occurrence options]
  (local start occurrence.start)
  (local end occurrence.end)
  (when (and (= start.value-type :date-time) (wrapper-precedes? Temporal start end options))
    (if (= start.time-mode :utc)
        (set occurrence.instant-interval
             (Temporal.interval.from {:type :instant :start start.instant :end end.instant}))
        (= start.time-mode :zoned)
        (set occurrence.zoned-interval
             (Temporal.interval.from {:type :zoned-date-time
                                      :start (zoned-endpoint Temporal start options)
                                      :end (zoned-endpoint Temporal end options)}))
        nil))
  occurrence)

(fn make-occurrence [Temporal event start options]
  (local duration (event-duration Temporal event options))
  (local occurrence {:kind :temporal-ics-occurrence
                     :uid event.uid
                     :event event
                     :recurrence-id start
                     :start start
                     :end (occurrence-end-with-options Temporal start event duration options)
                     :status event.status})
  (when event.summary
    (set occurrence.summary event.summary))
  (when event.description
    (set occurrence.description event.description))
  (add-interval-fields! Temporal occurrence options))

(fn validate-floating-zone [event options]
  (when (and (= event.dtstart.value-type :date-time)
             (= event.dtstart.time-mode :floating)
             (not= (type options.zone-id) :string))
    (error "temporal ICS floating expansion requires string :zone-id")))

(fn recurrence-zone-id [event options]
  (if (= event.dtstart.value-type :date)
      "UTC"
      (= event.dtstart.time-mode :utc)
      "UTC"
      (= event.dtstart.time-mode :zoned)
      event.dtstart.zone-id
      (= event.dtstart.time-mode :floating)
      options.zone-id
      (error "unsupported temporal ICS recurrence zone mode")))

(fn recurrence-date-list [Temporal event key]
  (local result [])
  (each [_ wrapper (ipairs (if (= (. event key) nil) [] (. event key)))]
    (when (not (value.same-mode? event.dtstart wrapper))
      (error (.. "temporal ICS " (tostring key) " mode must match DTSTART")))
    (table.insert result (wrapper->plain Temporal wrapper)))
  result)

(fn recurrence-rdates [Temporal event]
  (local result [(wrapper->plain Temporal event.dtstart)])
  (each [_ plain (ipairs (recurrence-date-list Temporal event :rdates))]
    (table.insert result plain))
  result)

(fn recurrence-set [Temporal event]
  (Temporal.recurrence-set.from
    {:dtstart (wrapper->plain Temporal event.dtstart)
     :rrules event.rrules
     :rdates (recurrence-rdates Temporal event)
     :exdates (recurrence-date-list Temporal event :exdates)
     :exrules event.exrules}))

(fn recurrence-occurrence-options [event options limit]
  {:zone-id (recurrence-zone-id event options)
   :disambiguation options.disambiguation
   :limit limit})

(fn bounded-rule? [rule]
  (if rule.count
      true
      rule.until
      true
      false))

(fn has-unbounded-rrule? [event]
  (var unbounded? false)
  (each [_ rule (ipairs event.rrules)]
    (when (not (bounded-rule? rule))
      (set unbounded? true)))
  unbounded?)

(fn has-exclusions? [event]
  (if (list-nonempty? event.exdates)
      true
      (list-nonempty? event.exrules)
      true
      false))

(fn initial-raw-limit [event options]
  (if (= options.limit nil)
      nil
      (and (has-exclusions? event) (not (has-unbounded-rrule? event)))
      nil
      options.limit))

(fn safe-recurrence-occurrences [Temporal recurrence-set-record event options raw-limit]
  (local (ok result)
    (pcall #(Temporal.recurrence-set.occurrences
              recurrence-set-record
              (recurrence-occurrence-options event options raw-limit))))
  (if ok
      result
      (do
        (local message (tostring result))
        (if (and (message:find "unbounded" 1 true)
                 (message:find "recurrence-set" 1 true))
            (error "temporal ICS recurrence expansion requires :limit for unbounded recurrence")
            (error result)))))

(fn truncate-occurrences [occurrences limit]
  (if (= limit nil)
      occurrences
      (do
        (local truncated [])
        (var index 1)
        (while (and (<= index (# occurrences)) (<= index limit))
          (table.insert truncated (. occurrences index))
          (set index (+ index 1)))
        truncated)))

(fn maybe-backfill-unbounded [Temporal recurrence-set-record event options occurrences raw-limit]
  (if (not (and options.limit
                raw-limit
                (has-exclusions? event)
                (has-unbounded-rrule? event)))
      occurrences
      (do
        (var expanded occurrences)
        (var current-limit raw-limit)
        (while (and (< (# expanded) options.limit) (< current-limit max-backfill-raw-limit))
          (set current-limit (math.min max-backfill-raw-limit (* current-limit 2)))
          (set expanded (safe-recurrence-occurrences Temporal recurrence-set-record event options current-limit)))
        (when (< (# expanded) options.limit)
          (error (.. "temporal ICS recurrence expansion exhausted backfill limit "
                     (tostring max-backfill-raw-limit)
                     " before producing requested post-exclusion :limit")))
        expanded)))

(fn zdt->plain [Temporal zdt]
  (Temporal.plain-date-time.from-fields (zdt:fields)))

(fn expand-recurring-event [Temporal event options]
  (local expanded [])
  (local recurrence-set-record (recurrence-set Temporal event))
  (local raw-limit (initial-raw-limit event options))
  (local occurrences
    (truncate-occurrences
      (maybe-backfill-unbounded
        Temporal
        recurrence-set-record
        event
        options
        (safe-recurrence-occurrences Temporal recurrence-set-record event options raw-limit)
        raw-limit)
      options.limit))
  (each [_ zdt (ipairs occurrences)]
    (table.insert expanded (make-occurrence Temporal event (plain->wrapper Temporal event.dtstart (zdt->plain Temporal zdt)) options)))
  expanded)

(fn expand-simple-event [Temporal event options]
  (if (= event.status :cancelled)
      []
      [(make-occurrence Temporal event (copy-wrapper event.dtstart) options)]))

(fn event-groups [calendar]
  (local groups {})
  (each [index event (ipairs calendar.events)]
    (var group (. groups event.uid))
    (when (= group nil)
      (set group {:uid event.uid :master nil :master-source-order 0 :overrides []}))
    (if event.recurrence-id
        (table.insert group.overrides {:event event :source-order index})
        (do
          (when group.master
            (error "duplicate master"))
          (set group.master event)
          (set group.master-source-order index)))
    (set (. groups event.uid) group))
  (each [_ group (pairs groups)]
    (local seen {})
    (each [_ entry (ipairs group.overrides)]
      (local event entry.event)
      (local key (value.normalized-key event.recurrence-id))
      (when (. seen key)
        (error "duplicate override"))
      (set (. seen key) true)))
  groups)

(fn expand-event [Temporal event options]
  (validate-floating-zone event options)
  (if (= event.status :cancelled)
      []
      event.recurrence-id
      []
      (recurring-event? event)
      (expand-recurring-event Temporal event options)
      (expand-simple-event Temporal event options)))

(fn copy-occurrence-with-override [Temporal master override source-order options]
  (local occurrence (make-occurrence Temporal override (copy-wrapper override.dtstart) options))
  (set occurrence.recurrence-id override.recurrence-id)
  (set occurrence.source-order source-order)
  (when (and (= occurrence.summary nil) master.summary)
    (set occurrence.summary master.summary))
  (when (and (= occurrence.description nil) master.description)
    (set occurrence.description master.description))
  occurrence)

(fn validate-override-recurrence-id-mode [master override]
  (when (not (value.same-mode? master.dtstart override.recurrence-id))
    (error "temporal ICS RECURRENCE-ID must match master DTSTART mode")))

(fn validate-group-override-recurrence-id-modes [master overrides]
  (each [_ entry (ipairs overrides)]
    (validate-override-recurrence-id-mode master entry.event)))

(fn apply-group-overrides [Temporal group options]
  (local master group.master)
  (if (= master nil)
      []
      (= master.status :cancelled)
      (do
        (validate-group-override-recurrence-id-modes master group.overrides)
        [])
      (do
        (validate-floating-zone master options)
        (validate-group-override-recurrence-id-modes master group.overrides)
        (local generated (expand-event Temporal master options))
        (local by-key {})
        (local ordered-keys [])
        (each [_ occurrence (ipairs generated)]
          (set occurrence.source-order group.master-source-order)
          (local key (value.normalized-key occurrence.recurrence-id))
          (table.insert ordered-keys key)
          (set (. by-key key) occurrence))
        (local standalone [])
        (each [_ entry (ipairs group.overrides)]
          (local override entry.event)
          (validate-floating-zone override options)
          (local key (value.normalized-key override.recurrence-id))
          (if (= override.status :cancelled)
              (set (. by-key key) nil)
              (. by-key key)
              (set (. by-key key) (copy-occurrence-with-override Temporal master override entry.source-order options))
              (table.insert standalone (copy-occurrence-with-override Temporal master override entry.source-order options))))
        (local result [])
        (each [_ key (ipairs ordered-keys)]
          (local occurrence (. by-key key))
          (when occurrence
            (table.insert result occurrence)))
        (each [_ occurrence (ipairs standalone)]
          (table.insert result occurrence))
        result)))

(fn sort-local-key [wrapper]
  (if (= wrapper.value-type :date)
      (value.date-key wrapper.date)
      (= wrapper.time-mode :utc)
      (wrapper.instant:to-string)
      (= wrapper.time-mode :floating)
      (wrapper.plain:to-string)
      (= wrapper.time-mode :zoned)
      (wrapper.plain:to-string)
      ""))

(fn occurrence-source-order [occurrence]
  (if (= occurrence.source-order nil)
      0
      occurrence.source-order))

(fn occurrence-sort-key [Temporal occurrence options]
  (local instant (wrapper-instant Temporal occurrence.start options))
  {:instant instant
   :local-key (sort-local-key occurrence.start)
   :date-key (if (= occurrence.start.value-type :date) (value.date-key occurrence.start.date) nil)
   :uid occurrence.uid
   :source-order (occurrence-source-order occurrence)})

(fn nullable-string< [left right]
  (if (= left nil)
      (not= right nil)
      (= right nil)
      false
      (< left right)))

(fn occurrence-precedes? [Temporal options left right]
  (local left-key (occurrence-sort-key Temporal left options))
  (local right-key (occurrence-sort-key Temporal right options))
  (if (and left-key.instant right-key.instant)
      (do
        (local comparison (left-key.instant:compare right-key.instant))
        (if (not= comparison 0)
            (< comparison 0)
            (not= left-key.local-key right-key.local-key)
            (< left-key.local-key right-key.local-key)
            (not= left-key.uid right-key.uid)
            (< left-key.uid right-key.uid)
            (< left-key.source-order right-key.source-order)))
      (and left-key.instant (not right-key.instant))
      true
      (and (not left-key.instant) right-key.instant)
      false
      (not= left-key.date-key right-key.date-key)
      (nullable-string< left-key.date-key right-key.date-key)
      (not= left-key.uid right-key.uid)
      (< left-key.uid right-key.uid)
      (< left-key.source-order right-key.source-order)))

(fn expand-calendar [Temporal calendar options]
  (when (not (and (= (type calendar) :table)
                  (= calendar.kind :temporal-ics-calendar)))
    (error "temporal ICS expand requires parsed calendar"))
  (local normalized-options (validate-options options))
  (local groups (event-groups calendar))
  (local expanded [])
  (each [_ group (pairs groups)]
    (each [_ occurrence (ipairs (apply-group-overrides Temporal group normalized-options))]
      (table.insert expanded occurrence)))
  (table.sort expanded #(occurrence-precedes? Temporal normalized-options $1 $2))
  expanded)

{:expand-calendar expand-calendar}
