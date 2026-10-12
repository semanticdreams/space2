(local glm (require :glm))
(local {: Layout} (require :layout))
(local Text (require :text))
(local TextStyle (require :text-style))
(local CompactNodeProjection (require :graph/view/compact-node-projection))
(local GraphNodePresentation (require :graph/view/presentation))

(local defaults {:left-padding 12
                 :depth-indent 18
                 :label-gap 1
                 :vertical-padding 1
                 :expanded-gap 3
                 :focus-border-width 1.5
                 :selection-border-width 2.0})

(fn option-or [value fallback]
  (if (= value nil) fallback value))

(fn default-vec4 [value fallback]
  (if (= value nil) fallback value))

(fn row-title [row]
  (if (and row row.node row.node.label)
      row.node.label
      (if (and row row.key) row.key "")))

(fn node-size [row]
  (local size (assert (and row row.node row.node.size)
                      "OutlineRowWidget requires row.node.size"))
  (assert (> size 0) "OutlineRowWidget requires positive row.node.size")
  size)

(fn node-color [row]
  (assert (and row row.node row.node.color)
          "OutlineRowWidget requires row.node.color"))

(fn selected? [state]
  (not (not (state.opts.selected? state.row state.opts.owner))))

(fn focused? [state]
  (not (not (state.opts.focused? state.row state.opts.owner))))

(fn focus-color [state]
  (default-vec4 state.opts.focus-outline-color (glm.vec4 0.2 0.6 1 1)))

(fn selection-color [state]
  (default-vec4 state.opts.selection-border-color (glm.vec4 1 0.6 0.2 1)))

(fn row-depth [row]
  (if (= row.depth nil) 0 row.depth))

(fn point-x [state]
  (+ state.left-padding (* state.depth-indent (row-depth state.row))))

(fn selected-layer-size [state base-size]
  (if (selected? state)
      (+ base-size defaults.selection-border-width)
      0))

(fn focus-layer-size [state base-size]
  (if (focused? state)
      (+ base-size
         (if (selected? state) defaults.selection-border-width 0)
         defaults.focus-border-width)
      0))

(fn projection-layers [state]
  (local base-size (node-size state.row))
  [{:size (focus-layer-size state base-size) :color (focus-color state)}
   {:size (selected-layer-size state base-size) :color (selection-color state)}
   {:size base-size :color (node-color state.row)}])

(fn assert-options [opts]
  (assert opts "OutlineRowWidget requires opts")
  (assert opts.ctx "OutlineRowWidget requires :ctx")
  (assert (and opts.row opts.row.node) "OutlineRowWidget requires row.node")
  (assert opts.clickables "OutlineRowWidget requires :clickables")
  (assert opts.selector "OutlineRowWidget requires :selector")
  (assert opts.focus "OutlineRowWidget requires :focus")
  (assert opts.pointer-target "OutlineRowWidget requires :pointer-target")
  (assert opts.selected? "OutlineRowWidget requires :selected? predicate")
  (assert opts.focused? "OutlineRowWidget requires :focused? predicate")
  opts)

(fn make-label [state]
  (local ctx state.ctx)
  (local theme-color (and ctx.theme ctx.theme.graph ctx.theme.graph.label-color))
  ((Text {:text (row-title state.row)
          :style (TextStyle {:theme ctx.theme
                             :color (default-vec4 state.opts.label-color theme-color)
                             :scale (option-or state.opts.label-scale 1)})})
   ctx))

(fn projection-options [state position]
  {:points (assert state.ctx.points "OutlineRowWidget requires ctx.points")
   :node state.row.node
   :position position
   :pointer-target state.pointer-target
   :depth-offset-step 1
   :base-depth-offset-index 2
   :base-layer-index 3
   :focus-layer-index 1
   :selection-layer-index 2
   :focus-border-width defaults.focus-border-width
   :selection-border-width defaults.selection-border-width
   :clickables (assert state.clickables "OutlineRowWidget projection requires clickables")
   :selector state.selector
   :focus state.focus
   :focus-node state.focus-node
   :drop-focus-node? true
   :layers (projection-layers state)
   :selected? (selected? state)
   :focused? (focused? state)
    :owner (or state.opts.owner state.self)
   :on-focus state.opts.on-focus
   :on-right-click state.opts.on-right-click
   :on-activate state.opts.on-activate})

(fn attach-compact! [state position]
  (set state.projection (CompactNodeProjection.attach! (projection-options state position)))
  (set state.compact-point state.projection.point)
  (set state.focus-node state.projection.focus-node)
  (set state.selectable state.projection.selectable)
  (set state.compact-projection-dropped? false)
  (set state.self.point state.compact-point)
  (set state.self.focus-node state.focus-node)
  (set state.self.selectable state.selectable))

(fn mark-dirty [layout]
  (layout:mark-measure-dirty)
  (layout:mark-layout-dirty))

(fn compact-height [state]
  (state.label.layout:measurer)
  (+ (math.max (CompactNodeProjection.visible-size state.compact-point)
               state.label.layout.measure.y)
     (* 2 state.vertical-padding)))

(fn measure-row [state layout]
  (local summary-height (compact-height state))
  (var width (+ (point-x state)
                (/ (CompactNodeProjection.visible-size state.compact-point) 2.0)
                state.label-gap
                state.label.layout.measure.x))
  (var height summary-height)
  (when state.expanded-card
    (state.expanded-card.layout:measurer)
    (set width (math.max width state.expanded-card.layout.measure.x))
    (set height (+ height state.expanded-gap state.expanded-card.layout.measure.y)))
  (set layout.measure (glm.vec3 width height 0)))

(fn place-label! [state]
  (local point state.compact-point)
  (state.label.layout:measurer)
  (set state.label.layout.position
       (glm.vec3 (+ point.position.x (/ (CompactNodeProjection.visible-size point) 2.0) state.label-gap)
                 (- point.position.y (/ state.label.layout.measure.y 2.0))
                 0.02))
  (set state.label.layout.rotation (glm.quat 1 0 0 0))
  (set state.label.layout.depth-offset-index 1)
  (state.label.layout:layouter))

(fn layout-row [state layout]
  (local summary-height (compact-height state))
  (local visible-height (- summary-height (* 2 state.vertical-padding)))
  (local center-y (- (+ layout.position.y layout.size.y)
                     state.vertical-padding
                     (/ visible-height 2.0)))
  (state.compact-point:set-position (glm.vec3 (point-x state) center-y 0))
  (place-label! state)
  (when state.expanded-card
    (state.expanded-card.layout:measurer)
    (local card-height state.expanded-card.layout.measure.y)
    (set state.expanded-card.layout.position
         (glm.vec3 layout.position.x
                   (- (+ layout.position.y layout.size.y) summary-height state.expanded-gap card-height)
                   layout.position.z))
    (set state.expanded-card.layout.size (glm.vec3 layout.size.x card-height layout.size.z))
    (set state.expanded-card.layout.rotation layout.rotation)
    (state.expanded-card.layout:layouter)))

(fn refresh! [state]
  (when state.dropped?
    (error "OutlineRowWidget method called after drop"))
  (when (and state.projection (not state.compact-projection-dropped?))
    (CompactNodeProjection.refresh! state.projection {:selected? (selected? state)
                                                      :focused? (focused? state)}))
  (when state.expanded-card
    (local base-size (node-size state.row))
    (state.expanded-card:set-layer-size 1 (focus-layer-size state base-size))
    (state.expanded-card:set-layer-size 2 (selected-layer-size state base-size)))
  (mark-dirty state.layout)
  state.self)

(fn card-size [state key fallback]
  (option-or (. state.opts key) fallback))

(fn card-collapse-callback [state]
  (fn []
    (local handled? (and state.opts.on-collapse
                         (state.opts.on-collapse state.row.node {:owner (if state.opts.owner state.opts.owner state.self)})))
    (when (not handled?)
      (state.self:collapse!))))

(fn card-open-callback [state]
  (fn [event]
    (when state.opts.on-open
      (state.opts.on-open state.row.node event {:owner (if state.opts.owner state.opts.owner state.self)}))))

(fn card-menu-callback [state]
  (fn [event]
    (when state.opts.on-menu
      (state.opts.on-menu state.row.node event {:owner (if state.opts.owner state.opts.owner state.self)}))))

(fn expanded-card-click-callback [state]
  (fn [_card _event]
    (when state.focus-node
      (state.focus-node:request-focus {:reason :pointer :owner state.self}))))

(fn build-card [state]
  (local builder (GraphNodePresentation.card-builder
                   {:node state.row.node
                    :position state.compact-point.position
                    :default-size (card-size state :expanded-card-size (glm.vec3 64 20 0))
                    :min-size (card-size state :expanded-card-min-size (glm.vec3 16 16 0))
                    :max-size (card-size state :expanded-card-max-size (glm.vec3 640 480 0))
                    :resize-max-size (card-size state :expanded-card-resize-max-size (glm.vec3 640 480 0))
                    :depth-offset-index 2
                    :selection-color (selection-color state)
                    :focus-color (focus-color state)
                    :pointer-target state.pointer-target
                    :on-collapse (card-collapse-callback state)
                    :on-open (card-open-callback state)
                    :on-menu (card-menu-callback state)}))
  (builder state.ctx))

(fn unregister-expanded-card! [state]
  (when state.expanded-card
    (local clickables (assert state.clickables "OutlineRowWidget expanded card unregister requires clickables"))
    (when clickables.unregister
      (clickables:unregister state.expanded-card))
    (state.selector:remove-selectables [state.expanded-card])
    (state.expanded-card:drop)
    (set state.expanded-card nil)
    (set state.self.expanded-card nil)
    (when (not state.dropped?)
      (state.layout:set-children [state.label.layout]))))

(fn expand! [state]
  (when state.dropped?
    (error "OutlineRowWidget method called after drop"))
  (if state.expanded-card
      true
      (do
        (local clickables (assert state.clickables "OutlineRowWidget expand requires clickables"))
        (local previous-selectable state.selectable)
        (local next-card (build-card state))
        (CompactNodeProjection.drop! state.projection {:remove-selectable? false
                                                       :drop-focus-node? false
                                                       :drop-point? false})
        (set state.compact-projection-dropped? true)
        (set state.expanded-card next-card)
        (set state.self.expanded-card state.expanded-card)
        (set state.expanded-card.on-click (expanded-card-click-callback state))
        (set state.expanded-card.key state.row.key)
        (set state.expanded-card.node state.row.node)
        (clickables:register state.expanded-card)
        (state.selector:replace-selectable previous-selectable state.expanded-card)
        (set state.selectable state.expanded-card)
        (set state.self.selectable state.selectable)
        (when state.focus-node
          (set state.focus-node.presentation state.expanded-card))
        (state.layout:add-child state.expanded-card.layout)
        (refresh! state)
        true)))

(fn restore-compact! [state]
  (when state.compact-projection-dropped?
    (local position state.compact-point.position)
    (state.compact-point:drop)
    (attach-compact! state position)))

(fn collapse! [state]
  (when state.dropped?
    (error "OutlineRowWidget method called after drop"))
  (when state.expanded-card
    (unregister-expanded-card! state)
    (restore-compact! state)
    (refresh! state))
  true)

(fn drop! [state]
  (when (not state.dropped?)
    (set state.dropped? true)
    (if state.expanded-card
        (do
          (unregister-expanded-card! state)
          (when state.focus-node
            (state.focus-node:drop))
          (state.compact-point:drop))
        (when state.projection
          (CompactNodeProjection.drop! state.projection)))
    (state.label:drop)
    (state.layout:drop)))

(fn make-state [opts build-ctx]
  (local ctx (assert (if (= opts.ctx nil) build-ctx opts.ctx)
                     "OutlineRowWidget requires build ctx"))
  {:opts opts
   :ctx ctx
   :row opts.row
   :clickables (assert opts.clickables "OutlineRowWidget state requires clickables")
   :selector opts.selector
   :focus opts.focus
   :pointer-target opts.pointer-target
   :left-padding (option-or opts.left-padding defaults.left-padding)
   :depth-indent (option-or opts.depth-indent defaults.depth-indent)
   :label-gap (option-or opts.label-gap defaults.label-gap)
   :vertical-padding (option-or opts.vertical-padding defaults.vertical-padding)
   :expanded-gap (option-or opts.expanded-gap defaults.expanded-gap)
   :projection nil
   :label nil
   :layout nil
   :self nil
   :compact-point nil
   :focus-node nil
   :selectable nil
   :expanded-card nil
   :compact-projection-dropped? false
   :dropped? false})

(fn set-row! [state next-row]
  (assert (and next-row next-row.node) "OutlineRowWidget set-row requires row.node")
  (when (or (not (= next-row.key state.row.key))
            (not (= next-row.node state.row.node)))
    (error "OutlineRowWidget set-row does not support node/key change"))
  (set state.row next-row)
  (state.label:set-text (row-title state.row))
  (refresh! state))

(fn expanded-query [state]
  (when state.dropped?
    (error "OutlineRowWidget method called after drop"))
  (not (= state.expanded-card nil)))

(fn make-row-self [state layout]
  {:layout layout
   :refresh (fn [_self] (refresh! state))
   :set-row (fn [_self next-row] (set-row! state next-row))
   :point nil
   :selectable nil
   :focus-node nil
   :label nil
   :expanded-card nil
   :expanded? (fn [_self] (expanded-query state))
   :expand! (fn [_self] (expand! state))
   :collapse! (fn [_self] (collapse! state))
   :drop (fn [_self] (drop! state))})

(fn layout-measurer-callback [state]
  (fn [self]
    (measure-row state self)))

(fn layout-layouter-callback [state]
  (fn [self]
    (layout-row state self)))

(fn OutlineRowWidget [input-opts]
  (local opts (assert-options input-opts))
  (fn build [build-ctx]
    (local state (make-state opts build-ctx))
    (local layout (Layout {:name (.. "outline-row-" (tostring state.row.key))
                           :measurer (layout-measurer-callback state)
                           :layouter (layout-layouter-callback state)}))
    (set state.layout layout)
    (set state.self (make-row-self state layout))
    (attach-compact! state (glm.vec3 0 0 0))
    (set state.label (make-label state))
    (set state.self.label state.label)
    (layout:set-children [state.label.layout])
    state.self))

OutlineRowWidget
