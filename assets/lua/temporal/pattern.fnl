(local supported-tokens
  {:yyyy {:field :year :width 4}
   :MM {:field :month :width 2}
   :dd {:field :day :width 2}
   :HH {:field :hour :width 2}
   :mm {:field :minute :width 2}
   :ss {:field :second :width 2}})

(fn alpha? [ch]
  (not= (ch:match "^%a$") nil))

(fn digit-text? [text]
  (not= (text:match "^%d+$") nil))

(fn token-part [token]
  (local spec (. supported-tokens token))
  (if spec
      {:kind :field :token token :width spec.width :field spec.field}
      (error (.. "unsupported temporal pattern token: " token))))

(fn read-alpha-run [text start]
  (var stop start)
  (while (and (<= stop (length text))
              (alpha? (text:sub stop stop)))
    (set stop (+ stop 1)))
  (values (text:sub start (- stop 1)) stop))

(fn read-quoted-literal [text start]
  (var index (+ start 1))
  (var literal "")
  (var closed false)
  (while (and (not closed) (<= index (length text)))
    (local ch (text:sub index index))
    (if (= ch "'")
        (set closed true)
        (do
          (set literal (.. literal ch))
          (set index (+ index 1)))))
  (when (not closed)
    (error "invalid temporal pattern quote"))
  (values literal (+ index 1)))

(fn compile [pattern-text]
  (assert (= (type pattern-text) :string) "temporal pattern must be a string")
  (local parts [])
  (var index 1)
  (while (<= index (length pattern-text))
    (local ch (pattern-text:sub index index))
    (if (= ch "'")
        (do
          (local (literal next-index) (read-quoted-literal pattern-text index))
          (table.insert parts {:kind :literal :text literal})
          (set index next-index))
        (alpha? ch)
        (do
          (local (token next-index) (read-alpha-run pattern-text index))
          (table.insert parts (token-part token))
          (set index next-index))
        (do
          (table.insert parts {:kind :literal :text ch})
          (set index (+ index 1)))))
  {:pattern pattern-text :parts parts})

(fn read-fixed-digits [text index width token]
  (local field-text (text:sub index (+ index width -1)))
  (when (or (not= (length field-text) width)
            (not (digit-text? field-text)))
    (error (.. "invalid temporal pattern field: " token)))
  (values (tonumber field-text) (+ index width)))

(fn parse [Temporal compiled text opts]
  (assert (= (type text) :string) "temporal pattern text must be a string")
  (when (or (= opts nil) (not= opts.type :plain-date-time))
    (error "unsupported temporal pattern parse type"))
  (local fields {})
  (var index 1)
  (each [_ part (ipairs compiled.parts)]
    (if (= part.kind :literal)
        (do
          (local actual (text:sub index (+ index (length part.text) -1)))
          (when (not= actual part.text)
            (error "temporal pattern literal mismatch"))
          (set index (+ index (length part.text))))
        (= part.kind :field)
        (do
          (local (value next-index) (read-fixed-digits text index part.width part.token))
          (set (. fields part.field) value)
          (set index next-index))
        (error "invalid temporal pattern part")))
  (when (<= index (length text))
    (error "temporal pattern trailing text"))
  (Temporal.plain-date-time.from-fields fields))

(fn zero-pad [value width]
  (string.format (.. "%0" width "d") value))

(fn format [compiled value]
  (local fields (value:fields))
  (var result "")
  (each [_ part (ipairs compiled.parts)]
    (if (= part.kind :literal)
        (set result (.. result part.text))
        (= part.kind :field)
        (set result (.. result (zero-pad (. fields part.field) part.width)))
        (error "invalid temporal pattern part")))
  result)

(fn create [Temporal]
  {:compile compile
   :parse (fn [compiled text opts]
            (parse Temporal compiled text opts))
   :format format})

create
