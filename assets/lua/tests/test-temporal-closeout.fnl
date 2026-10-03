(local tests [])
(local Temporal (require :temporal))
(local RuntimeScheduler (require :runtime-scheduler))
(local RuntimeTimers (require :runtime-timers))

(fn assert-error-contains [f needle message]
  (local (ok err) (pcall f))
  (assert (not ok) message)
  (assert (string.find (tostring err) needle 1 true)
          (.. message ": expected " needle ", got " (tostring err))))

(fn assert= [actual expected message]
  (assert (= actual expected)
          (.. message ": expected " (tostring expected) ", got " (tostring actual))))

(fn plain [iso]
  (Temporal.plain-date-time.parse iso))

(fn duration-ms [ms]
  (Temporal.duration.from {:milliseconds ms}))

(fn core-interval-and-recurrence-surfaces-compose []
  (local instant (Temporal.instant.parse "2026-09-25T12:00:00Z"))
  (local shifted (instant:add (Temporal.duration.from {:seconds 90})))
  (assert= (shifted:to-string)
           "2026-09-25T12:01:30Z"
           "duration arithmetic should remain public")
  (local pdt (plain "2026-01-31T10:00:00"))
  (local period (Temporal.period.from {:months 1}))
  (local next-month (Temporal.period.add-to-plain-date-time pdt period))
  (assert= (next-month:to-string)
           "2026-02-28T10:00:00"
           "calendar period should clamp month-end")
  (assert= (Temporal.interval.format
             (Temporal.interval.parse "2026-09-25T12:00:00Z/PT1H" {:type :instant}))
           "2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"
           "instant interval exact duration endpoint should format")
  (local repeating (Temporal.repeating-interval.parse
                     "R2/2026-01-31T10:00:00/P1M"
                     {:type :plain-date-time}))
  (assert= (Temporal.interval.format (. (Temporal.repeating-interval.occurrences repeating {}) 2))
           "2026-02-28T10:00:00/2026-03-28T10:00:00"
           "repeating interval should preserve calendar-period stepping")
  (local recurrence-set
    (Temporal.recurrence-set.from
      {:dtstart (plain "2026-01-01T09:00:00")
       :rrules [(Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;COUNT=2")]
       :rdates [(plain "2026-01-03T09:00:00")]
       :exdates [(plain "2026-01-02T09:00:00")]}))
  (local occurrences (Temporal.recurrence-set.occurrences recurrence-set {:zone-id "America/New_York"}))
  (assert= (# occurrences) 2 "recurrence-set should dedupe/exclude and return two occurrences")
  (local first-occurrence (. occurrences 1))
  (assert= (first-occurrence:to-string)
           "2026-01-01T09:00:00-05:00[America/New_York]"
           "recurrence-set should include dtstart through explicit zone"))

(fn interchange-presentation-and-data-surfaces-compose []
  (local calendar (Temporal.ics.parse "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal Closeout//EN\nBEGIN:VEVENT\nUID:closeout@example.test\nDTSTART:20261001T090000\nDURATION:PT1H\nSUMMARY:Closeout smoke\nEND:VEVENT\nEND:VCALENDAR\n"))
  (local expanded (Temporal.ics.expand calendar {:zone-id "America/New_York"}))
  (assert= (# expanded) 1 "ICS floating event should expand with explicit zone")
  (local iso (plain "2026-10-01T09:30:00"))
  (local japanese (Temporal.calendar.from-iso iso {:calendar "japanese"}))
  (assert= japanese.calendar "japanese" "calendar facade should expose Japanese seed calendar")
  (assert= japanese.era "reiwa" "calendar facade should return finite Japanese era")
  (local localized (Temporal.localization.format-plain-date-time
                     iso
                     {:locale "en-US" :calendar "gregory" :date-style :long}))
  (assert= localized "October 1, 2026" "localization should format selected CLDR seed text")
  (assert (Temporal.business-calendar.is-business-day
            (plain "2026-07-06T09:00:00")
            {:jurisdiction "US-FED"})
          "US-FED business calendar should classify Monday after observed holiday")
  (local natural-candidates (Temporal.natural.candidates "today" {:locale "en-US"}))
  (assert= (. natural-candidates 1 :provider-id)
           "space.temporal.natural-seed"
           "natural candidates should include seed provider id")
  (local provider-candidates (Temporal.providers.parse "today" {:locale "en-US"}))
  (assert= (. provider-candidates 1 :provider-id)
           "space.temporal.natural-seed"
           "provider registry should dispatch natural seed provider")
  (local instant (Temporal.migrations.timestamp->instant
                   0
                   {:schema-id :closeout :field-path "created-at"}))
  (assert= (instant:to-string)
           "1970-01-01T00:00:00Z"
           "migrations should convert legacy integer seconds to instant"))

(fn runtime-scheduling-surfaces-compose []
  (local scheduler
    (RuntimeScheduler.create {:clock (Temporal.clock.fixed (Temporal.instant.parse "2026-01-01T00:00:00Z"))}))
  (local calls [])
  (scheduler:schedule-once {:delay (duration-ms 10)
                            :callback (fn [] (table.insert calls "once"))})
  (scheduler:advance (duration-ms 10))
  (assert= (. calls 1) "once" "RuntimeScheduler one-shot should fire")
  (local recurrence-set
    (Temporal.recurrence-set.from {:dtstart (plain "2026-01-01T00:00:00")
                                   :rdates [(plain "2026-01-01T00:00:01")]}))
  (scheduler:schedule-recurrence {:recurrence-set recurrence-set
                                  :zone-id "UTC"
                                  :limit 1
                                  :callback (fn [payload]
                                              (table.insert calls (payload.scheduled-at:to-string)))})
  (scheduler:advance (duration-ms 990))
  (assert= (. calls 2) "2026-01-01T00:00:01Z" "recurrence scheduler payload should expose scheduled-at")
  (RuntimeTimers.clear))

(fn ecosystem-equivalent-futures-remain-loud []
  (assert-error-contains #(Temporal.localization.format-plain-date-time
                            (plain "2026-10-01T09:30:00")
                            {:locale "es-ES" :calendar "gregory" :date-style :short})
                         "unsupported temporal locale"
                         "unsupported CLDR locale should remain loud")
  (assert-error-contains #(Temporal.calendar.from-iso
                            (plain "2026-10-01T09:30:00")
                            {:calendar "islamic"})
                         "unsupported calendar"
                         "unsupported calendar should remain loud")
  (assert-error-contains #(Temporal.business-calendar.holidays {:jurisdiction "CA-FED" :year 2026})
                         "unsupported temporal holiday jurisdiction"
                         "unsupported holiday jurisdiction should remain loud")
  (assert-error-contains #(Temporal.business-calendar.holidays {:jurisdiction "US-FED" :year 2028})
                         "unsupported temporal holiday year"
                         "unsupported holiday year should remain loud")
  (assert-error-contains #(Temporal.natural.candidates "hoy" {:locale "es-ES"})
                         "unsupported temporal natural locale"
                         "unsupported natural language locale should remain loud")
  (local unsupported-provider-text (Temporal.providers.parse "not a temporal phrase" {:locale "en-US"}))
  (assert= (# unsupported-provider-text) 0 "unsupported natural text should return no provider candidates")
  (assert-error-contains #(Temporal.ics.parse "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Space//Temporal Closeout//EN\nBEGIN:VTODO\nUID:todo@example.test\nEND:VTODO\nEND:VCALENDAR\n")
                         "VTODO"
                         "unsupported iCalendar component should remain loud")
  (assert-error-contains #(Temporal.interval.parse "2026-001T00:00:00Z/PT1H" {:type :instant})
                         "invalid temporal instant"
                         "unsupported ordinal-date interval endpoint should remain loud"))

(table.insert tests {:name "core interval and recurrence surfaces compose"
                     :fn core-interval-and-recurrence-surfaces-compose})
(table.insert tests {:name "interchange presentation and data surfaces compose"
                     :fn interchange-presentation-and-data-surfaces-compose})
(table.insert tests {:name "runtime scheduling surfaces compose"
                     :fn runtime-scheduling-surfaces-compose})
(table.insert tests {:name "ecosystem equivalent futures remain loud"
                     :fn ecosystem-equivalent-futures-remain-loud})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-closeout" :tests tests})))

{:name "temporal-closeout" :tests tests :main main}
