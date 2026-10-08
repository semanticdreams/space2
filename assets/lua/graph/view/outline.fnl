(local glm (require :glm))
(local GraphOutline (require :graph/outline))
(local GraphViewNodeViews (require :graph/view/node-views))
(local GraphNodeActions (require :graph/view/node-actions))
(local FocusedActions (require :graph/view/focused-actions))

(local row-width 640)
(local row-height 24)
(local row-left-padding 8)
(local row-depth-indent 18)

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

(fn drop-row-handles! [self]
    (local row-handles (assert self.row-handles "GraphOutlineView requires row handles"))
    (local clickables (assert self.clickables "GraphOutlineView requires clickables for row teardown"))
    (each [_ record (ipairs row-handles)]
        (local target (assert record.target "GraphOutlineView row handle requires target"))
        (when (and record.double? clickables.unregister-double-click)
            (clickables:unregister-double-click target))
        (when (and record.right? clickables.unregister-right-click)
            (clickables:unregister-right-click target))
        (when record.left?
            (assert clickables.unregister "GraphOutlineView requires clickables.unregister")
            (clickables:unregister target)))
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

(fn graph-map-selected-keys [graph-map]
    (assert graph-map.selected_node_keys
            "GraphOutlineView requires graph-map selected_node_keys"))

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

(fn select-key! [self key]
    (local node (resolve-visible-node self key "select"))
    (self.graph-map:set-selected-node-keys! [node.key])
    (set self.graph-map.focused_node_key node.key)
    true)

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

(fn row-position [row index]
    (glm.vec3 (+ row-left-padding (* row-depth-indent row.depth))
              (- (* (- index 1) row-height))
              0))

(fn ray-plane-point [ray z]
    (local direction (assert (and ray ray.direction) "GraphOutlineView row intersect requires ray.direction"))
    (local origin (assert ray.origin "GraphOutlineView row intersect requires ray.origin"))
    (if (= direction.z 0)
        nil
        (do
            (local distance (/ (- z origin.z) direction.z))
            (if (< distance 0)
                nil
                (values (+ origin (* direction distance)) distance)))))

(fn point-in-row? [point position]
    (and (>= point.x position.x)
         (<= point.x (+ position.x row-width))
         (<= point.y position.y)
         (>= point.y (- position.y row-height))))

(fn attach-row-intersect! [target position]
    (set target.position position)
    (set target.size (glm.vec3 row-width row-height 0))
    (set target.intersect
         (fn [self ray]
             (local (point distance) (ray-plane-point ray self.position.z))
             (if (and point (point-in-row? point self.position))
                 (values true point distance)
                 (values false nil nil)))))

(fn register-row-clickables! [self clickables target]
    (assert clickables.unregister "GraphOutlineView requires clickables.unregister")
    (clickables:register target)
    (local record {:target target :left? true})
    (when clickables.register-right-click
        (clickables:register-right-click target)
        (set record.right? true))
    (when clickables.register-double-click
        (clickables:register-double-click target)
        (set record.double? true))
    (table.insert self.row-handles record)
    record)

(fn attach-row-handles! [self row index]
    (local clickables (assert self.clickables "GraphOutlineView row handles require clickables"))
    (local target {:key row.key
                   :row row
                   :label (row-title row)
                   :depth row.depth})
    (attach-row-intersect! target (row-position row index))
    (set target.on-click
         (fn [_target _event]
             (select-key! self row.key)))
    (set target.activate
         (fn [_target opts]
             (select-key! self row.key)
             (open-key! self row.key opts)
             true))
    (set target.on-double-click
         (fn [_target event]
             (target:activate {:event event})))
    (set target.on-right-click
         (fn [_target event]
             (select-key! self row.key)
             (local manager (get-menu-manager self.ctx))
             (when manager
                  (manager:open {:actions (self:node-actions row.node)
                                 :position (menu-position event)}))))
    (register-row-clickables! self clickables target)
    target)

(fn rebuild-rows! [self]
    (drop-row-handles! self)
    (set self.rows (GraphOutline.build-rows self.graph-map self.graph-map.outline_root_keys))
    (set self.row-by-key {})
    (each [idx row (ipairs self.rows)]
        (set (. self.row-by-key row.key) row)
        (attach-row-handles! self row idx))
    self.rows)

(fn connect! [self signal handler]
    (when signal
        (local connected (signal:connect handler))
        (table.insert self.connections {:signal signal :handler connected})))

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
                     (view.graph-map:set-selected-node-keys! keys)
                     true)
                 false)))
    (set self.clear-selection
         (fn [view]
             (view:assert-not-dropped "clear-selection")
             (if (> (length view.graph-map.selected_node_keys) 0)
                 (do
                     (view.graph-map:set-selected-node-keys! [])
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
                     (view.graph-map:set-selected-node-keys! [node.key])
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
                     (view.graph-map:set-selected-node-keys! keys)
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
                     (view.graph-map:set-selected-node-keys! keys)
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
                     (set view.graph-map.focused_node_key (. visible-selected 1))
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
    (local node-views (GraphViewNodeViews {:graph-map graph-map
                                           :ctx ctx
                                           :view-target options.view-target
                                           :view-context (resolve-view-context options ctx)}))
    (local self {:graph-map graph-map
                 :ctx ctx
                 :clickables clickables
                 :rows []
                 :row-by-key {}
                 :node-views node-views
                 :connections []
                 :row-handles []})
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
                 (graph-map:set-selected-node-keys! [node.key]))
             (when (not (= reveal-options.focus? false))
                 (set graph-map.focused_node_key node.key))
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
             true))
    (set self.restore-state
         (fn [view state]
             (view:assert-not-dropped "restore-state")
             (local payload (options-table state))
             (when payload.views
                 (view:restore-views-state payload.views))
             (when payload.selected_node_keys
                 (graph-map:set-selected-node-keys! payload.selected_node_keys))
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
    (connect! self graph-map.node-added (fn [_payload] (rebuild-rows! self)))
    (connect! self graph-map.node-removed (fn [_payload] (rebuild-rows! self)))
    (connect! self graph-map.edge-added (fn [_payload] (rebuild-rows! self)))
    (connect! self graph-map.edge-removed (fn [_payload] (rebuild-rows! self)))
    (connect! self graph-map.outline-roots-changed (fn [_payload] (rebuild-rows! self)))
    (rebuild-rows! self)
    self)

GraphOutlineView
