(local _ (require :main))
(local InputModel (require :input-model))
(local TextEditingPort (require :text-editing-port))

(local tests [])

(fn eager-move-caret [self delta]
  (self.model:move-caret delta))

(fn eager-move-caret-to [self position]
  (self.model:move-caret-to position))

(fn eager-insert-text [self value]
  (self.model:insert-text value))

(fn eager-delete-at-cursor [self]
  (self.model:delete-at-cursor))

(fn eager-enter-insert-mode [self]
  (self.model:enter-insert-mode))

(fn eager-enter-normal-mode [self]
  (self.model:enter-normal-mode))

(fn eager-submit [self payload]
  (set self.submitted-payload-value payload))

(fn eager-submitted-payload [self]
  self.submitted-payload-value)

(fn make-input [text]
  (local model (InputModel {:text text}))
  (local input {:model model
                :submitted-payload-value nil
                :submitted-payload eager-submitted-payload})
  (set input.move-caret eager-move-caret)
  (set input.move-caret-to eager-move-caret-to)
  (set input.insert-text eager-insert-text)
  (set input.delete-at-cursor eager-delete-at-cursor)
  (set input.enter-insert-mode eager-enter-insert-mode)
  (set input.enter-normal-mode eager-enter-normal-mode)
  (set input.submit eager-submit)
  input)

(fn assert-cursor [port line column label]
  (local (actual-line actual-column) (port:cursor-line-column))
  (assert (= actual-line line) (.. label " line"))
  (assert (= actual-column column) (.. label " column")))

(fn eager-port-exposes-input-model-navigation []
  (local input (make-input "abc\n  de\nf"))
  (local port (TextEditingPort.from-input input))
  (assert (= (port:line-count) 3) "line count should come from eager lines")
  (assert (= (port:line-length 0) 3) "first line length should match model")
  (assert (= (port:line-length 1) 4) "second line length should match model")
  (assert (= (port:line-first-nonblank 1) 2) "first nonblank should skip ASCII spaces")
  (assert-cursor port 2 1 "initial cursor")

  (assert (port:move-to-line-column 1 3) "move to explicit line/column should move")
  (assert-cursor port 1 3 "explicit line/column")
  (assert (port:move-to-line-edge :start) "line-start should move")
  (assert-cursor port 1 0 "line start")
  (assert (port:move-to-line-edge :end) "line-end should move")
  (assert-cursor port 1 3 "line end")
  (assert (port:move-to-first-nonblank) "first-nonblank should move")
  (assert-cursor port 1 2 "first nonblank")
  (assert (port:move-to-first-line) "first-line should move")
  (assert-cursor port 0 0 "first line")
  (assert (port:move-to-last-line) "last-line should move")
  (assert-cursor port 2 0 "last line clamps to short line"))

(fn eager-port-preserves-preferred-column-and_delete-clamps []
  (local input (make-input "abcd\nx\nabc"))
  (local port (TextEditingPort.from-input input))
  (port:move-to-line-column 0 3)
  (assert (port:move-vertical 1) "vertical should move to shorter line")
  (assert-cursor port 1 0 "vertical down clamps")
  (assert (port:move-vertical 1) "vertical should move to next longer line")
  (assert-cursor port 2 2 "vertical down preserves preferred column")

  (local delete-input (make-input "ab\nc"))
  (local delete-port (TextEditingPort.from-input delete-input))
  (delete-port:move-to-line-column 0 1)
  (assert (delete-port:delete-at-cursor) "delete should remove at cursor")
  (assert (= (delete-input.model:get-text) "a\nc") "delete should mutate model")
  (assert-cursor delete-port 0 0 "delete clamps to current line"))

(fn virtual-line-count [self]
  (table.insert self.calls :text-line-count)
  3)

(fn virtual-line-length [self line]
  (table.insert self.calls [:text-line-length line])
  (. [5 2 4] (+ line 1)))

(fn virtual-first-nonblank [self line]
  (table.insert self.calls [:text-line-first-nonblank line])
  (if (= line 2) 1 0))

(fn virtual-cursor-line-column [self]
  (table.insert self.calls :text-cursor-line-column)
  (values self.line self.column))

(fn virtual-move-to-line-column [self line column]
  (table.insert self.calls [:move-caret-to-line-column line column])
  (set self.line line)
  (set self.column column)
  true)

(fn virtual-move-horizontal [self delta]
  (table.insert self.calls [:move-caret-horizontal-bounded delta])
  (set self.column (+ self.column delta))
  true)

(fn virtual-move-vertical [self delta]
  (table.insert self.calls [:move-caret-vertical-bounded delta])
  (set self.line (+ self.line delta))
  true)

(fn virtual-insert-text [self text]
  (table.insert self.calls [:insert-text text])
  true)

(fn virtual-delete-at-cursor [self]
  (table.insert self.calls :delete-at-cursor)
  true)

(fn virtual-enter-insert-mode [self]
  (table.insert self.calls :enter-insert-mode))

(fn virtual-enter-normal-mode [self]
  (table.insert self.calls :enter-normal-mode))

(fn virtual-submit [self payload]
  (table.insert self.calls [:submit payload]))

(fn virtual-move-next-word-start [self]
  (table.insert self.calls :move-next-word-start)
  (if self.next-word-result
      (do
        (set self.line self.next-word-line)
        (set self.column self.next-word-column)
        true)
      false))

(fn make-virtual-stub []
  (local calls [])
  (local input {:bounded-logical-navigation? true
                :line 1
                :column 2
                :calls calls})
  (set input.text-line-count virtual-line-count)
  (set input.text-line-length virtual-line-length)
  (set input.text-line-first-nonblank virtual-first-nonblank)
  (set input.text-cursor-line-column virtual-cursor-line-column)
  (set input.move-caret-to-line-column virtual-move-to-line-column)
  (set input.move-caret-horizontal-bounded virtual-move-horizontal)
  (set input.move-caret-vertical-bounded virtual-move-vertical)
  (set input.insert-text virtual-insert-text)
  (set input.delete-at-cursor virtual-delete-at-cursor)
  (set input.enter-insert-mode virtual-enter-insert-mode)
  (set input.enter-normal-mode virtual-enter-normal-mode)
  (set input.submit virtual-submit)
  (set input.move-next-word-start virtual-move-next-word-start)
  input)

(fn call-at [calls idx]
  (. calls idx))

(fn call-matches? [call name]
  (if (= call name)
      true
      (and (= (type call) :table)
           (= (. call 1) name))
      true
      false))

(fn contains-call? [calls name]
  (var found false)
  (each [_ call (ipairs calls)]
    (when (call-matches? call name)
      (set found true)))
  found)

(fn call-line-count [port]
  (port:line-count))

(fn call-cursor-line-column [port]
  (port:cursor-line-column))

(fn call-move-horizontal [port]
  (port:move-horizontal 1))

(fn call-insert-text [port]
  (port:insert-text "x"))

(fn call-move-next-word-start [port]
  (port:move-next-word-start))

(fn virtual-port-routes-to-logical-and-bounded-methods []
  (local input (make-virtual-stub))
  (local port (TextEditingPort.from-input input))
  (assert (= (port:line-count) 3) "virtual line-count should call logical method")
  (assert (= (port:line-length 2) 4) "virtual line-length should call logical method")
  (assert (= (port:line-first-nonblank 2) 1) "virtual first-nonblank should call logical method")
  (assert-cursor port 1 2 "virtual cursor")
  (assert (port:move-to-line-column 2 9) "virtual move-to clamps using logical line length")
  (assert-cursor port 2 3 "virtual clamped move-to")
  (assert (port:move-horizontal -1) "virtual horizontal should use bounded movement")
  (assert (port:move-vertical -1) "virtual vertical should use bounded movement")
  (assert (port:insert-text "z") "virtual insert should delegate")
  (assert (port:delete-at-cursor) "virtual delete should delegate")
  (port:enter-insert-mode)
  (port:enter-normal-mode)
  (local payload {:key :value})
  (port:submit payload)
  (assert (= (call-at input.calls 1) :text-line-count) "first call should be logical line-count")
  (assert (contains-call? input.calls :move-caret-horizontal-bounded) "horizontal should use bounded method")
  (assert (contains-call? input.calls :move-caret-vertical-bounded) "vertical should use bounded method"))

(fn assert-missing-error [operation port call label kind]
  (local (ok err) (pcall call port))
  (assert (not ok) (.. label " should fail"))
  (assert (string.find err (.. "text%-editing%-port missing " operation)) (.. label " error should name operation"))
  (assert (string.find err kind) (.. label " error should name kind")))

(fn partial-text-line-count []
  1)

(fn missing-operation-errors-name-operation-and-kind []
  (local unknown-port (TextEditingPort.from-input {}))
  (assert-missing-error "line%-count" unknown-port call-line-count "line-count" "unknown")
  (assert-missing-error "cursor%-line%-column" unknown-port call-cursor-line-column "cursor-line-column" "unknown")

  (local virtual-port (TextEditingPort.from-input {:text-line-count partial-text-line-count}))
  (assert-missing-error "move%-horizontal" virtual-port call-move-horizontal "move" "virtual%-input")

  (local model (InputModel {:text "abc"}))
  (local input-port (TextEditingPort.from-input {:model model
                                                 :move-caret eager-move-caret
                                                 :move-caret-to eager-move-caret-to}))
  (assert-missing-error "insert%-text" input-port call-insert-text "insert" "input"))

(local word-motion-cases
  [{:text "alpha beta" :cursor 0 :expected-line 0 :expected-column 6 :moved? true :label "single space"}
   {:text "alpha  beta" :cursor 5 :expected-line 0 :expected-column 7 :moved? true :label "from whitespace"}
   {:text "foo.bar baz" :cursor 0 :sequence [[0 3] [0 4] [0 8]] :moved? true :label "punctuation boundaries"}
   {:text "alpha\nbeta" :cursor 0 :expected-line 1 :expected-column 0 :moved? true :label "across newline"}
   {:text "alpha" :cursor 0 :expected-line 0 :expected-column 0 :moved? false :label "no next word"}])

(fn port-move-next-word-start-parity []
  (each [_ scenario (ipairs word-motion-cases)]
    (local eager (make-input scenario.text))
    (eager.model:move-caret-to scenario.cursor)
    (local eager-port (TextEditingPort.from-input eager))
    (if scenario.sequence
        (each [idx expected (ipairs scenario.sequence)]
          (assert (eager-port:move-next-word-start) (.. scenario.label " eager w " idx " should move"))
          (assert-cursor eager-port (. expected 1) (. expected 2) (.. scenario.label " eager w " idx)))
        (do
          (assert (= (eager-port:move-next-word-start) scenario.moved?) (.. scenario.label " eager moved"))
          (assert-cursor eager-port scenario.expected-line scenario.expected-column (.. scenario.label " eager"))))

    (local virtual (make-virtual-stub))
    (set virtual.line 0)
    (set virtual.column (or scenario.cursor 0))
    (set virtual.next-word-result scenario.moved?)
    (set virtual.next-word-line scenario.expected-line)
    (set virtual.next-word-column scenario.expected-column)
    (local virtual-port (TextEditingPort.from-input virtual))
    (when (not scenario.sequence)
      (assert (= (virtual-port:move-next-word-start) scenario.moved?) (.. scenario.label " virtual moved"))
      (assert-cursor virtual-port scenario.expected-line scenario.expected-column (.. scenario.label " virtual")))))

(table.insert tests {:name "Text editing port exposes eager InputModel navigation" :fn eager-port-exposes-input-model-navigation})
(table.insert tests {:name "Text editing port preserves preferred column and delete clamp" :fn eager-port-preserves-preferred-column-and_delete-clamps})
(table.insert tests {:name "Text editing port routes virtual inputs through logical methods" :fn virtual-port-routes-to-logical-and-bounded-methods})
(table.insert tests {:name "Text editing port reports explicit missing operations" :fn missing-operation-errors-name-operation-and-kind})
(table.insert tests {:name "Text editing port move next word start parity" :fn port-move-next-word-start-parity})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "text-editing-port"
                       :tests tests})))

{:name "text-editing-port"
 :tests tests
 :main main}
