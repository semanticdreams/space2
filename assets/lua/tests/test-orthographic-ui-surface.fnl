(local Runner (require :tests/runner))
(local glm (require :glm))
(local {: Layout} (require :layout))
(local OrthographicUiSurface (require :orthographic-ui-surface))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn approx= [a b epsilon]
  (<= (math.abs (- a b)) (if (= epsilon nil) 1e-5 epsilon)))

(fn assert-approx [actual expected label]
  (assert (approx= actual expected 1e-4)
          (string.format "%s should be %.4f, got %.4f" label expected actual)))

(fn noop-update [_self]
  nil)

(fn drop-layout-probe [self]
  (set self.dropped? true)
  (when self.layout
    (self.layout:drop)))

(fn render-target-probe-builder [_ctx]
  {:layout nil
   :update noop-update
   :drop noop-update})

(fn mesh-batch-probe-builder [ctx]
  (ctx:register-mesh-batch :mesh-batch-probe)
  {:layout nil
   :update noop-update
   :drop noop-update})

(fn layout-probe-builder [_ctx]
  {:layout (Layout {:name "orthographic-ui-surface-probe"})
   :update noop-update
   :drop drop-layout-probe})

(fn assert-layout-size [layout width height label]
  (assert (= layout.size.x width)
          (string.format "%s width should be %.2f, got %.2f" label width layout.size.x))
  (assert (= layout.size.y height)
          (string.format "%s height should be %.2f, got %.2f" label height layout.size.y)))

(add-test "orthographic surface exposes hud presentation target"
  (fn []
    (local surface (OrthographicUiSurface.create {:viewport {:x 0 :y 0 :width 640 :height 480}}))
    (local entity (surface:build render-target-probe-builder))
    (assert entity "surface should return built entity")
    (surface:update)
    (local target (surface:presentation-target))
    (assert (= target.kind :hud) "surface should present as hud target")
    (assert target.projection "surface target should expose projection")
    (assert (= (length (target:get-render-contexts)) 1)
            "surface target should expose one render context")
    (surface:drop)))

(add-test "orthographic surface scales root layout to viewport world units"
  (fn []
    (local surface (OrthographicUiSurface.create {:viewport {:x 0 :y 0 :width 640 :height 480}}))
    (local entity (surface:build layout-probe-builder))
    (assert-layout-size entity.layout 32 24 "default surface root")
    (surface:update-viewport {:x 0 :y 0 :width 800 :height 600})
    (assert-layout-size entity.layout 40 30 "resized surface root")
    (surface:drop)))

(add-test "orthographic surface projection uses non-inverted y"
  (fn []
    (local surface (OrthographicUiSurface.create {:viewport {:x 0 :y 0 :width 640 :height 480}}))
    (local bottom (* surface.projection (glm.vec4 0 0 0 1)))
    (local top (* surface.projection (glm.vec4 0 24 0 1)))
    (assert (< bottom.y top.y)
            "higher world y should map higher on screen")
    (assert-approx bottom.y -1 "projection bottom y")
    (assert-approx top.y 1 "projection top y")
    (surface:drop)))

(add-test "orthographic surface rejects invalid world scale"
  (fn []
    (each [_ opts (ipairs [{:world-units-per-pixel false}
                           {:world-units-per-pixel 0}
                           {:world-units-per-pixel -1}])]
      (local (ok err) (pcall OrthographicUiSurface.create opts))
      (assert (not ok) "invalid world scale should fail")
      (assert (string.find (tostring err) "world-units-per-pixel" 1 true)
              "invalid world scale error should name world-units-per-pixel"))))

(add-test "orthographic surface rejects invalid viewport dimensions"
  (fn []
    (each [_ viewport (ipairs [{:width false :height 480}
                               {:width 640 :height false}
                               {:w false :h 480}
                               {:w 640 :h false}])]
      (local (ok err) (pcall OrthographicUiSurface.create {:viewport viewport}))
      (assert (not ok) "invalid viewport dimensions should fail")
      (assert (string.find (tostring err) "viewport" 1 true)
              "invalid viewport dimension error should name viewport"))))

(add-test "orthographic surface exposes registered mesh batches through render context"
  (fn []
    (local surface (OrthographicUiSurface.create {}))
    (surface:build mesh-batch-probe-builder)
    (local target (surface:presentation-target))
    (local contexts (target:get-render-contexts))
    (local render-context (. contexts 1))
    (assert render-context.get-mesh-batches
            "surface render context should expose get-mesh-batches")
    (local batches (render-context:get-mesh-batches))
    (assert (= (. batches 1) :mesh-batch-probe)
            "registered mesh batch should be visible through surface render context")
    (surface:drop)))

(add-test "orthographic surface drops previous entity on rebuild"
  (fn []
    (local surface (OrthographicUiSurface.create {}))
    (local first (surface:build layout-probe-builder))
    (local second (surface:build layout-probe-builder))
    (assert first.dropped? "rebuild should drop previous entity")
    (assert (not (= first second)) "rebuild should attach a new entity")
    (surface:drop)
    (assert second.dropped? "surface drop should drop current entity")))

(fn main []
  (Runner.run-tests {:name "orthographic-ui-surface" :tests tests}))

{:main main :tests tests}
