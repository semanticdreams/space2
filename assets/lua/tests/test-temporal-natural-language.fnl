(local Temporal (require :temporal))
(local NaturalCorpus (require :temporal/natural-corpus))

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

(fn assert-supported-locales [locales]
  (assert (= (# locales) 3))
  (assert (= (. locales 1) "en-US"))
  (assert (= (. locales 2) "fr-FR"))
  (assert (= (. locales 3) "ja-JP")))

(fn assert-locale-data-shape [locale data]
  (assert data)
  (assert (> (# data.relative_literals) 0))
  (assert (> (# data.relative_count_offsets) 0))
  (assert (= (# data.next_weekday) 7))
  (assert (= (# data.weekly_weekday_recurrence) 7))
  (assert (= (# data.bare_weekday_ambiguity) 7))
  (assert (= (type (. data.relative_literals 1 :phrase_id)) :string))
  (assert (= (type (. data.relative_literals 1 :text)) :string))
  (assert (= (type (. data.relative_literals 1 :offset_days)) :number))
  (assert (= (type locale) :string)))

(fn corpus-supported-locales-are-exact []
  (assert-supported-locales (NaturalCorpus.supported-locales)))

(fn corpus-load-exposes-packaged-metadata []
  (local corpus (NaturalCorpus.load))
  (assert (= corpus.manifest.id "natural-phrase-seed"))
  (assert (= corpus.manifest.provider_id "space.temporal.natural-seed"))
  (assert (= corpus.manifest.version "natural-phrase-seed-2026-10-track10"))
  (assert (= corpus.manifest.runtime_network_fetch_allowed false))
  (assert-supported-locales corpus.manifest.supported_locales)
  (assert-supported-locales corpus.phrases.locale_order))

(fn corpus-locale-data-loads-supported-locales []
  (each [_ locale (ipairs ["en-US" "fr-FR" "ja-JP"])]
    (assert-locale-data-shape locale (NaturalCorpus.locale-data locale))))

(fn corpus-locale-data-rejects-unsupported-locale []
  (assert-error #(NaturalCorpus.locale-data "es-ES")
                "unsupported temporal natural locale"))

(fn corpus-public-helpers-return-defensive-copies []
  (local first-locales (NaturalCorpus.supported-locales))
  (tset first-locales 1 "mutated")
  (assert-supported-locales (NaturalCorpus.supported-locales))

  (local first-load (NaturalCorpus.load))
  (tset first-load.manifest.supported_locales 1 "mutated")
  (tset (. first-load.phrases.locales "en-US" :relative_literals 1) :text "mutated")
  (local second-load (NaturalCorpus.load))
  (assert-supported-locales second-load.manifest.supported_locales)
  (assert (= (. second-load.phrases.locales "en-US" :relative_literals 1 :text) "today"))

  (local first-data (NaturalCorpus.locale-data "fr-FR"))
  (tset (. first-data.relative_literals 1) :text "mutated")
  (local second-data (NaturalCorpus.locale-data "fr-FR"))
  (assert (= (. second-data.relative_literals 1 :text) "aujourd'hui")))

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
(table.insert tests {:name "corpus supported locales are exact" :fn corpus-supported-locales-are-exact})
(table.insert tests {:name "corpus load exposes packaged metadata" :fn corpus-load-exposes-packaged-metadata})
(table.insert tests {:name "corpus locale data loads supported locales" :fn corpus-locale-data-loads-supported-locales})
(table.insert tests {:name "corpus locale data rejects unsupported locale" :fn corpus-locale-data-rejects-unsupported-locale})
(table.insert tests {:name "corpus public helpers return defensive copies" :fn corpus-public-helpers-return-defensive-copies})
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
