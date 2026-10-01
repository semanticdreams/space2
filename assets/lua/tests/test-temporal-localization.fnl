(local tests [])

(fn assert-error-contains [f fragment message]
  (local (ok err) (pcall f))
  (assert (not ok) message)
  (assert (err:match fragment) (.. message ": expected error containing " fragment ", got " (tostring err)))
  err)

(fn assert-array= [actual expected message]
  (assert (= (length actual) (length expected)) message)
  (each [index expected-value (ipairs expected)]
    (assert (= (. actual index) expected-value)
            (.. message ": index " (tostring index)
                " expected " (tostring expected-value)
                ", got " (tostring (. actual index))))))

(fn assert-combinations= [actual expected message]
  (assert (= (length actual) (length expected)) message)
  (each [index expected-row (ipairs expected)]
    (local actual-row (. actual index))
    (assert (= actual-row.locale expected-row.locale) (.. message ": locale at " (tostring index)))
    (assert (= actual-row.calendar expected-row.calendar) (.. message ": calendar at " (tostring index)))
    (assert (= actual-row.date-style expected-row.date-style) (.. message ": style at " (tostring index)))))

(fn iso-midnight? [plain iso-date]
  (= (plain:to-string) (.. iso-date "T00:00:00")))

(fn plain [Temporal]
  (Temporal.plain-date-time.parse "2026-10-01T09:30:00"))

(fn pre-1000-from-iso [_plain options]
  {:kind :temporal-calendar-fields
   :calendar options.calendar
   :era "ce"
   :year 1
   :month 1
   :day 1
   :hour 9
   :minute 30
   :second 0
   :nanosecond 0})

(fn pre-1000-to-string [_self]
  "0001-01-01T00:00:00")

(fn pre-1000-to-iso [fields]
  (assert (= fields.calendar "gregory") "parser should preserve calendar")
  (assert (= fields.kind :temporal-calendar-fields) "parser should use calendar field record kind")
  (assert (= fields.era "ce") "parser should preserve era")
  (assert (= fields.year 1) "parser should parse variable-width year")
  (assert (= fields.month 1) "parser should parse month")
  (assert (= fields.day 1) "parser should parse day")
  (assert (= fields.hour 0) "parser should return midnight hour")
  (assert (= fields.minute 0) "parser should return midnight minute")
  (assert (= fields.second 0) "parser should return midnight second")
  (assert (= fields.nanosecond 0) "parser should return midnight nanosecond")
  {:to-string pre-1000-to-string})

(fn pre-1000-calendar []
  {:from-iso pre-1000-from-iso
   :to-iso pre-1000-to-iso})

(fn supported-locales-are-exact []
  (local Temporal (require :temporal))
  (assert Temporal.localization "Temporal.localization should be exported")
  (assert-array= (Temporal.localization.supported-locales)
                 ["en-US" "fr-FR" "ja-JP"]
                 "supported locales should be exact and ordered"))

(fn supported-combinations-are-exact []
  (local Temporal (require :temporal))
  (assert-combinations=
    (Temporal.localization.supported-combinations)
    [{:locale "en-US" :calendar "buddhist" :date-style :short}
     {:locale "en-US" :calendar "buddhist" :date-style :long}
     {:locale "en-US" :calendar "gregory" :date-style :short}
     {:locale "en-US" :calendar "gregory" :date-style :long}
     {:locale "fr-FR" :calendar "gregory" :date-style :short}
     {:locale "fr-FR" :calendar "gregory" :date-style :long}
     {:locale "ja-JP" :calendar "gregory" :date-style :short}
     {:locale "ja-JP" :calendar "gregory" :date-style :long}
     {:locale "ja-JP" :calendar "japanese" :date-style :short}
     {:locale "ja-JP" :calendar "japanese" :date-style :long}]
    "supported combinations should include exactly seed locale/calendar/styles"))

(fn format-examples-match-seed-patterns []
  (local Temporal (require :temporal))
  (local iso (plain Temporal))
  (local examples
    [{:options {:locale "en-US" :calendar "gregory" :date-style :short} :expected "10/01/2026"}
     {:options {:locale "en-US" :calendar "gregory" :date-style :long} :expected "October 1, 2026"}
     {:options {:locale "fr-FR" :calendar "gregory" :date-style :short} :expected "01/10/2026"}
     {:options {:locale "fr-FR" :calendar "gregory" :date-style :long} :expected "1 octobre 2026"}
     {:options {:locale "ja-JP" :calendar "gregory" :date-style :short} :expected "2026/10/01"}
     {:options {:locale "ja-JP" :calendar "gregory" :date-style :long} :expected "2026年10月1日"}
     {:options {:locale "en-US" :calendar "buddhist" :date-style :short} :expected "10/01/2569 BE"}
     {:options {:locale "en-US" :calendar "buddhist" :date-style :long} :expected "October 1, 2569 BE"}
     {:options {:locale "ja-JP" :calendar "japanese" :date-style :short} :expected "R8/10/01"}
     {:options {:locale "ja-JP" :calendar "japanese" :date-style :long} :expected "令和8年10月1日"}])
  (each [_ example (ipairs examples)]
    (local actual (Temporal.localization.format-plain-date-time iso example.options))
    (assert (= actual example.expected)
            (.. "formatted output should match seed pattern: expected " example.expected ", got " actual))))

(fn emitted-strings-parse-to-iso-midnight []
  (local Temporal (require :temporal))
  (local iso (plain Temporal))
  (local combinations (Temporal.localization.supported-combinations))
  (each [_ combination (ipairs combinations)]
    (local options {:locale combination.locale
                    :calendar combination.calendar
                    :date-style combination.date-style})
    (local text (Temporal.localization.format-plain-date-time iso options))
    (local parsed (Temporal.localization.parse-plain-date-time text options))
    (assert (iso-midnight? parsed "2026-10-01")
            (.. "parsed localized text should return ISO midnight for " text))))

(fn pre-1000-emitted-string-parses-to-iso-midnight []
  (local create-localization (require :temporal/localization))
  (local seed (require :temporal/cldr-seed))
  (local localization
    (create-localization
      {:calendar (pre-1000-calendar)
       :seed seed}))
  (local options {:locale "en-US" :calendar "gregory" :date-style :short})
  (local text (localization.format-plain-date-time {} options))
  (assert (= text "01/01/1") "format should only pad width-2 fields")
  (local parsed (localization.parse-plain-date-time text options))
  (assert (iso-midnight? parsed "0001-01-01")
          "parser should accept its emitted pre-1000 Gregorian text"))

(fn validation-errors-are-loud []
  (local Temporal (require :temporal))
  (local iso (plain Temporal))
  (assert-error-contains #(Temporal.localization.format-plain-date-time iso {:calendar "gregory" :date-style :short})
                         "missing temporal localization locale"
                         "locale option should be required")
  (assert-error-contains #(Temporal.localization.format-plain-date-time iso {:locale "en-US" :date-style :short})
                         "missing temporal localization calendar"
                         "calendar option should be required")
  (assert-error-contains #(Temporal.localization.format-plain-date-time iso {:locale "en-US" :calendar "gregory"})
                         "missing temporal localization date%-style"
                         "date-style option should be required")
  (assert-error-contains #(Temporal.localization.format-plain-date-time iso {:locale "en-US" :calendar "gregory" :date-style :short :time-style :short})
                         "unknown temporal localization option"
                         "unknown options should be rejected")
  (assert-error-contains #(Temporal.localization.format-plain-date-time iso {:locale "en-us" :calendar "gregory" :date-style :short})
                         "unsupported temporal locale"
                         "unsupported locale should be rejected")
  (assert-error-contains #(Temporal.localization.format-plain-date-time iso {:locale "en-US" :calendar "islamic" :date-style :short})
                         "unsupported temporal calendar"
                         "unsupported calendar should be rejected")
  (assert-error-contains #(Temporal.localization.format-plain-date-time iso {:locale "fr-FR" :calendar "buddhist" :date-style :short})
                         "unsupported temporal locale/calendar combination"
                         "unsupported locale/calendar combination should be rejected")
  (assert-error-contains #(Temporal.localization.format-plain-date-time iso {:locale "en-US" :calendar "gregory" :date-style :medium})
                         "unsupported temporal date style"
                         "unsupported date style should be rejected"))

(fn parse-errors-are-loud []
  (local Temporal (require :temporal))
  (assert-error-contains #(Temporal.localization.parse-plain-date-time "10/01/2026 trailing" {:locale "en-US" :calendar "gregory" :date-style :short})
                         "malformed localized text"
                         "parser should consume entire text")
  (assert-error-contains #(Temporal.localization.parse-plain-date-time "Foo 1, 2026" {:locale "en-US" :calendar "gregory" :date-style :long})
                         "invalid month name"
                         "invalid month name should be rejected")
  (assert-error-contains #(Temporal.localization.parse-plain-date-time "X8/10/01" {:locale "ja-JP" :calendar "japanese" :date-style :short})
                         "invalid era name"
                         "invalid era code should be rejected")
  (assert-error-contains #(Temporal.localization.parse-plain-date-time "未来8年10月1日" {:locale "ja-JP" :calendar "japanese" :date-style :long})
                         "invalid era name"
                         "invalid era name should be rejected"))

(table.insert tests {:name "supported locales are exact" :fn supported-locales-are-exact})
(table.insert tests {:name "supported combinations are exact" :fn supported-combinations-are-exact})
(table.insert tests {:name "format examples match seed patterns" :fn format-examples-match-seed-patterns})
(table.insert tests {:name "emitted strings parse to ISO midnight" :fn emitted-strings-parse-to-iso-midnight})
(table.insert tests {:name "pre-1000 emitted string parses to ISO midnight" :fn pre-1000-emitted-string-parses-to-iso-midnight})
(table.insert tests {:name "validation errors are loud" :fn validation-errors-are-loud})
(table.insert tests {:name "parse errors are loud" :fn parse-errors-are-loud})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-localization"
                       :tests tests})))

{:name "temporal-localization"
 :tests tests
 :main main}
