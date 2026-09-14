(local glm (require :glm))
(local Rectangle (require :rectangle))
(local Text (require :text))
(local TextStyle (require :text-style))
(local InputModel (require :input-model))
(local Signal (require :signal))
(local colors (require :colors))
(local gl (require :gl))
(local {: Layout : resolve-mark-flag : finite-constraint?} (require :layout))
(local {: fallback-glyph
        : newline-codepoint} (require :text-utils))
(local FocusPolicy (require :text-input-focus-policy))
(local CaretPolicy (require :text-input-caret-policy))
(local ExternalEditor (require :external-editor))
(local {: resolve-input-colors
        : resolve-padding} (require :widget-theme-utils))

(fn standard-context-menu [input _event]
  [{:name "Copy"
    :fn (fn [_button _event]
          (local content (input:get-text))
          (gl.clipboard-set content))}
   {:name "Paste"
    :fn (fn [_button _event]
          (local value (gl.clipboard-get))
          (input:insert-text value))}
   {:name "Clear"
    :fn (fn [_button _event]
          (input:set-text ""))}])

(fn Input [opts]
  (local options (or opts {}))
  (local padding (resolve-padding options.padding))
  (local caret-width (or options.caret-width 0.05))
  (local min-width (or options.min-width 5.0))
  (local min-height (or options.min-height 1.6))
  (local placeholder-text (or options.placeholder ""))
  (local multiline? (and (= options.multiline? true)))
  (local line-wrap? (if (= options.line-wrap? nil)
                       (and multiline? true)
                       (and (= options.line-wrap? true))))
  (when (and line-wrap? (not multiline?))
    (error "line-wrap? requires multiline? to be enabled"))
  (local explicit-line-count (if multiline?
                               options.line-count
                               1))
  (local resolved-min-lines
    (let [fallback (if multiline?
                       (or options.min-lines 1)
                       1)]
      (or explicit-line-count fallback)))
  (local resolved-max-lines
    (let [fallback (if multiline?
                       (or options.max-lines math.huge)
                       1)]
      (math.max resolved-min-lines (or explicit-line-count fallback))))
  (local explicit-column-count options.column-count)
  (local resolved-min-columns
    (or explicit-column-count
        (math.max 1 (or options.min-columns 1))))
  (local resolved-max-columns
    (let [fallback (or options.max-columns math.huge)]
      (math.max resolved-min-columns (or explicit-column-count fallback))))

  (fn build [ctx]
    (local model (InputModel {:text options.text}))
    (local colors (resolve-input-colors ctx options))
    (local focus-context (and ctx ctx.focus))
    (local focusable? (and focus-context (not (= options.focusable? false))))
    (local focus-node
      (and focusable?
           (focus-context:create-node {:name (or options.focus-name
                                                 options.name
                                                 "input")})))
    (local focus-manager (and focus-node focus-node.manager))
    (local focus-outline ((Rectangle {:color colors.focus-outline}) ctx))
    (focus-outline:set-visible false {:mark-layout-dirty? false})
    (local background ((Rectangle {:color colors.background}) ctx))
    (local caret ((Rectangle {:color colors.caret-normal}) ctx))
    (caret:set-visible false {:mark-layout-dirty? false})
    (local text-style
      (or options.text-style
          (TextStyle {:color colors.foreground})))
    (local text ((Text {:text (or options.text "")
                        :style text-style}) ctx))
    (local placeholder-style
      (TextStyle {:color colors.placeholder
                  :font text-style.font
                  :scale text-style.scale}))
    (local placeholder ((Text {:text placeholder-text
                               :style placeholder-style}) ctx))
    (local computed-line-height
      (CaretPolicy.resolve-line-height text-style min-height))
    (local computed-column-width
      (CaretPolicy.resolve-column-width text-style caret-width))
    (var layout nil)
    (local pointer-target (and ctx ctx.pointer-target))
    (local clickables (assert ctx.clickables "Input requires ctx.clickables"))
    (local hoverables (assert ctx.hoverables "Input requires ctx.hoverables"))
    (local system-cursors (and ctx ctx.system-cursors))
    (fn get-menu-manager []
      (or (and ctx ctx.menu-manager) app.menu-manager))
    (local initial-visible-lines (or explicit-line-count resolved-min-lines))
  (local initial-visible-columns (or explicit-column-count resolved-min-columns))
  (var input nil)
  (set input {:__dropped false})
  (model:set-viewport-lines initial-visible-lines)
  (model:set-viewport-columns initial-visible-columns)

  (fn glyph-advance [style codepoint]
    (local font (and style style.font))
    (if (not font)
        0
        (let [glyph (fallback-glyph font codepoint)]
            (if (and glyph glyph.advance)
                (* glyph.advance style.scale)
                0))))

  (fn mark-virtual-dirty [self opts]
    (set self.virtual-dirty? true)
    (set self.visual-rows-dirty? true)
    (local mark-measure-dirty? (resolve-mark-flag opts :mark-measure-dirty? true))
    (when (and mark-measure-dirty? self.text self.text.layout)
      (self.text.layout:mark-measure-dirty)))

    ;; ---- line-wrap helpers ----

    (fn compute-visual-rows [self max-width]
      (local style self.text.style)
      (local visual-rows [])
      (local total-lines (length self.model.lines))
      (for [li 0 (- total-lines 1)]
        (local line (. self.model.lines (+ li 1)))
        (local codepoints (or line.codepoints []))
        (local len (length codepoints))
        (var col 0)
        (var row-start 0)
        (var row-width 0.0)
        (while (< col len)
          (local cp (. codepoints (+ col 1)))
          (local advance (glyph-advance style cp))
          (when (and (> max-width 0.0) (> col row-start) (> (+ row-width advance) max-width))
            (table.insert visual-rows {:line-index li :start-col row-start :end-col col})
            (set row-start col)
            (set row-width 0.0))
          (set row-width (+ row-width advance))
          (set col (+ col 1)))
        (table.insert visual-rows {:line-index li :start-col row-start :end-col col}))
      visual-rows)

    (fn ensure-visual-rows [self]
      (when (and self.line-wrap? self.visual-rows-dirty?)
        (set self.visual-rows-dirty? false)
        (local max-width (or (and self.inner-size self.inner-size.x) 0))
        (set self.visual-rows (compute-visual-rows self max-width))))

    (fn caret-visual-row-index [self]
      (local visual-rows (or self.visual-rows []))
      (local cursor-line self.model.cursor-line)
      (local cursor-column self.model.cursor-column)
      (var first nil)
      (var last nil)
      (for [i 0 (- (length visual-rows) 1)]
        (local vr (. visual-rows (+ i 1)))
        (when (= vr.line-index cursor-line)
          (when (not first) (set first i))
          (set last i)))
      (if (not first)
          0
          (do
            (local line (. self.model.lines (+ cursor-line 1)))
            (local line-len (length (or line.codepoints [])))
            (if (>= cursor-column line-len)
                last
                (do
                  (var found first)
                  (for [i first last]
                    (local vr (. visual-rows (+ i 1)))
                    (when (and (>= cursor-column vr.start-col)
                               (< cursor-column vr.end-col))
                      (set found i)))
                  found)))))

    (fn wrapped-visible-codepoints [self]
      (ensure-visual-rows self)
      (local visual-rows self.visual-rows)
      (local viewport-lines (math.max 1 (or self.visible-line-count 0)))
      (local newline newline-codepoint)
      (var buffer [])
      (var drawn 0)
      (local start-row (math.max 0 (or self.scroll.line 0)))
      (var vi start-row)
      (while (and (< drawn viewport-lines) (< vi (length visual-rows)))
        (when (> drawn 0)
          (table.insert buffer newline))
        (local vr (. visual-rows (+ vi 1)))
        (when vr
          (local line (. self.model.lines (+ vr.line-index 1)))
          (when (and line line.codepoints)
            (for [col vr.start-col (- vr.end-col 1)]
              (local cp (. line.codepoints (+ col 1)))
              (when cp
                (table.insert buffer cp)))))
        (set vi (+ vi 1))
        (set drawn (+ drawn 1)))
      buffer)

    (fn caret-x-offset-in-wrapped-line [self]
      (ensure-visual-rows self)
      (local vr-index (caret-visual-row-index self))
      (local visual-rows self.visual-rows)
      (local vr (. visual-rows (+ vr-index 1)))
      (if (not vr)
          0
          (do
            (local line (. self.model.lines (+ vr.line-index 1)))
            (if (not (and line line.codepoints))
                0
                (do
                  (local cursor-column self.model.cursor-column)
                  (var width 0.0)
                  (local style self.text.style)
                  (for [col vr.start-col (- (math.min cursor-column (length line.codepoints)) 1)]
                    (local cp (. line.codepoints (+ col 1)))
                    (when cp
                      (set width (+ width (glyph-advance style cp)))))
                  width)))))

    ;; ---- end line-wrap helpers ----

    (fn sync-viewport-state [self]
      (set self.lines self.model.lines)
      (set self.cursor-line self.model.cursor-line)
      (set self.cursor-column self.model.cursor-column)
      (when (not self.scroll)
        (set self.scroll {:line 0 :column 0}))
      (if self.line-wrap?
          (do
            (set self.scroll.column 0)
            (ensure-visual-rows self)
            (local visual-rows self.visual-rows)
            (local total-visual (length visual-rows))
            (local viewport-lines (math.max 1 self.model.viewport-lines))
            (set self.scroll.line (math.max 0 (math.min (or self.scroll.line 0) (math.max 0 (- total-visual viewport-lines)))))
            (local caret-vr (caret-visual-row-index self))
            (when (not self.explicit-scroll?)
              (when (< caret-vr self.scroll.line)
                (set self.scroll.line caret-vr))
              (when (>= caret-vr (+ self.scroll.line viewport-lines))
                (set self.scroll.line (math.max 0 (- caret-vr (- viewport-lines 1))))))
            (set self.prev-cursor-line self.cursor-line)
            (set self.prev-cursor-column self.cursor-column)
            (local vr (. visual-rows (+ self.scroll.line 1)))
            (when vr
              (set self.model.scroll-line vr.line-index)))
          (do
            (set self.scroll.line self.model.scroll-line)
            (set self.scroll.column self.model.scroll-column)))
      (set self.visible-line-count self.model.viewport-lines)
      (set self.visible-column-count self.model.viewport-columns))

    (fn refresh-virtual-text [self force?]
      (when (and self.text (or self.virtual-dirty? force?))
        (set self.virtual-dirty? false)
        (local codepoints
          (if self.line-wrap?
              (wrapped-visible-codepoints self)
              (self.model:get-visible-codepoints)))
        (self.text:set-codepoints codepoints {:mark-measure-dirty? false})
        true))

    (fn resolve-line-count [self inner-height]
      (if self.explicit-line-count
          self.explicit-line-count
          (let [line-height (math.max (or self.line-height 0) 0.0001)
                available (or inner-height 0)
                computed (if (> line-height 0)
                             (math.max 1 (math.floor (/ available line-height)))
                             1)]
            (math.max 1 (math.min self.max-lines computed)))))

    (fn resolve-column-count [self inner-width]
      (if self.explicit-column-count
          self.explicit-column-count
          (let [column-width (math.max (or self.column-width 0) 0.0001)
                available (or inner-width 0)
                computed (if (> column-width 0)
                             (math.max 1 (math.floor (/ available column-width)))
                             1)]
            (math.max 1 (math.min self.max-columns computed)))))

    (fn apply-viewport [self inner-size]
      (local next-lines (resolve-line-count self inner-size.y))
      (local next-columns
        (if self.line-wrap?
            (or self.model.longest-line-length (length self.model.codepoints) 1)
            (resolve-column-count self inner-size.x)))
      (var changed? false)
      (when (self.model:set-viewport-lines next-lines)
        (set changed? true))
      (when (self.model:set-viewport-columns next-columns)
        (set changed? true))
      (when changed?
        (mark-virtual-dirty self {:mark-measure-dirty? false})))

    (fn text-measure-height [self fallback]
      (local measure (and self.text self.text.layout self.text.layout.measure))
      (or (and measure measure.y) fallback 0))

    (fn text-block-offset [self inner-height]
      (local text-height (text-measure-height self inner-height))
      (local extra-height (math.max 0 (- inner-height text-height)))
      (if self.multiline?
          extra-height
          (/ extra-height 2)))

    (fn caret-vertical-offset [self]
      (if self.line-wrap?
          (do
            (ensure-visual-rows self)
            (local caret-vr (caret-visual-row-index self))
            (local relative (- caret-vr (or self.scroll.line 0)))
            (local inner-height (or (and self.inner-size self.inner-size.y) 0))
            (local lh (math.max 0 (or self.line-height 0)))
            (local text-height (text-measure-height self inner-height))
            (local offset-top (+ self.padding.y
                                 (text-block-offset self inner-height)
                                 (math.max 0 (- text-height lh))))
            (- offset-top (* relative lh)))
          (do
            (local relative (- (or self.model.cursor-line 0)
                               (or self.model.scroll-line 0)))
            (local inner-height (or (and self.inner-size self.inner-size.y) 0))
            (local lh (math.max 0 (or self.line-height 0)))
            (local text-height (text-measure-height self inner-height))
            (local offset-top (+ self.padding.y
                                  (text-block-offset self inner-height)
                                  (math.max 0 (- text-height lh))))
            (- offset-top (* (math.max 0 relative) lh)))))

    (fn cursor-prefix-width [self]
      (if self.line-wrap?
          (caret-x-offset-in-wrapped-line self)
          (let [lines (or self.model.lines [])
                line (. lines (+ self.model.cursor-line 1))]
            (if (not (and line line.codepoints))
                0
                (let [start (math.max 0 (or self.model.scroll-column 0))
                      stop (math.max 0 (or self.model.cursor-column 0))]
                  (if (< stop start)
                      0
                      (do
                        (var width 0)
                        (var column start)
                        (local style self.text.style)
                        (while (< column stop)
                          (local codepoint (. line.codepoints (+ column 1)))
                          (when codepoint
                            (set width (+ width (glyph-advance style codepoint))))
                          (set column (+ column 1)))
                        width)))))))

    (fn caret-width-for-mode [self]
      (CaretPolicy.mode-caret-width self.text.style
                                    (. self.codepoints (+ self.cursor-index 1))
                                    self.caret-width
                                    self.mode))

    (fn caret-height-for-inner [self inner-height]
      (CaretPolicy.caret-height self.line-height inner-height))

    (fn update-caret-layout [self opts]
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? true))
      (when (and self.caret self.layout self.inner-size)
        (local rotation (or self.layout.rotation (glm.quat 1 0 0 0)))
        (local position (or self.layout.position (glm.vec3 0 0 0)))
        (local clip self.layout.clip-region)
        (local depth-index (or self.layout.depth-offset-index 0))
        (local size (or self.layout.size self.layout.measure))
        (local inner-height (or self.inner-size.y 0))
        (local caret-depth (+ depth-index 2))
        (local prefix (self:cursor-prefix-width))
        (local x-offset (+ self.padding.x prefix))
        (local caret-y (caret-vertical-offset self))
        (local caret-height (caret-height-for-inner self inner-height))
        (local caret-position (+ position (rotation:rotate (glm.vec3 x-offset caret-y 0))))
        (set self.caret.layout.size (glm.vec3 (caret-width-for-mode self) caret-height size.z))
        (set self.caret.layout.position caret-position)
        (set self.caret.layout.rotation rotation)
        (set self.caret.layout.depth-offset-index caret-depth)
        (set self.caret.layout.clip-region clip)
        (when mark-layout-dirty?
          (self.caret.layout:mark-layout-dirty))))

    (fn update-placeholder [self opts]
      (local mark-measure-dirty? (resolve-mark-flag opts :mark-measure-dirty? true))
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? false))
      (if (> (length self.codepoints) 0)
          (self.placeholder:set-text ""
                                     {:mark-measure-dirty? mark-measure-dirty?
                                      })
          (self.placeholder:set-text placeholder-text
                                     {:mark-measure-dirty? mark-measure-dirty?
                                      })))

    (fn sync-from-model [self]
      (set self.explicit-scroll? false)
      (set self.codepoints model.codepoints)
      (set self.cursor-index model.cursor-index)
      (set self.mode model.mode)
      (set self.connected? model.connected?)
      (sync-viewport-state self))

    (fn apply-text-change [self notify? opts]
      (local mark-measure-dirty? (resolve-mark-flag opts :mark-measure-dirty? true))
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? true))
      (when notify?
        (set self.caret-explicitly-positioned? true))
      (set self.visual-rows-dirty? true)
      (sync-from-model self)
      (mark-virtual-dirty self {:mark-measure-dirty? mark-measure-dirty?})
      (update-placeholder self {:mark-measure-dirty? mark-measure-dirty?})
      (when (and mark-measure-dirty? self.layout)
        (self.layout:mark-measure-dirty))
      (self:update-caret-visual {:mark-layout-dirty? mark-layout-dirty?})
      (update-caret-layout self {:mark-layout-dirty? mark-layout-dirty?})
      (refresh-virtual-text self true)
      (when (and notify? options.on-change)
        (options.on-change self (self:get-text))))

    (fn apply-caret-change [self opts]
      (set self.caret-explicitly-positioned? true)
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? true))
      (local mark-measure-dirty? (resolve-mark-flag opts :mark-measure-dirty? false))
      (local prev-scroll-line (or (and self.scroll self.scroll.line) 0))
      (local prev-scroll-column (or (and self.scroll self.scroll.column) 0))
      (local prev-cursor-line (or self.cursor-line 0))
      (local prev-cursor-column (or self.cursor-column 0))
      (local prev-cursor-index (or self.cursor-index 0))
      (sync-from-model self)
      (local scroll-changed?
        (or (not (= prev-scroll-line self.scroll.line))
            (not (= prev-scroll-column self.scroll.column))))
      (local caret-moved?
        (or (not (= prev-cursor-line self.cursor-line))
            (not (= prev-cursor-column self.cursor-column))
            (not (= prev-cursor-index self.cursor-index))))
      (when scroll-changed?
        (mark-virtual-dirty self {:mark-measure-dirty? mark-measure-dirty?})
        (refresh-virtual-text self true)
        (when self.text.layout
          (self.text.layout:mark-layout-dirty)))
      (self:update-caret-visual {:mark-layout-dirty? mark-layout-dirty?})
      (when (or caret-moved? scroll-changed? mark-layout-dirty?)
        (update-caret-layout self {:mark-layout-dirty? mark-layout-dirty?})))

    (fn apply-mode-change [self opts]
      (apply-caret-change self opts))

    (fn update-caret-visual [self opts]
      (CaretPolicy.apply-caret-visual self opts))

    (fn update-focus-visual [self opts]
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? true))
      (local overlay self.focus-overlay)
      (when overlay
        (overlay:set-visible self.focused? {:mark-layout-dirty? mark-layout-dirty?}))
      (self:update-caret-visual {:mark-layout-dirty? mark-layout-dirty?})
      (self:update-background {:mark-layout-dirty? mark-layout-dirty?}))

    (fn update-background [self opts]
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? true))
      (local rect self.background)
      (when rect
        (local color
          (if self.focused?
              self.colors.focused-background
              (if self.hovered?
                  self.colors.hover-background
                  self.colors.background)))
        (set rect.color color)
        (when (and mark-layout-dirty? rect.layout)
          (rect.layout:mark-layout-dirty))))

    (fn sync-placeholder [self]
      (update-placeholder self))

    (fn measure-input [self layout]
      (refresh-virtual-text self)
      (self.text.layout:measurer)
      (self.placeholder.layout:measurer)
      (local text-measure self.text.layout.measure)
      (local placeholder-measure self.placeholder.layout.measure)
      (local min-column-width (* self.column-width self.min-columns))
      (local min-line-height (* self.line-height self.min-lines))
      (local inner-width
        (if self.line-wrap?
            (math.max (or options.content-min-width 0)
                      min-column-width
                      placeholder-measure.x)
            (math.max (or options.content-min-width 0)
                      text-measure.x
                      placeholder-measure.x
                      min-column-width)))
      (local inner-height (math.max text-measure.y
                                    placeholder-measure.y
                                    min-line-height))
      (set self.content-size (glm.vec3 inner-width inner-height 0))
      (local total-width (+ (* 2 padding.x) inner-width))
      (local total-height (+ (* 2 padding.y) inner-height))
      (local clamped-width (math.max min-width total-width))
      (local clamped-height (math.max min-height total-height))
      (set layout.measure (glm.vec3 clamped-width clamped-height 0)))

    (fn measure-constrained-input [self layout constraints]
      (local max-x (and (finite-constraint? constraints 1) constraints.max.x))
      (if (and self.line-wrap? max-x)
          (do
            (local constrained-inner-width (math.max 0 (- max-x (* 2 padding.x))))
            ;; Use a minimal positive width for wrapping so zero-width constraints
            ;; still produce visual rows instead of one oversized row.
            (local wrap-width (math.max constrained-inner-width 0.001))
            (local visual-rows (compute-visual-rows self wrap-width))
            (local viewport-lines (math.max 1 self.max-lines))
            (local drawn-lines (math.min (length visual-rows) viewport-lines))
            (local wrapped-height (* drawn-lines self.line-height))
            (self.placeholder.layout:measurer)
            (local placeholder-measure self.placeholder.layout.measure)
            (local min-column-width (* self.column-width self.min-columns))
            (local min-line-height (* self.line-height self.min-lines))
            (local inner-width (math.max constrained-inner-width
                                         (or options.content-min-width 0)
                                         min-column-width
                                         placeholder-measure.x))
            (local inner-height (math.max wrapped-height
                                          placeholder-measure.y
                                          min-line-height))
            (local total-width (+ (* 2 padding.x) inner-width))
            (local total-height (+ (* 2 padding.y) inner-height))
            (local clamped-width (math.max min-width total-width))
            (local clamped-height (math.max min-height total-height))
            (set layout.measure (glm.vec3 clamped-width clamped-height 0)))
          (measure-input self layout)))

    (fn layouter-input [self layout]
      (local rotation (or layout.rotation (glm.quat 1 0 0 0)))
      (local position (or layout.position (glm.vec3 0 0 0)))
      (local clip layout.clip-region)
      (local depth-index (or layout.depth-offset-index 0))
      (local size (or layout.size layout.measure))
      (local inner-width (math.max 0 (- size.x (* 2 padding.x))))
      (local inner-height (math.max 0 (- size.y (* 2 padding.y))))
      (local inner-size (glm.vec3 inner-width inner-height size.z))
      (set self.inner-size inner-size)
      (when self.line-wrap?
        (set self.visual-rows-dirty? true)
        (set self.virtual-dirty? true))
      (apply-viewport self inner-size)
      (sync-viewport-state self)
      (local refreshed? (refresh-virtual-text self))
      (when refreshed?
        (self.text.layout:measurer))
      (fn apply-layout [node depth]
        (when node
          (set node.layout.size size)
          (set node.layout.position position)
          (set node.layout.rotation rotation)
          (set node.layout.depth-offset-index (+ depth-index depth))
          (set node.layout.clip-region clip)
          (node.layout:layouter)))
      (apply-layout self.focus-overlay 0)
      (apply-layout self.background 1)
      (local text-offset
        (rotation:rotate
          (glm.vec3 padding.x
                    (+ padding.y (text-block-offset self inner-height))
                    0)))
      (local text-position (+ position text-offset))
      (set self.text.layout.size inner-size)
      (set self.text.layout.position text-position)
      (set self.text.layout.rotation rotation)
      (set self.text.layout.depth-offset-index (+ depth-index 3))
      (set self.text.layout.clip-region clip)
      (self.text.layout:layouter)
      (set self.placeholder.layout.size inner-size)
      (set self.placeholder.layout.position text-position)
      (set self.placeholder.layout.rotation rotation)
      (set self.placeholder.layout.depth-offset-index (+ depth-index 4))
      (set self.placeholder.layout.clip-region clip)
      (self.placeholder.layout:layouter)
      (when self.caret
        (local caret-depth (+ depth-index 2))
        (local prefix (self:cursor-prefix-width))
        (local x-offset (+ padding.x prefix))
        (local caret-y (caret-vertical-offset self))
        (local caret-height (caret-height-for-inner self inner-height))
        (local caret-position (+ position (rotation:rotate (glm.vec3 x-offset caret-y 0))))
        (set self.caret.layout.size (glm.vec3 (caret-width-for-mode self) caret-height size.z))
        (set self.caret.layout.position caret-position)
        (set self.caret.layout.rotation rotation)
        (set self.caret.layout.depth-offset-index caret-depth)
        (set self.caret.layout.clip-region clip)
        (self.caret.layout:layouter))
      (set self.layout-happened? true))

    (set layout
         (Layout {:name (or options.name "input")
                  :measurer (fn [layout-self]
                              (measure-input input layout-self))
                  :constrained-measurer (fn [layout-self constraints]
                                         (measure-constrained-input input layout-self constraints))
                  :layouter (fn [layout-self]
                              (layouter-input input layout-self))
                  :children [focus-outline.layout
                             background.layout
                             text.layout
                             placeholder.layout
                             caret.layout]}))
    (when (and focus-node focus-context layout)
      (focus-context:attach-bounds focus-node {:layout layout}))

    (set input
         {:layout layout
          :model model
          :text text
          :placeholder placeholder
          :focus-overlay focus-outline
          :background background
          :caret caret
          :padding padding
          :caret-width caret-width
          :multiline? multiline?
          :focus-node focus-node
          :focus-manager focus-manager
          :mode model.mode
          :hovered? false
          :focused? false
          :connected? model.connected?
          :codepoints model.codepoints
          :cursor-index model.cursor-index
          :cursor-line 0
          :cursor-column 0
          :lines []
          :scroll {:line 0 :column 0}
          :visible-line-count initial-visible-lines
          :visible-column-count initial-visible-columns
          :explicit-line-count explicit-line-count
          :explicit-column-count explicit-column-count
          :min-lines resolved-min-lines
          :max-lines resolved-max-lines
          :min-columns resolved-min-columns
          :max-columns resolved-max-columns
          :line-height computed-line-height
          :column-width computed-column-width
          :virtual-dirty? true
          :visual-rows-dirty? true
          :line-wrap? line-wrap?
          :visual-rows []
          :prev-cursor-line nil
          :prev-cursor-column nil
          :layout-happened? false
          :explicit-scroll? false
          :caret-explicitly-positioned? false
          :colors colors
          :pointer-target pointer-target
          :changed model.changed
          :submitted (Signal)})

    (set input.get-text
         (fn [_self]
           (model:get-text)))

    (set input.set-text
         (fn [_self value opts]
           (model:set-text value opts)))

    (set input.insert-text
         (fn [_self value]
           (model:insert-text value)))

    (set input.delete-at-cursor
         (fn [_self]
           (model:delete-at-cursor)))

    (set input.delete-before-cursor
         (fn [_self]
           (model:delete-before-cursor)))

    (set input.move-caret
         (fn [self delta]
           (local moved (model:move-caret delta))
           (when moved
             (apply-caret-change self))
           moved))

    (set input.move-caret-to
         (fn [self position]
           (local moved (model:move-caret-to position))
           (when moved
             (apply-caret-change self))
           moved))

    (set input.enter-insert-mode
         (fn [_self]
           (model:enter-insert-mode)))

    (set input.enter-normal-mode
         (fn [_self]
           (model:enter-normal-mode)))

    (set input.set-mode
         (fn [_self mode]
           (model:set-mode mode)))

    (set input.update-background update-background)
    (set input.update-caret-visual update-caret-visual)
    (set input.update-focus-visual update-focus-visual)
    (set input.sync-placeholder sync-placeholder)
    (set input.cursor-prefix-width cursor-prefix-width)
    (set input.caret-width-for-mode caret-width-for-mode)
    (set input.scroll-lines
          (fn [self delta]
            (if self.line-wrap?
                (do
                  (ensure-visual-rows self)
                  (local visual-rows self.visual-rows)
                  (local viewport-lines (math.max 1 (or self.visible-line-count 1)))
                  (local total-visual (length visual-rows))
                  (local max-scroll (math.max 0 (- total-visual viewport-lines)))
                  (local next (math.max 0 (math.min (+ (or self.scroll.line 0) delta) max-scroll)))
                  (if (= next (or self.scroll.line 0))
                      false
                      (do
                        (set self.scroll.line next)
                        (set self.explicit-scroll? true)
                        (local vr (. visual-rows (+ next 1)))
                        (when vr
                          (set self.model.scroll-line vr.line-index))
                        (mark-virtual-dirty self)
                        (refresh-virtual-text self true)
                        true)))
                (if (self.model:scroll-lines delta)
                    (do
                      (sync-viewport-state self)
                      (mark-virtual-dirty self)
                      (refresh-virtual-text self true)
                      true)
                    false))))
    (set input.scroll-columns
          (fn [self delta]
            (assert (not self.line-wrap?)
                    "horizontal scroll is not available when line-wrap? is enabled")
            (if (self.model:scroll-columns delta)
                (do
                  (sync-viewport-state self)
                  (mark-virtual-dirty self)
                  (refresh-virtual-text self true)
                  true)
                false)))
    (set input.set-scroll-position
          (fn [self opts]
            (local opts-table (or opts {}))
            (if self.line-wrap?
                (do
                  (assert (= (or opts-table.column 0) 0)
                          "cannot set horizontal scroll position when line-wrap? is enabled")
                  (ensure-visual-rows self)
                  (local visual-rows self.visual-rows)
                  (local viewport-lines (math.max 1 (or self.visible-line-count 1)))
                  (local total-visual (length visual-rows))
                  (local max-scroll (math.max 0 (- total-visual viewport-lines)))
                  (local target-line (if (= opts-table.line nil)
                                        (or self.scroll.line 0)
                                        (math.floor (math.max 0 (or opts-table.line 0)))))
                  (local clamped (math.max 0 (math.min target-line max-scroll)))
                  (if (= clamped (or self.scroll.line 0))
                      false
                      (do
                        (set self.scroll.line clamped)
                        (set self.explicit-scroll? true)
                        (local vr (. visual-rows (+ clamped 1)))
                        (when vr
                          (set self.model.scroll-line vr.line-index))
                        (mark-virtual-dirty self)
                        (refresh-virtual-text self true)
                        true)))
                (if (self.model:set-scroll-position opts-table)
                    (do
                      (sync-viewport-state self)
                      (mark-virtual-dirty self)
                      (refresh-virtual-text self true)
                      true)
                    false))))
    (set input.refresh-virtual-text
         (fn [self]
           (refresh-virtual-text self true)))

    (set input.request-focus
          (fn [self]
            (FocusPolicy.request-focus self)))

    (set input.submit
         (fn [self payload]
           (self.submitted:emit payload)))

    (set input.on-click
         (fn [self _event]
           (self:request-focus)))

    (fn strip-single-trailing-newline [value]
      (if (not (= (type value) :string))
          (or value "")
          (let [n (# value)]
            (if (<= n 0)
                value
                (let [last (string.sub value n n)]
                  (if (= last "\n")
                      (let [without-nl (string.sub value 1 (- n 1))
                            m (# without-nl)]
                        (if (and (> m 0) (= (string.sub without-nl m m) "\r"))
                            (string.sub without-nl 1 (- m 1))
                            without-nl))
                      (if (= last "\r")
                          (string.sub value 1 (- n 1))
                          value)))))))

    (set input.on-double-click
         (fn [self _event]
           (ExternalEditor.edit-string
             (self:get-text)
             (fn [value]
               (when (not self.__dropped)
                 (local next-value (if self.multiline? value (strip-single-trailing-newline value)))
                 (self:set-text next-value)))
             options.external-editor)))

    (set input.on-hovered
         (fn [self hovered?]
           (set self.hovered? hovered?)
           (when system-cursors
             (system-cursors:set-cursor (if hovered? "ibeam" "arrow")))
           (self:update-background)))

    (fn resolve-context-actions [self event]
      (local config options.context-menu)
      (if (not config)
          (standard-context-menu self event)
          (if (= (type config) :function)
              (config self event)
              (error "Input context menu must be a function"))))

    (set input.on-right-click
         (fn [self event]
           (local menu-manager (get-menu-manager))
           (assert menu-manager "Input context menu requires a menu manager")
           (assert (and event event.point) "Input context menu requires event.point")
           (local actions (resolve-context-actions self event))
           (menu-manager:open {:actions actions
                               :position event.point
                               :open-button (and event event.button)})))

    (set input.on-state-connected
         (fn [self event]
           (model:on-state-connected event)
           (sync-from-model self)))

    (set input.on-state-disconnected
         (fn [self event]
           (model:on-state-disconnected event)
           (apply-mode-change self)
           (FocusPolicy.handle-state-disconnected self)))

    (set input.intersect
         (fn [self ray]
           (self.layout:intersect ray)))

    (clickables:register input)
    (clickables:register-right-click input)
    (clickables:register-double-click input)

    (hoverables:register input)

    (FocusPolicy.connect-focus-listeners input)

    (set input.__model-changed
         (model.changed:connect
           (fn [_text]
             (apply-text-change input true))))

    (set input.__mode-changed
         (model.mode-changed:connect
           (fn [_mode]
             (apply-mode-change input))))

    (apply-text-change input false {:mark-measure-dirty? false :mark-layout-dirty? false})
    (input:update-background {:mark-layout-dirty? false})

    (set input.on-text-input
         (fn [_self payload]
           (model:on-text-input payload)))

    (set input.on-text-editing
         (fn [_self payload]
           (model:on-text-editing payload)))

    (set input.on-key-up
         (fn [_self payload]
           (model:on-key-up payload)))

    (set input.drop
         (fn [self]
           (assert (not self.__dropped) "Input dropped twice")
           (set self.__dropped true)
            (FocusPolicy.handle-blur self)
           (clickables:unregister self)
           (clickables:unregister-right-click self)
           (clickables:unregister-double-click self)
           (hoverables:unregister self)
            (when self.__model-changed
              (self.model.changed:disconnect self.__model-changed true)
              (set self.__model-changed nil))
            (when self.__mode-changed
             (self.model.mode-changed:disconnect self.__mode-changed true)
            (set self.__mode-changed nil))
           (when self.submitted
             (self.submitted:clear))
           (self.model:drop)
            (FocusPolicy.disconnect-focus-listeners self)
            (when self.focus-node
             (self.focus-node:drop)
             (set self.focus-node nil))
           (self.text:drop)
           (self.placeholder:drop)
           (self.focus-overlay:drop)
           (self.background:drop)
           (self.caret:drop)
           (self.layout:drop)))

    input))

(local InputModule {:Input Input
                    :standard-context-menu standard-context-menu})

(setmetatable InputModule
              {:__call (fn [_ opts]
                         (Input opts))})

InputModule
