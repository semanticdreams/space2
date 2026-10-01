(fn assert-string [value boundary]
  (when (not= (type value) :string)
    (error (.. "temporal ICS " boundary " must be a string")))
  value)

(fn uppercase [text]
  (string.upper text))

(fn valid-name? [text]
  (not= nil (text:match "^[%a%d%-]+$")))

(fn validate-property-name [name]
  (when (not (valid-name? name))
    (error (.. "invalid temporal ICS property name: " (tostring name))))
  (uppercase name))

(fn validate-parameter-name [name]
  (when (not (valid-name? name))
    (error (.. "invalid temporal ICS parameter name: " (tostring name))))
  (uppercase name))

(fn normalize-line-ending [line-ending]
  (if (or (= line-ending nil) (= line-ending :crlf))
      "\r\n"
      (= line-ending :lf)
      "\n"
      (error (.. "invalid temporal ICS line-ending: " (tostring line-ending)))))

(fn append-line [lines chars]
  (table.insert lines (table.concat chars)))

(fn unfold-lines [text]
  (assert-string text "input")
  (local lines [])
  (var chars [])
  (var index 1)
  (var ended-with-break? false)
  (while (<= index (length text))
    (local char (text:sub index index))
    (if (= char "\r")
        (do
          (when (not= (text:sub (+ index 1) (+ index 1)) "\n")
            (error "invalid temporal ICS line ending"))
          (local following (text:sub (+ index 2) (+ index 2)))
          (if (or (= following " ") (= following "\t"))
              (set index (+ index 3))
              (do
                (append-line lines chars)
                (set chars [])
                (set index (+ index 2))))
          (set ended-with-break? true))
        (= char "\n")
        (do
          (local following (text:sub (+ index 1) (+ index 1)))
          (if (or (= following " ") (= following "\t"))
              (set index (+ index 2))
              (do
                (append-line lines chars)
                (set chars [])
                (set index (+ index 1))))
          (set ended-with-break? true))
        (do
          (table.insert chars char)
          (set index (+ index 1))
          (set ended-with-break? false))))
  (when (or (> (# chars) 0) (not ended-with-break?))
    (when (not (and (= (length text) 0) (= (# chars) 0)))
      (append-line lines chars)))
  lines)

(fn unescape-text [text]
  (assert-string text "escaped text")
  (local chars [])
  (var index 1)
  (while (<= index (length text))
    (local char (text:sub index index))
    (if (= char "\\")
        (do
          (local escaped (text:sub (+ index 1) (+ index 1)))
          (when (= escaped "")
            (error "invalid temporal ICS escape: trailing backslash"))
          (if (or (= escaped "\\") (= escaped ",") (= escaped ";"))
              (table.insert chars escaped)
              (or (= escaped "n") (= escaped "N"))
              (table.insert chars "\n")
              (error (.. "invalid temporal ICS escape: \\" escaped)))
          (set index (+ index 2)))
        (do
          (table.insert chars char)
          (set index (+ index 1)))))
  (table.concat chars))

(fn escape-text [text]
  (assert-string text "text")
  (local chars [])
  (for [index 1 (length text)]
    (local char (text:sub index index))
    (if (= char "\\")
        (table.insert chars "\\\\")
        (= char ",")
        (table.insert chars "\\,")
        (= char ";")
        (table.insert chars "\\;")
        (= char "\r")
        (table.insert chars "\\n")
        (= char "\n")
        (table.insert chars "\\n")
        (table.insert chars char)))
  (table.concat chars))

(fn parse-params [pieces]
  (local params {})
  (for [index 2 (# pieces)]
    (local piece (. pieces index))
    (local equals-index (piece:find "=" 1 true))
    (when (not equals-index)
      (error (.. "invalid temporal ICS parameter on content line: " piece)))
    (local name (validate-parameter-name (piece:sub 1 (- equals-index 1))))
    (local value (piece:sub (+ equals-index 1)))
    (when (not= (. params name) nil)
      (error (.. "duplicate temporal ICS parameter: " name)))
    (tset params name value))
  params)

(fn split-on-semicolon [text]
  (local pieces [])
  (var start 1)
  (var index (text:find ";" start true))
  (while index
    (table.insert pieces (text:sub start (- index 1)))
    (set start (+ index 1))
    (set index (text:find ";" start true)))
  (table.insert pieces (text:sub start))
  pieces)

(fn parse-content-line [line source-order]
  (assert-string line "content line")
  (local colon-index (line:find ":" 1 true))
  (when (not colon-index)
    (error "invalid temporal ICS content line: missing colon"))
  (local prefix (line:sub 1 (- colon-index 1)))
  (local value (line:sub (+ colon-index 1)))
  (local pieces (split-on-semicolon prefix))
  (local name (validate-property-name (. pieces 1)))
  {:kind :temporal-ics-content-line
   :name name
   :params (parse-params pieces)
   :value (unescape-text value)
   :source-order (if (= source-order nil) 1 source-order)})

(fn parse-content-lines [text]
  (local parsed [])
  (local lines (unfold-lines text))
  (each [index line (ipairs lines)]
    (table.insert parsed (parse-content-line line index)))
  parsed)

(fn fold-line [line]
  (assert-string line "fold line")
  (if (<= (length line) 75)
      line
      (do
        (local parts [(line:sub 1 75)])
        (var index 76)
        (while (<= index (length line))
          (table.insert parts (.. "\r\n " (line:sub index (+ index 73))))
          (set index (+ index 74)))
        (table.concat parts))))

(fn sorted-param-keys [params]
  (local keys [])
  (local param-table (if (= params nil) {} params))
  (each [key _ (pairs param-table)]
    (table.insert keys key))
  (table.sort keys)
  keys)

(fn validate-emit-options [options]
  (local option-table (if (= options nil) {} options))
  (each [key _ (pairs option-table)]
    (when (not= key :line-ending)
      (error (.. "unknown temporal ICS emit option: " (tostring key)))))
  (normalize-line-ending (and options options.line-ending)))

(fn emit-content-line [name params value options]
  (local newline (validate-emit-options options))
  (local normalized-name (validate-property-name (assert-string name "property name")))
  (local line-parts [normalized-name])
  (when (and params (not= (type params) :table))
    (error "temporal ICS parameters must be a table"))
  (each [_ key (ipairs (sorted-param-keys params))]
    (local normalized-key (validate-parameter-name (assert-string key "parameter name")))
    (local param-value (. params key))
    (when (not= (type param-value) :string)
      (error (.. "temporal ICS parameter " normalized-key " must be a string")))
    (table.insert line-parts (.. ";" normalized-key "=" param-value)))
  (table.insert line-parts (.. ":" (escape-text value)))
  (local folded (fold-line (table.concat line-parts)))
  (if (= newline "\r\n")
      folded
      (folded:gsub "\r\n" newline)))

{:unfold-lines unfold-lines
 :parse-content-line parse-content-line
 :parse-content-lines parse-content-lines
 :unescape-text unescape-text
 :escape-text escape-text
 :fold-line fold-line
 :emit-content-line emit-content-line}
