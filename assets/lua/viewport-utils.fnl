(local glm (require :glm))
(local number-or
  (fn [value fallback]
    (if (not (= value nil)) value fallback)))

(fn to-table [data]
  (if (not data)
      {:x 0 :y 0 :width 0 :height 0}
      (if (= (type data) "userdata")
          {:x data.x
           :y data.y
           :width data.z
           :height data.w}
          {:x (number-or (or data.x data.x) 0)
           :y (number-or (or data.y data.y) 0)
           :width (number-or (or data.width data.w data.width data.w) 0)
           :height (number-or (or data.height data.h data.height data.h) 0)})))

(fn to-glm-vec4 [viewport]
  (glm.vec4 viewport.x viewport.y viewport.width viewport.height))

(fn input-pos->viewport-pos [pos viewport engine]
  (if (not pos)
      nil
      (do
        (local px (number-or pos.x viewport.x))
        (local py (number-or pos.y viewport.y))
        (local logical-width (or (and engine engine.width) 0))
        (local logical-height (or (and engine engine.height) 0))
        (if (and (> logical-width 0)
                 (> logical-height 0)
                 (> viewport.width 0)
                 (> viewport.height 0)
                 (or (not (= logical-width viewport.width))
                     (not (= logical-height viewport.height))))
            {:x (+ viewport.x (* (/ (- px viewport.x) logical-width) viewport.width))
             :y (+ viewport.y (* (/ (- py viewport.y) logical-height) viewport.height))}
            {:x px :y py}))))

(fn viewport-pos->input-pos [pos viewport engine]
  (assert pos "viewport-pos->input-pos requires a position")
  (assert viewport "viewport-pos->input-pos requires a viewport")
  (local px (if (not (= pos.x nil)) pos.x viewport.x))
  (local py (if (not (= pos.y nil)) pos.y viewport.y))
  (local logical-width (if (and engine engine.width) engine.width 0))
  (local logical-height (if (and engine engine.height) engine.height 0))
  (if (and (> logical-width 0)
           (> logical-height 0)
           (> viewport.width 0)
           (> viewport.height 0)
           (or (not (= logical-width viewport.width))
               (not (= logical-height viewport.height))))
      {:x (+ viewport.x (* (/ (- px viewport.x) viewport.width) logical-width))
       :y (+ viewport.y (* (/ (- py viewport.y) viewport.height) logical-height))}
      {:x px :y py}))

{:to-table to-table
  :to-glm-vec4 to-glm-vec4
  :input-pos->viewport-pos input-pos->viewport-pos
  :viewport-pos->input-pos viewport-pos->input-pos}
