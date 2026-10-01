(local parser (require :temporal/ics/parser))
(local formatter (require :temporal/ics/formatter))
(local expand (require :temporal/ics/expand))

(fn create [Temporal]
  (when (= Temporal nil)
    (error "Temporal.ics requires Temporal facade"))
  (fn parse [text options]
    (parser.parse-calendar Temporal text options))
  (fn format [calendar options]
    (formatter.format-calendar Temporal calendar options))
  (fn expand-calendar [calendar options]
    (expand.expand-calendar Temporal calendar (if (= options nil) {} options)))
  {:parse parse
   :format format
   :expand expand-calendar})

create
