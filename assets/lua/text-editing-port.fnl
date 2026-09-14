(local whitespace-codepoints {})
(tset whitespace-codepoints 9 true)
(tset whitespace-codepoints 10 true)
(tset whitespace-codepoints 11 true)
(tset whitespace-codepoints 12 true)
(tset whitespace-codepoints 13 true)
(tset whitespace-codepoints 32 true)

(fn whitespace? [codepoint]
  (and codepoint (. whitespace-codepoints codepoint)))

(fn input-model [input]
  (if (and input input.model)
      input.model
      input))

(fn input-lines [input]
  (local model (input-model input))
  (and model model.lines))

(fn any-logical-navigation? [input]
  (if (not input)
      false
      input.text-line-count
      true
      input.text-line-length
      true
      input.text-line-first-nonblank
      true
      input.text-cursor-line-column
      true
      input.move-caret-to-line-column
      true
      input.move-caret-horizontal-bounded
      true
      input.move-caret-vertical-bounded
      true
      false))

(fn has-logical-navigation? [input]
  (and input input.text-line-count input.text-line-length
       input.text-line-first-nonblank input.text-cursor-line-column
       input.move-caret-to-line-column))

(fn input-kind [input]
  (if (any-logical-navigation? input)
      :virtual-input
      (and input input.model)
      :input
      (and input input.lines)
      :input-model
      (and input input.codepoints)
      :input-model
      :unknown))

(fn missing! [input operation]
  (error (.. "text-editing-port missing " operation " for " (tostring (input-kind input)))))

(fn require-method [input target method-name operation]
  (local method (and target (. target method-name)))
  (if method
      method
      (missing! input operation)))

(fn line-count-for-lines [lines]
  (if lines
      (length lines)
      0))

(fn clamp-line-index [input lines idx]
  (local total (if (has-logical-navigation? input)
                   (input:text-line-count)
                   (line-count-for-lines lines)))
  (local value (if (= idx nil) 0 idx))
  (if (<= total 0)
      0
      (math.max 0 (math.min value (- total 1)))))

(fn line-length-for-lines [lines idx]
  (local line (and lines (. lines (+ idx 1))))
  (if (and line line.codepoints)
      (length line.codepoints)
      0))

(fn last-valid-column [line-size]
  (local size (if (= line-size nil) 0 line-size))
  (if (> size 0)
      (- size 1)
      0))

(fn clamp-column-to-line [line-size column]
  (local limit (last-valid-column line-size))
  (local value (if (= column nil) 0 column))
  (math.max 0 (math.min value limit)))

(fn line-start-index [lines idx]
  (var total 0)
  (var i 0)
  (while (< i idx)
    (local line (and lines (. lines (+ i 1))))
    (when line
      (local cp-count (length (if line.codepoints line.codepoints [])))
      (local newline-length (if (= line.newline-length nil) 0 line.newline-length))
      (set total (+ total cp-count newline-length)))
    (set i (+ i 1)))
  total)

(fn line-first-nonblank-for-line [line]
  (if (not line)
      0
      (do
        (local codepoints (if line.codepoints line.codepoints []))
        (var column 0)
        (var found nil)
        (each [_ codepoint (ipairs codepoints)]
          (when (not found)
            (if (whitespace? codepoint)
                (set column (+ column 1))
                (set found column))))
        (if (= found nil) 0 found))))

(fn current-line-index [input]
  (if (has-logical-navigation? input)
      (do
        (local (line _column) (input:text-cursor-line-column))
        (math.max 0 (if (= line nil) 0 line)))
      (do
        (local model (input-model input))
        (math.max 0 (if (and model model.cursor-line) model.cursor-line 0)))))

(fn current-column [input]
  (if (has-logical-navigation? input)
      (do
        (local (_line column) (input:text-cursor-line-column))
        (math.max 0 (if (= column nil) 0 column)))
      (do
        (local model (input-model input))
        (math.max 0 (if (and model model.cursor-column) model.cursor-column 0)))))

(fn cursor-line-column [input]
  (if (has-logical-navigation? input)
      (values (current-line-index input) (current-column input))
      (input-lines input)
      (values (current-line-index input) (current-column input))
      (missing! input "cursor-line-column")))

(fn line-count [input]
  (local lines (input-lines input))
  (if (has-logical-navigation? input)
      (input:text-line-count)
      lines
      (line-count-for-lines lines)
      (missing! input "line-count")))

(fn line-length [input idx]
  (local lines (input-lines input))
  (if (has-logical-navigation? input)
      (input:text-line-length idx)
      lines
      (line-length-for-lines lines idx)
      (missing! input "line-length")))

(fn line-first-nonblank [input idx]
  (local lines (input-lines input))
  (if (has-logical-navigation? input)
      (input:text-line-first-nonblank idx)
      lines
      (line-first-nonblank-for-line (. lines (+ idx 1)))
      (missing! input "line-first-nonblank")))

(fn remember-column [input column]
  (if column
      (set input.__preferred-column column)
      (set input.__preferred-column (current-column input)))
  input.__preferred-column)

(fn preferred-column [input]
  (if (= input.__preferred-column nil)
      (current-column input)
      input.__preferred-column))

(fn move-to-line-column [input line-index column]
  (local lines (input-lines input))
  (if (has-logical-navigation? input)
      (do
        (local total (input:text-line-count))
        (if (<= total 0)
            (do
              (local moved (input:move-caret-to-line-column 0 0))
              (remember-column input 0)
              moved)
            (do
              (local requested-line (if (= line-index nil) 0 line-index))
              (local clamped-line (math.max 0 (math.min requested-line (- total 1))))
              (local clamped-column (clamp-column-to-line (input:text-line-length clamped-line) column))
              (local moved (input:move-caret-to-line-column clamped-line clamped-column))
              (remember-column input clamped-column)
              moved)))
      lines
      (do
        (local move-to (require-method input input :move-caret-to "move-to-line-column"))
        (local total (line-count-for-lines lines))
        (if (<= total 0)
            (do
              (local moved (move-to input 0))
              (remember-column input 0)
              moved)
            (do
              (local clamped-line (clamp-line-index input lines line-index))
              (local clamped-column (clamp-column-to-line (line-length-for-lines lines clamped-line) column))
              (local target-index (+ (line-start-index lines clamped-line) clamped-column))
              (local moved (move-to input target-index))
              (remember-column input clamped-column)
              moved)))
      (missing! input "move-to-line-column")))

(fn move-to-line-edge [input edge]
  (local current (clamp-line-index input (input-lines input) (current-line-index input)))
  (local size (line-length input current))
  (local column (if (= edge :start) 0 (last-valid-column size)))
  (move-to-line-column input current column))

(fn move-to-first-nonblank [input]
  (local current (clamp-line-index input (input-lines input) (current-line-index input)))
  (move-to-line-column input current (line-first-nonblank input current)))

(fn move-to-first-line [input]
  (remember-column input nil)
  (move-to-line-column input 0 0))

(fn move-to-last-line [input]
  (remember-column input nil)
  (local total (line-count input))
  (if (<= total 0)
      false
      (move-to-line-column input (- total 1) (preferred-column input))))

(fn move-horizontal [input delta]
  (if (any-logical-navigation? input)
      (do
        (local move-bounded (require-method input input :move-caret-horizontal-bounded "move-horizontal"))
        (local moved (move-bounded input delta))
        (when moved
          (remember-column input nil))
        moved)
      (do
        (local move (require-method input input :move-caret "move-horizontal"))
        (local lines (input-lines input))
        (if (not lines)
            (move input delta)
            (do
              (local column (current-column input))
              (local line-index (current-line-index input))
              (local line-size (line-length-for-lines lines line-index))
              (local max-column (last-valid-column line-size))
              (if (< delta 0)
                  (if (> column 0)
                      (do
                        (local moved (move input delta))
                        (when moved
                          (remember-column input nil))
                        moved)
                      false)
                  (if (and (> line-size 0) (< column max-column))
                      (do
                        (local moved (move input delta))
                        (when moved
                          (remember-column input nil))
                        moved)
                      false)))))))

(fn move-vertical [input delta]
  (if (any-logical-navigation? input)
      (do
        (local move-bounded (require-method input input :move-caret-vertical-bounded "move-vertical"))
        (when (= input.__preferred-column nil)
          (remember-column input nil))
        (move-bounded input delta))
      (do
        (when (= input.__preferred-column nil)
          (remember-column input nil))
        (local lines (input-lines input))
        (if (not lines)
            false
            (do
              (local total (line-count-for-lines lines))
              (if (<= total 0)
                  false
                  (do
                    (local current (clamp-line-index input lines (current-line-index input)))
                    (local target (math.max 0 (math.min (+ current delta) (- total 1))))
                    (if (= target current)
                        false
                        (do
                          (local target-column (preferred-column input))
                          (local moved (move-to-line-column input target target-column))
                          (when moved
                            (set input.__preferred-column target-column))
                          moved)))))))))

(fn clamp-caret-to-current-line [input]
  (local current (clamp-line-index input (input-lines input) (current-line-index input)))
  (local column (current-column input))
  (local clamped (clamp-column-to-line (line-length input current) column))
  (if (= column clamped)
      false
      (move-to-line-column input current clamped)))

(fn delegate [input method-name operation ...]
  (local method (require-method input input method-name operation))
  (method input ...))

(fn from-input [input]
  (local port {})
  (set port.line-count
       (fn [_self]
         (line-count input)))
  (set port.line-length
       (fn [_self idx]
         (line-length input idx)))
  (set port.line-first-nonblank
       (fn [_self idx]
         (line-first-nonblank input idx)))
  (set port.cursor-line-column
       (fn [_self]
         (cursor-line-column input)))
  (set port.move-to-line-column
       (fn [_self line column]
         (move-to-line-column input line column)))
  (set port.move-horizontal
       (fn [_self delta]
         (move-horizontal input delta)))
  (set port.move-vertical
       (fn [_self delta]
         (move-vertical input delta)))
  (set port.move-to-line-edge
       (fn [_self edge]
         (move-to-line-edge input edge)))
  (set port.move-to-first-nonblank
       (fn [_self]
         (move-to-first-nonblank input)))
  (set port.move-to-first-line
       (fn [_self]
         (move-to-first-line input)))
  (set port.move-to-last-line
       (fn [_self]
         (move-to-last-line input)))
  (set port.clamp-caret-to-current-line
       (fn [_self]
         (clamp-caret-to-current-line input)))
  (set port.insert-text
       (fn [_self text]
         (delegate input :insert-text "insert-text" text)))
  (set port.delete-at-cursor
       (fn [_self]
         (local removed (delegate input :delete-at-cursor "delete-at-cursor"))
         (when removed
           (clamp-caret-to-current-line input))
         removed))
  (set port.enter-insert-mode
       (fn [_self]
         (delegate input :enter-insert-mode "enter-insert-mode")))
  (set port.enter-normal-mode
       (fn [_self]
         (delegate input :enter-normal-mode "enter-normal-mode")))
  (set port.submit
       (fn [_self payload]
         (delegate input :submit "submit" payload)))
  (set port.move-next-word-start
       (fn [_self]
         (missing! input "move-next-word-start")))
  port)

{:from-input from-input}
