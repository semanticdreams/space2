(local core (require :temporal-core))

(local weekday-to-number {:mo 1 :tu 2 :we 3 :th 4 :fr 5 :sa 6 :su 7})

(fn midnight [plain]
  (local plain-text (plain:to-string))
  (core.plain-date-time.parse (.. (plain-text:sub 1 10) "T00:00:00")))

(fn require-context [ctx]
  (when (not= (type ctx) :table)
    (error "temporal expression context is required"))
  ctx)

(fn reference-plain-date-time [ctx]
  (require-context ctx)
  (when (= ctx.reference-plain-date-time nil)
    (if ctx.reference-instant
        (error "reference instant resolution requires projection support")
        (error "temporal expression context requires reference plain date-time")))
  ctx.reference-plain-date-time)

(fn context [options]
  (when (not= (type options) :table)
    (error "temporal expression context options must be a table"))
  (when (not= (type options.zone-id) :string)
    (error "temporal expression context requires zone id"))
  (when (and (= options.reference-plain-date-time nil)
             (= options.reference-instant nil))
    (error "temporal expression context requires reference"))
  {:zone-id options.zone-id
   :reference-plain-date-time options.reference-plain-date-time
   :reference-instant options.reference-instant})

(fn resolve-relative-date [expr ctx]
  (local reference (reference-plain-date-time ctx))
  (local days (if (= expr.unit :day)
                  expr.amount
                  (= expr.unit :week)
                  (* expr.amount 7)
                  (error "unsupported temporal relative date unit")))
  {:kind :plain-date-time
   :value (midnight (reference:add-days days))})

(fn resolve-next-weekday [expr ctx]
  (local reference (reference-plain-date-time ctx))
  (local target (. weekday-to-number expr.weekday))
  (when (= target nil)
    (error "invalid temporal weekday"))
  (local current (reference:iso-weekday))
  (var days (- target current))
  (when (<= days 0)
    (set days (+ days 7)))
  {:kind :plain-date-time
   :value (midnight (reference:add-days days))})

(fn resolve [expr ctx]
  (when (not= (type expr) :table)
    (error "temporal expression is required"))
  (require-context ctx)
  (if (= expr.kind :relative-date)
      (resolve-relative-date expr ctx)
      (= expr.kind :next-weekday)
      (resolve-next-weekday expr ctx)
      (= expr.kind :recurrence)
      {:kind :recurrence :rule expr.rule}
      (error "unsupported temporal expression")))

{:context context
 :resolve resolve}
