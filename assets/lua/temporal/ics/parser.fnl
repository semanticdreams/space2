(local grammar (require :temporal/ics/grammar))
(local value (require :temporal/ics/value))

(local valid-options {:unknown-property-policy true})
(local top-level-properties {:VERSION true :PRODID true :CALSCALE true :METHOD true})
(local event-scalar-properties {:UID true :SUMMARY true :DESCRIPTION true :STATUS true :SEQUENCE true
                                :DTSTART true :DTEND true :DURATION true :RECURRENCE-ID true
                                :DTSTAMP true})
(local event-repeat-properties {:RRULE true :RDATE true :EXDATE true :EXRULE true})

(fn assert-string [input label]
  (when (not= (type input) :string)
    (error (.. "temporal ICS " label " must be a string")))
  input)

(fn option-policy [options]
  (local table-options (if (= options nil) {} options))
  (when (not= (type table-options) :table)
    (error "temporal ICS parse options must be a table"))
  (each [key _value (pairs table-options)]
    (when (not (. valid-options key))
      (error (.. "unknown temporal ICS parse option: " (tostring key)))))
  (local policy (or table-options.unknown-property-policy :reject))
  (when (and (not= policy :reject) (not= policy :preserve))
    (error (.. "invalid temporal ICS unknown-property-policy: " (tostring policy))))
  policy)

(fn line-record [line]
  {:name line.name :params line.params :value line.value :source-order line.source-order})

(fn split-comma-values [text]
  (local items [])
  (var start 1)
  (var index (text:find "," start true))
  (while index
    (table.insert items (text:sub start (- index 1)))
    (set start (+ index 1))
    (set index (text:find "," start true)))
  (table.insert items (text:sub start))
  items)

(fn parse-date-list [Temporal line dtstart]
  (local parsed [])
  (each [_ raw (ipairs (split-comma-values line.value))]
    (local wrapper (value.parse-date-time Temporal line.params raw))
    (when (not (value.same-mode? dtstart wrapper))
      (error (.. "temporal ICS " line.name " mode must match DTSTART")))
    (table.insert parsed wrapper))
  parsed)

(fn status-value [raw]
  (if (= raw nil)
      :confirmed
      (= raw "CONFIRMED")
      :confirmed
      (= raw "CANCELLED")
      :cancelled
      (= raw "TENTATIVE")
      :tentative
      (error (.. "unsupported temporal ICS STATUS: " (tostring raw)))))

(fn parse-sequence [raw]
  (if (= raw nil)
      0
      (do
        (local number (tonumber raw))
        (when (or (= number nil) (not= number (math.floor number)))
          (error (.. "invalid temporal ICS SEQUENCE: " (tostring raw))))
        number)))

(fn remember-scalar! [seen line]
  (when (. seen line.name)
    (error (.. "duplicate temporal ICS VEVENT property: " line.name)))
  (tset seen line.name true))

(fn append-x-property! [event line]
  (table.insert event.x-properties (line-record line)))

(fn parse-event [Temporal lines policy]
  (local event {:kind :temporal-ics-event
                :rrules []
                :rdates []
                :exdates []
                :exrules []
                :x-properties []})
  (local seen {})
  (local date-list-lines [])
  (each [_ line (ipairs lines)]
    (if (. event-scalar-properties line.name)
        (do
          (remember-scalar! seen line)
          (if (= line.name "UID")
              (set event.uid line.value)
              (= line.name "SUMMARY")
              (set event.summary line.value)
              (= line.name "DESCRIPTION")
              (set event.description line.value)
              (= line.name "STATUS")
              (set event.status (status-value line.value))
              (= line.name "SEQUENCE")
              (set event.sequence (parse-sequence line.value))
              (= line.name "DTSTART")
              (set event.dtstart (value.parse-date-time Temporal line.params line.value))
              (= line.name "DTEND")
              (set event.dtend (value.parse-date-time Temporal line.params line.value))
              (= line.name "DURATION")
              (set event.duration-line line)
              (= line.name "RECURRENCE-ID")
              (set event.recurrence-id (value.parse-date-time Temporal line.params line.value))
              (= line.name "DTSTAMP")
              (append-x-property! event line)))
        (. event-repeat-properties line.name)
        (if (or (= line.name "RRULE") (= line.name "EXRULE"))
            (do
              (local parsed (Temporal.recurrence.parse-rrule (.. "RRULE:" line.value)))
              (table.insert (if (= line.name "RRULE") event.rrules event.exrules) parsed))
            (table.insert date-list-lines line))
        (line.name:match "^X%-")
        (if (= policy :preserve)
            (append-x-property! event line)
            (error (.. "unsupported temporal ICS VEVENT property: " line.name)))
        (error (.. "unsupported temporal ICS VEVENT property: " line.name))))
  (when (= event.uid nil)
    (error "temporal ICS VEVENT requires UID"))
  (when (= event.dtstart nil)
    (error "temporal ICS VEVENT requires DTSTART"))
  (when (and event.dtend event.duration-line)
    (error "temporal ICS VEVENT DTEND and DURATION are mutually exclusive"))
  (when (= event.status nil)
    (set event.status :confirmed))
  (when (= event.sequence nil)
    (set event.sequence 0))
  (when event.duration-line
    (set event.duration
         (value.parse-duration Temporal event.duration-line.value (= event.dtstart.value-type :date)))
    (set event.duration-line nil))
  (when (and event.dtend (not (value.same-mode? event.dtstart event.dtend)))
    (error "temporal ICS DTEND mode must match DTSTART"))
  (when (and event.recurrence-id (not (value.same-mode? event.dtstart event.recurrence-id)))
    (error "temporal ICS RECURRENCE-ID mode must match DTSTART"))
  (each [_ line (ipairs date-list-lines)]
    (local parsed (parse-date-list Temporal line event.dtstart))
    (each [_ wrapper (ipairs parsed)]
      (table.insert (if (= line.name "RDATE") event.rdates event.exdates) wrapper)))
  event)

(fn parse-timezone [lines raw-lines]
  (local timezone {:kind :temporal-ics-timezone :raw-lines raw-lines})
  (each [_ line (ipairs lines)]
    (when (= line.name "TZID")
      (when timezone.tzid
        (error "duplicate temporal ICS VTIMEZONE TZID"))
      (set timezone.tzid line.value)))
  (when (= timezone.tzid nil)
    (error "temporal ICS VTIMEZONE requires TZID"))
  timezone)

(fn collect-component [parsed raw start-index component-name]
  (local lines [])
  (local raw-lines [])
  (var index (+ start-index 1))
  (var done? false)
  (while (and (<= index (# parsed)) (not done?))
    (local line (. parsed index))
    (if (= line.name "BEGIN")
        (error (.. "unsupported temporal ICS nested component: " line.value))
        (and (= line.name "END") (= line.value component-name))
        (set done? true)
        (= line.name "END")
        (error (.. "unexpected temporal ICS END:" line.value))
        (do
          (table.insert lines line)
          (table.insert raw-lines (. raw index))))
    (set index (+ index 1)))
  (when (not done?)
    (error (.. "temporal ICS component missing END:" component-name)))
  (values lines raw-lines index))

(fn collect-metadata-component [parsed raw start-index component-name]
  (local top-level-lines [])
  (local raw-lines [])
  (var index (+ start-index 1))
  (var depth 0)
  (var done? false)
  (while (and (<= index (# parsed)) (not done?))
    (local line (. parsed index))
    (if (= line.name "BEGIN")
        (do
          (table.insert raw-lines (. raw index))
          (set depth (+ depth 1)))
        (= line.name "END")
        (if (and (= depth 0) (= line.value component-name))
            (set done? true)
            (> depth 0)
            (do
              (table.insert raw-lines (. raw index))
              (set depth (- depth 1)))
            (error (.. "unexpected temporal ICS END:" line.value)))
        (do
          (table.insert raw-lines (. raw index))
          (when (= depth 0)
            (table.insert top-level-lines line))))
    (set index (+ index 1)))
  (when (not done?)
    (error (.. "temporal ICS component missing END:" component-name)))
  (values top-level-lines raw-lines index))

(fn parse-calendar [Temporal text options]
  (when (not (and Temporal Temporal.recurrence Temporal.recurrence.parse-rrule))
    (error "temporal ICS parser requires Temporal facade"))
  (local policy (option-policy options))
  (local raw-lines (grammar.unfold-lines (assert-string text "input")))
  (local parsed [])
  (each [index raw (ipairs raw-lines)]
    (table.insert parsed (grammar.parse-content-line raw index)))
  (when (< (# parsed) 2)
    (error "temporal ICS input must contain VCALENDAR"))
  (local first (. parsed 1))
  (local last (. parsed (# parsed)))
  (when (not (and (= first.name "BEGIN") (= first.value "VCALENDAR")))
    (error "temporal ICS input must begin with VCALENDAR"))
  (when (not (and (= last.name "END") (= last.value "VCALENDAR")))
    (error "temporal ICS input must end with VCALENDAR"))
  (local calendar {:kind :temporal-ics-calendar
                   :calscale "GREGORIAN"
                   :timezones []
                   :events []})
  (local seen {})
  (var index 2)
  (while (< index (# parsed))
    (local line (. parsed index))
    (if (= line.name "BEGIN")
        (if (= line.value "VEVENT")
            (do
              (local (component-lines _raw end-index) (collect-component parsed raw-lines index "VEVENT"))
              (table.insert calendar.events (parse-event Temporal component-lines policy))
              (set index (- end-index 1)))
            (= line.value "VTIMEZONE")
            (do
              (local (component-lines component-raw end-index) (collect-metadata-component parsed raw-lines index "VTIMEZONE"))
              (table.insert calendar.timezones (parse-timezone component-lines component-raw))
              (set index (- end-index 1)))
            (error (.. "unsupported temporal ICS component: " line.value)))
        (= line.name "END")
        (error (.. "unexpected temporal ICS END:" line.value))
        (. top-level-properties line.name)
        (do
          (when (. seen line.name)
            (error (.. "duplicate temporal ICS VCALENDAR property: " line.name)))
          (tset seen line.name true)
          (if (= line.name "VERSION")
              (set calendar.version line.value)
              (= line.name "PRODID")
              (set calendar.prodid line.value)
              (= line.name "CALSCALE")
              (set calendar.calscale line.value)
              (= line.name "METHOD")
              (set calendar.method line.value)))
        (error (.. "unsupported temporal ICS VCALENDAR property: " line.name)))
    (set index (+ index 1)))
  (when (not= calendar.version "2.0")
    (error "temporal ICS VCALENDAR requires VERSION:2.0"))
  (when (not= calendar.calscale "GREGORIAN")
    (error (.. "unsupported temporal ICS CALSCALE: " (tostring calendar.calscale))))
  (when (= (# calendar.events) 0)
    (error "temporal ICS VCALENDAR requires VEVENT"))
  calendar)

{:parse-calendar parse-calendar}
