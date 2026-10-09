(local glm (require :glm))
(local GraphOutline (require :graph/outline))
(local GraphViewNodeViews (require :graph/view/node-views))
(local GraphNodeActions (require :graph/view/node-actions))
(local FocusedActions (require :graph/view/focused-actions))
(local CompactNodeProjection (require :graph/view/compact-node-projection))
(local GraphNodePresentation (require :graph/view/presentation))
(local PanelBounds (require :graph/view/panel-bounds))
(local GraphViewUtils (require :graph/view/utils))
(local RawRectangle (require :raw-rectangle))
(local Text (require :text))
(local TextStyle (require :text-style))

(local ensure-glm-vec4 GraphViewUtils.ensure-glm-vec4)

(local row-width 640)
(local row-height 24)
(local row-left-padding 12)
(local row-depth-indent 18)
(local node-label-gap 12)
(local point-label-gap 1.0)
(local graph-label-default-scale 3.0)
(local focus-border-width 1.5)
(local selection-border-width 2.0)
(local point-depth-offset-step 1)
(local point-base-depth-offset 2)
(local focus-layer-index 1)
(local selection-layer-index 2)
(local base-layer-index 3)
(local empty-state-message "No outline roots. Focus a node or select exactly one node, then run Set Outline Root (SPC g o r).")

(var rebuild-rows! nil)

(fn outline-text-style [ctx color scale]
    (assert scale "GraphOutlineView text style requires scale")
    (TextStyle {:color color
                :scale scale
                :theme ctx.theme}))

(fn create-rectangle! [ctx color position size depth-offset]
    (assert depth-offset "GraphOutlineView rectangle visual requires depth offset")
    (local rectangle ((RawRectangle {:color color}) ctx))
    (set rectangle.position position)
    (set rectangle.size size)
    (set rectangle.rotation (glm.quat 1 0 0 0))
    (set rectangle.depth-offset-index depth-offset)
    (rectangle:update)
    rectangle)

(fn create-text! [ctx text position color scale]
    (assert scale "GraphOutlineView text visual requires scale")
    (local label ((Text {:text text
                         :style (outline-text-style ctx color scale)}) ctx))
    (label.layout:measurer)
    (set label.layout.position position)
    (set label.layout.rotation (glm.quat 1 0 0 0))
    (set label.layout.depth-offset-index 1)
    (label.layout:layouter)
    label)

(fn point-relative-label-position [point label]
    (assert point "GraphOutlineView point-relative label requires point")
    (assert label "GraphOutlineView point-relative label requires label")
    (local measure (or label.layout.measure (glm.vec3 0 0 0)))
    (glm.vec3 (+ point.position.x (/ (CompactNodeProjection.visible-size point) 2.0) point-label-gap)
              (- point.position.y (/ measure.y 2.0))
              0.02))

(fn place-point-relative-label! [point label]
    (set label.layout.position (point-relative-label-position point label))
    (label.layout:layouter)
    label)

(fn row-label-scale [self]
    (if (= self.outline-text-scale nil)
        graph-label-default-scale
        self.outline-text-scale))

(fn empty-state-label-scale [self]
    (if (= self.outline-text-scale nil)
        1.0
        self.outline-text-scale))

(fn drop-handle-list! [handles]
    (each [_ handle (ipairs handles)]
        (when (and handle handle.drop)
            (handle:drop)))
    (for [idx (length handles) 1 -1]
        (table.remove handles idx)))

(fn row-title [row]
    (if (and row row.node row.node.label)
        row.node.label
        (and row row.key)
        row.key
        ""))

(fn disconnect-all! [connections]
    (each [_ connection (ipairs connections)]
        (when (and connection.signal connection.handler)
            (connection.signal:disconnect connection.handler true)))
    (for [idx (length connections) 1 -1]
        (table.remove connections idx)))

(fn drop-expanded-record! [self record]
    (when (and record record.expanded-card)
        (local card record.expanded-card)
        (local clickables (assert self.clickables
                                  "GraphOutlineView expanded card drop requires clickables"))
        (when clickables.unregister
            (clickables:unregister card))
        (when (and self.selector record.selectable)
            (self.selector:remove-selectables [record.selectable]))
        (when card.drop
            (card:drop))
        (set record.expanded-card nil)))

(fn drop-row-handles! [self]
    (local row-handles (assert self.row-handles "GraphOutlineView requires row handles"))
    (when self.empty-state-handle
        (drop-handle-list! self.empty-state-handle.visuals)
        (set self.empty-state-handle nil))
    (each [_ record (ipairs row-handles)]
        (when record.visuals
            (drop-handle-list! record.visuals))
        (drop-expanded-record! self record)
        (when record.focus-node
            (set (. self.row-by-focus record.focus-node) nil))
        (when (and record.projection record.projection.drop!)
            (record.projection:drop!))
        (when record.focus-node
            (set record.focus-node nil)))
    (for [idx (length row-handles) 1 -1]
        (table.remove row-handles idx)))

(fn visible-key? [self key]
    (not (= (. self.row-by-key (tostring key)) nil)))

(fn selected-key-set [graph-map]
    (local selected {})
    (local selected-keys (assert graph-map.selected_node_keys
                                 "GraphOutlineView requires graph-map selected_node_keys"))
    (each [_ key (ipairs selected-keys)]
        (set (. selected key) true))
    selected)

(fn visual-color [self row]
    (if (= self.graph-map.focused_node_key row.key)
        (glm.vec4 0.20 0.28 0.42 0.78)
        (. (selected-key-set self.graph-map) row.key)
        (glm.vec4 0.18 0.32 0.24 0.70)
        (glm.vec4 0.08 0.08 0.10 0.58)))

(fn row-selected? [self row]
    (not (= (. (selected-key-set self.graph-map) row.key) nil)))

(fn row-focused? [self row]
    (= self.graph-map.focused_node_key row.key))

(fn row-focus-layer-size [self row base-size]
    (if (row-focused? self row)
        (+ base-size
           (if (row-selected? self row) selection-border-width 0)
           focus-border-width)
        0))

(fn outline-selection-border-color [ctx]
    (local color (and ctx ctx.theme ctx.theme.graph ctx.theme.graph.selection-border-color))
    (assert color "GraphOutlineView requires theme graph.selection-border-color")
    (ensure-glm-vec4 color))

(fn outline-focus-outline-color [ctx]
    (local color (and ctx ctx.theme ctx.theme.input ctx.theme.input.focus-outline))
    (assert color "GraphOutlineView requires theme input focus-outline")
    (ensure-glm-vec4 color))

(fn node-color [row]
    (assert (and row row.node row.node.color)
            "GraphOutlineView node visual requires node color"))

(fn node-size [row]
    (local size (assert (and row row.node row.node.size)
                        "GraphOutlineView node visual requires node size"))
    (assert (> size 0) "GraphOutlineView node visual requires positive node size")
    size)

(fn graph-map-selected-keys [graph-map]
    (assert graph-map.selected_node_keys
            "GraphOutlineView requires graph-map selected_node_keys"))

(fn set-graph-map-selected-keys! [graph-map keys]
    (assert graph-map.set-selected-node-keys
            "GraphOutlineView requires graph-map set-selected-node-keys")
    (graph-map:set-selected-node-keys keys))

(fn default-reveal-options [opts]
    (if opts opts {:select? true :focus? true}))

(fn options-table [value]
    (if value value {}))

(fn resolve-view-context [options ctx]
    (if options.view-context
        options.view-context
        (and options.view-target options.view-target.build-context)
        options.view-target.build-context
        ctx))

(fn resolve-key [node-or-key]
    (if (= (type node-or-key) :string)
        node-or-key
        (and node-or-key node-or-key.key)))

(fn resolve-visible-node [self node-or-key context]
    (local key (resolve-key node-or-key))
    (assert (= (type key) :string)
            (.. "GraphOutlineView " context " requires node key or node"))
    (local row (. self.row-by-key key))
    (assert row (.. "GraphOutlineView " context " node not visible: " key))
    row.node)

(fn open-key! [self key opts]
    (local node (resolve-visible-node self key "open"))
    (self.node-views:open node opts)
    true)

(fn get-menu-manager [ctx]
    (if (and ctx ctx.menu-manager)
        ctx.menu-manager
        app.menu-manager
        app.menu-manager
        nil))

(fn menu-position [event]
    (if (and event event.point)
        event.point
        (and event event.position)
        event.position
        {:x 0 :y 0 :z 0}))

(fn row-label-x [row]
    (+ row-left-padding (* row-depth-indent row.depth) node-label-gap))

(fn row-node-position [row index]
    (glm.vec3 (+ row-left-padding (* row-depth-indent row.depth))
              (- (+ (* (- index 1) row-height) (/ row-height 2)))
              0))

(fn refresh-row-visual! [self record]
    (local row (assert record.row "GraphOutlineView row visual requires row"))
    (if record.expanded?
        (when (and record.point record.point.set-layer-size)
            (local base-size (or record.point.size (node-size row)))
            (record.point:set-layer-size focus-layer-index (row-focus-layer-size self row base-size))
            (record.point:set-layer-size selection-layer-index (if (row-selected? self row)
                                                                  (+ base-size selection-border-width)
                                                                  0)))
        record.projection
        (CompactNodeProjection.refresh! record.projection
                                        {:selected? (row-selected? self row)
                                         :focused? (row-focused? self row)}))
    (when (and record.point record.visuals)
        (local label (. record.visuals 2))
        (when label
            (place-point-relative-label! record.point label)))
    (when record.background
        (set record.background.color (visual-color self row))
        (record.background:update)))

(fn refresh-row-visuals! [self]
    (each [_ record (ipairs self.row-handles)]
        (refresh-row-visual! self record)))

(fn row-record-for-key [self key]
    (var found nil)
    (each [_ record (ipairs self.row-handles) &until found]
        (when (and record.row (= record.row.key key))
            (set found record)))
    found)

(fn row-selectables-for-keys [self keys]
    (local selectables [])
    (each [_ key (ipairs keys)]
        (local record (row-record-for-key self key))
        (when (and record record.selectable)
            (table.insert selectables record.selectable)))
    selectables)

(fn sync-selector-selected-keys! [self keys]
    (when self.selector
        (self.selector:set-selected (row-selectables-for-keys self keys) false)))

(fn set-outline-selection! [self keys]
    (set-graph-map-selected-keys! self.graph-map keys)
    (sync-selector-selected-keys! self keys)
    (refresh-row-visuals! self))

(fn selected-keys-from-selector [self]
    (local keys [])
    (when self.selector
        (each [_ selectable (ipairs self.selector.selected)]
            (when (and selectable selectable.key (visible-key? self selectable.key))
                (table.insert keys selectable.key))))
    keys)

(fn sync-selector-selection-to-map! [self]
    (when (not self.rebuilding?)
        (set-graph-map-selected-keys! self.graph-map (selected-keys-from-selector self))
        (refresh-row-visuals! self)))

(fn sync-map-selection-to-selector! [self]
    (sync-selector-selected-keys! self (graph-map-selected-keys self.graph-map))
    (refresh-row-visuals! self))

(fn focus-key! [self key opts]
    (local record (row-record-for-key self key))
    (if (and record record.focus-node)
        (record.focus-node:request-focus opts)
        (set self.graph-map.focused_node_key key)))

(fn focus-visible-key! [self key reason]
    (local node (resolve-visible-node self key "focus"))
    (focus-key! self node.key {:reason reason})
    (set self.graph-map.focused_node_key node.key)
    (refresh-row-visuals! self)
    true)

(fn projection-focus [node opts]
    (local view (assert (and opts opts.owner)
                        "GraphOutlineView compact focus requires owner"))
    (set view.graph-map.focused_node_key node.key)
    (refresh-row-visuals! view)
    true)

(fn projection-right-click [node event opts]
    (local view (assert (and opts opts.owner)
                        "GraphOutlineView compact right-click requires owner"))
    (local manager (get-menu-manager view.ctx))
    (when manager
        (manager:open {:actions (view:node-actions node)
                       :position (menu-position event)})))

(fn register-expanded-card! [self record card]
    (local clickables (assert self.clickables
                              "GraphOutlineView expanded card requires clickables"))
    (assert clickables.register "GraphOutlineView expanded card requires clickables.register")
    (set card.on-click
         (fn [_card _event]
             (when record.focus-node
                 (record.focus-node:request-focus {:reason :pointer}))))
    (clickables:register card)
    (when self.selector
        (self.selector:add-selectables [card]))
    (set record.expanded-card card)
    (set record.point card)
    (set record.selectable card)
    (when record.focus-node
        (set record.focus-node.presentation card)))

(fn expanded-card-collapse [self]
    (rebuild-rows! self)
    true)

(fn expanded-card-collapse-callback [self]
    (fn collapse-callback []
        (expanded-card-collapse self))

    collapse-callback)

(fn expanded-card-open [self node _event]
    (self.node-views:open node)
    true)

(fn expanded-card-open-callback [self node]
    (fn open-callback [event]
        (expanded-card-open self node event))

    open-callback)

(fn expanded-card-menu [self node event]
    (local manager (get-menu-manager self.ctx))
    (when manager
        (manager:open {:actions (self:node-actions node)
                       :position (menu-position event)})))

(fn expanded-card-menu-callback [self node]
    (fn menu-callback [event]
        (expanded-card-menu self node event))

    menu-callback)

(fn expanded-card-options [self record node]
    (local bounds (PanelBounds.inline-card-bounds))
    {:node node
     :position record.point.position
     :default-size bounds.default-size
     :min-size bounds.min-size
     :max-size bounds.max-size
     :resize-max-size bounds.resize-max-size
     :depth-offset-index point-base-depth-offset
     :selection-color self.selection-border-color
     :focus-color self.focus-outline-color
     :pointer-target self.pointer-target
     :on-collapse (expanded-card-collapse-callback self)
     :on-open (expanded-card-open-callback self node)
     :on-menu (expanded-card-menu-callback self node)})

(fn build-expanded-card! [self record node]
    (local card-builder
          (GraphNodePresentation.card-builder (expanded-card-options self record node)))
    (card-builder self.ctx))

(fn unregister-compact-projection-handles! [record]
    (local projection (assert record.projection
                              "GraphOutlineView compact expansion requires projection"))
    (local point (assert projection.point
                         "GraphOutlineView compact expansion requires point"))
    (local clickables (assert projection.clickables
                              "GraphOutlineView compact expansion requires clickables"))
    (when (and projection.left? clickables.unregister)
        (clickables:unregister point))
    (when (and projection.right? clickables.unregister-right-click)
        (clickables:unregister-right-click point))
    (when (and projection.double? clickables.unregister-double-click)
        (clickables:unregister-double-click point))
    (when (and projection.selector projection.selectable)
        (projection.selector:remove-selectables [projection.selectable]))
    (when point.drop
        (point:drop))
    (set projection.left? nil)
    (set projection.right? nil)
    (set projection.double? nil))

(fn expand-record! [self record node]
    (if record.expanded?
        true
        (do
            (unregister-compact-projection-handles! record)
            (local card (build-expanded-card! self record node))
            (register-expanded-card! self record card)
            (set record.expanded? true)
            (set (. self.expanded-row-keys node.key) true)
            (refresh-row-visual! self record)
            true)))

(fn projection-activate [node opts]
    (local view (assert (and opts opts.owner)
                        "GraphOutlineView compact activate requires owner"))
    (local record (assert (row-record-for-key view node.key)
                          "GraphOutlineView compact activate requires visible record"))
    (focus-visible-key! view node.key :activate)
    (expand-record! view record node))

(fn projection-layers [self row base-size]
    [{:size (row-focus-layer-size self row base-size)
      :color self.focus-outline-color}
     {:size (if (row-selected? self row)
              (+ base-size selection-border-width)
              0)
      :color self.selection-border-color}
     {:size base-size
      :color (node-color row)}])

(fn projection-options [self row index base-size clickables]
    {:points (assert self.ctx.points "GraphOutlineView node visuals require ctx.points")
     :node row.node
     :position (row-node-position row index)
     :pointer-target self.pointer-target
     :depth-offset-step point-depth-offset-step
     :base-depth-offset-index point-base-depth-offset
     :base-layer-index base-layer-index
     :focus-layer-index focus-layer-index
     :selection-layer-index selection-layer-index
     :focus-border-width focus-border-width
     :selection-border-width selection-border-width
     :clickables clickables
     :selector self.selector
     :focus self.focus
     :layers (projection-layers self row base-size)
     :selected? (row-selected? self row)
     :focused? (row-focused? self row)
     :owner self
     :on-focus projection-focus
     :on-right-click projection-right-click
     :on-activate projection-activate})

(fn attach-row-label! [self row point]
    (local label
            (create-text! self.ctx
                          (row-title row)
                          (glm.vec3 0 0 0.02)
                          (glm.vec4 0.86 0.88 0.92 1)
                          (row-label-scale self)))
    (place-point-relative-label! point label)
    label)

(fn attach-row-handles! [self row index]
    (local clickables (assert self.clickables "GraphOutlineView row handles require clickables"))
    (local base-size (node-size row))
    (local record {:row row
                   :label (row-title row)
                   :label-x (row-label-x row)
                   :depth row.depth})
    (local projection
          (CompactNodeProjection.attach! (projection-options self row index base-size clickables)))
    (table.insert self.row-handles record)
    (set record.row row)
    (set record.projection projection)
    (set record.point projection.point)
    (set record.selectable projection.selectable)
    (set record.focus-node projection.focus-node)
    (when record.focus-node
        (set (. self.row-by-focus record.focus-node) row))
    (local label (attach-row-label! self row record.point))
    (set record.visuals [false label])
    record.point)

(fn attach-empty-state! [self]
    (local background
          (create-rectangle! self.ctx
                             (glm.vec4 0.08 0.08 0.10 0.58)
                             (glm.vec3 0 (- row-height) -0.04)
                             (glm.vec2 row-width row-height)
                             0))
    (local label
           (create-text! self.ctx
                          empty-state-message
                          (glm.vec3 row-left-padding (- 0 row-height -6) 0.02)
                          (glm.vec4 0.86 0.88 0.92 1)
                          (empty-state-label-scale self)))
    (set self.empty-state-handle {:message empty-state-message
                                   :visuals [background label]})
    self.empty-state-handle)

(fn make-outline-view-state [graph-map ctx clickables node-views outline-text-scale selector focus pointer-target]
    {:graph-map graph-map
      :ctx ctx
      :clickables clickables
      :selector selector
      :focus focus
      :pointer-target pointer-target
      :selection-border-color (outline-selection-border-color ctx)
      :focus-outline-color (outline-focus-outline-color ctx)
      :rows []
      :row-by-key {}
      :row-by-focus {}
      :expanded-row-keys {}
      :node-views node-views
      :outline-text-scale outline-text-scale
      :connections []
      :row-handles []})

(fn should-restore-focus-on-rebuild? [self]
    (local focus-manager (and self.focus self.focus.manager))
    (local current-focus (and focus-manager (focus-manager:get-focused-node)))
    (if current-focus
        (not (= (. self.row-by-focus current-focus) nil))
        true))

(set rebuild-rows! (fn [self]
    (set self.rebuilding? true)
    (drop-row-handles! self)
    (set self.rows (GraphOutline.build-rows self.graph-map self.graph-map.outline_root_keys))
    (set self.row-by-key {})
    (set self.expanded-row-keys {})
    (each [idx row (ipairs self.rows)]
        (set (. self.row-by-key row.key) row)
        (attach-row-handles! self row idx))
    (when (= (length self.rows) 0)
        (attach-empty-state! self))
    (set self.rebuilding? false)
    (sync-map-selection-to-selector! self)
    (when (and self.graph-map.focused_node_key
               (visible-key? self self.graph-map.focused_node_key)
               (should-restore-focus-on-rebuild? self))
        (focus-key! self self.graph-map.focused_node_key {:reason :rebuild}))
    self.rows))

(fn connect! [self signal handler]
    (when signal
        (local connected (signal:connect handler))
        (table.insert self.connections {:signal signal :handler connected})))

(fn sync-focus-manager-to-map! [self payload]
    (local focus-node (and payload payload.current))
    (local row (and focus-node (. self.row-by-focus focus-node)))
    (if row
        (do
            (set self.graph-map.focused_node_key row.key)
            (refresh-row-visuals! self))
        (do
            (local previous-row (and payload payload.previous (. self.row-by-focus payload.previous)))
            (when (and previous-row (= self.graph-map.focused_node_key previous-row.key))
                (set self.graph-map.focused_node_key nil)
                (refresh-row-visuals! self)))))

(fn install-sync-connections! [self selector focus-manager]
    (when (and selector selector.changed)
        (connect! self selector.changed (fn [_payload] (sync-selector-selection-to-map! self))))
    (when self.graph-map.selection-changed
        (connect! self self.graph-map.selection-changed (fn [_payload] (sync-map-selection-to-selector! self))))
    (when (and focus-manager focus-manager.focus-focus)
        (connect! self focus-manager.focus-focus (fn [payload] (sync-focus-manager-to-map! self payload))))
    (when (and focus-manager focus-manager.focus-blur)
        (connect! self focus-manager.focus-blur (fn [payload] (sync-focus-manager-to-map! self payload)))))

(fn install-rebuild-connections! [self graph-map]
    (connect! self graph-map.node-added (fn [_payload] (rebuild-rows! self)))
    (connect! self graph-map.node-removed (fn [_payload] (rebuild-rows! self)))
    (connect! self graph-map.edge-added (fn [_payload] (rebuild-rows! self)))
    (connect! self graph-map.edge-removed (fn [_payload] (rebuild-rows! self)))
    (connect! self graph-map.outline-roots-changed (fn [_payload] (rebuild-rows! self))))

(fn install-selection-methods! [self]
    (set self.selected-node-count
         (fn [view]
             (view:assert-not-dropped "selected-node-count")
             (local selected (selected-key-set view.graph-map))
             (accumulate [count 0 _ row (ipairs view.rows)]
                 (if (. selected row.key) (+ count 1) count))))
    (set self.select-all-visible-nodes
         (fn [view]
             (view:assert-not-dropped "select-all-visible-nodes")
             (local keys (icollect [_ row (ipairs view.rows)] row.key))
             (if (> (length keys) 0)
                  (do
                      (set-outline-selection! view keys)
                      true)
                 false)))
    (set self.clear-selection
         (fn [view]
             (view:assert-not-dropped "clear-selection")
             (if (> (length view.graph-map.selected_node_keys) 0)
                  (do
                      (set-outline-selection! view [])
                      true)
                 false)))
    (set self.focused-node-selected?
         (fn [view]
             (local node (view:focused-node))
             (if node
                 (not (= (. (selected-key-set view.graph-map) node.key) nil))
                 false)))
    (set self.select-focused-node-only
         (fn [view]
             (local node (view:focused-node))
             (if node
                  (do
                      (set-outline-selection! view [node.key])
                      true)
                 false)))
    (set self.add-focused-node-to-selection
         (fn [view]
             (local node (view:focused-node))
             (if node
                 (do
                     (local keys [])
                     (local seen {})
                     (each [_ key (ipairs (graph-map-selected-keys view.graph-map))]
                         (when (visible-key? view key)
                             (set (. seen key) true)
                             (table.insert keys key)))
                     (when (not (. seen node.key))
                         (table.insert keys node.key))
                      (set-outline-selection! view keys)
                      true)
                 false)))
    (set self.remove-focused-node-from-selection
         (fn [view]
             (local node (view:focused-node))
             (if node
                 (do
                     (local keys [])
                     (each [_ key (ipairs (graph-map-selected-keys view.graph-map))]
                         (when (and (not= key node.key) (visible-key? view key))
                             (table.insert keys key)))
                      (set-outline-selection! view keys)
                      true)
                 false)))
    (set self.toggle-focused-node-selection
         (fn [view]
             (if (view:focused-node-selected?)
                 (view:remove-focused-node-from-selection)
                 (view:add-focused-node-to-selection))))
    (set self.focus-selected-node
         (fn [view]
             (view:assert-not-dropped "focus-selected-node")
             (local visible-selected [])
             (each [_ key (ipairs (graph-map-selected-keys view.graph-map))]
                 (when (visible-key? view key)
                     (table.insert visible-selected key)))
             (if (= (length visible-selected) 1)
                  (do
                      (focus-key! view (. visible-selected 1) {:reason :selection-command})
                      (set view.graph-map.focused_node_key (. visible-selected 1))
                      (refresh-row-visuals! view)
                      true)
                 false)))
    (set self.has-visible-nodes?
         (fn [view]
             (view:assert-not-dropped "has-visible-nodes?")
             (> (length view.rows) 0))))

(fn install-focused-actions! [self]
    (FocusedActions.install!
        self
        {:focused-node (fn [view]
                         (local key view.graph-map.focused_node_key)
                         (if (and key (visible-key? view key))
                             (. view.row-by-key key :node)
                             nil))
         :focused-node-actions (fn [view]
                                 (view:assert-not-dropped "focused-node-actions")
                                 (local node (view:focused-node))
                                 (if node (view:node-actions node) []))
         :run-focused-node-action-slot (fn [view index]
                                         (view:assert-not-dropped "run-focused-node-action-slot")
                                         (if (not (= (type index) :number))
                                             false
                                             (do
                                                 (local action (. (view:focused-node-actions) index))
                                                 (if (and action (= (type action.fn) :function))
                                                     (do
                                                         (action.fn nil {})
                                                         true)
                                                     false))))
         :open-focused-node-menu (fn [view]
                                   (view:assert-not-dropped "open-focused-node-menu")
                                   (local node (view:focused-node))
                                   (local manager (get-menu-manager view.ctx))
                                   (if (and node manager)
                                       (do
                                           (manager:open {:actions (view:focused-node-actions)
                                                          :position {:x 0 :y 0 :z 0}})
                                           true)
                                       false))
         :copy-focused-node-key (fn [view]
                                  (view:assert-not-dropped "copy-focused-node-key")
                                  (local node (view:focused-node))
                                  (if node
                                      (do
                                          (local runtime-gl (require :gl))
                                          (runtime-gl.clipboard-set (tostring node.key))
                                          true)
                                      false))
         :remove-focused-node-from-map (fn [view]
                                         (view:assert-not-dropped "remove-focused-node-from-map")
                                         (local node (view:focused-node))
                                         (if node
                                             (> (view.graph-map:remove-nodes [node]) 0)
                                             false))
         :reveal-focused-node (fn [view opts]
                                (view:assert-not-dropped "reveal-focused-node")
                                (local node (view:focused-node))
                                (if node
                                    (do
                                        (view:reveal-node node (default-reveal-options opts))
                                        true)
                                    false))}))

(fn GraphOutlineView [options]
    (local graph-map (assert options.graph-map "GraphOutlineView requires :graph-map"))
    (local ctx (assert options.ctx "GraphOutlineView requires :ctx"))
    (local clickables (assert ctx.clickables "GraphOutlineView requires ctx.clickables"))
    (local selector options.selector)
    (local focus (and ctx ctx.focus))
    (local focus-manager (and focus focus.manager))
    (local pointer-target (or options.pointer-target
                              (and ctx ctx.pointer-target)))
    (local node-views (GraphViewNodeViews {:graph-map graph-map
                                            :ctx ctx
                                            :view-target options.view-target
                                            :view-context (resolve-view-context options ctx)}))
    (local outline-text-scale options.outline-text-scale)
    (local self (make-outline-view-state graph-map ctx clickables node-views outline-text-scale selector focus pointer-target))
    (var dropped? false)
    (set self.assert-not-dropped
         (fn [_view context]
             (assert (not dropped?) (.. "GraphOutlineView " context " called after drop"))))
    (set self.node-actions
         (fn [view node]
             (view:assert-not-dropped "node-actions")
             (GraphNodeActions.build {:graph-map graph-map
                                      :views node-views
                                      :include-preview-action? false}
                                     node)))
    (set self.reveal-node
         (fn [view node-or-key opts]
             (view:assert-not-dropped "reveal-node")
              (local reveal-options (options-table opts))
              (local node (resolve-visible-node view node-or-key "reveal-node"))
              (when (not (= reveal-options.select? false))
                  (set-outline-selection! view [node.key]))
              (when (not (= reveal-options.focus? false))
                   (focus-key! view node.key {:reason :reveal})
                   (set graph-map.focused_node_key node.key))
              (refresh-row-visuals! view)
              node))
    (set self.open-node
         (fn [view node-or-key opts]
             (view:assert-not-dropped "open-node")
             (local node (view:reveal-node node-or-key opts))
             (node-views:open node opts)
             true))
    (set self.open-focused-node
         (fn [view]
             (view:assert-not-dropped "open-focused-node")
             (local node (view:focused-node))
             (if node
                 (do
                     (node-views:open node)
                     true)
                 false)))
    (set self.expand-focused-node
         (fn [view]
             (view:assert-not-dropped "expand-focused-node")
             (local node (view:focused-node))
             (if node
                 (do
                     (node-views:open node)
                     true)
                 false)))
    (set self.remove-nodes
         (fn [view nodes]
             (view:assert-not-dropped "remove-nodes")
             (graph-map:remove-nodes nodes)))
    (set self.remove-selected-nodes
         (fn [view]
             (view:assert-not-dropped "remove-selected-nodes")
             (local nodes [])
             (each [_ key (ipairs (graph-map-selected-keys graph-map))]
                 (local row (. view.row-by-key key))
                 (when row
                     (table.insert nodes row.node)))
             (graph-map:remove-nodes nodes)))
    (set self.update (fn [view _delta] (view:assert-not-dropped "update") true))
    (set self.start-layout (fn [view] (view:assert-not-dropped "start-layout") false))
    (set self.apply-initial-camera-policy! (fn [view] (view:assert-not-dropped "apply-initial-camera-policy!") true))
    (set self.capture-state
         (fn [view]
             (view:assert-not-dropped "capture-state")
             {:views (and node-views node-views.capture-state (node-views:capture-state))
              :selected_node_keys (icollect [_ key (ipairs (graph-map-selected-keys graph-map))]
                                    (and (visible-key? view key) key))}))
    (set self.restore-views-state
         (fn [view state]
             (view:assert-not-dropped "restore-views-state")
             (when (and node-views node-views.restore-state state)
                 (node-views:restore-state state))
             true))
    (set self.restore-graph-state
         (fn [view state]
             (view:assert-not-dropped "restore-graph-state")
             (when (and graph-map graph-map.restore-state state)
                 (graph-map:restore-state state))
             (refresh-row-visuals! view)
             true))
    (set self.restore-state
         (fn [view state]
             (view:assert-not-dropped "restore-state")
             (local payload (options-table state))
             (when payload.views
                 (view:restore-views-state payload.views))
              (when payload.selected_node_keys
                  (set-outline-selection! view payload.selected_node_keys))
             (refresh-row-visuals! view)
             true))
    (set self.drop
         (fn [view]
             (view:assert-not-dropped "drop")
             (set dropped? true)
             (disconnect-all! view.connections)
             (drop-row-handles! view)
             (when node-views
                 (node-views:drop-all))))
    (install-selection-methods! self)
    (install-focused-actions! self)
    (install-sync-connections! self selector focus-manager)
    (install-rebuild-connections! self graph-map)
    (rebuild-rows! self)
    self)

GraphOutlineView
