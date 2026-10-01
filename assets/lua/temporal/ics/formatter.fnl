(local grammar (require :temporal/ics/grammar))
(local value (require :temporal/ics/value))

(local default-prodid "-//Space//Temporal//EN")

(local calendar-keys {:kind true :version true :prod-id true :calscale true :method true
                       :timezones true :events true :x-properties true})
(local event-keys {:kind true :uid true :sequence true :status true :recurrence-id true
                    :dtstart true :dtend true :duration true :rrules true :rdates true
                    :exdates true :exrules true :summary true :description true
                    :source-order true :x-properties true})
(local timezone-keys {:kind true :tzid true :raw-lines true})
(local property-keys {:name true :params true :value true :source-order true})
(local date-keys {:kind true :value-type true :date true})
(local floating-keys {:kind true :value-type true :time-mode true :plain true})
(local utc-keys {:kind true :value-type true :time-mode true :instant true})
(local zoned-keys {:kind true :value-type true :time-mode true :zone-id true :plain true})

(fn assert-table [record label]
  (when (not= (type record) :table)
    (error (.. "temporal ICS " label " must be a table")))
  record)

(fn assert-string [text label]
  (when (not= (type text) :string)
    (error (.. "temporal ICS " label " must be a string")))
  text)

(fn validate-keys [record label allowed]
  (assert-table record label)
  (each [key _value (pairs record)]
    (when (not (. allowed key))
      (error (.. "unknown temporal ICS " label " key: " (tostring key))))))

(fn validate-options [options]
  (local table-options (if (= options nil) {} options))
  (when (not= (type table-options) :table)
    (error "temporal ICS format options must be a table"))
  (each [key _value (pairs table-options)]
    (when (not= key :line-ending)
      (error (.. "unknown temporal ICS format option: " (tostring key)))))
  (if (or (= table-options.line-ending nil) (= table-options.line-ending :crlf))
      "\r\n"
      (= table-options.line-ending :lf)
      "\n"
      (error (.. "invalid temporal ICS line-ending: " (tostring table-options.line-ending)))))

(fn sorted-param-keys [params]
  (local keys [])
  (local param-table (if (= params nil) {} params))
  (each [key _value (pairs param-table)]
    (table.insert keys key))
  (table.sort keys)
  keys)

(fn optional-list [items]
  (if (= items nil)
      []
      items))

(fn optional-number [number fallback]
  (if (= number nil)
      fallback
      number))

(fn fold-for-newline [line newline]
  (local folded (grammar.fold-line line))
  (if (= newline "\r\n")
      folded
      (do
        (local converted (folded:gsub "\r\n" newline))
        converted)))

(fn emit-line [lines name params raw-value newline escape?]
  (assert-string name "property name")
  (assert-string raw-value "property value")
  (local line-parts [(string.upper name)])
  (when (and params (not= (type params) :table))
    (error "temporal ICS parameters must be a table"))
  (each [_ key (ipairs (sorted-param-keys params))]
    (local param-value (. params key))
    (when (not= (type param-value) :string)
      (error (.. "temporal ICS parameter " (tostring key) " must be a string")))
    (table.insert line-parts (.. ";" (string.upper key) "=" param-value)))
  (table.insert line-parts (.. ":" (if escape? (grammar.escape-text raw-value) raw-value)))
  (table.insert lines (fold-for-newline (table.concat line-parts) newline)))

(fn validate-property [property]
  (validate-keys property "property" property-keys))

(fn validate-preserved-property-name [property allow-dtstamp?]
  (validate-property property)
  (local name (assert-string property.name "property name"))
  (when (not (or (name:match "^X%-") (and allow-dtstamp? (= name "DTSTAMP"))))
    (error (.. "unsupported temporal ICS preserved property: " name))))

(fn emit-calendar-property [lines property newline]
  (validate-preserved-property-name property false)
  (emit-line lines property.name property.params property.value newline true))

(fn emit-event-property [lines property newline]
  (validate-preserved-property-name property true)
  (emit-line lines property.name property.params property.value newline true))

(fn validate-date-time [wrapper]
  (validate-keys wrapper "date-time" (if (= wrapper.value-type :date)
                                         date-keys
                                         (= wrapper.time-mode :floating)
                                         floating-keys
                                         (= wrapper.time-mode :utc)
                                         utc-keys
                                         (= wrapper.time-mode :zoned)
                                         zoned-keys
                                         {})))

(fn emit-date-time [lines name wrapper newline]
  (validate-date-time wrapper)
  (local (params text) (value.format-date-time wrapper))
  (emit-line lines name params text newline false))

(fn params-key [params]
  (local parts [])
  (each [_ key (ipairs (sorted-param-keys params))]
    (table.insert parts (.. (string.upper key) "=" (. params key))))
  (table.concat parts ";"))

(fn emit-date-list [lines name wrappers newline]
  (when (> (# wrappers) 0)
    (local texts [])
    (var shared-params nil)
    (var shared-key nil)
    (each [_ wrapper (ipairs wrappers)]
      (validate-date-time wrapper)
      (local (params text) (value.format-date-time wrapper))
      (local key (params-key params))
      (when (and shared-key (not= shared-key key))
        (error (.. "temporal ICS " name " values must share parameters")))
      (set shared-params params)
      (set shared-key key)
      (table.insert texts text))
    (emit-line lines name shared-params (table.concat texts ",") newline false)))

(fn rrule-value [Temporal rule]
  (local text (Temporal.recurrence.to-rrule rule))
  (local prefix "RRULE:")
  (if (= (text:sub 1 (length prefix)) prefix)
      (text:sub (+ (length prefix) 1))
      text))

(fn emit-rule-list [Temporal lines name rules newline]
  (each [_ rule (ipairs rules)]
    (emit-line lines name {} (rrule-value Temporal rule) newline false)))

(fn status-text [status]
  (if (or (= status nil) (= status :confirmed))
      "CONFIRMED"
      (= status :cancelled)
      "CANCELLED"
      (= status :tentative)
      "TENTATIVE"
      (error (.. "unsupported temporal ICS STATUS: " (tostring status)))))

(fn raw-timezone-tzid [timezone]
  (var depth 0)
  (var tzid nil)
  (each [index raw (ipairs timezone.raw-lines)]
    (local line (grammar.parse-content-line raw index))
    (if (= line.name "BEGIN")
        (set depth (+ depth 1))
        (= line.name "END")
        (set depth (- depth 1))
        (and (= depth 0) (= line.name "TZID"))
        (do
          (when tzid
            (error "duplicate temporal ICS VTIMEZONE TZID"))
          (set tzid line.value))))
  tzid)

(fn emit-timezone [lines timezone newline]
  (validate-keys timezone "timezone" timezone-keys)
  (when (or (= timezone.raw-lines nil) (= (# timezone.raw-lines) 0))
    (error "temporal ICS VTIMEZONE requires preserved raw lines"))
  (local raw-tzid (raw-timezone-tzid timezone))
  (when (= raw-tzid nil)
    (error "temporal ICS VTIMEZONE preserved raw lines require TZID"))
  (when (not= timezone.tzid raw-tzid)
    (error (.. "temporal ICS VTIMEZONE TZID mismatch: " (tostring timezone.tzid))))
  (table.insert lines "BEGIN:VTIMEZONE")
  (each [_ raw (ipairs (optional-list timezone.raw-lines))]
    (table.insert lines (fold-for-newline (assert-string raw "timezone raw line") newline)))
  (table.insert lines "END:VTIMEZONE"))

(fn all-day-event? [event]
  (and event.dtstart (= event.dtstart.value-type :date)))

(fn require-same-mode [event property-name wrapper]
  (when (and wrapper (not (value.same-mode? event.dtstart wrapper)))
    (error (.. "temporal ICS " property-name " mode must match DTSTART"))))

(fn validate-date-list-modes [event property-name wrappers]
  (each [_ wrapper (ipairs wrappers)]
    (require-same-mode event property-name wrapper)))

(fn validate-event-date-modes [event]
  (require-same-mode event "DTEND" event.dtend)
  (require-same-mode event "RECURRENCE-ID" event.recurrence-id)
  (validate-date-list-modes event "RDATE" (optional-list event.rdates))
  (validate-date-list-modes event "EXDATE" (optional-list event.exdates)))

(fn emit-event [Temporal lines event newline]
  (validate-keys event "event" event-keys)
  (when (and event.dtend event.duration)
    (error "temporal ICS VEVENT DTEND and DURATION are mutually exclusive"))
  (validate-date-time event.dtstart)
  (validate-event-date-modes event)
  (table.insert lines "BEGIN:VEVENT")
  (emit-line lines "UID" {} (assert-string event.uid "VEVENT UID") newline false)
  (emit-line lines "SEQUENCE" {} (tostring (optional-number event.sequence 0)) newline false)
  (emit-line lines "STATUS" {} (status-text event.status) newline false)
  (when event.recurrence-id
    (emit-date-time lines "RECURRENCE-ID" event.recurrence-id newline))
  (emit-date-time lines "DTSTART" event.dtstart newline)
  (when event.dtend
    (emit-date-time lines "DTEND" event.dtend newline))
  (when event.duration
    (emit-line lines "DURATION" {} (value.format-duration event.duration (all-day-event? event)) newline false))
  (emit-rule-list Temporal lines "RRULE" (optional-list event.rrules) newline)
  (emit-date-list lines "RDATE" (optional-list event.rdates) newline)
  (emit-date-list lines "EXDATE" (optional-list event.exdates) newline)
  (emit-rule-list Temporal lines "EXRULE" (optional-list event.exrules) newline)
  (when event.summary
    (emit-line lines "SUMMARY" {} event.summary newline true))
  (when event.description
    (emit-line lines "DESCRIPTION" {} event.description newline true))
  (each [_ property (ipairs (optional-list event.x-properties))]
    (emit-event-property lines property newline))
  (table.insert lines "END:VEVENT"))

(fn format-calendar [Temporal calendar options]
  (when (not (and Temporal Temporal.recurrence Temporal.recurrence.to-rrule))
    (error "temporal ICS formatter requires Temporal facade"))
  (local newline (validate-options options))
  (validate-keys calendar "calendar" calendar-keys)
  (when (not= calendar.version "2.0")
    (error "temporal ICS VCALENDAR requires VERSION:2.0"))
  (when (not= (if (= calendar.calscale nil) "GREGORIAN" calendar.calscale) "GREGORIAN")
    (error (.. "unsupported temporal ICS CALSCALE: " (tostring calendar.calscale))))
  (when (= (# (optional-list calendar.events)) 0)
    (error "temporal ICS VCALENDAR requires VEVENT"))
  (local lines ["BEGIN:VCALENDAR"])
  (emit-line lines "VERSION" {} calendar.version newline false)
  (emit-line lines "PRODID" {} (if (= calendar.prod-id nil) default-prodid calendar.prod-id) newline false)
  (emit-line lines "CALSCALE" {} (if (= calendar.calscale nil) "GREGORIAN" calendar.calscale) newline false)
  (when calendar.method
    (emit-line lines "METHOD" {} calendar.method newline false))
  (each [_ property (ipairs (optional-list calendar.x-properties))]
    (emit-calendar-property lines property newline))
  (each [_ timezone (ipairs (optional-list calendar.timezones))]
    (emit-timezone lines timezone newline))
  (each [_ event (ipairs (optional-list calendar.events))]
    (emit-event Temporal lines event newline))
  (table.insert lines "END:VCALENDAR")
  (.. (table.concat lines newline) newline))

{:format-calendar format-calendar}
