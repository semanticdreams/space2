(local parser (require :temporal/ics/parser))

(fn create [Temporal]
  (fn parse [text options]
    (parser.parse-calendar Temporal text options))
  (fn format [_calendar _options]
    (error "Temporal.ics.format is not implemented"))
  (fn expand [_calendar _options]
    (error "Temporal.ics.expand is not implemented"))
  {:parse parse
   :format format
   :expand expand})

create
