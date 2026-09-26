(local recurrence (require :temporal/recurrence))

(local weekday-name-to-symbol
  {:monday :mo
   :tuesday :tu
   :wednesday :we
   :thursday :th
   :friday :fr
   :saturday :sa
   :sunday :su})

(fn trim [text]
  (text:match "^%s*(.-)%s*$"))

(fn unsupported []
  (error "unsupported temporal natural expression"))

(fn parse-count [text]
  (local amount (tonumber text))
  (when (= amount nil)
    (unsupported))
  (when (< amount 0)
    (unsupported))
  (when (not= amount (math.floor amount))
    (unsupported))
  amount)

(fn parse-relative [text]
  (local amount-text (text:match "^in (%d+) days?$"))
  (if amount-text
      {:kind :relative-date :amount (parse-count amount-text) :unit :day}
      (do
        (local week-amount-text (text:match "^in (%d+) weeks?$"))
        (when week-amount-text
          {:kind :relative-date :amount (parse-count week-amount-text) :unit :week}))))

(fn parse-weekday-expression [text prefix]
  (local weekday-name (text:match (.. "^" prefix " (%a+)$")))
  (when weekday-name
    (local weekday (. weekday-name-to-symbol weekday-name))
    (when (not weekday)
      (unsupported))
    weekday))

(fn parse-next-weekday [text]
  (local weekday (parse-weekday-expression text "next"))
  (when weekday
    {:kind :next-weekday :weekday weekday}))

(fn parse-every-weekday [text]
  (local weekday (parse-weekday-expression text "every"))
  (when weekday
    {:kind :recurrence
     :rule (recurrence.from {:freq :weekly :by-day [weekday]})}))

(fn parse [input]
  (when (not= (type input) :string)
    (unsupported))
  (local trimmed (trim input))
  (local text (trimmed:lower))
  (local relative (parse-relative text))
  (local next-weekday (parse-next-weekday text))
  (local every-weekday (parse-every-weekday text))
  (if (= text "today")
      {:kind :relative-date :amount 0 :unit :day}
      (= text "tomorrow")
      {:kind :relative-date :amount 1 :unit :day}
      relative
      relative
      next-weekday
      next-weekday
      every-weekday
      every-weekday
      (unsupported)))

{:parse parse}
