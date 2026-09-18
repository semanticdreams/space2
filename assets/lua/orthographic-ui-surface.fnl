(local glm (require :glm))
(local {: LayoutRoot} (require :layout))
(local BuildContext (require :build-context))
(local LightingViewState (require :lighting-view-state))
(local viewport-utils (require :viewport-utils))

(local identity-view (glm.mat4 1))
(local default-viewport {:x 0 :y 0 :width 800 :height 600})
(local default-world-units-per-pixel 0.05)

(fn finite-size [value]
  (assert (or (= value nil) (= (type value) :number))
          "OrthographicUiSurface viewport dimensions must be numeric")
  (math.max (if (= value nil) 0 value) 1))

(fn assert-numeric-viewport-field [viewport field-name]
  (local value (. viewport field-name))
  (assert (or (= value nil) (= (type value) :number))
          "OrthographicUiSurface viewport dimensions must be numeric"))

(fn validate-raw-viewport [viewport]
  (when (= (type viewport) :table)
    (assert-numeric-viewport-field viewport :x)
    (assert-numeric-viewport-field viewport :y)
    (assert-numeric-viewport-field viewport :width)
    (assert-numeric-viewport-field viewport :height)
    (assert-numeric-viewport-field viewport :w)
    (assert-numeric-viewport-field viewport :h)))

(fn resolve-world-units-per-pixel [value]
  (local units (if (= value nil) default-world-units-per-pixel value))
  (assert (and (= (type units) :number) (> units 0))
          "OrthographicUiSurface requires positive :world-units-per-pixel")
  units)

(fn viewport-world-size [viewport world-units-per-pixel]
  (local safe-width (finite-size viewport.width))
  (local safe-height (finite-size viewport.height))
  (glm.vec3 (* safe-width world-units-per-pixel)
            (* safe-height world-units-per-pixel)
            1))

(fn apply-root-layout [self]
  (when (and self.entity self.entity.layout)
    (local root-size (viewport-world-size self.viewport self.world-units-per-pixel))
    (set self.entity.layout.size root-size)
    (set self.entity.layout.position (glm.vec3 0 0 0))
    (self.entity.layout:mark-measure-dirty)))

(fn delegate [method-name field-name]
  (fn [self]
    (local ctx (assert self.build-context "OrthographicUiSurface requires build-context"))
    (local method (and method-name (. ctx method-name)))
    (if method
        (method ctx)
        (. ctx field-name))))

(fn update-viewport [self viewport]
  (local next-viewport (if viewport
                           viewport
                           (if self.viewport
                               self.viewport
                               default-viewport)))
  (validate-raw-viewport next-viewport)
  (local vp (viewport-utils.to-table next-viewport))
  (set self.viewport vp)
  (local world-size (viewport-world-size vp self.world-units-per-pixel))
  (set self.projection (glm.ortho 0 world-size.x 0 world-size.y -100.0 100.0))
  (apply-root-layout self)
  nil)

(fn build [self builder]
  (assert (= (type builder) :function) "OrthographicUiSurface.build requires builder function")
  (when self.entity
    (self:drop))
  (local entity (builder self.build-context))
  (set self.entity entity)
  (when (and entity entity.layout)
    (entity.layout:set-root self.layout-root)
    (apply-root-layout self))
  entity)

(fn update [self]
  (when (and self.entity self.entity.update)
    (self.entity:update))
  (self.layout-root:update))

(fn get-view-matrix [_self]
  identity-view)

(fn get-lighting-view-state [_self]
  (LightingViewState.orthographic (glm.vec3 0 0 -1)))

(fn presentation-target [self]
  (assert self.projection "OrthographicUiSurface presentation target requires projection")
  {:kind :hud
   :surface self
   :projection self.projection
   :get-view-matrix (fn [_target] (self:get-view-matrix))
   :get-lighting-view-state (fn [_target] (self:get-lighting-view-state))
   :get-render-contexts (fn [_target] [self])})

(fn drop [self]
  (when self.entity
    (when self.entity.drop
      (self.entity:drop))
    (set self.entity nil))
  nil)

(fn create [opts]
  (assert (or (= opts nil) (= (type opts) :table))
          "OrthographicUiSurface.create requires table options")
  (local options (or opts {}))
  (local layout-root (LayoutRoot))
  (local build-context (BuildContext {:layout-root layout-root
                                      :quad-unlit? true}))
  (local self {:projection nil
               :viewport default-viewport
               :world-units-per-pixel (resolve-world-units-per-pixel options.world-units-per-pixel)
               :entity nil
               :layout-root layout-root
               :build-context build-context
               :update-viewport update-viewport
               :build build
               :update update
               :get-triangle-vector (delegate nil :triangle-vector)
               :get-triangle-batches (delegate :get-triangle-batches nil)
               :get-line-vector (delegate nil :line-vector)
               :get-point-vector (delegate nil :point-vector)
               :get-line-strips (delegate nil :line-strips)
               :get-image-batches (delegate nil :image-batches)
               :get-mesh-batches (delegate :get-mesh-batches nil)
               :get-instanced-color-mesh-batches (delegate :get-instanced-color-mesh-batches nil)
               :get-quad-draw-list (delegate :get-quad-draw-list nil)
               :get-text-ssbo-draw-list (delegate :get-text-ssbo-draw-list nil)
               :get-view-matrix get-view-matrix
               :get-lighting-view-state get-lighting-view-state
               :presentation-target presentation-target
               :drop drop})
  (self:update-viewport (or options.viewport default-viewport))
  self)

{:create create}
