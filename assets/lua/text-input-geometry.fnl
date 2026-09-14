(local glm (require :glm))

(fn layout-size [input]
  (assert input "TextInputGeometry requires input")
  (assert input.layout "TextInputGeometry requires input.layout")
  (assert (or input.layout.size input.layout.measure)
          "TextInputGeometry requires measured layout size")
  (or input.layout.size input.layout.measure))

(fn local-point-from-event [input event]
  (assert input "TextInputGeometry.local-point-from-event requires input")
  (assert event "TextInputGeometry.local-point-from-event requires event")
  (if event.local-point
      event.local-point
      (do
        (assert event.point "TextInputGeometry.local-point-from-event requires event.point or event.local-point")
        (assert input.layout "TextInputGeometry.local-point-from-event requires input.layout")
        (local position (or input.layout.position (glm.vec3 0 0 0)))
        (local rotation (or input.layout.rotation (glm.quat 1 0 0 0)))
        (local inverse (rotation:inverse))
        (inverse:rotate (- event.point position)))))

(fn row-y-offset [size padding line-height visible-row]
  (assert size "TextInputGeometry.row-y-offset requires size")
  (assert padding "TextInputGeometry.row-y-offset requires padding")
  (assert (= (type line-height) :number) "TextInputGeometry.row-y-offset requires line-height")
  (assert (= (type visible-row) :number) "TextInputGeometry.row-y-offset requires visible-row")
  (- size.y padding.y (* visible-row line-height)))

(fn row-index-for-point [input local-point]
  (assert input "TextInputGeometry.row-index-for-point requires input")
  (assert local-point "TextInputGeometry.row-index-for-point requires local-point")
  (assert input.padding "TextInputGeometry.row-index-for-point requires input.padding")
  (assert (= (type input.line-height) :number) "TextInputGeometry.row-index-for-point requires input.line-height")
  (local size (layout-size input))
  (local top-y (- size.y input.padding.y))
  (local raw (if (> input.line-height 0)
               (math.floor (/ (math.max 0 (- top-y local-point.y)) input.line-height))
               0))
  (+ 1 raw))

(fn column-for-x [column-width local-x row-length]
  (assert (= (type column-width) :number) "TextInputGeometry.column-for-x requires column-width")
  (local raw-column (if (> column-width 0)
                      (math.floor (/ (math.max 0 (or local-x 0)) column-width))
                      0))
  (math.max 0 (math.min raw-column (math.max 0 (or row-length 0)))))

(fn screen-point-for-row-column [input visible-row column]
  (assert input "TextInputGeometry.screen-point-for-row-column requires input")
  (assert input.layout "TextInputGeometry.screen-point-for-row-column requires input.layout")
  (assert input.padding "TextInputGeometry.screen-point-for-row-column requires input.padding")
  (assert (= (type input.column-width) :number) "TextInputGeometry.screen-point-for-row-column requires input.column-width")
  (local size (layout-size input))
  (local rotation (or input.layout.rotation (glm.quat 1 0 0 0)))
  (local position (or input.layout.position (glm.vec3 0 0 0)))
  (local local-x (+ input.padding.x (* (+ (math.max 0 (or column 0)) 0.5) input.column-width)))
  (local local-y (+ (row-y-offset size input.padding input.line-height (math.max 1 (or visible-row 1)))
                    (* 0.5 input.line-height)))
  (+ position (rotation:rotate (glm.vec3 local-x local-y 0))))

{:local-point-from-event local-point-from-event
 :row-y-offset row-y-offset
 :row-index-for-point row-index-for-point
 :column-for-x column-for-x
 :screen-point-for-row-column screen-point-for-row-column}
