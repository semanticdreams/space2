(local max-safe-period-field 9007199254740991)

(fn valid-key? [key]
  (if (= key :years)
      true
      (= key :months)
      true
      (= key :weeks)
      true
      (= key :days)
      true
      false))

(fn finite-integer? [value]
  (and (= (type value) :number)
       (= value value)
       (< value math.huge)
       (> value (- math.huge))
       (<= value max-safe-period-field)
       (>= value (- max-safe-period-field))
       (= value (math.floor value))))

(fn field-or-zero [parts key]
  (local value (. parts key))
  (if (= value nil)
      0
      value))

(fn field-sign [value]
  (if (> value 0)
      1
      (< value 0)
      -1
      0))

(fn assert-consistent-signs [fields]
  (var sign 0)
  (each [_ value (ipairs [fields.years fields.months fields.weeks fields.days])]
    (local value-sign (field-sign value))
    (when (not= value-sign 0)
      (if (= sign 0)
          (set sign value-sign)
          (not= sign value-sign)
          (error "temporal period fields must not mix signs"))))
  fields)

(fn from [parts]
  (when (not (= (type parts) :table))
    (error "temporal period fields must be a table"))
  (each [key _value (pairs parts)]
    (when (and (not (valid-key? key)) (not (= key :kind)))
      (error (.. "invalid temporal period field: " (tostring key)))))
  (when (and (not (= parts.kind nil)) (not (= parts.kind :period)))
    (error "invalid temporal period kind"))
  (local fields
    {:kind :period
     :years (field-or-zero parts :years)
     :months (field-or-zero parts :months)
     :weeks (field-or-zero parts :weeks)
     :days (field-or-zero parts :days)})
  (each [_ key (ipairs [:years :months :weeks :days])]
    (when (not (finite-integer? (. fields key)))
      (error (.. "invalid temporal period field value: " (tostring key)))))
  (assert-consistent-signs fields))

(fn consume-component [text suffix]
  (local (amount remaining) (text:match (.. "^(%d+)" suffix "(.*)$")))
  (if amount
      (values (tonumber amount) remaining true)
      (values 0 text false)))

(fn parse [text]
  (when (not (= (type text) :string))
    (error "temporal period text must be a string"))
  (local (sign unsigned)
    (if (text:match "^%-")
        (values -1 (text:sub 2))
        (values 1 text)))
  (when (or (= unsigned "") (unsigned:match "^%-") (unsigned:match "%+") (unsigned:match "%.") (unsigned:match "T"))
    (error "invalid temporal period text"))
  (when (not (unsigned:match "^P"))
    (error "invalid temporal period text"))
  (var rest (unsigned:sub 2))
  (local (years after-years has-years?) (consume-component rest "Y"))
  (set rest after-years)
  (local (months after-months has-months?) (consume-component rest "M"))
  (set rest after-months)
  (local (weeks after-weeks has-weeks?) (consume-component rest "W"))
  (set rest after-weeks)
  (local (days after-days has-days?) (consume-component rest "D"))
  (set rest after-days)
  (when (or (not= rest "")
            (not (if has-years?
                     true
                     has-months?
                     true
                     has-weeks?
                     true
                     has-days?
                     true
                     false)))
    (error "invalid temporal period text"))
  (from {:years (* sign (tonumber (or years "0")))
         :months (* sign (tonumber (or months "0")))
         :weeks (* sign (tonumber (or weeks "0")))
         :days (* sign (tonumber (or days "0")))}))

(fn negate [period]
  (local p (from period))
  (from {:years (- p.years)
         :months (- p.months)
         :weeks (- p.weeks)
         :days (- p.days)}))

(fn format [period]
  (local p (from period))
  (local negative? (if (< p.years 0)
                       true
                       (< p.months 0)
                       true
                       (< p.weeks 0)
                       true
                       (< p.days 0)
                       true
                       false))
  (local parts [])
  (fn append-field [value suffix]
    (when (not= value 0)
      (table.insert parts (.. (tostring (math.abs value)) suffix))))
  (append-field p.years "Y")
  (append-field p.months "M")
  (append-field p.weeks "W")
  (append-field p.days "D")
  (if (= (length parts) 0)
      "P0D"
      (.. (if negative? "-" "") "P" (table.concat parts ""))))

(fn add-to-plain-date-time [plain period]
  (local p (from period))
  (local add-calendar (. plain :add-calendar))
  (when (not add-calendar)
    (error "temporal period target must be a plain date-time"))
  (add-calendar plain {:years p.years
                       :months p.months
                       :weeks p.weeks
                       :days p.days}))

(fn subtract-from-plain-date-time [plain period]
  (add-to-plain-date-time plain (negate period)))

(fn create-period [_base]
  {:from from
   :parse parse
   :format format
   :negate negate
   :add-to-plain-date-time add-to-plain-date-time
   :subtract-from-plain-date-time subtract-from-plain-date-time})

create-period
