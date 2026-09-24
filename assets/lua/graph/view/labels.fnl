(local glm (require :glm))
(local Utils (require :graph/view/utils))
(local NodeBase (require :graph/node-base))
(local GraphViewLod (require :graph/view/lod))

(local ensure-glm-vec4 Utils.ensure-glm-vec4)
(local truncate-with-ellipsis Utils.truncate-with-ellipsis)
(local wrap-text Utils.wrap-text)
(local node-id NodeBase.node-id)
(local Text (require :text))
(local TextStyle (require :text-style))

(fn clamp [value min-value max-value]
    (math.max min-value (math.min max-value value)))

(fn finite-number? [value]
    (and (= (type value) :number)
         (= value value)
         (not (= value math.huge))
         (not (= value (- math.huge)))))

(fn GraphViewLabels [opts]
    (local options (or opts {}))
    (local ctx options.ctx)
    (assert ctx "GraphViewLabels requires a build context")
    (local label-color (ensure-glm-vec4 options.label-color (glm.vec4 0.6 0.6 0.6 1)))
    (local label-depth-offset (or options.label-depth-offset 1.0))
    (local label-target-pixels (or options.label-target-pixels 10.0))
    (local label-min-scale (or options.label-min-scale 3.0))
    (local label-max-scale 18.0)
    (local label-scale-epsilon (or options.label-scale-epsilon 0.05))
    (local lod (or options.lod
                   (GraphViewLod {:camera options.camera
                                  :surface options.surface
                                  :surface-provider options.surface-provider})))
    (assert (> label-target-pixels 0) "GraphViewLabels label-target-pixels must be > 0")
    (assert (> label-min-scale 0) "GraphViewLabels label-min-scale must be > 0")
    (assert (<= label-min-scale label-max-scale)
            "GraphViewLabels label-min-scale must be <= internal max scale")
    (assert (>= label-scale-epsilon 0) "GraphViewLabels label-scale-epsilon must be >= 0")
    (assert (and lod
                 lod.capture-view-state
                 lod.view-state-changed?
                 lod.target-for-point
                 lod.pixels-per-world-unit-for-point)
            "GraphViewLabels requires a LOD provider with capture-view-state, view-state-changed?, target-for-point, and pixels-per-world-unit-for-point")
    (var last-view-state nil)
    (local labels {})
    (local node-lod {})
    (local node-scale {})

    (fn label-settings [lod]
        (if (= lod 0)
            {:text-length 120 :line-length 30 :fallback-scale 3}
            (= lod 1)
            {:text-length 60 :line-length 20 :fallback-scale 5}
            (= lod 2)
            {:text-length 20 :line-length nil :fallback-scale 8}
            nil))

    (fn label-text [node settings]
        (local compact node.compact-label)
        (if (= compact false) false
            (if settings.line-length
                (wrap-text (truncate-with-ellipsis (or compact node.label (node-id node)) settings.text-length) settings.line-length)
                (truncate-with-ellipsis (or compact node.label (node-id node)) settings.text-length))))

    (fn resolve-label-scale [point settings]
        (local pixels-per-world-unit
          (and point
               point.position
               (lod:pixels-per-world-unit-for-point point.position)))
        (if (and (finite-number? pixels-per-world-unit)
                 (> pixels-per-world-unit 0))
            (clamp (/ label-target-pixels pixels-per-world-unit)
                   label-min-scale
                   label-max-scale)
            settings.fallback-scale))

    (fn place-label [span point]
        (when (and span point)
            (local measure (or span.layout.measure (glm.vec3 0 0 0)))
            (local half-point (/ (or point.size 0.0) 2.0))
            (local offset (glm.vec3 (- (/ measure.x 2.0))
                                (- (+ half-point 1.0 measure.y))
                                0.05))
            (set span.layout.size measure)
            (set span.layout.depth-offset-index label-depth-offset)
            (set span.layout.position (+ point.position offset))
            (set span.layout.rotation (glm.quat 1 0 0 0))
            (span.layout:layouter)))

    (fn drop-label [node]
        (local span (. labels node))
        (when span
            (span:drop))
        (set (. labels node) nil)
        (set (. node-scale node) nil)
        (set (. node-lod node) nil))

    (fn update-node-label [node point force?]
        (local target (lod:target-for-point point.position))
        (local current (. node-lod node))
        (local settings (and (< target 3) (label-settings target)))
        (local next-scale (and settings (resolve-label-scale point settings)))
        (local current-scale (. node-scale node))
        (local scale-changed?
          (and settings
               (or force?
                   (not (finite-number? current-scale))
                   (> (math.abs (- next-scale current-scale))
                      label-scale-epsilon))))
        (when (or force? (not (= target current)) scale-changed?)
            (if (< target 3)
                (do
                    (local text (label-text node settings))
                    (if (= text false)
                        (drop-label node)
                        (do
                            (local existing (. labels node))
                            (var span existing)
                            (if span
                                (do (span:set-text text {:mark-measure-dirty? true}) (set span.style.scale next-scale))
                                (do
                                    (local style (TextStyle {:color label-color :scale next-scale}))
                                    (local builder (Text {:text text :style style}))
                                    (set span (builder ctx)) (set (. labels node) span)))
                            (span.layout:measurer)
                            (place-label span point))))
                (drop-label node))
            (set (. node-scale node) next-scale)
            (set (. node-lod node) target)))

    (fn update [_self points nodes opts]
        (local force? (or (and opts opts.force?) false))
        (local view-state (lod:capture-view-state))
        (var should-run force?)
        (when (not should-run)
            (set should-run (lod:view-state-changed? last-view-state view-state)))
        (when should-run
            (if nodes
                (each [_ node (ipairs nodes)]
                    (local point (. points node))
                    (when point
                        (update-node-label node point force?)))
                (each [node point (pairs points)]
                    (update-node-label node point force?)))
            (set last-view-state view-state)))

    (fn refresh-positions [_self points nodes]
        (local targets (or nodes []))
        (when (not nodes)
            (each [node _ (pairs labels)]
                (table.insert targets node)))
        (each [_ node (ipairs targets)]
            (local span (. labels node))
            (local point (. points node))
            (when (and span point)
                (place-label span point))))

    (fn drop-node [_self node]
        (drop-label node))

    (fn drop-all [_self]
        (each [node span (pairs labels)]
            (when span
                (span:drop))
            (set (. labels node) nil)
            (set (. node-scale node) nil)
            (set (. node-lod node) nil))
        (set last-view-state nil)
        (when (and lod lod.drop)
            (lod:drop)))

    (fn move-label [_self existing node]
        (when (. labels existing)
            (set (. labels node) (. labels existing))
            (set (. labels existing) nil))
        (when (. node-scale existing)
            (set (. node-scale node) (. node-scale existing))
            (set (. node-scale existing) nil))
        (when (. node-lod existing)
            (set (. node-lod node) (. node-lod existing))
            (set (. node-lod existing) nil)))

    (local self {:update update
                 :refresh-positions refresh-positions
                 :drop-node drop-node
                 :drop-all drop-all
                 :move-label move-label
                 :labels labels
                 :node-lod node-lod
                 :lod lod})
    self)

GraphViewLabels
