(local _ (require :main))
(local glm (require :glm))
(local BuildContext (require :build-context))
(local Input (require :input))
(local VirtualInput (require :virtual-input))
(local TextStyle (require :text-style))
(local {: FocusManager} (require :focus))
(local fs (require :fs))
(local LazyTextSource (require :lazy-text-source))
(local LazyTextBuffer (require :lazy-text-buffer))
(local States (require :states))
(local InputState (require :input-state-router))
(local StateSystemBindings (require :state-system-bindings))
(local {: fallback-glyph} (require :text-utils))
(local Geometry (require :text-input-geometry))
(local MathUtils (require :math-utils))
(local {: LayoutRoot} (require :layout))
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

(fn rooted-input [buffer columns lines]
  (local root (LayoutRoot {:log-dirt? false}))
  (local input ((VirtualInput {:buffer buffer :line-count lines :column-count columns}) (make-ctx)))
  (input.layout:set-root root)
  (narrow-layout! input columns lines)
  {:root root :input input})

(fn caret-local-x [input]
  (- input.caret.layout.position.x input.layout.position.x))

(fn caret-local-y [input]
  (- input.caret.layout.position.y input.layout.position.y))

(fn expected-caret-y [input visible-row]
  (- input.layout.size.y input.padding.y (* visible-row input.line-height)))

(fn assert-near [actual expected message]
  (assert (approx actual expected)
          (.. message "; expected=" (tostring expected) " actual=" (tostring actual))))

(fn snapshot-text [buffer]
  (. (buffer:get-viewport {:line 0 :column 0 :lines 1 :columns 80}) :rows 1 :text))

(fn instrument-lazy-buffer [buffer]
  (assert buffer "instrument-lazy-buffer requires buffer")
  (local state {:viewport-calls []
                :get-line-summary-calls 0
                :line-column-for-byte-calls 0
                :get-line-count-calls 0})
  (local original-get-viewport buffer.get-viewport)
  (local original-get-line-summary buffer.get-line-summary)
  (local original-line-column-for-byte buffer.line-column-for-byte)
  (local original-get-line-count buffer.get-line-count)
  (set buffer.state state)
  (set buffer.get-viewport
       (fn [self view]
         (table.insert state.viewport-calls view)
         (original-get-viewport self view)))
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
  buffer)

(fn reset-lazy-buffer-counters! [buffer]
  (assert buffer.state "reset-lazy-buffer-counters! requires instrumented buffer")
  (set buffer.state.viewport-calls [])
  (set buffer.state.get-line-summary-calls 0)
  (set buffer.state.line-column-for-byte-calls 0)
  (set buffer.state.get-line-count-calls 0))

(fn variable-width-style []
  (fn glyph [advance]
    {:planeBounds {:left 0 :right advance :bottom -0.2 :top 0.8}
     :atlasBounds {:left 0 :right 10 :bottom 0 :top 10}
     :advance advance})
  (local fallback (glyph 0.6))
  (TextStyle {:scale 1.0
              :font {:glyph-map {32 fallback
                                  87 (glyph 1.0)
                                  105 (glyph 0.2)
                                  97 (glyph 0.6)
                                  98 (glyph 0.6)
                                  99 (glyph 0.6)
                                  100 (glyph 0.6)
                                  101 (glyph 0.6)
                                  102 (glyph 0.6)
                                  103 (glyph 0.6)
                                  104 (glyph 0.6)
                                  65533 fallback}
                     :metadata {:metrics {:lineHeight 1.0
                                           :ascender 0.8
                                           :descender -0.2}
                                :atlas {:width 64 :height 64 :distanceRange 4}}
                     :texture {:id 1 :ready true}}}))

(fn layout-caret-parity-inputs [content line column]
  (local style (variable-width-style))
  (local buffer (lazy-buffer (.. "variable-caret-" (tostring line) "-" (tostring column)) content {:chunk-bytes 4}))
  (local input ((VirtualInput {:buffer buffer :line-count 2 :column-count 8 :text-style style}) (make-ctx)))
  (local eager ((Input {:text content :multiline? true :line-wrap? false :line-count 2 :column-count 8 :text-style style}) (make-ctx)))
  (narrow-layout! input 8 2)
  (narrow-layout! eager 8 2)
  (eager:request-focus)
  (input:request-focus)
  (var eager-index column)
  (each [idx cp (utf8.codes content)]
    (when (and (> line 0) (= cp (string.byte "\n")) (<= idx (length content)))
      (set eager-index (+ idx column))))
  (eager:move-caret-to eager-index)
  (input:move-caret-to-line-column line column)
  (input.layout:layouter)
  (eager.layout:layouter)
  {:input input :eager eager})

(fn assert-caret-x-parity [content column message]
  (local pair (layout-caret-parity-inputs content 0 column))
  (local virtual-x pair.input.caret.layout.position.x)
  (local eager-x pair.eager.caret.layout.position.x)
  (assert (approx virtual-x eager-x)
          (.. message "; virtual x=" (tostring virtual-x) " eager x=" (tostring eager-x)))
  (pair.eager:drop)
  (pair.input:drop))

(fn variable-width-caret-x-matches-eager-input []
  (assert-caret-x-parity "iiiiWWWW" 4 "VirtualInput caret x should sum narrow glyph advances before wide glyphs")
  (assert-caret-x-parity "WWWWiiii" 4 "VirtualInput caret x should sum wide glyph advances before narrow glyphs"))

(fn multiline-caret-y-still-matches-eager-input []
  (local pair (layout-caret-parity-inputs "abcd\nefgh" 1 2))
  (local virtual-y pair.input.caret.layout.position.y)
  (local eager-y pair.eager.caret.layout.position.y)
  (assert (approx virtual-y eager-y)
          (.. "VirtualInput multiline caret y should match eager Input; virtual y=" (tostring virtual-y) " eager y=" (tostring eager-y)))
  (pair.eager:drop)
  (pair.input:drop))

(fn ascii-row [line text start-column visible-columns]
  (assert (= (type start-column) :number) "ascii-row requires start-column")
  (assert (= (type visible-columns) :number) "ascii-row requires visible-columns")
  (local start (math.max 0 start-column))
  (local columns (math.max 0 visible-columns))
  (local codepoints [])
  (local offsets [0])
  (for [column start (- (+ start columns) 1)]
    (local byte-index (+ column 1))
    (when (<= byte-index (# text))
      (table.insert codepoints (string.byte text byte-index))
      (table.insert offsets (length codepoints))))
  {:line line
   :start-column start
   :start-byte start
   :end-byte (+ start (length codepoints))
   :line-end-byte (# text)
   :line-end-known? true
   :newline-bytes 0
   :text (string.sub text (+ start 1) (+ start (length codepoints)))
   :codepoints codepoints
   :column-byte-offsets offsets})

(fn anchored-start-column-buffer [text start-column visible-columns]
  (local row (ascii-row 0 text start-column visible-columns))
  (local state {:viewport-calls []})
  {:cursor-byte 0
   :scroll-line 0
   :state state
   :get-viewport (fn [_self view]
                   (table.insert state.viewport-calls view)
                   {:start-line 0
                    :start-column 0
                    :requested-lines view.lines
                    :requested-columns view.columns
                    :rows [row]})
   :line-column-for-byte (fn [_self byte]
                           (assert (= (type byte) :number) "test buffer line-column-for-byte requires byte")
                           (values 0 (math.max 0 byte) true))
   :get-line-count (fn [_self] 1)
   :get-line-summary (fn [_self _line]
                       {:codepoint-count (# text)
                        :first-nonblank-column 0})
   :move-caret-to-line-column (fn [self _line column]
                                (set self.cursor-byte (math.max 0 column))
                                true)})

(fn anchored-row-start-column-is-caret-visible-base []
  (local style (variable-width-style))
  (local buffer (anchored-start-column-buffer "iiiiWWWW" 4 4))
  (local input ((VirtualInput {:buffer buffer :line-count 1 :column-count 4 :text-style style}) (make-ctx)))
  (narrow-layout! input 4 1)
  (input:request-focus)
  (input:move-caret-to-line-column 0 6)
  (input.layout:layouter)
  (local row (. input.viewport.rows 1))
  (assert (= input.scroll-column 0) "test precondition: viewport requested/global scroll column stays 0")
  (assert (= row.start-column 4) "test precondition: row start-column is the authoritative visible base")
  (assert input.caret.visible? "caret at logical column 6 should remain visible within row columns 4..8")
  (assert (approx input.caret.layout.position.x (+ input.padding.x 2.0))
          (.. "caret x should use row.start-column base; x=" (tostring input.caret.layout.position.x)))
  (assert (approx input.caret.layout.size.x 1.0)
          (.. "normal-mode block caret width should use row.start-column glyph; width=" (tostring input.caret.layout.size.x)))
  (input:drop))

(fn assert-viewport-calls-bounded [buffer max-lines max-columns message]
  (each [i view (ipairs (or (and buffer.state buffer.state.viewport-calls) []))]
    (assert (<= view.lines max-lines)
            (.. message ": viewport call " i " requested too many lines: " view.lines))
    (assert (<= view.columns max-columns)
            (.. message ": viewport call " i " requested too many columns: " view.columns))))

(fn assert-logical-scans-bounded [buffer max-calls message]
  (assert (<= buffer.state.get-line-summary-calls max-calls)
          (.. message ": get-line-summary calls should stay bounded; calls=" buffer.state.get-line-summary-calls))
  (assert (<= buffer.state.line-column-for-byte-calls max-calls)
          (.. message ": line-column-for-byte calls should stay bounded; calls=" buffer.state.line-column-for-byte-calls))
  (assert (<= buffer.state.get-line-count-calls max-calls)
          (.. message ": get-line-count calls should stay bounded; calls=" buffer.state.get-line-count-calls)))

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

(fn count-router-disconnects [input activate]
  (local original-disconnected input.on-state-disconnected)
  (var disconnected-count 0)
  (set input.on-state-disconnected
       (fn [self event]
         (set disconnected-count (+ disconnected-count 1))
         (original-disconnected self event)))
  (activate input)
  (assert (= (InputState.active-input) input) "focused input should be router-active")
  (InputState.disconnect-input input)
  disconnected-count)

(fn router-disconnect-invokes-shared-policy-users-once []
  (set-test-states)
  (local focus (make-focus-ctx))
  (local eager ((Input {}) focus.ctx))
  (local virtual ((VirtualInput {:buffer (lazy-buffer "disconnect-once" "abc" {:chunk-bytes 4})
                                :line-count 1
                                :column-count 8}) (make-ctx)))
  (local eager-count (count-router-disconnects eager (fn [input] (input:request-focus))))
  (local virtual-count (count-router-disconnects virtual (fn [input] (input:on-click {:row-index 1 :column 0}))))
  (assert (= eager-count 1)
          (.. "router disconnect should invoke Input on-state-disconnected once, got " eager-count))
  (assert (= virtual-count 1)
          (.. "router disconnect should invoke VirtualInput on-state-disconnected once, got " virtual-count))
  (assert (not (InputState.active-input)) "router disconnect should clear active input")
  (eager:drop)
  (virtual:drop)
  (focus.manager:drop))

(fn active-drop-invokes-router-disconnect-once-with-states-host []
  (set-test-states)
  (local focus (make-focus-ctx))
  (local input ((Input {}) focus.ctx))
  (local original-disconnected input.on-state-disconnected)
  (var disconnected-count 0)
  (set input.on-state-disconnected
       (fn [self event]
         (set disconnected-count (+ disconnected-count 1))
         (original-disconnected self event)))
  (input:request-focus)
  (assert (= (InputState.active-input) input) "precondition: Input should be active before drop")
  (input:drop)
  (assert (= disconnected-count 1)
          (.. "active Input drop should invoke one router disconnect callback, got " disconnected-count))
  (assert (not (InputState.active-input)) "active Input drop should clear router active input")
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

(fn root-update-after-focus-lays-out-caret []
  (local env (rooted-input (lazy-buffer "root-focus-caret" "alpha\nbeta" {:chunk-bytes 4}) 6 2))
  (local input env.input)
  (input:request-focus)
  (env.root:update)
  (assert input.caret.visible? "root update after focus should show VirtualInput caret")
  (assert (> input.caret.layout.size.x 0) "root update after focus should give caret nonzero width")
  (assert (> input.caret.layout.size.y 0) "root update after focus should give caret nonzero height")
  (assert-near (caret-local-x input) input.padding.x "focused caret x should match column zero")
  (assert-near (caret-local-y input) (expected-caret-y input 1) "focused caret y should match first row")
  (input:drop))

(fn root-update-after-insert-mode-lays-out-thin-caret []
  (local env (rooted-input (lazy-buffer "root-mode-caret" "alpha\nbeta" {:chunk-bytes 4}) 6 2))
  (local input env.input)
  (input:request-focus)
  (input.layout:layouter)
  (local normal-width input.caret.layout.size.x)
  (input:enter-insert-mode)
  (env.root:update)
  (assert (> normal-width input.caret-width) "normal caret should start as a block")
  (assert-near input.caret.layout.size.x input.caret-width "root update after insert mode should apply thin caret width")
  (input:drop))

(fn root-update-after-cursor-move-lays-out-caret-position []
  (local env (rooted-input (lazy-buffer "root-move-caret" "alpha\nbeta" {:chunk-bytes 4}) 6 2))
  (local input env.input)
  (input:request-focus)
  (input.layout:layouter)
  (assert (input:move-caret-to-line-column 1 2) "precondition: caret move should succeed")
  (env.root:update)
  (assert-near (caret-local-x input) (+ input.padding.x (* 2 input.column-width)) "root update after move should place caret at column two")
  (assert-near (caret-local-y input) (expected-caret-y input 2) "root update after move should place caret on second row")
  (input:drop))

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

(fn direct-normal-edit-keys-do-not-edit []
  (local buffer (lazy-buffer "direct-normal-gate" "abc\ndef" {:chunk-bytes 4}))
  (local input ((VirtualInput {:buffer buffer :line-count 2 :column-count 8}) (make-ctx)))
  (narrow-layout! input 8 2)
  (local before (snapshot-text buffer))
  (assert (= input.mode :normal) "precondition: VirtualInput should start in normal mode")
  (assert (= (input:on-key-down {:key 8}) false) "direct Backspace should not edit in normal mode")
  (assert (= (input:on-key-down {:key 127}) false) "direct Delete should not edit in normal mode")
  (assert (= (input:on-key-down {:key 13}) false) "direct Return should not insert newline in normal mode")
  (assert (= (snapshot-text buffer) before) "normal-mode direct edit keys should not mutate lazy text")
  (input:drop))

(fn direct-normal-arrows-do-not-move-caret []
  (local buffer (lazy-buffer "direct-normal-arrows" "abc\ndef" {:chunk-bytes 4}))
  (local input ((VirtualInput {:buffer buffer :line-count 2 :column-count 8}) (make-ctx)))
  (narrow-layout! input 8 2)
  (input:move-caret-to-line-column 0 1)
  (local before-byte buffer.cursor-byte)
  (local before-line input.cursor-line)
  (local before-column input.cursor-column)
  (assert (= (input:on-key-down {:key 1073741904}) false) "direct Left should not move in normal mode")
  (assert (= (input:on-key-down {:key 1073741903}) false) "direct Right should not move in normal mode")
  (assert (= (input:on-key-down {:key 1073741906}) false) "direct Up should not move in normal mode")
  (assert (= (input:on-key-down {:key 1073741905}) false) "direct Down should not move in normal mode")
  (assert (= buffer.cursor-byte before-byte) "normal-mode direct arrows should not move buffer cursor")
  (assert (= input.cursor-line before-line) "normal-mode direct arrows should not change cursor line")
  (assert (= input.cursor-column before-column) "normal-mode direct arrows should not change cursor column")
  (input:drop))

(fn large-file-geometry-and-horizontal-scroll-stay-lazy []
  (local long-line (string.rep "a" 100000))
  (local content (.. "top\n" long-line "\ntail"))
  (local buffer (instrument-lazy-buffer (lazy-buffer "large-geometry" content {:chunk-bytes 16})))
  (local input ((VirtualInput {:buffer buffer :line-count 3 :column-count 4}) (make-ctx)))
  (set-test-states)
  (narrow-layout! input 4 3)
  (local first-row (. input.rows 1))
  (local second-row (. input.rows 2))
  (local third-row (. input.rows 3))
  (assert (= (codepoints->text (first-row:get-codepoints)) "top")
          "large lazy viewport should render the first logical row first")
  (assert (= (codepoints->text (second-row:get-codepoints)) "aaaa")
          "large lazy viewport should render only the visible slice of the long row")
  (assert (< third-row.layout.position.y second-row.layout.position.y)
          "large lazy viewport should preserve downward row order after the long row")
  (local world (Geometry.screen-point-for-row-column input 2 2))
  (input:on-click {:local-point (- world input.layout.position)})
  (assert (= input.cursor-line 1) "geometry click should target the long lazy row")
  (assert (= input.cursor-column 2) "geometry click should target the requested visible column")
  (input.layout:layouter)
  (assert (= input.caret.layout.position.y second-row.layout.position.y)
          "caret y should align with the clicked row widget")
  (reset-lazy-buffer-counters! buffer)
  (for [_ 1 8]
    (assert (input:move-caret-horizontal-bounded 1 {:allow-line-cross? true})
            "bounded horizontal movement should handle repeated l-style moves")
    (input.layout:layouter))
  (assert (> input.scroll-column 0)
          "repeated horizontal movement should scroll the large lazy row")
  (assert-viewport-calls-bounded buffer input.visible-line-count input.visible-column-count
                                 "large-file geometry/horizontal scroll")
  (assert-logical-scans-bounded buffer 1 "large-file geometry/horizontal scroll")
  (input:drop))

(fn rotated-layout-click-point-targets-shared-geometry-cell []
  (local buffer (lazy-buffer "rotated-geometry" "alpha\nbravo\ncharlie" {:chunk-bytes 4}))
  (local input ((VirtualInput {:buffer buffer :line-count 3 :column-count 8}) (make-ctx)))
  (set-test-states)
  (narrow-layout! input 8 3)
  (set input.layout.position (glm.vec3 7 11 0))
  (set input.layout.rotation (glm.quat (math.rad 90) (glm.vec3 0 0 1)))
  (input.layout:layouter)
  (local point (Geometry.screen-point-for-row-column input 2 3))
  (input:on-click {:point point})
  (assert (= input.cursor-line 1)
          "rotated event.point click should target the second logical row")
  (assert (= input.cursor-column 3)
          "rotated event.point click should target the requested column")
  (input:drop))

[{:name "VirtualInput file-backed lazy rows use logical text and visual downward layout" :fn file-backed-lazy-rows-use-logical-text-and-visual-downward-layout}
 {:name "VirtualInput file-backed focus lifecycle matches eager Input" :fn file-backed-focus-lifecycle-matches-eager-input}
 {:name "VirtualInput focused drop blurs before child teardown" :fn focused-virtual-input-drop-blurs-before-child-teardown}
 {:name "Text input shared policy router disconnect invokes state disconnected once" :fn router-disconnect-invokes-shared-policy-users-once}
 {:name "Text input active drop invokes router disconnect once with states host" :fn active-drop-invokes-router-disconnect-once-with-states-host}
  {:name "VirtualInput file-backed caret mode matches eager Input" :fn file-backed-caret-mode-matches-eager-input}
   {:name "VirtualInput variable-width caret x matches eager Input" :fn variable-width-caret-x-matches-eager-input}
   {:name "VirtualInput multiline caret y still matches eager Input" :fn multiline-caret-y-still-matches-eager-input}
   {:name "VirtualInput anchored row start-column is caret visible base" :fn anchored-row-start-column-is-caret-visible-base}
   {:name "VirtualInput root update after focus lays out caret" :fn root-update-after-focus-lays-out-caret}
   {:name "VirtualInput root update after insert mode lays out thin caret" :fn root-update-after-insert-mode-lays-out-thin-caret}
   {:name "VirtualInput root update after cursor move lays out caret position" :fn root-update-after-cursor-move-lays-out-caret-position}
   {:name "VirtualInput file-backed caret visual update matches eager Input" :fn file-backed-caret-visual-update-matches-eager-input}
  {:name "VirtualInput direct normal edit keys do not edit" :fn direct-normal-edit-keys-do-not-edit}
  {:name "VirtualInput direct normal arrows do not move caret" :fn direct-normal-arrows-do-not-move-caret}
  {:name "VirtualInput large-file geometry and horizontal scroll stay lazy" :fn large-file-geometry-and-horizontal-scroll-stay-lazy}
  {:name "VirtualInput rotated layout click point targets shared geometry cell" :fn rotated-layout-click-point-targets-shared-geometry-cell}]
