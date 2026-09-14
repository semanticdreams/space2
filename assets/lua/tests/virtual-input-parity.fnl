(local _ (require :main))
(local glm (require :glm))
(local BuildContext (require :build-context))
(local Input (require :input))
(local VirtualInput (require :virtual-input))
(local {: FocusManager} (require :focus))
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
  (BuildContext {:clickables ptr
                 :hoverables hover}))

(fn make-focus-ctx []
  (local manager (FocusManager {:root-name "virtual-input-drop-focus"}))
  (local root (manager:get-root-scope))
  (local scope (manager:create-scope {:name "virtual-input-drop-scope"}))
  (manager:attach scope root)
  {:ctx (BuildContext {:focus-manager manager
                       :focus-scope scope
                       :clickables (pointer-stub)
                       :hoverables (hover-stub)})
   :manager manager})

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

(fn file-backed-focus-lifecycle-matches-eager-input []
  (local states (set-test-states))
  (local buffer (lazy-buffer "focus-parity" "alpha\nbravo" {:chunk-bytes 4}))
  (local input ((VirtualInput {:buffer buffer :line-count 2 :column-count 8}) (make-ctx)))
  (local eager ((Input {:text "alpha\nbravo" :multiline? true :line-wrap? false :line-count 2 :column-count 8}) (make-ctx)))
  (narrow-layout! input 8 2)
  (eager.layout:measurer) (set eager.layout.size eager.layout.measure) (eager.layout:layouter)
  (assert (= input.focused? eager.focused?) "VirtualInput should start unfocused like Input")
  (assert (= input.caret.visible? eager.caret.visible?) "unfocused VirtualInput caret should be hidden like Input")
  (input:on-click {:row-index 1 :column 0})
  (input.layout:layouter)
  (assert (= (states:active-name) :text) "click should enter text state")
  (assert input.focused? "click/focus should mark VirtualInput focused")
  (assert input.caret.visible? "focused VirtualInput caret should be visible")
  (input:on-state-disconnected {:state :text})
  (input.layout:layouter)
  (assert (= input.focused? false) "disconnect should clear focused flag")
  (assert (= input.mode :normal) "disconnect should normalize mode")
  (assert (= input.caret.visible? false) "blurred VirtualInput caret should hide")
  (eager:drop) (input:drop))

(fn focused-virtual-input-drop-blurs-before-child-teardown []
  (local focus (make-focus-ctx))
  (local input ((VirtualInput {:buffer (lazy-buffer "drop-focus-order" "alpha" {:chunk-bytes 4}) :line-count 1 :column-count 8}) focus.ctx))
  (set-test-states)
  (narrow-layout! input 8 1)
  (input:request-focus)
  (local original-update input.update-focus-visual)
  (set input.update-focus-visual
       (fn [self opts]
         (assert (not self.__child-drop-started?) "drop should blur before child teardown")
         (original-update self opts)))
  (each [_ row-widget (ipairs input.rows)]
    (local original-drop row-widget.drop)
    (set row-widget.drop (fn [self] (set input.__child-drop-started? true) (original-drop self))))
  (input:drop)
  (focus.manager:drop))

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
  (set-test-states)
  (narrow-layout! input 8 2)
  (eager.layout:measurer) (set eager.layout.size eager.layout.measure) (eager.layout:layouter)
  (eager:request-focus)
  (input:request-focus)
  (input.layout:layouter)
  (eager.layout:layouter)
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

(fn file-backed-caret-visual-update-matches-eager-input []
  (local content "Wombat\nBee")
  (local buffer (lazy-buffer "caret-visual" content {:chunk-bytes 3}))
  (local input ((VirtualInput {:buffer buffer :line-count 2 :column-count 8}) (make-ctx)))
  (local eager ((Input {:text content :multiline? true :line-wrap? false :line-count 2 :column-count 8}) (make-ctx)))
  (set-test-states)
  (narrow-layout! input 8 2)
  (narrow-layout! eager 8 2)
  (eager:move-caret-to 0)
  (eager:request-focus)
  (eager:update-caret-visual {:mark-layout-dirty? false})
  (local expected-focused-visible? eager.caret.visible?)
  (input:request-focus)
  (input:update-caret-visual {:mark-layout-dirty? false})
  (assert (= input.caret.visible? expected-focused-visible?)
          (.. "focused VirtualInput update-caret-visual should unhide like Input; virtual="
              (tostring input.caret.visible?)
              " expected="
              (tostring expected-focused-visible?)
              " focused="
              (tostring input.focused?)))
  (input.layout:layouter)
  (eager.layout:layouter)
  (assert (= input.caret.visible? expected-focused-visible?)
          "focused VirtualInput caret should stay visible after layout like Input")
  (assert (= input.caret.color eager.caret.color)
          "normal caret color should match eager Input")
  (assert (approx input.caret.layout.size.x eager.caret.layout.size.x)
          "normal caret width should match eager Input for the same current glyph")
  (input:enter-insert-mode)
  (eager:enter-insert-mode)
  (input.layout:layouter)
  (eager.layout:layouter)
  (assert (= input.caret.visible? expected-focused-visible?)
          "insert caret visibility should match eager Input")
  (assert (= input.caret.color eager.caret.color)
          "insert caret color should match eager Input")
  (assert (approx input.caret.layout.size.x eager.caret.layout.size.x)
          "insert caret width should match eager Input")
  (input:enter-normal-mode)
  (eager:enter-normal-mode)
  (input.layout:layouter)
  (eager.layout:layouter)
  (assert (= input.caret.color eager.caret.color)
          "restored normal caret color should match eager Input")
  (assert (approx input.caret.layout.size.x eager.caret.layout.size.x)
          "restored normal caret width should match eager Input")
  (input:on-state-disconnected {:state :text})
  (eager:on-state-disconnected {:state :text})
  (input:update-caret-visual {:mark-layout-dirty? false})
  (eager:update-caret-visual {:mark-layout-dirty? false})
  (assert (= input.caret.visible? eager.caret.visible?)
          "blurred VirtualInput update-caret-visual should hide like Input")
  (eager:drop) (input:drop))

[{:name "VirtualInput file-backed lazy rows use logical text and visual downward layout" :fn file-backed-lazy-rows-use-logical-text-and-visual-downward-layout}
 {:name "VirtualInput file-backed focus lifecycle matches eager Input" :fn file-backed-focus-lifecycle-matches-eager-input}
 {:name "VirtualInput focused drop blurs before child teardown" :fn focused-virtual-input-drop-blurs-before-child-teardown}
 {:name "VirtualInput file-backed caret mode matches eager Input" :fn file-backed-caret-mode-matches-eager-input}
 {:name "VirtualInput file-backed caret visual update matches eager Input" :fn file-backed-caret-visual-update-matches-eager-input}]
