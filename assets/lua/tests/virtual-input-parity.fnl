(local _ (require :main))
(local glm (require :glm))
(local BuildContext (require :build-context))
(local Input (require :input))
(local VirtualInput (require :virtual-input))
(local fs (require :fs))
(local LazyTextSource (require :lazy-text-source))
(local LazyTextBuffer (require :lazy-text-buffer))
(local States (require :states))
(local StateSystemBindings (require :state-system-bindings))
(local {: fallback-glyph} (require :text-utils))
(local MathUtils (require :math-utils))
(local approx (. MathUtils :approx))
(local temp-root "/tmp/space/tests/virtual-input-parity")

(fn codepoints->text [codepoints]
  (assert (= (type codepoints) :table) "codepoints->text requires codepoints")
  (table.concat (icollect [_ cp (ipairs codepoints)] (utf8.char cp))))

(fn pointer-stub []
  {:register (fn [_ _] nil) :unregister (fn [_ _] nil)
   :register-right-click (fn [_ _] nil) :unregister-right-click (fn [_ _] nil)
   :register-double-click (fn [_ _] nil) :unregister-double-click (fn [_ _] nil)})

(fn hover-stub []
  {:register (fn [_ _] nil) :unregister (fn [_ _] nil)})

(fn make-ctx []
  (local ptr (assert (pointer-stub) "test pointer stub required"))
  (local hover (assert (hover-stub) "test hover stub required"))
  (BuildContext {:clickables ptr :hoverables hover}))

(fn make-temp-file [name content]
  (local dir (fs.join-path temp-root (.. name "-" (os.time))))
  (when (fs.exists dir) (fs.remove-all dir))
  (fs.create-dirs dir)
  (local path (fs.join-path dir "file.txt"))
  (fs.write-file path content)
  path)

(fn lazy-buffer [name content opts]
  (local chunk-bytes (if (and opts opts.chunk-bytes) opts.chunk-bytes 4))
  (LazyTextBuffer {:source (LazyTextSource.file (make-temp-file name content) {:chunk-bytes chunk-bytes})
                   :chunk-bytes chunk-bytes}))

(fn narrow-layout! [input columns lines]
  (input.layout:measurer)
  (set input.layout.size (glm.vec3 (+ (* 2 input.padding.x) (* columns input.column-width))
                                   (+ (* 2 input.padding.y) (* lines input.line-height)) 0))
  (input.layout:layouter)
  input)

(fn set-test-states []
  (local states (States))
  (states:add-state :normal {})
  (states:add-state :text {})
  (states:set-state :normal)
  (StateSystemBindings.bind-states-host states)
  states)

(fn file-backed-lazy-rows-use-logical-text-and-visual-downward-layout []
  (local content "alpha\nbravo\ncharlie\ndelta")
  (local buffer (lazy-buffer "row-layout" content {:chunk-bytes 4}))
  (local input ((VirtualInput {:buffer buffer :line-count 3 :column-count 8}) (make-ctx)))
  (narrow-layout! input 8 3)
  (local first-row (. input.rows 1)) (local second-row (. input.rows 2)) (local third-row (. input.rows 3))
  (assert (= (codepoints->text (first-row:get-codepoints)) "alpha") "first row should keep lazy logical order")
  (assert (= (codepoints->text (second-row:get-codepoints)) "bravo") "second row should keep lazy logical order")
  (assert (= (codepoints->text (third-row:get-codepoints)) "charlie") "third row should keep lazy logical order")
  (local eager ((Input {:text content :line-count 3 :column-count 8}) (make-ctx)))
  (assert (= (codepoints->text eager.codepoints) content) "eager Input should expose the same logical multiline content")
  (assert (< second-row.layout.position.y first-row.layout.position.y) "second visual row should be below the first row")
  (assert (< third-row.layout.position.y second-row.layout.position.y) "third visual row should be below the second row")
  (set-test-states)
  (input:on-click {:local-point (glm.vec3 (+ input.padding.x (* 0.5 input.column-width))
                                          (+ (- second-row.layout.position.y input.layout.position.y) (* 0.5 input.line-height)) 0)})
  (assert (= input.cursor-line 1) "clicking the visually second lazy row should target logical row 1")
  (eager:drop) (input:drop))

(fn file-backed-caret-mode-matches-eager-input []
  (local buffer (lazy-buffer "caret-mode" "Aardvark\nBee" {:chunk-bytes 4}))
  (local input ((VirtualInput {:buffer buffer :line-count 2 :column-count 8}) (make-ctx)))
  (local eager ((Input {:text "A" :line-count 1 :column-count 8}) (make-ctx)))
  (narrow-layout! input 8 2)
  (eager.layout:measurer) (set eager.layout.size eager.layout.measure) (eager.layout:layouter)
  (local font (assert (and eager.text eager.text.style eager.text.style.font) "caret parity test requires eager font"))
  (local glyph (assert (fallback-glyph font (string.byte "A")) "caret parity test requires glyph A"))
  (local expected-block-width (* glyph.advance eager.text.style.scale))
  (assert (approx input.caret.layout.size.x expected-block-width) "normal mode should use block/glyph caret width")
  (assert (= input.caret.color eager.caret.color) "normal mode should use eager normal caret color")
  (input:enter-insert-mode) (eager:enter-insert-mode) (input.layout:layouter) (eager.layout:layouter)
  (assert (approx input.caret.layout.size.x input.caret-width) "insert mode should use thin caret width")
  (assert (= input.caret.color eager.caret.color) "insert mode should use eager insert caret color")
  (input:enter-normal-mode) (eager:enter-normal-mode) (input.layout:layouter) (eager.layout:layouter)
  (assert (approx input.caret.layout.size.x expected-block-width) "returning to normal should restore block caret width")
  (assert (= input.caret.color eager.caret.color) "returning to normal should restore normal caret color")
  (eager:drop) (input:drop))

[{:name "VirtualInput file-backed lazy rows use logical text and visual downward layout" :fn file-backed-lazy-rows-use-logical-text-and-visual-downward-layout}
 {:name "VirtualInput file-backed caret mode matches eager Input" :fn file-backed-caret-mode-matches-eager-input}]
