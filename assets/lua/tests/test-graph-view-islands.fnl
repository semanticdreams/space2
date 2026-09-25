(local glm (require :glm))
(local fs (require :fs))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local GraphView (require :graph/view/init))
(local GraphViewLayout (require :graph/view/layout))
(local BuildContext (require :build-context))
(local JsonUtils (require :json-utils))
(local StringEntityStore (require :entities/string))
(local ListEntityStore (require :entities/list))
(local IdentityStore (require :entities/identity))
(local {:register-loader register-string-loader} (require :graph/nodes/string-entity))
(local {:register-loader register-list-loader} (require :graph/nodes/list-entity))
(local {:FocusManager FocusManager} (require :focus))
(local {:Layout Layout :LayoutRoot LayoutRoot} (require :layout))
(local OrderedListPresenter (require :graph/view/island-presenters/ordered-list))

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

(fn copy-vec3 [position]
    (glm.vec3 position.x position.y position.z))

(fn force-layout-stub-add-node [self position]
    (table.insert self.positions (copy-vec3 position))
    (- (length self.positions) 1))

(fn force-layout-stub-add-edge [self source target _bidirectional?]
    (table.insert self.edges {:source source :target target}))

(fn force-layout-stub-pin-node [self idx pinned?]
    (set (. self.pins idx) pinned?))

(fn force-layout-stub-set-position [self idx position]
    (set (. self.positions (+ idx 1)) (copy-vec3 position)))

(fn force-layout-stub-get-positions [self]
    (if self.next-positions
        self.next-positions
        self.positions))

(fn force-layout-stub-update [_self _iterations]
    nil)

(fn force-layout-stub-start [self]
    (set self.starts (+ self.starts 1)))

(fn force-layout-stub-clear [self]
    (set self.clears (+ self.clears 1))
    (set self.positions [])
    (set self.next-positions nil)
    (set self.edges [])
    (set self.pins {}))

(fn make-force-layout-stub []
    {:positions []
     :next-positions nil
     :edges []
     :pins {}
     :starts 0
     :clears 0
     :add-node force-layout-stub-add-node
     :add-edge force-layout-stub-add-edge
     :pin-node force-layout-stub-pin-node
     :set-position force-layout-stub-set-position
     :get-positions force-layout-stub-get-positions
     :update force-layout-stub-update
     :start force-layout-stub-start
     :clear force-layout-stub-clear})

(fn line-stub-update [_self _start _end]
    nil)

(fn line-stub-drop [_self]
    nil)

(fn make-line-stub [_ctx _opts]
    {:update line-stub-update
     :drop line-stub-drop})

(fn layout-stub-set-point-position [node position _context]
    (local point node._test-point)
    (set point.position position))

(fn layout-stub-get-position [_self node]
    node._test-point.position)

(fn layout-stub-body-position-for-force-position [force-position]
    (+ force-position (glm.vec3 0 12 0)))

(fn layout-stub-member-placements [body-position]
    (local placements {})
    (set (. placements "test:a") body-position)
    (set (. placements "test:b") (- body-position (glm.vec3 0 24 0)))
    placements)

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
    (assert (not (. view.pinned (map:lookup "test:a")))
            "first member should not be pinned by island by default")
    (assert (not (. view.pinned (map:lookup "test:b")))
            "second member should not be pinned by island by default"))

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

(fn check-island-removal-keeps-default-unpinned-members-unpinned [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local node-a (map:lookup "test:a"))
    (local node-b (map:lookup "test:b"))
    (assert (not (. view.pinned node-a)) "fixture should start with first member unpinned by default")
    (assert (not (. view.pinned node-b)) "fixture should start with second member unpinned by default")
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

(fn check-unpins-expanded-member-after-island-removal-and-collapse [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local node-a (map:lookup "test:a"))
    (local point-a (. view.points node-a))
    (assert point-a "fixture should have first member point")
    (point-a:on-double-click {})
    (local card (. view.points node-a))
    (assert card._card-size "member should expand into a card")
    (map:remove-island "island-1")
    (assert (. view.pinned node-a) "expanded member should stay pinned until collapse")
    (local collapse-button (. card.header-bar.children 4 :element))
    (assert collapse-button "expanded card should expose collapse button")
    (collapse-button:on-click {})
    (assert (not (. view.pinned node-a))
            "member should unpin after island removal and expanded-card collapse"))

(fn check-clears-expanded-pin-reason-before-later-island-removal [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local node-a (map:lookup "test:a"))
    (local point-a (. view.points node-a))
    (assert point-a "fixture should have first member point")
    (point-a:on-double-click {})
    (local card (. view.points node-a))
    (assert card._card-size "member should expand into a card")
    (map:create-island (island-record {:id "island-1" :members ["test:a"]}))
    (map:remove-island "island-1")
    (assert (. view.pinned node-a) "expanded member should remain pinned after first island removal")
    (local collapse-button (. card.header-bar.children 4 :element))
    (assert collapse-button "expanded card should expose collapse button")
    (collapse-button:on-click {})
    (assert (not (. view.pinned node-a))
            "collapsed member should release the expanded-card pin")
    (map:create-island (island-record {:id "island-2" :members ["test:a"]}))
    (assert (not (. view.pinned node-a))
            "second island should leave collapsed member unpinned by default")
    (map:remove-island "island-2")
    (assert (not (. view.pinned node-a))
            "second island removal should not restore stale expanded-card pin ownership"))

(fn check-removes-island-member-node-without-pin-cleanup-error [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local node-a (map:lookup "test:a"))
    (assert (not (. view.pinned node-a))
            "fixture should start with removed member unpinned by default")
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

(fn check-list-created-island-preserves-body-position-after-unrelated-drag-end [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local item-node (map:lookup fixture.item-key))
    (local unrelated-node (map:lookup fixture.unrelated-key))
    (local list-entry (. movables.by-node list-node))
    (local item-entry (. movables.by-node item-node))
    (local unrelated-entry (. movables.by-node unrelated-node))
    (assert list-entry "list node should be movable")
    (assert item-entry "list item should be movable")
    (assert unrelated-entry "unrelated node should be movable")
    (list-entry.target:set-position (glm.vec3 24 0 0))
    (assert-vec3 (view:get-position list-node) (glm.vec3 24 0 0)
                 "fixture should place list node at non-origin position")
    (assert (. map.presentation-points list-node.key) "graph map should expose GraphView presentation point")
    (list-node:expand-items-as-island)
    (local island (map:get-island "ordered-list:list"))
    (assert (= (. island.state.position 1) 48)
            (.. "island body x should initialize near list node, got " (. island.state.position 1)))
    (list-entry.target:set-position (glm.vec3 500 0 0))
    (assert-vec3 (view:get-position list-node) (glm.vec3 500 0 0)
                 "source list node should be allowed to move after island creation")
    (item-entry.target:set-position (glm.vec3 300 400 0))
    (unrelated-entry.on-drag-end unrelated-entry)
    (local reconciled-position (view:get-position item-node))
    (assert-vec3 reconciled-position (glm.vec3 48 0 0)
                 "unrelated drag-end reconciliation should use stored island body position")
    (local list-position (view:get-position list-node))
    (assert (not (and (= reconciled-position.x (+ list-position.x 24))
                      (= reconciled-position.y list-position.y)
                      (= reconciled-position.z list-position.z)))
            "first list island member should not be recomputed from current list node position"))

(fn check-ordered-list-aggregate-record-exposes-center-force-anchor []
    (local node-a {:key "test:a" :size 10})
    (local node-b {:key "test:b" :size 10})
    (local node-c {:key "test:c" :size 10})
    (local nodes {})
    (set (. nodes "test:a") node-a)
    (set (. nodes "test:b") node-b)
    (set (. nodes "test:c") node-c)
    (local positions {})
    (set (. positions "test:a") (glm.vec3 0 0 0))
    (set (. positions "test:b") (glm.vec3 0 -20 0))
    (set (. positions "test:c") (glm.vec3 0 -40 0))
    (local host
        {:node-for-key (fn [_self key] (. nodes key))
         :position-for-key (fn [_self key] (. positions key))})
    (local island
        {:id "island-1"
         :kind "ordered-list"
         :members ["test:a" "test:b" "test:c"]
         :state {:position (glm.vec3 100 200 0)
                 :spacing 20}})
    (local record (OrderedListPresenter.aggregate-layout-record island host))
    (assert-vec3 record.position (glm.vec3 100 200 0)
                 "aggregate record body position should remain ordered-list origin")
    (assert-vec3 record.force-position (glm.vec3 100 180 0)
                 "aggregate force position should be the ordered-list visual center")
    (assert (= (type record.body-position-for-force-position) :function)
            "aggregate record should expose center-to-origin conversion")
    (local moved-origin (record.body-position-for-force-position (glm.vec3 130 230 0)))
    (assert-vec3 moved-origin (glm.vec3 130 250 0)
                 "moved force center should convert back to ordered-list origin")
    (local placements (record.member-placements moved-origin))
    (assert-vec3 (. placements "test:a") (glm.vec3 130 250 0)
                 "first member placement should use converted origin")
    (assert-vec3 (. placements "test:b") (glm.vec3 130 230 0)
                 "second member placement should preserve spacing")
    (assert-vec3 (. placements "test:c") (glm.vec3 130 210 0)
                 "third member placement should preserve spacing"))

(fn check-list-created-island-moves-as-force-layout-unit [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local item-node (map:lookup fixture.item-key))
    (local second-node (map:lookup fixture.second-item-key))
    (local list-entry (. movables.by-node list-node))
    (assert list-entry "list node should be movable")
    (list-entry.target:set-position (glm.vec3 48 0 0))
    (list-node:expand-items-as-island)
    (assert (not (. view.pinned item-node))
            "first list island member should be unpinned by default")
    (assert (not (. view.pinned second-node))
            "second list island member should be unpinned by default")
    (local before-a (view:get-position item-node))
    (local before-b (view:get-position second-node))
    (for [_ 1 8]
        (view:update 0.016))
    (local after-a (view:get-position item-node))
    (local after-b (view:get-position second-node))
    (local delta-a (- after-a before-a))
    (local delta-b (- after-b before-b))
    (assert (> (glm.length delta-a) 0.001)
            "ordered-list island body should move during force layout")
    (assert-vec3 delta-b delta-a
                 "ordered-list island members should move by the same aggregate delta")
    (assert-close (- after-a.y after-b.y) 24
                  "ordered-list island spacing should be preserved after force layout"))

(fn check-force-moved-island-keeps-runtime-position-after-unrelated-drag-end [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local item-node (map:lookup fixture.item-key))
    (local second-node (map:lookup fixture.second-item-key))
    (local unrelated-node (map:lookup fixture.unrelated-key))
    (local list-entry (. movables.by-node list-node))
    (local unrelated-entry (. movables.by-node unrelated-node))
    (assert list-entry "list node should be movable")
    (assert unrelated-entry "unrelated node should be movable")
    (list-entry.target:set-position (glm.vec3 48 0 0))
    (list-node:expand-items-as-island)
    (local persisted-island (map:get-island "ordered-list:list"))
    (local persisted-body-x (. persisted-island.state.position 1))
    (for [_ 1 8]
        (view:update 0.016))
    (local runtime-a (view:get-position item-node))
    (local runtime-b (view:get-position second-node))
    (assert (> (math.abs (- runtime-a.x persisted-body-x)) 0.001)
            "force layout should move island body away from persisted body x")
    (unrelated-entry.on-drag-end unrelated-entry)
    (assert-vec3 (view:get-position item-node) runtime-a
                 "unrelated drag-end reconciliation should keep first member at runtime island body")
    (assert-vec3 (view:get-position second-node) runtime-b
                 "unrelated drag-end reconciliation should keep second member at runtime island body"))

(fn check-force-moved-island-flushes-body-origin-not-force-center [fixture]
    (local map fixture.map) (local view fixture.view) (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local item-node (map:lookup fixture.item-key))
    (local second-node (map:lookup fixture.second-item-key))
    (local list-entry (. movables.by-node list-node))
    (assert list-entry "list node should be movable")
    (list-entry.target:set-position (glm.vec3 48 0 0))
    (list-node:expand-items-as-island)
    (for [_ 1 8] (view:update 0.016))
    (local first-runtime (view:get-position item-node))
    (local second-runtime (view:get-position second-node))
    (view:capture-state)
    (local island (map:get-island "ordered-list:list"))
    (assert island "captured map should still contain ordered-list island")
    (assert-close (. island.state.position 1) first-runtime.x "flushed island state x should be first-member/body origin x")
    (assert-close (. island.state.position 2) first-runtime.y "flushed island state y should be first-member/body origin y")
    (assert-close (. island.state.position 3) first-runtime.z "flushed island state z should be first-member/body origin z")
    (local visual-center-y (* (+ first-runtime.y second-runtime.y) 0.5))
    (assert (> (math.abs (- (. island.state.position 2) visual-center-y)) 0.001)
            "flushed island state should not store ordered-list visual center"))

(fn check-membership-refresh-preserves-runtime-island-body [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local string-store fixture.string-store)
    (local list-store fixture.list-store)
    (local list-node (map:lookup fixture.list-key))
    (local item-node (map:lookup fixture.item-key))
    (local second-node (map:lookup fixture.second-item-key))
    (local list-entry (. movables.by-node list-node))
    (assert list-entry "list node should be movable")
    (list-entry.target:set-position (glm.vec3 48 0 0))
    (list-node:expand-items-as-island)
    (local persisted-island (map:get-island "ordered-list:list"))
    (local persisted-body-x (. persisted-island.state.position 1))
    (for [_ 1 8]
        (view:update 0.016))
    (local runtime-a (view:get-position item-node))
    (local runtime-b (view:get-position second-node))
    (assert (> (math.abs (- runtime-a.x persisted-body-x)) 0.001)
            "force layout should move island body away from persisted body before membership refresh")
    (local third (string-store:create-entity {:id "item-c" :value "C"}))
    (local third-key (.. "string-entity:" third.id))
    (list-store:add-item "list" third-key)
    (local third-node (map:lookup third-key))
    (assert third-node "membership refresh should load new island member node")
    (assert-vec3 (view:get-position item-node) runtime-a
                 "membership refresh should preserve first member runtime island body")
    (assert-vec3 (view:get-position second-node) runtime-b
                 "membership refresh should preserve second member runtime island body")
    (assert-vec3 (view:get-position third-node) (- runtime-b (glm.vec3 0 24 0))
                 "membership refresh should place new member relative to runtime island body"))

(fn check-expanded-member-stays-pinned-through-island-position-flush [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local item-node (map:lookup fixture.item-key))
    (local second-node (map:lookup fixture.second-item-key))
    (local list-entry (. movables.by-node list-node))
    (assert list-entry "list node should be movable")
    (list-entry.target:set-position (glm.vec3 48 0 0))
    (list-node:expand-items-as-island)
    (local item-point (. view.points item-node))
    (assert item-point "first list item should have a point")
    (item-point:on-double-click {})
    (assert (. view.pinned item-node) "expanded island member should be explicitly pinned")
    (local pinned-position (view:get-position item-node))
    (local second-before (view:get-position second-node))
    (for [_ 1 8]
        (view:update 0.016))
    (assert-vec3 (view:get-position item-node) pinned-position
                 "force layout refresh should not move expanded member while pinned")
    (assert (> (glm.length (- (view:get-position second-node) second-before)) 0.001)
            "unpinned island member should prove aggregate moved before flush")
    (view:capture-state)
    (assert-vec3 (view:get-position item-node) pinned-position
                 "island position flush reconciliation should not move expanded member while pinned"))

(fn check-collapsed-expanded-member-rejoins-aggregate-placement [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local item-node (map:lookup fixture.item-key))
    (local second-node (map:lookup fixture.second-item-key))
    (local list-entry (. movables.by-node list-node))
    (assert list-entry "list node should be movable")
    (list-entry.target:set-position (glm.vec3 48 0 0))
    (list-node:expand-items-as-island)
    (local aggregate-position (view:get-position item-node))
    (local second-position (view:get-position second-node))
    (local item-point (. view.points item-node))
    (assert item-point "first list item should have a point")
    (item-point:on-double-click {})
    (assert (. view.pinned item-node) "expanded island member should be explicitly pinned")
    (local item-entry (. movables.by-node item-node))
    (assert item-entry "expanded item should remain movable")
    (item-entry.target:set-position (glm.vec3 300 400 0))
    (assert-vec3 (view:get-position item-node) (glm.vec3 300 400 0)
                 "expanded pinned member should move away from aggregate before collapse")
    (local card (. view.points item-node))
    (local collapse-button (. card.header-bar.children 4 :element))
    (assert collapse-button "expanded card should expose collapse button")
    (collapse-button:on-click {})
    (assert (not (. view.pinned item-node))
            "collapsed member should release explicit expanded pin")
    (assert-vec3 (view:get-position item-node) aggregate-position
                 "collapsed member should immediately rejoin aggregate placement")
    (assert-vec3 (view:get-position second-node) second-position
                 "other member should preserve aggregate placement during collapse"))

(fn check-replacing-expanded-island-member-resyncs-aggregate-record [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local item-node (map:lookup fixture.item-key))
    (local unrelated-node (map:lookup fixture.unrelated-key))
    (local list-entry (. movables.by-node list-node))
    (local unrelated-entry (. movables.by-node unrelated-node))
    (assert list-entry "list node should be movable")
    (assert unrelated-entry "unrelated node should be movable")
    (list-entry.target:set-position (glm.vec3 48 0 0))
    (list-node:expand-items-as-island)
    (local item-point (. view.points item-node))
    (assert item-point "first list item should have a point")
    (item-point:on-double-click {})
    (assert (. view.pinned item-node) "expanded member should be pinned before replacement")
    (for [_ 1 4]
        (view:update 0.016))
    (local replacement (Graph.GraphNode {:key fixture.item-key
                                         :label "replacement item"
                                         :size 10
                                         :color (glm.vec4 0.8 0.4 0.2 1)
                                         :preview (make-preview)}))
    (map:add-node replacement)
    (assert (= (map:lookup fixture.item-key) replacement)
            "graph map should replace expanded island member")
    (assert (. view.pinned replacement) "replacement expanded member should inherit explicit pin")
    (assert (not (. view.pinned item-node))
            "old expanded member should no longer be pinned after replacement")
    (local replacement-card (. view.points replacement))
    (assert replacement-card._card-size "replacement should stay expanded before collapse")
    (local collapse-button (. replacement-card.header-bar.children 4 :element))
    (assert collapse-button "replacement expanded card should expose collapse button")
    (collapse-button:on-click {})
    (assert (not (. view.pinned replacement))
            "replacement member should be unpinned after collapse")
    (assert (= (length (view.graph-layout.layout:get-positions)) 3)
            "collapsed replacement island member should not be duplicated as an ordinary force node")
    (unrelated-entry.target:set-position (view:get-position (map:lookup fixture.second-item-key)))
    (local (updated? update-err) (pcall (fn []
                                          (for [_ 1 8]
                                              (view:update 0.016)))))
    (assert updated? (.. "layout update should resync expanded island replacement: " (tostring update-err)))
    (assert (not (. view.points item-node))
            "old expanded member point should be removed after replacement")
    (assert (. view.points replacement)
            "replacement expanded member point should stay mounted after update"))

(fn assert-unique-public-indices [view]
    (local seen {})
    (each [node idx (pairs view.indices)]
        (assert (= (type idx) :number)
                (.. "public registry index should be numeric for " (tostring (and node node.key))))
        (assert (not (. seen idx))
                (.. "public registry index collision at " idx))
        (set (. seen idx) node)))

(fn check-adding-node-after-island-sync-keeps-public-indices-unique [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local string-store fixture.string-store)
    (local list-node (map:lookup fixture.list-key))
    (local item-node (map:lookup fixture.item-key))
    (local second-node (map:lookup fixture.second-item-key))
    (local list-entry (. movables.by-node list-node))
    (assert list-entry "list node should be movable")
    (list-entry.target:set-position (glm.vec3 48 0 0))
    (list-node:expand-items-as-island)
    (assert-unique-public-indices view)
    (local extra (string-store:create-entity {:id "extra-after-island" :value "Extra"}))
    (local extra-key (.. "string-entity:" extra.id))
    (map:load-by-key extra-key)
    (local extra-node (map:lookup extra-key))
    (assert extra-node "extra node should be loaded after island sync")
    (assert-unique-public-indices view)
    (assert (= (. view.nodes-by-index (+ (. view.indices item-node) 1)) item-node)
            "first island member public index should still point at member")
    (assert (= (. view.nodes-by-index (+ (. view.indices second-node) 1)) second-node)
            "second island member public index should still point at member")
    (assert (= (. view.nodes-by-index (+ (. view.indices extra-node) 1)) extra-node)
            "new node public index should point at new node"))

(fn check-replacing-node-after-island-sync-refreshes-layout-participant [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local unrelated-node (map:lookup fixture.unrelated-key))
    (local list-entry (. movables.by-node list-node))
    (assert list-entry "list node should be movable")
    (list-entry.target:set-position (glm.vec3 48 0 0))
    (list-node:expand-items-as-island)
    (local replacement (Graph.GraphNode {:key fixture.unrelated-key
                                         :label "replacement"
                                         :size 10
                                         :color (glm.vec4 0.8 0.4 0.2 1)
                                         :preview (make-preview)}))
    (map:add-node replacement)
    (assert (= (map:lookup fixture.unrelated-key) replacement)
            "graph map should replace unrelated node")
    (local (updated? update-err) (pcall (fn [] (view:update 0.016))))
    (assert updated? (.. "layout update should use replacement node: " (tostring update-err)))
    (local (position-ok? position-err) (pcall (fn [] (view:get-position replacement))))
    (assert position-ok? (.. "replacement point should stay mounted: " (tostring position-err)))
    (assert (not (. view.points unrelated-node))
            "old node point should be removed after replacement"))

(fn check-capture-fails-visibly-when-moved-island-cannot-flush-position [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local list-entry (. movables.by-node list-node))
    (assert list-entry "list node should be movable")
    (list-entry.target:set-position (glm.vec3 48 0 0))
    (list-node:expand-items-as-island)
    (for [_ 1 8]
        (view:update 0.016))
    (local original-update-island map.update-island)
    (set map.update-island false)
    (local (ok err) (pcall (fn [] (view:capture-state))))
    (set map.update-island original-update-island)
    (assert (not ok) "capture-state should fail when moved island position cannot be flushed")
    (assert (string.find (tostring err) "GraphView island position flush requires GraphMap.update-island" 1 true)
            "failure should explain missing update-island during island position flush"))

(fn check-restored-old-format-list-island-uses-member-fallback-after-drag-end [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local item-node (map:lookup fixture.item-key))
    (local unrelated-node (map:lookup fixture.unrelated-key))
    (local unrelated-entry (. movables.by-node unrelated-node))
    (assert unrelated-entry "unrelated node should be movable")
    (assert-vec3 (view:get-position list-node) (glm.vec3 24 0 0)
                 "restored fixture should materialize list node at non-origin position")
    (assert (map:get-island "ordered-list:list")
            "restored fixture should have old-format ordered-list island")
    (unrelated-entry.on-drag-end unrelated-entry)
    (local list-position (view:get-position list-node))
    (local item-position (view:get-position item-node))
    (assert-vec3 item-position (glm.vec3 300 400 0)
                 "old-format island without body position should fall back to member position")
    (assert (not (and (= item-position.x list-position.x)
                      (= item-position.y list-position.y)
                      (= item-position.z list-position.z)))
            "restored old-format island first member should not overlap list node after unrelated drag-end"))

(fn check-alt-dragging-second-island-member-moves-whole-island-on-drag-end [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local item-node (map:lookup fixture.item-key))
    (local second-node (map:lookup fixture.second-item-key))
    (local list-entry (. movables.by-node list-node))
    (local second-entry (. movables.by-node second-node))
    (list-entry.target:set-position (glm.vec3 24 0 0))
    (list-node:expand-items-as-island)
    (second-entry.on-drag-start second-entry {} {:mod 256})
    (second-entry.target:set-position (glm.vec3 200 300 0))
    (assert-vec3 (view:get-position item-node) (glm.vec3 48 0 0)
                 "other members should not live-move during alt drag")
    (second-entry.on-drag-end second-entry {})
    (local island (map:get-island "ordered-list:list"))
    (assert (= (. island.state.position 1) 200) "island body x should update from second member drop")
    (assert (= (. island.state.position 2) 324) "island body y should keep second member at drop")
    (assert-vec3 (view:get-position item-node) (glm.vec3 200 324 0)
                 "first member should move to new island body")
    (assert-vec3 (view:get-position second-node) (glm.vec3 200 300 0)
                 "dragged second member should stay at dropped position after reconcile"))

(fn check-alt-drag-end-clears-state-before-visible-update-failure [fixture]
    (local map fixture.map)
    (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local second-node (map:lookup fixture.second-item-key))
    (local list-entry (. movables.by-node list-node))
    (local second-entry (. movables.by-node second-node))
    (list-entry.target:set-position (glm.vec3 24 0 0))
    (list-node:expand-items-as-island)
    (local original-update-island map.update-island)
    (set map.update-island false)
    (second-entry.on-drag-start second-entry {} {:mod 256})
    (second-entry.target:set-position (glm.vec3 200 300 0))
    (local (failed? err) (pcall (fn [] (second-entry.on-drag-end second-entry {}))))
    (assert (not failed?) "alt drag end should still fail visibly when update-island is missing")
    (assert (string.find (tostring err) "GraphView island member alt-drag requires GraphMap.update-island" 1 true)
            "failure should explain missing update-island")
    (local (cleared? second-err) (pcall (fn [] (second-entry.on-drag-end second-entry {}))))
    (set map.update-island original-update-island)
    (assert cleared? (.. "drag state should clear before visible update failure: " (tostring second-err))))

(fn check-graph-view-layout-converts-force-center-to-island-body-position []
    (local force-layout (make-force-layout-stub))
    (local normal {:key "test:normal" :size 10})
    (local member-a {:key "test:a" :size 10})
    (local member-b {:key "test:b" :size 10})
    (local center (glm.vec3 10 88 0))
    (local origin (glm.vec3 10 100 0))
    (local delta (glm.vec3 5 -7 0))
    (local nodes {})
    (set (. nodes normal) normal)
    (set (. nodes member-a) member-a)
    (set (. nodes member-b) member-b)
    (local points {})
    (set (. points normal) {:position center})
    (set (. points member-a) {:position origin})
    (set (. points member-b) {:position (glm.vec3 10 76 0)})
    (set normal._test-point (. points normal))
    (set member-a._test-point (. points member-a))
    (set member-b._test-point (. points member-b))
    (var captured-body-position nil)
    (local graph-layout
        (GraphViewLayout {:layout force-layout
                          :nodes nodes
                          :points points
                          :make-line make-line-stub
                          :set-point-position layout-stub-set-point-position
                          :get-position layout-stub-get-position
                          :get-position-raw layout-stub-get-position
                          :on-island-position (fn [_island-id position]
                                                (set captured-body-position position))}))
    (graph-layout:add-node normal center false)
    (local record
        {:id "island-1"
         :members [member-a member-b]
         :position origin
         :force-position center
         :body-position-for-force-position layout-stub-body-position-for-force-position
         :member-placements layout-stub-member-placements})
    (graph-layout:sync-island-layouts [record])
    (set force-layout.next-positions [(+ center delta) (+ center delta)])
    (graph-layout:update 0.016)
    (assert-vec3 (. (. points normal) :position) (+ center delta)
                 "normal node should move by injected force delta")
    (assert-vec3 captured-body-position (+ origin delta)
                 "island runtime callback should receive body/origin position")
    (assert-vec3 (. (. points member-a) :position) (+ origin delta)
                 "first island member should use converted body origin")
    (assert-vec3 (. (. points member-b) :position) (- (+ origin delta) (glm.vec3 0 24 0))
                 "second island member should preserve ordered-list spacing"))

(fn check-graph-view-layout-compares-force-anchor-against-snapshot []
    (local force-layout (make-force-layout-stub))
    (local member-a {:key "test:a" :size 10})
    (local member-b {:key "test:b" :size 10})
    (local center (glm.vec3 10 88 0))
    (local origin (glm.vec3 10 100 0))
    (local first-force-position (glm.vec3 15 81 0))
    (local second-force-position (glm.vec3 22 85 0))
    (local nodes {})
    (set (. nodes member-a) member-a)
    (set (. nodes member-b) member-b)
    (local points {})
    (set (. points member-a) {:position origin})
    (set (. points member-b) {:position (glm.vec3 10 76 0)})
    (set member-a._test-point (. points member-a))
    (set member-b._test-point (. points member-b))
    (local captured-body-positions [])
    (local graph-layout
        (GraphViewLayout {:layout force-layout
                          :nodes nodes
                          :points points
                          :make-line make-line-stub
                          :set-point-position layout-stub-set-point-position
                          :get-position layout-stub-get-position
                          :get-position-raw layout-stub-get-position
                          :on-island-position (fn [_island-id position]
                                                (table.insert captured-body-positions position))}))
    (local record
        {:id "island-1"
         :members [member-a member-b]
         :position origin
         :force-position center
         :body-position-for-force-position layout-stub-body-position-for-force-position
         :member-placements layout-stub-member-placements})
    (graph-layout:sync-island-layouts [record])
    (set force-layout.next-positions [first-force-position])
    (graph-layout:update 0.016)
    (set first-force-position.x second-force-position.x)
    (set first-force-position.y second-force-position.y)
    (set first-force-position.z second-force-position.z)
    (graph-layout:update 0.016)
    (assert (= (length captured-body-positions) 2)
            "island body callback should run for each in-place force anchor mutation")
    (assert-vec3 (. captured-body-positions 1) (layout-stub-body-position-for-force-position (glm.vec3 15 81 0))
                 "first in-place force anchor position should convert to body")
    (assert-vec3 (. captured-body-positions 2) (layout-stub-body-position-for-force-position second-force-position)
                 "second in-place force anchor position should convert to body")
    (assert-vec3 (. (. points member-a) :position) (layout-stub-body-position-for-force-position second-force-position)
                 "first island member should follow the second converted body origin")
    (assert-vec3 (. (. points member-b) :position)
                 (- (layout-stub-body-position-for-force-position second-force-position) (glm.vec3 0 24 0))
                 "second island member should follow the second converted body origin"))

(fn check-graph-view-layout-routes-member-edge-through-island-force-anchor []
    (local force-layout (make-force-layout-stub))
    (local member-a {:key "test:a" :size 10})
    (local member-b {:key "test:b" :size 10})
    (local outside {:key "test:outside" :size 10})
    (local island-force-position (glm.vec3 0 -12 0))
    (local outside-position (glm.vec3 100 0 0))
    (local nodes {})
    (set (. nodes member-a) member-a)
    (set (. nodes member-b) member-b)
    (set (. nodes outside) outside)
    (local points {})
    (set (. points member-a) {:position (glm.vec3 0 0 0)})
    (set (. points member-b) {:position (glm.vec3 0 -24 0)})
    (set (. points outside) {:position outside-position})
    (set member-a._test-point (. points member-a))
    (set member-b._test-point (. points member-b))
    (set outside._test-point (. points outside))
    (local graph-layout
        (GraphViewLayout {:layout force-layout
                          :nodes nodes
                          :points points
                          :make-line make-line-stub
                          :set-point-position layout-stub-set-point-position
                          :get-position layout-stub-get-position
                          :get-position-raw layout-stub-get-position}))
    (graph-layout:add-node outside outside-position false)
    (graph-layout:sync-island-layouts
        [{:id "island-1"
          :members [member-a member-b]
          :position (glm.vec3 0 0 0)
          :force-position island-force-position
          :body-position-for-force-position layout-stub-body-position-for-force-position
          :member-placements layout-stub-member-placements}])
    (graph-layout:add-edge {:source member-b :target outside})
    (local edge (. force-layout.edges 1))
    (assert edge "member edge should be added to force layout")
    (assert-vec3 (. force-layout.positions (+ edge.source 1)) island-force-position
                 "edge from unpinned island member should use aggregate force anchor")
    (assert-vec3 (. force-layout.positions (+ edge.target 1)) outside-position
                 "edge target should use outside node force body"))

(fn check-empty-island-sync-does-not-start-force-layout [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local node-a (Graph.GraphNode {:key "test:no-island-a"
                                    :label "No island A"
                                    :size 10
                                    :color (glm.vec4 0.4 0.6 1 1)
                                    :preview (make-preview)}))
    (local node-b (Graph.GraphNode {:key "test:no-island-b"
                                    :label "No island B"
                                    :size 10
                                    :color (glm.vec4 0.4 0.6 1 1)
                                    :preview (make-preview)}))
    (local node-c (Graph.GraphNode {:key "test:no-island-c"
                                    :label "No island C"
                                    :size 10
                                    :color (glm.vec4 0.4 0.6 1 1)
                                    :preview (make-preview)}))
    (map:add-node node-a {:position (glm.vec3 8 9 0)
                          :run-force? false})
    (map:add-node node-b {:position (glm.vec3 16 6 0)
                          :run-force? false})
    (map:add-node node-c {:position (glm.vec3 24 12 0)
                          :run-force? false})
    (map:add-edge (Graph.GraphEdge {:source node-a
                                    :target node-b})
                  {:run-force? false})
    (view:update 0.016)
    (assert-vec3 (view:get-position node-a) (glm.vec3 8 9 0)
                 "first node should stay fixed when no islands sync and force is disabled")
    (assert-vec3 (view:get-position node-b) (glm.vec3 16 6 0)
                 "second node should stay fixed when no islands sync and force is disabled")
    (assert-vec3 (view:get-position node-c) (glm.vec3 24 12 0)
                 "third node should stay fixed when no islands sync and force is disabled"))

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

(fn with-list-fixture [maybe-opts maybe-f]
    (local options (if (= (type maybe-opts) :function) {} (or maybe-opts {})))
    (local f (if (= (type maybe-opts) :function) maybe-opts maybe-f))
    (assert (= (type f) :function) "with-list-fixture requires callback")
    (local dir (make-temp-dir))
    (when (fs.exists dir)
        (fs.remove-all dir))
    (fs.create-dirs dir)
    (local string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path dir "string")}))
    (local list-store (ListEntityStore.ListEntityStore {:base-dir (fs.join-path dir "list")}))
    (local identity-store (IdentityStore.IdentityStore {:base-dir (fs.join-path dir "identity")}))
    (local graph (Graph {:with-start false :identity-store identity-store}))
    (register-string-loader graph {:store string-store})
    (register-list-loader graph {:store list-store :identity-store identity-store})
    (local map (GraphMap.GraphMap {:graph graph :id "graph-view-list-islands"}))
    (local item (string-store:create-entity {:id "item-a" :value "A"}))
    (local item-b (string-store:create-entity {:id "item-b" :value "B"}))
    (local unrelated (string-store:create-entity {:id "unrelated" :value "Unrelated"}))
    (local list (list-store:create-entity {:id "list"
                                           :name "List"
                                           :items [(.. "string-entity:" item.id)
                                                   (.. "string-entity:" item-b.id)]}))
    (local list-key (.. "list-entity:" list.id))
    (local item-key (.. "string-entity:" item.id))
    (local second-item-key (.. "string-entity:" item-b.id))
    (local unrelated-key (.. "string-entity:" unrelated.id))
    (map:load-by-key list-key)
    (map:load-by-key item-key)
    (map:load-by-key second-item-key)
    (map:load-by-key unrelated-key)
    (when options.restore-state
        (map:restore-state options.restore-state))
    (when options.persisted-positions
        (local graph-dir (fs.join-path (fs.join-path (fs.join-path dir "graph") "maps") "graph-view-list-islands"))
        (fs.create-dirs graph-dir)
        (JsonUtils.write-json! (fs.join-path graph-dir "metadata.json")
                               {:positions options.persisted-positions}))
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
                (f {:graph graph
                    :map map
                     :view view
                      :movables movables
                      :string-store string-store
                      :list-store list-store
                       :dir dir
                     :list-key list-key
                     :item-key item-key
                     :second-item-key second-item-key
                     :unrelated-key unrelated-key}))))
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

(fn graph-view-island-removal-keeps-default-unpinned-members-unpinned []
    (with-fixture {:island (island-record {})}
        check-island-removal-keeps-default-unpinned-members-unpinned))

(fn graph-view-preserves-expanded-member-pin-after-island-removal []
    (with-fixture {:island (island-record {})}
        check-preserves-expanded-member-pin-after-island-removal))

(fn graph-view-unpins-expanded-member-after-island-removal-and-collapse []
    (with-fixture {:island (island-record {})}
        check-unpins-expanded-member-after-island-removal-and-collapse))

(fn graph-view-clears-expanded-pin-reason-before-later-island-removal []
    (with-fixture {}
        check-clears-expanded-pin-reason-before-later-island-removal))

(fn graph-view-removes-island-member-node-without-pin-cleanup-error []
    (with-fixture {:island (island-record {})}
        check-removes-island-member-node-without-pin-cleanup-error))

(fn graph-view-snaps-island-member-back-after-drag-end []
    (with-fixture {:island (island-record {:state {:position (glm.vec3 5 6 0)
                                                   :spacing 7}})}
        check-snaps-island-member-back-after-drag-end))

(fn graph-view-list-created-island-preserves-body-position-after-unrelated-drag-end []
    (with-list-fixture
        check-list-created-island-preserves-body-position-after-unrelated-drag-end))

(fn graph-view-ordered-list-aggregate-record-exposes-center-force-anchor []
    (check-ordered-list-aggregate-record-exposes-center-force-anchor))

(fn graph-view-list-created-island-moves-as-force-layout-unit []
    (with-list-fixture check-list-created-island-moves-as-force-layout-unit))

(fn graph-view-force-moved-island-keeps-runtime-position-after-unrelated-drag-end []
    (with-list-fixture check-force-moved-island-keeps-runtime-position-after-unrelated-drag-end))
(fn graph-view-force-moved-island-flushes-body-origin-not-force-center []
    (with-list-fixture check-force-moved-island-flushes-body-origin-not-force-center))
(fn graph-view-membership-refresh-preserves-runtime-island-body []
    (with-list-fixture check-membership-refresh-preserves-runtime-island-body))
(fn graph-view-expanded-member-stays-pinned-through-island-position-flush []
    (with-list-fixture check-expanded-member-stays-pinned-through-island-position-flush))
(fn graph-view-collapsed-expanded-member-rejoins-aggregate-placement []
    (with-list-fixture check-collapsed-expanded-member-rejoins-aggregate-placement))
(fn graph-view-replacing-expanded-island-member-resyncs-aggregate-record []
    (with-list-fixture check-replacing-expanded-island-member-resyncs-aggregate-record))
(fn graph-view-adding-node-after-island-sync-keeps-public-indices-unique []
    (with-list-fixture check-adding-node-after-island-sync-keeps-public-indices-unique))
(fn graph-view-replacing-node-after-island-sync-refreshes-layout-participant []
    (with-list-fixture check-replacing-node-after-island-sync-refreshes-layout-participant))

(fn graph-view-capture-fails-visibly-when-moved-island-cannot-flush-position []
    (with-list-fixture check-capture-fails-visibly-when-moved-island-cannot-flush-position))

(fn graph-view-restored-old-format-list-island-uses-member-fallback-after-drag-end []
    (with-list-fixture
        {:restore-state {:nodes ["list-entity:list" "string-entity:item-a" "string-entity:unrelated"]
                         :edges []
                         :islands [{:id "ordered-list:list"
                                    :kind "ordered-list"
                                    :members ["string-entity:item-a"]
                                    :state {:list-key "list-entity:list"
                                            :spacing 24}}]}
         :persisted-positions {"list-entity:list" [24 0 0]
                                "string-entity:item-a" [300 400 0]
                                 "string-entity:unrelated" [-100 -100 0]}}
        check-restored-old-format-list-island-uses-member-fallback-after-drag-end))

(fn graph-view-alt-dragging-second-island-member-moves-whole-island-on-drag-end []
    (with-list-fixture check-alt-dragging-second-island-member-moves-whole-island-on-drag-end))

(fn graph-view-alt-drag-end-clears-state-before-visible-update-failure []
    (with-list-fixture check-alt-drag-end-clears-state-before-visible-update-failure))

(fn graph-view-layout-converts-force-center-to-island-body-position []
    (check-graph-view-layout-converts-force-center-to-island-body-position))

(fn graph-view-layout-compares-force-anchor-against-snapshot []
    (check-graph-view-layout-compares-force-anchor-against-snapshot))

(fn graph-view-layout-routes-member-edge-through-island-force-anchor []
    (check-graph-view-layout-routes-member-edge-through-island-force-anchor))

(fn graph-view-empty-island-sync-does-not-start-force-layout []
    (with-fixture {:keys []}
        check-empty-island-sync-does-not-start-force-layout))

(table.insert tests {:name "GraphView applies ordered-list island positions"
                     :fn graph-view-applies-ordered-list-island-positions})
(table.insert tests {:name "GraphView updates island layout when island changes"
                     :fn graph-view-updates-island-layout-when-island-changes})
(table.insert tests {:name "GraphView refreshes labels after island update"
                     :fn graph-view-refreshes-labels-after-island-update})
(table.insert tests {:name "GraphView fails visibly for missing island presenter"
                     :fn graph-view-fails-visibly-for-missing-island-presenter})
(table.insert tests {:name "GraphView island removal keeps default unpinned members unpinned"
                     :fn graph-view-island-removal-keeps-default-unpinned-members-unpinned})
(table.insert tests {:name "GraphView preserves expanded member pin after island removal"
                     :fn graph-view-preserves-expanded-member-pin-after-island-removal})
(table.insert tests {:name "GraphView unpins expanded member after island removal and collapse"
                     :fn graph-view-unpins-expanded-member-after-island-removal-and-collapse})
(table.insert tests {:name "GraphView clears expanded pin reason before later island removal"
                     :fn graph-view-clears-expanded-pin-reason-before-later-island-removal})
(table.insert tests {:name "GraphView removes island member node without pin cleanup error"
                     :fn graph-view-removes-island-member-node-without-pin-cleanup-error})
(table.insert tests {:name "GraphView snaps island member back after drag end"
                     :fn graph-view-snaps-island-member-back-after-drag-end})
(table.insert tests {:name "GraphView list-created island preserves body position after unrelated drag end"
                      :fn graph-view-list-created-island-preserves-body-position-after-unrelated-drag-end})
(table.insert tests {:name "GraphView ordered-list aggregate record exposes center force anchor"
                     :fn graph-view-ordered-list-aggregate-record-exposes-center-force-anchor})
(table.insert tests {:name "GraphView list-created island moves as force-layout unit" :fn graph-view-list-created-island-moves-as-force-layout-unit})
(table.insert tests {:name "GraphView force-moved island keeps runtime position after unrelated drag end" :fn graph-view-force-moved-island-keeps-runtime-position-after-unrelated-drag-end})
(table.insert tests {:name "GraphView force-moved island flushes body origin not force center" :fn graph-view-force-moved-island-flushes-body-origin-not-force-center})
(table.insert tests {:name "GraphView membership refresh preserves runtime island body" :fn graph-view-membership-refresh-preserves-runtime-island-body})
(table.insert tests {:name "GraphView expanded member stays pinned through island position flush" :fn graph-view-expanded-member-stays-pinned-through-island-position-flush})
(table.insert tests {:name "GraphView collapsed expanded member rejoins aggregate placement" :fn graph-view-collapsed-expanded-member-rejoins-aggregate-placement})
(table.insert tests {:name "GraphView replacing expanded island member resyncs aggregate record" :fn graph-view-replacing-expanded-island-member-resyncs-aggregate-record})
(table.insert tests {:name "GraphView adding node after island sync keeps public indices unique" :fn graph-view-adding-node-after-island-sync-keeps-public-indices-unique})
(table.insert tests {:name "GraphView replacing node after island sync refreshes layout participant" :fn graph-view-replacing-node-after-island-sync-refreshes-layout-participant})
(table.insert tests {:name "GraphView capture fails visibly when moved island cannot flush position"
                     :fn graph-view-capture-fails-visibly-when-moved-island-cannot-flush-position})
(table.insert tests {:name "GraphView restored old-format list island uses member fallback after unrelated drag end"
                     :fn graph-view-restored-old-format-list-island-uses-member-fallback-after-drag-end})
(table.insert tests {:name "GraphView alt-dragging second island member moves whole island on drag end"
                     :fn graph-view-alt-dragging-second-island-member-moves-whole-island-on-drag-end})
(table.insert tests {:name "GraphView alt drag end clears state before visible update failure"
                       :fn graph-view-alt-drag-end-clears-state-before-visible-update-failure})
(table.insert tests {:name "GraphViewLayout converts island force center to body position"
                     :fn graph-view-layout-converts-force-center-to-island-body-position})
(table.insert tests {:name "GraphViewLayout compares island force anchor against snapshot"
                     :fn graph-view-layout-compares-force-anchor-against-snapshot})
(table.insert tests {:name "GraphViewLayout routes island member edge through force anchor"
                     :fn graph-view-layout-routes-member-edge-through-island-force-anchor})
(table.insert tests {:name "GraphView empty island sync does not start force layout"
                      :fn graph-view-empty-island-sync-does-not-start-force-layout})

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "graph-view-islands" :tests tests})))

{:name "graph-view-islands"
 :tests tests
 :main main}
