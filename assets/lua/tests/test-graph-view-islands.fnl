(local glm (require :glm))
(local fs (require :fs))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local GraphView (require :graph/view/init))
(local BuildContext (require :build-context))
(local {:FocusManager FocusManager} (require :focus))
(local {:Layout Layout :LayoutRoot LayoutRoot} (require :layout))

(local tests [])
(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "graph-view-islands"))

(fn assert-close [actual expected message]
    (assert (< (math.abs (- actual expected)) 1e-5)
            (or message (string.format "expected %s to equal %s" actual expected))))

(fn assert-vec3 [actual expected message]
    (assert actual (or message "expected vec3, got nil"))
    (assert-close actual.x expected.x (.. (or message "vec3") " x"))
    (assert-close actual.y expected.y (.. (or message "vec3") " y"))
    (assert-close actual.z expected.z (.. (or message "vec3") " z")))

(fn make-temp-dir []
    (set temp-counter (+ temp-counter 1))
    (fs.join-path temp-root (.. "case-" (os.time) "-" temp-counter)))

(fn make-icons-stub []
    (local glyph {:advance 1})
    (local font {:metadata {:metrics {:ascender 1 :descender -1}
                            :atlas {:width 1 :height 1}}
                 :glyph-map {65533 glyph 4242 glyph}})
    (local stub {:font font
                 :codepoints {:open_in_new 4242
                               :content_copy 4242
                               :open_in_full 4242
                               :close_fullscreen 4242
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

(fn make-ctx []
    (local focus-manager (FocusManager {:root-name "test-graph-view-islands"}))
    (local focus-scope (focus-manager:create-scope {:name "graph-view-islands"}))
    (local layout-root (LayoutRoot {:log-dirt? false}))
    (local ctx
        (BuildContext {:layout-root layout-root
                       :clickables (assert app.clickables "test requires app.clickables")
                       :hoverables (assert app.hoverables "test requires app.hoverables")
                       :theme {:graph {:selection-border-color (glm.vec4 1 0.6 0.2 1)
                                       :label-color (glm.vec4 1 1 1 1)
                                       :label-target-pixels 13.0
                                       :label-min-scale 4.0
                                       :edge-color (glm.vec4 0.6 0.6 0.6 1)}
                               :input {:focus-outline (glm.vec4 0.2 0.6 1 1)}}
                       :focus-manager focus-manager
                       :focus-scope focus-scope}))
    (set ctx.icons (make-icons-stub))
    ctx)

(fn island-preview-measurer [self]
    (set self.measure (glm.vec3 40 24 0)))

(fn island-preview-constrained-measurer [self _constraints]
    (set self.measure (glm.vec3 40 24 0)))

(fn island-preview-layouter [_self]
    nil)

(fn build-island-preview [_ctx]
    (local widget {})
    (local layout (Layout {:name "graph-view-island-preview"
                          :measurer island-preview-measurer
                          :constrained-measurer island-preview-constrained-measurer
                          :layouter island-preview-layouter}))
    (set widget.layout layout)
    (set widget.drop (fn [_self] (layout:drop)))
    widget)

(fn make-preview []
    (fn preview-factory [_node _opts]
        build-island-preview))

(fn register-test-loader [graph]
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key
                              :label key
                              :size 10
                              :color (glm.vec4 0.4 0.6 1 1)
                              :preview (make-preview)})))
    graph)

(fn make-movables-stub []
    (local entries [])
    (local by-node {})
    {:entries entries
     :by-node by-node
     :register (fn [_self _point entry]
                 (table.insert entries entry)
                 (set (. by-node entry.key) entry))
     :unregister (fn [_self node]
                   (set (. by-node node) nil))})

(fn option-value [options key default]
    (if (not (= (. options key) nil))
        (. options key)
        default))

(fn island-record [opts]
    (local options (if opts opts {}))
    {:id (option-value options :id "island-1")
     :kind (option-value options :kind "ordered-list")
     :members (option-value options :members ["test:a" "test:b"])
     :state (option-value options :state {:position (glm.vec3 100 200 0)
                                          :spacing 12})})

(fn check-applies-ordered-list-island-positions [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (assert view.island-host "GraphView should expose island-host")
    (assert-vec3 (view:get-position (map:lookup "test:a")) (glm.vec3 50 75 2)
                 "first member should use island origin")
    (assert-vec3 (view:get-position (map:lookup "test:b")) (glm.vec3 50 55 2)
                 "second member should be vertically offset")
    (assert (. view.pinned (map:lookup "test:a")) "first member should be pinned by island")
    (assert (. view.pinned (map:lookup "test:b")) "second member should be pinned by island"))

(fn check-updates-island-layout-when-island-changes [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (map:update-island "island-1" {:state {:position (glm.vec3 30 60 1)
                                           :spacing 5}})
    (assert-vec3 (view:get-position (map:lookup "test:a")) (glm.vec3 30 60 1)
                 "updated origin should move first member")
    (assert-vec3 (view:get-position (map:lookup "test:b")) (glm.vec3 30 55 1)
                 "updated spacing should move second member"))

(fn label-position-for-node [view node]
    (local span (. view.labels.labels node))
    (assert span "expected label span for node")
    (assert span.layout "expected label span layout")
    span.layout.position)

(fn check-refreshes-labels-after-island-update [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local node-a (map:lookup "test:a"))
    (view:update 0.016)
    (local before-label (label-position-for-node view node-a))
    (local before-node (view:get-position node-a))
    (map:update-island "island-1" {:state {:position (glm.vec3 80 90 0)
                                           :spacing 10}})
    (local after-label (label-position-for-node view node-a))
    (local after-node (view:get-position node-a))
    (local node-delta (- after-node before-node))
    (local expected-label (+ before-label node-delta))
    (assert-vec3 after-label expected-label
                 "label should move with node after island update reconciliation"))

(fn no-op-fixture [_fixture]
    nil)

(fn check-unpins-members-after-island-removal [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local node-a (map:lookup "test:a"))
    (local node-b (map:lookup "test:b"))
    (assert (. view.pinned node-a) "fixture should start with first member pinned")
    (assert (. view.pinned node-b) "fixture should start with second member pinned")
    (map:remove-island "island-1")
    (assert (not (. view.pinned node-a)) "first member should unpin after island removal")
    (assert (not (. view.pinned node-b)) "second member should unpin after island removal"))

(fn check-preserves-expanded-member-pin-after-island-removal [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local node-a (map:lookup "test:a"))
    (local point-a (. view.points node-a))
    (assert point-a "fixture should have first member point")
    (assert point-a.on-double-click "fixture point should expose double-click expansion")
    (point-a:on-double-click {})
    (assert (. (. view.points node-a) :_card-size) "member should expand into a card")
    (assert (. view.pinned node-a) "expanded member should be pinned before island removal")
    (map:remove-island "island-1")
    (assert (. view.pinned node-a) "expanded member should remain pinned after island removal"))

(fn check-removes-island-member-node-without-pin-cleanup-error [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local node-a (map:lookup "test:a"))
    (assert (. view.pinned node-a) "fixture should start with removed member pinned")
    (local (ok err) (pcall (fn [] (map:remove-nodes [node-a]))))
    (assert ok (.. "removing island member should not fail: " (tostring err)))
    (assert (not (map:lookup "test:a")) "removed node should leave graph map")
    (assert (not (. view.pinned node-a)) "removed member should not remain pinned in view"))

(fn check-snaps-island-member-back-after-drag-end [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local node-a (map:lookup "test:a"))
    (local entry (. movables.by-node node-a))
    (assert entry "movable entry should be registered for island member")
    (entry.target:set-position (glm.vec3 400 500 0))
    (assert-vec3 (view:get-position node-a) (glm.vec3 400 500 0)
                 "drag should move member before drag end")
    (entry.on-drag-end entry)
    (assert-vec3 (view:get-position node-a) (glm.vec3 5 6 0)
                 "drag end should reconcile island and snap member back"))

(fn with-fixture [opts f]
    (local options (or opts {}))
    (local dir (make-temp-dir))
    (when (fs.exists dir)
        (fs.remove-all dir))
    (fs.create-dirs dir)
    (local graph (register-test-loader (Graph {:with-start false})))
    (local map (GraphMap.GraphMap {:graph graph :id (or options.map-id "islands")}))
    (each [_ key (ipairs (or options.keys ["test:a" "test:b" "test:c"]))]
        (map:load-by-key key))
    (when options.island
        (map:create-island options.island))
    (local ctx (make-ctx))
    (local movables (make-movables-stub))
    (var view nil)
    (local (ok result)
        (pcall
            (fn []
                (set view (GraphView {:graph-map map
                                      :ctx ctx
                                      :data-dir dir
                                      :movables movables}))
                (f {:graph graph :map map :view view :movables movables :dir dir}))))
    (when view
        (view:drop))
    (map:drop)
    (graph:drop)
    (fs.remove-all dir)
    (if ok
        result
        (error result)))

(fn graph-view-applies-ordered-list-island-positions []
    (with-fixture {:island (island-record {:state {:position (glm.vec3 50 75 2)
                                                   :spacing 20}})}
        check-applies-ordered-list-island-positions))

(fn graph-view-updates-island-layout-when-island-changes []
    (with-fixture {:island (island-record {:state {:position (glm.vec3 10 20 0)
                                                   :spacing 10}})}
        check-updates-island-layout-when-island-changes))

(fn graph-view-refreshes-labels-after-island-update []
    (with-fixture {:island (island-record {:state {:position (glm.vec3 10 20 0)
                                                   :spacing 10}})}
        check-refreshes-labels-after-island-update))

(fn graph-view-fails-visibly-for-missing-island-presenter []
    (local (ok err)
        (pcall
            (fn []
                (with-fixture {:island (island-record {:kind "missing-kind"
                                                       :members ["test:a"]})}
                    no-op-fixture))))
    (assert (not ok) "GraphView should fail when no island presenter exists")
    (assert (string.find (tostring err) "missing graph island presenter kind: missing-kind" 1 true)
            "missing presenter error should include island kind"))

(fn graph-view-unpins-members-after-island-removal []
    (with-fixture {:island (island-record {})}
        check-unpins-members-after-island-removal))

(fn graph-view-preserves-expanded-member-pin-after-island-removal []
    (with-fixture {:island (island-record {})}
        check-preserves-expanded-member-pin-after-island-removal))

(fn graph-view-removes-island-member-node-without-pin-cleanup-error []
    (with-fixture {:island (island-record {})}
        check-removes-island-member-node-without-pin-cleanup-error))

(fn graph-view-snaps-island-member-back-after-drag-end []
    (with-fixture {:island (island-record {:state {:position (glm.vec3 5 6 0)
                                                   :spacing 7}})}
        check-snaps-island-member-back-after-drag-end))

(table.insert tests {:name "GraphView applies ordered-list island positions"
                     :fn graph-view-applies-ordered-list-island-positions})
(table.insert tests {:name "GraphView updates island layout when island changes"
                     :fn graph-view-updates-island-layout-when-island-changes})
(table.insert tests {:name "GraphView refreshes labels after island update"
                     :fn graph-view-refreshes-labels-after-island-update})
(table.insert tests {:name "GraphView fails visibly for missing island presenter"
                     :fn graph-view-fails-visibly-for-missing-island-presenter})
(table.insert tests {:name "GraphView unpins members after island removal"
                     :fn graph-view-unpins-members-after-island-removal})
(table.insert tests {:name "GraphView preserves expanded member pin after island removal"
                     :fn graph-view-preserves-expanded-member-pin-after-island-removal})
(table.insert tests {:name "GraphView removes island member node without pin cleanup error"
                     :fn graph-view-removes-island-member-node-without-pin-cleanup-error})
(table.insert tests {:name "GraphView snaps island member back after drag end"
                     :fn graph-view-snaps-island-member-back-after-drag-end})

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "graph-view-islands" :tests tests})))

{:name "graph-view-islands"
 :tests tests
 :main main}
