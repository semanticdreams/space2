(local glm (require :glm))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local GraphMapManager (require :graph/map-manager))
(local Edge (require :graph/edge))
(local GraphOutline (require :graph/outline))
(local GraphView (require :graph/view))
(local CommandHelpers (require :tests/graph-command-helpers))
(local Clickables (require :clickables))

(local tests [])

(fn approx [actual expected]
    (< (math.abs (- actual expected)) 0.0001))

(fn register-test-loader [graph]
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key
                              :label key})))
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

(fn point-intersect [_self _ray]
    (values false nil nil))

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
     :theme {:font (make-test-font)
             :text {:foreground (glm.vec4 0.8 0.8 0.8 1) :scale 1.0}}
     :render-events render-events
     :get-text-ssbo-batcher (fn [_self] text-batcher)
     :get-rectangle-quad-batcher (fn [_self] quad-batcher)})

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

(fn click-child-row [clickables button timestamp]
    (click-row clickables 40 -36 button timestamp))

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

(fn outline-row-clicks-body []
    (local {:graph graph :graph-map graph-map} (make-map))
    (add-edge! graph-map "test:root" "test:child")
    (graph-map:set-view-mode! "outline")
    (graph-map:set-outline-root-keys! ["test:root"])
    (local clickables (Clickables))
    (assert clickables "outline row click test requires clickables")
    (local view (GraphView {:graph-map graph-map :ctx (make-real-render-ctx clickables)}))
    (click-child-row clickables 1 100)
    (assert (= graph-map.focused_node_key "test:child") "row click should focus hit-tested child row")
    (assert (= (table.concat graph-map.selected_node_keys ",") "test:child") "row click should select hit-tested child row")
    (view:drop)
    (graph-map:drop)
    (graph:drop))

(fn outline-row-clicks-use-real-hit-testing []
    (with-screen-ray outline-row-clicks-body))

(fn outline-row-action-body []
    (local original-menu-manager app.menu-manager)
    (local {:graph graph :graph-map graph-map} (make-map))
    (add-edge! graph-map "test:root" "test:child")
    (graph-map:set-view-mode! "outline")
    (graph-map:set-outline-root-keys! ["test:root"])
    (local clickables (Clickables))
    (assert clickables "outline row action test requires clickables")
    (var opened-menu nil)
    (var opened-node-key nil)
    (set app.menu-manager {:open (fn [_self opts] (set opened-menu opts))})
    (local view (GraphView {:graph-map graph-map :ctx (make-real-render-ctx clickables)}))
    (set view.node-views.open
         (fn [_self node _opts]
             (set opened-node-key node.key)))
    (click-child-row clickables 3 200)
    (assert opened-menu "row right-click should open action menu through clickables")
    (assert (= graph-map.focused_node_key "test:child") "row right-click should focus hit-tested child row")
    (click-child-row clickables 1 300)
    (click-child-row clickables 1 500)
    (assert (= opened-node-key "test:child") "row double-click should activate/open hit-tested child row")
    (view:drop)
    (graph-map:drop)
    (graph:drop)
    (set app.menu-manager original-menu-manager))

(fn outline-row-right-click-and-activation-use-real-hit-testing []
    (with-screen-ray outline-row-action-body))

(fn outline-row-registrations-body []
    (local {:graph graph :graph-map graph-map} (make-map))
    (add-edge! graph-map "test:root" "test:child")
    (graph-map:set-view-mode! "outline")
    (graph-map:set-outline-root-keys! ["test:root"])
    (local clickables (Clickables))
    (assert clickables "outline row registration test requires clickables")
    (local view (GraphView {:graph-map graph-map :ctx (make-real-render-ctx clickables)}))
    (assert (= (length clickables.left-click-objects) 2) "outline should register one left-click target per visible row")
    (assert (= (length clickables.right-click-objects) 2) "outline should register one right-click target per visible row")
    (assert (= (length clickables.double-click-objects) 2) "outline should register one double-click target per visible row")
    (graph-map:set-outline-root-keys! ["test:child"])
    (assert (= (length clickables.left-click-objects) 1) "rebuild should unregister stale left-click row targets")
    (assert (= (length clickables.right-click-objects) 1) "rebuild should unregister stale right-click row targets")
    (assert (= (length clickables.double-click-objects) 1) "rebuild should unregister stale double-click row targets")
    (view:drop)
    (assert (= (length clickables.left-click-objects) 0) "drop should unregister row left-click targets")
    (assert (= (length clickables.right-click-objects) 0) "drop should unregister row right-click targets")
    (assert (= (length clickables.double-click-objects) 0) "drop should unregister row double-click targets")
    (graph-map:drop)
    (graph:drop))

(fn outline-row-registrations-drop-on-rebuild-and-drop []
    (with-screen-ray outline-row-registrations-body))

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
(table.insert tests {:name "outline row clicks use real hit testing" :fn outline-row-clicks-use-real-hit-testing})
(table.insert tests {:name "outline row right-click and activation use real hit testing" :fn outline-row-right-click-and-activation-use-real-hit-testing})
(table.insert tests {:name "outline row registrations drop on rebuild and drop" :fn outline-row-registrations-drop-on-rebuild-and-drop})
(table.insert tests {:name "outline view creates tree node visual artifacts for projected rows" :fn outline-view-creates-tree-node-visual-artifacts-for-projected-rows})
(table.insert tests {:name "outline labels align right of node points" :fn outline-labels-align-right-of-node-points})
(table.insert tests {:name "outline view creates empty state guidance when no roots" :fn outline-view-creates-empty-state-guidance-when-no-roots})
(table.insert tests {:name "command toggle outline flips view mode" :fn command-toggle-outline-flips-view-mode})
(table.insert tests {:name "command set outline root prefers focused node" :fn command-set-outline-root-prefers-focused-node})
(table.insert tests {:name "command set outline root uses single selection" :fn command-set-outline-root-uses-single-selection})

(fn main []
    ((. (require :tests/runner) :run-tests) {:name "graph-outline-view" :tests tests}))

{:name "graph-outline-view" :tests tests :main main}
