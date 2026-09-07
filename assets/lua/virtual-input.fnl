(local glm (require :glm))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Rectangle (require :rectangle))
(local {: Layout : resolve-mark-flag} (require :layout))
(local ClipUtils (require :clip-utils))
(local BoundsUtils (require :bounds-utils))
(local gl (require :gl))
(local Modifiers (require :input-modifiers))
(local InputState (require :input-state-router))
(local {: fallback-glyph : line-height} (require :text-utils))
(local {: resolve-input-colors : resolve-padding} (require :widget-theme-utils))

(local KEY_BACKSPACE 8)
(local KEY_DELETE 127)
(local KEY_RETURN 13)
(local KEY_LEFT 1073741904)
(local KEY_RIGHT 1073741903)
(local KEY_DOWN 1073741905)
(local KEY_UP 1073741906)
(local KEY_HOME 1073741898)
(local KEY_END 1073741901)
(local KEY_PAGEUP 1073741899)
(local KEY_PAGEDOWN 1073741902)

(var virtual-input-clip-region-seq 0)

(fn next-virtual-input-clip-region-id []
  (set virtual-input-clip-region-seq (+ virtual-input-clip-region-seq 1))
  virtual-input-clip-region-seq)

(fn clip-codepoints [items max-count]
  (assert (= (type max-count) :number) "clip-codepoints requires max-count")
  (local out [])
  (local limit (math.max 0 (or max-count 0)))
  (var i 1)
  (while (and (<= i (length (or items []))) (<= i limit))
    (table.insert out (. items i))
    (set i (+ i 1)))
  out)

(fn byte-for-column [row column]
  (assert row "byte-for-column requires row")
  (local offsets (or row.column-byte-offsets [0]))
  (local idx (+ (math.max 0 (math.floor (or column 0))) 1))
  (local offset (. offsets idx))
  (if (= offset nil)
      (or row.end-byte row.line-end-byte row.start-byte 0)
      (+ (or row.start-byte 0) offset)))

(fn column-for-x [input row local-x]
  (assert input "column-for-x requires input")
  (local raw-column (if (> input.column-width 0)
                      (math.floor (/ (math.max 0 local-x) input.column-width))
                      0))
  (math.max 0 (math.min raw-column (length (or row.codepoints [])))))

(fn row-visible-column-count [input row]
  (assert row "row-visible-column-count requires row")
  (math.min input.visible-column-count (length (or row.codepoints []))))

(fn mark-row-layouts-dirty [input]
  (each [_ row-widget (ipairs input.rows)]
    (when (and row-widget row-widget.layout)
      (row-widget.layout:mark-layout-dirty))))

(fn mark-caret-dirty [input]
  (when (and input.caret input.caret.layout)
    (input.caret.layout:mark-layout-dirty)))

(fn mark-viewport-dirty [input]
  (mark-row-layouts-dirty input)
  (mark-caret-dirty input))

(fn adapter-row [row]
  (assert row "adapter-row requires row")
  (local codepoints (clip-codepoints (or row.codepoints []) (+ (length (or row.codepoints [])) 1)))
  (when (or row.partial?
            (< (or row.end-byte 0) (or row.line-end-byte row.end-byte 0)))
    (table.insert codepoints 32))
  {:line row.line
   :start-byte row.start-byte
   :end-byte row.end-byte
   :line-end-byte row.line-end-byte
   :line-end-known? row.line-end-known?
   :newline-bytes row.newline-bytes
   :newline-length (or row.newline-bytes 0)
   :text row.text
   :codepoints codepoints
   :partial? row.partial?
   :column-byte-offsets (or row.column-byte-offsets [0])})

(fn adapter-line-start-index [lines idx]
  (assert lines "adapter-line-start-index requires lines")
  (var total 0)
  (var i 0)
  (while (< i idx)
    (local line (. lines (+ i 1)))
    (when line
      (set total (+ total
                   (length (or line.codepoints []))
                   (or line.newline-length 0))))
    (set i (+ i 1)))
  total)

(fn cursor-column-for-row [row cursor]
  (assert row "cursor-column-for-row requires row")
  (var column 0)
  (each [i offset (ipairs (or row.column-byte-offsets []))]
    (when (<= (+ (or row.start-byte 0) offset) cursor)
      (set column (- i 1))))
  column)

(fn sync-model-state [self snapshot]
  (assert self "sync-model-state requires input")
  (local model (or self.model {}))
  (local lines [])
  (each [_ row (ipairs (or (and snapshot snapshot.rows) []))]
    (table.insert lines (adapter-row row)))
  (local cursor (or self.buffer.cursor-byte 0))
  (var cursor-line 0)
  (var cursor-column 0)
  (var found? false)
  (each [i row (ipairs lines)]
    (when (and (not found?)
               (>= cursor (or row.start-byte 0))
               (<= cursor (or row.line-end-byte row.end-byte 0)))
      (set cursor-line (- i 1))
      (set cursor-column (cursor-column-for-row row cursor))
      (set found? true)))
  (local cursor-index (+ (adapter-line-start-index lines cursor-line) cursor-column))
  (set model.lines lines)
  (set model.cursor-line cursor-line)
  (set model.cursor-column cursor-column)
  (set model.cursor-index cursor-index)
  (set self.model model)
  (set self.lines lines)
  (set self.cursor-line cursor-line)
  (set self.cursor-column cursor-column)
  (set self.cursor-index cursor-index)
  model)

(fn refresh-viewport [self opts]
  (assert self.buffer "refresh-viewport requires buffer")
  (local options (or opts {}))
  (local snapshot (self.buffer:get-viewport {:line self.scroll-line
                                             :column self.scroll-column
                                             :lines self.visible-line-count
                                             :columns self.visible-column-count}))
  (set self.viewport snapshot)
  (set self.scroll-line snapshot.start-line)
  (set self.scroll-column snapshot.start-column)
  (each [i row-widget (ipairs self.rows)]
    (local viewport-row (. snapshot.rows i))
    (local codepoints (clip-codepoints (and viewport-row viewport-row.codepoints)
                                       self.visible-column-count))
    (row-widget:set-codepoints codepoints {:mark-measure-dirty? false}))
  (when (resolve-mark-flag options :mark-layout-dirty? true)
    (mark-viewport-dirty self))
  (sync-model-state self snapshot)
  snapshot)

(fn sync-scroll [self]
  (assert self "sync-scroll requires input")
  (set self.scroll-line (math.max 0 (or self.buffer.scroll-line self.scroll-line 0))))

(fn notify-change [self]
  (when self.on-change
    (self.on-change self self.buffer)))

(fn ensure-viewport [self]
  (assert self "ensure-viewport requires input")
  (or self.viewport (self:refresh-viewport {:mark-layout-dirty? false})))

(fn caret-row [self]
  (assert self "caret-row requires input")
  (local viewport (ensure-viewport self))
  (var found nil)
  (each [_ row (ipairs (or viewport.rows []))]
    (when (and (not found)
               (>= (or self.buffer.cursor-byte 0) (or row.start-byte 0))
               (<= (or self.buffer.cursor-byte 0) (or row.line-end-byte row.end-byte 0)))
      (set found row)))
  found)

(fn line-from-cursor [self]
  (assert self "line-from-cursor requires input")
  (local viewport (ensure-viewport self))
  (var found-line nil)
  (each [_ row (ipairs (or viewport.rows []))]
    (when (and (not found-line)
               (>= (or self.buffer.cursor-byte 0) (or row.start-byte 0))
               (<= (or self.buffer.cursor-byte 0) (or row.line-end-byte row.end-byte 0)))
      (set found-line row.line)))
  found-line)

(fn keep-line-visible [self line]
  (when line
    (local next-scroll
      (if (< line self.scroll-line)
          line
          (>= line (+ self.scroll-line self.visible-line-count))
          (math.max 0 (- line (- self.visible-line-count 1)))
          self.scroll-line))
    (when (not (= next-scroll self.scroll-line))
      (set self.scroll-line next-scroll)
      (set self.buffer.scroll-line next-scroll))))

(fn keep-column-visible [self column]
  (when column
    (assert (= (type self.visible-column-count) :number)
            "keep-column-visible requires visible-column-count")
    (assert (= (type self.scroll-column) :number)
            "keep-column-visible requires scroll-column")
    (local visible-count (math.max 1 self.visible-column-count))
    (var next-scroll
      (if (< column self.scroll-column)
          column
          (>= column (+ self.scroll-column visible-count))
          (- column (- visible-count 1))
          self.scroll-column))
    (set next-scroll (math.max 0 next-scroll))
    (when (not (= next-scroll self.scroll-column))
      (set self.scroll-column next-scroll))))

(fn locate-caret-in-row [self row]
  (assert self "locate-caret-in-row requires input")
  (assert row "locate-caret-in-row requires row")
  (local cursor (or self.buffer.cursor-byte 0))
  (local row-start (or row.start-byte 0))
  (local row-end (or row.end-byte row.line-end-byte row-start))
  (when (and (>= cursor row-start) (<= cursor row-end))
    (values row.line (+ self.scroll-column (cursor-column-for-row row cursor)) row)))

(fn locate-caret-in-full-line [self line]
  (assert self "locate-caret-in-full-line requires input")
  (when line
    (assert (= (type self.visible-column-count) :number)
            "locate-caret-in-full-line requires visible-column-count")
    (assert (= (type self.scroll-column) :number)
            "locate-caret-in-full-line requires scroll-column")
    (local cursor (or self.buffer.cursor-byte 0))
    (local snapshot (self.buffer:get-viewport {:line line
                                               :column self.scroll-column
                                               :lines 1
                                               :columns self.visible-column-count}))
    (local row (. (or snapshot.rows []) 1))
    (when (and row
               (>= cursor (or row.start-byte 0))
               (<= cursor (or row.end-byte row.start-byte 0)))
      (values row.line (+ self.scroll-column (cursor-column-for-row row cursor)) row))))

(fn locate-caret-line-column [self]
  (assert self "locate-caret-line-column requires input")
  (local viewport (ensure-viewport self))
  (local cursor (or self.buffer.cursor-byte 0))
  (var fallback-line nil)
  (var found-line nil)
  (var found-column nil)
  (var found-row nil)
  (each [_ row (ipairs (or viewport.rows []))]
    (when (and row (not found-row))
      (local (line column located-row) (locate-caret-in-row self row))
      (if located-row
          (do
            (set found-line line)
            (set found-column column)
            (set found-row located-row))
          (and (not fallback-line)
               (<= cursor (or row.line-end-byte row.end-byte 0)))
          (set fallback-line row.line))))
  (if found-row
      (values found-line found-column found-row)
      (or fallback-line self.cursor-line)
      (locate-caret-in-full-line self (or fallback-line self.cursor-line))
      (values nil nil nil)))

(fn keep-caret-column-visible [self]
  (local (_line column _row) (locate-caret-line-column self))
  (keep-column-visible self column))

(fn infer-line-from-viewport-edge [self]
  (assert self "infer-line-from-viewport-edge requires input")
  (local viewport (ensure-viewport self))
  (local rows (or viewport.rows []))
  (local first-row (. rows 1))
  (local last-row (. rows (length rows)))
  (local cursor (or self.buffer.cursor-byte 0))
  (if (and first-row (< cursor (or first-row.start-byte 0)))
      (math.max 0 (- first-row.line 1))
      (and last-row last-row.partial? (> cursor (or last-row.end-byte 0)))
      last-row.line
      (and last-row (> cursor (or last-row.line-end-byte last-row.end-byte 0)))
      (+ last-row.line 1)
      nil))

(fn line-after-caret-move [self explicit-line]
  (assert self "line-after-caret-move requires input")
  (or explicit-line (line-from-cursor self) (infer-line-from-viewport-edge self)))

(fn caret-line-column [self]
  (assert self "caret-line-column requires input")
  (locate-caret-line-column self))

(fn apply-caret-byte [self target-byte extend-selection?]
  (assert (= (type target-byte) :number) "apply-caret-byte requires numeric target")
  (local anchor (or self.selection-anchor-byte self.buffer.cursor-byte 0))
  (local moved (self.buffer:move-caret-to-byte target-byte))
  (if extend-selection?
      (do
        (set self.selection-anchor-byte anchor)
        (self.buffer:set-selection anchor self.buffer.cursor-byte))
      (do
        (set self.selection-anchor-byte self.buffer.cursor-byte)
        (when self.buffer.selection
          (self.buffer:clear-selection))))
  (when moved
    (keep-line-visible self (line-after-caret-move self nil))
    (keep-caret-column-visible self)
    (mark-caret-dirty self)
    (self:refresh-viewport))
  moved)

(fn byte-for-adapter-position [self position]
  (assert (= (type position) :number) "byte-for-adapter-position requires numeric position")
  (local viewport (ensure-viewport self))
  (local rows (or viewport.rows []))
  (local target (math.max 0 (math.floor position)))
  (var remaining target)
  (var fallback-byte (or self.buffer.cursor-byte 0))
  (each [_ row (ipairs rows)]
    (when (and row remaining)
      (set fallback-byte (or row.line-end-byte row.end-byte fallback-byte))
      (local codepoint-count (length (or row.codepoints [])))
      (local newline-length (or row.newline-bytes 0))
      (local span (+ codepoint-count newline-length))
      (if (<= remaining codepoint-count)
          (do
            (set fallback-byte (byte-for-column row remaining))
            (set remaining nil))
          (and remaining (< remaining span))
          (do
            (set fallback-byte (or row.line-end-byte row.end-byte fallback-byte))
            (set remaining nil))
          remaining
          (set remaining (- remaining span)))))
  fallback-byte)

(fn move-caret-to [self position]
  (apply-caret-byte self (byte-for-adapter-position self position) false))

(fn apply-caret-line-column [self line column extend-selection?]
  (assert (= (type line) :number) "apply-caret-line-column requires line")
  (local anchor (or self.selection-anchor-byte self.buffer.cursor-byte 0))
  (local moved (self.buffer:move-caret-to-line-column (math.max 0 line) (math.max 0 column)))
  (if extend-selection?
      (do
        (set self.selection-anchor-byte anchor)
        (self.buffer:set-selection anchor self.buffer.cursor-byte))
      (do
        (set self.selection-anchor-byte self.buffer.cursor-byte)
        (when self.buffer.selection
          (self.buffer:clear-selection))))
  (when moved
    (keep-line-visible self (line-after-caret-move self line))
    (keep-column-visible self column)
    (mark-caret-dirty self)
    (self:refresh-viewport))
  moved)

(fn insert-text [self text]
  (assert (= (type text) :string) "VirtualInput insert-text requires string text")
  (when self.buffer.selection
    (if self.buffer.delete-selection
        (self.buffer:delete-selection)
        (error "VirtualInput requires buffer:delete-selection for selected insertion")))
  (local changed (self.buffer:insert-text text))
  (when changed
    (set self.selection-anchor-byte self.buffer.cursor-byte)
    (notify-change self)
    (keep-caret-column-visible self)
    (self:refresh-viewport))
  changed)

(fn delete-active-selection [self]
  (when (not self.buffer.delete-selection)
    (error "VirtualInput requires buffer:delete-selection for selected delete"))
  (local changed (self.buffer:delete-selection))
  (when changed
    (set self.selection-anchor-byte self.buffer.cursor-byte)
    (notify-change self)
    (keep-caret-column-visible self)
    (self:refresh-viewport))
  changed)

(fn delete-before-cursor [self]
  (if self.buffer.selection
      (delete-active-selection self)
      (do
        (local changed (self.buffer:delete-before-cursor))
        (when changed
          (set self.selection-anchor-byte self.buffer.cursor-byte)
          (notify-change self)
          (keep-caret-column-visible self)
          (self:refresh-viewport))
        changed)))

(fn delete-at-cursor [self]
  (if self.buffer.selection
      (delete-active-selection self)
      (do
        (local changed (self.buffer:delete-at-cursor))
        (when changed
          (set self.selection-anchor-byte self.buffer.cursor-byte)
          (notify-change self)
          (keep-caret-column-visible self)
          (self:refresh-viewport))
        changed)))

(fn update-horizontal-selection [self anchor extend-selection?]
  (if extend-selection?
      (do
        (set self.selection-anchor-byte anchor)
        (self.buffer:set-selection anchor self.buffer.cursor-byte))
      (do
        (set self.selection-anchor-byte self.buffer.cursor-byte)
        (when self.buffer.selection
          (self.buffer:clear-selection)))))

(fn apply-horizontal-caret-move [self delta extend-selection?]
  (when (not self.buffer.move-caret-horizontal)
    (error "VirtualInput requires buffer:move-caret-horizontal for horizontal movement"))
  (local anchor (or self.selection-anchor-byte self.buffer.cursor-byte 0))
  (local previous-line self.cursor-line)
  (local previous-column (+ self.scroll-column self.cursor-column))
  (local moved (self.buffer:move-caret-horizontal delta))
  (update-horizontal-selection self anchor extend-selection?)
  (when moved
    (local target-line (or (line-after-caret-move self nil) previous-line))
    (local target-column (if (= target-line previous-line)
                           (math.max 0 (+ previous-column delta))
                           0))
    (when target-line
      (set self.cursor-line target-line))
    (set self.cursor-column target-column)
    (keep-line-visible self target-line)
    (keep-column-visible self target-column)
    (mark-caret-dirty self)
    (self:refresh-viewport))
  moved)

(fn move-caret [self delta opts]
  (local (line column _row) (caret-line-column self))
  (local extend? (and opts opts.extend-selection?))
  (if (= (type delta) :number)
      (apply-horizontal-caret-move self delta extend?)
      (= delta :left)
      (apply-horizontal-caret-move self -1 extend?)
      (= delta :right)
      (apply-horizontal-caret-move self 1 extend?)
      (= delta :up)
      (apply-caret-line-column self (- line 1) column extend?)
      (= delta :down)
      (apply-caret-line-column self (+ line 1) column extend?)
      (= delta :home)
      (apply-caret-line-column self line 0 extend?)
      (= delta :end)
      (apply-caret-line-column self line (row-visible-column-count self _row) extend?)
      (error (.. "VirtualInput unsupported caret move: " (tostring delta)))))

(fn scroll-lines [self delta opts]
  (local changed (self.buffer:scroll-lines delta))
  (when changed
    (local extend? (and opts opts.extend-selection?))
    (sync-scroll self)
    (self:refresh-viewport)
    (when (not (caret-row self))
      (apply-caret-line-column self self.scroll-line 0 extend?)))
  changed)

(fn copy-selection [self]
  (if self.buffer.selection
      (do
        (local text (self.buffer:get-selected-text))
        (gl.clipboard-set text)
        text)
      false))

(fn save [self]
  (local result (self.buffer:save))
  (when self.on-save
    (self.on-save self result))
  result)

(fn on-text-input [self payload]
  (if (and payload (= (type payload.text) :string))
      (self:insert-text payload.text)
      false))

(fn on-key-down [self payload]
  (if (not (and payload payload.key))
      false
      (do
        (local key payload.key)
        (local ctrl? (Modifiers.ctrl-held? payload.mod))
        (local shift? (Modifiers.shift-held? payload.mod))
        (if (and ctrl? (= key (string.byte "s")))
            (do (self:save) true)
            (and ctrl? (= key (string.byte "S")))
            (do (self:save) true)
            (and ctrl? (= key (string.byte "c")))
            (if (self:copy-selection) true false)
            (and ctrl? (= key (string.byte "C")))
            (if (self:copy-selection) true false)
            (= key KEY_LEFT)
            (self:move-caret :left {:extend-selection? shift?})
            (= key KEY_RIGHT)
            (self:move-caret :right {:extend-selection? shift?})
            (= key KEY_UP)
            (self:move-caret :up {:extend-selection? shift?})
            (= key KEY_DOWN)
            (self:move-caret :down {:extend-selection? shift?})
            (= key KEY_HOME)
            (self:move-caret :home {:extend-selection? shift?})
            (= key KEY_END)
            (self:move-caret :end {:extend-selection? shift?})
            (= key KEY_PAGEUP)
            (self:scroll-lines (- self.visible-line-count) {:extend-selection? shift?})
            (= key KEY_PAGEDOWN)
            (self:scroll-lines self.visible-line-count {:extend-selection? shift?})
            (= key KEY_BACKSPACE)
            (self:delete-before-cursor)
            (= key KEY_DELETE)
            (self:delete-at-cursor)
            (= key KEY_RETURN)
            (self:insert-text "\n")
            false))))

(fn enter-insert-mode [self]
  (set self.mode :insert)
  (mark-caret-dirty self)
  true)

(fn enter-normal-mode [self]
  (set self.mode :normal)
  (mark-caret-dirty self)
  true)

(fn submit [self payload]
  (if self.on-submit
      (self.on-submit self payload)
      false))

(fn local-point-from-event [self event]
  (if (and event event.local-point)
      event.local-point
      (if (and event event.point self.layout)
          (- event.point self.layout.position)
          (glm.vec3 0 0 0))))

(fn on-click [self event]
  (self:request-focus)
  (local point (local-point-from-event self event))
  (local row-index (if (and event event.row-index)
                     event.row-index
                     (+ 1 (math.floor (/ (math.max 0 (- point.y self.padding.y)) self.line-height)))))
  (local viewport (ensure-viewport self))
  (local row (. viewport.rows row-index))
  (when row
    (local column (if (and event event.column)
                    event.column
                    (column-for-x self row (- point.x self.padding.x))))
    (apply-caret-byte self (byte-for-column row column) (and event (Modifiers.shift-held? event.mod))))
  true)

(fn measure-virtual-input [input layout]
  (each [_ row-widget (ipairs input.rows)]
    (row-widget.layout:measurer))
  (local width (+ (* 2 input.padding.x) (* input.column-width input.configured-column-count)))
  (local height (+ (* 2 input.padding.y) (* input.line-height input.configured-line-count)))
  (set layout.measure (glm.vec3 width height 0)))

(fn visible-count-for-size [available unit configured]
  (assert (= (type available) :number) "visible-count-for-size requires available size")
  (assert (= (type unit) :number) "visible-count-for-size requires unit size")
  (assert (= (type configured) :number) "visible-count-for-size requires configured count")
  (local raw-count (if (> unit 0)
                     (math.floor (+ (/ (math.max 0 available) unit) 1e-6))
                     configured))
  (math.max 1 (math.min configured raw-count)))

(fn update-visible-viewport-size [input size]
  (assert input "update-visible-viewport-size requires input")
  (local allocated (or size input.layout.size input.layout.measure))
  (local inner-width (math.max 0 (- allocated.x (* 2 input.padding.x))))
  (local inner-height (math.max 0 (- allocated.y (* 2 input.padding.y))))
  (local next-columns (visible-count-for-size inner-width input.column-width input.configured-column-count))
  (local next-lines (visible-count-for-size inner-height input.line-height input.configured-line-count))
  (local changed? (or (not (= next-columns input.visible-column-count))
                      (not (= next-lines input.visible-line-count))))
  (when changed?
    (set input.visible-column-count next-columns)
    (set input.visible-line-count next-lines)
    (input:refresh-viewport {:mark-layout-dirty? false}))
  changed?)

(fn intersect-bounds [parent child]
  (if parent
      (BoundsUtils.bounds-aabb-in-parent parent child)
      child))

(fn update-local-clip-region [input layout]
  (assert input "update-local-clip-region requires input")
  (assert layout "update-local-clip-region requires layout")
  (local clip (or input.local-clip-region
                  {:id input.local-clip-region-id
                   :layout layout
                   :bounds {:position layout.position
                            :rotation layout.rotation
                            :size layout.size}}))
  (set clip.id input.local-clip-region-id)
  (set clip.layout layout)
  (local bounds (or clip.bounds
                    {:position layout.position
                     :rotation layout.rotation
                     :size layout.size}))
  (local input-bounds {:position layout.position
                       :rotation layout.rotation
                       :size layout.size})
  (local parent-bounds (and layout.clip-region layout.clip-region.bounds))
  (local resolved (intersect-bounds parent-bounds input-bounds))
  (local resolved-size (or (and resolved resolved.size) layout.size))
  (set clip.bounds bounds)
  (set bounds.position (or (and resolved resolved.position) layout.position))
  (set bounds.rotation (or (and resolved resolved.rotation) layout.rotation))
  (set bounds.size (glm.vec3 (math.max 0 (math.min resolved-size.x layout.size.x))
                             (math.max 0 (math.min resolved-size.y layout.size.y))
                             (math.max 0 (math.min resolved-size.z layout.size.z))))
  (ClipUtils.update-region clip)
  (set input.local-clip-region clip)
  clip)

(fn layout-child [child position rotation size depth clip]
  (set child.layout.position position)
  (set child.layout.rotation rotation)
  (set child.layout.size size)
  (set child.layout.depth-offset-index depth)
  (set child.layout.clip-region clip)
  (child.layout:layouter))

(fn caret-position [input position rotation line column]
  (local visible-row (+ (- line input.scroll-line) 1))
  (+ position
     (rotation:rotate (glm.vec3 (+ input.padding.x (* (- column input.scroll-column) input.column-width))
                                 (+ input.padding.y (* (- visible-row 1) input.line-height))
                                 0))))

(fn show-caret [input position rotation size depth clip line column]
  (set input.caret.visible? true)
  (layout-child input.caret
                (caret-position input position rotation line column)
                rotation
                (glm.vec3 input.caret-width input.line-height size.z)
                depth
                clip))

(fn hide-caret [input position rotation size depth clip]
  (set input.caret.visible? false)
  (layout-child input.caret position rotation (glm.vec3 0 0 size.z) depth clip))

(fn layout-caret [input position rotation size depth clip]
  (local (line column row) (caret-line-column input))
  (if (and row
           (>= column input.scroll-column)
           (<= column (+ input.scroll-column input.visible-column-count)))
      (show-caret input position rotation size depth clip line column)
      (hide-caret input position rotation size depth clip)))

(fn layout-virtual-input [input layout]
  (assert input "layout-virtual-input requires input")
  (local rotation (or layout.rotation (glm.quat 1 0 0 0)))
  (local position (or layout.position (glm.vec3 0 0 0)))
  (local size (or layout.size layout.measure))
  (local depth (or layout.depth-offset-index 0))
  (update-visible-viewport-size input size)
  (input:refresh-viewport {:mark-layout-dirty? false})
  (local clip (update-local-clip-region input layout))
  (layout-child input.background position rotation size (+ depth 1) clip)
  (each [i row-widget (ipairs input.rows)]
    (local row-pos (+ position (rotation:rotate (glm.vec3 input.padding.x
                                                          (+ input.padding.y (* (- i 1) input.line-height))
                                                          0))))
    (layout-child row-widget row-pos rotation (glm.vec3 (- size.x (* 2 input.padding.x)) input.line-height size.z) (+ depth 3) clip))
  (layout-caret input position rotation size (+ depth 2) clip))

(fn measure-layout [layout]
  (measure-virtual-input layout.virtual-input layout))

(fn run-layout [layout]
  (layout-virtual-input layout.virtual-input layout))

(fn intersect-virtual-input [self ray]
  (self.layout:intersect ray))

(fn request-focus [self]
  (when self.focus-node
    (self.focus-node:request-focus))
  (when (and InputState (not self.connected?))
    (InputState.connect-input self)
    (InputState.set-state :text))
  true)

(fn on-state-connected [self _event]
  (set self.connected? true))

(fn on-state-disconnected [self _event]
  (set self.connected? false))

(fn handle-focus [input]
  (input:request-focus))

(fn handle-blur [input]
  (when input.connected?
    (InputState.disconnect-input input)))

(fn focus-event-current? [input event]
  (= (and event event.current) input.focus-node))

(fn focus-event-previous? [input event]
  (= (and event event.previous) input.focus-node))

(fn make-focus-listener [input]
  (fn [event]
    (when (focus-event-current? input event)
      (handle-focus input))))

(fn make-blur-listener [input]
  (fn [event]
    (when (focus-event-previous? input event)
      (handle-blur input))))

(fn drop [self]
  (assert (not self.__dropped) "VirtualInput dropped twice")
  (set self.__dropped true)
  (self.clickables:unregister self)
  (each [_ row-widget (ipairs self.rows)]
    (row-widget:drop))
  (self.background:drop)
  (self.caret:drop)
  (when self.focus-node
    (self.focus-node:drop)
    (set self.focus-node nil))
  (when (and self.connected? InputState)
    (InputState.disconnect-input self))
  (when self.__focus-listener
    (local manager self.focus-manager)
    (when (and manager manager.focus-focus)
      (manager.focus-focus.disconnect self.__focus-listener true))
    (set self.__focus-listener nil))
  (when self.__blur-listener
    (local manager self.focus-manager)
    (when (and manager manager.focus-blur)
      (manager.focus-blur.disconnect self.__blur-listener true))
    (set self.__blur-listener nil))
  (self.layout:drop))

(fn resolve-line-height* [text-style]
  (local value (line-height text-style))
  (if (and value (> value 0)) value 1.6))

(fn resolve-column-width* [text-style caret-width]
  (local font (and text-style text-style.font))
  (if font
      (do
        (local glyph (fallback-glyph font 32))
        (local advance (* glyph.advance text-style.scale))
        (if (and advance (> advance 0)) advance caret-width))
      caret-width))

(fn VirtualInput [opts]
  (local options (or opts {}))
  (local buffer (assert options.buffer "VirtualInput requires opts.buffer"))
  (local line-count (math.max 1 (math.floor (or options.line-count 24))))
  (local column-count (math.max 1 (math.floor (or options.column-count 80))))
  (local padding (resolve-padding options.padding))
  (local caret-width (or options.caret-width 0.05))
  (fn build [ctx]
    (assert ctx "VirtualInput requires ctx")
    (assert ctx.get-text-ssbo-batcher "VirtualInput requires ctx.get-text-ssbo-batcher")
    (assert ctx.get-rectangle-quad-batcher "VirtualInput requires ctx.get-rectangle-quad-batcher")
    (local clickables (assert ctx.clickables "VirtualInput requires ctx.clickables"))
    (local pointer-target (and ctx ctx.pointer-target))
    (local colors (resolve-input-colors ctx options))
    (local focus-context (and ctx ctx.focus))
    (local focusable? (and focus-context (not (= options.focusable? false))))
    (local focus-node
      (and focusable?
           (focus-context:create-node {:name (or options.focus-name
                                                  options.name
                                                  "virtual-input")})))
    (local focus-manager (and focus-node focus-node.manager))
    (local text-style (or options.text-style (TextStyle {:color colors.foreground})))
    (local row-widgets [])
    (for [_ 1 line-count]
      (table.insert row-widgets ((Text {:codepoints [] :style text-style}) ctx)))
    (local background ((Rectangle {:color colors.background}) ctx))
    (local caret ((Rectangle {:color colors.caret-insert}) ctx))
    (local computed-line-height (resolve-line-height* text-style))
    (local computed-column-width (resolve-column-width* text-style caret-width))
    (local child-layouts [background.layout caret.layout])
    (each [_ row-widget (ipairs row-widgets)]
      (table.insert child-layouts row-widget.layout))
    (local layout
      (Layout {:name (or options.name "virtual-input")
               :measurer measure-layout
               :layouter run-layout
               :children child-layouts}))
    (local input
      {:__dropped false
       :layout layout
       :buffer buffer
       :rows row-widgets
        :background background
        :caret caret
        :clickables clickables
        :pointer-target pointer-target
        :focus-node focus-node
        :focus-manager focus-manager
        :connected? false
        :line-count line-count
        :column-count column-count
        :configured-line-count line-count
        :configured-column-count column-count
        :visible-line-count line-count
        :visible-column-count column-count
        :local-clip-region nil
        :local-clip-region-id (next-virtual-input-clip-region-id)
        :padding padding
       :line-height computed-line-height
       :column-width computed-column-width
       :caret-width caret-width
       :scroll-line (math.max 0 (or buffer.scroll-line 0))
       :scroll-column 0
       :viewport nil
       :model {}
       :lines []
       :cursor-index 0
       :cursor-line 0
       :cursor-column 0
       :mode :normal
       :multiline? true
       :selection-anchor-byte (or buffer.cursor-byte 0)
       :on-change options.on-change
       :on-save options.on-save
       :on-submit options.on-submit
       :refresh-viewport refresh-viewport
       :insert-text insert-text
       :delete-before-cursor delete-before-cursor
       :delete-at-cursor delete-at-cursor
       :move-caret-to move-caret-to
       :move-caret move-caret
       :scroll-lines scroll-lines
       :copy-selection copy-selection
       :save save
       :enter-insert-mode enter-insert-mode
       :enter-normal-mode enter-normal-mode
       :submit submit
       :on-text-input on-text-input
       :on-key-down on-key-down
       :on-click on-click
       :request-focus request-focus
       :on-state-connected on-state-connected
       :on-state-disconnected on-state-disconnected
       :intersect intersect-virtual-input
       :drop drop})
    (set layout.virtual-input input)
    (when (and focus-node focus-context layout)
      (focus-context:attach-bounds focus-node {:layout layout}))
    (when focus-manager
      (set input.__focus-listener
           (focus-manager.focus-focus.connect (make-focus-listener input)))
      (set input.__blur-listener
           (focus-manager.focus-blur.connect (make-blur-listener input))))
    (clickables:register input)
    (input:refresh-viewport {:mark-layout-dirty? false})
    input))

VirtualInput
