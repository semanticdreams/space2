(local _ (require :main)) (local glm (require :glm)) (local gl (require :gl))
(local BuildContext (require :build-context)) (local VirtualInput (require :virtual-input)) (local fs (require :fs))
(local LazyTextSource (require :lazy-text-source)) (local LazyTextBuffer (require :lazy-text-buffer))
(local InputState (require :input-state-router)) (local Runtime (require :state-runtime)) (local States (require :states))
(local StateSystemBindings (require :state-system-bindings)) (local TextState (require :text-state)) (local InsertState (require :insert-state))
(local tests [])
(local temp-root "/tmp/space/tests/virtual-input")
(fn codepoints-from-text [text]
  (assert (= (type text) :string) "codepoints-from-text requires text")
  (icollect [_ cp (utf8.codes (or text ""))] cp))
(fn text-from-codepoints [codepoints]
  (assert (= (type codepoints) :table) "text-from-codepoints requires codepoints")
  (table.concat
    (icollect [_ cp (ipairs (or codepoints []))]
              (utf8.char cp))))
(fn row [line text start]
  (assert (= (type line) :number) "row requires line")
  (local start-byte (or start 0))
  (local offsets [0])
  (var last 0)
  (each [byte-index cp (utf8.codes (or text ""))]
    (set last (- (+ byte-index (# (utf8.char cp))) 1))
    (table.insert offsets last))
  {:line line
   :start-byte start-byte
   :end-byte (+ start-byte (# (or text "")))
   :line-end-byte (+ start-byte (# (or text "")))
   :line-end-known? true
   :newline-bytes 1
   :text (or text "")
   :codepoints (codepoints-from-text text)
   :column-byte-offsets offsets})

(fn install-buffer-logical-api [buffer rows]
  (set buffer.get-line-count
       (fn [_self]
         (length rows)))
  (set buffer.get-line-summary
       (fn [_self line]
         (local target-line (if (= line nil) 0 line))
         (local current-row (. rows (+ (math.max 0 target-line) 1)))
         (local codepoints (if (and current-row current-row.codepoints) current-row.codepoints []))
         (var first nil)
         (each [idx cp (ipairs codepoints)]
           (when (and (not first) (not (if (= cp 9) true (if (= cp 10) true (if (= cp 11) true (if (= cp 12) true (if (= cp 13) true (= cp 32))))))))
             (set first (- idx 1))))
         {:codepoint-count (length codepoints)
          :first-nonblank-column (if (= first nil) 0 first)}))
  (set buffer.line-column-for-byte
       (fn [_self byte]
         (local target (math.max 0 (if (= byte nil) 0 byte)))
         (var found-line 0)
         (var found-column 0)
         (var known? false)
         (each [_ current-row (ipairs rows)]
           (when (and (not known?)
                      (>= target (if (= current-row.start-byte nil) 0 current-row.start-byte))
                      (<= target (if (= current-row.line-end-byte nil)
                                      (if (= current-row.end-byte nil) 0 current-row.end-byte)
                                      current-row.line-end-byte)))
             (set found-line current-row.line)
             (var column 0)
             (each [idx offset (ipairs (if current-row.column-byte-offsets current-row.column-byte-offsets []))]
               (when (<= (+ (if (= current-row.start-byte nil) 0 current-row.start-byte) offset) target)
                 (set column (- idx 1))))
             (set found-column column)
             (set known? true)))
         (values found-line found-column known?)))
  (set buffer.byte-for-codepoint-position
       (fn [_self position]
         (local target (math.max 0 (if (= position nil) 0 position)))
         (var remaining target)
         (var fallback 0)
         (each [_ current-row (ipairs rows)]
           (when remaining
             (local codepoint-count (length (if current-row.codepoints current-row.codepoints [])))
             (local newline-length (if (= current-row.newline-bytes nil) 0 current-row.newline-bytes))
             (set fallback (if (= current-row.line-end-byte nil)
                               (if (= current-row.end-byte nil) fallback current-row.end-byte)
                               current-row.line-end-byte))
             (if (<= remaining codepoint-count)
                 (do
                   (local offset (. (if current-row.column-byte-offsets current-row.column-byte-offsets []) (+ remaining 1)))
                   (set fallback (+ (if (= current-row.start-byte nil) 0 current-row.start-byte)
                                    (if (= offset nil) 0 offset)))
                   (set remaining nil))
                 (< remaining (+ codepoint-count newline-length))
                 (do
                   (set fallback (if (= current-row.line-end-byte nil)
                                     (if (= current-row.end-byte nil) fallback current-row.end-byte)
                                     current-row.line-end-byte))
                   (set remaining nil))
                 (set remaining (- remaining (+ codepoint-count newline-length))))))
         fallback)))

(fn make-buffer [opts]
  (assert true "make-buffer uses explicit test defaults")
  (local options (or opts {}))
  (local state {:viewport-calls []
                :inserted []
                :deleted-before 0
                :deleted-at 0
                :moved []
                :scrolled []
                :selections []
                :cleared-selection 0
                :deleted-selection 0
                :saved 0})
  (local rows (or options.rows [(row 0 "alpha" 0) (row 1 "beta" 6) (row 2 "gamma" 11)]))
  (local buffer {:cursor-byte (or options.cursor-byte 0)
                 :scroll-line (or options.scroll-line 0)
                 :selection options.selection
                 :dirty? false
                 :state state})
  (set buffer.get-viewport
       (fn [self view]
         (table.insert state.viewport-calls view)
         (local out [])
         (for [i 1 view.lines]
           (local source-row (. rows (+ view.line i)))
           (table.insert out (or source-row (row (+ view.line i -1) ""))))
         {:start-line view.line
          :start-column view.column
          :requested-lines view.lines
          :requested-columns view.columns
          :rows out}))
  (set buffer.insert-text
       (fn [self text]
         (table.insert state.inserted text)
         (set self.cursor-byte (+ self.cursor-byte (# text)))
         (set self.selection nil)
         (set self.dirty? true)
         true))
  (set buffer.delete-before-cursor
       (fn [self]
         (set state.deleted-before (+ state.deleted-before 1))
         (set self.cursor-byte (math.max 0 (- self.cursor-byte 1)))
         true))
  (set buffer.delete-at-cursor
       (fn [_self]
         (set state.deleted-at (+ state.deleted-at 1))
         true))
  (set buffer.move-caret-to-byte
       (fn [self byte]
         (table.insert state.moved byte)
         (set self.cursor-byte byte)
         true))
  (set buffer.move-caret-to-line-column
       (fn [self line column]
         (table.insert state.moved {:line line :column column})
         (set self.cursor-byte (+ (* line 10) column))
         true))
  (install-buffer-logical-api buffer rows)
  (set buffer.move-caret-horizontal
       (fn [self delta]
         (table.insert state.moved {:horizontal delta})
         (set self.cursor-byte (math.max 0 (+ self.cursor-byte delta)))
         true))
  (set buffer.scroll-lines
       (fn [self delta]
         (table.insert state.scrolled delta)
         (set self.scroll-line (math.max 0 (+ self.scroll-line delta)))
         true))
  (set buffer.set-selection
       (fn [self anchor active]
         (table.insert state.selections {:anchor anchor :active active})
         (set self.selection {:anchor-byte anchor
                              :active-byte active
                              :start-byte (math.min anchor active)
                              :end-byte (math.max anchor active)})
         true))
  (set buffer.clear-selection
       (fn [self]
         (set state.cleared-selection (+ state.cleared-selection 1))
         (set self.selection nil)
         true))
  (set buffer.delete-selection
       (fn [self]
         (set state.deleted-selection (+ state.deleted-selection 1))
         (set self.selection nil)
         true))
  (set buffer.get-selected-text
       (fn [_self]
         (or options.selected-text "selected")))
  (set buffer.save
       (fn [_self]
         (set state.saved (+ state.saved 1))
         (if options.save-error
             (error options.save-error)
             {:saved true})))
  buffer)

(fn make-clickables-stub []
  (local state {:register 0 :unregister 0 :register-right 0 :unregister-right 0 :register-double 0 :unregister-double 0})
  (local stub {:state state})
  (set stub.register (fn [_self _obj] (set state.register (+ state.register 1))))
  (set stub.unregister (fn [_self _obj] (set state.unregister (+ state.unregister 1))))
  (set stub.register-right-click (fn [_self _obj] (set state.register-right (+ state.register-right 1))))
  (set stub.unregister-right-click (fn [_self _obj] (set state.unregister-right (+ state.unregister-right 1))))
  (set stub.register-double-click (fn [_self _obj] (set state.register-double (+ state.register-double 1))))
  (set stub.unregister-double-click (fn [_self _obj] (set state.unregister-double (+ state.unregister-double 1))))
  stub)

(fn make-hoverables-stub []
  (local state {:register 0 :unregister 0})
  (local stub {:state state})
  (set stub.register (fn [_self _obj] (set state.register (+ state.register 1))))
  (set stub.unregister (fn [_self _obj] (set state.unregister (+ state.unregister 1))))
  stub)

(fn make-command-hints-stub []
  {:handle-toggle-key (fn [_self _payload] true)
   :close-on-handled-event (fn [_self _route-key _payload] false)})

(fn command-hints-hud-provider [_self]
  {:command-hints (make-command-hints-stub)})

(fn make-ctx []
  (BuildContext {:clickables (make-clickables-stub)
                 :hoverables (make-hoverables-stub)}))

(fn make-temp-file [name content]
  (local dir (fs.join-path temp-root (.. name "-" (os.time))))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local path (fs.join-path dir "file.txt"))
  (fs.write-file path content)
  path)

(fn lazy-buffer [name content opts]
  (local path (make-temp-file name content))
  (local chunk-bytes (if (and opts opts.chunk-bytes) opts.chunk-bytes 4))
  (LazyTextBuffer {:source (LazyTextSource.file path {:chunk-bytes chunk-bytes})
                   :chunk-bytes chunk-bytes}))

(fn snapshot-text [buffer]
  (. (buffer:get-viewport {:line 0 :column 0 :lines 1 :columns 80}) :rows 1 :text))

(fn key [value] (string.byte value))

(fn fail-arrow-bypass [_self _payload] (error "left/right arrows should route through TextNormalCommands first"))
(fn narrow-layout! [input columns lines]
  (input.layout:measurer)
  (set input.layout.size
       (glm.vec3 (+ (* 2 input.padding.x) (* columns input.column-width))
                 (+ (* 2 input.padding.y) (* lines input.line-height))
                 0))
  (input.layout:layouter)
  input)

(fn assert-caret-visible-inside [input message]
  (input.layout:layouter)
  (assert input.caret.visible? (.. message ": caret should be visible"))
  (local local-x (- input.caret.layout.position.x input.layout.position.x))
  (local local-y (- input.caret.layout.position.y input.layout.position.y))
  (local epsilon 0.00001)
  (assert (>= (+ local-x epsilon) input.padding.x) (.. message ": caret should be inside left edge"))
  (assert (<= local-x (+ (- input.layout.size.x input.padding.x) epsilon))
          (.. message ": caret should be inside right edge"))
  (assert (>= (+ local-y epsilon) input.padding.y) (.. message ": caret should be inside bottom edge"))
  (assert (<= local-y (+ (- input.layout.size.y input.padding.y) epsilon))
          (.. message ": caret should be inside top edge")))

(fn set-test-states []
  (local states (States))
  (states:add-state :normal {})
  (states:add-state :text {})
  (states:set-state :normal)
  (StateSystemBindings.bind-states-host states)
  states)

(fn with-virtual-input-states [body]
  (local original-states app.states)
  (local states (States {:hud_provider command-hints-hud-provider}))
  (local text-state (TextState))
  (local insert-state (InsertState))
  (states:add-state :normal {})
  (states:add-state :text text-state)
  (states:add-state :insert insert-state)
  (states:set-state :normal)
  (StateSystemBindings.bind-states-host states)
  (local (ok result)
    (pcall body {:states states
                 :text-state text-state
                 :insert-state insert-state}))
  (Runtime.reset)
  (StateSystemBindings.bind-states-host original-states)
  (when states.drop
    (states:drop))
  (if ok
      result
      (error result)))

(fn install-clipboard-spy []
  (local original-set gl.clipboard-set)
  (var copied nil)
  (set gl.clipboard-set (fn [value] (set copied value)))
  {:read (fn [] copied)
   :restore (fn [] (set gl.clipboard-set original-set))})

(fn build-input [opts]
  ((VirtualInput opts) (make-ctx)))

(fn record-viewport-calls [buffer]
  (local original-get-viewport buffer.get-viewport)
  (set buffer.state {:viewport-calls []})
  (set buffer.get-viewport
       (fn [self view]
          (table.insert self.state.viewport-calls view)
          (original-get-viewport self view)))
  buffer)

(fn instrument-logical-scans [buffer]
  (assert buffer "instrument-logical-scans requires buffer")
  (when (= buffer.state nil) (set buffer.state {}))
  (local state buffer.state)
  (set state.get-line-summary-calls 0)
  (set state.line-column-for-byte-calls 0)
  (set state.get-line-count-calls 0)
  (set state.get-viewport-calls 0)
  (local original-get-line-summary buffer.get-line-summary)
  (local original-line-column-for-byte buffer.line-column-for-byte)
  (local original-get-line-count buffer.get-line-count)
  (local original-get-viewport buffer.get-viewport)
  (set buffer.get-line-summary
       (fn [self line]
         (set state.get-line-summary-calls (+ state.get-line-summary-calls 1))
         (original-get-line-summary self line)))
  (set buffer.line-column-for-byte
       (fn [self byte]
          (set state.line-column-for-byte-calls (+ state.line-column-for-byte-calls 1))
          (original-line-column-for-byte self byte)))
  (set buffer.get-line-count
       (fn [self]
         (set state.get-line-count-calls (+ state.get-line-count-calls 1))
         (original-get-line-count self)))
  (set buffer.get-viewport
       (fn [self view]
         (set state.get-viewport-calls (+ state.get-viewport-calls 1))
         (original-get-viewport self view)))
  buffer)
(fn reset-logical-scan-counters! [buffer]
  (assert buffer.state "reset-logical-scan-counters! requires instrumented buffer state")
  (set buffer.state.get-line-summary-calls 0)
  (set buffer.state.line-column-for-byte-calls 0)
  (set buffer.state.get-line-count-calls 0)
  (set buffer.state.get-viewport-calls 0))
(fn assert-no-full-logical-scans [buffer message]
  (assert (= buffer.state.get-line-summary-calls 0) (.. message ": get-line-summary should not be called; calls=" buffer.state.get-line-summary-calls))
  (assert (= buffer.state.line-column-for-byte-calls 0) (.. message ": line-column-for-byte should not be called; calls=" buffer.state.line-column-for-byte-calls))
  (assert (= buffer.state.get-line-count-calls 0) (.. message ": get-line-count should not be called; calls=" buffer.state.get-line-count-calls)))
(fn seed-viewport-anchor! [buffer line column columns]
  (assert buffer.build-viewport-row-from-anchor "LazyTextBuffer must expose build-viewport-row-from-anchor to seed viewport anchors")
  (buffer:move-caret-to-line-column line column)
  (local row (buffer:build-viewport-row-from-anchor {:byte buffer.cursor-byte :line line :column column} columns))
  (assert row "seed-viewport-anchor! expected a viewport row from bounded anchor API")
  row)
(fn assert-input-cursor [input buffer line column message]
  (assert (= input.cursor-index buffer.cursor-byte) (.. message ": input cursor byte should match buffer"))
  (assert (= input.cursor-line line) (.. message ": cursor line should match expected"))
  (assert (= input.cursor-column column) (.. message ": cursor column should match expected")))

(fn assert-viewport-calls-bounded [calls max-lines max-columns message]
  (each [i view (ipairs (or calls []))]
    (assert (<= view.lines max-lines)
            (.. message ": viewport call " i " requested " view.lines " lines, expected <= " max-lines))
    (assert (<= view.columns max-columns)
            (.. message ": viewport call " i " requested " view.columns " columns, expected <= " max-columns))))

(fn expect-build-without-context []
  ((VirtualInput {:buffer (make-buffer)}) nil))

(fn exercise-copy [input clipboard]
  (assert (= (input:copy-selection) "copy me"))
  (assert (= (clipboard.read) "copy me"))
  (assert (input:on-key-down {:key (string.byte "c") :mod 64})))

(fn save-conflict [input]
  (input:save))

(fn drop-again [input]
  (input:drop))

(fn record-save [input result]
  (assert input.save-results "record-save requires input.save-results")
  (table.insert input.save-results result))

(fn count-change [input _buffer]
  (set input.change-count (+ input.change-count 1)))

(fn virtual-input-requires-explicit-build-context []
  (local (ok err) (pcall expect-build-without-context))
  (assert (not ok) "VirtualInput should reject missing build context")
  (assert (string.find (tostring err) "VirtualInput requires ctx" 1 true)))

(fn virtual-input-renders-only-visible-viewport-rows []
  (local buffer (make-buffer))
  (local input (build-input {:buffer buffer :line-count 2 :column-count 4}))
  (input:refresh-viewport)
  (assert (= (length input.rows) 2) "should build exactly visible row widgets")
  (assert (= (. buffer.state.viewport-calls 1 :lines) 2))
  (assert (= (. buffer.state.viewport-calls 1 :columns) 4))
  (local first-row (. input.rows 1))
  (local second-row (. input.rows 2))
  (assert (= (text-from-codepoints (first-row:get-codepoints)) "alph"))
  (assert (= (text-from-codepoints (second-row:get-codepoints)) "beta"))
  (input:drop))

(fn virtual-input-caret-navigation-loads-lazy-rows []
  (local buffer (make-buffer))
  (local input (build-input {:buffer buffer :line-count 2 :column-count 6}))
  (input:move-caret :down)
  (input:move-caret :right)
  (input:on-key-down {:key 1073741902})
  (assert (>= (length buffer.state.moved) 2) "caret movement should move through the lazy buffer")
  (assert (= (. buffer.state.scrolled 1) 2) "page down should scroll by visible lines")
  (assert (>= (length buffer.state.viewport-calls) 3) "navigation should refresh visible viewport")
  (local handled (input:on-key-down {:key 999999}))
  (assert (= handled false) "unsupported key payloads return false")
  (input:drop))

(fn virtual-input-page-down-keeps-subsequent-vertical-navigation-valid []
  (local rows [(row 0 "zero" 0) (row 1 "one" 10) (row 2 "two" 20) (row 3 "three" 30)])
  (local buffer (make-buffer {:rows rows :cursor-byte 0}))
  (local input (build-input {:buffer buffer :line-count 2 :column-count 8}))
  (input:refresh-viewport)
  (assert (input:on-key-down {:key 1073741902}) "PageDown should be handled")
  (local (ok err) (pcall (fn [] (input:move-caret :down))))
  (assert ok (.. "Down after PageDown should not use nil caret line/column: " (tostring err)))
  (local last-move (. buffer.state.moved (length buffer.state.moved)))
  (assert (= (. last-move :line) 3) "Down after PageDown should move from visible page to following row")
  (input:drop))

(fn virtual-input-shift-page-down-extends-selection []
  (local rows [(row 0 "zero" 0) (row 1 "one" 10) (row 2 "two" 20) (row 3 "three" 30)])
  (local buffer (make-buffer {:rows rows :cursor-byte 0}))
  (local input (build-input {:buffer buffer :line-count 2 :column-count 8}))
  (input:refresh-viewport)
  (assert (input:on-key-down {:key 1073741902 :mod 1}) "Shift+PageDown should be handled")
  (local selection (. buffer.state.selections (length buffer.state.selections)))
  (assert selection "Shift+PageDown should record an extended selection")
  (assert (= selection.anchor 0) "Shift+PageDown should preserve original anchor")
  (assert (= selection.active 20) "Shift+PageDown should extend to the relocated page caret")
  (input:drop))

(fn virtual-input-shift-page-up-extends-selection []
  (local rows [(row 0 "zero" 0) (row 1 "one" 10) (row 2 "two" 20) (row 3 "three" 30)])
  (local buffer (make-buffer {:rows rows :cursor-byte 20 :scroll-line 2}))
  (local input (build-input {:buffer buffer :line-count 2 :column-count 8}))
  (input:refresh-viewport)
  (assert (input:on-key-down {:key 1073741899 :mod 1}) "Shift+PageUp should be handled")
  (local selection (. buffer.state.selections (length buffer.state.selections)))
  (assert selection "Shift+PageUp should record an extended selection")
  (assert (= selection.anchor 20) "Shift+PageUp should preserve original anchor")
  (assert (= selection.active 0) "Shift+PageUp should extend to the relocated page caret")
  (input:drop))

(fn virtual-input-inserts-and-deletes-through-lazy-buffer []
  (local buffer (make-buffer {:cursor-byte 2 :selection {:anchor-byte 1 :active-byte 3 :start-byte 1 :end-byte 3}}))
  (local input (build-input {:buffer buffer :line-count 1 :column-count 8}))
  (input:enter-insert-mode)
  (input:on-text-input {:text "Z"})
  (input:delete-before-cursor)
  (input:delete-at-cursor)
  (assert (= (. buffer.state.inserted 1) "Z"))
  (assert (= buffer.state.deleted-selection 1) "normal insertion replaces existing selection")
  (assert (= buffer.state.deleted-before 1))
  (assert (= buffer.state.deleted-at 1))
  (input:drop))

(fn virtual-input-copies-selected-text []
  (local clipboard (install-clipboard-spy))
  (local buffer (make-buffer {:selected-text "copy me"
                              :selection {:anchor-byte 0 :active-byte 4 :start-byte 0 :end-byte 4}}))
  (local input (build-input {:buffer buffer :line-count 1 :column-count 8}))
  (local (ok err) (pcall exercise-copy input clipboard))
  (input:drop)
  (clipboard.restore)
  (when (not ok)
    (error err)))

(fn virtual-input-save-reports-success-and-conflict []
  (local successes [])
  (local buffer (make-buffer))
  (local input (build-input {:buffer buffer
                             :line-count 1
                             :column-count 8
                             :on-save record-save}))
  (set input.save-results successes)
  (local ok-result (input:save))
  (assert ok-result.saved)
  (assert (= (length successes) 1))
  (local conflict (build-input {:buffer (make-buffer {:save-error "file changed since token"})
                                :line-count 1
                                :column-count 8}))
  (local (ok err) (pcall save-conflict conflict))
  (assert (not ok) "save conflicts should fail loudly")
  (assert (string.find (tostring err) "file changed since token" 1 true))
  (input:drop)
  (conflict:drop))

(fn virtual-input-drop-tears-down-owned-children []
  (local ctx (make-ctx))
  (local input ((VirtualInput {:buffer (make-buffer) :line-count 3 :column-count 8}) ctx))
  (input:drop)
  (assert (= ctx.clickables.state.unregister 1) "drop should unregister direct pointer child")
  (local (ok err) (pcall drop-again input))
  (assert (not ok) "double drop should error")
  (assert (string.find (tostring err) "VirtualInput dropped twice" 1 true)))

(fn virtual-input-click-focus-routes-input-state-events []
  (local states (set-test-states))
  (local buffer (make-buffer))
  (local input (build-input {:buffer buffer :line-count 1 :column-count 8}))
  (input:on-click {:row-index 1 :column 0})
  (assert (= (InputState.active-input) input) "click should make VirtualInput active input")
  (assert (= (states:active-name) :text) "click should enter text input state")
  (assert (= input.mode :normal) "click should leave VirtualInput in normal mode")
  (assert (not (InputState.dispatch-input :on-text-input {:text "R"}))
          "routed text input should not be handled while VirtualInput is normal")
  (assert (= (# buffer.state.inserted) 0)
          "text input routed in text state should not mutate the buffer")
  (input:drop)
  (assert (not (InputState.active-input)) "drop should release active VirtualInput"))

(fn virtual-input-text-state-i-enters-insert-mode []
  (with-virtual-input-states
    (fn [env]
      (local states (. env :states))
      (local text-state (. env :text-state))
      (local buffer (lazy-buffer "text-state-insert" "abc\ndef"))
      (local input (build-input {:buffer buffer :line-count 2 :column-count 8}))
      (input:on-click {:row-index 1 :column 0})
      (assert (= (states:active-name) :text) "click should enter text state")
      (assert (text-state:on-key-down {:key (string.byte "i")})
              "TextState i should be handled for VirtualInput")
      (assert (= input.mode :insert) "VirtualInput should enter insert mode")
      (assert (= (states:active-name) :insert) "states host should enter insert")
      (assert (Runtime.dispatch-text-input {:text "i"})
              "one-shot text input for insert key should be consumed")
      (assert (= (snapshot-text buffer) "abc")
              "one-shot text input for insert key should not mutate buffer")
      (assert (Runtime.dispatch-text-input {:text "Z"})
              "subsequent printable text input should be routed in insert mode")
      (assert (= (snapshot-text buffer) "Zabc")
              "subsequent printable text input should insert exactly once")
      (input:drop))))

(fn virtual-input-state-helper-clears-ignored-text-input []
  (with-virtual-input-states
    (fn [env]
      (local text-state (. env :text-state))
      (local buffer (lazy-buffer "ignored-text-source" "abc"))
      (local input (build-input {:buffer buffer :line-count 1 :column-count 8}))
      (input:on-click {:row-index 1 :column 0})
      (assert (text-state:on-key-down {:key (string.byte "i")})
              "TextState i should arm one ignored text-input event")
      (input:drop)))
  (local buffer (make-buffer))
  (set-test-states)
  (local input (build-input {:buffer buffer :line-count 1 :column-count 8}))
  (input:on-click {:row-index 1 :column 0})
  (input:enter-insert-mode)
  (assert (Runtime.dispatch-text-input {:text "Z"})
          "fresh active input should receive routed text input")
  (assert (= (. buffer.state.inserted 1) "Z")
          "with-virtual-input-states cleanup should not leak ignored text-input events")
  (input:drop))

(fn virtual-input-text-state-h-l-move-without-numeric-delta-error []
  (with-virtual-input-states
    (fn [env]
      (local text-state (. env :text-state)) (local buffer (lazy-buffer "text-state-horizontal" "abcd"))
      (local input (build-input {:buffer buffer :line-count 1 :column-count 8})) (input:on-click {:row-index 1 :column 1})
      (assert (text-state:on-key-down {:key (string.byte "l")}) "TextState l should move right")
      (assert (= buffer.cursor-byte 2) "l should move one UTF-8 codepoint right")
      (assert (text-state:on-key-down {:key (string.byte "h")}) "TextState h should move left")
      (assert (= buffer.cursor-byte 1) "h should move one UTF-8 codepoint left")
      (set input.on-key-down fail-arrow-bypass) (assert (text-state:on-key-down {:key 1073741903}) "TextState right arrow should be handled")
      (assert (= buffer.cursor-byte 2) "right arrow should move one codepoint through shared port")
      (assert (text-state:on-key-down {:key 1073741904}) "TextState left arrow should be handled")
      (assert (= buffer.cursor-byte 1) "left arrow should move one codepoint through shared port")
      (input:drop))))

(fn virtual-input-text-state-j-k-move-using-lazy-rows []
  (with-virtual-input-states
    (fn [env]
      (local text-state (. env :text-state))
      (local buffer (lazy-buffer "text-state-vertical" "aa\nbb\ncc"))
      (local input (build-input {:buffer buffer :line-count 3 :column-count 8}))
      (input:on-click {:row-index 1 :column 1})
      (assert (text-state:on-key-down {:key (string.byte "j")})
              "TextState j should move down")
      (assert (= input.cursor-line 1) "j should move to second lazy row")
      (assert (= input.cursor-column 1) "j should preserve preferred column")
      (assert (text-state:on-key-down {:key (string.byte "k")})
              "TextState k should move up")
      (assert (= input.cursor-line 0) "k should move back to first lazy row")
      (input:drop))))

(fn virtual-input-text-state-x-deletes-and-clamps []
  (with-virtual-input-states
    (fn [env]
      (local text-state (. env :text-state))
      (local buffer (lazy-buffer "text-state-delete" "abc"))
      (local input (build-input {:buffer buffer :line-count 1 :column-count 8}))
      (input:on-click {:row-index 1 :column 2})
      (assert (text-state:on-key-down {:key (string.byte "x")})
              "TextState x should delete at cursor")
      (assert (= (snapshot-text buffer) "ab") "x should delete the current character")
      (assert (<= input.cursor-column 1) "caret should clamp inside remaining line")
      (input:drop))))

(fn virtual-input-insert-state-escape-returns-to-text-mode []
  (with-virtual-input-states
    (fn [env]
      (local states (. env :states))
      (local text-state (. env :text-state))
      (local insert-state (. env :insert-state))
      (local buffer (lazy-buffer "insert-state-escape" "abcd"))
      (local input (build-input {:buffer buffer :line-count 1 :column-count 8}))
      (input:on-click {:row-index 1 :column 2})
      (assert (text-state:on-key-down {:key (string.byte "i")})
              "TextState i should enter insert before Escape")
      (assert (= input.mode :insert) "precondition: VirtualInput should be in insert mode")
      (assert (= (states:active-name) :insert) "precondition: states host should be insert")
      (assert (Runtime.dispatch-text-input {:text "i"})
              "one-shot text input for insert key should be consumed before Escape")
      (assert (= (snapshot-text buffer) "abcd")
              "one-shot text input for insert key should not mutate buffer before Escape")
      (assert (insert-state:on-key-down {:key 27})
              "InsertState Escape should be handled for VirtualInput")
      (assert (= input.mode :normal) "Escape should return VirtualInput to normal mode")
      (assert (= (states:active-name) :text) "Escape should return states host to text")
      (assert (= buffer.cursor-byte 1) "Escape should move caret left once when possible")
      (assert (not (Runtime.dispatch-text-input {:text "Q"}))
              "printable text input after Escape should not be handled in text state")
      (assert (= (snapshot-text buffer) "abcd")
              "printable text input after Escape should not mutate buffer")
      (input:drop))))

(fn virtual-input-insert-state-return-inserts-newline []
  (with-virtual-input-states
    (fn [env]
      (local states (. env :states))
      (local text-state (. env :text-state))
      (local insert-state (. env :insert-state))
      (local buffer (lazy-buffer "insert-state-return" "abc"))
      (local input (build-input {:buffer buffer :line-count 2 :column-count 8}))
      (input:on-click {:row-index 1 :column 1})
      (assert (text-state:on-key-down {:key (string.byte "i")})
              "TextState i should enter insert before Return")
      (assert (insert-state:on-key-down {:key 13})
              "InsertState Return should be handled for multiline VirtualInput")
      (local rows (. (buffer:get-viewport {:line 0 :column 0 :lines 2 :columns 80}) :rows))
      (assert (= (. rows 1 :text) "a") "Return should split text at the caret")
      (assert (= (. rows 2 :text) "bc") "Return should keep text after inserted newline")
      (assert (= input.mode :insert) "Return should keep multiline VirtualInput in insert mode")
      (assert (= (states:active-name) :insert) "Return should keep states host in insert")
      (input:drop))))

(fn virtual-input-insertion-replaces-real-buffer-selection []
  (local buffer (lazy-buffer "selection-replace" "abcde"))
  (buffer:move-caret-to-byte 1)
  (buffer:set-selection 1 3)
  (local input (build-input {:buffer buffer :line-count 1 :column-count 10}))
  (input:insert-text "Z")
  (assert (= (snapshot-text buffer) "aZde") "selection bytes should be replaced by inserted text")
  (input:drop))

(fn virtual-input-backspace-deletes-active-selection []
  (local buffer (lazy-buffer "backspace-selection" "abcdef"))
  (buffer:move-caret-to-byte 4)
  (buffer:set-selection 1 4)
  (local input (build-input {:buffer buffer
                             :line-count 1
                             :column-count 10
                             :on-change count-change}))
  (set input.change-count 0)
  (assert (input:delete-before-cursor) "delete-before-cursor should delete active selection")
  (assert (= (snapshot-text buffer) "aef") "Backspace should remove selected bytes")
  (assert (= buffer.cursor-byte 1) "caret should move to selection start")
  (assert (not buffer.selection) "selection should clear after delete")
  (assert (= input.change-count 1) "selection delete should notify once")
  (input:drop))

(fn virtual-input-delete-deletes-active-selection []
  (local buffer (lazy-buffer "delete-selection" "abcdef"))
  (buffer:move-caret-to-byte 4)
  (buffer:set-selection 1 4)
  (local input (build-input {:buffer buffer
                             :line-count 1
                             :column-count 10
                             :on-change count-change}))
  (set input.change-count 0)
  (assert (input:delete-at-cursor) "delete-at-cursor should delete active selection")
  (assert (= (snapshot-text buffer) "aef") "Delete should remove selected bytes")
  (assert (= buffer.cursor-byte 1) "caret should move to selection start")
  (assert (not buffer.selection) "selection should clear after delete")
  (assert (= input.change-count 1) "selection delete should notify once")
  (input:drop))

(fn virtual-input-caret-navigation-scrolls-to-target-row []
  (local rows [(row 0 "zero" 0) (row 1 "one" 10) (row 2 "two" 20) (row 3 "three" 30)])
  (local buffer (make-buffer {:rows rows :cursor-byte 10}))
  (local input (build-input {:buffer buffer :line-count 2 :column-count 8}))
  (input:refresh-viewport)
  (input:move-caret :down)
  (local last-view (. buffer.state.viewport-calls (length buffer.state.viewport-calls)))
  (assert (= last-view.line 1) "moving to row beyond viewport should scroll requested rows")
  (input:drop))

(fn virtual-input-horizontal-navigation-preserves-utf8-boundaries []
  (local buffer (lazy-buffer "utf8-nav" "éx"))
  (local input (build-input {:buffer buffer :line-count 1 :column-count 8}))
  (input:move-caret-horizontal-bounded 1 {:allow-line-cross? true :allow-after-line-end? true})
  (assert (= buffer.cursor-byte 2) "right arrow should advance over the whole UTF-8 character")
  (input:move-caret-horizontal-bounded -1 {:allow-line-cross? true :allow-after-line-end? true})
  (assert (= buffer.cursor-byte 0) "left arrow should return to previous UTF-8 boundary")
  (input:drop))

(fn virtual-input-horizontal-crossing-newline-scrolls-viewport []
  (local buffer (lazy-buffer "horizontal-newline-scroll" "aa\r\nbb\r\ncc"))
  (buffer:move-caret-to-line-column 1 2)
  (local input (build-input {:buffer buffer :line-count 2 :column-count 8}))
  (input:refresh-viewport)
  (input:move-caret-horizontal-bounded 1 {:allow-line-cross? true :allow-after-line-end? true})
  (assert (= buffer.cursor-byte 8) "right arrow should cross CRLF to next row start")
  (assert (= input.scroll-line 1) "crossing below the viewport should scroll target row into view")
  (input:drop))
(fn move-without-safe-horizontal [input]
  (input:move-caret :right))

(fn virtual-input-horizontal-navigation-requires-safe-buffer-api []
  (local buffer (make-buffer {:rows [(row 0 "éx" 0)]}))
  (set buffer.move-caret-horizontal nil)
  (local input (build-input {:buffer buffer :line-count 1 :column-count 8}))
  (local (ok err) (pcall move-without-safe-horizontal input))
  (assert (not ok) "horizontal movement without safe buffer API should fail loudly")
  (assert (string.find (tostring err) "move-caret-horizontal" 1 true))
  (assert (= buffer.cursor-byte 0) "unsafe fallback must not move by raw bytes")
  (input:drop))

(fn virtual-input-layout-hides-off-viewport-caret []
  (local rows [(row 0 "zero" 0) (row 1 "one" 10) (row 2 "two" 20)])
  (local buffer (make-buffer {:rows rows :cursor-byte 30 :scroll-line 0}))
  (local input (build-input {:buffer buffer :line-count 2 :column-count 8}))
  (input.layout:measurer)
  (set input.layout.size input.layout.measure)
  (input.layout:layouter)
  (assert (= input.caret.visible? false) "off-viewport cursor should not render caret on first visible row")
  (input:drop))

(fn virtual-input-narrow-layout-requests-visible-columns-and-local-clip []
  (local buffer (make-buffer {:rows [(row 0 "abcdefghij" 0)
                                     (row 1 "klmnopqrst" 11)]}))
  (local input (build-input {:buffer buffer :line-count 2 :column-count 10}))
  (input.layout:measurer)
  (local narrow-width (+ (* 2 input.padding.x) (* 3 input.column-width)))
  (local one-line-height (+ (* 2 input.padding.y) input.line-height))
  (set input.layout.position (glm.vec3 1 2 0))
  (set input.layout.size (glm.vec3 narrow-width one-line-height 0))
  (set input.layout.clip-region {:id 9001
                                 :bounds {:position (glm.vec3 0 0 0)
                                          :rotation (glm.quat 1 0 0 0)
                                          :size (glm.vec3 100 100 0)}})
  (set buffer.state.viewport-calls [])
  (input.layout:layouter)
  (local last-view (. buffer.state.viewport-calls (length buffer.state.viewport-calls)))
  (assert (= input.visible-column-count 3) "allocated width should reduce visible columns")
  (assert (= input.visible-line-count 1) "allocated height should reduce visible rows")
  (assert-viewport-calls-bounded buffer.state.viewport-calls
                                 input.visible-line-count
                                 input.visible-column-count
                                 "narrow layout refresh should stay within allocated viewport")
  (assert (= last-view.columns 3) "refresh should request allocated visible columns")
  (assert (= last-view.lines 1) "refresh should request allocated visible rows")
  (assert input.local-clip-region "VirtualInput should create a local clip region")
  (assert (= (. input.rows 1 :layout :clip-region) input.local-clip-region)
          "visible row should receive local clip")
  (assert (= input.caret.layout.clip-region input.local-clip-region)
          "caret should receive local clip")
  (assert (<= input.local-clip-region.bounds.size.x input.layout.size.x)
          "local clip width should not exceed allocated input width")
  (input:drop))

(fn virtual-input-narrow-layout-text-state-l-moves-past-visible-edge []
  (with-virtual-input-states
    (fn [env]
      (local text-state (. env :text-state))
      (local buffer (lazy-buffer "narrow-text-state-right" "abcdefghij"))
      (local input (build-input {:buffer buffer :line-count 1 :column-count 10}))
      (input.layout:measurer)
      (local narrow-width (+ (* 2 input.padding.x) (* 3 input.column-width)))
      (local one-line-height (+ (* 2 input.padding.y) input.line-height))
      (set input.layout.position (glm.vec3 0 0 0))
      (set input.layout.size (glm.vec3 narrow-width one-line-height 0))
      (input.layout:layouter)
      (input:on-click {:row-index 1 :column 2})
      (assert (= input.visible-column-count 3) "precondition: narrow layout should expose three visual columns")
      (assert (text-state:on-key-down {:key (string.byte "l")})
              "TextState l should move beyond the last visible codepoint")
      (assert (= buffer.cursor-byte 3) (.. "l should route through the UTF-8-safe buffer movement API; byte=" buffer.cursor-byte " column=" input.cursor-column))
      (input:drop))))

(fn virtual-input-long-line-horizontal-navigation-keeps-caret-visible []
  (with-virtual-input-states
    (fn [env]
      (local text-state (. env :text-state))
      (local buffer (record-viewport-calls (lazy-buffer "horizontal-visible" "abcdefghijklmnopqrstuvwxyz")))
      (local input (build-input {:buffer buffer :line-count 1 :column-count 4}))
      (input.layout:measurer)
      (set input.layout.size (+ (glm.vec3 (* 2 input.padding.x)
                                          (* 2 input.padding.y)
                                          0)
                                 (glm.vec3 (* 4 input.column-width)
                                           input.line-height
                                           0)))
      (input.layout:layouter)
      (input:on-click {:row-index 1 :column 0})
      (for [_ 1 8]
        (text-state:on-key-down {:key (string.byte "l")})
        (input.layout:layouter))
      (assert (> input.scroll-column 0) "moving right past visible columns should scroll horizontally")
      (assert input.caret.visible? "caret should remain visible after horizontal scroll")
      (local local-x (- input.caret.layout.position.x input.layout.position.x))
      (assert (>= local-x input.padding.x) "caret x should stay inside left input padding")
      (assert (<= local-x (- input.layout.size.x input.padding.x))
              "caret x should stay inside right input padding")
      (local last-view (. buffer.state.viewport-calls (length buffer.state.viewport-calls)))
      (assert (= last-view.column input.scroll-column)
              "viewport request should use updated horizontal scroll column")
      (input:drop))))

(fn virtual-input-numeric-horizontal-jump-keeps-caret-visible []
  (local buffer (record-viewport-calls (lazy-buffer "numeric-horizontal-visible" "abcdefghijklmnopqrstuvwxyz")))
  (local input (build-input {:buffer buffer :line-count 1 :column-count 4}))
  (set-test-states) (input.layout:measurer)
  (set input.layout.size (+ (glm.vec3 (* 2 input.padding.x)
                                    (* 2 input.padding.y)
                                    0)
                           (glm.vec3 (* 4 input.column-width)
                                     input.line-height
                                     0)))
  (input.layout:layouter)
  (input:request-focus)
  (set buffer.state.viewport-calls [])
  (assert (input:move-caret 8) "numeric movement should move through the safe horizontal API")
  (input.layout:layouter)
  (assert (= input.scroll-column 5) "jumping to column 8 should scroll far enough to show the caret")
  (assert input.caret.visible? "caret should remain visible after numeric horizontal jump")
  (local local-x (- input.caret.layout.position.x input.layout.position.x))
  (assert (>= local-x input.padding.x) "caret x should stay inside left input padding after jump")
  (assert (<= local-x (- input.layout.size.x input.padding.x))
          "caret x should stay inside right input padding after jump")
  (local last-view (. buffer.state.viewport-calls (length buffer.state.viewport-calls)))
  (assert (= last-view.column input.scroll-column)
          "viewport request should use updated horizontal scroll column after jump")
  (assert-viewport-calls-bounded buffer.state.viewport-calls
                                  input.visible-line-count
                                  input.visible-column-count
                                   "numeric horizontal jump should not expand caret discovery requests")
  (input:drop))

(fn virtual-input-arrow-vertical-preserves-logical-column-outside-visible-row []
  (local buffer (lazy-buffer "arrow-logical-column"
                             "0123456789ABCDEFGHIJ\nabcdefghijklmnopqrst\n"))
  (buffer:move-caret-to-line-column 0 8)
  (local input (build-input {:buffer buffer :line-count 2 :column-count 4}))
  (set-test-states) (narrow-layout! input 4 2)
  (input:request-focus)
  (set input.scroll-column 0)
  (input:refresh-viewport)
  (assert (input:move-caret :down)
          "vertical caret movement should use logical cursor coordinates")
  (assert (= input.cursor-line 1) "Down arrow should move to next logical line")
  (assert (= input.cursor-column 8)
          "Down arrow should preserve logical column outside visible row")
  (assert (= buffer.cursor-byte 29)
          "Down arrow should move buffer cursor to line 1 logical column 8")
  (assert-caret-visible-inside input "Down arrow")
  (input:drop))

(fn virtual-input-text-state-caret-on-whitespace-only-line-matches-input []
  (with-virtual-input-states
    (fn [env]
      (local text-state (. env :text-state))
      (local buffer (lazy-buffer "caret-whitespace-only" "   \nnext"))
      (buffer:move-caret-to-line-column 0 2)
      (local input (build-input {:buffer buffer :line-count 1 :column-count 4}))
      (narrow-layout! input 4 1)
      (input:request-focus)
      (assert (text-state:on-key-down {:key (key "^") :mod 1})
              "^ should be handled on whitespace-only VirtualInput line")
      (assert (= input.cursor-column 0)
              "^ should resolve whitespace-only line to column 0 like Input")
      (assert (= buffer.cursor-byte 0)
              "^ should move buffer cursor to whitespace-only line start")
      (input:drop))))

(fn virtual-input-text-state-line-edges-use-full-logical-long-line []
  (with-virtual-input-states
    (fn [env]
      (local states (. env :states))
      (local text-state (. env :text-state))
      (local insert-state (. env :insert-state))
      (local buffer (lazy-buffer "text-state-full-line-edges"
                                 "  abcdefghijklmnopqrstuvwxyz\nshort\n"))
      (buffer:move-caret-to-line-column 0 8)
      (local input (build-input {:buffer buffer :line-count 1 :column-count 4}))
      (narrow-layout! input 4 1)
      (input:refresh-viewport)
      (input:request-focus)
      (states:set-state :text)
      (assert (text-state:on-key-down {:key (key "0")})
              "0 should move to full logical line start")
      (assert (= buffer.cursor-byte 0) "0 should land at byte 0, not viewport start")
      (assert (= input.cursor-column 0) "0 should sync logical column 0")
      (assert (= input.scroll-column 0) "0 should reveal logical start")
      (assert (text-state:on-key-down {:key (key "$") :mod 1})
              "$ should move to full logical line end")
      (assert (= input.cursor-column 27) "$ should use full line length")
      (assert (= buffer.cursor-byte 27) "$ should place caret on last logical character")
      (assert (> input.scroll-column 0) "$ should reveal logical line end")
      (assert-caret-visible-inside input "$")
      (assert (text-state:on-key-down {:key (key "^") :mod 1})
              "^ should move to first nonblank in full logical line")
      (assert (= input.cursor-column 2) "^ should ignore leading spaces")
      (assert (= buffer.cursor-byte 2) "^ should land at first nonblank byte")
      (assert (text-state:on-key-down {:key (key "A")})
              "A should append after full logical line end")
      (assert (= input.mode :insert) "A should enter insert mode")
      (assert (= buffer.cursor-byte 28) "A should place insert caret after full line")
      (assert-caret-visible-inside input "A")
      (assert (insert-state:on-key-down {:key 27}) "Escape should leave A insert mode")
      (assert (text-state:on-key-down {:key (key "I")})
              "I should insert at first nonblank of full logical line")
      (assert (= input.mode :insert) "I should enter insert mode")
      (assert (= buffer.cursor-byte 2) "I should land at first nonblank byte")
      (input:drop))))

(fn virtual-input-text-state-j-k-preserve-logical-column-over-clipped-lines []
  (with-virtual-input-states
    (fn [env]
      (local text-state (. env :text-state))
      (local buffer (lazy-buffer "text-state-clipped-vertical"
                                 "0123456789ABCDEFGHIJ\nabcdefghijklmnopqrst\nUVWXYZ0123456789abcd\n"))
      (buffer:move-caret-to-line-column 0 8)
      (local input (build-input {:buffer buffer :line-count 2 :column-count 4}))
      (narrow-layout! input 4 2)
      (input:refresh-viewport)
      (input:request-focus)
      (assert (text-state:on-key-down {:key (key "j")}) "j should move down")
      (assert (= input.cursor-line 1) "j should move to logical line 1")
      (assert (= input.cursor-column 8) "j should preserve logical column 8")
      (assert (> input.scroll-column 0) "j should keep clipped logical column visible")
      (assert-caret-visible-inside input "j")
      (assert (text-state:on-key-down {:key (key "k")}) "k should move up")
      (assert (= input.cursor-line 0) "k should return to logical line 0")
      (assert (= input.cursor-column 8) "k should preserve logical column 8")
      (assert-caret-visible-inside input "k")
      (input:drop))))

(fn virtual-input-text-state-goto-and-page-movement-use-logical-lines []
  (with-virtual-input-states
    (fn [env]
      (local text-state (. env :text-state))
      (local buffer (lazy-buffer "text-state-goto-page"
                                 "line0\nline1\nline2\nline3\nline4\nline5\n"))
      (local input (build-input {:buffer buffer :line-count 2 :column-count 8}))
      (narrow-layout! input 8 2)
      (input:on-click {:row-index 1 :column 0})
      (assert (text-state:on-key-down {:key (key "G")}) "G should move to final logical line")
      (assert (= input.cursor-line 6) "G should include trailing empty logical line")
      (assert (= input.scroll-line 5) "G should reveal final line in two-line viewport")
      (assert-caret-visible-inside input "G")
      (assert (text-state:on-key-down {:key (key "g")}) "first g should enter prefix")
      (assert (text-state:on-key-down {:key (key "g")}) "gg should move to first line")
      (assert (= input.cursor-line 0) "gg should return to logical line 0")
      (assert (= input.scroll-line 0) "gg should reveal first line")
      (assert-caret-visible-inside input "gg")
      (assert (input:on-key-down {:key 1073741902}) "PageDown should be handled")
      (assert (= input.cursor-line 2) "PageDown should move by visible logical lines")
      (assert (= input.scroll-line 2) "PageDown should scroll by visible logical lines")
      (assert-caret-visible-inside input "PageDown")
      (input:drop))))

(fn virtual-input-editing-maintains-horizontal-and-vertical-visibility []
  (local buffer (lazy-buffer "edit-both-axis-visibility" "row0\nrow1\nabcdefghij\n"))
  (buffer:move-caret-to-line-column 2 8)
  (local input (build-input {:buffer buffer :line-count 2 :column-count 4}))
  (set-test-states) (narrow-layout! input 4 2)
  (input:request-focus)
  (set input.scroll-line 1)
  (set input.scroll-column 5)
  (input:refresh-viewport)
  (assert (input:insert-text "\nZ") "insert should mutate lazy buffer")
  (assert (= input.cursor-line 3) "inserted newline should update logical line")
  (assert (= input.cursor-column 1) "inserted text should update logical column")
  (assert (= input.scroll-line 2) "insert should keep new line visible")
  (assert (= input.scroll-column 1) "insert should keep new column visible")
  (assert-caret-visible-inside input "insert")
  (input:drop))

(fn virtual-input-text-state-x-deletes-clamps-and-keeps-caret-visible []
  (with-virtual-input-states
    (fn [env]
      (local text-state (. env :text-state))
      (local buffer (lazy-buffer "delete-clamp-visible" "abcdefghij"))
      (buffer:move-caret-to-line-column 0 9)
      (local input (build-input {:buffer buffer :line-count 1 :column-count 4}))
      (narrow-layout! input 4 1)
      (set input.scroll-column 6)
      (input:refresh-viewport)
      (input:request-focus)
      (assert (text-state:on-key-down {:key (key "x")}) "x should delete at cursor")
      (assert (= (snapshot-text buffer) "abcdefghi") "x should delete final character")
      (assert (= input.cursor-column 8) "x should clamp to new final logical char")
      (assert (= buffer.cursor-byte 8) "x should clamp buffer cursor")
      (assert-caret-visible-inside input "x")
      (input:drop))))

(fn virtual-input-disconnect-normalizes-mode-like-input []
  (local buffer (lazy-buffer "disconnect-normal-mode" "abc"))
  (local input (build-input {:buffer buffer :line-count 1 :column-count 8}))
  (input:enter-insert-mode)
  (input:on-state-connected {})
  (input:on-state-disconnected {})
  (assert (= input.connected? false) "disconnect should clear connected flag")
  (assert (= input.mode :normal) "disconnect should normalize VirtualInput mode")
  (input:drop))

(fn virtual-input-h-l-after-exact-dollar-on-huge-line-stays-bounded []
  (with-virtual-input-states
    (fn [env]
      (local text-state (. env :text-state))
      (local buffer (instrument-logical-scans (lazy-buffer "hot-hl-after-dollar" (string.rep "a" 100000) {:chunk-bytes 65536})))
      (local input (build-input {:buffer buffer :line-count 1 :column-count 4}))
      (narrow-layout! input 4 1)
      (input:on-click {:row-index 1 :column 0})
      (assert (text-state:on-key-down {:key (key "$") :mod 1}) "$ should land on the huge logical line end before bounded h/l") (input:move-caret-to-line-column 0 100000)
      (reset-logical-scan-counters! buffer)
      (assert (= (input:on-key-down {:key 1073741903}) false) "direct right arrow at far line end should return bounded no-move") (local handled-h (text-state:on-key-down {:key (key "h")}))
      (local handled-l (text-state:on-key-down {:key (key "l")}))
      (assert handled-h "h after exact $ should be handled")
      (assert handled-l "l after exact $ should be handled")
      (assert-no-full-logical-scans buffer "h/l after exact $")
      (assert-caret-visible-inside input "h/l after exact $")
      (assert (> input.scroll-column 0) "h/l after exact $ should keep far horizontal scroll")
      (input:drop))))

(fn virtual-input-repeated-h-l-far-into-huge-line-stays-bounded []
  (with-virtual-input-states
    (fn [env]
      (local text-state (. env :text-state))
      (local buffer (instrument-logical-scans (lazy-buffer "hot-repeated-hl" (string.rep "a" 100000) {:chunk-bytes 65536})))
      (local input (build-input {:buffer buffer :line-count 1 :column-count 4}))
      (narrow-layout! input 4 1)
      (input:move-caret-to-line-column 0 90000)
      (input:request-focus)
      (reset-logical-scan-counters! buffer)
      (for [i 1 25]
        (local command (if (= (% i 2) 1) "h" "l"))
        (assert (text-state:on-key-down {:key (key command)}) (.. command " should be handled during repeated far h/l")))
      (assert (and (>= input.cursor-column 89999) (<= input.cursor-column 90000)) (.. "repeated h/l should stay near the far logical column; column=" input.cursor-column))
      (assert (= (input:on-key-down {:key 1073741904}) false) "direct left arrow should not bypass normal command routing")
      (assert (= (input:on-key-down {:key 1073741903}) false) "direct right arrow should not bypass normal command routing")
      (assert-no-full-logical-scans buffer "repeated far h/l")
      (input:drop))))

(fn virtual-input-j-k-from-far-column-uses-cached-target-anchors []
  (with-virtual-input-states
    (fn [env]
      (local text-state (. env :text-state))
      (local huge-line (string.rep "a" 100000))
      (local buffer (instrument-logical-scans (lazy-buffer "hot-jk-cached-anchors" (.. huge-line "\n" huge-line "\n" huge-line) {:chunk-bytes 65536})))
      (local input (build-input {:buffer buffer :line-count 3 :column-count 4}))
      (narrow-layout! input 4 3)
      (input:move-caret-to-line-column 1 90000)
      (set input.scroll-line 1)
      (set buffer.scroll-line 1)
      (set input.scroll-column 89997)
      (input:refresh-viewport)
      (seed-viewport-anchor! buffer 0 90000 4)
      (seed-viewport-anchor! buffer 2 90000 4)
      (input:move-caret-to-line-column 1 90000)
      (input:request-focus)
      (reset-logical-scan-counters! buffer)
      (assert (text-state:on-key-down {:key (key "j")}) "j from far cached anchor column should be handled")
      (assert (= input.cursor-line 2) "j should move to logical line 2")
      (assert (= input.cursor-column 90000) "j should preserve far preferred column")
      (assert (= input.__preferred-column 90000) "j should preserve preferred column cache")
      (assert-caret-visible-inside input "j from far cached column")
      (assert (text-state:on-key-down {:key (key "k")}) "k from far cached anchor column should be handled")
      (assert (= input.cursor-line 1) "k should return to logical line 1")
      (assert (= input.cursor-column 90000) "k should preserve far preferred column")
      (assert-caret-visible-inside input "k from far cached column")
      (input:move-caret-to-line-column 1 0) (reset-logical-scan-counters! buffer) (assert (= (input:on-key-down {:key 1073741904}) false) "direct left arrow at far line start should return bounded no-move")
      (assert-no-full-logical-scans buffer "j/k from cached target anchors")
      (input:drop))))

(fn virtual-input-j-k-from-far-column-clamps-to-short-target-line-end []
  (with-virtual-input-states (fn [env]
    (local text-state (. env :text-state)) (local huge-line (string.rep "a" 100000)) (local short-line "tiny")
    (local buffer (instrument-logical-scans (lazy-buffer "hot-jk-short-target" (.. huge-line "\n" short-line "\n" huge-line) {:chunk-bytes 65536}))) (local input (build-input {:buffer buffer :line-count 3 :column-count 4})) (narrow-layout! input 4 3)
    (input:move-caret-to-line-column 0 90000) (set input.scroll-line 0) (set buffer.scroll-line 0) (set input.scroll-column 89997) (input:refresh-viewport) (buffer:move-caret-to-line-column 1 (# short-line))
    (tset input.viewport-row-anchor-cache "1:4" {:byte buffer.cursor-byte :line 1 :column 4 :line-end? true}) (tset input.viewport-row-anchor-cache "1:90000" {:byte buffer.cursor-byte :line 1 :column 4 :line-end? true})
    (input:move-caret-to-line-column 0 90000) (set input.scroll-line 0) (set buffer.scroll-line 0) (set input.scroll-column 89997) (input:request-focus) (set input.__preferred-column 90000) (reset-logical-scan-counters! buffer)
    (assert (input:move-caret-vertical-bounded 1) "bounded j should move into short cached row") (assert (= input.cursor-line 1) "j should move to short line") (assert (= input.cursor-column (# short-line)) "j should clamp to actual short line end")
    (assert (= input.__preferred-column 90000) "j should preserve far preferred column") (assert (text-state:on-key-down {:key (key "k")}) "k should return toward cached huge source") (assert (= input.cursor-line 0) "k should return to huge source") (assert (= input.cursor-column 90000) "k should restore far preferred column") (assert-no-full-logical-scans buffer "j/k far column into short target") (input:drop))))

(fn virtual-input-text-state-l-stops-at-cached-line-end []
  (with-virtual-input-states (fn [env]
    (local text-state (. env :text-state)) (local buffer (instrument-logical-scans (lazy-buffer "hot-l-boundary" "abc\ndef" {:chunk-bytes 16}))) (local input (build-input {:buffer buffer :line-count 2 :column-count 8}))
    (narrow-layout! input 8 2) (input:on-click {:row-index 1 :column 0}) (assert (text-state:on-key-down {:key (key "$") :mod 1}) "$ should move to last valid character") (assert (= input.cursor-column 2) "$ should land on last valid character")
    (reset-logical-scan-counters! buffer) (assert (= (input:move-caret-horizontal-bounded 1) false) "bounded l after $ should return false") (assert (text-state:on-key-down {:key (key "l")}) "TextState should consume l")
    (assert (= input.cursor-line 0) "l after $ should not cross rows") (assert (= input.cursor-column 2) "l after $ should not move") (input:move-caret-to-line-column 0 0) (input:refresh-viewport) (reset-logical-scan-counters! buffer)
    (assert (text-state:on-key-down {:key (key "l")}) "first l should move") (assert (text-state:on-key-down {:key (key "l")}) "second l should reach last valid character") (assert (= (input:move-caret-horizontal-bounded 1) false) "bounded l at cached row boundary should return false")
    (assert (text-state:on-key-down {:key (key "l")}) "TextState should consume repeated boundary l") (assert (= input.cursor-line 0) "repeated l should not cross rows") (assert (= input.cursor-column 2) "repeated l should stay at line end") (assert-no-full-logical-scans buffer "cached line-end l") (input:drop))))

(fn virtual-input-refresh-after-far-horizontal-scroll-uses-cached-viewport-anchor []
  (local buffer (instrument-logical-scans (lazy-buffer "hot-refresh-horizontal-anchor" (string.rep "a" 100000) {:chunk-bytes 65536})))
  (local input (build-input {:buffer buffer :line-count 1 :column-count 4}))
  (narrow-layout! input 4 1)
  (input:move-caret-to-line-column 0 90000)
  (set input.scroll-column 89997)
  (input:refresh-viewport)
  (reset-logical-scan-counters! buffer)
  (input:refresh-viewport)
  (local rendered-row (. input.viewport.rows 1))
  (assert (and rendered-row (>= rendered-row.start-byte input.scroll-column)) "far horizontal refresh should render from the horizontal scroll anchor")
  (assert-no-full-logical-scans buffer "refresh after far horizontal scroll")
  (input:drop))

(fn virtual-input-exact-dollar-A-G-still-work-with-anchor-cache []
  (with-virtual-input-states
    (fn [env]
      (local text-state (. env :text-state))
      (local insert-state (. env :insert-state))
      (local long-line (string.rep "a" 100000))
      (local buffer (instrument-logical-scans (lazy-buffer "exact-commands-anchor-cache" (.. long-line "\n" "final!") {:chunk-bytes 65536})))
      (local input (build-input {:buffer buffer :line-count 2 :column-count 4}))
      (narrow-layout! input 4 2)
      (input:on-click {:row-index 1 :column 0})
      (assert (text-state:on-key-down {:key (key "$") :mod 1}) "$ should be handled on a long line")
      (assert (= buffer.cursor-byte 99999) "$ should land at the last logical character")
      (assert-input-cursor input buffer 0 99999 "$")
      (assert (text-state:on-key-down {:key (key "A")}) "A should be handled after long-line $")
      (assert (= input.mode :insert) "A should enter insert mode")
      (assert (= buffer.cursor-byte 100000) "A should place caret after line end")
      (assert-input-cursor input buffer 0 100000 "A")
      (assert (insert-state:on-key-down {:key 27}) "Escape should leave insert after A")
      (assert (= input.mode :normal) "Escape should return VirtualInput to normal mode")
      (assert (= buffer.cursor-byte 99999) "Escape after A should move caret back onto final character")
      (assert-input-cursor input buffer 0 99999 "Escape")
      (assert (text-state:on-key-down {:key (key "G")}) "G should be handled with anchor cache populated")
      (assert (= input.cursor-line 1) "G should land on the final logical line")
      (assert (= input.cursor-column 5) "G should clamp to final line end")
      (assert (= buffer.cursor-byte 100006) "G should move buffer cursor to final logical line end")
      (assert-input-cursor input buffer 1 5 "G")
      (input:drop))))

(table.insert tests {:name "VirtualInput requires explicit build context" :fn virtual-input-requires-explicit-build-context}) (table.insert tests {:name "VirtualInput renders only visible viewport rows" :fn virtual-input-renders-only-visible-viewport-rows})
(table.insert tests {:name "VirtualInput caret navigation loads lazy rows" :fn virtual-input-caret-navigation-loads-lazy-rows}) (table.insert tests {:name "VirtualInput PageDown keeps subsequent vertical navigation valid" :fn virtual-input-page-down-keeps-subsequent-vertical-navigation-valid})
(table.insert tests {:name "VirtualInput Shift+PageDown extends selection" :fn virtual-input-shift-page-down-extends-selection}) (table.insert tests {:name "VirtualInput Shift+PageUp extends selection" :fn virtual-input-shift-page-up-extends-selection})
(table.insert tests {:name "VirtualInput inserts and deletes through lazy buffer" :fn virtual-input-inserts-and-deletes-through-lazy-buffer}) (table.insert tests {:name "VirtualInput copies selected text" :fn virtual-input-copies-selected-text})
(table.insert tests {:name "VirtualInput save reports success and conflict" :fn virtual-input-save-reports-success-and-conflict}) (table.insert tests {:name "VirtualInput drop tears down owned children" :fn virtual-input-drop-tears-down-owned-children})
(table.insert tests {:name "VirtualInput click focus routes InputState events" :fn virtual-input-click-focus-routes-input-state-events}) (table.insert tests {:name "VirtualInput TextState i enters insert mode" :fn virtual-input-text-state-i-enters-insert-mode})
(table.insert tests {:name "VirtualInput state helper clears ignored text input" :fn virtual-input-state-helper-clears-ignored-text-input}) (table.insert tests {:name "VirtualInput TextState h/l/arrows move through command engine" :fn virtual-input-text-state-h-l-move-without-numeric-delta-error})
(table.insert tests {:name "VirtualInput TextState j/k move using lazy rows" :fn virtual-input-text-state-j-k-move-using-lazy-rows}) (table.insert tests {:name "VirtualInput TextState x deletes and clamps" :fn virtual-input-text-state-x-deletes-and-clamps})
(table.insert tests {:name "VirtualInput InsertState Escape returns to text mode" :fn virtual-input-insert-state-escape-returns-to-text-mode}) (table.insert tests {:name "VirtualInput InsertState Return inserts newline" :fn virtual-input-insert-state-return-inserts-newline})
(table.insert tests {:name "VirtualInput insertion replaces real buffer selection" :fn virtual-input-insertion-replaces-real-buffer-selection}) (table.insert tests {:name "VirtualInput Backspace deletes active selection" :fn virtual-input-backspace-deletes-active-selection})
(table.insert tests {:name "VirtualInput Delete deletes active selection" :fn virtual-input-delete-deletes-active-selection}) (table.insert tests {:name "VirtualInput caret navigation scrolls to target row" :fn virtual-input-caret-navigation-scrolls-to-target-row})
(table.insert tests {:name "VirtualInput horizontal navigation preserves UTF-8 boundaries" :fn virtual-input-horizontal-navigation-preserves-utf8-boundaries}) (table.insert tests {:name "VirtualInput horizontal crossing newline scrolls viewport" :fn virtual-input-horizontal-crossing-newline-scrolls-viewport})
(table.insert tests {:name "VirtualInput horizontal navigation requires safe buffer API" :fn virtual-input-horizontal-navigation-requires-safe-buffer-api}) (table.insert tests {:name "VirtualInput layout hides off-viewport caret" :fn virtual-input-layout-hides-off-viewport-caret})
(table.insert tests {:name "VirtualInput narrow layout requests visible columns and local clip" :fn virtual-input-narrow-layout-requests-visible-columns-and-local-clip}) (table.insert tests {:name "VirtualInput narrow layout TextState l moves past visible edge" :fn virtual-input-narrow-layout-text-state-l-moves-past-visible-edge})
(table.insert tests {:name "VirtualInput long-line horizontal navigation keeps caret visible" :fn virtual-input-long-line-horizontal-navigation-keeps-caret-visible}) (table.insert tests {:name "VirtualInput numeric horizontal jump keeps caret visible" :fn virtual-input-numeric-horizontal-jump-keeps-caret-visible})
(table.insert tests {:name "VirtualInput arrow vertical preserves logical column outside visible row" :fn virtual-input-arrow-vertical-preserves-logical-column-outside-visible-row}) (table.insert tests {:name "VirtualInput TextState caret on whitespace-only line matches Input" :fn virtual-input-text-state-caret-on-whitespace-only-line-matches-input})
(table.insert tests {:name "VirtualInput TextState line edges use full logical long line" :fn virtual-input-text-state-line-edges-use-full-logical-long-line}) (table.insert tests {:name "VirtualInput TextState j/k preserve logical column over clipped lines" :fn virtual-input-text-state-j-k-preserve-logical-column-over-clipped-lines})
(table.insert tests {:name "VirtualInput TextState goto and page movement use logical lines" :fn virtual-input-text-state-goto-and-page-movement-use-logical-lines}) (table.insert tests {:name "VirtualInput editing maintains horizontal and vertical visibility" :fn virtual-input-editing-maintains-horizontal-and-vertical-visibility})
(table.insert tests {:name "VirtualInput TextState x deletes clamps and keeps caret visible" :fn virtual-input-text-state-x-deletes-clamps-and-keeps-caret-visible}) (table.insert tests {:name "VirtualInput disconnect normalizes mode like Input" :fn virtual-input-disconnect-normalizes-mode-like-input})
(table.insert tests {:name "VirtualInput h/l after exact dollar on huge line stays bounded" :fn virtual-input-h-l-after-exact-dollar-on-huge-line-stays-bounded})
(table.insert tests {:name "VirtualInput repeated h/l far into huge line stays bounded" :fn virtual-input-repeated-h-l-far-into-huge-line-stays-bounded})
(table.insert tests {:name "VirtualInput j/k from far column uses cached target anchors" :fn virtual-input-j-k-from-far-column-uses-cached-target-anchors})
(table.insert tests {:name "VirtualInput j/k from far column clamps to short target line end" :fn virtual-input-j-k-from-far-column-clamps-to-short-target-line-end})
(table.insert tests {:name "VirtualInput TextState l stops at cached line end" :fn virtual-input-text-state-l-stops-at-cached-line-end})
(table.insert tests {:name "VirtualInput refresh after far horizontal scroll uses cached viewport anchor" :fn virtual-input-refresh-after-far-horizontal-scroll-uses-cached-viewport-anchor})
(table.insert tests {:name "VirtualInput exact dollar A G still work with anchor cache" :fn virtual-input-exact-dollar-A-G-still-work-with-anchor-cache})
(each [_ test (ipairs (require :tests/virtual-input-parity))] (table.insert tests test))
(each [_ test (ipairs (require :tests/virtual-input-word-motion))] (table.insert tests test))
(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "virtual-input"
                       :tests tests})))
{:name "virtual-input"
 :tests tests
 :main main}
