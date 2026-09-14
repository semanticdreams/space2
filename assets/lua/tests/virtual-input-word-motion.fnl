(local _ (require :main))
(local glm (require :glm))
(local BuildContext (require :build-context))
(local VirtualInput (require :virtual-input))
(local fs (require :fs))
(local LazyTextSource (require :lazy-text-source))
(local LazyTextBuffer (require :lazy-text-buffer))
(local Runtime (require :state-runtime))
(local States (require :states))
(local StateSystemBindings (require :state-system-bindings))
(local TextState (require :text-state))
(local InsertState (require :insert-state))

(local temp-root "/tmp/space/tests/virtual-input-word-motion")

(fn noop-register [_self _obj])
(fn command-hints-toggle [_self _payload] true)
(fn command-hints-close [_self _route-key _payload] false)

(fn make-command-hints-stub []
  {:handle-toggle-key command-hints-toggle
   :close-on-handled-event command-hints-close})

(fn command-hints-hud-provider [_self]
  {:command-hints (make-command-hints-stub)})

(fn make-ctx []
  (BuildContext {:clickables {:register noop-register
                              :unregister noop-register}
                 :hoverables {:register noop-register
                              :unregister noop-register}}))

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

(fn key [value] (string.byte value))

(fn build-input [opts]
  ((VirtualInput opts) (make-ctx)))

(fn narrow-layout! [input columns lines]
  (input.layout:measurer)
  (set input.layout.size
       (glm.vec3 (+ (* 2 input.padding.x) (* columns input.column-width))
                 (+ (* 2 input.padding.y) (* lines input.line-height))
                 0))
  (input.layout:layouter)
  input)

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
  (local (ok result) (pcall body {:states states :text-state text-state}))
  (Runtime.reset)
  (StateSystemBindings.bind-states-host original-states)
  (when states.drop
    (states:drop))
  (if ok
      result
      (error result)))

(fn assert-input-cursor [input buffer line column message]
  (assert (= input.cursor-index buffer.cursor-byte) (.. message ": input cursor byte should match buffer"))
  (assert (= input.cursor-line line) (.. message ": cursor line should match expected"))
  (assert (= input.cursor-column column) (.. message ": cursor column should match expected")))

(fn assert-caret-visible-inside [input message]
  (input.layout:layouter)
  (assert input.caret.visible? (.. message ": caret should be visible")))

(fn instrument-logical-scans [buffer]
  (when (= buffer.state nil) (set buffer.state {}))
  (local state buffer.state)
  (set state.get-line-summary-calls 0)
  (set state.line-column-for-byte-calls 0)
  (set state.get-line-count-calls 0)
  (local original-get-line-summary buffer.get-line-summary)
  (local original-line-column-for-byte buffer.line-column-for-byte)
  (local original-get-line-count buffer.get-line-count)
  (fn wrapped-get-line-summary [self line]
    (set state.get-line-summary-calls (+ state.get-line-summary-calls 1))
    (original-get-line-summary self line))
  (fn wrapped-line-column-for-byte [self byte]
    (set state.line-column-for-byte-calls (+ state.line-column-for-byte-calls 1))
    (original-line-column-for-byte self byte))
  (fn wrapped-get-line-count [self]
    (set state.get-line-count-calls (+ state.get-line-count-calls 1))
    (original-get-line-count self))
  (set buffer.get-line-summary wrapped-get-line-summary)
  (set buffer.line-column-for-byte wrapped-line-column-for-byte)
  (set buffer.get-line-count wrapped-get-line-count)
  buffer)

(fn reset-logical-scan-counters! [buffer]
  (set buffer.state.get-line-summary-calls 0)
  (set buffer.state.line-column-for-byte-calls 0)
  (set buffer.state.get-line-count-calls 0))

(fn assert-no-full-logical-scans [buffer message]
  (assert (= buffer.state.get-line-summary-calls 0) (.. message ": get-line-summary should not be called"))
  (assert (= buffer.state.line-column-for-byte-calls 0) (.. message ": line-column-for-byte should not be called"))
  (assert (= buffer.state.get-line-count-calls 0) (.. message ": get-line-count should not be called")))

(fn instrument-source-reads [source]
  (local original-read-range source.read-range)
  (set source.max-requested 0)
  (fn wrapped-read-range [self offset max-bytes]
    (set self.max-requested (math.max self.max-requested max-bytes))
    (original-read-range self offset max-bytes))
  (set source.read-range wrapped-read-range)
  source)

(fn call-with-large-concat-disabled [limit f arg]
  (local original-concat table.concat)
  (fn guarded-concat [items sep i j]
    (var total 0)
    (local start (if (= i nil) 1 i))
    (local finish (if (= j nil) (length items) j))
    (for [index start finish]
      (local item (. items index))
      (when (= (type item) :string)
        (set total (+ total (# item)))))
    (when (> total limit)
      (error (.. "table.concat materialized " total " bytes; limit=" limit)))
    (original-concat items sep i j))
  (set table.concat guarded-concat)
  (local (ok result) (pcall f arg))
  (set table.concat original-concat)
  (if ok result (error result)))

(fn run-basic-word-motion-case [name content opts steps]
  (fn run-case [env]
    (local buffer (lazy-buffer name content {:chunk-bytes 4}))
    (when opts.cursor-column
      (buffer:move-caret-to-line-column 0 opts.cursor-column))
    (local line-count (if (= opts.line-count nil) 1 opts.line-count))
    (local input (build-input {:buffer buffer :line-count line-count :column-count 12}))
    (local text-state (. env :text-state))
    (input:request-focus)
    (each [idx expected (ipairs steps)]
      (assert (text-state:on-key-down {:key (key "w")})
              (.. name " step " idx " should move"))
      (assert-input-cursor input buffer (. expected 1) (. expected 2) (.. name " step " idx)))
    (input:drop))
  (with-virtual-input-states run-case))

(fn virtual-input-text-state-w-moves-within-word []
  (run-basic-word-motion-case "word-within" "alpha beta" {} [[0 6]]))

(fn virtual-input-text-state-w-moves-from-whitespace []
  (run-basic-word-motion-case "word-whitespace" "alpha  beta" {:cursor-column 5} [[0 7]]))

(fn virtual-input-text-state-w-respects-punctuation-boundaries []
  (run-basic-word-motion-case "word-punctuation" "foo.bar baz" {} [[0 3] [0 4] [0 8]]))

(fn virtual-input-text-state-w-crosses-newline []
  (run-basic-word-motion-case "word-newline" "alpha\nbeta" {:line-count 2} [[1 0]]))

(fn word-motion-lazy-input [name content]
  (local path (make-temp-file name content))
  (local source (instrument-source-reads (LazyTextSource.file path {:chunk-bytes 16})))
  (local buffer (instrument-logical-scans (LazyTextBuffer {:source source :chunk-bytes 16})))
  (local input (build-input {:buffer buffer :line-count 1 :column-count 4}))
  (narrow-layout! input 4 1)
  (values source buffer input))

(fn press-w [text-state]
  (text-state:on-key-down {:key (key "w")}))

(fn assert-press-w [text-state]
  (assert (text-state:on-key-down {:key (key "w")}) "w should stream to next word on huge line"))

(fn assert-eof-word-motion [env]
  (local (source buffer input) (word-motion-lazy-input "word-eof" (string.rep "a" 100000)))
  (input:request-focus)
  (reset-logical-scan-counters! buffer)
  ;; TextState may consume the key through active-input routing even when the
  ;; command engine returns false; assert the user-visible EOF no-move/lazy behavior.
  (call-with-large-concat-disabled 4096 press-w (. env :text-state))
  (assert-input-cursor input buffer 0 0 "w eof no move")
  (assert (<= source.max-requested 16) (.. "EOF word motion should keep source requests bounded; max=" source.max-requested))
  (assert-no-full-logical-scans buffer "eof w")
  (input:drop))

(fn virtual-input-text-state-w-at-eof-does-not-move []
  (with-virtual-input-states assert-eof-word-motion))

(fn assert-huge-word-motion [env]
  (local (source buffer input) (word-motion-lazy-input "word-huge" (.. (string.rep "a" 100000) " next")))
  (input:request-focus)
  (reset-logical-scan-counters! buffer)
  (call-with-large-concat-disabled 4096 assert-press-w (. env :text-state))
  (assert-input-cursor input buffer 0 100001 "w huge line")
  (assert (<= source.max-requested 16) (.. "huge word motion should keep source requests bounded; max=" source.max-requested))
  (assert-no-full-logical-scans buffer "huge w")
  (assert-caret-visible-inside input "huge w")
  (input:drop))

(fn virtual-input-text-state-w-huge-line-stays-lazy []
  (with-virtual-input-states assert-huge-word-motion))

[{:name "VirtualInput TextState w moves within word" :fn virtual-input-text-state-w-moves-within-word}
 {:name "VirtualInput TextState w moves from whitespace" :fn virtual-input-text-state-w-moves-from-whitespace}
 {:name "VirtualInput TextState w respects punctuation boundaries" :fn virtual-input-text-state-w-respects-punctuation-boundaries}
 {:name "VirtualInput TextState w crosses newline" :fn virtual-input-text-state-w-crosses-newline}
 {:name "VirtualInput TextState w at EOF does not move" :fn virtual-input-text-state-w-at-eof-does-not-move}
 {:name "VirtualInput TextState w huge line stays lazy" :fn virtual-input-text-state-w-huge-line-stays-lazy}]
