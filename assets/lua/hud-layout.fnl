(local glm (require :glm))
(local {: Layout} (require :layout))
(local {: Flex : FlexChild} (require :flex))
(local Stack (require :stack))
(local Tiles (require :tiles))
(local FloatLayer (require :float-layer))
(local ControlPanel (require :hud-control-panel))
(local StatusPanel (require :hud-status-panel))

(local default-world-scale 0.05)
(local panel-depth-layer-step 8)
(local tiles-depth-layer-step 0)

(fn hud-content-width [hud]
  (local target (or hud {}))
  (local units-per-pixel (or target.world-units-per-pixel default-world-scale))
  (local margin-px (or target.margin-px 0))
  (local margin (* units-per-pixel margin-px))
  (local half-width (or target.half-width 0))
  (math.max 0.001 (- (* half-width 2) (* margin 2))))

(fn hud-content-height [hud]
  (local target (or hud {}))
  (local units-per-pixel (or target.world-units-per-pixel default-world-scale))
  (local margin-px (or target.margin-px 0))
  (local margin (* units-per-pixel margin-px))
  (local half-height (or target.half-height 0))
  (math.max 0.001 (- (* half-height 2) (* margin 2))))

(fn FullWidth [opts]
  (assert opts.child "FullWidth requires :child")
  (fn build [ctx]
    (local child (opts.child ctx))
    (local hud (or opts.hud ctx.pointer-target))

    (fn resolve-width []
      (local width (hud-content-width hud))
      (if (and opts.min-width (< width opts.min-width))
          opts.min-width
          width))

    (fn measurer [self]
      (child.layout:measurer)
      (local child-measure child.layout.measure)
      (local width (resolve-width))
      (local height (. child-measure 2))
      (local depth (. child-measure 3))
      (set self.measure (glm.vec3 width height depth)))

    (fn layouter [self]
      (set self.size self.measure)
      (set child.layout.size self.size)
      (set child.layout.position self.position)
      (set child.layout.rotation self.rotation)
      (set child.layout.depth-offset-index self.depth-offset-index)
      (set child.layout.clip-region self.clip-region)
      (child.layout:layouter))

    (local layout
      (Layout {:name (or opts.name "full-width")
               : measurer : layouter
               :children [child.layout]}))

    (fn drop [self]
      (self.layout:drop)
      (child:drop))

    {: child
     : layout
     :drop drop
     :update (fn [_self]
               (when (and child child.update)
                 (child:update)))}))

(fn make-overlay-root []
  (fn build [_ctx]
    (local depth-layer-step panel-depth-layer-step)
    (local overlay {:children []})

    (fn measurer [self]
      (set self.measure (glm.vec3 0))
      (each [_ metadata (ipairs overlay.children)]
        (local child (and metadata metadata.element))
        (local layout (and child child.layout))
        (when layout
          (layout:measurer)
          (for [axis 1 3]
            (when (> (. layout.measure axis) (. self.measure axis))
              (set (. self.measure axis) (. layout.measure axis)))))))

    (fn layouter [self]
      (each [idx metadata (ipairs overlay.children)]
        (local child (and metadata metadata.element))
        (local layout (and child child.layout))
        (when layout
          (set layout.size (if metadata.fill-parent? self.size (or metadata.size layout.measure layout.size)))
          (local offset (or metadata.position (glm.vec3 0 0 0)))
          (local rotation (or metadata.rotation (glm.quat 1 0 0 0)))
          (local depth-offset-index
            (+ self.depth-offset-index
               (or metadata.depth-offset-index 0)
               (* (- idx 1) depth-layer-step)))
          (set layout.position (+ self.position (self.rotation:rotate offset)))
          (set layout.rotation (* self.rotation rotation))
          (set layout.depth-offset-index depth-offset-index)
          (set layout.clip-region self.clip-region)
          (layout:layouter))))

    (local layout
      (Layout {:name "hud-overlay"
               :children []
               :measurer measurer
               :layouter layouter}))

    (fn drop [_self]
      (layout:drop)
      (each [_ metadata (ipairs overlay.children)]
        (when (and metadata metadata.element metadata.element.drop)
          (metadata.element:drop)))
      (set overlay.children []))

    (set overlay.layout layout)
    (set overlay.drop drop)
    overlay))

(fn maybe-update [widget]
  (when (and widget widget.update)
    (widget:update)))

(fn build-scene-stack [ctx tiles float snackbar-host middle-overlay]
  (local children [(fn [_ctx] tiles)
                   (fn [_ctx] float)])
  (when snackbar-host
    (table.insert children (fn [_ctx] snackbar-host)))
  (table.insert children (fn [_ctx] middle-overlay))
  ((Stack {:depth-offset-step panel-depth-layer-step
           :children children})
   ctx))

(fn build-hud-entity [ctx parts]
  (local control (parts.control-wrapper ctx))
  (local status (parts.status-wrapper ctx))
  (local tiles (parts.tiles-root ctx))
  (local float (parts.float-root ctx))
  (local overlay (parts.overlay-root ctx))
  (local middle-overlay (parts.middle-overlay-root ctx))
  (local left-dock (and parts.left-dock-builder (parts.left-dock-builder ctx)))
  (local right-dock (and parts.right-dock-builder (parts.right-dock-builder ctx)))
  (local top-toolbar (and parts.top-toolbar-builder (parts.top-toolbar-builder ctx)))
  (local snackbar-host (and parts.snackbar-host-builder (parts.snackbar-host-builder ctx)))
  (local hud (assert ctx.pointer-target "HudLayout requires ctx.pointer-target"))
  (local scene-stack (build-scene-stack ctx tiles float snackbar-host middle-overlay))
  (local center-children [])
  (when top-toolbar
    (table.insert center-children (FlexChild (fn [_ctx] top-toolbar))))
  (table.insert center-children (FlexChild (fn [_ctx] scene-stack) 1))
  (local center-column
    ((Flex {:axis 2
            :xalign :stretch
            :yspacing 0
            :children center-children})
     ctx))
  (local base-children [])
  (when left-dock
    (table.insert base-children (FlexChild (fn [_ctx] left-dock))))
  (table.insert base-children (FlexChild (fn [_ctx] center-column) 1))
  (when right-dock
    (table.insert base-children (FlexChild (fn [_ctx] right-dock))))
  (local middle-base
    ((Flex {:axis 1
            :xspacing 0
            :yalign :stretch
            :children base-children})
     ctx))
  (local bands
    ((Flex {:axis 2
            :xalign :stretch
            :yspacing 0
            :children [(FlexChild (fn [_ctx] control))
                       (FlexChild (fn [_ctx] middle-base) 1)
                       (FlexChild (fn [_ctx] status))]})
     ctx))

  (fn measurer [self]
    (bands.layout:measurer)
    (overlay.layout:measurer)
    (local width (hud-content-width hud))
    (local height (hud-content-height hud))
    (local depth (math.max (. bands.layout.measure 3)
                           (. overlay.layout.measure 3)))
    (set self.measure (glm.vec3 width height depth)))

  (fn layouter [self]
    (set self.size self.measure)
    (local base-position self.position)
    (set bands.layout.size self.size)
    (set bands.layout.position base-position)
    (set bands.layout.rotation self.rotation)
    (set bands.layout.clip-region self.clip-region)
    (set bands.layout.depth-offset-index self.depth-offset-index)
    (bands.layout:layouter)
    (set overlay.layout.size self.size)
    (set overlay.layout.position base-position)
    (set overlay.layout.rotation self.rotation)
    (set overlay.layout.clip-region self.clip-region)
    (set overlay.layout.depth-offset-index (+ self.depth-offset-index 64))
    (overlay.layout:layouter))

  (local layout
    (Layout {:name "hud-panels"
             :measurer measurer
             :layouter layouter
             :children [bands.layout overlay.layout]}))

  (fn update [_self]
    (maybe-update control)
    (maybe-update status)
    (maybe-update top-toolbar)
    (maybe-update tiles)
    (maybe-update float)
    (maybe-update snackbar-host)
    (maybe-update left-dock)
    (maybe-update right-dock)
    (maybe-update overlay))

  (fn drop [self]
    (self.layout:drop)
    (bands:drop)
    (overlay:drop)
    (when top-toolbar
      (top-toolbar:drop)))

  {:layout layout
   :update update
   :bands-root bands
   :middle-root scene-stack
   :control-root control
   :status-root status
   :tiles-root tiles
   :float-root float
   :snackbar-host-root snackbar-host
   :left-dock-root left-dock
   :right-dock-root right-dock
   :middle-overlay-root middle-overlay
   :overlay-root overlay
   :top-toolbar-root top-toolbar
   :drop drop})

(fn make-hud-builder [opts]
  (local options (if opts opts {}))
  (local control-panel-opts (if options.control-panel-opts options.control-panel-opts {}))
  (local status-panel-opts (if options.status-panel-opts options.status-panel-opts {}))
  (local control-builder (if options.control-builder
                             options.control-builder
                             (ControlPanel control-panel-opts)))
  (local status-builder (if options.status-builder
                            options.status-builder
                            (StatusPanel status-panel-opts)))
  (local tiles-root (Tiles {:rows 4
                            :columns 4
                            :xspacing 0
                            :yspacing 0
                            :depth-layer-step tiles-depth-layer-step}))
  (local float-root (FloatLayer {:depth-layer-step panel-depth-layer-step}))
  (local overlay-root (make-overlay-root))
  (local middle-overlay-root (make-overlay-root))
  (local left-dock-builder options.left-dock-builder)
  (local right-dock-builder options.right-dock-builder)
  (local top-toolbar-builder options.top-toolbar-builder)
  (local snackbar-host-builder options.snackbar-host-builder)
  (local control-wrapper (FullWidth {:name "control-panel-wrapper"
                                      :child control-builder}))
  (local status-wrapper (FullWidth {:name "status-panel-wrapper"
                                     :child status-builder}))
  (fn build [ctx]
    (build-hud-entity ctx {:control-wrapper control-wrapper
                           :status-wrapper status-wrapper
                           :tiles-root tiles-root
                           :float-root float-root
                           :overlay-root overlay-root
                           :middle-overlay-root middle-overlay-root
                           :left-dock-builder left-dock-builder
                           :right-dock-builder right-dock-builder
                           :top-toolbar-builder top-toolbar-builder
                           :snackbar-host-builder snackbar-host-builder})))

{:FullWidth FullWidth
 :make-overlay-root make-overlay-root
 :make-hud-builder make-hud-builder}
