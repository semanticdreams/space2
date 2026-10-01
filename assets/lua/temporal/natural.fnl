(local provider-id "space.temporal.natural-seed")
(local version "natural-phrase-seed-2026-10-track10")
(local allowed-option-keys {:locale true})
(local family-ranks {:relative-literals 10
                     :relative-count-offsets 20
                     :next-weekday 30
                     :weekly-weekday-recurrence 40
                     :bare-weekday-ambiguity 50})
(local weekday-keywords {:mo :mo :tu :tu :we :we :th :th :fr :fr :sa :sa :su :su})

(fn trim [text]
  (text:match "^%s*(.-)%s*$"))

(fn unsupported []
  (error "unsupported temporal natural expression"))

(fn ambiguous []
  (error "ambiguous temporal natural expression"))

(fn parse-count [text]
  (local amount (tonumber text))
  (when (= amount nil)
    (unsupported))
  (when (< amount 0)
    (unsupported))
  (when (not= amount (math.floor amount))
    (unsupported))
  amount)

(fn weekday-keyword [weekday]
  (local keyword (. weekday-keywords weekday))
  (when (= keyword nil)
    (error (.. "unsupported temporal natural weekday: " (tostring weekday))))
  keyword)

(fn relative-expression [amount unit]
  {:kind :relative-date
   :amount amount
   :unit (if (= unit "day") :day :week)})

(fn next-weekday-expression [weekday]
  {:kind :next-weekday
   :weekday (weekday-keyword weekday)})

(fn recurrence-expression [recurrence weekday]
  {:kind :recurrence
   :rule (recurrence.from {:freq :weekly
                           :by-day [(weekday-keyword weekday)]})})

(fn validate-options [options]
  (when (not (= options nil))
    (when (not (= (type options) :table))
      (error "temporal natural options must be a table"))
    (each [key _value (pairs options)]
      (when (not (. allowed-option-keys key))
        (error (.. "unsupported temporal natural option: " (tostring key))))))
  (or options {}))

(fn locale-position [locales locale]
  (var position nil)
  (each [index current (ipairs locales)]
    (when (= current locale)
      (set position index)))
  position)

(fn locales-for-options [corpus options]
  (local locales (corpus.supported-locales))
  (if (not (= options.locale nil))
      (do
        (when (= (locale-position locales options.locale) nil)
          (error (.. "unsupported temporal natural locale: " (tostring options.locale))))
        [options.locale])
      locales))

(fn phrase-text [record]
  (record.text:lower))

(fn new-candidate [locale family phrase-id matched-text rank expression]
  {:kind :natural-candidate
   :provider-id provider-id
   :locale locale
   :phrase-id phrase-id
   :family family
   :matched-text matched-text
   :rank rank
   :expression expression
   :requires-context true})

(fn append-relative-literals [out locale text records]
  (each [_ record (ipairs records)]
    (when (= text (phrase-text record))
      (table.insert out
        (new-candidate locale
                       :relative-literals
                       record.phrase_id
                       text
                       (. family-ranks :relative-literals)
                       (relative-expression record.offset_days "day"))))))

(fn pattern-to-regex [pattern]
  (local escaped (pattern:gsub "([%^%$%(%)%%%.%[%]%*%+%-%?])" "%%%1"))
  (.. "^" (escaped:gsub "{%w+}" "(%%d+)") "$"))

(fn append-relative-count-offsets [out locale text records]
  (each [_ record (ipairs records)]
    (local count-text (text:match (pattern-to-regex (record.pattern:lower))))
    (when count-text
      (local amount (* (parse-count count-text) record.direction))
      (table.insert out
        (new-candidate locale
                       :relative-count-offsets
                       record.phrase_id
                       text
                       (. family-ranks :relative-count-offsets)
                       (relative-expression amount record.unit))))))

(fn append-next-weekday [out locale text records]
  (each [_ record (ipairs records)]
    (when (= text (phrase-text record))
      (table.insert out
        (new-candidate locale
                       :next-weekday
                       record.phrase_id
                       text
                       (. family-ranks :next-weekday)
                       (next-weekday-expression record.weekday))))))

(fn append-weekly-recurrence [out recurrence locale text records]
  (each [_ record (ipairs records)]
    (when (= text (phrase-text record))
      (table.insert out
        (new-candidate locale
                       :weekly-weekday-recurrence
                       record.phrase_id
                       text
                       (. family-ranks :weekly-weekday-recurrence)
                       (recurrence-expression recurrence record.weekday))))))

(fn append-bare-weekday-ambiguity [out recurrence locale text records]
  (each [_ record (ipairs records)]
    (when (= text (phrase-text record))
      (table.insert out
        (new-candidate locale
                       :bare-weekday-ambiguity
                       (.. record.phrase_id "-next")
                       text
                       (. family-ranks :bare-weekday-ambiguity)
                       (next-weekday-expression record.weekday)))
      (table.insert out
        (new-candidate locale
                       :bare-weekday-ambiguity
                       (.. record.phrase_id "-weekly")
                       text
                       (. family-ranks :bare-weekday-ambiguity)
                       (recurrence-expression recurrence record.weekday))))))

(fn sort-candidates! [items locale-order]
  (table.sort items
    (fn [a b]
      (if (not (= a.rank b.rank))
          (< a.rank b.rank)
          (not (= a.locale b.locale))
          (< (locale-position locale-order a.locale) (locale-position locale-order b.locale))
          (< a.phrase-id b.phrase-id)))))

(fn require-resolve-context [context]
  (when (not (= (type context) :table))
    (error "temporal natural resolve context is required"))
  (when (and (= context.reference-plain-date-time nil)
             (or (= context.reference-instant nil)
                 (not (= (type context.zone-id) :string))))
    (error "temporal natural resolve context requires reference plain date-time or reference instant with zone id"))
  context)

(fn create [deps]
  (when (not (and deps deps.recurrence deps.recurrence.from))
    (error "temporal natural parser requires recurrence dependency"))
  (when (not (and deps.expression deps.expression.resolve))
    (error "temporal natural parser requires expression dependency"))
  (when (not (and deps.corpus deps.corpus.supported-locales deps.corpus.locale-data))
    (error "temporal natural parser requires corpus dependency"))
  (local recurrence deps.recurrence)
  (local expression deps.expression)
  (local corpus deps.corpus)

  (fn candidates [input options]
    (when (not= (type input) :string)
      (error "temporal natural text must be a string"))
    (local opts (validate-options options))
    (local trimmed (trim input))
    (local text (trimmed:lower))
    (local locale-order (corpus.supported-locales))
    (local locales (locales-for-options corpus opts))
    (local out [])
    (each [_ locale (ipairs locales)]
      (local data (corpus.locale-data locale))
      (append-relative-literals out locale text data.relative_literals)
      (append-relative-count-offsets out locale text data.relative_count_offsets)
      (append-next-weekday out locale text data.next_weekday)
      (append-weekly-recurrence out recurrence locale text data.weekly_weekday_recurrence)
      (append-bare-weekday-ambiguity out recurrence locale text data.bare_weekday_ambiguity))
    (sort-candidates! out locale-order)
    out)

  (fn parse [input options]
    (local matches (candidates input options))
    (if (= (# matches) 0)
        (unsupported)
        (> (# matches) 1)
        (ambiguous)
        (. matches 1 :expression)))

  (fn resolve [input context]
    (local ctx (require-resolve-context context))
    (expression.resolve (parse input {:locale context.locale}) ctx))

  (fn provider []
    {:id provider-id
     :version version
     :priority 10
     :capabilities [:natural]
     :parse candidates})

  {:candidates candidates
   :parse parse
   :resolve resolve
   :provider provider})

create
