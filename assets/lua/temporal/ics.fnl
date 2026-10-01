(local parser (require :temporal/ics/parser))
(local formatter (require :temporal/ics/formatter))

(fn create [Temporal]
  (when (= Temporal nil)
    (error "Temporal.ics requires Temporal facade"))
  (fn parse [text options]
    (parser.parse-calendar Temporal text options))
  (fn format [calendar options]
    (formatter.format-calendar Temporal calendar options))
  (fn expand [_calendar _options]
    (error "Temporal.ics.expand is not implemented"))
  {:parse parse
   :format format
   :expand expand})

create
