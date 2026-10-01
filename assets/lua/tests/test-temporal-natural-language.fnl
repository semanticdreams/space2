(local Temporal (require :temporal))

(local tests [])

(fn assert-error [f expected]
  (local (ok err) (pcall f))
  (when ok
    (error (.. "expected error containing: " expected)))
  (when (not (string.find (tostring err) expected 1 true))
    (error (.. "expected error containing " expected ", got " (tostring err)))))

(fn assert-relative [expr amount unit]
  (assert (= expr.kind :relative-date))
  (assert (= expr.amount amount))
  (assert (= expr.unit unit)))

(fn parse-preserves-today []
  (assert-relative (Temporal.natural.parse "today") 0 :day))

(fn parse-preserves-relative-count-weeks []
  (assert-relative (Temporal.natural.parse "in 2 weeks") 2 :week))

(fn candidates-include-schema []
  (local candidates (Temporal.natural.candidates "today" {:locale "en-US"}))
  (assert (= (# candidates) 1))
  (local candidate (. candidates 1))
  (assert (= candidate.kind :natural-candidate))
  (assert (= candidate.provider-id "space.temporal.natural-seed"))
  (assert (= candidate.locale "en-US"))
  (assert (= candidate.phrase-id "en-us-today"))
  (assert (= candidate.family :relative-literals))
  (assert (= candidate.matched-text "today"))
  (assert (= candidate.rank 10))
  (assert (= candidate.requires-context true))
  (assert-relative candidate.expression 0 :day))

(fn candidates-handle-packaged-locales []
  (assert-relative (. (Temporal.natural.candidates "demain" {:locale "fr-FR"}) 1 :expression) 1 :day)
  (assert-relative (. (Temporal.natural.candidates "明日" {:locale "ja-JP"}) 1 :expression) 1 :day))

(fn bare-weekday-is-ambiguous []
  (local candidates (Temporal.natural.candidates "Tuesday" {:locale "en-US"}))
  (assert (>= (# candidates) 2))
  (assert-error #(Temporal.natural.parse "Tuesday" {:locale "en-US"})
                "ambiguous temporal natural expression"))

(fn unsupported-locale-throws []
  (assert-error #(Temporal.natural.candidates "today" {:locale "es-ES"})
                "unsupported temporal natural locale"))

(fn unknown-option-key-throws []
  (assert-error #(Temporal.natural.candidates "today" {:calendar "gregory"})
                "unsupported temporal natural option"))

(fn resolve-rejects-missing-context []
  (assert-error #(Temporal.natural.resolve "today")
                "temporal natural resolve context is required"))

(table.insert tests {:name "parse preserves today" :fn parse-preserves-today})
(table.insert tests {:name "parse preserves relative count weeks" :fn parse-preserves-relative-count-weeks})
(table.insert tests {:name "candidates include schema" :fn candidates-include-schema})
(table.insert tests {:name "candidates handle packaged locales" :fn candidates-handle-packaged-locales})
(table.insert tests {:name "bare weekday is ambiguous" :fn bare-weekday-is-ambiguous})
(table.insert tests {:name "unsupported locale throws" :fn unsupported-locale-throws})
(table.insert tests {:name "unknown option key throws" :fn unknown-option-key-throws})
(table.insert tests {:name "resolve rejects missing context" :fn resolve-rejects-missing-context})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-natural-language"
                       :tests tests})))

{:name "temporal-natural-language"
 :tests tests
 :main main}
