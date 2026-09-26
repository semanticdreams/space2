(fn valid-fraction? [fraction]
  (and (<= 1 (length fraction))
       (<= (length fraction) 9)))

(fn parse-zoned-parts [text]
  (assert (= (type text) :string) "temporal zoned date time text must be a string")
  (local (fractional-local fraction fractional-offset fractional-zone)
    (text:match "^(%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.(%d+))([+-]%d%d:%d%d)%[([^%]]+)%]$"))
  (if fractional-local
      (if (valid-fraction? fraction)
          (values fractional-local fractional-offset fractional-zone)
          (error "invalid temporal zoned date time"))
      (do
        (local (local-part offset zone-id)
          (text:match "^(%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d)([+-]%d%d:%d%d)%[([^%]]+)%]$"))
        (if (not local-part)
            (error "invalid temporal zoned date time")
            (not offset)
            (error "invalid temporal zoned date time")
            (not zone-id)
            (error "invalid temporal zoned date time")
            (values local-part offset zone-id)))))

(fn expected-zoned-string [Temporal local-part offset zone-id]
  (local plain (Temporal.plain-date-time.parse local-part))
  (.. (plain:to-string) offset "[" zone-id "]"))

(fn create [Temporal]
  (fn parse-instant [text]
    (Temporal.instant.parse text))

  (fn format-instant [instant]
    (instant:to-string))

  (fn parse-plain-date-time [text]
    (Temporal.plain-date-time.parse text))

  (fn format-plain-date-time [plain]
    (plain:to-string))

  (fn parse-zoned-date-time [text]
    (local (local-part offset zone-id) (parse-zoned-parts text))
    (local instant (Temporal.instant.parse (.. local-part offset)))
    (local zdt (Temporal.zoned-date-time.from-instant instant zone-id))
    (when (not (= (zdt:offset-string) offset))
      (error "temporal zoned offset does not match zone"))
    (when (not (= (zdt:to-string) (expected-zoned-string Temporal local-part offset zone-id)))
      (error "temporal zoned offset does not match zone"))
    zdt)

  (fn format-zoned-date-time [zdt]
    (zdt:to-string))

  {:parse-instant parse-instant
   :format-instant format-instant
   :parse-plain-date-time parse-plain-date-time
   :format-plain-date-time format-plain-date-time
   :parse-zoned-date-time parse-zoned-date-time
   :format-zoned-date-time format-zoned-date-time})

create
