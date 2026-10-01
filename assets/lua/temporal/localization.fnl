(local allowed-option-keys {:locale true
                            :calendar true
                            :date-style true})
(local style-order {:short 1
                    :long 2})

(fn reject-unknown-option-keys [options]
  (when (not (= (type options) :table))
    (error "missing temporal localization locale"))
  (each [key _ (pairs options)]
    (when (not (. allowed-option-keys key))
      (error (.. "unknown temporal localization option: " (tostring key))))))

(fn contains-string? [items value]
  (var found? false)
  (each [_ item (ipairs items)]
    (when (= item value)
      (set found? true)))
  found?)

(fn validate-options [seed options]
  (reject-unknown-option-keys options)
  (local locale options.locale)
  (local calendar options.calendar)
  (local date-style options.date-style)
  (when (= locale nil)
    (error "missing temporal localization locale"))
  (when (= calendar nil)
    (error "missing temporal localization calendar"))
  (when (= date-style nil)
    (error "missing temporal localization date-style"))
  (when (not (contains-string? (seed.supported-locales) locale))
    (error (.. "unsupported temporal locale: " (tostring locale))))
  (when (not (contains-string? (seed.supported-calendars) calendar))
    (error (.. "unsupported temporal calendar: " (tostring calendar))))
  (local combination (seed.find-combination locale calendar))
  (when (= combination nil)
    (error (.. "unsupported temporal locale/calendar combination: " locale "/" calendar)))
  (local style (. combination.styles date-style))
  (when (= style nil)
    (error (.. "unsupported temporal date style: " (tostring date-style))))
  {:locale locale
   :calendar calendar
   :date-style date-style
   :combination combination
   :style style})

(fn pad2 [value]
  (if (< value 10)
      (.. "0" (tostring value))
      (tostring value)))

(fn format-number [value width]
  (if (= width 2)
      (pad2 value)
      (tostring value)))

(fn month-name [loaded locale month]
  (local names (. loaded.locales.month_names locale))
  (when (= names nil)
    (error (.. "unsupported temporal locale: " locale)))
  (. names month))

(fn era-by-id [calendar-data id]
  (var found nil)
  (each [_ era (ipairs calendar-data.eras)]
    (when (= era.id id)
      (set found era)))
  found)

(fn era-text [seed calendar era-id field]
  (local calendar-data (seed.calendar-data calendar))
  (local era (and calendar-data (era-by-id calendar-data era-id)))
  (when (= era nil)
    (error "invalid era name"))
  (if (= field "era-code")
      era.code
      (= field "era-name")
      era.name_ja
      era.id))

(fn format-token [seed loaded locale calendar fields token]
  (if (not (= token.literal nil))
      token.literal
      (= token.field "year")
      (format-number fields.year token.width)
      (= token.field "month")
      (format-number fields.month token.width)
      (= token.field "day")
      (format-number fields.day token.width)
      (= token.field "month-name")
      (month-name loaded (or token.locale locale) fields.month)
      (= token.field "era")
      (era-text seed calendar fields.era "era")
      (= token.field "era-code")
      (era-text seed calendar fields.era "era-code")
      (= token.field "era-name")
      (era-text seed calendar fields.era "era-name")
      (error (.. "unsupported temporal localization token: " (tostring token.field)))))

(fn digit? [char]
  (and (not (= char nil))
       (not (= (char:match "%d") nil))))

(fn read-fixed-digits [text pos width]
  (local stop (+ pos width -1))
  (local value (text:sub pos stop))
  (when (not (= (length value) width))
    (error "malformed localized text"))
  (var index 1)
  (while (<= index width)
    (when (not (digit? (value:sub index index)))
      (error "malformed localized text"))
    (set index (+ index 1)))
  (values (tonumber value) (+ stop 1)))

(fn read-variable-digits [text pos]
  (var stop (- pos 1))
  (var cursor pos)
  (while (digit? (text:sub cursor cursor))
    (set stop cursor)
    (set cursor (+ cursor 1)))
  (when (< stop pos)
    (error "malformed localized text"))
  (values (tonumber (text:sub pos stop)) (+ stop 1)))

(fn read-number-token [text pos width]
  (if (= width 2)
      (read-fixed-digits text pos 2)
      (read-variable-digits text pos)))

(fn parse-month-name [loaded locale text pos]
  (local names (. loaded.locales.month_names locale))
  (when (= names nil)
    (error "invalid month name"))
  (var found-month nil)
  (var found-name nil)
  (each [month name (ipairs names)]
    (when (= (text:sub pos (+ pos (length name) -1)) name)
      (set found-month month)
      (set found-name name)))
  (when (= found-month nil)
    (error "invalid month name"))
  (values found-month (+ pos (length found-name))))

(fn parse-era-token [seed calendar field text pos]
  (local calendar-data (seed.calendar-data calendar))
  (var found-era nil)
  (var found-text nil)
  (each [_ era (ipairs calendar-data.eras)]
    (local candidate (if (= field "era-code")
                         era.code
                         (= field "era-name")
                         era.name_ja
                         era.id))
    (when (and candidate (= (text:sub pos (+ pos (length candidate) -1)) candidate))
      (set found-era era)
      (set found-text candidate)))
  (when (= found-era nil)
    (error "invalid era name"))
  (values found-era.id (+ pos (length found-text))))

(fn parse-token [seed loaded locale calendar text pos fields token]
  (if (not (= token.literal nil))
      (do
        (local literal token.literal)
        (when (not (= (text:sub pos (+ pos (length literal) -1)) literal))
          (error "malformed localized text"))
        (+ pos (length literal)))
      (= token.field "year")
      (do
        (local (value next-pos) (read-number-token text pos token.width))
        (set fields.year value)
        next-pos)
      (= token.field "month")
      (do
        (local (value next-pos) (read-number-token text pos token.width))
        (set fields.month value)
        next-pos)
      (= token.field "day")
      (do
        (local (value next-pos) (read-number-token text pos token.width))
        (set fields.day value)
        next-pos)
      (= token.field "month-name")
      (do
        (local (value next-pos) (parse-month-name loaded (or token.locale locale) text pos))
        (set fields.month value)
        next-pos)
      (or (= token.field "era") (= token.field "era-code") (= token.field "era-name"))
      (do
        (local (value next-pos) (parse-era-token seed calendar token.field text pos))
        (set fields.era value)
        next-pos)
      (error (.. "unsupported temporal localization token: " (tostring token.field)))))

(fn compare-combinations [left right]
  (if (not (= left.locale right.locale))
      (< left.locale right.locale)
      (not (= left.calendar right.calendar))
      (< left.calendar right.calendar)
      (< (. style-order left.date-style) (. style-order right.date-style))))

(fn create-localization [deps]
  (when (not (= (type deps) :table))
    (error "Temporal.localization dependencies must be a table"))
  (local calendar deps.calendar)
  (local seed deps.seed)
  (when (not (= (type calendar) :table))
    (error "Temporal.localization requires calendar dependency"))
  (when (not (= (type seed) :table))
    (error "Temporal.localization requires seed dependency"))
  (fn supported-locales []
    (seed.supported-locales))
  (fn supported-combinations []
    (local loaded (seed.load))
    (local out [])
    (each [_ combination (ipairs loaded.locales.combinations)]
      (table.insert out {:locale combination.locale
                         :calendar combination.calendar
                         :date-style :short})
      (table.insert out {:locale combination.locale
                         :calendar combination.calendar
                         :date-style :long}))
    (table.sort out compare-combinations)
    out)
  (fn format-plain-date-time [plain options]
    (local valid (validate-options seed options))
    (local localized (calendar.from-iso plain {:calendar valid.calendar}))
    (local loaded (seed.load))
    (local parts [])
    (each [_ token (ipairs valid.style.tokens)]
      (table.insert parts (format-token seed loaded valid.locale valid.calendar localized token)))
    (table.concat parts ""))
  (fn parse-plain-date-time [text options]
    (when (not (= (type text) :string))
      (error "malformed localized text"))
    (local valid (validate-options seed options))
    (local loaded (seed.load))
    (local fields {:calendar valid.calendar
                   :era (if (= valid.calendar "buddhist") "be" "ce")
                   :hour 0
                   :minute 0
                   :second 0
                   :nanosecond 0})
    (var pos 1)
    (each [_ token (ipairs valid.style.tokens)]
      (set pos (parse-token seed loaded valid.locale valid.calendar text pos fields token)))
    (when (not (= pos (+ (length text) 1)))
      (error "malformed localized text"))
    (calendar.to-iso fields))
  {:supported-locales supported-locales
   :supported-combinations supported-combinations
   :format-plain-date-time format-plain-date-time
   :parse-plain-date-time parse-plain-date-time})

create-localization
