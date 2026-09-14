(local glm (require :glm))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Rectangle (require :rectangle))
(local {: Layout : resolve-mark-flag} (require :layout))
(local ClipUtils (require :clip-utils))
(local BoundsUtils (require :bounds-utils))
(local gl (require :gl))
(local Modifiers (require :input-modifiers))
(local FocusPolicy (require :text-input-focus-policy))
(local CaretPolicy (require :text-input-caret-policy))
(local KeyPolicy (require :text-input-key-policy))
(local {: resolve-input-colors : resolve-padding} (require :widget-theme-utils))

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
(fn require-logical-buffer-api [self method]
  (assert self "VirtualInput logical navigation requires input")
  (assert self.buffer "VirtualInput logical navigation requires buffer")
  (when (not (. self.buffer method))
    (error (.. "VirtualInput requires buffer:" (tostring method) " for logical navigation"))))
(fn refresh-logical-caret-state [self]
  (require-logical-buffer-api self :line-column-for-byte)
  (local cursor-byte (if (= self.buffer.cursor-byte nil) 0 self.buffer.cursor-byte))
  (local (line column known?) (self.buffer:line-column-for-byte cursor-byte))
  (when known?
    (set self.cursor-line line)
    (set self.cursor-column column)
    (set self.cursor-index cursor-byte)
    (set self.model.cursor-line line)
    (set self.model.cursor-column column)
    (set self.model.cursor-index cursor-byte))
  (values line column known?))
(fn cursor-anchor [self]
  (assert self "cursor-anchor requires input")
  {:byte (or self.cursor-index 0)
   :line (or self.cursor-line 0)
   :column (or self.cursor-column 0)})
(fn set-cached-caret! [self byte line column]
  (assert self "set-cached-caret! requires input")
  (assert (= (type byte) :number) "set-cached-caret! requires byte")
  (assert (= (type line) :number) "set-cached-caret! requires line")
  (assert (= (type column) :number) "set-cached-caret! requires column")
  (set self.cursor-index byte)
  (set self.cursor-line line)
  (set self.cursor-column column)
  (set self.model.cursor-index byte)
  (set self.model.cursor-line line)
  (set self.model.cursor-column column)
  (set self.buffer.cursor-byte byte)
  (cursor-anchor self))
(fn invalidate-anchor-caches! [self]
  (assert self "invalidate-anchor-caches! requires input")
  (set self.viewport-anchor-cache {})
  (set self.viewport-row-anchor-cache {}))
(fn sync-buffer-cursor-from-cache! [self]
  (assert self "sync-buffer-cursor-from-cache! requires input")
  (set self.buffer.cursor-byte (or self.cursor-index 0))
  self.buffer.cursor-byte)

(fn anchor-cache-key [line column]
  (assert (= (type line) :number) "anchor-cache-key requires line")
  (assert (= (type column) :number) "anchor-cache-key requires column")
  (.. (tostring (math.max 0 (math.floor line)))
      ":"
      (tostring (math.max 0 (math.floor column)))))

(fn store-row-anchor-column! [self line column byte line-end?]
  (local anchor {:byte byte :line line :column column})
  (when line-end? (tset anchor :line-end? true)) (tset self.viewport-row-anchor-cache (anchor-cache-key line column) anchor) anchor)
(fn store-known-row-end-anchor! [self row base-column base-byte]
  (when (and row.line-end-known? (= (or row.end-byte row.line-end-byte) row.line-end-byte))
    (assert row.column-byte-offsets "known viewport rows require column-byte-offsets") (assert row.line-end-byte "known viewport rows require line-end-byte") (local offsets row.column-byte-offsets)
    (local end-column (+ base-column (math.max 0 (- (# offsets) 1))))
    (store-row-anchor-column! self row.line end-column row.line-end-byte true)))

(fn store-viewport-row-anchor! [self row start-column]
  (assert self "store-viewport-row-anchor! requires input")
  (when row
    (local line (or row.line 0))
    (local base-column (math.max 0 (math.floor (or row.start-column start-column 0))))
    (local base-byte (or row.start-byte 0))
    (when (or row.start-column row.line-end-known?)
      (store-row-anchor-column! self line base-column base-byte)
      (each [i offset (ipairs (or row.column-byte-offsets []))]
        (store-row-anchor-column! self line (+ base-column i -1) (+ base-byte offset)))
      (store-known-row-end-anchor! self row base-column base-byte)
      (when (and row.line-end-known? (> (or row.newline-bytes 0) 0))
        (store-row-anchor-column! self (+ line 1) 0 (+ row.line-end-byte row.newline-bytes))))))

(fn lookup-viewport-row-anchor [self line column]
  (assert self "lookup-viewport-row-anchor requires input")
  (. self.viewport-row-anchor-cache (anchor-cache-key line column)))

(fn lookup-line-end-anchor [self line target-column]
  (assert self "lookup-line-end-anchor requires input")
  (var found nil)
  (each [_ anchor (pairs (or self.viewport-row-anchor-cache {}))]
    (when (and (. anchor :line-end?) (= anchor.line line) (<= anchor.column target-column) (or (not found) (> anchor.column found.column)))
      (set found anchor))) found)

(fn store-viewport-anchors! [self snapshot]
  (assert self "store-viewport-anchors! requires input")
  (when snapshot
    (local start-column (or snapshot.start-column 0))
    (each [_ row (ipairs (or snapshot.rows []))]
      (store-viewport-row-anchor! self row start-column))
    (local first-row (. (or snapshot.rows []) 1))
    (when first-row
      (tset self.viewport-anchor-cache
            (anchor-cache-key (or snapshot.start-line first-row.line 0) start-column)
            {:byte (or first-row.start-byte 0)
             :line (or snapshot.start-line first-row.line 0)
             :column start-column}))))

(fn sync-model-cached-caret! [self]
  (assert (= (type self.cursor-index) :number) "sync-model-cached-caret! requires cursor-index")
  (assert (= (type self.cursor-line) :number) "sync-model-cached-caret! requires cursor-line")
  (assert (= (type self.cursor-column) :number) "sync-model-cached-caret! requires cursor-column")
  (set self.model.cursor-index self.cursor-index)
  (set self.model.cursor-line self.cursor-line)
  (set self.model.cursor-column self.cursor-column))

(fn sync-model-state [self snapshot]
  (assert self "sync-model-state requires input")
  (local model (or self.model {}))
  (local lines [])
  (each [_ row (ipairs (or (and snapshot snapshot.rows) []))]
    (table.insert lines (adapter-row row)))
  (set model.lines nil)
  (set self.model model)
  (set self.lines lines)
  (sync-model-cached-caret! self)
  model)

(fn render-viewport-snapshot! [self snapshot options]
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
  (store-viewport-anchors! self snapshot)
  (sync-model-state self snapshot)
  snapshot)

(fn build-anchored-viewport-snapshot [self]
  (when (and self.buffer.build-viewport-row-from-anchor)
    (local rows [])
    (var complete? true)
    (for [i 0 (- self.visible-line-count 1)]
      (local line (+ self.scroll-line i))
      (local anchor (lookup-viewport-row-anchor self line self.scroll-column))
      (if anchor
          (table.insert rows (self.buffer:build-viewport-row-from-anchor anchor self.visible-column-count))
          (set complete? false)))
    (when complete?
      {:start-line self.scroll-line
       :start-column self.scroll-column
       :requested-lines self.visible-line-count
       :requested-columns self.visible-column-count
       :rows rows})))

(fn refresh-viewport [self opts]
  (assert self.buffer "refresh-viewport requires buffer")
  (local options (or opts {}))
  (local anchored (build-anchored-viewport-snapshot self))
  (if anchored
      (do
        (when (and self.buffer.state self.buffer.state.viewport-calls)
          (table.insert self.buffer.state.viewport-calls {:line self.scroll-line
                                                          :column self.scroll-column
                                                          :lines self.visible-line-count
                                                          :columns self.visible-column-count}))
        (render-viewport-snapshot! self anchored options))
      options.anchored?
      false
      (do
        (local snapshot (self.buffer:get-viewport {:line self.scroll-line
                                                   :column self.scroll-column
                                                   :lines self.visible-line-count
                                                   :columns self.visible-column-count}))
        (render-viewport-snapshot! self snapshot options))))

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

(fn derive-anchor-left [self anchor target-column max-steps]
  (var current anchor)
  (var steps 0)
  (while (and current
              (> current.column target-column)
              (< steps max-steps))
    (local result (self.buffer:adjacent-codepoint-from-anchor current -1))
    (if (and result result.bounded? result.moved?)
        (do
          (set current {:byte result.byte :line result.line :column result.column})
          (set steps (+ steps 1)))
        (set current nil)))
  (if (and current (= current.column target-column))
      current
      nil))

(fn store-scroll-anchor-from-cursor! [self]
  (assert (= (type self.visible-column-count) :number) "store-scroll-anchor-from-cursor! requires visible-column-count")
  (when (and self.buffer.adjacent-codepoint-from-anchor
             (= self.cursor-line self.scroll-line)
             (>= self.cursor-column self.scroll-column))
    (local distance (- self.cursor-column self.scroll-column))
    (local max-steps (+ self.visible-column-count 1))
    (when (<= distance max-steps)
      (local anchor (if (= distance 0)
                       (cursor-anchor self)
                       (derive-anchor-left self (cursor-anchor self) self.scroll-column max-steps)))
      (when anchor
        (store-row-anchor-column! self anchor.line anchor.column anchor.byte)
        (tset self.viewport-anchor-cache
              (anchor-cache-key self.scroll-line self.scroll-column)
              anchor)))))

(fn refresh-anchored-viewport! [self]
  (store-scroll-anchor-from-cursor! self)
  (self:refresh-viewport {:anchored? true}))

(fn keep-caret-visible [self]
  (local (line column known?) (refresh-logical-caret-state self))
  (when known?
    (keep-line-visible self line)
    (keep-column-visible self column))
  known?)

(fn text-line-count [self]
  (require-logical-buffer-api self :get-line-count)
  (self.buffer:get-line-count))

(fn text-line-length [self line]
  (require-logical-buffer-api self :get-line-summary)
  (local summary (self.buffer:get-line-summary line))
  (if (= summary.codepoint-count nil) 0 summary.codepoint-count))

(fn text-line-first-nonblank [self line]
  (require-logical-buffer-api self :get-line-summary)
  (local summary (self.buffer:get-line-summary line))
  (local first-column (if (= summary.first-nonblank-column nil) 0 summary.first-nonblank-column))
  (local line-size (if (= summary.codepoint-count nil) 0 summary.codepoint-count))
  (if (= first-column line-size) 0 first-column))

(fn text-cursor-line-column [self]
  (local (line column known?) (refresh-logical-caret-state self))
  (if known?
      (values line column)
      (values (if (= self.cursor-line nil) 0 self.cursor-line)
              (if (= self.cursor-column nil) 0 self.cursor-column))))

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
    (keep-caret-visible self)
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
  (require-logical-buffer-api self :byte-for-codepoint-position)
  (apply-caret-byte self (self.buffer:byte-for-codepoint-position position) false))

(fn apply-caret-line-column [self line column extend-selection?]
  (assert (= (type line) :number) "apply-caret-line-column requires line")
  (local anchor (or self.selection-anchor-byte self.buffer.cursor-byte 0))
  (local target-line (math.max 0 line))
  (local target-column (math.max 0 column))
  (local moved (self.buffer:move-caret-to-line-column target-line target-column))
  (if extend-selection?
      (do
        (set self.selection-anchor-byte anchor)
        (self.buffer:set-selection anchor self.buffer.cursor-byte))
      (do
        (set self.selection-anchor-byte self.buffer.cursor-byte)
        (when self.buffer.selection
          (self.buffer:clear-selection))))
  (when moved
    (set-cached-caret! self self.buffer.cursor-byte target-line target-column)
    (when self.buffer.adjacent-codepoint-from-anchor
      (local next-result (self.buffer:adjacent-codepoint-from-anchor (cursor-anchor self) 1))
      (store-row-anchor-column! self target-line target-column self.buffer.cursor-byte (and next-result next-result.bounded? (. next-result :line-end?))))
    (keep-caret-visible self)
    (store-scroll-anchor-from-cursor! self)
    (mark-caret-dirty self)
    (self:refresh-viewport))
  moved)

(fn move-caret-to-line-column [self line column opts]
  (apply-caret-line-column self line column (and opts opts.extend-selection?)))

(fn insert-text [self text]
  (assert (= (type text) :string) "VirtualInput insert-text requires string text")
  (invalidate-anchor-caches! self)
  (when self.buffer.selection
    (if self.buffer.delete-selection
        (self.buffer:delete-selection)
        (error "VirtualInput requires buffer:delete-selection for selected insertion")))
  (local changed (self.buffer:insert-text text))
  (when changed
    (refresh-logical-caret-state self)
    (set self.selection-anchor-byte self.buffer.cursor-byte)
    (notify-change self)
    (keep-caret-visible self)
    (mark-caret-dirty self)
    (self:refresh-viewport))
  changed)

(fn delete-active-selection [self]
  (when (not self.buffer.delete-selection)
    (error "VirtualInput requires buffer:delete-selection for selected delete"))
  (invalidate-anchor-caches! self)
  (local changed (self.buffer:delete-selection))
  (when changed
    (refresh-logical-caret-state self)
    (set self.selection-anchor-byte self.buffer.cursor-byte)
    (notify-change self)
    (keep-caret-visible self)
    (mark-caret-dirty self)
    (self:refresh-viewport))
  changed)

(fn delete-before-cursor [self]
  (if self.buffer.selection
      (delete-active-selection self)
      (do
        (invalidate-anchor-caches! self)
        (local changed (self.buffer:delete-before-cursor))
        (when changed
          (refresh-logical-caret-state self)
          (set self.selection-anchor-byte self.buffer.cursor-byte)
          (notify-change self)
          (keep-caret-visible self)
          (mark-caret-dirty self)
          (self:refresh-viewport))
        changed)))

(fn delete-at-cursor [self]
  (if self.buffer.selection
      (delete-active-selection self)
      (do
        (invalidate-anchor-caches! self)
        (local changed (self.buffer:delete-at-cursor))
        (when changed
          (refresh-logical-caret-state self)
          (set self.selection-anchor-byte self.buffer.cursor-byte)
          (notify-change self)
          (keep-caret-visible self)
          (mark-caret-dirty self)
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
  (local moved (self.buffer:move-caret-horizontal delta))
  (update-horizontal-selection self anchor extend-selection?)
  (when moved
    (refresh-logical-caret-state self)
    (keep-caret-visible self)
    (store-scroll-anchor-from-cursor! self)
    (mark-caret-dirty self)
    (self:refresh-viewport))
  moved)

(fn target-line-anchor [self target-line target-column]
  (local line-end (lookup-line-end-anchor self target-line target-column)) (local preferred (lookup-viewport-row-anchor self target-line target-column))
  (if (and line-end preferred (> preferred.column line-end.column)) line-end preferred preferred
      (do (local scrolled (lookup-viewport-row-anchor self target-line self.scroll-column))
        (if (and line-end scrolled (> scrolled.column line-end.column)) line-end scrolled scrolled
            (do (local line-start (lookup-viewport-row-anchor self target-line 0)) (if line-start line-start line-end))))))

(fn move-caret-horizontal-bounded [self delta opts]
  (when (not self.buffer.adjacent-codepoint-from-anchor)
    (error "VirtualInput requires buffer:adjacent-codepoint-from-anchor for bounded horizontal movement"))
  (local direction (if (< delta 0) -1 1))
  (local result (self.buffer:adjacent-codepoint-from-anchor (cursor-anchor self) direction))
  (local cached-next-line (and (and opts opts.allow-line-cross?) result result.line-end? (> direction 0) (target-line-anchor self (+ result.line 1) 0)))
  (local target-anchor cached-next-line)
  (local line-end-anchor (and (> direction 0) result result.moved? (not (and opts opts.allow-after-line-end?)) (lookup-line-end-anchor self result.line result.column)))
  (local after-line-end? (and (> direction 0) result result.moved? (not (and opts opts.allow-after-line-end?))
                              (or (. result :after-line-end?) (and line-end-anchor (= line-end-anchor.column result.column)))))
  (if (not (and result result.bounded?))
      false
      after-line-end?
      false
      (and (not result.moved?) (not target-anchor))
      false
      (do
        (local anchor (or self.selection-anchor-byte self.buffer.cursor-byte 0))
        (local target (if target-anchor target-anchor result))
        (set-cached-caret! self target.byte target.line target.column) (update-horizontal-selection self anchor (and opts opts.extend-selection?))
        (keep-line-visible self target.line) (keep-column-visible self target.column) (store-scroll-anchor-from-cursor! self) (mark-caret-dirty self) (refresh-anchored-viewport! self)
        true)))

(fn apply-bounded-vertical-result! [self result target-column extend-selection?]
  (local anchor (if (= self.selection-anchor-byte nil)
                  self.buffer.cursor-byte
                  self.selection-anchor-byte))
  (set-cached-caret! self result.byte result.line result.column)
  (set self.__preferred-column target-column)
  (update-horizontal-selection self anchor extend-selection?)
  (keep-line-visible self result.line)
  (keep-column-visible self result.column)
  (store-scroll-anchor-from-cursor! self)
  (mark-caret-dirty self)
  (refresh-anchored-viewport! self)
  true)

(fn move-caret-vertical-bounded [self delta opts]
  (when (not self.buffer.move-to-line-column-from-anchor)
    (error "VirtualInput requires buffer:move-to-line-column-from-anchor for bounded vertical movement"))
  (local target-line (+ (or self.cursor-line 0) delta))
  (if (< target-line 0)
      false
      (do
        (local target-column (or self.__preferred-column self.cursor-column 0))
        (local target-anchor (target-line-anchor self target-line target-column))
        (if (not target-anchor)
            false
            (do
              (local requested-column (if (and (. target-anchor :line-end?)
                                                (> target-column target-anchor.column))
                                        target-anchor.column
                                        target-column))
              (local result (self.buffer:move-to-line-column-from-anchor
                              (cursor-anchor self)
                              target-line
                              requested-column
                              {:max-codepoints (+ (or self.visible-column-count 1) 2)
                               :target-anchor target-anchor}))
              (if (not (and result result.bounded?))
                  false
                  (apply-bounded-vertical-result! self result target-column (and opts opts.extend-selection?))))))))

(fn move-next-word-start [self opts]
  (when (not self.buffer.next-word-start-from-anchor)
    (error "VirtualInput requires buffer:next-word-start-from-anchor for word movement"))
  (local result (self.buffer:next-word-start-from-anchor (cursor-anchor self) opts))
  (if (not (and result result.moved?))
      false
      (do
        (local anchor (or self.selection-anchor-byte self.buffer.cursor-byte 0))
        (set-cached-caret! self result.byte result.line result.column) (set self.__preferred-column result.column)
        (update-horizontal-selection self anchor (and opts opts.extend-selection?))
        (keep-line-visible self result.line)
        (keep-column-visible self result.column)
        (store-scroll-anchor-from-cursor! self)
        (mark-caret-dirty self)
        (refresh-anchored-viewport! self)
        true)))

(fn move-caret [self delta opts]
  (local (line column) (text-cursor-line-column self))
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
      (apply-caret-line-column self line (math.max 0 (- (text-line-length self line) 1)) extend?)
      (error (.. "VirtualInput unsupported caret move: " (tostring delta)))))

(fn scroll-lines [self delta opts]
  (local changed (self.buffer:scroll-lines delta))
  (when changed
    (local extend? (and opts opts.extend-selection?))
    (sync-scroll self)
    (self:refresh-viewport)
    (when (not (caret-row self))
      (apply-caret-line-column self self.scroll-line 0 extend?))
    (keep-caret-visible self)
    (mark-caret-dirty self)
    (self:refresh-viewport))
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
  (if (= self.mode :insert)
      (do
        (when (and payload (= (type payload.text) :string))
          (self:insert-text payload.text))
        true)
      false))
(fn update-caret-visual [self opts]
  (CaretPolicy.apply-caret-visual self opts))

(fn update-focus-visual [self opts]
  (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? true))
  (when self.background
    (set self.background.color (if self.focused? self.colors.focused-background self.colors.background))
    (when (and mark-layout-dirty? self.background.layout)
      (self.background.layout:mark-layout-dirty)))
  (update-caret-visual self {:mark-layout-dirty? mark-layout-dirty?}))
(fn on-key-down [self payload]
  (KeyPolicy.handle-direct-key self payload))

(fn enter-insert-mode [self]
  (set self.mode :insert)
  (update-caret-visual self)
  (mark-caret-dirty self)
  true)

(fn enter-normal-mode [self]
  (set self.mode :normal)
  (update-caret-visual self)
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
                      (do
                        (local size (assert (or self.layout.size self.layout.measure) "VirtualInput click requires measured layout size"))
                        (local top-y (- size.y self.padding.y))
                        (+ 1 (math.floor (/ (math.max 0 (- top-y point.y)) self.line-height))))))
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
(fn row-y-offset [input size visible-row] (assert input "row-y-offset requires input") (assert size "row-y-offset requires size") (- size.y input.padding.y (* visible-row input.line-height)))
(fn caret-row-style [input row]
  (assert input "VirtualInput caret row style requires input")
  (assert row "VirtualInput caret row style requires row")
  (local row-widget (. input.rows (+ (- row.line input.scroll-line) 1)))
  (assert (and row-widget row-widget.style) "VirtualInput caret width requires row text style"))
(fn caret-row-codepoint [input row column]
  (assert input "VirtualInput caret codepoint requires input")
  (assert row "VirtualInput caret codepoint requires row")
  (local codepoints (assert row.codepoints "VirtualInput caret width requires row codepoints"))
  (. codepoints (+ (- column input.scroll-column) 1)))
(fn caret-width-for-mode [input row column]
  (local style (caret-row-style input row))
  (when (and (not (= input.mode :insert)) (not style.font))
    (error "VirtualInput caret width requires row text font"))
  (CaretPolicy.mode-caret-width style
                                (caret-row-codepoint input row column)
                                input.caret-width
                                input.mode))
(fn caret-position [input position rotation size line column] (+ position (rotation:rotate (glm.vec3 (+ input.padding.x (* (- column input.scroll-column) input.column-width)) (row-y-offset input size (+ (- line input.scroll-line) 1)) 0))))
(fn show-caret [input position rotation size depth clip line column]
  (local (_caret-line _caret-column row) (caret-line-column input))
  (assert row "VirtualInput show-caret requires visible caret row")
  (update-caret-visual input {:mark-layout-dirty? false})
  (if input.focused?
      (do
        (layout-child input.caret (caret-position input position rotation size line column) rotation (glm.vec3 (caret-width-for-mode input row column) (CaretPolicy.caret-height input.line-height (- size.y (* 2 input.padding.y))) size.z) depth clip))
      (do
        (set input.caret.visible? false)
        (layout-child input.caret position rotation (glm.vec3 0 0 size.z) depth clip))))
(fn hide-caret [input position rotation size depth clip]
  (set input.caret.visible? false)
  (layout-child input.caret position rotation (glm.vec3 0 0 size.z) depth clip))
(fn layout-caret [input position rotation size depth clip]
  (local (line column row) (caret-line-column input))
  (if (and input.focused?
           row
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
                                                          (row-y-offset input size i)
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
  (FocusPolicy.request-focus self))

(fn on-state-connected [self _event]
  (set self.connected? true))

(fn on-state-disconnected [self _event]
  (FocusPolicy.handle-blur self))

(fn initialize-cached-state! [input]
  (local (_line _column known?) (refresh-logical-caret-state input))
  (when known?
    (keep-line-visible input input.cursor-line)
    (keep-column-visible input input.cursor-column)
    (store-scroll-anchor-from-cursor! input)))

(fn drop [self]
  (assert (not self.__dropped) "VirtualInput dropped twice")
  (set self.__dropped true)
  (FocusPolicy.handle-blur self)
  (FocusPolicy.disconnect-focus-listeners self)
  (self.clickables:unregister self)
  (when self.focus-node
    (self.focus-node:drop)
    (set self.focus-node nil))
  (each [_ row-widget (ipairs self.rows)]
    (row-widget:drop))
  (self.background:drop)
  (self.caret:drop)
  (self.layout:drop))

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
    (local caret ((Rectangle {:color colors.caret-normal}) ctx))
    (caret:set-visible false {:mark-layout-dirty? false})
    (local computed-line-height (CaretPolicy.resolve-line-height text-style 1.6))
    (local computed-column-width (CaretPolicy.resolve-column-width text-style caret-width))
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
         :focused? false
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
        :colors colors
       :scroll-line (math.max 0 (or buffer.scroll-line 0))
        :scroll-column 0
        :viewport nil
        :viewport-anchor-cache {}
        :viewport-row-anchor-cache {}
        :model {}
       :lines []
       :cursor-index 0
       :cursor-line 0
       :cursor-column 0
       :mode :normal
        :multiline? true
        :bounded-logical-navigation? true
        :selection-anchor-byte (or buffer.cursor-byte 0)
       :on-change options.on-change
       :on-save options.on-save
       :on-submit options.on-submit
       :refresh-viewport refresh-viewport
       :insert-text insert-text
        :delete-before-cursor delete-before-cursor
         :delete-at-cursor delete-at-cursor
         :move-caret-to move-caret-to
         :move-caret-to-line-column move-caret-to-line-column
          :move-caret-horizontal-bounded move-caret-horizontal-bounded
          :move-caret-vertical-bounded move-caret-vertical-bounded
          :move-next-word-start move-next-word-start
          :move-caret move-caret
        :scroll-lines scroll-lines
        :text-line-count text-line-count
        :text-line-length text-line-length
        :text-line-first-nonblank text-line-first-nonblank
        :text-cursor-line-column text-cursor-line-column
        :copy-selection copy-selection
       :save save
       :enter-insert-mode enter-insert-mode
       :enter-normal-mode enter-normal-mode
       :submit submit
       :on-text-input on-text-input
       :on-key-down on-key-down
        :on-click on-click
        :request-focus request-focus
        :update-focus-visual update-focus-visual
        :update-caret-visual update-caret-visual
        :on-state-connected on-state-connected
       :on-state-disconnected on-state-disconnected
       :intersect intersect-virtual-input
       :drop drop})
    (set layout.virtual-input input)
    (when (and focus-node focus-context layout)
      (focus-context:attach-bounds focus-node {:layout layout}))
    (FocusPolicy.connect-focus-listeners input)
    (clickables:register input)
    (initialize-cached-state! input)
    (input:refresh-viewport {:mark-layout-dirty? false})
    input))

VirtualInput
