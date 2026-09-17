(local glm (require :glm))
(local appdirs (require :appdirs))
(local Signal (require :signal))
(local PanelBounds (require :graph/view/panel-bounds))
(local Utils (require :graph/view/utils))
(local MathUtils (require :math-utils))
(local GraphViewEdge (require :graph/view/edge))
(local GraphViewRegistry (require :graph/view/registry))
(local GraphViewLayout (require :graph/view/layout))
(local GraphViewMovables (require :graph/view/movables))
(local GraphViewLabels (require :graph/view/labels))
(local GraphViewSelection (require :graph/view/selection))
(local GraphViewNodeViews (require :graph/view/node-views))
(local GraphViewPersistence (require :graph/view/persistence)) (local ActivityCameraState (require :activity-camera-state))
(local NodeBase (require :graph/node-base))
(local GraphNodePresentation (require :graph/view/presentation))
(local IslandHost (require :graph/view/island-host))
(local IslandPresenters (require :graph/view/island-presenters))

(local new-triangle-line GraphViewEdge.new-triangle-line)
(local ensure-glm-vec3 Utils.ensure-glm-vec3)
(local ensure-glm-vec4 Utils.ensure-glm-vec4)
(local node-id NodeBase.node-id)
(local array->vec3 MathUtils.array->vec3)
(local array->quat MathUtils.array->quat)

(local {:ForceLayout ForceLayout} (require :force-layout))
(local Modifiers (require :input-modifiers))
(local LinkEntityStore (require :entities/link))

(fn expand-linked-frontier [graph-map keys]
    (local store (LinkEntityStore.get-default))
    (local next-frontier [])
    (each [_ key (ipairs keys)]
        (local entities (store:find-entities-for-key key))
        (each [_ entity (ipairs entities)]
            (local other-key
                (if (= (tostring entity.source-key) (tostring key))
                    entity.target-key
                    entity.source-key))
            (graph-map:load-by-key other-key)
            (table.insert next-frontier (tostring other-key))))
    next-frontier)

(fn GraphView [opts]
    (local options (or opts {}))
    (local graph-map (or options.graph-map options.graph))
    (assert graph-map "GraphView requires a graph-map")
    (local graph-map-id (or graph-map.id "main"))
    (local ctx options.ctx)
    (assert ctx "GraphView requires a build context with triangle-vector and points")
    (local points (or ctx.points (and ctx ctx.points)))
    (local vector (and ctx ctx.triangle-vector))
    (local selector options.selector)
    (local selected-nodes [])
    (local selected-nodes-changed (Signal))
    (local node-by-point {})
    (local pinned {})
    (local view-target options.view-target)
    (local view-context (or options.view-context
                            (and view-target view-target.build-context)
                            ctx))
    (local movables options.movables)
    (local clickables (and ctx ctx.clickables))
    (local focus (and ctx ctx.focus))
    (local focus-manager (and focus focus.manager))
    (var points-focus-scope
         (and focus (focus:create-scope {:name "graph-node-points"
                                         :directional-traversal-boundary? true})))
    (local focus-nodes {})
    (local node-by-focus {})
    (var selected-set {})
    (var focused-node nil)
    (var selection-handler nil)
    (var focus-focus-handler nil)
    (var focus-blur-handler nil)
    (var movables-handler nil)
    (var register-movable nil)
    (var drag-active? false)
    (var drag-node nil)
    (var expand-seq-timestamp 0)
    (var expand-seq-frontier [])
    (local expand-seq-timeout 800)
    (local expanded-nodes {})
    (local pinned-before-expand {})
    (var toggle-node-presentation nil)
    (var extra-panel-transfer-source nil)
    (var extra-panel-transfer-handler nil)
    (var dropped? false)
    (var pending-initial-center? false)
    (var initial-center-consumed? false) (var armed-initial-camera-state nil)
    (var consume-initial-center! nil)
    (assert points "GraphView requires ctx.points")
    (assert vector "GraphView requires ctx.triangle-vector")
    (assert focus "GraphView requires ctx.focus")
    (local layout (ForceLayout))
    (layout:set-bounds (glm.vec3 -1000 -90 0) (glm.vec3 1000 510 0))
    (local data-dir (or options.data-dir
                        (and appdirs (appdirs.user-data-dir "space"))))
    (assert data-dir "GraphView requires a data-dir for persistence")
    (local persistence (or options.persistence
                           (GraphViewPersistence {:data-dir data-dir
                                                   :map-id graph-map-id})))
    (local theme (and ctx ctx.theme))
    (local graph-theme (and theme theme.graph))
    (local resolved-label-color (or options.label-color (and graph-theme graph-theme.label-color)))
    (local resolved-label-target-pixels (or options.label-target-pixels
                                           (and graph-theme graph-theme.label-target-pixels)))
    (local resolved-label-min-scale (or options.label-min-scale
                                        (and graph-theme graph-theme.label-min-scale)))
    (local resolved-edge-color (or options.edge-color (and graph-theme graph-theme.edge-color)))
    (local resolved-edge-thickness (or options.edge-thickness
                                      (and graph-theme graph-theme.edge-thickness)
                                      2.0))
    (local selection-border-color (or options.selection-border-color
                                      (and graph-theme graph-theme.selection-border-color)))
    (assert selection-border-color "GraphView requires theme graph.selection-border-color")
    (local focus-outline-color (or options.focus-outline-color
                                   (and theme theme.input theme.input.focus-outline)))
    (assert focus-outline-color "GraphView requires theme input focus-outline")
    (local resolved-selection-border-color (ensure-glm-vec4 selection-border-color))
    (local resolved-focus-outline-color (ensure-glm-vec4 focus-outline-color))
    (local selection-border-width 2.0)
    (local focus-border-width 1.5)
    (local point-depth-offset-step 1)
    (local point-base-depth-offset 2)
    (local focus-layer-index 1)
    (local selection-layer-index 2)
    (local base-layer-index 3)
    (local lod-surface-provider
           (or options.lod-surface-provider
               (fn []
                   (or options.lod-surface
                       (and ctx ctx.pointer-target)))))
    (local labels (GraphViewLabels {:ctx ctx
                                    :camera options.camera
                                    :surface-provider lod-surface-provider
                                    :label-color resolved-label-color
                                    :label-target-pixels resolved-label-target-pixels
                                    :label-min-scale resolved-label-min-scale
                                    :label-depth-offset (or options.label-depth-offset 1.0)}))
    (local views (GraphViewNodeViews {:graph-map graph-map
                                       :ctx ctx
                                      :view-target view-target
                                      :view-context view-context}))
    (local selection (GraphViewSelection {:selector selector
                                      :node-by-point node-by-point
                                      :selected-nodes selected-nodes
                                      :selected-nodes-changed selected-nodes-changed
                                      :node-id node-id
                                      :on-change (fn [_nodes] nil)}))

    (local nodes {})
    (local nodes-by-index [])
    (local indices {})
    (local edge-map {})
    (local edges [])
    (local pending-edges []) ;; Edges waiting for nodes
    (local node-changed-handlers {})
    (local registry
          (GraphViewRegistry {:nodes nodes
                          :nodes-by-index nodes-by-index
                          :indices indices
                          :points {}
                          :edge-map edge-map
                          :edges edges
                          :node-by-point node-by-point
                          :pinned pinned}))

    (assert clickables "GraphView requires clickables for node view double click")

    (fn assert-not-dropped [context]
        (assert (not dropped?)
                (string.format "GraphView %s called after drop" context)))

    (fn get-menu-manager []
        (or (and ctx ctx.menu-manager) app.menu-manager))

    (fn node-menu-actions [node]
        (local actions [])
        (local configured-actions
               (if (= (type (and node node.actions)) :function)
                   ((. node :actions) node)
                   (and node node.actions)))
        (table.insert actions
                       {:name "Open"
                        :icon "open_in_new"
                         :fn (fn [_button event]
                                (when focus-manager
                                    (focus-manager:arm-auto-focus {:event event}))
                                (local (ok err) (pcall (fn [] (views:open node))))
                                (when focus-manager
                                    (focus-manager:clear-auto-focus))
                                (when (not ok)
                                    (error err)))})
        (table.insert actions
                       {:name "Copy key"
                        :icon "content_copy"
                        :fn (fn [_button _event]
                               (local runtime-gl (require :gl)) (runtime-gl.clipboard-set (tostring node.key)))})
        (table.insert actions
                       {:name (if (. expanded-nodes node) "Collapse" "Expand")
                        :icon (if (. expanded-nodes node) "close_fullscreen" "open_in_full")
                         :fn (fn [_button _event]
                                (toggle-node-presentation node))})
        (table.insert actions
                       {:name "cube"
                         :fn (fn [_button _event]
                                (local scene app.scene)
                                (when (and scene scene.add-graph-node-cube)
                                    (scene:add-graph-node-cube {:node node})))})
        (table.insert actions
                       {:name "Remove from Map"
                        :icon "close"
                        :fn (fn [_button _event]
                                (when (and graph-map graph-map.remove-nodes)
                                    (graph-map:remove-nodes [node])))})
        (table.insert actions {:type :separator})
        (each [_ action (ipairs (or configured-actions []))]
            (when (and action action.name action.fn)
                (table.insert actions action)))
        actions)

    (fn resolve-menu-position [event]
        (local screen (and event event.screen))
        (if (and screen app.hud app.hud.screen-pos-ray)
            (do
                (local ray (app.hud:screen-pos-ray {:x (or screen.x 0)
                                                    :y (or screen.y 0)}))
                (if (and ray ray.origin ray.direction)
                    (do
                        (local dz (or ray.direction.z 0))
                        (local t (if (not (= dz 0))
                                     (/ (- 0 ray.origin.z) dz)
                                     0))
                        (+ ray.origin (* ray.direction t)))
                    (or (and event event.point) (glm.vec3 0 0 0))))
            (or (and event event.point) (glm.vec3 0 0 0))))

    (fn update-point-state [node]
        (local point (. registry.points node))
        (when point
            (local base-size (or point.size 0))
            (local selected? (rawget selected-set node))
            (local focused? (= focused-node node))
            (local selection-size (if selected?
                                      (+ base-size selection-border-width)
                                      0))
            (local focus-size (if focused?
                                  (+ base-size
                                     (if selected? selection-border-width 0)
                                     focus-border-width)
                                  0))
            (point:set-layer-size focus-layer-index focus-size)
            (point:set-layer-size selection-layer-index selection-size)))

    (fn bounds-for-presentation [presentation]
        (when presentation
            (if presentation._card-size
                (do
                    (local position (or (and presentation.layout presentation.layout.position)
                                        presentation.position))
                    (local size (or (and presentation.layout presentation.layout.size)
                                    presentation._card-size))
                    (when (and position size)
                        {:position (glm.vec3 position.x position.y position.z)
                         :size size}))
                (do
                    (local position presentation.position)
                    (local size (or presentation.size 0))
                    (local half (* size 0.5))
                    (when position
                        {:position (glm.vec3 (- position.x half)
                                             (- position.y half)
                                             (- position.z half))
                         :size (glm.vec3 size size size)})))))

    (fn attach-focus-bounds [node]
        (local focus-node (. focus-nodes node))
        (when (and focus-node focus)
            (focus:attach-bounds
                focus-node
                {:get-bounds (fn [_self]
                                  (bounds-for-presentation (. registry.points node)))})))

    (fn bind-focus-node-activate [node focus-node]
        (when focus-node
            (set focus-node.activate
                 (fn [_node opts]
                     (local mod (and opts opts.event opts.event.mod))
                     (if (Modifiers.alt-held? mod)
                         (do
                             (local ts (or (and opts opts.event opts.event.payload
                                                opts.event.payload.timestamp) 0))
                             (local continuing?
                                 (and (> (length expand-seq-frontier) 0)
                                      (> ts 0)
                                      (<= (- ts expand-seq-timestamp) expand-seq-timeout)))
                             (local frontier
                                 (if continuing?
                                     expand-seq-frontier
                                     [(tostring node.key)]))
                             (set expand-seq-frontier (expand-linked-frontier graph-map frontier))
                             (set expand-seq-timestamp ts)
                             true)
                         (do (views:open node) true))))))

    (fn update-selection-set [nodes]
        (local next {})
        (each [_ node (ipairs (or nodes []))]
            (set (. next node) true))
        (local previous selected-set)
        (set selected-set next)
        (each [node _ (pairs previous)]
            (when (not (rawget next node))
                (update-point-state node)))
        (each [node _ (pairs next)]
            (when (not (rawget previous node))
                (update-point-state node))))

    (fn handle-focus-change [payload]
        (assert-not-dropped "handle-focus-change")
        (local previous-focus (and payload payload.previous))
        (local current-focus (and payload payload.current))
        (local previous-node (and previous-focus (. node-by-focus previous-focus)))
        (local current-node (and current-focus (. node-by-focus current-focus)))
        (set focused-node current-node)
        (when previous-node
            (update-point-state previous-node))
        (when current-node
            (update-point-state current-node)))

    (fn assert-valid-position [pos context node _point]
        (local key (and node node.key))
        (fn finite-number? [v]
            (and (= (type v) :number)
                 (= v v)
                 (not (= v math.huge))
                 (not (= v (- math.huge)))))
        (when (or (not pos)
                  (not (finite-number? pos.x))
                  (not (finite-number? pos.y))
                  (not (finite-number? pos.z)))
            (error (string.format "GraphView received non-finite position in %s for %s"
                                  context
                                  (or key "unknown node"))))
        (local magnitude (glm.length pos))
        (when (> magnitude 1e6)
            (error (string.format "GraphView position magnitude %.3f exceeds threshold for %s (%s) in %s"
                                  magnitude
                                  (or key "unknown node")
                                  (node-id node)
                                  context))))

    (fn next-position []
        (local center (ensure-glm-vec3 layout.center-position (glm.vec3 0 0 0)))
        (glm.vec3 (+ center.x (* (math.random) 100))
                  (+ center.y (* (math.random) 100))
                  center.z))

    (fn assert-point [_self node context]
        (assert node (string.format "GraphView missing node for %s" context))
        (local point (. registry.points node))
        (assert point (string.format "GraphView missing point for node %s (%s)"
                                     (node-id node)
                                     context))
        (assert point.position
                (string.format "GraphView missing position for node %s (%s)"
                               (node-id node)
                               context))
        point)

    (fn get-position [_self node]
        (assert-not-dropped "get-position")
        (local point (assert-point nil node "get-position"))
        (assert-valid-position point.position "GraphView.get-position" node point)
        (glm.vec3 point.position.x point.position.y point.position.z))

    (fn get-position-raw [_self node]
        (assert-not-dropped "get-position-raw")
        (local point (assert-point nil node "get-position-raw"))
        (assert-valid-position point.position "GraphView.get-position-raw" node point)
        point.position)

    (fn set-point-position [node position source]
        (local point (. registry.points node))
        (assert point (string.format "GraphView.set-point-position missing point for node %s"
                                     (node-id node)))
        (local context (or source "GraphView.set-point-position"))
        (assert-valid-position position context node point)
        (if point.set-position-values
            (point:set-position-values position.x position.y position.z)
            (point:set-position position))
        (when movables-handler
            (movables-handler:update-position node position)))

    (fn compact-label-targets [nodes]
        (local filtered [])
        (each [_ node (ipairs (or nodes []))]
            (when (not (. expanded-nodes node))
                (table.insert filtered node)))
        filtered)

    (fn update-labels [nodes opts]
        (if nodes
            (do
                (local filtered (compact-label-targets nodes))
                (when (> (length filtered) 0)
                    (labels:update registry.points filtered opts)))
            (do
                (local filtered [])
                (each [node _ (pairs registry.points)]
                    (when (not (. expanded-nodes node))
                        (table.insert filtered node)))
                (labels:update registry.points filtered opts))))

    (fn refresh-label-positions [nodes]
        (if nodes
            (do
                (local filtered (compact-label-targets nodes))
                (when (> (length filtered) 0)
                    (labels:refresh-positions registry.points filtered)))
            (do
                (local filtered [])
                (each [node _ (pairs registry.points)]
                    (when (not (. expanded-nodes node))
                        (table.insert filtered node)))
                (labels:refresh-positions registry.points filtered))))

    (local graph-layout
          (GraphViewLayout {:layout layout
                        :nodes-by-index nodes-by-index
                        :indices indices
                        :nodes nodes
                        :points registry.points
                        :edges edges
                        :edge-map edge-map
                        :pinned pinned
                        :make-line new-triangle-line
                        :ctx ctx
                        :edge-color resolved-edge-color
                        :edge-thickness resolved-edge-thickness
                        :label-color (or resolved-label-color (glm.vec4 0.8 0.8 0.8 1))
                        :label-depth-offset (or options.label-depth-offset 1.0)
                        :set-point-position set-point-position
                        :update-labels update-labels
                        :refresh-label-positions refresh-label-positions
                         :get-position get-position
                         :get-position-raw get-position-raw}))

    (local island-host
        (IslandHost.GraphViewIslandHost
            {:presenters IslandPresenters
             :node-for-key (fn [_host-options key]
                             (graph-map:lookup key))
             :position-for-key (fn [_host-options key]
                                 (local node (graph-map:lookup key))
                                 (and node (get-position nil node)))
             :set-node-position (fn [_host-options key position]
                                  (local node (graph-map:lookup key))
                                  (assert node (.. "GraphView island host missing node for key: " (tostring key)))
                                  (graph-layout:set-node-position node position {:skip-labels? true}))
             :set-node-pinned (fn [_host-options key pinned?]
                                (local node (graph-map:lookup key))
                                (assert node (.. "GraphView island host missing node for key: " (tostring key)))
                                (set (. pinned node) (if pinned? true nil))
                                (graph-layout:set-node-pinned node pinned?))}))

    (fn reconcile-graph-islands! []
        (island-host:reconcile-all (graph-map:list-islands)))

    (var batch-depth 0)
    (var batched-layout-dirty? false)
    (var batched-force-layout? false)
    (local batched-label-nodes {})

    (fn clear-batched-graph-updates! []
        (set batched-layout-dirty? false)
        (set batched-force-layout? false)
        (each [node _ (pairs batched-label-nodes)]
            (set (. batched-label-nodes node) nil)))

    (fn queue-batched-label-refresh! [node]
        (when node
            (set (. batched-label-nodes node) true)))

    (fn flush-batched-graph-updates! []
        (when batched-layout-dirty?
            (if batched-force-layout?
                (graph-layout:start)
                (graph-layout:update-lines)))
        (local label-nodes
            (icollect [node _ (pairs batched-label-nodes)]
                node))
        (when (> (length label-nodes) 0)
            (update-labels label-nodes {:force? true}))
        (clear-batched-graph-updates!))

    (fn queue-graph-layout-refresh! [run-force?]
        (if (> batch-depth 0)
            (do
                (set batched-layout-dirty? true)
                (when run-force?
                    (set batched-force-layout? true)))
            (if run-force?
                (graph-layout:start)
                (graph-layout:update-lines))))

    (fn queue-label-refresh! [node]
        (if (> batch-depth 0)
            (queue-batched-label-refresh! node)
            (update-labels [node] {:force? true})))

    (fn with-batched-graph-updates [cb]
        (set batch-depth (+ batch-depth 1))
        (local (ok result) (pcall cb))
        (set batch-depth (- batch-depth 1))
        (if ok
            (do
                (when (= batch-depth 0)
                    (flush-batched-graph-updates!))
                result)
            (do
                (when (= batch-depth 0)
                    (clear-batched-graph-updates!))
                (error result))))

    (set movables-handler
         (GraphViewMovables {:ctx ctx
                         :movables movables
                         :persistence persistence
                         :pointer-target options.pointer-target
                         :on-position (fn [node position]
                                           (graph-layout:set-node-position node position {:skip-labels? true}))
                         :on-drag-start (fn [node _entry]
                                            (set drag-active? true)
                                            (set drag-node node))
                          :on-drag-end (fn [node _entry]
                                           (set drag-active? false)
                                           (set drag-node nil)
                                           (update-labels [node] {:force? true})
                                           (refresh-label-positions [node])
                                           (reconcile-graph-islands!))}))

    (set register-movable
         (fn [node point]
             (when movables-handler
                 (movables-handler:register node point))))

    (fn presentation-position [presentation]
        (glm.vec3 presentation.position.x
                  presentation.position.y
                  presentation.position.z))

    (fn build-compact-presentation [node position]
        (GraphNodePresentation.compact-point
            {:points points
             :position position
             :pointer-target (or options.pointer-target
                                 (and ctx ctx.pointer-target))
             :depth-offset-step point-depth-offset-step
             :base-depth-offset-index point-base-depth-offset
             :base-layer-index base-layer-index
             :layers [{:size 0
                       :color resolved-focus-outline-color}
                      {:size 0
                       :color resolved-selection-border-color}
                      {:size node.size
                       :color node.color}]}))

    (fn build-expanded-presentation [node position]
        (local saved-size (persistence:saved-size node))
        (local bounds (PanelBounds.inline-card-bounds))
        (local card-builder (GraphNodePresentation.card-builder
                              {:node node
                               :position position
                               :default-size bounds.default-size
                               :min-size bounds.min-size
                               :max-size bounds.max-size
                               :resize-max-size bounds.resize-max-size
                               :requested-size saved-size
                              :depth-offset-index point-base-depth-offset
                              :selection-color resolved-selection-border-color
                              :focus-color resolved-focus-outline-color
                              :pointer-target (or options.pointer-target
                                                  (and ctx ctx.pointer-target))
                              :on-collapse (fn [] (toggle-node-presentation node))
                              :on-open (fn [event]
                                         (local focus-node (. focus-nodes node))
                                         (when focus-node
                                             (focus-node:request-focus))
                                         (when focus-manager
                                             (focus-manager:arm-auto-focus {:event event}))
                                         (local (ok err) (pcall (fn [] (views:open node))))
                                         (when focus-manager
                                             (focus-manager:clear-auto-focus))
                                         (when (not ok)
                                             (error err)))
                               :on-menu (fn [event]
                                          (local focus-node (. focus-nodes node))
                                          (when focus-node
                                             (focus-node:request-focus))
                                         (local manager (get-menu-manager))
                                          (when manager
                                              (manager:open {:actions (node-menu-actions node)
                                                             :position (resolve-menu-position event)})))}))
        (card-builder ctx))
    (fn attach-presentation-events [node presentation]
        (set presentation.on-click
             (fn [_self _event]
                 (local focus-node (. focus-nodes node))
                 (when focus-node
                     (focus-node:request-focus))))
        (when (not presentation._card-size)
            (set presentation.on-double-click
                 (fn [_self event]
                     (if (Modifiers.alt-held? (and event event.mod))
                         (expand-linked-frontier graph-map [(tostring node.key)])
                         (toggle-node-presentation node))))
            (set presentation.on-right-click
                 (fn [_self event]
                     (local focus-node (. focus-nodes node))
                     (when focus-node
                         (focus-node:request-focus))
                     (local manager (get-menu-manager))
                     (when manager
                         (manager:open {:actions (node-menu-actions node)
                                        :position (resolve-menu-position event)}))))))

    (fn detach-presentation [node presentation]
        (when clickables
            (clickables:unregister presentation)
            (when clickables.unregister-right-click
                (clickables:unregister-right-click presentation))
            (clickables:unregister-double-click presentation)
            (set presentation.on-double-click nil)
            (set presentation.on-right-click nil))
        (when movables-handler
            (movables-handler:unregister node))
        (set (. node-by-point presentation) nil)
        (when (and presentation._card-size app.resizables presentation._resize-target)
          (app.resizables:unregister presentation._resize-target))
        (when presentation.drop
            (presentation:drop)))

    (fn install-presentation [node previous presentation]
        (attach-presentation-events node presentation)
        (clickables:register presentation)
        (when (not presentation._card-size)
            (when clickables.register-right-click
                (clickables:register-right-click presentation))
            (clickables:register-double-click presentation))
        (set (. registry.points node) presentation)
        (set (. node-by-point presentation) node)
        (when selector
            (selector:replace-selectable previous presentation))
        (register-movable node presentation)
        (attach-focus-bounds node)
        (update-point-state node)
        (when (and presentation._card-size app.resizables presentation._resize-target)
           (app.resizables:register presentation._resize-target
             {:target presentation._resize-target
              :handle presentation.layout
              :key presentation._resize-target
              :min-size presentation._min-size
              :max-size presentation._resize-max-size
              :on-resize-start (fn [entry _drag]
                               (set entry.target.position presentation.layout.position)
                               (set entry.target.size presentation._card-size)
                               (set entry.target.rotation presentation.layout.rotation)
                               entry)
             :on-resize-end (fn [entry]
                             (when (and entry entry.target persistence)
                               (persistence:set-size (. presentation :node) entry.target.size)))
             :pointer-target (or presentation._pointer-target
                                  (and options options.pointer-target)
                                  (and ctx ctx.pointer-target))})))

    (fn detach-node-signals [node]
        (local record (. node-changed-handlers node))
        (when record
            (when (and record record.signal record.handler)
                (record.signal:disconnect record.handler true))
            (set (. node-changed-handlers node) nil)))

    (fn attach-node-signals [node]
        (when (and node node.changed node.changed.connect (not (. node-changed-handlers node)))
            (local handler
                (node.changed:connect
                    (fn [_payload]
                        (when (. registry.points node)
                            (update-labels [node] {:force? true})))))
            (set (. node-changed-handlers node) {:signal node.changed
                                                 :handler handler})))

    (fn update [_self _delta]
        (assert-not-dropped "update")
        (local moved-nodes (graph-layout:update))
        (each [node point (pairs registry.points)]
            (when (and point point.position)
                (assert-valid-position point.position "GraphView.update.persist" node point)))
        (when (not drag-active?)
            (update-labels nil nil)
            (refresh-label-positions moved-nodes))
        (persistence:persist registry.points false))

    (fn drop-node-artifacts [node]
        (detach-node-signals node)
        (labels:drop-node node)
        (views:drop-node node))

    (var handle-edge-added nil)
    (var remove-extra-panel-entry! nil)

    (fn remove-live-scene-cube-panel! [node-key]
        (local scene (and app app.scene))
        (when (and scene scene.scene-children scene.remove-panel-child)
            (local to-remove [])
            (each [_ metadata (ipairs scene.scene-children)]
                (local persistence (and metadata metadata.persistence))
                (when (and persistence
                           (= persistence.kind "graph-node-cube")
                           (= persistence.node-key node-key)
                           (= persistence.graph-map-id graph-map-id))
                    (table.insert to-remove metadata.element)))
            (each [_ element (ipairs to-remove)]
                (scene:remove-panel-child element))))

    (fn drain-pending-edges []
        (local remaining-edges [])
        (each [_ pending (ipairs pending-edges)]
            (local edge pending.edge)
            (local source-ready? (registry:lookup (node-id edge.source)))
            (local target-ready? (registry:lookup (node-id edge.target)))
            (if (and source-ready? target-ready?)
                (handle-edge-added pending)
                (table.insert remaining-edges pending)))
        (for [i (length pending-edges) 1 -1]
            (table.remove pending-edges i))
        (each [_ pending (ipairs remaining-edges)]
            (table.insert pending-edges pending)))

    ;; Forward declaration or reordering needed since handle-node-added calls handle-edge-added
    (set handle-edge-added
         (fn [payload]
        (assert-not-dropped "handle-edge-added")
        (local edge (and payload payload.edge))
        (local edge-opts (and payload payload.opts))
        (when edge
            (local source-ready? (registry:lookup (node-id edge.source)))
            (local target-ready? (registry:lookup (node-id edge.target)))
            
            (if (and source-ready? target-ready?)
                (do
                    (local run-force? (if (= (and edge-opts edge-opts.run-force?) nil)
                                          true
                                          edge-opts.run-force?))
                    (local (record added?)
                          (registry:add-edge edge
                              (fn []
                                  (graph-layout:add-edge edge))))
                    (if added?
                        (queue-graph-layout-refresh! run-force?)
                        (do
                            (graph-layout:refresh-edge-line record)
                            (graph-layout:update-lines))))
                (do
                    ;; Queue pending edge
                    (table.insert pending-edges {:edge edge :opts edge-opts}))))
        edge))

    (fn handle-node-added [payload]
        (assert-not-dropped "handle-node-added")
        (local node (and payload payload.node))
        (local node-opts (and payload payload.opts))
        (when node
            (local existing (registry:lookup node.key))
            (when (not existing)
                (local run-force? (if (= (and node-opts node-opts.run-force?) nil)
                                      true
                                      node-opts.run-force?))
                (local position (ensure-glm-vec3 (or (persistence:saved-position node)
                                                     (and node-opts node-opts.position))
                                                 (next-position)))
                (assert-valid-position position "GraphView.add-node position" node)
                (local idx (graph-layout:add-node node position (and node-opts node-opts.pinned)))
                (assert (not (= idx nil)) "GraphView.add-node failed to allocate layout index")
                (local point (GraphNodePresentation.compact-point {:points points
                                            :position position
                                            :pointer-target (or options.pointer-target
                                                                (and ctx ctx.pointer-target))
                                            :depth-offset-step point-depth-offset-step
                                            :base-depth-offset-index point-base-depth-offset
                                            :base-layer-index base-layer-index
                                            :layers [{:size 0
                                                      :color resolved-focus-outline-color}
                                                     {:size 0
                                                      :color resolved-selection-border-color}
                                                     {:size node.size
                                                      :color node.color}]}))
                (assert point (string.format "GraphView.add-node failed to create point for %s"
                                             (node-id node)))
                (local focus-node (focus:create-node {:name (.. "graph-node-" (node-id node))
                                                       :parent points-focus-scope}))
                (bind-focus-node-activate node focus-node)
                (set (. focus-nodes node) focus-node)
                (set (. node-by-focus focus-node) node)
                (when (and focus-manager focus-node)
                    (local current-focused (focus-manager:get-focused-node))
                    (when (= current-focused focus-node)
                        (set focused-node node)
                        (update-point-state node))
                    (when (and (not current-focused)
                               (or (and node-opts node-opts.auto-focus?)
                                   (and node node.auto-focus?)))
                        (focus-node:request-focus)
                        (when node
                            (set node.auto-focus? false))))
                (set point.on-click
                     (fn [_self _event]
                         (focus-node:request-focus)))
                (set point.on-double-click
                     (fn [_self event]
                         (if (Modifiers.alt-held? (and event event.mod))
                             (expand-linked-frontier graph-map [(tostring node.key)])
                             (toggle-node-presentation node))))
                (set point.on-right-click
                     (fn [_self event]
                         (when focus-node
                             (focus-node:request-focus))
                         (local manager (get-menu-manager))
                         (when manager
                             (manager:open {:actions (node-menu-actions node)
                                            :position (resolve-menu-position event)}))))
                (clickables:register point)
                (when clickables.register-right-click
                    (clickables:register-right-click point))
                (clickables:register-double-click point)
                (registry:add-node node point idx (and node-opts node-opts.pinned))
                (when consume-initial-center!
                    (consume-initial-center! node))
                (attach-focus-bounds node)
                (register-movable node point)
                (when selector
                    (selector:add-selectables [point]))
                (queue-graph-layout-refresh! run-force?)
                (update-point-state node)
                (queue-label-refresh! node)
                (attach-node-signals node)
                (drain-pending-edges)
                (when (= (persistence:saved-presentation node) :expanded)
                    (toggle-node-presentation node)))))

    ;; Removed handle-edge-added from here as it was moved above

    (set toggle-node-presentation
         (fn [node]
        (assert-not-dropped "toggle-node-presentation")
        (when (not node) (lua "return nil"))
        (local current-point (. registry.points node))
        (when (not current-point) (lua "return nil"))
        (local expanded? (. expanded-nodes node))
        (local pos (presentation-position current-point))
        (if expanded?
            (do
              (local new-point (build-compact-presentation node pos))
              (detach-presentation node current-point)
              (install-presentation node current-point new-point)
              (set (. pinned node) (or (. pinned-before-expand node) false))
              (set (. pinned-before-expand node) nil)
              (set (. expanded-nodes node) nil)
              (queue-label-refresh! node)
              (persistence:set-presentation node nil)
              (graph-layout:rebuild))
            (do
              (local new-card (build-expanded-presentation node pos))
              (detach-presentation node current-point)
              (install-presentation node current-point new-card)
              (labels:drop-node node)
              (set (. pinned-before-expand node) (. pinned node))
              (set (. pinned node) true)
              (set (. expanded-nodes node) true)
              (persistence:set-presentation node :expanded)
              (graph-layout:rebuild)))))

    (fn handle-node-replaced [payload]
        (assert-not-dropped "handle-node-replaced")
        (local existing (and payload payload.old))
        (local node (and payload payload.new))
        (when (and existing node)
            (local was-expanded? (. expanded-nodes existing))
            (local saved-pin-before (. pinned-before-expand existing))
            (local had-saved-pin-before? (not (= saved-pin-before nil)))
            (when movables-handler
                (movables-handler:unregister existing))
            (local replacement (registry:replace existing node))
            (when was-expanded?
                (set (. expanded-nodes node) true)
                (set (. expanded-nodes existing) nil))
            (when had-saved-pin-before?
                (set (. pinned-before-expand node) saved-pin-before)
                (set (. pinned-before-expand existing) nil))
            (when (and replacement (not was-expanded?))
                (when replacement.point
                    (attach-presentation-events node replacement.point)
                    (set (. node-by-point replacement.point) node)
                    (register-movable node replacement.point)))
            (labels:move-label existing node)
            (views:move-view existing node)
            (detach-node-signals existing)
            (attach-node-signals node)
            (local focus-node (. focus-nodes existing))
            (when focus-node
                (set (. focus-nodes existing) nil)
                (set (. focus-nodes node) focus-node)
                (set (. node-by-focus focus-node) node)
                (bind-focus-node-activate node focus-node)
                (attach-focus-bounds node)
                (when (= focused-node existing)
                    (set focused-node node)))
            (local replacement-selection [])
            (each [_ selected (ipairs selected-nodes)]
                (table.insert replacement-selection
                              (if (= selected existing) node selected)))
            (selection:set-selection replacement-selection)
            (when was-expanded?
                ;; Rebuild the expanded card so its embedded widget belongs to the replacement node.
                (local old-presentation replacement.point)
                (set old-presentation.node node)
                (attach-presentation-events node old-presentation)
                (register-movable node old-presentation)
                (attach-focus-bounds node)
                (update-point-state node)
                (local position (presentation-position old-presentation))
                (local (build-ok replacement-card)
                       (pcall (fn [] (build-expanded-presentation node position))))
                (if build-ok
                    (do
                        (detach-presentation node old-presentation)
                        (install-presentation node old-presentation replacement-card)
                        (labels:drop-node node)
                        (set (. pinned node) true)
                        (set (. expanded-nodes node) true)
                        (persistence:set-presentation node :expanded)
                        (graph-layout:rebuild))
                    (do
                        (local compact (build-compact-presentation node position))
                        (detach-presentation node old-presentation)
                        (install-presentation node old-presentation compact)
                        (set (. pinned node) (or (. pinned-before-expand node) false))
                        (set (. pinned-before-expand node) nil)
                        (set (. expanded-nodes node) nil)
                        (queue-label-refresh! node)
                        (persistence:set-presentation node nil)
                        (graph-layout:rebuild)
                        (error replacement-card))))))

    (fn handle-nodes-removed [payload]
        (assert-not-dropped "handle-nodes-removed")
        (local removal-set (and payload payload.removal-set))
        (local nodes-to-remove (and payload payload.nodes))
        (when (and nodes-to-remove (> (length nodes-to-remove) 0))
            (local (removed-count removal-set)
                  (registry:remove-nodes nodes-to-remove
                       {:before-remove (fn [node point]
                                            (drop-node-artifacts node)
                                            (when (and clickables point)
                                                (clickables:unregister point)
                                                (when clickables.unregister-right-click
                                                    (clickables:unregister-right-click point))
                                                (clickables:unregister-double-click point)
                                                (set point.on-double-click nil)
                                                (set point.on-right-click nil))
                                            (when selector
                                                (selector:remove-selectables [point]))
                                            (when movables-handler
                                                (movables-handler:unregister node))
                                            (when (and point._card-size app.resizables point._resize-target)
                                                (app.resizables:unregister point._resize-target)))
                       :on-drop-point (fn [point]
                                           (when (and point point.drop)
                                               (point:drop)))}))
            (when (> removed-count 0)
                (when selector
                    (local remaining-selectables [])
                    (each [_ point (pairs registry.points)]
                        (table.insert remaining-selectables point))
                    (selector:set-selectables remaining-selectables)
                    (selector:set-selected []))
                (each [node _ (pairs removal-set)]
                    (when node.key
                        (when remove-extra-panel-entry!
                            (remove-extra-panel-entry! "graph-node-cube" node.key graph-map-id {:drop-panel? true}))
                        (remove-live-scene-cube-panel! node.key))
                    (when (. expanded-nodes node)
                        (persistence:set-presentation node nil))
                    (persistence:set-size node nil)
                    (when (and node node.key persistence.prune-node-key)
                        (persistence:prune-node-key node.key))
                    (set (. expanded-nodes node) nil)
                    (set (. pinned-before-expand node) nil)
                    (local focus-node (. focus-nodes node))
                    (when focus-node
                        (focus-node:drop)
                        (set (. focus-nodes node) nil)
                        (set (. node-by-focus focus-node) nil))
                    (set (. selected-set node) nil)
                    (when (= focused-node node)
                        (set focused-node nil)))
                (selection:prune removal-set)
                (graph-layout:rebuild))))

    (fn handle-edge-removed [payload]
        (assert-not-dropped "handle-edge-removed")
        (local edge (and payload payload.edge))
        (when edge
            (registry:remove-edges (fn [candidate] (= candidate edge)))
            (graph-layout:update-lines)))

    (var node-added-handler nil)
    (var node-removed-handler nil)
    (var node-replaced-handler nil)
    (var edge-added-handler nil)
    (var edge-removed-handler nil)
    (var island-added-handler nil)
    (var island-updated-handler nil)
    (var island-removed-handler nil)
    (var stabilized-handler nil)

    (fn handle-island-added-or-updated [payload]
        (assert-not-dropped "handle-island-added-or-updated")
        (local island (and payload payload.island))
        (when island
            (island-host:reconcile-island island)))

    (fn handle-island-removed [payload]
        (assert-not-dropped "handle-island-removed")
        (local island (and payload payload.island))
        (when island
            (island-host:drop-island island.id)))

    (fn attach-graph []
        (when (and graph-map.node-added (not node-added-handler))
            (set node-added-handler
                 (graph-map.node-added:connect handle-node-added)))
        (when (and graph-map.node-removed (not node-removed-handler))
            (set node-removed-handler
                 (graph-map.node-removed:connect handle-nodes-removed)))
        (when (and graph-map.node-replaced (not node-replaced-handler))
            (set node-replaced-handler
                 (graph-map.node-replaced:connect handle-node-replaced)))
        (when (and graph-map.edge-added (not edge-added-handler))
            (set edge-added-handler
                 (graph-map.edge-added:connect handle-edge-added)))
        (when (and graph-map.edge-removed (not edge-removed-handler))
            (set edge-removed-handler
                 (graph-map.edge-removed:connect handle-edge-removed)))
        (when (and graph-map.island-added (not island-added-handler))
            (set island-added-handler
                 (graph-map.island-added:connect handle-island-added-or-updated)))
        (when (and graph-map.island-updated (not island-updated-handler))
            (set island-updated-handler
                 (graph-map.island-updated:connect handle-island-added-or-updated)))
        (when (and graph-map.island-removed (not island-removed-handler))
            (set island-removed-handler
                 (graph-map.island-removed:connect handle-island-removed))))

    (fn detach-graph []
        (when (and graph-map.node-added node-added-handler)
            (graph-map.node-added:disconnect node-added-handler true)
            (set node-added-handler nil))
        (when (and graph-map.node-removed node-removed-handler)
            (graph-map.node-removed:disconnect node-removed-handler true)
            (set node-removed-handler nil))
        (when (and graph-map.node-replaced node-replaced-handler)
            (graph-map.node-replaced:disconnect node-replaced-handler true)
            (set node-replaced-handler nil))
        (when (and graph-map.edge-added edge-added-handler)
            (graph-map.edge-added:disconnect edge-added-handler true)
            (set edge-added-handler nil))
        (when (and graph-map.edge-removed edge-removed-handler)
            (graph-map.edge-removed:disconnect edge-removed-handler true)
            (set edge-removed-handler nil))
        (when (and graph-map.island-added island-added-handler)
            (graph-map.island-added:disconnect island-added-handler true)
            (set island-added-handler nil))
        (when (and graph-map.island-updated island-updated-handler)
            (graph-map.island-updated:disconnect island-updated-handler true)
            (set island-updated-handler nil))
        (when (and graph-map.island-removed island-removed-handler)
            (graph-map.island-removed:disconnect island-removed-handler true)
            (set island-removed-handler nil)))

    (when layout.stabilized
        (set stabilized-handler
             (layout.stabilized:connect (fn [] (persistence:schedule-save)))))

    (set selection-handler
         (selected-nodes-changed:connect (fn [nodes]
                                             (update-selection-set nodes))))
    (set focus-focus-handler
         (focus-manager.focus-focus:connect handle-focus-change))
    (set focus-blur-handler
         (focus-manager.focus-blur:connect handle-focus-change))

    (selection:attach)
    (selection:on-selection-changed)
    (update-selection-set selected-nodes)

    (attach-graph)
    (with-batched-graph-updates
        (fn []
            (each [_ node (pairs graph-map.nodes)]
                (handle-node-added {:node node}))
            (each [_ edge (ipairs graph-map.edges)]
                (handle-edge-added {:edge edge}))
            (reconcile-graph-islands!)))
    (when (and graph-map.selected_node_keys
               (> (length graph-map.selected_node_keys) 0))
        (local restored-selection [])
        (each [_ key (ipairs graph-map.selected_node_keys)]
            (local node (graph-map:lookup key))
            (when node
                (table.insert restored-selection node)))
        (selection:set-selection restored-selection))
    (when graph-map.focused_node_key
        (local node (graph-map:lookup graph-map.focused_node_key))
        (local focus-node (and node (. focus-nodes node)))
        (when focus-node
            (focus-node:request-focus)))

    (local view {:graph-map graph-map
                  :ctx ctx
                  :camera options.camera
                  :layout layout
                  :points registry.points
                 :node-by-point node-by-point
                 :movables movables
                 :movable-targets (and movables-handler movables-handler.targets)
                 :nodes nodes
                 :nodes-by-index nodes-by-index
                 :indices indices
                 :edges edges
                 :edge-map edge-map
                 :selected-nodes selected-nodes
                 :selected-nodes-changed selected-nodes-changed
                 :focus-nodes focus-nodes
                 :node-by-focus node-by-focus
                 :labels labels
                 :views views
                 :pinned pinned
                 :persistence persistence
                  :selection selection
                  :graph-layout graph-layout
                  :island-host island-host
                   :extra-panels []
                   :extra-panel-runtimes []})

    (fn extra-panel-persistence-matches? [persistence entry]
        (and (= (type persistence) :table)
             (= persistence.kind entry.kind)
             (= persistence.node-key entry.node-key)
             (= persistence.graph-map-id entry.graph-map-id)
             (= persistence.graph-map-id graph-map-id)))

    (fn find-extra-panel-runtime-by-entry [entry]
        (var found nil)
        (each [_ runtime (ipairs view.extra-panel-runtimes) &until found]
            (when (and (= runtime.kind entry.kind)
                       (= runtime.node-key entry.node-key)
                       (= runtime.graph-map-id entry.graph-map-id))
                (set found runtime)))
        found)

    (fn resolve-extra-panel-target-kind [target receiver-id]
        (if receiver-id
            (values "receiver" receiver-id)
            (= target app.hud) "hud"
            (= target app.scene) "scene"
            (= target view-target) "canvas"
            (not target) "canvas"
            (and app.panel-transfer app.panel-transfer.find-receiver-for-target)
            (do
                (local receiver (app.panel-transfer:find-receiver-for-target target))
                (if receiver
                    (values "receiver" receiver.id)
                    "canvas"))
            "canvas"))

    (fn handle-extra-panel-transferred [payload]
        (local persistence (and payload payload.persistence))
        (when (= (type persistence) :table)
            (var matched-entry nil)
            (each [_ entry (ipairs view.extra-panels) &until matched-entry]
                (when (extra-panel-persistence-matches? persistence entry)
                    (set matched-entry entry)))
            (when matched-entry
                (local target (or (and payload payload.target)
                                  (and payload payload.destination payload.destination.target)))
                (local (target-kind receiver-id)
                    (resolve-extra-panel-target-kind target (and payload payload.receiver-id)))
                (set matched-entry.target-kind target-kind)
                (set matched-entry.target-receiver-id receiver-id)
                (local runtime (find-extra-panel-runtime-by-entry matched-entry))
                (when runtime
                    (set runtime.target target)
                    (set runtime.element (and payload payload.new-element))))))

    (fn register-extra-panel-transfer-handler []
        (local pt (and app app.panel-transfer))
        (when (and pt pt.panel-transferred (not extra-panel-transfer-handler))
            (set extra-panel-transfer-source pt)
            (set extra-panel-transfer-handler
                 (pt.panel-transferred:connect handle-extra-panel-transferred))))

    (fn unregister-extra-panel-transfer-handler []
        (local pt extra-panel-transfer-source)
        (when (and pt pt.panel-transferred extra-panel-transfer-handler)
            (pt.panel-transferred:disconnect extra-panel-transfer-handler true)
            (set extra-panel-transfer-handler nil)
            (set extra-panel-transfer-source nil)))

    (register-extra-panel-transfer-handler)

    (set remove-extra-panel-entry!
         (fn [kind node-key graph-map-id opts]
             (local options (or opts {}))
             (for [i (length view.extra-panels) 1 -1]
                 (local entry (. view.extra-panels i))
                 (when (and (= entry.kind kind)
                            (= entry.node-key node-key)
                            (= entry.graph-map-id graph-map-id))
                     (table.remove view.extra-panels i)))
             (for [i (length view.extra-panel-runtimes) 1 -1]
                 (local record (. view.extra-panel-runtimes i))
                 (when (and (= record.kind kind)
                            (= record.node-key node-key)
                            (= record.graph-map-id graph-map-id))
                     (when (and options.drop-panel? record.target record.element record.target.remove-panel-child)
                         (record.target:remove-panel-child record.element))
                     (table.remove view.extra-panel-runtimes i)))))

    (fn find-extra-panel-entry [runtime]
        (var found nil)
        (each [_ entry (ipairs view.extra-panels) &until found]
            (when (and (= entry.kind runtime.kind)
                       (= entry.node-key runtime.node-key)
                       (= entry.graph-map-id runtime.graph-map-id))
                (set found entry)))
        found)

    (fn sync-extra-panel-runtime-state! [runtime]
        (local entry (find-extra-panel-entry runtime))
        (when (and entry runtime.target runtime.element runtime.target.capture-panel-element-state)
            (local panel-state (runtime.target:capture-panel-element-state runtime.element))
            (when panel-state
                (set entry.panel panel-state)))
        entry)

    (fn sync-extra-panel-runtime-states! []
        (each [_ runtime (ipairs view.extra-panel-runtimes)]
            (sync-extra-panel-runtime-state! runtime))
        view.extra-panels)

    (fn drop-extra-panel-runtimes! []
        (for [i (length view.extra-panel-runtimes) 1 -1]
            (local record (. view.extra-panel-runtimes i))
            (when (and record.target record.element record.target.remove-panel-child)
                (record.target:remove-panel-child record.element))
            (table.remove view.extra-panel-runtimes i)))

    (set view.remove-extra-panel-entry!
         (fn [_self kind node-key graph-map-id opts]
             (assert-not-dropped "remove-extra-panel-entry!")
             (remove-extra-panel-entry! kind node-key graph-map-id opts)
             true))

    (set view.register-extra-panel!
         (fn [_self entry target element]
             (assert-not-dropped "register-extra-panel!")
             (assert (= (type entry) :table) "GraphView.register-extra-panel! requires entry")
             (assert entry.kind "GraphView.register-extra-panel! requires entry.kind")
             (assert entry.node-key "GraphView.register-extra-panel! requires entry.node-key")
             (assert entry.graph-map-id "GraphView.register-extra-panel! requires entry.graph-map-id")
             (remove-extra-panel-entry! entry.kind entry.node-key entry.graph-map-id {:drop-panel? true})
             (table.insert view.extra-panels entry)
             (when (and target element)
                 (table.insert view.extra-panel-runtimes {:kind entry.kind
                                                          :node-key entry.node-key
                                                          :graph-map-id entry.graph-map-id
                                                          :target target
                                                           :element element}))
              entry))

    (fn resolve-view-node [node-or-key]
        (local node
            (if (= (type node-or-key) :string)
                (graph-map:lookup node-or-key)
                node-or-key))
        (assert node "GraphView reveal/open requires an existing graph-map node")
        (assert (. registry.points node)
                (.. "GraphView reveal/open requires mounted node: " (tostring node.key)))
        node)

    (fn presentation-center [presentation]
        (local bounds (bounds-for-presentation presentation))
        (assert bounds "GraphView reveal/open requires presentation bounds")
        (local position bounds.position)
        (local size bounds.size)
        (glm.vec3 (+ position.x (* size.x 0.5))
                  (+ position.y (* size.y 0.5))
                  (+ position.z (* size.z 0.5))))

    (fn center-camera-on-node! [node]
        (local camera options.camera)
        (assert camera "GraphView reveal-node requires :camera")
        (assert camera.position "GraphView reveal-node requires camera.position")
        (assert camera.set-position "GraphView reveal-node requires camera:set-position")
        (local center (presentation-center (. registry.points node)))
        (camera:set-position (glm.vec3 center.x center.y camera.position.z)))

    (fn find-initial-center-target []
        (local start-node (and graph-map.lookup (graph-map:lookup "start")))
        (if (and start-node (. registry.points start-node))
            start-node
            (do
                (var target-node nil)
                (each [_ node (ipairs nodes-by-index) &until target-node]
                    (when (. registry.points node)
                        (set target-node node)))
                target-node)))

    (fn camera-state-values=? [left right count]
        (var matches? true)
        (for [idx 1 count]
            (when (not (= (rawget left idx) (rawget right idx)))
                (set matches? false)))
        matches?)

    (fn camera-states=? [left right]
        (if (not left)
            false
            (not right)
            false
            (not left.position)
            false
            (not right.position)
            false
            (not (camera-state-values=? left.position right.position 3))
            false
            left.rotation
            (and right.rotation
                 (camera-state-values=? left.rotation right.rotation 4))
            right.rotation
            false
            true))

    (fn should-capture-initial-camera-state? [current-state armed-state]
        (if (not pending-initial-center?)
            true
            initial-center-consumed?
            true
            (camera-states=? current-state armed-state)
            false
            true))

    (fn capture-current-camera-state []
        (ActivityCameraState.capture-camera options.camera))

    (fn arm-pending-initial-center! []
        (set pending-initial-center? true)
        (set armed-initial-camera-state (capture-current-camera-state)))

    (fn should-capture-camera-state? []
        (should-capture-initial-camera-state? (capture-current-camera-state)
                                              armed-initial-camera-state))

    (set consume-initial-center!
         (fn [node]
             (when (and pending-initial-center?
                        (not initial-center-consumed?)
                        node
                        (. registry.points node))
                 (center-camera-on-node! node)
                 (set pending-initial-center? false)
                 (set initial-center-consumed? true)
                 (set armed-initial-camera-state nil)
                 true)))

    (set view.apply-initial-camera-policy!
         (fn [_self]
             (assert-not-dropped "apply-initial-camera-policy!")
             (if initial-center-consumed?
                 true
                 (do
                     (local target-node (find-initial-center-target))
                     (if target-node
                         (do
                              (center-camera-on-node! target-node)
                              (set initial-center-consumed? true)
                              (set pending-initial-center? false)
                              (set armed-initial-camera-state nil))
                          (arm-pending-initial-center!))
                      true))))

    (set view.remove-nodes (fn [_self nodes-to-remove]
                                (assert-not-dropped "remove-nodes")
                                (graph-map:remove-nodes nodes-to-remove)))
    (set view.remove-selected-nodes (fn [_self]
                                         (assert-not-dropped "remove-selected-nodes")
                                         (graph-map:remove-nodes selected-nodes)))
    (set view.reveal-node
         (fn [_self node-or-key opts]
             (assert-not-dropped "reveal-node")
             (local reveal-options (or opts {}))
             (local node (resolve-view-node node-or-key))
             (when (not (= reveal-options.select? false))
                 (selection:set-selection [node]))
             (when (not (= reveal-options.focus? false))
                 (local focus-node (. focus-nodes node))
                 (assert focus-node "GraphView reveal-node requires focus node")
                 (focus-node:request-focus))
             (when (not (= reveal-options.center? false))
                 (center-camera-on-node! node))
             node))
    (set view.open-node
         (fn [self node-or-key opts]
             (assert-not-dropped "open-node")
             (local node (self:reveal-node node-or-key opts))
             (views:open node)
             true))
    (set view.open-focused-node (fn [_self]
                                    (assert-not-dropped "open-focused-node")
                                   (when focused-node
                                       (views:open focused-node)
                                       true)))
    (set view.update update)
    (set view.get-position get-position)
    (set view.start-layout (fn [_self]
                               (assert-not-dropped "start-layout")
                               (graph-layout:start)))
    (set view.with-batched-updates
         (fn [_self cb]
             (assert-not-dropped "with-batched-updates")
             (assert (= (type cb) :function)
                     "GraphView.with-batched-updates requires callback")
             (with-batched-graph-updates cb)))
     (set view.capture-state
          (fn [_self]
              (assert-not-dropped "capture-state")
              (local keys (icollect [_ node (ipairs selected-nodes)]
                               (and node node.key)))
              (set graph-map.selected_node_keys keys)
              (set graph-map.focused_node_key (and focused-node focused-node.key))
              (sync-extra-panel-runtime-states!)
              (local view-state (and views views.capture-state (views:capture-state)))
              (when (and view-state view-state.open-views persistence.set-panels)
                  (persistence:set-panels view-state.open-views))
              (when persistence.set-extra-panels
                  (persistence:set-extra-panels (or view.extra-panels []))) (view:capture-camera-state!)
               (persistence:persist registry.points true)
               {:views view-state
               :selected_node_keys keys
               :extra_panels view.extra-panels}))
    (set view.restore-graph-state
         (fn [self state]
             (assert-not-dropped "restore-graph-state")
             (when (and graph-map graph-map.restore-state state)
                 (self:with-batched-updates
                   (fn []
                       (graph-map:restore-state state))))
             true))
    (set view.capture-camera-state!
         (fn [_self]
             (when (and options.camera
                        persistence
                        persistence.set-camera-state
                        (should-capture-camera-state?))
                 (local state (capture-current-camera-state))
                 (persistence:set-camera-state state)
                 state)))
    (set view.restore-views-state
         (fn [_self state]
             (assert-not-dropped "restore-views-state")
             (when (and views views.restore-state state)
                 (views:restore-state state))
             true))
    (fn resolve-extra-panel-target [entry]
        (if (= entry.target-kind nil) view-target
            (= entry.target-kind "canvas") view-target
            (= entry.target-kind "hud")
            (do
                (assert app.hud
                        "GraphView.restore-state extra panel target-kind hud requires app.hud")
                app.hud)
            (= entry.target-kind "scene")
            (do
                (assert app.scene
                        "GraphView.restore-state extra panel target-kind scene requires app.scene")
                app.scene)
            (= entry.target-kind "receiver")
            (do
                (assert entry.target-receiver-id
                        "GraphView.restore-state receiver extra panel requires target-receiver-id")
                (assert app.panel-transfer
                        "GraphView.restore-state receiver extra panel requires app.panel-transfer")
                (local receiver (app.panel-transfer:find-receiver-by-id entry.target-receiver-id))
                (assert receiver
                        (.. "GraphView.restore-state receiver not found for extra panel: "
                            entry.target-receiver-id))
                (local target (receiver.target-fn))
                (assert target
                        (.. "GraphView.restore-state receiver target-fn returned nil for extra panel: "
                            entry.target-receiver-id))
                target)
            (error (.. "GraphView.restore-state unknown extra panel target-kind: " entry.target-kind))))
    (set view.restore-state
         (fn [self state]
             (assert-not-dropped "restore-state")
             (local payload (or state {}))
              (when payload.views
                  (self:restore-views-state payload.views))
             (when payload.selected_node_keys
                 (local restored-selection [])
                 (each [_ key (ipairs payload.selected_node_keys)]
                     (local node (and graph-map graph-map.lookup (graph-map:lookup key)))
                     (when node
                         (table.insert restored-selection node)))
                 (selection:set-selection restored-selection))
              (when payload.extra_panels
                  ;; Snapshot to avoid aliasing when payload.extra_panels is view.extra-panels.
                  (local entries [])
                  (each [_ e (ipairs payload.extra_panels)]
                      (table.insert entries e))
                   (drop-extra-panel-runtimes!)
                   (set view.extra-panels [])
                    (each [_ entry (ipairs entries)]
                        (var restored? false)
                        (assert (= (type entry.graph-map-id) :string)
                                "GraphView.restore-state extra_panels entries require graph-map-id")
                        (assert (= (type entry.kind) :string)
                                 "GraphView.restore-state extra_panels entries require kind")
                        (when (and (= entry.graph-map-id graph-map-id)
                                    (= entry.kind "graph-node-cube"))
                            (assert (and app.scene app.scene.add-graph-node-cube)
                                    "GraphView.restore-state graph-node-cube extra panel requires app.scene.add-graph-node-cube")
                            (local size (array->vec3 (or (and entry.panel entry.panel.size) [4 4 4])))
                            (local position (array->vec3 (and entry.panel entry.panel.position)))
                            (local rotation (array->quat (or (and entry.panel entry.panel.rotation) [1 0 0 0])))
                             (local result
                               (app.scene:add-graph-node-cube {:node-key entry.node-key
                                                                :label (and entry.panel entry.panel.label)
                                                               :size (or size (glm.vec3 4 4 4))
                                                               :position position
                                                               :rotation (or rotation (glm.quat 1 0 0 0))
                                                                :graph-map-id entry.graph-map-id
                                                                :restore? true}))
                             (when result
                                 (local restored-entry {})
                                 (each [k v (pairs entry)]
                                     (set (. restored-entry k) v))
                                 (when (= restored-entry.target-kind nil)
                                     (set restored-entry.target-kind "scene"))
                                 (self:register-extra-panel! restored-entry app.scene result)
                                 (set restored? true)))
                      (when (and (= entry.graph-map-id graph-map-id)
                                 entry.kind entry.restorer-module
                                 (not= entry.kind "graph-node-cube"))
                          (local (ok module-or-err) (pcall require entry.restorer-module))
                          (assert ok
                                  (.. "GraphView.restore-state failed requiring extra panel restorer module "
                                      entry.restorer-module
                                      ": "
                                      (tostring module-or-err)))
                          (assert (= (type module-or-err.open-panel) :function)
                                  (.. "GraphView.restore-state extra panel restorer module "
                                      entry.restorer-module
                                      " must export function :open-panel"))
                          (local target (resolve-extra-panel-target entry))
                          (when target
                              (local result
                                (module-or-err.open-panel {:target target
                                                            :restore? true
                                                            :panel {:node-key entry.node-key
                                                                    :graph-map-id entry.graph-map-id
                                                                    :panel entry.panel}}))
                              (when result
                                  (set restored? true))))
                     (when (and (= entry.graph-map-id graph-map-id)
                                (not= entry.kind "graph-node-cube")
                                (not entry.restorer-module))
                         (error (.. "GraphView.restore-state extra panel kind "
                                    entry.kind
                                    " requires restorer-module")))
                      restored?))
             true))
    (set view.drop
         (fn [_self]
             (assert-not-dropped "drop")
              (set dropped? true)
              (detach-graph)
              (island-host:drop)
              (selection:drop)
             (when (and selected-nodes-changed selection-handler)
                 (selected-nodes-changed:disconnect selection-handler true)
                 (set selection-handler nil))
             (when (and focus-manager focus-focus-handler)
                 (focus-manager.focus-focus:disconnect focus-focus-handler true)
                 (set focus-focus-handler nil))
             (when (and focus-manager focus-blur-handler)
                 (focus-manager.focus-blur:disconnect focus-blur-handler true)
                 (set focus-blur-handler nil))
              (each [node point (pairs registry.points)]
                  (when (and point point.position)
                      (assert-valid-position point.position "GraphView.drop.persist" node point)))
              (local (capture-ok capture-err)
                (pcall
                  (fn []
                    (when (and views views.capture-state)
                        (local view-state (views:capture-state))
                        (when (and view-state view-state.open-views persistence.set-panels)
                            (persistence:set-panels view-state.open-views)))
                    (when (and persistence.set-extra-panels)
                        (sync-extra-panel-runtime-states!)
                        (persistence:set-extra-panels (or view.extra-panels []))) (view:capture-camera-state!)
                     (persistence:persist registry.points true))))
             (drop-extra-panel-runtimes!)
             (when (and layout.stabilized stabilized-handler)
                 (layout.stabilized:disconnect stabilized-handler true)
                 (set stabilized-handler nil))
             (each [_ record (ipairs edges)]
                 (registry:drop-edge record))
             (for [i (length edges) 1 -1]
                 (table.remove edges i))
             (labels:drop-all)
            (when movables-handler
                (movables-handler:drop-all))
            (each [_ point (pairs registry.points)]
                (when clickables
                    (clickables:unregister point)
                    (when clickables.unregister-right-click
                        (clickables:unregister-right-click point))
                    (clickables:unregister-double-click point)
                    (set point.on-double-click nil)
                    (set point.on-right-click nil))
                (when selector
                    (selector:remove-selectables [point]))
                (set (. node-by-point point) nil)
                (when (and point._card-size app.resizables point._resize-target)
                    (app.resizables:unregister point._resize-target))
                (when point.drop
                    (point:drop)))
            (each [node focus-node (pairs focus-nodes)]
                (when focus-node
                    (focus-node:drop))
                (set (. focus-nodes node) nil))
            (when points-focus-scope
                (points-focus-scope:drop)
                (set points-focus-scope nil))
             (each [focus-node _ (pairs node-by-focus)]
                 (set (. node-by-focus focus-node) nil))
             (each [node _ (pairs selected-set)]
                 (set (. selected-set node) nil))
             (set focused-node nil)
              (set drag-active? false) (set drag-node nil)
              (clear-batched-graph-updates!)
              (unregister-extra-panel-transfer-handler)
              (each [node _ (pairs expanded-nodes)]
                  (set (. expanded-nodes node) nil))
             (each [node _ (pairs pinned-before-expand)]
                 (set (. pinned-before-expand node) nil))
             (set view.movable-targets (and movables-handler movables-handler.targets))
             (each [_ node (pairs nodes)]
                 (drop-node-artifacts node))
             (views:drop-all)
              (layout:clear)
              (each [node _ (pairs pinned)]
                  (set (. pinned node) nil))
              (when (not capture-ok)
                  (error capture-err))))
    view)


GraphView
