(local glm (require :glm))
(local LayeredPoint (require :layered-point))
(local {: Layout} (require :layout))
(local Rectangle (require :rectangle))
(local RawRectangle (require :raw-rectangle))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local {: resolve-card-colors : get-button-theme-colors} (require :widget-theme-utils))
(local ViewKindBadge (require :graph/view/kind-badge))

(local default-focus-border-width 0.3)
(local default-selection-border-width 0.5)

(fn compact-point [opts]
  "Create a compact graph node presentation (same LayeredPoint as before)."
  (local options (or opts {}))
  (LayeredPoint {:points options.points
                 :position options.position
                 :pointer-target options.pointer-target
                 :depth-offset-step options.depth-offset-step
                 :base-depth-offset-index options.base-depth-offset-index
                 :base-layer-index options.base-layer-index
                 :layers options.layers}))

(fn card-builder [opts]
  "Returns a builder function (ctx) -> widget for an expanded graph node card.
  The returned widget has .layout (Layout), .position (vec3), .size (number),
  and the standard GraphView point interface including .intersect, .set-position,
  .set-position-values, .set-size, .set-layer-size, .drop, and event handler fields."
  (local options (or opts {}))
  (local node (assert options.node "card-builder requires :node"))
  (local position (or options.position (glm.vec3 0 0 0)))
  (local default-size (or options.default-size options.size (glm.vec3 64.0 48.0 0)))
  (local min-size (or options.min-size default-size))
  (local max-size (or options.max-size default-size))
  (local resize-max-size (or options.resize-max-size max-size))
  (fn finite-number? [v]
    (and (= (type v) :number) (= v v) (not (= v math.huge)) (not (= v (- math.huge)))))
  (fn assert-finite-size [vec label]
    (assert (finite-number? vec.x) (.. label ".x must be finite"))
    (assert (finite-number? vec.y) (.. label ".y must be finite"))
    (assert (finite-number? vec.z) (.. label ".z must be finite")))
  (assert-finite-size min-size "min-size")
  (assert-finite-size max-size "max-size")
  (assert-finite-size resize-max-size "resize-max-size")
  (assert-finite-size default-size "default-size")
  (assert (>= min-size.x 0) "min-size.x must be non-negative")
  (assert (>= min-size.y 0) "min-size.y must be non-negative")
  (assert (>= max-size.x min-size.x) "max-size.x must be >= min-size.x")
  (assert (>= max-size.y min-size.y) "max-size.y must be >= min-size.y")
  (assert (>= resize-max-size.x max-size.x) "resize-max-size.x must be >= max-size.x")
  (assert (>= resize-max-size.y max-size.y) "resize-max-size.y must be >= max-size.y")
  (local selection-color (or options.selection-color (glm.vec4 0.22 0.16 0.08 0.96)))
  (local focus-color (or options.focus-color (glm.vec4 0.08 0.16 0.24 0.96)))
  (local focus-border-width (if (not (= nil options.focus-border-width))
                                options.focus-border-width
                                default-focus-border-width))
  (local selection-border-width (if (not (= nil options.selection-border-width))
                                    options.selection-border-width
                                    default-selection-border-width))
  (assert (finite-number? focus-border-width) "focus-border-width must be a finite number")
  (assert (finite-number? selection-border-width) "selection-border-width must be a finite number")
  (assert (>= focus-border-width 0) "focus-border-width must be non-negative")
  (assert (>= selection-border-width 0) "selection-border-width must be non-negative")
  (local depth-offset-index (or options.depth-offset-index 0))
  (local on-collapse (assert options.on-collapse "card-builder requires :on-collapse"))
  (local on-open (assert options.on-open "card-builder requires :on-open"))
  (local on-menu (assert options.on-menu "card-builder requires :on-menu"))
  (local title-text ((. (require :graph/view/utils) :truncate-with-ellipsis) (tostring (or node.label node.key "node")) 42))
  (fn build-header-bar [ctx]
    (fn title-builder [child-ctx]
      (((require :text) {:text title-text}) child-ctx))
    (fn spacer-builder [_ctx]
      (local layout (Layout {:name "graph-card-header-spacer"
                               :measurer (fn [self] (set self.measure (glm.vec3 0 0 0)))
                               :layouter (fn [_self] nil)}))
      {:layout layout :drop (fn [_self] (layout:drop))})
    (local badge-builder
      (ViewKindBadge.titlebar-builder node.kind-badge {:scale 0.9
                                                       :padding [0.18 0.06]}))
    (local titlebar-children [])
    (when badge-builder
      (table.insert titlebar-children (FlexChild badge-builder 0)))
    (table.insert titlebar-children (FlexChild title-builder 0))
    (table.insert titlebar-children (FlexChild spacer-builder 1))
    (table.insert titlebar-children
                  (FlexChild (Button {:icon "close_fullscreen"
                                      :variant :ghost
                                      :focusable? false :text nil
                                      :on-click (fn [_ _] (on-collapse))}) 0))
    (table.insert titlebar-children
                  (FlexChild (Button {:icon "open_in_new"
                                      :variant :ghost
                                      :focusable? false :text nil
                                      :on-click (fn [_ event] (on-open event))}) 0))
    (table.insert titlebar-children
                  (FlexChild (Button {:icon "more_vert"
                                      :variant :ghost
                                      :focusable? false :text nil
                                      :on-click (fn [_ event] (on-menu event))}) 0))
    ((Flex {:axis 1
            :yalign :center
            :xspacing 0.25
            :children titlebar-children})
      ctx))

  (fn [ctx]
    (assert ctx "card-builder requires ctx")
    (local layout-root (and ctx ctx.layout-root))
    (assert layout-root "card-builder requires ctx.layout-root")
    (local preview-fn (assert (and node node.preview)
                              (.. "Graph card requires node preview for " (or node.key "unknown"))))
    (assert (= (type preview-fn) :function)
            (.. "Graph card preview must be a function for " (or node.key "unknown")))

    (local card-colors (resolve-card-colors ctx options))
    (local resolved-background card-colors.background)

    (fn make-outline-strips [color border-width]
      (local top ((RawRectangle {:color color}) ctx))
      (local bottom ((RawRectangle {:color color}) ctx))
      (local left ((RawRectangle {:color color}) ctx))
      (local right ((RawRectangle {:color color}) ctx))
      (local strips [top bottom left right])
      (var visible? false)

      (fn set-visible [v]
        (local desired (not (not v)))
        (when (not (= visible? desired))
          (set visible? desired)
          (each [_ strip (ipairs strips)]
            (strip:set-visible desired))))

      (fn update [pos card-size depth clip-region]
        (local x pos.x)
        (local y pos.y)
        (local w card-size.x)
        (local h card-size.y)
        (local bw border-width)
        (local doubled (* 2 bw))
        (set top.position (glm.vec3 (- x bw) (+ y h) 0))
        (set top.size (glm.vec2 (+ w doubled) bw))
        (set top.depth-offset-index depth)
        (set top.clip-region clip-region)
        (top:update)
        (set bottom.position (glm.vec3 (- x bw) (- y bw) 0))
        (set bottom.size (glm.vec2 (+ w doubled) bw))
        (set bottom.depth-offset-index depth)
        (set bottom.clip-region clip-region)
        (bottom:update)
        (set left.position (glm.vec3 (- x bw) y 0))
        (set left.size (glm.vec2 bw h))
        (set left.depth-offset-index depth)
        (set left.clip-region clip-region)
        (left:update)
        (set right.position (glm.vec3 (+ x w) y 0))
        (set right.size (glm.vec2 bw h))
        (set right.depth-offset-index depth)
        (set right.clip-region clip-region)
        (right:update))

      (fn drop []
        (each [_ strip (ipairs strips)]
          (strip:drop)))

      {:strips strips
       :visible? (fn [] visible?)
       :set-visible set-visible
       :update update
       :drop drop})

    (local selection-outline (make-outline-strips selection-color selection-border-width))
    (local focus-outline (make-outline-strips focus-color focus-border-width))
    (local background ((Rectangle {:color resolved-background}) ctx))
    (local titlebar-theme-colors (get-button-theme-colors ctx :tertiary)) (local titlebar-background ((Rectangle {:color (or (and titlebar-theme-colors titlebar-theme-colors.background) (glm.vec4 0.2 0.2 0.2 1))}) ctx))
    (local card {:node node
                  :_card-size (glm.vec3 default-size.x default-size.y default-size.z)
                  :_header-height 3.0
                  :_min-size min-size
                  :_max-size max-size
                  :_resize-max-size resize-max-size
                  :_user-size nil
                  :on-click nil
                  :on-double-click nil
                  :on-right-click nil})
    (set card.position (glm.vec3 position.x position.y position.z))
    (set card.size (math.max default-size.x default-size.y))
    (set card.depth-offset-index depth-offset-index)
    (set card._focus-layer-size 0)
    (set card._selection-layer-size 0)
    (set card._background background) (set card.header-titlebar-background titlebar-background)
    (set card._focus-outline focus-outline)
    (set card._selection-outline selection-outline)
    (set card._pointer-target options.pointer-target)
    (when options.requested-size
      (set card._user-size (glm.vec3 (math.max min-size.x (math.min resize-max-size.x options.requested-size.x))
                                      (math.max min-size.y (math.min resize-max-size.y options.requested-size.y))
                                      0)))


    (fn card-origin [size]
      (local resolved (or size card._card-size default-size))
      (glm.vec3 (- card.position.x (/ resolved.x 2.0))
                (- card.position.y (/ resolved.y 2.0))
                (- card.position.z (/ resolved.z 2.0))))
    (local header-bar (build-header-bar ctx))
    (local has-badge? (not (or (= node.kind-badge nil) (= node.kind-badge false))))
    (set card.header-bar header-bar)
    (set card.header-kind-badge (if has-badge? (. header-bar.children 1 :element) nil))
    (set card.header-title (. header-bar.children (if has-badge? 2 1) :element))
    (set card.header-title-text title-text)


    (fn measurer [self]
      (header-bar.layout:measurer)
      (set card._header-height (or header-bar.layout.measure.y 3.0))
      (local child (and card.view-widget card.view-widget.layout))
      (when child
        (local effective-max (if card._user-size card._user-size card._max-size))
        (child:measure-constrained {:max (glm.vec3 effective-max.x
                                                    (math.max 0 (- effective-max.y card._header-height))
                                                    effective-max.z)}))
      (local child-measure (and child child.measure))
      (local desired-y (if child-measure
                           (+ card._header-height child-measure.y)
                           default-size.y))
      (local desired-x (if child-measure
                             (math.max default-size.x child-measure.x header-bar.layout.measure.x)
                             (math.max default-size.x header-bar.layout.measure.x)))
      (set card._card-size
           (if card._user-size
               (glm.vec3 (math.max min-size.x (math.min resize-max-size.x card._user-size.x))
                         (math.max min-size.y (math.min resize-max-size.y card._user-size.y))
                         0)
               (glm.vec3 (math.max min-size.x (math.min max-size.x desired-x))
                         (math.max min-size.y (math.min max-size.y desired-y))
                         0)))
      (set card.size (math.max card._card-size.x card._card-size.y)) (set self.measure card._card-size))

    (fn layouter [self]
      (local header-height card._header-height)
      (set self.size card._card-size)
      (set self.position (card-origin card._card-size))
      (set self.rotation (glm.quat 1 0 0 0))
      (local culled? (self:effective-culled?))
      (when focus-outline
        (local visible? (and (> card._focus-layer-size 0) (not culled?)))
        (focus-outline.set-visible visible?)
        (when visible?
          (focus-outline.update self.position card._card-size (+ self.depth-offset-index 1) self.clip-region)))
      (when selection-outline
        (local show-selection? (and (> card._selection-layer-size 0) (not culled?)))
        (selection-outline.set-visible show-selection?)
        (when show-selection?
          (selection-outline.update self.position card._card-size self.depth-offset-index self.clip-region)))
      (when background
        (set background.layout.position self.position)
        (set background.layout.size card._card-size)
        (set background.layout.rotation (glm.quat 1 0 0 0))
        (set background.layout.depth-offset-index (+ self.depth-offset-index 2))
        (background.layout:layouter true))
      (when titlebar-background (set titlebar-background.layout.position (+ self.position (glm.vec3 0 (- card._card-size.y header-height) 0))) (set titlebar-background.layout.size (glm.vec3 card._card-size.x header-height 0)) (set titlebar-background.layout.rotation (glm.quat 1 0 0 0)) (set titlebar-background.layout.depth-offset-index (+ self.depth-offset-index 3)) (titlebar-background.layout:layouter true))
      (when (and card.header-bar card.header-bar.layout)
        (local header card.header-bar.layout)
        (set header.position (+ self.position (glm.vec3 0 (- card._card-size.y header-height) 0)))
        (set header.size (glm.vec3 card._card-size.x header-height 0))
        (set header.rotation (glm.quat 1 0 0 0))
        (set header.depth-offset-index (+ self.depth-offset-index 3))
        (header:layouter true))
      (when (and card.view-widget card.view-widget.layout)
        (local child card.view-widget.layout)
        (set child.position self.position)
        (set child.size (glm.vec3 card._card-size.x (- card._card-size.y header-height) 0))
        (set child.rotation (glm.quat 1 0 0 0))
        (set child.depth-offset-index (+ self.depth-offset-index 4))
        (child:layouter true))
      (when card._resize-target
        (set card._resize-target.position self.position)
        (set card._resize-target.size card._card-size)
        (set card._resize-target.rotation self.rotation)))

    (local layout
      (Layout {:name (.. "graph-card-" (or node.key "unknown"))
               :measurer measurer
               :layouter layouter}))
    (layout:set-root layout-root)
    (local original-set-self-culled layout.set-self-culled)
    (set layout.set-self-culled
         (fn [self culled?]
           (original-set-self-culled self culled?)
           (when culled?
             (focus-outline.set-visible false)
             (selection-outline.set-visible false))))
    (local original-set-parent-culled layout.set-parent-culled)
    (set layout.set-parent-culled
         (fn [self culled?]
           (original-set-parent-culled self culled?)
           (when culled?
             (focus-outline.set-visible false)
             (selection-outline.set-visible false))))
    (layout:add-child background.layout) (layout:add-child titlebar-background.layout)
    (layout:add-child header-bar.layout)
    (set card.layout layout)
    (set card._resize-target
         {:position layout.position
          :size card._card-size
          :rotation layout.rotation
          :set-transform (fn [self transform]
                          (when transform.size
                            (local clamped-x (math.max min-size.x (math.min resize-max-size.x transform.size.x)))
                            (local clamped-y (math.max min-size.y (math.min resize-max-size.y transform.size.y)))
                            (set self.size (glm.vec3 clamped-x clamped-y 0))
                            (card:set-size self.size))
                          (when transform.position
                            (set self.position (glm.vec3 transform.position.x transform.position.y transform.position.z))
                            (local center-x (+ transform.position.x (/ self.size.x 2)))
                            (local center-y (+ transform.position.y (/ self.size.y 2)))
                            (card:set-position (glm.vec3 center-x center-y 0))))})
    (set layout.position (card-origin card._card-size))
    (set layout.size card._card-size)
    (set layout.measure card._card-size)
    (set layout.depth-offset-index depth-offset-index)

    (set card.set-position
         (fn [_ new-position]
            (set card.position (glm.vec3 new-position.x new-position.y new-position.z))
            (set layout.position (card-origin card._card-size))
            (layout:mark-layout-dirty)))

    (set card.set-position-values
          (fn [_ x y z]
            (card:set-position (glm.vec3 x y z))))

    (set card.set-size
         (fn [_ size]
           (set card._user-size (glm.vec3 (math.max min-size.x (math.min resize-max-size.x size.x))
                                           (math.max min-size.y (math.min resize-max-size.y size.y))
                                           0))
           (layout:mark-measure-dirty)
           (layout:mark-layout-dirty)))

    (set card.set-transform
         (fn [_ transform]
           (when transform.position
             (card:set-position transform.position))
           (when transform.size
             (card:set-size transform.size))))

    (set card.set-layer-size
         (fn [_ idx size]
           (when (= idx 1)
             (set card._focus-layer-size (or size 0))
             (when focus-outline
               (focus-outline.set-visible (and (> card._focus-layer-size 0)
                                               (not (layout:effective-culled?))))))
           (when (= idx 2)
             (set card._selection-layer-size (or size 0))
             (when selection-outline
               (selection-outline.set-visible (and (> card._selection-layer-size 0)
                                                   (not (layout:effective-culled?))))))
           (layout:mark-layout-dirty)))

    (set card.intersect
         (fn [_ ray]
           (layout:intersect ray)))

    (set card.drop
         (fn [_]
            (when card.header-bar
              (when card.header-bar.drop
                (card.header-bar:drop))
              (set card.header-bar nil))
            (when card.view-widget
              (when card.view-widget.drop
                (card.view-widget:drop))
              (set card.view-widget nil))
            (when focus-outline
              (focus-outline.drop))
            (when selection-outline
              (selection-outline.drop))
             (when background
               (background:drop)) (when titlebar-background (titlebar-background:drop))
             (set card._focus-outline nil)
             (set card._selection-outline nil)
             (set card._background nil) (set card.header-titlebar-background nil)
             (layout:drop)))

    (local (ok result)
           (pcall
             (fn []
               (local builder (preview-fn node {:node node}))
               (assert (= (type builder) :function)
                       (.. "Graph card preview must return a builder for " (or node.key "unknown")))
               (local view-widget (builder ctx))
               (assert (and view-widget view-widget.layout)
                       (.. "Graph card preview must return widget with layout for " (or node.key "unknown")))
               (set card.view-widget view-widget)
               (layout:add-child view-widget.layout)
               (layout:mark-measure-dirty)
               (layout:mark-layout-dirty)
               view-widget)))
    (if ok
        result
        (do
          (card:drop)
          (error (.. "Graph card failed to build node preview for "
                     (or node.key "unknown")
                     ": "
                     (tostring result)))))

    card))

{:compact-point compact-point
 :card-builder card-builder}
