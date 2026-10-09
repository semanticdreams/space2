(local glm (require :glm))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local GraphMapManager (require :graph/map-manager))
(local Edge (require :graph/edge))
(local GraphOutline (require :graph/outline))
(local GraphView (require :graph/view))
(local CommandHelpers (require :tests/graph-command-helpers))
(local Clickables (require :clickables))
(local ObjectSelector (require :object-selector))
(local {:FocusManager FocusManager} (require :focus))
(local {:Layout Layout :LayoutRoot LayoutRoot} (require :layout))

(local tests [])

(fn approx [actual expected]
    (< (math.abs (- actual expected)) 0.0001))

(fn preview-measurer [self]
    (set self.measure (glm.vec3 24 12 0)))

(fn preview-constrained-measurer [self _constraints]
    (set self.measure (glm.vec3 24 12 0)))

(fn preview-layouter [_self]
    nil)

(fn preview-drop [widget]
    (set widget.state.dropped? true)
    (widget.layout:drop))

(fn build-preview-widget [state node]
    (set state.built-node node)
    (local layout (Layout {:name "outline-compact-preview"
                           :measurer preview-measurer
                           :constrained-measurer preview-constrained-measurer
                           :layouter preview-layouter}))
    {:layout layout
     :state state
     :drop preview-drop})

(fn tracked-preview [state]
    (fn preview-for-node [node _opts]
        (fn preview-builder [_ctx]
            (build-preview-widget state node)))
    preview-for-node)

(fn register-test-loader [graph]
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key
                              :label key
                              :preview (tracked-preview {})})))
    graph)

(fn make-map []
    (local graph (register-test-loader (Graph {:with-start false})))
    (local graph-map (GraphMap.GraphMap {:graph graph :id "outline-test" :name "Outline Test"}))
    {:graph graph :graph-map graph-map})

(fn add-edge! [graph-map source-key target-key]
    (local source (if (graph-map:lookup source-key)
                      (graph-map:lookup source-key)
                      (graph-map:load-by-key source-key)))
    (local target (if (graph-map:lookup target-key)
                      (graph-map:lookup target-key)
                      (graph-map:load-by-key target-key)))
    (assert source (.. "missing test graph source: " source-key))
    (assert target (.. "missing test graph target: " target-key))
    (graph-map:add-edge (Edge.GraphEdge {:source source :target target})))

(fn drop-noop [_self] nil)

(fn make-drop-handle []
    {:drop drop-noop})

(fn make-test-font []
    (local glyph {:advance 8
                  :planeBounds {:left 0 :bottom 0 :right 8 :top 10}
                  :atlasBounds {:left 0 :bottom 0 :right 8 :top 10}})
    (local font {:glyph-map {}
                 :metadata {:metrics {:lineHeight 12 :ascender 10 :descender -2}
                            :atlas {:distanceRange 4}}})
    (for [codepoint 32 126]
        (set (. font.glyph-map codepoint) glyph))
    (set (. font.glyph-map 65533) glyph)
    font)

(fn make-icons-stub []
    (local glyph {:advance 1})
    (local font {:metadata {:metrics {:ascender 1 :descender -1}
                            :atlas {:width 1 :height 1}}
                 :glyph-map {65533 glyph
                             4242 glyph}})
    (local stub {:font font
                 :codepoints {:close_fullscreen 4242
                              :open_in_new 4242
                              :more_vert 4242}})
    (set stub.get
         (fn [self name]
             (local value (. self.codepoints name))
             (assert value (.. "Missing icon " name))
             value))
    (set stub.resolve
         (fn [self name]
             {:type :font
              :codepoint (self:get name)
              :font self.font}))
    stub)

(fn make-hoverables-stub []
    {:register (fn [_self _obj] nil)
     :unregister (fn [_self _obj] nil)})

(fn make-text-batcher-stub [events]
    {:upsert-text (fn [_self _key payload]
                    (table.insert events {:kind :text-upsert :text payload.codepoints}))
     :update-text-transform (fn [_self _key _payload]
                              (table.insert events {:kind :text-transform}))
     :remove-text (fn [_self _key]
                    (table.insert events {:kind :text-remove}))})

(fn make-quad-batcher-stub [events]
    {:upsert-quad (fn [_self _key payload]
                    (table.insert events {:kind :quad-upsert :color payload.color}))
     :remove-quad (fn [_self _key]
                    (table.insert events {:kind :quad-remove}))})

(fn point-set-position [self position]
    (set self.position position))

(fn point-set-position-values [self x y z]
    (set self.position (glm.vec3 x y z)))

(fn point-set-color [self color]
    (set self.color color))

(fn point-set-size [self size]
    (set self.size size))

(fn point-set-depth-offset-index [self depth-offset-index]
    (set self.depth-offset-index depth-offset-index))

(fn point-intersect [self ray]
    (local direction (assert (and ray ray.direction) "point intersect requires ray.direction"))
    (local origin (assert ray.origin "point intersect requires ray.origin"))
    (if (= direction.z 0)
        (values false nil nil)
        (do
            (local distance (/ (- self.position.z origin.z) direction.z))
            (if (< distance 0)
                (values false nil nil)
                (do
                    (local point (+ origin (* direction distance)))
                    (local half (/ (or self.size 0) 2.0))
                    (if (and (<= (math.abs (- point.x self.position.x)) half)
                             (<= (math.abs (- point.y self.position.y)) half))
                        (values true point distance)
                        (values false nil nil)))))))

(fn point-drop [self]
    (set self.dropped? true))

(fn make-points-stub [events]
    (local created [])
    {:created created
     :create-point (fn [_self opts]
                     (local point {:position opts.position
                                   :color opts.color
                                   :size opts.size
                                   :depth-offset-index opts.depth-offset-index
                                   :set-position point-set-position
                                   :set-position-values point-set-position-values
                                   :set-color point-set-color
                                   :set-size point-set-size
                                   :set-depth-offset-index point-set-depth-offset-index
                                   :intersect point-intersect
                                   :drop point-drop})
                     (table.insert created point)
                     (table.insert events {:kind :point-create
                                           :position opts.position
                                           :color opts.color
                                           :size opts.size
                                           :depth-offset-index opts.depth-offset-index})
                     point)})

(fn add-render-stub [_self]
    (make-drop-handle))

(fn register-clickable-stub [_self _target]
    (make-drop-handle))

(fn unregister-clickable-stub [_self _target]
    nil)

(fn create-focus-scope-stub [_self _opts]
    (make-drop-handle))

(fn make-render-ctx []
    (local render-events [])
    (local text-batcher (make-text-batcher-stub render-events))
    (local quad-batcher (make-quad-batcher-stub render-events))
    {:triangle-vector {:add add-render-stub}
     :points (make-points-stub render-events)
     :clickables {:register register-clickable-stub
                  :unregister unregister-clickable-stub
                  :register-right-click register-clickable-stub
                  :unregister-right-click unregister-clickable-stub
                  :register-double-click register-clickable-stub
                  :unregister-double-click unregister-clickable-stub}
      :focus {:create-scope create-focus-scope-stub}
      :layout-root (LayoutRoot {:log-dirt? false})
      :icons (make-icons-stub)
      :hoverables (make-hoverables-stub)
      :theme {:graph {:selection-border-color (glm.vec4 1 0.6 0.2 1)}
             :input {:focus-outline (glm.vec4 0.2 0.6 1 1)}
             :font (make-test-font)
             :text {:foreground (glm.vec4 0.8 0.8 0.8 1) :scale 1.0}}
     :render-events render-events
     :get-text-ssbo-batcher (fn [_self] text-batcher)
     :get-rectangle-quad-batcher (fn [_self] quad-batcher)})

(fn identity-project [position _opts]
    position)

(fn make-focus-ctx []
    (local manager (FocusManager {:root-name "outline-selection-focus-test"}))
    (local scope (manager:create-scope {:name "outline"}))
    (manager:attach scope (manager:get-root-scope))
    {:manager manager
     :scope scope
     :create-node (fn [self opts]
                     (local node (manager:create-node opts))
                     (manager:attach node (if (and opts opts.parent)
                                              opts.parent
                                              self.scope))
                     node)
      :attach-bounds (fn [_self node opts]
                       (set node.position (and opts opts.position))
                       (set node.size (and opts opts.size))
                       (set node.get-bounds (and opts opts.get-bounds))
                       node)})

(fn make-render-ctx-with-focus []
    (local ctx (make-render-ctx))
    (set ctx.focus (make-focus-ctx))
    ctx)

(fn count-render-events [ctx kind]
    (accumulate [count 0 _ event (ipairs ctx.render-events)]
        (if (= event.kind kind) (+ count 1) count)))

(fn render-events-of-kind [ctx kind]
    (local matches [])
    (each [_ event (ipairs ctx.render-events)]
        (when (= event.kind kind)
            (table.insert matches event)))
    matches)

(fn outline-layer-point [ctx row-index layer-index]
    (local point-index (+ (* (- row-index 1) 3) layer-index))
    (assert (. ctx.points.created point-index)
            (.. "missing outline point layer " point-index)))

(fn with-screen-ray [body]
    (local original app.screen-pos-ray)
    (set app.screen-pos-ray
         (fn [pointer]
             {:origin (glm.vec3 pointer.x pointer.y 10)
              :direction (glm.vec3 0 0 -1)}))
    (local (ok result) (pcall body))
    (set app.screen-pos-ray original)
    (if ok
        result
        (error result)))

(fn make-real-render-ctx [clickables]
    (assert clickables "outline test requires clickables")
    (local ctx (make-render-ctx))
    (set ctx.clickables clickables)
    (assert ctx.clickables "outline test render ctx requires clickables")
    ctx)

(fn click-row [clickables x y button timestamp]
    (local payload {:button button :x x :y y :timestamp timestamp})
    (clickables:on-mouse-button-down payload)
    (clickables:on-mouse-button-up payload))

(fn view-record-for-key [view key]
    (var found nil)
    (each [_ record (ipairs (or view.row-handles [])) &until found]
        (when (and record record.row (= record.row.key key))
            (set found record)))
    (assert found (.. "missing outline record for " key)))

(fn click-position [clickables position button timestamp]
    (click-row clickables position.x position.y button timestamp))

(fn click-record-point [clickables record button timestamp]
    (local point (assert record.point "outline record requires compact point"))
    (click-position clickables point.position button timestamp))

(fn offset-position [position dx dy]
    (glm.vec3 (+ position.x dx) (+ position.y dy) position.z))

(fn row-keys [rows]
    (icollect [_ row (ipairs rows)] row.key))

(fn row-depths [rows]
    (icollect [_ row (ipairs rows)] row.depth))

(fn outline-builds-reachable-outgoing-depth-first-rows []
    (local {:graph graph :graph-map graph-map} (make-map))
    (add-edge! graph-map "test:root" "test:a")
    (add-edge! graph-map "test:a" "test:a1")
    (add-edge! graph-map "test:root" "test:b")
    (graph-map:load-by-key "test:unreachable")
    (local rows (GraphOutline.build-rows graph-map ["test:root"]))
    (assert (= (table.concat (row-keys rows) ",") "test:root,test:a,test:a1,test:b")
            "outline should include only outgoing reachable nodes in depth-first order")
    (assert (= (table.concat (row-depths rows) ",") "0,1,2,1")
            "outline should assign indentation depth from roots")
    (graph-map:drop)
    (graph:drop))

(fn outline-skips-incoming-only-edges []
    (local {:graph graph :graph-map graph-map} (make-map))
    (add-edge! graph-map "test:parent" "test:root")
    (local rows (GraphOutline.build-rows graph-map ["test:root"]))
    (assert (= (table.concat (row-keys rows) ",") "test:root")
            "outline should not walk incoming edges")
    (graph-map:drop)
    (graph:drop))

(fn outline-handles-cycles-and-shared-nodes-by-first-occurrence []
    (local {:graph graph :graph-map graph-map} (make-map))
    (add-edge! graph-map "test:root" "test:a")
    (add-edge! graph-map "test:a" "test:root")
    (add-edge! graph-map "test:root" "test:b")
    (add-edge! graph-map "test:b" "test:a")
    (local rows (GraphOutline.build-rows graph-map ["test:root"]))
    (assert (= (table.concat (row-keys rows) ",") "test:root,test:a,test:b")
            "outline should emit each key once at first occurrence")
    (graph-map:drop)
    (graph:drop))

(fn graph-map-persists-outline-mode-and-roots []
    (local {:graph graph :graph-map graph-map} (make-map))
    (graph-map:load-by-key "test:root")
    (graph-map:load-by-key "test:child")
    (assert (= graph-map.view_mode "spatial") "GraphMap should default to spatial mode")
    (assert (= (length graph-map.outline_root_keys) 0) "GraphMap should default to no outline roots")
    (graph-map:set-view-mode! "outline")
    (graph-map:set-outline-root-keys! ["test:root" "test:missing" "test:root" "test:child"])
    (assert (= (table.concat graph-map.outline_root_keys ",") "test:root,test:child")
            "GraphMap should keep visible unique outline roots in input order")
    (local state (graph-map:capture-state))
    (local restored (GraphMap.GraphMap {:graph graph :id "restored-outline"}))
    (restored:restore-state state)
    (assert (= restored.view_mode "outline") "restore should keep outline mode")
    (assert (= (table.concat restored.outline_root_keys ",") "test:root,test:child")
            "restore should keep valid outline roots")
    (restored:drop)
    (graph-map:drop)
    (graph:drop))

(fn graph-map-prunes-removed-outline-roots []
    (local {:graph graph :graph-map graph-map} (make-map))
    (local root (graph-map:load-by-key "test:root"))
    (graph-map:load-by-key "test:child")
    (graph-map:set-outline-root-keys! ["test:root" "test:child"])
    (graph-map:remove-nodes [root])
    (assert (= (table.concat graph-map.outline_root_keys ",") "test:child")
            "removing a node should prune matching outline roots")
    (graph-map:drop)
    (graph:drop))

(fn map-manager-persists-outline-state-per-map []
    (local graph (register-test-loader (Graph {:with-start false})))
    (local manager (GraphMapManager.GraphMapManager
                     {:graph graph
                      :state {:active_map_id "main"
                              :next_map_id 3
                              :maps [{:id "main"
                                      :name "Main"
                                      :nodes ["test:main-root"]
                                      :edges []
                                      :view_mode "outline"
                                      :outline_root_keys ["test:main-root"]}
                                     {:id "map-2"
                                      :name "Second"
                                      :nodes ["test:second-root"]
                                      :edges []
                                      :view_mode "spatial"
                                      :outline_root_keys ["test:second-root"]}]}}))
    (local main-map (manager:get-active-map))
    (assert (= main-map.view_mode "outline") "active map should hydrate persisted outline mode")
    (assert (= (table.concat main-map.outline_root_keys ",") "test:main-root")
            "active map should hydrate persisted outline roots")
    (manager:switch-map! "map-2")
    (local second-map (manager:get-active-map))
    (assert (= second-map.view_mode "spatial") "second map should keep its own mode")
    (second-map:set-view-mode! "outline")
    (local captured (manager:capture-state))
    (local by-id {})
    (each [_ entry (ipairs captured.maps)]
        (set (. by-id entry.id) entry))
    (assert (= (. by-id "main" :view_mode) "outline") "inactive map capture should keep outline mode")
    (assert (= (table.concat (. by-id "main" :outline_root_keys) ",") "test:main-root")
            "inactive map capture should keep outline roots")
    (assert (= (. by-id "map-2" :view_mode) "outline") "active map capture should keep changed outline mode")
    (assert (= (table.concat (. by-id "map-2" :outline_root_keys) ",") "test:second-root")
            "active map capture should keep outline roots")
    (manager:drop)
    (graph:drop))

(fn outline-view-exposes-visible-row-selection []
    (local {:graph graph :graph-map graph-map} (make-map))
    (add-edge! graph-map "test:root" "test:child")
    (graph-map:set-view-mode! "outline")
    (graph-map:set-outline-root-keys! ["test:root"])
    (local view (GraphView {:graph-map graph-map :ctx (make-render-ctx)}))
    (assert (= (view:selected-node-count) 0) "outline view should start with no selected rows")
    (view:reveal-node "test:child" {:select? true :focus? true})
    (assert (= graph-map.focused_node_key "test:child") "outline reveal should focus visible rows")
    (assert (= (table.concat graph-map.selected_node_keys ",") "test:child") "outline reveal should select visible rows")
    (view:drop)
    (graph-map:drop)
    (graph:drop))

(fn outline-reveal-refreshes-node-selection-rings []
    (local {:graph graph :graph-map graph-map} (make-map))
    (add-edge! graph-map "test:root" "test:child")
    (graph-map:set-view-mode! "outline")
    (graph-map:set-outline-root-keys! ["test:root"])
    (local ctx (make-render-ctx))
    (local view (GraphView {:graph-map graph-map :ctx ctx}))
    (local child-focus-ring (outline-layer-point ctx 2 1))
    (local child-selection-ring (outline-layer-point ctx 2 2))
    (assert (= child-focus-ring.size 0) "child focus ring should start hidden")
    (assert (= child-selection-ring.size 0) "child selection ring should start hidden")
    (view:reveal-node "test:child" {:select? true :focus? true})
    (assert (> child-focus-ring.size 0)
            "reveal-node should refresh child focus ring immediately")
    (assert (> child-selection-ring.size 0)
            "reveal-node should refresh child selection ring immediately")
    (local child-record (. view.row-handles 2))
    (local child-label (assert (. child-record :visuals 2)
                               "child row should keep its label visual"))
    (assert (approx child-label.layout.position.x (+ child-focus-ring.position.x (/ child-focus-ring.size 2.0) 1.0))
            (.. "reveal-node should keep child label past expanded focus ring, got "
                (tostring child-label.layout.position.x)))
    (view:clear-selection)
    (assert (= child-selection-ring.size 0)
            "clear-selection should refresh child selection ring immediately")
    (view:drop)
    (graph-map:drop)
    (graph:drop))

(fn outline-view-rejects-unreachable-reveal []
    (local {:graph graph :graph-map graph-map} (make-map))
    (graph-map:load-by-key "test:root")
    (graph-map:load-by-key "test:other")
    (graph-map:set-view-mode! "outline")
    (graph-map:set-outline-root-keys! ["test:root"])
    (local view (GraphView {:graph-map graph-map :ctx (make-render-ctx)}))
    (local (ok message) (pcall (fn [] (view:reveal-node "test:other" {:select? true}))))
    (assert (not ok) "outline reveal should fail for hidden map nodes")
    (assert (string.find (tostring message) "not visible") "outline reveal error should explain visibility")
    (view:drop)
    (graph-map:drop)
    (graph:drop))

(fn outline-compact-point-clicks-body []
    (local {:graph graph :graph-map graph-map} (make-map))
    (add-edge! graph-map "test:root" "test:child")
    (graph-map:set-view-mode! "outline")
    (graph-map:set-outline-root-keys! ["test:root"])
    (graph-map:set-selected-node-keys ["test:root"])
    (local clickables (Clickables))
    (local view (GraphView {:graph-map graph-map :ctx (make-real-render-ctx clickables)}))
    (local child-record (view-record-for-key view "test:child"))
    (assert (= (. clickables.left-click-objects 2) child-record.point)
            "outline should register compact point as left-click target")
    (assert (= (. clickables.right-click-objects 2) child-record.point)
            "outline should register compact point as right-click target")
    (assert (= (. clickables.double-click-objects 2) child-record.point)
            "outline should register compact point as double-click target")
    (click-record-point clickables child-record 1 100)
    (assert (= graph-map.focused_node_key "test:child")
            "compact point click should focus hit-tested child node")
    (assert (= (table.concat graph-map.selected_node_keys ",") "test:root")
            "compact point click should preserve existing selection")
    (view:drop)
    (graph-map:drop)
    (graph:drop))

(fn outline-compact-point-clicks-use-real-hit-testing []
    (with-screen-ray outline-compact-point-clicks-body))

(fn outline-row-whitespace-and-label-misses-body []
    (local original-menu-manager app.menu-manager)
    (local {:graph graph :graph-map graph-map} (make-map))
    (add-edge! graph-map "test:root" "test:child")
    (graph-map:set-view-mode! "outline")
    (graph-map:set-outline-root-keys! ["test:root"])
    (graph-map:set-selected-node-keys ["test:root"])
    (local clickables (Clickables))
    (var opened-menu nil)
    (var opened-node-key nil)
    (set app.menu-manager {:open (fn [_self opts] (set opened-menu opts))})
    (local view (GraphView {:graph-map graph-map :ctx (make-real-render-ctx clickables)}))
    (set view.node-views.open
         (fn [_self node _opts]
             (set opened-node-key node.key)))
    (local child-record (view-record-for-key view "test:child"))
    (click-position clickables (offset-position child-record.point.position 80 0) 1 100)
    (click-position clickables (offset-position child-record.point.position 20 0) 3 200)
    (click-position clickables (offset-position child-record.point.position 80 0) 1 300)
    (click-position clickables (offset-position child-record.point.position 80 0) 1 500)
    (assert (= graph-map.focused_node_key nil)
            "row whitespace or label area outside compact point should not focus")
    (assert (= (table.concat graph-map.selected_node_keys ",") "test:root")
            "row whitespace or label area outside compact point should preserve selection")
    (assert (= opened-menu nil)
            "right-clicking row whitespace should not open menu")
    (assert (= opened-node-key nil)
            "double-clicking row whitespace should not activate/open node")
    (view:drop)
    (graph-map:drop)
    (graph:drop)
    (set app.menu-manager original-menu-manager))

(fn outline-row-whitespace-and-label-misses-use-real-hit-testing []
    (with-screen-ray outline-row-whitespace-and-label-misses-body))

(fn outline-compact-point-click-syncs-selector-and-focus-manager-body []
    (local {:graph graph :graph-map graph-map} (make-map))
    (add-edge! graph-map "test:root" "test:child")
    (graph-map:set-view-mode! "outline")
    (graph-map:set-outline-root-keys! ["test:root"])
    (graph-map:set-selected-node-keys ["test:root"])
    (local clickables (Clickables))
    (local ctx (make-render-ctx-with-focus))
    (set ctx.clickables clickables)
    (local selector (ObjectSelector {:project identity-project :ctx ctx :enabled? true}))
    (local view (GraphView {:graph-map graph-map :ctx ctx :selector selector}))
    (local root-record (view-record-for-key view "test:root"))
    (local child-record (view-record-for-key view "test:child"))
    (click-record-point clickables child-record 1 100)
    (assert child-record.selectable "visible outline compact points should expose selector entries")
    (assert child-record.focus-node "visible outline compact points should expose focus nodes")
    (assert (= child-record.selectable child-record.point)
            "outline selector entry should be the compact point presentation")
    (local bounds (and child-record.focus-node.get-bounds
                      (child-record.focus-node:get-bounds)))
    (assert bounds "outline focus node should expose dynamic compact point bounds")
    (assert (approx bounds.size.x child-record.point.size)
            "outline focus bounds width should match compact point size")
    (assert (approx bounds.size.y child-record.point.size)
            "outline focus bounds height should match compact point size")
    (assert (= graph-map.focused_node_key "test:child") "compact point click should keep graph-map focused key")
    (assert (= (table.concat graph-map.selected_node_keys ",") "test:root") "compact point click should preserve graph-map selected key")
    (assert (= (. selector.selected 1) root-record.selectable) "compact point click should preserve the selected outline point in ObjectSelector")
    (assert (= (ctx.focus.manager:get-focused-node) child-record.focus-node) "compact point click should focus the outline focus node")
    (assert (= (view:select-all-visible-nodes) true) "select-all should work for outline compact points")
    (assert (= (length selector.selected) 2) "select-all should sync all visible outline compact points to ObjectSelector")
    (assert (= (view:clear-selection) true) "clear-selection should work for outline compact points")
    (assert (= (length selector.selected) 0) "clear-selection should clear ObjectSelector outline compact points")
    (graph-map:set-selected-node-keys ["test:child"])
    (assert (= (. selector.selected 1) child-record.selectable) "graph-map selection changes should sync to ObjectSelector")
    (assert (= (view:focus-selected-node) true) "focus-selected-node should focus one selected outline compact point")
    (assert (= (ctx.focus.manager:get-focused-node) child-record.focus-node) "focus-selected-node should request focus on the outline focus node")
    (root-record.focus-node:request-focus {:reason :test})
    (assert (= graph-map.focused_node_key "test:root") "focus-manager focus changes should sync to graph-map focused key")
    (view:reveal-node "test:child" {:select? true :focus? true})
    (local old-child-selectable child-record.selectable)
    (graph-map:set-outline-root-keys! ["test:child"])
    (local rebuilt-child-record (. view.row-handles 1))
    (assert (= (length selector.selectables) 1) "rebuild should remove stale outline compact point selectables")
    (assert (not (= (. selector.selectables 1) old-child-selectable)) "rebuild should replace stale outline compact point selectables")
    (assert (= (. selector.selected 1) rebuilt-child-record.selectable) "rebuild should keep selection synchronized to the new outline compact point")
    (assert (= (ctx.focus.manager:get-focused-node) rebuilt-child-record.focus-node) "rebuild should keep focus synchronized to the new outline focus node")
    (view:drop)
    (assert (= (length selector.selectables) 0) "drop should remove outline compact point selectables")
    (assert (= (ctx.focus.manager:get-focused-node) nil) "drop should clear focused outline focus node")
    (graph-map:drop)
    (graph:drop)
    (selector:drop))

(fn outline-compact-point-click-syncs-selector-and-focus-manager []
    (with-screen-ray outline-compact-point-click-syncs-selector-and-focus-manager-body))

(fn outline-focus-clears-when-external-control-focused-body []
    (local {:graph graph :graph-map graph-map} (make-map))
    (add-edge! graph-map "test:root" "test:child")
    (graph-map:set-view-mode! "outline")
    (graph-map:set-outline-root-keys! ["test:root"])
    (local clickables (Clickables))
    (local ctx (make-render-ctx-with-focus))
    (set ctx.clickables clickables)
    (local view (GraphView {:graph-map graph-map :ctx ctx}))
    (local child-focus-ring (outline-layer-point ctx 2 1))
    (local external-focus-node (ctx.focus:create-node {:name "external-control"}))
    (local child-record (view-record-for-key view "test:child"))
    (click-record-point clickables child-record 1 100)
    (assert (= graph-map.focused_node_key "test:child") "compact point click should set outline graph focus")
    (assert (> child-focus-ring.size 0) "focused outline compact point should show focus ring")
    (external-focus-node:request-focus {:reason :test})
    (assert (= graph-map.focused_node_key nil) "external focus should clear stale outline graph focus")
    (assert (= child-focus-ring.size 0) "external focus should hide stale outline focus ring")
    (graph-map:set-outline-root-keys! ["test:child"])
    (assert (= (ctx.focus.manager:get-focused-node) external-focus-node)
            "outline rebuild should not steal focus back from external controls")
    (assert (= graph-map.focused_node_key nil)
            "outline rebuild should keep graph focus clear while external control is focused")
    (view:drop)
    (external-focus-node:drop)
    (graph-map:drop)
    (graph:drop))

(fn outline-focus-clears-when-external-control-focused []
    (with-screen-ray outline-focus-clears-when-external-control-focused-body))

(fn outline-compact-point-action-body []
    (local original-menu-manager app.menu-manager)
    (local {:graph graph :graph-map graph-map} (make-map))
    (add-edge! graph-map "test:root" "test:child")
    (graph-map:set-view-mode! "outline")
    (graph-map:set-outline-root-keys! ["test:root"])
    (graph-map:set-selected-node-keys ["test:root"])
    (local clickables (Clickables))
    (assert clickables "outline row action test requires clickables")
    (var opened-menu nil)
    (var opened-node-key nil)
    (set app.menu-manager {:open (fn [_self opts] (set opened-menu opts))})
    (local view (GraphView {:graph-map graph-map :ctx (make-real-render-ctx clickables)}))
    (set view.node-views.open
          (fn [_self node _opts]
              (set opened-node-key node.key)))
    (local child-record (view-record-for-key view "test:child"))
    (click-record-point clickables child-record 3 200)
    (assert opened-menu "compact point right-click should open action menu through clickables")
    (assert (= graph-map.focused_node_key "test:child") "compact point right-click should focus hit-tested child node")
    (assert (= (table.concat graph-map.selected_node_keys ",") "test:root") "compact point right-click should preserve selection")
    (click-record-point clickables child-record 1 300)
    (click-record-point clickables child-record 1 500)
    (assert (= opened-node-key nil)
            "compact point double-click should not open full node view")
    (assert child-record.expanded?
            "compact point double-click should expand compact presentation")
    (assert child-record.point._card-size
            "compact point double-click should replace point with expanded card presentation")
    (assert (= (table.concat graph-map.selected_node_keys ",") "test:root") "compact point double-click activation should preserve selection")
    (view:drop)
    (graph-map:drop)
    (graph:drop)
    (set app.menu-manager original-menu-manager))

(fn outline-focused-compact-point-activation-body []
    (local {:graph graph :graph-map graph-map} (make-map))
    (add-edge! graph-map "test:root" "test:child")
    (graph-map:set-view-mode! "outline")
    (graph-map:set-outline-root-keys! ["test:root"])
    (local clickables (Clickables))
    (local ctx (make-render-ctx-with-focus))
    (set ctx.clickables clickables)
    (local view (GraphView {:graph-map graph-map :ctx ctx}))
    (var opened-node-key nil)
    (set view.node-views.open
         (fn [_self node _opts]
             (set opened-node-key node.key)))
    (local child-record (view-record-for-key view "test:child"))
    (child-record.focus-node:request-focus {:reason :test})
    (assert (= (ctx.focus.manager:activate-focused {}) true)
            "focus activation should activate focused outline compact point")
    (assert (= opened-node-key nil)
            "focus activation should not open full node view")
    (assert child-record.expanded?
            "focus activation should expand compact presentation")
    (assert child-record.point._card-size
            "focus activation should replace point with expanded card presentation")
    (assert (= (ctx.focus.manager:activate-focused {}) true)
            "focus activation on expanded outline card should be idempotent")
    (assert (= opened-node-key nil)
            "second focus activation should not open full node view")
    (assert child-record.expanded?
            "second focus activation should leave outline compact point expanded")
    (assert child-record.point._card-size
            "second focus activation should keep expanded card presentation")
    (view:drop)
    (graph-map:drop)
    (graph:drop))

(fn outline-focused-compact-point-activation-uses-graph-expansion []
    (with-screen-ray outline-focused-compact-point-activation-body))

(fn outline-compact-point-right-click-and-activation-use-real-hit-testing []
    (with-screen-ray outline-compact-point-action-body))

(fn outline-compact-point-registrations-body []
    (local {:graph graph :graph-map graph-map} (make-map))
    (add-edge! graph-map "test:root" "test:child")
    (graph-map:set-view-mode! "outline")
    (graph-map:set-outline-root-keys! ["test:root"])
    (local clickables (Clickables))
    (assert clickables "outline row registration test requires clickables")
    (local view (GraphView {:graph-map graph-map :ctx (make-real-render-ctx clickables)}))
    (local root-record (view-record-for-key view "test:root"))
    (local child-record (view-record-for-key view "test:child"))
    (assert (= (length clickables.left-click-objects) 2) "outline should register one left-click target per visible row")
    (assert (= (length clickables.right-click-objects) 2) "outline should register one right-click target per visible row")
    (assert (= (length clickables.double-click-objects) 2) "outline should register one double-click target per visible row")
    (assert (= (. clickables.left-click-objects 1) root-record.point) "outline root left-click target should be compact point")
    (assert (= (. clickables.left-click-objects 2) child-record.point) "outline child left-click target should be compact point")
    (local stale-root-point root-record.point)
    (local stale-child-point child-record.point)
    (graph-map:set-outline-root-keys! ["test:child"])
    (assert (= (length clickables.left-click-objects) 1) "rebuild should unregister stale left-click row targets")
    (assert (= (length clickables.right-click-objects) 1) "rebuild should unregister stale right-click row targets")
    (assert (= (length clickables.double-click-objects) 1) "rebuild should unregister stale double-click row targets")
    (assert (not (= (. clickables.left-click-objects 1) stale-root-point)) "rebuild should remove stale root compact point clickable")
    (assert (not (= (. clickables.left-click-objects 1) stale-child-point)) "rebuild should replace stale child compact point clickable")
    (view:drop)
    (assert (= (length clickables.left-click-objects) 0) "drop should unregister compact point left-click targets")
    (assert (= (length clickables.right-click-objects) 0) "drop should unregister compact point right-click targets")
    (assert (= (length clickables.double-click-objects) 0) "drop should unregister compact point double-click targets")
    (graph-map:drop)
    (graph:drop))

(fn outline-compact-point-registrations-drop-on-rebuild-and-drop []
    (with-screen-ray outline-compact-point-registrations-body))

(fn outline-view-creates-tree-node-visual-artifacts-for-projected-rows []
    (local {:graph graph :graph-map graph-map} (make-map))
    (add-edge! graph-map "test:root" "test:child")
    (graph-map:set-view-mode! "outline")
    (graph-map:set-outline-root-keys! ["test:root"])
    (local ctx (make-render-ctx))
    (local view (GraphView {:graph-map graph-map :ctx ctx}))
    (assert (>= (count-render-events ctx :text-upsert) 2)
            "outline rows should create visible node labels")
    (assert (>= (count-render-events ctx :point-create) 6)
            "outline rows should create layered graph node circle artifacts, not plain text-only rows")
    (local base-points [])
    (each [_ event (ipairs (render-events-of-kind ctx :point-create))]
        (when (> event.size 0)
            (table.insert base-points event)))
    (assert (= (length base-points) 2)
            "outline should create one visible base node circle per projected row")
    (assert (= (. base-points 1 :position :x) 12)
            "root node circle should start at deterministic tree x position")
    (assert (= (. base-points 2 :position :x) 30)
            "child node circle should indent by depth in tree layout")
    (assert (= (. base-points 1 :position :y) -12)
            "root node circle should use deterministic first-row y position")
    (assert (= (. base-points 2 :position :y) -36)
            "child node circle should use deterministic traversal-row y position")
    (assert (= (count-render-events ctx :quad-upsert) 0)
            "non-empty outline rows should not render list-row rectangles")
    (view:drop)
    (assert (>= (count-render-events ctx :text-remove) 2)
            "dropping outline rows should remove node label artifacts")
    (each [_ point (ipairs ctx.points.created)]
        (assert point.dropped? "dropping outline rows should remove node circle artifacts"))
    (graph-map:drop)
    (graph:drop))

(fn outline-labels-align-right-of-node-points []
    (local {:graph graph :graph-map graph-map} (make-map))
    (add-edge! graph-map "test:root" "test:child")
    (graph-map:set-view-mode! "outline")
    (graph-map:set-outline-root-keys! ["test:root"])
    (local ctx (make-render-ctx))
    (local view (GraphView {:graph-map graph-map :ctx ctx}))
    (local root-point (outline-layer-point ctx 1 3))
    (local root-label (assert (. (. view.row-handles 1) :visuals 2)
                              "root row should keep its label visual"))
    (assert (= root-label.style.scale 3.0)
            "outline node labels should use graph-view label default scale")
    (assert (approx root-label.layout.position.x (+ root-point.position.x (/ root-point.size 2.0) 1.0))
            (.. "outline label x should sit just right of the node point, got "
                (tostring root-label.layout.position.x)))
    (assert (approx root-label.layout.position.y (- root-point.position.y (/ root-label.layout.measure.y 2.0)))
            (.. "outline label y should vertically center measured text on the node point, got "
                (tostring root-label.layout.position.y)))
    (view:drop)
    (graph-map:drop)
    (graph:drop))

(fn outline-view-creates-empty-state-guidance-when-no-roots []
    (local {:graph graph :graph-map graph-map} (make-map))
    (graph-map:load-by-key "test:orphan")
    (graph-map:set-view-mode! "outline")
    (local ctx (make-render-ctx))
    (local view (GraphView {:graph-map graph-map :ctx ctx}))
    (assert (= (length view.rows) 0) "outline with no roots should project no rows")
    (assert view.empty-state-handle "outline with no roots should own an empty-state visual handle")
    (assert (string.find view.empty-state-handle.message "Set Outline Root")
            "empty state should guide users to set an outline root")
    (assert (>= (count-render-events ctx :text-upsert) 1)
            "empty state should create visible guidance text")
    (view:drop)
    (assert (>= (count-render-events ctx :text-remove) 1)
            "dropping empty state should remove guidance text")
    (graph-map:drop)
    (graph:drop))

(fn command-toggle-outline-flips-view-mode []
    (local {:graph graph :graph-map graph-map} (make-map))
    (CommandHelpers.reset!)
    (CommandHelpers.set-graph-map! graph-map)
    (CommandHelpers.set-graph-view! {:graph-map graph-map})
    (local provider (CommandHelpers.provider))
    (local binding (assert (CommandHelpers.find-binding-by-command provider.bindings "graph.view.toggle-outline") "outline toggle binding missing"))
    (assert (= (. binding.keys 1) "g") "outline toggle binding should live under graph leader")
    (assert (= (table.concat binding.keys " ") "g v o") "outline toggle binding should use SPC g v o")
    (local command (assert (. provider.commands "graph.view.toggle-outline") "outline toggle command missing"))
    (assert (= (command:run {}) true) "toggle command should run")
    (assert (= graph-map.view_mode "outline") "toggle should enter outline mode")
    (assert (= (command:run {}) true) "toggle command should run twice")
    (assert (= graph-map.view_mode "spatial") "toggle should return to spatial mode")
    (CommandHelpers.reset!)
    (graph-map:drop)
    (graph:drop))

(fn command-set-outline-root-prefers-focused-node []
    (local {:graph graph :graph-map graph-map} (make-map))
    (graph-map:load-by-key "test:focused")
    (graph-map:load-by-key "test:selected")
    (set graph-map.focused_node_key "test:focused")
    (graph-map:set-selected-node-keys ["test:selected"])
    (CommandHelpers.reset!)
    (CommandHelpers.set-graph-map! graph-map)
    (CommandHelpers.set-graph-view! {:graph-map graph-map
                                     :focused-node (fn [_self] (graph-map:lookup graph-map.focused_node_key))})
    (local provider (CommandHelpers.provider))
    (local binding (assert (CommandHelpers.find-binding-by-command provider.bindings "graph.outline.set-root-from-current") "outline root binding missing"))
    (assert (= (table.concat binding.keys " ") "g o r") "outline root binding should use SPC g o r")
    (local command (assert (. provider.commands "graph.outline.set-root-from-current") "set outline root command missing"))
    (assert (= (command:run {}) true) "set root command should run with focus")
    (assert (= (table.concat graph-map.outline_root_keys ",") "test:focused")
            "set root should prefer focused node over selection")
    (CommandHelpers.reset!)
    (graph-map:drop)
    (graph:drop))

(fn command-set-outline-root-uses-single-selection []
    (local {:graph graph :graph-map graph-map} (make-map))
    (graph-map:load-by-key "test:selected")
    (graph-map:set-selected-node-keys ["test:selected"])
    (CommandHelpers.reset!)
    (CommandHelpers.set-graph-map! graph-map)
    (CommandHelpers.set-graph-view! {:graph-map graph-map
                                     :focused-node (fn [_self] nil)})
    (local provider (CommandHelpers.provider))
    (local command (assert (. provider.commands "graph.outline.set-root-from-current") "set outline root command missing"))
    (assert (= (command:run {}) true) "set root command should run with one selected key")
    (assert (= (table.concat graph-map.outline_root_keys ",") "test:selected")
            "set root should use exactly one selected node when focus is absent")
    (CommandHelpers.reset!)
    (graph-map:drop)
    (graph:drop))

(table.insert tests {:name "outline builds reachable outgoing depth-first rows" :fn outline-builds-reachable-outgoing-depth-first-rows})
(table.insert tests {:name "outline skips incoming-only edges" :fn outline-skips-incoming-only-edges})
(table.insert tests {:name "outline handles cycles and shared nodes by first occurrence" :fn outline-handles-cycles-and-shared-nodes-by-first-occurrence})
(table.insert tests {:name "graph map persists outline mode and roots" :fn graph-map-persists-outline-mode-and-roots})
(table.insert tests {:name "graph map prunes removed outline roots" :fn graph-map-prunes-removed-outline-roots})
(table.insert tests {:name "map manager persists outline state per map" :fn map-manager-persists-outline-state-per-map})
(table.insert tests {:name "outline view exposes visible row selection" :fn outline-view-exposes-visible-row-selection})
(table.insert tests {:name "outline reveal refreshes node selection rings" :fn outline-reveal-refreshes-node-selection-rings})
(table.insert tests {:name "outline view rejects unreachable reveal" :fn outline-view-rejects-unreachable-reveal})
(table.insert tests {:name "outline compact point clicks use real hit testing" :fn outline-compact-point-clicks-use-real-hit-testing})
(table.insert tests {:name "outline row whitespace and label misses use real hit testing" :fn outline-row-whitespace-and-label-misses-use-real-hit-testing})
(table.insert tests {:name "outline compact point click syncs selector and focus manager" :fn outline-compact-point-click-syncs-selector-and-focus-manager})
(table.insert tests {:name "outline focus clears when external control focused" :fn outline-focus-clears-when-external-control-focused})
(table.insert tests {:name "outline compact point right-click and activation use real hit testing" :fn outline-compact-point-right-click-and-activation-use-real-hit-testing})
(table.insert tests {:name "outline focused compact point activation uses graph expansion" :fn outline-focused-compact-point-activation-uses-graph-expansion})
(table.insert tests {:name "outline compact point registrations drop on rebuild and drop" :fn outline-compact-point-registrations-drop-on-rebuild-and-drop})
(table.insert tests {:name "outline view creates tree node visual artifacts for projected rows" :fn outline-view-creates-tree-node-visual-artifacts-for-projected-rows})
(table.insert tests {:name "outline labels align right of node points" :fn outline-labels-align-right-of-node-points})
(table.insert tests {:name "outline view creates empty state guidance when no roots" :fn outline-view-creates-empty-state-guidance-when-no-roots})
(table.insert tests {:name "command toggle outline flips view mode" :fn command-toggle-outline-flips-view-mode})
(table.insert tests {:name "command set outline root prefers focused node" :fn command-set-outline-root-prefers-focused-node})
(table.insert tests {:name "command set outline root uses single selection" :fn command-set-outline-root-uses-single-selection})

(fn main []
    ((. (require :logging) :set-level) "warn")
    ((. (require :tests/runner) :run-tests) {:name "graph-outline-view" :tests tests}))

{:name "graph-outline-view" :tests tests :main main}
