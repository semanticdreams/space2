(local glm (require :glm))
(local LayeredPointBox (require :layered-point-box))
(local Points (require :points))
(local MathUtils (require :math-utils))
(local {:VectorBuffer VectorBuffer} (require :vector-buffer))

(local tests [])
(local approx (. MathUtils :approx))

(fn make-points []
  (local vector (VectorBuffer))
  (local points (Points {:point-vector vector}))
  (values vector points))

(fn build-box [opts]
  (local (_vector points) (make-points))
  (local build (LayeredPointBox opts))
  (build {:points points}))

(fn build-box-from-opts-ctx [opts]
  (local (_vector points) (make-points))
  (local build
    (LayeredPointBox {:ctx {:points points}
                      :reserved-size opts.reserved-size
                      :layers opts.layers}))
  (build))

(fn assert-fails-with [f fragments]
  (local (ok err) (pcall f))
  (assert (not ok) "expected call to fail")
  (each [_ fragment (ipairs fragments)]
    (assert (string.find (tostring err) fragment 1 true)
            (.. "expected error to contain " fragment))))

(fn layered-point-box-measures-reserved-chrome-size []
  (local box
    (build-box {:reserved-size 12
                :layers [{:size 0}
                         {:size 8}
                         {:size 6}]}))
  (box.layout:measurer)
  (assert (approx box.layout.measure.x 12))
  (assert (approx box.layout.measure.y 12))
  (assert (approx box.layout.measure.z 0))
  (box:drop))

(fn layered-point-box-centers-point-in-reserved-box []
  (local box
    (build-box {:reserved-size 12
                :layers [{:size 8}]}))
  (set box.layout.position (glm.vec3 10 -20 0))
  (set box.layout.size (glm.vec3 12 12 0))
  (box.layout:layouter)
  (assert (approx box.point.position.x 16))
  (assert (approx box.point.position.y -14))
  (assert (approx box.point.position.z 0))
  (box:drop))

(fn layered-point-box-builds-from-options-ctx []
  (local box
    (build-box-from-opts-ctx {:reserved-size 12
                              :layers [{:size 8}]}))
  (box.layout:measurer)
  (assert (approx box.layout.measure.x 12))
  (box:drop))

(fn layered-point-box-rejects-layer-sizes-larger-than-reserved-size []
  (local box
    (build-box {:reserved-size 12
                :layers [{:size 8}]}))
  (assert-fails-with (fn [] (box.point:set-layer-size 1 14))
                     ["LayeredPointBox" "reserved size"])
  (assert-fails-with (fn [] (box.point:set-layer 1 {:size 14}))
                     ["LayeredPointBox" "reserved size"])
  (assert-fails-with (fn [] (box.point:set-size 14))
                     ["LayeredPointBox" "reserved size"])
  (box:drop))

(fn layered-point-box-rejects-initial-layer-size-larger-than-reserved-size []
  (assert-fails-with (fn []
                       (build-box {:reserved-size 12
                                   :layers [{:size 14}]}))
                     ["LayeredPointBox" "reserved size"]))

(fn layered-point-box-rejects-initial-default-layer-size-larger-than-reserved-size []
  (assert-fails-with (fn []
                       (build-box {:reserved-size 8
                                   :layers [{}]}))
                     ["LayeredPointBox" "reserved size"]))

(fn layered-point-box-can-update-reserved-size-explicitly []
  (local box
    (build-box {:reserved-size 12
                :layers [{:size 8}]}))
  (box:set-reserved-size 14)
  (box.point:set-layer-size 1 14)
  (box.layout:measurer)
  (assert (approx box.layout.measure.x 14))
  (assert (approx box.layout.measure.y 14))
  (box:drop))

(fn layered-point-box-drops-point-and-layout-once []
  (local box
    (build-box {:reserved-size 12
                :layers [{:size 8}
                         {:size 6}]}))
  (var point-drops 0)
  (each [_ layer (ipairs box.point.layers)]
    (local original-drop layer.point.drop)
    (set layer.point.drop
         (fn [point-self]
           (set point-drops (+ point-drops 1))
           (original-drop point-self))))
  (var layout-drops 0)
  (local original-layout-drop box.layout.drop)
  (set box.layout.drop
       (fn [layout-self]
         (set layout-drops (+ layout-drops 1))
         (original-layout-drop layout-self)))
  (box:drop)
  (box:drop)
  (assert (= point-drops 2))
  (assert (= layout-drops 1)))

(fn layered-point-box-methods-fail-after-drop []
  (local box
    (build-box {:reserved-size 12
                :layers [{:size 8}]}))
  (box:drop)
  (assert-fails-with (fn [] (box:refresh))
                     ["LayeredPointBox" "called after drop"])
  (assert-fails-with (fn [] (box:set-reserved-size 14))
                     ["LayeredPointBox" "called after drop"]))

(table.insert tests {:name "LayeredPointBox measures reserved chrome size"
                     :fn layered-point-box-measures-reserved-chrome-size})
(table.insert tests {:name "LayeredPointBox centers point in reserved box"
                     :fn layered-point-box-centers-point-in-reserved-box})
(table.insert tests {:name "LayeredPointBox builds from options ctx"
                     :fn layered-point-box-builds-from-options-ctx})
(table.insert tests {:name "LayeredPointBox rejects layer sizes larger than reserved size"
                     :fn layered-point-box-rejects-layer-sizes-larger-than-reserved-size})
(table.insert tests {:name "LayeredPointBox rejects initial layer size larger than reserved size"
                     :fn layered-point-box-rejects-initial-layer-size-larger-than-reserved-size})
(table.insert tests {:name "LayeredPointBox rejects initial default layer size larger than reserved size"
                     :fn layered-point-box-rejects-initial-default-layer-size-larger-than-reserved-size})
(table.insert tests {:name "LayeredPointBox can update reserved size explicitly"
                     :fn layered-point-box-can-update-reserved-size-explicitly})
(table.insert tests {:name "LayeredPointBox drops point and layout once"
                     :fn layered-point-box-drops-point-and-layout-once})
(table.insert tests {:name "LayeredPointBox methods fail after drop"
                     :fn layered-point-box-methods-fail-after-drop})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "layered-point-box"
                       :tests tests})))

{:name "layered-point-box"
 :tests tests
 :main main}
