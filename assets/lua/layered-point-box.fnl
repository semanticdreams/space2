(local glm (require :glm))
(local {: Layout} (require :layout))
(local LayeredPoint (require :layered-point))

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn assert-reserved-size [size]
  (assert (and (finite-number? size) (> size 0))
          "LayeredPointBox requires positive finite reserved size")
  size)

(fn resolved-layer-size [size]
  (if (= size nil)
      10.0
      size))

(fn LayeredPointBox [opts]
  (local options (or opts {}))
  (assert options.layers "LayeredPointBox requires layers")
  (local initial-reserved-size (assert-reserved-size options.reserved-size))

  (fn build [ctx]
    (local effective-ctx (if ctx ctx options.ctx))
    (local points (if options.points
                      options.points
                      (and effective-ctx effective-ctx.points)))
    (assert points "LayeredPointBox requires points")
    (local point
      (LayeredPoint {:points points
                     :ctx effective-ctx
                     :position options.position
                     :pointer-target options.pointer-target
                     :depth-offset-step options.depth-offset-step
                     :base-depth-offset-index options.base-depth-offset-index
                     :base-layer-index options.base-layer-index
                     :layers options.layers}))
    (local self {:point point
                 :reserved-size initial-reserved-size
                 :dropped? false})

    (fn assert-not-dropped []
      (when self.dropped?
        (error "LayeredPointBox called after drop")))

    (fn assert-size-within-reserved [size]
      (assert-not-dropped)
      (local resolved (resolved-layer-size size))
      (when (> resolved self.reserved-size)
        (error (string.format "LayeredPointBox layer size %s exceeds reserved size %s"
                              (tostring resolved)
                              (tostring self.reserved-size))))
      resolved)

    (local point-set-size point.set-size)
    (local point-set-layer point.set-layer)
    (local point-set-layer-size point.set-layer-size)

    (set point.set-size
         (fn [point-self size]
           (assert-not-dropped)
           (assert-size-within-reserved size)
           (point-set-size point-self size)))
    (set point.set-layer
         (fn [point-self idx params]
           (assert-not-dropped)
           (when (and params (not (= params.size nil)))
             (assert-size-within-reserved params.size))
           (point-set-layer point-self idx params)))
    (set point.set-layer-size
         (fn [point-self idx size]
           (assert-not-dropped)
           (assert-size-within-reserved size)
           (point-set-layer-size point-self idx size)))

    (fn measurer [layout]
      (set layout.measure (glm.vec3 self.reserved-size self.reserved-size 0)))

    (fn layouter [layout]
      (local position layout.position)
      (local size layout.size)
      (self.point:set-position-values (+ position.x (/ size.x 2))
                                      (+ position.y (/ size.y 2))
                                      position.z))

    (set self.layout (Layout {:name (or options.name "layered-point-box")
                              :measurer measurer
                              :layouter layouter}))
    (set self.refresh (fn [self]
                        (assert-not-dropped)
                        (self.layout:mark-layout-dirty)
                        self))
    (set self.set-reserved-size
         (fn [self size]
           (assert-not-dropped)
           (set self.reserved-size (assert-reserved-size size))
           (self.layout:mark-measure-dirty)
           (self.layout:mark-layout-dirty)
           self))
    (set self.drop
         (fn [self]
           (when (not self.dropped?)
             (set self.dropped? true)
             (self.point:drop)
             (self.layout:drop))))
    self)
  build)

LayeredPointBox
